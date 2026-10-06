#!/bin/zsh
# 脚本自述：
# - 脚本名称：shell.command
# - 核心用途：执行“shell”对应的本机环境配置任务。
# - 影响范围：可能安装、更新或修改当前用户的工具链与配置文件。
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
# ---------- 内置自述 ----------
jobs_shell_show_readme_and_wait() {
  clear 2>/dev/null || true
  cat <<'EOFREADME' | tee -a "$LOG_FILE" | jobs_intro_style auto
============================================================
shell - Shell 切换
============================================================

这是 shell.command 的内置自述，不读取同级 README.md。

功能：
  扫描当前机器可用 shell，并通过 fzf 或文本菜单选择默认登录 shell。

结构：
  Scripts/shell.command/shell.command
  Scripts/shell.command/README.md

运行：
  shell
  shell [参数...]

说明：
  - 会优先读取 /etc/shells，同时补充 Homebrew 常见 zsh/bash/fish 路径。
  - chsh 可能要求输入当前用户密码。
  - 终端可输入的自定义命令都应独立收进 Scripts。
  - README.md 只作为源码说明；运行时展示的是脚本内置自述。
  - 日志路径：/tmp/shell.log
============================================================
EOFREADME

  if [[ -t 0 && "${JOBS_MAC_ENV_SKIP_README:-}" != "1" ]]; then
    log "" | jobs_intro_style body
    warm_echo "按回车继续执行 shell..." | jobs_intro_style body
    local _answer=""
    IFS= read -r _answer
  fi
}
# ---------- 通用工具 ----------
jobs_shell_has() {
  command -v "$1" >/dev/null 2>&1
}
# 封装 jobs_shell_collect_candidates 对应的独立处理逻辑。
jobs_shell_collect_candidates() {
  local candidates=()
  local item=""
  local brew_prefix=""

  if [[ -f /etc/shells ]]; then
    while IFS= read -r item || [[ -n "$item" ]]; do
      [[ -n "$item" ]] || continue
      [[ "$item" == \#* ]] && continue
      [[ -x "$item" ]] || continue
      candidates+=("$item")
    done < /etc/shells
  fi

  if jobs_shell_has brew; then
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
    if [[ -n "$brew_prefix" ]]; then
      candidates+=(
        "$brew_prefix/bin/zsh"
        "$brew_prefix/bin/bash"
        "$brew_prefix/bin/fish"
      )
    fi
  fi

  candidates+=(
    /bin/zsh
    /bin/bash
    /usr/local/bin/zsh
    /usr/local/bin/bash
    /usr/local/bin/fish
    /opt/homebrew/bin/zsh
    /opt/homebrew/bin/bash
    /opt/homebrew/bin/fish
  )

  printf "%s\n" "${candidates[@]}" | awk 'NF && !seen[$0]++' | while IFS= read -r item; do
    [[ -x "$item" ]] && print -r -- "$item"
  done
}
# 封装 jobs_shell_is_in_etc_shells 对应的独立处理逻辑。
jobs_shell_is_in_etc_shells() {
  local shell_path="$1"
  [[ -f /etc/shells ]] || return 1
  grep -Fxq "$shell_path" /etc/shells
}
# 封装 jobs_shell_choose_with_fzf 对应的独立处理逻辑。
jobs_shell_choose_with_fzf() {
  local current_shell="${SHELL:-}"
  jobs_shell_collect_candidates | while IFS= read -r item; do
    if [[ "$item" == "$current_shell" ]]; then
      print -r -- "$item	当前默认 Shell"
    elif jobs_shell_is_in_etc_shells "$item"; then
      print -r -- "$item	/etc/shells 已登记"
    else
      print -r -- "$item	未登记到 /etc/shells"
    fi
  done | fzf \
    --delimiter=$'\t' \
    --with-nth=1,2 \
    --prompt='Select shell > ' \
    --height=80% \
    --border \
    --no-sort \
    --layout=reverse \
    --header=$'选择默认登录 shell；Esc 取消。' \
  | awk -F '\t' '{print $1}'
}
# 封装 jobs_shell_choose_with_text_menu 对应的独立处理逻辑。
jobs_shell_choose_with_text_menu() {
  local candidates=()
  local item=""
  local index=1
  local answer=""

  while IFS= read -r item; do
    [[ -n "$item" ]] && candidates+=("$item")
  done < <(jobs_shell_collect_candidates)

  if (( ${#candidates[@]} == 0 )); then
    error_echo "没有找到可用 shell"
    return 1
  fi

  bold_echo "可用 shell："
  for item in "${candidates[@]}"; do
    local marker=""
    [[ "$item" == "${SHELL:-}" ]] && marker="  当前"
    jobs_shell_is_in_etc_shells "$item" || marker="  未登记到 /etc/shells"
    printf "%2d) %s%s\n" "$index" "$item" "$marker" | tee -a "$LOG_FILE"
    (( index++ ))
  done

  log ""
  warm_echo "输入编号后回车切换；直接回车取消："
  IFS= read -r answer
  [[ -n "$answer" ]] || return 1

  if [[ ! "$answer" =~ '^[0-9]+$' ]]; then
    error_echo "输入不是编号：$answer"
    return 1
  fi

  if (( answer < 1 || answer > ${#candidates[@]} )); then
    error_echo "编号超出范围：$answer"
    return 1
  fi

  JOBS_SHELL_SELECTED="${candidates[$answer]}"
}
# 封装 jobs_shell_choose 对应的独立处理逻辑。
jobs_shell_choose() {
  JOBS_SHELL_SELECTED=""

  if jobs_shell_has fzf; then
    JOBS_SHELL_SELECTED="$(jobs_shell_choose_with_fzf || true)"
  else
    warn_echo "fzf 不可用，改用文本菜单"
    jobs_shell_choose_with_text_menu || return 1
  fi

  [[ -n "$JOBS_SHELL_SELECTED" ]]
}
# 封装 jobs_shell_ensure_registered 对应的独立处理逻辑。
jobs_shell_ensure_registered() {
  local selected_shell="$1"
  local answer=""

  if jobs_shell_is_in_etc_shells "$selected_shell"; then
    return 0
  fi

  warn_echo "所选 shell 未登记到 /etc/shells：$selected_shell"
  log "👉 直接按 [Enter]：取消切换"
  log "👉 输入 YES 后回车：使用 sudo 写入 /etc/shells 后继续"
  IFS= read -r answer

  if [[ "$answer" != "YES" ]]; then
    note_echo "已取消 shell 切换"
    return 1
  fi

  print -r -- "$selected_shell" | sudo tee -a /etc/shells >/dev/null
  success_echo "已写入 /etc/shells：$selected_shell"
}
# 封装 jobs_shell_switch 对应的独立处理逻辑。
jobs_shell_switch() {
  local selected_shell="$1"

  [[ -x "$selected_shell" ]] || {
    error_echo "不可执行：$selected_shell"
    return 1
  }

  if [[ "$selected_shell" == "${SHELL:-}" ]]; then
    note_echo "当前默认 shell 已经是：$selected_shell"
    return 0
  fi

  jobs_shell_ensure_registered "$selected_shell" || return 1

  highlight_echo "正在切换默认 shell：$selected_shell"
  chsh -s "$selected_shell" || {
    error_echo "chsh 失败：$selected_shell"
    return 1
  }

  success_echo "默认 shell 已切换为：$selected_shell"
  note_echo "请新开一个终端窗口验证：echo \$SHELL"
}
# ---------- 命令实现 ----------
shell() {
  emulate -L zsh

  local selected_shell=""
  if ! jobs_shell_choose; then
    note_echo "已取消 shell 切换"
    return 0
  fi

  selected_shell="$JOBS_SHELL_SELECTED"
  jobs_shell_switch "$selected_shell"
}
# ---------- 主流程统一收口 ----------
jobs_shell_main() {
  # 展示脚本说明并等待用户确认影响范围。
  jobs_shell_show_readme_and_wait
  # 执行当前流程中的独立业务步骤：shell。
  shell "$@"
  # 执行当前流程中的独立业务步骤：gray_echo。
  gray_echo "日志路径：$LOG_FILE"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：shell.command' | jobs_intro_style title
  print -r -- '核心用途：执行“shell”对应的自动化任务。' | jobs_intro_style body
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
  # 执行 jobs_shell_main 对应的独立业务步骤。
  jobs_shell_main "$@"
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
