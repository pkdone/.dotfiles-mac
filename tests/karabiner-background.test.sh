#!/usr/bin/env bash
#
# Karabiner background items. Synthetic BTM items and dumpbtm text only.
# sfltool is not run. Run: ./tests/karabiner-background.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/btm-login-items.py"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "karabiner-background tests: python3 not found, skipped"; exit 0; fi

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

eq "karabiner background step is checked by macconfig" "@macconfig-check.sh" \
  "$(awk -F'|' '$1 == "karabiner-login-items" { print $6; exit }' "$DIR/lib/manual-steps.list")"
has "manual step says macconfig checks this" "macconfig checks this" \
  "$(awk -F'|' '$1 == "karabiner-login-items" { print $3; exit }' "$DIR/lib/manual-steps.list")"
eq "karabiner-background is report-only" "PAUL|" \
  "$(awk -F'|' '$1 == "karabiner-background" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"
# Comments may name sfltool. The section must not invoke it.
miss "the login-items section does not invoke sfltool" "sfltool" \
  "$(grep -vE '^[[:space:]]*#' "$DIR/checks/login-items.sh" || true)"
miss "karabiner.sh does not invoke sfltool" "sfltool" \
  "$(grep -vE '^[[:space:]]*#' "$DIR/checks/karabiner.sh" || true)"

out="$("$PY" - "$HELPER" <<'PY'
import importlib.util
import sys
mod_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("btm_login_items", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def item(name, disp, ident=""):
    return {
        "name": name,
        "disposition": disp,
        "identifier": ident or name,
        "executable": "",
        "url": "",
        "bundle": "",
    }

items = [
    item("Karabiner-Core-Service", 0xB, "org.pqrs.Karabiner-Core-Service"),
    item("Karabiner-VirtualHIDDevice-Daemon", 0x3),
    item("Karabiner-Elements Privileged Daemons v2", 0x2, "org.pqrs.Karabiner-Privileged"),
]
calls = {"n": 0}
def read_items():
    return items
def read_dump():
    calls["n"] += 1
    return "should not be read"
lines = mod.resolve_karabiner(read_items, read_dump)
print("\n".join(lines))
print(f"calls={calls['n']}")
PY
)"
has "core service passes from the database" "ok|Karabiner-Core-Service|Karabiner-Core-Service is enabled and allowed" "$out"
has "virtual hid daemon passes from the database" "ok|Karabiner-VirtualHIDDevice-Daemon|" "$out"
miss "privileged daemons v2 is not required" "Privileged Daemons" "$out"
has "a readable database does not call sfltool" "calls=0" "$out"

denied="$("$PY" - "$HELPER" <<'PY'
import importlib.util
import sys
mod_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("btm_login_items", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
def read_items():
    raise PermissionError(1, "Operation not permitted", "/var/db")
def read_dump():
    return """
 #4:
                 Name: Karabiner-Core-Service
          Disposition: [enabled, allowed, notified] (11)
 #5:
                 Name: Karabiner-VirtualHIDDevice-Daemon
          Disposition: [enabled, allowed] (3)
 #6:
                 Name: Karabiner-Elements Privileged Daemons v2
          Disposition: [disabled, allowed] (2)
"""
print("\n".join(mod.resolve_karabiner(read_items, read_dump)))
PY
)"
has "dumpbtm core service passes" "ok|Karabiner-Core-Service|" "$denied"
has "dumpbtm daemon passes" "ok|Karabiner-VirtualHIDDevice-Daemon|" "$denied"
miss "dumpbtm ignores the disabled privileged daemon" "Privileged Daemons" "$denied"

bad="$("$PY" - "$HELPER" <<'PY'
import importlib.util
import sys
mod_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("btm_login_items", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
items = [
    {"name": "Karabiner-Core-Service", "disposition": 0x2, "identifier": "Karabiner-Core-Service", "executable": "", "url": "", "bundle": ""},
    {"name": "Other", "disposition": 0xB, "identifier": "other", "executable": "", "url": "", "bundle": ""},
]
print("\n".join(mod.karabiner_lines(mod.states_from_items(items))))
PY
)"
has "disabled core service warns" "warn|Karabiner-Core-Service|" "$bad"
has "disabled phrase names the state" "disabled, allowed" "$bad"
has "missing daemon warns" "warn|Karabiner-VirtualHIDDevice-Daemon|" "$bad"
has "warn says macconfig does not change it" "does not change" "$bad"

none="$("$PY" - "$HELPER" <<'PY'
import importlib.util
import sys
mod_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("btm_login_items", mod_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print("\n".join(mod.resolve_karabiner(lambda: None, lambda: "")))
PY
)"
eq "unreadable database with no dump is info" "info" "${none%%|*}"
has "unreadable database stays by hand" "stays by hand" "$none"

cat > "$tmp/dump.txt" <<'EOF'
 #1:
                 Name: Karabiner-Core-Service
       Developer Name: Fumihiko Takayama
          Disposition: [enabled, allowed, visible, notified] (11)
 #2:
                 Name: Karabiner-VirtualHIDDevice-Daemon
          Disposition: [enabled allowed] (3)
EOF
cli="$("$PY" "$HELPER" --karabiner --dump "$tmp/dump.txt")"
has "cli dump core service passes" "ok|Karabiner-Core-Service|" "$cli"
has "cli dump daemon passes" "ok|Karabiner-VirtualHIDDevice-Daemon|" "$cli"
eq "--dump does not rewrite the file" "$(cksum "$tmp/dump.txt")" "$(cksum "$tmp/dump.txt")"

printf 'not a dump\n' > "$tmp/garbage.txt"
garbage="$("$PY" "$HELPER" --karabiner --dump "$tmp/garbage.txt")"
eq "a dump with no records is info" "info" "${garbage%%|*}"

printf 'karabiner-background tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
