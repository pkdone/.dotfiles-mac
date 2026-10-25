#!/usr/bin/env bash
#
# Finder sidebar rows. Synthetic sfl archives only — the real sidebar is not
# opened or written. Run: ./tests/finder-sidebar-rows.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/finder-sidebar-rows.py"
LIST="$DIR/lib/finder-sidebar-rows.list"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "finder-sidebar-rows tests: python3 not found, skipped"; exit 0; fi

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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
chmod +x "$HELPER"
home="$tmp/home"
mkdir -p "$home"

eq "finder sidebar step is checked by macconfig" "@macconfig:finder" \
  "$(awk -F'|' '$1 == "finder-sidebar" { print $6; exit }' "$DIR/lib/manual-steps.list")"
miss "manual step title does not repeat that macconfig checks it" "macconfig checks this" \
  "$(awk -F'|' '$1 == "finder-sidebar" { print $3; exit }' "$DIR/lib/manual-steps.list")"
eq "finder-sidebar is report-only" "PAUL|" \
  "$(awk -F'|' '$1 == "finder-sidebar" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"
has "Tags collapsed stays a defaults row" "SidebarTagsSctionDisclosedState|bool|false" \
  "$(grep -E '^com\.apple\.finder\|SidebarTagsSctionDisclosedState\|' "$DIR/lib/macos-defaults.list")"

cat > "$tmp/write_rows.py" <<'PY'
import os
import plistlib
import struct
import sys
from plistlib import UID

HIDDEN = "com.apple.LSSharedFileList.ItemIsHidden"

def encode_bookmark(components, volume="/"):
    chunks = []
    offset = 4

    def add_item(blob):
        nonlocal offset
        rel = offset
        chunks.append(blob)
        offset += len(blob)
        if offset & 3:
            pad = 4 - (offset & 3)
            chunks.append(b"\x00" * pad)
            offset += pad
        return rel

    def add_string(text):
        raw = text.encode("utf-8")
        return add_item(struct.pack("<II", len(raw), 0x0101) + raw)

    vol_off = add_string(volume)
    comp_offs = [add_string(part) for part in components]
    payload = b"".join(struct.pack("<I", off) for off in comp_offs)
    arr_off = add_item(struct.pack("<II", len(payload), 0x0601) + payload)
    entries = sorted(((0x1004, arr_off), (0x2002, vol_off)))
    entry_blob = b"".join(struct.pack("<III", key, off, 0) for key, off in entries)
    toc_rel = offset
    chunks.append(struct.pack("<IIIII", len(entry_blob) - 8, 0xFFFFFFFE, 1, 0, len(entries)))
    chunks.append(entry_blob)
    offset += 20 + len(entry_blob)
    body = b"".join(chunks)
    header = struct.pack("<4sIIIQQQQI", b"book", offset + 48, 0x10040000, 48, 0, 0, 0, 0, toc_rel)
    return header + body

def archive(rows):
    objects = ["$null"]

    def add(obj):
        objects.append(obj)
        return UID(len(objects) - 1)

    item_uids = []
    for name, bookmark, hidden in rows:
        keys = []
        vals = []
        if name is not None:
            keys.append(add("Name"))
            vals.append(add(name))
        if bookmark is not None:
            keys.append(add("Bookmark"))
            vals.append(add(bookmark))
        if hidden is not None:
            props = {
                "NS.keys": [add(HIDDEN)],
                "NS.objects": [add(bool(hidden))],
            }
            keys.append(add("CustomItemProperties"))
            vals.append(add(props))
        item = {"NS.keys": keys, "NS.objects": vals}
        item_uids.append(add(item))
    items = {"NS.objects": item_uids}
    root = {"NS.keys": [add("items")], "NS.objects": [add(items)]}
    return {
        "$archiver": "NSKeyedArchiver",
        "$version": 100000,
        "$top": {"root": add(root)},
        "$objects": objects,
    }

def write(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        plistlib.dump(archive(rows), fh, fmt=plistlib.FMT_BINARY)

# argv: dest mode home
dest, mode, home = sys.argv[1:4]
home_parts = [part for part in home.rstrip("/").split("/") if part]
user = os.path.basename(home.rstrip("/"))
if mode == "good":
    top = [
        ("Recents", b"Recents\x00myDocuments.cannedSearch", True),
        ("Shared", None, True),
        ("AirDrop", None, True),
        (None, b"\x00com~apple~CloudDocs\x00", True),
    ]
    volumes = [
        (user, encode_bookmark(home_parts), False),
        ("Macintosh HD", encode_bookmark([], volume="/"), False),
        ("Network", None, False),
        (None, encode_bookmark([".Trash"], volume=home), False),
    ]
elif mode == "drift":
    top = [
        ("AirDrop", None, False),
        ("Shared", None, False),
        ("iCloud Drive", None, False),
    ]
    volumes = [
        ("Macintosh HD", None, True),
        ("Network", None, True),
        (user, encode_bookmark(home_parts), True),
        ("Trash", None, True),
    ]
elif mode == "partial":
    top = [("Shared", None, True)]
    volumes = [("Macintosh HD", None, False)]
else:
    raise SystemExit("unknown mode " + mode)
side = os.path.dirname(dest)
write(os.path.join(side, "top.sfl4"), top)
write(os.path.join(side, "volumes.sfl4"), volumes)
PY

run_mode() { # mode
  "$PY" "$tmp/write_rows.py" "$tmp/side/top.sfl4" "$1" "$home"
  HOME="$home" "$PY" "$HELPER" --list "$LIST" --home "$home" --user "$(basename "$home")" \
    --top "$tmp/side/top.sfl4" --volumes "$tmp/side/volumes.sfl4"
}

out="$(run_mode good)"
eq "hidden shared passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$2=="shared"{print $1}')"
has "shared pass says it is hidden" "Shared is hidden" "$out"
miss "shared is not required to be first" "first visible" "$out"
eq "airdrop hidden passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$2=="airdrop"{print $1}')"
eq "icloud marker hidden passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$2=="icloud"{print $1}')"
eq "home by path passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$2=="home"{print $1}')"
eq "macintosh hd passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$2=="macintosh-hd"{print $1}')"
eq "network passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$2=="network"{print $1}')"
eq "trash by path passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$2=="trash"{print $1}')"
miss "a complete sidebar has nothing left by hand" "stay by hand" "$out"

before="$(cksum "$tmp/side/top.sfl4"; cksum "$tmp/side/volumes.sfl4")"
run_mode good >/dev/null
eq "a passing read does not rewrite the sidebar files" "$before" "$(cksum "$tmp/side/top.sfl4"; cksum "$tmp/side/volumes.sfl4")"

out="$(run_mode drift)"
eq "visible shared warns" "warn" "$(printf '%s\n' "$out" | awk -F'|' '$2=="shared"{print $1}')"
has "visible shared says to hide it" "Hide it" "$(printf '%s\n' "$out" | awk -F'|' '$2=="shared"')"
miss "visible shared is not judged by position" "first visible" "$(printf '%s\n' "$out" | awk -F'|' '$2=="shared"')"
eq "visible airdrop warns" "warn" "$(printf '%s\n' "$out" | awk -F'|' '$2=="airdrop"{print $1}')"
eq "visible icloud warns" "warn" "$(printf '%s\n' "$out" | awk -F'|' '$2=="icloud"{print $1}')"
eq "hidden home warns" "warn" "$(printf '%s\n' "$out" | awk -F'|' '$2=="home"{print $1}')"
eq "hidden macintosh hd warns" "warn" "$(printf '%s\n' "$out" | awk -F'|' '$2=="macintosh-hd"{print $1}')"
has "a drift says macconfig does not change the sidebar" "does not change the sidebar" "$out"

out="$(run_mode partial)"
eq "named shared still passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$2=="shared"{print $1}')"
eq "named macintosh hd still passes" "ok" "$(printf '%s\n' "$out" | awk -F'|' '$2=="macintosh-hd"{print $1}')"
has "unnamed rows stay by hand" "stay by hand" "$out"
has "unnamed list includes AirDrop" "AirDrop" "$out"
has "unnamed list includes iCloud Drive" "iCloud Drive" "$out"
has "unnamed list includes the home folder" "your home folder" "$out"
miss "a named row is not also left by hand" "Macintosh HD" "$(printf '%s\n' "$out" | awk -F'|' '$1=="info"')"

printf 'not a sidebar file\n' > "$tmp/side/bad.sfl4"
out="$(HOME="$home" "$PY" "$HELPER" --list "$LIST" --home "$home" --top "$tmp/side/bad.sfl4" --volumes "$tmp/side/bad.sfl4")"
eq "an unreadable archive is info" "info" "${out%%|*}"
has "an unreadable archive stays by hand" "stay by hand" "$out"

writers="$(grep -nE 'open\(.*["'\'']wb["'\'']|plistlib.dump' "$HELPER" || true)"
eq "helper does not write a sidebar file" "" "$writers"

# A good sidebar with no FavoriteItems file: rows pass, but the manual step
# stays on screen because Favorites can't be checked yet.
run_mode good >/dev/null
fav_dir="$home/Library/Application Support/com.apple.sharedfilelist"
mkdir -p "$fav_dir"
cp "$tmp/side/top.sfl4" "$fav_dir/com.apple.LSSharedFileList.TopSidebarSection.sfl4"
cp "$tmp/side/volumes.sfl4" "$fav_dir/com.apple.LSSharedFileList.FavoriteVolumes.sfl4"
rm -f "$fav_dir"/com.apple.LSSharedFileList.FavoriteItems.sfl*
printf '%s\n' \
  'finder-sidebar|Login Items & Finder|Finder sidebar rows|Finder → Settings → Sidebar|app:Finder|@macconfig:finder' \
  > "$tmp/step.list"
mkdir -p "$tmp/bin"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/open"
chmod +x "$tmp/bin/open"
open_out="$(printf 's\n' | HOME="$home" NO_COLOR=1 MANUAL_STEPS_OPEN_TTY=1 \
  MANUAL_STEPS_LIST="$tmp/step.list" PATH="$tmp/bin:$PATH" \
  "$DIR/scripts/manual-steps.sh" open 2>"$tmp/open.err")"
eq "open of a missing FavoriteItems file exits 0" 0 "$?"
eq "open stderr stays empty" "" "$(cat "$tmp/open.err")"
has "a missing FavoriteItems file is still shown" "Finder sidebar" "$open_out"
has "a missing FavoriteItems file names the part that was checked" \
  "Checked: the sidebar rows the files name." "$open_out"
has "a missing FavoriteItems file names the part still by hand" \
  "Still by hand:" "$open_out"
has "a missing FavoriteItems file names the favorites file" \
  "FavoriteItems" "$open_out"
has "a missing FavoriteItems file is MANUAL" "MANUAL:" "$open_out"
has "a missing FavoriteItems file keeps press s" "press s." "$open_out"
miss "a missing FavoriteItems file is not labelled can't-check" \
  "Can't check this automatically" "$open_out"
miss "a passing row check is not labelled not set yet" "NOTSET:" "$open_out"

printf 'finder-sidebar-rows tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
