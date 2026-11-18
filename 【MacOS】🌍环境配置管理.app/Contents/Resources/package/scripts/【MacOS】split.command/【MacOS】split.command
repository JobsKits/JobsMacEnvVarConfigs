#!/bin/zsh
# 脚本自述：
# - 脚本名称：Jobs 文件拆分（运行时按当前文件名显示）。
# - 核心用途：手动输入或拖入单文件 / 目录，持续校验，按上限拆成可还原的分卷。
# - 影响范围：只新增分卷目录；校验成功后精确输入 YES 才删除源文件。
# - 运行提示：先确认自述，再检查系统工具和 fzf；不安装软件或修改 Shell 配置。

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
TARGET_FILE=""
MAX_CHUNK_BYTES=$((50 * 1024 * 1024))
MAX_CHUNK_LABEL="50 MiB"
STANDARD_QUERY=""
FILE_QUERY=""
REPLY=""
FZF_LINES=()
LARGE_FILES=()
SELECTED_FILES=()
ACTIVE_STAGING_DIR=""

# 在自述之前只解析脚本位置，不创建日志或修改目标。
prepare_display() {
  SCRIPT_PATH="${SCRIPT_SOURCE_PATH:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
}
# 按终端能力显示自述，日志始终保留可搜索的纯文本。
print_styled() {
  local style="$1" message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$style" "$message"
  else
    printf '%s\n' "$message"
  fi
}
# 同步显示业务信息和纯文本日志。
log() {
  local message="$1"
  print_styled "${2:-0}" "$message"
  [[ "${LOG_READY:-0}" != 1 ]] || printf '%s\n' "$message" >> "$LOG_FILE"
}
# 以信息级别记录当前处理状态。
info_echo() {
  log "ℹ $1" '1;34'
}
# 以成功级别记录已验证的操作结果。
success_echo() {
  log "✔ $1" '1;32'
}
# 以警告级别记录取消、跳过或需关注的状态。
warn_echo() {
  log "⚠ $1" '1;33'
}
# 以错误级别记录失败对象与原因。
error_echo() {
  log "✖ $1" '1;31'
}
# 第一屏说明影响范围，确认之前不创建日志或写入目标。
show_script_intro_and_wait() {
  prepare_display
  print_styled '1;31' "======== Jobs 文件拆分（${SCRIPT_PATH:t}）========"
  print_styled '0;34' "工具版本：$SCRIPT_VERSION"
  print_styled '0;34' '1、每次手动输入 / 拖入单文件或目录；空输入、无效路径和无可拆文件持续重问，不递归。'
  print_styled '0;34' '2、分卷上限：50 MiB、100 MiB、1900 MiB 或自定义 MiB。'
  print_styled '0;34' '3、先在独占临时目录生成分卷，大小和 SHA-256 校验成功后发布。'
  jobs_prompt_output print_styled '0;34' '4、已有分卷目录不覆盖；删除源文件必须精确输入 YES，回车保留。'
  print_styled '0;34' '5、仅检查系统工具与 fzf，不安装或升级软件，不修改 Shell 配置。'
  print_styled '0;34' "日志：${LOG_FILE}；Ctrl+C 可取消。"
  if [[ ! -t 0 ]]; then
    print_styled '1;31' '✖ 缺少可交互输入，请在终端中运行。'
    exit 1
  fi
  jobs_prompt_output printf '➤ 按 [Enter] 继续，或 Ctrl+C 退出：'
  IFS= jobs_list_intro_read -r REPLY || exit 1
}
# 确认后初始化运行选项、相对定位和日志。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  SCRIPT_PATH="${SCRIPT_SOURCE_PATH:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  : > "$LOG_FILE" || exit 1
  LOG_READY=1
  trap 'handle_interruption INT' INT
  trap 'handle_interruption TERM' TERM
}
# 取消时保留独占临时目录，显示恢复排查所需的位置。
handle_interruption() {
  warn_echo "收到 $1，已停止拆分；源文件保留。"
  [[ -z "$ACTIVE_STAGING_DIR" ]] || warn_echo "临时结果保留：$ACTIVE_STAGING_DIR"
  [[ "$1" == INT ]] && exit 130
  exit 143
}
# 验证真实执行所需工具及当前 fzf 选项，不触发安装或升级。
check_environment() {
  local executable probe_rc=0
  for executable in /usr/bin/split /usr/bin/stat /usr/bin/shasum /usr/bin/find /usr/bin/mktemp /bin/cat /bin/mv /usr/bin/osascript; do
    if [[ ! -x "$executable" ]]; then
      error_echo "系统工具不可用：$executable"
      exit 1
    fi
  done
  if ! command -v fzf >/dev/null 2>&1 || ! fzf --version >/dev/null 2>&1; then
    error_echo 'fzf 缺失或损坏；请先安装或修复 fzf 后重试。'
    exit 1
  fi
  printf '' | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' fzf --filter='' --multi --print-query --expect=left \
    --header='' --footer='' --bind='enter:toggle,ctrl-a:select-all,ctrl-d:deselect-all,space:transform:if [ "${FZF_SELECT_COUNT:-0}" -gt 0 ]; then echo accept; else echo abort; fi' \
    >/dev/null 2>> "$LOG_FILE" || probe_rc=$?
  if (( probe_rc > 1 )); then
    error_echo '当前 fzf 不支持所需选项，请更新 fzf 后重试。'
    exit 1
  fi
  info_echo "环境检查完成；日志：$LOG_FILE"
}
# 原路径优先，再安全解析拖入引用和转义；不执行输入中的任何代码。
normalize_target_input() {
  local candidate="$1"
  local -a tokens=()
  REPLY=''
  if [[ ( -d "$candidate" || -f "$candidate" ) && ! -L "$candidate" ]]; then
    REPLY="${candidate:A}"
    return 0
  fi
  while [[ "$candidate" == [\ $'\t\r\n\u00a0\u3000']* ]]; do
    candidate="${candidate[2,-1]}"
  done
  while [[ "$candidate" == *[\ $'\t\r\n\u00a0\u3000'] ]]; do
    candidate="${candidate[1,-2]}"
  done
  [[ -n "$candidate" ]] || return 1
  if [[ ( -d "$candidate" || -f "$candidate" ) && ! -L "$candidate" ]]; then
    REPLY="${candidate:A}"
    return 0
  fi
  tokens=("${(@z)candidate}") 2>/dev/null || return 1
  (( ${#tokens} == 1 )) || return 1
  candidate="${(Q)tokens[1]}"
  [[ "$candidate" != '~/'* ]] || candidate="${HOME}/${candidate#'~/'}"
  [[ ( -d "$candidate" || -f "$candidate" ) && ! -L "$candidate" ]] || return 1
  REPLY="${candidate:A}"
}
# 计算源文件对应的分卷目录，保留蓝本的同级命名约定。
get_output_directory() {
  local filename="${1:t}" base_no_ext="${${1:t}%.*}"
  [[ -n "$base_no_ext" ]] || base_no_ext="$filename"
  REPLY="${1:h}/$base_no_ext"
  [[ "$base_no_ext" != "$filename" ]] || REPLY="${1}.parts"
}
# 只接收有内容且可产生新输出的普通源文件。
is_splittable_file() {
  local file="$1" filename="${1:t}" bytes=''
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || return 1
  [[ "$filename" != .* && ! "$filename" =~ '@[0-9]+of[0-9]+$' ]] || return 1
  bytes="$(/usr/bin/stat -f %z "$file")" || return 1
  (( bytes > 1 )) || return 1
  get_output_directory "$file"
  [[ ! -e "$REPLY" && ! -L "$REPLY" ]]
}
# 持续询问手动目标，直到存在可拆分的真实文件。
choose_target_directory() {
  local input='' file='' size=0 found=0
  while true; do
    log '➤ 手动输入或拖入单个目标目录（也可拖入一个文件）；Ctrl+C 退出：'
    IFS= read -r input || return 1
    TARGET_DIR=''
    TARGET_FILE=''
    if ! normalize_target_input "$input"; then
      error_echo '请输入存在的单个普通文件或目录；空输入、多路径及符号链接不接受。'
      continue
    fi
    if [[ -f "$REPLY" ]]; then
      TARGET_FILE="$REPLY"
      TARGET_DIR="${REPLY:h}"
    else
      TARGET_DIR="$REPLY"
    fi
    if [[ ! -r "$TARGET_DIR" || ! -x "$TARGET_DIR" || ! -w "$TARGET_DIR" ]]; then
      error_echo "目录必须可读取、可进入且可写入：$TARGET_DIR"
      continue
    fi
    found=0
    if [[ -n "$TARGET_FILE" ]]; then
      is_splittable_file "$TARGET_FILE" && found=1
    else
      while IFS= read -r -d '' file; do
        if is_splittable_file "$file"; then
          found=1
          break
        fi
      done < <(/usr/bin/find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type f -print0)
    fi
    if (( ! found )); then
      error_echo '目标中没有可拆分文件（需可读、非空、非已有分卷，且输出目录未被占用），请重新输入。'
      continue
    fi
    info_echo "目标：${TARGET_FILE:-$TARGET_DIR}"
    return 0
  done
}
# 拒绝以参数或默认路径绕过手动目标选择。
require_target_directory() {
  if (( $# > 0 )); then
    error_echo '此入口不接受路径参数；请启动后手动输入或拖入目标。'
    exit 1
  fi
  choose_target_directory || exit 1
}
# 保留 fzf 空查询和空按键行，以区分返回、空选与选择器失败。
parse_fzf_output() {
  local output="$1" line=''
  FZF_LINES=()
  while IFS= read -r line; do
    FZF_LINES+=("$line")
  done <<< "$output"
}
# 验证 MiB 输入并转换成至少一个字节的整数上限。
set_custom_limit() {
  local custom_mb='' answer='' bytes=''
  while true; do
    jobs_prompt_output log '➤ 输入自定义上限（MiB，可带小数）；直接回车返回标准选择：'
    IFS= read -r custom_mb || return 2
    [[ -n "$custom_mb" ]] || return 3
    if [[ ! "$custom_mb" =~ '^[0-9]+([.][0-9]+)?$' ]]; then
      warn_echo '请输入大于 0 的数字。'
      continue
    fi
    bytes="$(/usr/bin/awk -v mb="$custom_mb" 'BEGIN { n = mb * 1048576; if (n >= 1 && n <= 9007199254740991) printf "%.0f", int(n) }')"
    if [[ -z "$bytes" ]]; then
      warn_echo '上限必须至少为 1 字节，且不能超过可精确表示的范围。'
      continue
    fi
    jobs_prompt_output log "➤ 分卷上限：${custom_mb} MiB（${bytes} 字节）；回车确认，任意字符重新输入："
    IFS= read -r answer || return 2
    if [[ -z "$answer" ]]; then
      MAX_CHUNK_BYTES="$bytes"
      MAX_CHUNK_LABEL="${custom_mb} MiB"
      return 0
    fi
  done
}
# 通过根层 fzf 选择上限，取消时不形成执行计划。
choose_split_standard() {
  local output='' choice='' selection_rc=0 custom_rc=0
  while true; do
    selection_rc=0
    output="$(printf '%s\n' '50MiB|50 MiB（默认）' '100MiB|100 MiB' '1900MiB|1900 MiB' 'CUSTOM|自定义 MiB' 'CANCEL|取消本轮' | \
      FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' fzf --no-multi --print-query --query="$STANDARD_QUERY" \
        --height=12 --layout=reverse --border --delimiter='|' --with-nth=2 \
        --bind='up:up,down:down,tab:down,shift-tab:up' --header='↑/↓ 或 Tab 选择；回车确认；Esc 取消' --footer='↑/↓ 或 Tab 选择；回车确认；Esc 取消' --prompt='分卷上限 > ')" || selection_rc=$?
    parse_fzf_output "$output"
    STANDARD_QUERY="${FZF_LINES[1]:-}"
    if (( selection_rc == 130 || selection_rc == 1 )); then
      return 2
    fi
    if (( selection_rc != 0 )); then
      error_echo "fzf 标准选择失败（退出码 $selection_rc）。"
      return 1
    fi
    choice="${FZF_LINES[2]%%|*}"
    case "$choice" in
      50MiB) MAX_CHUNK_BYTES=$((50 * 1024 * 1024)); MAX_CHUNK_LABEL='50 MiB' ;;
      100MiB) MAX_CHUNK_BYTES=$((100 * 1024 * 1024)); MAX_CHUNK_LABEL='100 MiB' ;;
      1900MiB) MAX_CHUNK_BYTES=$((1900 * 1024 * 1024)); MAX_CHUNK_LABEL='1900 MiB' ;;
      CANCEL) return 2 ;;
      CUSTOM)
        custom_rc=0
        set_custom_limit || custom_rc=$?
        (( custom_rc == 3 )) && continue
        (( custom_rc == 0 )) || return "$custom_rc"
        ;;
      *) error_echo 'fzf 返回了无法识别的标准。'; return 1 ;;
    esac
    info_echo "分卷上限：$MAX_CHUNK_LABEL（$MAX_CHUNK_BYTES 字节）"
    return 0
  done
}
# 仅扫描目标目录的普通大文件，避免再次拆分已有分卷。
find_large_files() {
  local file='' size=0
  LARGE_FILES=()
  if [[ -n "$TARGET_FILE" ]]; then
    if is_splittable_file "$TARGET_FILE"; then
      size="$(/usr/bin/stat -f %z "$TARGET_FILE")" || return 1
      (( size > MAX_CHUNK_BYTES )) && LARGE_FILES=("$TARGET_FILE")
    fi
  else
    while IFS= read -r -d '' file; do
      is_splittable_file "$file" || continue
      size="$(/usr/bin/stat -f %z "$file")" || return 1
      (( size > MAX_CHUNK_BYTES )) && LARGE_FILES+=("$file")
    done < <(/usr/bin/find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type f -print0)
  fi
  if (( ${#LARGE_FILES} == 0 )); then
    warn_echo "没有超过 $MAX_CHUNK_LABEL 的可拆分文件；请重输目标，并按需调低分卷上限。"
    return 2
  fi
  LARGE_FILES=("${(@on)LARGE_FILES}")
  return 0
}
# 通过多选面板形成计划，左方向键返回标准，空选不会选中高亮项。
select_large_files() {
  local output='' selection_rc=0 row='' id='' i=1
  local -a rows=($'ALL\t全选' $'CLEAR\t清空' $'CANCEL\t取消本轮')
  SELECTED_FILES=()
  for row in "${LARGE_FILES[@]}"; do
    rows+=("${i}"$'\t'"${(q)row:t}")
    (( i += 1 ))
  done
  local hints='↑/↓ 或 Tab 移动；回车勾选/操作；空格确认；← 返回标准；Esc 取消'
  output="$(printf '%s\n' "${rows[@]}" | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' fzf \
    --multi --print-query --expect=left --query="$FILE_QUERY" --height=80% --layout=reverse --border \
    --delimiter=$'\t' --with-nth=2.. --header="$hints" --footer="$hints" --prompt='待拆分文件 > ' \
    --bind='up:up,down:down,tab:down,shift-tab:up,ctrl-a:select-all,ctrl-d:deselect-all' \
    --bind='enter:transform:case "$FZF_CURRENT_ITEM" in ALL*) echo select-all ;; CLEAR*) echo deselect-all ;; CANCEL*) echo abort ;; *) echo toggle ;; esac' \
    --bind='space:transform:case "$FZF_CURRENT_ITEM" in ALL*) echo select-all ;; CLEAR*) echo deselect-all ;; CANCEL*) echo abort ;; *) if [ "${FZF_SELECT_COUNT:-0}" -gt 0 ]; then echo accept; else echo abort; fi ;; esac')" || selection_rc=$?
  parse_fzf_output "$output"
  FILE_QUERY="${FZF_LINES[1]:-}"
  [[ "${FZF_LINES[2]:-}" == left ]] && return 3
  if (( selection_rc == 130 || selection_rc == 1 )); then
    return 2
  fi
  if (( selection_rc != 0 )); then
    error_echo "fzf 文件选择失败（退出码 $selection_rc）。"
    return 1
  fi
  for row in "${FZF_LINES[@]:2}"; do
    [[ -n "$row" ]] || continue
    id="${row%%$'\t'*}"
    [[ "$id" != ALL && "$id" != CLEAR && "$id" != CANCEL ]] || continue
    if [[ "$id" != <-> ]] || (( id < 1 || id > ${#LARGE_FILES} )); then
      error_echo 'fzf 返回了无效的文件编号。'
      return 1
    fi
    SELECTED_FILES+=("${LARGE_FILES[id]}")
  done
  (( ${#SELECTED_FILES} > 0 )) || return 2
}
# 读取源文件摘要，不依赖文件名输出格式。
file_sha256() {
  /usr/bin/shasum -a 256 < "$1" | /usr/bin/awk '{ print $1 }'
}
# 串联分卷内容，为校验提供恒定内存的输入流。
stream_parts() {
  local part=''
  for part in "$@"; do
    /bin/cat "$part" || return 1
  done
}
# 校验完成后仅接受精确 YES 删除源文件，其它输入和 EOF 均保留。
confirm_delete_source() {
  local source_file="$1" expected_hash="$2" expected_identity="${3:-}" answer='' current_hash='' current_identity=''
  local parts_dir="${4:-}" expected_count="${5:-0}" part='' parts_hash=''
  local -a current_parts=()
  log "➤ 是否删除源文件：$source_file"
  jobs_prompt_output log '危险操作：只有输入 YES 后回车才删除；直接回车、其它输入或输入结束均保留。'
  IFS= read -r answer || answer=''
  if [[ "$answer" != YES ]]; then
    info_echo "已保留源文件：$source_file"
    return 0
  fi
  if [[ ! -f "$source_file" || -L "$source_file" ]]; then
    error_echo "源文件已被替换或不再是普通文件，拒绝删除：$source_file"
    return 1
  fi
  current_identity="$(/usr/bin/stat -f '%d:%i' "$source_file")" || return 1
  if [[ -n "$expected_identity" && "$current_identity" != "$expected_identity" ]]; then
    error_echo "源文件身份发生变化，拒绝删除：$source_file"
    return 1
  fi
  current_hash="$(file_sha256 "$source_file")" || return 1
  if [[ "$current_hash" != "$expected_hash" ]]; then
    error_echo "源文件已变化，拒绝删除：$source_file"
    return 1
  fi
  if [[ -n "$parts_dir" ]]; then
    [[ -d "$parts_dir" && ! -L "$parts_dir" ]] || return 1
    while IFS= read -r -d '' part; do
      current_parts+=("$part")
    done < <(/usr/bin/find "$parts_dir" -mindepth 1 -maxdepth 1 -type f -print0)
    current_parts=("${(@o)current_parts}")
    parts_hash="$(stream_parts "${current_parts[@]}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }')" || return 1
    if (( ${#current_parts} != expected_count )) || [[ "$parts_hash" != "$expected_hash" ]]; then
      error_echo '已发布分卷被改动或缺失，保留源文件。'
      return 1
    fi
  fi
  if /bin/rm -f -- "$source_file"; then
    success_echo "已删除源文件：$source_file"
  else
    error_echo "删除源文件失败：$source_file"
    return 1
  fi
}
# 以系统排他重命名发布整个目录，目标并发出现时失败，不套入已有目录。
publish_directory_exclusively() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JOBS_RENAME'
ObjC.import('Foundation');
ObjC.bindFunction('renamex_np', ['int', ['char *', 'char *', 'unsigned int']]);
ObjC.bindFunction('__error', ['int *', []]);
ObjC.bindFunction('strerror', ['char *', ['int']]);
function run(args) {
  if ($.renamex_np(args[0], args[1], 4) !== 0) {
    var code = $.__error()[0];
    throw new Error('排他发布失败（' + code + '）：' + $.strerror(code));
  }
}
JOBS_RENAME
}
# 在独占临时目录拆分并验证，完整目录只在校验通过后发布一次。
split_one_file() {
  local file="$1" filename="${1:t}" parent_dir="${1:h}" base_no_ext='' output_dir=''
  local file_size=0 planned_count=0 chunk_size=0 suffix_width=1 capacity=26 actual_count=0
  local staging_dir='' part='' renamed_part='' source_hash='' parts_hash='' final_hash='' source_identity=''
  local total_bytes=0 part_size=0 index=1 width=1 index_padded='' total_padded=''
  local -a parts=() published_parts=()
  [[ -f "$file" && ! -L "$file" ]] || { error_echo "不是普通源文件：$file"; return 1; }
  file_size="$(/usr/bin/stat -f %z "$file")" || return 1
  if (( file_size <= MAX_CHUNK_BYTES || file_size == 0 )); then
    info_echo "文件未超过分卷上限，跳过：$file"
    return 0
  fi
  get_output_directory "$file"
  output_dir="$REPLY"
  if [[ -e "$output_dir" || -L "$output_dir" ]]; then
    error_echo "分卷目标已存在，拒绝覆盖：$output_dir"
    return 1
  fi
  planned_count=$(( 1 + (file_size - 1) / MAX_CHUNK_BYTES ))
  chunk_size=$(( 1 + (file_size - 1) / planned_count ))
  actual_count=$(( 1 + (file_size - 1) / chunk_size ))
  while (( capacity < actual_count )); do
    (( suffix_width += 1 ))
    (( capacity *= 26 ))
  done
  staging_dir="$(/usr/bin/mktemp -d "${parent_dir}/.split.XXXXXXXX")" || return 1
  ACTIVE_STAGING_DIR="$staging_dir"
  info_echo "临时结果（失败或中断时保留）：$staging_dir"
  info_echo "来源：$file"
  info_echo "目标：$output_dir；上限 $MAX_CHUNK_BYTES 字节；计划 $actual_count 卷，主卷 $chunk_size 字节。"
  source_identity="$(/usr/bin/stat -f '%d:%i' "$file")" || return 1
  source_hash="$(file_sha256 "$file")" || return 1
  if ! /usr/bin/split -b "$chunk_size" -a "$suffix_width" "$file" "${staging_dir}/part_" 2>> "$LOG_FILE"; then
    error_echo "split 执行失败；保留源文件和临时结果：$staging_dir"
    return 1
  fi
  while IFS= read -r -d '' part; do
    parts+=("$part")
  done < <(/usr/bin/find "$staging_dir" -mindepth 1 -maxdepth 1 -type f -print0)
  parts=("${(@o)parts}")
  if (( ${#parts} != actual_count )); then
    error_echo "分卷数量不符；保留临时结果：$staging_dir"
    return 1
  fi
  for part in "${parts[@]}"; do
    part_size="$(/usr/bin/stat -f %z "$part")" || return 1
    if (( part_size < 1 || part_size > MAX_CHUNK_BYTES )); then
      error_echo "分卷大小超出上限或为空：$part"
      return 1
    fi
    (( total_bytes += part_size ))
  done
  parts_hash="$(stream_parts "${parts[@]}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }')" || return 1
  final_hash="$(file_sha256 "$file")" || return 1
  if (( total_bytes != file_size )) || [[ "$source_hash" != "$parts_hash" || "$source_hash" != "$final_hash" ]]; then
    error_echo "大小或 SHA-256 校验失败；保留源文件和临时结果：$staging_dir"
    return 1
  fi
  width="${#actual_count}"
  printf -v total_padded "%0${width}d" "$actual_count"
  for part in "${parts[@]}"; do
    printf -v index_padded "%0${width}d" "$index"
    renamed_part="${staging_dir}/${filename}@${index_padded}of${total_padded}"
    if ! /bin/mv -n "$part" "$renamed_part"; then
      error_echo "分卷命名失败；保留临时结果：$staging_dir"
      return 1
    fi
    published_parts+=("${output_dir}/${filename}@${index_padded}of${total_padded}")
    (( index += 1 ))
  done
  if [[ -e "$output_dir" || -L "$output_dir" ]]; then
    error_echo "发布前发现目标已存在；保留临时结果：$staging_dir"
    return 1
  fi
  if ! publish_directory_exclusively "$staging_dir" "$output_dir" 2>> "$LOG_FILE"; then
    error_echo "分卷发布失败；保留临时结果：$staging_dir"
    return 1
  fi
  if [[ -d "${output_dir}/${staging_dir:t}" ]]; then
    ACTIVE_STAGING_DIR="${output_dir}/${staging_dir:t}"
  else
    ACTIVE_STAGING_DIR="$output_dir"
  fi
  parts=()
  while IFS= read -r -d '' part; do
    parts+=("$part")
  done < <(/usr/bin/find "$output_dir" -mindepth 1 -maxdepth 1 -type f -print0)
  if [[ -L "$output_dir" ]] || (( ${#parts} != actual_count )); then
    error_echo "发布目录清单不符，拒绝删除源文件；结果：$ACTIVE_STAGING_DIR"
    return 1
  fi
  for part in "${published_parts[@]}"; do
    if [[ ! -f "$part" || -L "$part" ]]; then
      error_echo "发布分卷未位于目标根部，拒绝删除源文件；结果：$ACTIVE_STAGING_DIR"
      return 1
    fi
  done
  parts_hash="$(stream_parts "${published_parts[@]}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }')" || return 1
  if [[ "$parts_hash" != "$source_hash" ]]; then
    error_echo "发布后 SHA-256 校验失败；保留源文件和结果：$ACTIVE_STAGING_DIR"
    return 1
  fi
  ACTIVE_STAGING_DIR=''
  success_echo "已拆分并通过 SHA-256 校验：$output_dir（$actual_count 卷）"
  confirm_delete_source "$file" "$source_hash" "$source_identity" "$output_dir" "$actual_count"
}
# 顺序执行已确认计划，单项失败仍汇总真实失败状态。
run_selected_files() {
  local file='' failures=0
  info_echo "待拆分文件：${#SELECTED_FILES} 个。"
  for file in "${SELECTED_FILES[@]}"; do
    ACTIVE_STAGING_DIR=''
    if ! split_one_file "$file"; then
      [[ -z "$ACTIVE_STAGING_DIR" ]] || warn_echo "保留待排查结果：$ACTIVE_STAGING_DIR"
      (( failures += 1 ))
    fi
  done
  if (( failures > 0 )); then
    error_echo "拆分流程结束，失败 $failures 项；日志：$LOG_FILE"
    return 1
  fi
  success_echo "拆分流程结束；日志：$LOG_FILE"
}
# 展示执行计划并默认取消，左键只返回上一选择层。
confirm_split_plan() {
  local output='' rc=0 file=''
  info_echo "待执行拆分：${#SELECTED_FILES} 个文件；分卷上限 $MAX_CHUNK_LABEL。"
  for file in "${SELECTED_FILES[@]}"; do
    get_output_directory "$file"
    log "来源：$file → 分卷目录：$REPLY"
  done
  output="$(printf '%s\n' 'CANCEL|取消本轮（默认）' 'RUN|开始拆分并校验' | \
    FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' fzf --no-multi --expect=left \
      --height=12 --layout=reverse --border --delimiter='|' --with-nth=2 \
      --bind='up:up,down:down,tab:down,shift-tab:up' \
      --header='↑/↓ 选择；回车确认；← 返回上一层；Esc 取消' \
      --footer='↑/↓ 选择；回车确认；← 返回上一层；Esc 取消' --prompt='确认拆分 > ')" || rc=$?
  [[ "$output" == left$'\n'* || "$output" == left ]] && return 3
  (( rc == 130 || rc == 1 )) && return 2
  (( rc == 0 )) || { error_echo "执行确认失败（退出码 $rc）。"; return 1; }
  [[ "$output" == *$'\nRUN|'* ]] || return 2
}
# 循环编排标准和文件选择，返回动作只改变计划，不执行拆分。
plan_and_split() {
  local selection_rc=0
  while true; do
    selection_rc=0
    choose_split_standard || selection_rc=$?
    if (( selection_rc == 2 )); then
      info_echo '已取消标准选择。'
      return 0
    fi
    (( selection_rc == 0 )) || return 1
    selection_rc=0
    find_large_files || selection_rc=$?
    if (( selection_rc == 2 )); then
      require_target_directory
      continue
    fi
    (( selection_rc == 0 )) || return 1
    while true; do
      if [[ -n "$TARGET_FILE" ]]; then
        SELECTED_FILES=("$TARGET_FILE")
      else
        selection_rc=0
        select_large_files || selection_rc=$?
        (( selection_rc == 3 )) && break
        if (( selection_rc == 2 )); then
          info_echo '未勾选文件或已取消，未执行拆分。'
          return 0
        fi
        (( selection_rc == 0 )) || return 1
      fi
      selection_rc=0
      confirm_split_plan || selection_rc=$?
      if (( selection_rc == 3 )); then
        [[ -n "$TARGET_FILE" ]] && break
        continue
      fi
      if (( selection_rc == 2 )); then
        info_echo '已取消拆分，未写入分卷。'
        return 0
      fi
      (( selection_rc == 0 )) || return 1
      run_selected_files
      return $?
    done
  done
}
# 编排自述、只读检查、路径输入和分卷执行。
main() {
  show_script_intro_and_wait || return $? # 首先显示用途与影响范围，回车确认后继续。
  initialize_runtime # 确认后初始化日志、脚本定位和运行选项。
  check_environment # 验证系统工具及 fzf，缺失时安全停止。
  require_target_directory "$@" # 持续校验手动输入或拖入的单文件 / 目录。
  plan_and_split # 先完成可返回的选择，再拆分并校验已选文件。
}

main "$@"
