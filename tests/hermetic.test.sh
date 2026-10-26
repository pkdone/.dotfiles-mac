#!/usr/bin/env bash
#
# The safe PATH hides host commands even when they sit earlier on the
# inherited PATH. The configured-Mac stubs answer as a machine that is
# already set up, so a test that falls through to $PATH cannot pass by
# accident on Linux.
# Run: ./tests/hermetic.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"

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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
safe="$(hermetic_safe_root)"
eq "safe path is a directory" "dir" "$([ -d "$safe" ] && echo dir || echo missing)"
eq "safe path provides awk" "awk" "$(PATH="$safe" command -v awk >/dev/null && echo awk || echo missing)"

decoy="$tmp/decoy"
mkdir -p "$decoy"
cat > "$decoy/lpstat" <<'EOF'
#!/bin/sh
printf '%s\n' "printer HP_ENVY_6000_series is idle"
exit 0
EOF
chmod +x "$decoy/lpstat"
found="$(PATH="$decoy:$PATH" command -v lpstat || true)"
eq "a planted lpstat is what an inherited PATH would run" "$decoy/lpstat" "$found"
closed="$(PATH="$safe" command -v lpstat || true)"
eq "the safe path does not see a planted lpstat" "" "$closed"
for cmd in pmset system_profiler displayplacer sfltool shortcuts dscl defaults ioreg osascript open; do
  hit="$(PATH="$safe" command -v "$cmd" || true)"
  eq "the safe path hides $cmd" "" "$hit"
done

conf="$(hermetic_configured_root "$tmp/configured")"
printer="$(PATH="$conf:$safe" lpstat -p)"
has "configured lpstat names the home printer" "HP_ENVY_6000" "$printer"
power="$(PATH="$conf:$safe" pmset -g custom)"
has "configured pmset has AC sleep 0" "sleep                0" "$power"
short="$(PATH="$conf:$safe" shortcuts list)"
has "configured shortcuts list Mode WebConf On" "Mode WebConf On" "$short"
eq "configured brightness stub is executable" "yes" \
  "$([ -x "$conf/corebrightnessdiag" ] && echo yes || echo no)"

# BTM_DIR is the only way to keep --karabiner off the real database.
# A store file that is not a plist is parsed, so the message says
# "Invalid file". The default directory is not consulted: on Linux that
# directory is missing and the message would not mention a bad file, and
# on a Mac it would be the real login-item database.
mkdir -p "$tmp/btm"
printf 'not a plist\n' > "$tmp/btm/BackgroundItems-v9.btm"
btm="$(BTM_DIR="$tmp/btm" PATH="$safe" python3 "$DIR/lib/btm-login-items.py" --karabiner 2>&1 || true)"
has "BTM_DIR is the store that was read" "Invalid file" "$btm"

has "display check uses the same diag override as bootstrap" \
  'AUTO_BRIGHTNESS_DIAG:-/usr/libexec/corebrightnessdiag' "$(cat "$DIR/checks/display.sh")"

printf 'hermetic tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
