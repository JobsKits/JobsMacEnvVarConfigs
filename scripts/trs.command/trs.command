#!/bin/zsh
# 脚本自述：
# - 脚本名称：trs.command
# - 核心用途：执行“trs”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


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
  printf "%b" "${COLOR_CYAN}按回车继续...${COLOR_RESET}"
  read -r _
}
# 收集并校验用户输入，决定后续执行路径。
prompt_required_run() {
  local message="$1"
  printf "%b" "${COLOR_YELLOW}${message}${COLOR_RESET}\n按回车跳过；输入任意字符后回车执行；输入 q 后回车退出翻译："
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
  if command_exists brew; then
    eval "$(brew shellenv 2>/dev/null || true)" || true
    return 0
  fi

  local arch_name="$(uname -m)"
  local brew_candidate=""

  if [[ "${arch_name}" == "arm64" ]]; then
    brew_candidate="/opt/homebrew/bin/brew"
  else
    brew_candidate="/usr/local/bin/brew"
  fi

  if [[ -x "${brew_candidate}" ]]; then
    eval "$("${brew_candidate}" shellenv 2>/dev/null || true)" || true
    return 0
  fi

  log_warn "未检测到 Homebrew。"
  if prompt_required_run "缺少 Homebrew，是否现在自动安装？"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if command_exists brew; then
      eval "$(brew shellenv 2>/dev/null || true)" || true
      log_ok "Homebrew 安装完成"
    else
      log_error "Homebrew 安装后仍不可用，请手动检查。"
      return 1
    fi
  else
    return 1
  fi
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
  cat <<'LANGS'
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
  ensure_fzf

  local selected=""
  selected="$(language_rows | fzf --height=80% --border --prompt='选择对方语言 > ' --no-multi)" || return 1
  CURRENT_OTHER_NAME="$(printf "%s" "${selected}" | awk -F '｜' '{print $2}')"
  CURRENT_OTHER_CODE="$(printf "%s" "${selected}" | awk -F '｜' '{print $3}')"
  [[ -n "${CURRENT_OTHER_CODE}" ]]
}
# 封装 show_help 对应的独立处理逻辑。
show_help() {
  cat <<EOF_HELP

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
    printf "%b" "${COLOR_CYAN}按回车打开 Translation Languages 设置；输入一个空格后回车打开设置菜单；输入 q 后回车退出翻译：${COLOR_RESET}"
    IFS= read -r answer

    if [[ "${answer}" == " " ]]; then
      settings_menu
      continue
    fi

    if [[ "${answer:l}" == "q" ]]; then
      return 1
    fi

    open_translation_settings
    printf "%b" "${COLOR_CYAN}下载完成后回到这里，按回车重新检测；输入 q 后回车退出翻译：${COLOR_RESET}"
    IFS= read -r answer

    if [[ "${answer:l}" == "q" ]]; then
      return 1
    fi
  done
}
# 封装 change_language_interactive 对应的独立处理逻辑。
change_language_interactive() {
  if select_language; then
    CURRENT_DIRECTION="to_zh"
    save_config
    log_ok "当前语言：${CURRENT_OTHER_NAME} / ${CURRENT_OTHER_CODE}"
    log_ok "当前方向：$(direction_label)"
    ensure_current_pair_ready || exit 1
  fi
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
  ensure_fzf

  local choice=""
  choice="$(printf "%s\n" \
    "返回翻译" \
    "切换方向" \
    "切换对方语言" \
    "打开 Translation Languages 设置" \
    "查看帮助" \
    "退出翻译" \
    | fzf --height=60% --border --prompt='设置 > ' --no-multi)" || return 0

  case "${choice}" in
    "返回翻译")
      return 0
      ;;
    "切换方向")
      swap_direction
      return 0
      ;;
    "切换对方语言")
      change_language_interactive
      return 0
      ;;
    "打开 Translation Languages 设置")
      LAST_TRANSLATE_FROM="$(source_lang)"
      LAST_TRANSLATE_TO="$(target_lang)"
      open_translation_settings
      return 0
      ;;
    "查看帮助")
      show_help
      pause
      return 0
      ;;
    "退出翻译")
      exit 0
      ;;
  esac
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
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
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
