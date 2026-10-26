#!/bin/zsh
# 脚本自述：
# - 脚本名称：flutter_gem_tests.zsh
# - 核心用途：隔离验证 Flutter 失败传播、FVM 固定版本保护与 Gem 用户目录回退。
# - 影响范围：仅使用专属临时目录和假命令，不联网、不升级真实 SDK 或 Gem。
# - 运行提示：自动执行回归；按 Ctrl+C 可取消。

TEST_SCRIPT_DIR="${${(%):-%x}:A:h}"
TEST_ROOT=''
TEST_COUNT=0
TEST_FAILED=0
TEST_QUARANTINE_BODY=''

# 只清理本测试自己创建的目录。
cleanup_tests() {
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" && "${TEST_ROOT:t}" == .jobs-flutter-gem-tests.* ]]; then
    /bin/rm -r -- "$TEST_ROOT"
  fi
}
# 在整个测试进程结束时清理，避免 zsh 的函数内 EXIT trap 提前触发。
TRAPEXIT() {
  cleanup_tests
}
# 使用 HOME 内的临时根验证真实的用户目录范围检查，不修改 HOME。
initialize_tests() {
  setopt NO_NOMATCH
  print -r -- 'Flutter / Gem 隔离回归：只运行假命令；不联网、不安装、不升级。'
  TEST_ROOT="$(/usr/bin/mktemp -d "$HOME/.jobs-flutter-gem-tests.XXXXXXXX")" || return 1
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "${TEST_SCRIPT_DIR:h}/update.command" || return 1
  TEST_QUARANTINE_BODY="${functions[jobs_update_flutter_release_verified_quarantine]}"
}
# 每个用例有独立目录；所有命令均明确替换，避免调用宿主工具链。
reset_fixture() {
  export TEST_CASE_DIR="$TEST_ROOT/case-$TEST_COUNT"
  export TEST_CASE_CALLS="$TEST_CASE_DIR/calls"
  /bin/mkdir -p "$TEST_CASE_DIR/shared/plugins" "$TEST_CASE_DIR/shared/bin" "$TEST_CASE_DIR/user/bin" "$TEST_CASE_DIR/sdk/bin"
  : > "$TEST_CASE_CALLS"
  LOG_FILE="$TEST_CASE_DIR/log"
  : > "$LOG_FILE"
  export MOCK_UPGRADE_RESULT=0 MOCK_DOCTOR_RESULT=0 MOCK_DOCTOR_LICENSE=0 MOCK_DOCTOR_ERROR_OUTPUT=0 MOCK_GEM_RESULT=0 MOCK_USER_VISIBLE=1 MOCK_POST_USER_VISIBLE=1
  MOCK_RUBY_PATH='/opt/homebrew/Cellar/ruby/4.0.9/bin/ruby'
  MOCK_GEM_HOME="$TEST_CASE_DIR/shared"
  MOCK_GEM_BIN="$TEST_CASE_DIR/shared/bin"
  MOCK_GEM_USER="$TEST_CASE_DIR/user"
  MOCK_FLUTTER="$TEST_CASE_DIR/sdk/bin/flutter"
  FVM_CACHE_PATH="$TEST_CASE_DIR/fvm"
  JOBS_UPDATE_TRUST_MODE=1
  /bin/cat > "$MOCK_FLUTTER" <<'MOCK_FLUTTER_SCRIPT'
#!/bin/zsh
print -r -- "flutter|$*" >> "$TEST_CASE_CALLS"
case "$*" in
  upgrade) exit "$MOCK_UPGRADE_RESULT" ;;
  'doctor -v')
    [[ "$MOCK_DOCTOR_LICENSE" != 1 ]] || print -r -- 'Android license status unknown. Run flutter doctor --android-licenses.'
    if (( MOCK_DOCTOR_RESULT != 0 || MOCK_DOCTOR_ERROR_OUTPUT == 1 )); then
      print -r -- 'Failed to download sky_engine.zip. SocketException: Connection refused'
    fi
    exit "$MOCK_DOCTOR_RESULT"
    ;;
  'doctor --android-licenses') exit 0 ;;
  *) exit 98 ;;
esac
MOCK_FLUTTER_SCRIPT
  /bin/chmod +x "$MOCK_FLUTTER"
  function jobs_update_has() { return 1; }
  function jobs_update_find_external_command() { print -r -- "$MOCK_FLUTTER"; }
  function jobs_update_flutter_release_verified_quarantine() { print -r -- 'quarantine' >> "$TEST_CASE_CALLS"; }
  function jobs_update_repair_gem_extensions() { return 0; }
  function gem() {
    print -r -- "gem|$*" >> "$TEST_CASE_CALLS"
    case "$*" in
      env)
        print -r -- "  - INSTALLATION DIRECTORY: $MOCK_GEM_HOME"
        print -r -- "  - EXECUTABLE DIRECTORY: $MOCK_GEM_BIN"
        print -r -- "  - RUBY EXECUTABLE: $MOCK_RUBY_PATH"
        ;;
      'env user_gemhome') print -r -- "$MOCK_GEM_USER" ;;
      'env path')
        local visible="$MOCK_USER_VISIBLE"
        [[ ! -f "$TEST_CASE_DIR/gem-updated" ]] || visible="$MOCK_POST_USER_VISIBLE"
        if (( visible == 1 )); then
          print -r -- "$MOCK_GEM_HOME:$MOCK_GEM_USER"
        else
          print -r -- "$MOCK_GEM_HOME"
        fi
        ;;
      update*)
        : > "$TEST_CASE_DIR/gem-updated"
        return "$MOCK_GEM_RESULT"
        ;;
      *) return 97 ;;
    esac
  }
}
# 精确检查模拟调用，避免匹配描述行造成假通过。
assert_call() {
  /usr/bin/grep -Fxq -- "$1" "$TEST_CASE_CALLS" || {
    print -u2 -r -- "缺少调用：$1"
    /bin/cat "$TEST_CASE_CALLS" >&2
    return 1
  }
}
# 确认失败分支没有继续执行后续写操作。
assert_no_call() {
  if /usr/bin/grep -Fq -- "$1" "$TEST_CASE_CALLS"; then
    print -u2 -r -- "不应出现调用：$1"
    return 1
  fi
}
# 在共享 home 可写时保留原安装来源和明确验证的写入位置。
test_gem_shared() {
  jobs_update_gem_packages 'gem update' || return 1
  assert_call "gem|update --no-user-install --install-dir $MOCK_GEM_HOME --bindir $MOCK_GEM_BIN" || return 1
  assert_no_call '--user-install --bindir'
}
# 复现日志中的只读 rdoc 插件；必须回退用户目录而不是发起 sudo。
test_gem_readonly_plugin() {
  print -r -- 'old plugin' > "$MOCK_GEM_HOME/plugins/rdoc_plugin.rb"
  /bin/chmod 400 "$MOCK_GEM_HOME/plugins/rdoc_plugin.rb"
  jobs_update_gem_packages 'gem update' || return 1
  assert_call "gem|update --user-install --bindir $MOCK_GEM_USER/bin" || return 1
  [[ ":$PATH:" == *":$MOCK_GEM_USER/bin:"* ]] || return 1
  [[ "$(/bin/cat "$MOCK_GEM_HOME/plugins/rdoc_plugin.rb")" == 'old plugin' ]] || return 1
  assert_no_call 'sudo'
}
# 当前 Ruby 搜索不到用户目录时，不能安装后再误报可用。
test_gem_user_not_visible() {
  /bin/chmod 500 "$MOCK_GEM_HOME/plugins"
  MOCK_USER_VISIBLE=0
  local result=0
  jobs_update_gem_packages 'gem update' || result=$?
  /bin/chmod 700 "$MOCK_GEM_HOME/plugins"
  (( result != 0 )) || return 1
  assert_no_call 'gem|update'
}
# 用户 Gem 目录仍不可写时明确失败，不扩大权限。
test_gem_user_not_writable() {
  /bin/chmod 500 "$MOCK_GEM_HOME/plugins" "$MOCK_GEM_USER/bin"
  local result=0
  jobs_update_gem_packages 'gem update' || result=$?
  /bin/chmod 700 "$MOCK_GEM_HOME/plugins" "$MOCK_GEM_USER/bin"
  (( result != 0 )) || return 1
  assert_no_call 'gem|update'
}
# 用户升级失败或升级后 Ruby 搜索路径失效，必须传播失败且不前置 PATH。
test_gem_user_failure() {
  /bin/chmod 500 "$MOCK_GEM_HOME/plugins"
  MOCK_GEM_RESULT=7
  local result=0 original_path="$PATH"
  jobs_update_gem_packages 'gem update' || result=$?
  /bin/chmod 700 "$MOCK_GEM_HOME/plugins"
  (( result == 7 )) && [[ "$PATH" == "$original_path" ]]
}
# 用户 bin 不能通过符号链接重新写到共享目录。
test_gem_user_symlink() {
  /bin/chmod 500 "$MOCK_GEM_HOME/plugins"
  /bin/rmdir "$MOCK_GEM_USER/bin"
  /bin/ln -s "$MOCK_GEM_BIN" "$MOCK_GEM_USER/bin"
  local result=0
  jobs_update_gem_packages 'gem update' || result=$?
  /bin/chmod 700 "$MOCK_GEM_HOME/plugins"
  (( result != 0 )) || return 1
  assert_no_call 'gem|update'
}
# 更新完成但当前 Ruby 搜索范围发生变化时，仍然明确返回失败。
test_gem_post_visibility() {
  /bin/chmod 500 "$MOCK_GEM_HOME/plugins"
  MOCK_POST_USER_VISIBLE=0
  local result=0 original_path="$PATH"
  jobs_update_gem_packages 'gem update' || result=$?
  /bin/chmod 700 "$MOCK_GEM_HOME/plugins"
  (( result != 0 )) && [[ "$PATH" == "$original_path" ]]
}
# 用户 Gem 回退加入 PATH 后，已有 Homebrew pod 不能被用户 bin 抢占。
test_gem_preserves_active_pod() {
  /bin/mkdir -p "$TEST_CASE_DIR/brew-bin"
  print -r -- '#!/bin/zsh' > "$TEST_CASE_DIR/brew-bin/pod"
  print -r -- '#!/bin/zsh' > "$MOCK_GEM_USER/bin/pod"
  /bin/chmod +x "$TEST_CASE_DIR/brew-bin/pod" "$MOCK_GEM_USER/bin/pod"
  export PATH="$TEST_CASE_DIR/brew-bin:$PATH"
  /bin/chmod 500 "$MOCK_GEM_HOME/plugins"
  jobs_update_gem_packages 'gem update' || return 1
  /bin/chmod 700 "$MOCK_GEM_HOME/plugins"
  [[ "$(whence -p pod)" == "$TEST_CASE_DIR/brew-bin/pod" ]]
}
# RubyGems 本体由 Homebrew 管理时，不执行 gem update --system。
test_brew_rubygems() {
  jobs_update_rubygems_system || return 1
  assert_no_call 'gem|update --system'
}
# 子命令失败必须使 Ruby 更新项失败，扩展复检成功不能覆盖它。
test_ruby_result() {
  function jobs_update_has() { [[ "$1" == gem ]]; }
  MOCK_GEM_RESULT=8
  local result=0
  jobs_update_ruby_base || result=$?
  (( result != 0 ))
}
# 独立 SDK 升级失败后不运行 quarantine 或 doctor。
test_flutter_upgrade_failure() {
  MOCK_UPGRADE_RESULT=1
  local result=0
  jobs_update_fvm_flutter || result=$?
  (( result != 0 )) || return 1
  assert_call 'flutter|upgrade' || return 1
  assert_no_call 'quarantine' || return 1
  assert_no_call 'flutter|doctor'
}
# FVM default 指向固定版本时，原缓存不被直接 upgrade 或 doctor 改写。
test_fvm_pinned() {
  /bin/mkdir -p "$FVM_CACHE_PATH/versions/3.38.0/bin"
  /bin/cp "$MOCK_FLUTTER" "$FVM_CACHE_PATH/versions/3.38.0/bin/flutter"
  /bin/ln -s "$FVM_CACHE_PATH/versions/3.38.0" "$FVM_CACHE_PATH/default"
  MOCK_FLUTTER="$FVM_CACHE_PATH/default/bin/flutter"
  jobs_update_fvm_flutter || return 1
  assert_no_call 'flutter|'
}
# FVM 频道缓存仍按官方 Flutter 频道升级流程处理。
test_fvm_channel() {
  /bin/mkdir -p "$FVM_CACHE_PATH/versions/stable/bin"
  /bin/cp "$MOCK_FLUTTER" "$FVM_CACHE_PATH/versions/stable/bin/flutter"
  /bin/ln -s "$FVM_CACHE_PATH/versions/stable" "$FVM_CACHE_PATH/default"
  MOCK_FLUTTER="$FVM_CACHE_PATH/default/bin/flutter"
  jobs_update_fvm_flutter || return 1
  assert_call 'flutter|upgrade' || return 1
  assert_call 'quarantine' || return 1
  assert_call 'flutter|doctor -v'
}
# doctor 下载失败不能因日志清理或许可提示而变成成功。
test_doctor_failure() {
  MOCK_DOCTOR_RESULT=1
  MOCK_DOCTOR_LICENSE=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) || return 1
  assert_no_call 'flutter|doctor --android-licenses'
}
# 即使 doctor 返回零，明确的资源下载错误也不能报成功。
test_doctor_false_success() {
  MOCK_DOCTOR_ERROR_OUTPUT=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 ))
}
# 仅替换系统依赖，继续执行生产隔离标记函数本体。
install_quarantine_mocks() {
  local quarantine_body="${TEST_QUARANTINE_BODY//\/usr\/bin\/codesign/mock_codesign}"
  quarantine_body="${quarantine_body//\/usr\/bin\/xattr/mock_xattr}"
  eval "jobs_update_flutter_release_verified_quarantine() { $quarantine_body }"
  /bin/mkdir -p "$TEST_CASE_DIR/sdk/bin/cache/dart-sdk/bin"
  /bin/cp "$MOCK_FLUTTER" "$TEST_CASE_DIR/sdk/bin/cache/dart-sdk/bin/dart"
  function mock_codesign() {
    print -r -- 'Authority=Developer ID Application: FLUTTER.IO LLC (S8QB4VV633)'
  }
  function mock_xattr() {
    print -r -- "xattr|$*" >> "$TEST_CASE_CALLS"
  }
  function find() {
    local count=0
    [[ ! -f "$TEST_CASE_DIR/find-count" ]] || count="$(<"$TEST_CASE_DIR/find-count")"
    (( count += 1 ))
    print -r -- "$count" > "$TEST_CASE_DIR/find-count"
    (( count != MOCK_FIND_FAIL_AT )) || return 1
    if (( count == 1 )); then
      print -r -- "$TEST_CASE_DIR/sdk/quarantined-file"
    fi
    return 0
  }
}
# 查询失败不等于 SDK 无隔离标记。
test_quarantine_initial_query_failure() {
  install_quarantine_mocks
  MOCK_FIND_FAIL_AT=1
  local result=0
  jobs_update_flutter_release_verified_quarantine "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) || return 1
  assert_no_call 'xattr|' || return 1
  ! /usr/bin/grep -Fq 'Flutter SDK 无 quarantine 标记' "$LOG_FILE"
}
# 清理后的查询失败也不能输出已全部解除。
test_quarantine_final_query_failure() {
  install_quarantine_mocks
  MOCK_FIND_FAIL_AT=3
  local result=0
  jobs_update_flutter_release_verified_quarantine "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) || return 1
  ! /usr/bin/grep -Fq '并解除 Flutter SDK quarantine 标记' "$LOG_FILE"
}
# 链接查询失败不能被命令替换或空列表掩盖。
test_quarantine_link_query_failure() {
  install_quarantine_mocks
  MOCK_FIND_FAIL_AT=2
  local result=0
  jobs_update_flutter_release_verified_quarantine "$MOCK_FLUTTER" || result=$?
  (( result != 0 ))
}
# 子 shell 隔离 PATH 和函数替换，每个测试都从独立目录开始。
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
# 运行与用户日志直接相关的回归，不触发真实更新入口。
run_tests() {
  run_case '正常 Gem 保留原来源' test_gem_shared
  run_case '只读 rdoc 插件回退用户目录' test_gem_readonly_plugin
  run_case '用户 Gem 不可见时停止' test_gem_user_not_visible
  run_case '用户 bin 不可写时停止' test_gem_user_not_writable
  run_case '用户 Gem 升级失败不激活 PATH' test_gem_user_failure
  run_case '用户 bin 链接越界停止' test_gem_user_symlink
  run_case '用户 Gem 更新后搜索范围复检' test_gem_post_visibility
  run_case '用户回退保留活跃 Brew pod 来源' test_gem_preserves_active_pod
  run_case 'Homebrew RubyGems 本体保留包管理器管理' test_brew_rubygems
  run_case 'Ruby 子步骤失败不被复检覆盖' test_ruby_result
  run_case 'Flutter 升级失败停止后续 SDK 操作' test_flutter_upgrade_failure
  run_case 'FVM 固定版本保护' test_fvm_pinned
  run_case 'FVM 频道缓存允许升级' test_fvm_channel
  run_case 'doctor 网络失败传播' test_doctor_failure
  run_case 'doctor 零退出码下载错误仍失败' test_doctor_false_success
  run_case 'SDK 隔离标记初次查询失败' test_quarantine_initial_query_failure
  run_case 'SDK 隔离标记最终复检失败' test_quarantine_final_query_failure
  run_case 'SDK 隔离标记链接查询失败' test_quarantine_link_query_failure
  print -r -- "完成：$TEST_COUNT 项，失败 $TEST_FAILED 项。"
  (( TEST_FAILED == 0 ))
}
# 编排隔离初始化和回归。
main() {
  initialize_tests # 加载函数并建立仅使用模拟命令的隔离环境。
  run_tests # 验证用户日志涉及的错误和必要保护分支。
}

main "$@"
