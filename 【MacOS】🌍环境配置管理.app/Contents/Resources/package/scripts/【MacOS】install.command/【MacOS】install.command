#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】install.command
# - 核心用途：执行“install”对应的自动化任务。
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



# ============================================================
# 【MacOS】install.command - macOS 新系统配置（fzf 菜单版）
# ============================================================
# 说明：
# 1. 适合 .command 双击运行，也可终端执行。
# 2. 启动后先显示内置 README，并等待回车确认。
# 3. 菜单使用 fzf 多选；如果新系统没有 fzf，会先提示安装 Homebrew / fzf。
# 4. 每个被选择的部件都会先自检：不存在就安装最新，存在就更新。
# 5. 第三方依赖已存在时，会统一确认一次是否升级，不再逐项询问。
# 6. 其他安装 / 更新动作执行前会强提示：回车执行，任意字符 + 回车跳过。
# 7. 注意：install 这个命令名与系统 /usr/bin/install 存在冲突风险。
# ============================================================

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
source "${SCRIPT_DIR:h}/_lib/【MacOS】FlutterSDK网络入口.zsh/【MacOS】FlutterSDK网络入口.zsh"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

# ---------- 全局状态 ----------
TOTAL_STAGES=0
CURRENT_STAGE=0
THIRD_PARTY_EXISTING_UPGRADE_CONFIRMED=""
readonly ALL_MENU_ITEM="✅ 全选安装"

readonly JOBS_SOFTWARE_REPO="https://github.com/JobsKits/JobsSoftware.MacOS.git"
readonly JOBS_ENV_REPO="https://github.com/JobsKits/JobsMacEnvVarConfig.git"
readonly JOBS_WORKSPACE="${HOME}/Desktop/JobsKits"

# ---------- Homebrew 第三方配置 ----------
# 只维护第三方名称即可。
# 例如：需要安装 brew install git-lfs，就写 git-lfs。
# 例如：需要安装 brew install --cask vlc，就写 vlc。
readonly -a BREW_CASKS=(
  hammerspoon
  flutter
  trex
  vlc
  jdownloader
  codex-app # 图形化界面
  codex # 终端使用
  github-store
  jtool2
  motrix
  onlyoffice
  pot
  qlcolorcode
  temurin@17
)

readonly -a BREW_FORMULAE=(
  agg
  asciinema
  caddy
  cloudflared
  git-lfs
  gh
  nushell
  rbenv
  ruby
  node
  jenv
  openjdk
  openjdk@17
  openjdk@21
  fvm
  pnpm
  python
  python3
  python-tk@3.14
  pyinstaller
  pyside
  cocoapods
  fastlane
  mysql
  hugo
  yt-dlp
  ffmpeg
  cmake
  graphviz
  sevenzip
  go-task
  uv
  fzf
  glow
  lazygit
  dufs
  git-filter-repo
  nginx
  radare2
)
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
# ---------- 通用基础函数 ----------
print_divider() {
  gray_echo "------------------------------------------------------------------------"
}
# 封装 pause_for_enter 对应的独立处理逻辑。
pause_for_enter() {
  local prompt="${1:-👉 请按回车继续，或按 Ctrl+C 取消...}"
  if [[ -t 0 && "${JOBS_MAC_ENV_SKIP_README:-}" != "1" ]]; then
    echo ""
    local answer=""
    read "answer?$(jobs_prompt_render "${prompt}")"
  fi
}
# 收集并校验用户输入，决定后续执行路径。
confirm_execute() {
  local title="$1"
  local action_word="${2:-执行}"

  echo ""
  warn_echo "强提示：${title}"
  jobs_prompt_output warm_echo "回车=${action_word}；输入任意字符后回车=跳过"

  if [[ ! -t 0 ]]; then
    warn_echo "当前不是交互式终端，已跳过：${title}"
    return 1
  fi

  local answer=""
  read "answer?$(jobs_prompt_render "> ")"

  if [[ -z "${answer}" ]]; then
    return 0
  fi

  warn_echo "已跳过：${title}"
  return 1
}
# 收集并校验用户输入，决定后续执行路径。
confirm_existing_third_party_upgrade_once() {
  if [[ "${THIRD_PARTY_EXISTING_UPGRADE_CONFIRMED}" == "1" ]]; then
    return 0
  fi

  if [[ "${THIRD_PARTY_EXISTING_UPGRADE_CONFIRMED}" == "0" ]]; then
    return 1
  fi

  if confirm_execute "已检测到部分第三方依赖已存在，是否统一升级已存在的 brew cask / brew formula / npm 全局包 / gem 包？" "统一升级"; then
    THIRD_PARTY_EXISTING_UPGRADE_CONFIRMED="1"
    success_echo "本轮已存在第三方依赖将统一执行升级，后续不再逐项询问。"
    return 0
  fi

  THIRD_PARTY_EXISTING_UPGRADE_CONFIRMED="0"
  warn_echo "本轮已存在第三方依赖将统一跳过升级，后续不再逐项询问。"
  return 1
}
# 封装 progress_step 对应的独立处理逻辑。
progress_step() {
  local step_name="$1"
  CURRENT_STAGE=$((CURRENT_STAGE + 1))
  echo ""

  if (( TOTAL_STAGES > 0 )); then
    highlight_echo "当前系统配置进度：${CURRENT_STAGE}/${TOTAL_STAGES} 👉 ${step_name}"
  else
    highlight_echo "当前系统配置 👉 ${step_name}"
  fi

  print_divider
}
# 执行已经拆分完成的独立业务步骤。
run_cmd() {
  local desc="$1"
  shift

  note_echo "${desc}"
  debug_echo "执行命令：$*"

  "$@"
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    success_echo "${desc}：完成"
  else
    error_echo "${desc}：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 执行已经拆分完成的独立业务步骤。
run_sh() {
  local desc="$1"
  local cmd="$2"

  note_echo "${desc}"
  debug_echo "执行命令：${cmd}"

  /bin/zsh -c "${cmd}"
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    success_echo "${desc}：完成"
  else
    error_echo "${desc}：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 封装 require_command 对应的独立处理逻辑。
require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1
}
# 执行 Flutter doctor，并在检测到 Android license 未确认时引导接受许可。
run_flutter_doctor_and_android_licenses() {
  local label="$1"
  shift

  local -a flutter_base_cmd=("$@")
  if (( ${#flutter_base_cmd[@]} == 0 )); then
    warn_echo "未提供 Flutter 命令，跳过 Flutter doctor。"
    return 0
  fi

  hash -r 2>/dev/null || true

  local command_name="${flutter_base_cmd[1]}"
  if ! require_command "${command_name}" && [[ ! -x "${command_name}" ]]; then
    warn_echo "未检测到 ${command_name}，跳过 ${label} doctor。"
    return 0
  fi

  local doctor_output_file=""
  doctor_output_file="$(mktemp -t jobs_install_flutter_doctor.XXXXXX)"
  local -a doctor_cmd=("${flutter_base_cmd[@]}" doctor -v)
  local -a license_cmd=("${flutter_base_cmd[@]}" doctor --android-licenses)

  note_echo "${label} doctor -v"
  debug_echo "执行命令：${doctor_cmd[*]}"
  "${doctor_cmd[@]}" 2>&1 | tee -a "$LOG_FILE" | tee "$doctor_output_file"
  local doctor_exit_code=${pipestatus[1]}

  if (( doctor_exit_code == 0 )); then
    success_echo "${label} doctor -v：完成"
  else
    warn_echo "${label} doctor -v：返回非 0（${doctor_exit_code}），继续检查 Android license 提示。"
  fi

  if grep -Eq "Android license status unknown|flutter doctor --android-licenses" "$doctor_output_file"; then
    warn_echo "检测到 Android license status unknown，将执行：${license_cmd[*]}"

    if grep -Fq "cmdline-tools component is missing" "$doctor_output_file"; then
      warm_echo "doctor 同时提示 Android cmdline-tools 缺失；若许可接受失败，请先在 Android Studio 安装 Command-line Tools。"
    fi

    if [[ -t 0 ]]; then
      run_cmd "接受 Android SDK licenses" "${license_cmd[@]}" || true
    else
      warn_echo "当前不是交互式终端，已跳过 Android SDK licenses 接受步骤。"
    fi
  fi

  rm -f "$doctor_output_file"
  return 0
}
# 解析并返回后续流程需要的目标信息。
get_node_major_version() {
  if ! require_command node; then
    echo "0"
    return 0
  fi

  local version=""
  version="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
  [[ -n "${version}" ]] && echo "${version}" || echo "0"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_node_for_opencli() {
  local major=""
  major="$(get_node_major_version)"

  if (( major >= 21 )); then
    success_echo "Node.js 版本满足 OpenCLI 要求：$(node --version)"
    return 0
  fi

  warn_echo "OpenCLI 需要 Node.js >= 21，当前版本：$(node --version 2>/dev/null || echo '未安装')"

  if require_command brew; then
    run_cmd "通过 Homebrew 安装 / 升级 node" brew upgrade node || run_cmd "通过 Homebrew 安装 node" brew install node
    hash -r 2>/dev/null || true
    major="$(get_node_major_version)"
  fi

  if (( major >= 21 )); then
    success_echo "Node.js 已满足 OpenCLI 要求：$(node --version)"
    return 0
  fi

  error_echo "Node.js 仍低于 21，跳过 OpenCLI 安装。请先升级 Node.js 后重试。"
  return 1
}
# 解析并返回后续流程需要的目标信息。
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 检查当前运行条件是否满足后续流程要求。
check_url_access() {
  local url="$1"
  curl -I -L -s --connect-timeout 8 --max-time 15 "${url}" >/dev/null 2>&1
}
# 封装 append_once 对应的独立处理逻辑。
append_once() {
  local line="$1"
  local file="${2:-$HOME/.zshrc}"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -Fqx "$line" "$file"; then
    return 0
  fi

  echo "" >> "$file"
  echo "$line" >> "$file"
}
# 封装 append_comment_once 对应的独立处理逻辑。
append_comment_once() {
  local comment="$1"
  local file="$2"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -Fqx "$comment" "$file"; then
    return 0
  fi

  echo "" >> "$file"
  echo "$comment" >> "$file"
}
# 解析并返回后续流程需要的目标信息。
find_brew_bin() {
  jobs_brew_find
}
# 解析并返回后续流程需要的目标信息。
find_fzf_bin() {
  if command -v fzf >/dev/null 2>&1; then
    command -v fzf
    return 0
  fi

  local candidate
  for candidate in \
    /opt/homebrew/bin/fzf \
    /usr/local/bin/fzf \
    /opt/homebrew/opt/fzf/bin/fzf \
    /usr/local/opt/fzf/bin/fzf; do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  return 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_raw_github_access_or_exit() {
  info_echo "开始检查 raw.githubusercontent.com 网络连通性..."

  if check_url_access "https://raw.githubusercontent.com"; then
    success_echo "raw.githubusercontent.com 网络访问正常"
    return 0
  fi

  error_echo "当前无法访问 raw.githubusercontent.com。Homebrew / Oh My Zsh 安装大概率会失败。"
  warm_echo "请先处理网络问题，再重新运行脚本。"
  pause_for_enter "$(jobs_prompt_render "👉 网络未就绪。请按回车结束脚本...")"
  exit 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_github_access_or_exit() {
  info_echo "开始检查 GitHub 网络连通性..."

  if check_url_access "https://github.com"; then
    success_echo "GitHub 网络访问正常"
    return 0
  fi

  error_echo "当前无法访问 GitHub。Jobs 仓库拉取会失败。"
  warm_echo "请先处理网络问题，再重新运行脚本。"
  pause_for_enter "$(jobs_prompt_render "👉 GitHub 不可访问。请按回车结束脚本...")"
  exit 1
}
# 执行对应的环境配置或同步处理。
setup_brew_shellenv() {
  local jobs_existing_brew=""
  if jobs_existing_brew="$(jobs_brew_find)"; then
    JOBS_HOMEBREW_BIN="$jobs_existing_brew"
    jobs_brew_activate || return 1
  fi
  local brew_bin="$1"
  local shellenv_line="eval \"\$(${brew_bin} shellenv)\""

  if [[ ! -x "${brew_bin}" ]]; then
    error_echo "Homebrew 可执行文件不存在或不可执行：${brew_bin}"
    return 1
  fi

  local target_file
  for target_file in "${HOME}/.zprofile" "${HOME}/.zshrc"; do
    append_comment_once "# Homebrew shellenv" "${target_file}"
    append_once "${shellenv_line}" "${target_file}"
    success_echo "已确认 Homebrew 环境变量配置：${target_file}"
  done

  eval "$(${brew_bin} shellenv)"
  hash -r 2>/dev/null || true
}
# 执行对应的环境配置或同步处理。
setup_fzf_shellenv() {
  if ! require_command brew; then
    return 0
  fi

  local fzf_base
  fzf_base="$(brew --prefix fzf 2>/dev/null)"

  if [[ -n "${fzf_base}" && -d "${fzf_base}" ]]; then
    append_comment_once "# fzf" "${HOME}/.zshrc"
    append_once '[ -f "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh" ] && source "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"' "${HOME}/.zshrc"
    append_once '[ -f "$(brew --prefix)/opt/fzf/shell/completion.zsh" ] && source "$(brew --prefix)/opt/fzf/shell/completion.zsh"' "${HOME}/.zshrc"
    success_echo "已确认 fzf shell 配置：${HOME}/.zshrc"
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_jenv_init() {
  append_comment_once "# jenv" "${HOME}/.zshrc"
  append_once 'export PATH="$HOME/.jenv/bin:$PATH"' "${HOME}/.zshrc"
  append_once 'eval "$(jenv init -)"' "${HOME}/.zshrc"
  success_echo "已确认 jenv 初始化配置：${HOME}/.zshrc"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_rbenv_init() {
  append_comment_once "# rbenv" "${HOME}/.zshrc"
  append_once 'eval "$(rbenv init - zsh)"' "${HOME}/.zshrc"
  success_echo "已确认 rbenv 初始化配置：${HOME}/.zshrc"
}
# 封装 post_openjdk_hint 对应的独立处理逻辑。
post_openjdk_hint() {
  warm_echo "openjdk 安装 / 更新完成后，如需让系统 java 指向 Homebrew openjdk，可按需执行："
  warm_echo '  sudo ln -sfn "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk.jdk'
  warm_echo "如果使用 jenv 管理 Java，推荐执行："
  warm_echo '  jenv add "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk/Contents/Home"'
}
# ---------- 内置自述 ----------
jobs_install_show_readme_and_wait() {
  clear 2>/dev/null || true

  {
    cat <<'EOFREADME' | jobs_intro_style auto | jobs_prompt_filter
============================================================
【MacOS】install.command - macOS 新系统配置（fzf 菜单版）
============================================================

这是 【MacOS】install.command 的内置自述，不读取同级 README.md。

核心原则：
  1. 不再一股脑安装。
  2. 启动后使用 fzf 输出多选菜单。
  3. 菜单额外提供“✅ 全选安装”。
  4. 每个部件都会先自检：
     - 不存在：安装最新版
     - 已存在：更新到最新版 / 刷新配置
  5. 第三方依赖已存在时统一确认一次是否升级，不再逐项询问：
     - brew cask
     - brew formula
     - npm 全局包
     - gem 包
  6. 其他安装 / 更新动作执行前都会强提示：
     - 直接回车：执行安装 / 更新
     - 输入任意字符后回车：跳过

Homebrew 第三方配置：
  - brew cask 只需要维护脚本顶部 BREW_CASKS 数组里的第三方名称。
  - brew formula 只需要维护脚本顶部 BREW_FORMULAE 数组里的第三方名称。
  - 菜单项会自动根据这两个数组生成。
  - 执行时会自动拼出 brew install / brew install --cask 命令。
  - 少数需要 tap / 后置初始化的 cask / formula，会由脚本内部自动处理，不需要写在数组里。

当前 BREW_CASKS：
EOFREADME

    local pkg
    for pkg in "${BREW_CASKS[@]}"; do
      echo "  - ${pkg}" | jobs_intro_style body
    done

    cat <<'EOFREADME' | jobs_intro_style auto | jobs_prompt_filter

当前 BREW_FORMULAE：
EOFREADME

    for pkg in "${BREW_FORMULAE[@]}"; do
      echo "  - ${pkg}" | jobs_intro_style body
    done

    cat <<'EOFREADME' | jobs_intro_style auto | jobs_prompt_filter

将支持选择的部件（菜单从上到下按此顺序显示）：
  - ✅ 全选安装
  - Xcode Command Line Tools
  - Xcode iOS 平台组件
  - Oh My Zsh
  - Homebrew
  - brew cask：由 BREW_CASKS 自动生成
  - brew formula：由 BREW_FORMULAE 自动生成
  - Rosetta 2
  - npm 全局包：quicktype
  - npm 全局包：OpenCLI
  - npm 全局包：CodeGraph
  - gem 包：cocoapods
  - Git LFS 初始化与大文件参数
  - JobsKits 仓库：JobsSoftware.MacOS、JobsMacEnvVarConfig
  - 手动下载页：VS Code、Android Studio、Python

启动菜单前置依赖：
  - 菜单依赖 fzf。
  - 如果 Homebrew / fzf 不存在，脚本会先提示你安装。
  - 这是为了让后续功能选择能够正常显示，不代表进入了全量安装。

说明：
  - 该命令名与系统 /usr/bin/install 有冲突风险。
  - 日志路径：/tmp/install.log
  - 部分步骤依赖 GitHub / raw.githubusercontent.com。
  - 部分 sudo 步骤可能要求输入系统密码。
  - 本脚本不会递归执行 JobsMacEnvVarConfig/【MacOS】install.command，避免自调用死循环。
============================================================
EOFREADME
  } | jobs_intro_style auto

  if [[ "${JOBS_LIST_PARENT_MENU:-}" == list ]]; then
    jobs_list_intro_read -r _answer
  else
    pause_for_enter "$(jobs_prompt_render "👉 请确认没有误操作。按回车进入菜单准备流程，或按 Ctrl+C 取消...")"
  fi
}
# ---------- 菜单前置依赖：Homebrew / fzf ----------
install_homebrew_without_menu() {
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_install_or_exit
    return 0
  fi
  ensure_raw_github_access_or_exit

  if ! confirm_execute "菜单依赖 Homebrew，当前未检测到 Homebrew，是否安装 Homebrew？" "安装"; then
    error_echo "没有 Homebrew 无法自动安装 fzf，也无法进入 fzf 菜单。"
    pause_for_enter "$(jobs_prompt_render "👉 请按回车退出...")"
    exit 1
  fi

  jobs_brew_install_or_exit

  local brew_bin=""
  if brew_bin="$(find_brew_bin)"; then
    setup_brew_shellenv "${brew_bin}" || return 1
  else
    error_echo "Homebrew 安装后仍未检测到 brew 命令，无法继续。"
    pause_for_enter "$(jobs_prompt_render "👉 请按回车退出...")"
    exit 1
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_brew_for_menu() {
  local brew_bin=""

  if brew_bin="$(find_brew_bin)"; then
    setup_brew_shellenv "${brew_bin}" || return 1
    return 0
  fi

  install_homebrew_without_menu
}
# 检查当前运行条件是否满足后续流程要求。
ensure_fzf_for_menu() {
  local fzf_bin=""

  if fzf_bin="$(find_fzf_bin)"; then
    success_echo "fzf 已存在：${fzf_bin}"
    return 0
  fi

  if ! require_command brew; then
    error_echo "brew 不存在，无法安装 fzf。"
    pause_for_enter "$(jobs_prompt_render "👉 请按回车退出...")"
    exit 1
  fi

  if ! confirm_execute "菜单依赖 fzf，当前未检测到 fzf，是否安装 fzf？" "安装"; then
    error_echo "没有 fzf 无法显示选择菜单。"
    pause_for_enter "$(jobs_prompt_render "👉 请按回车退出...")"
    exit 1
  fi

  run_cmd "安装 fzf" brew install fzf
  setup_fzf_shellenv

  if fzf_bin="$(find_fzf_bin)"; then
    success_echo "fzf 安装完成：${fzf_bin}"
    return 0
  fi

  error_echo "fzf 安装后仍未检测到可执行文件，无法继续。"
  pause_for_enter "$(jobs_prompt_render "👉 请按回车退出...")"
  exit 1
}
# 封装 prepare_menu_runtime 对应的独立处理逻辑。
prepare_menu_runtime() {
  highlight_echo "准备 fzf 菜单运行环境"
  print_divider

  ensure_brew_for_menu || return 1
  ensure_fzf_for_menu || return 1
}
# ---------- Homebrew 自检 ----------
require_brew_or_skip() {
  local brew_bin=""

  if brew_bin="$(find_brew_bin)"; then
    setup_brew_shellenv "${brew_bin}" || return 1
    return 0
  fi

  warn_echo "brew 不存在，当前部件无法继续。请先选择 Homebrew。"
  return 1
}
# 封装 brew_formula_installed 对应的独立处理逻辑。
brew_formula_installed() {
  local pkg="$1"
  brew list --formula --versions "${pkg}" >/dev/null 2>&1
}
# 封装 brew_cask_installed 对应的独立处理逻辑。
brew_cask_installed() {
  local pkg="$1"
  brew list --cask --versions "${pkg}" >/dev/null 2>&1
}
# 封装 brew_cask_local_app_path 对应的独立处理逻辑。
brew_cask_local_app_path() {
  local pkg="$1"

  case "${pkg}" in
    vlc) echo "/Applications/VLC.app" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_cask_local_app_exists 对应的独立处理逻辑。
brew_cask_local_app_exists() {
  local pkg="$1"
  local app_path=""

  app_path="$(brew_cask_local_app_path "${pkg}")"
  [[ -n "${app_path}" && -d "${app_path}" ]]
}
# ---------- 部件：Xcode Command Line Tools ----------
component_clt() {
  progress_step "Xcode Command Line Tools"

  if xcode-select -p >/dev/null 2>&1; then
    success_echo "Xcode Command Line Tools 已存在：$(xcode-select -p)"

    if confirm_execute "CLT 已存在，是否执行 Xcode License 接受，并通过 softwareupdate 安装可用更新？" "更新"; then
      if require_command xcodebuild; then
        run_cmd "接受 Xcode License" sudo xcodebuild -license accept
      else
        warn_echo "未检测到 xcodebuild，跳过 Xcode License 接受步骤"
      fi

      warn_echo "softwareupdate --install --all 可能安装系统可用更新，请确认你已经理解。"
      run_cmd "安装 macOS 可用软件更新" sudo softwareupdate --install --all
    fi

    return 0
  fi

  if confirm_execute "未检测到 Xcode Command Line Tools，是否安装？" "安装"; then
    run_cmd "安装 Xcode Command Line Tools" xcode-select --install
    warn_echo "如果系统弹出图形安装窗口，请完成安装后再次执行本脚本。"
  fi
}
# ---------- 部件：Xcode iOS 平台组件 ----------
component_xcode_ios_platform() {
  progress_step "Xcode iOS 平台组件"

  if ! require_command xcodebuild; then
    warn_echo "未检测到 xcodebuild，无法下载 iOS 平台组件。请先安装 Xcode / Command Line Tools。"
    return 0
  fi

  local action_word="安装"
  local desc="下载 Xcode iOS 平台组件"

  if xcodebuild -showsdks 2>/dev/null | grep -E "iphoneos|iphonesimulator" >/dev/null 2>&1; then
    action_word="更新"
    desc="检测到 iOS SDK，是否重新下载 / 更新 Xcode iOS 平台组件？"
  else
    desc="未检测到 iOS SDK，是否下载 Xcode iOS 平台组件？"
  fi

  if confirm_execute "${desc}" "${action_word}"; then
    run_sh "删除 Xcode 缓存" 'rm -rf ~/Library/Caches/com.apple.dt.Xcode'
    run_sh "删除 CoreSimulator 缓存" 'rm -rf ~/Library/Developer/CoreSimulator/Caches'
    run_cmd "下载 / 更新 iOS 模拟器平台" xcodebuild -downloadPlatform iOS -verbose
  fi
}
# ---------- 部件：Oh My Zsh ----------
# 下载成功且语法有效才执行；保留现有 .zshrc，不改变登录 Shell。
jobs_install_ohmyzsh() (
  local installer=""
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-ohmyzsh-install.XXXXXXXX")" || return 1
  trap 'rm -f -- "$installer"' EXIT
  curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 10 --max-time 120 --output "$installer" \
    https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh || return 1
  [[ -s "$installer" ]] || return 1
  /bin/sh -n "$installer" || return 1
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes /bin/sh "$installer"
)
component_oh_my_zsh() {
  progress_step "Oh My Zsh"

  ensure_raw_github_access_or_exit

  if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    success_echo "Oh My Zsh 已存在：${HOME}/.oh-my-zsh"

    if confirm_execute "Oh My Zsh 已存在，是否更新？" "更新"; then
      if [[ -f "${HOME}/.oh-my-zsh/tools/upgrade.sh" ]]; then
        run_sh "更新 Oh My Zsh" "ZSH='${HOME}/.oh-my-zsh' '${HOME}/.oh-my-zsh/tools/upgrade.sh'"
      else
        warn_echo "未找到 Oh My Zsh upgrade.sh，跳过更新"
      fi
    fi

    return 0
  fi

  if confirm_execute "未检测到 Oh My Zsh，是否安装？" "安装"; then
    run_cmd "安装 Oh My Zsh" jobs_install_ohmyzsh || return 1
    warn_echo "Oh My Zsh 官方安装流程可能有交互输出，这是正常现象。"
  fi
}
# ---------- 部件：Homebrew ----------
component_homebrew() {
  progress_step "Homebrew"

  local brew_bin=""

  if brew_bin="$(find_brew_bin)"; then
    setup_brew_shellenv "${brew_bin}" || return 1
    success_echo "Homebrew 已存在：${brew_bin}"

    if confirm_execute "Homebrew 已存在，是否执行 update / upgrade / cleanup / doctor？" "更新"; then
      run_cmd "brew update（更新软件列表）" brew update
      run_cmd "brew upgrade（升级已安装软件）" brew upgrade
      run_cmd "brew cleanup（清理旧版本缓存）" brew cleanup
      run_cmd "brew doctor（检查 Homebrew 健康状态）" brew doctor
      run_cmd "brew -v（输出 Homebrew 版本）" brew -v
    fi

    return 0
  fi

  if confirm_execute "未检测到 Homebrew，是否安装？" "安装"; then
    install_homebrew_without_menu
  fi
}
# ---------- 部件：Rosetta 2 ----------
component_rosetta() {
  progress_step "Rosetta 2"

  if [[ "$(uname -m)" != "arm64" ]]; then
    info_echo "当前不是 Apple Silicon，跳过 Rosetta 2"
    return 0
  fi

  if /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    success_echo "Rosetta 2 已存在。Rosetta 属于系统组件，通常随系统更新维护，不单独执行更新。"
    return 0
  fi

  if confirm_execute "未检测到 Rosetta 2，是否安装？" "安装"; then
    run_cmd "安装 Rosetta 2" /usr/sbin/softwareupdate --install-rosetta --agree-to-license
  fi
}
# ---------- 部件：brew formula ----------
brew_formula_install_arg() {
  local formula_name="$1"

  case "${formula_name}" in
    go-task) echo "go-task/tap/go-task" ;;
    *) echo "${formula_name}" ;;
  esac
}
# 封装 brew_formula_tap_name 对应的独立处理逻辑。
brew_formula_tap_name() {
  local formula_name="$1"

  case "${formula_name}" in
    fvm) echo "leoafarias/fvm" ;;
    go-task) echo "go-task/tap" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_formula_after_install 对应的独立处理逻辑。
brew_formula_after_install() {
  local formula_name="$1"

  case "${formula_name}" in
    rbenv) ensure_rbenv_init ;;
    jenv) ensure_jenv_init ;;
    openjdk|openjdk@17) post_openjdk_hint ;;
    fzf) setup_fzf_shellenv ;;
    *) return 0 ;;
  esac
}
# 封装 component_brew_formula 对应的独立处理逻辑。
component_brew_formula() {
  local formula_name="$1"
  local install_arg=""
  local tap_name=""

  install_arg="$(brew_formula_install_arg "${formula_name}")"
  tap_name="$(brew_formula_tap_name "${formula_name}")"

  progress_step "brew formula：${formula_name}"

  if ! require_brew_or_skip; then
    return 0
  fi

  local installed=0
  local desc="未检测到 brew formula：${formula_name}，是否安装最新版？"

  if brew_formula_installed "${formula_name}"; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 brew formula：${formula_name}"
      return 0
    fi
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if [[ -n "${tap_name}" ]]; then
    run_cmd "确认 Homebrew Tap：${tap_name}" brew tap "${tap_name}"
  fi

  if (( installed )); then
    run_cmd "更新 brew formula：${formula_name}" brew upgrade "${install_arg}"
  else
    run_cmd "安装 brew formula：${formula_name}" brew install "${install_arg}"
  fi

  brew_formula_after_install "${formula_name}"
}
# ---------- 部件：brew cask ----------
brew_cask_tap_name() {
  local cask_name="$1"

  case "${cask_name}" in
    github-store) echo "OpenHub-Store/tap" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_cask_after_install 对应的独立处理逻辑。
brew_cask_after_install() {
  local cask_name="$1"

  case "${cask_name}" in
    flutter)
      jobs_flutter_sdk_command flutter --version >/dev/null || return $?
      run_flutter_doctor_and_android_licenses "Flutter" flutter
      ;;
    github-store)
      local app_path="/Applications/GitHub-Store.app"

      if [[ -d "${app_path}" ]]; then
        run_cmd "移除 GitHub-Store Gatekeeper 隔离属性" xattr -dr com.apple.quarantine "${app_path}"
      else
        warn_echo "未找到 ${app_path}，跳过 GitHub-Store 去隔离。若使用了自定义 --appdir，请手动执行 xattr。"
      fi
      ;;
    *) return 0 ;;
  esac
}
# 封装 component_brew_cask 对应的独立处理逻辑。
component_brew_cask() {
  local cask_name="$1"
  local tap_name=""

  tap_name="$(brew_cask_tap_name "${cask_name}")"

  progress_step "brew cask：${cask_name}"

  if ! require_brew_or_skip; then
    return 0
  fi

  local installed=0
  local desc="未检测到 brew cask：${cask_name}，是否安装最新版？"

  if brew_cask_installed "${cask_name}"; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 brew cask：${cask_name}"
      return 0
    fi
  elif brew_cask_local_app_exists "${cask_name}"; then
    local app_path=""
    app_path="$(brew_cask_local_app_path "${cask_name}")"
    success_echo "已检测到本机 App：${app_path}"
    warn_echo "Homebrew 未登记 brew cask：${cask_name}，但本机已有 App，跳过重复安装。"
    return 0
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if [[ -n "${tap_name}" ]]; then
    run_cmd "确认 Homebrew Tap：${tap_name}" brew tap "${tap_name}"
  fi

  local brew_exit_code=0

  if [[ "$cask_name" == flutter ]]; then
    local operation=install
    (( ! installed )) || operation=upgrade
    run_cmd "Flutter cask：${operation}（探测Brew原始制品）" jobs_flutter_sdk_command --brew-cask "$(command -v brew)" "$operation"
    brew_exit_code=$?
  elif (( installed )); then
    run_cmd "更新 brew cask：${cask_name}" brew upgrade --cask "${cask_name}"
    brew_exit_code=$?
  else
    run_cmd "安装 brew cask：${cask_name}" brew install --cask "${cask_name}"
    brew_exit_code=$?
  fi

  if [[ ${brew_exit_code} -eq 0 ]]; then
    brew_cask_after_install "${cask_name}"
  else
    warn_echo "brew cask：${cask_name} 安装 / 更新失败，跳过后置处理。"
    [[ "$cask_name" != flutter ]] || return "$brew_exit_code"
  fi
}
# ---------- 部件：npm quicktype ----------
component_npm_quicktype() {
  progress_step "npm 全局包：quicktype"

  if ! require_command npm; then
    warn_echo "npm 不存在，无法安装 quicktype。请先选择 brew formula：node。"
    return 0
  fi

  local installed=0
  local desc="未检测到 npm 全局包 quicktype，是否安装？"

  if npm list -g quicktype --depth=0 >/dev/null 2>&1; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 npm 全局包：quicktype"
      return 0
    fi
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if (( installed )); then
    run_cmd "更新 npm 全局包 quicktype" sudo npm update -g quicktype
  else
    run_cmd "安装 npm 全局包 quicktype" sudo npm install -g quicktype
  fi
}
# ---------- 部件：npm OpenCLI ----------
component_npm_opencli() {
  progress_step "npm 全局包：OpenCLI"

  if ! require_command npm; then
    warn_echo "npm 不存在，无法安装 OpenCLI。请先选择 brew formula：node。"
    return 0
  fi

  if ! ensure_node_for_opencli; then
    return 0
  fi

  local installed=0
  local desc="未检测到 npm 全局包 OpenCLI，是否安装？"

  if npm list -g @jackwener/opencli --depth=0 >/dev/null 2>&1; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 npm 全局包：OpenCLI"
      return 0
    fi
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if (( installed )); then
    run_cmd "更新 npm 全局包 OpenCLI" sudo npm install -g @jackwener/opencli@latest
  else
    run_cmd "安装 npm 全局包 OpenCLI" sudo npm install -g @jackwener/opencli@latest
  fi

  if require_command opencli; then
    run_cmd "输出 OpenCLI 版本" opencli --version
    warm_echo "OpenCLI 浏览器自动化还需要手动安装 Browser Bridge 扩展，安装后可执行：opencli doctor"
  else
    warn_echo "npm 安装完成后当前 PATH 仍找不到 opencli，建议重新打开终端或检查 npm global bin。"
  fi
}
# ---------- 部件：npm CodeGraph ----------
component_npm_codegraph() {
  progress_step "npm 全局包：CodeGraph"

  if ! require_command npm; then
    warn_echo "npm 不存在，无法安装 CodeGraph。请先选择 brew formula：node。"
    return 0
  fi

  local installed=0
  local desc="未检测到 npm 全局包 CodeGraph，是否安装？"

  if npm list -g @colbymchenry/codegraph --depth=0 >/dev/null 2>&1; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 npm 全局包：CodeGraph"
      return 0
    fi
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if (( installed )); then
    run_cmd "更新 npm 全局包 CodeGraph" npm i -g @colbymchenry/codegraph
  else
    run_cmd "安装 npm 全局包 CodeGraph" npm i -g @colbymchenry/codegraph
  fi

  if require_command codegraph; then
    run_cmd "输出 CodeGraph 版本" codegraph --version
    warm_echo "CodeGraph 全局命令已安装。进入具体项目后，可按需执行：codegraph init -i"
  else
    warn_echo "npm 安装完成后当前 PATH 仍找不到 codegraph，建议重新打开终端或检查 npm global bin。"
  fi
}
# ---------- 部件：gem cocoapods ----------
component_gem_cocoapods() {
  progress_step "gem 包：cocoapods"

  if ! require_command gem; then
    warn_echo "gem 不存在，无法安装 cocoapods。请先确认 Ruby 环境。"
    return 0
  fi

  local installed=0
  local desc="未检测到 gem 包 cocoapods，是否安装？"

  if gem list -i cocoapods >/dev/null 2>&1; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 gem 包：cocoapods"
      return 0
    fi
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if (( installed )); then
    run_cmd "更新 gem 包 cocoapods" sudo gem update cocoapods
  else
    run_cmd "安装 gem 包 cocoapods" sudo gem install cocoapods
  fi
}
# ---------- 部件：Git LFS 初始化 ----------
component_git_lfs_init() {
  progress_step "Git LFS 初始化"

  if ! require_command git; then
    warn_echo "git 不存在，无法初始化 Git LFS。请先安装 Xcode Command Line Tools 或 git。"
    return 0
  fi

  if ! git lfs version >/dev/null 2>&1; then
    warn_echo "git-lfs 不存在，无法初始化。请先选择 brew formula：git-lfs。"
    return 0
  fi

  if confirm_execute "是否初始化 / 刷新 Git LFS 与大文件传输参数？" "执行"; then
    run_cmd "初始化 Git LFS" git lfs install
    run_cmd "配置 Git core.compression=0" git config --global core.compression 0
    run_cmd "配置 Git http.postBuffer=524288000" git config --global http.postBuffer 524288000
  fi
}
# ---------- 部件：JobsKits 仓库 ----------
clone_or_update_repo() {
  local repo_name="$1"
  local repo_url="$2"
  local target_dir="$3"

  if [[ -d "${target_dir}/.git" ]]; then
    success_echo "仓库已存在：${target_dir}"

    if confirm_execute "${repo_name} 已存在，是否执行 git pull 更新？" "更新"; then
      run_sh "更新仓库：${repo_name}" "cd '${target_dir}' && git pull --ff-only"
    fi

    return 0
  fi

  if confirm_execute "未检测到仓库 ${repo_name}，是否克隆到 ${target_dir}？" "安装"; then
    run_sh "创建 JobsKits 工作目录" "mkdir -p '${JOBS_WORKSPACE}'"
    run_sh "克隆仓库：${repo_name}" "git clone '${repo_url}' '${target_dir}'"
  fi
}
# 封装 component_jobs_repos 对应的独立处理逻辑。
component_jobs_repos() {
  progress_step "JobsKits 仓库"

  ensure_github_access_or_exit

  if ! require_command git; then
    warn_echo "git 不存在，跳过 JobsKits 仓库拉取。请先安装 Xcode Command Line Tools 或 git。"
    return 0
  fi

  local software_dir="${JOBS_WORKSPACE}/JobsSoftware.MacOS"
  local env_dir="${JOBS_WORKSPACE}/JobsMacEnvVarConfig"

  clone_or_update_repo "JobsSoftware.MacOS" "${JOBS_SOFTWARE_REPO}" "${software_dir}"
  clone_or_update_repo "JobsMacEnvVarConfig" "${JOBS_ENV_REPO}" "${env_dir}"

  local install_script="${env_dir}/【MacOS】install.command/【MacOS】install.command"
  if [[ -f "${install_script}" ]]; then
    if confirm_execute "是否为 JobsMacEnvVarConfig/【MacOS】install.command 添加可执行权限？" "执行"; then
      run_cmd "添加可执行权限：JobsMacEnvVarConfig/【MacOS】install.command" chmod +x "${install_script}"
    fi
    warn_echo "不会执行 ${install_script}，避免 【MacOS】install.command 递归调用自身。"
  fi
}
# ---------- 部件：手动下载页面 ----------
open_download_page() {
  local name="$1"
  local url="$2"

  if ! require_command open; then
    warn_echo "open 命令不存在，无法打开：${name}"
    return 0
  fi

  if confirm_execute "是否打开 ${name} 下载页？" "打开"; then
    run_cmd "打开 ${name} 下载页" open "${url}"
  fi
}
# 封装 component_manual_download_pages 对应的独立处理逻辑。
component_manual_download_pages() {
  progress_step "手动下载页面"

  open_download_page "Visual Studio Code" "https://code.visualstudio.com/"
  open_download_page "Android Studio" "https://developer.android.com/studio?hl=zh-cn"
  open_download_page "Python" "https://www.python.org/downloads/"
  open_download_page "Codex++" "https://github.com/BigPizzaV3/CodexPlusPlus"
}
# ---------- 菜单 ----------
get_menu_items() {
  MENU_ITEMS=(
    "${ALL_MENU_ITEM}"
    "Xcode Command Line Tools"
    "Xcode iOS 平台组件"
    "Oh My Zsh"
    "Homebrew"
  )

  local pkg
  for pkg in "${BREW_CASKS[@]}"; do
    MENU_ITEMS+=("brew cask：${pkg}")
  done

  for pkg in "${BREW_FORMULAE[@]}"; do
    MENU_ITEMS+=("brew formula：${pkg}")
  done

  MENU_ITEMS+=(
    "Rosetta 2"
    "npm 全局包：quicktype"
    "npm 全局包：OpenCLI"
    "npm 全局包：CodeGraph"
    "gem 包：cocoapods"
    "Git LFS 初始化"
    "JobsKits 仓库"
    "手动下载页面"
  )
}
# 收集并校验用户输入，决定后续执行路径。
choose_menu_items() {
  local fzf_bin=""
  fzf_bin="$(find_fzf_bin)" || return 1

  get_menu_items

  local selections=""
  selections="$(printf '%s\n' "${MENU_ITEMS[@]}" | "${fzf_bin}" \
    --multi \
    --no-sort \
    --layout=reverse-list \
    --height=90% \
    --border \
    --prompt='选择要安装 / 更新的功能 > ' \
    --header='Tab 多选，Enter 确认；选择「✅ 全选安装」会依次处理所有部件；已存在第三方依赖升级只统一确认一次。')"

  if [[ -z "${selections}" ]]; then
    warn_echo "未选择任何功能，脚本结束。"
    return 1
  fi

  SELECTED_ITEMS=("${(@f)selections}")

  local item
  local has_all=0
  for item in "${SELECTED_ITEMS[@]}"; do
    if [[ "${item}" == "${ALL_MENU_ITEM}" ]]; then
      has_all=1
      break
    fi
  done

  RUN_ITEMS=()
  if (( has_all )); then
    for item in "${MENU_ITEMS[@]}"; do
      [[ "${item}" == "${ALL_MENU_ITEM}" ]] && continue
      RUN_ITEMS+=("${item}")
    done
  else
    RUN_ITEMS=("${SELECTED_ITEMS[@]}")
  fi

  return 0
}
# 执行已经拆分完成的独立业务步骤。
run_selected_item() {
  local item="$1"

  case "${item}" in
    "Xcode Command Line Tools") component_clt ;;
    "Xcode iOS 平台组件") component_xcode_ios_platform ;;
    "Oh My Zsh") component_oh_my_zsh ;;
    "Homebrew") component_homebrew ;;
    "Rosetta 2") component_rosetta ;;
    "brew cask："*) component_brew_cask "${item#brew cask：}" ;;
    "brew formula："*) component_brew_formula "${item#brew formula：}" ;;
    "npm 全局包：quicktype") component_npm_quicktype ;;
    "npm 全局包：OpenCLI") component_npm_opencli ;;
    "npm 全局包：CodeGraph") component_npm_codegraph ;;
    "gem 包：cocoapods") component_gem_cocoapods ;;
    "Git LFS 初始化") component_git_lfs_init ;;
    "JobsKits 仓库") component_jobs_repos ;;
    "手动下载页面") component_manual_download_pages ;;
    *) warn_echo "未知菜单项，已跳过：${item}" ;;
  esac
}
# ---------- 收尾 ----------
finish_summary() {
  echo ""
  print_divider
  success_echo "macOS 新系统配置流程执行结束"
  info_echo "日志文件位置：${LOG_FILE}"
  warm_echo "请手动检查终端日志，确认失败项并按需补装。"
  warm_echo "重点留意：CLT / Xcode / Oh My Zsh / Homebrew / GitHub 网络 / sudo 密码相关步骤。"
  print_divider
}
# ---------- 主流程 ----------
install() {
  prepare_menu_runtime || return 1

  if ! choose_menu_items; then
    return 0
  fi

  TOTAL_STAGES=${#RUN_ITEMS[@]}
  CURRENT_STAGE=0

  local item item_result=0
  for item in "${RUN_ITEMS[@]}"; do
    item_result=0
    run_selected_item "${item}" || item_result=$?
    if [[ "$item" == 'brew cask：flutter' ]] && (( item_result != 0 )); then
      return "$item_result"
    fi
  done

  finish_summary
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
jobs_install_main() {
  # 执行当前流程中的独立业务步骤：处理当前语句。
  : > "${LOG_FILE}"

  # 展示脚本说明并等待用户确认影响范围。
  jobs_install_show_readme_and_wait
  # 执行安装步骤，并保留命令失败信息供后续排查。
  install "$@" || return $?

  # 执行当前流程中的独立业务步骤：pause_for_enter。
  pause_for_enter "$(jobs_prompt_render "👉 全部流程已执行完成。请按回车退出...")"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】install.command' | jobs_intro_style title
  print -r -- '核心用途：执行“install”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  jobs_list_intro_read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _
}
# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  show_script_intro_and_wait || return $? # 先展示用途、影响范围及确认方式。
  jobs_install_main "$@" # 按选择准备当前用户的开发环境。
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  set -u
  set -o pipefail
  setopt NO_NOMATCH
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    main "$@"
  fi
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
