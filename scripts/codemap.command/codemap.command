#!/bin/zsh
# 脚本自述：
# - 脚本名称：codemap.command
# - 核心用途：为当前目录或传入的一个、多个目录构建 CodeGraph 代码地图。
# - 影响范围：只构建目标目录内的 .codegraph，包括其中的 .gitignore；不会安装 Git hooks。
# - 运行提示：先阅读内置自述并按回车确认；Ctrl+C 取消；缺少依赖时停止，不自动安装。
# shell: zsh

typeset SCRIPT_DIR SCRIPT_PATH SCRIPT_BASENAME LOG_FILE CODEGRAPH_BIN CODEGRAPH_OPERATION
typeset -a TARGET_DIRS
typeset -i SUCCEEDED_COUNT=0 FAILED_COUNT=0

# 按终端能力展示红色标题或蓝色正文，非彩色环境使用纯文本。
jobs_intro_style() {
  local intro_color=0
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      printf "%s%s%s\n", esc (role == "title" ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
# 首先说明索引影响，并阻止缺少交互输入的误调用。
show_script_intro_and_wait() {
  print -r -- '====================== codemap：构建代码地图 ======================' | jobs_intro_style title
  print -r -- '1、codemap：构建当前目录；codemap 目录 [更多目录...]：构建指定目录。' | jobs_intro_style body
  print -r -- '2、支持手工输入、Finder 拖入路径及多个目录；含空格路径请加引号或直接拖入。' | jobs_intro_style body
  print -r -- '3、首次初始化 .codegraph，已有地图则完整重建；索引文件与内部 .gitignore 均位于 .codegraph。' | jobs_intro_style body
  print -r -- '4、只调用已安装且健康的 CodeGraph；缺失时停止并提示安装入口，不隐式安装工具。' | jobs_intro_style body
  print -r -- "5、日志：${TMPDIR:-/tmp}/codemap.log；确认前按 Ctrl+C 取消。" | jobs_intro_style body
  print -r -- '==================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '✖ 当前没有可交互输入，请在终端中重新运行 codemap。'
    exit 1
  fi
  if ! IFS= read -r "?👉 已了解用途与影响，按回车继续；按 Ctrl+C 取消：" _; then
    print -u2 -r -- '✖ 输入已结束，未执行代码地图构建。'
    exit 1
  fi
}
# 确认后初始化路径、日志和 Shell 选项，不改变调用者的当前目录。
initialize_script_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
  SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
  SCRIPT_BASENAME="codemap"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
  if ! : > "$LOG_FILE"; then
    print -u2 -r -- "✖ 无法创建日志：$LOG_FILE"
    exit 1
  fi
  TARGET_DIRS=()
  SUCCEEDED_COUNT=0
  FAILED_COUNT=0
}
# 将业务消息同步到终端和纯文本日志，保留路径中的反斜杠字面量。
log_message() {
  local level="$1" color="$2"
  shift 2
  print -r -- "$level $*" >> "$LOG_FILE"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s %s\033[0m\n' "$color" "$level" "$*"
  else
    print -r -- "$level $*"
  fi
}
# 记录当前正在检查或执行的步骤。
info_echo() {
  log_message 'ℹ' '1;34' "$@"
}
# 记录已经验证的成功结果。
success_echo() {
  log_message '✔' '1;32' "$@"
}
# 记录不会被静默忽略的失败原因。
error_echo() {
  log_message '✖' '1;31' "$@"
}
# 仅在原样路径不存在时处理拖入转义，避免损坏真实引号或反斜杠文件名。
normalize_target_path() {
  local target_input="$1"
  if [[ ! -d "$target_input" ]]; then
    target_input="${target_input%$'\n'}"
    target_input="${target_input%$'\r'}"
    if [[ ! -d "$target_input" ]]; then
      target_input="${(Q)target_input}"
    fi
    if [[ "$target_input" == '~' ]]; then
      target_input="$HOME"
    elif [[ "$target_input" == '~/'* ]]; then
      target_input="$HOME/${target_input#\~/}"
    fi
  fi
  if [[ -z "$target_input" || ! -d "$target_input" ]]; then
    error_echo "目标必须是存在的目录：$1"
    return 1
  fi
  REPLY="${target_input:A}"
  if [[ "$REPLY" == / || "$REPLY" == "${HOME:A}" ]]; then
    error_echo "不对文件系统根目录或用户主目录整体建图，请指定项目目录：$REPLY"
    return 1
  fi
  if [[ ! -r "$REPLY" || ! -x "$REPLY" || ! -w "$REPLY" ]]; then
    error_echo "目标需要可读取、进入并写入 .codegraph：$REPLY"
    return 1
  fi
  if [[ -L "$REPLY/.codegraph" || ( -e "$REPLY/.codegraph" && ! -d "$REPLY/.codegraph" ) ]]; then
    error_echo ".codegraph 必须是目标内的普通目录，不能是文件或符号链接：$REPLY/.codegraph"
    return 1
  fi
  return 0
}
# 一次校验全部目标并去重；不传参数时使用调用时的当前目录。
collect_target_directories() {
  local target_input REPLY
  local -a requested_targets
  requested_targets=("$@")
  if [[ "${requested_targets[1]:-}" == -- ]]; then
    requested_targets[1]=()
  fi
  if (( ${#requested_targets[@]} == 0 )); then
    requested_targets=("$PWD")
  fi
  for target_input in "${requested_targets[@]}"; do
    if ! normalize_target_path "$target_input"; then
      error_echo '参数校验失败，本次没有开始构建任何目标。'
      exit 2
    fi
    if (( ${TARGET_DIRS[(Ie)$REPLY]} == 0 )); then
      TARGET_DIRS+=("$REPLY")
    fi
  done
}
# 在同级仓库布局中寻找独立安装器；运行态副本缺失源码布局时给出入口名称。
show_installation_hint() {
  local installer_name='【MacOS】⚙️安装代码地图CodeGraph.command'
  local installer="${SCRIPT_DIR}/../../../../JobsCommand@iOS/配置相关/${installer_name}/${installer_name}"
  error_echo '未找到可用 CodeGraph；请先运行独立安装器，完成 Homebrew 与工具链健康体检。'
  if [[ -f "$installer" ]]; then
    info_echo "安装入口：${installer:A}"
  else
    info_echo "安装入口：JobsCommand@iOS/配置相关/${installer_name}/${installer_name}"
  fi
}
# 发现发行版并验证版本和索引接口，残缺安装不能进入建图流程。
check_codegraph_environment() {
  local candidate version_output
  local -a candidates
  if [[ ! -x /usr/bin/plutil ]]; then
    error_echo '缺少 macOS 原生 plutil，无法校验 CodeGraph 的 JSON 构建状态。'
    exit 1
  fi
  candidates=(
    "$HOME/.local/share/jobs-codegraph/bin/codegraph"
    "$(command -v codegraph 2>/dev/null)"
    /opt/homebrew/bin/codegraph
    /usr/local/bin/codegraph
    "$HOME/.local/bin/codegraph"
    "$HOME/.npm-global/bin/codegraph"
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/codegraph"
    "$HOME/.homebrew/bin/codegraph"
  )
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if version_output="$(CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$candidate" --version 2>&1)" &&
       CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$candidate" init --help >/dev/null 2>&1 &&
       CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$candidate" index --help >/dev/null 2>&1 &&
       CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$candidate" status --help >/dev/null 2>&1; then
      CODEGRAPH_BIN="$candidate"
      info_echo "CodeGraph 已通过版本和 CLI 接口检查：$candidate（$version_output）"
      return 0
    fi
    error_echo "发现不可用 CodeGraph：$candidate；版本检查输出：$version_output"
  done
  show_installation_hint
  exit 127
}
# 记录实际命令及输出，透传 CodeGraph 和日志管道的失败状态。
run_codegraph_logged() {
  local -a command_status
  info_echo "执行：${(q)CODEGRAPH_BIN} ${(j: :)${(q)@}}"
  /usr/bin/env -u CODEGRAPH_NO_WATCH CODEGRAPH_DIR=.codegraph CODEGRAPH_TELEMETRY=0 \
    CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 NO_COLOR=1 FORCE_COLOR=0 \
    "$CODEGRAPH_BIN" "$@" 2>&1 | /usr/bin/tee -a "$LOG_FILE"
  command_status=("${pipestatus[@]}")
  if (( command_status[1] != 0 )); then
    error_echo "CodeGraph 执行失败，退出码：${command_status[1]}"
    return "${command_status[1]}"
  fi
  if (( command_status[2] != 0 )); then
    error_echo "日志写入失败，退出码：${command_status[2]}"
    return 1
  fi
  return 0
}
# 从官方 JSON 读取字段，无法解析时返回失败而非猜测成功。
read_status_field() {
  /usr/bin/plutil -extract "$1" raw -o - - <<< "$2" 2>/dev/null
}
# 根据目标自身的初始化状态选择操作，空目录及父项目索引不能当成本项目地图。
choose_codegraph_operation() {
  local target_dir="$1" status_json initialized project_path
  CODEGRAPH_OPERATION=init
  [[ -d "$target_dir/.codegraph" ]] || return 0
  if ! status_json="$(CODEGRAPH_DIR=.codegraph CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$CODEGRAPH_BIN" status --json "$target_dir" 2>&1)"; then
    error_echo "已有地图状态读取失败：$target_dir；$status_json"
    return 1
  fi
  print -r -- "$status_json" >> "$LOG_FILE"
  initialized="$(read_status_field initialized "$status_json")" || return 1
  project_path="$(read_status_field projectPath "$status_json")" || return 1
  if [[ "$initialized" == true && "$project_path" == "$target_dir" ]]; then
    CODEGRAPH_OPERATION=index
  elif [[ "$initialized" == false || ( "$initialized" == true && "$project_path" != "$target_dir" ) ]]; then
    info_echo "目标尚未初始化，将修复空目录或失败残留：$target_dir/.codegraph"
  else
    error_echo "无法识别已有地图的初始化状态：$target_dir"
    return 1
  fi
}
# 核对项目身份、输出位置和完整状态，防止只有空目录也被认作构建成功。
verify_codegraph_result() {
  local target_dir="$1" status_json initialized project_path index_path last_indexed index_state
  if ! status_json="$(CODEGRAPH_DIR=.codegraph CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$CODEGRAPH_BIN" status --json "$target_dir" 2>&1)"; then
    error_echo "CodeGraph 状态读取失败：$target_dir；$status_json"
    return 1
  fi
  print -r -- "$status_json" | /usr/bin/tee -a "$LOG_FILE"
  initialized="$(read_status_field initialized "$status_json")" || return 1
  project_path="$(read_status_field projectPath "$status_json")" || return 1
  index_path="$(read_status_field indexPath "$status_json")" || return 1
  last_indexed="$(read_status_field lastIndexed "$status_json")" || return 1
  index_state="$(read_status_field index.state "$status_json")" || return 1
  if [[ "$initialized" != true || "$project_path" != "$target_dir" ||
        "$index_path" != "$target_dir/.codegraph" || -z "$last_indexed" ||
        "$last_indexed" == null || "$index_state" != complete || ! -d "$target_dir/.codegraph" ]]; then
    error_echo "产物校验失败：项目身份、.codegraph 位置或完整索引状态不匹配：$target_dir"
    return 1
  fi
  return 0
}
# 首次初始化项目，已有地图时调用官方完整重建，再验证真实产物。
build_one_codemap() {
  local target_dir="$1"
  info_echo "开始构建：$target_dir"
  if ! choose_codegraph_operation "$target_dir"; then
    error_echo "无法安全确定初始化或重建方式：$target_dir"
    return 1
  fi
  if [[ "$CODEGRAPH_OPERATION" == index ]]; then
    run_codegraph_logged index "$target_dir" || return 1
  else
    run_codegraph_logged init --yes "$target_dir" || return 1
  fi
  if ! verify_codegraph_result "$target_dir"; then
    error_echo "构建未通过完整性检查，请查看日志后重试：$target_dir"
    return 1
  fi
  success_echo "代码地图已生成：$target_dir/.codegraph"
}
# 依次处理全部目录，单个目标失败时继续收集其余目标结果。
build_target_codemaps() {
  local target_dir
  for target_dir in "${TARGET_DIRS[@]}"; do
    if build_one_codemap "$target_dir"; then
      (( SUCCEEDED_COUNT += 1 ))
    else
      (( FAILED_COUNT += 1 ))
    fi
  done
}
# 汇总批处理结果；任一目标失败都返回非零退出码。
finish_codemap_run() {
  info_echo "处理结束：成功 $SUCCEEDED_COUNT，失败 $FAILED_COUNT；日志：$LOG_FILE"
  if (( FAILED_COUNT > 0 )); then
    exit 1
  fi
}
# 编排确认、校验、建图和结果汇总。
main() {
  show_script_intro_and_wait # 先展示内置自述并等待确认，避免误触后修改项目。
  initialize_script_runtime # 确认后初始化路径、日志与运行选项。
  collect_target_directories "$@" # 解析当前目录或多个手工、拖入路径并一次校验。
  check_codegraph_environment # 只复用通过健康检查的 CodeGraph，不隐式安装依赖。
  build_target_codemaps # 按目标是否已有地图选择初始化或重建并校验结果。
  finish_codemap_run # 输出成功和失败统计，并向终端返回整体状态。
}

main "$@"
