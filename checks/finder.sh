# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# CHECK_PART=icon|recents. The runner calls this twice so the two Finder
# sections stay in their original places in the report.
case "${CHECK_PART:-}" in
icon)
# ---- 9b. Finder icon-view defaults (72 / 13) ------------------------------
hdr "Finder icon view defaults"
fixid finder-icon-view
CHECKED=$((CHECKED + 1))
pin="$DOTDIR/scripts/pin-finder-icon-view.sh"
if [ ! -x "$pin" ]; then
  fixid repo-file; bad "scripts/pin-finder-icon-view.sh missing"
elif "$pin" --check >/dev/null 2>&1; then
  pass "Finder icon view defaults iconSize=72 textSize=13"
else
  bad "Finder icon view defaults drifted ($("$pin" --check 2>&1 || true)) — run macos.sh"
fi
;;
recents)
# ---- 12. Finder sidebar Recents ----
hdr "Finder sidebar Recents"
fixid finder-recents
CHECKED=$((CHECKED + 1))
helper="$DOTDIR/lib/finder-sidebar-recents.py"
if [ ! -r "$helper" ]; then
  fixid tooling; warn "lib/finder-sidebar-recents.py missing — skip"
elif [ -z "$DOT_PYTHON" ]; then
  fixid tooling; warn "python3 not found — skip Finder Recents"
else
  # Guard exit status: with set -e, a failing $(...) aborts before rc= is set.
  out="$("$DOT_PYTHON" "$helper" 2>&1)" && rc=0 || rc=$?
  if [ "$rc" = 3 ] || printf '%s\n' "$out" | rg -q 'tcc=denied|Operation not permitted|PermissionError'; then
    fixid tcc; warn "Finder Recents unreadable (Full Disk Access) — System Settings → Privacy & Security → Full Disk Access → enable Ghostty"
  elif [ "$rc" = 0 ]; then
    pass "Finder sidebar Recents hidden"
  else
    bad "Finder sidebar Recents not hidden ($out) — run macos.sh"
  fi
fi
;;
*)
  echo "checks/finder.sh: CHECK_PART must be icon or recents" >&2
  exit 1
  ;;
esac
