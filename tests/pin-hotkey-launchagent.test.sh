#!/usr/bin/env bash
#
# Hotkey LaunchAgents: WatchPaths on com.apple.symbolichotkeys, @HOME@ rendered
# at install time (launchd expands neither ~ nor $HOME), bootout/bootstrap when
# the installed plist differs, and pin scripts that do not write when the
# hotkey is already correct (a write would retrigger WatchPaths forever).
# Fake `defaults` only — no launchd and no live symbolichotkeys plist.
# Run: ./tests/pin-hotkey-launchagent.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$DIR/install.sh"
CHECK="$DIR/macconfig-check.sh"
RENDER="$DIR/scripts/install-launchagent.sh"
PIN164="$DIR/scripts/pin-dictation-hotkey-164.sh"
PIN190="$DIR/scripts/pin-quicknote-hotkey-190.sh"
LINKS="$DIR/lib/links.list"
LABEL164=com.pdone.pin-dictation-hotkey-164
LABEL190=com.pdone.pin-quicknote-hotkey-190
WATCH='@HOME@/Library/Preferences/com.apple.symbolichotkeys.plist'

pass=0
fail=0
eq() {  # description expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {  # description needle haystack
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}
miss() {  # description needle haystack
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}
ok() {  # description status
  if [ "$2" = 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s (status %s)\n' "$1" "$2"; fi
}

# ---- repo plists: RunAtLoad stays, WatchPaths is a placeholder ------------
for label in "$LABEL164" "$LABEL190"; do
  plist="$DIR/launchagents/${label}.plist"
  body="$(cat "$plist")"
  has "$label keeps RunAtLoad" '<key>RunAtLoad</key>' "$body"
  has "$label RunAtLoad is true" '<true/>' "$body"
  has "$label throttles to 10s" '<integer>10</integer>' "$body"
  has "$label watches symbolichotkeys via @HOME@" "<string>${WATCH}</string>" "$body"
  watch="$(awk '/<key>WatchPaths<\/key>/,/<\/array>/' "$plist")"
  has "$label WatchPaths array is the placeholder" "$WATCH" "$watch"
  # shellcheck disable=SC2016  # the needle is the literal token, compared as text
  miss "$label WatchPaths does not use \$HOME" '$HOME' "$watch"
  miss "$label WatchPaths does not use a tilde" '~' "$watch"
  miss "$label WatchPaths does not hardcode /Users" '/Users/' "$watch"
  case "$label" in
    *164*) script=pin-dictation-hotkey-164.sh ;;
    *190*) script=pin-quicknote-hotkey-190.sh ;;
  esac
  # shellcheck disable=SC2016  # the needle is plist text, compared literally
  has "$label ProgramArguments still lets bash expand \$HOME" \
    'exec "$HOME/.dotfiles-mac/scripts/'"$script"'"' "$body"
done

rows="$(grep -vE '^[[:space:]]*(#|$)' "$LINKS")"
miss "links.list does not symlink the LaunchAgents" 'launchagents/' "$rows"
has "install.sh renders the plist" 'install-launchagent.sh" --write' "$(cat "$INSTALL")"
has "install.sh reloads with bootout/bootstrap" 'load-launchagent.sh" --reload' "$(cat "$INSTALL")"

fixer="$(awk '/fix_launchagent\(\)/ {grab=1} grab {print} grab && /^  \}$/ {exit}' "$CHECK")"
# shellcheck disable=SC2016  # the needle is source text, compared literally
has "fixer reloads only after a rewrite" 'if [ "$wrote" = 1 ]; then' "$fixer"
has "fixer bootout/bootstrap uses --reload" 'load-launchagent.sh" --reload' "$fixer"
has "check compares the rendered plist" 'install-launchagent.sh" --check' "$(cat "$CHECK")"

# ---- render: absolute home, never through a symlink into the repo ---------
tmp="$(mktemp -d)"
home="$tmp/home"
bin="$tmp/bin"
state="$tmp/hotkeys.txt"
dlog="$tmp/defaults.log"
mkdir -p "$bin"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

cksum_of() { cksum "$1" | awk '{print $1}'; }
mtime_ns() { python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$1"; }

repo164="$DIR/launchagents/${LABEL164}.plist"
repo_sum="$(cksum_of "$repo164")"
dest164="$home/Library/LaunchAgents/${LABEL164}.plist"

out="$(HOME="$home" "$RENDER" --check "$LABEL164" 2>&1)"
rc=$?
eq "missing installed plist fails --check" 1 "$rc"
has "missing plist tells --fix to write and bootstrap" "installed plist missing" "$out"

mkdir -p "$(dirname "$dest164")"
ln -s "$repo164" "$dest164"
out="$(HOME="$home" "$RENDER" --check "$LABEL164" 2>&1)"
rc=$?
eq "symlink fails --check" 1 "$rc"
has "symlink tells --fix to render and reload" "installed plist is a symlink" "$out"

out="$(HOME="$home" "$RENDER" --write "$LABEL164")"
rc=$?
ok "write replaces the symlink" "$rc"
eq "write says updated" updated "$out"
eq "repo plist was not edited through the symlink" "$repo_sum" "$(cksum_of "$repo164")"
if [ -L "$dest164" ]; then eq "installed plist is a regular file" regular symlink
else eq "installed plist is a regular file" regular regular; fi
has "installed WatchPaths is the absolute home" \
  "$home/Library/Preferences/com.apple.symbolichotkeys.plist" "$(cat "$dest164")"
miss "installed plist has no @HOME@ placeholder" '@HOME@' "$(cat "$dest164")"
has "repo plist still has the placeholder" "$WATCH" "$(cat "$repo164")"

out="$(HOME="$home" "$RENDER" --check "$LABEL164")"
rc=$?
ok "matching plist passes --check" "$rc"
has "check names WatchPaths and the throttle" "WatchPaths symbolichotkeys, ThrottleInterval 10" "$out"

before_m="$(mtime_ns "$dest164")"
sleep 0.05
out="$(HOME="$home" "$RENDER" --write "$LABEL164")"
rc=$?
ok "second write succeeds" "$rc"
eq "second write is unchanged" unchanged "$out"
eq "second write does not touch the file" "$before_m" "$(mtime_ns "$dest164")"

printf 'stale\n' > "$dest164"
out="$(HOME="$home" "$RENDER" --check "$LABEL164" 2>&1)"
rc=$?
eq "stale plist fails --check" 1 "$rc"
has "stale plist tells --fix to rewrite and reload" "differs from repo" "$out"
out="$(HOME="$home" "$RENDER" --write "$LABEL164")"
eq "stale plist is rewritten" updated "$out"
out="$(HOME="$home" "$RENDER" --check "$LABEL164")"
rc=$?
ok "rewritten plist matches" "$rc"

# ---- pin scripts: write only when that hotkey differs --------------------
cat > "$bin/defaults" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DEFAULTS_LOG:?}"
cmd="$1"
domain="${2:-}"
key="${3:-}"
if [ "$cmd" = read ] && [ "$domain" = com.apple.symbolichotkeys ] && [ "$key" = AppleSymbolicHotKeys ]; then
  cat "${HOTKEY_STATE:?}"
  exit 0
fi
if [ "$cmd" = write ]; then
  printf 'WRITE %s\n' "$*" >> "${DEFAULTS_LOG:?}"
  exit 0
fi
exit 0
EOF
chmod +x "$bin/defaults"

write_state() {  # 164en 164type 164p1 190en 190type 190p1
  cat > "$state" <<EOF
{
    164 =     {
        enabled = $1;
        value =         {
            parameters =             (
                $3,
                54,
                0
            );
            type = $2;
        };
    };
    190 =     {
        enabled = $4;
        value =         {
            parameters =             (
                $6,
                65535,
                0
            );
            type = $5;
        };
    };
}
EOF
}
run_pin() {
  : > "$dlog"
  HOME="$home" PATH="$bin:$PATH" DEFAULTS_LOG="$dlog" HOTKEY_STATE="$state" "$@"
}
write_count() { grep -c '^WRITE ' "$dlog" || true; }

write_state 1 modifier 1048592 0 standard 65535
out="$(run_pin "$PIN164")"
rc=$?
ok "164 already correct exits 0" "$rc"
has "164 already correct leaves the plist alone" "left alone" "$out"
eq "164 already correct does not defaults-write" 0 "$(write_count)"
out="$(run_pin "$PIN164" --check)"
rc=$?
ok "164 --check ok" "$rc"
has "164 --check says ok" "ok (Right Command twice)" "$out"

out="$(run_pin "$PIN190")"
rc=$?
ok "190 already disabled exits 0" "$rc"
has "190 already disabled leaves the plist alone" "left alone" "$out"
eq "190 already disabled does not defaults-write" 0 "$(write_count)"

# 164 is unbound and 190 is already disabled. The 190 script must not write.
write_state 0 standard 65535 0 standard 65535
out="$(run_pin "$PIN190")"
eq "190 does not write when only 164 drifted" 0 "$(write_count)"
out="$(run_pin "$PIN164")"
rc=$?
ok "164 drift exits 0" "$rc"
eq "164 drift writes once" 1 "$(write_count)"
has "164 drift uses dict-add" "WRITE write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 164 " "$(cat "$dlog")"
miss "164 drift does not touch key 190" "-dict-add 190" "$(cat "$dlog")"

# Follow-up WatchPaths run: the value is correct, so the second start must not write.
write_state 1 modifier 1048592 0 standard 65535
out="$(run_pin "$PIN164")"
eq "164 follow-up does not write" 0 "$(write_count)"
has "164 follow-up left alone" "left alone" "$out"

write_state 1 modifier 1048592 1 standard 65535
out="$(run_pin "$PIN190")"
rc=$?
ok "190 drift exits 0" "$rc"
eq "190 drift writes once" 1 "$(write_count)"
has "190 drift uses dict-add" "WRITE write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 190 " "$(cat "$dlog")"
miss "190 drift does not touch key 164" "-dict-add 164" "$(cat "$dlog")"
out="$(run_pin "$PIN164")"
eq "164 does not write when only 190 drifted" 0 "$(write_count)"

write_state 1 modifier 1048592 false standard 65535
out="$(run_pin "$PIN190" --check)"
rc=$?
ok "190 enabled=false is already disabled" "$rc"
out="$(run_pin "$PIN190")"
eq "190 enabled=false does not write" 0 "$(write_count)"

write_state 0 standard 65535 0 standard 65535
out="$(run_pin "$PIN164" --check)"
rc=$?
eq "164 --check fails when unbound" 1 "$rc"
has "164 --check names the drift" "drift" "$out"

printf 'pin-hotkey-launchagent tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
