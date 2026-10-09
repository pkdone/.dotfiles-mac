#!/usr/bin/env bash
#
# check.sh is a shim that execs macconfig-check.sh. The macconfig fish function
# is the same program, callable from any directory. These tests stay off the
# macOS-only checks: --help and a rejected flag both exit before those run.
# Run: ./tests/macconfig.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM="$DIR/check.sh"
REAL="$DIR/macconfig-check.sh"
FISH_FN="$DIR/fish/functions/macconfig.fish"

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}

capture() {  # cmd...  — prints "rc<newline>output"
  local rc out
  out="$("$@" 2>&1)"
  rc=$?
  printf '%s\n%s' "$rc" "$out"
}

# ---- shim forwards args, output, and exit status -------------------------
help_shim="$(capture "$SHIM" --help)"
help_real="$(capture "$REAL" --help)"
eq "shim --help matches macconfig-check.sh (exit and output)" "$help_real" "$help_shim"
eq "shim --help exits 0" "0" "${help_shim%%$'\n'*}"

bad_shim="$(capture "$SHIM" --sentinel-from-shim)"
bad_real="$(capture "$REAL" --sentinel-from-shim)"
eq "shim forwards an unknown flag (exit and output)" "$bad_real" "$bad_shim"
eq "unknown flag exits 2" "2" "${bad_shim%%$'\n'*}"
case "$bad_shim" in
  *"--sentinel-from-shim"*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); printf 'FAIL: unknown-flag message names the argument\n  actual: [%s]\n' "$bad_shim" ;;
esac

dry_shim="$(capture "$SHIM" --no-color --dry-run)"
dry_real="$(capture "$REAL" --no-color --dry-run)"
eq "shim forwards multiple args (--no-color --dry-run)" "$dry_real" "$dry_shim"
eq "--dry-run without --fix exits 2" "2" "${dry_shim%%$'\n'*}"

# From another directory, so a cwd-relative exec would miss the real script.
other="$(mktemp -d)"
away_shim="$(cd "$other" && capture "$SHIM" --help)"
eq "shim --help from another directory matches" "$help_real" "$away_shim"
rmdir "$other"

# stdin stays attached (the scheduled job runs check.sh </dev/null).
stdin_shim="$(printf 'not-used\n' | "$SHIM" --help 2>&1)"
stdin_rc=$?
stdin_real="$(printf 'not-used\n' | "$REAL" --help 2>&1)"
eq "shim --help with stdin exits 0" "0" "$stdin_rc"
eq "shim --help with stdin matches macconfig-check.sh" "$stdin_real" "$stdin_shim"

# ---- fish function -------------------------------------------------------
if [ -f "$FISH_FN" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: %s exists\n' "$FISH_FN"; fi

# Needles are fixed strings (fish source). Escaping keeps them from expanding here.
if grep -F -q 'function macconfig --description' "$FISH_FN"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: macconfig has a --description\n'; fi
if grep -F -q "\$HOME/.dotfiles-mac" "$FISH_FN"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: macconfig uses the dotfiles repo path\n'; fi
if grep -F -q 'macconfig-check.sh' "$FISH_FN"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: macconfig runs macconfig-check.sh\n'; fi
if grep -F -q "\$argv" "$FISH_FN"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: macconfig passes arguments through\n'; fi

if command -v fish >/dev/null 2>&1; then
  fish_err="$(fish -n "$FISH_FN" 2>&1)"
  fish_rc=$?
  eq "fish -n macconfig.fish" "0" "$fish_rc"
  eq "fish -n prints nothing" "" "$fish_err"

  # Stand-in script under a fake HOME: proves args and the exit status come
  # back, and that the caller's directory is left alone.
  fake="$(mktemp -d)"
  mkdir -p "$fake/.dotfiles-mac"
  cat > "$fake/.dotfiles-mac/macconfig-check.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*"
printf '%s' "$PWD" > "$MACCONFIG_PWD_OUT"
exit "${MACCONFIG_EXIT:-0}"
EOF
  chmod +x "$fake/.dotfiles-mac/macconfig-check.sh"
  pwd_out="$(mktemp)"
  fish_out="$(
    HOME="$fake" MACCONFIG_PWD_OUT="$pwd_out" MACCONFIG_EXIT=7 \
      fish --no-config -c "cd /tmp; source \"$FISH_FN\"; macconfig --fix --no-color; echo STATUS:\$status"
  )"
  eq "macconfig passes args and returns the script status" "--fix --no-color
STATUS:7" "$fish_out"
  eq "macconfig leaves the working directory alone" "/tmp" "$(cat "$pwd_out")"
  rm -rf "$fake" "$pwd_out"
else
  echo "fish not installed — skipped fish -n (CI fish-syntax job still parses *.fish)"
fi

printf 'macconfig tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
