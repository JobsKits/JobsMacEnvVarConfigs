#!/bin/zsh
# 脚本自述：
# - 核心用途：隔离验证 update 的 Gem 扩展修复顺序、错误传播和独立入口交互。
# - 影响范围：仅写专属临时目录；gem、rbenv、Ruby worker 与 Specs 刷新均为替身。
# - 运行提示：自动执行，不联网、不升级、不修改宿主 Gem；按 Ctrl+C 可取消。

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

TEST_DIR="${${(%):-%x}:A:h:h}"
PROTOTYPE_SCRIPT="${TEST_DIR:h}/【MacOS】repair_gem_extensions.command"
UPDATE_SCRIPT="${TEST_DIR:h:h}/【MacOS】update.command/【MacOS】update.command"
TEST_ROOT=''
TEST_PASSED=0
TEST_FAILED=0
MOCK_GEM_PRESENT=1
MOCK_RBENV_PRESENT=1
MOCK_POD_PRESENT=1
MOCK_WORKER_FAILURE_AT=0
MOCK_WORKER_EXIT=23
PTY_CAPTURE=''
TEST_ACTUAL_RUN_CMD=''

# 说明所有真实包管理器均不会进入被测执行链。
show_test_intro() {
  print -r -- 'Gem 原生扩展 Shell 集成回归：仅运行临时目录与替身，不联网、不升级。'
}
# 汇总断言；失败继续执行以保留完整回归结果。
expect_equal() {
  local expected="$1" actual="$2" description="$3"
  if [[ "$actual" == "$expected" ]]; then
    (( TEST_PASSED += 1 ))
  else
    (( TEST_FAILED += 1 ))
    print -u2 -r -- "✖ ${description}：期望 ${(qqq)expected}，实际 ${(qqq)actual}"
  fi
}
# 检查文本包含关键反馈，不依赖日志其它细节。
expect_contains() {
  local actual="$1" expected="$2" description="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    (( TEST_PASSED += 1 ))
  else
    (( TEST_FAILED += 1 ))
    print -u2 -r -- "✖ ${description}：缺少 ${(qqq)expected}"
  fi
}
# 检查文本不包含被禁止的控制符或真实业务记录。
expect_absent() {
  local actual="$1" unexpected="$2" description="$3"
  if [[ "$actual" != *"$unexpected"* ]]; then
    (( TEST_PASSED += 1 ))
  else
    (( TEST_FAILED += 1 ))
    print -u2 -r -- "✖ ${description}：出现 ${(qqq)unexpected}"
  fi
}
# 成功时回收本测试临时文件，失败保留证据便于排查。
cleanup_tests() {
  zpty -d jobs_gemext_test 2>/dev/null || true
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" && "${TEST_ROOT:t}" == jobs-gemext-integration.* ]]; then
    if (( TEST_FAILED == 0 )); then
      /bin/rm -r -- "$TEST_ROOT"
    else
      print -u2 -r -- "隔离回归材料：$TEST_ROOT"
    fi
  fi
}
# 在脚本进程结束时回收目录，避免函数内 EXIT trap 提前触发清理。
TRAPEXIT() {
  cleanup_tests
}
# 创建专属目录并在明确的 source 模式下加载 update 函数。
initialize_tests() {
  setopt NO_NOMATCH
  zmodload zsh/zpty || return 1
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-gemext-integration.XXXXXXXX")" || return 1
  export TEST_ROOT
  /bin/mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/gems" "$TEST_ROOT/runtime" "$TEST_ROOT/site-ruby"
  /bin/cat > "$TEST_ROOT/bin/ruby" <<'MOCK_UPDATE_RUBY'
#!/bin/zsh
[[ "$*" == '--disable-gems -rrbconfig -e '* ]] || exit 93
print -r -- "$TEST_ROOT/site-ruby"
MOCK_UPDATE_RUBY
  /bin/chmod +x "$TEST_ROOT/bin/ruby"
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "$UPDATE_SCRIPT" || return 1
  TEST_ACTUAL_RUN_CMD="${functions[jobs_update_run_cmd]}"
}
# 将所有升级与刷新入口替换为无副作用记录器，worker 次数通过文件跨管道保存。
install_update_mocks() {
  function jobs_update_has() {
    case "$1" in
      gem|ruby) (( MOCK_GEM_PRESENT == 1 )) ;;
      rbenv) (( MOCK_RBENV_PRESENT == 1 )) ;;
      pod) (( MOCK_POD_PRESENT == 1 )) ;;
      *) return 1 ;;
    esac
  }
  function ensure_rbenv_init() {
    print -r -- 'rbenv:init' >> "$TEST_ROOT/events"
  }
  function rbenv() {
    print -r -- "rbenv:$*" >> "$TEST_ROOT/events"
  }
  function gem() {
    case "$*" in
      'list -i ^cocoapods$') return 0 ;;
      'env home') print -r -- "$TEST_ROOT/gems" ;;
      env)
        print -r -- "  - INSTALLATION DIRECTORY: $TEST_ROOT/gems"
        print -r -- "  - EXECUTABLE DIRECTORY: $TEST_ROOT/bin"
        print -r -- "  - RUBY EXECUTABLE: $TEST_ROOT/bin/ruby"
        ;;
      update*) print -r -- "gem:$*" >> "$TEST_ROOT/events" ;;
      *) print -u2 -r -- "禁止的 gem 替身调用：$*"; return 91 ;;
    esac
  }
  function jobs_gemext_find_ruby() {
    print -r -- "$TEST_ROOT/bin/ruby"
  }
  function jobs_update_gem() {
    gem "$@"
  }
  function jobs_update_run_cmd() {
    shift
    "$@"
  }
  function jobs_update_run_sudo_cmd() {
    shift
    "$@"
  }
  function find_brew_bin() {
    return 1
  }
  function jobs_update_cocoapods_repos() {
    print -r -- 'repos:refresh' >> "$TEST_ROOT/events"
  }
  function jobs_gemext_process() {
    local count=0
    [[ ! -s "$TEST_ROOT/worker-count" ]] || count="$(<"$TEST_ROOT/worker-count")"
    (( count += 1 ))
    print -r -- "$count" > "$TEST_ROOT/worker-count"
    print -r -- "worker:$1:$count" >> "$TEST_ROOT/events"
    print -r -- "MOCK_WORKER:$1:$count"
    (( count != MOCK_WORKER_FAILURE_AT )) || return "$MOCK_WORKER_EXIT"
    return 0
  }
  function warn_echo() {
    print -r -- "$1"
  }
  function info_echo() {
    print -r -- "$1"
  }
}
# 每个用例恢复健康默认值，并将日志限制在专属目录。
reset_update_mock() {
  MOCK_GEM_PRESENT=1
  MOCK_RBENV_PRESENT=1
  MOCK_POD_PRESENT=1
  MOCK_WORKER_FAILURE_AT=0
  MOCK_WORKER_EXIT=23
  LOG_FILE="$TEST_ROOT/update.log"
  : > "$TEST_ROOT/events"
  : > "$TEST_ROOT/worker-count"
  : > "$LOG_FILE"
}
# 验证真实 RubyGems 升级前后各扫描一次，并先完成 rbenv 初始化。
test_update_sequence() {
  local result=0 expected=''
  reset_update_mock
  jobs_update_ruby_base > "$TEST_ROOT/output" 2>&1 || result=$?
  expected=$'rbenv:init\nrbenv:rehash\nworker:repair:1\ngem:update --system --no-document\ngem:update --no-user-install --install-dir '"$TEST_ROOT/gems --bindir $TEST_ROOT/bin --no-document"$'\nworker:repair:2'
  expect_equal 0 "$result" '健康 Ruby 阶段成功'
  expect_equal "$expected" "$(<"$TEST_ROOT/events")" 'rbenv、修复、升级、复检顺序'
  expect_equal 2 "$(<"$TEST_ROOT/worker-count")" '健康环境升级前后仍各扫描一次'
  expect_contains "$(<"$LOG_FILE")" 'MOCK_WORKER:repair:1' '首次扫描同步落盘'
  expect_contains "$(<"$LOG_FILE")" 'MOCK_WORKER:repair:2' '升级后复检同步落盘'
}
# 前后任一次修复失败，都必须让 Ruby 阶段报告非零。
test_update_worker_failures() {
  local failure_at result
  for failure_at in 1 2; do
    reset_update_mock
    MOCK_WORKER_FAILURE_AT="$failure_at"
    result=0
    jobs_update_ruby_base > "$TEST_ROOT/output" 2>&1 || result=$?
    expect_equal 1 "$result" "第 ${failure_at} 次修复失败传播到 Ruby 阶段"
  done
  reset_update_mock
  MOCK_WORKER_FAILURE_AT=1
  result=0
  jobs_update_repair_gem_extensions > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 23 "$result" '日志管道保留 worker 原退出码'
}
# 日志流写入失败不能被 worker 的成功退出码覆盖。
test_update_tee_failures() {
  local result=0
  reset_update_mock
  print -r -- 'not a directory' > "$TEST_ROOT/blocked"
  LOG_FILE="$TEST_ROOT/blocked/update.log"
  jobs_update_repair_gem_extensions > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 1 "$(( result != 0 ))" 'worker 成功但日志写入失败时返回非零'
  MOCK_WORKER_FAILURE_AT=2
  result=0
  jobs_update_repair_gem_extensions > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 23 "$result" 'worker 与日志同时失败时保留 worker 错误'
}
# 独立调用与公共执行器调用都只将每条 worker 输出写入日志一次。
test_worker_log_once() {
  reset_update_mock
  jobs_update_repair_gem_extensions > "$TEST_ROOT/output" 2>&1
  expect_equal 1 "$(/usr/bin/grep -Fc 'MOCK_WORKER:repair:1' "$LOG_FILE")" '独立 worker 输出仅落盘一次'
  (
    reset_update_mock
    functions[jobs_update_run_cmd]="$TEST_ACTUAL_RUN_CMD"
    jobs_update_run_cmd '包装 worker' jobs_update_repair_gem_extensions > "$TEST_ROOT/output" 2>&1
    /usr/bin/grep -Fc 'MOCK_WORKER:repair:1' "$LOG_FILE" > "$TEST_ROOT/log-count"
  )
  expect_equal 1 "$(< "$TEST_ROOT/log-count")" '公共执行器内 worker 输出仅落盘一次'
}
# CocoaPods 本体升级后先修扩展，再刷新 Specs；修复失败或无 pod 时阻止刷新。
test_cocoapods_sequence() {
  local result=0
  reset_update_mock
  jobs_update_gem_cocoapods > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 0 "$result" 'CocoaPods 升级与复检成功'
  expect_equal "gem:update cocoapods --no-user-install --install-dir $TEST_ROOT/gems --bindir $TEST_ROOT/bin --no-document"$'\nworker:repair:1\nrepos:refresh' "$(<"$TEST_ROOT/events")" 'CocoaPods 工具升级、扩展复检、Specs 刷新顺序'
  reset_update_mock
  MOCK_WORKER_FAILURE_AT=1
  result=0
  jobs_update_gem_cocoapods > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 1 "$result" 'CocoaPods 扩展复检失败传播'
  expect_absent "$(<"$TEST_ROOT/events")" 'repos:refresh' '修复失败跳过 Specs 刷新'
  reset_update_mock
  MOCK_POD_PRESENT=0
  result=0
  jobs_update_gem_cocoapods > "$TEST_ROOT/output" 2>&1 || result=$?
  expect_equal 1 "$result" '无 pod 时报告不可刷新'
  expect_absent "$(<"$TEST_ROOT/events")" 'worker:' '无 pod 时不调用扩展 worker'
  expect_absent "$(<"$TEST_ROOT/events")" 'repos:refresh' '无 pod 时不刷新 Specs'
}
# 内嵌和原型逐字节相同，修复模块与独立脚本均没有外部 source 依赖。
test_embedded_copy() {
  local script_name output_name result
  for script_name output_name in "$PROTOTYPE_SCRIPT" prototype-block "$UPDATE_SCRIPT" update-block; do
    /usr/bin/awk '/^# >>> Jobs Gem extension repair >>>$/ { copy = 1 } copy { print } /^# <<< Jobs Gem extension repair <<<$/ { exit }' "$script_name" > "$TEST_ROOT/$output_name"
  done
  result=0
  /usr/bin/cmp -s "$TEST_ROOT/prototype-block" "$TEST_ROOT/update-block" || result=$?
  expect_equal 0 "$result" '内嵌修复块与独立原型逐字节一致'
  result=0
  if /usr/bin/grep -Eq '^[[:space:]]*(source|\.)[[:space:]]+[^=[:space:]]' "$TEST_ROOT/prototype-block" "$PROTOTYPE_SCRIPT"; then
    result=1
  fi
  expect_equal 0 "$result" '修复模块可独立携带且不 source 外置实现'
}
# 生成仅执行替身的独立脚本和伪终端驱动。
prepare_standalone_fixtures() {
  /usr/bin/sed '$d' "$PROTOTYPE_SCRIPT" > "$TEST_ROOT/prototype-definitions.zsh"
  /bin/cp "$PROTOTYPE_SCRIPT" "$TEST_ROOT/standalone.command"
  /bin/cat > "$TEST_ROOT/bin/ruby" <<'MOCK_RUBY'
#!/bin/zsh
if [[ "$*" == '--disable-gems -rrbconfig -e '* ]]; then
  print -r -- 'ruby:health' >> "$TEST_ROOT/ruby-events"
  exit 0
fi
if [[ "$1" == --disable-gems && "$2" == - ]]; then
  /bin/cat > /dev/null
  print -r -- "ruby:worker:$3" >> "$TEST_ROOT/ruby-events"
  print -r -- "MOCK_STANDALONE_WORKER:$3"
  exit 0
fi
print -u2 -r -- "拒绝未知 Ruby 调用：$*"
exit 92
MOCK_RUBY
  /bin/chmod +x "$TEST_ROOT/bin/ruby"
  /bin/cat > "$TEST_ROOT/pty-driver.zsh" <<'PTY_DRIVER'
#!/bin/zsh
source "$TEST_ROOT/prototype-definitions.zsh"
trap 'print -r -- "TEST_DONE=$?"' EXIT
jobs_gemext_process() {
  print -r -- "pty:worker:$1" >> "$TEST_ROOT/pty-events"
  print -r -- "MOCK_PTY_WORKER:$1"
}
case "$1" in
  color)
    unset NO_COLOR
    TERM=xterm-256color
    jobs_intro_line title 'TITLE'
    jobs_intro_line body '1、BODY'
    ;;
  no-color)
    NO_COLOR=1
    TERM=xterm-256color
    jobs_intro_line title 'TITLE'
    jobs_intro_line body '1、BODY'
    ;;
  skip|run|cancel)
    main --repair
    exit $?
    ;;
esac
PTY_DRIVER
}
# 通过原生 zpty 验证 TTY 配色与两次输入，不调用真实 worker。
capture_pty() {
  local scenario="$1" answer_one="${2:-}" answer_two="${3:-}" chunk='' attempt
  PTY_CAPTURE=''
  /bin/mkdir -p "$TEST_ROOT/pty-$scenario"
  : > "$TEST_ROOT/pty-events"
  TMPDIR="$TEST_ROOT/pty-$scenario" zpty -b jobs_gemext_test /bin/zsh -f "$TEST_ROOT/pty-driver.zsh" "$scenario"
  case "$scenario" in
    skip|run|cancel)
      zpty -w -n jobs_gemext_test "${answer_one}"$'\n'
      [[ "$scenario" == cancel ]] || zpty -w -n jobs_gemext_test "${answer_two}"$'\n'
      ;;
  esac
  for attempt in {1..300}; do
    while zpty -r jobs_gemext_test chunk; do
      PTY_CAPTURE+="$chunk"
    done
    [[ "$PTY_CAPTURE" != *TEST_DONE=* ]] || break
    /bin/sleep 0.01
  done
  zpty -d jobs_gemext_test 2>/dev/null || true
  expect_contains "$PTY_CAPTURE" 'TEST_DONE=0' "伪终端 ${scenario} 正常结束"
}
# 独立复制文件运行成功；无交互授权时不创建日志或启动 worker。
test_standalone_entry() {
  local result=0
  : > "$TEST_ROOT/ruby-events"
  /usr/bin/env JOBS_GEMEXT_RUBY="$TEST_ROOT/bin/ruby" TMPDIR="$TEST_ROOT/runtime" \
    /bin/zsh "$TEST_ROOT/standalone.command" --check -t > "$TEST_ROOT/standalone-output" 2>&1 || result=$?
  expect_equal 0 "$result" '单独拷走脚本仍能执行只读 worker'
  expect_equal $'ruby:health\nruby:worker:check' "$(<"$TEST_ROOT/ruby-events")" '独立入口只调用替身 Ruby'
  expect_contains "$(<"$TEST_ROOT/runtime/repair_gem_extensions.log")" 'MOCK_STANDALONE_WORKER:check' '独立入口日志同步落盘'
  /bin/mkdir -p "$TEST_ROOT/no-tty"
  : > "$TEST_ROOT/ruby-events"
  result=0
  /usr/bin/env JOBS_GEMEXT_RUBY="$TEST_ROOT/bin/ruby" TMPDIR="$TEST_ROOT/no-tty" \
    /bin/zsh "$TEST_ROOT/standalone.command" --repair < /dev/null > "$TEST_ROOT/standalone-output" 2>&1 || result=$?
  expect_equal 2 "$result" '普通入口非 TTY 不静默修复'
  expect_equal '' "$(<"$TEST_ROOT/ruby-events")" '确认前不调用 Ruby'
  if [[ -e "$TEST_ROOT/no-tty/repair_gem_extensions.log" ]]; then
    expect_equal absent exists '确认前不初始化日志'
  else
    expect_equal absent absent '确认前不初始化日志'
  fi
}
# 检查自述红色粗体标题、蓝色常规正文以及纯文本降级。
test_standalone_styles() {
  capture_pty color
  expect_contains "$PTY_CAPTURE" $'\e[1;31mTITLE\e[0m' 'TTY 标题为红色粗体'
  expect_contains "$PTY_CAPTURE" $'\e[0;34m1、BODY\e[0m' 'TTY 编号正文为蓝色常规'
  capture_pty no-color
  expect_absent "$PTY_CAPTURE" $'\e[' 'NO_COLOR 时不输出 ANSI'
  local output=''
  output="$(/bin/zsh -c 'source "$TEST_ROOT/prototype-definitions.zsh"; jobs_intro_line title TITLE; jobs_intro_line body "1、BODY"')"
  expect_equal $'TITLE\n1、BODY' "$output" '非 TTY 输出纯文本'
}
# 回车跳过不写日志、不调用 worker；非空输入才执行，取消自述也不执行。
test_standalone_prompts() {
  capture_pty skip '' ''
  expect_equal '' "$(<"$TEST_ROOT/pty-events")" '普通操作直接回车跳过'
  if [[ -e "$TEST_ROOT/pty-skip/repair_gem_extensions.log" ]]; then
    expect_equal absent exists '跳过操作不初始化日志'
  else
    expect_equal absent absent '跳过操作不初始化日志'
  fi
  capture_pty run '' y
  expect_equal 'pty:worker:repair' "$(<"$TEST_ROOT/pty-events")" '普通操作非空输入才执行修复'
  expect_contains "$(<"$TEST_ROOT/pty-run/repair_gem_extensions.log")" 'MOCK_PTY_WORKER:repair' '确认执行后日志落盘'
  capture_pty cancel n ''
  expect_equal '' "$(<"$TEST_ROOT/pty-events")" '取消自述不调用 worker'
}
# 统一报告结果，并让任一失败反馈到测试进程退出码。
finish_tests() {
  print -r -- "通过 ${TEST_PASSED}；失败 ${TEST_FAILED}。"
  (( TEST_FAILED == 0 ))
}
# 编排隔离准备、更新集成和独立入口验证。
main() {
  show_test_intro # 说明隔离边界。
  initialize_tests # 创建临时目录并只加载函数定义。
  install_update_mocks # 阻止真实包管理器及网络操作。
  test_update_sequence # 验证更新前后的扫描顺序。
  test_update_worker_failures # 验证构建失败传播。
  test_update_tee_failures # 验证日志失败传播。
  test_worker_log_once # 验证独立和包装模式均不重复落盘。
  test_cocoapods_sequence # 验证工具升级和 Specs 之间的修复边界。
  test_embedded_copy # 验证单文件实现保持一致。
  prepare_standalone_fixtures # 准备无副作用独立入口和 TTY 驱动。
  test_standalone_entry # 验证单文件运行与非交互保护。
  test_standalone_styles # 验证自述配色与降级。
  test_standalone_prompts # 验证回车跳过和非空执行。
  finish_tests # 汇总并传播测试退出码。
}

main "$@"
