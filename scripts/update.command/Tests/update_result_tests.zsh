#!/bin/zsh
# 脚本自述：
# - 脚本名称：update_result_tests.zsh
# - 核心用途：隔离验证更新结果、第三方零退出码误报与 Git 远端复检。
# - 影响范围：仅操作本测试的临时目录，包管理器与 Git 均使用假命令。
# - 运行提示：自动运行，不联网、不安装、不升级；Ctrl+C 可取消。

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
    # 只接受本次请求对应的 RGB 响应；非协议输入使本次探测失败。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || return 1
        jobs_style_reply=''
        for jobs_style_attempt in 1 2 3; do
            jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty)
            jobs_style_reply=$jobs_style_reply$jobs_style_piece
            case $jobs_style_reply in
                *"$jobs_style_bel"|*"$jobs_style_esc\\") break ;;
                '') ;;
                "$jobs_style_esc"*) ;;
                *) break ;;
            esac
        done
        case $jobs_style_reply in
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_bel")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_bel"}
                ;;
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_esc\\")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_esc\\"}
                ;;
            *) return 1 ;;
        esac
        jobs_style_normalized=$(printf '%s\n' "$jobs_style_rgb" | LC_ALL=C awk -F/ '
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    h = tolower($i)
                    if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) exit 1
                    n = 0
                    for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                    value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                }
                printf "%d/%d/%d", value[1], value[2], value[3]
            }
        ') || return 1
        [ -n "$jobs_style_normalized" ]
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
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key"; then
                            jobs_style_cleanup_ok=0
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
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || jobs_style_cleanup_ok=0
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
                printf '终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_recovery" >&2
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
    trap 'jobs_style_exit_status=129; exit 129' HUP
    trap 'jobs_style_exit_status=130; exit 130' INT
    trap 'jobs_style_exit_status=143; exit 143' TERM
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
        trap 'jobs_style_exit_status=129; exit 129' HUP
        trap 'jobs_style_exit_status=130; exit 130' INT
        trap 'jobs_style_exit_status=143; exit 143' TERM
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

TEST_SCRIPT_DIR="${${(%):-%x}:A:h}"
TEST_UPDATE_SCRIPT="${TEST_SCRIPT_DIR:h}/update.command"
TEST_ROOT=''
TEST_PASSED=0
TEST_FAILED=0

# 说明测试边界，避免把模拟结果当作真实升级验收。
show_test_intro() {
  print -r -- '更新结果隔离回归：假命令验证，不联网、不安装、不升级。Ctrl+C 可取消。'
}
# 只清理本测试创建的目录。
cleanup_tests() {
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" && "${TEST_ROOT:t}" == jobs-update-results.* ]]; then
    /bin/rm -r -- "$TEST_ROOT"
  fi
}
# 建立私有临时目录并以 source 模式加载被测函数。
initialize_tests() {
  setopt NO_NOMATCH
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-update-results.XXXXXXXX")" || return 1
  /bin/mkdir -p "$TEST_ROOT/runtime" || return 1
  export TMPDIR="$TEST_ROOT/runtime" JOBS_MAC_ENV_SOURCE_MODE=1
  source "$TEST_UPDATE_SCRIPT" || return 1
}
# 为每个用例重置计数、日志和返回值。
reset_fixture() {
  LOG_FILE="$TEST_ROOT/test.log"
  : > "$LOG_FILE"
  : > "$TEST_ROOT/calls"
  JOBS_UPDATE_FAILURE_COUNT=0
  JOBS_UPDATE_SKIP_COUNT=0
  JOBS_UPDATE_COMMAND_COUNT=0
  JOBS_UPDATE_FAILED_STEPS=0
  JOBS_UPDATE_PARTIAL_STEPS=0
  JOBS_UPDATE_SKIPPED_STEPS=0
  JOBS_UPDATE_SUCCEEDED_STEPS=0
  JOBS_UPDATE_FAILED_DESCRIPTIONS=()
  JOBS_UPDATE_TRUST_MODE=0
  MOCK_GIT_MODE=current
  MOCK_PULL_RESULT=0
  MOCK_TEE_DELAY=0
  export MOCK_OMZ_RESULT=0
}
# 值不符时显示实际结果。
assert_equal() {
  [[ "$1" == "$2" ]] && return 0
  print -u2 -r -- "期望 [$1]；实际 [$2]"
  return 1
}
# 从实际日志检查结果说明。
assert_log() {
  /usr/bin/grep -Fq -- "$1" "$LOG_FILE"
}
# 确认失败日志中没有成功标记。
assert_no_log() {
  ! /usr/bin/grep -Fq -- "$1" "$LOG_FILE"
}
# 用文件记录 Git 请求，不进入任何真实远端。
install_git_mock() {
  function git() {
    print -r -- "${(j:|:)@}" >> "$TEST_ROOT/calls"
    [[ "$1" == -C ]] && shift 2
    case "$1" in
      symbolic-ref) print -r -- main ;;
      config)
        case "$3" in
          branch.main.remote) print -r -- origin ;;
          branch.main.merge) print -r -- refs/heads/main ;;
          *) return 1 ;;
        esac
        ;;
      remote) print -r -- 'https://example.invalid/ohmyzsh/ohmyzsh.git' ;;
      ls-remote)
        case "$MOCK_GIT_MODE" in
          offline) return 128 ;;
          invalid) print -r -- '<html>HEAD</html>' ;;
          *) print -r -- $'1234567890123456789012345678901234567890\trefs/heads/main' ;;
        esac
        ;;
      merge-base) [[ "$MOCK_GIT_MODE" != stale ]] ;;
      rev-parse) print -r -- true ;;
      pull) return "$MOCK_PULL_RESULT" ;;
      *) print -u2 -r -- "不允许的假 Git 调用：$*"; return 99 ;;
    esac
  }
}
# 命令成功必须保持返回值和日志同步。
test_command_success() {
  jobs_update_run_cmd '正常命令' print -r -- 'version 1.0' || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  assert_log 'version 1.0' && assert_log '正常命令：完成'
}
# 非零返回不能被后续日志覆盖。
test_nonzero_result() {
  jobs_update_run_cmd '失败命令' /bin/zsh -c 'print detail; exit 28'
  local result=$?
  assert_equal 28 "$result" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  assert_log detail && assert_no_log '失败命令：完成'
}
# 第三方以零退出码输出 fatal 时仍须失败。
test_zero_with_error() {
  jobs_update_run_cmd '吞错命令' print -r -- 'fatal: unable to access remote'
  local result=$?
  assert_equal 1 "$result" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  assert_no_log '吞错命令：完成'
}
# 彩色失败文本也应被识别。
test_colored_failure() {
  jobs_update_run_cmd '彩色错误' print -r -- $'\033[31mERROR: permission denied\033[0m'
  assert_equal 1 "$?" && assert_no_log '彩色错误：完成'
}
# 普通说明中的 error 单词不能误报。
test_benign_error_word() {
  jobs_update_run_cmd '正常说明' print -r -- '0 errors; error handling improved' || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 输出消费者延迟时，判定必须等到输出已经落盘。
test_waits_for_output() {
  functions[test_real_log_stream]="${functions[jobs_update_log_stream]}"
  function jobs_update_log_stream() {
    /bin/sleep 0.05
    test_real_log_stream "$@"
  }
  jobs_update_run_cmd '延迟错误' print -r -- 'Error: failed download'
  assert_equal 1 "$?" && assert_log 'failed download'
}
# Shell 函数中的 PATH 或其它状态变更必须留在当前进程。
test_preserves_function_state() {
  local state_value=old
  function change_state() { state_value=new; print updated; }
  jobs_update_run_cmd '函数状态' change_state || return 1
  assert_equal new "$state_value"
}
# stdin 自动确认同样必须保留函数状态。
test_yes_preserves_state() {
  local state_value=old
  function accept_yes() {
    local answer=''
    IFS= read -r answer || return 1
    [[ "$answer" == y ]] || return 1
    state_value=new
  }
  jobs_update_run_cmd_with_yes '确认命令' accept_yes || return 1
  assert_equal new "$state_value"
}
# 日志无法落盘时不能确认执行完成。
test_log_write_failure() {
  LOG_FILE="$TEST_ROOT/missing-parent/log"
  jobs_update_run_cmd '日志失败' print -r -- result
  local result=$?
  (( result != 0 )) && assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 业务为了继续执行使用 || true 时，步骤仍须保留失败。
test_step_keeps_swallowed_failure() {
  function swallow_failure() {
    jobs_update_run_cmd '内层失败' /bin/zsh -c 'exit 7' || true
    print continued
  }
  jobs_update_run_step '外层更新' swallow_failure || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILED_STEPS" || return 1
  assert_no_log '外层更新：完成' && assert_log '外层更新：未完成'
}
# 没有命令包装器的业务函数返回失败也须进入汇总。
test_step_direct_failure() {
  jobs_update_run_step '直接失败' /bin/zsh -c 'exit 9' || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" && assert_equal 1 "$JOBS_UPDATE_FAILED_STEPS"
}
# 单纯跳过与部分执行应有不同结果。
test_step_skipped() {
  jobs_update_run_step '缺少工具' jobs_update_record_skip '工具缺失' || return 1
  assert_equal 1 "$JOBS_UPDATE_SKIPPED_STEPS" || return 1
  assert_no_log '缺少工具：完成'
}
# 完成部分命令后跳过后续项不算全部完成。
test_step_partial() {
  function partly_run() {
    jobs_update_run_cmd '子项成功' print result || return 1
    jobs_update_record_skip '缺少可选环境'
  }
  jobs_update_run_step '部分更新' partly_run || return 1
  assert_equal 1 "$JOBS_UPDATE_PARTIAL_STEPS" && assert_no_log '部分更新：完成'
}
# 无人值守没有授权时，明确记录未完成，绝不等待密码。
test_sudo_no_authorization() {
  function sudo() { print -r -- "$*" >> "$TEST_ROOT/calls"; print -u2 -r -- 'sudo: a password is required'; return 1; }
  JOBS_UPDATE_TRUST_MODE=1
  jobs_update_run_sudo_cmd '系统更新' forbidden-command
  assert_equal 1 "$?" || return 1
  assert_equal 0 "$JOBS_UPDATE_SKIP_COUNT" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" || return 1
  assert_equal 1 "$JOBS_UPDATE_COMMAND_COUNT" || return 1
  assert_equal '-n forbidden-command' "$(<"$TEST_ROOT/calls")"
}
# 授权通过后的业务失败不可误称为缺少权限。
test_sudo_command_failure() {
  function sudo() {
    return 23
  }
  JOBS_UPDATE_TRUST_MODE=1
  jobs_update_run_sudo_cmd '系统更新' forbidden-command
  assert_equal 23 "$?" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILURE_COUNT" && assert_equal 0 "$JOBS_UPDATE_SKIP_COUNT"
}
# 精确命令 NOPASSWD 可以成功，即使 sudo 验证策略不允许 -v。
test_sudo_exact_command_authorization() {
  function sudo() {
    print -r -- "$*" >> "$TEST_ROOT/calls"
    [[ "$*" == '-n permitted-command --specific' ]]
  }
  JOBS_UPDATE_TRUST_MODE=1
  jobs_update_run_sudo_cmd '指定授权命令' permitted-command --specific || return 1
  assert_equal '-n permitted-command --specific' "$(<"$TEST_ROOT/calls")" || return 1
  assert_equal 0 "$JOBS_UPDATE_SKIP_COUNT" && assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 为 Oh My Zsh 创建仅打印成功的本地假升级入口。
create_omz_fixture() {
  export ZSH="$TEST_ROOT/omz dir ' quoted"
  /bin/mkdir -p "$ZSH/tools" || return 1
  print -r -- 'print -r -- "Hooray! Oh My Zsh has been updated!"; exit "${MOCK_OMZ_RESULT:-0}"' > "$ZSH/tools/upgrade.sh"
  install_git_mock
}
# 上游静默吞错且网络不可达，必须拒绝更新成功。
test_omz_offline_after_success_text() {
  create_omz_fixture || return 1
  MOCK_GIT_MODE=offline
  jobs_update_run_step 'Oh My Zsh 更新' jobs_update_oh_my_zsh || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILED_STEPS" || return 1
  assert_no_log '更新并核验 Oh My Zsh：完成'
}
# 远端可达但本地仍落后时也不能成功。
test_omz_stale() {
  create_omz_fixture || return 1
  MOCK_GIT_MODE=stale
  jobs_update_oh_my_zsh
  assert_equal 1 "$?" && assert_no_log '更新并核验 Oh My Zsh：完成'
}
# 远端提交已包含在本地历史时允许完成。
test_omz_current() {
  create_omz_fixture || return 1
  jobs_update_oh_my_zsh || return 1
  assert_log '已核验远端 origin/main' && assert_log '更新并核验 Oh My Zsh：完成'
}
# 远端返回 HTML 等非 Git 数据时不接受为有效提交。
test_git_invalid_ref_output() {
  install_git_mock
  MOCK_GIT_MODE=invalid
  jobs_update_run_cmd 'Git 验证' jobs_update_verify_git_current "$TEST_ROOT" origin
  assert_equal 1 "$?" && assert_no_log 'Git 验证：完成'
}
# 新版 Dart 参数存在时使用全缓存模式。
test_dart_all_supported() {
  function dart() {
    print -r -- "$*" >> "$TEST_ROOT/calls"
    case "$*" in
      'pub cache repair --help') print -r -- '  --all Repair all cached packages.' ;;
      'pub cache repair --all'|'pub global list') return 0 ;;
      *) return 99 ;;
    esac
  }
  jobs_update_pub_cache || return 1
  /usr/bin/grep -Fxq -- 'pub cache repair --all' "$TEST_ROOT/calls"
}
# 旧版 Dart 不强塞其不存在的参数。
test_dart_legacy() {
  function dart() {
    case "$*" in
      'pub cache repair --help') print -r -- 'Repair cached packages.' ;;
      'pub cache repair'|'pub global list') return 0 ;;
      *) return 99 ;;
    esac
  }
  jobs_update_pub_cache || return 1
  assert_equal 0 "$JOBS_UPDATE_FAILURE_COUNT"
}
# 日志中的 No pubspec 零退出码不能再显示修复完成。
test_dart_no_pubspec() {
  function dart() {
    case "$*" in
      'pub cache repair --help') print -r -- 'Repair cached packages.' ;;
      'pub cache repair') print -r -- 'No pubspec.yaml found. Run from a Dart project or use --all to repair all cached packages.' ;;
      'pub global list') return 0 ;;
      *) return 99 ;;
    esac
  }
  jobs_update_pub_cache
  assert_equal 1 "$?" && assert_no_log 'Dart pub cache repair：完成'
}
# 只选择两个假业务步骤，核对失败后继续与最终退出码。
test_global_summary_failure() {
  function jobs_update_prompt_run() { [[ "$1" == *'Oh My Zsh'* || "$1" == *'Git LFS'* ]]; }
  function jobs_update_oh_my_zsh() { jobs_update_run_cmd '上游失败' print -r -- 'fatal: blocked' || true; }
  function jobs_update_git_lfs_init() { jobs_update_run_cmd '后续继续' print -r -- continued; }
  update
  assert_equal 1 "$?" || return 1
  assert_equal 1 "$JOBS_UPDATE_FAILED_STEPS" || return 1
  assert_log '后续继续：完成' && assert_log 'update 执行结束' && assert_no_log 'update 执行完成'
}
# 无失败但有明确跳过也须给调用方不完整状态。
test_global_summary_skip() {
  function jobs_update_prompt_run() { [[ "$1" == *'Oh My Zsh'* ]]; }
  function jobs_update_oh_my_zsh() { jobs_update_record_skip '尚未安装'; }
  update
  assert_equal 1 "$?" && assert_no_log 'update 执行完成'
}
# 成功结果及没有选择任何任务的结果均保持零退出码。
test_global_summary_success() {
  function jobs_update_prompt_run() { [[ "$1" == *'Oh My Zsh'* ]]; }
  function jobs_update_oh_my_zsh() { jobs_update_run_cmd '已验证' print current; }
  update || return 1
  assert_log 'update 执行完成，共完成 1 个更新项'
}
# 在独立子进程中运行用例，防止假函数泄漏到下一项。
run_case() {
  local title="$1" test_function="$2"
  if ( reset_fixture; "$test_function" ) > "$TEST_ROOT/case.out" 2>&1; then
    (( TEST_PASSED += 1 ))
    print -r -- "PASS ${title}"
  else
    (( TEST_FAILED += 1 ))
    print -r -- "FAIL ${title}"
    /bin/cat "$TEST_ROOT/case.out"
  fi
}
# 编排全部具有独立行为价值的回归分支。
run_tests() {
  run_case '正常命令与日志' test_command_success
  run_case '非零退出码' test_nonzero_result
  run_case '零退出码明确失败' test_zero_with_error
  run_case 'ANSI彩色错误' test_colored_failure
  run_case '普通error词汇' test_benign_error_word
  run_case '等待输出消费者完成' test_waits_for_output
  run_case '保留Shell函数状态' test_preserves_function_state
  run_case '确认输入保留Shell状态' test_yes_preserves_state
  run_case '日志记录失败' test_log_write_failure
  run_case '步骤保留被吞失败' test_step_keeps_swallowed_failure
  run_case '函数直接返回失败' test_step_direct_failure
  run_case '步骤明确跳过' test_step_skipped
  run_case '步骤部分执行' test_step_partial
  run_case 'sudo无授权' test_sudo_no_authorization
  run_case 'sudo业务失败' test_sudo_command_failure
  run_case 'sudo精确命令授权' test_sudo_exact_command_authorization
  run_case 'Oh My Zsh静默失败' test_omz_offline_after_success_text
  run_case 'Oh My Zsh落后远端' test_omz_stale
  run_case 'Oh My Zsh远端已核验' test_omz_current
  run_case 'Git异常响应' test_git_invalid_ref_output
  run_case 'Dart新版全缓存参数' test_dart_all_supported
  run_case 'Dart旧版兼容' test_dart_legacy
  run_case 'Dart No pubspec误报' test_dart_no_pubspec
  run_case '失败后继续与全局汇总' test_global_summary_failure
  run_case '跳过导致不完整结果' test_global_summary_skip
  run_case '全局成功结果' test_global_summary_success
  print -r -- "结果：${TEST_PASSED} passed，${TEST_FAILED} failed"
  (( TEST_FAILED == 0 ))
}
# 仅主测试进程退出时清理，函数返回和子进程退出不触碰共享夹具。
TRAPEXIT() {
  (( ZSH_SUBSHELL == 0 )) && cleanup_tests
  return 0
}
# 编排说明、隔离环境和行为回归。
main() {
  show_test_intro # 说明不会调用真实升级和联网。
  initialize_tests # 准备独立临时目录并加载被测函数。
  run_tests # 逐项检查结果传播、Git复检和参数适配。
}

main "$@"
