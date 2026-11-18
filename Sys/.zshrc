# JobsMacEnv 主入口
# 只保留最小入口，具体逻辑全部拆到 $HOME/.JobsMacEnv 下维护

export JOBS_MAC_ENV_HOME="$HOME/.JobsMacEnv"
[[ -n "${JOBS_MAC_ENV_HOME_OVERRIDE:-}" ]] && export JOBS_MAC_ENV_HOME="$JOBS_MAC_ENV_HOME_OVERRIDE"

jobs_source_if_exists() {
  local file="$1"
  [[ -f "$file" ]] && source "$file"
}

jobs_source_if_exists "$JOBS_MAC_ENV_HOME/zsh/【MacOS】bootstrap.zsh/【MacOS】bootstrap.zsh"
jobs_source_if_exists "$JOBS_MAC_ENV_HOME/zsh/【MacOS】env_methods.zsh/【MacOS】env_methods.zsh"
jobs_source_if_exists "$JOBS_MAC_ENV_HOME/zsh/env.zsh"
jobs_source_if_exists "$JOBS_MAC_ENV_HOME/zsh/aliases.zsh"
jobs_source_if_exists "$JOBS_MAC_ENV_HOME/zsh/【MacOS】user_mounts.zsh/【MacOS】user_mounts.zsh"
