#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】cocoapods_network_tests.zsh
# - 核心用途：隔离验证 CocoaPods 选源、刷新和包管理器升级分支。
# - 影响范围：仅创建专属临时目录；curl、git、pod、brew、gem 均使用假命令。
# - 运行提示：自动执行回归，不联网、不安装、不升级；按 Ctrl+C 可取消。

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
TEST_UPDATE_SCRIPT="${TEST_SCRIPT_DIR:h}/【MacOS】update.command"
TEST_ROOT=''
TEST_PASSED=0
TEST_FAILED=0
TEST_TOTAL=0
TEST_ORIGINAL_RUN_CMD=''

# 说明隔离边界，避免把模拟成功误认为真实网络验收。
show_test_intro() {
  print -r -- 'CocoaPods 网络与升级隔离回归'
  print -r -- '仅运行临时目录中的假命令，不联网、不安装、不升级。按 Ctrl+C 可取消。'
}
# 回收测试自建进程，防止被测超时逻辑回归后留下挂起夹具。
terminate_mock_processes() {
  local process_id
  [[ -n "$TEST_ROOT" && -f "$TEST_ROOT/processes" ]] || return 0
  while IFS= read -r process_id; do
    [[ "$process_id" == <-> && "$process_id" -gt 1 ]] || continue
    kill -KILL "$process_id" 2>/dev/null || true
  done < "$TEST_ROOT/processes"
}
# 只删除本测试生成的临时目录。
cleanup_tests() {
  terminate_mock_processes
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" && "${TEST_ROOT:t}" == jobs-update-tests.* ]]; then
    /bin/rm -r -- "$TEST_ROOT"
  fi
}
# 创建模拟命令，真实网络和包管理器命令不会进入执行链。
create_mock_commands() {
  /bin/mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/runtime" "$TEST_ROOT/gems"
  /bin/cat > "$TEST_ROOT/bin/curl" <<'MOCK_CURL'
#!/bin/zsh
setopt NO_NOMATCH
local target='' url='' argument candidate mode duration delay
print -r -- "curl|${(j: :)@}" >> "$MOCK_ROOT/calls"
while (( $# > 0 )); do
  argument="$1"
  shift
  case "$argument" in
    --output|-o) target="$1"; shift ;;
    --connect-timeout|--max-time|--write-out|--header) shift ;;
    --head|-I) print -r -- 'HEAD request is forbidden' >&2; exit 97 ;;
    https://*) url="$argument" ;;
  esac
done
if [[ "$url" == https://api.github.com/repos/CocoaPods/Specs/commits/master ]]; then
  print -r -- api >> "$MOCK_ROOT/api-probes"
  case "${MOCK_API_MODE:-valid}" in
    fail) exit 28 ;;
    html) print -r -- '<html>portal</html>' > "$target" ;;
    json) print -r -- '{"sha":"1234567890123456789012345678901234567890"}' > "$target" ;;
    invalid-length) print -r -- 1234567890 > "$target" ;;
    sha64) print -r -- 1234567890123456789012345678901234567890123456789012345678901234 > "$target" ;;
    empty) : > "$target" ;;
    hang)
      print -r -- "$$" >> "$MOCK_ROOT/processes"
      /bin/sleep 30 &
      print -r -- "$!" >> "$MOCK_ROOT/processes"
      wait
      ;;
    *) print -r -- 1234567890123456789012345678901234567890 > "$target" ;;
  esac
  print -rn -- "${MOCK_API_STATUS:-200}"
  exit 0
fi
[[ "$url" == *'/Specs/a/7/5/AFNetworking/4.0.1/AFNetworking.podspec.json' ]] || exit 96
candidate=cdn
[[ "$url" == https://raw.githubusercontent.com/* ]] && candidate=git
print -r -- "$candidate" >> "$MOCK_ROOT/probes"
: > "$MOCK_ROOT/$candidate.started"
if [[ "${MOCK_PROBE_BARRIER:-0}" == 1 ]]; then
  local other=git attempt
  [[ "$candidate" == git ]] && other=cdn
  for attempt in {1..30}; do
    [[ -f "$MOCK_ROOT/$other.started" ]] && break
    /bin/sleep 0.03
  done
  [[ -f "$MOCK_ROOT/$other.started" ]] || exit 95
fi
mode="${MOCK_CDN_MODE:-valid}"
duration="${MOCK_CDN_TIME:-1.0}"
delay="${MOCK_CDN_DELAY:-0}"
if [[ "$candidate" == git ]]; then
  mode="${MOCK_GIT_MODE:-valid}"
  duration="${MOCK_GIT_TIME:-1.0}"
  delay="${MOCK_GIT_DELAY:-0}"
  [[ -f "$MOCK_ROOT/refresh-started" && "${MOCK_FALLBACK_GIT_MODE:-}" == fail ]] && mode=fail
fi
if [[ "$mode" == hang ]]; then
  print -r -- "$$" >> "$MOCK_ROOT/processes"
  /bin/sleep 30 &
  print -r -- "$!" >> "$MOCK_ROOT/processes"
  wait
  exit 94
fi
[[ "$delay" != 0 ]] && /bin/sleep "$delay"
case "$mode" in
  fail) exit 28 ;;
  html) print -r -- '<html>"name":"AFNetworking","version":"4.0.1"</html>' > "$target" ;;
  malformed) print -r -- '{"name":"AFNetworking","version":"4.0.1",' > "$target" ;;
  wrong-version) print -r -- '{"name":"AFNetworking","version":"9.0"}' > "$target" ;;
  embedded-fields) print -r -- '{"notice":"\"name\":\"AFNetworking\",\"version\":\"4.0.1\""}' > "$target" ;;
  empty) : > "$target" ;;
  *) print -r -- '{"name":"AFNetworking","version":"4.0.1","source":{"git":"https://github.com/AFNetworking/AFNetworking.git","tag":"4.0.1"}}' > "$target" ;;
esac
print -rn -- "$duration"
MOCK_CURL
  /bin/cat > "$TEST_ROOT/bin/git" <<'MOCK_GIT'
#!/bin/zsh
print -r -- "git|${(j: :)@}" >> "$MOCK_ROOT/calls"
[[ "$*" == *'ls-remote --exit-code https://github.com/CocoaPods/Specs.git HEAD' ]] || exit 91
[[ "${GIT_TERMINAL_PROMPT:-}" == 0 && "${GIT_ASKPASS:-}" == /usr/bin/false && "${GCM_INTERACTIVE:-}" == never ]] || exit 90
case "${MOCK_GIT_PROTOCOL:-valid}" in
  fail) exit 128 ;;
  invalid) print -r -- '<html>HEAD</html>' ;;
  hang)
    print -r -- "$$" >> "$MOCK_ROOT/processes"
    /bin/sleep 30 &
    print -r -- "$!" >> "$MOCK_ROOT/processes"
    wait
    ;;
  *) print -r -- '1234567890123456789012345678901234567890	HEAD' ;;
esac
MOCK_GIT
  /bin/cat > "$TEST_ROOT/bin/pod" <<'MOCK_POD'
#!/bin/zsh
print -r -- "pod|${(j: :)@}" >> "$MOCK_ROOT/calls"
print -r -- "${(j: :)@}|${COCOAPODS_CDN_MAX_CONCURRENCY-unset}" >> "$MOCK_ROOT/concurrency"
if [[ "$*" == 'repo list --no-ansi' ]]; then
  /bin/cat "$MOCK_ROOT/repos"
  exit "${MOCK_REPO_LIST_RESULT:-0}"
fi
[[ "$1" == repo && ( "$2" == update || "$2" == add-cdn ) ]] || exit 89
[[ "${GIT_TERMINAL_PROMPT:-}" == 0 && "${GIT_ASKPASS:-}" == /usr/bin/false && "${GCM_INTERACTIVE:-}" == never ]] || exit 88
[[ "$2" == update ]] && : > "$MOCK_ROOT/refresh-started"
if [[ "$2" == update && ( "${MOCK_POD_ERROR_REPO:-}" == "$3" || "${MOCK_POD_ERROR_REPO:-}" == '*' ) ]]; then
  print -r -- "${MOCK_POD_ERROR_TEXT:-}" >&2
  exit "${MOCK_POD_ERROR_RESULT:-1}"
fi
if [[ "${MOCK_POD_HANG:-0}" == 1 ]]; then
  print -r -- "$$" >> "$MOCK_ROOT/processes"
  /bin/sleep 30 &
  print -r -- "$!" >> "$MOCK_ROOT/processes"
  wait
fi
exit "${MOCK_POD_RESULT:-0}"
MOCK_POD
  /bin/cat > "$TEST_ROOT/bin/brew" <<'MOCK_BREW'
#!/bin/zsh
print -r -- "brew|${(j: :)@}" >> "$MOCK_ROOT/calls"
case "$*" in
  'list --formula --versions cocoapods') exit "${MOCK_BREW_INSTALLED_RESULT:-0}" ;;
  '--prefix cocoapods') print -r -- "${MOCK_BREW_PREFIX:-$MOCK_ROOT}" ;;
  'upgrade cocoapods') exit "${MOCK_BREW_UPGRADE_RESULT:-0}" ;;
  *) exit 87 ;;
esac
MOCK_BREW
  /bin/cat > "$TEST_ROOT/bin/gem" <<'MOCK_GEM'
#!/bin/zsh
print -r -- "gem|${(j: :)@}" >> "$MOCK_ROOT/calls"
case "$*" in
  'list -i ^cocoapods$') exit "${MOCK_GEM_INSTALLED_RESULT:-0}" ;;
  'env home') print -r -- "${MOCK_GEM_HOME:-$MOCK_ROOT/gems}" ;;
  'env')
    print -r -- "  - INSTALLATION DIRECTORY: ${MOCK_GEM_HOME:-$MOCK_ROOT/gems}"
    print -r -- "  - EXECUTABLE DIRECTORY: $MOCK_ROOT/bin"
    print -r -- "  - RUBY EXECUTABLE: $MOCK_ROOT/bin/ruby"
    ;;
  'env user_gemhome'|'env path') print -r -- "$MOCK_ROOT/usergems" ;;
  'update cocoapods --no-user-install --install-dir '*) exit "${MOCK_GEM_UPDATE_RESULT:-0}" ;;
  *) exit 86 ;;
esac
MOCK_GEM
  /bin/chmod +x "$TEST_ROOT/bin/curl" "$TEST_ROOT/bin/git" "$TEST_ROOT/bin/pod" "$TEST_ROOT/bin/brew" "$TEST_ROOT/bin/gem"
}
# 初始化专属运行目录，并通过 source 接口加载函数。
initialize_tests() {
  setopt NO_NOMATCH
  zmodload zsh/datetime
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-update-tests.XXXXXXXX")" || return 1
  export MOCK_ROOT="$TEST_ROOT"
  create_mock_commands
  export PATH="$TEST_ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  export TMPDIR="$TEST_ROOT/runtime"
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "$TEST_UPDATE_SCRIPT" || return 1
  TEST_ORIGINAL_RUN_CMD="${functions[jobs_update_run_cmd]}"
  LOG_FILE="$TEST_ROOT/test.log"
}
# 固定包发现及运行包装器，禁止从宿主默认目录发现真实 Homebrew。
install_safe_wrappers() {
  function jobs_update_pod_network_prepare() {
    return 0
  }
  function jobs_update_repair_gem_extensions() {
    return 0
  }
  function jobs_gemext_find_ruby() {
    print -r -- "$MOCK_ROOT/bin/ruby"
  }
  function jobs_update_gem() {
    gem "$@"
  }
  function find_brew_bin() {
    [[ "${MOCK_BREW_PRESENT:-1}" == 1 ]] || return 1
    print -r -- "$MOCK_ROOT/bin/brew"
  }
  function jobs_update_has() {
    case "$1" in
      gem|ruby) [[ "${MOCK_GEM_PRESENT:-1}" == 1 ]] ;;
      pod) [[ "${MOCK_POD_PRESENT:-1}" == 1 ]] ;;
      *) command -v "$1" >/dev/null 2>&1 ;;
    esac
  }
  function jobs_update_run_cmd() {
    shift
    "$@"
  }
  function jobs_update_run_brew_adaptive_cmd() {
    print -r -- "adaptive|$1|$2" >> "$MOCK_ROOT/calls"
    shift 2
    "$@"
  }
  function jobs_update_run_brew_update() {
    print -r -- 'brew-index-refresh' >> "$MOCK_ROOT/calls"
    return "${MOCK_BREW_INDEX_RESULT:-0}"
  }
  function jobs_update_run_sudo_cmd() {
    print -r -- "sudo-wrapper|$1" >> "$MOCK_ROOT/calls"
    shift
    "$@"
  }
  function warn_echo() { print -r -- "$*" >&2; }
  function info_echo() { print -r -- "$*" >&2; }
}
# 每个场景重新建立可控默认值，上一场景不能污染后续结果。
reset_fixture() {
  terminate_mock_processes
  export MOCK_CDN_MODE=valid MOCK_GIT_MODE=valid MOCK_CDN_TIME=1.0 MOCK_GIT_TIME=1.0
  export MOCK_CDN_DELAY=0 MOCK_GIT_DELAY=0 MOCK_PROBE_BARRIER=0 MOCK_GIT_PROTOCOL=valid
  export MOCK_API_MODE=valid MOCK_API_STATUS=200
  export MOCK_POD_HANG=0 MOCK_POD_RESULT=0 MOCK_REPO_LIST_RESULT=0
  export MOCK_POD_ERROR_REPO='' MOCK_POD_ERROR_TEXT='' MOCK_POD_ERROR_RESULT=1
  export MOCK_FALLBACK_GIT_MODE=''
  unset MOCK_FIRST_REFRESH_RESULT MOCK_SECOND_REFRESH_RESULT
  export MOCK_BREW_PRESENT=1 MOCK_BREW_INSTALLED_RESULT=0 MOCK_BREW_UPGRADE_RESULT=0 MOCK_BREW_INDEX_RESULT=0 MOCK_BREW_PREFIX="$TEST_ROOT"
  export MOCK_GEM_PRESENT=1 MOCK_GEM_INSTALLED_RESULT=0 MOCK_GEM_UPDATE_RESULT=0 MOCK_GEM_HOME="$TEST_ROOT/gems"
  export MOCK_POD_PRESENT=1 MOCK_SPECS_RESULT=0 JOBS_SPECS_SOURCE=auto
  export JOBS_SPECS_PROBE_TIMEOUT=8 JOBS_SPECS_CONNECT_TIMEOUT=2 JOBS_SPECS_UPDATE_TIMEOUT=8
  unset COCOAPODS_CDN_MAX_CONCURRENCY
  JOBS_UPDATE_COCOAPODS_BREW_UPDATED=0
  JOBS_UPDATE_FAILURE_COUNT=0 JOBS_UPDATE_SKIP_COUNT=0 JOBS_UPDATE_COMMAND_COUNT=0
  JOBS_UPDATE_FAILED_STEPS=0 JOBS_UPDATE_PARTIAL_STEPS=0 JOBS_UPDATE_SKIPPED_STEPS=0 JOBS_UPDATE_SUCCEEDED_STEPS=0
  JOBS_UPDATE_FAILED_DESCRIPTIONS=()
  : > "$TEST_ROOT/calls"
  : > "$TEST_ROOT/probes"
  : > "$TEST_ROOT/api-probes"
  : > "$TEST_ROOT/processes"
  : > "$TEST_ROOT/test.log"
  : > "$TEST_ROOT/concurrency"
  /bin/rm -f -- "$TEST_ROOT/cdn.started" "$TEST_ROOT/git.started" "$TEST_ROOT/refresh-started" "$TEST_ROOT/first-refresh" "$TEST_ROOT/timer-stop-exercised"
  print -r -- $'private-repo\n- Type: git\n- URL: https://example.invalid/private-specs.git\n\npublic-alias\n- Type: CDN\n- URL: https://cdn.cocoapods.org/\n' > "$TEST_ROOT/repos"
}
# 输出断言失败的实际值，便于定位被测分支。
assert_equal() {
  [[ "$1" == "$2" ]] && return 0
  print -r -- "期望：[$1]；实际：[$2]；${3:-值不相等}" >&2
  return 1
}
# 核对操作日志包含预期整行，避免子串命中造成假通过。
assert_call() {
  /usr/bin/grep -Fxq -- "$1" "$TEST_ROOT/calls" && return 0
  print -r -- "缺少命令：$1" >&2
  /bin/cat "$TEST_ROOT/calls" >&2
  return 1
}
# 核对操作日志没有禁止出现的命令片段。
assert_no_call() {
  /usr/bin/grep -Fq -- "$1" "$TEST_ROOT/calls" || return 0
  print -r -- "不应执行：$1" >&2
  /bin/cat "$TEST_ROOT/calls" >&2
  return 1
}
# 确认所有探测临时目录均已由被测代码回收。
assert_no_probe_temp() {
  local -a remaining=("$TMPDIR"/jobs-update-specs.*(N) "$TMPDIR"/jobs-update-specs-outcome.*(N) "$TMPDIR"/jobs-update-specs-repo.*(N))
  assert_equal 0 "${#remaining}" '探测临时目录未回收'
}
# 检查超时夹具进程已结束；短暂僵尸态不视为存活工作进程。
assert_no_live_mock_processes() {
  local process_id process_state
  while IFS= read -r process_id; do
    [[ "$process_id" == <-> ]] || continue
    process_state="$(/bin/ps -p "$process_id" -o stat= 2>/dev/null)"
    if [[ -n "$process_state" && "$process_state" != Z* ]]; then
      print -r -- "超时后仍存活的模拟进程：$process_id ($process_state)" >&2
      return 1
    fi
  done < "$TEST_ROOT/processes"
}
# 捕获选源输出及状态，失败时 stdout 必须为空。
assert_selection() {
  local selected selection_result=0
  selected="$(jobs_update_specs_select_source 2> "$TEST_ROOT/selector.stderr")" || selection_result=$?
  assert_equal "$1" "$selection_result" '选源退出码' || return 1
  assert_equal "$2" "$selected" '选源 stdout 必须只有源名' || return 1
  assert_no_probe_temp
}
# 两源健康且 Git 优势不足时保留 CDN。
test_cdn_default() { assert_selection 0 cdn; }
# Git GET 快过 CDN 15% 时允许优先 Git。
test_git_faster() { export MOCK_GIT_TIME=0.84; assert_selection 0 git; }
# 15% 阈值边界仍选择 CDN，避免轻微抖动切源。
test_git_threshold() { export MOCK_GIT_TIME=0.85; assert_selection 0 cdn; }
# CDN 失败时回退通过 HTTP 与 Git 协议检查的 Git。
test_cdn_failure() { export MOCK_CDN_MODE=fail; assert_selection 0 git; }
# Git 的 HTTP 可达不代表 Git 仓库协议可用。
test_git_protocol_failure() { export MOCK_GIT_TIME=0.1 MOCK_GIT_PROTOCOL=fail; assert_selection 0 cdn; }
# Git 协议响应必须包含有效 HEAD，不能只看退出码。
test_git_protocol_invalid() { export MOCK_CDN_MODE=fail MOCK_GIT_PROTOCOL=invalid; assert_selection 1 ''; }
# 双源均失败时不返回可用于刷新的源。
test_both_failure() { export MOCK_CDN_MODE=fail MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# 显式指定 CDN 后不可因不健康悄悄改选 Git。
test_forced_cdn_failure() { export JOBS_SPECS_SOURCE=cdn MOCK_CDN_MODE=fail; assert_selection 1 ''; }
# 显式指定 Git 后不可因不健康悄悄改选 CDN。
test_forced_git_failure() { export JOBS_SPECS_SOURCE=git MOCK_GIT_PROTOCOL=fail; assert_selection 1 ''; }
# 显式指定的健康 Git 不受 CDN 耗时优势影响。
test_forced_git() { export JOBS_SPECS_SOURCE=git MOCK_GIT_TIME=5.0; assert_selection 0 git; }
# Raw 和 Git 协议健康仍不足以选择 Git；真正刷新所需 API 必须可用。
test_git_api_unavailable_selects_cdn() {
  export MOCK_GIT_TIME=0.1 MOCK_API_MODE=fail
  assert_selection 0 cdn || return 1
  assert_call 'git|-c credential.interactive=false ls-remote --exit-code https://github.com/CocoaPods/Specs.git HEAD' || return 1
  assert_equal api "$(< "$TEST_ROOT/api-probes")"
}
# API 非200、门户、空响应或普通JSON均不得冒充版本SHA。
test_git_api_invalid_payload() {
  local mode
  export MOCK_CDN_MODE=fail
  for mode in html json invalid-length empty; do
    export MOCK_API_MODE="$mode"
    assert_selection 1 '' || return 1
  done
  export MOCK_API_MODE=valid MOCK_API_STATUS=302
  assert_selection 1 ''
}
# GitHub API 的两种对象ID长度都必须以完整响应返回。
test_git_api_sha_lengths() {
  export JOBS_SPECS_SOURCE=git
  assert_selection 0 git || return 1
  export MOCK_API_MODE=sha64
  assert_selection 0 git || return 1
  /usr/bin/grep -Fq -- '--header Accept: application/vnd.github.v3.sha --header User-Agent: CocoaPods' "$TEST_ROOT/calls"
}
# API 挂起也属于同一Git候选墙钟时限，结束后回收传输进程。
test_git_api_timeout() {
  export JOBS_SPECS_PROBE_TIMEOUT=1 MOCK_API_MODE=hang MOCK_CDN_MODE=fail
  assert_selection 1 '' || return 1
  assert_no_live_mock_processes
}
# 门户 HTML 即使带 name/version 文本，也不得识别为有效样本。
test_html_payload() { export MOCK_CDN_MODE=html MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# 非完整 JSON 即使包含正确字段，也不得识别为有效样本。
test_malformed_payload() { export MOCK_CDN_MODE=malformed MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# 普通 JSON 中的嵌套文本不得冒充 name/version 字段。
test_embedded_fields_payload() { export MOCK_CDN_MODE=embedded-fields MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# HTTP 成功但版本不匹配时拒绝该候选。
test_wrong_version_payload() { export MOCK_CDN_MODE=wrong-version MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# HTTP 成功但没有响应正文时拒绝该候选。
test_empty_payload() { export MOCK_CDN_MODE=empty MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# 两个 GET 必须并发启动，否则互相等待的夹具都会失败。
test_parallel_probes() { export MOCK_PROBE_BARRIER=1; assert_selection 0 cdn; }
# 非法耗时不得参与 Shell 算术或使候选被误判可用。
test_invalid_duration() { export MOCK_CDN_TIME='1;exit' MOCK_GIT_MODE=fail; assert_selection 1 ''; }
# 限制探测参数范围，非法参数不得启动任何请求。
test_invalid_probe_config() {
  local value
  for value in 0 31 -1 1.5 abc 9999; do
    export JOBS_SPECS_PROBE_TIMEOUT="$value"
    assert_selection 1 '' || return 1
    assert_equal '' "$(< "$TEST_ROOT/calls")" '非法时限仍执行了命令' || return 1
  done
}
# 显式模式拼写错误必须失败，不能退回自动模式。
test_invalid_mode() { export JOBS_SPECS_SOURCE=unknown; assert_selection 1 ''; }
# 连接时限不得超过整次探测预算。
test_connect_timeout_clamp() {
  export JOBS_SPECS_PROBE_TIMEOUT=1 JOBS_SPECS_CONNECT_TIMEOUT=30
  assert_selection 0 cdn || return 1
  /usr/bin/grep -Fq -- '--connect-timeout 1 --max-time 1' "$TEST_ROOT/calls"
}
# 两个挂起 HTTP 进程须在同一墙钟预算结束，并回收所有子进程。
test_probe_timeout() {
  export JOBS_SPECS_PROBE_TIMEOUT=1 MOCK_CDN_MODE=hang MOCK_GIT_MODE=hang
  local started="$EPOCHREALTIME" elapsed
  assert_selection 1 '' || return 1
  elapsed=$(( EPOCHREALTIME - started ))
  (( elapsed < 5 )) || { print -r -- "探测墙钟超时未生效：${elapsed}s" >&2; return 1; }
  assert_no_live_mock_processes
}
# Git 协议阶段也必须包含在候选整体时限之内。
test_git_protocol_timeout() {
  export JOBS_SPECS_PROBE_TIMEOUT=1 MOCK_CDN_MODE=fail MOCK_GIT_PROTOCOL=hang
  assert_selection 1 '' || return 1
  assert_no_live_mock_processes
}
# 确定性放大“先杀sleep、后杀timer”窗口，不能靠主机调度恰好避开竞态。
install_timer_stop_fixture() {
  functions[jobs_test_original_terminate_tree]="${functions[jobs_update_specs_terminate_tree]}"
  function jobs_update_specs_terminate_tree() {
    local process_id="$1" sleep_child='' attempt
    for attempt in {1..50}; do
      sleep_child="$(/bin/ps -axo pid=,ppid=,comm= | /usr/bin/awk -v parent="$process_id" '$2 == parent && ($3 == "sleep" || $3 ~ /\/sleep$/) {print $1; exit}')"
      [[ -n "$sleep_child" ]] && break
      kill -0 "$process_id" 2>/dev/null || break
      /bin/sleep 0.01
    done
    if [[ -n "$sleep_child" ]]; then
      kill -TERM "$sleep_child" 2>/dev/null || true
      : > "$MOCK_ROOT/timer-stop-exercised"
      /bin/sleep 0.15
    fi
    jobs_test_original_terminate_tree "$process_id"
  }
}
# 探测已完成后回收timer，不得因为它的sleep被终止而写出假超时。
test_completed_probe_timer_stop_is_not_timeout() {
  install_timer_stop_fixture
  local specs_work_dir specs_probe_timeout=8 specs_connect_timeout=2
  specs_work_dir="$(/usr/bin/mktemp -d "$TMPDIR/jobs-update-specs.XXXXXXXX")" || return 1
  jobs_update_specs_run_candidate cdn || return 1
  [[ -f "$TEST_ROOT/timer-stop-exercised" && -f "$specs_work_dir/cdn.result" && ! -f "$specs_work_dir/cdn.reason" ]] || return 1
  /bin/rm -r -- "$specs_work_dir"
  assert_no_probe_temp
}
# 刷新已完成后回收timer，也不得把正常返回改成124。
test_completed_refresh_timer_stop_is_not_timeout() {
  install_timer_stop_fixture
  jobs_update_specs_run_cmd '正常刷新timer回收夹具' pod repo update public-alias --verbose || return 1
  [[ -f "$TEST_ROOT/timer-stop-exercised" ]] || return 1
  assert_no_probe_temp
}
# 刷新使用 CocoaPods 清单中的自定义 CDN 别名，私源保持不动。
test_cdn_alias_refresh() {
  jobs_update_cocoapods_repos || return 1
  assert_call 'pod|repo list --no-ansi' || return 1
  assert_call 'pod|repo update public-alias --verbose' || return 1
  assert_no_call 'pod|repo update private-repo' || return 1
  assert_no_call 'pod|repo remove' || return 1
  assert_no_probe_temp
}
# 已登记 HTTPS Git 源按实际别名刷新，并容忍大小写及尾斜杠。
test_git_alias_refresh() {
  export JOBS_SPECS_SOURCE=git
  print -r -- $'private-repo\n- Type: git\n- URL: https://example.invalid/private.git\n\ncustom Specs\n- Type: git\n- URL: https://GITHUB.COM/CocoaPods/Specs.git/\n' > "$TEST_ROOT/repos"
  jobs_update_cocoapods_repos || return 1
  assert_call 'pod|repo update custom Specs --verbose' || return 1
  assert_no_call 'pod|repo add'
}
# 没有官方 CDN 时独立登记 CDN，不删除或改写已有私源。
test_add_missing_cdn() {
  print -r -- $'private-repo\n- Type: git\n- URL: https://example.invalid/private.git\n' > "$TEST_ROOT/repos"
  jobs_update_cocoapods_repos || return 1
  assert_call 'pod|repo add-cdn jobs-public-cdn https://cdn.cocoapods.org/' || return 1
  assert_call 'pod|repo update jobs-public-cdn --verbose' || return 1
  assert_no_call 'pod|repo remove'
}
# 新 CDN 名被私源占用时继续避让，不能覆写同名仓库。
test_cdn_name_collision() {
  print -r -- $'jobs-public-cdn\n- Type: git\n- URL: https://example.invalid/private.git\n\njobs-public-cdn-cdn\n- Type: git\n- URL: https://example.invalid/private2.git\n' > "$TEST_ROOT/repos"
  jobs_update_cocoapods_repos || return 1
  assert_call 'pod|repo add-cdn jobs-public-cdn-cdn-cdn https://cdn.cocoapods.org/' || return 1
  assert_call 'pod|repo update jobs-public-cdn-cdn-cdn --verbose'
}
# 以选项开头的不安全旧别名不得进入 pod repo update 参数。
test_unsafe_alias() {
  print -r -- $'--unsafe\n- Type: CDN\n- URL: https://cdn.cocoapods.org/\n' > "$TEST_ROOT/repos"
  jobs_update_cocoapods_repos || return 1
  assert_no_call 'pod|repo update --unsafe' || return 1
  assert_call 'pod|repo update jobs-public-cdn --verbose'
}
# 没有官方 Git 源时停止，不能为了更新冷克隆巨大 Specs 仓库。
test_missing_git_cache() {
  export JOBS_SPECS_SOURCE=git
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'pod|repo add' || return 1
  assert_no_call 'pod|repo update'
}
# 双源失败时只读取现有源，不新增、不删除、不触发刷新。
test_no_refresh_when_offline() {
  export MOCK_CDN_MODE=fail MOCK_GIT_MODE=fail
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'pod|repo update' || return 1
  assert_no_call 'pod|repo add' || return 1
  assert_no_call 'pod|repo remove'
}
# 仓库清单读取失败时停止，不能误以为没有源而新增。
test_repo_list_failure() {
  export MOCK_REPO_LIST_RESULT=1
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'pod|repo add' || return 1
  assert_no_call 'pod|repo update'
}
# 刷新失败需要向上返回，不能被包装器吞成成功。
test_refresh_failure() {
  export MOCK_POD_RESULT=7
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 7 "$result" || return 1
  assert_no_probe_temp
}
# CDN 刷新默认限制并发，作用域仅限本次 pod 命令。
test_cdn_refresh_concurrency_default() {
  jobs_update_cocoapods_repos || return 1
  /usr/bin/grep -Fxq -- 'repo update public-alias --verbose|8' "$TEST_ROOT/concurrency" || return 1
  assert_equal 0 "${+COCOAPODS_CDN_MAX_CONCURRENCY}"
}
# 调用者显式指定的并发值不被默认值覆盖，包括空值。
test_cdn_refresh_concurrency_explicit() {
  local configured
  for configured in 32 ''; do
    export COCOAPODS_CDN_MAX_CONCURRENCY="$configured"
    jobs_update_cocoapods_repos || return 1
    /usr/bin/grep -Fxq -- "repo update public-alias --verbose|${configured}" "$TEST_ROOT/concurrency" || return 1
    assert_equal "$configured" "$COCOAPODS_CDN_MAX_CONCURRENCY" || return 1
  done
}
# 真实刷新阶段有独立墙钟时限，超时后杀掉 pod 及其后代。
test_refresh_timeout() {
  export JOBS_SPECS_UPDATE_TIMEOUT=1 MOCK_POD_HANG=1
  local started="$EPOCHREALTIME" elapsed result=0
  jobs_update_cocoapods_repos || result=$?
  elapsed=$(( EPOCHREALTIME - started ))
  assert_equal 124 "$result" || return 1
  (( elapsed < 6 )) || { print -r -- "刷新墙钟超时未生效：${elapsed}s" >&2; return 1; }
  assert_no_live_mock_processes || return 1
  assert_no_probe_temp
}
# 只模拟首轮真实超时结果；继续执行原选源与第二轮刷新，避免把回退测试绑到短看门狗。
prepare_timeout_fallback_fixture() {
  print -r -- $'backup-specs\n- Type: git\n- URL: https://github.com/CocoaPods/Specs.git\n' >> "$TEST_ROOT/repos"
  export JOBS_SPECS_UPDATE_TIMEOUT=8 MOCK_FIRST_REFRESH_RESULT=124
  functions[jobs_test_original_specs_run_cmd]="${functions[jobs_update_specs_run_cmd]}"
  function jobs_update_specs_run_cmd() {
    if [[ ! -f "$MOCK_ROOT/first-refresh" || -n "${MOCK_SECOND_REFRESH_RESULT:-}" ]]; then
      local simulated_result="${MOCK_FIRST_REFRESH_RESULT:-124}"
      [[ ! -f "$MOCK_ROOT/first-refresh" ]] || simulated_result="$MOCK_SECOND_REFRESH_RESULT"
      : > "$MOCK_ROOT/first-refresh"
      : > "$MOCK_ROOT/refresh-started"
      shift
      local -a refresh_command=("$@")
      shift refresh_command
      print -r -- "pod|${(j: :)refresh_command}" >> "$MOCK_ROOT/calls"
      return "$simulated_result"
    fi
    jobs_test_original_specs_run_cmd "$@"
  }
}
# 小样本通过但 CDN 真正刷新超时后，只重测并刷新已有健康 Git 源一次。
test_auto_timeout_fallback_recovers() {
  prepare_timeout_fallback_fixture
  jobs_update_cocoapods_repos || return 1
  assert_call 'pod|repo update public-alias --verbose' || return 1
  assert_call 'pod|repo update backup-specs --verbose' || return 1
  assert_equal 2 "$(/usr/bin/grep -c '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  assert_equal 4 "$(/usr/bin/wc -l < "$TEST_ROOT/probes" | /usr/bin/tr -d ' ')" || return 1
  assert_no_call 'pod|repo add' || return 1
  assert_no_call 'pod|repo remove' || return 1
  assert_no_live_mock_processes || return 1
  assert_no_probe_temp
}
# 原来选中 Git 超时，也只能回退已登记且重新测通的 CDN。
test_auto_git_timeout_fallback_recovers() {
  prepare_timeout_fallback_fixture
  export MOCK_GIT_TIME=0.1
  jobs_update_cocoapods_repos || return 1
  assert_equal $'pod|repo update backup-specs --verbose\npod|repo update public-alias --verbose' \
    "$(/usr/bin/grep '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  assert_no_call 'pod|repo add' || return 1
  assert_no_live_mock_processes
}
# 显式选源即使真超时也不换协议，取消和本地错误不进入恢复分支。
test_timeout_fallback_respects_explicit_and_cancel() {
  prepare_timeout_fallback_fixture
  local mode code result
  for mode in cdn git; do
    : > "$TEST_ROOT/calls"
    /bin/rm -f -- "$TEST_ROOT/first-refresh"
    export JOBS_SPECS_SOURCE="$mode"
    result=0
    jobs_update_cocoapods_repos || result=$?
    assert_equal 124 "$result" || return 1
    assert_equal 1 "$(/usr/bin/grep -c '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  done
  export JOBS_SPECS_SOURCE=auto
  for code in 130 143 7; do
    : > "$TEST_ROOT/calls"
    /bin/rm -f -- "$TEST_ROOT/first-refresh"
    export MOCK_FIRST_REFRESH_RESULT="$code"
    result=0
    jobs_update_cocoapods_repos || result=$?
    assert_equal "$code" "$result" || return 1
    assert_equal 1 "$(/usr/bin/grep -c '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  done
  assert_no_live_mock_processes
}
# 备用源在原刷新期间变坏时，重新实测必须挡住后续刷新。
test_timeout_fallback_probe_rejects_unhealthy() {
  prepare_timeout_fallback_fixture
  export MOCK_FALLBACK_GIT_MODE=fail
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 124 "$result" || return 1
  assert_no_call 'pod|repo update backup-specs' || return 1
  assert_equal 4 "$(/usr/bin/wc -l < "$TEST_ROOT/probes" | /usr/bin/tr -d ' ')" || return 1
  assert_no_live_mock_processes
}
# 两个已登记源均真超时时止于两次刷新，最终仍报告超时。
test_timeout_fallback_second_timeout_stays_failed() {
  prepare_timeout_fallback_fixture
  export MOCK_SECOND_REFRESH_RESULT=124
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 124 "$result" || return 1
  assert_equal 2 "$(/usr/bin/grep -c '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  assert_no_live_mock_processes || return 1
  assert_no_probe_temp
}
# 以真实命令退出与实际输出模拟用户日志，首轮Git样本仍然健康。
prepare_network_fallback_fixture() {
  print -r -- $'backup-specs\n- Type: git\n- URL: https://github.com/CocoaPods/Specs.git\n' >> "$TEST_ROOT/repos"
  export MOCK_GIT_TIME=0.1 MOCK_POD_ERROR_REPO=backup-specs MOCK_POD_ERROR_RESULT=1
  export MOCK_POD_ERROR_TEXT='[!] Failed to connect to GitHub to update the CocoaPods/Specs specs repo - Please check if you are offline, or that GitHub is down'
}
# 首轮API网络错误exit1后，自动实测已有CDN并完成刷新，不再仅处理124。
test_git_api_failure_recovers_with_cdn() {
  prepare_network_fallback_fixture
  jobs_update_cocoapods_repos || return 1
  assert_equal $'pod|repo update backup-specs --verbose\npod|repo update public-alias --verbose' \
    "$(/usr/bin/grep '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  assert_no_call 'pod|repo add' || return 1
  assert_no_call 'pod|repo remove' || return 1
  assert_no_probe_temp
}
# 回退不是忽略错误；另一公共源也报网络失败时必须保留非零。
test_both_refresh_network_failures() {
  prepare_network_fallback_fixture
  export MOCK_POD_ERROR_REPO='*'
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_equal 2 "$(/usr/bin/grep -c '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  assert_no_probe_temp
}
# 用户明确指定Git时，网络错误也不能静默改用CDN。
test_explicit_source_network_failure() {
  prepare_network_fallback_fixture
  export JOBS_SPECS_SOURCE=git
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_equal 1 "$(/usr/bin/grep -c '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  assert_no_probe_temp
}
# 未知错误、权限/认证/证书/运行时和取消均须向上返回，不用换源掩盖。
test_non_network_failures_never_fallback() {
  prepare_network_fallback_fixture
  local label code result
  for label in unknown 'Permission denied' 'Authentication failed' 'HTTP 403 Forbidden' 'curl: (60) SSL certificate problem: certificate verify failed' 'RuntimeError: fixture crashed' 'LoadError: missing gem'; do
    : > "$TEST_ROOT/calls"
    export MOCK_POD_ERROR_TEXT="$label"
    [[ "$label" == unknown ]] || MOCK_POD_ERROR_TEXT+=$'\n[!] Failed to connect to GitHub to update the CocoaPods/Specs specs repo'
    result=0
    jobs_update_cocoapods_repos || result=$?
    assert_equal 1 "$result" || return 1
    assert_equal 1 "$(/usr/bin/grep -c '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  done
  export MOCK_POD_ERROR_TEXT='[!] Failed to connect to GitHub to update the CocoaPods/Specs specs repo'
  for code in 129 130 137 143; do
    : > "$TEST_ROOT/calls"
    export MOCK_POD_ERROR_RESULT="$code"
    result=0
    jobs_update_cocoapods_repos || result=$?
    assert_equal "$code" "$result" || return 1
    assert_equal 1 "$(/usr/bin/grep -c '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  done
  assert_no_probe_temp
}
# 备用CDN不再健康时，不执行第二次真正刷新。
test_network_fallback_revalidates_alternative() {
  prepare_network_fallback_fixture
  export MOCK_CDN_MODE=fail
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_equal 1 "$(/usr/bin/grep -c '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  assert_no_probe_temp
}
# 记录器失败也不能因命令输出碰巧含网络词而认定可以安全恢复。
test_capture_failure_is_not_network_recovery() {
  prepare_network_fallback_fixture
  function jobs_test_fail_capture() { /bin/cat > "$1"; return 7; }
  functions[jobs_update_specs_run_cmd]="${functions[jobs_update_specs_run_cmd]/\/usr\/bin\/tee/jobs_test_fail_capture}"
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_equal 1 "$(/usr/bin/grep -c '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  assert_no_probe_temp
}
# 真实统一日志包装器只写一次，已恢复的错误不再污染外层失败统计。
test_recovered_network_summary_and_single_log() {
  prepare_network_fallback_fixture
  functions[jobs_update_run_cmd]="$TEST_ORIGINAL_RUN_CMD"
  JOBS_UPDATE_LOG_READY=1
  jobs_update_run_step 'CocoaPods恢复夹具' jobs_update_cocoapods_repos || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  assert_equal 0 "$JOBS_UPDATE_SKIP_COUNT" || return 1
  assert_equal 1 "$JOBS_UPDATE_SUCCEEDED_STEPS" || return 1
  assert_equal 1 "$(/usr/bin/grep -c '^\[!\] Failed to connect to GitHub' "$TEST_ROOT/test.log")" || return 1
  assert_no_probe_temp
}
# 历史日志或旧分类不得触发当前未知错误的换源。
test_stale_output_does_not_trigger_recovery() {
  prepare_network_fallback_fixture
  print -r -- "$MOCK_POD_ERROR_TEXT" > "$TEST_ROOT/test.log"
  export MOCK_POD_ERROR_TEXT='unknown failure'
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_equal 1 "$(/usr/bin/grep -c '^pod|repo update ' "$TEST_ROOT/calls")" || return 1
  assert_no_probe_temp
}
# 非法刷新预算不得启动真实刷新命令。
test_invalid_refresh_timeout() {
  export JOBS_SPECS_UPDATE_TIMEOUT=901
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'pod|repo update'
}
# 包管理器分支只验证升级逻辑，规格源步骤替换为明确记录的本地夹具。
stub_specs_refresh() {
  function jobs_update_cocoapods_repos() {
    print -r -- 'specs-refresh' >> "$MOCK_ROOT/calls"
    return "${MOCK_SPECS_RESULT:-0}"
  }
}
# 仅选择 CocoaPods 也要升级 Brew 所管理的安装，不能误报未安装。
test_brew_managed() {
  stub_specs_refresh
  jobs_update_gem_cocoapods || return 1
  assert_call 'brew|list --formula --versions cocoapods' || return 1
  assert_call 'brew|upgrade cocoapods' || return 1
  assert_call 'specs-refresh' || return 1
  assert_no_call 'gem|update' || return 1
  assert_equal 1 "$JOBS_UPDATE_COCOAPODS_BREW_UPDATED"
}
# 本轮 formula 阶段已升级 CocoaPods 时，不重复执行 Brew upgrade。
test_brew_already_updated() {
  stub_specs_refresh
  JOBS_UPDATE_COCOAPODS_BREW_UPDATED=1
  jobs_update_gem_cocoapods || return 1
  assert_no_call 'brew|upgrade' || return 1
  assert_call 'specs-refresh' || return 1
  assert_no_call 'gem|update'
}
# 升级成功的标记须跨连续函数调用保留，避免同轮重复升级。
test_brew_success_marker() {
  stub_specs_refresh
  jobs_update_gem_cocoapods || return 1
  jobs_update_gem_cocoapods || return 1
  local count="$(/usr/bin/grep -Fxc -- 'brew|upgrade cocoapods' "$TEST_ROOT/calls")"
  assert_equal 1 "$count"
}
# Brew 升级失败不能改走 gem 安装，并且不能写入成功标记。
test_brew_failure() {
  stub_specs_refresh
  export MOCK_BREW_UPGRADE_RESULT=1
  local result=0
  jobs_update_gem_cocoapods || result=$?
  assert_equal 1 "$result" || return 1
  assert_equal 0 "$JOBS_UPDATE_COCOAPODS_BREW_UPDATED" || return 1
  assert_no_call 'gem|update' || return 1
  assert_call 'specs-refresh'
}
# 仅升级 CocoaPods 也要先刷新 Brew 索引；失败后仅继续独立 Specs 维护。
test_brew_index_failure() {
  stub_specs_refresh
  export MOCK_BREW_INDEX_RESULT=1
  local result=0
  jobs_update_gem_cocoapods || result=$?
  assert_equal 1 "$result" || return 1
  assert_equal 0 "$JOBS_UPDATE_COCOAPODS_BREW_UPDATED" || return 1
  assert_call 'brew-index-refresh' || return 1
  assert_no_call 'brew|upgrade' || return 1
  assert_no_call 'gem|update' || return 1
  assert_call 'specs-refresh'
}
# 可写 gem home 内的 CocoaPods 使用普通 gem update。
test_gem_managed() {
  stub_specs_refresh
  export MOCK_BREW_PRESENT=0
  jobs_update_gem_cocoapods || return 1
  assert_call "gem|update cocoapods --no-user-install --install-dir $TEST_ROOT/gems --bindir $TEST_ROOT/bin --no-document" || return 1
  assert_no_call 'sudo-wrapper|' || return 1
  assert_no_call 'brew|'
}
# Brew 存在但未登记 CocoaPods 时仍检查 gem，不误认为 Brew 管理。
test_brew_other_formula_only() {
  stub_specs_refresh
  export MOCK_BREW_INSTALLED_RESULT=1
  jobs_update_gem_cocoapods || return 1
  assert_call "gem|update cocoapods --no-user-install --install-dir $TEST_ROOT/gems --bindir $TEST_ROOT/bin --no-document" || return 1
  assert_no_call 'brew|upgrade'
}
# 权限不完整且用户目录无法安全确认时停止工具更新，不提权，独立规格源仍可维护。
test_system_gem_managed() {
  stub_specs_refresh
  export MOCK_BREW_PRESENT=0 MOCK_GEM_HOME="$TEST_ROOT/blocked-gem-home"
  /bin/mkdir -p "$MOCK_GEM_HOME/plugins"
  print -r -- 'fixture' > "$MOCK_GEM_HOME/plugins/rdoc_plugin.rb"
  /bin/chmod 400 "$MOCK_GEM_HOME/plugins/rdoc_plugin.rb"
  local result=0
  jobs_update_gem_cocoapods || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'sudo-wrapper|' || return 1
  assert_no_call 'gem|update' || return 1
  assert_call 'specs-refresh'
}
# 未登记安装时不新装 CocoaPods，但已有 pod 仍可维护规格源。
test_unregistered_pod() {
  stub_specs_refresh
  export MOCK_BREW_PRESENT=0 MOCK_GEM_INSTALLED_RESULT=1
  jobs_update_gem_cocoapods || return 1
  assert_no_call 'gem|update' || return 1
  assert_no_call 'brew|upgrade' || return 1
  assert_call 'specs-refresh'
}
# 活跃 pod 属于 gem 时，即使 Brew 也装过 CocoaPods，仍升级当前 gem。
test_mixed_installations() {
  stub_specs_refresh
  export MOCK_BREW_PREFIX="$TEST_ROOT/runtime"
  jobs_update_gem_cocoapods || return 1
  assert_call "gem|update cocoapods --no-user-install --install-dir $TEST_ROOT/gems --bindir $TEST_ROOT/bin --no-document" || return 1
  assert_no_call 'brew|upgrade' || return 1
  assert_equal 0 "$JOBS_UPDATE_COCOAPODS_BREW_UPDATED"
}
# 活跃 pod 既不属于 Brew formula，也未被 gem 登记时停止本体升级。
test_unknown_owner() {
  stub_specs_refresh
  export MOCK_BREW_PREFIX="$TEST_ROOT/runtime" MOCK_GEM_INSTALLED_RESULT=1
  local result=0
  jobs_update_gem_cocoapods || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'gem|update' || return 1
  assert_no_call 'brew|upgrade' || return 1
  assert_call 'specs-refresh'
}
# Git 更快但没有本地 Git 仓库时，继续使用通过探测的 CDN。
test_cdn_when_git_cache_missing() {
  export MOCK_GIT_TIME=0.1
  jobs_update_cocoapods_repos || return 1
  assert_call 'pod|repo update public-alias --verbose' || return 1
  assert_no_call 'pod|repo add'
}
# HTTPS 探测不保证 SSH，只有 SSH Git 源时不得用它通过刷新。
test_ssh_git_cache_is_not_https() {
  export JOBS_SPECS_SOURCE=git
  print -r -- $'ssh-specs\n- Type: git\n- URL: git@github.com:CocoaPods/Specs.git\n' > "$TEST_ROOT/repos"
  local result=0
  jobs_update_cocoapods_repos || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'pod|repo update'
}
# 没有 pod 命令时返回失败，不调用规格源维护。
test_missing_pod() {
  stub_specs_refresh
  export MOCK_POD_PRESENT=0
  local result=0
  jobs_update_gem_cocoapods || result=$?
  assert_equal 1 "$result" || return 1
  assert_no_call 'specs-refresh'
}
# 在子 Shell 里执行单项，避免测试替换函数污染其它场景。
run_case() {
  local title="$1" test_function="$2" result
  (( TEST_TOTAL += 1 ))
  reset_fixture
  ( "$test_function" ) > "$TEST_ROOT/case.stdout" 2> "$TEST_ROOT/case.stderr"
  result=$?
  if (( result == 0 )); then
    (( TEST_PASSED += 1 ))
    print -r -- "✔ $title"
  else
    (( TEST_FAILED += 1 ))
    print -r -- "✖ $title"
    /bin/cat "$TEST_ROOT/case.stderr" "$TEST_ROOT/case.stdout"
  fi
}
# 覆盖有效性、阈值、并发、进程回收、源身份和升级来源分支。
run_network_cases() {
  run_case '健康双源默认 CDN' test_cdn_default
  run_case 'Git 明显更快' test_git_faster
  run_case 'Git 15% 阈值边界' test_git_threshold
  run_case 'CDN 失败回退 Git' test_cdn_failure
  run_case 'Git 协议失败回退 CDN' test_git_protocol_failure
  run_case 'Git 无效 HEAD' test_git_protocol_invalid
  run_case '双源失败' test_both_failure
  run_case '强制 CDN 不静默换源' test_forced_cdn_failure
  run_case '强制 Git 不静默换源' test_forced_git_failure
  run_case '强制健康 Git' test_forced_git
  run_case 'Git API不可达不选Git' test_git_api_unavailable_selects_cdn
  run_case 'Git API非200或非SHA拒绝' test_git_api_invalid_payload
  run_case 'Git API完整40/64SHA与请求头' test_git_api_sha_lengths
  run_case 'Git API候选整体时限' test_git_api_timeout
  run_case '拒绝 HTML 字段假阳性' test_html_payload
  run_case '拒绝不完整 JSON' test_malformed_payload
  run_case '拒绝 JSON 内嵌字段文本' test_embedded_fields_payload
  run_case '拒绝错误版本' test_wrong_version_payload
  run_case '拒绝空响应' test_empty_payload
  run_case '双源并发' test_parallel_probes
  run_case '拒绝非法耗时' test_invalid_duration
  run_case '探测时限范围校验' test_invalid_probe_config
  run_case '选源模式校验' test_invalid_mode
  run_case '连接时限收敛' test_connect_timeout_clamp
  run_case 'HTTP 墙钟超时与子进程回收' test_probe_timeout
  run_case 'Git 协议墙钟超时与子进程回收' test_git_protocol_timeout
  run_case '完成探测后停timer不得误写超时' test_completed_probe_timer_stop_is_not_timeout
  run_case '完成刷新后停timer不得误返124' test_completed_refresh_timer_stop_is_not_timeout
  run_case '自定义 CDN 别名与私源保留' test_cdn_alias_refresh
  run_case '自定义 Git 别名与 URL 规范化' test_git_alias_refresh
  run_case '缺失 CDN 独立登记' test_add_missing_cdn
  run_case 'CDN 安全同名避让' test_cdn_name_collision
  run_case '拒绝选项形式别名' test_unsafe_alias
  run_case 'Git 缓存缺失不冷克隆' test_missing_git_cache
  run_case '离线不触发刷新' test_no_refresh_when_offline
  run_case '源清单失败不新增' test_repo_list_failure
  run_case '刷新失败传播' test_refresh_failure
  run_case 'CDN 默认并发8且不改父环境' test_cdn_refresh_concurrency_default
  run_case 'CDN 显式并发值及空值保护' test_cdn_refresh_concurrency_explicit
  run_case '刷新墙钟超时与子进程回收' test_refresh_timeout
  run_case '自动CDN超时重测已有Git源后恢复' test_auto_timeout_fallback_recovers
  run_case '自动Git超时重测已有CDN源后恢复' test_auto_git_timeout_fallback_recovers
  run_case '显式选源、取消与本地错误不切源' test_timeout_fallback_respects_explicit_and_cancel
  run_case '原刷新超时后拒绝不健康备用源' test_timeout_fallback_probe_rejects_unhealthy
  run_case '备用源仍超时不冒充成功或重复刷新' test_timeout_fallback_second_timeout_stays_failed
  run_case 'Git API网络exit1后真实命令回退CDN' test_git_api_failure_recovers_with_cdn
  run_case '双源网络错误仍返回失败' test_both_refresh_network_failures
  run_case '显式源网络错误不换源' test_explicit_source_network_failure
  run_case '未知、权限、认证、证书、运行时及取消不换源' test_non_network_failures_never_fallback
  run_case '备用源必须重新测通' test_network_fallback_revalidates_alternative
  run_case '输出捕获失败不冒充网络恢复' test_capture_failure_is_not_network_recovery
  run_case '恢复后外层汇总成功且日志只写一次' test_recovered_network_summary_and_single_log
  run_case '历史日志不触发本次换源' test_stale_output_does_not_trigger_recovery
  run_case '刷新时限范围校验' test_invalid_refresh_timeout
  run_case '单独选择 CocoaPods 升级 Brew 安装' test_brew_managed
  run_case '跳过 formula 阶段已完成升级' test_brew_already_updated
  run_case '成功标记避免同轮重复升级' test_brew_success_marker
  run_case 'Brew 升级失败不混装 gem' test_brew_failure
  run_case 'Brew 索引失败跳过本体且维护独立 Specs' test_brew_index_failure
  run_case '可写 gem home 升级' test_gem_managed
  run_case 'Brew 未登记 CocoaPods 回退 gem' test_brew_other_formula_only
  run_case '不安全用户目录停止 Gem 升级且不提权' test_system_gem_managed
  run_case '未登记安装保留源维护' test_unregistered_pod
  run_case '混装优先升级活跃 gem' test_mixed_installations
  run_case '未知归属不升级本体' test_unknown_owner
  run_case '缺少 Git 缓存继续使用健康 CDN' test_cdn_when_git_cache_missing
  run_case 'SSH 本地源不冒充 HTTPS 可用' test_ssh_git_cache_is_not_https
  run_case '缺少 pod 返回失败' test_missing_pod
}
# 汇总结果，任何用例失败均向 CI 返回非零。
report_test_results() {
  print -r -- "共 ${TEST_TOTAL} 项：通过 ${TEST_PASSED}，失败 ${TEST_FAILED}。"
  (( TEST_FAILED == 0 ))
}
# 只在测试主 Shell 退出时清理；子 Shell 和命令替换不能删除共享夹具。
TRAPEXIT() {
  (( ZSH_SUBSHELL == 0 )) && cleanup_tests
  return 0
}
# 中断时通过统一退出路径回收夹具。
TRAPINT() {
  exit 130
}
# 终止时通过统一退出路径回收夹具。
TRAPTERM() {
  exit 143
}
# 依次展示隔离说明、准备夹具、执行回归并汇总。
main() {
  show_test_intro # 先说明模拟执行和临时文件边界。
  initialize_tests # 准备隔离命令并加载待测函数。
  install_safe_wrappers # 屏蔽宿主包管理器发现与提权执行。
  run_network_cases # 执行网络选源、刷新及升级来源回归。
  report_test_results # 以非零退出码报告任意失败。
}

main "$@"
