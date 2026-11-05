#!/bin/zsh
# 脚本自述：
# - 脚本名称：brew_diagnostics_tests.zsh
# - 核心用途：隔离验证 Homebrew 健康警告、真实错误与 formula 类型选择。
# - 影响范围：仅使用专属临时目录和假 brew；不联网、不安装、不升级。
# - 运行提示：自动运行回归；Ctrl+C 可取消。

TEST_SCRIPT_DIR="${${(%):-%x}:A:h}"
TEST_ROOT=''
TEST_PASSED=0
TEST_FAILED=0
MOCK_DOCTOR_MODE=healthy
MOCK_TRUST_DENIED=0
MOCK_FORMULA_INSTALLED=1
# 展示隔离测试范围。
show_test_intro() {
  print -r -- 'Homebrew 诊断与 formula 隔离回归：不联网、不安装、不升级。Ctrl+C 可取消。'
}
# 建立私有临时目录，并限制可执行程序来源。
initialize_tests() {
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-brew-diagnostics.XXXXXXXX")" || return 1
  /bin/mkdir -p "$TEST_ROOT/runtime" || return 1
  export TMPDIR="$TEST_ROOT/runtime" JOBS_MAC_ENV_SOURCE_MODE=1
  export PATH='/usr/bin:/bin:/usr/sbin:/sbin'
}
# 只允许本测试声明的 brew 请求，禁止进入真实包管理器。
install_mock_commands() {
  function brew() {
    print -r -- "${(j:|:)@}" >> "$TEST_ROOT/calls"
    case "$*" in
      doctor)
        case "$MOCK_DOCTOR_MODE" in
          healthy) print -r -- 'Your system is ready to brew.'; return 0 ;;
          warning)
            print -r -- 'Warning: Some installed casks are deprecated or disabled.'
            print -r -- '  codex-app'
            print -r -- 'Warning: You have unlinked kegs in your Cellar.'
            return 1
            ;;
          mixed)
            print -r -- 'Warning: Unlinked kegs.'
            print -r -- 'Error: Permission denied'
            return 1
            ;;
          masked) print -r -- 'Error: Failed to run diagnostic checks'; return 0 ;;
          crash|crash-zero)
            print -r -- 'Warning: Unlinked kegs.'
            print -r -- "/brew/doctor.rb:42:in 'run': diagnostic crashed (NoMethodError)"
            [[ "$MOCK_DOCTOR_MODE" != crash-zero ]] || return 0
            return 1
            ;;
          abnormal) print -r -- 'Warning: Unlinked kegs.'; return 2 ;;
          silent) return 1 ;;
          *) return 99 ;;
        esac
        ;;
      'help trust') return 0 ;;
      'trust --json=v1') print -r -- '{}'; return 0 ;;
      trust\ *)
        if (( MOCK_TRUST_DENIED == 1 )); then
          print -r -- 'Error: Trust configuration is not writable'
          return 1
        fi
        return 0
        ;;
      'list --formula --versions '*) (( MOCK_FORMULA_INSTALLED == 1 )); return $? ;;
      'tap '*) return 0 ;;
      cleanup|-v) return 0 ;;
      *) print -u2 -r -- "禁止的假 brew 调用：$*"; return 99 ;;
    esac
  }
  function require_brew_or_skip() { return 0; }
  function jobs_update_run_brew_update() { return 0; }
  function jobs_update_run_brew_upgrade() { return 0; }
  function jobs_update_run_brew_cask_upgrade() { return 0; }
  function jobs_update_run_brew_adaptive_cmd() {
    print -r -- "${(j:|:)@}" >> "$TEST_ROOT/upgrades"
    return 0
  }
}
# 重置结果与日志，防止前一个场景影响下一个场景。
reset_fixture() {
  LOG_FILE="$TEST_ROOT/run.log"
  : > "$LOG_FILE"
  : > "$TEST_ROOT/calls"
  : > "$TEST_ROOT/upgrades"
  JOBS_UPDATE_FAILURE_COUNT=0
  JOBS_UPDATE_SKIP_COUNT=0
  JOBS_UPDATE_COMMAND_COUNT=0
  JOBS_UPDATE_HEALTH_WARNING_COUNT=0
  JOBS_UPDATE_FAILED_DESCRIPTIONS=()
  MOCK_DOCTOR_MODE=healthy
  MOCK_TRUST_DENIED=0
  MOCK_FORMULA_INSTALLED=1
}
# 比较状态值并在失败时输出差异。
assert_equal() {
  [[ "$1" == "$2" ]] && return 0
  print -u2 -r -- "期望 [$1]；实际 [$2]"
  return 1
}
# 健康检查正常时不产生任何警告或失败。
test_healthy_doctor() {
  jobs_update_run_brew_doctor || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  assert_equal 0 "$JOBS_UPDATE_HEALTH_WARNING_COUNT" || return 1
  assert_equal 1 "$JOBS_UPDATE_COMMAND_COUNT"
}
# Homebrew 以 exit 1 返回的健康诊断必须保留警告，但不假报升级失败。
test_health_warnings() {
  MOCK_DOCTOR_MODE=warning
  jobs_update_run_brew_doctor || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  assert_equal 2 "$JOBS_UPDATE_HEALTH_WARNING_COUNT" || return 1
  assert_equal 1 "$JOBS_UPDATE_COMMAND_COUNT" || return 1
  /usr/bin/grep -Fq 'codex-app' "$LOG_FILE" || return 1
  /usr/bin/grep -Fq '2 项健康警告' "$LOG_FILE"
}
# 明确 Error、崩溃、异常退出或无诊断失败，均不能被警告分支吞掉。
test_execution_failures() {
  local mode result=0
  for mode in mixed masked crash crash-zero abnormal silent; do
    reset_fixture
    MOCK_DOCTOR_MODE="$mode"
    result=0
    jobs_update_run_brew_doctor || result=$?
    (( result != 0 )) || return 1
    assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
    assert_equal 0 "$JOBS_UPDATE_HEALTH_WARNING_COUNT" || return 1
  done
}
# 即使输出只有健康警告，日志无法落盘时仍须报告真实失败。
test_log_write_failure() {
  local result=0
  MOCK_DOCTOR_MODE=warning
  LOG_FILE="$TEST_ROOT"
  jobs_update_run_brew_doctor || result=$?
  (( result != 0 )) || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  assert_equal 0 "$JOBS_UPDATE_HEALTH_WARNING_COUNT"
}
# go-task 必须选择已安装的官方 formula，不能命中第三方同名 cask。
test_go_task_formula() {
  jobs_update_brew_formula_one go-task || return 1
  /usr/bin/grep -Fq '|plain|brew|upgrade|--formula|homebrew/core/go-task' "$TEST_ROOT/upgrades" || return 1
  ! /usr/bin/grep -Fq 'go-task/tap' "$TEST_ROOT/calls"
}
# 其它 formula 同样明确包类型，并保留既有名称。
test_general_formula() {
  jobs_update_brew_formula_one ruby || return 1
  /usr/bin/grep -Fq '|plain|brew|upgrade|--formula|ruby' "$TEST_ROOT/upgrades"
}
# 未安装的 formula 不得被升级入口隐式安装。
test_missing_formula() {
  MOCK_FORMULA_INSTALLED=0
  jobs_update_brew_formula_one go-task || return 1
  assert_equal 1 "$JOBS_UPDATE_SKIP_COUNT" || return 1
  [[ ! -s "$TEST_ROOT/upgrades" ]]
}
# Tap 信任失败必须传播返回值，而非被旧有 || true 吞掉。
test_trust_failure() {
  local result=0
  MOCK_TRUST_DENIED=1
  jobs_update_trust_configured_brew_taps || result=$?
  (( result != 0 && JOBS_UPDATE_FAILURE_COUNT > 0 ))
}
# 全组升级完成但健康检查有警告时，仍保留独立健康提示。
test_homebrew_warnings() {
  MOCK_DOCTOR_MODE=warning
  jobs_update_homebrew || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  assert_equal 2 "$JOBS_UPDATE_HEALTH_WARNING_COUNT"
}
# 逐项执行隔离场景，失败时展示被测输出。
run_tests() {
  [[ -n "$TEST_ROOT" && -d "$TEST_ROOT/runtime" ]] || return 1
  source "${TEST_SCRIPT_DIR:h:h}/update.command" || return 1
  install_mock_commands
  local name
  for name in test_healthy_doctor test_health_warnings test_execution_failures test_log_write_failure test_go_task_formula test_general_formula test_missing_formula test_trust_failure test_homebrew_warnings; do
    reset_fixture
    if ( "$name" ) > "$TEST_ROOT/output" 2>&1; then
      (( TEST_PASSED += 1 ))
      print -r -- "PASS $name"
    else
      (( TEST_FAILED += 1 ))
      print -r -- "FAIL $name"
      /bin/cat "$TEST_ROOT/output"
    fi
  done
  print -r -- "通过 ${TEST_PASSED} 组，失败 ${TEST_FAILED} 组。"
  (( TEST_FAILED == 0 ))
}
# 只回收本测试自行创建的临时目录。
cleanup_tests() {
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" && "${TEST_ROOT:t}" == jobs-brew-diagnostics.* ]]; then
    /bin/rm -r -- "$TEST_ROOT"
  fi
}
# 退出时回收隔离目录，不触碰真实环境。
TRAPEXIT() {
  cleanup_tests
}
# 编排测试说明、隔离准备与实际验证。
main() {
  show_test_intro # 说明不会调用真实安装或升级。
  initialize_tests # 加载被测函数并安装假命令。
  run_tests # 执行诊断、类型和失败传播回归。
}

main "$@"
