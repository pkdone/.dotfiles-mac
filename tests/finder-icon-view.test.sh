#!/usr/bin/env bash
#
# Finder icon view: iconSize=72, textSize=13, arrangeBy=name on
# StandardViewSettings and FK_StandardViewSettings, and arrangeBy=name on
# DesktopViewSettings. The Desktop's icon size and text size are not written.
# Fake defaults and killall only.
# Run: ./tests/finder-icon-view.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="$DIR/scripts/pin-finder-icon-view.sh"
MACOS="$DIR/macos.sh"
PY="$(command -v python3 || true)"
if [ -z "$PY" ] || [ ! -x /usr/bin/python3 ]; then
  echo "finder-icon-view tests: /usr/bin/python3 not found, skipped"
  exit 0
fi

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
ok() {
  if [ "$2" = 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s (status %s)\n' "$1" "$2"; fi
}

tmp="$(mktemp -d)"
home="$tmp/home"
bin="$tmp/bin"
plist="$tmp/finder.plist"
dlog="$tmp/defaults.log"
klog="$tmp/killall.log"
mkdir -p "$bin" "$home"
: > "$tmp/made-backups"
note_backups() {
  printf '%s\n' "$1" | awk '/backups -> / { print $NF }' >> "$tmp/made-backups"
}
cleanup() {
  local d
  while IFS= read -r d; do
    [ -n "$d" ] && rm -rf "$d"
  done < "$tmp/made-backups"
  rm -rf "$tmp"
}
trap cleanup EXIT

cat > "$bin/defaults" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DEFAULTS_LOG:?}"
cmd="${1:-}"
domain="${2:-}"
dest="${3:-}"
if [ "$cmd" = export ] && [ "$domain" = com.apple.finder ]; then
  if [ "$dest" = "-" ] || [ -z "$dest" ]; then
    cat "${FINDER_PLIST:?}"
  else
    cp "${FINDER_PLIST:?}" "$dest"
  fi
  exit 0
fi
if [ "$cmd" = import ] && [ "$domain" = com.apple.finder ]; then
  cat > "${FINDER_PLIST:?}"
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
chmod +x "$bin/defaults" "$bin/killall"

write_plist() { # python expr
  "$PY" - "$plist" "$1" <<'PY'
import plistlib, sys
path, expr = sys.argv[1], sys.argv[2]
with open(path, "wb") as fh:
    plistlib.dump(eval(expr), fh, fmt=plistlib.FMT_BINARY)
PY
}
read_iv() { # key field
  "$PY" - "$plist" "$1" "$2" <<'PY'
import plistlib, sys
pl = plistlib.load(open(sys.argv[1], "rb"))
key, field = sys.argv[2], sys.argv[3]
block = pl.get(key)
if not isinstance(block, dict):
    print("MISSING")
    raise SystemExit
iv = block.get("IconViewSettings")
if not isinstance(iv, dict) or field not in iv:
    print("MISSING")
else:
    print(iv[field])
PY
}
imports() { grep -c '^import com.apple.finder -$' "$dlog" || true; }

export FINDER_PLIST="$plist" DEFAULTS_LOG="$dlog" KILLALL_LOG="$klog"
export PATH="$bin:$PATH" HOME="$home"

write_plist '{
  "StandardViewSettings": {"IconViewSettings": {"iconSize": 64, "textSize": 12, "showItemInfo": True}},
  "FK_StandardViewSettings": {"IconViewSettings": {"iconSize": 72, "textSize": 13, "arrangeBy": "dateModified", "labelOnBottom": True}},
  "DesktopViewSettings": {"IconViewSettings": {"iconSize": 48, "textSize": 11, "arrangeBy": "none", "showItemInfo": False}},
}'
: > "$dlog"
: > "$klog"
out="$("$PIN" --check)"
rc=$?
eq "sizes without Sort By Name are drift" 1 "$rc"
has "drift names StandardViewSettings" "StandardViewSettings=64x12 arrangeBy=unset" "$out"
has "drift names the other sort" "FK_StandardViewSettings=72x13 arrangeBy=dateModified" "$out"
has "drift names the Desktop sort" "DesktopViewSettings arrangeBy=none" "$out"
eq "a check does not import" 0 "$(imports)"
eq "a check does not restart Finder" "" "$(cat "$klog")"

out="$("$PIN")"
rc=$?
ok "apply exits 0" "$rc"
has "apply says it pinned" "Finder icon view defaults pinned" "$out"
eq "apply imports once" 1 "$(imports)"
eq "apply restarts Finder" "Finder" "$(cat "$klog")"
eq "standard icon size is 72" "72.0" "$(read_iv StandardViewSettings iconSize)"
eq "standard text size is 13" "13.0" "$(read_iv StandardViewSettings textSize)"
eq "standard sort is name" "name" "$(read_iv StandardViewSettings arrangeBy)"
eq "standard keeps its other key" "True" "$(read_iv StandardViewSettings showItemInfo)"
eq "fk sort is name" "name" "$(read_iv FK_StandardViewSettings arrangeBy)"
eq "fk keeps labelOnBottom" "True" "$(read_iv FK_StandardViewSettings labelOnBottom)"
eq "desktop icon size stays 48" "48" "$(read_iv DesktopViewSettings iconSize)"
eq "desktop text size stays 11" "11" "$(read_iv DesktopViewSettings textSize)"
eq "desktop sort is name" "name" "$(read_iv DesktopViewSettings arrangeBy)"
eq "desktop keeps showItemInfo" "False" "$(read_iv DesktopViewSettings showItemInfo)"

: > "$dlog"
: > "$klog"
out="$("$PIN" --check)"
rc=$?
ok "matching arrangeBy passes" "$rc"
has "matching line names arrangeBy" "arrangeBy=name" "$out"
has "matching line names the Desktop" "Desktop arrangeBy=name" "$out"
eq "a passing check does not import" 0 "$(imports)"

: > "$dlog"
: > "$klog"
out="$("$PIN")"
rc=$?
ok "a second apply exits 0" "$rc"
eq "a second apply still imports" 1 "$(imports)"
eq "a second apply still restarts Finder" "Finder" "$(cat "$klog")"
eq "desktop sort is still name after a re-assert" "name" "$(read_iv DesktopViewSettings arrangeBy)"
eq "desktop icon size is still 48 after a re-assert" "48" "$(read_iv DesktopViewSettings iconSize)"

# macos.sh writes only when a value differs, and queues the same Finder restart.
: > "$dlog"
: > "$klog"
out="$(HOME="$home" PATH="$bin:$PATH" FINDER_PLIST="$plist" DEFAULTS_LOG="$dlog" KILLALL_LOG="$klog" \
  "$MACOS" --no-color --yes --only @finder-icon-view)"
rc=$?
note_backups "$out"
ok "macos leaves a matching icon view" "$rc"
has "macos says left alone" "already iconSize=72 textSize=13 arrangeBy=name, Desktop arrangeBy=name (left alone)" "$out"
eq "macos does not import when it matches" 0 "$(imports)"
eq "macos does not restart Finder when it matches" "" "$(cat "$klog")"

write_plist '{
  "StandardViewSettings": {"IconViewSettings": {"iconSize": 72, "textSize": 13, "arrangeBy": "name"}},
  "FK_StandardViewSettings": {"IconViewSettings": {"iconSize": 72, "textSize": 13}},
  "DesktopViewSettings": {"IconViewSettings": {"iconSize": 64, "arrangeBy": "grid"}},
}'
: > "$dlog"
: > "$klog"
out="$(HOME="$home" PATH="$bin:$PATH" FINDER_PLIST="$plist" DEFAULTS_LOG="$dlog" KILLALL_LOG="$klog" \
  "$MACOS" --no-color --yes --dry-run --only @finder-icon-view)"
rc=$?
note_backups "$out"
ok "macos dry-run exits 0" "$rc"
has "macos dry-run names Sort By Name" "Desktop arrangeBy=name (dry-run)" "$out"
eq "dry-run does not import" 0 "$(imports)"
eq "desktop sort stays grid in a dry-run" "grid" "$(read_iv DesktopViewSettings arrangeBy)"

out="$(HOME="$home" PATH="$bin:$PATH" FINDER_PLIST="$plist" DEFAULTS_LOG="$dlog" KILLALL_LOG="$klog" \
  "$MACOS" --no-color --yes --only @finder-icon-view)"
rc=$?
note_backups "$out"
ok "macos sets a missing arrangeBy" "$rc"
has "macos reports the change" "Finder icon view defaults -> iconSize=72 textSize=13 arrangeBy=name, Desktop arrangeBy=name" "$out"
has "macos restarts Finder" "Restarting to apply: Finder" "$out"
eq "fk arrangeBy is name after macos" "name" "$(read_iv FK_StandardViewSettings arrangeBy)"
eq "standard arrangeBy stays name" "name" "$(read_iv StandardViewSettings arrangeBy)"
eq "desktop sort is name after macos" "name" "$(read_iv DesktopViewSettings arrangeBy)"
eq "desktop icon size stays 64" "64" "$(read_iv DesktopViewSettings iconSize)"
eq "desktop text size stays unset" "MISSING" "$(read_iv DesktopViewSettings textSize)"

# Paul's Mac: both window defaults already match, only the Desktop is unsorted.
write_plist '{
  "StandardViewSettings": {"IconViewSettings": {"iconSize": 72, "textSize": 13, "arrangeBy": "name"}},
  "FK_StandardViewSettings": {"IconViewSettings": {"iconSize": 72, "textSize": 13, "arrangeBy": "name"}},
  "DesktopViewSettings": {"IconViewSettings": {"iconSize": 56, "textSize": 12, "arrangeBy": "none"}},
}'
: > "$dlog"
: > "$klog"
out="$("$PIN" --check)"
rc=$?
eq "an unsorted Desktop alone is drift" 1 "$rc"
has "the drift line names the Desktop" "DesktopViewSettings arrangeBy=none" "$out"
eq "that check does not restart Finder" "" "$(cat "$klog")"

out="$(HOME="$home" PATH="$bin:$PATH" FINDER_PLIST="$plist" DEFAULTS_LOG="$dlog" KILLALL_LOG="$klog" \
  "$MACOS" --no-color --yes --only @finder-icon-view)"
rc=$?
note_backups "$out"
ok "macos sorts the Desktop" "$rc"
has "macos reports the Desktop change" "Desktop arrangeBy=name" "$out"
has "macos restarts Finder for the Desktop" "Restarting to apply: Finder" "$out"
eq "desktop sort is name" "name" "$(read_iv DesktopViewSettings arrangeBy)"
eq "desktop icon size stays 56" "56" "$(read_iv DesktopViewSettings iconSize)"
eq "desktop text size stays 12" "12" "$(read_iv DesktopViewSettings textSize)"
eq "standard icon size is still 72" "72.0" "$(read_iv StandardViewSettings iconSize)"
"$PIN" --check >/dev/null
ok "the check passes after macos" "$?"

# No Desktop block yet: only the sort is written, no icon size.
write_plist '{
  "StandardViewSettings": {"IconViewSettings": {"iconSize": 72, "textSize": 13, "arrangeBy": "name"}},
  "FK_StandardViewSettings": {"IconViewSettings": {"iconSize": 72, "textSize": 13, "arrangeBy": "name"}},
}'
out="$("$PIN" --check)"
rc=$?
eq "a missing Desktop block is drift" 1 "$rc"
has "a missing Desktop sort reads unset" "DesktopViewSettings arrangeBy=unset" "$out"
"$PIN" >/dev/null
ok "apply with no Desktop block exits 0" "$?"
eq "a new Desktop block gets the sort" "name" "$(read_iv DesktopViewSettings arrangeBy)"
eq "a new Desktop block gets no icon size" "MISSING" "$(read_iv DesktopViewSettings iconSize)"
eq "a new Desktop block gets no text size" "MISSING" "$(read_iv DesktopViewSettings textSize)"

has "docs name the .DS_Store exception" "Sort By Name" "$(cat "$DIR/docs/settings.md")"
has "docs name the Desktop sort" "DesktopViewSettings" "$(cat "$DIR/docs/settings.md")"
miss "docs no longer say the Desktop is not changed" "The Desktop (\`DesktopViewSettings\`) is not changed" "$(cat "$DIR/docs/settings.md")"
has "docs name the View Options path" "Show View Options" "$(cat "$DIR/docs/settings.md")"

printf 'finder-icon-view tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
