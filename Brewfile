#tap "homebrew/cask"

# Names below are read by scripts/render-app-sources.sh (the README section
# "Where apps come from"). Each entry starts the line with brew, cask, or mas.
# After changing this file, run scripts/render-app-sources.sh.

# ---- Homebrew formulae (brew bundle / brewsync) -------------------------
# If one of these is missing, run brewsync.

# Core CLI
brew "git"
brew "gh"
brew "fish"
brew "mise"
brew "jq"
brew "yq"
brew "ripgrep"
brew "fd"
brew "fzf"
brew "bat"
brew "eza"
brew "tree"
brew "wget"
brew "curl"
brew "direnv"
brew "tmux"
brew "htop"
brew "mas"
brew "dockutil"
brew "duti"
brew "displayplacer"  # built-in display More Space (macos.sh; external displays are not changed)
brew "ykman"
brew "ffmpeg"

# Build/dev basics
brew "pkgconf"
brew "shellcheck"
brew "openssl"
brew "python"
brew "uv"
brew "go"
brew "rustup"
brew "mongosh"
brew "pnpm"

# Cluster tools
brew "awscli"
brew "kubernetes-cli"
brew "helm"

# Secrets (SOPS + age)
brew "sops"
brew "age"

# GNU-ish tools; do not force them to shadow macOS defaults
brew "coreutils"
brew "findutils"
brew "gnu-sed"
brew "gawk"
brew "grep"

# ---- Homebrew casks (brew bundle / brewsync) ----------------------------
# If one of these is missing, run brewsync.
# 1Password desktop is company-managed (lib/mdm-apps.list, Iru Self Service).
# The CLI stays here.

cask "ghostty"
cask "visual-studio-code"
cask "cursor"
cask "cursor-cli"     # Cursor CLI → cursor-agent (not bare agent)
cask "coteditor"
cask "karabiner-elements"
cask "hammerspoon"   # Lua automation (hammerspoon/ → ~/.hammerspoon; Sidecar → Slack, Finder hotkey)
cask "microsoft-teams"
cask "raycast"
cask "1password-cli"  # 1Password CLI (op)
cask "logi-options+"
cask "chatgpt"
cask "claude"
cask "google-gemini"
cask "grok-bot"       # Grok Bot desktop (AI teammates)
cask "grok-build"     # Grok Build terminal coding agent (grok / agent)
cask "google-chrome"
cask "spotify"
cask "sonos"          # Sonos S2 desktop controller
cask "granola"
cask "slack"
cask "acorn"
cask "docker-desktop"
cask "multipass"
cask "cog-app"
cask "kid3"
cask "yubico-authenticator"  # Yubico Authenticator

# ---- Mac App Store -------------------------------------------------------
# No App Store apps currently. This Mac can't sign in with a personal Apple ID.
# brew "mas" above stays: prune-apps.sh uses `mas uninstall`.
# Unwanted App Store apps (GarageBand, iMovie, Pages) are lib/unwanted-apps.list.
# Okta Verify and 1Password desktop are
# lib/mdm-apps.list (Iru Self Service). mas can't upgrade those copies.
