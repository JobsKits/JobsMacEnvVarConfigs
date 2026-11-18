#!/bin/zsh
# shell: zsh
# 脚本自述：隔离验证list父子确认与方向键返回，不执行安装、更新、清理或录屏。

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

# 说明测试只运行隔离夹具，真正业务不会被调用。
show_test_intro() {
  print -r -- '菜单返回回归：真实PTY/fzf验证←返回、Enter继续和取消；不安装、不更新、不录屏。'
  [[ "${1:-}" != --yes ]] || return 0
  [[ -t 0 ]] || { print -u2 '请在终端执行，自动验证使用 --yes。'; exit 64; }
  read -r '?按回车继续；Ctrl+C取消：' _ || exit 130
}
# 从测试脚本位置解析生产入口，独立创建本轮临时目录。
initialize_test_paths() {
  setopt NO_NOMATCH PIPE_FAIL
  SCRIPT_DIR="${${(%):-%x}:A:h}"
  LIST_FILE="${SCRIPT_DIR:h:h}/【MacOS】list.command"
  SCRIPTS_ROOT="${LIST_FILE:h:h}"
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/jobs-list-confirm-tests.XXXXXX")" || exit 1
  LOG_FILE="$TEST_ROOT/navigation.log"
  : > "$LOG_FILE"
  print -r -- "隔离夹具：$TEST_ROOT"
}
# 复用系统Expect和现有fzf，不进行任何依赖安装。
check_test_environment() {
  [[ -x /usr/bin/expect ]] || { print -u2 '缺少系统Expect。'; exit 69; }
  FZF_BIN="$(command -v fzf 2>/dev/null)" || { print -u2 '缺少fzf，请先通过原环境入口准备。'; exit 69; }
  "$FZF_BIN" --version >/dev/null || exit 69
}
# 提取最后一个同名生产函数，保留其真实定义而不source整个业务脚本。
extract_function() {
  /usr/bin/awk -v wanted="$2" '
    /^[A-Za-z_][A-Za-z_0-9]*\(\)[[:space:]]*\{/ {
      if (collect) { saved = body; collect = 0 }
      if ($0 ~ ("^" wanted "\\(\\)")) { collect = 1; body = "" }
    }
    collect { body = body $0 ORS }
    END { if (collect) saved = body; printf "%s", saved }
  ' "$1"
}
# 提取生产确认模块并生成只写哨兵的子功能，不执行真实脚本主入口。
write_child_fixture() {
  /usr/bin/awk '/^# >>> Jobs list parent confirmation >>>/ { keep = 1 } keep { print } /^# <<< Jobs list parent confirmation <<</ { exit }' "$LIST_FILE" > "$TEST_ROOT/helper.zsh"
  [[ -s "$TEST_ROOT/helper.zsh" ]] || exit 1
  print -r -- '#!/bin/zsh -f' > "$TEST_ROOT/child.zsh"
  cat "$TEST_ROOT/helper.zsh" "$TEST_ROOT/display-stubs.zsh" >> "$TEST_ROOT/child.zsh"
  cat >> "$TEST_ROOT/child.zsh" <<'CHILD'
jobs_list_intro_read -r 'answer?ORIGINAL_CONFIRM:'
print -r -- "BUSINESS_RAN:${answer:-}"
CHILD
  chmod +x "$TEST_ROOT/child.zsh"
}
# 每个菜单目标只提取其初始确认函数，展示/解析函数用无副作用桩替代。
write_intro_fixtures() {
  local name source_file intro_function
  local -a names
  names=("${(@f)$(/usr/bin/awk -F '\t' '$4 == "script" && $5 != "【MacOS】jrecord.command" { print $5 }' "$LIST_FILE" | sort -u)}")
  mkdir -p "$TEST_ROOT/all-intros"
  GATE_COUNT=0
  for name in "${names[@]}"; do
    source_file="$SCRIPTS_ROOT/$name/$name"
    [[ -r "$source_file" ]] || exit 1
    grep -Fq '# >>> Jobs list parent confirmation >>>' "$source_file" || exit 1
    intro_function=show_script_intro_and_wait
    case "$name" in
      【MacOS】pods.command) intro_function=show_readme_and_block ;;
      【MacOS】dq.command) intro_function=show_script_intro ;;
      【MacOS】df.command) intro_function=jobs_df_show_readme_and_wait ;;
    esac
    cat "$TEST_ROOT/helper.zsh" "$TEST_ROOT/display-stubs.zsh" > "$TEST_ROOT/all-intros/$name.zsh"
    extract_function "$source_file" "$intro_function" >> "$TEST_ROOT/all-intros/$name.zsh"
    print -r -- "$intro_function" >> "$TEST_ROOT/all-intros/$name.zsh"
    print -r -- 'print BUSINESS_RAN' >> "$TEST_ROOT/all-intros/$name.zsh"
    /bin/zsh -n "$TEST_ROOT/all-intros/$name.zsh" || exit 1
    (( GATE_COUNT += 1 ))
  done
  (( GATE_COUNT > 0 )) || exit 1
}
# 只输出说明与只读解析，不允许夹具进入安装、修复或真实业务。
write_display_stubs() {
  cat > "$TEST_ROOT/display-stubs.zsh" <<'STUBS'
jobs_intro_style(){ cat; }
jobs_prompt_filter(){ cat; }
jobs_prompt_render(){ print -r -- "$1"; }
prepare_display(){ :; }
clear(){ :; }
print_styled(){ print -r -- "$2"; }
message(){ print -r -- "$1"; }
show_usage(){ :; }
parse_arguments(){ :; }
close_trace_noise(){ :; }
print_divider(){ :; }
jobs_dq_print_usage(){ :; }
jobs_update_parse_entry_arguments(){ :; }
jobs_update_parse_args(){ :; }
jobs_update_prepare_display(){ :; }
jobs_update_prepare_entry_display(){ :; }
log(){ print -r -- "$1"; }
color_echo(){ print -r -- "$1"; }
info_echo(){ print -r -- "$1"; }
success_echo(){ print -r -- "$1"; }
warn_echo(){ print -r -- "$1"; }
warm_echo(){ print -r -- "$1"; }
note_echo(){ print -r -- "$1"; }
error_echo(){ print -r -- "$1"; }
err_echo(){ print -r -- "$1"; }
debug_echo(){ print -r -- "$1"; }
highlight_echo(){ print -r -- "$1"; }
gray_echo(){ print -r -- "$1"; }
bold_echo(){ print -r -- "$1"; }
underline_echo(){ print -r -- "$1"; }
LOG_FILE=/dev/null
JOBS_UPDATE_TRUST_MODE=0
JOBS_UPDATE_ENTRY_EXIT_CODE=0
JOBS_UPDATE_ENTRY_READY=0
STUBS
}
# 使用真正的父层执行与菜单函数，只有菜单数据和具体业务被隔离。
write_parent_fixture() {
  local function_name
  cat "$TEST_ROOT/helper.zsh" > "$TEST_ROOT/parent.zsh"
  for function_name in run_script_feature run_to_format_feature run_function_feature run_feature show_menu; do
    extract_function "$LIST_FILE" "$function_name" >> "$TEST_ROOT/parent.zsh"
  done
  cat >> "$TEST_ROOT/parent.zsh" <<'PARENT'
LOG_FILE=/dev/null
FZF_BIN="${JOBS_TEST_FZF_BIN:-}"
note_echo(){ print -r -- "$1"; }
error_echo(){ print -r -- "$1"; }
info_echo(){ print -r -- "$1"; }
log(){ print -r -- "$1"; }
warm_echo(){ print -r -- "$1"; }
jobs_prompt_render(){ print -r -- "$1"; }
jobs_prompt_output(){ local command="$1"; shift; "$command" "$@"; }
resolve_script_file(){ print -r -- "$JOBS_TEST_ROOT/child.zsh"; }
fzf_supports_info_command(){ return 1; }
load_function_modules(){ :; }
flutter(){ print BUSINESS_RAN; }
build_fzf_items(){
  print x >> "$JOBS_TEST_ROOT/menu-count-$JOBS_TEST_MENU_KIND"
  local frame="$(wc -l < "$JOBS_TEST_ROOT/menu-count-$JOBS_TEST_MENU_KIND")"
  print -u2 -r -- "MENU_FRAME:$((frame))"
  case "$JOBS_TEST_MENU_KIND" in
    script) printf 'test\tcor\tconfirm\tscript\t【MacOS】cor.command\tCHILD TEST\n' ;;
    jrecord) printf 'test\tjrecord\tconfirm\tscript\t【MacOS】jrecord.command\tCHILD TEST\n' ;;
    format) printf 'test\tmp4\tconfirm\tto_format\tmp4\tCHILD TEST\n' ;;
    function) printf 'test\tflutter\tconfirm\tfunction\tflutter\tCHILD TEST\n' ;;
  esac
}
stty rows 40 cols 120
tty_signature(){
  local raw="$(stty -g)" tail flags
  tail="${raw#*lflag=}"
  flags="${tail%%:*}"
  printf '%slflag=%x:%s\n' "${raw%%lflag=*}" "$((16#$flags & ~16#20000000))" "${tail#*:}"
}
before_tty="$(tty_signature)"
show_menu
[[ "$(tty_signature)" == "$before_tty" ]] || { print TTY_CHANGED; exit 1; }
print PARENT_DONE
PARENT
}
# 写入系统Expect驱动，发送真实方向键并仅模拟fzf的光标位置响应。
write_expect_drivers() {
  cat > "$TEST_ROOT/check.exp" <<'KEYS'
set timeout 5
log_user 0
set fixture [lindex $argv 0]
proc check {fixture name mode keys expected prompt business} {
  spawn -noecho env JOBS_LIST_PARENT_MENU=$mode /bin/zsh -f $fixture
  expect {
    -exact $prompt {}
    timeout {puts stderr "FAIL $name prompt"; exit 1}
  }
  send -- $keys
  set seen 0
  set value {}
  expect {
    -re {BUSINESS_RAN:([^\r\n]*)} {set seen 1; set value $expect_out(1,string); exp_continue}
    eof {}
    timeout {puts stderr "FAIL $name eof"; exit 1}
  }
  set result [wait]
  set code [lindex $result 3]
  if {$expected == 130 && [llength $result] > 4 && [lindex $result 5] eq "SIGINT"} {set code 130}
  if {$code != $expected || $seen != $business} { puts stderr "FAIL $name code=$code business=$seen result=$result"; exit 1 }
  if {$mode ne "list" && $business && $value ne "abc"} {puts stderr "FAIL $name original read value=$value"; exit 1}
  puts "PASS $name"
}
check $fixture left list "\033\[D" 20 "返回功能菜单" 0
check $fixture ss3 list "\033OD" 20 "返回功能菜单" 0
check $fixture enter list "\r" 0 "返回功能菜单" 1
check $fixture esc list "\033" 130 "返回功能菜单" 0
check $fixture ctrl_c list "\003" 130 "返回功能菜单" 0
check $fixture standalone {} "abc\r" 0 "ORIGINAL_CONFIRM:" 1
check $fixture other_source other "abc\r" 0 "ORIGINAL_CONFIRM:" 1
KEYS
  cat > "$TEST_ROOT/all-intros.exp" <<'INTROS'
set timeout 5
log_user 0
set fixture [lindex $argv 0]
proc check {fixture name mode keys expected prompt business} {
  spawn -noecho env JOBS_LIST_PARENT_MENU=$mode /bin/zsh -f $fixture
  expect {
    -exact $prompt {}
    eof {puts stderr "FAIL $name early eof: $expect_out(buffer)"; exit 1}
    timeout {puts stderr "FAIL $name prompt"; exit 1}
  }
  send -- $keys
  set seen 0
  set value {}
  expect {
    -re {BUSINESS_RAN:([^\r\n]*)} {set seen 1; set value $expect_out(1,string); exp_continue}
    eof {}
    timeout {puts stderr "FAIL $name eof"; exit 1}
  }
  set result [wait]
  set code [lindex $result 3]
  if {$expected == 130 && [llength $result] > 4 && [lindex $result 5] eq "SIGINT"} {set code 130}
  if {$code != $expected || $seen != $business} { puts stderr "FAIL $name code=$code business=$seen result=$result"; exit 1 }
  if {$mode ne "list" && $business && $value ne "abc"} {puts stderr "FAIL $name original read value=$value"; exit 1}
  puts "PASS $name"
}
foreach intro [glob -directory [lindex $argv 0] -- *.zsh] { check $intro [file tail $intro] list "\033\[D" 20 "返回功能菜单" 0 }
INTROS
  cat > "$TEST_ROOT/parent.exp" <<'MENU'
set timeout 8
log_user 0
set root [lindex $argv 0]
foreach kind {script jrecord format function} {
  set counter [open "$root/menu-count-$kind" w]; close $counter
  spawn -noecho env JOBS_TEST_ROOT=$root JOBS_TEST_MENU_KIND=$kind TERM=xterm-256color FZF_DEFAULT_OPTS= NO_COLOR=1 /bin/zsh -f $root/parent.zsh
  expect_before -re {\x1b\[6n} {send -- "\033\[1;1R"; exp_continue}
  expect {
    -exact "MENU_FRAME:1" {}
    timeout {puts stderr "FAIL $kind initial menu"; exit 1}
    eof {puts stderr "FAIL $kind early eof"; exit 1}
  }
  expect {
    -exact "CHILD TEST" {}
    timeout {puts stderr "FAIL $kind first rendered item"; exit 1}
    eof {puts stderr "FAIL $kind first render eof"; exit 1}
  }
  send -- "\r"
  expect {
    -exact "返回功能菜单" {}
    timeout {puts stderr "FAIL $kind child confirm"; exit 1}
    eof {puts stderr "FAIL $kind child eof"; exit 1}
  }
  send -- "\033\[D"
  expect {
    -exact "BUSINESS_RAN" {puts stderr "FAIL $kind business ran"; exit 1}
    -exact "按回车返回菜单" {puts stderr "FAIL $kind extra confirmation"; exit 1}
    -exact "MENU_FRAME:2" {}
    timeout {puts stderr "FAIL $kind parent redraw"; exit 1}
  }
  expect {
    -exact "CHILD TEST" {}
    timeout {puts stderr "FAIL $kind second rendered item"; exit 1}
    eof {puts stderr "FAIL $kind second render eof"; exit 1}
  }
  send -- "\033"
  set done 0
  expect {
    -exact "PARENT_DONE" {set done 1; exp_continue}
    eof {if {!$done} {puts stderr "FAIL $kind no parent completion"; exit 1}}
    timeout {puts stderr "FAIL $kind parent done"; exit 1}
  }
  set result [wait]
  if {[lindex $result 3] != 0} {puts stderr "FAIL $kind status $result"; exit 1}
  puts "PASS real fzf parent redraw: $kind"
}
MENU
}
# 执行键盘、自述门禁与四类真实fzf父层往返，任何失败立即保留现场退出。
run_navigation_tests() {
  /usr/bin/expect "$TEST_ROOT/check.exp" "$TEST_ROOT/child.zsh" | tee -a "$LOG_FILE" || exit 1
  /usr/bin/expect "$TEST_ROOT/all-intros.exp" "$TEST_ROOT/all-intros" | tee -a "$LOG_FILE" || exit 1
  JOBS_TEST_FZF_BIN="$FZF_BIN" /usr/bin/expect "$TEST_ROOT/parent.exp" "$TEST_ROOT" | tee -a "$LOG_FILE" || exit 1
  print -r -- "PASS: 7项按键/来源、${GATE_COUNT}个生产自述和4类真实fzf父层返回；日志：$LOG_FILE"
}
# 先确认测试范围，再构造隔离夹具并执行真实PTY交互。
main() {
  show_test_intro "$@" # 说明隔离范围并等待确认。
  initialize_test_paths # 解析生产入口并创建独立现场。
  check_test_environment # 检查系统Expect和已安装fzf。
  write_display_stubs # 限定只读展示与参数解析。
  write_child_fixture # 提取真实确认模块并隔离业务。
  write_intro_fixtures # 对账菜单中的全部非录屏确认入口。
  write_parent_fixture # 保留实际父层执行和重画逻辑。
  write_expect_drivers # 准备真实按键与终端光标响应。
  run_navigation_tests # 核对返回、确认、取消和父层重画。
}

main "$@"
