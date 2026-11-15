#!/bin/zsh
# 脚本自述：
# - 脚本名称：entrypoint_tests.zsh
# - 核心用途：隔离验证入口确认、日志配色和中断回收。
# - 影响范围：仅创建临时目录与假业务子进程，不执行真实更新。
# - 运行提示：自动执行回归，按 Ctrl+C 可取消。

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
    # 完整颜色帧有界重发；仅退出恢复容忍帧外回车和明确方向键。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        jobs_style_reply=''
        jobs_style_query_buffer=''
        jobs_style_query_target_reply=''
        jobs_style_query_target_normalized=''
        jobs_style_query_target_rgb=''
        jobs_style_query_st="${jobs_style_esc}\\"
        jobs_style_query_stale_count=0
        jobs_style_query_phase=${2:-strict}
        jobs_style_query_cr=$(printf '\r')
        jobs_style_query_lf=$(printf '\n.')
        jobs_style_query_lf=${jobs_style_query_lf%.}
        jobs_style_query_failure='未收到目标颜色的完整答复（最多 3 次查询，每次约 2 秒）'
        for jobs_style_query_round in 1 2 3; do
            printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || {
                jobs_style_query_failure='无法向原终端发送配色查询'
                return 1
            }
            for jobs_style_attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
                # 哨兵保留末尾换行，不能把只有回车的键盘输入误当成无答复。
                jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty; printf '.')
                jobs_style_piece=${jobs_style_piece%.}
                jobs_style_query_buffer=$jobs_style_query_buffer$jobs_style_piece
                while [ -n "$jobs_style_query_buffer" ]; do
                    # 仅退出恢复阶段允许帧外的明确控制键，普通文字仍然失败。
                    if [ "$jobs_style_query_phase" = cleanup ]; then
                        jobs_style_query_control_sequence=''
                        jobs_style_query_control_partial=0
                        case $jobs_style_query_buffer in
                            "$jobs_style_query_cr"*) jobs_style_query_control_sequence=$jobs_style_query_cr ;;
                            "$jobs_style_query_lf"*) jobs_style_query_control_sequence=$jobs_style_query_lf ;;
                        esac
                        if [ -z "$jobs_style_query_control_sequence" ]; then
                            for jobs_style_query_direction in A B C D; do
                                for jobs_style_query_control_candidate in \
                                    "${jobs_style_esc}[${jobs_style_query_direction}" \
                                    "${jobs_style_esc}O${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;2${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;3${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;4${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;5${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;6${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;7${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;8${jobs_style_query_direction}"; do
                                    case $jobs_style_query_buffer in
                                        "$jobs_style_query_control_candidate"*)
                                            jobs_style_query_control_sequence=$jobs_style_query_control_candidate
                                            break 2
                                            ;;
                                    esac
                                    case $jobs_style_query_control_candidate in
                                        "$jobs_style_query_buffer"*) jobs_style_query_control_partial=1 ;;
                                    esac
                                done
                            done
                        fi
                        if [ -n "$jobs_style_query_control_sequence" ]; then
                            jobs_style_cleanup_control_keys=$(( ${jobs_style_cleanup_control_keys:-0} + 1 ))
                            if [ "$jobs_style_cleanup_control_keys" -gt 64 ]; then
                                jobs_style_query_failure='退出恢复期间已识别控制键超过 64 个，已停止自动恢复'
                                return 1
                            fi
                            jobs_style_query_buffer=${jobs_style_query_buffer#"$jobs_style_query_control_sequence"}
                            continue
                        fi
                        if [ "$jobs_style_query_control_partial" = 1 ]; then
                            break
                        fi
                    fi
                    case $jobs_style_query_buffer in
                        "$jobs_style_esc"|"$jobs_style_esc]") break ;;
                        "$jobs_style_esc]"*) ;;
                        *) jobs_style_query_failure='收到非配色查询输入，已停止读取'; return 1 ;;
                    esac
                    jobs_style_query_head=''
                    jobs_style_query_terminator=''
                    case $jobs_style_query_buffer in
                        *"$jobs_style_bel"*)
                            jobs_style_query_head=${jobs_style_query_buffer%%"$jobs_style_bel"*}
                            jobs_style_query_terminator=$jobs_style_bel
                            ;;
                    esac
                    case $jobs_style_query_buffer in
                        *"$jobs_style_query_st"*)
                            jobs_style_query_st_head=${jobs_style_query_buffer%%"$jobs_style_query_st"*}
                            if [ -z "$jobs_style_query_terminator" ] ||
                               [ "${#jobs_style_query_st_head}" -lt "${#jobs_style_query_head}" ]; then
                                jobs_style_query_head=$jobs_style_query_st_head
                                jobs_style_query_terminator=$jobs_style_query_st
                            fi
                            ;;
                    esac
                    [ -n "$jobs_style_query_terminator" ] || break
                    jobs_style_query_frame=$jobs_style_query_head$jobs_style_query_terminator
                    jobs_style_query_buffer=${jobs_style_query_buffer#"$jobs_style_query_frame"}
                    jobs_style_query_body=${jobs_style_query_head#"$jobs_style_esc]"}
                    case $jobs_style_query_body in
                        *';rgb:'*) ;;
                        *) jobs_style_query_failure='配色答复格式或 RGB 数据无效'; return 1 ;;
                    esac
                    jobs_style_query_frame_key=${jobs_style_query_body%%';rgb:'*}
                    case $jobs_style_query_frame_key in
                        10|11|12|'4;'[0-9]|'4;1'[0-5]) ;;
                        *) jobs_style_query_failure='收到不属于本次颜色协议的答复'; return 1 ;;
                    esac
                    jobs_style_query_frame_rgb=${jobs_style_query_body#"$jobs_style_query_frame_key;rgb:"}
                    jobs_style_query_frame_normalized=$(printf '%s\n' "$jobs_style_query_frame_rgb" | LC_ALL=C awk -F/ '
                        BEGIN { valid = 1 }
                        NR != 1 || NF != 3 { valid = 0; exit }
                        {
                            for (i = 1; i <= 3; i++) {
                                h = tolower($i)
                                if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) {
                                    valid = 0
                                    exit
                                }
                                n = 0
                                for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                                value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                            }
                        }
                        END {
                            if (!valid || NR != 1) exit 1
                            printf "%d/%d/%d", value[1], value[2], value[3]
                        }
                    ')
                    if [ -z "$jobs_style_query_frame_normalized" ]; then
                        jobs_style_query_failure='配色答复格式或 RGB 数据无效'
                        return 1
                    fi
                    if [ "$jobs_style_query_frame_key" = "$jobs_style_query_key" ]; then
                        if [ -n "$jobs_style_query_target_reply" ] &&
                           [ "$jobs_style_query_target_normalized" != "$jobs_style_query_frame_normalized" ]; then
                            jobs_style_query_failure='同一颜色的重复答复不一致，已停止自动恢复'
                            return 1
                        fi
                        jobs_style_query_target_reply=$jobs_style_query_frame
                        jobs_style_query_target_normalized=$jobs_style_query_frame_normalized
                        jobs_style_query_target_rgb=$jobs_style_query_frame_rgb
                    else
                        jobs_style_query_stale_count=$((jobs_style_query_stale_count + 1))
                        if [ "$jobs_style_query_stale_count" -gt 128 ]; then
                            jobs_style_query_failure='收到过多旧颜色答复，已停止读取'
                            return 1
                        fi
                    fi
                done
                if [ -n "$jobs_style_query_target_reply" ] && [ -z "$jobs_style_query_buffer" ]; then
                    jobs_style_reply=$jobs_style_query_target_reply
                    jobs_style_normalized=$jobs_style_query_target_normalized
                    jobs_style_rgb=$jobs_style_query_target_rgb
                    return 0
                fi
            done
            # 残缺帧不能通过重发拼成另一个答复，更不能被当成键盘空输入。
            if [ -n "$jobs_style_query_buffer" ]; then
                jobs_style_query_failure='配色答复帧不完整，已停止自动恢复'
                return 1
            fi
        done
        return 1
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
            jobs_style_cleanup_issue='无法读取或设置原终端输入模式，或临时配色未完成核验'
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            jobs_style_cleanup_control_keys=0
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key" cleanup; then
                            jobs_style_cleanup_ok=0
                            jobs_style_cleanup_issue="颜色项 $jobs_style_key：$jobs_style_query_failure"
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
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_cleanup_ok=0; jobs_style_cleanup_issue='无法恢复原终端输入模式'; }
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
                printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_cleanup_issue" "$jobs_style_recovery" >&2
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
    trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
    trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
    trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
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
        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
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
function sudo() {
  print -r -- "sudo|$*" >> "$ENTRY_TEST_CASE/sudo-calls"
  if [[ "$*" == '-n -v' ]]; then
    [[ "${ENTRY_TEST_AUTH:-denied}" == cached || -f "$ENTRY_TEST_CASE/authorized" ]]
  elif [[ "$*" == '-v' ]]; then
    print -r -- 'MOCK_INITIAL_AUTH'
    local answer=''
    IFS= read -r answer || return 1
    [[ "$answer" == authorize ]] || return 1
    : > "$ENTRY_TEST_CASE/authorized"
  elif [[ "$*" == '-n fixture-command' && ( "${ENTRY_TEST_AUTH:-denied}" == cached || -f "$ENTRY_TEST_CASE/authorized" ) ]]; then
    return 0
  else
    print -u2 -r -- 'sudo: a password is required'
    return 1
  fi
}
if [[ "${ENTRY_TEST_MODE:-stub}" == auth ]]; then
  function jobs_update_show_readme_and_wait() { return 0; }
  function update() {
    [[ -z "$JOBS_UPDATE_SUDO_KEEPALIVE_PID" ]] || print -r -- "$JOBS_UPDATE_SUDO_KEEPALIVE_PID" > "$ENTRY_TEST_CASE/keepalive"
    jobs_update_run_sudo_cmd '假管理员任务' fixture-command
  }
elif [[ "${ENTRY_TEST_MODE:-stub}" == signal ]]; then
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
  export ENTRY_TEST_CASE="$TEST_ROOT/case-$TEST_COUNT" ENTRY_TEST_MODE=stub ENTRY_TEST_RESULT=0 ENTRY_TEST_AUTH=denied TERM=xterm-256color
  unset NO_COLOR
  /bin/mkdir -p "$ENTRY_TEST_CASE/runtime"
  print -r -- preserved > "$ENTRY_TEST_CASE/log"
  : > "$ENTRY_TEST_CASE/calls"
  TEST_TRANSCRIPT=''
}
# 限定等待时间，避免入口回归后测试无限挂起。
wait_for_file() {
  local attempt
  for attempt in {1..500}; do
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
  for attempt in {1..500}; do
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
  for attempt in {1..500}; do
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
# 缓存授权直接全量执行，正常退出后本轮保活进程已结束。
test_cached_auth_cleanup() {
  export ENTRY_TEST_MODE=auth ENTRY_TEST_AUTH=cached
  /bin/zsh "$TEST_ROOT/driver.zsh" -t </dev/null > "$ENTRY_TEST_CASE/output" 2>&1 || return 1
  local keepalive_pid="$(< "$ENTRY_TEST_CASE/keepalive")"
  ! kill -0 "$keepalive_pid" 2>/dev/null || return 1
  [[ "$(< "$ENTRY_TEST_CASE/sudo-calls")" == $'sudo|-n -v\nsudo|-n fixture-command' ]]
}
# 后台无授权时不尝试密码输入，管理员任务必须真实返回未完成。
test_background_auth_denied() {
  export ENTRY_TEST_MODE=auth
  local result=0
  /bin/zsh "$TEST_ROOT/driver.zsh" -t </dev/null > "$ENTRY_TEST_CASE/output" 2>&1 || result=$?
  [[ "$result" == 1 && ! -f "$ENTRY_TEST_CASE/keepalive" ]] || return 1
  [[ "$(< "$ENTRY_TEST_CASE/sudo-calls")" == $'sudo|-n -v\nsudo|-n fixture-command' ]] || return 1
  /usr/bin/grep -Fq '缺少该命令的管理员授权' "$ENTRY_TEST_CASE/log"
}
# 真实 TTY 只在开头询问一次，后续管理员动作均为非交互执行。
test_initial_auth_once() {
  export ENTRY_TEST_MODE=auth
  TEST_PTY="entry-auth-$TEST_COUNT"
  zpty -b "$TEST_PTY" /bin/zsh "$TEST_ROOT/driver.zsh" -t || return 1
  local attempt ready=0
  for attempt in {1..500}; do
    drain_pty
    if [[ "$TEST_TRANSCRIPT" == *MOCK_INITIAL_AUTH* ]]; then
      ready=1
      break
    fi
    /bin/sleep 0.02
  done
  (( ready == 1 )) || return 1
  zpty -w "$TEST_PTY" authorize
  finish_pty || return 1
  [[ "$(< "$ENTRY_TEST_CASE/result")" == 0 ]] || return 1
  [[ "$(< "$ENTRY_TEST_CASE/sudo-calls")" == $'sudo|-n -v\nsudo|-v\nsudo|-n fixture-command' ]] || return 1
  ! kill -0 "$(< "$ENTRY_TEST_CASE/keepalive")" 2>/dev/null
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
  run_case '缓存授权直接执行且结束停止保活' test_cached_auth_cleanup
  run_case '后台无授权不等待密码并报告未完成' test_background_auth_denied
  run_case '启动时一次授权后无交互执行' test_initial_auth_once
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
