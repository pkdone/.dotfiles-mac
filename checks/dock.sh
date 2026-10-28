# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.

# ---- space kept for the Dock ----------------------------------------------
# macOS normally takes the Dock out of each display's usable area, so a window
# that fills the screen stops at the Dock. After an OS update or a display
# reconnect it can stop doing that while the Dock is still drawn, and Fill puts
# windows under it. Restarting the Dock brings the space back.
# These helpers always exit 0: macconfig-check.sh runs under set -euo pipefail.

# Hammerspoon and NSScreen each print one line per display: the full frame,
# then the usable frame, "x y w h x y w h", in Hammerspoon's coordinates
# (origin at the top left of the main display, y grows down).
DOCK_SPACE_HS_CODE='local t = {}
for _, s in ipairs(hs.screen.allScreens()) do
  local f, v = s:fullFrame(), s:frame()
  local n = {f.x, f.y, f.w, f.h, v.x, v.y, v.w, v.h}
  for i, x in ipairs(n) do n[i] = string.format("%d", math.floor(x + 0.5)) end
  t[#t + 1] = table.concat(n, " ")
end
return table.concat(t, "\n")'
# NSScreen's origin is the bottom left of the first screen, y grows up.
DOCK_SPACE_JXA_CODE='ObjC.import("AppKit");
var s = $.NSScreen.screens, out = [];
var top = s.objectAtIndex(0).frame.size.height;
for (var i = 0; i < s.count; i++) {
  var f = s.objectAtIndex(i).frame, v = s.objectAtIndex(i).visibleFrame;
  out.push([f.origin.x, top - f.origin.y - f.size.height, f.size.width, f.size.height,
    v.origin.x, top - v.origin.y - v.size.height, v.size.width, v.size.height]
    .map(function (n) { return Math.round(n); }).join(" "));
}
out.join("\n");'

# dock_frame_lines — keep only lines of eight whole numbers from stdin.
dock_frame_lines() {
  awk 'NF == 8 { for (i = 1; i <= 8; i++) if ($i !~ /^-?[0-9]+$/) next; print }'
}

# dock_screen_frames — the frame lines for every display. Hammerspoon's hs
# when Hammerspoon is running and answers, otherwise NSScreen through
# osascript. Prints nothing when neither works.
dock_screen_frames() {
  local out=""
  if command -v hs >/dev/null 2>&1 && pgrep -xq Hammerspoon 2>/dev/null; then
    out="$(with_timeout 10 hs -c "$DOCK_SPACE_HS_CODE" </dev/null 2>/dev/null || true)"
    out="$(printf '%s\n' "$out" | dock_frame_lines)"
  fi
  if [ -z "$out" ] && command -v osascript >/dev/null 2>&1; then
    out="$(with_timeout 10 osascript -l JavaScript -e "$DOCK_SPACE_JXA_CODE" </dev/null 2>/dev/null || true)"
    out="$(printf '%s\n' "$out" | dock_frame_lines)"
  fi
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  fi
}

# dock_space_verdict EDGE — read frame lines on stdin, EDGE is bottom, left or
# right. Prints one line:
#   ok|POINTS                  a display keeps POINTS for the Dock on that edge
#   missing|X,Y WxH|WxH        none does; the usable and full size of the first
#                              display that shows the menu bar
#   menubar                    none does, and no display keeps the menu bar
#                              either (a full-screen app), so it can't be told
# and nothing at all when there are no frame lines.
dock_space_verdict() {
  awk -v edge="$1" -v min="${DOCK_SPACE_MIN:-8}" '
    BEGIN { best = 0 }
    NF == 8 {
      n++
      top = $6 - $2
      gap = ($2 + $4) - ($6 + $8)
      if (edge == "left") gap = $5 - $1
      if (edge == "right") gap = ($1 + $3) - ($5 + $7)
      if (gap > best) best = gap
      if (top > 0 && shown == "") shown = $5 "," $6 " " $7 "x" $8 "|" $3 "x" $4
    }
    END {
      if (!n) exit
      if (best >= min) print "ok|" best
      else if (shown != "") print "missing|" shown
      else print "menubar"
    }'
}

# dock_autohide_on — 0 when "Automatically hide and show the Dock" is on.
dock_autohide_on() {
  case "$(defaults read com.apple.dock autohide 2>/dev/null || true)" in
    1|true|TRUE|YES|yes) return 0 ;;
  esac
  return 1
}

# dock_orientation — bottom, left or right. Unset is bottom.
dock_orientation() {
  case "$(defaults read com.apple.dock orientation 2>/dev/null || true)" in
    left) printf 'left\n' ;;
    right) printf 'right\n' ;;
    *) printf 'bottom\n' ;;
  esac
}

# dock_edge_words EDGE — "at the bottom" / "on the left" / "on the right".
dock_edge_words() {
  case "$1" in
    left|right) printf 'on the %s' "$1" ;;
    *) printf 'at the bottom' ;;
  esac
}

# dock_space_restart — the --fix for dock-space. Restart the Dock, wait up to
# DOCK_SPACE_WAIT seconds for macOS to keep its space again, and say what it
# keeps now. 0 = the space is back, 1 = it is not.
# macos.sh and desktop-bindings.py run first and may have restarted the Dock
# already. When the space is back it is left alone. When killall finds no Dock,
# launchd is still starting it, so this waits the same way.
dock_space_restart() {
  local edge verdict="" i=0 rest did="restarted the Dock"
  edge="$(dock_orientation)"
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "would restart the Dock (killall Dock) and measure the screen again"
    return 0
  fi
  verdict="$(dock_screen_frames | dock_space_verdict "$edge")"
  case "$verdict" in
    ok\|*)
      echo "macOS already keeps ${verdict#ok|} points for the Dock $(dock_edge_words "$edge") again (an earlier Dock restart in this --fix brought it back)"
      return 0
      ;;
  esac
  if ! killall Dock >/dev/null 2>&1; then
    did="found no Dock to restart (it was still starting)"
  fi
  verdict=""
  while [ "$i" -lt "${DOCK_SPACE_WAIT:-10}" ]; do
    sleep 1
    i=$((i + 1))
    verdict="$(dock_screen_frames | dock_space_verdict "$edge")"
    case "$verdict" in ok\|*) break ;; esac
  done
  case "$verdict" in
    ok\|*)
      echo "$did; macOS keeps ${verdict#ok|} points for it $(dock_edge_words "$edge") again"
      return 0
      ;;
    missing\|*)
      rest="${verdict#missing|}"
      echo "$did, but macOS still isn't keeping space for it (usable area ${rest%%|*} of ${rest#*|})"
      return 1
      ;;
  esac
  echo "$did, but the screen could not be measured afterwards"
  return 1
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

# ---- 4. Dock ------------------------------------------------------------
hdr "Dock"
fixid dock-apps
if ! command -v dockutil >/dev/null 2>&1; then
  fixid tooling
  warn "dockutil not installed — run brewsync (skipping Dock check)"
else
  # dockutil --list is tab-separated: label \t file://URL \t section \t plist \t bundle-id
  # We compare by PATH (mirrors how dock.sh pins apps). Only %20 needs decoding for our
  # paths. A * in an expected path is a glob and matches the installed app path.
  url_to_path() { local p="${1#file://}"; p="${p%/}"; printf '%s' "${p//%20/ }"; }

  expected_paths=(); expected_names=()
  while IFS='|' read -r name path manual; do
    case "$name" in ''|'#'*) continue ;; esac
    path="${path/@HOME@/$HOME}"
    # A manual-step app that is not on disk yet is not drift. The Dock check
    # says so, and the order comparison uses the apps that are installed.
    if [ -n "${manual:-}" ] && [ ! -e "$path" ]; then
      CHECKED=$((CHECKED + 1))
      fixid manual-step
      warn "$name is missing because the manual step hasn't been done (${manual#manual:})"
      fixid dock-apps
      continue
    fi
    expected_names+=("$name"); expected_paths+=("$path")
  done < "$DOTDIR/lib/dock-apps.list"

  actual_paths=()
  while IFS=$'\t' read -r _label url _rest; do
    [ -z "$url" ] && continue
    actual_paths+=("$(url_to_path "$url")")
  done < <(dockutil --list)

  CHECKED=$((CHECKED + 1))
  mism=0
  if [ "${#actual_paths[@]}" -ne "${#expected_paths[@]}" ]; then
    bad "Dock has ${#actual_paths[@]} app(s), expected ${#expected_paths[@]}"
    mism=$((mism + 1))
  fi
  n=${#expected_paths[@]}
  if [ "${#actual_paths[@]}" -lt "$n" ]; then n=${#actual_paths[@]}; fi
  i=0
  while [ "$i" -lt "$n" ]; do
    exp="${expected_paths[$i]}"; act="${actual_paths[$i]}"
    # shellcheck disable=SC2254  # $exp is an intentional glob pattern when the list uses *
    case "$act" in
      $exp) : ;;
      *) bad "Dock #$((i + 1)): $act (expected ${expected_names[$i]} ~ $exp)"; mism=$((mism + 1)) ;;
    esac
    i=$((i + 1))
  done
  if [ "$mism" -eq 0 ]; then
    pass "Dock matches lib/dock-apps.list (${#expected_paths[@]} apps, in order)"
  fi
fi

# A Dock that hides itself never has space kept for it. A screen that can't be
# measured is left out silently.
fixid dock-space
if dock_autohide_on; then
  skip "the Dock hides itself, so macOS keeps no space for it — not checked"
else
  dock_edge="$(dock_orientation)"
  dock_verdict="$(dock_screen_frames | dock_space_verdict "$dock_edge")"
  case "$dock_verdict" in
    ok\|*)
      CHECKED=$((CHECKED + 1))
      pass "macOS keeps ${dock_verdict#ok|} points for the Dock $(dock_edge_words "$dock_edge") of the screen"
      ;;
    missing\|*)
      CHECKED=$((CHECKED + 1))
      dock_rest="${dock_verdict#missing|}"
      warn "The Dock is showing but macOS isn't keeping space for it, so Fill puts windows under it (usable area ${dock_rest%%|*} of ${dock_rest#*|}, nothing kept $(dock_edge_words "$dock_edge")). Restarting the Dock fixes it"
      ;;
    menubar)
      skip "the menu bar is hidden too (a full-screen app?), so the space kept for the Dock can't be measured"
      ;;
  esac
fi
