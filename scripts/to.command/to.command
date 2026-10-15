#!/bin/zsh
# 脚本自述：
# - 脚本名称：to.command
# - 核心用途：执行“to”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


# ---------- 基础路径 ----------
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
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
  jobs_brew_find
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
  if ! ask_any_to_run "是否通过 Homebrew 安装 FFmpeg？"; then
    error_echo "已跳过 FFmpeg 安装，无法继续转换。"
    return 1
  fi
  jobs_brew_install_or_exit
  local brew_bin="$JOBS_HOMEBREW_BIN"
  "$brew_bin" install ffmpeg 2>&1 | tee -a "$LOG_FILE"
  local brew_status=${pipestatus[1]}
  (( brew_status == 0 )) || return "$brew_status"
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
