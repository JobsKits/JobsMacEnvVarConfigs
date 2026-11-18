#!/bin/zsh
# 脚本自述：frun 进入 Flutter 备战状态，输入或拖入独立 main 的 Dart 源码运行。
# 影响范围：仅在所属 Flutter 工程内运行目标，Flutter 可能写入依赖与构建缓存。
# 运行提示：无参时提交路径即确认运行；有参时回车确认；Ctrl+C / q 退出。
# shell: zsh
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

ENTRY_PATH="${0:A}"
SCRIPT_DIR=""
LOG_FILE=""
FRUN_TARGET=""
FRUN_PROJECT=""
FRUN_DEVICE=""
FRUN_DRY_RUN=0
FRUN_YES=0
FRUN_INTERACTIVE=0
FRUN_COLOR=0
typeset -a FRUN_FLUTTER_ARGS=() FRUN_SDK=()
# 按当前终端能力展示标题、说明与询问；日志始终保持纯文本。
frun_display() {
  local role="$1" message="$2" sgr='0;34'
  case "$role" in title) sgr='1;31' ;; question) sgr='1;36' ;; success) sgr='1;32' ;; error) sgr='1;31' ;; esac
  if (( FRUN_COLOR )); then
    printf '\033[%sm%s\033[0m\n' "$sgr" "$message" >&2
  else
    print -u2 -r -- "$message"
  fi
  [[ -z "$LOG_FILE" ]] || print -r -- "$message" >> "$LOG_FILE"
}
# 输出固定帮助；不访问 SDK、不创建日志。
frun_help() {
  cat <<'HELP'
frun：独立运行 Flutter 工程中的 Dart main 入口

  frun                         进入备战状态；输入 / 拖入单个 .dart 后回车运行
  frun 路径.dart               运行指定源码（先回车确认）
  frun -d chrome 路径.dart     显式选择设备；不指定时交给 Flutter 原生选择
  frun --dry-run 路径.dart     只校验路径、入口、pubspec、SDK并打印命令
  frun --yes 路径.dart         明确授权非交互执行；仅适合已知目标
  frun 路径.dart -- --release  透传 flutter run 参数（禁止覆盖 -t / --target）

无参模式在运行结束后继续等待下一份源码；q / quit / exit、Ctrl+C 或输入结束退出。
支持中文、空格、引号、Finder 拖入的 Shell 转义路径及 ~/；不执行输入中的 Shell 表达式。
SDK 优先所属工程的 .fvm/flutter_sdk；FVM 项目无可用链接时使用 fvm flutter，绝不降级到全局 SDK。
普通辅助文件 / part 不可直接运行；不会替源码生成 main，也不会复制源码到临时工程。
不执行 clean、升级或额外 pub get；flutter run 自身可能解析依赖、获取组件并写构建缓存。
Flutter 原始输入输出直连终端：r 热重载、R 热重启、q 结束；日志仅记调度和退出码。
HELP
}
# 先展示用途；只读帮助 / dry-run 无需交互确认。
show_script_intro_and_wait() {
  local item=''
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" && "${PLAIN_OUTPUT:-0}" != 1 ]]; then
    FRUN_COLOR=1
  fi
  for item in "$@"; do
    [[ "$item" != --help && "$item" != -h ]] || { frun_help; exit 0; }
  done
  frun_display title 'frun｜Flutter Demo 独立运行'
  frun_display body '1、输入 / 拖入含 main 的 .dart，自动定位所属工程及 SDK。'
  frun_display body '2、仅运行该目标；Flutter 可能更新依赖缓存和构建产物，不修改全局 SDK 绑定。'
  frun_display body '3、Ctrl+C 取消；备战状态输入 q 退出。日志在确认后的系统临时目录生成。'
}
# 解析自有选项，Flutter 参数必须放在 -- 之后，避免路径被误判。
frun_parse_arguments() {
  setopt NO_NOMATCH PIPE_FAIL
  SCRIPT_DIR="${ENTRY_PATH:h}"
  while (( $# )); do
    case "$1" in
      --dry-run) FRUN_DRY_RUN=1 ;;
      --yes) FRUN_YES=1 ;;
      -d|--device)
        (( $# >= 2 )) && [[ -n "$2" ]] || { frun_display error '✖ --device 需要设备 ID。'; exit 2; }
        FRUN_DEVICE="$2"; shift ;;
      --)
        shift
        FRUN_FLUTTER_ARGS=("$@")
        break ;;
      -*) frun_display error "✖ 未知选项：$1；Flutter 参数放在 -- 之后。"; exit 2 ;;
      *) [[ -z "$FRUN_TARGET" ]] || { frun_display error '✖ 每次只接受一个 .dart 文件。'; exit 2; }
        FRUN_TARGET="$1" ;;
    esac
    shift
  done
  local item=''
  for item in "${FRUN_FLUTTER_ARGS[@]}"; do
    case "$item" in
      -t|-t?*|--target|--target=*|-d|-d?*|--device-id|--device-id=*)
        frun_display error '✖ 请用 frun 的路径和 --device 指定入口 / 设备，不能在透传参数中覆盖。'; exit 2 ;;
    esac
  done
  [[ -n "$FRUN_TARGET" ]] || FRUN_INTERACTIVE=1
  if (( FRUN_INTERACTIVE && FRUN_DRY_RUN )); then
    frun_display error '✖ --dry-run 需要明确的 .dart 路径。'; exit 2
  fi
}
# 保留用户原始路径；仅在它不存在时进行 zsh 词法解引号，不 eval / 展开命令。
frun_resolve_path() {
  local raw="$1" candidate=''
  local -a tokens=()
  raw="${raw%$'\r'}"
  if [[ -f "$raw" ]]; then
    candidate="$raw"
  else
    raw="${raw#${raw%%[![:space:]]*}}"
    raw="${raw%${raw##*[![:space:]]}}"
    tokens=("${(@z)raw}")
    (( ${#tokens[@]} == 1 )) || { frun_display error '✖ 请输入 / 拖入单个 Dart 文件。'; return 2; }
    candidate="${(Q)tokens[1]}"
    case "$candidate" in '~/'*) candidate="$HOME/${candidate#\~/}" ;; esac
  fi
  if [[ "$candidate" == *$'\n'* || "$candidate" == *$'\r'* || ! -f "$candidate" || "$candidate" != *.dart ]]; then
    frun_display error "✖ 不是可读取的 .dart 文件：$candidate"; return 2
  fi
  [[ -r "$candidate" ]] || { frun_display error "✖ 文件不可读：$candidate"; return 2; }
  FRUN_TARGET="${candidate:A}"
}
# 轻量检查直接 main 声明和 part；最终语法及入口有效性由 Dart 编译器判定。
frun_validate_entry() {
  if ! /usr/bin/awk '
    /^[[:space:]]*\/\*/ { comment=1 }
    comment { if ($0 ~ /\*\//) comment=0; next }
    /^[[:space:]]*\/\// { next }
    /^[[:space:]]*part[[:space:]]+of([[:space:]]|[\047\042])/ { invalid=1 }
    /^[[:space:]]*((void|Future([[:space:]]*<[^>]+>)?)[[:space:]]+)?main[[:space:]]*\(/ { entry=1 }
    END { exit invalid || !entry }
  ' "$FRUN_TARGET"; then
    frun_display error "✖ 源码未发现直接 main 声明，或它是 part 辅助文件：$FRUN_TARGET"
    return 2
  fi
}
# 从文件真实位置向上找到最近 pubspec，防止跨过嵌套的其它 Dart package。
frun_find_project() {
  local directory="${FRUN_TARGET:h}"
  while [[ ! -f "$directory/pubspec.yaml" ]]; do
    [[ "$directory" != / ]] || { frun_display error '✖ 文件不属于任何含 pubspec.yaml 的工程。'; return 2; }
    directory="${directory:h}"
  done
  if ! /usr/bin/awk '
    /^[^[:space:]#]/ { dependencies=($0 ~ /^dependencies:[[:space:]]*($|#)/); flutter=0; child=0 }
    dependencies && /^[[:space:]]+[^[:space:]#]/ {
      match($0, /[^[:space:]]/); indent=RSTART-1
      if (!child) child=indent
      if (indent == child) {
        flutter=($0 ~ /^[[:space:]]+flutter:[[:space:]]*($|#)/)
        if ($0 ~ /^[[:space:]]+flutter:[[:space:]]*\{[[:space:]]*sdk:[[:space:]]*flutter[[:space:]]*\}/) found=1
      } else if (flutter && indent > child && $0 ~ /^[[:space:]]+sdk:[[:space:]]*flutter([[:space:]]|$)/) found=1
    }
    END { exit !found }
  ' "$directory/pubspec.yaml"; then
    frun_display error "✖ 最近的 pubspec.yaml 未声明 dependencies.flutter.sdk: flutter：$directory/pubspec.yaml"
    return 2
  fi
  FRUN_PROJECT="$directory"
}
# 本地 SDK 优先；存在 FVM 声明时不回退到另一套全局 Flutter。
frun_resolve_sdk() {
  local directory="$FRUN_PROJECT" fvm_root='' flutter_bin=''
  while true; do
    if [[ -f "$directory/.fvmrc" || -f "$directory/.fvm/fvm_config.json" || -e "$directory/.fvm/flutter_sdk" || -L "$directory/.fvm/flutter_sdk" ]]; then
      fvm_root="$directory"; break
    fi
    [[ "$directory" != / ]] || break
    directory="${directory:h}"
  done
  if [[ -n "$fvm_root" ]]; then
    if [[ -x "$fvm_root/.fvm/flutter_sdk/bin/flutter" ]]; then
      FRUN_SDK=("$fvm_root/.fvm/flutter_sdk/bin/flutter")
    elif flutter_bin="$(whence -p fvm 2>/dev/null)" && [[ -n "$flutter_bin" ]]; then
      FRUN_SDK=("$flutter_bin" flutter)
    else
      frun_display error "✖ FVM 工程缺少可用 SDK 链接和 fvm 命令：$fvm_root"
      frun_display body '请先准备项目声明的 FVM SDK；frun 不会用全局 Flutter 替代它。'
      return 127
    fi
  elif flutter_bin="$(whence -p flutter 2>/dev/null)" && [[ -n "$flutter_bin" ]]; then
    FRUN_SDK=("$flutter_bin")
  else
    frun_display error '✖ 未找到 Flutter SDK；请先安装 Flutter 或准备工程的 FVM SDK。'
    return 127
  fi
}
# 展示所属工程、真实入口和无损参数引用；只读模式不执行任何 SDK 命令。
frun_print_plan() {
  local -a command_args=("${FRUN_SDK[@]}" run -t "$FRUN_TARGET")
  [[ -z "$FRUN_DEVICE" ]] || command_args+=(-d "$FRUN_DEVICE")
  command_args+=("${FRUN_FLUTTER_ARGS[@]}")
  frun_display body "工程：$FRUN_PROJECT"
  frun_display body "入口：$FRUN_TARGET"
  frun_display body "命令：${(j: :)${(@q)command_args}}"
}
# 确认后创建每次独立日志；Flutter 的 stdin/stdout 保持直连 TTY。
frun_initialize_run() {
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="$(umask 077; /usr/bin/mktemp "${TMPDIR:-/tmp}/frun.XXXXXXXX")" || return 1
    frun_display body "日志：$LOG_FILE（仅调度与退出码；Flutter 输出直接显示）"
  fi
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
}
# 适配器仅准备 SDK；交互业务直接启动，防止日志监督层夺走 TTY。
frun_run_target() {
  local sdk_adapter="$SCRIPT_DIR/../_lib/【MacOS】FlutterSDK命令适配.sh/【MacOS】FlutterSDK命令适配.sh"
  local -a command_args=("${FRUN_SDK[@]}" run -t "$FRUN_TARGET")
  [[ -z "$FRUN_DEVICE" ]] || command_args+=(-d "$FRUN_DEVICE")
  command_args+=("${FRUN_FLUTTER_ARGS[@]}")
  [[ -f "$sdk_adapter" ]] || { frun_display error "✖ 缺少随包 SDK 命令适配器：$sdk_adapter"; return 127; }
  frun_initialize_run || return $?
  frun_print_plan || return $?
  (
    builtin cd -q -- "$FRUN_PROJECT" || exit 1
    /bin/sh "$sdk_adapter" "${FRUN_SDK[@]}" --version || exit $?
    "${command_args[@]}"
  )
  local result_code=$?
  frun_display body "Flutter 已结束，退出码：$result_code"
  return "$result_code"
}
# 带参运行的确认允许明确 --yes；只读检查不创建运行日志。
frun_confirm_target() {
  (( FRUN_DRY_RUN || FRUN_YES )) && return 0
  [[ -t 0 && -t 1 ]] || { frun_display error '✖ 实际运行需要交互终端；自动化调用须显式传 --yes。'; return 2; }
  local answer=''
  frun_display question '运行此 Demo？[回车继续 / 其它输入取消]'
  IFS= read -r answer || return 130
  [[ -z "$answer" ]]
}
# 完成单目标校验；失败保持明确退出码，不运行 SDK。
frun_prepare_target() {
  frun_resolve_path "$1" || return $?
  frun_validate_entry || return $?
  frun_find_project || return $?
  frun_resolve_sdk || return $?
}
# 备战模式将路径提交作为本次启动确认，运行结束后继续接收下一份源码。
frun_dispatch() {
  local input_path='' result_code=0
  if (( ! FRUN_INTERACTIVE )); then
    frun_prepare_target "$FRUN_TARGET" || exit $?
    frun_print_plan || exit $?
    (( ! FRUN_DRY_RUN )) || exit 0
    frun_confirm_target || exit $?
    frun_run_target
    exit $?
  fi
  [[ -t 0 && -t 1 ]] || { frun_display error '✖ 备战模式需要终端；可用 --dry-run 路径只读检查。'; exit 2; }
  while true; do
    frun_display title 'Flutter 已进入备战状态'
    frun_display question '输入 / 拖入一个 .dart 后回车运行；q 退出：'
    IFS= read -r input_path || exit 0
    case "$input_path" in q|quit|exit) exit 0 ;; '') continue ;; esac
    frun_prepare_target "$input_path" || continue
    frun_run_target
    result_code=$?
    (( result_code != 130 && result_code != 143 && result_code != 129 )) || exit "$result_code"
  done
}
# 首先说明用途，再解析请求并调度独立源码运行。
main() {
  show_script_intro_and_wait "$@" # 先展示影响范围和取消方式。
  frun_parse_arguments "$@" # 解析路径、设备与只读参数。
  frun_dispatch # 校验后运行一次或继续等待下一个 Demo。
}
main "$@"
