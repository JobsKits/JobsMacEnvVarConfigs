#!/bin/zsh
# 脚本自述：
# - 脚本名称：i.command
# - 核心用途：打开当前 Xcode 的 Device Hub（Xcode 27）或旧版 Simulator。
# - 影响范围：启动模拟器管理应用；不安装组件、不修改项目或全局开发目录。
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
SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME="i"
LOG_FILE=""
ENV_HOME=""
# 优先加载相邻会话库，部署目录作为兼容回退。
jobs_i_source_lib() {
  local lib_name="$1"
  local candidate=""
  local candidates=(
    "$SCRIPT_DIR/../_lib/$lib_name"
    "$ENV_HOME/Scripts/_lib/$lib_name"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      source "$candidate" || return 1
      return 0
    fi
  done

  print -u2 -r -- "✖ 缺少私有库：$lib_name"
  print -u2 -r -- "请重新执行 JobsMacEnv 安装脚本。"
  return 1
}
# 封装 i 对应的独立处理逻辑。
i() {
  jobs_session_i_impl "$@"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" == "1" ]] && return 0
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：i.command' | jobs_intro_style title
  print -r -- '核心用途：打开 Xcode 27 Device Hub 或旧版 iOS Simulator。' | jobs_intro_style body
  print -r -- '影响范围：仅启动应用；不安装组件、不修改项目或全局开发目录。' | jobs_intro_style body
  print -r -- '定位顺序：DEVELOPER_DIR → xcode-select → 常见 Xcode 安装目录。' | jobs_intro_style body
  print -r -- '日志位置：系统临时目录中的 i.log。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    exit 1
  fi
  local answer=""
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" answer || exit 1
}
# 确认后初始化路径和日志，加载会话库并记录应用启动结果。
jobs_i_main() {
  emulate -L zsh
  set -o pipefail
  setopt NO_NOMATCH
  SCRIPT_DIR="${${(%):-%x}:A:h}"
  SCRIPT_PATH="$SCRIPT_DIR/i.command"
  ENV_HOME="${JOBS_MAC_ENV_HOME:-$HOME/.JobsMacEnv}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
  jobs_i_source_lib "jobs_session_lib.zsh" || return 1
  [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" == "1" ]] && return 0
  : > "$LOG_FILE" || return 1
  i "$@" 2>&1 | tee -a "$LOG_FILE"
}
# 编排一次自述确认和模拟器启动。
main() {
  show_script_intro_and_wait # 展示准确用途并等待一次回车，取消时不执行业务。
  jobs_i_main "$@" # 加载启动逻辑，定位应用并记录返回结果。
}

main "$@"
