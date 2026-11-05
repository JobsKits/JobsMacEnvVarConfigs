#!/bin/zsh
# 脚本自述：
# - 脚本名称：clean.command
# - 核心用途：清理 zsh 历史、用户缓存、Homebrew 缓存、失效开发 App 图标和实体已缺失的 iOS 模拟器登记。
# - 影响范围：会删除用户缓存、将开发构建 App 移入废纸篓、备份并注销实体缺失的模拟器、清空终端历史，并短暂重启 Spotlight 与 Dock。
# - 运行提示：运行后会先打印内置自述；按回车继续，按 Ctrl+C 取消。


# ---------- 基础路径 ----------
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
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
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
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
  cat <<EOFREADME | jobs_intro_style auto
============================================================
clean - 终端清理
============================================================

这是 clean.command 的内置自述，不读取同级 README.md。

功能：
  - 清空 zsh 历史和 zsh_sessions 残留。
  - 删除 ${HOME}/Library/Caches 内的文件、子目录和隐藏项，保留 Caches 目录本身。
  - 将 Spotlight 收录且无法在 macOS 打开的 Apple 平台构建 App 移入废纸篓。
  - 定向注销非 macOS 构建产物与模拟器 App 的 LaunchServices 记录。
  - 检查实体已缺失的 iOS 模拟器，先备份残留数据，再按 UUID 注销 CoreSimulator 登记。
  - 检测到 Homebrew 时顺手执行 brew cleanup。

说明：
  - 用户缓存直接删除，不经过废纸篓；应用后续可能重新生成缓存。
  - 缓存目录为符号链接时跳过；无权限删除的项目会记录日志并继续后续清理。
  - 只移动用户目录中 Build/Products 或 build/*-iphone 等开发输出下的 .app。
  - 不移动 Applications 里的正常 App，不移动正常 CoreSimulator 设备容器中的 App 实体。
  - 模拟器目录或 device.plist 已缺失才注销；仅 data 缺失或 Runtime 不可用的设备保留。
  - 只关闭待注销的损坏设备；残留目录先备份到废纸篓，正常设备与共享 Runtime 保留。
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
  if ! read -r "?👉 已了解缓存、历史、构建 App 和失效模拟器登记的清理范围，按回车继续；按 Ctrl+C 取消：" answer; then
    print -r -- '无法读取确认输入，已取消 clean，未执行任何清理。' | jobs_intro_style body
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
# 清空当前用户缓存内容，保留目录本身且不跟随缓存入口的符号链接。
jobs_clean_user_caches() {
  emulate -L zsh
  setopt PIPE_FAIL

  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1
  if [[ -z "${HOME:-}" || "$HOME" != /* || ! -d "$HOME" || "${HOME:A}" == / ]]; then
    error_echo "用户目录无效，已跳过缓存清理。"
    return 1
  fi

  local user_home="${HOME:A}"
  local cache_dir="$user_home/Library/Caches"
  if [[ -L "$user_home/Library" || -L "$cache_dir" ]]; then
    warn_echo "缓存入口为符号链接，已跳过：$cache_dir"
    return 1
  fi
  if [[ ! -e "$cache_dir" ]]; then
    info_echo "用户缓存目录不存在，已跳过：$cache_dir"
    return 0
  fi
  if [[ ! -d "$cache_dir" ]]; then
    warn_echo "用户缓存路径不是目录，已跳过：$cache_dir"
    return 1
  fi

  local cache_item=""
  local -i removed_count=0
  local -i failed_count=0

  info_echo "正在清理用户缓存：$cache_dir"
  if ! /usr/bin/find "$cache_dir" -mindepth 1 -maxdepth 1 -print0 2>> "$LOG_FILE" |
    while IFS= read -r -d '' cache_item; do
      if /bin/rm -rf -- "$cache_item" >> "$LOG_FILE" 2>&1; then
        ((removed_count += 1))
      else
        ((failed_count += 1))
        warn_echo "缓存删除失败，已继续：$cache_item"
      fi
    done; then
    error_echo "用户缓存目录读取失败，详情见：$LOG_FILE"
    return 1
  fi

  if (( failed_count > 0 )); then
    warn_echo "用户缓存清理结束：已删除 ${removed_count} 项，${failed_count} 项未完全删除，详情见：$LOG_FILE"
    return 1
  fi
  success_echo "用户缓存清理完成：已删除 ${removed_count} 项，保留目录：$cache_dir"
}
# 限时调用当前 Xcode 的 simctl，固定设备集，取消或超时只结束本次客户端。
jobs_clean_simctl() (
  local devices_dir="$1" simctl_bin="" task_pid="" result=0 deadline=$((SECONDS + 30))
  shift
  simctl_bin="$(/usr/bin/xcrun --find simctl 2>/dev/null)" || return 127
  trap '[[ -z "$task_pid" ]] || /bin/kill -KILL "$task_pid" 2>/dev/null' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  "$simctl_bin" --set "$devices_dir" "$@" &
  task_pid=$!
  while /bin/kill -0 "$task_pid" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      /bin/kill -KILL "$task_pid" 2>/dev/null || true
      wait "$task_pid" 2>/dev/null || true
      task_pid=""
      print -u2 -r -- 'simctl 操作超过 30 秒，已停止本次客户端。'
      return 124
    fi
    /bin/sleep 0.1
  done
  wait "$task_pid" || result=$?
  task_pid=""
  return "$result"
)
# 完整校验 JSON 后才输出 iOS UUID 与状态，避免错误输出或外部路径成为删除参数。
jobs_clean_simulator_rows() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JOBS_SIMULATOR_JSON'
ObjC.import('Foundation');
function run(argv) {
  const raw = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null);
  const payload = JSON.parse(ObjC.unwrap(raw));
  if (!payload || !payload.devices || typeof payload.devices !== 'object' || Array.isArray(payload.devices)) {
    throw new Error('缺少 devices 对象');
  }
  const rows = [], seen = {};
  Object.keys(payload.devices).forEach(function(runtime) {
    if (!Array.isArray(payload.devices[runtime])) throw new Error('设备清单不是数组');
    if (!/^com\.apple\.CoreSimulator\.SimRuntime\.iOS-/.test(runtime)) return;
    payload.devices[runtime].forEach(function(device) {
      if (!device || typeof device.udid !== 'string' ||
          !/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i.test(device.udid) ||
          typeof device.state !== 'string' || !device.state || /[\x00-\x1f\x7f]/.test(device.state) ||
          device.dataPath !== argv[1] + '/' + device.udid + '/data' || seen[device.udid.toUpperCase()]) {
        throw new Error('设备 UUID、状态或 dataPath 不可靠');
      }
      seen[device.udid.toUpperCase()] = true;
      rows.push(device.udid + '\t' + device.state);
    });
  });
  return rows.join('\n');
}
JOBS_SIMULATOR_JSON
}
# 0 表示目录或定义确实缺失；1 保留现有定义；2 表示权限、链接或路径不可靠。
jobs_clean_simulator_missing() {
  emulate -L zsh
  local devices_dir="$1" uuid="$2" current="${HOME:A}" component="" entry=""
  [[ -n "$HOME" && "$HOME" == /* && "$current" != / && -d "$current" && -r "$current" && -x "$current" ]] || return 2
  [[ "$devices_dir" == "$current/Library/Developer/CoreSimulator/Devices" ]] || return 2
  [[ "$uuid" =~ '^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$' ]] || return 2
  for component in Library Developer CoreSimulator Devices "$uuid"; do
    current+="/$component"
    [[ ! -L "$current" ]] || return 2
    [[ -e "$current" ]] || return 0
    [[ -d "$current" && -r "$current" && -x "$current" ]] || return 2
  done
  for entry in "$current/device.plist" "$current/data"; do
    [[ ! -L "$entry" ]] || return 2
  done
  if [[ -e "$current/device.plist" ]]; then
    [[ -f "$current/device.plist" && -r "$current/device.plist" ]] || return 2
    # 保留仍有定义的设备，data 可由系统初始化或重新生成。
    [[ ! -e "$current/data" || ( -d "$current/data" && -r "$current/data" && -x "$current/data" ) ]] || return 2
    return 1
  fi
  [[ ! -e "$current/data" || ( -d "$current/data" && -r "$current/data" && -x "$current/data" ) ]] || return 2
  return 0
}
# 写操作前重新查询同一 UUID；恢复、状态变化或已消失均保留，不沿用旧快照。
jobs_clean_simulator_recheck() {
  local devices_dir="$1" uuid="$2" expected_state="$3" snapshot="$4" check_result=0
  jobs_clean_simctl "$devices_dir" list devices --json > "$snapshot" 2>> "$LOG_FILE" || return 2
  jobs_clean_simulator_rows "$snapshot" "$devices_dir" > "$snapshot.rows" 2>> "$LOG_FILE" || return 2
  jobs_clean_simulator_missing "$devices_dir" "$uuid" || check_result=$?
  (( check_result == 0 )) || return "$check_result"
  /usr/bin/grep -Fxq -- "$uuid"$'\t'"$expected_state" "$snapshot.rows" && return 0
  # 关闭命令假成功时不能把仍在运行的损坏设备当作清理完成。
  if [[ "$expected_state" == Shutdown ]] && /usr/bin/grep -Fxq -- "$uuid"$'\tBooted' "$snapshot.rows"; then
    return 2
  fi
  return 1
}
# 仅注销定义或目录已丢失的 iOS 设备；残留数据备份验证成功后才交给 simctl 删除。
jobs_clean_orphaned_simulators() {
  emulate -L zsh
  (( JOBS_CLEAN_CONFIRMED == 1 )) || return 1
  local devices_dir="${HOME:A}/Library/Developer/CoreSimulator/Devices" scan_dir="" backup_dir=""
  local uuid="" device_state="" entry="" result=0 query_result=0
  local -i candidates=0 removed=0 failed=0 skipped=0
  scan_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsClean-SimulatorScan.XXXXXXXX")" || return 1
  jobs_clean_simctl "$devices_dir" list devices --json > "$scan_dir/before.json" 2>> "$LOG_FILE" || query_result=$?
  if (( query_result == 127 )); then
    info_echo '未安装可用的 Xcode simctl，跳过模拟器登记清理。'
    return 0
  fi
  if (( query_result != 0 )) || ! jobs_clean_simulator_rows "$scan_dir/before.json" "$devices_dir" > "$scan_dir/before.rows" 2>> "$LOG_FILE"; then
    warn_echo "模拟器清单读取失败，未注销设备；诊断：$scan_dir"
    return 1
  fi
  info_echo '正在检查 CoreSimulator 中实体已缺失的 iOS 模拟器登记…'
  while IFS=$'\t' read -r uuid device_state; do
    [[ -n "$uuid" ]] || continue
    result=0
    jobs_clean_simulator_missing "$devices_dir" "$uuid" || result=$?
    (( result != 1 )) || continue
    if (( result == 2 )) || [[ "$device_state" != Shutdown && "$device_state" != Booted ]]; then
      ((skipped += 1))
      (( result != 2 )) || ((failed += 1))
      warn_echo "设备路径不可靠或正在转换状态，保留：$uuid ($device_state)"
      continue
    fi
    ((candidates += 1))
    result=0
    jobs_clean_simulator_recheck "$devices_dir" "$uuid" "$device_state" "$scan_dir/$uuid.precheck.json" || result=$?
    if (( result != 0 )); then
      ((skipped += 1))
      (( result != 2 )) || ((failed += 1))
      warn_echo "设备已变化或无法复检，保留：$uuid"
      continue
    fi
    if [[ -z "$backup_dir" ]]; then
      if [[ -L "$HOME/.Trash" || ! -d "$HOME/.Trash" || ! -w "$HOME/.Trash" ]] ||
         ! backup_dir="$(/usr/bin/mktemp -d "$HOME/.Trash/JobsClean-SimulatorOrphans-XXXXXXXX")" ||
         ! /bin/cp "$scan_dir/before.json" "$backup_dir/inventory-before.json"; then
        error_echo '模拟器清理备份不可用，已停止注销。'
        return 1
      fi
      note_echo "模拟器清理备份：$backup_dir"
    fi
    if [[ "$device_state" == Booted ]]; then
      if ! jobs_clean_simctl "$devices_dir" shutdown "$uuid" >> "$LOG_FILE" 2>&1; then
        ((failed += 1))
        warn_echo "损坏设备关闭失败，保留：$uuid"
        continue
      fi
      device_state=Shutdown
    fi
    result=0
    jobs_clean_simulator_recheck "$devices_dir" "$uuid" "$device_state" "$scan_dir/$uuid.shutdown.json" || result=$?
    if (( result != 0 )); then
      ((skipped += 1))
      (( result != 2 )) || ((failed += 1))
      warn_echo "关闭后设备已变化或无法复检，保留：$uuid"
      continue
    fi
    entry="$devices_dir/$uuid"
    if [[ -d "$entry" ]]; then
      if ! /usr/bin/ditto "$entry" "$backup_dir/$uuid" >> "$LOG_FILE" 2>&1 ||
         ! /usr/bin/diff -qr "$entry" "$backup_dir/$uuid" >> "$LOG_FILE" 2>&1; then
        ((failed += 1))
        warn_echo "残留数据备份校验失败，保留：$uuid"
        continue
      fi
    fi
    result=0
    jobs_clean_simulator_recheck "$devices_dir" "$uuid" "$device_state" "$scan_dir/$uuid.delete.json" || result=$?
    if (( result != 0 )) || { [[ -d "$entry" ]] && ! /usr/bin/diff -qr "$entry" "$backup_dir/$uuid" >> "$LOG_FILE" 2>&1; }; then
      ((skipped += 1))
      (( result != 2 )) || ((failed += 1))
      warn_echo "删除前设备或数据已变化，保留：$uuid"
      continue
    fi
    if ! jobs_clean_simctl "$devices_dir" delete "$uuid" >> "$LOG_FILE" 2>&1 ||
       ! jobs_clean_simctl "$devices_dir" list devices --json > "$scan_dir/$uuid.after.json" 2>> "$LOG_FILE" ||
       ! jobs_clean_simulator_rows "$scan_dir/$uuid.after.json" "$devices_dir" > "$scan_dir/$uuid.after.rows" 2>> "$LOG_FILE" ||
       /usr/bin/grep -q -- "^$uuid"$'\t' "$scan_dir/$uuid.after.rows"; then
      ((failed += 1))
      warn_echo "设备注销失败或登记仍存在：$uuid；详情：$scan_dir"
      continue
    fi
    ((removed += 1))
    gray_echo "已注销实体缺失的模拟器：$uuid"
  done < "$scan_dir/before.rows"
  info_echo "模拟器登记检查：候选 $candidates，已注销 $removed，保留 $skipped，失败 $failed；诊断：$scan_dir"
  (( failed == 0 ))
}
# 按 Homebrew 当前策略信任 FVM tap，避免 cleanup 扫描阶段反复提示未信任。
jobs_clean_trust_fvm_tap_if_required() {
  emulate -L zsh
  local brew_bin="${1:-}"
  [[ -n "$brew_bin" ]] || brew_bin="$(jobs_brew_find)" || return 0

  [[ -n "${HOMEBREW_REQUIRE_TAP_TRUST:-}" ]] || "$brew_bin" config 2>/dev/null | grep -Fq "HOMEBREW_REQUIRE_TAP_TRUST: set" || return 0
  "$brew_bin" tap 2>/dev/null | grep -Fxq "leoafarias/fvm" || return 0
  "$brew_bin" trust --json=v1 2>/dev/null | grep -Fq '"leoafarias/fvm"' && return 0

  if "$brew_bin" trust --tap leoafarias/fvm >/dev/null 2>&1; then
    print -P "%F{green}✔ Homebrew Tap 已信任：leoafarias/fvm%f"
  fi
}
# 顺手清理 Homebrew 旧版本包和缓存；Homebrew 不存在或清理失败都不阻断 clean。
jobs_clean_homebrew_cleanup() {
  emulate -L zsh

  local brew_bin=""
  brew_bin="$(jobs_brew_find)" || return 0

  jobs_clean_trust_fvm_tap_if_required "$brew_bin"

  print -P "%F{blue}ℹ 正在执行 brew cleanup...%f"
  if "$brew_bin" cleanup 2> >(grep -Fv "Warning: Skipping fvm: tap formula is not trusted" >&2); then
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
  local simulator_result=0
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
  jobs_clean_orphaned_simulators || simulator_result=$?
  jobs_clean_unregister_non_macos_development_apps
  jobs_clean_refresh_application_lists
  jobs_clean_homebrew_cleanup
  jobs_clean_user_caches || true

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
  if (( simulator_result != 0 )); then
    warn_echo "模拟器登记清理未全部完成，详情见：$LOG_FILE"
  fi
  return "$simulator_result"
}
# ---------- 主流程统一收口 ----------
# 为被 entrypoints.command 加载的场景编排完整 clean 流程。
jobs_clean_main() {
  show_script_intro_and_wait # 先说明用户缓存、终端历史和应用登记清理范围，并等待确认。
  jobs_clean_prepare_runtime # 确认后再初始化 zsh 选项与本次日志。
  clean "$@" # 清理终端历史、失效模拟器与开发 App 登记、Homebrew 和用户缓存。
}
# 统一收口可独立执行的 clean 业务流程。
main() {
  show_script_intro_and_wait # 先说明用户缓存、终端历史和应用登记清理范围，并等待确认。
  jobs_clean_prepare_runtime # 确认后再初始化 zsh 选项与本次日志。
  clean "$@" # 清理终端历史、失效模拟器与开发 App 登记、Homebrew 和用户缓存。
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    main "$@"
  fi
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
