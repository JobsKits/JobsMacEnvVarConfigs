grep -Fq 'export PATH="$(brew --prefix ruby)/bin:$PATH"' ~/.zprofile \
  || echo 'export PATH="$(brew --prefix ruby)/bin:$PATH"' >> ~/.zprofile

# === Homebrew Ruby PATH (zsh login) ===
if command -v brew >/dev/null 2>&1; then
  ruby_prefix="$(brew --prefix ruby 2>/dev/null || true)"
  if [[ -n "$ruby_prefix" && -d "$ruby_prefix/bin" ]]; then
    case ":$PATH:" in
      *":$ruby_prefix/bin:"*) ;;
      *) export PATH="$ruby_prefix/bin:$PATH" ;;
    esac
  fi
fi
