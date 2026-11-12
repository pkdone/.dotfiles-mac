#!/usr/bin/env bash
#
# bootstrap.sh keeps going when a step exits non-zero. The log wrapper tees
# the whole run, so this drives a copy of bootstrap with stub steps and checks
# the real exit status, the manual-steps list, and the log path.
# Run: ./tests/bootstrap.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

cat > "$tmp/stub.sh" <<'EOF'
#!/bin/bash
name="$(basename "$0")"
printf 'STEP %s' "$name"
if [ "$#" -gt 0 ]; then
  printf ' %s' "$*"
fi
printf '\n'
if [ -n "${FAIL_STEP:-}" ] && [ "$name" = "$FAIL_STEP" ]; then
  echo "$name blew up" >&2
  exit 7
fi
exit 0
EOF
chmod +x "$tmp/stub.sh"

make_sandbox() {
  local sandbox="$1" s
  mkdir -p "$sandbox/lib" "$sandbox/scripts"
  cp "$DIR/bootstrap.sh" "$sandbox/bootstrap.sh"
  cp "$DIR/lib/dotfiles-log.sh" "$sandbox/lib/dotfiles-log.sh"
  cp "$DIR/lib/fleet-apps.sh" "$sandbox/lib/fleet-apps.sh"
  cp "$DIR/lib/session-checks.sh" "$sandbox/lib/session-checks.sh"
  cp "$DIR/scripts/manual-steps.sh" "$sandbox/scripts/manual-steps.sh"
  cp "$DIR/lib/manual-steps.list" "$sandbox/lib/manual-steps.list"
  for s in install.sh shell.sh hostname.sh macos.sh dock.sh handlers.sh prune-apps.sh; do
    cp "$tmp/stub.sh" "$sandbox/$s"
    chmod +x "$sandbox/$s"
  done
  chmod +x "$sandbox/bootstrap.sh"
}

# ---- a failed step does not stop the rest; the run exits non-zero ----
fail_home="$tmp/home-fail"
fail_sandbox="$tmp/fail-repo"
make_sandbox "$fail_sandbox"
fail_out="$(HOME="$fail_home" FAIL_STEP=handlers.sh "$fail_sandbox/bootstrap.sh" --yes 2>&1)"
fail_rc=$?
eq "failed step exits non-zero" 1 "$fail_rc"
has "install still ran" "STEP install.sh" "$fail_out"
has "the failing step ran" "STEP handlers.sh" "$fail_out"
has "prune-apps still ran" "STEP prune-apps.sh" "$fail_out"
has "manual-steps list still prints" "Manual steps" "$fail_out"
has "failure summary names the step" "step 6 handlers.sh (exit 7)" "$fail_out"
has "failure summary says setup continued" "Setup still ran the rest, including the manual steps." "$fail_out"
fail_log="$(printf '%s\n' "$fail_out" | sed -n 's/^Log file: //p' | head -1)"
case "$fail_log" in
  "$fail_home/Library/Logs/dotfiles/bootstrap-"*.log) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); printf 'FAIL: summary log path\n  actual: [%s]\n' "$fail_log" ;;
esac
if [ -n "$fail_log" ] && [ -f "$fail_log" ]; then
  pass=$((pass + 1))
  has "log contains the later step" "STEP prune-apps.sh" "$(cat "$fail_log")"
  has "log contains the failure summary" "step 6 handlers.sh (exit 7)" "$(cat "$fail_log")"
else
  fail=$((fail + 1))
  echo "FAIL: log file from the summary was not written"
fi
fail_order="$(printf '%s\n' "$fail_out" | awk '
  /STEP handlers.sh/ && !h { h = NR }
  /STEP prune-apps.sh/ && !p { p = NR }
  /Manual steps/ && !m { m = NR }
  /These steps failed/ && !f { f = NR }
  END { if (h && p && m && f && h < p && p < m && m < f) print "ok"; else print "bad" }
')"
eq "failure summary comes after the later step and the manual-steps list" "ok" "$fail_order"

# ---- the same continuation on a dry run ----
dry_home="$tmp/home-dry"
dry_sandbox="$tmp/dry-repo"
make_sandbox "$dry_sandbox"
dry_out="$(HOME="$dry_home" FAIL_STEP=handlers.sh "$dry_sandbox/bootstrap.sh" --dry-run --yes 2>&1)"
dry_rc=$?
eq "dry-run with a failed preview exits non-zero" 1 "$dry_rc"
has "dry-run still previews prune-apps" "STEP prune-apps.sh --dry-run" "$dry_out"
has "dry-run still lists manual steps" "Manual steps" "$dry_out"
has "dry-run summary names the preview" "step 6 handlers.sh (exit 7)" "$dry_out"
miss "dry-run does not claim setup completed cleanly" "Setup complete." "$dry_out"

# ---- a clean run exits 0 and has no failure summary ----
ok_home="$tmp/home-ok"
ok_sandbox="$tmp/ok-repo"
make_sandbox "$ok_sandbox"
ok_out="$(HOME="$ok_home" "$ok_sandbox/bootstrap.sh" --yes 2>&1)"
ok_rc=$?
eq "clean bootstrap exits 0" 0 "$ok_rc"
has "clean run says setup complete" "Setup complete." "$ok_out"
has "clean run lists manual steps" "Manual steps" "$ok_out"
miss "clean run has no failure summary" "These steps failed." "$ok_out"

# ---- the walk-through is still offered after a failed step ----
walk_home="$tmp/home-walk"
walk_sandbox="$tmp/walk-repo"
make_sandbox "$walk_sandbox"
walk_out="$(HOME="$walk_home" FAIL_STEP=handlers.sh DOTFILES_INTERACTIVE=1 "$walk_sandbox/bootstrap.sh" 2>&1 <<'EOF'
y
y
y
y
y
y
y
y
EOF
)"
walk_rc=$?
eq "interactive run with a failed step exits non-zero" 1 "$walk_rc"
has "walk-through was reached" "stdin isn't a terminal — skipping the walk-through" "$walk_out"
has "walk-through run still names the failed step" "step 6 handlers.sh (exit 7)" "$walk_out"
walk_order="$(printf '%s\n' "$walk_out" | awk '
  /STEP prune-apps.sh/ && !p { p = NR }
  /Manual steps/ && !m { m = NR }
  /skipping the walk-through/ && !w { w = NR }
  /These steps failed/ && !f { f = NR }
  END { if (p && m && w && f && p < m && m < w && w < f) print "ok"; else print "bad" }
')"
eq "walk-through runs before the failure summary" "ok" "$walk_order"

# A missing Dock app is still named. The Desktop pin for it is applied by
# re-running dock.sh, not by a separate macconfig --fix.
boot_src="$(cat "$DIR/bootstrap.sh")"
miss "bootstrap does not send you back to macconfig --fix for the Desktop pin" \
  "macconfig --fix for the Desktop pin" "$boot_src"
has "bootstrap still says to re-run dock.sh after a manual step" "re-run dock.sh." "$boot_src"
has "bootstrap still warns about apps that are not installed" "Not installed yet" "$boot_src"
has "bootstrap dry-run previews install.sh" 'install.sh  --dry-run' "$boot_src"
has "bootstrap dry-run previews dock.sh with --list" 'dock.sh  --list' "$boot_src"

pin_home="$tmp/home-pin"
pin_sandbox="$tmp/pin-repo"
make_sandbox "$pin_sandbox"
cp "$DIR/lib/dock-apps.list" "$pin_sandbox/lib/dock-apps.list"
# The shipped Dock list has no manual: row. A fixture row keeps the
# "not set up yet" path covered.
printf '%s\n' 'Sample Web|/no/such/Sample Web.app|manual:sample-web' \
  >> "$pin_sandbox/lib/dock-apps.list"
pin_out="$(HOME="$pin_home" "$pin_sandbox/bootstrap.sh" --dry-run --yes 2>&1)"
pin_rc=$?
eq "dry-run with the Dock list exits 0" 0 "$pin_rc"
has "dry-run names a manual-step Dock app" "Not set up yet" "$pin_out"
has "dry-run names a Dock app that is not installed" "Not installed yet" "$pin_out"
has "dry-run tells you to re-run dock.sh" "re-run dock.sh." "$pin_out"
miss "dry-run output does not mention macconfig --fix" "macconfig --fix" "$pin_out"
has "dry-run previews install.sh" "STEP install.sh --dry-run" "$pin_out"
has "dry-run previews dock.sh without applying" "STEP dock.sh --list" "$pin_out"

printf 'bootstrap tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
