#!/usr/bin/env bash
#
# Finder and Trash tidy settings: the rows in lib/macos-defaults.list, the
# screenshot folder created by install.sh and by macos.sh before the location
# write, and the missing-folder drift in macconfig-check.sh. macos.sh is driven
# with a fake `defaults` and `killall` so this runs on Linux CI and never
# restarts Finder or SystemUIServer. Run: ./tests/finder-tidy.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$DIR/lib/macos-defaults.list"
MACOS="$DIR/macos.sh"
INSTALL="$DIR/install.sh"
CHECK="$DIR/macconfig-check.sh"
# Built so this file does not contain a literal personal home path. Export
# lines under $DIR include that path when the repo is cloned there; the
# assertions below still reject it on the rows and on the write itself.
HOME_MARK="$(printf '%s%s' '/Users/' 'pdone')"

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
miss() {  # description needle haystack
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

rows="$(grep -vE '^[[:space:]]*(#|$)' "$LIST")"
restart_of() {  # domain key
  awk -F'|' -v d="$1" -v k="$2" '$1 == d && $2 == k { print $5; exit }' "$LIST"
}

# ---- list rows (the single source macos.sh and macconfig-check.sh share) ----
for row in \
  'com.apple.finder|FXRemoveOldTrashItems|bool|true|Finder|Finder|Remove Trash items after 30 days|' \
  'com.apple.finder|FXDefaultSearchScope|string|SCcf|Finder|Finder|Search scope|' \
  'com.apple.finder|_FXSortFoldersFirst|bool|true|Finder|Finder|Keep folders on top|' \
  'com.apple.desktopservices|DSDontWriteNetworkStores|bool|true|Finder|Finder|No .DS_Store on network volumes|' \
  'com.apple.screencapture|location|string|@HOME@/Pictures/Screenshots|SystemUIServer|Screenshots|Save location|' \
  'com.apple.screencapture|show-thumbnail|bool|true|SystemUIServer|Screenshots|Floating thumbnail|'
do
  has "defaults row $(printf '%s' "$row" | cut -d'|' -f1-2)" "$row" "$rows"
done

eq "trash items restart Finder" Finder "$(restart_of com.apple.finder FXRemoveOldTrashItems)"
eq "search scope restart Finder" Finder "$(restart_of com.apple.finder FXDefaultSearchScope)"
eq "folders on top restart Finder" Finder "$(restart_of com.apple.finder _FXSortFoldersFirst)"
eq "network .DS_Store restart Finder" Finder "$(restart_of com.apple.desktopservices DSDontWriteNetworkStores)"
eq "screenshot location restarts SystemUIServer" SystemUIServer "$(restart_of com.apple.screencapture location)"
eq "screenshot thumbnail restarts SystemUIServer" SystemUIServer "$(restart_of com.apple.screencapture show-thumbnail)"

eq "search scope value is SCcf" SCcf "$(awk -F'|' '$1=="com.apple.finder" && $2=="FXDefaultSearchScope" { print $4; exit }' "$LIST")"
eq "location uses @HOME@, not a hardcoded home" '@HOME@/Pictures/Screenshots' \
  "$(awk -F'|' '$1=="com.apple.screencapture" && $2=="location" { print $4; exit }' "$LIST")"
miss "location is not the old ~/Pictures row" '|@HOME@/Pictures|SystemUIServer|' "$rows"

eq "dock tilesize stays 28" 'com.apple.dock|tilesize|float|28|Dock|' \
  "$(awk -F'|' '$1=="com.apple.dock" && $2=="tilesize" { print $1"|"$2"|"$3"|"$4"|"$5"|"; exit }' "$LIST")"

# No Downloads cleanup and no periodic move into ~/tmp.
# shellcheck disable=SC2016  # the pattern is a fixed string, not a shell expansion
untidy="$(grep -nE 'Downloads|\$HOME/tmp|~/tmp' "$LIST" "$MACOS" "$INSTALL" "$CHECK" || true)"
eq "no Downloads cleanup or ~/tmp moves" "" "$untidy"
hardcoded="$(grep -n -F "$HOME_MARK" "$LIST" "$MACOS" "$INSTALL" "$CHECK" || true)"
eq "checks expand @HOME@ / \$HOME and do not hardcode a personal home path" "" "$hardcoded"

# shellcheck disable=SC2016  # needles are source text, compared literally
has "install.sh mkdir -p screenshots" 'mkdir -p "$HOME/Pictures/Screenshots"' "$(cat "$INSTALL")"
# shellcheck disable=SC2016
has "macos.sh prepares the screenshot dir before apply" 'ensure_screenshot_dir "$domain" "$key" "$desired"' "$(cat "$MACOS")"
has "check drifts when the screenshot folder is missing" \
  'missing (mkdir -p before setting it)' "$(cat "$CHECK")"
# shellcheck disable=SC2016  # needle is source text, compared literally
has "check displays the screenshot path with a literal tilde" \
  'shot_shown="~${desired#"$HOME"}"' "$(cat "$CHECK")"
has "defaults stay SAFE via macos.sh" 'defaults|SAFE|macos|' "$(grep -v '^#' "$DIR/lib/autofix.list")"

# ---- macos.sh with a fake defaults / killall ----------------------------
tmp="$(mktemp -d)"
bin="$tmp/bin"
state="$tmp/state"
dlog="$tmp/defaults.log"
klog="$tmp/killall.log"
home="$tmp/home"
mkdir -p "$bin" "$home/Pictures"
printf 'keep\n' > "$home/Pictures/already.png"

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
# Fake `defaults` for finder-tidy tests. State lines: domain|key|type|value
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
    flag="${args[3]:-}"
    value="${args[4]:-}"
    if [ "$domain" = com.apple.screencapture ] && [ "$key" = location ]; then
      if [ -d "$value" ]; then
        echo "location-dir-present" >> "${DEFAULTS_LOG:?}"
      else
        echo "location-dir-MISSING" >> "${DEFAULTS_LOG:?}"
      fi
    fi
    printf 'W|%s|%s|%s|%s\n' "$domain" "$key" "$flag" "$value" >> "${DEFAULTS_LOG:?}"
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

is_dir() { if [ -d "$1" ]; then echo yes; else echo no; fi; }

: > "$state"
run_macos() {
  : > "$dlog"
  : > "$klog"
  HOME="$home" PATH="$bin:$PATH" DEFAULTS_LOG="$dlog" DEFAULTS_STATE="$state" KILLALL_LOG="$klog" \
    "$MACOS" --no-color --yes "$@"
}

# Dry-run: decide, create nothing, write nothing.
out="$(run_macos --dry-run --only 'com.apple.screencapture|location')"
rc=$?
eq "dry-run exits 0" 0 "$rc"
has "dry-run would mkdir" "screenshot folder ~/Pictures/Screenshots — would mkdir -p" "$out"
has "dry-run would set the expanded path" "would set (was unset) -> $home/Pictures/Screenshots" "$out"
miss "dry-run output has no hardcoded home" "$HOME_MARK" "$out"
eq "dry-run does not create the folder" no "$(is_dir "$home/Pictures/Screenshots")"
eq "dry-run does not write" "" "$(grep '^W|' "$dlog" || true)"
eq "dry-run does not restart" "" "$(cat "$klog")"
eq "existing picture stays put on dry-run" keep "$(cat "$home/Pictures/already.png")"

# Apply: mkdir before the write, SystemUIServer only, nothing moved.
out="$(run_macos --only 'com.apple.screencapture|location')"
rc=$?
eq "apply location exits 0" 0 "$rc"
has "apply says the folder was created" "screenshot folder ~/Pictures/Screenshots — created" "$out"
has "apply sets the expanded path" "set (was unset) -> $home/Pictures/Screenshots" "$out"
eq "folder exists" yes "$(is_dir "$home/Pictures/Screenshots")"
has "write saw the folder already" "location-dir-present" "$(cat "$dlog")"
miss "write did not race ahead of mkdir" "location-dir-MISSING" "$(cat "$dlog")"
eq "write is -string to the expanded path" "W|com.apple.screencapture|location|-string|$home/Pictures/Screenshots" \
  "$(grep '^W|' "$dlog")"
# Only the write lines: export lines carry the backup path under $DIR, which
# includes HOME_MARK when the repo is cloned under that home.
miss "write value is not a hardcoded home" "$HOME_MARK" "$(grep -E '^(W\||write )' "$dlog" || true)"
eq "location restarts SystemUIServer" SystemUIServer "$(cat "$klog")"
eq "existing picture is not moved" keep "$(cat "$home/Pictures/already.png")"
eq "existing picture is not copied into Screenshots" "" "$(find "$home/Pictures/Screenshots" -type f -print)"
eq "no Downloads folder" no "$(is_dir "$home/Downloads")"
eq "no ~/tmp folder" no "$(is_dir "$home/tmp")"

# Value already correct, folder removed: --only (the fixer) recreates it and does not rewrite.
rmdir "$home/Pictures/Screenshots"
printf 'com.apple.screencapture|location|string|%s\n' "$home/Pictures/Screenshots" > "$state"
out="$(run_macos --only 'com.apple.screencapture|location')"
rc=$?
eq "repair of missing folder exits 0" 0 "$rc"
eq "folder recreated" yes "$(is_dir "$home/Pictures/Screenshots")"
has "fixer notes the mkdir" "already set: $home/Pictures/Screenshots (mkdir -p ~/Pictures/Screenshots)" "$out"
eq "matching value is not rewritten" "" "$(grep '^W|' "$dlog" || true)"
eq "mkdir alone does not restart SystemUIServer" "" "$(cat "$klog")"

# Value and folder already correct: left alone.
out="$(run_macos --only 'com.apple.screencapture|location')"
has "already set is left alone" "already set: $home/Pictures/Screenshots (left alone)" "$out"
miss "no second create" "screenshot folder ~/Pictures/Screenshots — created" "$out"
eq "still no rewrite" "" "$(grep '^W|' "$dlog" || true)"

# Thumbnail does not create the screenshots folder and does not move files.
thumb_home="$tmp/thumb-home"
mkdir -p "$thumb_home"
home="$thumb_home"
: > "$state"
out="$(run_macos --only 'com.apple.screencapture|show-thumbnail')"
rc=$?
eq "thumbnail exits 0" 0 "$rc"
has "thumbnail set true" "com.apple.screencapture show-thumbnail — set (was unset) -> true" "$out"
eq "thumbnail write" "W|com.apple.screencapture|show-thumbnail|-bool|true" "$(grep '^W|' "$dlog")"
eq "thumbnail does not create Screenshots" no "$(is_dir "$home/Pictures/Screenshots")"
eq "thumbnail restarts SystemUIServer" SystemUIServer "$(cat "$klog")"

# desktopservices may not exist yet; the write still happens and restarts Finder.
ds_home="$tmp/ds-home"
mkdir -p "$ds_home"
home="$ds_home"
: > "$state"
out="$(run_macos --only 'com.apple.desktopservices|DSDontWriteNetworkStores')"
rc=$?
eq "desktopservices exits 0" 0 "$rc"
has "desktopservices set true" "com.apple.desktopservices DSDontWriteNetworkStores — set (was unset) -> true" "$out"
eq "desktopservices write" "W|com.apple.desktopservices|DSDontWriteNetworkStores|-bool|true" "$(grep '^W|' "$dlog")"
eq "desktopservices restarts Finder" Finder "$(cat "$klog")"
miss "desktopservices does not restart the Dock" "Dock" "$(cat "$klog")"

printf 'finder-tidy tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
