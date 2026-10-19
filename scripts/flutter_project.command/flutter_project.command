#!/bin/zsh
# 脚本自述：
# - 脚本名称：flutter_project.command
# - 核心用途：执行“flutter_project”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# JobsMacEnv function module.
# 本文件由 JobsMacEnv 加载；不要在这里写自动执行流程。

# ================================== Flutter 项目辅助命令模块 ==================================
# 兼容原版位置：Scripts/flutter_project.command/flutter_project.command
# flutter 的具体实现复用当前版本的 Scripts/_lib/jobs_flutter_lib.zsh。

_jobs_flutter_project_module_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
_jobs_flutter_project_env_home="${JOBS_MAC_ENV_HOME:-$HOME/.JobsMacEnv}"
_jobs_flutter_project_lib_candidates=(
  "${_jobs_flutter_project_module_dir}/../_lib/jobs_flutter_lib.zsh"
  "${_jobs_flutter_project_env_home}/Scripts/_lib/jobs_flutter_lib.zsh"
)

_jobs_flutter_project_lib_loaded="false"
# 🔥 flutter() 重载（优先 FVM）🔥
flutter() {
  jobs_flutter_flutter_impl "$@"
}
# 🔥 dart() 重载（优先 FVM，跟随项目锚定版本）🔥
dart() {
  jobs_flutter_dart_impl "$@"
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  for _jobs_flutter_project_lib in "${_jobs_flutter_project_lib_candidates[@]}"; do
    if [[ -f "$_jobs_flutter_project_lib" ]]; then
      source "$_jobs_flutter_project_lib"
      _jobs_flutter_project_lib_loaded="true"
      break
    fi
  done
  if [[ "$_jobs_flutter_project_lib_loaded" != "true" ]]; then
    print -u2 "JobsMacEnv: 缺少 Flutter 私有库：jobs_flutter_lib.zsh"
    print -u2 "JobsMacEnv: 请重新执行 install.command"
    unset _jobs_flutter_project_module_dir _jobs_flutter_project_env_home _jobs_flutter_project_lib_candidates _jobs_flutter_project_lib _jobs_flutter_project_lib_loaded
    return 0 2>/dev/null || true
  fi
  unset _jobs_flutter_project_module_dir _jobs_flutter_project_env_home _jobs_flutter_project_lib_candidates _jobs_flutter_project_lib _jobs_flutter_project_lib_loaded
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
