#!/bin/zsh
# 脚本自述：隔离验证SDK适配、真实BrewURL、source安全和失败传播；不联网、不运行真实SDK。
setopt NO_NOMATCH
TEST_DIR="${${(%):-%x}:A:h}"
LIB_ROOT="${TEST_DIR:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp/}JobsFlutterSDKAdapter.XXXXXXXX")" || exit 1
TEST_COUNT=0
TEST_ASSERTIONS=0
TEST_FAILURES=0
# 仅清理本夹具创建的目录。
TRAPEXIT() { [[ -d "$TEST_ROOT" && "${TEST_ROOT:t}" == JobsFlutterSDKAdapter.* ]] && /bin/rm -r -- "$TEST_ROOT"; }
# 每个用例复制资源到中文空格路径；下载层完全替换，不可能调用真实网络模块。
fixture() {
  export TEST_CASE="$TEST_ROOT/中文 空格/$TEST_COUNT" TEST_TRACE="$TEST_ROOT/trace-$TEST_COUNT"
  /bin/mkdir -p "$TEST_CASE/Scripts/【MacOS】FlutterSDK网络选路.zsh" "$TEST_CASE/Scripts/【MacOS】FlutterSDK命令适配.sh" "$TEST_CASE/Scripts/【MacOS】SDK获取重试.zsh" "$TEST_CASE/sdk/bin/internal" "$TEST_CASE/sdk/bin/cache/dart-sdk/bin" "$TEST_CASE/bin" "$TEST_CASE/project"
  /bin/cp "$LIB_ROOT/【MacOS】FlutterSDK命令适配.sh/【MacOS】FlutterSDK命令适配.sh" "$TEST_CASE/Scripts/【MacOS】FlutterSDK命令适配.sh/"
  TEST_ADAPTER="$TEST_CASE/Scripts/【MacOS】FlutterSDK命令适配.sh/【MacOS】FlutterSDK命令适配.sh"
  : > "$TEST_TRACE"
  export JOBS_FLUTTER_ROUTE_LOG="$TEST_CASE/sdk.log" MOCK_BUSINESS_STATUS=0 MOCK_INITIAL_STATUS=0 MOCK_METADATA_FAIL_ONCE=0 MOCK_METADATA_FATAL=0 MOCK_DART_PREFIX_MISSING=0 MOCK_FVM_RUNTIME_STATUS=0 MOCK_CHECK_LOG_OFFSET=0
  unset JOBS_FLUTTER_ROUTE_SDK_ROOT JOBS_FLUTTER_ROUTE_VERSION FLUTTER_PREBUILT_ENGINE_VERSION
  /bin/cat > "$TEST_CASE/Scripts/【MacOS】FlutterSDK网络选路.zsh/【MacOS】FlutterSDK网络选路.zsh" <<'NETWORK'
#!/bin/zsh
if [[ "$ZSH_EVAL_CONTEXT" != toplevel ]]; then
  function jfs_fvm_timed() { "$@"; }
  function jfs_route_note() { print -r -- "$2" >> "$1"; }
  function jfs_route_stop_tree() { kill -TERM "$1" 2>/dev/null || true; }
  function jobs_flutter_sdk_retry() {
    print -r -- "source-route|${JOBS_FLUTTER_ROUTE_MODE:-dart}|${JOBS_FLUTTER_ROUTE_SOURCE_URL:-}|$4" >> "$TEST_TRACE"
    export JOBS_FLUTTER_ROUTE_OBJECT_PATH=flutter_infra_release/releases/stable/macos/fixture.zip
    export JOBS_FLUTTER_ROUTE_EXPECTED_SHA256="${MOCK_ARCHIVE_SHA:-}"
    JFS_SIZE="${MOCK_ARCHIVE_SIZE:-0}"
    shift 4
    "$@"
  }
  function jobs_flutter_route_prepare() { print -r -- "provider-probe|$JOBS_FLUTTER_ROUTE_SOURCE_URL" >> "$TEST_TRACE"; return 75; }
  function jobs_flutter_route_invalidate() { :; }
  return 0
fi
if [[ "$1" == --fvm-runtime ]]; then print -r -- 'runtime-gate' >> "$TEST_TRACE"; exit "$MOCK_FVM_RUNTIME_STATUS"; fi
if [[ "$1" == --cache-dir ]]; then
  dir="$(mktemp -d "$TEST_CASE/cache.XXXXXX")" || exit 1
  /bin/chmod 700 "$dir"; : > "$dir/.jobs-sdk-route"; print -r -- "$dir"; exit 0
fi
[[ "${MOCK_CHECK_LOG_OFFSET:-0}" != 1 ]] || print -r -- "log-offset|${JOBS_SDK_LOG_REPLACED:-unset}" >> "$TEST_TRACE"
print -r -- "route|$1|${JOBS_FLUTTER_ROUTE_MODE:-dart}|${JOBS_FLUTTER_ROUTE_SOURCE_URL:-}|${JOBS_FLUTTER_ROUTE_CAPTURE_OUTPUT:-0}" >> "$TEST_TRACE"
[[ -z "${JOBS_FLUTTER_ROUTE_CURL_CONFIG:-}" ]] || print -r -- "provider|$JOBS_FLUTTER_ROUTE_CURL_CONFIG|${JOBS_FLUTTER_ROUTE_PREPARE_ONCE:-0}" >> "$TEST_TRACE"
if [[ "$1" == --fvm-install ]]; then
  shift 3
  manager=$1 version=$2
  shift 2
  "$manager" install "$version" "$@"
else
  shift 5
  "$@"
fi
NETWORK
  /bin/cat > "$TEST_CASE/Scripts/【MacOS】SDK获取重试.zsh/【MacOS】SDK获取重试.zsh" <<'RETRY'
#!/bin/zsh
function jobs_sdk_retry() { shift 2; "$@"; }
RETRY
  /bin/cat > "$TEST_CASE/bin/curl" <<'CURL'
#!/bin/zsh
while (( $# )); do
 if [[ "$1" == --output ]]; then shift; /bin/cp "$MOCK_ARCHIVE_PAYLOAD" "$1"; exit 0; fi
 shift
done
exit 99
CURL
  /bin/chmod +x "$TEST_CASE/bin/curl"
  /bin/cat > "$TEST_CASE/sdk/bin/flutter" <<'FLUTTER'
#!/bin/zsh
print -r -- "flutter|${(j:|:)@}" >> "$TEST_TRACE"
[[ "$1" != --version ]] || exit "$MOCK_INITIAL_STATUS"
if [[ "$1" == run && "$2" == --stdin ]]; then IFS= read -r line; print -r -- "stdin|$line" >> "$TEST_TRACE"; fi
exit "$MOCK_BUSINESS_STATUS"
FLUTTER
  /bin/cat > "$TEST_CASE/sdk/bin/dart" <<'DART'
#!/bin/zsh
print -r -- "dart|${(j:|:)@}" >> "$TEST_TRACE"
exit "$MOCK_BUSINESS_STATUS"
DART
  /bin/cat > "$TEST_CASE/bin/fvm" <<'FVM'
#!/bin/zsh
if [[ "$1 $2" == 'api context' ]]; then
  print -r -- 'fvm-context' >> "$TEST_TRACE"
  printf '{"context":{"versionsCachePath":"%s/cache","environment":{"SECRET":"never-persist-me"}}}\n' "$TEST_CASE"
  exit 0
fi
print -r -- "fvm|${(j:|:)@}" >> "$TEST_TRACE"
[[ "$1 $2" != 'flutter --version' ]] || exit "$MOCK_INITIAL_STATUS"
[[ "$1" != install ]] || exit 0
exit "$MOCK_BUSINESS_STATUS"
FVM
  /bin/cat > "$TEST_CASE/bin/brew" <<'BREW'
#!/bin/zsh
if [[ "$1" == ruby ]]; then print -r -- 'https://bottles.example.invalid/dart-exact.tar.gz'; exit 0; fi
if [[ "$1 $2" == '--prefix dart' ]]; then
  if [[ "$MOCK_DART_PREFIX_MISSING" == 1 ]]; then print -r -- "$TEST_CASE/missing"; else print -r -- "$TEST_CASE/sdk"; fi
  exit 0
fi
if [[ "$1" == info && "${@: -1}" == dart ]]; then
 print -r -- '{"formulae":[{"name":"dart","versions":{"stable":"3.10.3"},"urls":{"stable":{"url":"https://dart.example.invalid/source.zip"}},"bottle":{"stable":{"files":{"arm64_test":{"url":"https://bottles.example.invalid/dart-exact.tar.gz"}}}}}]}'
 exit 0
fi
if [[ "$1" == info ]]; then
  print -r -- metadata >> "$TEST_CASE/metadata-calls"
  if [[ "$MOCK_METADATA_FATAL" == 1 ]]; then print -u2 'Error: No available Cask with the name flutter'; exit 1; fi
  if [[ "$MOCK_METADATA_FAIL_ONCE" == 1 && ! -f "$TEST_CASE/metadata-tried" ]]; then
    : > "$TEST_CASE/metadata-tried"
    print -u2 'curl: (28) Operation timed out'
    exit 1
  fi
  print -r -- '{"casks":[{"url":"https://example.invalid/original/flutter.zip?real=1","version":"3.38.4"}]}'
  exit 0
fi
print -r -- "brew|${(j:|:)@}" >> "$TEST_TRACE"
exit "$MOCK_BUSINESS_STATUS"
BREW
  /bin/chmod +x "$TEST_CASE/sdk/bin/flutter" "$TEST_CASE/sdk/bin/dart" "$TEST_CASE/bin/fvm" "$TEST_CASE/bin/brew"
  print -r -- a5cb96369ef86c7e85abf5d662a1ca5d89775053 > "$TEST_CASE/sdk/bin/internal/engine.version"
  : > "$TEST_CASE/sdk/bin/internal/update_dart_sdk.sh"
  print -r -- 'name: fixture' > "$TEST_CASE/project/pubspec.yaml"
  /bin/mkdir -p "$TEST_CASE/cache/3.38.4"
}
# 明确比较调用内容，避免只验证字符串存在于注释。
assert_has() { (( TEST_ASSERTIONS++ )); /usr/bin/grep -Fxq -- "$1" "$TEST_TRACE"; }
assert_count() { (( TEST_ASSERTIONS++ )); [[ "$(/usr/bin/grep -Fxc -- "$1" "$TEST_TRACE")" == "$2" ]]; }
assert_equal() { (( TEST_ASSERTIONS++ )); [[ "$1" == "$2" ]]; }
test_business_once() {
  export MOCK_BUSINESS_STATUS=7
  local result=0
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/sdk/bin/flutter" build 'a b' || result=$?
  assert_equal "$result" 7 && assert_count 'flutter|--version' 1 && assert_count 'flutter|build|a b' 1 &&
    assert_has 'route|--run|dart||1' && assert_has 'route|--once|dart||0'
}
test_initial_failure() {
  export MOCK_INITIAL_STATUS=143
  local result=0
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/sdk/bin/flutter" run || result=$?
  assert_equal "$result" 143 && assert_count 'flutter|run' 0
}
test_precache_platform() {
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/sdk/bin/flutter" precache --ios || return 1
  assert_has 'route|--run|platform||1' && assert_count 'flutter|precache|--ios' 1
}
test_upgrade_public_interface() {
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/sdk/bin/flutter" upgrade --force || return 1
  assert_has 'route|--flutter-upgrade|dart||1' && assert_has 'flutter|upgrade|--force' &&
    assert_count 'flutter|--version' 1
}
test_stdin_preserved() {
  print -r -- '用户 输入' | /bin/sh "$TEST_ADAPTER" "$TEST_CASE/sdk/bin/flutter" run --stdin || return 1
  assert_has 'stdin|用户 输入'
}
test_fvm_install_args() {
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/bin/fvm" install 3.38.4 --skip-pub-get || return 1
  assert_has 'route|--fvm-install|dart||0' && assert_has 'fvm|install|3.38.4|--skip-pub-get'
}
test_fvm_use_once() {
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/bin/fvm" use 3.38.4 --force || return 1
  assert_count 'fvm|install|3.38.4' 1 && assert_count 'fvm|use|3.38.4|--force' 1 &&
    ! /usr/bin/grep -q 'never-persist-me' "$TEST_TRACE"
}
test_warm_fvm_use() {
  /bin/mkdir -p "$TEST_CASE/cache/3.38.4/bin/internal" "$TEST_CASE/cache/3.38.4/bin/cache/dart-sdk/bin"
  /bin/cp "$TEST_CASE/sdk/bin/internal/engine.version" "$TEST_CASE/cache/3.38.4/bin/internal/engine.version"
  /bin/cp "$TEST_CASE/sdk/bin/internal/engine.version" "$TEST_CASE/cache/3.38.4/bin/cache/engine-dart-sdk.stamp"
  [[ -z "${FLUTTER_PREBUILT_ENGINE_VERSION:-}" ]] || print -r -- "$FLUTTER_PREBUILT_ENGINE_VERSION" > "$TEST_CASE/cache/3.38.4/bin/cache/engine-dart-sdk.stamp"
  /bin/cp "$TEST_CASE/sdk/bin/dart" "$TEST_CASE/cache/3.38.4/bin/cache/dart-sdk/bin/dart"
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/bin/fvm" use 3.38.4 --force || return 1
  assert_count 'fvm|install|3.38.4' 0 && assert_count 'fvm|use|3.38.4|--force' 1 &&
    assert_count 'route|--fvm-install|dart||0' 0
}
test_custom_engine_warm_use() {
  export FLUTTER_PREBUILT_ENGINE_VERSION=1111111111111111111111111111111111111111
  test_warm_fvm_use
}
test_fvm_dart() {
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/bin/fvm" dart fix --apply || return 1
  assert_has 'fvm|flutter|--version' && assert_count 'fvm|dart|fix|--apply' 1
}
test_direct_dart() {
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/sdk/bin/dart" run 'file space.dart' || return 1
  assert_has 'flutter|--version' && assert_has 'dart|run|file space.dart'
}
test_fvm_releases() {
  FLUTTER_STORAGE_BASE_URL=https://owned.invalid /bin/sh "$TEST_ADAPTER" "$TEST_CASE/bin/fvm" releases || return 1
  assert_has 'route|--run|source|https://owned.invalid/flutter_infra_release/releases/releases_macos.json|1'
}
test_brew_original_url() {
  local original="${FLUTTER_STORAGE_BASE_URL-unset}"
  /bin/sh "$TEST_ADAPTER" --brew-cask "$TEST_CASE/bin/brew" install || return 1
  assert_has 'route|--run|source|https://example.invalid/original/flutter.zip?real=1|1' && assert_has 'brew|install|--cask|flutter' &&
    assert_equal "${FLUTTER_STORAGE_BASE_URL-unset}" "$original"
}
test_brew_metadata_retry() {
  export MOCK_METADATA_FAIL_ONCE=1
  /bin/sh "$TEST_ADAPTER" --brew-cask "$TEST_CASE/bin/brew" install || return 1
  assert_equal "$(/usr/bin/grep -c metadata "$TEST_CASE/metadata-calls")" 2 &&
    assert_count 'brew|install|--cask|flutter' 1
}
test_brew_metadata_returns_to_ip_fallback() {
  export MOCK_METADATA_FAIL_ONCE=1
  local result=0
  /bin/sh "$TEST_ADAPTER" --brew-cask-once "$TEST_CASE/bin/brew" upgrade || result=$?
  assert_equal "$result" 1 && assert_count 'brew|upgrade|--cask|flutter' 0 || return 1
  /bin/sh "$TEST_ADAPTER" --brew-cask-once "$TEST_CASE/bin/brew" upgrade || return 1
  assert_equal "$(/usr/bin/grep -c metadata "$TEST_CASE/metadata-calls")" 2 && assert_count 'brew|upgrade|--cask|flutter' 1
}
test_brew_provider_config() {
  print -r -- ipv6 > "$TEST_CASE/brew curlrc"
  HOMEBREW_CURLRC="$TEST_CASE/brew curlrc" /bin/sh "$TEST_ADAPTER" --brew-cask-once "$TEST_CASE/bin/brew" upgrade || return 1
  assert_has "provider|$TEST_CASE/brew curlrc|1" && assert_count 'brew|upgrade|--cask|flutter' 1
}
test_brew_metadata_fatal() {
  export MOCK_METADATA_FATAL=1
  local result=0
  /bin/sh "$TEST_ADAPTER" --brew-cask "$TEST_CASE/bin/brew" install || result=$?
  assert_equal "$result" 1 && assert_equal "$(/usr/bin/grep -c metadata "$TEST_CASE/metadata-calls")" 1 &&
    assert_count 'brew|install|--cask|flutter' 0
}
test_brew_once_failure() {
  export MOCK_BUSINESS_STATUS=9
  local result=0
  /bin/sh "$TEST_ADAPTER" --brew-cask-once "$TEST_CASE/bin/brew" upgrade || result=$?
  assert_equal "$result" 9 && assert_count 'brew|upgrade|--cask|flutter' 1 &&
    assert_has 'route|--once|source|https://example.invalid/original/flutter.zip?real=1|0'
}
test_symlink_sdk() {
  /bin/ln -s "$TEST_CASE/sdk/bin/flutter" "$TEST_CASE/bin/flutter"
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/bin/flutter" analyze || return 1
  assert_has 'flutter|--version' && assert_has 'flutter|analyze'
}
test_library_source_and_metadata() {
  local before="${HTTPS_PROXY-unset}"
  source "$LIB_ROOT/jobs_flutter_lib.zsh" || return 1
  assert_count 'flutter|--version' 0 && assert_equal "${HTTPS_PROXY-unset}" "$before" || return 1
  /bin/mkdir -p "$TEST_CASE/project/.fvm"
  /bin/ln -s "$TEST_CASE/sdk" "$TEST_CASE/project/.fvm/flutter_sdk"
  print -r -- 3.38.4 > "$TEST_CASE/sdk/version"
  builtin cd "$TEST_CASE/project" || return 1
  assert_equal "$(jobs_flutter_read_project_flutter_version)" 3.38.4 && assert_count 'flutter|--version' 0
}
test_official_archive_sha() {
  export MOCK_ARCHIVE_PAYLOAD="$TEST_CASE/payload" JOBS_FLUTTER_ROUTE_CURL="$TEST_CASE/bin/curl"
  print -r -- 'PK-fixture-archive' > "$MOCK_ARCHIVE_PAYLOAD"
  export MOCK_ARCHIVE_SHA="$(/usr/bin/shasum -a 256 "$MOCK_ARCHIVE_PAYLOAD" | /usr/bin/awk '{print $1}')"
  : > "$TEST_CASE/download"
  /bin/sh "$TEST_ADAPTER" --official-archive stable "$TEST_CASE/download" || return 1
  /usr/bin/cmp -s "$MOCK_ARCHIVE_PAYLOAD" "$TEST_CASE/download" && assert_has 'source-route|archive||stable'
}
test_official_archive_rejects_corruption() {
  export MOCK_ARCHIVE_PAYLOAD="$TEST_CASE/payload" JOBS_FLUTTER_ROUTE_CURL="$TEST_CASE/bin/curl"
  print -r -- 'corrupted fixture' > "$MOCK_ARCHIVE_PAYLOAD"
  export MOCK_ARCHIVE_SHA=1111111111111111111111111111111111111111111111111111111111111111
  : > "$TEST_CASE/download"
  local result=0
  /bin/sh "$TEST_ADAPTER" --official-archive stable "$TEST_CASE/download" || result=$?
  assert_equal "$result" 1 && [[ ! -s "$TEST_CASE/download" ]]
}
test_dart_brew_actual_supplier() {
  /bin/sh "$TEST_ADAPTER" --brew-dart "$TEST_CASE/bin/brew" install || return 1
  assert_has 'provider-probe|https://bottles.example.invalid/dart-exact.tar.gz' && assert_has 'brew|install|dart'
}
test_dart_brew_requires_native_binary() {
  export MOCK_DART_PREFIX_MISSING=1
  local result=0
  /bin/sh "$TEST_ADAPTER" --brew-dart "$TEST_CASE/bin/brew" install || result=$?
  assert_equal "$result" 1 && assert_has 'brew|install|dart'
}
test_channel_preserves_ref_and_arguments() {
  /usr/bin/git -C "$TEST_CASE/sdk" init -q -b stable || return 1
  /usr/bin/git -C "$TEST_CASE/sdk" remote add origin https://example.invalid/jobs/flutter-fork.git || return 1
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/sdk/bin/flutter" channel beta || return 1
  assert_has 'source-route|git|https://example.invalid/jobs/flutter-fork.git|beta' && assert_has 'flutter|channel|beta' &&
    assert_count 'flutter|--version' 1 && assert_equal "$(/usr/bin/head -n1 "$TEST_TRACE")" 'route|--run|dart||1'
}
test_channel_current_sdk_failure_blocks_git_and_channel() {
  export MOCK_INITIAL_STATUS=143
  local result=0
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/sdk/bin/flutter" channel beta || result=$?
  assert_equal "$result" 143 && assert_count 'flutter|--version' 1 && assert_count 'flutter|channel|beta' 0 &&
    assert_count 'source-route|git|https://example.invalid/jobs/flutter-fork.git|beta' 0
}
test_append_log_does_not_inherit_replaced_flag() {
  JOBS_SDK_LOG_REPLACED=1 MOCK_CHECK_LOG_OFFSET=1 /bin/sh "$TEST_ADAPTER" "$TEST_CASE/sdk/bin/flutter" --version || return 1
  assert_has 'log-offset|0' && assert_count 'flutter|--version' 1
}
test_fvm_runtime_before_context() {
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/bin/fvm" use 3.38.4 --force || return 1
  assert_equal "$(/usr/bin/head -n1 "$TEST_TRACE")" runtime-gate && assert_has fvm-context
}
test_fvm_runtime_cancel_stops_context() {
  export MOCK_FVM_RUNTIME_STATUS=143
  local result=0
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/bin/fvm" use 3.38.4 --force || result=$?
  assert_equal "$result" 143 && assert_count fvm-context 0 && assert_count 'fvm|install|3.38.4' 0
}
test_fvm_package_prerequisite() {
  export PUB_CACHE="$TEST_CASE/pub-cache"
  /bin/mkdir -p "$PUB_CACHE/bin"
  /bin/cp "$TEST_CASE/bin/fvm" "$PUB_CACHE/bin/fvm"
  /bin/sh "$TEST_ADAPTER" "$TEST_CASE/sdk/bin/dart" pub global activate fvm || return 1
  assert_count 'dart|pub|global|activate|fvm' 1
}
# 安装入口只给Flutter cask包SDK预检，其它工具维持原流程。
test_install_flutter_scope() {
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "${LIB_ROOT:h}/install.command/install.command" || return 1
  export PATH="$TEST_CASE/bin:$PATH"
  function progress_step() { :; }
  function require_brew_or_skip() { return 0; }
  function brew_cask_installed() { return 1; }
  function brew_cask_local_app_exists() { return 1; }
  function confirm_execute() { return 0; }
  function run_cmd() { shift; "$@"; }
  function jobs_flutter_sdk_command() { print -r -- "adapter|${(j:|:)@}" >> "$TEST_TRACE"; }
  function brew_cask_after_install() { print -r -- "after|$1" >> "$TEST_TRACE"; }
  component_brew_cask flutter || return 1
  component_brew_cask other-tool || return 1
  assert_has "adapter|--brew-cask|$TEST_CASE/bin/brew|install" && assert_has 'after|flutter' &&
    assert_has 'brew|install|--cask|other-tool'
}
test_install_flutter_cancel() {
  test_install_flutter_scope || return 1
  : > "$TEST_TRACE"
  function jobs_flutter_sdk_command() { return 130; }
  local result=0
  component_brew_cask flutter || result=$?
  assert_equal "$result" 130 && assert_count 'after|flutter' 0
}
test_install_cancel_stops_remaining_items() {
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "${LIB_ROOT:h}/install.command/install.command" || return 1
  function prepare_menu_runtime() { return 0; }
  function choose_menu_items() { RUN_ITEMS=('brew cask：flutter' 'brew cask：other-tool'); }
  function run_selected_item() { print -r -- "item|$1" >> "$TEST_TRACE"; return 130; }
  function finish_summary() { print -r -- summary >> "$TEST_TRACE"; }
  local result=0
  install || result=$?
  assert_equal "$result" 130 && assert_count 'item|brew cask：other-tool' 0 && assert_count summary 0
}
# 原双栈函数的统计留在父Shell；只有SDK网络失败进入下一轮。
test_update_brew_network_retry() {
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "${LIB_ROOT:h}/update.command/update.command" || return 1
  export PATH="$TEST_CASE/bin:$PATH"
  JOBS_FLUTTER_NETWORK_RESOURCE_ROOT="$TEST_CASE/Scripts"
  JOBS_FLUTTER_NETWORK_TASK_CACHE="$TEST_CASE/cache-task"
  /bin/mkdir -p "$JOBS_FLUTTER_NETWORK_TASK_CACHE"
  TEST_ATTEMPTS=0
  function jobs_update_run_brew_adaptive_cmd() {
    (( TEST_ATTEMPTS++ ))
    [[ " $* " == *' --brew-cask-once '* ]] || return 97
    JOBS_UPDATE_LAST_BREW_OUTPUT_FILE="$TEST_CASE/brew-output"
    if (( TEST_ATTEMPTS == 1 )); then print -r -- 'curl: (28) Operation timed out' > "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"; return 1; fi
    : > "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
    return 0
  }
  function jobs_update_record_failure() { print -r -- "failure|$*" >> "$TEST_TRACE"; }
  jobs_update_flutter_cask_sdk || return 1
  assert_equal "$TEST_ATTEMPTS" 2 && assert_count 'failure|' 0
}
# 明确本地权限错误应原码返回，不能无限重跑。
test_update_brew_local_error() {
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "${LIB_ROOT:h}/update.command/update.command" || return 1
  JOBS_FLUTTER_NETWORK_RESOURCE_ROOT="$TEST_CASE/Scripts"
  JOBS_FLUTTER_NETWORK_TASK_CACHE="$TEST_CASE/cache-task"
  TEST_ATTEMPTS=0
  function jobs_update_run_brew_adaptive_cmd() {
    (( TEST_ATTEMPTS++ ))
    JOBS_UPDATE_LAST_BREW_OUTPUT_FILE="$TEST_CASE/brew-output"
    print -r -- 'Permission denied' > "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
    return 9
  }
  function jobs_update_record_failure() { print -r -- "failure|$2" >> "$TEST_TRACE"; }
  local result=0
  jobs_update_flutter_cask_sdk || result=$?
  assert_equal "$result" 9 && assert_equal "$TEST_ATTEMPTS" 1 && assert_has 'failure|9'
}
# 保留失败上下文，所有路径固定在夹具临时根。
run_test() {
  (( TEST_COUNT++ ))
  if (fixture && "$1"); then print -r -- "PASS $1"; else (( TEST_FAILURES++ )); print -u2 -r -- "FAIL $1"; /bin/cat "$TEST_TRACE" >&2; fi
}
main() {
  print -r -- 'SDK网络适配隔离回归：假网络模块、假SDK、假Brew；不运行真实网络或安装。'
  local test
  for test in test_business_once test_initial_failure test_precache_platform test_upgrade_public_interface test_stdin_preserved test_fvm_install_args test_fvm_use_once test_warm_fvm_use test_custom_engine_warm_use test_fvm_dart test_direct_dart test_fvm_releases test_brew_original_url test_brew_metadata_retry test_brew_metadata_returns_to_ip_fallback test_brew_provider_config test_brew_metadata_fatal test_brew_once_failure test_symlink_sdk test_library_source_and_metadata test_official_archive_sha test_official_archive_rejects_corruption test_dart_brew_actual_supplier test_dart_brew_requires_native_binary test_channel_preserves_ref_and_arguments test_fvm_package_prerequisite test_channel_current_sdk_failure_blocks_git_and_channel test_append_log_does_not_inherit_replaced_flag test_fvm_runtime_before_context test_fvm_runtime_cancel_stops_context test_install_flutter_scope test_install_flutter_cancel test_install_cancel_stops_remaining_items test_update_brew_network_retry test_update_brew_local_error; do run_test "$test"; done
  print -r -- "结果：${TEST_COUNT}项，失败${TEST_FAILURES}。"
  (( TEST_FAILURES == 0 ))
}
main "$@"
