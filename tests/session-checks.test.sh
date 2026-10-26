#!/usr/bin/env bash
#
# British input source, pointer size, gh auth status, and the 1Password CLI.
# The checks live once, in lib/session-checks.sh, and scripts/manual-steps.sh
# runs them. macconfig-check.sh prints that result in Manual steps.
# Run: ./tests/session-checks.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
LIB="$DIR/lib/session-checks.sh"
MS="$DIR/scripts/manual-steps.sh"
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
# Account ids, emails, UUIDs, and URLs from op must not show up in a result or a log.
no_account_fields() {
  local label="$1" blob="$2" field
  for field in \
    'acct-email-SECRET@example.com' 'acct-url-SECRET' 'user-uuid-SECRET' 'account-uuid-SECRET' \
    '"email"' '"user_uuid"' '"account_uuid"' '"url"'
  do
    miss "$label has no $field" "$field" "$blob"
  done
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# defaults read DOMAIN [KEY] — body is $DEFAULTS_DIR/domain or domain.key
mkdir -p "$tmp/bin" "$tmp/defaults" "$tmp/1Password.app"
cat > "$tmp/bin/defaults" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "read" ] || exit 1
domain="$2"
key="${3:-}"
if [ -n "$key" ]; then
  file="${DEFAULTS_DIR:?}/$domain.$key"
else
  file="${DEFAULTS_DIR:?}/$domain"
fi
[ -f "$file" ] || exit 1
cat "$file"
EOF
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
exit "${GH_RC:-0}"
EOF
cat > "$tmp/bin/op" <<'EOF'
#!/usr/bin/env bash
# Stubbed op. whoami uses OP_WHOAMI_RC (else OP_RC). account list prints a
# JSON array of OP_ACCOUNTS objects, or OP_ACCOUNT_BODY. Values are secrets
# the check must not echo. signin must never run.
log="${OP_LOG:-}"
if [ -n "$log" ]; then
  printf '%s\n' "$*" >> "$log"
  if [ -t 0 ]; then printf '%s\n' "stdin-tty" >> "$log"; else printf '%s\n' "stdin-not-tty" >> "$log"; fi
fi
cmd="${1:-}"
if [ "$cmd" = signin ]; then
  printf '%s\n' "ran-signin" >> "${log:-/dev/stderr}"
  exit 99
fi
if [ "$cmd" = whoami ]; then
  exit "${OP_WHOAMI_RC:-${OP_RC:-0}}"
fi
if [ "$cmd" = account ] && [ "${2:-}" = list ]; then
  case " $* " in
    *" --format=json "*) ;;
    *) exit 2 ;;
  esac
  if [ -n "${OP_ACCOUNT_BODY:-}" ]; then
    printf '%s' "$OP_ACCOUNT_BODY"
    exit "${OP_ACCOUNT_RC:-0}"
  fi
  n="${OP_ACCOUNTS:-0}"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '['
  i=0
  while [ "$i" -lt "$n" ]; do
    [ "$i" -gt 0 ] && printf ','
    printf '%s' "{\"url\":\"https://acct-url-SECRET.1password.com\",\"email\":\"acct-email-SECRET@example.com\",\"user_uuid\":\"user-uuid-SECRET\",\"account_uuid\":\"account-uuid-SECRET-$i\"}"
    i=$((i + 1))
  done
  printf ']'
  exit 0
fi
exit 1
EOF
cat > "$tmp/bin/open" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$tmp/bin/defaults" "$tmp/bin/gh" "$tmp/bin/op" "$tmp/bin/open"
: > "$tmp/op.log"
stub_path="$tmp/bin:$PATH"

with_timeout() { shift; "$@"; }
# shellcheck source=../lib/session-checks.sh disable=SC1091
. "$LIB"

run_check() { # function name — CHECK_PATH replaces PATH (missing-binary cases)
  R_STATUS=""
  R_DETAIL=""
  # Resolved before the command prefix: a prefix assignment is not visible to
  # the next one on the same command.
  whoami_rc="${OP_WHOAMI_RC:-${OP_RC:-0}}"
  PATH="${CHECK_PATH:-$tmp/bin:$PATH}" DEFAULTS_DIR="$tmp/defaults" \
    SESSION_CHECKS_OP_APP="$tmp/1Password.app" \
    GH_RC="${GH_RC:-0}" OP_RC="${OP_RC:-0}" \
    OP_WHOAMI_RC="$whoami_rc" \
    OP_ACCOUNTS="${OP_ACCOUNTS:-0}" \
    OP_ACCOUNT_BODY="${OP_ACCOUNT_BODY:-}" \
    OP_ACCOUNT_RC="${OP_ACCOUNT_RC:-0}" \
    OP_LOG="${OP_LOG:-$tmp/op.log}" \
    "$@"
}

british_on() {
  cat > "$tmp/defaults/com.apple.HIToolbox.AppleSelectedInputSources" <<'EOF'
(
    {
        InputSourceKind = "Keyboard Layout";
        "KeyboardLayout Name" = British;
        "KeyboardLayout ID" = 2;
    },
    {
        "Bundle ID" = "com.apple.PressAndHold";
        InputSourceKind = "Non Keyboard Input Method";
    }
)
EOF
}
british_off() {
  cat > "$tmp/defaults/com.apple.HIToolbox.AppleSelectedInputSources" <<'EOF'
(
    {
        InputSourceKind = "Keyboard Layout";
        "KeyboardLayout Name" = ABC;
    },
    {
        InputSourceKind = "Keyboard Layout";
        "KeyboardLayout Name" = British;
    }
)
EOF
}
pointer() { # domain-exists size-or-empty
  printf 'domain\n' > "$tmp/defaults/com.apple.universalaccess"
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1" > "$tmp/defaults/com.apple.universalaccess.mouseDriverCursorSize"
  else
    rm -f "$tmp/defaults/com.apple.universalaccess.mouseDriverCursorSize"
  fi
}

british_on
run_check check_input_british
eq "British enabled is ok" ok "$R_STATUS"
eq "British enabled detail" "British keyboard layout only" "$R_DETAIL"

british_off
run_check check_input_british
eq "another layout is a warning" warn "$R_STATUS"
has "another layout names it" "ABC" "$R_DETAIL"

rm -f "$tmp/defaults/com.apple.HIToolbox.AppleSelectedInputSources" \
  "$tmp/defaults/com.apple.HIToolbox.AppleEnabledInputSources"
run_check check_input_british
eq "neither input-source key is check by hand" hand "$R_STATUS"
eq "neither input-source key names both keys" \
  "could not read AppleEnabledInputSources or AppleSelectedInputSources" "$R_DETAIL"
miss "neither input-source key uses the old selected-only message" \
  "can't read the selected input sources" "$R_DETAIL"

# Selected cannot be read. Enabled still names British. That is the layout.
rm -f "$tmp/defaults/com.apple.HIToolbox.AppleSelectedInputSources"
cat > "$tmp/defaults/com.apple.HIToolbox.AppleEnabledInputSources" <<'EOF'
(
    {
        InputSourceKind = "Keyboard Layout";
        "KeyboardLayout Name" = British;
        "KeyboardLayout ID" = 2;
    },
    {
        "Bundle ID" = "com.apple.PressAndHold";
        InputSourceKind = "Non Keyboard Input Method";
    }
)
EOF
run_check check_input_british
eq "Enabled British is ok when Selected cannot be read" ok "$R_STATUS"
eq "Enabled British detail" "British keyboard layout only" "$R_DETAIL"

pointer 1.4
run_check check_pointer_size
eq "pointer 1.4 is ok" ok "$R_STATUS"
eq "pointer 1.4 prints two decimals" "size 1.40" "$R_DETAIL"

pointer 1.2
run_check check_pointer_size
eq "pointer 1.2 is the low edge" ok "$R_STATUS"

pointer 2.0
run_check check_pointer_size
eq "pointer 2.0 is the high edge" ok "$R_STATUS"

pointer 1.0
run_check check_pointer_size
eq "pointer 1.0 (Normal) is a warning" warn "$R_STATUS"

pointer 2.1
run_check check_pointer_size
eq "pointer 2.1 is a warning" warn "$R_STATUS"

pointer ""
run_check check_pointer_size
eq "unset pointer size is a warning" warn "$R_STATUS"
has "unset pointer wants one notch above" "one notch above" "$R_DETAIL"

rm -f "$tmp/defaults/com.apple.universalaccess" \
  "$tmp/defaults/com.apple.universalaccess.mouseDriverCursorSize"
run_check check_pointer_size
eq "unreadable pointer domain is by hand" hand "$R_STATUS"

GH_RC=0
run_check check_gh_auth
eq "gh auth status success is ok" ok "$R_STATUS"
has "gh ok names github.com" "signed in to github.com" "$R_DETAIL"

GH_RC=1
run_check check_gh_auth
eq "gh auth status failure is a warning" warn "$R_STATUS"
has "gh failure points at gh auth login" "gh auth login" "$R_DETAIL"

mkdir -p "$tmp/empty-bin"
# An empty PATH, not /usr/bin: some machines ship gh there, and this case is "gh missing".
CHECK_PATH="$tmp/empty-bin" run_check check_gh_auth
eq "missing gh is a warning" warn "$R_STATUS"
unset CHECK_PATH

unset OP_WHOAMI_RC OP_ACCOUNTS OP_ACCOUNT_BODY OP_ACCOUNT_RC
: > "$tmp/op.log"
OP_RC=0
run_check check_op_cli
eq "op whoami success is ok" ok "$R_STATUS"
eq "op whoami success is signed in" "signed in" "$R_DETAIL"
has "whoami success ran whoami" "whoami" "$(cat "$tmp/op.log")"
miss "whoami success does not list accounts" "account list" "$(cat "$tmp/op.log")"
miss "whoami success does not sign in" "signin" "$(cat "$tmp/op.log")"
has "whoami is not a tty" "stdin-not-tty" "$(cat "$tmp/op.log")"
miss "whoami is not given a terminal" "stdin-tty" "$(cat "$tmp/op.log")"

: > "$tmp/op.log"
OP_RC=1
OP_WHOAMI_RC=1
OP_ACCOUNTS=1
run_check check_op_cli
eq "an added account is ok" ok "$R_STATUS"
eq "an added account detail" \
  "set up (account added via the 1Password app); a new terminal asks to unlock on first use" \
  "$R_DETAIL"
no_account_fields "an added account result" "$R_DETAIL"
no_account_fields "an added account log" "$(cat "$tmp/op.log")"
has "an added account lists accounts as json" "account list --format=json" "$(cat "$tmp/op.log")"
miss "an added account does not sign in" "signin" "$(cat "$tmp/op.log")"
has "account list is not a tty" "stdin-not-tty" "$(cat "$tmp/op.log")"
# set -x is the debug path. It may show the count, never an account field.
: > "$tmp/trace.log"
(
  set -x
  run_check check_op_cli
  printf 'STATUS=%s\nDETAIL=%s\n' "$R_STATUS" "$R_DETAIL"
) >"$tmp/trace.out" 2>"$tmp/trace.log"
eq "traced account count is ok" "ok" "$(sed -n 's/^STATUS=//p' "$tmp/trace.out")"
no_account_fields "traced stdout" "$(cat "$tmp/trace.out")"
no_account_fields "debug trace" "$(cat "$tmp/trace.log")"
no_account_fields "debug trace log" "$(cat "$tmp/op.log")"
has "debug trace shows the count" "n=1" "$(cat "$tmp/trace.log")"

: > "$tmp/op.log"
OP_ACCOUNTS=2
run_check check_op_cli
eq "two accounts is ok" ok "$R_STATUS"
miss "two accounts does not print an account uuid" "account-uuid-SECRET" "$R_DETAIL"

: > "$tmp/op.log"
OP_ACCOUNTS=0
OP_ACCOUNT_BODY='[]'
run_check check_op_cli
eq "empty account list is not set yet" warn "$R_STATUS"
eq "empty account list detail" \
  "turn on Integrate with 1Password CLI in 1Password → Settings → Developer, then run op signin" \
  "$R_DETAIL"
miss "empty account list does not say op whoami" "op whoami" "$R_DETAIL"

: > "$tmp/op.log"
OP_ACCOUNT_BODY='https://acct-url-SECRET.1password.com acct-email-SECRET@example.com user-uuid-SECRET account-uuid-SECRET'
OP_ACCOUNT_RC=1
run_check check_op_cli
eq "account list failure is not set yet" warn "$R_STATUS"
no_account_fields "account list failure result" "$R_DETAIL"
no_account_fields "account list failure log" "$(cat "$tmp/op.log")"
unset OP_WHOAMI_RC OP_ACCOUNTS OP_ACCOUNT_BODY OP_ACCOUNT_RC

OP_RC=0
rmdir "$tmp/1Password.app"
run_check check_op_cli
eq "missing 1Password app is a warning" warn "$R_STATUS"
mkdir -p "$tmp/1Password.app"

# Not /usr/bin:/bin: a host `op` in /usr/bin would look installed.
CHECK_PATH="$(hermetic_safe_root)" run_check check_op_cli
eq "missing op CLI is a warning" warn "$R_STATUS"
unset CHECK_PATH

# The library itself never writes, never sudo, never opens the notification store.
lib_code="$(grep -v '^[[:space:]]*#' "$LIB")"
miss "session checks do not sudo" 'sudo' "$lib_code"
miss "session checks do not defaults write" 'defaults write' "$lib_code"
miss "session checks do not touch the notification store" 'usernoted' "$lib_code"

# macconfig-check.sh shows the manual-steps result. It does not run the checks again.
check_src="$(grep -v '^[[:space:]]*#' "$DIR/macconfig-check.sh" "$DIR"/checks/*.sh)"
for fn in check_pointer_size check_input_british check_gh_auth check_op_cli; do
  miss "macconfig-check.sh does not call $fn" "$fn" "$check_src"
done
miss "nothing hides these rows from Manual steps" 'MANUAL_STEPS_COVERED' \
  "$(cat "$DIR/macconfig-check.sh" "$DIR"/checks/*.sh "$MS")"
miss "there is no second sign-in section" 'Sign-ins, keyboard, and pointer' \
  "$(cat "$DIR/macconfig-check.sh" "$DIR"/checks/*.sh)"
manual_src="$(grep -v '^[[:space:]]*#' "$DIR/checks/manual.sh")"
# shellcheck disable=SC2016  # needle is source text, compared literally
has "a by-hand manual step is info" 'hand)    info ' "$manual_src"
miss "Manual steps does not report drift" 'bad "' "$manual_src"
for id in pointer-size input-british gh-auth 1password-cli; do
  has "a $id warning keeps its id" "$id) fixid $id" "$manual_src"
  eq "$id is Needs Paul with no fixer" "PAUL|" \
    "$(awk -F'|' -v id="$id" '$1 == id { print $2 "|" $3; exit }' "$AUTO")"
  has "manual step $id exists" "$id|" "$(cat "$LIST")"
done
eq "input-british check name" "input-british" \
  "$(awk -F'|' '$1 == "input-british" { print $6; exit }' "$LIST")"
eq "gh-auth check name" "gh-auth" \
  "$(awk -F'|' '$1 == "gh-auth" { print $6; exit }' "$LIST")"
eq "1password-cli check name" "op-cli" \
  "$(awk -F'|' '$1 == "1password-cli" { print $6; exit }' "$LIST")"
eq "1password-cli step names op signin once" \
  "Turn on Integrate with 1Password CLI, then run op signin once in a terminal" \
  "$(awk -F'|' '$1 == "1password-cli" { print $3; exit }' "$LIST")"
has "op check still runs op whoami" "with_timeout 8 op whoami </dev/null" "$(cat "$LIB")"
has "op check counts inside the timeout" "with_timeout 8 python3 -c" "$(cat "$LIB")"
has "op check discards account-list stderr" "2>/dev/null || true)" "$(cat "$LIB")"
miss "op check does not capture account list in a variable" "json=" "$(cat "$LIB")"
miss "op check does not run op signin" "with_timeout 8 op signin" "$(cat "$LIB")"
miss "session checks do not mktemp" 'mktemp' "$(grep -v '^[[:space:]]*#' "$LIB")"
eq "pointer-size check name" "pointer-size" \
  "$(awk -F'|' '$1 == "pointer-size" { print $6; exit }' "$LIST")"
eq "no app-store manual step" "" \
  "$(awk -F'|' '$1 == "app-store" { print $1; exit }' "$LIST")"

# Source the Manual steps section with the same fakes. Stubs replace
# pass/warn/info so the real macconfig-check.sh machinery never runs.
# shellcheck disable=SC2034,SC2317
run_manual() {
  (
    set -euo pipefail
    # shellcheck disable=SC2030  # this PATH is only for the sourced section
    export PATH="$tmp/bin:$PATH" DEFAULTS_DIR="$tmp/defaults" SESSION_CHECKS_OP_APP="$tmp/1Password.app"
    export GH_RC="${1:-0}" OP_RC="${2:-0}" NO_COLOR=1
    # $3 is an optional steps list. Account-count cases set OP_WHOAMI_RC and
    # OP_ACCOUNTS in the environment before the call.
    export OP_WHOAMI_RC="${OP_WHOAMI_RC:-${2:-0}}" OP_ACCOUNTS="${OP_ACCOUNTS:-0}"
    export MANUAL_STEPS_LIST="${3:-$tmp/steps.list}"
    DOTDIR="$DIR"
    CHECKED=0
    FIX_ID=""
    hdr() { :; }
    fixid() { FIX_ID="$1"; }
    pass() { printf 'PASS %s %s\n' "$FIX_ID" "$1"; }
    warn() { printf 'WARN %s %s\n' "$FIX_ID" "$1"; }
    info() { printf 'INFO %s %s\n' "$FIX_ID" "$1"; }
    bad() { printf 'DRIFT %s %s\n' "$FIX_ID" "$1"; }
    # shellcheck disable=SC1091
    . "$DIR/checks/manual.sh"
  )
}

british_on
pointer 1.4
cat > "$tmp/steps.list" <<'EOF'
gh-auth|Sign-ins|Sign in to the GitHub CLI|Terminal: gh auth login||gh-auth
1password-cli|Company apps (MDM)|Turn on Integrate with 1Password CLI|1Password → Settings → Developer|app:1Password|op-cli
input-british|Display, keyboard & desktop|Keyboard input source: British|System Settings → Keyboard|x-apple.systempreferences:com.apple.Keyboard-Settings.extension|input-british
pointer-size|Trackpad, mouse & pointer|Pointer size one notch above Normal|System Settings → Accessibility|x-apple.systempreferences:com.apple.Accessibility-Settings.extension|pointer-size
EOF

out="$(run_manual 0 0)"
rc=$?
eq "manual section all-ok exits 0" 0 "$rc"
miss "manual section all-ok has no warning" 'WARN ' "$out"
miss "manual section all-ok has no drift" 'DRIFT ' "$out"
has "manual section prints British" 'Keyboard input source: British' "$out"
has "manual section prints gh" 'Sign in to the GitHub CLI' "$out"
has "manual section prints op" 'Integrate with 1Password CLI' "$out"
has "manual section prints pointer" 'Pointer size one notch above Normal' "$out"
miss "manual section does not print an App Store step" 'Sign in to the App Store' "$out"

british_off
out="$(run_manual 0 0)"
has "British off is a warning tagged input-british" 'WARN input-british' "$out"
has "British off names the step" 'Keyboard input source: British' "$out"
miss "British off is not drift" 'DRIFT ' "$out"
british_on

pointer 1.0
out="$(run_manual 0 0)"
has "Normal pointer is a warning tagged pointer-size" 'WARN pointer-size' "$out"
has "Normal pointer names the step" 'Pointer size one notch above Normal' "$out"
miss "Normal pointer is not drift" 'DRIFT ' "$out"
pointer 1.4

out="$(run_manual 1 0)"
has "gh signed out is a warning tagged gh-auth" 'WARN gh-auth' "$out"
has "gh signed out names the step" 'Sign in to the GitHub CLI' "$out"
miss "gh signed out is not drift" 'DRIFT ' "$out"

out="$(run_manual 0 1)"
has "no 1Password account is a warning tagged 1password-cli" 'WARN 1password-cli' "$out"
has "no 1Password account names the step" 'Integrate with 1Password CLI' "$out"
has "no 1Password account says to run op signin" 'op signin' "$out"
miss "no 1Password account is not info" 'INFO 1password-cli' "$out"
miss "no 1Password account is not drift" 'DRIFT ' "$out"
miss "no 1Password account does not print an account email" 'acct-email-SECRET@example.com' "$out"

out="$(OP_WHOAMI_RC=1 OP_ACCOUNTS=1 run_manual 0 1)"
unset OP_WHOAMI_RC OP_ACCOUNTS
has "an added account passes in Manual steps" 'PASS ' "$out"
has "an added account names the app integration" 'account added via the 1Password app' "$out"
miss "an added account does not warn" 'WARN 1password-cli' "$out"
miss "an added account does not print the email" 'acct-email-SECRET@example.com' "$out"
miss "an added account does not print the url" 'acct-url-SECRET' "$out"

rmdir "$tmp/1Password.app"
out="$(run_manual 0 0)"
has "missing 1Password app is a warning tagged 1password-cli" 'WARN 1password-cli' "$out"
mkdir -p "$tmp/1Password.app"

# No pointer-size row: that check does not run.
cat > "$tmp/no-pointer.list" <<'EOF'
input-british|Display, keyboard & desktop|Keyboard input source: British|System Settings → Keyboard|x-apple.systempreferences:com.apple.Keyboard-Settings.extension|input-british
gh-auth|Sign-ins|Sign in to the GitHub CLI|Terminal: gh auth login||gh-auth
1password-cli|Company apps (MDM)|Turn on Integrate with 1Password CLI|1Password → Settings → Developer|app:1Password|op-cli
EOF
out="$(run_manual 0 0 "$tmp/no-pointer.list")"
miss "absent pointer step is not checked" 'pointer-size' "$out"
has "other steps still run without the pointer row" 'Sign in to the GitHub CLI' "$out"

# scripts/manual-steps.sh is the one runner of these checks.
porcelain() {
  # shellcheck disable=SC2031  # parent PATH, not the section subshell's
  PATH="$tmp/bin:$PATH" DEFAULTS_DIR="$tmp/defaults" \
    SESSION_CHECKS_OP_APP="$tmp/1Password.app" \
    GH_RC="${1:-0}" OP_RC="${2:-0}" \
    OP_WHOAMI_RC="${3:-${2:-0}}" OP_ACCOUNTS="${4:-0}" \
    OP_ACCOUNT_BODY="${OP_ACCOUNT_BODY:-}" OP_ACCOUNT_RC="${OP_ACCOUNT_RC:-0}" \
    OP_LOG="${OP_LOG:-$tmp/op.log}" \
    MANUAL_STEPS_LIST="$tmp/steps.list" \
    "$MS" check --porcelain 2>&1
}
out="$(porcelain 0 0)"
eq "standalone gh-auth passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$3=="gh-auth"{print $1; exit}')"
eq "standalone British passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$3=="input-british"{print $1; exit}')"
eq "standalone pointer passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$3=="pointer-size"{print $1; exit}')"
out="$(porcelain 0 1)"
eq "standalone op with no account is a warning" "warn" "$(printf '%s\n' "$out" | awk -F'|' '$3=="1password-cli"{print $1; exit}')"
has "standalone op with no account says to run op signin" "op signin" "$(printf '%s\n' "$out" | awk -F'|' '$3=="1password-cli"{print $5; exit}')"
out="$(porcelain 0 1 1 1)"
eq "standalone op with an account is ok" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$3=="1password-cli"{print $1; exit}')"
miss "standalone op with an account does not print the email" "acct-email-SECRET@example.com" "$out"
out="$(porcelain 0 0)"
eq "standalone op whoami success is ok" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$3=="1password-cli"{print $1; exit}')"
out="$(porcelain 1 0)"
eq "standalone gh signed out is a warning" "warn" "$(printf '%s\n' "$out" | awk -F'|' '$3=="gh-auth"{print $1; exit}')"

# manualsteps open/pending skip a step whose check is ok. No account is
# "NOTSET:". A one-row list, so other steps do not get in the way.
printf '%s\n' \
  '1password-cli|Company apps (MDM)|Turn on Integrate with 1Password CLI, then run op signin once in a terminal|1Password → Settings → Developer|app:1Password|op-cli' \
  > "$tmp/op-only.list"
pending_ok="$(OP_WHOAMI_RC=1 OP_ACCOUNTS=1 PATH="$stub_path" \
  SESSION_CHECKS_OP_APP="$tmp/1Password.app" MANUAL_STEPS_LIST="$tmp/op-only.list" \
  OP_LOG="$tmp/op.log" NO_COLOR=1 "$MS" pending)"
has "an added account is already done" "Skipped 1 already done." "$pending_ok"
has "an added account leaves nothing to set" "Nothing left to set by hand." "$pending_ok"
miss "an added account is not shown by pending" "Integrate with 1Password CLI" "$pending_ok"
miss "pending with an account does not print the email" "acct-email-SECRET@example.com" "$pending_ok"
open_ok="$(printf 's\n' | OP_WHOAMI_RC=1 OP_ACCOUNTS=1 PATH="$stub_path" \
  SESSION_CHECKS_OP_APP="$tmp/1Password.app" MANUAL_STEPS_LIST="$tmp/op-only.list" \
  MANUAL_STEPS_OPEN_TTY=1 OP_LOG="$tmp/op.log" NO_COLOR=1 "$MS" open)"
has "open skips an added account" "Nothing to do" "$open_ok"
miss "open does not show an added account" "Integrate with 1Password CLI" "$open_ok"
pending_miss="$(OP_WHOAMI_RC=1 OP_ACCOUNTS=0 PATH="$stub_path" \
  SESSION_CHECKS_OP_APP="$tmp/1Password.app" MANUAL_STEPS_LIST="$tmp/op-only.list" \
  OP_LOG="$tmp/op.log" NO_COLOR=1 "$MS" pending)"
has "no account says not set yet" "NOTSET:" "$pending_miss"
has "no account names the developer setting" "1Password → Settings → Developer" "$pending_miss"
has "no account says to run op signin" "then run op signin" "$pending_miss"
miss "no account does not mention op whoami" "op whoami" "$pending_miss"

printf 'session-checks tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
