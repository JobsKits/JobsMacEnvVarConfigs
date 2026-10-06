#!/bin/zsh
# 脚本自述：
# - 脚本名称：decode.command
# - 核心用途：执行“decode”对应的自动化任务。
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
color_echo()     { log "[1;32m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "[1;34mℹ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "[1;32m✔ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "[1;33m⚠ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "[1;33m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "[1;35m➤ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "[1;31m✖ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "[1;31m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "[1;35m🐞 $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "[1;36m🔹 $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "[0;90m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "[1m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "[4m$1[0m"; }
# ---------- 内置自述 ----------
jobs_decode_show_readme_and_wait() {
  clear 2>/dev/null || true
  cat <<'EOFREADME' | tee -a "$LOG_FILE" | jobs_intro_style auto
============================================================
decode - URL 解码
============================================================

这是 decode.command 的内置自述，不读取同级 README.md。

功能：
  交互式 URL Decode，并自动复制结果到剪贴板。

结构：
  Scripts/decode.command/decode.command
  Scripts/decode.command/README.md

运行：
  decode
  decode [参数...]

说明：
  - 终端可输入的自定义命令都应独立收进 Scripts。
  - README.md 只作为源码说明；运行时展示的是脚本内置自述。
  - 日志路径：/tmp/decode.log
============================================================
EOFREADME

  if [[ -t 0 && "${JOBS_MAC_ENV_SKIP_README:-}" != "1" ]]; then
    log "" | jobs_intro_style body
    warm_echo "按回车继续执行 decode..." | jobs_intro_style body
    local _answer=""
    IFS= read -r _answer
  fi
}
# ---------- 命令实现 ----------
# 🔥 URL Decode REPL（decode -> 解码 + 自动 pbcopy）🔥
decode() {
  emulate -L zsh
  setopt no_aliases

  local input decoded

  # 统一提示
  print -P "%F{cyan}🔤 decode%f：粘贴要转的字符串/URL（支持 %E8%B6%85...）"
  print -P "%F{cyan}        回车=解码并复制到剪切板；q/quit/exit=退出%f"

  while true; do
    # -r：不转义反斜杠；?prompt：zsh 的提示符
    read -r "?👉 输入： " input || break

    # 退出指令
    case "$input" in
      q|Q|quit|QUIT|exit|EXIT)
        print -P "%F{green}✅ 已退出 decode%f"
        return 0
        ;;
    esac

    # 空输入：继续下一轮
    if [[ -z "$input" ]]; then
      print -P "%F{yellow}⚠️  请输入内容（或 q 退出）%f"
      continue
    fi

    # 用 python3 解码（macOS 基本都有；比 perl 更稳）
    decoded="$(python3 - <<'PY' "$input" 2>/dev/null
import sys, urllib.parse
print(urllib.parse.unquote(sys.argv[1]))
PY
)" || decoded=""

    if [[ -z "$decoded" ]]; then
      print -P "%F{red}❌ 解码失败：请确认你粘贴的是一整串内容%f"
      continue
    fi

    # 显示 + 复制
    print -P "%F{green}✅ 解码结果：%f$decoded"
    print -r -- "$decoded" | pbcopy
    print -P "%F{magenta}📋 已复制到剪切板%f"
  done
}
# ---------- 主流程统一收口 ----------
jobs_decode_main() {
  # 展示脚本说明并等待用户确认影响范围。
  jobs_decode_show_readme_and_wait
  # 执行当前流程中的独立业务步骤：decode。
  decode "$@"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：decode.command' | jobs_intro_style title
  print -r -- '核心用途：执行“decode”对应的自动化任务。' | jobs_intro_style body
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
  # 执行 jobs_decode_main 对应的独立业务步骤。
  jobs_decode_main "$@"
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
