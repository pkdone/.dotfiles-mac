# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 13d. Modes (Hammerspoon menu-bar switcher) ----------------------------
# hammerspoon/modes.lua must be valid (the same validator the switcher uses: a Lua
# interpreter if there is one, else the running Hammerspoon via `hs`; `luac -p` only
# checks syntax). The Focus Shortcuts and Focus modes it names should exist (report
# only: a mode still runs without them). A non-Normal mode left on for more than
# HEALTH_MODE_MAX_HOURS is a warning. Apps a mode quit or hid on purpose are listed as
# info, never drift. Read-only: never switches a mode or touches state.json.
hdr "Modes (Hammerspoon)"
HEALTH_MODE_MAX_HOURS="${HEALTH_MODE_MAX_HOURS:-4}"
MODES_CFG="$DOTDIR/hammerspoon/modes.lua"
MODES_ENGINE="$DOTDIR/hammerspoon/mode_switcher.lua"
MODES_STATE="$HOME/Library/Application Support/pdone-modes/state.json"
CHECKED=$((CHECKED + 1))
fixid modes-config
modes_lua=""
for c in lua5.4 lua54 lua; do
  if command -v "$c" >/dev/null 2>&1; then modes_lua="$c"; break; fi
done
modes_val=""
if [ ! -r "$MODES_CFG" ] || [ ! -r "$MODES_ENGINE" ]; then
  fixid repo-file; bad "hammerspoon/modes.lua or mode_switcher.lua missing — restore it from git"
else
  if [ -n "$modes_lua" ]; then
    modes_val="$(with_timeout 10 "$modes_lua" -e "local ms = dofile(arg[1]); io.write(ms.validateFile(arg[2]))" "$MODES_ENGINE" "$MODES_CFG" </dev/null 2>&1 || true)"
    modes_how="$modes_lua"
  elif command -v hs >/dev/null 2>&1 && pgrep -xq Hammerspoon; then
    # hs reads stdin unless it's /dev/null; dofile (not require) = the repo file as it is now
    modes_val="$(with_timeout 15 hs -q -t 10 -c "return dofile('$MODES_ENGINE').validateFile('$MODES_CFG')" </dev/null 2>&1 | grep -v '^-- Loading' || true)"
    modes_how="Hammerspoon (hs)"
  elif command -v luac >/dev/null 2>&1; then
    if modes_err="$(luac -p "$MODES_CFG" 2>&1)"; then modes_val="ok"; else modes_val="error: $modes_err"; fi
    modes_how="luac -p (syntax only)"
  fi
  case "$modes_val" in
    ok)       pass "hammerspoon/modes.lua is valid ($modes_how)" ;;
    error:*)  bad "hammerspoon/modes.lua: ${modes_val#error: } — fix it, then reload Hammerspoon" ;;
    "")       fixid tooling; warn "can't validate hammerspoon/modes.lua (no lua / luac, and Hammerspoon isn't running)" ;;
    *)        fixid tooling; warn "hammerspoon/modes.lua: unexpected validator output: $(printf '%s' "$modes_val" | head -c 200)" ;;
  esac

  # Shortcuts named in modes.lua (Focus on/off only)
  fixid modes-setup
  CHECKED=$((CHECKED + 1))
  modes_need="$(grep -oE "(on|off)[[:space:]]*=[[:space:]]*'[^']+'" "$MODES_CFG" | sed -E "s/^[a-z]+[[:space:]]*=[[:space:]]*'//; s/'\$//" | sort -u)"
  if ! command -v shortcuts >/dev/null 2>&1; then
    fixid tooling; warn "shortcuts CLI not found — can't check the Focus Shortcuts"
  elif ! modes_have="$(with_timeout 15 shortcuts list </dev/null 2>/dev/null)"; then
    fixid tooling; warn "shortcuts list failed — can't check the Focus Shortcuts"
  else
    modes_missing=""
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      if ! printf '%s\n' "$modes_have" | grep -Fxq "$s"; then modes_missing="$modes_missing '$s',"; fi
    done <<< "$modes_need"
    if [ -n "$modes_missing" ]; then
      warn "Shortcuts missing:${modes_missing%,} — create them (manual step mode-focus-shortcuts); modes still run, without the Focus"
    else
      pass "Focus Shortcuts exist ($(printf '%s\n' "$modes_need" | grep -c .))"
    fi
  fi

  # Focus modes named in modes.lua (focus = '<name>'), from the Focus database
  CHECKED=$((CHECKED + 1))
  modes_focus="$(grep -oE "^[[:space:]]+focus[[:space:]]*=[[:space:]]*'[^']+'" "$MODES_CFG" | sed -E "s/.*'([^']+)'/\1/" | sort -u)"
  modes_fdb="$HOME/Library/DoNotDisturb/DB/ModeConfigurations.json"
  if [ -z "$DOT_PYTHON" ]; then
    fixid tooling; warn "python3 missing — can't check the Focus modes"
  elif ! modes_fnames="$("$DOT_PYTHON" - "$modes_fdb" <<'PY' 2>/dev/null
import json, sys
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "name" and isinstance(v, str):
                print(v)
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
walk(json.load(open(sys.argv[1])))
PY
)"; then
    note "Focus modes not readable (needs Full Disk Access) — check System Settings → Focus for:$(printf '%s\n' "$modes_focus" | tr '\n' ' ' | sed 's/ $//; s/^/ /')"
  else
    modes_fmiss=""
    for f in $modes_focus; do
      if ! printf '%s\n' "$modes_fnames" | grep -Fxq "$f"; then modes_fmiss="$modes_fmiss $f"; fi
    done
    if [ -n "$modes_fmiss" ]; then
      warn "Focus modes missing:$modes_fmiss — System Settings → Focus → Add Focus… (manual step mode-focus-modes)"
    else
      pass "Focus modes exist:$(printf '%s\n' "$modes_focus" | tr '\n' ' ' | sed 's/ $//; s/^/ /')"
    fi
  fi
fi

# Current mode (state.json is written by the switcher; absent = Normal)
CHECKED=$((CHECKED + 1))
fixid mode-long
if [ ! -f "$MODES_STATE" ]; then
  pass "mode: Normal (no state.json yet)"
elif [ -z "$DOT_PYTHON" ]; then
  fixid tooling; warn "python3 missing — can't read the mode state"
else
  modes_st="$("$DOT_PYTHON" - "$MODES_STATE" <<'PY' 2>/dev/null
import json, sys, time
s = json.load(open(sys.argv[1]))
ch = s.get("changes") or {}
if not isinstance(ch, dict):
    ch = {}
def names(key):
    return ", ".join((x.get("name") or x.get("bundle") or "?").replace("\u200e", "") for x in ch.get(key) or [] if isinstance(x, dict))
hours = (time.time() - float(s.get("since") or time.time())) / 3600
print("\t".join([str(s.get("mode") or "?"), "%.1f" % hours, str(s.get("phase") or ""), names("quit"), names("hidden")]))
PY
)" || modes_st=""
  if [ -z "$modes_st" ]; then
    fixid modes-config; warn "state.json unreadable ($MODES_STATE) — switch to Normal from the menu bar to rewrite it"
  else
    IFS=$'\t' read -r st_mode st_hours st_phase st_quit st_hidden <<< "$modes_st"
    if [ "$st_mode" = "Normal" ]; then
      pass "mode: Normal"
    else
      if [ -n "$st_quit" ]; then note "quit by $st_mode on purpose (not drift; Normal reopens them): $st_quit"; fi
      if [ -n "$st_hidden" ]; then note "hidden by $st_mode on purpose (not drift; Normal unhides them): $st_hidden"; fi
      if awk -v h="$st_hours" -v max="$HEALTH_MODE_MAX_HOURS" 'BEGIN { exit !(h > max) }'; then
        warn "mode $st_mode has been on for ${st_hours}h (> ${HEALTH_MODE_MAX_HOURS}h) — switch back to Normal from the menu bar if you're done"
      else
        pass "mode: $st_mode for ${st_hours}h${st_phase:+ ($st_phase)}"
      fi
    fi
  fi
fi
