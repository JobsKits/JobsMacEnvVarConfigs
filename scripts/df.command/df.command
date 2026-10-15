#!/bin/zsh
# 脚本自述：
# - 脚本名称：df.command
# - 核心用途：执行“df”对应的自动化任务。
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


# ---------- 默认配置 ----------
JOBS_DF_EXTERNAL_PORT="${JOBS_DF_EXTERNAL_PORT:-80}"
JOBS_DF_DUFS_PORT="${JOBS_DF_DUFS_PORT:-5010}"
JOBS_DF_CADDY_BEGIN="# >>> JobsMacEnv df dufs share >>>"
JOBS_DF_CADDY_END="# <<< JobsMacEnv df dufs share <<<"
JOBS_DF_KEEP_CADDY_BLOCK="false"
JOBS_DF_WRITE_MODE="false"
JOBS_DF_AUTH=""
JOBS_DF_DOMAIN="${JOBS_DF_DOMAIN:-}"
JOBS_DF_DOMAIN_DISABLED="false"
JOBS_DF_DOMAIN_FROM_ARGS="false"
JOBS_DF_DOMAIN_DEFAULT=""
JOBS_DF_LOCAL_DOMAIN_SUFFIX="${JOBS_DF_LOCAL_DOMAIN_SUFFIX:-test}"
JOBS_DF_SKIP_LOCAL_HOSTS="false"
JOBS_DF_LOCAL_HOSTS_UPDATED="false"
JOBS_DF_HOSTS_BEGIN="# >>> JobsMacEnv df local hosts >>>"
JOBS_DF_HOSTS_END="# <<< JobsMacEnv df local hosts <<<"
JOBS_DF_ONCE="false"
JOBS_DF_SERVE_PATH=""
JOBS_DF_ASSUME_DEFAULTS="false"
JOBS_DF_ASK_PORT_RESULT=""

BREW_BIN=""
CADDY_BIN=""
DUFS_BIN=""
CADDYFILE_PATH=""
RUNNING_DUFS_PID=""
RUNNING_DUFS_LOG=""
CADDY_BLOCK_TOUCHED="false"
CLEANED_UP="false"
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
# ---------- 内置说明 ----------
jobs_df_print_builtin_readme() {
  cat <<'EOFREADME' | tee -a "$LOG_FILE" | jobs_intro_style auto

============================================================
df - dufs + Caddy 局域网目录共享
============================================================

这是 df.command 的内置自述，不读取同级 README.md。

功能：
  把一个本地目录开放给同一局域网里的其它电脑 / 手机浏览器访问。
  内部用 dufs 提供文件服务，外部用 Caddy 统一暴露入口。

结构：
  Scripts/df.command/df.command
  Scripts/df.command/README.md

运行：
  df
  df .
  df ~/Downloads
  df /Users/jobs/Documents/Github/JobsDocs

常用选项：
  df --yes
  df --rw
  df --auth 'admin:123456@/:rw'
  df --domain jobsdocs
  df --domain jobsdocs.test
  df --no-domain
  df --no-hosts
  df --external-port 8099
  df --dufs-port 5010
  df --keep-caddy

默认行为：
  - 直接输入 df，会一步一步询问要开放的本地目录。
  - 不传目录时，默认候选目录就是当前终端所在目录；路径问题直接回车即采用。
  - 默认只读，别人只能下载 / 浏览。
  - 默认 Caddy 对外端口：80，本机 / 局域网浏览器访问时不用带端口。
  - 默认 dufs 内部端口：5010，只监听 127.0.0.1。
  - 本地短域名默认使用 .test 后缀，例如 jobsdocs.test。
  - 不要使用 .cn / .com / .net / .org / .io 等公网真实后缀做局域网短域名。
  - 本机短域名 hosts 映射会由脚本自动写入 /etc/hosts。
  - 端口 80 和本机 hosts 都需要管理员权限，脚本会在需要时请求 sudo 密码。
  - 其它电脑 / 手机无法被这台 Mac 自动写 hosts；可优先使用 IP 或 Mac 的 .local 名称访问。
  - 真要让手机也用 jd.test 这种短域名，需要在路由器 / AdGuard Home / Pi-hole / dnsmasq 里做局域网 DNS 映射。
  - 成功后会明确打印：本机访问、手机访问、短域名访问、端口规则怎么用。

安全说明：
  - --rw 会允许上传 / 删除 / 编辑，必须谨慎使用。
  - --rw 如果没有配置 --auth，脚本会要求输入 YES 才继续。
  - 这个工具只建议用于局域网临时共享，不建议直接暴露公网。
  - 共享期间不要关闭当前终端；按回车会停止本次共享。
  - 默认停止共享时会移除 Caddyfile 托管块；需要保留时加 --keep-caddy。

命令冲突：
  - df 会覆盖 macOS 原生 df 的命令优先级。
  - 查看磁盘空间请用：/bin/df -h

日志路径：
  /tmp/df.log
============================================================
EOFREADME
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
jobs_df_show_readme_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：df.command' | jobs_intro_style title
  print -r -- '核心用途：执行“df”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  jobs_df_print_builtin_readme
  log "" | jobs_intro_style body
  read -r "?按回车继续执行 df；按 Ctrl+C 取消。" _
}
# 封装 jobs_df_print_usage 对应的独立处理逻辑。
jobs_df_print_usage() {
  jobs_df_print_builtin_readme
  cat <<'EOFUSAGE' | tee -a "$LOG_FILE"

高级用法：
  df /Users/jobs/Documents/Github/JobsDocs
  df --domain jobsdocs /Users/jobs/Documents/Github/JobsDocs
  df --domain jobsdocs.test /Users/jobs/Documents/Github/JobsDocs
  df --no-domain /Users/jobs/Documents/Github/JobsDocs
  df --external-port 8099 --dufs-port 5000 /Users/jobs/Documents/Github/JobsDocs
  df --rw --auth 'admin:123456@/:rw' /Users/jobs/Documents/Github/JobsDocs

选项：
  --yes                       使用默认交互项，少问问题
  --rw                        允许上传 / 删除 / 编辑。默认只读
  --readonly, --read-only      强制只读
  --auth user:pass@/:rw        透传给 dufs 的访问控制参数
  --domain <短域名或前缀>       输出并托管短域名访问，例如 jobsdocs 或 jobsdocs.test
  --no-domain                 不使用短域名，只输出 IP 访问
  --no-hosts                  不自动写入本机 /etc/hosts
  --external-port <端口>       Caddy 对局域网暴露的端口，默认 80；改成 8099 时浏览器必须带端口
  --dufs-port <端口>           dufs 本机监听端口，默认 5010
  --caddyfile <路径>           指定 Caddyfile 路径
  --keep-caddy                退出时保留 Caddyfile 托管块
  --once                      执行一次后退出，不继续询问下一个目录
  -h, --help                  显示帮助
EOFUSAGE
}
# ---------- 通用工具 ----------
jobs_df_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  print -r -- "$value"
}
# 封装 jobs_df_strip_outer_quotes 对应的独立处理逻辑。
jobs_df_strip_outer_quotes() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value%$'\n'}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  print -r -- "$value"
}
# 封装 jobs_df_decode_drag_path 对应的独立处理逻辑。
jobs_df_decode_drag_path() {
  local raw="$1"
  raw="$(jobs_df_trim "$raw")"
  raw="$(jobs_df_strip_outer_quotes "$raw")"

  # zsh 的 ${(Q)...} 可安全去掉拖入路径产生的反斜杠转义，不执行命令。
  raw="${(Q)raw}"

  case "$raw" in
    "~") raw="$HOME" ;;
    "~/"*) raw="${HOME}/${raw#~/}" ;;
  esac

  print -r -- "$raw"
}
# 封装 jobs_df_abs_dir 对应的独立处理逻辑。
jobs_df_abs_dir() {
  local target_path="$1"
  [[ -n "$target_path" ]] || return 1

  if [[ -d "$target_path" ]]; then
    (cd "$target_path" && pwd -P)
    return 0
  fi

  return 1
}
# 封装 jobs_df_ensure_dir 对应的独立处理逻辑。
jobs_df_ensure_dir() {
  local dir="$1"
  [[ -d "$dir" ]] || mkdir -p "$dir"
}
# 封装 jobs_df_is_uint 对应的独立处理逻辑。
jobs_df_is_uint() {
  local value="$1"
  [[ "$value" == <-> ]]
}
# 封装 jobs_df_is_valid_port 对应的独立处理逻辑。
jobs_df_is_valid_port() {
  local value="$1"
  jobs_df_is_uint "$value" || return 1
  (( value >= 1 && value <= 65535 ))
}
# 封装 jobs_df_port_needs_sudo 对应的独立处理逻辑。
jobs_df_port_needs_sudo() {
  local value="$1"
  jobs_df_is_uint "$value" || return 1
  (( value < 1024 ))
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
jobs_df_clean_domain() {
  local value="$1"
  value="$(jobs_df_trim "$value")"
  value="${value#http://}"
  value="${value#https://}"
  value="${value%%/*}"
  value="${value%%:*}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  print -r -- "$value"
}
# 封装 jobs_df_slugify_name 对应的独立处理逻辑。
jobs_df_slugify_name() {
  local value="$1"
  value="$(jobs_df_trim "$value")"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | perl -CSDA -pe 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  [[ -n "$value" ]] || value="share"
  print -r -- "$value"
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
jobs_df_prepare_default_domain() {
  local raw_path="$1"
  local decoded=""
  local abs_path=""
  local base_name=""
  local slug=""

  decoded="$(jobs_df_decode_drag_path "$raw_path")"
  [[ -n "$decoded" ]] || decoded="$PWD"

  if abs_path="$(jobs_df_abs_dir "$decoded" 2>/dev/null)"; then
    base_name="$(basename "$abs_path")"
  else
    base_name="$(basename "$decoded")"
  fi

  slug="$(jobs_df_slugify_name "$base_name")"
  JOBS_DF_DOMAIN_DEFAULT="${slug}.${JOBS_DF_LOCAL_DOMAIN_SUFFIX}"
}
# 封装 jobs_df_normalize_domain_input 对应的独立处理逻辑。
jobs_df_normalize_domain_input() {
  local value="$1"
  local default_domain="${2:-$JOBS_DF_DOMAIN_DEFAULT}"

  value="$(jobs_df_clean_domain "$value")"

  case "$value" in
    "")
      print -r -- "$default_domain"
      return 0
      ;;
    none|no|n|skip|off|0)
      print -r -- ""
      return 0
      ;;
  esac

  if [[ "$value" != *.* ]]; then
    value="${value}.${JOBS_DF_LOCAL_DOMAIN_SUFFIX}"
  fi

  print -r -- "$value"
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
jobs_df_is_allowed_local_domain() {
  local value="$1"
  case "$value" in
    *.${JOBS_DF_LOCAL_DOMAIN_SUFFIX}) return 0 ;;
    *) return 1 ;;
  esac
}
# 封装 jobs_df_warn_public_domain_suffix 对应的独立处理逻辑。
jobs_df_warn_public_domain_suffix() {
  local value="$1"
  err_echo "不要使用 .cn / .com / .net / .org / .io 等公网真实后缀做局域网短域名。"
  err_echo "df 默认统一使用 .${JOBS_DF_LOCAL_DOMAIN_SUFFIX}：${JOBS_DF_DOMAIN_DEFAULT}"
  err_echo "直接回车采用默认短域名；输入 none 表示不用短域名。"
  [[ -n "$value" ]] && warn_echo "已拒绝：$value"
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
jobs_df_is_valid_domain() {
  local value="$1"
  [[ -n "$value" ]] || return 1
  [[ "$value" != *" "* ]] || return 1
  [[ "$value" != *"/"* ]] || return 1
  [[ "$value" =~ "^[A-Za-z0-9.-]+$" ]] || return 1
  [[ "$value" == *.* ]] || return 1
  [[ "$value" != .* && "$value" != *. ]] || return 1
  return 0
}
# 封装 jobs_df_find_brew_bin 对应的独立处理逻辑。
jobs_df_find_brew_bin() {
  jobs_brew_find
}
# 封装 jobs_df_ask_any_to_run 对应的独立处理逻辑。
jobs_df_ask_any_to_run() {
  local message="$1"
  local answer=""
  log ""
  read -r "?${message}（直接回车跳过；输入任意字符后回车执行）：" answer
  [[ -n "$answer" ]]
}
# 封装 jobs_df_confirm_yes 对应的独立处理逻辑。
jobs_df_confirm_yes() {
  local message="$1"
  local answer=""

  log ""
  warn_echo "$message"
  err_echo "危险操作必须输入大写 YES 后回车。"
  err_echo "直接回车会继续询问；输入 YES 通过。"
  gray_echo "需要取消时请按 Ctrl+C。"

  while true; do
    answer=""
    IFS= read -r "?➤ 请输入 YES 后回车：" answer
    answer="$(printf '%s' "$answer" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [[ "$answer" == "YES" ]]; then
      return 0
    fi

    err_echo "未输入 YES，继续等待确认。"
  done
}
# 封装 jobs_df_remove_managed_hosts_to_file 对应的独立处理逻辑。
jobs_df_remove_managed_hosts_to_file() {
  local source_file="$1"
  local target_file="$2"

  awk -v begin="$JOBS_DF_HOSTS_BEGIN" -v end="$JOBS_DF_HOSTS_END" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$source_file" > "$target_file"
}
# 封装 jobs_df_write_local_hosts 对应的独立处理逻辑。
jobs_df_write_local_hosts() {
  local local_domain="$1"
  local tmp=""
  local cleaned=""
  local backup=""

  [[ -n "$local_domain" ]] || return 0

  if [[ "$JOBS_DF_SKIP_LOCAL_HOSTS" == "true" ]]; then
    warn_echo "已按 --no-hosts 跳过本机 /etc/hosts 自动写入。"
    return 0
  fi

  tmp="$(mktemp)"
  cleaned="$(mktemp)"

  if [[ -f /etc/hosts ]]; then
    jobs_df_remove_managed_hosts_to_file /etc/hosts "$cleaned"
  else
    : > "$cleaned"
  fi

  {
    cat "$cleaned"
    echo ""
    echo "$JOBS_DF_HOSTS_BEGIN"
    echo "# 由 JobsMacEnv df.command 自动维护：本机浏览器短域名访问"
    echo "127.0.0.1 ${local_domain}"
    echo "$JOBS_DF_HOSTS_END"
  } > "$tmp"

  log ""
  highlight_echo "自动写入本机 hosts：${local_domain} → 127.0.0.1"
  gray_echo "macOS 会要求输入本机管理员密码，用于修改 /etc/hosts。"

  backup="/etc/hosts.backup.jobs-df.$(date +%Y%m%d%H%M%S)"

  if ! sudo cp /etc/hosts "$backup"; then
    rm -f "$tmp" "$cleaned"
    error_echo "本机 hosts 备份失败，已跳过短域名自动写入。"
    return 1
  fi

  if ! sudo cp "$tmp" /etc/hosts; then
    rm -f "$tmp" "$cleaned"
    error_echo "本机 hosts 写入失败，短域名暂不可用；IP 访问仍可用。"
    return 1
  fi

  sudo dscacheutil -flushcache >/dev/null 2>&1 || true
  sudo killall -HUP mDNSResponder >/dev/null 2>&1 || true

  rm -f "$tmp" "$cleaned"
  JOBS_DF_LOCAL_HOSTS_UPDATED="true"

  success_echo "已写入本机 hosts：127.0.0.1 ${local_domain}"
  gray_echo "hosts 备份：$backup"
}
# 封装 jobs_df_http_self_check 对应的独立处理逻辑。
jobs_df_http_self_check() {
  local title="$1"
  local url="$2"
  local code=""
  local body_log="/tmp/df.http.selfcheck.log"
  local err_log="/tmp/df.http.selfcheck.err"

  if ! command -v curl >/dev/null 2>&1; then
    warn_echo "未检测到 curl，跳过访问自测：$url"
    return 0
  fi

  code="$(curl -sS -o "$body_log" -w "%{http_code}" --max-time 5 "$url" 2>"$err_log" || true)"

  case "$code" in
    2*|3*|401|403)
      success_echo "${title}自测通过：${url}（HTTP ${code}）"
      return 0
      ;;
    000|5*)
      warn_echo "${title}自测异常：${url}（HTTP ${code:-无响应}）"
      [[ -s "$err_log" ]] && cat "$err_log" | tee -a "$LOG_FILE"
      return 1
      ;;
    *)
      warn_echo "${title}自测返回 HTTP ${code}：${url}"
      return 0
      ;;
  esac
}
# 封装 jobs_df_run_self_checks 对应的独立处理逻辑。
jobs_df_run_self_checks() {
  local external_port="$1"
  local local_domain="$2"

  log ""
  highlight_echo "本机访问自测"
  jobs_df_http_self_check "127.0.0.1 " "$(jobs_df_url_for_host "127.0.0.1" "$external_port")" || true

  if [[ -n "$local_domain" && "$JOBS_DF_SKIP_LOCAL_HOSTS" != "true" ]]; then
    jobs_df_http_self_check "短域名 " "$(jobs_df_url_for_host "$local_domain" "$external_port")" || true
  fi
}
# 封装 jobs_df_ask_yes_no 对应的独立处理逻辑。
jobs_df_ask_yes_no() {
  local message="$1"
  local default_value="$2"
  local answer=""
  local suffix=""

  if [[ "$default_value" == "yes" ]]; then
    suffix="Y/n"
  else
    suffix="y/N"
  fi

  while true; do
    read -r "?${message}（${suffix}）：" answer
    answer="$(jobs_df_trim "$answer")"
    case "$answer" in
      "") [[ "$default_value" == "yes" ]] && return 0 || return 1 ;;
      y|Y|yes|YES|Yes) return 0 ;;
      n|N|no|NO|No) return 1 ;;
      *) warn_echo "请输入 y 或 n。" ;;
    esac
  done
}
# 封装 jobs_df_ask_port 对应的独立处理逻辑。
jobs_df_ask_port() {
  local title="$1"
  local current_value="$2"
  local input=""

  JOBS_DF_ASK_PORT_RESULT="$current_value"

  if [[ "$JOBS_DF_ASSUME_DEFAULTS" == "true" ]]; then
    return 0
  fi

  while true; do
    read -r "?👉 ${title}，直接回车使用 ${current_value}：" input
    input="$(jobs_df_trim "$input")"
    [[ -z "$input" ]] && input="$current_value"

    if jobs_df_is_valid_port "$input"; then
      JOBS_DF_ASK_PORT_RESULT="$input"
      return 0
    fi

    warn_echo "端口不合法：$input"
  done
}
# 封装 jobs_df_finalize_domain_or_fail 对应的独立处理逻辑。
jobs_df_finalize_domain_or_fail() {
  local input_value="$1"
  local normalized=""

  if [[ "$JOBS_DF_DOMAIN_DISABLED" == "true" ]]; then
    JOBS_DF_DOMAIN=""
    return 0
  fi

  [[ -n "$JOBS_DF_DOMAIN_DEFAULT" ]] || jobs_df_prepare_default_domain "$JOBS_DF_SERVE_PATH"

  normalized="$(jobs_df_normalize_domain_input "$input_value" "$JOBS_DF_DOMAIN_DEFAULT")"
  JOBS_DF_DOMAIN="$normalized"

  [[ -n "$JOBS_DF_DOMAIN" ]] || return 0

  if ! jobs_df_is_valid_domain "$JOBS_DF_DOMAIN"; then
    error_echo "短域名格式不合法：$JOBS_DF_DOMAIN"
    return 1
  fi

  if ! jobs_df_is_allowed_local_domain "$JOBS_DF_DOMAIN"; then
    jobs_df_warn_public_domain_suffix "$JOBS_DF_DOMAIN"
    return 1
  fi

  return 0
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
jobs_df_ask_domain() {
  local input=""
  local normalized=""

  [[ -n "$JOBS_DF_DOMAIN_DEFAULT" ]] || jobs_df_prepare_default_domain "$JOBS_DF_SERVE_PATH"

  if [[ "$JOBS_DF_DOMAIN_DISABLED" == "true" ]]; then
    JOBS_DF_DOMAIN=""
    return 0
  fi

  if [[ -n "$JOBS_DF_DOMAIN" ]]; then
    jobs_df_finalize_domain_or_fail "$JOBS_DF_DOMAIN"
    return $?
  fi

  if [[ "$JOBS_DF_ASSUME_DEFAULTS" == "true" ]]; then
    jobs_df_finalize_domain_or_fail ""
    return $?
  fi

  while true; do
    read -r "?👉 本地短域名；直接回车使用 ${JOBS_DF_DOMAIN_DEFAULT}；输入 none 不用域名；输入前缀会自动补 .${JOBS_DF_LOCAL_DOMAIN_SUFFIX}：" input
    normalized="$(jobs_df_normalize_domain_input "$input" "$JOBS_DF_DOMAIN_DEFAULT")"

    if [[ -z "$normalized" ]]; then
      JOBS_DF_DOMAIN=""
      return 0
    fi

    if ! jobs_df_is_valid_domain "$normalized"; then
      warn_echo "短域名格式不合法：$normalized"
      continue
    fi

    if ! jobs_df_is_allowed_local_domain "$normalized"; then
      jobs_df_warn_public_domain_suffix "$normalized"
      continue
    fi

    JOBS_DF_DOMAIN="$normalized"
    return 0
  done
}
# 封装 jobs_df_require_homebrew 对应的独立处理逻辑。
jobs_df_require_homebrew() {
  jobs_brew_install_or_exit
  BREW_BIN="$JOBS_HOMEBREW_BIN"
}
# 封装 jobs_df_resolve_bin 对应的独立处理逻辑。
jobs_df_resolve_bin() {
  local bin_name="$1"
  local resolved=""

  if resolved="$(command -v "$bin_name" 2>/dev/null)"; then
    print -r -- "$resolved"
    return 0
  fi

  if [[ -z "$BREW_BIN" ]]; then
    BREW_BIN="$(jobs_df_find_brew_bin 2>/dev/null || true)"
  fi

  if [[ -n "$BREW_BIN" ]]; then
    local brew_prefix=""
    brew_prefix="$($BREW_BIN --prefix 2>/dev/null || true)"
    if [[ -n "$brew_prefix" && -x "$brew_prefix/bin/$bin_name" ]]; then
      print -r -- "$brew_prefix/bin/$bin_name"
      return 0
    fi
  fi

  return 1
}
# 封装 jobs_df_ensure_formula 对应的独立处理逻辑。
jobs_df_ensure_formula() {
  local formula="$1"
  local bin_name="$2"

  if jobs_df_resolve_bin "$bin_name" >/dev/null 2>&1; then
    return 0
  fi

  warn_echo "未检测到命令：$bin_name"
  if ! jobs_df_ask_any_to_run "是否执行 brew install ${formula}？"; then
    error_echo "已跳过安装：$formula"
    return 1
  fi

  jobs_df_require_homebrew || return 1
  "$BREW_BIN" install "$formula" || return 1

  if ! jobs_df_resolve_bin "$bin_name" >/dev/null 2>&1; then
    error_echo "安装后仍未找到命令：$bin_name"
    return 1
  fi
}
# 封装 jobs_df_ensure_dependencies 对应的独立处理逻辑。
jobs_df_ensure_dependencies() {
  jobs_df_ensure_formula dufs dufs || return 1
  jobs_df_ensure_formula caddy caddy || return 1
  [[ -n "$BREW_BIN" ]] || BREW_BIN="$(jobs_df_find_brew_bin 2>/dev/null || true)"

  DUFS_BIN="$(jobs_df_resolve_bin dufs)"
  CADDY_BIN="$(jobs_df_resolve_bin caddy)"

  success_echo "dufs：$DUFS_BIN"
  success_echo "caddy：$CADDY_BIN"
}
# 封装 jobs_df_find_caddyfile 对应的独立处理逻辑。
jobs_df_find_caddyfile() {
  if [[ -n "$CADDYFILE_PATH" ]]; then
    print -r -- "$CADDYFILE_PATH"
    return 0
  fi

  if [[ -n "${CADDYFILE_PATH_OVERRIDE:-}" ]]; then
    print -r -- "$CADDYFILE_PATH_OVERRIDE"
    return 0
  fi

  if [[ -n "$BREW_BIN" ]]; then
    local brew_prefix=""
    brew_prefix="$($BREW_BIN --prefix 2>/dev/null || true)"
    if [[ -n "$brew_prefix" ]]; then
      print -r -- "$brew_prefix/etc/Caddyfile"
      return 0
    fi
  fi

  if [[ -d /opt/homebrew/etc ]]; then
    print -r -- "/opt/homebrew/etc/Caddyfile"
    return 0
  fi

  if [[ -d /usr/local/etc ]]; then
    print -r -- "/usr/local/etc/Caddyfile"
    return 0
  fi

  print -r -- "$HOME/.config/caddy/Caddyfile"
}
# 封装 jobs_df_remove_managed_block_to_file 对应的独立处理逻辑。
jobs_df_remove_managed_block_to_file() {
  local source_file="$1"
  local target_file="$2"

  awk -v begin="$JOBS_DF_CADDY_BEGIN" -v end="$JOBS_DF_CADDY_END" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$source_file" > "$target_file"
}
# 封装 jobs_df_write_caddyfile_block 对应的独立处理逻辑。
jobs_df_write_caddyfile_block() {
  local caddyfile="$1"
  local external_port="$2"
  local dufs_port="$3"
  local serve_path="$4"
  local local_domain="$5"
  local tmp=""
  local backup=""
  local site_address=":${external_port}"

  if [[ -n "$local_domain" ]]; then
    # 显式使用 http://，避免 Caddy 对局域网自定义域名自动启用 HTTPS。
    if [[ "$external_port" == "80" ]]; then
      site_address="http://${local_domain}, :80"
    else
      site_address="http://${local_domain}:${external_port}, :${external_port}"
    fi
  fi

  jobs_df_ensure_dir "$(dirname "$caddyfile")"
  [[ -f "$caddyfile" ]] || : > "$caddyfile"

  tmp="$(mktemp)"
  backup="${caddyfile}.backup.jobs-df.$(date +%Y%m%d%H%M%S)"
  cp "$caddyfile" "$backup"

  jobs_df_remove_managed_block_to_file "$caddyfile" "$tmp"

  {
    cat "$tmp"
    echo ""
    echo "$JOBS_DF_CADDY_BEGIN"
    echo "# 由 JobsMacEnv df.command 自动维护。"
    echo "# 当前共享目录：$serve_path"
    if [[ -n "$local_domain" ]]; then
      echo "# 本地短域名：$local_domain"
      echo "# 说明：域名解析需要在本机 / 其它电脑 hosts 或局域网 DNS 里配置。"
    fi
    echo "$site_address {"
    echo "    reverse_proxy 127.0.0.1:${dufs_port}"
    echo "}"
    echo "$JOBS_DF_CADDY_END"
  } > "$caddyfile"

  rm -f "$tmp"

  if ! "$CADDY_BIN" validate --config "$caddyfile" --adapter caddyfile >/tmp/df.caddy.validate.log 2>&1; then
    cp "$backup" "$caddyfile"
    error_echo "Caddyfile 校验失败，已恢复备份：$backup"
    cat /tmp/df.caddy.validate.log | tee -a "$LOG_FILE"
    return 1
  fi

  CADDY_BLOCK_TOUCHED="true"
  success_echo "已写入 Caddyfile：$caddyfile"
  gray_echo "Caddyfile 备份：$backup"
}
# 封装 jobs_df_remove_caddyfile_block 对应的独立处理逻辑。
jobs_df_remove_caddyfile_block() {
  local caddyfile="$1"
  local tmp=""

  [[ -f "$caddyfile" ]] || return 0
  grep -Fq "$JOBS_DF_CADDY_BEGIN" "$caddyfile" || return 0

  tmp="$(mktemp)"
  jobs_df_remove_managed_block_to_file "$caddyfile" "$tmp"
  cat "$tmp" > "$caddyfile"
  rm -f "$tmp"

  if "$CADDY_BIN" validate --config "$caddyfile" --adapter caddyfile >/tmp/df.caddy.validate.log 2>&1; then
    jobs_df_reload_caddy "$caddyfile" || true
    success_echo "已移除 Caddyfile 托管块"
  else
    warn_echo "移除 Caddyfile 托管块后校验失败，已保留当前文件，请手动检查：$caddyfile"
    cat /tmp/df.caddy.validate.log | tee -a "$LOG_FILE"
  fi
}
# 封装 jobs_df_reload_caddy 对应的独立处理逻辑。
jobs_df_reload_caddy() {
  local caddyfile="$1"
  local brew_caddyfile=""

  if jobs_df_port_needs_sudo "$JOBS_DF_EXTERNAL_PORT"; then
    log ""
    warn_echo "Caddy 对外端口 ${JOBS_DF_EXTERNAL_PORT} 是系统保留端口，需要管理员权限启动 / 重载 Caddy。"
    gray_echo "这是为了让浏览器可以输入不带端口的地址，例如：http://jd.test"

    if pgrep -x caddy >/dev/null 2>&1; then
      if sudo "$CADDY_BIN" reload --config "$caddyfile" --adapter caddyfile; then
        return 0
      fi
      warn_echo "Caddy reload 未成功，尝试重启 Caddy。"
    fi

    if [[ -n "$BREW_BIN" ]]; then
      "$BREW_BIN" services stop caddy >/dev/null 2>&1 || true
    fi

    sudo "$CADDY_BIN" stop >/dev/null 2>&1 || true
    sudo "$CADDY_BIN" start --config "$caddyfile" --adapter caddyfile
    return $?
  fi

  if [[ -n "$BREW_BIN" ]]; then
    local brew_prefix=""
    brew_prefix="$($BREW_BIN --prefix 2>/dev/null || true)"
    [[ -n "$brew_prefix" ]] && brew_caddyfile="$brew_prefix/etc/Caddyfile"
  fi

  if [[ -n "$BREW_BIN" && "$caddyfile" == "$brew_caddyfile" ]] && "$BREW_BIN" services list 2>/dev/null | grep -Eq '^caddy[[:space:]]'; then
    "$BREW_BIN" services restart caddy
    return $?
  fi

  if pgrep -x caddy >/dev/null 2>&1; then
    "$CADDY_BIN" reload --config "$caddyfile" --adapter caddyfile
    return $?
  fi

  "$CADDY_BIN" start --config "$caddyfile" --adapter caddyfile
}
# 封装 jobs_df_start_dufs 对应的独立处理逻辑。
jobs_df_start_dufs() {
  local serve_path="$1"
  local dufs_port="$2"
  local -a args

  args=("$serve_path" -b 127.0.0.1 -p "$dufs_port")

  if [[ "$JOBS_DF_WRITE_MODE" == "true" ]]; then
    args+=(-A)
  fi

  if [[ -n "$JOBS_DF_AUTH" ]]; then
    args+=(-a "$JOBS_DF_AUTH")
  fi

  RUNNING_DUFS_LOG="/tmp/df.dufs.${dufs_port}.log"
  : > "$RUNNING_DUFS_LOG"

  "$DUFS_BIN" "${args[@]}" >> "$RUNNING_DUFS_LOG" 2>&1 &
  RUNNING_DUFS_PID=$!

  sleep 1
  if ! kill -0 "$RUNNING_DUFS_PID" >/dev/null 2>&1; then
    error_echo "dufs 启动失败，请查看：$RUNNING_DUFS_LOG"
    cat "$RUNNING_DUFS_LOG" | tee -a "$LOG_FILE"
    RUNNING_DUFS_PID=""
    return 1
  fi

  success_echo "dufs 已启动：127.0.0.1:${dufs_port}"
  gray_echo "dufs 日志：$RUNNING_DUFS_LOG"
}
# 封装 jobs_df_stop_dufs 对应的独立处理逻辑。
jobs_df_stop_dufs() {
  if [[ -n "$RUNNING_DUFS_PID" ]] && kill -0 "$RUNNING_DUFS_PID" >/dev/null 2>&1; then
    kill "$RUNNING_DUFS_PID" >/dev/null 2>&1 || true
    wait "$RUNNING_DUFS_PID" 2>/dev/null || true
    success_echo "dufs 已停止"
  fi

  RUNNING_DUFS_PID=""
}
# 封装 jobs_df_lan_ips 对应的独立处理逻辑。
jobs_df_lan_ips() {
  local ip=""
  local iface=""

  for iface in en0 en1 bridge0; do
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    [[ -n "$ip" ]] && print -r -- "$ip"
  done

  if command -v ifconfig >/dev/null 2>&1; then
    ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" { print $2 }'
  fi
}
# 封装 jobs_df_primary_lan_ip 对应的独立处理逻辑。
jobs_df_primary_lan_ip() {
  jobs_df_lan_ips | sort -u | head -n 1
}
# 封装 jobs_df_macos_local_hostname 对应的独立处理逻辑。
jobs_df_macos_local_hostname() {
  local name=""

  if command -v scutil >/dev/null 2>&1; then
    name="$(scutil --get LocalHostName 2>/dev/null || true)"
  fi

  name="$(jobs_df_trim "$name")"
  [[ -n "$name" ]] || return 1
  print -r -- "${name}.local"
}
# 封装 jobs_df_url_for_host 对应的独立处理逻辑。
jobs_df_url_for_host() {
  local host="$1"
  local external_port="$2"

  if [[ "$external_port" == "80" ]]; then
    print -r -- "http://${host}"
  else
    print -r -- "http://${host}:${external_port}"
  fi
}
# 封装 jobs_df_print_urls 对应的独立处理逻辑。
jobs_df_print_urls() {
  local external_port="$1"
  local local_domain="$2"
  local ip=""
  local primary_ip=""
  local bonjour_host=""

  primary_ip="$(jobs_df_primary_lan_ip)"
  bonjour_host="$(jobs_df_macos_local_hostname 2>/dev/null || true)"

  log ""
  highlight_echo "============================================================"
  highlight_echo "访问方式汇总"
  highlight_echo "============================================================"

  highlight_echo "1）IP 访问：同 Wi-Fi 下最稳，手机也能直接用。"
  jobs_df_lan_ips | sort -u | while IFS= read -r ip; do
    [[ -n "$ip" ]] || continue
    color_echo "  $(jobs_df_url_for_host "$ip" "$external_port")"
  done

  log ""
  highlight_echo "2）同局域网免改 hosts 访问：优先试 Mac 的 Bonjour / .local 名称。"
  if [[ -n "$bonjour_host" ]]; then
    color_echo "  $(jobs_df_url_for_host "$bonjour_host" "$external_port")"
    gray_echo "手机和其它电脑在同一个 Wi-Fi 下通常可以直接访问这个地址。"
  else
    warn_echo "未读取到本机 LocalHostName，跳过 .local 地址输出。"
    gray_echo "可以在 macOS：系统设置 → 通用 → 共享 → 本地主机名 中查看。"
  fi

  if [[ -n "$local_domain" ]]; then
    log ""
    highlight_echo "3）本机浏览器自定义短域名访问：脚本已处理本机 hosts。"
    if [[ "$JOBS_DF_SKIP_LOCAL_HOSTS" == "true" ]]; then
      warn_echo "本次使用了 --no-hosts，脚本没有写入本机 /etc/hosts。"
      gray_echo "本机如需短域名访问，请手动添加：127.0.0.1 ${local_domain}"
    elif [[ "$JOBS_DF_LOCAL_HOSTS_UPDATED" == "true" ]]; then
      success_echo "本机已自动写入：127.0.0.1 ${local_domain}"
    else
      warn_echo "本机 hosts 自动写入未成功；短域名可能打不开。"
      gray_echo "本机可手动添加：127.0.0.1 ${local_domain}"
    fi
    color_echo "  $(jobs_df_url_for_host "$local_domain" "$external_port")"

    log ""
    highlight_echo "4）手机 / 其它电脑使用自定义短域名：必须配置局域网 DNS。"
    if [[ -n "$primary_ip" ]]; then
      warn_echo "这台 Mac 不能自动修改手机的 hosts，也不能自动改路由器 DNS。"
      gray_echo "如果你想让手机也访问 ${local_domain}，需要在路由器 / AdGuard Home / Pi-hole / dnsmasq 里添加："
      color_echo "  ${primary_ip} ${local_domain}"
      gray_echo "配置完成后，手机浏览器访问："
      color_echo "  $(jobs_df_url_for_host "$local_domain" "$external_port")"
    else
      warn_echo "未自动识别局域网 IP，请手动把 ${local_domain} 解析到这台 Mac 的局域网 IP。"
    fi

    log ""
    err_echo "不要使用 .cn / .com / .net / .org / .io 等公网真实后缀做局域网短域名。"
    err_echo "本工具默认统一使用 .${JOBS_DF_LOCAL_DOMAIN_SUFFIX}，例如：${JOBS_DF_DOMAIN_DEFAULT}"
  fi

  log ""
  highlight_echo "5）本机自测地址："
  color_echo "  $(jobs_df_url_for_host "127.0.0.1" "$external_port")"

  if [[ "$external_port" == "80" ]]; then
    log ""
    success_echo "当前 Caddy 对外端口是 80，浏览器地址不用带端口。"
    gray_echo "示例：http://jd.test / http://192.168.1.8 / http://${bonjour_host:-Mac本地主机名.local}"
  else
    log ""
    warn_echo "当前 Caddy 对外端口是 ${external_port}，浏览器地址必须带 :${external_port}。"
    gray_echo "只有把 Caddy 对外端口改成 80，才能输入不带端口的 http://域名/。"
  fi

  highlight_echo "============================================================"
  warn_echo "共享期间不要关闭这个终端窗口；按回车会停止本次共享。"
  gray_echo "手机打不开自定义短域名时，不要反复改 Caddy；优先用 IP 或 .local，或配置路由器 DNS。"
}
# 封装 jobs_df_interactive_config 对应的独立处理逻辑。
jobs_df_interactive_config() {
  local port_input=""
  local auth_input=""

  jobs_df_ask_port "Caddy 对外端口" "$JOBS_DF_EXTERNAL_PORT"
  JOBS_DF_EXTERNAL_PORT="$JOBS_DF_ASK_PORT_RESULT"

  jobs_df_ask_port "dufs 内部端口" "$JOBS_DF_DUFS_PORT"
  JOBS_DF_DUFS_PORT="$JOBS_DF_ASK_PORT_RESULT"

  jobs_df_ask_domain || return 1

  if [[ "$JOBS_DF_ASSUME_DEFAULTS" == "true" ]]; then
    return 0
  fi

  if jobs_df_ask_yes_no "是否允许局域网用户上传 / 删除 / 编辑文件" "no"; then
    JOBS_DF_WRITE_MODE="true"
    read -r "?👉 访问控制参数，直接回车表示不加账号密码；示例 admin:123456@/:rw：" auth_input
    auth_input="$(jobs_df_trim "$auth_input")"
    if [[ -n "$auth_input" ]]; then
      JOBS_DF_AUTH="$auth_input"
    fi
  else
    JOBS_DF_WRITE_MODE="false"
  fi

  return 0
}
# 封装 jobs_df_run_one_session 对应的独立处理逻辑。
jobs_df_run_one_session() {
  local input_path="$1"
  local decoded=""
  local serve_path=""
  local caddyfile=""
  local wait_answer=""

  JOBS_DF_LOCAL_HOSTS_UPDATED="false"

  decoded="$(jobs_df_decode_drag_path "$input_path")"
  if [[ -z "$decoded" ]]; then
    decoded="$PWD"
  fi

  [[ -n "$JOBS_DF_DOMAIN_DEFAULT" ]] || jobs_df_prepare_default_domain "$decoded"
  if [[ "$JOBS_DF_DOMAIN_DISABLED" != "true" && -z "$JOBS_DF_DOMAIN" ]]; then
    jobs_df_finalize_domain_or_fail "" || return 1
  fi

  if ! serve_path="$(jobs_df_abs_dir "$decoded")"; then
    error_echo "目录不存在或不是目录：$decoded"
    return 1
  fi

  caddyfile="$(jobs_df_find_caddyfile)"
  CADDYFILE_PATH="$caddyfile"

  highlight_echo "准备开放目录：$serve_path"
  info_echo "Caddyfile：$caddyfile"
  info_echo "Caddy 对外端口：$JOBS_DF_EXTERNAL_PORT"
  info_echo "dufs 内部端口：$JOBS_DF_DUFS_PORT"
  [[ -n "$JOBS_DF_DOMAIN" ]] && info_echo "本地短域名：$JOBS_DF_DOMAIN"
  [[ "$JOBS_DF_WRITE_MODE" == "true" ]] && warn_echo "共享模式：读写" || success_echo "共享模式：只读"

  if [[ "$JOBS_DF_WRITE_MODE" == "true" && -z "$JOBS_DF_AUTH" ]]; then
    jobs_df_confirm_yes "当前启用了读写模式，但没有配置账号密码，局域网用户将可以上传 / 删除 / 编辑文件。"
  fi

  jobs_df_start_dufs "$serve_path" "$JOBS_DF_DUFS_PORT" || return 1
  jobs_df_write_caddyfile_block "$caddyfile" "$JOBS_DF_EXTERNAL_PORT" "$JOBS_DF_DUFS_PORT" "$serve_path" "$JOBS_DF_DOMAIN" || {
    jobs_df_stop_dufs
    return 1
  }

  if ! jobs_df_reload_caddy "$caddyfile"; then
    error_echo "Caddy 启动 / 重载失败。"
    jobs_df_stop_dufs
    return 1
  fi

  if [[ "$JOBS_DF_EXTERNAL_PORT" == "80" ]]; then
    success_echo "Caddy 已接管入口：:80（浏览器不用带端口）"
  else
    success_echo "Caddy 已接管入口：:${JOBS_DF_EXTERNAL_PORT}"
  fi

  if [[ -n "$JOBS_DF_DOMAIN" ]]; then
    jobs_df_write_local_hosts "$JOBS_DF_DOMAIN" || warn_echo "短域名本机自动配置失败；IP 访问仍可使用。"
  fi

  jobs_df_run_self_checks "$JOBS_DF_EXTERNAL_PORT" "$JOBS_DF_DOMAIN"
  jobs_df_print_urls "$JOBS_DF_EXTERNAL_PORT" "$JOBS_DF_DOMAIN"
  log ""
  IFS= read -r "?👉 共享中。确认其它电脑已经能访问后，按回车停止本次共享：" wait_answer
  jobs_df_stop_dufs
}
# 封装 jobs_df_cleanup 对应的独立处理逻辑。
jobs_df_cleanup() {
  [[ "$CLEANED_UP" == "true" ]] && return 0
  CLEANED_UP="true"

  jobs_df_stop_dufs

  if [[ "$JOBS_DF_KEEP_CADDY_BLOCK" != "true" && "$CADDY_BLOCK_TOUCHED" == "true" && -n "$CADDYFILE_PATH" && -n "$CADDY_BIN" ]]; then
    jobs_df_remove_caddyfile_block "$CADDYFILE_PATH" || true
  fi

  gray_echo "日志路径：$LOG_FILE"
}
# 封装 jobs_df_interrupt 对应的独立处理逻辑。
jobs_df_interrupt() {
  jobs_df_cleanup
  exit 130
}
# 封装 jobs_df_parse_args 对应的独立处理逻辑。
jobs_df_parse_args() {
  local arg=""

  while (( $# > 0 )); do
    arg="$1"
    case "$arg" in
      -h|--help)
        jobs_df_print_usage
        exit 0
        ;;
      --yes|-y)
        JOBS_DF_ASSUME_DEFAULTS="true"
        shift
        ;;
      --rw)
        JOBS_DF_WRITE_MODE="true"
        shift
        ;;
      --readonly|--read-only)
        JOBS_DF_WRITE_MODE="false"
        shift
        ;;
      --auth)
        JOBS_DF_AUTH="${2:-}"
        shift 2
        ;;
      --domain|--host)
        JOBS_DF_DOMAIN="$(jobs_df_clean_domain "${2:-}")"
        JOBS_DF_DOMAIN_DISABLED="false"
        JOBS_DF_DOMAIN_FROM_ARGS="true"
        shift 2
        ;;
      --no-domain)
        JOBS_DF_DOMAIN=""
        JOBS_DF_DOMAIN_DISABLED="true"
        JOBS_DF_DOMAIN_FROM_ARGS="true"
        shift
        ;;
      --no-hosts)
        JOBS_DF_SKIP_LOCAL_HOSTS="true"
        shift
        ;;
      --external-port|--port)
        JOBS_DF_EXTERNAL_PORT="${2:-}"
        shift 2
        ;;
      --dufs-port)
        JOBS_DF_DUFS_PORT="${2:-}"
        shift 2
        ;;
      --caddyfile)
        CADDYFILE_PATH="${2:-}"
        shift 2
        ;;
      --keep-caddy)
        JOBS_DF_KEEP_CADDY_BLOCK="true"
        shift
        ;;
      --once)
        JOBS_DF_ONCE="true"
        shift
        ;;
      --)
        shift
        JOBS_DF_SERVE_PATH="$*"
        break
        ;;
      -* )
        error_echo "未知选项：$arg"
        jobs_df_print_usage
        exit 2
        ;;
      *)
        if [[ -z "$JOBS_DF_SERVE_PATH" ]]; then
          JOBS_DF_SERVE_PATH="$arg"
        else
          JOBS_DF_SERVE_PATH="${JOBS_DF_SERVE_PATH} $arg"
        fi
        shift
        ;;
    esac
  done

  if ! jobs_df_is_valid_port "$JOBS_DF_EXTERNAL_PORT" || ! jobs_df_is_valid_port "$JOBS_DF_DUFS_PORT"; then
    error_echo "端口不合法：Caddy=${JOBS_DF_EXTERNAL_PORT}，dufs=${JOBS_DF_DUFS_PORT}"
    exit 2
  fi

  # --domain 允许只传前缀，例如 jobsdocs；最终会自动补 .test 并在交互配置阶段校验。
}
# 封装 jobs_df_interactive_loop 对应的独立处理逻辑。
jobs_df_interactive_loop() {
  local input_path=""
  local again=""

  while true; do
    log ""
    read -r "?👉 拖入或输入要开放的本地目录；直接回车用当前目录：${PWD}；输入 q 退出：" input_path
    input_path="$(jobs_df_trim "$input_path")"

    if [[ "$input_path" == "q" || "$input_path" == "Q" || "$input_path" == "quit" || "$input_path" == "exit" ]]; then
      info_echo "已退出。"
      break
    fi

    if [[ "$JOBS_DF_DOMAIN_FROM_ARGS" != "true" ]]; then
      JOBS_DF_DOMAIN=""
    fi

    jobs_df_prepare_default_domain "$input_path"
    jobs_df_interactive_config || continue
    jobs_df_run_one_session "$input_path" || true

    if [[ "$JOBS_DF_ONCE" == "true" ]]; then
      break
    fi

    log ""
    read -r "?👉 继续开放其它目录？直接回车继续；输入 q 退出：" again
    again="$(jobs_df_trim "$again")"
    if [[ "$again" == "q" || "$again" == "Q" || "$again" == "quit" || "$again" == "exit" ]]; then
      break
    fi
  done
}
# 编排脚本的高层业务流程。
# 注册目录共享流程的退出与中断处理。
jobs_df_register_signal_handlers() {
  trap jobs_df_cleanup EXIT
  trap jobs_df_interrupt INT TERM
}
# 执行目录共享入口下沉后的完整控制流程。
jobs_df_run_business_flow() {
  # 执行当前流程中的独立业务步骤：jobs_df_parse_args。
  jobs_df_parse_args "$@"

  # 检查当前步骤所需的环境、路径或输入条件。
  jobs_df_ensure_dependencies || exit 1

  # 根据当前条件选择对应的执行分支。
  if [[ -n "$JOBS_DF_SERVE_PATH" ]]; then
    # 准备后续业务需要的配置、目录或运行上下文。
    jobs_df_prepare_default_domain "$JOBS_DF_SERVE_PATH"
    # 根据当前条件选择对应的执行分支。
    if [[ "$JOBS_DF_ASSUME_DEFAULTS" != "true" ]]; then
      # 准备后续业务需要的配置、目录或运行上下文。
      jobs_df_interactive_config || return 1
    else
      # 执行当前流程中的独立业务步骤：jobs_df_finalize_domain_or_fail。
      jobs_df_finalize_domain_or_fail "$JOBS_DF_DOMAIN" || return 1
    fi
    # 执行当前流程中的独立业务步骤：jobs_df_run_one_session。
    jobs_df_run_one_session "$JOBS_DF_SERVE_PATH"
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 执行当前流程中的独立业务步骤：jobs_df_interactive_loop。
  jobs_df_interactive_loop
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  set -o pipefail
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  jobs_df_show_readme_and_wait # 展示脚本说明并等待用户确认影响范围。
  initialize_script_runtime # 初始化 Shell 选项、日志、依赖和入口运行状态。
  jobs_df_register_signal_handlers # 注册退出和中断处理，确保异常场景仍能收尾。
  jobs_df_run_business_flow "$@" # 执行目录共享的参数解析、确认和会话流程。
}

main "$@"
