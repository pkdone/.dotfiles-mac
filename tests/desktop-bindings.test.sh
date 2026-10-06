#!/usr/bin/env bash
#
# Unit tests for lib/desktop-bindings.py (Dock "Assign To" check and apply).
# Synthetic plists and a fake `defaults` / `killall` on PATH — never the live
# Dock or com.apple.spaces. Run: ./tests/desktop-bindings.test.sh
#
set -uo pipefail   # deliberately not -e: run every assertion, then tally failures

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/desktop-bindings.py"
REAL_LIST="$DIR/lib/desktop-bindings.list"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "desktop-bindings tests: python3 not found, skipped"; exit 0; fi

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
ok() {  # description status
  if [ "$2" = 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; fi
}
has() {  # description needle haystack
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}
if_exists() { if [ -e "$1" ]; then printf 'exists'; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin"

# Fake defaults/killall so a live --apply can be proven without a Dock.
# FAKE_WRITE_RC / KILLALL_RC override the exit status of write/delete and killall.
cat > "$bin/defaults" <<'PY'
#!/usr/bin/env python3
import json, os, sys
log = os.environ["FAKE_LOG"]
with open(log, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(sys.argv[1:]) + "\n")
cmd = sys.argv[1] if len(sys.argv) > 1 else ""
if cmd == "export":
    data = open(os.environ["FAKE_PLIST"], "rb").read()
    dest = sys.argv[3]
    if dest == "-":
        sys.stdout.buffer.write(data)
    else:
        with open(dest, "wb") as fh:
            fh.write(data)
    raise SystemExit(0)
if cmd in ("write", "delete"):
    raise SystemExit(int(os.environ.get("FAKE_WRITE_RC", "0")))
sys.stderr.write("unexpected defaults command\n")
raise SystemExit(99)
PY
cat > "$bin/killall" <<'PY'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ["FAKE_LOG"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(["killall", *sys.argv[1:]]) + "\n")
raise SystemExit(int(os.environ.get("KILLALL_RC", "0")))
PY
chmod +x "$bin/defaults" "$bin/killall" "$HELPER"

export PATH="$bin:$PATH"
export FAKE_LOG="$tmp/fake.log"
export FAKE_PLIST="$tmp/live.plist"
export FAKE_WRITE_RC=0
export KILLALL_RC=0
: > "$FAKE_LOG"

# make_plist PATH [python] — p starts as a Main display with Desktops 1–4
# (Desktop 1 UUID "", a full-screen Space that must not shift numbering, and
# a secondary monitor that must be ignored) plus spans-displays.
make_plist() {
  "$PY" - "$1" "${2:-pass}" <<'PY'
import plistlib, sys
path, tweak = sys.argv[1], sys.argv[2]
def desk(uuid, typ=0):
    return {"type": typ, "uuid": uuid}
p = {
  "spans-displays": False,
  "app-bindings": {},
  "SpacesDisplayConfiguration": {"Management Data": {"Monitors": [
    {"Display Identifier": "Main", "Spaces": [
      desk(""), desk("UUID-2"), desk("UUID-3"), desk("FS-1", 4), desk("UUID-4"),
    ]},
    {"Display Identifier": "Secondary", "Spaces": [desk("OTHER-1")]},
  ]}},
}
exec(tweak)
with open(path, "wb") as fh:
    plistlib.dump(p, fh, fmt=plistlib.FMT_XML)
PY
}
binds() {
  "$PY" -c 'import plistlib,sys
b=plistlib.load(open(sys.argv[1],"rb")).get("app-bindings") or {}
print("\n".join("%s=%s" % (k, b[k]) for k in sorted(b)))' "$1"
}
space_sig() {
  "$PY" -c 'import plistlib,sys
p=plistlib.load(open(sys.argv[1],"rb"))
mons=p["SpacesDisplayConfiguration"]["Management Data"]["Monitors"]
lines=[]
for m in mons:
    parts=[]
    for s in m.get("Spaces") or []:
        parts.append("%s:%s" % (s.get("type"), "" if s.get("uuid") is None else s.get("uuid")))
    lines.append("%s %s" % (m.get("Display Identifier"), ",".join(parts)))
lines.append("spans %s" % p.get("spans-displays"))
print("\n".join(lines))' "$1"
}
run() { "$PY" "$HELPER" "$@"; }

cat > "$tmp/small.list" <<'EOF'
# comment and blanks ignored
Slack|com.tinyspeck.slackmacgap|1
Chrome|com.google.Chrome|2
Spotify|com.spotify.client|4
Ghostty|com.mitchellh.ghostty|none
Sidecar|com.example.sidecar|none
Missing|com.example.missing|1
EOF

# ---- read-only check: same map the apply path uses ----
make_plist "$tmp/check.plist" 'p["app-bindings"] = {
  "com.tinyspeck.slackmacgap": "",
  "com.google.chrome": "UUID-2",
  "com.spotify.client": "FS-1",
  "com.mitchellh.ghostty": "UUID-2",
  "com.example.sidecar": "OTHER-1",
}'
sum_before="$(cksum < "$tmp/check.plist")"
log_before="$(cksum < "$FAKE_LOG")"
out="$(run --plist "$tmp/check.plist" "$tmp/small.list")"; rc=$?
eq "check with drift exits 0 (read-only)" 0 "$rc"
eq "check lines" "$(printf '%s\n' \
  'ok|com.tinyspeck.slackmacgap|Slack assigned to Desktop 1' \
  'ok|com.google.Chrome|Chrome assigned to Desktop 2' \
  'bad|com.spotify.client|Spotify assigned to unknown desktop FS-1 (expected Desktop 4)' \
  'bad|com.mitchellh.ghostty|Ghostty assigned to Desktop 2 (expected None)' \
  'bad|com.example.sidecar|Sidecar assigned to unknown desktop OTHER-1 (expected None)' \
  'bad|com.example.missing|Missing assigned to None (expected Desktop 1)')" "$out"
eq "check does not modify the plist" "$sum_before" "$(cksum < "$tmp/check.plist")"
eq "check --plist does not call defaults" "$log_before" "$(cksum < "$FAKE_LOG")"

echo 'not a plist' > "$tmp/bad.plist"
out="$(run --plist "$tmp/bad.plist" "$tmp/small.list")"; rc=$?
eq "unreadable plist is a warning, exit 0" 0 "$rc"
has "unreadable plist warning" "warn||could not read com.apple.spaces" "$out"
out="$(run --apply --plist "$tmp/bad.plist" --out "$tmp/nope.plist" "$tmp/small.list")"; rc=$?
eq "apply of unreadable plist exits 2" 2 "$rc"
has "apply of unreadable plist fails closed" "fail||could not read com.apple.spaces" "$out"
eq "unreadable apply writes nothing" "" "$(if_exists "$tmp/nope.plist")"

# ---- apply: set, clear, keep case, preserve unmanaged and the Space layout ----
make_plist "$tmp/in.plist" 'p["app-bindings"] = {
  "Com.TinySpeck.SlackMacGap": "UUID-4",
  "Com.Google.Chrome": "",
  "com.spotify.client": "UUID-4",
  "com.mitchellh.ghostty": "UUID-2",
  "com.example.Keep": "KEEP",
}'
sig_before="$(space_sig "$tmp/in.plist")"
sum_in="$(cksum < "$tmp/in.plist")"
out="$(run --apply --dry-run --plist "$tmp/in.plist" --out "$tmp/dry.plist" "$tmp/small.list")"; rc=$?
eq "dry-run exits 0" 0 "$rc"
eq "dry-run writes no plist" "" "$(if_exists "$tmp/dry.plist")"
eq "dry-run leaves the source alone" "$sum_in" "$(cksum < "$tmp/in.plist")"
has "dry-run would assign Desktop 1" "dry|com.tinyspeck.slackmacgap|would assign Slack to Desktop 1" "$out"
has "dry-run would clear" "dry|com.mitchellh.ghostty|would clear Ghostty (None)" "$out"
has "dry-run names the resolved UUID" "would assign Chrome to Desktop 2 (UUID-2)" "$out"
eq "dry-run does not call defaults" "$log_before" "$(cksum < "$FAKE_LOG")"

out="$(run --apply --plist "$tmp/in.plist" --out "$tmp/out.plist" "$tmp/small.list")"; rc=$?
eq "apply exits 0" 0 "$rc"
eq "apply source plist unchanged" "$sum_in" "$(cksum < "$tmp/in.plist")"
eq "apply bindings" "$(printf '%s\n' \
  'com.example.Keep=KEEP' \
  'com.example.missing=' \
  'com.google.chrome=UUID-2' \
  'com.spotify.client=UUID-4' \
  'com.tinyspeck.slackmacgap=')" "$(binds "$tmp/out.plist")"
eq "apply does not invent or reorder Spaces" "$sig_before" "$(space_sig "$tmp/out.plist")"
eq "file apply does not restart or back up" "" "$(printf '%s\n' "$out" | grep '^note|' || true)"
has "apply reports the slack write" "chg|com.tinyspeck.slackmacgap|assign Slack to Desktop 1" "$out"
has "apply reports the clear" "chg|com.mitchellh.ghostty|clear Ghostty (None)" "$out"

out="$(run --apply --plist "$tmp/out.plist" --out "$tmp/out2.plist" "$tmp/small.list")"; rc=$?
eq "second apply exits 0" 0 "$rc"
eq "second apply is a no-op (no output plist)" "" "$(if_exists "$tmp/out2.plist")"
eq "second apply reports already-set pins" "" "$(printf '%s\n' "$out" | grep -v '^ok|' || true)"
has "already on Desktop 1" "ok|com.tinyspeck.slackmacgap|Slack already assigned to Desktop 1" "$out"

# --plist --apply must not fall through to a live defaults write.
: > "$FAKE_LOG"
out="$(run --apply --plist "$tmp/in.plist" "$tmp/small.list")"; rc=$?
eq "plist apply without --out exits 1" 1 "$rc"
has "refuses a live write from --plist" "refusing to write live preferences from --plist" "$out"
eq "refused apply does not call defaults" "" "$(cat "$FAKE_LOG")"

# Desktop 1 follows the Space record: a non-empty UUID is written through,
# and an omitted UUID is the empty string the checker treats as Desktop 1.
make_plist "$tmp/desk1.plist" 'p["SpacesDisplayConfiguration"]["Management Data"]["Monitors"][0]["Spaces"][0]["uuid"] = "DESK-1"'
printf 'Slack|com.tinyspeck.slackmacgap|1\n' > "$tmp/slack.list"
out="$(run --apply --plist "$tmp/desk1.plist" --out "$tmp/desk1.out" "$tmp/slack.list")"
eq "Desktop 1 uses the Space UUID, not a hardcoded empty string" "com.tinyspeck.slackmacgap=DESK-1" "$(binds "$tmp/desk1.out")"
has "message includes that UUID" "assign Slack to Desktop 1 (DESK-1)" "$out"
out="$(run --plist "$tmp/desk1.out" "$tmp/slack.list")"
eq "checker agrees with the UUID it just wrote" "ok|com.tinyspeck.slackmacgap|Slack assigned to Desktop 1" "$out"

make_plist "$tmp/nouuid.plist" 'p["SpacesDisplayConfiguration"]["Management Data"]["Monitors"][0]["Spaces"][0] = {"type": 0}'
run --apply --plist "$tmp/nouuid.plist" --out "$tmp/nouuid.out" "$tmp/slack.list" >/dev/null
eq "omitted Desktop 1 UUID is written as empty string" "com.tinyspeck.slackmacgap=" "$(binds "$tmp/nouuid.out")"

# UUIDs are resolved at apply time. A recreated Space (new UUID) is what gets stored.
make_plist "$tmp/fresh.plist" 'p["SpacesDisplayConfiguration"]["Management Data"]["Monitors"][0]["Spaces"][1]["uuid"] = "FRESH-2"
p["app-bindings"] = {"com.google.chrome": "STALE-2"}'
printf 'Chrome|com.google.Chrome|2\n' > "$tmp/chrome.list"
run --apply --plist "$tmp/fresh.plist" --out "$tmp/fresh.out" "$tmp/chrome.list" >/dev/null
eq "recreated Space UUID replaces the stale binding" "com.google.chrome=FRESH-2" "$(binds "$tmp/fresh.out")"

# ---- the real list: the pins that were drifting, without creating Desktops ----
make_plist "$tmp/real.plist" 'p["app-bindings"] = {
  "com.spotify.client": "UUID-4",
  "com.google.chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod": "UUID-4",
}'
sig_real="$(space_sig "$tmp/real.plist")"
only="$(awk -F'|' '$1 !~ /^#/ && NF && $3 != "4" && $3 != "none" { printf "%s%s", sep, $2; sep="," }' "$REAL_LIST")"
eq "seven drifted bundles" 7 "$(printf '%s\n' "$only" | tr ',' '\n' | grep -c .)"
out="$(run --apply --plist "$tmp/real.plist" --only "$only" --out "$tmp/real.out" "$REAL_LIST")"; rc=$?
eq "seven drifted pins apply cleanly" 0 "$rc"
eq "seven chg lines" 7 "$(printf '%s\n' "$out" | grep -c '^chg|')"
eq "real-list bindings" "$(printf '%s\n' \
  'co.anysphere.cursor.nightly=UUID-3' \
  'com.anysphere.sand=UUID-3' \
  'com.google.chrome=UUID-2' \
  'com.google.chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod=UUID-4' \
  'com.granola.app=' \
  'com.spotify.client=UUID-4' \
  'com.tinyspeck.slackmacgap=' \
  'com.todesktop.230313mzl4w4u92=UUID-3' \
  'net.whatsapp.whatsapp=')" "$(binds "$tmp/real.out")"
eq "real-list apply leaves Spaces alone" "$sig_real" "$(space_sig "$tmp/real.out")"
out="$(run --plist "$tmp/real.out" "$REAL_LIST")"; rc=$?
eq "checker is clean after apply" 0 "$rc"
eq "every real pin ok" 11 "$(printf '%s\n' "$out" | grep -c '^ok|')"
eq "no remaining drift" "" "$(printf '%s\n' "$out" | grep '^bad|' || true)"

make_plist "$tmp/short.plist" 'p["SpacesDisplayConfiguration"]["Management Data"]["Monitors"][0]["Spaces"] = [
  {"type": 0, "uuid": ""}, {"type": 0, "uuid": "UUID-2"}, {"type": 0, "uuid": "UUID-3"}]'
sig_short="$(space_sig "$tmp/short.plist")"
out="$(run --apply --plist "$tmp/short.plist" --out "$tmp/short.out" "$REAL_LIST")"; rc=$?
eq "missing Desktop 4 fails the apply" 1 "$rc"
has "names how many Desktops exist" "Desktop 4 doesn't exist on the Main display (have 3)" "$out"
has "missing desktop is a refusal, not a bad write" "refuse|com.spotify.client|Spotify: Desktop 4 doesn't exist" "$out"
eq "Desktop 4 pins were not invented" "" "$(binds "$tmp/short.out" | grep -e spotify -e youtube -e cinhimbnkkaeohfgghhklpknlkffjgod || true)"
has "Desktop 1 still written" "com.tinyspeck.slackmacgap=" "$(binds "$tmp/short.out")"
eq "short display gains no Space" "$sig_short" "$(space_sig "$tmp/short.out")"
has "Chrome still written onto Desktop 2" "com.google.chrome=UUID-2" "$(binds "$tmp/short.out")"

# ---- live defaults path: fake defaults/killall, backup, one Dock restart ----
live() { # extra env assignments via the inherited vars; args are helper args
  FAKE_LOG="$FAKE_LOG" FAKE_PLIST="$FAKE_PLIST" FAKE_WRITE_RC="$FAKE_WRITE_RC" KILLALL_RC="$KILLALL_RC" \
    DESKTOP_BINDINGS_BACKUP_DIR="$1" "$PY" "$HELPER" "${@:2}"
}
write_argv() {
  "$PY" -c 'import json,sys
for line in open(sys.argv[1], encoding="utf-8"):
    a=json.loads(line)
    if a and a[0] in ("write", "delete"):
        print(json.dumps(a))' "$1"
}
kill_lines() {
  "$PY" -c 'import json,sys
for line in open(sys.argv[1], encoding="utf-8"):
    a=json.loads(line)
    if a and a[0]=="killall":
        print(json.dumps(a))' "$1"
}

make_plist "$FAKE_PLIST" 'p["app-bindings"] = {
  "Com.TinySpeck.SlackMacGap": "UUID-4",
  "com.mitchellh.ghostty": "UUID-2",
  "com.example.Keep": "KEEP",
}'
cat > "$tmp/live.list" <<'EOF'
Slack|com.tinyspeck.slackmacgap|1
Ghostty|com.mitchellh.ghostty|none
EOF
: > "$FAKE_LOG"
FAKE_WRITE_RC=0
KILLALL_RC=0
out="$(live "$tmp/backups-ok" --apply "$tmp/live.list")"; rc=$?
eq "live apply exits 0" 0 "$rc"
has "live apply assigns Desktop 1" "chg|com.tinyspeck.slackmacgap|assign Slack to Desktop 1" "$out"
has "live apply clears Ghostty" "chg|com.mitchellh.ghostty|clear Ghostty (None)" "$out"
has "live apply restarts Dock" "note||restarted Dock" "$out"
backup_note="$(printf '%s\n' "$out" | awk -F'|' '$1=="note" && $3 ~ /^backed up / { print $3; exit }')"
backup_path="${backup_note#backed up com.apple.spaces -> }"
has "backup stays in the test dir" "$tmp/backups-ok/" "$backup_note"
if [ -f "$backup_path" ]; then backup_rc=0; else backup_rc=1; fi
ok "backup plist exists" "$backup_rc"
eq "defaults write argv" \
  '["write", "com.apple.spaces", "app-bindings", "-dict", "com.example.Keep", "KEEP", "com.tinyspeck.slackmacgap", ""]' \
  "$(write_argv "$FAKE_LOG")"
eq "killall Dock once" '["killall", "Dock"]' "$(kill_lines "$FAKE_LOG")"
eq "write does not touch spans-displays" "" "$(write_argv "$FAKE_LOG" | grep spans-displays || true)"

# Resulting dict empty → defaults delete, not an empty -dict.
make_plist "$FAKE_PLIST" 'p["app-bindings"] = {"com.mitchellh.ghostty": "UUID-2"}'
printf 'Ghostty|com.mitchellh.ghostty|none\n' > "$tmp/clear.list"
: > "$FAKE_LOG"
out="$(live "$tmp/backups-del" --apply "$tmp/clear.list")"; rc=$?
eq "clear-last-key exits 0" 0 "$rc"
eq "empty app-bindings is defaults delete" \
  '["delete", "com.apple.spaces", "app-bindings"]' \
  "$(write_argv "$FAKE_LOG")"
has "cleared key reported" "chg|com.mitchellh.ghostty|clear Ghostty (None)" "$out"

: > "$FAKE_LOG"
FAKE_WRITE_RC=1
out="$(live "$tmp/backups-fail" --apply "$tmp/live.list")"; rc=$?
eq "defaults write failure exits 1" 1 "$rc"
has "write failure is reported" "not written" "$out"
eq "failed write does not restart Dock" "" "$(kill_lines "$FAKE_LOG")"
FAKE_WRITE_RC=0

make_plist "$FAKE_PLIST" 'p["app-bindings"] = {
  "Com.TinySpeck.SlackMacGap": "UUID-4",
  "com.mitchellh.ghostty": "UUID-2",
  "com.example.Keep": "KEEP",
}'
: > "$FAKE_LOG"
KILLALL_RC=1
out="$(live "$tmp/backups-nodock" --apply "$tmp/live.list")"; rc=$?
eq "Dock not running still counts as written" 0 "$rc"
has "notes that Dock was not running" "note||Dock not running" "$out"
eq "the write still happened" \
  '["write", "com.apple.spaces", "app-bindings", "-dict", "com.example.Keep", "KEEP", "com.tinyspeck.slackmacgap", ""]' \
  "$(write_argv "$FAKE_LOG")"
KILLALL_RC=0

: > "$FAKE_LOG"
out="$(live "$tmp/backups-dry" --apply --dry-run "$tmp/live.list")"; rc=$?
eq "live dry-run exits 0" 0 "$rc"
has "live dry-run would assign" "dry|com.tinyspeck.slackmacgap|would assign Slack to Desktop 1" "$out"
eq "live dry-run does not write" "" "$(write_argv "$FAKE_LOG")"
eq "live dry-run does not restart Dock" "" "$(kill_lines "$FAKE_LOG")"
eq "live dry-run still reads the domain" 1 "$(grep -c '"export"' "$FAKE_LOG")"

printf 'desktop-bindings tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
