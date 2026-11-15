#!/bin/zsh
# 脚本自述：
# - 脚本名称：trs.command
# - 核心用途：执行“trs”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

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



# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
jobs_prompt_color_ready() {
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" '
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
    function segment(value, inherited, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
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
          return segment(left, 0) connector segment(right, 31)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31) "或" segment(substr(value, splitAt + length("或")), 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!kind || !color) return value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original) {
      original = value
      gsub(esc "\\[[0-9;]*m", "", value)
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return original
      output = ""
      inherited = 0
      depth = 0
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited) boundary
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
      return output segment(value, inherited)
    }
    BEGIN { esc = sprintf("%c", 27); first = 1 }
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
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0
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
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
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
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
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
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
APP_HOME="${HOME}/.local/share/jobs-translator"
BIN_HOME="${HOME}/.local/bin"
TRANSLATE_REPO="${APP_HOME}/translate-cli"
TRANSLATE_GIT_URL="https://github.com/scriptingosx/translate-cli.git"
CONFIG_FILE="${APP_HOME}/config.zsh"
CHINESE_CODE="zh-Hans"
DEFAULT_OTHER_CODE="en-US"
DEFAULT_OTHER_NAME="英语（美国）"
DEFAULT_DIRECTION="to_zh"
CURRENT_OTHER_CODE="${DEFAULT_OTHER_CODE}"
CURRENT_OTHER_NAME="${DEFAULT_OTHER_NAME}"
CURRENT_DIRECTION="${DEFAULT_DIRECTION}"
TRANSLATE_BIN=""
LAST_TRANSLATE_OUTPUT=""
LAST_TRANSLATE_FROM=""
LAST_TRANSLATE_TO=""
LAST_TRANSLATE_ERROR_KIND=""

COLOR_RESET="\033[0m"
COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_CYAN="\033[36m"
COLOR_BOLD="\033[1m"
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log_info() { printf "%b\n" "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log_ok() { printf "%b\n" "${COLOR_GREEN}[OK]${COLOR_RESET} $*"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log_warn() { printf "%b\n" "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log_error() { printf "%b\n" "${COLOR_RED}[ERROR]${COLOR_RESET} $*"; }
# 封装 pause 对应的独立处理逻辑。
pause() {
  jobs_prompt_output printf "%b" "${COLOR_CYAN}按回车继续...${COLOR_RESET}"
  read -r _
}
# 收集并校验用户输入，决定后续执行路径。
prompt_required_run() {
  local message="$1"
  jobs_prompt_output printf "%b" "${COLOR_YELLOW}${message}${COLOR_RESET}\n按回车跳过；输入任意字符后回车执行；输入 q 后回车退出翻译："
  local answer=""
  IFS= read -r answer
  [[ -n "${answer}" && "${answer:l}" != "q" ]]
}
# 封装 command_exists 对应的独立处理逻辑。
command_exists() {
  command -v "$1" >/dev/null 2>&1
}
# 封装 version_major 对应的独立处理逻辑。
version_major() {
  local version="$1"
  printf "%s" "${version%%.*}"
}
# 检查当前运行条件是否满足后续流程要求。
check_macos_version() {
  local version=""
  version="$(sw_vers -productVersion 2>/dev/null || true)"
  if [[ -z "${version}" ]]; then
    log_warn "无法读取 macOS 版本，继续尝试运行"
    return 0
  fi

  local major="$(version_major "${version}")"
  if [[ ! "${major}" =~ '^[0-9]+$' ]]; then
    log_warn "无法解析 macOS 主版本号：${version}，继续尝试运行"
    return 0
  fi

  if [[ "${major}" -lt 26 ]]; then
    log_warn "当前 macOS 版本：${version}"
    log_warn "当前使用的 macOS 原生翻译 CLI 方案要求 macOS 26.0 或更高版本。"
    log_warn "如果你已经有可用的 translate 命令，脚本仍会尝试调用；否则无法保证可用。"
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_homebrew() {
  if JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_activate || return 1
    return 0
  fi
  log_warn "未检测到健康 Homebrew。"
  if ! prompt_required_run "缺少 Homebrew，是否现在自动安装？"; then
    return 1
  fi
  jobs_brew_install_or_exit
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || return 1
  log_ok "Homebrew 安装完成"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_fzf() {
  if command_exists fzf; then
    return 0
  fi

  log_warn "未检测到 fzf。"
  if ! ensure_homebrew; then
    log_error "fzf 未安装，且 Homebrew 不可用。请先安装 fzf。"
    exit 1
  fi

  if prompt_required_run "缺少 fzf，是否现在通过 Homebrew 安装？"; then
    brew install fzf
  else
    log_error "fzf 是必需依赖，已退出。"
    exit 1
  fi

  if ! command_exists fzf; then
    log_error "fzf 安装后仍不可用，请检查 PATH。"
    exit 1
  fi
}
# 解析并返回后续流程需要的目标信息。
find_translate_bin() {
  local found=""
  found="$(command -v translate 2>/dev/null || true)"
  if [[ -n "${found}" ]]; then
    TRANSLATE_BIN="${found}"
    return 0
  fi

  if [[ -x "${BIN_HOME}/translate" ]]; then
    TRANSLATE_BIN="${BIN_HOME}/translate"
    return 0
  fi

  return 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_swift_toolchain() {
  if command_exists swift; then
    return 0
  fi

  log_error "未检测到 Swift 工具链。请先安装 Xcode 或 Command Line Tools。"
  log_info "可尝试执行：xcode-select --install"
  return 1
}
# 封装 build_translate_cli 对应的独立处理逻辑。
build_translate_cli() {
  ensure_swift_toolchain || return 1

  if ! command_exists git; then
    log_error "未检测到 git，无法拉取 translate-cli。"
    return 1
  fi

  mkdir -p "${APP_HOME}" "${BIN_HOME}"

  if [[ -d "${TRANSLATE_REPO}/.git" ]]; then
    log_info "更新 translate-cli：${TRANSLATE_REPO}"
    git -C "${TRANSLATE_REPO}" pull --ff-only
  else
    rm -rf "${TRANSLATE_REPO}"
    log_info "拉取 translate-cli：${TRANSLATE_GIT_URL}"
    git clone "${TRANSLATE_GIT_URL}" "${TRANSLATE_REPO}"
  fi

  log_info "构建 translate-cli"
  swift build --package-path "${TRANSLATE_REPO}" -c release

  local candidate_1="${TRANSLATE_REPO}/.build/release/translate"
  local candidate_2="${TRANSLATE_REPO}/.build/release/translate-cli"

  if [[ -x "${candidate_1}" ]]; then
    cp "${candidate_1}" "${BIN_HOME}/translate"
  elif [[ -x "${candidate_2}" ]]; then
    cp "${candidate_2}" "${BIN_HOME}/translate"
  else
    log_error "构建完成，但未找到 translate 可执行文件。"
    return 1
  fi

  chmod +x "${BIN_HOME}/translate"
  TRANSLATE_BIN="${BIN_HOME}/translate"
  log_ok "translate 已安装：${TRANSLATE_BIN}"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_translate_cli() {
  if find_translate_bin; then
    return 0
  fi

  log_warn "未检测到 translate 命令。"
  log_info "该命令用于调用 macOS 原生 Translation Service。"

  if prompt_required_run "缺少 translate，是否现在自动拉取并构建 scriptingosx/translate-cli？"; then
    build_translate_cli || {
      log_error "translate-cli 构建失败。"
      exit 1
    }
  else
    log_error "translate 是必需依赖，已退出。"
    exit 1
  fi
}
# 封装 load_config 对应的独立处理逻辑。
load_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}" || true
  fi

  if [[ -z "${CURRENT_OTHER_CODE:-}" ]]; then
    CURRENT_OTHER_CODE="${DEFAULT_OTHER_CODE}"
  fi

  if [[ -z "${CURRENT_OTHER_NAME:-}" ]]; then
    CURRENT_OTHER_NAME="${DEFAULT_OTHER_NAME}"
  fi

  case "${CURRENT_DIRECTION:-}" in
    "to_zh"|"from_zh")
      ;;
    *)
      CURRENT_DIRECTION="${DEFAULT_DIRECTION}"
      ;;
  esac
}
# 封装 save_config 对应的独立处理逻辑。
save_config() {
  mkdir -p "${APP_HOME}"
  {
    printf "CURRENT_OTHER_CODE='%s'\n" "${CURRENT_OTHER_CODE}"
    printf "CURRENT_OTHER_NAME='%s'\n" "${CURRENT_OTHER_NAME}"
    printf "CURRENT_DIRECTION='%s'\n" "${CURRENT_DIRECTION}"
  } > "${CONFIG_FILE}"
}
# 封装 print_header 对应的独立处理逻辑。
print_header() {
  clear || true
  printf "%b\n" "${COLOR_BOLD}Jobs Translator / trs${COLOR_RESET}"
  printf "%b\n" "macOS 原生翻译能力封装，不使用云 API Key。"
  printf "\n"
}
# 封装 language_rows 对应的独立处理逻辑。
language_rows() {
  cat <<'LANGS' | jobs_prompt_filter
English US｜英语（美国）｜en-US
English UK｜英语（英国）｜en-GB
Japanese｜日语｜ja
Korean｜韩语｜ko
French｜法语｜fr
German｜德语｜de
Spanish｜西班牙语｜es
Russian｜俄语｜ru
Italian｜意大利语｜it
Portuguese｜葡萄牙语｜pt
Vietnamese｜越南语｜vi
Thai｜泰语｜th
Arabic｜阿拉伯语｜ar
Indonesian｜印尼语｜id
Malay｜马来语｜ms
Hindi｜印地语｜hi
Dutch｜荷兰语｜nl
Turkish｜土耳其语｜tr
Polish｜波兰语｜pl
Swedish｜瑞典语｜sv
Ukrainian｜乌克兰语｜uk
LANGS
}
# 收集并校验用户输入，决定后续执行路径。
select_language() {
  ensure_fzf || return 1
  local selected="" picker_result=0
  selected="$(language_rows |
    FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --height=80% --border \
      --prompt='选择对方语言 > ' --no-multi --expect=left \
      --header='回车确认，← 返回设置，Esc 取消设置并返回翻译')" || picker_result=$?
  [[ "${selected%%$'\n'*}" == left ]] && return 10
  (( picker_result == 0 )) || return "$picker_result"
  [[ "$selected" == *$'\n'* ]] || return 130
  selected="${selected#*$'\n'}"
  [[ -n "$selected" ]] || return 130
  CURRENT_OTHER_NAME="$(printf "%s" "$selected" | awk -F '｜' '{print $2}')"
  CURRENT_OTHER_CODE="$(printf "%s" "$selected" | awk -F '｜' '{print $3}')"
  [[ -n "$CURRENT_OTHER_CODE" ]]
}
# 封装 show_help 对应的独立处理逻辑。
show_help() {
  cat <<EOF_HELP | jobs_prompt_filter

输入方式：

  直接输入原文 + 回车      立即翻译
  空格 + 回车              打开设置菜单
  Ctrl + C                 退出 trs

说明：

  在“原文 >”输入区，除“单个空格”以外，任何非空输入都会按原文翻译。
  例如 :help、:swap 这类字符串，也会被当作普通原文翻译，不再作为命令处理。
  退出翻译、切换方向、切换对方语言、打开 Translation Languages 设置，统一从设置菜单进入。

当前设计：

  中文固定为：${CHINESE_CODE}
  默认方向：对方语言 → 中文
  启动 trs 后直接进入翻译输入，不再先弹出语言选择菜单。
  进入“原文 >”输入前，会先检查当前语言对是否已准备好。
  真正输入原文后，回车就是翻译，不再弹出下一步菜单。

EOF_HELP
}
# 封装 source_lang 对应的独立处理逻辑。
source_lang() {
  if [[ "${CURRENT_DIRECTION}" == "to_zh" ]]; then
    printf "%s" "${CURRENT_OTHER_CODE}"
  else
    printf "%s" "${CHINESE_CODE}"
  fi
}
# 封装 target_lang 对应的独立处理逻辑。
target_lang() {
  if [[ "${CURRENT_DIRECTION}" == "to_zh" ]]; then
    printf "%s" "${CHINESE_CODE}"
  else
    printf "%s" "${CURRENT_OTHER_CODE}"
  fi
}
# 封装 direction_label 对应的独立处理逻辑。
direction_label() {
  if [[ "${CURRENT_DIRECTION}" == "to_zh" ]]; then
    printf "%s → 中文" "${CURRENT_OTHER_NAME}"
  else
    printf "中文 → %s" "${CURRENT_OTHER_NAME}"
  fi
}
# 封装 open_translation_settings 对应的独立处理逻辑。
open_translation_settings() {
  log_info "正在打开系统设置。"
  log_info "进入后找到：通用 → 语言与地区 → Translation Languages…"
  log_info "至少下载：${LAST_TRANSLATE_FROM:-当前源语言} 和 ${LAST_TRANSLATE_TO:-当前目标语言}。"

  open "x-apple.systempreferences:com.apple.Localization-Settings.extension" >/dev/null 2>&1 && return 0
  open -a "System Settings" >/dev/null 2>&1 && return 0
  open -a "System Preferences" >/dev/null 2>&1 && return 0

  log_warn "无法自动打开系统设置，请手动进入：系统设置 → 通用 → 语言与地区 → Translation Languages…"
}
# 封装 classify_translate_error 对应的独立处理逻辑。
classify_translate_error() {
  local output="$1"

  if [[ "${output}" == *"download the Translation resources"* || "${output}" == *"Translation resources"* || "${output}" == *"Unable to Translate"* ]]; then
    printf "resources"
    return 0
  fi

  printf "unknown"
}
# 封装 record_translate_error 对应的独立处理逻辑。
record_translate_error() {
  local output="$1"
  local from_code="$2"
  local to_code="$3"
  local kind="$(classify_translate_error "${output}")"

  LAST_TRANSLATE_OUTPUT="${output}"
  LAST_TRANSLATE_FROM="${from_code}"
  LAST_TRANSLATE_TO="${to_code}"
  LAST_TRANSLATE_ERROR_KIND="${kind}"
}
# 封装 print_translate_failure_hint 对应的独立处理逻辑。
print_translate_failure_hint() {
  local output="$1"
  local from_code="$2"
  local to_code="$3"

  record_translate_error "${output}" "${from_code}" "${to_code}"

  if [[ "${LAST_TRANSLATE_ERROR_KIND}" == "resources" ]]; then
    log_error "系统翻译资源未准备好，当前语言对还不能翻译。"
    log_warn "需要确认 / 下载的语言资源：${from_code}、${to_code}"
    log_warn "路径：系统设置 → 通用 → 语言与地区 → Translation Languages…"
    return 0
  fi

  log_error "翻译失败。"
  log_warn "源语言：${from_code}，目标语言：${to_code}"
  log_warn "translate 原始错误："
  printf "%s\n" "${output}"
}
# 封装 probe_text_for_source 对应的独立处理逻辑。
probe_text_for_source() {
  local from_code="$1"

  if [[ "${from_code}" == "${CHINESE_CODE}" ]]; then
    printf "你好"
  else
    printf "test"
  fi
}
# 封装 probe_language_pair 对应的独立处理逻辑。
probe_language_pair() {
  local from_code="$1"
  local to_code="$2"
  local probe_text="$(probe_text_for_source "${from_code}")"
  local output=""
  local translate_exit_code=0

  LAST_TRANSLATE_OUTPUT=""
  LAST_TRANSLATE_FROM="${from_code}"
  LAST_TRANSLATE_TO="${to_code}"
  LAST_TRANSLATE_ERROR_KIND=""

  output="$(printf "%s" "${probe_text}" | "${TRANSLATE_BIN}" --from "${from_code}" --to "${to_code}" 2>&1)" || translate_exit_code=$?

  if [[ "${translate_exit_code}" -ne 0 ]]; then
    record_translate_error "${output}" "${from_code}" "${to_code}"
    return "${translate_exit_code}"
  fi

  return 0
}
# 检查当前运行条件是否满足后续流程要求。
ensure_current_pair_ready() {
  local from_code=""
  local to_code=""
  local answer=""

  while true; do
    from_code="$(source_lang)"
    to_code="$(target_lang)"

    log_info "检测当前语言对：${from_code} → ${to_code}"
    if probe_language_pair "${from_code}" "${to_code}"; then
      log_ok "语言资源已就绪：${from_code} → ${to_code}"
      return 0
    fi

    print_translate_failure_hint "${LAST_TRANSLATE_OUTPUT}" "${from_code}" "${to_code}"
    printf "\n%b" "${COLOR_CYAN}还没进入原文输入；先把当前语言对准备好。${COLOR_RESET}\n"
    jobs_prompt_output printf "%b" "${COLOR_CYAN}按回车打开 Translation Languages 设置；输入一个空格后回车打开设置菜单；输入 q 后回车退出翻译：${COLOR_RESET}"
    IFS= read -r answer

    if [[ "${answer}" == " " ]]; then
      settings_menu
      continue
    fi

    if [[ "${answer:l}" == "q" ]]; then
      return 1
    fi

    open_translation_settings
    jobs_prompt_output printf "%b" "${COLOR_CYAN}下载完成后回到这里，按回车重新检测；输入 q 后回车退出翻译：${COLOR_RESET}"
    IFS= read -r answer

    if [[ "${answer:l}" == "q" ]]; then
      return 1
    fi
  done
}
# 封装 change_language_interactive 对应的独立处理逻辑。
change_language_interactive() {
  local picker_result=0
  select_language || picker_result=$?
  (( picker_result == 0 )) || return "$picker_result"
  CURRENT_DIRECTION="to_zh"
  save_config || return 1
  log_ok "当前语言：${CURRENT_OTHER_NAME} / ${CURRENT_OTHER_CODE}"
  log_ok "当前方向：$(direction_label)"
  ensure_current_pair_ready || return 1
}
# 封装 swap_direction 对应的独立处理逻辑。
swap_direction() {
  if [[ "${CURRENT_DIRECTION}" == "to_zh" ]]; then
    CURRENT_DIRECTION="from_zh"
  else
    CURRENT_DIRECTION="to_zh"
  fi

  save_config
  log_ok "已切换方向：$(direction_label)"
  ensure_current_pair_ready || exit 1
}
# 封装 translate_text 对应的独立处理逻辑。
translate_text() {
  local text="$1"
  local from_code="$(source_lang)"
  local to_code="$(target_lang)"
  local output=""
  local translate_exit_code=0

  LAST_TRANSLATE_OUTPUT=""
  LAST_TRANSLATE_FROM="${from_code}"
  LAST_TRANSLATE_TO="${to_code}"
  LAST_TRANSLATE_ERROR_KIND=""

  output="$(printf "%s" "${text}" | "${TRANSLATE_BIN}" --from "${from_code}" --to "${to_code}" 2>&1)" || translate_exit_code=$?

  if [[ "${translate_exit_code}" -ne 0 ]]; then
    print_translate_failure_hint "${output}" "${from_code}" "${to_code}"
    log_warn "本次不会弹出下一步菜单。输入一个空格后回车，可打开设置菜单。"
    return "${translate_exit_code}"
  fi

  printf "%b\n" "${COLOR_GREEN}译文：${COLOR_RESET}${output}"
}
# 封装 settings_menu 对应的独立处理逻辑。
settings_menu() {
  ensure_fzf || return 1
  local choice="" picker_result=0 menu_cursor=1
  while true; do
    picker_result=0
    choice="$(printf "%s\n" \
      "返回翻译" "切换方向" "切换对方语言" \
      "打开 Translation Languages 设置" "查看帮助" "退出翻译" |
      FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --height=60% --border \
        --prompt='设置 > ' --no-multi --expect=left --sync \
        --bind="start:pos($menu_cursor)" \
        --header='回车确认，← / Esc 返回翻译')" || picker_result=$?
    [[ "${choice%%$'\n'*}" == left ]] && return 0
    if (( picker_result == 130 )); then
      return 0
    elif (( picker_result != 0 )); then
      log_error "设置选择器失败（退出码 $picker_result）。"
      return "$picker_result"
    fi
    [[ "$choice" == *$'\n'* ]] || return 0
    choice="${choice#*$'\n'}"
    case "$choice" in
      "返回翻译"|'') return 0 ;;
      "切换方向") swap_direction; return $? ;;
      "切换对方语言")
        menu_cursor=3
        picker_result=0
        change_language_interactive || picker_result=$?
        if (( picker_result == 10 )); then
          continue
        elif (( picker_result == 130 )); then
          return 0
        fi
        return "$picker_result"
        ;;
      "打开 Translation Languages 设置")
        LAST_TRANSLATE_FROM="$(source_lang)"
        LAST_TRANSLATE_TO="$(target_lang)"
        open_translation_settings
        return $?
        ;;
      "查看帮助") show_help; pause; return 0 ;;
      "退出翻译") exit 0 ;;
      *) log_error "无效的设置选项。"; return 1 ;;
    esac
  done
}
# 封装 trim_text 对应的独立处理逻辑。
trim_text() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf "%s" "${value}"
}
# 封装 interactive_loop 对应的独立处理逻辑。
interactive_loop() {
  load_config
  print_header

  log_ok "当前语言：${CURRENT_OTHER_NAME} / ${CURRENT_OTHER_CODE}"
  log_ok "当前方向：$(direction_label)"
  printf "\n"
  show_help
  ensure_current_pair_ready || exit 1
  printf "\n"

  while true; do
    printf "%b" "${COLOR_CYAN}原文 [$(direction_label)] > ${COLOR_RESET}"
    local raw_text=""
    IFS= read -r raw_text || break

    if [[ "${raw_text}" == " " ]]; then
      settings_menu
      printf "\n"
      continue
    fi

    local text=""
    text="$(trim_text "${raw_text}")"
    [[ -z "${text}" ]] && continue


    translate_text "${text}" || true
    printf "\n"
  done

  log_ok "已退出翻译。"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：trs.command' | jobs_intro_style title
  print -r -- '核心用途：执行“trs”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  jobs_list_intro_read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  set -euo pipefail
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_script_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 检查当前环境与执行条件是否满足脚本要求。
  check_macos_version
  # 检查当前环境与执行条件是否满足脚本要求。
  ensure_translate_cli
  # 执行 interactive_loop 对应的独立业务步骤。
  interactive_loop
}

main "$@"
