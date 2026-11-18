#!/bin/zsh
# 脚本自述：
# - 名称：JobsMacEnv 分项环境管理后端。
# - 用途：供安装面板与终端卸载入口按组件部署、恢复配置和终端命令。
# - 影响：仅管理当前用户 .JobsMacEnv、.local/bin、.zshrc 及私有收据。
# - 策略：--catalog/--dry-run 只读；真实操作必须明确指定 --yes；不安装系统依赖。
# shell: zsh

ENTRY_PATH="${0:A}"
SCRIPT_DIR=""
SOURCE_ROOT=""
STATE_ROOT=""
ENV_ROOT=""
BIN_ROOT=""
LOG_FILE=""
LOCK_ROOT=""
LOCK_TOKEN=""
RUN_ID=""
ACTION=""
CONFIRMED=0
DRY_RUN=0
RESULT_CODE=0
typeset -a SELECTED EXPANDED COMPONENT_IDS COMMAND_IDS
# 目录、标签和负载只在初始化时构建，机器协议不输出额外自述。
typeset -A LABELS DESCRIPTIONS COMMAND_FILES COMMAND_ALIASES SETTINGS

env_error() {
  print -u2 -r -- "✖ $*"
  [[ -z "$LOG_FILE" ]] || print -r -- "✖ $*" >> "$LOG_FILE"
}
env_log() {
  print -r -- "$*"
  [[ -z "$LOG_FILE" ]] || print -r -- "$*" >> "$LOG_FILE"
}
env_event() {
  local message="${3//$'\t'/ }"
  message="${message//$'\n'/ }"
  printf 'JOBS_MANAGER_EVENT\t%s\t%s\t%s\n' "$1" "$2" "$message"
}
env_usage() {
  cat <<'HELP'
JobsMacEnv 分项环境管理后端
用途：精确备份后安装，按收据恢复；不安装 Homebrew、JDK 或各业务依赖。
用法：
  --catalog                           输出 id、名称、说明、yes/no/unknown 四列 TSV
  --install [--yes] [--dry-run] ID...   安装所选组件并自动补齐公共支持
  --uninstall [--yes] [--dry-run] ID... 撤回所选组件，保留用户后来修改的对象
  --help                              显示本自述
--dry-run 不写用户配置、收据或日志；真实操作必须带 --yes。
历史终端安装没有收据时仅报告，不能推断安装前的内容。Ctrl+C 可中止。
HELP
}
# 解析独立开关，允许 --yes / --dry-run 出现在组件前后。
env_parse_arguments() {
  local argument=""
  for argument in "$@"; do
    case "$argument" in
      --catalog|--status) [[ -z "$ACTION" ]] || return 2; ACTION=catalog ;;
      --install) [[ -z "$ACTION" ]] || return 2; ACTION=install ;;
      --uninstall) [[ -z "$ACTION" ]] || return 2; ACTION=uninstall ;;
      --yes) CONFIRMED=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --help|-h) ACTION=help ;;
      --*) env_error "未知参数：$argument"; return 2 ;;
      *) SELECTED+=("$argument") ;;
    esac
  done
  [[ -n "$ACTION" ]] || ACTION=help
}
# 根路径始终从实际脚本包解析，App Bundle 与仓库使用同一布局。
env_initialize_paths() {
  setopt NO_NOMATCH PIPE_FAIL
  SCRIPT_DIR="${ENTRY_PATH:h}"
  SOURCE_ROOT="${SCRIPT_DIR:h}"
  [[ "$HOME" == /* && -d "$HOME" && "$HOME" != / ]] || {
    env_error 'HOME 必须是已存在的绝对用户目录。'
    return 2
  }
  ENV_ROOT="$HOME/.JobsMacEnv"
  BIN_ROOT="$HOME/.local/bin"
  STATE_ROOT="$HOME/Library/Application Support/JobsMacEnvManager"
  LOCK_ROOT="$STATE_ROOT/operation.lock"
}
env_add_component() {
  COMPONENT_IDS+=("$1")
  LABELS[$1]="$2"
  DESCRIPTIONS[$1]="$3"
}
env_add_command() {
  local command_id="cmd-$1"
  env_add_component "$command_id" "$1 · $3" "$4；自动补齐配置、Shell 入口及公共脚本支持"
  COMMAND_IDS+=("$command_id")
  COMMAND_FILES[$command_id]="$2"
  COMMAND_ALIASES[$command_id]="$1"
}
# 命令与源脚本一一对应，媒体格式别名集中归 to 组件。
env_build_catalog() {
  env_add_component env-core '环境变量与别名' '根据 sync_env.txt 生成环境、PATH、别名及轻量入口；不安装 SDK'
  env_add_component shell-behavior '交互与 Git 行为' '部署启动目录、Git 交互、路径拖入处理；自动补齐基础环境与 Shell 入口'
  env_add_component user-mounts '用户模块加载器' '部署 【MacOS】user_mounts.zsh/【MacOS】user_mounts.zsh，按序加载交互、Git、路径拖入与命令函数模块'
  env_add_component local-custom '命令函数加载器' '部署 【MacOS】local.zsh/【MacOS】local.zsh，加载运行时与短命令函数；自动补齐公共脚本支持'
  env_add_component shell-entry '启用终端环境' '在 .zshrc 加入受控加载块；卸载只停用加载，不删除已有终端命令'
  env_add_component runtime-support '公共脚本支持' '部署 entrypoints、runtime_init、Flutter 路由、JDK 辅助及 _lib；命令共用'
  env_add_command list 【MacOS】list.command '功能菜单' '打开 JobsMacEnv 交互式功能清单'
  env_add_command m5c 【MacOS】m5c.command '文件处理' '部署现有 m5c 文件处理工具'
  env_add_command jsplit '【MacOS】split.command' '文件拆分' '将目标拆成可验证的 Jobs 分卷'
  env_add_command jmerge '【MacOS】merge.command' '分卷合并' '校验分卷并还原原始文件'
  env_add_command flat 【MacOS】flat.command '目录扁平化' '将文件按现有工具规则扁平整理'
  env_add_command trs 【MacOS】trs.command '文本处理' '部署现有 trs 文本工具'
  env_add_command orc 【MacOS】orc.command '离线文字识别' '部署 Indra OCR 入口；八种大小写函数统一调用，依赖与模型按业务入口准备'
  env_add_command gif 【MacOS】gif.command 'GIF 工具' '部署 GIF 转换工具'
  env_add_command jrecord 【MacOS】jrecord.command '独立窗口录屏' '保留完整 Core 原生源码；安装阶段不申请权限或开始录屏'
  env_add_command tts 【MacOS】tts.command '本地语音合成' '部署本地 TTS 入口；模型按业务入口处理'
  env_add_command simios 【MacOS】simios.command 'iOS 模拟器' '部署 iOS 模拟器工具'
  env_add_command pods 【MacOS】pods.command 'CocoaPods 自检' '部署 Pod 编译与 podspec lint 工具'
  env_add_command clean 【MacOS】clean.command '系统清理' '仅部署清理入口；安装和卸载均不执行清理'
  env_add_command clr 【MacOS】clr.command 'Chrome 下载记录' '仅部署清理下载记录工具；不删除下载文件'
  env_add_command dq 【MacOS】dq.command '应用隔离属性' '仅部署隔离属性管理入口；不修改安全设置'
  env_add_command df 【MacOS】df.command '局域网文件服务' '部署 dufs / Caddy 入口；安装阶段不启动服务'
  env_add_command cor 【MacOS】cor.command '颜色转换' '部署 HEX / RGB / RGBA 转换工具'
  env_add_command decode 【MacOS】decode.command 'URL 解码' '部署交互式 URL 解码工具'
  env_add_command ts 【MacOS】ts.command '时间戳转换' '部署时间戳转换工具'
  env_add_command download 【MacOS】download.command '媒体下载' '部署媒体下载入口；安装阶段不下载媒体'
  env_add_command to 【MacOS】to.command '媒体格式转换' '同时注册 mp4/mov/webm/mkv/avi/m4v/mp3/m4a/aac/wav/flac/ogg/opus'
  COMMAND_ALIASES[cmd-to]='to mp4 mov webm mkv avi m4v mp3 m4a aac wav flac ogg opus'
  env_add_command code 【MacOS】code.command 'VS Code' '部署编辑器快捷入口'
  env_add_command codemap 【MacOS】codemap.command '代码地图' '部署 CodeGraph 命令入口；不安装引擎或初始化索引'
  env_add_command frun 【MacOS】frun.command 'Flutter Demo 独立运行' '输入或拖入 Dart main；部署阶段不启动 Flutter 或升级 SDK'
  env_add_command install 【MacOS】install.command '依赖安装菜单' '部署开发依赖安装器；安装此组件不执行依赖安装'
  env_add_command update 【MacOS】update.command '工具链更新菜单' '部署工具链更新器；安装此组件不执行升级'
  env_add_command shell 【MacOS】shell.command '登录 Shell 管理' '部署 Shell 选择器；安装阶段不修改登录 Shell'
  env_add_command zz 【MacOS】zz.command '路径跳转' '部署路径解析与目录跳转工具'
  env_add_command x 【MacOS】x.command '脚本运行' '部署脚本授权与运行入口'
  env_add_command save 【MacOS】save.command '重载配置' '部署终端配置重载入口'
  env_add_command rb 【MacOS】rb.command '重启 Shell' '部署登录 Shell 重启入口'
  env_add_command a 【MacOS】a.command '打开 bash 配置' '部署 bash 配置编辑入口'
  env_add_command b 【MacOS】b.command '打开 zsh 配置' '部署 zsh 配置编辑入口'
  env_add_command i 【MacOS】i.command '打开 Simulator' '部署 Simulator 启动入口'
  env_add_command fixfvm 【MacOS】fixfvm.command 'FVM 修复' '部署 FVM 修复器；安装阶段不重装 FVM'
  env_add_command check1 【MacOS】check1.command 'Flutter 路径诊断' '部署 Flutter 路径诊断工具'
  env_add_command check 【MacOS】check.command 'Flutter 体检' '部署项目 Flutter 体检工具'
  env_add_command c 【MacOS】c.command '开发快捷命令 c' '部署现有 c 工具'
  env_add_command d 【MacOS】d.command '开发快捷命令 d' '部署现有 d 工具'
  env_add_command buildCheck 【MacOS】buildCheck.command '构建检查' '部署构建检查器；安装阶段不构建工程'
  env_add_command apk 【MacOS】apk.command 'Android 打包' '部署 APK 工具；安装阶段不打包或改工程'
  env_add_command ipa 【MacOS】ipa.command 'iOS 打包' '部署 IPA 工具；安装阶段不打包或改工程'
  env_add_command config 【MacOS】config.command '环境配置编辑' '部署配置编辑工具'
  env_add_command gemrepair 【MacOS】repair_gem_extensions.command 'Gem 原生扩展修复' '部署现有 Gem 修复器；安装阶段不修复或重装 Gem'
  COMMAND_ALIASES[cmd-gemrepair]='repair_gem_extensions'
  env_add_command markdown-toc '【MacOS】⚙️配置全局Markdown目录过滤器.command' '全局 Markdown 目录过滤器' '只部署过滤器管理器；安装阶段不写入 Git 全局配置'
  COMMAND_ALIASES[cmd-markdown-toc]='jmarkdown-toc'
}
env_valid_id() {
  [[ -n "${LABELS[$1]:-}" ]]
}
env_selected() {
  (( ${SELECTED[(Ie)$1]} > 0 ))
}
env_expand_selection() {
  local component=""
  (( ${#SELECTED} > 0 )) || { env_error '请至少选择一个组件。'; return 2; }
  for component in "${SELECTED[@]}"; do
    [[ "$component" != all ]] || continue
    env_valid_id "$component" || { env_error "未知组件：$component"; return 2; }
  done
  if (( ${SELECTED[(Ie)all]} > 0 )); then
    SELECTED=("${COMPONENT_IDS[@]}")
  fi
  SELECTED=("${(@u)SELECTED}")
  EXPANDED=("${SELECTED[@]}")
  if [[ "$ACTION" == install ]]; then
    for component in "${SELECTED[@]}"; do
      case "$component" in
        cmd-*) EXPANDED+=(env-core runtime-support user-mounts local-custom shell-entry) ;;
        local-custom) EXPANDED+=(env-core runtime-support user-mounts shell-entry) ;;
        shell-behavior) EXPANDED+=(env-core user-mounts shell-entry) ;;
        user-mounts|shell-entry) EXPANDED+=(env-core shell-entry) ;;
      esac
    done
  fi
  # 按加载依赖部署，Shell 入口最后启用；卸载使用反向顺序。
  EXPANDED=("${(@u)EXPANDED}")
  local -a ordered
  for component in env-core runtime-support user-mounts shell-behavior local-custom "${COMMAND_IDS[@]}" shell-entry; do
    (( ${EXPANDED[(Ie)$component]} > 0 )) && ordered+=("$component")
  done
  EXPANDED=("${ordered[@]}")
}
# 不穿过链接目录，也不把目录或链接当成可覆盖文件。
env_validate_target() {
  local target="$1" ancestor="${1:h}"
  [[ "$target" == "$HOME/"* && "$target" != *$'\n'* && "$target" != *$'\t'* ]] || return 2
  while [[ "$ancestor" != "$HOME" && "$ancestor" != / ]]; do
    [[ ! -L "$ancestor" && ( ! -e "$ancestor" || -d "$ancestor" ) ]] || {
      env_error "父目录是链接或非目录，已保留：$ancestor"; return 3
    }
    ancestor="${ancestor:h}"
  done
  [[ ! -L "$target" && ( ! -e "$target" || -f "$target" ) ]] || {
    env_error "目标不是普通文件，已保留：$target"; return 3
  }
}
env_target() {
  case "$1" in
    env/*) print -r -- "$ENV_ROOT/${1#env/}" ;;
    bin/*) print -r -- "$BIN_ROOT/${1#bin/}" ;;
    zshrc) print -r -- "$HOME/.zshrc" ;;
    *) return 2 ;;
  esac
}
env_fingerprint() {
  local file="$1" digest="" mode=""
  if [[ ! -e "$file" && ! -L "$file" ]]; then print -r -- absent; return 0; fi
  [[ -f "$file" && ! -L "$file" ]] || return 3
  digest="$(/usr/bin/shasum -a 256 "$file")" || return 1
  mode="$(/usr/bin/stat -f '%Lp' "$file")" || return 1
  print -r -- "file:${digest%% *}:$mode"
}
env_record_path() {
  local key="$(print -rn -- "$2" | /usr/bin/shasum -a 256)" || return 1
  print -r -- "$STATE_ROOT/receipts/$1/${key%% *}"
}
env_probe_path() {
  case "$1" in
    env-core) print -r -- "$ENV_ROOT/zsh/env.zsh" ;;
    shell-behavior) print -r -- "$ENV_ROOT/zsh/custom/【MacOS】shell_behavior.zsh/【MacOS】shell_behavior.zsh" ;;
    user-mounts) print -r -- "$ENV_ROOT/zsh/【MacOS】user_mounts.zsh/【MacOS】user_mounts.zsh" ;;
    local-custom) print -r -- "$ENV_ROOT/zsh/custom/【MacOS】local.zsh/【MacOS】local.zsh" ;;
    shell-entry) print -r -- "$HOME/.zshrc" ;;
    runtime-support) print -r -- "$ENV_ROOT/Scripts/【MacOS】runtime_init.command/【MacOS】runtime_init.command" ;;
    cmd-*)
      local command_words="${COMMAND_ALIASES[$1]}"
      local -a aliases=( ${=command_words} )
      print -r -- "$BIN_ROOT/${aliases[1]}"
      ;;
  esac
}
# yes 只表示完整收据与当前文件一致；旧安装和后来修改均为 unknown。
env_component_status() {
  local component="$1" receipt="$STATE_ROOT/receipts/$1" record="" target="" expected="" actual="" count=0
  if [[ -L "$STATE_ROOT" || -L "$receipt" ]]; then print -r -- unknown; return 0; fi
  if [[ -d "$receipt" ]]; then
    [[ -f "$receipt/complete" ]] || { print -r -- unknown; return 0; }
    for record in "$receipt"/*(N/); do
      (( count += 1 ))
      [[ ! -L "$record" && -f "$record/relative" && -f "$record/after" ]] || { print -r -- unknown; return 0; }
      target="$(env_target "$(<"$record/relative")")" || { print -r -- unknown; return 0; }
      env_validate_target "$target" 2>/dev/null || { print -r -- unknown; return 0; }
      expected="$(<"$record/after")"
      actual="$(env_fingerprint "$target" 2>/dev/null)" || { print -r -- unknown; return 0; }
      [[ "$actual" == "$expected" ]] || { print -r -- unknown; return 0; }
    done
    if (( count > 0 )); then print -r -- yes; else print -r -- unknown; fi
    return 0
  fi
  target="$(env_probe_path "$component")" || { print -r -- unknown; return 0; }
  if [[ "$component" == shell-entry && -f "$target" && ! -L "$target" ]] &&
    ! /usr/bin/grep -Eq 'JobsMacEnv|JOBS_MAC_ENV_HOME' "$target"; then
    print -r -- no
    return 0
  fi
  if [[ -e "$target" || -L "$target" ]]; then print -r -- unknown; else print -r -- no; fi
}
env_print_catalog() {
  local component="" component_state=""
  for component in "${COMPONENT_IDS[@]}"; do
    component_state="$(env_component_status "$component")" || return 1
    printf '%s\t%s\t%s\t%s\n' "$component" "${LABELS[$component]}" "${DESCRIPTIONS[$component]}" "$component_state"
  done
}
# 只解释 sync_env 的声明字段，绝不 source 或 eval 用户配置。
env_read_settings() {
  SETTINGS=(JAVA_VERSION 17 ANDROID_SDK_DEFAULT '$HOME/Library/Android/sdk' USE_FVM true FLUTTER_CANDIDATES '$HOME/fvm/default/bin,$HOME/development/flutter/bin'
    ENABLE_COREPACK true NVM_DIR '$HOME/.nvm' ENABLE_PNPM true ENABLE_CARGO true CARGO_HOME '$HOME/.cargo'
    ENABLE_PYENV true PYENV_ROOT '$HOME/.pyenv' ENABLE_RBENV true RBENV_ROOT '$HOME/.rbenv' ENABLE_GO true GOPATH '$HOME/go')
  typeset -ga ENV_PATHS ENV_ALIASES
  ENV_PATHS=(); ENV_ALIASES=()
  local line="" section="" key="" value=""
  [[ -r "$SOURCE_ROOT/sync_env.txt" ]] || { env_error "缺少配置：$SOURCE_ROOT/sync_env.txt"; return 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" && "$line" != \#* ]] || continue
    if [[ "${line[1]}" == '[' && "${line[-1]}" == ']' ]]; then section="${line[2,-2]}"; continue; fi
    case "$section" in
      PATH) ENV_PATHS+=("$line") ;;
      ALIASES) ENV_ALIASES+=("$line") ;;
      *) key="${line%%=*}"; value="${line#*=}"; [[ -z "${SETTINGS[$key]+x}" ]] || SETTINGS[$key]="$value" ;;
    esac
  done < "$SOURCE_ROOT/sync_env.txt"
}
# 仅展开约定的 HOME 占位符，其余字符按字符串引用，避免配置变成代码。
env_quote_setting() {
  local value="$1"
  value="${value//\$\{HOME\}/$HOME}"
  value="${value//\$HOME/$HOME}"
  print -r -- "${(qqq)value}"
}
env_generate_environment() {
  print -r -- '# 自动生成；来源 sync_env.txt，由 JobsMacEnv 管理面板部署。'
  printf 'jobs_setup_java %s\n' "$(env_quote_setting "${SETTINGS[JAVA_VERSION]}")"
  printf 'jobs_setup_android %s\n' "$(env_quote_setting "${SETTINGS[ANDROID_SDK_DEFAULT]}")"
  printf 'jobs_setup_flutter %s %s\n' "$(env_quote_setting "${SETTINGS[USE_FVM]}")" "$(env_quote_setting "${SETTINGS[FLUTTER_CANDIDATES]}")"
  printf 'jobs_setup_node %s %s\n' "$(env_quote_setting "${SETTINGS[ENABLE_COREPACK]}")" "$(env_quote_setting "${SETTINGS[NVM_DIR]}")"
  local pair="" key="" method=""
  for pair in CARGO:rust PYENV:pyenv RBENV:rbenv GO:go; do
    key="${pair%%:*}"; method="${pair#*:}"
    if [[ "${SETTINGS[ENABLE_$key]}" == true ]]; then
      case "$key" in CARGO) key=CARGO_HOME ;; PYENV) key=PYENV_ROOT ;; RBENV) key=RBENV_ROOT ;; GO) key=GOPATH ;; esac
      printf 'jobs_setup_%s %s\n' "$method" "$(env_quote_setting "${SETTINGS[$key]}")"
    fi
  done
  local item=""
  for item in "${ENV_PATHS[@]}"; do printf 'jobs_path_add %s\n' "$(env_quote_setting "$item")"; done
  if [[ "${SETTINGS[ENABLE_PNPM]}" == true ]]; then
    print -r -- 'if command -v pnpm >/dev/null 2>&1; then'
    print -r -- '  export PNPM_HOME="$HOME/Library/pnpm"'
    print -r -- '  jobs_path_add "$PNPM_HOME"'
    print -r -- fi
  fi
}
env_generate_aliases() {
  print -r -- '# 自动生成别名；来源 sync_env.txt。'
  local item="" name="" value=""
  for item in "${ENV_ALIASES[@]}"; do
    name="${item%%=*}"; value="${item#*=}"
    [[ "$name" =~ '^[A-Za-z_][A-Za-z0-9_-]*$' ]] || { env_error "别名名称无效：$name"; return 2; }
    printf 'alias %s=%s\n' "$name" "${(qqq)value}"
  done
}
env_generate_shell_entry() {
  local target="$HOME/.zshrc" starts=0 ends=0
  env_validate_target "$target" || return $?
  if [[ -f "$target" ]]; then
    starts="$(/usr/bin/grep -Fxc '# >>> JobsMacEnv managed shell entry >>>' "$target" || true)"
    ends="$(/usr/bin/grep -Fxc '# <<< JobsMacEnv managed shell entry <<<' "$target" || true)"
    if (( starts != ends || starts > 1 )); then env_error '.zshrc 中受控标记异常，已停止。'; return 3; fi
    if (( starts == 1 )); then
      /usr/bin/awk '
        $0 == "# >>> JobsMacEnv managed shell entry >>>" { if (seen || inside) { bad=1; exit }; inside=1; seen=1 }
        $0 == "# <<< JobsMacEnv managed shell entry <<<" { if (!inside) { bad=1; exit }; inside=0 }
        END { if (inside || bad) exit 3 }
      ' "$target" || return 3
      /bin/cat "$target"
      return $?
    else
      /bin/cat "$target" || return 1
      # 原终端安装器的完整入口已经加载了环境，不能重复加载。
      if /usr/bin/grep -Fq 'jobs_source_if_exists "$JOBS_MAC_ENV_HOME/zsh/【MacOS】env_methods.zsh/【MacOS】env_methods.zsh"' "$target"; then return 0; fi
    fi
  fi
  printf '\n%s\n' '# >>> JobsMacEnv managed shell entry >>>'
  print -r -- '[[ -r "$HOME/.JobsMacEnv/.zshrc" ]] && source "$HOME/.JobsMacEnv/.zshrc"'
  print -r -- '# <<< JobsMacEnv managed shell entry <<<'
}
# 一次安装的负载先列清楚；同一目标只能由一个组件持有。
env_add_payload() {
  local component="$1" relative="$2" source="$3" mode="$4"
  [[ "$relative" != *'..'* && "$relative" != *$'\n'* && "$relative" != *$'\t'* ]] || return 2
  [[ -z "${PAYLOAD_COMPONENTS[$relative]:-}" || "${PAYLOAD_COMPONENTS[$relative]}" == "$component" ]] || return 2
  PAYLOAD_COMPONENTS[$relative]="$component"
  PAYLOAD_SOURCES[$relative]="$source"
  PAYLOAD_MODES[$relative]="$mode"
  if [[ -z "${PAYLOAD_ORIGINS[$relative]+x}" ]]; then
    local target="$(env_target "$relative")" || return $?
    env_validate_target "$target" || return $?
    PAYLOAD_ORIGINS[$relative]="$(env_fingerprint "$target")" || return $?
  fi
}
env_add_tree() {
  local component="$1" source="$2" destination="$3" file="" relative="" listing=""
  [[ -d "$source" && ! -L "$source" ]] || { env_error "缺少普通目录：$source"; return 1; }
  listing="$(/usr/bin/find "$source" \( -name .git -o -name node_modules -o -name Pods -o -name .dart_tool -o -name build -o -name DerivedData -o -name .DS_Store \) -prune -o -type l -print)" || return 1
  [[ -z "$listing" ]] || { env_error "源目录含链接，不能静默展开：$listing"; return 3; }
  listing="$(/usr/bin/find "$source" \( -name .git -o -name node_modules -o -name Pods -o -name .dart_tool -o -name build -o -name DerivedData -o -name .DS_Store \) -prune -o -type f -print)" || return 1
  for file in "${(@f)listing}"; do
    [[ -n "$file" ]] || continue
    relative="${file#"$source/"}"
    env_add_payload "$component" "$destination/$relative" "$file" preserve || return $?
  done
}
env_add_bundle() {
  env_add_tree "$1" "$SOURCE_ROOT/scripts/$2" "env/Scripts/$2"
}
env_build_payload() {
  typeset -gA PAYLOAD_COMPONENTS PAYLOAD_SOURCES PAYLOAD_MODES PAYLOAD_CONTENTS PAYLOAD_ORIGINS
  local component="" command_name="" aliases="" file="" content="" relative=""
  for component in "${EXPANDED[@]}"; do
    case "$component" in
      env-core)
        env_read_settings || return $?
        for file in 【MacOS】bootstrap.zsh/【MacOS】bootstrap.zsh 【MacOS】env_methods.zsh/【MacOS】env_methods.zsh; do env_add_payload "$component" "env/zsh/$file" "$SOURCE_ROOT/zsh/$file" preserve || return $?; done
        env_add_payload "$component" env/sync_env.txt "$SOURCE_ROOT/sync_env.txt" preserve || return $?
        env_add_payload "$component" env/.zshrc "$SOURCE_ROOT/Sys/.zshrc" preserve || return $?
        content="$(env_generate_environment)" || return $?
        PAYLOAD_CONTENTS[env/zsh/env.zsh]="$content"$'\n'
        env_add_payload "$component" env/zsh/env.zsh generated 600 || return $?
        content="$(env_generate_aliases)" || return $?
        PAYLOAD_CONTENTS[env/zsh/aliases.zsh]="$content"$'\n'
        env_add_payload "$component" env/zsh/aliases.zsh generated 600 || return $?
        ;;
      shell-behavior)
        for file in 【MacOS】shell_behavior.zsh/【MacOS】shell_behavior.zsh 【MacOS】git_behavior.zsh/【MacOS】git_behavior.zsh 【MacOS】path_drag_resolver.zsh/【MacOS】path_drag_resolver.zsh; do env_add_payload "$component" "env/zsh/custom/$file" "$SOURCE_ROOT/zsh/custom/$file" preserve || return $?; done
        ;;
      user-mounts) env_add_payload "$component" env/zsh/【MacOS】user_mounts.zsh/【MacOS】user_mounts.zsh "$SOURCE_ROOT/zsh/【MacOS】user_mounts.zsh/【MacOS】user_mounts.zsh" preserve || return $? ;;
      local-custom) env_add_payload "$component" env/zsh/custom/【MacOS】local.zsh/【MacOS】local.zsh "$SOURCE_ROOT/zsh/custom/【MacOS】local.zsh/【MacOS】local.zsh" preserve || return $? ;;
      shell-entry)
        PAYLOAD_ORIGINS[zshrc]="$(env_fingerprint "$HOME/.zshrc")" || return $?
        content="$(env_generate_shell_entry && printf '\001')" || return $?
        PAYLOAD_CONTENTS[zshrc]="${content%$'\001'}"
        [[ "$(env_fingerprint "$HOME/.zshrc")" == "${PAYLOAD_ORIGINS[zshrc]}" ]] || { env_error '.zshrc 在生成候选时发生变化，已停止。'; return 3; }
        env_add_payload "$component" zshrc generated 600 || return $?
        ;;
      runtime-support)
        for file in 【MacOS】entrypoints.command 【MacOS】runtime_init.command 【MacOS】flutter_project.command 【MacOS】install_jdk17.command; do env_add_bundle "$component" "$file" || return $?; done
        env_add_tree "$component" "$SOURCE_ROOT/scripts/_lib" env/Scripts/_lib || return $?
        ;;
      cmd-*)
        file="${COMMAND_FILES[$component]}"
        env_add_bundle "$component" "$file" || return $?
        aliases="${COMMAND_ALIASES[$component]}"
        for command_name in ${=aliases}; do
          relative="bin/$command_name"
          content=$'#!/bin/zsh\n# JobsMacEnv 分项管理转发器；真实业务在完整脚本包内执行。\n'
          content+='exec /bin/zsh "$HOME/.JobsMacEnv/Scripts/'"$file/$file"'"'
          [[ "$component" != cmd-to || "$command_name" == to ]] || content+=" ${(qqq)command_name}"
          content+=' "$@"'
          PAYLOAD_CONTENTS[$relative]="$content"$'\n'
          env_add_payload "$component" "$relative" generated 755 || return $?
        done
        ;;
    esac
  done
}
# 所有源文件与已有收据先校验，再开始写入；发现并发修改直接保留。
env_preflight_install() {
  local relative="" target="" component="" record="" current="" after="" before="" prior=""
  for relative in "${(@k)PAYLOAD_COMPONENTS}"; do
    component="${PAYLOAD_COMPONENTS[$relative]}"
    target="$(env_target "$relative")" || return $?
    env_validate_target "$target" || return $?
    if [[ "${PAYLOAD_SOURCES[$relative]}" != generated ]]; then
      [[ -f "${PAYLOAD_SOURCES[$relative]}" && ! -L "${PAYLOAD_SOURCES[$relative]}" ]] || { env_error "源文件不可读：${PAYLOAD_SOURCES[$relative]}"; return 1; }
    fi
    record="$(env_record_path "$component" "$relative")" || return 1
    env_validate_target "$record/.probe" || return $?
    if [[ -d "$record" ]]; then
      [[ ! -L "$record" && -f "$record/before" && -f "$record/relative" ]] || { env_error "收据残缺：$record"; return 3; }
      [[ "$(<"$record/relative")" == "$relative" ]] || return 3
      current="$(env_fingerprint "$target")" || return $?
      before="$(<"$record/before")"
      after="$(<"$record/after")" 2>/dev/null || after=''
      prior="$(<"$record/prior")" 2>/dev/null || prior=''
      if [[ "$current" != "$after" && "$current" != "$before" && "$current" != "$prior" ]]; then env_error "已被后来修改，安装时保留：$target"; return 3; fi
    fi
  done
}
# 私有状态与独占锁只在 --yes 的真实写操作中创建。
env_begin_transaction() {
  local parent="${STATE_ROOT:h}" directory=""
  env_validate_target "$STATE_ROOT/.probe" || return $?
  for directory in receipts history logs; do
    env_validate_target "$STATE_ROOT/$directory/.probe" || return $?
  done
  /bin/mkdir -p "$STATE_ROOT/receipts" "$STATE_ROOT/history" "$STATE_ROOT/logs" || return 1
  /bin/chmod 700 "$STATE_ROOT" "$STATE_ROOT/receipts" "$STATE_ROOT/history" "$STATE_ROOT/logs" || return 1
  LOCK_TOKEN="$$:$(/bin/date +%s):$RANDOM"
  if ! /bin/mkdir "$LOCK_ROOT" 2>/dev/null; then env_error "另一个操作或未清理的锁存在：$LOCK_ROOT；请核对后重试。"; return 4; fi
  print -r -- "$LOCK_TOKEN" > "$LOCK_ROOT/owner" || return 1
  RUN_ID="$(/bin/date +%Y%m%d-%H%M%S)-$$-$RANDOM"
  LOG_FILE="$STATE_ROOT/logs/$RUN_ID.log"
  (umask 077; : > "$LOG_FILE") || return 1
  env_log "操作：$ACTION；来源：$SOURCE_ROOT；目标：$ENV_ROOT / $BIN_ROOT / .zshrc"
  env_log "收据与备份：$STATE_ROOT；日志：$LOG_FILE"
}
env_release_transaction() {
  if [[ -n "$LOCK_TOKEN" && -f "$LOCK_ROOT/owner" && ! -L "$LOCK_ROOT" && "$(<"$LOCK_ROOT/owner")" == "$LOCK_TOKEN" ]]; then
    /bin/rm -f "$LOCK_ROOT/owner"
    /bin/rmdir "$LOCK_ROOT" 2>/dev/null || true
  fi
}
TRAPEXIT() {
  local result=$?
  (( ZSH_SUBSHELL == 0 )) || return "$result"
  env_release_transaction
  return "$result"
}
TRAPINT() { exit 130; }
TRAPTERM() { exit 143; }
TRAPHUP() { exit 129; }
# 写前保存原件与候选指纹，发布前再次核对，失败可由下一次恢复。
env_install_file() {
  local component="$1" relative="$2" target="" record="" before="" expected="" prior="" candidate="" source="${PAYLOAD_SOURCES[$2]}" mode="${PAYLOAD_MODES[$2]}"
  target="$(env_target "$relative")" || return $?
  env_validate_target "$target" || return $?
  record="$(env_record_path "$component" "$relative")" || return 1
  env_validate_target "$record/.probe" || return $?
  before="$(env_fingerprint "$target")" || return $?
  [[ "$before" == "${PAYLOAD_ORIGINS[$relative]}" ]] || { env_error "目标在计划后发生变化，已保留：$target"; return 3; }
  if [[ ! -d "$record" ]]; then
    /bin/mkdir -p "$record" || return 1
    print -r -- "$relative" > "$record/relative" || return 1
    if [[ "$before" != absent ]]; then
      /bin/cp -p "$target" "$record/original" || return 1
      [[ "$(env_fingerprint "$record/original")" == "$before" ]] || { env_error "备份核验失败：$target"; return 1; }
    fi
    print -r -- "$before" > "$record/before" || return 1
  else
    [[ -f "$record/relative" && -f "$record/before" && "$(<"$record/relative")" == "$relative" ]] || return 3
    expected="$(<"$record/after")" 2>/dev/null || expected=''
    prior="$(<"$record/prior")" 2>/dev/null || prior=''
    [[ "$before" == "$expected" || "$before" == "$(<"$record/before")" || "$before" == "$prior" ]] || { env_error "发布前文件变化，已保留：$target"; return 3; }
  fi
  /bin/mkdir -p "${target:h}" || return 1
  candidate="$(umask 077; /usr/bin/mktemp "${target:h}/.jobs-env.XXXXXXXX")" || return 1
  if [[ "$source" == generated ]]; then
    print -rn -- "${PAYLOAD_CONTENTS[$relative]}" > "$candidate" || return 1
    /bin/chmod "$mode" "$candidate" || return 1
  else
    /bin/cp -p "$source" "$candidate" || return 1
    # 包内主入口保留原执行语义，确保 App 携带的资源也可运行。
    if [[ "$relative" == env/Scripts/*.command/*.command ]]; then /bin/chmod u+x "$candidate" || return 1; fi
  fi
  expected="$(env_fingerprint "$candidate")" || return 1
  print -r -- "$before" > "$record/prior" || return 1
  print -r -- "$expected" > "$record/after.pending" || return 1
  /bin/mv -f "$record/after.pending" "$record/after" || return 1
  env_validate_target "$target" || return $?
  [[ "$(env_fingerprint "$target")" == "$before" ]] || { /bin/rm -f "$candidate"; env_error "候选发布前文件变化：$target"; return 3; }
  /bin/mv -f "$candidate" "$target" || return 1
  [[ "$(env_fingerprint "$target")" == "$expected" ]] || return 1
}
env_install_components() {
  local component="" relative="" count=0
  for component in "${EXPANDED[@]}"; do
    env_event "$component" running "正在安装 ${LABELS[$component]}"
    env_log "开始安装：${LABELS[$component]} [$component]"
    count=0
    for relative in "${(@ok)PAYLOAD_COMPONENTS}"; do
      [[ "${PAYLOAD_COMPONENTS[$relative]}" == "$component" ]] || continue
      if env_install_file "$component" "$relative"; then
        :
      else
        local install_code=$?
        env_event "$component" failed "安装失败，已保存收据与原件；退出码 $install_code"
        return "$install_code"
      fi
      (( count += 1 ))
    done
    (( count > 0 )) || { env_error "组件没有负载：$component"; return 1; }
    print -r -- "$RUN_ID" > "$STATE_ROOT/receipts/$component/complete" || return 1
    env_log "✔ 已安装：${LABELS[$component]}（$count 个文件）"
    env_event "$component" success "已安装 $count 个文件"
  done
  env_log '新终端将读取所选环境；当前终端需自行重新加载 .zshrc。'
}
# 未被收据登记的文件若仍引用共享支持，不能只根据已选组件推断无人使用。
env_scan_unknown_references() {
  local component="" receipt="" record="" relative="" target="" file="" found=0
  local -a roots
  if (( ${#KNOWN_MANAGED_TARGETS} == 0 )); then
    for receipt in "$STATE_ROOT/receipts"/*(N/); do
      for record in "$receipt"/*(N/); do
        [[ -f "$record/relative" && ! -L "$record" ]] || continue
        relative="$(<"$record/relative")"
        target="$(env_target "$relative")" || return 3
        KNOWN_MANAGED_TARGETS[$target]=1
      done
    done
  fi
  for target in "$BIN_ROOT" "$ENV_ROOT/Scripts" "$ENV_ROOT/zsh"; do
    [[ ! -d "$target" || -L "$target" ]] || roots+=("$target")
  done
  if (( ${#roots} > 0 )); then
    /usr/bin/find "${roots[@]}" \( -name .git -o -name node_modules -o -name Pods -o -name .dart_tool -o -name build -o -name DerivedData \) -prune -o -type f -print0 |
      while IFS= read -r -d '' file; do
        [[ -z "${KNOWN_MANAGED_TARGETS[$file]:-}" ]] || continue
        if /usr/bin/grep -IqE '(\.JobsMacEnv|JOBS_MAC_ENV_HOME|_lib/|entrypoints\.command|runtime_init\.command)' "$file"; then
          env_error "发现无收据的共享引用，保留公共环境：$file"
          found=1
        fi
      done || return 3
  fi
  target="$HOME/.zshrc"
  if [[ -f "$target" && ! -L "$target" && -z "${KNOWN_MANAGED_TARGETS[$target]:-}" ]] &&
    /usr/bin/grep -IqE '(\.JobsMacEnv|JOBS_MAC_ENV_HOME)' "$target"; then
    env_error "发现无收据的 Shell 加载引用，保留公共环境：$target"
    found=1
  fi
  (( found == 0 )) || return 3
}
# 共享模块的依赖按文件加载关系定义，失败后仍保留的收据也算存活引用。
env_component_dependents() {
  case "$1" in
    env-core) print -rl -- "${(@)COMPONENT_IDS:#env-core}" ;;
    runtime-support) print -rl -- shell-entry local-custom "${COMMAND_IDS[@]}" ;;
    user-mounts) print -rl -- shell-entry shell-behavior local-custom "${COMMAND_IDS[@]}" ;;
    local-custom) print -rl -- shell-entry "${COMMAND_IDS[@]}" ;;
  esac
}
# 公共支持被其它未选组件引用时不能删除，不清空共享环境。
env_preflight_uninstall() {
  local component="" dependent="" protected=0
  typeset -gA KNOWN_MANAGED_TARGETS
  for component in env-core runtime-support user-mounts local-custom; do
    env_selected "$component" || continue
    env_scan_unknown_references || return 3
    local dependents="$(env_component_dependents "$component")"
    for dependent in "${(@f)dependents}"; do
      env_selected "$dependent" && continue
      if [[ -d "$STATE_ROOT/receipts/$dependent" ]]; then
        env_error "仍被未选组件引用：${LABELS[$dependent]}；请一并勾选，或保留公共环境。"
        protected=1
      fi
    done
  done
  (( protected == 0 ))
}
env_uninstall_record() {
  local component="$1" record="$2" relative="" target="" before="" after="" prior="" current="" candidate="" history=""
  [[ ! -L "$record" && -f "$record/relative" && -f "$record/before" ]] || { env_error "收据残缺，保留：$record"; return 3; }
  env_validate_target "$record/.probe" || return $?
  relative="$(<"$record/relative")"
  [[ "$relative" != *'..'* ]] || return 3
  target="$(env_target "$relative")" || return 3
  env_validate_target "$target" || return $?
  before="$(<"$record/before")"
  after="$(<"$record/after")" 2>/dev/null || after=''
  prior="$(<"$record/prior")" 2>/dev/null || prior=''
  current="$(env_fingerprint "$target")" || return $?
  if [[ "$current" == "$before" ]]; then
    env_log "已恢复原状态：$target"
  elif [[ ( -n "$after" && "$current" == "$after" ) || ( -n "$prior" && "$current" == "$prior" ) ]]; then
    if [[ "$before" == absent ]]; then
      [[ "$(env_fingerprint "$target")" == "$current" ]] || return 3
      /bin/rm -f "$target" || return 1
    else
      [[ -f "$record/original" && ! -L "$record/original" && "$(env_fingerprint "$record/original")" == "$before" ]] || { env_error "原件备份缺失或变化：$target"; return 3; }
      candidate="$(umask 077; /usr/bin/mktemp "${target:h}/.jobs-env.XXXXXXXX")" || return 1
      /bin/cp -p "$record/original" "$candidate" || return 1
      [[ "$(env_fingerprint "$target")" == "$current" ]] || { /bin/rm -f "$candidate"; return 3; }
      /bin/mv -f "$candidate" "$target" || return 1
    fi
    [[ "$(env_fingerprint "$target")" == "$before" ]] || return 1
  else
    env_error "用户修改或原点未知，已保留：$target；备份：$record"
    return 3
  fi
  history="$STATE_ROOT/history/$RUN_ID/$component"
  /bin/mkdir -p "$history" || return 1
  /bin/mv "$record" "$history/${record:t}" || return 1
}
# 先核对同一组件的全部文件，用户修改不应导致该组件只卸载一半。
env_preflight_component_uninstall() {
  local component="$1" record="" target="" current="" before="" after="" prior=""
  for record in "$STATE_ROOT/receipts/$component"/*(N/); do
    [[ ! -L "$record" && -f "$record/relative" && -f "$record/before" ]] || { env_error "收据残缺，保留组件：$component"; return 3; }
    target="$(env_target "$(<"$record/relative")")" || return 3
    env_validate_target "$target" || return $?
    current="$(env_fingerprint "$target")" || return $?
    before="$(<"$record/before")"
    after="$(<"$record/after")" 2>/dev/null || after=''
    prior="$(<"$record/prior")" 2>/dev/null || prior=''
    [[ "$current" == "$before" || "$current" == "$after" || "$current" == "$prior" ]] || { env_error "组件包含用户后来修改，全部保留：$target"; return 3; }
    if [[ "$before" != absent ]]; then
      [[ -f "$record/original" && ! -L "$record/original" && "$(env_fingerprint "$record/original")" == "$before" ]] || { env_error "恢复备份缺失或变化：$target"; return 3; }
    fi
  done
}
env_uninstall_components() {
  local component="" receipt="" record="" state="" failures=0 component_failed=0
  for component in "${(@Oa)EXPANDED}"; do
    component_failed=0
    env_event "$component" running "正在卸载 ${LABELS[$component]}"
    env_log "开始卸载：${LABELS[$component]} [$component]"
    receipt="$STATE_ROOT/receipts/$component"
    if [[ "$component" == env-core || "$component" == runtime-support || "$component" == user-mounts || "$component" == local-custom ]]; then
      local still_referenced=0 dependent=""
      local dependents="$(env_component_dependents "$component")"
      for dependent in "${(@f)dependents}"; do
        [[ ! -d "$STATE_ROOT/receipts/$dependent" ]] || still_referenced=1
      done
      if (( still_referenced )); then
        env_log "⚠ 仍有依赖组件未完全撤回，保留：${LABELS[$component]}"
        env_event "$component" failed '仍被未完成卸载的组件引用，已保留'
        failures=1
        continue
      fi
      if ! env_scan_unknown_references; then
        env_event "$component" failed '仍有无收据的共享引用，已保留'
        failures=1
        continue
      fi
    fi
    if [[ ! -d "$receipt" ]]; then
      state="$(env_component_status "$component")"
      if [[ "$state" == no ]]; then
        env_log '未安装，跳过。'
        env_event "$component" success '未安装，已跳过'
      else
        env_log '⚠ 没有本工具收据；保留历史安装与用户配置，无法恢复未知原点。'
        env_event "$component" failed '没有本工具收据，历史安装与用户配置已保留'
        failures=1
      fi
      continue
    fi
    if ! env_preflight_component_uninstall "$component"; then
      env_event "$component" failed '组件有用户修改或备份异常，整个组件已保留'
      failures=1
      continue
    fi
    for record in "$receipt"/*(N/); do
      if ! env_uninstall_record "$component" "$record"; then failures=1; component_failed=1; fi
    done
    if [[ -z "$(/usr/bin/find "$receipt" -mindepth 1 -type d -print -quit)" ]]; then
      [[ ! -f "$receipt/complete" ]] || /bin/rm -f "$receipt/complete" || return 1
      /bin/rmdir "$receipt" || return 1
      env_log "✔ 已撤回：${LABELS[$component]}；恢复材料保留在 history。"
      env_event "$component" success '已按收据恢复原状态'
    else
      env_log "⚠ 尚有保留项：${LABELS[$component]}；修复冲突后可再次卸载。"
      env_event "$component" failed '用户修改或收据异常，尚有保留项'
    fi
  done
  env_log '卸载不清除 SDK、模型、缓存、用户数据或其它工具的配置。空目录与历史备份保留。'
  (( failures == 0 )) || return 3
}
env_run_action() {
  env_expand_selection || return $?
  if [[ "$ACTION" == install ]]; then env_build_payload || return $?; env_preflight_install || return $?; else env_preflight_uninstall || return 3; fi
  if (( DRY_RUN )); then
    local component=""
    for component in "${EXPANDED[@]}"; do print -r -- "计划 $ACTION：$component · ${LABELS[$component]}"; done
    print -r -- '演练完成：未写用户配置、收据或日志。'
    return 0
  fi
  (( CONFIRMED )) || { env_error '真实操作需要明确 --yes；可先使用 --dry-run 查看计划。'; return 2; }
  env_log 'JobsMacEnv 分项环境管理：按收据安装或恢复所选对象；用户修改与未知归属保留。'
  env_begin_transaction || return $?
  if [[ "$ACTION" == install ]]; then env_install_components; else env_uninstall_components; fi
}
# 解析机器协议并定位路径；失败时不构建目录或执行写操作。
env_prepare_context() {
  env_parse_arguments "$@" || exit $?
  env_initialize_paths || exit $?
}
# 按已校验动作分发，保留帮助和目录查询的纯净输出。
env_dispatch_action() {
  case "$ACTION" in
    help) env_usage ;;
    catalog) env_print_catalog ;;
    install|uninstall) env_run_action ;;
  esac
}
# 统一后端协议入口，不向机器查询输出插入终端交互。
main() {
  env_prepare_context "$@" # 校验协议并定位实际资源，错误时不进入下游。
  env_build_catalog # 构建稳定的组件标识与命令映射。
  env_dispatch_action # 查询保持纯净，明确写操作仍走原授权入口。
}

main "$@"
