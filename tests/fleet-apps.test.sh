#!/usr/bin/env bash
#
# Company apps are installed from Fleet Self service. The check warns when
# one is missing. On a terminal it can open the page. It does not install
# the app, and it does not call the Fleet API.
# Run: ./tests/fleet-apps.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/fleet-apps.sh disable=SC1091
. "$DIR/lib/fleet-apps.sh"

pass_n=0
fail_n=0
eq() {
  if [ "$2" = "$3" ]; then pass_n=$((pass_n + 1)); else
    fail_n=$((fail_n + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {
  case "$3" in *"$2"*) pass_n=$((pass_n + 1)) ;; *)
    fail_n=$((fail_n + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}
miss() {
  case "$3" in *"$2"*) fail_n=$((fail_n + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;;
    *) pass_n=$((pass_n + 1)) ;; esac
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/apps"

cat > "$tmp/bin/open" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${OPEN_LOG:?}"
if [ -n "${OPEN_CREATE:-}" ]; then
  mkdir -p "$OPEN_CREATE"
fi
exit "${OPEN_RC:-0}"
EOF
cat > "$tmp/bin/profiles" <<'EOF'
#!/bin/bash
[ "${1:-}" = status ] && [ "${2:-}" = -type ] && [ "${3:-}" = enrollment ] || exit 2
cat "${PROFILES_STATUS_FILE:?}"
EOF
chmod +x "$tmp/bin/open" "$tmp/bin/profiles"

OPEN_LOG="$tmp/open.log"
PROFILES_STATUS_FILE="$tmp/profiles.txt"
FLEET_OPEN_CMD="$tmp/bin/open"
FLEET_PROFILES_CMD="$tmp/bin/profiles"
FLEET_ID_FILE="$tmp/identifier"
FLEET_DESKTOP_APP="$tmp/Fleet Desktop.app"
FLEET_HOST_FALLBACK="cursor.cloud.fleetdm.com"
OPEN_RC=0
OPEN_CREATE=""
export OPEN_LOG PROFILES_STATUS_FILE FLEET_OPEN_CMD FLEET_PROFILES_CMD
export FLEET_ID_FILE FLEET_DESKTOP_APP FLEET_HOST_FALLBACK OPEN_RC OPEN_CREATE

cat > "$PROFILES_STATUS_FILE" <<'EOF'
Enrolled via DEP: Yes
MDM enrollment: Yes (User Approved)
MDM server: https://fleet.example.test/mdm/apple/mdm
EOF

# A stand-in device id. Not a real Mac.
DEVICE_ID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
printf '%s\n' "$DEVICE_ID" > "$FLEET_ID_FILE"
SELF_URL="https://fleet.example.test/device/${DEVICE_ID}/self-service"

ZOOM="$tmp/apps/zoom.us.app"
ONEP="$tmp/apps/1Password.app"
OKTA="$tmp/apps/Okta Verify.app"
cat > "$tmp/apps.list" <<EOF
# required company apps
Okta Verify|$OKTA|
Zoom|$ZOOM|
1Password|$ONEP|
EOF

reset_case() {
  : >"$OPEN_LOG"
  OPEN_RC=0
  OPEN_CREATE=""
  export OPEN_RC OPEN_CREATE
  rm -rf "$ZOOM" "$ONEP" "$OKTA" "$FLEET_DESKTOP_APP"
  printf '%s\n' "$DEVICE_ID" > "$FLEET_ID_FILE"
}

# $1 interactive, $2 offer, $3 FLEET_CHECK, $4 stdin text. Prints the prompt's stdout.
run_prompt() {
  local interactive="$1" offer="$2" check="$3" input="$4"
  DOTFILES_INTERACTIVE="$interactive" FLEET_OFFER="$offer" FLEET_CHECK="$check" \
    fleet_company_apps_prompt "$tmp/apps.list" <<EOF
$input
EOF
}

# ---- the real list still names Zoom and 1Password as required ----
apps_data="$(grep -v '^[[:space:]]*#' "$DIR/lib/mdm-apps.list" || true)"
has "Zoom is a required company app" "Zoom|/Applications/zoom.us.app|" "$apps_data"
has "1Password is a required company app" "1Password|/Applications/1Password.app|" "$apps_data"
eq "a missing company app stays Needs Paul" "PAUL" \
  "$(awk -F'|' '$1=="mdm" { print $2; exit }' "$DIR/lib/autofix.list")"
has "bootstrap offers the page after install" "fleet_company_apps_prompt" "$(cat "$DIR/bootstrap.sh")"
order="$(awk '
  /step 1 / { s = NR }
  /fleet_company_apps_prompt/ && s && !p { p = NR }
  /step 2 / { t = NR }
  END { if (s && p && t && s < p && p < t) print "ok"; else print "bad" }
' "$DIR/bootstrap.sh")"
eq "the offer sits after install and before the shell step" "ok" "$order"

# ---- host: parsed from profiles, or the fallback ----
eq "MDM server host is parsed" "fleet.example.test" "$(fleet_mdm_host)"
printf '\n' > "$tmp/profiles-empty.txt"
PROFILES_STATUS_FILE="$tmp/profiles-empty.txt" eq "missing MDM server uses the fallback host" \
  "cursor.cloud.fleetdm.com" "$(PROFILES_STATUS_FILE="$tmp/profiles-empty.txt" fleet_mdm_host)"
eq "missing profiles command uses the fallback host" "cursor.cloud.fleetdm.com" \
  "$(FLEET_PROFILES_CMD="$tmp/bin/no-such-profiles" fleet_mdm_host)"
PROFILES_STATUS_FILE="$tmp/profiles.txt"

# ---- all present: no prompt, nothing opened ----
reset_case
mkdir -p "$ZOOM" "$ONEP" "$OKTA"
out="$(run_prompt 1 1 "" $'y\n')"
rc=$?
eq "all present exits 0" 0 "$rc"
eq "all present opens nothing" "" "$(cat "$OPEN_LOG")"
miss "all present does not ask" "Open Fleet Self service" "$out"
miss "all present does not warn" "warning:" "$out"

# ---- some missing, answer yes: open the self-service URL, then re-check ----
reset_case
mkdir -p "$OKTA"
OPEN_CREATE="$ZOOM"
export OPEN_CREATE
out="$(run_prompt 1 1 "" $'y\n\n')"
rc=$?
eq "yes exits 0" 0 "$rc"
eq "yes opens the self-service URL" "$SELF_URL" "$(cat "$OPEN_LOG")"
has "yes names Zoom" "Zoom ($ZOOM)" "$out"
has "yes names 1Password" "1Password ($ONEP)" "$out"
has "yes asks to open Fleet Self service" "Open Fleet Self service to install them now? [Y/n]" "$out"
has "yes waits for Enter" "Press Enter after installing them." "$out"
has "yes reports Zoom present after install" "Zoom is now present" "$out"
has "yes warns that 1Password is still missing" "warning: 1Password missing at $ONEP" "$out"
miss "yes does not call the missing app drift" "DRIFT" "$out"

# Same answers, reported through the check (pass / warn, never drift).
reset_case
mkdir -p "$OKTA"
OPEN_CREATE="$ZOOM"
export OPEN_CREATE
# Called from lib/fleet-apps.sh when FLEET_CHECK=1. Shellcheck cannot see that.
# shellcheck disable=SC2317
pass() { printf 'ok|%s\n' "$1"; }
# shellcheck disable=SC2317
warn() { printf 'warn|%s\n' "$1"; }
# shellcheck disable=SC2317
bad() { printf 'drift|%s\n' "$1"; }
out="$(run_prompt 1 1 1 $'y\n\n')"
rc=$?
eq "check yes exits 0" 0 "$rc"
eq "check yes opens the same URL" "$SELF_URL" "$(cat "$OPEN_LOG")"
has "check reports Okta already present" "ok|Okta Verify present" "$out"
has "check reports Zoom present after install" "ok|Zoom is now present" "$out"
has "check warns 1Password is still missing" "warn|1Password missing at $ONEP" "$out"
miss "check does not report drift" "drift|" "$out"
unset -f pass warn bad

# ---- non-interactive: name the apps and how to install them; do not open ----
reset_case
out="$(run_prompt 0 1 "" $'y\n')"
rc=$?
eq "non-interactive exits 0" 0 "$rc"
eq "non-interactive opens nothing" "" "$(cat "$OPEN_LOG")"
miss "non-interactive does not ask" "Open Fleet Self service to install them now?" "$out"
has "non-interactive names Zoom" "Zoom ($ZOOM)" "$out"
has "non-interactive names 1Password" "1Password ($ONEP)" "$out"
has "non-interactive prints the menu path" "Fleet Desktop menu bar → My device → Self service" "$out"
has "non-interactive prints the self-service URL" "$SELF_URL" "$out"
has "non-interactive warns" "warning: Zoom missing at $ZOOM" "$out"

# ---- identifier missing: open Fleet Desktop, not a URL ----
reset_case
rm -f "$FLEET_ID_FILE"
mkdir -p "$FLEET_DESKTOP_APP"
out="$(run_prompt 1 1 "" $'y\n\n')"
rc=$?
eq "missing identifier exits 0" 0 "$rc"
eq "missing identifier opens Fleet Desktop" "$FLEET_DESKTOP_APP" "$(cat "$OPEN_LOG")"
has "missing identifier says Fleet Desktop opened" "Opened Fleet Desktop" "$out"
miss "missing identifier does not build a device URL" "https://" "$out"
has "missing identifier still warns" "warning: Zoom missing at $ZOOM" "$out"

# Identifier missing and Fleet Desktop not installed: print the menu path.
reset_case
rm -f "$FLEET_ID_FILE"
rm -rf "$FLEET_DESKTOP_APP"
OPEN_RC=1
export OPEN_RC
out="$(run_prompt 1 1 "" $'y\n\n')"
rc=$?
eq "no desktop exits 0" 0 "$rc"
has "no desktop prints the menu path" "Fleet Desktop menu bar → My device → Self service" "$out"
miss "no desktop does not build a device URL" "https://" "$out"

# ---- the check script uses the same prompt and does not drift ----
reset_case
OPEN_CREATE=""
export OPEN_CREATE
out="$(
  # shellcheck disable=SC2034  # checks/mdm.sh increments this
  CHECKED=0
  hdr() { printf 'hdr|%s\n' "$1"; }
  fixid() { :; }
  # shellcheck disable=SC2317
  pass() { printf 'ok|%s\n' "$1"; }
  # shellcheck disable=SC2317
  warn() { printf 'warn|%s\n' "$1"; }
  # shellcheck disable=SC2317
  bad() { printf 'drift|%s\n' "$1"; }
  # shellcheck disable=SC2317
  note() { :; }
  DOTDIR="$DIR" DOTFILES_INTERACTIVE=0 FLEET_OFFER=0 \
    . "$DIR/checks/mdm.sh"
)"
has "check section header" "hdr|MDM / company apps" "$out"
has "check names Zoom from the list" "Zoom" "$out"
has "check names 1Password from the list" "1Password" "$out"
miss "check script does not report drift" "drift|" "$out"
eq "check script opens nothing when it is not a terminal" "" "$(cat "$OPEN_LOG")"

# Old product names stay out of the tree. The needles are built here so this
# file does not contain them.
vendor="$(printf '%s%s' 'Kand' 'ji')"
hits="$(git -C "$DIR" grep -n -I -F "$vendor" -- . || true)"
eq "no old MDM vendor name remains" "" "$hits"
low="$(printf '%s' "$vendor" | tr '[:upper:]' '[:lower:]')"
hits="$(git -C "$DIR" grep -n -I -F "$low" -- . || true)"
eq "no old MDM vendor name in lower case remains" "" "$hits"
other="$(printf '%s%s' 'Ir' 'u')"
hits="$(git -C "$DIR" grep -n -I -F "$other" -- . || true)"
eq "no old self-service app name remains" "" "$hits"

printf 'fleet-apps tests: %d passed, %d failed\n' "$pass_n" "$fail_n"
[ "$fail_n" -eq 0 ]
