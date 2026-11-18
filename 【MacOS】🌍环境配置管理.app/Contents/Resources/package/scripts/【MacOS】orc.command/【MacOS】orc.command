#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】orc.command（ORC 大小写通用）
# - 核心用途：通过 indra-ocr 在本机识别 PDF / 图片并输出 Markdown、文本或 JSON。
# - 影响范围：确认后按需安装独立 Python 环境；首次识别下载模型，已有缓存可离线复用。
# - 运行提示：回车继续、非空取消；--help / --version 只读，--offline 禁止安装及模型联网。
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

# >>> Jobs list parent confirmation >>>
# 只读确认键；返回码20仅交给实际启动本功能的list父菜单。
jobs_list_confirm_start() {
  emulate -L zsh
  local jobs_list_key='' jobs_list_prefix='' jobs_list_direction=''
  [[ -t 0 ]] || return 130
  print -u2 -n -r -- '按回车继续；← 返回功能菜单；Esc / Ctrl+C 取消：'
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

typeset ORC_HOME ORC_VENV ORC_PYTHON ORC_BASE_PYTHON LOG_FILE ORC_LOCK=''
typeset -a ORC_ARGS=()
typeset -i ORC_OFFLINE=0 ORC_INSTALL_ONLY=0

# 将说明写到标准错误，保留标准输出用于 OCR 正文。
orc_note() {
  print -u2 -r -- "$*"
  [[ -z "$LOG_FILE" ]] || print -r -- "$*" >> "$LOG_FILE"
}
# 仅为可用终端渲染自述；重定向及 NO_COLOR 保持纯文本。
orc_intro_line() {
  local role="$1" text="$2" color='0;34'
  [[ "$role" != title ]] || color='1;31'
  if [[ -t 2 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" && "${PLAIN_OUTPUT:-0}" != 1 ]]; then
    printf '\033[%sm%s\033[0m\n' "$color" "$text" >&2
  else
    print -u2 -r -- "$text"
  fi
}
# 显示两种确认选项；任意非空输入或 EOF 均取消。
orc_confirm() {
  local answer=''
  [[ -t 0 ]] || { orc_note '✖ 需要交互终端，未执行安装或识别。'; return 2; }
  if [[ -t 2 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" && "${PLAIN_OUTPUT:-0}" != 1 ]]; then
    printf '%s；\033[1;32m直接回车继续\033[0m；\033[1;31m任意字符后回车取消\033[0m：' "$1" >&2
  else
    print -u2 -n -r -- "$1；直接回车继续；任意字符后回车取消："
  fi
  IFS= read -r answer || return 130
  [[ -z "$answer" ]] || return 130
}
# 只读展示包装参数和上游主要选项，不为帮助安装依赖。
orc_help() {
  cat <<'HELP'
用法：ORC [--offline] 文件 [更多文件...] [indra-ocr 选项]
      ORC                  交互输入文件路径，可从 Finder 拖入
      ORC --install        只按需安装工具，不下载识别模型
      ORC --version        查询已安装的上游版本；不安装、不联网
      ORC --help           查看帮助；不创建日志或环境

orc / ORC / Orc / oRc / orC / ORc / OrC / oRC 均可调用。
--offline                  不安装或修复工具，并强制 HF_HUB_OFFLINE=1
--format md|text|json       默认 Markdown；未指定 --out 时正文写 stdout
--out 目录                 写 .md / .txt / .jsonl，同名结果会被上游覆盖
--mode auto|ocr|text        默认 auto；ocr 强制识别 PDF 文本层
--model-dir 目录            指定完整的本地模型（也可 INDRA_OCR_MODEL_DIR）
--cores / --threads 数量    CPU 线程数
--dpi 数值                 默认 200
--max-pages 数量           默认 0，不限制
--password 密码            PDF 密码
--no-image-ocr              不识别图片
--math                     数学公式识别；首次可能下载额外模型
--keep-furniture           保留页眉页脚
--timings                  显示耗时

示例：ORC "扫描件.pdf" --format text
      orc --offline "图片.png" --out "识别结果"
环境：JOBS_ORC_HOME 可指定工具数据目录；JOBS_ORC_PYTHON 可指定 Python 3.10～3.13。
首次识别通常联网下载约 76 MB 基础模型，完整缓存后可离线；数学模型另计。
提示和日志写 stderr，OCR 正文保持 stdout；按 Ctrl+C 可取消。
HELP
}
# 按运行环境解析持久位置，用户输入的相对数据目录以调用目录为准。
orc_resolve_paths() {
  ORC_HOME="${JOBS_ORC_HOME:-$HOME/.local/share/jobs-orc}"
  ORC_HOME="${ORC_HOME:a}"
  ORC_VENV="$ORC_HOME/venv"
  ORC_PYTHON="$ORC_VENV/bin/python"
}
# 自述确认前只处理只读请求，不创建日志、环境或模型缓存。
show_script_intro_and_wait() {
  local argument
  for argument in "$@"; do
    case "$argument" in
      --) break ;;
      --help|-h) orc_help; exit 0 ;;
      --version)
        orc_resolve_paths
        if [[ -x "$ORC_PYTHON" ]]; then
          "$ORC_PYTHON" -I -B -c 'from importlib.metadata import version; print("indra-ocr " + version("indra-ocr"))'
          exit $?
        fi
        print -u2 -r -- '尚未安装 indra-ocr，请在终端运行 ORC --install。'
        exit 1
        ;;
    esac
  done
  orc_intro_line title '================ ORC：本地 PDF / 图片文字识别 ================'
  orc_intro_line body '1、调用 indra-ocr；参数原样透传，支持 Markdown / 文本 / JSON。'
  orc_intro_line body '2、缺工具时另行确认后准备独立环境；首次识别按需下载模型。'
  orc_intro_line body '3、完整模型缓存可离线；--offline 禁止安装与模型联网。'
  orc_intro_line body '4、--out 会覆盖同名结果；默认仅向标准输出写识别内容。'
  orc_intro_line body "5、日志：${TMPDIR:-/tmp}/orc.log；Ctrl+C 取消。"
  if [[ "${JOBS_LIST_PARENT_MENU:-}" == list ]]; then
    jobs_list_confirm_start
    local confirm_code=$?
    (( confirm_code == 0 )) || exit "$confirm_code"
  else
    orc_confirm '已了解用途与影响' || exit $?
  fi
}
# 确认后准备日志和退出清理，不切换调用者的工作目录。
initialize_orc_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  orc_resolve_paths
  LOG_FILE="${TMPDIR:-/tmp}/orc.log"
  (umask 077; : > "$LOG_FILE") || exit 1
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
}
# 释放仅由本进程创建的安装锁，不删除环境或用户数据。
orc_release_lock() {
  [[ -z "$ORC_LOCK" ]] || rmdir "$ORC_LOCK" 2>/dev/null
}
# 在进程退出时释放本轮锁，子 Shell 不提前清理父进程状态。
TRAPEXIT() {
  local result=$?
  (( ZSH_SUBSHELL != 0 )) || orc_release_lock
  return "$result"
}
# 消费包装器选项，保留上游参数的顺序和边界。
parse_orc_arguments() {
  local argument passthrough=0
  [[ "${HF_HUB_OFFLINE:-0}" != 1 ]] || ORC_OFFLINE=1
  for argument in "$@"; do
    if (( passthrough )); then
      ORC_ARGS+=("$argument")
      continue
    fi
    case "$argument" in
      --offline) ORC_OFFLINE=1 ;;
      --install) ORC_INSTALL_ONLY=1 ;;
      --) passthrough=1; ORC_ARGS+=("$argument") ;;
      *) ORC_ARGS+=("$argument") ;;
    esac
  done
  if (( ORC_INSTALL_ONLY && ( ${#ORC_ARGS} || ORC_OFFLINE ) )); then
    orc_note '✖ --install 请单独使用，不能与输入文件或 --offline 混用。'
    exit 2
  fi
}
# 无参数时安全拆解拖入的路径；不求值其中的 Shell 表达式。
collect_orc_input() {
  (( ORC_INSTALL_ONLY || ${#ORC_ARGS} )) && return 0
  local supplied=''
  local -a tokens
  print -u2 -n -r -- '➤ 输入或拖入 PDF / 图片路径（多个文件可依次拖入，空回车取消）：'
  IFS= read -r supplied || exit 130
  [[ -n "$supplied" ]] || exit 130
  if [[ -f "$supplied" ]]; then
    ORC_ARGS=("$supplied")
  else
    tokens=("${(@z)supplied}")
    ORC_ARGS=("${(@Q)tokens}")
  fi
  local input
  for input in "${ORC_ARGS[@]}"; do
    [[ -f "$input" && -r "$input" ]] || { orc_note "✖ 不是可读取的文件：$input"; exit 2; }
  done
}
# 同时验证虚拟环境归属、CLI 和原生依赖，不触发模型加载或网络请求。
orc_environment_healthy() {
  [[ -x "$ORC_PYTHON" && -f "$ORC_VENV/pyvenv.cfg" && ! -L "$ORC_VENV" ]] || return 1
  "$ORC_PYTHON" -I -B -c '
import sys
from pathlib import Path
assert Path(sys.prefix).resolve() == Path(sys.argv[1]).resolve()
import indra_ocr.cli, onnxruntime, cv2, pypdfium2, huggingface_hub
' "$ORC_VENV" >/dev/null 2>&1
}
# 安装前先核实 pip 确实属于目标虚拟环境，避免写到系统解释器。
orc_venv_healthy() {
  [[ -x "$ORC_PYTHON" && -f "$ORC_VENV/pyvenv.cfg" && ! -L "$ORC_VENV" ]] || return 1
  "$ORC_PYTHON" -I -B -c 'import sys, pip; from pathlib import Path; assert Path(sys.prefix).resolve() == Path(sys.argv[1]).resolve()' "$ORC_VENV" >/dev/null 2>&1
}
# 只接受已知依赖有轮子的 Python 区间，避免误用系统旧版或过新的运行时。
orc_python_healthy() {
  [[ -x "$1" ]] || return 1
  "$1" -I -B -c 'import sys, venv, ssl; assert (3, 10) <= sys.version_info[:2] < (3, 14)' >/dev/null 2>&1
}
# 发现已有解释器；显式指定无效时停止，不悄悄换用其它版本。
orc_find_python() {
  local candidate name prefix
  if [[ -n "${JOBS_ORC_PYTHON:-}" ]]; then
    candidate="${JOBS_ORC_PYTHON:A}"
    orc_python_healthy "$candidate" || { orc_note '✖ JOBS_ORC_PYTHON 必须是健康的 Python 3.10～3.13。'; return 2; }
    print -r -- "$candidate"
    return 0
  fi
  for name in python3.12 python3.13 python3.11 python3.10 python3; do
    candidate="$(command -v "$name" 2>/dev/null)"
    if orc_python_healthy "$candidate"; then print -r -- "$candidate"; return 0; fi
    for prefix in /opt/homebrew /usr/local "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}"; do
      candidate="$prefix/bin/$name"
      if orc_python_healthy "$candidate"; then print -r -- "$candidate"; return 0; fi
    done
  done
  return 1
}
# 缺少兼容解释器时只补本任务的 Python，不升级其它公式或改写启动配置。
orc_prepare_python() {
  local candidate code=0 brew_bin='' prefix=''
  candidate="$(orc_find_python)" || code=$?
  if (( code == 0 )); then
    ORC_BASE_PYTHON="$candidate"
    return 0
  fi
  (( code != 2 )) || return 2
  for candidate in "${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew"; do
    [[ -x "$candidate" ]] || continue
    HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || continue
    prefix="$("$candidate" --prefix 2>/dev/null)" || continue
    [[ -d "$prefix" ]] || continue
    brew_bin="$candidate"
    break
  done
  [[ -n "$brew_bin" ]] || { orc_note '✖ 缺少 Python 3.10～3.13 和健康 Homebrew；请先准备 Homebrew 或通过 JOBS_ORC_PYTHON 指定已有解释器。'; return 1; }
  orc_note 'ℹ 补齐本任务必需的 python@3.12，不更新其它工具。'
  HOMEBREW_NO_AUTO_UPDATE=1 "$brew_bin" install python@3.12 >> "$LOG_FILE" 2>&1 || { orc_note "✖ brew install python@3.12 失败，见日志：$LOG_FILE"; return 1; }
  prefix="$("$brew_bin" --prefix python@3.12)" || return 1
  ORC_BASE_PYTHON="$prefix/bin/python3.12"
  orc_python_healthy "$ORC_BASE_PYTHON"
}
# 安装日志实时送到终端和文件，网络获取失败退避重试，其它错误直接停止。
orc_install_packages() {
  local result=0 delay=2 attempt=0 attempt_log
  local -a stages
  attempt_log="$(mktemp "${TMPDIR:-/tmp}/orc-pip.XXXXXXXX")" || return 1
  while true; do
    attempt=$((attempt + 1))
    orc_note "ℹ 安装 indra-ocr（第 $attempt 次）；Ctrl+C 可取消。"
    env -u PIP_TARGET -u PIP_PREFIX -u PIP_USER -u PIP_ROOT -u PIP_PYTHON PIP_CONFIG_FILE=/dev/null \
      "$ORC_PYTHON" -I -B -m pip install --prefix "$ORC_VENV" --no-user --no-color --disable-pip-version-check --no-input indra-ocr 2>&1 | tee "$attempt_log" | tee -a "$LOG_FILE" >&2
    stages=("${pipestatus[@]}")
    result=${stages[1]}
    if (( stages[2] != 0 || stages[3] != 0 )); then
      /bin/rm -f "$attempt_log"
      orc_note '✖ 安装输出或日志写入失败，停止后续识别。'
      return 1
    fi
    (( result != 0 )) || { /bin/rm -f "$attempt_log"; return 0; }
    case "$result" in 129|130|143) /bin/rm -f "$attempt_log"; return "$result" ;; esac
    if ! LC_ALL=C grep -Eqi 'Connection(Error|Reset|Refused)|ConnectTimeout|ReadTimeout|Temporary failure|Network is unreachable|Max retries exceeded|timed out|IncompleteRead|HTTP[^[:cntrl:]]* (429|50[0234])' "$attempt_log"; then
      /bin/rm -f "$attempt_log"
      return "$result"
    fi
    orc_note "⚠ 网络获取失败，${delay} 秒后重试；按 Ctrl+C 停止。"
    sleep "$delay" || return 130
    (( delay >= 30 )) || delay=$(( delay * 2 > 30 ? 30 : delay * 2 ))
  done
}
# 仅在依赖缺失且本轮得到确认后创建或补齐独立虚拟环境。
prepare_orc_environment() {
  [[ ! -e "$ORC_HOME/install.lock" ]] || { orc_note "✖ 安装锁已存在：$ORC_HOME/install.lock；请等待该安装完成，异常退出后确认无人使用再移除此空目录。"; exit 1; }
  if orc_environment_healthy; then
    orc_note '✔ 复用已有 indra-ocr 环境，不执行安装或升级。'
    return 0
  fi
  if (( ORC_OFFLINE )); then
    orc_note '✖ 离线模式下 indra-ocr 环境不可用；请联网运行 ORC --install 后再试。'
    exit 1
  fi
  orc_note "ℹ 将在 $ORC_VENV 按需准备 Python 和 pip install indra-ocr；不写系统 Python。"
  orc_confirm '必需环境未就绪，联网安装依赖' || exit $?
  [[ ! -L "$ORC_HOME" && ! -L "$ORC_VENV" ]] || { orc_note '✖ 工具目录或虚拟环境是符号链接，未自动修改。'; exit 1; }
  mkdir -p "$ORC_HOME" || exit 1
  mkdir "$ORC_HOME/install.lock" || { orc_note '✖ 已有另一个安装进程，未修改环境。'; exit 1; }
  ORC_LOCK="$ORC_HOME/install.lock"
  if ! orc_venv_healthy; then
    if [[ -e "$ORC_VENV" ]]; then
      orc_note "✖ 原有虚拟环境损坏，已保留：$ORC_VENV；请先移走该目录后重试。"
      exit 1
    fi
    orc_prepare_python || exit $?
    "$ORC_BASE_PYTHON" -I -B -m venv "$ORC_VENV" >> "$LOG_FILE" 2>&1 || { orc_note '✖ 创建虚拟环境失败，未执行识别。'; exit 1; }
  fi
  orc_install_packages || { local result=$?; orc_note "✖ indra-ocr 安装失败（退出码 $result），见日志：$LOG_FILE"; exit "$result"; }
  orc_environment_healthy || { orc_note "✖ 安装后原生依赖复检失败，请查看日志并核对 Python / 系统架构：$LOG_FILE"; exit 1; }
  orc_release_lock
  ORC_LOCK=''
  orc_note '✔ indra-ocr 环境已通过依赖复检。'
}
# 标准输出只交给上游；密码等输入参数不写入包装器日志。
run_orc_business() {
  if (( ORC_INSTALL_ONLY )); then
    orc_note '✔ 工具已就绪；模型将在首次识别时按需下载，--install 不预下载模型。'
    return 0
  fi
  local result=0
  # 默认模型缓存与本工具同处；显式缓存设置（包括空值）继续保留。
  if [[ -z "${HF_HOME+x}" && -z "${HF_HUB_CACHE+x}" ]]; then
    export HF_HOME="$ORC_HOME/models"
  fi
  if (( ORC_OFFLINE )); then
    orc_note 'ℹ 严格离线识别：不安装依赖，禁止 Hugging Face 模型联网。'
    HF_HUB_OFFLINE=1 "$ORC_PYTHON" -I -B -m indra_ocr.cli "${ORC_ARGS[@]}" 2> >(tee -a "$LOG_FILE" >&2) || result=$?
  else
    orc_note 'ℹ 开始本地识别；未缓存的模型可能首次联网下载。'
    "$ORC_PYTHON" -I -B -m indra_ocr.cli "${ORC_ARGS[@]}" 2> >(tee -a "$LOG_FILE" >&2) || result=$?
  fi
  orc_note "ℹ indra-ocr 退出码：$result；日志：$LOG_FILE"
  exit "$result"
}
# 集中编排确认、输入、依赖与识别流程。
main() {
  show_script_intro_and_wait "$@" # 先说明本地识别及首次联网影响，再确认。
  initialize_orc_runtime # 确认后才创建日志并准备运行路径。
  parse_orc_arguments "$@" # 识别离线和安装模式，其它参数保持原样。
  collect_orc_input # 无参数时取得实际文件，避免误调用就下载依赖。
  prepare_orc_environment # 复用健康环境，缺失时经确认补齐并复检。
  run_orc_business # 调用官方 CLI，保留纯净标准输出和真实退出码。
}

main "$@"
