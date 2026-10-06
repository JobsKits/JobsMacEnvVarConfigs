#!/bin/zsh
# 脚本自述：
# - 脚本名称：simios.command
# - 核心用途：执行“simios”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# JobsMacEnv function module / executable script.
# 作用：检测完整 Xcode 环境，然后下载 / 补齐 iOS Simulator Runtime。

# 说明：
# - 被 zsh/custom/local.zsh source 时，只注册 simios 函数，不自动执行。
# - 作为 ~/.local/bin/simios 或 Scripts/simios.command/simios.command 直接执行时，自动进入主流程。

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
_jobs_simios_module_file="${(%):-%N}"
# 按当前输出级别记录终端信息，并同步写入脚本日志。
_jobs_simios_cecho() {
  local color="$1"
  shift
  printf "%b%s%b\n" "$color" "$*" "${JOBS_SIMIOS_C_RESET:-\033[0m}"
}
# 封装 _jobs_simios_line 对应的独立处理逻辑。
_jobs_simios_line() {
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "────────────────────────────────────────"
}
# 封装 _jobs_simios_section 对应的独立处理逻辑。
_jobs_simios_section() {
  echo ""
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BOLD$JOBS_SIMIOS_C_CYAN" "▶ $1"
  _jobs_simios_line
}
# 封装 _jobs_simios_log 对应的独立处理逻辑。
_jobs_simios_log() {
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BLUE" "[simios] $1"
}
# 封装 _jobs_simios_ok 对应的独立处理逻辑。
_jobs_simios_ok() {
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GREEN" "[OK] $1"
}
# 封装 _jobs_simios_warn 对应的独立处理逻辑。
_jobs_simios_warn() {
  _jobs_simios_cecho "$JOBS_SIMIOS_C_YELLOW" "[WARN] $1"
}
# 封装 _jobs_simios_err 对应的独立处理逻辑。
_jobs_simios_err() {
  _jobs_simios_cecho "$JOBS_SIMIOS_C_RED" "[ERR] $1"
}
# 封装 _jobs_simios_pause_enter 对应的独立处理逻辑。
_jobs_simios_pause_enter() {
  local message="${1:-按回车继续...}"
  printf "%b%s%b" "$JOBS_SIMIOS_C_MAGENTA" "$message" "$JOBS_SIMIOS_C_RESET"
  local _input=""
  IFS= read -r _input
}
# 封装 _jobs_simios_ask_run 对应的独立处理逻辑。
_jobs_simios_ask_run() {
  local message="$1"
  local input=""
  printf "%b%s%b" "$JOBS_SIMIOS_C_MAGENTA" "${message}（回车跳过，输入任意字符后回车执行）：" "$JOBS_SIMIOS_C_RESET"
  IFS= read -r input
  [[ -n "$input" ]]
}
# 封装 _jobs_simios_run_root 对应的独立处理逻辑。
_jobs_simios_run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
_jobs_simios_show_readme_and_wait() {
  clear || true
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BOLD$JOBS_SIMIOS_C_CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BOLD$JOBS_SIMIOS_C_CYAN" "              simios" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BOLD$JOBS_SIMIOS_C_CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BLUE" "用途：检测完整 Xcode 环境，然后下载 / 补齐 iOS Simulator Runtime。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GREEN" "执行顺序：" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  1) 检测 macOS / Xcode.app 是否存在" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  2) 检测 xcodebuild 是否来自完整 Xcode，而不是只有 Command Line Tools" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  3) 检测 xcode-select 指向；不强制永久改系统，可临时使用 DEVELOPER_DIR" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  4) 检测 Xcode 首次启动组件 / license / 磁盘空间 / 网络连通" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  5) 最后由你决定是否执行 iOS 模拟器下载" | jobs_intro_style body
  echo "" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_YELLOW" "交互规则：" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  - 普通安装 / 更新 / 升级动作：回车跳过，输入任意字符后回车执行" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  - 必须修复项：脚本会明确说明原因，再让你继续" | jobs_intro_style body
  echo "" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GREEN" "核心下载命令：" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  xcodebuild -downloadPlatform iOS -verbose" | jobs_intro_style body
  echo "" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_YELLOW" "说明：" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  xcodebuild 常见 verbose 参数是单横线 -verbose；如果你的版本支持 --verbose，脚本会自动使用 --verbose。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  _jobs_simios_pause_enter "按回车开始体检..."
}
# 封装 _jobs_simios_require_macos 对应的独立处理逻辑。
_jobs_simios_require_macos() {
  _jobs_simios_section "系统检测"

  if [[ "$(uname -s)" != "Darwin" ]]; then
    _jobs_simios_err "当前不是 macOS，无法下载 Xcode iOS Simulator Runtime。"
    return 1
  fi

  _jobs_simios_ok "当前系统是 macOS。"
}
# 封装 _jobs_simios_collect_xcode_apps 对应的独立处理逻辑。
_jobs_simios_collect_xcode_apps() {
  local -a found
  local item=""

  for item in \
    /Applications/Xcode.app \
    /Applications/Xcode*.app \
    "${HOME}/Applications/Xcode.app" \
    "${HOME}/Applications/Xcode"*.app \
    /Applications/Xcodes/Xcode*.app; do
    if [[ -d "${item}/Contents/Developer" && -x "${item}/Contents/Developer/usr/bin/xcodebuild" ]]; then
      found+=("$item")
    fi
  done

  if (( ${#found[@]} > 0 )); then
    printf "%s\n" "${found[@]}" | awk '!seen[$0]++'
  fi
}
# 封装 _jobs_simios_choose_xcode_app 对应的独立处理逻辑。
_jobs_simios_choose_xcode_app() {
  _jobs_simios_section "Xcode 检测"

  local active_dev=""
  local active_app=""
  active_dev="$(xcode-select -p 2>/dev/null || true)"

  if [[ "$active_dev" == */Contents/Developer ]]; then
    active_app="${active_dev%/Contents/Developer}"
    if [[ -d "$active_app" && -x "${active_app}/Contents/Developer/usr/bin/xcodebuild" ]]; then
      JOBS_SIMIOS_XCODE_APP="$active_app"
      _jobs_simios_ok "当前 xcode-select 已指向完整 Xcode：$JOBS_SIMIOS_XCODE_APP"
      return 0
    fi
  fi

  local first_app=""
  first_app="$(_jobs_simios_collect_xcode_apps | head -n 1)"

  if [[ -z "$first_app" ]]; then
    _jobs_simios_err "未检测到完整 Xcode.app。"
    _jobs_simios_warn "只安装 Command Line Tools 没有现实意义：iOS Simulator Runtime 下载依赖完整 Xcode。"
    _jobs_simios_warn "请先安装 Xcode，再重新运行：simios"
    echo ""
    _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "建议路径：/Applications/Xcode.app"
    _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "安装来源：Mac App Store 或 Apple Developer 下载页"
    return 1
  fi

  JOBS_SIMIOS_XCODE_APP="$first_app"
  _jobs_simios_ok "检测到 Xcode：$JOBS_SIMIOS_XCODE_APP"
}
# 封装 _jobs_simios_maybe_check_xcode_update 对应的独立处理逻辑。
_jobs_simios_maybe_check_xcode_update() {
  echo ""
  if _jobs_simios_ask_run "Xcode 已存在，是否打开更新入口检查 Xcode 升级"; then
    if command -v mas >/dev/null 2>&1; then
      _jobs_simios_log "检测到 mas，尝试升级 App Store 版 Xcode。"
      mas upgrade 497799835 || open "macappstore://itunes.apple.com/app/id497799835" || true
    else
      _jobs_simios_warn "未检测到 mas。为了避免额外引入 Homebrew / mas，本脚本不自动安装它。"
      _jobs_simios_log "改为打开 App Store 的 Xcode 页面。"
      open "macappstore://itunes.apple.com/app/id497799835" || true
    fi
  else
    _jobs_simios_log "跳过 Xcode 升级检查。"
  fi
}
# 封装 _jobs_simios_prepare_developer_dir 对应的独立处理逻辑。
_jobs_simios_prepare_developer_dir() {
  _jobs_simios_section "xcode-select / DEVELOPER_DIR 检测"

  JOBS_SIMIOS_DEVELOPER_DIR_SELECTED="${JOBS_SIMIOS_XCODE_APP}/Contents/Developer"
  JOBS_SIMIOS_XCODEBUILD_BIN="${JOBS_SIMIOS_DEVELOPER_DIR_SELECTED}/usr/bin/xcodebuild"

  if [[ ! -x "$JOBS_SIMIOS_XCODEBUILD_BIN" ]]; then
    _jobs_simios_err "xcodebuild 不存在或不可执行：$JOBS_SIMIOS_XCODEBUILD_BIN"
    return 1
  fi

  export DEVELOPER_DIR="$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED"

  local active_dev=""
  active_dev="$(xcode-select -p 2>/dev/null || true)"

  _jobs_simios_ok "本次脚本使用：DEVELOPER_DIR=$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED"

  if [[ "$active_dev" == "$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED" ]]; then
    _jobs_simios_ok "系统 xcode-select 指向正确。"
  else
    _jobs_simios_warn "系统 xcode-select 当前指向：${active_dev:-未设置}"
    _jobs_simios_warn "脚本本次会临时使用 DEVELOPER_DIR，不强制修改你的全局设置。"
    if _jobs_simios_ask_run "是否永久切换 xcode-select 到当前 Xcode"; then
      _jobs_simios_run_root xcode-select -s "$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED"
      _jobs_simios_ok "已永久切换 xcode-select。"
    else
      _jobs_simios_log "跳过永久切换，仅本次脚本临时使用当前 Xcode。"
    fi
  fi
}
# 封装 _jobs_simios_show_xcode_version 对应的独立处理逻辑。
_jobs_simios_show_xcode_version() {
  _jobs_simios_section "Xcode 版本"
  "$JOBS_SIMIOS_XCODEBUILD_BIN" -version || {
    _jobs_simios_err "xcodebuild 无法正常输出版本。"
    return 1
  }
}
# 封装 _jobs_simios_check_xcodebuild_support 对应的独立处理逻辑。
_jobs_simios_check_xcodebuild_support() {
  _jobs_simios_section "xcodebuild 能力检测"

  local help_text=""
  help_text="$({ "$JOBS_SIMIOS_XCODEBUILD_BIN" -help || true; } 2>&1)"

  if ! printf "%s\n" "$help_text" | grep -q -- "downloadPlatform"; then
    _jobs_simios_err "当前 Xcode 的 xcodebuild 不支持 -downloadPlatform。"
    _jobs_simios_warn "这通常说明 Xcode 版本过旧，需要先升级 Xcode。"
    _jobs_simios_maybe_check_xcode_update
    return 1
  fi

  _jobs_simios_ok "支持 -downloadPlatform。"

  if printf "%s\n" "$help_text" | grep -q -- "--verbose"; then
    JOBS_SIMIOS_VERBOSE_ARG="--verbose"
  else
    JOBS_SIMIOS_VERBOSE_ARG="-verbose"
  fi

  _jobs_simios_ok "verbose 参数使用：$JOBS_SIMIOS_VERBOSE_ARG"
}
# 封装 _jobs_simios_ensure_first_launch 对应的独立处理逻辑。
_jobs_simios_ensure_first_launch() {
  _jobs_simios_section "Xcode 首次启动组件检测"

  local help_text=""
  help_text="$({ "$JOBS_SIMIOS_XCODEBUILD_BIN" -help || true; } 2>&1)"

  if printf "%s\n" "$help_text" | grep -q -- "checkFirstLaunchStatus"; then
    if "$JOBS_SIMIOS_XCODEBUILD_BIN" -checkFirstLaunchStatus >/dev/null 2>&1; then
      _jobs_simios_ok "Xcode 首次启动组件状态正常。"
    else
      _jobs_simios_warn "Xcode 首次启动组件未完成。"
      _jobs_simios_warn "这属于执行 xcodebuild 下载前的必要支援项，需要安装 / 初始化。"
      _jobs_simios_pause_enter "按回车执行：sudo xcodebuild -runFirstLaunch ..."
      _jobs_simios_run_root "$JOBS_SIMIOS_XCODEBUILD_BIN" -runFirstLaunch
      _jobs_simios_ok "首次启动组件已处理。"
    fi
  else
    _jobs_simios_warn "当前 xcodebuild 不支持 -checkFirstLaunchStatus。"
    if _jobs_simios_ask_run "是否执行一次 xcodebuild -runFirstLaunch 做初始化"; then
      _jobs_simios_run_root "$JOBS_SIMIOS_XCODEBUILD_BIN" -runFirstLaunch
      _jobs_simios_ok "已执行首次启动初始化。"
    else
      _jobs_simios_log "跳过首次启动初始化。"
    fi
  fi
}
# 封装 _jobs_simios_ensure_license 对应的独立处理逻辑。
_jobs_simios_ensure_license() {
  _jobs_simios_section "Xcode License 检测"

  if "$JOBS_SIMIOS_XCODEBUILD_BIN" -license check >/dev/null 2>&1; then
    _jobs_simios_ok "Xcode license 已同意。"
    return 0
  fi

  _jobs_simios_warn "Xcode license 尚未同意。"
  _jobs_simios_warn "不同意 license 时，xcodebuild 后续下载大概率会失败。"
  _jobs_simios_pause_enter "按回车进入交互式 license 确认：sudo xcodebuild -license ..."
  _jobs_simios_run_root "$JOBS_SIMIOS_XCODEBUILD_BIN" -license

  if "$JOBS_SIMIOS_XCODEBUILD_BIN" -license check >/dev/null 2>&1; then
    _jobs_simios_ok "Xcode license 已同意。"
  else
    _jobs_simios_err "license 仍未通过检查，停止执行。"
    return 1
  fi
}
# 封装 _jobs_simios_check_disk_space 对应的独立处理逻辑。
_jobs_simios_check_disk_space() {
  _jobs_simios_section "磁盘空间检测"

  local free_kb="0"
  local free_gb="0"
  free_kb="$(df -k "$HOME" | awk 'NR==2 {print $4}')"
  free_gb=$(( free_kb / 1024 / 1024 ))

  if (( free_gb >= 30 )); then
    _jobs_simios_ok "当前用户目录所在磁盘可用空间约 ${free_gb}GB。"
  elif (( free_gb >= 15 )); then
    _jobs_simios_warn "当前可用空间约 ${free_gb}GB，可能够用，但大型 runtime 可能吃紧。"
  else
    _jobs_simios_warn "当前可用空间约 ${free_gb}GB，iOS Simulator Runtime 下载很可能失败。"
  fi
}
# 封装 _jobs_simios_check_network 对应的独立处理逻辑。
_jobs_simios_check_network() {
  _jobs_simios_section "网络连通检测"

  if ! command -v curl >/dev/null 2>&1; then
    _jobs_simios_warn "未检测到 curl，跳过网络预检。macOS 正常情况下会自带 curl。"
    return 0
  fi

  if curl -Is --connect-timeout 10 https://developer.apple.com >/dev/null 2>&1; then
    _jobs_simios_ok "developer.apple.com 可连接。"
  else
    _jobs_simios_warn "developer.apple.com 连接预检失败。可能是网络、代理、VPN、DNS 或 Apple CDN 临时问题。"
    _jobs_simios_warn "这不是本地环境硬缺失，脚本不会自动改网络设置。"
  fi
}
# 封装 _jobs_simios_list_ios_runtimes 对应的独立处理逻辑。
_jobs_simios_list_ios_runtimes() {
  if DEVELOPER_DIR="$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED" xcrun simctl runtime list >/dev/null 2>&1; then
    DEVELOPER_DIR="$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED" xcrun simctl runtime list 2>/dev/null | grep -i "iOS" || true
  else
    DEVELOPER_DIR="$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED" xcrun simctl list runtimes 2>/dev/null | grep -i "iOS" || true
  fi
}
# 封装 _jobs_simios_show_existing_runtimes 对应的独立处理逻辑。
_jobs_simios_show_existing_runtimes() {
  _jobs_simios_section "现有 iOS Runtime"

  local runtimes=""
  runtimes="$(_jobs_simios_list_ios_runtimes)"

  if [[ -n "$runtimes" ]]; then
    _jobs_simios_ok "检测到 iOS Runtime："
    printf "%s\n" "$runtimes"
  else
    _jobs_simios_warn "未检测到 iOS Runtime，稍后建议执行下载。"
  fi
}
# 封装 _jobs_simios_run_download 对应的独立处理逻辑。
_jobs_simios_run_download() {
  _jobs_simios_section "下载 / 补齐 iOS Simulator Runtime"

  mkdir -p "$JOBS_SIMIOS_LOG_DIR"

  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "日志文件：$JOBS_SIMIOS_LOG_FILE"
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "将执行：xcodebuild -downloadPlatform iOS $JOBS_SIMIOS_VERBOSE_ARG"
  echo ""

  if ! _jobs_simios_ask_run "是否开始下载 / 补齐 iOS Simulator Runtime"; then
    _jobs_simios_log "已跳过下载。"
    return 0
  fi

  local -a args
  args=(-downloadPlatform iOS "$JOBS_SIMIOS_VERBOSE_ARG")

  set +e
  DEVELOPER_DIR="$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED" "$JOBS_SIMIOS_XCODEBUILD_BIN" "${args[@]}" 2>&1 | tee "$JOBS_SIMIOS_LOG_FILE"
  local command_status=${pipestatus[1]}
  set -e

  if (( command_status != 0 )); then
    _jobs_simios_err "下载命令失败，退出码：$command_status"
    _jobs_simios_warn "完整日志：$JOBS_SIMIOS_LOG_FILE"
    _jobs_simios_warn "常见原因：license 未同意、Xcode 未完成首次启动、网络 / CDN 异常、磁盘空间不足、Xcode 版本过旧。"
    return "$command_status"
  fi

  _jobs_simios_ok "iOS Simulator Runtime 下载 / 补齐命令执行完成。"
}
# 封装 _jobs_simios_final_report 对应的独立处理逻辑。
_jobs_simios_final_report() {
  _jobs_simios_section "完成报告"

  _jobs_simios_ok "脚本执行结束。"
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "日志路径：$JOBS_SIMIOS_LOG_FILE"
  echo ""
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GREEN" "当前 iOS Runtime："
  _jobs_simios_list_ios_runtimes || true
  echo ""
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "如果 Xcode UI 里暂时看不到新 runtime，重启 Xcode 后再看。"
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
_jobs_simios_main() {
  # 执行当前流程中的独立业务步骤：emulate。
  emulate -L zsh
  # 执行当前流程中的独立业务步骤：set。
  set -e
  # 执行当前流程中的独立业务步骤：set。
  set -o pipefail
  # 执行当前流程中的独立业务步骤：setopt。
  setopt NULL_GLOB

  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_RESET='\033[0m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_BOLD='\033[1m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_BLUE='\033[34m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_CYAN='\033[36m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_GREEN='\033[32m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_YELLOW='\033[33m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_MAGENTA='\033[35m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_RED='\033[31m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_GRAY='\033[90m'

  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_XCODE_APP=""
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_DEVELOPER_DIR_SELECTED=""
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_XCODEBUILD_BIN=""
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_VERBOSE_ARG="-verbose"
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_LOG_DIR="${HOME}/Library/Logs/simios"
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_LOG_FILE="${JOBS_SIMIOS_LOG_DIR}/simios-$(date '+%Y%m%d-%H%M%S').log"

  # 展示脚本说明并等待用户确认影响范围。
  _jobs_simios_show_readme_and_wait
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_require_macos
  # 执行当前流程中的独立业务步骤：_jobs_simios_choose_xcode_app。
  _jobs_simios_choose_xcode_app
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_maybe_check_xcode_update
  # 准备后续业务需要的配置、目录或运行上下文。
  _jobs_simios_prepare_developer_dir
  # 执行当前流程中的独立业务步骤：_jobs_simios_show_xcode_version。
  _jobs_simios_show_xcode_version
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_check_xcodebuild_support
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_ensure_first_launch
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_ensure_license
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_check_disk_space
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_check_network
  # 执行当前流程中的独立业务步骤：_jobs_simios_show_existing_runtimes。
  _jobs_simios_show_existing_runtimes
  # 执行当前流程中的独立业务步骤：_jobs_simios_run_download。
  _jobs_simios_run_download
  # 执行当前流程中的独立业务步骤：_jobs_simios_final_report。
  _jobs_simios_final_report
  # 执行当前流程中的独立业务步骤：_jobs_simios_pause_enter。
  _jobs_simios_pause_enter "按回车退出..."
}
# 终端入口：安装 JobsMacEnv 后可直接执行 simios
simios() {
  _jobs_simios_main "$@"
}

_jobs_simios_module_file_abs="${_jobs_simios_module_file:A}"
_jobs_simios_argv0_abs="${0:A}"
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：simios.command' | jobs_intro_style title
  print -r -- '核心用途：执行“simios”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    exit 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
}
# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  show_script_intro_and_wait # 展示脚本内置自述，并按运行入口完成防误触确认。
  _jobs_simios_main "$@" # 执行 _jobs_simios_main 对应的独立业务步骤。
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    if [[ "$_jobs_simios_module_file" == "$0" || "$_jobs_simios_module_file_abs" == "$_jobs_simios_argv0_abs" ]]; then
      main "$@"
    fi
  fi
  unset _jobs_simios_module_file _jobs_simios_module_file_abs _jobs_simios_argv0_abs 2>/dev/null || true
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
