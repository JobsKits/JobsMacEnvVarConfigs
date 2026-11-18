#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】simios.command
# - 核心用途：执行“simios”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# JobsMacEnv function module / executable script.
# 作用：检测完整 Xcode 环境，然后下载 / 补齐 iOS Simulator Runtime。

# 说明：
# - 被 zsh/custom/【MacOS】local.zsh/【MacOS】local.zsh source 时，只注册 simios 函数，不自动执行。
# - 作为 ~/.local/bin/simios 或 Scripts/【MacOS】simios.command/【MacOS】simios.command 直接执行时，自动进入主流程。

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。


# >>> Jobs list parent confirmation >>>
# 只读确认键；返回码20仅交给实际启动本功能的list父菜单。
jobs_list_confirm_start() {
  emulate -L zsh
  local jobs_list_key='' jobs_list_prefix='' jobs_list_direction=''
  [[ -t 0 ]] || return 130
  print -u2 -n -r -- "$(jobs_prompt_render '按回车继续；← 返回功能菜单；Esc / Ctrl+C 取消：')"
  while true; do
    IFS= read -rsk1 jobs_list_key || return 130
    case "$jobs_list_key" in
      $'\r'|$'\n') print -u2; return 0 ;;
      $'\e')
        jobs_list_prefix=''
        IFS= read -rsk1 -t 0.12 jobs_list_prefix || { print -u2; return 130; }
        case "$jobs_list_prefix" in
          '['|'O')
            jobs_list_direction=''
            IFS= read -rsk1 -t 0.12 jobs_list_direction || { print -u2; return 130; }
            [[ "$jobs_list_direction" != D ]] || { print -u2; return 20; }
            ;;
          *) print -u2; return 130 ;;
        esac
        ;;
      $'\003') print -u2; return 130 ;;
    esac
  done
}
# 独立启动保留原read参数；list来源的返回/取消立即结束子脚本而不执行业务。
jobs_list_intro_read() {
  if [[ "${JOBS_LIST_PARENT_MENU:-}" != list ]]; then
    builtin read "$@"
    return $?
  fi
  local jobs_list_confirm_status=0
  jobs_list_confirm_start || jobs_list_confirm_status=$?
  (( jobs_list_confirm_status == 0 )) || exit "$jobs_list_confirm_status"
}
# <<< Jobs list parent confirmation <<<
# URL仅供显示；纯文本日志传color=0。
jobs_url_format() {
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-1}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", urlRender(pending)
        pending = $0; first = 0
      } else {
        if (!lines && !first) printf "\n"
        printf "%s", urlRender($0)
        if (lines) printf "\n"
        first = 0
      }
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", urlRender(pending)
      }
    }
  '
}
# URL仅供显示；纯文本日志传color=0。
jobs_url_stream() {
  local url_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then url_color=1; fi
  jobs_url_format "$url_color" "${1:-1}"
}
jobs_prompt_color_ready() {
  env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)' && return 1
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  # 中文字符类按UTF-8字符处理，仅约束此awk进程，保留调用者locale。
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" -v question="${4:-0}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
    function typedEnter(value, start, prefix) {
      prefix = substr(value, 1, start - 1)
      gsub(/[“”‘’「」『』"]/, "", prefix)
      gsub(sprintf("%c", 39), "", prefix)
      if (prefix ~ /(空格|[Ss][Pp][Aa][Cc][Ee])[[:space:]]*(后|再|并|[Tt][Hh][Ee][Nn])?[[:space:]]*$/) return 1
      return prefix ~ /(输入|键入|填写|[Tt]ype)[^；;|]*[[:alnum:]_+-]+[[:space:]]*(后|再|并)?[[:space:]]*$/
    }
    function greenPosition(value, token, start) {
      if (match(value, /(直接|仅|只需|只|按下|按)?[[:space:]]*(回车|回車)/)) {
        start = RSTART
        return typedEnter(value, start) ? 0 : start
      }
      if (!match(value, /(^|[^[:alnum:]_])([Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn])([^[:alnum:]_]|$)/)) return 0
      start = RSTART
      token = substr(value, RSTART, RLENGTH)
      match(token, /[Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]/)
      start += RSTART - 1
      return typedEnter(value, start) ? 0 : start
    }
    function segment(value, inherited, is_question, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
      if (value == "") return value
      kind = inherited
      start = 1
      if (!kind) {
        if (match(value, /(输入)?(任意|任何)(非空)?(字符|内容|输入|键)|非空(字符|内容|输入)?|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key/)) {
          red = RSTART
        }
        green = greenPosition(value)
        if (red && green && green < red) {
          left = substr(value, 1, red - 1)
          right = substr(value, red)
          connector = ""
          if (match(left, /(或者|或)[[:space:]]*$/)) {
            connector = substr(left, RSTART)
            left = substr(left, 1, RSTART - 1)
          }
          return segment(left, 0, is_question) connector segment(right, 31, 0)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31, is_question) "或" segment(substr(value, splitAt + length("或")), 0, 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!color) return value
      if (!kind) return is_question && value !~ /^[[:space:]]*$/ ? esc "[1;36m" value esc "[0m" : value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      if (is_question && prefix !~ /^[[:space:]]*$/) prefix = esc "[1;36m" prefix esc "[0m"
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original, question_body) {
      original = value
      value = urlProtect(urlClean(value, 0))
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return urlRender(original)
      output = ""
      inherited = 0
      depth = 0
      question_body = question
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited, question_body) boundary
        if (inherited || greenPosition(part) || part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) question_body = 0
        if (boundary ~ /[（(\[【]/) {
          depth++
          if (part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) inherited = 31
          else if (greenPosition(part)) inherited = 32
        } else if (boundary ~ /[）)\]】]/) {
          if (depth) depth--
        } else if (boundary ~ /[：:=＝]/) {
          if (!inherited) {
            if (part ~ /(任意|任何|非空|其它输入|其他输入)/) inherited = 31
            else if (greenPosition(part)) inherited = 32
          }
        } else if (!depth) inherited = 0
        value = substr(value, consumed)
      }
      return urlRender(urlRestore(output segment(value, inherited, question_body) (question && color ? esc "[0m" : "")))
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", render(pending)
        pending = $0
        first = 0
        next
      }
      if (!lines && !first) printf "\n"
      printf "%s", render($0)
      if (lines) printf "\n"
      first = 0
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", render(pending)
      }
    }
  '
}
# read 的命令替换会使 stdout 成为管道，按输入与提示所在 stderr 判断终端。
jobs_prompt_render() {
  local jobs_prompt_color=0
  if [ -t 0 ] && [ -t 2 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0 0 1
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 1
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous=""
  if [ "${1:-}" = print ]; then
    for jobs_prompt_arg in "$@"; do
      case "$jobs_prompt_arg" in -?*u2*|-u2) jobs_prompt_stderr=1 ;; esac
      if [ "$jobs_prompt_previous" = -u ] && [ "$jobs_prompt_arg" = 2 ]; then jobs_prompt_stderr=1; fi
      jobs_prompt_previous="$jobs_prompt_arg"
      [ "$jobs_prompt_arg" != -- ] || break
    done
  fi
  if [ -n "${ZSH_VERSION:-}" ]; then
    if [ "$jobs_prompt_stderr" = 1 ]; then
      "$@" 2>&1 | jobs_prompt_filter >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$?
  fi
  return "$jobs_prompt_status"
}
# 仅替换日志 primitive 的 tee：磁盘同步追加纯文，终端保留非选项原色。
jobs_prompt_tee() {
  local jobs_prompt_log="$1" jobs_prompt_line="" jobs_prompt_newline=0
  while :; do
    jobs_prompt_line=""
    if IFS= read -r jobs_prompt_line; then jobs_prompt_newline=1; else jobs_prompt_newline=0; [ -n "$jobs_prompt_line" ] || break; fi
    if [ "$jobs_prompt_newline" = 1 ]; then
      { printf '%s\n' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s\n' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    else
      { printf '%s' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    fi
  done
}
# JOBS_INPUT_CHOICE_STYLE_END

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
  ' | jobs_prompt_filter
}
_jobs_simios_module_file="${(%):-%N}"
# 按当前输出级别记录终端信息，并同步写入脚本日志。
_jobs_simios_cecho() {
  local color="$1"
  shift
  printf "%b%s%b\n" "$color" "$*" "${JOBS_SIMIOS_C_RESET:-\033[0m}"
}
# 封装 _jobs_simios_line 对应的独立处理逻辑。
_jobs_simios_line() {
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "────────────────────────────────────────"
}
# 封装 _jobs_simios_section 对应的独立处理逻辑。
_jobs_simios_section() {
  echo ""
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BOLD$JOBS_SIMIOS_C_CYAN" "▶ $1"
  _jobs_simios_line
}
# 封装 _jobs_simios_log 对应的独立处理逻辑。
_jobs_simios_log() {
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BLUE" "[simios] $1"
}
# 封装 _jobs_simios_ok 对应的独立处理逻辑。
_jobs_simios_ok() {
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GREEN" "[OK] $1"
}
# 封装 _jobs_simios_warn 对应的独立处理逻辑。
_jobs_simios_warn() {
  _jobs_simios_cecho "$JOBS_SIMIOS_C_YELLOW" "[WARN] $1"
}
# 封装 _jobs_simios_err 对应的独立处理逻辑。
_jobs_simios_err() {
  _jobs_simios_cecho "$JOBS_SIMIOS_C_RED" "[ERR] $1"
}
# 封装 _jobs_simios_pause_enter 对应的独立处理逻辑。
_jobs_simios_pause_enter() {
  local message="${1:-按回车继续...}"
  printf "%b%s%b" "$JOBS_SIMIOS_C_MAGENTA" "$message" "$JOBS_SIMIOS_C_RESET"
  local _input=""
  IFS= read -r _input
}
# 封装 _jobs_simios_ask_run 对应的独立处理逻辑。
_jobs_simios_ask_run() {
  local message="$1"
  local input=""
  jobs_prompt_output printf "%b%s%b" "$JOBS_SIMIOS_C_MAGENTA" "${message}（回车跳过，输入任意字符后回车执行）：" "$JOBS_SIMIOS_C_RESET"
  IFS= read -r input
  [[ -n "$input" ]]
}
# 封装 _jobs_simios_run_root 对应的独立处理逻辑。
_jobs_simios_run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
_jobs_simios_show_readme_and_wait() {
  clear || true
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BOLD$JOBS_SIMIOS_C_CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BOLD$JOBS_SIMIOS_C_CYAN" "              simios" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BOLD$JOBS_SIMIOS_C_CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_BLUE" "用途：检测完整 Xcode 环境，然后下载 / 补齐 iOS Simulator Runtime。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GREEN" "执行顺序：" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  1) 检测 macOS / Xcode.app 是否存在" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  2) 检测 xcodebuild 是否来自完整 Xcode，而不是只有 Command Line Tools" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  3) 检测 xcode-select 指向；不强制永久改系统，可临时使用 DEVELOPER_DIR" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  4) 检测 Xcode 首次启动组件 / license / 磁盘空间 / 网络连通" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  5) 最后由你决定是否执行 iOS 模拟器下载" | jobs_intro_style body
  echo "" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_YELLOW" "交互规则：" | jobs_intro_style title
  jobs_prompt_output _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  - 普通安装 / 更新 / 升级动作：回车跳过，输入任意字符后回车执行" | jobs_intro_style body | jobs_prompt_filter
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  - 必须修复项：脚本会明确说明原因，再让你继续" | jobs_intro_style body
  echo "" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GREEN" "核心下载命令：" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  xcodebuild -downloadPlatform iOS -verbose" | jobs_intro_style body
  echo "" | jobs_intro_style body
  _jobs_simios_cecho "$JOBS_SIMIOS_C_YELLOW" "说明：" | jobs_intro_style title
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "  xcodebuild 常见 verbose 参数是单横线 -verbose；如果你的版本支持 --verbose，脚本会自动使用 --verbose。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  _jobs_simios_pause_enter "按回车开始体检..."
}
# 封装 _jobs_simios_require_macos 对应的独立处理逻辑。
_jobs_simios_require_macos() {
  _jobs_simios_section "系统检测"

  if [[ "$(uname -s)" != "Darwin" ]]; then
    _jobs_simios_err "当前不是 macOS，无法下载 Xcode iOS Simulator Runtime。"
    return 1
  fi

  _jobs_simios_ok "当前系统是 macOS。"
}
# 封装 _jobs_simios_collect_xcode_apps 对应的独立处理逻辑。
_jobs_simios_collect_xcode_apps() {
  local -a found
  local item=""

  for item in \
    /Applications/Xcode.app \
    /Applications/Xcode*.app \
    "${HOME}/Applications/Xcode.app" \
    "${HOME}/Applications/Xcode"*.app \
    /Applications/Xcodes/Xcode*.app; do
    if [[ -d "${item}/Contents/Developer" && -x "${item}/Contents/Developer/usr/bin/xcodebuild" ]]; then
      found+=("$item")
    fi
  done

  if (( ${#found[@]} > 0 )); then
    printf "%s\n" "${found[@]}" | awk '!seen[$0]++'
  fi
}
# 封装 _jobs_simios_choose_xcode_app 对应的独立处理逻辑。
_jobs_simios_choose_xcode_app() {
  _jobs_simios_section "Xcode 检测"

  local active_dev=""
  local active_app=""
  active_dev="$(xcode-select -p 2>/dev/null || true)"

  if [[ "$active_dev" == */Contents/Developer ]]; then
    active_app="${active_dev%/Contents/Developer}"
    if [[ -d "$active_app" && -x "${active_app}/Contents/Developer/usr/bin/xcodebuild" ]]; then
      JOBS_SIMIOS_XCODE_APP="$active_app"
      _jobs_simios_ok "当前 xcode-select 已指向完整 Xcode：$JOBS_SIMIOS_XCODE_APP"
      return 0
    fi
  fi

  local first_app=""
  first_app="$(_jobs_simios_collect_xcode_apps | head -n 1)"

  if [[ -z "$first_app" ]]; then
    _jobs_simios_err "未检测到完整 Xcode.app。"
    _jobs_simios_warn "只安装 Command Line Tools 没有现实意义：iOS Simulator Runtime 下载依赖完整 Xcode。"
    _jobs_simios_warn "请先安装 Xcode，再重新运行：simios"
    echo ""
    _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "建议路径：/Applications/Xcode.app"
    _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "安装来源：Mac App Store 或 Apple Developer 下载页"
    return 1
  fi

  JOBS_SIMIOS_XCODE_APP="$first_app"
  _jobs_simios_ok "检测到 Xcode：$JOBS_SIMIOS_XCODE_APP"
}
# 封装 _jobs_simios_maybe_check_xcode_update 对应的独立处理逻辑。
_jobs_simios_maybe_check_xcode_update() {
  echo ""
  if _jobs_simios_ask_run "Xcode 已存在，是否打开更新入口检查 Xcode 升级"; then
    if command -v mas >/dev/null 2>&1; then
      _jobs_simios_log "检测到 mas，尝试升级 App Store 版 Xcode。"
      mas upgrade 497799835 || open "macappstore://itunes.apple.com/app/id497799835" || true
    else
      _jobs_simios_warn "未检测到 mas。为了避免额外引入 Homebrew / mas，本脚本不自动安装它。"
      _jobs_simios_log "改为打开 App Store 的 Xcode 页面。"
      open "macappstore://itunes.apple.com/app/id497799835" || true
    fi
  else
    _jobs_simios_log "跳过 Xcode 升级检查。"
  fi
}
# 封装 _jobs_simios_prepare_developer_dir 对应的独立处理逻辑。
_jobs_simios_prepare_developer_dir() {
  _jobs_simios_section "xcode-select / DEVELOPER_DIR 检测"

  JOBS_SIMIOS_DEVELOPER_DIR_SELECTED="${JOBS_SIMIOS_XCODE_APP}/Contents/Developer"
  JOBS_SIMIOS_XCODEBUILD_BIN="${JOBS_SIMIOS_DEVELOPER_DIR_SELECTED}/usr/bin/xcodebuild"

  if [[ ! -x "$JOBS_SIMIOS_XCODEBUILD_BIN" ]]; then
    _jobs_simios_err "xcodebuild 不存在或不可执行：$JOBS_SIMIOS_XCODEBUILD_BIN"
    return 1
  fi

  export DEVELOPER_DIR="$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED"

  local active_dev=""
  active_dev="$(xcode-select -p 2>/dev/null || true)"

  _jobs_simios_ok "本次脚本使用：DEVELOPER_DIR=$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED"

  if [[ "$active_dev" == "$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED" ]]; then
    _jobs_simios_ok "系统 xcode-select 指向正确。"
  else
    _jobs_simios_warn "系统 xcode-select 当前指向：${active_dev:-未设置}"
    _jobs_simios_warn "脚本本次会临时使用 DEVELOPER_DIR，不强制修改你的全局设置。"
    if _jobs_simios_ask_run "是否永久切换 xcode-select 到当前 Xcode"; then
      _jobs_simios_run_root xcode-select -s "$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED"
      _jobs_simios_ok "已永久切换 xcode-select。"
    else
      _jobs_simios_log "跳过永久切换，仅本次脚本临时使用当前 Xcode。"
    fi
  fi
}
# 封装 _jobs_simios_show_xcode_version 对应的独立处理逻辑。
_jobs_simios_show_xcode_version() {
  _jobs_simios_section "Xcode 版本"
  "$JOBS_SIMIOS_XCODEBUILD_BIN" -version || {
    _jobs_simios_err "xcodebuild 无法正常输出版本。"
    return 1
  }
}
# 封装 _jobs_simios_check_xcodebuild_support 对应的独立处理逻辑。
_jobs_simios_check_xcodebuild_support() {
  _jobs_simios_section "xcodebuild 能力检测"

  local help_text=""
  help_text="$({ "$JOBS_SIMIOS_XCODEBUILD_BIN" -help || true; } 2>&1)"

  if ! printf "%s\n" "$help_text" | grep -q -- "downloadPlatform"; then
    _jobs_simios_err "当前 Xcode 的 xcodebuild 不支持 -downloadPlatform。"
    _jobs_simios_warn "这通常说明 Xcode 版本过旧，需要先升级 Xcode。"
    _jobs_simios_maybe_check_xcode_update
    return 1
  fi

  _jobs_simios_ok "支持 -downloadPlatform。"

  if printf "%s\n" "$help_text" | grep -q -- "--verbose"; then
    JOBS_SIMIOS_VERBOSE_ARG="--verbose"
  else
    JOBS_SIMIOS_VERBOSE_ARG="-verbose"
  fi

  _jobs_simios_ok "verbose 参数使用：$JOBS_SIMIOS_VERBOSE_ARG"
}
# 封装 _jobs_simios_ensure_first_launch 对应的独立处理逻辑。
_jobs_simios_ensure_first_launch() {
  _jobs_simios_section "Xcode 首次启动组件检测"

  local help_text=""
  help_text="$({ "$JOBS_SIMIOS_XCODEBUILD_BIN" -help || true; } 2>&1)"

  if printf "%s\n" "$help_text" | grep -q -- "checkFirstLaunchStatus"; then
    if "$JOBS_SIMIOS_XCODEBUILD_BIN" -checkFirstLaunchStatus >/dev/null 2>&1; then
      _jobs_simios_ok "Xcode 首次启动组件状态正常。"
    else
      _jobs_simios_warn "Xcode 首次启动组件未完成。"
      _jobs_simios_warn "这属于执行 xcodebuild 下载前的必要支援项，需要安装 / 初始化。"
      _jobs_simios_pause_enter "按回车执行：sudo xcodebuild -runFirstLaunch ..."
      _jobs_simios_run_root "$JOBS_SIMIOS_XCODEBUILD_BIN" -runFirstLaunch
      _jobs_simios_ok "首次启动组件已处理。"
    fi
  else
    _jobs_simios_warn "当前 xcodebuild 不支持 -checkFirstLaunchStatus。"
    if _jobs_simios_ask_run "是否执行一次 xcodebuild -runFirstLaunch 做初始化"; then
      _jobs_simios_run_root "$JOBS_SIMIOS_XCODEBUILD_BIN" -runFirstLaunch
      _jobs_simios_ok "已执行首次启动初始化。"
    else
      _jobs_simios_log "跳过首次启动初始化。"
    fi
  fi
}
# 封装 _jobs_simios_ensure_license 对应的独立处理逻辑。
_jobs_simios_ensure_license() {
  _jobs_simios_section "Xcode License 检测"

  if "$JOBS_SIMIOS_XCODEBUILD_BIN" -license check >/dev/null 2>&1; then
    _jobs_simios_ok "Xcode license 已同意。"
    return 0
  fi

  _jobs_simios_warn "Xcode license 尚未同意。"
  _jobs_simios_warn "不同意 license 时，xcodebuild 后续下载大概率会失败。"
  _jobs_simios_pause_enter "按回车进入交互式 license 确认：sudo xcodebuild -license ..."
  _jobs_simios_run_root "$JOBS_SIMIOS_XCODEBUILD_BIN" -license

  if "$JOBS_SIMIOS_XCODEBUILD_BIN" -license check >/dev/null 2>&1; then
    _jobs_simios_ok "Xcode license 已同意。"
  else
    _jobs_simios_err "license 仍未通过检查，停止执行。"
    return 1
  fi
}
# 封装 _jobs_simios_check_disk_space 对应的独立处理逻辑。
_jobs_simios_check_disk_space() {
  _jobs_simios_section "磁盘空间检测"

  local free_kb="0"
  local free_gb="0"
  free_kb="$(df -k "$HOME" | awk 'NR==2 {print $4}')"
  free_gb=$(( free_kb / 1024 / 1024 ))

  if (( free_gb >= 30 )); then
    _jobs_simios_ok "当前用户目录所在磁盘可用空间约 ${free_gb}GB。"
  elif (( free_gb >= 15 )); then
    _jobs_simios_warn "当前可用空间约 ${free_gb}GB，可能够用，但大型 runtime 可能吃紧。"
  else
    _jobs_simios_warn "当前可用空间约 ${free_gb}GB，iOS Simulator Runtime 下载很可能失败。"
  fi
}
# 封装 _jobs_simios_check_network 对应的独立处理逻辑。
_jobs_simios_check_network() {
  _jobs_simios_section "网络连通检测"

  if ! command -v curl >/dev/null 2>&1; then
    _jobs_simios_warn "未检测到 curl，跳过网络预检。macOS 正常情况下会自带 curl。"
    return 0
  fi

  if curl -Is --connect-timeout 10 https://developer.apple.com >/dev/null 2>&1; then
    _jobs_simios_ok "developer.apple.com 可连接。"
  else
    _jobs_simios_warn "developer.apple.com 连接预检失败。可能是网络、代理、VPN、DNS 或 Apple CDN 临时问题。"
    _jobs_simios_warn "这不是本地环境硬缺失，脚本不会自动改网络设置。"
  fi
}
# 封装 _jobs_simios_list_ios_runtimes 对应的独立处理逻辑。
_jobs_simios_list_ios_runtimes() {
  if DEVELOPER_DIR="$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED" xcrun simctl runtime list >/dev/null 2>&1; then
    DEVELOPER_DIR="$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED" xcrun simctl runtime list 2>/dev/null | grep -i "iOS" || true
  else
    DEVELOPER_DIR="$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED" xcrun simctl list runtimes 2>/dev/null | grep -i "iOS" || true
  fi
}
# 封装 _jobs_simios_show_existing_runtimes 对应的独立处理逻辑。
_jobs_simios_show_existing_runtimes() {
  _jobs_simios_section "现有 iOS Runtime"

  local runtimes=""
  runtimes="$(_jobs_simios_list_ios_runtimes)"

  if [[ -n "$runtimes" ]]; then
    _jobs_simios_ok "检测到 iOS Runtime："
    printf "%s\n" "$runtimes"
  else
    _jobs_simios_warn "未检测到 iOS Runtime，稍后建议执行下载。"
  fi
}
# 封装 _jobs_simios_run_download 对应的独立处理逻辑。
_jobs_simios_run_download() {
  _jobs_simios_section "下载 / 补齐 iOS Simulator Runtime"

  mkdir -p "$JOBS_SIMIOS_LOG_DIR"

  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "日志文件：$JOBS_SIMIOS_LOG_FILE"
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "将执行：xcodebuild -downloadPlatform iOS $JOBS_SIMIOS_VERBOSE_ARG"
  echo ""

  if ! _jobs_simios_ask_run "是否开始下载 / 补齐 iOS Simulator Runtime"; then
    _jobs_simios_log "已跳过下载。"
    return 0
  fi

  local -a args
  args=(-downloadPlatform iOS "$JOBS_SIMIOS_VERBOSE_ARG")

  set +e
  DEVELOPER_DIR="$JOBS_SIMIOS_DEVELOPER_DIR_SELECTED" "$JOBS_SIMIOS_XCODEBUILD_BIN" "${args[@]}" 2>&1 | tee "$JOBS_SIMIOS_LOG_FILE"
  local command_status=${pipestatus[1]}
  set -e

  if (( command_status != 0 )); then
    _jobs_simios_err "下载命令失败，退出码：$command_status"
    _jobs_simios_warn "完整日志：$JOBS_SIMIOS_LOG_FILE"
    _jobs_simios_warn "常见原因：license 未同意、Xcode 未完成首次启动、网络 / CDN 异常、磁盘空间不足、Xcode 版本过旧。"
    return "$command_status"
  fi

  _jobs_simios_ok "iOS Simulator Runtime 下载 / 补齐命令执行完成。"
}
# 封装 _jobs_simios_final_report 对应的独立处理逻辑。
_jobs_simios_final_report() {
  _jobs_simios_section "完成报告"

  _jobs_simios_ok "脚本执行结束。"
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "日志路径：$JOBS_SIMIOS_LOG_FILE"
  echo ""
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GREEN" "当前 iOS Runtime："
  _jobs_simios_list_ios_runtimes || true
  echo ""
  _jobs_simios_cecho "$JOBS_SIMIOS_C_GRAY" "如果 Xcode UI 里暂时看不到新 runtime，重启 Xcode 后再看。"
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
_jobs_simios_main() {
  # 执行当前流程中的独立业务步骤：emulate。
  emulate -L zsh
  # 执行当前流程中的独立业务步骤：set。
  set -e
  # 执行当前流程中的独立业务步骤：set。
  set -o pipefail
  # 执行当前流程中的独立业务步骤：setopt。
  setopt NULL_GLOB

  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_RESET='\033[0m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_BOLD='\033[1m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_BLUE='\033[34m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_CYAN='\033[36m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_GREEN='\033[32m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_YELLOW='\033[33m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_MAGENTA='\033[35m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_RED='\033[31m'
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_C_GRAY='\033[90m'

  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_XCODE_APP=""
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_DEVELOPER_DIR_SELECTED=""
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_XCODEBUILD_BIN=""
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_VERBOSE_ARG="-verbose"
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_LOG_DIR="${HOME}/Library/Logs/simios"
  # 初始化当前流程后续步骤需要使用的变量。
  JOBS_SIMIOS_LOG_FILE="${JOBS_SIMIOS_LOG_DIR}/simios-$(date '+%Y%m%d-%H%M%S').log"

  # 展示脚本说明并等待用户确认影响范围。
  _jobs_simios_show_readme_and_wait
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_require_macos
  # 执行当前流程中的独立业务步骤：_jobs_simios_choose_xcode_app。
  _jobs_simios_choose_xcode_app
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_maybe_check_xcode_update
  # 准备后续业务需要的配置、目录或运行上下文。
  _jobs_simios_prepare_developer_dir
  # 执行当前流程中的独立业务步骤：_jobs_simios_show_xcode_version。
  _jobs_simios_show_xcode_version
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_check_xcodebuild_support
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_ensure_first_launch
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_ensure_license
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_check_disk_space
  # 检查当前步骤所需的环境、路径或输入条件。
  _jobs_simios_check_network
  # 执行当前流程中的独立业务步骤：_jobs_simios_show_existing_runtimes。
  _jobs_simios_show_existing_runtimes
  # 执行当前流程中的独立业务步骤：_jobs_simios_run_download。
  _jobs_simios_run_download
  # 执行当前流程中的独立业务步骤：_jobs_simios_final_report。
  _jobs_simios_final_report
  # 执行当前流程中的独立业务步骤：_jobs_simios_pause_enter。
  _jobs_simios_pause_enter "按回车退出..."
}
# 终端入口：安装 JobsMacEnv 后可直接执行 simios
simios() {
  _jobs_simios_main "$@"
}

_jobs_simios_module_file_abs="${_jobs_simios_module_file:A}"
_jobs_simios_argv0_abs="${0:A}"
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】simios.command' | jobs_intro_style title
  print -r -- '核心用途：执行“simios”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    exit 1
  fi
  jobs_list_intro_read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _ || exit 1
}
# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  show_script_intro_and_wait || return $? # 展示脚本内置自述，并按运行入口完成防误触确认。
  _jobs_simios_main "$@" # 执行 _jobs_simios_main 对应的独立业务步骤。
}
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_module() {
  if [[ "${JOBS_MAC_ENV_SOURCE_MODE:-}" != "1" ]]; then
    if [[ "$_jobs_simios_module_file" == "$0" || "$_jobs_simios_module_file_abs" == "$_jobs_simios_argv0_abs" ]]; then
      main "$@"
    fi
  fi
  unset _jobs_simios_module_file _jobs_simios_module_file_abs _jobs_simios_argv0_abs 2>/dev/null || true
}
# 加载模块时统一执行必要的初始化和入口分派。
initialize_script_module "$@"
