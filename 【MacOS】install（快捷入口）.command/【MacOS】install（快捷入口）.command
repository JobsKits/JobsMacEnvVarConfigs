#!/bin/zsh
# 脚本自述：相对路径转交同级功能包，保留参数与退出码；由原脚本负责业务确认。
# shell: zsh

SHORTCUT_SOURCE="${(%):-%x}"
TARGET_DIRECTORY='./【MacOS】install.command'
TARGET_SCRIPT='./【MacOS】install.command/【MacOS】install.command'

launch_companion() {
  setopt NO_NOMATCH
  local shortcut_directory="${SHORTCUT_SOURCE:A:h:h}"
  cd -- "$shortcut_directory" || return 1
  if [[ ! -d "$TARGET_DIRECTORY" || -L "$TARGET_DIRECTORY" || ! -f "$TARGET_SCRIPT" || -L "$TARGET_SCRIPT" ]]; then
    print -u2 -r -- "✖ 找不到有效的配套脚本 / Companion script unavailable: $TARGET_SCRIPT"
    return 1
  fi
  # 按原 shebang 选择系统 Shell，不修改原文件权限。
  local first_line
  local -a interpreter
  IFS= read -r first_line < "$TARGET_SCRIPT"
  first_line="${first_line%$'\r'}"
  case "$first_line" in
    '#!/bin/zsh'|'#!/usr/bin/zsh'|'#!/usr/bin/env zsh') interpreter=(/bin/zsh) ;;
    '#!/bin/bash'|'#!/usr/bin/env bash') interpreter=(/bin/bash) ;;
    '#!/bin/sh'|'#!/usr/bin/env sh') interpreter=(/bin/sh) ;;
    *)
      if [[ -x "$TARGET_SCRIPT" ]]; then
        exec "$TARGET_SCRIPT" "$@"
      fi
      print -u2 -r -- "✖ 无法解析脚本解释器，请先授予原脚本执行权限 / Grant execute permission to the source script: $TARGET_SCRIPT"
      return 1
      ;;
  esac
  exec "${interpreter[@]}" "$TARGET_SCRIPT" "$@"
}

main() {
  launch_companion "$@"
}

main "$@"
