# shell: zsh
# 脚本自述：
# - 脚本名称：android_sdk_tests.zsh
# - 核心用途：验证 Flutter Android 工具缺失自愈、许可复检和失败传播。
# - 影响范围：仅使用专属临时目录和假工具，不联网、不安装或升级真实环境。
# - 运行提示：自动运行隔离回归；按 Ctrl+C 可取消。

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
TEST_ROOT=''
TEST_COUNT=0
TEST_FAILED=0
# 说明所有包管理器与 Android 工具均由临时假命令替换。
show_test_intro() {
  print -r -- 'Android SDK 隔离回归：不联网、不安装、不升级真实工具。Ctrl+C 可取消。'
}
# 只回收本测试创建的临时根。
TRAPEXIT() {
  [[ -z "$TEST_ROOT" || ! -d "$TEST_ROOT" || "${TEST_ROOT:t}" != jobs-update-android.* ]] || /bin/rm -r -- "$TEST_ROOT"
}
# 从源码包加载函数，不执行真实更新入口。
initialize_tests() {
  setopt NO_NOMATCH
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-update-android.XXXXXXXX")" || return 1
  TEST_ROOT="${TEST_ROOT:A}"
  export JOBS_MAC_ENV_SOURCE_MODE=1
  source "${TEST_SCRIPT_DIR:h:h}/update.command" || return 1
}
# 每例独立模拟 Flutter 实际 SDK、引导 SDK、JDK 和 Homebrew。
reset_fixture() {
  export TEST_CASE_DIR="$TEST_ROOT/case-$TEST_COUNT"
  export TEST_CASE_CALLS="$TEST_CASE_DIR/calls"
  export TEST_SDK="$TEST_CASE_DIR/Android SDK"
  export TEST_BOOTSTRAP="$TEST_CASE_DIR/brew/share/android-commandlinetools"
  export TEST_JDK="$TEST_CASE_DIR/Studio JDK"
  export TEST_MANAGER_TEMPLATE="$TEST_CASE_DIR/sdkmanager-template"
  export MOCK_BREW_INSTALLED=0 MOCK_BREW_FAIL=0 MOCK_MANAGER_FAIL=0 MOCK_INSTALL_NO_TARGET=0 MOCK_INSTALL_INVISIBLE_TARGET=0
  export MOCK_LICENSE_FAIL=0 MOCK_LICENSE_FALSE_SUCCESS=0 MOCK_LICENSE_PERSISTENT=0
  export MOCK_LICENSE_HANG=0
  export MOCK_DOCTOR_EXIT=0 MOCK_DOCTOR_FATAL=0 MOCK_NETWORK_ERROR=0 MOCK_DEVICE_WARNING=0
  export MOCK_POST_DOCTOR_EXIT=0 MOCK_POST_DOCTOR_FATAL=0 MOCK_DOCTOR_ABNORMAL=0 MOCK_UNKNOWN_DIAGNOSTIC=0
  JOBS_UPDATE_HEALTH_WARNING_COUNT=0
  export MOCK_FLUTTER="$TEST_CASE_DIR/flutter"
  /bin/mkdir -p "$TEST_SDK" "$TEST_JDK/bin" "$TEST_CASE_DIR/brew/bin"
  : > "$TEST_CASE_CALLS"
  LOG_FILE="$TEST_CASE_DIR/update.log"
  : > "$LOG_FILE"
  JOBS_UPDATE_TRUST_MODE=1
  JOBS_UPDATE_LOG_READY=1
  /bin/cat > "$TEST_JDK/bin/java" <<'MOCK_JAVA'
#!/bin/zsh
exit 0
MOCK_JAVA
  /bin/cat > "$TEST_MANAGER_TEMPLATE" <<'MOCK_MANAGER'
#!/bin/zsh
print -r -- "sdkmanager|$*" >> "$TEST_CASE_CALLS"
case "$*" in
  --version)
    (( MOCK_MANAGER_FAIL == 0 )) || { print -r -- 'UnsupportedClassVersionError'; exit 8; }
    print -r -- '23.0'
    ;;
  *'--install cmdline-tools;latest')
    [[ "$1" == "--sdk_root=$TEST_SDK" ]] || exit 96
    [[ "$JAVA_HOME" == "$TEST_JDK" && "$ANDROID_HOME" == "$TEST_SDK" ]] || exit 95
    (( MOCK_INSTALL_NO_TARGET == 0 )) || exit 0
    if (( MOCK_INSTALL_INVISIBLE_TARGET == 1 )); then
      /bin/mkdir -p "$TEST_SDK/cmdline-tools/jobs-installed/bin"
      /bin/cp "$TEST_MANAGER_TEMPLATE" "$TEST_SDK/cmdline-tools/jobs-installed/bin/sdkmanager"
      exit 0
    fi
    /bin/mkdir -p "$TEST_SDK/cmdline-tools/latest/bin"
    /bin/cp "$TEST_MANAGER_TEMPLATE" "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
    ;;
  *) exit 98 ;;
esac
MOCK_MANAGER
  /bin/cat > "$MOCK_FLUTTER" <<'MOCK_FLUTTER_SCRIPT'
#!/bin/zsh
print -r -- "flutter|$*" >> "$TEST_CASE_CALLS"
case "$*" in
  'doctor -v')
    (( MOCK_DOCTOR_ABNORMAL == 0 )) || exit "$MOCK_DOCTOR_ABNORMAL"
    if (( MOCK_DOCTOR_FATAL == 1 )); then
      print -r -- 'Failed to download sky_engine.zip. SocketException: Connection refused'
      print -r -- 'Android license status unknown.'
      exit 1
    fi
    print -r -- "    • Android SDK at $TEST_SDK"
    print -r -- "    • Java binary at: $TEST_JDK/bin/java"
    if [[ ! -f "$TEST_CASE_DIR/licensed" || "$MOCK_LICENSE_PERSISTENT" == 1 ]]; then
      print -r -- '[!] Android toolchain'
      print -r -- '    ✗ Android license status unknown.'
      print -r -- '      Run flutter doctor --android-licenses'
      exit "$MOCK_DOCTOR_EXIT"
    fi
    if (( MOCK_NETWORK_ERROR == 1 )); then
      print -r -- '[!] Network resources'
      print -r -- '    ✗ A network error occurred while checking "https://maven.google.com/": Operation timed out'
    elif (( MOCK_DEVICE_WARNING == 1 )); then
      print -r -- '[✓] Connected device'
      print -r -- '    ! Error: Browsing on the local area network for iPhone (code -27)'
    else
      print -r -- '[✓] Android toolchain'
    fi
    if (( MOCK_POST_DOCTOR_FATAL == 1 )); then
      print -r -- 'Failed to download sky_engine.zip. SocketException: Connection refused'
      exit 1
    fi
    if (( MOCK_UNKNOWN_DIAGNOSTIC == 1 )); then
      print -r -- '[!] Android toolchain'
      print -r -- '    ✗ Unknown Android validation failure.'
    fi
    exit "$MOCK_POST_DOCTOR_EXIT"
    ;;
  'doctor --android-licenses')
    if (( MOCK_LICENSE_HANG == 1 )); then
      while true; do /bin/sleep 1; done
    fi
    (( MOCK_LICENSE_FALSE_SUCCESS == 0 )) || { print -r -- 'Android sdkmanager not found.'; exit 0; }
    (( MOCK_LICENSE_FAIL == 0 )) || exit 7
    [[ -x "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager" || -x "$TEST_SDK/cmdline-tools/22.0/bin/sdkmanager" ]] || exit 94
    : > "$TEST_CASE_DIR/licensed"
    print -r -- 'All SDK package licenses accepted.'
    ;;
  *) exit 97 ;;
esac
MOCK_FLUTTER_SCRIPT
  /bin/cat > "$TEST_CASE_DIR/brew/bin/brew" <<'MOCK_BREW'
#!/bin/zsh
print -r -- "brew|$*" >> "$TEST_CASE_CALLS"
case "$*" in
  --prefix) print -r -- "$TEST_CASE_DIR/brew" ;;
  'list --cask --versions android-commandlinetools') exit "$(( 1 - MOCK_BREW_INSTALLED ))" ;;
  'install --cask android-commandlinetools'|'reinstall --cask android-commandlinetools')
    (( MOCK_BREW_FAIL == 0 )) || exit 6
    /bin/mkdir -p "$TEST_BOOTSTRAP/cmdline-tools/latest/bin"
    /bin/cp "$TEST_MANAGER_TEMPLATE" "$TEST_BOOTSTRAP/cmdline-tools/latest/bin/sdkmanager"
    ;;
  *) exit 93 ;;
esac
MOCK_BREW
  /bin/chmod +x "$TEST_JDK/bin/java" "$TEST_MANAGER_TEMPLATE" "$MOCK_FLUTTER" "$TEST_CASE_DIR/brew/bin/brew"
  function find_brew_bin() { print -r -- "$TEST_CASE_DIR/brew/bin/brew"; }
  function jobs_update_find_external_command() {
    [[ "$1" == sdkmanager && -x "$TEST_CASE_DIR/external/sdkmanager" ]] || return 1
    print -r -- "$TEST_CASE_DIR/external/sdkmanager"
  }
  function jobs_update_run_brew_update() { print -r -- 'brew-update' >> "$TEST_CASE_CALLS"; }
  function jobs_update_run_brew_adaptive_cmd() { shift 2; "$@"; }
}
# 将健康候选放到指定位置，避免使用宿主机 SDK。
install_manager() {
  /bin/mkdir -p "${1:h}"
  /bin/cp "$TEST_MANAGER_TEMPLATE" "$1"
}
# 统计真实假命令调用，不匹配描述日志。
call_count() {
  /usr/bin/grep -Fc -- "$1" "$TEST_CASE_CALLS" || true
}
# 已有健康 SDK 工具应直接接受许可，不进行安装。
test_healthy() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count 'flutter|doctor -v')" == 2 && "$(call_count 'flutter|doctor --android-licenses')" == 1 ]] || return 1
  [[ "$(call_count 'brew|install')" == 0 && "$(call_count '--install cmdline-tools;latest')" == 0 ]]
}
# 当前 SDK 的版本目录可复用，不强制重复安装 latest。
test_versioned_sdk() {
  install_manager "$TEST_SDK/cmdline-tools/22.0/bin/sdkmanager"
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count '--install cmdline-tools;latest')" == 0 ]]
}
# 重现本机 jobs-* 目录：工具可作引导，但必须补齐 Flutter 可发现的 latest。
test_jobs_directory_bootstrap() {
  install_manager "$TEST_SDK/cmdline-tools/jobs-23.0-ncXbUk/bin/sdkmanager"
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count '--install cmdline-tools;latest')" == 1 && "$(call_count 'brew|install')" == 0 ]] || return 1
  [[ -x "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager" && "$(call_count 'flutter|doctor --android-licenses')" == 1 ]]
}
# 引导工具安装返回零但只留下 jobs-* 时，严格复检必须拒绝继续许可。
test_post_install_invisible() {
  install_manager "$TEST_SDK/cmdline-tools/jobs-23.0-ncXbUk/bin/sdkmanager"
  MOCK_INSTALL_INVISIBLE_TARGET=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count '--install cmdline-tools;latest')" == 1 && "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# 外部 sdkmanager 必须明确安装到 Flutter 实际 SDK。
test_existing_external() {
  install_manager "$TEST_CASE_DIR/external/sdkmanager"
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count '--install cmdline-tools;latest')" == 1 && "$(call_count 'brew|install')" == 0 ]]
}
# 工具全缺时只补引导 cask 一次，再补目标 SDK 并复检。
test_missing_chain() {
  MOCK_DOCTOR_EXIT=1
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count 'brew|install --cask android-commandlinetools')" == 1 && "$(call_count '--install cmdline-tools;latest')" == 1 ]]
}
# 已有 cask 登记而文件残缺时使用 reinstall，不循环重试。
test_broken_cask() {
  MOCK_BREW_INSTALLED=1
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$(call_count 'brew|reinstall --cask android-commandlinetools')" == 1 ]]
}
# 引导安装失败后必须停止许可与 doctor 复检。
test_install_failure() {
  MOCK_BREW_FAIL=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'brew|install')" == 1 && "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# 安装器零退出码不能替代目标 sdkmanager 复检。
test_post_install_missing() {
  MOCK_INSTALL_NO_TARGET=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count '--install cmdline-tools;latest')" == 1 && "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# 可执行文件存在但版本检查失败时不能继续接受许可。
test_unhealthy_manager() {
  MOCK_MANAGER_FAIL=1
  install_manager "$TEST_CASE_DIR/external/sdkmanager"
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# 许可命令即使返回零，明确缺失工具输出也必须失败。
test_false_license_success() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_LICENSE_FALSE_SUCCESS=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'flutter|doctor -v')" == 1 ]]
}
# 许可接受后仍未知，复检必须保留失败结果。
test_license_still_unknown() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_LICENSE_PERSISTENT=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'flutter|doctor -v')" == 2 ]]
}
# 实际下载失败不继续执行 Android 安装。
test_flutter_fatal() {
  MOCK_DOCTOR_FATAL=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'brew|')" == 0 && "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# Android 自愈后网络健康探测失败单独汇总，不覆盖已经完成的 SDK 更新。
test_network_warning() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_NETWORK_ERROR=1
  MOCK_POST_DOCTOR_EXIT=1
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ -f "$TEST_CASE_DIR/licensed" && "$JOBS_UPDATE_HEALTH_WARNING_COUNT" == 1 ]]
}
# 网络健康标题不能掩盖真正的 SDK 资源下载失败。
test_network_and_download_failure() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_NETWORK_ERROR=1
  MOCK_POST_DOCTOR_FATAL=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && (( JOBS_UPDATE_HEALTH_WARNING_COUNT == 0 ))
}
# 未识别的 Android 验证失败不能因同时出现网络健康告警被洗成成功。
test_network_and_unknown_failure() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_NETWORK_ERROR=1
  MOCK_UNKNOWN_DIAGNOSTIC=1
  MOCK_POST_DOCTOR_EXIT=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 ))
}
# doctor 启动后异常退出且没有结构化诊断，必须保留失败。
test_doctor_abnormal_exit() {
  MOCK_DOCTOR_ABNORMAL=2
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ "$(call_count 'flutter|doctor --android-licenses')" == 0 ]]
}
# 设备离线提醒不应被解释为 SDK 升级或许可失败。
test_device_warning() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  MOCK_DEVICE_WARNING=1
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  (( JOBS_UPDATE_HEALTH_WARNING_COUNT == 1 ))
}
# JDK 和 SDK 定向只在函数内有效，返回后保留调用者原状态。
test_environment_scope() {
  export JAVA_HOME="$TEST_CASE_DIR/original-java" ANDROID_HOME="$TEST_CASE_DIR/original-sdk"
  unset ANDROID_SDK_ROOT
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || return 1
  [[ "$JAVA_HOME" == "$TEST_CASE_DIR/original-java" && "$ANDROID_HOME" == "$TEST_CASE_DIR/original-sdk" && "${+ANDROID_SDK_ROOT}" == 0 ]]
}
# 许可子进程卡住时受总时限约束，不能继续写入接受标记或执行 doctor。
test_license_timeout() {
  install_manager "$TEST_SDK/cmdline-tools/latest/bin/sdkmanager"
  export JOBS_ANDROID_SDK_TIMEOUT=1 MOCK_LICENSE_HANG=1
  local result=0
  jobs_update_run_flutter_doctor_and_android_licenses Flutter "$MOCK_FLUTTER" || result=$?
  (( result != 0 )) && [[ ! -e "$TEST_CASE_DIR/licensed" && "$(call_count 'flutter|doctor -v')" == 1 ]]
}
# 用子 Shell 隔离函数替换及环境变量，不污染下一例。
run_case() {
  local label="$1"
  shift
  (( TEST_COUNT += 1 ))
  if (reset_fixture && "$@"); then
    print -r -- "PASS $label"
  else
    print -u2 -r -- "FAIL $label"
    (( TEST_FAILED += 1 ))
  fi
}
# 覆盖依赖链健康、缺失、修复失败、复检失败及环境作用域。
run_tests() {
  run_case '健康 SDK 直接接受许可' test_healthy
  run_case '版本化 SDK 工具复用' test_versioned_sdk
  run_case 'jobs-* 目录只作引导并补 latest' test_jobs_directory_bootstrap
  run_case '安装后仅不可见目录时停止' test_post_install_invisible
  run_case '外部引导工具定向修复' test_existing_external
  run_case '多层缺失一次自愈' test_missing_chain
  run_case '残缺 cask 一次重装' test_broken_cask
  run_case '引导安装失败停止' test_install_failure
  run_case '安装后无工具不误报成功' test_post_install_missing
  run_case 'sdkmanager 可执行但不健康' test_unhealthy_manager
  run_case '许可零码错误输出不误报成功' test_false_license_success
  run_case '许可接受后仍未知' test_license_still_unknown
  run_case 'Flutter 下载失败停止' test_flutter_fatal
  run_case '网络健康告警和升级结果分开' test_network_warning
  run_case '网络告警不掩盖实际下载失败' test_network_and_download_failure
  run_case '网络告警不掩盖未知验证失败' test_network_and_unknown_failure
  run_case 'doctor 异常退出保留失败' test_doctor_abnormal_exit
  run_case '设备离线提醒不误判' test_device_warning
  run_case 'JDK 与 SDK 环境作用域' test_environment_scope
  run_case '许可卡住时总时限退出' test_license_timeout
  print -r -- "完成：$TEST_COUNT 项，失败 $TEST_FAILED 项。"
  (( TEST_FAILED == 0 ))
}
# 编排自述、源码加载和隔离回归。
main() {
  show_test_intro # 说明测试范围和取消方式。
  initialize_tests # 建立私有目录并加载源码函数。
  run_tests # 执行必要依赖与失败传播回归。
}

main "$@"
