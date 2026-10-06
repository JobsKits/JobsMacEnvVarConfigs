#!/bin/zsh
# 脚本自述：
# - 脚本名称：gif.command
# - 核心用途：执行“gif”对应的自动化任务。
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
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
# 按当前输出级别记录终端信息，并同步写入脚本日志。
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

APP_HOME="${JOBS_MAC_ENV_HOME:-$HOME/.JobsMacEnv}"
CONFIG_DIR="$APP_HOME/gif"
CONFIG_FILE="$CONFIG_DIR/config.zsh"
LATEST_FILE="$CONFIG_DIR/latest_path.txt"

GIF_OUTPUT_PARENT="$HOME/Desktop"
GIF_THEME="github-dark"
GIF_FONT_SIZE="28"
GIF_LINE_HEIGHT="1.35"
GIF_SPEED="1"
GIF_IDLE_TIME_LIMIT="1.2"
GIF_REC_IDLE_LIMIT="1.2"
GIF_FPS_CAP="30"
GIF_LAST_FRAME_DURATION="2"
GIF_RENDERER="swash"
GIF_TEXT_FONT_FAMILY="SF Mono,Menlo,JetBrains Mono,Fira Code"
GIF_NO_LOOP="false"
GIF_CLEAR_AFTER_FINISH="true"
GIF_VIDEO_ENABLED="true"
GIF_VIDEO_CRF="18"
GIF_VIDEO_PRESET="medium"

# 录制模式：默认永远是 terminal；只有进入设置菜单时才允许临时改为 screen。
GIF_RECORD_MODE="terminal"
GIF_SCREEN_COUNTDOWN="3"
GIF_SCREEN_SHOW_CURSOR="true"
GIF_SCREEN_FPS="24"
GIF_SCREEN_GIF_WIDTH="1600"

OUTPUT_DIR=""
CAST_FILE=""
GIF_FILE=""
VIDEO_FILE=""
SCREEN_MOV_FILE=""
META_FILE=""
RECORD_ZDOTDIR=""
AGG_BIN=""
FFMPEG_BIN=""
SCREENCAPTURE_BIN=""
SETTINGS_MENU="false"
# 封装 show_usage 对应的独立处理逻辑。
show_usage() {
  cat <<'EOF_USAGE'
Jobs GIF / gif

用途：
  录制当前终端会话或整个屏幕，并在录制结束后转成高质量 GIF 和 MP4。

用法：
  gif
  gif --repair <输出目录、session.cast 或 session.mov>
  gif --help

启动录制：
  按 Enter：跳过设置菜单，默认使用“当前终端录制”。
  输入任意字符后回车：进入设置菜单，可选择“当前终端录制 / 全屏录制”，并配置路径、品质、视频输出。

录制模式：
  当前终端录制：基于 asciinema + agg。一个终端执行一次 gif 就生成一个录制结果；多个终端分别执行即可录制多个。
  全屏录制：基于 macOS screencapture + ffmpeg。只录整个屏幕，不做 App / 窗口录制。

排除 gif 干扰：
  所有设置、提示、路径输入、品质配置都发生在正式录制之前。
  真正开始录制前会清屏，尽量避免把 gif 程序自己的文字录进去。

结束录制：
  录制过程中按 Ctrl-C：停止录制，并立即转换 session.gif / session.mp4。
  不建议输入 exit，因为它会被录进去。

输出：
  默认输出到：~/Desktop/Gif@YYYY.MM.DD HH:MM:SS
  终端模式：session.cast、session.gif、session.mp4、README.md
  全屏模式：session.mov、session.mp4、session.gif、README.md
EOF_USAGE
}
# 执行对应的清理操作，并保留必要的安全检查。
clear_terminal_soft() {
  command clear 2>/dev/null || true
  printf '\033[3J\033[H\033[2J'
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_intro_if_double_clicked() {
  local current_name="$(basename -- "$SCRIPT_PATH")"
  [[ "$current_name" == *.command ]] || return 0

  clear_terminal_soft
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | jobs_intro_style title
  bold_echo "      Jobs GIF 录制入口" | jobs_intro_style title
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | jobs_intro_style title
  info_echo "本脚本支持当前终端录制和全屏录制，并在结束后生成 session.gif / session.mp4。" | jobs_intro_style body
  info_echo "正式开始录制前会清屏，gif 的设置过程不会进入录制内容。" | jobs_intro_style body
  warn_echo "结束录制：录制过程中按 Ctrl-C。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  gray_echo "输出默认路径：~/Desktop/Gif@YYYY.MM.DD HH:MM:SS" | jobs_intro_style body
  gray_echo "依赖工具：Homebrew、asciinema、agg、ffmpeg；全屏录制额外使用 macOS 自带 screencapture。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  warm_echo "按回车继续..." | jobs_intro_style body
  local _answer=""
  IFS= read -r _answer
}
# 解析并返回后续流程需要的目标信息。
get_cpu_arch() {
  uname -m
}
# 封装 trim_text 对应的独立处理逻辑。
trim_text() {
  local value="$1"
  value="$(printf "%s" "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf "%s" "$value"
}
# 封装 normalize_dragged_path 对应的独立处理逻辑。
normalize_dragged_path() {
  local raw="$1"
  raw="$(trim_text "$raw")"
  raw="${raw%$'\r'}"

  raw="${raw#\"}"
  raw="${raw%\"}"
  raw="${raw#\'}"
  raw="${raw%\'}"

  raw="${raw/#\~/$HOME}"
  raw="${raw//\\ / }"
  raw="${raw//\\(/(}"
  raw="${raw//\\)/)}"
  raw="${raw//\\&/&}"
  raw="${raw//\\'/'}"
  raw="${raw//\\\"/\"}"
  raw="${raw%/}"

  printf "%s" "$raw"
}
# 检查当前运行条件是否满足后续流程要求。
is_positive_int() {
  [[ "$1" =~ '^[0-9]+$' ]] && [[ "$1" -gt 0 ]]
}
# 检查当前运行条件是否满足后续流程要求。
is_nonnegative_int() {
  [[ "$1" =~ '^[0-9]+$' ]]
}
# 检查当前运行条件是否满足后续流程要求。
is_positive_number() {
  [[ "$1" =~ '^[0-9]+([.][0-9]+)?$' ]]
}
# 检查当前运行条件是否满足后续流程要求。
is_bool_text() {
  [[ "$1" == "true" || "$1" == "false" ]]
}
# 检查当前运行条件是否满足后续流程要求。
is_theme_text() {
  [[ "$1" =~ '^[A-Za-z0-9,_#.-]+$' ]]
}
# 封装 load_config 对应的独立处理逻辑。
load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0

  if source "$CONFIG_FILE" 2>>"$LOG_FILE"; then
    return 0
  fi

  warn_echo "历史配置读取失败，已使用默认配置：$CONFIG_FILE"
}
# 封装 quote_value 对应的独立处理逻辑。
quote_value() {
  printf "%q" "$1"
}
# 封装 save_config 对应的独立处理逻辑。
save_config() {
  mkdir -p "$CONFIG_DIR"
  {
    echo "# Jobs GIF 配置：自动生成"
    printf "GIF_OUTPUT_PARENT=%s\n" "$(quote_value "$GIF_OUTPUT_PARENT")"
    printf "GIF_THEME=%s\n" "$(quote_value "$GIF_THEME")"
    printf "GIF_FONT_SIZE=%s\n" "$(quote_value "$GIF_FONT_SIZE")"
    printf "GIF_LINE_HEIGHT=%s\n" "$(quote_value "$GIF_LINE_HEIGHT")"
    printf "GIF_SPEED=%s\n" "$(quote_value "$GIF_SPEED")"
    printf "GIF_IDLE_TIME_LIMIT=%s\n" "$(quote_value "$GIF_IDLE_TIME_LIMIT")"
    printf "GIF_REC_IDLE_LIMIT=%s\n" "$(quote_value "$GIF_REC_IDLE_LIMIT")"
    printf "GIF_FPS_CAP=%s\n" "$(quote_value "$GIF_FPS_CAP")"
    printf "GIF_LAST_FRAME_DURATION=%s\n" "$(quote_value "$GIF_LAST_FRAME_DURATION")"
    printf "GIF_RENDERER=%s\n" "$(quote_value "$GIF_RENDERER")"
    printf "GIF_TEXT_FONT_FAMILY=%s\n" "$(quote_value "$GIF_TEXT_FONT_FAMILY")"
    printf "GIF_NO_LOOP=%s\n" "$(quote_value "$GIF_NO_LOOP")"
    printf "GIF_CLEAR_AFTER_FINISH=%s\n" "$(quote_value "$GIF_CLEAR_AFTER_FINISH")"
    printf "GIF_VIDEO_ENABLED=%s\n" "$(quote_value "$GIF_VIDEO_ENABLED")"
    printf "GIF_VIDEO_CRF=%s\n" "$(quote_value "$GIF_VIDEO_CRF")"
    printf "GIF_VIDEO_PRESET=%s\n" "$(quote_value "$GIF_VIDEO_PRESET")"
    printf "GIF_SCREEN_COUNTDOWN=%s\n" "$(quote_value "$GIF_SCREEN_COUNTDOWN")"
    printf "GIF_SCREEN_SHOW_CURSOR=%s\n" "$(quote_value "$GIF_SCREEN_SHOW_CURSOR")"
    printf "GIF_SCREEN_FPS=%s\n" "$(quote_value "$GIF_SCREEN_FPS")"
    printf "GIF_SCREEN_GIF_WIDTH=%s\n" "$(quote_value "$GIF_SCREEN_GIF_WIDTH")"
  } > "$CONFIG_FILE"
}
# 封装 refresh_brew_shellenv 对应的独立处理逻辑。
refresh_brew_shellenv() {
  local brew_bin=""

  if command -v brew >/dev/null 2>&1; then
    brew_bin="$(command -v brew)"
  elif [[ -x "/opt/homebrew/bin/brew" ]]; then
    brew_bin="/opt/homebrew/bin/brew"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    brew_bin="/usr/local/bin/brew"
  fi

  [[ -n "$brew_bin" ]] || return 1
  eval "$("$brew_bin" shellenv)"
  return 0
}
# 封装 inject_shellenv_block 对应的独立处理逻辑。
inject_shellenv_block() {
  local profile_file="$1"
  local shellenv_cmd="$2"
  local id="Homebrew"
  local header="# >>> ${id} 环境变量 >>>"
  local footer="# <<< ${id} 环境变量 <<<"

  if [[ -z "$profile_file" || -z "$shellenv_cmd" ]]; then
    error_echo "缺少参数：inject_shellenv_block <profile_file> <shellenv_cmd>"
    return 1
  fi

  touch "$profile_file"

  if grep -Fq "$shellenv_cmd" "$profile_file"; then
    info_echo "Homebrew shellenv 已存在：$profile_file"
    return 0
  fi

  {
    echo ""
    echo "$header"
    echo "$shellenv_cmd"
    echo "$footer"
  } >> "$profile_file"

  success_echo "已写入 Homebrew shellenv：$profile_file"
}
# 收集并校验用户输入，决定后续执行路径。
prompt_homebrew_update() {
  info_echo "Homebrew 已安装。是否执行更新？"
  echo "👉 按 [Enter]：跳过更新"
  echo "👉 输入任意字符后回车：执行 brew update && brew upgrade && brew cleanup && brew doctor && brew -v"

  local confirm=""
  IFS= read -r confirm

  if [[ -z "$confirm" ]]; then
    note_echo "已选择跳过 Homebrew 更新"
    return 0
  fi

  info_echo "正在更新 Homebrew..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || { warn_echo "brew doctor 有警告/错误，请按提示处理"; }
  brew -v      || { warn_echo "打印 brew 版本失败，可忽略"; }
  success_echo "Homebrew 已更新"
}
# 执行对应的环境配置或同步处理。
install_homebrew() {
  local allow_update="${1:-false}"
  local arch="$(get_cpu_arch)"
  local shell_name="${SHELL##*/}"
  local profile_file=""
  local brew_bin=""
  local shellenv_cmd=""

  if ! refresh_brew_shellenv; then
    warn_echo "未检测到 Homebrew，准备安装...（架构：$arch）"

    if [[ "$arch" == "arm64" ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error_echo "Homebrew 安装失败（arm64）"
        exit 1
      }
      brew_bin="/opt/homebrew/bin/brew"
    else
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error_echo "Homebrew 安装失败（x86_64）"
        exit 1
      }
      brew_bin="/usr/local/bin/brew"
    fi

    success_echo "Homebrew 安装成功"

    shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
    case "$shell_name" in
      zsh)  profile_file="$HOME/.zprofile" ;;
      bash) profile_file="$HOME/.bash_profile" ;;
      *)    profile_file="$HOME/.profile" ;;
    esac

    inject_shellenv_block "$profile_file" "$shellenv_cmd"
    eval "$("$brew_bin" shellenv)"
    return 0
  fi

  [[ "$allow_update" == "true" ]] || return 0
  prompt_homebrew_update
}
# 检查当前运行条件是否满足后续流程要求。
ensure_dependencies() {
  local allow_update="${1:-false}"
  local mode="${2:-terminal}"

  install_homebrew "$allow_update"
  refresh_brew_shellenv || {
    error_echo "Homebrew shellenv 生效失败"
    exit 1
  }

  local -a missing_packages
  missing_packages=()

  if [[ "$mode" == "terminal" ]]; then
    command -v asciinema >/dev/null 2>&1 || missing_packages+=("asciinema")
    command -v agg >/dev/null 2>&1 || missing_packages+=("agg")
    command -v ffmpeg >/dev/null 2>&1 || missing_packages+=("ffmpeg")
  elif [[ "$mode" == "screen" ]]; then
    command -v ffmpeg >/dev/null 2>&1 || missing_packages+=("ffmpeg")
    if [[ ! -x "/usr/sbin/screencapture" ]] && ! command -v screencapture >/dev/null 2>&1; then
      error_echo "未找到 macOS 自带 screencapture，无法全屏录制"
      exit 1
    fi
  else
    error_echo "未知录制模式：$mode"
    exit 1
  fi

  if (( ${#missing_packages[@]} == 0 )); then
    if [[ "$mode" == "terminal" ]]; then
      success_echo "终端录制依赖已就绪：asciinema / agg / ffmpeg"
    else
      success_echo "全屏录制依赖已就绪：screencapture / ffmpeg"
    fi
    return 0
  fi

  warn_echo "缺少依赖：${missing_packages[*]}"
  info_echo "正在通过 Homebrew 安装缺失依赖..."
  brew install "${missing_packages[@]}" || {
    error_echo "依赖安装失败：${missing_packages[*]}"
    exit 1
  }

  if [[ "$mode" == "terminal" ]]; then
    command -v asciinema >/dev/null 2>&1 || { error_echo "asciinema 安装后仍不可用"; exit 1; }
    command -v agg >/dev/null 2>&1 || { error_echo "agg 安装后仍不可用"; exit 1; }
  fi
  command -v ffmpeg >/dev/null 2>&1 || { error_echo "ffmpeg 安装后仍不可用"; exit 1; }
  success_echo "录制依赖安装完成"
}
# 封装 assert_writable_dir 对应的独立处理逻辑。
assert_writable_dir() {
  local dir="$1"
  local test_file=""

  if [[ ! -d "$dir" ]]; then
    error_echo "路径不是有效目录：$dir"
    return 1
  fi

  if [[ ! -w "$dir" ]]; then
    error_echo "目录不可写：$dir"
    return 1
  fi

  test_file="$dir/.jobs_gif_write_test_$$"
  if ! : > "$test_file" 2>/dev/null; then
    error_echo "目录写入测试失败：$dir"
    return 1
  fi

  rm -f "$test_file"
  return 0
}
# 封装 make_unique_output_dir 对应的独立处理逻辑。
make_unique_output_dir() {
  local parent="$1"
  local timestamp="$2"
  local base="$parent/Gif@$timestamp"
  local candidate="$base"
  local index=1

  while [[ -e "$candidate" ]]; do
    candidate="$base-$index"
    index=$((index + 1))
  done

  mkdir -p "$candidate"
  printf "%s" "$candidate"
}
# 封装 set_output_files 对应的独立处理逻辑。
set_output_files() {
  OUTPUT_DIR="$1"
  CAST_FILE="$OUTPUT_DIR/session.cast"
  GIF_FILE="$OUTPUT_DIR/session.gif"
  VIDEO_FILE="$OUTPUT_DIR/session.mp4"
  SCREEN_MOV_FILE="$OUTPUT_DIR/session.mov"
  META_FILE="$OUTPUT_DIR/README.md"
}
# 封装 prepare_default_output_path 对应的独立处理逻辑。
prepare_default_output_path() {
  local timestamp="$(date '+%Y.%m.%d %H:%M:%S')"
  local candidate="$GIF_OUTPUT_PARENT"

  [[ -n "$candidate" ]] || candidate="$HOME/Desktop"
  candidate="$(normalize_dragged_path "$candidate")"

  if ! assert_writable_dir "$candidate" >/dev/null 2>&1; then
    candidate="$HOME/Desktop"
  fi

  mkdir -p "$candidate"
  GIF_OUTPUT_PARENT="$candidate"
  set_output_files "$(make_unique_output_dir "$GIF_OUTPUT_PARENT" "$timestamp")"
}
# 收集并校验用户输入，决定后续执行路径。
prompt_launch_mode() {
  local input=""

  echo ""
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold_echo "      启动录制"
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  gray_echo "默认模式：当前终端录制"
  gray_echo "当前父目录：$GIF_OUTPUT_PARENT"
  gray_echo "当前品质：theme=$GIF_THEME font=$GIF_FONT_SIZE fps=$GIF_FPS_CAP video=$GIF_VIDEO_ENABLED"
  echo ""
  info_echo "按 [Enter]：跳过设置，直接开始当前终端录制。"
  info_echo "输入任意字符后回车：进入设置菜单，可选择全屏录制。"
  echo ""
  printf "选择 > " | tee -a "$LOG_FILE"
  IFS= read -r input

  if [[ -z "$input" ]]; then
    SETTINGS_MENU="false"
    GIF_RECORD_MODE="terminal"
    note_echo "已跳过设置菜单，使用当前终端录制。"
  else
    SETTINGS_MENU="true"
    note_echo "进入设置菜单。"
  fi
}
# 收集并校验用户输入，决定后续执行路径。
prompt_record_mode() {
  local input=""

  GIF_RECORD_MODE="terminal"

  echo ""
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold_echo "      录制模式"
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info_echo "按回车跳过：默认录制当前终端。"
  echo "1) 当前终端录制：asciinema + agg。一个终端录一个，多终端分别执行 gif 即可录多个。"
  echo "2) 全屏录制：macOS screencapture + ffmpeg。只录整个屏幕，不录具体 App / 窗口。"
  echo ""

  while true; do
    printf "录制模式 > " | tee -a "$LOG_FILE"
    IFS= read -r input
    input="$(trim_text "$input")"

    case "$input" in
      ""|1)
        GIF_RECORD_MODE="terminal"
        success_echo "已选择：当前终端录制"
        return 0
        ;;
      2)
        GIF_RECORD_MODE="screen"
        success_echo "已选择：全屏录制"
        return 0
        ;;
      *)
        warn_echo "无效选择：$input"
        ;;
    esac
  done
}
# 收集并校验用户输入，决定后续执行路径。
prompt_output_path() {
  local default_parent="$HOME/Desktop"
  local input=""
  local candidate=""
  local timestamp="$(date '+%Y.%m.%d %H:%M:%S')"

  mkdir -p "$default_parent"

  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold_echo "      输出路径配置"
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  gray_echo "历史父目录：$GIF_OUTPUT_PARENT"
  echo ""
  info_echo "请输入或拖入一个已存在、可写的父目录。"
  info_echo "按回车跳过：默认生成到桌面。"
  gray_echo "默认目录名：Gif@$timestamp"
  echo ""

  while true; do
    printf "输出父目录 > " | tee -a "$LOG_FILE"
    IFS= read -r input

    if [[ -z "$input" ]]; then
      candidate="$default_parent"
    else
      candidate="$(normalize_dragged_path "$input")"
    fi

    if assert_writable_dir "$candidate"; then
      GIF_OUTPUT_PARENT="$candidate"
      set_output_files "$(make_unique_output_dir "$GIF_OUTPUT_PARENT" "$timestamp")"
      success_echo "输出目录已确认：$OUTPUT_DIR"
      return 0
    fi

    warn_echo "请重新输入一个可用目录，或直接回车使用桌面。"
  done
}
# 封装 apply_quality_preset 对应的独立处理逻辑。
apply_quality_preset() {
  local preset="$1"

  case "$preset" in
    high)
      GIF_THEME="github-dark"
      GIF_FONT_SIZE="28"
      GIF_LINE_HEIGHT="1.35"
      GIF_SPEED="1"
      GIF_IDLE_TIME_LIMIT="1.2"
      GIF_REC_IDLE_LIMIT="1.2"
      GIF_FPS_CAP="30"
      GIF_LAST_FRAME_DURATION="2"
      GIF_RENDERER="swash"
      GIF_TEXT_FONT_FAMILY="SF Mono,Menlo,JetBrains Mono,Fira Code"
      GIF_NO_LOOP="false"
      GIF_VIDEO_ENABLED="true"
      GIF_VIDEO_CRF="18"
      GIF_VIDEO_PRESET="medium"
      GIF_SCREEN_FPS="24"
      GIF_SCREEN_GIF_WIDTH="1600"
      ;;
    balanced)
      GIF_THEME="github-dark"
      GIF_FONT_SIZE="24"
      GIF_LINE_HEIGHT="1.35"
      GIF_SPEED="1.05"
      GIF_IDLE_TIME_LIMIT="1"
      GIF_REC_IDLE_LIMIT="1"
      GIF_FPS_CAP="24"
      GIF_LAST_FRAME_DURATION="2"
      GIF_RENDERER="swash"
      GIF_TEXT_FONT_FAMILY="SF Mono,Menlo,JetBrains Mono,Fira Code"
      GIF_NO_LOOP="false"
      GIF_VIDEO_ENABLED="true"
      GIF_VIDEO_CRF="20"
      GIF_VIDEO_PRESET="medium"
      GIF_SCREEN_FPS="20"
      GIF_SCREEN_GIF_WIDTH="1280"
      ;;
    small)
      GIF_THEME="github-dark"
      GIF_FONT_SIZE="20"
      GIF_LINE_HEIGHT="1.3"
      GIF_SPEED="1.15"
      GIF_IDLE_TIME_LIMIT="0.8"
      GIF_REC_IDLE_LIMIT="0.8"
      GIF_FPS_CAP="15"
      GIF_LAST_FRAME_DURATION="1.5"
      GIF_RENDERER="swash"
      GIF_TEXT_FONT_FAMILY="SF Mono,Menlo,JetBrains Mono,Fira Code"
      GIF_NO_LOOP="false"
      GIF_VIDEO_ENABLED="true"
      GIF_VIDEO_CRF="24"
      GIF_VIDEO_PRESET="fast"
      GIF_SCREEN_FPS="15"
      GIF_SCREEN_GIF_WIDTH="960"
      ;;
  esac
}
# 收集并校验用户输入，决定后续执行路径。
prompt_custom_value() {
  local var_name="$1"
  local label="$2"
  local validator="$3"
  local current=""
  local input=""

  eval "current=\"\${${var_name}}\""

  while true; do
    printf "%s [%s] > " "$label" "$current" | tee -a "$LOG_FILE"
    IFS= read -r input

    if [[ -z "$input" ]]; then
      return 0
    fi

    input="$(trim_text "$input")"
    [[ -z "$input" ]] && return 0

    case "$validator" in
      int)
        is_positive_int "$input" || { warn_echo "$label 必须是正整数"; continue; }
        ;;
      nonnegative_int)
        is_nonnegative_int "$input" || { warn_echo "$label 必须是非负整数"; continue; }
        ;;
      number)
        is_positive_number "$input" || { warn_echo "$label 必须是正数"; continue; }
        ;;
      theme)
        is_theme_text "$input" || { warn_echo "$label 只能包含字母、数字、连字符、下划线、逗号、点和 #"; continue; }
        ;;
      renderer)
        [[ "$input" == "swash" || "$input" == "resvg" ]] || { warn_echo "$label 只能是 swash 或 resvg"; continue; }
        ;;
      bool)
        is_bool_text "$input" || { warn_echo "$label 只能是 true 或 false"; continue; }
        ;;
      preset)
        [[ "$input" == "ultrafast" || "$input" == "superfast" || "$input" == "veryfast" || "$input" == "faster" || "$input" == "fast" || "$input" == "medium" || "$input" == "slow" || "$input" == "slower" || "$input" == "veryslow" ]] || { warn_echo "$label 不是有效 preset"; continue; }
        ;;
      text)
        ;;
    esac

    eval "${var_name}=\"\$input\""
    return 0
  done
}
# 收集并校验用户输入，决定后续执行路径。
prompt_custom_quality() {
  info_echo "自定义品质；每一项直接回车代表保留当前值。"
  prompt_custom_value GIF_THEME "主题" theme
  prompt_custom_value GIF_FONT_SIZE "字体大小" int
  prompt_custom_value GIF_LINE_HEIGHT "行高" number
  prompt_custom_value GIF_SPEED "播放速度" number
  prompt_custom_value GIF_IDLE_TIME_LIMIT "GIF 空闲压缩秒数" number
  prompt_custom_value GIF_REC_IDLE_LIMIT "录制空闲压缩秒数" number
  prompt_custom_value GIF_FPS_CAP "FPS 上限" int
  prompt_custom_value GIF_LAST_FRAME_DURATION "末帧停留秒数" number
  prompt_custom_value GIF_RENDERER "渲染器 swash/resvg" renderer
  prompt_custom_value GIF_TEXT_FONT_FAMILY "字体族" text
  prompt_custom_value GIF_NO_LOOP "是否不循环 true/false" bool
  prompt_custom_value GIF_VIDEO_ENABLED "是否生成 MP4 true/false" bool
  prompt_custom_value GIF_VIDEO_CRF "MP4 CRF 数值" int
  prompt_custom_value GIF_VIDEO_PRESET "MP4 preset" preset
  prompt_custom_value GIF_SCREEN_COUNTDOWN "全屏录制倒计时秒数" int
  prompt_custom_value GIF_SCREEN_SHOW_CURSOR "全屏录制是否显示鼠标 true/false" bool
  prompt_custom_value GIF_SCREEN_FPS "全屏 GIF FPS" int
  prompt_custom_value GIF_SCREEN_GIF_WIDTH "全屏 GIF 宽度像素，输入 0 表示不缩放" nonnegative_int
  prompt_custom_value GIF_CLEAR_AFTER_FINISH "结束后清屏 true/false" bool
}
# 收集并校验用户输入，决定后续执行路径。
prompt_quality() {
  local input=""

  echo ""
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bold_echo "      GIF / MP4 品质配置"
  bold_echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  gray_echo "当前配置：theme=$GIF_THEME font=$GIF_FONT_SIZE terminal_fps=$GIF_FPS_CAP screen_fps=$GIF_SCREEN_FPS screen_width=$GIF_SCREEN_GIF_WIDTH video=$GIF_VIDEO_ENABLED crf=$GIF_VIDEO_CRF"
  echo ""
  info_echo "按回车跳过：沿用当前/历史品质配置。"
  echo "1) 高质量：大字号，30fps，适合 README / 博客展示"
  echo "2) 均衡：中等字号，24fps，体积更稳"
  echo "3) 小体积：较小字号，15fps，适合快速分享"
  echo "4) 自定义：逐项配置"
  echo ""

  while true; do
    printf "品质选择 > " | tee -a "$LOG_FILE"
    IFS= read -r input
    input="$(trim_text "$input")"

    case "$input" in
      "")
        note_echo "已跳过品质修改，沿用当前配置"
        return 0
        ;;
      1)
        apply_quality_preset high
        success_echo "已选择高质量配置"
        return 0
        ;;
      2)
        apply_quality_preset balanced
        success_echo "已选择均衡配置"
        return 0
        ;;
      3)
        apply_quality_preset small
        success_echo "已选择小体积配置"
        return 0
        ;;
      4)
        prompt_custom_quality
        success_echo "自定义品质配置完成"
        return 0
        ;;
      *)
        warn_echo "无效选择：$input"
        ;;
    esac
  done
}
# 封装 write_metadata 对应的独立处理逻辑。
write_metadata() {
  [[ -n "$META_FILE" ]] || return 0

  local mode_label="当前终端录制"
  local raw_row="| session.cast | asciinema 原始录制文件 |"
  local end_text="录制过程中按 `Ctrl-C`。脚本会停止 asciinema 录制，然后立即把 `session.cast` 转为 `session.gif` 和 `session.mp4`。"
  local repair_text="gif --repair "$OUTPUT_DIR""

  if [[ "$GIF_RECORD_MODE" == "screen" ]]; then
    mode_label="全屏录制"
    raw_row="| session.mov | macOS screencapture 原始录屏文件 |"
    end_text="录制过程中按 `Ctrl-C`。脚本会停止全屏录制，然后立即把 `session.mov` 转为 `session.mp4` 和 `session.gif`。"
  fi

  cat > "$META_FILE" <<EOF_META
# $(basename "$OUTPUT_DIR")

## 文件

| 文件 | 说明 |
| --- | --- |
$raw_row
| session.gif | 高质量 GIF 文件 |
| session.mp4 | H.264 MP4 文件 |
| README.md | 本说明文件 |

## 录制模式

$mode_label

## 配置

| 配置项 | 值 |
| --- | --- |
| 终端主题 | $GIF_THEME |
| 终端字体大小 | $GIF_FONT_SIZE |
| 终端行高 | $GIF_LINE_HEIGHT |
| 终端播放速度 | $GIF_SPEED |
| 终端 GIF 空闲压缩 | $GIF_IDLE_TIME_LIMIT |
| 终端录制空闲压缩 | $GIF_REC_IDLE_LIMIT |
| 终端 FPS 上限 | $GIF_FPS_CAP |
| 终端末帧停留 | $GIF_LAST_FRAME_DURATION |
| 终端渲染器 | $GIF_RENDERER |
| 终端字体族 | $GIF_TEXT_FONT_FAMILY |
| 不循环 | $GIF_NO_LOOP |
| 生成 MP4 | $GIF_VIDEO_ENABLED |
| MP4 CRF | $GIF_VIDEO_CRF |
| MP4 preset | $GIF_VIDEO_PRESET |
| 全屏倒计时 | $GIF_SCREEN_COUNTDOWN |
| 全屏显示鼠标 | $GIF_SCREEN_SHOW_CURSOR |
| 全屏 GIF FPS | $GIF_SCREEN_FPS |
| 全屏 GIF 宽度 | $GIF_SCREEN_GIF_WIDTH |

## 结束录制

推荐方式：

$end_text

不建议输入 \`exit\`，因为手动输入的字符会被录进去。

如果异常情况下只留下原始文件，可执行：

\`\`\`zsh
$repair_text
\`\`\`
EOF_META
}
# 封装 write_latest_path 对应的独立处理逻辑。
write_latest_path() {
  mkdir -p "$CONFIG_DIR"
  {
    printf "OUTPUT_DIR=%s\n" "$OUTPUT_DIR"
    printf "RECORD_MODE=%s\n" "$GIF_RECORD_MODE"
    printf "GIF_FILE=%s\n" "$GIF_FILE"
    printf "VIDEO_FILE=%s\n" "$VIDEO_FILE"
    printf "CAST_FILE=%s\n" "$CAST_FILE"
    printf "SCREEN_MOV_FILE=%s\n" "$SCREEN_MOV_FILE"
  } > "$LATEST_FILE"
}
# 解析并返回后续流程需要的目标信息。
find_tool() {
  local name="$1"
  local value=""
  value="$(command -v "$name" 2>/dev/null || true)"
  [[ -n "$value" ]] || value="/opt/homebrew/bin/$name"
  [[ -x "$value" ]] || value="/usr/local/bin/$name"
  [[ -x "$value" ]] || return 1
  printf "%s" "$value"
}
# 解析并返回后续流程需要的目标信息。
find_system_tool() {
  local name="$1"
  local value=""
  value="$(command -v "$name" 2>/dev/null || true)"
  [[ -n "$value" ]] || value="/usr/sbin/$name"
  [[ -x "$value" ]] || value="/usr/bin/$name"
  [[ -x "$value" ]] || return 1
  printf "%s" "$value"
}
# 封装 agg_supports 对应的独立处理逻辑。
agg_supports() {
  local agg_bin="$1"
  local option="$2"
  "$agg_bin" --help 2>&1 | grep -Fq -- "$option"
}
# 封装 build_agg_args 对应的独立处理逻辑。
build_agg_args() {
  local agg_bin="$1"
  local -a result
  result=()

  agg_supports "$agg_bin" "--theme" && result+=(--theme "$GIF_THEME")
  agg_supports "$agg_bin" "--font-size" && result+=(--font-size "$GIF_FONT_SIZE")
  agg_supports "$agg_bin" "--line-height" && result+=(--line-height "$GIF_LINE_HEIGHT")
  agg_supports "$agg_bin" "--speed" && result+=(--speed "$GIF_SPEED")
  agg_supports "$agg_bin" "--idle-time-limit" && result+=(--idle-time-limit "$GIF_IDLE_TIME_LIMIT")
  agg_supports "$agg_bin" "--fps-cap" && result+=(--fps-cap "$GIF_FPS_CAP")
  agg_supports "$agg_bin" "--last-frame-duration" && result+=(--last-frame-duration "$GIF_LAST_FRAME_DURATION")
  agg_supports "$agg_bin" "--renderer" && result+=(--renderer "$GIF_RENDERER")

  if [[ -n "$GIF_TEXT_FONT_FAMILY" ]] && agg_supports "$agg_bin" "--text-font-family"; then
    result+=(--text-font-family "$GIF_TEXT_FONT_FAMILY")
  fi

  if [[ "$GIF_NO_LOOP" == "true" ]] && agg_supports "$agg_bin" "--no-loop"; then
    result+=(--no-loop)
  fi

  print -rl -- "${result[@]}"
}
# 封装 convert_to_gif 对应的独立处理逻辑。
convert_to_gif() {
  [[ -s "$CAST_FILE" ]] || {
    error_echo "录制文件不存在或为空：$CAST_FILE"
    return 1
  }

  local agg_bin="${AGG_BIN:-}"
  [[ -n "$agg_bin" && -x "$agg_bin" ]] || agg_bin="$(find_tool agg 2>/dev/null || true)"
  [[ -n "$agg_bin" ]] || {
    error_echo "未找到 agg，无法转换 GIF"
    return 1
  }

  AGG_BIN="$agg_bin"
  local gif_tmp="$GIF_FILE.tmp"
  local -a agg_args
  agg_args=( ${(f)"$(build_agg_args "$agg_bin")"} )

  rm -f "$gif_tmp"

  {
    echo "[gif] 开始转换 GIF：$CAST_FILE -> $GIF_FILE"
    echo "[gif] agg: $agg_bin"
    echo "[gif] args: ${agg_args[*]}"
  } >> "$LOG_FILE"

  if ! "$agg_bin" "${agg_args[@]}" "$CAST_FILE" "$gif_tmp" >> "$LOG_FILE" 2>&1; then
    warn_echo "agg 高级参数转换失败，尝试基础参数兜底。"
    rm -f "$gif_tmp"
    "$agg_bin" "$CAST_FILE" "$gif_tmp" >> "$LOG_FILE" 2>&1 || {
      error_echo "GIF 转换失败，请查看日志：$LOG_FILE"
      return 1
    }
  fi

  [[ -s "$gif_tmp" ]] || {
    error_echo "GIF 临时文件生成失败：$gif_tmp"
    return 1
  }

  mv -f "$gif_tmp" "$GIF_FILE"
  [[ -s "$GIF_FILE" ]] || {
    error_echo "GIF 文件生成失败：$GIF_FILE"
    return 1
  }

  success_echo "GIF 已生成：$GIF_FILE"
  return 0
}
# 封装 convert_to_mp4 对应的独立处理逻辑。
convert_to_mp4() {
  [[ "$GIF_VIDEO_ENABLED" == "true" ]] || return 0
  [[ -s "$GIF_FILE" ]] || {
    error_echo "缺少 GIF，无法生成 MP4：$GIF_FILE"
    return 1
  }

  local ffmpeg_bin="${FFMPEG_BIN:-}"
  [[ -n "$ffmpeg_bin" && -x "$ffmpeg_bin" ]] || ffmpeg_bin="$(find_tool ffmpeg 2>/dev/null || true)"
  [[ -n "$ffmpeg_bin" ]] || {
    error_echo "未找到 ffmpeg，无法转换 MP4"
    return 1
  }

  FFMPEG_BIN="$ffmpeg_bin"
  local video_tmp="$VIDEO_FILE.tmp.mp4"
  rm -f "$video_tmp"

  {
    echo "[gif] 开始转换 MP4：$GIF_FILE -> $VIDEO_FILE"
    echo "[gif] ffmpeg: $ffmpeg_bin"
  } >> "$LOG_FILE"

  "$ffmpeg_bin" -y -i "$GIF_FILE" \
    -movflags +faststart \
    -pix_fmt yuv420p \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
    -c:v libx264 \
    -crf "$GIF_VIDEO_CRF" \
    -preset "$GIF_VIDEO_PRESET" \
    "$video_tmp" >> "$LOG_FILE" 2>&1 || {
      error_echo "MP4 转换失败，请查看日志：$LOG_FILE"
      return 1
    }

  [[ -s "$video_tmp" ]] || {
    error_echo "MP4 临时文件生成失败：$video_tmp"
    return 1
  }

  mv -f "$video_tmp" "$VIDEO_FILE"
  [[ -s "$VIDEO_FILE" ]] || {
    error_echo "MP4 文件生成失败：$VIDEO_FILE"
    return 1
  }

  success_echo "MP4 已生成：$VIDEO_FILE"
  return 0
}
# 封装 build_screen_gif_filter 对应的独立处理逻辑。
build_screen_gif_filter() {
  local fps_value="$GIF_SCREEN_FPS"
  local width_value="$GIF_SCREEN_GIF_WIDTH"

  [[ -n "$fps_value" ]] || fps_value="24"
  [[ -n "$width_value" ]] || width_value="1600"

  if [[ "$width_value" == "0" ]]; then
    printf "fps=%s" "$fps_value"
  else
    printf "fps=%s,scale=%s:-1:flags=lanczos" "$fps_value" "$width_value"
  fi
}
# 封装 convert_screen_mov_to_mp4 对应的独立处理逻辑。
convert_screen_mov_to_mp4() {
  [[ "$GIF_VIDEO_ENABLED" == "true" ]] || return 0
  [[ -s "$SCREEN_MOV_FILE" ]] || {
    error_echo "缺少全屏原始录屏，无法生成 MP4：$SCREEN_MOV_FILE"
    return 1
  }

  local ffmpeg_bin="${FFMPEG_BIN:-}"
  [[ -n "$ffmpeg_bin" && -x "$ffmpeg_bin" ]] || ffmpeg_bin="$(find_tool ffmpeg 2>/dev/null || true)"
  [[ -n "$ffmpeg_bin" ]] || {
    error_echo "未找到 ffmpeg，无法转换 MP4"
    return 1
  }

  FFMPEG_BIN="$ffmpeg_bin"
  local video_tmp="$VIDEO_FILE.tmp.mp4"
  rm -f "$video_tmp"

  {
    echo "[gif] 开始转换全屏 MP4：$SCREEN_MOV_FILE -> $VIDEO_FILE"
    echo "[gif] ffmpeg: $ffmpeg_bin"
  } >> "$LOG_FILE"

  "$ffmpeg_bin" -y -i "$SCREEN_MOV_FILE" \
    -movflags +faststart \
    -pix_fmt yuv420p \
    -c:v libx264 \
    -crf "$GIF_VIDEO_CRF" \
    -preset "$GIF_VIDEO_PRESET" \
    "$video_tmp" >> "$LOG_FILE" 2>&1 || {
      error_echo "全屏 MP4 转换失败，请查看日志：$LOG_FILE"
      return 1
    }

  [[ -s "$video_tmp" ]] || {
    error_echo "全屏 MP4 临时文件生成失败：$video_tmp"
    return 1
  }

  mv -f "$video_tmp" "$VIDEO_FILE"
  success_echo "MP4 已生成：$VIDEO_FILE"
  return 0
}
# 封装 convert_screen_video_to_gif 对应的独立处理逻辑。
convert_screen_video_to_gif() {
  local source_video="$VIDEO_FILE"
  [[ -s "$source_video" ]] || source_video="$SCREEN_MOV_FILE"
  [[ -s "$source_video" ]] || {
    error_echo "缺少全屏视频，无法生成 GIF"
    return 1
  }

  local ffmpeg_bin="${FFMPEG_BIN:-}"
  [[ -n "$ffmpeg_bin" && -x "$ffmpeg_bin" ]] || ffmpeg_bin="$(find_tool ffmpeg 2>/dev/null || true)"
  [[ -n "$ffmpeg_bin" ]] || {
    error_echo "未找到 ffmpeg，无法转换 GIF"
    return 1
  }

  FFMPEG_BIN="$ffmpeg_bin"
  local palette_file="$OUTPUT_DIR/palette.png"
  local gif_tmp="$GIF_FILE.tmp"
  local vf="$(build_screen_gif_filter)"

  rm -f "$palette_file" "$gif_tmp"

  {
    echo "[gif] 开始转换全屏 GIF：$source_video -> $GIF_FILE"
    echo "[gif] ffmpeg: $ffmpeg_bin"
    echo "[gif] vf: $vf"
  } >> "$LOG_FILE"

  "$ffmpeg_bin" -y -i "$source_video" \
    -vf "$vf,palettegen=stats_mode=diff" \
    "$palette_file" >> "$LOG_FILE" 2>&1 || {
      error_echo "全屏 GIF 调色板生成失败，请查看日志：$LOG_FILE"
      rm -f "$palette_file"
      return 1
    }

  "$ffmpeg_bin" -y -i "$source_video" -i "$palette_file" \
    -lavfi "$vf [x]; [x][1:v] paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    "$gif_tmp" >> "$LOG_FILE" 2>&1 || {
      error_echo "全屏 GIF 转换失败，请查看日志：$LOG_FILE"
      rm -f "$palette_file" "$gif_tmp"
      return 1
    }

  rm -f "$palette_file"

  [[ -s "$gif_tmp" ]] || {
    error_echo "全屏 GIF 临时文件生成失败：$gif_tmp"
    return 1
  }

  mv -f "$gif_tmp" "$GIF_FILE"
  success_echo "GIF 已生成：$GIF_FILE"
  return 0
}
# 封装 notify_macos 对应的独立处理逻辑。
notify_macos() {
  local title="$1"
  local message="$2"

  command -v osascript >/dev/null 2>&1 || return 0
  /usr/bin/osascript -e "display notification \"${message}\" with title \"${title}\"" >/dev/null 2>&1 || true
}
# 封装 finish_recording 对应的独立处理逻辑。
finish_recording() {
  local result=0

  if [[ "$GIF_RECORD_MODE" == "screen" ]]; then
    [[ -s "$SCREEN_MOV_FILE" ]] || {
      error_echo "全屏录制文件不存在或为空：$SCREEN_MOV_FILE"
      return 1
    }

    convert_screen_mov_to_mp4 || result=1
    if (( result == 0 )); then
      convert_screen_video_to_gif || result=1
    fi
  else
    [[ -s "$CAST_FILE" ]] || {
      error_echo "录制文件不存在或为空：$CAST_FILE"
      return 1
    }

    convert_to_gif || result=1
    if (( result == 0 )); then
      convert_to_mp4 || result=1
    fi
  fi

  if (( result != 0 )); then
    error_echo "转码失败，仅保留已有文件：$OUTPUT_DIR"
    error_echo "可稍后执行：gif --repair "$OUTPUT_DIR""
    return 1
  fi

  write_metadata
  write_latest_path
  notify_macos "Jobs GIF" "GIF / MP4 已生成：$(basename "$OUTPUT_DIR")"

  if [[ "$GIF_CLEAR_AFTER_FINISH" == "true" ]]; then
    clear_terminal_soft
  else
    success_echo "输出目录：$OUTPUT_DIR"
  fi

  return 0
}
# 封装 create_recording_zdotdir 对应的独立处理逻辑。
create_recording_zdotdir() {
  RECORD_ZDOTDIR="$OUTPUT_DIR/.gif-zdotdir"
  mkdir -p "$RECORD_ZDOTDIR"

  cat > "$RECORD_ZDOTDIR/.zshenv" <<'EOF_ZSHENV'
[[ -r "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
export JOBS_GIF_RECORDING=1
EOF_ZSHENV

  cat > "$RECORD_ZDOTDIR/.zprofile" <<'EOF_ZPROFILE'
[[ -r "$HOME/.zprofile" ]] && source "$HOME/.zprofile"
EOF_ZPROFILE

  cat > "$RECORD_ZDOTDIR/.zlogin" <<'EOF_ZLOGIN'
[[ -r "$HOME/.zlogin" ]] && source "$HOME/.zlogin"
EOF_ZLOGIN

  cat > "$RECORD_ZDOTDIR/.zlogout" <<'EOF_ZLOGOUT'
[[ -r "$HOME/.zlogout" ]] && source "$HOME/.zlogout"
EOF_ZLOGOUT

  cat > "$RECORD_ZDOTDIR/.zshrc" <<'EOF_ZSHRC'
[[ -r "$HOME/.zshrc" ]] && source "$HOME/.zshrc"

# gif 录制期间，Ctrl-C 直接退出录制 shell；关闭 ECHOCTL 避免显示 ^C。
if [[ "${JOBS_GIF_RECORDING:-}" == "1" ]]; then
  stty -echoctl 2>/dev/null || true
  # 封装 TRAPINT 对应的独立处理逻辑。
  TRAPINT() { exit 130 }
fi
EOF_ZSHRC
}
# 封装 start_terminal_recording 对应的独立处理逻辑。
start_terminal_recording() {
  local record_shell="/bin/zsh"
  local record_command=""
  local zdotdir_arg=""

  if [[ ! -x "$record_shell" ]]; then
    record_shell="$(command -v zsh 2>/dev/null || true)"
  fi
  [[ -n "$record_shell" ]] || { error_echo "未找到 zsh，无法启动录制 shell"; exit 1; }

  create_recording_zdotdir
  zdotdir_arg="$(quote_value "$RECORD_ZDOTDIR")"
  record_command="ZDOTDIR=${zdotdir_arg} JOBS_GIF_RECORDING=1 exec $(quote_value "$record_shell") -l"

  clear_terminal_soft
  sleep 0.15

  # Ctrl-C 用来结束 asciinema 录制；这里不设置额外 trap，避免提前打断后续转码。
  if ! ASCIINEMA_REC=1 asciinema rec -q --overwrite --idle-time-limit "$GIF_REC_IDLE_LIMIT" --command "$record_command" "$CAST_FILE"; then
    echo "[gif] asciinema rec 已结束或被 Ctrl-C 中断，继续执行转码" >> "$LOG_FILE"
  fi
}
# 封装 start_screen_recording 对应的独立处理逻辑。
start_screen_recording() {
  local screencapture_bin="${SCREENCAPTURE_BIN:-}"
  [[ -n "$screencapture_bin" && -x "$screencapture_bin" ]] || screencapture_bin="$(find_system_tool screencapture 2>/dev/null || true)"
  [[ -n "$screencapture_bin" ]] || { error_echo "未找到 screencapture，无法全屏录制"; exit 1; }
  SCREENCAPTURE_BIN="$screencapture_bin"

  local countdown="$GIF_SCREEN_COUNTDOWN"
  is_positive_int "$countdown" || countdown="3"

  clear_terminal_soft
  info_echo "全屏录制将在 ${countdown} 秒后开始。"
  info_echo "现在可以切换到你要展示的屏幕；录制中按 Ctrl-C 结束。"
  sleep 1

  while (( countdown > 0 )); do
    clear_terminal_soft
    bold_echo "全屏录制倒计时：${countdown}"
    sleep 1
    countdown=$((countdown - 1))
  done

  clear_terminal_soft
  sleep 0.2

  local -a capture_args
  capture_args=(-v)
  [[ "$GIF_SCREEN_SHOW_CURSOR" == "true" ]] && capture_args+=(-g)

  {
    echo "[gif] 开始全屏录制：$screencapture_bin ${capture_args[*]} $SCREEN_MOV_FILE"
    echo "[gif] 结束方式：Ctrl-C"
  } >> "$LOG_FILE"

  if ! "$screencapture_bin" "${capture_args[@]}" "$SCREEN_MOV_FILE"; then
    echo "[gif] screencapture 已结束或被 Ctrl-C 中断，继续执行转码" >> "$LOG_FILE"
  fi
}
# 封装 start_recording 对应的独立处理逻辑。
start_recording() {
  if [[ "$GIF_RECORD_MODE" == "screen" ]]; then
    start_screen_recording
  else
    start_terminal_recording
  fi
}
# 封装 repair_from_path 对应的独立处理逻辑。
repair_from_path() {
  local target="$1"
  local dir=""

  load_config
  target="$(normalize_dragged_path "$target")"

  if [[ -d "$target" ]]; then
    dir="$target"
    set_output_files "$dir"
    if [[ -s "$CAST_FILE" ]]; then
      GIF_RECORD_MODE="terminal"
    elif [[ -s "$SCREEN_MOV_FILE" ]]; then
      GIF_RECORD_MODE="screen"
    else
      error_echo "repair 目录内未找到 session.cast 或 session.mov：$target"
      return 1
    fi
  elif [[ -f "$target" ]]; then
    dir="$(cd "$(dirname "$target")" && pwd)"
    set_output_files "$dir"
    case "$target" in
      *.cast)
        GIF_RECORD_MODE="terminal"
        CAST_FILE="$target"
        ;;
      *.mov)
        GIF_RECORD_MODE="screen"
        SCREEN_MOV_FILE="$target"
        ;;
      *)
        error_echo "repair 只支持 session.cast 或 session.mov：$target"
        return 1
        ;;
    esac
  else
    error_echo "repair 目标不存在：$target"
    return 1
  fi

  ensure_dependencies false "$GIF_RECORD_MODE"
  finish_recording
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：gif.command' | jobs_intro_style title
  print -r -- '核心用途：执行“gif”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  # 根据当前条件选择对应的执行分支。
  case "${1:-}" in
    -h|--help|help)
      # 执行当前流程中的独立业务步骤：show_usage。
      show_usage
      # 执行当前流程中的独立业务步骤：return。
      return 0
      ;;
    --repair|repair)
      # 根据当前条件选择对应的执行分支。
      if [[ -z "${2:-}" ]]; then
        # 执行当前流程中的独立业务步骤：error_echo。
        error_echo "缺少 repair 目标：输出目录或 session.cast"
        # 输出当前步骤的提示或执行进度。
        echo "用法：gif --repair <输出目录或 session.cast>"
        # 执行当前流程中的独立业务步骤：return。
        return 1
      fi
      # 执行当前流程中的独立业务步骤：repair_from_path。
      repair_from_path "$2"
      # 执行当前流程中的独立业务步骤：return。
      return $?
      ;;
  esac

  # 展示脚本说明并等待用户确认影响范围。
  show_intro_if_double_clicked
  # 准备后续业务需要的配置、目录或运行上下文。
  load_config
  # 执行当前流程中的独立业务步骤：prompt_launch_mode。
  prompt_launch_mode

  # 根据当前条件选择对应的执行分支。
  if [[ "$SETTINGS_MENU" == "true" ]]; then
    # 执行当前流程中的独立业务步骤：prompt_record_mode。
    prompt_record_mode
    # 执行当前流程中的独立业务步骤：prompt_output_path。
    prompt_output_path
    # 执行当前流程中的独立业务步骤：prompt_quality。
    prompt_quality
    # 准备后续业务需要的配置、目录或运行上下文。
    save_config
  else
    # 直接回车启动时，默认永远录制当前终端，避免上次选择全屏后误录整个屏幕。
    GIF_RECORD_MODE="terminal"
    # 准备后续业务需要的配置、目录或运行上下文。
    prepare_default_output_path
  fi

  # 检查当前步骤所需的环境、路径或输入条件。
  ensure_dependencies "$SETTINGS_MENU" "$GIF_RECORD_MODE"

  # 执行当前流程中的独立业务步骤：write_metadata。
  write_metadata
  # 执行当前流程中的独立业务步骤：write_latest_path。
  write_latest_path
  # 执行当前流程中的独立业务步骤：start_recording。
  start_recording
  finish_recording || return 1
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  set -u
  set -o pipefail
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_script_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行入口下沉后的完整业务流程。
  run_main_business_flow "$@"
}

main "$@"
