#!/bin/zsh
# 脚本自述：
# - 脚本名称：ts.command
# - 核心用途：执行“ts”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


# ---------- 基础路径 ----------
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
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
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
# ---------- 彩色日志 ----------
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
jobs_ts_show_readme_and_wait() {
  clear 2>/dev/null || true
  cat <<'EOFREADME' | tee -a "$LOG_FILE" | jobs_intro_style auto
============================================================
ts - 时间戳转换
============================================================

这是 ts.command 的内置自述，不读取同级 README.md。

功能：
  识别秒 / 毫秒 / 微秒 / 纳秒时间戳，并转换为本地时间。

结构：
  Scripts/ts.command/ts.command
  Scripts/ts.command/README.md

运行：
  ts
  ts [参数...]

说明：
  - 终端可输入的自定义命令都应独立收进 Scripts。
  - README.md 只作为源码说明；运行时展示的是脚本内置自述。
  - 日志路径：/tmp/ts.log
============================================================
EOFREADME

  if [[ -t 0 && "${JOBS_MAC_ENV_SKIP_README:-}" != "1" ]]; then
    log "" | jobs_intro_style body
    warm_echo "按回车继续执行 ts..." | jobs_intro_style body
    local _answer=""
    IFS= read -r _answer
  fi
}
# ---------- 命令实现 ----------
# ================================== 时间戳转换 ==================================
# ts
# 交互式输入 Unix 时间戳，并输出完整时间：年、月、日、时、分、秒、周几、时区。
# 时区选择：直接回车使用当前系统时区；输入任意字符后用 fzf 选择其他时区。
# 自动识别常见时间戳精度：秒 / 毫秒 / 微秒 / 纳秒。
# 封装 ts 对应的独立处理逻辑。
ts() {
  emulate -L zsh
  setopt no_nomatch

  local input tz_trigger selected_tz

  if ! command -v python3 >/dev/null 2>&1; then
    print -P "%F{red}❌ 未检测到 python3，无法转换时间戳%f"
    return 1
  fi
  # 封装 _jobs_ts_read_line 对应的独立处理逻辑。
  _jobs_ts_read_line() {
    emulate -L zsh

    local prompt="$1"
    local ch line=""

    printf "%s" "$prompt" > /dev/tty

    while true; do
      if ! IFS= read -r -s -k 1 ch < /dev/tty; then
        printf "\n" > /dev/tty
        return 130
      fi

      case "$ch" in
        $'\e')
          printf "\n" > /dev/tty
          return 130
          ;;
        $'\n'|$'\r')
          printf "\n" > /dev/tty
          REPLY="$line"
          return 0
          ;;
        $'\177'|$'\b')
          if [[ -n "$line" ]]; then
            line="${line[1,-2]}"
            printf '\b \b' > /dev/tty
          fi
          ;;
        $'\003'|$'\004')
          printf "\n" > /dev/tty
          return 130
          ;;
        *)
          line+="$ch"
          printf "%s" "$ch" > /dev/tty
          ;;
      esac
    done
  }

  while true; do
    if ! _jobs_ts_read_line "请输入时间戳（Esc 退出）："; then
      print -P "%F{yellow}已取消%f"
      return 130
    fi

    input="$REPLY"

    if [[ -n "${input//[[:space:]]/}" ]]; then
      break
    fi

    print -P "%F{red}❌ 时间戳不能为空%f"
  done

  if ! _jobs_ts_read_line "时区：直接回车使用当前时区；输入任意字符后用 fzf 选择其他时区（Esc 退出）："; then
    print -P "%F{yellow}已取消%f"
    return 130
  fi

  tz_trigger="$REPLY"

  if [[ -n "${tz_trigger//[[:space:]]/}" ]]; then
    if ! command -v fzf >/dev/null 2>&1; then
      print -P "%F{red}❌ 未检测到 fzf。先安装：brew install fzf%f"
      return 1
    fi

    selected_tz="$(
      python3 - <<'PY' | fzf --prompt='选择时区：' --height=60% --border
import os

zones = set()
try:
    from zoneinfo import available_timezones
    zones.update(available_timezones())
except Exception:
    base = "/usr/share/zoneinfo"
    skip_dirs = {"posix", "right", "SystemV", "Etc"}
    skip_files = {"localtime", "posixrules", "leapseconds", "tzdata.zi", "zone.tab", "zone1970.tab", "iso3166.tab"}
    if os.path.isdir(base):
        for root, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if d not in skip_dirs and not d.startswith(".")]
            for name in files:
                if name in skip_files or name.startswith("."):
                    continue
                full_path = os.path.join(root, name)
                rel_path = os.path.relpath(full_path, base)
                if os.path.sep in rel_path:
                    zones.add(rel_path.replace(os.path.sep, "/"))

for zone in sorted(zones):
    print(zone)
PY
    )"

    if [[ -z "$selected_tz" ]]; then
      print -P "%F{yellow}⚠️  未选择时区，已取消%f"
      return 130
    fi
  fi

  python3 - "$input" "$selected_tz" <<'PY'
import os
import sys
import time
from decimal import Decimal, InvalidOperation
from datetime import datetime

try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

WEEKDAYS = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]


def local_zone_name(dt):
    for path in ("/etc/localtime", "/var/db/timezone/localtime"):
        try:
            real_path = os.path.realpath(path)
        except Exception:
            continue
        marker = "/zoneinfo/"
        if marker in real_path:
            return real_path.split(marker, 1)[1]
    return os.environ.get("TZ") or dt.tzname() or "当前系统时区"


def parse_timestamp(raw):
    value = raw.strip()
    if value.startswith("@"):
        value = value[1:]

    try:
        number = Decimal(value)
    except InvalidOperation:
        raise ValueError("时间戳格式不正确，只支持数字，例如 1715400000 或 1715400000000")

    plain_digits = value.lstrip("+-")
    unit = "秒"
    seconds = number

    if "." not in plain_digits and "e" not in plain_digits.lower():
        digits = plain_digits.lstrip("0") or "0"
        length = len(digits)
        if length >= 19:
            seconds = number / Decimal(1_000_000_000)
            unit = "纳秒"
        elif length >= 16:
            seconds = number / Decimal(1_000_000)
            unit = "微秒"
        elif length >= 13:
            seconds = number / Decimal(1_000)
            unit = "毫秒"

    return float(seconds), unit


def format_offset(dt):
    offset = dt.strftime("%z")
    if len(offset) == 5:
        return f"{offset[:3]}:{offset[3:]}"
    return offset or "未知偏移"


raw = sys.argv[1]
zone_name = sys.argv[2] if len(sys.argv) > 2 else ""

try:
    seconds, unit = parse_timestamp(raw)

    if zone_name:
        if ZoneInfo is not None:
            dt = datetime.fromtimestamp(seconds, ZoneInfo(zone_name))
        elif hasattr(time, "tzset"):
            os.environ["TZ"] = zone_name
            time.tzset()
            dt = datetime.fromtimestamp(seconds).astimezone()
        else:
            raise RuntimeError("当前 python3 不支持指定时区转换")
        zone_label = zone_name
    else:
        dt = datetime.fromtimestamp(seconds).astimezone()
        zone_label = local_zone_name(dt)

    print(f"时间戳：{raw.strip()}（识别为：{unit}）")
    print(f"完整时间：{dt.year:04d}年{dt.month:02d}月{dt.day:02d}日 {dt.hour:02d}:{dt.minute:02d}:{dt.second:02d} {WEEKDAYS[dt.weekday()]}")
    print(f"时区：{zone_label}（UTC{format_offset(dt)}，{dt.tzname() or '未知缩写'}）")
except Exception as exc:
    print(f"❌ 转换失败：{exc}", file=sys.stderr)
    sys.exit(1)
PY
}
# ---------- 主流程统一收口 ----------
jobs_ts_main() {
  # 展示脚本说明并等待用户确认影响范围。
  jobs_ts_show_readme_and_wait
  # 执行当前流程中的独立业务步骤：ts。
  ts "$@"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：ts.command' | jobs_intro_style title
  print -r -- '核心用途：执行“ts”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_script_intro_and_wait
  # 执行 jobs_ts_main 对应的独立业务步骤。
  jobs_ts_main "$@"
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  set -o pipefail
  setopt NO_NOMATCH
  : > "$LOG_FILE"
  unalias ts 2>/dev/null
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    main "$@"
  fi
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
