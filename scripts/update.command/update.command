#!/bin/zsh
# 脚本自述：
# - 脚本名称：update.command
# - 核心用途：执行“update”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


# ============================================================
# update.command - macOS 开发环境升级维护
# ============================================================
# 原则：install.command 负责安装过的内容，update.command 必须体现并提供升级 / 刷新入口。
# 说明：
# 1. 适合 .command 双击运行，也可终端执行。
# 2. 启动后先显示内置 README，并等待回车确认。
# 3. 普通升级项统一为：直接回车执行升级，输入任意字符后回车跳过。
# 4. 单项失败不阻断后续更新项，但会写入日志。
# 5. 不存在的工具不在 update 中静默安装，只提示回到 install.command 补装。
# ============================================================

# ---------- 基础路径 ----------
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
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
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
JOBS_UPDATE_TRUST_MODE=0
readonly JOBS_UPDATE_NETWORK_PROBE_URL="https://formulae.brew.sh/api/formula.jws.json"
readonly JOBS_UPDATE_NETWORK_PROBE_BYTES=1048576
readonly JOBS_UPDATE_NETWORK_PROBE_TIMEOUT_SECONDS=8
readonly JOBS_UPDATE_MAX_LOW_SPEED_LIMIT_BPS=131072
readonly JOBS_UPDATE_MIN_LOW_SPEED_LIMIT_BPS=8192
readonly JOBS_UPDATE_FINAL_LOW_SPEED_LIMIT_BPS=1024
readonly JOBS_UPDATE_LOW_SPEED_SECONDS=30
readonly JOBS_UPDATE_FINAL_LOW_SPEED_SECONDS=60
readonly JOBS_UPDATE_PROGRESS_INTERVAL_SECONDS=20
JOBS_UPDATE_NETWORK_READY=0
JOBS_UPDATE_PREFERRED_IP_FAMILY="ipv4"
JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv6"
JOBS_UPDATE_IPV4_PROBE_SPEED=0
JOBS_UPDATE_IPV6_PROBE_SPEED=0
JOBS_UPDATE_ACTIVE_LOW_SPEED_LIMIT_BPS=0
JOBS_UPDATE_ACTIVE_LOW_SPEED_SECONDS=0
JOBS_UPDATE_BREW_CURLRC=""
JOBS_UPDATE_LAST_BREW_OUTPUT_FILE=""
JOBS_UPDATE_PROGRESS_MONITOR_PID=""
JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC=""
JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET=0


# ---------- 全局配置：必须与 install.command 保持同源 ----------
readonly JOBS_SOFTWARE_REPO="https://github.com/JobsKits/JobsSoftware.MacOS.git"
readonly JOBS_ENV_REPO="https://github.com/JobsKits/JobsMacEnvVarConfig.git"
readonly JOBS_WORKSPACE="${HOME}/Desktop/JobsKits"

readonly -a BREW_CASKS=(
  hammerspoon
  flutter
  trex
  vlc
  jdownloader
  codex-app
  codex
  github-store
  jtool2
  motrix
  onlyoffice
  pot
  qlcolorcode
  temurin@17
)

readonly -a BREW_FORMULAE=(
  agg
  asciinema
  caddy
  cloudflared
  git-lfs
  gh
  nushell
  rbenv
  ruby
  node
  jenv
  openjdk
  openjdk@17
  openjdk@21
  fvm
  pnpm
  python
  python3
  python-tk@3.14
  pyinstaller
  pyside
  cocoapods
  fastlane
  mysql
  hugo
  yt-dlp
  ffmpeg
  cmake
  graphviz
  sevenzip
  go-task
  uv
  fzf
  glow
  lazygit
  dufs
  git-filter-repo
  nginx
  radare2
)
# ---------- 彩色日志 ----------
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }
# ---------- 通用基础函数 ----------
print_divider() {
  gray_echo "------------------------------------------------------------------------"
}
# 封装 jobs_update_has 对应的独立处理逻辑。
jobs_update_has() {
  command -v "$1" >/dev/null 2>&1
}
# 打印 update.command 的参数说明。
jobs_update_show_usage() {
  cat <<'EOFUSAGE'
用法：
  update.command
  update.command -t

参数：
  -t, --trust, --unattended  无人值守模式：跳过脚本确认、自动执行更新项；提权命令使用 sudo -n，无授权时立即跳过，绝不等待密码。
  -h, --help                显示本说明。
EOFUSAGE
}
# 解析 update.command 的运行参数。
jobs_update_parse_args() {
  local arg=""

  for arg in "$@"; do
    case "$arg" in
      -t|--trust|--unattended)
        JOBS_UPDATE_TRUST_MODE=1
        ;;
      -h|--help)
        jobs_update_show_usage
        return 2
        ;;
      *)
        error_echo "未知参数：${arg}"
        jobs_update_show_usage
        return 1
        ;;
    esac
  done
}
# 无人值守模式禁止阻塞式密码输入，提权项由统一执行器快速判定。
jobs_update_prepare_unattended_mode() {
  if (( JOBS_UPDATE_TRUST_MODE != 1 )); then
    return 0
  fi

  echo ""
  warn_echo "已启用无人值守模式：将自动执行全部更新项，并为已知确认点自动输入 y。"
  warm_echo "需要管理员权限的命令统一使用 sudo -n；当前无免密或已缓存授权时立即跳过，绝不等待密码。"
  gray_echo "安全边界：脚本不保存、不传递管理员密码，也不自动修改 sudoers。"
}
# 封装 jobs_update_prompt_run 对应的独立处理逻辑。
jobs_update_prompt_run() {
  local title="$1"
  local detail="$2"
  local answer=""

  echo ""
  warn_echo "强提示：${title}"
  warm_echo "回车=执行升级 / 刷新；输入任意字符后回车=跳过"
  gray_echo "${detail}"

  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    note_echo "托管模式：自动执行 ${title}"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    warn_echo "当前不是交互式终端，已跳过：${title}"
    return 1
  fi

  IFS= read -r answer

  if [[ -z "$answer" ]]; then
    return 0
  fi

  note_echo "已跳过：${title}"
  return 1
}
# 封装 jobs_update_run_step 对应的独立处理逻辑。
jobs_update_run_step() {
  local title="$1"
  shift

  echo ""
  highlight_echo "$title"
  print_divider

  "$@"
  local exit_code=$?

  if (( exit_code == 0 )); then
    success_echo "$title：完成"
  else
    warn_echo "$title：返回非 0（${exit_code}），继续后续更新项"
  fi

  return 0
}
# 封装 jobs_update_run_cmd 对应的独立处理逻辑。
jobs_update_run_cmd() {
  local desc="$1"
  shift

  note_echo "$desc"
  debug_echo "执行命令：$*"

  "$@"
  local exit_code=$?

  if (( exit_code == 0 )); then
    success_echo "$desc：完成"
  else
    warn_echo "$desc：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 统一执行需要管理员权限的命令，确保无人值守时不会停在密码提示。
jobs_update_run_sudo_cmd() {
  local desc="$1"
  shift

  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    if jobs_update_run_cmd "$desc（无人值守）" sudo -n "$@"; then
      return 0
    fi

    warn_echo "无人值守模式未获得该命令的无密码授权，已跳过：${desc}"
    warm_echo "如确实需要执行，请之后在场以普通模式手动运行 update。"
    return 1
  fi

  jobs_update_run_cmd "$desc" sudo "$@"
}
# npm 全局包可能遗留为 root 所有；仅在目标不可写时进入统一提权策略。
jobs_update_run_npm_global_cmd() {
  local desc="$1"
  local package_relative_path="$2"
  local npm_root=""
  local package_path=""
  shift 2

  npm_root="$(npm root -g 2>/dev/null || true)"
  package_path="${npm_root}/${package_relative_path}"

  if [[ -n "$npm_root" ]] && { { [[ -e "$package_path" ]] && [[ ! -w "$package_path" ]]; } || { [[ ! -e "$package_path" ]] && [[ ! -w "$npm_root" ]]; }; }; then
    warn_echo "npm 全局包目录当前用户不可写：${package_path}"
    jobs_update_run_sudo_cmd "$desc" npm "$@"
    return $?
  fi

  jobs_update_run_cmd "$desc" npm "$@"
}
# 封装 jobs_update_run_sh 对应的独立处理逻辑。
jobs_update_run_sh() {
  local desc="$1"
  local cmd="$2"

  note_echo "$desc"
  debug_echo "执行命令：${cmd}"

  /bin/zsh -c "$cmd"
  local exit_code=$?

  if (( exit_code == 0 )); then
    success_echo "$desc：完成"
  else
    warn_echo "$desc：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 对已知会询问 y/n 的命令定点输入 y，避免托管模式中途卡住。
jobs_update_run_cmd_with_yes() {
  local desc="$1"
  shift

  note_echo "$desc"
  debug_echo "执行命令：printf 'y\\n' | $*"

  printf 'y\n' | "$@" 2>&1 | tee -a "$LOG_FILE"
  local exit_code=${pipestatus[2]}

  if (( exit_code == 0 )); then
    success_echo "$desc：完成"
  else
    warn_echo "$desc：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 返回指定 IP 协议对应的 curl 参数。
jobs_update_ip_family_curl_flag() {
  case "$1" in
    ipv4) print -r -- "--ipv4" ;;
    ipv6) print -r -- "--ipv6" ;;
    *) return 1 ;;
  esac
}
# 使用小流量分段下载测量指定 IP 协议的实时速度。
jobs_update_measure_ip_family_speed() {
  local family="$1"
  local family_flag=""
  local range_end=$((JOBS_UPDATE_NETWORK_PROBE_BYTES - 1))
  local speed=""

  family_flag="$(jobs_update_ip_family_curl_flag "$family")" || {
    print -r -- "0"
    return 0
  }
  speed="$(/usr/bin/curl "$family_flag" \
    --location \
    --silent \
    --fail \
    --output /dev/null \
    --range "0-${range_end}" \
    --connect-timeout 5 \
    --max-time "$JOBS_UPDATE_NETWORK_PROBE_TIMEOUT_SECONDS" \
    --write-out '%{speed_download}' \
    "$JOBS_UPDATE_NETWORK_PROBE_URL" 2>/dev/null || true)"
  speed="${speed%%.*}"
  [[ "$speed" == <-> ]] || speed=0
  print -r -- "$speed"
}
# 把字节每秒转换成便于日志阅读的 KiB/s。
jobs_update_format_download_speed() {
  local speed="${1:-0}"

  if [[ "$speed" != <-> ]] || (( speed <= 0 )); then
    print -r -- "不可用"
    return 0
  fi
  print -r -- "$((speed / 1024)) KiB/s"
}
# 返回指定 IP 协议的测速结果。
jobs_update_probe_speed_for_family() {
  case "$1" in
    ipv4) print -r -- "$JOBS_UPDATE_IPV4_PROBE_SPEED" ;;
    ipv6) print -r -- "$JOBS_UPDATE_IPV6_PROBE_SPEED" ;;
    *) print -r -- "0" ;;
  esac
}
# 按实测带宽计算低速阈值，避免慢线路被固定阈值误判为断线。
jobs_update_adaptive_low_speed_limit_for_family() {
  local speed=""
  local limit=0

  speed="$(jobs_update_probe_speed_for_family "$1")"
  [[ "$speed" == <-> ]] || speed=0
  if (( speed > 0 )); then
    limit=$((speed / 4))
  fi
  (( limit < JOBS_UPDATE_MIN_LOW_SPEED_LIMIT_BPS )) && limit=$JOBS_UPDATE_MIN_LOW_SPEED_LIMIT_BPS
  (( limit > JOBS_UPDATE_MAX_LOW_SPEED_LIMIT_BPS )) && limit=$JOBS_UPDATE_MAX_LOW_SPEED_LIMIT_BPS
  print -r -- "$limit"
}
# 写入仅供本轮 update 使用的 Homebrew curl 配置。
jobs_update_write_brew_curlrc() {
  local family="$1"
  local guard_mode="${2:-adaptive}"
  local family_option=""
  local speed_limit=0
  local speed_seconds=0

  [[ -n "$JOBS_UPDATE_BREW_CURLRC" ]] || return 1
  family_option="$(jobs_update_ip_family_curl_flag "$family")" || return 1
  case "$guard_mode" in
    adaptive)
      speed_limit="$(jobs_update_adaptive_low_speed_limit_for_family "$family")"
      speed_seconds=$JOBS_UPDATE_LOW_SPEED_SECONDS
      ;;
    final)
      speed_limit=$JOBS_UPDATE_FINAL_LOW_SPEED_LIMIT_BPS
      speed_seconds=$JOBS_UPDATE_FINAL_LOW_SPEED_SECONDS
      ;;
    *)
      return 1
      ;;
  esac
  JOBS_UPDATE_ACTIVE_LOW_SPEED_LIMIT_BPS=$speed_limit
  JOBS_UPDATE_ACTIVE_LOW_SPEED_SECONDS=$speed_seconds

  {
    if (( JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET == 1 )); then
      if [[ "$JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC" == /* && -f "$JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC" ]]; then
        print -r -- "config = \"${JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC}\""
      elif [[ -f "${HOME}/.curlrc" ]]; then
        print -r -- "config = \"${HOME}/.curlrc\""
      fi
    fi
    print -r -- "$family_option"
    print -r -- "--connect-timeout 10"
    print -r -- "--speed-limit ${speed_limit}"
    print -r -- "--speed-time ${speed_seconds}"
  } > "$JOBS_UPDATE_BREW_CURLRC"
}
# 选择探测速度更快的 IP 协议，并让后续 Homebrew 下载复用该选择。
jobs_update_select_preferred_ip_family() {
  JOBS_UPDATE_IPV4_PROBE_SPEED="$(jobs_update_measure_ip_family_speed ipv4)"
  JOBS_UPDATE_IPV6_PROBE_SPEED="$(jobs_update_measure_ip_family_speed ipv6)"

  info_echo "Homebrew 下载线路探测：IPv4=$(jobs_update_format_download_speed "$JOBS_UPDATE_IPV4_PROBE_SPEED")，IPv6=$(jobs_update_format_download_speed "$JOBS_UPDATE_IPV6_PROBE_SPEED")"
  if (( JOBS_UPDATE_IPV6_PROBE_SPEED > JOBS_UPDATE_IPV4_PROBE_SPEED )); then
    JOBS_UPDATE_PREFERRED_IP_FAMILY="ipv6"
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv4"
  else
    JOBS_UPDATE_PREFERRED_IP_FAMILY="ipv4"
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv6"
  fi

  if (( JOBS_UPDATE_IPV4_PROBE_SPEED == 0 && JOBS_UPDATE_IPV6_PROBE_SPEED == 0 )); then
    warn_echo "IPv4 / IPv6 探测均未获得有效速度，先从 IPv4 开始；正式下载失败后仍会自动切换。"
  else
    success_echo "Homebrew 下载首选线路：${JOBS_UPDATE_PREFERRED_IP_FAMILY}"
  fi
}
# 初始化整轮 update 共用的 Homebrew 自适应下载策略。
jobs_update_ensure_network_strategy() {
  if (( JOBS_UPDATE_NETWORK_READY == 1 )); then
    return 0
  fi
  if [[ ! -x /usr/bin/curl ]]; then
    warn_echo "未找到 /usr/bin/curl，Homebrew 下载将沿用默认网络策略。"
    return 1
  fi

  if (( ${+HOMEBREW_CURLRC} )); then
    JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET=1
    JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC="$HOMEBREW_CURLRC"
  fi
  JOBS_UPDATE_BREW_CURLRC="$(mktemp -t jobs_update_homebrew_curlrc.XXXXXX)" || return 1
  jobs_update_select_preferred_ip_family
  jobs_update_write_brew_curlrc "$JOBS_UPDATE_PREFERRED_IP_FAMILY" adaptive || return 1
  export HOMEBREW_CURLRC="$JOBS_UPDATE_BREW_CURLRC"
  JOBS_UPDATE_NETWORK_READY=1
  note_echo "已启用全局 Homebrew 自适应下载：低速阈值会按线路实测速度自动收敛，停滞时切换 IPv4 / IPv6。"
}
# 清理临时网络配置，并恢复用户原有的 Homebrew curl 设置。
jobs_update_cleanup_network_strategy() {
  if (( JOBS_UPDATE_NETWORK_READY != 1 )) && [[ -z "$JOBS_UPDATE_BREW_CURLRC" && -z "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]]; then
    return 0
  fi
  jobs_update_stop_brew_progress_monitor
  if [[ -n "$JOBS_UPDATE_BREW_CURLRC" && -f "$JOBS_UPDATE_BREW_CURLRC" ]]; then
    rm -f "$JOBS_UPDATE_BREW_CURLRC"
  fi
  if [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" && -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]]; then
    rm -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
  fi
  if (( JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET == 1 )); then
    export HOMEBREW_CURLRC="$JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC"
  else
    unset HOMEBREW_CURLRC
  fi
  JOBS_UPDATE_NETWORK_READY=0
}
# 更新首选 IP 协议，并重写后续 Homebrew 下载使用的速度守卫。
jobs_update_prefer_ip_family() {
  local family="$1"

  JOBS_UPDATE_PREFERRED_IP_FAMILY="$family"
  if [[ "$family" == "ipv4" ]]; then
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv6"
  else
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv4"
  fi
  jobs_update_write_brew_curlrc "$family" adaptive
}
# 汇总 Homebrew 未完成下载缓存的当前字节数。
jobs_update_homebrew_incomplete_bytes() {
  local cache_dir="${HOME}/Library/Caches/Homebrew/downloads"
  local file=""
  local size=0
  local total=0

  [[ -d "$cache_dir" ]] || {
    print -r -- "0"
    return 0
  }
  while IFS= read -r -d '' file; do
    size="$(stat -f '%z' "$file" 2>/dev/null || print -r -- "0")"
    [[ "$size" == <-> ]] || size=0
    total=$((total + size))
  done < <(find "$cache_dir" -type f -name '*.incomplete' -print0 2>/dev/null)
  print -r -- "$total"
}
# 把字节数转换成便于进度日志阅读的大小。
jobs_update_format_download_bytes() {
  local bytes="${1:-0}"

  [[ "$bytes" == <-> ]] || bytes=0
  if (( bytes >= 1048576 )); then
    print -r -- "$((bytes / 1048576)) MiB"
  elif (( bytes >= 1024 )); then
    print -r -- "$((bytes / 1024)) KiB"
  else
    print -r -- "${bytes} B"
  fi
}
# 在 Homebrew 隐藏 curl 进度条时输出缓存增长心跳。
jobs_update_monitor_brew_progress() {
  local desc="$1"
  local family="$2"
  local previous_bytes=""
  local current_bytes=""
  local delta_bytes=0

  previous_bytes="$(jobs_update_homebrew_incomplete_bytes)"
  while true; do
    sleep "$JOBS_UPDATE_PROGRESS_INTERVAL_SECONDS"
    current_bytes="$(jobs_update_homebrew_incomplete_bytes)"
    if (( current_bytes > previous_bytes )); then
      delta_bytes=$((current_bytes - previous_bytes))
      info_echo "${desc}（${family}）仍在下载：最近增加 $(jobs_update_format_download_bytes "$delta_bytes")，未完成缓存共 $(jobs_update_format_download_bytes "$current_bytes")。"
    else
      gray_echo "${desc}（${family}）仍在执行，暂未观察到下载缓存增长；若持续低于阈值将自动超时。"
    fi
    previous_bytes=$current_bytes
  done
}
# 启动单个 Homebrew 命令对应的进度心跳。
jobs_update_start_brew_progress_monitor() {
  jobs_update_stop_brew_progress_monitor
  jobs_update_monitor_brew_progress "$1" "$2" &
  JOBS_UPDATE_PROGRESS_MONITOR_PID=$!
}
# 停止当前 Homebrew 进度心跳并回收后台进程。
jobs_update_stop_brew_progress_monitor() {
  [[ -n "$JOBS_UPDATE_PROGRESS_MONITOR_PID" ]] || return 0
  kill "$JOBS_UPDATE_PROGRESS_MONITOR_PID" 2>/dev/null || true
  wait "$JOBS_UPDATE_PROGRESS_MONITOR_PID" 2>/dev/null || true
  JOBS_UPDATE_PROGRESS_MONITOR_PID=""
}
# 判断 Homebrew 失败是否来自下载链路，以免对安装或权限错误盲目换线。
jobs_update_brew_failure_is_network_related() {
  [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" && -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]] || return 1
  grep -Eqi 'curl: \([0-9]+\)|Failed to download resource|Download failed|Could not resolve host|Failed to connect|Connection timed out|Operation timed out|Operation too slow|SSL connect error|Recv failure|Send failure|HTTP/[0-9.]+ stream' "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
}
# 使用指定 IP 协议执行一次 Homebrew 下载命令。
jobs_update_run_brew_network_attempt() {
  local desc="$1"
  local confirmation_mode="$2"
  local family="$3"
  local guard_mode="$4"
  local retries=0
  shift 4

  jobs_update_write_brew_curlrc "$family" "$guard_mode" || return 1
  [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]] || return 1
  : > "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
  note_echo "${desc}（${family}，连续 ${JOBS_UPDATE_ACTIVE_LOW_SPEED_SECONDS} 秒低于 $(jobs_update_format_download_speed "$JOBS_UPDATE_ACTIVE_LOW_SPEED_LIMIT_BPS") 时终止当前尝试）"
  debug_echo "执行命令：HOMEBREW_CURLRC=<临时配置> HOMEBREW_CURL_RETRIES=${retries} $*"
  jobs_update_start_brew_progress_monitor "$desc" "$family"

  if [[ "$confirmation_mode" == "yes" ]]; then
    printf 'y\n' | env HOMEBREW_CURLRC="$JOBS_UPDATE_BREW_CURLRC" HOMEBREW_CURL_RETRIES="$retries" "$@" 2>&1 | tee -a "$LOG_FILE" | tee "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
    local exit_code=${pipestatus[2]}
  else
    env HOMEBREW_CURLRC="$JOBS_UPDATE_BREW_CURLRC" HOMEBREW_CURL_RETRIES="$retries" "$@" 2>&1 | tee -a "$LOG_FILE" | tee "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
    local exit_code=${pipestatus[1]}
  fi
  jobs_update_stop_brew_progress_monitor

  if (( exit_code == 0 )); then
    success_echo "${desc}（${family}）：完成"
  else
    warn_echo "${desc}（${family}）：失败（exit code: ${exit_code}）"
  fi
  return $exit_code
}
# 为所有 Homebrew 更新下载提供低速换线和有限重试。
jobs_update_run_brew_adaptive_cmd() {
  local desc="$1"
  local confirmation_mode="$2"
  local primary_family=""
  local secondary_family=""
  local exit_code=0
  shift 2

  if ! jobs_update_ensure_network_strategy; then
    if [[ "$confirmation_mode" == "yes" ]]; then
      jobs_update_run_cmd_with_yes "$desc" "$@"
    else
      jobs_update_run_cmd "$desc" "$@"
    fi
    return $?
  fi
  if [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" && -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]]; then
    rm -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
  fi
  JOBS_UPDATE_LAST_BREW_OUTPUT_FILE="$(mktemp -t jobs_update_brew_output.XXXXXX)" || return 1
  primary_family="$JOBS_UPDATE_PREFERRED_IP_FAMILY"
  secondary_family="$JOBS_UPDATE_SECONDARY_IP_FAMILY"

  jobs_update_run_brew_network_attempt "$desc" "$confirmation_mode" "$primary_family" adaptive "$@"
  exit_code=$?
  if (( exit_code == 0 )); then
    jobs_update_prefer_ip_family "$primary_family"
    return 0
  fi
  if ! jobs_update_brew_failure_is_network_related; then
    return $exit_code
  fi

  warn_echo "${primary_family} 下载异常或持续低速，自动切换到 ${secondary_family}。"
  jobs_update_run_brew_network_attempt "$desc" "$confirmation_mode" "$secondary_family" adaptive "$@"
  exit_code=$?
  if (( exit_code == 0 )); then
    jobs_update_prefer_ip_family "$secondary_family"
    return 0
  fi
  if ! jobs_update_brew_failure_is_network_related; then
    return $exit_code
  fi

  warn_echo "IPv4 / IPv6 均触发网络失败；将使用探测中较快的 ${primary_family} 做最后一次宽松低速尝试，停滞时仍会退出。"
  jobs_update_run_brew_network_attempt "$desc" "$confirmation_mode" "$primary_family" final "$@"
  exit_code=$?
  jobs_update_prefer_ip_family "$primary_family"
  return $exit_code
}
# 执行 brew update，遇到 Homebrew API 下载失败时自动降级为本地 tap 更新。
jobs_update_run_brew_update() {
  jobs_update_run_brew_adaptive_cmd "brew update（更新软件列表）" plain brew update
  local exit_code=$?

  if (( exit_code == 0 )); then
    return 0
  fi

  if [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]] && grep -Eq "formulae\\.brew\\.sh/api|Failed to download .*\\.jws\\.json" "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"; then
    warn_echo "brew update API 数据下载失败，将使用 HOMEBREW_NO_INSTALL_FROM_API=1 降级重试。"
    warm_echo "说明：该模式会跳过 formulae.brew.sh API JSON 下载，改用本地 tap 更新，通常更慢但更稳。"
    jobs_update_run_brew_adaptive_cmd "brew update（本地 tap 降级重试）" plain env HOMEBREW_NO_INSTALL_FROM_API=1 brew update
    exit_code=$?
  else
    warn_echo "brew update（更新软件列表）：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 执行 brew upgrade，托管模式下自动确认 Homebrew 的 y/n 提示。
jobs_update_run_brew_upgrade() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    jobs_update_run_brew_adaptive_cmd "brew upgrade（升级已安装 formula）" yes brew upgrade
    return $?
  fi

  jobs_update_run_brew_adaptive_cmd "brew upgrade（升级已安装 formula）" plain brew upgrade
}
# 执行 brew cask 全局升级，托管模式下自动确认 Homebrew 的 y/n 提示。
jobs_update_run_brew_cask_upgrade() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    jobs_update_run_brew_adaptive_cmd "brew upgrade --cask（升级已安装 cask）" yes brew upgrade --cask
    return $?
  fi

  jobs_update_run_brew_adaptive_cmd "brew upgrade --cask（升级已安装 cask）" plain brew upgrade --cask
}
# 封装 append_once 对应的独立处理逻辑。
append_once() {
  local line="$1"
  local file="${2:-$HOME/.zshrc}"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -Fqx "$line" "$file"; then
    return 0
  fi

  echo "" >> "$file"
  echo "$line" >> "$file"
}
# 封装 append_comment_once 对应的独立处理逻辑。
append_comment_once() {
  local comment="$1"
  local file="$2"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -Fqx "$comment" "$file"; then
    return 0
  fi

  echo "" >> "$file"
  echo "$comment" >> "$file"
}
# 解析并返回后续流程需要的目标信息。
find_brew_bin() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  local candidate
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}
# 执行对应的环境配置或同步处理。
setup_brew_shellenv() {
  local brew_bin="$1"
  local shellenv_line="eval \"\$(${brew_bin} shellenv)\""

  if [[ ! -x "$brew_bin" ]]; then
    warn_echo "Homebrew 可执行文件不存在或不可执行：${brew_bin}"
    return 1
  fi

  local target_file
  for target_file in "${HOME}/.zprofile" "${HOME}/.zshrc"; do
    append_comment_once "# Homebrew shellenv" "$target_file"
    append_once "$shellenv_line" "$target_file"
    success_echo "已确认 Homebrew 环境变量配置：${target_file}"
  done

  eval "$($brew_bin shellenv)"
  hash -r 2>/dev/null || true
}
# 封装 require_brew_or_skip 对应的独立处理逻辑。
require_brew_or_skip() {
  local brew_bin=""

  if brew_bin="$(find_brew_bin)"; then
    setup_brew_shellenv "$brew_bin"
    return 0
  fi

  warn_echo "未检测到 Homebrew，跳过当前更新项。请先运行 install.command 安装 Homebrew。"
  return 1
}
# 执行对应的环境配置或同步处理。
setup_fzf_shellenv() {
  if ! jobs_update_has brew; then
    return 0
  fi

  local fzf_base=""
  fzf_base="$(brew --prefix fzf 2>/dev/null || true)"

  if [[ -n "$fzf_base" && -d "$fzf_base" ]]; then
    append_comment_once "# fzf" "${HOME}/.zshrc"
    append_once '[ -f "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh" ] && source "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"' "${HOME}/.zshrc"
    append_once '[ -f "$(brew --prefix)/opt/fzf/shell/completion.zsh" ] && source "$(brew --prefix)/opt/fzf/shell/completion.zsh"' "${HOME}/.zshrc"
    success_echo "已确认 fzf shell 配置：${HOME}/.zshrc"
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_jenv_init() {
  append_comment_once "# jenv" "${HOME}/.zshrc"
  append_once 'export PATH="$HOME/.jenv/bin:$PATH"' "${HOME}/.zshrc"
  append_once 'eval "$(jenv init -)"' "${HOME}/.zshrc"
  success_echo "已确认 jenv 初始化配置：${HOME}/.zshrc"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_rbenv_init() {
  append_comment_once "# rbenv" "${HOME}/.zshrc"
  append_once 'eval "$(rbenv init - zsh)"' "${HOME}/.zshrc"
  success_echo "已确认 rbenv 初始化配置：${HOME}/.zshrc"
}
# 封装 post_openjdk_hint 对应的独立处理逻辑。
post_openjdk_hint() {
  warm_echo "openjdk 更新完成后，如需让系统 java 指向 Homebrew openjdk，可按需执行："
  warm_echo '  sudo ln -sfn "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk.jdk'
  warm_echo "如果使用 jenv 管理 Java，推荐执行："
  warm_echo '  jenv add "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk/Contents/Home"'
}
# 封装 jobs_update_source_nvm_if_needed 对应的独立处理逻辑。
jobs_update_source_nvm_if_needed() {
  if jobs_update_has nvm; then
    return 0
  fi

  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  if [[ -s "$nvm_dir/nvm.sh" ]]; then
    source "$nvm_dir/nvm.sh"
  fi
}
# 解析并返回后续流程需要的目标信息。
get_node_major_version() {
  if ! jobs_update_has node; then
    echo "0"
    return 0
  fi

  local version=""
  version="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
  [[ -n "$version" ]] && echo "$version" || echo "0"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_node_for_opencli() {
  local major=""
  major="$(get_node_major_version)"

  if (( major >= 21 )); then
    success_echo "Node.js 版本满足 OpenCLI 要求：$(node --version)"
    return 0
  fi

  warn_echo "OpenCLI 需要 Node.js >= 21，当前版本：$(node --version 2>/dev/null || echo '未安装')"
  warn_echo "update.command 不会静默安装 Node，请先通过 Homebrew / nvm 升级 Node 后重试。"
  return 1
}
# 封装 jobs_update_find_external_command 对应的独立处理逻辑。
jobs_update_find_external_command() {
  local command_name="$1"
  local path_dir=""
  local candidate=""
  local candidate_real=""
  local script_real=""

  if [[ -n "${SCRIPT_PATH:-}" && -e "$SCRIPT_PATH" ]]; then
    script_real="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd -P)/$(basename "$SCRIPT_PATH")"
  fi

  for path_dir in ${(s.:.)PATH}; do
    [[ -n "$path_dir" ]] || continue
    candidate="$path_dir/$command_name"
    [[ -x "$candidate" ]] || continue

    candidate_real="$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P)/$(basename "$candidate")"
    [[ -n "$script_real" && "$candidate_real" == "$script_real" ]] && continue

    print -r -- "$candidate"
    return 0
  done

  return 1
}
# 执行 Android SDK licenses 接受流程，托管模式下自动输入 y。
jobs_update_run_flutter_android_licenses() {
  local desc="$1"
  shift

  local -a license_cmd=("$@")
  if (( ${#license_cmd[@]} == 0 )); then
    warn_echo "未提供 Android SDK licenses 命令，已跳过。"
    return 0
  fi

  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    note_echo "$desc"
    debug_echo "执行命令：yes | ${license_cmd[*]}"
    yes | "${license_cmd[@]}" 2>&1 | tee -a "$LOG_FILE"
    local exit_code=${pipestatus[2]}

    if (( exit_code == 0 )); then
      success_echo "$desc：完成"
    else
      warn_echo "$desc：失败（exit code: ${exit_code}）"
    fi

    return $exit_code
  fi

  if [[ ! -t 0 ]]; then
    warn_echo "当前不是交互式终端，已跳过：$desc"
    return 0
  fi

  jobs_update_run_cmd "$desc" "${license_cmd[@]}"
}
# 执行 Flutter doctor，并在检测到 Android license 未确认时引导接受许可。
jobs_update_run_flutter_doctor_and_android_licenses() {
  local label="$1"
  shift

  local -a flutter_base_cmd=("$@")
  if (( ${#flutter_base_cmd[@]} == 0 )); then
    warn_echo "未提供 Flutter 命令，跳过 Flutter doctor。"
    return 0
  fi

  local doctor_output_file=""
  doctor_output_file="$(mktemp -t jobs_update_flutter_doctor.XXXXXX)"
  local -a doctor_cmd=("${flutter_base_cmd[@]}" doctor -v)
  local -a license_cmd=("${flutter_base_cmd[@]}" doctor --android-licenses)

  note_echo "${label} doctor -v"
  debug_echo "执行命令：${doctor_cmd[*]}"
  "${doctor_cmd[@]}" 2>&1 | tee -a "$LOG_FILE" | tee "$doctor_output_file"
  local doctor_exit_code=${pipestatus[1]}

  if (( doctor_exit_code == 0 )); then
    success_echo "${label} doctor -v：完成"
  else
    warn_echo "${label} doctor -v：返回非 0（${doctor_exit_code}），继续检查 Android license 提示。"
  fi

  if grep -Eq "Android license status unknown|flutter doctor --android-licenses" "$doctor_output_file"; then
    warn_echo "检测到 Android license status unknown，将执行：${license_cmd[*]}"

    if grep -Fq "cmdline-tools component is missing" "$doctor_output_file"; then
      warm_echo "doctor 同时提示 Android cmdline-tools 缺失；若许可接受失败，请先在 Android Studio 安装 Command-line Tools。"
    fi

    jobs_update_run_flutter_android_licenses "接受 Android SDK licenses" "${license_cmd[@]}" || true
  fi

  rm -f "$doctor_output_file"
  return 0
}
# ---------- 内置自述 ----------
jobs_update_show_readme_and_wait() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    note_echo "托管模式：已跳过完整自述确认。" | jobs_intro_style body
    return 0
  fi

  clear 2>/dev/null || true

  {
    cat <<'EOFREADME' | jobs_intro_style auto
============================================================
update.command - macOS 开发环境升级维护
============================================================

核心原则：
  install.command 安装 / 初始化过的内容，update.command 必须体现并提供升级 / 刷新入口。

本脚本会按顺序询问是否更新：
  1. Xcode Command Line Tools / softwareupdate
  2. Xcode iOS 平台组件
  3. Oh My Zsh
  4. Homebrew
  5. brew cask：由 BREW_CASKS 自动生成
  6. brew formula：由 BREW_FORMULAE 自动生成
  7. Rosetta 2 状态检查
  8. FVM / Flutter SDK / flutter doctor
  9. Node / corepack / npm 基础维护
 10. npm 全局包：quicktype
 11. npm 全局包：OpenCLI
 12. npm 全局包：CodeGraph
 13. Ruby / RubyGems
 14. gem 包：cocoapods
 15. Python / pip
 16. Dart pub 缓存
 17. Git LFS 初始化与大文件参数
 18. JobsKits 仓库：JobsSoftware.MacOS、JobsMacEnvVarConfig
 19. 手动下载页：VS Code、Android Studio、Python

交互规则：
  - 直接回车：执行当前升级 / 刷新项
  - 输入任意字符后回车：跳过当前项
  - 单项失败：记录警告，继续后续项
  - 工具不存在：提示回到 install.command 补装，不在 update 中静默安装
  - Homebrew：brew update 遇到 formulae.brew.sh API 下载失败时，会自动使用 HOMEBREW_NO_INSTALL_FROM_API=1 降级重试
  - Homebrew 下载：全局测速选择 IPv4 / IPv6；正式下载持续低速时自动换线，无需人工选择
  - 第三方 tap：检测到 Homebrew tap trust 策略时，会先信任脚本维护的指定 tap 后再执行升级

当前 BREW_CASKS：
EOFREADME

    local pkg
    for pkg in "${BREW_CASKS[@]}"; do
      echo "  - ${pkg}" | jobs_intro_style body
    done

    cat <<'EOFREADME' | jobs_intro_style auto

当前 BREW_FORMULAE：
EOFREADME

    for pkg in "${BREW_FORMULAE[@]}"; do
      echo "  - ${pkg}" | jobs_intro_style body
    done

    cat <<'EOFREADME' | jobs_intro_style auto

日志路径：/tmp/update.log
============================================================
EOFREADME
  } | tee -a "$LOG_FILE" | jobs_intro_style auto

  if [[ -t 0 && "${JOBS_MAC_ENV_SKIP_README:-}" != "1" ]]; then
    echo "" | jobs_intro_style body
    local _answer=""
    IFS= read -r "_answer?👉 已阅读自述文件，按回车开始逐项更新；按 Ctrl+C 取消："
  fi
}
# ---------- 更新项：系统 / Xcode / Shell ----------
jobs_update_clt() {
  if ! xcode-select -p >/dev/null 2>&1; then
    warn_echo "未检测到 Xcode Command Line Tools。update.command 不负责安装，请运行 install.command 补装。"
    return 0
  fi

  success_echo "Xcode Command Line Tools 已存在：$(xcode-select -p)"

  if jobs_update_has xcodebuild; then
    jobs_update_run_sudo_cmd "接受 Xcode License" xcodebuild -license accept || true
  else
    warn_echo "未检测到 xcodebuild，跳过 Xcode License 接受步骤"
  fi

  warn_echo "softwareupdate --install --all 可能安装 macOS 可用系统更新，耗时较长。"
  jobs_update_run_sudo_cmd "安装 macOS 可用软件更新" softwareupdate --install --all || true
}
# 封装 jobs_update_xcode_ios_platform 对应的独立处理逻辑。
jobs_update_xcode_ios_platform() {
  if ! jobs_update_has xcodebuild; then
    warn_echo "未检测到 xcodebuild，无法更新 Xcode iOS 平台组件。"
    return 0
  fi

  if xcodebuild -showsdks 2>/dev/null | grep -E "iphoneos|iphonesimulator" >/dev/null 2>&1; then
    success_echo "检测到 iOS SDK，开始刷新 iOS 平台组件。"
  else
    warn_echo "未检测到 iOS SDK，将尝试通过 xcodebuild 下载 iOS 平台组件。"
  fi

  jobs_update_run_sh "清理 Xcode 缓存" 'rm -rf ~/Library/Caches/com.apple.dt.Xcode' || true
  jobs_update_run_sh "清理 CoreSimulator 缓存" 'rm -rf ~/Library/Developer/CoreSimulator/Caches' || true
  jobs_update_run_cmd "下载 / 更新 iOS 模拟器平台" xcodebuild -downloadPlatform iOS -verbose || true
}
# 封装 jobs_update_oh_my_zsh 对应的独立处理逻辑。
jobs_update_oh_my_zsh() {
  if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    warn_echo "未检测到 Oh My Zsh。update.command 不负责安装，请运行 install.command 补装。"
    return 0
  fi

  success_echo "Oh My Zsh 已存在：${HOME}/.oh-my-zsh"

  if [[ -f "${HOME}/.oh-my-zsh/tools/upgrade.sh" ]]; then
    jobs_update_run_sh "更新 Oh My Zsh" "ZSH='${HOME}/.oh-my-zsh' '${HOME}/.oh-my-zsh/tools/upgrade.sh'" || true
  else
    warn_echo "未找到 Oh My Zsh upgrade.sh，跳过更新"
  fi
}
# 封装 jobs_update_rosetta 对应的独立处理逻辑。
jobs_update_rosetta() {
  if [[ "$(uname -m)" != "arm64" ]]; then
    info_echo "当前不是 Apple Silicon，Rosetta 2 不适用。"
    return 0
  fi

  if /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    success_echo "Rosetta 2 已安装。Rosetta 2 通常通过 macOS 系统更新维护，无独立 upgrade 命令。"
  else
    warn_echo "未检测到 Rosetta 2。update.command 不负责安装，请运行 install.command 补装。"
  fi
}
# ---------- 更新项：Homebrew ----------
jobs_update_homebrew() {
  if ! require_brew_or_skip; then
    return 0
  fi

  jobs_update_trust_configured_brew_taps
  jobs_update_run_brew_update || true
  jobs_update_run_brew_upgrade || true
  jobs_update_run_brew_cask_upgrade || true
  jobs_update_run_cmd "brew cleanup（清理旧版本缓存）" brew cleanup || true
  jobs_update_run_cmd "brew doctor（检查 Homebrew 健康状态）" brew doctor || true
  jobs_update_run_cmd "brew -v（输出 Homebrew 版本）" brew -v || true
}
# 封装 brew_formula_install_arg 对应的独立处理逻辑。
brew_formula_install_arg() {
  local formula_name="$1"

  case "$formula_name" in
    go-task) echo "go-task/tap/go-task" ;;
    *) echo "$formula_name" ;;
  esac
}
# 封装 brew_formula_tap_name 对应的独立处理逻辑。
brew_formula_tap_name() {
  local formula_name="$1"

  case "$formula_name" in
    fvm) echo "leoafarias/fvm" ;;
    go-task) echo "go-task/tap" ;;
    *) echo "" ;;
  esac
}
# 按当前 Homebrew 信任策略确认第三方 tap，避免已开启 tap trust 时直接拒绝加载。
brew_trust_tap_if_required() {
  local tap_name="$1"

  [[ -n "$tap_name" ]] || return 0

  if ! brew help trust >/dev/null 2>&1; then
    return 0
  fi

  if brew trust --json=v1 2>/dev/null | grep -Fq "\"${tap_name:l}\""; then
    success_echo "Homebrew Tap 已信任：${tap_name}"
    return 0
  fi

  jobs_update_run_cmd "信任 Homebrew Tap：${tap_name}" brew trust "$tap_name" || true
}
# 在全局 brew upgrade 前信任脚本维护的第三方 tap，避免扫描阶段先跳过第三方 formula/cask。
jobs_update_trust_configured_brew_taps() {
  local pkg=""
  local tap_name=""
  local trusted_taps=()

  for pkg in "${BREW_FORMULAE[@]}"; do
    tap_name="$(brew_formula_tap_name "$pkg")"
    [[ -n "$tap_name" ]] || continue
    (( ${trusted_taps[(Ie)$tap_name]} > 0 )) && continue
    trusted_taps+=("$tap_name")
    brew_trust_tap_if_required "$tap_name"
  done

  for pkg in "${BREW_CASKS[@]}"; do
    tap_name="$(brew_cask_tap_name "$pkg")"
    [[ -n "$tap_name" ]] || continue
    (( ${trusted_taps[(Ie)$tap_name]} > 0 )) && continue
    trusted_taps+=("$tap_name")
    brew_trust_tap_if_required "$tap_name"
  done
}
# 封装 brew_formula_after_update 对应的独立处理逻辑。
brew_formula_after_update() {
  local formula_name="$1"

  case "$formula_name" in
    rbenv) ensure_rbenv_init ;;
    jenv) ensure_jenv_init ;;
    openjdk|openjdk@17) post_openjdk_hint ;;
    fzf) setup_fzf_shellenv ;;
    *) return 0 ;;
  esac
}
# 封装 brew_cask_tap_name 对应的独立处理逻辑。
brew_cask_tap_name() {
  local cask_name="$1"

  case "$cask_name" in
    github-store) echo "OpenHub-Store/tap" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_cask_install_hint 对应的独立处理逻辑。
brew_cask_install_hint() {
  local cask_name="$1"

  case "$cask_name" in
    github-store)
      warm_echo "补装命令：brew tap OpenHub-Store/tap"
      warm_echo "补装命令：brew install --cask github-store"
      ;;
    *) return 0 ;;
  esac
}
# 封装 jobs_update_github_store_after_update 对应的独立处理逻辑。
jobs_update_github_store_after_update() {
  local app_path="/Applications/GitHub-Store.app"

  if [[ -d "$app_path" ]]; then
    jobs_update_run_cmd "解除 GitHub-Store.app quarantine 标记" xattr -dr com.apple.quarantine "$app_path" || true
  else
    warn_echo "未找到 ${app_path}，跳过 quarantine 标记清理。"
  fi
}
# 仅在 Dart 通过 Flutter 官方签名校验后，解除 Homebrew Cask 传播到 Flutter SDK 的隔离标记。
jobs_update_flutter_release_verified_quarantine() {
  local flutter_command=""
  local flutter_root=""
  local dart_binary=""
  local signature_info=""
  local remaining_quarantine=""

  flutter_command="$(command -v flutter 2>/dev/null || true)"
  [[ -n "$flutter_command" ]] || return 0

  flutter_command="$(realpath "$flutter_command" 2>/dev/null || true)"
  [[ -n "$flutter_command" && -f "$flutter_command" ]] || return 0

  flutter_root="$(cd "$(dirname "$flutter_command")/.." 2>/dev/null && pwd -P || true)"
  dart_binary="${flutter_root}/bin/cache/dart-sdk/bin/dart"
  if [[ ! -x "$dart_binary" ]]; then
    warn_echo "未找到 Flutter SDK 内的 Dart 二进制文件，跳过 quarantine 标记清理。"
    return 0
  fi

  if ! /usr/bin/codesign --verify --strict "$dart_binary" >/dev/null 2>&1; then
    warn_echo "Dart 代码签名校验失败，为避免降低系统安全性，保留 Flutter SDK 的 quarantine 标记。"
    return 1
  fi

  signature_info="$(/usr/bin/codesign -dv --verbose=4 "$dart_binary" 2>&1 || true)"
  if ! print -r -- "$signature_info" | grep -Fq 'Authority=Developer ID Application: FLUTTER.IO LLC (S8QB4VV633)'; then
    warn_echo "Dart 签名方不是预期的 FLUTTER.IO LLC，保留 Flutter SDK 的 quarantine 标记。"
    return 1
  fi

  if ! find "$flutter_root" -xattrname com.apple.quarantine -print -quit 2>/dev/null | grep -Fq '/'; then
    success_echo "Flutter SDK 无 quarantine 标记，无需处理。"
    return 0
  fi

  /usr/bin/xattr -dr com.apple.quarantine "$flutter_root" 2>/dev/null || true
  find "$flutter_root" -type l -xattrname com.apple.quarantine -print0 2>/dev/null |
    while IFS= read -r -d '' quarantined_link; do
      /usr/bin/xattr -d -s com.apple.quarantine "$quarantined_link" 2>/dev/null || true
    done
  remaining_quarantine="$(find "$flutter_root" -xattrname com.apple.quarantine -print -quit 2>/dev/null || true)"
  if [[ -n "$remaining_quarantine" ]]; then
    warn_echo "Flutter SDK 仍存在 quarantine 标记：${remaining_quarantine}"
    return 1
  fi

  success_echo "已验证 FLUTTER.IO LLC 官方签名，并解除 Flutter SDK quarantine 标记。"
}
# 封装 brew_cask_after_update 对应的独立处理逻辑。
brew_cask_after_update() {
  local cask_name="$1"

  case "$cask_name" in
    flutter) jobs_update_flutter_release_verified_quarantine || true ;;
    github-store) jobs_update_github_store_after_update ;;
    *) return 0 ;;
  esac
}
# 封装 brew_cask_local_app_path 对应的独立处理逻辑。
brew_cask_local_app_path() {
  local cask_name="$1"

  case "$cask_name" in
    vlc) echo "/Applications/VLC.app" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_cask_local_app_exists 对应的独立处理逻辑。
brew_cask_local_app_exists() {
  local cask_name="$1"
  local app_path=""

  app_path="$(brew_cask_local_app_path "$cask_name")"
  [[ -n "$app_path" && -d "$app_path" ]]
}
# 封装 jobs_update_brew_formula_one 对应的独立处理逻辑。
jobs_update_brew_formula_one() {
  local formula_name="$1"
  local install_arg=""
  local tap_name=""

  if ! require_brew_or_skip; then
    return 0
  fi

  install_arg="$(brew_formula_install_arg "$formula_name")"
  tap_name="$(brew_formula_tap_name "$formula_name")"

  if ! brew list --formula --versions "$formula_name" >/dev/null 2>&1; then
    warn_echo "未安装 brew formula：${formula_name}，跳过升级。请运行 install.command 补装。"
    return 0
  fi

  if [[ -n "$tap_name" ]]; then
    brew_trust_tap_if_required "$tap_name"
    jobs_update_run_cmd "确认 Homebrew Tap：${tap_name}" brew tap "$tap_name" || true
  fi

  jobs_update_run_brew_adaptive_cmd "升级 brew formula：${formula_name}" plain brew upgrade "$install_arg" || true
  brew_formula_after_update "$formula_name"
}
# 封装 jobs_update_brew_formulae 对应的独立处理逻辑。
jobs_update_brew_formulae() {
  local pkg
  for pkg in "${BREW_FORMULAE[@]}"; do
    echo ""
    highlight_echo "brew formula：${pkg}"
    jobs_update_brew_formula_one "$pkg"
  done
}
# 封装 jobs_update_brew_cask_one 对应的独立处理逻辑。
jobs_update_brew_cask_one() {
  local cask_name="$1"
  local tap_name=""

  if ! require_brew_or_skip; then
    return 0
  fi

  tap_name="$(brew_cask_tap_name "$cask_name")"
  if [[ -n "$tap_name" ]]; then
    brew_trust_tap_if_required "$tap_name"
    jobs_update_run_cmd "确认 Homebrew Tap：${tap_name}" brew tap "$tap_name" || true
  fi

  if ! brew list --cask --versions "$cask_name" >/dev/null 2>&1; then
    if brew_cask_local_app_exists "$cask_name"; then
      local app_path=""
      app_path="$(brew_cask_local_app_path "$cask_name")"
      success_echo "已检测到本机 App：${app_path}"
      warn_echo "Homebrew 未登记 brew cask：${cask_name}，但本机已有 App，跳过升级。"
      return 0
    fi

    warn_echo "未安装 brew cask：${cask_name}，跳过升级。请运行 install.command 补装。"
    brew_cask_install_hint "$cask_name"
    return 0
  fi

  jobs_update_run_brew_adaptive_cmd "升级 brew cask：${cask_name}" plain brew upgrade --cask "$cask_name" || true
  brew_cask_after_update "$cask_name"
}
# 封装 jobs_update_brew_casks 对应的独立处理逻辑。
jobs_update_brew_casks() {
  local pkg
  for pkg in "${BREW_CASKS[@]}"; do
    echo ""
    highlight_echo "brew cask：${pkg}"
    jobs_update_brew_cask_one "$pkg"
  done
}
# ---------- 更新项：语言 / 包管理 ----------
jobs_update_fvm_flutter() {
  local external_flutter=""

  if jobs_update_has brew && brew list --formula fvm >/dev/null 2>&1; then
    jobs_update_brew_formula_one fvm
  elif jobs_update_has dart; then
    jobs_update_run_cmd "升级 FVM（Dart pub global）" dart pub global activate fvm || true
  else
    warn_echo "未检测到 brew formula fvm 或 dart，跳过 FVM 更新"
  fi

  if external_flutter="$(jobs_update_find_external_command flutter 2>/dev/null)"; then
    jobs_update_run_cmd "Flutter upgrade" "$external_flutter" upgrade || true
    jobs_update_flutter_release_verified_quarantine || true
    jobs_update_run_flutter_doctor_and_android_licenses "Flutter" "$external_flutter" || true
  elif jobs_update_has fvm; then
    jobs_update_run_flutter_doctor_and_android_licenses "FVM Flutter" fvm flutter || true
  else
    warn_echo "未检测到外部 flutter / fvm，跳过 Flutter SDK 更新"
  fi
}
# 封装 jobs_update_node_base 对应的独立处理逻辑。
jobs_update_node_base() {
  jobs_update_source_nvm_if_needed

  if jobs_update_has nvm; then
    jobs_update_run_cmd "nvm 安装 / 更新 LTS" nvm install --lts --reinstall-packages-from=current || true
    jobs_update_run_cmd "nvm 设置 default=LTS" nvm alias default 'lts/*' || true
    jobs_update_run_cmd "nvm use default" nvm use default || true
  elif jobs_update_has node; then
    success_echo "检测到 Node：$(node --version 2>/dev/null || true)"
    warn_echo "未检测到 nvm；Node 版本升级已由 Homebrew formula：node 更新项负责。"
  else
    warn_echo "未检测到 node / nvm，跳过 Node 基础维护"
  fi

  if jobs_update_has corepack; then
    jobs_update_run_cmd "启用 corepack" corepack enable || true
  fi

  if jobs_update_has npm; then
    jobs_update_run_cmd "升级 npm 自身" npm install -g npm@latest || true
    jobs_update_run_cmd "输出 npm 版本" npm -v || true
  fi
}
# 封装 jobs_update_npm_quicktype 对应的独立处理逻辑。
jobs_update_npm_quicktype() {
  if ! jobs_update_has npm; then
    warn_echo "npm 不存在，无法更新 quicktype。请先运行 install.command 安装 node。"
    return 0
  fi

  if npm list -g quicktype --depth=0 >/dev/null 2>&1; then
    jobs_update_run_npm_global_cmd "更新 npm 全局包 quicktype" "quicktype" update -g quicktype || true
  else
    warn_echo "未检测到 npm 全局包 quicktype，跳过升级。请运行 install.command 补装。"
  fi
}
# 封装 jobs_update_npm_opencli 对应的独立处理逻辑。
jobs_update_npm_opencli() {
  if ! jobs_update_has npm; then
    warn_echo "npm 不存在，无法更新 OpenCLI。请先运行 install.command 安装 node。"
    return 0
  fi

  if ! ensure_node_for_opencli; then
    return 0
  fi

  if npm list -g @jackwener/opencli --depth=0 >/dev/null 2>&1; then
    jobs_update_run_npm_global_cmd "更新 npm 全局包 OpenCLI" "@jackwener/opencli" install -g @jackwener/opencli@latest || true
  else
    warn_echo "未检测到 npm 全局包 OpenCLI，跳过升级。请运行 install.command 补装。"
  fi

  if jobs_update_has opencli; then
    jobs_update_run_cmd "输出 OpenCLI 版本" opencli --version || true
    warm_echo "OpenCLI 浏览器自动化还需要手动维护 Browser Bridge 扩展，可执行：opencli doctor"
  else
    warn_echo "当前 PATH 仍找不到 opencli，建议重新打开终端或检查 npm global bin。"
  fi
}
# 封装 jobs_update_npm_codegraph 对应的独立处理逻辑。
jobs_update_npm_codegraph() {
  if ! jobs_update_has npm; then
    warn_echo "npm 不存在，无法更新 CodeGraph。请先运行 install.command 安装 node。"
    return 0
  fi

  if npm list -g @colbymchenry/codegraph --depth=0 >/dev/null 2>&1; then
    success_echo "检测到 npm 全局包 CodeGraph，开始升级到 npm latest。"
  elif jobs_update_has codegraph; then
    warn_echo "检测到 codegraph 命令，但未检测到 npm 全局包 @colbymchenry/codegraph。"
    warm_echo "将尝试用 npm 接管并升级 CodeGraph；如果你想保留非 npm 安装方式，可跳过本项。"
  else
    warn_echo "未检测到 npm 全局包 CodeGraph，跳过升级。请运行 install.command 补装。"
    return 0
  fi

  if ! jobs_update_run_cmd "更新 npm 全局包 CodeGraph" npm install -g @colbymchenry/codegraph@latest; then
    warn_echo "CodeGraph npm 升级失败。若日志里是 EACCES 权限问题，请优先修复 npm 全局目录权限，或手动执行：sudo npm install -g @colbymchenry/codegraph@latest"
    return 0
  fi

  if jobs_update_has codegraph; then
    jobs_update_run_cmd "输出 CodeGraph 版本" codegraph --version || true
    jobs_update_run_cmd "刷新 CodeGraph Agent 配置" codegraph install --yes || true
    warm_echo "提示：已存在项目的 .codegraph/codegraph.db 不会在这里强制重建；进入具体项目后可按需执行 codegraph index --force。"
  else
    warn_echo "CodeGraph 已尝试升级，但当前 PATH 仍找不到 codegraph。建议重新打开终端或检查 npm global bin。"
  fi
}
# 封装 jobs_update_ruby_base 对应的独立处理逻辑。
jobs_update_ruby_base() {
  if jobs_update_has rbenv; then
    ensure_rbenv_init
    jobs_update_run_cmd "rbenv rehash" rbenv rehash || true
  fi

  if jobs_update_has gem; then
    jobs_update_run_cmd "gem update --system" gem update --system || true
    jobs_update_run_cmd "gem update" gem update || true
  else
    warn_echo "未检测到 gem，跳过 RubyGems 更新"
  fi
}
# 封装 jobs_update_gem_cocoapods 对应的独立处理逻辑。
jobs_update_gem_cocoapods() {
  local gem_home=""

  if ! jobs_update_has gem; then
    warn_echo "gem 不存在，无法更新 cocoapods。请先确认 Ruby 环境。"
    return 0
  fi

  if gem list -i cocoapods >/dev/null 2>&1; then
    gem_home="$(gem env home 2>/dev/null || true)"
    if [[ -n "$gem_home" && -w "$gem_home" ]]; then
      jobs_update_run_cmd "更新 gem 包 cocoapods" gem update cocoapods || true
    else
      jobs_update_run_sudo_cmd "更新系统 gem 包 cocoapods" gem update cocoapods || true
    fi
  else
    warn_echo "未检测到 gem 包 cocoapods，跳过升级。请运行 install.command 补装。"
  fi

  if jobs_update_has pod; then
    jobs_update_run_cmd "pod repo update" pod repo update || true
  fi
}
# 封装 jobs_update_python_base 对应的独立处理逻辑。
jobs_update_python_base() {
  if jobs_update_has pyenv; then
    if pyenv commands | grep -qx update; then
      jobs_update_run_cmd "pyenv update" pyenv update || true
    else
      warn_echo "pyenv-update 插件不存在，跳过 pyenv update"
    fi
    jobs_update_run_cmd "pyenv rehash" pyenv rehash || true
  fi

  if jobs_update_has pipx; then
    jobs_update_run_cmd "pipx upgrade-all" pipx upgrade-all || true
  fi

  if jobs_update_has python3; then
    jobs_update_run_cmd "python3 pip 自升级" python3 -m pip install --upgrade pip || true
  elif jobs_update_has python; then
    jobs_update_run_cmd "python pip 自升级" python -m pip install --upgrade pip || true
  else
    warn_echo "未检测到 Python，跳过 Python 更新"
  fi
}
# 封装 jobs_update_pub_cache 对应的独立处理逻辑。
jobs_update_pub_cache() {
  if jobs_update_has dart; then
    jobs_update_run_cmd "Dart pub global list" dart pub global list || true
    jobs_update_run_cmd "Dart pub cache repair" dart pub cache repair || true
  else
    warn_echo "未检测到 dart，跳过 Dart pub cache 更新"
  fi
}
# ---------- 更新项：Git / JobsKits / 手动下载页 ----------
jobs_update_git_lfs_init() {
  if ! jobs_update_has git; then
    warn_echo "git 不存在，无法刷新 Git LFS。请先安装 Xcode Command Line Tools 或 git。"
    return 0
  fi

  if ! git lfs version >/dev/null 2>&1; then
    warn_echo "git-lfs 不存在，无法初始化。请先运行 install.command 安装 brew formula：git-lfs。"
    return 0
  fi

  jobs_update_run_cmd "初始化 / 刷新 Git LFS" git lfs install || true
  jobs_update_run_cmd "配置 Git core.compression=0" git config --global core.compression 0 || true
  jobs_update_run_cmd "配置 Git http.postBuffer=524288000" git config --global http.postBuffer 524288000 || true
}
# 封装 jobs_update_repo 对应的独立处理逻辑。
jobs_update_repo() {
  local repo_name="$1"
  local repo_url="$2"
  local target_dir="$3"

  if [[ -d "${target_dir}/.git" ]]; then
    jobs_update_run_sh "更新仓库：${repo_name}" "cd '${target_dir}' && git pull --ff-only" || true
    return 0
  fi

  warn_echo "未检测到仓库：${target_dir}"
  warm_echo "update.command 不负责克隆新仓库。需要补装时请运行 install.command。"
  gray_echo "仓库地址：${repo_url}"
}
# 封装 jobs_update_jobs_repos 对应的独立处理逻辑。
jobs_update_jobs_repos() {
  if ! jobs_update_has git; then
    warn_echo "git 不存在，跳过 JobsKits 仓库更新。"
    return 0
  fi

  jobs_update_repo "JobsSoftware.MacOS" "$JOBS_SOFTWARE_REPO" "${JOBS_WORKSPACE}/JobsSoftware.MacOS"
  jobs_update_repo "JobsMacEnvVarConfig" "$JOBS_ENV_REPO" "${JOBS_WORKSPACE}/JobsMacEnvVarConfig"

  local install_script="${JOBS_WORKSPACE}/JobsMacEnvVarConfig/install.command/install.command"
  if [[ -f "$install_script" ]]; then
    jobs_update_run_cmd "确认 JobsMacEnvVarConfig/install.command 可执行权限" chmod +x "$install_script" || true
    warn_echo "不会执行 ${install_script}，避免 install.command 递归调用。"
  fi
}
# 封装 open_download_page 对应的独立处理逻辑。
open_download_page() {
  local name="$1"
  local url="$2"

  if ! jobs_update_has open; then
    warn_echo "open 命令不存在，无法打开：${name}"
    return 0
  fi

  jobs_update_run_cmd "打开 ${name} 下载 / 更新页" open "$url" || true
}
# 封装 jobs_update_manual_download_pages 对应的独立处理逻辑。
jobs_update_manual_download_pages() {
  open_download_page "Visual Studio Code" "https://code.visualstudio.com/"
  open_download_page "Android Studio" "https://developer.android.com/studio?hl=zh-cn"
  open_download_page "Python" "https://www.python.org/downloads/"
}
# ---------- 命令实现 ----------
update() {
  local ran_count=0

  if jobs_update_prompt_run "是否更新 Xcode Command Line Tools / macOS softwareupdate？" "对应 install.command：Xcode Command Line Tools。"; then
    jobs_update_run_step "Xcode Command Line Tools / softwareupdate 更新" jobs_update_clt
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Xcode iOS 平台组件？" "对应 install.command：Xcode iOS 平台组件。"; then
    jobs_update_run_step "Xcode iOS 平台组件更新" jobs_update_xcode_ios_platform
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Oh My Zsh？" "对应 install.command：Oh My Zsh。"; then
    jobs_update_run_step "Oh My Zsh 更新" jobs_update_oh_my_zsh
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Homebrew？" "执行 brew update / upgrade / cask upgrade / cleanup / doctor。"; then
    jobs_update_run_step "Homebrew 更新" jobs_update_homebrew
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否逐项升级 install.command 中的 brew cask？" "覆盖 BREW_CASKS 内所有 cask；github-store 会确认 OpenHub-Store/tap 并解除 quarantine 标记。"; then
    jobs_update_run_step "brew cask 批量升级" jobs_update_brew_casks
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否逐项升级 install.command 中的 brew formula？" "覆盖 BREW_FORMULAE 内所有 formula。"; then
    jobs_update_run_step "brew formula 批量升级" jobs_update_brew_formulae
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否检查 Rosetta 2？" "Rosetta 2 无独立升级命令，只检查状态并说明维护方式。"; then
    jobs_update_run_step "Rosetta 2 状态检查" jobs_update_rosetta
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 FVM / Flutter？" "覆盖 install.command 中的 brew cask：flutter 与 brew formula：fvm 的后续 SDK 维护。"; then
    jobs_update_run_step "FVM / Flutter 更新" jobs_update_fvm_flutter
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否维护 Node / corepack / npm？" "覆盖 install.command 中的 brew formula：node / pnpm，并兼容 nvm。"; then
    jobs_update_run_step "Node / corepack / npm 维护" jobs_update_node_base
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 npm 全局包 quicktype？" "对应 install.command：npm 全局包 quicktype。"; then
    jobs_update_run_step "npm quicktype 更新" jobs_update_npm_quicktype
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 npm 全局包 OpenCLI？" "对应 install.command：npm 全局包 OpenCLI。"; then
    jobs_update_run_step "npm OpenCLI 更新" jobs_update_npm_opencli
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 npm 全局包 CodeGraph？" "对应 install.command：npm 全局包 CodeGraph；执行 npm install -g @colbymchenry/codegraph@latest，并刷新 Agent 配置。"; then
    jobs_update_run_step "npm CodeGraph 更新" jobs_update_npm_codegraph
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Ruby / RubyGems？" "覆盖 install.command 中的 brew formula：ruby / rbenv 的后续维护。"; then
    jobs_update_run_step "Ruby / RubyGems 更新" jobs_update_ruby_base
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 CocoaPods？" "对应 install.command：gem 包 cocoapods，并执行 pod repo update。"; then
    jobs_update_run_step "CocoaPods 更新" jobs_update_gem_cocoapods
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Python / pip？" "覆盖 install.command 中的 brew formula：python / python3 / uv 的后续维护。"; then
    jobs_update_run_step "Python / pip 更新" jobs_update_python_base
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否修复 Dart pub 缓存？" "覆盖 Flutter / FVM / Dart 生态的缓存维护。"; then
    jobs_update_run_step "Dart pub 缓存修复" jobs_update_pub_cache
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否刷新 Git LFS 初始化与大文件参数？" "对应 install.command：Git LFS 初始化。"; then
    jobs_update_run_step "Git LFS 初始化刷新" jobs_update_git_lfs_init
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 JobsKits 仓库？" "对应 install.command：JobsSoftware.MacOS、JobsMacEnvVarConfig。"; then
    jobs_update_run_step "JobsKits 仓库更新" jobs_update_jobs_repos
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否打开手动下载 / 更新页面？" "对应 install.command：VS Code、Android Studio、Python 手动下载页。"; then
    jobs_update_run_step "手动下载 / 更新页面" jobs_update_manual_download_pages
    (( ran_count++ ))
  fi

  echo ""
  print_divider
  if (( ran_count == 0 )); then
    warn_echo "没有执行任何更新项"
  else
    success_echo "update 执行完成，共执行 ${ran_count} 个更新项"
  fi
  info_echo "日志文件位置：${LOG_FILE}"
  print_divider
}
# ---------- 主流程统一收口 ----------
jobs_update_main() {
  # 展示脚本说明并等待用户确认影响范围。
  jobs_update_show_readme_and_wait
  # 执行更新或升级步骤，确保该动作不会被默认触发。
  update "$@"
  local exit_code=$?
  # 清理临时下载策略，并恢复用户原有的 Homebrew curl 环境。
  jobs_update_cleanup_network_strategy
  return $exit_code
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    note_echo "托管模式：已跳过脚本内置自述确认。" | jobs_intro_style title
    return 0
  fi

  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：update.command' | jobs_intro_style title
  print -r -- '核心用途：执行“update”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  jobs_update_parse_args "$@" # 解析运行参数，识别托管模式或帮助请求。
  local parse_exit_code=$?
  if (( parse_exit_code == 2 )); then
    return 0
  elif (( parse_exit_code != 0 )); then
    return $parse_exit_code
  fi
  jobs_update_prepare_unattended_mode || return $? # 启用无人值守的非交互提权策略。
  show_script_intro_and_wait || return $? # 展示脚本内置自述，并按运行入口完成防误触确认。
  jobs_update_main "$@" || return $? # 执行 jobs_update_main 对应的核心业务步骤。
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  set -u
  set -o pipefail
  setopt NO_NOMATCH
  : > "$LOG_FILE"
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    main "$@"
  fi
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
