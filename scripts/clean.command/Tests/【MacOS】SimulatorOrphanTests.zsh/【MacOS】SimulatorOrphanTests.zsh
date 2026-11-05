# shell: zsh
# 脚本自述：
# - 脚本名称：【MacOS】SimulatorOrphanTests.zsh
# - 核心用途：隔离验证 clean 对 CoreSimulator 残留登记的识别、备份、注销与失败传播。
# - 影响范围：只使用本次临时 HOME 和假 simctl，不操作真实设备、Runtime、缓存或终端历史。
# - 运行提示：自动执行隔离回归；按 Ctrl+C 可取消。

TEST_SCRIPT_DIR="${${(%):-%x}:A:h}"
TEST_SCRIPT_PATH="${${(%):-%x}:A}"
TEST_SOURCE="${TEST_SCRIPT_DIR:h:h}/clean.command"
TEST_ROOT="${JOBS_CLEAN_SIM_TEST_ROOT:-}"
TEST_DEVICE_A='AAAAAAAA-1111-4111-8111-111111111111'
TEST_DEVICE_B='BBBBBBBB-2222-4222-8222-222222222222'
TEST_CASE_DIR=''
TEST_META=''
TEST_DEVICES=''
TEST_CALLS=''
TEST_MODE='normal'
# 只回收带本测试归属标记的临时目录。
cleanup_test_root() {
  [[ -z "${JOBS_CLEAN_SIM_TEST_CASE:-}" && -n "$TEST_ROOT" && -d "$TEST_ROOT" &&
     "${TEST_ROOT:t}" == jobs-clean-simulator-tests.* && -f "$TEST_ROOT/.jobs-clean-simulator-tests" ]] || return 0
  /bin/rm -r -- "$TEST_ROOT"
}
# 输出失败原因，交给当前用例退出状态汇总。
fail_test() {
  print -u2 -r -- "FAIL: $*"
  return 1
}
# 比较文本时保留空格和中文，不作 Shell 求值。
assert_equal() {
  [[ "$1" == "$2" ]] || fail_test "${3:-值不一致}；expected=[$1] actual=[$2]"
}
# 核对假工具没有收到任何 shutdown/delete。
assert_no_mutation() {
  if /usr/bin/grep -Eq '^(shutdown|delete)\|' "$TEST_CALLS"; then
    fail_test "不应执行设备变更：$(/bin/cat "$TEST_CALLS")"
  fi
}
# 核对精确 UUID 对应的单条模拟器命令。
assert_call() {
  /usr/bin/grep -Fxq -- "$1|$2" "$TEST_CALLS" || fail_test "缺少精确调用：$1|$2"
}
# 生成真实 JSON，路径与设备名始终作为数据参数传给 JXA。
write_device_record() {
  local uuid="$1" state="${2:-Shutdown}" runtime="${3:-com.apple.CoreSimulator.SimRuntime.iOS-27-2}" data_path="${4:-$TEST_DEVICES/$1/data}"
  /usr/bin/osascript -l JavaScript - "$uuid" "$state" "$runtime" "$data_path" > "$TEST_META/$uuid.json" <<'JXA'
function run(argv) {
  return JSON.stringify({runtime: argv[2], device: {udid: argv[0], name: "测试设备 ' 中文", state: argv[1], isAvailable: true, dataPath: argv[3]}});
}
JXA
}
# 只创建当前用例需要的设备定义与模拟数据。
create_complete_device() {
  local uuid="$1"
  /bin/mkdir -p "$TEST_DEVICES/$uuid/data"
  print -r -- 'fixture-device-definition' > "$TEST_DEVICES/$uuid/device.plist"
  print -r -- 'fixture-app-data' > "$TEST_DEVICES/$uuid/data/important.txt"
}
# 将假设备登记拼成 simctl 的设备清单格式。
emit_mock_inventory() {
  /usr/bin/osascript -l JavaScript - "$TEST_META" <<'JXA'
ObjC.import("Foundation");
function run(argv) {
  var directory = argv[0], result = {devices: {}};
  var names = ObjC.deepUnwrap($.NSFileManager.defaultManager.contentsOfDirectoryAtPathError(directory, null));
  names.filter(function(name) { return /\.json$/.test(name); }).sort().forEach(function(name) {
    var text = $.NSString.stringWithContentsOfFileEncodingError(directory + "/" + name, $.NSUTF8StringEncoding, null);
    var row = JSON.parse(ObjC.unwrap(text));
    if (!result.devices[row.runtime]) result.devices[row.runtime] = [];
    result.devices[row.runtime].push(row.device);
  });
  return JSON.stringify(result);
}
JXA
}
# 完全替代生产 simctl，所有状态和调用记录均落在临时用例目录。
jobs_clean_simctl() {
  local devices_dir="$1" action="$2" uuid="${3:-}" calls=0
  shift 2
  [[ "$devices_dir" == "$TEST_DEVICES" ]] || return 91
  case "$action" in
    list)
      calls="$(/bin/cat "$TEST_CASE_DIR/list-count")"
      (( calls += 1 ))
      print -r -- "$calls" > "$TEST_CASE_DIR/list-count"
      print -r -- "list|$*" >> "$TEST_CALLS"
      [[ "$TEST_MODE" != query_failure ]] || return 9
      if [[ "$TEST_MODE" == bad_json ]]; then print -r -- '{broken'; return 0; fi
      if [[ "$TEST_MODE" == bad_schema ]]; then print -r -- '{"unexpected":[]}'; return 0; fi
      if [[ "$TEST_MODE" == restore_on_query && "$calls" -ge 2 ]]; then
        create_complete_device "$TEST_DEVICE_A"
      fi
      if [[ "$TEST_MODE" == restore_late && "$calls" -ge 4 ]]; then
        create_complete_device "$TEST_DEVICE_A"
      fi
      if [[ "$TEST_MODE" == change_data && "$calls" -eq 4 ]]; then
        print -r -- 'concurrent-data-change' >> "$TEST_DEVICES/$TEST_DEVICE_A/data/important.txt"
      fi
      emit_mock_inventory
      ;;
    shutdown)
      print -r -- "shutdown|$uuid" >> "$TEST_CALLS"
      [[ "$TEST_MODE" != shutdown_failure ]] || return 8
      [[ "$TEST_MODE" != shutdown_false_success ]] || return 0
      /usr/bin/sed 's/"state":"Booted"/"state":"Shutdown"/' "$TEST_META/$uuid.json" > "$TEST_META/$uuid.next"
      /bin/mv "$TEST_META/$uuid.next" "$TEST_META/$uuid.json"
      ;;
    delete)
      print -r -- "delete|$uuid" >> "$TEST_CALLS"
      [[ "$TEST_MODE" != delete_failure ]] || return 7
      [[ "$TEST_MODE" != delete_false_success ]] || return 0
      /bin/rm -- "$TEST_META/$uuid.json"
      ;;
    *) return 92 ;;
  esac
}
# 每个子进程只加载函数，并使用调用方分配的专属临时 HOME。
initialize_case() {
  [[ -n "$TEST_ROOT" && -f "$TEST_ROOT/.jobs-clean-simulator-tests" ]] || return 1
  TEST_CASE_DIR="$TEST_ROOT/$JOBS_CLEAN_SIM_TEST_CASE"
  TEST_META="$TEST_CASE_DIR/metadata"
  TEST_DEVICES="$HOME/Library/Developer/CoreSimulator/Devices"
  TEST_CALLS="$TEST_CASE_DIR/calls"
  /bin/mkdir -p "$TEST_META" "$TEST_DEVICES" "$HOME/.Trash"
  : > "$TEST_CALLS"
  print -r -- 0 > "$TEST_CASE_DIR/list-count"
  export JOBS_MAC_ENV_SOURCE_MODE=1
  # 保留本测试的假工具定义；source 会定义生产同名适配器。
  local fake_adapter="${functions[jobs_clean_simctl]}"
  source "$TEST_SOURCE" || return 1
  functions[jobs_clean_simctl]="$fake_adapter"
  LOG_FILE="$TEST_CASE_DIR/clean.log"
  : > "$LOG_FILE"
  JOBS_CLEAN_CONFIRMED=1
}
# 完整的正常与仅 Runtime 失配设备均保留。
test_complete_devices_survive() {
  write_device_record "$TEST_DEVICE_A" Shutdown
  write_device_record "$TEST_DEVICE_B" Booted
  create_complete_device "$TEST_DEVICE_A"
  create_complete_device "$TEST_DEVICE_B"
  /usr/bin/sed 's/"isAvailable":true/"isAvailable":false/' "$TEST_META/$TEST_DEVICE_A.json" > "$TEST_META/$TEST_DEVICE_A.next"
  /bin/mv "$TEST_META/$TEST_DEVICE_A.next" "$TEST_META/$TEST_DEVICE_A.json"
  jobs_clean_orphaned_simulators || return 1
  assert_no_mutation
}
# 整台目录已缺失时只注销对应登记。
test_missing_directory_is_removed() {
  write_device_record "$TEST_DEVICE_A"
  jobs_clean_orphaned_simulators || return 1
  assert_call delete "$TEST_DEVICE_A" || return 1
  [[ ! -e "$TEST_META/$TEST_DEVICE_A.json" ]] || return 1
  [[ -n "$(/usr/bin/find "$HOME/.Trash" -name inventory-before.json -print)" ]] || fail_test '缺少清理前设备清单'
}
# 缺定义但仍有 App 数据时，删除登记之前必须留下完整数据副本。
test_missing_plist_is_backed_up() {
  write_device_record "$TEST_DEVICE_A"
  /bin/mkdir -p "$TEST_DEVICES/$TEST_DEVICE_A/data"
  print -r -- 'do-not-lose-this-data' > "$TEST_DEVICES/$TEST_DEVICE_A/data/important.txt"
  jobs_clean_orphaned_simulators || return 1
  assert_call delete "$TEST_DEVICE_A" || return 1
  local backup_file="$(/usr/bin/find "$HOME/.Trash" -name important.txt -print | /usr/bin/head -n 1)"
  [[ -n "$backup_file" ]] || fail_test '部分实体未备份' || return 1
  assert_equal 'do-not-lose-this-data' "$(/bin/cat "$backup_file")" '备份数据不一致'
}
# 仅缺 data 不删除仍有定义的可恢复设备。
test_data_only_missing_is_preserved() {
  write_device_record "$TEST_DEVICE_A"
  create_complete_device "$TEST_DEVICE_A"
  /bin/rm -r -- "$TEST_DEVICES/$TEST_DEVICE_A/data"
  jobs_clean_orphaned_simulators || return 1
  assert_no_mutation
}
# 运行中的残留设备须按 UUID 关闭并复检后再注销。
test_booted_orphan_is_shutdown_first() {
  write_device_record "$TEST_DEVICE_A" Booted
  jobs_clean_orphaned_simulators || return 1
  assert_call shutdown "$TEST_DEVICE_A" || return 1
  assert_call delete "$TEST_DEVICE_A" || return 1
  local mutations="$(/usr/bin/grep -E '^(shutdown|delete)\|' "$TEST_CALLS")"
  assert_equal $'shutdown|'"$TEST_DEVICE_A"$'\ndelete|'"$TEST_DEVICE_A" "$mutations" '关闭与注销顺序错误'
}
# 工具错误和假成功必须保留对应记录并返回失败。
test_tool_failure() {
  TEST_MODE="$JOBS_CLEAN_SIM_TEST_CASE"
  local state=Shutdown
  [[ "$TEST_MODE" != shutdown* ]] || state=Booted
  write_device_record "$TEST_DEVICE_A" "$state"
  if jobs_clean_orphaned_simulators; then fail_test '工具失败或未注销不能报告成功'; return 1; fi
  [[ -f "$TEST_META/$TEST_DEVICE_A.json" ]] || fail_test '失败后登记应保留' || return 1
  if [[ "$TEST_MODE" == shutdown* ]]; then
    ! /usr/bin/grep -q '^delete|' "$TEST_CALLS" || fail_test '关闭失败后不应注销'
  fi
}
# 写前复检若发现设备实体恢复，保留它而不覆盖并发变化。
test_recovered_device_is_preserved() {
  TEST_MODE=restore_on_query
  write_device_record "$TEST_DEVICE_A"
  jobs_clean_orphaned_simulators || return 1
  assert_no_mutation
}
# 已做快照后定义恢复或数据变化，不得借旧快照删除新的内容。
test_late_changes_are_preserved() {
  TEST_MODE="$JOBS_CLEAN_SIM_TEST_CASE"
  write_device_record "$TEST_DEVICE_A"
  /bin/mkdir -p "$TEST_DEVICES/$TEST_DEVICE_A/data"
  print -r -- 'original-data' > "$TEST_DEVICES/$TEST_DEVICE_A/data/important.txt"
  jobs_clean_orphaned_simulators || true
  assert_no_mutation || return 1
  [[ -f "$TEST_META/$TEST_DEVICE_A.json" ]] || fail_test '并发变化后应保留登记'
}
# 残留数据无法读取时，备份失败不能继续注销。
test_backup_failure_preserves_device() {
  write_device_record "$TEST_DEVICE_A"
  /bin/mkdir -p "$TEST_DEVICES/$TEST_DEVICE_A/data"
  print -r -- 'unreadable-fixture-data' > "$TEST_DEVICES/$TEST_DEVICE_A/data/important.txt"
  /bin/chmod 000 "$TEST_DEVICES/$TEST_DEVICE_A/data/important.txt"
  jobs_clean_orphaned_simulators
  local result=$?
  /bin/chmod 600 "$TEST_DEVICES/$TEST_DEVICE_A/data/important.txt"
  assert_no_mutation || return 1
  (( result != 0 )) || fail_test '备份不可读数据失败应报告未完成'
}
# 异常查询和格式不能产生设备修改。
test_bad_query_has_no_mutation() {
  TEST_MODE="$JOBS_CLEAN_SIM_TEST_CASE"
  write_device_record "$TEST_DEVICE_A"
  if jobs_clean_orphaned_simulators; then fail_test '异常查询应返回失败'; return 1; fi
  assert_no_mutation
}
# 非法 UUID 和集外路径不能转成默认设备集的删除操作。
test_untrusted_record_has_no_mutation() {
  case "$JOBS_CLEAN_SIM_TEST_CASE" in
    invalid_uuid) write_device_record not-a-uuid ;;
    outside_path) write_device_record "$TEST_DEVICE_A" Shutdown com.apple.CoreSimulator.SimRuntime.iOS-27-2 "$TEST_CASE_DIR/external/data" ;;
    non_ios) write_device_record "$TEST_DEVICE_A" Shutdown com.apple.CoreSimulator.SimRuntime.watchOS-27-2 ;;
    unknown_state) write_device_record "$TEST_DEVICE_A" Creating ;;
  esac
  jobs_clean_orphaned_simulators || true
  assert_no_mutation
}
# 设备目录及元数据链接均不作为缺失实体跟随或注销。
test_symbolic_links_are_preserved() {
  write_device_record "$TEST_DEVICE_A"
  /bin/mkdir -p "$TEST_CASE_DIR/external"
  case "$JOBS_CLEAN_SIM_TEST_CASE" in
    device_symlink) /bin/ln -s "$TEST_CASE_DIR/external" "$TEST_DEVICES/$TEST_DEVICE_A" ;;
    plist_symlink)
      /bin/mkdir -p "$TEST_DEVICES/$TEST_DEVICE_A"
      /bin/ln -s "$TEST_CASE_DIR/external/missing" "$TEST_DEVICES/$TEST_DEVICE_A/device.plist"
      ;;
    trash_symlink)
      /bin/rmdir "$HOME/.Trash"
      /bin/ln -s "$TEST_CASE_DIR/external" "$HOME/.Trash"
      ;;
    device_set_symlink)
      /bin/rmdir "$TEST_DEVICES"
      /bin/ln -s "$TEST_CASE_DIR/external" "$TEST_DEVICES"
      ;;
  esac
  jobs_clean_orphaned_simulators || true
  assert_no_mutation
}
# 不可遍历目录不得误判为设备不存在。
test_unreadable_device_is_preserved() {
  write_device_record "$TEST_DEVICE_A"
  /bin/mkdir -p "$TEST_DEVICES/$TEST_DEVICE_A"
  /bin/chmod 000 "$TEST_DEVICES/$TEST_DEVICE_A"
  jobs_clean_orphaned_simulators
  local result=$?
  /bin/chmod 700 "$TEST_DEVICES/$TEST_DEVICE_A"
  assert_no_mutation || return 1
  (( result != 0 )) || fail_test '不可检查的设备应报告未完成'
}
# 未确认时，连可清理的登记也必须保留。
test_confirmation_is_required() {
  write_device_record "$TEST_DEVICE_A"
  JOBS_CLEAN_CONFIRMED=0
  if jobs_clean_orphaned_simulators; then fail_test '缺少确认应失败'; return 1; fi
  assert_no_mutation
}
# 合法空列表和重复执行均无多余关闭或删除。
test_empty_inventory_and_idempotence() {
  jobs_clean_orphaned_simulators || return 1
  assert_no_mutation || return 1
  write_device_record "$TEST_DEVICE_A"
  jobs_clean_orphaned_simulators || return 1
  jobs_clean_orphaned_simulators || return 1
  assert_equal 1 "$(/usr/bin/grep -c '^delete|' "$TEST_CALLS")" '重复清理不应再次注销'
}
# 每例从与源码无关的目录运行，保持真实资源相对寻址覆盖。
run_selected_case() {
  initialize_case || return 1
  cd "$TEST_CASE_DIR" || return 1
  case "$JOBS_CLEAN_SIM_TEST_CASE" in
    complete) test_complete_devices_survive ;;
    missing_directory) test_missing_directory_is_removed ;;
    missing_plist) test_missing_plist_is_backed_up ;;
    missing_data) test_data_only_missing_is_preserved ;;
    booted) test_booted_orphan_is_shutdown_first ;;
    shutdown_failure|shutdown_false_success|delete_failure|delete_false_success) test_tool_failure ;;
    recovered) test_recovered_device_is_preserved ;;
    restore_late|change_data) test_late_changes_are_preserved ;;
    backup_failure) test_backup_failure_preserves_device ;;
    query_failure|bad_json|bad_schema) test_bad_query_has_no_mutation ;;
    invalid_uuid|outside_path|non_ios|unknown_state) test_untrusted_record_has_no_mutation ;;
    device_symlink|plist_symlink|trash_symlink|device_set_symlink) test_symbolic_links_are_preserved ;;
    unreadable) test_unreadable_device_is_preserved ;;
    no_confirmation) test_confirmation_is_required ;;
    idempotent) test_empty_inventory_and_idempotence ;;
    *) fail_test '未知隔离用例' ;;
  esac
}
# 逐例派发临时 HOME，禁止测试进入真实 clean 主流程。
run_all_cases() {
  setopt NO_NOMATCH
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-clean-simulator-tests.XXXXXXXX")" || return 1
  TEST_ROOT="${TEST_ROOT:A}"
  : > "$TEST_ROOT/.jobs-clean-simulator-tests"
  trap cleanup_test_root EXIT
  local case_name='' case_home='' passed=0 failed=0
  local -a cases=(complete missing_directory missing_plist missing_data booted shutdown_failure shutdown_false_success delete_failure delete_false_success recovered restore_late change_data backup_failure query_failure bad_json bad_schema invalid_uuid outside_path non_ios unknown_state device_symlink plist_symlink trash_symlink device_set_symlink unreadable no_confirmation idempotent)
  for case_name in "${cases[@]}"; do
    case_home="$TEST_ROOT/$case_name/home space 中文"
    /bin/mkdir -p "$case_home/tmp"
    if /usr/bin/env HOME="$case_home" TMPDIR="$case_home/tmp/" NO_COLOR=1 JOBS_CLEAN_SIM_TEST_ROOT="$TEST_ROOT" JOBS_CLEAN_SIM_TEST_CASE="$case_name" \
      /bin/zsh -f "$TEST_SCRIPT_PATH" > "$TEST_ROOT/$case_name/output.log" 2>&1; then
      (( passed += 1 ))
      print -r -- "PASS $case_name"
    else
      (( failed += 1 ))
      print -r -- "FAIL $case_name"
      /bin/cat "$TEST_ROOT/$case_name/output.log"
    fi
  done
  print -r -- "${passed} passed, ${failed} failed"
  (( failed == 0 ))
}
# 说明本次测试的隔离范围，子用例不重复打印。
show_test_intro() {
  [[ -n "${JOBS_CLEAN_SIM_TEST_CASE:-}" ]] || print -r -- 'CoreSimulator 残留登记隔离回归：仅操作临时 HOME 与假 simctl。'
}
# 区分专属子用例与整组派发，不执行真实清理。
run_requested_tests() {
  if [[ -n "${JOBS_CLEAN_SIM_TEST_CASE:-}" ]]; then
    run_selected_case
  else
    run_all_cases
  fi
}
# 独立入口只编排说明与隔离测试派发。
main() {
  show_test_intro # 说明只使用本次夹具和假工具。
  run_requested_tests "$@" # 按父子进程模式执行指定用例或整组回归。
}
main "$@"
