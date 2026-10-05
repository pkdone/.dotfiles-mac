#!/usr/bin/env bash
#
# Unit tests for lib/autofix.list + lib/autofix-lib.sh — the safe / needs-Paul split used
# by `check.sh --fix`. Plain bash + awk + grep (runs on Linux CI; nothing macOS-specific
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

rows() { awk -F'|' '$1 !~ /^#/ && NF' "$LIST"; }

# ---- the list is well formed ----
bad_rows="$(rows | awk -F'|' '
  NF != 4                                   { print NR ": " $0 " (want 4 fields)"; next }
  $2 != "SAFE" && $2 != "PAUL"              { print NR ": " $0 " (class must be SAFE or PAUL)"; next }
  $2 == "SAFE" && $3 !~ /^(macos|launchagent|symlink|hammerspoon)$/ { print NR ": " $0 " (unknown fixer)"; next }
  $2 == "PAUL" && $3 != ""                  { print NR ": " $0 " (PAUL rows have no fixer)"; next }
  $4 == ""                                  { print NR ": " $0 " (missing description)"; next }
  $1 !~ /^[a-z0-9-]+$/                      { print NR ": " $0 " (id must be [a-z0-9-])" }')"
eq "every autofix.list row is well formed" "" "$bad_rows"
eq "ids are unique" "" "$(rows | cut -d'|' -f1 | sort | uniq -d)"

# ---- the classes Paul asked for ----
for id in defaults dictation-164 quicknote-190 finder-icon-view finder-recents coteditor launchagent symlink hammerspoon; do
  eq "$id is SAFE" SAFE "$(autofix_class "$LIST" "$id")"
done
for id in brew app-install unwanted-app dock-apps desktop-assign login-shell hostname url-handler \
          login-items tcc manual-step mdm security software-update delete-files dotfiles-git \
          karabiner-rules repo-file launchagent-exit health tooling; do
  eq "$id needs Paul" PAUL "$(autofix_class "$LIST" "$id")"
done

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

# ---- the list and check.sh agree ----
used="$(grep -oE '(^|[;[:space:]])fixid [a-z0-9-]+' "$DIR/check.sh" | awk '{print $NF}' | grep -vx unclassified | sort -u)"
listed="$(rows | cut -d'|' -f1 | sort -u)"
eq "every id check.sh tags is in lib/autofix.list" "" "$(comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$listed"))"
eq "every id in lib/autofix.list is used by check.sh" "" "$(comm -13 <(printf '%s\n' "$used") <(printf '%s\n' "$listed"))"
for fixer in $(rows | awk -F'|' '$2 == "SAFE" {print $3}' | sort -u); do
  grep -qE "^[[:space:]]+${fixer}\)" "$DIR/check.sh"; ok "check.sh run_fix handles fixer '$fixer'" "$?"
done
# macos-backed ids other than "defaults" are the @items macos.sh --only understands.
for id in $(rows | awk -F'|' '$2 == "SAFE" && $3 == "macos" && $1 != "defaults" {print $1}'); do
  grep -q "selected @$id" "$DIR/macos.sh"; ok "macos.sh --only knows @$id" "$?"
done

printf 'autofix tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
