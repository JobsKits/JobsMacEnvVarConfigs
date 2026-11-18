#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】gif.command
# - 核心用途：执行“gif”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

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
    jobs_style_original_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 完整颜色帧有界重发；设置核验与退出恢复容忍帧外回车和明确方向键。
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
                    # 设置核验与退出恢复阶段允许帧外的明确控制键，普通文字仍然失败。
                    if [ "$jobs_style_query_phase" = cleanup ] || [ "$jobs_style_query_phase" = applied ]; then
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
                            jobs_style_phase_control_keys=$(( ${jobs_style_phase_control_keys:-0} + 1 ))
                            if [ "$jobs_style_phase_control_keys" -gt 64 ]; then
                                jobs_style_query_failure='本阶段已识别控制键超过 64 个，已停止自动恢复'
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
    # 核验中断时重新读取当前值，只撤回仍等于本轮目标值的颜色。
    jobs_terminal_style_rollback() {
        jobs_style_rollback_issue='无法读取或设置原终端输入模式'
        jobs_style_rollback_safe=''
        jobs_style_rollback_conflicts=''
        jobs_style_phase_control_keys=0
        jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
        if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
            jobs_style_query_active=1
            jobs_style_rollback_ok=1
            while IFS='|' read -r jobs_style_key jobs_style_original_normalized jobs_style_original; do
                [ -n "$jobs_style_key" ] || continue
                if ! jobs_terminal_style_query "$jobs_style_key" cleanup; then
                    jobs_style_rollback_ok=0
                    jobs_style_rollback_issue="回退颜色项 $jobs_style_key：$jobs_style_query_failure"
                    break
                fi
                if [ "$jobs_style_normalized" = "$jobs_style_original_normalized" ]; then
                    continue
                elif jobs_terminal_style_accepts_target "$jobs_style_key"; then
                    jobs_style_rollback_safe=$jobs_style_rollback_safe$jobs_style_original
                else
                    jobs_style_rollback_conflicts="$jobs_style_rollback_conflicts $jobs_style_key"
                fi
            done <<JOBS_STYLE_ROLLBACK
$jobs_style_original_rows
JOBS_STYLE_ROLLBACK
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_rollback_ok=0; jobs_style_rollback_issue='无法恢复原终端输入模式'; }
            jobs_style_query_active=0
            if [ "$jobs_style_rollback_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_rollback_safe" > /dev/tty; then
                if [ -z "$jobs_style_rollback_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                    return 0
                fi
                printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_rollback_conflicts" >&2
                jobs_style_rollback_issue="核验中断后检测到其它配色变更：$jobs_style_rollback_conflicts"
            fi
        fi
        printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_rollback_issue" "$jobs_style_recovery" >&2
        return 1
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ] && [ "$jobs_style_applied_complete" != 1 ]; then
            if jobs_terminal_style_rollback; then
                jobs_style_changed=0
            else
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
            if [ "${2:-}" = continue ]; then
                jobs_style_cleanup_status=$jobs_style_result
                return 0
            fi
            exit "$jobs_style_result"
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_cleanup_issue='无法读取或设置原终端输入模式，或临时配色未完成核验'
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            jobs_style_phase_control_keys=0
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
        jobs_style_original_rows="$jobs_style_original_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_reply
"
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
    jobs_style_phase_control_keys=0
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key" applied; then
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
        printf '临时配色核验失败（颜色项 %s：%s），正在核对原色恢复。\n' "$jobs_style_key" "$jobs_style_query_failure" >&2
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
        printf '%s\n' '已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
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
    jobs_style_applied_complete=1
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

# >>> Jobs list parent confirmation >>>
# 只读确认键；返回码20仅交给实际启动本功能的list父菜单。
jobs_list_confirm_start() {
  emulate -L zsh
  local jobs_list_key='' jobs_list_prefix='' jobs_list_direction=''
  [[ -t 0 ]] || return 130
  print -u2 -n -r -- "$(jobs_prompt_render '按回车继续；← 返回功能菜单；Esc / Ctrl+C 取消：')"
  while true; do
    IFS= read -rsk1 jobs_list_key || return 130
    case "$jobs_list_key" in
      $'\r'|$'\n') print -u2; return 0 ;;
      $'\e')
        jobs_list_prefix=''
        IFS= read -rsk1 -t 0.12 jobs_list_prefix || { print -u2; return 130; }
        case "$jobs_list_prefix" in
          '['|'O')
            jobs_list_direction=''
            IFS= read -rsk1 -t 0.12 jobs_list_direction || { print -u2; return 130; }
            [[ "$jobs_list_direction" != D ]] || { print -u2; return 20; }
            ;;
          *) print -u2; return 130 ;;
        esac
        ;;
      $'\003') print -u2; return 130 ;;
    esac
  done
}
# 独立启动保留原read参数；list来源的返回/取消立即结束子脚本而不执行业务。
jobs_list_intro_read() {
  if [[ "${JOBS_LIST_PARENT_MENU:-}" != list ]]; then
    builtin read "$@"
    return $?
  fi
  local jobs_list_confirm_status=0
  jobs_list_confirm_start || jobs_list_confirm_status=$?
  (( jobs_list_confirm_status == 0 )) || exit "$jobs_list_confirm_status"
}
# <<< Jobs list parent confirmation <<<



# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
# URL仅供显示；纯文本日志传color=0。
jobs_url_format() {
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-1}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", urlRender(pending)
        pending = $0; first = 0
      } else {
        if (!lines && !first) printf "\n"
        printf "%s", urlRender($0)
        if (lines) printf "\n"
        first = 0
      }
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", urlRender(pending)
      }
    }
  '
}
# URL仅供显示；纯文本日志传color=0。
jobs_url_stream() {
  local url_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then url_color=1; fi
  jobs_url_format "$url_color" "${1:-1}"
}
jobs_prompt_color_ready() {
  env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)' && return 1
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  # 中文字符类按UTF-8字符处理，仅约束此awk进程，保留调用者locale。
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" -v question="${4:-0}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
    function typedEnter(value, start, prefix) {
      prefix = substr(value, 1, start - 1)
      gsub(/[“”‘’「」『』"]/, "", prefix)
      gsub(sprintf("%c", 39), "", prefix)
      if (prefix ~ /(空格|[Ss][Pp][Aa][Cc][Ee])[[:space:]]*(后|再|并|[Tt][Hh][Ee][Nn])?[[:space:]]*$/) return 1
      return prefix ~ /(输入|键入|填写|[Tt]ype)[^；;|]*[[:alnum:]_+-]+[[:space:]]*(后|再|并)?[[:space:]]*$/
    }
    function greenPosition(value, token, start) {
      if (match(value, /(直接|仅|只需|只|按下|按)?[[:space:]]*(回车|回車)/)) {
        start = RSTART
        return typedEnter(value, start) ? 0 : start
      }
      if (!match(value, /(^|[^[:alnum:]_])([Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn])([^[:alnum:]_]|$)/)) return 0
      start = RSTART
      token = substr(value, RSTART, RLENGTH)
      match(token, /[Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]/)
      start += RSTART - 1
      return typedEnter(value, start) ? 0 : start
    }
    function segment(value, inherited, is_question, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
      if (value == "") return value
      kind = inherited
      start = 1
      if (!kind) {
        if (match(value, /(输入)?(任意|任何)(非空)?(字符|内容|输入|键)|非空(字符|内容|输入)?|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key/)) {
          red = RSTART
        }
        green = greenPosition(value)
        if (red && green && green < red) {
          left = substr(value, 1, red - 1)
          right = substr(value, red)
          connector = ""
          if (match(left, /(或者|或)[[:space:]]*$/)) {
            connector = substr(left, RSTART)
            left = substr(left, 1, RSTART - 1)
          }
          return segment(left, 0, is_question) connector segment(right, 31, 0)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31, is_question) "或" segment(substr(value, splitAt + length("或")), 0, 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!color) return value
      if (!kind) return is_question && value !~ /^[[:space:]]*$/ ? esc "[1;36m" value esc "[0m" : value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      if (is_question && prefix !~ /^[[:space:]]*$/) prefix = esc "[1;36m" prefix esc "[0m"
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original, question_body) {
      original = value
      value = urlProtect(urlClean(value, 0))
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return urlRender(original)
      output = ""
      inherited = 0
      depth = 0
      question_body = question
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited, question_body) boundary
        if (inherited || greenPosition(part) || part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) question_body = 0
        if (boundary ~ /[（(\[【]/) {
          depth++
          if (part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) inherited = 31
          else if (greenPosition(part)) inherited = 32
        } else if (boundary ~ /[）)\]】]/) {
          if (depth) depth--
        } else if (boundary ~ /[：:=＝]/) {
          if (!inherited) {
            if (part ~ /(任意|任何|非空|其它输入|其他输入)/) inherited = 31
            else if (greenPosition(part)) inherited = 32
          }
        } else if (!depth) inherited = 0
        value = substr(value, consumed)
      }
      return urlRender(urlRestore(output segment(value, inherited, question_body) (question && color ? esc "[0m" : "")))
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", render(pending)
        pending = $0
        first = 0
        next
      }
      if (!lines && !first) printf "\n"
      printf "%s", render($0)
      if (lines) printf "\n"
      first = 0
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", render(pending)
      }
    }
  '
}
# read 的命令替换会使 stdout 成为管道，按输入与提示所在 stderr 判断终端。
jobs_prompt_render() {
  local jobs_prompt_color=0
  if [ -t 0 ] && [ -t 2 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0 0 1
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 1
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous=""
  if [ "${1:-}" = print ]; then
    for jobs_prompt_arg in "$@"; do
      case "$jobs_prompt_arg" in -?*u2*|-u2) jobs_prompt_stderr=1 ;; esac
      if [ "$jobs_prompt_previous" = -u ] && [ "$jobs_prompt_arg" = 2 ]; then jobs_prompt_stderr=1; fi
      jobs_prompt_previous="$jobs_prompt_arg"
      [ "$jobs_prompt_arg" != -- ] || break
    done
  fi
  if [ -n "${ZSH_VERSION:-}" ]; then
    if [ "$jobs_prompt_stderr" = 1 ]; then
      "$@" 2>&1 | jobs_prompt_filter >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$?
  fi
  return "$jobs_prompt_status"
}
# 仅替换日志 primitive 的 tee：磁盘同步追加纯文，终端保留非选项原色。
jobs_prompt_tee() {
  local jobs_prompt_log="$1" jobs_prompt_line="" jobs_prompt_newline=0
  while :; do
    jobs_prompt_line=""
    if IFS= read -r jobs_prompt_line; then jobs_prompt_newline=1; else jobs_prompt_newline=0; [ -n "$jobs_prompt_line" ] || break; fi
    if [ "$jobs_prompt_newline" = 1 ]; then
      { printf '%s\n' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s\n' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    else
      { printf '%s' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    fi
  done
}
# JOBS_INPUT_CHOICE_STYLE_END

jobs_brew_note() {
  jobs_prompt_output print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  jobs_prompt_output print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "$(jobs_prompt_render "➤ 安装路径选择：")"
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
# 共用原生依赖获取：jobs_brew_download_file。
jobs_brew_download_file() {
  local destination="$1" description="$2" download_url attempt download_result=1 http_code
  local retry_round=0 retry_delay=1 round_has_retryable=0
  local -a request_headers download_urls
  local -A blocked_urls
  shift 2
  download_urls=("$@")
  (( ${#download_urls} > 0 )) || { jobs_brew_note '没有已声明的官方获取地址。'; return 2; }
  while true; do
    (( retry_round += 1 ))
    round_has_retryable=0
    for download_url in "${download_urls[@]}"; do
      [[ -z "${blocked_urls[$download_url]:-}" ]] || continue
      request_headers=()
      if [[ "$download_url" == https://api.github.com/repos/Homebrew/install/contents/install.sh\?ref=HEAD ]]; then
        request_headers=(-H 'Accept: application/vnd.github.raw+json')
      fi
      for attempt in 1 2 3; do
        jobs_brew_note "下载${description}（第 $retry_round 轮，第 $attempt 次）：$download_url"
        download_result=0
        http_code="$(curl -q -fsSL --proto '=https' --proto-redir '=https' \
          --connect-timeout 10 --max-time 30 "${request_headers[@]}" \
          --write-out '%{http_code}' "$download_url" -o "$destination" \
          2> >(tee -a "${LOG_FILE:-/dev/null}" >&2))" || download_result=$?
        if (( download_result == 0 )); then
          return 0
        fi
        rm -f -- "$destination" || return 1
        jobs_brew_note "${description}下载失败：curl 退出码 $download_result，HTTP ${http_code:-未知}。"
        case "$download_result" in
          129|130|143) return "$download_result" ;;
          5|6|7|18|28|35|52|55|56) ;;
          22)
            if [[ "$http_code" != 408 && "$http_code" != 429 && "$http_code" != 5[0-9][0-9] ]]; then
              blocked_urls[$download_url]=1
              break
            fi
            ;;
          *) blocked_urls[$download_url]=1; break ;;
        esac
        if (( attempt < 3 )); then
          jobs_brew_note '临时连接失败，1 秒后重试同一官方地址；Ctrl+C 可取消。'
          sleep 1 || return $?
        fi
      done
      if [[ -z "${blocked_urls[$download_url]:-}" ]]; then
        round_has_retryable=1
      fi
      jobs_brew_note '当前地址尚未取得可用响应；如有下一已声明官方地址，将按原顺序尝试，安装目录不变。'
    done
    if (( round_has_retryable == 0 )); then
      jobs_brew_note "获取${description}遇到确定错误，停止；未执行安装。日志：${LOG_FILE:-终端输出}。"
      return "$download_result"
    fi
    jobs_brew_note "官方来源暂时不可用，${retry_delay} 秒后继续下一轮；不设总次数或总时长上限，按 Ctrl+C 取消。"
    sleep "$retry_delay" || return $?
    if (( retry_delay < 30 )); then
      retry_delay=$(( retry_delay * 2 ))
      (( retry_delay <= 30 )) || retry_delay=30
    fi
  done
}

# 共用原生依赖获取：jobs_brew_stop_acquisition_tree。
jobs_brew_stop_acquisition_tree() {
  local root="$1" child=""
  for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
    jobs_brew_stop_acquisition_tree "$child"
  done
  /bin/kill -TERM "$root" 2>/dev/null || true
  /bin/kill -KILL "$root" 2>/dev/null || true
}

# 共用原生依赖获取：jobs_brew_fetch_release。
jobs_brew_fetch_release() {
  setopt LOCAL_OPTIONS LOCAL_TRAPS NO_ERREXIT
  local git_bin="$1" release_tag="$2" stage="$3" target="${3}/brew"
  local attempt_log="${3}/git-fetch-attempt.log" history="${3}/git-fetch-history.log"
  local attempt=1 result=0 delay=1 task_pid="" interrupted=0 failure=""
  [[ "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$stage" == /* &&
     "${stage:t}" == .jobs-homebrew.* && -d "$stage" && ! -L "$stage" && ! -e "$target" && ! -L "$target" ]] || {
    jobs_brew_note 'Homebrew 获取版本或私有暂存路径无效，未执行 Git 获取。'
    return 2
  }
  "$git_bin" init --quiet "$target" || { result=$?; jobs_brew_note "Homebrew 暂存仓初始化失败（$result）：$target"; return "$result"; }
  "$git_bin" -C "$target" remote add origin https://github.com/Homebrew/brew.git || return $?
  trap 'interrupted=130; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' INT
  trap 'interrupted=143; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' TERM
  trap 'interrupted=129; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' HUP
  while true; do
    jobs_brew_note "获取 Homebrew 官方版本 $release_tag（第 $attempt 次）：https://github.com/Homebrew/brew.git → $target；失败自动重试，Ctrl+C 取消。"
    : > "$attempt_log" || return 1
    print -r -- "━━ Homebrew $release_tag：第 $attempt 次 ━━" >> "$history" || return 1
    (
      local -a acquisition_statuses
      LC_ALL=C GIT_TERMINAL_PROMPT=0 "$git_bin" -C "$target" -c color.ui=false \
        -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 fetch --progress --depth 1 origin "refs/tags/$release_tag" 2>&1 |
        jobs_prompt_tee "$history" | jobs_prompt_tee "${LOG_FILE:-/dev/null}" | jobs_prompt_tee "$attempt_log" >&2
      acquisition_statuses=("${pipestatus[@]}")
      (( acquisition_statuses[2] == 0 && acquisition_statuses[3] == 0 && acquisition_statuses[4] == 0 )) || exit 74
      exit "${acquisition_statuses[1]}"
    ) <&0 &
    task_pid=$!
    result=0
    wait "$task_pid" || result=$?
    task_pid=""
    (( interrupted == 0 )) || return "$interrupted"
    jobs_brew_note "Homebrew $release_tag 获取第 $attempt 次退出码：$result。"
    if (( result == 0 )); then
      "$git_bin" -C "$target" checkout --quiet --detach FETCH_HEAD || return $?
      return 0
    fi
    case "$result" in
      74) jobs_brew_note "Homebrew 获取日志写入失败，停止；请检查磁盘空间、路径和权限。"; return 74 ;;
      129|130|131|137|143|126|127) return "$result" ;;
    esac
    failure="$(/usr/bin/tail -c 65536 "$attempt_log")" || return 1
    if print -r -- "$failure" | /usr/bin/grep -Eqi \
      'Permission denied|Operation not permitted|No space left on device|Read-only file system|File exists|already exists and is not an empty directory|Bad CPU type|Exec format error|unknown option|unrecognized option|invalid argument|couldn.t find remote ref|Remote branch .* not found|repository .* not found|Authentication failed|could not read Username|terminal prompts disabled|HTTP[^[:cntrl:]]*(401|403|404)|returned error: (401|403|404)|SSL certificate problem|certificate verify failed|unable to get local issuer certificate'; then
      jobs_brew_note "Homebrew 官方版本获取遇到本地、认证、证书或版本确定错误（$result），已停止；请核对日志：${LOG_FILE:-$history}。"
      return "$result"
    fi
    jobs_brew_note "Homebrew 网络获取尚未完成，保留本轮已收对象，${delay} 秒后继续；不设总次数或总时长上限，Ctrl+C 取消。"
    sleep "$delay" &
    task_pid=$!
    wait "$task_pid" || { result=$?; (( interrupted == 0 )) || return "$interrupted"; return "$result"; }
    task_pid=""
    (( interrupted == 0 )) || return "$interrupted"
    (( attempt += 1 ))
    (( delay >= 30 )) || delay=$(( delay * 2 ))
    (( delay <= 30 )) || delay=30
  done
}

# 共用原生依赖获取：jobs_brew_stop_failed_install。
jobs_brew_stop_failed_install() {
  case "$1" in
    129|130|143) exit "$1" ;;
    *) exit 1 ;;
  esac
}

jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if jobs_brew_download_file "$installer" 'Homebrew 官方安装器' \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
      'https://api.github.com/repos/Homebrew/install/contents/install.sh?ref=HEAD'; then
    if [[ ! -s "$installer" || "$(head -n 1 "$installer")" != '#!/bin/bash' ]] || ! /bin/bash -n "$installer"; then
      rm -f -- "$installer"
      jobs_brew_note '官方安装器响应为空或内容校验失败（可能是 HTML / JSON 错误页）；未执行安装。'
      return 1
    fi
  else
    installer_result=$?
    rm -f -- "$installer"
    jobs_brew_note "系统目录安装器下载失败（curl 退出码 $installer_result）；尚未执行安装，不自动切换安装路径。"
    return "$installer_result"
  fi
  /bin/bash "$installer" || installer_result=$?
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return "$installer_result"
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin release_result=0
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  local git_health=1 locate_result=0 git_candidate="" selected_developer="" clt_result=0 clt_diagnostic=""
  git_bin="$(command -v git 2>/dev/null)"
  # /usr/bin/git 可能只是CLT占位器；先查询真实工具，避免健康检查自行弹出安装窗口。
  if [[ "$git_bin" == /usr/bin/git || -z "$git_bin" ]]; then
    git_bin="$(/usr/bin/xcrun --find git 2>/dev/null)" || locate_result=$?
    case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
  fi
  if [[ -n "$git_bin" && -x "$git_bin" ]]; then
    git_health=0;"$git_bin" --version >/dev/null 2>&1 || git_health=$?
    case "$git_health" in 129|130|131|137|143) return "$git_health" ;; esac
  fi
  if (( git_health != 0 )); then
    [[ -z "${DEVELOPER_DIR:-}" ]] || { jobs_brew_note '显式DEVELOPER_DIR没有健康Git，保留用户开发目录，未自动改全局选择。'; return 1; }
    locate_result=0
    selected_developer="$(/usr/bin/xcode-select -p 2>/dev/null)" || locate_result=$?
    case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
    if [[ -n "$selected_developer" && -d "$selected_developer" ]]; then
      jobs_brew_note "既有开发目录未提供健康Git：$selected_developer；可能是许可、版本或本地文件阻塞，未反复安装或改全局xcode-select。"
      return 1
    fi
    if [[ "${DRY_RUN:-0}" == 1 || "${CHECK_ONLY:-0}" == 1 || ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]] ||
       env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
      jobs_brew_note '用户目录Homebrew需要健康Git；当前为只读或非交互入口，未打开CLT安装窗口或写安装目标。'
      return 1
    fi
    jobs_brew_note '当前已选用户目录Homebrew安装需要Apple Command Line Tools的Git；只打开一次原生安装窗口，许可由本人处理，当前流程持续复检，Ctrl+C停止。' || return $?
    clt_diagnostic="$(/usr/bin/xcode-select --install 2>&1)" || clt_result=$?
    jobs_brew_note "$clt_diagnostic" || return $?
    if (( clt_result != 0 )) && [[ "$clt_diagnostic" != *'already being installed'* && "$clt_diagnostic" != *'正在安装'* ]]; then return "$clt_result"; fi
    while true; do
      locate_result=0
      git_candidate="$(/usr/bin/xcrun --find git 2>/dev/null)" || locate_result=$?
      case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
      if [[ -n "$git_candidate" && -x "$git_candidate" ]]; then
        git_health=0;"$git_candidate" --version >/dev/null 2>&1 || git_health=$?
        case "$git_health" in 129|130|131|137|143) return "$git_health" ;; esac
        if (( git_health == 0 )); then git_bin="$git_candidate";break;fi
      fi
      jobs_brew_note '等待Apple CLT提供健康Git；不会重复打开窗口，Ctrl+C停止。' || return $?
      /bin/sleep 3 || return $?
    done
  fi
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if jobs_brew_download_file "$stage/release.json" 'Homebrew 官方稳定版本' \
      https://api.github.com/repos/Homebrew/brew/releases/latest; then
    release_result=0
  else
    release_result=$?
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本已停止（退出码 $release_result），未执行安装。"
    return "$release_result"
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    rm -r -- "$stage"
    jobs_brew_note '官方版本响应无有效 tag，停止；不重试版本解析或执行安装。'
    return 1
  fi
  if jobs_brew_fetch_release "$git_bin" "$release_tag" "$stage"; then
    release_result=0
  else
    release_result=$?
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 官方版本获取已停止（退出码 $release_result），未执行安装。"
    return "$release_result"
  fi
  if ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || jobs_brew_stop_failed_install $? ;;
      user) jobs_brew_install_user || jobs_brew_stop_failed_install $? ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  ' | jobs_prompt_filter
}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log()            { echo -e "$1" | jobs_prompt_tee "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }

APP_HOME="${JOBS_MAC_ENV_HOME:-$HOME/.JobsMacEnv}"
CONFIG_DIR="$APP_HOME/gif"
CONFIG_FILE="$CONFIG_DIR/config.zsh"
LATEST_FILE="$CONFIG_DIR/latest_path.txt"

GIF_OUTPUT_PARENT="$HOME/Desktop"
GIF_THEME="github-dark"
GIF_FONT_SIZE="28"
GIF_LINE_HEIGHT="1.35"
GIF_SPEED="1"
GIF_IDLE_TIME_LIMIT="1.2"
GIF_REC_IDLE_LIMIT="1.2"
GIF_FPS_CAP="30"
GIF_LAST_FRAME_DURATION="2"
GIF_RENDERER="swash"
GIF_TEXT_FONT_FAMILY="SF Mono,Menlo,JetBrains Mono,Fira Code"
GIF_NO_LOOP="false"
GIF_CLEAR_AFTER_FINISH="true"
GIF_VIDEO_ENABLED="true"
GIF_VIDEO_CRF="18"
GIF_VIDEO_PRESET="medium"

# 录制模式：默认永远是 terminal；只有进入设置菜单时才允许临时改为 screen。
GIF_RECORD_MODE="terminal"
GIF_SCREEN_COUNTDOWN="3"
GIF_SCREEN_SHOW_CURSOR="true"
GIF_SCREEN_FPS="24"
GIF_SCREEN_GIF_WIDTH="1600"

OUTPUT_DIR=""
CAST_FILE=""
GIF_FILE=""
VIDEO_FILE=""
SCREEN_MOV_FILE=""
META_FILE=""
RECORD_ZDOTDIR=""
AGG_BIN=""
FFMPEG_BIN=""
SCREENCAPTURE_BIN=""
SETTINGS_MENU="false"
# 封装 show_usage 对应的独立处理逻辑。
show_usage() {
  cat <<'EOF_USAGE' | jobs_prompt_filter
Jobs GIF / gif

用途：
  录制当前终端会话或整个屏幕，并在录制结束后转成高质量 GIF 和 MP4。

用法：
  gif
  gif --repair <输出目录、session.cast 或 session.mov>
  gif --help

启动录制：
  按 Enter：跳过设置菜单，默认使用“当前终端录制”。
  输入任意字符后回车：进入设置菜单，可选择“当前终端录制 / 全屏录制”，并配置路径、品质、视频输出。

录制模式：
  当前终端录制：基于 asciinema + agg。一个终端执行一次 gif 就生成一个录制结果；多个终端分别执行即可录制多个。
  全屏录制：基于 macOS screencapture + ffmpeg。只录整个屏幕，不做 App / 窗口录制。

排除 gif 干扰：
  所有设置、提示、路径输入、品质配置都发生在正式录制之前。
  真正开始录制前会清屏，尽量避免把 gif 程序自己的文字录进去。

结束录制：
  录制过程中按 Ctrl-C：停止录制，并立即转换 session.gif / session.mp4。
  不建议输入 exit，因为它会被录进去。

输出：
  默认输出到：~/Desktop/Gif@YYYY.MM.DD HH:MM:SS
  终端模式：session.cast、session.gif、session.mp4、README.md
  全屏模式：session.mov、session.mp4、session.gif、README.md
EOF_USAGE
}
# 执行对应的清理操作，并保留必要的安全检查。
clear_terminal_soft() {
  command clear 2>/dev/null || true
  printf '\033[3J\033[H\033[2J'
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_intro_if_double_clicked() {
  local current_name="$(basename -- "$SCRIPT_PATH")"
  [[ "$current_name" == *.command ]] || return 0

  clear_terminal_soft
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | jobs_intro_style title
  bold_echo "      Jobs GIF 录制入口" | jobs_intro_style title
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | jobs_intro_style title
  info_echo "本脚本支持当前终端录制和全屏录制，并在结束后生成 session.gif / session.mp4。" | jobs_intro_style body
  info_echo "正式开始录制前会清屏，gif 的设置过程不会进入录制内容。" | jobs_intro_style body
  warn_echo "结束录制：录制过程中按 Ctrl-C。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  gray_echo "输出默认路径：~/Desktop/Gif@YYYY.MM.DD HH:MM:SS" | jobs_intro_style body
  gray_echo "依赖工具：Homebrew、asciinema、agg、ffmpeg；全屏录制额外使用 macOS 自带 screencapture。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  print -u2 -r -- "$(jobs_prompt_render "按回车继续...")"
  local _answer=""
  IFS= jobs_list_intro_read -r _answer
}
# 解析并返回后续流程需要的目标信息。
get_cpu_arch() {
  uname -m
}
# 封装 trim_text 对应的独立处理逻辑。
trim_text() {
  local value="$1"
  value="$(printf "%s" "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf "%s" "$value"
}
# 封装 normalize_dragged_path 对应的独立处理逻辑。
normalize_dragged_path() {
  local raw="$1"
  raw="$(trim_text "$raw")"
  raw="${raw%$'\r'}"

  raw="${raw#\"}"
  raw="${raw%\"}"
  raw="${raw#\'}"
  raw="${raw%\'}"

  raw="${raw/#\~/$HOME}"
  raw="${raw//\\ / }"
  raw="${raw//\\(/(}"
  raw="${raw//\\)/)}"
  raw="${raw//\\&/&}"
  raw="${raw//\\'/'}"
  raw="${raw//\\\"/\"}"
  raw="${raw%/}"

  printf "%s" "$raw"
}
# 检查当前运行条件是否满足后续流程要求。
is_positive_int() {
  [[ "$1" =~ '^[0-9]+$' ]] && [[ "$1" -gt 0 ]]
}
# 检查当前运行条件是否满足后续流程要求。
is_nonnegative_int() {
  [[ "$1" =~ '^[0-9]+$' ]]
}
# 检查当前运行条件是否满足后续流程要求。
is_positive_number() {
  [[ "$1" =~ '^[0-9]+([.][0-9]+)?$' ]]
}
# 检查当前运行条件是否满足后续流程要求。
is_bool_text() {
  [[ "$1" == "true" || "$1" == "false" ]]
}
# 检查当前运行条件是否满足后续流程要求。
is_theme_text() {
  [[ "$1" =~ '^[A-Za-z0-9,_#.-]+$' ]]
}
# 封装 load_config 对应的独立处理逻辑。
load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0

  if source "$CONFIG_FILE" 2>>"$LOG_FILE"; then
    return 0
  fi

  warn_echo "历史配置读取失败，已使用默认配置：$CONFIG_FILE"
}
# 封装 quote_value 对应的独立处理逻辑。
quote_value() {
  printf "%q" "$1"
}
# 封装 save_config 对应的独立处理逻辑。
save_config() {
  mkdir -p "$CONFIG_DIR"
  {
    echo "# Jobs GIF 配置：自动生成"
    printf "GIF_OUTPUT_PARENT=%s\n" "$(quote_value "$GIF_OUTPUT_PARENT")"
    printf "GIF_THEME=%s\n" "$(quote_value "$GIF_THEME")"
    printf "GIF_FONT_SIZE=%s\n" "$(quote_value "$GIF_FONT_SIZE")"
    printf "GIF_LINE_HEIGHT=%s\n" "$(quote_value "$GIF_LINE_HEIGHT")"
    printf "GIF_SPEED=%s\n" "$(quote_value "$GIF_SPEED")"
    printf "GIF_IDLE_TIME_LIMIT=%s\n" "$(quote_value "$GIF_IDLE_TIME_LIMIT")"
    printf "GIF_REC_IDLE_LIMIT=%s\n" "$(quote_value "$GIF_REC_IDLE_LIMIT")"
    printf "GIF_FPS_CAP=%s\n" "$(quote_value "$GIF_FPS_CAP")"
    printf "GIF_LAST_FRAME_DURATION=%s\n" "$(quote_value "$GIF_LAST_FRAME_DURATION")"
    printf "GIF_RENDERER=%s\n" "$(quote_value "$GIF_RENDERER")"
    printf "GIF_TEXT_FONT_FAMILY=%s\n" "$(quote_value "$GIF_TEXT_FONT_FAMILY")"
    printf "GIF_NO_LOOP=%s\n" "$(quote_value "$GIF_NO_LOOP")"
    printf "GIF_CLEAR_AFTER_FINISH=%s\n" "$(quote_value "$GIF_CLEAR_AFTER_FINISH")"
    printf "GIF_VIDEO_ENABLED=%s\n" "$(quote_value "$GIF_VIDEO_ENABLED")"
    printf "GIF_VIDEO_CRF=%s\n" "$(quote_value "$GIF_VIDEO_CRF")"
    printf "GIF_VIDEO_PRESET=%s\n" "$(quote_value "$GIF_VIDEO_PRESET")"
    printf "GIF_SCREEN_COUNTDOWN=%s\n" "$(quote_value "$GIF_SCREEN_COUNTDOWN")"
    printf "GIF_SCREEN_SHOW_CURSOR=%s\n" "$(quote_value "$GIF_SCREEN_SHOW_CURSOR")"
    printf "GIF_SCREEN_FPS=%s\n" "$(quote_value "$GIF_SCREEN_FPS")"
    printf "GIF_SCREEN_GIF_WIDTH=%s\n" "$(quote_value "$GIF_SCREEN_GIF_WIDTH")"
  } > "$CONFIG_FILE"
}
# 封装 refresh_brew_shellenv 对应的独立处理逻辑。
refresh_brew_shellenv() {
  JOBS_HOMEBREW_BIN="$(jobs_brew_find)" || return 1
  jobs_brew_activate
}
# 封装 inject_shellenv_block 对应的独立处理逻辑。
inject_shellenv_block() {
  local profile_file="$1"
  local shellenv_cmd="$2"
  local id="Homebrew"
  local header="# >>> ${id} 环境变量 >>>"
  local footer="# <<< ${id} 环境变量 <<<"

  if [[ -z "$profile_file" || -z "$shellenv_cmd" ]]; then
    error_echo "缺少参数：inject_shellenv_block <profile_file> <shellenv_cmd>"
    return 1
  fi

  touch "$profile_file"

  if grep -Fq "$shellenv_cmd" "$profile_file"; then
    info_echo "Homebrew shellenv 已存在：$profile_file"
    return 0
  fi

  {
    echo ""
    echo "$header"
    echo "$shellenv_cmd"
    echo "$footer"
  } >> "$profile_file"

  success_echo "已写入 Homebrew shellenv：$profile_file"
}
# 收集并校验用户输入，决定后续执行路径。
prompt_homebrew_update() {
  info_echo "Homebrew 已安装。是否执行更新？"
  jobs_prompt_output echo "👉 按 [Enter]：跳过更新"
  jobs_prompt_output echo "👉 输入任意字符后回车：执行 brew update && brew upgrade && brew cleanup && brew doctor && brew -v"

  local confirm=""
  IFS= read -r confirm

  if [[ -z "$confirm" ]]; then
    note_echo "已选择跳过 Homebrew 更新"
    return 0
  fi

  info_echo "正在更新 Homebrew..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || { warn_echo "brew doctor 有警告/错误，请按提示处理"; }
  brew -v      || { warn_echo "打印 brew 版本失败，可忽略"; }
  success_echo "Homebrew 已更新"
}
# 执行对应的环境配置或同步处理。
install_homebrew() {
  local allow_update="${1:-false}"
  local arch="$(get_cpu_arch)"
  local shell_name="${SHELL##*/}"
  local profile_file=""
  local brew_bin=""
  local shellenv_cmd=""

  if ! refresh_brew_shellenv; then
    warn_echo "未检测到 Homebrew，准备安装...（架构：$arch）"

    if [[ "$arch" == "arm64" ]]; then
      jobs_brew_install_or_exit || {
        error_echo "Homebrew 安装失败（arm64）"
        exit 1
      }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    else
      jobs_brew_install_or_exit || {
        error_echo "Homebrew 安装失败（x86_64）"
        exit 1
      }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    fi

    success_echo "Homebrew 安装成功"

    shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
    case "$shell_name" in
      zsh)  profile_file="$HOME/.zprofile" ;;
      bash) profile_file="$HOME/.bash_profile" ;;
      *)    profile_file="$HOME/.profile" ;;
    esac

    inject_shellenv_block "$profile_file" "$shellenv_cmd"
    eval "$("$brew_bin" shellenv)"
    return 0
  fi

  [[ "$allow_update" == "true" ]] || return 0
  prompt_homebrew_update
}
# 检查当前运行条件是否满足后续流程要求。
ensure_dependencies() {
  local allow_update="${1:-false}"
  local mode="${2:-terminal}"

  install_homebrew "$allow_update"
  refresh_brew_shellenv || {
    error_echo "Homebrew shellenv 生效失败"
    exit 1
  }

  local -a missing_packages
  missing_packages=()

  if [[ "$mode" == "terminal" ]]; then
    command -v asciinema >/dev/null 2>&1 || missing_packages+=("asciinema")
    command -v agg >/dev/null 2>&1 || missing_packages+=("agg")
    command -v ffmpeg >/dev/null 2>&1 || missing_packages+=("ffmpeg")
  elif [[ "$mode" == "screen" ]]; then
    command -v ffmpeg >/dev/null 2>&1 || missing_packages+=("ffmpeg")
    if [[ ! -x "/usr/sbin/screencapture" ]] && ! command -v screencapture >/dev/null 2>&1; then
      error_echo "未找到 macOS 自带 screencapture，无法全屏录制"
      exit 1
    fi
  else
    error_echo "未知录制模式：$mode"
    exit 1
  fi

  if (( ${#missing_packages[@]} == 0 )); then
    if [[ "$mode" == "terminal" ]]; then
      success_echo "终端录制依赖已就绪：asciinema / agg / ffmpeg"
    else
      success_echo "全屏录制依赖已就绪：screencapture / ffmpeg"
    fi
    return 0
  fi

  warn_echo "缺少依赖：${missing_packages[*]}"
  info_echo "正在通过 Homebrew 安装缺失依赖..."
  brew install "${missing_packages[@]}" || {
    error_echo "依赖安装失败：${missing_packages[*]}"
    exit 1
  }

  if [[ "$mode" == "terminal" ]]; then
    command -v asciinema >/dev/null 2>&1 || { error_echo "asciinema 安装后仍不可用"; exit 1; }
    command -v agg >/dev/null 2>&1 || { error_echo "agg 安装后仍不可用"; exit 1; }
  fi
  command -v ffmpeg >/dev/null 2>&1 || { error_echo "ffmpeg 安装后仍不可用"; exit 1; }
  success_echo "录制依赖安装完成"
}
# 封装 assert_writable_dir 对应的独立处理逻辑。
assert_writable_dir() {
  local dir="$1"
  local test_file=""

  if [[ ! -d "$dir" ]]; then
    error_echo "路径不是有效目录：$dir"
    return 1
  fi

  if [[ ! -w "$dir" ]]; then
    error_echo "目录不可写：$dir"
    return 1
  fi

  test_file="$dir/.jobs_gif_write_test_$$"
  if ! : > "$test_file" 2>/dev/null; then
    error_echo "目录写入测试失败：$dir"
    return 1
  fi

  rm -f "$test_file"
  return 0
}
# 封装 make_unique_output_dir 对应的独立处理逻辑。
make_unique_output_dir() {
  local parent="$1"
  local timestamp="$2"
  local base="$parent/Gif@$timestamp"
  local candidate="$base"
  local index=1

  while [[ -e "$candidate" ]]; do
    candidate="$base-$index"
    index=$((index + 1))
  done

  mkdir -p "$candidate"
  printf "%s" "$candidate"
}
# 封装 set_output_files 对应的独立处理逻辑。
set_output_files() {
  OUTPUT_DIR="$1"
  CAST_FILE="$OUTPUT_DIR/session.cast"
  GIF_FILE="$OUTPUT_DIR/session.gif"
  VIDEO_FILE="$OUTPUT_DIR/session.mp4"
  SCREEN_MOV_FILE="$OUTPUT_DIR/session.mov"
  META_FILE="$OUTPUT_DIR/README.md"
}
# 封装 prepare_default_output_path 对应的独立处理逻辑。
prepare_default_output_path() {
  local timestamp="$(date '+%Y.%m.%d %H:%M:%S')"
  local candidate="$GIF_OUTPUT_PARENT"

  [[ -n "$candidate" ]] || candidate="$HOME/Desktop"
  candidate="$(normalize_dragged_path "$candidate")"

  if ! assert_writable_dir "$candidate" >/dev/null 2>&1; then
    candidate="$HOME/Desktop"
  fi

  mkdir -p "$candidate"
  GIF_OUTPUT_PARENT="$candidate"
  set_output_files "$(make_unique_output_dir "$GIF_OUTPUT_PARENT" "$timestamp")"
}
# 收集并校验用户输入，决定后续执行路径。
prompt_launch_mode() {
  local input=""

  echo ""
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold_echo "      启动录制"
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  gray_echo "默认模式：当前终端录制"
  gray_echo "当前父目录：$GIF_OUTPUT_PARENT"
  gray_echo "当前品质：theme=$GIF_THEME font=$GIF_FONT_SIZE fps=$GIF_FPS_CAP video=$GIF_VIDEO_ENABLED"
  echo ""
  jobs_prompt_output info_echo "按 [Enter]：跳过设置，直接开始当前终端录制。"
  jobs_prompt_output info_echo "输入任意字符后回车：进入设置菜单，可选择全屏录制。"
  echo ""
  printf "选择 > " | tee -a "$LOG_FILE"
  IFS= read -r input

  if [[ -z "$input" ]]; then
    SETTINGS_MENU="false"
    GIF_RECORD_MODE="terminal"
    note_echo "已跳过设置菜单，使用当前终端录制。"
  else
    SETTINGS_MENU="true"
    note_echo "进入设置菜单。"
  fi
}
# 收集并校验用户输入，决定后续执行路径。
prompt_record_mode() {
  local input=""

  GIF_RECORD_MODE="terminal"

  echo ""
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold_echo "      录制模式"
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  jobs_prompt_output info_echo "按回车跳过：默认录制当前终端。"
  echo "1) 当前终端录制：asciinema + agg。一个终端录一个，多终端分别执行 gif 即可录多个。"
  echo "2) 全屏录制：macOS screencapture + ffmpeg。只录整个屏幕，不录具体 App / 窗口。"
  echo ""

  while true; do
    printf "录制模式 > " | tee -a "$LOG_FILE"
    IFS= read -r input
    input="$(trim_text "$input")"

    case "$input" in
      ""|1)
        GIF_RECORD_MODE="terminal"
        success_echo "已选择：当前终端录制"
        return 0
        ;;
      2)
        GIF_RECORD_MODE="screen"
        success_echo "已选择：全屏录制"
        return 0
        ;;
      *)
        warn_echo "无效选择：$input"
        ;;
    esac
  done
}
# 收集并校验用户输入，决定后续执行路径。
prompt_output_path() {
  local default_parent="$HOME/Desktop"
  local input=""
  local candidate=""
  local timestamp="$(date '+%Y.%m.%d %H:%M:%S')"

  mkdir -p "$default_parent"

  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold_echo "      输出路径配置"
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  gray_echo "历史父目录：$GIF_OUTPUT_PARENT"
  echo ""
  info_echo "请输入或拖入一个已存在、可写的父目录。"
  jobs_prompt_output info_echo "按回车跳过：默认生成到桌面。"
  gray_echo "默认目录名：Gif@$timestamp"
  echo ""

  while true; do
    printf "输出父目录 > " | tee -a "$LOG_FILE"
    IFS= read -r input

    if [[ -z "$input" ]]; then
      candidate="$default_parent"
    else
      candidate="$(normalize_dragged_path "$input")"
    fi

    if assert_writable_dir "$candidate"; then
      GIF_OUTPUT_PARENT="$candidate"
      set_output_files "$(make_unique_output_dir "$GIF_OUTPUT_PARENT" "$timestamp")"
      success_echo "输出目录已确认：$OUTPUT_DIR"
      return 0
    fi

    jobs_prompt_output warn_echo "请重新输入一个可用目录，或直接回车使用桌面。"
  done
}
# 封装 apply_quality_preset 对应的独立处理逻辑。
apply_quality_preset() {
  local preset="$1"

  case "$preset" in
    high)
      GIF_THEME="github-dark"
      GIF_FONT_SIZE="28"
      GIF_LINE_HEIGHT="1.35"
      GIF_SPEED="1"
      GIF_IDLE_TIME_LIMIT="1.2"
      GIF_REC_IDLE_LIMIT="1.2"
      GIF_FPS_CAP="30"
      GIF_LAST_FRAME_DURATION="2"
      GIF_RENDERER="swash"
      GIF_TEXT_FONT_FAMILY="SF Mono,Menlo,JetBrains Mono,Fira Code"
      GIF_NO_LOOP="false"
      GIF_VIDEO_ENABLED="true"
      GIF_VIDEO_CRF="18"
      GIF_VIDEO_PRESET="medium"
      GIF_SCREEN_FPS="24"
      GIF_SCREEN_GIF_WIDTH="1600"
      ;;
    balanced)
      GIF_THEME="github-dark"
      GIF_FONT_SIZE="24"
      GIF_LINE_HEIGHT="1.35"
      GIF_SPEED="1.05"
      GIF_IDLE_TIME_LIMIT="1"
      GIF_REC_IDLE_LIMIT="1"
      GIF_FPS_CAP="24"
      GIF_LAST_FRAME_DURATION="2"
      GIF_RENDERER="swash"
      GIF_TEXT_FONT_FAMILY="SF Mono,Menlo,JetBrains Mono,Fira Code"
      GIF_NO_LOOP="false"
      GIF_VIDEO_ENABLED="true"
      GIF_VIDEO_CRF="20"
      GIF_VIDEO_PRESET="medium"
      GIF_SCREEN_FPS="20"
      GIF_SCREEN_GIF_WIDTH="1280"
      ;;
    small)
      GIF_THEME="github-dark"
      GIF_FONT_SIZE="20"
      GIF_LINE_HEIGHT="1.3"
      GIF_SPEED="1.15"
      GIF_IDLE_TIME_LIMIT="0.8"
      GIF_REC_IDLE_LIMIT="0.8"
      GIF_FPS_CAP="15"
      GIF_LAST_FRAME_DURATION="1.5"
      GIF_RENDERER="swash"
      GIF_TEXT_FONT_FAMILY="SF Mono,Menlo,JetBrains Mono,Fira Code"
      GIF_NO_LOOP="false"
      GIF_VIDEO_ENABLED="true"
      GIF_VIDEO_CRF="24"
      GIF_VIDEO_PRESET="fast"
      GIF_SCREEN_FPS="15"
      GIF_SCREEN_GIF_WIDTH="960"
      ;;
  esac
}
# 收集并校验用户输入，决定后续执行路径。
prompt_custom_value() {
  local var_name="$1"
  local label="$2"
  local validator="$3"
  local current=""
  local input=""

  eval "current=\"\${${var_name}}\""

  while true; do
    printf "%s [%s] > " "$label" "$current" | tee -a "$LOG_FILE"
    IFS= read -r input

    if [[ -z "$input" ]]; then
      return 0
    fi

    input="$(trim_text "$input")"
    [[ -z "$input" ]] && return 0

    case "$validator" in
      int)
        is_positive_int "$input" || { warn_echo "$label 必须是正整数"; continue; }
        ;;
      nonnegative_int)
        is_nonnegative_int "$input" || { warn_echo "$label 必须是非负整数"; continue; }
        ;;
      number)
        is_positive_number "$input" || { warn_echo "$label 必须是正数"; continue; }
        ;;
      theme)
        is_theme_text "$input" || { warn_echo "$label 只能包含字母、数字、连字符、下划线、逗号、点和 #"; continue; }
        ;;
      renderer)
        [[ "$input" == "swash" || "$input" == "resvg" ]] || { warn_echo "$label 只能是 swash 或 resvg"; continue; }
        ;;
      bool)
        is_bool_text "$input" || { warn_echo "$label 只能是 true 或 false"; continue; }
        ;;
      preset)
        [[ "$input" == "ultrafast" || "$input" == "superfast" || "$input" == "veryfast" || "$input" == "faster" || "$input" == "fast" || "$input" == "medium" || "$input" == "slow" || "$input" == "slower" || "$input" == "veryslow" ]] || { warn_echo "$label 不是有效 preset"; continue; }
        ;;
      text)
        ;;
    esac

    eval "${var_name}=\"\$input\""
    return 0
  done
}
# 收集并校验用户输入，决定后续执行路径。
prompt_custom_quality() {
  jobs_prompt_output info_echo "自定义品质；每一项直接回车代表保留当前值。"
  prompt_custom_value GIF_THEME "主题" theme
  prompt_custom_value GIF_FONT_SIZE "字体大小" int
  prompt_custom_value GIF_LINE_HEIGHT "行高" number
  prompt_custom_value GIF_SPEED "播放速度" number
  prompt_custom_value GIF_IDLE_TIME_LIMIT "GIF 空闲压缩秒数" number
  prompt_custom_value GIF_REC_IDLE_LIMIT "录制空闲压缩秒数" number
  prompt_custom_value GIF_FPS_CAP "FPS 上限" int
  prompt_custom_value GIF_LAST_FRAME_DURATION "末帧停留秒数" number
  prompt_custom_value GIF_RENDERER "渲染器 swash/resvg" renderer
  prompt_custom_value GIF_TEXT_FONT_FAMILY "字体族" text
  prompt_custom_value GIF_NO_LOOP "是否不循环 true/false" bool
  prompt_custom_value GIF_VIDEO_ENABLED "是否生成 MP4 true/false" bool
  prompt_custom_value GIF_VIDEO_CRF "MP4 CRF 数值" int
  prompt_custom_value GIF_VIDEO_PRESET "MP4 preset" preset
  prompt_custom_value GIF_SCREEN_COUNTDOWN "全屏录制倒计时秒数" int
  prompt_custom_value GIF_SCREEN_SHOW_CURSOR "全屏录制是否显示鼠标 true/false" bool
  prompt_custom_value GIF_SCREEN_FPS "全屏 GIF FPS" int
  prompt_custom_value GIF_SCREEN_GIF_WIDTH "全屏 GIF 宽度像素，输入 0 表示不缩放" nonnegative_int
  prompt_custom_value GIF_CLEAR_AFTER_FINISH "结束后清屏 true/false" bool
}
# 收集并校验用户输入，决定后续执行路径。
prompt_quality() {
  local input=""

  echo ""
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold_echo "      GIF / MP4 品质配置"
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  gray_echo "当前配置：theme=$GIF_THEME font=$GIF_FONT_SIZE terminal_fps=$GIF_FPS_CAP screen_fps=$GIF_SCREEN_FPS screen_width=$GIF_SCREEN_GIF_WIDTH video=$GIF_VIDEO_ENABLED crf=$GIF_VIDEO_CRF"
  echo ""
  jobs_prompt_output info_echo "按回车跳过：沿用当前/历史品质配置。"
  echo "1) 高质量：大字号，30fps，适合 README / 博客展示"
  echo "2) 均衡：中等字号，24fps，体积更稳"
  echo "3) 小体积：较小字号，15fps，适合快速分享"
  echo "4) 自定义：逐项配置"
  echo ""

  while true; do
    printf "品质选择 > " | tee -a "$LOG_FILE"
    IFS= read -r input
    input="$(trim_text "$input")"

    case "$input" in
      "")
        note_echo "已跳过品质修改，沿用当前配置"
        return 0
        ;;
      1)
        apply_quality_preset high
        success_echo "已选择高质量配置"
        return 0
        ;;
      2)
        apply_quality_preset balanced
        success_echo "已选择均衡配置"
        return 0
        ;;
      3)
        apply_quality_preset small
        success_echo "已选择小体积配置"
        return 0
        ;;
      4)
        prompt_custom_quality
        success_echo "自定义品质配置完成"
        return 0
        ;;
      *)
        warn_echo "无效选择：$input"
        ;;
    esac
  done
}
# 封装 write_metadata 对应的独立处理逻辑。
write_metadata() {
  [[ -n "$META_FILE" ]] || return 0

  local mode_label="当前终端录制"
  local raw_row="| session.cast | asciinema 原始录制文件 |"
  local end_text="录制过程中按 `Ctrl-C`。脚本会停止 asciinema 录制，然后立即把 `session.cast` 转为 `session.gif` 和 `session.mp4`。"
  local repair_text="gif --repair "$OUTPUT_DIR""

  if [[ "$GIF_RECORD_MODE" == "screen" ]]; then
    mode_label="全屏录制"
    raw_row="| session.mov | macOS screencapture 原始录屏文件 |"
    end_text="录制过程中按 `Ctrl-C`。脚本会停止全屏录制，然后立即把 `session.mov` 转为 `session.mp4` 和 `session.gif`。"
  fi

  cat > "$META_FILE" <<EOF_META
# $(basename "$OUTPUT_DIR")

## 文件

| 文件 | 说明 |
| --- | --- |
$raw_row
| session.gif | 高质量 GIF 文件 |
| session.mp4 | H.264 MP4 文件 |
| README.md | 本说明文件 |

## 录制模式

$mode_label

## 配置

| 配置项 | 值 |
| --- | --- |
| 终端主题 | $GIF_THEME |
| 终端字体大小 | $GIF_FONT_SIZE |
| 终端行高 | $GIF_LINE_HEIGHT |
| 终端播放速度 | $GIF_SPEED |
| 终端 GIF 空闲压缩 | $GIF_IDLE_TIME_LIMIT |
| 终端录制空闲压缩 | $GIF_REC_IDLE_LIMIT |
| 终端 FPS 上限 | $GIF_FPS_CAP |
| 终端末帧停留 | $GIF_LAST_FRAME_DURATION |
| 终端渲染器 | $GIF_RENDERER |
| 终端字体族 | $GIF_TEXT_FONT_FAMILY |
| 不循环 | $GIF_NO_LOOP |
| 生成 MP4 | $GIF_VIDEO_ENABLED |
| MP4 CRF | $GIF_VIDEO_CRF |
| MP4 preset | $GIF_VIDEO_PRESET |
| 全屏倒计时 | $GIF_SCREEN_COUNTDOWN |
| 全屏显示鼠标 | $GIF_SCREEN_SHOW_CURSOR |
| 全屏 GIF FPS | $GIF_SCREEN_FPS |
| 全屏 GIF 宽度 | $GIF_SCREEN_GIF_WIDTH |

## 结束录制

推荐方式：

$end_text

不建议输入 \`exit\`，因为手动输入的字符会被录进去。

如果异常情况下只留下原始文件，可执行：

\`\`\`zsh
$repair_text
\`\`\`
EOF_META
}
# 封装 write_latest_path 对应的独立处理逻辑。
write_latest_path() {
  mkdir -p "$CONFIG_DIR"
  {
    printf "OUTPUT_DIR=%s\n" "$OUTPUT_DIR"
    printf "RECORD_MODE=%s\n" "$GIF_RECORD_MODE"
    printf "GIF_FILE=%s\n" "$GIF_FILE"
    printf "VIDEO_FILE=%s\n" "$VIDEO_FILE"
    printf "CAST_FILE=%s\n" "$CAST_FILE"
    printf "SCREEN_MOV_FILE=%s\n" "$SCREEN_MOV_FILE"
  } > "$LATEST_FILE"
}
# 解析并返回后续流程需要的目标信息。
find_tool() {
  local name="$1"
  local value=""
  value="$(command -v "$name" 2>/dev/null || true)"
  [[ -n "$value" ]] || value="/opt/homebrew/bin/$name"
  [[ -x "$value" ]] || value="/usr/local/bin/$name"
  [[ -x "$value" ]] || return 1
  printf "%s" "$value"
}
# 解析并返回后续流程需要的目标信息。
find_system_tool() {
  local name="$1"
  local value=""
  value="$(command -v "$name" 2>/dev/null || true)"
  [[ -n "$value" ]] || value="/usr/sbin/$name"
  [[ -x "$value" ]] || value="/usr/bin/$name"
  [[ -x "$value" ]] || return 1
  printf "%s" "$value"
}
# 封装 agg_supports 对应的独立处理逻辑。
agg_supports() {
  local agg_bin="$1"
  local option="$2"
  "$agg_bin" --help 2>&1 | grep -Fq -- "$option"
}
# 封装 build_agg_args 对应的独立处理逻辑。
build_agg_args() {
  local agg_bin="$1"
  local -a result
  result=()

  agg_supports "$agg_bin" "--theme" && result+=(--theme "$GIF_THEME")
  agg_supports "$agg_bin" "--font-size" && result+=(--font-size "$GIF_FONT_SIZE")
  agg_supports "$agg_bin" "--line-height" && result+=(--line-height "$GIF_LINE_HEIGHT")
  agg_supports "$agg_bin" "--speed" && result+=(--speed "$GIF_SPEED")
  agg_supports "$agg_bin" "--idle-time-limit" && result+=(--idle-time-limit "$GIF_IDLE_TIME_LIMIT")
  agg_supports "$agg_bin" "--fps-cap" && result+=(--fps-cap "$GIF_FPS_CAP")
  agg_supports "$agg_bin" "--last-frame-duration" && result+=(--last-frame-duration "$GIF_LAST_FRAME_DURATION")
  agg_supports "$agg_bin" "--renderer" && result+=(--renderer "$GIF_RENDERER")

  if [[ -n "$GIF_TEXT_FONT_FAMILY" ]] && agg_supports "$agg_bin" "--text-font-family"; then
    result+=(--text-font-family "$GIF_TEXT_FONT_FAMILY")
  fi

  if [[ "$GIF_NO_LOOP" == "true" ]] && agg_supports "$agg_bin" "--no-loop"; then
    result+=(--no-loop)
  fi

  print -rl -- "${result[@]}"
}
# 封装 convert_to_gif 对应的独立处理逻辑。
convert_to_gif() {
  [[ -s "$CAST_FILE" ]] || {
    error_echo "录制文件不存在或为空：$CAST_FILE"
    return 1
  }

  local agg_bin="${AGG_BIN:-}"
  [[ -n "$agg_bin" && -x "$agg_bin" ]] || agg_bin="$(find_tool agg 2>/dev/null || true)"
  [[ -n "$agg_bin" ]] || {
    error_echo "未找到 agg，无法转换 GIF"
    return 1
  }

  AGG_BIN="$agg_bin"
  local gif_tmp="$GIF_FILE.tmp"
  local -a agg_args
  agg_args=( ${(f)"$(build_agg_args "$agg_bin")"} )

  rm -f "$gif_tmp"

  {
    echo "[gif] 开始转换 GIF：$CAST_FILE -> $GIF_FILE"
    echo "[gif] agg: $agg_bin"
    echo "[gif] args: ${agg_args[*]}"
  } >> "$LOG_FILE"

  if ! "$agg_bin" "${agg_args[@]}" "$CAST_FILE" "$gif_tmp" >> "$LOG_FILE" 2>&1; then
    warn_echo "agg 高级参数转换失败，尝试基础参数兜底。"
    rm -f "$gif_tmp"
    "$agg_bin" "$CAST_FILE" "$gif_tmp" >> "$LOG_FILE" 2>&1 || {
      error_echo "GIF 转换失败，请查看日志：$LOG_FILE"
      return 1
    }
  fi

  [[ -s "$gif_tmp" ]] || {
    error_echo "GIF 临时文件生成失败：$gif_tmp"
    return 1
  }

  mv -f "$gif_tmp" "$GIF_FILE"
  [[ -s "$GIF_FILE" ]] || {
    error_echo "GIF 文件生成失败：$GIF_FILE"
    return 1
  }

  success_echo "GIF 已生成：$GIF_FILE"
  return 0
}
# 封装 convert_to_mp4 对应的独立处理逻辑。
convert_to_mp4() {
  [[ "$GIF_VIDEO_ENABLED" == "true" ]] || return 0
  [[ -s "$GIF_FILE" ]] || {
    error_echo "缺少 GIF，无法生成 MP4：$GIF_FILE"
    return 1
  }

  local ffmpeg_bin="${FFMPEG_BIN:-}"
  [[ -n "$ffmpeg_bin" && -x "$ffmpeg_bin" ]] || ffmpeg_bin="$(find_tool ffmpeg 2>/dev/null || true)"
  [[ -n "$ffmpeg_bin" ]] || {
    error_echo "未找到 ffmpeg，无法转换 MP4"
    return 1
  }

  FFMPEG_BIN="$ffmpeg_bin"
  local video_tmp="$VIDEO_FILE.tmp.mp4"
  rm -f "$video_tmp"

  {
    echo "[gif] 开始转换 MP4：$GIF_FILE -> $VIDEO_FILE"
    echo "[gif] ffmpeg: $ffmpeg_bin"
  } >> "$LOG_FILE"

  "$ffmpeg_bin" -y -i "$GIF_FILE" \
    -movflags +faststart \
    -pix_fmt yuv420p \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
    -c:v libx264 \
    -crf "$GIF_VIDEO_CRF" \
    -preset "$GIF_VIDEO_PRESET" \
    "$video_tmp" >> "$LOG_FILE" 2>&1 || {
      error_echo "MP4 转换失败，请查看日志：$LOG_FILE"
      return 1
    }

  [[ -s "$video_tmp" ]] || {
    error_echo "MP4 临时文件生成失败：$video_tmp"
    return 1
  }

  mv -f "$video_tmp" "$VIDEO_FILE"
  [[ -s "$VIDEO_FILE" ]] || {
    error_echo "MP4 文件生成失败：$VIDEO_FILE"
    return 1
  }

  success_echo "MP4 已生成：$VIDEO_FILE"
  return 0
}
# 封装 build_screen_gif_filter 对应的独立处理逻辑。
build_screen_gif_filter() {
  local fps_value="$GIF_SCREEN_FPS"
  local width_value="$GIF_SCREEN_GIF_WIDTH"

  [[ -n "$fps_value" ]] || fps_value="24"
  [[ -n "$width_value" ]] || width_value="1600"

  if [[ "$width_value" == "0" ]]; then
    printf "fps=%s" "$fps_value"
  else
    printf "fps=%s,scale=%s:-1:flags=lanczos" "$fps_value" "$width_value"
  fi
}
# 封装 convert_screen_mov_to_mp4 对应的独立处理逻辑。
convert_screen_mov_to_mp4() {
  [[ "$GIF_VIDEO_ENABLED" == "true" ]] || return 0
  [[ -s "$SCREEN_MOV_FILE" ]] || {
    error_echo "缺少全屏原始录屏，无法生成 MP4：$SCREEN_MOV_FILE"
    return 1
  }

  local ffmpeg_bin="${FFMPEG_BIN:-}"
  [[ -n "$ffmpeg_bin" && -x "$ffmpeg_bin" ]] || ffmpeg_bin="$(find_tool ffmpeg 2>/dev/null || true)"
  [[ -n "$ffmpeg_bin" ]] || {
    error_echo "未找到 ffmpeg，无法转换 MP4"
    return 1
  }

  FFMPEG_BIN="$ffmpeg_bin"
  local video_tmp="$VIDEO_FILE.tmp.mp4"
  rm -f "$video_tmp"

  {
    echo "[gif] 开始转换全屏 MP4：$SCREEN_MOV_FILE -> $VIDEO_FILE"
    echo "[gif] ffmpeg: $ffmpeg_bin"
  } >> "$LOG_FILE"

  "$ffmpeg_bin" -y -i "$SCREEN_MOV_FILE" \
    -movflags +faststart \
    -pix_fmt yuv420p \
    -c:v libx264 \
    -crf "$GIF_VIDEO_CRF" \
    -preset "$GIF_VIDEO_PRESET" \
    "$video_tmp" >> "$LOG_FILE" 2>&1 || {
      error_echo "全屏 MP4 转换失败，请查看日志：$LOG_FILE"
      return 1
    }

  [[ -s "$video_tmp" ]] || {
    error_echo "全屏 MP4 临时文件生成失败：$video_tmp"
    return 1
  }

  mv -f "$video_tmp" "$VIDEO_FILE"
  success_echo "MP4 已生成：$VIDEO_FILE"
  return 0
}
# 封装 convert_screen_video_to_gif 对应的独立处理逻辑。
convert_screen_video_to_gif() {
  local source_video="$VIDEO_FILE"
  [[ -s "$source_video" ]] || source_video="$SCREEN_MOV_FILE"
  [[ -s "$source_video" ]] || {
    error_echo "缺少全屏视频，无法生成 GIF"
    return 1
  }

  local ffmpeg_bin="${FFMPEG_BIN:-}"
  [[ -n "$ffmpeg_bin" && -x "$ffmpeg_bin" ]] || ffmpeg_bin="$(find_tool ffmpeg 2>/dev/null || true)"
  [[ -n "$ffmpeg_bin" ]] || {
    error_echo "未找到 ffmpeg，无法转换 GIF"
    return 1
  }

  FFMPEG_BIN="$ffmpeg_bin"
  local palette_file="$OUTPUT_DIR/palette.png"
  local gif_tmp="$GIF_FILE.tmp"
  local vf="$(build_screen_gif_filter)"

  rm -f "$palette_file" "$gif_tmp"

  {
    echo "[gif] 开始转换全屏 GIF：$source_video -> $GIF_FILE"
    echo "[gif] ffmpeg: $ffmpeg_bin"
    echo "[gif] vf: $vf"
  } >> "$LOG_FILE"

  "$ffmpeg_bin" -y -i "$source_video" \
    -vf "$vf,palettegen=stats_mode=diff" \
    "$palette_file" >> "$LOG_FILE" 2>&1 || {
      error_echo "全屏 GIF 调色板生成失败，请查看日志：$LOG_FILE"
      rm -f "$palette_file"
      return 1
    }

  "$ffmpeg_bin" -y -i "$source_video" -i "$palette_file" \
    -lavfi "$vf [x]; [x][1:v] paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    "$gif_tmp" >> "$LOG_FILE" 2>&1 || {
      error_echo "全屏 GIF 转换失败，请查看日志：$LOG_FILE"
      rm -f "$palette_file" "$gif_tmp"
      return 1
    }

  rm -f "$palette_file"

  [[ -s "$gif_tmp" ]] || {
    error_echo "全屏 GIF 临时文件生成失败：$gif_tmp"
    return 1
  }

  mv -f "$gif_tmp" "$GIF_FILE"
  success_echo "GIF 已生成：$GIF_FILE"
  return 0
}
# 封装 notify_macos 对应的独立处理逻辑。
notify_macos() {
  local title="$1"
  local message="$2"

  command -v osascript >/dev/null 2>&1 || return 0
  /usr/bin/osascript -e "display notification \"${message}\" with title \"${title}\"" >/dev/null 2>&1 || true
}
# 封装 finish_recording 对应的独立处理逻辑。
finish_recording() {
  local result=0

  if [[ "$GIF_RECORD_MODE" == "screen" ]]; then
    [[ -s "$SCREEN_MOV_FILE" ]] || {
      error_echo "全屏录制文件不存在或为空：$SCREEN_MOV_FILE"
      return 1
    }

    convert_screen_mov_to_mp4 || result=1
    if (( result == 0 )); then
      convert_screen_video_to_gif || result=1
    fi
  else
    [[ -s "$CAST_FILE" ]] || {
      error_echo "录制文件不存在或为空：$CAST_FILE"
      return 1
    }

    convert_to_gif || result=1
    if (( result == 0 )); then
      convert_to_mp4 || result=1
    fi
  fi

  if (( result != 0 )); then
    error_echo "转码失败，仅保留已有文件：$OUTPUT_DIR"
    error_echo "可稍后执行：gif --repair "$OUTPUT_DIR""
    return 1
  fi

  write_metadata
  write_latest_path
  notify_macos "Jobs GIF" "GIF / MP4 已生成：$(basename "$OUTPUT_DIR")"

  if [[ "$GIF_CLEAR_AFTER_FINISH" == "true" ]]; then
    clear_terminal_soft
  else
    success_echo "输出目录：$OUTPUT_DIR"
  fi

  return 0
}
# 封装 create_recording_zdotdir 对应的独立处理逻辑。
create_recording_zdotdir() {
  RECORD_ZDOTDIR="$OUTPUT_DIR/.gif-zdotdir"
  mkdir -p "$RECORD_ZDOTDIR"

  cat > "$RECORD_ZDOTDIR/.zshenv" <<'EOF_ZSHENV'
[[ -r "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
export JOBS_GIF_RECORDING=1
EOF_ZSHENV

  cat > "$RECORD_ZDOTDIR/.zprofile" <<'EOF_ZPROFILE'
[[ -r "$HOME/.zprofile" ]] && source "$HOME/.zprofile"
EOF_ZPROFILE

  cat > "$RECORD_ZDOTDIR/.zlogin" <<'EOF_ZLOGIN'
[[ -r "$HOME/.zlogin" ]] && source "$HOME/.zlogin"
EOF_ZLOGIN

  cat > "$RECORD_ZDOTDIR/.zlogout" <<'EOF_ZLOGOUT'
[[ -r "$HOME/.zlogout" ]] && source "$HOME/.zlogout"
EOF_ZLOGOUT

  cat > "$RECORD_ZDOTDIR/.zshrc" <<'EOF_ZSHRC'
[[ -r "$HOME/.zshrc" ]] && source "$HOME/.zshrc"

# gif 录制期间，Ctrl-C 直接退出录制 shell；关闭 ECHOCTL 避免显示 ^C。
if [[ "${JOBS_GIF_RECORDING:-}" == "1" ]]; then
  stty -echoctl 2>/dev/null || true
  # 封装 TRAPINT 对应的独立处理逻辑。
  TRAPINT() { exit 130 }
fi
EOF_ZSHRC
}
# 封装 start_terminal_recording 对应的独立处理逻辑。
start_terminal_recording() {
  local record_shell="/bin/zsh"
  local record_command=""
  local zdotdir_arg=""

  if [[ ! -x "$record_shell" ]]; then
    record_shell="$(command -v zsh 2>/dev/null || true)"
  fi
  [[ -n "$record_shell" ]] || { error_echo "未找到 zsh，无法启动录制 shell"; exit 1; }

  create_recording_zdotdir
  zdotdir_arg="$(quote_value "$RECORD_ZDOTDIR")"
  record_command="ZDOTDIR=${zdotdir_arg} JOBS_GIF_RECORDING=1 exec $(quote_value "$record_shell") -l"

  clear_terminal_soft
  sleep 0.15

  # Ctrl-C 用来结束 asciinema 录制；这里不设置额外 trap，避免提前打断后续转码。
  if ! ASCIINEMA_REC=1 asciinema rec -q --overwrite --idle-time-limit "$GIF_REC_IDLE_LIMIT" --command "$record_command" "$CAST_FILE"; then
    echo "[gif] asciinema rec 已结束或被 Ctrl-C 中断，继续执行转码" >> "$LOG_FILE"
  fi
}
# 封装 start_screen_recording 对应的独立处理逻辑。
start_screen_recording() {
  local screencapture_bin="${SCREENCAPTURE_BIN:-}"
  [[ -n "$screencapture_bin" && -x "$screencapture_bin" ]] || screencapture_bin="$(find_system_tool screencapture 2>/dev/null || true)"
  [[ -n "$screencapture_bin" ]] || { error_echo "未找到 screencapture，无法全屏录制"; exit 1; }
  SCREENCAPTURE_BIN="$screencapture_bin"

  local countdown="$GIF_SCREEN_COUNTDOWN"
  is_positive_int "$countdown" || countdown="3"

  clear_terminal_soft
  info_echo "全屏录制将在 ${countdown} 秒后开始。"
  info_echo "现在可以切换到你要展示的屏幕；录制中按 Ctrl-C 结束。"
  sleep 1

  while (( countdown > 0 )); do
    clear_terminal_soft
    bold_echo "全屏录制倒计时：${countdown}"
    sleep 1
    countdown=$((countdown - 1))
  done

  clear_terminal_soft
  sleep 0.2

  local -a capture_args
  capture_args=(-v)
  [[ "$GIF_SCREEN_SHOW_CURSOR" == "true" ]] && capture_args+=(-g)

  {
    echo "[gif] 开始全屏录制：$screencapture_bin ${capture_args[*]} $SCREEN_MOV_FILE"
    echo "[gif] 结束方式：Ctrl-C"
  } >> "$LOG_FILE"

  if ! "$screencapture_bin" "${capture_args[@]}" "$SCREEN_MOV_FILE"; then
    echo "[gif] screencapture 已结束或被 Ctrl-C 中断，继续执行转码" >> "$LOG_FILE"
  fi
}
# 封装 start_recording 对应的独立处理逻辑。
start_recording() {
  if [[ "$GIF_RECORD_MODE" == "screen" ]]; then
    start_screen_recording
  else
    start_terminal_recording
  fi
}
# 封装 repair_from_path 对应的独立处理逻辑。
repair_from_path() {
  local target="$1"
  local dir=""

  load_config
  target="$(normalize_dragged_path "$target")"

  if [[ -d "$target" ]]; then
    dir="$target"
    set_output_files "$dir"
    if [[ -s "$CAST_FILE" ]]; then
      GIF_RECORD_MODE="terminal"
    elif [[ -s "$SCREEN_MOV_FILE" ]]; then
      GIF_RECORD_MODE="screen"
    else
      error_echo "repair 目录内未找到 session.cast 或 session.mov：$target"
      return 1
    fi
  elif [[ -f "$target" ]]; then
    dir="$(cd "$(dirname "$target")" && pwd)"
    set_output_files "$dir"
    case "$target" in
      *.cast)
        GIF_RECORD_MODE="terminal"
        CAST_FILE="$target"
        ;;
      *.mov)
        GIF_RECORD_MODE="screen"
        SCREEN_MOV_FILE="$target"
        ;;
      *)
        error_echo "repair 只支持 session.cast 或 session.mov：$target"
        return 1
        ;;
    esac
  else
    error_echo "repair 目标不存在：$target"
    return 1
  fi

  ensure_dependencies false "$GIF_RECORD_MODE"
  finish_recording
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】gif.command' | jobs_intro_style title
  print -r -- '核心用途：执行“gif”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  jobs_list_intro_read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  # 根据当前条件选择对应的执行分支。
  case "${1:-}" in
    -h|--help|help)
      # 执行当前流程中的独立业务步骤：show_usage。
      show_usage
      # 执行当前流程中的独立业务步骤：return。
      return 0
      ;;
    --repair|repair)
      # 根据当前条件选择对应的执行分支。
      if [[ -z "${2:-}" ]]; then
        # 执行当前流程中的独立业务步骤：error_echo。
        error_echo "缺少 repair 目标：输出目录或 session.cast"
        # 输出当前步骤的提示或执行进度。
        echo "用法：gif --repair <输出目录或 session.cast>"
        # 执行当前流程中的独立业务步骤：return。
        return 1
      fi
      # 执行当前流程中的独立业务步骤：repair_from_path。
      repair_from_path "$2"
      # 执行当前流程中的独立业务步骤：return。
      return $?
      ;;
  esac

  # 展示脚本说明并等待用户确认影响范围。
  show_intro_if_double_clicked
  # 准备后续业务需要的配置、目录或运行上下文。
  load_config
  # 执行当前流程中的独立业务步骤：prompt_launch_mode。
  prompt_launch_mode

  # 根据当前条件选择对应的执行分支。
  if [[ "$SETTINGS_MENU" == "true" ]]; then
    # 执行当前流程中的独立业务步骤：prompt_record_mode。
    prompt_record_mode
    # 执行当前流程中的独立业务步骤：prompt_output_path。
    prompt_output_path
    # 执行当前流程中的独立业务步骤：prompt_quality。
    prompt_quality
    # 准备后续业务需要的配置、目录或运行上下文。
    save_config
  else
    # 直接回车启动时，默认永远录制当前终端，避免上次选择全屏后误录整个屏幕。
    GIF_RECORD_MODE="terminal"
    # 准备后续业务需要的配置、目录或运行上下文。
    prepare_default_output_path
  fi

  # 检查当前步骤所需的环境、路径或输入条件。
  ensure_dependencies "$SETTINGS_MENU" "$GIF_RECORD_MODE"

  # 执行当前流程中的独立业务步骤：write_metadata。
  write_metadata
  # 执行当前流程中的独立业务步骤：write_latest_path。
  write_latest_path
  # 执行当前流程中的独立业务步骤：start_recording。
  start_recording
  finish_recording || return 1
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  set -u
  set -o pipefail
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  show_script_intro_and_wait || return $? # 先展示用途、影响范围及确认方式。
  initialize_script_runtime # 确认后初始化运行选项、路径及日志。
  run_main_business_flow "$@" # 执行已确认的业务并传递入口参数。
}

main "$@"
