#!/usr/bin/env bash
#
# The README "Where apps come from" section is generated from the Brewfile and
# lib/mdm-apps.list. A missing app's message names that same source.
# 1Password for Safari and Okta Extension App are in neither source.
# Run: ./tests/app-sources.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER="$DIR/scripts/render-app-sources.sh"
README="$DIR/README.md"
# shellcheck source=../lib/join-names.sh disable=SC1091
. "$DIR/lib/join-names.sh"
# shellcheck source=../lib/brew-missing-hint.sh disable=SC1091
. "$DIR/lib/brew-missing-hint.sh"

pass=0
fail=0
eq() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n' "$1" "$2" ;; esac
}
miss() {
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

out="$("$RENDER" --check 2>&1)"; rc=$?
eq "README app-sources section matches the sources" 0 "$rc"
[ "$rc" -eq 0 ] || printf '%s\n' "$out"

section="$(awk '
  $0 == "<!-- BEGIN app-sources -->" { grab = 1; next }
  $0 == "<!-- END app-sources -->" { grab = 0; next }
  grab { print }
' "$README")"

tools="$(sed -nE 's/^brew "([^"]+)".*/\1/p' "$DIR/Brewfile" | join_and)"
casks="$(sed -nE 's/^cask "([^"]+)".*/\1/p' "$DIR/Brewfile" | join_and)"
mas_apps="$(sed -nE 's/^mas "([^"]+)".*/\1/p' "$DIR/Brewfile" | join_and)"
company="$(awk -F'|' '
  /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
  { name = $1; gsub(/^[[:space:]]+|[[:space:]]+$/, "", name); if (name != "") print name }
' "$DIR/lib/mdm-apps.list" | join_and)"

line_of() {
  printf '%s\n' "$section" | awk -v label="$1" 'index($0, label) == 1 { print; exit }'
}
eq "command-line tools match the Brewfile" "**Command-line tools:** ${tools}." "$(line_of '**Command-line tools:**')"
eq "desktop apps match the Brewfile" "**Desktop apps:** ${casks}." "$(line_of '**Desktop apps:**')"
eq "Mac App Store apps match the Brewfile" "**Apps:** ${mas_apps}." "$(line_of '**Apps:**')"

store="$(printf '%s\n' "$section" | awk '
  $0 == "### Mac App Store" { on = 1; next }
  $0 == "### Company apps (Iru Self Service)" { on = 0 }
  on { print }
')"
eq "App Store list is only Keynote and Numbers" "Keynote and Numbers" "$mas_apps"
miss "App Store section does not name 1Password for Safari" "1Password for Safari" "$store"
miss "App Store section does not name Okta Extension" "Okta Extension" "$store"
has "company apps match lib/mdm-apps.list" "**Apps:** ${company}." "$section"
tick='`'
has "Homebrew missing says run brewsync" "run ${tick}brewsync${tick}" "$section"
has "App Store missing needs sign-in" "needs App Store sign-in" "$section"
has "company missing says Iru Self Service" "install it from Iru Self Service" "$section"
has "Safari extensions are called out as unlisted" "1Password for Safari and Okta Extension App are not in any of these lists" "$section"
miss "README does not mention check.sh" "check.sh" "$(cat "$README")"

mas_lines="$(grep -E '^mas ' "$DIR/Brewfile" || true)"
eq "Brewfile mas entries are Keynote and Numbers" 'mas "Keynote", id: 409183694
mas "Numbers", id: 409203825' "$mas_lines"
miss "Brewfile has no 1Password for Safari mas id" "1569813296" "$mas_lines"
miss "Brewfile has no Okta Extension mas id" "1439967473" "$mas_lines"

mdm_data="$(awk 'NF && $0 !~ /^[[:space:]]*#/' "$DIR/lib/mdm-apps.list")"
miss "mdm list has no 1Password for Safari" "1Password for Safari" "$mdm_data"
miss "mdm list has no Okta Extension App" "Okta Extension App" "$mdm_data"
miss "mdm list has no Safari extension id" "1569813296" "$mdm_data"
miss "mdm list has no Okta extension id" "1439967473" "$mdm_data"

app_store="$(awk -F'|' '$1 == "app-store" { print $3; exit }' "$DIR/lib/manual-steps.list")"
has "App Store step names Keynote" "Keynote" "$app_store"
has "App Store step names Numbers" "Numbers" "$app_store"
miss "App Store step does not name 1Password for Safari" "1Password for Safari" "$app_store"
miss "App Store step does not name Okta Extension" "Okta Extension" "$app_store"

has "mdm check names Iru Self Service" "install from Iru Self Service" "$(cat "$DIR/checks/mdm.sh")"
has "brew check names brewsync" "run brewsync" "$(cat "$DIR/checks/brew.sh")"
has "brew check names App Store sign-in" "needs App Store sign-in" "$(cat "$DIR/checks/brew.sh")"
install="$(cat "$DIR/install.sh")"
has "install names brewsync" "run brewsync" "$install"
has "install names App Store sign-in" "needs App Store sign-in" "$install"
miss "install does not name 1Password for Safari" "1Password for Safari" "$install"
miss "install does not name Okta Extension" "Okta Extension" "$install"

sample="$(printf '%s\n' \
  "brew bundle can't satisfy your Brewfile's dependencies." \
  "→ Formula git needs to be installed or updated." \
  "→ Cask ghostty needs to be installed or updated." \
  "→ App Keynote (409183694) needs to be installed or updated.")"
eq "verbose check names both sources" "Homebrew packages (git and ghostty): run brewsync.
Mac App Store apps (Keynote): needs App Store sign-in." "$(brew_missing_hint "$sample")"

only_app='→ App Numbers needs to be installed.'
eq "app-only hint is App Store sign-in" "Mac App Store apps (Numbers): needs App Store sign-in." "$(brew_missing_hint "$only_app")"

three='-> Formula git needs to be installed.
-> Formula gh needs to be updated.
-> Cask slack needs to be installed.'
eq "three Homebrew names use and" "Homebrew packages (git, gh, and slack): run brewsync." "$(brew_missing_hint "$three")"

eq "unparsed verbose output has no hint" "" "$(brew_missing_hint "something else failed")"

printf 'app-sources tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
