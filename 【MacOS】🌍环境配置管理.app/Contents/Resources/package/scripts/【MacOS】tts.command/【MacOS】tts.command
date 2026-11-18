#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】tts.command
# - 核心用途：执行“tts”对应的自动化任务。
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



# ---------- 基础路径 ----------
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
# >>> Jobs embedded Python runtime >>>
# 输出诊断，不污染函数返回的解释器路径。
_jobs_python_note() {
  jobs_prompt_output print -u2 -r -- "$*"
}
# 标识当前 zsh 进程及其子 shell，避免继承环境绕过确认。
_jobs_python_process_token() {
  print -r -- "$$:${ZSH_SUBSHELL:-0}"
}
# 只有当前可交互进程内形成的确认才允许环境写操作。
_jobs_python_has_authorization() {
  [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]] || return 1
  [[ "${parameters[_JOBS_PYTHON_CONFIRMED_PROCESS]:-}" != *export* &&
     "${_JOBS_PYTHON_CONFIRMED_PROCESS:-}" == "$(_jobs_python_process_token)" ]]
}
# 记录调用方已完成的终端确认；非交互入口只允许后续只读检查。
jobs_python_mark_confirmed() {
  emulate -L zsh
  if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]]; then
    typeset -g +x _JOBS_PYTHON_CONFIRMED_PROCESS="$(_jobs_python_process_token)"
  fi
  return 0
}
# 在业务自述之后确认本次 Homebrew 更新及 Python 环境准备。
jobs_python_confirm_prepare() {
  emulate -L zsh
  local answer=""
  _jobs_python_has_authorization && return 0
  _jobs_python_note "${1:-Python 环境预检：更新 Homebrew；Python 不满足业务版本时经确认安装或修复。}"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 || "${DRY_RUN:-0}" == 1 ]]; then
    _jobs_python_note "✖ 环境准备需要终端确认；当前未更新或安装任何环境。"
    return 1
  fi
  print -u2 -n -r -- "$(jobs_prompt_render '➤ 按回车准备环境；任意非空输入（含空格）取消：')"
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消环境准备。'
    return 1
  fi
  jobs_python_mark_confirmed
}
# 对缺失依赖和已有虚拟环境修复使用统一的必需动作确认。
_jobs_python_confirm_required() {
  emulate -L zsh
  local answer=""
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $1；需要在终端确认后重试，未执行安装或修复。"
    return 1
  fi
  print -u2 -n -r -- "$(jobs_prompt_render "➤ $1；直接回车执行，任意非空输入（含空格）取消：")"
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消，停止当前流程。'
    return 1
  fi
}
# 校验版本参数，避免把调用参数作为公式或命令选项解释。
_jobs_python_validate_arguments() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  if [[ ! "$minimum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ||
        ( -n "$maximum" && ! "$maximum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ) ||
        ! "$formula" =~ '^python(@[0-9]+\.[0-9]+)?$' ]]; then
    _jobs_python_note "✖ Python 版本或 Homebrew 公式参数无效：$minimum / $formula / $maximum"
    return 1
  fi
  if [[ -n "$maximum" ]] && ! _jobs_python_version_less "$minimum" "$maximum"; then
    _jobs_python_note '✖ Python 最低版本必须小于排他上限。'
    return 1
  fi
}
# 以数值逐段比较版本，不依赖任何 Python 运行时。
_jobs_python_version_less() {
  emulate -L zsh
  local -a left right
  local component left_value right_value
  left=("${(@s:.:)1}")
  right=("${(@s:.:)2}")
  for component in 1 2 3; do
    left_value=$((10#${left[$component]:-0}))
    right_value=$((10#${right[$component]:-0}))
    (( left_value < right_value )) && return 0
    (( left_value > right_value )) && return 1
  done
  return 1
}
# 验证本脚本内封装的 Homebrew 接口，不读取外部函数库。
_jobs_python_load_brew_helpers() {
  emulate -L zsh
  local helper
  for helper in jobs_brew_find jobs_brew_choose_installation jobs_brew_install_system jobs_brew_install_user jobs_brew_activate; do
    (( $+functions[$helper] )) || { _jobs_python_note "✖ 脚本内置 Homebrew 接口缺失：$helper"; return 1; }
  done
}
# 验证解释器版本、标准库与归属，返回可机器判断的状态码。
_jobs_python_probe() {
  emulate -L zsh
  local candidate="$1" minimum="$2" maximum="$3" tree="$4" mode="$5"
  [[ -x "$candidate" ]] || return 1
  PYTHONDONTWRITEBYTECODE=1 "$candidate" -c '
import sys
def version(value):
    return tuple((list(map(int, value.split("."))) + [0, 0, 0])[:3])
actual = tuple(sys.version_info[:3])
if actual < version(sys.argv[1]):
    sys.exit(2)
if sys.argv[2] and actual >= version(sys.argv[2]):
    sys.exit(5)
try:
    import venv
    from pathlib import Path
    if actual >= (3, 11, 0):
        import tomllib
except Exception as error:
    print("Python standard library unavailable: " + str(error), file=sys.stderr)
    sys.exit(3)
try:
    target = Path(sys.argv[3]).resolve()
    executable = Path(sys.executable).resolve()
    if sys.argv[4] == "venv":
        if Path(sys.prefix).resolve() != target or sys.prefix == sys.base_prefix:
            sys.exit(4)
    else:
        executable.relative_to(target)
except (ValueError, OSError):
    sys.exit(4)
print("JOBS_PYTHON_OK|" + ".".join(map(str, actual)) + "|" + str(executable))
' "$minimum" "$maximum" "$tree" "$mode"
}
# 验证公式路径属于当前 Homebrew Cellar，再寻找该公式内的健康解释器。
_jobs_python_find_formula_python() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  local cellar_root formula_cellar formula_prefix candidate probe_result probe_code=1 version_suffix actual_formula python3_command link_target
  local -a candidates runtime_bins
  cellar_root="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar 2>/dev/null)" || return 1
  formula_cellar="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar "$formula" 2>/dev/null)" || return 1
  actual_formula="${formula_cellar:t}"
  [[ "$cellar_root" == /* && "$cellar_root" != / && "$formula_cellar" == /* &&
     "${formula_cellar:A}" == "${cellar_root:A}/$actual_formula" &&
     ( "$actual_formula" == "$formula" ||
       ( "$formula" == python && "$actual_formula" =~ '^python@[0-9]+\.[0-9]+$' ) ) ]] || {
    _jobs_python_note "✖ Homebrew 公式 Cellar 路径异常：$formula_cellar"
    return 4
  }
  formula_prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --prefix "$formula" 2>/dev/null)" || return 1
  if [[ "$formula_prefix" == /* && ! -e "$formula_prefix" && ! -L "$formula_prefix" ]]; then
    return 1
  fi
  if [[ -L "$formula_prefix" && ! -e "$formula_prefix" ]]; then
    link_target="$(/usr/bin/readlink "$formula_prefix")" || return 4
    [[ "$link_target" == /* ]] || link_target="${formula_prefix:h}/$link_target"
    if [[ "${link_target:a}" == "${formula_cellar:A}/"* ]]; then
      return 1
    fi
    _jobs_python_note "✖ 损坏的公式链接指向外部路径：$formula_prefix"
    return 4
  fi
  [[ "$formula_prefix" == /* && "${formula_prefix:A}" == "${formula_cellar:A}/"* && -d "$formula_prefix" ]] || {
    _jobs_python_note "✖ Homebrew 公式前缀不属于指定公式：$formula_prefix"
    return 4
  }
  version_suffix="${actual_formula#python@}"
  [[ "$actual_formula" != python ]] || version_suffix=3
  candidates=("$formula_prefix/libexec/bin/python3" "$formula_prefix/bin/python$version_suffix" "$formula_prefix/bin/python3")
  runtime_bins=()
  for candidate in "$formula_prefix/libexec/bin" "$formula_prefix/bin"; do
    if [[ -d "$candidate" && "${candidate:A}" == "${formula_prefix:A}/"* ]]; then
      runtime_bins+=("$candidate")
    fi
  done
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    probe_code=0
    probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "${formula_cellar:A}" runtime 2>&1)" || probe_code=$?
    if (( probe_code == 0 )) && [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
      python3_command=""
      local runtime_bin
      for runtime_bin in "${runtime_bins[@]}"; do
        if [[ -x "$runtime_bin/python3" ]]; then
          python3_command="$runtime_bin/python3"
          break
        fi
      done
      if [[ -z "$python3_command" ]] ||
         ! _jobs_python_probe "$python3_command" "$minimum" "$maximum" "${formula_cellar:A}" runtime >/dev/null 2>&1; then
        _jobs_python_note "✖ 公式缺少健康的 python3 命令入口：$formula_prefix"
        return 3
      fi
      typeset -gx JOBS_PYTHON_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_PROCESS="$(_jobs_python_process_token)"
      typeset -g +x _JOBS_PYTHON_SELECTED_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_TREE="${formula_cellar:A}"
      export PATH="${(j.:.)runtime_bins}:$PATH"
      rehash
      _jobs_python_note "✔ 复用 Homebrew Python：$candidate（${${probe_result#*|}%%|*}）"
      return 0
    fi
    (( probe_code != 0 )) || probe_code=1
    [[ "$probe_code" != 2 && "$probe_code" != 5 ]] || break
  done
  return "$probe_code"
}
# 在当前进程一次更新 Homebrew；失败不进入 Python 安装或业务。
_jobs_python_update_brew_once() {
  emulate -L zsh
  local brew_key="${JOBS_HOMEBREW_BIN:A}" token="$(_jobs_python_process_token)"
  _jobs_python_has_authorization || return 1
  if [[ "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" != association* ||
        "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" == *export* ]]; then
    unset _JOBS_PYTHON_UPDATED_BREWS
    typeset -gA +x _JOBS_PYTHON_UPDATED_BREWS
  fi
  [[ "${_JOBS_PYTHON_UPDATED_BREWS[$brew_key]:-}" != "$token" ]] || return 0
  _jobs_python_note "ℹ 更新 Homebrew 本体及公式索引：$JOBS_HOMEBREW_BIN update"
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" update; then
    _jobs_python_note '✖ Homebrew 更新失败，停止 Python 准备；未升级其它公式。'
    return 1
  fi
  jobs_brew_activate || { _jobs_python_note '✖ Homebrew 更新后激活或健康复检失败。'; return 1; }
  _JOBS_PYTHON_UPDATED_BREWS[$brew_key]="$token"
}
# 全新 Mac 缺少 CLT 时只请求系统安装一次，完成对话框后由用户重新运行。
_jobs_python_require_clt_for_install() {
  emulate -L zsh
  local developer_directory git_command token="$(_jobs_python_process_token)"
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || return 0
  developer_directory="$(/usr/bin/xcode-select -p 2>/dev/null)" || developer_directory=""
  git_command="$(command -v git 2>/dev/null)"
  if [[ -n "$developer_directory" && -d "$developer_directory" && -n "$git_command" ]] &&
     "$git_command" --version >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${parameters[_JOBS_PYTHON_CLT_REQUESTED_PROCESS]:-}" != *export* &&
        "${_JOBS_PYTHON_CLT_REQUESTED_PROCESS:-}" == "$token" ]]; then
    _jobs_python_note '✖ 已请求 Command Line Tools 安装；请完成系统对话框后重新运行脚本。'
    return 1
  fi
  _jobs_python_confirm_required '缺少可用 Git / Command Line Tools，将打开 Apple 系统安装对话框' || return 1
  typeset -g +x _JOBS_PYTHON_CLT_REQUESTED_PROCESS="$token"
  if ! /usr/bin/xcode-select --install; then
    _jobs_python_note '✖ 无法发起 Command Line Tools 安装；请先在系统中安装或修复开发者工具。'
    return 1
  fi
  _jobs_python_note 'ℹ 已请求系统安装；请完成 Command Line Tools 对话框后重新运行，本次不继续安装 Homebrew。'
  return 1
}
# 准备必经的 Homebrew 通道，缺失时复用内置安装路径选择。
_jobs_python_prepare_brew() {
  emulate -L zsh
  local installed=""
  _jobs_python_load_brew_helpers || return 1
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    if ! _jobs_python_has_authorization; then
      _jobs_python_note '✖ 缺少健康 Homebrew；请在终端确认环境准备，未执行安装。'
      return 1
    fi
    _jobs_python_require_clt_for_install || return 1
    jobs_brew_choose_installation || return 1
    case "${JOBS_HOMEBREW_INSTALL_MODE:-}" in
      system) jobs_brew_install_system || return $? ;;
      user) jobs_brew_install_user || return $? ;;
      *) _jobs_python_note '✖ Homebrew 安装路径选择无效，停止。'; return 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || { _jobs_python_note '✖ Homebrew 激活或健康检查失败。'; return 1; }
  if _jobs_python_has_authorization; then
    _jobs_python_update_brew_once || return 1
  else
    _jobs_python_note 'ℹ 当前未获得终端确认，仅只读检查已有 Homebrew / Python，不更新或安装。'
  fi
}
# 更新 Homebrew 后只处理业务指定的 Python 公式，并立即复检。
jobs_python_ensure() {
  emulate -L zsh
  local minimum="${1:-}" formula="${2:-python@3.13}" maximum="${3:-}"
  local probe_code=0 action=install installed_versions=""
  unset JOBS_PYTHON_BIN
  _jobs_python_validate_arguments "$minimum" "$formula" "$maximum" || return 1
  _jobs_python_prepare_brew || return 1
  _jobs_python_find_formula_python "$minimum" "$formula" "$maximum" || probe_code=$?
  (( probe_code != 0 )) || return 0
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $formula 不满足 Python $minimum${maximum:+ 至小于 $maximum}；无交互确认，停止。"
    return 1
  fi
  if (( probe_code == 4 )); then
    _jobs_python_note '✖ Python 或公式路径归属异常，停止；不覆盖外部解释器。'
    return 1
  fi
  if (( probe_code == 5 )); then
    _jobs_python_note "✖ $formula 的 Python 版本高于业务允许范围（须小于 $maximum）；停止，不尝试无效升级。"
    return 1
  fi
  installed_versions="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" list --versions "$formula" 2>/dev/null)" || installed_versions=""
  if [[ -n "$installed_versions" ]]; then
    action=reinstall
    (( probe_code != 2 )) || action=upgrade
  fi
  _jobs_python_confirm_required "必需的 $formula 未就绪，执行 brew $action $formula" || return 1
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" "$action" "$formula"; then
    _jobs_python_note "✖ brew $action $formula 失败；停止，不重复安装。"
    return 1
  fi
  jobs_brew_activate || return 1
  if ! _jobs_python_find_formula_python "$minimum" "$formula" "$maximum"; then
    _jobs_python_note "✖ $formula 安装或修复后仍不满足要求；停止下游业务。"
    return 1
  fi
}
# 拒绝空目录、根目录及符号链接路径，防止虚拟环境修复涉及其它目录。
_jobs_python_validate_venv_path() {
  emulate -L zsh
  local supplied="${1:-}" absolute
  [[ -n "$supplied" ]] || { _jobs_python_note '✖ 虚拟环境路径不能为空。'; return 1; }
  absolute="${supplied:a}"
  if [[ "$absolute" == / || "$absolute" == "${HOME:a}" || "$absolute" != "${absolute:A}" ||
        -L "$absolute" || ( -e "$absolute" && ! -d "$absolute" ) ]]; then
    _jobs_python_note "✖ 虚拟环境须为独立真实目录，拒绝危险路径：$supplied"
    return 1
  fi
  if [[ -d "$absolute" && ! -f "$absolute/pyvenv.cfg" && ! -e "$absolute/bin/python" &&
        ! -L "$absolute/bin/python" && "${absolute:t}" != .venv && "${absolute:t}" != venv ]]; then
    _jobs_python_note "✖ 目录不是可识别的虚拟环境，不移动源码或用户目录：$absolute"
    return 1
  fi
  print -r -- "$absolute"
}
# 复用健康虚拟环境；旧坏环境完整改名备份后重建，不删除原目录。
jobs_python_prepare_venv() {
  emulate -L zsh
  local supplied="${1:-}" minimum="${2:-}" maximum="${3:-}" environment candidate probe_result backup suffix=0
  _jobs_python_validate_arguments "$minimum" python "${maximum:-}" || return 1
  environment="$(_jobs_python_validate_venv_path "$supplied")" || return 1
  candidate="$environment/bin/python"
  if [[ -d "$environment" ]] &&
     probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" &&
     [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✔ 复用虚拟环境：$environment"
    return 0
  fi
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ 虚拟环境缺失或不健康，需要终端确认后准备：$environment"
    return 1
  fi
  if [[ -z "${JOBS_PYTHON_BIN:-}" || ! -x "$JOBS_PYTHON_BIN" ||
        "${parameters[_JOBS_PYTHON_SELECTED_PROCESS]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_BIN]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_TREE]:-}" == *export* ||
        "${_JOBS_PYTHON_SELECTED_PROCESS:-}" != "$(_jobs_python_process_token)" ||
        "${_JOBS_PYTHON_SELECTED_BIN:-}" != "$JOBS_PYTHON_BIN" ]]; then
    _jobs_python_note '✖ 尚未选定健康 Homebrew Python，请先调用 jobs_python_ensure。'
    return 1
  fi
  if ! _jobs_python_probe "$JOBS_PYTHON_BIN" "$minimum" "$maximum" "$_JOBS_PYTHON_SELECTED_TREE" runtime >/dev/null 2>&1; then
    _jobs_python_note '✖ 已选择的 Homebrew Python 不满足虚拟环境版本要求，停止。'
    return 1
  fi
  if [[ -d "$environment" ]]; then
    _jobs_python_confirm_required "修复旧或损坏的虚拟环境 $environment（完整改名备份）" || return 1
    backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$"
    while [[ -e "$backup" || -L "$backup" ]]; do
      (( suffix += 1 ))
      backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$.$suffix"
    done
    if ! mv -- "$environment" "$backup"; then
      _jobs_python_note "✖ 原虚拟环境备份失败，停止：$environment"
      return 1
    fi
    _jobs_python_note "ℹ 原虚拟环境已完整保留：$backup"
  fi
  if ! PYTHONDONTWRITEBYTECODE=1 "$JOBS_PYTHON_BIN" -m venv "$environment"; then
    _jobs_python_note "✖ 虚拟环境创建失败，停止；备份保持原状：${backup:-无旧环境}"
    return 1
  fi
  if ! probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" ||
     [[ "$probe_result" != JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✖ 虚拟环境创建后复检失败，停止：$environment"
    return 1
  fi
  _jobs_python_note "✔ 虚拟环境已就绪：$environment"
}
# <<< Jobs embedded Python runtime <<<

# 编排本文件内嵌的环境自检，保留当前入口的确认和版本要求。
jobs_envtts_python_preflight() {
  case "${1:-interactive}" in
    confirmed) jobs_python_mark_confirmed ;;
    readonly) ;;
    *)
      if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
        jobs_python_confirm_prepare || return 1
      fi
      ;;
  esac
  jobs_python_ensure 3.10 python@3.12 3.13
}

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

SUPERTONIC_VENV_DIR="${SUPERTONIC_VENV_DIR:-${HOME}/Desktop/supertonic-venv}"
SUPERTONIC_HOST="${SUPERTONIC_HOST:-127.0.0.1}"
SUPERTONIC_PORT="${SUPERTONIC_PORT:-7788}"
SUPERTONIC_VOICE="${SUPERTONIC_VOICE:-M1}"
SUPERTONIC_LANG="${SUPERTONIC_LANG:-auto}"
SUPERTONIC_STEPS="${SUPERTONIC_STEPS:-8}"
SUPERTONIC_SPEED="${SUPERTONIC_SPEED:-1.0}"
SUPERTONIC_OUTPUT_DIR="${SUPERTONIC_OUTPUT_DIR:-${SCRIPT_DIR}/outputs}"
SUPERTONIC_ZH_ENGINE="${SUPERTONIC_ZH_ENGINE:-say}"
SUPERTONIC_ZH_VOICE="${SUPERTONIC_ZH_VOICE:-}"
SUPERTONIC_ZH_RATE="${SUPERTONIC_ZH_RATE:-200}"

MOSS_TTS_NANO_HOME="${MOSS_TTS_NANO_HOME:-${HOME}/Desktop/MOSS-TTS-Nano}"
MOSS_TTS_NANO_VENV_DIR="${MOSS_TTS_NANO_VENV_DIR:-${HOME}/Desktop/moss-tts-nano-venv}"
MOSS_TTS_NANO_BACKEND="${MOSS_TTS_NANO_BACKEND:-onnx}"
MOSS_TTS_NANO_EXECUTION_PROVIDER="${MOSS_TTS_NANO_EXECUTION_PROVIDER:-cpu}"
MOSS_TTS_NANO_PROMPT_SPEECH="${MOSS_TTS_NANO_PROMPT_SPEECH:-${MOSS_TTS_NANO_HOME}/assets/audio/zh_1.wav}"
MOSS_TTS_NANO_OUTPUT_DIR="${MOSS_TTS_NANO_OUTPUT_DIR:-${SCRIPT_DIR}/outputs}"
MOSS_TTS_NANO_REPO_URL="${MOSS_TTS_NANO_REPO_URL:-https://github.com/OpenMOSS/MOSS-TTS-Nano.git}"
MOSS_TTS_NANO_SKIP_INSTALL="${MOSS_TTS_NANO_SKIP_INSTALL:-0}"

VOXCPM_VENV_DIR="${VOXCPM_VENV_DIR:-${HOME}/Desktop/voxcpm-venv}"
VOXCPM_OUTPUT_DIR="${VOXCPM_OUTPUT_DIR:-${SCRIPT_DIR}/outputs}"
VOXCPM_DEVICE="${VOXCPM_DEVICE:-auto}"
VOXCPM_CONTROL="${VOXCPM_CONTROL:-}"
VOXCPM_REFERENCE_AUDIO="${VOXCPM_REFERENCE_AUDIO:-}"
VOXCPM_PROMPT_AUDIO="${VOXCPM_PROMPT_AUDIO:-}"
VOXCPM_PROMPT_TEXT="${VOXCPM_PROMPT_TEXT:-}"
VOXCPM_DENOISE="${VOXCPM_DENOISE:-0}"
VOXCPM_NO_OPTIMIZE="${VOXCPM_NO_OPTIMIZE:-1}"
VOXCPM_HF_ENDPOINT="${VOXCPM_HF_ENDPOINT:-}"
VOXCPM_SKIP_INSTALL="${VOXCPM_SKIP_INSTALL:-0}"
TTS_ENGINE="${TTS_ENGINE:-}"
FZF_BIN="${FZF_BIN:-}"
TTS_SELECTED_ENGINE=""

SERVER_URL="http://${SUPERTONIC_HOST}:${SUPERTONIC_PORT}"
SERVER_LOG="/tmp/${SCRIPT_BASENAME}.server.log"
SERVER_PID_FILE="/tmp/${SCRIPT_BASENAME}.server.pid"
# ---------- 彩色日志 ----------
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
# ---------- 通用交互 ----------
# 解析并返回后续流程需要的目标信息。
find_fzf_bin() {
  if command -v fzf >/dev/null 2>&1; then
    command -v fzf
    return 0
  fi

  local brew_prefix=""
  if command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
    if [[ -n "$brew_prefix" && -x "$brew_prefix/bin/fzf" ]]; then
      print -r -- "$brew_prefix/bin/fzf"
      return 0
    fi
  fi

  return 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_fzf_for_engine_menu() {
  if FZF_BIN="$(find_fzf_bin 2>/dev/null)"; then
    return 0
  fi

  warn_echo "未检测到 fzf，TTS 引擎选择菜单需要 fzf。"
  if command -v brew >/dev/null 2>&1; then
    if ask_enter_to_run "是否自动执行 brew install fzf"; then
      brew install fzf || return 1
      FZF_BIN="$(find_fzf_bin 2>/dev/null)" || return 1
      return 0
    fi
  else
    warn_echo "当前未检测到 Homebrew，无法自动安装 fzf。"
  fi

  return 1
}
# 收集并校验用户输入，决定后续执行路径。
select_tts_engine_text_fallback() {
  local answer=""
  echo ""
  highlight_echo "====================== 请选择 TTS 引擎 ======================" 
  log "1) MOSS-TTS-Nano    优势：CPU 友好、中文/中英混读、长文本；劣势：音质/表现力弱于 VoxCPM2"
  log "2) VoxCPM2          优势：30 语言、48kHz、声音设计/克隆；劣势：2B 大模型，首次下载大，CPU 慢"
  log "3) Supertonic       优势：轻量稳定、启动快、英文/日韩；劣势：无官方中文，中文走 macOS say"
  log "q) 退出"
  highlight_echo "============================================================"
  read -r "?$(jobs_prompt_render "请输入序号，默认 1：")" answer
  case "$answer" in
    ""|1|moss|MOSS|moss-tts|moss-tts-nano) TTS_SELECTED_ENGINE="moss"; return 0 ;;
    2|voxcpm|VoxCPM|VoxCPM2|vox|VOX) TTS_SELECTED_ENGINE="voxcpm"; return 0 ;;
    3|supertonic|Supertonic|st|ST) TTS_SELECTED_ENGINE="supertonic"; return 0 ;;
    q|Q|quit|exit) return 1 ;;
    *) warn_echo "未知选择，默认使用 MOSS-TTS-Nano。"; TTS_SELECTED_ENGINE="moss"; return 0 ;;
  esac
}
# 收集并校验用户输入，决定后续执行路径。
select_tts_engine() {
  local selected=""
  local selected_engine=""

  if [[ -n "${TTS_ENGINE:-}" ]]; then
    case "$TTS_ENGINE" in
      moss|moss-tts|moss-tts-nano|MOSS|MOSS-TTS|MOSS-TTS-Nano) TTS_SELECTED_ENGINE="moss"; return 0 ;;
      voxcpm|voxcpm2|vox|VoxCPM|VoxCPM2|VOX) TTS_SELECTED_ENGINE="voxcpm"; return 0 ;;
      supertonic|Supertonic|st|ST) TTS_SELECTED_ENGINE="supertonic"; return 0 ;;
    esac
  fi

  if ensure_fzf_for_engine_menu; then
    selected="$(cat <<'ENGINE_MENU_EOF' | "$FZF_BIN" \
      --delimiter=$'\t' \
      --with-nth=2,3 \
      --prompt='TTS Engine > ' \
      --height=45% \
      --border \
      --no-sort \
      --layout=reverse \
      --header=$'选择本次朗读引擎：Enter 确认，Esc 取消。可输入 moss / voxcpm / supertonic 快速过滤。每行已写明优势和劣势。'
moss	MOSS-TTS-Nano	优势：CPU 友好、中文/中英混读、长文本；劣势：音质/表现力弱于 VoxCPM2
voxcpm	VoxCPM2	优势：30 语言、48kHz、声音设计/克隆；劣势：2B 大模型，首次下载大，CPU 慢
supertonic	Supertonic	优势：轻量稳定、启动快、英文/日韩；劣势：无官方中文，中文走 macOS say
ENGINE_MENU_EOF
)"
    [[ -z "$selected" ]] && return 1
    selected_engine="${selected%%$'\t'*}"
    case "$selected_engine" in
      moss|voxcpm|supertonic) TTS_SELECTED_ENGINE="$selected_engine"; return 0 ;;
    esac
  fi

  select_tts_engine_text_fallback
}
# 封装 print_engine_banner 对应的独立处理逻辑。
print_engine_banner() {
  local engine="$1"
  echo ""
  case "$engine" in
    moss)
      highlight_echo "已选择：MOSS-TTS-Nano（CPU 友好 / 中文增强 / 长文本）"
      ;;
    voxcpm)
      highlight_echo "已选择：VoxCPM2（高质量 / 声音设计 / 声音克隆）"
      ;;
    supertonic)
      highlight_echo "已选择：Supertonic（轻量稳定 / 原有逻辑）"
      ;;
  esac
  echo ""
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme_and_wait() {
  clear
  highlight_echo "==================== 【MacOS】🔊Supertonic 本地朗读 ====================" | jobs_intro_style title
  color_echo "用途：输入文本，调用本机 TTS 生成语音并立即播放。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  info_echo "Supertonic 服务：${SERVER_URL}" | jobs_intro_style body
  info_echo "默认虚拟环境：${SUPERTONIC_VENV_DIR}" | jobs_intro_style body
  info_echo "英文等支持语言：走 Supertonic" | jobs_intro_style body
  info_echo "中文：默认走 macOS say，避免 Supertonic 中文发音错误" | jobs_intro_style body
  echo "" | jobs_intro_style body
  note_echo "常用输入：" | jobs_intro_style title
  gray_echo "  直接输入文本            立即朗读，例如：fuck / 你好" | jobs_intro_style body
  gray_echo "  :zh-voices              查看本机中文语音" | jobs_intro_style body
  gray_echo "  :zh-voice Tingting      指定中文语音" | jobs_intro_style body
  gray_echo "  :zh-rate 200            指定中文语速" | jobs_intro_style body
  gray_echo "  :zh-engine say          中文走 macOS say，默认推荐" | jobs_intro_style body
  gray_echo "  :zh-engine supertonic   中文也强制走 Supertonic，不推荐" | jobs_intro_style body
  gray_echo "  :voice F1               切换 Supertonic 声音" | jobs_intro_style body
  gray_echo "  :lang en                切换 Supertonic 语言" | jobs_intro_style body
  gray_echo "  :docs                   打开本地接口文档" | jobs_intro_style body
  gray_echo "  :stop                   停止本脚本启动的后台服务" | jobs_intro_style body
  gray_echo "  :quit                   退出" | jobs_intro_style body
  echo "" | jobs_intro_style body
  warn_echo "说明：Supertonic 当前没有 zh 中文模型；中文默认交给 macOS say。" | jobs_intro_style body
  gray_echo "日志：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "=======================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body
  jobs_list_intro_read -r "?$(jobs_prompt_render "👉 按回车进入朗读；按 Ctrl+C 取消：")" _
}
# 收集并校验用户输入，决定后续执行路径。
ask_enter_to_run() {
  local message="$1"
  local answer=""
  read -r "?$(jobs_prompt_render "${message}（直接回车执行；输入任意字符后回车跳过）：")" answer
  [[ -z "$answer" ]]
}
# 封装 strip_outer_quotes 对应的独立处理逻辑。
strip_outer_quotes() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value%$'\n'}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  print -r -- "$value"
}
# 封装 python_bin 对应的独立处理逻辑。
python_bin() {
  print -r -- "${SUPERTONIC_VENV_DIR}/bin/python"
}
# 封装 supertonic_bin 对应的独立处理逻辑。
supertonic_bin() {
  print -r -- "${SUPERTONIC_VENV_DIR}/bin/supertonic"
}
# 封装 require_command 对应的独立处理逻辑。
require_command() {
  local cmd="$1"
  local tip="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error_echo "未找到命令：${cmd}"
    err_echo "$tip"
    return 1
  fi
  success_echo "已检测到 ${cmd}：$(command -v "$cmd")"
}
# ---------- 环境检查 ----------
install_or_repair_environment() {
  jobs_envtts_python_preflight || return 1
  jobs_python_prepare_venv "$SUPERTONIC_VENV_DIR" 3.10 3.13 || return 1

  mkdir -p "$(dirname "$SUPERTONIC_VENV_DIR")"

  local py="$(python_bin)"
  if [[ ! -x "$py" ]]; then
    error_echo "虚拟环境 Python 不可执行：${py}"
    return 1
  fi

  note_echo "开始安装 / 补齐 supertonic[serve] 依赖。"
  "$py" -m pip install --upgrade pip >> "$LOG_FILE" 2>&1 || return 1
  "$py" -m pip install 'supertonic[serve]' >> "$LOG_FILE" 2>&1 || return 1
  success_echo "Supertonic 依赖已安装 / 补齐。"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_environment() {
  jobs_envtts_python_preflight || return 1
  jobs_python_prepare_venv "$SUPERTONIC_VENV_DIR" 3.10 3.13 || return 1
  require_command "curl" "macOS 通常自带 curl，如果缺失请检查系统环境。" || return 1

  local py="$(python_bin)"
  local st="$(supertonic_bin)"

  if [[ ! -x "$py" || ! -x "$st" ]]; then
    warn_echo "未检测到可用的 Supertonic 虚拟环境：${SUPERTONIC_VENV_DIR}"
    gray_echo "当前脚本默认读取：~/Desktop/supertonic-venv"
    gray_echo "如果虚拟环境不在默认位置，可以这样指定："
    gray_echo "SUPERTONIC_VENV_DIR=/你的/venv/路径 ${SCRIPT_PATH}"
    echo ""
    if ask_enter_to_run "是否自动创建 / 修复虚拟环境并安装 supertonic[serve]"; then
      install_or_repair_environment || {
        error_echo "环境创建 / 修复失败。日志：${LOG_FILE}"
        return 1
      }
    else
      error_echo "已跳过安装，无法继续朗读。"
      return 1
    fi
  fi

  "$py" - <<'PY' >/dev/null 2>&1
import supertonic
PY
  if [[ $? -ne 0 ]]; then
    warn_echo "虚拟环境存在，但无法 import supertonic。"
    if ask_enter_to_run "是否自动重新安装 / 补齐 supertonic[serve]"; then
      install_or_repair_environment || return 1
    else
      error_echo "已跳过修复，无法继续朗读。"
      return 1
    fi
  fi

  success_echo "Supertonic 虚拟环境可用：${SUPERTONIC_VENV_DIR}"
}
# ---------- 服务管理 ----------
is_server_alive() {
  curl -fsS "${SERVER_URL}/docs" >/dev/null 2>&1
}
# 封装 start_server_if_needed 对应的独立处理逻辑。
start_server_if_needed() {
  if is_server_alive; then
    success_echo "本地 Supertonic 服务已可用：${SERVER_URL}"
    return 0
  fi

  local st="$(supertonic_bin)"
  if [[ ! -x "$st" ]]; then
    error_echo "未找到 supertonic 可执行文件：${st}"
    return 1
  fi

  note_echo "正在后台启动 Supertonic 服务：${SERVER_URL}"
  gray_echo "首次运行可能会下载模型，服务日志：${SERVER_LOG}"
  : > "$SERVER_LOG"

  nohup "$st" serve --host "$SUPERTONIC_HOST" --port "$SUPERTONIC_PORT" >> "$SERVER_LOG" 2>&1 &
  local pid="$!"
  print -r -- "$pid" > "$SERVER_PID_FILE"

  local i=0
  while (( i < 420 )); do
    if is_server_alive; then
      success_echo "Supertonic 服务启动成功：${SERVER_URL}"
      return 0
    fi
    sleep 1
    (( i++ ))
  done

  error_echo "Supertonic 服务启动超时。"
  if command -v lsof >/dev/null 2>&1; then
    gray_echo "端口占用情况："
    lsof -nP -iTCP:"$SUPERTONIC_PORT" -sTCP:LISTEN 2>/dev/null | tee -a "$LOG_FILE" || true
  fi
  gray_echo "最近服务日志："
  tail -n 80 "$SERVER_LOG" 2>/dev/null | tee -a "$LOG_FILE"
  return 1
}
# 封装 stop_started_server 对应的独立处理逻辑。
stop_started_server() {
  if [[ ! -f "$SERVER_PID_FILE" ]]; then
    warn_echo "未找到本脚本记录的服务 PID：${SERVER_PID_FILE}"
    return 0
  fi

  local pid="$(cat "$SERVER_PID_FILE" 2>/dev/null)"
  if [[ -z "$pid" ]]; then
    warn_echo "服务 PID 为空。"
    return 0
  fi

  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    rm -f "$SERVER_PID_FILE"
    success_echo "已停止本脚本启动的 Supertonic 服务：PID ${pid}"
  else
    rm -f "$SERVER_PID_FILE"
    warn_echo "记录的服务进程已不存在：PID ${pid}"
  fi
}
# ---------- 中文 fallback ----------
contains_chinese() {
  local text="$1"
  local py="$(python_bin)"
  "$py" - "$text" <<'PY'
import re
import sys
print("yes" if re.search(r"[\u4e00-\u9fff]", sys.argv[1]) else "no")
PY
}
# 封装 list_macos_chinese_voices 对应的独立处理逻辑。
list_macos_chinese_voices() {
  if ! command -v say >/dev/null 2>&1; then
    error_echo "当前系统未找到 macOS say 命令。"
    return 1
  fi
  note_echo "本机可疑中文语音如下；如果为空，请去系统设置里下载中文朗读声音。"
  say -v '?' 2>/dev/null | grep -Ei 'zh_|chinese|mandarin|cantonese|tingting|mei-?jia|sin-?ji|yu-?shu|li-?mu' | tee -a "$LOG_FILE" || true
}
# 封装 pick_macos_chinese_voice 对应的独立处理逻辑。
pick_macos_chinese_voice() {
  if [[ -n "$SUPERTONIC_ZH_VOICE" ]]; then
    print -r -- "$SUPERTONIC_ZH_VOICE"
    return 0
  fi

  local voices
  voices="$(say -v '?' 2>/dev/null || true)"

  local preferred
  for preferred in Tingting Mei-Jia Meijia Sin-ji Sinji Yu-shu Yushu Li-mu Limu; do
    if print -r -- "$voices" | awk '{print $1}' | grep -Fxq "$preferred"; then
      print -r -- "$preferred"
      return 0
    fi
  done

  local detected
  detected="$(print -r -- "$voices" | awk 'BEGIN{IGNORECASE=1} /zh_|Chinese|Mandarin|Cantonese/ {print $1; exit}')"
  if [[ -n "$detected" ]]; then
    print -r -- "$detected"
    return 0
  fi

  return 1
}
# 封装 speak_chinese_with_macos_say 对应的独立处理逻辑。
speak_chinese_with_macos_say() {
  local raw_text="$1"
  local text="$(strip_outer_quotes "$raw_text")"

  if ! command -v say >/dev/null 2>&1; then
    error_echo "未找到 macOS say 命令，无法使用中文 fallback。"
    return 1
  fi

  local timestamp="$(date '+%Y%m%d_%H%M%S')"
  mkdir -p "$SUPERTONIC_OUTPUT_DIR"
  local output_file="${SUPERTONIC_OUTPUT_DIR}/macos_say_zh_${timestamp}.aiff"

  local voice=""
  voice="$(pick_macos_chinese_voice || true)"

  if [[ -n "$voice" ]]; then
    note_echo "检测到中文：使用 macOS say 朗读，voice=${voice} rate=${SUPERTONIC_ZH_RATE}"
    say -v "$voice" -r "$SUPERTONIC_ZH_RATE" -o "$output_file" "$text" >> "$LOG_FILE" 2>&1
  else
    warn_echo "未找到明确中文语音，使用 macOS 默认语音尝试朗读。"
    warn_echo "建议下载中文语音后执行 :zh-voices / :zh-voice。"
    say -r "$SUPERTONIC_ZH_RATE" -o "$output_file" "$text" >> "$LOG_FILE" 2>&1
  fi

  if [[ $? -ne 0 || ! -s "$output_file" ]]; then
    error_echo "macOS say 生成中文音频失败：${output_file}"
    return 1
  fi

  success_echo "中文语音已生成：${output_file}"

  if command -v afplay >/dev/null 2>&1; then
    afplay "$output_file"
  else
    open "$output_file"
  fi
}
# ---------- 语音生成 ----------
detect_lang() {
  local text="$1"
  local py="$(python_bin)"
  "$py" - "$text" <<'PY'
import re
import sys

text = sys.argv[1]
if re.search(r"[\u3040-\u30ff]", text):
    print("ja")
elif re.search(r"[\uac00-\ud7af]", text):
    print("ko")
elif re.search(r"[\u4e00-\u9fff]", text):
    print("na")
else:
    print("en")
PY
}
# 封装 build_payload 对应的独立处理逻辑。
build_payload() {
  local text="$1"
  local lang="$2"
  local py="$(python_bin)"
  "$py" - "$text" "$SUPERTONIC_VOICE" "$lang" "$SUPERTONIC_STEPS" "$SUPERTONIC_SPEED" <<'PY'
import json
import sys

text, voice, lang, steps, speed = sys.argv[1:6]
payload = {
    "text": text,
    "voice": voice,
    "lang": lang,
    "steps": int(steps),
    "speed": float(speed),
    "response_format": "wav",
}
print(json.dumps(payload, ensure_ascii=False))
PY
}
# 封装 speak_text 对应的独立处理逻辑。
speak_text() {
  local raw_text="$1"
  local text="$(strip_outer_quotes "$raw_text")"

  if [[ -z "$text" ]]; then
    warn_echo "空文本，已跳过。"
    return 0
  fi

  local has_chinese="$(contains_chinese "$text")"
  if [[ "$has_chinese" == "yes" && "$SUPERTONIC_ZH_ENGINE" == "say" ]]; then
    speak_chinese_with_macos_say "$text"
    return $?
  fi

  local lang="$SUPERTONIC_LANG"
  if [[ "$lang" == "auto" ]]; then
    lang="$(detect_lang "$text")"
  fi

  local timestamp="$(date '+%Y%m%d_%H%M%S')"
  mkdir -p "$SUPERTONIC_OUTPUT_DIR"
  local output_file="${SUPERTONIC_OUTPUT_DIR}/supertonic_${timestamp}.wav"
  local payload="$(build_payload "$text" "$lang")"

  note_echo "正在生成语音：voice=${SUPERTONIC_VOICE} lang=${lang} steps=${SUPERTONIC_STEPS} speed=${SUPERTONIC_SPEED}"

  curl -fsS -X POST "${SERVER_URL}/v1/tts" \
    -H 'content-type: application/json' \
    -d "$payload" \
    -o "$output_file" >> "$LOG_FILE" 2>&1

  if [[ $? -ne 0 || ! -s "$output_file" ]]; then
    error_echo "语音生成失败：${output_file}"
    gray_echo "最近服务日志："
    tail -n 80 "$SERVER_LOG" 2>/dev/null | tee -a "$LOG_FILE"
    return 1
  fi

  success_echo "语音已生成：${output_file}"

  if command -v afplay >/dev/null 2>&1; then
    afplay "$output_file"
  else
    open "$output_file"
  fi
}
# ---------- MOSS-TTS-Nano 引擎 ----------
moss_python_bin() {
  print -r -- "${MOSS_TTS_NANO_VENV_DIR}/bin/python"
}
# 封装 moss_cli_bin 对应的独立处理逻辑。
moss_cli_bin() {
  print -r -- "${MOSS_TTS_NANO_VENV_DIR}/bin/moss-tts-nano"
}
# 封装 moss_install_or_repair_environment 对应的独立处理逻辑。
moss_install_or_repair_environment() {
  jobs_envtts_python_preflight || return 1
  jobs_python_prepare_venv "$MOSS_TTS_NANO_VENV_DIR" 3.10 3.13 || return 1
  if ! command -v git >/dev/null 2>&1; then
    error_echo "未找到 git，无法拉取 MOSS-TTS-Nano 仓库。"
    err_echo "请先安装 git，例如：brew install git"
    return 1
  fi

  mkdir -p "$(dirname "$MOSS_TTS_NANO_HOME")" "$(dirname "$MOSS_TTS_NANO_VENV_DIR")"

  if [[ ! -d "$MOSS_TTS_NANO_HOME/.git" ]]; then
    if [[ -e "$MOSS_TTS_NANO_HOME" ]]; then
      error_echo "目标目录已存在但不是 git 仓库：${MOSS_TTS_NANO_HOME}"
      err_echo "请删除 / 改名后重试，或设置 MOSS_TTS_NANO_HOME 指向正确仓库。"
      return 1
    fi
    note_echo "开始克隆 MOSS-TTS-Nano：${MOSS_TTS_NANO_HOME}"
    git clone "$MOSS_TTS_NANO_REPO_URL" "$MOSS_TTS_NANO_HOME" >> "$LOG_FILE" 2>&1 || return 1
  else
    note_echo "检测到 MOSS-TTS-Nano 仓库，执行 git pull 同步。"
    (cd "$MOSS_TTS_NANO_HOME" && git pull --ff-only) >> "$LOG_FILE" 2>&1 || warn_echo "git pull 失败，继续使用本地已有版本。"
  fi

  local py="$(moss_python_bin)"
  if [[ ! -x "$py" ]]; then
    error_echo "MOSS-TTS-Nano 虚拟环境 Python 不可执行：${py}"
    return 1
  fi

  note_echo "开始安装 / 补齐 MOSS-TTS-Nano 依赖。"
  "$py" -m pip install --upgrade pip >> "$LOG_FILE" 2>&1 || return 1

  if [[ -f "$MOSS_TTS_NANO_HOME/requirements.txt" ]]; then
    (cd "$MOSS_TTS_NANO_HOME" && "$py" -m pip install -r requirements.txt) >> "$LOG_FILE" 2>&1 || {
      error_echo "MOSS-TTS-Nano requirements 安装失败。"
      warn_echo "常见原因：WeTextProcessing / pynini 在非 conda 环境安装失败。"
      err_echo "可按官方建议手动处理 pynini 后重试，日志：${LOG_FILE}"
      return 1
    }
  fi

  (cd "$MOSS_TTS_NANO_HOME" && "$py" -m pip install -e .) >> "$LOG_FILE" 2>&1 || return 1
  success_echo "MOSS-TTS-Nano 依赖已安装 / 补齐。"
}
# 封装 moss_ensure_environment 对应的独立处理逻辑。
moss_ensure_environment() {
  jobs_envtts_python_preflight || return 1
  jobs_python_prepare_venv "$MOSS_TTS_NANO_VENV_DIR" 3.10 3.13 || return 1
  local cli="$(moss_cli_bin)"

  if [[ ! -x "$cli" || ! -d "$MOSS_TTS_NANO_HOME" ]]; then
    warn_echo "未检测到可用的 MOSS-TTS-Nano 环境。"
    gray_echo "默认仓库目录：${MOSS_TTS_NANO_HOME}"
    gray_echo "默认虚拟环境：${MOSS_TTS_NANO_VENV_DIR}"
    if [[ "$MOSS_TTS_NANO_SKIP_INSTALL" == "1" ]]; then
      error_echo "已设置 MOSS_TTS_NANO_SKIP_INSTALL=1，跳过自动安装。"
      return 1
    fi
    if ask_enter_to_run "是否自动克隆 / 创建虚拟环境 / 安装 MOSS-TTS-Nano"; then
      moss_install_or_repair_environment || {
        error_echo "MOSS-TTS-Nano 环境创建 / 修复失败。日志：${LOG_FILE}"
        return 1
      }
    else
      error_echo "已跳过安装，无法继续使用 MOSS-TTS-Nano。"
      return 1
    fi
  fi

  if [[ ! -f "$MOSS_TTS_NANO_PROMPT_SPEECH" ]]; then
    warn_echo "未找到 MOSS-TTS-Nano 参考音频：${MOSS_TTS_NANO_PROMPT_SPEECH}"
    gray_echo "脚本默认使用仓库内 assets/audio/zh_1.wav 作为 voice clone 参考音频。"
    gray_echo "可以通过 :prompt /path/to/your_voice.wav 或环境变量 MOSS_TTS_NANO_PROMPT_SPEECH 指定。"
  fi

  success_echo "MOSS-TTS-Nano 环境可用：${MOSS_TTS_NANO_HOME}"
}
# 封装 moss_detect_lang 对应的独立处理逻辑。
moss_detect_lang() {
  local text="$1"
  local py="$(moss_python_bin)"
  if [[ ! -x "$py" ]]; then
    py="$JOBS_PYTHON_BIN"
  fi
  "$py" - "$text" <<'MOSS_LANG_EOF'
import re, sys
text = sys.argv[1]
if re.search(r"[\u4e00-\u9fff]", text):
    print("zh")
elif re.search(r"[\u3040-\u30ff]", text):
    print("ja")
elif re.search(r"[\uac00-\ud7af]", text):
    print("ko")
else:
    print("en")
MOSS_LANG_EOF
}
# 封装 moss_speak_text 对应的独立处理逻辑。
moss_speak_text() {
  local raw_text="$1"
  local text="$(strip_outer_quotes "$raw_text")"

  if [[ -z "$text" ]]; then
    warn_echo "空文本，已跳过。"
    return 0
  fi

  local cli="$(moss_cli_bin)"
  if [[ ! -x "$cli" ]]; then
    error_echo "未找到 moss-tts-nano 命令：${cli}"
    return 1
  fi

  if [[ ! -f "$MOSS_TTS_NANO_PROMPT_SPEECH" ]]; then
    error_echo "未找到 MOSS-TTS-Nano 参考音频：${MOSS_TTS_NANO_PROMPT_SPEECH}"
    err_echo "请先执行：:prompt /path/to/your_voice.wav"
    return 1
  fi

  mkdir -p "$MOSS_TTS_NANO_OUTPUT_DIR" "$MOSS_TTS_NANO_HOME/generated_audio"
  local timestamp="$(date '+%Y%m%d_%H%M%S')"
  local default_output="${MOSS_TTS_NANO_HOME}/generated_audio/moss_tts_nano_output.wav"
  local output_file="${MOSS_TTS_NANO_OUTPUT_DIR}/moss_tts_nano_${timestamp}.wav"
  local detected_lang="$(moss_detect_lang "$text" 2>/dev/null || print -r -- auto)"

  note_echo "正在生成语音：engine=MOSS-TTS-Nano backend=${MOSS_TTS_NANO_BACKEND} provider=${MOSS_TTS_NANO_EXECUTION_PROVIDER} lang=${detected_lang}"
  gray_echo "参考音频：${MOSS_TTS_NANO_PROMPT_SPEECH}"
  gray_echo "首次运行会自动下载 ONNX 模型，耗时取决于网络。"

  rm -f "$default_output"

  local cmd=("$cli" generate --prompt-speech "$MOSS_TTS_NANO_PROMPT_SPEECH" --text "$text")
  if [[ -n "$MOSS_TTS_NANO_BACKEND" ]]; then
    cmd+=(--backend "$MOSS_TTS_NANO_BACKEND")
  fi
  if [[ "$MOSS_TTS_NANO_BACKEND" == "onnx" && -n "$MOSS_TTS_NANO_EXECUTION_PROVIDER" ]]; then
    cmd+=(--execution-provider "$MOSS_TTS_NANO_EXECUTION_PROVIDER")
  fi

  (cd "$MOSS_TTS_NANO_HOME" && "${cmd[@]}") >> "$LOG_FILE" 2>&1
  if [[ $? -ne 0 ]]; then
    error_echo "MOSS-TTS-Nano 语音生成失败。"
    gray_echo "最近日志："
    tail -n 120 "$LOG_FILE" 2>/dev/null | tee -a "$LOG_FILE"
    return 1
  fi

  if [[ ! -s "$default_output" ]]; then
    error_echo "未找到 MOSS-TTS-Nano 默认输出文件：${default_output}"
    gray_echo "请检查 CLI 是否变更了默认输出路径。日志：${LOG_FILE}"
    return 1
  fi

  cp -f "$default_output" "$output_file" || return 1
  success_echo "语音已生成：${output_file}"

  if command -v afplay >/dev/null 2>&1; then
    afplay "$output_file"
  else
    open "$output_file"
  fi
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
moss_show_readme_and_wait() {
  clear
  highlight_echo "==================== 【MacOS】🔊MOSS-TTS-Nano 本地朗读 ====================" | jobs_intro_style title
  color_echo "用途：输入文本，调用 MOSS-TTS-Nano 生成语音并立即播放。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  info_echo "默认仓库目录：${MOSS_TTS_NANO_HOME}" | jobs_intro_style body
  info_echo "默认虚拟环境：${MOSS_TTS_NANO_VENV_DIR}" | jobs_intro_style body
  info_echo "默认后端：${MOSS_TTS_NANO_BACKEND} / ${MOSS_TTS_NANO_EXECUTION_PROVIDER}" | jobs_intro_style body
  info_echo "默认参考音频：${MOSS_TTS_NANO_PROMPT_SPEECH}" | jobs_intro_style body
  echo "" | jobs_intro_style body
  note_echo "常用输入：" | jobs_intro_style title
  gray_echo "  直接输入文本              立即朗读，例如：你好 / Hello" | jobs_intro_style body
  gray_echo "  :prompt /path/voice.wav   指定 MOSS 参考音频" | jobs_intro_style body
  gray_echo "  :backend onnx             使用 ONNX 后端，默认推荐" | jobs_intro_style body
  gray_echo "  :provider cpu             ONNX CPU 推理，默认推荐" | jobs_intro_style body
  gray_echo "  :config                   查看当前配置" | jobs_intro_style body
  gray_echo "  :quit                     退出" | jobs_intro_style body
  echo "" | jobs_intro_style body
  warn_echo "说明：MOSS-TTS-Nano 首次运行会下载模型；如果网络慢，需要等待。" | jobs_intro_style body
  gray_echo "日志：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "==========================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body
  jobs_list_intro_read -r "?$(jobs_prompt_render "👉 按回车进入朗读；按 Ctrl+C 取消：")" _
}
# 封装 moss_show_runtime_config 对应的独立处理逻辑。
moss_show_runtime_config() {
  echo ""
  highlight_echo "========================= MOSS-TTS-Nano 当前配置 ========================="
  gray_echo "仓库目录：${MOSS_TTS_NANO_HOME}"
  gray_echo "虚拟环境：${MOSS_TTS_NANO_VENV_DIR}"
  gray_echo "后端：${MOSS_TTS_NANO_BACKEND}"
  gray_echo "执行设备：${MOSS_TTS_NANO_EXECUTION_PROVIDER}"
  gray_echo "参考音频：${MOSS_TTS_NANO_PROMPT_SPEECH}"
  gray_echo "输出目录：${MOSS_TTS_NANO_OUTPUT_DIR}"
  gray_echo "日志：${LOG_FILE}"
  highlight_echo "========================================================================="
  echo ""
}
# 封装 moss_show_help 对应的独立处理逻辑。
moss_show_help() {
  cat <<'MOSS_HELP_EOF' | tee -a "$LOG_FILE" | jobs_prompt_filter
可用命令：
  直接输入文本              立即朗读
  :prompt /path/voice.wav   指定 voice clone 参考音频
  :backend onnx             切换后端，默认 onnx
  :provider cpu             切换 ONNX 执行设备，默认 cpu；可选 cuda
  :config                   查看当前配置
  :quit                     退出脚本
MOSS_HELP_EOF
}
# 封装 moss_interactive_loop 对应的独立处理逻辑。
moss_interactive_loop() {
  moss_show_runtime_config
  moss_show_help
  echo ""

  while true; do
    local input=""
    read -r "?$(jobs_prompt_render "🔊 请输入要朗读的文本（直接回车退出）： ")" input
    input="$(strip_outer_quotes "$input")"

    if [[ -z "$input" ]]; then
      success_echo "已退出朗读循环。"
      break
    fi

    case "$input" in
      ":quit"|":q"|":exit")
        success_echo "已退出朗读循环。"
        break
        ;;
      ":help")
        moss_show_help
        ;;
      ":config")
        moss_show_runtime_config
        ;;
      ":prompt "*)
        MOSS_TTS_NANO_PROMPT_SPEECH="${input#":prompt "}"
        success_echo "MOSS 参考音频已切换为：${MOSS_TTS_NANO_PROMPT_SPEECH}"
        ;;
      ":backend "*)
        MOSS_TTS_NANO_BACKEND="${input#":backend "}"
        success_echo "MOSS 后端已切换为：${MOSS_TTS_NANO_BACKEND}"
        ;;
      ":provider "*)
        MOSS_TTS_NANO_EXECUTION_PROVIDER="${input#":provider "}"
        success_echo "MOSS 执行设备已切换为：${MOSS_TTS_NANO_EXECUTION_PROVIDER}"
        ;;
      *)
        moss_speak_text "$input"
        ;;
    esac
    echo ""
  done
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
moss_main() {
  # 根据当前条件选择对应的执行分支。
  if [[ "$#" -gt 0 ]]; then
    # 检查当前步骤所需的环境、路径或输入条件。
    moss_ensure_environment || exit 1
    # 执行当前流程中的独立业务步骤：moss_speak_text。
    moss_speak_text "$*"
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 展示脚本说明并等待用户确认影响范围。
  moss_show_readme_and_wait
  # 检查当前步骤所需的环境、路径或输入条件。
  moss_ensure_environment || exit 1
  # 执行当前流程中的独立业务步骤：moss_interactive_loop。
  moss_interactive_loop
}
# ---------- VoxCPM2 引擎 ----------
voxcpm_python_bin() {
  print -r -- "${VOXCPM_VENV_DIR}/bin/python"
}
# 封装 voxcpm_cli_bin 对应的独立处理逻辑。
voxcpm_cli_bin() {
  print -r -- "${VOXCPM_VENV_DIR}/bin/voxcpm"
}
# 封装 voxcpm_install_or_repair_environment 对应的独立处理逻辑。
voxcpm_install_or_repair_environment() {
  jobs_envtts_python_preflight || return 1
  jobs_python_prepare_venv "$VOXCPM_VENV_DIR" 3.10 3.13 || return 1

  mkdir -p "$(dirname "$VOXCPM_VENV_DIR")"

  local py="$(voxcpm_python_bin)"
  if [[ ! -x "$py" ]]; then
    error_echo "VoxCPM 虚拟环境 Python 不可执行：${py}"
    return 1
  fi

  if [[ -n "$VOXCPM_HF_ENDPOINT" ]]; then
    export HF_ENDPOINT="$VOXCPM_HF_ENDPOINT"
  fi

  note_echo "开始安装 / 补齐 VoxCPM 依赖。"
  "$py" -m pip install --upgrade pip >> "$LOG_FILE" 2>&1 || return 1
  "$py" -m pip install voxcpm >> "$LOG_FILE" 2>&1 || return 1

  "$py" - <<'VOXCPM_IMPORT_EOF' >> "$LOG_FILE" 2>&1
from voxcpm import VoxCPM
print("VoxCPM is ready")
VOXCPM_IMPORT_EOF
  if [[ $? -ne 0 ]]; then
    error_echo "VoxCPM 安装后仍无法 import。日志：${LOG_FILE}"
    return 1
  fi

  success_echo "VoxCPM 依赖已安装 / 补齐。"
}
# 封装 voxcpm_ensure_environment 对应的独立处理逻辑。
voxcpm_ensure_environment() {
  jobs_envtts_python_preflight || return 1
  jobs_python_prepare_venv "$VOXCPM_VENV_DIR" 3.10 3.13 || return 1
  local cli="$(voxcpm_cli_bin)"
  local py="$(voxcpm_python_bin)"

  if [[ ! -x "$py" || ! -x "$cli" ]]; then
    warn_echo "未检测到可用的 VoxCPM 环境。"
    gray_echo "默认虚拟环境：${VOXCPM_VENV_DIR}"
    if [[ "$VOXCPM_SKIP_INSTALL" == "1" ]]; then
      error_echo "已设置 VOXCPM_SKIP_INSTALL=1，跳过自动安装。"
      return 1
    fi
    if ask_enter_to_run "是否自动创建 / 修复 VoxCPM 环境并安装 voxcpm"; then
      voxcpm_install_or_repair_environment || {
        error_echo "VoxCPM 环境创建 / 修复失败。日志：${LOG_FILE}"
        return 1
      }
    else
      error_echo "已跳过安装，无法继续朗读。"
      return 1
    fi
  fi

  "$py" - <<'VOXCPM_CHECK_EOF' >/dev/null 2>&1
from voxcpm import VoxCPM
VOXCPM_CHECK_EOF
  if [[ $? -ne 0 ]]; then
    warn_echo "虚拟环境存在，但无法 import voxcpm。"
    if ask_enter_to_run "是否自动重新安装 / 补齐 voxcpm"; then
      voxcpm_install_or_repair_environment || return 1
    else
      error_echo "已跳过修复，无法继续朗读。"
      return 1
    fi
  fi

  success_echo "VoxCPM 虚拟环境可用：${VOXCPM_VENV_DIR}"
}
# 封装 voxcpm_speak_text 对应的独立处理逻辑。
voxcpm_speak_text() {
  local raw_text="$1"
  local text="$(strip_outer_quotes "$raw_text")"

  if [[ -z "$text" ]]; then
    warn_echo "空文本，已跳过。"
    return 0
  fi

  local cli="$(voxcpm_cli_bin)"
  if [[ ! -x "$cli" ]]; then
    error_echo "未找到 voxcpm 命令：${cli}"
    return 1
  fi

  if [[ -n "$VOXCPM_PROMPT_AUDIO" && -z "$VOXCPM_PROMPT_TEXT" ]]; then
    error_echo "已设置 VOXCPM_PROMPT_AUDIO，但未设置 VOXCPM_PROMPT_TEXT。Hi-Fi 克隆需要参考音频的逐字稿。"
    err_echo "请在交互里执行：:prompt-text 参考音频对应文本"
    return 1
  fi

  if [[ -n "$VOXCPM_REFERENCE_AUDIO" && ! -f "$VOXCPM_REFERENCE_AUDIO" ]]; then
    error_echo "VoxCPM 参考音频不存在：${VOXCPM_REFERENCE_AUDIO}"
    return 1
  fi

  if [[ -n "$VOXCPM_PROMPT_AUDIO" && ! -f "$VOXCPM_PROMPT_AUDIO" ]]; then
    error_echo "VoxCPM prompt 音频不存在：${VOXCPM_PROMPT_AUDIO}"
    return 1
  fi

  if [[ -n "$VOXCPM_HF_ENDPOINT" ]]; then
    export HF_ENDPOINT="$VOXCPM_HF_ENDPOINT"
  fi

  mkdir -p "$VOXCPM_OUTPUT_DIR"
  local timestamp="$(date '+%Y%m%d_%H%M%S')"
  local output_file="${VOXCPM_OUTPUT_DIR}/voxcpm_${timestamp}.wav"
  local cmd=()
  local mode="design"

  if [[ -n "$VOXCPM_PROMPT_AUDIO" ]]; then
    mode="clone"
    cmd=("$cli" clone --text "$text" --prompt-audio "$VOXCPM_PROMPT_AUDIO" --prompt-text "$VOXCPM_PROMPT_TEXT" --output "$output_file")
    [[ -n "$VOXCPM_REFERENCE_AUDIO" ]] && cmd+=(--reference-audio "$VOXCPM_REFERENCE_AUDIO")
    note_echo "正在生成语音：engine=VoxCPM2 mode=Hi-Fi Clone device=${VOXCPM_DEVICE}"
  elif [[ -n "$VOXCPM_REFERENCE_AUDIO" ]]; then
    mode="clone"
    cmd=("$cli" clone --text "$text" --reference-audio "$VOXCPM_REFERENCE_AUDIO" --output "$output_file")
    note_echo "正在生成语音：engine=VoxCPM2 mode=Clone device=${VOXCPM_DEVICE}"
  else
    cmd=("$cli" design --text "$text" --output "$output_file")
    [[ -n "$VOXCPM_CONTROL" ]] && cmd+=(--control "$VOXCPM_CONTROL")
    note_echo "正在生成语音：engine=VoxCPM2 mode=Design device=${VOXCPM_DEVICE}"
  fi

  [[ -n "$VOXCPM_DEVICE" ]] && cmd+=(--device "$VOXCPM_DEVICE")
  [[ "$VOXCPM_NO_OPTIMIZE" == "1" || "$VOXCPM_NO_OPTIMIZE" == "true" ]] && cmd+=(--no-optimize)
  [[ "$mode" == "clone" && ( "$VOXCPM_DENOISE" == "1" || "$VOXCPM_DENOISE" == "true" ) ]] && cmd+=(--denoise)

  gray_echo "输出文件：${output_file}"
  gray_echo "首次运行会自动下载 VoxCPM2 权重，体积较大；CPU 模式可能很慢，Apple Silicon 建议 device=mps。"

  "${cmd[@]}" >> "$LOG_FILE" 2>&1
  if [[ $? -ne 0 || ! -s "$output_file" ]]; then
    error_echo "VoxCPM 语音生成失败：${output_file}"
    gray_echo "最近日志："
    tail -n 160 "$LOG_FILE" 2>/dev/null | tee -a "$LOG_FILE"
    return 1
  fi

  success_echo "语音已生成：${output_file}"

  if command -v afplay >/dev/null 2>&1; then
    afplay "$output_file"
  else
    open "$output_file"
  fi
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
voxcpm_show_readme_and_wait() {
  clear
  highlight_echo "====================== 【MacOS】🔊VoxCPM2 本地朗读 ======================" | jobs_intro_style title
  color_echo "用途：高质量多语言 TTS、声音设计、参考音频克隆。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  info_echo "默认虚拟环境：${VOXCPM_VENV_DIR}" | jobs_intro_style body
  info_echo "默认设备：${VOXCPM_DEVICE}（auto 会按 cuda → mps → cpu 选择）" | jobs_intro_style body
  info_echo "输出目录：${VOXCPM_OUTPUT_DIR}" | jobs_intro_style body
  echo "" | jobs_intro_style body
  note_echo "常用输入：" | jobs_intro_style title
  gray_echo "  直接输入文本                    立即朗读" | jobs_intro_style body
  gray_echo "  :device auto|mps|cpu|cuda       切换设备，Apple Silicon 推荐 mps" | jobs_intro_style body
  gray_echo "  :control 年轻女声，温柔甜美       设置声音设计提示词" | jobs_intro_style body
  gray_echo "  :reference /path/voice.wav      使用参考音频做声音克隆" | jobs_intro_style body
  gray_echo "  :prompt /path/voice.wav         Hi-Fi 克隆 prompt 音频，需要配合 :prompt-text" | jobs_intro_style body
  gray_echo "  :prompt-text 参考音频逐字稿       设置 Hi-Fi 克隆参考文本" | jobs_intro_style body
  gray_echo "  :denoise on|off                 克隆时是否对参考音频降噪" | jobs_intro_style body
  gray_echo "  :optimize on|off                控制 torch.compile；CPU/MPS 不稳时建议 off" | jobs_intro_style body
  gray_echo "  :hf-mirror on|off               设置 / 取消 HF_ENDPOINT=https://hf-mirror.com" | jobs_intro_style body
  gray_echo "  :config                         查看当前配置" | jobs_intro_style body
  gray_echo "  :quit                           退出" | jobs_intro_style body
  echo "" | jobs_intro_style body
  warn_echo "说明：VoxCPM2 质量强，但模型大；首次下载慢，CPU 推理慢。普通短文本/英文轻量朗读不要默认选它。" | jobs_intro_style body
  gray_echo "日志：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "=======================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body
  jobs_list_intro_read -r "?$(jobs_prompt_render "👉 按回车进入朗读；按 Ctrl+C 取消：")" _
}
# 封装 voxcpm_show_runtime_config 对应的独立处理逻辑。
voxcpm_show_runtime_config() {
  echo ""
  highlight_echo "============================ VoxCPM2 当前配置 ============================"
  gray_echo "虚拟环境：${VOXCPM_VENV_DIR}"
  gray_echo "设备：${VOXCPM_DEVICE}"
  gray_echo "声音设计提示：${VOXCPM_CONTROL:-未设置}"
  gray_echo "参考音频：${VOXCPM_REFERENCE_AUDIO:-未设置}"
  gray_echo "Prompt 音频：${VOXCPM_PROMPT_AUDIO:-未设置}"
  gray_echo "Prompt 文本：${VOXCPM_PROMPT_TEXT:-未设置}"
  gray_echo "降噪：${VOXCPM_DENOISE}"
  gray_echo "no-optimize：${VOXCPM_NO_OPTIMIZE}"
  gray_echo "HF_ENDPOINT：${HF_ENDPOINT:-${VOXCPM_HF_ENDPOINT:-未设置}}"
  gray_echo "输出目录：${VOXCPM_OUTPUT_DIR}"
  gray_echo "日志：${LOG_FILE}"
  highlight_echo "========================================================================="
  echo ""
}
# 封装 voxcpm_show_help 对应的独立处理逻辑。
voxcpm_show_help() {
  cat <<'VOXCPM_HELP_EOF' | tee -a "$LOG_FILE" | jobs_prompt_filter
可用命令：
  直接输入文本                    立即朗读
  :device auto|mps|cpu|cuda       切换设备
  :control 文本                   设置声音设计提示词；清空用 :control off
  :reference /path/voice.wav      设置参考音频；清空用 :reference off
  :prompt /path/voice.wav         设置 Hi-Fi 克隆 prompt 音频；清空用 :prompt off
  :prompt-text 文本               设置 Hi-Fi 克隆 prompt 文本；清空用 :prompt-text off
  :denoise on|off                 克隆时是否启用参考音频降噪
  :optimize on|off                on=允许优化；off=传入 --no-optimize
  :hf-mirror on|off               on=HF_ENDPOINT=https://hf-mirror.com
  :config                         查看当前配置
  :quit                           退出脚本
VOXCPM_HELP_EOF
}
# 封装 voxcpm_interactive_loop 对应的独立处理逻辑。
voxcpm_interactive_loop() {
  voxcpm_show_runtime_config
  voxcpm_show_help
  echo ""

  while true; do
    local input=""
    read -r "?$(jobs_prompt_render "🔊 请输入要朗读的文本（直接回车退出）： ")" input
    input="$(strip_outer_quotes "$input")"

    if [[ -z "$input" ]]; then
      success_echo "已退出朗读循环。"
      break
    fi

    case "$input" in
      ":quit"|":q"|":exit")
        success_echo "已退出朗读循环。"
        break
        ;;
      ":help")
        voxcpm_show_help
        ;;
      ":config")
        voxcpm_show_runtime_config
        ;;
      ":device "*)
        VOXCPM_DEVICE="${input#":device "}"
        success_echo "VoxCPM 设备已切换为：${VOXCPM_DEVICE}"
        ;;
      ":control off")
        VOXCPM_CONTROL=""
        success_echo "VoxCPM 声音设计提示已清空。"
        ;;
      ":control "*)
        VOXCPM_CONTROL="${input#":control "}"
        success_echo "VoxCPM 声音设计提示已设置为：${VOXCPM_CONTROL}"
        ;;
      ":reference off")
        VOXCPM_REFERENCE_AUDIO=""
        success_echo "VoxCPM 参考音频已清空。"
        ;;
      ":reference "*)
        VOXCPM_REFERENCE_AUDIO="${input#":reference "}"
        success_echo "VoxCPM 参考音频已切换为：${VOXCPM_REFERENCE_AUDIO}"
        ;;
      ":prompt off")
        VOXCPM_PROMPT_AUDIO=""
        success_echo "VoxCPM prompt 音频已清空。"
        ;;
      ":prompt "*)
        VOXCPM_PROMPT_AUDIO="${input#":prompt "}"
        success_echo "VoxCPM prompt 音频已切换为：${VOXCPM_PROMPT_AUDIO}"
        ;;
      ":prompt-text off")
        VOXCPM_PROMPT_TEXT=""
        success_echo "VoxCPM prompt 文本已清空。"
        ;;
      ":prompt-text "*)
        VOXCPM_PROMPT_TEXT="${input#":prompt-text "}"
        success_echo "VoxCPM prompt 文本已设置。"
        ;;
      ":denoise on")
        VOXCPM_DENOISE="1"
        success_echo "VoxCPM 降噪已开启。"
        ;;
      ":denoise off")
        VOXCPM_DENOISE="0"
        success_echo "VoxCPM 降噪已关闭。"
        ;;
      ":optimize on")
        VOXCPM_NO_OPTIMIZE="0"
        success_echo "VoxCPM 优化已开启。"
        ;;
      ":optimize off")
        VOXCPM_NO_OPTIMIZE="1"
        success_echo "VoxCPM 优化已关闭，将传入 --no-optimize。"
        ;;
      ":hf-mirror on")
        VOXCPM_HF_ENDPOINT="https://hf-mirror.com"
        export HF_ENDPOINT="$VOXCPM_HF_ENDPOINT"
        success_echo "已设置 HF_ENDPOINT=${VOXCPM_HF_ENDPOINT}"
        ;;
      ":hf-mirror off")
        VOXCPM_HF_ENDPOINT=""
        unset HF_ENDPOINT
        success_echo "已取消 HF_ENDPOINT。"
        ;;
      *)
        voxcpm_speak_text "$input"
        ;;
    esac
    echo ""
  done
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
voxcpm_main() {
  # 根据当前条件选择对应的执行分支。
  if [[ "$#" -gt 0 ]]; then
    # 检查当前步骤所需的环境、路径或输入条件。
    voxcpm_ensure_environment || exit 1
    # 执行当前流程中的独立业务步骤：voxcpm_speak_text。
    voxcpm_speak_text "$*"
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 展示脚本说明并等待用户确认影响范围。
  voxcpm_show_readme_and_wait
  # 检查当前步骤所需的环境、路径或输入条件。
  voxcpm_ensure_environment || exit 1
  # 执行当前流程中的独立业务步骤：voxcpm_interactive_loop。
  voxcpm_interactive_loop
}
# ---------- 菜单与交互 ----------
show_supported_languages() {
  cat <<'EOF' | tee -a "$LOG_FILE" | jobs_prompt_filter
支持语言代码：
  en 英语    ko 韩语    ja 日语    ar 阿拉伯语
  bg 保加利亚语 cs 捷克语 da 丹麦语 de 德语
  el 希腊语  es 西班牙语 et 爱沙尼亚语 fi 芬兰语
  fr 法语    hi 印地语 hr 克罗地亚语 hu 匈牙利语
  id 印尼语  it 意大利语 lt 立陶宛语 lv 拉脱维亚语
  nl 荷兰语  pl 波兰语 pt 葡萄牙语 ro 罗马尼亚语
  ru 俄语    sk 斯洛伐克语 sl 斯洛文尼亚语 sv 瑞典语
  tr 土耳其语 uk 乌克兰语 vi 越南语
  na 未知 / fallback

注意：官方公开语言列表没有 zh / 中文。中文建议用 auto 或 na，但效果不保证。
EOF
}
# 封装 show_runtime_config 对应的独立处理逻辑。
show_runtime_config() {
  echo ""
  highlight_echo "============================== 当前配置 =============================="
  gray_echo "虚拟环境：${SUPERTONIC_VENV_DIR}"
  gray_echo "服务地址：${SERVER_URL}"
  gray_echo "声音角色：${SUPERTONIC_VOICE}"
  gray_echo "语言模式：${SUPERTONIC_LANG}"
  gray_echo "推理步数：${SUPERTONIC_STEPS}"
  gray_echo "语速倍数：${SUPERTONIC_SPEED}"
  gray_echo "输出目录：${SUPERTONIC_OUTPUT_DIR}"
  gray_echo "中文引擎：${SUPERTONIC_ZH_ENGINE}"
  gray_echo "中文语音：${SUPERTONIC_ZH_VOICE:-自动选择}"
  gray_echo "中文语速：${SUPERTONIC_ZH_RATE}"
  gray_echo "主日志：${LOG_FILE}"
  gray_echo "服务日志：${SERVER_LOG}"
  highlight_echo "======================================================================="
  echo ""
}
# 封装 show_help 对应的独立处理逻辑。
show_help() {
  cat <<'EOF' | tee -a "$LOG_FILE" | jobs_prompt_filter
可用命令：
  直接输入文本        立即朗读，例如：fuck
  :lang en           切换语言，例如 en / ja / ko / es / na / auto
  :voice F1          切换声音，内置 M1-M5、F1-F5
  :speed 1.2         切换语速，建议 0.7-2.0
  :steps 10          切换质量步数，建议 5-12，越大越慢
  :list              查看官方支持的语言代码
  :docs              打开本地接口文档
  :config            查看当前配置
  :stop              停止本脚本启动的后台服务
  :quit              退出
EOF
}
# 封装 interactive_loop 对应的独立处理逻辑。
interactive_loop() {
  show_runtime_config
  show_help
  echo ""

  while true; do
    local input=""
    read -r "?$(jobs_prompt_render "🔊 请输入要朗读的文本（直接回车退出）： ")" input
    input="$(strip_outer_quotes "$input")"

    if [[ -z "$input" ]]; then
      success_echo "已退出朗读循环。"
      break
    fi

    case "$input" in
      ":quit"|":q"|":exit")
        success_echo "已退出朗读循环。"
        break
        ;;
      ":help")
        show_help
        ;;
      ":list")
        show_supported_languages
        ;;
      ":docs")
        open "${SERVER_URL}/docs"
        ;;
      ":config")
        show_runtime_config
        ;;
      ":stop")
        stop_started_server
        ;;
      ":lang "*)
        SUPERTONIC_LANG="${input#":lang "}"
        success_echo "语言已切换为：${SUPERTONIC_LANG}"
        ;;
      ":zh-engine "*)
        SUPERTONIC_ZH_ENGINE="${input#":zh-engine "}"
        success_echo "中文引擎已切换为：${SUPERTONIC_ZH_ENGINE}"
        ;;
      ":zh-voices")
        list_macos_chinese_voices
        ;;
      ":zh-voice "*)
        SUPERTONIC_ZH_VOICE="${input#":zh-voice "}"
        success_echo "中文语音已切换为：${SUPERTONIC_ZH_VOICE}"
        ;;
      ":zh-rate "*)
        SUPERTONIC_ZH_RATE="${input#":zh-rate "}"
        success_echo "中文语速已切换为：${SUPERTONIC_ZH_RATE}"
        ;;
      ":voice "*)
        SUPERTONIC_VOICE="${input#":voice "}"
        success_echo "声音已切换为：${SUPERTONIC_VOICE}"
        ;;
      ":speed "*)
        SUPERTONIC_SPEED="${input#":speed "}"
        success_echo "语速已切换为：${SUPERTONIC_SPEED}"
        ;;
      ":steps "*)
        SUPERTONIC_STEPS="${input#":steps "}"
        success_echo "步数已切换为：${SUPERTONIC_STEPS}"
        ;;
      *)
        speak_text "$input"
        ;;
    esac
    echo ""
  done
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
supertonic_main() {
  # 根据当前条件选择对应的执行分支。
  if [[ "$#" -gt 0 ]]; then
    # 检查当前步骤所需的环境、路径或输入条件。
    ensure_environment || exit 1
    # 执行当前流程中的独立业务步骤：start_server_if_needed。
    start_server_if_needed || exit 1
    # 执行当前流程中的独立业务步骤：speak_text。
    speak_text "$*"
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 展示脚本说明并等待用户确认影响范围。
  show_readme_and_wait
  # 检查当前步骤所需的环境、路径或输入条件。
  ensure_environment || exit 1
  # 执行当前流程中的独立业务步骤：start_server_if_needed。
  start_server_if_needed || exit 1
  # 执行当前流程中的独立业务步骤：interactive_loop。
  interactive_loop
}
# 封装 parse_engine_args 对应的独立处理逻辑。
parse_engine_args() {
  local next_is_engine="false"
  local cleaned=()
  local arg=""

  for arg in "$@"; do
    if [[ "$next_is_engine" == "true" ]]; then
      TTS_ENGINE="$arg"
      next_is_engine="false"
      continue
    fi

    case "$arg" in
      --engine)
        next_is_engine="true"
        ;;
      --engine=*)
        TTS_ENGINE="${arg#--engine=}"
        ;;
      --moss|--moss-tts|--moss-tts-nano)
        TTS_ENGINE="moss"
        ;;
      --voxcpm|--voxcpm2|--vox)
        TTS_ENGINE="voxcpm"
        ;;
      --supertonic)
        TTS_ENGINE="supertonic"
        ;;
      *)
        cleaned+=("$arg")
        ;;
    esac
  done

  printf '%s\n' "${cleaned[@]}"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- "Python 环境：确认后更新 Homebrew；缺失时选择安装路径，Python 不满足要求才修复。" | jobs_intro_style body
  print -r -- '脚本名称：【MacOS】tts.command' | jobs_intro_style title
  print -r -- '核心用途：执行“tts”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    exit 1
  fi
  jobs_list_intro_read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _ || exit 1
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  jobs_envtts_python_preflight || return 1 # 三个语音引擎共用兼容的 Homebrew Python。
  # 初始化当前流程后续步骤需要使用的变量。
  local parsed=""
  # 初始化当前流程后续步骤需要使用的变量。
  local engine=""
  # 初始化当前流程后续步骤需要使用的变量。
  local args=()

  # 初始化当前流程后续步骤需要使用的变量。
  parsed="$(parse_engine_args "$@")"
  # 根据当前条件选择对应的执行分支。
  if [[ -n "$parsed" ]]; then
    # 循环处理用户输入或当前批次中的全部目标。
    while IFS= read -r item; do
      # 执行当前流程中的独立业务步骤：处理当前语句。
      [[ -n "$item" ]] && args+=("$item")
    done <<< "$parsed"
  fi

  # 根据当前条件选择对应的执行分支。
  if ! select_tts_engine; then
    # 执行当前流程中的独立业务步骤：info_echo。
    info_echo "已取消 TTS 引擎选择。"
    # 执行当前流程中的独立业务步骤：return。
    return 0
  fi
  # 初始化当前流程后续步骤需要使用的变量。
  engine="$TTS_SELECTED_ENGINE"
  # 执行当前流程中的独立业务步骤：print_engine_banner。
  print_engine_banner "$engine"

  # 根据当前条件选择对应的执行分支。
  case "$engine" in
    # 执行当前流程中的独立业务步骤：moss。
    moss)
      # 执行当前流程中的独立业务步骤：moss_main。
      moss_main "${args[@]}"
      ;;
    # 执行当前流程中的独立业务步骤：voxcpm。
    voxcpm)
      # 执行当前流程中的独立业务步骤：voxcpm_main。
      voxcpm_main "${args[@]}"
      ;;
    # 执行当前流程中的独立业务步骤：supertonic。
    supertonic)
      # 执行当前流程中的独立业务步骤：supertonic_main。
      supertonic_main "${args[@]}"
      ;;
    # 执行当前流程中的独立业务步骤：处理当前语句。
    *)
      # 执行当前流程中的独立业务步骤：error_echo。
      error_echo "未知 TTS 引擎：${engine}"
      # 执行当前流程中的独立业务步骤：return。
      return 1
      ;;
  esac
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
# 入口失败在阶段内终止；source 业务继续使用可返回的预检函数。
jobs_envtts_python_prepare_runtime() {
  jobs_envtts_python_preflight confirmed || exit 1
}


main() {
  show_script_intro_and_wait || return $? # 先展示用途并确认环境准备。
  jobs_envtts_python_prepare_runtime # 当前进程统一选择兼容运行时。
  initialize_script_runtime # 初始化 Shell 选项、日志、依赖和入口运行状态。
  run_main_business_flow "$@" # 执行入口下沉后的完整业务流程。
}

main "$@"
