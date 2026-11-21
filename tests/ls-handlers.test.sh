#!/usr/bin/env bash
#
# Tests for lib/ls-handlers.py and lib/ls-handlers.list. A plist file stands in for
# Launch Services (LS_HANDLERS_PLIST); no real preference is read or written.
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "ls-handlers tests: python3 not found, skipped"; exit 0; fi
pass=0; fail=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi; }
has() { case "$3" in *"$2"*) pass=$((pass + 1)) ;; *) fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in: [%s]\n' "$1" "$2" "$3" ;; esac; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
list="$tmp/l.list"
printf 'uti|public.data|CotEditor|com.coteditor.CotEditor\next|Local|CotEditor|com.coteditor.CotEditor\n' > "$list"
cat > "$tmp/ls.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>LSHandlers</key><array>
<dict><key>LSHandlerContentType</key><string>public.data</string><key>LSHandlerRoleAll</key><string>com.coteditor.CotEditor</string></dict>
</array></dict></plist>
P
export LS_HANDLERS_PLIST="$tmp/ls.plist"
out="$("$PY" "$DIR/lib/ls-handlers.py" "$list")"
has "uti ok" "ok|public.data|public.data -> CotEditor / com.coteditor.CotEditor" "$out"
has "ext drift" "bad|local|.local -> unset" "$out"
out="$("$PY" "$DIR/lib/ls-handlers.py" --apply --dry-run "$list")"
has "dry run" "dry|local|.local: unset -> CotEditor" "$out"
printf 'uti|public.html|Chrome|com.google.Chrome\n' > "$tmp/b.list"
out="$("$PY" "$DIR/lib/ls-handlers.py" "$tmp/b.list")"
has "browser type refused" "fail||" "$out"
out="$("$PY" "$DIR/lib/ls-handlers.py")"
has "real list has public.data" "|public.data|" "$out"
has "real list has .env variants" "|local|" "$out"
eq "real list parses" 0 "$(printf '%s\n' "$out" | grep -c '^fail')"

echo "ls-handlers tests: $pass passed, $fail failed"
[ "$fail" = 0 ]
