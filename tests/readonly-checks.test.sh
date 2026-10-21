#!/usr/bin/env bash
#
# Warn-only checks: FileVault's neighbours, disk floor, SSH, LaunchServices,
# Hammerspoon syntax, broken repo symlinks, and com.pdone LaunchAgents.
# Nothing here writes a preference, a plist, or the notification store.
# Run: ./tests/readonly-checks.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "readonly-checks tests: python3 not found, skipped"; exit 0; fi

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

with_timeout() { shift; "$@"; }
export DOT_PYTHON="$PY"
export MACCONFIG_CHECKS_DEFINE_ONLY=1
# shellcheck disable=SC1091
. "$DIR/checks/health.sh"
# shellcheck disable=SC1091
. "$DIR/checks/security.sh"
# shellcheck disable=SC1091
. "$DIR/checks/symlinks.sh"
# shellcheck disable=SC1091
. "$DIR/checks/handlers.sh"
# shellcheck disable=SC1091
. "$DIR/checks/hammerspoon.sh"
# shellcheck disable=SC1091
. "$DIR/checks/hotkeys.sh"
unset MACCONFIG_CHECKS_DEFINE_ONLY

eq "disk under 15% warns" warn "$(disk_space_level 14 100 15 50)"
eq "disk under 50 GB warns" warn "$(disk_space_level 20 49 15 50)"
eq "disk on both floors is ok" ok "$(disk_space_level 15 50 15 50)"
eq "disk above both floors is ok" ok "$(disk_space_level 40 200 15 50)"

eq "empty stealth text warns" "warn" "$(stealth_from_text '' | cut -d'|' -f1)"
eq "stealth enabled is ok" "ok" "$(stealth_from_text 'Stealth mode enabled' | cut -d'|' -f1)"
has "stealth enabled reports the text" "Stealth mode enabled" "$(stealth_from_text 'Stealth mode enabled')"
eq "stealth disabled warns" "warn" "$(stealth_from_text 'Stealth mode disabled' | cut -d'|' -f1)"
eq "stealth is on is ok" "ok" "$(stealth_from_text 'Firewall stealth mode is on' | cut -d'|' -f1)"

write_su_dated() { # path days_ago updates_json auto_off
  "$PY" - "$1" "$2" "$3" "$4" <<'PY'
import json, plistlib, sys
from datetime import datetime, timedelta, timezone
path, days, updates, auto_off = sys.argv[1:]
now = datetime.now(timezone.utc) - timedelta(days=float(days))
data = {
    "CriticalUpdateInstall": auto_off != "critical",
    "ConfigDataInstall": True,
    "AutomaticallyInstallMacOSUpdates": auto_off != "macos",
    "RecommendedUpdates": json.loads(updates),
    "LastSuccessfulDate": now,
}
plistlib.dump(data, open(path, "wb"))
PY
}

write_su_dated "$tmp/fresh.plist" 1 '[]' ''
fresh="$(su_plist_lines "$tmp/fresh.plist")"
eq "fresh cache auto is info" info "$(printf '%s\n' "$fresh" | awk -F'|' '$1=="auto"{print $2; exit}')"
eq "fresh cache pending is ok" ok "$(printf '%s\n' "$fresh" | awk -F'|' '$1=="pending"{print $2; exit}')"
has "auto line names CriticalUpdateInstall" "CriticalUpdateInstall=true" "$fresh"
has "auto line names ConfigDataInstall" "ConfigDataInstall=true" "$fresh"
has "auto line names AutomaticallyInstallMacOSUpdates" "AutomaticallyInstallMacOSUpdates=true" "$fresh"
has "auto line says the employer manages updates" "managed by the employer (MDM)" "$fresh"
miss "auto line is not a warning" "warn|automatic security updates" "$fresh"

write_su_dated "$tmp/off.plist" 1 '[]' critical
off="$(su_plist_lines "$tmp/off.plist")"
eq "critical updates off is info" info "$(printf '%s\n' "$off" | awk -F'|' '$1=="auto"{print $2; exit}')"
has "off line still reports the other keys" "ConfigDataInstall=true" "$off"
has "off line still names CriticalUpdateInstall" "CriticalUpdateInstall=false" "$off"
has "off line still says the employer manages updates" "managed by the employer (MDM)" "$off"
miss "off toggles are not a warning" "warn|automatic security updates" "$off"

write_su_dated "$tmp/old.plist" 10 '[{"Display Name": "macOS Test"}]' ''
old="$(su_plist_lines "$tmp/old.plist")"
eq "update older than 7 days warns" warn "$(printf '%s\n' "$old" | awk -F'|' '$1=="pending"{print $2; exit}')"
has "old update names the title" "macOS Test" "$old"
has "old update mentions LastSuccessfulDate" "LastSuccessfulDate=" "$old"

write_su_dated "$tmp/new.plist" 2 '[{"Display Name": "macOS Recent"}]' ''
new="$(su_plist_lines "$tmp/new.plist")"
eq "update under 7 days is info" info "$(printf '%s\n' "$new" | awk -F'|' '$1=="pending"{print $2; exit}')"

"$PY" - "$tmp/nodate.plist" <<'PY'
import plistlib, sys
plistlib.dump({
    "CriticalUpdateInstall": True,
    "ConfigDataInstall": True,
    "AutomaticallyInstallMacOSUpdates": True,
    "RecommendedUpdates": [{"Display Name": "macOS Undated"}],
}, open(sys.argv[1], "wb"))
PY
nodate="$(su_plist_lines "$tmp/nodate.plist")"
eq "pending update without a date warns" warn "$(printf '%s\n' "$nodate" | awk -F'|' '$1=="pending"{print $2; exit}')"

# SSH agent, modes, and signing. Stubs stand in for ssh-add and ssh-keygen.
bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/ssh-add" <<'EOF'
#!/bin/sh
if [ -n "${SSH_ADD_OUT:-}" ]; then
  printf '%s\n' "$SSH_ADD_OUT"
fi
exit "${SSH_ADD_RC:-0}"
EOF
cat > "$bin/ssh-keygen" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${SIGN_LOG:?}"
if [ "${SIGN_RC:-0}" = 0 ]; then
  echo signed
  exit 0
fi
echo failed >&2
exit "${SIGN_RC:-1}"
EOF
chmod +x "$bin/ssh-add" "$bin/ssh-keygen"

ssh_home="$tmp/sshhome"
mkdir -p "$ssh_home"
ssh_out="$(PATH="$bin:$PATH" SSH_ADD_RC=1 SSH_ADD_OUT="" ssh_audit "$ssh_home")"
miss "no loaded key is not a warning" "no SSH key loaded" "$ssh_out"
miss "no loaded key adds no ssh-add warning" "warn|" "$ssh_out"
has "missing .ssh is info" "info|no ~/.ssh directory" "$ssh_out"
has "signing off is info" "info|commit signing is not configured" "$ssh_out"

mkdir -p "$ssh_home/.ssh"
chmod 755 "$ssh_home/.ssh"
printf 'not a real key\n' > "$ssh_home/.ssh/id_ed25519"
chmod 644 "$ssh_home/.ssh/id_ed25519"
bad_mode="$(PATH="$bin:$PATH" SSH_ADD_RC=0 SSH_ADD_OUT="256 SHA256:abc comment (ED25519)" ssh_audit "$ssh_home")"
has "loaded key passes" "ok|SSH agent has 1 key(s) loaded" "$bad_mode"
has "ssh dir mode warns" "warn|~/.ssh is mode 755 (want 700)" "$bad_mode"
has "private key mode warns" "warn|~/.ssh/id_ed25519 is mode 644 (want 600)" "$bad_mode"

chmod 700 "$ssh_home/.ssh"
chmod 600 "$ssh_home/.ssh/id_ed25519"
cat > "$ssh_home/.gitconfig" <<EOF
[commit]
	gpgsign = true
[gpg]
	format = ssh
[user]
	signingkey = $ssh_home/.ssh/id_ed25519
EOF
sign_log="$tmp/sign.log"
: > "$sign_log"
good="$(PATH="$bin:$PATH" SSH_ADD_RC=0 SSH_ADD_OUT="256 SHA256:abc comment (ED25519)" \
  SIGN_LOG="$sign_log" SIGN_RC=0 HOME="$ssh_home" ssh_audit "$ssh_home")"
has "700 dir passes" "ok|~/.ssh is mode 700" "$good"
has "600 key passes" "ok|~/.ssh/id_ed25519 is mode 600" "$good"
has "dry sign passes" "ok|git commit signing works" "$good"
has "dry sign names the key" "id_ed25519" "$(cat "$sign_log")"
miss "dry sign does not use -Y verify" "-Y verify" "$(cat "$sign_log")"

bad_sign="$(PATH="$bin:$PATH" SSH_ADD_RC=0 SSH_ADD_OUT="256 SHA256:abc" \
  SIGN_LOG="$sign_log" SIGN_RC=1 ssh_audit "$ssh_home")"
has "failed dry sign warns" "warn|git commit signing is configured" "$bad_sign"

# Broken symlinks that point into the repo.
repo="$tmp/repo"
home="$tmp/home"
mkdir -p "$repo/real" "$home/.config" "$home/Library/LaunchAgents" "$home/.dotfiles-mac"
printf 'here\n' > "$repo/real/file"
printf 'here\n' > "$home/.dotfiles-mac/other"
ln -s "$repo/real/file" "$home/.config/good"
ln -s "$repo/real/missing" "$home/.config/bad"
ln -s "/no/such/target" "$home/.config/elsewhere"
ln -s "$home/.dotfiles-mac/missing-agent" "$home/Library/LaunchAgents/stale"
ln -s "$repo/real/missing-dot" "$home/.gitconfig"
ln -s "/etc/hostname" "$home/.vimrc"
broken="$(DOTDIR="$repo" broken_repo_symlinks "$home")"
has "broken config link is reported" "$home/.config/bad" "$broken"
has "broken launchagent link is reported" "$home/Library/LaunchAgents/stale" "$broken"
has "broken home dotfile is reported" "$home/.gitconfig" "$broken"
miss "good link is not reported" "$home/.config/good" "$broken"
miss "link outside the repo is not reported" "$home/.config/elsewhere" "$broken"
miss "valid home dotfile is not reported" "$home/.vimrc" "$broken"

# LaunchServices handlers.
"$PY" - "$tmp/chrome.plist" <<'PY'
import plistlib, sys
plistlib.dump({"LSHandlers": [
    {"LSHandlerURLScheme": "http", "LSHandlerRoleAll": "com.google.Chrome"},
    {"LSHandlerURLScheme": "https", "LSHandlerRoleAll": "com.google.chrome"},
]}, open(sys.argv[1], "wb"))
PY
eq "Chrome handlers are ok" ok "$(launchservices_browser_line "$tmp/chrome.plist" | cut -d'|' -f1)"

"$PY" - "$tmp/safari.plist" <<'PY'
import plistlib, sys
plistlib.dump({"LSHandlers": [
    {"LSHandlerURLScheme": "http", "LSHandlerRoleAll": "com.apple.Safari"},
    {"LSHandlerURLScheme": "https", "LSHandlerRoleAll": "com.google.chrome"},
]}, open(sys.argv[1], "wb"))
PY
safari="$(launchservices_browser_line "$tmp/safari.plist")"
eq "Safari http warns" warn "$(printf '%s\n' "$safari" | cut -d'|' -f1)"
has "Safari warning names http" "http" "$safari"

# Hammerspoon config: fake luac, no running app.
cat > "$bin/luac" <<'EOF'
#!/bin/sh
# -p FILE
file=""
for a in "$@"; do file="$a"; done
if grep -q BAD "$file"; then
  echo "syntax error" >&2
  exit 1
fi
exit 0
EOF
chmod +x "$bin/luac"
hs_repo="$tmp/hsrepo"
mkdir -p "$hs_repo/hammerspoon"
printf 'return {}\n' > "$hs_repo/hammerspoon/init.lua"
clean_line="$(DOTDIR="$hs_repo" H_HS_RUNNING=no PATH="$bin:$PATH" hammerspoon_config_line)"
eq "syntax-clean config is ok" ok "$(printf '%s\n' "$clean_line" | cut -d'|' -f1)"
printf 'BAD\n' > "$hs_repo/hammerspoon/init.lua"
bad_lua="$(DOTDIR="$hs_repo" H_HS_RUNNING=no PATH="$bin:$PATH" hammerspoon_config_line)"
eq "syntax error warns" warn "$(printf '%s\n' "$bad_lua" | cut -d'|' -f1)"
rm -f "$hs_repo/hammerspoon/init.lua"
missing_lua="$(DOTDIR="$hs_repo" H_HS_RUNNING=no hammerspoon_config_line)"
eq "missing init.lua warns" warn "$(printf '%s\n' "$missing_lua" | cut -d'|' -f1)"

# hs runs Lua inside Hammerspoon, which does not see the CLI's environment.
# The path has to be in the code sent over IPC.
hs_code="$(hs_loadfile_code "$hs_repo/hammerspoon/init.lua")"
has "hs code embeds the config path" "$hs_repo/hammerspoon/init.lua" "$hs_code"
miss "hs code does not read HS_CONFIG" "os.getenv" "$hs_code"
cat > "$bin/hs" <<'EOF'
#!/bin/sh
prev=""
code=""
for a in "$@"; do
  if [ "$prev" = "-c" ]; then
    code="$a"
  fi
  prev="$a"
done
printf '%s\n' "$code" > "${HS_LOG:?}"
case "$code" in
  *loadfile*'"'"${HS_EXPECT:?}"'"'*) echo ok; exit 0 ;;
  *os.getenv*) echo "error: nil path"; exit 0 ;;
  *) echo "ipc failed"; exit 1 ;;
esac
EOF
chmod +x "$bin/hs"
printf 'return {}\n' > "$hs_repo/hammerspoon/init.lua"
hs_log="$tmp/hs.log"
: > "$hs_log"
live="$(DOTDIR="$hs_repo" H_HS_RUNNING=yes PATH="$bin:$PATH" HS_LOG="$hs_log" HS_EXPECT="$hs_repo/hammerspoon/init.lua" hammerspoon_config_line)"
eq "running Hammerspoon compiles via embedded path" ok "$(printf '%s\n' "$live" | cut -d'|' -f1)"
has "hs was given the path" "$hs_repo/hammerspoon/init.lua" "$(cat "$hs_log")"
miss "hs command did not use getenv" "os.getenv" "$(cat "$hs_log")"

eq "bare hs ok is success" ok "$(hs_compile_result 'ok')"
eq "quoted hs ok is success" ok "$(hs_compile_result '"ok"')"
eq "bare hs error is a compile failure" error "$(hs_compile_result 'error: near eof' | cut -d'|' -f1)"
eq "quoted hs error is a compile failure" error "$(hs_compile_result '"error: near eof"' | cut -d'|' -f1)"
has "quoted hs error keeps the message" "near eof" "$(hs_compile_result '"error: near eof"')"

# A quoted compile error must not be treated as a lost connection. luac is
# still on PATH and would pass this file, so falling through would hide it.
cat > "$bin/hs" <<'EOF'
#!/bin/sh
printf '%s\n' '"error: unexpected symbol near eof"'
exit 0
EOF
quoted_err="$(DOTDIR="$hs_repo" H_HS_RUNNING=yes PATH="$bin:$PATH" hammerspoon_config_line)"
eq "quoted hs error warns" warn "$(printf '%s\n' "$quoted_err" | cut -d'|' -f1)"
has "quoted hs error names the compile failure" "unexpected symbol near eof" "$quoted_err"
miss "quoted hs error is not the unavailable fallback" "hs unavailable" "$quoted_err"
miss "quoted hs error is not the luac fallback" "lua syntax check" "$quoted_err"

# A managed link is already drift. The extra scan must not warn about it again.
record_managed_link "$home/.config/bad"
CHECKED=0
FIX_ID=""
# These are called from checks/symlinks.sh, which this file does not follow.
# shellcheck disable=SC2317
fixid() { FIX_ID="$1"; }
# shellcheck disable=SC2317
pass() { printf 'PASS %s\n' "$1"; }
# shellcheck disable=SC2317
warn() { printf 'WARN %s %s\n' "$FIX_ID" "$1"; }
managed_out="$(DOTDIR="$repo" HOME="$home" check_broken_dotfiles_symlinks)"
# shellcheck disable=SC2088  # the report prints a literal tilde, not this home
miss "managed broken link is not warned again" "~/.config/bad" "$managed_out"
has "unmanaged broken link is still warned" "broken-symlink" "$managed_out"
has "unmanaged launchagent link is still warned" "LaunchAgents/stale" "$managed_out"

# --only health did not run the hotkeys section, so an unloaded pin agent
# is not already reported.
if LAUNCHAGENT_CHECKED="" health_pin_already_reported com.pdone.pin-dictation-hotkey-164; then
  eq "unloaded pin with no hotkeys section is not already reported" no yes
else
  eq "unloaded pin with no hotkeys section is not already reported" no no
fi
if LAUNCHAGENT_CHECKED="com.pdone.pin-dictation-hotkey-164" health_pin_already_reported com.pdone.pin-dictation-hotkey-164; then
  eq "pin already checked by hotkeys is skipped" yes yes
else
  eq "pin already checked by hotkeys is skipped" yes no
fi
if LAUNCHAGENT_CHECKED="com.pdone.pin-dictation-hotkey-164" health_pin_already_reported com.pdone.pin-quicknote-hotkey-190; then
  eq "the other pin is not skipped" no yes
else
  eq "the other pin is not skipped" no no
fi

# com.pdone LaunchAgents. Fake --check compares the rendered template.
la_repo="$tmp/larepo"
mkdir -p "$la_repo/scripts" "$la_repo/launchagents" "$tmp/lahome/Library/LaunchAgents"
printf 'home=@HOME@\n' > "$la_repo/launchagents/com.pdone.example.plist"
printf 'home=@HOME@\n' > "$la_repo/launchagents/com.pdone.pin-dictation-hotkey-164.plist"
cat > "$la_repo/scripts/install-launchagent.sh" <<'EOF'
#!/bin/sh
mode=""
label=""
for a in "$@"; do
  case "$a" in
    --check) mode=check ;;
    *) label="$a" ;;
  esac
done
repo="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
src="$repo/launchagents/${label}.plist"
dest="${HOME}/Library/LaunchAgents/${label}.plist"
rendered="$(sed "s|@HOME@|${HOME}|g" "$src")"
if [ -L "$dest" ]; then
  echo "installed plist is a symlink"
  exit 1
fi
if [ ! -f "$dest" ]; then
  echo "installed plist missing"
  exit 1
fi
if [ "$(cat "$dest")" != "$rendered" ]; then
  echo "installed plist differs from repo"
  exit 1
fi
echo matches
exit 0
EOF
chmod +x "$la_repo/scripts/install-launchagent.sh"
sed "s|@HOME@|$tmp/lahome|g" "$la_repo/launchagents/com.pdone.example.plist" \
  > "$tmp/lahome/Library/LaunchAgents/com.pdone.example.plist"
sed "s|@HOME@|$tmp/lahome|g" "$la_repo/launchagents/com.pdone.pin-dictation-hotkey-164.plist" \
  > "$tmp/lahome/Library/LaunchAgents/com.pdone.pin-dictation-hotkey-164.plist"

# CHECKED is incremented inside check_pdone_launchagents.
# shellcheck disable=SC2034
CHECKED=0
FIX_ID=""
fixid() { FIX_ID="$1"; }
pass() { printf 'PASS %s\n' "$1"; }
warn() { printf 'WARN %s %s\n' "$FIX_ID" "$1"; }
match_out="$(DOTDIR="$la_repo" HOME="$tmp/lahome" LAUNCHAGENT_CHECKED="" check_pdone_launchagents)"
has "matching agents pass" "PASS com.pdone.* LaunchAgents match" "$match_out"
miss "matching agents do not warn" "WARN " "$match_out"

printf 'nope\n' > "$tmp/lahome/Library/LaunchAgents/com.pdone.unknown.plist"
unknown_out="$(DOTDIR="$la_repo" HOME="$tmp/lahome" LAUNCHAGENT_CHECKED="" check_pdone_launchagents)"
has "unknown agent warns" "WARN launchagent-template LaunchAgent com.pdone.unknown is stale or unknown" "$unknown_out"
miss "unknown run does not claim everything matches" "PASS com.pdone" "$unknown_out"

# A label already reported by the pin section is not warned a second time.
rm -f "$tmp/lahome/Library/LaunchAgents/com.pdone.pin-dictation-hotkey-164.plist"
seen_out="$(DOTDIR="$la_repo" HOME="$tmp/lahome" \
  LAUNCHAGENT_CHECKED="com.pdone.pin-dictation-hotkey-164" check_pdone_launchagents)"
miss "already reported pin agent is not repeated" "pin-dictation" "$seen_out"
miss "already reported mismatch is not an all-clear" "PASS com.pdone" "$seen_out"

# The new checks do not write and do not call the network softwareupdate tool.
sec_code="$(grep -v '^[[:space:]]*#' "$DIR/checks/security.sh")"
miss "security check does not call softwareupdate" "softwareupdate" "$sec_code"
miss "security check does not sudo" "sudo" "$sec_code"
miss "security check does not set stealth mode" "--setstealthmode" "$sec_code"
miss "security check does not defaults write" "defaults write" "$sec_code"
hs_code="$(grep -v '^[[:space:]]*#' "$DIR/checks/hammerspoon.sh")"
miss "hammerspoon check does not reload" "hs.reload" "$hs_code"
miss "hammerspoon check does not dofile" "dofile" "$hs_code"

printf 'readonly-checks tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
