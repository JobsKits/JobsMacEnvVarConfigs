#!/bin/zsh
# 脚本自述：
# - 脚本名称：homebrew_network_tests.zsh
# - 核心用途：隔离验证 Homebrew 慢速下载、有限重试与 Python 共用索引更新。
# - 影响范围：仅使用临时文件与假 brew，不联网、不安装、不升级。
# - 运行提示：自动执行回归，按 Ctrl+C 可取消。

TEST_SCRIPT_DIR="${${(%):-%x}:A:h}"
TEST_ROOT=''
TEST_PASSED=0
TEST_FAILED=0
# 仅回收本测试创建的目录和网络策略临时文件。
cleanup_tests() {
  jobs_update_cleanup_network_strategy 2>/dev/null || true
  if [[ -d "$TEST_ROOT" && "${TEST_ROOT:t}" == jobs-brew-tests.* ]]; then
    /bin/rm -r -- "$TEST_ROOT"
  fi
}
# 建立只输出预定错误的假命令，杜绝真实包管理器调用。
initialize_tests() {
  print -r -- 'Homebrew 下载与索引隔离回归；不联网、不安装、不升级。Ctrl+C 可取消。'
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-brew-tests.XXXXXXXX")" || return 1
  /bin/mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/runtime"
  export MOCK_ROOT="$TEST_ROOT" TMPDIR="$TEST_ROOT/runtime"
  export PATH="$TEST_ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  /bin/cat > "$TEST_ROOT/bin/brew" <<'MOCK_BREW'
#!/bin/zsh
print -r -- "$*" >> "$MOCK_ROOT/calls"
print -r -- "${HOMEBREW_CURL_SPEED_LIMIT:-}|${HOMEBREW_CURL_SPEED_TIME:-}|${HOMEBREW_NO_AUTO_UPDATE:-}|${HOMEBREW_NO_INSTALL_CLEANUP:-}|${GIT_TERMINAL_PROMPT:-}" >> "$MOCK_ROOT/env"
[[ -f "${HOMEBREW_CURLRC:-}" ]] && /bin/cat "$HOMEBREW_CURLRC" >> "$MOCK_ROOT/configs"
integer attempt=0
[[ -f "$MOCK_ROOT/attempt" ]] && read -r attempt < "$MOCK_ROOT/attempt"
(( attempt += 1 ))
print -r -- "$attempt" > "$MOCK_ROOT/attempt"
case "${MOCK_BREW_MODE:-ok}" in
  recover) (( attempt > 1 )) && exit 0 ;;
  api-recover) [[ "${HOMEBREW_NO_INSTALL_FROM_API:-}" == 1 ]] && exit 0 ;;
  ok) exit 0 ;;
  permission) print -r -- 'Error: Permission denied' >&2; exit 1 ;;
  certificate) print -r -- 'curl: (60) SSL certificate problem: certificate verify failed' >&2; exit 60 ;;
  upgrade-failure)
    case "$1" in
      update|doctor|-v) exit 0 ;;
    esac
    ;;
  masked) print -r -- 'Error: Failed to download resource "qtwebengine"' >&2; exit 0 ;;
esac
if [[ "${MOCK_BREW_MODE:-}" == api-recover ]]; then
  print -r -- 'Error: Failed to download https://formulae.brew.sh/api/formula.jws.json' >&2
else
  print -r -- "fatal: unable to access 'https://github.com/Homebrew/brew/': Failed to connect" >&2
fi
exit 128
MOCK_BREW
  /bin/chmod +x "$TEST_ROOT/bin/brew"
}
# 覆盖环境探测，所有网络请求和包管理器均留在隔离夹具内。
install_safe_wrappers() {
  function jobs_update_select_preferred_ip_family() {
    JOBS_UPDATE_IPV4_PROBE_SPEED=140000
    JOBS_UPDATE_IPV6_PROBE_SPEED=460000
    JOBS_UPDATE_PREFERRED_IP_FAMILY=ipv6
    JOBS_UPDATE_SECONDARY_IP_FAMILY=ipv4
  }
  function jobs_update_start_brew_progress_monitor() { return 0; }
  function find_brew_bin() { print -r -- "$MOCK_ROOT/bin/brew"; }
  function require_brew_or_skip() { return 0; }
  function jobs_update_trust_configured_brew_taps() { return 0; }
  function _jobs_python_has_authorization() { return 0; }
  function jobs_brew_activate() { return 0; }
}
# 脚本退出时清理；不在初始化函数内注册局部 EXIT trap。
TRAPEXIT() {
  cleanup_tests
}
# 每个用例清空状态，保留原命令和网络策略函数供实际调用。
reset_fixture() {
  jobs_update_cleanup_network_strategy
  unset HOMEBREW_CURLRC
  JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET=0
  JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC=''
  JOBS_UPDATE_BREW_CURLRC=''
  JOBS_UPDATE_LAST_BREW_OUTPUT_FILE=''
  JOBS_UPDATE_NETWORK_READY=0
  JOBS_UPDATE_BREW_UPDATE_RESULTS=()
  JOBS_UPDATE_FAILURE_COUNT=0
  JOBS_UPDATE_SKIP_COUNT=0
  JOBS_UPDATE_COMMAND_COUNT=0
  JOBS_UPDATE_FAILED_STEPS=0
  JOBS_UPDATE_FAILED_DESCRIPTIONS=()
  JOBS_UPDATE_DEFER_BREW_FAILURE=0
  export MOCK_BREW_MODE=ok
  export JOBS_HOMEBREW_BIN="$TEST_ROOT/bin/brew"
  LOG_FILE="$TEST_ROOT/run.log"
  : > "$LOG_FILE"
  : > "$TEST_ROOT/calls"
  : > "$TEST_ROOT/env"
  : > "$TEST_ROOT/configs"
  print -r -- 0 > "$TEST_ROOT/attempt"
  unset _JOBS_PYTHON_UPDATED_BREWS
}
# 检查调用次数与最终状态，避免只匹配展示文案。
assert_equal() {
  [[ "$1" == "$2" ]] && return 0
  print -u2 -r -- "期望[$1]，实际[$2]"
  return 1
}
# 高速 API 测速不得提高 bottle 的停滞门槛。
test_stall_guard() {
  JOBS_UPDATE_IPV6_PROBE_SPEED=99999999
  assert_equal 1 "$(jobs_update_adaptive_low_speed_limit_for_family ipv6)" || return 1
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade || return 1
  /usr/bin/grep -Fxq '1|60|1|1|0' "$TEST_ROOT/env" || return 1
  /usr/bin/grep -Fxq -- '--speed-limit 1' "$TEST_ROOT/configs"
}
# 首轮失败后恢复不计最终失败，curl 协议会变更。
test_recovered_retry() {
  export MOCK_BREW_MODE=recover
  jobs_update_run_brew_adaptive_cmd fixture yes brew upgrade || return 1
  assert_equal 2 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  /usr/bin/grep -Fxq -- '--ipv6' "$TEST_ROOT/configs" || return 1
  /usr/bin/grep -Fxq -- '--ipv4' "$TEST_ROOT/configs"
}
# 不可达网络只尝试三次，最终失败只登记一次。
test_offline_bounded() {
  export MOCK_BREW_MODE=offline
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade && return 1
  assert_equal 3 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  /usr/bin/grep -Fxq '1|120|1|1|0' "$TEST_ROOT/env"
}
# 安装权限错误不能用重复下载处理。
test_permission_no_retry() {
  export MOCK_BREW_MODE=permission
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade && return 1
  assert_equal 1 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 证书错误需要修复信任链，不能靠切换 IP 协议重复尝试。
test_certificate_no_retry() {
  export MOCK_BREW_MODE=certificate
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade && return 1
  assert_equal 1 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 命令成功但日志目标无法写入时也必须返回失败。
test_log_write_failure() {
  LOG_FILE="$TEST_ROOT"
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade && return 1
  assert_equal 1 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 明确下载失败即使退出零也不能报告完成。
test_masked_download_failure() {
  export MOCK_BREW_MODE=masked
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade && return 1
  assert_equal 3 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 全局和 Python 自检共享同一成功索引，避免再次裸 brew update。
test_python_reuses_index() {
  jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN" || return 1
  _jobs_python_update_brew_once || return 1
  assert_equal 1 "$(<"$TEST_ROOT/attempt")"
}
# 同轮失败索引不被再次获取，也不进入下游升级。
test_failed_index_stops_downstream() {
  export MOCK_BREW_MODE=offline
  jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN" && return 1
  _jobs_python_update_brew_once && return 1
  jobs_update_brew_formula_one ruby && return 1
  assert_equal 3 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# API 降级成功时清除中间尝试的失败语义。
test_api_fallback_recovers() {
  export MOCK_BREW_MODE=api-recover
  jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN" || return 1
  assert_equal 2 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 升级失败必须保留缓存并跳过显式 cleanup。
test_no_cleanup_after_failure() {
  export MOCK_BREW_MODE=upgrade-failure
  jobs_update_homebrew && return 1
  /usr/bin/grep -Fxq upgrade "$TEST_ROOT/calls" || return 1
  /usr/bin/grep -Fxq doctor "$TEST_ROOT/calls" || return 1
  ! /usr/bin/grep -Fxq cleanup "$TEST_ROOT/calls"
}
# curl 设置的原始未设置、空值和文件路径均需精确还原。
test_restore_curlrc() {
  local mode expected_file
  for mode in unset empty file; do
    reset_fixture
    case "$mode" in
      unset) unset HOMEBREW_CURLRC ;;
      empty) export HOMEBREW_CURLRC='' ;;
      file)
        expected_file="$TEST_ROOT/original config"
        print -r -- '--retry 1' > "$expected_file"
        export HOMEBREW_CURLRC="$expected_file"
        ;;
    esac
    jobs_update_ensure_network_strategy || return 1
    local temporary_file="$JOBS_UPDATE_BREW_CURLRC"
    jobs_update_cleanup_network_strategy
    [[ ! -e "$temporary_file" ]] || return 1
    case "$mode" in
      unset) (( ! ${+HOMEBREW_CURLRC} )) || return 1 ;;
      empty) (( ${+HOMEBREW_CURLRC} )) && [[ -z "$HOMEBREW_CURLRC" ]] || return 1 ;;
      file) assert_equal "$expected_file" "$HOMEBREW_CURLRC" || return 1 ;;
    esac
  done
}
# 独立记录各场景，失败时展示被测日志。
run_tests() {
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "${TEST_SCRIPT_DIR:h}/update.command" || return 1
  install_safe_wrappers
  local name
  for name in test_stall_guard test_recovered_retry test_offline_bounded test_permission_no_retry test_certificate_no_retry test_log_write_failure test_masked_download_failure test_python_reuses_index test_failed_index_stops_downstream test_api_fallback_recovers test_no_cleanup_after_failure test_restore_curlrc; do
    reset_fixture
    if "$name" > "$TEST_ROOT/output" 2>&1; then
      (( TEST_PASSED += 1 ))
      print -r -- "PASS $name"
    else
      (( TEST_FAILED += 1 ))
      print -r -- "FAIL $name"
      /bin/cat "$TEST_ROOT/output"
    fi
  done
  print -r -- "Homebrew 隔离回归：$TEST_PASSED passed，$TEST_FAILED failed"
  (( TEST_FAILED == 0 ))
}
# 编排隔离环境及回归用例。
main() {
  initialize_tests # 展示测试边界并加载只供 source 的被测函数。
  run_tests # 验证下载重试、缓存门禁和环境恢复。
}
main "$@"
