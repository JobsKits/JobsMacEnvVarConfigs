#!/bin/zsh
# 脚本自述：
# - 脚本名称：update_audit_tests.zsh
# - 核心用途：隔离验证配置写入、Python 管理边界与退出清理。
# - 影响范围：仅使用私有临时文件和假命令，不更改 HOME 或真实用户配置。
# - 运行提示：自动运行，不联网、不升级；Ctrl+C 可取消。

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

AUDIT_SCRIPT_DIR="${${(%):-%x}:A:h}"
AUDIT_UPDATE_SCRIPT="${AUDIT_SCRIPT_DIR:h}/update.command"
AUDIT_ROOT=''
AUDIT_PASSED=0
AUDIT_FAILED=0

# 说明测试只模拟业务，不使用真实包管理器和用户配置。
show_audit_intro() {
  print -r -- '全脚本补充回归：配置、Python 与退出清理；仅私有夹具，不改 HOME、不联网、不升级。'
}
# 仅清理当前测试创建的目录。
cleanup_audit_tests() {
  if [[ -n "$AUDIT_ROOT" && -d "$AUDIT_ROOT" && "${AUDIT_ROOT:t}" == jobs-update-audit.* ]]; then
    /bin/rm -r -- "$AUDIT_ROOT"
  fi
}
# 创建隔离环境，并以只加载函数的接口取得被测代码。
initialize_audit_tests() {
  setopt NO_NOMATCH
  AUDIT_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-update-audit.XXXXXXXX")" || return 1
  /bin/mkdir -p "$AUDIT_ROOT/runtime" || return 1
  export TMPDIR="$AUDIT_ROOT/runtime" JOBS_MAC_ENV_SOURCE_MODE=1
  source "$AUDIT_UPDATE_SCRIPT" || return 1
}
# 重置计数与假命令数据，避免上一用例污染结果。
reset_audit_fixture() {
  LOG_FILE="$AUDIT_ROOT/audit.log"
  : > "$LOG_FILE"
  : > "$AUDIT_ROOT/calls"
  : > "$AUDIT_ROOT/lines"
  JOBS_UPDATE_FAILURE_COUNT=0
  JOBS_UPDATE_SKIP_COUNT=0
  JOBS_UPDATE_COMMAND_COUNT=0
  JOBS_UPDATE_FAILED_DESCRIPTIONS=()
  JOBS_UPDATE_COMMAND_OUTPUT_FILES=()
  JOBS_UPDATE_TRUST_MODE=0
  export AUDIT_MOCK_MANAGED_MARKER='' AUDIT_MOCK_PYTHON_PROBE_RESULT=0 AUDIT_MOCK_PIP_RESULT=0
  export AUDIT_MOCK_BREW_RESULT=0
}
# 不符时显示实际值，方便定位失败分支。
audit_assert_equal() {
  [[ "$1" == "$2" ]] && return 0
  print -u2 -r -- "期望 [$1]；实际 [$2]"
  return 1
}
# 确认命令调用与预期完全一致。
audit_assert_call() {
  /usr/bin/grep -Fxq -- "$1" "$AUDIT_ROOT/calls"
}
# 拒绝出现不应执行的命令。
audit_assert_no_call() {
  ! /usr/bin/grep -Fq -- "$1" "$AUDIT_ROOT/calls"
}
# 创建带空格路径的假 Homebrew，只允许 shellenv。
create_audit_brew() {
  AUDIT_BREW_BIN="$AUDIT_ROOT/brew path 中文/brew"
  /bin/mkdir -p "${AUDIT_BREW_BIN:h}" || return 1
  /bin/cat > "$AUDIT_BREW_BIN" <<'MOCK_BREW'
#!/bin/zsh
[[ "$*" == shellenv ]] || exit 98
(( ${AUDIT_MOCK_BREW_RESULT:-0} == 0 )) || exit "$AUDIT_MOCK_BREW_RESULT"
print -r -- 'export JOBS_AUDIT_SHELLENV=active'
MOCK_BREW
  /bin/chmod +x "$AUDIT_BREW_BIN"
}
# 截获配置写入目标，不接触真实 HOME 下的任何文件。
install_config_spies() {
  function append_comment_once() {
    print -r -- "comment|$2" >> "$AUDIT_ROOT/calls"
  }
  function append_once() {
    print -r -- "line|$2" >> "$AUDIT_ROOT/calls"
    print -r -- "$1" >> "$AUDIT_ROOT/lines"
  }
}
# 带空格的真实可执行文件路径必须生成可再次执行的 shellenv 行。
test_shellenv_quoted_path() {
  create_audit_brew || return 1
  install_config_spies
  setup_brew_shellenv "$AUDIT_BREW_BIN" || return 1
  audit_assert_equal active "${JOBS_AUDIT_SHELLENV:-}" || return 1
  local generated_line="$(/usr/bin/head -n 1 "$AUDIT_ROOT/lines")" observed=''
  observed="$(/bin/zsh -c 'eval "$1" || exit $?; print -r -- "${JOBS_AUDIT_SHELLENV:-}"' audit-shellenv "$generated_line")" || return 1
  audit_assert_equal active "$observed" || return 1
  audit_assert_call "comment|${HOME}/.zprofile" || return 1
  audit_assert_call "line|${HOME}/.zshrc"
}
# 实际写入路径被普通文件阻塞时，失败不能被配置成功日志覆盖。
test_shellenv_write_failure() {
  create_audit_brew || return 1
  functions[audit_real_append_comment_once]="${functions[append_comment_once]}"
  functions[audit_real_append_once]="${functions[append_once]}"
  print -r -- blocked > "$AUDIT_ROOT/not-a-directory"
  function append_comment_once() {
    audit_real_append_comment_once "$1" "$AUDIT_ROOT/not-a-directory/.zprofile"
  }
  function append_once() {
    audit_real_append_once "$1" "$AUDIT_ROOT/not-a-directory/.zprofile"
  }
  setup_brew_shellenv "$AUDIT_BREW_BIN"
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  ! /usr/bin/grep -Fq -- '已确认 Homebrew 环境变量配置' "$LOG_FILE"
}
# shellenv 命令失败时，不执行配置写入。
test_shellenv_activation_failure() {
  create_audit_brew || return 1
  install_config_spies
  export AUDIT_MOCK_BREW_RESULT=19
  setup_brew_shellenv "$AUDIT_BREW_BIN"
  audit_assert_equal 1 "$?" || return 1
  [[ ! -s "$AUDIT_ROOT/lines" ]] || return 1
  ! /usr/bin/grep -Fq -- '已确认 Homebrew 环境变量配置' "$LOG_FILE"
}
# 在指定的配置写入阶段返回失败，实际 HOME 保持只读。
install_failing_config_spies() {
  AUDIT_CONFIG_CALL_COUNT=0
  AUDIT_CONFIG_FAIL_AT="${1:-2}"
  function append_comment_once() {
    (( AUDIT_CONFIG_CALL_COUNT += 1 ))
    print -r -- "config|${AUDIT_CONFIG_CALL_COUNT}|$1" >> "$AUDIT_ROOT/calls"
    (( AUDIT_CONFIG_CALL_COUNT != AUDIT_CONFIG_FAIL_AT ))
  }
  function append_once() {
    (( AUDIT_CONFIG_CALL_COUNT += 1 ))
    print -r -- "config|${AUDIT_CONFIG_CALL_COUNT}|$1" >> "$AUDIT_ROOT/calls"
    (( AUDIT_CONFIG_CALL_COUNT != AUDIT_CONFIG_FAIL_AT ))
  }
}
# rbenv 数据写入失败须登记一次失败且不打印已确认。
test_rbenv_config_failure() {
  install_failing_config_spies 2
  ensure_rbenv_init
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  ! /usr/bin/grep -Fq -- '已确认 rbenv 初始化配置' "$LOG_FILE"
}
# jenv 中间步骤失败须停止后续写入。
test_jenv_config_failure() {
  install_failing_config_spies 2
  ensure_jenv_init
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 2 "$AUDIT_CONFIG_CALL_COUNT" || return 1
  audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  ! /usr/bin/grep -Fq -- '已确认 jenv 初始化配置' "$LOG_FILE"
}
# fzf 最后一步失败不能显示整个配置已完成。
test_fzf_config_failure() {
  /bin/mkdir -p "$AUDIT_ROOT/fzf" || return 1
  function jobs_update_has() { [[ "$1" == brew ]]; }
  function brew() { [[ "$*" == '--prefix fzf' ]] || return 99; print -r -- "$AUDIT_ROOT/fzf"; }
  install_failing_config_spies 3
  setup_fzf_shellenv
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  ! /usr/bin/grep -Fq -- '已确认 fzf shell 配置' "$LOG_FILE"
}
# fzf 位置探测失败时不能继续写 Shell 配置。
test_fzf_prefix_failure() {
  function jobs_update_has() { [[ "$1" == brew ]]; }
  function brew() { return 22; }
  install_failing_config_spies 99
  setup_fzf_shellenv
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 0 "$AUDIT_CONFIG_CALL_COUNT" && audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 读取现有内容失败不能误当作不存在并继续追加。
test_append_lookup_failure() {
  function grep() { return 2; }
  local target="$AUDIT_ROOT/lookup-failure-profile"
  append_once 'export mocked=1' "$target"
  audit_assert_equal 2 "$?" || return 1
  [[ ! -s "$target" ]] || return 1
  append_comment_once '# mock config' "$target"
  audit_assert_equal 2 "$?" && [[ ! -s "$target" ]]
}
# 创建目录失败时保留非零结果，不触碰其它目标。
test_append_mkdir_failure() {
  local blocker="$AUDIT_ROOT/append-blocker"
  print -r -- blocked > "$blocker"
  append_once 'export mocked=1' "$blocker/profile"
  local line_result=$?
  append_comment_once '# mock' "$blocker/profile"
  local comment_result=$?
  (( line_result != 0 && comment_result != 0 ))
}
# touch 失败应停止，不尝试读取或写入配置。
test_append_touch_failure() {
  function touch() { return 75; }
  append_once 'export mocked=1' "$AUDIT_ROOT/touch-failure-profile"
  audit_assert_equal 75 "$?" || return 1
  append_comment_once '# mock' "$AUDIT_ROOT/touch-failure-profile"
  audit_assert_equal 75 "$?"
}
# 实际写入返回失败时，两个追加函数都必须保留其状态。
test_append_print_failure() {
  function print() { return 71; }
  append_once 'export mocked=1' "$AUDIT_ROOT/print-failure-profile"
  audit_assert_equal 71 "$?" || return 1
  append_comment_once '# mock' "$AUDIT_ROOT/print-failure-profile"
  audit_assert_equal 71 "$?"
}
# 初始化配置失败不能被后面的成功检查覆盖 Ruby 项结果。
test_ruby_config_failure_propagates() {
  install_failing_config_spies 2
  function jobs_update_has() { [[ "$1" == rbenv ]]; }
  function rbenv() { [[ "$*" == rehash ]]; }
  function jobs_update_repair_gem_extensions() { return 0; }
  jobs_update_ruby_base
  audit_assert_equal 1 "$?" || return 1
  audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  ! /usr/bin/grep -Fq -- '已确认 rbenv 初始化配置' "$LOG_FILE"
}
# 查找必须委托健康发现器，不能退回只检查路径存在。
test_find_brew_uses_health_success() {
  function jobs_brew_find() {
    print -r -- health-check >> "$AUDIT_ROOT/calls"
    print -r -- "$AUDIT_ROOT/verified-brew"
  }
  local candidate=''
  candidate="$(find_brew_bin)" || return 1
  audit_assert_equal "$AUDIT_ROOT/verified-brew" "$candidate" && audit_assert_call health-check
}
# 健康发现失败时不调用宿主其它 Homebrew。
test_find_brew_health_failure() {
  function jobs_brew_find() {
    print -r -- health-rejected >> "$AUDIT_ROOT/calls"
    return 7
  }
  local candidate=''
  candidate="$(find_brew_bin)"
  audit_assert_equal 7 "$?" || return 1
  [[ -z "$candidate" ]] && audit_assert_call health-rejected
}
# 创建只接受只读探测、版本检查或指定 pip 升级的假 Python。
install_python_mocks() {
  JOBS_PYTHON_BIN="$AUDIT_ROOT/mock-python"
  export AUDIT_CALLS_FILE="$AUDIT_ROOT/calls"
  /bin/cat > "$JOBS_PYTHON_BIN" <<'MOCK_PYTHON'
#!/bin/zsh
print -r -- "python|${(j: :)@}" >> "$AUDIT_CALLS_FILE"
if [[ "$1" == -c ]]; then
  (( ${AUDIT_MOCK_PYTHON_PROBE_RESULT:-0} == 0 )) || exit "$AUDIT_MOCK_PYTHON_PROBE_RESULT"
  print -r -- "${AUDIT_MOCK_MANAGED_MARKER:-}"
elif [[ "$*" == '-m pip --version' ]]; then
  print -r -- 'pip 26.0 from mock'
  exit "${AUDIT_MOCK_PIP_RESULT:-0}"
elif [[ "$*" == '-m pip install --upgrade pip' ]]; then
  print -r -- 'Successfully installed mock pip'
  exit "${AUDIT_MOCK_PIP_RESULT:-0}"
else
  exit 98
fi
MOCK_PYTHON
  /bin/chmod +x "$JOBS_PYTHON_BIN" || return 1
  function jobs_envupdate_python_preflight() {
    print -r -- "preflight|$1|${_JOBS_PYTHON_CONFIRMED_PROCESS:-}" >> "$AUDIT_ROOT/calls"
  }
  function jobs_update_has() { return 1; }
}
# 全量升级明确授权 Python 维护，pip 仍遵守包管理器的归属。
test_python_trust_unattended() {
  install_python_mocks || return 1
  local _JOBS_PYTHON_CONFIRMED_PROCESS=old-authorization
  JOBS_UPDATE_TRUST_MODE=1
  export AUDIT_MOCK_MANAGED_MARKER='/mock/stdlib/EXTERNALLY-MANAGED'
  jobs_update_python_base </dev/null || return 1
  audit_assert_call 'preflight|unattended|old-authorization' || return 1
  audit_assert_call 'python|-m pip --version' && audit_assert_no_call 'pip install'
}
# -t 是当前入口的明确授权，必要动作不得再次 read；普通后台仍无授权。
test_python_unattended_authorization() {
  local DRY_RUN=0
  JOBS_UPDATE_TRUST_MODE=0
  _jobs_python_has_authorization </dev/null && return 1
  JOBS_UPDATE_TRUST_MODE=1
  _jobs_python_has_authorization </dev/null || return 1
  function read() { print -r -- unexpected-read >> "$AUDIT_ROOT/calls"; return 99; }
  _jobs_python_confirm_required '修复 Python 依赖' </dev/null || return 1
  audit_assert_no_call unexpected-read || return 1
  local _JOBS_PYTHON_READONLY=1
  _jobs_python_has_authorization && return 1
  _JOBS_PYTHON_READONLY=0
  DRY_RUN=1
  ! _jobs_python_has_authorization
}
# 缺失的业务 Python 只准备一次并复检，失败不得进入后续业务或循环重装。
test_python_unattended_repair() {
  JOBS_UPDATE_TRUST_MODE=1
  JOBS_HOMEBREW_BIN=/mock/brew
  local probe_count=0
  function _jobs_python_prepare_brew() { return 0; }
  function _jobs_python_find_formula_python() {
    (( probe_count += 1 ))
    (( probe_count > 1 ))
  }
  function _jobs_python_confirm_required() {
    _jobs_python_has_authorization
  }
  function jobs_update_run_brew_adaptive_cmd() {
    print -r -- "repair|$*" >> "$AUDIT_ROOT/calls"
  }
  function jobs_brew_activate() { return 0; }
  function read() { return 99; }
  jobs_python_ensure 3.11 python@3.13 </dev/null || return 1
  audit_assert_equal 2 "$probe_count" || return 1
  audit_assert_call 'repair|准备 Python：brew install python@3.13 plain /mock/brew install python@3.13'
}
# 已管理 Python 仅检查 pip 版本，不绕过 EXTERNALLY-MANAGED。
test_python_managed_no_install() {
  install_python_mocks || return 1
  export AUDIT_MOCK_MANAGED_MARKER='/mock/stdlib/EXTERNALLY-MANAGED'
  jobs_update_python_base </dev/null || return 1
  audit_assert_call 'preflight|confirmed|' || return 1
  audit_assert_call 'python|-m pip --version' && audit_assert_no_call 'pip install'
}
# 非外部管理 Python 保留普通 pip 自升级能力。
test_python_unmanaged_upgrade() {
  install_python_mocks || return 1
  jobs_update_python_base </dev/null || return 1
  audit_assert_call 'preflight|confirmed|' || return 1
  audit_assert_call 'python|-m pip install --upgrade pip' && audit_assert_no_call 'pip --version'
}
# 探测管理标记失败时停止，不能猜测为可写环境。
test_python_marker_probe_failure() {
  install_python_mocks || return 1
  export AUDIT_MOCK_PYTHON_PROBE_RESULT=13
  jobs_update_python_base </dev/null
  audit_assert_equal 1 "$?" || return 1
  audit_assert_no_call 'python|-m pip'
}
# pip 业务失败须保持非零结果和失败计数。
test_python_pip_failure() {
  install_python_mocks || return 1
  export AUDIT_MOCK_PIP_RESULT=21
  jobs_update_python_base </dev/null
  audit_assert_equal 21 "$?" && audit_assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 只读环境准备未通过时不进入 pip 维护。
test_python_preflight_failure() {
  install_python_mocks || return 1
  function jobs_envupdate_python_preflight() {
    print -r -- "preflight|$1" >> "$AUDIT_ROOT/calls"
    return 1
  }
  JOBS_UPDATE_TRUST_MODE=1
  jobs_update_python_base </dev/null
  audit_assert_equal 1 "$?" || return 1
  audit_assert_no_call python
}
# 在 source 模式调用主流程时保留宿主已有信号处理。
test_source_preserves_signal_trap() {
  function jobs_update_show_readme_and_wait() { return 0; }
  function update() { return 0; }
  trap 'print -r -- host-term > "$AUDIT_ROOT/host-term"' TERM
  local trap_before="$(trap -p TERM)" trap_after=''
  jobs_update_main || return 1
  trap_after="$(trap -p TERM)"
  audit_assert_equal "$trap_before" "$trap_after"
}
# 通过真实 TERM 检查独立主流程退出143，并只回收登记的私有文件。
test_term_cleanup() {
  local signal_dir="$AUDIT_ROOT/signal" child_pid=0 result=0 attempt=0
  /bin/mkdir -p "$signal_dir" || return 1
  print -r -- keep > "$signal_dir/unrelated"
  /bin/cat > "$signal_dir/runner.zsh" <<'SIGNAL_RUNNER'
#!/bin/zsh
export JOBS_MAC_ENV_SOURCE_MODE=1
source "$1" || exit 96
unset JOBS_MAC_ENV_SOURCE_MODE
LOG_FILE="$AUDIT_SIGNAL_DIR/run.log"
function jobs_update_show_readme_and_wait() { return 0; }
function update() {
  local pending="$AUDIT_SIGNAL_DIR/jobs-update-command.pending"
  print -r -- pending > "$pending"
  print -r -- pending > "${pending}.status"
  JOBS_UPDATE_COMMAND_OUTPUT_FILES+=("$pending")
  print -r -- ready > "$AUDIT_SIGNAL_DIR/ready"
  while true; do
    /bin/sleep 0.02
  done
}
jobs_update_main
SIGNAL_RUNNER
  AUDIT_SIGNAL_DIR="$signal_dir" /bin/zsh "$signal_dir/runner.zsh" "$AUDIT_UPDATE_SCRIPT" > "$signal_dir/stdout" 2>&1 &
  child_pid=$!
  for attempt in {1..500}; do
    [[ -f "$signal_dir/ready" ]] && break
    kill -0 "$child_pid" 2>/dev/null || break
    /bin/sleep 0.02
  done
  if [[ ! -f "$signal_dir/ready" ]]; then
    kill -TERM "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    /bin/cat "$signal_dir/stdout" >&2
    return 1
  fi
  kill -TERM "$child_pid" || return 1
  wait "$child_pid"
  result=$?
  audit_assert_equal 143 "$result" || return 1
  [[ ! -e "$signal_dir/jobs-update-command.pending" && ! -e "$signal_dir/jobs-update-command.pending.status" ]] || return 1
  audit_assert_equal keep "$(<"$signal_dir/unrelated")"
}
# 隔离执行每一项，避免假函数、trap 与变量泄漏。
run_audit_case() {
  local title="$1" test_function="$2"
  if ( reset_audit_fixture; "$test_function" ) > "$AUDIT_ROOT/case.out" 2>&1; then
    (( AUDIT_PASSED += 1 ))
    print -r -- "PASS ${title}"
  else
    (( AUDIT_FAILED += 1 ))
    print -r -- "FAIL ${title}"
    /bin/cat "$AUDIT_ROOT/case.out"
  fi
}
# 执行补充验证并将失败传给调用方。
run_audit_tests() {
  run_audit_case 'shellenv空格路径可执行' test_shellenv_quoted_path
  run_audit_case '配置写入失败不报成功' test_shellenv_write_failure
  run_audit_case 'shellenv激活失败停止写入' test_shellenv_activation_failure
  run_audit_case 'rbenv配置失败不报成功' test_rbenv_config_failure
  run_audit_case 'jenv配置中途失败停止' test_jenv_config_failure
  run_audit_case 'fzf配置末步失败不报成功' test_fzf_config_failure
  run_audit_case 'fzf路径探测失败停止' test_fzf_prefix_failure
  run_audit_case '配置读取grep失败传播' test_append_lookup_failure
  run_audit_case '配置mkdir失败传播' test_append_mkdir_failure
  run_audit_case '配置touch失败传播' test_append_touch_failure
  run_audit_case '配置print失败传播' test_append_print_failure
  run_audit_case 'Ruby配置失败保留结果' test_ruby_config_failure_propagates
  run_audit_case 'Brew健康发现成功' test_find_brew_uses_health_success
  run_audit_case 'Brew健康发现失败' test_find_brew_health_failure
  run_audit_case 'Python全量维护且遵守包管理边界' test_python_trust_unattended
  run_audit_case 'Python无人值守授权不再等待输入' test_python_unattended_authorization
  run_audit_case 'Python无人值守补依赖后复检' test_python_unattended_repair
  run_audit_case '外部管理pip仅检查版本' test_python_managed_no_install
  run_audit_case '普通Python自升级pip' test_python_unmanaged_upgrade
  run_audit_case 'Python管理标记探测失败' test_python_marker_probe_failure
  run_audit_case 'pip升级失败传播' test_python_pip_failure
  run_audit_case 'Python预检失败停止下游' test_python_preflight_failure
  run_audit_case 'source保留宿主信号处理' test_source_preserves_signal_trap
  run_audit_case 'TERM退出143并清理私有输出' test_term_cleanup
  print -r -- "结果：${AUDIT_PASSED} passed，${AUDIT_FAILED} failed"
  (( AUDIT_FAILED == 0 ))
}
# 只在主测试进程退出时回收夹具。
TRAPEXIT() {
  (( ZSH_SUBSHELL == 0 )) && cleanup_audit_tests
  return 0
}
# 编排说明、隔离环境与补充行为回归。
main() {
  show_audit_intro # 说明不修改真实用户环境。
  initialize_audit_tests # 加载函数并准备专属临时夹具。
  run_audit_tests # 验证配置、Python和信号处理边界。
}

main "$@"
