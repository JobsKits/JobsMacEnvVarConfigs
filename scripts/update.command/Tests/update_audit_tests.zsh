#!/bin/zsh
# 脚本自述：
# - 脚本名称：update_audit_tests.zsh
# - 核心用途：隔离验证配置写入、Python 管理边界与退出清理。
# - 影响范围：仅使用私有临时文件和假命令，不更改 HOME 或真实用户配置。
# - 运行提示：自动运行，不联网、不升级；Ctrl+C 可取消。

AUDIT_SCRIPT_DIR="${${(%):-%x}:A:h}"
AUDIT_UPDATE_SCRIPT="${AUDIT_SCRIPT_DIR:h}/update.command"
AUDIT_ROOT=''
AUDIT_PASSED=0
AUDIT_FAILED=0

# 说明测试只模拟业务，不使用真实包管理器和用户配置。
show_audit_intro() {
  print -r -- '全脚本补充回归：配置、Python 与退出清理；仅私有夹具，不改 HOME、不联网、不升级。'
}
# 仅清理当前测试创建的目录。
cleanup_audit_tests() {
  if [[ -n "$AUDIT_ROOT" && -d "$AUDIT_ROOT" && "${AUDIT_ROOT:t}" == jobs-update-audit.* ]]; then
    /bin/rm -r -- "$AUDIT_ROOT"
  fi
}
# 创建隔离环境，并以只加载函数的接口取得被测代码。
initialize_audit_tests() {
  setopt NO_NOMATCH
  AUDIT_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-update-audit.XXXXXXXX")" || return 1
  /bin/mkdir -p "$AUDIT_ROOT/runtime" || return 1
  export TMPDIR="$AUDIT_ROOT/runtime" JOBS_MAC_ENV_SOURCE_MODE=1
  source "$AUDIT_UPDATE_SCRIPT" || return 1
}
# 重置计数与假命令数据，避免上一用例污染结果。
reset_audit_fixture() {
  LOG_FILE="$AUDIT_ROOT/audit.log"
  : > "$LOG_FILE"
  : > "$AUDIT_ROOT/calls"
  : > "$AUDIT_ROOT/lines"
  JOBS_UPDATE_FAILURE_COUNT=0
  JOBS_UPDATE_SKIP_COUNT=0
  JOBS_UPDATE_COMMAND_COUNT=0
  JOBS_UPDATE_FAILED_DESCRIPTIONS=()
  JOBS_UPDATE_COMMAND_OUTPUT_FILES=()
  JOBS_UPDATE_TRUST_MODE=0
  export AUDIT_MOCK_MANAGED_MARKER='' AUDIT_MOCK_PYTHON_PROBE_RESULT=0 AUDIT_MOCK_PIP_RESULT=0
  export AUDIT_MOCK_BREW_RESULT=0
}
# 不符时显示实际值，方便定位失败分支。
audit_assert_equal() {
  [[ "$1" == "$2" ]] && return 0
  print -u2 -r -- "期望 [$1]；实际 [$2]"
  return 1
}
# 确认命令调用与预期完全一致。
audit_assert_call() {
  /usr/bin/grep -Fxq -- "$1" "$AUDIT_ROOT/calls"
}
# 拒绝出现不应执行的命令。
audit_assert_no_call() {
  ! /usr/bin/grep -Fq -- "$1" "$AUDIT_ROOT/calls"
}
# 创建带空格路径的假 Homebrew，只允许 shellenv。
create_audit_brew() {
  AUDIT_BREW_BIN="$AUDIT_ROOT/brew path 中文/brew"
  /bin/mkdir -p "${AUDIT_BREW_BIN:h}" || return 1
  /bin/cat > "$AUDIT_BREW_BIN" <<'MOCK_BREW'
#!/bin/zsh
[[ "$*" == shellenv ]] || exit 98
(( ${AUDIT_MOCK_BREW_RESULT:-0} == 0 )) || exit "$AUDIT_MOCK_BREW_RESULT"
print -r -- 'export JOBS_AUDIT_SHELLENV=active'
MOCK_BREW
  /bin/chmod +x "$AUDIT_BREW_BIN"
}
# 截获配置写入目标，不接触真实 HOME 下的任何文件。
install_config_spies() {
  function append_comment_once() {
    print -r -- "comment|$2" >> "$AUDIT_ROOT/calls"
  }
  function append_once() {
    print -r -- "line|$2" >> "$AUDIT_ROOT/calls"
    print -r -- "$1" >> "$AUDIT_ROOT/lines"
  }
}
# 带空格的真实可执行文件路径必须生成可再次执行的 shellenv 行。
test_shellenv_quoted_path() {
  create_audit_brew || return 1
  install_config_spies
  setup_brew_shellenv "$AUDIT_BREW_BIN" || return 1
  audit_assert_equal active "${JOBS_AUDIT_SHELLENV:-}" || return 1
  local generated_line="$(/usr/bin/head -n 1 "$AUDIT_ROOT/lines")" observed=''
  observed="$(/bin/zsh -c 'eval "$1" || exit $?; print -r -- "${JOBS_AUDIT_SHELLENV:-}"' audit-shellenv "$generated_line")" || return 1
  audit_assert_equal active "$observed" || return 1
  audit_assert_call "comment|${HOME}/.zprofile" || return 1
  audit_assert_call "line|${HOME}/.zshrc"
}
# 实际写入路径被普通文件阻塞时，失败不能被配置成功日志覆盖。
test_shellenv_write_failure() {
  create_audit_brew || return 1
  functions[audit_real_append_comment_once]="${functions[append_comment_once]}"
  functions[audit_real_append_once]="${functions[append_once]}"
  print -r -- blocked > "$AUDIT_ROOT/not-a-directory"
  function append_comment_once() {
    audit_real_append_comment_once "$1" "$AUDIT_ROOT/not-a-directory/.zprofile"
  }
  function append_once() {
    audit_real_append_once "$1" "$AUDIT_ROOT/not-a-directory/.zprofile"
  }
  setup_brew_shellenv "$AUDIT_BREW_BIN"
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  ! /usr/bin/grep -Fq -- '已确认 Homebrew 环境变量配置' "$LOG_FILE"
}
# shellenv 命令失败时，不执行配置写入。
test_shellenv_activation_failure() {
  create_audit_brew || return 1
  install_config_spies
  export AUDIT_MOCK_BREW_RESULT=19
  setup_brew_shellenv "$AUDIT_BREW_BIN"
  audit_assert_equal 1 "$?" || return 1
  [[ ! -s "$AUDIT_ROOT/lines" ]] || return 1
  ! /usr/bin/grep -Fq -- '已确认 Homebrew 环境变量配置' "$LOG_FILE"
}
# 在指定的配置写入阶段返回失败，实际 HOME 保持只读。
install_failing_config_spies() {
  AUDIT_CONFIG_CALL_COUNT=0
  AUDIT_CONFIG_FAIL_AT="${1:-2}"
  function append_comment_once() {
    (( AUDIT_CONFIG_CALL_COUNT += 1 ))
    print -r -- "config|${AUDIT_CONFIG_CALL_COUNT}|$1" >> "$AUDIT_ROOT/calls"
    (( AUDIT_CONFIG_CALL_COUNT != AUDIT_CONFIG_FAIL_AT ))
  }
  function append_once() {
    (( AUDIT_CONFIG_CALL_COUNT += 1 ))
    print -r -- "config|${AUDIT_CONFIG_CALL_COUNT}|$1" >> "$AUDIT_ROOT/calls"
    (( AUDIT_CONFIG_CALL_COUNT != AUDIT_CONFIG_FAIL_AT ))
  }
}
# rbenv 数据写入失败须登记一次失败且不打印已确认。
test_rbenv_config_failure() {
  install_failing_config_spies 2
  ensure_rbenv_init
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  ! /usr/bin/grep -Fq -- '已确认 rbenv 初始化配置' "$LOG_FILE"
}
# jenv 中间步骤失败须停止后续写入。
test_jenv_config_failure() {
  install_failing_config_spies 2
  ensure_jenv_init
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 2 "$AUDIT_CONFIG_CALL_COUNT" || return 1
  audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  ! /usr/bin/grep -Fq -- '已确认 jenv 初始化配置' "$LOG_FILE"
}
# fzf 最后一步失败不能显示整个配置已完成。
test_fzf_config_failure() {
  /bin/mkdir -p "$AUDIT_ROOT/fzf" || return 1
  function jobs_update_has() { [[ "$1" == brew ]]; }
  function brew() { [[ "$*" == '--prefix fzf' ]] || return 99; print -r -- "$AUDIT_ROOT/fzf"; }
  install_failing_config_spies 3
  setup_fzf_shellenv
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  ! /usr/bin/grep -Fq -- '已确认 fzf shell 配置' "$LOG_FILE"
}
# fzf 位置探测失败时不能继续写 Shell 配置。
test_fzf_prefix_failure() {
  function jobs_update_has() { [[ "$1" == brew ]]; }
  function brew() { return 22; }
  install_failing_config_spies 99
  setup_fzf_shellenv
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 0 "$AUDIT_CONFIG_CALL_COUNT" && audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 读取现有内容失败不能误当作不存在并继续追加。
test_append_lookup_failure() {
  function grep() { return 2; }
  local target="$AUDIT_ROOT/lookup-failure-profile"
  append_once 'export mocked=1' "$target"
  audit_assert_equal 2 "$?" || return 1
  [[ ! -s "$target" ]] || return 1
  append_comment_once '# mock config' "$target"
  audit_assert_equal 2 "$?" && [[ ! -s "$target" ]]
}
# 创建目录失败时保留非零结果，不触碰其它目标。
test_append_mkdir_failure() {
  local blocker="$AUDIT_ROOT/append-blocker"
  print -r -- blocked > "$blocker"
  append_once 'export mocked=1' "$blocker/profile"
  local line_result=$?
  append_comment_once '# mock' "$blocker/profile"
  local comment_result=$?
  (( line_result != 0 && comment_result != 0 ))
}
# touch 失败应停止，不尝试读取或写入配置。
test_append_touch_failure() {
  function touch() { return 75; }
  append_once 'export mocked=1' "$AUDIT_ROOT/touch-failure-profile"
  audit_assert_equal 75 "$?" || return 1
  append_comment_once '# mock' "$AUDIT_ROOT/touch-failure-profile"
  audit_assert_equal 75 "$?"
}
# 实际写入返回失败时，两个追加函数都必须保留其状态。
test_append_print_failure() {
  function print() { return 71; }
  append_once 'export mocked=1' "$AUDIT_ROOT/print-failure-profile"
  audit_assert_equal 71 "$?" || return 1
  append_comment_once '# mock' "$AUDIT_ROOT/print-failure-profile"
  audit_assert_equal 71 "$?"
}
# 初始化配置失败不能被后面的成功检查覆盖 Ruby 项结果。
test_ruby_config_failure_propagates() {
  install_failing_config_spies 2
  function jobs_update_has() { [[ "$1" == rbenv ]]; }
  function rbenv() { [[ "$*" == rehash ]]; }
  function jobs_update_repair_gem_extensions() { return 0; }
  jobs_update_ruby_base
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  ! /usr/bin/grep -Fq -- '已确认 rbenv 初始化配置' "$LOG_FILE"
}
# 查找必须委托健康发现器，不能退回只检查路径存在。
test_find_brew_uses_health_success() {
  function jobs_brew_find() {
    print -r -- health-check >> "$AUDIT_ROOT/calls"
    print -r -- "$AUDIT_ROOT/verified-brew"
  }
  local candidate=''
  candidate="$(find_brew_bin)" || return 1
  audit_assert_equal "$AUDIT_ROOT/verified-brew" "$candidate" && audit_assert_call health-check
}
# 健康发现失败时不调用宿主其它 Homebrew。
test_find_brew_health_failure() {
  function jobs_brew_find() {
    print -r -- health-rejected >> "$AUDIT_ROOT/calls"
    return 7
  }
  local candidate=''
  candidate="$(find_brew_bin)"
  audit_assert_equal 7 "$?" || return 1
  [[ -z "$candidate" ]] && audit_assert_call health-rejected
}
# 创建只接受只读探测、版本检查或指定 pip 升级的假 Python。
install_python_mocks() {
  JOBS_PYTHON_BIN="$AUDIT_ROOT/mock-python"
  export AUDIT_CALLS_FILE="$AUDIT_ROOT/calls"
  /bin/cat > "$JOBS_PYTHON_BIN" <<'MOCK_PYTHON'
#!/bin/zsh
print -r -- "python|${(j: :)@}" >> "$AUDIT_CALLS_FILE"
if [[ "$1" == -c ]]; then
  (( ${AUDIT_MOCK_PYTHON_PROBE_RESULT:-0} == 0 )) || exit "$AUDIT_MOCK_PYTHON_PROBE_RESULT"
  print -r -- "${AUDIT_MOCK_MANAGED_MARKER:-}"
elif [[ "$*" == '-m pip --version' ]]; then
  print -r -- 'pip 26.0 from mock'
  exit "${AUDIT_MOCK_PIP_RESULT:-0}"
elif [[ "$*" == '-m pip install --upgrade pip' ]]; then
  print -r -- 'Successfully installed mock pip'
  exit "${AUDIT_MOCK_PIP_RESULT:-0}"
else
  exit 98
fi
MOCK_PYTHON
  /bin/chmod +x "$JOBS_PYTHON_BIN" || return 1
  function jobs_envupdate_python_preflight() {
    print -r -- "preflight|$1|${_JOBS_PYTHON_CONFIRMED_PROCESS:-}" >> "$AUDIT_ROOT/calls"
  }
  function jobs_update_has() { return 1; }
}
# 托管 Python 调用只读模式，并隔离外层遗留的准备授权。
test_python_trust_readonly() {
  install_python_mocks || return 1
  local _JOBS_PYTHON_CONFIRMED_PROCESS=old-authorization
  JOBS_UPDATE_TRUST_MODE=1
  export AUDIT_MOCK_MANAGED_MARKER='/mock/stdlib/EXTERNALLY-MANAGED'
  jobs_update_python_base </dev/null || return 1
  audit_assert_call 'preflight|readonly|' || return 1
  audit_assert_call 'python|-m pip --version' && audit_assert_no_call 'pip install'
}
# 已管理 Python 仅检查 pip 版本，不绕过 EXTERNALLY-MANAGED。
test_python_managed_no_install() {
  install_python_mocks || return 1
  export AUDIT_MOCK_MANAGED_MARKER='/mock/stdlib/EXTERNALLY-MANAGED'
  jobs_update_python_base </dev/null || return 1
  audit_assert_call 'preflight|confirmed|' || return 1
  audit_assert_call 'python|-m pip --version' && audit_assert_no_call 'pip install'
}
# 非外部管理 Python 保留普通 pip 自升级能力。
test_python_unmanaged_upgrade() {
  install_python_mocks || return 1
  jobs_update_python_base </dev/null || return 1
  audit_assert_call 'preflight|confirmed|' || return 1
  audit_assert_call 'python|-m pip install --upgrade pip' && audit_assert_no_call 'pip --version'
}
# 探测管理标记失败时停止，不能猜测为可写环境。
test_python_marker_probe_failure() {
  install_python_mocks || return 1
  export AUDIT_MOCK_PYTHON_PROBE_RESULT=13
  jobs_update_python_base </dev/null
  audit_assert_equal 1 "$?" || return 1
  audit_assert_no_call 'python|-m pip'
}
# pip 业务失败须保持非零结果和失败计数。
test_python_pip_failure() {
  install_python_mocks || return 1
  export AUDIT_MOCK_PIP_RESULT=21
  jobs_update_python_base </dev/null
  audit_assert_equal 21 "$?" && audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 只读环境准备未通过时不进入 pip 维护。
test_python_preflight_failure() {
  install_python_mocks || return 1
  function jobs_envupdate_python_preflight() {
    print -r -- "preflight|$1" >> "$AUDIT_ROOT/calls"
    return 1
  }
  JOBS_UPDATE_TRUST_MODE=1
  jobs_update_python_base </dev/null
  audit_assert_equal 1 "$?" || return 1
  audit_assert_no_call python
}
# 在 source 模式调用主流程时保留宿主已有信号处理。
test_source_preserves_signal_trap() {
  function jobs_update_show_readme_and_wait() { return 0; }
  function update() { return 0; }
  trap 'print -r -- host-term > "$AUDIT_ROOT/host-term"' TERM
  local trap_before="$(trap -p TERM)" trap_after=''
  jobs_update_main || return 1
  trap_after="$(trap -p TERM)"
  audit_assert_equal "$trap_before" "$trap_after"
}
# 通过真实 TERM 检查独立主流程退出143，并只回收登记的私有文件。
test_term_cleanup() {
  local signal_dir="$AUDIT_ROOT/signal" child_pid=0 result=0 attempt=0
  /bin/mkdir -p "$signal_dir" || return 1
  print -r -- keep > "$signal_dir/unrelated"
  /bin/cat > "$signal_dir/runner.zsh" <<'SIGNAL_RUNNER'
#!/bin/zsh
export JOBS_MAC_ENV_SOURCE_MODE=1
source "$1" || exit 96
unset JOBS_MAC_ENV_SOURCE_MODE
LOG_FILE="$AUDIT_SIGNAL_DIR/run.log"
function jobs_update_show_readme_and_wait() { return 0; }
function update() {
  local pending="$AUDIT_SIGNAL_DIR/jobs-update-command.pending"
  print -r -- pending > "$pending"
  print -r -- pending > "${pending}.status"
  JOBS_UPDATE_COMMAND_OUTPUT_FILES+=("$pending")
  print -r -- ready > "$AUDIT_SIGNAL_DIR/ready"
  while true; do
    /bin/sleep 0.02
  done
}
jobs_update_main
SIGNAL_RUNNER
  AUDIT_SIGNAL_DIR="$signal_dir" /bin/zsh "$signal_dir/runner.zsh" "$AUDIT_UPDATE_SCRIPT" > "$signal_dir/stdout" 2>&1 &
  child_pid=$!
  for attempt in {1..100}; do
    [[ -f "$signal_dir/ready" ]] && break
    kill -0 "$child_pid" 2>/dev/null || break
    /bin/sleep 0.02
  done
  if [[ ! -f "$signal_dir/ready" ]]; then
    kill -TERM "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    /bin/cat "$signal_dir/stdout" >&2
    return 1
  fi
  kill -TERM "$child_pid" || return 1
  wait "$child_pid"
  result=$?
  audit_assert_equal 143 "$result" || return 1
  [[ ! -e "$signal_dir/jobs-update-command.pending" && ! -e "$signal_dir/jobs-update-command.pending.status" ]] || return 1
  audit_assert_equal keep "$(<"$signal_dir/unrelated")"
}
# 隔离执行每一项，避免假函数、trap 与变量泄漏。
run_audit_case() {
  local title="$1" test_function="$2"
  if ( reset_audit_fixture; "$test_function" ) > "$AUDIT_ROOT/case.out" 2>&1; then
    (( AUDIT_PASSED += 1 ))
    print -r -- "PASS ${title}"
  else
    (( AUDIT_FAILED += 1 ))
    print -r -- "FAIL ${title}"
    /bin/cat "$AUDIT_ROOT/case.out"
  fi
}
# 执行补充验证并将失败传给调用方。
run_audit_tests() {
  run_audit_case 'shellenv空格路径可执行' test_shellenv_quoted_path
  run_audit_case '配置写入失败不报成功' test_shellenv_write_failure
  run_audit_case 'shellenv激活失败停止写入' test_shellenv_activation_failure
  run_audit_case 'rbenv配置失败不报成功' test_rbenv_config_failure
  run_audit_case 'jenv配置中途失败停止' test_jenv_config_failure
  run_audit_case 'fzf配置末步失败不报成功' test_fzf_config_failure
  run_audit_case 'fzf路径探测失败停止' test_fzf_prefix_failure
  run_audit_case '配置读取grep失败传播' test_append_lookup_failure
  run_audit_case '配置mkdir失败传播' test_append_mkdir_failure
  run_audit_case '配置touch失败传播' test_append_touch_failure
  run_audit_case '配置print失败传播' test_append_print_failure
  run_audit_case 'Ruby配置失败保留结果' test_ruby_config_failure_propagates
  run_audit_case 'Brew健康发现成功' test_find_brew_uses_health_success
  run_audit_case 'Brew健康发现失败' test_find_brew_health_failure
  run_audit_case 'Python托管只读且隔离旧授权' test_python_trust_readonly
  run_audit_case '外部管理pip仅检查版本' test_python_managed_no_install
  run_audit_case '普通Python自升级pip' test_python_unmanaged_upgrade
  run_audit_case 'Python管理标记探测失败' test_python_marker_probe_failure
  run_audit_case 'pip升级失败传播' test_python_pip_failure
  run_audit_case 'Python预检失败停止下游' test_python_preflight_failure
  run_audit_case 'source保留宿主信号处理' test_source_preserves_signal_trap
  run_audit_case 'TERM退出143并清理私有输出' test_term_cleanup
  print -r -- "结果：${AUDIT_PASSED} passed，${AUDIT_FAILED} failed"
  (( AUDIT_FAILED == 0 ))
}
# 只在主测试进程退出时回收夹具。
TRAPEXIT() {
  (( ZSH_SUBSHELL == 0 )) && cleanup_audit_tests
  return 0
}
# 编排说明、隔离环境与补充行为回归。
main() {
  show_audit_intro # 说明不修改真实用户环境。
  initialize_audit_tests # 加载函数并准备专属临时夹具。
  run_audit_tests # 验证配置、Python和信号处理边界。
}

main "$@"
