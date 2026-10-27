#!/usr/bin/env bash
#
# The README names the three places apps come from. It does not list the apps,
# and it does not give an exact count of manual steps.
# 1Password for Safari and Okta Extension App are in neither the Brewfile nor
# lib/mdm-apps.list.
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
eq "README app-sources note matches the sources" 0 "$rc"
[ "$rc" -eq 0 ] || printf '%s\n' "$out"

section="$(awk '
  $0 == "<!-- BEGIN app-sources -->" { grab = 1; next }
  $0 == "<!-- END app-sources -->" { grab = 0; next }
  grab { print }
' "$README")"

mas_apps="$(sed -nE 's/^mas "([^"]+)".*/\1/p' "$DIR/Brewfile" | join_and)"
eq "Brewfile has no Mac App Store apps" "" "$mas_apps"
has "note names Homebrew" "Homebrew, via the Brewfile, for most apps and command-line tools." "$section"
has "note names Fleet Self service" "Fleet Self service, for company-managed apps that can't be installed unattended. Setup prompts you to install them." "$section"
has "note says nothing comes from the Mac App Store" "Nothing is installed from it now" "$section"
has "note explains the Apple ID limit" "can't sign in with a personal Apple ID" "$section"
miss "note is not a dedicated section" "## Where apps come from" "$section"
miss "note does not list command-line tools" "**Command-line tools:**" "$section"
miss "note does not list desktop apps" "**Desktop apps:**" "$section"
miss "note does not list apps" "**Apps:**" "$section"
miss "note does not name a Homebrew cask" "ghostty" "$section"
miss "note does not name a company app" "Okta Verify" "$section"
miss "note does not ask for sign-in" "App Store sign-in" "$section"
miss "note does not name 1Password for Safari" "1Password for Safari" "$section"
miss "note does not name Okta Extension" "Okta Extension" "$section"
miss "README does not mention check.sh" "check.sh" "$(cat "$README")"

# An exact integer count would go stale each time a step is added. The README
# says "up to about 40" / "about 10" instead, and this test must not require a
# particular integer.
readme="$(cat "$README")"
has "README approximates the manual-step count" "up to about 40" "$readme"
has "README says fewer steps are usually open" "Usually far fewer are still open" "$readme"
has "README approximates the by-eye count" "about 10 you confirm by eye" "$readme"
has "README says to wait for the Homebrew paste" "wait for it to finish" "$readme"
has "README says bootstrap offers the walk-through" "offers to walk you through them" "$readme"
has "README keeps later commands for a re-run" "go through them again later" "$readme"
miss "README leaves the run-log example to the setup doc" "install-20260101-120000.log" "$readme"
exact="$(printf '%s\n' "$readme" | grep -E '[0-9]+ (manual steps|settings) have to be set by hand|[0-9]+ you confirm by eye|[0-9]+ steps you set by hand' | grep -vi 'about ' || true)"
eq "README does not pin an exact manual-step count" "" "$exact"

# The Homebrew installer reads the rest of a paste, so it has its own fence.
# The next fence starts by putting brew on PATH, then installs gh.
bash_fence() {
  awk -v want="$1" '
    $0 == "```bash" { n++; capture = 1; next }
    $0 == "```" && capture { capture = 0; next }
    capture && n == want { print }
  ' "$README"
}
first_paste="$(bash_fence 1)"
second_paste="$(bash_fence 2)"
has "first paste is the Homebrew installer" "Homebrew/install/HEAD/install.sh" "$first_paste"
miss "first paste stops before gh" "brew install gh" "$first_paste"
eq "second paste puts brew on PATH first" 'eval "$(/opt/homebrew/bin/brew shellenv)"' \
  "$(printf '%s\n' "$second_paste" | head -n 1)"
has "second paste installs gh" "brew install gh" "$second_paste"
has "second paste runs bootstrap" "~/.dotfiles-mac/bootstrap.sh" "$second_paste"

mas_brew="$(mktemp)"
printf '%s\n' 'mas "Example Store App", id: 1' > "$mas_brew"
mas_note="$(APP_SOURCES_BREWFILE="$mas_brew" "$RENDER" --stdout)"
has "a Mac App Store line is described in general" "Brewfile installs with" "$mas_note"
miss "a Mac App Store line is not listed by name" "Example Store App" "$mas_note"
miss "a Mac App Store line does not say nothing is installed" "Nothing is installed from the Mac App Store now" "$mas_note"
rm -f "$mas_brew"

has "setup still explains the unlisted Safari extensions" \
  "1Password for Safari and Okta Extension App are not in the Brewfile" \
  "$(cat "$DIR/docs/setup.md")"

mas_lines="$(grep -E '^mas ' "$DIR/Brewfile" || true)"
eq "Brewfile has no mas installs" "" "$mas_lines"
miss "Brewfile has no 1Password for Safari mas id" "1569813296" "$mas_lines"
miss "Brewfile has no Okta Extension mas id" "1439967473" "$mas_lines"

mdm_data="$(awk 'NF && $0 !~ /^[[:space:]]*#/' "$DIR/lib/mdm-apps.list")"
miss "mdm list has no 1Password for Safari" "1Password for Safari" "$mdm_data"
miss "mdm list has no Okta Extension App" "Okta Extension App" "$mdm_data"
miss "mdm list has no Safari extension id" "1569813296" "$mdm_data"
miss "mdm list has no Okta extension id" "1439967473" "$mdm_data"

eq "no app-store manual step" "" \
  "$(awk -F'|' '$1 == "app-store" { print $1; exit }' "$DIR/lib/manual-steps.list")"
miss "manual steps do not ask for App Store sign-in" "App Store sign-in" \
  "$(grep -v '^[[:space:]]*#' "$DIR/lib/manual-steps.list" || true)"

mdm_src="$(cat "$DIR/checks/mdm.sh" "$DIR/lib/fleet-apps.sh")"
has "mdm check names Fleet Self service" "install from Fleet Self service" "$mdm_src"
has "mdm check offers Fleet Self service" "Open Fleet Self service to install them now? [Y/n]" "$mdm_src"
has "mdm check does not treat a missing app as drift" "warn" "$(cat "$DIR/lib/fleet-apps.sh")"
miss "mdm check does not call bad for a missing app" "bad " "$(cat "$DIR/checks/mdm.sh")"
has "brew check names brewsync" "run brewsync" "$(cat "$DIR/checks/brew.sh")"
miss "brew check does not ask for App Store sign-in" "App Store sign-in" "$(cat "$DIR/checks/brew.sh")"
install="$(cat "$DIR/install.sh")"
has "install names brewsync" "run brewsync" "$install"
miss "install does not ask for App Store sign-in" "App Store sign-in" "$install"
miss "install does not open the App Store" "macappstore://" "$install"
miss "install does not name 1Password for Safari" "1Password for Safari" "$install"
miss "install does not name Okta Extension" "Okta Extension" "$install"

sample="$(printf '%s\n' \
  "brew bundle can't satisfy your Brewfile's dependencies." \
  "→ Formula git needs to be installed or updated." \
  "→ Cask ghostty needs to be installed or updated." \
  "→ App Example (1) needs to be installed or updated.")"
eq "verbose check names Homebrew only" "Homebrew packages (git and ghostty): run brewsync." "$(brew_missing_hint "$sample")"

only_app='→ App Example needs to be installed.'
eq "an App line is not a sign-in hint" "" "$(brew_missing_hint "$only_app")"

three='-> Formula git needs to be installed.
-> Formula gh needs to be updated.
-> Cask slack needs to be installed.'
eq "three Homebrew names use and" "Homebrew packages (git, gh, and slack): run brewsync." "$(brew_missing_hint "$three")"

eq "unparsed verbose output has no hint" "" "$(brew_missing_hint "something else failed")"

printf 'app-sources tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
