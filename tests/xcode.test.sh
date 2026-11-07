#!/usr/bin/env bash
#
# Full Xcode is checked and not installed. A Command Line Tools developer
# directory is drift. The licence and first launch are read, never accepted
# and never run. xcode-select, xcodebuild, and sudo are stubs.
# Run: ./tests/xcode.test.sh
#
# SC2317: pass/bad/warn/fixid inside run() are the stubs the sourced
# checks call. Shellcheck does not follow those calls.
# SC2030/SC2031: each run is its own subshell; the exports do not leak.
# SC2034: CHECKED and MACCONFIG_CHECKS_DEFINE_ONLY are read by the sourced file.
# shellcheck disable=SC2317,SC2030,SC2031,SC2034
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
CHECKS="$DIR/checks/apps.sh"
LIST="$DIR/lib/manual-steps.list"
AUTO="$DIR/lib/autofix.list"

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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin" "$tmp/home"
SAFE="$(hermetic_safe_root)"
PY="$(PATH="$SAFE" command -v python3 || true)"
if [ -z "$PY" ]; then echo "xcode tests: python3 not found, skipped"; exit 0; fi

XCODE_CALL_LOG="$tmp/calls.log"
XCODE_SELECT_OUT="/Library/Developer/CommandLineTools"
XCODE_SELECT_RC=0
XCODE_FIRST_OUT=""
XCODE_FIRST_RC=0
XCODE_APP_PATH="$tmp/no-such-xcode.app"
XCODE_LICENSE_PLIST="$tmp/license.plist"
export XCODE_CALL_LOG XCODE_SELECT_OUT XCODE_SELECT_RC XCODE_FIRST_OUT XCODE_FIRST_RC
export XCODE_APP_PATH XCODE_LICENSE_PLIST
: > "$XCODE_CALL_LOG"

cat > "$bin/xcode-select" <<'EOF'
#!/bin/sh
printf '%s\n' "xcode-select $*" >> "${XCODE_CALL_LOG:?}"
if [ "${1:-}" = "-p" ] && [ "$#" -eq 1 ]; then
  if [ -n "${XCODE_SELECT_OUT:-}" ]; then
    printf '%s\n' "$XCODE_SELECT_OUT"
  fi
  exit "${XCODE_SELECT_RC:-0}"
fi
printf '%s\n' "bad xcode-select: $*" >&2
exit 99
EOF
cat > "$bin/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "sudo $*" >> "${XCODE_CALL_LOG:?}"
exit 99
EOF
cat > "$bin/mas" <<'EOF'
#!/bin/sh
printf '%s\n' "mas $*" >> "${XCODE_CALL_LOG:?}"
exit 99
EOF
chmod +x "$bin/xcode-select" "$bin/sudo" "$bin/mas"

write_app() { # version bundle-id
  "$PY" - "$XCODE_APP_PATH" "$1" "$2" <<'PY'
import os, plistlib, sys
root, version, bundle = sys.argv[1:]
os.makedirs(os.path.join(root, "Contents"), exist_ok=True)
plistlib.dump(
    {"CFBundleIdentifier": bundle, "CFBundleShortVersionString": version},
    open(os.path.join(root, "Contents", "Info.plist"), "wb"),
)
plistlib.dump(
    {"CFBundleShortVersionString": version},
    open(os.path.join(root, "Contents", "version.plist"), "wb"),
)
PY
  mkdir -p "$XCODE_APP_PATH/Contents/Developer/usr/bin"
  cat > "$XCODE_APP_PATH/Contents/Developer/usr/bin/xcodebuild" <<'EOF'
#!/bin/sh
printf '%s\n' "xcodebuild $*" >> "${XCODE_CALL_LOG:?}"
if [ "${1:-}" = "-checkFirstLaunchStatus" ] && [ "$#" -eq 1 ]; then
  if [ -n "${XCODE_FIRST_OUT:-}" ]; then
    printf '%s\n' "$XCODE_FIRST_OUT"
  fi
  exit "${XCODE_FIRST_RC:-0}"
fi
printf '%s\n' "bad xcodebuild: $*" >&2
exit 99
EOF
  chmod +x "$XCODE_APP_PATH/Contents/Developer/usr/bin/xcodebuild"
}

write_license() { # agreed version, or empty to omit the key
  "$PY" - "$XCODE_LICENSE_PLIST" "$1" <<'PY'
import os, plistlib, sys
path, agreed = sys.argv[1:]
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {}
if agreed:
    data["IDEXcodeVersionForAgreedToGMLicense"] = agreed
plistlib.dump(data, open(path, "wb"))
PY
}

reset_case() {
  : > "$XCODE_CALL_LOG"
  XCODE_SELECT_OUT="/Library/Developer/CommandLineTools"
  XCODE_SELECT_RC=0
  XCODE_FIRST_OUT=""
  XCODE_FIRST_RC=0
  XCODE_APP_PATH="$tmp/Xcode.app"
  XCODE_LICENSE_PLIST="$tmp/license.plist"
  rm -rf "$XCODE_APP_PATH" "$XCODE_LICENSE_PLIST"
}

run_checks() {
  local rc=0
  out="$(
    set -euo pipefail
    export DOTDIR="$DIR" DOT_PYTHON="$PY" PATH="$bin:$SAFE"
    export XCODE_APP_PATH XCODE_LICENSE_PLIST XCODE_CALL_LOG
    export XCODE_SELECT_OUT XCODE_SELECT_RC XCODE_FIRST_OUT XCODE_FIRST_RC
    CHECKED=0
    pass() { printf 'pass|%s\n' "$1"; }
    bad() { printf 'bad|%s\n' "$1"; }
    warn() { printf 'warn|%s\n' "$1"; }
    fixid() { printf 'fixid|%s\n' "$1"; }
    hdr() { printf 'hdr|%s\n' "$1"; }
    info() { :; }
    note() { :; }
    skip() { :; }
    with_timeout() { shift; "$@"; }
    MACCONFIG_CHECKS_DEFINE_ONLY=1
    # shellcheck source=../checks/apps.sh disable=SC1091
    . "$DIR/checks/apps.sh"
    check_step_xcode_app
    check_step_xcode_select
    check_step_xcode_license
    check_step_xcode_first_launch
  )" || rc=$?
  RUN_RC=$rc
  RUN_OUT="$out"
}

status_n() {
  printf '%s\n' "$1" | awk -F'|' -v n="$2" '
    $1=="pass" || $1=="bad" || $1=="warn" { c++; if (c==n) { print $1; exit } }
  '
}
msg_n() {
  printf '%s\n' "$1" | awk -F'|' -v n="$2" '
    $1=="pass" || $1=="bad" || $1=="warn" {
      c++
      if (c==n) { print substr($0, length($1)+2); exit }
    }
  '
}
tag_n() {
  printf '%s\n' "$1" | awk -F'|' -v n="$2" '
    $1=="fixid" { tag=$2; next }
    $1=="pass" || $1=="bad" || $1=="warn" {
      c++
      if (c==n) { print tag; exit }
    }
  '
}

# ---- list, rung, and the setters ----------------------------------------
eq "xcode is report-only" "PAUL|" \
  "$(awk -F'|' '$1=="xcode" { print $2 "|" $3; exit }' "$AUTO")"
has "the section tags xcode" "fixid xcode" "$(cat "$CHECKS")"
has "the section heading is Xcode" 'hdr "Xcode"' "$(cat "$CHECKS")"
for id in xcode-app xcode-select xcode-license xcode-first-launch; do
  eq "$id is checked by the apps section" "@macconfig:apps" \
    "$(awk -F'|' -v id="$id" '$1==id { print $6; exit }' "$LIST")"
  eq "$id is in the Xcode group" "Xcode" \
    "$(awk -F'|' -v id="$id" '$1==id { print $2; exit }' "$LIST")"
done
eq "install step opens the Mac App Store" "macappstore://apps.apple.com/app/id497799835" \
  "$(awk -F'|' '$1=="xcode-app" { print $5; exit }' "$LIST")"
eq "select step names the hand command" \
  "Terminal, yourself: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" \
  "$(awk -F'|' '$1=="xcode-select" { print $4; exit }' "$LIST")"
eq "licence step names the hand command" \
  "Open Xcode and accept the licence, or in a terminal yourself: sudo xcodebuild -license accept" \
  "$(awk -F'|' '$1=="xcode-license" { print $4; exit }' "$LIST")"
eq "first launch step names the hand command" \
  "Open Xcode once and let the first launch finish, or in a terminal yourself: sudo xcodebuild -runFirstLaunch" \
  "$(awk -F'|' '$1=="xcode-first-launch" { print $4; exit }' "$LIST")"

code="$(grep -v '^[[:space:]]*#' "$CHECKS")"
eq "one first-launch status read" 1 "$(printf '%s\n' "$code" | grep -c -- '-checkFirstLaunchStatus 2>&1')"
eq "one developer-directory read" 1 "$(printf '%s\n' "$code" | grep -c 'with_timeout 10 xcode-select -p')"
miss "the check does not call mas" "mas " "$code"
has "drift names the select command" "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" "$code"
has "drift names licence acceptance" "sudo xcodebuild -license accept" "$code"
has "drift names first launch" "sudo xcodebuild -runFirstLaunch" "$code"

for f in bootstrap.sh install.sh macos.sh dock.sh shell.sh handlers.sh hostname.sh prune-apps.sh lib/safe-fixers.sh lib/brew-bundle.sh; do
  text="$(cat "$DIR/$f")"
  miss "$f does not mas-install Xcode" "mas install" "$text"
  miss "$f does not select the developer directory" "xcode-select -s" "$text"
  miss "$f does not accept the Xcode licence" "xcodebuild -license" "$text"
  miss "$f does not run first launch" "runFirstLaunch" "$text"
done
pre="$(awk '/^brew_preflight_clt\(\)/,/^}/' "$DIR/lib/brew-bundle.sh")"
has "Homebrew preflight still offers the Command Line Tools" "xcode-select --install" "$pre"
miss "Homebrew preflight does not require the Xcode app" "Xcode.app" "$pre"

# ---- Command Line Tools only --------------------------------------------
reset_case
XCODE_APP_PATH="$tmp/no-such-xcode.app"
run_checks
eq "CLT-only check exits 0" 0 "$RUN_RC"
eq "CLT-only app is drift" bad "$(status_n "$RUN_OUT" 1)"
eq "CLT-only developer directory is drift" bad "$(status_n "$RUN_OUT" 2)"
eq "CLT-only licence is drift" bad "$(status_n "$RUN_OUT" 3)"
eq "CLT-only first launch is drift" bad "$(status_n "$RUN_OUT" 4)"
eq "CLT-only app tag" xcode "$(tag_n "$RUN_OUT" 1)"
has "missing app is not full Xcode" "Command Line Tools are not full Xcode" "$(msg_n "$RUN_OUT" 1)"
has "developer directory names Command Line Tools" \
  "/Library/Developer/CommandLineTools (Command Line Tools, not full Xcode)" \
  "$(msg_n "$RUN_OUT" 2)"
has "licence says Command Line Tools do not use it" "Command Line Tools do not use this licence" "$(msg_n "$RUN_OUT" 3)"
has "first launch says Command Line Tools are not finished Xcode" \
  "Command Line Tools are not a finished Xcode" "$(msg_n "$RUN_OUT" 4)"
miss "CLT-only does not say first launch is done" "first launch is done" "$RUN_OUT"
eq "CLT-only only reads the developer directory" "xcode-select -p" "$(cat "$XCODE_CALL_LOG")"
miss "CLT-only does not run xcodebuild" "xcodebuild" "$(cat "$XCODE_CALL_LOG")"
miss "CLT-only does not run sudo" "sudo " "$(cat "$XCODE_CALL_LOG")"
miss "CLT-only does not run mas" "mas " "$(cat "$XCODE_CALL_LOG")"

# ---- app installed, developer directory still the Command Line Tools -----
reset_case
write_app 16.2 com.apple.dt.Xcode
write_license 16.0
run_checks
eq "installed app passes while the directory is still the tools" pass "$(status_n "$RUN_OUT" 1)"
eq "installed app with the tools directory is drift" bad "$(status_n "$RUN_OUT" 2)"
eq "licence can pass before the directory is switched" pass "$(status_n "$RUN_OUT" 3)"
eq "first launch stays drift while the tools are selected" bad "$(status_n "$RUN_OUT" 4)"
has "a point release matches the agreed major" "major version 16 (installed 16.2, agreed 16.0)" "$(msg_n "$RUN_OUT" 3)"
has "first launch names the tools directory" \
  "Command Line Tools, not full Xcode" "$(msg_n "$RUN_OUT" 4)"
miss "tools directory does not run xcodebuild" "xcodebuild" "$(cat "$XCODE_CALL_LOG")"
miss "tools directory does not switch it" "xcode-select -s" "$(cat "$XCODE_CALL_LOG")"

# ---- full Xcode selected, licensed, and launched ------------------------
reset_case
write_app 16.2 com.apple.dt.Xcode
write_license 16.2
XCODE_SELECT_OUT="$XCODE_APP_PATH/Contents/Developer"
run_checks
eq "ready app passes" pass "$(status_n "$RUN_OUT" 1)"
eq "ready directory passes" pass "$(status_n "$RUN_OUT" 2)"
eq "ready licence passes" pass "$(status_n "$RUN_OUT" 3)"
eq "ready first launch passes" pass "$(status_n "$RUN_OUT" 4)"
has "ready directory says full Xcode" "full Xcode" "$(msg_n "$RUN_OUT" 2)"
miss "ready directory is not described as the tools" "Command Line Tools" "$(msg_n "$RUN_OUT" 2)"
has "ready first launch is done" "Xcode first launch is done" "$(msg_n "$RUN_OUT" 4)"
eq "ready probe is only the status check" "xcodebuild -checkFirstLaunchStatus" \
  "$(grep '^xcodebuild ' "$XCODE_CALL_LOG")"
miss "ready run does not accept the licence" "license" "$(cat "$XCODE_CALL_LOG")"
miss "ready run does not run first launch" "runFirstLaunch" "$(cat "$XCODE_CALL_LOG")"
miss "ready run does not use sudo" "sudo " "$(cat "$XCODE_CALL_LOG")"

# ---- selected Xcode, old licence, first launch still pending -------------
reset_case
write_app 16.2 com.apple.dt.Xcode
write_license 15.4
XCODE_SELECT_OUT="$XCODE_APP_PATH/Contents/Developer"
XCODE_FIRST_RC=1
run_checks
eq "old licence is drift" bad "$(status_n "$RUN_OUT" 3)"
eq "pending first launch is drift" bad "$(status_n "$RUN_OUT" 4)"
has "old licence names both versions" "installed 16.2, agreed 15.4" "$(msg_n "$RUN_OUT" 3)"
miss "pending first launch is not the tools" "Command Line Tools" "$(msg_n "$RUN_OUT" 4)"
eq "pending probe is only the status check" "xcodebuild -checkFirstLaunchStatus" \
  "$(grep '^xcodebuild ' "$XCODE_CALL_LOG")"

# ---- xcodebuild reports a tools instance even if the path matched --------
reset_case
write_app 16.2 com.apple.dt.Xcode
write_license 16.2
XCODE_SELECT_OUT="$XCODE_APP_PATH/Contents/Developer"
XCODE_FIRST_OUT="xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance"
XCODE_FIRST_RC=1
run_checks
eq "a tools reply is drift" bad "$(status_n "$RUN_OUT" 4)"
has "a tools reply says Command Line Tools" "Command Line Tools, not full Xcode" "$(msg_n "$RUN_OUT" 4)"

# ---- other failures ------------------------------------------------------
reset_case
write_app 16.2 com.example.NotXcode
XCODE_SELECT_OUT="$XCODE_APP_PATH/Contents/Developer"
run_checks
eq "wrong bundle is drift" bad "$(status_n "$RUN_OUT" 1)"
has "wrong bundle names the id" "bundle id com.example.NotXcode" "$(msg_n "$RUN_OUT" 1)"

reset_case
mkdir -p "$XCODE_APP_PATH/Contents"
run_checks
eq "app without a bundle id is drift" bad "$(status_n "$RUN_OUT" 1)"
has "missing bundle id is named" "no bundle id" "$(msg_n "$RUN_OUT" 1)"

reset_case
write_app 16.2 com.apple.dt.Xcode
write_license ""
XCODE_SELECT_OUT="$XCODE_APP_PATH/Contents/Developer"
run_checks
eq "missing licence key is drift" bad "$(status_n "$RUN_OUT" 3)"
has "missing licence key says nothing was agreed" "agreed nothing" "$(msg_n "$RUN_OUT" 3)"

reset_case
write_app 16.2 com.apple.dt.Xcode
mkdir -p "$XCODE_LICENSE_PLIST"
XCODE_SELECT_OUT="$XCODE_APP_PATH/Contents/Developer"
run_checks
eq "unreadable licence is a warning" warn "$(status_n "$RUN_OUT" 3)"
eq "unreadable licence is tooling" tooling "$(tag_n "$RUN_OUT" 3)"

reset_case
write_app 16.2 com.apple.dt.Xcode
write_license 16.2
XCODE_SELECT_OUT="$XCODE_APP_PATH/Contents/Developer"
XCODE_FIRST_RC=142
run_checks
eq "a status check that does not finish is a warning" warn "$(status_n "$RUN_OUT" 4)"
eq "a hung status check is tooling" tooling "$(tag_n "$RUN_OUT" 4)"

reset_case
write_app 16.2 com.apple.dt.Xcode
mv "$bin/xcode-select" "$bin/xcode-select.off"
run_checks
mv "$bin/xcode-select.off" "$bin/xcode-select"
eq "missing xcode-select does not pass the directory" warn "$(status_n "$RUN_OUT" 2)"
eq "missing xcode-select is tooling" tooling "$(tag_n "$RUN_OUT" 2)"
eq "missing xcode-select does not pass first launch" warn "$(status_n "$RUN_OUT" 4)"
# The app is real, so that line still passes. The directory was not read.
eq "missing xcode-select still sees the app" pass "$(status_n "$RUN_OUT" 1)"
eq "missing xcode-select ran nothing" "" "$(cat "$XCODE_CALL_LOG")"

reset_case
write_app 16.2 com.apple.dt.Xcode
XCODE_SELECT_OUT=""
XCODE_SELECT_RC=0
run_checks
eq "an empty developer directory is a warning" warn "$(status_n "$RUN_OUT" 2)"
has "an empty read says nothing came back" "returned nothing" "$(msg_n "$RUN_OUT" 2)"

# Sourcing the definitions does not read the machine.
reset_case
: > "$XCODE_CALL_LOG"
(
  set -euo pipefail
  export DOTDIR="$DIR" DOT_PYTHON="$PY" PATH="$bin:$SAFE" XCODE_CALL_LOG
  MACCONFIG_CHECKS_DEFINE_ONLY=1
  # shellcheck source=../checks/apps.sh disable=SC1091
  . "$DIR/checks/apps.sh"
)
eq "defining the checks runs nothing" "" "$(cat "$XCODE_CALL_LOG")"

# ---- macconfig --only apps on a Command Line Tools machine ---------------
reset_case
XCODE_APP_PATH="$tmp/no-such-xcode.app"
XCODE_SELECT_OUT="/Library/Developer/CommandLineTools"
int_rc=0
int_out="$(
  HOME="$tmp/home" PATH="$bin:$SAFE" NO_COLOR=1 \
    XCODE_APP_PATH="$XCODE_APP_PATH" XCODE_LICENSE_PLIST="$XCODE_LICENSE_PLIST" \
    XCODE_CALL_LOG="$XCODE_CALL_LOG" XCODE_SELECT_OUT="$XCODE_SELECT_OUT" \
    XCODE_SELECT_RC=0 XCODE_FIRST_RC=0 \
    "$DIR/macconfig-check.sh" --no-color --only apps 2>"$tmp/int.err"
)" || int_rc=$?
eq "macconfig on Command Line Tools exits 1" 1 "$int_rc"
eq "macconfig stderr stays empty" "" "$(cat "$tmp/int.err")"
has "macconfig prints the Xcode heading" "Xcode" "$int_out"
has "macconfig names the missing app" "Full Xcode is not installed" "$int_out"
has "macconfig names the Command Line Tools directory" \
  "Command Line Tools, not full Xcode" "$int_out"
miss "macconfig does not say first launch is done" "first launch is done" "$int_out"
miss "macconfig did not switch the directory" "xcode-select -s" "$(cat "$XCODE_CALL_LOG")"
miss "macconfig did not run xcodebuild" "xcodebuild" "$(cat "$XCODE_CALL_LOG")"
miss "macconfig did not use sudo" "sudo " "$(cat "$XCODE_CALL_LOG")"
miss "macconfig did not run mas" "mas " "$(cat "$XCODE_CALL_LOG")"

printf 'xcode tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
