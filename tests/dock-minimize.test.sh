#!/usr/bin/env bash
#
# Dock minimize-into-app and no-bouncing: the two new com.apple.dock rows in
# lib/macos-defaults.list, restart Dock (same as the existing dock rows), and
# the defaults row in lib/autofix.list. tilesize stays exactly 28. macos.sh is
# driven with a fake `defaults` and `killall` so this runs on Linux CI and
# never restarts a live Dock. Run: ./tests/dock-minimize.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$DIR/lib/macos-defaults.list"
MACOS="$DIR/macos.sh"
DOCKAPPS="$DIR/lib/dock-apps.list"
AUTOFIX="$DIR/lib/autofix.list"

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {  # description needle haystack
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}

rows="$(grep -vE '^[[:space:]]*(#|$)' "$LIST")"
field() {  # domain key field-number (1-based)
  awk -F'|' -v d="$1" -v k="$2" -v f="$3" '$1 == d && $2 == k { print $f; exit }' "$LIST"
}

# ---- list rows (the single source macos.sh and macconfig-check.sh share) ----
for row in \
  'com.apple.dock|minimize-to-application|bool|true|Dock|Dock|Minimize windows into application icon|' \
  'com.apple.dock|no-bouncing|bool|true|Dock|Dock|Animate opening applications|'
do
  has "defaults row $(printf '%s' "$row" | cut -d'|' -f1-2)" "$row" "$rows"
done

eq "minimize-to-application is bool true" true "$(field com.apple.dock minimize-to-application 4)"
eq "no-bouncing is bool true" true "$(field com.apple.dock no-bouncing 4)"
eq "minimize-to-application type is bool" bool "$(field com.apple.dock minimize-to-application 3)"
eq "no-bouncing type is bool" bool "$(field com.apple.dock no-bouncing 3)"
eq "minimize-to-application restarts Dock" Dock "$(field com.apple.dock minimize-to-application 5)"
eq "no-bouncing restarts Dock" Dock "$(field com.apple.dock no-bouncing 5)"
eq "minimize-to-application area is Dock" Dock "$(field com.apple.dock minimize-to-application 6)"
eq "no-bouncing area is Dock" Dock "$(field com.apple.dock no-bouncing 6)"

eq "dock tilesize stays exactly 28" 'com.apple.dock|tilesize|float|28|Dock|Dock|Icon size|' \
  "$(awk -F'|' '$1=="com.apple.dock" && $2=="tilesize" { print $1"|"$2"|"$3"|"$4"|"$5"|"$6"|"$7"|"; exit }' "$LIST")"
eq "autohide stays out of macos-defaults" "" \
  "$(awk -F'|' '$2=="autohide" { print; exit }' "$LIST")"
eq "dock-apps.list stays free of these keys" "" \
  "$(grep -E 'minimize-to-application|no-bouncing|autohide' "$DOCKAPPS" || true)"

defaults_row="$(awk -F'|' '$1=="defaults" { print; exit }' "$AUTOFIX")"
has "autofix defaults row is SAFE via macos" 'defaults|SAFE|macos|' "$defaults_row"
has "autofix defaults row covers minimize into app" "minimize into app" "$defaults_row"
has "autofix defaults row covers no bouncing" "no bouncing" "$defaults_row"
has "autofix defaults row names the Dock restart" "restart Dock" "$defaults_row"
has "autofix still covers window tiling" "window tiling" "$defaults_row"

has "settings names minimize-to-application" "minimize-to-application" "$(cat "$DIR/docs/settings.md")"
has "settings names no-bouncing" "no-bouncing" "$(cat "$DIR/docs/settings.md")"
# shellcheck disable=SC2016  # needle is Markdown from docs/settings.md, compared literally
has "settings records the Dock restart" 'Both set `restart` to `Dock`' "$(cat "$DIR/docs/settings.md")"
# shellcheck disable=SC2016  # needle is Markdown from docs/settings.md, compared literally
has "settings keeps icon size at 28" 'Icon size stays exactly `28`' "$(cat "$DIR/docs/settings.md")"

# ---- macos.sh --list ----------------------------------------------------
list_out="$("$MACOS" --list)"
# shellcheck disable=SC2016  # needles are Markdown from macos.sh --list, compared literally
has "list prints minimize into application icon" \
  '| Dock | Minimize windows into application icon | `com.apple.dock minimize-to-application` | `true` (On) |' \
  "$list_out"
# shellcheck disable=SC2016  # needle is Markdown from macos.sh --list, compared literally
has "list prints no bouncing" \
  '| Dock | Animate opening applications | `com.apple.dock no-bouncing` | `true` (Off — no bounce) |' \
  "$list_out"
# shellcheck disable=SC2016  # needle is Markdown from macos.sh --list, compared literally
has "list still prints tilesize 28" \
  '| Dock | Icon size | `com.apple.dock tilesize` | `28` (exact) |' \
  "$list_out"

# ---- macos.sh with a fake defaults / killall ----------------------------
tmp="$(mktemp -d)"
bin="$tmp/bin"
state="$tmp/state"
dlog="$tmp/defaults.log"
klog="$tmp/killall.log"
mkdir -p "$bin"
dockapps_before="$(cksum "$DOCKAPPS")"

BACKUP_BEFORE=""
if [ -d "$DIR/backups" ]; then
  BACKUP_BEFORE="$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'defaults-*' | sort)"
fi
cleanup() {
  local d now
  if [ -d "$DIR/backups" ]; then
    now="$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'defaults-*' | sort)"
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      case "$BACKUP_BEFORE" in
        *"$d"*) ;;
        *) rm -rf "$d" ;;
      esac
    done <<< "$now"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

cat > "$bin/defaults" <<'EOF'
#!/usr/bin/env bash
# Fake `defaults`. State lines: domain|key|type|value
printf '%s\n' "$*" >> "${DEFAULTS_LOG:?}"
args=("$@")
if [ "${args[0]}" = "-currentHost" ]; then
  args=("${args[@]:1}")
fi
cmd="${args[0]}"
domain="${args[1]:-}"
key="${args[2]:-}"
case "$cmd" in
  read|read-type)
    line="$(awk -F'|' -v d="$domain" -v k="$key" '$1 == d && $2 == k { print; exit }' "${DEFAULTS_STATE:?}")"
    [ -n "$line" ] || exit 1
    if [ "$cmd" = read ]; then
      printf '%s\n' "$(printf '%s\n' "$line" | cut -d'|' -f4-)"
      exit 0
    fi
    typ="$(printf '%s\n' "$line" | cut -d'|' -f3)"
    case "$typ" in
      string) echo "Type is string" ;;
      bool)   echo "Type is boolean" ;;
      int)    echo "Type is integer" ;;
      float)  echo "Type is float" ;;
      *) exit 1 ;;
    esac
    ;;
  export)
    touch "${args[2]}"
    ;;
  write)
    printf 'W|%s|%s|%s|%s\n' "$domain" "$key" "${args[3]:-}" "${args[4]:-}" >> "${DEFAULTS_LOG:?}"
    ;;
  *)
    echo "unexpected defaults $*" >> "${DEFAULTS_LOG:?}"
    exit 1
    ;;
esac
EOF
cat > "$bin/killall" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KILLALL_LOG:?}"
exit 0
EOF
chmod +x "$bin/defaults" "$bin/killall"

MIN='com.apple.dock|minimize-to-application'
BOUNCE='com.apple.dock|no-bouncing'
: > "$state"
run_macos() {
  : > "$dlog"
  : > "$klog"
  PATH="$bin:$PATH" DEFAULTS_LOG="$dlog" DEFAULTS_STATE="$state" KILLALL_LOG="$klog" \
    "$MACOS" --no-color --yes "$@" --only "$MIN" --only "$BOUNCE"
}

writes() { grep '^W|' "$dlog" || true; }

# Both unset: pin true and restart Dock once (the same killall the other dock rows use).
out="$(run_macos)"
rc=$?
eq "pin unset dock behavior exits 0" 0 "$rc"
has "unset minimize-to-application is set true" \
  "com.apple.dock minimize-to-application — set (was unset) -> true" "$out"
has "unset no-bouncing is set true" \
  "com.apple.dock no-bouncing — set (was unset) -> true" "$out"
eq "both keys are written bool true" \
  $'W|com.apple.dock|minimize-to-application|-bool|true\nW|com.apple.dock|no-bouncing|-bool|true' "$(writes)"
eq "one Dock restart" Dock "$(cat "$klog")"
has "restart message names Dock" "Restarting to apply: Dock" "$out"
eq "tilesize is not written" "" "$(writes | grep tilesize || true)"
eq "autohide is not written" "" "$(writes | grep autohide || true)"

# Dry-run writes nothing and restarts nothing.
out="$(run_macos --dry-run)"
rc=$?
eq "dry-run exits 0" 0 "$rc"
has "dry-run would set minimize-to-application" \
  "com.apple.dock minimize-to-application — would set (was unset) -> true" "$out"
eq "dry-run does not write" "" "$(writes)"
eq "dry-run does not restart" "" "$(cat "$klog")"

# Both keys already match (defaults read prints 1 for boolean true).
printf 'com.apple.dock|minimize-to-application|bool|1\ncom.apple.dock|no-bouncing|bool|true\n' > "$state"
out="$(run_macos)"
rc=$?
eq "already-set exits 0" 0 "$rc"
has "minimize-to-application 1 is already true" \
  "com.apple.dock minimize-to-application — already set: 1 (left alone)" "$out"
has "no-bouncing true is already true" \
  "com.apple.dock no-bouncing — already set: true (left alone)" "$out"
eq "already-set writes nothing" "" "$(writes)"
eq "already-set restarts nothing" "" "$(cat "$klog")"

# Drift: bouncing still on (0) is repaired to true, and Dock restarts once.
printf 'com.apple.dock|minimize-to-application|bool|true\ncom.apple.dock|no-bouncing|bool|0\n' > "$state"
out="$(run_macos)"
rc=$?
eq "no-bouncing drift exits 0" 0 "$rc"
has "no-bouncing changes 0 to true" \
  "com.apple.dock no-bouncing — changed: 0 -> true" "$out"
eq "no-bouncing write is -bool true" \
  "W|com.apple.dock|no-bouncing|-bool|true" "$(writes)"
eq "drift restarts Dock" Dock "$(cat "$klog")"
miss_finder="$(grep -c Finder "$klog" || true)"
eq "drift does not restart Finder" 0 "$miss_finder"

eq "dock-apps.list unchanged" "$dockapps_before" "$(cksum "$DOCKAPPS")"

# WhatsApp Web sits between Slack and Granola. A missing copy is the manual
# step, not a hard error. The Safari web-app UUID is not stored in the list.
names="$(awk -F'|' '$1 !~ /^[[:space:]]*#/ && $1 !~ /^[[:space:]]*$/ { print $1 }' "$DOCKAPPS")"
eq "dock order starts Slack, WhatsApp Web, Granola" \
  "$(printf '%s\n' Slack 'WhatsApp Web' Granola)" \
  "$(printf '%s\n' "$names" | head -n 3)"
eq "WhatsApp Web dock row is the manual step" \
  "WhatsApp Web|@HOME@/Applications/WhatsApp Web.app|manual:whatsapp-web" \
  "$(awk -F'|' '$1=="WhatsApp Web" { print; exit }' "$DOCKAPPS")"
eq "dock list does not hard-code a Safari web app UUID" "" \
  "$(grep -E 'com\.apple\.(Safari|safari)\.WebApp\.[0-9A-Fa-f]{8}-' "$DOCKAPPS" || true)"
list_out="$("$DIR/dock.sh" --list)"
has "dock.sh --list names WhatsApp Web second" $' 1. Slack\n 2. WhatsApp Web\n 3. Granola' "$list_out"

docktmp="$(mktemp -d)"
dockbin="$docktmp/bin"
mkdir -p "$dockbin"
cat > "$dockbin/dockutil" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOCK_LOG:?}"
if [ "$1" = "--list" ]; then
  cat "${DOCK_LIST:?}"
fi
exit 0
EOF
cat > "$dockbin/killall" <<'EOF'
#!/usr/bin/env bash
printf 'killall %s\n' "$*" >> "${DOCK_LOG:?}"
exit 0
EOF
chmod +x "$dockbin/dockutil" "$dockbin/killall"
dock_list() { # home, omit_manual (1 to drop manual: rows)
  awk -F'|' -v home="$1" -v omit="$2" '
    $1 ~ /^[[:space:]]*#/ || $1 ~ /^[[:space:]]*$/ { next }
    {
      path = $2
      gsub(/@HOME@/, home, path)
      if (omit == "1" && $3 ~ /^manual:/) next
      enc = path
      gsub(/ /, "%20", enc)
      printf "%s\tfile://%s/\tpersistent-apps\n", $1, enc
    }
  ' "$DOCKAPPS"
}
run_dock() { # home
  : > "$docktmp/log"
  HOME="$1" PATH="$dockbin:$PATH" DOCK_LOG="$docktmp/log" "$DIR/dock.sh"
}
run_check() { # home, omit_manual
  dock_list "$1" "$2" > "$docktmp/list"
  HOME="$1" PATH="$dockbin:$PATH" DOCK_LOG="$docktmp/log" DOCK_LIST="$docktmp/list" \
    "$DIR/macconfig-check.sh" --only dock --no-color
}

miss_home="$docktmp/miss-home"
mkdir -p "$miss_home"
out="$(run_dock "$miss_home")"; rc=$?
eq "dock.sh skips a missing WhatsApp Web" 0 "$rc"
has "dock.sh points at the manual step" \
  "[skip] WhatsApp Web is missing because the manual step hasn't been done (whatsapp-web)" "$out"
eq "dock.sh does not add the missing app" "" \
  "$(grep -F 'WhatsApp Web.app' "$docktmp/log" || true)"

have_home="$docktmp/have-home"
mkdir -p "$have_home/Applications/WhatsApp Web.app"
out="$(run_dock "$have_home")"; rc=$?
eq "dock.sh adds WhatsApp Web when the app exists" 0 "$rc"
has "dock.sh adds the web app path" \
  "--add $have_home/Applications/WhatsApp Web.app" "$(cat "$docktmp/log")"
eq "dock.sh does not skip WhatsApp Web when it exists" "" \
  "$(printf '%s\n' "$out" | grep '\[skip\] WhatsApp Web' || true)"

out="$(run_check "$miss_home" 1)"; rc=$?
eq "macconfig does not fail when WhatsApp Web is missing" 0 "$rc"
has "macconfig says the manual step hasn't been done" \
  "WhatsApp Web is missing because the manual step hasn't been done (whatsapp-web)" "$out"
eq "a missing WhatsApp Web is not drift" "" \
  "$(printf '%s\n' "$out" | grep 'DRIFT' || true)"

out="$(run_check "$have_home" 0)"; rc=$?
eq "macconfig passes when WhatsApp Web is in the Dock" 0 "$rc"
eq "an installed WhatsApp Web is not called missing" "" \
  "$(printf '%s\n' "$out" | grep "manual step hasn't been done" || true)"
has "dock order matches with WhatsApp Web included" "Dock matches lib/dock-apps.list" "$out"

out="$(run_check "$have_home" 1)"; rc=$?
eq "an installed WhatsApp Web missing from the Dock is drift" 1 "$rc"
has "drift names WhatsApp Web" "WhatsApp Web" "$out"

rm -rf "$docktmp"

printf 'dock-minimize tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
