#!/usr/bin/env bash
# Pin Finder icon-view defaults: iconSize=72, textSize=13.
# Writes StandardViewSettings + FK_StandardViewSettings (folder defaults).
# Desktop icons are left alone (separate surface).
set -euo pipefail

ICON_SIZE=72
TEXT_SIZE=13
LABEL="Finder icon view defaults"
LOG="${HOME}/Library/Logs/com.pdone.pin-finder-icon-view.log"
KEYS=(StandardViewSettings FK_StandardViewSettings)

read_sizes() {
  /usr/bin/python3 - "$1" <<'PY'
import plistlib, subprocess, sys
key = sys.argv[1]
pl = plistlib.loads(subprocess.check_output(["defaults", "export", "com.apple.finder", "-"]))
iv = (pl.get(key) or {}).get("IconViewSettings") or {}
icon = iv.get("iconSize")
text = iv.get("textSize")
def norm(x):
    if x is None: return ""
    try: return str(int(float(x)))
    except Exception: return str(x)
print(f"{norm(icon)}|{norm(text)}")
PY
}

all_ok() {
  local key cur icon text
  for key in "${KEYS[@]}"; do
    cur="$(read_sizes "$key")"
    icon="${cur%%|*}"
    text="${cur##*|}"
    [ "$icon" = "$ICON_SIZE" ] && [ "$text" = "$TEXT_SIZE" ] || return 1
  done
  return 0
}

apply() {
  /usr/bin/python3 - "$ICON_SIZE" "$TEXT_SIZE" <<'PY'
import plistlib, subprocess, sys
icon_size = float(sys.argv[1])
text_size = float(sys.argv[2])
keys = ["StandardViewSettings", "FK_StandardViewSettings"]
raw = subprocess.check_output(["defaults", "export", "com.apple.finder", "-"])
pl = plistlib.loads(raw)
for key in keys:
    block = pl.setdefault(key, {})
    if not isinstance(block, dict):
        block = {}
        pl[key] = block
    iv = block.setdefault("IconViewSettings", {})
    if not isinstance(iv, dict):
        iv = {}
        block["IconViewSettings"] = iv
    iv["iconSize"] = icon_size
    iv["textSize"] = text_size
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

  (default)  Set iconSize=72 textSize=13 on Standard + FK_Standard view settings.
  --check    Exit 0 if both match; exit 1 and print current values otherwise.
USAGE
    exit 0
    ;;
  --check)
    if all_ok; then
      echo "$LABEL ok (iconSize=$ICON_SIZE textSize=$TEXT_SIZE)"
      exit 0
    fi
    echo -n "$LABEL drift:"
    for key in "${KEYS[@]}"; do
      cur="$(read_sizes "$key")"
      echo -n " $key=${cur%%|*}x${cur##*|}"
    done
    echo
    exit 1
    ;;
esac

before=""
for key in "${KEYS[@]}"; do
  cur="$(read_sizes "$key")"
  before+=" $key=${cur%%|*}x${cur##*|}"
done
apply
if all_ok; then
  msg="$LABEL pinned (was$before)"
else
  msg="$LABEL write may not have stuck (was$before)"
fi
log "$msg"
echo "$msg"
