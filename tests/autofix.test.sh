#!/usr/bin/env bash
#
# Unit tests for lib/autofix.list + lib/autofix-lib.sh — the safe / needs-Paul split used
# by `macconfig-check.sh --fix`. Plain bash + awk + grep (runs on Linux CI; nothing macOS-specific
# is executed). Run: ./tests/autofix.test.sh   (exits non-zero if any assertion fails)
#
set -uo pipefail   # deliberately not -e: run every assertion, then tally failures

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$DIR/lib/autofix.list"
# shellcheck source=../lib/autofix-lib.sh disable=SC1091
. "$DIR/lib/autofix-lib.sh"

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
miss() {  # description needle haystack
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;;
    *) pass=$((pass + 1)) ;; esac
}

rows() { awk -F'|' '$1 !~ /^#/ && NF' "$LIST"; }

# ---- the list is well formed ----
bad_rows="$(rows | awk -F'|' '
  NF != 4                                   { print NR ": " $0 " (want 4 fields)"; next }
  $2 != "SAFE" && $2 != "PAUL"              { print NR ": " $0 " (class must be SAFE or PAUL)"; next }
  $2 == "SAFE" && $3 !~ /^(macos|launchagent|symlink|hammerspoon|desktop|fileext|dockrestart|origin|tailscale)$/ { print NR ": " $0 " (unknown fixer)"; next }
  $2 == "PAUL" && $3 != ""                  { print NR ": " $0 " (PAUL rows have no fixer)"; next }
  $4 == ""                                  { print NR ": " $0 " (missing description)"; next }
  $1 !~ /^[a-z0-9-]+$/                      { print NR ": " $0 " (id must be [a-z0-9-])" }')"
eq "every autofix.list row is well formed" "" "$bad_rows"
eq "ids are unique" "" "$(rows | cut -d'|' -f1 | sort | uniq -d)"

# ---- the classes Paul asked for ----
for id in defaults dictation-164 quicknote-190 gameoverlay-260 spotlight-64 services-off finder-icon-view finder-recents coteditor launchagent symlink hammerspoon origin tailscale-exit desktop-assign file-handler display-more-space arzopa-display dock-space; do
  eq "$id is SAFE" SAFE "$(autofix_class "$LIST" "$id")"
done
eq "desktop-assign fixer is desktop" desktop "$(autofix_lookup "$LIST" desktop-assign | cut -d'|' -f2)"
eq "file-handler fixer is fileext" fileext "$(autofix_lookup "$LIST" file-handler | cut -d'|' -f2)"
eq "dock-space fixer is dockrestart" dockrestart "$(autofix_lookup "$LIST" dock-space | cut -d'|' -f2)"
eq "origin fixer is origin" origin "$(autofix_lookup "$LIST" origin | cut -d'|' -f2)"
eq "tailscale-exit fixer is tailscale" tailscale "$(autofix_lookup "$LIST" tailscale-exit | cut -d'|' -f2)"
for id in brew app-install unwanted-app dock-apps login-shell docker-path-block hostname auto-brightness ac-sleep notifications url-handler \
          login-items tcc manual-step mouse-settings pointer-size input-british gh-auth 1password-cli mdm security software-update delete-files dotfiles-git \
          karabiner-rules repo-file launchagent-exit health tooling broken-symlink hammerspoon-config launchagent-template; do
  eq "$id needs Paul" PAUL "$(autofix_class "$LIST" "$id")"
done
unscriptable="$(grep -n -e "can't be scripted" -e "no reliable way to script" \
  "$DIR/lib/autofix.list" "$DIR/lib/desktop-bindings.list" || true)"
readme_claim="$(grep -n -e "no reliable way to script" -e "desktop assignments (macOS can't" \
  "$DIR/README.md" "$DIR"/docs/*.md || true)"
eq "list files don't call assignments unscriptable" "" "$unscriptable"
eq "docs don't call assignments unscriptable" "" "$readme_claim"

# ---- lookup semantics ----
eq "SAFE lookup returns class|fixer|why" "SAFE|symlink" "$(autofix_lookup "$LIST" symlink | cut -d'|' -f1-2)"
eq "unknown id is never automated" PAUL "$(autofix_class "$LIST" no-such-id)"
case "$(autofix_lookup "$LIST" no-such-id)" in *"not classified"*) r=0 ;; *) r=1 ;; esac
ok "unknown id explains it isn't classified" "$r"
tmp="$(mktemp)"
printf 'odd|SAFE||a SAFE row without a fixer\nhs|SAFE|hammerspoon|start it\n' > "$tmp"
eq "SAFE row without a fixer is treated as PAUL" PAUL "$(autofix_class "$tmp" odd)"
eq "SAFE row with a fixer stays SAFE" "SAFE|hammerspoon|start it" "$(autofix_lookup "$tmp" hs)"
eq "missing list file -> PAUL" PAUL "$(autofix_class "$tmp.missing" hs)"
rm -f "$tmp"

# ---- the list and macconfig-check.sh agree ----
used="$(grep -h -oE '(^|[;[:space:]])fixid [a-z0-9-]+' "$DIR/macconfig-check.sh" "$DIR"/checks/*.sh | awk '{print $NF}' | grep -vx unclassified | sort -u)"
listed="$(rows | cut -d'|' -f1 | sort -u)"
eq "every id macconfig-check.sh tags is in lib/autofix.list" "" "$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$listed"))"
eq "every id in lib/autofix.list is used by macconfig-check.sh" "" "$(comm -13 <(printf '%s\n' "$used") <(printf '%s\n' "$listed"))"
for fixer in $(rows | awk -F'|' '$2 == "SAFE" {print $3}' | sort -u); do
  grep -qE "^[[:space:]]+${fixer}\)" "$DIR/macconfig-check.sh"; ok "macconfig-check.sh run_fix handles fixer '$fixer'" "$?"
done
# macos-backed ids other than "defaults" are the @items macos.sh --only understands.
for id in $(rows | awk -F'|' '$2 == "SAFE" && $3 == "macos" && $1 != "defaults" {print $1}'); do
  grep -q "selected @$id" "$DIR/macos.sh"; ok "macos.sh --only knows @$id" "$?"
done

# Hammerspoon and desktop pins are one helper, shared by --fix and bootstrap.
helper="$(cat "$DIR/lib/safe-fixers.sh")"
has "helper starts Hammerspoon" "safe_start_hammerspoon" "$helper"
has "helper applies desktop pins" "safe_apply_desktops" "$helper"
has "helper opens Hammerspoon in the background" "open -g -a Hammerspoon" "$helper"
has "helper runs desktop-bindings.py --apply" 'desktop-bindings.py" --apply' "$helper"
has "macconfig-check.sh starts Hammerspoon through the helper" "safe_start_hammerspoon" "$(cat "$DIR/macconfig-check.sh")"
has "macconfig-check.sh applies desktops through the helper" "safe_apply_desktops" "$(cat "$DIR/macconfig-check.sh")"
has "install.sh starts Hammerspoon through the helper" "safe_start_hammerspoon" "$(cat "$DIR/install.sh")"
has "dock.sh applies desktops through the helper" "safe_apply_desktops" "$(cat "$DIR/dock.sh")"
miss "macconfig-check.sh does not open Hammerspoon itself" "open -g -a Hammerspoon" "$(cat "$DIR/macconfig-check.sh")"
miss "install.sh does not open Hammerspoon itself" "open -g -a Hammerspoon" "$(cat "$DIR/install.sh")"
miss "macconfig-check.sh does not call desktop-bindings.py --apply itself" 'desktop-bindings.py" --apply' "$(cat "$DIR/macconfig-check.sh")"
miss "dock.sh does not call desktop-bindings.py --apply itself" 'desktop-bindings.py" --apply' "$(cat "$DIR/dock.sh")"

has "helper installs origin" "safe_install_origin" "$helper"
has "helper uses the Cursor origin installer" "https://downloads.cursor.com/origin/install.sh" "$helper"
# shellcheck disable=SC2016  # the helper source is compared literally
has "helper pipes the installer to sh" 'curl -fsSL "$url" | sh' "$helper"
has "macconfig-check.sh installs origin through the helper" "safe_install_origin" "$(cat "$DIR/macconfig-check.sh")"
has "install.sh installs origin through the helper" "safe_install_origin" "$(cat "$DIR/install.sh")"
miss "macconfig-check.sh does not curl the origin installer" "downloads.cursor.com/origin/install.sh" "$(cat "$DIR/macconfig-check.sh")"
miss "install.sh does not curl the origin installer" "downloads.cursor.com/origin/install.sh" "$(cat "$DIR/install.sh")"

has "helper sets the Tailscale exit node" "safe_tailscale_exit" "$helper"
has "helper turns on Allow Local Network Access" "--exit-node-allow-lan-access=true" "$helper"
has "the Tailscale row names Allow Local Network Access" "Allow Local Network Access" \
  "$(awk -F'|' '$1=="tailscale-exit" { print $4; exit }' "$LIST")"
has "macconfig-check.sh sets Tailscale through the helper" "safe_tailscale_exit" "$(cat "$DIR/macconfig-check.sh")"
has "install.sh sets Tailscale through the helper" "safe_tailscale_exit" "$(cat "$DIR/install.sh")"
has "a Tailscale miss does not abort install.sh" 'safe_tailscale_exit || ts_rc=$?' "$(cat "$DIR/install.sh")"
miss "macconfig-check.sh does not invoke the Tailscale CLI" "exit-node" "$(cat "$DIR/macconfig-check.sh")"
miss "install.sh does not invoke the Tailscale CLI" "exit-node" "$(cat "$DIR/install.sh")"

printf 'autofix tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
