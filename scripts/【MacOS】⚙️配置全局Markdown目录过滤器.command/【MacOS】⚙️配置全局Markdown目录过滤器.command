#!/bin/zsh
# Created by Jobs on 2026年10月23日，星期五.
# 每台电脑一次：安装全局目录驱动；显式 setup 参数可恢复指定仓库的 [toc]。
# 只更改本驱动的用户级配置，保留正文和暂存内容；不提交、不推送。
# 默认 install；setup / restore-tree 必须指定仓库根目录，不推断父仓。
set -euo pipefail
SCRIPT_ROOT="${0:A:h}"

main() {
  local root="$SCRIPT_ROOT" node_bin="" candidate="" mode="${1:-install}"
  (( $# == 0 )) && set -- install
  for candidate in "${commands[node]:-}" /opt/homebrew/bin/node /usr/local/bin/node; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      node_bin="$candidate"
      break
    fi
  done
  if [[ -z "$node_bin" ]]; then
    print -u2 -r -- '需要 Node.js 20 或更新版本。请安装 Node.js 后重新运行此入口。'
    return 1
  fi
  print -r -- "Markdown 目录：${mode}（全局驱动仅作用于仓库已登记的文件）"
  "$node_bin" "$root/GlobalMarkdownToc.mjs" "$@"
}

main "$@"
