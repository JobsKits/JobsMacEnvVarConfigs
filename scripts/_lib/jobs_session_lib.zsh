# JobsMacEnv session private library. Do not call directly.
jobs_session_save_impl() {
  local files=(
    "$HOME/.bash_profile"
    "$HOME/.bashrc"
    "$HOME/.zshrc"
    "$HOME/.profile"
  )
  for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
      source "$file"
      echo -e "\033[1;32m✅ 已加载配置文件：file://$file\033[0m"
    else
      echo -e "\033[1;33m⚠️ 未找到配置文件：file://$file\033[0m"
    fi
  done
  echo -e "\n📎 ⌘Command + 点击路径可打开对应文件（macOS Terminal 支持）"
}

jobs_session_rb_impl() { exec -l "$SHELL"; }
jobs_session_a_impl() { open "$HOME/.bash_profile"; }
jobs_session_b_impl() { open "$HOME/.zshrc"; }
# 从开发目录或 Xcode 应用根目录定位新旧模拟器入口。
jobs_session_simulator_app_for_developer_dir() {
  emulate -L zsh
  local developer_dir="${1%/}"
  local candidate=""

  [[ "$developer_dir" == *.app ]] && developer_dir="$developer_dir/Contents/Developer"
  [[ -d "$developer_dir" ]] || return 1

  for candidate in \
    "$developer_dir/../Applications/DeviceHub.app" \
    "$developer_dir/Applications/DeviceHub.app" \
    "$developer_dir/Applications/Simulator.app" \
    "$developer_dir/../Applications/Simulator.app"; do
    if [[ -d "$candidate" ]]; then
      print -r -- "${candidate:A}"
      return 0
    fi
  done
  return 1
}
# 优先使用显式开发目录和当前 Xcode，随后检查常见安装位置。
jobs_session_find_simulator_app() {
  emulate -L zsh
  setopt NULL_GLOB
  local developer_dir=""
  local xcode_app=""

  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    jobs_session_simulator_app_for_developer_dir "$DEVELOPER_DIR" && return 0
    print -u2 -r -- "✖ DEVELOPER_DIR 中未找到 Device Hub 或 Simulator：$DEVELOPER_DIR"
    return 1
  fi

  developer_dir="$(xcode-select -p 2>/dev/null)"
  if [[ -n "$developer_dir" ]]; then
    jobs_session_simulator_app_for_developer_dir "$developer_dir" && return 0
  fi

  for xcode_app in \
    /Applications/Xcode*.app \
    "$HOME"/Applications/Xcode*.app \
    /Applications/Xcodes/Xcode*.app; do
    jobs_session_simulator_app_for_developer_dir "$xcode_app" && return 0
  done
  return 1
}
# 按完整路径启动 Xcode 27 Device Hub 或旧版 Simulator，并保留失败状态。
jobs_session_i_impl() {
  emulate -L zsh
  local simulator_app=""
  local launch_status=0

  if ! simulator_app="$(jobs_session_find_simulator_app)"; then
    print -u2 -r -- "✖ 未找到可用的 Device Hub / Simulator 应用。"
    print -u2 -r -- "请检查完整 Xcode 的安装位置及 DEVELOPER_DIR / xcode-select -p；仅安装 Command Line Tools 不包含模拟器。"
    return 1
  fi

  print -r -- "➤ 打开模拟器：$simulator_app"
  open -a "$simulator_app" "$@"
  launch_status=$?
  if (( launch_status != 0 )); then
    print -u2 -r -- "✖ 启动失败（退出码 $launch_status）：$simulator_app"
  fi
  return "$launch_status"
}
