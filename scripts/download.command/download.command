#!/bin/zsh
# 脚本自述：
# - 脚本名称：download.command
# - 核心用途：执行媒体下载；默认优先使用 yt-dlp，失败后可自动兜底到自建 cobalt API。
# - 影响范围：会在当前目录写入下载文件，并通过网络访问目标媒体站点或已配置的 cobalt API。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

# ---------- 基础路径 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

# ---------- 彩色日志 ----------
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }

# ---------- 参数状态 ----------
typeset -ga JOBS_DOWNLOAD_FORWARD_ARGS=()
typeset -g JOBS_DOWNLOAD_BACKEND_EFFECTIVE=""
typeset -g JOBS_DOWNLOAD_SOURCE_URL=""
typeset -g JOBS_DOWNLOAD_SHOW_HELP="0"
typeset -g JOBS_DOWNLOAD_COBALT_API_EFFECTIVE=""
typeset -g JOBS_DOWNLOAD_COBALT_KEY_EFFECTIVE=""
typeset -g JOBS_DOWNLOAD_COBALT_MODE_EFFECTIVE=""
typeset -g JOBS_DOWNLOAD_COBALT_QUALITY_EFFECTIVE=""
typeset -g JOBS_DOWNLOAD_COBALT_AUDIO_FORMAT_EFFECTIVE=""
typeset -g JOBS_DOWNLOAD_COBALT_LOCAL_PROCESSING_EFFECTIVE=""

# 打印脚本内置自述，并等待终端用户确认后再继续。
show_script_intro_and_wait() {
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear 2>/dev/null || true
  fi
  highlight_echo "============================== 脚本内置自述 =============================="
  note_echo "脚本名称：download.command"
  note_echo "核心用途：媒体下载；默认 yt-dlp 优先，失败后可兜底自建 cobalt API。"
  note_echo "运行策略：download URL 保持原 yt-dlp 体验；download --cobalt URL 可强制 cobalt。"
  warn_echo "影响范围：会在当前目录写入下载文件，并访问目标站点或配置的 API。"
  gray_echo "cobalt API：默认不调用公开托管 API；请通过 JOBS_DOWNLOAD_COBALT_API 指向自建实例。"
  gray_echo "日志文件：${LOG_FILE}"
  gray_echo "取消方式：确认前按 Ctrl+C 终止，不会继续执行下载业务。"
  highlight_echo "=========================================================================="
  echo ""
  if [[ ! -t 0 ]]; then
    error_echo "当前没有可交互输入，请在终端中重新运行。"
    exit 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
}
# 输出 download 命令用法，说明 yt-dlp 与 cobalt 两种后端。
jobs_download_print_usage() {
  cat <<'EOFUSAGE' | tee -a "$LOG_FILE"
usage:
  download <url> [yt-dlp 参数...]
  download --backend auto <url>
  download --backend yt-dlp <url> [yt-dlp 参数...]
  download --backend cobalt <url>
  download --cobalt <url>

backend:
  auto      默认模式；先跑 yt-dlp，失败后在已配置 cobalt API 时自动兜底
  yt-dlp    只使用 yt-dlp，并自动带上默认浏览器 cookies
  cobalt    只使用 cobalt API；需要配置 JOBS_DOWNLOAD_COBALT_API

cobalt env:
  JOBS_DOWNLOAD_COBALT_API="https://your-cobalt-api.example/"
  JOBS_DOWNLOAD_COBALT_KEY="可选 Api-Key"
  JOBS_DOWNLOAD_COBALT_AUTHORIZATION="可选完整 Authorization 值"

cobalt options:
  --cobalt-api <url>                 临时指定 cobalt API
  --cobalt-key <key>                 临时指定 cobalt Api-Key
  --audio                            cobalt 下载音频
  --mute                             cobalt 下载静音视频
  --cobalt-quality <max|1080|720|...>       cobalt 视频质量，默认 max
  --cobalt-audio-format <best|mp3|opus|...> cobalt 音频格式，默认 best
EOFUSAGE
}
# 检测 macOS 默认浏览器，并转换为 yt-dlp 支持的 cookies 名称。
jobs_detect_default_browser_for_ytdlp() {
  emulate -L zsh

  local bundle_id
  bundle_id="$(osascript 2>/dev/null <<'EOF'
try
  id of application (path to default application for URL "https://www.youtube.com")
on error
  return ""
end try
EOF
)"

  case "$bundle_id" in
    com.google.Chrome|com.google.Chrome.canary)
      echo "chrome"
      ;;
    com.microsoft.edgemac)
      echo "edge"
      ;;
    org.mozilla.firefox)
      echo "firefox"
      ;;
    com.apple.Safari)
      echo "safari"
      ;;
    *)
      echo ""
      ;;
  esac
}
# 解析 download 自身参数，并保留 yt-dlp 原生命令参数。
jobs_download_parse_args() {
  emulate -L zsh

  JOBS_DOWNLOAD_FORWARD_ARGS=()
  JOBS_DOWNLOAD_BACKEND_EFFECTIVE="${JOBS_DOWNLOAD_BACKEND:-auto}"
  JOBS_DOWNLOAD_SOURCE_URL=""
  JOBS_DOWNLOAD_SHOW_HELP="0"
  JOBS_DOWNLOAD_COBALT_API_EFFECTIVE="${JOBS_DOWNLOAD_COBALT_API:-}"
  JOBS_DOWNLOAD_COBALT_KEY_EFFECTIVE="${JOBS_DOWNLOAD_COBALT_KEY:-}"
  JOBS_DOWNLOAD_COBALT_MODE_EFFECTIVE="${JOBS_DOWNLOAD_COBALT_MODE:-auto}"
  JOBS_DOWNLOAD_COBALT_QUALITY_EFFECTIVE="${JOBS_DOWNLOAD_COBALT_QUALITY:-max}"
  JOBS_DOWNLOAD_COBALT_AUDIO_FORMAT_EFFECTIVE="${JOBS_DOWNLOAD_COBALT_AUDIO_FORMAT:-best}"
  JOBS_DOWNLOAD_COBALT_LOCAL_PROCESSING_EFFECTIVE="${JOBS_DOWNLOAD_COBALT_LOCAL_PROCESSING:-disabled}"

  local arg
  while (( $# > 0 )); do
    arg="$1"
    case "$arg" in
      -h|--help)
        JOBS_DOWNLOAD_SHOW_HELP="1"
        shift
        ;;
      --backend|--download-backend)
        shift
        if (( $# == 0 )); then
          error_echo "download: --backend 需要跟 auto / yt-dlp / cobalt"
          return 2
        fi
        JOBS_DOWNLOAD_BACKEND_EFFECTIVE="$1"
        shift
        ;;
      --backend=*|--download-backend=*)
        JOBS_DOWNLOAD_BACKEND_EFFECTIVE="${arg#*=}"
        shift
        ;;
      --yt-dlp)
        JOBS_DOWNLOAD_BACKEND_EFFECTIVE="yt-dlp"
        shift
        ;;
      --cobalt)
        JOBS_DOWNLOAD_BACKEND_EFFECTIVE="cobalt"
        shift
        ;;
      --cobalt-api)
        shift
        if (( $# == 0 )); then
          error_echo "download: --cobalt-api 需要跟 API 地址"
          return 2
        fi
        JOBS_DOWNLOAD_COBALT_API_EFFECTIVE="$1"
        shift
        ;;
      --cobalt-api=*)
        JOBS_DOWNLOAD_COBALT_API_EFFECTIVE="${arg#*=}"
        shift
        ;;
      --cobalt-key)
        shift
        if (( $# == 0 )); then
          error_echo "download: --cobalt-key 需要跟 Api-Key"
          return 2
        fi
        JOBS_DOWNLOAD_COBALT_KEY_EFFECTIVE="$1"
        shift
        ;;
      --cobalt-key=*)
        JOBS_DOWNLOAD_COBALT_KEY_EFFECTIVE="${arg#*=}"
        shift
        ;;
      --audio)
        JOBS_DOWNLOAD_COBALT_MODE_EFFECTIVE="audio"
        shift
        ;;
      --mute)
        JOBS_DOWNLOAD_COBALT_MODE_EFFECTIVE="mute"
        shift
        ;;
      --cobalt-quality|--cobalt-video-quality)
        shift
        if (( $# == 0 )); then
          error_echo "download: --cobalt-quality 需要跟质量值，例如 max / 1080 / 720"
          return 2
        fi
        JOBS_DOWNLOAD_COBALT_QUALITY_EFFECTIVE="$1"
        shift
        ;;
      --cobalt-quality=*|--cobalt-video-quality=*)
        JOBS_DOWNLOAD_COBALT_QUALITY_EFFECTIVE="${arg#*=}"
        shift
        ;;
      --cobalt-audio-format)
        shift
        if (( $# == 0 )); then
          error_echo "download: --cobalt-audio-format 需要跟格式值，例如 best / mp3 / opus"
          return 2
        fi
        JOBS_DOWNLOAD_COBALT_AUDIO_FORMAT_EFFECTIVE="$1"
        shift
        ;;
      --cobalt-audio-format=*)
        JOBS_DOWNLOAD_COBALT_AUDIO_FORMAT_EFFECTIVE="${arg#*=}"
        shift
        ;;
      --cobalt-local-processing)
        shift
        if (( $# == 0 )); then
          error_echo "download: --cobalt-local-processing 需要跟 disabled / preferred / forced"
          return 2
        fi
        JOBS_DOWNLOAD_COBALT_LOCAL_PROCESSING_EFFECTIVE="$1"
        shift
        ;;
      --cobalt-local-processing=*)
        JOBS_DOWNLOAD_COBALT_LOCAL_PROCESSING_EFFECTIVE="${arg#*=}"
        shift
        ;;
      --)
        shift
        while (( $# > 0 )); do
          JOBS_DOWNLOAD_FORWARD_ARGS+=("$1")
          shift
        done
        ;;
      *)
        JOBS_DOWNLOAD_FORWARD_ARGS+=("$arg")
        shift
        ;;
    esac
  done

  jobs_download_pick_source_url
  jobs_download_normalize_backend
}
# 从透传参数中提取第一个 http/https URL，供 cobalt API 使用。
jobs_download_pick_source_url() {
  emulate -L zsh

  local item
  for item in "${JOBS_DOWNLOAD_FORWARD_ARGS[@]}"; do
    case "$item" in
      http://*|https://*)
        JOBS_DOWNLOAD_SOURCE_URL="$item"
        return 0
        ;;
    esac
  done
  return 0
}
# 归一化后端名称，避免用户输入大小写或别名导致分支走偏。
jobs_download_normalize_backend() {
  emulate -L zsh

  JOBS_DOWNLOAD_BACKEND_EFFECTIVE="$(print -r -- "$JOBS_DOWNLOAD_BACKEND_EFFECTIVE" | tr '[:upper:]' '[:lower:]')"
  case "$JOBS_DOWNLOAD_BACKEND_EFFECTIVE" in
    auto|yt-dlp|ytdlp|cobalt)
      [[ "$JOBS_DOWNLOAD_BACKEND_EFFECTIVE" == "ytdlp" ]] && JOBS_DOWNLOAD_BACKEND_EFFECTIVE="yt-dlp"
      return 0
      ;;
    *)
      error_echo "download: 未支持的后端：${JOBS_DOWNLOAD_BACKEND_EFFECTIVE}"
      warn_echo "可用后端：auto / yt-dlp / cobalt"
      return 2
      ;;
  esac
}
# 判断当前是否已经配置可调用的 cobalt API。
jobs_download_has_cobalt_api() {
  emulate -L zsh

  [[ -n "${JOBS_DOWNLOAD_COBALT_API_EFFECTIVE:-}" ]] && return 0
  [[ "${JOBS_DOWNLOAD_ALLOW_PUBLIC_COBALT:-}" == "1" ]] && return 0
  return 1
}
# 输出本次 cobalt API 地址，并补齐结尾斜杠。
jobs_download_cobalt_api_url() {
  emulate -L zsh

  local api="${JOBS_DOWNLOAD_COBALT_API_EFFECTIVE:-}"
  if [[ -z "$api" && "${JOBS_DOWNLOAD_ALLOW_PUBLIC_COBALT:-}" == "1" ]]; then
    api="https://api.cobalt.tools/"
    warn_echo "已按 JOBS_DOWNLOAD_ALLOW_PUBLIC_COBALT=1 使用公开 cobalt API；官方不建议把公开实例作为项目默认后端。"
  fi
  [[ -z "$api" ]] && return 1
  [[ "$api" != */ ]] && api="${api}/"
  print -r -- "$api"
}
# 按 cobalt 配置生成 Authorization 头内容。
jobs_download_cobalt_auth_header() {
  emulate -L zsh

  if [[ -n "${JOBS_DOWNLOAD_COBALT_AUTHORIZATION:-}" ]]; then
    print -r -- "$JOBS_DOWNLOAD_COBALT_AUTHORIZATION"
    return 0
  fi
  if [[ -n "${JOBS_DOWNLOAD_COBALT_KEY_EFFECTIVE:-}" ]]; then
    print -r -- "Api-Key ${JOBS_DOWNLOAD_COBALT_KEY_EFFECTIVE}"
    return 0
  fi
  return 1
}
# 对 JSON 字符串做最小必要转义，避免 URL 中特殊字符破坏请求体。
jobs_download_json_escape() {
  emulate -L zsh

  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\t'/\\t}"
  print -r -- "\"${value}\""
}
# 生成 cobalt API 请求体，默认取最高视频质量并禁用本地处理分支。
jobs_download_make_cobalt_payload() {
  emulate -L zsh

  local url_json mode_json quality_json audio_format_json local_processing_json
  url_json="$(jobs_download_json_escape "$JOBS_DOWNLOAD_SOURCE_URL")"
  mode_json="$(jobs_download_json_escape "$JOBS_DOWNLOAD_COBALT_MODE_EFFECTIVE")"
  quality_json="$(jobs_download_json_escape "$JOBS_DOWNLOAD_COBALT_QUALITY_EFFECTIVE")"
  audio_format_json="$(jobs_download_json_escape "$JOBS_DOWNLOAD_COBALT_AUDIO_FORMAT_EFFECTIVE")"
  local_processing_json="$(jobs_download_json_escape "$JOBS_DOWNLOAD_COBALT_LOCAL_PROCESSING_EFFECTIVE")"
  print -r -- "{\"url\":${url_json},\"downloadMode\":${mode_json},\"videoQuality\":${quality_json},\"audioFormat\":${audio_format_json},\"filenameStyle\":\"pretty\",\"localProcessing\":${local_processing_json}}"
}
# 从 cobalt JSON 响应文件里读取指定 key path。
jobs_download_json_get() {
  emulate -L zsh

  local json_file="$1"
  local key_path="$2"
  plutil -extract "$key_path" raw -o - "$json_file" 2>/dev/null
}
# 清理下载文件名，避免 API 返回值携带路径分隔符。
jobs_download_sanitize_filename() {
  emulate -L zsh

  local filename="$1"
  filename="${filename//$'\r'/ }"
  filename="${filename//$'\n'/ }"
  filename="${filename//\//_}"
  filename="${filename//:/_}"
  filename="${filename## }"
  filename="${filename%% }"
  [[ -z "$filename" ]] && return 1
  print -r -- "$filename"
}
# 生成不覆盖已有文件的目标路径。
jobs_download_unique_path() {
  emulate -L zsh

  local target_path="$1"
  [[ ! -e "$target_path" ]] && print -r -- "$target_path" && return 0

  local stem ext index candidate
  if [[ "$target_path" == *.* ]]; then
    stem="${target_path%.*}"
    ext=".${target_path##*.}"
  else
    stem="$target_path"
    ext=""
  fi
  index=1
  while true; do
    candidate="${stem} (${index})${ext}"
    [[ ! -e "$candidate" ]] && print -r -- "$candidate" && return 0
    index=$((index + 1))
  done
}
# 从 URL 或 cobalt picker 类型推断文件扩展名。
jobs_download_extension_from_url() {
  emulate -L zsh

  local url="$1"
  local media_type="$2"
  local clean_url filename ext
  clean_url="${url%%#*}"
  clean_url="${clean_url%%\?*}"
  filename="${clean_url:t}"
  if [[ "$filename" == *.* ]]; then
    ext="${filename##*.}"
    if [[ -n "$ext" && "$ext" != "$filename" && ${#ext} -le 6 ]]; then
      print -r -- ".${ext}"
      return 0
    fi
  fi
  case "$media_type" in
    photo)
      print -r -- ".jpg"
      ;;
    gif)
      print -r -- ".gif"
      ;;
    video)
      print -r -- ".mp4"
      ;;
    *)
      print -r -- ".bin"
      ;;
  esac
}
# 下载 cobalt 返回的单个媒体 URL 到当前目录。
jobs_download_fetch_url() {
  emulate -L zsh

  local url="$1"
  local filename="${2:-}"
  local safe_filename target_path

  if [[ -n "$filename" ]]; then
    safe_filename="$(jobs_download_sanitize_filename "$filename")" || safe_filename=""
  fi
  if [[ -n "$safe_filename" ]]; then
    target_path="$(jobs_download_unique_path "$safe_filename")"
    info_echo "cobalt: 下载到 ${target_path}"
    curl -fL --retry 2 --connect-timeout 15 -o "$target_path" -- "$url"
    return $?
  fi

  info_echo "cobalt: 下载远端文件名"
  curl -fL --retry 2 --connect-timeout 15 -OJ -- "$url"
}
# 处理 cobalt redirect / tunnel 响应。
jobs_download_handle_cobalt_single() {
  emulate -L zsh

  local response_file="$1"
  local url filename
  url="$(jobs_download_json_get "$response_file" "url" || true)"
  filename="$(jobs_download_json_get "$response_file" "filename" || true)"
  if [[ -z "$url" ]]; then
    error_echo "cobalt: 响应缺少下载 URL"
    return 1
  fi
  jobs_download_fetch_url "$url" "$filename"
}
# 处理 cobalt picker 响应，默认把多图、多视频和可选音频全部下载下来。
jobs_download_handle_cobalt_picker() {
  emulate -L zsh

  local response_file="$1"
  local index=0
  local failed=0
  local total=0
  local item_url item_type ext filename audio_url audio_filename

  while item_url="$(jobs_download_json_get "$response_file" "picker.${index}.url" || true)"; [[ -n "$item_url" ]]; do
    item_type="$(jobs_download_json_get "$response_file" "picker.${index}.type" || true)"
    [[ -z "$item_type" ]] && item_type="item"
    ext="$(jobs_download_extension_from_url "$item_url" "$item_type")"
    filename="$(printf 'cobalt-picker-%02d%s' "$((index + 1))" "$ext")"
    jobs_download_fetch_url "$item_url" "$filename" || failed=1
    total=$((total + 1))
    index=$((index + 1))
  done

  audio_url="$(jobs_download_json_get "$response_file" "audio" || true)"
  if [[ -n "$audio_url" ]]; then
    audio_filename="$(jobs_download_json_get "$response_file" "audioFilename" || true)"
    [[ -z "$audio_filename" ]] && audio_filename="cobalt-picker-audio$(jobs_download_extension_from_url "$audio_url" "audio")"
    jobs_download_fetch_url "$audio_url" "$audio_filename" || failed=1
    total=$((total + 1))
  fi

  if (( total == 0 )); then
    error_echo "cobalt: picker 响应没有可下载项目"
    return 1
  fi
  return $failed
}
# 解释 cobalt API 响应状态，并分派到对应下载流程。
jobs_download_handle_cobalt_response() {
  emulate -L zsh

  local response_file="$1"
  local response_status error_code service
  response_status="$(jobs_download_json_get "$response_file" "status" || true)"
  case "$response_status" in
    redirect|tunnel)
      jobs_download_handle_cobalt_single "$response_file"
      ;;
    picker)
      jobs_download_handle_cobalt_picker "$response_file"
      ;;
    local-processing)
      service="$(jobs_download_json_get "$response_file" "service" || true)"
      error_echo "cobalt: 当前实例要求本地处理 local-processing，download 暂不在这里接管 ffmpeg 合并。"
      warn_echo "建议改用 yt-dlp，或把 cobalt 实例的 localProcessing 保持为 disabled。服务：${service:-unknown}"
      return 3
      ;;
    error)
      error_code="$(jobs_download_json_get "$response_file" "error.code" || true)"
      service="$(jobs_download_json_get "$response_file" "error.context.service" || true)"
      error_echo "cobalt: API 返回错误：${error_code:-unknown}"
      [[ -n "$service" ]] && warn_echo "cobalt: 关联服务：${service}"
      return 1
      ;;
    *)
      error_echo "cobalt: 未识别响应状态：${response_status:-empty}"
      return 1
      ;;
  esac
}
# 调用 yt-dlp，并自动使用默认浏览器 cookies。
jobs_download_run_ytdlp() {
  emulate -L zsh

  if ! command -v yt-dlp >/dev/null 2>&1; then
    error_echo "download: yt-dlp not found"
    warn_echo "install: brew install yt-dlp"
    return 127
  fi

  local browser
  browser="$(jobs_detect_default_browser_for_ytdlp)"
  if [[ -z "$browser" ]]; then
    warn_echo "download: 未识别默认浏览器，回退使用 chrome cookies"
    browser="chrome"
  fi
  info_echo "download: using yt-dlp cookies from browser: $browser"
  yt-dlp --cookies-from-browser "$browser" "$@"
}
# 调用已配置的 cobalt API，并把响应里的媒体文件下载到当前目录。
jobs_download_run_cobalt() {
  emulate -L zsh

  if [[ -z "$JOBS_DOWNLOAD_SOURCE_URL" ]]; then
    error_echo "cobalt: 需要传入 http/https URL"
    return 2
  fi
  if ! command -v curl >/dev/null 2>&1; then
    error_echo "cobalt: curl 不存在，无法调用 API"
    return 127
  fi
  if ! jobs_download_has_cobalt_api; then
    error_echo "cobalt: 未配置 API 地址"
    warn_echo "请先设置：export JOBS_DOWNLOAD_COBALT_API='https://你的-cobalt-api/'"
    warn_echo "官方不建议未经许可调用 api.cobalt.tools；download 默认不会把公开实例作为后端。"
    return 2
  fi

  local api response_file payload auth_header curl_status handle_status
  local -a curl_args
  api="$(jobs_download_cobalt_api_url)" || return 2
  if ! response_file="$(mktemp "${TMPDIR:-/tmp}/download-cobalt-response.XXXXXX")"; then
    error_echo "cobalt: 创建临时响应文件失败"
    return 1
  fi
  payload="$(jobs_download_make_cobalt_payload)"
  auth_header="$(jobs_download_cobalt_auth_header || true)"

  curl_args=(-fsSL -X POST -H "Accept: application/json" -H "Content-Type: application/json" -H "User-Agent: JobsDownload/1.0" --data "$payload" -o "$response_file")
  if [[ -n "$auth_header" ]]; then
    curl_args+=(-H "Authorization: $auth_header")
  fi
  curl_args+=("$api")

  info_echo "cobalt: POST ${api}"
  curl "${curl_args[@]}"
  curl_status=$?
  if (( curl_status != 0 )); then
    rm -f "$response_file"
    error_echo "cobalt: API 请求失败，curl exit=${curl_status}"
    return $curl_status
  fi

  jobs_download_handle_cobalt_response "$response_file"
  handle_status=$?
  rm -f "$response_file"
  return $handle_status
}
# 自动模式先走 yt-dlp，失败后在可用时兜底 cobalt。
jobs_download_run_auto() {
  emulate -L zsh

  local ytdlp_status
  if command -v yt-dlp >/dev/null 2>&1; then
    jobs_download_run_ytdlp "$@"
    ytdlp_status=$?
    (( ytdlp_status == 0 )) && return 0
    warn_echo "download: yt-dlp 下载失败，exit=${ytdlp_status}"
  else
    ytdlp_status=127
    warn_echo "download: 未检测到 yt-dlp"
  fi

  if jobs_download_has_cobalt_api; then
    warn_echo "download: 尝试切换到 cobalt API 兜底。"
    jobs_download_run_cobalt
    return $?
  fi

  warn_echo "download: cobalt API 未配置，无法自动兜底。"
  warn_echo "启用方式：export JOBS_DOWNLOAD_COBALT_API='https://你的-cobalt-api/'"
  return $ytdlp_status
}
# 根据解析后的后端策略执行下载。
jobs_download_dispatch() {
  emulate -L zsh

  if [[ "$JOBS_DOWNLOAD_SHOW_HELP" == "1" ]]; then
    jobs_download_print_usage
    return 0
  fi
  if (( ${#JOBS_DOWNLOAD_FORWARD_ARGS[@]} == 0 )); then
    jobs_download_print_usage
    return 1
  fi

  case "$JOBS_DOWNLOAD_BACKEND_EFFECTIVE" in
    auto)
      jobs_download_run_auto "${JOBS_DOWNLOAD_FORWARD_ARGS[@]}"
      ;;
    yt-dlp)
      jobs_download_run_ytdlp "${JOBS_DOWNLOAD_FORWARD_ARGS[@]}"
      ;;
    cobalt)
      jobs_download_run_cobalt
      ;;
  esac
}
# 暴露 download 命令业务函数，便于脚本入口和 source 模式复用。
download() {
  emulate -L zsh

  jobs_download_parse_args "$@" || return $?
  jobs_download_dispatch
}
# 编排脚本自述和媒体下载流程。
main() {
  show_script_intro_and_wait # 打印内置自述并阻塞确认，避免误触后立即发起下载。
  download "$@" # 按 auto / yt-dlp / cobalt 后端策略执行媒体下载。
}
# 初始化脚本运行环境，并按 source 模式决定是否执行入口。
initialize_script_module() {
  set -o pipefail
  setopt NO_NOMATCH
  : > "$LOG_FILE"
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    main "$@"
  fi
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
