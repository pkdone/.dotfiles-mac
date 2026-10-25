#!/usr/bin/env bash
#
# Brewfile install: a second run changes nothing, and one failing cask does
# not stop the others. brew, curl, df, xcode-select, and sudo are stubs.
# Run: ./tests/brew-bundle.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DIR/scripts/brew-bundle-install.sh"
# shellcheck source=../lib/brew-bundle.sh disable=SC1091
. "$DIR/lib/brew-bundle.sh"

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
count_line() {
  if [ ! -f "$2" ]; then
    echo 0
    return 0
  fi
  # -e so a pattern like -v is not read as a grep flag.
  grep -cFx -e "$1" "$2" || true
}
check() {
  local msg="$1"
  shift
  if "$@"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n' "$msg"
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

install_stubs() {
  cat > "$case_bin/brew" <<'EOF'
#!/bin/sh
if [ -z "${STUB_DIR:-}" ]; then
  echo "brew stub: STUB_DIR is not set" >&2
  exit 99
fi
log="$STUB_DIR/commands"
state="$STUB_DIR/installed"
fail_bundle="$STUB_DIR/fail-bundle"
fail_install="$STUB_DIR/fail-install"
mut="$STUB_DIR/mutations"
touch "$log" "$state" "$fail_bundle" "$fail_install" "$mut"
cmd="$1"
shift
if [ $# -eq 0 ]; then
  printf '%s\n' "$cmd" >> "$log"
else
  printf '%s %s\n' "$cmd" "$*" >> "$log"
fi
if [ -n "${HOMEBREW_CASK_OPTS+x}" ]; then
  printf 'OPTS %s\n' "$HOMEBREW_CASK_OPTS" >> "$log"
fi

parse_file() {
  sed -nE 's/^brew "([^"]+)".*/formula \1/p; s/^cask "([^"]+)".*/cask \1/p' "$1"
}

bundle_file() {
  _prev=""
  for _a in "$@"; do
    if [ "$_prev" = "--file" ]; then
      printf '%s\n' "$_a"
      return 0
    fi
    _prev="$_a"
  done
  return 1
}

do_install_names() {
  _cask=0
  _name=""
  for _a in "$@"; do
    case "$_a" in
      --help)
        if [ -f "$STUB_DIR/no-adopt" ]; then
          echo "  --force"
        else
          echo "  --adopt"
          echo "  --force"
        fi
        exit 0
        ;;
      --cask) _cask=1 ;;
      --adopt) ;;
      -*) ;;
      *) _name="$_a" ;;
    esac
  done
  if [ -z "$_name" ]; then
    echo "brew stub: install needs a name" >&2
    exit 2
  fi
  if [ "$_cask" -eq 1 ]; then
    _kind=cask
  else
    _kind=formula
  fi
  if grep -qxF "$_name" "$fail_install"; then
    echo "Error: It seems there is already an App at '/Applications/${_name}.app'." >&2
    exit 1
  fi
  if grep -qxF "$_kind $_name" "$state"; then
    exit 0
  fi
  echo "$_kind $_name" >> "$state"
  echo "mutate $_kind $_name" >> "$mut"
  exit 0
}

case "$cmd" in
  --prefix)
    echo /opt/homebrew
    exit 0
    ;;
  doctor)
    _mode=ok
    if [ -f "$STUB_DIR/doctor" ]; then
      _mode=$(cat "$STUB_DIR/doctor")
    fi
    case "$_mode" in
      harmless)
        echo "Warning: A newer Command Line Tools release is available."
        exit 1
        ;;
      serious)
        echo "Warning: /opt/homebrew/bin is not in your PATH."
        exit 1
        ;;
      *)
        echo "Your system is ready to brew."
        exit 0
        ;;
    esac
    ;;
  info)
    _json='{"casks":['
    _first=1
    for _a in "$@"; do
      case "$_a" in
        --cask|--json=v2) continue ;;
      esac
      if [ "$_first" -eq 0 ]; then
        _json="$_json,"
      fi
      _first=0
      if [ "$_a" = "karabiner-elements" ]; then
        _json="$_json{\"token\":\"karabiner-elements\",\"artifacts\":[{\"pkg\":[\"Karabiner-Elements.pkg\"]}]}"
      else
        _json="$_json{\"token\":\"$_a\",\"artifacts\":[{\"app\":[\"$_a.app\"]}]}"
      fi
    done
    _json="$_json]}"
    printf '%s\n' "$_json"
    exit 0
    ;;
  list)
    _kind=formula
    for _a in "$@"; do
      case "$_a" in
        --cask) _kind=cask ;;
        --formula) _kind=formula ;;
      esac
    done
    while read -r _k _n; do
      [ "$_k" = "$_kind" ] && printf '%s\n' "$_n"
    done < "$state"
    exit 0
    ;;
  install)
    do_install_names "$@"
    ;;
  bundle)
    _action=install
    _bfile=""
    _prev=""
    _kind=""
    for _a in "$@"; do
      case "$_a" in
        check) _action=check ;;
        list) _action=list ;;
        --formula) _kind=formula ;;
        --cask) _kind=cask ;;
        --file) _prev=file ;;
        *)
          if [ "$_prev" = "file" ]; then
            _bfile="$_a"
            _prev=""
          fi
          ;;
      esac
    done
    if [ "$_action" = "list" ]; then
      parse_file "$_bfile" | while read -r _k _n; do
        [ "$_k" = "$_kind" ] && printf '%s\n' "$_n"
      done
      exit 0
    fi
    if [ "$_action" = "check" ]; then
      if [ -f "$STUB_DIR/check-garbage" ]; then
        echo "something unexpected"
        exit 1
      fi
      rm -f "$STUB_DIR/check-missing"
      parse_file "$_bfile" | while read -r _k _n; do
        [ -n "$_k" ] || continue
        if grep -qxF "$_k $_n" "$state"; then
          continue
        fi
        echo 1 > "$STUB_DIR/check-missing"
        if [ "$_k" = "formula" ]; then
          echo "Formula $_n needs to be installed."
        else
          echo "Cask $_n needs to be installed."
        fi
      done
      if [ -f "$STUB_DIR/check-missing" ]; then
        exit 1
      fi
      exit 0
    fi
    rm -f "$STUB_DIR/bundle-failed"
    parse_file "$_bfile" | while read -r _k _n; do
      [ -n "$_k" ] || continue
      if grep -qxF "$_k $_n" "$state"; then
        continue
      fi
      if grep -qxF "$_n" "$fail_bundle"; then
        echo "Error: Failure while installing $_n" >&2
        echo 1 > "$STUB_DIR/bundle-failed"
        continue
      fi
      echo "$_k $_n" >> "$state"
      echo "mutate $_k $_n" >> "$mut"
    done
    if [ -f "$STUB_DIR/bundle-failed" ]; then
      exit 1
    fi
    exit 0
    ;;
  *)
    echo "brew stub: unknown $cmd" >&2
    exit 99
    ;;
esac
EOF
  cat > "$case_bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/curl.log"
if [ -f "$STUB_DIR/fail-hosts" ]; then
  while read -r _host; do
    [ -n "$_host" ] || continue
    case "$*" in
      *"$_host"*) exit 1 ;;
    esac
  done < "$STUB_DIR/fail-hosts"
fi
exit 0
EOF
  cat > "$case_bin/xcode-select" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/xcode.log"
if [ "$1" = "-p" ]; then
  if [ -f "$STUB_DIR/no-clt" ]; then
    exit 1
  fi
  echo /Library/Developer/CommandLineTools
  exit 0
fi
exit 0
EOF
  cat > "$case_bin/df" <<'EOF'
#!/bin/sh
_avail=50000000
if [ -f "$STUB_DIR/df-avail" ]; then
  _avail=$(cat "$STUB_DIR/df-avail")
fi
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "disk 100000000 1 $_avail 1% /"
exit 0
EOF
  cat > "$case_bin/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_DIR/sudo.log"
exit 0
EOF
  chmod +x "$case_bin/brew" "$case_bin/curl" "$case_bin/xcode-select" "$case_bin/df" "$case_bin/sudo"
}

new_case() {
  case_dir="$tmp/$1"
  case_bin="$case_dir/bin"
  case_home="$case_dir/home"
  STUB_DIR="$case_dir/stub"
  mkdir -p "$case_bin" "$case_home" "$STUB_DIR"
  : > "$STUB_DIR/installed"
  : > "$STUB_DIR/fail-bundle"
  : > "$STUB_DIR/fail-install"
  : > "$STUB_DIR/mutations"
  : > "$STUB_DIR/commands"
  printf '%s\n' ok > "$STUB_DIR/doctor"
  brewfile="$case_dir/Brewfile"
  install_stubs
  DOTFILES_INTERACTIVE=0
  DOTFILES_SUDO_KEEPALIVE_SECS=60
}

run_case() {
  out="$(
    HOME="$case_home" \
      PATH="$case_bin:/usr/bin:/bin" \
      STUB_DIR="$STUB_DIR" \
      DOTFILES_INTERACTIVE="$DOTFILES_INTERACTIVE" \
      DOTFILES_BREW_RETRY_DELAY=0 \
      DOTFILES_SUDO_KEEPALIVE_SECS="$DOTFILES_SUDO_KEEPALIVE_SECS" \
      "$SCRIPT" --file "$brewfile" 2>&1
  )"
  rc=$?
}

cat > "$tmp/full.Brewfile" <<'EOF'
brew "jq"
cask "hammerspoon"
cask "raycast"
cask "karabiner-elements"
EOF

# --- verbose parser (no brew process) ---
sample="$(printf '%s\n' \
  "→ Formula git needs to be installed or updated." \
  "Formula jq needs to be updated." \
  "Cask raycast needs to be installed." \
  "→ Cask slack needs to be installed or updated.")"
parsed="$(brew_missing_from_verbose "$sample")"
eq "parser keeps only not-yet-installed entries" "$(printf '%s\n' "formula git" "cask raycast" "cask slack")" "$parsed"

harmless_doc="$(printf '%s\n' "Warning: A newer Command Line Tools release is available." "" "Warning: You have unlinked kegs.")"
eq "harmless doctor notes are dropped" "" "$(printf '%s\n' "$harmless_doc" | brew_doctor_filter)"
serious_doc="$(printf '%s\n' "Warning: /opt/homebrew/bin is not in your PATH." "A shell restart may be needed.")"
has "serious doctor note is kept" "not in your PATH" "$(printf '%s\n' "$serious_doc" | brew_doctor_filter)"

# --- second run is a no-op ---
new_case idem
cp "$tmp/full.Brewfile" "$brewfile"
run_case
eq "first install exits 0" 0 "$rc"
has "first install reports success" "All Brewfile entries are installed." "$out"
miss "first install does not retry" "Retrying" "$out"
installed_snapshot="$(sort "$STUB_DIR/installed")"
mut_before="$(wc -l < "$STUB_DIR/mutations" | tr -d ' ')"
eq "first install mutated every entry" 4 "$mut_before"
run_case
eq "second install exits 0" 0 "$rc"
has "second install reports success" "All Brewfile entries are installed." "$out"
miss "second install does not retry" "Retrying" "$out"
eq "second install does not change what is installed" "$installed_snapshot" "$(sort "$STUB_DIR/installed")"
mut_after="$(wc -l < "$STUB_DIR/mutations" | tr -d ' ')"
eq "second install performs no installs" "$mut_before" "$mut_after"
eq "second install does not retry a cask" 0 "$(count_line "install --cask --adopt raycast" "$STUB_DIR/commands")"
has "casks are adopted via HOMEBREW_CASK_OPTS" "OPTS --adopt" "$(cat "$STUB_DIR/commands")"

# --- one failing cask: others install, exactly one retry, summary names it ---
new_case failone
cp "$tmp/full.Brewfile" "$brewfile"
printf '%s\n' raycast > "$STUB_DIR/fail-bundle"
printf '%s\n' raycast > "$STUB_DIR/fail-install"
run_case
eq "failing cask exits 1" 1 "$rc"
has "summary names the cask" "raycast (cask)" "$out"
has "summary has the Homebrew reason" "already an App" "$out"
has "summary has the fix command" "Fix: brew install --cask --adopt raycast" "$out"
miss "generic some-entries message is not used" "some Brewfile entries did not install" "$out"
eq "raycast is retried once" 1 "$(count_line "install --cask --adopt raycast" "$STUB_DIR/commands")"
eq "hammerspoon is not retried" 0 "$(count_line "install --cask --adopt hammerspoon" "$STUB_DIR/commands")"
eq "jq is not retried" 0 "$(count_line "install jq" "$STUB_DIR/commands")"
check "jq was installed" grep -qxF "formula jq" "$STUB_DIR/installed"
check "hammerspoon was installed" grep -qxF "cask hammerspoon" "$STUB_DIR/installed"
check "karabiner-elements was installed" grep -qxF "cask karabiner-elements" "$STUB_DIR/installed"
if grep -qxF "cask raycast" "$STUB_DIR/installed"; then
  fail=$((fail + 1))
  echo "FAIL: raycast was recorded as installed"
else
  pass=$((pass + 1))
fi
has "non-interactive run warns about the pkg cask" "not a terminal" "$out"
has "warning names karabiner-elements" "karabiner-elements" "$out"
check "sudo was not called without a terminal" test ! -f "$STUB_DIR/sudo.log"

# --- retry then success: still exactly one retry ---
new_case retryok
cp "$tmp/full.Brewfile" "$brewfile"
printf '%s\n' raycast > "$STUB_DIR/fail-bundle"
run_case
eq "a retry that succeeds exits 0" 0 "$rc"
has "retry is announced" "Retrying 1 missing entry" "$out"
has "retry success is reported" "All Brewfile entries are installed." "$out"
eq "successful retry happens once" 1 "$(count_line "install --cask --adopt raycast" "$STUB_DIR/commands")"
check "retry installed raycast" grep -qxF "cask raycast" "$STUB_DIR/installed"

# --- preflight: network, command line tools, disk ---
new_case net
cp "$tmp/full.Brewfile" "$brewfile"
printf '%s\n' github.com formulae.brew.sh > "$STUB_DIR/fail-hosts"
run_case
eq "offline install exits 2" 2 "$rc"
has "offline message names github.com" "github.com" "$out"
has "offline message names formulae.brew.sh" "formulae.brew.sh" "$out"
has "offline message says to check the connection" "Check the internet connection" "$out"
eq "offline install does not run brew" 0 "$(count_line "bundle --file $brewfile" "$STUB_DIR/commands")"

new_case clt
cp "$tmp/full.Brewfile" "$brewfile"
touch "$STUB_DIR/no-clt"
run_case
eq "missing Command Line Tools exits 2" 2 "$rc"
has "missing tools names the installer" "xcode-select --install" "$out"
has "missing tools says Homebrew needs them" "Homebrew needs them" "$out"
eq "missing tools does not install casks" 0 "$(count_line "bundle --file $brewfile" "$STUB_DIR/commands")"

new_case disk
cp "$tmp/full.Brewfile" "$brewfile"
printf '%s\n' 1000 > "$STUB_DIR/df-avail"
run_case
eq "low disk exits 2" 2 "$rc"
has "low disk says how much is needed" "at least 10 GB" "$out"
has "low disk is plain about free space" "Not enough free disk space" "$out"
eq "low disk does not install" 0 "$(count_line "bundle --file $brewfile" "$STUB_DIR/commands")"

# --- doctor: harmless is quiet, serious is a warning, neither fails the install ---
new_case doctor_ok
cp "$tmp/full.Brewfile" "$brewfile"
printf '%s\n' harmless > "$STUB_DIR/doctor"
run_case
eq "harmless doctor still exits 0" 0 "$rc"
miss "harmless doctor text is not shown" "newer Command Line Tools" "$out"
check "harmless doctor still installed jq" grep -qxF "formula jq" "$STUB_DIR/installed"

new_case doctor_bad
cp "$tmp/full.Brewfile" "$brewfile"
printf '%s\n' serious > "$STUB_DIR/doctor"
run_case
eq "serious doctor still exits 0" 0 "$rc"
has "serious doctor is shown" "not in your PATH" "$out"
has "serious doctor does not stop setup" "Setup will continue" "$out"
check "serious doctor still installed hammerspoon" grep -qxF "cask hammerspoon" "$STUB_DIR/installed"

# --- check output we cannot parse is still reported ---
new_case garbage
cp "$tmp/full.Brewfile" "$brewfile"
touch "$STUB_DIR/check-garbage"
run_case
eq "unparsed check exits 1" 1 "$rc"
has "unparsed check says so" "no missing formula or cask could be named" "$out"
has "unparsed check gives the command" "brew bundle check --no-upgrade --verbose --file" "$out"
eq "unparsed check does not retry" 0 "$(count_line "install --cask --adopt raycast" "$STUB_DIR/commands")"

# --- no --adopt on an old Homebrew ---
new_case noadopt
cp "$tmp/full.Brewfile" "$brewfile"
touch "$STUB_DIR/no-adopt"
printf '%s\n' raycast > "$STUB_DIR/fail-bundle"
printf '%s\n' raycast > "$STUB_DIR/fail-install"
run_case
eq "install without --adopt still finishes the report" 1 "$rc"
has "missing --adopt is explained" "no --adopt flag" "$out"
eq "retry omits --adopt" 1 "$(count_line "install --cask raycast" "$STUB_DIR/commands")"
eq "retry does not pass --adopt" 0 "$(count_line "install --cask --adopt raycast" "$STUB_DIR/commands")"
has "fix command omits --adopt" "Fix: brew install --cask raycast" "$out"
miss "OPTS do not force --adopt" "OPTS --adopt" "$(cat "$STUB_DIR/commands")"

# --- a caller's --force is not combined with --adopt ---
new_case forceopts
cp "$tmp/full.Brewfile" "$brewfile"
export HOMEBREW_CASK_OPTS="--force"
run_case
unset HOMEBREW_CASK_OPTS
eq "install with --force still exits 0" 0 "$rc"
has "force opts explain why adopt is skipped" "cannot be combined with --adopt" "$out"
miss "force opts are not given --adopt as well" "OPTS --force --adopt" "$(cat "$STUB_DIR/commands")"
has "force opts are left as the caller set them" "OPTS --force" "$(cat "$STUB_DIR/commands")"

# --- formula only: no sudo warning ---
new_case formula
printf '%s\n' 'brew "jq"' > "$brewfile"
run_case
eq "formula-only install exits 0" 0 "$rc"
miss "formula-only install does not talk about a password" "admin password" "$out"
check "sudo was not used for a formula" test ! -f "$STUB_DIR/sudo.log"

# --- interactive sudo once, and the keepalive dies with the script ---
new_case sudo
cp "$tmp/full.Brewfile" "$brewfile"
DOTFILES_INTERACTIVE=1
DOTFILES_SUDO_KEEPALIVE_SECS=1
run_case
eq "interactive install exits 0" 0 "$rc"
has "interactive install names the pkg cask" "karabiner-elements" "$out"
eq "sudo -v is asked once" 1 "$(count_line "-v" "$STUB_DIR/sudo.log")"
sudo_before="$(wc -l < "$STUB_DIR/sudo.log" | tr -d ' ')"
sleep 2
sudo_after="$(wc -l < "$STUB_DIR/sudo.log" | tr -d ' ')"
eq "sudo keepalive is not still running" "$sudo_before" "$sudo_after"

# --- no Homebrew, and a missing Brewfile ---
new_case nobrew
cp "$tmp/full.Brewfile" "$brewfile"
rm -f "$case_bin/brew"
out="$(
  HOME="$case_home" \
    PATH="$case_bin:/usr/bin:/bin" \
    STUB_DIR="$STUB_DIR" \
    DOTFILES_INTERACTIVE=0 \
    DOTFILES_BREW_RETRY_DELAY=0 \
    "$SCRIPT" --file "$brewfile" 2>&1
)"
rc=$?
eq "missing Homebrew exits 2" 2 "$rc"
has "missing Homebrew is explained" "Homebrew is not installed" "$out"

help_out="$(PATH="/usr/bin:/bin" "$SCRIPT" --help 2>&1)"
help_rc=$?
eq "--help exits 0" 0 "$help_rc"
has "--help mentions the retry" "retry that entry" "$help_out"

missing_out="$(PATH="/usr/bin:/bin" "$SCRIPT" --file "$tmp/no-such-Brewfile" 2>&1)"
missing_rc=$?
eq "missing Brewfile exits 2" 2 "$missing_rc"
has "missing Brewfile is named" "Brewfile not found" "$missing_out"

rootbin="$tmp/rootbin"
mkdir -p "$rootbin"
cat > "$rootbin/id" <<'EOF'
#!/bin/sh
echo 0
EOF
chmod +x "$rootbin/id"
root_out="$(PATH="$rootbin:/usr/bin:/bin" "$SCRIPT" --help 2>&1)"
root_rc=$?
eq "helper refuses root" 1 "$root_rc"
has "helper root message" "refusing to run as root" "$root_out"

printf 'brew-bundle tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
