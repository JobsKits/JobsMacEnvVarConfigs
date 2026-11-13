# shell: zsh
# 脚本自述：
# - 脚本名称：【MacOS】SimulatorOrphanTests.zsh
# - 核心用途：隔离验证 clean 对 CoreSimulator 残留登记的识别、备份、注销与失败传播。
# - 影响范围：只使用本次临时 HOME 和假 simctl，不操作真实设备、Runtime、缓存或终端历史。
# - 运行提示：自动执行隔离回归；按 Ctrl+C 可取消。

# >>> Jobs terminal style protection v1 >>>
# 临时保护当前终端配色，业务进程自行管理原有退出清理。
jobs_terminal_style_run() {
    # 无法可靠保存原色时，沿用脚本已有的纯文本约定。
    jobs_terminal_style_plain() {
        PLAIN_OUTPUT=1
        NO_COLOR=1
        FORCE_COLOR=0
        CLICOLOR=0
        ANSI_COLORS_DISABLED=1
        npm_config_color=false
        export PLAIN_OUTPUT NO_COLOR FORCE_COLOR CLICOLOR ANSI_COLORS_DISABLED npm_config_color
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    }
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    fi
    if [ -n "${TMUX:-}${STY:-}" ]; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_tty=$(tty 2>/dev/null) || jobs_terminal_style_plain "$@"
    if ! ps -o pgid= -o tpgid= -p "$$" 2>/dev/null |
         LC_ALL=C awk 'NF == 2 && $1 == $2 && $1 > 0 { foreground = 1 } END { exit !foreground }'; then
        jobs_terminal_style_plain "$@"
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$jobs_style_tty" ] &&
               kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null; then
                if "$@"; then
                    jobs_style_exit_status=0
                else
                    jobs_style_exit_status=$?
                fi
                exit "$jobs_style_exit_status"
            fi
            ;;
    esac
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_terminal_style_plain "$@"
    jobs_style_saved=''
    jobs_style_saved_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 只接受本次请求对应的 RGB 响应；非协议输入使本次探测失败。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || return 1
        jobs_style_reply=''
        for jobs_style_attempt in 1 2 3; do
            jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty)
            jobs_style_reply=$jobs_style_reply$jobs_style_piece
            case $jobs_style_reply in
                *"$jobs_style_bel"|*"$jobs_style_esc\\") break ;;
                '') ;;
                "$jobs_style_esc"*) ;;
                *) break ;;
            esac
        done
        case $jobs_style_reply in
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_bel")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_bel"}
                ;;
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_esc\\")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_esc\\"}
                ;;
            *) return 1 ;;
        esac
        jobs_style_normalized=$(printf '%s\n' "$jobs_style_rgb" | LC_ALL=C awk -F/ '
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    h = tolower($i)
                    if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) exit 1
                    n = 0
                    for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                    value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                }
                printf "%d/%d/%d", value[1], value[2], value[3]
            }
        ') || return 1
        [ -n "$jobs_style_normalized" ]
    }
    # 查询可用不代表终端允许改色，按目标值核对实际生效结果。
    jobs_terminal_style_accepts_target() {
        jobs_style_requested_hex=''
        case $1 in
            10|12) jobs_style_requested_hex=ffffff ;;
            11) jobs_style_requested_hex=000000 ;;
            '4;'*)
                jobs_style_requested_index=0
                for jobs_style_requested_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
                    if [ "4;$jobs_style_requested_index" = "$1" ]; then
                        jobs_style_requested_hex=$jobs_style_requested_color
                        break
                    fi
                    jobs_style_requested_index=$((jobs_style_requested_index + 1))
                done
                ;;
        esac
        [ -n "$jobs_style_requested_hex" ] || return 1
        printf '%s|%s\n' "$jobs_style_normalized" "$jobs_style_requested_hex" | LC_ALL=C awk -F'|' '
            function hexbyte(h) {
                return (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1
            }
            {
                if (split($1, actual, "/") != 3 || length($2) != 6) exit 1
                for (i = 1; i <= 3; i++) {
                    difference = actual[i] - hexbyte(substr($2, i * 2 - 1, 2)) * 257
                    if (difference < -255 || difference > 255) exit 1
                }
            }
        '
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key"; then
                            jobs_style_cleanup_ok=0
                            break
                        fi
                        if [ "$jobs_style_normalized" = "$jobs_style_expected" ]; then
                            jobs_style_restore_safe=$jobs_style_restore_safe$jobs_style_original
                        else
                            jobs_style_conflicts="$jobs_style_conflicts $jobs_style_key"
                        fi
                    done <<JOBS_STYLE_APPLIED
$jobs_style_applied_rows
JOBS_STYLE_APPLIED
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || jobs_style_cleanup_ok=0
                    jobs_style_query_active=0
                fi
            fi
            if [ "$jobs_style_cleanup_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_restore_safe" > /dev/tty; then
                if [ -z "$jobs_style_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                else
                    printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_conflicts" >&2
                    printf '确认要覆盖后续改色时才使用恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
                    [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
                fi
            else
                printf '终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_recovery" >&2
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
        fi
        if [ "${2:-}" = continue ]; then
            jobs_style_cleanup_status=$jobs_style_result
            return 0
        fi
        exit "$jobs_style_result"
    }
    trap 'jobs_terminal_style_cleanup "$jobs_style_exit_status"' 0
    trap 'jobs_style_exit_status=129; exit 129' HUP
    trap 'jobs_style_exit_status=130; exit 130' INT
    trap 'jobs_style_exit_status=143; exit 143' TERM
    if ! stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    for jobs_style_key in 10 11 12 '4;0' '4;1' '4;2' '4;3' '4;4' '4;5' '4;6' '4;7' '4;8' '4;9' '4;10' '4;11' '4;12' '4;13' '4;14' '4;15'; do
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_saved=$jobs_style_saved$jobs_style_reply
        jobs_style_saved_rows="$jobs_style_saved_rows$jobs_style_key|$jobs_style_reply
"
    done
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_recovery_dir=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/jobs-terminal-style.XXXXXX") || jobs_terminal_style_plain "$@"
    jobs_style_recovery=$jobs_style_recovery_dir/restore.sh
    if ! (umask 077; {
        printf '#!/bin/sh\n'
        printf '[ -t 0 ] && [ "$(tty)" = '\''%s'\'' ] || { printf '\''请在原终端运行恢复入口。\\n'\'' >&2; exit 1; }\n' "$jobs_style_tty"
        printf 'printf '\''本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：'\'' >&2\n'
        printf 'IFS= read -r jobs_restore_choice\n[ "$jobs_restore_choice" = YES ] || exit 1\n'
        printf 'printf '\''%%s\\033[0m'\'' '\''%s'\'' > /dev/tty\n' "$jobs_style_saved"
    } > "$jobs_style_recovery"); then
        printf '%s\n' '无法保存终端配色恢复入口；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '正在准备本次终端临时配色；强退后恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
    jobs_style_changed=1
    printf '\033]10;#ffffff\007\033]11;#000000\007\033]12;#ffffff\007' > /dev/tty
    jobs_style_index=0
    for jobs_style_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
        printf '\033]4;%s;#%s\007' "$jobs_style_index" "$jobs_style_color" > /dev/tty
        jobs_style_index=$((jobs_style_index + 1))
    done
    printf '\033[0m' > /dev/tty
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || { jobs_style_exit_status=1; exit 1; }
    stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    jobs_style_targets_ok=1
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_applied_rows="$jobs_style_applied_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_original
"
        if ! jobs_terminal_style_accepts_target "$jobs_style_key"; then
            jobs_style_targets_ok=0
        fi
    done <<JOBS_STYLE_ORIGINAL
$jobs_style_saved_rows
JOBS_STYLE_ORIGINAL
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '无法核实本次临时配色，已停止启动业务。' >&2
        jobs_style_exit_status=1
        exit 1
    fi
    jobs_style_applied_complete=1
    if [ "$jobs_style_targets_ok" != 1 ]; then
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; exit 129' HUP
        trap 'jobs_style_exit_status=130; exit 130' INT
        trap 'jobs_style_exit_status=143; exit 143' TERM
        printf '%s\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '%s\n' '本次终端已临时使用黑底白字。' >&2
    JOBS_TERMINAL_STYLE_TTY=$jobs_style_tty
    JOBS_TERMINAL_STYLE_OWNER=$$
    export JOBS_TERMINAL_STYLE_TTY JOBS_TERMINAL_STYLE_OWNER
    if "$@"; then
        jobs_style_exit_status=0
    else
        jobs_style_exit_status=$?
    fi
    exit "$jobs_style_exit_status"
}
# 仅监督直接执行的入口；被 source 时不切换配色、不重新执行业务。
jobs_terminal_style_bootstrap() {
    jobs_style_bootstrap_script=$1
    shift
    if [ -n "${ZSH_VERSION:-}" ]; then
        case ${ZSH_EVAL_CONTEXT:-} in
            *:file|*:file:*) return 0 ;;
        esac
    elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$jobs_style_bootstrap_script}" != "$jobs_style_bootstrap_script" ]; then
        return 0
    fi
    if [ "${JOBS_TERMINAL_STYLE_REEXEC:-}" = "$jobs_style_bootstrap_script" ]; then
        unset JOBS_TERMINAL_STYLE_REEXEC
        return 0
    fi
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       [ -n "${TMUX:-}${STY:-}" ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        return 0
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null &&
               [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$(tty 2>/dev/null)" ]; then
                return 0
            fi
            ;;
    esac
    JOBS_TERMINAL_STYLE_REEXEC=$jobs_style_bootstrap_script
    export JOBS_TERMINAL_STYLE_REEXEC
    jobs_terminal_style_run /bin/zsh "$jobs_style_bootstrap_script" "$@"
    jobs_style_bootstrap_result=$?
    exit "$jobs_style_bootstrap_result"
}
jobs_terminal_style_bootstrap "$0" "$@"
# <<< Jobs terminal style protection v1 <<<

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
