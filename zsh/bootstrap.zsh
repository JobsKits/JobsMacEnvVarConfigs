# JobsMacEnv 启动层
# 这里放最基础、最稳定、适合全局执行的初始化逻辑

# 仅交互式 shell 处理 UI / cd / 提示等动作
[[ -o interactive ]] || return 0

# Oh My Zsh（存在才启用）
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  export ZSH="$HOME/.oh-my-zsh"
  : "${ZSH_THEME:=robbyrussell}"
  typeset -ga plugins
  if (( ${plugins[(Ie)git]} == 0 )); then
    plugins+=(git)
  fi
  source "$ZSH/oh-my-zsh.sh"
fi

# Homebrew shellenv（Apple Silicon / Intel 自动兼容）
# 输出当前脚本内的 Homebrew 健康诊断。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
}
# 验证 Homebrew 命令和真实前缀均可用。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 在当前脚本内发现健康 Homebrew，不触发安装或升级。
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
jobs_bootstrap_brew() {
  local brew_bin="" brew_env=""
  brew_bin="$(jobs_brew_find)" || return 0
  brew_env="$("$brew_bin" shellenv)" || return 0
  eval "$brew_env"
}

jobs_bootstrap_brew
