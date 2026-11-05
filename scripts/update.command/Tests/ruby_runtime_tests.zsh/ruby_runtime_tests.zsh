#!/bin/zsh
# 脚本自述：
# - 脚本名称：ruby_runtime_tests.zsh
# - 核心用途：隔离验证 Gem 更新始终使用原生扩展检查选定的 Ruby。
# - 影响范围：仅写专属临时夹具；不联网、不调用真实 RubyGems、不升级软件。
# - 运行提示：自动运行；按 Ctrl+C 可取消。

TEST_SCRIPT_DIR="${${(%):-%x}:A:h}"
TEST_ROOT=''
TEST_COUNT=0
TEST_FAILED=0

# 只清理当前测试创建的临时目录。
cleanup_tests() {
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" && "${TEST_ROOT:t}" == jobs-ruby-runtime.* ]]; then
    /bin/rm -r -- "$TEST_ROOT"
  fi
}
# 在进程退出时清理隔离夹具。
TRAPEXIT() {
  cleanup_tests
}
# 加载函数而不启动 update，并创建与真实工具链无关的假 Ruby 和旧 gem。
initialize_tests() {
  setopt NO_NOMATCH
  print -r -- 'Ruby 运行时隔离回归：只运行专属夹具，不联网、不升级。'
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-ruby-runtime.XXXXXXXX")" || return 1
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "${TEST_SCRIPT_DIR:h:h}/update.command" || return 1
  /bin/mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/Cellar/ruby/4.0.9/bin" "$TEST_ROOT/gems/bin" || return 1
  /bin/cat > "$TEST_ROOT/Cellar/ruby/4.0.9/bin/ruby" <<'MOCK_RUBY'
#!/bin/zsh
print -r -- "ruby|$*" >> "$MOCK_ROOT/calls"
[[ "$*" == '--disable-gems -rrubygems/gem_runner -e Gem::GemRunner.new.run(ARGV) -- '* ]] || exit 97
[[ -z "${RUBYOPT+x}${RUBYLIB+x}${RUBYGEMS_GEMDEPS+x}${BUNDLE_GEMFILE+x}${BUNDLE_BIN_PATH+x}" ]] || exit 96
shift 5
case "$*" in
  env)
    [[ "${MOCK_ENV_FAILURE:-0}" == 0 ]] || exit 7
    print -r -- "  - INSTALLATION DIRECTORY: $MOCK_ROOT/gems"
    print -r -- "  - EXECUTABLE DIRECTORY: $MOCK_ROOT/gems/bin"
    print -r -- "  - RUBY EXECUTABLE: ${MOCK_REPORTED_RUBY:-$MOCK_SELECTED_RUBY}"
    ;;
  'update --system') exit 95 ;;
  'update --no-user-install --install-dir '*) exit "${MOCK_UPDATE_RESULT:-0}" ;;
  *) exit 94 ;;
esac
MOCK_RUBY
  /bin/cat > "$TEST_ROOT/bin/gem" <<'MOCK_OLD_GEM'
#!/bin/zsh
print -r -- 'wrong-system-gem' >> "$MOCK_ROOT/calls"
exit 93
MOCK_OLD_GEM
  /bin/chmod +x "$TEST_ROOT/Cellar/ruby/4.0.9/bin/ruby" "$TEST_ROOT/bin/gem" || return 1
}
# 每个用例使用独立调用记录，清除上次解析出的运行时。
reset_fixture() {
  export MOCK_ROOT="$TEST_ROOT" MOCK_SELECTED_RUBY="$TEST_ROOT/Cellar/ruby/4.0.9/bin/ruby"
  export MOCK_ENV_FAILURE=0 MOCK_UPDATE_RESULT=0
  unset MOCK_REPORTED_RUBY JOBS_UPDATE_GEM_CURRENT_RUBY JOBS_UPDATE_GEM_CURRENT_HOME JOBS_UPDATE_GEM_CURRENT_BIN
  export PATH="$TEST_ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  : > "$TEST_ROOT/calls"
  LOG_FILE="$TEST_ROOT/test.log"
  : > "$LOG_FILE"
  function jobs_gemext_find_ruby() { print -r -- "$MOCK_SELECTED_RUBY"; }
}
# 确认旧 gem 没有获得任何读取或更新调用。
assert_old_gem_unused() {
  ! /usr/bin/grep -Fq -- wrong-system-gem "$TEST_ROOT/calls"
}
# 复现 PATH 中 gem 为旧解释器时，更新仍绑定原生扩展所选的 Ruby。
test_runtime_binding() {
  export RUBYOPT='invalid injected option' RUBYLIB='/invalid/injected' RUBYGEMS_GEMDEPS='invalid'
  export BUNDLE_GEMFILE='/invalid/Gemfile' BUNDLE_BIN_PATH='/invalid/bundle'
  jobs_update_gem_packages '更新 Gem' || return 1
  [[ "$JOBS_UPDATE_GEM_CURRENT_RUBY" == "$MOCK_SELECTED_RUBY" ]] || return 1
  /usr/bin/grep -Fq -- "-- update --no-user-install --install-dir $TEST_ROOT/gems --bindir $TEST_ROOT/gems/bin --no-document" "$TEST_ROOT/calls" || return 1
  [[ "$RUBYOPT" == 'invalid injected option' ]] || return 1
  assert_old_gem_unused
}
# Homebrew Ruby 的 RubyGems 本体继续交给 Homebrew 维护。
test_homebrew_system_guard() {
  jobs_update_rubygems_system || return 1
  ! /usr/bin/grep -Fq -- '-- update --system' "$TEST_ROOT/calls" || return 1
  assert_old_gem_unused
}
# 所选 Ruby 的 RubyGems 读取失败时，不回退旧 gem 或继续更新。
test_environment_failure() {
  MOCK_ENV_FAILURE=1
  local result=0
  jobs_update_gem_packages '更新 Gem' || result=$?
  (( result != 0 )) || return 1
  ! /usr/bin/grep -Fq -- '-- update' "$TEST_ROOT/calls" || return 1
  assert_old_gem_unused
}
# 返回的环境若属于另一解释器，拒绝写入该目录。
test_runtime_mismatch() {
  export MOCK_REPORTED_RUBY='/usr/bin/ruby'
  local result=0
  jobs_update_gem_packages '更新 Gem' || result=$?
  (( result != 0 )) || return 1
  ! /usr/bin/grep -Fq -- '-- update' "$TEST_ROOT/calls" || return 1
  assert_old_gem_unused
}
# RubyGems 更新的真实失败退出码不能被环境查询覆盖。
test_update_failure() {
  MOCK_UPDATE_RESULT=8
  local result=0
  jobs_update_gem_packages '更新 Gem' || result=$?
  (( result == 8 )) || return 1
  assert_old_gem_unused
}
# PATH 缺少 gem 启动器时，已有 Ruby 自带的 RubyGems 仍然可维护。
test_ruby_without_gem_launcher() {
  function jobs_update_has() { [[ "$1" == ruby ]]; }
  function jobs_update_repair_gem_extensions() { return 0; }
  jobs_update_ruby_base || return 1
  /usr/bin/grep -Fq -- '-- update --no-user-install' "$TEST_ROOT/calls" || return 1
  assert_old_gem_unused
}
# 子 Shell 隔离测试注入与调用状态。
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
# 运行解释器绑定、管理边界和失败传播用例。
run_tests() {
  run_case 'Gem 与原生扩展使用同一 Ruby' test_runtime_binding
  run_case '保留 Homebrew RubyGems 管理权' test_homebrew_system_guard
  run_case '所选 RubyGems 缺失时停止' test_environment_failure
  run_case '环境解释器错配时停止' test_runtime_mismatch
  run_case 'Gem 更新失败传播' test_update_failure
  run_case '已有 Ruby 不依赖 PATH 的 gem 启动器' test_ruby_without_gem_launcher
  print -r -- "完成：$TEST_COUNT 项，失败 $TEST_FAILED 项。"
  (( TEST_FAILED == 0 ))
}
# 编排隔离初始化与测试，不启动真实升级入口。
main() {
  initialize_tests # 建立假 Ruby、旧 gem 和独立日志。
  run_tests # 验证解释器选择及必要保护分支。
}

main "$@"
