#!/bin/zsh
# 脚本自述：
# - 脚本名称：tts.command
# - 核心用途：执行“tts”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


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

SUPERTONIC_VENV_DIR="${SUPERTONIC_VENV_DIR:-${HOME}/Desktop/supertonic-venv}"
SUPERTONIC_HOST="${SUPERTONIC_HOST:-127.0.0.1}"
SUPERTONIC_PORT="${SUPERTONIC_PORT:-7788}"
SUPERTONIC_VOICE="${SUPERTONIC_VOICE:-M1}"
SUPERTONIC_LANG="${SUPERTONIC_LANG:-auto}"
SUPERTONIC_STEPS="${SUPERTONIC_STEPS:-8}"
SUPERTONIC_SPEED="${SUPERTONIC_SPEED:-1.0}"
SUPERTONIC_OUTPUT_DIR="${SUPERTONIC_OUTPUT_DIR:-${SCRIPT_DIR}/outputs}"
SUPERTONIC_ZH_ENGINE="${SUPERTONIC_ZH_ENGINE:-say}"
SUPERTONIC_ZH_VOICE="${SUPERTONIC_ZH_VOICE:-}"
SUPERTONIC_ZH_RATE="${SUPERTONIC_ZH_RATE:-200}"

MOSS_TTS_NANO_HOME="${MOSS_TTS_NANO_HOME:-${HOME}/Desktop/MOSS-TTS-Nano}"
MOSS_TTS_NANO_VENV_DIR="${MOSS_TTS_NANO_VENV_DIR:-${HOME}/Desktop/moss-tts-nano-venv}"
MOSS_TTS_NANO_BACKEND="${MOSS_TTS_NANO_BACKEND:-onnx}"
MOSS_TTS_NANO_EXECUTION_PROVIDER="${MOSS_TTS_NANO_EXECUTION_PROVIDER:-cpu}"
MOSS_TTS_NANO_PROMPT_SPEECH="${MOSS_TTS_NANO_PROMPT_SPEECH:-${MOSS_TTS_NANO_HOME}/assets/audio/zh_1.wav}"
MOSS_TTS_NANO_OUTPUT_DIR="${MOSS_TTS_NANO_OUTPUT_DIR:-${SCRIPT_DIR}/outputs}"
MOSS_TTS_NANO_REPO_URL="${MOSS_TTS_NANO_REPO_URL:-https://github.com/OpenMOSS/MOSS-TTS-Nano.git}"
MOSS_TTS_NANO_SKIP_INSTALL="${MOSS_TTS_NANO_SKIP_INSTALL:-0}"

VOXCPM_VENV_DIR="${VOXCPM_VENV_DIR:-${HOME}/Desktop/voxcpm-venv}"
VOXCPM_OUTPUT_DIR="${VOXCPM_OUTPUT_DIR:-${SCRIPT_DIR}/outputs}"
VOXCPM_DEVICE="${VOXCPM_DEVICE:-auto}"
VOXCPM_CONTROL="${VOXCPM_CONTROL:-}"
VOXCPM_REFERENCE_AUDIO="${VOXCPM_REFERENCE_AUDIO:-}"
VOXCPM_PROMPT_AUDIO="${VOXCPM_PROMPT_AUDIO:-}"
VOXCPM_PROMPT_TEXT="${VOXCPM_PROMPT_TEXT:-}"
VOXCPM_DENOISE="${VOXCPM_DENOISE:-0}"
VOXCPM_NO_OPTIMIZE="${VOXCPM_NO_OPTIMIZE:-1}"
VOXCPM_HF_ENDPOINT="${VOXCPM_HF_ENDPOINT:-}"
VOXCPM_SKIP_INSTALL="${VOXCPM_SKIP_INSTALL:-0}"
TTS_ENGINE="${TTS_ENGINE:-}"
FZF_BIN="${FZF_BIN:-}"
TTS_SELECTED_ENGINE=""

SERVER_URL="http://${SUPERTONIC_HOST}:${SUPERTONIC_PORT}"
SERVER_LOG="/tmp/${SCRIPT_BASENAME}.server.log"
SERVER_PID_FILE="/tmp/${SCRIPT_BASENAME}.server.pid"
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
# ---------- 通用交互 ----------
# 解析并返回后续流程需要的目标信息。
find_fzf_bin() {
  if command -v fzf >/dev/null 2>&1; then
    command -v fzf
    return 0
  fi

  local brew_prefix=""
  if command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
    if [[ -n "$brew_prefix" && -x "$brew_prefix/bin/fzf" ]]; then
      print -r -- "$brew_prefix/bin/fzf"
      return 0
    fi
  fi

  return 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_fzf_for_engine_menu() {
  if FZF_BIN="$(find_fzf_bin 2>/dev/null)"; then
    return 0
  fi

  warn_echo "未检测到 fzf，TTS 引擎选择菜单需要 fzf。"
  if command -v brew >/dev/null 2>&1; then
    if ask_enter_to_run "是否自动执行 brew install fzf"; then
      brew install fzf || return 1
      FZF_BIN="$(find_fzf_bin 2>/dev/null)" || return 1
      return 0
    fi
  else
    warn_echo "当前未检测到 Homebrew，无法自动安装 fzf。"
  fi

  return 1
}
# 收集并校验用户输入，决定后续执行路径。
select_tts_engine_text_fallback() {
  local answer=""
  echo ""
  highlight_echo "====================== 请选择 TTS 引擎 ======================" 
  log "1) MOSS-TTS-Nano    优势：CPU 友好、中文/中英混读、长文本；劣势：音质/表现力弱于 VoxCPM2"
  log "2) VoxCPM2          优势：30 语言、48kHz、声音设计/克隆；劣势：2B 大模型，首次下载大，CPU 慢"
  log "3) Supertonic       优势：轻量稳定、启动快、英文/日韩；劣势：无官方中文，中文走 macOS say"
  log "q) 退出"
  highlight_echo "============================================================"
  read -r "?请输入序号，默认 1：" answer
  case "$answer" in
    ""|1|moss|MOSS|moss-tts|moss-tts-nano) TTS_SELECTED_ENGINE="moss"; return 0 ;;
    2|voxcpm|VoxCPM|VoxCPM2|vox|VOX) TTS_SELECTED_ENGINE="voxcpm"; return 0 ;;
    3|supertonic|Supertonic|st|ST) TTS_SELECTED_ENGINE="supertonic"; return 0 ;;
    q|Q|quit|exit) return 1 ;;
    *) warn_echo "未知选择，默认使用 MOSS-TTS-Nano。"; TTS_SELECTED_ENGINE="moss"; return 0 ;;
  esac
}
# 收集并校验用户输入，决定后续执行路径。
select_tts_engine() {
  local selected=""
  local selected_engine=""

  if [[ -n "${TTS_ENGINE:-}" ]]; then
    case "$TTS_ENGINE" in
      moss|moss-tts|moss-tts-nano|MOSS|MOSS-TTS|MOSS-TTS-Nano) TTS_SELECTED_ENGINE="moss"; return 0 ;;
      voxcpm|voxcpm2|vox|VoxCPM|VoxCPM2|VOX) TTS_SELECTED_ENGINE="voxcpm"; return 0 ;;
      supertonic|Supertonic|st|ST) TTS_SELECTED_ENGINE="supertonic"; return 0 ;;
    esac
  fi

  if ensure_fzf_for_engine_menu; then
    selected="$(cat <<'ENGINE_MENU_EOF' | "$FZF_BIN" \
      --delimiter=$'\t' \
      --with-nth=2,3 \
      --prompt='TTS Engine > ' \
      --height=45% \
      --border \
      --no-sort \
      --layout=reverse \
      --header=$'选择本次朗读引擎：Enter 确认，Esc 取消。可输入 moss / voxcpm / supertonic 快速过滤。每行已写明优势和劣势。'
moss	MOSS-TTS-Nano	优势：CPU 友好、中文/中英混读、长文本；劣势：音质/表现力弱于 VoxCPM2
voxcpm	VoxCPM2	优势：30 语言、48kHz、声音设计/克隆；劣势：2B 大模型，首次下载大，CPU 慢
supertonic	Supertonic	优势：轻量稳定、启动快、英文/日韩；劣势：无官方中文，中文走 macOS say
ENGINE_MENU_EOF
)"
    [[ -z "$selected" ]] && return 1
    selected_engine="${selected%%$'\t'*}"
    case "$selected_engine" in
      moss|voxcpm|supertonic) TTS_SELECTED_ENGINE="$selected_engine"; return 0 ;;
    esac
  fi

  select_tts_engine_text_fallback
}
# 封装 print_engine_banner 对应的独立处理逻辑。
print_engine_banner() {
  local engine="$1"
  echo ""
  case "$engine" in
    moss)
      highlight_echo "已选择：MOSS-TTS-Nano（CPU 友好 / 中文增强 / 长文本）"
      ;;
    voxcpm)
      highlight_echo "已选择：VoxCPM2（高质量 / 声音设计 / 声音克隆）"
      ;;
    supertonic)
      highlight_echo "已选择：Supertonic（轻量稳定 / 原有逻辑）"
      ;;
  esac
  echo ""
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme_and_wait() {
  clear
  highlight_echo "==================== 【MacOS】🔊Supertonic 本地朗读 ====================" | jobs_intro_style title
  color_echo "用途：输入文本，调用本机 TTS 生成语音并立即播放。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  info_echo "Supertonic 服务：${SERVER_URL}" | jobs_intro_style body
  info_echo "默认虚拟环境：${SUPERTONIC_VENV_DIR}" | jobs_intro_style body
  info_echo "英文等支持语言：走 Supertonic" | jobs_intro_style body
  info_echo "中文：默认走 macOS say，避免 Supertonic 中文发音错误" | jobs_intro_style body
  echo "" | jobs_intro_style body
  note_echo "常用输入：" | jobs_intro_style title
  gray_echo "  直接输入文本            立即朗读，例如：fuck / 你好" | jobs_intro_style body
  gray_echo "  :zh-voices              查看本机中文语音" | jobs_intro_style body
  gray_echo "  :zh-voice Tingting      指定中文语音" | jobs_intro_style body
  gray_echo "  :zh-rate 200            指定中文语速" | jobs_intro_style body
  gray_echo "  :zh-engine say          中文走 macOS say，默认推荐" | jobs_intro_style body
  gray_echo "  :zh-engine supertonic   中文也强制走 Supertonic，不推荐" | jobs_intro_style body
  gray_echo "  :voice F1               切换 Supertonic 声音" | jobs_intro_style body
  gray_echo "  :lang en                切换 Supertonic 语言" | jobs_intro_style body
  gray_echo "  :docs                   打开本地接口文档" | jobs_intro_style body
  gray_echo "  :stop                   停止本脚本启动的后台服务" | jobs_intro_style body
  gray_echo "  :quit                   退出" | jobs_intro_style body
  echo "" | jobs_intro_style body
  warn_echo "说明：Supertonic 当前没有 zh 中文模型；中文默认交给 macOS say。" | jobs_intro_style body
  gray_echo "日志：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "=======================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?👉 按回车进入朗读；按 Ctrl+C 取消：" _
}
# 收集并校验用户输入，决定后续执行路径。
ask_enter_to_run() {
  local message="$1"
  local answer=""
  read -r "?${message}（直接回车执行；输入任意字符后回车跳过）：" answer
  [[ -z "$answer" ]]
}
# 封装 strip_outer_quotes 对应的独立处理逻辑。
strip_outer_quotes() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value%$'\n'}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  print -r -- "$value"
}
# 封装 python_bin 对应的独立处理逻辑。
python_bin() {
  print -r -- "${SUPERTONIC_VENV_DIR}/bin/python"
}
# 封装 supertonic_bin 对应的独立处理逻辑。
supertonic_bin() {
  print -r -- "${SUPERTONIC_VENV_DIR}/bin/supertonic"
}
# 封装 require_command 对应的独立处理逻辑。
require_command() {
  local cmd="$1"
  local tip="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error_echo "未找到命令：${cmd}"
    err_echo "$tip"
    return 1
  fi
  success_echo "已检测到 ${cmd}：$(command -v "$cmd")"
}
# ---------- 环境检查 ----------
install_or_repair_environment() {
  local py3=""
  py3="$(command -v python3 || true)"

  if [[ -z "$py3" ]]; then
    error_echo "未找到 python3，无法创建虚拟环境。"
    err_echo "请先安装 Python，例如：brew install python"
    return 1
  fi

  mkdir -p "$(dirname "$SUPERTONIC_VENV_DIR")"

  if [[ ! -d "$SUPERTONIC_VENV_DIR" ]]; then
    note_echo "开始创建虚拟环境：${SUPERTONIC_VENV_DIR}"
    "$py3" -m venv "$SUPERTONIC_VENV_DIR" >> "$LOG_FILE" 2>&1 || return 1
  fi

  local py="$(python_bin)"
  if [[ ! -x "$py" ]]; then
    error_echo "虚拟环境 Python 不可执行：${py}"
    return 1
  fi

  note_echo "开始安装 / 补齐 supertonic[serve] 依赖。"
  "$py" -m pip install --upgrade pip >> "$LOG_FILE" 2>&1 || return 1
  "$py" -m pip install 'supertonic[serve]' >> "$LOG_FILE" 2>&1 || return 1
  success_echo "Supertonic 依赖已安装 / 补齐。"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_environment() {
  require_command "curl" "macOS 通常自带 curl，如果缺失请检查系统环境。" || return 1

  local py="$(python_bin)"
  local st="$(supertonic_bin)"

  if [[ ! -x "$py" || ! -x "$st" ]]; then
    warn_echo "未检测到可用的 Supertonic 虚拟环境：${SUPERTONIC_VENV_DIR}"
    gray_echo "当前脚本默认读取：~/Desktop/supertonic-venv"
    gray_echo "如果虚拟环境不在默认位置，可以这样指定："
    gray_echo "SUPERTONIC_VENV_DIR=/你的/venv/路径 ${SCRIPT_PATH}"
    echo ""
    if ask_enter_to_run "是否自动创建 / 修复虚拟环境并安装 supertonic[serve]"; then
      install_or_repair_environment || {
        error_echo "环境创建 / 修复失败。日志：${LOG_FILE}"
        return 1
      }
    else
      error_echo "已跳过安装，无法继续朗读。"
      return 1
    fi
  fi

  "$py" - <<'PY' >/dev/null 2>&1
import supertonic
PY
  if [[ $? -ne 0 ]]; then
    warn_echo "虚拟环境存在，但无法 import supertonic。"
    if ask_enter_to_run "是否自动重新安装 / 补齐 supertonic[serve]"; then
      install_or_repair_environment || return 1
    else
      error_echo "已跳过修复，无法继续朗读。"
      return 1
    fi
  fi

  success_echo "Supertonic 虚拟环境可用：${SUPERTONIC_VENV_DIR}"
}
# ---------- 服务管理 ----------
is_server_alive() {
  curl -fsS "${SERVER_URL}/docs" >/dev/null 2>&1
}
# 封装 start_server_if_needed 对应的独立处理逻辑。
start_server_if_needed() {
  if is_server_alive; then
    success_echo "本地 Supertonic 服务已可用：${SERVER_URL}"
    return 0
  fi

  local st="$(supertonic_bin)"
  if [[ ! -x "$st" ]]; then
    error_echo "未找到 supertonic 可执行文件：${st}"
    return 1
  fi

  note_echo "正在后台启动 Supertonic 服务：${SERVER_URL}"
  gray_echo "首次运行可能会下载模型，服务日志：${SERVER_LOG}"
  : > "$SERVER_LOG"

  nohup "$st" serve --host "$SUPERTONIC_HOST" --port "$SUPERTONIC_PORT" >> "$SERVER_LOG" 2>&1 &
  local pid="$!"
  print -r -- "$pid" > "$SERVER_PID_FILE"

  local i=0
  while (( i < 420 )); do
    if is_server_alive; then
      success_echo "Supertonic 服务启动成功：${SERVER_URL}"
      return 0
    fi
    sleep 1
    (( i++ ))
  done

  error_echo "Supertonic 服务启动超时。"
  if command -v lsof >/dev/null 2>&1; then
    gray_echo "端口占用情况："
    lsof -nP -iTCP:"$SUPERTONIC_PORT" -sTCP:LISTEN 2>/dev/null | tee -a "$LOG_FILE" || true
  fi
  gray_echo "最近服务日志："
  tail -n 80 "$SERVER_LOG" 2>/dev/null | tee -a "$LOG_FILE"
  return 1
}
# 封装 stop_started_server 对应的独立处理逻辑。
stop_started_server() {
  if [[ ! -f "$SERVER_PID_FILE" ]]; then
    warn_echo "未找到本脚本记录的服务 PID：${SERVER_PID_FILE}"
    return 0
  fi

  local pid="$(cat "$SERVER_PID_FILE" 2>/dev/null)"
  if [[ -z "$pid" ]]; then
    warn_echo "服务 PID 为空。"
    return 0
  fi

  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    rm -f "$SERVER_PID_FILE"
    success_echo "已停止本脚本启动的 Supertonic 服务：PID ${pid}"
  else
    rm -f "$SERVER_PID_FILE"
    warn_echo "记录的服务进程已不存在：PID ${pid}"
  fi
}
# ---------- 中文 fallback ----------
contains_chinese() {
  local text="$1"
  local py="$(python_bin)"
  "$py" - "$text" <<'PY'
import re
import sys
print("yes" if re.search(r"[\u4e00-\u9fff]", sys.argv[1]) else "no")
PY
}
# 封装 list_macos_chinese_voices 对应的独立处理逻辑。
list_macos_chinese_voices() {
  if ! command -v say >/dev/null 2>&1; then
    error_echo "当前系统未找到 macOS say 命令。"
    return 1
  fi
  note_echo "本机可疑中文语音如下；如果为空，请去系统设置里下载中文朗读声音。"
  say -v '?' 2>/dev/null | grep -Ei 'zh_|chinese|mandarin|cantonese|tingting|mei-?jia|sin-?ji|yu-?shu|li-?mu' | tee -a "$LOG_FILE" || true
}
# 封装 pick_macos_chinese_voice 对应的独立处理逻辑。
pick_macos_chinese_voice() {
  if [[ -n "$SUPERTONIC_ZH_VOICE" ]]; then
    print -r -- "$SUPERTONIC_ZH_VOICE"
    return 0
  fi

  local voices
  voices="$(say -v '?' 2>/dev/null || true)"

  local preferred
  for preferred in Tingting Mei-Jia Meijia Sin-ji Sinji Yu-shu Yushu Li-mu Limu; do
    if print -r -- "$voices" | awk '{print $1}' | grep -Fxq "$preferred"; then
      print -r -- "$preferred"
      return 0
    fi
  done

  local detected
  detected="$(print -r -- "$voices" | awk 'BEGIN{IGNORECASE=1} /zh_|Chinese|Mandarin|Cantonese/ {print $1; exit}')"
  if [[ -n "$detected" ]]; then
    print -r -- "$detected"
    return 0
  fi

  return 1
}
# 封装 speak_chinese_with_macos_say 对应的独立处理逻辑。
speak_chinese_with_macos_say() {
  local raw_text="$1"
  local text="$(strip_outer_quotes "$raw_text")"

  if ! command -v say >/dev/null 2>&1; then
    error_echo "未找到 macOS say 命令，无法使用中文 fallback。"
    return 1
  fi

  local timestamp="$(date '+%Y%m%d_%H%M%S')"
  mkdir -p "$SUPERTONIC_OUTPUT_DIR"
  local output_file="${SUPERTONIC_OUTPUT_DIR}/macos_say_zh_${timestamp}.aiff"

  local voice=""
  voice="$(pick_macos_chinese_voice || true)"

  if [[ -n "$voice" ]]; then
    note_echo "检测到中文：使用 macOS say 朗读，voice=${voice} rate=${SUPERTONIC_ZH_RATE}"
    say -v "$voice" -r "$SUPERTONIC_ZH_RATE" -o "$output_file" "$text" >> "$LOG_FILE" 2>&1
  else
    warn_echo "未找到明确中文语音，使用 macOS 默认语音尝试朗读。"
    warn_echo "建议下载中文语音后执行 :zh-voices / :zh-voice。"
    say -r "$SUPERTONIC_ZH_RATE" -o "$output_file" "$text" >> "$LOG_FILE" 2>&1
  fi

  if [[ $? -ne 0 || ! -s "$output_file" ]]; then
    error_echo "macOS say 生成中文音频失败：${output_file}"
    return 1
  fi

  success_echo "中文语音已生成：${output_file}"

  if command -v afplay >/dev/null 2>&1; then
    afplay "$output_file"
  else
    open "$output_file"
  fi
}
# ---------- 语音生成 ----------
detect_lang() {
  local text="$1"
  local py="$(python_bin)"
  "$py" - "$text" <<'PY'
import re
import sys

text = sys.argv[1]
if re.search(r"[\u3040-\u30ff]", text):
    print("ja")
elif re.search(r"[\uac00-\ud7af]", text):
    print("ko")
elif re.search(r"[\u4e00-\u9fff]", text):
    print("na")
else:
    print("en")
PY
}
# 封装 build_payload 对应的独立处理逻辑。
build_payload() {
  local text="$1"
  local lang="$2"
  local py="$(python_bin)"
  "$py" - "$text" "$SUPERTONIC_VOICE" "$lang" "$SUPERTONIC_STEPS" "$SUPERTONIC_SPEED" <<'PY'
import json
import sys

text, voice, lang, steps, speed = sys.argv[1:6]
payload = {
    "text": text,
    "voice": voice,
    "lang": lang,
    "steps": int(steps),
    "speed": float(speed),
    "response_format": "wav",
}
print(json.dumps(payload, ensure_ascii=False))
PY
}
# 封装 speak_text 对应的独立处理逻辑。
speak_text() {
  local raw_text="$1"
  local text="$(strip_outer_quotes "$raw_text")"

  if [[ -z "$text" ]]; then
    warn_echo "空文本，已跳过。"
    return 0
  fi

  local has_chinese="$(contains_chinese "$text")"
  if [[ "$has_chinese" == "yes" && "$SUPERTONIC_ZH_ENGINE" == "say" ]]; then
    speak_chinese_with_macos_say "$text"
    return $?
  fi

  local lang="$SUPERTONIC_LANG"
  if [[ "$lang" == "auto" ]]; then
    lang="$(detect_lang "$text")"
  fi

  local timestamp="$(date '+%Y%m%d_%H%M%S')"
  mkdir -p "$SUPERTONIC_OUTPUT_DIR"
  local output_file="${SUPERTONIC_OUTPUT_DIR}/supertonic_${timestamp}.wav"
  local payload="$(build_payload "$text" "$lang")"

  note_echo "正在生成语音：voice=${SUPERTONIC_VOICE} lang=${lang} steps=${SUPERTONIC_STEPS} speed=${SUPERTONIC_SPEED}"

  curl -fsS -X POST "${SERVER_URL}/v1/tts" \
    -H 'content-type: application/json' \
    -d "$payload" \
    -o "$output_file" >> "$LOG_FILE" 2>&1

  if [[ $? -ne 0 || ! -s "$output_file" ]]; then
    error_echo "语音生成失败：${output_file}"
    gray_echo "最近服务日志："
    tail -n 80 "$SERVER_LOG" 2>/dev/null | tee -a "$LOG_FILE"
    return 1
  fi

  success_echo "语音已生成：${output_file}"

  if command -v afplay >/dev/null 2>&1; then
    afplay "$output_file"
  else
    open "$output_file"
  fi
}
# ---------- MOSS-TTS-Nano 引擎 ----------
moss_python_bin() {
  print -r -- "${MOSS_TTS_NANO_VENV_DIR}/bin/python"
}
# 封装 moss_cli_bin 对应的独立处理逻辑。
moss_cli_bin() {
  print -r -- "${MOSS_TTS_NANO_VENV_DIR}/bin/moss-tts-nano"
}
# 封装 moss_install_or_repair_environment 对应的独立处理逻辑。
moss_install_or_repair_environment() {
  local py3=""
  py3="$(command -v python3 || true)"

  if [[ -z "$py3" ]]; then
    error_echo "未找到 python3，无法创建 MOSS-TTS-Nano 虚拟环境。"
    err_echo "请先安装 Python，例如：brew install python"
    return 1
  fi

  local py_version=""
  py_version="$($py3 - <<'MOSS_PYVER_EOF' 2>/dev/null
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
MOSS_PYVER_EOF
)"
  if [[ -n "$py_version" ]]; then
    local major="${py_version%%.*}"
    local minor="${py_version#*.}"
    if (( major < 3 || (major == 3 && minor < 10) )); then
      error_echo "MOSS-TTS-Nano 需要 Python >= 3.10，当前 python3=${py_version}。"
      err_echo "建议执行：brew install python"
      return 1
    fi
  fi

  if ! command -v git >/dev/null 2>&1; then
    error_echo "未找到 git，无法拉取 MOSS-TTS-Nano 仓库。"
    err_echo "请先安装 git，例如：brew install git"
    return 1
  fi

  mkdir -p "$(dirname "$MOSS_TTS_NANO_HOME")" "$(dirname "$MOSS_TTS_NANO_VENV_DIR")"

  if [[ ! -d "$MOSS_TTS_NANO_HOME/.git" ]]; then
    if [[ -e "$MOSS_TTS_NANO_HOME" ]]; then
      error_echo "目标目录已存在但不是 git 仓库：${MOSS_TTS_NANO_HOME}"
      err_echo "请删除 / 改名后重试，或设置 MOSS_TTS_NANO_HOME 指向正确仓库。"
      return 1
    fi
    note_echo "开始克隆 MOSS-TTS-Nano：${MOSS_TTS_NANO_HOME}"
    git clone "$MOSS_TTS_NANO_REPO_URL" "$MOSS_TTS_NANO_HOME" >> "$LOG_FILE" 2>&1 || return 1
  else
    note_echo "检测到 MOSS-TTS-Nano 仓库，执行 git pull 同步。"
    (cd "$MOSS_TTS_NANO_HOME" && git pull --ff-only) >> "$LOG_FILE" 2>&1 || warn_echo "git pull 失败，继续使用本地已有版本。"
  fi

  if [[ ! -d "$MOSS_TTS_NANO_VENV_DIR" ]]; then
    note_echo "开始创建 MOSS-TTS-Nano 虚拟环境：${MOSS_TTS_NANO_VENV_DIR}"
    "$py3" -m venv "$MOSS_TTS_NANO_VENV_DIR" >> "$LOG_FILE" 2>&1 || return 1
  fi

  local py="$(moss_python_bin)"
  if [[ ! -x "$py" ]]; then
    error_echo "MOSS-TTS-Nano 虚拟环境 Python 不可执行：${py}"
    return 1
  fi

  note_echo "开始安装 / 补齐 MOSS-TTS-Nano 依赖。"
  "$py" -m pip install --upgrade pip >> "$LOG_FILE" 2>&1 || return 1

  if [[ -f "$MOSS_TTS_NANO_HOME/requirements.txt" ]]; then
    (cd "$MOSS_TTS_NANO_HOME" && "$py" -m pip install -r requirements.txt) >> "$LOG_FILE" 2>&1 || {
      error_echo "MOSS-TTS-Nano requirements 安装失败。"
      warn_echo "常见原因：WeTextProcessing / pynini 在非 conda 环境安装失败。"
      err_echo "可按官方建议手动处理 pynini 后重试，日志：${LOG_FILE}"
      return 1
    }
  fi

  (cd "$MOSS_TTS_NANO_HOME" && "$py" -m pip install -e .) >> "$LOG_FILE" 2>&1 || return 1
  success_echo "MOSS-TTS-Nano 依赖已安装 / 补齐。"
}
# 封装 moss_ensure_environment 对应的独立处理逻辑。
moss_ensure_environment() {
  local cli="$(moss_cli_bin)"

  if [[ ! -x "$cli" || ! -d "$MOSS_TTS_NANO_HOME" ]]; then
    warn_echo "未检测到可用的 MOSS-TTS-Nano 环境。"
    gray_echo "默认仓库目录：${MOSS_TTS_NANO_HOME}"
    gray_echo "默认虚拟环境：${MOSS_TTS_NANO_VENV_DIR}"
    if [[ "$MOSS_TTS_NANO_SKIP_INSTALL" == "1" ]]; then
      error_echo "已设置 MOSS_TTS_NANO_SKIP_INSTALL=1，跳过自动安装。"
      return 1
    fi
    if ask_enter_to_run "是否自动克隆 / 创建虚拟环境 / 安装 MOSS-TTS-Nano"; then
      moss_install_or_repair_environment || {
        error_echo "MOSS-TTS-Nano 环境创建 / 修复失败。日志：${LOG_FILE}"
        return 1
      }
    else
      error_echo "已跳过安装，无法继续使用 MOSS-TTS-Nano。"
      return 1
    fi
  fi

  if [[ ! -f "$MOSS_TTS_NANO_PROMPT_SPEECH" ]]; then
    warn_echo "未找到 MOSS-TTS-Nano 参考音频：${MOSS_TTS_NANO_PROMPT_SPEECH}"
    gray_echo "脚本默认使用仓库内 assets/audio/zh_1.wav 作为 voice clone 参考音频。"
    gray_echo "可以通过 :prompt /path/to/your_voice.wav 或环境变量 MOSS_TTS_NANO_PROMPT_SPEECH 指定。"
  fi

  success_echo "MOSS-TTS-Nano 环境可用：${MOSS_TTS_NANO_HOME}"
}
# 封装 moss_detect_lang 对应的独立处理逻辑。
moss_detect_lang() {
  local text="$1"
  local py="$(moss_python_bin)"
  if [[ ! -x "$py" ]]; then
    py="$(command -v python3 || true)"
  fi
  "$py" - "$text" <<'MOSS_LANG_EOF'
import re, sys
text = sys.argv[1]
if re.search(r"[\u4e00-\u9fff]", text):
    print("zh")
elif re.search(r"[\u3040-\u30ff]", text):
    print("ja")
elif re.search(r"[\uac00-\ud7af]", text):
    print("ko")
else:
    print("en")
MOSS_LANG_EOF
}
# 封装 moss_speak_text 对应的独立处理逻辑。
moss_speak_text() {
  local raw_text="$1"
  local text="$(strip_outer_quotes "$raw_text")"

  if [[ -z "$text" ]]; then
    warn_echo "空文本，已跳过。"
    return 0
  fi

  local cli="$(moss_cli_bin)"
  if [[ ! -x "$cli" ]]; then
    error_echo "未找到 moss-tts-nano 命令：${cli}"
    return 1
  fi

  if [[ ! -f "$MOSS_TTS_NANO_PROMPT_SPEECH" ]]; then
    error_echo "未找到 MOSS-TTS-Nano 参考音频：${MOSS_TTS_NANO_PROMPT_SPEECH}"
    err_echo "请先执行：:prompt /path/to/your_voice.wav"
    return 1
  fi

  mkdir -p "$MOSS_TTS_NANO_OUTPUT_DIR" "$MOSS_TTS_NANO_HOME/generated_audio"
  local timestamp="$(date '+%Y%m%d_%H%M%S')"
  local default_output="${MOSS_TTS_NANO_HOME}/generated_audio/moss_tts_nano_output.wav"
  local output_file="${MOSS_TTS_NANO_OUTPUT_DIR}/moss_tts_nano_${timestamp}.wav"
  local detected_lang="$(moss_detect_lang "$text" 2>/dev/null || print -r -- auto)"

  note_echo "正在生成语音：engine=MOSS-TTS-Nano backend=${MOSS_TTS_NANO_BACKEND} provider=${MOSS_TTS_NANO_EXECUTION_PROVIDER} lang=${detected_lang}"
  gray_echo "参考音频：${MOSS_TTS_NANO_PROMPT_SPEECH}"
  gray_echo "首次运行会自动下载 ONNX 模型，耗时取决于网络。"

  rm -f "$default_output"

  local cmd=("$cli" generate --prompt-speech "$MOSS_TTS_NANO_PROMPT_SPEECH" --text "$text")
  if [[ -n "$MOSS_TTS_NANO_BACKEND" ]]; then
    cmd+=(--backend "$MOSS_TTS_NANO_BACKEND")
  fi
  if [[ "$MOSS_TTS_NANO_BACKEND" == "onnx" && -n "$MOSS_TTS_NANO_EXECUTION_PROVIDER" ]]; then
    cmd+=(--execution-provider "$MOSS_TTS_NANO_EXECUTION_PROVIDER")
  fi

  (cd "$MOSS_TTS_NANO_HOME" && "${cmd[@]}") >> "$LOG_FILE" 2>&1
  if [[ $? -ne 0 ]]; then
    error_echo "MOSS-TTS-Nano 语音生成失败。"
    gray_echo "最近日志："
    tail -n 120 "$LOG_FILE" 2>/dev/null | tee -a "$LOG_FILE"
    return 1
  fi

  if [[ ! -s "$default_output" ]]; then
    error_echo "未找到 MOSS-TTS-Nano 默认输出文件：${default_output}"
    gray_echo "请检查 CLI 是否变更了默认输出路径。日志：${LOG_FILE}"
    return 1
  fi

  cp -f "$default_output" "$output_file" || return 1
  success_echo "语音已生成：${output_file}"

  if command -v afplay >/dev/null 2>&1; then
    afplay "$output_file"
  else
    open "$output_file"
  fi
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
moss_show_readme_and_wait() {
  clear
  highlight_echo "==================== 【MacOS】🔊MOSS-TTS-Nano 本地朗读 ====================" | jobs_intro_style title
  color_echo "用途：输入文本，调用 MOSS-TTS-Nano 生成语音并立即播放。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  info_echo "默认仓库目录：${MOSS_TTS_NANO_HOME}" | jobs_intro_style body
  info_echo "默认虚拟环境：${MOSS_TTS_NANO_VENV_DIR}" | jobs_intro_style body
  info_echo "默认后端：${MOSS_TTS_NANO_BACKEND} / ${MOSS_TTS_NANO_EXECUTION_PROVIDER}" | jobs_intro_style body
  info_echo "默认参考音频：${MOSS_TTS_NANO_PROMPT_SPEECH}" | jobs_intro_style body
  echo "" | jobs_intro_style body
  note_echo "常用输入：" | jobs_intro_style title
  gray_echo "  直接输入文本              立即朗读，例如：你好 / Hello" | jobs_intro_style body
  gray_echo "  :prompt /path/voice.wav   指定 MOSS 参考音频" | jobs_intro_style body
  gray_echo "  :backend onnx             使用 ONNX 后端，默认推荐" | jobs_intro_style body
  gray_echo "  :provider cpu             ONNX CPU 推理，默认推荐" | jobs_intro_style body
  gray_echo "  :config                   查看当前配置" | jobs_intro_style body
  gray_echo "  :quit                     退出" | jobs_intro_style body
  echo "" | jobs_intro_style body
  warn_echo "说明：MOSS-TTS-Nano 首次运行会下载模型；如果网络慢，需要等待。" | jobs_intro_style body
  gray_echo "日志：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "==========================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?👉 按回车进入朗读；按 Ctrl+C 取消：" _
}
# 封装 moss_show_runtime_config 对应的独立处理逻辑。
moss_show_runtime_config() {
  echo ""
  highlight_echo "========================= MOSS-TTS-Nano 当前配置 ========================="
  gray_echo "仓库目录：${MOSS_TTS_NANO_HOME}"
  gray_echo "虚拟环境：${MOSS_TTS_NANO_VENV_DIR}"
  gray_echo "后端：${MOSS_TTS_NANO_BACKEND}"
  gray_echo "执行设备：${MOSS_TTS_NANO_EXECUTION_PROVIDER}"
  gray_echo "参考音频：${MOSS_TTS_NANO_PROMPT_SPEECH}"
  gray_echo "输出目录：${MOSS_TTS_NANO_OUTPUT_DIR}"
  gray_echo "日志：${LOG_FILE}"
  highlight_echo "========================================================================="
  echo ""
}
# 封装 moss_show_help 对应的独立处理逻辑。
moss_show_help() {
  cat <<'MOSS_HELP_EOF' | tee -a "$LOG_FILE"
可用命令：
  直接输入文本              立即朗读
  :prompt /path/voice.wav   指定 voice clone 参考音频
  :backend onnx             切换后端，默认 onnx
  :provider cpu             切换 ONNX 执行设备，默认 cpu；可选 cuda
  :config                   查看当前配置
  :quit                     退出脚本
MOSS_HELP_EOF
}
# 封装 moss_interactive_loop 对应的独立处理逻辑。
moss_interactive_loop() {
  moss_show_runtime_config
  moss_show_help
  echo ""

  while true; do
    local input=""
    read -r "?🔊 请输入要朗读的文本（直接回车退出）： " input
    input="$(strip_outer_quotes "$input")"

    if [[ -z "$input" ]]; then
      success_echo "已退出朗读循环。"
      break
    fi

    case "$input" in
      ":quit"|":q"|":exit")
        success_echo "已退出朗读循环。"
        break
        ;;
      ":help")
        moss_show_help
        ;;
      ":config")
        moss_show_runtime_config
        ;;
      ":prompt "*)
        MOSS_TTS_NANO_PROMPT_SPEECH="${input#":prompt "}"
        success_echo "MOSS 参考音频已切换为：${MOSS_TTS_NANO_PROMPT_SPEECH}"
        ;;
      ":backend "*)
        MOSS_TTS_NANO_BACKEND="${input#":backend "}"
        success_echo "MOSS 后端已切换为：${MOSS_TTS_NANO_BACKEND}"
        ;;
      ":provider "*)
        MOSS_TTS_NANO_EXECUTION_PROVIDER="${input#":provider "}"
        success_echo "MOSS 执行设备已切换为：${MOSS_TTS_NANO_EXECUTION_PROVIDER}"
        ;;
      *)
        moss_speak_text "$input"
        ;;
    esac
    echo ""
  done
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
moss_main() {
  # 根据当前条件选择对应的执行分支。
  if [[ "$#" -gt 0 ]]; then
    # 检查当前步骤所需的环境、路径或输入条件。
    moss_ensure_environment || exit 1
    # 执行当前流程中的独立业务步骤：moss_speak_text。
    moss_speak_text "$*"
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 展示脚本说明并等待用户确认影响范围。
  moss_show_readme_and_wait
  # 检查当前步骤所需的环境、路径或输入条件。
  moss_ensure_environment || exit 1
  # 执行当前流程中的独立业务步骤：moss_interactive_loop。
  moss_interactive_loop
}
# ---------- VoxCPM2 引擎 ----------
voxcpm_python_bin() {
  print -r -- "${VOXCPM_VENV_DIR}/bin/python"
}
# 封装 voxcpm_cli_bin 对应的独立处理逻辑。
voxcpm_cli_bin() {
  print -r -- "${VOXCPM_VENV_DIR}/bin/voxcpm"
}
# 封装 voxcpm_install_or_repair_environment 对应的独立处理逻辑。
voxcpm_install_or_repair_environment() {
  local py3=""
  py3="$(command -v python3 || true)"

  if [[ -z "$py3" ]]; then
    error_echo "未找到 python3，无法创建 VoxCPM 虚拟环境。"
    err_echo "请先安装 Python，例如：brew install python"
    return 1
  fi

  local py_version=""
  py_version="$($py3 - <<'VOXCPM_PYVER_EOF' 2>/dev/null
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
VOXCPM_PYVER_EOF
)"
  if [[ -n "$py_version" ]]; then
    local major="${py_version%%.*}"
    local minor="${py_version#*.}"
    if (( major < 3 || (major == 3 && minor < 10) || major >= 3 && minor >= 13 )); then
      error_echo "VoxCPM 推荐 Python 3.10-3.12，当前 python3=${py_version}。"
      err_echo "建议安装 Python 3.11 / 3.12 后重试。"
      return 1
    fi
  fi

  mkdir -p "$(dirname "$VOXCPM_VENV_DIR")"

  if [[ ! -d "$VOXCPM_VENV_DIR" ]]; then
    note_echo "开始创建 VoxCPM 虚拟环境：${VOXCPM_VENV_DIR}"
    "$py3" -m venv "$VOXCPM_VENV_DIR" >> "$LOG_FILE" 2>&1 || return 1
  fi

  local py="$(voxcpm_python_bin)"
  if [[ ! -x "$py" ]]; then
    error_echo "VoxCPM 虚拟环境 Python 不可执行：${py}"
    return 1
  fi

  if [[ -n "$VOXCPM_HF_ENDPOINT" ]]; then
    export HF_ENDPOINT="$VOXCPM_HF_ENDPOINT"
  fi

  note_echo "开始安装 / 补齐 VoxCPM 依赖。"
  "$py" -m pip install --upgrade pip >> "$LOG_FILE" 2>&1 || return 1
  "$py" -m pip install voxcpm >> "$LOG_FILE" 2>&1 || return 1

  "$py" - <<'VOXCPM_IMPORT_EOF' >> "$LOG_FILE" 2>&1
from voxcpm import VoxCPM
print("VoxCPM is ready")
VOXCPM_IMPORT_EOF
  if [[ $? -ne 0 ]]; then
    error_echo "VoxCPM 安装后仍无法 import。日志：${LOG_FILE}"
    return 1
  fi

  success_echo "VoxCPM 依赖已安装 / 补齐。"
}
# 封装 voxcpm_ensure_environment 对应的独立处理逻辑。
voxcpm_ensure_environment() {
  local cli="$(voxcpm_cli_bin)"
  local py="$(voxcpm_python_bin)"

  if [[ ! -x "$py" || ! -x "$cli" ]]; then
    warn_echo "未检测到可用的 VoxCPM 环境。"
    gray_echo "默认虚拟环境：${VOXCPM_VENV_DIR}"
    if [[ "$VOXCPM_SKIP_INSTALL" == "1" ]]; then
      error_echo "已设置 VOXCPM_SKIP_INSTALL=1，跳过自动安装。"
      return 1
    fi
    if ask_enter_to_run "是否自动创建 / 修复 VoxCPM 环境并安装 voxcpm"; then
      voxcpm_install_or_repair_environment || {
        error_echo "VoxCPM 环境创建 / 修复失败。日志：${LOG_FILE}"
        return 1
      }
    else
      error_echo "已跳过安装，无法继续朗读。"
      return 1
    fi
  fi

  "$py" - <<'VOXCPM_CHECK_EOF' >/dev/null 2>&1
from voxcpm import VoxCPM
VOXCPM_CHECK_EOF
  if [[ $? -ne 0 ]]; then
    warn_echo "虚拟环境存在，但无法 import voxcpm。"
    if ask_enter_to_run "是否自动重新安装 / 补齐 voxcpm"; then
      voxcpm_install_or_repair_environment || return 1
    else
      error_echo "已跳过修复，无法继续朗读。"
      return 1
    fi
  fi

  success_echo "VoxCPM 虚拟环境可用：${VOXCPM_VENV_DIR}"
}
# 封装 voxcpm_speak_text 对应的独立处理逻辑。
voxcpm_speak_text() {
  local raw_text="$1"
  local text="$(strip_outer_quotes "$raw_text")"

  if [[ -z "$text" ]]; then
    warn_echo "空文本，已跳过。"
    return 0
  fi

  local cli="$(voxcpm_cli_bin)"
  if [[ ! -x "$cli" ]]; then
    error_echo "未找到 voxcpm 命令：${cli}"
    return 1
  fi

  if [[ -n "$VOXCPM_PROMPT_AUDIO" && -z "$VOXCPM_PROMPT_TEXT" ]]; then
    error_echo "已设置 VOXCPM_PROMPT_AUDIO，但未设置 VOXCPM_PROMPT_TEXT。Hi-Fi 克隆需要参考音频的逐字稿。"
    err_echo "请在交互里执行：:prompt-text 参考音频对应文本"
    return 1
  fi

  if [[ -n "$VOXCPM_REFERENCE_AUDIO" && ! -f "$VOXCPM_REFERENCE_AUDIO" ]]; then
    error_echo "VoxCPM 参考音频不存在：${VOXCPM_REFERENCE_AUDIO}"
    return 1
  fi

  if [[ -n "$VOXCPM_PROMPT_AUDIO" && ! -f "$VOXCPM_PROMPT_AUDIO" ]]; then
    error_echo "VoxCPM prompt 音频不存在：${VOXCPM_PROMPT_AUDIO}"
    return 1
  fi

  if [[ -n "$VOXCPM_HF_ENDPOINT" ]]; then
    export HF_ENDPOINT="$VOXCPM_HF_ENDPOINT"
  fi

  mkdir -p "$VOXCPM_OUTPUT_DIR"
  local timestamp="$(date '+%Y%m%d_%H%M%S')"
  local output_file="${VOXCPM_OUTPUT_DIR}/voxcpm_${timestamp}.wav"
  local cmd=()
  local mode="design"

  if [[ -n "$VOXCPM_PROMPT_AUDIO" ]]; then
    mode="clone"
    cmd=("$cli" clone --text "$text" --prompt-audio "$VOXCPM_PROMPT_AUDIO" --prompt-text "$VOXCPM_PROMPT_TEXT" --output "$output_file")
    [[ -n "$VOXCPM_REFERENCE_AUDIO" ]] && cmd+=(--reference-audio "$VOXCPM_REFERENCE_AUDIO")
    note_echo "正在生成语音：engine=VoxCPM2 mode=Hi-Fi Clone device=${VOXCPM_DEVICE}"
  elif [[ -n "$VOXCPM_REFERENCE_AUDIO" ]]; then
    mode="clone"
    cmd=("$cli" clone --text "$text" --reference-audio "$VOXCPM_REFERENCE_AUDIO" --output "$output_file")
    note_echo "正在生成语音：engine=VoxCPM2 mode=Clone device=${VOXCPM_DEVICE}"
  else
    cmd=("$cli" design --text "$text" --output "$output_file")
    [[ -n "$VOXCPM_CONTROL" ]] && cmd+=(--control "$VOXCPM_CONTROL")
    note_echo "正在生成语音：engine=VoxCPM2 mode=Design device=${VOXCPM_DEVICE}"
  fi

  [[ -n "$VOXCPM_DEVICE" ]] && cmd+=(--device "$VOXCPM_DEVICE")
  [[ "$VOXCPM_NO_OPTIMIZE" == "1" || "$VOXCPM_NO_OPTIMIZE" == "true" ]] && cmd+=(--no-optimize)
  [[ "$mode" == "clone" && ( "$VOXCPM_DENOISE" == "1" || "$VOXCPM_DENOISE" == "true" ) ]] && cmd+=(--denoise)

  gray_echo "输出文件：${output_file}"
  gray_echo "首次运行会自动下载 VoxCPM2 权重，体积较大；CPU 模式可能很慢，Apple Silicon 建议 device=mps。"

  "${cmd[@]}" >> "$LOG_FILE" 2>&1
  if [[ $? -ne 0 || ! -s "$output_file" ]]; then
    error_echo "VoxCPM 语音生成失败：${output_file}"
    gray_echo "最近日志："
    tail -n 160 "$LOG_FILE" 2>/dev/null | tee -a "$LOG_FILE"
    return 1
  fi

  success_echo "语音已生成：${output_file}"

  if command -v afplay >/dev/null 2>&1; then
    afplay "$output_file"
  else
    open "$output_file"
  fi
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
voxcpm_show_readme_and_wait() {
  clear
  highlight_echo "====================== 【MacOS】🔊VoxCPM2 本地朗读 ======================" | jobs_intro_style title
  color_echo "用途：高质量多语言 TTS、声音设计、参考音频克隆。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  info_echo "默认虚拟环境：${VOXCPM_VENV_DIR}" | jobs_intro_style body
  info_echo "默认设备：${VOXCPM_DEVICE}（auto 会按 cuda → mps → cpu 选择）" | jobs_intro_style body
  info_echo "输出目录：${VOXCPM_OUTPUT_DIR}" | jobs_intro_style body
  echo "" | jobs_intro_style body
  note_echo "常用输入：" | jobs_intro_style title
  gray_echo "  直接输入文本                    立即朗读" | jobs_intro_style body
  gray_echo "  :device auto|mps|cpu|cuda       切换设备，Apple Silicon 推荐 mps" | jobs_intro_style body
  gray_echo "  :control 年轻女声，温柔甜美       设置声音设计提示词" | jobs_intro_style body
  gray_echo "  :reference /path/voice.wav      使用参考音频做声音克隆" | jobs_intro_style body
  gray_echo "  :prompt /path/voice.wav         Hi-Fi 克隆 prompt 音频，需要配合 :prompt-text" | jobs_intro_style body
  gray_echo "  :prompt-text 参考音频逐字稿       设置 Hi-Fi 克隆参考文本" | jobs_intro_style body
  gray_echo "  :denoise on|off                 克隆时是否对参考音频降噪" | jobs_intro_style body
  gray_echo "  :optimize on|off                控制 torch.compile；CPU/MPS 不稳时建议 off" | jobs_intro_style body
  gray_echo "  :hf-mirror on|off               设置 / 取消 HF_ENDPOINT=https://hf-mirror.com" | jobs_intro_style body
  gray_echo "  :config                         查看当前配置" | jobs_intro_style body
  gray_echo "  :quit                           退出" | jobs_intro_style body
  echo "" | jobs_intro_style body
  warn_echo "说明：VoxCPM2 质量强，但模型大；首次下载慢，CPU 推理慢。普通短文本/英文轻量朗读不要默认选它。" | jobs_intro_style body
  gray_echo "日志：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "=======================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?👉 按回车进入朗读；按 Ctrl+C 取消：" _
}
# 封装 voxcpm_show_runtime_config 对应的独立处理逻辑。
voxcpm_show_runtime_config() {
  echo ""
  highlight_echo "============================ VoxCPM2 当前配置 ============================"
  gray_echo "虚拟环境：${VOXCPM_VENV_DIR}"
  gray_echo "设备：${VOXCPM_DEVICE}"
  gray_echo "声音设计提示：${VOXCPM_CONTROL:-未设置}"
  gray_echo "参考音频：${VOXCPM_REFERENCE_AUDIO:-未设置}"
  gray_echo "Prompt 音频：${VOXCPM_PROMPT_AUDIO:-未设置}"
  gray_echo "Prompt 文本：${VOXCPM_PROMPT_TEXT:-未设置}"
  gray_echo "降噪：${VOXCPM_DENOISE}"
  gray_echo "no-optimize：${VOXCPM_NO_OPTIMIZE}"
  gray_echo "HF_ENDPOINT：${HF_ENDPOINT:-${VOXCPM_HF_ENDPOINT:-未设置}}"
  gray_echo "输出目录：${VOXCPM_OUTPUT_DIR}"
  gray_echo "日志：${LOG_FILE}"
  highlight_echo "========================================================================="
  echo ""
}
# 封装 voxcpm_show_help 对应的独立处理逻辑。
voxcpm_show_help() {
  cat <<'VOXCPM_HELP_EOF' | tee -a "$LOG_FILE"
可用命令：
  直接输入文本                    立即朗读
  :device auto|mps|cpu|cuda       切换设备
  :control 文本                   设置声音设计提示词；清空用 :control off
  :reference /path/voice.wav      设置参考音频；清空用 :reference off
  :prompt /path/voice.wav         设置 Hi-Fi 克隆 prompt 音频；清空用 :prompt off
  :prompt-text 文本               设置 Hi-Fi 克隆 prompt 文本；清空用 :prompt-text off
  :denoise on|off                 克隆时是否启用参考音频降噪
  :optimize on|off                on=允许优化；off=传入 --no-optimize
  :hf-mirror on|off               on=HF_ENDPOINT=https://hf-mirror.com
  :config                         查看当前配置
  :quit                           退出脚本
VOXCPM_HELP_EOF
}
# 封装 voxcpm_interactive_loop 对应的独立处理逻辑。
voxcpm_interactive_loop() {
  voxcpm_show_runtime_config
  voxcpm_show_help
  echo ""

  while true; do
    local input=""
    read -r "?🔊 请输入要朗读的文本（直接回车退出）： " input
    input="$(strip_outer_quotes "$input")"

    if [[ -z "$input" ]]; then
      success_echo "已退出朗读循环。"
      break
    fi

    case "$input" in
      ":quit"|":q"|":exit")
        success_echo "已退出朗读循环。"
        break
        ;;
      ":help")
        voxcpm_show_help
        ;;
      ":config")
        voxcpm_show_runtime_config
        ;;
      ":device "*)
        VOXCPM_DEVICE="${input#":device "}"
        success_echo "VoxCPM 设备已切换为：${VOXCPM_DEVICE}"
        ;;
      ":control off")
        VOXCPM_CONTROL=""
        success_echo "VoxCPM 声音设计提示已清空。"
        ;;
      ":control "*)
        VOXCPM_CONTROL="${input#":control "}"
        success_echo "VoxCPM 声音设计提示已设置为：${VOXCPM_CONTROL}"
        ;;
      ":reference off")
        VOXCPM_REFERENCE_AUDIO=""
        success_echo "VoxCPM 参考音频已清空。"
        ;;
      ":reference "*)
        VOXCPM_REFERENCE_AUDIO="${input#":reference "}"
        success_echo "VoxCPM 参考音频已切换为：${VOXCPM_REFERENCE_AUDIO}"
        ;;
      ":prompt off")
        VOXCPM_PROMPT_AUDIO=""
        success_echo "VoxCPM prompt 音频已清空。"
        ;;
      ":prompt "*)
        VOXCPM_PROMPT_AUDIO="${input#":prompt "}"
        success_echo "VoxCPM prompt 音频已切换为：${VOXCPM_PROMPT_AUDIO}"
        ;;
      ":prompt-text off")
        VOXCPM_PROMPT_TEXT=""
        success_echo "VoxCPM prompt 文本已清空。"
        ;;
      ":prompt-text "*)
        VOXCPM_PROMPT_TEXT="${input#":prompt-text "}"
        success_echo "VoxCPM prompt 文本已设置。"
        ;;
      ":denoise on")
        VOXCPM_DENOISE="1"
        success_echo "VoxCPM 降噪已开启。"
        ;;
      ":denoise off")
        VOXCPM_DENOISE="0"
        success_echo "VoxCPM 降噪已关闭。"
        ;;
      ":optimize on")
        VOXCPM_NO_OPTIMIZE="0"
        success_echo "VoxCPM 优化已开启。"
        ;;
      ":optimize off")
        VOXCPM_NO_OPTIMIZE="1"
        success_echo "VoxCPM 优化已关闭，将传入 --no-optimize。"
        ;;
      ":hf-mirror on")
        VOXCPM_HF_ENDPOINT="https://hf-mirror.com"
        export HF_ENDPOINT="$VOXCPM_HF_ENDPOINT"
        success_echo "已设置 HF_ENDPOINT=${VOXCPM_HF_ENDPOINT}"
        ;;
      ":hf-mirror off")
        VOXCPM_HF_ENDPOINT=""
        unset HF_ENDPOINT
        success_echo "已取消 HF_ENDPOINT。"
        ;;
      *)
        voxcpm_speak_text "$input"
        ;;
    esac
    echo ""
  done
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
voxcpm_main() {
  # 根据当前条件选择对应的执行分支。
  if [[ "$#" -gt 0 ]]; then
    # 检查当前步骤所需的环境、路径或输入条件。
    voxcpm_ensure_environment || exit 1
    # 执行当前流程中的独立业务步骤：voxcpm_speak_text。
    voxcpm_speak_text "$*"
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 展示脚本说明并等待用户确认影响范围。
  voxcpm_show_readme_and_wait
  # 检查当前步骤所需的环境、路径或输入条件。
  voxcpm_ensure_environment || exit 1
  # 执行当前流程中的独立业务步骤：voxcpm_interactive_loop。
  voxcpm_interactive_loop
}
# ---------- 菜单与交互 ----------
show_supported_languages() {
  cat <<'EOF' | tee -a "$LOG_FILE"
支持语言代码：
  en 英语    ko 韩语    ja 日语    ar 阿拉伯语
  bg 保加利亚语 cs 捷克语 da 丹麦语 de 德语
  el 希腊语  es 西班牙语 et 爱沙尼亚语 fi 芬兰语
  fr 法语    hi 印地语 hr 克罗地亚语 hu 匈牙利语
  id 印尼语  it 意大利语 lt 立陶宛语 lv 拉脱维亚语
  nl 荷兰语  pl 波兰语 pt 葡萄牙语 ro 罗马尼亚语
  ru 俄语    sk 斯洛伐克语 sl 斯洛文尼亚语 sv 瑞典语
  tr 土耳其语 uk 乌克兰语 vi 越南语
  na 未知 / fallback

注意：官方公开语言列表没有 zh / 中文。中文建议用 auto 或 na，但效果不保证。
EOF
}
# 封装 show_runtime_config 对应的独立处理逻辑。
show_runtime_config() {
  echo ""
  highlight_echo "============================== 当前配置 =============================="
  gray_echo "虚拟环境：${SUPERTONIC_VENV_DIR}"
  gray_echo "服务地址：${SERVER_URL}"
  gray_echo "声音角色：${SUPERTONIC_VOICE}"
  gray_echo "语言模式：${SUPERTONIC_LANG}"
  gray_echo "推理步数：${SUPERTONIC_STEPS}"
  gray_echo "语速倍数：${SUPERTONIC_SPEED}"
  gray_echo "输出目录：${SUPERTONIC_OUTPUT_DIR}"
  gray_echo "中文引擎：${SUPERTONIC_ZH_ENGINE}"
  gray_echo "中文语音：${SUPERTONIC_ZH_VOICE:-自动选择}"
  gray_echo "中文语速：${SUPERTONIC_ZH_RATE}"
  gray_echo "主日志：${LOG_FILE}"
  gray_echo "服务日志：${SERVER_LOG}"
  highlight_echo "======================================================================="
  echo ""
}
# 封装 show_help 对应的独立处理逻辑。
show_help() {
  cat <<'EOF' | tee -a "$LOG_FILE"
可用命令：
  直接输入文本        立即朗读，例如：fuck
  :lang en           切换语言，例如 en / ja / ko / es / na / auto
  :voice F1          切换声音，内置 M1-M5、F1-F5
  :speed 1.2         切换语速，建议 0.7-2.0
  :steps 10          切换质量步数，建议 5-12，越大越慢
  :list              查看官方支持的语言代码
  :docs              打开本地接口文档
  :config            查看当前配置
  :stop              停止本脚本启动的后台服务
  :quit              退出
EOF
}
# 封装 interactive_loop 对应的独立处理逻辑。
interactive_loop() {
  show_runtime_config
  show_help
  echo ""

  while true; do
    local input=""
    read -r "?🔊 请输入要朗读的文本（直接回车退出）： " input
    input="$(strip_outer_quotes "$input")"

    if [[ -z "$input" ]]; then
      success_echo "已退出朗读循环。"
      break
    fi

    case "$input" in
      ":quit"|":q"|":exit")
        success_echo "已退出朗读循环。"
        break
        ;;
      ":help")
        show_help
        ;;
      ":list")
        show_supported_languages
        ;;
      ":docs")
        open "${SERVER_URL}/docs"
        ;;
      ":config")
        show_runtime_config
        ;;
      ":stop")
        stop_started_server
        ;;
      ":lang "*)
        SUPERTONIC_LANG="${input#":lang "}"
        success_echo "语言已切换为：${SUPERTONIC_LANG}"
        ;;
      ":zh-engine "*)
        SUPERTONIC_ZH_ENGINE="${input#":zh-engine "}"
        success_echo "中文引擎已切换为：${SUPERTONIC_ZH_ENGINE}"
        ;;
      ":zh-voices")
        list_macos_chinese_voices
        ;;
      ":zh-voice "*)
        SUPERTONIC_ZH_VOICE="${input#":zh-voice "}"
        success_echo "中文语音已切换为：${SUPERTONIC_ZH_VOICE}"
        ;;
      ":zh-rate "*)
        SUPERTONIC_ZH_RATE="${input#":zh-rate "}"
        success_echo "中文语速已切换为：${SUPERTONIC_ZH_RATE}"
        ;;
      ":voice "*)
        SUPERTONIC_VOICE="${input#":voice "}"
        success_echo "声音已切换为：${SUPERTONIC_VOICE}"
        ;;
      ":speed "*)
        SUPERTONIC_SPEED="${input#":speed "}"
        success_echo "语速已切换为：${SUPERTONIC_SPEED}"
        ;;
      ":steps "*)
        SUPERTONIC_STEPS="${input#":steps "}"
        success_echo "步数已切换为：${SUPERTONIC_STEPS}"
        ;;
      *)
        speak_text "$input"
        ;;
    esac
    echo ""
  done
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
supertonic_main() {
  # 根据当前条件选择对应的执行分支。
  if [[ "$#" -gt 0 ]]; then
    # 检查当前步骤所需的环境、路径或输入条件。
    ensure_environment || exit 1
    # 执行当前流程中的独立业务步骤：start_server_if_needed。
    start_server_if_needed || exit 1
    # 执行当前流程中的独立业务步骤：speak_text。
    speak_text "$*"
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 展示脚本说明并等待用户确认影响范围。
  show_readme_and_wait
  # 检查当前步骤所需的环境、路径或输入条件。
  ensure_environment || exit 1
  # 执行当前流程中的独立业务步骤：start_server_if_needed。
  start_server_if_needed || exit 1
  # 执行当前流程中的独立业务步骤：interactive_loop。
  interactive_loop
}
# 封装 parse_engine_args 对应的独立处理逻辑。
parse_engine_args() {
  local next_is_engine="false"
  local cleaned=()
  local arg=""

  for arg in "$@"; do
    if [[ "$next_is_engine" == "true" ]]; then
      TTS_ENGINE="$arg"
      next_is_engine="false"
      continue
    fi

    case "$arg" in
      --engine)
        next_is_engine="true"
        ;;
      --engine=*)
        TTS_ENGINE="${arg#--engine=}"
        ;;
      --moss|--moss-tts|--moss-tts-nano)
        TTS_ENGINE="moss"
        ;;
      --voxcpm|--voxcpm2|--vox)
        TTS_ENGINE="voxcpm"
        ;;
      --supertonic)
        TTS_ENGINE="supertonic"
        ;;
      *)
        cleaned+=("$arg")
        ;;
    esac
  done

  printf '%s\n' "${cleaned[@]}"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：tts.command' | jobs_intro_style title
  print -r -- '核心用途：执行“tts”对应的自动化任务。' | jobs_intro_style body
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
  # 初始化当前流程后续步骤需要使用的变量。
  local parsed=""
  # 初始化当前流程后续步骤需要使用的变量。
  local engine=""
  # 初始化当前流程后续步骤需要使用的变量。
  local args=()

  # 初始化当前流程后续步骤需要使用的变量。
  parsed="$(parse_engine_args "$@")"
  # 根据当前条件选择对应的执行分支。
  if [[ -n "$parsed" ]]; then
    # 循环处理用户输入或当前批次中的全部目标。
    while IFS= read -r item; do
      # 执行当前流程中的独立业务步骤：处理当前语句。
      [[ -n "$item" ]] && args+=("$item")
    done <<< "$parsed"
  fi

  # 根据当前条件选择对应的执行分支。
  if ! select_tts_engine; then
    # 执行当前流程中的独立业务步骤：info_echo。
    info_echo "已取消 TTS 引擎选择。"
    # 执行当前流程中的独立业务步骤：return。
    return 0
  fi
  # 初始化当前流程后续步骤需要使用的变量。
  engine="$TTS_SELECTED_ENGINE"
  # 执行当前流程中的独立业务步骤：print_engine_banner。
  print_engine_banner "$engine"

  # 根据当前条件选择对应的执行分支。
  case "$engine" in
    # 执行当前流程中的独立业务步骤：moss。
    moss)
      # 执行当前流程中的独立业务步骤：moss_main。
      moss_main "${args[@]}"
      ;;
    # 执行当前流程中的独立业务步骤：voxcpm。
    voxcpm)
      # 执行当前流程中的独立业务步骤：voxcpm_main。
      voxcpm_main "${args[@]}"
      ;;
    # 执行当前流程中的独立业务步骤：supertonic。
    supertonic)
      # 执行当前流程中的独立业务步骤：supertonic_main。
      supertonic_main "${args[@]}"
      ;;
    # 执行当前流程中的独立业务步骤：处理当前语句。
    *)
      # 执行当前流程中的独立业务步骤：error_echo。
      error_echo "未知 TTS 引擎：${engine}"
      # 执行当前流程中的独立业务步骤：return。
      return 1
      ;;
  esac
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  setopt NO_NOMATCH
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
