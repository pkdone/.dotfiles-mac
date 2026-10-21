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

# ---- Finder sidebar Favorites (mysides) ----
# lib/sidebar-favorites.list is the order. A match is left alone. Drift is
# repaired by macos.sh --only @finder-favorites, which restarts Finder only
# when the list changed. Addresses that are not files (AirDrop and similar)
# are not part of this list.
hdr "Finder Favorites"
fixid finder-favorites
CHECKED=$((CHECKED + 1))
side_helper="$DOTDIR/lib/sidebar-favorites.py"
side_list="$DOTDIR/lib/sidebar-favorites.list"
if [ ! -r "$side_helper" ] || [ ! -r "$side_list" ]; then
  fixid repo-file
  warn "sidebar favorites files missing — skip"
elif [ -z "$DOT_PYTHON" ]; then
  fixid tooling
  warn "python3 not found — skip Finder Favorites"
elif ! command -v mysides >/dev/null 2>&1; then
  fixid tooling
  warn "mysides not installed — skip Finder Favorites (brew install mysides)"
else
  if side_out="$(with_timeout 15 mysides list </dev/null 2>&1)"; then
    side_rc=0
  else
    side_rc=$?
  fi
  if [ "$side_rc" -ne 0 ]; then
    fixid tooling
    warn "mysides list failed — Finder Favorites left unread"
  else
    side_tmp="$(mktemp)"
    printf '%s\n' "$side_out" > "$side_tmp"
    side_line="$("$DOT_PYTHON" "$side_helper" compare --list "$side_list" --mysides "$side_tmp" || true)"
    rm -f "$side_tmp"
    side_status="${side_line%%|*}"
    side_msg="${side_line#*|}"
    case "$side_status" in
      ok) pass "$side_msg" ;;
      bad) bad "$side_msg — macconfig --fix rebuilds them" ;;
      *) fixid tooling; warn "${side_msg:-Finder Favorites check failed}" ;;
    esac
  fi
fi

# ---- Show Finder menu shortcut (Cmd-Ctrl-Shift-F) ----
# One entry in the Finder menu-shortcut dictionary. Other shortcuts in that
# dictionary are left in place. --fix writes this entry with -dict-add.
hdr "Show Finder shortcut"
fixid finder-show
CHECKED=$((CHECKED + 1))
show_raw="$(defaults read com.apple.finder NSUserKeyEquivalents 2>/dev/null || true)"
show_val="$(finder_show_value "$show_raw")"
# '@^$f' is Cmd-Ctrl-Shift-F. The dollar sign is the shortcut, not a variable.
# shellcheck disable=SC2016
if [ "$show_val" = '@^$f' ]; then
  pass "Show Finder shortcut is Cmd-Ctrl-Shift-F"
else
  bad "Show Finder shortcut is ${show_val:-unset} (want Cmd-Ctrl-Shift-F) — macconfig --fix"
fi
;;
*)
  echo "checks/finder.sh: CHECK_PART must be icon or recents" >&2
  exit 1
  ;;
esac
