#!/usr/bin/env bash
#
# scripts/reset-folder-views.sh and macconfig --reset-folder-views: delete the
# .DS_Store files under a temp HOME (Desktop included), never inside
# ~/Library, ~/.Trash, hidden folders, node_modules or bundles, never through
# a symlink, and only regular files. --dry-run lists and deletes nothing.
# defaults, killall and PlistBuddy are stand-ins; PATH is the hermetic one.
# Run: ./tests/reset-folder-views.test.sh
#
# The script prints paths as a literal ~/..., so the expected strings do too.
# shellcheck disable=SC2088
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
RESET="$DIR/scripts/reset-folder-views.sh"
CHECK="$DIR/macconfig-check.sh"

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
present() { if [ -e "$2" ] || [ -L "$2" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL: %s\n  missing file: %s\n' "$1" "$2"; fi; }
gone() { if [ -e "$2" ] || [ -L "$2" ]; then
  fail=$((fail + 1)); printf 'FAIL: %s\n  still there: %s\n' "$1" "$2"; else pass=$((pass + 1)); fi; }

tmp="$(mktemp -d)"
home="$tmp/home"
bin="$tmp/bin"
plist="$tmp/finder.plist"
dlog="$tmp/defaults.log"
klog="$tmp/killall.log"
plog="$tmp/plistbuddy.log"
mounted=""
cleanup() {
  if [ -n "$mounted" ]; then sudo -n umount "$mounted" 2>/dev/null || true; fi
  chmod -R u+rwx "$tmp" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$bin" "$home"
: > "$dlog"; : > "$klog"; : > "$plog"

cat > "$bin/defaults" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DEFAULTS_LOG:?}"
if [ "${1:-}" = export ] && [ "${2:-}" = com.apple.finder ]; then
  [ -f "${FINDER_PLIST:?}" ] && cat "$FINDER_PLIST"
  exit 0
fi
echo "unexpected defaults: $*" >&2
exit 1
EOF
cat > "$bin/killall" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${KILLALL_LOG:?}"
exit 0
EOF
cat > "$bin/PlistBuddy" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${PLISTBUDDY_LOG:?}"
exit 1
EOF
chmod +x "$bin/defaults" "$bin/killall" "$bin/PlistBuddy"

SAFE="$(hermetic_safe_root)"
run() { # args... — the reset script under the temp HOME and hermetic PATH
  HOME="$home" PATH="$bin:$SAFE" FINDER_PLIST="$plist" DEFAULTS_LOG="$dlog" \
    KILLALL_LOG="$klog" PLISTBUDDY_LOG="$plog" "$@" 2>&1
}

write_plist() { # desktop arrangeBy
  /usr/bin/python3 - "$plist" "$1" <<'PY'
import plistlib, sys
path, desk = sys.argv[1], sys.argv[2]
iv = {"iconSize": 72.0, "textSize": 13.0, "arrangeBy": "name"}
pl = {
    "StandardViewSettings": {"IconViewSettings": dict(iv)},
    "FK_StandardViewSettings": {"IconViewSettings": dict(iv)},
    "DesktopViewSettings": {"IconViewSettings": {"iconSize": 64, "arrangeBy": desk}},
}
plistlib.dump(pl, open(path, "wb"), fmt=plistlib.FMT_BINARY)
PY
}

ds() { mkdir -p "$home/$1"; printf 'view\n' > "$home/$1/.DS_Store"; }

# Removed: folders Finder shows.
ds .
ds Desktop
ds Documents
ds "Documents/Old Projects"
ds Developer
ds Developer/repo
ds Pictures
ds Pictures/Screenshots
# Kept: pruned folders.
ds Library
ds "Library/Application Support/Foo"
ds .Trash
ds .cursor/projects
ds Developer/repo/.git
ds Developer/repo/node_modules/pkg
ds "Applications/Tool.app/Contents"
ds "Pictures/Photos Library.photoslibrary"
ds "Music/Music/Music Library.musiclibrary"
# Kept: not a regular file, or reached only through a symlink.
mkdir -p "$home/Music/.DS_Store"
mkdir -p "$home/Movies"
printf 'target\n' > "$tmp/outside-target"
ln -s "$tmp/outside-target" "$home/Movies/.DS_Store"
mkdir -p "$tmp/outside"
printf 'view\n' > "$tmp/outside/.DS_Store"
ln -s "$tmp/outside" "$home/Linked"
# A name that only looks like one.
printf 'x\n' > "$home/Documents/.DS_Store.bak"

write_plist name

# ---- dry run --------------------------------------------------------------
out="$(run "$RESET" --dry-run)"
rc=$?
eq "dry run exits 0" 0 "$rc"
has "dry run lists the home folder" "  ~/.DS_Store" "$out"
has "dry run lists the Desktop" "~/Desktop/.DS_Store" "$out"
has "dry run lists a folder with a space" "~/Documents/Old Projects/.DS_Store" "$out"
has "dry run lists Screenshots" "~/Pictures/Screenshots/.DS_Store" "$out"
has "dry run lists a repo folder" "~/Developer/repo/.DS_Store" "$out"
has "dry run gives the count" "Would remove 8 .DS_Store file(s)" "$out"
has "dry run says Finder would restart" "then restart Finder (dry-run)" "$out"
miss "dry run skips Library" "Library" "$out"
miss "dry run skips the Trash" ".Trash" "$out"
miss "dry run skips hidden folders" ".cursor" "$out"
miss "dry run skips .git" ".git/" "$out"
miss "dry run skips node_modules" "node_modules" "$out"
miss "dry run skips app bundles" "Tool.app" "$out"
miss "dry run skips the Photos library" "photoslibrary" "$out"
miss "dry run skips the Music library" "musiclibrary" "$out"
miss "dry run skips a .DS_Store folder" "~/Music/.DS_Store" "$out"
miss "dry run skips a .DS_Store symlink" "~/Movies/.DS_Store" "$out"
miss "dry run does not follow a linked folder" "~/Linked" "$out"
miss "dry run skips a look-alike name" ".DS_Store.bak" "$out"
present "dry run deletes nothing" "$home/Desktop/.DS_Store"
present "dry run leaves the home folder file" "$home/.DS_Store"
eq "dry run does not restart Finder" "" "$(cat "$klog")"
eq "dry run does not read defaults" "" "$(cat "$dlog")"

# ---- real run -------------------------------------------------------------
out="$(run "$RESET")"
rc=$?
eq "real run exits 0" 0 "$rc"
has "real run gives the count" "Removed 8 .DS_Store file(s) under ~" "$out"
has "real run restarts Finder" "Finder restarted" "$out"
eq "real run calls killall Finder once" "Finder" "$(cat "$klog")"
miss "a matching default gives no hint" "macconfig --fix" "$out"
gone "home folder view removed" "$home/.DS_Store"
gone "Desktop view removed" "$home/Desktop/.DS_Store"
gone "Documents view removed" "$home/Documents/.DS_Store"
gone "folder with a space removed" "$home/Documents/Old Projects/.DS_Store"
gone "Developer view removed" "$home/Developer/.DS_Store"
gone "repo view removed" "$home/Developer/repo/.DS_Store"
gone "Pictures view removed" "$home/Pictures/.DS_Store"
gone "Screenshots view removed" "$home/Pictures/Screenshots/.DS_Store"
present "Library kept" "$home/Library/.DS_Store"
present "Library subfolder kept" "$home/Library/Application Support/Foo/.DS_Store"
present "Trash kept" "$home/.Trash/.DS_Store"
present "hidden folder kept" "$home/.cursor/projects/.DS_Store"
present ".git kept" "$home/Developer/repo/.git/.DS_Store"
present "node_modules kept" "$home/Developer/repo/node_modules/pkg/.DS_Store"
present "app bundle kept" "$home/Applications/Tool.app/Contents/.DS_Store"
present "Photos library kept" "$home/Pictures/Photos Library.photoslibrary/.DS_Store"
present "Music library kept" "$home/Music/Music/Music Library.musiclibrary/.DS_Store"
present "a .DS_Store folder is kept" "$home/Music/.DS_Store"
present "a .DS_Store symlink is kept" "$home/Movies/.DS_Store"
present "a symlink's target is kept" "$tmp/outside-target"
present "a linked folder's file is kept" "$tmp/outside/.DS_Store"
present "a look-alike name is kept" "$home/Documents/.DS_Store.bak"
present "the folders themselves are kept" "$home/Pictures/Screenshots"
eq "PlistBuddy is never called" "" "$(cat "$plog")"
has "real run is logged" "Removed 8 .DS_Store file(s)" "$(cat "$home/Library/Logs/com.pdone.reset-folder-views.log")"

# ---- nothing left, and an unsorted Desktop default -----------------------
: > "$klog"
write_plist none
out="$(run "$RESET")"
rc=$?
eq "a second run exits 0" 0 "$rc"
has "a second run removes nothing" "Removed 0 .DS_Store file(s)" "$out"
eq "a second run still restarts Finder" "Finder" "$(cat "$klog")"
has "an unsorted default points at --fix" "Finder's default view is not Sort By Name yet. Run: macconfig --fix" "$out"
out="$(run "$RESET" --dry-run)"
has "an empty dry run says nothing would change" "Nothing would change" "$out"

# ---- permission denied stays quiet ---------------------------------------
if [ "$(id -u)" != 0 ]; then
  ds Documents/locked
  chmod 000 "$home/Documents/locked"
  ds Documents/readonly
  chmod 555 "$home/Documents/readonly"
  ds Downloads
  : > "$klog"
  out="$(run "$RESET")"
  rc=$?
  eq "unreadable folders still exit 0" 0 "$rc"
  miss "no Permission denied noise" "Permission denied" "$out"
  has "an undeletable file is counted" "1 could not be removed (permission), left alone" "$out"
  has "the rest is still removed" "Removed 1 .DS_Store file(s)" "$out"
  gone "Downloads view removed" "$home/Downloads/.DS_Store"
  chmod 755 "$home/Documents/locked" "$home/Documents/readonly"
  present "an undeletable file is left alone" "$home/Documents/readonly/.DS_Store"
  present "an unreadable folder's file is left alone" "$home/Documents/locked/.DS_Store"
  eq "Finder still restarts" "Finder" "$(cat "$klog")"
else
  echo "reset-folder-views: running as root, permission cases skipped"
fi

# ---- another volume mounted under HOME is skipped -------------------------
if [ "$(uname -s)" = Linux ] && sudo -n true 2>/dev/null; then
  mkdir -p "$home/Mounted"
  # --configured-mac stubs sudo, so a zero exit is not proof of a mount.
  if sudo -n mount -t tmpfs -o "size=1m,uid=$(id -u)" tmpfs "$home/Mounted" 2>/dev/null \
    && [ "$(stat -c %d "$home/Mounted")" != "$(stat -c %d "$home")" ]; then
    mounted="$home/Mounted"
    printf 'view\n' > "$home/Mounted/.DS_Store"
    ds Movies/clips
    out="$(run "$RESET" --dry-run)"
    miss "a mounted volume is not listed" "~/Mounted" "$out"
    has "the home volume is still listed" "~/Movies/clips/.DS_Store" "$out"
    run "$RESET" >/dev/null
    present "a mounted volume's file is kept" "$home/Mounted/.DS_Store"
  else
    echo "reset-folder-views: no tmpfs mount, volume case skipped"
  fi
else
  echo "reset-folder-views: no sudo mount here, volume case skipped"
fi

# ---- arguments ------------------------------------------------------------
out="$(run "$RESET" --bogus)"
eq "an unknown argument exits 2" 2 "$?"
has "an unknown argument is named" "--bogus" "$out"
out="$(run "$RESET" --help)"
eq "--help exits 0" 0 "$?"
has "--help says views are lost" "icon positions are lost" "$out"
out="$(HOME="$tmp/nowhere" PATH="$bin:$SAFE" "$RESET" --dry-run 2>&1)"
eq "a missing HOME exits 1" 1 "$?"

# ---- macconfig --reset-folder-views ---------------------------------------
ds Desktop
: > "$klog"; : > "$dlog"
out="$(run "$CHECK" --reset-folder-views --dry-run)"
eq "macconfig dry run exits 0" 0 "$?"
has "macconfig dry run lists the Desktop" "~/Desktop/.DS_Store" "$out"
miss "macconfig dry run runs no checks" "Summary" "$out"
present "macconfig dry run deletes nothing" "$home/Desktop/.DS_Store"
eq "macconfig dry run does not restart Finder" "" "$(cat "$klog")"
out="$(run "$CHECK" --no-color --reset-folder-views)"
eq "macconfig reset exits 0" 0 "$?"
gone "macconfig reset removes the Desktop view" "$home/Desktop/.DS_Store"
eq "macconfig reset restarts Finder" "Finder" "$(cat "$klog")"
miss "macconfig reset runs no checks" "Summary" "$out"
for combo in "--fix" "--health-json" "--only finder" "--issues"; do
  # shellcheck disable=SC2086
  out="$(run "$CHECK" --reset-folder-views $combo)"
  eq "--reset-folder-views with $combo exits 2" 2 "$?"
  has "--reset-folder-views with $combo says why" "runs on its own" "$out"
done
out="$(run "$CHECK" --dry-run)"
eq "--dry-run alone still exits 2" 2 "$?"
has "--help names the reset" "--reset-folder-views" "$(run "$CHECK" --help)"

# The drift check and --fix never reach the reset script: macconfig-check.sh
# runs it only from the --reset-folder-views branch, and nothing else calls it.
callers="$(cd "$DIR" && grep -rln 'reset-folder-views\.sh"' --include='*.sh' --include='*.list' --include='*.py' --include='*.fish' . \
  | grep -v '^./tests/' | sort | tr '\n' ' ')"
eq "only macconfig-check.sh runs the reset script" "./macconfig-check.sh " "$callers"
branch="$(awk '/RESET_VIEWS" = 1 \]; then/{on=1} on{print} on && /^fi$/{exit}' "$CHECK")"
# shellcheck disable=SC2016
has "the reset branch execs the script" 'exec "$DOTDIR/scripts/reset-folder-views.sh"' "$branch"
eq "the reset script is not in autofix.list" "" "$(grep -n 'reset-folder-views\.sh' "$DIR/lib/autofix.list" || true)"

printf 'reset-folder-views tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
