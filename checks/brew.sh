# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 2. Homebrew --------------------------------------------------------
hdr "Homebrew (Brewfile)"
fixid brew
CHECKED=$((CHECKED + 1))
# shellcheck source=../lib/brew-missing-hint.sh disable=SC1091
. "$DOTDIR/lib/brew-missing-hint.sh"
if ! command -v brew >/dev/null 2>&1; then
  warn "brew not installed — skipping Brewfile check"
else
  bf_names="$(sed -nE 's/^(brew|cask) "([^"]+)".*/\2/p' "$DOTDIR/Brewfile" | sed -E 's#.*/##' | sort -u)"
  if ! brew bundle check --no-upgrade --file "$DOTDIR/Brewfile" >/dev/null 2>&1; then
    # --no-upgrade => fail only on genuinely MISSING entries, not merely outdated ones.
    bad "Brewfile not satisfied — missing entries:"
    verbose="$(brew bundle check --no-upgrade --file "$DOTDIR/Brewfile" --verbose 2>&1 || true)"
    hint="$(brew_missing_hint "$verbose")"
    if [ -z "$hint" ]; then
      hint="Homebrew packages: run brewsync. Mac App Store apps: needs App Store sign-in."
    fi
    printf '%s\n' "$hint" | sed 's/^/          /'
    printf '%s\n' "$verbose" | sed 's/^/          /' || true
  else
    # The Brewfile pins names, not versions, so a *managed* package being merely
    # outdated is a soft warning (run brewsync), not drift. Match brewsync's env
    # (HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1) so self-updating casks it would never
    # upgrade (Cursor, VS Code, Slack, Gemini, ...) aren't flagged as actionable here.
    outdated="$(HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1 brew outdated --quiet 2>/dev/null | grep -Fxf <(printf '%s\n' "$bf_names") || true)"
    if [ -n "$outdated" ]; then
      warn "all installed; outdated (run brewsync to update): $(printf '%s' "$outdated" | tr '\n' ' ')"
    else
      pass "Brewfile satisfied (all installed and current)"
    fi
  fi
  # Closed-set extras: anything brew bundle cleanup would remove (formulae, casks, MAS)
  # that isn't in the Brewfile. Soft warning only — never auto-zap from macconfig-check.sh.
  # Manual non-brew apps (Cursor Nightly, YouTube Music) never appear here.
  # MDM apps in lib/mdm-apps.list are expected leftovers — filter them out.
  CHECKED=$((CHECKED + 1))
  cleanup="$(brew bundle cleanup --file "$DOTDIR/Brewfile" 2>/dev/null || true)"
  mdm_names=""
  if [ -r "$DOTDIR/lib/mdm-apps.list" ]; then
    mdm_names="$(awk -F'|' '$1 !~ /^#/ && NF {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1}' "$DOTDIR/lib/mdm-apps.list")"
  fi
  if printf '%s\n' "$cleanup" | rg -q 'Would (uninstall|remove)'; then
    extras="$(printf '%s\n' "$cleanup" | MDM_NAMES="$mdm_names" awk '
      BEGIN { mdm=ENVIRON["MDM_NAMES"]; n=split(mdm, a, "\n"); for (i=1;i<=n;i++) if (a[i]!="") skip[a[i]]=1 }
      /^Would / {grab=1; next}
      /^Run / {grab=0}
      grab && NF {
        line=$0; gsub(/^[[:space:]]+/, "", line)
        name=line; sub(/ \(.*/, "", name)
        if (!(name in skip)) print line
      }
    ' | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    if [ -n "$extras" ]; then
      warn "Brewfile extras (add to Brewfile or uninstall): $extras"
    else
      pass "no undeclared brew/cask/mas extras (MDM apps ignored)"
    fi
  else
    pass "no undeclared brew/cask/mas extras"
  fi
fi
