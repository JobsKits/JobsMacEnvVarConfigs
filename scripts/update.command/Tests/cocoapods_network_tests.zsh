#!/bin/zsh
# 脚本自述：
# - 脚本名称：cocoapods_network_tests.zsh
# - 核心用途：隔离验证 CocoaPods 选源、刷新和包管理器升级分支。
# - 影响范围：仅创建专属临时目录；curl、git、pod、brew、gem 均使用假命令。
# - 运行提示：自动执行回归，不联网、不安装、不升级；按 Ctrl+C 可取消。

TEST_SCRIPT_DIR="${${(%):-%x}:A:h}"
TEST_UPDATE_SCRIPT="${TEST_SCRIPT_DIR:h}/update.command"
TEST_ROOT=''
TEST_PASSED=0
TEST_FAILED=0
TEST_TOTAL=0

# 说明隔离边界，避免把模拟成功误认为真实网络验收。
show_test_intro() {
  print -r -- 'CocoaPods 网络与升级隔离回归'
  print -r -- '仅运行临时目录中的假命令，不联网、不安装、不升级。按 Ctrl+C 可取消。'
}
# 回收测试自建进程，防止被测超时逻辑回归后留下挂起夹具。
terminate_mock_processes() {
  local process_id
  [[ -n "$TEST_ROOT" && -f "$TEST_ROOT/processes" ]] || return 0
  while IFS= read -r process_id; do
    [[ "$process_id" == <-> && "$process_id" -gt 1 ]] || continue
    kill -KILL "$process_id" 2>/dev/null || true
  done < "$TEST_ROOT/processes"
}
# 只删除本测试生成的临时目录。
cleanup_tests() {
  terminate_mock_processes
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" && "${TEST_ROOT:t}" == jobs-update-tests.* ]]; then
    /bin/rm -r -- "$TEST_ROOT"
  fi
}
# 创建模拟命令，真实网络和包管理器命令不会进入执行链。
create_mock_commands() {
  /bin/mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/runtime" "$TEST_ROOT/gems"
  /bin/cat > "$TEST_ROOT/bin/curl" <<'MOCK_CURL'
#!/bin/zsh
setopt NO_NOMATCH
local target='' url='' argument candidate mode duration delay
print -r -- "curl|${(j: :)@}" >> "$MOCK_ROOT/calls"
while (( $# > 0 )); do
  argument="$1"
  shift
  case "$argument" in
    --output|-o) target="$1"; shift ;;
    --connect-timeout|--max-time|--write-out) shift ;;
    --head|-I) print -r -- 'HEAD request is forbidden' >&2; exit 97 ;;
    https://*) url="$argument" ;;
  esac
done
[[ "$url" == *'/Specs/a/7/5/AFNetworking/4.0.1/AFNetworking.podspec.json' ]] || exit 96
candidate=cdn
[[ "$url" == https://raw.githubusercontent.com/* ]] && candidate=git
print -r -- "$candidate" >> "$MOCK_ROOT/probes"
: > "$MOCK_ROOT/$candidate.started"
if [[ "${MOCK_PROBE_BARRIER:-0}" == 1 ]]; then
  local other=git attempt
  [[ "$candidate" == git ]] && other=cdn
  for attempt in {1..30}; do
    [[ -f "$MOCK_ROOT/$other.started" ]] && break
    /bin/sleep 0.03
  done
  [[ -f "$MOCK_ROOT/$other.started" ]] || exit 95
fi
mode="${MOCK_CDN_MODE:-valid}"
duration="${MOCK_CDN_TIME:-1.0}"
delay="${MOCK_CDN_DELAY:-0}"
if [[ "$candidate" == git ]]; then
  mode="${MOCK_GIT_MODE:-valid}"
  duration="${MOCK_GIT_TIME:-1.0}"
  delay="${MOCK_GIT_DELAY:-0}"
fi
if [[ "$mode" == hang ]]; then
  print -r -- "$$" >> "$MOCK_ROOT/processes"
  /bin/sleep 30 &
  print -r -- "$!" >> "$MOCK_ROOT/processes"
  wait
  exit 94
fi
[[ "$delay" != 0 ]] && /bin/sleep "$delay"
case "$mode" in
  fail) exit 28 ;;
  html) print -r -- '<html>"name":"AFNetworking","version":"4.0.1"</html>' > "$target" ;;
  malformed) print -r -- '{"name":"AFNetworking","version":"4.0.1",' > "$target" ;;
  wrong-version) print -r -- '{"name":"AFNetworking","version":"9.0"}' > "$target" ;;
  embedded-fields) print -r -- '{"notice":"\"name\":\"AFNetworking\",\"version\":\"4.0.1\""}' > "$target" ;;
  empty) : > "$target" ;;
  *) print -r -- '{"name":"AFNetworking","version":"4.0.1","source":{"git":"https://github.com/AFNetworking/AFNetworking.git","tag":"4.0.1"}}' > "$target" ;;
esac
print -rn -- "$duration"
MOCK_CURL
  /bin/cat > "$TEST_ROOT/bin/git" <<'MOCK_GIT'
#!/bin/zsh
print -r -- "git|${(j: :)@}" >> "$MOCK_ROOT/calls"
[[ "$*" == *'ls-remote --exit-code https://github.com/CocoaPods/Specs.git HEAD' ]] || exit 91
[[ "${GIT_TERMINAL_PROMPT:-}" == 0 && "${GIT_ASKPASS:-}" == /usr/bin/false && "${GCM_INTERACTIVE:-}" == never ]] || exit 90
case "${MOCK_GIT_PROTOCOL:-valid}" in
  fail) exit 128 ;;
  invalid) print -r -- '<html>HEAD</html>' ;;
  hang)
    print -r -- "$$" >> "$MOCK_ROOT/processes"
    /bin/sleep 30 &
    print -r -- "$!" >> "$MOCK_ROOT/processes"
    wait
    ;;
  *) print -r -- '1234567890123456789012345678901234567890	HEAD' ;;
esac
MOCK_GIT
  /bin/cat > "$TEST_ROOT/bin/pod" <<'MOCK_POD'
#!/bin/zsh
print -r -- "pod|${(j: :)@}" >> "$MOCK_ROOT/calls"
if [[ "$*" == 'repo list --no-ansi' ]]; then
  /bin/cat "$MOCK_ROOT/repos"
  exit "${MOCK_REPO_LIST_RESULT:-0}"
fi
[[ "$1" == repo && ( "$2" == update || "$2" == add-cdn ) ]] || exit 89
[[ "${GIT_TERMINAL_PROMPT:-}" == 0 && "${GIT_ASKPASS:-}" == /usr/bin/false && "${GCM_INTERACTIVE:-}" == never ]] || exit 88
if [[ "${MOCK_POD_HANG:-0}" == 1 ]]; then
  print -r -- "$$" >> "$MOCK_ROOT/processes"
  /bin/sleep 30 &
  print -r -- "$!" >> "$MOCK_ROOT/processes"
  wait
fi
exit "${MOCK_POD_RESULT:-0}"
MOCK_POD
  /bin/cat > "$TEST_ROOT/bin/brew" <<'MOCK_BREW'
#!/bin/zsh
print -r -- "brew|${(j: :)@}" >> "$MOCK_ROOT/calls"
case "$*" in
  'list --formula --versions cocoapods') exit "${MOCK_BREW_INSTALLED_RESULT:-0}" ;;
  '--prefix cocoapods') print -r -- "${MOCK_BREW_PREFIX:-$MOCK_ROOT}" ;;
  'upgrade cocoapods') exit "${MOCK_BREW_UPGRADE_RESULT:-0}" ;;
  *) exit 87 ;;
esac
MOCK_BREW
  /bin/cat > "$TEST_ROOT/bin/gem" <<'MOCK_GEM'
#!/bin/zsh
print -r -- "gem|${(j: :)@}" >> "$MOCK_ROOT/calls"
case "$*" in
  'list -i ^cocoapods$') exit "${MOCK_GEM_INSTALLED_RESULT:-0}" ;;
  'env home') print -r -- "${MOCK_GEM_HOME:-$MOCK_ROOT/gems}" ;;
  'update cocoapods') exit "${MOCK_GEM_UPDATE_RESULT:-0}" ;;
  *) exit 86 ;;
esac
MOCK_GEM
  /bin/chmod +x "$TEST_ROOT/bin/curl" "$TEST_ROOT/bin/git" "$TEST_ROOT/bin/pod" "$TEST_ROOT/bin/brew" "$TEST_ROOT/bin/gem"
}
# 初始化专属运行目录，并通过 source 接口加载函数。
initialize_tests() {
  setopt NO_NOMATCH
  zmodload zsh/datetime
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-update-tests.XXXXXXXX")" || return 1
  export MOCK_ROOT="$TEST_ROOT"
  create_mock_commands
  export PATH="$TEST_ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  export TMPDIR="$TEST_ROOT/runtime"
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "$TEST_UPDATE_SCRIPT" || return 1
  LOG_FILE="$TEST_ROOT/test.log"
}
# 固定包发现及运行包装器，禁止从宿主默认目录发现真实 Homebrew。
install_safe_wrappers() {
  function jobs_update_pod_network_prepare() {
    return 0
  }
  function jobs_update_repair_gem_extensions() {
    return 0
  }
  function find_brew_bin() {
    [[ "${MOCK_BREW_PRESENT:-1}" == 1 ]] || return 1
    print -r -- "$MOCK_ROOT/bin/brew"
  }
  function jobs_update_has() {
    case "$1" in
      gem) [[ "${MOCK_GEM_PRESENT:-1}" == 1 ]] ;;
      pod) [[ "${MOCK_POD_PRESENT:-1}" == 1 ]] ;;
      *) command -v "$1" >/dev/null 2>&1 ;;
    esac
  }
  function jobs_update_run_cmd() {
    shift
    "$@"
  }
  function jobs_update_run_brew_adaptive_cmd() {
    print -r -- "adaptive|$1|$2" >> "$MOCK_ROOT/calls"
    shift 2
    "$@"
  }
  function jobs_update_run_sudo_cmd() {
    print -r -- "sudo-wrapper|$1" >> "$MOCK_ROOT/calls"
    shift
    "$@"
  }
  function warn_echo() { print -r -- "$*" >&2; }
  function info_echo() { print -r -- "$*" >&2; }
}
# 每个场景重新建立可控默认值，上一场景不能污染后续结果。
reset_fixture() {
  terminate_mock_processes
  export MOCK_CDN_MODE=valid MOCK_GIT_MODE=valid MOCK_CDN_TIME=1.0 MOCK_GIT_TIME=1.0
  export MOCK_CDN_DELAY=0 MOCK_GIT_DELAY=0 MOCK_PROBE_BARRIER=0 MOCK_GIT_PROTOCOL=valid
  export MOCK_POD_HANG=0 MOCK_POD_RESULT=0 MOCK_REPO_LIST_RESULT=0
  export MOCK_BREW_PRESENT=1 MOCK_BREW_INSTALLED_RESULT=0 MOCK_BREW_UPGRADE_RESULT=0 MOCK_BREW_PREFIX="$TEST_ROOT"
  export MOCK_GEM_PRESENT=1 MOCK_GEM_INSTALLED_RESULT=0 MOCK_GEM_UPDATE_RESULT=0 MOCK_GEM_HOME="$TEST_ROOT/gems"
  export MOCK_POD_PRESENT=1 MOCK_SPECS_RESULT=0 JOBS_SPECS_SOURCE=auto
  export JOBS_SPECS_PROBE_TIMEOUT=3 JOBS_SPECS_CONNECT_TIMEOUT=2 JOBS_SPECS_UPDATE_TIMEOUT=3
  JOBS_UPDATE_COCOAPODS_BREW_UPDATED=0
  : > "$TEST_ROOT/calls"
  : > "$TEST_ROOT/probes"
  : > "$TEST_ROOT/processes"
  : > "$TEST_ROOT/test.log"
  /bin/rm -f -- "$TEST_ROOT/cdn.started" "$TEST_ROOT/git.started"
  print -r -- $'private-repo\n- Type: git\n- URL: https://example.invalid/private-specs.git\n\npublic-alias\n- Type: CDN\n- URL: https://cdn.cocoapods.org/\n' > "$TEST_ROOT/repos"
}
# 输出断言失败的实际值，便于定位被测分支。
assert_equal() {
  [[ "$1" == "$2" ]] && return 0
  print -r -- "期望：[$1]；实际：[$2]；${3:-值不相等}" >&2
  return 1
}
# 核对操作日志包含预期整行，避免子串命中造成假通过。
assert_call() {
  /usr/bin/grep -Fxq -- "$1" "$TEST_ROOT/calls" && return 0
  print -r -- "缺少命令：$1" >&2
  /bin/cat "$TEST_ROOT/calls" >&2
  return 1
}
# 核对操作日志没有禁止出现的命令片段。
assert_no_call() {
  /usr/bin/grep -Fq -- "$1" "$TEST_ROOT/calls" || return 0
  print -r -- "不应执行：$1" >&2
  /bin/cat "$TEST_ROOT/calls" >&2
  return 1
}
# 确认所有探测临时目录均已由被测代码回收。
assert_no_probe_temp() {
  local -a remaining=("$TMPDIR"/jobs-update-specs.*(N))
  assert_equal 0 "${#remaining}" '探测临时目录未回收'
}
# 检查超时夹具进程已结束；短暂僵尸态不视为存活工作进程。
assert_no_live_mock_processes() {
  local process_id process_state
  while IFS= read -r process_id; do
    [[ "$process_id" == <-> ]] || continue
    process_state="$(/bin/ps -p "$process_id" -o stat= 2>/dev/null)"
    if [[ -n "$process_state" && "$process_state" != Z* ]]; then
      print -r -- "超时后仍存活的模拟进程：$process_id ($process_state)" >&2
      return 1
    fi
  done < "$TEST_ROOT/processes"
}
# 捕获选源输出及状态，失败时 stdout 必须为空。
assert_selection() {
  local selected selection_result=0
  selected="$(jobs_update_specs_select_source 2> "$TEST_ROOT/selector.stderr")" || selection_result=$?
  assert_equal "$1" "$selection_result" '选源退出码' || return 1
  assert_equal "$2" "$selected" '选源 stdout 必须只有源名' || return 1
  assert_no_probe_temp
}
# 两源健康且 Git 优势不足时保留 CDN。
test_cdn_default() { assert_selection 0 cdn; }
# Git GET 快过 CDN 15% 时允许优先 Git。
test_git_faster() { export MOCK_GIT_TIME=0.84; assert_selection 0 git; }
# 15% 阈值边界仍选择 CDN，避免轻微抖动切源。
test_git_threshold() { export MOCK_GIT_TIME=0.85; assert_selection 0 cdn; }
# CDN 失败时回退通过 HTTP 与 Git 协议检查的 Git。
test_cdn_failure() { export MOCK_CDN_MODE=fail; assert_selection 0 git; }
# Git 的 HTTP 可达不代表 Git 仓库协议可用。
test_git_protocol_failure() { export MOCK_GIT_TIME=0.1 MOCK_GIT_PROTOCOL=fail; assert_selection 0 cdn; }
# Git 协议响应必须包含有效 HEAD，不能只看退出码。
test_git_protocol_invalid() { export MOCK_CDN_MODE=fail MOCK_GIT_PROTOCOL=invalid; assert_selection 1 ''; }
# 双源均失败时不返回可用于刷新的源。
test_both_failure() { export MOCK_CDN_MODE=fail MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# 显式指定 CDN 后不可因不健康悄悄改选 Git。
test_forced_cdn_failure() { export JOBS_SPECS_SOURCE=cdn MOCK_CDN_MODE=fail; assert_selection 1 ''; }
# 显式指定 Git 后不可因不健康悄悄改选 CDN。
test_forced_git_failure() { export JOBS_SPECS_SOURCE=git MOCK_GIT_PROTOCOL=fail; assert_selection 1 ''; }
# 显式指定的健康 Git 不受 CDN 耗时优势影响。
test_forced_git() { export JOBS_SPECS_SOURCE=git MOCK_GIT_TIME=5.0; assert_selection 0 git; }
# 门户 HTML 即使带 name/version 文本，也不得识别为有效样本。
test_html_payload() { export MOCK_CDN_MODE=html MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# 非完整 JSON 即使包含正确字段，也不得识别为有效样本。
test_malformed_payload() { export MOCK_CDN_MODE=malformed MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# 普通 JSON 中的嵌套文本不得冒充 name/version 字段。
test_embedded_fields_payload() { export MOCK_CDN_MODE=embedded-fields MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# HTTP 成功但版本不匹配时拒绝该候选。
test_wrong_version_payload() { export MOCK_CDN_MODE=wrong-version MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# HTTP 成功但没有响应正文时拒绝该候选。
test_empty_payload() { export MOCK_CDN_MODE=empty MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# 两个 GET 必须并发启动，否则互相等待的夹具都会失败。
test_parallel_probes() { export MOCK_PROBE_BARRIER=1; assert_selection 0 cdn; }
# 非法耗时不得参与 Shell 算术或使候选被误判可用。
test_invalid_duration() { export MOCK_CDN_TIME='1;exit' MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# 限制探测参数范围，非法参数不得启动任何请求。
test_invalid_probe_config() {
  local value
  for value in 0 31 -1 1.5 abc 9999; do
    export JOBS_SPECS_PROBE_TIMEOUT="$value"
    assert_selection 1 '' || return 1
    assert_equal '' "$(< "$TEST_ROOT/calls")" '非法时限仍执行了命令' || return 1
  done
}
# 显式模式拼写错误必须失败，不能退回自动模式。
test_invalid_mode() { export JOBS_SPECS_SOURCE=unknown; assert_selection 1 ''; }
# 连接时限不得超过整次探测预算。
test_connect_timeout_clamp() {
  export JOBS_SPECS_PROBE_TIMEOUT=1 JOBS_SPECS_CONNECT_TIMEOUT=30
  assert_selection 0 cdn || return 1
  /usr/bin/grep -Fq -- '--connect-timeout 1 --max-time 1' "$TEST_ROOT/calls"
}
# 两个挂起 HTTP 进程须在同一墙钟预算结束，并回收所有子进程。
test_probe_timeout() {
  export JOBS_SPECS_PROBE_TIMEOUT=1 MOCK_CDN_MODE=hang MOCK_GIT_MODE=hang
  local started="$EPOCHREALTIME" elapsed
  assert_selection 1 '' || return 1
  elapsed=$(( EPOCHREALTIME - started ))
  (( elapsed < 5 )) || { print -r -- "探测墙钟超时未生效：${elapsed}s" >&2; return 1; }
  assert_no_live_mock_processes
}
# Git 协议阶段也必须包含在候选整体时限之内。
test_git_protocol_timeout() {
  export JOBS_SPECS_PROBE_TIMEOUT=1 MOCK_CDN_MODE=fail MOCK_GIT_PROTOCOL=hang
  assert_selection 1 '' || return 1
  assert_no_live_mock_processes
}
# 刷新使用 CocoaPods 清单中的自定义 CDN 别名，私源保持不动。
test_cdn_alias_refresh() {
  jobs_update_cocoapods_repos || return 1
  assert_call 'pod|repo list --no-ansi' || return 1
  assert_call 'pod|repo update public-alias' || return 1
  assert_no_call 'pod|repo update private-repo' || return 1
  assert_no_call 'pod|repo remove' || return 1
  assert_no_probe_temp
}
# 已登记 HTTPS Git 源按实际别名刷新，并容忍大小写及尾斜杠。
test_git_alias_refresh() {
  export JOBS_SPECS_SOURCE=git
  print -r -- $'private-repo\n- Type: git\n- URL: https://example.invalid/private.git\n\ncustom Specs\n- Type: git\n- URL: https://GITHUB.COM/CocoaPods/Specs.git/\n' > "$TEST_ROOT/repos"
  jobs_update_cocoapods_repos || return 1
  assert_call 'pod|repo update custom Specs' || return 1
  assert_no_call 'pod|repo add'
}
# 没有官方 CDN 时独立登记 CDN，不删除或改写已有私源。
test_add_missing_cdn() {
  print -r -- $'private-repo\n- Type: git\n- URL: https://example.invalid/private.git\n' > "$TEST_ROOT/repos"
  jobs_update_cocoapods_repos || return 1
  assert_call 'pod|repo add-cdn jobs-public-cdn https://cdn.cocoapods.org/' || return 1
  assert_call 'pod|repo update jobs-public-cdn' || return 1
  assert_no_call 'pod|repo remove'
}
# 新 CDN 名被私源占用时继续避让，不能覆写同名仓库。
test_cdn_name_collision() {
  print -r -- $'jobs-public-cdn\n- Type: git\n- URL: https://example.invalid/private.git\n\njobs-public-cdn-cdn\n- Type: git\n- URL: https://example.invalid/private2.git\n' > "$TEST_ROOT/repos"
  jobs_update_cocoapods_repos || return 1
  assert_call 'pod|repo add-cdn jobs-public-cdn-cdn-cdn https://cdn.cocoapods.org/' || return 1
  assert_call 'pod|repo update jobs-public-cdn-cdn-cdn'
}
# 以选项开头的不安全旧别名不得进入 pod repo update 参数。
test_unsafe_alias() {
  print -r -- $'--unsafe\n- Type: CDN\n- URL: https://cdn.cocoapods.org/\n' > "$TEST_ROOT/repos"
  jobs_update_cocoapods_repos || return 1
  assert_no_call 'pod|repo update --unsafe' || return 1
  assert_call 'pod|repo update jobs-public-cdn'
}
# 没有官方 Git 源时停止，不能为了更新冷克隆巨大 Specs 仓库。
test_missing_git_cache() {
  export JOBS_SPECS_SOURCE=git
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'pod|repo add' || return 1
  assert_no_call 'pod|repo update'
}
# 双源失败时只读取现有源，不新增、不删除、不触发刷新。
test_no_refresh_when_offline() {
  export MOCK_CDN_MODE=fail MOCK_GIT_MODE=fail
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'pod|repo update' || return 1
  assert_no_call 'pod|repo add' || return 1
  assert_no_call 'pod|repo remove'
}
# 仓库清单读取失败时停止，不能误以为没有源而新增。
test_repo_list_failure() {
  export MOCK_REPO_LIST_RESULT=1
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'pod|repo add' || return 1
  assert_no_call 'pod|repo update'
}
# 刷新失败需要向上返回，不能被包装器吞成成功。
test_refresh_failure() {
  export MOCK_POD_RESULT=7
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 7 "$result" || return 1
  assert_no_probe_temp
}
# 真实刷新阶段有独立墙钟时限，超时后杀掉 pod 及其后代。
test_refresh_timeout() {
  export JOBS_SPECS_UPDATE_TIMEOUT=1 MOCK_POD_HANG=1
  local started="$EPOCHREALTIME" elapsed result=0
  jobs_update_cocoapods_repos || result=$?
  elapsed=$(( EPOCHREALTIME - started ))
  assert_equal 124 "$result" || return 1
  (( elapsed < 6 )) || { print -r -- "刷新墙钟超时未生效：${elapsed}s" >&2; return 1; }
  assert_no_live_mock_processes || return 1
  assert_no_probe_temp
}
# 非法刷新预算不得启动真实刷新命令。
test_invalid_refresh_timeout() {
  export JOBS_SPECS_UPDATE_TIMEOUT=901
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'pod|repo update'
}
# 包管理器分支只验证升级逻辑，规格源步骤替换为明确记录的本地夹具。
stub_specs_refresh() {
  function jobs_update_cocoapods_repos() {
    print -r -- 'specs-refresh' >> "$MOCK_ROOT/calls"
    return "${MOCK_SPECS_RESULT:-0}"
  }
}
# 仅选择 CocoaPods 也要升级 Brew 所管理的安装，不能误报未安装。
test_brew_managed() {
  stub_specs_refresh
  jobs_update_gem_cocoapods || return 1
  assert_call 'brew|list --formula --versions cocoapods' || return 1
  assert_call 'brew|upgrade cocoapods' || return 1
  assert_call 'specs-refresh' || return 1
  assert_no_call 'gem|update' || return 1
  assert_equal 1 "$JOBS_UPDATE_COCOAPODS_BREW_UPDATED"
}
# 本轮 formula 阶段已升级 CocoaPods 时，不重复执行 Brew upgrade。
test_brew_already_updated() {
  stub_specs_refresh
  JOBS_UPDATE_COCOAPODS_BREW_UPDATED=1
  jobs_update_gem_cocoapods || return 1
  assert_no_call 'brew|upgrade' || return 1
  assert_call 'specs-refresh' || return 1
  assert_no_call 'gem|update'
}
# 升级成功的标记须跨连续函数调用保留，避免同轮重复升级。
test_brew_success_marker() {
  stub_specs_refresh
  jobs_update_gem_cocoapods || return 1
  jobs_update_gem_cocoapods || return 1
  local count="$(/usr/bin/grep -Fxc -- 'brew|upgrade cocoapods' "$TEST_ROOT/calls")"
  assert_equal 1 "$count"
}
# Brew 升级失败不能改走 gem 安装，并且不能写入成功标记。
test_brew_failure() {
  stub_specs_refresh
  export MOCK_BREW_UPGRADE_RESULT=1
  local result=0
  jobs_update_gem_cocoapods || result=$?
  assert_equal 1 "$result" || return 1
  assert_equal 0 "$JOBS_UPDATE_COCOAPODS_BREW_UPDATED" || return 1
  assert_no_call 'gem|update' || return 1
  assert_call 'specs-refresh'
}
# 可写 gem home 内的 CocoaPods 使用普通 gem update。
test_gem_managed() {
  stub_specs_refresh
  export MOCK_BREW_PRESENT=0
  jobs_update_gem_cocoapods || return 1
  assert_call 'gem|update cocoapods' || return 1
  assert_no_call 'sudo-wrapper|' || return 1
  assert_no_call 'brew|'
}
# Brew 存在但未登记 CocoaPods 时仍检查 gem，不误认为 Brew 管理。
test_brew_other_formula_only() {
  stub_specs_refresh
  export MOCK_BREW_INSTALLED_RESULT=1
  jobs_update_gem_cocoapods || return 1
  assert_call 'gem|update cocoapods' || return 1
  assert_no_call 'brew|upgrade'
}
# 不可写 gem home 必须进入已有提权包装器；测试包装器仍执行假 gem。
test_system_gem_managed() {
  stub_specs_refresh
  export MOCK_BREW_PRESENT=0 MOCK_GEM_HOME="$TEST_ROOT/missing-gem-home"
  jobs_update_gem_cocoapods || return 1
  assert_call 'sudo-wrapper|更新系统 gem 包 cocoapods' || return 1
  assert_call 'gem|update cocoapods'
}
# 未登记安装时不新装 CocoaPods，但已有 pod 仍可维护规格源。
test_unregistered_pod() {
  stub_specs_refresh
  export MOCK_BREW_PRESENT=0 MOCK_GEM_INSTALLED_RESULT=1
  jobs_update_gem_cocoapods || return 1
  assert_no_call 'gem|update' || return 1
  assert_no_call 'brew|upgrade' || return 1
  assert_call 'specs-refresh'
}
# 活跃 pod 属于 gem 时，即使 Brew 也装过 CocoaPods，仍升级当前 gem。
test_mixed_installations() {
  stub_specs_refresh
  export MOCK_BREW_PREFIX="$TEST_ROOT/runtime"
  jobs_update_gem_cocoapods || return 1
  assert_call 'gem|update cocoapods' || return 1
  assert_no_call 'brew|upgrade' || return 1
  assert_equal 0 "$JOBS_UPDATE_COCOAPODS_BREW_UPDATED"
}
# 活跃 pod 既不属于 Brew formula，也未被 gem 登记时停止本体升级。
test_unknown_owner() {
  stub_specs_refresh
  export MOCK_BREW_PREFIX="$TEST_ROOT/runtime" MOCK_GEM_INSTALLED_RESULT=1
  local result=0
  jobs_update_gem_cocoapods || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'gem|update' || return 1
  assert_no_call 'brew|upgrade' || return 1
  assert_call 'specs-refresh'
}
# Git 更快但没有本地 Git 仓库时，继续使用通过探测的 CDN。
test_cdn_when_git_cache_missing() {
  export MOCK_GIT_TIME=0.1
  jobs_update_cocoapods_repos || return 1
  assert_call 'pod|repo update public-alias' || return 1
  assert_no_call 'pod|repo add'
}
# HTTPS 探测不保证 SSH，只有 SSH Git 源时不得用它通过刷新。
test_ssh_git_cache_is_not_https() {
  export JOBS_SPECS_SOURCE=git
  print -r -- $'ssh-specs\n- Type: git\n- URL: git@github.com:CocoaPods/Specs.git\n' > "$TEST_ROOT/repos"
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'pod|repo update'
}
# 没有 pod 命令时返回失败，不调用规格源维护。
test_missing_pod() {
  stub_specs_refresh
  export MOCK_POD_PRESENT=0
  local result=0
  jobs_update_gem_cocoapods || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'specs-refresh'
}
# 在子 Shell 里执行单项，避免测试替换函数污染其它场景。
run_case() {
  local title="$1" test_function="$2" result
  (( TEST_TOTAL += 1 ))
  reset_fixture
  ( "$test_function" ) > "$TEST_ROOT/case.stdout" 2> "$TEST_ROOT/case.stderr"
  result=$?
  if (( result == 0 )); then
    (( TEST_PASSED += 1 ))
    print -r -- "✔ $title"
  else
    (( TEST_FAILED += 1 ))
    print -r -- "✖ $title"
    /bin/cat "$TEST_ROOT/case.stderr" "$TEST_ROOT/case.stdout"
  fi
}
# 覆盖有效性、阈值、并发、进程回收、源身份和升级来源分支。
run_network_cases() {
  run_case '健康双源默认 CDN' test_cdn_default
  run_case 'Git 明显更快' test_git_faster
  run_case 'Git 15% 阈值边界' test_git_threshold
  run_case 'CDN 失败回退 Git' test_cdn_failure
  run_case 'Git 协议失败回退 CDN' test_git_protocol_failure
  run_case 'Git 无效 HEAD' test_git_protocol_invalid
  run_case '双源失败' test_both_failure
  run_case '强制 CDN 不静默换源' test_forced_cdn_failure
  run_case '强制 Git 不静默换源' test_forced_git_failure
  run_case '强制健康 Git' test_forced_git
  run_case '拒绝 HTML 字段假阳性' test_html_payload
  run_case '拒绝不完整 JSON' test_malformed_payload
  run_case '拒绝 JSON 内嵌字段文本' test_embedded_fields_payload
  run_case '拒绝错误版本' test_wrong_version_payload
  run_case '拒绝空响应' test_empty_payload
  run_case '双源并发' test_parallel_probes
  run_case '拒绝非法耗时' test_invalid_duration
  run_case '探测时限范围校验' test_invalid_probe_config
  run_case '选源模式校验' test_invalid_mode
  run_case '连接时限收敛' test_connect_timeout_clamp
  run_case 'HTTP 墙钟超时与子进程回收' test_probe_timeout
  run_case 'Git 协议墙钟超时与子进程回收' test_git_protocol_timeout
  run_case '自定义 CDN 别名与私源保留' test_cdn_alias_refresh
  run_case '自定义 Git 别名与 URL 规范化' test_git_alias_refresh
  run_case '缺失 CDN 独立登记' test_add_missing_cdn
  run_case 'CDN 安全同名避让' test_cdn_name_collision
  run_case '拒绝选项形式别名' test_unsafe_alias
  run_case 'Git 缓存缺失不冷克隆' test_missing_git_cache
  run_case '离线不触发刷新' test_no_refresh_when_offline
  run_case '源清单失败不新增' test_repo_list_failure
  run_case '刷新失败传播' test_refresh_failure
  run_case '刷新墙钟超时与子进程回收' test_refresh_timeout
  run_case '刷新时限范围校验' test_invalid_refresh_timeout
  run_case '单独选择 CocoaPods 升级 Brew 安装' test_brew_managed
  run_case '跳过 formula 阶段已完成升级' test_brew_already_updated
  run_case '成功标记避免同轮重复升级' test_brew_success_marker
  run_case 'Brew 升级失败不混装 gem' test_brew_failure
  run_case '可写 gem home 升级' test_gem_managed
  run_case 'Brew 未登记 CocoaPods 回退 gem' test_brew_other_formula_only
  run_case '系统 gem 进入已有提权包装器' test_system_gem_managed
  run_case '未登记安装保留源维护' test_unregistered_pod
  run_case '混装优先升级活跃 gem' test_mixed_installations
  run_case '未知归属不升级本体' test_unknown_owner
  run_case '缺少 Git 缓存继续使用健康 CDN' test_cdn_when_git_cache_missing
  run_case 'SSH 本地源不冒充 HTTPS 可用' test_ssh_git_cache_is_not_https
  run_case '缺少 pod 返回失败' test_missing_pod
}
# 汇总结果，任何用例失败均向 CI 返回非零。
report_test_results() {
  print -r -- "共 ${TEST_TOTAL} 项：通过 ${TEST_PASSED}，失败 ${TEST_FAILED}。"
  (( TEST_FAILED == 0 ))
}
# 只在测试主 Shell 退出时清理；子 Shell 和命令替换不能删除共享夹具。
TRAPEXIT() {
  (( ZSH_SUBSHELL == 0 )) && cleanup_tests
  return 0
}
# 中断时通过统一退出路径回收夹具。
TRAPINT() {
  exit 130
}
# 终止时通过统一退出路径回收夹具。
TRAPTERM() {
  exit 143
}
# 依次展示隔离说明、准备夹具、执行回归并汇总。
main() {
  show_test_intro # 先说明模拟执行和临时文件边界。
  initialize_tests # 准备隔离命令并加载待测函数。
  install_safe_wrappers # 屏蔽宿主包管理器发现与提权执行。
  run_network_cases # 执行网络选源、刷新及升级来源回归。
  report_test_results # 以非零退出码报告任意失败。
}

main "$@"
