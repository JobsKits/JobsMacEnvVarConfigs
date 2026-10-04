#!/bin/zsh
# 脚本自述：
# - 脚本名称：clean.command
# - 核心用途：清理 zsh 历史、Homebrew 缓存和 Spotlight 中不可在 macOS 打开的开发 App 图标。
# - 影响范围：会将 Spotlight 收录的非 macOS 构建 App 移入废纸篓、注销开发 App 记录、清空终端历史，并短暂重启 Spotlight 与 Dock。
# - 运行提示：运行后会先打印内置自述；按回车继续，按 Ctrl+C 取消。


# ---------- 基础路径 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
LAUNCH_SERVICES_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
JOBS_CLEAN_APPLICATION_INDEX_CHANGED=0
JOBS_CLEAN_CONFIRMED=0
JOBS_CLEAN_MOVED_BUILD_PRODUCTS=0
# ---------- 彩色日志 ----------
# 同步记录终端输出和脚本日志。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "[1;32m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "[1;34mℹ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "[1;32m✔ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "[1;33m⚠ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "[1;33m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "[1;35m➤ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "[1;31m✖ $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "[1;31m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "[1;35m🐞 $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "[1;36m🔹 $1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "[0;90m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "[1m$1[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "[4m$1[0m"; }
# ---------- 内置自述 ----------
# 打印脚本内置自述，并在交互式终端等待用户确认。
show_script_intro_and_wait() {
  emulate -L zsh

  clear 2>/dev/null || true
  cat <<EOFREADME
============================================================
clean - 终端清理
============================================================

这是 clean.command 的内置自述，不读取同级 README.md。

功能：
  - 清空 zsh 历史和 zsh_sessions 残留。
  - 将 Spotlight 收录且无法在 macOS 打开的 Apple 平台构建 App 移入废纸篓。
  - 定向注销非 macOS 构建产物与模拟器 App 的 LaunchServices 记录。
  - 检测到 Homebrew 时顺手执行 brew cleanup。

说明：
  - 只移动用户目录中 Build/Products 或 build/*-iphone 等开发输出下的 .app。
  - 不移动 Applications 里的正常 App，不移动 CoreSimulator 设备容器中的 App 实体。
  - 构建 App 会保留在废纸篓的 JobsClean-DevelopmentApps-* 目录中，可恢复或重新构建。
  - 会短暂重启 Spotlight、corespotlightd、sharedfilelistd 和 Dock，界面可能闪烁一次。
  - 日志路径：${LOG_FILE}
============================================================
EOFREADME

  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  local answer=""
  if ! read -r "?👉 已了解会清空历史并将构建 App 移入废纸篓，按回车继续；按 Ctrl+C 取消：" answer; then
    print -r -- '无法读取确认输入，已取消 clean，未执行任何清理。'
    return 1
  fi
  JOBS_CLEAN_CONFIRMED=1
}
# ---------- 命令实现 ----------
# 初始化清理流程需要的 zsh 选项和日志文件。
jobs_clean_prepare_runtime() {
  emulate -L zsh
  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1
  set -o pipefail
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}
# 按 Homebrew 当前策略信任 FVM tap，避免 cleanup 扫描阶段反复提示未信任。
jobs_clean_trust_fvm_tap_if_required() {
  emulate -L zsh

  [[ -n "${HOMEBREW_REQUIRE_TAP_TRUST:-}" ]] || brew config 2>/dev/null | grep -Fq "HOMEBREW_REQUIRE_TAP_TRUST: set" || return 0
  brew tap 2>/dev/null | grep -Fxq "leoafarias/fvm" || return 0
  brew trust --json=v1 2>/dev/null | grep -Fq '"leoafarias/fvm"' && return 0

  if brew trust --tap leoafarias/fvm >/dev/null 2>&1; then
    print -P "%F{green}✔ Homebrew Tap 已信任：leoafarias/fvm%f"
  fi
}
# 顺手清理 Homebrew 旧版本包和缓存；Homebrew 不存在或清理失败都不阻断 clean。
jobs_clean_homebrew_cleanup() {
  emulate -L zsh

  command -v brew >/dev/null 2>&1 || return 0

  jobs_clean_trust_fvm_tap_if_required

  print -P "%F{blue}ℹ 正在执行 brew cleanup...%f"
  if brew cleanup 2> >(grep -Fv "Warning: Skipping fvm: tap formula is not trusted" >&2); then
    print -P "%F{green}✔ Homebrew 垃圾清理完成%f"
  else
    print -P "%F{yellow}⚠ brew cleanup 执行失败，已忽略，继续 clean%f"
  fi
}
# 判断路径是否属于可重新生成的非 macOS Apple 平台构建 App。
jobs_clean_is_non_macos_build_product_app_path() {
  emulate -L zsh

  local app_path="$1"
  case "$app_path" in
    */[Bb]uild/Products/*-iphone*/*.app|*/[Bb]uild/Products/*-appletv*/*.app|*/[Bb]uild/Products/*-watch*/*.app|*/[Bb]uild/Products/*-xr*/*.app)
      return 0
      ;;
    */[Bb]uild/*-iphone*/*.app|*/[Bb]uild/*-appletv*/*.app|*/[Bb]uild/*-watch*/*.app|*/[Bb]uild/*-xr*/*.app)
      return 0
      ;;
  esac
  return 1
}
# 判断 LaunchServices 路径是否属于无法在 macOS 直接打开的 Apple 开发 App。
jobs_clean_is_non_macos_development_app_path() {
  emulate -L zsh

  local app_path="$1"
  case "$app_path" in
    "$HOME/Library/Developer/CoreSimulator/Devices/"*/data/Containers/Bundle/Application/*/*.app)
      return 0
      ;;
  esac
  jobs_clean_is_non_macos_build_product_app_path "$app_path"
}
# 将 Spotlight 直接收录的非 macOS 构建 App 移入废纸篓，从文件源头清除图标。
jobs_clean_move_indexed_build_apps_to_trash() {
  emulate -L zsh
  setopt NO_NOMATCH

  command -v mdfind >/dev/null 2>&1 || {
    warn_echo "Spotlight 查询工具不可用，已跳过构建 App 废纸篓清理。"
    return 0
  }
  [[ -d "$HOME/.Trash" ]] || {
    warn_echo "废纸篓目录不可用，已跳过构建 App 文件清理：$HOME/.Trash"
    return 0
  }

  local app_path=""
  local relative_path=""
  local destination=""
  local destination_parent=""
  local trash_root=""
  local -i candidate_count=0
  local -i moved_count=0
  local -i failed_count=0
  local -i skipped_count=0
  typeset -A seen_paths=()

  info_echo "正在检查 Spotlight 直接收录的非 macOS 构建 App..."
  while IFS= read -r -d '' app_path; do
    jobs_clean_is_non_macos_build_product_app_path "$app_path" || continue
    [[ "$app_path" == "$HOME/"* ]] || {
      ((skipped_count++))
      warn_echo "已跳过用户目录以外的构建 App：$app_path"
      continue
    }
    [[ "$app_path" != "$HOME/.Trash/"* ]] || continue
    [[ -d "$app_path" || -L "$app_path" ]] || continue
    [[ -z "${seen_paths[$app_path]:-}" ]] || continue
    seen_paths[$app_path]=1
    ((candidate_count++))

    if [[ -z "$trash_root" ]]; then
      trash_root="$HOME/.Trash/JobsClean-DevelopmentApps-$(date '+%Y%m%d-%H%M%S')-$$"
      if ! mkdir -p "$trash_root"; then
        error_echo "无法创建可恢复清理目录：$trash_root"
        return 1
      fi
    fi

    relative_path="${app_path#/}"
    destination="$trash_root/$relative_path"
    destination_parent="${destination:h}"
    if ! mkdir -p "$destination_parent"; then
      ((failed_count++))
      warn_echo "无法创建废纸篓目标目录：$destination_parent"
      continue
    fi
    if [[ -x "$LAUNCH_SERVICES_REGISTER" ]]; then
      "$LAUNCH_SERVICES_REGISTER" -u "$app_path" >> "$LOG_FILE" 2>&1 || true
    fi
    if /bin/mv "$app_path" "$destination" >> "$LOG_FILE" 2>&1; then
      ((moved_count++))
      JOBS_CLEAN_MOVED_BUILD_PRODUCTS=1
      JOBS_CLEAN_APPLICATION_INDEX_CHANGED=1
      gray_echo "已移入废纸篓：$app_path"
    else
      ((failed_count++))
      warn_echo "移入废纸篓失败：$app_path"
    fi
  done < <(mdfind -0 'kMDItemContentType == "com.apple.application-bundle"' 2>/dev/null)

  if (( candidate_count == 0 )); then
    info_echo "Spotlight 中未发现需要移走的非 macOS 构建 App。"
    return 0
  fi
  success_echo "Spotlight 构建 App 清理完成：发现 ${candidate_count} 项，已移入废纸篓 ${moved_count} 项。"
  [[ -z "$trash_root" ]] || note_echo "可恢复目录：$trash_root"
  (( skipped_count == 0 )) || warn_echo "为保护外部路径，已跳过 ${skipped_count} 项。"
  (( failed_count == 0 )) || warn_echo "其中 ${failed_count} 项移动失败，详情见：$LOG_FILE"
}
# 定向注销非 macOS 构建产物与模拟器 App；模拟器容器中的实体文件保持不动。
jobs_clean_unregister_non_macos_development_apps() {
  emulate -L zsh
  setopt NO_NOMATCH

  [[ -x "$LAUNCH_SERVICES_REGISTER" ]] || {
    warn_echo "LaunchServices 注册工具不可用，已跳过失效 App 图标清理：$LAUNCH_SERVICES_REGISTER"
    return 0
  }

  local line=""
  local app_path=""
  local -i candidate_count=0
  local -i unregistered_count=0
  local -i stale_count=0
  local -i failed_count=0
  typeset -A seen_paths=()

  info_echo "正在检查 LaunchServices 中的非 macOS 构建产物与模拟器 App..."
  while IFS= read -r line; do
    [[ "$line" =~ '^path:[[:space:]]+(.+)[[:space:]]+\(0x[[:xdigit:]]+\)$' ]] || continue
    app_path="${match[1]}"
    jobs_clean_is_non_macos_development_app_path "$app_path" || continue
    [[ -z "${seen_paths[$app_path]:-}" ]] || continue
    seen_paths[$app_path]=1
    ((candidate_count++))

    if [[ ! -e "$app_path" && ! -L "$app_path" ]]; then
      ((stale_count++))
      continue
    fi
    if "$LAUNCH_SERVICES_REGISTER" -u "$app_path" >> "$LOG_FILE" 2>&1; then
      ((unregistered_count++))
      gray_echo "已注销：$app_path"
    else
      ((failed_count++))
      warn_echo "注销失败：$app_path"
    fi
  done < <("$LAUNCH_SERVICES_REGISTER" -dump 2>/dev/null)

  if "$LAUNCH_SERVICES_REGISTER" -gc >> "$LOG_FILE" 2>&1; then
    JOBS_CLEAN_APPLICATION_INDEX_CHANGED=1
  else
    warn_echo "LaunchServices 垃圾回收执行失败，已继续后续清理。"
  fi

  if (( candidate_count == 0 )); then
    info_echo "未发现需要注销的非 macOS 开发 App 记录。"
    return 0
  fi
  success_echo "LaunchServices 清理完成：发现 ${candidate_count} 项，已注销 ${unregistered_count} 项，已回收 ${stale_count} 项失效路径。"
  (( failed_count == 0 )) || warn_echo "其中 ${failed_count} 项注销失败，详情见：$LOG_FILE"
}
# 重启应用列表相关的用户级进程，让失效图标立即从 Spotlight 消失。
jobs_clean_refresh_application_lists() {
  emulate -L zsh

  (( JOBS_CLEAN_APPLICATION_INDEX_CHANGED == 1 )) || return 0
  killall Spotlight >/dev/null 2>&1 || true
  killall corespotlightd >/dev/null 2>&1 || true
  killall sharedfilelistd >/dev/null 2>&1 || true
  killall Dock >/dev/null 2>&1 || true
  success_echo "已刷新 Spotlight 和 Dock 应用列表"
}
# 执行对应的清理操作，并保留必要的安全检查。
clean() {
  emulate -L zsh
  setopt no_nomatch null_glob

  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1

  local old_histfile="${HISTFILE:-}"
  local hist_file="${old_histfile:-$HOME/.zsh_history}"
  local old_histsize="${HISTSIZE:-10000}"
  local old_savehist="${SAVEHIST:-$old_histsize}"
  local file
  local history_files=(
    "$hist_file"
    "$HOME/.zsh_history"
    "$HOME/.zsh_sessions"/*.history(N)
    "$HOME/.zsh_sessions"/*.historynew(N)
  )

  HISTSIZE=0
  SAVEHIST=0
  builtin fc -W "$hist_file" 2>/dev/null || true

  for file in "${history_files[@]}"; do
    [[ -n "$file" ]] || continue
    [[ -e "$file" || -L "$file" ]] || continue
    : >| "$file" 2>/dev/null || true
  done

  jobs_clean_move_indexed_build_apps_to_trash
  jobs_clean_unregister_non_macos_development_apps
  jobs_clean_refresh_application_lists
  jobs_clean_homebrew_cleanup

  HISTSIZE="$old_histsize"
  SAVEHIST="$old_savehist"
  if [[ -n "$old_histfile" ]]; then
    HISTFILE="$old_histfile"
  else
    unset HISTFILE
  fi

  printf '\033[H\033[2J\033[3J'
  printf '\033]1337;ClearScrollback\007'
  printf '\033[H'
}
# ---------- 主流程统一收口 ----------
# 为被 entrypoints.command 加载的场景编排完整 clean 流程。
jobs_clean_main() {
  show_script_intro_and_wait # 先说明终端历史和应用登记清理范围，并等待确认。
  jobs_clean_prepare_runtime # 确认后再初始化 zsh 选项与本次日志。
  clean "$@" # 清理终端历史、失效开发 App 登记和 Homebrew 缓存。
}
# 统一收口可独立执行的 clean 业务流程。
main() {
  show_script_intro_and_wait # 先说明终端历史和应用登记清理范围，并等待确认。
  jobs_clean_prepare_runtime # 确认后再初始化 zsh 选项与本次日志。
  clean "$@" # 清理终端历史、失效开发 App 登记和 Homebrew 缓存。
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    main "$@"
  fi
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
