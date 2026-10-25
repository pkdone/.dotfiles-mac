# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# CHECK_PART=icon|recents. The runner calls this twice so the two Finder
# sections stay in their original places in the report.
# scripts/manual-steps.sh calls check_step_finder_sidebar (@macconfig:finder).
check_step_finder_sidebar() {
  fixid finder-sidebar
  fav_base="$HOME/Library/Application Support/com.apple.sharedfilelist"
  fav_have=0
  for fav_ext in sfl4 sfl3 sfl2; do
    if [ -f "$fav_base/com.apple.LSSharedFileList.FavoriteItems.$fav_ext" ]; then
      fav_have=1
      break
    fi
  done
  if [ "$fav_have" = 0 ]; then
    note "Finder Favorites file is missing (~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl4). Finder may not create it until the sidebar is edited, so this can't be checked"
  fi
  side_rows="$DOTDIR/lib/finder-sidebar-rows.py"
  side_rules="$DOTDIR/lib/finder-sidebar-rows.list"
  if [ ! -r "$side_rows" ] || [ ! -r "$side_rules" ]; then
    CHECKED=$((CHECKED + 1))
    fixid repo-file
    warn "sidebar row files missing — skip"
  elif [ -z "$DOT_PYTHON" ]; then
    info "no python3 — Finder sidebar rows stay by hand"
  else
    side_out="$(with_timeout 20 "$DOT_PYTHON" "$side_rows" --list "$side_rules" </dev/null 2>/dev/null || true)"
    side_n=0
    while IFS='|' read -r side_st side_id side_row_msg; do
      [ -n "$side_st" ] || continue
      case "$side_st" in
        ok)
          CHECKED=$((CHECKED + 1))
          side_n=$((side_n + 1))
          pass "$side_row_msg"
          ;;
        warn)
          CHECKED=$((CHECKED + 1))
          side_n=$((side_n + 1))
          fixid finder-sidebar
          warn "$side_row_msg"
          ;;
        info) info "$side_row_msg" ;;
        *)
          CHECKED=$((CHECKED + 1))
          fixid tooling
          warn "${side_row_msg:-$side_st}"
          ;;
      esac
    done <<SIDE_ROWS
$side_out
SIDE_ROWS
    if [ "$side_n" -eq 0 ] && ! printf '%s\n' "$side_out" | grep -q '^info|'; then
      info "Finder sidebar rows could not be read, so they stay by hand"
    fi
  fi
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

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

# ---- Finder sidebar Favorites (sidebar file, check only) ----
# lib/sidebar-favorites.list is the order. The check reads
# FavoriteItems.sfl4, or sfl3, or sfl2. A match is left alone. A difference
# is a warning: writing that file is not reliable, so --fix does not change
# it. Rows that are not files (AirDrop and similar) are not part of this list.
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
else
  side_line="$("$DOT_PYTHON" "$side_helper" compare --list "$side_list" || true)"
  side_status="${side_line%%|*}"
  side_msg="${side_line#*|}"
  case "$side_status" in
    ok) pass "$side_msg" ;;
    info) info "$side_msg" ;;
    bad) warn "$side_msg — set them in Finder. macconfig --fix does not change Favorites" ;;
    *) warn "${side_msg:-Finder Favorites could not be read}" ;;
  esac
fi

# ---- Finder sidebar rows (named rows only, check only) ------------------
# lib/finder-sidebar-rows.list is Shared at the top, AirDrop and iCloud Drive
# hidden, and the home folder, Macintosh HD, Network, and Trash visible.
# A row the sidebar files do not name is an info line (still by hand).
# Tags collapsed is the defaults key SidebarTagsSctionDisclosedState. Recents
# hidden is the section above. --fix does not write the sidebar files.
# Manual step finder-sidebar points here.
hdr "Finder sidebar rows"
check_step_finder_sidebar

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
