#!/usr/bin/env bash
#
# Unit tests for lib/display-resolution.py. Synthetic profiler JSON only —
# system_profiler is never run, and nothing writes a display mode.
# Run: ./tests/display-resolution.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/display-resolution.py"
LIST="$DIR/lib/display-resolution.list"
CHECK="$DIR/macconfig-check.sh"
STEPS="$DIR/lib/manual-steps.list"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "display-resolution tests: python3 not found, skipped"; exit 0; fi

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

eq "expected More Space prefix" "builtin|1800 x 1169" \
  "$(grep -E '^builtin\|' "$LIST")"
eq "display-more-space is checked by macconfig-check.sh" "@macconfig-check.sh" \
  "$(awk -F'|' '$1 == "display-more-space" { print $6; exit }' "$STEPS")"
eq "display-more-space is Needs Paul" "PAUL|" \
  "$(awk -F'|' '$1 == "display-more-space" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"
miss "helper does not call displayplacer" 'displayplacer' "$(cat "$HELPER")"
writers="$(grep -nE 'subprocess|os\.system|Popen' "$HELPER" || true)"
eq "helper does not shell out" "" "$writers"

# This Mac's Color LCD: More Space is 1800 x 1169 on a 3024x1964 Retina panel.
cat > "$tmp/more-space.json" <<'EOF'
{
  "SPDisplaysDataType": [
    {
      "sppci_model": "Apple M4",
      "spdisplays_ndrvs": [
        {
          "_name": "Color LCD",
          "spdisplays_connection_type": "spdisplays_internal",
          "_spdisplays_resolution": "1800 x 1169 @ 120.00Hz",
          "_spdisplays_pixels": "3600 x 2338",
          "spdisplays_pixelresolution": "spdisplays_3024x1964Retina"
        },
        {
          "_name": "DELL U2723QE",
          "spdisplays_connection_type": "spdisplays_connection_type_displayport",
          "_spdisplays_resolution": "2560 x 1440 @ 60.00Hz"
        }
      ]
    }
  ]
}
EOF
run() { "$PY" "$HELPER" --json "$1" --list "${2:-$LIST}"; }
out="$(run "$tmp/more-space.json")"; rc=$?
eq "matching panel exits 0" 0 "$rc"
eq "More Space passes and ignores the external display" \
  "ok||Built-in display is More Space (Color LCD '1800 x 1169 @ 120.00Hz'; _spdisplays_resolution starts with 1800 x 1169)" \
  "$out"

cat > "$tmp/default.json" <<'EOF'
{
  "SPDisplaysDataType": [
    {
      "spdisplays_ndrvs": [
        {
          "_name": "Color LCD",
          "spdisplays_connection_type": "spdisplays_internal",
          "_spdisplays_resolution": "1512 x 982 @ 120.00Hz"
        }
      ]
    }
  ]
}
EOF
out="$(run "$tmp/default.json")"
eq "a different scaled mode warns" \
  "warn||Built-in display is not More Space (Color LCD: _spdisplays_resolution is '1512 x 982 @ 120.00Hz'; want _spdisplays_resolution to start with 1800 x 1169) — System Settings → Displays. macconfig-check.sh --fix does not change this" \
  "$out"

cat > "$tmp/clamshell.json" <<'EOF'
{
  "SPDisplaysDataType": [
    {
      "spdisplays_ndrvs": [
        {
          "_name": "DELL U2723QE",
          "spdisplays_connection_type": "spdisplays_connection_type_displayport",
          "_spdisplays_resolution": "2560 x 1440 @ 60.00Hz"
        }
      ]
    }
  ]
}
EOF
out="$(run "$tmp/clamshell.json")"; rc=$?
eq "clamshell exits 0" 0 "$rc"
eq "no built-in display is info" \
  "info||no built-in display — More Space not checked (clamshell or external display only)" \
  "$out"

# An external panel named Color LCD is not the built-in display.
cat > "$tmp/named-external.json" <<'EOF'
{
  "SPDisplaysDataType": [
    {
      "spdisplays_ndrvs": [
        {
          "_name": "Color LCD",
          "spdisplays_connection_type": "spdisplays_connection_type_displayport",
          "_spdisplays_resolution": "1800 x 1169 @ 60.00Hz"
        }
      ]
    }
  ]
}
EOF
out="$(run "$tmp/named-external.json")"
has "external Color LCD is not the built-in panel" "info||no built-in display" "$out"

# Older dumps omit the connection type and name the panel Color LCD.
cat > "$tmp/name-only.json" <<'EOF'
{
  "SPDisplaysDataType": [
    {
      "spdisplays_ndrvs": [
        {
          "_name": "Color LCD",
          "_spdisplays_resolution": "1800 x 1169 @ 120.00Hz"
        }
      ]
    }
  ]
}
EOF
out="$(run "$tmp/name-only.json")"
has "Color LCD without a connection type is built-in" "ok||Built-in display is More Space" "$out"

cat > "$tmp/other-internal.json" <<'EOF'
{
  "SPDisplaysDataType": [
    {
      "spdisplays_ndrvs": [
        {
          "_name": "Built-in Liquid Retina XDR Display",
          "spdisplays_connection_type": "spdisplays_internal",
          "_spdisplays_resolution": "1800 x 1169"
        }
      ]
    }
  ]
}
EOF
out="$(run "$tmp/other-internal.json")"
has "any internal panel is checked" "Built-in Liquid Retina XDR Display '1800 x 1169'" "$out"

cat > "$tmp/no-res.json" <<'EOF'
{
  "SPDisplaysDataType": [
    {"spdisplays_ndrvs": [{"_name": "Color LCD", "spdisplays_connection_type": "spdisplays_internal"}]}
  ]
}
EOF
out="$(run "$tmp/no-res.json")"
has "missing resolution warns" "_spdisplays_resolution is missing" "$out"
has "missing resolution is a warning" "warn||" "$out"

cat > "$tmp/empty.json" <<'EOF'
{"SPDisplaysDataType": [{"spdisplays_ndrvs": []}]}
EOF
out="$(run "$tmp/empty.json")"
has "empty drive list is info" "info||no built-in display" "$out"

printf 'not json\n' > "$tmp/garbage.json"
out="$(run "$tmp/garbage.json")"; rc=$?
eq "garbage exits 0" 0 "$rc"
has "garbage is an error line" "error||could not read system_profiler JSON" "$out"

out="$(run "$tmp/more-space.json" "$tmp/no-such.list")"; rc=$?
eq "missing list exits 0" 0 "$rc"
has "missing list is an error line" "error||display resolution list missing" "$out"

printf 'builtin|1800 x 1169\nbuiltin|1512 x 982\n' > "$tmp/two.list"
out="$(run "$tmp/more-space.json" "$tmp/two.list")"
has "two prefixes are an error" "exactly one builtin prefix" "$out"

# The prefix comes from the list, not a hard-coded pass inside the helper call.
printf 'builtin|1512 x 982\n' > "$tmp/other.list"
out="$(run "$tmp/default.json" "$tmp/other.list")"
has "a different list prefix is what gets checked" "starts with 1512 x 982" "$out"

stdin_out="$("$PY" "$HELPER" --list "$LIST" < "$tmp/more-space.json")"
eq "stdin matches --json" "$(run "$tmp/more-space.json")" "$stdin_out"

section="$(awk '/^# ---- 6c\. Built-in display/,/^# ---- 7\. URL handlers/' "$CHECK")"
has "section calls the helper" 'lib/display-resolution.py' "$section"
has "section reads the list" 'lib/display-resolution.list' "$section"
has "section tags display-more-space" 'fixid display-more-space' "$section"
# shellcheck disable=SC2016
has "section warns on mismatch" 'warn "$disp_msg"' "$section"
# shellcheck disable=SC2016
has "section skips a clamshell with info" 'info "$disp_msg"' "$section"
miss "section does not call displayplacer" 'displayplacer' "$section"

printf 'display-resolution tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
