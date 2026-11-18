#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】runtime_init.command
# - 核心用途：执行“runtime_init”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# JobsMacEnv runtime initialization.
# 只放交互式 shell 启动时需要初始化的轻量内容。
# jenv / rbenv：存在才初始化，避免新机器首次启动报错。
# Dart completion：路径由 Flutter 独立命令脚本中的 JOBS_DART_CLI_COMPLETION_FILE 配置。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  if command -v jenv >/dev/null 2>&1; then
    export PATH="$HOME/.jenv/bin:$PATH"
    eval "$(jenv init -)"
  fi
  if command -v rbenv >/dev/null 2>&1; then
    eval "$(rbenv init - zsh)"
  fi
  if [[ -n "${JOBS_DART_CLI_COMPLETION_FILE:-}" && -f "$JOBS_DART_CLI_COMPLETION_FILE" ]]; then
    source "$JOBS_DART_CLI_COMPLETION_FILE"
  fi
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
