#!/usr/bin/env bash
#
# Login-item allow-list and display names. Cursor and Cursor Nightly
# BackgroundActivityCheck agents must be allow-listed. A boolean name, which
# the BTM store sometimes holds and which prints as "true", must not be the
# name the check shows.
# Run: ./tests/login-items-allow.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "login-items-allow tests: python3 not found, skipped"; exit 0; fi

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

audit="$("$PY" - "$DIR/lib/btm-login-items.py" "$DIR/lib/login-items-allow.list" "$tmp/items.btm" <<'PY'
import importlib.util
import io
import plistlib
import sys
from contextlib import redirect_stdout
from pathlib import Path
mod_path, allow, dest = sys.argv[1:]
spec = importlib.util.spec_from_file_location("btm_login_items", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def item(**kw):
    base = {
        "disposition": 0xB,  # enabled
        "type": 0x8,         # agent
        "name": "Example",
        "identifier": "8.com.example.agent",
        "bundleIdentifier": "",
        "developerName": "Example Dev",
        "teamIdentifier": "TEAMID",
        "url": "file:///bin",
        "executablePath": "",
        "container": "",
    }
    base.update(kw)
    return base

items = [
    item(
        name=True,
        identifier="8.com.todesktop.230313mzl4w4u92.BackgroundActivityCheck",
        bundleIdentifier="com.todesktop.230313mzl4w4u92",
        developerName="Anysphere, Inc.",
        teamIdentifier="VDXQ22DGB9",
        executablePath="/Applications/Cursor.app/Contents/Library/LoginItems/BackgroundActivityCheck",
    ),
    item(
        name="true",
        identifier="co.anysphere.cursor.nightly.BackgroundActivityCheck",
        bundleIdentifier="",
        developerName="Anysphere, Inc.",
        executablePath="/Applications/Cursor Nightly.app/Contents/Library/LoginItems/BackgroundActivityCheck",
    ),
    item(
        name=True,
        identifier="8.com.example.other",
        bundleIdentifier="com.todesktop.230313mzl4w4u92.BackgroundActivityCheck",
        executablePath="/Applications/Cursor.app/Contents/Library/LoginItems/BackgroundActivityCheck",
    ),
    item(
        name="Helper",
        identifier="8.com.unrelated.helper",
        bundleIdentifier="",
        container="2.co.anysphere.cursor.nightly",
        executablePath="/Applications/Cursor Nightly.app/Contents/MacOS/Helper",
    ),
    item(
        name="pin-dictation",
        identifier="8.com.pdone.pin-dictation-hotkey-164",
        bundleIdentifier="",
    ),
    item(
        name="Raycast",
        identifier="2.com.raycast.macos",
        bundleIdentifier="com.raycast.macos",
        executablePath="/Applications/Raycast.app/Contents/MacOS/Raycast",
    ),
    item(
        name="Widget",
        identifier="8.com.evil.widget",
        bundleIdentifier="com.evil.widget",
    ),
]
plistlib.dump({
    "$version": 100000,
    "$archiver": "NSKeyedArchiver",
    "$top": {"root": "items"},
    "$objects": ["$null"] + items,
}, open(dest, "wb"))

buf = io.StringIO()
with redirect_stdout(buf):
    mod.audit(allow, None, [Path(dest)])
sys.stdout.write(buf.getvalue())
PY
)" || { echo "login-items-allow tests: audit helper failed"; exit 1; }

# class|kind|name|developer|team|id|detail
field_in() { # audit text, needle, field number (1-based)
  printf '%s\n' "$1" | awk -F'|' -v id="$2" -v n="$3" 'index($0, id) { print $n; exit }'
}
field() { field_in "$audit" "$1" "$2"; }

eq "cursor helper display name" BackgroundActivityCheck "$(field "com.todesktop.230313mzl4w4u92|" 3)"
eq "cursor helper class" allow "$(field "com.todesktop.230313mzl4w4u92|" 1)"

eq "nightly helper class" allow "$(field "co.anysphere.cursor.nightly.BackgroundActivityCheck" 1)"
eq "nightly helper display name" BackgroundActivityCheck "$(field "co.anysphere.cursor.nightly.BackgroundActivityCheck" 3)"
miss "nightly name is not the word true" "|true|" "$(printf '%s\n' "$audit" | grep 'cursor.nightly.BackgroundActivityCheck')"

eq "helper bundle id is allow-listed" allow "$(field "com.todesktop.230313mzl4w4u92.BackgroundActivityCheck" 1)"
eq "helper inside nightly is allow-listed" allow "$(field "com.unrelated.helper" 1)"
eq "real helper name is kept" Helper "$(field "com.unrelated.helper" 3)"

eq "dictation pin label still allow-listed" allow "$(field "com.pdone.pin-dictation-hotkey-164" 1)"
eq "raycast name stays Raycast" Raycast "$(field "com.raycast.macos" 3)"
eq "raycast stays allow-listed" allow "$(field "com.raycast.macos" 1)"

eq "unknown item stays unknown" unknown "$(field "com.evil.widget" 1)"
eq "unknown item keeps its name" Widget "$(field "com.evil.widget" 3)"

eq "SentinelOne team is allow-listed" allow "$(
  "$PY" - "$DIR/lib/btm-login-items.py" "$DIR/lib/login-items-allow.list" <<'PY'
import importlib.util, io, sys
from contextlib import redirect_stdout
mod_path, allow = sys.argv[1:]
spec = importlib.util.spec_from_file_location("btm_login_items", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
it = {
    "type": 0x8, "disposition": 0xB, "name": "sentineld-helper",
    "identifier": "8.com.sentinelone.sentineld-helper",
    "bundle": "com.sentinelone.sentineld-helper", "id": "com.sentinelone.sentineld-helper",
    "developer": "SentinelOne", "team": "4AYE5J54KN", "url": "file:///bin",
    "executable": "", "parent": "", "enabled": True,
}
rules = mod.read_allow(allow)
print("allow" if any(mod.matches(r, it) for r in rules) else "no")
PY
)"

company="$("$PY" - "$DIR/lib/btm-login-items.py" "$DIR/lib/login-items-allow.list" "$tmp/company.btm" "$tmp/mdm.btm" <<'PY'
import importlib.util, io, plistlib, sys
from contextlib import redirect_stdout
from pathlib import Path
mod_path, allow, items_path, mdm_path = sys.argv[1:]
spec = importlib.util.spec_from_file_location("btm_login_items", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
plistlib.dump({
    "$version": 100000,
    "$archiver": "NSKeyedArchiver",
    "$top": {"root": "items"},
    "$objects": ["$null", {
        "disposition": 0xB,
        "type": 0x8,
        "name": "New helper",
        "identifier": "8.com.company.new-helper",
        "bundleIdentifier": "com.company.new-helper",
        "developerName": "Company",
        "teamIdentifier": "NEWTEAM99",
        "url": "file:///bin",
        "executablePath": "",
        "container": "",
    }],
}, open(items_path, "wb"))
plistlib.dump({
    "$version": 100000,
    "$archiver": "NSKeyedArchiver",
    "$top": {
        "mdmPayloadsByIdentifier": {
            "payload": {
                "Rules": [{
                    "RuleType": "BundleIdentifier",
                    "RuleValue": "com.company.known",
                    "TeamIdentifier": "NEWTEAM99",
                }],
            },
        },
    },
    "$objects": ["$null"],
}, open(mdm_path, "wb"))
buf = io.StringIO()
with redirect_stdout(buf):
    mod.audit(allow, Path(mdm_path), [Path(items_path)])
sys.stdout.write(buf.getvalue())
PY
)"
eq "a new company-team helper stays unknown" unknown "$(printf '%s\n' "$company" | cut -d'|' -f1)"
eq "a new company-team helper is marked company-team" company-team "$(printf '%s\n' "$company" | cut -d'|' -f7)"
company_msg="$(awk '/li_detail. = company-team/,/else/' "$DIR/checks/health.sh")"
has "a company-team warning says to add it to the allow list" "Add it to lib/login-items-allow.list" "$company_msg"
miss "a company-team warning does not say to turn it off" "turn it Off" "$company_msg"

koi="$("$PY" - "$DIR/lib/btm-login-items.py" "$DIR/lib/login-items-allow.list" "$tmp/koi.btm" <<'PY'
import importlib.util, io, plistlib, sys
from contextlib import redirect_stdout
from pathlib import Path
mod_path, allow, items_path = sys.argv[1:]
spec = importlib.util.spec_from_file_location("btm_login_items", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
plistlib.dump({
    "$version": 100000,
    "$archiver": "NSKeyedArchiver",
    "$top": {"root": "items"},
    "$objects": ["$null", {
        "disposition": 0xB,
        "type": 0x10,
        "name": "koi.security.mdm.sh",
        "identifier": "koi.security.mdm.plist",
        "bundleIdentifier": "",
        "developerName": "",
        "teamIdentifier": "",
        "url": "file:///bin",
        "executablePath": "/usr/local/bin/koi.security.mdm.sh",
        "container": "",
    }],
}, open(items_path, "wb"))
buf = io.StringIO()
with redirect_stdout(buf):
    mod.audit(allow, None, [Path(items_path)])
sys.stdout.write(buf.getvalue())
PY
)"
eq "koi security MDM daemon is allow-listed" allow "$(printf '%s\n' "$koi" | cut -d'|' -f1)"
eq "koi security MDM daemon keeps its name" "koi.security.mdm.sh" "$(printf '%s\n' "$koi" | cut -d'|' -f3)"
eq "koi security MDM daemon keeps its plist id" "koi.security.mdm.plist" "$(printf '%s\n' "$koi" | cut -d'|' -f6)"
has "allow list matches koi.security.*" "label-prefix|koi.security.|" "$(cat "$DIR/lib/login-items-allow.list")"
allow_branch="$(awk '/^[[:space:]]*allow\)/,/^[[:space:]]*mdm\)/' "$DIR/checks/health.sh")"
miss "an allow-listed item is not told to turn Off" "turn it Off" "$allow_branch"

# WhatsApp Web is a Safari web app. Its bundle id is
# com.apple.Safari.WebApp.<UUID>, new on each Mac, so the allow row is its
# path under ~/Applications. HOME is a temp folder so the host is not read.
home="$tmp/home"
mkdir -p "$home/Applications/WhatsApp Web.app" "$home/Applications/Gmail.app" \
  "$tmp/elsewhere/WhatsApp Web.app"
webapp_audit() { # HOME, allow list
  HOME="$1" "$PY" - "$DIR/lib/btm-login-items.py" "$2" "$tmp/webapp.btm" "$tmp/elsewhere" <<'PY'
import importlib.util, io, os, plistlib, sys
from contextlib import redirect_stdout
from pathlib import Path
from urllib.parse import quote
mod_path, allow, items_path, elsewhere = sys.argv[1:]
spec = importlib.util.spec_from_file_location("btm_login_items", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
home = os.environ["HOME"]
def url(path):
    return "file://" + quote(path) + "/"
def item(name, bundle, path, kind=0x2):
    return {
        "disposition": 0xB, "type": kind, "name": name,
        "identifier": f"2.{bundle}", "bundleIdentifier": bundle,
        "developerName": "", "teamIdentifier": "",
        "url": url(path), "executablePath": "", "container": "",
    }
items = [
    item("WhatsApp Web", "com.apple.Safari.WebApp.2C07FD29-EDF8-4FBA-8539-F9C71386A734",
         f"{home}/Applications/WhatsApp Web.app"),
    item("Gmail", "com.apple.Safari.WebApp.11111111-2222-3333-4444-555555555555",
         f"{home}/Applications/Gmail.app"),
    item("WhatsApp Web", "com.apple.Safari.WebApp.99999999-2222-3333-4444-555555555555",
         f"{elsewhere}/WhatsApp Web.app"),
    item("WhatsApp agent", "com.example.whatsapp-agent",
         f"{home}/Applications/WhatsApp Web.app", kind=0x8),
]
plistlib.dump({
    "$version": 100000, "$archiver": "NSKeyedArchiver",
    "$top": {"root": "items"}, "$objects": ["$null"] + items,
}, open(items_path, "wb"))
buf = io.StringIO()
with redirect_stdout(buf):
    mod.audit(allow, None, [Path(items_path)])
sys.stdout.write(buf.getvalue())
PY
}
web="$(webapp_audit "$home" "$DIR/lib/login-items-allow.list")"
eq "WhatsApp Web in ~/Applications is allow-listed" allow "$(field_in "$web" "2C07FD29-EDF8-4FBA-8539-F9C71386A734" 1)"
eq "WhatsApp Web keeps its name" "WhatsApp Web" "$(field_in "$web" "2C07FD29-EDF8-4FBA-8539-F9C71386A734" 3)"
eq "another Safari web app stays unknown" unknown "$(field_in "$web" "11111111-2222-3333-4444-555555555555" 1)"
eq "a WhatsApp Web app somewhere else stays unknown" unknown "$(field_in "$web" "99999999-2222-3333-4444-555555555555" 1)"
eq "a background agent at that path is not an app row match" unknown "$(field_in "$web" "com.example.whatsapp-agent" 1)"
rm -rf "$home/Applications/WhatsApp Web.app"
web="$(webapp_audit "$home" "$DIR/lib/login-items-allow.list")"
eq "a removed WhatsApp Web is stale, not allowed" stale "$(field_in "$web" "2C07FD29-EDF8-4FBA-8539-F9C71386A734" 1)"
mkdir -p "$home/Applications/WhatsApp Web.app"

printf 'app|Applications/WhatsApp Web.app|relative\napp|~/Applications/WhatsApp Web|no .app\n' > "$tmp/bad-app.list"
bad="$(webapp_audit "$home" "$tmp/bad-app.list" 2>&1)"
has "an app row needs a full .app path" "allowlist: line 1: an app row needs the full path of a .app" "$bad"
has "an app row without .app is refused" "allowlist: line 2: an app row needs the full path of a .app" "$bad"
miss "the allowlist error has no pipe for health.sh to split on" "allowlist: line 1: an app row needs the full path of a .app, such as ~/Applications/WhatsApp Web.app|" "$bad"
eq "a refused app row allows nothing" unknown "$(field_in "$bad" "2C07FD29-EDF8-4FBA-8539-F9C71386A734" 1)"

allow_text="$(cat "$DIR/lib/login-items-allow.list")"
has "allow list names WhatsApp Web by path" "app|~/Applications/WhatsApp Web.app|" "$allow_text"
miss "allow list does not pin this Mac's web app UUID" "2C07FD29" "$allow_text"
miss "allow list does not allow every Safari web app" "com.apple.Safari.WebApp|" "$allow_text"
has "allow list header documents the app type" "#          app " "$allow_text"

has "allow list mentions Cursor BackgroundActivityCheck" \
  "com.todesktop.230313mzl4w4u92.BackgroundActivityCheck" "$(cat "$DIR/lib/login-items-allow.list")"
has "allow list mentions Cursor Nightly" \
  "co.anysphere.cursor.nightly" "$(cat "$DIR/lib/login-items-allow.list")"

printf 'login-items-allow tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
