# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# scripts/manual-steps.sh calls check_step_xcode_app, check_step_xcode_select,
# check_step_xcode_license, and check_step_xcode_first_launch (@macconfig:apps).
#
# Full Xcode is checked and not installed. On this Mac, `mas install` of Xcode
# needs an administrator, and so do `xcode-select -s`, licence acceptance, and
# first launch. Those commands appear below only as the line Paul runs himself.
# This file never executes them, never calls sudo, and never runs mas.
# Homebrew's preflight still only needs some developer directory so the
# Brewfile can install. Command Line Tools do not pass this section.
#
# Reads, and only these:
#   the app bundle id (com.apple.dt.Xcode)
#   xcode-select -p
#   Contents/version.plist and the GM licence version key
#   <developer-dir>/usr/bin/xcodebuild -checkFirstLaunchStatus
#       once the active directory is that Xcode

xcode_app_path() {
  printf '%s\n' "${XCODE_APP_PATH:-/Applications/Xcode.app}"
}

xcode_developer_dir() {
  printf '%s/Contents/Developer\n' "$(xcode_app_path)"
}

xcode_clt_dir() {
  printf '%s\n' "${XCODE_CLT_DIR:-/Library/Developer/CommandLineTools}"
}

xcode_license_plist() {
  printf '%s\n' "${XCODE_LICENSE_PLIST:-/Library/Preferences/com.apple.dt.Xcode.plist}"
}

xcode_norm() {
  local p="$1"
  while [ -n "$p" ] && [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do
    p="${p%/}"
  done
  printf '%s\n' "$p"
}

xcode_physical() {
  local p
  p="$(xcode_norm "$1")"
  if [ -d "$p" ]; then
    (cd "$p" && pwd -P) 2>/dev/null || printf '%s\n' "$p"
  else
    printf '%s\n' "$p"
  fi
}

xcode_same_dir() {
  local a b
  a="$(xcode_physical "$1")"
  b="$(xcode_physical "$2")"
  [ "$a" = "$b" ]
}

# Prints the active developer directory. 2: xcode-select is missing.
# 142: the read did not finish. 3: it failed or printed nothing.
xcode_selected_dir() {
  local out rc
  if ! command -v xcode-select >/dev/null 2>&1; then
    return 2
  fi
  rc=0
  out="$(with_timeout 10 xcode-select -p 2>/dev/null)" || rc=$?
  out="$(printf '%s\n' "$out" | head -n 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ "$rc" -eq 142 ]; then
    return 142
  fi
  if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
    return 3
  fi
  printf '%s\n' "$out"
}

# Prints one plist value. 3: no such file. 2: key missing or blank.
# 1: unreadable, not a file, or not a plist. 0: value on stdout.
xcode_plist_value() {
  local f="$1" key="$2"
  if [ -z "${DOT_PYTHON:-}" ]; then
    return 1
  fi
  if [ ! -e "$f" ]; then
    return 3
  fi
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    return 1
  fi
  "$DOT_PYTHON" - "$f" "$key" <<'PY'
import plistlib, sys
path, key = sys.argv[1], sys.argv[2]
try:
    data = plistlib.load(open(path, "rb"))
except Exception:
    sys.exit(1)
if not isinstance(data, dict) or key not in data or data[key] is None:
    sys.exit(2)
value = data[key]
if isinstance(value, str):
    value = value.strip()
else:
    value = str(value).strip()
if value == "":
    sys.exit(2)
sys.stdout.write(value)
PY
}

xcode_major() {
  printf '%s\n' "$1" | awk -F. 'NF { if ($1 ~ /^[0-9]+$/) print $1; exit }'
}

xcode_hand_install() {
  printf '%s\n' "Install Xcode from the Mac App Store. macconfig does not install it and does not use sudo."
}

xcode_hand_select() {
  printf '%s\n' "Select it yourself with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer. macconfig does not run that and does not use sudo."
}

xcode_hand_license() {
  printf '%s\n' "Accept it yourself with sudo xcodebuild -license accept, or open Xcode and accept the licence. macconfig does not accept it and does not use sudo."
}

xcode_hand_launch() {
  printf '%s\n' "Open Xcode once, or run sudo xcodebuild -runFirstLaunch yourself. macconfig does not run that and does not use sudo."
}

check_step_xcode_app() {
  local app bid rc
  app="$(xcode_app_path)"
  CHECKED=$((CHECKED + 1))
  if [ ! -d "$app" ]; then
    fixid xcode
    bad "Full Xcode is not installed at $app. Command Line Tools are not full Xcode. $(xcode_hand_install)"
    return 0
  fi
  if [ -z "${DOT_PYTHON:-}" ]; then
    fixid tooling
    warn "python3 missing — can't confirm the bundle id of $app"
    return 0
  fi
  rc=0
  bid="$(xcode_plist_value "$app/Contents/Info.plist" CFBundleIdentifier)" || rc=$?
  if [ "$rc" -eq 1 ]; then
    fixid tooling
    warn "Can't read the bundle id of $app — can't confirm full Xcode"
    return 0
  fi
  if [ "$rc" -ne 0 ] || [ -z "$bid" ]; then
    fixid xcode
    bad "$app is not full Xcode (no bundle id). Command Line Tools are not this app. $(xcode_hand_install)"
    return 0
  fi
  if [ "$bid" != "com.apple.dt.Xcode" ]; then
    fixid xcode
    bad "$app is not full Xcode (bundle id $bid). Command Line Tools are not this app. $(xcode_hand_install)"
    return 0
  fi
  fixid xcode
  pass "Full Xcode is installed at $app (com.apple.dt.Xcode)"
}

check_step_xcode_select() {
  local dev rc want
  CHECKED=$((CHECKED + 1))
  want="$(xcode_developer_dir)"
  rc=0
  dev="$(xcode_selected_dir)" || rc=$?
  case "$rc" in
    0) ;;
    2)
      fixid tooling
      warn "xcode-select missing — can't read the active developer directory"
      return 0
      ;;
    142)
      fixid tooling
      warn "xcode-select -p did not finish — can't read the active developer directory"
      return 0
      ;;
    *)
      fixid tooling
      warn "xcode-select -p returned nothing — can't read the active developer directory"
      return 0
      ;;
  esac
  if xcode_same_dir "$dev" "$want"; then
    fixid xcode
    pass "Active developer directory is $dev (full Xcode)"
    return 0
  fi
  fixid xcode
  if xcode_same_dir "$dev" "$(xcode_clt_dir)"; then
    bad "Active developer directory is $dev (Command Line Tools, not full Xcode). $(xcode_hand_select)"
  else
    bad "Active developer directory is $dev. It should be $want (full Xcode). $(xcode_hand_select)"
  fi
}

check_step_xcode_license() {
  local app installed agreed installed_major agreed_major rc lic
  app="$(xcode_app_path)"
  CHECKED=$((CHECKED + 1))
  if [ ! -d "$app" ]; then
    fixid xcode
    bad "Xcode licence cannot be checked: full Xcode is not installed at $app. Command Line Tools do not use this licence. $(xcode_hand_install) $(xcode_hand_license)"
    return 0
  fi
  if [ -z "${DOT_PYTHON:-}" ]; then
    fixid tooling
    warn "python3 missing — can't read the Xcode licence"
    return 0
  fi
  rc=0
  installed="$(xcode_plist_value "$app/Contents/version.plist" CFBundleShortVersionString)" || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$installed" ]; then
    fixid tooling
    warn "Xcode version unreadable at $app/Contents/version.plist — can't compare the licence"
    return 0
  fi
  lic="$(xcode_license_plist)"
  rc=0
  agreed="$(xcode_plist_value "$lic" IDEXcodeVersionForAgreedToGMLicense)" || rc=$?
  case "$rc" in
    0) ;;
    1)
      fixid tooling
      warn "Xcode licence file can't be read ($lic). $(xcode_hand_license)"
      return 0
      ;;
    *)
      fixid xcode
      bad "Xcode licence is not accepted (installed $installed, agreed nothing). $(xcode_hand_license)"
      return 0
      ;;
  esac
  installed_major="$(xcode_major "$installed")"
  agreed_major="$(xcode_major "$agreed")"
  if [ -n "$installed_major" ] && [ "$installed_major" = "$agreed_major" ]; then
    fixid xcode
    pass "Xcode licence accepted for major version $installed_major (installed $installed, agreed $agreed)"
    return 0
  fi
  fixid xcode
  bad "Xcode licence is not accepted for the installed major version (installed $installed, agreed $agreed). $(xcode_hand_license)"
}

check_step_xcode_first_launch() {
  local app dev xb out rc
  app="$(xcode_app_path)"
  CHECKED=$((CHECKED + 1))
  if [ ! -d "$app" ]; then
    fixid xcode
    bad "Xcode first launch is not done: full Xcode is not installed at $app. Command Line Tools are not a finished Xcode. $(xcode_hand_install) $(xcode_hand_launch)"
    return 0
  fi
  rc=0
  dev="$(xcode_selected_dir)" || rc=$?
  case "$rc" in
    0) ;;
    2)
      fixid tooling
      warn "xcode-select missing — can't check Xcode first launch"
      return 0
      ;;
    142)
      fixid tooling
      warn "xcode-select -p did not finish — can't check Xcode first launch"
      return 0
      ;;
    *)
      fixid tooling
      warn "xcode-select -p returned nothing — can't check Xcode first launch"
      return 0
      ;;
  esac
  if ! xcode_same_dir "$dev" "$(xcode_developer_dir)"; then
    fixid xcode
    if xcode_same_dir "$dev" "$(xcode_clt_dir)"; then
      bad "Xcode first launch is not done. The active developer directory is $dev (Command Line Tools, not full Xcode). $(xcode_hand_launch)"
    else
      bad "Xcode first launch is not done. The active developer directory is $dev, not $(xcode_developer_dir). $(xcode_hand_launch)"
    fi
    return 0
  fi
  xb="$(xcode_norm "$dev")/usr/bin/xcodebuild"
  if [ ! -x "$xb" ]; then
    fixid tooling
    warn "xcodebuild missing at $xb — can't check Xcode first launch"
    return 0
  fi
  rc=0
  out="$(with_timeout 20 "$xb" -checkFirstLaunchStatus 2>&1)" || rc=$?
  case "$out" in
    *"command line tools instance"*|*"requires Xcode"*)
      fixid xcode
      bad "Xcode first launch is not done. xcodebuild says the active developer directory is Command Line Tools, not full Xcode. $(xcode_hand_launch)"
      return 0
      ;;
  esac
  if [ "$rc" -eq 0 ]; then
    fixid xcode
    pass "Xcode first launch is done (active developer directory is full Xcode)"
    return 0
  fi
  if [ "$rc" -eq 142 ]; then
    fixid tooling
    warn "xcodebuild -checkFirstLaunchStatus did not finish — can't check Xcode first launch"
    return 0
  fi
  fixid xcode
  bad "Xcode first launch is not done. $(xcode_hand_launch)"
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

# ---- 8. unwanted apps ---------------------------------------------------
hdr "Unwanted apps"
fixid unwanted-app
UNWANTED_LIST="$DOTDIR/lib/unwanted-apps.list"
if [ ! -r "$UNWANTED_LIST" ]; then
  fixid repo-file; warn "lib/unwanted-apps.list missing — skipping unwanted apps check"
else
  while IFS="|" read -r name path _mas_id; do
    case "$name" in ""|"#"*) continue ;; esac
    name="$(printf "%s" "$name" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")"
    path="$(printf "%s" "$path" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")"
    [ -n "$name" ] || continue
    [ -n "$path" ] || continue
    CHECKED=$((CHECKED + 1))
    if [ -e "$path" ]; then
      bad "$name still installed at $path (run prune-apps.sh)"
    else
      pass "$name absent"
    fi
  done < "$UNWANTED_LIST"
fi

# ---- 8b. full Xcode (checked, not installed) ----------------------------
hdr "Xcode"
check_step_xcode_app
check_step_xcode_select
check_step_xcode_license
check_step_xcode_first_launch
