#!/bin/zsh
# shell: zsh
# 脚本自述：Jobs 窗口录屏；只采集明确选中的窗口，默认无声音，不覆盖已有文件。
# 首次运行检查 Apple 工具链、按需检查 fzf；缺失依赖自动补齐并复检。
# 同名目录内的 Core 是随包原生源码，不需要上游仓库、SwiftPM 包或浏览器插件。
# 普通运行先确认自述；--yes 明确授权本轮准备，录制前仍显示目标与确认菜单。

# >>> Jobs terminal style protection v1 >>>
# 临时保护当前终端配色，业务进程自行管理原有退出清理。
jobs_terminal_style_run() {
    # 用可中断的 builtin wait 监督直接业务子进程，不向共享进程组发送信号。
    jobs_terminal_style_business() {
        jobs_style_business_pid=''
        jobs_style_business_start=''
        jobs_style_business_cancel=0
        jobs_style_business_result=0
        # TERM/HUP 交给业务层的有界清理，父层等它结束后才还原终端。
        jobs_terminal_style_forward() {
            jobs_style_business_cancel=$2
            jobs_style_observed_start=$(ps -o lstart= -p "$jobs_style_business_pid" 2>/dev/null)
            jobs_style_observed_parent=$(ps -o ppid= -p "$jobs_style_business_pid" 2>/dev/null | tr -d '[:space:]')
            if [ -n "$jobs_style_business_start" ] &&
               [ "$jobs_style_observed_start" = "$jobs_style_business_start" ] &&
               [ "$jobs_style_observed_parent" = "$$" ]; then
                kill -s "$1" "$jobs_style_business_pid" 2>/dev/null || :
            fi
        }
        trap ':' INT
        trap 'jobs_terminal_style_forward HUP 129' HUP
        trap 'jobs_terminal_style_forward TERM 143' TERM
        if [ -t 0 ]; then
            "$@" < /dev/tty &
        else
            "$@" <&0 &
        fi
        jobs_style_business_pid=$!
        jobs_style_business_start=$(ps -o lstart= -p "$jobs_style_business_pid" 2>/dev/null)
        while :; do
            if builtin wait "$jobs_style_business_pid"; then
                jobs_style_business_result=0
            else
                jobs_style_business_result=$?
            fi
            jobs_style_observed_start=$(ps -o lstart= -p "$jobs_style_business_pid" 2>/dev/null)
            if [ -n "$jobs_style_business_start" ] &&
               [ "$jobs_style_observed_start" = "$jobs_style_business_start" ]; then
                continue
            fi
            break
        done
        jobs_style_business_pid=''
        if [ "$jobs_style_business_cancel" -ne 0 ]; then
            return "$jobs_style_business_cancel"
        fi
        return "$jobs_style_business_result"
    }
    # 无法可靠保存原色时，沿用脚本已有的纯文本约定。
    jobs_terminal_style_plain() {
        PLAIN_OUTPUT=1
        NO_COLOR=1
        FORCE_COLOR=0
        CLICOLOR=0
        ANSI_COLORS_DISABLED=1
        npm_config_color=false
        export PLAIN_OUTPUT NO_COLOR FORCE_COLOR CLICOLOR ANSI_COLORS_DISABLED npm_config_color
        # 业务子进程接收同一前台组的 INT，监督层保留其最终退出码。
        trap ':' INT
        if jobs_terminal_style_business "$@"; then
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
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 完整颜色帧有界重发；仅退出恢复容忍帧外回车和明确方向键。
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
                    # 仅退出恢复阶段允许帧外的明确控制键，普通文字仍然失败。
                    if [ "$jobs_style_query_phase" = cleanup ]; then
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
                            jobs_style_cleanup_control_keys=$(( ${jobs_style_cleanup_control_keys:-0} + 1 ))
                            if [ "$jobs_style_cleanup_control_keys" -gt 64 ]; then
                                jobs_style_query_failure='退出恢复期间已识别控制键超过 64 个，已停止自动恢复'
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
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_cleanup_issue='无法读取或设置原终端输入模式，或临时配色未完成核验'
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            jobs_style_cleanup_control_keys=0
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
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key"; then
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
        printf '%s\n' '无法核实本次临时配色，已停止启动业务。' >&2
        jobs_style_exit_status=1
        exit 1
    fi
    jobs_style_applied_complete=1
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
    printf '%s\n' '本次终端已临时使用黑底白字。' >&2
    JOBS_TERMINAL_STYLE_TTY=$jobs_style_tty
    JOBS_TERMINAL_STYLE_OWNER=$$
    export JOBS_TERMINAL_STYLE_TTY JOBS_TERMINAL_STYLE_OWNER
    # 媒体子进程可在 INT 后保存并继续询问，监督层不能改写其结果。
    trap ':' INT
    if jobs_terminal_style_business "$@"; then
        jobs_style_exit_status=0
    else
        jobs_style_exit_status=$?
    fi
    exit "$jobs_style_exit_status"
}
# 仅监督直接执行的入口；被 source 时不切换配色、不重新执行业务。
jobs_terminal_style_bootstrap() {
    for jobs_readonly_arg in "$@"; do
        case "$jobs_readonly_arg" in
            --help|-h|help|--version|--doctor) return 0 ;;
        esac
    done
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

# 自包含 Homebrew 检查及路径选择。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
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
  print -u2 -n -r -- "➤ 安装路径选择："
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
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if run_managed curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    run_managed /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! run_managed curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! run_managed env GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
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

# 保留本仓安装提示接口，不写入 Shell 配置。
jobs_prompt_output() {
    "$@"
}
typeset -g SCRIPT_DIR='' LOG_FILE='' RUN_DIR='' CACHE_ROOT='' ENGINE=''
typeset -g MODE=interactive YES=0 REPAIR=1 ALL_WINDOWS=0 WINDOW_ID='' OUTPUT='' DURATION=''
typeset -g INCLUDE_AUXILIARY=0 MEDIA_STOP_REQUESTED=0 CHILD_RESULT=0
typeset -g FPS_INPUT_PASTE_MODE=0
typeset -g FPS=30 AUDIO=none SHOW_CURSOR=1 FZF_BIN='' SWIFTC='' SDK_PATH='' CHILD_PID='' CHILD_START=''
typeset -g TARGET='' TARGET_LABEL='' NATIVE_INFO='' JOBS_HOMEBREW_BIN=''
typeset -g JOBS_HOMEBREW_INSTALL_MODE='' CHILD_MEDIA=0
typeset -ga OWNED_PIDS=() OWNED_STARTS=()

# 显示最小使用说明；帮助路径不会初始化缓存、安装依赖或申请权限。
show_help() {
    cat <<'HELP'
Jobs 窗口录屏 / jrecord
  无参数                     键盘选择浏览器窗口、配置并确认录制
  --all                      同时列出其它应用有标题窗口，隐藏状态会标注
  --include-auxiliary        显式进入诊断模式，额外包含无标题辅助窗口（含隐藏）
  --window-id ID              按真实窗口 ID 取得身份快照后录制
  --output PATH.mp4          指定新文件，拒绝覆盖；省略时录制前询问目录，默认系统桌面
  --duration SECONDS         自动停止；不指定则 Ctrl+C 停止并保存
  --fps 1..60                默认 30
  --audio none|system        默认 none；system 可能包含同应用其它窗口声音
  --no-cursor                不录鼠标指针
  --list                     列出窗口，不录制
  --doctor                   只体检，不安装、不编译、不申请权限
  --prepare                  自动准备依赖并编译内核，不录制
  --permission               显式申请屏幕录制权限，不录制
  --yes                      明确授权本轮准备；指定 --window-id 时同时授权录制
  --no-repair                 缺失或损坏时报告并停止，不自动修复
  --help / --version         显示帮助 / 版本
依赖：MacOS 15+，支持 MacOS 15 SDK 的 Xcode / Command Line Tools。
交互额外需要 fzf（缺失自动经 Homebrew 安装）；原生录制不依赖 FFmpeg。
录制成功后询问是否打开所在目录，默认不打开；非交互录制必须指定 --output。
开始采集前全屏显示 5→1 双圆心跳倒计时，鼠标点击穿透；Ctrl+C 取消倒计时。
复制整个同名目录即可迁移；不要只复制入口而遗漏 Core。
HELP
}
# 拒绝未知、缺值与不安全数值，所有帮助参数均优先结束。
parse_arguments() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --help|-h|help) show_help; exit 0 ;;
        esac
    done
    for arg in "$@"; do
        [[ "$arg" != --version ]] || { print -r -- 'Jobs 窗口录屏 1.0.0'; exit 0; }
    done
    while (( $# )); do
        case "$1" in
            --doctor|--prepare|--list|--permission)
                [[ "$MODE" == interactive ]] || { print -u2 '模式参数不能重复。'; exit 64; }
                MODE="${1#--}" ;;
            --yes) YES=1 ;;
            --no-repair) REPAIR=0 ;;
            --all) ALL_WINDOWS=1 ;;
            --include-auxiliary) INCLUDE_AUXILIARY=1 ;;
            --no-cursor) SHOW_CURSOR=0 ;;
            --window-id|--output|--duration|--fps|--audio)
                (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || { print -u2 -r -- "参数 $1 缺少值。"; exit 64; }
                case "$1" in
                    --window-id) WINDOW_ID="$2" ;;
                    --output) OUTPUT="$2" ;;
                    --duration) DURATION="$2" ;;
                    --fps) FPS="$2" ;;
                    --audio) AUDIO="$2" ;;
                esac
                shift ;;
            *) print -u2 -r -- "未知参数：$1（使用 --help）。"; exit 64 ;;
        esac
        shift
    done
    [[ -z "$WINDOW_ID" || ( "$WINDOW_ID" == <-> && ${#WINDOW_ID} -le 10 ) ]] || { print -u2 '窗口 ID 必须为有效正整数。'; exit 64; }
    if [[ -n "$WINDOW_ID" ]] && ! (( WINDOW_ID > 0 && WINDOW_ID <= 4294967295 )); then
        print -u2 '窗口 ID 超出系统 UInt32 正整数范围。'
        exit 64
    fi
    [[ "$FPS" == <-> && ${#FPS} -le 2 ]] && (( FPS >= 1 && FPS <= 60 )) || { print -u2 '帧率须为 1 到 60。'; exit 64; }
    [[ "$AUDIO" == none || "$AUDIO" == system ]] || { print -u2 '声音模式须为 none 或 system。'; exit 64; }
    if [[ -n "$DURATION" ]]; then
        [[ "$DURATION" =~ '^[0-9]{1,5}(\.[0-9]{1,3})?$' ]] && (( DURATION > 0 && DURATION <= 86400 )) || { print -u2 '时长须为大于 0、最多 86400 秒的有限数值。'; exit 64; }
    fi
    [[ -z "$WINDOW_ID" || "$MODE" == interactive ]] || { print -u2 '窗口录制参数不能与只读或准备模式混用。'; exit 64; }
    [[ -z "$OUTPUT" || "$OUTPUT" == *.mp4 ]] || { print -u2 '输出文件必须使用 .mp4 后缀。'; exit 64; }
}
# 先展示用途及影响，只有明确模式或确认后才准备环境。
show_script_intro_and_wait() {
    parse_arguments "$@"
    if [[ "$MODE" == doctor ]]; then
        print -r -- 'Jobs 窗口录屏：只读体检；不修复、不录制、不申请权限。'
        return 0
    fi
    if [[ "$MODE" == interactive && -z "$OUTPUT" ]] && [[ ! -t 0 || ! -t 1 ]]; then
        print -u2 '非交互录制必须显式指定 --output PATH.mp4；交互录制会先询问保存目录，默认系统桌面。'
        exit 64
    fi
    print_styled '1;31' 'Jobs 窗口录屏'
    print_styled '0;34' '1、只录明确选定的窗口；默认静音；已有文件不覆盖。'
    print_styled '0;34' '2、检查原生编译器 / SDK，按需补齐依赖并编译 Core 到用户缓存。'
    print_styled '0;34' '3、交互使用 fzf；缺失时检查 Homebrew 后安装，不升级整个环境或修改 Shell 配置。'
    print_styled '0;34' '4、屏幕录制授权由系统处理；Ctrl+C 结束并保存，关闭终端同样尝试封尾。'
    print_styled '0;34' '5、日志在系统临时目录内独立 jobs-window-record 会话；不记录窗口标题或身份 token。'
    print_styled '0;34' '6、未传 --output 时先询问保存目录，默认系统桌面；成功保存后可选择打开所在目录，默认不打开。'
    print_styled '0;34' '7、开始采集前显示 5→1 双圆心跳倒计时，不拦截鼠标；倒计时中 Ctrl+C 取消录制。'
    (( YES )) && return 0
    [[ -t 0 && -t 1 ]] || { print -u2 '请在终端运行；自动化须显式传 --yes。'; exit 64; }
    if [[ "${JOBS_RECORD_PARENT_MENU:-${JOBS_LIST_PARENT_MENU:-}}" == list ]]; then
        print -r -- '已了解用途与影响；← 返回功能菜单，Ctrl+C 取消。'
    else
        print -r -- '已了解用途与影响；Ctrl+C 取消。'
    fi
    print_styled '1;32' '按回车继续：'
    wait_for_intro_confirmation
}
# 自述确认只接受回车；来自 list 时立即识别真实左方向键并返回父菜单。
wait_for_intro_confirmation() {
    local key='' prefix='' direction=''
    while true; do
        IFS= read -r -s -k1 key || exit 130
        case "$key" in
            $'\r'|$'\n') print; return 0 ;;
            $'\004') exit 130 ;;
            $'\e')
                prefix=''
                direction=''
                IFS= read -r -s -k1 -t 0.15 prefix || continue
                [[ "$prefix" == '[' || "$prefix" == O ]] || continue
                IFS= read -r -s -k1 -t 0.15 direction || continue
                if [[ "$direction" == D && "${JOBS_RECORD_PARENT_MENU:-${JOBS_LIST_PARENT_MENU:-}}" == list ]]; then
                    print
                    print -r -- '已返回功能菜单。'
                    exit 20
                fi ;;
        esac
    done
}
# 仅对可靠的交互终端着色，重定向和配色降级时保持纯文本。
print_styled() {
    local color="$1" message="$2"
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" && "${PLAIN_OUTPUT:-0}" != 1 ]]; then
        printf '\033[%sm%s\033[0m\n' "$color" "$message"
    else
        print -r -- "$message"
    fi
}
# 追加纯文本日志，颜色只向交互终端显示。
log_note() {
    local message="$*"
    print -r -- "$message" >&2
    [[ -z "$LOG_FILE" ]] || print -r -- "$message" >> "$LOG_FILE"
}
# 保留步骤实时进度和退出码，同时跟踪本次子进程供信号清理。
run_managed() {
    local command_rc=0 terminal_path=''
    MEDIA_STOP_REQUESTED=0
    CHILD_RESULT=0
    CHILD_MEDIA=0
    [[ "$1" != "$ENGINE" || "${2:-}" != record ]] || CHILD_MEDIA=1
    if [[ -t 0 ]]; then
        terminal_path="$(/usr/bin/tty)"
        JOBS_RECORD_TTY="$terminal_path" "$@" < /dev/tty > >(tee -a "$LOG_FILE") 2>&1 &
    else
        "$@" > >(tee -a "$LOG_FILE") 2>&1 &
    fi
    CHILD_PID=$!
    CHILD_START="$(/bin/ps -o lstart= -p "$CHILD_PID" 2>/dev/null)"
    wait "$CHILD_PID" || command_rc=$?
    (( ! MEDIA_STOP_REQUESTED )) || command_rc="$CHILD_RESULT"
    CHILD_RESULT="$command_rc"
    CHILD_PID=''
    CHILD_START=''
    CHILD_MEDIA=0
    return "$command_rc"
}
# 取得小体积更新目录并保存本次结果，避免把旧错误误作本轮网络状态。
run_captured() {
    local capture_file="$1" command_rc=0
    shift
    CHILD_MEDIA=0
    "$@" > "$capture_file" 2>&1 &
    CHILD_PID=$!
    wait "$CHILD_PID" || command_rc=$?
    CHILD_PID=''
    cat "$capture_file" | tee -a "$LOG_FILE"
    return "$command_rc"
}
# 只对可恢复的 SDK 获取网络故障持续重试；本地权限、磁盘和许可问题立即报告。
sdk_network_failure() {
    local detail="$1"
    print -r -- "$detail" | LC_ALL=C /usr/bin/grep -Eiq 'network|timed? ?out|connection|connect to|not connected|unavailable|NSURLErrorDomain|download.*fail|网络|超时|连接'
}
# 本地阻塞不能伪装成网络重试或自动接受许可证。
sdk_local_failure() {
    local detail="$1"
    print -r -- "$detail" | LC_ALL=C /usr/bin/grep -Eiq 'permission|not permitted|not authorized|authentication|administrator|license|licence|disk.*full|no space|权限|授权|许可证|磁盘.*不足'
}
# 先暂停本次子进程树再取后代，避免退出清理时安装器继续派生新进程。
freeze_owned_tree() {
    local pid="$1" parent="$2" observed child stamp
    observed="$(/bin/ps -o ppid= -p "$pid" 2>/dev/null)"
    [[ "${observed//[[:space:]]/}" == "$parent" ]] || return 0
    kill -STOP "$pid" 2>/dev/null || return 0
    stamp="$(/bin/ps -o lstart= -p "$pid" 2>/dev/null)"
    [[ -n "$stamp" ]] || { kill -CONT "$pid" 2>/dev/null; return 0; }
    OWNED_PIDS+=("$pid")
    OWNED_STARTS+=("$stamp")
    local children="$(/bin/ps -axo pid=,ppid= | /usr/bin/awk -v parent="$pid" '$2 == parent { print $1 }')"
    for child in ${(f)children}; do
        [[ "$child" == <-> ]] && freeze_owned_tree "$child" "$pid"
    done
}
# 每次发信号前复核启动身份，不向共享进程组或无关复用 PID 发信号。
owned_process_alive() {
    local index="$1" stamp
    stamp="$(/bin/ps -o lstart= -p "${OWNED_PIDS[$index]}" 2>/dev/null)"
    [[ -n "$stamp" && "$stamp" == "${OWNED_STARTS[$index]}" ]]
}
# 结束本次子进程树并有限等待，让原生内核有机会完成媒体封尾。
stop_owned_child() {
    local signal="${1:-TERM}" attempt index alive grace=10 child_rc=0
    [[ -n "$CHILD_PID" ]] || return 0
    if (( CHILD_MEDIA )); then
        local media_pid="$CHILD_PID" observed_start='' observed_parent='' process_state=''
        observed_start="$(/bin/ps -o lstart= -p "$media_pid" 2>/dev/null)"
        observed_parent="$(/bin/ps -o ppid= -p "$media_pid" 2>/dev/null)"
        if [[ -n "$CHILD_START" && "$observed_start" == "$CHILD_START" && "${observed_parent//[[:space:]]/}" == "$$" ]]; then
            # tee 必须继续消费输出；只通知原生顶级进程，不能先杀日志管道。
            kill -s "$signal" "$media_pid" 2>/dev/null || true
            for attempt in {1..95}; do
                observed_start="$(/bin/ps -o lstart= -p "$media_pid" 2>/dev/null)"
                [[ "$observed_start" == "$CHILD_START" ]] || break
                process_state="$(/bin/ps -o stat= -p "$media_pid" 2>/dev/null)"
                [[ "$process_state" != *Z* ]] || break
                sleep 1
            done
            observed_start="$(/bin/ps -o lstart= -p "$media_pid" 2>/dev/null)"
            if [[ "$observed_start" == "$CHILD_START" && "$process_state" != *Z* ]]; then
                log_note '✖ 原生录屏未在期限内完成封尾；只中断该进程并保留暂存文件。'
                kill -KILL "$media_pid" 2>/dev/null || true
            fi
        fi
        wait "$media_pid" 2>/dev/null || child_rc=$?
        CHILD_RESULT="$child_rc"
        CHILD_PID=''
        CHILD_START=''
        return 0
    elif [[ "$signal" == INT ]]; then
        signal=TERM
    fi
    OWNED_PIDS=()
    OWNED_STARTS=()
    freeze_owned_tree "$CHILD_PID" "$$"
    for (( index=${#OWNED_PIDS}; index>=1; index-- )); do
        owned_process_alive "$index" || continue
        kill -s "$signal" "${OWNED_PIDS[$index]}" 2>/dev/null || true
        kill -CONT "${OWNED_PIDS[$index]}" 2>/dev/null || true
    done
    # 内核最坏包含窗口枚举、stop、封尾和媒体校验；宽限大于这些总预算。
    for (( attempt=1; attempt<=grace; attempt++ )); do
        alive=0
        for (( index=1; index<=${#OWNED_PIDS}; index++ )); do
            owned_process_alive "$index" && alive=1
        done
        (( alive )) || break
        sleep 1
    done
    for (( index=${#OWNED_PIDS}; index>=1; index-- )); do
        owned_process_alive "$index" || continue
        log_note '✖ 子进程未在期限内完成清理；中断它并保留暂存文件供恢复。'
        kill -KILL "${OWNED_PIDS[$index]}" 2>/dev/null || true
    done
    wait "$CHILD_PID" 2>/dev/null || child_rc=$?
    CHILD_RESULT="$child_rc"
    CHILD_PID=''
}
# 媒体 Ctrl+C 是结束并保存；其它阶段或退出信号仍取消整个入口。
handle_signal() {
    local signal="$1" code="$2"
    trap '' INT TERM HUP
    if [[ "$signal" == INT && -n "$CHILD_PID" ]] && (( CHILD_MEDIA )); then
        MEDIA_STOP_REQUESTED=1
        stop_owned_child INT
        trap 'handle_signal INT 130' INT
        trap 'handle_signal TERM 143' TERM
        trap 'handle_signal HUP 129' HUP
        return 0
    fi
    stop_owned_child "$signal"
    exit "$code"
}
# 退出时回收本次子进程树，日志和故障产物保留。
cleanup_runtime() {
    restore_frame_rate_input_mode
    stop_owned_child TERM
}
# 在确认之后解析可迁移路径、建立私有日志并接入清理。
initialize_runtime() {
    setopt NO_NOMATCH PIPE_FAIL
    umask 077
    SCRIPT_DIR="${${(%):-%x}:A:h}"
    [[ -d "$SCRIPT_DIR/Core" ]] || { print -u2 '缺少同级 Core 原生源码，请复制完整的窗口录屏目录。'; exit 1; }
    if [[ "$MODE" == doctor ]]; then
        return 0
    fi
    RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jobs-window-record.XXXXXX")" || exit 1
    LOG_FILE="$RUN_DIR/record.log"
    : > "$LOG_FILE"
    trap cleanup_runtime EXIT
    trap 'handle_signal INT 130' INT
    trap 'handle_signal TERM 143' TERM
    trap 'handle_signal HUP 129' HUP
    log_note "ℹ 日志：$LOG_FILE"
}
# 验证 Apple 工具链真实可执行及 SDK 可读取；不修改全局 developer 路径。
apple_toolchain_healthy() {
    /usr/bin/xcode-select -p >/dev/null 2>&1 || return 1
    SWIFTC="$(/usr/bin/xcrun --find swiftc 2>/dev/null)" || return 1
    SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null)" || return 1
    [[ -x "$SWIFTC" && -d "$SDK_PATH" ]] || return 1
    "$SWIFTC" --version >/dev/null 2>&1 || return 1
    local sdk_version
    sdk_version="$(/usr/bin/plutil -extract Version raw -o - "$SDK_PATH/SDKSettings.plist" 2>/dev/null)" || return 1
    [[ "${sdk_version%%.*}" == <-> ]] && (( ${sdk_version%%.*} >= 15 ))
}
# 自动触发官方工具链安装；异步安装期间持续复检，不重复弹安装窗口。
repair_apple_toolchain() {
    log_note '━━━━━━━━━━ 来源｜Apple 工具链 ━━━━━━━━━━'
    log_note '来源：Apple Software Update / https://developer.apple.com/xcode/resources/'
    log_note '用途：编译随包窗口采集内核；系统权限和许可证须在官方界面处理。'
    if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
        /usr/bin/xcode-select --install 2>&1 | tee -a "$LOG_FILE" || return 1
        log_note 'ℹ 官方安装器已接管下载；完成后自动续行，Ctrl+C 可取消等待。'
        until apple_toolchain_healthy; do
            sleep 5
        done
        return 0
    fi
    local updates label update_rc attempt=0 delay=2 capture_file="$RUN_DIR/apple-updates.txt"
    while true; do
        log_note 'ℹ 正在取得 Apple 官方工具链更新目录；网络失败将持续重试，Ctrl+C 可取消。'
        run_captured "$capture_file" env LC_ALL=C /usr/sbin/softwareupdate --list
        update_rc=$?
        updates="$(cat "$capture_file")"
        if sdk_local_failure "$updates"; then
            log_note '✖ Apple 更新目录被权限、许可或磁盘条件阻塞；未继续。'
            return 1
        fi
        if (( update_rc == 0 )) && ! sdk_network_failure "$updates"; then break; fi
        sdk_network_failure "$updates" || { log_note "✖ Apple 更新目录查询失败（$update_rc），错误不属于可重试网络故障。"; return 1; }
        attempt=$(( attempt + 1 ))
        log_note "⚠ SDK 更新目录获取失败，第 $attempt 次；${delay} 秒后重试，Ctrl+C 可取消。"
        sleep "$delay"
        delay=$(( delay < 30 ? delay * 2 : 30 ))
        (( delay <= 30 )) || delay=30
    done
    label="$(print -r -- "$updates" | /usr/bin/awk '/Label: Command Line Tools for Xcode/ { sub(/^.*Label: /, ""); value=$0 } END { print value }')"
    [[ -n "$label" ]] || { log_note '✖ 未发现可自动补齐的 MacOS 15+ SDK。请在 Xcode 设置安装对应组件或修复 developer 路径后重试。'; return 1; }
    log_note "ℹ Apple 官方组件：$label"
    attempt=0
    delay=2
    local start_line install_detail
    while true; do
        start_line=$(( $(wc -l < "$LOG_FILE") + 1 ))
        run_managed env LC_ALL=C /usr/sbin/softwareupdate --install "$label" --verbose
        update_rc=$?
        apple_toolchain_healthy && return 0
        install_detail="$(/usr/bin/tail -n +"$start_line" "$LOG_FILE")"
        sdk_local_failure "$install_detail" && { log_note '✖ Apple SDK 安装受权限、许可或磁盘条件阻塞；停止。'; return 1; }
        sdk_network_failure "$install_detail" || { log_note "✖ Apple SDK 安装后复检失败（$update_rc），保留已下载内容并停止。"; return 1; }
        attempt=$(( attempt + 1 ))
        log_note "⚠ SDK 获取第 $attempt 次失败，${delay} 秒后继续；不重复已完成业务，Ctrl+C 可取消。"
        sleep "$delay"
        delay=$(( delay < 30 ? delay * 2 : 30 ))
        (( delay <= 30 )) || delay=30
    done
}
# 检查 fzf 的版本及实际需要的选项，避免只检查命令路径。
fzf_healthy() {
    local candidate
    for candidate in "$(command -v fzf 2>/dev/null)" "${JOBS_HOMEBREW_BIN:h}/fzf" /opt/homebrew/bin/fzf /usr/local/bin/fzf "$HOME/.local/homebrew/bin/fzf"; do
        [[ -x "$candidate" ]] || continue
        "$candidate" --version >/dev/null 2>&1 || continue
        print -r -- $'probe\tok' | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' "$candidate" --filter ok --no-multi --info=hidden --delimiter=$'\t' --with-nth=2.. \
            --bind='up:up,down:down,tab:down,shift-tab:up,left:abort' >/dev/null 2>&1 || continue
        FZF_BIN="$candidate"
        return 0
    done
    return 1
}
# Homebrew 只在 fzf 真正缺失时参与；安装后的 PATH 仅对本进程生效。
ensure_fzf() {
    fzf_healthy && return 0
    (( REPAIR )) || { log_note '✖ fzf 缺失或损坏，--no-repair 阻止修复。'; return 1; }
    if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
        jobs_brew_choose_installation || return 1
        log_note '来源：Homebrew 官方 https://github.com/Homebrew/brew / https://github.com/Homebrew/install'
        case "$JOBS_HOMEBREW_INSTALL_MODE" in
            system) jobs_brew_install_system || return 1 ;;
            user) jobs_brew_install_user || return 1 ;;
            *) return 1 ;;
        esac
    fi
    local brew_prefix
    brew_prefix="$("$JOBS_HOMEBREW_BIN" --prefix)" || return 1
    export PATH="$brew_prefix/bin:$brew_prefix/sbin:$PATH"
    rehash
    HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || return 1
    log_note '━━━━━━━━━━ 来源｜fzf ━━━━━━━━━━'
    log_note '来源：https://formulae.brew.sh/formula/fzf'
    log_note "工具：$JOBS_HOMEBREW_BIN；目标：$brew_prefix"
    if HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" list --versions fzf >/dev/null 2>&1; then
        run_managed env HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" reinstall fzf || return 1
    else
        run_managed env HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" install fzf || return 1
    fi
    rehash
    fzf_healthy || { log_note '✖ fzf 安装后复检失败；停止，不进入录制。'; return 1; }
}
# 只体检报告所有层级；缺失不会悄悄进入安装或录制。
report_health() {
    local failed=0 os_version
    os_version="$(/usr/bin/sw_vers -productVersion)"
    print -r -- "MacOS：$os_version / $(/usr/bin/uname -m)"
    if (( ${os_version%%.*} >= 15 )); then print '✔ 系统版本满足'; else print '✖ 需要 MacOS 15+'; failed=1; fi
    if apple_toolchain_healthy; then print -rl -- "✔ Swift：$SWIFTC" "✔ SDK：$SDK_PATH"; else print '✖ Swift / MacOS 15+ SDK 未就绪'; failed=1; fi
    if fzf_healthy; then print -r -- "✔ fzf：$FZF_BIN"; else print '✖ 交互所需 fzf 未就绪；指定窗口 ID 的路径不依赖它'; failed=1; fi
    print 'ℹ 录屏权限由原生内核运行时检查；本模式不编译、不弹授权、不采集。'
    print 'ℹ 如需准备，使用 --prepare；系统权限或许可证无法由脚本绕过。'
    return "$failed"
}
# 先复用健康依赖，只修复本次业务真正需要的缺失层。
check_environment() {
    if [[ "$MODE" == doctor ]]; then report_health; exit $?; fi
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || { log_note '✖ 本工具仅支持 MacOS。'; exit 1; }
    local os_version="$(/usr/bin/sw_vers -productVersion)"
    (( ${os_version%%.*} >= 15 )) || { log_note '✖ 需要 MacOS 15+；不会自动升级操作系统。'; exit 1; }
    if ! apple_toolchain_healthy; then
        (( REPAIR )) && repair_apple_toolchain && apple_toolchain_healthy || { log_note '✖ Apple 工具链复检未通过，停止。'; exit 1; }
    fi
    if [[ "$MODE" == prepare || ( "$MODE" == interactive && ( -z "$WINDOW_ID" || ( -t 0 && -t 1 ) ) ) ]]; then
        ensure_fzf || exit 1
    fi
}
# 原生源码、编译器和 SDK 共同决定缓存身份，损坏缓存保留后重建。
prepare_engine() {
    local -a sources
    sources=( "$SCRIPT_DIR"/Core/**/*.swift(N.) )
    (( ${#sources} )) || { log_note '✖ Core 中没有 Swift 源码。'; exit 1; }
    CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/Library/Caches}/JobsWindowRecorder"
    [[ "$CACHE_ROOT" == /* && ! -L "$CACHE_ROOT" ]] || { log_note '✖ 缓存目录必须是普通绝对目录。'; exit 1; }
    mkdir -p "$CACHE_ROOT" || exit 1
    [[ -O "$CACHE_ROOT" ]] || { log_note '✖ 缓存目录不属于当前用户。'; exit 1; }
    local digest candidate stage
    digest="$( { /usr/bin/shasum -a 256 "${sources[@]}"; "$SWIFTC" --version 2>&1; print -r -- "$SDK_PATH $(/usr/bin/uname -m)"; } | /usr/bin/shasum -a 256)"
    digest="${digest%% *}"
    for candidate in "$CACHE_ROOT"/"$digest".*/JobsWindowRecorder(N.); do
        [[ -f "${candidate:h}/.ready" && -O "${candidate:h}" && ! -L "${candidate:h}" ]] || continue
        [[ "$("$candidate" --version 2>/dev/null)" == 'JobsWindowRecorder 1.0.0' ]] || continue
        "$candidate" --self-test >/dev/null 2>&1 || continue
        ENGINE="$candidate"
        return 0
    done
    # 各调用独占构建目录，完成标记后才供复用；无需接管其它调用的锁或缓存。
    stage="$(mktemp -d "$CACHE_ROOT/$digest.XXXXXX")" || exit 1
    log_note 'ℹ 正在从随包 Core 编译原生内核（无第三方 Swift 包）。'
    run_managed "$SWIFTC" -swift-version 5 -O -parse-as-library -sdk "$SDK_PATH" -target "$(/usr/bin/uname -m)-apple-macos15.0" "${sources[@]}" -o "$stage/JobsWindowRecorder" \
        -framework AppKit -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia -framework CoreVideo || { log_note "✖ 编译失败，现场保留：$stage"; exit 1; }
    "$stage/JobsWindowRecorder" --self-test || { log_note "✖ 原生内核自检失败：$stage"; exit 1; }
    print -r -- "$digest" > "$stage/.ready" || exit 1
    ENGINE="$stage/JobsWindowRecorder"
    log_note '✔ 原生内核已就绪。'
}
# 系统授权只能显式申请；拒绝后停止，不偷偷转用屏幕区域捕获。
ensure_recording_permission() {
    NATIVE_INFO="$("$ENGINE" doctor)" || return 1
    if [[ "$(print -r -- "$NATIVE_INFO" | /usr/bin/plutil -extract screenRecordingAuthorized raw -o - - 2>/dev/null)" == true ]]; then return 0; fi
    if [[ ! -t 0 ]]; then
        log_note '✖ 缺少屏幕录制授权；在交互终端运行 --permission 后重试。'
        return 77
    fi
    log_note 'ℹ 即将请求当前终端的屏幕录制权限；请在系统设置完成授权。'
    "$ENGINE" request-permission || return 77
}
# 从独立快照选择窗口，动作行和实际 token 分开处理。
choose_window() {
    local listing result rc line scope_label mode_label menu_header window_count parent_label
    local -a args rows window_rows
    while true; do
        args=(list)
        (( ALL_WINDOWS )) || args+=(--browsers)
        (( ! INCLUDE_AUXILIARY )) || args+=(--include-auxiliary)
        listing="$("$ENGINE" "${args[@]}")" || return $?
        window_rows=()
        [[ -z "$listing" ]] || window_rows=("${(@f)listing}")
        window_count=${#window_rows}
        parent_label='终端'
        [[ "${JOBS_RECORD_PARENT_MENU:-}" != list ]] || parent_label='功能菜单'
        rows=("@back"$'\t'"返回$parent_label" $'@cancel\t取消本轮' $'@refresh\t重新加载窗口' $'@scope\t切换浏览器 / 全部应用')
        rows+=("${window_rows[@]}")
        scope_label='浏览器'
        (( ! ALL_WINDOWS )) || scope_label='全部应用'
        mode_label='普通窗口'
        if (( INCLUDE_AUXILIARY )); then
            mode_label='诊断窗口（含辅助）'
        fi
        menu_header="范围：$scope_label | $mode_label：$window_count 个"
        if (( window_count == 0 )); then
            menu_header+=$'\n当前没有可录窗口；打开窗口后选择“重新加载窗口”，也可切换范围或取消。'
        fi
        menu_header+=$'\n'"↑/↓ 或 Tab 选择，回车确认；← 返回$parent_label；Esc 取消本轮"
        result="$(printf '%s\n' "${rows[@]}" | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' "$FZF_BIN" --no-multi \
            --delimiter=$'\t' --with-nth=2.. --expect=left --height=80% --info=hidden \
            --bind='up:up,down:down,tab:down,shift-tab:up' --header="$menu_header" --prompt='选择录制窗口 > ')"
        rc=$?
        [[ "$result" != left && "$result" != left$'\n'* ]] || return 20
        (( rc == 0 )) || { (( rc == 1 || rc == 130 )) && return 130; return "$rc"; }
        line="${${(@f)result}[-1]}"
        case "${line%%$'\t'*}" in
            @back) return 20 ;;
            @cancel|'') return 130 ;;
            @refresh) continue ;;
            @scope) ALL_WINDOWS=$(( 1 - ALL_WINDOWS )); continue ;;
            *)
                # fzf 返回值必须原样存在于本次快照，拒绝注入或过期的菜单输出。
                (( ${rows[(Ie)$line]} )) || return 1
                TARGET="${line%%$'\t'*}"
                TARGET_LABEL="${line#*$'\t'}"
                return 0 ;;
        esac
    done
}
# 消费完整终端转义序列，控制码中的数字不能进入帧率缓冲。
read_frame_rate_escape() {
    local first='' key='' sequence='' previous='' index
    REPLY=cancel
    if ! IFS= read -r -s -k 1 -t 0.05 first < /dev/tty; then
        return 0
    fi
    case "$first" in
        '['|'O')
            sequence="$first"
            for index in {1..32}; do
                IFS= read -r -s -k 1 -t 0.05 key < /dev/tty || return 1
                sequence+="$key"
                if [[ "$key" == [@-~] ]]; then
                    case "$sequence" in
                        '[D'|'OD') REPLY=back ;;
                        '[200~') REPLY=paste-start ;;
                        '[201~') REPLY=paste-end ;;
                        *) REPLY=ignore ;;
                    esac
                    return 0
                fi
            done
            return 1 ;;
        ']')
            for index in {1..2048}; do
                IFS= read -r -s -k 1 -t 0.05 key < /dev/tty || return 1
                if [[ "$key" == $'\a' || ( "$previous" == $'\e' && "$key" == $'\x5c' ) ]]; then
                    REPLY=ignore
                    return 0
                fi
                previous="$key"
            done
            return 1 ;;
        *) return 1 ;;
    esac
}
# 可重复恢复手动输入的临时粘贴模式，信号退出也由现有 EXIT 清理调用。
restore_frame_rate_input_mode() {
    if (( FPS_INPUT_PASTE_MODE )); then
        printf '\033[?2004l' > /dev/tty 2>/dev/null || true
        FPS_INPUT_PASTE_MODE=0
    fi
}
# 逐键构建纯数字缓冲，整段无效粘贴拒绝；有效回车前不修改当前 FPS。
read_numeric_frame_rate() {
    [[ -t 0 && -t 1 ]] || { log_note '✖ 自定义帧率需要可交互终端。'; return 64; }
    local digits='' key='' action='' paste_digits='' paste_active=0 paste_invalid=0 overflow=0 paste_overflow=0
    print -r -- "当前帧率：$FPS FPS；合法范围 1..60；仅接收数字，退格修改，← 返回帧率菜单，Esc / Ctrl+C 取消本轮。"
    print -n -r -- '自定义帧率 > '
    FPS_INPUT_PASTE_MODE=1
    if ! printf '\033[?2004h' > /dev/tty; then
        restore_frame_rate_input_mode
        log_note '✖ 无法准备终端数字输入，未修改当前帧率。'
        return 1
    fi
    {
        while true; do
            IFS= read -r -s -k 1 key < /dev/tty || return 130
            if [[ "$key" == $'\e' ]]; then
                read_frame_rate_escape || return 130
                action="$REPLY"
                case "$action" in
                    paste-start)
                        (( ! paste_active )) || return 130
                        paste_active=1
                        paste_invalid=0
                        paste_overflow=0
                        paste_digits=''
                        continue ;;
                    paste-end)
                        if (( paste_active )); then
                            paste_active=0
                            if (( paste_invalid || paste_overflow )); then
                                digits=''
                                overflow=0
                                print -r -- ''
                                print_styled '1;33' '粘贴内容含非数字或过长，已拒绝整段；请重新输入 1..60 的数字帧率。'
                                print -n -r -- '自定义帧率 > '
                            else
                                for key in ${(s::)paste_digits}; do
                                    if (( ${#digits} < 32 )); then
                                        digits+="$key"
                                        print -n -r -- "$key"
                                    else
                                        overflow=$(( overflow + 1 ))
                                    fi
                                done
                            fi
                            paste_digits=''
                        fi
                        continue ;;
                    back)
                        (( ! paste_active )) || { paste_invalid=1; continue; }
                        return 20 ;;
                    cancel) return 130 ;;
                    ignore)
                        (( ! paste_active )) || paste_invalid=1
                        continue ;;
                esac
            fi
            if (( paste_active )); then
                case "$key" in
                    [0-9])
                        if (( ${#paste_digits} < 32 )); then
                            paste_digits+="$key"
                        else
                            paste_overflow=1
                        fi ;;
                    $'\r'|$'\n') ;;
                    *) paste_invalid=1 ;;
                esac
                continue
            fi
            case "$key" in
                [0-9])
                    if (( ${#digits} < 32 )); then
                        digits+="$key"
                        print -n -r -- "$key"
                    else
                        overflow=$(( overflow + 1 ))
                    fi ;;
                $'\x7f'|$'\b')
                    if (( overflow )); then
                        overflow=$(( overflow - 1 ))
                    elif [[ -n "$digits" ]]; then
                        digits="${digits[1,-2]}"
                        printf '\b \b' > /dev/tty
                    fi ;;
                $'\r'|$'\n')
                    if (( ! overflow && ${#digits} >= 1 && ${#digits} <= 2 )) && (( 10#$digits >= 1 && 10#$digits <= 60 )); then
                        FPS=$(( 10#$digits ))
                        return 0
                    fi
                    digits=''
                    overflow=0
                    print -r -- ''
                    print_styled '1;33' '请输入 1..60 的整数帧率；空值、0 或超出范围均不会生效。'
                    print -n -r -- '自定义帧率 > ' ;;
                $'\x03'|$'\x04') return 130 ;;
                *) ;;
            esac
        done
    } always {
        restore_frame_rate_input_mode
        print -r -- ''
    }
}
# 帧率使用明确预设或数字输入，不在配置行直接切换数值。
choose_frame_rate() {
    local result='' line='' rc=0 value='' label=''
    local -a rows
    while true; do
        rows=("current"$'\t'"保持当前帧率：$FPS FPS")
        for value in 15 24 25 30 50 60; do
            label="$value FPS"
            [[ "$value" != "$FPS" ]] || label+='（当前）'
            rows+=("$value"$'\t'"$label")
        done
        rows+=($'custom\t手动输入数字帧率（1..60）' $'back\t返回录制配置' $'cancel\t取消本轮')
        result="$(printf '%s\n' "${rows[@]}" | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' "$FZF_BIN" --no-multi \
            --delimiter=$'\t' --with-nth=2.. --expect=left --height=70% --info=hidden \
            --bind='up:up,down:down,tab:down,shift-tab:up' --header="当前：$FPS FPS；↑/↓ 或 Tab 选择，回车设值；← 返回录制配置；Esc 取消本轮" --prompt='帧率设置 > ')"
        rc=$?
        [[ "$result" != left && "$result" != left$'\n'* ]] || return 20
        (( rc == 0 )) || { (( rc == 1 || rc == 130 )) && return 130; return "$rc"; }
        line="${${(@f)result}[-1]}"
        case "${line%%$'\t'*}" in
            current) return 0 ;;
            15|24|25|30|50|60) FPS="${line%%$'\t'*}"; return 0 ;;
            custom)
                read_numeric_frame_rate
                rc=$?
                (( rc != 20 )) || continue
                return "$rc" ;;
            back) return 20 ;;
            cancel|'') return 130 ;;
            *) return 1 ;;
        esac
    done
}
# 声音模式只提供已实现的静音与系统声音，当前值默认保持。
choose_audio_mode() {
    local result='' line='' rc=0 current_label='' none_label='静音：不录制任何声音' system_label='录制声音：系统 / 应用声音，不录麦克风'
    local -a rows
    [[ "$AUDIO" != none ]] || none_label+='（当前）'
    [[ "$AUDIO" != system ]] || system_label+='（当前）'
    if [[ "$AUDIO" == system ]]; then
        current_label='录制声音'
        rows=("system"$'\t'"$system_label" "none"$'\t'"$none_label")
    else
        current_label='静音'
        rows=("none"$'\t'"$none_label" "system"$'\t'"$system_label")
    fi
    rows+=($'back\t返回录制配置' $'cancel\t取消本轮')
    result="$(printf '%s\n' "${rows[@]}" | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' "$FZF_BIN" --no-multi \
        --delimiter=$'\t' --with-nth=2.. --expect=left --height=65% --info=hidden \
        --bind='up:up,down:down,tab:down,shift-tab:up' --header="当前：$current_label；系统声音可能包含同应用其它窗口；← 返回录制配置；Esc 取消本轮" --prompt='声音设置 > ')"
    rc=$?
    [[ "$result" != left && "$result" != left$'\n'* ]] || return 20
    (( rc == 0 )) || { (( rc == 1 || rc == 130 )) && return 130; return "$rc"; }
    line="${${(@f)result}[-1]}"
    case "${line%%$'\t'*}" in
        none|system) AUDIO="${line%%$'\t'*}"; return 0 ;;
        back) return 20 ;;
        cancel|'') return 130 ;;
        *) return 1 ;;
    esac
}
# 子层可返回选窗；默认选中返回项，普通回车不会直接开始录制。
confirm_recording() {
    local result rc line audio_label
    while true; do
        audio_label='静音'
        [[ "$AUDIO" != system ]] || audio_label='录制声音'
        result="$(printf '%s\n' $'back\t返回窗口选择' $'start\t开始录制' "audio"$'\t'"声音设置（当前：$audio_label）" "fps"$'\t'"帧率设置（当前：$FPS FPS）" $'cancel\t取消本轮' | \
            FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' "$FZF_BIN" --no-multi --delimiter=$'\t' --with-nth=2.. \
            --expect=left --height=70% --bind='up:up,down:down,tab:down,shift-tab:up' \
            --header="目标：$TARGET_LABEL | 声音：$audio_label | 帧率：$FPS FPS | ← 返回窗口选择；Esc 取消本轮" --prompt='确认录制 > ')"
        rc=$?
        [[ "$result" != left && "$result" != left$'\n'* ]] || return 20
        (( rc == 0 )) || { (( rc == 1 || rc == 130 )) && return 130; return "$rc"; }
        line="${${(@f)result}[-1]}"
        case "${line%%$'\t'*}" in
            back) return 20 ;;
            cancel|'') return 130 ;;
            audio)
                choose_audio_mode
                rc=$?
                (( rc == 0 || rc == 20 )) || return "$rc" ;;
            fps)
                choose_frame_rate
                rc=$?
                (( rc == 0 || rc == 20 )) || return "$rc" ;;
            start) return 0 ;;
            *) return 1 ;;
        esac
    done
}
# 只读解析当前用户的系统桌面，失败时使用约定的用户桌面目录。
resolve_desktop_directory() {
    local desktop=''
    desktop="$(/usr/bin/osascript -e 'POSIX path of (path to desktop folder)' 2>/dev/null)" || desktop=''
    [[ -n "$desktop" && "$desktop" == /* ]] || desktop="$HOME/Desktop"
    REPLY="${desktop:A}"
}
# 只做路径词法解析，支持终端拖入转义，不执行输入中的任何表达式。
normalize_output_directory() {
    local raw="${1%$'\r'}" candidate=''
    local -a words
    REPLY=''
    if [[ -d "$raw" ]]; then
        candidate="$raw"
    else
        words=( ${(z)raw} )
        (( ${#words} == 1 )) || return 1
        candidate="${(Q)words[1]}"
        case "$candidate" in
            '~') candidate="$HOME" ;;
            '~/'*) candidate="$HOME/${candidate#\~/}" ;;
        esac
    fi
    [[ -n "$candidate" && -d "$candidate" && -r "$candidate" && -x "$candidate" && -w "$candidate" ]] || return 1
    REPLY="${candidate:A}"
}
# 采集前取得有效保存目录；默认桌面，输入结束或中断不开始录制。
choose_output_directory() {
    [[ -t 0 && -t 1 ]] || { log_note '✖ 非交互录制必须指定 --output PATH.mp4。'; return 64; }
    local default_directory='' answer=''
    resolve_desktop_directory
    default_directory="$REPLY"
    while true; do
        print -r -- '请输入或拖入已存在且可写的保存目录；Ctrl+C 取消本轮。'
        print_styled '1;32' "直接回车使用系统桌面：$default_directory"
        print -n -r -- '保存目录 > '
        if ! IFS= read -r answer; then
            log_note 'ℹ 保存地址输入已结束，未开始录制。'
            return 130
        fi
        [[ -n "$answer" ]] || answer="$default_directory"
        if normalize_output_directory "$answer"; then
            return 0
        fi
        log_note '⚠ 保存目录不存在、不可读取或不可写，请重新输入；不会创建未知目录。'
    done
}
# 显式文件路径优先，否则先询问目录，再生成带时间和 PID 的新文件名。
prepare_output_path() {
    if [[ -z "$OUTPUT" ]]; then
        choose_output_directory || return $?
        OUTPUT="$REPLY/窗口录屏-$(date '+%Y.%m.%d %H-%M-%S')-$$.mp4"
    else
        OUTPUT="${OUTPUT:a}"
    fi
    [[ -d "${OUTPUT:h}" && -w "${OUTPUT:h}" && ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || { log_note '✖ 输出父目录不可写，或目标已存在；未录制。'; return 1; }
}
# 只对成功发布的最终视频询问目录操作，取消或非交互时保持不打开。
offer_open_output_directory() {
    [[ -t 0 && -t 1 && -f "$OUTPUT" && ! -L "$OUTPUT" && -s "$OUTPUT" ]] || return 0
    if [[ -z "$FZF_BIN" || ! -x "$FZF_BIN" ]]; then
        log_note '⚠ 录制已保存；fzf 当前不可用，未打开所在目录。'
        return 0
    fi
    local result='' selected='' menu_rc=0 parent_label='终端'
    [[ "${JOBS_RECORD_PARENT_MENU:-}" != list ]] || parent_label='功能菜单'
    result="$(printf '%s\n' $'keep\t不打开（默认）' $'open\t打开录制文件所在目录' "back"$'\t'"返回$parent_label（不打开）" | \
        FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' "$FZF_BIN" --no-multi --delimiter=$'\t' --with-nth=2.. \
        --expect=left --height=12 --layout=reverse --border --bind='up:up,down:down,tab:down,shift-tab:up' \
        --header="录制已保存；↑/↓ 或 Tab 选择，回车确认；← 返回$parent_label；Esc 不打开" --prompt='录制完成 > ')" || menu_rc=$?
    [[ "$result" != left && "$result" != left$'\n'* ]] || return 20
    (( menu_rc == 0 )) || return 0
    selected="${${${(@f)result}[-1]}%%$'\t'*}"
    [[ "$selected" != back ]] || return 20
    [[ "$selected" == open ]] || return 0
    /usr/bin/open "${OUTPUT:h}" || log_note '⚠ 视频已保存，但打开所在目录失败。'
    return 0
}
# 仅在地址有效且目标明确后采集，成功发布后进入唯一的目录操作询问。
record_target() {
    local -a args
    prepare_output_path || return $?
    args=(record --target "$TARGET" --output "$OUTPUT" --fps "$FPS" --audio "$AUDIO")
    [[ -z "$DURATION" ]] || args+=(--duration "$DURATION")
    (( SHOW_CURSOR )) || args+=(--no-cursor)
    log_note "ℹ 即将显示 5 秒倒计时，随后录制；声音=$AUDIO，FPS=$FPS。倒计时中 Ctrl+C 取消，录制中 Ctrl+C 保存。"
    local recording_rc=0
    run_managed "$ENGINE" "${args[@]}" || recording_rc=$?
    (( recording_rc == 0 )) || return "$recording_rc"
    [[ -f "$OUTPUT" && ! -L "$OUTPUT" && -s "$OUTPUT" ]] || { log_note '✖ 内核未发布可用的最终 MP4，未执行目录操作。'; return 1; }
    log_note "✔ 录制已保存：$OUTPUT"
    offer_open_output_directory
}
# 真正返回已有父菜单；直接调用仅返回终端，不递归启动功能菜单。
return_to_recording_parent() {
    if [[ "${JOBS_RECORD_PARENT_MENU:-}" == list ]]; then
        return 20
    fi
    log_note 'ℹ 已返回终端。'
    return 0
}
# 模式分发保证体检、列窗、准备和授权都不会进入录制。
run_business() {
    case "$MODE" in
        prepare) log_note '✔ 依赖和内核已复检，未录制。'; return 0 ;;
        permission) "$ENGINE" request-permission; return $? ;;
        list)
            ensure_recording_permission || return $?
            local listing
            local -a list_args=(list)
            (( ALL_WINDOWS )) || list_args+=(--browsers)
            (( ! INCLUDE_AUXILIARY )) || list_args+=(--include-auxiliary)
            listing="$("$ENGINE" "${list_args[@]}")"
            local listing_rc=$?
            (( listing_rc == 0 )) || return "$listing_rc"
            print -r -- $'窗口ID\t应用\t标题\t尺寸'
            [[ -z "$listing" ]] || print -r -- "$listing" | /usr/bin/cut -f2-
            return 0 ;;
    esac
    ensure_recording_permission || return $?
    if [[ -n "$WINDOW_ID" ]]; then
        local -a resolve_args=(resolve --window-id "$WINDOW_ID")
        (( ! INCLUDE_AUXILIARY )) || resolve_args+=(--include-auxiliary)
        TARGET="$("$ENGINE" "${resolve_args[@]}")" || return $?
        if (( ! YES )); then
            print -n -r -- "将录制真实窗口 ID $WINDOW_ID（声音=$AUDIO）。输入 YES 开始，其它取消："
            local answer
            IFS= read -r answer && [[ "$answer" == YES ]] || return 130
        fi
        local record_rc=0
        record_target || record_rc=$?
        if (( record_rc == 20 )); then
            return_to_recording_parent
            return $?
        fi
        return "$record_rc"
    fi
    local rc
    while true; do
        choose_window
        rc=$?
        if (( rc == 20 )); then
            return_to_recording_parent
            return $?
        fi
        (( rc == 0 )) || return "$rc"
        confirm_recording
        rc=$?
        (( rc == 20 )) && continue
        (( rc == 0 )) || return "$rc"
        record_target
        rc=$?
        if (( rc == 20 )); then
            return_to_recording_parent
            return $?
        fi
        return "$rc"
    done
}
# 集中编排自述、环境门禁、原生准备及用户选择。
main() {
    show_script_intro_and_wait "$@" # 先说明用途和本轮修复范围，再取得明确运行意图。
    initialize_runtime # 解析相对包位置并准备私有日志及进程清理。
    check_environment # 逐层检查、条件式补齐并复检实际依赖。
    prepare_engine # 编译或复用通过纯逻辑自检的原生内核。
    run_business # 按模式执行体检、列窗、准备、授权或明确目标的录制。
}

main "$@"
