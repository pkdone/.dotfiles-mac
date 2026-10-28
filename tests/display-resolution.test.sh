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

eq "14-inch More Space prefix" "3024x1964|1800 x 1169" \
  "$(grep -E '^3024x1964\|' "$LIST")"
eq "16-inch More Space prefix" "3456x2234|2056 x 1329" \
  "$(grep -E '^3456x2234\|' "$LIST")"
eq "ARZOPA pin row" \
  "external|ARZOPA|s74646035|16 inch external screen|1920x1080|180|off|left" \
  "$(awk -F'|' '$1 == "external" { print; exit }' "$LIST")"
# The persistent id is recorded so a reader knows which panel was measured,
# and the list says it is not the match key.
has "persistent id is not the match key" "persistent screen id is not a match" "$(cat "$LIST")"
miss "the pin row does not key off the persistent id" \
  "82BDB23E-5EA1-4C6F-925B-EB392903EC5E|ARZOPA" "$(cat "$LIST")"
ABSENT='info|arzopa|ARZOPA not connected — resolution and position not checked'
both() { printf '%s\n%s' "$1" "$ABSENT"; }
eq "display-more-space is checked by macconfig-check.sh" "@macconfig:display" \
  "$(awk -F'|' '$1 == "display-more-space" { print $6; exit }' "$STEPS")"
eq "display-more-space is fixed by macos.sh" "SAFE|macos" \
  "$(awk -F'|' '$1 == "display-more-space" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"
writers="$(grep -nE 'subprocess|os\.system|Popen' "$HELPER" || true)"
eq "helper does not shell out" "" "$writers"

# 14-inch Color LCD: More Space is 1800 x 1169 on a 3024x1964 Retina panel.
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
  "$(both "ok||Built-in display is More Space (Color LCD '1800 x 1169 @ 120.00Hz'; _spdisplays_resolution starts with 1800 x 1169)")" \
  "$out"

cat > "$tmp/default.json" <<'EOF'
{
  "SPDisplaysDataType": [
    {
      "spdisplays_ndrvs": [
        {
          "_name": "Color LCD",
          "spdisplays_connection_type": "spdisplays_internal",
          "_spdisplays_resolution": "1512 x 982 @ 120.00Hz",
          "spdisplays_pixelresolution": "spdisplays_3024x1964Retina"
        }
      ]
    }
  ]
}
EOF
out="$(run "$tmp/default.json")"
eq "a different scaled mode warns" \
  "$(both "warn||Built-in display is not More Space (Color LCD: _spdisplays_resolution is '1512 x 982 @ 120.00Hz'; want _spdisplays_resolution to start with 1800 x 1169). macos.sh sets this with displayplacer when that mode is listed; otherwise System Settings → Displays")" \
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
  "$(both "info||no built-in display — More Space not checked (clamshell or external display only)")" \
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
          "_spdisplays_resolution": "1800 x 1169 @ 120.00Hz",
          "spdisplays_pixelresolution": "spdisplays_3024x1964Retina"
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
          "_spdisplays_resolution": "1800 x 1169",
          "spdisplays_pixelresolution": "spdisplays_3024x1964Retina"
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
    {"spdisplays_ndrvs": [{"_name": "Color LCD", "spdisplays_connection_type": "spdisplays_internal", "spdisplays_pixelresolution": "spdisplays_3024x1964Retina"}]}
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

printf '3024x1964|1800 x 1169\n3024x1964|1512 x 982\n' > "$tmp/two.list"
out="$(run "$tmp/more-space.json" "$tmp/two.list")"
has "a panel listed twice is an error" "3024x1964 listed twice" "$out"

printf 'builtin|1800 x 1169\n' > "$tmp/old.list"
out="$(run "$tmp/more-space.json" "$tmp/old.list")"
has "a row without a panel size is an error" "want <width>x<height>/<prefix>" "$out"

# 16-inch panel: More Space is 2056 x 1329 on 3456x2234.
cat > "$tmp/sixteen.json" <<'EOF'
{"SPDisplaysDataType": [{"spdisplays_ndrvs": [{"_name": "Color LCD", "spdisplays_connection_type": "spdisplays_internal", "_spdisplays_resolution": "2056 x 1329 @ 120.00Hz", "spdisplays_pixelresolution": "spdisplays_3456x2234Retina"}]}]}
EOF
out="$(run "$tmp/sixteen.json")"
eq "16-inch More Space passes" \
  "$(both "ok||Built-in display is More Space (Color LCD '2056 x 1329 @ 120.00Hz'; _spdisplays_resolution starts with 2056 x 1329)")" \
  "$out"
sed 's/2056 x 1329/1800 x 1169/' "$tmp/sixteen.json" > "$tmp/sixteen-14mode.json"
out="$(run "$tmp/sixteen-14mode.json")"
has "16-inch panel on the 14-inch value warns" "warn||" "$out"
has "16-inch warning names its own prefix" "start with 2056 x 1329" "$out"

# A panel size not in the list is info, not drift.
sed 's/3456x2234/2560x1664/' "$tmp/sixteen.json" > "$tmp/unknown.json"
out="$(run "$tmp/unknown.json")"
eq "unknown panel is info" \
  "$(both "info||built-in panel size not in lib/display-resolution.list (Color LCD 2560x1664; known: 3024x1964, 3456x2234) — More Space not checked")" \
  "$out"
cat > "$tmp/no-size.json" <<'EOF'
{"SPDisplaysDataType": [{"spdisplays_ndrvs": [{"_name": "Color LCD", "spdisplays_connection_type": "spdisplays_internal", "_spdisplays_resolution": "1800 x 1169"}]}]}
EOF
out="$(run "$tmp/no-size.json")"
has "panel size not reported is info" "info||built-in panel size not in lib/display-resolution.list (Color LCD size not reported" "$out"

# The prefix comes from the list, not a hard-coded pass inside the helper call.
printf '3024x1964|1512 x 982\n' > "$tmp/other.list"
out="$(run "$tmp/default.json" "$tmp/other.list")"
has "a different list prefix is what gets checked" "starts with 1512 x 982" "$out"

stdin_out="$("$PY" "$HELPER" --list "$LIST" < "$tmp/more-space.json")"
eq "stdin matches --json" "$(run "$tmp/more-space.json")" "$stdin_out"

# displayplacer plan: change only the built-in screen, keep the external mode.
cat > "$tmp/placer-14.txt" <<'EOF'
Persistent screen id: BUILTIN-ID
Contextual screen id: 1
Type: MacBook built in screen
Resolution: 1512x982
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0) - main display
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:1512x982 hz:120 color_depth:8 scaling:on <-- current mode
  mode 1: res:1800x1169 hz:60 color_depth:8 scaling:on
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on
  mode 3: res:1800x1169 hz:120 color_depth:4 scaling:on
  mode 4: res:1800x1169 hz:120 color_depth:8

Persistent screen id: EXTERNAL-ID
Contextual screen id: 2
Type: 27 inch external screen
Resolution: 2560x1440
Hertz: 60
Color Depth: 8
Scaling: off
Origin: (1800,0)
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:2560x1440 hz:60 color_depth:8 <-- current mode
  mode 1: res:1920x1080 hz:60 color_depth:8

Execute the command below to set your screens to the current arrangement:
displayplacer "id:BUILTIN-ID res:1512x982 hz:120 color_depth:8 scaling:on origin:(0,0) degree:0" "id:EXTERNAL-ID res:2560x1440 hz:60 color_depth:8 scaling:off origin:(1800,0) degree:0"
EOF
plan() { "$PY" "$HELPER" --json "$1" --list "${3:-$LIST}" --plan --placer "$2"; }
run_with_placer() { "$PY" "$HELPER" --json "$1" --list "${3:-$LIST}" --placer "$2"; }
out="$(plan "$tmp/default.json" "$tmp/placer-14.txt")"
eq "plan picks the 120Hz scaled More Space mode and leaves the external display" \
  "$(printf '%s\n' \
    'apply||built-in display More Space 1800x1169 at 120Hz, scaling on' \
    'screen|id:BUILTIN-ID mode:2 origin:(0,0) degree:0' \
    'screen|id:EXTERNAL-ID mode:0 origin:(1800,0) degree:0')" \
  "$out"
miss "plan does not put the More Space resolution on the external display" 'res:1800' "$out"

# Already More Space: the plan is a no-op even if displayplacer list shows another mode.
out="$(plan "$tmp/more-space.json" "$tmp/placer-14.txt")"
eq "plan does not change a display that is already More Space" \
  "$(both "ok||Built-in display is More Space (Color LCD '1800 x 1169 @ 120.00Hz'; _spdisplays_resolution starts with 1800 x 1169)")" \
  "$out"
miss "already More Space plan has no screen line" 'screen|' "$out"

out="$(plan "$tmp/clamshell.json" "$tmp/placer-14.txt")"
has "plan leaves a clamshell alone" "info||no built-in display" "$out"
miss "clamshell plan has no screen line" 'screen|' "$out"

cat > "$tmp/placer-no-mode.txt" <<'EOF'
Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1512x982
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:1512x982 hz:120 color_depth:8 scaling:on <-- current mode
  mode 4: res:1800x1169 hz:120 color_depth:8
EOF
out="$(plan "$tmp/default.json" "$tmp/placer-no-mode.txt")"
has "a scaled-off mode is not More Space" "no More Space mode 1800x1169" "$out"
miss "missing scaled mode has no screen line" 'screen|' "$out"
has "missing mode says other displays were not changed" "Other displays were not changed" "$out"

cat > "$tmp/placer-external-only.txt" <<'EOF'
Persistent screen id: EXTERNAL-ID
Type: 27 inch external screen
Resolution: 2560x1440
Hertz: 60
Color Depth: 8
Scaling: off
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:2560x1440 hz:60 color_depth:8 <-- current mode
EOF
out="$(plan "$tmp/default.json" "$tmp/placer-external-only.txt")"
has "no built-in screen in displayplacer list is a warning" "could not match the built-in display" "$out"
miss "external-only list has no screen line" 'screen|' "$out"

# Closest refresh rate when the current one is not listed. 144 is nearer 120 than 60.
cat > "$tmp/placer-nearest.txt" <<'EOF'
Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1512x982
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 1: res:1800x1169 hz:60 color_depth:8 scaling:on
  mode 5: res:1800x1169 hz:144 color_depth:8 scaling:on
EOF
out="$(plan "$tmp/default.json" "$tmp/placer-nearest.txt")"
has "nearest refresh rate is chosen" "screen|id:BUILTIN-ID mode:5 origin:(0,0) degree:0" "$out"
has "nearest refresh rate is named" "at 144Hz" "$out"

# 16-inch panel.
cat > "$tmp/placer-16.txt" <<'EOF'
Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1728x1117
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:1728x1117 hz:120 color_depth:8 scaling:on <-- current mode
  mode 8: res:2056x1329 hz:120 color_depth:8 scaling:on
EOF
out="$(plan "$tmp/sixteen-14mode.json" "$tmp/placer-16.txt")"
has "16-inch plan uses 2056x1329" "screen|id:BUILTIN-ID mode:8 origin:(0,0) degree:0" "$out"

# A 16 inch external screen is not the ARZOPA unless system_profiler names it
# or reports its serial. Type alone must not pin some other monitor.
cat > "$tmp/other-16.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1512 x 982 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"},
  {"_name":"DELL Portable","spdisplays_connection_type":"spdisplays_connection_type_usb_type_c","_spdisplays_resolution":"2560 x 1440 @ 60.00Hz","_spdisplays_display-serial-number":"999"}
]}]}
EOF
cat > "$tmp/placer-other-16.txt" <<'EOF'
Persistent screen id: 82BDB23E-5EA1-4C6F-925B-EB392903EC5E
Type: 16 inch external screen
Resolution: 2560x1440
Hertz: 60
Color Depth: 8
Scaling: off
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:2560x1440 hz:60 color_depth:8 <-- current mode
  mode 3: res:1920x1080 hz:180 color_depth:8

Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1512x982
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (1920,0)
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:1512x982 hz:120 color_depth:8 scaling:on <-- current mode
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on
EOF
out="$(plan "$tmp/other-16.json" "$tmp/placer-other-16.txt")"
has "a different 16 inch panel is not pinned by persistent id or type" \
  "screen|id:82BDB23E-5EA1-4C6F-925B-EB392903EC5E mode:0 origin:(0,0) degree:0" "$out"
miss "a different 16 inch panel is not moved to 1920x1080" "res:1920x1080" "$out"
has "that plan still sets More Space" "screen|id:BUILTIN-ID mode:2 origin:(1920,0) degree:0" "$out"

# Connected by name. Wrong mode, and the laptop is not at (0,0).
cat > "$tmp/arzopa.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1800 x 1169 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"},
  {"_name":"ARZOPA","spdisplays_connection_type":"spdisplays_connection_type_usb_type_c","_spdisplays_resolution":"2560 x 1440 @ 60.00Hz","_spdisplays_display-serial-number":"74646035"}
]}]}
EOF
cat > "$tmp/placer-arzopa-wrong.txt" <<'EOF'
Persistent screen id: OTHER-UUID
Serial screen id: s74646035
Type: 16 inch external screen
Resolution: 2560x1440
Hertz: 60
Color Depth: 8
Scaling: off
Origin: (1800,0)
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:2560x1440 hz:60 color_depth:8 <-- current mode
  mode 4: res:1920x1080 hz:60 color_depth:8
  mode 7: res:1920x1080 hz:180 color_depth:8 scaling:on
  mode 9: res:1920x1080 hz:180 color_depth:4
  mode 11: res:1920x1080 hz:180 color_depth:8

Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1800x1169
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0) - main display
Rotation: 0
Resolutions for rotation 0:
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on <-- current mode
EOF
out="$(run "$tmp/arzopa.json")"
has "a connected ARZOPA without displayplacer list is pending" "pending|arzopa|" "$out"
has "pending names the pinned mode" "1920x1080 at 180Hz (or the highest rate the connection offers), scaling off" "$out"
out="$(run_with_placer "$tmp/arzopa.json" "$tmp/placer-arzopa-wrong.txt")"
has "wrong ARZOPA mode warns" "warn|arzopa|" "$out"
has "warning wants the left-hand origin" "origin (-1920,0)" "$out"
miss "warning does not treat it as unplugged" "not connected" "$out"
out="$(plan "$tmp/arzopa.json" "$tmp/placer-arzopa-wrong.txt")"
has "plan sets 1920x1080 at 180Hz scaling off to the left" \
  "screen|id:OTHER-UUID res:1920x1080 hz:180 color_depth:8 enabled:true scaling:off origin:(-1920,0) degree:0" "$out"
has "plan keeps the laptop at (0,0) on its current mode" \
  "screen|id:BUILTIN-ID mode:2 origin:(0,0) degree:0" "$out"
has "plan names the ARZOPA change" "apply||ARZOPA 1920x1080 at 180Hz, scaling off, left of the laptop" "$out"
has "plan names the rate it set" "rate|arzopa|180" "$out"
miss "plan does not call the ARZOPA change More Space" "More Space" "$out"

# Serial matches even when the persistent id differs and the profiler name differs.
cat > "$tmp/arzopa-serial.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1800 x 1169 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"},
  {"_name":"Portable Monitor","_spdisplays_display-serial-number":"s74646035","_spdisplays_resolution":"1920 x 1080 @ 180.00Hz"}
]}]}
EOF
cat > "$tmp/placer-arzopa-ok.txt" <<'EOF'
Persistent screen id: NOT-THE-OLD-UUID
Serial screen id: s74646035
Screen name: ARZOPA
Type: 16 inch external screen
Resolution: 1920x1080
Hertz: 180
Color Depth: 8
Scaling: off
Origin: (-1920,0)
Rotation: 0
Resolutions for rotation 0:
  mode 11: res:1920x1080 hz:180 color_depth:8 <-- current mode

Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1800x1169
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0) - main display
Rotation: 0
Resolutions for rotation 0:
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on <-- current mode
EOF
out="$(plan "$tmp/arzopa-serial.json" "$tmp/placer-arzopa-ok.txt")"
eq "an already pinned ARZOPA is left alone" \
  "$(printf '%s\n' \
    "ok||Built-in display is More Space (Color LCD '1800 x 1169 @ 120.00Hz'; _spdisplays_resolution starts with 1800 x 1169)" \
    "ok|arzopa|ARZOPA is 1920x1080 at 180Hz, scaling off, at (-1920,0), to the left of the laptop. The laptop stays at (0,0), so the Dock and menu bar stay on it")" \
  "$out"

# Type matches when displayplacer has no name and no serial.
cat > "$tmp/placer-type-only.txt" <<'EOF'
Persistent screen id: TYPE-ONLY
Type: 16 inch external screen
Resolution: 1920x1080
Hertz: 180
Color Depth: 8
Scaling: off
Origin: (-1920,0)
Rotation: 0
Resolutions for rotation 0:
  mode 1: res:1920x1080 hz:180 color_depth:8 <-- current mode

Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1800x1169
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on <-- current mode
EOF
out="$(run_with_placer "$tmp/arzopa.json" "$tmp/placer-type-only.txt")"
has "type matches when name and serial are absent" "ok|arzopa|ARZOPA is 1920x1080" "$out"

# A named Dell of the same size class is not the ARZOPA, even at the old UUID.
cat > "$tmp/placer-named-other.txt" <<'EOF'
Persistent screen id: 82BDB23E-5EA1-4C6F-925B-EB392903EC5E
Screen name: DELL Portable
Serial screen id: s999
Type: 16 inch external screen
Resolution: 1920x1080
Hertz: 180
Color Depth: 8
Scaling: off
Origin: (-1920,0)
Rotation: 0
Resolutions for rotation 0:
  mode 1: res:1920x1080 hz:180 color_depth:8 <-- current mode

Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1800x1169
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on <-- current mode
EOF
out="$(run_with_placer "$tmp/arzopa.json" "$tmp/placer-named-other.txt")"
has "a different name and serial do not match" "no screen named ARZOPA" "$out"
miss "a different panel is not reported as pinned" "ok|arzopa|" "$out"

# A scaled 180Hz mode is not the pin. With only 60Hz listed unscaled, 60Hz
# is the highest this connection offers, so the plan uses it.
cat > "$tmp/placer-no-180.txt" <<'EOF'
Persistent screen id: OTHER-UUID
Serial screen id: s74646035
Type: 16 inch external screen
Resolution: 1920x1080
Hertz: 60
Color Depth: 8
Scaling: on
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 4: res:1920x1080 hz:60 color_depth:8
  mode 7: res:1920x1080 hz:180 color_depth:8 scaling:on

Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1800x1169
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on <-- current mode
EOF
out="$(plan "$tmp/arzopa.json" "$tmp/placer-no-180.txt")"
has "a scaled 180Hz mode is skipped for the unscaled 60Hz one" \
  "screen|id:OTHER-UUID res:1920x1080 hz:60 color_depth:8 enabled:true scaling:off origin:(-1920,0) degree:0" "$out"
miss "a scaled 180Hz mode is not set" "hz:180" "$out"

# No unscaled 1920x1080 mode at all: by hand, nothing is set.
cat > "$tmp/placer-no-unscaled.txt" <<'EOF'
Persistent screen id: OTHER-UUID
Serial screen id: s74646035
Type: 16 inch external screen
Resolution: 1920x1080
Hertz: 60
Color Depth: 8
Scaling: on
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 7: res:1920x1080 hz:180 color_depth:8 scaling:on
  mode 8: res:2560x1440 hz:60 color_depth:8

Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1800x1169
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0)
Rotation: 0
Resolutions for rotation 0:
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on <-- current mode
EOF
out="$(plan "$tmp/arzopa.json" "$tmp/placer-no-unscaled.txt")"
has "no unscaled 1920x1080 mode warns" \
  "warn|arzopa|ARZOPA: displayplacer has no mode 1920x1080 with scaling off at any refresh rate — set it by hand" "$out"
miss "no unscaled 1920x1080 mode does not set a screen" "screen|" "$out"

# Through the StarTech Thunderbolt 5 dock the ARZOPA lists 1920x1080 unscaled
# at 144, 120, 100 and 60Hz, and no 180Hz.
cur() { [ "$1" = "$2" ] && printf ' <-- current mode'; return 0; }
dock_placer() { # current Hertz
  cat <<EOF
Persistent screen id: DOCK-UUID
Serial screen id: s74646035
Type: 16 inch external screen
Resolution: 1920x1080
Hertz: $1
Color Depth: 8
Scaling: off
Origin: (-1920,0)
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:1920x1080 hz:144 color_depth:8$(cur "$1" 144)
  mode 1: res:1920x1080 hz:120 color_depth:8$(cur "$1" 120)
  mode 2: res:1920x1080 hz:100 color_depth:8$(cur "$1" 100)
  mode 3: res:1920x1080 hz:60 color_depth:8$(cur "$1" 60)
  mode 4: res:1920x1080 hz:144 color_depth:8 scaling:on

Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1800x1169
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0) - main display
Rotation: 0
Resolutions for rotation 0:
  mode 2: res:1800x1169 hz:120 color_depth:8 scaling:on <-- current mode
EOF
}
dock_placer 144 > "$tmp/placer-dock-144.txt"
dock_placer 100 > "$tmp/placer-dock-100.txt"
out="$(run_with_placer "$tmp/arzopa.json" "$tmp/placer-dock-144.txt")"
eq "dock at 144Hz passes as the highest the connection offers" \
  "ok|arzopa|ARZOPA is 1920x1080 at 144Hz, the highest this connection offers (180Hz needs a direct connection), scaling off, at (-1920,0), to the left of the laptop. The laptop stays at (0,0), so the Dock and menu bar stay on it" \
  "$(printf '%s\n' "$out" | grep '|arzopa|')"
out="$(plan "$tmp/arzopa.json" "$tmp/placer-dock-144.txt")"
miss "dock at 144Hz is left alone" "screen|" "$out"

out="$(run_with_placer "$tmp/arzopa.json" "$tmp/placer-dock-100.txt")"
has "dock at 100Hz is drift" "warn|arzopa|ARZOPA is not in its place (100Hz;" "$out"
has "dock drift wants the highest offered rate" \
  "want 1920x1080 at 144Hz, the highest this connection offers (180Hz needs a direct connection), scaling off" "$out"
out="$(plan "$tmp/arzopa.json" "$tmp/placer-dock-100.txt")"
has "dock drift plan sets 144Hz unscaled" \
  "screen|id:DOCK-UUID res:1920x1080 hz:144 color_depth:8 enabled:true scaling:off origin:(-1920,0) degree:0" "$out"
has "dock drift plan names 144Hz" "apply||ARZOPA 1920x1080 at 144Hz, scaling off, left of the laptop" "$out"
has "dock drift plan names the rate it set" "rate|arzopa|144" "$out"
has "dock drift plan keeps the laptop" "screen|id:BUILTIN-ID mode:2 origin:(0,0) degree:0" "$out"

# 144Hz did not take: --max-hz 143 asks for the next rate down.
out="$("$PY" "$HELPER" --json "$tmp/arzopa.json" --list "$LIST" --plan --placer "$tmp/placer-dock-100.txt" --max-hz 143)"
has "max-hz plan falls back to 120Hz" \
  "screen|id:DOCK-UUID res:1920x1080 hz:120 color_depth:8 enabled:true scaling:off origin:(-1920,0) degree:0" "$out"
has "max-hz plan names 120Hz" "rate|arzopa|120" "$out"
out="$("$PY" "$HELPER" --json "$tmp/arzopa.json" --list "$LIST" --placer "$tmp/placer-dock-100.txt" --max-hz 100)"
has "max-hz at the current rate passes" \
  "ok|arzopa|ARZOPA is 1920x1080 at 100Hz, the highest rate displayplacer could set" "$out"
out="$("$PY" "$HELPER" --json "$tmp/arzopa.json" --list "$LIST" --plan --placer "$tmp/placer-dock-100.txt" --max-hz 59)"
has "no settable rate left warns" \
  "ARZOPA: displayplacer could not set 1920x1080 with scaling off at any listed refresh rate (144, 120, 100, 60Hz)" "$out"
miss "no settable rate left sets nothing" "screen|" "$out"

# Plugged in directly, 180Hz is listed, so 144Hz is drift.
sed 's/mode 4: res:1920x1080 hz:144 color_depth:8 scaling:on/mode 5: res:1920x1080 hz:180 color_depth:8/' \
  "$tmp/placer-dock-144.txt" > "$tmp/placer-direct-144.txt"
out="$(run_with_placer "$tmp/arzopa.json" "$tmp/placer-direct-144.txt")"
has "a direct connection at 144Hz is drift" "warn|arzopa|ARZOPA is not in its place (144Hz;" "$out"
has "a direct connection wants 180Hz" "want 1920x1080 at 180Hz, scaling off" "$out"
out="$(plan "$tmp/arzopa.json" "$tmp/placer-direct-144.txt")"
has "a direct connection plan sets 180Hz" \
  "screen|id:DOCK-UUID res:1920x1080 hz:180 color_depth:8 enabled:true scaling:off origin:(-1920,0) degree:0" "$out"
# A faster mode than the pin is not chosen over 180Hz.
sed 's/mode 4: res:1920x1080 hz:144 color_depth:8 scaling:on/mode 5: res:1920x1080 hz:180 color_depth:8\
  mode 6: res:1920x1080 hz:240 color_depth:8/' \
  "$tmp/placer-dock-144.txt" > "$tmp/placer-direct-240.txt"
out="$(plan "$tmp/arzopa.json" "$tmp/placer-direct-240.txt")"
has "180Hz is preferred over a faster listed rate" "rate|arzopa|180" "$out"

# Real `displayplacer list` from Paul's Mac with the ARZOPA on the dock.
# Unscaled modes carry no scaling token, the mode in use ends with
# "<-- current mode", and the ARZOPA block has a serial but no name.
REAL="$DIR/tests/fixtures/displayplacer-dock.txt"
cat > "$tmp/arzopa-dock.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1800 x 1169 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"},
  {"_name":"ARZOPA","_spdisplays_display-serial-number":"74646035","_spdisplays_resolution":"1920 x 1080 @ 144.00Hz"}
]}]}
EOF
has "the real list has unscaled modes without a scaling token" \
  "mode 61: res:1920x1080 hz:144 color_depth:8 <-- current mode" "$(cat "$REAL")"
eq "the real ARZOPA list parses its unscaled 1920x1080 rates" "144 120 100 60" "$(
  "$PY" - "$HELPER" "$REAL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dr", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
screens = mod.parse_placer(open(sys.argv[2]).read())
arzopa = [s for s in screens if s["serial"] == "s74646035"][0]
print(" ".join(str(r) for r in mod._offered_rates(arzopa["modes"], "1920x1080", "off")))
PY
)"
eq "the real lists' current modes are the marked ones" "66 61" "$(
  "$PY" - "$HELPER" "$REAL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dr", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(" ".join(mod._current_mode(s)["n"] for s in mod.parse_placer(open(sys.argv[2]).read())))
PY
)"
out="$(run_with_placer "$tmp/arzopa-dock.json" "$REAL")"
eq "the real dock list passes at 144Hz, the highest offered" \
  "$(printf '%s\n' \
    "ok||Built-in display is More Space (Color LCD '1800 x 1169 @ 120.00Hz'; _spdisplays_resolution starts with 1800 x 1169)" \
    "ok|arzopa|ARZOPA is 1920x1080 at 144Hz, the highest this connection offers (180Hz needs a direct connection), scaling off, at (-1920,0), to the left of the laptop. The laptop stays at (0,0), so the Dock and menu bar stay on it")" \
  "$out"
out="$(plan "$tmp/arzopa-dock.json" "$REAL")"
miss "the real dock list needs no change" "screen|" "$out"
# The same list with the ARZOPA dropped to 100Hz: the plan sets 144Hz unscaled.
sed -e '151s/^Hertz: 144$/Hertz: 100/' \
  -e 's/^\(  mode 61: res:1920x1080 hz:144 color_depth:8\) <-- current mode$/\1/' \
  -e 's/^\(  mode 63: res:1920x1080 hz:100 color_depth:8\)$/\1 <-- current mode/' \
  "$REAL" > "$tmp/real-dock-100.txt"
eq "the drifted copy only changes the ARZOPA rate" "Hertz: 100" "$(sed -n 151p "$tmp/real-dock-100.txt")"
out="$(plan "$tmp/arzopa-dock.json" "$tmp/real-dock-100.txt")"
has "the real dock list at 100Hz is set to 144Hz unscaled" \
  "screen|id:82BDB23E-5EA1-4C6F-925B-EB392903EC5E res:1920x1080 hz:144 color_depth:8 enabled:true scaling:off origin:(-1920,0) degree:0" "$out"
has "the real dock list keeps the laptop on its marked mode" \
  "screen|id:37D8832A-2D66-02CA-B9F7-8F30A301B230 mode:66 origin:(0,0) degree:0" "$out"

# An explicit scaling:off token, as older displayplacer builds print it,
# still reads as unscaled.
sed 's/^\(  mode [0-9]*: res:[0-9x]* hz:[0-9]* color_depth:[0-9]*\)\( <-- current mode\)\{0,1\}$/\1 scaling:off\2/' \
  "$REAL" > "$tmp/real-dock-token.txt"
has "the token copy has explicit scaling:off" \
  "mode 61: res:1920x1080 hz:144 color_depth:8 scaling:off <-- current mode" "$(cat "$tmp/real-dock-token.txt")"
out="$(run_with_placer "$tmp/arzopa-dock.json" "$tmp/real-dock-token.txt")"
has "an explicit scaling:off still passes at 144Hz" "ok|arzopa|ARZOPA is 1920x1080 at 144Hz, the highest" "$out"

# Case-insensitive name, no serial on the profiler row.
cat > "$tmp/arzopa-case.json" <<'EOF'
{"SPDisplaysDataType":[{"spdisplays_ndrvs":[
  {"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1800 x 1169 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"},
  {"_name":"arzopa","spdisplays_connection_type":"spdisplays_connection_type_usb_type_c","_spdisplays_resolution":"1920 x 1080 @ 180.00Hz"}
]}]}
EOF
out="$(run "$tmp/arzopa-case.json")"
has "the name match ignores case" "pending|arzopa|ARZOPA is connected" "$out"

printf 'external|ARZOPA|s1|16 inch external screen|1920x1080|180|off|sideways\n3024x1964|1800 x 1169\n' > "$tmp/bad-place.list"
out="$(run "$tmp/more-space.json" "$tmp/bad-place.list")"
has "a bad place value is an error" "place should be left" "$out"

section="$(cat "$DIR/checks/display.sh")"
has "section calls the helper" 'lib/display-resolution.py' "$section"
has "section reads the list" 'lib/display-resolution.list' "$section"
has "section tags display-more-space" 'fixid display-more-space' "$section"
has "section tags the ARZOPA pin" 'fixid arzopa-display' "$section"
has "section reads displayplacer list" 'displayplacer list' "$section"
# shellcheck disable=SC2016
has "section warns on mismatch" 'warn "$disp_msg"' "$section"
# shellcheck disable=SC2016
has "section skips a clamshell instead of walking it" 'skip "$disp_msg"' "$section"
# shellcheck disable=SC2016  # the check source contains this literal
has "a skip still prints as an info line" 'skip() { note "$1"; }' "$(cat "$DIR/macconfig-check.sh")"
has "a note prints the info prefix" "printf '  info  %s\\n'" "$(cat "$DIR/macconfig-check.sh")"
miss "section does not run a displayplacer set" 'displayplacer "' "$section"

printf 'display-resolution tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
