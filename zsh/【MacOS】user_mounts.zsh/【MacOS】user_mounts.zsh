# shell: zsh
# 模块自述：只供 source，沿用原交互式启动和只读健康发现；不增加询问。
# 加载时初始化集中于本函数，保持模块内部原语句顺序。
jobs_initialize_user_mounts() {
  # 用户挂载入口
  # 这里只负责按顺序加载自定义模块

  export JOBS_USER_MOUNTS_DIR="$JOBS_MAC_ENV_HOME/zsh/custom"

  jobs_source_if_exists() {
    local file="$1"
    [[ -f "$file" ]] && source "$file"
  }

  jobs_source_if_exists "$JOBS_USER_MOUNTS_DIR/【MacOS】shell_behavior.zsh/【MacOS】shell_behavior.zsh"
  jobs_source_if_exists "$JOBS_USER_MOUNTS_DIR/【MacOS】git_behavior.zsh/【MacOS】git_behavior.zsh"
  jobs_source_if_exists "$JOBS_USER_MOUNTS_DIR/【MacOS】path_drag_resolver.zsh/【MacOS】path_drag_resolver.zsh"
  jobs_source_if_exists "$JOBS_USER_MOUNTS_DIR/【MacOS】local.zsh/【MacOS】local.zsh"
}

jobs_initialize_user_mounts
