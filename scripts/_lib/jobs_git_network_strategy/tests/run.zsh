#!/bin/zsh
# 脚本自述：
# - 脚本名称：Jobs Git 网络策略离线验证。
# - 核心用途：以隔离夹具验证原生优先、单次代理回退与输出/凭据边界。
# - 影响范围：仅使用临时目录和临时 bare 仓库，不推送任何网络仓库。
# - 运行提示：这是可重复的离线测试入口，不更改用户 Git 或系统代理配置。
# shell: zsh

typeset -g TEST_ROOT='' WRAPPER='' TEST_TEMP='' TEST_LIBRARY=''
typeset -g CASE_DIR='' CASE_RESULT=0 PASSED=0 FAILED=0
typeset -g FIRST_STATUS=128 SECOND_STATUS=0 FIRST_STDOUT='' FIRST_STDERR=''
typeset -g SECOND_STDOUT='' SECOND_STDERR='' TARGET_FIXTURE='https://git.example.test/team/project.git'
typeset -g SYSTEM_SNAPSHOT='' UPDATED_SNAPSHOT='' PROBE_FAILURE_PORT='' EXPLICIT_PROXY=0
typeset -g PUSH_CALLS=0 CONFIG_PROXY_EMPTY=0
typeset -g FIXTURE_PROXY_ENV_NAME='' FIXTURE_PROXY_ENV_VALUE='' FIXTURE_NO_PROXY=''
typeset -g HTTP_FIXTURE_PID=''
typeset -ga FIXTURE_ARGS

# 清理整个测试专属的临时目录，不触及用户仓库。
cleanup_tests() {
    if [[ -n "$HTTP_FIXTURE_PID" ]]; then
        kill -TERM "$HTTP_FIXTURE_PID" 2>/dev/null
        wait "$HTTP_FIXTURE_PID" 2>/dev/null
        HTTP_FIXTURE_PID=''
    fi
    [[ -n "$TEST_TEMP" && -d "$TEST_TEMP" ]] || return 0
    /bin/rm -f "${TEST_TEMP}/library.zsh"
    # 全部路径均来自本测试自身的 mktemp，逐文件删除避免宽泛清理。
    /usr/bin/find "$TEST_TEMP" -type f -delete
    /usr/bin/find "$TEST_TEMP" -type l -delete
    /usr/bin/find "$TEST_TEMP" -depth -type d -empty -delete
}
# 测试进程结束后回收自己创建的所有临时文件。
TRAPEXIT() {
    cleanup_tests
}
# 人工中断时立即退出，避免继续后续用例。
TRAPINT() {
    exit 130
}
# 终止测试后保留系统和业务仓库不变。
TRAPTERM() {
    exit 143
}
# 准备函数库；只去掉正式入口调用，测试仍使用同一份生产函数。
prepare_test_suite() {
    setopt NO_NOMATCH
    TEST_ROOT="${${(%):-%x}:A:h}"
    WRAPPER="${TEST_ROOT:h}/bin/git"
    TEST_TEMP="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-git-network-tests.XXXXXXXX")" || exit 1
    TEST_LIBRARY="${TEST_TEMP}/library.zsh"
    /usr/bin/sed '$d' "$WRAPPER" > "$TEST_LIBRARY"
}
# 生成可在测试中动态替换的系统代理快照。
proxy_snapshot() {
    local port="$1"
    print -r -- "<dictionary> {
  HTTPSEnable : 1
  HTTPSProxy : 127.0.0.1
  HTTPSPort : ${port}
  HTTPEnable : 1
  HTTPProxy : 127.0.0.1
  HTTPPort : ${port}
}"
}
# 为每项验证建立独立的 HOME、诊断、输出和参数记录。
reset_case() {
    CASE_DIR="${TEST_TEMP}/case-$1"
    /bin/mkdir -p "${CASE_DIR}/home" "${CASE_DIR}/tmp" "${CASE_DIR}/calls"
    FIRST_STATUS=128
    SECOND_STATUS=0
    FIRST_STDOUT=''
    FIRST_STDERR="fatal: unable to access 'https://git.example.test/team/project.git/': Failed to connect to git.example.test port 443 after 4000 ms: Couldn't connect to server"
    SECOND_STDOUT=''
    SECOND_STDERR=''
    TARGET_FIXTURE='https://git.example.test/team/project.git'
    SYSTEM_SNAPSHOT="$(proxy_snapshot 8101)"
    UPDATED_SNAPSHOT=''
    PROBE_FAILURE_PORT=''
    EXPLICIT_PROXY=0
    CONFIG_PROXY_EMPTY=0
    FIXTURE_PROXY_ENV_NAME=''
    FIXTURE_PROXY_ENV_VALUE=''
    FIXTURE_NO_PROXY=''
    FIXTURE_ARGS=( push origin main:main )
}
# 记录 push 原始参数及次序，元数据命令返回固定的只读夹具。
fixture_real_git() {
    local argument='' command='' index=1
    for argument in "$@"; do
        case "$argument" in
            push|--version|config|remote|symbolic-ref)
                command="$argument"
                break
                ;;
        esac
        (( index++ ))
    done
    case "$command" in
        push)
            (( PUSH_CALLS++ ))
            printf '%s\0' "$@" > "${CASE_DIR}/calls/${PUSH_CALLS}.argv"
            if (( PUSH_CALLS == 1 )); then
                [[ -n "$UPDATED_SNAPSHOT" ]] && SYSTEM_SNAPSHOT="$UPDATED_SNAPSHOT"
                [[ -n "$FIRST_STDOUT" ]] && print -rn -- "$FIRST_STDOUT"
                [[ -n "$FIRST_STDERR" ]] && print -rn -u2 -- "$FIRST_STDERR"
                return "$FIRST_STATUS"
            fi
            [[ -n "$SECOND_STDOUT" ]] && print -rn -- "$SECOND_STDOUT"
            [[ -n "$SECOND_STDERR" ]] && print -rn -u2 -- "$SECOND_STDERR"
            return "$SECOND_STATUS"
            ;;
        --version)
            print -r -- 'git version fixture-1.0'
            return 0
            ;;
        symbolic-ref)
            print -r -- main
            return 0
            ;;
        config)
            if (( EXPLICIT_PROXY )) && [[ "$*" == *'--get-urlmatch http.proxy '* ]]; then
                (( CONFIG_PROXY_EMPTY )) || print -r -- 'http://explicit.example.test:9999'
                return 0
            fi
            return 1
            ;;
        remote)
            if [[ "$*" == *'get-url --push --all '* ]]; then
                print -r -- "$TARGET_FIXTURE"
                return 0
            fi
            print -r -- origin
            return 0
            ;;
    esac
    print -u2 -r -- "unexpected fixture git invocation: $command"
    return 99
}
# 在子进程内替换外部边界，执行同一生产 main；不会调用公网 Git。
invoke_case() {
    (
        unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY
        export HOME="${CASE_DIR}/home" TMPDIR="${CASE_DIR}/tmp/"
        [[ -n "$FIXTURE_PROXY_ENV_NAME" ]] && export "${FIXTURE_PROXY_ENV_NAME}=${FIXTURE_PROXY_ENV_VALUE}"
        [[ -n "$FIXTURE_NO_PROXY" ]] && export "NO_PROXY=${FIXTURE_NO_PROXY}"
        source "$TEST_LIBRARY" || exit 99
        PUSH_CALLS=0
        real_git() {
            fixture_real_git "$@"
        }
        exec_real_git() {
            fixture_real_git "$@"
            exit $?
        }
        system_proxy_snapshot() {
            print -r -- "$SYSTEM_SNAPSHOT"
        }
        curl_head_status() {
            print -r -- "$1" >> "${CASE_DIR}/probes"
            print -r -- "$TARGET_ROOT" >> "${CASE_DIR}/probe-targets"
            if [[ -n "$PROBE_FAILURE_PORT" && "$1" == *":${PROBE_FAILURE_PORT}" ]]; then
                print -rn -- 000
                return 7
            fi
            print -rn -- 200
            return 0
        }
        main "${FIXTURE_ARGS[@]}"
    ) > "${CASE_DIR}/stdout" 2> "${CASE_DIR}/stderr"
    CASE_RESULT=$?
}
# 比较状态并给出简洁的失败定位。
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
# 验证原始参数数组逐项一致，不用有损字符串拼接替代。
assert_argv() {
    local file="$1" label="$2" item=''
    shift 2
    local -a expected=( "$@" ) actual=()
    if [[ -f "$file" ]]; then
        while IFS= read -r -d $'\0' item; do
            actual+=( "$item" )
        done < "$file"
    fi
    assert_equal "${#actual}" "${#expected}" "${label} argc" || return 1
    local index=0
    for (( index = 1; index <= ${#expected}; index++ )); do
        assert_equal "${actual[index]}" "${expected[index]}" "${label} argument-${index}" || return 1
    done
    return 0
}
# 成功路径只能执行一次，stdout 字节保持原样。
test_native_success() {
    reset_case native-success
    FIRST_STATUS=0
    FIRST_STDERR='native success'
    FIRST_STDOUT=$'native stdout\nwithout-final-newline'
    invoke_case
    assert_equal "$CASE_RESULT" 0 native-success-exit
    assert_argv "${CASE_DIR}/calls/1.argv" native-success "${FIXTURE_ARGS[@]}"
    assert_equal "$(<"${CASE_DIR}/stdout")" "$FIRST_STDOUT" native-stdout
    assert_equal "$([[ -e "${CASE_DIR}/calls/2.argv" ]] && print yes || print no)" no native-no-retry
}
# 首次连接失败后读取更新过的系统端口，保留原始参数作用域与次序。
test_dynamic_proxy_and_arguments() {
    reset_case dynamic-proxy
    UPDATED_SNAPSHOT="$(proxy_snapshot 9123)"
    FIXTURE_ARGS=( --no-optional-locks -c color.diff=false -ccore.quotepath=false -C '/tmp/repo with spaces' --git-dir=.git --work-tree '/tmp/work tree' --exec-path=/usr/libexec/git-core --config-env=credential.helper=JOBS_TEST_CREDENTIAL push -v origin 'refs/heads/main:refs/heads/main' )
    invoke_case
    assert_equal "$CASE_RESULT" 0 proxy-success-exit
    assert_argv "${CASE_DIR}/calls/1.argv" original-arguments "${FIXTURE_ARGS[@]}"
    assert_argv "${CASE_DIR}/calls/2.argv" retry-arguments \
        --no-optional-locks -c color.diff=false -ccore.quotepath=false -C '/tmp/repo with spaces' --git-dir=.git --work-tree '/tmp/work tree' --exec-path=/usr/libexec/git-core --config-env=credential.helper=JOBS_TEST_CREDENTIAL \
        -c http.proxy=http://127.0.0.1:9123 -c remote.origin.proxy=http://127.0.0.1:9123 push -v origin 'refs/heads/main:refs/heads/main'
    assert_equal "$(<"${CASE_DIR}/probes")" 'http://127.0.0.1:9123' current-port-and-dedup
}
# 没有系统代理时原失败码必须完整返回。
test_no_proxy() {
    reset_case no-proxy
    SYSTEM_SNAPSHOT='<dictionary> {}'
    invoke_case
    assert_equal "$CASE_RESULT" 128 no-proxy-exit
    assert_equal "$([[ -e "${CASE_DIR}/calls/2.argv" ]] && print yes || print no)" no no-proxy-no-retry
}
# 认证、分支冲突、证书、未知中断、进度或 stdout 均阻止重放。
test_unsafe_failures() {
    local label='' diagnostic=''
    local -a labels=( authentication nonff remote-rejected certificate disconnect progress mixed-failure )
    local -a diagnostics=(
        'fatal: Authentication failed for https://git.example.test'
        '! [rejected] main -> main (non-fast-forward)'
        '! [remote rejected] main -> main (hook declined)'
        'fatal: unable to access https://git.example.test: SSL certificate problem'
        'fatal: the remote end hung up unexpectedly'
        $'Writing objects: 100%\nfatal: unable to access https://git.example.test: Failed to connect to git.example.test'
        $'remote: update accepted\nfatal: unable to access https://git.example.test: Failed to connect to git.example.test'
    )
    local index=0
    for (( index = 1; index <= ${#labels}; index++ )); do
        label="${labels[index]}"
        diagnostic="${diagnostics[index]}"
        reset_case "$label"
        FIRST_STDERR="$diagnostic"
        invoke_case
        assert_equal "$CASE_RESULT" 128 "${label}-exit"
        assert_equal "$([[ -e "${CASE_DIR}/calls/2.argv" ]] && print yes || print no)" no "${label}-no-retry"
    done
    reset_case stdout-progress
    FIRST_STDOUT=$'To https://git.example.test\n*\trefs/heads/main:refs/heads/main\t[new branch]'
    invoke_case
    assert_equal "$([[ -e "${CASE_DIR}/calls/2.argv" ]] && print yes || print no)" no stdout-no-replay
}
# 重试失败时只返回该退出码，绝不尝试第二个可用代理。
test_one_retry_only() {
    reset_case second-failure
    SYSTEM_SNAPSHOT="$(proxy_snapshot 8101)
SOCKSEnable : 1
SOCKSProxy : localhost
SOCKSPort : 8102"
    SECOND_STATUS=73
    SECOND_STDERR='fatal: Authentication failed'
    invoke_case
    assert_equal "$CASE_RESULT" 73 second-failure-exit
    assert_equal "$([[ -e "${CASE_DIR}/calls/3.argv" ]] && print yes || print no)" no no-third-push
    assert_equal "$(<"${CASE_DIR}/probes")" 'http://127.0.0.1:8101' no-second-proxy-after-retry
}
# 探测可以跳过失效代理，实际 push 仍只能重试一次。
test_probe_candidate_order() {
    reset_case candidate-order
    SYSTEM_SNAPSHOT="$(proxy_snapshot 8101)
SOCKSEnable : 1
SOCKSProxy : localhost
SOCKSPort : 8102"
    PROBE_FAILURE_PORT=8101
    invoke_case
    assert_equal "$CASE_RESULT" 0 second-candidate-success
    assert_equal "$(<"${CASE_DIR}/probes")" $'http://127.0.0.1:8101\nsocks5h://localhost:8102' probe-priority
    assert_argv "${CASE_DIR}/calls/2.argv" socks-retry -c http.proxy=socks5h://localhost:8102 -c remote.origin.proxy=socks5h://localhost:8102 push origin main:main
}
# 非 push 保持原生 stdout，不输出策略自述或创建审计文件。
test_nonpush_passthrough() {
    reset_case version
    FIXTURE_ARGS=( --version --build-options )
    invoke_case
    assert_equal "$CASE_RESULT" 0 version-exit
    assert_equal "$(<"${CASE_DIR}/stdout")" 'git version fixture-1.0' version-stdout
    assert_equal "$(<"${CASE_DIR}/stderr")" '' version-stderr
    assert_equal "$([[ -e "${CASE_DIR}/home/Library/Logs/JobsGitNetworkStrategy/push.log" ]] && print yes || print no)" no version-no-log
}
# SSH、本地、多 URL 和不明确选项都不扩展为 HTTP 代理推送。
test_target_boundaries() {
    local label='' target=''
    local -a labels=( ssh local multiple-url )
    local -a targets=( 'git@git.example.test:team/project.git' '/tmp/local.git' $'https://git.example.test/a.git\nhttps://git.example.test/b.git' )
    local index=0
    for (( index = 1; index <= ${#labels}; index++ )); do
        label="${labels[index]}"
        target="${targets[index]}"
        reset_case "$label"
        TARGET_FIXTURE="$target"
        invoke_case
        assert_equal "$CASE_RESULT" 128 "${label}-exit"
        assert_equal "$([[ -e "${CASE_DIR}/calls/2.argv" ]] && print yes || print no)" no "${label}-no-retry"
    done
    reset_case unknown-push-option
    FIXTURE_ARGS=( push --future-option origin main )
    invoke_case
    assert_equal "$([[ -e "${CASE_DIR}/calls/2.argv" ]] && print yes || print no)" no unknown-option-no-retry
}
# 已有代理（包括显式空配置）不被自动系统代理覆盖。
test_explicit_proxy_respected() {
    local empty=0
    for empty in 0 1; do
        reset_case "explicit-proxy-${empty}"
        EXPLICIT_PROXY=1
        CONFIG_PROXY_EMPTY="$empty"
        invoke_case
        assert_equal "$CASE_RESULT" 128 "explicit-${empty}-exit"
        assert_equal "$([[ -e "${CASE_DIR}/calls/2.argv" ]] && print yes || print no)" no "explicit-${empty}-no-retry"
    done
    reset_case empty-environment-proxy
    FIXTURE_PROXY_ENV_NAME=https_proxy
    invoke_case
    assert_equal "$CASE_RESULT" 128 empty-environment-proxy-exit
    assert_equal "$([[ -e "${CASE_DIR}/calls/2.argv" ]] && print yes || print no)" no empty-environment-proxy-no-retry
}
# 系统域名例外、简单主机、CIDR 和 NO_PROXY 都不能被自动代理扩大覆盖。
test_bypass_rules() {
    local rule='' target='' index=0
    local -a labels=( wildcard-domain exact-domain ipv4-cidr ipv6-cidr simple-host no-proxy )
    local -a rules=( '*.example.test' 'git.example.test' '127.0/8' '::1/128' '' '' )
    local -a targets=(
        'https://git.example.test/team.git' 'https://git.example.test/team.git'
        'http://127.0.0.2/team.git' 'http://[::1]/team.git'
        'https://intranet/team.git' 'https://git.example.test/team.git'
    )
    for (( index = 1; index <= ${#labels}; index++ )); do
        reset_case "bypass-${labels[index]}"
        TARGET_FIXTURE="${targets[index]}"
        rule="${rules[index]}"
        SYSTEM_SNAPSHOT+=$'\n'"ExceptionsList : <array> {
    0 : ${rule}
}"
        [[ "${labels[index]}" == simple-host ]] && SYSTEM_SNAPSHOT+=$'\nExcludeSimpleHostnames : 1'
        [[ "${labels[index]}" == no-proxy ]] && FIXTURE_NO_PROXY='.example.test'
        invoke_case
        assert_equal "$CASE_RESULT" 128 "${labels[index]}-bypass-exit"
        assert_equal "$([[ -e "${CASE_DIR}/calls/2.argv" ]] && print yes || print no)" no "${labels[index]}-bypass-no-retry"
        assert_equal "$([[ -e "${CASE_DIR}/probes" ]] && print yes || print no)" no "${labels[index]}-bypass-no-probe"
    done
}
# 审计和探测不含凭据、查询参数、仓库路径或原始输出，临时诊断退出后清空。
test_secret_and_cleanup_boundaries() {
    reset_case secret-boundaries
    TARGET_FIXTURE='https://user:fixture-secret@git.example.test/team/private.git?token=query-secret'
    FIRST_STDERR="fatal: unable to access '${TARGET_FIXTURE}': Failed to connect to git.example.test port 443"
    SECOND_STDOUT='second-stdout-secret'
    SECOND_STDERR='second-stderr-secret'
    invoke_case
    assert_equal "$CASE_RESULT" 0 secret-case-success
    local audit="${CASE_DIR}/home/Library/Logs/JobsGitNetworkStrategy/push.log"
    local leaked=no
    /usr/bin/grep -Eiq 'fixture-secret|query-secret|private.git|second-stdout-secret|second-stderr-secret|user:' "$audit" && leaked=yes
    assert_equal "$leaked" no secret-audit
    assert_equal "$(<"${CASE_DIR}/probe-targets")" 'https://git.example.test/' credential-free-probe
    assert_equal "$(<"${CASE_DIR}/stdout")" second-stdout-secret retry-stdout
    assert_equal "$(/usr/bin/find "${CASE_DIR}/tmp" -mindepth 1 -print)" '' diagnostics-cleaned
    assert_equal "$(/usr/bin/stat -f '%Lp' "$audit")" 600 private-audit
}
# 默认 remote、DNS 失败和 IPv6 URL 均沿用同一严格回退路径。
test_default_dns_and_ipv6() {
    reset_case default-dns
    FIXTURE_ARGS=( push )
    FIRST_STDERR='fatal: unable to access https://git.example.test: Could not resolve host: git.example.test'
    invoke_case
    assert_equal "$CASE_RESULT" 0 dns-success
    assert_argv "${CASE_DIR}/calls/2.argv" default-remote-retry -c http.proxy=http://127.0.0.1:8101 -c remote.origin.proxy=http://127.0.0.1:8101 push
    reset_case ipv6
    TARGET_FIXTURE='https://[::1]:8443/team.git'
    invoke_case
    assert_equal "$CASE_RESULT" 0 ipv6-exit
    assert_equal "$(<"${CASE_DIR}/probe-targets")" 'https://[::1]:8443/' ipv6-probe
}
# 用系统 Git 在临时 bare 仓库完成真实本地 push，验证生产入口无协议包装。
test_real_local_push() {
    reset_case real-local
    local source_repo="${CASE_DIR}/source" bare_repo="${CASE_DIR}/remote.git"
    /usr/bin/git init --quiet --initial-branch=main "$source_repo" || return 1
    /usr/bin/git init --quiet --bare "$bare_repo" || return 1
    /usr/bin/git -C "$source_repo" -c user.name=Jobs -c user.email=fixture@example.test commit --quiet --allow-empty -m fixture || return 1
    /usr/bin/git -C "$source_repo" remote add origin "$bare_repo" || return 1
    HOME="${CASE_DIR}/home" TMPDIR="${CASE_DIR}/tmp/" /bin/zsh "$WRAPPER" -C "$source_repo" push origin main:main > "${CASE_DIR}/stdout" 2> "${CASE_DIR}/stderr"
    assert_equal "$?" 0 real-local-push-exit
    assert_equal "$(/usr/bin/git -C "$bare_repo" rev-parse refs/heads/main)" "$(/usr/bin/git -C "$source_repo" rev-parse HEAD)" real-local-push-head
}
# 原生 HTTP 连接真实失败后，经本地 HTTP 代理和 Git CGI 完成真实单次 push。
test_real_http_proxy_fallback() {
    reset_case real-http
    local source_repo="${CASE_DIR}/source" bare_repo="${CASE_DIR}/remote.git"
    /usr/bin/git init --quiet --initial-branch=main "$source_repo" || return 1
    /usr/bin/git init --quiet --bare "$bare_repo" || return 1
    /usr/bin/git -C "$bare_repo" config http.receivepack true || return 1
    /usr/bin/git -C "$source_repo" -c user.name=Jobs -c user.email=fixture@example.test commit --quiet --allow-empty -m http-fixture || return 1
    /usr/bin/perl "${TEST_ROOT}/http_fixture.pl" "$CASE_DIR" "${CASE_DIR}/ports" "${CASE_DIR}/requests" > "${CASE_DIR}/server.stdout" 2> "${CASE_DIR}/server.stderr" &
    HTTP_FIXTURE_PID=$!
    local guard=0
    while [[ ! -s "${CASE_DIR}/ports" ]] && (( guard < 100 )); do
        /bin/sleep 0.02
        (( guard++ ))
    done
    if [[ ! -s "${CASE_DIR}/ports" ]]; then
        assert_equal missing running http-fixture-start
        return 1
    fi
    local -a ports=( "${(@f)$(<"${CASE_DIR}/ports")}" )
    /usr/bin/git -C "$source_repo" remote add origin "http://127.0.0.1:${ports[2]}/remote.git" || return 1
    SYSTEM_SNAPSHOT="$(proxy_snapshot "${ports[1]}")"
    (
        unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY
        export HOME="${CASE_DIR}/home" TMPDIR="${CASE_DIR}/tmp/"
        source "$TEST_LIBRARY" || exit 99
        system_proxy_snapshot() {
            print -r -- "$SYSTEM_SNAPSHOT"
        }
        main -C "$source_repo" push origin main:main
    ) > "${CASE_DIR}/stdout" 2> "${CASE_DIR}/stderr"
    local push_result=$?
    kill -TERM "$HTTP_FIXTURE_PID" 2>/dev/null
    wait "$HTTP_FIXTURE_PID" 2>/dev/null
    HTTP_FIXTURE_PID=''
    assert_equal "$push_result" 0 real-http-fallback-exit
    assert_equal "$(/usr/bin/git -C "$bare_repo" rev-parse refs/heads/main 2>/dev/null)" "$(/usr/bin/git -C "$source_repo" rev-parse HEAD)" real-http-fallback-head
    local audit="${CASE_DIR}/home/Library/Logs/JobsGitNetworkStrategy/push.log"
    assert_equal "$(/usr/bin/grep -c 'mode=native .*exit=128' "$audit")" 1 real-http-native-failed-once
    assert_equal "$(/usr/bin/grep -c 'mode=proxy-retry .*exit=0' "$audit")" 1 real-http-proxy-push-once
    assert_equal "$(/usr/bin/grep -c '^HEAD /$' "${CASE_DIR}/requests")" 1 real-http-probe-once
    assert_equal "$(/usr/bin/grep -c '^POST /remote.git/git-receive-pack$' "${CASE_DIR}/requests")" 1 real-http-post-once
}
# 汇总离线测试结果并返回可供自动检查的退出码。
finish_test_suite() {
    print -r -- "Jobs Git 离线验证：${PASSED} 项通过，${FAILED} 项失败。"
    (( FAILED == 0 ))
}
# 先说明离线边界，再执行各类隔离验证。
show_test_intro() {
    print -r -- 'Jobs Git 网络策略离线验证：只使用隔离夹具和临时本地 bare 仓库，无公网推送。'
}
# 编排独立的策略验证与本地 Git 集成验证。
main() {
    show_test_intro # 先说明验证范围，不读取交互输入或修改真实配置。
    prepare_test_suite # 定位同包源码并创建隔离测试目录。
    test_native_success # 验证成功路径只执行一次且 stdout 原样保留。
    test_dynamic_proxy_and_arguments # 验证失败后动态端口发现与原始参数完整透传。
    test_no_proxy # 验证没有系统代理时保留原失败码。
    test_unsafe_failures # 验证认证、冲突、证书、进度和未知故障不自动重放。
    test_one_retry_only # 验证实际重试失败后不继续轮询。
    test_probe_candidate_order # 验证候选优先级和不可达候选跳过。
    test_nonpush_passthrough # 验证版本查询与非 push 输出兼容。
    test_target_boundaries # 验证 SSH、本地、多目标和未知参数边界。
    test_explicit_proxy_respected # 验证已有代理及显式空配置不被覆盖。
    test_bypass_rules # 验证系统例外、CIDR、简单主机与 NO_PROXY 保持旁路。
    test_secret_and_cleanup_boundaries # 验证审计脱敏和临时输出清理。
    test_default_dns_and_ipv6 # 验证默认 remote、DNS 错误和 IPv6 解析。
    test_real_local_push # 在临时 bare 仓库验证真实系统 Git 推送。
    test_real_http_proxy_fallback # 真实验证初始连接失败、代理 HEAD 与 smart HTTP 单次推送。
    finish_test_suite # 输出汇总并传播测试退出码。
}

main "$@"
