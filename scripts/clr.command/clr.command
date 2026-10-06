#!/bin/zsh
# 脚本自述：
# - 脚本名称：clr.command
# - 核心用途：执行“clr”对应的自动化任务。
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
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 封装 print_divider 对应的独立处理逻辑。
print_divider()  { gray_echo "------------------------------------------------------------------------"; }

# ---------- 常量 ----------
CLR_EXTENSION_ID="fglcbiaddbchgemaegkjejejikhilpon"
CLR_EXTENSION_KEY="MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3S09xpt4B73vCWFVhd2azGUia+BbB1KEVgC609S+mYzFSTNF1jlRGgw2eqnwLd/4WL5FxeDHKLjQS+lnjXvYTWohRDEyEJlHeq6VBFX0V+YLfFMsHFQu3sFeqkcMi5LteL7bscylwFUHhMUVd8yeNFQykAhRH4WV50VCymYzo7nWL83KMkkGqprFCMkDBZe8cVmjNEFuNlIjbPExd2UIk2YNI+egbwkeBbZIMa2JZ9gK7bfMeG6n5X8FnYgqiaGafd1xZFcSwKdEAY7jwSIpKW86t284MBiznmK9x8tIAzDmlDa/ynWN2sPBkeKyEsANpL3LuDkDtYSHG3lK0uzvtQIDAQAB"
CLR_DETECTED_EXTENSION_ID=""
CLR_EXTENSION_DIR="${HOME}/.JobsMacEnv/ChromeExtensions/jobs-clear-downloads"
CLR_EXTENSION_ID_FILE="${CLR_EXTENSION_DIR}/extension_id.txt"
CLR_EXTENSION_URL=""
CLR_DOWNLOADS_URL="chrome://downloads/"

# ---------- 参数状态 ----------
CLR_ASSUME_YES=0
CLR_OPEN_ONLY=0
CLR_OPEN_AFTER=0
CLR_INSTALL_EXTENSION=0
CLR_REVEAL_EXTENSION=0
CLR_FORCE_EXTENSION=0
CLR_LEGACY_UI=0
CLR_MANUAL_EXTENSION_ID=""
# ---------- 内置自述 ----------
jobs_clr_show_readme_and_wait() {
  clear 2>/dev/null || true
  cat <<'EOFREADME' | tee -a "$LOG_FILE" | jobs_intro_style auto
============================================================
clr - 清空 Chrome 下载记录
============================================================

功能：
  清空 Google Chrome 浏览器下载历史，不删除已经下载到本地的真实文件。

这版调整：
  - 不再假装坐标点击一定可靠。
  - 不再依赖直接改 Chrome History 数据库。
  - 默认改用一个极小的本地 Chrome 扩展，通过 Chrome 官方 downloads API
    清除下载历史。
  - 本地扩展 manifest 使用合法固定 key，扩展 ID 稳定，避免每次靠扫描 Chrome Profile 猜 ID。
  - 同时兼容你已经加载过的旧版扩展 ID；但不会再盲信已保存的旧 ID。
  - 每次会先校验 Chrome 当前配置里扩展是否仍处于启用状态。
  - 旧 ID、已删除 ID、已禁用 ID 会被自动忽略，避免 ERR_BLOCKED_BY_CLIENT 被误判为清理成功。
  - 第一次需要把本地扩展加载到 Chrome；以后执行 clr 就可以直接触发清理。

重要边界：
  - 只清除 Chrome 下载历史。
  - 不删除 ~/Downloads 或其它目录里的真实文件。
  - 不退出 Google Chrome。
  - 不备份 Chrome History 数据库。
  - 不关闭或替换你原来的网页；清理时只会打开一个扩展内部页面。

运行：
  clr
  clr --install-extension
  clr --open-only
  clr --yes
  clr --extension-id Chrome扩展卡片里的32位ID

说明：
  - 默认执行前会停一下确认：直接回车执行清理，输入任意字符后回车取消。
  - 第一次如果提示未安装扩展，执行 clr --install-extension，按提示加载一次。
  - 如果 Chrome 已经显示扩展装好了，但 clr 仍识别不到，可以执行：
    clr --extension-id 扩展卡片里显示的32位ID
  - 如果 Chrome 页面显示 ERR_BLOCKED_BY_CLIENT，通常代表旧 ID 已被禁用、移除或被 Chrome 屏蔽；重新执行 clr --install-extension 后按提示重新加载扩展。
  - 日志路径：/tmp/clr.log
============================================================
EOFREADME

  if [[ -t 0 && "${JOBS_MAC_ENV_SKIP_README:-}" != "1" ]]; then
    log "" | jobs_intro_style body
    warm_echo "按回车继续执行 clr..." | jobs_intro_style body
    local _answer=""
    IFS= read -r _answer
  fi
}
# 封装 jobs_clr_usage 对应的独立处理逻辑。
jobs_clr_usage() {
  cat <<'EOFUSAGE'
usage: clr [--install-extension] [--open-only] [--open] [--yes] [--legacy-ui] [--force-extension] [--extension-id ID]

选项：
  --install-extension  生成本地 Chrome 扩展，并打开 chrome://extensions/ 安装页
  --reveal-extension   在 Finder 中显示本地扩展目录
  --open-only          只在新标签页打开 chrome://downloads/，不清理
  --open               清理触发后打开 chrome://downloads/ 查看结果
  --yes, -y            跳过回车确认，适合自动化调用
  --force-extension    保留兼容参数；新版优先使用固定 ID / 自动识别 / 手动 ID
  --extension-id ID    手动指定并保存 Chrome 扩展卡片里的 32 位 ID
  --set-extension-id ID 同 --extension-id
  --legacy-ui          走旧版 UI 自动点击兜底；不推荐，只保留给临时测试
  --help, -h           显示帮助
EOFUSAGE
}
# 封装 jobs_clr_parse_args 对应的独立处理逻辑。
jobs_clr_parse_args() {
  while (( $# > 0 )); do
    case "$1" in
      --install-extension)
        CLR_INSTALL_EXTENSION=1
        ;;
      --reveal-extension)
        CLR_REVEAL_EXTENSION=1
        ;;
      --open-only)
        CLR_OPEN_ONLY=1
        ;;
      --open)
        CLR_OPEN_AFTER=1
        ;;
      --yes|-y)
        CLR_ASSUME_YES=1
        ;;
      --force-extension)
        CLR_FORCE_EXTENSION=1
        ;;
      --extension-id|--set-extension-id)
        if [[ -z "${2:-}" ]]; then
          error_echo "$1 需要跟一个 Chrome 扩展 ID。"
          return 1
        fi
        CLR_MANUAL_EXTENSION_ID="$2"
        shift
        ;;
      --legacy-ui)
        CLR_LEGACY_UI=1
        ;;
      --help|-h)
        jobs_clr_usage
        return 2
        ;;
      *)
        error_echo "未知参数：$1"
        jobs_clr_usage
        return 1
        ;;
    esac
    shift
  done

  return 0
}
# 封装 jobs_clr_confirm 对应的独立处理逻辑。
jobs_clr_confirm() {
  if (( CLR_ASSUME_YES )); then
    return 0
  fi

  echo ""
  warn_echo "确认：即将清空 Google Chrome 下载历史。"
  warm_echo "不会删除真实下载文件；不会退出 Chrome；不会备份 History 数据库；不会关闭或替换当前网页。"
  log "👉 直接按 [Enter]：继续清理"
  log "👉 输入任意字符后回车：取消"

  if [[ ! -t 0 ]]; then
    error_echo "当前不是交互式终端，未指定 --yes，已取消。"
    return 1
  fi

  local answer=""
  printf "> " | tee -a "$LOG_FILE"
  IFS= read -r answer

  if [[ -z "${answer}" ]]; then
    return 0
  fi

  warn_echo "已取消清理。"
  return 1
}
# 封装 jobs_clr_open_chrome_url_new_tab 对应的独立处理逻辑。
jobs_clr_open_chrome_url_new_tab() {
  local url="$1"
  local osa_output=""
  local osa_status=0

  osa_output="$(osascript <<EOFAPPLESCRIPT 2>&1
try
  tell application "Google Chrome"
    activate
    if not (exists window 1) then
      make new window
      set URL of active tab of front window to "${url}"
    else
      tell front window to make new tab with properties {URL:"${url}"}
    end if
  end tell
  return "OPENED_NEW_TAB"
on error errMsg number errNum
  return "OPEN_FAILED:" & errNum & ":" & errMsg
end try
EOFAPPLESCRIPT
)"
  osa_status=$?

  if (( osa_status == 0 )) && [[ "$osa_output" == "OPENED_NEW_TAB" ]]; then
    return 0
  fi

  warn_echo "AppleScript 打开失败：$osa_output"
  if open -a "Google Chrome" "$url" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}
# 封装 jobs_clr_open_downloads_page 对应的独立处理逻辑。
jobs_clr_open_downloads_page() {
  note_echo "在 Chrome 新标签页打开下载记录页：${CLR_DOWNLOADS_URL}"
  if jobs_clr_open_chrome_url_new_tab "$CLR_DOWNLOADS_URL"; then
    success_echo "已打开 ${CLR_DOWNLOADS_URL}"
    return 0
  fi

  error_echo "无法打开 Google Chrome。请确认已安装 Chrome。"
  return 1
}
# 封装 jobs_clr_write_extension_files 对应的独立处理逻辑。
jobs_clr_write_extension_files() {
  mkdir -p "$CLR_EXTENSION_DIR" || return 1

  cat > "${CLR_EXTENSION_DIR}/manifest.json" <<'EOFMANIFEST'
{
  "manifest_version": 3,
  "name": "Jobs Clear Chrome Downloads",
  "version": "1.0.3",
  "key": "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3S09xpt4B73vCWFVhd2azGUia+BbB1KEVgC609S+mYzFSTNF1jlRGgw2eqnwLd/4WL5FxeDHKLjQS+lnjXvYTWohRDEyEJlHeq6VBFX0V+YLfFMsHFQu3sFeqkcMi5LteL7bscylwFUHhMUVd8yeNFQykAhRH4WV50VCymYzo7nWL83KMkkGqprFCMkDBZe8cVmjNEFuNlIjbPExd2UIk2YNI+egbwkeBbZIMa2JZ9gK7bfMeG6n5X8FnYgqiaGafd1xZFcSwKdEAY7jwSIpKW86t284MBiznmK9x8tIAzDmlDa/ynWN2sPBkeKyEsANpL3LuDkDtYSHG3lK0uzvtQIDAQAB",
  "description": "Clear Chrome download history without deleting local files.",
  "permissions": ["downloads"],
  "action": {
    "default_title": "Clear Chrome downloads"
  },
  "background": {
    "service_worker": "background.js"
  },
  "commands": {
    "clear-download-history": {
      "suggested_key": {
        "default": "Alt+Shift+C",
        "mac": "Alt+Shift+C"
      },
      "description": "Clear Chrome download history"
    }
  }
}
EOFMANIFEST

  cat > "${CLR_EXTENSION_DIR}/background.js" <<'EOFBG'
function chromeDownloadsSearch(query) {
  return new Promise((resolve, reject) => {
    # 封装 try 对应的独立处理逻辑。
    try {
      chrome.downloads.search(query, (items) => {
        const err = chrome.runtime.lastError;
        if (err) reject(new Error(err.message));
        else resolve(items || []);
      });
    } catch (error) {
      reject(error);
    }
  });
}

function chromeDownloadsErase(query) {
  return new Promise((resolve, reject) => {
    # 封装 try 对应的独立处理逻辑。
    try {
      chrome.downloads.erase(query, (ids) => {
        const err = chrome.runtime.lastError;
        if (err) reject(new Error(err.message));
        else resolve(ids || []);
      });
    } catch (error) {
      reject(error);
    }
  });
}

async function clearDownloads() {
  const before = await chromeDownloadsSearch({});
  const erasedIds = await chromeDownloadsErase({});
  const after = await chromeDownloadsSearch({});

  # 封装 return 对应的独立处理逻辑。
  return {
    ok: true,
    before: before.length,
    erased: erasedIds.length,
    after: after.length,
    erasedIds,
    time: new Date().toISOString()
  };
}

chrome.action.onClicked.addListener(async () => {
  await clearDownloads();
});

chrome.commands.onCommand.addListener(async (command) => {
  if (command === 'clear-download-history') {
    await clearDownloads();
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== 'JOBS_CLR_CLEAR_DOWNLOADS') {
    return false;
  }

  clearDownloads()
    .then((result) => sendResponse(result))
    .catch((error) => sendResponse({ ok: false, error: String(error && error.message ? error.message : error) }));

  return true;
});
EOFBG

  cat > "${CLR_EXTENSION_DIR}/clear.html" <<'EOFHTML'
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>clr - Chrome 下载历史清理</title>
  <style>
    :root { color-scheme: light dark; }
    # 封装 body 对应的独立处理逻辑。
    body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; margin: 48px; line-height: 1.6; }
    .card { max-width: 760px; border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); border-radius: 16px; padding: 28px; }
    # 封装 h1 对应的独立处理逻辑。
    h1 { margin: 0 0 16px; font-size: 24px; }
    .status { font-size: 18px; font-weight: 700; }
    .muted { opacity: .72; }
    # 封装 code 对应的独立处理逻辑。
    code { padding: 2px 6px; border-radius: 6px; background: color-mix(in srgb, CanvasText 10%, transparent); }
  </style>
</head>
<body>
  <main class="card">
    <h1>clr - Chrome 下载历史清理</h1>
    <p id="status" class="status">正在清理 Chrome 下载历史...</p>
    <p id="detail" class="muted">只清除浏览器下载历史，不删除本地文件。</p>
  </main>
  <script src="clear.js"></script>
</body>
</html>
EOFHTML

  cat > "${CLR_EXTENSION_DIR}/clear.js" <<'EOFJS'
const statusEl = document.getElementById('status');
const detailEl = document.getElementById('detail');

function setResult(status, detail) {
  statusEl.textContent = status;
  detailEl.textContent = detail;
}

chrome.runtime.sendMessage({ type: 'JOBS_CLR_CLEAR_DOWNLOADS' }, (response) => {
  const err = chrome.runtime.lastError;
  if (err) {
    setResult('清理失败', err.message || String(err));
    return;
  }

  if (!response || !response.ok) {
    setResult('清理失败', response && response.error ? response.error : '未知错误');
    return;
  }

  setResult(
    'Chrome 下载历史已清理',
    `清理前 ${response.before} 条，已移除 ${response.erased} 条，清理后 ${response.after} 条。本地真实文件没有被删除。`
  );
});
EOFJS

  cat > "${CLR_EXTENSION_DIR}/README.md" <<'EOFEXTREADME'
# Jobs Clear Chrome Downloads

这是 `clr` 命令配套的本地 Chrome 扩展。

用途：调用 Chrome `downloads` API 清除浏览器下载历史，不删除本地真实文件。

安装：

1. 打开 Chrome：`chrome://extensions/`
2. 开启右上角「开发者模式」
3. 点击「加载已解压的扩展程序」
4. 选择本目录
5. 重新执行：`clr`

扩展 ID：固定为 `fglcbiaddbchgemaegkjejejikhilpon`。

如果你已经加载过旧版，Chrome 页面里可能显示旧 ID。此时可执行：

```zsh
clr --extension-id 旧版扩展卡片里显示的32位ID
```
EOFEXTREADME

  return 0
}
# 封装 jobs_clr_reveal_extension_dir 对应的独立处理逻辑。
jobs_clr_reveal_extension_dir() {
  jobs_clr_write_extension_files || return 1
  note_echo "本地扩展目录：${CLR_EXTENSION_DIR}"
  printf "%s" "$CLR_EXTENSION_DIR" | pbcopy 2>/dev/null || true
  info_echo "扩展目录路径已复制到剪贴板。"
  open -R "$CLR_EXTENSION_DIR" >/dev/null 2>&1 || true
}
# 封装 jobs_clr_install_extension_flow 对应的独立处理逻辑。
jobs_clr_install_extension_flow() {
  jobs_clr_write_extension_files || {
    error_echo "生成本地 Chrome 扩展失败。"
    return 1
  }

  rm -f "$CLR_EXTENSION_ID_FILE" 2>/dev/null || true

  print_divider
  note_echo "本地 Chrome 扩展已生成："
  log "$CLR_EXTENSION_DIR"
  printf "%s" "$CLR_EXTENSION_DIR" | pbcopy 2>/dev/null || true
  info_echo "扩展目录路径已复制到剪贴板。"

  print_divider
  warm_echo "第一次需要手动加载一次这个本地扩展："
  log "1. Chrome 会打开 chrome://extensions/。"
  log "2. 打开右上角「开发者模式」。"
  log "3. 点击「加载已解压的扩展程序」。"
  log "4. 选择这个目录：${CLR_EXTENSION_DIR}"
  log "5. 如果之前加载过旧版且仍不生效，先移除旧的 Jobs Clear Chrome Downloads，再重新加载本目录。"
  log "6. 预期新版扩展 ID：${CLR_EXTENSION_ID}"
  log "7. 加载完成后，重新执行：clr"

  open -R "$CLR_EXTENSION_DIR" >/dev/null 2>&1 || true
  jobs_clr_open_chrome_url_new_tab "chrome://extensions/" >/dev/null 2>&1 || open -a "Google Chrome" "chrome://extensions/" >/dev/null 2>&1 || true
  return 0
}
# 封装 jobs_clr_is_valid_extension_id 对应的独立处理逻辑。
jobs_clr_is_valid_extension_id() {
  local candidate="$1"
  [[ "$candidate" =~ '^[a-p]{32}$' ]]
}
# 封装 jobs_clr_save_extension_id 对应的独立处理逻辑。
jobs_clr_save_extension_id() {
  local candidate="$1"
  if ! jobs_clr_is_valid_extension_id "$candidate"; then
    return 1
  fi

  mkdir -p "$CLR_EXTENSION_DIR" || return 1
  printf "%s\n" "$candidate" > "$CLR_EXTENSION_ID_FILE" || return 1
  success_echo "已保存 clr Chrome 扩展 ID：${candidate}"
  return 0
}
# 封装 jobs_clr_lookup_extension_id_in_chrome 对应的独立处理逻辑。
jobs_clr_lookup_extension_id_in_chrome() {
  local candidate="$1"
  local chrome_root="${HOME}/Library/Application Support/Google/Chrome"

  [[ -n "$candidate" ]] || return 1
  [[ -d "$chrome_root" ]] || return 1

  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi

  python3 - "$chrome_root" "$candidate" <<'EOFPY' 2>/dev/null
import json
import os
import sys

root = sys.argv[1]
candidate = sys.argv[2]
rows = []

try:
    profile_names = os.listdir(root)
except Exception:
    profile_names = []

for profile in profile_names:
    profile_dir = os.path.join(root, profile)
    if not os.path.isdir(profile_dir):
        continue

    for fname in ('Preferences', 'Secure Preferences'):
        pref = os.path.join(profile_dir, fname)
        if not os.path.isfile(pref):
            continue

        try:
            with open(pref, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except Exception:
            continue

        item = data.get('extensions', {}).get('settings', {}).get(candidate)
        if not isinstance(item, dict):
            continue

        manifest = item.get('manifest') or {}
        name = str(manifest.get('name') or '')
        raw_path = str(item.get('path') or '')
        state = item.get('state', 1)
        status = 'enabled' if state == 1 or state is None else f'disabled:{state}'
        rows.append((status, profile, fname, name, raw_path))

if not rows:
    sys.exit(1)

rows.sort(key=lambda row: (0 if row[0] == 'enabled' else 1, row[1], row[2]))
print('\t'.join(rows[0]))
sys.exit(0 if rows[0][0] == 'enabled' else 2)
EOFPY
}
# 封装 jobs_clr_read_saved_extension_id 对应的独立处理逻辑。
jobs_clr_read_saved_extension_id() {
  [[ -f "$CLR_EXTENSION_ID_FILE" ]] || return 1

  local candidate=""
  candidate="$(tr -d '[:space:]' < "$CLR_EXTENSION_ID_FILE" 2>/dev/null || true)"
  if ! jobs_clr_is_valid_extension_id "$candidate"; then
    warn_echo "已保存的扩展 ID 不合法，忽略：${candidate}"
    rm -f "$CLR_EXTENSION_ID_FILE" 2>/dev/null || true
    return 1
  fi

  local lookup=""
  lookup="$(jobs_clr_lookup_extension_id_in_chrome "$candidate" || true)"
  if [[ -z "$lookup" ]]; then
    warn_echo "已保存的 clr Chrome 扩展 ID 已失效，Chrome 当前配置里找不到：${candidate}"
    warm_echo "将自动忽略这个旧 ID，并重新检测已启用的扩展。"
    rm -f "$CLR_EXTENSION_ID_FILE" 2>/dev/null || true
    return 1
  fi

  local ext_status=""
  local profile=""
  local source_file=""
  ext_status="$(print -r -- "$lookup" | awk -F'\t' '{ print $1 }')"
  profile="$(print -r -- "$lookup" | awk -F'\t' '{ print $2 }')"
  source_file="$(print -r -- "$lookup" | awk -F'\t' '{ print $3 }')"

  if [[ "$ext_status" == "enabled" ]]; then
    CLR_DETECTED_EXTENSION_ID="$candidate"
    info_echo "使用已保存且已启用的 clr Chrome 扩展 ID：${CLR_DETECTED_EXTENSION_ID}（Profile=${profile}，来源=${source_file}）"
    return 0
  fi

  warn_echo "已保存的 clr Chrome 扩展 ID 当前不是启用状态：${candidate}，状态=${ext_status}"
  warm_echo "这通常会导致 Chrome 打开 ${candidate}/clear.html 时显示 ERR_BLOCKED_BY_CLIENT。"
  rm -f "$CLR_EXTENSION_ID_FILE" 2>/dev/null || true
  return 1
}
# 封装 jobs_clr_find_extension_id 对应的独立处理逻辑。
jobs_clr_find_extension_id() {
  if [[ -n "$CLR_MANUAL_EXTENSION_ID" ]]; then
    if ! jobs_clr_is_valid_extension_id "$CLR_MANUAL_EXTENSION_ID"; then
      error_echo "扩展 ID 格式不对：${CLR_MANUAL_EXTENSION_ID}"
      warm_echo "Chrome 扩展 ID 应该是 32 个 a-p 之间的小写字母。"
      return 1
    fi

    CLR_DETECTED_EXTENSION_ID="$CLR_MANUAL_EXTENSION_ID"
    jobs_clr_save_extension_id "$CLR_DETECTED_EXTENSION_ID" || true
    return 0
  fi

  if jobs_clr_read_saved_extension_id; then
    return 0
  fi

  local chrome_root="${HOME}/Library/Application Support/Google/Chrome"
  [[ -d "$chrome_root" ]] || return 1

  if ! command -v python3 >/dev/null 2>&1; then
    warn_echo "未找到 python3，无法自动识别 Chrome 扩展 ID。"
    return 1
  fi

  local result=""
  result="$(python3 - "$chrome_root" "$CLR_EXTENSION_DIR" "$CLR_EXTENSION_ID" <<'EOFPY' 2>/dev/null
import json
import os
import sys

root = sys.argv[1]
ext_dir = os.path.realpath(os.path.expanduser(sys.argv[2]))
fixed_id = sys.argv[3]
target_name = 'Jobs Clear Chrome Downloads'
rows = []
seen = set()

try:
    profile_names = os.listdir(root)
except Exception:
    profile_names = []

for profile in profile_names:
    profile_dir = os.path.join(root, profile)
    if not os.path.isdir(profile_dir):
        continue

    for fname in ('Preferences', 'Secure Preferences'):
        pref = os.path.join(profile_dir, fname)
        if not os.path.isfile(pref):
            continue

        try:
            with open(pref, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except Exception:
            continue

        settings = data.get('extensions', {}).get('settings', {})
        if not isinstance(settings, dict):
            continue

        for ext_id, item in settings.items():
            if not isinstance(item, dict) or not isinstance(ext_id, str):
                continue

            manifest = item.get('manifest') or {}
            name = manifest.get('name') or ''
            raw_path = item.get('path') or ''
            item_path = os.path.realpath(os.path.expanduser(raw_path)) if raw_path else ''
            state = item.get('state', 1)

            matched = False
            if ext_id == fixed_id:
                matched = True
            if item_path and item_path == ext_dir:
                matched = True
            if item_path and item_path.endswith('/jobs-clear-downloads'):
                matched = True
            if name == target_name:
                matched = True

            if not matched:
                continue

            status = 'enabled' if state == 1 or state is None else f'disabled:{state}'
            key = (ext_id, profile, status, item_path, fname)
            if key in seen:
                continue
            seen.add(key)
            rows.append(key)

# 固定 ID 优先，其次启用状态，其次任意匹配。
def rank(row):
    ext_id, profile, status, item_path, fname = row
    return (
        0 if ext_id == fixed_id else 1,
        0 if status == 'enabled' else 1,
        0 if fname == 'Preferences' else 1,
        profile,
    )

for row in sorted(rows, key=rank):
    print('\t'.join(row))
EOFPY
)"

  local first_enabled=""
  first_enabled="$(print -r -- "$result" | awk -F'\t' '$3 == "enabled" { print; exit }')"
  if [[ -n "$first_enabled" ]]; then
    CLR_DETECTED_EXTENSION_ID="${first_enabled%%$'\t'*}"
    local profile=""
    local source_file=""
    profile="$(print -r -- "$first_enabled" | awk -F'\t' '{ print $2 }')"
    source_file="$(print -r -- "$first_enabled" | awk -F'\t' '{ print $5 }')"
    info_echo "已检测到 clr Chrome 扩展：Profile=${profile}，ID=${CLR_DETECTED_EXTENSION_ID}，来源=${source_file}"
    jobs_clr_save_extension_id "$CLR_DETECTED_EXTENSION_ID" || true
    return 0
  fi

  local first_match=""
  first_match="$(print -r -- "$result" | head -n 1)"
  if [[ -n "$first_match" ]]; then
    local profile=""
    local state_text=""
    profile="$(print -r -- "$first_match" | awk -F'\t' '{ print $2 }')"
    state_text="$(print -r -- "$first_match" | awk -F'\t' '{ print $3 }')"
    warn_echo "检测到 clr Chrome 扩展，但它未启用：Profile=${profile}，状态=${state_text}"
    warm_echo "请到 chrome://extensions/ 打开该扩展右下角开关，然后重新执行：clr"
    return 1
  fi

  warn_echo "未在 Chrome 当前配置中检测到已启用的 clr 本地扩展。"
  warm_echo "不会再盲目打开固定扩展 ID，避免出现 ERR_BLOCKED_BY_CLIENT 却被脚本误判为成功。"
  warm_echo "请执行：clr --install-extension，并确认 Chrome 扩展页里的 Jobs Clear Chrome Downloads 已启用。"
  return 1
}
# 封装 jobs_clr_extension_installed 对应的独立处理逻辑。
jobs_clr_extension_installed() {
  if jobs_clr_find_extension_id; then
    return 0
  fi

  if (( CLR_FORCE_EXTENSION )); then
    warn_echo "--force-extension 已保留兼容；当前仍会按固定 ID / 保存 ID / 自动识别 ID 执行。"
  fi

  return 1
}
# 封装 jobs_clr_clear_by_extension 对应的独立处理逻辑。
jobs_clr_clear_by_extension() {
  jobs_clr_write_extension_files || return 1

  if ! jobs_clr_extension_installed; then
    warn_echo "未检测到 clr 本地 Chrome 扩展。"
    warm_echo "原因：Chrome 没有给普通命令行提供稳定的“清空下载历史”接口；之前的坐标点击和数据库清理都不可靠。"
    jobs_clr_install_extension_flow
    return 2
  fi

  local extension_url="chrome-extension://${CLR_DETECTED_EXTENSION_ID}/clear.html"
  note_echo "通过本地 Chrome 扩展触发下载历史清理。"
  info_echo "扩展清理页：${extension_url}"

  if jobs_clr_open_chrome_url_new_tab "$extension_url"; then
    success_echo "已打开扩展清理页。页面会显示清理前后数量。"
    return 0
  fi

  error_echo "无法打开扩展清理页。"
  return 1
}
# 封装 jobs_clr_legacy_ui_click 对应的独立处理逻辑。
jobs_clr_legacy_ui_click() {
  warn_echo "正在执行旧版 UI 自动点击兜底。这个方式不保证成功。"

  local osa_output=""
  osa_output="$(osascript <<'EOFAPPLESCRIPT' 2>&1
try
  tell application "Google Chrome"
    activate
    if not (exists window 1) then
      make new window
      set URL of active tab of front window to "chrome://downloads/"
    else
      tell front window to make new tab with properties {URL:"chrome://downloads/"}
    end if
  end tell
  delay 1.2

  tell application "System Events"
    tell process "Google Chrome"
      set frontmost to true
      delay 0.2
      key code 48
      delay 0.2
      key code 49
      delay 0.5
    end tell
  end tell
  return "LEGACY_KEYBOARD_DONE"
on error errMsg number errNum
  return "LEGACY_FAILED:" & errNum & ":" & errMsg
end try
EOFAPPLESCRIPT
)"

  if [[ "$osa_output" == "LEGACY_KEYBOARD_DONE" ]]; then
    success_echo "旧版 UI 键盘触发已执行。请查看下载页是否清空。"
    return 0
  fi

  warn_echo "旧版 UI 触发失败：$osa_output"
  return 1
}
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
jobs_clr_main() {
  # 初始化当前流程后续步骤需要使用的变量。
  local parse_status=0
  # 执行当前流程中的独立业务步骤：jobs_clr_parse_args。
  jobs_clr_parse_args "$@"
  # 初始化当前流程后续步骤需要使用的变量。
  parse_status=$?

  # 根据当前条件选择对应的执行分支。
  if (( parse_status == 2 )); then
    # 执行当前流程中的独立业务步骤：return。
    return 0
  fi

  # 根据当前条件选择对应的执行分支。
  if (( parse_status != 0 )); then
    # 执行当前流程中的独立业务步骤：return。
    return "$parse_status"
  fi

  # 展示脚本说明并等待用户确认影响范围。
  jobs_clr_show_readme_and_wait

  # 根据当前条件选择对应的执行分支。
  if (( CLR_REVEAL_EXTENSION )); then
    # 执行当前流程中的独立业务步骤：jobs_clr_reveal_extension_dir。
    jobs_clr_reveal_extension_dir
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 根据当前条件选择对应的执行分支。
  if (( CLR_INSTALL_EXTENSION )); then
    # 执行安装步骤，并保留命令失败信息供后续排查。
    jobs_clr_install_extension_flow
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 根据当前条件选择对应的执行分支。
  if (( CLR_OPEN_ONLY )); then
    # 执行当前流程中的独立业务步骤：jobs_clr_open_downloads_page。
    jobs_clr_open_downloads_page
    # 执行当前流程中的独立业务步骤：return。
    return $?
  fi

  # 根据当前条件选择对应的执行分支。
  if ! jobs_clr_confirm; then
    # 执行当前流程中的独立业务步骤：return。
    return 1
  fi

  # 执行当前流程中的独立业务步骤：print_divider。
  print_divider

  # 初始化当前流程后续步骤需要使用的变量。
  local exit_code=1
  # 根据当前条件选择对应的执行分支。
  if (( CLR_LEGACY_UI )); then
    # 执行当前流程中的独立业务步骤：jobs_clr_legacy_ui_click。
    jobs_clr_legacy_ui_click
    # 初始化当前流程后续步骤需要使用的变量。
    exit_code=$?
  else
    # 执行当前流程中的独立业务步骤：jobs_clr_clear_by_extension。
    jobs_clr_clear_by_extension
    # 初始化当前流程后续步骤需要使用的变量。
    exit_code=$?
  fi

  # 根据当前条件选择对应的执行分支。
  if (( CLR_OPEN_AFTER )); then
    # 执行当前流程中的独立业务步骤：jobs_clr_open_downloads_page。
    jobs_clr_open_downloads_page
  fi

  # 执行当前流程中的独立业务步骤：print_divider。
  print_divider
  # 根据当前条件选择对应的执行分支。
  case "$exit_code" in
    # 执行当前流程中的独立业务步骤：处理当前语句。
    0)
      # 输出当前流程的完成状态、摘要和日志位置。
      success_echo "Chrome 下载历史清理动作已触发。"
      # 执行当前流程中的独立业务步骤：warm_echo。
      warm_echo "真实下载文件没有被删除。"
      ;;
    # 执行当前流程中的独立业务步骤：处理当前语句。
    2)
      # 执行当前流程中的独立业务步骤：warn_echo。
      warn_echo "第一次需要先加载本地 Chrome 扩展。加载后重新执行：clr"
      ;;
    # 执行当前流程中的独立业务步骤：处理当前语句。
    *)
      # 执行当前流程中的独立业务步骤：error_echo。
      error_echo "Chrome 下载历史未清理。请看上面的失败原因。"
      ;;
  esac

  # 执行当前流程中的独立业务步骤：gray_echo。
  gray_echo "日志路径：$LOG_FILE"
  # 执行当前流程中的独立业务步骤：return。
  return $exit_code
}
# 封装 clr 对应的独立处理逻辑。
clr() {
  emulate -L zsh
  jobs_clr_main "$@"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：clr.command' | jobs_intro_style title
  print -r -- '核心用途：执行“clr”对应的自动化任务。' | jobs_intro_style body
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
  # 执行 jobs_clr_main 对应的独立业务步骤。
  jobs_clr_main "$@"
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
