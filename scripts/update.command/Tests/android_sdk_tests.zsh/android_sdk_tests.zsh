# shell: zsh
# 脚本自述：
# - 脚本名称：android_sdk_tests.zsh
# - 核心用途：验证 Flutter Android 工具缺失自愈、许可复检和失败传播。
# - 影响范围：仅使用专属临时目录和假工具，不联网、不安装或升级真实环境。
# - 运行提示：自动运行隔离回归；按 Ctrl+C 可取消。

TEST_SCRIPT_DIR="${${(%):-%x}:A:h}"
TEST_ROOT=''
TEST_COUNT=0
TEST_FAILED=0
# 说明所有包管理器与 Android 工具均由临时假命令替换。
show_test_intro() {
  print -r -- 'Android SDK 隔离回归：不联网、不安装、不升级真实工具。Ctrl+C 可取消。'
}
# 只回收本测试创建的临时根。
TRAPEXIT() {
  [[ -z "$TEST_ROOT" || ! -d "$TEST_ROOT" || "${TEST_ROOT:t}" != jobs-update-android.* ]] || /bin/rm -r -- "$TEST_ROOT"
}
# 从源码包加载函数，不执行真实更新入口。
initialize_tests() {
  setopt NO_NOMATCH
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-update-android.XXXXXXXX")" || return 1
  TEST_ROOT="${TEST_ROOT:A}"
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "${TEST_SCRIPT_DIR:h:h}/update.command" || return 1
}
# 每例独立模拟 Flutter 实际 SDK、引导 SDK、JDK 和 Homebrew。
reset_fixture() {
  export TEST_CASE_DIR="$TEST_ROOT/case-$TEST_COUNT"
  export TEST_CASE_CALLS="$TEST_CASE_DIR/calls"
  export TEST_SDK="$TEST_CASE_DIR/Android SDK"
  export TEST_BOOTSTRAP="$TEST_CASE_DIR/brew/share/android-commandlinetools"
  export TEST_JDK="$TEST_CASE_DIR/Studio JDK"
  export TEST_MANAGER_TEMPLATE="$TEST_CASE_DIR/sdkmanager-template"
  export MOCK_BREW_INSTALLED=0 MOCK_BREW_FAIL=0 MOCK_MANAGER_FAIL=0 MOCK_INSTALL_NO_TARGET=0 MOCK_INSTALL_INVISIBLE_TARGET=0
  export MOCK_LICENSE_FAIL=0 MOCK_LICENSE_FALSE_SUCCESS=0 MOCK_LICENSE_PERSISTENT=0
  export MOCK_LICENSE_HANG=0
  export MOCK_DOCTOR_EXIT=0 MOCK_DOCTOR_FATAL=0 MOCK_NETWORK_ERROR=0 MOCK_DEVICE_WARNING=0
  export MOCK_POST_DOCTOR_EXIT=0 MOCK_POST_DOCTOR_FATAL=0 MOCK_DOCTOR_ABNORMAL=0 MOCK_UNKNOWN_DIAGNOSTIC=0
  JOBS_UPDATE_HEALTH_WARNING_COUNT=0
  export MOCK_FLUTTER="$TEST_CASE_DIR/flutter"
  /bin/mkdir -p "$TEST_SDK" "$TEST_JDK/bin" "$TEST_CASE_DIR/brew/bin"
  : > "$TEST_CASE_CALLS"
  LOG_FILE="$TEST_CASE_DIR/update.log"
  : > "$LOG_FILE"
  JOBS_UPDATE_TRUST_MODE=1
  JOBS_UPDATE_LOG_READY=1
  /bin/cat > "$TEST_JDK/bin/java" <<'MOCK_JAVA'
#!/bin/zsh
exit 0
MOCK_JAVA
  /bin/cat > "$TEST_MANAGER_TEMPLATE" <<'MOCK_MANAGER'
#!/bin/zsh
print -r -- "sdkmanager|$*" >> "$TEST_CASE_CALLS"
case "$*" in
  --version)
    (( MOCK_MANAGER_FAIL == 0 )) || { print -r -- 'UnsupportedClassVersionError'; exit 8; }
    print -r -- '23.0'
    ;;
  *'--install cmdline-tools;latest')
    [[ "$1" == "--sdk_root=$TEST_SDK" ]] || exit 96
    [[ "$JAVA_HOME" == "$TEST_JDK" && "$ANDROID_HOME" == "$TEST_SDK" ]] || exit 95
    (( MOCK_INSTALL_NO_TARGET == 0 )) || exit 0
    if (( MOCK_INSTALL_INVISIBLE_TARGET == 1 )); then
      /bin/mkdir -p "$TEST_SDK/cmdline-tools/jobs-installed/bin"
      /bin/cp "$TEST_MANAGER_TEMPLATE" "$TEST_SDK/cmdline-tools/jobs-installed/bin/sdkmanager"
      exit 0
    fi
    /bin/mkdir -p "$TEST_SDK/cmdline-tools/latest/bin"
    /bin/cp "$TEST_MANAGER_TEMPLATE" "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
    ;;
  *) exit 98 ;;
esac
MOCK_MANAGER
  /bin/cat > "$MOCK_FLUTTER" <<'MOCK_FLUTTER_SCRIPT'
#!/bin/zsh
print -r -- "flutter|$*" >> "$TEST_CASE_CALLS"
case "$*" in
  'doctor -v')
    (( MOCK_DOCTOR_ABNORMAL == 0 )) || exit "$MOCK_DOCTOR_ABNORMAL"
    if (( MOCK_DOCTOR_FATAL == 1 )); then
      print -r -- 'Failed to download sky_engine.zip. SocketException: Connection refused'
      print -r -- 'Android license status unknown.'
      exit 1
    fi
    print -r -- "    • Android SDK at $TEST_SDK"
    print -r -- "    • Java binary at: $TEST_JDK/bin/java"
    if [[ ! -f "$TEST_CASE_DIR/licensed" || "$MOCK_LICENSE_PERSISTENT" == 1 ]]; then
      print -r -- '[!] Android toolchain'
      print -r -- '    ✗ Android license status unknown.'
      print -r -- '      Run flutter doctor --android-licenses'
      exit "$MOCK_DOCTOR_EXIT"
    fi
    if (( MOCK_NETWORK_ERROR == 1 )); then
      print -r -- '[!] Network resources'
      print -r -- '    ✗ A network error occurred while checking "https://maven.google.com/": Operation timed out'
    elif (( MOCK_DEVICE_WARNING == 1 )); then
      print -r -- '[✓] Connected device'
      print -r -- '    ! Error: Browsing on the local area network for iPhone (code -27)'
    else
      print -r -- '[✓] Android toolchain'
    fi
    if (( MOCK_POST_DOCTOR_FATAL == 1 )); then
      print -r -- 'Failed to download sky_engine.zip. SocketException: Connection refused'
      exit 1
    fi
    if (( MOCK_UNKNOWN_DIAGNOSTIC == 1 )); then
      print -r -- '[!] Android toolchain'
      print -r -- '    ✗ Unknown Android validation failure.'
    fi
    exit "$MOCK_POST_DOCTOR_EXIT"
    ;;
  'doctor --android-licenses')
    if (( MOCK_LICENSE_HANG == 1 )); then
      while true; do /bin/sleep 1; done
    fi
    (( MOCK_LICENSE_FALSE_SUCCESS == 0 )) || { print -r -- 'Android sdkmanager not found.'; exit 0; }
    (( MOCK_LICENSE_FAIL == 0 )) || exit 7
    [[ -x "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager" || -x "$TEST_SDK/cmdline-tools/22.0/bin/sdkmanager" ]] || exit 94
    : > "$TEST_CASE_DIR/licensed"
    print -r -- 'All SDK package licenses accepted.'
    ;;
  *) exit 97 ;;
esac
MOCK_FLUTTER_SCRIPT
  /bin/cat > "$TEST_CASE_DIR/brew/bin/brew" <<'MOCK_BREW'
#!/bin/zsh
print -r -- "brew|$*" >> "$TEST_CASE_CALLS"
case "$*" in
  --prefix) print -r -- "$TEST_CASE_DIR/brew" ;;
  'list --cask --versions android-commandlinetools') exit "$(( 1 - MOCK_BREW_INSTALLED ))" ;;
  'install --cask android-commandlinetools'|'reinstall --cask android-commandlinetools')
    (( MOCK_BREW_FAIL == 0 )) || exit 6
    /bin/mkdir -p "$TEST_BOOTSTRAP/cmdline-tools/latest/bin"
    /bin/cp "$TEST_MANAGER_TEMPLATE" "$TEST_BOOTSTRAP/cmdline-tools/latest/bin/sdkmanager"
    ;;
  *) exit 93 ;;
esac
MOCK_BREW
  /bin/chmod +x "$TEST_JDK/bin/java" "$TEST_MANAGER_TEMPLATE" "$MOCK_FLUTTER" "$TEST_CASE_DIR/brew/bin/brew"
  function find_brew_bin() { print -r -- "$TEST_CASE_DIR/brew/bin/brew"; }
  function jobs_update_find_external_command() {
    [[ "$1" == sdkmanager && -x "$TEST_CASE_DIR/external/sdkmanager" ]] || return 1
    print -r -- "$TEST_CASE_DIR/external/sdkmanager"
  }
  function jobs_update_run_brew_update() { print -r -- 'brew-update' >> "$TEST_CASE_CALLS"; }
  function jobs_update_run_brew_adaptive_cmd() { shift 2; "$@"; }
}
# 将健康候选放到指定位置，避免使用宿主机 SDK。
install_manager() {
  /bin/mkdir -p "${1:h}"
  /bin/cp "$TEST_MANAGER_TEMPLATE" "$1"
}
# 统计真实假命令调用，不匹配描述日志。
call_count() {
  /usr/bin/grep -Fc -- "$1" "$TEST_CASE_CALLS" || true
}
# 已有健康 SDK 工具应直接接受许可，不进行安装。
test_healthy() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count 'flutter|doctor -v')" == 2 && "$(call_count 'flutter|doctor --android-licenses')" == 1 ]] || return 1
  [[ "$(call_count 'brew|install')" == 0 && "$(call_count '--install cmdline-tools;latest')" == 0 ]]
}
# 当前 SDK 的版本目录可复用，不强制重复安装 latest。
test_versioned_sdk() {
  install_manager "$TEST_SDK/cmdline-tools/22.0/bin/sdkmanager"
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count '--install cmdline-tools;latest')" == 0 ]]
}
# 重现本机 jobs-* 目录：工具可作引导，但必须补齐 Flutter 可发现的 latest。
test_jobs_directory_bootstrap() {
  install_manager "$TEST_SDK/cmdline-tools/jobs-23.0-ncXbUk/bin/sdkmanager"
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count '--install cmdline-tools;latest')" == 1 && "$(call_count 'brew|install')" == 0 ]] || return 1
  [[ -x "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager" && "$(call_count 'flutter|doctor --android-licenses')" == 1 ]]
}
# 引导工具安装返回零但只留下 jobs-* 时，严格复检必须拒绝继续许可。
test_post_install_invisible() {
  install_manager "$TEST_SDK/cmdline-tools/jobs-23.0-ncXbUk/bin/sdkmanager"
  MOCK_INSTALL_INVISIBLE_TARGET=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count '--install cmdline-tools;latest')" == 1 && "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# 外部 sdkmanager 必须明确安装到 Flutter 实际 SDK。
test_existing_external() {
  install_manager "$TEST_CASE_DIR/external/sdkmanager"
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count '--install cmdline-tools;latest')" == 1 && "$(call_count 'brew|install')" == 0 ]]
}
# 工具全缺时只补引导 cask 一次，再补目标 SDK 并复检。
test_missing_chain() {
  MOCK_DOCTOR_EXIT=1
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count 'brew|install --cask android-commandlinetools')" == 1 && "$(call_count '--install cmdline-tools;latest')" == 1 ]]
}
# 已有 cask 登记而文件残缺时使用 reinstall，不循环重试。
test_broken_cask() {
  MOCK_BREW_INSTALLED=1
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count 'brew|reinstall --cask android-commandlinetools')" == 1 ]]
}
# 引导安装失败后必须停止许可与 doctor 复检。
test_install_failure() {
  MOCK_BREW_FAIL=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'brew|install')" == 1 && "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# 安装器零退出码不能替代目标 sdkmanager 复检。
test_post_install_missing() {
  MOCK_INSTALL_NO_TARGET=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count '--install cmdline-tools;latest')" == 1 && "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# 可执行文件存在但版本检查失败时不能继续接受许可。
test_unhealthy_manager() {
  MOCK_MANAGER_FAIL=1
  install_manager "$TEST_CASE_DIR/external/sdkmanager"
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# 许可命令即使返回零，明确缺失工具输出也必须失败。
test_false_license_success() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_LICENSE_FALSE_SUCCESS=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'flutter|doctor -v')" == 1 ]]
}
# 许可接受后仍未知，复检必须保留失败结果。
test_license_still_unknown() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_LICENSE_PERSISTENT=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'flutter|doctor -v')" == 2 ]]
}
# 实际下载失败不继续执行 Android 安装。
test_flutter_fatal() {
  MOCK_DOCTOR_FATAL=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'brew|')" == 0 && "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# Android 自愈后网络健康探测失败单独汇总，不覆盖已经完成的 SDK 更新。
test_network_warning() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_NETWORK_ERROR=1
  MOCK_POST_DOCTOR_EXIT=1
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ -f "$TEST_CASE_DIR/licensed" && "$JOBS_UPDATE_HEALTH_WARNING_COUNT" == 1 ]]
}
# 网络健康标题不能掩盖真正的 SDK 资源下载失败。
test_network_and_download_failure() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_NETWORK_ERROR=1
  MOCK_POST_DOCTOR_FATAL=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && (( JOBS_UPDATE_HEALTH_WARNING_COUNT == 0 ))
}
# 未识别的 Android 验证失败不能因同时出现网络健康告警被洗成成功。
test_network_and_unknown_failure() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_NETWORK_ERROR=1
  MOCK_UNKNOWN_DIAGNOSTIC=1
  MOCK_POST_DOCTOR_EXIT=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 ))
}
# doctor 启动后异常退出且没有结构化诊断，必须保留失败。
test_doctor_abnormal_exit() {
  MOCK_DOCTOR_ABNORMAL=2
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# 设备离线提醒不应被解释为 SDK 升级或许可失败。
test_device_warning() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_DEVICE_WARNING=1
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  (( JOBS_UPDATE_HEALTH_WARNING_COUNT == 1 ))
}
# JDK 和 SDK 定向只在函数内有效，返回后保留调用者原状态。
test_environment_scope() {
  export JAVA_HOME="$TEST_CASE_DIR/original-java" ANDROID_HOME="$TEST_CASE_DIR/original-sdk"
  unset ANDROID_SDK_ROOT
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$JAVA_HOME" == "$TEST_CASE_DIR/original-java" && "$ANDROID_HOME" == "$TEST_CASE_DIR/original-sdk" && "${+ANDROID_SDK_ROOT}" == 0 ]]
}
# 许可子进程卡住时受总时限约束，不能继续写入接受标记或执行 doctor。
test_license_timeout() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  export JOBS_ANDROID_SDK_TIMEOUT=1 MOCK_LICENSE_HANG=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ ! -e "$TEST_CASE_DIR/licensed" && "$(call_count 'flutter|doctor -v')" == 1 ]]
}
# 用子 Shell 隔离函数替换及环境变量，不污染下一例。
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
# 覆盖依赖链健康、缺失、修复失败、复检失败及环境作用域。
run_tests() {
  run_case '健康 SDK 直接接受许可' test_healthy
  run_case '版本化 SDK 工具复用' test_versioned_sdk
  run_case 'jobs-* 目录只作引导并补 latest' test_jobs_directory_bootstrap
  run_case '安装后仅不可见目录时停止' test_post_install_invisible
  run_case '外部引导工具定向修复' test_existing_external
  run_case '多层缺失一次自愈' test_missing_chain
  run_case '残缺 cask 一次重装' test_broken_cask
  run_case '引导安装失败停止' test_install_failure
  run_case '安装后无工具不误报成功' test_post_install_missing
  run_case 'sdkmanager 可执行但不健康' test_unhealthy_manager
  run_case '许可零码错误输出不误报成功' test_false_license_success
  run_case '许可接受后仍未知' test_license_still_unknown
  run_case 'Flutter 下载失败停止' test_flutter_fatal
  run_case '网络健康告警和升级结果分开' test_network_warning
  run_case '网络告警不掩盖实际下载失败' test_network_and_download_failure
  run_case '网络告警不掩盖未知验证失败' test_network_and_unknown_failure
  run_case 'doctor 异常退出保留失败' test_doctor_abnormal_exit
  run_case '设备离线提醒不误判' test_device_warning
  run_case 'JDK 与 SDK 环境作用域' test_environment_scope
  run_case '许可卡住时总时限退出' test_license_timeout
  print -r -- "完成：$TEST_COUNT 项，失败 $TEST_FAILED 项。"
  (( TEST_FAILED == 0 ))
}
# 编排自述、源码加载和隔离回归。
main() {
  show_test_intro # 说明测试范围和取消方式。
  initialize_tests # 建立私有目录并加载源码函数。
  run_tests # 执行必要依赖与失败传播回归。
}

main "$@"
