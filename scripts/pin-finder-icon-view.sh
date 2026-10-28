#!/usr/bin/env bash
# Pin Finder icon-view defaults: iconSize=72, textSize=13, arrangeBy=name
# (View Options → Sort By Name) on StandardViewSettings and
# FK_StandardViewSettings, and arrangeBy=name on DesktopViewSettings.
# The Desktop's icon size and text size are left as they are.
# A folder that saved its own view in .DS_Store is not changed
# (scripts/reset-folder-views.sh clears those on request).
set -euo pipefail

ICON_SIZE=72
TEXT_SIZE=13
ARRANGE_BY=name
LABEL="Finder icon view defaults"
LOG="${HOME}/Library/Logs/com.pdone.pin-finder-icon-view.log"
KEYS=(StandardViewSettings FK_StandardViewSettings)
DESKTOP_KEY=DesktopViewSettings

read_sizes() {
  /usr/bin/python3 - "$1" <<'PY'
import plistlib, subprocess, sys
key = sys.argv[1]
pl = plistlib.loads(subprocess.check_output(["defaults", "export", "com.apple.finder", "-"]))
block = pl.get(key) or {}
iv = block.get("IconViewSettings") if isinstance(block, dict) else {}
if not isinstance(iv, dict):
    iv = {}
icon = iv.get("iconSize")
text = iv.get("textSize")
arrange = iv.get("arrangeBy")
def norm(x):
    if x is None: return ""
    try: return str(int(float(x)))
    except Exception: return str(x)
if arrange is None:
    arrange_s = ""
else:
    arrange_s = str(arrange).replace("|", "/")
print(f"{norm(icon)}|{norm(text)}|{arrange_s}")
PY
}

# cur is icon|text|arrangeBy
split_cur() {
  local cur="$1"
  icon="${cur%%|*}"
  cur="${cur#*|}"
  text="${cur%%|*}"
  arrange="${cur#*|}"
}

all_ok() {
  local key cur icon text arrange
  for key in "${KEYS[@]}"; do
    cur="$(read_sizes "$key")"
    split_cur "$cur"
    [ "$icon" = "$ICON_SIZE" ] && [ "$text" = "$TEXT_SIZE" ] && [ "$arrange" = "$ARRANGE_BY" ] || return 1
  done
  cur="$(read_sizes "$DESKTOP_KEY")"
  split_cur "$cur"
  [ "$arrange" = "$ARRANGE_BY" ]
}

# One line per key, " Key=72x13 arrangeBy=name"; the Desktop names only its sort.
describe() {
  local key cur icon text arrange out=""
  for key in "${KEYS[@]}"; do
    cur="$(read_sizes "$key")"
    split_cur "$cur"
    out+=" $key=${icon}x${text} arrangeBy=${arrange:-unset}"
  done
  cur="$(read_sizes "$DESKTOP_KEY")"
  split_cur "$cur"
  out+=" $DESKTOP_KEY arrangeBy=${arrange:-unset}"
  printf '%s' "$out"
}

apply() {
  /usr/bin/python3 - "$ICON_SIZE" "$TEXT_SIZE" "$ARRANGE_BY" <<'PY'
import plistlib, subprocess, sys
icon_size = float(sys.argv[1])
text_size = float(sys.argv[2])
arrange_by = sys.argv[3]
raw = subprocess.check_output(["defaults", "export", "com.apple.finder", "-"])
pl = plistlib.loads(raw)

def icon_view(key):
    block = pl.setdefault(key, {})
    if not isinstance(block, dict):
        block = {}
        pl[key] = block
    iv = block.setdefault("IconViewSettings", {})
    if not isinstance(iv, dict):
        iv = {}
        block["IconViewSettings"] = iv
    return iv

for key in ["StandardViewSettings", "FK_StandardViewSettings"]:
    iv = icon_view(key)
    iv["iconSize"] = icon_size
    iv["textSize"] = text_size
    iv["arrangeBy"] = arrange_by
icon_view("DesktopViewSettings")["arrangeBy"] = arrange_by
out = plistlib.dumps(pl, fmt=plistlib.FMT_BINARY)
subprocess.run(["defaults", "import", "com.apple.finder", "-"], input=out, check=True)
PY
  killall Finder 2>/dev/null || true
}

log() {
  mkdir -p "$(dirname "$LOG")"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"
}

case "${1:-}" in
  -h|--help)
    cat <<'USAGE'
Usage: pin-finder-icon-view.sh [--check]

  (default)  Set iconSize=72 textSize=13 arrangeBy=name on Standard + FK_Standard,
             and arrangeBy=name on the Desktop. The Desktop's icon size and text
             size are not written.
  --check    Exit 0 if all three match; exit 1 and print current values otherwise.
USAGE
    exit 0
    ;;
  --check)
    if all_ok; then
      echo "$LABEL ok (iconSize=$ICON_SIZE textSize=$TEXT_SIZE arrangeBy=$ARRANGE_BY, Desktop arrangeBy=$ARRANGE_BY)"
      exit 0
    fi
    echo "$LABEL drift:$(describe)"
    exit 1
    ;;
esac

before="$(describe)"
apply
if all_ok; then
  msg="$LABEL pinned (was$before)"
else
  msg="$LABEL write may not have stuck (was$before)"
fi
log "$msg"
echo "$msg"
