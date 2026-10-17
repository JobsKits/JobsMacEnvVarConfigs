#!/bin/zsh
# 脚本自述：
# - 脚本名称：update.command
# - 核心用途：执行“update”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


# ============================================================
# update.command - macOS 开发环境升级维护
# ============================================================
# 原则：install.command 负责安装过的内容，update.command 必须体现并提供升级 / 刷新入口。
# 说明：
# 1. 适合 .command 双击运行，也可终端执行。
# 2. 启动后先显示内置 README，并等待回车确认。
# 3. 普通升级项统一为：直接回车跳过，输入任意字符后回车执行。
# 4. 单项失败不阻断后续更新项，但会写入日志。
# 5. 不存在的工具不在 update 中静默安装，只提示回到 install.command 补装。
# ============================================================

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
jobs_envupdate_python_preflight() {
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
LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
JOBS_UPDATE_TRUST_MODE=0
JOBS_UPDATE_COCOAPODS_BREW_UPDATED=0
readonly JOBS_UPDATE_NETWORK_PROBE_URL="https://formulae.brew.sh/api/formula.jws.json"
readonly JOBS_UPDATE_NETWORK_PROBE_BYTES=1048576
readonly JOBS_UPDATE_NETWORK_PROBE_TIMEOUT_SECONDS=8
readonly JOBS_UPDATE_MAX_LOW_SPEED_LIMIT_BPS=131072
readonly JOBS_UPDATE_MIN_LOW_SPEED_LIMIT_BPS=8192
readonly JOBS_UPDATE_FINAL_LOW_SPEED_LIMIT_BPS=1024
readonly JOBS_UPDATE_LOW_SPEED_SECONDS=30
readonly JOBS_UPDATE_FINAL_LOW_SPEED_SECONDS=60
readonly JOBS_UPDATE_PROGRESS_INTERVAL_SECONDS=20
JOBS_UPDATE_NETWORK_READY=0
JOBS_UPDATE_PREFERRED_IP_FAMILY="ipv4"
JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv6"
JOBS_UPDATE_IPV4_PROBE_SPEED=0
JOBS_UPDATE_IPV6_PROBE_SPEED=0
JOBS_UPDATE_ACTIVE_LOW_SPEED_LIMIT_BPS=0
JOBS_UPDATE_ACTIVE_LOW_SPEED_SECONDS=0
JOBS_UPDATE_BREW_CURLRC=""
JOBS_UPDATE_LAST_BREW_OUTPUT_FILE=""
JOBS_UPDATE_PROGRESS_MONITOR_PID=""
JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC=""
JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET=0


# ---------- 全局配置：必须与 install.command 保持同源 ----------
readonly JOBS_SOFTWARE_REPO="https://github.com/JobsKits/JobsSoftware.MacOS.git"
readonly JOBS_ENV_REPO="https://github.com/JobsKits/JobsMacEnvVarConfig.git"
readonly JOBS_WORKSPACE="${HOME}/Desktop/JobsKits"

readonly -a BREW_CASKS=(
  hammerspoon
  flutter
  trex
  vlc
  jdownloader
  codex-app
  codex
  github-store
  jtool2
  motrix
  onlyoffice
  pot
  qlcolorcode
  temurin@17
)

readonly -a BREW_FORMULAE=(
  agg
  asciinema
  caddy
  cloudflared
  git-lfs
  gh
  nushell
  rbenv
  ruby
  node
  jenv
  openjdk
  openjdk@17
  openjdk@21
  fvm
  pnpm
  python
  python3
  python-tk@3.14
  pyinstaller
  pyside
  cocoapods
  fastlane
  mysql
  hugo
  yt-dlp
  ffmpeg
  cmake
  graphviz
  sevenzip
  go-task
  uv
  fzf
  glow
  lazygit
  dufs
  git-filter-repo
  nginx
  radare2
)
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
# ---------- 通用基础函数 ----------
print_divider() {
  gray_echo "------------------------------------------------------------------------"
}
# 封装 jobs_update_has 对应的独立处理逻辑。
jobs_update_has() {
  command -v "$1" >/dev/null 2>&1
}
# 打印 update.command 的参数说明。
jobs_update_show_usage() {
  cat <<'EOFUSAGE'
用法：
  update.command
  update.command -t

参数：
  -t, --trust, --unattended  无人值守模式：跳过脚本确认、自动执行更新项；提权命令使用 sudo -n，无授权时立即跳过，绝不等待密码。
  -h, --help                显示本说明。
EOFUSAGE
}
# 解析 update.command 的运行参数。
jobs_update_parse_args() {
  local arg=""

  for arg in "$@"; do
    case "$arg" in
      -t|--trust|--unattended)
        JOBS_UPDATE_TRUST_MODE=1
        ;;
      -h|--help)
        jobs_update_show_usage
        return 2
        ;;
      *)
        error_echo "未知参数：${arg}"
        jobs_update_show_usage
        return 1
        ;;
    esac
  done
}
# 无人值守模式禁止阻塞式密码输入，提权项由统一执行器快速判定。
jobs_update_prepare_unattended_mode() {
  if (( JOBS_UPDATE_TRUST_MODE != 1 )); then
    return 0
  fi

  echo ""
  warn_echo "已启用无人值守模式：将自动执行全部更新项，并为已知确认点自动输入 y。"
  warm_echo "需要管理员权限的命令统一使用 sudo -n；当前无免密或已缓存授权时立即跳过，绝不等待密码。"
  gray_echo "安全边界：脚本不保存、不传递管理员密码，也不自动修改 sudoers。"
}
# 封装 jobs_update_prompt_run 对应的独立处理逻辑。
jobs_update_prompt_run() {
  local title="$1"
  local detail="$2"
  local answer=""

  echo ""
  warn_echo "强提示：${title}"
  warm_echo "回车=跳过；输入任意字符后回车=执行升级 / 刷新"
  gray_echo "${detail}"

  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    note_echo "托管模式：自动执行 ${title}"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    warn_echo "当前不是交互式终端，已跳过：${title}"
    return 1
  fi

  IFS= read -r answer || return 1

  if [[ -n "$answer" ]]; then
    return 0
  fi

  note_echo "已跳过：${title}"
  return 1
}
# 封装 jobs_update_run_step 对应的独立处理逻辑。
jobs_update_run_step() {
  local title="$1"
  shift

  echo ""
  highlight_echo "$title"
  print_divider

  "$@"
  local exit_code=$?

  if (( exit_code == 0 )); then
    success_echo "$title：完成"
  else
    warn_echo "$title：返回非 0（${exit_code}），继续后续更新项"
  fi

  return 0
}
# 封装 jobs_update_run_cmd 对应的独立处理逻辑。
jobs_update_run_cmd() {
  local desc="$1"
  shift

  note_echo "$desc"
  debug_echo "执行命令：$*"

  "$@"
  local exit_code=$?

  if (( exit_code == 0 )); then
    success_echo "$desc：完成"
  else
    warn_echo "$desc：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 统一执行需要管理员权限的命令，确保无人值守时不会停在密码提示。
jobs_update_run_sudo_cmd() {
  local desc="$1"
  shift

  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    if jobs_update_run_cmd "$desc（无人值守）" sudo -n "$@"; then
      return 0
    fi

    warn_echo "无人值守模式未获得该命令的无密码授权，已跳过：${desc}"
    warm_echo "如确实需要执行，请之后在场以普通模式手动运行 update。"
    return 1
  fi

  jobs_update_run_cmd "$desc" sudo "$@"
}
# npm 全局包可能遗留为 root 所有；仅在目标不可写时进入统一提权策略。
jobs_update_run_npm_global_cmd() {
  local desc="$1"
  local package_relative_path="$2"
  local npm_root=""
  local package_path=""
  shift 2

  npm_root="$(npm root -g 2>/dev/null || true)"
  package_path="${npm_root}/${package_relative_path}"

  if [[ -n "$npm_root" ]] && { { [[ -e "$package_path" ]] && [[ ! -w "$package_path" ]]; } || { [[ ! -e "$package_path" ]] && [[ ! -w "$npm_root" ]]; }; }; then
    warn_echo "npm 全局包目录当前用户不可写：${package_path}"
    jobs_update_run_sudo_cmd "$desc" npm "$@"
    return $?
  fi

  jobs_update_run_cmd "$desc" npm "$@"
}
# 封装 jobs_update_run_sh 对应的独立处理逻辑。
jobs_update_run_sh() {
  local desc="$1"
  local cmd="$2"

  note_echo "$desc"
  debug_echo "执行命令：${cmd}"

  /bin/zsh -c "$cmd"
  local exit_code=$?

  if (( exit_code == 0 )); then
    success_echo "$desc：完成"
  else
    warn_echo "$desc：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 对已知会询问 y/n 的命令定点输入 y，避免托管模式中途卡住。
jobs_update_run_cmd_with_yes() {
  local desc="$1"
  shift

  note_echo "$desc"
  debug_echo "执行命令：printf 'y\\n' | $*"

  printf 'y\n' | "$@" 2>&1 | tee -a "$LOG_FILE"
  local exit_code=${pipestatus[2]}

  if (( exit_code == 0 )); then
    success_echo "$desc：完成"
  else
    warn_echo "$desc：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 返回指定 IP 协议对应的 curl 参数。
jobs_update_ip_family_curl_flag() {
  case "$1" in
    ipv4) print -r -- "--ipv4" ;;
    ipv6) print -r -- "--ipv6" ;;
    *) return 1 ;;
  esac
}
# 使用小流量分段下载测量指定 IP 协议的实时速度。
jobs_update_measure_ip_family_speed() {
  local family="$1"
  local family_flag=""
  local range_end=$((JOBS_UPDATE_NETWORK_PROBE_BYTES - 1))
  local speed=""

  family_flag="$(jobs_update_ip_family_curl_flag "$family")" || {
    print -r -- "0"
    return 0
  }
  speed="$(/usr/bin/curl "$family_flag" \
    --location \
    --silent \
    --fail \
    --output /dev/null \
    --range "0-${range_end}" \
    --connect-timeout 5 \
    --max-time "$JOBS_UPDATE_NETWORK_PROBE_TIMEOUT_SECONDS" \
    --write-out '%{speed_download}' \
    "$JOBS_UPDATE_NETWORK_PROBE_URL" 2>/dev/null || true)"
  speed="${speed%%.*}"
  [[ "$speed" == <-> ]] || speed=0
  print -r -- "$speed"
}
# 把字节每秒转换成便于日志阅读的 KiB/s。
jobs_update_format_download_speed() {
  local speed="${1:-0}"

  if [[ "$speed" != <-> ]] || (( speed <= 0 )); then
    print -r -- "不可用"
    return 0
  fi
  print -r -- "$((speed / 1024)) KiB/s"
}
# 返回指定 IP 协议的测速结果。
jobs_update_probe_speed_for_family() {
  case "$1" in
    ipv4) print -r -- "$JOBS_UPDATE_IPV4_PROBE_SPEED" ;;
    ipv6) print -r -- "$JOBS_UPDATE_IPV6_PROBE_SPEED" ;;
    *) print -r -- "0" ;;
  esac
}
# 按实测带宽计算低速阈值，避免慢线路被固定阈值误判为断线。
jobs_update_adaptive_low_speed_limit_for_family() {
  local speed=""
  local limit=0

  speed="$(jobs_update_probe_speed_for_family "$1")"
  [[ "$speed" == <-> ]] || speed=0
  if (( speed > 0 )); then
    limit=$((speed / 4))
  fi
  (( limit < JOBS_UPDATE_MIN_LOW_SPEED_LIMIT_BPS )) && limit=$JOBS_UPDATE_MIN_LOW_SPEED_LIMIT_BPS
  (( limit > JOBS_UPDATE_MAX_LOW_SPEED_LIMIT_BPS )) && limit=$JOBS_UPDATE_MAX_LOW_SPEED_LIMIT_BPS
  print -r -- "$limit"
}
# 写入仅供本轮 update 使用的 Homebrew curl 配置。
jobs_update_write_brew_curlrc() {
  local family="$1"
  local guard_mode="${2:-adaptive}"
  local family_option=""
  local speed_limit=0
  local speed_seconds=0

  [[ -n "$JOBS_UPDATE_BREW_CURLRC" ]] || return 1
  family_option="$(jobs_update_ip_family_curl_flag "$family")" || return 1
  case "$guard_mode" in
    adaptive)
      speed_limit="$(jobs_update_adaptive_low_speed_limit_for_family "$family")"
      speed_seconds=$JOBS_UPDATE_LOW_SPEED_SECONDS
      ;;
    final)
      speed_limit=$JOBS_UPDATE_FINAL_LOW_SPEED_LIMIT_BPS
      speed_seconds=$JOBS_UPDATE_FINAL_LOW_SPEED_SECONDS
      ;;
    *)
      return 1
      ;;
  esac
  JOBS_UPDATE_ACTIVE_LOW_SPEED_LIMIT_BPS=$speed_limit
  JOBS_UPDATE_ACTIVE_LOW_SPEED_SECONDS=$speed_seconds

  {
    if (( JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET == 1 )); then
      if [[ "$JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC" == /* && -f "$JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC" ]]; then
        print -r -- "config = \"${JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC}\""
      elif [[ -f "${HOME}/.curlrc" ]]; then
        print -r -- "config = \"${HOME}/.curlrc\""
      fi
    fi
    print -r -- "$family_option"
    print -r -- "--connect-timeout 10"
    print -r -- "--speed-limit ${speed_limit}"
    print -r -- "--speed-time ${speed_seconds}"
  } > "$JOBS_UPDATE_BREW_CURLRC"
}
# 选择探测速度更快的 IP 协议，并让后续 Homebrew 下载复用该选择。
jobs_update_select_preferred_ip_family() {
  JOBS_UPDATE_IPV4_PROBE_SPEED="$(jobs_update_measure_ip_family_speed ipv4)"
  JOBS_UPDATE_IPV6_PROBE_SPEED="$(jobs_update_measure_ip_family_speed ipv6)"

  info_echo "Homebrew 下载线路探测：IPv4=$(jobs_update_format_download_speed "$JOBS_UPDATE_IPV4_PROBE_SPEED")，IPv6=$(jobs_update_format_download_speed "$JOBS_UPDATE_IPV6_PROBE_SPEED")"
  if (( JOBS_UPDATE_IPV6_PROBE_SPEED > JOBS_UPDATE_IPV4_PROBE_SPEED )); then
    JOBS_UPDATE_PREFERRED_IP_FAMILY="ipv6"
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv4"
  else
    JOBS_UPDATE_PREFERRED_IP_FAMILY="ipv4"
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv6"
  fi

  if (( JOBS_UPDATE_IPV4_PROBE_SPEED == 0 && JOBS_UPDATE_IPV6_PROBE_SPEED == 0 )); then
    warn_echo "IPv4 / IPv6 探测均未获得有效速度，先从 IPv4 开始；正式下载失败后仍会自动切换。"
  else
    success_echo "Homebrew 下载首选线路：${JOBS_UPDATE_PREFERRED_IP_FAMILY}"
  fi
}
# 初始化整轮 update 共用的 Homebrew 自适应下载策略。
jobs_update_ensure_network_strategy() {
  if (( JOBS_UPDATE_NETWORK_READY == 1 )); then
    return 0
  fi
  if [[ ! -x /usr/bin/curl ]]; then
    warn_echo "未找到 /usr/bin/curl，Homebrew 下载将沿用默认网络策略。"
    return 1
  fi

  if (( ${+HOMEBREW_CURLRC} )); then
    JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET=1
    JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC="$HOMEBREW_CURLRC"
  fi
  JOBS_UPDATE_BREW_CURLRC="$(mktemp -t jobs_update_homebrew_curlrc.XXXXXX)" || return 1
  jobs_update_select_preferred_ip_family
  jobs_update_write_brew_curlrc "$JOBS_UPDATE_PREFERRED_IP_FAMILY" adaptive || return 1
  export HOMEBREW_CURLRC="$JOBS_UPDATE_BREW_CURLRC"
  JOBS_UPDATE_NETWORK_READY=1
  note_echo "已启用全局 Homebrew 自适应下载：低速阈值会按线路实测速度自动收敛，停滞时切换 IPv4 / IPv6。"
}
# 清理临时网络配置，并恢复用户原有的 Homebrew curl 设置。
jobs_update_cleanup_network_strategy() {
  if (( JOBS_UPDATE_NETWORK_READY != 1 )) && [[ -z "$JOBS_UPDATE_BREW_CURLRC" && -z "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]]; then
    return 0
  fi
  jobs_update_stop_brew_progress_monitor
  if [[ -n "$JOBS_UPDATE_BREW_CURLRC" && -f "$JOBS_UPDATE_BREW_CURLRC" ]]; then
    rm -f "$JOBS_UPDATE_BREW_CURLRC"
  fi
  if [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" && -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]]; then
    rm -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
  fi
  if (( JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC_WAS_SET == 1 )); then
    export HOMEBREW_CURLRC="$JOBS_UPDATE_ORIGINAL_HOMEBREW_CURLRC"
  else
    unset HOMEBREW_CURLRC
  fi
  JOBS_UPDATE_NETWORK_READY=0
}
# 更新首选 IP 协议，并重写后续 Homebrew 下载使用的速度守卫。
jobs_update_prefer_ip_family() {
  local family="$1"

  JOBS_UPDATE_PREFERRED_IP_FAMILY="$family"
  if [[ "$family" == "ipv4" ]]; then
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv6"
  else
    JOBS_UPDATE_SECONDARY_IP_FAMILY="ipv4"
  fi
  jobs_update_write_brew_curlrc "$family" adaptive
}
# 汇总 Homebrew 未完成下载缓存的当前字节数。
jobs_update_homebrew_incomplete_bytes() {
  local cache_dir="${HOME}/Library/Caches/Homebrew/downloads"
  local file=""
  local size=0
  local total=0

  [[ -d "$cache_dir" ]] || {
    print -r -- "0"
    return 0
  }
  while IFS= read -r -d '' file; do
    size="$(stat -f '%z' "$file" 2>/dev/null || print -r -- "0")"
    [[ "$size" == <-> ]] || size=0
    total=$((total + size))
  done < <(find "$cache_dir" -type f -name '*.incomplete' -print0 2>/dev/null)
  print -r -- "$total"
}
# 把字节数转换成便于进度日志阅读的大小。
jobs_update_format_download_bytes() {
  local bytes="${1:-0}"

  [[ "$bytes" == <-> ]] || bytes=0
  if (( bytes >= 1048576 )); then
    print -r -- "$((bytes / 1048576)) MiB"
  elif (( bytes >= 1024 )); then
    print -r -- "$((bytes / 1024)) KiB"
  else
    print -r -- "${bytes} B"
  fi
}
# 在 Homebrew 隐藏 curl 进度条时输出缓存增长心跳。
jobs_update_monitor_brew_progress() {
  local desc="$1"
  local family="$2"
  local previous_bytes=""
  local current_bytes=""
  local delta_bytes=0

  previous_bytes="$(jobs_update_homebrew_incomplete_bytes)"
  while true; do
    sleep "$JOBS_UPDATE_PROGRESS_INTERVAL_SECONDS"
    current_bytes="$(jobs_update_homebrew_incomplete_bytes)"
    if (( current_bytes > previous_bytes )); then
      delta_bytes=$((current_bytes - previous_bytes))
      info_echo "${desc}（${family}）仍在下载：最近增加 $(jobs_update_format_download_bytes "$delta_bytes")，未完成缓存共 $(jobs_update_format_download_bytes "$current_bytes")。"
    else
      gray_echo "${desc}（${family}）仍在执行，暂未观察到下载缓存增长；若持续低于阈值将自动超时。"
    fi
    previous_bytes=$current_bytes
  done
}
# 启动单个 Homebrew 命令对应的进度心跳。
jobs_update_start_brew_progress_monitor() {
  jobs_update_stop_brew_progress_monitor
  jobs_update_monitor_brew_progress "$1" "$2" &
  JOBS_UPDATE_PROGRESS_MONITOR_PID=$!
}
# 停止当前 Homebrew 进度心跳并回收后台进程。
jobs_update_stop_brew_progress_monitor() {
  [[ -n "$JOBS_UPDATE_PROGRESS_MONITOR_PID" ]] || return 0
  kill "$JOBS_UPDATE_PROGRESS_MONITOR_PID" 2>/dev/null || true
  wait "$JOBS_UPDATE_PROGRESS_MONITOR_PID" 2>/dev/null || true
  JOBS_UPDATE_PROGRESS_MONITOR_PID=""
}
# 判断 Homebrew 失败是否来自下载链路，以免对安装或权限错误盲目换线。
jobs_update_brew_failure_is_network_related() {
  [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" && -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]] || return 1
  grep -Eqi 'curl: \([0-9]+\)|Failed to download resource|Download failed|Could not resolve host|Failed to connect|Connection timed out|Operation timed out|Operation too slow|SSL connect error|Recv failure|Send failure|HTTP/[0-9.]+ stream' "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
}
# 使用指定 IP 协议执行一次 Homebrew 下载命令。
jobs_update_run_brew_network_attempt() {
  local desc="$1"
  local confirmation_mode="$2"
  local family="$3"
  local guard_mode="$4"
  local retries=0
  shift 4

  jobs_update_write_brew_curlrc "$family" "$guard_mode" || return 1
  [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]] || return 1
  : > "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
  note_echo "${desc}（${family}，连续 ${JOBS_UPDATE_ACTIVE_LOW_SPEED_SECONDS} 秒低于 $(jobs_update_format_download_speed "$JOBS_UPDATE_ACTIVE_LOW_SPEED_LIMIT_BPS") 时终止当前尝试）"
  debug_echo "执行命令：HOMEBREW_CURLRC=<临时配置> HOMEBREW_CURL_RETRIES=${retries} $*"
  jobs_update_start_brew_progress_monitor "$desc" "$family"

  if [[ "$confirmation_mode" == "yes" ]]; then
    printf 'y\n' | env HOMEBREW_CURLRC="$JOBS_UPDATE_BREW_CURLRC" HOMEBREW_CURL_RETRIES="$retries" "$@" 2>&1 | tee -a "$LOG_FILE" | tee "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
    local exit_code=${pipestatus[2]}
  else
    env HOMEBREW_CURLRC="$JOBS_UPDATE_BREW_CURLRC" HOMEBREW_CURL_RETRIES="$retries" "$@" 2>&1 | tee -a "$LOG_FILE" | tee "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
    local exit_code=${pipestatus[1]}
  fi
  jobs_update_stop_brew_progress_monitor

  if (( exit_code == 0 )); then
    success_echo "${desc}（${family}）：完成"
  else
    warn_echo "${desc}（${family}）：失败（exit code: ${exit_code}）"
  fi
  return $exit_code
}
# 为所有 Homebrew 更新下载提供低速换线和有限重试。
jobs_update_run_brew_adaptive_cmd() {
  local desc="$1"
  local confirmation_mode="$2"
  local primary_family=""
  local secondary_family=""
  local exit_code=0
  shift 2

  if ! jobs_update_ensure_network_strategy; then
    if [[ "$confirmation_mode" == "yes" ]]; then
      jobs_update_run_cmd_with_yes "$desc" "$@"
    else
      jobs_update_run_cmd "$desc" "$@"
    fi
    return $?
  fi
  if [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" && -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]]; then
    rm -f "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"
  fi
  JOBS_UPDATE_LAST_BREW_OUTPUT_FILE="$(mktemp -t jobs_update_brew_output.XXXXXX)" || return 1
  primary_family="$JOBS_UPDATE_PREFERRED_IP_FAMILY"
  secondary_family="$JOBS_UPDATE_SECONDARY_IP_FAMILY"

  jobs_update_run_brew_network_attempt "$desc" "$confirmation_mode" "$primary_family" adaptive "$@"
  exit_code=$?
  if (( exit_code == 0 )); then
    jobs_update_prefer_ip_family "$primary_family"
    return 0
  fi
  if ! jobs_update_brew_failure_is_network_related; then
    return $exit_code
  fi

  warn_echo "${primary_family} 下载异常或持续低速，自动切换到 ${secondary_family}。"
  jobs_update_run_brew_network_attempt "$desc" "$confirmation_mode" "$secondary_family" adaptive "$@"
  exit_code=$?
  if (( exit_code == 0 )); then
    jobs_update_prefer_ip_family "$secondary_family"
    return 0
  fi
  if ! jobs_update_brew_failure_is_network_related; then
    return $exit_code
  fi

  warn_echo "IPv4 / IPv6 均触发网络失败；将使用探测中较快的 ${primary_family} 做最后一次宽松低速尝试，停滞时仍会退出。"
  jobs_update_run_brew_network_attempt "$desc" "$confirmation_mode" "$primary_family" final "$@"
  exit_code=$?
  jobs_update_prefer_ip_family "$primary_family"
  return $exit_code
}
# 执行 brew update，遇到 Homebrew API 下载失败时自动降级为本地 tap 更新。
jobs_update_run_brew_update() {
  jobs_update_run_brew_adaptive_cmd "brew update（更新软件列表）" plain brew update
  local exit_code=$?

  if (( exit_code == 0 )); then
    return 0
  fi

  if [[ -n "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE" ]] && grep -Eq "formulae\\.brew\\.sh/api|Failed to download .*\\.jws\\.json" "$JOBS_UPDATE_LAST_BREW_OUTPUT_FILE"; then
    warn_echo "brew update API 数据下载失败，将使用 HOMEBREW_NO_INSTALL_FROM_API=1 降级重试。"
    warm_echo "说明：该模式会跳过 formulae.brew.sh API JSON 下载，改用本地 tap 更新，通常更慢但更稳。"
    jobs_update_run_brew_adaptive_cmd "brew update（本地 tap 降级重试）" plain env HOMEBREW_NO_INSTALL_FROM_API=1 brew update
    exit_code=$?
  else
    warn_echo "brew update（更新软件列表）：失败（exit code: ${exit_code}）"
  fi

  return $exit_code
}
# 执行 brew upgrade，托管模式下自动确认 Homebrew 的 y/n 提示。
jobs_update_run_brew_upgrade() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    jobs_update_run_brew_adaptive_cmd "brew upgrade（升级已安装 formula）" yes brew upgrade
    return $?
  fi

  jobs_update_run_brew_adaptive_cmd "brew upgrade（升级已安装 formula）" plain brew upgrade
}
# 执行 brew cask 全局升级，托管模式下自动确认 Homebrew 的 y/n 提示。
jobs_update_run_brew_cask_upgrade() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    jobs_update_run_brew_adaptive_cmd "brew upgrade --cask（升级已安装 cask）" yes brew upgrade --cask
    return $?
  fi

  jobs_update_run_brew_adaptive_cmd "brew upgrade --cask（升级已安装 cask）" plain brew upgrade --cask
}
# 封装 append_once 对应的独立处理逻辑。
append_once() {
  local line="$1"
  local file="${2:-$HOME/.zshrc}"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -Fqx "$line" "$file"; then
    return 0
  fi

  echo "" >> "$file"
  echo "$line" >> "$file"
}
# 封装 append_comment_once 对应的独立处理逻辑。
append_comment_once() {
  local comment="$1"
  local file="$2"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -Fqx "$comment" "$file"; then
    return 0
  fi

  echo "" >> "$file"
  echo "$comment" >> "$file"
}
# 解析并返回后续流程需要的目标信息。
find_brew_bin() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  local candidate
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}
# 执行对应的环境配置或同步处理。
setup_brew_shellenv() {
  local brew_bin="$1"
  local shellenv_line="eval \"\$(${brew_bin} shellenv)\""

  if [[ ! -x "$brew_bin" ]]; then
    warn_echo "Homebrew 可执行文件不存在或不可执行：${brew_bin}"
    return 1
  fi

  local target_file
  for target_file in "${HOME}/.zprofile" "${HOME}/.zshrc"; do
    append_comment_once "# Homebrew shellenv" "$target_file"
    append_once "$shellenv_line" "$target_file"
    success_echo "已确认 Homebrew 环境变量配置：${target_file}"
  done

  eval "$($brew_bin shellenv)"
  hash -r 2>/dev/null || true
}
# 封装 require_brew_or_skip 对应的独立处理逻辑。
require_brew_or_skip() {
  local brew_bin=""

  if brew_bin="$(find_brew_bin)"; then
    setup_brew_shellenv "$brew_bin"
    return 0
  fi

  warn_echo "未检测到 Homebrew，跳过当前更新项。请先运行 install.command 安装 Homebrew。"
  return 1
}
# 执行对应的环境配置或同步处理。
setup_fzf_shellenv() {
  if ! jobs_update_has brew; then
    return 0
  fi

  local fzf_base=""
  fzf_base="$(brew --prefix fzf 2>/dev/null || true)"

  if [[ -n "$fzf_base" && -d "$fzf_base" ]]; then
    append_comment_once "# fzf" "${HOME}/.zshrc"
    append_once '[ -f "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh" ] && source "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"' "${HOME}/.zshrc"
    append_once '[ -f "$(brew --prefix)/opt/fzf/shell/completion.zsh" ] && source "$(brew --prefix)/opt/fzf/shell/completion.zsh"' "${HOME}/.zshrc"
    success_echo "已确认 fzf shell 配置：${HOME}/.zshrc"
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_jenv_init() {
  append_comment_once "# jenv" "${HOME}/.zshrc"
  append_once 'export PATH="$HOME/.jenv/bin:$PATH"' "${HOME}/.zshrc"
  append_once 'eval "$(jenv init -)"' "${HOME}/.zshrc"
  success_echo "已确认 jenv 初始化配置：${HOME}/.zshrc"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_rbenv_init() {
  append_comment_once "# rbenv" "${HOME}/.zshrc"
  append_once 'eval "$(rbenv init - zsh)"' "${HOME}/.zshrc"
  success_echo "已确认 rbenv 初始化配置：${HOME}/.zshrc"
}
# 封装 post_openjdk_hint 对应的独立处理逻辑。
post_openjdk_hint() {
  warm_echo "openjdk 更新完成后，如需让系统 java 指向 Homebrew openjdk，可按需执行："
  warm_echo '  sudo ln -sfn "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk" /Library/Java/JavaVirtualMachines/openjdk.jdk'
  warm_echo "如果使用 jenv 管理 Java，推荐执行："
  warm_echo '  jenv add "$(brew --prefix)/opt/openjdk/libexec/openjdk.jdk/Contents/Home"'
}
# 封装 jobs_update_source_nvm_if_needed 对应的独立处理逻辑。
jobs_update_source_nvm_if_needed() {
  if jobs_update_has nvm; then
    return 0
  fi

  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  if [[ -s "$nvm_dir/nvm.sh" ]]; then
    source "$nvm_dir/nvm.sh"
  fi
}
# 解析并返回后续流程需要的目标信息。
get_node_major_version() {
  if ! jobs_update_has node; then
    echo "0"
    return 0
  fi

  local version=""
  version="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
  [[ -n "$version" ]] && echo "$version" || echo "0"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_node_for_opencli() {
  local major=""
  major="$(get_node_major_version)"

  if (( major >= 21 )); then
    success_echo "Node.js 版本满足 OpenCLI 要求：$(node --version)"
    return 0
  fi

  warn_echo "OpenCLI 需要 Node.js >= 21，当前版本：$(node --version 2>/dev/null || echo '未安装')"
  warn_echo "update.command 不会静默安装 Node，请先通过 Homebrew / nvm 升级 Node 后重试。"
  return 1
}
# 封装 jobs_update_find_external_command 对应的独立处理逻辑。
jobs_update_find_external_command() {
  local command_name="$1"
  local path_dir=""
  local candidate=""
  local candidate_real=""
  local script_real=""

  if [[ -n "${SCRIPT_PATH:-}" && -e "$SCRIPT_PATH" ]]; then
    script_real="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd -P)/$(basename "$SCRIPT_PATH")"
  fi

  for path_dir in ${(s.:.)PATH}; do
    [[ -n "$path_dir" ]] || continue
    candidate="$path_dir/$command_name"
    [[ -x "$candidate" ]] || continue

    candidate_real="$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P)/$(basename "$candidate")"
    [[ -n "$script_real" && "$candidate_real" == "$script_real" ]] && continue

    print -r -- "$candidate"
    return 0
  done

  return 1
}
# 执行 Android SDK licenses 接受流程，托管模式下自动输入 y。
jobs_update_run_flutter_android_licenses() {
  local desc="$1"
  shift

  local -a license_cmd=("$@")
  if (( ${#license_cmd[@]} == 0 )); then
    warn_echo "未提供 Android SDK licenses 命令，已跳过。"
    return 0
  fi

  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    note_echo "$desc"
    debug_echo "执行命令：yes | ${license_cmd[*]}"
    yes | "${license_cmd[@]}" 2>&1 | tee -a "$LOG_FILE"
    local exit_code=${pipestatus[2]}

    if (( exit_code == 0 )); then
      success_echo "$desc：完成"
    else
      warn_echo "$desc：失败（exit code: ${exit_code}）"
    fi

    return $exit_code
  fi

  if [[ ! -t 0 ]]; then
    warn_echo "当前不是交互式终端，已跳过：$desc"
    return 0
  fi

  jobs_update_run_cmd "$desc" "${license_cmd[@]}"
}
# 执行 Flutter doctor，并在检测到 Android license 未确认时引导接受许可。
jobs_update_run_flutter_doctor_and_android_licenses() {
  local label="$1"
  shift

  local -a flutter_base_cmd=("$@")
  if (( ${#flutter_base_cmd[@]} == 0 )); then
    warn_echo "未提供 Flutter 命令，跳过 Flutter doctor。"
    return 0
  fi

  local doctor_output_file=""
  doctor_output_file="$(mktemp -t jobs_update_flutter_doctor.XXXXXX)"
  local -a doctor_cmd=("${flutter_base_cmd[@]}" doctor -v)
  local -a license_cmd=("${flutter_base_cmd[@]}" doctor --android-licenses)

  note_echo "${label} doctor -v"
  debug_echo "执行命令：${doctor_cmd[*]}"
  "${doctor_cmd[@]}" 2>&1 | tee -a "$LOG_FILE" | tee "$doctor_output_file"
  local doctor_exit_code=${pipestatus[1]}

  if (( doctor_exit_code == 0 )); then
    success_echo "${label} doctor -v：完成"
  else
    warn_echo "${label} doctor -v：返回非 0（${doctor_exit_code}），继续检查 Android license 提示。"
  fi

  if grep -Eq "Android license status unknown|flutter doctor --android-licenses" "$doctor_output_file"; then
    warn_echo "检测到 Android license status unknown，将执行：${license_cmd[*]}"

    if grep -Fq "cmdline-tools component is missing" "$doctor_output_file"; then
      warm_echo "doctor 同时提示 Android cmdline-tools 缺失；若许可接受失败，请先在 Android Studio 安装 Command-line Tools。"
    fi

    jobs_update_run_flutter_android_licenses "接受 Android SDK licenses" "${license_cmd[@]}" || true
  fi

  rm -f "$doctor_output_file"
  return 0
}
# ---------- 内置自述 ----------
jobs_update_show_readme_and_wait() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    note_echo "托管模式：已跳过完整自述确认。" | jobs_intro_style body
    return 0
  fi

  clear 2>/dev/null || true

  {
    cat <<'EOFREADME' | jobs_intro_style auto
============================================================
update.command - macOS 开发环境升级维护
============================================================

核心原则：
  install.command 安装 / 初始化过的内容，update.command 必须体现并提供升级 / 刷新入口。

本脚本会按顺序询问是否更新：
  1. Xcode Command Line Tools / softwareupdate
  2. Xcode iOS 平台组件
  3. Oh My Zsh
  4. Homebrew
  5. brew cask：由 BREW_CASKS 自动生成
  6. brew formula：由 BREW_FORMULAE 自动生成
  7. Rosetta 2 状态检查
  8. FVM / Flutter SDK / flutter doctor
  9. Node / corepack / npm 基础维护
 10. npm 全局包：quicktype
 11. npm 全局包：OpenCLI
 12. npm 全局包：CodeGraph
 13. Ruby / RubyGems
 14. CocoaPods：识别 Homebrew / gem，实测后刷新所选公共 Specs 源
 15. Python / pip
 16. Dart pub 缓存
 17. Git LFS 初始化与大文件参数
 18. JobsKits 仓库：JobsSoftware.MacOS、JobsMacEnvVarConfig
 19. 手动下载页：VS Code、Android Studio、Python

交互规则：
  - 直接回车：跳过当前项
  - 输入任意字符后回车：执行当前升级 / 刷新项
  - 单项失败：记录警告，继续后续项
  - 工具不存在：提示回到 install.command 补装，不在 update 中静默安装
  - Homebrew：brew update 遇到 formulae.brew.sh API 下载失败时，会自动使用 HOMEBREW_NO_INSTALL_FROM_API=1 降级重试
  - Homebrew 下载：全局测速选择 IPv4 / IPv6；正式下载持续低速时自动换线，无需人工选择
  - 第三方 tap：检测到 Homebrew tap trust 策略时，会先信任脚本维护的指定 tap 后再执行升级

当前 BREW_CASKS：
EOFREADME

    local pkg
    for pkg in "${BREW_CASKS[@]}"; do
      echo "  - ${pkg}" | jobs_intro_style body
    done

    cat <<'EOFREADME' | jobs_intro_style auto

当前 BREW_FORMULAE：
EOFREADME

    for pkg in "${BREW_FORMULAE[@]}"; do
      echo "  - ${pkg}" | jobs_intro_style body
    done

    cat <<'EOFREADME' | jobs_intro_style auto

日志路径：/tmp/update.log
============================================================
EOFREADME
  } | tee -a "$LOG_FILE" | jobs_intro_style auto

  if [[ -t 0 && "${JOBS_MAC_ENV_SKIP_README:-}" != "1" ]]; then
    echo "" | jobs_intro_style body
    local _answer=""
    IFS= read -r "_answer?👉 已阅读自述文件，按回车开始逐项更新；按 Ctrl+C 取消："
  fi
}
# ---------- 更新项：系统 / Xcode / Shell ----------
jobs_update_clt() {
  if ! xcode-select -p >/dev/null 2>&1; then
    warn_echo "未检测到 Xcode Command Line Tools。update.command 不负责安装，请运行 install.command 补装。"
    return 0
  fi

  success_echo "Xcode Command Line Tools 已存在：$(xcode-select -p)"

  if jobs_update_has xcodebuild; then
    jobs_update_run_sudo_cmd "接受 Xcode License" xcodebuild -license accept || true
  else
    warn_echo "未检测到 xcodebuild，跳过 Xcode License 接受步骤"
  fi

  warn_echo "softwareupdate --install --all 可能安装 macOS 可用系统更新，耗时较长。"
  jobs_update_run_sudo_cmd "安装 macOS 可用软件更新" softwareupdate --install --all || true
}
# 封装 jobs_update_xcode_ios_platform 对应的独立处理逻辑。
jobs_update_xcode_ios_platform() {
  if ! jobs_update_has xcodebuild; then
    warn_echo "未检测到 xcodebuild，无法更新 Xcode iOS 平台组件。"
    return 0
  fi

  if xcodebuild -showsdks 2>/dev/null | grep -E "iphoneos|iphonesimulator" >/dev/null 2>&1; then
    success_echo "检测到 iOS SDK，开始刷新 iOS 平台组件。"
  else
    warn_echo "未检测到 iOS SDK，将尝试通过 xcodebuild 下载 iOS 平台组件。"
  fi

  jobs_update_run_sh "清理 Xcode 缓存" 'rm -rf ~/Library/Caches/com.apple.dt.Xcode' || true
  jobs_update_run_sh "清理 CoreSimulator 缓存" 'rm -rf ~/Library/Developer/CoreSimulator/Caches' || true
  jobs_update_run_cmd "下载 / 更新 iOS 模拟器平台" xcodebuild -downloadPlatform iOS -verbose || true
}
# 封装 jobs_update_oh_my_zsh 对应的独立处理逻辑。
jobs_update_oh_my_zsh() {
  if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    warn_echo "未检测到 Oh My Zsh。update.command 不负责安装，请运行 install.command 补装。"
    return 0
  fi

  success_echo "Oh My Zsh 已存在：${HOME}/.oh-my-zsh"

  if [[ -f "${HOME}/.oh-my-zsh/tools/upgrade.sh" ]]; then
    jobs_update_run_sh "更新 Oh My Zsh" "ZSH='${HOME}/.oh-my-zsh' '${HOME}/.oh-my-zsh/tools/upgrade.sh'" || true
  else
    warn_echo "未找到 Oh My Zsh upgrade.sh，跳过更新"
  fi
}
# 封装 jobs_update_rosetta 对应的独立处理逻辑。
jobs_update_rosetta() {
  if [[ "$(uname -m)" != "arm64" ]]; then
    info_echo "当前不是 Apple Silicon，Rosetta 2 不适用。"
    return 0
  fi

  if /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
    success_echo "Rosetta 2 已安装。Rosetta 2 通常通过 macOS 系统更新维护，无独立 upgrade 命令。"
  else
    warn_echo "未检测到 Rosetta 2。update.command 不负责安装，请运行 install.command 补装。"
  fi
}
# ---------- 更新项：Homebrew ----------
jobs_update_homebrew() {
  if ! require_brew_or_skip; then
    return 0
  fi

  jobs_update_trust_configured_brew_taps
  jobs_update_run_brew_update || true
  jobs_update_run_brew_upgrade || true
  jobs_update_run_brew_cask_upgrade || true
  jobs_update_run_cmd "brew cleanup（清理旧版本缓存）" brew cleanup || true
  jobs_update_run_cmd "brew doctor（检查 Homebrew 健康状态）" brew doctor || true
  jobs_update_run_cmd "brew -v（输出 Homebrew 版本）" brew -v || true
}
# 封装 brew_formula_install_arg 对应的独立处理逻辑。
brew_formula_install_arg() {
  local formula_name="$1"

  case "$formula_name" in
    go-task) echo "go-task/tap/go-task" ;;
    *) echo "$formula_name" ;;
  esac
}
# 封装 brew_formula_tap_name 对应的独立处理逻辑。
brew_formula_tap_name() {
  local formula_name="$1"

  case "$formula_name" in
    fvm) echo "leoafarias/fvm" ;;
    go-task) echo "go-task/tap" ;;
    *) echo "" ;;
  esac
}
# 按当前 Homebrew 信任策略确认第三方 tap，避免已开启 tap trust 时直接拒绝加载。
brew_trust_tap_if_required() {
  local tap_name="$1"

  [[ -n "$tap_name" ]] || return 0

  if ! brew help trust >/dev/null 2>&1; then
    return 0
  fi

  if brew trust --json=v1 2>/dev/null | grep -Fq "\"${tap_name:l}\""; then
    success_echo "Homebrew Tap 已信任：${tap_name}"
    return 0
  fi

  jobs_update_run_cmd "信任 Homebrew Tap：${tap_name}" brew trust "$tap_name" || true
}
# 在全局 brew upgrade 前信任脚本维护的第三方 tap，避免扫描阶段先跳过第三方 formula/cask。
jobs_update_trust_configured_brew_taps() {
  local pkg=""
  local tap_name=""
  local trusted_taps=()

  for pkg in "${BREW_FORMULAE[@]}"; do
    tap_name="$(brew_formula_tap_name "$pkg")"
    [[ -n "$tap_name" ]] || continue
    (( ${trusted_taps[(Ie)$tap_name]} > 0 )) && continue
    trusted_taps+=("$tap_name")
    brew_trust_tap_if_required "$tap_name"
  done

  for pkg in "${BREW_CASKS[@]}"; do
    tap_name="$(brew_cask_tap_name "$pkg")"
    [[ -n "$tap_name" ]] || continue
    (( ${trusted_taps[(Ie)$tap_name]} > 0 )) && continue
    trusted_taps+=("$tap_name")
    brew_trust_tap_if_required "$tap_name"
  done
}
# 封装 brew_formula_after_update 对应的独立处理逻辑。
brew_formula_after_update() {
  local formula_name="$1"

  case "$formula_name" in
    rbenv) ensure_rbenv_init ;;
    jenv) ensure_jenv_init ;;
    openjdk|openjdk@17) post_openjdk_hint ;;
    fzf) setup_fzf_shellenv ;;
    *) return 0 ;;
  esac
}
# 封装 brew_cask_tap_name 对应的独立处理逻辑。
brew_cask_tap_name() {
  local cask_name="$1"

  case "$cask_name" in
    github-store) echo "OpenHub-Store/tap" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_cask_install_hint 对应的独立处理逻辑。
brew_cask_install_hint() {
  local cask_name="$1"

  case "$cask_name" in
    github-store)
      warm_echo "补装命令：brew tap OpenHub-Store/tap"
      warm_echo "补装命令：brew install --cask github-store"
      ;;
    *) return 0 ;;
  esac
}
# 封装 jobs_update_github_store_after_update 对应的独立处理逻辑。
jobs_update_github_store_after_update() {
  local app_path="/Applications/GitHub-Store.app"

  if [[ -d "$app_path" ]]; then
    jobs_update_run_cmd "解除 GitHub-Store.app quarantine 标记" xattr -dr com.apple.quarantine "$app_path" || true
  else
    warn_echo "未找到 ${app_path}，跳过 quarantine 标记清理。"
  fi
}
# 仅在 Dart 通过 Flutter 官方签名校验后，解除 Homebrew Cask 传播到 Flutter SDK 的隔离标记。
jobs_update_flutter_release_verified_quarantine() {
  local flutter_command=""
  local flutter_root=""
  local dart_binary=""
  local signature_info=""
  local remaining_quarantine=""

  flutter_command="$(command -v flutter 2>/dev/null || true)"
  [[ -n "$flutter_command" ]] || return 0

  flutter_command="$(realpath "$flutter_command" 2>/dev/null || true)"
  [[ -n "$flutter_command" && -f "$flutter_command" ]] || return 0

  flutter_root="$(cd "$(dirname "$flutter_command")/.." 2>/dev/null && pwd -P || true)"
  dart_binary="${flutter_root}/bin/cache/dart-sdk/bin/dart"
  if [[ ! -x "$dart_binary" ]]; then
    warn_echo "未找到 Flutter SDK 内的 Dart 二进制文件，跳过 quarantine 标记清理。"
    return 0
  fi

  if ! /usr/bin/codesign --verify --strict "$dart_binary" >/dev/null 2>&1; then
    warn_echo "Dart 代码签名校验失败，为避免降低系统安全性，保留 Flutter SDK 的 quarantine 标记。"
    return 1
  fi

  signature_info="$(/usr/bin/codesign -dv --verbose=4 "$dart_binary" 2>&1 || true)"
  if ! print -r -- "$signature_info" | grep -Fq 'Authority=Developer ID Application: FLUTTER.IO LLC (S8QB4VV633)'; then
    warn_echo "Dart 签名方不是预期的 FLUTTER.IO LLC，保留 Flutter SDK 的 quarantine 标记。"
    return 1
  fi

  if ! find "$flutter_root" -xattrname com.apple.quarantine -print -quit 2>/dev/null | grep -Fq '/'; then
    success_echo "Flutter SDK 无 quarantine 标记，无需处理。"
    return 0
  fi

  /usr/bin/xattr -dr com.apple.quarantine "$flutter_root" 2>/dev/null || true
  find "$flutter_root" -type l -xattrname com.apple.quarantine -print0 2>/dev/null |
    while IFS= read -r -d '' quarantined_link; do
      /usr/bin/xattr -d -s com.apple.quarantine "$quarantined_link" 2>/dev/null || true
    done
  remaining_quarantine="$(find "$flutter_root" -xattrname com.apple.quarantine -print -quit 2>/dev/null || true)"
  if [[ -n "$remaining_quarantine" ]]; then
    warn_echo "Flutter SDK 仍存在 quarantine 标记：${remaining_quarantine}"
    return 1
  fi

  success_echo "已验证 FLUTTER.IO LLC 官方签名，并解除 Flutter SDK quarantine 标记。"
}
# 封装 brew_cask_after_update 对应的独立处理逻辑。
brew_cask_after_update() {
  local cask_name="$1"

  case "$cask_name" in
    flutter) jobs_update_flutter_release_verified_quarantine || true ;;
    github-store) jobs_update_github_store_after_update ;;
    *) return 0 ;;
  esac
}
# 封装 brew_cask_local_app_path 对应的独立处理逻辑。
brew_cask_local_app_path() {
  local cask_name="$1"

  case "$cask_name" in
    vlc) echo "/Applications/VLC.app" ;;
    *) echo "" ;;
  esac
}
# 封装 brew_cask_local_app_exists 对应的独立处理逻辑。
brew_cask_local_app_exists() {
  local cask_name="$1"
  local app_path=""

  app_path="$(brew_cask_local_app_path "$cask_name")"
  [[ -n "$app_path" && -d "$app_path" ]]
}
# 封装 jobs_update_brew_formula_one 对应的独立处理逻辑。
jobs_update_brew_formula_one() {
  local formula_name="$1"
  local install_arg=""
  local tap_name=""

  if ! require_brew_or_skip; then
    return 0
  fi

  install_arg="$(brew_formula_install_arg "$formula_name")"
  tap_name="$(brew_formula_tap_name "$formula_name")"

  if ! brew list --formula --versions "$formula_name" >/dev/null 2>&1; then
    warn_echo "未安装 brew formula：${formula_name}，跳过升级。请运行 install.command 补装。"
    return 0
  fi

  if [[ -n "$tap_name" ]]; then
    brew_trust_tap_if_required "$tap_name"
    jobs_update_run_cmd "确认 Homebrew Tap：${tap_name}" brew tap "$tap_name" || true
  fi

  if jobs_update_run_brew_adaptive_cmd "升级 brew formula：${formula_name}" plain brew upgrade "$install_arg"; then
    [[ "$formula_name" == cocoapods ]] && JOBS_UPDATE_COCOAPODS_BREW_UPDATED=1
  fi
  brew_formula_after_update "$formula_name"
}
# 封装 jobs_update_brew_formulae 对应的独立处理逻辑。
jobs_update_brew_formulae() {
  local pkg
  for pkg in "${BREW_FORMULAE[@]}"; do
    echo ""
    highlight_echo "brew formula：${pkg}"
    jobs_update_brew_formula_one "$pkg"
  done
}
# 封装 jobs_update_brew_cask_one 对应的独立处理逻辑。
jobs_update_brew_cask_one() {
  local cask_name="$1"
  local tap_name=""

  if ! require_brew_or_skip; then
    return 0
  fi

  tap_name="$(brew_cask_tap_name "$cask_name")"
  if [[ -n "$tap_name" ]]; then
    brew_trust_tap_if_required "$tap_name"
    jobs_update_run_cmd "确认 Homebrew Tap：${tap_name}" brew tap "$tap_name" || true
  fi

  if ! brew list --cask --versions "$cask_name" >/dev/null 2>&1; then
    if brew_cask_local_app_exists "$cask_name"; then
      local app_path=""
      app_path="$(brew_cask_local_app_path "$cask_name")"
      success_echo "已检测到本机 App：${app_path}"
      warn_echo "Homebrew 未登记 brew cask：${cask_name}，但本机已有 App，跳过升级。"
      return 0
    fi

    warn_echo "未安装 brew cask：${cask_name}，跳过升级。请运行 install.command 补装。"
    brew_cask_install_hint "$cask_name"
    return 0
  fi

  jobs_update_run_brew_adaptive_cmd "升级 brew cask：${cask_name}" plain brew upgrade --cask "$cask_name" || true
  brew_cask_after_update "$cask_name"
}
# 封装 jobs_update_brew_casks 对应的独立处理逻辑。
jobs_update_brew_casks() {
  local pkg
  for pkg in "${BREW_CASKS[@]}"; do
    echo ""
    highlight_echo "brew cask：${pkg}"
    jobs_update_brew_cask_one "$pkg"
  done
}
# ---------- 更新项：语言 / 包管理 ----------
jobs_update_fvm_flutter() {
  local external_flutter=""

  if jobs_update_has brew && brew list --formula fvm >/dev/null 2>&1; then
    jobs_update_brew_formula_one fvm
  elif jobs_update_has dart; then
    jobs_update_run_cmd "升级 FVM（Dart pub global）" dart pub global activate fvm || true
  else
    warn_echo "未检测到 brew formula fvm 或 dart，跳过 FVM 更新"
  fi

  if external_flutter="$(jobs_update_find_external_command flutter 2>/dev/null)"; then
    jobs_update_run_cmd "Flutter upgrade" "$external_flutter" upgrade || true
    jobs_update_flutter_release_verified_quarantine || true
    jobs_update_run_flutter_doctor_and_android_licenses "Flutter" "$external_flutter" || true
  elif jobs_update_has fvm; then
    jobs_update_run_flutter_doctor_and_android_licenses "FVM Flutter" fvm flutter || true
  else
    warn_echo "未检测到外部 flutter / fvm，跳过 Flutter SDK 更新"
  fi
}
# 封装 jobs_update_node_base 对应的独立处理逻辑。
jobs_update_node_base() {
  jobs_update_source_nvm_if_needed

  if jobs_update_has nvm; then
    jobs_update_run_cmd "nvm 安装 / 更新 LTS" nvm install --lts --reinstall-packages-from=current || true
    jobs_update_run_cmd "nvm 设置 default=LTS" nvm alias default 'lts/*' || true
    jobs_update_run_cmd "nvm use default" nvm use default || true
  elif jobs_update_has node; then
    success_echo "检测到 Node：$(node --version 2>/dev/null || true)"
    warn_echo "未检测到 nvm；Node 版本升级已由 Homebrew formula：node 更新项负责。"
  else
    warn_echo "未检测到 node / nvm，跳过 Node 基础维护"
  fi

  if jobs_update_has corepack; then
    jobs_update_run_cmd "启用 corepack" corepack enable || true
  fi

  if jobs_update_has npm; then
    jobs_update_run_cmd "升级 npm 自身" npm install -g npm@latest || true
    jobs_update_run_cmd "输出 npm 版本" npm -v || true
  fi
}
# 封装 jobs_update_npm_quicktype 对应的独立处理逻辑。
jobs_update_npm_quicktype() {
  if ! jobs_update_has npm; then
    warn_echo "npm 不存在，无法更新 quicktype。请先运行 install.command 安装 node。"
    return 0
  fi

  if npm list -g quicktype --depth=0 >/dev/null 2>&1; then
    jobs_update_run_npm_global_cmd "更新 npm 全局包 quicktype" "quicktype" update -g quicktype || true
  else
    warn_echo "未检测到 npm 全局包 quicktype，跳过升级。请运行 install.command 补装。"
  fi
}
# 封装 jobs_update_npm_opencli 对应的独立处理逻辑。
jobs_update_npm_opencli() {
  if ! jobs_update_has npm; then
    warn_echo "npm 不存在，无法更新 OpenCLI。请先运行 install.command 安装 node。"
    return 0
  fi

  if ! ensure_node_for_opencli; then
    return 0
  fi

  if npm list -g @jackwener/opencli --depth=0 >/dev/null 2>&1; then
    jobs_update_run_npm_global_cmd "更新 npm 全局包 OpenCLI" "@jackwener/opencli" install -g @jackwener/opencli@latest || true
  else
    warn_echo "未检测到 npm 全局包 OpenCLI，跳过升级。请运行 install.command 补装。"
  fi

  if jobs_update_has opencli; then
    jobs_update_run_cmd "输出 OpenCLI 版本" opencli --version || true
    warm_echo "OpenCLI 浏览器自动化还需要手动维护 Browser Bridge 扩展，可执行：opencli doctor"
  else
    warn_echo "当前 PATH 仍找不到 opencli，建议重新打开终端或检查 npm global bin。"
  fi
}
# 封装 jobs_update_npm_codegraph 对应的独立处理逻辑。
jobs_update_npm_codegraph() {
  if ! jobs_update_has npm; then
    warn_echo "npm 不存在，无法更新 CodeGraph。请先运行 install.command 安装 node。"
    return 0
  fi

  if npm list -g @colbymchenry/codegraph --depth=0 >/dev/null 2>&1; then
    success_echo "检测到 npm 全局包 CodeGraph，开始升级到 npm latest。"
  elif jobs_update_has codegraph; then
    warn_echo "检测到 codegraph 命令，但未检测到 npm 全局包 @colbymchenry/codegraph。"
    warm_echo "将尝试用 npm 接管并升级 CodeGraph；如果你想保留非 npm 安装方式，可跳过本项。"
  else
    warn_echo "未检测到 npm 全局包 CodeGraph，跳过升级。请运行 install.command 补装。"
    return 0
  fi

  if ! jobs_update_run_cmd "更新 npm 全局包 CodeGraph" npm install -g @colbymchenry/codegraph@latest; then
    warn_echo "CodeGraph npm 升级失败。若日志里是 EACCES 权限问题，请优先修复 npm 全局目录权限，或手动执行：sudo npm install -g @colbymchenry/codegraph@latest"
    return 0
  fi

  if jobs_update_has codegraph; then
    jobs_update_run_cmd "输出 CodeGraph 版本" codegraph --version || true
    jobs_update_run_cmd "刷新 CodeGraph Agent 配置" codegraph install --yes || true
    warm_echo "提示：已存在项目的 .codegraph/codegraph.db 不会在这里强制重建；进入具体项目后可按需执行 codegraph index --force。"
  else
    warn_echo "CodeGraph 已尝试升级，但当前 PATH 仍找不到 codegraph。建议重新打开终端或检查 npm global bin。"
  fi
}
# >>> Jobs Gem extension repair >>>
# 定位 CocoaPods 所用 Ruby；无法解析时复用当前 Ruby 和现有 Homebrew Ruby。
jobs_gemext_find_ruby() {
  local pod_bin='' entry='' interpreter='' candidate=''
  local -a candidates=()
  [[ -z "${JOBS_GEMEXT_RUBY:-}" ]] || candidates+=("$JOBS_GEMEXT_RUBY")
  pod_bin="$(whence -p pod 2>/dev/null)" || pod_bin=''
  if [[ -n "$pod_bin" ]]; then
    pod_bin="${pod_bin:A}"
    for entry in "$pod_bin" "${pod_bin:h:h}/libexec/bin/pod"; do
      [[ -f "$entry" ]] || continue
      interpreter="$(/usr/bin/sed -n '1s/^#!//p' "$entry")"
      [[ "$interpreter" == /*/ruby && -x "$interpreter" ]] && candidates+=("$interpreter")
    done
  fi
  candidates+=("$(whence -p ruby 2>/dev/null)" /opt/homebrew/opt/ruby/bin/ruby /usr/local/opt/ruby/bin/ruby)
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if env -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH \
      "$candidate" --disable-gems -rrbconfig -e 'exit(RUBY_ENGINE == "ruby" ? 0 : 1)' >/dev/null 2>&1; then
      print -r -- "$candidate"
      return 0
    fi
  done
  print -u2 -r -- '✖ 没有找到可用的 Ruby，停止原生扩展检查。'
  return 1
}
# 清理仅影响本次 worker 的 Bundler 注入，原调用终端环境保持不变。
jobs_gemext_process() {
  local repair_mode="${1:-check}" ruby_bin=''
  ruby_bin="$(jobs_gemext_find_ruby)" || return 1
  env -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH \
    "$ruby_bin" --disable-gems - "$repair_mode" "${JOBS_GEMEXT_BACKUP_ROOT:-$HOME/.JobsMacEnv/backups/gem-native-extensions}" <<'JOBS_GEMEXT_RUBY'
# >>> Jobs Gem extension Ruby >>>
require 'rubygems'
require 'rbconfig'
require 'fileutils'
require 'tmpdir'
require 'open3'
require 'rubygems/ext'

# 仅重建实际缺失的本平台扩展；保留已安装版本和原 Gem 安装记录。
class JobsGemExtensionRepair
  FEATURES = {
    'io-console' => ['io/console'],
    'erb' => ['erb', 'erb/escape'],
    'prism' => ['prism'],
    'json' => ['json']
  }.freeze
  PRIORITY = %w[bigdecimal io-console json prism psych erb nkf rbs].freeze
  CLEAN_ENV = %w[RUBYOPT RUBYLIB RUBYGEMS_GEMDEPS BUNDLE_GEMFILE BUNDLE_BIN_PATH].freeze

  class << self
    # 按当前 Ruby 的实际 Gem 搜索目录读取完整 spec，健康 / 默认 Gem 不进入修复。
    def missing_specs
      Gem.path.flat_map do |root|
        Dir.glob(File.join(root, 'specifications', '*.gemspec')).map do |path|
          spec = Gem::Specification.load(path)
          next unless spec && !spec.default_gem? && !spec.extensions.empty? && spec.missing_extensions?

          spec
        end.compact
      end.uniq { |spec| File.realpath(spec.loaded_from) }.sort_by do |spec|
        [PRIORITY.index(spec.name) || PRIORITY.length, spec.name, spec.version]
      end
    end

    # 只有确实有待修目标时，才检查本机编译工具链。
    def preflight!
      %w[rubyhdrdir rubyarchhdrdir].each do |key|
        file = key == 'rubyhdrdir' ? 'ruby.h' : 'ruby/config.h'
        raise "当前 Ruby 缺少头文件：#{key}" unless File.file?(File.join(RbConfig::CONFIG.fetch(key), file))
      end
      raise 'make 不可用' unless system('make', '--version', out: File::NULL, err: File::NULL)
      if RUBY_PLATFORM.include?('darwin')
        raise 'Xcode / Command Line Tools 的 clang 不可用' unless system('/usr/bin/xcrun', '--find', 'clang', out: File::NULL, err: File::NULL)
      end
    end

    # 完整备份会被构建器覆盖的 Gem 源目录和当前平台目录，旧平台扩展保持原状。
    def snapshot(spec, backup_root)
      source = spec.full_gem_path
      extension = spec.extension_dir
      raise "Gem 目录不存在或为链接：#{source}" unless File.directory?(source) && !File.symlink?(source)
      raise "Gem 目录不可写：#{source}" unless File.writable?(source) && File.writable?(File.dirname(source))
      ancestor = File.dirname(extension)
      ancestor = File.dirname(ancestor) until File.exist?(ancestor) || ancestor == File.dirname(ancestor)
      raise "扩展目录不可写：#{ancestor}" unless File.writable?(ancestor)
      raise '扩展目标不允许符号链接' if File.symlink?(extension)
      raise '仅支持本机已有的 extconf.rb 扩展源码' unless spec.extensions.all? { |entry| entry.end_with?('extconf.rb') && File.file?(File.join(source, entry)) }

      directory = Dir.mktmpdir("#{spec.full_name.gsub(/[^A-Za-z0-9_.-]/, '_')}-", backup_root)
      saved = {
        :directory => directory,
        :source => source,
        :extension => extension,
        :extension_existed => File.exist?(extension),
        :spec_path => spec.loaded_from,
        :spec_bytes => File.binread(spec.loaded_from)
      }
      FileUtils.cp_r(source, File.join(directory, 'gem'), preserve: true)
      FileUtils.cp_r(extension, File.join(directory, 'extension'), preserve: true) if saved[:extension_existed]
      FileUtils.cp(spec.loaded_from, File.join(directory, 'original.gemspec'), preserve: true)
      File.write(File.join(directory, 'manifest.txt'), saved.reject { |key, _| key == :spec_bytes }.map { |key, value| "#{key}=#{value.inspect}" }.join("\n") + "\n")
      saved
    end

    # 使用 RubyGems 原生构建接口；不经过 Gem 安装器、插件或远程下载。
    def build_spec(spec)
      spec.build_extensions
    end

    # 新 Ruby 进程精确激活原版本，并确认该版本的原生二进制真正载入。
    def verify_spec(spec)
      environment = CLEAN_ENV.each_with_object({}) { |key, result| result[key] = nil }
      environment['GEM_HOME'] = spec.base_dir
      environment['GEM_PATH'] = ([spec.base_dir] + Gem.path).uniq.join(File::PATH_SEPARATOR)
      features = FEATURES.fetch(spec.name, [spec.name.tr('-', '_')])
      code = <<~'VERIFY'
        require 'rubygems'
        name, version, source, extension, *features = ARGV
        gem name, "= #{version}"
        spec = Gem.loaded_specs.fetch(name)
        abort '激活了其它目录的同名 Gem' unless File.realpath(spec.full_gem_path) == File.realpath(source)
        features.each { |feature| require feature }
        binaries = $LOADED_FEATURES.select do |path|
          path.match?(/\.(bundle|so)\z/) &&
            [source, extension].any? { |root| File.expand_path(path).start_with?(File.expand_path(root) + File::SEPARATOR) }
        end
        expected = Dir.glob(File.join(extension, '**', '*.{bundle,so}')).map { |path| File.basename(path) }.uniq
        loaded = binaries.map { |path| File.basename(path) }.uniq
        abort '原生扩展未实际加载完整，或回退到了纯 Ruby 实现' if expected.empty? || !(expected - loaded).empty?
      VERIFY
      output, status = Open3.capture2e(environment, RbConfig.ruby, '--disable-gems', '-e', code,
                                      spec.name, spec.version.to_s, spec.full_gem_path, spec.extension_dir, *features)
      raise "原生扩展加载验证失败：#{output}" unless status.success?
      true
    end

    # 将失败构建留在备份旁，恢复本目标的原目录；不回滚其它已成功目标。
    def restore_snapshot(saved)
      directory = saved.fetch(:directory)
      source = saved.fetch(:source)
      extension = saved.fetch(:extension)
      FileUtils.mv(source, File.join(directory, 'failed-gem')) if File.exist?(source)
      FileUtils.cp_r(File.join(directory, 'gem'), source, preserve: true)
      FileUtils.mv(extension, File.join(directory, 'failed-extension')) if File.exist?(extension)
      if saved[:extension_existed]
        FileUtils.mkdir_p(File.dirname(extension))
        FileUtils.cp_r(File.join(directory, 'extension'), extension, preserve: true)
      end
      if !File.file?(saved[:spec_path]) || File.binread(saved[:spec_path]) != saved[:spec_bytes]
        FileUtils.cp(File.join(directory, 'original.gemspec'), saved[:spec_path], preserve: true)
      end
    end

    # 每个目标先备份，构建或验证失败则恢复并明确保留排查材料。
    def repair_spec(spec, backup_root)
      saved = snapshot(spec, backup_root)
      puts "➤ 重建 #{spec.full_name}；备份：#{saved[:directory]}"
      build_spec(spec)
      raise '构建结束后仍缺少当前平台完成标记' unless File.file?(spec.gem_build_complete_path)
      raise 'Gem 安装记录被意外改写' unless File.binread(spec.loaded_from) == saved[:spec_bytes]
      verify_spec(spec)
      File.write(File.join(saved[:directory], 'result.txt'), "success\n")
      puts "✔ #{spec.full_name}：当前平台扩展已构建并实际加载。"
      true
    rescue StandardError => error
      warn "✖ #{spec.full_name}：#{error.class}: #{error.message}"
      if saved
        File.write(File.join(saved[:directory], 'result.txt'), "failed\n#{error.class}: #{error.message}\n")
        begin
          restore_snapshot(saved)
          warn "⚠ 已恢复该 Gem 原目录；排查材料：#{saved[:directory]}"
        rescue StandardError => restore_error
          warn "✖ 自动恢复失败：#{restore_error.message}；完整备份：#{saved[:directory]}"
          raise
        end
      end
      false
    end

    # 持有修复锁后重新检测；健康设备不写备份、不重复编译。
    def run(mode:, backup_root:, runtime_label: nil)
      raise '未知执行模式' unless %w[check repair].include?(mode)
      puts "ℹ Ruby #{RUBY_VERSION}；平台 #{Gem::Platform.local}；运行时 #{runtime_label || RbConfig.ruby}"
      targets = missing_specs
      puts "ℹ 当前平台缺失原生扩展：#{targets.length} 个已安装版本。"
      targets.each { |spec| puts "  - #{spec.full_name}" }
      return 0 if targets.empty? || mode == 'check'

      preflight!
      FileUtils.mkdir_p(backup_root)
      File.open(File.join(backup_root, '.repair.lock'), File::RDWR | File::CREAT, 0o600) do |lock|
        raise '另一个 Gem 扩展修复正在运行' unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        targets = missing_specs
        failed = targets.reject { |spec| repair_spec(spec, backup_root) }
        remaining = missing_specs
        puts "ℹ 修复成功 #{targets.length - failed.length}；失败 #{failed.length}；仍缺失 #{remaining.length}。"
        return failed.empty? && remaining.empty? ? 0 : 1
      end
    rescue StandardError => error
      warn "✖ 扩展修复停止：#{error.class}: #{error.message}"
      1
    end

    # 单文件 Shell 通过 stdin 执行；加载测试中的类定义不会启动修复。
    def run_cli
      $stdout.sync = true
      $stderr.sync = true
      exit run(mode: ARGV.fetch(0), backup_root: File.expand_path(ARGV.fetch(1)))
    end
  end
end

JobsGemExtensionRepair.run_cli if $PROGRAM_NAME == '-'
# <<< Jobs Gem extension Ruby <<<
JOBS_GEMEXT_RUBY
}
# <<< Jobs Gem extension repair <<<
# 将原生扩展诊断同步写入 update 日志，并传播 worker 退出码。
jobs_update_repair_gem_extensions() {
  jobs_gemext_process repair 2>&1 | /usr/bin/tee -a "$LOG_FILE"
  local -a stage_codes=("${pipestatus[@]}")
  (( stage_codes[1] == 0 )) || return "${stage_codes[1]}"
  return "${stage_codes[2]}"
}
# 封装 jobs_update_ruby_base 对应的独立处理逻辑。
jobs_update_ruby_base() {
  local result=0
  if jobs_update_has rbenv; then
    ensure_rbenv_init
    jobs_update_run_cmd "rbenv rehash" rbenv rehash || true
  fi

  jobs_update_run_cmd '修复当前 CocoaPods / Ruby 缺失的原生 Gem 扩展' jobs_update_repair_gem_extensions || result=1
  if jobs_update_has gem; then
    jobs_update_run_cmd "gem update --system" gem update --system || true
    jobs_update_run_cmd "gem update" gem update || true
  else
    warn_echo "未检测到 gem，跳过 RubyGems 更新"
  fi
  jobs_update_run_cmd '复检更新后的原生 Gem 扩展' jobs_update_repair_gem_extensions || result=1
  return "$result"
}
# 记录选源诊断，不将可能包含凭据的 curl/git 原始错误写入日志。
jobs_update_specs_log() {
  print -r -- "$1" >&2
  print -r -- "$1" >> "$LOG_FILE"
}
# 校验环境变量中的整数时限，避免无效参数关闭超时保护。
jobs_update_specs_timeout() {
  local value="$1" maximum="$2"
  if [[ "$value" != <-> || ${#value} -gt 3 ]]; then
    jobs_update_specs_log "⚠ CocoaPods 时限必须是 1..${maximum} 的整数：$value"
    return 1
  fi
  REPLY=$(( 10#$value ))
  if (( REPLY < 1 || REPLY > maximum )); then
    jobs_update_specs_log "⚠ CocoaPods 时限超出 1..${maximum}：$value"
    return 1
  fi
  return 0
}
# 终止本次启动的进程树，覆盖 Git HTTP 传输与 CocoaPods 子进程。
jobs_update_specs_terminate_tree() {
  local process_id="$1" child_id child_list
  [[ "$process_id" == <-> && "$process_id" -gt 1 ]] || return 0
  child_list="$(/bin/ps -axo pid=,ppid= | /usr/bin/awk -v parent="$process_id" '$2 == parent {print $1}')"
  for child_id in "${(@f)child_list}"; do
    [[ -n "$child_id" ]] && jobs_update_specs_terminate_tree "$child_id"
  done
  kill -KILL "$process_id" 2>/dev/null || true
}
# 只回收当前子流程自己的进程和专属临时目录。
jobs_update_specs_cleanup() {
  local process_id
  for process_id in "${specs_pids[@]}"; do
    jobs_update_specs_terminate_tree "$process_id"
    wait "$process_id" 2>/dev/null || true
  done
  if [[ -d "$specs_work_dir" && "${specs_work_dir:t}" == jobs-update-specs.* ]]; then
    /bin/rm -r -- "$specs_work_dir"
  fi
}
# 校验完整 podspec JSON，拒绝门户 HTML、空响应和普通 JSON 假阳性。
jobs_update_specs_validate_payload() {
  local payload="$1" payload_name payload_version
  [[ -s "$payload" ]] || return 1
  /usr/bin/plutil -convert xml1 -o /dev/null -- "$payload" >/dev/null 2>&1 || return 1
  payload_name="$(/usr/bin/plutil -extract name raw -o - -- "$payload" 2>/dev/null)" || return 1
  payload_version="$(/usr/bin/plutil -extract version raw -o - -- "$payload" 2>/dev/null)" || return 1
  [[ "$payload_name" == AFNetworking && "$payload_version" == 4.0.1 ]]
}
# 对同一固定样本发送真实 GET；Git 候选额外验证 Specs 的 Git 协议。
jobs_update_specs_probe() {
  local candidate="$1" sample_url duration command_result=0
  local sample_path='Specs/a/7/5/AFNetworking/4.0.1/AFNetworking.podspec.json'
  sample_url="https://cdn.cocoapods.org/${sample_path}"
  [[ "$candidate" == git ]] && sample_url="https://raw.githubusercontent.com/CocoaPods/Specs/master/${sample_path}"
  curl -q --silent --show-error --fail --location \
    --connect-timeout "$specs_connect_timeout" --max-time "$specs_probe_timeout" \
    --output "$specs_work_dir/$candidate.json" --write-out '%{time_total}' \
    "$sample_url" > "$specs_work_dir/$candidate.time" 2> "$specs_work_dir/$candidate.error" || command_result=$?
  if (( command_result != 0 )); then
    print -r -- "podspec GET 失败，curl 退出码：$command_result。" > "$specs_work_dir/$candidate.reason"
    return 1
  fi
  if ! jobs_update_specs_validate_payload "$specs_work_dir/$candidate.json"; then
    print -r -- '不是完整有效的 AFNetworking 4.0.1 podspec。' > "$specs_work_dir/$candidate.reason"
    return 1
  fi
  duration="$(< "$specs_work_dir/$candidate.time")"
  [[ ${#duration} -le 20 && "$duration" =~ '^[0-9]+([.][0-9]+)?$' ]] || return 1
  if [[ "$candidate" == git ]]; then
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false GCM_INTERACTIVE=never \
      git -c credential.interactive=false ls-remote --exit-code https://github.com/CocoaPods/Specs.git HEAD \
      > "$specs_work_dir/git.head" 2> "$specs_work_dir/git.error" || command_result=$?
    if (( command_result != 0 )) || ! /usr/bin/grep -Eq '^[0-9a-fA-F]{40,64}[[:space:]]+HEAD$' "$specs_work_dir/git.head"; then
      print -r -- "Git ls-remote 未通过，退出码：$command_result。" > "$specs_work_dir/git.reason"
      return 1
    fi
  fi
  print -r -- "$duration" > "$specs_work_dir/$candidate.result"
}
# 为一个候选的 HTTP 和 Git 全过程设置墙钟时限，并回收看门狗。
jobs_update_specs_run_candidate() (
  trap - EXIT INT TERM
  local candidate="$1" worker_pid timer_pid candidate_result=0
  jobs_update_specs_probe "$candidate" &
  worker_pid=$!
  (
    /bin/sleep "$specs_probe_timeout"
    print -r -- '候选整体超时，已终止传输进程。' > "$specs_work_dir/$candidate.timeout"
    jobs_update_specs_terminate_tree "$worker_pid"
  ) &
  timer_pid=$!
  wait "$worker_pid" 2>/dev/null || candidate_result=$?
  jobs_update_specs_terminate_tree "$timer_pid"
  wait "$timer_pid" 2>/dev/null || true
  if [[ -f "$specs_work_dir/$candidate.timeout" ]]; then
    /bin/mv -- "$specs_work_dir/$candidate.timeout" "$specs_work_dir/$candidate.reason"
    /bin/rm -f -- "$specs_work_dir/$candidate.result"
    return 1
  fi
  return "$candidate_result"
)
# 移植 Swift 挂载脚本的同样本实测策略；双源失败时保留缓存并拒绝联网刷新。
jobs_update_specs_select_source() (
  local specs_mode="${JOBS_SPECS_SOURCE:-auto}" REPLY
  local git_registered="${1:-1}"
  local specs_probe_timeout specs_connect_timeout specs_work_dir candidate process_id reason selected
  local -a specs_pids=()
  case "$specs_mode" in
    auto|cdn|git) ;;
    *) jobs_update_specs_log '⚠ JOBS_SPECS_SOURCE 仅支持 auto、cdn、git。'; return 1 ;;
  esac
  jobs_update_specs_timeout "${JOBS_SPECS_PROBE_TIMEOUT:-8}" 30 || return 1
  specs_probe_timeout="$REPLY"
  jobs_update_specs_timeout "${JOBS_SPECS_CONNECT_TIMEOUT:-2}" 30 || return 1
  specs_connect_timeout="$REPLY"
  (( specs_connect_timeout > specs_probe_timeout )) && specs_connect_timeout="$specs_probe_timeout"
  jobs_update_has curl || { jobs_update_specs_log '⚠ curl 不可用，保留 Specs 缓存。'; return 1; }
  specs_work_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-update-specs.XXXXXXXX")" || return 1
  trap jobs_update_specs_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  jobs_update_specs_log "ℹ CocoaPods 同样本网络探测：模式 ${specs_mode}，两源并发，每源整体限时 ${specs_probe_timeout}s。"
  for candidate in cdn git; do
    jobs_update_specs_run_candidate "$candidate" &
    specs_pids+=("$!")
  done
  for process_id in "${specs_pids[@]}"; do
    wait "$process_id" 2>/dev/null || true
  done
  specs_pids=()
  for candidate in cdn git; do
    if [[ -f "$specs_work_dir/$candidate.result" ]]; then
      jobs_update_specs_log "✔ $candidate 可用，相同 podspec GET 耗时：$(< "$specs_work_dir/$candidate.result")s。"
    else
      reason='没有有效结果。'
      [[ -s "$specs_work_dir/$candidate.reason" ]] && reason="$(< "$specs_work_dir/$candidate.reason")"
      jobs_update_specs_log "⚠ $candidate 不可用：$reason"
    fi
  done
  if [[ "$specs_mode" != auto ]]; then
    selected="$specs_mode"
  elif [[ -f "$specs_work_dir/cdn.result" && -f "$specs_work_dir/git.result" ]]; then
    selected=cdn
    if (( $(< "$specs_work_dir/git.result") < $(< "$specs_work_dir/cdn.result") * 0.85 )); then
      selected=git
    fi
  elif [[ -f "$specs_work_dir/cdn.result" ]]; then
    selected=cdn
  else
    selected=git
  fi
  if [[ "$specs_mode" == auto && "$selected" == git && "$git_registered" == 0 && -f "$specs_work_dir/cdn.result" ]]; then
    selected=cdn
    jobs_update_specs_log 'ℹ Git 小文件更快但尚无本地 Git Specs；改用已通过探测的 CDN，避免冷克隆。'
  fi
  if [[ ! -f "$specs_work_dir/$selected.result" ]]; then
    jobs_update_specs_log '⚠ 本次没有通过探测的所选源；保留现有缓存，跳过 Specs 刷新。网络尚未恢复。'
    return 1
  fi
  jobs_update_specs_log "✔ 本次只刷新 $selected 公共源；此探测不保证大仓库克隆或具体 Pod 源码下载成功。"
  print -r -- "$selected"
)
# 给真实源刷新设置独立总时限，禁止凭据交互，不改全局 Git 或代理配置。
jobs_update_specs_run_cmd() (
  local desc="$1" REPLY specs_update_timeout specs_work_dir worker_pid timer_pid command_result=0
  local -a specs_pids=()
  shift
  jobs_update_specs_timeout "${JOBS_SPECS_UPDATE_TIMEOUT:-120}" 900 || return 1
  specs_update_timeout="$REPLY"
  specs_work_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-update-specs.XXXXXXXX")" || return 1
  trap jobs_update_specs_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  jobs_update_run_cmd "$desc（总时限 ${specs_update_timeout}s）" env \
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/false GCM_INTERACTIVE=never \
    GIT_HTTP_LOW_SPEED_LIMIT=1024 GIT_HTTP_LOW_SPEED_TIME=30 "$@" &
  worker_pid=$!
  specs_pids+=("$worker_pid")
  (
    /bin/sleep "$specs_update_timeout"
    : > "$specs_work_dir/refresh.timeout"
    jobs_update_specs_terminate_tree "$worker_pid"
  ) &
  timer_pid=$!
  specs_pids+=("$timer_pid")
  wait "$worker_pid" 2>/dev/null || command_result=$?
  jobs_update_specs_terminate_tree "$timer_pid"
  wait "$timer_pid" 2>/dev/null || true
  specs_pids=()
  if [[ -f "$specs_work_dir/refresh.timeout" ]]; then
    warn_echo "Specs 刷新超过 ${specs_update_timeout}s，已停止本次进程；保留现有源与缓存，未完成刷新。"
    return 124
  fi
  return "$command_result"
)
# 在独立 Ruby 中复用工程网络模块，只输出状态及私有 NUL 环境载荷。
jobs_update_pod_network_payload() {
  local payload_path="$1" ruby_bin
  ruby_bin="$(jobs_gemext_find_ruby)" || return 1
  env -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH \
    "$ruby_bin" - "$payload_path" "$PWD" 2>/dev/null <<'JOBS_UPDATE_POD_NETWORK_RUBY'
# >>> Jobs CocoaPods network module >>>
# frozen_string_literal: true

require 'uri'

# 仅为本次依赖安装复用真实可用的 Git 链路，不改系统或全局 Git 配置。
module JobsCocoaPodsNetwork
  PROBE_URL = 'https://github.com/andreamazz/AMPopTip.git'.freeze
  PROBE_REF = 'refs/tags/4.12.0'.freeze
  DEFAULT_PROBE_TIMEOUT = 6
  OUTPUT_LIMIT = 4096
  PROXY_KEYS = %w[https_proxy HTTPS_PROXY http_proxy HTTP_PROXY all_proxy ALL_PROXY].freeze
  GIT_PROXY_KEY = 'http.https://github.com/.proxy'.freeze

  module_function

  # Podfile 在 Specs 选择前调用；查询命令与重复解析都不额外联网。
  def apply!(project_root:, probe: nil)
    return :skipped if ENV['JOBS_POD_NETWORK_ADAPT'] == '0' || probe == false || (probe.nil? && !dependency_command?)

    project_root = File.expand_path(project_root)
    @results ||= {}
    return @results[project_root] if @results.key?(project_root)

    timeout = probe_timeout
    runner = probe.respond_to?(:call) ? probe : method(:git_route_usable?)
    explicit = ENV['JOBS_POD_PROXY_URL'].to_s.strip
    if !explicit.empty? && valid_proxy_url?(explicit)
      route = proxy_route(:explicit, explicit)
      return remember_route(project_root, route) if route && usable?(runner, route, project_root, timeout)

      log('显式 JOBS_POD_PROXY_URL 未通过 Git tag 探测，继续检查当前链路。')
    elsif !explicit.empty?
      log('JOBS_POD_PROXY_URL 格式无效，继续检查当前链路；未输出代理内容。')
    end

    inherited = { kind: :inherited, environment: {} }
    return remember_route(project_root, inherited) if usable?(runner, inherited, project_root, timeout)

    routes = system_proxy_routes(timeout).reject { |route| route[:proxy] == explicit }
    results = routes.map do |route|
      Thread.new { [route, usable?(runner, route, project_root, timeout)] }
    end.map(&:value)
    selected = results.find { |_route, successful| successful }
    return remember_route(project_root, selected.first) if selected

    log('当前链路和已配置代理均未通过 Git tag 探测；继续交给源码归档回退及 CocoaPods，不代表安装成功。')
    @results[project_root] = :unavailable
  rescue StandardError
    log('网络适配未完成，保留现有环境继续安装；未输出可能含凭据的错误内容。')
    :unavailable
  end

  # 只接受真正的 CocoaPods 安装或升级，ipc/spec 等查询不触发网络。
  def dependency_command?
    command = ARGV.find { |argument| !argument.start_with?('-') }
    File.basename($PROGRAM_NAME) == 'pod' && %w[install update].include?(command)
  end

  # 对每个独立进程组设置短上限，系统候选并发，共享同一轮等待时间。
  def probe_timeout
    value = ENV['JOBS_POD_NETWORK_PROBE_TIMEOUT'] || ENV['JOB_POD_NETWORK_PROBE_TIMEOUT']
    value.to_s.match?(/\A\d+\z/) && (1..30).cover?(value.to_i) ? value.to_i : DEFAULT_PROBE_TIMEOUT
  end

  # 显式环境 URL 可以包含凭据，但控制字符、无效端口与未知协议被拒绝。
  def valid_proxy_url?(value)
    return false if value.match?(/[\x00-\x20\x7f]/)

    uri = URI.parse(value)
    %w[http https socks5 socks5h].include?(uri.scheme) &&
      uri.host && !uri.host.empty? && (1..65_535).cover?(uri.port.to_i) &&
      ['', '/'].include?(uri.path.to_s) && !uri.query && !uri.fragment
  rescue URI::Error, ArgumentError
    false
  end

  # 仅读取 macOS 已开启的手工代理，不执行 PAC、不猜端口。
  def system_proxy_routes(timeout)
    return [] unless File.executable?('/usr/sbin/scutil')

    output, successful, = run_bounded({}, ['/usr/sbin/scutil', '--proxy'], nil, [timeout, 1].min)
    return [] unless successful

    parse_system_proxies(output).each_with_object([]) do |(kind, proxy), routes|
      route = proxy_route(kind, proxy)
      routes << route if route
    end
  end

  # scutil 的 HTTPSProxy 表示 HTTP CONNECT；SOCKS 使用远端 DNS。
  def parse_system_proxies(output)
    values = {}
    depth = 0
    output.each_line do |line|
      match = line.match(/\A\s*(HTTPSEnable|HTTPSProxy|HTTPSPort|HTTPEnable|HTTPProxy|HTTPPort|SOCKSEnable|SOCKSProxy|SOCKSPort)\s*:\s*(.*?)\s*\z/) if depth <= 1
      values[match[1]] = match[2] if match
      depth += line.count('{') - line.count('}')
    end
    routes = []
    %w[HTTPS HTTP SOCKS].each do |kind|
      next unless values["#{kind}Enable"] == '1'

      host = values["#{kind}Proxy"].to_s
      port = values["#{kind}Port"].to_s
      next unless host.match?(/\A[A-Za-z0-9._:\[\]-]+\z/) && port.match?(/\A\d+\z/)

      host = "[#{host}]" if host.include?(':') && !host.start_with?('[')
      proxy = "#{kind == 'SOCKS' ? 'socks5h' : 'http'}://#{host}:#{port}"
      routes << ["system_#{kind.downcase}".to_sym, proxy] if valid_proxy_url?(proxy)
    end
    routes.uniq { |_kind, proxy| proxy }
  end

  # 追加 GitHub 范围的临时配置，既有私有域配置与 NO_PROXY 均保留。
  def proxy_route(kind, proxy)
    count = ENV.fetch('GIT_CONFIG_COUNT', '0')
    return nil unless count.match?(/\A\d+\z/)

    index = count.to_i
    environment = PROXY_KEYS.each_with_object({}) { |key, result| result[key] = proxy }
    environment['GIT_CONFIG_COUNT'] = (index + 1).to_s
    environment["GIT_CONFIG_KEY_#{index}"] = GIT_PROXY_KEY
    environment["GIT_CONFIG_VALUE_#{index}"] = proxy
    { kind: kind, proxy: proxy, environment: environment }
  end

  # 探测失败只返回状态，原始 stderr 与代理 URL 不进入日志。
  def usable?(runner, route, project_root, timeout)
    runner.call(environment: route[:environment].dup, project_root: project_root, timeout: timeout) == true
  rescue StandardError
    false
  end

  # Git 协议必须返回指定 tag 的对象 ID，HTTP 首页成功不能代替此检查。
  def git_route_usable?(environment:, project_root:, timeout:)
    environment = environment.merge(
      'GIT_TERMINAL_PROMPT' => '0', 'GCM_INTERACTIVE' => 'never',
      'GIT_ASKPASS' => '/usr/bin/false', 'SSH_ASKPASS' => '/usr/bin/false'
    )
    output, successful, = run_bounded(
      environment, ['git', '-c', 'credential.interactive=false', 'ls-remote', '--exit-code', PROBE_URL, PROBE_REF], project_root, timeout
    )
    successful && output.lines.any? do |line|
      line.match?(/\A[0-9a-fA-F]{40}(?:[0-9a-fA-F]{24})?\s+#{Regexp.escape(PROBE_REF)}\s*\z/)
    end
  end

  # 当前 pod 进程及其子进程继承代理；退出时恢复原环境，不写磁盘配置。
  def remember_route(project_root, route)
    unless route[:kind] == :inherited
      @original_environment ||= {}
      route[:environment].each do |key, value|
        @original_environment[key] = ENV[key] unless @original_environment.key?(key)
        ENV[key] = value
      end
      unless @restore_registered
        at_exit { restore! }
        @restore_registered = true
      end
    end
    message = case route[:kind]
              when :inherited then '已复用当前 Git 下载链路。'
              when :explicit then '已验证显式 JOBS_POD_PROXY_URL，仅本次 pod 进程使用。'
              else '已验证并临时继承 macOS 已开启的系统代理，仅本次 pod 进程使用。'
              end
    log(message)
    @results[project_root] = route[:kind] == :inherited ? :inherited : :proxy
  end

  # 隔离测试及进程退出共用恢复入口，只还原本模块实际覆盖的环境项。
  def restore!
    (@original_environment || {}).each { |key, value| ENV[key] = value }
    @original_environment = {}
    @results = {}
    nil
  end

  # 输出有上限且 stderr 丢弃；退出上限包含继承输出管道的子进程。
  def run_bounded(environment, command, project_root, timeout)
    reader, writer = IO.pipe
    options = { in: File::NULL, out: writer, err: File::NULL, pgroup: true }
    options[:chdir] = project_root if project_root
    pid = Process.spawn(environment, *command, options)
    writer.close
    waiter = Process.detach(pid)
    capture = { text: ''.dup, overflow: false }
    output_reader = Thread.new { capture_stdout(reader, capture) }
    deadline = monotonic_time + timeout
    timed_out = false
    while waiter.alive? || output_reader.alive?
      if monotonic_time >= deadline
        timed_out = true
        signal_group('TERM', pid)
        (output_reader.alive? ? output_reader : waiter).join(0.1)
        signal_group('KILL', pid)
        break
      end
      (waiter.alive? ? waiter : output_reader).join([deadline - monotonic_time, 0.02].min.clamp(0, 0.02))
    end
    waiter.join(0.2)
    reader.close unless reader.closed?
    output_reader.join(0.2)
    successful = !timed_out && !capture[:overflow] && !waiter.alive? && waiter.value.success?
    [capture[:text], successful, timed_out]
  rescue StandardError
    ['', false, false]
  ensure
    [reader, writer].compact.each { |stream| stream.close unless stream.closed? }
    if pid && (waiter.nil? || waiter.alive? || (output_reader && output_reader.alive?))
      signal_group('KILL', pid)
    end
    output_reader.join(0.2) if output_reader
  end

  # 始终读完有界缓冲，避免子进程因 stdout 写满而卡住。
  def capture_stdout(stream, capture)
    loop do
      chunk = stream.readpartial(1024)
      remaining = OUTPUT_LIMIT - capture[:text].bytesize
      capture[:text] << chunk.byteslice(0, remaining) if remaining.positive?
      capture[:overflow] = true if chunk.bytesize > remaining
    end
  rescue EOFError, IOError
    nil
  end

  # 独立进程组连同 Git helper 一起退出，已结束的进程属于正常竞态。
  def signal_group(signal, pid)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  # 单调时钟避免系统校时改变探测时限。
  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # 日志只陈述链路状态，不泄露代理地址、凭据或原始子进程错误。
  def log(message)
    $stderr.puts("[Jobs Pod 网络] #{message}")
  end
end
# <<< Jobs CocoaPods network module <<<

# >>> Jobs update Pod network handoff >>>
begin
  original_environment = ENV.to_h
  result = JobsCocoaPodsNetwork.apply!(project_root: ARGV.fetch(1), probe: true)
  raise 'unknown network result' unless %i[skipped inherited proxy unavailable].include?(result)

  changes = if result == :proxy
              ENV.select do |key, value|
                (JobsCocoaPodsNetwork::PROXY_KEYS.include?(key) || key.match?(/\AGIT_CONFIG_(?:COUNT|KEY_\d+|VALUE_\d+)\z/)) &&
                  original_environment[key] != value
              end
            else
              {}
            end
  File.open(ARGV.fetch(0), 'wb', 0o600) do |file|
    changes.each { |key, value| file.write("#{key}\0#{value}\0") }
  end
  puts result
rescue StandardError
  exit 1
end
# <<< Jobs update Pod network handoff <<<
JOBS_UPDATE_POD_NETWORK_RUBY
}
# 先完整校验受控键值，再导出；NUL 载荷不会作为 Shell 代码执行。
jobs_update_pod_network_apply_payload() {
  local payload_path="$1" route_key='' route_value='' index
  local -a route_keys=() route_values=()
  while true; do
    route_key=''
    IFS= read -r -d '' route_key || { [[ -z "$route_key" ]] && break; return 1; }
    IFS= read -r -d '' route_value || return 1
    case "$route_key" in
      https_proxy|HTTPS_PROXY|http_proxy|HTTP_PROXY|all_proxy|ALL_PROXY|GIT_CONFIG_COUNT|GIT_CONFIG_KEY_<->|GIT_CONFIG_VALUE_<->) ;;
      *) return 1 ;;
    esac
    route_keys+=("$route_key")
    route_values+=("$route_value")
  done < "$payload_path"
  for (( index=1; index<=${#route_keys}; index++ )); do
    export "${route_keys[$index]}=${route_values[$index]}"
  done
}
# 子流程退出时删除可能含认证值的私有载荷，不影响其它临时文件。
jobs_update_pod_network_cleanup() {
  if [[ -n "$jobs_pod_route_payload" && "${jobs_pod_route_payload:t}" == jobs-update-pod-route.* ]]; then
    /bin/rm -f -- "$jobs_pod_route_payload"
  fi
}
# 在本次 Specs 作用域内准备已有代理，失败时保留原环境继续真实选源。
jobs_update_pod_network_prepare() {
  local route_result=''
  jobs_pod_route_payload="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/jobs-update-pod-route.XXXXXXXX")" || {
    jobs_update_specs_log '⚠ 无法创建私有网络载荷，沿用当前环境继续 Specs 实测。'
    return 0
  }
  route_result="$(jobs_update_pod_network_payload "$jobs_pod_route_payload")" || route_result=failed
  case "$route_result" in
    proxy)
      if jobs_update_pod_network_apply_payload "$jobs_pod_route_payload"; then
        jobs_update_specs_log '✔ 已验证已有代理，本次 Specs 探测与 repo 命令继承相同环境。'
      else
        jobs_update_specs_log '⚠ 网络载荷校验失败，沿用原环境继续 Specs 实测；未认定代理可用。'
      fi
      ;;
    inherited) jobs_update_specs_log 'ℹ 已验证并复用当前 Git 链路，继续 Specs 实测。' ;;
    skipped) jobs_update_specs_log 'ℹ 已关闭 CocoaPods 代理适配，沿用当前环境进行 Specs 实测。' ;;
    unavailable) jobs_update_specs_log '⚠ 当前 Git 链路和已配置代理未通过验证，沿用原环境继续 Specs 实测；网络尚未恢复。' ;;
    *) jobs_update_specs_log '⚠ CocoaPods 网络适配未完成，沿用原环境继续 Specs 实测；未认定代理可用。' ;;
  esac
  jobs_update_pod_network_cleanup
  jobs_pod_route_payload=''
}
# 同一子 Shell 内准备代理、选择公共源并刷新；返回后父环境完全不变。
jobs_update_cocoapods_repos() (
  local selected source_list source_name='' source_url='' row repo_name='' cdn_repo='' git_repo=''
  local git_registered=0 result=0 jobs_pod_route_payload=''
  trap jobs_update_pod_network_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  jobs_update_pod_network_prepare
  source_list="$(pod repo list --no-ansi 2>/dev/null)" || { warn_echo '无法读取 CocoaPods 源清单，停止 Specs 刷新。'; return 1; }
  for row in "${(@f)source_list}"; do
    if [[ "$row" == '- URL:'* ]]; then
      source_url="${row#'- URL:'}"
      source_url="${source_url#"${source_url%%[![:space:]]*}"}"
      source_url="${source_url:l}"
      while [[ "$source_url" == */ ]]; do
        source_url="${source_url%/}"
      done
      if [[ -n "$source_name" && "$source_name" != -* && "$source_name" != *$'\t'* ]]; then
        case "$source_url" in
          https://cdn.cocoapods.org) [[ -n "$cdn_repo" ]] || cdn_repo="$source_name" ;;
          https://github.com/cocoapods/specs.git|https://github.com/cocoapods/specs)
            [[ -n "$git_repo" ]] || git_repo="$source_name"
            ;;
        esac
      fi
    elif [[ -n "$row" && "$row" != '- '* && "$row" != [[:space:]]* ]]; then
      source_name="$row"
    fi
  done
  [[ -n "$git_repo" ]] && git_registered=1
  selected="$(jobs_update_specs_select_source "$git_registered")" || return 1
  case "$selected" in
    cdn) repo_name="$cdn_repo" ;;
    git) repo_name="$git_repo" ;;
    *) return 1 ;;
  esac
  if [[ -z "$repo_name" ]]; then
    if [[ "$selected" == git ]]; then
      warn_echo '所选 GitHub Specs 尚无本地源；升级入口不冷克隆巨大 Specs 仓库，本次未刷新。'
      return 1
    fi
    repo_name='jobs-public-cdn'
    while print -r -- "$source_list" | /usr/bin/grep -Fxq -- "$repo_name"; do
      repo_name="${repo_name}-cdn"
    done
    jobs_update_specs_run_cmd '登记官方 CDN（保留已有源）' pod repo add-cdn "$repo_name" https://cdn.cocoapods.org/ || return $?
  fi
  jobs_update_specs_run_cmd "刷新 CocoaPods 公共源：$repo_name" pod repo update "$repo_name" || result=$?
  return "$result"
)
# 按已安装的包管理器更新 CocoaPods，再独立按网络实测刷新公共规格源。
jobs_update_gem_cocoapods() {
  local gem_home='' brew_bin='' brew_prefix='' pod_bin='' result=0 brew_managed=0 gem_installed=0
  pod_bin="$(whence -p pod 2>/dev/null)" || pod_bin=''
  if jobs_update_has gem && gem list -i '^cocoapods$' >/dev/null 2>&1; then
    gem_installed=1
  fi
  brew_bin="$(find_brew_bin)" || brew_bin=''
  if [[ -n "$brew_bin" ]] && "$brew_bin" list --formula --versions cocoapods >/dev/null 2>&1; then
    brew_prefix="$("$brew_bin" --prefix cocoapods 2>/dev/null)" || brew_prefix=''
    if [[ -z "$pod_bin" || ( -n "$brew_prefix" && "${pod_bin:A}" == "${brew_prefix:A}/"* ) ]]; then
      brew_managed=1
    elif (( gem_installed == 0 )); then
      warn_echo 'Homebrew 已安装 CocoaPods，但当前 pod 不属于该 formula；无法确认工具归属，跳过本体升级。'
      result=1
    fi
  fi
  if (( brew_managed == 1 )); then
    if (( JOBS_UPDATE_COCOAPODS_BREW_UPDATED == 1 )); then
      info_echo 'CocoaPods 已在本轮 Homebrew formula 阶段升级，继续维护规格源。'
    elif jobs_update_run_brew_adaptive_cmd '升级 Homebrew CocoaPods' plain "$brew_bin" upgrade cocoapods; then
      JOBS_UPDATE_COCOAPODS_BREW_UPDATED=1
    else
      result=1
    fi
  fi
  if (( brew_managed == 0 && gem_installed == 1 )); then
    gem_home="$(gem env home 2>/dev/null || true)"
    if [[ -n "$gem_home" && -w "$gem_home" ]]; then
      jobs_update_run_cmd "更新 gem 包 cocoapods" gem update cocoapods || result=1
    else
      jobs_update_run_sudo_cmd "更新系统 gem 包 cocoapods" gem update cocoapods || result=1
    fi
  elif (( brew_managed == 0 && result == 0 )); then
    warn_echo '当前 Homebrew / RubyGems 未登记 CocoaPods，跳过工具升级；已有 pod 命令仍可维护规格源。'
  fi
  if jobs_update_has pod; then
    if jobs_update_run_cmd '复检 CocoaPods 所用 Ruby 的原生扩展' jobs_update_repair_gem_extensions; then
      jobs_update_cocoapods_repos || result=1
    else
      warn_echo '原生扩展修复未完成，跳过本次规格源刷新。'
      result=1
    fi
  else
    warn_echo '当前 PATH 找不到 pod，无法刷新规格源；请先检查 CocoaPods 安装与 PATH。'
    result=1
  fi
  return "$result"
}
# 封装 jobs_update_python_base 对应的独立处理逻辑。
jobs_update_python_base() {
  jobs_envupdate_python_preflight confirmed || return 1 # Python 更新项获确认后准备内嵌运行时。
  if jobs_update_has pyenv; then
    if pyenv commands | grep -qx update; then
      jobs_update_run_cmd "pyenv update" pyenv update || true
    else
      warn_echo "pyenv-update 插件不存在，跳过 pyenv update"
    fi
    jobs_update_run_cmd "pyenv rehash" pyenv rehash || true
  fi

  if jobs_update_has pipx; then
    jobs_update_run_cmd "pipx upgrade-all" pipx upgrade-all || true
  fi

  jobs_update_run_cmd "Homebrew Python pip 自升级" "$JOBS_PYTHON_BIN" -m pip install --upgrade pip || true
}
# 封装 jobs_update_pub_cache 对应的独立处理逻辑。
jobs_update_pub_cache() {
  if jobs_update_has dart; then
    jobs_update_run_cmd "Dart pub global list" dart pub global list || true
    jobs_update_run_cmd "Dart pub cache repair" dart pub cache repair || true
  else
    warn_echo "未检测到 dart，跳过 Dart pub cache 更新"
  fi
}
# ---------- 更新项：Git / JobsKits / 手动下载页 ----------
jobs_update_git_lfs_init() {
  if ! jobs_update_has git; then
    warn_echo "git 不存在，无法刷新 Git LFS。请先安装 Xcode Command Line Tools 或 git。"
    return 0
  fi

  if ! git lfs version >/dev/null 2>&1; then
    warn_echo "git-lfs 不存在，无法初始化。请先运行 install.command 安装 brew formula：git-lfs。"
    return 0
  fi

  jobs_update_run_cmd "初始化 / 刷新 Git LFS" git lfs install || true
  jobs_update_run_cmd "配置 Git core.compression=0" git config --global core.compression 0 || true
  jobs_update_run_cmd "配置 Git http.postBuffer=524288000" git config --global http.postBuffer 524288000 || true
}
# 封装 jobs_update_repo 对应的独立处理逻辑。
jobs_update_repo() {
  local repo_name="$1"
  local repo_url="$2"
  local target_dir="$3"

  if [[ -d "${target_dir}/.git" ]]; then
    jobs_update_run_sh "更新仓库：${repo_name}" "cd '${target_dir}' && git pull --ff-only" || true
    return 0
  fi

  warn_echo "未检测到仓库：${target_dir}"
  warm_echo "update.command 不负责克隆新仓库。需要补装时请运行 install.command。"
  gray_echo "仓库地址：${repo_url}"
}
# 封装 jobs_update_jobs_repos 对应的独立处理逻辑。
jobs_update_jobs_repos() {
  if ! jobs_update_has git; then
    warn_echo "git 不存在，跳过 JobsKits 仓库更新。"
    return 0
  fi

  jobs_update_repo "JobsSoftware.MacOS" "$JOBS_SOFTWARE_REPO" "${JOBS_WORKSPACE}/JobsSoftware.MacOS"
  jobs_update_repo "JobsMacEnvVarConfig" "$JOBS_ENV_REPO" "${JOBS_WORKSPACE}/JobsMacEnvVarConfig"

  local install_script="${JOBS_WORKSPACE}/JobsMacEnvVarConfig/install.command/install.command"
  if [[ -f "$install_script" ]]; then
    jobs_update_run_cmd "确认 JobsMacEnvVarConfig/install.command 可执行权限" chmod +x "$install_script" || true
    warn_echo "不会执行 ${install_script}，避免 install.command 递归调用。"
  fi
}
# 封装 open_download_page 对应的独立处理逻辑。
open_download_page() {
  local name="$1"
  local url="$2"

  if ! jobs_update_has open; then
    warn_echo "open 命令不存在，无法打开：${name}"
    return 0
  fi

  jobs_update_run_cmd "打开 ${name} 下载 / 更新页" open "$url" || true
}
# 封装 jobs_update_manual_download_pages 对应的独立处理逻辑。
jobs_update_manual_download_pages() {
  open_download_page "Visual Studio Code" "https://code.visualstudio.com/"
  open_download_page "Android Studio" "https://developer.android.com/studio?hl=zh-cn"
  open_download_page "Python" "https://www.python.org/downloads/"
}
# ---------- 命令实现 ----------
update() {
  local ran_count=0
  JOBS_UPDATE_COCOAPODS_BREW_UPDATED=0

  if jobs_update_prompt_run "是否更新 Xcode Command Line Tools / macOS softwareupdate？" "对应 install.command：Xcode Command Line Tools。"; then
    jobs_update_run_step "Xcode Command Line Tools / softwareupdate 更新" jobs_update_clt
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Xcode iOS 平台组件？" "对应 install.command：Xcode iOS 平台组件。"; then
    jobs_update_run_step "Xcode iOS 平台组件更新" jobs_update_xcode_ios_platform
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Oh My Zsh？" "对应 install.command：Oh My Zsh。"; then
    jobs_update_run_step "Oh My Zsh 更新" jobs_update_oh_my_zsh
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Homebrew？" "执行 brew update / upgrade / cask upgrade / cleanup / doctor。"; then
    jobs_update_run_step "Homebrew 更新" jobs_update_homebrew
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否逐项升级 install.command 中的 brew cask？" "覆盖 BREW_CASKS 内所有 cask；github-store 会确认 OpenHub-Store/tap 并解除 quarantine 标记。"; then
    jobs_update_run_step "brew cask 批量升级" jobs_update_brew_casks
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否逐项升级 install.command 中的 brew formula？" "覆盖 BREW_FORMULAE 内所有 formula。"; then
    jobs_update_run_step "brew formula 批量升级" jobs_update_brew_formulae
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否检查 Rosetta 2？" "Rosetta 2 无独立升级命令，只检查状态并说明维护方式。"; then
    jobs_update_run_step "Rosetta 2 状态检查" jobs_update_rosetta
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 FVM / Flutter？" "覆盖 install.command 中的 brew cask：flutter 与 brew formula：fvm 的后续 SDK 维护。"; then
    jobs_update_run_step "FVM / Flutter 更新" jobs_update_fvm_flutter
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否维护 Node / corepack / npm？" "覆盖 install.command 中的 brew formula：node / pnpm，并兼容 nvm。"; then
    jobs_update_run_step "Node / corepack / npm 维护" jobs_update_node_base
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 npm 全局包 quicktype？" "对应 install.command：npm 全局包 quicktype。"; then
    jobs_update_run_step "npm quicktype 更新" jobs_update_npm_quicktype
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 npm 全局包 OpenCLI？" "对应 install.command：npm 全局包 OpenCLI。"; then
    jobs_update_run_step "npm OpenCLI 更新" jobs_update_npm_opencli
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 npm 全局包 CodeGraph？" "对应 install.command：npm 全局包 CodeGraph；执行 npm install -g @colbymchenry/codegraph@latest，并刷新 Agent 配置。"; then
    jobs_update_run_step "npm CodeGraph 更新" jobs_update_npm_codegraph
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Ruby / RubyGems？" "维护 ruby / rbenv；前后检查 CocoaPods 所用 Ruby 的原生扩展，缺失时备份重建。"; then
    jobs_update_run_step "Ruby / RubyGems 更新" jobs_update_ruby_base
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 CocoaPods？" "识别 Homebrew / gem 安装；实测 CDN / GitHub 后仅刷新所选公共源，失败保留缓存。"; then
    jobs_update_run_step "CocoaPods 更新" jobs_update_gem_cocoapods
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 Python / pip？" "覆盖 install.command 中的 brew formula：python / python3 / uv 的后续维护。"; then
    jobs_update_run_step "Python / pip 更新" jobs_update_python_base
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否修复 Dart pub 缓存？" "覆盖 Flutter / FVM / Dart 生态的缓存维护。"; then
    jobs_update_run_step "Dart pub 缓存修复" jobs_update_pub_cache
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否刷新 Git LFS 初始化与大文件参数？" "对应 install.command：Git LFS 初始化。"; then
    jobs_update_run_step "Git LFS 初始化刷新" jobs_update_git_lfs_init
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否更新 JobsKits 仓库？" "对应 install.command：JobsSoftware.MacOS、JobsMacEnvVarConfig。"; then
    jobs_update_run_step "JobsKits 仓库更新" jobs_update_jobs_repos
    (( ran_count++ ))
  fi

  if jobs_update_prompt_run "是否打开手动下载 / 更新页面？" "对应 install.command：VS Code、Android Studio、Python 手动下载页。"; then
    jobs_update_run_step "手动下载 / 更新页面" jobs_update_manual_download_pages
    (( ran_count++ ))
  fi

  echo ""
  print_divider
  if (( ran_count == 0 )); then
    warn_echo "没有执行任何更新项"
  else
    success_echo "update 执行完成，共执行 ${ran_count} 个更新项"
  fi
  info_echo "日志文件位置：${LOG_FILE}"
  print_divider
}
# ---------- 主流程统一收口 ----------
jobs_update_main() {
  # 展示脚本说明并等待用户确认影响范围。
  jobs_update_show_readme_and_wait
  # 执行更新或升级步骤，确保该动作不会被默认触发。
  update "$@"
  local exit_code=$?
  # 清理临时下载策略，并恢复用户原有的 Homebrew curl 环境。
  jobs_update_cleanup_network_strategy
  return $exit_code
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  if (( JOBS_UPDATE_TRUST_MODE == 1 )); then
    note_echo "托管模式：已跳过脚本内置自述确认。" | jobs_intro_style title
    print -r -- "Python 环境：非交互只读自检；缺失时停止 Python 项，不替换系统环境。" | jobs_intro_style body
    return 0
  fi

  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- 'Python 环境：选中 Python 项后更新 Homebrew，版本不满足要求才安装或修复。' | jobs_intro_style body
  print -r -- '脚本名称：update.command' | jobs_intro_style title
  print -r -- '核心用途：执行“update”对应的自动化任务。' | jobs_intro_style body
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
  jobs_update_parse_args "$@" # 解析运行参数，识别托管模式或帮助请求。
  local parse_exit_code=$?
  if (( parse_exit_code == 2 )); then
    return 0
  elif (( parse_exit_code != 0 )); then
    return $parse_exit_code
  fi
  jobs_update_prepare_unattended_mode || return $? # 启用无人值守的非交互提权策略。
  show_script_intro_and_wait || return $? # 展示脚本内置自述，并按运行入口完成防误触确认。
  jobs_update_main "$@" || return $? # 执行 jobs_update_main 对应的核心业务步骤。
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  set -u
  set -o pipefail
  setopt NO_NOMATCH
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    : > "$LOG_FILE"
    main "$@"
  fi
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
