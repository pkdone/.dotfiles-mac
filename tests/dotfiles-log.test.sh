#!/usr/bin/env bash
#
# Run logs go to ~/Library/Logs/dotfiles/ and nowhere inside the repo.
# Run: ./tests/dotfiles-log.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/dotfiles-log.sh disable=SC1091
. "$DIR/lib/dotfiles-log.sh"

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
trap 'rm -rf "$tmp" "$DIR/no-such-home-logtest"' EXIT

# --- gitignore belt ---
ignore="$(cat "$DIR/.gitignore")"
has "gitignore ignores log files" '*.log' "$ignore"
has "gitignore ignores a logs directory" 'logs/' "$ignore"

# --- refuse a log directory inside the checkout ---
inside=""
if inside="$(HOME="$DIR/no-such-home-logtest" dotfiles_new_log sample 2>"$tmp/inside.err")"; then
  inside_rc=0
else
  inside_rc=$?
fi
eq "log inside the repo is refused" 1 "$inside_rc"
eq "no path printed when refused" "" "$inside"
miss "refused run does not create the home" "no-such-home-logtest" "$(find "$DIR" -maxdepth 1 -name 'no-such-home-logtest' -print)"
has "refusal names the rule" "Logs belong in ~/Library/Logs/dotfiles/" "$(cat "$tmp/inside.err")"

# --- a real log is outside the repo, named, and pruned ---
home="$tmp/home"
mkdir -p "$home"
old="$home/Library/Logs/dotfiles/install-20000101-000000.log"
fresh="$home/Library/Logs/dotfiles/install-20990101-000000.log"
mkdir -p "$(dirname "$old")"
printf 'old\n' > "$old"
printf 'fresh\n' > "$fresh"
python3 -c 'import os,sys,time; os.utime(sys.argv[1], (time.time()-40*86400,)*2)' "$old"
python3 -c 'import os,sys,time; os.utime(sys.argv[1], (time.time()-86400,)*2)' "$fresh"

log_path="$(HOME="$home" dotfiles_new_log install)"
eq "new log is under Library/Logs/dotfiles" "$home/Library/Logs/dotfiles" "$(dirname "$log_path")"
case "$(basename "$log_path")" in
  install-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].log) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); printf 'FAIL: log name\n  actual: [%s]\n' "$(basename "$log_path")" ;;
esac
if [ -f "$old" ]; then
  fail=$((fail + 1))
  echo "FAIL: log older than 30 days was kept"
else
  pass=$((pass + 1))
fi
if [ -f "$fresh" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: recent log was pruned"
fi

# --- wrapper tees the run and does not record the environment ---
cat > "$tmp/sample.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
. "$DIR/lib/dotfiles-log.sh"
dotfiles_log_exec sample "\$@"
printf 'hello from inner %s\\n' "\$*"
EOF
chmod +x "$tmp/sample.sh"
export DOTFILES_TEST_SECRET="super-secret-token"
out="$(HOME="$home" "$tmp/sample.sh" one two 2>&1)"
rc=$?
unset DOTFILES_TEST_SECRET
eq "wrapped sample exits 0" 0 "$rc"
has "sample says hello" "hello from inner one two" "$out"
case "$out" in
  *"Log: $home/Library/Logs/dotfiles/sample-"*) pass=$((pass + 1)) ;;
  *) fail=$((fail + 1)); printf 'FAIL: log path not printed\n  actual: [%s]\n' "$out" ;;
esac
logged="$(find "$home/Library/Logs/dotfiles" -name 'sample-*.log' -print)"
has "log file contains the run" "hello from inner one two" "$(cat "$logged")"
miss "log file does not contain the secret" "super-secret-token" "$(cat "$logged")"
repo_logs="$(find "$DIR" -name '*.log' -not -path "$DIR/.git/*" -print || true)"
eq "repo checkout has no log files" "" "$repo_logs"

# bootstrap.sh logs, then runs install.sh, which logs again. The inner
# stdout is a pipe. An interactive flag already set by the outer run must
# survive that second wrapper, or sudo -v is skipped for pkg casks.
cat > "$tmp/child.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
. "$DIR/lib/dotfiles-log.sh"
dotfiles_log_exec child "\$@"
printf 'child_interactive=%s child_tty=%s\n' "\${DOTFILES_INTERACTIVE}" "\${DOTFILES_STDOUT_TTY}"
EOF
cat > "$tmp/parent.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
. "$DIR/lib/dotfiles-log.sh"
dotfiles_log_exec parent "\$@"
printf 'parent_interactive=%s parent_tty=%s\n' "\${DOTFILES_INTERACTIVE}" "\${DOTFILES_STDOUT_TTY}"
"$tmp/child.sh"
EOF
chmod +x "$tmp/child.sh" "$tmp/parent.sh"
nested="$(HOME="$home" DOTFILES_INTERACTIVE=1 DOTFILES_STDOUT_TTY=1 "$tmp/parent.sh" 2>&1)"
nested_rc=$?
eq "nested log wrappers exit 0" 0 "$nested_rc"
has "outer log keeps interactive" "parent_interactive=1" "$nested"
has "inner log keeps interactive" "child_interactive=1" "$nested"
has "inner log keeps the color tty" "child_tty=1" "$nested"
plain="$(HOME="$home" env -u DOTFILES_INTERACTIVE -u DOTFILES_STDOUT_TTY "$tmp/child.sh" 2>&1)"
has "a fresh piped run is not interactive" "child_interactive=0" "$plain"
has "a fresh piped run has no color tty" "child_tty=0" "$plain"

# --- entry points wire the logger; root is refused before any log ---
has "install.sh logs" "dotfiles_log_exec install" "$(cat "$DIR/install.sh")"
has "bootstrap.sh logs" "dotfiles_log_exec bootstrap" "$(cat "$DIR/bootstrap.sh")"
has "brewsync logs" "dotfiles_new_log brewsync" "$(cat "$DIR/fish/functions/brewsync.fish")"

rootbin="$tmp/rootbin"
mkdir -p "$rootbin"
cat > "$rootbin/id" <<'EOF'
#!/bin/sh
if [ "$1" = "-u" ]; then echo 0; exit 0; fi
echo 0
EOF
chmod +x "$rootbin/id"
root_out="$(HOME="$home" PATH="$rootbin:/usr/bin:/bin" "$DIR/install.sh" 2>&1)"
root_rc=$?
eq "install.sh refuses root" 1 "$root_rc"
has "install.sh root message" "refusing to run as root" "$root_out"
boot_out="$(HOME="$home" PATH="$rootbin:/usr/bin:/bin" "$DIR/bootstrap.sh" --help 2>&1)"
boot_rc=$?
eq "bootstrap.sh refuses root" 1 "$boot_rc"
has "bootstrap.sh root message" "refusing to run as root" "$boot_out"

help_out="$(HOME="$home" "$DIR/bootstrap.sh" --help 2>&1)"
help_rc=$?
eq "bootstrap --help exits 0" 0 "$help_rc"
has "bootstrap --help is usage" "Usage: bootstrap.sh" "$help_out"
help_logs="$(find "$home/Library/Logs/dotfiles" -name 'bootstrap-*.log' -print || true)"
eq "bootstrap --help does not write a log" "" "$help_logs"

bad_out="$(HOME="$home" "$DIR/bootstrap.sh" --nope 2>&1)"
bad_rc=$?
eq "bootstrap unknown arg exits 2" 2 "$bad_rc"
has "unknown arg names itself" "Unknown argument" "$bad_out"

if [ "$(uname -s)" != Darwin ]; then
  darwin_out="$(HOME="$home" "$DIR/install.sh" 2>&1)"
  darwin_rc=$?
  eq "install.sh on this OS stops before a log" 1 "$darwin_rc"
  has "install.sh names Darwin" "install.sh is for macOS" "$darwin_out"
  # install.sh must not have written a run log. The install-*.log files already
  # here were created by dotfiles_new_log above and are empty of setup output.
  sh_logs="$(grep -l 'Installing from Brewfile' "$home/Library/Logs/dotfiles"/install-*.log 2>/dev/null || true)"
  eq "non-Darwin install.sh writes no run log" "" "$sh_logs"
fi

printf 'dotfiles-log tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
