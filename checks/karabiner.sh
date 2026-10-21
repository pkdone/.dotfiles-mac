# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 10. Karabiner Fn-kill and menu bar icon ----------------------------
# Config is symlinked via links.list (section 1). Here we also verify the
# managed rule is still present in that JSON (UI edits can strip it), and that
# the menu bar icon stays hidden (global show_in_menu_bar and
# show_profile_name_in_menu_bar are false). Read-only: python3 json, never a write.
# The DriverKit extension and Accessibility grants are manual steps, checked in
# the "Manual steps" section (scripts/manual-steps.sh ids karabiner-driver / karabiner-ax).
hdr "Karabiner Fn-kill"
fixid karabiner-rules
CHECKED=$((CHECKED + 1))
kj="$HOME/.config/karabiner/karabiner.json"
if [ ! -r "$kj" ]; then
  bad "$HOME/.config/karabiner/karabiner.json missing/unreadable"
else
  if rg -q 'Never start Dictation/Siri from Fn/Globe' "$kj" \
    && rg -q 'pdone_fn' "$kj" \
    && rg -q '"set_variable"' "$kj" \
    && rg -q '"consumer_key_code": "dictation"' "$kj" \
    && rg -q '"key_code": "f"' "$kj" \
    && rg -q '"key_code": "f11"' "$kj" \
    && rg -q 'left_command' "$kj"; then
    pass "karabiner.json has Fn-kill rule (variable layer; Fn+F fullscreen; Fn+F11 Show Desktop)"
  else
    bad "karabiner.json missing expected Fn-kill rule (restore from repo karabiner/karabiner.json)"
  fi
  CHECKED=$((CHECKED + 1))
  if rg -q 'Finder: Forward Delete' "$kj" \
    && rg -q 'delete_forward' "$kj" \
    && rg -q 'frontmost_application_if' "$kj" \
    && rg -q 'com\\\\.apple\\\\.finder' "$kj"; then
    pass "karabiner.json has Finder Forward Delete → Trash rule"
  else
    bad "karabiner.json missing Finder Forward Delete → Trash rule"
  fi
  CHECKED=$((CHECKED + 1))
  if [ -z "$DOT_PYTHON" ]; then
    fixid tooling
    warn "python3 not found — can't check Karabiner menu bar icon"
  else
    kb_menu="$("$DOT_PYTHON" - "$kj" <<'PY' 2>/dev/null
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("unreadable")
    raise SystemExit(0)
g = data.get("global") if isinstance(data, dict) else None
if not isinstance(g, dict):
    print("missing-global")
    raise SystemExit(0)
keys = ("show_in_menu_bar", "show_profile_name_in_menu_bar")
parts = []
ok = True
for name in keys:
    if name not in g:
        parts.append(name + "=missing")
        ok = False
    elif g[name] is False:
        parts.append(name + "=false")
    elif g[name] is True:
        parts.append(name + "=true")
        ok = False
    else:
        parts.append(name + "=other")
        ok = False
print("ok" if ok else " ".join(parts))
PY
)" || kb_menu="unreadable"
    fixid karabiner-rules
    if [ "$kb_menu" = ok ]; then
      pass "karabiner.json hides the menu bar icon (show_in_menu_bar and show_profile_name_in_menu_bar are false)"
    else
      bad "karabiner.json menu bar icon not hidden (${kb_menu:-unreadable}; expected global show_in_menu_bar false and show_profile_name_in_menu_bar false)"
    fi
  fi
fi

# ---- Karabiner background items (check only) ----------------------------
# Karabiner-Core-Service and Karabiner-VirtualHIDDevice-Daemon must be enabled
# and allowed. Karabiner-Elements Privileged Daemons v2 may stay disabled.
# The helper reads Background Task Management (the same records `sfltool
# dumpbtm` prints) and does not change them. If those records cannot be read
# it tries sfltool with a short timeout. If that does not finish, this is info.
# Manual step karabiner-login-items points here. --fix does not change this.
hdr "Karabiner background"
fixid karabiner-background
kb_bg="$DOTDIR/lib/btm-login-items.py"
if [ ! -r "$kb_bg" ]; then
  CHECKED=$((CHECKED + 1))
  fixid repo-file
  warn "lib/btm-login-items.py missing — can't check Karabiner background items"
elif [ -z "$DOT_PYTHON" ]; then
  info "no python3 — Karabiner background items stay by hand"
else
  kb_bg_out="$(with_timeout 20 "$DOT_PYTHON" "$kb_bg" --karabiner </dev/null 2>/dev/null || true)"
  kb_bg_n=0
  while IFS='|' read -r kb_st kb_name kb_msg; do
    [ -n "$kb_st" ] || continue
    case "$kb_st" in
      ok)
        CHECKED=$((CHECKED + 1))
        kb_bg_n=$((kb_bg_n + 1))
        pass "$kb_msg"
        ;;
      warn)
        CHECKED=$((CHECKED + 1))
        kb_bg_n=$((kb_bg_n + 1))
        fixid karabiner-background
        warn "$kb_msg"
        ;;
      info) info "$kb_msg" ;;
      *)
        CHECKED=$((CHECKED + 1))
        fixid tooling
        warn "${kb_msg:-$kb_st}"
        ;;
    esac
  done <<KB_BG
$kb_bg_out
KB_BG
  if [ "$kb_bg_n" -eq 0 ] && ! printf '%s\n' "$kb_bg_out" | grep -q '^info|'; then
    info "Karabiner background items could not be read, so Allow in the Background stays by hand"
  fi
fi
