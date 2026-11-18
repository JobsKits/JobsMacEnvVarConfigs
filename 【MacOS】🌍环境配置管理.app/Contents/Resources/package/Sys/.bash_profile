#!/bin/bash
# ================================== ~/.bash_profile (safe & quiet) ==================================
# 目标：
# 1) 任何工具未安装都不报错（brew/rbenv/jenv/sdkman 等）
# 2) 仅交互式 shell 才做 cd / 初始化，避免影响脚本
# 3) PATH 追加防重复，避免越叠越长

# ---------------------------------- Helpers -----------------------------------
path_prepend() { # prepend dir to PATH if exists and not duplicated
  [ -d "$1" ] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

path_append() {  # append dir to PATH if exists and not duplicated
  [ -d "$1" ] || return 0
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$PATH:$1" ;;
  esac
}

# ---------------------------------- Interactive only -----------------------------------
case "$-" in
  *i*) IS_INTERACTIVE=1 ;;
  *)   IS_INTERACTIVE=0 ;;
esac

# ================================== 默认进入桌面目录（仅交互式 shell） ==================================
if [ "$IS_INTERACTIVE" = "1" ] && [ -d "$HOME/Desktop" ]; then
  cd "$HOME/Desktop" 2>/dev/null
fi

# ================================== Homebrew shellenv（芯片自检 + 路径兜底） ==================================
init_homebrew() {
  local arch brew_bin

  arch="$(uname -m)"

  # 先按芯片给默认路径（更符合直觉）
  if [ "$arch" = "arm64" ]; then
    brew_bin="/opt/homebrew/bin/brew"
  else
    brew_bin="/usr/local/bin/brew"
  fi

  # 再做事实兜底：如果默认不存在，就在常见路径里找
  if [ ! -x "$brew_bin" ]; then
    if [ -x /opt/homebrew/bin/brew ]; then
      brew_bin="/opt/homebrew/bin/brew"
    elif [ -x /usr/local/bin/brew ]; then
      brew_bin="/usr/local/bin/brew"
    else
      # 没安装 brew：安静跳过（不报错）
      return 0
    fi
  fi

  eval "$("$brew_bin" shellenv)"
}

init_homebrew

# ================================== Homebrew Curl（存在才加载） ==================================
if [ -d /usr/local/opt/curl ]; then
  path_prepend "/usr/local/opt/curl/bin"
  export LDFLAGS="-L/usr/local/opt/curl/lib"
  export CPPFLAGS="-I/usr/local/opt/curl/include"
  export PKG_CONFIG_PATH="/usr/local/opt/curl/lib/pkgconfig"
elif [ -d /opt/homebrew/opt/curl ]; then
  path_prepend "/opt/homebrew/opt/curl/bin"
  export LDFLAGS="-L/opt/homebrew/opt/curl/lib"
  export CPPFLAGS="-I/opt/homebrew/opt/curl/include"
  export PKG_CONFIG_PATH="/opt/homebrew/opt/curl/lib/pkgconfig"
fi

# ================================== rbenv (bash only) ==================================
# 只在 bash 中初始化，避免被 zsh source 时加载 bash completion 导致 `complete` 报错
if [[ -n "$BASH_VERSION" ]] && command -v rbenv >/dev/null 2>&1; then
  eval "$(rbenv init - bash)"
fi

# ================================== Homebrew Ruby（如果你不用 rbenv 可保留；存在才加） ==================================
# 如果你明确只用 rbenv，下面两行可以删掉
path_prepend "/usr/local/opt/ruby/bin"
path_prepend "/opt/homebrew/opt/ruby/bin"

# ================================== jenv（存在才启用；避免 command not found） ==================================
path_prepend "$HOME/.jenv/bin"
if command -v jenv >/dev/null 2>&1; then
  eval "$(jenv init -)"
  export JAVA_HOME="$HOME/.jenv/versions/$(jenv version-name)"
  path_prepend "$JAVA_HOME/bin"
fi

# ================================== sdkman（存在才 source） ==================================
export SDKMAN_DIR="$HOME/.sdkman"
[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ] && . "$SDKMAN_DIR/bin/sdkman-init.sh"

# ================================== pipx ==================================
path_append "$HOME/.local/bin"

# ================================== Gradle（目录存在才加） ==================================
path_prepend "$HOME/Documents/Gradle/gradle-8.7/bin"

# ================================== JAVA_HOME fallback（仅当未设置时） ==================================
if [ -z "$JAVA_HOME" ]; then
  JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null)"
  export JAVA_HOME
fi
[ -n "$JAVA_HOME" ] && path_prepend "$JAVA_HOME/bin"

# ================================== Android SDK（统一用 ANDROID_SDK_ROOT，防重复） ==================================
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
path_prepend "$ANDROID_SDK_ROOT/platform-tools"
path_prepend "$ANDROID_SDK_ROOT/emulator"
path_prepend "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin"
path_prepend "$ANDROID_SDK_ROOT/tools"
path_prepend "$ANDROID_SDK_ROOT/tools/bin"

# ================================== VSCode CLI（目录存在才加） ==================================
path_prepend "/usr/local/bin"
path_prepend "/opt/homebrew/bin"
path_prepend "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

# ================================== Flutter / Dart（固定路径；不使用 pwd） ==================================
path_prepend "$HOME/flutter/bin"
path_prepend "$HOME/Documents/GitHub.Jobs/Flutter.SDK/Flutter.SDK.last/bin"
export PUB_HOSTED_URL="https://pub.dev"
export FLUTTER_STORAGE_BASE_URL="https://storage.googleapis.com"

# 最后导出 PATH
export PATH
