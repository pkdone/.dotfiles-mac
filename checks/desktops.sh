# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 4b. Dock "Assign To" desktop pins ----------------------------------
# Read-only here. --fix writes the drifted bundles back (same Desktop N → Space
# UUID map) via the desktop fixer below.
hdr "Desktop assignments (Dock → Options → Assign To)"
fixid desktop-assign
if PY="$(dot_python)"; then
  while IFS='|' read -r status bundle msg; do
    [ -z "$status" ] && continue
    case "$status" in
      ok)  CHECKED=$((CHECKED + 1)); pass "$msg" ;;
      bad) CHECKED=$((CHECKED + 1)); fixid desktop-assign "$bundle"; bad "$msg" ;;
      # The app is not installed yet, so this pin does not apply. The manual
      # step is separate. skip prints the info line and does not count it.
      skip) skip "$msg" ;;
      *)   CHECKED=$((CHECKED + 1)); fixid tooling; warn "${msg:-$bundle}" ;;
    esac
  done < <("$PY" "$DOTDIR/lib/desktop-bindings.py" "$DOTDIR/lib/desktop-bindings.list")
else
  CHECKED=$((CHECKED + 1))
  fixid tooling; warn "no python3 — skipping desktop assignment check"
fi
