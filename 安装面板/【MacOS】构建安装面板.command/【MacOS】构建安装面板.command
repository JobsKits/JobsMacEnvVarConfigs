#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】构建安装面板.command
# - 核心用途：编译并打包当前仓库的原生安装／卸载管理面板。
# - 影响范围：仅生成本仓同名 App 与临时构建文件，不安装或卸载任何环境组件。
# - 运行提示：终端先展示自述再确认；自动化须显式 --yes；支持 --native 与 --output。
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


ENTRY_FILE="${0:A}"
PANEL_ROOT=""
PROJECT_ROOT=""
PROFILE=""
OUTPUT_APP=""
STAGE_DIR=""
LOG_FILE=""
BUILD_LOCK=""
APP_NAME=""
BUNDLE_ID=""
APPROVED=0
NATIVE_ONLY=0

show_intro_and_confirm() {
    local answer="" argument=""
    for argument in "$@"; do
        [[ "$argument" != --yes ]] || APPROVED=1
    done
    printf '%s\n' '构建安装面板' \
        '用途：使用 Xcode 命令行工具编译 AppKit 面板，将当前后端和所需资源打包进 App。' \
        '影响：只生成 App 和本轮构建日志，不执行安装、卸载、sudo 或系统配置修改。' \
        '默认构建 Apple Silicon / Intel 通用版本；--native 只构建当前架构。' \
        '取消：Ctrl+C；非交互构建必须显式 --yes。日志位于系统临时目录。'
    (( APPROVED )) && return 0
    [[ -t 0 && -t 1 ]] || { printf '%s\n' '缺少显式 --yes，已取消。' >&2; return 2; }
    if [[ -n "${TERM:-}" && "${TERM:-}" != dumb && "${NO_COLOR+x}" != x ]]; then
        printf '\033[1;32m仅按回车\033[0m继续构建；\033[1;31m输入任意字符后回车\033[0m取消：'
    else
        printf '%s' '仅按回车继续构建；输入任意字符后回车取消：'
    fi
    IFS= read -r answer || return 130
    [[ -z "$answer" ]] || return 130
}

initialize_build() {
    setopt NO_NOMATCH PIPE_FAIL
    umask 077
    PANEL_ROOT="${ENTRY_FILE:h:h}"
    PROJECT_ROOT="${PANEL_ROOT:h}"
    PROFILE="$(/bin/cat "$PANEL_ROOT/Resources/BuildProfile.txt")" || return 1
    case "$PROFILE" in
        system)
            APP_NAME='【MacOS】🧰新系统配置管理.app'
            BUNDLE_ID='com.jobs.systemsetup.managementpanel'
            ;;
        env)
            APP_NAME='【MacOS】🌍环境配置管理.app'
            BUNDLE_ID='com.jobs.environmentconfig.managementpanel'
            ;;
        *) printf '%s\n' '构建类型无效：Resources/BuildProfile.txt 必须是 system 或 env。' >&2; return 2 ;;
    esac
    while (( $# > 0 )); do
        case "$1" in
            --yes) shift ;;
            --native) NATIVE_ONLY=1; shift ;;
            --output)
                (( $# >= 2 )) && [[ -n "$2" ]] || return 2
                OUTPUT_APP="${2:A}"
                shift 2
                ;;
            *) printf '未知参数：%s\n' "$1" >&2; return 2 ;;
        esac
    done
    [[ -n "$OUTPUT_APP" ]] || OUTPUT_APP="$PROJECT_ROOT/$APP_NAME"
    [[ "$OUTPUT_APP" == *.app && -d "${OUTPUT_APP:h}" && ! -L "${OUTPUT_APP:h}" && ! -L "$OUTPUT_APP" ]] || {
        printf '%s\n' '目标必须是实际目录中的 .app 路径，不能是符号链接。' >&2
        return 2
    }
    if [[ -e "$OUTPUT_APP" ]]; then
        [[ -d "$OUTPUT_APP" && -f "$OUTPUT_APP/Contents/Info.plist" && ! -L "$OUTPUT_APP/Contents" &&
           "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$OUTPUT_APP/Contents/Info.plist" 2>/dev/null)" == "$BUNDLE_ID" ]] || {
            printf '拒绝覆盖非本工具 App：%s\n' "$OUTPUT_APP" >&2
            return 2
        }
    fi
    local process_commands=""
    process_commands="$(/bin/ps -axo command=)" || return 1
    if printf '%s\n' "$process_commands" | /usr/bin/awk -v executable="$OUTPUT_APP/Contents/MacOS/JobsEnvironmentManager" 'index($0, executable) == 1 { found = 1 } END { exit !found }'; then
        printf '%s\n' '该管理面板仍在运行。请等任务结束并完全退出面板后再构建。' >&2
        return 2
    fi
    LOG_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsPanelBuild.XXXXXXXX")" || return 1
    BUILD_LOCK="${OUTPUT_APP:h}/.JobsPanelBuild.${BUNDLE_ID}.lock"
    /bin/mkdir "$BUILD_LOCK" 2>/dev/null || { printf '另一个构建仍在进行，或上次异常退出留下锁：%s\n' "$BUILD_LOCK" >&2; return 2; }
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    print -r -- "$$" > "$BUILD_LOCK/pid" || return 1
    STAGE_DIR="$(/usr/bin/mktemp -d "${OUTPUT_APP:h}/.JobsPanelBuild.XXXXXXXX")" || return 1
}

log_message() {
    printf '%s\n' "$1" | /usr/bin/tee -a "$LOG_FILE"
}

run_logged() {
    "$@" 2>&1 | /usr/bin/tee -a "$LOG_FILE"
    local codes=("${pipestatus[@]}")
    (( codes[1] == 0 && codes[2] == 0 ))
}

cleanup_build() {
    local cleanup_code=0
    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" && ! -L "$STAGE_DIR" &&
          "${STAGE_DIR:t}" == .JobsPanelBuild.* && ! -e "$STAGE_DIR/previous.app" ]]; then
        /bin/rm -r -- "$STAGE_DIR" || cleanup_code=1
    fi
    if [[ -n "$BUILD_LOCK" && -d "$BUILD_LOCK" && ! -L "$BUILD_LOCK" &&
          -f "$BUILD_LOCK/pid" && ! -L "$BUILD_LOCK/pid" && "$(<"$BUILD_LOCK/pid")" == "$$" ]]; then
        /bin/rm -- "$BUILD_LOCK/pid" || cleanup_code=1
        /bin/rmdir -- "$BUILD_LOCK" || cleanup_code=1
    fi
    return "$cleanup_code"
}

# 顶层退出钩子覆盖整个构建，避免函数内 EXIT trap 提前释放事务锁。
TRAPEXIT() {
    local build_code=$?
    if ! cleanup_build; then
        print -u2 -r -- "构建临时文件未能完整回收，请核对日志与暂存位置：$STAGE_DIR"
        (( build_code != 0 )) || build_code=1
    fi
    return "$build_code"
}

check_build_tools() {
    /usr/bin/xcrun --find swiftc >/dev/null 2>&1 || { log_message '错误：缺少 Swift 编译器，请先准备 Xcode 命令行工具。'; return 1; }
    [[ -r "$PANEL_ROOT/Sources/EnvironmentManager.swift" && -r "$PANEL_ROOT/Resources/PanelTranslations.json" && -r "$PROJECT_ROOT/icon.png" ]] || {
        log_message '错误：面板源码、翻译或仓库本地图标缺失。'
        return 1
    }
}

copy_tree() {
    local source_dir="$1" target_dir="$2"
    [[ -d "$source_dir" && ! -L "$source_dir" ]] || { log_message "错误：配套目录缺失或为链接：$source_dir"; return 1; }
    /bin/mkdir -p "$target_dir" || return 1
    /usr/bin/tar -C "$source_dir" --exclude .git --exclude .DS_Store --exclude node_modules \
        --exclude work --exclude build --exclude DerivedData --exclude Tests --exclude tests --exclude '*.app' -cf - . |
        /usr/bin/tar -C "$target_dir" -xf -
    local codes=("${pipestatus[@]}")
    (( codes[1] == 0 && codes[2] == 0 ))
}

copy_environment_payload() {
    local source_root="$1" target_root="$2" item=""
    for item in scripts zsh Sys 【MacOS】环境管理后端.command; do
        copy_tree "$source_root/$item" "$target_root/$item" || return 1
    done
    /bin/cp -p "$source_root/sync_env.txt" "$target_root/sync_env.txt" || return 1
}

stage_resources() {
    local application="$1" package_root="" backend_relative=""
    package_root="$application/Contents/Resources/package"
    /bin/mkdir -p "$application/Contents/MacOS" "$application/Contents/Resources" "$package_root" || return 1
    /bin/cp -p "$PANEL_ROOT/Resources/PanelTranslations.json" "$application/Contents/Resources/PanelTranslations.json" || return 1
    if [[ "$PROFILE" == system ]]; then
        copy_tree "$PROJECT_ROOT/【MacOS】🆕新系统配置.command" "$package_root/【MacOS】🆕新系统配置.command" || return 1
        copy_environment_payload "$PROJECT_ROOT/🌍JobsMacEnvVarConfigs" "$package_root/🌍JobsMacEnvVarConfigs" || return 1
        backend_relative='package/【MacOS】🆕新系统配置.command/【MacOS】环境管理后端.command/【MacOS】环境管理后端.command'
    else
        copy_environment_payload "$PROJECT_ROOT" "$package_root" || return 1
        backend_relative='package/【MacOS】环境管理后端.command/【MacOS】环境管理后端.command'
    fi
    /bin/cat > "$application/Contents/Resources/PanelConfiguration.json" <<PROFILE_JSON
{"kind":"$PROFILE","backend":"$backend_relative","preferenceDomain":"$BUNDLE_ID.preferences"}
PROFILE_JSON
    /bin/cat > "$application/Contents/Info.plist" <<APP_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>JobsEnvironmentManager</string>
<key>CFBundleDisplayName</key><string>${APP_NAME%.app}</string>
<key>CFBundleExecutable</key><string>JobsEnvironmentManager</string>
<key>CFBundleIconFile</key><string>JobsEnvironmentManager.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
APP_PLIST
    /usr/bin/plutil -lint "$application/Contents/Info.plist" || return 1
}

build_icon() {
    local application="$1" size="" scale="" pixels="" iconset="$STAGE_DIR/JobsEnvironmentManager.iconset"
    /bin/mkdir -p "$iconset" || return 1
    for size in 16 32 128 256 512; do
        for scale in 1 2; do
            pixels=$(( size * scale ))
            local suffix=""
            (( scale == 1 )) || suffix='@2x'
            /usr/bin/sips -z "$pixels" "$pixels" "$PROJECT_ROOT/icon.png" --out "$iconset/icon_${size}x${size}${suffix}.png" >/dev/null || return 1
        done
    done
    run_logged /usr/bin/iconutil -c icns "$iconset" -o "$application/Contents/Resources/JobsEnvironmentManager.icns"
}

build_binary() {
    local application="$1" sdk="" native_arch=""
    sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" || return 1
    if (( NATIVE_ONLY )); then
        native_arch="$(/usr/bin/uname -m)"
        run_logged /usr/bin/xcrun swiftc -swift-version 5 -O -sdk "$sdk" -target "${native_arch}-apple-macos13.0" "$PANEL_ROOT/Sources/EnvironmentManager.swift" -o "$application/Contents/MacOS/JobsEnvironmentManager" || return 1
    else
        run_logged /usr/bin/xcrun swiftc -swift-version 5 -O -sdk "$sdk" -target arm64-apple-macos13.0 "$PANEL_ROOT/Sources/EnvironmentManager.swift" -o "$STAGE_DIR/manager-arm64" || return 1
        run_logged /usr/bin/xcrun swiftc -swift-version 5 -O -sdk "$sdk" -target x86_64-apple-macos13.0 "$PANEL_ROOT/Sources/EnvironmentManager.swift" -o "$STAGE_DIR/manager-x86_64" || return 1
        run_logged /usr/bin/lipo -create "$STAGE_DIR/manager-arm64" "$STAGE_DIR/manager-x86_64" -output "$application/Contents/MacOS/JobsEnvironmentManager" || return 1
    fi
    /bin/chmod 755 "$application/Contents/MacOS/JobsEnvironmentManager" || return 1
}

# 记录当前源码和全部包内资源的哈希，便于核对实际交付版本。
write_build_receipt() {
    local application="$1" resource_root="$1/Contents/Resources"
    local source_digest="" built_at="" item="" file_count=0
    source_digest="$(/usr/bin/shasum -a 256 "$PANEL_ROOT/Sources/EnvironmentManager.swift")" || return 1
    source_digest="${source_digest%% *}"
    built_at="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" || return 1
    /bin/cat > "$resource_root/BuildReceipt.plist" <<BUILD_RECEIPT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>profile</key><string>$PROFILE</string>
<key>builtAtUTC</key><string>$built_at</string>
<key>sourceSHA256</key><string>$source_digest</string>
</dict></plist>
BUILD_RECEIPT
    /usr/bin/plutil -lint "$resource_root/BuildReceipt.plist" >> "$LOG_FILE" 2>&1 || return 1
    (
        cd "$resource_root" || exit 1
        local resource_files=(**/*(.DN))
        (( ${#resource_files} > 0 )) || exit 1
        for item in "${resource_files[@]}"; do
            [[ "$item" != Payload.sha256 ]] || continue
            [[ "$item" != *$'\n'* && "$item" != *$'\r'* ]] || exit 1
            /usr/bin/shasum -a 256 "./$item" || exit 1
        done
    ) > "$resource_root/Payload.sha256" || return 1
    (
        cd "$resource_root" || exit 1
        /usr/bin/shasum -a 256 -c Payload.sha256
    ) >> "$LOG_FILE" 2>&1 || return 1
    file_count="$(/usr/bin/wc -l < "$resource_root/Payload.sha256")" || return 1
    log_message "资源清单已验证：${file_count//[[:space:]]/} 份；源码 SHA-256：$source_digest"
}

verify_and_publish() {
    local application="$1"
    write_build_receipt "$application" || return 1
    run_logged /usr/bin/codesign --force --sign - "$application" || return 1
    run_logged /usr/bin/codesign --verify --deep --strict "$application" || return 1
    run_logged "$application/Contents/MacOS/JobsEnvironmentManager" --self-test || return 1
    if [[ -d "$OUTPUT_APP" ]]; then
        /bin/mv "$OUTPUT_APP" "$STAGE_DIR/previous.app" || return 1
    fi
    if ! /bin/mv "$application" "$OUTPUT_APP"; then
        if [[ -d "$STAGE_DIR/previous.app" ]]; then
            /bin/mv "$STAGE_DIR/previous.app" "$OUTPUT_APP" || log_message "错误：原 App 恢复失败，保留于 $STAGE_DIR/previous.app"
        fi
        return 1
    fi
    if [[ -d "$STAGE_DIR/previous.app" ]]; then
        /bin/rm -r -- "$STAGE_DIR/previous.app" || return 1
    fi
    log_message "成功：$OUTPUT_APP"
    log_message "日志：$LOG_FILE"
}

run_build() {
    local application="$STAGE_DIR/$APP_NAME"
    log_message "来源：$PANEL_ROOT/Sources/EnvironmentManager.swift"
    log_message "资源：当前仓库后端、Shell 配置与本地图标 $PROJECT_ROOT/icon.png"
    log_message "目标：$OUTPUT_APP"
    stage_resources "$application" && build_icon "$application" && build_binary "$application" && verify_and_publish "$application"
}

# 保留业务真实失败码，由统一门禁停止后续构建步骤。
run_build_step() {
    local step_code=0
    "$@" || step_code=$?
    (( step_code == 0 )) || exit "$step_code"
}
# 编排自述、事务准备、编译环境检查与产物发布。
main() {
  run_build_step show_intro_and_confirm "$@" # 先展示构建范围并取得本轮确认。
  run_build_step initialize_build "$@" # 按当前入口定位资源并建立全程事务锁。
  run_build_step check_build_tools # 核实构建工具与本仓必需资源。
  run_build_step run_build # 编译、签名、自测后发布完整产物。
}

main "$@"
