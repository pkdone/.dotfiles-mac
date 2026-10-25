#!/usr/bin/env bash
#
# Tailscale sign-in step. A fake CLI only — status JSON is never signed in,
# and auth keys and node keys must not appear in the result.
# Run: ./tests/tailscale-signin.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MS="$DIR/scripts/manual-steps.sh"
LIST="$DIR/lib/manual-steps.list"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "tailscale-signin tests: python3 not found, skipped"; exit 0; fi

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
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

row="$(awk -F'|' '$1=="tailscale-signin" { print; exit }' "$LIST")"
eq "step is in Sign-ins" Sign-ins "$(printf '%s\n' "$row" | cut -d'|' -f2)"
eq "step title" "Open Tailscale, turn it on, and sign in as paul.done@anysphere.co" \
  "$(printf '%s\n' "$row" | cut -d'|' -f3)"
has "step opens Tailscale from Applications" "Open Tailscale from Applications" "$row"
has "step names the menu bar login" "click Log in" "$row"
eq "step opens the Tailscale app" app:Tailscale "$(printf '%s\n' "$row" | cut -d'|' -f5)"
eq "step check name" tailscale-signin "$(printf '%s\n' "$row" | cut -d'|' -f6)"
# Sign-ins stays one group, after the 1Password steps: GitHub, then Tailscale.
order="$(awk -F'|' '$1=="1password-cli" || $1=="gh-auth" || $1=="tailscale-signin" { print $1 }' "$LIST" | tr '\n' ' ')"
eq "Tailscale follows 1Password and the GitHub sign-in" "1password-cli gh-auth tailscale-signin " "$order"
eq "fix does not sign in" "PAUL|" \
  "$(awk -F'|' '$1=="tailscale-signin" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/open" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$bin/tailscale" <<'EOF'
#!/bin/sh
printf '%s\n' "BE_CLI=${TAILSCALE_BE_CLI-}" >> "${TAILSCALE_LOG:?}"
if [ "${1:-}" = status ] && [ "${2:-}" = --json ]; then
  printf '%s' "${TAILSCALE_JSON-}"
  exit "${TAILSCALE_RC:-0}"
fi
exit 1
EOF
chmod +x "$bin/open" "$bin/tailscale"
printf '%s\n' \
  'tailscale-signin|Sign-ins|Open Tailscale, turn it on, and sign in as paul.done@anysphere.co|Open Tailscale|app:Tailscale|tailscale-signin' \
  > "$tmp/steps.list"
export NO_COLOR=1 TAILSCALE_LOG="$tmp/tailscale.log" MANUAL_STEPS_TAILSCALE_BIN="$bin/tailscale"
: > "$TAILSCALE_LOG"
AUTH='tskey-auth-SECRETVALUE'
NODE='nodekey:SECRETVALUE'

json_for() { # state login
  "$PY" - "$1" "$2" "$AUTH" "$NODE" <<'PY'
import json, sys
state, login, auth, node = sys.argv[1:]
user = {"7": {"LoginName": login}} if login else {}
print(json.dumps({
    "BackendState": state,
    "AuthKey": auth,
    "Self": {"UserID": 7, "NodeKey": node},
    "User": user,
}))
PY
}

check() {
  TAILSCALE_JSON="$1" TAILSCALE_RC="${2:-0}" \
    PATH="$bin:$PATH" MANUAL_STEPS_LIST="$tmp/steps.list" \
    "$MS" check --porcelain
}

out="$(check "$(json_for Running paul.done@anysphere.co)")"
eq "running as Paul is ok" ok "$(printf '%s\n' "$out" | cut -d'|' -f1)"
has "the CLI is forced even when the app binary is used" "BE_CLI=1" "$(cat "$TAILSCALE_LOG")"
has "running as Paul names the account" "paul.done@anysphere.co" "$out"
miss "running as Paul does not print the auth key" "$AUTH" "$out"
miss "running as Paul does not print the node key" "$NODE" "$out"

out="$(check "$(json_for NeedsLogin '')")"
eq "needs login is not set yet" warn "$(printf '%s\n' "$out" | cut -d'|' -f1)"
has "needs login names the state" "NeedsLogin" "$out"
miss "needs login does not print the auth key" "$AUTH" "$out"

out="$(check "$(json_for Stopped '')")"
eq "stopped is not set yet" warn "$(printf '%s\n' "$out" | cut -d'|' -f1)"
has "stopped names the state" "Stopped" "$out"

out="$(check "$(json_for Running other@example.com)")"
eq "a different account is not set yet" warn "$(printf '%s\n' "$out" | cut -d'|' -f1)"
has "a different account is named" "signed in as other@example.com" "$out"
has "a different account names the wanted login" "paul.done@anysphere.co" "$out"
miss "a different account does not print the node key" "$NODE" "$out"

out="$(check 'not-json')"
eq "unreadable status is check by hand" hand "$(printf '%s\n' "$out" | cut -d'|' -f1)"
miss "unreadable status does not echo the body" "not-json" "$out"

out="$(MANUAL_STEPS_TAILSCALE_BIN="$tmp/no-such-tailscale" PATH="$bin:$PATH" \
  MANUAL_STEPS_LIST="$tmp/steps.list" "$MS" check --porcelain)"
eq "a missing CLI is check by hand" hand "$(printf '%s\n' "$out" | cut -d'|' -f1)"
has "a missing CLI says it can't be run" "can't be run" "$out"

cat > "$bin/tailscale" <<'EOF'
#!/bin/sh
if [ "${1:-}" = status ] && [ "${2:-}" = --json ]; then
  printf '%s' "${TAILSCALE_JSON-}"
  exit 0
fi
exit 1
EOF
chmod +x "$bin/tailscale"
open_out="$(printf 's\n' | TAILSCALE_JSON="$(json_for NeedsLogin '')" \
  PATH="$bin:$PATH" MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/steps.list" \
  "$MS" open)"
has "open shows the step when Tailscale needs login" \
  "Open Tailscale, turn it on, and sign in as paul.done@anysphere.co" "$open_out"
has "open says not set yet" "Not set yet:" "$open_out"
miss "open does not print the auth key" "$AUTH" "$open_out"

open_ok="$(printf 's\n' | TAILSCALE_JSON="$(json_for Running paul.done@anysphere.co)" \
  PATH="$bin:$PATH" MANUAL_STEPS_OPEN_TTY=1 MANUAL_STEPS_LIST="$tmp/steps.list" \
  "$MS" open)"
has "open skips a signed-in Tailscale" "Nothing to do" "$open_ok"
miss "open hides the title when already signed in" "sign in as paul.done" "$open_ok"

printf 'tailscale-signin tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
