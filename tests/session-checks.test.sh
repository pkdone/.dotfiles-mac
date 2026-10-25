#!/usr/bin/env bash
#
# British input source, pointer size, gh auth status, and op whoami.
# The checks live once, in lib/session-checks.sh, and scripts/manual-steps.sh
# runs them. macconfig-check.sh prints that result in Manual steps.
# Run: ./tests/session-checks.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
exit "${OP_RC:-0}"
EOF
chmod +x "$tmp/bin/defaults" "$tmp/bin/gh" "$tmp/bin/op"

with_timeout() { shift; "$@"; }
# shellcheck source=../lib/session-checks.sh disable=SC1091
. "$LIB"

run_check() { # function name — CHECK_PATH replaces PATH (missing-binary cases)
  R_STATUS=""
  R_DETAIL=""
  PATH="${CHECK_PATH:-$tmp/bin:$PATH}" DEFAULTS_DIR="$tmp/defaults" \
    SESSION_CHECKS_OP_APP="$tmp/1Password.app" \
    GH_RC="${GH_RC:-0}" OP_RC="${OP_RC:-0}" \
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

OP_RC=0
run_check check_op_cli
eq "op whoami success is ok" ok "$R_STATUS"

OP_RC=1
run_check check_op_cli
eq "op installed but not signed in is by hand, not a warning" hand "$R_STATUS"
has "op not signed in mentions an unlock" "unlock" "$R_DETAIL"
miss "op not signed in is not a warning detail" "not installed" "$R_DETAIL"

OP_RC=0
rmdir "$tmp/1Password.app"
run_check check_op_cli
eq "missing 1Password app is a warning" warn "$R_STATUS"
mkdir -p "$tmp/1Password.app"

CHECK_PATH="/usr/bin:/bin" run_check check_op_cli
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
eq "1password-cli step names op signin then op whoami" \
  "Turn on Integrate with 1Password CLI, then run op signin and then op whoami in a terminal" \
  "$(awk -F'|' '$1 == "1password-cli" { print $3; exit }' "$LIST")"
has "op check still runs op whoami" "with_timeout 8 op whoami" "$(cat "$LIB")"
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
has "op locked is info, not a warning" 'INFO ' "$out"
has "op locked names the step" 'Integrate with 1Password CLI' "$out"
has "op locked says check by hand" 'check by hand' "$out"
miss "op locked does not warn" 'WARN 1password-cli' "$out"
miss "op locked is not drift" 'DRIFT ' "$out"

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
    MANUAL_STEPS_LIST="$tmp/steps.list" \
    "$MS" check --porcelain 2>&1
}
out="$(porcelain 0 0)"
eq "standalone gh-auth passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$3=="gh-auth"{print $1; exit}')"
eq "standalone British passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$3=="input-british"{print $1; exit}')"
eq "standalone pointer passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$3=="pointer-size"{print $1; exit}')"
out="$(porcelain 0 1)"
eq "standalone op not signed in is by hand" "hand" "$(printf '%s\n' "$out" | awk -F'|' '$3=="1password-cli"{print $1; exit}')"
out="$(porcelain 1 0)"
eq "standalone gh signed out is a warning" "warn" "$(printf '%s\n' "$out" | awk -F'|' '$3=="gh-auth"{print $1; exit}')"

printf 'session-checks tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
