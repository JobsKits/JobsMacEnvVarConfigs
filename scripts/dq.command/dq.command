#!/bin/zsh
# 脚本自述：
# - 脚本名称：dq.command
# - 核心用途：解决新装 App 无法打开、被系统建议移到废纸篓的问题。
# - 影响范围：只修改用户传入路径的 com.apple.quarantine 扩展属性。
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
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }

# ---------- 运行配置 ----------
DQ_OPEN_AFTER="false"
DQ_DRY_RUN="false"
DQ_TARGETS=()

# 打印 dq 的内置使用说明。
jobs_dq_print_usage() {
  cat <<'EOFUSAGE' | tee -a "$LOG_FILE"

用法：
  dq
  dq 文件或目录
  dq --open 文件或目录
  dq --dry-run 文件或目录

示例：
  dq
  dq ~/Downloads/Otty.dmg
  dq "/Users/jobs/Downloads/Otty (1).dmg"
  dq /Users/jobs/Downloads/Otty\ \(1\).dmg
  dq --open /Applications/Otty.app

参数：
  --open       清理隔离标记后调用 open 打开目标。
  --dry-run    只检查目标是否存在 quarantine 标记，不修改文件。
  -h, --help   显示帮助。

安全边界：
  - 本命令只移除传入路径上的 com.apple.quarantine 扩展属性。
  - 不会执行 spctl --master-disable，也不会全局关闭 Gatekeeper。
  - 请只对你确认来源可信的下载文件、DMG、zip 或 App 使用。
EOFUSAGE
}

# 展示脚本用途和影响范围。
show_script_intro() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：dq.command' | jobs_intro_style title
  print -r -- '核心用途：解决新装 App 无法打开、被系统建议移到废纸篓的问题。' | jobs_intro_style body
  print -r -- '影响范围：只修改用户传入路径的 com.apple.quarantine 扩展属性。' | jobs_intro_style body
  print -r -- '取消方式：输入路径前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  jobs_dq_print_usage
}

# 去掉拖入路径产生的引号、反斜杠转义和换行。
jobs_dq_normalize_path() {
  local raw="$1"
  raw="${raw%$'\r'}"
  raw="${raw%$'\n'}"
  print -r -- "${(Q)raw}"
}

# 把用户输入或拖入的一行路径拆成一个或多个目标路径。
jobs_dq_add_input_targets() {
  local input="$1"
  local item=""
  local normalized=""
  local parsed_items=()

  input="${input%$'\r'}"
  input="${input%$'\n'}"
  [[ -n "$input" ]] || return 1

  parsed_items=("${(@z)input}")
  for item in "${parsed_items[@]}"; do
    normalized="$(jobs_dq_normalize_path "$item")"
    [[ -n "$normalized" ]] && DQ_TARGETS+=("$normalized")
  done

  (( ${#parsed_items[@]} > 0 ))
}

# 直接输入 dq 时循环询问目标路径，直到用户输入或拖入有效内容。
jobs_dq_prompt_targets_if_needed() {
  local input=""

  (( ${#DQ_TARGETS[@]} > 0 )) && return 0

  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行，并传入目标路径。'
    return 1
  fi

  while (( ${#DQ_TARGETS[@]} == 0 )); do
    IFS= read -r "?👉 请输入或拖入要修复打开限制的文件 / App / 目录路径，然后回车：" input
    if ! jobs_dq_add_input_targets "$input"; then
      warn_echo "未输入路径，请重新输入；按 Ctrl+C 可取消。"
    fi
  done
}

# 解析命令参数并收集待处理路径。
jobs_dq_parse_args() {
  local arg=""
  local normalized=""

  while (( $# > 0 )); do
    arg="$1"
    shift

    case "$arg" in
      --open)
        DQ_OPEN_AFTER="true"
        ;;
      --dry-run)
        DQ_DRY_RUN="true"
        ;;
      -h|--help)
        jobs_dq_print_usage
        return 2
        ;;
      --)
        while (( $# > 0 )); do
          normalized="$(jobs_dq_normalize_path "$1")"
          DQ_TARGETS+=("$normalized")
          shift
        done
        ;;
      -*)
        error_echo "未知参数：$arg"
        return 1
        ;;
      *)
        normalized="$(jobs_dq_normalize_path "$arg")"
        DQ_TARGETS+=("$normalized")
        ;;
    esac
  done

  return 0
}

# 检查目标路径是否带有 quarantine 标记。
jobs_dq_has_quarantine() {
  local target="$1"
  xattr -p com.apple.quarantine "$target" >/dev/null 2>&1
}

# 对单个目标执行打开限制相关隔离标记清理。
jobs_dq_handle_one() {
  local target="$1"

  if [[ ! -e "$target" ]]; then
    error_echo "目标不存在：$target"
    return 1
  fi

  if jobs_dq_has_quarantine "$target"; then
    info_echo "检测到 quarantine 标记：$target"
  else
    warn_echo "未检测到 quarantine 标记，仍会递归确认子项：$target"
  fi

  if [[ "$DQ_DRY_RUN" == "true" ]]; then
    note_echo "dry-run：未修改目标。"
    return 0
  fi

  if xattr -dr com.apple.quarantine "$target"; then
    success_echo "已清理打开限制隔离标记：$target"
  else
    error_echo "清理打开限制隔离标记失败：$target"
    return 1
  fi

  if [[ "$DQ_OPEN_AFTER" == "true" ]]; then
    open "$target" || warn_echo "open 打开失败：$target"
  fi
}

# 执行所有目标的打开限制相关隔离标记清理。
dq() {
  local target=""
  local failed=0

  for target in "${DQ_TARGETS[@]}"; do
    jobs_dq_handle_one "$target" || failed=1
  done

  return "$failed"
}

# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
jobs_dq_main() {
  jobs_dq_parse_args "$@" || return $?
  show_script_intro
  jobs_dq_prompt_targets_if_needed || return $?
  dq
}

# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  jobs_dq_main "$@"
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
