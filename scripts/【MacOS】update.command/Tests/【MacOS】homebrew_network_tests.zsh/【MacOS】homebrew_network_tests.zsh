#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】homebrew_network_tests.zsh
# - 核心用途：隔离验证 Homebrew 慢速下载、有限重试与 Python 共用索引更新。
# - 影响范围：仅使用临时文件与假 brew，不联网、不安装、不升级。
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

TEST_SCRIPT_DIR="${${(%):-%x}:A:h:h}"
TEST_ROOT=''
TEST_PASSED=0
TEST_FAILED=0
TEST_LOCK_HOLDER_PID=''
# 仅回收本测试创建的目录和网络策略临时文件。
cleanup_tests() {
  if [[ -n "$TEST_LOCK_HOLDER_PID" ]]; then
    wait "$TEST_LOCK_HOLDER_PID" 2>/dev/null || true
  fi
  jobs_update_cleanup_network_strategy 2>/dev/null || true
  if [[ -d "$TEST_ROOT" && "${TEST_ROOT:t}" == jobs-brew-tests.* ]]; then
    /bin/rm -r -- "$TEST_ROOT"
  fi
}
# 建立只输出预定错误的假命令，杜绝真实包管理器调用。
initialize_tests() {
  print -r -- 'Homebrew 下载与索引隔离回归；不联网、不安装、不升级。Ctrl+C 可取消。'
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-brew-tests.XXXXXXXX")" || return 1
  /bin/mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/runtime" "$TEST_ROOT/prefix/var/homebrew/locks"
  export MOCK_ROOT="$TEST_ROOT" TMPDIR="$TEST_ROOT/runtime"
  export PATH="$TEST_ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  /bin/cat > "$TEST_ROOT/bin/brew" <<'MOCK_BREW'
#!/bin/zsh
if [[ "${MOCK_BREW_MODE:-}" == manual-app ]]; then
  print -r -- "$*" >> "$MOCK_ROOT/calls"
  case "$1" in
    update) exit 0 ;;
    list) exit 1 ;;
    info) /bin/cat "$MOCK_ROOT/cask.json"; exit 0 ;;
    *) exit 99 ;;
  esac
fi
if [[ "$1" == --prefix ]]; then
  print -r -- "$MOCK_ROOT/prefix"
  exit 0
fi
print -r -- "$*" >> "$MOCK_ROOT/calls"
print -r -- "${HOMEBREW_CURL_SPEED_LIMIT:-}|${HOMEBREW_CURL_SPEED_TIME:-}|${HOMEBREW_NO_AUTO_UPDATE:-}|${HOMEBREW_NO_INSTALL_CLEANUP:-}|${GIT_TERMINAL_PROMPT:-}" >> "$MOCK_ROOT/env"
print -r -- "${HOMEBREW_GIT_PATH-unset}|${GIT_EXECUTABLE-unset}" >> "$MOCK_ROOT/git-env"
[[ -f "${HOMEBREW_CURLRC:-}" ]] && /bin/cat "$HOMEBREW_CURLRC" >> "$MOCK_ROOT/configs"
integer attempt=0
[[ -f "$MOCK_ROOT/attempt" ]] && read -r attempt < "$MOCK_ROOT/attempt"
(( attempt += 1 ))
print -r -- "$attempt" > "$MOCK_ROOT/attempt"
case "${MOCK_BREW_MODE:-ok}" in
  recover) (( attempt > 1 )) && exit 0 ;;
  api-recover) [[ "${HOMEBREW_NO_INSTALL_FROM_API:-}" == 1 ]] && exit 0 ;;
  ok) exit 0 ;;
  permission) print -r -- 'Error: Permission denied' >&2; exit 1 ;;
  certificate) print -r -- 'curl: (60) SSL certificate problem: certificate verify failed' >&2; exit 60 ;;
  locked|lock-recover)
    if [[ "$MOCK_BREW_MODE" == locked ]] || (( attempt == 1 )); then
      print -r -- 'lockf: 200: already locked' >&2
      print -r -- 'Error: Another `brew update` process is already running.' >&2
      exit 1
    fi
    /usr/bin/lockf -k -s -t 0 "$MOCK_ROOT/prefix/var/homebrew/locks/update" /usr/bin/true || exit 1
    exit 0
    ;;
  upgrade-failure)
    case "$1" in
      update|doctor|-v) exit 0 ;;
    esac
    ;;
  masked) print -r -- 'Error: Failed to download resource "qtwebengine"' >&2; exit 0 ;;
esac
if [[ "${MOCK_BREW_MODE:-}" == api-recover ]]; then
  print -r -- 'Error: Failed to download https://formulae.brew.sh/api/formula.jws.json' >&2
else
  print -r -- "fatal: unable to access 'https://github.com/Homebrew/brew/': Failed to connect" >&2
fi
exit 128
MOCK_BREW
  /bin/chmod +x "$TEST_ROOT/bin/brew"
}
# 覆盖环境探测，所有网络请求和包管理器均留在隔离夹具内。
install_safe_wrappers() {
  function jobs_update_select_preferred_ip_family() {
    JOBS_UPDATE_IPV4_PROBE_SPEED=140000
    JOBS_UPDATE_IPV6_PROBE_SPEED=460000
    JOBS_UPDATE_PREFERRED_IP_FAMILY=ipv6
    JOBS_UPDATE_SECONDARY_IP_FAMILY=ipv4
  }
  function jobs_update_start_brew_progress_monitor() { return 0; }
  function find_brew_bin() { print -r -- "$MOCK_ROOT/bin/brew"; }
  function require_brew_or_skip() { return 0; }
  function jobs_update_trust_configured_brew_taps() { return 0; }
  function _jobs_python_has_authorization() { return 0; }
  function jobs_brew_activate() { return 0; }
  function brew_cask_local_app_path() {
    [[ "$1" == vlc ]] && print -r -- "$MOCK_ROOT/VLC.app"
  }
}
# 脚本退出时清理；不在初始化函数内注册局部 EXIT trap。
TRAPEXIT() {
  cleanup_tests
}
# 每个用例清空状态，保留原命令和网络策略函数供实际调用。
reset_fixture() {
  jobs_update_cleanup_network_strategy
  unset HOMEBREW_CURLRC HOMEBREW_GIT_PATH GIT_EXECUTABLE
  unset JOBS_UPDATE_BREW_LOCK_TIMEOUT_SECONDS
  JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET=0
  JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC=''
  JOBS_UPDATE_BREW_CURLRC=''
  JOBS_UPDATE_LAST_BREW_OUTPUT_FILE=''
  JOBS_UPDATE_NETWORK_READY=0
  JOBS_UPDATE_BREW_UPDATE_RESULTS=()
  JOBS_UPDATE_FAILURE_COUNT=0
  JOBS_UPDATE_SKIP_COUNT=0
  JOBS_UPDATE_COMMAND_COUNT=0
  JOBS_UPDATE_FAILED_STEPS=0
  JOBS_UPDATE_FAILED_DESCRIPTIONS=()
  JOBS_UPDATE_DEFER_BREW_FAILURE=0
  export MOCK_BREW_MODE=ok
  export JOBS_HOMEBREW_BIN="$TEST_ROOT/bin/brew"
  LOG_FILE="$TEST_ROOT/run.log"
  : > "$LOG_FILE"
  : > "$TEST_ROOT/calls"
  : > "$TEST_ROOT/env"
  : > "$TEST_ROOT/configs"
  : > "$TEST_ROOT/git-env"
  print -r -- 0 > "$TEST_ROOT/attempt"
  unset _JOBS_PYTHON_UPDATED_BREWS
}
# 只创建临时 App 元数据，不能碰真实 /Applications。
prepare_manual_app_fixture() {
  export MOCK_BREW_MODE=manual-app
  /bin/mkdir -p "$TEST_ROOT/VLC.app/Contents"
  /bin/cat > "$TEST_ROOT/VLC.app/Contents/Info.plist" <<'APP_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>3.0.24</string>
<key>CFBundleVersion</key><string>3.0.24</string>
</dict></plist>
APP_PLIST
  print -r -- '{"casks":[{"token":"vlc","version":"3.0.24","bundle_version":"3.0.24","bundle_short_version":"3.0.24","artifacts":[{"app":["VLC.app"]}]}]}' > "$TEST_ROOT/cask.json"
}
# 检查调用次数与最终状态，避免只匹配展示文案。
assert_equal() {
  [[ "$1" == "$2" ]] && return 0
  print -u2 -r -- "期望[$1]，实际[$2]"
  return 1
}
# 高速 API 测速不得提高 bottle 的停滞门槛。
test_stall_guard() {
  JOBS_UPDATE_IPV6_PROBE_SPEED=99999999
  assert_equal 1 "$(jobs_update_adaptive_low_speed_limit_for_family ipv6)" || return 1
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade || return 1
  /usr/bin/grep -Fxq '1|60|1|1|0' "$TEST_ROOT/env" || return 1
  /usr/bin/grep -Fxq -- '--speed-limit 1' "$TEST_ROOT/configs"
}
# 首轮失败后恢复不计最终失败，curl 协议会变更。
test_recovered_retry() {
  export MOCK_BREW_MODE=recover
  jobs_update_run_brew_adaptive_cmd fixture yes brew upgrade || return 1
  assert_equal 2 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  /usr/bin/grep -Fxq -- '--ipv6' "$TEST_ROOT/configs" || return 1
  /usr/bin/grep -Fxq -- '--ipv4' "$TEST_ROOT/configs"
}
# 不可达网络只尝试三次，最终失败只登记一次。
test_offline_bounded() {
  export MOCK_BREW_MODE=offline
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade && return 1
  assert_equal 3 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  /usr/bin/grep -Fxq '1|120|1|1|0' "$TEST_ROOT/env"
}
# 安装权限错误不能用重复下载处理。
test_permission_no_retry() {
  export MOCK_BREW_MODE=permission
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade && return 1
  assert_equal 1 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 证书错误需要修复信任链，不能靠切换 IP 协议重复尝试。
test_certificate_no_retry() {
  export MOCK_BREW_MODE=certificate
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade && return 1
  assert_equal 1 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 命令成功但日志目标无法写入时也必须返回失败。
test_log_write_failure() {
  LOG_FILE="$TEST_ROOT"
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade && return 1
  assert_equal 1 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 明确下载失败即使退出零也不能报告完成。
test_masked_download_failure() {
  export MOCK_BREW_MODE=masked
  jobs_update_run_brew_adaptive_cmd fixture plain brew upgrade && return 1
  assert_equal 3 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 全局和 Python 自检共享同一成功索引，避免再次裸 brew update。
test_python_reuses_index() {
  jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN" || return 1
  _jobs_python_update_brew_once || return 1
  assert_equal 1 "$(<"$TEST_ROOT/attempt")"
}
# Homebrew update 的 Shell Git 必须实际指向入口，并且不向父环境泄漏。
test_update_git_wrapper() {
  local expected_wrapper="${SCRIPT_DIR:h}/_lib/jobs_git_network_strategy/bin/git"
  jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN" || return 1
  /usr/bin/grep -Fxq "$expected_wrapper|$expected_wrapper" "$TEST_ROOT/git-env" || return 1
  (( ! ${+HOMEBREW_GIT_PATH} && ! ${+GIT_EXECUTABLE} ))
}
# 显式 Git 路径和显式空值都不能被脚本的默认入口覆盖。
test_preserve_explicit_git() {
  local expected
  for expected in '' '/explicit git'; do
    reset_fixture
    export HOMEBREW_GIT_PATH="$expected" GIT_EXECUTABLE="$expected"
    jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN" || return 1
    /usr/bin/grep -Fxq "$expected|$expected" "$TEST_ROOT/git-env" || return 1
    assert_equal "$expected" "$HOMEBREW_GIT_PATH" || return 1
    assert_equal "$expected" "$GIT_EXECUTABLE" || return 1
  done
}
# 真正持有本地系统锁，证明等待释放后成功且原锁文件和内容仍在。
test_lock_release_recovers() {
  local lock_file="$TEST_ROOT/prefix/var/homebrew/locks/update"
  print -r -- 'preserve-lock' > "$lock_file"
  /usr/bin/lockf -k -s -t 0 "$lock_file" /bin/zsh -c 'print ready > "$MOCK_ROOT/lock-ready"; sleep 0.4' &
  TEST_LOCK_HOLDER_PID=$!
  while [[ ! -f "$TEST_ROOT/lock-ready" ]]; do sleep 0.05; done
  export MOCK_BREW_MODE=lock-recover JOBS_UPDATE_BREW_LOCK_TIMEOUT_SECONDS=3
  jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN" || return 1
  wait "$TEST_LOCK_HOLDER_PID" || return 1
  TEST_LOCK_HOLDER_PID=''
  /bin/rm -f "$TEST_ROOT/lock-ready"
  assert_equal 2 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  assert_equal preserve-lock "$(<"$lock_file")" || return 1
  _jobs_python_update_brew_once || return 1
  assert_equal 2 "$(<"$TEST_ROOT/attempt")"
}
# 锁持续占用只等待到时限，不能杀持锁进程、删除锁或绕过索引门禁。
test_lock_timeout_preserves_owner() {
  local lock_file="$TEST_ROOT/prefix/var/homebrew/locks/update"
  print -r -- 'preserve-lock' > "$lock_file"
  /usr/bin/lockf -k -s -t 0 "$lock_file" /bin/zsh -c 'print ready > "$MOCK_ROOT/lock-ready"; sleep 2' &
  TEST_LOCK_HOLDER_PID=$!
  while [[ ! -f "$TEST_ROOT/lock-ready" ]]; do sleep 0.05; done
  export MOCK_BREW_MODE=locked JOBS_UPDATE_BREW_LOCK_TIMEOUT_SECONDS=1
  jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN" && return 1
  kill -0 "$TEST_LOCK_HOLDER_PID" || return 1
  _jobs_python_update_brew_once && return 1
  assert_equal 1 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  assert_equal preserve-lock "$(<"$lock_file")" || return 1
  wait "$TEST_LOCK_HOLDER_PID" || return 1
  TEST_LOCK_HOLDER_PID=''
  /bin/rm -f "$TEST_ROOT/lock-ready"
}
# 已释放却反复报锁错误时最多补试一次，不把锁误当下载错误换线。
test_repeated_lock_is_bounded() {
  export MOCK_BREW_MODE=locked
  jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN" && return 1
  assert_equal 2 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 手动安装但版本确证最新时只核验，不接管、覆盖、安装或升级 App。
test_manual_app_current() {
  prepare_manual_app_fixture
  jobs_update_brew_cask_one vlc || return 1
  assert_equal 0 "$JOBS_UPDATE_SKIP_COUNT" || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  /usr/bin/grep -Fq '版本 3.0.24 已与 Homebrew 当前稳定版本核对一致' "$LOG_FILE" || return 1
  ! /usr/bin/grep -Eq '^(install|upgrade|reinstall|adopt)' "$TEST_ROOT/calls"
}
# 本地版本落后和独立构建号都不能据短版本号误报已完成。
test_manual_app_version_mismatch() {
  local key value
  for key value in CFBundleShortVersionString 3.0.23 CFBundleVersion 999; do
    reset_fixture
    prepare_manual_app_fixture
    /usr/bin/plutil -replace "$key" -string "$value" "$TEST_ROOT/VLC.app/Contents/Info.plist" || return 1
    jobs_update_brew_cask_one vlc || return 1
    assert_equal 1 "$JOBS_UPDATE_SKIP_COUNT" || return 1
    ! /usr/bin/grep -Fq '已与 Homebrew 当前稳定版本核对一致' "$LOG_FILE" || return 1
  done
}
# latest、多段版本、错误对象和坏 JSON 均保守跳过，不能无条件消除未完成。
test_manual_app_invalid_metadata() {
  local metadata
  for metadata in \
    '{"casks":[{"token":"vlc","version":"latest","artifacts":[{"app":["VLC.app"]}]}]}' \
    '{"casks":[{"token":"vlc","version":"3.0.24,1","artifacts":[{"app":["VLC.app"]}]}]}' \
    '{"casks":[{"token":"vlc","version":"3.0.24","bundle_version":"999","artifacts":[{"app":["VLC.app"]}]}]}' \
    '{"casks":[{"token":"other","version":"3.0.24","artifacts":[{"app":["VLC.app"]}]}]}' \
    '{"casks":[{"token":"vlc","version":"3.0.24","artifacts":[{"app":["Other.app"]}]}]}' \
    '{"casks":[]}' 'invalid json'; do
    reset_fixture
    prepare_manual_app_fixture
    print -r -- "$metadata" > "$TEST_ROOT/cask.json"
    jobs_update_brew_cask_one vlc || return 1
    assert_equal 1 "$JOBS_UPDATE_SKIP_COUNT" || return 1
    ! /usr/bin/grep -Fq '已与 Homebrew 当前稳定版本核对一致' "$LOG_FILE" || return 1
  done
}
# 同轮失败索引不被再次获取，也不进入下游升级。
test_failed_index_stops_downstream() {
  export MOCK_BREW_MODE=offline
  jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN" && return 1
  _jobs_python_update_brew_once && return 1
  jobs_update_brew_formula_one ruby && return 1
  assert_equal 3 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# API 降级成功时清除中间尝试的失败语义。
test_api_fallback_recovers() {
  export MOCK_BREW_MODE=api-recover
  jobs_update_run_brew_update "$JOBS_HOMEBREW_BIN" || return 1
  assert_equal 2 "$(<"$TEST_ROOT/attempt")" || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 升级失败必须保留缓存并跳过显式 cleanup。
test_no_cleanup_after_failure() {
  export MOCK_BREW_MODE=upgrade-failure
  jobs_update_homebrew && return 1
  /usr/bin/grep -Fxq upgrade "$TEST_ROOT/calls" || return 1
  /usr/bin/grep -Fxq doctor "$TEST_ROOT/calls" || return 1
  ! /usr/bin/grep -Fxq cleanup "$TEST_ROOT/calls"
}
# curl 设置的原始未设置、空值和文件路径均需精确还原。
test_restore_curlrc() {
  local mode expected_file
  for mode in unset empty file; do
    reset_fixture
    case "$mode" in
      unset) unset HOMEBREW_CURLRC ;;
      empty) export HOMEBREW_CURLRC='' ;;
      file)
        expected_file="$TEST_ROOT/original config"
        print -r -- '--retry 1' > "$expected_file"
        export HOMEBREW_CURLRC="$expected_file"
        ;;
    esac
    jobs_update_ensure_network_strategy || return 1
    local temporary_file="$JOBS_UPDATE_BREW_CURLRC"
    jobs_update_cleanup_network_strategy
    [[ ! -e "$temporary_file" ]] || return 1
    case "$mode" in
      unset) (( ! ${+HOMEBREW_CURLRC} )) || return 1 ;;
      empty) (( ${+HOMEBREW_CURLRC} )) && [[ -z "$HOMEBREW_CURLRC" ]] || return 1 ;;
      file) assert_equal "$expected_file" "$HOMEBREW_CURLRC" || return 1 ;;
    esac
  done
}
# 独立记录各场景，失败时展示被测日志。
run_tests() {
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "${TEST_SCRIPT_DIR:h}/【MacOS】update.command" || return 1
  install_safe_wrappers
  local name
  for name in test_stall_guard test_recovered_retry test_offline_bounded test_permission_no_retry test_certificate_no_retry test_log_write_failure test_masked_download_failure test_python_reuses_index test_update_git_wrapper test_preserve_explicit_git test_lock_release_recovers test_lock_timeout_preserves_owner test_repeated_lock_is_bounded test_manual_app_current test_manual_app_version_mismatch test_manual_app_invalid_metadata test_failed_index_stops_downstream test_api_fallback_recovers test_no_cleanup_after_failure test_restore_curlrc; do
    reset_fixture
    if "$name" > "$TEST_ROOT/output" 2>&1; then
      (( TEST_PASSED += 1 ))
      print -r -- "PASS $name"
    else
      (( TEST_FAILED += 1 ))
      print -r -- "FAIL $name"
      /bin/cat "$TEST_ROOT/output"
    fi
  done
  print -r -- "Homebrew 隔离回归：$TEST_PASSED passed，$TEST_FAILED failed"
  (( TEST_FAILED == 0 ))
}
# 编排隔离环境及回归用例。
main() {
  initialize_tests # 展示测试边界并加载只供 source 的被测函数。
  run_tests # 验证下载重试、缓存门禁和环境恢复。
}
main "$@"
