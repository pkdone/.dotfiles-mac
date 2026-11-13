#!/usr/bin/env bash
#
# Allow in the Menu Bar is check-only. Fixture plists only — the Control
# Center store is never opened or written. Run: ./tests/menubar-allow.test.sh
#
# shellcheck disable=SC2034,SC2317  # stubs the sourced check calls
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTDIR="$DIR"
HELPER="$DIR/lib/menubar-allow.py"
LIST="$DIR/lib/menubar-allow.list"
CHECK="$DIR/checks/menubar.sh"
STEPS="$DIR/lib/manual-steps.list"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "menubar-allow tests: python3 not found, skipped"; exit 0; fi
export DOT_PYTHON="$PY"

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

# spec lines: bundle|true|false|optional menuItemLocations bundle
write_store() { # dest spec [nested|list]
  "$PY" - "$1" "$2" "${3:-nested}" <<'PY'
import plistlib, sys
dest, spec, kind = sys.argv[1], sys.argv[2], sys.argv[3]
items = []
for raw in open(spec, encoding="utf-8"):
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    parts = line.split("|")
    bundle, allowed = parts[0], parts[1]
    menu = parts[2] if len(parts) > 2 and parts[2] else bundle
    flag = allowed == "true"
    items.append({"bundle": {"_0": bundle}})
    items.append({
        "location": {"bundle": {"_0": bundle}},
        "menuItemLocations": [{"bundle": {"_0": menu}}],
        "isAllowed": flag,
    })
fmt = plistlib.FMT_BINARY
if kind == "list":
    with open(dest, "wb") as fh:
        plistlib.dump({"trackedApplications": items}, fh, fmt=fmt)
else:
    blob = plistlib.dumps(items, fmt=fmt)
    with open(dest, "wb") as fh:
        plistlib.dump({"trackedApplications": blob}, fh, fmt=fmt)
PY
}
run() { "$PY" "$HELPER" --plist "$1" --list "${2:-$LIST}"; }

# The eleven pinned apps, in list order. Others stay unpinned.
eq "allow list bundles" \
  "com.1password.1password
com.todesktop.230313mzl4w4u92
co.anysphere.cursor.nightly
com.docker.docker
com.granola.app
com.microsoft.teams2
com.tinyspeck.slackmacgap
us.zoom.xos
com.raycast.macos
com.logi.cp-dev-mgr
notion.id" \
  "$(awk -F'|' '$1 !~ /^#/ && NF == 3 { print $1 }' "$LIST")"
eq "every pinned app is off" "" \
  "$(awk -F'|' '$1 !~ /^#/ && NF == 3 && $2 != "off" { print }' "$LIST")"
for kept in io.tailscale.ipn.macsys org.hammerspoon.Hammerspoon com.fleetdm.desktop \
  org.pqrs.Karabiner-Console-User-Server com.okta.mobile com.sentinelone.SentinelAgent
do
  miss "allow list does not pin $kept" "$kept" "$(cat "$LIST")"
done

title="$(awk -F'|' '$1 == "menubar-third-party-hide" { print $3; exit }' "$STEPS")"
while IFS='|' read -r _bundle _expect name; do
  [ -n "$name" ] || continue
  has "manual step names $name" "$name" "$title"
done < <(awk -F'|' '$1 !~ /^#/ && NF == 3 { print $1 "|" $2 "|" $3 }' "$LIST")
has "manual step leaves the unpinned icons" \
  "Leave Tailscale, Hammerspoon, Fleet Desktop and the rest as they are" "$title"
miss "manual step does not leave 1Password on" "Leave Tailscale, 1Password" "$title"
eq "manual step check is the menubar section" "@macconfig:menubar" \
  "$(awk -F'|' '$1 == "menubar-third-party-hide" { print $6; exit }' "$STEPS")"
eq "menubar-allow is Needs Paul" "PAUL|" \
  "$(awk -F'|' '$1 == "menubar-allow" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"

writers="$(grep -nE 'defaults write|PlistBuddy|killall ControlCenter|plistlib.dump|subprocess' \
  "$CHECK" "$HELPER" || true)"
eq "check and helper never write the menu bar store" "" "$writers"
has "helper default plist is the control center group store" \
  "group.com.apple.controlcenter.plist" "$(cat "$HELPER")"

# Paul's Mac: the eleven are off. Tailscale stays on and is not pinned.
# Docker's menu item bundle is com.electron.dockerdesktop, not the toggle.
cat > "$tmp/off.spec" <<'EOF'
com.1password.1password|false|
com.todesktop.230313mzl4w4u92|false|
co.anysphere.cursor.nightly|false|
com.docker.docker|false|com.electron.dockerdesktop
com.granola.app|false|
com.microsoft.teams2|false|
com.tinyspeck.slackmacgap|false|
us.zoom.xos|false|
com.raycast.macos|false|
com.logi.cp-dev-mgr|false|
notion.id|false|
io.tailscale.ipn.macsys|true|
org.hammerspoon.Hammerspoon|true|
com.fleetdm.desktop|true|
EOF
write_store "$tmp/off.plist" "$tmp/off.spec"
expected="$(awk -F'|' '$1 !~ /^#/ && NF == 3 {
  printf "ok|%s|%s (%s): Allow in the Menu Bar is off\n", $1, $3, $1
}' "$LIST")"
out="$(run "$tmp/off.plist")"; rc=$?
eq "all off exits 0" 0 "$rc"
eq "all off snapshot" "$expected" "$out"
miss "an allowed unpinned app is not drift" "io.tailscale.ipn.macsys" "$out"
miss "docker menu item bundle is not a separate app" "com.electron.dockerdesktop" "$out"

write_store "$tmp/off-list.plist" "$tmp/off.spec" list
eq "a plain array matches the nested blob" "$out" "$(run "$tmp/off-list.plist")"

# One app allowed that should be off: drift, with the one-line how-to-fix.
sed 's/^com.tinyspeck.slackmacgap|false|/com.tinyspeck.slackmacgap|true|/' \
  "$tmp/off.spec" > "$tmp/slack.spec"
write_store "$tmp/slack.plist" "$tmp/slack.spec"
out="$(run "$tmp/slack.plist")"; rc=$?
eq "allowed slack exits 0" 0 "$rc"
has "allowed slack is drift" \
  "drift|com.tinyspeck.slackmacgap|Slack (com.tinyspeck.slackmacgap) is allowed in the menu bar — System Settings → Menu Bar → Allow in the Menu Bar → turn off Slack" \
  "$out"
eq "one drift line" 1 "$(printf '%s\n' "$out" | grep -c '^drift|' || true)"
has "the other apps stay off" "ok|com.1password.1password|" "$out"
miss "docker menu item is still not drift" "com.electron.dockerdesktop" "$out"

# Docker itself allowed. The electron menu-item id is not the toggle.
sed 's/^com.docker.docker|false|com.electron.dockerdesktop/com.docker.docker|true|com.electron.dockerdesktop/' \
  "$tmp/off.spec" > "$tmp/docker.spec"
write_store "$tmp/docker.plist" "$tmp/docker.spec"
out="$(run "$tmp/docker.plist")"
has "allowed docker is drift" \
  "drift|com.docker.docker|Docker (com.docker.docker) is allowed in the menu bar — System Settings → Menu Bar → Allow in the Menu Bar → turn off Docker" \
  "$out"
miss "electron bundle is not reported when docker is allowed" "com.electron.dockerdesktop" "$out"

# An app missing from trackedApplications is info, not drift.
grep -v '^com.granola.app|' "$tmp/off.spec" > "$tmp/missing.spec"
write_store "$tmp/missing.plist" "$tmp/missing.spec"
out="$(run "$tmp/missing.plist")"; rc=$?
eq "missing app exits 0" 0 "$rc"
eq "missing app is info" \
  "info|com.granola.app|Granola (com.granola.app): not installed, or not in Allow in the Menu Bar yet" \
  "$(printf '%s\n' "$out" | grep '^info|')"
miss "missing app is not drift" "drift|" "$out"
has "a present app is still off" "ok|com.1password.1password|" "$out"

# A missing file is a warning, not a failure and not drift.
out="$(run "$tmp/no-such.plist")"; rc=$?
eq "missing file exits 0" 0 "$rc"
has "missing file is a warning" "warn|-|Allow in the Menu Bar list missing at $tmp/no-such.plist" "$out"
miss "missing file is not drift" "drift|" "$out"
miss "missing file does not invent per-app lines" "info|" "$out"

printf 'not a plist\n' > "$tmp/garbage.plist"
out="$(run "$tmp/garbage.plist")"; rc=$?
eq "garbage exits 0" 0 "$rc"
has "garbage is a warning" "warn|-|could not read Allow in the Menu Bar list" "$out"
miss "garbage is not drift" "drift|" "$out"

"$PY" - "$tmp/no-key.plist" <<'PY'
import plistlib, sys
plistlib.dump({"other": 1}, open(sys.argv[1], "wb"), fmt=plistlib.FMT_BINARY)
PY
out="$(run "$tmp/no-key.plist")"; rc=$?
eq "missing key exits 0" 0 "$rc"
has "missing key is a warning" "no readable trackedApplications" "$out"

# isAllowed that is not a bool is a warning for that app, not drift.
"$PY" - "$tmp/bad-bool.plist" <<'PY'
import plistlib, sys
items = [
    {"bundle": {"_0": "com.1password.1password"}},
    {"location": {"bundle": {"_0": "com.1password.1password"}},
     "menuItemLocations": [], "isAllowed": 1},
]
blob = plistlib.dumps(items, fmt=plistlib.FMT_BINARY)
plistlib.dump({"trackedApplications": blob}, open(sys.argv[1], "wb"), fmt=plistlib.FMT_BINARY)
PY
out="$(run "$tmp/bad-bool.plist")"
has "non-bool isAllowed warns" "warn|com.1password.1password|1Password (com.1password.1password): isAllowed unreadable" "$out"
miss "non-bool isAllowed is not drift" "drift|" "$out"

# A row that expects on drifts when the toggle is off. The repo list is all off.
printf 'com.example.kept|on|Kept\n' > "$tmp/on.list"
printf 'com.example.kept|false|\n' > "$tmp/on.spec"
write_store "$tmp/on.plist" "$tmp/on.spec"
out="$(run "$tmp/on.plist" "$tmp/on.list")"
eq "expected on and allowed off is drift" \
  "drift|com.example.kept|Kept (com.example.kept) is not allowed in the menu bar — System Settings → Menu Bar → Allow in the Menu Bar → turn on Kept" \
  "$out"

before="$("$PY" -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$tmp/off.plist")"
run "$tmp/off.plist" >/dev/null
after="$("$PY" -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$tmp/off.plist")"
eq "reading does not modify the plist" "$before" "$after"

# The section maps drift to bad, a missing app to an info line, and a
# missing file to a warning. It does not write.
section="$(cat "$CHECK")"
has "section calls the helper" "lib/menubar-allow.py" "$section"
# shellcheck disable=SC2016  # needles are source text, compared literally
has "section drifts with bad" 'bad "$m_msg"' "$section"
# shellcheck disable=SC2016
has "section notes a missing app" 'note "$m_msg"' "$section"
# shellcheck disable=SC2016
has "section warns" 'warn "$m_msg"' "$section"
has "section tags menubar-allow" "fixid menubar-allow" "$section"

run_section() { # plist path
  # Subshell so a `return` in the sourced check leaves the source, not this function.
  (
    unset MENUBAR_PREPARED MENUBAR_FAIL_WARNED MENUBAR_OUT MENUBAR_FAIL
    export MENUBAR_ALLOW_PLIST="$1"
    CHECKED=0
    LINES=""
    pass() { LINES="${LINES}pass|$1"$'\n'; }
    bad() { LINES="${LINES}bad|$1"$'\n'; }
    warn() { LINES="${LINES}warn|$1"$'\n'; }
    note() { LINES="${LINES}note|$1"$'\n'; }
    info() { LINES="${LINES}info|$1"$'\n'; }
    fixid() { LINES="${LINES}fixid|$1"$'\n'; }
    hdr() { :; }
    with_timeout() { shift; "$@"; }
    MACCONFIG_CHECKS_DEFINE_ONLY=1
    # shellcheck disable=SC1090
    . "$CHECK"
    check_step_menubar_third_party_hide
    printf '%s' "$LINES"
  )
}

off_lines="$(run_section "$tmp/off.plist")"
eq "section passes when every pinned app is off" 11 \
  "$(printf '%s\n' "$off_lines" | grep -c '^pass|' || true)"
miss "section does not drift when every pinned app is off" "bad|" "$off_lines"
miss "section does not warn when the plist is readable" "warn|" "$off_lines"

slack_lines="$(run_section "$tmp/slack.plist")"
has "section drifts the allowed app" "bad|" "$slack_lines"
has "section how-to-fix names Slack" \
  "System Settings → Menu Bar → Allow in the Menu Bar → turn off Slack" "$slack_lines"
has "section tags the drift" "fixid|menubar-allow" "$slack_lines"

miss_lines="$(run_section "$tmp/missing.plist")"
has "section info for a missing app" \
  "note|Granola (com.granola.app): not installed, or not in Allow in the Menu Bar yet" \
  "$miss_lines"
miss "section does not drift a missing app" "bad|" "$miss_lines"

gone_lines="$(run_section "$tmp/no-such.plist")"
has "section warns when the file is missing" "warn|" "$gone_lines"
has "section tags the missing file" "fixid|menubar-allow" "$gone_lines"
miss "section does not drift when the file is missing" "bad|" "$gone_lines"

# manualsteps uses the same step function. A missing plist warns. Every
# pinned app off is ok, and an app that is not in the blob yet does not
# keep the step open. One allowed app is not set, with the how-to-fix.
# shellcheck disable=SC1091
. "$DIR/lib/covered-steps.sh"
with_timeout() { shift; "$@"; }
unset MENUBAR_PREPARED MENUBAR_FAIL_WARNED
off_step="$(MENUBAR_ALLOW_PLIST="$tmp/off.plist" covered_step_run menubar-third-party-hide menubar)"
eq "manual step is ok when every pinned app is off" "ok" \
  "$(printf '%s\n' "$off_step" | cut -d'|' -f1)"
unset MENUBAR_PREPARED MENUBAR_FAIL_WARNED
miss_step="$(MENUBAR_ALLOW_PLIST="$tmp/missing.plist" covered_step_run menubar-third-party-hide menubar)"
eq "a missing app does not keep the manual step open" "ok" \
  "$(printf '%s\n' "$miss_step" | cut -d'|' -f1)"
unset MENUBAR_PREPARED MENUBAR_FAIL_WARNED
slack_step="$(MENUBAR_ALLOW_PLIST="$tmp/slack.plist" covered_step_run menubar-third-party-hide menubar)"
eq "an allowed app warns the manual step" "warn" \
  "$(printf '%s\n' "$slack_step" | cut -d'|' -f1)"
has "manual step how-to-fix names Slack" \
  "System Settings → Menu Bar → Allow in the Menu Bar → turn off Slack" "$slack_step"
unset MENUBAR_PREPARED MENUBAR_FAIL_WARNED
gone_step="$(MENUBAR_ALLOW_PLIST="$tmp/no-such.plist" covered_step_run menubar-third-party-hide menubar)"
eq "a missing plist warns the manual step" "warn" \
  "$(printf '%s\n' "$gone_step" | cut -d'|' -f1)"

printf 'menubar-allow tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
