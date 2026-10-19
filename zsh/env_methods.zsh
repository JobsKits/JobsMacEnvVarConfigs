# ========================
# 环境工具函数
# ========================

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
jobs_log() {
  echo "[jobs-env] $1"
}

jobs_detect_arch() {
  uname -m
}

jobs_brew_prefix() {
  local brew_bin=""
  if brew_bin="$(jobs_brew_find)"; then
    "$brew_bin" --prefix
  else
    echo ""
  fi
}

jobs_source_if_exists() {
  local file="$1"
  [[ -f "$file" ]] && source "$file"
}

jobs_path_has() {
  local dir="$1"
  case ":$PATH:" in
    *":$dir:"*) return 0 ;;
    *) return 1 ;;
  esac
}

jobs_path_add() {
  local dir="$1"
  [[ -n "$dir" ]] || return 0
  [[ -d "$dir" ]] || return 0
  jobs_path_has "$dir" || PATH="$dir:$PATH"
}

jobs_path_append() {
  local dir="$1"
  [[ -n "$dir" ]] || return 0
  [[ -d "$dir" ]] || return 0
  jobs_path_has "$dir" || PATH="$PATH:$dir"
}

jobs_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

jobs_resolve_java_home() {
  local version="$1"
  local java_home=""

  if [[ -x /usr/libexec/java_home ]]; then
    java_home=$(/usr/libexec/java_home -v "$version" 2>/dev/null || true)
  fi

  if [[ -n "$java_home" && -d "$java_home" ]]; then
    printf "%s" "$java_home"
    return 0
  fi

  local candidates=(
    "/Library/Java/JavaVirtualMachines/temurin-${version}.jdk/Contents/Home"
    "/Library/Java/JavaVirtualMachines/zulu-${version}.jdk/Contents/Home"
    "/Library/Java/JavaVirtualMachines/openjdk-${version}.jdk/Contents/Home"
    "/opt/homebrew/opt/openjdk@${version}/libexec/openjdk.jdk/Contents/Home"
    "/usr/local/opt/openjdk@${version}/libexec/openjdk.jdk/Contents/Home"
  )

  local item
  for item in "${candidates[@]}"; do
    if [[ -d "$item" ]]; then
      printf "%s" "$item"
      return 0
    fi
  done

  return 1
}

jobs_setup_java() {
  local version="$1"
  local java_home=""

  java_home="$(jobs_resolve_java_home "$version" 2>/dev/null || true)"

  if [[ -n "$java_home" && -d "$java_home" ]]; then
    export JAVA_HOME="$java_home"
    jobs_path_add "$JAVA_HOME/bin"
  fi
}

jobs_setup_android() {
  local sdk_dir="$1"
  [[ -d "$sdk_dir" ]] || return 0

  export ANDROID_SDK_ROOT="$sdk_dir"
  export ANDROID_HOME="$sdk_dir"

  jobs_path_add "$sdk_dir/platform-tools"
  jobs_path_add "$sdk_dir/cmdline-tools/latest/bin"
  jobs_path_add "$sdk_dir/emulator"
  jobs_path_add "$sdk_dir/tools"
  jobs_path_add "$sdk_dir/tools/bin"
}

# 把 Flutter 兜底候选目录挂到 PATH（逗号分隔，取第一个真实存在的目录）。
jobs_flutter_link_path_candidates() {
  local candidates_csv="$1"
  local item=""

  # zsh 默认不做单词拆分（与 bash 的 IFS + $var 语义不同）。
  # 这里必须用 ${(s:,:)} 显式切分，否则整串会被当成单个路径，导致一个候选都挂不上。
  for item in ${(s:,:)candidates_csv}; do
    item="${item//\$HOME/$HOME}"
    [[ -n "$item" ]] || continue
    if [[ -d "$item" ]]; then
      jobs_path_add "$item"
      return 0
    fi
  done

  return 1
}

# 挂载项目感知的 flutter()/dart()：版本按当前项目 .fvmrc 解析，而不是固定 default。
jobs_flutter_enable_project_aware() {
  local env_home="${JOBS_MAC_ENV_HOME:-$HOME/.JobsMacEnv}"
  local hook="$env_home/Scripts/flutter_project.command/flutter_project.command"

  [[ -f "$hook" ]] || return 0
  jobs_source_if_exists "$hook"
}

jobs_setup_flutter() {
  local use_fvm="$1"
  local candidates_csv="$2"

  # 不在环境初始化层定义 flutter 自定义命令。
  # flutter shell 函数由 Scripts/flutter_project.command/flutter_project.command 承载，保持原版位置。
  if [[ "$use_fvm" == "true" ]]; then
    jobs_path_add "$HOME/.pub-cache/bin"
  fi

  jobs_flutter_link_path_candidates "$candidates_csv" || true

  # 开启 FVM 时把项目感知的解析器挂进当前 shell，保证 flutter/dart 跟随项目锚定版本。
  if [[ "$use_fvm" == "true" ]]; then
    jobs_flutter_enable_project_aware
  fi
}

jobs_setup_node() {
  local enable_corepack="$1"
  local nvm_dir="$2"

  export NVM_DIR="$nvm_dir"

  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    source "$NVM_DIR/nvm.sh"
  fi

  if [[ "$enable_corepack" == "true" ]] && jobs_command_exists corepack; then
    true
  fi
}

jobs_setup_rust() {
  local cargo_home="$1"
  export CARGO_HOME="$cargo_home"
  jobs_path_add "$CARGO_HOME/bin"
}

jobs_setup_pyenv() {
  local pyenv_root="$1"
  if [[ -d "$pyenv_root" ]]; then
    export PYENV_ROOT="$pyenv_root"
    jobs_path_add "$PYENV_ROOT/bin"
    if jobs_command_exists pyenv; then
      eval "$(pyenv init - zsh)"
    fi
  fi
}

jobs_setup_rbenv() {
  local rbenv_root="$1"
  if [[ -d "$rbenv_root" ]]; then
    export RBENV_ROOT="$rbenv_root"
    jobs_path_add "$RBENV_ROOT/bin"
    if jobs_command_exists rbenv; then
      eval "$(rbenv init - zsh)"
    fi
  fi
}

jobs_setup_go() {
  local gopath="$1"
  export GOPATH="$gopath"
  jobs_path_add "$GOPATH/bin"
}
