#!/bin/zsh
# 脚本自述：
# - 脚本名称：entrypoint_tests.zsh
# - 核心用途：隔离验证入口确认、日志配色和中断回收。
# - 影响范围：仅创建临时目录与假业务子进程，不执行真实更新。
# - 运行提示：自动执行回归，按 Ctrl+C 可取消。

TEST_SCRIPT_DIR="${${(%):-%x}:A:h}"
TEST_ROOT=''
TEST_COUNT=0
TEST_FAILED=0
TEST_PTY=''
TEST_TRANSCRIPT=''

# 回收本测试自己的终端和临时目录。
cleanup_tests() {
  [[ -z "$TEST_PTY" ]] || zpty -d "$TEST_PTY" 2>/dev/null || true
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" && "${TEST_ROOT:t}" == jobs-update-entry.* ]]; then
    if (( TEST_FAILED == 0 )); then
      /bin/rm -r -- "$TEST_ROOT"
    else
      print -u2 -r -- "隔离回归材料：$TEST_ROOT"
    fi
  fi
}
# 创建只调用假业务的驱动；源码的帮助入口另以真实脚本单独验证。
initialize_tests() {
  setopt NO_NOMATCH
  zmodload zsh/zpty || return 1
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-update-entry.XXXXXXXX")" || return 1
  export ENTRY_TEST_SCRIPT="${TEST_SCRIPT_DIR:h}/update.command"
  /bin/cat > "$TEST_ROOT/driver.zsh" <<'DRIVER'
export JOBS_MAC_ENV_SOURCE_MODE=1
source "$ENTRY_TEST_SCRIPT" || exit 97
unset JOBS_MAC_ENV_SOURCE_MODE
LOG_FILE="$ENTRY_TEST_CASE/log"
if [[ "${ENTRY_TEST_MODE:-stub}" == signal ]]; then
  function jobs_update_show_readme_and_wait() { return 0; }
  function update() {
    JOBS_UPDATE_BREW_CURLRC="$ENTRY_TEST_CASE/curlrc"
    : > "$JOBS_UPDATE_BREW_CURLRC"
    JOBS_UPDATE_NETWORK_READY=1
    /bin/zsh -c 'print -r -- "$$" > "$ENTRY_TEST_CASE/worker"; /bin/sleep 30 & print -r -- "$!" > "$ENTRY_TEST_CASE/sleeper"; wait' &
    wait "$!"
  }
else
  function jobs_update_main() {
    print -r -- called >> "$ENTRY_TEST_CASE/calls"
    success_echo '假业务完成'
    return "${ENTRY_TEST_RESULT:-0}"
  }
fi
main "$@"
entry_result=$?
print -r -- "$entry_result" > "$ENTRY_TEST_CASE/result"
exit "$entry_result"
DRIVER
  print -r -- '入口隔离回归：只运行假业务和私有子进程，不联网、不安装、不升级。'
}
# 为每一项准备独立的旧日志和环境。
reset_fixture() {
  export ENTRY_TEST_CASE="$TEST_ROOT/case-$TEST_COUNT" ENTRY_TEST_MODE=stub ENTRY_TEST_RESULT=0 TERM=xterm-256color
  unset NO_COLOR
  /bin/mkdir -p "$ENTRY_TEST_CASE/runtime"
  print -r -- preserved > "$ENTRY_TEST_CASE/log"
  : > "$ENTRY_TEST_CASE/calls"
  TEST_TRANSCRIPT=''
}
# 限定等待时间，避免入口回归后测试无限挂起。
wait_for_file() {
  local attempt
  for attempt in {1..100}; do
    [[ -f "$1" ]] && return 0
    /bin/sleep 0.02
  done
  return 1
}
# 非阻塞读取本测试 PTY 的输出。
drain_pty() {
  local chunk=''
  while zpty -r "$TEST_PTY" chunk 2>/dev/null; do
    TEST_TRANSCRIPT+="$chunk"$'\n'
  done
}
# 启动真正有 TTY 的假业务入口，并等待初始确认提示。
start_pty() {
  TEST_PTY="entry-$TEST_COUNT"
  zpty -b "$TEST_PTY" /bin/zsh "$TEST_ROOT/driver.zsh" "$@" || return 1
  local attempt
  for attempt in {1..100}; do
    drain_pty
    [[ "$TEST_TRANSCRIPT" == *'已了解脚本用途与影响'* ]] && return 0
    /bin/sleep 0.02
  done
  return 1
}
# 完成一个 PTY 会话并保留全部输出用于配色断言。
finish_pty() {
  wait_for_file "$ENTRY_TEST_CASE/result" || return 1
  drain_pty
  zpty -d "$TEST_PTY" 2>/dev/null || true
  TEST_PTY=''
}
# 帮助与参数错误必须保留旧日志并完全跳过业务。
test_readonly_entry() {
  local expected="$1" result=0
  shift
  /bin/zsh "$TEST_ROOT/driver.zsh" "$@" < /dev/null > "$ENTRY_TEST_CASE/output" 2>&1 || result=$?
  [[ "$result" == "$expected" && "$(< "$ENTRY_TEST_CASE/log")" == preserved && ! -s "$ENTRY_TEST_CASE/calls" ]]
}
# 真实脚本的 --help 不应创建或覆盖默认日志。
test_real_help() {
  print -r -- old > "$ENTRY_TEST_CASE/runtime/update.log"
  TMPDIR="$ENTRY_TEST_CASE/runtime" /bin/zsh "$ENTRY_TEST_SCRIPT" --help < /dev/null > "$ENTRY_TEST_CASE/output" 2>&1 || return 1
  [[ "$(< "$ENTRY_TEST_CASE/runtime/update.log")" == old ]]
}
# 第一次确认收到 EOF 后保持旧日志，不能进入业务。
test_intro_eof() {
  start_pty || return 1
  zpty -w -n "$TEST_PTY" $'\004'
  finish_pty || return 1
  [[ "$(< "$ENTRY_TEST_CASE/result")" != 0 && "$(< "$ENTRY_TEST_CASE/log")" == preserved && ! -s "$ENTRY_TEST_CASE/calls" ]]
}
# 首屏 Ctrl+C 直接取消，不创建日志或启动任何假业务。
test_intro_cancel() {
  start_pty || return 1
  zpty -w -n "$TEST_PTY" $'\003'
  local attempt cancelled=0
  for attempt in {1..100}; do
    if ! zpty -t "$TEST_PTY" 2>/dev/null; then
      cancelled=1
      break
    fi
    /bin/sleep 0.02
  done
  drain_pty
  zpty -d "$TEST_PTY" 2>/dev/null || true
  TEST_PTY=''
  (( cancelled == 1 )) && [[ "$(< "$ENTRY_TEST_CASE/log")" == preserved && ! -s "$ENTRY_TEST_CASE/calls" ]]
}
# 初次确认后才清旧日志，最终结果来自假业务。
test_confirmed_entry() {
  start_pty || return 1
  zpty -w -n "$TEST_PTY" $'\n'
  finish_pty || return 1
  [[ "$(< "$ENTRY_TEST_CASE/result")" == 0 && "$(< "$ENTRY_TEST_CASE/calls")" == called ]] || return 1
  ! /usr/bin/grep -Fq preserved "$ENTRY_TEST_CASE/log"
}
# 终端自述保留标题红粗体、正文蓝常规字重，文件不含 ANSI。
test_terminal_colors() {
  test_confirmed_entry || return 1
  [[ "$TEST_TRANSCRIPT" == *$'\033[1;31m'* && "$TEST_TRANSCRIPT" == *$'\033[0;34m'* ]] || return 1
  ! /usr/bin/grep -q $'\033' "$ENTRY_TEST_CASE/log"
}
# NO_COLOR 关闭首屏与业务颜色，落盘也保持纯文本。
test_no_color() {
  export NO_COLOR=1
  test_confirmed_entry || return 1
  [[ "$TEST_TRANSCRIPT" != *$'\033'* ]] && ! /usr/bin/grep -q $'\033' "$ENTRY_TEST_CASE/log"
}
# 无人值守只在假业务驱动中执行；不依赖 TTY，保留最终失败返回值。
test_unattended_result() {
  export ENTRY_TEST_RESULT=7
  local result=0
  /bin/zsh "$TEST_ROOT/driver.zsh" -t < /dev/null > "$ENTRY_TEST_CASE/output" 2>&1 || result=$?
  [[ "$result" == 7 && "$(< "$ENTRY_TEST_CASE/calls")" == called ]] || return 1
  ! /usr/bin/grep -q $'\033' "$ENTRY_TEST_CASE/output" "$ENTRY_TEST_CASE/log"
}
# 单独向入口 PID 发送 TERM 时立即回收其子进程和本轮 curlrc。
test_signal_cleanup() {
  export ENTRY_TEST_MODE=signal
  local driver_pid='' worker_pid='' sleeper_pid='' result=0
  /bin/zsh "$TEST_ROOT/driver.zsh" -t < /dev/null > "$ENTRY_TEST_CASE/output" 2>&1 &
  driver_pid=$!
  if ! wait_for_file "$ENTRY_TEST_CASE/sleeper"; then
    kill -TERM "$driver_pid" 2>/dev/null || true
    wait "$driver_pid" 2>/dev/null || true
    return 1
  fi
  worker_pid="$(< "$ENTRY_TEST_CASE/worker")"
  sleeper_pid="$(< "$ENTRY_TEST_CASE/sleeper")"
  kill -TERM "$driver_pid" || return 1
  wait "$driver_pid" 2>/dev/null || result=$?
  if kill -0 "$worker_pid" 2>/dev/null || kill -0 "$sleeper_pid" 2>/dev/null; then
    kill -KILL "$worker_pid" "$sleeper_pid" 2>/dev/null || true
    return 1
  fi
  [[ "$result" == 143 && ! -e "$ENTRY_TEST_CASE/curlrc" ]]
}
# 每个测试在子 shell 中运行，环境与 PTY 不污染其它用例。
run_case() {
  local label="$1"
  shift
  (( TEST_COUNT += 1 ))
  if (reset_fixture && "$@"); then
    print -r -- "PASS $label"
  else
    print -u2 -r -- "FAIL $label"
    (( TEST_FAILED += 1 ))
  fi
}
# 覆盖确认前只读、TTY 配色、假业务失败和独立入口中断回收。
run_tests() {
  run_case '帮助只读' test_readonly_entry 0 --help
  run_case '无人值守加帮助仍只读' test_readonly_entry 0 -t --help
  run_case '非法参数只读' test_readonly_entry 1 --invalid
  run_case '无TTY不执行业务' test_readonly_entry 1
  run_case '真实帮助保留默认日志' test_real_help
  run_case '初次确认EOF保留旧日志' test_intro_eof
  run_case '初次确认Ctrl+C取消' test_intro_cancel
  run_case '确认后才初始化日志' test_confirmed_entry
  run_case '终端配色与纯文本日志' test_terminal_colors
  run_case 'NO_COLOR完整降级' test_no_color
  run_case '无人值守传播假业务失败' test_unattended_result
  run_case 'TERM及时回收子进程和临时配置' test_signal_cleanup
  print -r -- "完成：$TEST_COUNT 项，失败 $TEST_FAILED 项。"
  (( TEST_FAILED == 0 ))
}
# 编排测试初始化和隔离回归。
main() {
  initialize_tests # 准备私有目录与只执行假业务的入口驱动。
  run_tests # 覆盖入口、日志、TTY 与信号回收。
}

trap cleanup_tests EXIT INT TERM
main "$@"
