#tap "homebrew/cask"

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

# GUI apps
cask "ghostty"
cask "visual-studio-code"
cask "cursor"
cask "coteditor"
cask "karabiner-elements"
cask "microsoft-teams"
cask "raycast"
cask "logi-options+"
cask "chatgpt"
cask "claude"
cask "google-gemini"
cask "google-chrome"
cask "spotify"
cask "granola"
cask "slack"
cask "acorn"
cask "docker-desktop"
cask "multipass"
cask "cog-app"
cask "kid3"

# Mac App Store (via mas; requires being signed in to the App Store).
# Wanted apps live here; unwanted ones (GarageBand/iMovie/Pages) are in lib/unwanted-apps.list.
mas "WhatsApp", id: 310633997
# Okta Verify is Kandji/MDM (see lib/mdm-apps.list) — mas can't upgrade it.
mas "Okta Extension App", id: 1439967473
mas "1Password for Safari", id: 1569813296
# Apple iWork kept installed (not pruned); declare so brew bundle cleanup stays clean.
mas "Keynote", id: 409183694
mas "Numbers", id: 409203825

