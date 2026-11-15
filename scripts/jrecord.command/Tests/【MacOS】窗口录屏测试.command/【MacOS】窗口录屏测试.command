#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 用途：隔离回归窗口录屏入口的参数、依赖门禁及真实 fzf 键盘返回行为。
# - 范围：只创建系统临时夹具，所有安装、编译和采集业务均被假函数替换。
# - 运行：按回车确认；自动验证使用 --yes，Ctrl+C 可取消。

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
    if "$@"; then
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

typeset -g TEST_SOURCE="${(%):-%x}" TEST_DIR='' TEST_TARGET='' TEST_FZF=''
# 首屏说明隔离范围，并按调用方式确认测试意图。
show_test_intro() {
  local arg
  for arg in "$@"; do
    if [[ "$arg" == --help || "$arg" == -h ]]; then
      print -r -- '窗口录屏隔离测试：无参数交互确认，--yes 自动运行；需要系统 Ruby/zsh 和已有健康 fzf。'
      exit 0
    fi
  done
  print -r -- '窗口录屏隔离回归：只运行参数、依赖假实现与真实 PTY/fzf；不安装、不编译、不录屏、不授权。'
  if (( $# )); then
    [[ $# == 1 && "$1" == --yes ]] || { print -u2 '仅支持 --yes 或 --help。'; exit 64; }
    return 0
  fi
  [[ -t 0 ]] || { print -u2 '自动验证请显式传入 --yes。'; exit 64; }
  print -n -r -- '按回车开始隔离测试，Ctrl+C 取消：'
  IFS= read -r || exit 130
}
# 按本文件位置解析被测入口，不依赖启动目录。
initialize_test_paths() {
  setopt NO_NOMATCH PIPE_FAIL
  TEST_DIR="${${TEST_SOURCE:A}:h}"
  TEST_TARGET="${TEST_DIR:h:h}/jrecord.command"
  [[ -r "$TEST_TARGET" ]] || { print -u2 -r -- "缺少被测入口：$TEST_TARGET"; exit 1; }
}
# 检查测试运行时及已有 fzf，不安装任何测试依赖。
check_test_environment() {
  local candidate
  /usr/bin/ruby -rpty -ropen3 -rjson -rfileutils -rtmpdir -rio/console -e 'exit 0' || exit 1
  for candidate in "$(command -v fzf 2>/dev/null)" /opt/homebrew/bin/fzf /usr/local/bin/fzf; do
    if [[ -x "$candidate" ]] && "$candidate" --version >/dev/null 2>&1; then
      TEST_FZF="$candidate"
      return 0
    fi
  done
  print -u2 '真实键盘回归需要已有健康 fzf；未运行安装，测试停止。'
  exit 1
}
# 用系统 Ruby 驱动独立 zsh 和真实伪终端，所有业务边界均保持隔离。
run_isolated_tests() {
  /usr/bin/ruby - "$TEST_TARGET" "$TEST_FZF" <<'RUBY'
require 'fileutils'
require 'tmpdir'
require 'open3'
require 'pty'
require 'io/console'
require 'shellwords'
require 'json'

production, fzf = ARGV
root = Dir.mktmpdir('jobs-window-record-tests.')
puts "隔离夹具：#{root}"
source = File.read(production)
raise '无法安全提取生产函数：末尾入口不匹配' unless source.match?(/^main "\$@"\s*\z/)
definitions = File.join(root, 'production-functions.zsh')
File.write(definitions, source.sub(/^main "\$@"\s*\z/, ''))
count = 0
assert = lambda do |condition, label|
  raise "FAIL: #{label}" unless condition
  count += 1
end
run_shell = lambda do |name, body|
  folder = File.join(root, name)
  FileUtils.mkdir_p(folder)
  trace = File.join(folder, 'trace')
  script = File.join(folder, 'case.zsh')
  File.write(script, "source \"$SUT_DEFINITIONS\"\n" + body)
  env = {'NO_COLOR'=>'1', 'TERM'=>'dumb', 'TRACE'=>trace, 'SUT_DEFINITIONS'=>definitions, 'JOBS_RECORD_PARENT_MENU'=>nil}
  output, error, status = Open3.capture3(env, '/bin/zsh', '-f', script)
  events = File.file?(trace) ? File.readlines(trace).map(&:chomp) : []
  [output, error, status.exitstatus, events]
end

# 帮助及参数校验直接运行真实入口，检查未产生会话、缓存或日志。
help_cases = [['--help'], ['--duration', 'NaN', '--help'], ['--unknown', '--help'], ['--window-id', '--help'], ['--doctor', '--prepare', '--help'], ['--version', '--help'], ['--help', '--unknown'], ['--fps', 'NaN', '--help', '--doctor', '--prepare']]
help_cases.each_with_index do |arguments, index|
  folder = File.join(root, "help-#{index}")
  FileUtils.mkdir_p(folder)
  output, error, status = Open3.capture3({'NO_COLOR'=>'1', 'TERM'=>'dumb', 'TMPDIR'=>folder, 'XDG_CACHE_HOME'=>File.join(folder, 'cache')}, '/bin/zsh', production, *arguments)
  assert.call(status.success? && output.include?('--doctor') && output.include?('--window-id'), "帮助优先：#{arguments.inspect} #{error}")
  assert.call(Dir.children(folder).empty?, "帮助产生了写入：#{arguments.inspect}")
end
invalid = []
%w[NaN inf Infinity -1 0 61 1.5 999999999999999].each { |value| invalid << ['--fps', value] }
%w[NaN nan inf Infinity -1 0 99999999 86400.001 1e3].each { |value| invalid << ['--duration', value] }
%w[NaN -1 0 999999999999999].each { |value| invalid << ['--window-id', value] }
invalid += [['--audio', 'mic'], ['--output', 'wrong.mov'], ['--fps'], ['--duration'], ['--window-id'], ['--doctor', '--prepare'], ['--doctor', '--list'], ['--list', '--window-id', '12']]
invalid.each_with_index do |arguments, index|
  folder = File.join(root, "invalid-#{index}")
  FileUtils.mkdir_p(folder)
  _, _, status = Open3.capture3({'NO_COLOR'=>'1', 'TERM'=>'dumb', 'TMPDIR'=>folder, 'XDG_CACHE_HOME'=>File.join(folder, 'cache')}, '/bin/zsh', production, *arguments)
  assert.call(status.exitstatus == 64 && Dir.children(folder).empty?, "无效参数未安全拒绝：#{arguments.inspect}")
end
output, error, status, events = run_shell.call('valid-parser', <<~'ZSH')
  parse_arguments --window-id 12 --duration 0.125 --fps 60 --audio system --output '中文 空格.mp4' --no-cursor --yes --no-repair
  print -r -- "$WINDOW_ID|$DURATION|$FPS|$AUDIO|$OUTPUT|$SHOW_CURSOR|$YES|$REPAIR"
ZSH
assert.call(status == 0 && output.strip == '12|0.125|60|system|中文 空格.mp4|0|1|0', "有效参数保真：#{error}")
output, error, status, events = run_shell.call('duration-boundary', <<~'ZSH')
  parse_arguments --window-id 12 --duration 86400 --yes
  print -r -- "$DURATION"
ZSH
assert.call(status == 0 && output.strip == '86400', "允许时长上界：#{error}")
doctor_folder = File.join(root, 'doctor-no-write')
FileUtils.mkdir_p(doctor_folder)
_, error, status = Open3.capture3({'NO_COLOR'=>'1', 'TERM'=>'dumb', 'TMPDIR'=>doctor_folder, 'XDG_CACHE_HOME'=>File.join(doctor_folder, 'cache')}, '/bin/zsh', production, '--doctor')
doctor_owned_files = Dir.children(doctor_folder).select { |name| name == 'cache' || name == 'record.log' || name.start_with?('jobs-window-record.') }
assert.call([0, 1].include?(status.exitstatus) && doctor_owned_files.empty?, "真实 doctor 不应创建工具日志或编译缓存：#{error}")

# 假包管理器只响应只读查询，真实安装动作由 run_managed 假函数记录。
brew_prefix = File.join(root, 'brew-prefix')
FileUtils.mkdir_p(File.join(brew_prefix, 'bin'))
brew = File.join(root, 'mock-brew')
File.write(brew, <<~'ZSH')
  #!/bin/zsh
  print -r -- "BREW:$*" >> "$TRACE"
  case "$1" in
    --prefix) print -r -- "$MOCK_BREW_PREFIX" ;;
    config|--version) exit 0 ;;
    list) exit 1 ;;
    *) print -r -- 'FORBIDDEN:真实包管理器写操作' >> "$TRACE"; exit 90 ;;
  esac
ZSH
FileUtils.chmod(0755, brew)
ENV['MOCK_BREW'] = brew
ENV['MOCK_BREW_PREFIX'] = brew_prefix
health_base = <<~'ZSH'
  MODE=prepare
  REPAIR=1
  APPLE_OK=1
  FZF_OK=1
  APPLE_REPAIR_OK=1
  BREW_FOUND=1
  INSTALL_RC=0
  POSTCHECK_OK=1
  log_note() { print -r -- "NOTE:$*" >> "$TRACE"; }
  apple_toolchain_healthy() { print APPLE_CHECK >> "$TRACE"; (( APPLE_OK )); }
  repair_apple_toolchain() {
    print APPLE_REPAIR >> "$TRACE"
    (( APPLE_REPAIR_OK )) || return 9
    APPLE_OK=1
  }
  fzf_healthy() { print FZF_CHECK >> "$TRACE"; (( FZF_OK )); }
  jobs_brew_find() {
    print BREW_FIND >> "$TRACE"
    (( BREW_FOUND )) || return 1
    print -r -- "$MOCK_BREW"
  }
  jobs_brew_choose_installation() { print BREW_CHOOSE >> "$TRACE"; JOBS_HOMEBREW_INSTALL_MODE=user; }
  jobs_brew_install_user() { print BREW_INSTALL >> "$TRACE"; JOBS_HOMEBREW_BIN="$MOCK_BREW"; }
  jobs_brew_install_system() { print FORBIDDEN_SYSTEM_INSTALL >> "$TRACE"; return 91; }
  run_managed() {
    print -r -- "INSTALL:$*" >> "$TRACE"
    (( INSTALL_RC == 0 )) || return "$INSTALL_RC"
    (( POSTCHECK_OK )) && FZF_OK=1
    return 0
  }
  prepare_engine() { print FORBIDDEN_COMPILE >> "$TRACE"; return 92; }
  record_target() { print FORBIDDEN_RECORD >> "$TRACE"; return 93; }
ZSH
health_case = lambda do |name, setup, finish = "check_environment\nprint READY >> \"$TRACE\"\n"|
  run_shell.call(name, health_base + setup + "\n" + finish)
end
_, _, status, events = health_case.call('healthy', '')
assert.call(status == 0 && events == %w[APPLE_CHECK FZF_CHECK READY], '健康依赖不应调用安装通道')
_, _, status, events = health_case.call('missing-tool', 'FZF_OK=0', "check_environment\ncheck_environment\nprint READY >> \"$TRACE\"\n")
assert.call(status == 0 && events.count { |line| line.start_with?('INSTALL:') } == 1 && events.include?('READY'), '末端缺失后只安装一次并复用健康结果')
assert.call(events.count('FZF_CHECK') == 3 && events.include?('BREW_FIND'), '安装前后复检与后续健康复用')
_, _, status, events = health_case.call('multiple-missing', "APPLE_OK=0\nFZF_OK=0\nBREW_FOUND=0")
assert.call(status == 0 && events.count('APPLE_REPAIR') == 1 && events.count('BREW_INSTALL') == 1 && events.count { |line| line.start_with?('INSTALL:') } == 1 && events.include?('READY'), '多层缺失应逐层补齐并复检')
assert.call(events.index('APPLE_REPAIR') < events.index('BREW_INSTALL') && events.count('APPLE_CHECK') == 2, '上游健康后才准备下游工具')
_, _, status, events = health_case.call('install-failed', "FZF_OK=0\nINSTALL_RC=9")
assert.call(status != 0 && events.count { |line| line.start_with?('INSTALL:') } == 1 && !events.include?('READY'), '安装失败必须阻断下游')
_, _, status, events = health_case.call('postcheck-failed', "FZF_OK=0\nPOSTCHECK_OK=0")
assert.call(status != 0 && events.count('FZF_CHECK') == 2 && !events.include?('READY'), '安装成功但复检失败必须停止')
_, _, status, events = health_case.call('apple-repair-failed', "APPLE_OK=0\nAPPLE_REPAIR_OK=0")
assert.call(status != 0 && events.include?('APPLE_REPAIR') && !events.include?('FZF_CHECK') && !events.include?('READY'), '上游修复失败不得进入下游')
_, _, status, events = health_case.call('apple-postcheck-failed', "APPLE_OK=0\nrepair_apple_toolchain() { print APPLE_REPAIR >> \"$TRACE\"; return 0; }")
assert.call(status != 0 && events.count('APPLE_CHECK') == 2 && !events.include?('FZF_CHECK') && !events.include?('READY'), '上游修复声称成功但复检失败也必须停止')
_, _, status, events = health_case.call('repair-disabled', "APPLE_OK=0\nREPAIR=0")
assert.call(status != 0 && !events.include?('APPLE_REPAIR') && !events.include?('READY'), '禁止修复时不得触发修复')
_, _, status, events = health_case.call('window-id-no-fzf', "MODE=interactive\nWINDOW_ID=12\nFZF_OK=0")
assert.call(status == 0 && events == %w[APPLE_CHECK READY], '指定窗口 ID 的执行路径不依赖 fzf')
_, _, status, events = health_case.call('doctor-readonly', "APPLE_OK=0\nFZF_OK=0\nMODE=doctor", "check_environment\nprint FORBIDDEN_DOCTOR_FALLTHROUGH >> \"$TRACE\"\n")
assert.call(status != 0 && events == %w[APPLE_CHECK FZF_CHECK], 'doctor 不得修复、编译或继续业务')

# SDK 错误分类使用真实纯函数；更新与安装仍由假边界返回确定结果。
['A network error occurred', 'The operation timed out', 'NSURLErrorDomain -1009', '连接超时'].each_with_index do |detail, index|
  ENV['SDK_TEST_DETAIL'] = detail
  _, _, status, _ = run_shell.call("network-classifier-#{index}", 'sdk_network_failure "$SDK_TEST_DETAIL"')
  assert.call(status == 0, "SDK 网络错误分类：#{detail}")
end
['Permission denied', 'No space left on device', 'License agreement required', '没有权限'].each_with_index do |detail, index|
  ENV['SDK_TEST_DETAIL'] = detail
  _, _, status, _ = run_shell.call("local-classifier-#{index}", 'sdk_local_failure "$SDK_TEST_DETAIL"')
  assert.call(status == 0, "SDK 本地错误分类：#{detail}")
end
_, _, status, _ = run_shell.call('unknown-classifier', 'sdk_network_failure "checksum mismatch"; network_rc=$?; sdk_local_failure "checksum mismatch"; local_rc=$?; (( network_rc != 0 && local_rc != 0 ))')
assert.call(status == 0, '未知错误不应擅自分类为可重试网络故障')
sdk_base = <<~'ZSH'
  RUN_DIR="${TRACE:h}"
  LOG_FILE="$RUN_DIR/mock-install.log"
  : > "$LOG_FILE"
  SDK_LIST_COUNT=0
  SDK_INSTALL_COUNT=0
  SDK_READY=0
  SDK_CASE=network
  function /usr/bin/xcode-select() { print XCODE_CHECK >> "$TRACE"; return 0; }
  log_note() { print -r -- "NOTE:$*" >> "$TRACE"; }
  apple_toolchain_healthy() { print SDK_CHECK >> "$TRACE"; (( SDK_READY )); }
  run_captured() {
    local destination="$1"
    SDK_LIST_COUNT=$(( SDK_LIST_COUNT + 1 ))
    print -r -- "SDK_LIST:$SDK_LIST_COUNT" >> "$TRACE"
    case "$SDK_CASE" in
      local-list) print 'network unavailable: Permission denied' > "$destination"; return 1 ;;
      unknown-list) print 'checksum mismatch' > "$destination"; return 1 ;;
      cancel) print 'network timeout' > "$destination"; return 1 ;;
    esac
    if [[ "$SDK_CASE" == network ]] && (( SDK_LIST_COUNT < 3 )); then
      print 'NSURLErrorDomain connection timed out' > "$destination"
      return 1
    fi
    print '* Label: Command Line Tools for Xcode-27.2' > "$destination"
    return 0
  }
  run_managed() {
    SDK_INSTALL_COUNT=$(( SDK_INSTALL_COUNT + 1 ))
    print -r -- "SDK_INSTALL:$SDK_INSTALL_COUNT" >> "$TRACE"
    if [[ "$SDK_CASE" == local-install ]]; then
      print 'No space left on device' >> "$LOG_FILE"
      return 1
    fi
    if (( SDK_INSTALL_COUNT < 3 )); then
      print 'NSURLErrorDomain download failed: connection timed out' >> "$LOG_FILE"
      return 1
    fi
    SDK_READY=1
    return 0
  }
  sleep() {
    print -r -- "WAIT:$1" >> "$TRACE"
    if [[ "$SDK_CASE" == cancel ]]; then
      kill -INT $$
    fi
  }
ZSH
_, _, status, events = run_shell.call('sdk-retry-success', sdk_base + "repair_apple_toolchain\nresult=$?\nprint -r -- \"SDK_RESULT:$result\" >> \"$TRACE\"\nexit \"$result\"\n")
assert.call(status == 0 && events.grep(/^SDK_LIST:/).length == 3 && events.grep(/^SDK_INSTALL:/).length == 3 && events.include?('SDK_RESULT:0'), 'SDK 更新目录与安装网络连续失败后自动成功')
assert.call(events.grep(/^WAIT:/) == %w[WAIT:2 WAIT:4 WAIT:2 WAIT:4], 'SDK 重试按目录和安装分别递增退避')
['local-list', 'unknown-list', 'local-install'].each do |scenario|
  _, _, status, events = run_shell.call("sdk-#{scenario}", sdk_base + "SDK_CASE=#{scenario}\nrepair_apple_toolchain\nresult=$?\nprint -r -- \"SDK_RESULT:$result\" >> \"$TRACE\"\nexit \"$result\"\n")
  expected_installs = scenario == 'local-install' ? 1 : 0
  assert.call(status != 0 && events.grep(/^SDK_LIST:/).length == 1 && events.grep(/^SDK_INSTALL:/).length == expected_installs && events.grep(/^WAIT:/).empty?, "SDK 本地或未知错误立即停止：#{scenario}")
end
_, _, status, events = run_shell.call('sdk-retry-cancel', sdk_base + <<~'ZSH')
  SDK_CASE=cancel
  stop_owned_child() { print -r -- "STOP:$1" >> "$TRACE"; }
  trap 'handle_signal INT 130' INT
  repair_apple_toolchain
  print FORBIDDEN_AFTER_CANCEL >> "$TRACE"
ZSH
assert.call(status == 130 && events.include?('STOP:INT') && events.grep(/^SDK_INSTALL:/).empty? && !events.include?('FORBIDDEN_AFTER_CANCEL'), 'SDK 网络重试期间 Ctrl+C 取消且不进入安装')

# PTY 运行真实 fzf，原生内核只提供确定窗口快照，录制边界仅写标记。
engine = File.join(root, 'mock-engine')
File.write(engine, <<~'ZSH')
  #!/bin/zsh
  print -r -- "ENGINE:$*" >> "$TRACE"
  if [[ "$1" == list ]]; then
    print LIST >> "$TRACE"
    print -r -- $'token-alpha\tChrome Window Alpha'
    print -r -- $'token-beta\tSafari Window Beta'
    exit 0
  fi
  if [[ "$1" == resolve ]]; then
    print token-resolved
    exit 0
  fi
  print -r -- "FORBIDDEN_ENGINE:$*" >> "$TRACE"
  exit 94
ZSH
FileUtils.chmod(0755, engine)
ENV['SCOPE_ENGINE'] = engine
business_body = <<~'ZSH'
    ENGINE="$MOCK_ENGINE"
    FZF_BIN="$REAL_FZF"
    MODE=interactive
    ensure_recording_permission() { return 0; }
    record_target() {
      print -r -- "RECORD:$TARGET" >> "$TRACE"
      print -r -- "SETTINGS:$FPS|$AUDIO" >> "$TRACE"
    }
    log_note() { print -r -- "NOTE:$*" >> "$TRACE"; }
    run_business
    result=$?
    print -r -- "RESULT:$result" >> "$TRACE"
    exit "$result"
ZSH
pty_case = lambda do |name, actions, body = nil, parent_menu = nil|
  folder = File.join(root, name)
  FileUtils.mkdir_p(folder)
  trace = File.join(folder, 'trace')
  harness = File.join(folder, 'pty-case.zsh')
  File.write(harness, "source \"$SUT_DEFINITIONS\"\nstty rows 40 cols 140\n" + (body || business_body))
  env = {'NO_COLOR'=>'1', 'TERM'=>'xterm-256color', 'FZF_DEFAULT_OPTS'=>'', 'FZF_DEFAULT_OPTS_FILE'=>'', 'SUT_DEFINITIONS'=>definitions, 'MOCK_ENGINE'=>engine, 'REAL_FZF'=>fzf, 'TRACE'=>trace, 'JOBS_RECORD_PARENT_MENU'=>parent_menu}
  buffer = ''.b
  process_id = nil
  begin
    PTY.spawn(env, '/bin/zsh', '-f', harness) do |reader, writer, pid|
      process_id = pid
      writer.sync = true
      reader.winsize = [40, 140]
      pump = lambda do |seconds|
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0
          next unless IO.select([reader], nil, nil, [remaining, 0.03].min)
          begin
            buffer << reader.read_nonblock(65536)
          rescue IO::WaitReadable
          rescue EOFError, Errno::EIO
            break
          end
        end
      end
      wait_for = lambda do |text|
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 8
        until buffer.include?(text.b)
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise "PTY timeout #{name}: #{text}; tail=#{buffer[-700, 700].inspect}" if remaining <= 0
          next unless IO.select([reader], nil, nil, [remaining, 0.2].min)
          begin
            buffer << reader.read_nonblock(65536)
          rescue IO::WaitReadable
          rescue EOFError, Errno::EIO
            raise "PTY ended early #{name}: #{text}; tail=#{buffer[-700, 700].inspect}"
          end
        end
        buffer.clear
      end
      actions.each do |text, keys|
        wait_for.call(text)
        pump.call(0.18)
        terminator = keys.end_with?("\r") ? "\r" : (keys.end_with?("\e[D") ? "\e[D" : nil)
        if terminator && keys.bytesize > terminator.bytesize
          writer.write(keys.byteslice(0, keys.bytesize - terminator.bytesize))
          pump.call(0.25)
          writer.write(terminator)
        else
          writer.write(keys)
        end
        pump.call(0.16)
      end
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 8
      loop do
        ended = Process.waitpid(pid, Process::WNOHANG)
        break if ended
        raise "PTY did not exit #{name}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        if IO.select([reader], nil, nil, 0.1)
          begin
            buffer << reader.read_nonblock(65536)
          rescue IO::WaitReadable, EOFError, Errno::EIO
          end
        end
      end
      process_id = nil
    end
  ensure
    if process_id
      begin
        Process.kill('TERM', process_id)
        Process.waitpid(process_id)
      rescue Errno::ESRCH, Errno::ECHILD
      end
    end
  end
  File.binwrite(File.join(folder, 'pty-tail'), buffer)
  events = File.file?(trace) ? File.readlines(trace).map(&:chomp) : []
  events << 'PTY_PASTE_MODE_CLOSED' if buffer.include?("\e[?2004l")
  events
end
intro_body = <<~'ZSH'
  trap 'print -r -- "INTRO_EXIT:$?" >> "$TRACE"' EXIT
  initialize_runtime() { print FORBIDDEN_INIT >> "$TRACE"; }
  show_script_intro_and_wait
  print INTRO_CONFIRMED >> "$TRACE"
ZSH
events = pty_case.call('pty-intro-parent-left', [['按回车继续', "\e[D"]], intro_body, 'list')
assert.call(events.include?('INTRO_EXIT:20') && !events.include?('INTRO_CONFIRMED') && !events.include?('FORBIDDEN_INIT'), '初始自述左键立即返回list且不初始化或开始业务')
events = pty_case.call('pty-intro-common-left', [['按回车继续', "\e[D"]], "JOBS_LIST_PARENT_MENU=list\n" + intro_body)
assert.call(events.include?('INTRO_EXIT:20') && !events.include?('INTRO_CONFIRMED'), '初始自述兼容通用list父标记并返回20')
events = pty_case.call('pty-intro-enter', [['按回车继续', "\r"]], intro_body)
assert.call(events.include?('INTRO_CONFIRMED') && events.include?('INTRO_EXIT:0'), '初始自述真实回车仍确认继续')
events = pty_case.call('pty-root-left', [['选择录制窗口', "\e[D"]])
assert.call(events.include?('RESULT:0') && events.grep(/^RECORD:/).empty?, '独立入口选窗左键正常返回终端且不录制')
events = pty_case.call('pty-parent-left', [['选择录制窗口', "\e[D"]], nil, 'list')
assert.call(events.include?('RESULT:20') && events.grep(/^RECORD:/).empty?, 'list 子层选窗左键透传父菜单返回码且不录制')
events = pty_case.call('pty-root-escape', [['选择录制窗口', "\e"]])
assert.call(events.include?('RESULT:130') && events.grep(/^RECORD:/).empty?, '选窗 Esc 取消本轮，区别于返回上一层')
events = pty_case.call('pty-config-return', [['选择录制窗口', "Alpha\r"], ['确认录制', "\e[D"], ['选择录制窗口', "Beta\r"], ['确认录制', "取消本轮\r"]])
assert.call(events.count('LIST') == 2 && events.include?('RESULT:130') && events.grep(/^RECORD:/).empty?, '窗口→配置→左键返回真实选窗，取消不录制')
events = pty_case.call('pty-empty-query-left', [['选择录制窗口', "Alpha\r"], ['确认录制', "zzzz-no-match\e[D"], ['选择录制窗口', "\e[D"]])
assert.call(events.count('LIST') == 2 && events.include?('RESULT:0') && events.grep(/^RECORD:/).empty?, '配置无匹配时左键逐层返回终端')
events = pty_case.call('pty-explicit-start', [['选择录制窗口', "Alpha\r"], ['确认录制', "开始录制\r"]])
assert.call(events.grep(/^RECORD:/) == ['RECORD:token-alpha'] && events.include?('RESULT:0'), '明确开始时仅透传本次快照 token')

# 设置使用真实独立子菜单；只有明确开始才接触假录制边界。
[15, 24, 25, 30, 50, 60].each do |value|
  events = pty_case.call("pty-fps-preset-#{value}", [
    ['选择录制窗口', "Alpha\r"], ['确认录制 >', "帧率设置\r"],
    ['帧率设置 >', "#{value} FPS\r"], ['确认录制 >', "开始录制\r"]
  ], "FPS=29\n" + business_body)
  assert.call(events.include?("SETTINGS:#{value}|none") && events.grep(/^RECORD:/).length == 1, "帧率预设 #{value} 确认后回配置并传给录制")
end
events = pty_case.call('pty-audio-current-preserved', [
  ['选择录制窗口', "Alpha\r"], ['确认录制 >', "声音设置\r"],
  ['声音设置 >', "\r"], ['确认录制 >', "开始录制\r"]
], "FPS=25\nAUDIO=system\n" + business_body)
assert.call(events.include?('SETTINGS:25|system') && events.grep(/^RECORD:/).length == 1, '声音子菜单默认保持当前值且不丢失帧率')
events = pty_case.call('pty-settings-preserved-across-menus', [
  ['选择录制窗口', "Alpha\r"], ['确认录制 >', "帧率设置\r"], ['帧率设置 >', "50 FPS\r"],
  ['确认录制 >', "声音设置\r"], ['声音设置 >', "录制声音\r"],
  ['确认录制 >', "帧率设置\r"], ['帧率设置 >', "手动输入数字帧率\r"],
  ['自定义帧率 >', "24\r"], ['确认录制 >', "声音设置\r"], ['声音设置 >', "静音\r"],
  ['确认录制 >', "开始录制\r"]
])
assert.call(events.include?('SETTINGS:24|none') && events.grep(/^RECORD:/).length == 1, '帧率与声音跨菜单反复设置后保留最终值，仅开始一次')
events = pty_case.call('pty-all-settings-left-to-parent', [
  ['选择录制窗口', "Alpha\r"], ['确认录制 >', "帧率设置\r"], ['帧率设置 >', "手动输入数字帧率\r"],
  ['自定义帧率 >', "48\e[D"], ['帧率设置 >', "zzzz-no-match\e[D"],
  ['确认录制 >', "声音设置\r"], ['声音设置 >', "zzzz-no-match\e[D"],
  ['确认录制 >', "\e[D"], ['选择录制窗口', "\e[D"]
], nil, 'list')
assert.call(events.include?('RESULT:20') && events.count('LIST') == 2 && events.grep(/^RECORD:/).empty?, '数字输入、无匹配帧率及声音菜单逐层左返，最终只返回 list')
[['帧率', '帧率设置'], ['声音', '声音设置']].each do |name, prompt|
  events = pty_case.call("pty-#{name}-escape", [
    ['选择录制窗口', "Alpha\r"], ['确认录制 >', "#{prompt}\r"], ["#{prompt} >", "\e"]
  ])
  assert.call(events.include?('RESULT:130') && events.grep(/^RECORD:/).empty?, "#{name}子菜单 Esc 取消整轮且不录制")
end

# 逐键运行生产输入函数；ANSI 与 bracketed paste 的数字不能冒充键盘帧率。
numeric_end = <<~'ZSH'
  report_numeric_exit() {
    local result=$?
    cleanup_runtime
    print -r -- "RESULT:$result" >> "$TRACE"
    print -r -- "SETTINGS:$FPS|$AUDIO" >> "$TRACE"
    print -r -- "PASTE_MODE:$FPS_INPUT_PASTE_MODE" >> "$TRACE"
  }
  trap report_numeric_exit EXIT
  trap 'handle_signal INT 130' INT
  read_numeric_frame_rate
  result=$?
  exit "$result"
ZSH
numeric_base = <<~'ZSH'
  FPS=29
  AUDIO=system
  record_target() { print FORBIDDEN_NUMERIC_RECORD >> "$TRACE"; return 95; }
ZSH
numeric_cases = [
  ['minimum', "1\r", 0, 1], ['maximum', "60\r", 0, 60],
  ['range-zero-corrected', "0\r24\r", 0, 24], ['range-61-corrected', "61\r25\r", 0, 25],
  ['120-never-truncated', "120\r30\r", 0, 30],
  ['ascii-only-and-backspace', "a٣０5x9\x7f0\r", 0, 50],
  ['CSI-OSC-SS3-filter', "\e[31m\e]0;12345\a\eO1;2A\e[0m48\r", 0, 48],
  ['OSC-ST-filter', "\e]0;60\e\\24\r", 0, 24],
  ['left-keeps-old', "60\e[D", 20, 29], ['SS3-left-keeps-old', "60\eOD", 20, 29],
  ['escape-cancels', "\e", 130, 29], ['CtrlC-cancels', "\x03", 130, 29],
  ['mixed-paste-rejected', "\e[200~3x0\n\e[201~\r\e[D", 20, 29],
  ['paste-newline-never-submits', "\e[200~30\n\e[201~\e[D", 20, 29]
]
numeric_cases.each do |name, keys, expected_result, expected_fps|
  events = pty_case.call("pty-numeric-#{name}", [['自定义帧率 >', keys]], numeric_base + numeric_end)
  assert.call(events.include?("RESULT:#{expected_result}") && events.include?("SETTINGS:#{expected_fps}|system") && events.include?('PASTE_MODE:0') && events.include?('PTY_PASTE_MODE_CLOSED') && !events.include?('FORBIDDEN_NUMERIC_RECORD'), "数字输入 #{name}：真实按键结果、帧率和声音正确，退出关闭 2004 且不录制")
end

# 只观察传入真实 fzf 的参数与行，不替换键盘选择结果。
observed_fzf = File.join(root, 'observed-real-fzf.rb')
File.write(observed_fzf, <<~'RUBY_FZF')
  #!/usr/bin/ruby
  require 'json'
  rows = STDIN.read
  header_argument = ARGV.find { |argument| argument.start_with?('--header=') }
  header_index = ARGV.index('--header')
  header = header_argument ? header_argument.split('=', 2).last : (header_index ? ARGV[header_index + 1] : '')
  snapshot = {'header'=>header, 'rows'=>rows.lines.map(&:chomp), 'arguments'=>ARGV}
  File.open(ENV.fetch('TRACE'), 'a') { |file| file.puts('FZF_MENU:' + JSON.generate(snapshot)) }
  IO.popen([ENV.fetch('REAL_FZF'), *ARGV], 'r+') do |process|
    process.write(rows)
    process.close_write
    STDOUT.write(process.read)
  end
  exit($?.exitstatus || 1)
RUBY_FZF
FileUtils.chmod(0755, observed_fzf)
menu_engine = File.join(root, 'menu-engine')
File.write(menu_engine, <<~'ZSH_MENU')
  #!/bin/zsh
  print -r -- "ENGINE:$*" >> "$TRACE"
  [[ "$1" == list ]] || { print FORBIDDEN_MENU_BUSINESS >> "$TRACE"; exit 94; }
  counter_file="${TRACE:h}/menu-list-count"
  counter=0
  [[ ! -f "$counter_file" ]] || counter="$(cat "$counter_file")"
  counter=$(( counter + 1 ))
  print -r -- "$counter" > "$counter_file"
  if [[ "${MOCK_MENU_CASE:-one}" == refresh ]] && (( counter == 1 )); then
    exit 0
  fi
  print -r -- $'main-token\t12714\tGoogle Chrome\tChrome Main Alpha\t1200×800'
  if [[ "$*" != *--browsers* ]]; then
    print -r -- $'other-token\t14000\tSafari\tSafari Main Beta\t900×700'
  fi
  if [[ "$*" == *--include-auxiliary* ]]; then
    for id in 5095 5096 5097 5098; do
      print -r -- "aux-$id"$'\t'"$id"$'\tGoogle Chrome\t[隐藏] [无标题]\t304×22'
    done
  fi
ZSH_MENU
FileUtils.chmod(0755, menu_engine)
ENV['OBSERVED_FZF'] = observed_fzf
ENV['MENU_ENGINE'] = menu_engine
menu_base = <<~'ZSH'
  ENGINE="$MENU_ENGINE"
  FZF_BIN="$OBSERVED_FZF"
  log_note() { print -r -- "OUTSIDE_MENU:$*" >> "$TRACE"; }
  record_target() { print FORBIDDEN_MENU_RECORD >> "$TRACE"; return 95; }
ZSH
menu_end = <<~'ZSH'
  choose_window
  result=$?
  print -r -- "RESULT:$result" >> "$TRACE"
  exit "$result"
ZSH
snapshots = lambda do |events|
  events.grep(/^FZF_MENU:/).map { |line| JSON.parse(line.sub(/^FZF_MENU:/, '')) }
end
data_rows = lambda do |snapshot|
  snapshot.fetch('rows').reject { |line| line.empty? || line.start_with?('@') }
end
events = pty_case.call('pty-menu-default-one', [['范围：浏览器 | 普通窗口：1 个', "\e[D"]], menu_base + menu_end)
menus = snapshots.call(events)
assert.call(menus.length == 1 && data_rows.call(menus.first).length == 1 && menus.first.fetch('header').include?('普通窗口：1 个'), '默认只计一条主窗口，操作行不计入窗口数')
assert.call(menus.first.fetch('rows').none? { |line| line.start_with?('@aux') } && events.grep(/^ENGINE:/) == ['ENGINE:list --browsers'], '普通菜单无辅助开关且不隐式透传诊断参数')
assert.call(menus.first.fetch('arguments').include?('--info=hidden'), '隐藏 fzf 对操作行的计数，仅显示真实窗口数量')
events = pty_case.call('pty-menu-explicit-diagnostic', [['诊断窗口（含辅助）：5 个', "\e[D"]], menu_base + "INCLUDE_AUXILIARY=1\n" + menu_end)
menus = snapshots.call(events)
assert.call(menus.length == 1 && data_rows.call(menus.first).length == 5 && menus.first.fetch('header').include?('范围：浏览器 | 诊断窗口（含辅助）：5 个') && events.include?('ENGINE:list --browsers --include-auxiliary'), '显式诊断模式清楚标注范围和辅助候选数')
assert.call(menus.first.fetch('rows').none? { |line| line.start_with?('@aux') } && events.include?('RESULT:20'), '诊断模式不暴露普通菜单辅助切换行，左键保留返回码')
events = pty_case.call('pty-menu-refresh-empty-to-one', [['当前没有可录窗口', "重新加载窗口\r"], ['普通窗口：1 个', "\e[D"]], menu_base + "export MOCK_MENU_CASE=refresh\n" + menu_end)
menus = snapshots.call(events)
assert.call(menus.length == 2 && menus.first.fetch('header').include?('普通窗口：0 个') && menus.first.fetch('header').include?('当前没有可录窗口') && data_rows.call(menus.first).empty?, '空态属于当前 header，操作入口仍可用且窗口数量为零')
assert.call(menus.last.fetch('header').include?('普通窗口：1 个') && !menus.last.fetch('header').include?('当前没有可录窗口') && data_rows.call(menus.last).length == 1, '重新加载从零到一时当前 header 清除空态')
assert.call(events.grep(/^OUTSIDE_MENU:/).empty? && events.grep(/^FORBIDDEN_MENU/).empty?, '空态不输出框外历史日志，重载和取消均不进入业务')
events = pty_case.call('pty-menu-scope-no-auxiliary', [['范围：浏览器 | 普通窗口：1 个', "切换浏览器\r"], ['范围：全部应用 | 普通窗口：2 个', "\e[D"]], menu_base + menu_end)
menus = snapshots.call(events)
assert.call(menus.length == 2 && events.grep(/^ENGINE:/) == ['ENGINE:list --browsers', 'ENGINE:list'] && menus.last.fetch('header').include?('范围：全部应用 | 普通窗口：2 个'), '切换范围只改变浏览器或全部应用，不隐式包含辅助候选')
assert.call(menus.all? { |menu| menu.fetch('rows').none? { |line| line.start_with?('@aux') } } && events.include?('RESULT:20'), '范围切换后无辅助开关且保持返回语义')

# 范围开关独立透传；非交互列窗不应附带未授权的辅助范围。
scope_base = <<~'ZSH'
  ENGINE="$SCOPE_ENGINE"
  ensure_recording_permission() { return 0; }
ZSH
_, _, status, events = run_shell.call('list-auxiliary', scope_base + "MODE=list\nINCLUDE_AUXILIARY=1\nrun_business\n")
assert.call(status == 0 && events.include?('ENGINE:list --browsers --include-auxiliary'), 'list 显式包含辅助窗口')
_, _, status, events = run_shell.call('list-all-normal', scope_base + "MODE=list\nALL_WINDOWS=1\nrun_business\n")
assert.call(status == 0 && events.include?('ENGINE:list') && events.grep(/--include-auxiliary/).empty?, '--all 不隐式包含辅助窗口')
_, _, status, events = run_shell.call('resolve-auxiliary', scope_base + <<~'ZSH')
  MODE=interactive
  WINDOW_ID=12
  YES=1
  INCLUDE_AUXILIARY=1
  record_target() { print -r -- "TARGET:$TARGET" >> "$TRACE"; }
  run_business
ZSH
assert.call(status == 0 && events.include?('ENGINE:resolve --window-id 12 --include-auxiliary') && events.include?('TARGET:token-resolved'), '显式 ID 解析透传辅助范围并保留身份 token')

# 目录输入使用真实词法解析，桌面解析与 Finder 打开均替换为本轮假边界。
desktop = File.join(root, '系统 桌面')
custom_directory = File.join(root, '中文 空格目录')
FileUtils.mkdir_p([desktop, custom_directory])
desktop = File.realpath(desktop)
custom_directory = File.realpath(custom_directory)
ENV['TEST_DESKTOP'] = desktop
ENV['TEST_OUTPUT_DIRECTORY'] = custom_directory
['原始路径', '拖入转义', '整体引号'].zip([custom_directory, Shellwords.escape(custom_directory), "\"#{custom_directory}\""]).each do |label, input|
  output, error, status, _ = run_shell.call("directory-#{label}", "normalize_output_directory #{Shellwords.escape(input)}\nresult=$?\nprint -r -- \"$REPLY\"\nexit \"$result\"\n")
  assert.call(status == 0 && output.strip == custom_directory, "中文空格目录解析：#{label} #{error}")
end
marker = File.join(root, 'FORBIDDEN_EVALUATION')
_, _, status, _ = run_shell.call('directory-no-eval', "normalize_output_directory #{Shellwords.escape("$(touch #{marker})")}\n")
assert.call(status != 0 && !File.exist?(marker), '输入路径不得执行命令替换')
output, _, status, _ = run_shell.call('desktop-resolver', <<~'ZSH')
  function /usr/bin/osascript() { print -r -- "$TEST_DESKTOP/"; }
  resolve_desktop_directory
  print -r -- "$REPLY"
ZSH
assert.call(status == 0 && output.strip == desktop, '默认系统桌面按只读系统路径解析')
folder = File.join(root, 'non-tty-needs-output')
FileUtils.mkdir_p(folder)
_, error, status = Open3.capture3({'NO_COLOR'=>'1', 'TERM'=>'dumb', 'TMPDIR'=>folder, 'XDG_CACHE_HOME'=>File.join(folder, 'cache')}, '/bin/zsh', production, '--window-id', '12', '--yes')
assert.call(status.exitstatus == 64 && error.include?('--output') && Dir.children(folder).empty?, '非交互未给输出地址须在准备前停止')

writer = File.join(root, 'fake-writer.rb')
File.write(writer, <<~'RUBY_WRITER')
  #!/usr/bin/ruby
  arguments = ARGV
  output_index = arguments.index('--output')
  abort 'missing fake output' unless output_index
  destination = arguments[output_index + 1]
  mode = ENV.fetch('WRITER_MODE', 'success')
  trace = ENV.fetch('TRACE')
  File.open(trace, 'a') { |file| file.puts("WRITER:#{mode}:#{destination}") }
  finish = lambda do
    if mode == 'sigint-fail'
      File.open(trace, 'a') { |file| file.puts('WRITER_EXIT:9') }
      exit 9
    end
    File.write(destination, 'isolated fake final file') unless mode == 'missing'
    File.open(trace, 'a') { |file| file.puts('WRITER_EXIT:0') }
    exit 0
  end
  exit 9 if mode == 'fail'
  if mode.start_with?('sigint-')
    Signal.trap('INT') { finish.call }
    puts 'FAKE_RECORDING_READY'
    STDOUT.flush
    loop { sleep 0.02 }
  end
  finish.call
RUBY_WRITER
FileUtils.chmod(0755, writer)
ENV['FAKE_WRITER'] = writer
recording_base = <<~'ZSH'
  RUN_DIR="${TRACE:h}"
  LOG_FILE="$RUN_DIR/record.log"
  : > "$LOG_FILE"
  ENGINE="$FAKE_WRITER"
  FZF_BIN="$REAL_FZF"
  TARGET=token-alpha
  function /usr/bin/osascript() { print -r -- "$TEST_DESKTOP/"; }
  function /usr/bin/open() { print -r -- "OPEN:$*" >> "$TRACE"; }
  functions -c offer_open_output_directory original_offer_open_output_directory
  offer_open_output_directory() {
    print POST_HOOK >> "$TRACE"
    original_offer_open_output_directory
  }
  trap 'handle_signal INT 130' INT
  trap 'handle_signal TERM 143' TERM
  trap 'handle_signal HUP 129' HUP
ZSH
recording_end = <<~'ZSH'
  record_target
  result=$?
  print -r -- "RESULT:$result" >> "$TRACE"
  print -r -- "FINAL:$OUTPUT" >> "$TRACE"
  exit "$result"
ZSH
non_tty_path = File.join(custom_directory, '显式 非交互.mp4')
output, _, status, events = run_shell.call('non-tty-explicit-output', recording_base + "OUTPUT=#{Shellwords.escape(non_tty_path)}\nexport WRITER_MODE=success\n" + recording_end)
assert.call(status == 0 && File.file?(non_tty_path) && events.grep(/^OPEN:/).empty? && !output.include?('保存目录 >'), '非交互显式输出正常保存且不问地址、不打开目录')
failure_path = File.join(custom_directory, '失败.mp4')
_, _, status, events = run_shell.call('recording-failure-no-question', recording_base + "OUTPUT=#{Shellwords.escape(failure_path)}\nexport WRITER_MODE=fail\n" + recording_end)
assert.call(status == 9 && !File.exist?(failure_path) && !events.include?('POST_HOOK'), '录制失败不询问目录')
missing_path = File.join(custom_directory, '无最终输出.mp4')
_, _, status, events = run_shell.call('recording-missing-no-question', recording_base + "OUTPUT=#{Shellwords.escape(missing_path)}\nexport WRITER_MODE=missing\n" + recording_end)
assert.call(status != 0 && !events.include?('POST_HOOK'), '内核返回成功但无最终输出时不询问目录')
events = pty_case.call('pty-default-desktop', [['保存目录 >', "\r"], ['录制完成 >', "\r"]], recording_base + "export WRITER_MODE=success\n" + recording_end)
final = events.grep(/^FINAL:/).last.to_s.sub(/^FINAL:/, '')
assert.call(File.dirname(final) == desktop && File.file?(final) && events.include?('RESULT:0') && events.grep(/^OPEN:/).empty?, '默认桌面保存、默认不打开目录')
events = pty_case.call('pty-drag-directory-and-open', [['保存目录 >', "#{Shellwords.escape(custom_directory)}\r"], ['录制完成 >', "打开录制文件所在目录\r"]], recording_base + "export WRITER_MODE=success\n" + recording_end)
assert.call(events.grep(/^OPEN:/) == ["OPEN:#{custom_directory}"] && events.include?('RESULT:0'), '中文空格目录拖入后只打开所在目录一次')
events = pty_case.call('pty-invalid-directory-retry', [['保存目录 >', "/不存在的录屏目录\r"], ['保存目录 >', "#{Shellwords.escape(custom_directory)}\r"], ['录制完成 >', "\r"]], recording_base + "export WRITER_MODE=success\n" + recording_end)
assert.call(events.grep(/^WRITER:/).length == 1 && events.include?('RESULT:0'), '无效保存目录持续重问，有效后才调用录制')
events = pty_case.call('pty-directory-eof', [['保存目录 >', "\x04"]], recording_base + recording_end)
assert.call(events.include?('RESULT:130') && events.grep(/^WRITER:/).empty? && !events.include?('POST_HOOK'), '保存地址 EOF 取消且不录制')
signal_success_path = File.join(custom_directory, 'INT 成功.mp4')
events = pty_case.call('pty-int-success-question', [['FAKE_RECORDING_READY', "\x03"], ['录制完成 >', "打开录制文件所在目录\r"]], recording_base + "OUTPUT=#{Shellwords.escape(signal_success_path)}\nexport WRITER_MODE=sigint-success\n" + recording_end)
assert.call(events.include?('WRITER_EXIT:0') && events.include?('RESULT:0') && events.count('POST_HOOK') == 1 && events.grep(/^OPEN:/) == ["OPEN:#{custom_directory}"], 'INT 正常保存后继续询问目录且保留真实成功退出码')
signal_failure_path = File.join(custom_directory, 'INT 失败.mp4')
events = pty_case.call('pty-int-failure-no-question', [['FAKE_RECORDING_READY', "\x03"]], recording_base + "OUTPUT=#{Shellwords.escape(signal_failure_path)}\nexport WRITER_MODE=sigint-fail\n" + recording_end)
assert.call(events.include?('RESULT:9') && !events.include?('POST_HOOK') && events.grep(/^OPEN:/).empty?, 'INT 后原生失败仍返回失败，不询问或打开目录')
puts "PASS: #{count} assertions（参数、无写入帮助、依赖闭环与真实 PTY/fzf）"
puts "隔离夹具：#{root}"
RUBY
}
# 编排测试说明、运行时体检及隔离回归。
main() {
  show_test_intro "$@" # 展示测试隔离范围并确认本轮运行。
  initialize_test_paths # 从测试文件实际位置定位生产入口。
  check_test_environment # 检查系统 Ruby/zsh 和已有 fzf，不安装依赖。
  run_isolated_tests # 验证参数、依赖门禁及真实键盘返回行为。
}

main "$@"
