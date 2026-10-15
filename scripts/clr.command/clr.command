#!/bin/zsh
# 脚本自述：
# - 脚本名称：clr.command
# - 核心用途：执行“clr”对应的自动化任务。
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
# >>> Jobs embedded Python runtime >>>
# 输出诊断，不污染函数返回的解释器路径。
_jobs_python_note() {
  print -u2 -r -- "$*"
}
# 标识当前 zsh 进程及其子 shell，避免继承环境绕过确认。
_jobs_python_process_token() {
  print -r -- "$$:${ZSH_SUBSHELL:-0}"
}
# 只有当前可交互进程内形成的确认才允许环境写操作。
_jobs_python_has_authorization() {
  [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]] || return 1
  [[ "${parameters[_JOBS_PYTHON_CONFIRMED_PROCESS]:-}" != *export* &&
     "${_JOBS_PYTHON_CONFIRMED_PROCESS:-}" == "$(_jobs_python_process_token)" ]]
}
# 记录调用方已完成的终端确认；非交互入口只允许后续只读检查。
jobs_python_mark_confirmed() {
  emulate -L zsh
  if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]]; then
    typeset -g +x _JOBS_PYTHON_CONFIRMED_PROCESS="$(_jobs_python_process_token)"
  fi
  return 0
}
# 在业务自述之后确认本次 Homebrew 更新及 Python 环境准备。
jobs_python_confirm_prepare() {
  emulate -L zsh
  local answer=""
  _jobs_python_has_authorization && return 0
  _jobs_python_note "${1:-Python 环境预检：更新 Homebrew；Python 不满足业务版本时经确认安装或修复。}"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 || "${DRY_RUN:-0}" == 1 ]]; then
    _jobs_python_note "✖ 环境准备需要终端确认；当前未更新或安装任何环境。"
    return 1
  fi
  print -u2 -n -r -- '➤ 按回车准备环境；任意非空输入（含空格）取消：'
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消环境准备。'
    return 1
  fi
  jobs_python_mark_confirmed
}
# 对缺失依赖和已有虚拟环境修复使用统一的必需动作确认。
_jobs_python_confirm_required() {
  emulate -L zsh
  local answer=""
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $1；需要在终端确认后重试，未执行安装或修复。"
    return 1
  fi
  print -u2 -n -r -- "➤ $1；直接回车执行，任意非空输入（含空格）取消："
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消，停止当前流程。'
    return 1
  fi
}
# 校验版本参数，避免把调用参数作为公式或命令选项解释。
_jobs_python_validate_arguments() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  if [[ ! "$minimum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ||
        ( -n "$maximum" && ! "$maximum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ) ||
        ! "$formula" =~ '^python(@[0-9]+\.[0-9]+)?$' ]]; then
    _jobs_python_note "✖ Python 版本或 Homebrew 公式参数无效：$minimum / $formula / $maximum"
    return 1
  fi
  if [[ -n "$maximum" ]] && ! _jobs_python_version_less "$minimum" "$maximum"; then
    _jobs_python_note '✖ Python 最低版本必须小于排他上限。'
    return 1
  fi
}
# 以数值逐段比较版本，不依赖任何 Python 运行时。
_jobs_python_version_less() {
  emulate -L zsh
  local -a left right
  local component left_value right_value
  left=("${(@s:.:)1}")
  right=("${(@s:.:)2}")
  for component in 1 2 3; do
    left_value=$((10#${left[$component]:-0}))
    right_value=$((10#${right[$component]:-0}))
    (( left_value < right_value )) && return 0
    (( left_value > right_value )) && return 1
  done
  return 1
}
# 验证本脚本内封装的 Homebrew 接口，不读取外部函数库。
_jobs_python_load_brew_helpers() {
  emulate -L zsh
  local helper
  for helper in jobs_brew_find jobs_brew_choose_installation jobs_brew_install_system jobs_brew_install_user jobs_brew_activate; do
    (( $+functions[$helper] )) || { _jobs_python_note "✖ 脚本内置 Homebrew 接口缺失：$helper"; return 1; }
  done
}
# 验证解释器版本、标准库与归属，返回可机器判断的状态码。
_jobs_python_probe() {
  emulate -L zsh
  local candidate="$1" minimum="$2" maximum="$3" tree="$4" mode="$5"
  [[ -x "$candidate" ]] || return 1
  PYTHONDONTWRITEBYTECODE=1 "$candidate" -c '
import sys
def version(value):
    return tuple((list(map(int, value.split("."))) + [0, 0, 0])[:3])
actual = tuple(sys.version_info[:3])
if actual < version(sys.argv[1]):
    sys.exit(2)
if sys.argv[2] and actual >= version(sys.argv[2]):
    sys.exit(5)
try:
    import venv
    from pathlib import Path
    if actual >= (3, 11, 0):
        import tomllib
except Exception as error:
    print("Python standard library unavailable: " + str(error), file=sys.stderr)
    sys.exit(3)
try:
    target = Path(sys.argv[3]).resolve()
    executable = Path(sys.executable).resolve()
    if sys.argv[4] == "venv":
        if Path(sys.prefix).resolve() != target or sys.prefix == sys.base_prefix:
            sys.exit(4)
    else:
        executable.relative_to(target)
except (ValueError, OSError):
    sys.exit(4)
print("JOBS_PYTHON_OK|" + ".".join(map(str, actual)) + "|" + str(executable))
' "$minimum" "$maximum" "$tree" "$mode"
}
# 验证公式路径属于当前 Homebrew Cellar，再寻找该公式内的健康解释器。
_jobs_python_find_formula_python() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  local cellar_root formula_cellar formula_prefix candidate probe_result probe_code=1 version_suffix actual_formula python3_command link_target
  local -a candidates runtime_bins
  cellar_root="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar 2>/dev/null)" || return 1
  formula_cellar="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar "$formula" 2>/dev/null)" || return 1
  actual_formula="${formula_cellar:t}"
  [[ "$cellar_root" == /* && "$cellar_root" != / && "$formula_cellar" == /* &&
     "${formula_cellar:A}" == "${cellar_root:A}/$actual_formula" &&
     ( "$actual_formula" == "$formula" ||
       ( "$formula" == python && "$actual_formula" =~ '^python@[0-9]+\.[0-9]+$' ) ) ]] || {
    _jobs_python_note "✖ Homebrew 公式 Cellar 路径异常：$formula_cellar"
    return 4
  }
  formula_prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --prefix "$formula" 2>/dev/null)" || return 1
  if [[ "$formula_prefix" == /* && ! -e "$formula_prefix" && ! -L "$formula_prefix" ]]; then
    return 1
  fi
  if [[ -L "$formula_prefix" && ! -e "$formula_prefix" ]]; then
    link_target="$(/usr/bin/readlink "$formula_prefix")" || return 4
    [[ "$link_target" == /* ]] || link_target="${formula_prefix:h}/$link_target"
    if [[ "${link_target:a}" == "${formula_cellar:A}/"* ]]; then
      return 1
    fi
    _jobs_python_note "✖ 损坏的公式链接指向外部路径：$formula_prefix"
    return 4
  fi
  [[ "$formula_prefix" == /* && "${formula_prefix:A}" == "${formula_cellar:A}/"* && -d "$formula_prefix" ]] || {
    _jobs_python_note "✖ Homebrew 公式前缀不属于指定公式：$formula_prefix"
    return 4
  }
  version_suffix="${actual_formula#python@}"
  [[ "$actual_formula" != python ]] || version_suffix=3
  candidates=("$formula_prefix/libexec/bin/python3" "$formula_prefix/bin/python$version_suffix" "$formula_prefix/bin/python3")
  runtime_bins=()
  for candidate in "$formula_prefix/libexec/bin" "$formula_prefix/bin"; do
    if [[ -d "$candidate" && "${candidate:A}" == "${formula_prefix:A}/"* ]]; then
      runtime_bins+=("$candidate")
    fi
  done
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    probe_code=0
    probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "${formula_cellar:A}" runtime 2>&1)" || probe_code=$?
    if (( probe_code == 0 )) && [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
      python3_command=""
      local runtime_bin
      for runtime_bin in "${runtime_bins[@]}"; do
        if [[ -x "$runtime_bin/python3" ]]; then
          python3_command="$runtime_bin/python3"
          break
        fi
      done
      if [[ -z "$python3_command" ]] ||
         ! _jobs_python_probe "$python3_command" "$minimum" "$maximum" "${formula_cellar:A}" runtime >/dev/null 2>&1; then
        _jobs_python_note "✖ 公式缺少健康的 python3 命令入口：$formula_prefix"
        return 3
      fi
      typeset -gx JOBS_PYTHON_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_PROCESS="$(_jobs_python_process_token)"
      typeset -g +x _JOBS_PYTHON_SELECTED_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_TREE="${formula_cellar:A}"
      export PATH="${(j.:.)runtime_bins}:$PATH"
      rehash
      _jobs_python_note "✔ 复用 Homebrew Python：$candidate（${${probe_result#*|}%%|*}）"
      return 0
    fi
    (( probe_code != 0 )) || probe_code=1
    [[ "$probe_code" != 2 && "$probe_code" != 5 ]] || break
  done
  return "$probe_code"
}
# 在当前进程一次更新 Homebrew；失败不进入 Python 安装或业务。
_jobs_python_update_brew_once() {
  emulate -L zsh
  local brew_key="${JOBS_HOMEBREW_BIN:A}" token="$(_jobs_python_process_token)"
  _jobs_python_has_authorization || return 1
  if [[ "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" != association* ||
        "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" == *export* ]]; then
    unset _JOBS_PYTHON_UPDATED_BREWS
    typeset -gA +x _JOBS_PYTHON_UPDATED_BREWS
  fi
  [[ "${_JOBS_PYTHON_UPDATED_BREWS[$brew_key]:-}" != "$token" ]] || return 0
  _jobs_python_note "ℹ 更新 Homebrew 本体及公式索引：$JOBS_HOMEBREW_BIN update"
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" update; then
    _jobs_python_note '✖ Homebrew 更新失败，停止 Python 准备；未升级其它公式。'
    return 1
  fi
  jobs_brew_activate || { _jobs_python_note '✖ Homebrew 更新后激活或健康复检失败。'; return 1; }
  _JOBS_PYTHON_UPDATED_BREWS[$brew_key]="$token"
}
# 全新 Mac 缺少 CLT 时只请求系统安装一次，完成对话框后由用户重新运行。
_jobs_python_require_clt_for_install() {
  emulate -L zsh
  local developer_directory git_command token="$(_jobs_python_process_token)"
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || return 0
  developer_directory="$(/usr/bin/xcode-select -p 2>/dev/null)" || developer_directory=""
  git_command="$(command -v git 2>/dev/null)"
  if [[ -n "$developer_directory" && -d "$developer_directory" && -n "$git_command" ]] &&
     "$git_command" --version >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${parameters[_JOBS_PYTHON_CLT_REQUESTED_PROCESS]:-}" != *export* &&
        "${_JOBS_PYTHON_CLT_REQUESTED_PROCESS:-}" == "$token" ]]; then
    _jobs_python_note '✖ 已请求 Command Line Tools 安装；请完成系统对话框后重新运行脚本。'
    return 1
  fi
  _jobs_python_confirm_required '缺少可用 Git / Command Line Tools，将打开 Apple 系统安装对话框' || return 1
  typeset -g +x _JOBS_PYTHON_CLT_REQUESTED_PROCESS="$token"
  if ! /usr/bin/xcode-select --install; then
    _jobs_python_note '✖ 无法发起 Command Line Tools 安装；请先在系统中安装或修复开发者工具。'
    return 1
  fi
  _jobs_python_note 'ℹ 已请求系统安装；请完成 Command Line Tools 对话框后重新运行，本次不继续安装 Homebrew。'
  return 1
}
# 准备必经的 Homebrew 通道，缺失时复用内置安装路径选择。
_jobs_python_prepare_brew() {
  emulate -L zsh
  local installed=""
  _jobs_python_load_brew_helpers || return 1
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    if ! _jobs_python_has_authorization; then
      _jobs_python_note '✖ 缺少健康 Homebrew；请在终端确认环境准备，未执行安装。'
      return 1
    fi
    _jobs_python_require_clt_for_install || return 1
    jobs_brew_choose_installation || return 1
    case "${JOBS_HOMEBREW_INSTALL_MODE:-}" in
      system) jobs_brew_install_system || return 1 ;;
      user) jobs_brew_install_user || return 1 ;;
      *) _jobs_python_note '✖ Homebrew 安装路径选择无效，停止。'; return 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || { _jobs_python_note '✖ Homebrew 激活或健康检查失败。'; return 1; }
  if _jobs_python_has_authorization; then
    _jobs_python_update_brew_once || return 1
  else
    _jobs_python_note 'ℹ 当前未获得终端确认，仅只读检查已有 Homebrew / Python，不更新或安装。'
  fi
}
# 更新 Homebrew 后只处理业务指定的 Python 公式，并立即复检。
jobs_python_ensure() {
  emulate -L zsh
  local minimum="${1:-}" formula="${2:-python@3.13}" maximum="${3:-}"
  local probe_code=0 action=install installed_versions=""
  unset JOBS_PYTHON_BIN
  _jobs_python_validate_arguments "$minimum" "$formula" "$maximum" || return 1
  _jobs_python_prepare_brew || return 1
  _jobs_python_find_formula_python "$minimum" "$formula" "$maximum" || probe_code=$?
  (( probe_code != 0 )) || return 0
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $formula 不满足 Python $minimum${maximum:+ 至小于 $maximum}；无交互确认，停止。"
    return 1
  fi
  if (( probe_code == 4 )); then
    _jobs_python_note '✖ Python 或公式路径归属异常，停止；不覆盖外部解释器。'
    return 1
  fi
  if (( probe_code == 5 )); then
    _jobs_python_note "✖ $formula 的 Python 版本高于业务允许范围（须小于 $maximum）；停止，不尝试无效升级。"
    return 1
  fi
  installed_versions="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" list --versions "$formula" 2>/dev/null)" || installed_versions=""
  if [[ -n "$installed_versions" ]]; then
    action=reinstall
    (( probe_code != 2 )) || action=upgrade
  fi
  _jobs_python_confirm_required "必需的 $formula 未就绪，执行 brew $action $formula" || return 1
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" "$action" "$formula"; then
    _jobs_python_note "✖ brew $action $formula 失败；停止，不重复安装。"
    return 1
  fi
  jobs_brew_activate || return 1
  if ! _jobs_python_find_formula_python "$minimum" "$formula" "$maximum"; then
    _jobs_python_note "✖ $formula 安装或修复后仍不满足要求；停止下游业务。"
    return 1
  fi
}
# 拒绝空目录、根目录及符号链接路径，防止虚拟环境修复涉及其它目录。
_jobs_python_validate_venv_path() {
  emulate -L zsh
  local supplied="${1:-}" absolute
  [[ -n "$supplied" ]] || { _jobs_python_note '✖ 虚拟环境路径不能为空。'; return 1; }
  absolute="${supplied:a}"
  if [[ "$absolute" == / || "$absolute" == "${HOME:a}" || "$absolute" != "${absolute:A}" ||
        -L "$absolute" || ( -e "$absolute" && ! -d "$absolute" ) ]]; then
    _jobs_python_note "✖ 虚拟环境须为独立真实目录，拒绝危险路径：$supplied"
    return 1
  fi
  if [[ -d "$absolute" && ! -f "$absolute/pyvenv.cfg" && ! -e "$absolute/bin/python" &&
        ! -L "$absolute/bin/python" && "${absolute:t}" != .venv && "${absolute:t}" != venv ]]; then
    _jobs_python_note "✖ 目录不是可识别的虚拟环境，不移动源码或用户目录：$absolute"
    return 1
  fi
  print -r -- "$absolute"
}
# 复用健康虚拟环境；旧坏环境完整改名备份后重建，不删除原目录。
jobs_python_prepare_venv() {
  emulate -L zsh
  local supplied="${1:-}" minimum="${2:-}" maximum="${3:-}" environment candidate probe_result backup suffix=0
  _jobs_python_validate_arguments "$minimum" python "${maximum:-}" || return 1
  environment="$(_jobs_python_validate_venv_path "$supplied")" || return 1
  candidate="$environment/bin/python"
  if [[ -d "$environment" ]] &&
     probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" &&
     [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✔ 复用虚拟环境：$environment"
    return 0
  fi
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ 虚拟环境缺失或不健康，需要终端确认后准备：$environment"
    return 1
  fi
  if [[ -z "${JOBS_PYTHON_BIN:-}" || ! -x "$JOBS_PYTHON_BIN" ||
        "${parameters[_JOBS_PYTHON_SELECTED_PROCESS]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_BIN]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_TREE]:-}" == *export* ||
        "${_JOBS_PYTHON_SELECTED_PROCESS:-}" != "$(_jobs_python_process_token)" ||
        "${_JOBS_PYTHON_SELECTED_BIN:-}" != "$JOBS_PYTHON_BIN" ]]; then
    _jobs_python_note '✖ 尚未选定健康 Homebrew Python，请先调用 jobs_python_ensure。'
    return 1
  fi
  if ! _jobs_python_probe "$JOBS_PYTHON_BIN" "$minimum" "$maximum" "$_JOBS_PYTHON_SELECTED_TREE" runtime >/dev/null 2>&1; then
    _jobs_python_note '✖ 已选择的 Homebrew Python 不满足虚拟环境版本要求，停止。'
    return 1
  fi
  if [[ -d "$environment" ]]; then
    _jobs_python_confirm_required "修复旧或损坏的虚拟环境 $environment（完整改名备份）" || return 1
    backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$"
    while [[ -e "$backup" || -L "$backup" ]]; do
      (( suffix += 1 ))
      backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$.$suffix"
    done
    if ! mv -- "$environment" "$backup"; then
      _jobs_python_note "✖ 原虚拟环境备份失败，停止：$environment"
      return 1
    fi
    _jobs_python_note "ℹ 原虚拟环境已完整保留：$backup"
  fi
  if ! PYTHONDONTWRITEBYTECODE=1 "$JOBS_PYTHON_BIN" -m venv "$environment"; then
    _jobs_python_note "✖ 虚拟环境创建失败，停止；备份保持原状：${backup:-无旧环境}"
    return 1
  fi
  if ! probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" ||
     [[ "$probe_result" != JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✖ 虚拟环境创建后复检失败，停止：$environment"
    return 1
  fi
  _jobs_python_note "✔ 虚拟环境已就绪：$environment"
}
# <<< Jobs embedded Python runtime <<<

# 编排本文件内嵌的环境自检，保留当前入口的确认和版本要求。
jobs_envclr_python_preflight() {
  case "${1:-interactive}" in
    confirmed) jobs_python_mark_confirmed ;;
    readonly) ;;
    *)
      if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
        jobs_python_confirm_prepare || return 1
      fi
      ;;
  esac
  jobs_python_ensure 3.11 python@3.13
}

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
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 封装 print_divider 对应的独立处理逻辑。
print_divider()  { gray_echo "------------------------------------------------------------------------"; }

# ---------- 常量 ----------
CLR_EXTENSION_ID="fglcbiaddbchgemaegkjejejikhilpon"
CLR_EXTENSION_KEY="MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3S09xpt4B73vCWFVhd2azGUia+BbB1KEVgC609S+mYzFSTNF1jlRGgw2eqnwLd/4WL5FxeDHKLjQS+lnjXvYTWohRDEyEJlHeq6VBFX0V+YLfFMsHFQu3sFeqkcMi5LteL7bscylwFUHhMUVd8yeNFQykAhRH4WV50VCymYzo7nWL83KMkkGqprFCMkDBZe8cVmjNEFuNlIjbPExd2UIk2YNI+egbwkeBbZIMa2JZ9gK7bfMeG6n5X8FnYgqiaGafd1xZFcSwKdEAY7jwSIpKW86t284MBiznmK9x8tIAzDmlDa/ynWN2sPBkeKyEsANpL3LuDkDtYSHG3lK0uzvtQIDAQAB"
CLR_DETECTED_EXTENSION_ID=""
CLR_EXTENSION_DIR="${HOME}/.JobsMacEnv/ChromeExtensions/jobs-clear-downloads"
CLR_EXTENSION_ID_FILE="${CLR_EXTENSION_DIR}/extension_id.txt"
CLR_EXTENSION_URL=""
CLR_DOWNLOADS_URL="chrome://downloads/"

# ---------- 参数状态 ----------
CLR_ASSUME_YES=0
CLR_OPEN_ONLY=0
CLR_OPEN_AFTER=0
CLR_INSTALL_EXTENSION=0
CLR_REVEAL_EXTENSION=0
CLR_FORCE_EXTENSION=0
CLR_LEGACY_UI=0
CLR_MANUAL_EXTENSION_ID=""
# ---------- 内置自述 ----------
jobs_clr_show_readme_and_wait() {
  clear 2>/dev/null || true
  cat <<'EOFREADME' | tee -a "$LOG_FILE" | jobs_intro_style auto
============================================================
clr - 清空 Chrome 下载记录
============================================================

功能：
  清空 Google Chrome 浏览器下载历史，不删除已经下载到本地的真实文件。

这版调整：
  - 不再假装坐标点击一定可靠。
  - 不再依赖直接改 Chrome History 数据库。
  - 默认改用一个极小的本地 Chrome 扩展，通过 Chrome 官方 downloads API
    清除下载历史。
  - 本地扩展 manifest 使用合法固定 key，扩展 ID 稳定，避免每次靠扫描 Chrome Profile 猜 ID。
  - 同时兼容你已经加载过的旧版扩展 ID；但不会再盲信已保存的旧 ID。
  - 每次会先校验 Chrome 当前配置里扩展是否仍处于启用状态。
  - 旧 ID、已删除 ID、已禁用 ID 会被自动忽略，避免 ERR_BLOCKED_BY_CLIENT 被误判为清理成功。
  - 第一次需要把本地扩展加载到 Chrome；以后执行 clr 就可以直接触发清理。

重要边界：
  - 只清除 Chrome 下载历史。
  - 不删除 ~/Downloads 或其它目录里的真实文件。
  - 不退出 Google Chrome。
  - 不备份 Chrome History 数据库。
  - 不关闭或替换你原来的网页；清理时只会打开一个扩展内部页面。

运行：
  clr
  clr --install-extension
  clr --open-only
  clr --yes
  clr --extension-id Chrome扩展卡片里的32位ID

说明：
  - 默认执行前会停一下确认：直接回车执行清理，输入任意字符后回车取消。
  - 第一次如果提示未安装扩展，执行 clr --install-extension，按提示加载一次。
  - 如果 Chrome 已经显示扩展装好了，但 clr 仍识别不到，可以执行：
    clr --extension-id 扩展卡片里显示的32位ID
  - 如果 Chrome 页面显示 ERR_BLOCKED_BY_CLIENT，通常代表旧 ID 已被禁用、移除或被 Chrome 屏蔽；重新执行 clr --install-extension 后按提示重新加载扩展。
  - 日志路径：/tmp/clr.log
============================================================
EOFREADME

  if [[ -t 0 && "${JOBS_MAC_ENV_SKIP_README:-}" != "1" ]]; then
    log "" | jobs_intro_style body
    warm_echo "按回车继续执行 clr..." | jobs_intro_style body
    local _answer=""
    IFS= read -r _answer
  fi
}
# 封装 jobs_clr_usage 对应的独立处理逻辑。
jobs_clr_usage() {
  cat <<'EOFUSAGE'
usage: clr [--install-extension] [--open-only] [--open] [--yes] [--legacy-ui] [--force-extension] [--extension-id ID]

选项：
  --install-extension  生成本地 Chrome 扩展，并打开 chrome://extensions/ 安装页
  --reveal-extension   在 Finder 中显示本地扩展目录
  --open-only          只在新标签页打开 chrome://downloads/，不清理
  --open               清理触发后打开 chrome://downloads/ 查看结果
  --yes, -y            跳过回车确认，适合自动化调用
  --force-extension    保留兼容参数；新版优先使用固定 ID / 自动识别 / 手动 ID
  --extension-id ID    手动指定并保存 Chrome 扩展卡片里的 32 位 ID
  --set-extension-id ID 同 --extension-id
  --legacy-ui          走旧版 UI 自动点击兜底；不推荐，只保留给临时测试
  --help, -h           显示帮助
EOFUSAGE
}
# 封装 jobs_clr_parse_args 对应的独立处理逻辑。
jobs_clr_parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --install-extension)
        CLR_INSTALL_EXTENSION=1
        ;;
      --reveal-extension)
        CLR_REVEAL_EXTENSION=1
        ;;
      --open-only)
        CLR_OPEN_ONLY=1
        ;;
      --open)
        CLR_OPEN_AFTER=1
        ;;
      --yes|-y)
        CLR_ASSUME_YES=1
        ;;
      --force-extension)
        CLR_FORCE_EXTENSION=1
        ;;
      --extension-id|--set-extension-id)
        if [[ -z "${2:-}" ]]; then
          error_echo "$1 需要跟一个 Chrome 扩展 ID。"
          return 1
        fi
        CLR_MANUAL_EXTENSION_ID="$2"
        shift
        ;;
      --legacy-ui)
        CLR_LEGACY_UI=1
        ;;
      --help|-h)
        jobs_clr_usage
        return 2
        ;;
      *)
        error_echo "未知参数：$1"
        jobs_clr_usage
        return 1
        ;;
    esac
    shift
  done

  return 0
}
# 封装 jobs_clr_confirm 对应的独立处理逻辑。
jobs_clr_confirm() {
  if (( CLR_ASSUME_YES )); then
    return 0
  fi

  echo ""
  warn_echo "确认：即将清空 Google Chrome 下载历史。"
  warm_echo "不会删除真实下载文件；不会退出 Chrome；不会备份 History 数据库；不会关闭或替换当前网页。"
  log "👉 直接按 [Enter]：继续清理"
  log "👉 输入任意字符后回车：取消"

  if [[ ! -t 0 ]]; then
    error_echo "当前不是交互式终端，未指定 --yes，已取消。"
    return 1
  fi

  local answer=""
  printf "> " | tee -a "$LOG_FILE"
  IFS= read -r answer

  if [[ -z "${answer}" ]]; then
    return 0
  fi

  warn_echo "已取消清理。"
  return 1
}
# 封装 jobs_clr_open_chrome_url_new_tab 对应的独立处理逻辑。
jobs_clr_open_chrome_url_new_tab() {
  local url="$1"
  local osa_output=""
  local osa_status=0

  osa_output="$(osascript <<EOFAPPLESCRIPT 2>&1
try
  tell application "Google Chrome"
    activate
    if not (exists window 1) then
      make new window
      set URL of active tab of front window to "${url}"
    else
      tell front window to make new tab with properties {URL:"${url}"}
    end if
  end tell
  return "OPENED_NEW_TAB"
on error errMsg number errNum
  return "OPEN_FAILED:" & errNum & ":" & errMsg
end try
EOFAPPLESCRIPT
)"
  osa_status=$?

  if (( osa_status == 0 )) && [[ "$osa_output" == "OPENED_NEW_TAB" ]]; then
    return 0
  fi

  warn_echo "AppleScript 打开失败：$osa_output"
  if open -a "Google Chrome" "$url" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}
# 封装 jobs_clr_open_downloads_page 对应的独立处理逻辑。
jobs_clr_open_downloads_page() {
  note_echo "在 Chrome 新标签页打开下载记录页：${CLR_DOWNLOADS_URL}"
  if jobs_clr_open_chrome_url_new_tab "$CLR_DOWNLOADS_URL"; then
    success_echo "已打开 ${CLR_DOWNLOADS_URL}"
    return 0
  fi

  error_echo "无法打开 Google Chrome。请确认已安装 Chrome。"
  return 1
}
# 封装 jobs_clr_write_extension_files 对应的独立处理逻辑。
jobs_clr_write_extension_files() {
  mkdir -p "$CLR_EXTENSION_DIR" || return 1

  cat > "${CLR_EXTENSION_DIR}/manifest.json" <<'EOFMANIFEST'
{
  "manifest_version": 3,
  "name": "Jobs Clear Chrome Downloads",
  "version": "1.0.3",
  "key": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3S09xpt4B73vCWFVhd2azGUia+BbB1KEVgC609S+mYzFSTNF1jlRGgw2eqnwLd/4WL5FxeDHKLjQS+lnjXvYTWohRDEyEJlHeq6VBFX0V+YLfFMsHFQu3sFeqkcMi5LteL7bscylwFUHhMUVd8yeNFQykAhRH4WV50VCymYzo7nWL83KMkkGqprFCMkDBZe8cVmjNEFuNlIjbPExd2UIk2YNI+egbwkeBbZIMa2JZ9gK7bfMeG6n5X8FnYgqiaGafd1xZFcSwKdEAY7jwSIpKW86t284MBiznmK9x8tIAzDmlDa/ynWN2sPBkeKyEsANpL3LuDkDtYSHG3lK0uzvtQIDAQAB",
  "description": "Clear Chrome download history without deleting local files.",
  "permissions": ["downloads"],
  "action": {
    "default_title": "Clear Chrome downloads"
  },
  "background": {
    "service_worker": "background.js"
  },
  "commands": {
    "clear-download-history": {
      "suggested_key": {
        "default": "Alt+Shift+C",
        "mac": "Alt+Shift+C"
      },
      "description": "Clear Chrome download history"
    }
  }
}
EOFMANIFEST

  cat > "${CLR_EXTENSION_DIR}/background.js" <<'EOFBG'
function chromeDownloadsSearch(query) {
  return new Promise((resolve, reject) => {
    # 封装 try 对应的独立处理逻辑。
    try {
      chrome.downloads.search(query, (items) => {
        const err = chrome.runtime.lastError;
        if (err) reject(new Error(err.message));
        else resolve(items || []);
      });
    } catch (error) {
      reject(error);
    }
  });
}

function chromeDownloadsErase(query) {
  return new Promise((resolve, reject) => {
    # 封装 try 对应的独立处理逻辑。
    try {
      chrome.downloads.erase(query, (ids) => {
        const err = chrome.runtime.lastError;
        if (err) reject(new Error(err.message));
        else resolve(ids || []);
      });
    } catch (error) {
      reject(error);
    }
  });
}

async function clearDownloads() {
  const before = await chromeDownloadsSearch({});
  const erasedIds = await chromeDownloadsErase({});
  const after = await chromeDownloadsSearch({});

  # 封装 return 对应的独立处理逻辑。
  return {
    ok: true,
    before: before.length,
    erased: erasedIds.length,
    after: after.length,
    erasedIds,
    time: new Date().toISOString()
  };
}

chrome.action.onClicked.addListener(async () => {
  await clearDownloads();
});

chrome.commands.onCommand.addListener(async (command) => {
  if (command === 'clear-download-history') {
    await clearDownloads();
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== 'JOBS_CLR_CLEAR_DOWNLOADS') {
    return false;
  }

  clearDownloads()
    .then((result) => sendResponse(result))
    .catch((error) => sendResponse({ ok: false, error: String(error && error.message ? error.message : error) }));

  return true;
});
EOFBG

  cat > "${CLR_EXTENSION_DIR}/clear.html" <<'EOFHTML'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>clr - Chrome 下载历史清理</title>
  <style>
    :root { color-scheme: light dark; }
    # 封装 body 对应的独立处理逻辑。
    body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; margin: 48px; line-height: 1.6; }
    .card { max-width: 760px; border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); border-radius: 16px; padding: 28px; }
    # 封装 h1 对应的独立处理逻辑。
    h1 { margin: 0 0 16px; font-size: 24px; }
    .status { font-size: 18px; font-weight: 700; }
    .muted { opacity: .72; }
    # 封装 code 对应的独立处理逻辑。
    code { padding: 2px 6px; border-radius: 6px; background: color-mix(in srgb, CanvasText 10%, transparent); }
  </style>
</head>
<body>
  <main class="card">
    <h1>clr - Chrome 下载历史清理</h1>
    <p id="status" class="status">正在清理 Chrome 下载历史...</p>
    <p id="detail" class="muted">只清除浏览器下载历史，不删除本地文件。</p>
  </main>
  <script src="clear.js"></script>
</body>
</html>
EOFHTML

  cat > "${CLR_EXTENSION_DIR}/clear.js" <<'EOFJS'
const statusEl = document.getElementById('status');
const detailEl = document.getElementById('detail');

function setResult(status, detail) {
  statusEl.textContent = status;
  detailEl.textContent = detail;
}

chrome.runtime.sendMessage({ type: 'JOBS_CLR_CLEAR_DOWNLOADS' }, (response) => {
  const err = chrome.runtime.lastError;
  if (err) {
    setResult('清理失败', err.message || String(err));
    return;
  }

  if (!response || !response.ok) {
    setResult('清理失败', response && response.error ? response.error : '未知错误');
    return;
  }

  setResult(
    'Chrome 下载历史已清理',
    `清理前 ${response.before} 条，已移除 ${response.erased} 条，清理后 ${response.after} 条。本地真实文件没有被删除。`
  );
});
EOFJS

  cat > "${CLR_EXTENSION_DIR}/README.md" <<'EOFEXTREADME'
# Jobs Clear Chrome Downloads

这是 `clr` 命令配套的本地 Chrome 扩展。

用途：调用 Chrome `downloads` API 清除浏览器下载历史，不删除本地真实文件。

安装：

1. 打开 Chrome：`chrome://extensions/`
2. 开启右上角「开发者模式」
3. 点击「加载已解压的扩展程序」
4. 选择本目录
5. 重新执行：`clr`

扩展 ID：固定为 `fglcbiaddbchgemaegkjejejikhilpon`。

如果你已经加载过旧版，Chrome 页面里可能显示旧 ID。此时可执行：

```zsh
clr --extension-id 旧版扩展卡片里显示的32位ID
```
EOFEXTREADME

  return 0
}
# 封装 jobs_clr_reveal_extension_dir 对应的独立处理逻辑。
jobs_clr_reveal_extension_dir() {
  jobs_clr_write_extension_files || return 1
  note_echo "本地扩展目录：${CLR_EXTENSION_DIR}"
  printf "%s" "$CLR_EXTENSION_DIR" | pbcopy 2>/dev/null || true
  info_echo "扩展目录路径已复制到剪贴板。"
  open -R "$CLR_EXTENSION_DIR" >/dev/null 2>&1 || true
}
# 封装 jobs_clr_install_extension_flow 对应的独立处理逻辑。
jobs_clr_install_extension_flow() {
  jobs_clr_write_extension_files || {
    error_echo "生成本地 Chrome 扩展失败。"
    return 1
  }

  rm -f "$CLR_EXTENSION_ID_FILE" 2>/dev/null || true

  print_divider
  note_echo "本地 Chrome 扩展已生成："
  log "$CLR_EXTENSION_DIR"
  printf "%s" "$CLR_EXTENSION_DIR" | pbcopy 2>/dev/null || true
  info_echo "扩展目录路径已复制到剪贴板。"

  print_divider
  warm_echo "第一次需要手动加载一次这个本地扩展："
  log "1. Chrome 会打开 chrome://extensions/。"
  log "2. 打开右上角「开发者模式」。"
  log "3. 点击「加载已解压的扩展程序」。"
  log "4. 选择这个目录：${CLR_EXTENSION_DIR}"
  log "5. 如果之前加载过旧版且仍不生效，先移除旧的 Jobs Clear Chrome Downloads，再重新加载本目录。"
  log "6. 预期新版扩展 ID：${CLR_EXTENSION_ID}"
  log "7. 加载完成后，重新执行：clr"

  open -R "$CLR_EXTENSION_DIR" >/dev/null 2>&1 || true
  jobs_clr_open_chrome_url_new_tab "chrome://extensions/" >/dev/null 2>&1 || open -a "Google Chrome" "chrome://extensions/" >/dev/null 2>&1 || true
  return 0
}
# 封装 jobs_clr_is_valid_extension_id 对应的独立处理逻辑。
jobs_clr_is_valid_extension_id() {
  local candidate="$1"
  [[ "$candidate" =~ '^[a-p]{32}$' ]]
}
# 封装 jobs_clr_save_extension_id 对应的独立处理逻辑。
jobs_clr_save_extension_id() {
  local candidate="$1"
  if ! jobs_clr_is_valid_extension_id "$candidate"; then
    return 1
  fi

  mkdir -p "$CLR_EXTENSION_DIR" || return 1
  printf "%s\n" "$candidate" > "$CLR_EXTENSION_ID_FILE" || return 1
  success_echo "已保存 clr Chrome 扩展 ID：${candidate}"
  return 0
}
# 封装 jobs_clr_lookup_extension_id_in_chrome 对应的独立处理逻辑。
jobs_clr_lookup_extension_id_in_chrome() {
  local candidate="$1"
  local chrome_root="${HOME}/Library/Application Support/Google/Chrome"

  [[ -n "$candidate" ]] || return 1
  [[ -d "$chrome_root" ]] || return 1

  if ! [[ -x "${JOBS_PYTHON_BIN:-}" ]]; then
    return 1
  fi

  "$JOBS_PYTHON_BIN" - "$chrome_root" "$candidate" <<'EOFPY' 2>/dev/null
import json
import os
import sys

root = sys.argv[1]
candidate = sys.argv[2]
rows = []

try:
    profile_names = os.listdir(root)
except Exception:
    profile_names = []

for profile in profile_names:
    profile_dir = os.path.join(root, profile)
    if not os.path.isdir(profile_dir):
        continue

    for fname in ('Preferences', 'Secure Preferences'):
        pref = os.path.join(profile_dir, fname)
        if not os.path.isfile(pref):
            continue

        try:
            with open(pref, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except Exception:
            continue

        item = data.get('extensions', {}).get('settings', {}).get(candidate)
        if not isinstance(item, dict):
            continue

        manifest = item.get('manifest') or {}
        name = str(manifest.get('name') or '')
        raw_path = str(item.get('path') or '')
        state = item.get('state', 1)
        status = 'enabled' if state == 1 or state is None else f'disabled:{state}'
        rows.append((status, profile, fname, name, raw_path))

if not rows:
    sys.exit(1)

rows.sort(key=lambda row: (0 if row[0] == 'enabled' else 1, row[1], row[2]))
print('\t'.join(rows[0]))
sys.exit(0 if rows[0][0] == 'enabled' else 2)
EOFPY
}
# 封装 jobs_clr_read_saved_extension_id 对应的独立处理逻辑。
jobs_clr_read_saved_extension_id() {
  [[ -f "$CLR_EXTENSION_ID_FILE" ]] || return 1

  local candidate=""
  candidate="$(tr -d '[:space:]' < "$CLR_EXTENSION_ID_FILE" 2>/dev/null || true)"
  if ! jobs_clr_is_valid_extension_id "$candidate"; then
    warn_echo "已保存的扩展 ID 不合法，忽略：${candidate}"
    rm -f "$CLR_EXTENSION_ID_FILE" 2>/dev/null || true
    return 1
  fi

  local lookup=""
  lookup="$(jobs_clr_lookup_extension_id_in_chrome "$candidate" || true)"
  if [[ -z "$lookup" ]]; then
    warn_echo "已保存的 clr Chrome 扩展 ID 已失效，Chrome 当前配置里找不到：${candidate}"
    warm_echo "将自动忽略这个旧 ID，并重新检测已启用的扩展。"
    rm -f "$CLR_EXTENSION_ID_FILE" 2>/dev/null || true
    return 1
  fi

  local ext_status=""
  local profile=""
  local source_file=""
  ext_status="$(print -r -- "$lookup" | awk -F'\t' '{ print $1 }')"
  profile="$(print -r -- "$lookup" | awk -F'\t' '{ print $2 }')"
  source_file="$(print -r -- "$lookup" | awk -F'\t' '{ print $3 }')"

  if [[ "$ext_status" == "enabled" ]]; then
    CLR_DETECTED_EXTENSION_ID="$candidate"
    info_echo "使用已保存且已启用的 clr Chrome 扩展 ID：${CLR_DETECTED_EXTENSION_ID}（Profile=${profile}，来源=${source_file}）"
    return 0
  fi

  warn_echo "已保存的 clr Chrome 扩展 ID 当前不是启用状态：${candidate}，状态=${ext_status}"
  warm_echo "这通常会导致 Chrome 打开 ${candidate}/clear.html 时显示 ERR_BLOCKED_BY_CLIENT。"
  rm -f "$CLR_EXTENSION_ID_FILE" 2>/dev/null || true
  return 1
}
# 封装 jobs_clr_find_extension_id 对应的独立处理逻辑。
jobs_clr_find_extension_id() {
  if [[ -n "$CLR_MANUAL_EXTENSION_ID" ]]; then
    if ! jobs_clr_is_valid_extension_id "$CLR_MANUAL_EXTENSION_ID"; then
      error_echo "扩展 ID 格式不对：${CLR_MANUAL_EXTENSION_ID}"
      warm_echo "Chrome 扩展 ID 应该是 32 个 a-p 之间的小写字母。"
      return 1
    fi

    CLR_DETECTED_EXTENSION_ID="$CLR_MANUAL_EXTENSION_ID"
    jobs_clr_save_extension_id "$CLR_DETECTED_EXTENSION_ID" || true
    return 0
  fi

  if jobs_clr_read_saved_extension_id; then
    return 0
  fi

  local chrome_root="${HOME}/Library/Application Support/Google/Chrome"
  [[ -d "$chrome_root" ]] || return 1

  if ! [[ -x "${JOBS_PYTHON_BIN:-}" ]]; then
    warn_echo "未找到 python3，无法自动识别 Chrome 扩展 ID。"
    return 1
  fi

  local result=""
  result="$("$JOBS_PYTHON_BIN" - "$chrome_root" "$CLR_EXTENSION_DIR" "$CLR_EXTENSION_ID" <<'EOFPY' 2>/dev/null
import json
import os
import sys

root = sys.argv[1]
ext_dir = os.path.realpath(os.path.expanduser(sys.argv[2]))
fixed_id = sys.argv[3]
target_name = 'Jobs Clear Chrome Downloads'
rows = []
seen = set()

try:
    profile_names = os.listdir(root)
except Exception:
    profile_names = []

for profile in profile_names:
    profile_dir = os.path.join(root, profile)
    if not os.path.isdir(profile_dir):
        continue

    for fname in ('Preferences', 'Secure Preferences'):
        pref = os.path.join(profile_dir, fname)
        if not os.path.isfile(pref):
            continue

        try:
            with open(pref, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except Exception:
            continue

        settings = data.get('extensions', {}).get('settings', {})
        if not isinstance(settings, dict):
            continue

        for ext_id, item in settings.items():
            if not isinstance(item, dict) or not isinstance(ext_id, str):
                continue

            manifest = item.get('manifest') or {}
            name = manifest.get('name') or ''
            raw_path = item.get('path') or ''
            item_path = os.path.realpath(os.path.expanduser(raw_path)) if raw_path else ''
            state = item.get('state', 1)

            matched = False
            if ext_id == fixed_id:
                matched = True
            if item_path and item_path == ext_dir:
                matched = True
            if item_path and item_path.endswith('/jobs-clear-downloads'):
                matched = True
            if name == target_name:
                matched = True

            if not matched:
                continue

            status = 'enabled' if state == 1 or state is None else f'disabled:{state}'
            key = (ext_id, profile, status, item_path, fname)
            if key in seen:
                continue
            seen.add(key)
            rows.append(key)

# 固定 ID 优先，其次启用状态，其次任意匹配。
def rank(row):
    ext_id, profile, status, item_path, fname = row
    return (
        0 if ext_id == fixed_id else 1,
        0 if status == 'enabled' else 1,
        0 if fname == 'Preferences' else 1,
        profile,
    )

for row in sorted(rows, key=rank):
    print('\t'.join(row))
EOFPY
)"

  local first_enabled=""
  first_enabled="$(print -r -- "$result" | awk -F'\t' '$3 == "enabled" { print; exit }')"
  if [[ -n "$first_enabled" ]]; then
    CLR_DETECTED_EXTENSION_ID="${first_enabled%%$'\t'*}"
    local profile=""
    local source_file=""
    profile="$(print -r -- "$first_enabled" | awk -F'\t' '{ print $2 }')"
    source_file="$(print -r -- "$first_enabled" | awk -F'\t' '{ print $5 }')"
    info_echo "已检测到 clr Chrome 扩展：Profile=${profile}，ID=${CLR_DETECTED_EXTENSION_ID}，来源=${source_file}"
    jobs_clr_save_extension_id "$CLR_DETECTED_EXTENSION_ID" || true
    return 0
  fi

  local first_match=""
  first_match="$(print -r -- "$result" | head -n 1)"
  if [[ -n "$first_match" ]]; then
    local profile=""
    local state_text=""
    profile="$(print -r -- "$first_match" | awk -F'\t' '{ print $2 }')"
    state_text="$(print -r -- "$first_match" | awk -F'\t' '{ print $3 }')"
    warn_echo "检测到 clr Chrome 扩展，但它未启用：Profile=${profile}，状态=${state_text}"
    warm_echo "请到 chrome://extensions/ 打开该扩展右下角开关，然后重新执行：clr"
    return 1
  fi

  warn_echo "未在 Chrome 当前配置中检测到已启用的 clr 本地扩展。"
  warm_echo "不会再盲目打开固定扩展 ID，避免出现 ERR_BLOCKED_BY_CLIENT 却被脚本误判为成功。"
  warm_echo "请执行：clr --install-extension，并确认 Chrome 扩展页里的 Jobs Clear Chrome Downloads 已启用。"
  return 1
}
# 封装 jobs_clr_extension_installed 对应的独立处理逻辑。
jobs_clr_extension_installed() {
  if jobs_clr_find_extension_id; then
    return 0
  fi

  if (( CLR_FORCE_EXTENSION )); then
    warn_echo "--force-extension 已保留兼容；当前仍会按固定 ID / 保存 ID / 自动识别 ID 执行。"
  fi

  return 1
}
# 封装 jobs_clr_clear_by_extension 对应的独立处理逻辑。
jobs_clr_clear_by_extension() {
  jobs_clr_write_extension_files || return 1

  if ! jobs_clr_extension_installed; then
    warn_echo "未检测到 clr 本地 Chrome 扩展。"
    warm_echo "原因：Chrome 没有给普通命令行提供稳定的“清空下载历史”接口；之前的坐标点击和数据库清理都不可靠。"
    jobs_clr_install_extension_flow
    return 2
  fi

  local extension_url="chrome-extension://${CLR_DETECTED_EXTENSION_ID}/clear.html"
  note_echo "通过本地 Chrome 扩展触发下载历史清理。"
  info_echo "扩展清理页：${extension_url}"

  if jobs_clr_open_chrome_url_new_tab "$extension_url"; then
    success_echo "已打开扩展清理页。页面会显示清理前后数量。"
    return 0
  fi

  error_echo "无法打开扩展清理页。"
  return 1
}
# 封装 jobs_clr_legacy_ui_click 对应的独立处理逻辑。
jobs_clr_legacy_ui_click() {
  warn_echo "正在执行旧版 UI 自动点击兜底。这个方式不保证成功。"

  local osa_output=""
  osa_output="$(osascript <<'EOFAPPLESCRIPT' 2>&1
try
  tell application "Google Chrome"
    activate
    if not (exists window 1) then
      make new window
      set URL of active tab of front window to "chrome://downloads/"
    else
      tell front window to make new tab with properties {URL:"chrome://downloads/"}
    end if
  end tell
  delay 1.2

  tell application "System Events"
    tell process "Google Chrome"
      set frontmost to true
      delay 0.2
      key code 48
      delay 0.2
      key code 49
      delay 0.5
    end tell
  end tell
  return "LEGACY_KEYBOARD_DONE"
on error errMsg number errNum
  return "LEGACY_FAILED:" & errNum & ":" & errMsg
end try
EOFAPPLESCRIPT
)"

  if [[ "$osa_output" == "LEGACY_KEYBOARD_DONE" ]]; then
    success_echo "旧版 UI 键盘触发已执行。请查看下载页是否清空。"
    return 0
  fi

  warn_echo "旧版 UI 触发失败：$osa_output"
  return 1
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
jobs_clr_main() {
  # 初始化当前流程后续步骤需要使用的变量。
  local parse_status=0
  # 执行当前流程中的独立业务步骤：jobs_clr_parse_args。
  jobs_clr_parse_args "$@"
  # 初始化当前流程后续步骤需要使用的变量。
  parse_status=$?

  # 根据当前条件选择对应的执行分支。
  if (( parse_status == 2 )); then
    # 执行当前流程中的独立业务步骤：return。
    return 0
  fi

  # 根据当前条件选择对应的执行分支。
  if (( parse_status != 0 )); then
    # 执行当前流程中的独立业务步骤：return。
    return "$parse_status"
  fi

  # 展示脚本说明并等待用户确认影响范围。
  jobs_clr_show_readme_and_wait || return 1
  jobs_envclr_python_preflight confirmed || return 1 # 确认后使用内嵌函数准备 Homebrew Python。

  # 根据当前条件选择对应的执行分支。
  if (( CLR_REVEAL_EXTENSION )); then
    # 执行当前流程中的独立业务步骤：jobs_clr_reveal_extension_dir。
    jobs_clr_reveal_extension_dir
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 根据当前条件选择对应的执行分支。
  if (( CLR_INSTALL_EXTENSION )); then
    # 执行安装步骤，并保留命令失败信息供后续排查。
    jobs_clr_install_extension_flow
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 根据当前条件选择对应的执行分支。
  if (( CLR_OPEN_ONLY )); then
    # 执行当前流程中的独立业务步骤：jobs_clr_open_downloads_page。
    jobs_clr_open_downloads_page
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 根据当前条件选择对应的执行分支。
  if ! jobs_clr_confirm; then
    # 执行当前流程中的独立业务步骤：return。
    return 1
  fi

  # 执行当前流程中的独立业务步骤：print_divider。
  print_divider

  # 初始化当前流程后续步骤需要使用的变量。
  local exit_code=1
  # 根据当前条件选择对应的执行分支。
  if (( CLR_LEGACY_UI )); then
    # 执行当前流程中的独立业务步骤：jobs_clr_legacy_ui_click。
    jobs_clr_legacy_ui_click
    # 初始化当前流程后续步骤需要使用的变量。
    exit_code=$?
  else
    # 执行当前流程中的独立业务步骤：jobs_clr_clear_by_extension。
    jobs_clr_clear_by_extension
    # 初始化当前流程后续步骤需要使用的变量。
    exit_code=$?
  fi

  # 根据当前条件选择对应的执行分支。
  if (( CLR_OPEN_AFTER )); then
    # 执行当前流程中的独立业务步骤：jobs_clr_open_downloads_page。
    jobs_clr_open_downloads_page
  fi

  # 执行当前流程中的独立业务步骤：print_divider。
  print_divider
  # 根据当前条件选择对应的执行分支。
  case "$exit_code" in
    # 执行当前流程中的独立业务步骤：处理当前语句。
    0)
      # 输出当前流程的完成状态、摘要和日志位置。
      success_echo "Chrome 下载历史清理动作已触发。"
      # 执行当前流程中的独立业务步骤：warm_echo。
      warm_echo "真实下载文件没有被删除。"
      ;;
    # 执行当前流程中的独立业务步骤：处理当前语句。
    2)
      # 执行当前流程中的独立业务步骤：warn_echo。
      warn_echo "第一次需要先加载本地 Chrome 扩展。加载后重新执行：clr"
      ;;
    # 执行当前流程中的独立业务步骤：处理当前语句。
    *)
      # 执行当前流程中的独立业务步骤：error_echo。
      error_echo "Chrome 下载历史未清理。请看上面的失败原因。"
      ;;
  esac

  # 执行当前流程中的独立业务步骤：gray_echo。
  gray_echo "日志路径：$LOG_FILE"
  # 执行当前流程中的独立业务步骤：return。
  return $exit_code
}
# 封装 clr 对应的独立处理逻辑。
clr() {
  emulate -L zsh
  jobs_clr_main "$@"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- "Python 环境：确认后更新 Homebrew；缺失时选择安装路径，Python 不满足要求才修复。" | jobs_intro_style body
  print -r -- '脚本名称：clr.command' | jobs_intro_style title
  print -r -- '核心用途：执行“clr”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    exit 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
}
# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  show_script_intro_and_wait # 先说明业务与环境准备范围并确认。
  jobs_clr_main "$@" # 执行 jobs_clr_main 对应的独立业务步骤。
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
