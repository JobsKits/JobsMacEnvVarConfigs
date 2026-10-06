#!/bin/zsh
# 脚本自述：
# - 脚本名称：m5c.command
# - 核心用途：执行“m5c”对应的自动化任务。
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
# ---------- 彩色日志 ----------
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }         # 正常绿色输出
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }       # 信息
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }       # 成功
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }       # 警告
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }         # 温馨提示
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }       # 说明
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }       # 错误
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }         # 错误纯文本
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }      # 调试
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }      # 高亮
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }         # 次要信息
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }            # 加粗
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }            # 下划线
# ---------- 自述 ----------
show_readme() {
  clear
  bold_echo "m5c - MD5 文件一致性比较工具" | jobs_intro_style title
  gray_echo "脚本路径：$SCRIPT_PATH" | jobs_intro_style body
  gray_echo "日志路径：$LOG_FILE" | jobs_intro_style body
  log "" | jobs_intro_style body
  note_echo "功能说明" | jobs_intro_style body
  log "  1. 输入或拖入第一个文件路径，回车确认。" | jobs_intro_style body
  log "  2. 输入或拖入第二个文件路径，回车确认。" | jobs_intro_style body
  log "  3. 分别计算两个文件的 MD5。" | jobs_intro_style body
  log "  4. 输出两个 MD5，并判断文件字节内容是否一致。" | jobs_intro_style body
  log "" | jobs_intro_style body
  note_echo "判断规则" | jobs_intro_style body
  log "  - 两个文件字节内容完全一致，MD5 必然一致。" | jobs_intro_style body
  log "  - MD5 一致时，日常文件校验可以认为内容相同。" | jobs_intro_style body
  log "  - MD5 不适合安全签名；安全用途建议 SHA-256。" | jobs_intro_style body
  log "" | jobs_intro_style body
  note_echo "流程" | jobs_intro_style body
  log "  启动 m5c" | jobs_intro_style body
  log "      ↓" | jobs_intro_style body
  log "  显示本内置自述并等待回车" | jobs_intro_style body
  log "      ↓" | jobs_intro_style body
  log "  输入 / 拖入第一个文件" | jobs_intro_style body
  log "      ↓" | jobs_intro_style body
  log "  输入 / 拖入第二个文件" | jobs_intro_style body
  log "      ↓" | jobs_intro_style body
  log "  计算两个文件 MD5" | jobs_intro_style body
  log "      ↓" | jobs_intro_style body
  log "  输出是否一致" | jobs_intro_style body
}
# 封装 press_enter_to_continue 对应的独立处理逻辑。
press_enter_to_continue() {
  log ""
  warm_echo "按回车开始比较..."
  local _answer=""
  IFS= read -r _answer
}
# ---------- 路径处理 ----------
trim_text() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  print -r -- "$value"
}
# 封装 normalize_path 对应的独立处理逻辑。
normalize_path() {
  local raw="$1"
  local value=""

  value="$(trim_text "$raw")"
  value="${(Q)value}"

  print -r -- "$value"
}
# 检查当前运行条件是否满足后续流程要求。
is_quit_text() {
  local value="${1:l}"
  [[ "$value" == "q" || "$value" == "quit" || "$value" == "exit" ]]
}
# 封装 read_file_path 对应的独立处理逻辑。
read_file_path() {
  local title="$1"
  local raw_path=""
  local file_path=""

  REPLY_FILE_PATH=""

  while true; do
    log ""
    highlight_echo "$title"
    note_echo "请输入或拖入文件路径，然后回车；输入 q / quit / exit 退出："

    IFS= read -r raw_path
    file_path="$(normalize_path "$raw_path")"

    if is_quit_text "$file_path"; then
      info_echo "已退出 m5c。"
      return 130
    fi

    if [[ -z "$file_path" ]]; then
      warn_echo "路径为空，请重新输入。"
      continue
    fi

    if [[ ! -e "$file_path" ]]; then
      error_echo "文件不存在：$file_path"
      continue
    fi

    if [[ ! -f "$file_path" ]]; then
      error_echo "这不是普通文件：$file_path"
      continue
    fi

    if [[ ! -r "$file_path" ]]; then
      error_echo "文件不可读：$file_path"
      continue
    fi

    REPLY_FILE_PATH="$file_path"
    return 0
  done
}
# ---------- MD5 ----------
calc_md5() {
  local file_path="$1"

  if command -v md5 >/dev/null 2>&1; then
    md5 -q "$file_path"
    return $?
  fi

  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$file_path" | awk '{print $1}'
    return $?
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -md5 -r "$file_path" | awk '{print $1}'
    return $?
  fi

  error_echo "当前系统找不到 md5、md5sum 或 openssl，无法计算 MD5。"
  return 1
}
# 封装 compare_files 对应的独立处理逻辑。
compare_files() {
  local file_a="$1"
  local file_b="$2"
  local md5_a=""
  local md5_b=""

  log ""
  info_echo "正在计算第一个文件 MD5..."
  md5_a="$(calc_md5 "$file_a")" || return 1

  info_echo "正在计算第二个文件 MD5..."
  md5_b="$(calc_md5 "$file_b")" || return 1

  log ""
  bold_echo "比较结果"
  log "第一个文件：$file_a"
  log "MD5：$md5_a"
  log ""
  log "第二个文件：$file_b"
  log "MD5：$md5_b"
  log ""

  if [[ "$md5_a" == "$md5_b" ]]; then
    success_echo "两个文件 MD5 完全一致，可以认为文件字节内容相同。"
  else
    error_echo "两个文件 MD5 不一致，文件字节内容不同。"
  fi

  gray_echo "日志路径：$LOG_FILE"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：m5c.command' | jobs_intro_style title
  print -r -- '核心用途：执行“m5c”对应的自动化任务。' | jobs_intro_style body
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
  local file_a=""
  # 初始化当前流程后续步骤需要使用的变量。
  local file_b=""

  # 展示脚本说明并等待用户确认影响范围。
  show_readme
  # 执行当前流程中的独立业务步骤：press_enter_to_continue。
  press_enter_to_continue

  # 执行当前流程中的独立业务步骤：read_file_path。
  read_file_path "第一个文件" || return 0
  file_a="$REPLY_FILE_PATH"

  # 执行当前流程中的独立业务步骤：read_file_path。
  read_file_path "第二个文件" || return 0
  file_b="$REPLY_FILE_PATH"

  # 执行当前流程中的独立业务步骤：compare_files。
  compare_files "$file_a" "$file_b"
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
