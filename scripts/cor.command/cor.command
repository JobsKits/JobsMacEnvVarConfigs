#!/bin/zsh
# 脚本自述：
# - 脚本名称：cor.command
# - 核心用途：执行“cor”对应的自动化任务。
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
# ---------- 内置自述 ----------
jobs_cor_show_readme_and_wait() {
  clear 2>/dev/null || true
  cat <<'EOFREADME' | tee -a "$LOG_FILE" | jobs_intro_style auto
============================================================
cor - 颜色转换 / 终端色块预览
============================================================

功能：
  转换 HEX / RGB / RGBA / 0xAARRGGBB，并在 macOS 终端直接显示色块。

支持输入：
  #D2D4DE
  D2D4DE
  #D2D4DE80
  D2D4DE80
  #ABC
  #ABCF
  rgb(210,212,222)
  rgba(210,212,222,0.5)
  0x80D2D4DE       按 0xAARRGGBB 解析
  0xD2D4DE         按 0xRRGGBB 解析

说明：
  - macOS Terminal.app / iTerm2 / VS Code 终端默认使用 24-bit True Color 预览。
  - 透明度无法由终端背景色真实呈现；色块预览按 RGB 原色显示，Alpha 只参与格式转换。
  - 日志路径：/tmp/cor.log
============================================================
EOFREADME

  if [[ -t 0 && "${JOBS_MAC_ENV_SKIP_README:-}" != "1" ]]; then
    log "" | jobs_intro_style body
    warm_echo "按回车继续执行 cor..." | jobs_intro_style body
    local _answer=""
    IFS= read -r _answer
  fi
}
# ---------- 基础工具 ----------
jobs_cor_supports_truecolor() {
  emulate -L zsh

  # macOS 自带 Terminal.app 常常不设置 COLORTERM，但支持 24-bit ANSI True Color。
  [[ "${COLORTERM:-}" == *truecolor* ]] && return 0
  [[ "${COLORTERM:-}" == *24bit* ]] && return 0
  [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]] && return 0
  [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]] && return 0
  [[ "${TERM_PROGRAM:-}" == "vscode" ]] && return 0
  [[ "${TERM_PROGRAM:-}" == "WezTerm" ]] && return 0
  [[ "${TERM:-}" == *truecolor* ]] && return 0
  [[ "${TERM:-}" == *24bit* ]] && return 0

  return 1
}
# 封装 jobs_cor_title_color 对应的独立处理逻辑。
jobs_cor_title_color() {
  emulate -L zsh

  local esc=$'\033'
  if jobs_cor_supports_truecolor; then
    printf "%s" "${esc}[38;2;210;212;222m"
  else
    printf "%s" "${esc}[37m"
  fi
}
# 封装 jobs_cor_to_hex 对应的独立处理逻辑。
jobs_cor_to_hex() {
  emulate -L zsh
  printf "%02X" "$1"
}
# 封装 jobs_cor_hex_to_dec 对应的独立处理逻辑。
jobs_cor_hex_to_dec() {
  emulate -L zsh
  printf "%d" "$(( 16#$1 ))"
}
# 封装 jobs_cor_is_hex 对应的独立处理逻辑。
jobs_cor_is_hex() {
  emulate -L zsh
  [[ "$1" =~ '^[0-9a-fA-F]+$' ]]
}
# 封装 jobs_cor_expand_short_hex 对应的独立处理逻辑。
jobs_cor_expand_short_hex() {
  emulate -L zsh

  local hex="$1" out="" i c
  for (( i = 1; i <= ${#hex}; i++ )); do
    c="${hex[i]}"
    out+="${c}${c}"
  done
  print -r -- "$out"
}
# 封装 jobs_cor_alpha_float_to_255 对应的独立处理逻辑。
jobs_cor_alpha_float_to_255() {
  emulate -L zsh
  awk -v v="$1" 'BEGIN { if (v < 0) v = 0; if (v > 1) v = 1; printf("%d", (v * 255) + 0.5) }'
}
# 封装 jobs_cor_alpha_255_to_float 对应的独立处理逻辑。
jobs_cor_alpha_255_to_float() {
  emulate -L zsh
  awk -v v="$1" 'BEGIN { printf("%.2f", v / 255) }'
}
# 封装 jobs_cor_clamp_alpha_float 对应的独立处理逻辑。
jobs_cor_clamp_alpha_float() {
  emulate -L zsh
  awk -v v="$1" 'BEGIN { if (v < 0) v = 0; if (v > 1) v = 1; printf("%.2f", v) }'
}
# 封装 jobs_cor_sanitize_input 对应的独立处理逻辑。
jobs_cor_sanitize_input() {
  emulate -L zsh
  print -r -- "$1" | tr -d '[:space:]' | tr -d '"' | tr -d "'"
}
# 封装 jobs_cor_upper_hex 对应的独立处理逻辑。
jobs_cor_upper_hex() {
  emulate -L zsh
  print -r -- "$1" | tr '[:lower:]' '[:upper:]'
}
# 封装 jobs_cor_rel_luma 对应的独立处理逻辑。
jobs_cor_rel_luma() {
  emulate -L zsh
  awk -v r="$1" -v g="$2" -v b="$3" 'BEGIN { printf("%.0f", 0.2126 * r + 0.7152 * g + 0.0722 * b) }'
}
# 封装 jobs_cor_pick_fg_rgb 对应的独立处理逻辑。
jobs_cor_pick_fg_rgb() {
  emulate -L zsh

  local l
  l="$(jobs_cor_rel_luma "$1" "$2" "$3")"
  if (( l > 186 )); then
    print -r -- "0;0;0"
  else
    print -r -- "255;255;255"
  fi
}
# 封装 jobs_cor_pick_fg_code 对应的独立处理逻辑。
jobs_cor_pick_fg_code() {
  emulate -L zsh

  local l
  l="$(jobs_cor_rel_luma "$1" "$2" "$3")"
  if (( l > 186 )); then
    print -r -- "30"
  else
    print -r -- "97"
  fi
}
# 封装 jobs_cor_rgb_to_ansi256 对应的独立处理逻辑。
jobs_cor_rgb_to_ansi256() {
  emulate -L zsh

  local r="$1" g="$2" b="$3"
  if (( r == g && g == b )); then
    if (( r < 8 )); then
      print -r -- 16
      return 0
    elif (( r > 248 )); then
      print -r -- 231
      return 0
    else
      print -r -- $(( 232 + ((r - 8) * 24 / 247) ))
      return 0
    fi
  fi

  local rc=$(( r * 5 / 255 ))
  local gc=$(( g * 5 / 255 ))
  local bc=$(( b * 5 / 255 ))
  print -r -- $(( 16 + 36 * rc + 6 * gc + bc ))
}
# 封装 jobs_cor_set_globals_from_hex 对应的独立处理逻辑。
jobs_cor_set_globals_from_hex() {
  emulate -L zsh

  local hex="$1" mode="${2:-RRGGBB_OR_RRGGBBAA}" rr gg bb aa
  hex="$(jobs_cor_upper_hex "$hex")"

  case "$mode" in
    AARRGGBB)
      (( ${#hex} == 8 )) || return 1
      aa="${hex[1,2]}"
      rr="${hex[3,4]}"
      gg="${hex[5,6]}"
      bb="${hex[7,8]}"
      ;;
    RRGGBB)
      (( ${#hex} == 6 )) || return 1
      rr="${hex[1,2]}"
      gg="${hex[3,4]}"
      bb="${hex[5,6]}"
      aa="FF"
      ;;
    *)
      case "${#hex}" in
        3|4)
          hex="$(jobs_cor_expand_short_hex "$hex")"
          ;;
      esac

      case "${#hex}" in
        6)
          rr="${hex[1,2]}"
          gg="${hex[3,4]}"
          bb="${hex[5,6]}"
          aa="FF"
          ;;
        8)
          rr="${hex[1,2]}"
          gg="${hex[3,4]}"
          bb="${hex[5,6]}"
          aa="${hex[7,8]}"
          ;;
        *)
          return 1
          ;;
      esac
      ;;
  esac

  typeset -g JOBS_COR_R="$(jobs_cor_hex_to_dec "$rr")"
  typeset -g JOBS_COR_G="$(jobs_cor_hex_to_dec "$gg")"
  typeset -g JOBS_COR_B="$(jobs_cor_hex_to_dec "$bb")"
  typeset -g JOBS_COR_AA_HEX="$aa"
  typeset -g JOBS_COR_A_FLOAT="$(jobs_cor_alpha_255_to_float "$(jobs_cor_hex_to_dec "$aa")")"
  return 0
}
# ---------- 色块输出 ----------
jobs_cor_show_block_line() {
  emulate -L zsh

  local rr="$1" gg="$2" bb="$3" label="$4" fg_rgb fg_code idx

  if jobs_cor_supports_truecolor; then
    fg_rgb="$(jobs_cor_pick_fg_rgb "$rr" "$gg" "$bb")"
    printf "\033[48;2;%d;%d;%dm" "$rr" "$gg" "$bb"
    printf "\033[38;2;%sm" "$fg_rgb"
  else
    idx="$(jobs_cor_rgb_to_ansi256 "$rr" "$gg" "$bb")"
    fg_code="$(jobs_cor_pick_fg_code "$rr" "$gg" "$bb")"
    printf "\033[48;5;%sm" "$idx"
    printf "\033[%sm" "$fg_code"
  fi

  printf "  %-30s  " "$label"
  printf "\033[0m\n"
}
# 封装 jobs_cor_show_block 对应的独立处理逻辑。
jobs_cor_show_block() {
  emulate -L zsh

  local rr="$1" gg="$2" bb="$3" hex="$4"
  printf "\n"
  jobs_cor_show_block_line "$rr" "$gg" "$bb" "${hex}"
  jobs_cor_show_block_line "$rr" "$gg" "$bb" "RGB ${rr}, ${gg}, ${bb}"
  jobs_cor_show_block_line "$rr" "$gg" "$bb" "终端色块预览"
  printf "\n"
  if jobs_cor_supports_truecolor; then
    printf "前景色预览：\033[38;2;%d;%d;%dm%s\033[0m\n" "$rr" "$gg" "$bb" "${hex} 文字颜色"
  else
    local idx
    idx="$(jobs_cor_rgb_to_ansi256 "$rr" "$gg" "$bb")"
    printf "前景色预览：\033[38;5;%sm%s\033[0m\n" "$idx" "${hex} 文字颜色"
  fi
}
# ---------- 解析输入 ----------
jobs_cor_parse_rgb_parts() {
  emulate -L zsh

  local body="$1" R G B A A255
  local -a parts
  parts=("${(@s:,:)body}")

  R="${parts[1]:-}"
  G="${parts[2]:-}"
  B="${parts[3]:-}"
  A="${parts[4]:-1}"

  [[ -n "$R" && -n "$G" && -n "$B" ]] || return 1
  (( ${#parts} == 3 || ${#parts} == 4 )) || return 1

  R="${R%%.*}"
  G="${G%%.*}"
  B="${B%%.*}"

  if ! [[ "$R" =~ '^[0-9]+$' && "$G" =~ '^[0-9]+$' && "$B" =~ '^[0-9]+$' ]]; then
    return 1
  fi

  if (( R < 0 || R > 255 || G < 0 || G > 255 || B < 0 || B > 255 )); then
    return 1
  fi

  if ! [[ "$A" =~ '^([0-9]+([.][0-9]+)?|[.][0-9]+)$' ]]; then
    return 1
  fi

  typeset -g JOBS_COR_R="$R"
  typeset -g JOBS_COR_G="$G"
  typeset -g JOBS_COR_B="$B"
  typeset -g JOBS_COR_A_FLOAT="$(jobs_cor_clamp_alpha_float "$A")"
  A255="$(jobs_cor_alpha_float_to_255 "$JOBS_COR_A_FLOAT")"
  typeset -g JOBS_COR_AA_HEX="$(jobs_cor_to_hex "$A255")"
  return 0
}
# 封装 jobs_cor_parse_input 对应的独立处理逻辑。
jobs_cor_parse_input() {
  emulate -L zsh

  local raw="$1" input hex body
  input="$(jobs_cor_sanitize_input "$raw")"
  [[ -n "$input" ]] || return 1

  # 0xAARRGGBB / 0xRRGGBB
  if [[ "$input" =~ '^0[xX][0-9a-fA-F]{6}$' ]]; then
    hex="${input[3,-1]}"
    jobs_cor_set_globals_from_hex "$hex" "RRGGBB"
    return $?
  fi

  if [[ "$input" =~ '^0[xX][0-9a-fA-F]{8}$' ]]; then
    hex="${input[3,-1]}"
    jobs_cor_set_globals_from_hex "$hex" "AARRGGBB"
    return $?
  fi

  # #RGB / #RGBA / #RRGGBB / #RRGGBBAA
  if [[ "$input" == \#* ]]; then
    hex="${input[2,-1]}"
    jobs_cor_is_hex "$hex" || return 1
    jobs_cor_set_globals_from_hex "$hex"
    return $?
  fi

  # 裸 HEX：RGB / RGBA / RRGGBB / RRGGBBAA
  if jobs_cor_is_hex "$input"; then
    jobs_cor_set_globals_from_hex "$input"
    return $?
  fi

  # rgb(...) / rgba(...)
  if [[ "$input" =~ '^rgb\(.+\)$' ]]; then
    body="$(print -r -- "$input" | sed -E 's/^rgb\((.*)\)$/\1/')"
    jobs_cor_parse_rgb_parts "$body"
    return $?
  fi

  if [[ "$input" =~ '^rgba\(.+\)$' ]]; then
    body="$(print -r -- "$input" | sed -E 's/^rgba\((.*)\)$/\1/')"
    jobs_cor_parse_rgb_parts "$body"
    return $?
  fi

  return 1
}
# ---------- 输出 ----------
jobs_cor_format_and_print_all() {
  emulate -L zsh

  local raw="$1" RR GG BB AA HEX6 HEX8
  RR="$(jobs_cor_to_hex "$JOBS_COR_R")"
  GG="$(jobs_cor_to_hex "$JOBS_COR_G")"
  BB="$(jobs_cor_to_hex "$JOBS_COR_B")"
  AA="$JOBS_COR_AA_HEX"
  HEX6="#${RR}${GG}${BB}"
  HEX8="#${RR}${GG}${BB}${AA}"

  printf "\n\033[1m输入：%s\033[0m\n" "$raw"
  printf "%s\n" "----------------------------------------"
  printf "HEX（不透明）:  %s\n" "$HEX6"
  printf "HEX（含透明） :  %s\n" "$HEX8"
  printf "RGB           :  rgb(%d, %d, %d)\n" "$JOBS_COR_R" "$JOBS_COR_G" "$JOBS_COR_B"
  printf "RGBA          :  rgba(%d, %d, %d, %.2f)\n" "$JOBS_COR_R" "$JOBS_COR_G" "$JOBS_COR_B" "$JOBS_COR_A_FLOAT"
  printf "0xAARRGGBB    :  0x%s%s%s%s\n" "$AA" "$RR" "$GG" "$BB"
  if jobs_cor_supports_truecolor; then
    printf "终端支持      :  24-bit True Color\n"
  else
    printf "终端支持      :  ANSI 256 色近似\n"
  fi
  jobs_cor_show_block "$JOBS_COR_R" "$JOBS_COR_G" "$JOBS_COR_B" "$HEX6"
  printf "\n"
}
# 封装 jobs_cor_print_title 对应的独立处理逻辑。
jobs_cor_print_title() {
  emulate -L zsh

  local c reset=$'\033[0m'
  c="$(jobs_cor_title_color)"
  printf "%b================== 颜色格式转换器 ==================%b\n" "$c" "$reset"
  printf "%b支持：#RGB / #RRGGBB / #RRGGBBAA / rgb() / rgba() / 0xAARRGGBB%b\n" "$c" "$reset"
  printf "%b输出：HEX / RGB / RGBA / 0x，并显示终端色块预览%b\n" "$c" "$reset"
  printf "\n"
}
# 封装 jobs_cor_convert_once 对应的独立处理逻辑。
jobs_cor_convert_once() {
  emulate -L zsh

  local user_input="$1"
  if jobs_cor_parse_input "$user_input"; then
    jobs_cor_format_and_print_all "$user_input"
  else
    print -P "%F{red}❌ 无法识别：$user_input%f"
    print -r -- "示例：#D2D4DE、D2D4DE、#ABC、rgb(210,212,222)、rgba(210,212,222,0.5)、0x80D2D4DE"
    return 1
  fi
}
# 封装 jobs_cor_interactive_loop 对应的独立处理逻辑。
jobs_cor_interactive_loop() {
  emulate -L zsh

  local user_input
  while true; do
    read -r "user_input?请输入颜色值（q 退出）： " || {
      printf "\n"
      break
    }

    [[ -z "$user_input" ]] && continue

    case "$user_input" in
      q|Q|quit|QUIT|exit|EXIT)
        print -P "%F{green}✅ 已退出 cor%f"
        break
        ;;
    esac

    jobs_cor_convert_once "$user_input"
  done
}
# 封装 cor 对应的独立处理逻辑。
cor() {
  emulate -L zsh

  jobs_cor_print_title

  if (( $# > 0 )); then
    local failed=0 user_input
    for user_input in "$@"; do
      jobs_cor_convert_once "$user_input" || failed=1
    done
    return "$failed"
  fi

  jobs_cor_interactive_loop
}
# ---------- 主流程统一收口 ----------
jobs_cor_main() {
  # 展示脚本说明并等待用户确认影响范围。
  jobs_cor_show_readme_and_wait
  # 执行当前流程中的独立业务步骤：cor。
  cor "$@"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：cor.command' | jobs_intro_style title
  print -r -- '核心用途：执行“cor”对应的自动化任务。' | jobs_intro_style body
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
  # 执行 jobs_cor_main 对应的独立业务步骤。
  jobs_cor_main "$@"
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
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
