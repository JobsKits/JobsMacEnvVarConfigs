#!/bin/zsh
# 脚本自述：
# - 核心用途：隔离验证 update 的 Gem 扩展修复顺序、错误传播和独立入口交互。
# - 影响范围：仅写专属临时目录；gem、rbenv、Ruby worker 与 Specs 刷新均为替身。
# - 运行提示：自动执行，不联网、不升级、不修改宿主 Gem；按 Ctrl+C 可取消。

TEST_DIR="${${(%):-%x}:A:h}"
PROTOTYPE_SCRIPT="${TEST_DIR:h}/repair_gem_extensions.command"
UPDATE_SCRIPT="${TEST_DIR:h:h}/update.command/update.command"
TEST_ROOT=''
TEST_PASSED=0
TEST_FAILED=0
MOCK_GEM_PRESENT=1
MOCK_RBENV_PRESENT=1
MOCK_POD_PRESENT=1
MOCK_WORKER_FAILURE_AT=0
MOCK_WORKER_EXIT=23
PTY_CAPTURE=''

# 说明所有真实包管理器均不会进入被测执行链。
show_test_intro() {
  print -r -- 'Gem 原生扩展 Shell 集成回归：仅运行临时目录与替身，不联网、不升级。'
}
# 汇总断言；失败继续执行以保留完整回归结果。
expect_equal() {
  local expected="$1" actual="$2" description="$3"
  if [[ "$actual" == "$expected" ]]; then
    (( TEST_PASSED += 1 ))
  else
    (( TEST_FAILED += 1 ))
    print -u2 -r -- "✖ ${description}：期望 ${(qqq)expected}，实际 ${(qqq)actual}"
  fi
}
# 检查文本包含关键反馈，不依赖日志其它细节。
expect_contains() {
  local actual="$1" expected="$2" description="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    (( TEST_PASSED += 1 ))
  else
    (( TEST_FAILED += 1 ))
    print -u2 -r -- "✖ ${description}：缺少 ${(qqq)expected}"
  fi
}
# 检查文本不包含被禁止的控制符或真实业务记录。
expect_absent() {
  local actual="$1" unexpected="$2" description="$3"
  if [[ "$actual" != *"$unexpected"* ]]; then
    (( TEST_PASSED += 1 ))
  else
    (( TEST_FAILED += 1 ))
    print -u2 -r -- "✖ ${description}：出现 ${(qqq)unexpected}"
  fi
}
# 成功时回收本测试临时文件，失败保留证据便于排查。
cleanup_tests() {
  zpty -d jobs_gemext_test 2>/dev/null || true
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" && "${TEST_ROOT:t}" == jobs-gemext-integration.* ]]; then
    if (( TEST_FAILED == 0 )); then
      /bin/rm -r -- "$TEST_ROOT"
    else
      print -u2 -r -- "隔离回归材料：$TEST_ROOT"
    fi
  fi
}
# 在脚本进程结束时回收目录，避免函数内 EXIT trap 提前触发清理。
TRAPEXIT() {
  cleanup_tests
}
# 创建专属目录并在明确的 source 模式下加载 update 函数。
initialize_tests() {
  setopt NO_NOMATCH
  zmodload zsh/zpty || return 1
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-gemext-integration.XXXXXXXX")" || return 1
  export TEST_ROOT
  /bin/mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/gems" "$TEST_ROOT/runtime"
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "$UPDATE_SCRIPT" || return 1
}
# 将所有升级与刷新入口替换为无副作用记录器，worker 次数通过文件跨管道保存。
install_update_mocks() {
  function jobs_update_has() {
    case "$1" in
      gem) (( MOCK_GEM_PRESENT == 1 )) ;;
      rbenv) (( MOCK_RBENV_PRESENT == 1 )) ;;
      pod) (( MOCK_POD_PRESENT == 1 )) ;;
      *) return 1 ;;
    esac
  }
  function ensure_rbenv_init() {
    print -r -- 'rbenv:init' >> "$TEST_ROOT/events"
  }
  function rbenv() {
    print -r -- "rbenv:$*" >> "$TEST_ROOT/events"
  }
  function gem() {
    case "$*" in
      'list -i ^cocoapods$') return 0 ;;
      'env home') print -r -- "$TEST_ROOT/gems" ;;
      update*) print -r -- "gem:$*" >> "$TEST_ROOT/events" ;;
      *) print -u2 -r -- "禁止的 gem 替身调用：$*"; return 91 ;;
    esac
  }
  function jobs_update_run_cmd() {
    shift
    "$@"
  }
  function jobs_update_run_sudo_cmd() {
    shift
    "$@"
  }
  function find_brew_bin() {
    return 1
  }
  function jobs_update_cocoapods_repos() {
    print -r -- 'repos:refresh' >> "$TEST_ROOT/events"
  }
  function jobs_gemext_process() {
    local count=0
    [[ ! -s "$TEST_ROOT/worker-count" ]] || count="$(<"$TEST_ROOT/worker-count")"
    (( count += 1 ))
    print -r -- "$count" > "$TEST_ROOT/worker-count"
    print -r -- "worker:$1:$count" >> "$TEST_ROOT/events"
    print -r -- "MOCK_WORKER:$1:$count"
    (( count != MOCK_WORKER_FAILURE_AT )) || return "$MOCK_WORKER_EXIT"
    return 0
  }
  function warn_echo() {
    print -r -- "$1"
  }
  function info_echo() {
    print -r -- "$1"
  }
}
# 每个用例恢复健康默认值，并将日志限制在专属目录。
reset_update_mock() {
  MOCK_GEM_PRESENT=1
  MOCK_RBENV_PRESENT=1
  MOCK_POD_PRESENT=1
  MOCK_WORKER_FAILURE_AT=0
  MOCK_WORKER_EXIT=23
  LOG_FILE="$TEST_ROOT/update.log"
  : > "$TEST_ROOT/events"
  : > "$TEST_ROOT/worker-count"
  : > "$LOG_FILE"
}
# 验证真实 RubyGems 升级前后各扫描一次，并先完成 rbenv 初始化。
test_update_sequence() {
  local result=0 expected=''
  reset_update_mock
  jobs_update_ruby_base > "$TEST_ROOT/output" 2>&1 || result=$?
  expected=$'rbenv:init\nrbenv:rehash\nworker:repair:1\ngem:update --system\ngem:update\nworker:repair:2'
  expect_equal 0 "$result" '健康 Ruby 阶段成功'
  expect_equal "$expected" "$(<"$TEST_ROOT/events")" 'rbenv、修复、升级、复检顺序'
  expect_equal 2 "$(<"$TEST_ROOT/worker-count")" '健康环境升级前后仍各扫描一次'
  expect_contains "$(<"$LOG_FILE")" 'MOCK_WORKER:repair:1' '首次扫描同步落盘'
  expect_contains "$(<"$LOG_FILE")" 'MOCK_WORKER:repair:2' '升级后复检同步落盘'
}
# 前后任一次修复失败，都必须让 Ruby 阶段报告非零。
test_update_worker_failures() {
  local failure_at result
  for failure_at in 1 2; do
    reset_update_mock
    MOCK_WORKER_FAILURE_AT="$failure_at"
    result=0
    jobs_update_ruby_base > "$TEST_ROOT/output" 2>&1 || result=$?
    expect_equal 1 "$result" "第 ${failure_at} 次修复失败传播到 Ruby 阶段"
  done
  reset_update_mock
  MOCK_WORKER_FAILURE_AT=1
  result=0
  jobs_update_repair_gem_extensions > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 23 "$result" '日志管道保留 worker 原退出码'
}
# 真实 tee 写入失败不能被 worker 的成功退出码覆盖。
test_update_tee_failures() {
  local result=0
  reset_update_mock
  print -r -- 'not a directory' > "$TEST_ROOT/blocked"
  LOG_FILE="$TEST_ROOT/blocked/update.log"
  jobs_update_repair_gem_extensions > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 1 "$result" 'worker 成功但 tee 失败时返回失败'
  MOCK_WORKER_FAILURE_AT=2
  result=0
  jobs_update_repair_gem_extensions > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 23 "$result" 'worker 与 tee 同时失败时保留 worker 错误'
}
# CocoaPods 本体升级后先修扩展，再刷新 Specs；修复失败或无 pod 时阻止刷新。
test_cocoapods_sequence() {
  local result=0
  reset_update_mock
  jobs_update_gem_cocoapods > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 0 "$result" 'CocoaPods 升级与复检成功'
  expect_equal $'gem:update cocoapods\nworker:repair:1\nrepos:refresh' "$(<"$TEST_ROOT/events")" 'CocoaPods 工具升级、扩展复检、Specs 刷新顺序'
  reset_update_mock
  MOCK_WORKER_FAILURE_AT=1
  result=0
  jobs_update_gem_cocoapods > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 1 "$result" 'CocoaPods 扩展复检失败传播'
  expect_absent "$(<"$TEST_ROOT/events")" 'repos:refresh' '修复失败跳过 Specs 刷新'
  reset_update_mock
  MOCK_POD_PRESENT=0
  result=0
  jobs_update_gem_cocoapods > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 1 "$result" '无 pod 时报告不可刷新'
  expect_absent "$(<"$TEST_ROOT/events")" 'worker:' '无 pod 时不调用扩展 worker'
  expect_absent "$(<"$TEST_ROOT/events")" 'repos:refresh' '无 pod 时不刷新 Specs'
}
# 内嵌和原型逐字节相同，修复模块与独立脚本均没有外部 source 依赖。
test_embedded_copy() {
  local script_name output_name result
  for script_name output_name in "$PROTOTYPE_SCRIPT" prototype-block "$UPDATE_SCRIPT" update-block; do
    /usr/bin/awk '/^# >>> Jobs Gem extension repair >>>$/ { copy = 1 } copy { print } /^# <<< Jobs Gem extension repair <<<$/ { exit }' "$script_name" > "$TEST_ROOT/$output_name"
  done
  result=0
  /usr/bin/cmp -s "$TEST_ROOT/prototype-block" "$TEST_ROOT/update-block" || result=$?
  expect_equal 0 "$result" '内嵌修复块与独立原型逐字节一致'
  result=0
  if /usr/bin/grep -Eq '^[[:space:]]*(source|\.)[[:space:]]+[^=[:space:]]' "$TEST_ROOT/prototype-block" "$PROTOTYPE_SCRIPT"; then
    result=1
  fi
  expect_equal 0 "$result" '修复模块可独立携带且不 source 外置实现'
}
# 生成仅执行替身的独立脚本和伪终端驱动。
prepare_standalone_fixtures() {
  /usr/bin/sed '$d' "$PROTOTYPE_SCRIPT" > "$TEST_ROOT/prototype-definitions.zsh"
  /bin/cp "$PROTOTYPE_SCRIPT" "$TEST_ROOT/standalone.command"
  /bin/cat > "$TEST_ROOT/bin/ruby" <<'MOCK_RUBY'
#!/bin/zsh
if [[ "$*" == '--disable-gems -rrbconfig -e '* ]]; then
  print -r -- 'ruby:health' >> "$TEST_ROOT/ruby-events"
  exit 0
fi
if [[ "$1" == --disable-gems && "$2" == - ]]; then
  /bin/cat > /dev/null
  print -r -- "ruby:worker:$3" >> "$TEST_ROOT/ruby-events"
  print -r -- "MOCK_STANDALONE_WORKER:$3"
  exit 0
fi
print -u2 -r -- "拒绝未知 Ruby 调用：$*"
exit 92
MOCK_RUBY
  /bin/chmod +x "$TEST_ROOT/bin/ruby"
  /bin/cat > "$TEST_ROOT/pty-driver.zsh" <<'PTY_DRIVER'
#!/bin/zsh
source "$TEST_ROOT/prototype-definitions.zsh"
trap 'print -r -- "TEST_DONE=$?"' EXIT
jobs_gemext_process() {
  print -r -- "pty:worker:$1" >> "$TEST_ROOT/pty-events"
  print -r -- "MOCK_PTY_WORKER:$1"
}
case "$1" in
  color)
    unset NO_COLOR
    TERM=xterm-256color
    jobs_intro_line title 'TITLE'
    jobs_intro_line body '1、BODY'
    ;;
  no-color)
    NO_COLOR=1
    TERM=xterm-256color
    jobs_intro_line title 'TITLE'
    jobs_intro_line body '1、BODY'
    ;;
  skip|run|cancel)
    main --repair
    exit $?
    ;;
esac
PTY_DRIVER
}
# 通过原生 zpty 验证 TTY 配色与两次输入，不调用真实 worker。
capture_pty() {
  local scenario="$1" answer_one="${2:-}" answer_two="${3:-}" chunk='' attempt
  PTY_CAPTURE=''
  /bin/mkdir -p "$TEST_ROOT/pty-$scenario"
  : > "$TEST_ROOT/pty-events"
  TMPDIR="$TEST_ROOT/pty-$scenario" zpty -b jobs_gemext_test /bin/zsh -f "$TEST_ROOT/pty-driver.zsh" "$scenario"
  case "$scenario" in
    skip|run|cancel)
      zpty -w -n jobs_gemext_test "${answer_one}"$'\n'
      [[ "$scenario" == cancel ]] || zpty -w -n jobs_gemext_test "${answer_two}"$'\n'
      ;;
  esac
  for attempt in {1..300}; do
    while zpty -r jobs_gemext_test chunk; do
      PTY_CAPTURE+="$chunk"
    done
    [[ "$PTY_CAPTURE" != *TEST_DONE=* ]] || break
    /bin/sleep 0.01
  done
  zpty -d jobs_gemext_test 2>/dev/null || true
  expect_contains "$PTY_CAPTURE" 'TEST_DONE=0' "伪终端 ${scenario} 正常结束"
}
# 独立复制文件运行成功；无交互授权时不创建日志或启动 worker。
test_standalone_entry() {
  local result=0
  : > "$TEST_ROOT/ruby-events"
  /usr/bin/env JOBS_GEMEXT_RUBY="$TEST_ROOT/bin/ruby" TMPDIR="$TEST_ROOT/runtime" \
    /bin/zsh "$TEST_ROOT/standalone.command" --check -t > "$TEST_ROOT/standalone-output" 2>&1 || result=$?
  expect_equal 0 "$result" '单独拷走脚本仍能执行只读 worker'
  expect_equal $'ruby:health\nruby:worker:check' "$(<"$TEST_ROOT/ruby-events")" '独立入口只调用替身 Ruby'
  expect_contains "$(<"$TEST_ROOT/runtime/repair_gem_extensions.log")" 'MOCK_STANDALONE_WORKER:check' '独立入口日志同步落盘'
  /bin/mkdir -p "$TEST_ROOT/no-tty"
  : > "$TEST_ROOT/ruby-events"
  result=0
  /usr/bin/env JOBS_GEMEXT_RUBY="$TEST_ROOT/bin/ruby" TMPDIR="$TEST_ROOT/no-tty" \
    /bin/zsh "$TEST_ROOT/standalone.command" --repair < /dev/null > "$TEST_ROOT/standalone-output" 2>&1 || result=$?
  expect_equal 2 "$result" '普通入口非 TTY 不静默修复'
  expect_equal '' "$(<"$TEST_ROOT/ruby-events")" '确认前不调用 Ruby'
  if [[ -e "$TEST_ROOT/no-tty/repair_gem_extensions.log" ]]; then
    expect_equal absent exists '确认前不初始化日志'
  else
    expect_equal absent absent '确认前不初始化日志'
  fi
}
# 检查自述红色粗体标题、蓝色常规正文以及纯文本降级。
test_standalone_styles() {
  capture_pty color
  expect_contains "$PTY_CAPTURE" $'\e[1;31mTITLE\e[0m' 'TTY 标题为红色粗体'
  expect_contains "$PTY_CAPTURE" $'\e[0;34m1、BODY\e[0m' 'TTY 编号正文为蓝色常规'
  capture_pty no-color
  expect_absent "$PTY_CAPTURE" $'\e[' 'NO_COLOR 时不输出 ANSI'
  local output=''
  output="$(/bin/zsh -c 'source "$TEST_ROOT/prototype-definitions.zsh"; jobs_intro_line title TITLE; jobs_intro_line body "1、BODY"')"
  expect_equal $'TITLE\n1、BODY' "$output" '非 TTY 输出纯文本'
}
# 回车跳过不写日志、不调用 worker；非空输入才执行，取消自述也不执行。
test_standalone_prompts() {
  capture_pty skip '' ''
  expect_equal '' "$(<"$TEST_ROOT/pty-events")" '普通操作直接回车跳过'
  if [[ -e "$TEST_ROOT/pty-skip/repair_gem_extensions.log" ]]; then
    expect_equal absent exists '跳过操作不初始化日志'
  else
    expect_equal absent absent '跳过操作不初始化日志'
  fi
  capture_pty run '' y
  expect_equal 'pty:worker:repair' "$(<"$TEST_ROOT/pty-events")" '普通操作非空输入才执行修复'
  expect_contains "$(<"$TEST_ROOT/pty-run/repair_gem_extensions.log")" 'MOCK_PTY_WORKER:repair' '确认执行后日志落盘'
  capture_pty cancel n ''
  expect_equal '' "$(<"$TEST_ROOT/pty-events")" '取消自述不调用 worker'
}
# 统一报告结果，并让任一失败反馈到测试进程退出码。
finish_tests() {
  print -r -- "通过 ${TEST_PASSED}；失败 ${TEST_FAILED}。"
  (( TEST_FAILED == 0 ))
}
# 编排隔离准备、更新集成和独立入口验证。
main() {
  show_test_intro # 说明隔离边界。
  initialize_tests # 创建临时目录并只加载函数定义。
  install_update_mocks # 阻止真实包管理器及网络操作。
  test_update_sequence # 验证更新前后的扫描顺序。
  test_update_worker_failures # 验证构建失败传播。
  test_update_tee_failures # 验证日志失败传播。
  test_cocoapods_sequence # 验证工具升级和 Specs 之间的修复边界。
  test_embedded_copy # 验证单文件实现保持一致。
  prepare_standalone_fixtures # 准备无副作用独立入口和 TTY 驱动。
  test_standalone_entry # 验证单文件运行与非交互保护。
  test_standalone_styles # 验证自述配色与降级。
  test_standalone_prompts # 验证回车跳过和非空执行。
  finish_tests # 汇总并传播测试退出码。
}

main "$@"
