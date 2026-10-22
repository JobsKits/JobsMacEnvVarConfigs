#!/bin/zsh
# 脚本自述：
# - 脚本名称：Jobs Git 动态链路本地集成验证。
# - 核心用途：用真实系统 Git 验证 URL 元数据、local 配置边界和 HTTP 业务单次执行。
# - 影响范围：只在隔离 HOME 与临时仓库中操作；HTTP 夹具只监听 loopback。
# - 运行提示：不访问公网；不改用户 Git 或系统代理；Ctrl+C 取消并清理夹具。
# shell: zsh

typeset -g INTEGRATION_ROOT='' WRAPPER='' TEST_TEMP='' TEST_LIBRARY='' HTTP_PID=''
typeset -g CASE_HOME='' CASE_DIR='' CASE_RESULT=0 PASSED=0 FAILED=0 HTTP_DIR=''
typeset -g HTTP_DIRECT_URL='' HTTP_PROXY_URL='' HTTP_SNAPSHOT='' SOURCE_HEAD=''
typeset -g CURRENT_CWD='' CURRENT_SNAPSHOT='' OUTPUT_LABEL=''

# 停止自己启动的 loopback 服务后只删除专属临时目录。
cleanup_integration() {
    if [[ -n "$HTTP_PID" ]]; then
        kill -TERM "$HTTP_PID" 2>/dev/null
        wait "$HTTP_PID" 2>/dev/null
        HTTP_PID=''
    fi
    [[ -n "$TEST_TEMP" && -d "$TEST_TEMP" ]] || return 0
    /usr/bin/find "$TEST_TEMP" -type f -delete
    /usr/bin/find "$TEST_TEMP" -type l -delete
    /usr/bin/find "$TEST_TEMP" -depth -type d -empty -delete
}
# 正常退出和受控失败都清理本测试的服务与仓库。
TRAPEXIT() {
    cleanup_integration
}
# 人工中断时不继续后续 Git 业务。
TRAPINT() {
    exit 130
}
# 收到终止后交给退出钩子回收服务。
TRAPTERM() {
    exit 143
}
# 展示真实 Git 与网络隔离边界。
show_integration_intro() {
    print -r -- 'Jobs Git 本地集成验证：真实 /usr/bin/git + 临时 bare 仓库 + loopback HTTP CGI，无公网请求。'
    print -r -- '运行策略：非交互验证；Ctrl+C 取消；记录仅存专属临时目录，退出时清理。'
}
# 读取同包生产函数，保留正式 main 与真实 Git / curl 实现。
prepare_integration() {
    setopt NO_NOMATCH
    INTEGRATION_ROOT="${${(%):-%x}:A:h}"
    WRAPPER="${INTEGRATION_ROOT:h}/bin/git"
    TEST_TEMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-git-integration.XXXXXXXX")" || exit 1
    TEST_LIBRARY="${TEST_TEMP}/library.zsh"
    /usr/bin/sed '$d' "$WRAPPER" > "$TEST_LIBRARY"
}
# 将命令限定到专属配置与 HOME，不继承真实 Git 或代理环境。
use_isolated_environment() {
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    unset GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_SSH GIT_SSH_COMMAND
    export HOME="$CASE_HOME" TMPDIR="${CASE_DIR}/tmp/" PATH=/usr/bin:/bin:/usr/sbin:/sbin
    export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL="${CASE_HOME}/.gitconfig"
    export GIT_TERMINAL_PROMPT=0 JOBS_GIT_CONNECT_TIMEOUT=1 JOBS_GIT_PROBE_TIMEOUT=2 JOBS_GIT_ROUTE_PRIORITY=direct
}
# 为元数据或 HTTP 场景分配独立的配置和仓库目录。
reset_case() {
    CASE_DIR="${TEST_TEMP}/$1"
    CASE_HOME="${CASE_DIR}/home"
    /bin/mkdir -p "$CASE_HOME" "${CASE_DIR}/tmp" "${CASE_DIR}/desktop"
}
# 真实 Git 只在隔离环境里创建测试仓库和设置测试配置。
setup_git() {
    (
        use_isolated_environment
        /usr/bin/git "$@"
    )
}
# 比较验证结果并累计失败，报错不包含真实凭据。
assert_equal() {
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then
        (( PASSED++ ))
        return 0
    fi
    (( FAILED++ ))
    print -u2 -r -- "FAIL ${label}: expected=[$expected] actual=[$actual]"
    return 1
}
# 文件不存在表示对应动作没有发生。
read_fixture() {
    [[ -f "$1" ]] && print -rn -- "$(<"$1")"
    return 0
}
# 真实解析 URL 与有效代理，不启动任何 Git 网络业务。
invoke_resolution() {
    OUTPUT_LABEL="$1"
    CURRENT_CWD="$2"
    shift 2
    (
        use_isolated_environment
        builtin cd "$CURRENT_CWD" || exit 99
        source "$TEST_LIBRARY" || exit 99
        parse_network_invocation "$@" || exit 98
        resolve_single_http_network_target || exit 97
        print -r -- "$TARGET_ROOT"
        print -r -- "remote=${TARGET_REMOTE}"
        if has_explicit_proxy; then
            print -r -- explicit-proxy=yes
        else
            print -r -- explicit-proxy=no
        fi
    ) > "${CASE_DIR}/${OUTPUT_LABEL}.stdout" 2> "${CASE_DIR}/${OUTPUT_LABEL}.stderr"
    CASE_RESULT=$?
}
# 非仓库目录的显式 HTTP URL 也必须进入策略，而不是悄悄绕过。
test_nonrepository_metadata() {
    reset_case metadata-nonrepo
    local command=''
    for command in clone ls-remote push; do
        invoke_resolution "$command" "${CASE_DIR}/desktop" "$command" 'https://git.example.test/team.git'
        assert_equal "$CASE_RESULT" 0 "nonrepo-${command}-resolved"
        assert_equal "$(read_fixture "${CASE_DIR}/${command}.stdout")" $'https://git.example.test/\nremote='"$([[ "$command" == clone ]] && print origin)"$'\nexplicit-proxy=no' "nonrepo-${command}-target"
    done
}
# clone 位于已有仓库内时忽略父仓 local rewrite / proxy，仍保留 global 和 -c。
test_clone_configuration_scope() {
    reset_case metadata-clone-scope
    local parent_repo="${CASE_DIR}/parent repo"
    setup_git init --quiet "$parent_repo" || exit 1
    setup_git -C "$parent_repo" config url.https://parent-local.invalid/.insteadOf https://git.example.test/ || exit 1
    setup_git -C "$parent_repo" config http.proxy http://parent-local.invalid:9999 || exit 1
    setup_git -C "$parent_repo" config remote.origin.proxy http://parent-local.invalid:9999 || exit 1
    invoke_resolution clone-parent "$parent_repo" -C "$parent_repo" clone 'https://git.example.test/team.git'
    assert_equal "$CASE_RESULT" 0 clone-parent-resolved
    assert_equal "$(read_fixture "${CASE_DIR}/clone-parent.stdout")" $'https://git.example.test/\nremote=origin\nexplicit-proxy=no' clone-parent-local-ignored
    setup_git config --global url.https://global.example.test/.insteadOf fixture:// || exit 1
    invoke_resolution clone-global "$parent_repo" clone fixture://team.git
    assert_equal "$CASE_RESULT" 0 clone-global-resolved
    assert_equal "$(read_fixture "${CASE_DIR}/clone-global.stdout")" $'https://global.example.test/\nremote=origin\nexplicit-proxy=no' clone-global-rewrite-preserved
    invoke_resolution clone-command-config "$parent_repo" -c http.proxy=http://command.example.test:8999 clone 'https://git.example.test/team.git'
    assert_equal "$CASE_RESULT" 0 clone-command-config-resolved
    assert_equal "$(read_fixture "${CASE_DIR}/clone-command-config.stdout")" $'https://git.example.test/\nremote=origin\nexplicit-proxy=yes' clone-explicit-command-config-preserved
    invoke_resolution lsremote-global "${CASE_DIR}/desktop" ls-remote fixture://team.git
    assert_equal "$CASE_RESULT" 0 lsremote-global-resolved
    assert_equal "$(read_fixture "${CASE_DIR}/lsremote-global.stdout")" $'https://global.example.test/\nremote=\nexplicit-proxy=no' lsremote-global-rewrite-preserved
}
# push 的 pushInsteadOf 最长匹配与普通 insteadOf 均使用真实 Git 配置。
test_push_rewrite_metadata() {
    reset_case metadata-push-rewrite
    setup_git config --global url.https://short.example.test/.pushInsteadOf fixture:// || exit 1
    setup_git config --global url.https://long.example.test/.pushInsteadOf fixture://team/ || exit 1
    invoke_resolution push-prefix "${CASE_DIR}/desktop" push fixture://team/project.git main:main
    assert_equal "$CASE_RESULT" 0 push-longest-prefix-resolved
    assert_equal "$(read_fixture "${CASE_DIR}/push-prefix.stdout")" $'https://long.example.test/\nremote=\nexplicit-proxy=no' push-longest-prefix-selected
}
# 配置递归和多目标时透传，不扩大到自动代理其它网络目标。
test_real_recursive_metadata() {
    reset_case metadata-recursive
    local repository="${CASE_DIR}/repository" command='' key=''
    setup_git init --quiet "$repository" || exit 1
    setup_git -C "$repository" remote add origin https://git.example.test/team.git || exit 1
    for command in fetch pull push; do
        key=fetch.recurseSubmodules
        [[ "$command" != push ]] || key=push.recurseSubmodules
        setup_git -C "$repository" config "$key" true || exit 1
        invoke_resolution "${command}-recursive" "$repository" "$command" origin
        assert_equal "$CASE_RESULT" 97 "${command}-recursive-config-skipped"
        if [[ "$command" != push ]]; then
            invoke_resolution "${command}-recursive-disabled" "$repository" "$command" --no-recurse-submodules origin
            assert_equal "$CASE_RESULT" 0 "${command}-cli-no-recurse-selected"
        fi
        setup_git -C "$repository" config --unset "$key" || exit 1
    done
    setup_git -C "$repository" config fetch.all true || exit 1
    for command in fetch pull; do
        invoke_resolution "${command}-all" "$repository" "$command"
        assert_equal "$CASE_RESULT" 97 "${command}-implicit-fetch-all-skipped"
        invoke_resolution "${command}-explicit-origin" "$repository" "$command" origin
        assert_equal "$CASE_RESULT" 0 "${command}-explicit-target-overrides-fetch-all"
    done
    setup_git -C "$repository" config --unset fetch.all || exit 1
    setup_git -C "$repository" -c user.name=Jobs -c user.email=fixture@example.test commit --quiet --allow-empty -m gitlink || exit 1
    local commit="$(setup_git -C "$repository" rev-parse HEAD)"
    setup_git -C "$repository" update-index --add --cacheinfo "160000,${commit},nested-module" || exit 1
    invoke_resolution gitlink-default "$repository" fetch origin
    assert_equal "$CASE_RESULT" 97 gitlink-default-on-demand-skipped
    invoke_resolution gitlink-cli "$repository" fetch --no-recurse-submodules origin
    assert_equal "$CASE_RESULT" 0 gitlink-cli-disabled-selected
    setup_git -C "$repository" config fetch.recurseSubmodules false || exit 1
    invoke_resolution gitlink-config "$repository" fetch origin
    assert_equal "$CASE_RESULT" 0 gitlink-config-disabled-selected
}
# 创建真实本地仓库并启动仅监听 loopback 的 smart HTTP / 代理夹具。
prepare_http_fixture() {
    reset_case http-transport
    HTTP_DIR="$CASE_DIR"
    local source_repo="${CASE_DIR}/source" bare_repo="${CASE_DIR}/remote.git"
    setup_git init --quiet --initial-branch=main "$source_repo" || exit 1
    setup_git init --quiet --bare --initial-branch=main "$bare_repo" || exit 1
    setup_git -C "$source_repo" -c user.name=Jobs -c user.email=fixture@example.test commit --quiet --allow-empty -m seed || exit 1
    setup_git -C "$source_repo" push --quiet "$bare_repo" main:main || exit 1
    setup_git -C "$bare_repo" config http.receivepack true || exit 1
    SOURCE_HEAD="$(setup_git -C "$source_repo" rev-parse HEAD)"
    (
        use_isolated_environment
        exec /usr/bin/perl "${INTEGRATION_ROOT}/http_fixture.pl" "$CASE_DIR" "${CASE_DIR}/ports" "${CASE_DIR}/requests"
    ) > "${CASE_DIR}/server.stdout" 2> "${CASE_DIR}/server.stderr" &
    HTTP_PID=$!
    local guard=0
    while [[ ! -s "${CASE_DIR}/ports" ]] && (( guard < 100 )); do
        /bin/sleep 0.02
        (( guard++ ))
    done
    [[ -s "${CASE_DIR}/ports" ]] || exit 1
    local -a ports=( "${(@f)$(<"${CASE_DIR}/ports")}" )
    HTTP_DIRECT_URL="http://127.0.0.1:${ports[1]}/remote.git"
    HTTP_PROXY_URL="http://127.0.0.1:${ports[2]}/remote.git"
    HTTP_SNAPSHOT="<dictionary> {
  HTTPEnable : 1
  HTTPProxy : 127.0.0.1
  HTTPPort : ${ports[1]}
}"
}
# 真实 main、真实 curl 和真实 Git；仅当前系统代理快照使用本地夹具。
invoke_http() {
    OUTPUT_LABEL="$1"
    CURRENT_CWD="$2"
    CURRENT_SNAPSHOT="$3"
    shift 3
    (
        use_isolated_environment
        builtin cd "$CURRENT_CWD" || exit 99
        source "$TEST_LIBRARY" || exit 99
        # 只替换系统快照，禁止读取用户实时系统代理。
        system_proxy_snapshot() {
            print -r -- snapshot >> "${HTTP_DIR}/${OUTPUT_LABEL}.snapshots"
            print -r -- "$CURRENT_SNAPSHOT"
        }
        main "$@"
    ) > "${HTTP_DIR}/${OUTPUT_LABEL}.stdout" 2> "${HTTP_DIR}/${OUTPUT_LABEL}.stderr"
    CASE_RESULT=$?
}
# 直连 ls-remote 和非仓库 clone 都真实经过策略，且代理参数不会落盘。
test_http_read_commands() {
    local clone_repo="${HTTP_DIR}/cloned repo"
    invoke_http lsremote "${HTTP_DIR}/desktop" '<dictionary> {}' ls-remote "$HTTP_DIRECT_URL" HEAD
    assert_equal "$CASE_RESULT" 0 http-lsremote-exit
    assert_equal "$(read_fixture "${HTTP_DIR}/lsremote.stdout")" "${SOURCE_HEAD}"$'\tHEAD' http-lsremote-head
    assert_equal "$(read_fixture "${HTTP_DIR}/lsremote.snapshots")" '' http-direct-no-system-proxy-query
    invoke_http clone "${HTTP_DIR}/desktop" "$HTTP_SNAPSHOT" clone --quiet "$HTTP_PROXY_URL" "$clone_repo"
    assert_equal "$CASE_RESULT" 0 http-fallback-clone-exit
    assert_equal "$(setup_git -C "$clone_repo" rev-parse HEAD 2>/dev/null)" "$SOURCE_HEAD" http-fallback-clone-head
    assert_equal "$(read_fixture "${HTTP_DIR}/clone.snapshots")" snapshot http-fallback-clone-live-proxy
    setup_git -C "$clone_repo" config --get-urlmatch http.proxy "$HTTP_PROXY_URL" > "${HTTP_DIR}/persisted-proxy" 2>/dev/null
    assert_equal "$?" 1 http-clone-proxy-not-persisted
    assert_equal "$(read_fixture "${HTTP_DIR}/persisted-proxy")" '' http-clone-no-proxy-value
}
# 拉取远端新增提交，证明代理可用于实际 Git 对象传输。
test_http_fetch() {
    local clone_repo="${HTTP_DIR}/cloned repo"
    setup_git -C "${HTTP_DIR}/source" -c user.name=Jobs -c user.email=fixture@example.test commit --quiet --allow-empty -m upstream || exit 1
    setup_git -C "${HTTP_DIR}/source" push --quiet "${HTTP_DIR}/remote.git" main:main || exit 1
    SOURCE_HEAD="$(setup_git -C "${HTTP_DIR}/source" rev-parse HEAD)"
    invoke_http fetch "$clone_repo" "$HTTP_SNAPSHOT" fetch --quiet origin main
    assert_equal "$CASE_RESULT" 0 http-fallback-fetch-exit
    assert_equal "$(setup_git -C "$clone_repo" rev-parse FETCH_HEAD 2>/dev/null)" "$SOURCE_HEAD" http-fallback-fetch-head
    assert_equal "$(read_fixture "${HTTP_DIR}/fetch.snapshots")" snapshot http-fallback-fetch-live-proxy
    setup_git -C "$clone_repo" merge --quiet --ff-only FETCH_HEAD || exit 1
}
# 一次真实 push 对应一次 receive-pack POST，审计中没有业务重放。
test_http_push_once() {
    local clone_repo="${HTTP_DIR}/cloned repo"
    setup_git -C "$clone_repo" -c user.name=Jobs -c user.email=fixture@example.test commit --quiet --allow-empty -m downstream || exit 1
    SOURCE_HEAD="$(setup_git -C "$clone_repo" rev-parse HEAD)"
    invoke_http push "$clone_repo" "$HTTP_SNAPSHOT" push --quiet origin main:main
    assert_equal "$CASE_RESULT" 0 http-fallback-push-exit
    assert_equal "$(setup_git -C "${HTTP_DIR}/remote.git" rev-parse refs/heads/main 2>/dev/null)" "$SOURCE_HEAD" http-fallback-push-head
    assert_equal "$(/usr/bin/grep -c '^POST /remote.git/git-receive-pack$' "${HTTP_DIR}/requests")" 1 http-push-receive-pack-once
    local audit="${CASE_HOME}/Library/Logs/JobsGitNetworkStrategy/push.log"
    assert_equal "$(/usr/bin/grep -c 'mode=direct .*exit=0' "$audit")" 1 http-one-direct-business
    assert_equal "$(/usr/bin/grep -c 'mode=proxy .*exit=0' "$audit")" 3 http-three-proxy-businesses
    assert_equal "$(/usr/bin/grep -c '^HEAD /$' "${HTTP_DIR}/requests")" 4 http-one-reachable-head-per-command
}
# 真实本地 push 直接透传，不读取代理或建立网络探测。
test_real_local_push() {
    local clone_repo="${HTTP_DIR}/cloned repo" local_remote="${HTTP_DIR}/local remote.git"
    setup_git init --quiet --bare "$local_remote" || exit 1
    invoke_http local-push "$clone_repo" '<dictionary> {}' push --quiet "$local_remote" main:main
    assert_equal "$CASE_RESULT" 0 local-push-passthrough-exit
    assert_equal "$(setup_git -C "$local_remote" rev-parse refs/heads/main 2>/dev/null)" "$SOURCE_HEAD" local-push-passthrough-head
    assert_equal "$(read_fixture "${HTTP_DIR}/local-push.snapshots")" '' local-push-no-system-proxy-query
    assert_equal "$(/usr/bin/grep -c '^HEAD /$' "${HTTP_DIR}/requests")" 4 local-push-no-network-probe
}
# 汇总真实元数据和本地 HTTP 集成验证结果。
finish_integration() {
    print -r -- "Jobs Git 本地集成验证：${PASSED} 项通过，${FAILED} 项失败。"
    (( FAILED == 0 ))
}
# 编排说明、真实配置边界及 loopback Git 业务。
main() {
    show_integration_intro # 先说明真实执行范围、取消方式和清理策略。
    prepare_integration # 建立专属临时目录并读取生产函数。
    test_nonrepository_metadata # 验证非仓库 cwd 的 HTTP URL 可以被识别。
    test_clone_configuration_scope # 验证 clone 不继承父仓 local 配置。
    test_push_rewrite_metadata # 验证 pushInsteadOf 的最长前缀展开。
    test_real_recursive_metadata # 验证递归子模块配置守住自动代理边界。
    prepare_http_fixture # 创建临时仓库并监听 loopback HTTP 服务。
    test_http_read_commands # 验证真实直连 ls-remote 和代理 clone。
    test_http_fetch # 验证代理 fetch 能取得真实新增提交。
    test_http_push_once # 验证真实 push 只发起一次写入业务。
    test_real_local_push # 验证本地 push 原生透传且不读取代理。
    finish_integration # 输出通过数并保留失败退出码。
}

main "$@"
