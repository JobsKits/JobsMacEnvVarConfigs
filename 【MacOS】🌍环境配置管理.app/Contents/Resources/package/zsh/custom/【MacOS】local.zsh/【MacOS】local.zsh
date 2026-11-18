# shell: zsh
# 模块自述：只供 source，沿用原交互式启动和只读健康发现；不增加询问。
# 加载时初始化集中于本函数，保持模块内部原语句顺序。
jobs_initialize_local_mounts() {
  # JobsMacEnv 自定义命令入口加载器
  # 大部分命令通过 Scripts/<命令>.command/<命令>.command 暴露。
  # 【MacOS】flutter_project.command 保持原版脚本位置，但不再自动注册全局 flutter 函数。

  export JOBS_MAC_ENV_HOME="${JOBS_MAC_ENV_HOME:-$HOME/.JobsMacEnv}"
  [[ -n "${JOBS_MAC_ENV_HOME_OVERRIDE:-}" ]] && export JOBS_MAC_ENV_HOME="$JOBS_MAC_ENV_HOME_OVERRIDE"

  _jobs_scripts_candidates=(
    "$JOBS_MAC_ENV_HOME/Scripts"
    "$HOME/.JobsMacEnv/Scripts"
  )

  JOBS_MAC_ENV_SCRIPTS_DIR=""
  for _jobs_scripts_dir in "${_jobs_scripts_candidates[@]}"; do
    if [[ -d "$_jobs_scripts_dir" ]]; then
      JOBS_MAC_ENV_SCRIPTS_DIR="$_jobs_scripts_dir"
      break
    fi
  done

  if [[ -z "$JOBS_MAC_ENV_SCRIPTS_DIR" ]]; then
    JOBS_MAC_ENV_SCRIPTS_DIR="$HOME/.JobsMacEnv/Scripts"
    print -u2 "JobsMacEnv: Scripts 目录不存在：$JOBS_MAC_ENV_SCRIPTS_DIR"
    print -u2 "JobsMacEnv: 请重新执行 【MacOS】install.command"
    unset _jobs_scripts_candidates _jobs_scripts_dir
    return 0 2>/dev/null || true
  fi

  jobs_source_scripts_file() {
    local file_name="$1"
    local nested_file="$JOBS_MAC_ENV_SCRIPTS_DIR/$file_name/$file_name"

    if [[ -f "$nested_file" ]]; then
      source "$nested_file"
    else
      print -u2 "JobsMacEnv: 入口脚本缺失：$nested_file"
    fi
  }

  jobs_source_scripts_file 【MacOS】runtime_init.command
  jobs_source_scripts_file 【MacOS】entrypoints.command

  unset _jobs_scripts_candidates _jobs_scripts_dir
  unfunction jobs_source_scripts_file 2>/dev/null || true
}

jobs_initialize_local_mounts
