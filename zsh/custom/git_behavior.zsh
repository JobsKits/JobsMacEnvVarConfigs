# Git / 终端显示行为
# 只在交互式 zsh 生效，不写入全局 Git 配置。

[[ -o interactive ]] || return 0

# JOBS_GIT_NETWORK_STRATEGY_BEGIN
# 终端与 Sourcetree 共用可执行入口，只有 push 连接失败时才动态尝试代理。
jobs_mount_git_network_strategy() {
  local strategy_bin="${JOBS_MAC_ENV_HOME:-$HOME/.JobsMacEnv}/Scripts/_lib/jobs_git_network_strategy/bin"
  if [[ -x "$strategy_bin/git" ]]; then
    path=("$strategy_bin" "${(@)path:#$strategy_bin}")
    export PATH
  fi
}
jobs_mount_git_network_strategy
unfunction jobs_mount_git_network_strategy
# JOBS_GIT_NETWORK_STRATEGY_END

jobs_locale_is_utf8() {
  local value="${1:-}"
  value="${value:l}"
  [[ "$value" == *utf-8* || "$value" == *utf8* ]]
}

# 终端字符集优先保持用户现有语言，只在缺少 UTF-8 语义时补齐编码。
if ! jobs_locale_is_utf8 "${LC_CTYPE:-}"; then
  export LC_CTYPE="${JOBS_TERMINAL_LC_CTYPE:-UTF-8}"
fi

if [[ -z "${LANG:-}" || "${LANG:l}" == "c" || "${LANG:l}" == "posix" ]]; then
  export LANG="${JOBS_TERMINAL_LANG:-zh_CN.UTF-8}"
fi

# 让终端里直接输入 git 时，中文路径 / emoji 路径按原文显示。
# 这里等价于每次执行：git -c core.quotepath=false ...
# 不会写入 ~/.gitconfig，也不会修改仓库 .git/config。
if [[ "${JOBS_GIT_QUOTEPATH_FIX:-true}" == "true" ]]; then
  function git {
    command git -c core.quotepath=false "$@"
  }
fi

unfunction jobs_locale_is_utf8 2>/dev/null || true
