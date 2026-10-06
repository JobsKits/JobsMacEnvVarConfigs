#!/bin/zsh
# 脚本自述：
# - 脚本名称：code.command
# - 核心用途：执行“code”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# JobsMacEnv VS Code CLI wrapper.
# 用途：即使 VS Code 没有执行“Shell Command: Install 'code' command in PATH”，也能在终端使用：code .


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
jobs_code_self_path="${0:A}"
# 封装 jobs_code_exec_if_valid 对应的独立处理逻辑。
jobs_code_exec_if_valid() {
  local candidate="$1"
  shift
  [[ -n "$candidate" ]] || return 1
  [[ -x "$candidate" ]] || return 1

  # 避免 ~/.local/bin/code 包装脚本递归调用自己。
  if [[ "${candidate:A}" == "$jobs_code_self_path" ]]; then
    return 1
  fi

  exec "$candidate" "$@"
}
# 封装 jobs_code_resolve_from_app 对应的独立处理逻辑。
jobs_code_resolve_from_app() {
  local app_path="$1"
  local bin_path="$app_path/Contents/Resources/app/bin/code"
  local insiders_bin_path="$app_path/Contents/Resources/app/bin/code-insiders"

  if [[ -x "$bin_path" ]]; then
    print -r -- "$bin_path"
    return 0
  fi

  if [[ -x "$insiders_bin_path" ]]; then
    print -r -- "$insiders_bin_path"
    return 0
  fi

  return 1
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
jobs_code_main() {
  # 初始化当前流程后续步骤需要使用的变量。
  local candidate=""
  # 初始化当前流程后续步骤需要使用的变量。
  local app_path=""

  # 1. 优先查找 VS Code App 内置的官方 CLI。
  local fixed_candidates=(
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    # 执行当前流程中的独立业务步骤：处理当前语句。
    "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    # 执行当前流程中的独立业务步骤：处理当前语句。
    "/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code-insiders"
    # 执行当前流程中的独立业务步骤：处理当前语句。
    "$HOME/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code-insiders"
  )

  # 循环处理用户输入或当前批次中的全部目标。
  for candidate in "${fixed_candidates[@]}"; do
    # 执行当前流程中的独立业务步骤：jobs_code_exec_if_valid。
    jobs_code_exec_if_valid "$candidate" "$@" || true
  done

  # 2. 兼容用户之后又安装了官方 code 软链接的情况。
  local link_candidates=(
    "/usr/local/bin/code"
    # 执行当前流程中的独立业务步骤：处理当前语句。
    "/opt/homebrew/bin/code"
  )

  # 循环处理用户输入或当前批次中的全部目标。
  for candidate in "${link_candidates[@]}"; do
    # 执行当前流程中的独立业务步骤：jobs_code_exec_if_valid。
    jobs_code_exec_if_valid "$candidate" "$@" || true
  done

  # 3. Spotlight 兜底：如果 VS Code 被放在非标准目录，尝试通过 Bundle ID 查找。
  if command -v mdfind >/dev/null 2>&1; then
    # 初始化当前流程后续步骤需要使用的变量。
    app_path="$(mdfind 'kMDItemCFBundleIdentifier == "com.microsoft.VSCode"' 2>/dev/null | head -n 1)"
    # 根据当前条件选择对应的执行分支。
    if [[ -n "$app_path" ]]; then
      # 初始化当前流程后续步骤需要使用的变量。
      candidate="$(jobs_code_resolve_from_app "$app_path" 2>/dev/null || true)"
      # 执行当前流程中的独立业务步骤：jobs_code_exec_if_valid。
      jobs_code_exec_if_valid "$candidate" "$@" || true
    fi

    # 初始化当前流程后续步骤需要使用的变量。
    app_path="$(mdfind 'kMDItemCFBundleIdentifier == "com.microsoft.VSCodeInsiders"' 2>/dev/null | head -n 1)"
    # 根据当前条件选择对应的执行分支。
    if [[ -n "$app_path" ]]; then
      # 初始化当前流程后续步骤需要使用的变量。
      candidate="$(jobs_code_resolve_from_app "$app_path" 2>/dev/null || true)"
      # 执行当前流程中的独立业务步骤：jobs_code_exec_if_valid。
      jobs_code_exec_if_valid "$candidate" "$@" || true
    fi
  fi

  # 执行当前流程中的独立业务步骤：cat。
  cat >&2 <<'EOFERR'
code: 未找到 VS Code 的命令行入口。

已检查：
  /Applications/Visual Studio Code.app/Contents/Resources/app/bin/code
  ~/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code
  /usr/local/bin/code
  /opt/homebrew/bin/code

处理方式：
  1. 确认 Visual Studio Code.app 已安装在 /Applications 或 ~/Applications；
  2. 重新执行 JobsMacEnvVarConfigs/install.command；
  3. 或在 VS Code 中执行：Command Palette → Shell Command: Install 'code' command in PATH。
EOFERR
  # 执行当前流程中的独立业务步骤：return。
  return 127
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：code.command' | jobs_intro_style title
  print -r -- '核心用途：执行“code”对应的自动化任务。' | jobs_intro_style body
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
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  emulate -L zsh
  set -o pipefail
  setopt NO_NOMATCH
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_script_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行 jobs_code_main 对应的独立业务步骤。
  jobs_code_main "$@"
}

main "$@"
