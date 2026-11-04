#!/usr/bin/env bash
#
# Services kept off (pbs NSServicesStatus). The keys come from
# lib/services-off.list. A listed key that is already off is not written.
# A drifted key is merged with -dict-add. Other services stay. pbs -flush
# runs once after a write, and not when nothing changed. enabled=0 and
# enabled=false both count as off. macOS Tahoe quotes some field names.
# tests/fixtures/pbs-NSServicesStatus-off.txt is that defaults read output.
# A quoted 0 is off. A quoted 1 is still drift.
# Run: ./tests/services-off.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN="$DIR/scripts/pin-services-off.sh"
MACOS="$DIR/macos.sh"
LIST="$DIR/lib/services-off.list"
FIXTURE="$DIR/tests/fixtures/pbs-NSServicesStatus-off.txt"
SAFARI="com.apple.Safari - Add to Reading List - addToReadingList"
STICKIES="com.apple.Stickies - Make Sticky - makeStickyFromTextService"
BEFORE="com.example.Before - Leave On - leaveOn"
KEEP="com.example.Keep - Leave On - leaveOn"

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
state="$tmp/services.txt"
dlog="$tmp/defaults.log"
plog="$tmp/pbs.log"
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
if [ "$1" = "-currentHost" ]; then shift; fi
cmd="$1"
domain="${2:-}"
key="${3:-}"
if [ "$cmd" = read ] && [ "$domain" = pbs ] && [ "$key" = NSServicesStatus ]; then
  if [ "${SERVICES_FAIL:-}" = 1 ]; then exit 1; fi
  cat "${SERVICES_STATE:?}"
  exit 0
fi
if [ "$cmd" = write ]; then
  printf 'WRITE %s\n' "$*" >> "${DEFAULTS_LOG:?}"
  exit 0
fi
exit 0
EOF
cat > "$bin/pbs" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${PBS_LOG:?}"
exit 0
EOF
chmod +x "$bin/defaults" "$bin/pbs"

list_keys() {
  awk '
    /^[[:space:]]*($|#)/ { next }
    {
      sub(/[[:space:]]*#.*$/, "")
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      if ($0 != "") print
    }
  ' "$LIST"
}

# $1 is a key to vary, or empty. $2 is off, on, partial, modes, absent, or false.
# Every other listed key is fully off. A keeper service stays on.
write_status() {
  local vary="$1" how="$2" key form cm sm pcm psm
  form="${3:-0}"
  {
    echo '{'
    while IFS= read -r key; do
      [ -n "$key" ] || continue
      cm=$form; sm=$form; pcm=$form; psm=$form
      if [ "$key" = "$vary" ]; then
        case "$how" in
          absent) continue ;;
          on) cm=1; sm=1; pcm=1; psm=1 ;;
          partial) cm=""; sm=0; pcm=""; psm="" ;;
          modes) cm=0; sm=0; pcm=1; psm=0 ;;
          false) cm=false; sm=false; pcm=false; psm=false ;;
          off) ;;
        esac
      fi
      printf '    "%s" =     {\n' "$key"
      if [ -n "$cm" ]; then printf '        enabled_context_menu = %s;\n' "$cm"; fi
      if [ -n "$sm" ]; then printf '        enabled_services_menu = %s;\n' "$sm"; fi
      if [ -n "$pcm" ] || [ -n "$psm" ]; then
        echo '        presentation_modes =         {'
        if [ -n "$pcm" ]; then printf '            ContextMenu = %s;\n' "$pcm"; fi
        if [ -n "$psm" ]; then printf '            ServicesMenu = %s;\n' "$psm"; fi
        echo '        };'
      fi
      echo '    };'
    done <<EOF
$(list_keys)
EOF
    cat <<EOF
    "$KEEP" =     {
        enabled_context_menu = 1;
        enabled_services_menu = 1;
        presentation_modes =         {
            ContextMenu = 1;
            ServicesMenu = 1;
        };
    };
}
EOF
  } > "$state"
}

run_pin() {
  : > "$dlog"
  : > "$plog"
  HOME="$home" PATH="$bin:$PATH" DEFAULTS_LOG="$dlog" SERVICES_STATE="$state" \
    SERVICES_FAIL="${SERVICES_FAIL:-}" DOTFILES_PBS="$bin/pbs" PBS_LOG="$plog" \
    "$@"
}
write_count() { grep -c '^WRITE ' "$dlog" || true; }
writes() { grep '^WRITE ' "$dlog" || true; }
flush_count() { grep -c -e '-flush' "$plog" || true; }

expected="$(cat <<'EOF'
com.apple.Safari - Add to Reading List - addToReadingList
com.apple.ChineseTextConverterService - Convert Text from Simplified to Traditional Chinese - convertTextToTraditionalChinese
com.apple.ChineseTextConverterService - Convert Text from Traditional to Simplified Chinese - convertTextToSimplifiedChinese
com.apple.Stickies - Make Sticky - makeStickyFromTextService
com.apple.Terminal - Open man Page in Terminal - openManPage
com.apple.Terminal - Search man Page Index in Terminal - searchManPages
com.apple.services.addToiTunesAsSpokenTrack - Add to Music as a Spoken Track - runWorkflowAsService
com.apple.services.showMap - Show Map - runWorkflowAsService
org.hammerspoon.Hammerspoon - Send to Hammerspoon - processDockIconDraggedText
EOF
)"
eq "list is those nine services, in order" "$expected" "$(list_keys)"
miss "CotEditor is not a pinned key" "CotEditor" "$(list_keys)"
miss "TextEdit is not a pinned key" "TextEdit" "$(list_keys)"
miss "Summarise is not a pinned key" "Summarise" "$(list_keys)"
miss "pin script does not hardcode a service key" "addToReadingList" "$(cat "$PIN")"
miss "check does not hardcode a service key" "addToReadingList" "$(cat "$DIR/checks/hotkeys.sh")"
has "pin script flushes with pbs" "/System/Library/CoreServices/pbs" "$(cat "$PIN")"
has "pin script merges with dict-add" "-dict-add" "$(cat "$PIN")"

SERVICES_FAIL=0
write_status "" off 0
out="$(run_pin "$PIN" --check)"
rc=$?
ok "all off --check exits 0" "$rc"
has "all off --check says off" "ok (off)" "$out"
out="$(run_pin "$PIN")"
rc=$?
ok "all off pin exits 0" "$rc"
has "all off pin leaves them alone" "left alone" "$out"
eq "all off pin does not write" 0 "$(write_count)"
eq "all off pin does not flush" 0 "$(flush_count)"

write_status "" off false
out="$(run_pin "$PIN" --check)"
rc=$?
ok "enabled=false --check exits 0" "$rc"
out="$(run_pin "$PIN")"
eq "enabled=false does not write" 0 "$(write_count)"
eq "enabled=false does not flush" 0 "$(flush_count)"

write_status "$SAFARI" on
out="$(run_pin "$PIN" --check)"
rc=$?
eq "one on --check fails" 1 "$rc"
has "one on --check names Safari" "$SAFARI" "$out"
miss "one on --check does not name Stickies" "$STICKIES" "$out"
out="$(run_pin "$PIN")"
rc=$?
ok "one on pin exits 0" "$rc"
eq "one on pin writes once" 1 "$(write_count)"
has "one on pin uses dict-add" "NSServicesStatus -dict-add" "$(writes)"
has "one on pin writes the Safari key" "$SAFARI" "$(writes)"
has "one on pin writes both menus off" "enabled_context_menu = 0" "$(writes)"
has "one on pin writes the services menu off" "enabled_services_menu = 0" "$(writes)"
has "one on pin writes ContextMenu off" "ContextMenu = 0" "$(writes)"
has "one on pin writes ServicesMenu off" "ServicesMenu = 0" "$(writes)"
miss "one on pin does not replace the whole dict" "NSServicesStatus -dict " "$(writes)"
miss "one on pin does not rewrite Stickies" "$STICKIES" "$(writes)"
miss "one on pin does not write the service left on" "$KEEP" "$(writes)"
eq "one on pin flushes once" 1 "$(flush_count)"
eq "flush is pbs -flush" "-flush" "$(cat "$plog")"

write_status "$STICKIES" partial
out="$(run_pin "$PIN" --check)"
rc=$?
eq "Stickies partial --check fails" 1 "$rc"
has "Stickies partial --check names Stickies" "$STICKIES" "$out"
out="$(run_pin "$PIN")"
eq "Stickies partial writes once" 1 "$(write_count)"
has "Stickies partial writes both menus" "enabled_context_menu = 0" "$(writes)"
has "Stickies partial writes the Stickies key" "$STICKIES" "$(writes)"
miss "Stickies partial does not rewrite Safari" "$SAFARI" "$(writes)"
eq "Stickies partial flushes once" 1 "$(flush_count)"

write_status "$SAFARI" modes
out="$(run_pin "$PIN")"
eq "presentation mode on is a write" 1 "$(write_count)"
has "presentation mode write names Safari" "$SAFARI" "$(writes)"

write_status "$SAFARI" absent
out="$(run_pin "$PIN")"
eq "missing key is written" 1 "$(write_count)"
has "missing key write names Safari" "$SAFARI" "$(writes)"
miss "missing key write leaves the keeper" "$KEEP" "$(writes)"

# Two drifted keys: Safari on, and Stickies with only the Services menu saved.
{
  echo '{'
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    if [ "$key" = "$SAFARI" ]; then
      cat <<EOF
    "$key" =     {
        enabled_context_menu = 1;
        enabled_services_menu = 1;
        presentation_modes =         {
            ContextMenu = 1;
            ServicesMenu = 1;
        };
    };
EOF
    elif [ "$key" = "$STICKIES" ]; then
      cat <<EOF
    "$key" =     {
        enabled_services_menu = 0;
    };
EOF
    else
      cat <<EOF
    "$key" =     {
        enabled_context_menu = 0;
        enabled_services_menu = 0;
        presentation_modes =         {
            ContextMenu = 0;
            ServicesMenu = 0;
        };
    };
EOF
    fi
  done <<EOF
$(list_keys)
EOF
  echo '}'
} > "$state"
out="$(run_pin "$PIN")"
eq "two drifted keys write twice" 2 "$(write_count)"
eq "two drifted keys flush once" 1 "$(flush_count)"
has "two drifted keys include Safari" "$SAFARI" "$(writes)"
has "two drifted keys include Stickies" "$STICKIES" "$(writes)"

export MACCONFIG_CHECKS_DEFINE_ONLY=1 DOTDIR="$DIR"
# shellcheck disable=SC1091
. "$DIR/checks/hotkeys.sh"
unset MACCONFIG_CHECKS_DEFINE_ONLY
hdr() { :; }
fixid() { :; }
CHECKED=0
bad() { printf 'BAD %s\n' "$1"; }
pass() { printf 'PASS %s\n' "$1"; }
run_check() {
  PATH="$bin:$PATH" SERVICES_STATE="$state" DEFAULTS_LOG="$dlog" \
    SERVICES_FAIL="${SERVICES_FAIL:-}" check_services_off
}

write_status "" off 0
out="$(run_check)"
has "check passes when every listed service is off" \
  "PASS Services shortcuts in lib/services-off.list are off" "$out"
miss "check does not drift when off" "BAD Services shortcuts still on" "$out"

write_status "" off false
out="$(run_check)"
has "check passes when the flags are false" \
  "PASS Services shortcuts in lib/services-off.list are off" "$out"

write_status "$SAFARI" on
out="$(run_check)"
has "check names Safari when it is on" "BAD Services shortcuts still on: $SAFARI " "$out"
has "check tells macconfig --fix" "macconfig --fix" "$out"
miss "check does not name Stickies when only Safari is on" "$STICKIES" "$out"

write_status "$STICKIES" partial
out="$(run_check)"
has "check names Stickies when only one menu is saved" "BAD Services shortcuts still on: $STICKIES " "$out"

SERVICES_FAIL=1
out="$(run_check)"
has "check drifts when NSServicesStatus cannot be read" "BAD pbs NSServicesStatus not readable" "$out"
SERVICES_FAIL=0

run_macos() {
  : > "$dlog"
  : > "$plog"
  PATH="$bin:/usr/bin:/bin" HOME="$home" DEFAULTS_LOG="$dlog" SERVICES_STATE="$state" \
    SERVICES_FAIL="${SERVICES_FAIL:-}" DOTFILES_PBS="$bin/pbs" PBS_LOG="$plog" \
    "$MACOS" --no-color --yes "$@"
}
write_status "" off 0
out="$(run_macos --only @services-off)"
rc=$?
note_backups "$out"
ok "macos leaves off services" "$rc"
has "macos says left alone" "Services shortcuts already off (left alone)" "$out"
miss "a match does not write a restore snapshot" "backups -> " "$out"
eq "macos does not write when every key matches" 0 "$(write_count)"
eq "macos does not flush when every key matches" 0 "$(flush_count)"

write_status "$SAFARI" on
out="$(run_macos --dry-run --only @services-off)"
rc=$?
note_backups "$out"
ok "macos dry-run does not fail" "$rc"
has "macos dry-run names the change" "Services shortcuts -> off (dry-run)" "$out"
eq "macos dry-run does not write" 0 "$(write_count)"
eq "macos dry-run does not flush" 0 "$(flush_count)"
miss "dry-run does not snapshot" "backups -> " "$out"

write_status "$SAFARI" on
out="$(run_macos --only @services-off)"
rc=$?
note_backups "$out"
ok "macos repairs a service that is on" "$rc"
has "macos reports the change" "Services shortcuts -> off" "$out"
eq "macos writes once when one key differs" 1 "$(write_count)"
eq "macos flushes once" 1 "$(flush_count)"
has "a change names its own restore snapshot" "backups -> " "$out"
eq "a change names one restore snapshot" 1 \
  "$(printf '%s\n' "$out" | grep -c 'backups -> ' || true)"
miss "macos does not write the service left on" "$KEEP" "$(writes)"

# Tahoe `defaults read`: quoted menu names, bare ContextMenu / ServicesMenu,
# service keys with spaces and hyphens. An unlisted service stays on at
# either end so a block that runs past its closing brace looks like drift.
has "fixture quotes the menu name" '        "enabled_context_menu" = 0;' "$(cat "$FIXTURE")"
has "fixture quotes the services menu" '        "enabled_services_menu" = 0;' "$(cat "$FIXTURE")"
has "fixture quotes presentation_modes" '        "presentation_modes" =         {' "$(cat "$FIXTURE")"
has "fixture leaves ContextMenu bare" '            ContextMenu = 0;' "$(cat "$FIXTURE")"
has "fixture leaves ServicesMenu bare" '            ServicesMenu = 0;' "$(cat "$FIXTURE")"
has "fixture quotes the Safari key" "    \"$SAFARI\" =     {" "$(cat "$FIXTURE")"
has "fixture leaves another service on" '        "enabled_context_menu" = 1;' "$(cat "$FIXTURE")"
while IFS= read -r key; do
  has "fixture includes $key" "\"$key\"" "$(cat "$FIXTURE")"
done <<EOF
$(list_keys)
EOF

cp "$FIXTURE" "$state"
out="$(run_pin "$PIN" --check)"
rc=$?
ok "quoted off --check exits 0" "$rc"
has "quoted off --check says off" "ok (off)" "$out"
out="$(run_pin "$PIN")"
rc=$?
ok "quoted off pin exits 0" "$rc"
has "quoted off pin leaves them alone" "left alone" "$out"
eq "quoted off pin does not write" 0 "$(write_count)"
eq "quoted off pin does not flush" 0 "$(flush_count)"
miss "quoted off pin does not write the service before" "$BEFORE" "$(writes)"
miss "quoted off pin does not write the keeper" "$KEEP" "$(writes)"
out="$(run_check)"
has "quoted check passes when every listed service is off" \
  "PASS Services shortcuts in lib/services-off.list are off" "$out"
miss "quoted check does not drift when off" "BAD Services shortcuts still on" "$out"
out="$(run_macos --only @services-off)"
rc=$?
note_backups "$out"
ok "macos leaves quoted-off services" "$rc"
has "macos says quoted services were left alone" "Services shortcuts already off (left alone)" "$out"
eq "macos does not write when the quoted keys are off" 0 "$(write_count)"
eq "macos does not flush when the quoted keys are off" 0 "$(flush_count)"

# false, with the same quoted names Tahoe prints for 0.
awk '{ gsub(/ = 0;/, " = false;"); print }' "$FIXTURE" > "$state"
out="$(run_pin "$PIN" --check)"
rc=$?
ok "quoted false --check exits 0" "$rc"
out="$(run_pin "$PIN")"
eq "quoted false does not write" 0 "$(write_count)"
out="$(run_check)"
has "quoted check passes when the flags are false" \
  "PASS Services shortcuts in lib/services-off.list are off" "$out"

# Nested presentation names quoted as well. Still off.
awk '{
  gsub(/ContextMenu = /, "\"ContextMenu\" = ")
  gsub(/ServicesMenu = /, "\"ServicesMenu\" = ")
  print
}' "$FIXTURE" > "$state"
out="$(run_pin "$PIN" --check)"
rc=$?
ok "quoted ContextMenu --check exits 0" "$rc"
out="$(run_check)"
has "quoted check passes when ContextMenu is quoted" \
  "PASS Services shortcuts in lib/services-off.list are off" "$out"

# Safari's context menu is on. The other listed services stay off.
awk '
  /Add to Reading List/ { grab = 1 }
  grab && /"enabled_context_menu"/ { sub(/= 0;/, "= 1;"); grab = 0 }
  { print }
' "$FIXTURE" > "$state"
out="$(run_pin "$PIN" --check)"
rc=$?
eq "quoted safari on --check fails" 1 "$rc"
has "quoted safari on --check names Safari" "$SAFARI" "$out"
miss "quoted safari on --check does not name Stickies" "$STICKIES" "$out"
miss "quoted safari on --check does not name the keeper" "$KEEP" "$out"
out="$(run_pin "$PIN")"
eq "quoted safari on writes once" 1 "$(write_count)"
has "quoted safari on uses dict-add" "NSServicesStatus -dict-add" "$(writes)"
has "quoted safari on writes the Safari key" "$SAFARI" "$(writes)"
miss "quoted safari on does not write Stickies" "$STICKIES" "$(writes)"
miss "quoted safari on does not write the service before" "$BEFORE" "$(writes)"
miss "quoted safari on does not write the keeper" "$KEEP" "$(writes)"
eq "quoted safari on flushes once" 1 "$(flush_count)"
out="$(run_check)"
has "quoted check names Safari when the menu is on" "BAD Services shortcuts still on: $SAFARI " "$out"
miss "quoted check does not name Stickies when only Safari is on" "$STICKIES" "$out"
out="$(run_macos --dry-run --only @services-off)"
rc=$?
note_backups "$out"
ok "macos dry-run sees the quoted menu that is on" "$rc"
has "macos dry-run names the quoted change" "Services shortcuts -> off (dry-run)" "$out"
eq "macos dry-run does not write the quoted menu" 0 "$(write_count)"
out="$(run_macos --only @services-off)"
rc=$?
note_backups "$out"
ok "macos repairs the quoted menu that is on" "$rc"
eq "macos writes once for the quoted menu" 1 "$(write_count)"
eq "macos flushes once for the quoted menu" 1 "$(flush_count)"
miss "macos does not write the quoted keeper" "$KEEP" "$(writes)"

# Menus off, ContextMenu on. Still drift.
awk '
  /Add to Reading List/ { grab = 1 }
  grab && /ContextMenu = 0;/ { sub(/= 0;/, "= 1;"); grab = 0 }
  { print }
' "$FIXTURE" > "$state"
out="$(run_pin "$PIN" --check)"
rc=$?
eq "quoted ContextMenu on --check fails" 1 "$rc"
has "quoted ContextMenu on --check names Safari" "$SAFARI" "$out"
miss "quoted ContextMenu on --check does not name Stickies" "$STICKIES" "$out"
out="$(run_check)"
has "quoted check names Safari when ContextMenu is on" "BAD Services shortcuts still on: $SAFARI " "$out"
out="$(run_pin "$PIN")"
eq "quoted ContextMenu on writes once" 1 "$(write_count)"
has "quoted ContextMenu on writes the Safari key" "$SAFARI" "$(writes)"

printf 'services-off tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
