#!/usr/bin/env bash
#
# Finder Favorites: lib/sidebar-favorites.list, reading FavoriteItems.sfl*,
# and macos.sh reporting a difference without writing the sidebar file.
# Run: ./tests/sidebar-favorites.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/sidebar-favorites.py"
LIST="$DIR/lib/sidebar-favorites.list"
MACOS="$DIR/macos.sh"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "sidebar-favorites tests: python3 not found, skipped"; exit 0; fi

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

names="$(awk -F'|' '$1 !~ /^#/ && NF { print $1 }' "$LIST")"
eq "favorites order" "Applications
Desktop
Developer
Documents
Downloads
Movies
Music
Pictures" "$names"

brewfile="$(cat "$DIR/Brewfile")"
miss "brewfile has no mysides cask" 'cask "mysides"' "$brewfile"
miss "brewfile has no mysides formula" 'brew "mysides"' "$brewfile"
miss "macos.sh does not run mysides" "mysides list" "$(cat "$DIR/macos.sh")"
miss "finder check does not run mysides" "mysides list" "$(cat "$DIR/checks/finder.sh")"
has "finder check leaves a difference as a warning" "does not change Favorites" "$(cat "$DIR/checks/finder.sh")"
eq "favorites are check-only" "PAUL" \
  "$(awk -F'|' '$1=="finder-favorites" { print $2; exit }' "$DIR/lib/autofix.list")"

tmp="$(mktemp -d)"
backup_before=""
if [ -d "$DIR/backups" ]; then
  backup_before="$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'defaults-*' | sort)"
fi
cleanup() {
  local d now
  if [ -d "$DIR/backups" ]; then
    now="$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'defaults-*' | sort)"
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      case "$backup_before" in
        *"$d"*) ;;
        *) rm -rf "$d" ;;
      esac
    done <<< "$now"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
home="$tmp/home"
side="$home/Library/Application Support/com.apple.sharedfilelist"
mkdir -p "$home" "$side"
export HOME="$home"

cat > "$tmp/write_sfl.py" <<'PY'
import os
import plistlib
import struct
import sys
from plistlib import UID

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

def components_for(path):
    return [part for part in path.rstrip("/").split("/") if part]

def load_desired(path, home):
    rows = []
    for raw in open(path, encoding="utf-8"):
        line = raw.split("#", 1)[0].strip()
        if not line or "|" not in line:
            continue
        name, folder = line.split("|", 1)
        rows.append((name.strip(), folder.strip().replace("@HOME@", home)))
    return rows

def archive(pairs):
    objects = ["$null"]

    def add(obj):
        objects.append(obj)
        return UID(len(objects) - 1)

    item_uids = []
    for name, bookmark in pairs:
        item = {
            "NS.keys": [add("Name"), add("Bookmark")],
            "NS.objects": [add(name), add(bookmark)],
        }
        item_uids.append(add(item))
    items = {"NS.objects": item_uids}
    root = {"NS.keys": [add("items")], "NS.objects": [add(items)]}
    return {
        "$archiver": "NSKeyedArchiver",
        "$version": 100000,
        "$top": {"root": add(root)},
        "$objects": objects,
    }

def pairs_for(desired, mode):
    if mode == "match":
        return [(name, encode_bookmark(components_for(path))) for name, path in desired]
    if mode == "short":
        name, path = desired[0]
        return [(name, encode_bookmark(components_for(path)))]
    if mode == "swapped":
        rows = [(name, encode_bookmark(components_for(path))) for name, path in desired]
        rows[0], rows[1] = rows[1], rows[0]
        return rows
    if mode == "airdrop":
        rows = [(name, encode_bookmark(components_for(path))) for name, path in desired]
        rows.append(("AirDrop", b"not-a-bookmark"))
        return rows
    if mode == "noparse":
        return [("Desktop", b"not-a-bookmark"), ("Documents", b"also-no")]
    if mode == "volume":
        rows = []
        for name, path in desired:
            parent, base = os.path.split(path.rstrip("/"))
            rows.append((name, encode_bookmark([base], volume=parent or "/")))
        return rows
    raise SystemExit("unknown mode " + mode)

list_path, dest, mode, home = sys.argv[1:5]
os.makedirs(os.path.dirname(dest), exist_ok=True)
with open(dest, "wb") as fh:
    plistlib.dump(archive(pairs_for(load_desired(list_path, home), mode)), fh, fmt=plistlib.FMT_BINARY)
PY

write_sfl() { # mode dest
  "$PY" "$tmp/write_sfl.py" "$LIST" "$2" "$1" "$home"
}

sfl4="$side/com.apple.LSSharedFileList.FavoriteItems.sfl4"
sfl3="$side/com.apple.LSSharedFileList.FavoriteItems.sfl3"
write_sfl match "$sfl4"
out="$(HOME="$home" "$PY" "$HELPER" compare --list "$LIST")"
eq "matching sidebar file passes" "ok" "${out%%|*}"

write_sfl airdrop "$sfl4"
out="$(HOME="$home" "$PY" "$HELPER" compare --list "$LIST" --sfl "$sfl4")"
eq "AirDrop is not part of the comparison" "ok" "${out%%|*}"

write_sfl volume "$sfl4"
out="$(HOME="$home" "$PY" "$HELPER" compare --list "$LIST" --sfl "$sfl4")"
eq "volume path plus the last component matches" "ok" "${out%%|*}"

write_sfl short "$sfl4"
out="$(HOME="$home" "$PY" "$HELPER" compare --list "$LIST" --sfl "$sfl4")"
eq "a short list is drift" "bad" "${out%%|*}"

write_sfl swapped "$sfl4"
out="$(HOME="$home" "$PY" "$HELPER" compare --list "$LIST" --sfl "$sfl4")"
eq "wrong order is drift" "bad" "${out%%|*}"

write_sfl noparse "$sfl4"
out="$(HOME="$home" "$PY" "$HELPER" compare --list "$LIST" --sfl "$sfl4")"
eq "unreadable bookmarks are not an empty sidebar" "warn" "${out%%|*}"
has "unreadable bookmarks say the paths could not be read" "could not read paths" "$out"

rm -f "$sfl4"
write_sfl match "$sfl3"
out="$(HOME="$home" "$PY" "$HELPER" compare --list "$LIST")"
eq "sfl3 is read when sfl4 is absent" "ok" "${out%%|*}"

write_sfl short "$sfl3"
write_sfl match "$sfl4"
out="$(HOME="$home" "$PY" "$HELPER" compare --list "$LIST")"
eq "sfl4 wins when both files exist" "ok" "${out%%|*}"

rm -f "$sfl4" "$sfl3"
out="$(HOME="$home" "$PY" "$HELPER" compare --list "$LIST")"
eq "a missing sidebar file warns" "warn" "${out%%|*}"
has "a missing sidebar file names the file" "FavoriteItems.sfl4" "$out"

write_sfl match "$sfl4"
before="$(cksum "$sfl4")"
out="$(HOME="$home" "$MACOS" --no-color --yes --only @finder-favorites)"
eq "matching favorites exits 0" 0 "$?"
has "matching favorites are left alone" "Finder Favorites already match" "$out"
eq "matching favorites does not rewrite the sidebar file" "$before" "$(cksum "$sfl4")"
eq "matching favorites does not create Developer" "no" "$([ -d "$home/Developer" ] && echo yes || echo no)"

write_sfl short "$sfl4"
before="$(cksum "$sfl4")"
out="$(HOME="$home" "$MACOS" --no-color --yes --dry-run --only @finder-favorites)"
has "a difference is reported" "does not change the sidebar" "$out"
eq "dry-run does not rewrite the sidebar file" "$before" "$(cksum "$sfl4")"
eq "dry-run does not create Developer" "no" "$([ -d "$home/Developer" ] && echo yes || echo no)"

out="$(HOME="$home" "$MACOS" --no-color --yes --only @finder-favorites)"
has "a real run also leaves the sidebar alone" "does not change the sidebar" "$out"
eq "a real run does not rewrite the sidebar file" "$before" "$(cksum "$sfl4")"
eq "a real run does not create Developer" "no" "$([ -d "$home/Developer" ] && echo yes || echo no)"

printf 'sidebar-favorites tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
