# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# Repo LaunchAgents are regular files rendered by scripts/install-launchagent.sh
# (@HOME@ -> $HOME). launchd does not expand ~ or $HOME, so a symlink to the
# repo plist would watch the literal placeholder. Drift when the installed
# bytes differ or the job isn't loaded.
check_repo_launchagent() {  # label  loaded-ok-text
  local label="$1" loaded_ok="$2" plist la_msg
  case " ${LAUNCHAGENT_CHECKED:-} " in
    *" $label "*) ;;
    *) LAUNCHAGENT_CHECKED="${LAUNCHAGENT_CHECKED:-} $label" ;;
  esac
  plist="$HOME/Library/LaunchAgents/${label}.plist"
  CHECKED=$((CHECKED + 1))
  fixid launchagent "$label|$plist"
  if [ ! -x "$DOTDIR/scripts/install-launchagent.sh" ]; then
    fixid repo-file
    bad "scripts/install-launchagent.sh missing"
  elif la_msg="$("$DOTDIR/scripts/install-launchagent.sh" --check "$label")"; then
    pass "LaunchAgent $label plist matches repo ($la_msg)"
  else
    bad "LaunchAgent $label ${la_msg:-plist check failed}"
  fi
  CHECKED=$((CHECKED + 1))
  fixid launchagent "$label|$plist"
  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    pass "LaunchAgent $label loaded ($loaded_ok)"
  else
    bad "LaunchAgent $label not loaded — re-run install.sh or macconfig-check.sh --fix"
  fi
}

# Warn-only sweep: every repo com.pdone.* template, and no stale installed
# plist. Labels already reported by check_repo_launchagent are not repeated.
# This does not rewrite plists and does not call launchctl.
check_pdone_launchagents() {
  local sweep_bad=0 label src dest msg repo_labels=" " script detail
  local repos=() installed=()
  script="$DOTDIR/scripts/install-launchagent.sh"
  fixid launchagent-template
  if [ ! -x "$script" ]; then
    CHECKED=$((CHECKED + 1))
    fixid repo-file
    warn "scripts/install-launchagent.sh missing — cannot compare com.pdone.* LaunchAgents"
    return 0
  fi
  shopt -s nullglob
  repos=("$DOTDIR"/launchagents/com.pdone.*.plist)
  installed=("$HOME"/Library/LaunchAgents/com.pdone.*.plist)
  shopt -u nullglob
  for src in ${repos[@]+"${repos[@]}"}; do
    label="$(basename "$src" .plist)"
    repo_labels="$repo_labels$label "
    if msg="$("$script" --check "$label" 2>&1)"; then
      continue
    fi
    sweep_bad=1
    case " ${LAUNCHAGENT_CHECKED:-} " in
      *" $label "*) continue ;;
    esac
    case "$msg" in
      *symlink*) detail="installed file is a symlink" ;;
      *missing*) detail="installed file is missing" ;;
      *) detail="installed file differs from the rendered template" ;;
    esac
    CHECKED=$((CHECKED + 1))
    fixid launchagent-template
    warn "LaunchAgent $label ${detail} once @HOME@ is expanded. This check does not rewrite it"
  done
  for dest in ${installed[@]+"${installed[@]}"}; do
    label="$(basename "$dest" .plist)"
    case "$repo_labels" in
      *" $label "*) continue ;;
    esac
    sweep_bad=1
    CHECKED=$((CHECKED + 1))
    fixid launchagent-template
    warn "LaunchAgent $label is stale or unknown (no launchagents/${label}.plist in the repo)"
  done
  if [ "$sweep_bad" = 0 ]; then
    CHECKED=$((CHECKED + 1))
    pass "com.pdone.* LaunchAgents match their repo templates (@HOME@ expanded); none stale or unknown"
  fi
  return 0
}

# One AppleSymbolicHotKeys entry, parsed the same way as hotkeys 164 and 190:
# the "KEY = { ... };" block, then enabled, type, and the three parameter lines.
# Sets hk_enabled, hk_type, hk_p1, hk_p2, hk_p3 (empty when the key is absent).
read_symbolic_hotkey() { # key  plist-text
  local key="$1" text="$2" blk
  blk="$(printf '%s\n' "$text" | awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key " =" { grab = 1 }
    grab { print }
    grab && $0 ~ /^[[:space:]]*};[[:space:]]*$/ { exit }
  ')"
  hk_enabled="$(printf '%s\n' "$blk" | awk '/enabled/ { print $3; exit }' | tr -d ';')"
  hk_type="$(printf '%s\n' "$blk" | awk '/type/ { print $3; exit }' | tr -d '";')"
  hk_p1="$(printf '%s\n' "$blk" | awk '/parameters/ { getline; print $1; exit }' | tr -d ',')"
  hk_p2="$(printf '%s\n' "$blk" | awk '/parameters/ { getline; getline; print $1; exit }' | tr -d ',')"
  hk_p3="$(printf '%s\n' "$blk" | awk '/parameters/ { getline; getline; getline; print $1; exit }' | tr -d ',')"
}

# Command+Space: enabled, type=standard, parameters (32, 49, 1048576).
spotlight_64_ok() {
  [ "${hk_enabled:-}" = 1 ] && [ "${hk_type:-}" = standard ] \
    && [ "${hk_p1:-}" = 32 ] && [ "${hk_p2:-}" = 49 ] && [ "${hk_p3:-}" = 1048576 ]
}

check_spotlight_hotkey() {
  local hk
  fixid spotlight-64
  CHECKED=$((CHECKED + 1))
  hk="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null || true)"
  if [ -z "$hk" ]; then
    bad "symbolichotkeys not readable"
  else
    read_symbolic_hotkey 64 "$hk"
    if spotlight_64_ok; then
      pass "Command+Space opens Spotlight (hotkey 64)"
    else
      bad "Command+Space no longer opens Spotlight (Raycast may have taken it). Fix: System Settings → Keyboard → Keyboard Shortcuts… → Spotlight → tick Show Spotlight search (Command+Space) → Done, or run macconfig --fix"
    fi
  fi
  CHECKED=$((CHECKED + 1))
  fixid repo-file
  if [ -x "$DOTDIR/scripts/pin-spotlight-hotkey-64.sh" ]; then
    pass "scripts/pin-spotlight-hotkey-64.sh present"
  else
    bad "scripts/pin-spotlight-hotkey-64.sh missing"
  fi
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

# ---- 9. dictation shortcut -----------------------------------------------
# Symbolic hotkey 164 is "Start Dictation". On this MacBook the default
# "Press microphone" binding uses Fn/Globe and will start the mic on hold.
# Desired: enabled, type=modifier, first parameter = 1048592 (Right Command twice)
# — an unused combo so Fn never owns dictation. Nested plist, not a macos-defaults row.
hdr "Dictation shortcut"
fixid dictation-164
CHECKED=$((CHECKED + 1))
hk="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null || true)"
if [ -z "$hk" ]; then
  bad "symbolichotkeys not readable"
else
  # Extract the 164 = { ... }; block (enabled + type + first parameter).
  blk="$(printf '%s\n' "$hk" | awk '
    $0 ~ /^[[:space:]]*164 =/ {grab=1}
    grab {print}
    grab && $0 ~ /^[[:space:]]*};[[:space:]]*$/ {exit}
  ')"
  enabled="$(printf '%s\n' "$blk" | awk '/enabled/ {print $3; exit}' | tr -d ';' )"
  ptype="$(printf '%s\n' "$blk" | awk '/type/ {print $3; exit}' | tr -d '";' )"
  p1="$(printf '%s\n' "$blk" | awk '/parameters/ {getline; print $1; exit}' | tr -d ',' )"
  if [ "$enabled" = "1" ] && [ "$ptype" = "modifier" ] && [ "$p1" = "1048592" ]; then
    pass "dictation hotkey 164 = Right Command twice (not Fn/mic)"
  else
    bad "dictation hotkey 164 enabled=$enabled type=${ptype:-?} p1=${p1:-?} (expected enabled=1 type=modifier p1=1048592 Right Command twice)"
  fi
fi
CHECKED=$((CHECKED + 1))
fixid repo-file
if [ -x "$DOTDIR/scripts/pin-dictation-hotkey-164.sh" ]; then
  pass "scripts/pin-dictation-hotkey-164.sh present"
else
  bad "scripts/pin-dictation-hotkey-164.sh missing"
fi
# Rendered plist (not a symlink) plus loaded job. --fix rewrites a drifted
# plist and bootout/bootstraps; a matching plist that isn't loaded is only
# bootstrapped. Same arg for both so one fixer run covers both.
check_repo_launchagent com.pdone.pin-dictation-hotkey-164 \
  "re-pins 164 at login and when symbolichotkeys changes"

# ---- 9a. Quick Note shortcut (Globe/Fn+Q) ---------------------------------
# Symbolic hotkey 190 is "Quick Note". Default is enabled with Fn/Globe+Q.
# Desired: disabled (enabled=0, type=standard, parameters unbound).
hdr "Quick Note shortcut"
fixid quicknote-190
CHECKED=$((CHECKED + 1))
hk="$(defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys 2>/dev/null || true)"
if [ -z "$hk" ]; then
  bad "symbolichotkeys not readable"
else
  blk="$(printf '%s\n' "$hk" | awk '
    $0 ~ /^[[:space:]]*190 =/ {grab=1}
    grab {print}
    grab && $0 ~ /^[[:space:]]*};[[:space:]]*$/ {exit}
  ')"
  enabled="$(printf '%s\n' "$blk" | awk '/enabled/ {print $3; exit}' | tr -d ';' )"
  ptype="$(printf '%s\n' "$blk" | awk '/type/ {print $3; exit}' | tr -d '";' )"
  p1="$(printf '%s\n' "$blk" | awk '/parameters/ {getline; print $1; exit}' | tr -d ',' )"
  case "${enabled:-}" in 0|false|False) en_ok=1 ;; *) en_ok=0 ;; esac
  if [ "$en_ok" = 1 ] && [ "${ptype:-}" = "standard" ] && [ "${p1:-}" = "65535" ]; then
    pass "Quick Note hotkey 190 = disabled (not Globe/Fn+Q)"
  else
    bad "Quick Note hotkey 190 enabled=${enabled:-missing} type=${ptype:-?} p1=${p1:-?} (expected enabled=0 type=standard p1=65535)"
  fi
fi
CHECKED=$((CHECKED + 1))
fixid repo-file
if [ -x "$DOTDIR/scripts/pin-quicknote-hotkey-190.sh" ]; then
  pass "scripts/pin-quicknote-hotkey-190.sh present"
else
  bad "scripts/pin-quicknote-hotkey-190.sh missing"
fi
check_repo_launchagent com.pdone.pin-quicknote-hotkey-190 \
  "re-disables 190 at login and when symbolichotkeys changes"

# ---- 9b. Spotlight search (Command+Space) --------------------------------
# Symbolic hotkey 64 is "Show Spotlight search". Desired: enabled, type=standard,
# parameters (32, 49, 1048576). Raycast's Replace Spotlight button sets enabled=0.
# No LaunchAgent: macos.sh and macconfig --fix write it only when it differs.
hdr "Spotlight shortcut"
check_spotlight_hotkey
check_pdone_launchagents
