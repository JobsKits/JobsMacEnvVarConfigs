# shell: zsh
# 模块自述：只供 source，沿用原交互式启动和只读健康发现；不增加询问。
# 加载时初始化集中于本函数，保持模块内部原语句顺序。
jobs_initialize_shell_behavior() {
  # 交互式终端默认行为
  # 单独拆出来，后面你想关掉某个行为，只改这个文件即可。
  # 注意：这里不再定义任何终端自定义命令。
  # 终端可输入的自定义命令必须统一放在 Scripts/<命令>.command/<命令>.command。

  # 打开终端默认进入桌面。
  if [[ -o interactive ]] && [[ -d "$HOME/Desktop" ]]; then
    cd "$HOME/Desktop"
  fi
}

jobs_initialize_shell_behavior
