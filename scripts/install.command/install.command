#!/bin/zsh
# 脚本自述：
# - 脚本名称：install.command
# - 核心用途：执行“install”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


# ============================================================
# install.command - macOS 新系统配置（fzf 菜单版）
# ============================================================
# 说明：
# 1. 适合 .command 双击运行，也可终端执行。
# 2. 启动后先显示内置 README，并等待回车确认。
# 3. 菜单使用 fzf 多选；如果新系统没有 fzf，会先提示安装 Homebrew / fzf。
# 4. 每个被选择的部件都会先自检：不存在就安装最新，存在就更新。
# 5. 第三方依赖已存在时，会统一确认一次是否升级，不再逐项询问。
# 6. 其他安装 / 更新动作执行前会强提示：回车执行，任意字符 + 回车跳过。
# 7. 注意：install 这个命令名与系统 /usr/bin/install 存在冲突风险。
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

# ---------- 全局状态 ----------
TOTAL_STAGES=0
CURRENT_STAGE=0
THIRD_PARTY_EXISTING_UPGRADE_CONFIRMED=""
readonly ALL_MENU_ITEM="✅ 全选安装"

readonly JOBS_SOFTWARE_REPO="https://github.com/JobsKits/JobsSoftware.MacOS.git"
readonly JOBS_ENV_REPO="https://github.com/JobsKits/JobsMacEnvVarConfig.git"
readonly JOBS_WORKSPACE="${HOME}/Desktop/JobsKits"

# ---------- Homebrew 第三方配置 ----------
# 只维护第三方名称即可。
# 例如：需要安装 brew install git-lfs，就写 git-lfs。
# 例如：需要安装 brew install --cask vlc，就写 vlc。
readonly -a BREW_CASKS=(
  hammerspoon
  flutter
  trex
  vlc
  jdownloader
  codex-app # 图形化界面
  codex # 终端使用
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
# 封装 pause_for_enter 对应的独立处理逻辑。
pause_for_enter() {
  local prompt="${1:-👉 请按回车继续，或按 Ctrl+C 取消...}"
  if [[ -t 0 && "${JOBS_MAC_ENV_SKIP_README:-}" != "1" ]]; then
    echo ""
    local answer=""
    read "answer?${prompt}"
  fi
}
# 收集并校验用户输入，决定后续执行路径。
confirm_execute() {
  local title="$1"
  local action_word="${2:-执行}"

  echo ""
  warn_echo "强提示：${title}"
  warm_echo "回车=${action_word}；输入任意字符后回车=跳过"

  if [[ ! -t 0 ]]; then
    warn_echo "当前不是交互式终端，已跳过：${title}"
    return 1
  fi

  local answer=""
  read "answer?> "

  if [[ -z "${answer}" ]]; then
    return 0
  fi

  warn_echo "已跳过：${title}"
  return 1
}
# 收集并校验用户输入，决定后续执行路径。
confirm_existing_third_party_upgrade_once() {
  if [[ "${THIRD_PARTY_EXISTING_UPGRADE_CONFIRMED}" == "1" ]]; then
    return 0
  fi

  if [[ "${THIRD_PARTY_EXISTING_UPGRADE_CONFIRMED}" == "0" ]]; then
    return 1
  fi

  if confirm_execute "已检测到部分第三方依赖已存在，是否统一升级已存在的 brew cask / brew formula / npm 全局包 / gem 包？" "统一升级"; then
    THIRD_PARTY_EXISTING_UPGRADE_CONFIRMED="1"
    success_echo "本轮已存在第三方依赖将统一执行升级，后续不再逐项询问。"
    return 0
  fi

  THIRD_PARTY_EXISTING_UPGRADE_CONFIRMED="0"
  warn_echo "本轮已存在第三方依赖将统一跳过升级，后续不再逐项询问。"
  return 1
}
# 封装 progress_step 对应的独立处理逻辑。
progress_step() {
  local step_name="$1"
  CURRENT_STAGE=$((CURRENT_STAGE + 1))
  echo ""

  if (( TOTAL_STAGES > 0 )); then
    highlight_echo "当前系统配置进度：${CURRENT_STAGE}/${TOTAL_STAGES} 👉 ${step_name}"
  else
    highlight_echo "当前系统配置 👉 ${step_name}"
  fi

  print_divider
}
# 执行已经拆分完成的独立业务步骤。
run_cmd() {
  local desc="$1"
  shift

  note_echo "${desc}"
  debug_echo "执行命令：$*"

  "$@"
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    success_echo "${desc}：完成"
  else
    error_echo "${desc}：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 执行已经拆分完成的独立业务步骤。
run_sh() {
  local desc="$1"
  local cmd="$2"

  note_echo "${desc}"
  debug_echo "执行命令：${cmd}"

  /bin/zsh -c "${cmd}"
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    success_echo "${desc}：完成"
  else
    error_echo "${desc}：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 封装 require_command 对应的独立处理逻辑。
require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1
}
# 执行 Flutter doctor，并在检测到 Android license 未确认时引导接受许可。
run_flutter_doctor_and_android_licenses() {
  local label="$1"
  shift

  local -a flutter_base_cmd=("$@")
  if (( ${#flutter_base_cmd[@]} == 0 )); then
    warn_echo "未提供 Flutter 命令，跳过 Flutter doctor。"
    return 0
  fi

  hash -r 2>/dev/null || true

  local command_name="${flutter_base_cmd[1]}"
  if ! require_command "${command_name}" && [[ ! -x "${command_name}" ]]; then
    warn_echo "未检测到 ${command_name}，跳过 ${label} doctor。"
    return 0
  fi

  local doctor_output_file=""
  doctor_output_file="$(mktemp -t jobs_install_flutter_doctor.XXXXXX)"
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

    if [[ -t 0 ]]; then
      run_cmd "接受 Android SDK licenses" "${license_cmd[@]}" || true
    else
      warn_echo "当前不是交互式终端，已跳过 Android SDK licenses 接受步骤。"
    fi
  fi

  rm -f "$doctor_output_file"
  return 0
}
# 解析并返回后续流程需要的目标信息。
get_node_major_version() {
  if ! require_command node; then
    echo "0"
    return 0
  fi

  local version=""
  version="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
  [[ -n "${version}" ]] && echo "${version}" || echo "0"
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

  if require_command brew; then
    run_cmd "通过 Homebrew 安装 / 升级 node" brew upgrade node || run_cmd "通过 Homebrew 安装 node" brew install node
    hash -r 2>/dev/null || true
    major="$(get_node_major_version)"
  fi

  if (( major >= 21 )); then
    success_echo "Node.js 已满足 OpenCLI 要求：$(node --version)"
    return 0
  fi

  error_echo "Node.js 仍低于 21，跳过 OpenCLI 安装。请先升级 Node.js 后重试。"
  return 1
}
# 解析并返回后续流程需要的目标信息。
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 检查当前运行条件是否满足后续流程要求。
check_url_access() {
  local url="$1"
  curl -I -L -s --connect-timeout 8 --max-time 15 "${url}" >/dev/null 2>&1
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
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  return 1
}
# 解析并返回后续流程需要的目标信息。
find_fzf_bin() {
  if command -v fzf >/dev/null 2>&1; then
    command -v fzf
    return 0
  fi

  local candidate
  for candidate in \
    /opt/homebrew/bin/fzf \
    /usr/local/bin/fzf \
    /opt/homebrew/opt/fzf/bin/fzf \
    /usr/local/opt/fzf/bin/fzf; do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  return 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_raw_github_access_or_exit() {
  info_echo "开始检查 raw.githubusercontent.com 网络连通性..."

  if check_url_access "https://raw.githubusercontent.com"; then
    success_echo "raw.githubusercontent.com 网络访问正常"
    return 0
  fi

  error_echo "当前无法访问 raw.githubusercontent.com。Homebrew / Oh My Zsh 安装大概率会失败。"
  warm_echo "请先处理网络问题，再重新运行脚本。"
  pause_for_enter "👉 网络未就绪。请按回车结束脚本..."
  exit 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_github_access_or_exit() {
  info_echo "开始检查 GitHub 网络连通性..."

  if check_url_access "https://github.com"; then
    success_echo "GitHub 网络访问正常"
    return 0
  fi

  error_echo "当前无法访问 GitHub。Jobs 仓库拉取会失败。"
  warm_echo "请先处理网络问题，再重新运行脚本。"
  pause_for_enter "👉 GitHub 不可访问。请按回车结束脚本..."
  exit 1
}
# 执行对应的环境配置或同步处理。
setup_brew_shellenv() {
  local brew_bin="$1"
  local shellenv_line="eval \"\$(${brew_bin} shellenv)\""

  if [[ ! -x "${brew_bin}" ]]; then
    error_echo "Homebrew 可执行文件不存在或不可执行：${brew_bin}"
    return 1
  fi

  local target_file
  for target_file in "${HOME}/.zprofile" "${HOME}/.zshrc"; do
    append_comment_once "# Homebrew shellenv" "${target_file}"
    append_once "${shellenv_line}" "${target_file}"
    success_echo "已确认 Homebrew 环境变量配置：${target_file}"
  done

  eval "$(${brew_bin} shellenv)"
  hash -r 2>/dev/null || true
}
# 执行对应的环境配置或同步处理。
setup_fzf_shellenv() {
  if ! require_command brew; then
    return 0
  fi

  local fzf_base
  fzf_base="$(brew --prefix fzf 2>/dev/null)"

  if [[ -n "${fzf_base}" && -d "${fzf_base}" ]]; then
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
  warm_echo "openjdk 安装 / 更新完成后，如需让系统 java 指向 Homebrew openjdk，可按需执行："
  warm_echo '  sudo ln -sfn "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk.jdk'
  warm_echo "如果使用 jenv 管理 Java，推荐执行："
  warm_echo '  jenv add "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk/Contents/Home"'
}
# ---------- 内置自述 ----------
jobs_install_show_readme_and_wait() {
  clear 2>/dev/null || true

  {
    cat <<'EOFREADME' | jobs_intro_style auto
============================================================
install.command - macOS 新系统配置（fzf 菜单版）
============================================================

这是 install.command 的内置自述，不读取同级 README.md。

核心原则：
  1. 不再一股脑安装。
  2. 启动后使用 fzf 输出多选菜单。
  3. 菜单额外提供“✅ 全选安装”。
  4. 每个部件都会先自检：
     - 不存在：安装最新版
     - 已存在：更新到最新版 / 刷新配置
  5. 第三方依赖已存在时统一确认一次是否升级，不再逐项询问：
     - brew cask
     - brew formula
     - npm 全局包
     - gem 包
  6. 其他安装 / 更新动作执行前都会强提示：
     - 直接回车：执行安装 / 更新
     - 输入任意字符后回车：跳过

Homebrew 第三方配置：
  - brew cask 只需要维护脚本顶部 BREW_CASKS 数组里的第三方名称。
  - brew formula 只需要维护脚本顶部 BREW_FORMULAE 数组里的第三方名称。
  - 菜单项会自动根据这两个数组生成。
  - 执行时会自动拼出 brew install / brew install --cask 命令。
  - 少数需要 tap / 后置初始化的 cask / formula，会由脚本内部自动处理，不需要写在数组里。

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

将支持选择的部件（菜单从上到下按此顺序显示）：
  - ✅ 全选安装
  - Xcode Command Line Tools
  - Xcode iOS 平台组件
  - Oh My Zsh
  - Homebrew
  - brew cask：由 BREW_CASKS 自动生成
  - brew formula：由 BREW_FORMULAE 自动生成
  - Rosetta 2
  - npm 全局包：quicktype
  - npm 全局包：OpenCLI
  - npm 全局包：CodeGraph
  - gem 包：cocoapods
  - Git LFS 初始化与大文件参数
  - JobsKits 仓库：JobsSoftware.MacOS、JobsMacEnvVarConfig
  - 手动下载页：VS Code、Android Studio、Python

启动菜单前置依赖：
  - 菜单依赖 fzf。
  - 如果 Homebrew / fzf 不存在，脚本会先提示你安装。
  - 这是为了让后续功能选择能够正常显示，不代表进入了全量安装。

说明：
  - 该命令名与系统 /usr/bin/install 有冲突风险。
  - 日志路径：/tmp/install.log
  - 部分步骤依赖 GitHub / raw.githubusercontent.com。
  - 部分 sudo 步骤可能要求输入系统密码。
  - 本脚本不会递归执行 JobsMacEnvVarConfig/install.command，避免自调用死循环。
============================================================
EOFREADME
  } | tee -a "$LOG_FILE" | jobs_intro_style auto

  pause_for_enter "👉 请确认没有误操作。按回车进入菜单准备流程，或按 Ctrl+C 取消..."
}
# ---------- 菜单前置依赖：Homebrew / fzf ----------
install_homebrew_without_menu() {
  ensure_raw_github_access_or_exit

  if ! confirm_execute "菜单依赖 Homebrew，当前未检测到 Homebrew，是否安装 Homebrew？" "安装"; then
    error_echo "没有 Homebrew 无法自动安装 fzf，也无法进入 fzf 菜单。"
    pause_for_enter "👉 请按回车退出..."
    exit 1
  fi

  run_sh \
    "安装 Homebrew" \
    '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

  local brew_bin=""
  if brew_bin="$(find_brew_bin)"; then
    setup_brew_shellenv "${brew_bin}"
  else
    error_echo "Homebrew 安装后仍未检测到 brew 命令，无法继续。"
    pause_for_enter "👉 请按回车退出..."
    exit 1
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_brew_for_menu() {
  local brew_bin=""

  if brew_bin="$(find_brew_bin)"; then
    setup_brew_shellenv "${brew_bin}"
    return 0
  fi

  install_homebrew_without_menu
}
# 检查当前运行条件是否满足后续流程要求。
ensure_fzf_for_menu() {
  local fzf_bin=""

  if fzf_bin="$(find_fzf_bin)"; then
    success_echo "fzf 已存在：${fzf_bin}"
    return 0
  fi

  if ! require_command brew; then
    error_echo "brew 不存在，无法安装 fzf。"
    pause_for_enter "👉 请按回车退出..."
    exit 1
  fi

  if ! confirm_execute "菜单依赖 fzf，当前未检测到 fzf，是否安装 fzf？" "安装"; then
    error_echo "没有 fzf 无法显示选择菜单。"
    pause_for_enter "👉 请按回车退出..."
    exit 1
  fi

  run_cmd "安装 fzf" brew install fzf
  setup_fzf_shellenv

  if fzf_bin="$(find_fzf_bin)"; then
    success_echo "fzf 安装完成：${fzf_bin}"
    return 0
  fi

  error_echo "fzf 安装后仍未检测到可执行文件，无法继续。"
  pause_for_enter "👉 请按回车退出..."
  exit 1
}
# 封装 prepare_menu_runtime 对应的独立处理逻辑。
prepare_menu_runtime() {
  highlight_echo "准备 fzf 菜单运行环境"
  print_divider

  ensure_brew_for_menu
  ensure_fzf_for_menu
}
# ---------- Homebrew 自检 ----------
require_brew_or_skip() {
  local brew_bin=""

  if brew_bin="$(find_brew_bin)"; then
    setup_brew_shellenv "${brew_bin}"
    return 0
  fi

  warn_echo "brew 不存在，当前部件无法继续。请先选择 Homebrew。"
  return 1
}
# 封装 brew_formula_installed 对应的独立处理逻辑。
brew_formula_installed() {
  local pkg="$1"
  brew list --formula --versions "${pkg}" >/dev/null 2>&1
}
# 封装 brew_cask_installed 对应的独立处理逻辑。
brew_cask_installed() {
  local pkg="$1"
  brew list --cask --versions "${pkg}" >/dev/null 2>&1
}
# 封装 brew_cask_local_app_path 对应的独立处理逻辑。
brew_cask_local_app_path() {
  local pkg="$1"

  case "${pkg}" in
    vlc) echo "/Applications/VLC.app" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_cask_local_app_exists 对应的独立处理逻辑。
brew_cask_local_app_exists() {
  local pkg="$1"
  local app_path=""

  app_path="$(brew_cask_local_app_path "${pkg}")"
  [[ -n "${app_path}" && -d "${app_path}" ]]
}
# ---------- 部件：Xcode Command Line Tools ----------
component_clt() {
  progress_step "Xcode Command Line Tools"

  if xcode-select -p >/dev/null 2>&1; then
    success_echo "Xcode Command Line Tools 已存在：$(xcode-select -p)"

    if confirm_execute "CLT 已存在，是否执行 Xcode License 接受，并通过 softwareupdate 安装可用更新？" "更新"; then
      if require_command xcodebuild; then
        run_cmd "接受 Xcode License" sudo xcodebuild -license accept
      else
        warn_echo "未检测到 xcodebuild，跳过 Xcode License 接受步骤"
      fi

      warn_echo "softwareupdate --install --all 可能安装系统可用更新，请确认你已经理解。"
      run_cmd "安装 macOS 可用软件更新" sudo softwareupdate --install --all
    fi

    return 0
  fi

  if confirm_execute "未检测到 Xcode Command Line Tools，是否安装？" "安装"; then
    run_cmd "安装 Xcode Command Line Tools" xcode-select --install
    warn_echo "如果系统弹出图形安装窗口，请完成安装后再次执行本脚本。"
  fi
}
# ---------- 部件：Xcode iOS 平台组件 ----------
component_xcode_ios_platform() {
  progress_step "Xcode iOS 平台组件"

  if ! require_command xcodebuild; then
    warn_echo "未检测到 xcodebuild，无法下载 iOS 平台组件。请先安装 Xcode / Command Line Tools。"
    return 0
  fi

  local action_word="安装"
  local desc="下载 Xcode iOS 平台组件"

  if xcodebuild -showsdks 2>/dev/null | grep -E "iphoneos|iphonesimulator" >/dev/null 2>&1; then
    action_word="更新"
    desc="检测到 iOS SDK，是否重新下载 / 更新 Xcode iOS 平台组件？"
  else
    desc="未检测到 iOS SDK，是否下载 Xcode iOS 平台组件？"
  fi

  if confirm_execute "${desc}" "${action_word}"; then
    run_sh "删除 Xcode 缓存" 'rm -rf ~/Library/Caches/com.apple.dt.Xcode'
    run_sh "删除 CoreSimulator 缓存" 'rm -rf ~/Library/Developer/CoreSimulator/Caches'
    run_cmd "下载 / 更新 iOS 模拟器平台" xcodebuild -downloadPlatform iOS -verbose
  fi
}
# ---------- 部件：Oh My Zsh ----------
component_oh_my_zsh() {
  progress_step "Oh My Zsh"

  ensure_raw_github_access_or_exit

  if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    success_echo "Oh My Zsh 已存在：${HOME}/.oh-my-zsh"

    if confirm_execute "Oh My Zsh 已存在，是否更新？" "更新"; then
      if [[ -f "${HOME}/.oh-my-zsh/tools/upgrade.sh" ]]; then
        run_sh "更新 Oh My Zsh" "ZSH='${HOME}/.oh-my-zsh' '${HOME}/.oh-my-zsh/tools/upgrade.sh'"
      else
        warn_echo "未找到 Oh My Zsh upgrade.sh，跳过更新"
      fi
    fi

    return 0
  fi

  if confirm_execute "未检测到 Oh My Zsh，是否安装？" "安装"; then
    run_sh \
      "安装 Oh My Zsh" \
      'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
    warn_echo "Oh My Zsh 官方安装流程可能有交互输出，这是正常现象。"
  fi
}
# ---------- 部件：Homebrew ----------
component_homebrew() {
  progress_step "Homebrew"

  local brew_bin=""

  if brew_bin="$(find_brew_bin)"; then
    setup_brew_shellenv "${brew_bin}"
    success_echo "Homebrew 已存在：${brew_bin}"

    if confirm_execute "Homebrew 已存在，是否执行 update / upgrade / cleanup / doctor？" "更新"; then
      run_cmd "brew update（更新软件列表）" brew update
      run_cmd "brew upgrade（升级已安装软件）" brew upgrade
      run_cmd "brew cleanup（清理旧版本缓存）" brew cleanup
      run_cmd "brew doctor（检查 Homebrew 健康状态）" brew doctor
      run_cmd "brew -v（输出 Homebrew 版本）" brew -v
    fi

    return 0
  fi

  if confirm_execute "未检测到 Homebrew，是否安装？" "安装"; then
    install_homebrew_without_menu
  fi
}
# ---------- 部件：Rosetta 2 ----------
component_rosetta() {
  progress_step "Rosetta 2"

  if [[ "$(uname -m)" != "arm64" ]]; then
    info_echo "当前不是 Apple Silicon，跳过 Rosetta 2"
    return 0
  fi

  if /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    success_echo "Rosetta 2 已存在。Rosetta 属于系统组件，通常随系统更新维护，不单独执行更新。"
    return 0
  fi

  if confirm_execute "未检测到 Rosetta 2，是否安装？" "安装"; then
    run_cmd "安装 Rosetta 2" /usr/sbin/softwareupdate --install-rosetta --agree-to-license
  fi
}
# ---------- 部件：brew formula ----------
brew_formula_install_arg() {
  local formula_name="$1"

  case "${formula_name}" in
    go-task) echo "go-task/tap/go-task" ;;
    *) echo "${formula_name}" ;;
  esac
}
# 封装 brew_formula_tap_name 对应的独立处理逻辑。
brew_formula_tap_name() {
  local formula_name="$1"

  case "${formula_name}" in
    fvm) echo "leoafarias/fvm" ;;
    go-task) echo "go-task/tap" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_formula_after_install 对应的独立处理逻辑。
brew_formula_after_install() {
  local formula_name="$1"

  case "${formula_name}" in
    rbenv) ensure_rbenv_init ;;
    jenv) ensure_jenv_init ;;
    openjdk|openjdk@17) post_openjdk_hint ;;
    fzf) setup_fzf_shellenv ;;
    *) return 0 ;;
  esac
}
# 封装 component_brew_formula 对应的独立处理逻辑。
component_brew_formula() {
  local formula_name="$1"
  local install_arg=""
  local tap_name=""

  install_arg="$(brew_formula_install_arg "${formula_name}")"
  tap_name="$(brew_formula_tap_name "${formula_name}")"

  progress_step "brew formula：${formula_name}"

  if ! require_brew_or_skip; then
    return 0
  fi

  local installed=0
  local desc="未检测到 brew formula：${formula_name}，是否安装最新版？"

  if brew_formula_installed "${formula_name}"; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 brew formula：${formula_name}"
      return 0
    fi
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if [[ -n "${tap_name}" ]]; then
    run_cmd "确认 Homebrew Tap：${tap_name}" brew tap "${tap_name}"
  fi

  if (( installed )); then
    run_cmd "更新 brew formula：${formula_name}" brew upgrade "${install_arg}"
  else
    run_cmd "安装 brew formula：${formula_name}" brew install "${install_arg}"
  fi

  brew_formula_after_install "${formula_name}"
}
# ---------- 部件：brew cask ----------
brew_cask_tap_name() {
  local cask_name="$1"

  case "${cask_name}" in
    github-store) echo "OpenHub-Store/tap" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_cask_after_install 对应的独立处理逻辑。
brew_cask_after_install() {
  local cask_name="$1"

  case "${cask_name}" in
    flutter)
      run_flutter_doctor_and_android_licenses "Flutter" flutter
      ;;
    github-store)
      local app_path="/Applications/GitHub-Store.app"

      if [[ -d "${app_path}" ]]; then
        run_cmd "移除 GitHub-Store Gatekeeper 隔离属性" xattr -dr com.apple.quarantine "${app_path}"
      else
        warn_echo "未找到 ${app_path}，跳过 GitHub-Store 去隔离。若使用了自定义 --appdir，请手动执行 xattr。"
      fi
      ;;
    *) return 0 ;;
  esac
}
# 封装 component_brew_cask 对应的独立处理逻辑。
component_brew_cask() {
  local cask_name="$1"
  local tap_name=""

  tap_name="$(brew_cask_tap_name "${cask_name}")"

  progress_step "brew cask：${cask_name}"

  if ! require_brew_or_skip; then
    return 0
  fi

  local installed=0
  local desc="未检测到 brew cask：${cask_name}，是否安装最新版？"

  if brew_cask_installed "${cask_name}"; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 brew cask：${cask_name}"
      return 0
    fi
  elif brew_cask_local_app_exists "${cask_name}"; then
    local app_path=""
    app_path="$(brew_cask_local_app_path "${cask_name}")"
    success_echo "已检测到本机 App：${app_path}"
    warn_echo "Homebrew 未登记 brew cask：${cask_name}，但本机已有 App，跳过重复安装。"
    return 0
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if [[ -n "${tap_name}" ]]; then
    run_cmd "确认 Homebrew Tap：${tap_name}" brew tap "${tap_name}"
  fi

  local brew_exit_code=0

  if (( installed )); then
    run_cmd "更新 brew cask：${cask_name}" brew upgrade --cask "${cask_name}"
    brew_exit_code=$?
  else
    run_cmd "安装 brew cask：${cask_name}" brew install --cask "${cask_name}"
    brew_exit_code=$?
  fi

  if [[ ${brew_exit_code} -eq 0 ]]; then
    brew_cask_after_install "${cask_name}"
  else
    warn_echo "brew cask：${cask_name} 安装 / 更新失败，跳过后置处理。"
  fi
}
# ---------- 部件：npm quicktype ----------
component_npm_quicktype() {
  progress_step "npm 全局包：quicktype"

  if ! require_command npm; then
    warn_echo "npm 不存在，无法安装 quicktype。请先选择 brew formula：node。"
    return 0
  fi

  local installed=0
  local desc="未检测到 npm 全局包 quicktype，是否安装？"

  if npm list -g quicktype --depth=0 >/dev/null 2>&1; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 npm 全局包：quicktype"
      return 0
    fi
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if (( installed )); then
    run_cmd "更新 npm 全局包 quicktype" sudo npm update -g quicktype
  else
    run_cmd "安装 npm 全局包 quicktype" sudo npm install -g quicktype
  fi
}
# ---------- 部件：npm OpenCLI ----------
component_npm_opencli() {
  progress_step "npm 全局包：OpenCLI"

  if ! require_command npm; then
    warn_echo "npm 不存在，无法安装 OpenCLI。请先选择 brew formula：node。"
    return 0
  fi

  if ! ensure_node_for_opencli; then
    return 0
  fi

  local installed=0
  local desc="未检测到 npm 全局包 OpenCLI，是否安装？"

  if npm list -g @jackwener/opencli --depth=0 >/dev/null 2>&1; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 npm 全局包：OpenCLI"
      return 0
    fi
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if (( installed )); then
    run_cmd "更新 npm 全局包 OpenCLI" sudo npm install -g @jackwener/opencli@latest
  else
    run_cmd "安装 npm 全局包 OpenCLI" sudo npm install -g @jackwener/opencli@latest
  fi

  if require_command opencli; then
    run_cmd "输出 OpenCLI 版本" opencli --version
    warm_echo "OpenCLI 浏览器自动化还需要手动安装 Browser Bridge 扩展，安装后可执行：opencli doctor"
  else
    warn_echo "npm 安装完成后当前 PATH 仍找不到 opencli，建议重新打开终端或检查 npm global bin。"
  fi
}
# ---------- 部件：npm CodeGraph ----------
component_npm_codegraph() {
  progress_step "npm 全局包：CodeGraph"

  if ! require_command npm; then
    warn_echo "npm 不存在，无法安装 CodeGraph。请先选择 brew formula：node。"
    return 0
  fi

  local installed=0
  local desc="未检测到 npm 全局包 CodeGraph，是否安装？"

  if npm list -g @colbymchenry/codegraph --depth=0 >/dev/null 2>&1; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 npm 全局包：CodeGraph"
      return 0
    fi
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if (( installed )); then
    run_cmd "更新 npm 全局包 CodeGraph" npm i -g @colbymchenry/codegraph
  else
    run_cmd "安装 npm 全局包 CodeGraph" npm i -g @colbymchenry/codegraph
  fi

  if require_command codegraph; then
    run_cmd "输出 CodeGraph 版本" codegraph --version
    warm_echo "CodeGraph 全局命令已安装。进入具体项目后，可按需执行：codegraph init -i"
  else
    warn_echo "npm 安装完成后当前 PATH 仍找不到 codegraph，建议重新打开终端或检查 npm global bin。"
  fi
}
# ---------- 部件：gem cocoapods ----------
component_gem_cocoapods() {
  progress_step "gem 包：cocoapods"

  if ! require_command gem; then
    warn_echo "gem 不存在，无法安装 cocoapods。请先确认 Ruby 环境。"
    return 0
  fi

  local installed=0
  local desc="未检测到 gem 包 cocoapods，是否安装？"

  if gem list -i cocoapods >/dev/null 2>&1; then
    installed=1

    if ! confirm_existing_third_party_upgrade_once; then
      warn_echo "已按统一选择跳过升级 gem 包：cocoapods"
      return 0
    fi
  else
    if ! confirm_execute "${desc}" "安装"; then
      return 0
    fi
  fi

  if (( installed )); then
    run_cmd "更新 gem 包 cocoapods" sudo gem update cocoapods
  else
    run_cmd "安装 gem 包 cocoapods" sudo gem install cocoapods
  fi
}
# ---------- 部件：Git LFS 初始化 ----------
component_git_lfs_init() {
  progress_step "Git LFS 初始化"

  if ! require_command git; then
    warn_echo "git 不存在，无法初始化 Git LFS。请先安装 Xcode Command Line Tools 或 git。"
    return 0
  fi

  if ! git lfs version >/dev/null 2>&1; then
    warn_echo "git-lfs 不存在，无法初始化。请先选择 brew formula：git-lfs。"
    return 0
  fi

  if confirm_execute "是否初始化 / 刷新 Git LFS 与大文件传输参数？" "执行"; then
    run_cmd "初始化 Git LFS" git lfs install
    run_cmd "配置 Git core.compression=0" git config --global core.compression 0
    run_cmd "配置 Git http.postBuffer=524288000" git config --global http.postBuffer 524288000
  fi
}
# ---------- 部件：JobsKits 仓库 ----------
clone_or_update_repo() {
  local repo_name="$1"
  local repo_url="$2"
  local target_dir="$3"

  if [[ -d "${target_dir}/.git" ]]; then
    success_echo "仓库已存在：${target_dir}"

    if confirm_execute "${repo_name} 已存在，是否执行 git pull 更新？" "更新"; then
      run_sh "更新仓库：${repo_name}" "cd '${target_dir}' && git pull --ff-only"
    fi

    return 0
  fi

  if confirm_execute "未检测到仓库 ${repo_name}，是否克隆到 ${target_dir}？" "安装"; then
    run_sh "创建 JobsKits 工作目录" "mkdir -p '${JOBS_WORKSPACE}'"
    run_sh "克隆仓库：${repo_name}" "git clone '${repo_url}' '${target_dir}'"
  fi
}
# 封装 component_jobs_repos 对应的独立处理逻辑。
component_jobs_repos() {
  progress_step "JobsKits 仓库"

  ensure_github_access_or_exit

  if ! require_command git; then
    warn_echo "git 不存在，跳过 JobsKits 仓库拉取。请先安装 Xcode Command Line Tools 或 git。"
    return 0
  fi

  local software_dir="${JOBS_WORKSPACE}/JobsSoftware.MacOS"
  local env_dir="${JOBS_WORKSPACE}/JobsMacEnvVarConfig"

  clone_or_update_repo "JobsSoftware.MacOS" "${JOBS_SOFTWARE_REPO}" "${software_dir}"
  clone_or_update_repo "JobsMacEnvVarConfig" "${JOBS_ENV_REPO}" "${env_dir}"

  local install_script="${env_dir}/install.command/install.command"
  if [[ -f "${install_script}" ]]; then
    if confirm_execute "是否为 JobsMacEnvVarConfig/install.command 添加可执行权限？" "执行"; then
      run_cmd "添加可执行权限：JobsMacEnvVarConfig/install.command" chmod +x "${install_script}"
    fi
    warn_echo "不会执行 ${install_script}，避免 install.command 递归调用自身。"
  fi
}
# ---------- 部件：手动下载页面 ----------
open_download_page() {
  local name="$1"
  local url="$2"

  if ! require_command open; then
    warn_echo "open 命令不存在，无法打开：${name}"
    return 0
  fi

  if confirm_execute "是否打开 ${name} 下载页？" "打开"; then
    run_cmd "打开 ${name} 下载页" open "${url}"
  fi
}
# 封装 component_manual_download_pages 对应的独立处理逻辑。
component_manual_download_pages() {
  progress_step "手动下载页面"

  open_download_page "Visual Studio Code" "https://code.visualstudio.com/"
  open_download_page "Android Studio" "https://developer.android.com/studio?hl=zh-cn"
  open_download_page "Python" "https://www.python.org/downloads/"
  open_download_page "Codex++" "https://github.com/BigPizzaV3/CodexPlusPlus"
}
# ---------- 菜单 ----------
get_menu_items() {
  MENU_ITEMS=(
    "${ALL_MENU_ITEM}"
    "Xcode Command Line Tools"
    "Xcode iOS 平台组件"
    "Oh My Zsh"
    "Homebrew"
  )

  local pkg
  for pkg in "${BREW_CASKS[@]}"; do
    MENU_ITEMS+=("brew cask：${pkg}")
  done

  for pkg in "${BREW_FORMULAE[@]}"; do
    MENU_ITEMS+=("brew formula：${pkg}")
  done

  MENU_ITEMS+=(
    "Rosetta 2"
    "npm 全局包：quicktype"
    "npm 全局包：OpenCLI"
    "npm 全局包：CodeGraph"
    "gem 包：cocoapods"
    "Git LFS 初始化"
    "JobsKits 仓库"
    "手动下载页面"
  )
}
# 收集并校验用户输入，决定后续执行路径。
choose_menu_items() {
  local fzf_bin=""
  fzf_bin="$(find_fzf_bin)" || return 1

  get_menu_items

  local selections=""
  selections="$(printf '%s\n' "${MENU_ITEMS[@]}" | "${fzf_bin}" \
    --multi \
    --no-sort \
    --layout=reverse-list \
    --height=90% \
    --border \
    --prompt='选择要安装 / 更新的功能 > ' \
    --header='Tab 多选，Enter 确认；选择「✅ 全选安装」会依次处理所有部件；已存在第三方依赖升级只统一确认一次。')"

  if [[ -z "${selections}" ]]; then
    warn_echo "未选择任何功能，脚本结束。"
    return 1
  fi

  SELECTED_ITEMS=("${(@f)selections}")

  local item
  local has_all=0
  for item in "${SELECTED_ITEMS[@]}"; do
    if [[ "${item}" == "${ALL_MENU_ITEM}" ]]; then
      has_all=1
      break
    fi
  done

  RUN_ITEMS=()
  if (( has_all )); then
    for item in "${MENU_ITEMS[@]}"; do
      [[ "${item}" == "${ALL_MENU_ITEM}" ]] && continue
      RUN_ITEMS+=("${item}")
    done
  else
    RUN_ITEMS=("${SELECTED_ITEMS[@]}")
  fi

  return 0
}
# 执行已经拆分完成的独立业务步骤。
run_selected_item() {
  local item="$1"

  case "${item}" in
    "Xcode Command Line Tools") component_clt ;;
    "Xcode iOS 平台组件") component_xcode_ios_platform ;;
    "Oh My Zsh") component_oh_my_zsh ;;
    "Homebrew") component_homebrew ;;
    "Rosetta 2") component_rosetta ;;
    "brew cask："*) component_brew_cask "${item#brew cask：}" ;;
    "brew formula："*) component_brew_formula "${item#brew formula：}" ;;
    "npm 全局包：quicktype") component_npm_quicktype ;;
    "npm 全局包：OpenCLI") component_npm_opencli ;;
    "npm 全局包：CodeGraph") component_npm_codegraph ;;
    "gem 包：cocoapods") component_gem_cocoapods ;;
    "Git LFS 初始化") component_git_lfs_init ;;
    "JobsKits 仓库") component_jobs_repos ;;
    "手动下载页面") component_manual_download_pages ;;
    *) warn_echo "未知菜单项，已跳过：${item}" ;;
  esac
}
# ---------- 收尾 ----------
finish_summary() {
  echo ""
  print_divider
  success_echo "macOS 新系统配置流程执行结束"
  info_echo "日志文件位置：${LOG_FILE}"
  warm_echo "请手动检查终端日志，确认失败项并按需补装。"
  warm_echo "重点留意：CLT / Xcode / Oh My Zsh / Homebrew / GitHub 网络 / sudo 密码相关步骤。"
  print_divider
}
# ---------- 主流程 ----------
install() {
  prepare_menu_runtime

  if ! choose_menu_items; then
    return 0
  fi

  TOTAL_STAGES=${#RUN_ITEMS[@]}
  CURRENT_STAGE=0

  local item
  for item in "${RUN_ITEMS[@]}"; do
    run_selected_item "${item}"
  done

  finish_summary
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
jobs_install_main() {
  # 执行当前流程中的独立业务步骤：处理当前语句。
  : > "${LOG_FILE}"

  # 展示脚本说明并等待用户确认影响范围。
  jobs_install_show_readme_and_wait
  # 执行安装步骤，并保留命令失败信息供后续排查。
  install "$@"

  # 执行当前流程中的独立业务步骤：pause_for_enter。
  pause_for_enter "👉 全部流程已执行完成。请按回车退出..."
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：install.command' | jobs_intro_style title
  print -r -- '核心用途：执行“install”对应的自动化任务。' | jobs_intro_style body
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
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_script_intro_and_wait
  # 执行 jobs_install_main 对应的核心业务步骤。
  jobs_install_main "$@"
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  set -u
  set -o pipefail
  setopt NO_NOMATCH
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    main "$@"
  fi
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
