#!/bin/zsh
# 脚本自述：
# - 脚本名称：Jobs 子卷合并（运行时按当前文件名显示）。
# - 核心用途：识别当前目录及一级子目录的 文件名@序号of总数，逐组校验并按数字顺序合并。
# - 影响范围：在目标目录发布完整文件；已有文件不覆盖，仅输入 YES 才删除本组分卷。
# - 运行提示：无效路径或无分卷时持续询问；--release-dir 使产物留在下载目录；Ctrl+C 随时停止。

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

SCRIPT_VERSION="2026.11.13"
SCRIPT_SOURCE_PATH="$0"
SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
TARGET_DIR=""
TARGET_EXPLICIT=0
TARGET_IS_VOLUME_DIR=0
TARGET_OUTPUT_IN_PLACE=0
USE_COLOR=0
NORMALIZED_DIR=""
PARSED_NAME=""
PARSED_INDEX=0
PARSED_TOTAL=0
GROUP_DIRS=()
GROUP_NAMES=()
SELECTED_GROUPS=()
CHUNKS=()
CHUNK_STATES=()
GROUP_BYTES=0
ACTIVE_TEMP=""
# 准备自述需要的路径和颜色，不写文件或改变工作目录。
prepare_display() {
  SCRIPT_PATH="${SCRIPT_SOURCE_PATH:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    USE_COLOR=1
  fi
}
# 打印说明，日志始终保留纯文本。
message() {
  local text="$1" tone="${2:-34}"
  if (( USE_COLOR )); then
    printf '\033[%sm%s\033[0m\n' "$tone" "$text"
  else
    print -r -- "$text"
  fi
  if [[ "${LOG_READY:-0}" == 1 ]]; then
    print -r -- "$text" >> "$LOG_FILE"
  fi
}
# 首屏展示用途与删除边界，确认前不进行真实业务。
show_script_intro_and_wait() {
  prepare_display
  message "======== Jobs 子卷合并（${SCRIPT_PATH:t}）========" '1;31'
  message "工具版本：$SCRIPT_VERSION" '0;34'
  message '1、每次手动输入 / 拖入目录；扫描本层与一级子目录，空路径或没有完整多卷组时持续重问。' '0;34'
  message '2、按完整原文件名分组，检查总数、重复及缺号；按数字卷号合并，兼容补零编号。' '0;34'
  message '3、拖入分卷目录时在父目录还原；拖入父目录时将一级子目录的分卷还原在该父目录。' '0;34'
  message '4、默认保留分卷；只有精确输入 YES 才删除本组分卷，不递归删除目录。' '0;34'
  message '5、只检查本机 fzf 和系统命令，不安装、不升级、不修改 Shell 配置。' '0;34'
  message "日志：${LOG_FILE}；不想合并可关闭终端，或按 Ctrl+C 退出。" '0;34'
  if [[ ! -t 0 ]]; then
    message '✖ 缺少交互终端，请在 Terminal 中运行。' '1;31'
    exit 1
  fi
  jobs_prompt_output print -n -r -- '➤ 按 [Enter] 继续，或 Ctrl+C 退出：'
  IFS= jobs_list_intro_read -r _ || exit 1
}
# 在用户确认后初始化日志与中断处理。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  : > "$LOG_FILE" || exit 1
  LOG_READY=1
  trap 'report_interruption; exit 130' INT
  trap 'report_interruption; exit 143' TERM
}
# 中断时保留候选，不把残缺结果发布为完整文件。
report_interruption() {
  message '⚠ 已中止；原有文件及未确认删除的分卷保留。' '1;33'
  [[ -z "$ACTIVE_TEMP" ]] || message "⚠ 未发布的候选：$ACTIVE_TEMP" '1;33'
}
# 检查本机工具和实际使用的选择器选项，不写入环境。
check_environment() {
  local utility
  for utility in fzf /usr/bin/find /usr/bin/stat /bin/cat /usr/bin/tee /usr/bin/shasum /usr/bin/mktemp link rm rmdir; do
    if ! command -v "$utility" >/dev/null 2>&1; then
      message "✖ 缺少命令：$utility。fzf 可手动运行 brew install fzf 安装。" '1;31'
      exit 1
    fi
  done
  if ! fzf --version >/dev/null 2>&1 || ! printf 'check\n' | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf \
    --filter=check --multi --footer='检查' --bind='space:transform:echo abort' >/dev/null 2>&1; then
    message '✖ fzf 不可用或不支持 footer / transform，请手动修复后重试。' '1;31'
    exit 1
  fi
}
# 优先保留真实目录名，仅在原输入无效时去除拖入产生的边缘空白。
normalize_directory_input() {
  local candidate="$1"
  local -a words
  NORMALIZED_DIR=""
  if [[ -d "$candidate" && ! -L "$candidate" ]]; then
    NORMALIZED_DIR="${candidate:A}"
    return 0
  fi
  while [[ "$candidate" == [[:space:]]* || "$candidate" == $'\u00a0'* || "$candidate" == $'\u3000'* ]]; do
    candidate="${candidate#?}"
  done
  while [[ "$candidate" == *[[:space:]] || "$candidate" == *$'\u00a0' || "$candidate" == *$'\u3000' ]]; do
    candidate="${candidate%?}"
  done
  if [[ -d "$candidate" && ! -L "$candidate" ]]; then
    NORMALIZED_DIR="${candidate:A}"
    return 0
  fi
  # 只做词法去引号，不执行 eval、变量替换或命令替换。
  words=("${(@z)candidate}") 2>/dev/null || return 1
  (( ${#words} == 1 )) || return 1
  candidate="${(Q)words[1]}"
  if [[ "$candidate" == '~/'* ]]; then
    candidate="$HOME/${candidate#\~/}"
  fi
  [[ -d "$candidate" && ! -L "$candidate" ]] || return 1
  NORMALIZED_DIR="${candidate:A}"
}
# 必须手动提供有效目录，不扫描任何隐式默认位置。
choose_target_directory() {
  local input=''
  while true; do
    message '➤ 手动输入或拖入一个分卷目录 / 父目录；Ctrl+C 退出：'
    IFS= read -r input || return 1
    if normalize_directory_input "$input" && [[ -r "$NORMALIZED_DIR" && -x "$NORMALIZED_DIR" ]]; then
      TARGET_DIR="$NORMALIZED_DIR"
      TARGET_EXPLICIT=1
      message "ℹ 扫描目录：$TARGET_DIR"
      return 0
    fi
    message '✖ 请输入存在且可读取、可进入的单个目录；空输入、多路径和符号链接不接受。' '1;31'
  done
}
# 目录不存在或未找到分卷时持续询问；输入结束才停止，不在 EOF 上空转。
require_target_directory() {
  if (( $# > 0 )); then
    message '✖ 此入口不接受路径参数；请启动后手动输入或拖入目标。' '1;31'
    exit 1
  fi
  while true; do
    choose_target_directory || exit 1
    if find_volume_groups; then
      return 0
    fi
    message '➤ 目录中没有可合并的完整多卷组，请重新输入目标。' '1;33'
  done
}
# 从最后一个合法后缀解析完整原文件名，保留名称中的 @。
parse_volume_name() {
  local filename="$1"
  if [[ "$filename" =~ '^(.+)@([0-9]+)of([0-9]+)$' ]]; then
    PARSED_NAME="$match[1]"
    (( ${#match[2]} <= 9 && ${#match[3]} <= 9 )) || return 1
    PARSED_INDEX=$(( 10#${match[2]} ))
    PARSED_TOTAL=$(( 10#${match[3]} ))
    [[ "$PARSED_NAME" != . && "$PARSED_NAME" != .. ]] || return 1
    return 0
  fi
  return 1
}
# 为一个目录内的每个原文件建立独立分卷组。
scan_volume_directory() {
  local dir="$1" file="" found=0 i
  while IFS= read -r -d '' file; do
    parse_volume_name "${file:t}" || continue
    found=0
    for (( i=1; i<=${#GROUP_NAMES}; i++ )); do
      if [[ "${GROUP_DIRS[i]}" == "$dir" && "${GROUP_NAMES[i]}" == "$PARSED_NAME" ]]; then
        found=1
        break
      fi
    done
    if (( ! found )); then
      GROUP_DIRS+=("$dir")
      GROUP_NAMES+=("$PARSED_NAME")
    fi
  done < <(/usr/bin/find "$dir" -maxdepth 1 -type f -print0)
}
# 扫描平铺文件及一级普通子目录，跳过缓存和第三方目录。
find_volume_groups() {
  GROUP_DIRS=()
  GROUP_NAMES=()
  scan_volume_directory "$TARGET_DIR"
  TARGET_IS_VOLUME_DIR=0
  if (( TARGET_EXPLICIT && ! TARGET_OUTPUT_IN_PLACE && ${#GROUP_NAMES} > 0 )); then
    TARGET_IS_VOLUME_DIR=1
    message "ℹ 当前目录直接包含分卷，其本层组将还原到父目录：${TARGET_DIR:h}"
  fi
  local dir=""
  while IFS= read -r -d '' dir; do
    case "${dir:t}" in
      .*|node_modules|Pods|ManualBy*Pods@Pods|PodsManual|build|DerivedData) continue ;;
    esac
    scan_volume_directory "$dir"
  done < <(/usr/bin/find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
  if (( ${#GROUP_NAMES} == 0 )); then
    message 'ℹ 未找到 文件名@序号of总数 格式的分卷；.partial 断点不参与合并。'
    return 1
  fi
  local i output_dir='' output=''
  local -a valid_dirs=() valid_names=()
  for (( i=1; i<=${#GROUP_NAMES}; i++ )); do
    dir="${GROUP_DIRS[i]}"
    output_dir="$TARGET_DIR"
    if (( TARGET_IS_VOLUME_DIR )) && [[ "$dir" == "$TARGET_DIR" ]]; then
      output_dir="${TARGET_DIR:h}"
    fi
    output="$output_dir/${GROUP_NAMES[i]}"
    if ! validate_group "$dir" "${GROUP_NAMES[i]}"; then
      continue
    fi
    if [[ ! -w "$output_dir" || -e "$output" || -L "$output" ]]; then
      message "✖ 输出目录不可写或已有同名目标，保留并跳过：$output" '1;31'
      continue
    fi
    valid_dirs+=("$dir")
    valid_names+=("${GROUP_NAMES[i]}")
  done
  GROUP_DIRS=("${valid_dirs[@]}")
  GROUP_NAMES=("${valid_names[@]}")
  (( ${#GROUP_NAMES} > 0 )) || return 1
  message "ℹ 共检测到 ${#GROUP_NAMES} 组可合并的完整多卷。"
  return 0
}
# 检查总数、索引唯一性和连续性，建立数值顺序。
validate_group() {
  local dir="$1" name="$2" file="" total=0 count=0 size=0 i index_key
  local -A indexed states
  CHUNKS=()
  CHUNK_STATES=()
  GROUP_BYTES=0
  while IFS= read -r -d '' file; do
    parse_volume_name "${file:t}" || continue
    [[ "$PARSED_NAME" == "$name" ]] || continue
    if (( PARSED_TOTAL < 2 || PARSED_INDEX < 1 || PARSED_INDEX > PARSED_TOTAL )); then
      message "✖ 非法卷号：$file" '1;31'
      return 1
    fi
    if (( total != 0 && total != PARSED_TOTAL )); then
      message "✖ 同组标记总卷数不一致：$name" '1;31'
      return 1
    fi
    total=$PARSED_TOTAL
    index_key="$PARSED_INDEX"
    if [[ -n "${indexed[$index_key]-}" ]]; then
      message "✖ 卷号重复（含补零后的重复编号）：$file" '1;31'
      return 1
    fi
    size="$(/usr/bin/stat -f %z "$file")" || return 1
    if (( size <= 0 )) || [[ ! -r "$file" || -L "$file" ]]; then
      message "✖ 分卷为空或不可读取，不能合并：$file" '1;31'
      return 1
    fi
    indexed[$index_key]="$file"
    states[$index_key]="$(/usr/bin/stat -f '%d:%i:%z:%m:%c' "$file")" || return 1
    GROUP_BYTES=$(( GROUP_BYTES + size ))
    count=$(( count + 1 ))
  done < <(/usr/bin/find "$dir" -maxdepth 1 -type f -print0)
  if (( count == 0 || count != total )); then
    message "✖ 缺卷：$name，已完成 $count/$total 卷；请先补齐下载，.partial 不参与合并。" '1;31'
    return 1
  fi
  for (( i=1; i<=total; i++ )); do
    if [[ -z "${indexed[$i]-}" ]]; then
      message "✖ 缺少第 $i 卷：$name" '1;31'
      return 1
    fi
    CHUNKS+=("${indexed[$i]}")
    CHUNK_STATES+=("${states[$i]}")
  done
}
# 用编号映射选择分卷组，显示名中的特殊字符不参与路径解析。
select_volume_groups() {
  local -a options=($'ALL\t全选' $'CLEAR\t清空' $'CANCEL\t取消本轮')
  local i selection="" row="" rc=0 label=""
  local hint='↑/↓ 或 Tab 移动；回车勾选/操作；空格确认；Ctrl+A 全选；Ctrl+D 清空；Esc 取消'
  for (( i=1; i<=${#GROUP_NAMES}; i++ )); do
    label="${GROUP_DIRS[i]} / ${GROUP_NAMES[i]}"
    options+=("$i"$'\t'"${(q)label}")
  done
  selection="$(printf '%s\n' "${options[@]}" | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf \
    --multi --height=80% --layout=reverse --border \
    --delimiter=$'\t' --with-nth=2.. --prompt='选择分卷组 > ' \
    --header="$hint" --footer="$hint" \
    --bind='up:up,down:down,tab:down,shift-tab:up,ctrl-a:select-all,ctrl-d:deselect-all' \
    --bind='enter:transform:case "$FZF_CURRENT_ITEM" in ALL*) echo select-all ;; CLEAR*) echo deselect-all ;; CANCEL*) echo abort ;; *) echo toggle ;; esac' \
    --bind='space:transform:case "$FZF_CURRENT_ITEM" in ALL*) echo select-all ;; CLEAR*) echo deselect-all ;; CANCEL*) echo abort ;; *) if [ "${FZF_SELECT_COUNT:-0}" -gt 0 ]; then echo accept; else echo abort; fi ;; esac')" || rc=$?
  if (( rc == 130 || rc == 1 )) || [[ -z "$selection" && "$rc" == 0 ]]; then
    message 'ℹ 已取消或空选，没有执行合并。'
    exit 0
  fi
  if (( rc != 0 )); then
    message "✖ fzf 选择失败（退出码 $rc）。" '1;31'
    exit 1
  fi
  SELECTED_GROUPS=()
  while IFS= read -r row; do
    i="${row%%$'\t'*}"
    [[ "$i" != ALL && "$i" != CLEAR && "$i" != CANCEL ]] || continue
    if [[ "$i" != <-> ]] || (( i < 1 || i > ${#GROUP_NAMES} )); then
      message '✖ 选择结果无效，停止。' '1;31'
      exit 1
    fi
    SELECTED_GROUPS+=("$i")
  done <<< "$selection"
  if (( ${#SELECTED_GROUPS} == 0 )); then
    message 'ℹ 没有勾选真实分卷组，未执行合并。'
    exit 0
  fi
}
# 按数值顺序输出分卷内容，读取失败使整个管道失败。
stream_chunks() {
  local file
  for file in "${CHUNKS[@]}"; do
    /bin/cat "$file" || return 1
  done
}
# 确认分卷在合并期间未被替换、增删或改写。
check_chunk_states() {
  local i current=""
  for (( i=1; i<=${#CHUNKS}; i++ )); do
    [[ -f "${CHUNKS[i]}" && ! -L "${CHUNKS[i]}" ]] || return 1
    current="$(/usr/bin/stat -f '%d:%i:%z:%m:%c' "${CHUNKS[i]}")" || return 1
    [[ "$current" == "${CHUNK_STATES[i]}" ]] || return 1
  done
}
# 只删除已合并且未变化的精确清单，空子目录才尝试移除。
offer_delete_chunks() {
  local dir="$1" output_dir="$2" answer="" file
  local output="${3:-}" expected_hash="${4:-}" result_hash='' chunks_hash=''
  jobs_prompt_output message '⚠ 默认保留分卷。删除本组分卷请输入 YES；回车、其它输入或 EOF 均保留。' '1;33'
  IFS= read -r answer || answer=""
  if [[ "$answer" != YES ]]; then
    message 'ℹ 已保留全部分卷。'
    return 0
  fi
  if ! check_chunk_states; then
    message '✖ 分卷已发生变化，取消删除。' '1;31'
    return 1
  fi
  if [[ -n "$output" ]]; then
    if [[ ! -f "$output" || -L "$output" ]]; then
      message '✖ 合并结果已移除或替换，保留分卷。' '1;31'
      return 1
    fi
    result_hash="$(/usr/bin/shasum -a 256 < "$output")" || return 1
    chunks_hash="$(stream_chunks | /usr/bin/shasum -a 256)" || return 1
    if [[ "${result_hash%% *}" != "$expected_hash" || "${chunks_hash%% *}" != "$expected_hash" ]]; then
      message '✖ 合并结果或分卷内容已变化，保留分卷。' '1;31'
      return 1
    fi
  fi
  for file in "${CHUNKS[@]}"; do
    if ! /bin/rm -f -- "$file"; then
      message "✖ 删除失败：$file" '1;31'
      return 1
    fi
  done
  if [[ "$dir" != "$output_dir" ]]; then
    /bin/rmdir "$dir" 2>/dev/null || message "ℹ 目录仍有其它内容，保留：$dir"
  fi
  message '✔ 已删除本组分卷；其它文件保留。' '1;32'
}
# 写入独占候选，核对大小与流摘要后以硬链接原子发布。
merge_one_group() {
  local dir="$1" name="$2" output_dir="$TARGET_DIR" output=""
  if (( TARGET_IS_VOLUME_DIR )) && [[ "$dir" == "$TARGET_DIR" ]]; then
    output_dir="${TARGET_DIR:h}"
  fi
  output="$output_dir/$name"
  local stream_hash="" output_hash="" output_size=0
  message "➤ 分卷来源：$dir；原文件名：$name"
  validate_group "$dir" "$name" || return 1
  if [[ -e "$output" || -L "$output" ]]; then
    message "✖ 目标已存在，保留原文件，拒绝覆盖：$output" '1;31'
    return 1
  fi
  ACTIVE_TEMP="$(/usr/bin/mktemp "$output_dir/.merge.XXXXXXXX")" || return 1
  message "ℹ 按卷号合并 ${#CHUNKS} 卷，共 $GROUP_BYTES 字节；目标：$output"
  if ! stream_hash="$(stream_chunks | /usr/bin/tee "$ACTIVE_TEMP" | /usr/bin/shasum -a 256)"; then
    message "✖ 读取或写入失败，保留未发布候选：$ACTIVE_TEMP" '1;31'
    return 1
  fi
  output_size="$(/usr/bin/stat -f %z "$ACTIVE_TEMP")" || return 1
  output_hash="$(/usr/bin/shasum -a 256 < "$ACTIVE_TEMP")" || return 1
  if (( output_size != GROUP_BYTES )) || [[ "${stream_hash%% *}" != "${output_hash%% *}" ]] || ! check_chunk_states; then
    message "✖ 大小、SHA-256 或分卷状态校验失败；候选保留：$ACTIVE_TEMP" '1;31'
    return 1
  fi
  # link(1) 对已存在的文件、目录和符号链接均失败，不覆盖并发创建的目标。
  if ! /bin/link "$ACTIVE_TEMP" "$output"; then
    message "✖ 发布失败，保留原目标与候选：$ACTIVE_TEMP" '1;31'
    return 1
  fi
  /bin/rm -f -- "$ACTIVE_TEMP" || return 1
  ACTIVE_TEMP=""
  message "✔ 已合并：$output；SHA-256：${output_hash%% *}" '1;32'
  message 'ℹ 此校验确认复制内容一致；没有可信原文件摘要时，不能据此验证镜像来源。'
  offer_delete_chunks "$dir" "$output_dir" "$output" "${output_hash%% *}"
}
# 批量处理选中分组，保留失败状态并报告真实汇总。
merge_selected_groups() {
  local i failed=0 completed=0
  for i in "${SELECTED_GROUPS[@]}"; do
    if merge_one_group "${GROUP_DIRS[i]}" "${GROUP_NAMES[i]}"; then
      completed=$(( completed + 1 ))
    else
      failed=$(( failed + 1 ))
    fi
  done
  message "ℹ 流程结束：成功 $completed 组，失败 $failed 组。日志：$LOG_FILE"
  (( failed == 0 ))
}
# 展示已选分卷的输出计划，默认取消且左键返回分组选择。
confirm_merge_plan() {
  local i output_dir='' output='' rc=0
  for i in "${SELECTED_GROUPS[@]}"; do
    output_dir="$TARGET_DIR"
    if (( TARGET_IS_VOLUME_DIR )) && [[ "${GROUP_DIRS[i]}" == "$TARGET_DIR" ]]; then
      output_dir="${TARGET_DIR:h}"
    fi
    message "来源：${GROUP_DIRS[i]} / ${GROUP_NAMES[i]} → $output_dir/${GROUP_NAMES[i]}"
  done
  output="$(printf '%s\n' 'CANCEL|取消本轮（默认）' 'RUN|开始合并并校验' | \
    FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' fzf --no-multi --expect=left \
      --height=12 --layout=reverse --border --delimiter='|' --with-nth=2 \
      --bind='up:up,down:down,tab:down,shift-tab:up' \
      --header='↑/↓ 选择；回车确认；← 返回上一层；Esc 取消' \
      --footer='↑/↓ 选择；回车确认；← 返回上一层；Esc 取消' --prompt='确认合并 > ')" || rc=$?
  [[ "$output" == left$'\n'* || "$output" == left ]] && return 3
  (( rc == 130 || rc == 1 )) && return 2
  (( rc == 0 )) || { message "✖ 执行确认失败（退出码 $rc）。" '1;31'; return 1; }
  [[ "$output" == *$'\nRUN|'* ]] || return 2
}
# 先完成可返回的执行确认，再处理分组，取消时没有业务写入。
plan_and_merge() {
  local rc=0
  while true; do
    select_volume_groups
    rc=0
    confirm_merge_plan || rc=$?
    (( rc == 3 )) && continue
    if (( rc == 2 )); then
      message 'ℹ 已取消合并，未写入输出文件。'
      return 0
    fi
    (( rc == 0 )) || return 1
    merge_selected_groups
    return $?
  done
}
# 编排自述、依赖、目录选择和分组合并。
main() {
  show_script_intro_and_wait || return $? # 先展示用途与影响，等待回车后继续。
  initialize_runtime # 确认后初始化日志和中断处理。
  check_environment # 只检查实际依赖，不安装或修改环境。
  require_target_directory "$@" # 持续选择并扫描目录，找到分卷后才进入选择。
  plan_and_merge # 勾选与确认计划后再合并，左键返回分组层。
}

main "$@"
