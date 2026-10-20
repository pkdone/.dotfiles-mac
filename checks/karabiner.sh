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
