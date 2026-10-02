# macOS 拖入路径解析
# 目标：
# 1. 默认提供 Ctrl-G：把当前命令行最后一个路径参数解析成真实路径
# 2. 可选开启自动粘贴解析：仅对“单个路径”的粘贴内容生效，尽量避免误伤普通文本
#
# 开关建议放到：zsh/custom/local.zsh
# export JOBS_ALIAS_DRAG_BINDKEY='^G'
# export JOBS_ALIAS_DRAG_AUTO_RESOLVE='true'

[[ -o interactive ]] || return 0

# gif 录制 shell 内不绑定 Ctrl-G，避免与录制结束/路径解析产生冲突。
[[ "${JOBS_GIF_RECORDING:-}" == "1" ]] && return 0

: "${JOBS_ALIAS_DRAG_BINDKEY:=^G}"
: "${JOBS_ALIAS_DRAG_AUTO_RESOLVE:=false}"

jobs_is_macos_alias() {
  local target_path="$1"
  [[ -e "$target_path" ]] || return 1

  osascript <<EOF_APPLE >/dev/null 2>&1
tell application "Finder"
  try
    set f to POSIX file "$target_path" as alias
    original item of f
    return true
  on error
    return false
  end try
end tell
EOF_APPLE
}

jobs_resolve_drag_target() {
  local target_path="$1"
  local resolved=""

  [[ -n "$target_path" ]] || return 1

  if jobs_is_macos_alias "$target_path"; then
    resolved="$(osascript <<EOF_APPLE 2>/dev/null
tell application "Finder"
  try
    set f to POSIX file "$target_path" as alias
    POSIX path of (original item of f)
  on error
    return ""
  end try
end tell
EOF_APPLE
)"
    if [[ -n "$resolved" ]]; then
      printf '%s\n' "${resolved%/}"
      return 0
    fi
  fi

  if command -v realpath >/dev/null 2>&1; then
    resolved="$(realpath "$target_path" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi

  if [[ -L "$target_path" ]]; then
    resolved="$(perl -MCwd=abs_path -e 'print abs_path(shift)' "$target_path" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi

  printf '%s\n' "$target_path"
}

jobs_unescape_dragged_path() {
  emulate -L zsh
  setopt no_nomatch

  local raw="$*"
  local out="$raw"

  # zsh 的 ${var//pattern/repl} 会把 "\(" 当成 glob pattern 解析，
  # 在部分环境下会触发 bad pattern: \(。这里改用 zsh 自带的 (Q)
  # quote-removal，一次性处理 Finder 拖入路径里的反斜杠、空格、括号、引号等。
  out="${(Q)out}"

  if [[ "$out" == "~"* ]]; then
    out="${~out}"
  fi

  printf '%s' "$out"
}

jobs_try_transform_paste_text() {
  local text="$1"
  local trimmed="$text"
  local unescaped=""
  local resolved=""

  trimmed="${trimmed#${trimmed%%[![:space:]]*}}"
  trimmed="${trimmed%${trimmed##*[![:space:]]}}"

  [[ -n "$trimmed" ]] || {
    printf '%s' "$text"
    return
  }

  [[ "$trimmed" == *$'\n'* ]] && {
    printf '%s' "$text"
    return
  }

  unescaped="$(jobs_unescape_dragged_path "$trimmed")"

  if [[ -e "$unescaped" || -L "$unescaped" ]]; then
    resolved="$(jobs_resolve_drag_target "$unescaped")"
    printf '%q' "$resolved"
    return
  fi

  printf '%s' "$text"
}

jobs_expand_last_arg_to_realpath_widget() {
  emulate -L zsh

  local left="$LBUFFER"
  local prefix=""
  local token=""
  local raw_path=""
  local resolved=""

  if [[ "$left" == *' '* ]]; then
    prefix="${left% *} "
    token="${left##* }"
  else
    token="$left"
  fi

  raw_path="$(jobs_unescape_dragged_path "$token")"

  if [[ ! -e "$raw_path" && ! -L "$raw_path" ]]; then
    zle -M "最后一个参数不是有效路径"
    return 0
  fi

  resolved="$(jobs_resolve_drag_target "$raw_path")"
  LBUFFER="${prefix}$(printf '%q' "$resolved")"
}

zle -N jobs-expand-last-arg-to-realpath jobs_expand_last_arg_to_realpath_widget
bindkey "$JOBS_ALIAS_DRAG_BINDKEY" jobs-expand-last-arg-to-realpath

if [[ "$JOBS_ALIAS_DRAG_AUTO_RESOLVE" == "true" ]]; then
  autoload -Uz bracketed-paste-magic

  jobs_bracketed_paste_magic_wrapper() {
    local before="$LBUFFER"
    local old_len=${#LBUFFER}
    bracketed-paste-magic
    local pasted="${LBUFFER[$((old_len + 1)),-1]}"
    local replaced="$(jobs_try_transform_paste_text "$pasted")"

    if [[ -n "$pasted" && "$replaced" != "$pasted" ]]; then
      LBUFFER="${before}${replaced}"
    fi
  }

  zle -N bracketed-paste jobs_bracketed_paste_magic_wrapper
fi
