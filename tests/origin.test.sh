#!/usr/bin/env bash
# SC2317: the section's helpers are stubs called by the sourced checks/shell.sh.
# shellcheck disable=SC2317
#
# Cursor origin CLI. Homebrew has no formula. install.sh and macconfig --fix
# run Cursor's installer only when ~/.local/bin/origin is missing or not an
# executable file. The Login shell check warns in that case. The helper copies
# the repo gitconfig and writes it back when the installer changes it. Tests
# stub curl and sh, and point HOME at a temp directory, so nothing is
# downloaded and this machine's origin binary is not read. The gitconfig
# cases use a copy, not this repo's gitconfig.
# Run: ./tests/origin.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=hermetic.sh disable=SC1091
. "$DIR/tests/hermetic.sh"
# shellcheck source=../lib/safe-fixers.sh disable=SC1091
. "$DIR/lib/safe-fixers.sh"

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
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;;
    *) pass=$((pass + 1)) ;; esac
}
rc_of() { printf '%s\n' "$1" | tail -n 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
safe="$(hermetic_safe_root)"

URL="https://downloads.cursor.com/origin/install.sh"

# ---- the Login shell check -------------------------------------------------
run_shell_section() (
  set -euo pipefail
  HOME="$1"
  USER=tester
  CHECKED=0
  if [ -n "${2:-}" ]; then
    ORIGIN_BIN="$2"
    export ORIGIN_BIN
  fi
  brew() { printf '/opt/homebrew\n'; }
  dscl() { printf 'UserShell: /opt/homebrew/bin/fish\n'; }
  hdr() { printf '[%s]\n' "$1"; }
  fixid() { printf 'fixid %s\n' "$1"; }
  pass() { printf 'ok %s\n' "$1"; }
  bad() { printf 'DRIFT %s\n' "$1"; }
  warn() { printf 'warn %s\n' "$1"; }
  # shellcheck source=../checks/shell.sh disable=SC1091
  . "$DIR/checks/shell.sh"
  printf 'checked %s\n' "$CHECKED"
)

home="$tmp/home"
mkdir -p "$home"
out="$(run_shell_section "$home")"
has "a missing origin binary warns" "warn origin missing or not executable at $home/.local/bin/origin" "$out"
has "login shell and origin both count" "checked 2" "$out"
has "the warning is tagged origin" "fixid origin" "$out"
has "the warning names install.sh" "run install.sh, or macconfig --fix" "$out"
miss "a missing origin binary is not drift" "DRIFT" "$out"

mkdir -p "$home/.local/bin"
printf '#!/bin/sh\nexit 0\n' > "$home/.local/bin/origin"
chmod 644 "$home/.local/bin/origin"
out="$(run_shell_section "$home")"
has "a non-executable origin file warns" "warn origin missing or not executable at $home/.local/bin/origin" "$out"
miss "a non-executable origin file is not drift" "DRIFT" "$out"

rm -f "$home/.local/bin/origin"
mkdir -p "$home/.local/bin/origin"
out="$(run_shell_section "$home")"
has "a directory at the origin path warns" "warn origin missing or not executable at $home/.local/bin/origin" "$out"
rmdir "$home/.local/bin/origin"

printf '#!/bin/sh\nexit 0\n' > "$home/.local/bin/origin"
chmod +x "$home/.local/bin/origin"
out="$(run_shell_section "$home")"
has "an executable origin passes" "ok origin installed at $home/.local/bin/origin" "$out"
miss "an executable origin does not warn" "warn origin" "$out"

link="$tmp/linked-origin"
printf '#!/bin/sh\nexit 0\n' > "$link"
chmod +x "$link"
ln -sfn "$link" "$home/.local/bin/origin"
out="$(run_shell_section "$home")"
has "a symlink to an executable origin passes" "ok origin installed at $home/.local/bin/origin" "$out"

row="$(awk -F'|' '$1 == "origin" { print $2 "|" $3; exit }' "$DIR/lib/autofix.list")"
eq "origin is SAFE and the fixer reruns the installer" "SAFE|origin" "$row"

# ---- the shared installer --------------------------------------------------
stubs="$tmp/stubs"
mkdir -p "$stubs"
curl_log="$tmp/curl.log"
sh_log="$tmp/sh.log"
: > "$curl_log"
: > "$sh_log"
cat > "$stubs/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${CURL_LOG:?}"
if [ "${CURL_FAIL:-0}" = 1 ]; then
  exit 1
fi
printf '%s\n' 'echo installer'
exit 0
EOF
cat > "$stubs/sh" <<'EOF'
#!/bin/sh
body="$(cat || true)"
# An empty body is a failed download. Do not create the binary.
if [ -z "$body" ]; then
  exit 1
fi
printf '%s\n' sh >> "${SH_LOG:?}"
# The real installer rewrites ~/.gitconfig (absolute credential helper, blank
# helper lines moved). ~/.gitconfig is a symlink to the repo file, so the
# write lands there. A neighbor file is touched to prove only gitconfig is
# put back.
if [ "${SH_REWRITE_GITCONFIG:-0}" = 1 ]; then
  cat > "${HOME}/.gitconfig" <<END
[credential "https://origin.cursor.com/git"]
	helper = !${HOME}/.local/bin/origin credential-helper
	helper =
[credential "https://origin.cursor.com"]
	helper = !${HOME}/.local/bin/origin credential-helper
	helper =
END
  if [ -n "${SH_MUTATED_COPY:-}" ]; then
    cat "${HOME}/.gitconfig" > "$SH_MUTATED_COPY"
  fi
fi
if [ -n "${SH_OTHER_FILE:-}" ]; then
  printf 'installer-touched\n' > "$SH_OTHER_FILE"
fi
if [ "${SH_SKIP_BIN:-0}" = 1 ]; then
  exit 0
fi
mkdir -p "$(dirname "$ORIGIN_BIN")"
printf '#!/bin/sh\nexit 0\n' > "$ORIGIN_BIN"
chmod +x "$ORIGIN_BIN"
exit 0
EOF
cat > "$stubs/git" <<'EOF'
#!/bin/sh
if [ -n "${GIT_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$GIT_LOG"
fi
exit 0
EOF
chmod +x "$stubs/curl" "$stubs/sh" "$stubs/git"

run_install() {
  local rc=0
  CURL_LOG="$curl_log" SH_LOG="$sh_log" PATH="$stubs:$safe" \
    ORIGIN_BIN="$1" HOME="$home" DRY_RUN="${2:-0}" CURL_FAIL="${3:-0}" SH_SKIP_BIN="${4:-0}" \
    safe_install_origin 2>&1 || rc=$?
  printf '%s\n' "$rc"
}

bin="$tmp/bin/origin"
: > "$curl_log"
: > "$sh_log"
out="$(run_install "$home/.local/bin/origin" 0)"
eq "an existing executable is left alone" 0 "$(rc_of "$out")"
has "an existing executable is reported" "origin already installed (~/.local/bin/origin)" "$out"
eq "an existing executable does not download" "" "$(cat "$curl_log")"
eq "an existing executable does not run sh" "" "$(cat "$sh_log")"

: > "$curl_log"
: > "$sh_log"
out="$(run_install "$bin" 1)"
eq "dry-run of a missing binary exits 0" 0 "$(rc_of "$out")"
has "dry-run names the installer" "would install origin (curl -fsSL $URL | sh)" "$out"
has "dry-run names the missing path" "because $bin is missing or not executable" "$out"
eq "dry-run does not download" "" "$(cat "$curl_log")"
eq "dry-run does not create the binary" "no" "$([ -e "$bin" ] && echo yes || echo no)"

mkdir -p "$(dirname "$bin")"
printf '#!/bin/sh\n' > "$bin"
chmod 644 "$bin"
: > "$curl_log"
out="$(run_install "$bin" 1)"
has "dry-run of a non-executable file still names the installer" "would install origin" "$out"
eq "dry-run of a non-executable file does not download" "" "$(cat "$curl_log")"
eq "dry-run leaves the non-executable file in place" "file" \
  "$([ -f "$bin" ] && [ ! -x "$bin" ] && echo file || echo other)"
rm -f "$bin"

: > "$curl_log"
: > "$sh_log"
out="$(run_install "$bin" 0)"
eq "installer success exits 0" 0 "$(rc_of "$out")"
has "installer success is reported" "installed origin ($bin)" "$out"
eq "installer is downloaded with curl -fsSL" "-fsSL $URL" "$(cat "$curl_log")"
eq "installer is piped to sh" "sh" "$(cat "$sh_log")"
eq "installer leaves an executable" "yes" "$([ -f "$bin" ] && [ -x "$bin" ] && echo yes || echo no)"

: > "$curl_log"
: > "$sh_log"
out="$(run_install "$bin" 0)"
eq "a second run does not download again" "" "$(cat "$curl_log")"
has "a second run reports the binary already installed" "origin already installed" "$out"

rm -f "$bin"
: > "$curl_log"
: > "$sh_log"
out="$(run_install "$bin" 0 1)"
eq "a failed download exits 1" 1 "$(rc_of "$out")"
has "a failed download is reported" "origin installer failed ($bin)" "$out"
eq "a failed download does not run sh" "" "$(cat "$sh_log")"
eq "a failed download leaves no binary" "no" "$([ -e "$bin" ] && echo yes || echo no)"

: > "$curl_log"
: > "$sh_log"
out="$(run_install "$bin" 0 0 1)"
eq "an installer that writes nothing exits 1" 1 "$(rc_of "$out")"
has "a finished installer with no binary says so" "still missing or not executable" "$out"
eq "that installer did run sh" "sh" "$(cat "$sh_log")"

# ---- install.sh dry-run ----------------------------------------------------
dry_home="$tmp/dry-home"
mkdir -p "$dry_home"
: > "$curl_log"
dry_out="$(HOME="$dry_home" PATH="$stubs:$safe" CURL_LOG="$curl_log" SH_LOG="$sh_log" \
  "$DIR/install.sh" --dry-run 2>&1)" || dry_rc=$?
dry_rc=${dry_rc:-0}
eq "install.sh --dry-run exits 0" 0 "$dry_rc"
has "install.sh --dry-run describes the origin install" "would install origin (curl -fsSL $URL | sh)" "$dry_out"
has "install.sh --dry-run says nothing is changed" "nothing is changed" "$dry_out"
eq "install.sh --dry-run does not download" "" "$(cat "$curl_log")"
eq "install.sh --dry-run does not create origin" "no" \
  "$([ -e "$dry_home/.local/bin/origin" ] && echo yes || echo no)"
eq "install.sh --dry-run does not create Developer" "no" \
  "$([ -d "$dry_home/Developer" ] && echo yes || echo no)"

install_src="$(cat "$DIR/install.sh")"
has "the real install runs the origin helper" "safe_install_origin" \
  "$(awk '/uname -s/,0' "$DIR/install.sh")"
has "a failed origin install does not abort setup" 'safe_install_origin || origin_rc=$?' "$install_src"
miss "install.sh does not name the installer URL" "downloads.cursor.com/origin/install.sh" "$install_src"

# ---- gitconfig is left byte-identical --------------------------------------
# The installer writes through ~/.gitconfig. When that is a symlink to the
# repo file, the tracked bytes change. The helper puts back only that file.
git_log="$tmp/git.log"
: > "$git_log"
helper_src="$(cat "$DIR/lib/safe-fixers.sh")"
miss "the helper does not check out the repo" "git checkout" "$helper_src"
miss "the helper does not git restore" "git restore" "$helper_src"

mtime_of() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}
run_install_gitconfig() {
  local rc=0
  CURL_LOG="$curl_log" SH_LOG="$sh_log" GIT_LOG="$git_log" PATH="$stubs:$safe" \
    ORIGIN_BIN="$1" ORIGIN_GITCONFIG="$2" HOME="$home" \
    DRY_RUN="${3:-0}" SH_REWRITE_GITCONFIG="${4:-0}" SH_OTHER_FILE="${5:-}" \
    SH_MUTATED_COPY="${6:-}" SH_SKIP_BIN="${7:-0}" CURL_FAIL="${8:-0}" \
    safe_install_origin 2>&1 || rc=$?
  printf '%s\n' "$rc"
}

repo="$tmp/repo"
mkdir -p "$repo"
repo_git="$repo/gitconfig"
neighbor="$repo/neighbor"
orig="$tmp/gitconfig.orig"
mutated="$tmp/gitconfig.mutated"
cp "$DIR/gitconfig" "$repo_git"
cp "$repo_git" "$orig"
ln -sfn "$repo_git" "$home/.gitconfig"
printf 'leave-me\n' > "$neighbor"
git_bin="$tmp/git-bin/origin"

: > "$curl_log"
: > "$sh_log"
: > "$git_log"
out="$(run_install_gitconfig "$git_bin" "$repo_git" 0 1 "$neighbor" "$mutated")"
eq "a rewrite through the symlink still exits 0" 0 "$(rc_of "$out")"
has "a rewrite through the symlink reports install" "installed origin ($git_bin)" "$out"
eq "the installer wrote a mutated copy" "yes" "$([ -s "$mutated" ] && echo yes || echo no)"
eq "the mutated copy differs from the repo file" "no" "$(cmp -s "$orig" "$mutated" && echo yes || echo no)"
eq "repo gitconfig is byte-identical after install" "yes" "$(cmp -s "$orig" "$repo_git" && echo yes || echo no)"
eq "the symlink still points at the repo file" "$repo_git" "$(readlink "$home/.gitconfig")"
eq "a neighbor file the installer changed stays changed" "installer-touched" "$(cat "$neighbor")"
eq "the helper does not run git" "" "$(cat "$git_log")"
# shellcheck disable=SC2016  # the helper text is compared literally
has "restored gitconfig keeps the \$HOME helper" '!$HOME/.local/bin/origin credential-helper' "$(cat "$repo_git")"
miss "restored gitconfig has no absolute helper" "!$home/.local/bin/origin credential-helper" "$(cat "$repo_git")"

# Unchanged bytes are not written back. The neighbor still changes, so this
# also shows a file other than gitconfig is left alone.
cp "$orig" "$repo_git"
printf 'leave-me\n' > "$neighbor"
touch -t 200001010000 "$repo_git"
unchanged_mtime="$(mtime_of "$repo_git")"
rm -f "$git_bin"
: > "$curl_log"
: > "$sh_log"
: > "$git_log"
out="$(run_install_gitconfig "$git_bin" "$repo_git" 0 0 "$neighbor")"
eq "an installer that leaves gitconfig alone exits 0" 0 "$(rc_of "$out")"
eq "an untouched gitconfig stays byte-identical" "yes" "$(cmp -s "$orig" "$repo_git" && echo yes || echo no)"
eq "an untouched gitconfig is not rewritten" "$unchanged_mtime" "$(mtime_of "$repo_git")"
eq "a neighbor stays changed when gitconfig was not" "installer-touched" "$(cat "$neighbor")"
eq "git is not run when gitconfig was not changed" "" "$(cat "$git_log")"

# A failed install that already rewrote gitconfig still puts the file back.
rm -f "$git_bin" "$mutated"
cp "$orig" "$repo_git"
: > "$curl_log"
: > "$sh_log"
: > "$git_log"
out="$(run_install_gitconfig "$git_bin" "$repo_git" 0 1 "" "$mutated" 1)"
eq "a failed install that rewrote gitconfig exits 1" 1 "$(rc_of "$out")"
has "a failed install that rewrote gitconfig says so" "still missing or not executable" "$out"
eq "a failed install wrote a mutated copy" "yes" "$([ -s "$mutated" ] && echo yes || echo no)"
eq "a failed install's mutated copy differs" "no" "$(cmp -s "$orig" "$mutated" && echo yes || echo no)"
eq "a failed install leaves gitconfig byte-identical" "yes" "$(cmp -s "$orig" "$repo_git" && echo yes || echo no)"
eq "git is not run when the install fails" "" "$(cat "$git_log")"

# The user's own ~/.gitconfig, when it is not the repo file, is not reverted.
user_git="$tmp/user-gitconfig"
printf 'user-owned\n' > "$user_git"
rm -f "$home/.gitconfig"
ln -sfn "$user_git" "$home/.gitconfig"
rm -f "$git_bin"
: > "$curl_log"
: > "$sh_log"
out="$(run_install_gitconfig "$git_bin" "$repo_git" 0 1)"
eq "a separate user gitconfig is left as the installer wrote it" "no" \
  "$(cmp -s "$user_git" "$orig" && echo yes || echo no)"
has "a separate user gitconfig keeps the absolute helper" "!$home/.local/bin/origin credential-helper" "$(cat "$user_git")"
eq "the repo file stays byte-identical when the user file is separate" "yes" \
  "$(cmp -s "$orig" "$repo_git" && echo yes || echo no)"

# Dry-run does not download and does not write the repo file.
rm -f "$git_bin"
cp "$orig" "$repo_git"
ln -sfn "$repo_git" "$home/.gitconfig"
touch -t 200001010000 "$repo_git"
dry_mtime="$(mtime_of "$repo_git")"
: > "$curl_log"
: > "$sh_log"
out="$(run_install_gitconfig "$git_bin" "$repo_git" 1 1)"
eq "dry-run with a gitconfig exits 0" 0 "$(rc_of "$out")"
eq "dry-run with a gitconfig does not download" "" "$(cat "$curl_log")"
eq "dry-run leaves gitconfig byte-identical" "yes" "$(cmp -s "$orig" "$repo_git" && echo yes || echo no)"
eq "dry-run does not write gitconfig" "$dry_mtime" "$(mtime_of "$repo_git")"

printf 'origin tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
