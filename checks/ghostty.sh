# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 13b. Ghostty config (app settings as code) --------------------------
# ghostty/config is symlinked into ~/.config/ghostty/config (section 1). Here: the repo
# file is valid, no other config file Ghostty loads overrides it, and what Ghostty
# actually loads equals the repo file alone (+show-config with only the repo copy vs the
# real one). Read-only: the comparison copy lives in a temp dir that's removed after.
hdr "Ghostty config"
fixid app-config
GHOSTTY_BIN=/Applications/Ghostty.app/Contents/MacOS/ghostty
G_REPO="$DOTDIR/ghostty/config"
if [ ! -x "$GHOSTTY_BIN" ]; then
  CHECKED=$((CHECKED + 1))
  fixid app-install; warn "Ghostty.app not installed — brew bundle (cask \"ghostty\")"
else
  CHECKED=$((CHECKED + 1))
  if g_val="$(with_timeout 10 "$GHOSTTY_BIN" +validate-config --config-file="$G_REPO" </dev/null 2>&1)"; then
    pass "ghostty/config is valid (ghostty +validate-config)"
  else
    bad "ghostty/config has errors: $(printf '%s' "$g_val" | tr '\n' ' ' | sed 's/[[:space:]]*$//') — fix the repo file"
  fi
  # Ghostty also reads these (Application Support is loaded after ~/.config and wins).
  CHECKED=$((CHECKED + 1))
  g_over=""
  for g_f in "$HOME/Library/Application Support/com.mitchellh.ghostty/config" \
             "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty" \
             "$HOME/.config/ghostty/config.ghostty"; do
    if [ -f "$g_f" ] && grep -Eq '^[[:space:]]*[^#[:space:]]' "$g_f"; then g_over="$g_over ${g_f/#$HOME/~};"; fi
  done
  if [ -n "$g_over" ]; then
    bad "Ghostty also loads${g_over%;} — it overrides the repo config; merge it into ghostty/config, then remove it"
  else
    pass "no other Ghostty config file overrides the repo one"
  fi
  CHECKED=$((CHECKED + 1))
  g_tmp="$(mktemp -d)"
  mkdir -p "$g_tmp/ghostty" && cp "$G_REPO" "$g_tmp/ghostty/config"
  g_eff="$(with_timeout 10 "$GHOSTTY_BIN" +show-config </dev/null 2>/dev/null || true)"
  g_want="$(XDG_CONFIG_HOME="$g_tmp" with_timeout 10 "$GHOSTTY_BIN" +show-config </dev/null 2>/dev/null || true)"
  rm -rf "$g_tmp"
  if [ -z "$g_want" ]; then
    fixid tooling; warn "ghostty +show-config printed nothing — can't compare the effective config"
  elif [ "$g_eff" = "$g_want" ]; then
    pass "Ghostty's effective config = ghostty/config ($(printf '%s\n' "$g_eff" | grep -c .) resolved settings)"
  else
    g_diff="$(diff <(printf '%s\n' "$g_want") <(printf '%s\n' "$g_eff") | grep -E '^[<>]' | head -3 | tr '\n' ' ')"
    bad "Ghostty's effective config differs from ghostty/config (< repo, > loaded): ${g_diff% } — check the symlink and override files"
  fi
fi
