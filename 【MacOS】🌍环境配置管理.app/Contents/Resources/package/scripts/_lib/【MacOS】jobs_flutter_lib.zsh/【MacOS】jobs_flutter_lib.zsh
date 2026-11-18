# JobsMacEnv Flutter private library. Do not call directly.
# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
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

# SDK 网络函数在模块定义完成后由唯一初始化入口加载。

# 解析 PATH 中的真实外部命令，跳过当前脚本自身，避免 flutter 自定义入口递归调用自己。
# 输出当前脚本内的 Homebrew 健康诊断。
jobs_brew_note() {
  jobs_prompt_output print -u2 -r -- "ℹ $*"
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
jobs_flutter_find_external_command() {
  emulate -L zsh

  local command_name="$1"
  local path_dir=""
  local candidate=""
  local candidate_real=""
  local script_real=""

  if [[ -n "${SCRIPT_PATH:-}" && -e "$SCRIPT_PATH" ]]; then
    script_real="$(cd "${SCRIPT_PATH:h}" 2>/dev/null && pwd -P)/${SCRIPT_PATH:t}"
  fi

  for path_dir in ${(s.:.)PATH}; do
    [[ -n "$path_dir" ]] || continue
    candidate="$path_dir/$command_name"
    [[ -x "$candidate" ]] || continue

    candidate_real="$(cd "${candidate:h}" 2>/dev/null && pwd -P)/${candidate:t}"
    [[ -n "$script_real" && "$candidate_real" == "$script_real" ]] && continue

    print -r -- "$candidate"
    return 0
  done

  return 1
}

# ================================== 项目 / 开发环境命令 ==================================
# 显式配置优先；未指定项目时由命令所在的当前工程上下文发现。
JOBS_FLUTTER_PROJECT_DIR="${JOBS_FLUTTER_PROJECT_DIR:-}"
JOBS_DART_CLI_COMPLETION_FILE="${JOBS_DART_CLI_COMPLETION_FILE:-$HOME/.dart-cli-completion/zsh-config.zsh}"

# ================================== 通用：项目目录自检与解析 ==================================
# 只展开当前用户的 ~/，其余路径按字面值处理，避免执行输入中的 Shell 表达式。
jobs_flutter_resolve_directory() {
  emulate -L zsh
  local dir="${1:-}"

  case "$dir" in
    '~') dir="$HOME" ;;
    '~/'*) dir="$HOME/${dir#\~/}" ;;
  esac
  [[ -n "$dir" && -d "$dir" ]] || return 1
  (builtin cd -q -P -- "${dir:A}" && builtin pwd -P)
}
# 用法：
#   jobs_flutter_get_project_dir             -> 用环境配置，未配置时向上查找当前工程
#   jobs_flutter_get_project_dir "./工程"    -> 用显式路径（会自检）
jobs_flutter_get_project_dir() {
  emulate -L zsh
  local dir="${1:-${JOBS_FLUTTER_PROJECT_DIR:-}}" search_dir=""

  if [[ -z "$dir" ]]; then
    search_dir="$(builtin pwd -P)" || return 1
    while true; do
      if [[ -f "$search_dir/pubspec.yaml" ]]; then
        dir="$search_dir"
        break
      fi
      [[ "$search_dir" == / ]] && break
      search_dir="${search_dir:h}"
    done
    if [[ -z "$dir" ]]; then
      print -u2 -r -- "❌ 当前目录及其上级未找到 pubspec.yaml：$PWD"
      print -u2 -r -- '👉 请进入项目目录，传入项目路径，或设置 JOBS_FLUTTER_PROJECT_DIR。'
      return 1
    fi
  fi

  if ! search_dir="$(jobs_flutter_resolve_directory "$dir")"; then
    print -u2 -r -- "❌ 项目目录不存在：$dir（当前目录：$PWD）"
    print -u2 -r -- '👉 请检查传入路径或 JOBS_FLUTTER_PROJECT_DIR；支持相对路径和 ~/。'
    return 1
  fi
  dir="$search_dir"

  # Flutter 项目轻自检（不强制失败，主要是提示你配错目录）
  if [[ ! -f "$dir/pubspec.yaml" || ! -d "$dir/lib" ]]; then
    echo "⚠️  目录存在，但不像 Flutter 项目（缺少 pubspec.yaml 或 lib/）：$dir" >&2
  fi

  printf "%s\n" "$dir"
}

# ================================== Homebrew 第三方更新（formula/cask/tap） ==================================
jobs_flutter_brew_update_third_party() {
  local brew_bin=""
  if ! brew_bin="$(jobs_brew_find)"; then
    echo "⚠️  [brew] unavailable, skip update"
    return 0
  fi

  echo "➤ 🍺 brew update"
  "$brew_bin" update || { echo "✖ brew update failed; stop further updates" >&2; return 1; }

  echo "➤ 📌 brew tap (refresh)"
  "$brew_bin" tap --repair >/dev/null 2>&1 || true

  echo "➤ ⬆️  brew upgrade (formula + cask)"
  "$brew_bin" upgrade || echo "⚠️  brew upgrade failed (ignored)"
  "$brew_bin" upgrade --cask || echo "⚠️  brew upgrade --cask failed (ignored)"

  echo "➤ 🧹 brew cleanup"
  "$brew_bin" cleanup || echo "⚠️  brew cleanup failed (ignored)"

  echo "➤ 🩺 brew doctor (optional)"
  "$brew_bin" doctor || echo "⚠️  brew doctor warnings (ignored)"

  echo "✅ brew third-party update done"
}

# 🔥 通用：jobs_flutter_try_run 🔥
jobs_flutter_try_run() {
  local cmd="$1"; shift
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "✅ [$cmd] detected, running: $*"
    eval "$@"
  else
    echo "⚠️  [$cmd] not installed, skip: $*"
  fi
}

# 🔥 save（手动用，不再自启动）🔥
jobs_flutter_save_impl() {
  local files=(
    "$HOME/.bash_profile"
    "$HOME/.bashrc"
    "$HOME/.zshrc"
    "$HOME/.profile"
  )
  for file in "${files[@]}"; do
    if [[ -f "$file" ]]; then
      source "$file"
      jobs_prompt_output echo -e "\033[1;32m✅ 已加载配置文件：file://$file\033[0m"
    else
      jobs_prompt_output echo -e "\033[1;33m⚠️ 未找到配置文件：file://$file\033[0m"
    fi
  done
  echo -e "\n📎 ⌘Command + 点击路径可打开对应文件（macOS Terminal 支持）"
}

# 从当前目录向上查找 FVM 项目根（.fvmrc / .fvm/flutter_sdk / fvm_config.json 任一命中即可）。
jobs_flutter_project_root() {
  emulate -L zsh

  local d="$PWD"

  while [[ "$d" != "/" && -n "$d" ]]; do
    if [[ -f "$d/.fvmrc" || -x "$d/.fvm/flutter_sdk/bin/flutter" || -f "$d/.fvm/fvm_config.json" ]]; then
      print -r -- "$d"
      return 0
    fi
    d="${d:h}"
  done

  return 1
}

# 🔥 flutter() 重载（优先 FVM）🔥
jobs_flutter_flutter_impl() {
  emulate -L zsh
  setopt no_aliases

  local root=""
  root="$(jobs_flutter_project_root 2>/dev/null || true)"

  if [[ -n "$root" && -x "$root/.fvm/flutter_sdk/bin/flutter" ]]; then
    jobs_flutter_sdk_command "$root/.fvm/flutter_sdk/bin/flutter" "$@"
    return $?
  fi

  if [[ -n "$root" && ( -f "$root/.fvmrc" || -f "$root/.fvm/fvm_config.json" ) ]]; then
    if command -v fvm >/dev/null 2>&1; then
      jobs_flutter_sdk_command fvm flutter "$@"
      return $?
    fi
    print -u2 "✖ 检测到 FVM 项目，但找不到 fvm 命令。请先安装 fvm。"
    return 127
  fi

  local external_flutter=""
  external_flutter="$(jobs_flutter_find_external_command flutter 2>/dev/null || true)"
  if [[ -n "$external_flutter" ]]; then
    jobs_flutter_sdk_command "$external_flutter" "$@"
    return $?
  fi

  print -u2 "✖ flutter: command not found（未安装系统 Flutter，且当前目录不在 FVM 项目内）"
  return 127
}

# 🔥 dart() 重载（优先 FVM，避免与项目 Flutter 的 Dart 版本错位）🔥
jobs_flutter_dart_impl() {
  emulate -L zsh
  setopt no_aliases

  local root=""
  root="$(jobs_flutter_project_root 2>/dev/null || true)"

  if [[ -n "$root" && -x "$root/.fvm/flutter_sdk/bin/dart" ]]; then
    jobs_flutter_sdk_command "$root/.fvm/flutter_sdk/bin/dart" "$@"
    return $?
  fi

  if [[ -n "$root" && ( -f "$root/.fvmrc" || -f "$root/.fvm/fvm_config.json" ) ]]; then
    if command -v fvm >/dev/null 2>&1; then
      jobs_flutter_sdk_command fvm dart "$@"
      return $?
    fi
    print -u2 "✖ 检测到 FVM 项目，但找不到 fvm 命令。请先安装 fvm。"
    return 127
  fi

  local external_dart=""
  external_dart="$(jobs_flutter_find_external_command dart 2>/dev/null || true)"
  if [[ -n "$external_dart" ]]; then
    jobs_flutter_sdk_command "$external_dart" "$@"
    return $?
  fi

  print -u2 "✖ dart: command not found（未安装系统 Flutter，且当前目录不在 FVM 项目内）"
  return 127
}

# 🔥 fvm 修复（与 Dart 内核匹配）🔥
jobs_flutter_fixfvm_impl() {
  echo "🔍 修复 fvm 与 Dart SDK 的内核版本不匹配..."
  dart pub global deactivate fvm || true
  rm -rf ~/.pub-cache/bin/fvm* ~/.pub-cache/global_packages/fvm
  dart pub global activate fvm
  hash -r
  echo "✅ fvm 已重新安装并与当前 Dart SDK 匹配"
}

# 🔥 版本检查 🔥
jobs_flutter_check1_impl() {
  echo "================ Dart =================="
  which dart; dart --version 2>/dev/null; echo
  echo "================ FVM ==================="
  which fvm; fvm --version 2>/dev/null; echo
  echo "================ Flutter ==============="
  if whence -v flutter | grep -q "shell function"; then
    echo "📍 flutter 是 shell function，函数体："
    functions flutter
    echo "📍 可执行路径（忽略函数）："; whence -p flutter || echo "（仅有函数）"
  else
    echo "📍 flutter 路径："; whence -p flutter
  fi
  echo "🔖 flutter --version:"; jobs_flutter_flutter_impl --version
}

# 🔥 快捷命令 🔥
jobs_flutter_rb_impl() { exec -l "$SHELL"; }
jobs_flutter_a_impl() { open "$HOME/.bash_profile"; }
jobs_flutter_b_impl() { open "$HOME/.zshrc"; }
# 旧 Flutter 入口复用会话库，保持新旧 Xcode 的模拟器定位一致。
jobs_flutter_i_impl() {
  local session_lib="${${(%):-%x}:A:h:h}/【MacOS】jobs_session_lib.zsh/【MacOS】jobs_session_lib.zsh"
  if [[ ! -f "$session_lib" ]]; then
    print -u2 -r -- "✖ 缺少模拟器启动库：$session_lib"
    return 1
  fi
  source "$session_lib" || return 1
  jobs_session_i_impl "$@"
}

# d：进入显式配置或当前上下文发现的项目目录。
jobs_flutter_d_impl() {
  local dir; dir="$(jobs_flutter_get_project_dir "${1:-}")" || return 1
  cd "$dir" || return 1
  echo "📍 已进入：$dir"
}

# ✅ check：也基于默认项目目录执行（可传参）
jobs_flutter_check_impl() {
  local dir; dir="$(jobs_flutter_get_project_dir "${1:-}")" || return 1
  cd "$dir" || return 1

  echo; java -version; echo
  echo "JAVA_HOME=$JAVA_HOME"; echo

  jobs_flutter_sdk_command fvm use 3.24.5 --force
  jobs_flutter_flutter_impl doctor -v
}

# 🔥 JDK17 锁定到项目（c）🔥
# 复用同一项目目录解析与自检。
jobs_flutter_c_impl() {
  local project_dir; project_dir="$(jobs_flutter_get_project_dir "${1:-}")" || return 1
  local want_major="17"

  cd "$project_dir" || { echo "❌ cd 失败：$project_dir"; return 1; }
  command -v jenv >/dev/null 2>&1 || { echo "❌ 未检测到 jenv（brew install jenv）"; return 1; }
  [[ -e ~/.jenv/shims/.jenv-shim ]] && rm -f ~/.jenv/shims/.jenv-shim
  jobs_flutter_try_run jenv 'eval "$(jenv init -)"'
  jobs_flutter_try_run jenv 'jenv enable-plugin export >/dev/null 2>&1'

  local jdk_home
  jdk_home="$((/usr/libexec/java_home -v "$want_major") 2>/dev/null)"
  [[ -n "$jdk_home" && -d "$jdk_home" ]] || { echo "❌ 未找到本机 JDK $want_major。建议：brew install --cask temurin17"; return 1; }

  if ! jenv versions --bare | grep -Eq "^$want_major(\.|$)"; then
    jobs_flutter_try_run jenv "jenv add \"$jdk_home\"" || return 1
    jobs_flutter_try_run jenv "jenv rehash"
  fi
  local jdk_label
  jdk_label="$(jenv versions --bare | awk -v m="$want_major" '$0 ~ "^"m"(\\.|$)" {print; exit}')"
  [[ -n "$jdk_label" ]] || jdk_label="$(jenv versions --bare | awk '/17/{print; exit}')"
  [[ -n "$jdk_label" ]] || { echo "❌ 无法解析 JDK$want_major 标签（jenv versions 看看）"; return 1; }

  jobs_flutter_try_run jenv "jenv local \"$jdk_label\""  || return 1
  jobs_flutter_try_run jenv "jenv shell \"$jdk_label\""  || return 1
  jobs_flutter_try_run jenv "jenv rehash"

  echo "✅ 已锁定 JDK：$jdk_label"
  echo "✅ JAVA_HOME：${JAVA_HOME:-<未导出>}"
  command -v java >/dev/null 2>&1 && java -version

  typeset -f jobs_flutter_check_impl >/dev/null && jobs_flutter_check_impl "$project_dir"
}

# 🔥 解析真实 Flutter 执行器（避免函数误判）🔥
jobs_flutter_resolve_flutter_exec() {
  if [[ -x .fvm/flutter_sdk/bin/flutter ]]; then
    echo ".fvm/flutter_sdk/bin/flutter" ".fvm/flutter_sdk/bin/flutter"; return 0
  fi
  if command -v fvm >/dev/null 2>&1; then
    local fpath; fpath="$(fvm which flutter 2>/dev/null || true)"
    if [[ -n "$fpath" && -x "$fpath" ]]; then
      echo "fvm" "fvm flutter"; return 0
    fi
    echo "fvm" "fvm flutter"; return 0
  fi
  local sysbin; sysbin="$(jobs_flutter_find_external_command flutter 2>/dev/null || true)"
  if [[ -n "$sysbin" && -x "$sysbin" ]]; then
    echo "$sysbin" "$sysbin"; return 0
  fi
  return 1
}

jobs_flutter_ensure_flutter_available() {
  local cmd prefix
  if read -r cmd prefix < <(jobs_flutter_resolve_flutter_exec); then
    echo "🛠️  使用 Flutter 执行器：$prefix"
    echo "$cmd" "$prefix"; return 0
  fi
  echo "⚠️  未找到 Flutter，尝试修复 FVM..."
  if command -v dart >/dev/null 2>&1; then
    if typeset -f jobs_flutter_fixfvm_impl >/dev/null; then jobs_flutter_fixfvm_impl || true
    else
      dart pub global deactivate fvm >/dev/null 2>&1 || true
      dart pub global activate  fvm >/dev/null 2>&1 || true
      hash -r
    fi
  fi
  if read -r cmd prefix < <(jobs_flutter_resolve_flutter_exec); then
    echo "🛠️  修复成功：$prefix"
    echo "$cmd" "$prefix"; return 0
  fi
  echo "❌ 仍不可用：请确保 .fvm/flutter_sdk 或 fvm 或系统 flutter 可用"; return 1
}


# 🔥 构建前置（智能 + 可选参数 + 强校验执行器）🔥
jobs_flutter_buildCheck_impl() {
  emulate -L zsh
  set +o noglob
  local here="$PWD" project_path ans
  local auto=0 do_clean=1 do_get=1 do_doctor=1 force_get=0 skip_lock_check=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) auto=1 ;;
      --no-clean) do_clean=0 ;;
      --no-get) do_get=0 ;;
      --no-doctor) do_doctor=0 ;;
      --force-get) force_get=1 ;;
      --skip-lock-check) skip_lock_check=1 ;;
      *) echo "⚠️  未知参数：$1" ;;
    esac; shift
  done
  if [[ -d "$here/lib" && -f "$here/pubspec.yaml" ]]; then
    project_path="$here"
  else
    project_path="$(jobs_flutter_get_project_dir_interactive "$here")" || { echo "已取消"; return 1; }
    cd "$project_path" || { echo "❌ cd 失败：$project_path"; return 1; }
  fi
  echo "📍 项目：$project_path"

  local _cmd _prefix
  if ! read -r _cmd _prefix < <(jobs_flutter_ensure_flutter_available); then return 1; fi

  if (( auto == 0 )); then
    read -r "?$(jobs_prompt_render "是否执行清理和依赖安装 (回车=执行，任意字符=跳过): ")" ans
    [[ -n "$ans" ]] && { echo "⏩ 用户选择跳过"; return 0; }
  fi

  local need_get=1
  if (( skip_lock_check == 0 && force_get == 0 )); then
    if [[ -f pubspec.yaml && -f pubspec.lock && pubspec.lock -nt pubspec.yaml ]]; then
      need_get=0
    fi
  fi
  (( force_get )) && need_get=1

  if (( do_clean )); then
    echo "🧹 清理：$_prefix clean"; jobs_flutter_try_run "$_cmd" "$_prefix clean"
  else
    echo "⏭️  跳过 clean"
  fi
  if (( do_get )); then
    if (( need_get )); then
      echo "📦 依赖：$_prefix pub get"; jobs_flutter_try_run "$_cmd" "$_prefix pub get"
    else
      echo "ℹ️  依赖未变化（pubspec.lock 新于 pubspec.yaml），跳过 pub get（--force-get 可强制）"
    fi
  else
    echo "⏭️  跳过 pub get"
  fi
  if (( do_doctor )); then
    echo "🩺 体检：$_prefix doctor -v"; jobs_flutter_try_run "$_cmd" "$_prefix doctor -v"
  else
    echo "⏭️  跳过 doctor"
  fi
}


# 🔥 Flutter 项目识别 & 目录选择 🔥
jobs_flutter_is_flutter_project() { local dir="$1"; [[ -d "$dir/lib" && -f "$dir/pubspec.yaml" ]]; }

jobs_flutter_get_project_dir_interactive() {
  local start="${1:-$PWD}" project_path="$start" input_path
  project_path="$(jobs_flutter_resolve_directory "$start")" || project_path="$start"
  while ! jobs_flutter_is_flutter_project "$project_path"; do
    echo "❌ [$project_path] 不是 Flutter 项目目录（缺少 lib/ 或 pubspec.yaml）" >&2
    read -r "?$(jobs_prompt_render "👉 请输入 Flutter 项目路径（回车=继续询问，q=退出）: ")" input_path || return 1
    [[ "$input_path" == [Qq] ]] && return 1
    [[ -z "$input_path" ]] && continue
    project_path="$(jobs_flutter_resolve_directory "$input_path")" || project_path=""
    [[ -z "$project_path" ]] && echo "⚠️ 路径无效，请重试" >&2
  done
  printf "%s\n" "$project_path"
}

# 🔥 APK / IPA 构建（保持你的逻辑）🔥
jobs_flutter_set_flutter_cmd() {
  export PATH="$HOME/.pub-cache/bin:$PATH"
  if command -v fvm >/dev/null 2>&1; then
    flutter_cmd=(jobs_flutter_sdk_command fvm flutter)
  else
    local external_flutter=""
    external_flutter="$(jobs_flutter_find_external_command flutter 2>/dev/null || true)"
    if [[ -n "$external_flutter" ]]; then
      flutter_cmd=(jobs_flutter_sdk_command "$external_flutter")
    else
      flutter_cmd=(jobs_flutter_flutter_impl)
    fi
  fi
  echo "[INFO] flutter_cmd = ${flutter_cmd[*]}"
}

jobs_flutter_read_project_flutter_version() {
  local v=""
  if [[ -f .fvm/version ]]; then
    v="$(tr -d '\r' < .fvm/version | tr -d '[:space:]')"; [[ -n "$v" ]] && echo "$v" && return 0
  fi
  if [[ -f .fvmrc ]]; then
    if command -v jq >/dev/null 2>&1 && head -c1 .fvmrc | grep -q '{'; then
      v="$(jq -r '.flutter // .flutterSdkVersion // empty' .fvmrc 2>/dev/null | tr -d '[:space:]')"
      [[ -n "$v" ]] && echo "$v" && return 0
    fi
    v="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' .fvmrc | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
    [[ -n "$v" ]] && echo "$v" && return 0
  fi
  if [[ -f .fvm/fvm_config.json ]] && command -v jq >/dev/null 2>&1; then
    v="$(jq -r '.flutter // .flutterSdkVersion // empty' .fvm/fvm_config.json 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$v" ]] && echo "$v" && return 0
  fi
  # 版本发现只读可信本地metadata，不能为显示版本触发SDK自举。
  if [[ -f .fvm/flutter_sdk/bin/cache/flutter.version.json ]] && command -v jq >/dev/null 2>&1; then
    v="$(jq -r '.frameworkVersion // empty' .fvm/flutter_sdk/bin/cache/flutter.version.json 2>/dev/null)"
  elif [[ -f .fvm/flutter_sdk/version ]]; then
    v="$(<.fvm/flutter_sdk/version)"
  elif [[ -d .fvm/flutter_sdk/.git || -f .fvm/flutter_sdk/.git ]]; then
    v="$(env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR git --no-optional-locks -c core.fsmonitor=false -C .fvm/flutter_sdk describe --tags --exact-match HEAD 2>/dev/null || true)"
  fi
  if [[ "$v" =~ '^v?[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.+-]+)?$' ]]; then
    print -r -- "$v"
    return 0
  fi
  return 1
}

jobs_flutter_ensure_fvm_and_flutter_version_before_build() {
  if ! command -v fvm >/dev/null 2>&1; then
    echo "[INFO] 未检测到 fvm，准备安装"
    if ! command -v dart >/dev/null 2>&1; then echo "[ERROR] 未检测到 dart"; return 1; fi
    dart pub global deactivate fvm >/dev/null 2>&1 || true
    dart pub global activate  fvm || { echo "[ERROR] fvm 安装失败"; return 1; }
    echo "[OK] fvm 安装成功"
  else
    dart pub global activate fvm >/dev/null 2>&1 || true
    echo "[INFO] fvm 已就绪"
  fi

  jobs_flutter_set_flutter_cmd

  local desired_version=""
  if desired_version="$(jobs_flutter_read_project_flutter_version)"; then
    echo "[INFO] 项目已绑定 Flutter 版本：$desired_version"
  else
    echo "[INFO] 项目未绑定 Flutter 版本，尝试获取 stable 列表"
    local versions latest pick
    versions="$(jobs_flutter_sdk_versions \
      | jq -r '.releases[] | select(.channel=="stable") | .version' | sort -V | uniq | tac)"
    [[ -n "$versions" ]] || { echo "[ERROR] Flutter发布清单未提供有效stable版本，未写项目配置"; return 1; }
    latest="$(echo "$versions" | head -n1)"
    if command -v fzf >/dev/null 2>&1; then
      pick="$(echo "$versions" | fzf --prompt='选择 Flutter 版本：' --height=50% --border --ansi)"
      desired_version="$(echo "$pick" | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+$')"
    fi
    desired_version="${desired_version:-$latest}"
    printf '{ "flutter": "%s" }\n' "$desired_version" > .fvmrc
    mkdir -p .fvm
    printf '{ "flutter": "%s", "flutterSdkVersion": "%s" }\n' "$desired_version" "$desired_version" > .fvm/fvm_config.json
    printf '%s\n' "$desired_version" > .fvm/version
    echo "[OK] 已写入 .fvmrc / .fvm/fvm_config.json / .fvm/version：$desired_version"
  fi

  echo "[INFO] 安装 Flutter $desired_version"
  jobs_flutter_sdk_command fvm install "$desired_version" || { echo "[ERROR] fvm install 失败"; return 1; }
  jobs_flutter_sdk_command fvm use "$desired_version" --force || { echo "[ERROR] fvm use 失败"; return 1; }
  jobs_flutter_set_flutter_cmd
  echo "[OK] Flutter $desired_version 就绪"
}

jobs_flutter_ensure_jdk17() {
  if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
    echo "[ERROR] 系统未安装 JDK 17（建议：brew install --cask temurin17）" >&2
    return 1
  fi
  jenv add "$(/usr/libexec/java_home -v 17)" >/dev/null 2>&1 || true
  jenv rehash
  local pick_17; pick_17="$(jenv versions --bare | grep -E '(^|[[:space:]])(.*17(\.|$).*)' | head -n1 || true)"
  [[ -z "${pick_17:-}" ]] && { echo "[ERROR] jenv 中未发现 JDK 17" >&2; return 1; }
  jenv shell "$pick_17"
  export JENV_VERSION="$pick_17"
  export JAVA_HOME="$(jenv prefix)"
  export PATH="$JAVA_HOME/bin:$PATH"
  echo "$pick_17" > .java-version
  echo "JENV_VERSION=$JENV_VERSION"
  echo "JAVA_HOME=$JAVA_HOME"
  java -version
}

jobs_flutter_apk_impl() {
  local project_path; project_path="$(jobs_flutter_get_project_dir_interactive "$PWD")" || return 1
  echo "[OK] 已确认 Flutter 项目目录: $project_path"
  cd "$project_path" || return 1
  typeset -f jobs_flutter_buildCheck_impl >/dev/null && jobs_flutter_buildCheck_impl -y || return $?
  jobs_flutter_ensure_fvm_and_flutter_version_before_build || return $?
  jobs_flutter_ensure_jdk17 || return $?
  if [[ -f "plugins/htprotect/pubspec.yaml" ]]; then
    echo "[INFO] 执行子插件依赖更新: plugins/htprotect"
    (cd plugins/htprotect && "${flutter_cmd[@]}" pub get) || return $?
  else
    echo "[WARN] 未找到 plugins/htprotect/pubspec.yaml，跳过 pub get"
  fi
  echo "[INFO] 开始构建 APK（release）..."
  "${flutter_cmd[@]}" build apk --release || return $?
  echo "[INFO] 打开输出目录: ./build/app/outputs/"; open "./build/app/outputs/"
}

jobs_flutter_ipa_impl() {
  typeset -f jobs_flutter_buildCheck_impl >/dev/null && jobs_flutter_buildCheck_impl -y || return $?
  local project_path; project_path="$(jobs_flutter_get_project_dir_interactive "$PWD")" || return 1
  echo "✅ 已确认 Flutter 项目目录: $project_path"
  cd "$project_path" || return 1
  echo "🚀 开始构建 iOS（release）..."
  jobs_flutter_flutter_impl build ipa --release || return $?
  echo "📂 打开输出目录: ./build/ios/ipa/"; open "./build/ios/ipa/"
}

# 🔥 config：用 Xcode 打开配置文件（无 Xcode 则用系统文本编辑器）🔥
jobs_flutter_config_impl() {
  local arg="$1"
  local home_dir="${HOME}"
  local target=""
  local xcode_app="/Applications/Xcode.app"

  # 无参数：默认打开 ~/.zshrc
  if [[ -z "$arg" ]]; then
    target="${home_dir}/.zshrc"
  else
    if [[ "$arg" == .* ]]; then
      target="${home_dir}/${arg}"
    elif [[ "$arg" == /* ]]; then
      target="$arg"
    else
      target="${home_dir}/${arg}"
    fi
  fi

  if [[ ! -e "$target" ]]; then
    echo "❌ 找不到：$target"
    echo "👉 用法：config（打开 ~/.zshrc） / config .profile（打开 \$HOME/.profile）"
    return 1
  fi

  if [[ -d "$xcode_app" ]]; then
    open -a "Xcode" "$target"
  else
    open -e "$target"
  fi
}

# 保持模块 source 时所需 SDK 接口，路径以当前模块实际位置为准。
jobs_initialize_flutter_library() {
  source "${${(%):-%x}:A:h:h}/【MacOS】FlutterSDK网络入口.zsh/【MacOS】FlutterSDK网络入口.zsh"
}

jobs_initialize_flutter_library
