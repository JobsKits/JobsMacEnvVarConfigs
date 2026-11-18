# shell: zsh
# 模块自述：只供 source；定义会话命令，不主动读写用户文件或等待输入。
jobs_prompt_color_ready() {
  env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)' && return 1
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 仅渲染展示流；color由调用者按实际TTY能力决定，日志传0。
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
# 只在真正交互展示流上着色；读取与机器输出不经过此函数。
jobs_url_stream() {
  local url_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then url_color=1; fi
  jobs_url_format "$url_color" "${1:-1}"
}

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
      echo -e "\033[1;32m✅ 已加载配置文件：file://$file\033[0m" | jobs_url_stream
    else
      echo -e "\033[1;33m⚠️ 未找到配置文件：file://$file\033[0m" | jobs_url_stream
    fi
  done
  echo -e "\n📎 ⌘Command + 点击路径可打开对应文件（macOS Terminal 支持）"
}

# 用用户当前 Shell 重新开启登录会话。
jobs_session_rb_impl() {
  exec -l "$SHELL"
}
# 打开当前用户 Bash 配置供编辑。
jobs_session_a_impl() {
  open "$HOME/.bash_profile"
}
# 打开当前用户 zsh 配置供编辑。
jobs_session_b_impl() {
  open "$HOME/.zshrc"
}
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
