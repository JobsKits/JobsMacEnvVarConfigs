#!/bin/zsh
# 脚本自述：
# - 脚本名称：to.command
# - 核心用途：执行“to”对应的自动化任务。
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

FFMPEG_BIN=""
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
ask_any_to_run() {
  emulate -L zsh

  local message="$1"
  local answer=""

  read -r "?${message}（直接回车跳过；输入任意字符后回车执行）：" answer
  [[ -n "$answer" ]]
}
# 封装 strip_outer_quotes 对应的独立处理逻辑。
strip_outer_quotes() {
  emulate -L zsh

  local value="$1"

  # 兼容终端拖入路径：read -r 会保留反斜杠，必须还原空格、括号、方括号等 shell 转义。
  value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  value="${value%$'\r'}"
  value="${value%$'\n'}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  value="${(Q)value}"
  value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  if [[ "$value" == "~/"* ]]; then
    value="$HOME/${value#~/}"
  elif [[ "$value" == "~" ]]; then
    value="$HOME"
  fi

  print -r -- "$value"
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_script_intro_and_wait() {
  emulate -L zsh


  clear 2>/dev/null || true

  echo "" | jobs_intro_style body
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
}
# ---------- 依赖检查 ----------
find_brew_bin() {
  emulate -L zsh

  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  local candidate=""
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done

  return 1
}
# 解析并返回后续流程需要的目标信息。
find_ffmpeg_bin() {
  emulate -L zsh

  if command -v ffmpeg >/dev/null 2>&1; then
    command -v ffmpeg
    return 0
  fi

  local candidate=""
  for candidate in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
    if [[ -x "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done

  return 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_ffmpeg() {
  emulate -L zsh

  FFMPEG_BIN=""
  if FFMPEG_BIN="$(find_ffmpeg_bin 2>/dev/null)"; then
    return 0
  fi

  warn_echo "未检测到 FFmpeg。"
  local brew_bin=""
  if ! brew_bin="$(find_brew_bin 2>/dev/null)"; then
    error_echo "未检测到 Homebrew，无法自动安装 FFmpeg。"
    gray_echo "可先执行：brew install ffmpeg"
    return 1
  fi

  if ask_any_to_run "是否通过 Homebrew 安装 FFmpeg？"; then
    "$brew_bin" install ffmpeg 2>&1 | tee -a "$LOG_FILE"
    local brew_status=${pipestatus[1]}
    (( brew_status == 0 )) || return "$brew_status"
  else
    error_echo "已跳过 FFmpeg 安装，无法继续转换。"
    gray_echo "可手动执行：brew install ffmpeg"
    return 1
  fi

  if FFMPEG_BIN="$(find_ffmpeg_bin 2>/dev/null)"; then
    return 0
  fi

  error_echo "FFmpeg 安装后仍不可用，请检查 PATH。"
  return 1
}
# ---------- 转换配置 ----------
normalize_ext() {
  emulate -L zsh

  local ext="$1"
  ext="${ext#.}"
  ext="${ext:l}"
  print -r -- "$ext"
}
# 检查当前运行条件是否满足后续流程要求。
is_format_shortcut() {
  emulate -L zsh

  local name="$(normalize_ext "$1")"
  local item=""
  local shortcuts=(mp4 mov webm mkv avi m4v mp3 m4a aac wav flac ogg opus gif)

  for item in "${shortcuts[@]}"; do
    [[ "$name" == "$item" ]] && return 0
  done

  return 1
}
# 封装 next_output_path 对应的独立处理逻辑。
next_output_path() {
  emulate -L zsh

  local dir="$1"
  local stem="$2"
  local ext="$3"
  local output="${dir}/${stem}.${ext}"
  local index=1

  while [[ -e "$output" ]]; do
    output="${dir}/${stem}_${index}.${ext}"
    ((index++))
  done

  print -r -- "$output"
}
# 封装 print_usage 对应的独立处理逻辑。
print_usage() {
  cat <<'EOFUSAGE' | tee -a "$LOG_FILE"
============================================================
to - FFmpeg 通用媒体格式转换
============================================================

常用：
  mp4  <视频文件>
  mov  <视频文件>
  webm <视频文件>
  mp3  <视频文件或音频文件>

通用：
  to mp4  <视频文件>
  to m4a  <视频文件或音频文件>
  to webm <视频文件>

说明：
  - 输入命令和源文件后，脚本会要求输入输出文件名。
  - 输出文件名不需要写后缀。
  - 直接回车沿用原文件名。
  - 输入格式和输出格式相同，不执行转换。
  - 输出文件默认放在源文件同目录。
  - 目标文件已存在时，会自动追加 _1、_2，避免覆盖。

注意：
  - gif 已被 JobsMacEnv 用作录制命令，因此 GIF 转换请使用：to gif <文件>
  - 日志路径：/tmp/to.log 或 /tmp/<快捷命令>.log
============================================================
EOFUSAGE
}
# 封装 read_target_ext 对应的独立处理逻辑。
read_target_ext() {
  emulate -L zsh

  local target_ext=""
  while [[ -z "$target_ext" ]]; do
    read -r "?👉 请输入目标格式，例如 mp4 / mov / webm / mp3：" target_ext
    target_ext="$(normalize_ext "$(strip_outer_quotes "$target_ext")")"
  done

  print -r -- "$target_ext"
}
# 封装 read_input_paths 对应的独立处理逻辑。
read_input_paths() {
  emulate -L zsh

  local raw_line=""
  local whole_path=""
  local item=""
  local -a items
  local -a parsed_paths

  while true; do
    read -r "?👉 请拖入或输入源文件路径；多个文件可连续拖入后回车，输入 q 取消：" raw_line
    whole_path="$(strip_outer_quotes "$raw_line")"

    case "${whole_path:l}" in
      q|quit|exit)
        warn_echo "已取消输入源文件。"
        return 1
        ;;
    esac

    if [[ -z "$whole_path" ]]; then
      warn_echo "源文件路径为空：请拖入文件，或输入 q 取消。"
      continue
    fi

    # 单文件拖入 / 单文件手写：优先按整行还原，避免中文、空格、方括号路径被错误拆分。
    if [[ -f "$whole_path" ]]; then
      print -r -- "$whole_path"
      return 0
    fi

    # 多文件拖入：再按 zsh 词法拆分，并逐项还原 shell 转义。
    items=("${(@z)raw_line}")
    parsed_paths=()
    for item in "${items[@]}"; do
      item="$(strip_outer_quotes "$item")"
      [[ -n "$item" ]] && parsed_paths+=("$item")
    done

    if (( ${#parsed_paths[@]} == 0 )); then
      warn_echo "没有解析到有效路径，请重新拖入文件。"
      continue
    fi

    for item in "${parsed_paths[@]}"; do
      print -r -- "$item"
    done
    return 0
  done
}
# 收集并校验用户输入，决定后续执行路径。
prompt_output_stem() {
  emulate -L zsh

  local old_stem="$1"
  local target_ext="$2"
  local output_stem=""
  local entered_ext=""

  read -r "?👉 请输入输出文件名，不带 .${target_ext}；直接回车沿用原文件名：" output_stem
  output_stem="$(strip_outer_quotes "$output_stem")"

  if [[ -z "$output_stem" ]]; then
    output_stem="$old_stem"
  else
    if [[ "$output_stem" == */* ]]; then
      output_stem="${output_stem:t}"
    fi

    entered_ext="$(normalize_ext "${output_stem:e}")"
    if [[ -n "$entered_ext" && "$entered_ext" == "$target_ext" ]]; then
      output_stem="${output_stem:r}"
    fi
  fi

  print -r -- "$output_stem"
}
# ---------- FFmpeg 执行 ----------
run_and_log() {
  emulate -L zsh

  "$@" 2>&1 | tee -a "$LOG_FILE"
  return ${pipestatus[1]}
}
# 执行已经拆分完成的独立业务步骤。
run_ffmpeg_convert() {
  emulate -L zsh

  local ffmpeg_bin="$1"
  local input_abs="$2"
  local output="$3"
  local target_ext="$4"

  case "$target_ext" in
    mp4)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -c:v libx264 -c:a aac -movflags +faststart "$output"
      ;;
    mov)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -c:v libx264 -c:a aac "$output"
      ;;
    webm)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -c:v libvpx-vp9 -c:a libopus "$output"
      ;;
    mkv)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -c copy "$output"
      ;;
    m4v)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -c:v libx264 -c:a aac -movflags +faststart "$output"
      ;;
    avi)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -c:v mpeg4 -q:v 5 -c:a libmp3lame -q:a 2 "$output"
      ;;
    mp3)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -vn -c:a libmp3lame -q:a 2 "$output"
      ;;
    m4a)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -vn -c:a aac -b:a 192k "$output"
      ;;
    aac)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -vn -c:a aac -b:a 192k "$output"
      ;;
    wav)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -vn -c:a pcm_s16le "$output"
      ;;
    flac)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -vn -c:a flac "$output"
      ;;
    ogg)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -vn -c:a libvorbis -q:a 5 "$output"
      ;;
    opus)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -vn -c:a libopus -b:a 128k "$output"
      ;;
    gif)
      run_and_log "$ffmpeg_bin" -i "$input_abs" -vf "fps=15,scale=720:-1:flags=lanczos" "$output"
      ;;
    *)
      warn_echo "未写入 ${target_ext} 的专用参数，改用 FFmpeg 自动推断。"
      run_and_log "$ffmpeg_bin" -i "$input_abs" "$output"
      ;;
  esac
}
# 封装 convert_one 对应的独立处理逻辑。
convert_one() {
  emulate -L zsh

  local ffmpeg_bin="$1"
  local target_ext="$2"
  local input="$3"

  input="$(strip_outer_quotes "$input")"

  if [[ ! -f "$input" ]]; then
    error_echo "文件不存在：$input"
    return 1
  fi

  local input_abs="${input:A}"
  local dir="${input_abs:h}"
  local filename="${input_abs:t}"
  local old_stem="${filename:r}"
  local input_ext="$(normalize_ext "${filename:e}")"
  local output_stem=""
  local output=""

  if [[ -n "$input_ext" && "$input_ext" == "$target_ext" ]]; then
    warn_echo "输入文件已经是 .${target_ext} 格式，不执行转换：$input_abs"
    return 1
  fi

  log ""
  highlight_echo "输入：$input_abs"
  output_stem="$(prompt_output_stem "$old_stem" "$target_ext")"
  output="$(next_output_path "$dir" "$output_stem" "$target_ext")"
  highlight_echo "输出：$output"

  run_ffmpeg_convert "$ffmpeg_bin" "$input_abs" "$output" "$target_ext"
  local command_status=$?

  if (( command_status == 0 )); then
    success_echo "转换完成：$output"
    return 0
  fi

  error_echo "转换失败：$input_abs"
  if [[ -f "$output" ]]; then
    rm -f "$output" 2>/dev/null || true
    warn_echo "已清理失败产生的半成品文件：$output"
  fi
  return "$command_status"
}
# 封装 convert_many 对应的独立处理逻辑。
convert_many() {
  emulate -L zsh

  local target_ext="$(normalize_ext "$1")"
  shift

  if [[ -z "$target_ext" ]]; then
    error_echo "缺少目标格式。"
    print_usage
    return 1
  fi

  if ! ensure_ffmpeg; then
    return 1
  fi

  local ffmpeg_bin="$FFMPEG_BIN"

  local input=""
  local failed=0

  for input in "$@"; do
    convert_one "$ffmpeg_bin" "$target_ext" "$input" || failed=1
  done

  gray_echo "日志路径：$LOG_FILE"
  return "$failed"
}
# ---------- 主流程统一收口 ----------
jobs_to_main() {
  # 执行当前流程中的独立业务步骤：emulate。
  emulate -L zsh

  # 初始化当前流程后续步骤需要使用的变量。
  local target_ext=""
  # 执行当前流程中的独立业务步骤：local。
  local -a inputs

  # 根据当前条件选择对应的执行分支。
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    # 执行当前流程中的独立业务步骤：print_usage。
    print_usage
    # 执行当前流程中的独立业务步骤：return。
    return 0
  fi

  # 根据当前条件选择对应的执行分支。
  if is_format_shortcut "$SCRIPT_BASENAME" && [[ "$SCRIPT_BASENAME" != "to" ]]; then
    # 初始化当前流程后续步骤需要使用的变量。
    target_ext="$(normalize_ext "$SCRIPT_BASENAME")"
    # 执行当前流程中的独立业务步骤：shift。
    shift 0
  elif (( $# > 0 )); then
    # 初始化当前流程后续步骤需要使用的变量。
    target_ext="$(normalize_ext "$1")"
    # 执行当前流程中的独立业务步骤：shift。
    shift
  else
    # 展示脚本说明并等待用户确认影响范围。
    show_script_intro_and_wait
    # 初始化当前流程后续步骤需要使用的变量。
    target_ext="$(read_target_ext)"
  fi

  # 根据当前条件选择对应的执行分支。
  if (( $# > 0 )); then
    # 初始化当前流程后续步骤需要使用的变量。
    inputs=("$@")
  else
    # 初始化当前流程后续步骤需要使用的变量。
    inputs=("${(@f)$(read_input_paths)}")
  fi

  # 根据当前条件选择对应的执行分支。
  if (( ${#inputs[@]} == 0 )); then
    # 执行当前流程中的独立业务步骤：error_echo。
    error_echo "没有拿到源文件路径。"
    # 执行当前流程中的独立业务步骤：return。
    return 1
  fi

  # 执行当前流程中的独立业务步骤：convert_many。
  convert_many "$target_ext" "${inputs[@]}"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：to.command' | jobs_intro_style title
  print -r -- '核心用途：执行“to”对应的自动化任务。' | jobs_intro_style body
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
  show_script_intro_and_wait # 展示脚本内置自述，并按运行入口完成防误触确认。
  jobs_to_main "$@" # 执行 jobs_to_main 对应的独立业务步骤。
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  set -o pipefail
  setopt NO_NOMATCH
  : > "$LOG_FILE"
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    main "$@"
  fi
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
