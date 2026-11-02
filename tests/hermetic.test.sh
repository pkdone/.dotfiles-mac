#!/usr/bin/env bash
#
# The safe PATH hides host commands even when they sit earlier on the
# inherited PATH. The configured-Mac stubs answer as a machine that is
# already set up, so a test that falls through to $PATH cannot pass by
# accident on Linux.
# Run: ./tests/hermetic.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"

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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
safe="$(hermetic_safe_root)"
eq "safe path is a directory" "dir" "$([ -d "$safe" ] && echo dir || echo missing)"
eq "safe path is published only when finished" "ready" "$([ -f "$safe/.ready" ] && echo ready || echo partial)"
eq "safe path provides awk" "awk" "$(PATH="$safe" command -v awk >/dev/null && echo awk || echo missing)"
eq "safe path provides python3" "python3" "$(PATH="$safe" command -v python3 >/dev/null && echo python3 || echo missing)"
eq "safe path provides perl" "perl" "$(PATH="$safe" command -v perl >/dev/null && echo perl || echo missing)"

# A cold cache with several callers at once. The directory must not be
# visible until python3, perl, cut, and rm are all linked. Callers share
# one published path. This override is private so the test does not remove
# the cache other suites are using.
cache="$tmp/cache"
mkdir -p "$tmp/parallel"
i=0
while [ "$i" -lt 8 ]; do
  (
    unset HERMETIC_SAFE_DIR
    # Read by hermetic_safe_root after this file is sourced below.
    # shellcheck disable=SC2034
    HERMETIC_SAFE_OVERRIDE="$cache"
    export HERMETIC_SAFE_OVERRIDE
    # shellcheck source=hermetic.sh disable=SC1091
    . "$DIR/tests/hermetic.sh"
    hermetic_safe_root
  ) > "$tmp/parallel/$i" &
  i=$((i + 1))
done
wait
i=0
while [ "$i" -lt 8 ]; do
  got="$(cat "$tmp/parallel/$i")"
  eq "parallel caller $i uses the published directory" "$cache" "$got"
  eq "parallel caller $i is finished" "ready" "$([ -f "$got/.ready" ] && echo ready || echo partial)"
  for cmd in awk python3 perl cut rm; do
    eq "parallel caller $i has $cmd" "yes" "$([ -x "$got/$cmd" ] && echo yes || echo no)"
  done
  eq "parallel caller $i hides lpstat" "no" "$([ -e "$got/lpstat" ] && echo yes || echo no)"
  i=$((i + 1))
done

decoy="$tmp/decoy"
mkdir -p "$decoy"
cat > "$decoy/lpstat" <<'EOF'
#!/bin/sh
printf '%s\n' "printer HP_ENVY_6000_series is idle"
exit 0
EOF
chmod +x "$decoy/lpstat"
found="$(PATH="$decoy:$PATH" command -v lpstat || true)"
eq "a planted lpstat is what an inherited PATH would run" "$decoy/lpstat" "$found"
closed="$(PATH="$safe" command -v lpstat || true)"
eq "the safe path does not see a planted lpstat" "" "$closed"
for cmd in pmset system_profiler displayplacer sfltool shortcuts dscl defaults ioreg osascript open; do
  hit="$(PATH="$safe" command -v "$cmd" || true)"
  eq "the safe path hides $cmd" "" "$hit"
done

conf="$(hermetic_configured_root "$tmp/configured")"
printer="$(PATH="$conf:$safe" lpstat -p)"
has "configured lpstat names the home printer" "HP_ENVY_6000" "$printer"
power="$(PATH="$conf:$safe" pmset -g custom)"
has "configured pmset has AC sleep 0" "sleep                0" "$power"
short="$(PATH="$conf:$safe" shortcuts list)"
has "configured shortcuts list Mode WebConf On" "Mode WebConf On" "$short"
eq "configured brightness stub is executable" "yes" \
  "$([ -x "$conf/corebrightnessdiag" ] && echo yes || echo no)"

# BTM_DIR is the only way to keep --karabiner off the real database.
# A store file that is not a plist is parsed, so the message says
# "Invalid file". The default directory is not consulted: on Linux that
# directory is missing and the message would not mention a bad file, and
# on a Mac it would be the real login-item database.
mkdir -p "$tmp/btm"
printf 'not a plist\n' > "$tmp/btm/BackgroundItems-v9.btm"
btm="$(BTM_DIR="$tmp/btm" PATH="$safe" python3 "$DIR/lib/btm-login-items.py" --karabiner 2>&1 || true)"
has "BTM_DIR is the store that was read" "Invalid file" "$btm"

has "display check uses the same diag override as bootstrap" \
  'AUTO_BRIGHTNESS_DIAG:-/usr/libexec/corebrightnessdiag' "$(cat "$DIR/checks/display.sh")"

# The Hammerspoon start and the Desktop apply are the shared helper. Under the
# safe PATH, open / pgrep / defaults are hidden, so a test can prove the helper
# does not touch this machine.
# shellcheck source=../lib/safe-fixers.sh disable=SC1091
. "$DIR/lib/safe-fixers.sh"
fixer="$(cat "$DIR/lib/safe-fixers.sh")"
has "Hammerspoon check can point at a fake app" \
  'HAMMERSPOON_APP:-/Applications/Hammerspoon.app' "$fixer"

hsbin="$tmp/hsbin"
mkdir -p "$hsbin" "$tmp/hs-app"
open_log="$tmp/open.log"
pgrep_count="$tmp/pgrep.count"
: > "$open_log"
printf '0\n' > "$pgrep_count"
cat > "$hsbin/open" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${OPEN_LOG:?}"
exit 0
EOF
cat > "$hsbin/pgrep" <<'EOF'
#!/bin/sh
n="${PGREP_COUNT:?}"
c=0
[ -f "$n" ] && c="$(cat "$n")"
c=$((c + 1))
printf '%s\n' "$c" > "$n"
# The first look is "already running?" and misses. Later looks see it up,
# so the start path does not sleep.
if [ "$c" -eq 1 ]; then
  exit 1
fi
exit 0
EOF
chmod +x "$hsbin/open" "$hsbin/pgrep"

miss_out="$(PATH="$hsbin:$safe" HAMMERSPOON_APP="$tmp/no-such-app" DRY_RUN=0 \
  SAFE_HAMMERSPOON_DESCRIBE=0 OPEN_LOG="$open_log" PGREP_COUNT="$pgrep_count" \
  safe_start_hammerspoon 2>&1)" || miss_rc=$?
miss_rc=${miss_rc:-0}
eq "missing Hammerspoon is refused" 2 "$miss_rc"
has "missing Hammerspoon names brewsync" "Hammerspoon.app not installed — run brewsync" "$miss_out"
eq "missing Hammerspoon does not call open" "" "$(cat "$open_log")"

: > "$open_log"
desc_out="$(PATH="$hsbin:$safe" HAMMERSPOON_APP="$tmp/no-such-app" DRY_RUN=1 \
  SAFE_HAMMERSPOON_DESCRIBE=1 OPEN_LOG="$open_log" PGREP_COUNT="$pgrep_count" \
  safe_start_hammerspoon 2>&1)" || desc_rc=$?
desc_rc=${desc_rc:-0}
eq "install dry-run description exits 0 when the app is absent" 0 "$desc_rc"
has "install dry-run description names the open command" \
  "would start Hammerspoon (open -g -a Hammerspoon) if it is installed and not running" "$desc_out"
eq "install dry-run description does not call open" "" "$(cat "$open_log")"

printf '0\n' > "$pgrep_count"
: > "$open_log"
run_out="$(PATH="$hsbin:$safe" HAMMERSPOON_APP="$tmp/hs-app" DRY_RUN=1 \
  SAFE_HAMMERSPOON_DESCRIBE=0 OPEN_LOG="$open_log" PGREP_COUNT="$pgrep_count" \
  safe_start_hammerspoon 2>&1)" || run_rc=$?
run_rc=${run_rc:-0}
eq "dry-run with the app installed exits 0" 0 "$run_rc"
has "dry-run would start Hammerspoon" "would start Hammerspoon (open -g -a Hammerspoon)" "$run_out"
eq "dry-run does not call open" "" "$(cat "$open_log")"

printf '0\n' > "$pgrep_count"
# Already running: the first pgrep must succeed. Swap in a stub that always hits.
cat > "$hsbin/pgrep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$hsbin/pgrep"
: > "$open_log"
already="$(PATH="$hsbin:$safe" HAMMERSPOON_APP="$tmp/hs-app" DRY_RUN=0 \
  SAFE_HAMMERSPOON_DESCRIBE=0 OPEN_LOG="$open_log" \
  safe_start_hammerspoon 2>&1)" || already_rc=$?
already_rc=${already_rc:-0}
eq "already running exits 0" 0 "$already_rc"
has "already running is reported" "Hammerspoon already running" "$already"
eq "already running does not call open" "" "$(cat "$open_log")"

cat > "$hsbin/pgrep" <<'EOF'
#!/bin/sh
n="${PGREP_COUNT:?}"
c=0
[ -f "$n" ] && c="$(cat "$n")"
c=$((c + 1))
printf '%s\n' "$c" > "$n"
if [ "$c" -eq 1 ]; then
  exit 1
fi
exit 0
EOF
chmod +x "$hsbin/pgrep"
printf '0\n' > "$pgrep_count"
: > "$open_log"
started="$(PATH="$hsbin:$safe" HAMMERSPOON_APP="$tmp/hs-app" DRY_RUN=0 \
  SAFE_HAMMERSPOON_DESCRIBE=0 OPEN_LOG="$open_log" PGREP_COUNT="$pgrep_count" \
  safe_start_hammerspoon 2>&1)" || started_rc=$?
started_rc=${started_rc:-0}
eq "start exits 0" 0 "$started_rc"
has "start reports that Hammerspoon started" "started Hammerspoon" "$started"
has "start uses open -g -a Hammerspoon" "-g -a Hammerspoon" "$(cat "$open_log")"

desk_out="$(PATH="$safe" safe_apply_desktops --dry-run 2>&1)" || desk_rc=$?
desk_rc=${desk_rc:-0}
eq "desktop apply without defaults fails closed" 2 "$desk_rc"
has "desktop apply without defaults does not claim a write" "could not read com.apple.spaces" "$desk_out"

inst_home="$tmp/inst-home"
inst="$(HOME="$inst_home" "$DIR/install.sh" --dry-run 2>&1)" || inst_rc=$?
inst_rc=${inst_rc:-0}
eq "install.sh --dry-run exits 0" 0 "$inst_rc"
has "install.sh --dry-run describes the Hammerspoon start" \
  "would start Hammerspoon (open -g -a Hammerspoon)" "$inst"
has "install.sh --dry-run says nothing is changed" "nothing is changed" "$inst"
eq "install.sh --dry-run does not create Developer" "no" \
  "$([ -d "$inst_home/Developer" ] && echo yes || echo no)"

printf 'hermetic tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
