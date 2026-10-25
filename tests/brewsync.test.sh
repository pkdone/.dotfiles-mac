#!/usr/bin/env bash
#
# brewsync: a bundle step that stops before it can name packages is reported,
# with the log path, and upgrade/cleanup still run. The function then exits
# non-zero. A normal "some entries are missing" result is a different message.
# Run: ./tests/brewsync.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FISH_FN="$DIR/fish/functions/brewsync.fish"

pass=0
fail=0
eq() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}
miss() {
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;;
    *) pass=$((pass + 1)) ;; esac
}

if [ ! -f "$FISH_FN" ]; then
  echo "FAIL: $FISH_FN missing"
  exit 1
fi

if ! command -v fish >/dev/null 2>&1; then
  echo "fish not installed — skipped brewsync run (CI fish-syntax job still parses *.fish)"
  echo "brewsync tests: 0 passed, 0 failed"
  exit 0
fi

fish_err="$(fish -n "$FISH_FN" 2>&1)"
fish_rc=$?
eq "fish -n brewsync.fish" "0" "$fish_rc"
eq "fish -n prints nothing" "" "$fish_err"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"
bin="$tmp/bin"
mkdir -p "$home/.dotfiles-mac/lib" "$home/.dotfiles-mac/scripts" "$bin"
cp "$DIR/lib/dotfiles-log.sh" "$home/.dotfiles-mac/lib/dotfiles-log.sh"

cat > "$home/.dotfiles-mac/scripts/brew-bundle-install.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "bundle-stub rc=${BUNDLE_RC:-3}"
if [ "${BUNDLE_RC:-3}" = 1 ]; then
  echo "⚠️  1 Brewfile entry is still missing:"
  echo "  raycast (cask)"
fi
if [ "${BUNDLE_RC:-3}" = 2 ]; then
  echo "Can't reach github.com, which Homebrew needs to download packages."
fi
exit "${BUNDLE_RC:-3}"
EOF
cat > "$bin/brew" <<'EOF'
#!/bin/sh
printf 'brew %s\n' "$*"
exit 0
EOF
chmod +x "$home/.dotfiles-mac/scripts/brew-bundle-install.sh" "$bin/brew"

run_brewsync() {
  HOME="$home" PATH="$bin:/usr/bin:/bin" BUNDLE_RC="$1" \
    fish --no-config -c "source \"$FISH_FN\"; brewsync; echo STATUS:\$status"
}

out="$(run_brewsync 3)"
rc=$?
eq "fish wrapper exits 0 after printing status" 0 "$rc"
has "crash says the install failed" "The Brewfile install failed before it could finish. No missing package was named." "$out"
has "crash names the log path" "The log for this run is $home/Library/Logs/dotfiles/brewsync-" "$out"
has "crash repeats the log path at the end" "The log is $home/Library/Logs/dotfiles/brewsync-" "$out"
has "outer wrapper prints the log" "Log: $home/Library/Logs/dotfiles/brewsync-" "$out"
has "crash still updates" "brew update" "$out"
has "crash still upgrades" "brew upgrade" "$out"
has "crash still cleans up" "brew cleanup" "$out"
has "crash still autoremoves" "brew autoremove" "$out"
has "crash still runs doctor" "brew doctor" "$out"
has "crash exits non-zero" "STATUS:3" "$out"
miss "crash does not say entries are still missing" "still missing" "$out"

out="$(run_brewsync 1)"
has "named misses stay a missing-entries result" "Some Brewfile entries are still missing" "$out"
has "named misses still upgrade" "brew update" "$out"
has "named misses exit 1" "STATUS:1" "$out"
miss "named misses are not a crashed install" "failed before it could finish" "$out"

out="$(run_brewsync 2)"
has "preflight failure skips upgrade" "Skipping upgrade and cleanup because the checks above failed." "$out"
has "preflight failure exits 2" "STATUS:2" "$out"
miss "preflight failure does not upgrade" "brew update" "$out"
miss "preflight failure is not the crash message" "failed before it could finish" "$out"

printf 'brewsync tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
