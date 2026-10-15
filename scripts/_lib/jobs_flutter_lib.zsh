# JobsMacEnv Flutter private library. Do not call directly.

# 解析 PATH 中的真实外部命令，跳过当前脚本自身，避免 flutter 自定义入口递归调用自己。
# 输出当前脚本内的 Homebrew 健康诊断。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
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
# ================================== CONFIG（硬编码绝对路径：你只改这里）==================================
# ✅ 直接写死绝对路径：复制粘贴后只改这一行就行
JOBS_FLUTTER_PROJECT_DIR="/Users/jobs/Documents/Github/flutter_tiyu_app"

# （可选）dart completion 路径也别写死 /Users/mac 了
JOBS_DART_CLI_COMPLETION_FILE="/Users/jobs/.dart-cli-completion/zsh-config.zsh"

# ================================== 通用：项目目录自检与解析 ==================================
# 用法：
#   jobs_flutter_get_project_dir                 -> 用默认 JOBS_FLUTTER_PROJECT_DIR
#   jobs_flutter_get_project_dir "/abs/path"     -> 用你传入的绝对路径（会自检）
jobs_flutter_get_project_dir() {
  local dir="${1:-$JOBS_FLUTTER_PROJECT_DIR}"

  # 允许你传 "~" 这种写法（虽然你说要绝对路径，但顺手兼容）
  eval "dir=\"$dir\""

  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo "❌ 项目目录不存在：$dir" >&2
    echo "👉 请修改 JOBS_FLUTTER_PROJECT_DIR 为真实绝对路径" >&2
    return 1
  fi

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
      echo -e "\033[1;32m✅ 已加载配置文件：file://$file\033[0m"
    else
      echo -e "\033[1;33m⚠️ 未找到配置文件：file://$file\033[0m"
    fi
  done
  echo -e "\n📎 ⌘Command + 点击路径可打开对应文件（macOS Terminal 支持）"
}

# 🔥 flutter() 重载（优先 FVM）🔥
jobs_flutter_flutter_impl() {
  emulate -L zsh
  setopt no_aliases

  local d="$PWD"
  local root=""

  while [[ "$d" != "/" ]]; do
    if [[ -f "$d/.fvmrc" || -x "$d/.fvm/flutter_sdk/bin/flutter" || -f "$d/.fvm/fvm_config.json" ]]; then
      root="$d"
      break
    fi
    d="${d:h}"
  done

  if [[ -n "$root" && -x "$root/.fvm/flutter_sdk/bin/flutter" ]]; then
    command "$root/.fvm/flutter_sdk/bin/flutter" "$@"
    return $?
  fi

  if [[ -n "$root" && ( -f "$root/.fvmrc" || -f "$root/.fvm/fvm_config.json" ) ]]; then
    if command -v fvm >/dev/null 2>&1; then
      command fvm flutter "$@"
      return $?
    fi
    print -u2 "✖ 检测到 FVM 项目，但找不到 fvm 命令。请先安装 fvm。"
    return 127
  fi

  local external_flutter=""
  external_flutter="$(jobs_flutter_find_external_command flutter 2>/dev/null || true)"
  if [[ -n "$external_flutter" ]]; then
    "$external_flutter" "$@"
    return $?
  fi

  print -u2 "✖ flutter: command not found（未安装系统 Flutter，且当前目录不在 FVM 项目内）"
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
jobs_flutter_i_impl() { open -a Simulator; }

# ✅ d：默认进入你写死的项目目录（可传参覆盖）
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

  fvm use 3.24.5 --force
  jobs_flutter_flutter_impl doctor -v
}

# 🔥 JDK17 锁定到项目（c）🔥
# ✅ 默认项目目录改为硬编码常量 + 自检
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
    read -r "?是否执行清理和依赖安装 (回车=执行，任意字符=跳过): " ans
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
  while ! jobs_flutter_is_flutter_project "$project_path"; do
    echo "❌ [$project_path] 不是 Flutter 项目目录（缺少 lib/ 或 pubspec.yaml）" >&2
    read -r "?👉 请输入 Flutter 项目路径（回车=继续询问，q=退出）: " input_path
    [[ "$input_path" == [Qq] ]] && return 1
    [[ -z "$input_path" ]] && continue
    eval "project_path=\"$input_path\""
    project_path="$(cd "$project_path" 2>/dev/null && pwd || echo "")"
    [[ -z "$project_path" ]] && echo "⚠️ 路径无效，请重试" >&2
  done
  printf "%s\n" "$project_path"
}

# 🔥 APK / IPA 构建（保持你的逻辑）🔥
jobs_flutter_set_flutter_cmd() {
  export PATH="$HOME/.pub-cache/bin:$PATH"
  if command -v fvm >/dev/null 2>&1; then
    flutter_cmd=(fvm flutter)
  else
    local external_flutter=""
    external_flutter="$(jobs_flutter_find_external_command flutter 2>/dev/null || true)"
    if [[ -n "$external_flutter" ]]; then
      flutter_cmd=("$external_flutter")
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
  if [[ -x .fvm/flutter_sdk/bin/flutter ]]; then
    v="$(.fvm/flutter_sdk/bin/flutter --version 2>/dev/null | grep -Eo 'Flutter [0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}' | head -n1)"
    [[ -n "$v" ]] && echo "$v" && return 0
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
    versions="$(curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json \
      | jq -r '.releases[] | select(.channel=="stable") | .version' | sort -V | uniq | tac)"
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
  fvm install "$desired_version" || { echo "[ERROR] fvm install 失败"; return 1; }
  fvm use "$desired_version" --force || { echo "[ERROR] fvm use 失败"; return 1; }
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
