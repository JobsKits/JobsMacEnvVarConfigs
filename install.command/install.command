#!/bin/zsh
# 脚本自述：
# - 脚本名称：install.command
# - 核心用途：执行“install”对应的自动化任务。
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

# ---------- 默认配置 ----------
CURRENT_SECTION=""
JAVA_VERSION="17"
JAVA_CANDIDATES="temurin@17,zulu@17,openjdk@17"
ANDROID_SDK_DEFAULT='$HOME/Library/Android/sdk'
USE_FVM="true"
FLUTTER_CANDIDATES='$HOME/fvm/default/bin,$HOME/development/flutter/bin'
ENABLE_PNPM="true"
ENABLE_COREPACK="true"
NVM_DIR='$HOME/.nvm'
ENABLE_CARGO="true"
CARGO_HOME='$HOME/.cargo'
ENABLE_PYENV="true"
PYENV_ROOT='$HOME/.pyenv'
ENABLE_RBENV="true"
RBENV_ROOT='$HOME/.rbenv'
ENABLE_GO="true"
GOPATH='$HOME/go'
PATH_LIST=()
ALIAS_LIST=()
# ---------- 通用工具 ----------
ensure_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || mkdir -p "$dir"
}
# 封装 trim 对应的独立处理逻辑。
trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "$value"
}
# 封装 write_file_if_changed 对应的独立处理逻辑。
write_file_if_changed() {
  local target="$1"
  local content="$2"
  local tmp=""

  tmp="$(mktemp)"
  printf "%s" "$content" > "$tmp"

  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    rm -f "$tmp"
    info_echo "无变化，跳过：$target"
    return 0
  fi

  mv "$tmp" "$target"
  success_echo "已写入：$target"
}
# 封装 copy_file_if_changed 对应的独立处理逻辑。
copy_file_if_changed() {
  local src="$1"
  local target="$2"

  [[ -f "$src" ]] || {
    error_echo "缺少文件：$src"
    exit 1
  }

  write_file_if_changed "$target" "$(cat "$src")"
}
# 解析并返回后续流程需要的目标信息。
get_cpu_arch() {
  uname -m
}
# 解析并返回后续流程需要的目标信息。
find_brew_bin() {
  jobs_brew_find
}
# 封装 profile_file_for_shell 对应的独立处理逻辑。
profile_file_for_shell() {
  local shell_path="${SHELL##*/}"

  case "$shell_path" in
    zsh)  print -r -- "$HOME/.zprofile" ;;
    bash) print -r -- "$HOME/.bash_profile" ;;
    *)    print -r -- "$HOME/.profile" ;;
  esac
}
# 封装 inject_shellenv_block 对应的独立处理逻辑。
inject_shellenv_block() {
  local profile_file="$1"
  local shellenv="$2"
  local id="homebrew_env"
  local header="# >>> ${id} 环境变量 >>>"
  local footer="# <<< ${id} 环境变量 <<<"

  if [[ -z "$profile_file" || -z "$shellenv" ]]; then
    error_echo "缺少参数：inject_shellenv_block <profile_file> <shellenv>"
    return 1
  fi

  ensure_dir "$(dirname "$profile_file")"
  touch "$profile_file"

  if grep -Fq "$header" "$profile_file"; then
    info_echo "Homebrew 环境变量块已存在：$profile_file"
  elif grep -Fq "$shellenv" "$profile_file"; then
    info_echo "Homebrew shellenv 已存在：$profile_file"
  else
    {
      echo ""
      echo "$header"
      echo "$shellenv"
      echo "$footer"
    } >> "$profile_file"
    success_echo "已写入 Homebrew 环境变量：$profile_file"
  fi

  eval "$shellenv"
  success_echo "Homebrew shellenv 已在当前终端生效"
}
# 执行对应的环境配置或同步处理。
install_homebrew() {
  local jobs_existing_brew=""
  if jobs_existing_brew="$(jobs_brew_find)"; then
    JOBS_HOMEBREW_BIN="$jobs_existing_brew"
    jobs_brew_activate || return 1
  fi
  local arch="$(get_cpu_arch)"
  local profile_file="$(profile_file_for_shell)"
  local brew_bin=""
  local shellenv_cmd=""
  local confirm=""

  if brew_bin="$(find_brew_bin 2>/dev/null)"; then
    shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
    inject_shellenv_block "$profile_file" "$shellenv_cmd"

    info_echo "Homebrew 已安装：$brew_bin"
    log "👉 直接按 [Enter]：跳过 Homebrew 更新"
    log "👉 输入任意字符后回车：执行 brew update && brew upgrade && brew cleanup && brew doctor && brew -v"
    IFS= read -r confirm

    if [[ -z "$confirm" ]]; then
      note_echo "已跳过 Homebrew 更新"
      return 0
    fi

    info_echo "正在更新 Homebrew..."
    brew update  || { error_echo "brew update 失败"; return 1; }
    brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
    brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
    brew doctor  || warn_echo "brew doctor 有警告/错误，请按提示处理"
    brew -v      || warn_echo "打印 brew 版本失败，可忽略"
    success_echo "Homebrew 更新流程完成"
    return 0
  fi

  warn_echo "未检测到 Homebrew，开始安装...（架构：$arch）"

  if [[ "$arch" == "arm64" ]]; then
    jobs_brew_install_or_exit || {
      error_echo "Homebrew 安装失败（arm64）"
      exit 1
    }
    brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
  else
    jobs_brew_install_or_exit || {
      error_echo "Homebrew 安装失败（x86_64）"
      exit 1
    }
    brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
  fi

  [[ -x "$brew_bin" ]] || {
    error_echo "Homebrew 安装后仍未找到 brew：$brew_bin"
    exit 1
  }

  shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
  inject_shellenv_block "$profile_file" "$shellenv_cmd"
  success_echo "Homebrew 安装完成"
}
# ---------- 配置解析 ----------
parse_sync_file() {
  local file="$1"

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    local line=""
    line="$(trim "$raw_line")"

    [[ -z "$line" ]] && continue
    [[ "${line[1]}" == "#" ]] && continue

    # zsh 对未闭合/转义不当的 [] glob 很敏感，这里不用 [[ "$line" == \[*\] ]]。
    # 直接判断首尾字符，稳定识别 sync_env.txt 的 [SECTION]。
    if (( ${#line} >= 2 )) && [[ "${line[1]}" == "[" && "${line[-1]}" == "]" ]]; then
      CURRENT_SECTION="${line[2,-2]}"
      continue
    fi

    case "$CURRENT_SECTION" in
      JAVA|ANDROID|FLUTTER|NODE|RUST|PYTHON|RUBY|GO)
        local key="${line%%=*}"
        local value="${line#*=}"
        case "$key" in
          JAVA_VERSION) JAVA_VERSION="$value" ;;
          JAVA_CANDIDATES) JAVA_CANDIDATES="$value" ;;
          ANDROID_SDK_DEFAULT) ANDROID_SDK_DEFAULT="$value" ;;
          USE_FVM) USE_FVM="$value" ;;
          FLUTTER_CANDIDATES) FLUTTER_CANDIDATES="$value" ;;
          ENABLE_PNPM) ENABLE_PNPM="$value" ;;
          ENABLE_COREPACK) ENABLE_COREPACK="$value" ;;
          NVM_DIR) NVM_DIR="$value" ;;
          ENABLE_CARGO) ENABLE_CARGO="$value" ;;
          CARGO_HOME) CARGO_HOME="$value" ;;
          ENABLE_PYENV) ENABLE_PYENV="$value" ;;
          PYENV_ROOT) PYENV_ROOT="$value" ;;
          ENABLE_RBENV) ENABLE_RBENV="$value" ;;
          RBENV_ROOT) RBENV_ROOT="$value" ;;
          ENABLE_GO) ENABLE_GO="$value" ;;
          GOPATH) GOPATH="$value" ;;
        esac
        ;;
      PATH)
        PATH_LIST+=("$line")
        ;;
      ALIASES)
        ALIAS_LIST+=("$line")
        ;;
    esac
  done < "$file"
}
# 封装 generate_env_content 对应的独立处理逻辑。
generate_env_content() {
  cat <<EOFVARS
# ========================
# 自动生成，请勿手改
# 来源：sync_env.txt
# ========================

jobs_setup_java "${JAVA_VERSION}"
jobs_setup_android "${ANDROID_SDK_DEFAULT}"
jobs_setup_flutter "${USE_FVM}" "${FLUTTER_CANDIDATES}"
jobs_setup_node "${ENABLE_COREPACK}" "${NVM_DIR}"
EOFVARS

  [[ "$ENABLE_CARGO" == "true" ]] && echo "jobs_setup_rust \"${CARGO_HOME}\""
  [[ "$ENABLE_PYENV" == "true" ]] && echo "jobs_setup_pyenv \"${PYENV_ROOT}\""
  [[ "$ENABLE_RBENV" == "true" ]] && echo "jobs_setup_rbenv \"${RBENV_ROOT}\""
  [[ "$ENABLE_GO" == "true" ]] && echo "jobs_setup_go \"${GOPATH}\""

  echo ""
  echo "# PATH"
  local item=""
  for item in "${PATH_LIST[@]}"; do
    echo "jobs_path_add \"${item}\""
  done

  if [[ "$ENABLE_PNPM" == "true" ]]; then
    cat <<'EOFPNPM'
if command -v pnpm >/dev/null 2>&1; then
  PNPM_HOME="${HOME}/Library/pnpm"
  export PNPM_HOME
  jobs_path_add "$PNPM_HOME"
fi
EOFPNPM
  fi
}
# 封装 generate_aliases_content 对应的独立处理逻辑。
generate_aliases_content() {
  echo "# 自动生成别名"

  local item=""
  for item in "${ALIAS_LIST[@]}"; do
    local name="${item%%=*}"
    local value="${item#*=}"
    echo "alias ${name}='${value}'"
  done
}
# 封装 generate_minimal_zshrc 对应的独立处理逻辑。
generate_minimal_zshrc() {
  cat <<'EOFZSHRC'
# JobsMacEnv 主入口
# 只保留最小入口，具体逻辑全部拆到 $HOME/.JobsMacEnv 下维护

export JOBS_MAC_ENV_HOME="$HOME/.JobsMacEnv"
[[ -n "${JOBS_MAC_ENV_HOME_OVERRIDE:-}" ]] && export JOBS_MAC_ENV_HOME="$JOBS_MAC_ENV_HOME_OVERRIDE"
# 封装 jobs_source_if_exists 对应的独立处理逻辑。
jobs_source_if_exists() {
  local file="$1"
  [[ -f "$file" ]] && source "$file"
}

jobs_source_if_exists "$JOBS_MAC_ENV_HOME/zsh/bootstrap.zsh"
jobs_source_if_exists "$JOBS_MAC_ENV_HOME/zsh/env_methods.zsh"
jobs_source_if_exists "$JOBS_MAC_ENV_HOME/zsh/env.zsh"
jobs_source_if_exists "$JOBS_MAC_ENV_HOME/zsh/aliases.zsh"
jobs_source_if_exists "$JOBS_MAC_ENV_HOME/zsh/user_mounts.zsh"
EOFZSHRC
}
# ---------- Java ----------
has_java_version() {
  local version="$1"
  [[ -x /usr/libexec/java_home ]] || return 1
  /usr/libexec/java_home -v "$version" >/dev/null 2>&1
}
# 执行对应的环境配置或同步处理。
install_jdk_formula_or_cask() {
  local candidate="$1"

  if [[ "$candidate" == openjdk@* ]]; then
    brew install "$candidate"
  else
    brew install --cask "$candidate"
  fi
}
# 执行对应的环境配置或同步处理。
install_jdk17_if_needed() {
  local version="$1"
  local candidates_csv="$2"
  local answer=""

  if has_java_version "$version"; then
    success_echo "已检测到 JDK ${version}，跳过安装"
    return 0
  fi

  warn_echo "系统未检测到 JDK ${version}"
  log "👉 直接按 [Enter]：跳过 JDK ${version} 安装"
  log "👉 输入任意字符后回车：自动安装 JDK ${version}"
  IFS= read -r answer

  if [[ -z "$answer" ]]; then
    note_echo "已跳过 JDK ${version} 自动安装"
    return 0
  fi

  if ! command -v brew >/dev/null 2>&1; then
    error_echo "未检测到 Homebrew，无法自动安装 JDK ${version}"
    return 1
  fi

  local candidate=""
  for candidate in ${(s:,:)candidates_csv}; do
    candidate="$(trim "$candidate")"
    [[ -n "$candidate" ]] || continue

    info_echo "尝试安装：$candidate"
    if install_jdk_formula_or_cask "$candidate"; then
      if has_java_version "$version"; then
        success_echo "JDK ${version} 安装完成"
      else
        warn_echo "$candidate 安装完成，但系统暂未识别到 JDK ${version}，继续后续流程"
      fi
      return 0
    fi

    warn_echo "$candidate 安装失败，继续尝试下一个"
  done

  error_echo "JDK ${version} 自动安装失败，请手动安装后再执行 source ~/.zshrc"
  return 0
}
# ---------- Scripts ----------
resolve_script_file() {
  local scripts_dir="$1"
  local script_name="$2"
  local nested_file="$scripts_dir/$script_name/$script_name"
  local flat_file="$scripts_dir/$script_name"

  if [[ -f "$nested_file" ]]; then
    print -r -- "$nested_file"
    return 0
  fi

  if [[ -f "$flat_file" ]]; then
    print -r -- "$flat_file"
    return 0
  fi

  return 1
}
# 封装 copy_script_bundle 对应的独立处理逻辑。
copy_script_bundle() {
  local source_scripts_dir="$1"
  local target_scripts_dir="$2"
  local script_name="$3"
  local source_bundle="$source_scripts_dir/$script_name"
  local source_file=""
  local target_bundle="$target_scripts_dir/$script_name"
  local target_file="$target_bundle/$script_name"

  ensure_dir "$target_scripts_dir"
  rm -rf "$target_bundle"
  ensure_dir "$target_bundle"

  if [[ -d "$source_bundle" ]]; then
    cp -R "$source_bundle/." "$target_bundle/"
  elif [[ -f "$source_bundle" ]]; then
    cp "$source_bundle" "$target_file"
  else
    error_echo "缺少脚本：$source_bundle"
    exit 1
  fi

  source_file="$(resolve_script_file "$target_scripts_dir" "$script_name")" || {
    error_echo "脚本复制失败：$script_name"
    exit 1
  }

  chmod +x "$source_file"
  success_echo "已同步脚本：$script_name"
}
# 封装 copy_all_script_bundles 对应的独立处理逻辑。
copy_all_script_bundles() {
  local source_scripts_dir="$1"
  local target_scripts_dir="$2"
  local item=""
  local script_name=""

  [[ -d "$source_scripts_dir" ]] || {
    error_echo "缺少目录：$source_scripts_dir"
    exit 1
  }

  rm -rf "$target_scripts_dir"
  ensure_dir "$target_scripts_dir"

  for item in "$source_scripts_dir"/*.command(N); do
    if [[ -d "$item" || -f "$item" ]]; then
      script_name="$(basename "$item")"
      copy_script_bundle "$source_scripts_dir" "$target_scripts_dir" "$script_name"
    fi
  done

  copy_scripts_private_libs "$source_scripts_dir" "$target_scripts_dir"
}
# 封装 copy_scripts_private_libs 对应的独立处理逻辑。
copy_scripts_private_libs() {
  local source_scripts_dir="$1"
  local target_scripts_dir="$2"
  local source_lib_dir="$source_scripts_dir/_lib"
  local target_lib_dir="$target_scripts_dir/_lib"

  if [[ -d "$source_lib_dir" ]]; then
    rm -rf "$target_lib_dir"
    cp -R "$source_lib_dir" "$target_lib_dir"
    success_echo "已同步 Scripts 私有库：$target_lib_dir"
  fi
}
# 检查当前运行条件是否满足后续流程要求。
verify_scripts_modules() {
  local scripts_dir="$1"
  local required_files=(
    entrypoints.command
    runtime_init.command
    list.command
    m5c.command
    flat.command
    trs.command
    gif.command
    install_jdk17.command
    simios.command
    pods.command
    clean.command
    clr.command
    dq.command
    df.command
    cor.command
    decode.command
    ts.command
    download.command
    code.command
    codemap.command
    to.command
    install.command
    update.command
    shell.command
    zz.command
    x.command
    save.command
    rb.command
    a.command
    b.command
    i.command
    flutter_project.command
    fixfvm.command
    check1.command
    check.command
    c.command
    d.command
    buildCheck.command
    apk.command
    ipa.command
    config.command
  )

  [[ -d "$scripts_dir" ]] || {
    error_echo "Scripts 模块目录不存在：$scripts_dir"
    exit 1
  }

  local missing=()
  local file=""
  for file in "${required_files[@]}"; do
    if ! resolve_script_file "$scripts_dir" "$file" >/dev/null 2>&1; then
      missing+=("$file")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    error_echo "Scripts 模块同步不完整：${missing[*]}"
    error_echo "当前目录：$scripts_dir"
    exit 1
  fi

  local required_libs=(
    _lib/jobs_path_lib.zsh
    _lib/jobs_session_lib.zsh
    _lib/jobs_flutter_lib.zsh
    _lib/jobs_git_network_strategy/bin/git
  )

  for file in "${required_libs[@]}"; do
    if [[ ! -f "$scripts_dir/$file" ]]; then
      missing+=("$file")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    error_echo "Scripts 私有库同步不完整：${missing[*]}"
    error_echo "当前目录：$scripts_dir"
    exit 1
  fi

  if [[ ! -x "$scripts_dir/_lib/jobs_git_network_strategy/bin/git" ]]; then
    error_echo "Git 网络策略入口不可执行：$scripts_dir/_lib/jobs_git_network_strategy/bin/git"
    exit 1
  fi

  success_echo "Scripts 模块自检通过：$scripts_dir"
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_if_command_conflict() {
  local bin_name="$1"
  local target_bin_dir="$2"
  local existing=""
  local target_path="$target_bin_dir/$bin_name"

  existing="$(command -v "$bin_name" 2>/dev/null || true)"
  if [[ -n "$existing" && "$existing" != "$target_path" ]]; then
    warn_echo "命令名可能冲突：$bin_name -> $existing"
    warn_echo "本次仍会写入：$target_path；如调用结果不符合预期，请检查 PATH 顺序或 alias / function。"
  fi
}
# 执行对应的环境配置或同步处理。
install_bin_entry() {
  local source_scripts_dir="$1"
  local target_bin_dir="$2"
  local script_name="$3"
  local bin_name="$4"
  local source_file=""

  warn_if_command_conflict "$bin_name" "$target_bin_dir"

  source_file="$(resolve_script_file "$source_scripts_dir" "$script_name")" || {
    error_echo "缺少入口脚本：$script_name"
    exit 1
  }

  copy_file_if_changed "$source_file" "$target_bin_dir/$bin_name"
  chmod +x "$target_bin_dir/$bin_name"
  success_echo "已安装命令入口：$target_bin_dir/$bin_name"
}
# 执行对应的清理操作，并保留必要的安全检查。
remove_obsolete_bin_entry() {
  local target_bin_dir="$1"
  local bin_name="$2"
  local target_path="$target_bin_dir/$bin_name"

  [[ -e "$target_path" ]] || return 0

  if [[ -f "$target_path" ]] && grep -Eq 'flutter\.command|jobs_flutter_show_readme|JOBS_MAC_ENV|jobs_dq_|dq\.command|com\.apple\.quarantine' "$target_path" 2>/dev/null; then
    rm -f "$target_path"
    note_echo "已移除旧的独立命令入口：$target_path"
    return 0
  fi

  warn_echo "检测到 $target_path，但它不像 JobsMacEnv 旧入口，已保留。"
}
# 执行对应的清理操作，并保留必要的安全检查。
remove_obsolete_script_bin_entry() {
  local source_scripts_dir="$1"
  local target_bin_dir="$2"
  local script_name="$3"
  local bin_name="$4"
  local target_path="$target_bin_dir/$bin_name"
  local source_file=""

  [[ -e "$target_path" ]] || return 0

  if ! source_file="$(resolve_script_file "$source_scripts_dir" "$script_name" 2>/dev/null)"; then
    warn_echo "检测到 $target_path，但找不到可比对的源脚本：$script_name，已保留。"
    return 0
  fi

  if [[ -f "$target_path" ]] && cmp -s "$source_file" "$target_path"; then
    rm -f "$target_path"
    note_echo "已移除旧的独立命令入口：$target_path"
    return 0
  fi

  warn_echo "检测到 $target_path，但它不是 JobsMacEnv 旧入口副本，已保留。"
}
# ---------- 交互 ----------
show_intro_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：install.command' | jobs_intro_style title
  print -r -- '核心用途：执行“install”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title

  cat <<'EOFINSTALL' | tee -a "$LOG_FILE" | jobs_intro_style auto
============================================================
🌍 JobsMacEnvVarConfig 安装 / 同步工具
============================================================

这是 install.command 内置自述，不读取外部 README.md。
作用：把当前目录里的终端环境配置、Scripts 脚本模块、快捷命令同步到本机。

------------------------------------------------------------
一、同步位置
------------------------------------------------------------

会同步到：

  ~/.JobsMacEnv/

主要内容包括：

  ~/.JobsMacEnv/zsh/
  ~/.JobsMacEnv/Scripts/
  ~/.JobsMacEnv/sync_env.txt
  ~/.JobsMacEnv/README.md
  ~/.JobsMacEnv/install.command

快捷命令会安装到：

  ~/.local/bin/

------------------------------------------------------------
二、核心命令
------------------------------------------------------------

大部分终端可输入的自定义命令会安装到 ~/.local/bin，
并同步到 ~/.JobsMacEnv/Scripts/<命令>.command/<命令>.command。

例外：
  - flutter_project.command 保持原版位置，只由 list 菜单按需加载；不会生成 ~/.local/bin/flutter，避免覆盖系统 Flutter。
  - install_jdk17.command 保持原版脚本位置；不会生成 ~/.local/bin/jdk17。

可执行：

  list

查看完整菜单。list 自己不在菜单中显示；脚本功能和可输入命令都会按“功能入口”展示。

说明：
  list 是总入口，用 fzf 展示菜单。
  clean / cor / decode / ts / download / install / update / shell 等均已独立成 command。
  to / mp4 / mov / webm / mp3 等复用 to.command，用于 FFmpeg 媒体格式转换。
  code 用于注册 VS Code 命令行入口，支持在终端执行 code .

------------------------------------------------------------
三、交互规则
------------------------------------------------------------

普通安装 / 更新 / 升级步骤：

  直接按 Enter              跳过
  输入任意字符后回车        执行

危险操作：

  必须输入 YES 才执行

不会用普通回车触发危险操作。

------------------------------------------------------------
四、Homebrew
------------------------------------------------------------

脚本会检查 Homebrew。

未安装：
  自动安装 Homebrew
  自动写入 shellenv
  当前终端立即生效

已安装：
  直接按 Enter              跳过 Homebrew 更新
  输入任意字符后回车        执行 brew update / upgrade / cleanup / doctor

------------------------------------------------------------
五、JDK 17
------------------------------------------------------------

脚本会检查 JDK 17。

如果不存在，会询问是否通过 Homebrew 自动安装：

  直接按 Enter              跳过安装
  输入任意字符后回车        自动安装

------------------------------------------------------------
六、Scripts 结构
------------------------------------------------------------

Scripts 目录采用脚本独立文件夹结构：

  Scripts/
    xxx.command/
      xxx.command
      README.md

安装时会同步整个脚本文件夹，并保留每个脚本自己的 README.md。
内部复用逻辑放在 Scripts/_lib/ 私有库中，不作为终端命令展示。

------------------------------------------------------------
七、功能菜单
------------------------------------------------------------

安装完成后，输入：

  list

即可打开功能菜单。

list 会检查：

  brew 是否可用
  fzf 是否可用
  fzf 是否需要安装

fzf 来源 Homebrew。

------------------------------------------------------------
八、zshrc
------------------------------------------------------------

脚本会生成轻量入口文件：

  ~/.JobsMacEnv/.zshrc

之后会询问是否替换：

  ~/.zshrc

规则：

  直接按 Enter              跳过替换
  输入 YES 后回车           备份并替换 ~/.zshrc

------------------------------------------------------------
九、流程
------------------------------------------------------------

  启动 install.command
        ↓
  显示本内置自述并等待回车
        ↓
  解析 sync_env.txt
        ↓
  检查 Homebrew
        ↓
  检查 JDK 17
        ↓
  同步 ~/.JobsMacEnv
        ↓
  同步 zsh 配置
        ↓
  同步 Scripts 脚本模块
        ↓
  安装全部自定义命令入口
        ↓
  询问是否替换 ~/.zshrc
        ↓
  完成

============================================================
EOFINSTALL

  log "" | jobs_intro_style body
  warm_echo "按回车继续安装 / 同步..." | jobs_intro_style body
  local _answer=""
  IFS= read -r _answer
}
# 收集并校验用户输入，决定后续执行路径。
prompt_replace_system_zshrc() {
  local generated_zshrc="$1"
  local system_zshrc="$HOME/.zshrc"
  local answer=""

  log ""
  warn_echo "是否替换系统当前 ~/.zshrc？"
  log "👉 直接按 [Enter]：跳过替换"
  log "👉 输入 YES 后回车：备份并替换 ~/.zshrc"
  IFS= read -r answer

  if [[ "$answer" != "YES" ]]; then
    note_echo "已跳过替换系统 .zshrc"
    return 0
  fi

  if [[ -f "$system_zshrc" ]]; then
    local backup="$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
    cp "$system_zshrc" "$backup"
    success_echo "已备份当前 .zshrc：$backup"
  fi

  cp "$generated_zshrc" "$system_zshrc"
  success_echo "已替换系统 .zshrc：$system_zshrc"
}
# ---------- 主流程 ----------
# 初始化安装流程共用路径，避免在各职责函数之间重复传递长参数列表。
prepare_install_paths() {
  if [[ -f "${SCRIPT_DIR}/../sync_env.txt" ]]; then
    source_dir="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
  else
    source_dir="$SCRIPT_DIR"
  fi
  target_root="$HOME/.JobsMacEnv"
  target_zsh_dir="$target_root/zsh"
  target_custom_dir="$target_zsh_dir/custom"
  target_scripts_dir="$target_root/Scripts"
  target_bin_dir="$HOME/.local/bin"
  old_target_scripts_dir="$target_root/scripts"
  sync_file="$source_dir/sync_env.txt"
  target_sync_file="$target_root/sync_env.txt"
  target_readme="$target_root/README.md"
  target_install="$target_root/install.command"
  target_zshrc_template="$target_root/.zshrc"
  target_env="$target_zsh_dir/env.zsh"
  target_aliases="$target_zsh_dir/aliases.zsh"
  source_zshrc="$source_dir/Sys/.zshrc"
  source_scripts_dir="$source_dir/Scripts"
}
# 兼容旧仓库布局，在 Sys 目录缺少模板时回退读取根目录 .zshrc。
resolve_source_zshrc() {
  if [[ ! -f "$source_zshrc" && -f "$source_dir/.zshrc" ]]; then
    source_zshrc="$source_dir/.zshrc"
  fi
}
# 校验同步所需源文件，避免安装进行到一半才因缺少输入而退出。
validate_install_sources() {
  [[ -f "$sync_file" ]] || { error_echo "缺少 sync_env.txt"; exit 1; }
  [[ -f "$source_zshrc" ]] || { error_echo "缺少文件：$source_zshrc"; exit 1; }
}
# 解析配置并准备 Homebrew 与 JDK 基础环境。
prepare_install_dependencies() {
  parse_sync_file "$sync_file"
  install_homebrew
  install_jdk17_if_needed "$JAVA_VERSION" "$JAVA_CANDIDATES"
}
# 创建目标目录并清理已经废弃的小写 scripts 目录。
prepare_target_directories() {
  highlight_echo "开始同步 JobsMacEnv 到：$target_root"
  ensure_dir "$target_root"
  ensure_dir "$target_zsh_dir"
  ensure_dir "$target_custom_dir"
  ensure_dir "$target_bin_dir"
  ensure_dir "$target_root/assets"
  rm -rf "$old_target_scripts_dir" 2>/dev/null || true
}
# 同步仓库入口文件以及所有独立脚本模块。
sync_core_files() {
  copy_file_if_changed "$source_zshrc" "$target_zshrc_template"
  copy_file_if_changed "$source_dir/README.md" "$target_readme"
  copy_file_if_changed "$source_dir/install.command/install.command" "$target_install"
  copy_file_if_changed "$source_dir/sync_env.txt" "$target_sync_file"
  copy_all_script_bundles "$source_scripts_dir" "$target_scripts_dir"
}
# 同步 zsh 模块，并兼容仓库中可选的自定义行为文件。
sync_zsh_modules() {
  copy_file_if_changed "$source_dir/zsh/bootstrap.zsh" "$target_zsh_dir/bootstrap.zsh"
  copy_file_if_changed "$source_dir/zsh/env_methods.zsh" "$target_zsh_dir/env_methods.zsh"
  copy_file_if_changed "$source_dir/zsh/user_mounts.zsh" "$target_zsh_dir/user_mounts.zsh"
  copy_file_if_changed "$source_dir/zsh/custom/shell_behavior.zsh" "$target_custom_dir/shell_behavior.zsh"

  if [[ -f "$source_dir/zsh/custom/git_behavior.zsh" ]]; then
    copy_file_if_changed "$source_dir/zsh/custom/git_behavior.zsh" "$target_custom_dir/git_behavior.zsh"
  fi

  if [[ -f "$source_dir/zsh/custom/path_drag_resolver.zsh" ]]; then
    copy_file_if_changed "$source_dir/zsh/custom/path_drag_resolver.zsh" "$target_custom_dir/path_drag_resolver.zsh"
  fi

  copy_file_if_changed "$source_dir/zsh/custom/local.zsh" "$target_custom_dir/local.zsh"
}
# 清理旧函数文件并生成最新的环境、别名和轻量入口配置。
generate_target_zsh_files() {
  if [[ -f "$target_custom_dir/legacy_functions.zsh" ]]; then
    rm -f "$target_custom_dir/legacy_functions.zsh"
    note_echo "已移除旧文件：$target_custom_dir/legacy_functions.zsh"
  fi

  write_file_if_changed "$target_env" "$(generate_env_content)"
  write_file_if_changed "$target_aliases" "$(generate_aliases_content)"
  write_file_if_changed "$target_zshrc_template" "$(generate_minimal_zshrc)"
  chmod +x "$target_install"
  verify_scripts_modules "$target_scripts_dir"
}
# 注册通用文件处理和开发辅助命令入口。
install_general_bin_entries() {
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" list.command list
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" m5c.command m5c
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" flat.command flat
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" trs.command trs
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" gif.command gif
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" simios.command simios
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" pods.command pods
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" clean.command clean
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" clr.command clr
  remove_obsolete_bin_entry "$target_bin_dir" dlclear
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" dq.command dq
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" df.command df

  local old_long_entry="$target_bin_dir/dequarantine"
  if [[ -f "$old_long_entry" ]] && grep -Eq 'jobs_dq_|jobs_dequarantine_|解除 macOS quarantine|com\.apple\.quarantine' "$old_long_entry" 2>/dev/null; then
    rm -f "$old_long_entry"
    note_echo "已移除旧长命令入口：$old_long_entry"
  fi

  install_bin_entry "$target_scripts_dir" "$target_bin_dir" cor.command cor
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" decode.command decode
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" ts.command ts
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" download.command download
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" code.command code
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" codemap.command codemap
}
# 注册音视频格式转换命令入口。
install_media_bin_entries() {
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command to
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command mp4
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command mov
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command webm
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command mkv
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command avi
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command m4v
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command mp3
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command m4a
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command aac
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command wav
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command flac
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command ogg
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" to.command opus
}
# 注册环境管理、构建和发布相关命令入口。
install_development_bin_entries() {
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" install.command install
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" update.command update
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" shell.command shell
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" zz.command zz
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" x.command x
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" save.command save
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" rb.command rb
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" a.command a
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" b.command b
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" i.command i
  remove_obsolete_bin_entry "$target_bin_dir" flutter
  remove_obsolete_script_bin_entry "$target_scripts_dir" "$target_bin_dir" install_jdk17.command jdk17
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" fixfvm.command fixfvm
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" check1.command check1
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" check.command check
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" c.command c
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" d.command d
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" buildCheck.command buildCheck
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" apk.command apk
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" ipa.command ipa
  install_bin_entry "$target_scripts_dir" "$target_bin_dir" config.command config
}
# 输出同步结果，并由用户决定是否替换系统 .zshrc。
finish_environment_sync() {
  success_echo "已生成轻量入口文件：$target_zshrc_template"
  success_echo "已同步 Scripts 模块目录：$target_scripts_dir"

  prompt_replace_system_zshrc "$target_zshrc_template"

  if [[ -f "$HOME/.zshrc" ]]; then
    note_echo "如需立即生效，请执行：source ~/.zshrc"
  fi

  success_echo "同步完成"
  gray_echo "日志路径：$LOG_FILE"
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  set -euo pipefail
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行 prepare_install_paths 对应的核心业务步骤。
  prepare_install_paths
  # 解析当前任务所需的路径、参数或运行上下文。
  resolve_source_zshrc
  # 检查当前环境与执行条件是否满足脚本要求。
  validate_install_sources
  # 执行 prepare_install_dependencies 对应的核心业务步骤。
  prepare_install_dependencies
  # 执行 prepare_target_directories 对应的独立业务步骤。
  prepare_target_directories
  # 执行 sync_core_files 对应的核心业务步骤。
  sync_core_files
  # 执行 sync_zsh_modules 对应的核心业务步骤。
  sync_zsh_modules
  # 执行 generate_target_zsh_files 对应的独立业务步骤。
  generate_target_zsh_files
  # 执行 install_general_bin_entries 对应的核心业务步骤。
  install_general_bin_entries
  # 执行 install_media_bin_entries 对应的核心业务步骤。
  install_media_bin_entries
  # 执行 install_development_bin_entries 对应的核心业务步骤。
  install_development_bin_entries
  # 输出脚本执行结果、摘要和日志位置。
  finish_environment_sync
}

main "$@"
