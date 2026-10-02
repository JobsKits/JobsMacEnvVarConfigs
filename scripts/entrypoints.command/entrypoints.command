#!/bin/zsh
# 脚本自述：
# - 脚本名称：entrypoints.command
# - 核心用途：执行“entrypoints”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# JobsMacEnv executable command wrappers.
# 这里只注册终端短命令；真实实现统一放在 Scripts/<命令>.command/<命令>.command。
# 封装 _jobs_resolve_scripts_command 对应的独立处理逻辑。
_jobs_resolve_scripts_command() {
  emulate -L zsh

  local command_name="$1"
  local env_home="${JOBS_MAC_ENV_HOME:-$HOME/.JobsMacEnv}"
  local scripts_dir="$env_home/Scripts"
  local script_file="${command_name}.command"
  local candidates=(
    "$scripts_dir/$script_file/$script_file"
    "$scripts_dir/$script_file"
  )

  local candidate=""
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      print -r -- "$candidate"
      return 0
    fi
  done

  return 1
}
# 封装 _jobs_run_scripts_command 对应的独立处理逻辑。
_jobs_run_scripts_command() {
  emulate -L zsh

  local command_name="$1"
  shift

  local script=""
  if ! script="$(_jobs_resolve_scripts_command "$command_name")"; then
    echo "$command_name: 主脚本不存在或不可执行" >&2
    echo "👉 请重新执行 JobsMacEnv 安装脚本" >&2
    return 127
  fi

  "$script" "$@"
}
# 封装 _jobs_restore_stateful_wrapper 对应的独立处理逻辑。
_jobs_restore_stateful_wrapper() {
  emulate -L zsh

  local command_name="$1"
  local main_function="$2"
  eval "${command_name}() { _jobs_source_and_run_scripts_command ${command_name} ${main_function} \"\$@\"; }"
}
# 封装 _jobs_source_and_run_scripts_command 对应的独立处理逻辑。
_jobs_source_and_run_scripts_command() {
  emulate -L zsh

  local command_name="$1"
  local main_function="$2"
  shift 2

  local script=""
  if ! script="$(_jobs_resolve_scripts_command "$command_name")"; then
    echo "$command_name: 主脚本不存在或不可执行" >&2
    echo "👉 请重新执行 JobsMacEnv 安装脚本" >&2
    return 127
  fi

  local previous_source_mode="${JOBS_MAC_ENV_SOURCE_MODE:-}"
  JOBS_MAC_ENV_SOURCE_MODE="1"
  source "$script" || {
    if [[ -n "$previous_source_mode" ]]; then
      JOBS_MAC_ENV_SOURCE_MODE="$previous_source_mode"
    else
      unset JOBS_MAC_ENV_SOURCE_MODE
    fi
    return 1
  }

  if [[ -n "$previous_source_mode" ]]; then
    JOBS_MAC_ENV_SOURCE_MODE="$previous_source_mode"
  else
    unset JOBS_MAC_ENV_SOURCE_MODE
  fi

  if ! typeset -f "$main_function" >/dev/null 2>&1; then
    echo "$command_name: 入口函数不存在：$main_function" >&2
    _jobs_restore_stateful_wrapper "$command_name" "$main_function"
    return 127
  fi

  "$main_function" "$@"
  local command_status=$?
  _jobs_restore_stateful_wrapper "$command_name" "$main_function"
  return $command_status
}
# list：打开 JobsMacEnv 功能菜单。
list() { _jobs_run_scripts_command list "$@"; }
# m5c：m5c
m5c() { _jobs_run_scripts_command m5c "$@"; }
# flat：flat
flat() { _jobs_run_scripts_command flat "$@"; }
# trs：trs
trs() { _jobs_run_scripts_command trs "$@"; }
# gif：gif
gif() { _jobs_run_scripts_command gif "$@"; }
# tts：调用 Supertonic 本地 TTS，输入文本后生成并播放语音。
tts() { _jobs_run_scripts_command "tts" "$@"; }
# simios：simios
simios() { _jobs_run_scripts_command simios "$@"; }
# pods：本地 CocoaPods Pod 编译 / podspec lint 自检。
pods() { _jobs_run_scripts_command pods "$@"; }
# clean：清空 zsh 历史、zsh_sessions，将 Spotlight 中不可打开的构建 App 移入废纸篓，并执行 brew cleanup。
clean() { _jobs_run_scripts_command clean "$@"; }
# clr：清空 Google Chrome 下载记录，不删除真实下载文件。
clr() { _jobs_run_scripts_command clr "$@"; }
# dq：解决新装 App 无法打开、被系统建议移到废纸篓的问题（清理 macOS quarantine 隔离标记）。
dq() { _jobs_run_scripts_command dq "$@"; }
# df：dufs + Caddy 临时开放本地目录给局域网浏览器访问。注意：系统磁盘 df 请用 /bin/df。
df() { _jobs_run_scripts_command df "$@"; }
# cor：转换 HEX / RGB / RGBA / 0xAARRGGBB，并输出终端色块预览。
cor() { _jobs_run_scripts_command cor "$@"; }
# decode：交互式 URL Decode，并自动复制结果到剪贴板。
decode() { _jobs_run_scripts_command decode "$@"; }
# ts：识别秒 / 毫秒 / 微秒 / 纳秒时间戳，并转换为本地时间。
ts() { _jobs_run_scripts_command ts "$@"; }
# download：媒体下载；yt-dlp 优先，并可在配置 cobalt API 后兜底。
download() { _jobs_run_scripts_command download "$@"; }
# to：FFmpeg 通用媒体格式转换入口。
to() { _jobs_run_scripts_command to "$@"; }
# code：打开 VS Code；用于补齐未注册 code 命令时的终端入口。
code() { _jobs_run_scripts_command code "$@"; }
# mp4 / mov / webm 等：统一复用 to.command，不复制真实业务脚本。
mp4()  { _jobs_run_scripts_command to mp4 "$@"; }
# 封装 mov 对应的独立处理逻辑。
mov()  { _jobs_run_scripts_command to mov "$@"; }
# 封装 webm 对应的独立处理逻辑。
webm() { _jobs_run_scripts_command to webm "$@"; }
# 封装 mkv 对应的独立处理逻辑。
mkv()  { _jobs_run_scripts_command to mkv "$@"; }
# 封装 avi 对应的独立处理逻辑。
avi()  { _jobs_run_scripts_command to avi "$@"; }
# 封装 m4v 对应的独立处理逻辑。
m4v()  { _jobs_run_scripts_command to m4v "$@"; }
# 封装 mp3 对应的独立处理逻辑。
mp3()  { _jobs_run_scripts_command to mp3 "$@"; }
# 封装 m4a 对应的独立处理逻辑。
m4a()  { _jobs_run_scripts_command to m4a "$@"; }
# 封装 aac 对应的独立处理逻辑。
aac()  { _jobs_run_scripts_command to aac "$@"; }
# 封装 wav 对应的独立处理逻辑。
wav()  { _jobs_run_scripts_command to wav "$@"; }
# 封装 flac 对应的独立处理逻辑。
flac() { _jobs_run_scripts_command to flac "$@"; }
# 封装 ogg 对应的独立处理逻辑。
ogg()  { _jobs_run_scripts_command to ogg "$@"; }
# 封装 opus 对应的独立处理逻辑。
opus() { _jobs_run_scripts_command to opus "$@"; }
# install：安装和初始化常用开发环境依赖。注意：该命令名与系统 /usr/bin/install 有冲突风险。
install() { _jobs_run_scripts_command install "$@"; }
# update：通过菜单批量更新 Homebrew、Flutter、Node、Python、Ruby、CocoaPods 等工具链。
update() { _jobs_run_scripts_command update "$@"; }
# shell：扫描当前机器可用 shell，并通过 fzf 选择默认登录 shell。
shell() { _jobs_run_scripts_command shell "$@"; }
# zz：解析 Finder 替身 / 软链接 / 文件路径并 cd 到真实目录。
zz() { _jobs_source_and_run_scripts_command zz jobs_zz_main "$@"; }
# x：给拖入的脚本 chmod +x 并执行。
x() { _jobs_run_scripts_command x "$@"; }
# save：重新加载 bash / zsh 常见配置文件。
save() { _jobs_source_and_run_scripts_command save jobs_save_main "$@"; }
# rb：用 exec 重启当前登录 shell。
rb() { _jobs_source_and_run_scripts_command rb jobs_rb_main "$@"; }
# a：打开 ~/.bash_profile。
a() { _jobs_run_scripts_command a "$@"; }
# b：打开 ~/.zshrc。
b() { _jobs_run_scripts_command b "$@"; }
# i：打开 iOS Simulator。
i() { _jobs_run_scripts_command i "$@"; }
# fixfvm：重装 Dart pub 全局 fvm，修复 FVM 与 Dart SDK 内核版本不匹配。
fixfvm() { _jobs_run_scripts_command fixfvm "$@"; }
# check1：打印 Dart / FVM / Flutter 路径和版本信息。
check1() { _jobs_run_scripts_command check1 "$@"; }
# check：进入默认 Flutter 项目，锁定 FVM 版本并执行 flutter doctor -v。
check() { _jobs_source_and_run_scripts_command check jobs_check_main "$@"; }
# c：进入默认 Flutter 项目，锁定 JDK 17，并执行项目检查。
c() { _jobs_source_and_run_scripts_command c jobs_c_main "$@"; }
# d：cd 到默认 Flutter 项目目录，可传入路径覆盖。
d() { _jobs_source_and_run_scripts_command d jobs_d_main "$@"; }
# buildCheck：Flutter 构建前清理、pub get 和 doctor 检查。
buildCheck() { _jobs_source_and_run_scripts_command buildCheck jobs_buildCheck_main "$@"; }
# apk：检查 Flutter / FVM / JDK 17 后构建 Android APK。
apk() { _jobs_source_and_run_scripts_command apk jobs_apk_main "$@"; }
# ipa：执行 Flutter iOS release 构建并打开输出目录。
ipa() { _jobs_source_and_run_scripts_command ipa jobs_ipa_main "$@"; }
# config：用 Xcode 或系统文本编辑器打开 ~/.zshrc 或指定配置文件。
config() { _jobs_run_scripts_command config "$@"; }
