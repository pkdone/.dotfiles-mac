# shellcheck shell=bash
#
# brew-bundle.sh — install a Brewfile without letting one entry derail the run.
# Sourced by scripts/brew-bundle-install.sh. Not executed directly.
#
# brew bundle installs every entry and returns non-zero if any one failed.
# This then retries only the entries that are still missing, once, and prints
# each failure with the Homebrew error (when there is one) and the command
# that installs that entry. Casks use --adopt when this Homebrew supports it.

_brew_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=join-names.sh disable=SC1091
. "$_brew_lib_dir/join-names.sh"
# shellcheck source=dotfiles-log.sh disable=SC1091
. "$_brew_lib_dir/dotfiles-log.sh"

# 10 GiB in df -k blocks. Below this, an install is likely to fail halfway.
BREW_MIN_FREE_KB=10485760

# with_timeout SECS CMD... — macOS has no timeout(1). perl's alarm survives exec.
with_timeout() {
  local secs="$1"
  shift
  if command -v perl >/dev/null 2>&1; then
    perl -e '$t = shift @ARGV; alarm $t; exec { $ARGV[0] } @ARGV or exit 127' "$secs" "$@"
  else
    "$@"
  fi
}

# Print "formula NAME" / "cask NAME" for verbose lines that still need an install.
# "needs to be updated" is not missing; brewsync upgrades those separately.
brew_missing_from_verbose() {
  local text="$1" line name
  # Pipe, not an unquoted heredoc: brew's text must not be expanded as shell.
  printf '%s\n' "$text" | while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
      "→ "*|"↳ "*|"-> "*) line="${line#* }" ;;
    esac
    case "$line" in
      "Formula "*" needs to be installed"*)
        name="${line#Formula }"
        name="${name%% needs to be *}"
        printf 'formula %s\n' "$name"
        ;;
      "Cask "*" needs to be installed"*)
        name="${line#Cask }"
        name="${name%% needs to be *}"
        printf 'cask %s\n' "$name"
        ;;
    esac
  done
}

# Fallback when `brew bundle check --verbose` fails but its wording is unfamiliar:
# Brewfile names minus `brew list`.
brew_missing_by_list() {
  local file="$1" kind flag wanted installed name short
  for kind in formula cask; do
    if [ "$kind" = "formula" ]; then
      flag="--formula"
    else
      flag="--cask"
    fi
    wanted="$(brew bundle list "$flag" --file "$file" 2>/dev/null || true)"
    installed="$(brew list "$flag" 2>/dev/null || true)"
    printf '%s\n' "$wanted" | while IFS= read -r name || [ -n "$name" ]; do
      [ -n "$name" ] || continue
      case "$name" in
        '==>'*|\#*) continue ;;
      esac
      short="${name##*/}"
      if ! printf '%s\n' "$installed" | grep -qxF "$short"; then
        printf '%s %s\n' "$kind" "$short"
      fi
    done
  done
}

# brew_collect_missing FILE DEST
# Writes missing "kind name" lines to DEST. Return 0 when satisfied, 1 when
# something is missing, 3 when the check failed and no formula or cask could
# be named. The check text is left in BREW_LAST_CHECK (same shell, not a
# command substitution).
brew_collect_missing() {
  local file="$1" dest="$2" verbose rc=0 parsed listed
  BREW_LAST_CHECK=""
  : > "$dest"
  verbose="$(brew bundle check --no-upgrade --file "$file" --verbose 2>&1)" || rc=$?
  BREW_LAST_CHECK="$verbose"
  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  parsed="$(brew_missing_from_verbose "$verbose")"
  if [ -n "$parsed" ]; then
    printf '%s\n' "$parsed" > "$dest"
    return 1
  fi
  listed="$(brew_missing_by_list "$file")"
  if [ -n "$listed" ]; then
    printf '%s\n' "$listed" > "$dest"
    return 1
  fi
  return 3
}

# Drop harmless `brew doctor` warnings. Print serious ones and anything we do
# not recognise, so a new serious note is not hidden. Never called for its
# exit status; the caller does not fail the install on doctor output.
brew_doctor_filter() {
  awk '
    function flush() {
      if (n > 0 && !drop) {
        i = 1
        while (i <= n) {
          print lines[i]
          i++
        }
      }
      n = 0
      drop = 0
      seen_serious = 0
      seen_harmless = 0
    }
    function note(s) {
      if (s ~ /newer Command Line Tools/ || s ~ /uncommitted modifications/ || s ~ /deprecated or disabled/ || s ~ /have the same name/ || s ~ /do not provide support/ || s ~ /unlinked kegs/ || s ~ /pre-release version/)
        seen_harmless = 1
      if (s ~ /Error:/ || s ~ /not writable/ || s ~ /not in your PATH/ || s ~ /was not found/ || s ~ /suspicious/ || s ~ /[Bb]roken/ || s ~ /does not exist/ || s ~ /[Pp]ermission denied/ || s ~ /failed/)
        seen_serious = 1
    }
    /^Warning:/ || /^Error:/ {
      if (inb) drop = seen_harmless && !seen_serious
      flush()
      inb = 1
      n = 1
      lines[1] = $0
      seen_serious = 0
      seen_harmless = 0
      note($0)
      next
    }
    inb && $0 ~ /^$/ {
      drop = seen_harmless && !seen_serious
      flush()
      inb = 0
      next
    }
    inb {
      n++
      lines[n] = $0
      note($0)
      next
    }
    END {
      if (inb) {
        drop = seen_harmless && !seen_serious
        flush()
      }
    }
  '
}

brew_host_of() {
  local url="$1"
  url="${url#https://}"
  url="${url#http://}"
  printf '%s\n' "${url%%/*}"
}

brew_preflight_network() {
  local url err failed="" hosts line
  for url in https://github.com https://formulae.brew.sh; do
    err="$(curl -fsS --max-time 10 -o /dev/null "$url" 2>&1)" || {
      failed="${failed}$(brew_host_of "$url")"$'\n'
      if [ -n "$err" ]; then
        failed="${failed}  ${err}"$'\n'
      fi
    }
  done
  if [ -z "$failed" ]; then
    return 0
  fi
  hosts="$(printf '%s\n' "$failed" | grep -v '^  ' | grep -v '^$' | join_and || true)"
  echo "Can't reach ${hosts}, which Homebrew needs to download packages."
  printf '%s\n' "$failed" | grep '^  ' || true
  echo "Check the internet connection, then run this setup again."
  return 1
}

brew_preflight_clt() {
  local reply
  if xcode-select -p >/dev/null 2>&1; then
    return 0
  fi
  echo "The Xcode Command Line Tools are not installed. Homebrew needs them."
  echo "Install them with: xcode-select --install"
  if dotfiles_is_interactive; then
    printf 'Run xcode-select --install now? [y/N] '
    read -r reply || reply=""
    case "$reply" in
      y|Y|yes|YES) xcode-select --install || true ;;
    esac
  fi
  echo "When the Command Line Tools are installed, run this setup again."
  return 1
}

brew_disk_volume() {
  if df -k /System/Volumes/Data >/dev/null 2>&1; then
    printf '%s\n' /System/Volumes/Data
    return 0
  fi
  if df -k "$HOME" >/dev/null 2>&1; then
    printf '%s\n' "$HOME"
    return 0
  fi
  printf '%s\n' /
}

brew_free_kb() {
  local vol="$1" kb
  kb="$(df -k "$vol" 2>/dev/null | awk 'NR==2 { print $4 }')" || true
  case "$kb" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$kb"
}

brew_preflight_disk() {
  local vol kb free_gb
  vol="$(brew_disk_volume)"
  if ! kb="$(brew_free_kb "$vol")"; then
    echo "Couldn't read free disk space on $vol, so setup is stopping rather than filling the disk."
    return 1
  fi
  if [ "$kb" -lt "$BREW_MIN_FREE_KB" ]; then
    free_gb=$((kb / 1024 / 1024))
    echo "Not enough free disk space: ${free_gb} GB free on ${vol}, and setup needs at least 10 GB."
    echo "Free some space, then run this setup again."
    return 1
  fi
}

brew_preflight_doctor() {
  local doctor_rc=0 doctor_out serious
  doctor_out="$(with_timeout 60 brew doctor 2>&1)" || doctor_rc=$?
  if [ "$doctor_rc" -eq 142 ] || [ "$doctor_rc" -eq 124 ]; then
    echo "⚠️  brew doctor did not finish in time. Setup will continue."
    return 0
  fi
  if [ "$doctor_rc" -eq 0 ]; then
    return 0
  fi
  serious="$(printf '%s\n' "$doctor_out" | brew_doctor_filter)"
  if [ -n "$serious" ]; then
    echo "⚠️  Homebrew doctor reported a problem. Setup will continue."
    printf '%s\n' "$serious" | sed 's/^/    /'
  fi
}

brew_ensure_homebrew() {
  local install_hb="$1"
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi
  if [ "$install_hb" != 1 ]; then
    echo "Homebrew is not installed, so there is nothing to install yet."
    echo "The bootstrap block in the README installs Homebrew. Then run this again."
    return 1
  fi
  echo "Homebrew is not on this Mac. Installing it now..."
  if ! dotfiles_is_interactive; then
    export NONINTERACTIVE=1
  fi
  if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    echo "The Homebrew installer failed. Fix the error above, then run this again."
    return 1
  fi
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  hash -r || true
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew still is not on PATH after the installer. Open a new terminal and run this again."
    return 1
  fi
}

brew_adopt_enable() {
  local help
  BREW_ADOPT=0
  # --adopt cannot be combined with --force. Leave a caller's --force alone.
  case " ${HOMEBREW_CASK_OPTS:-} " in
    *" --force "*|*" -f "*)
      echo "⚠️  HOMEBREW_CASK_OPTS includes --force, which cannot be combined with --adopt. Existing apps in /Applications will not be adopted."
      return 0
      ;;
  esac
  help="$(brew install --cask --help 2>&1 || true)"
  case "$help" in
    *--adopt*)
      BREW_ADOPT=1
      case " ${HOMEBREW_CASK_OPTS:-} " in
        *" --adopt "*) ;;
        *)
          HOMEBREW_CASK_OPTS="${HOMEBREW_CASK_OPTS:+$HOMEBREW_CASK_OPTS }--adopt"
          export HOMEBREW_CASK_OPTS
          ;;
      esac
      ;;
    *)
      echo "⚠️  This Homebrew has no --adopt flag. An app already in /Applications may fail until Homebrew is updated."
      ;;
  esac
}

# Print cask tokens whose artifacts need sudo (pkg installers, or an installer
# script marked sudo). Falls back to karabiner-elements when brew info or
# python3 cannot be read; that cask is the pkg installer this Brewfile ships.
brew_pkg_casks() {
  local file="$1" casks json parsed name
  local names=()
  casks="$(sed -nE 's/^cask "([^"]+)".*/\1/p' "$file")"
  if [ -z "$casks" ]; then
    return 0
  fi
  while IFS= read -r name || [ -n "$name" ]; do
    [ -n "$name" ] || continue
    names+=("$name")
  done <<EOF
$casks
EOF
  if ! json="$(brew info --cask --json=v2 "${names[@]}" 2>/dev/null)"; then
    printf '%s\n' "$casks" | grep -x 'karabiner-elements' || true
    return 0
  fi
  if ! parsed="$(printf '%s' "$json" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except Exception:
    sys.exit(1)
if isinstance(data, dict):
    casks = data.get("casks") or []
elif isinstance(data, list):
    casks = data
else:
    casks = []

def needs_sudo(art):
    if not isinstance(art, dict):
        return False
    if "pkg" in art:
        return True
    inst = art.get("installer")
    if isinstance(inst, dict):
        script = inst.get("script") if isinstance(inst.get("script"), dict) else {}
        return bool(inst.get("sudo") or script.get("sudo"))
    if isinstance(inst, list):
        for item in inst:
            if not isinstance(item, dict):
                continue
            script = item.get("script") if isinstance(item.get("script"), dict) else {}
            if item.get("sudo") or script.get("sudo"):
                return True
    return False

for c in casks:
    if not isinstance(c, dict):
        continue
    token = c.get("token") or ""
    if not token:
        full = c.get("full_token") or ""
        token = full.rsplit("/", 1)[-1]
    if token and any(needs_sudo(a) for a in (c.get("artifacts") or [])):
        print(token)
')"; then
    printf '%s\n' "$casks" | grep -x 'karabiner-elements' || true
    return 0
  fi
  printf '%s\n' "$parsed"
}

brew_sudo_keepalive_stop() {
  if [ -n "${BREW_SUDO_PID:-}" ]; then
    kill "$BREW_SUDO_PID" 2>/dev/null || true
    wait "$BREW_SUDO_PID" 2>/dev/null || true
    BREW_SUDO_PID=""
  fi
}

# One background process refreshes the sudo timestamp. It is killed on EXIT
# so a finished setup does not leave a password helper running.
brew_sudo_keepalive_start() {
  local interval
  interval="${DOTFILES_SUDO_KEEPALIVE_SECS:-60}"
  case "$interval" in
    ''|*[!0-9]*|0) interval=60 ;;
  esac
  if [ -z "${BREW_TMP:-}" ] || [ ! -d "$BREW_TMP" ]; then
    return 0
  fi
  cat > "$BREW_TMP/sudo-keepalive.sh" <<'EOF'
#!/bin/bash
set -uo pipefail
parent="$1"
interval="$2"
trap 'exit 0' TERM INT
while true; do
  sudo -n true || exit 0
  sleep "$interval" &
  sp=$!
  trap 'kill "$sp" 2>/dev/null || true; exit 0' TERM INT
  wait "$sp" || true
  kill -0 "$parent" 2>/dev/null || exit 0
done
EOF
  bash "$BREW_TMP/sudo-keepalive.sh" "$$" "$interval" >/dev/null 2>&1 &
  BREW_SUDO_PID=$!
}

brew_prepare_sudo() {
  local file="$1" pkg names
  pkg="$(brew_pkg_casks "$file")"
  if [ -z "$pkg" ]; then
    return 0
  fi
  names="$(printf '%s\n' "$pkg" | join_and)"
  if dotfiles_is_interactive; then
    echo "Some installers need an admin password: ${names}."
    echo "Asking once now so those installs are not stopped halfway through."
    if sudo -v; then
      brew_sudo_keepalive_start
    else
      echo "⚠️  No admin password. These may fail: ${names}."
    fi
  else
    echo "⚠️  This is not a terminal, so setup is not asking for an admin password."
    echo "    These package installers may fail: ${names}."
    echo "    Run the setup in a terminal, or install each one with: brew install --cask <name>"
  fi
}

brew_fix_command() {
  local kind="$1" name="$2"
  if [ "$kind" = "cask" ]; then
    if [ "${BREW_ADOPT:-0}" = 1 ]; then
      printf 'brew install --cask --adopt %s\n' "$name"
    else
      printf 'brew install --cask %s\n' "$name"
    fi
  else
    printf 'brew install %s\n' "$name"
  fi
}

# The last Homebrew error line in a capture, trimmed to one line.
brew_one_line_reason() {
  local file="$1" line reason=""
  [ -r "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *"Error:"*|*"error:"*|*"already an App"*|*"Failed"*|*"failed to"*|*"curl:"*|*"Permission denied"*|*"not writable"*)
        reason="$line"
        ;;
    esac
  done < "$file"
  if [ -z "$reason" ]; then
    reason="$(awk 'NF { line = $0 } END { print line }' "$file")"
  fi
  reason="${reason#"${reason%%[![:space:]]*}"}"
  reason="${reason%"${reason##*[![:space:]]}"}"
  if [ "${#reason}" -gt 240 ]; then
    reason="${reason:0:237}..."
  fi
  if [ -n "$reason" ]; then
    printf '%s\n' "$reason"
  fi
}

brew_report_missing() {
  local missing="$1" bundle_log="$2" retry_dir="$3" kind name reason fix n
  n="$(printf '%s\n' "$missing" | grep -c . || true)"
  if [ "$n" -eq 1 ]; then
    echo "⚠️  1 Brewfile entry is still missing:"
  else
    echo "⚠️  ${n} Brewfile entries are still missing:"
  fi
  printf '%s\n' "$missing" | while read -r kind name || [ -n "${kind:-}" ]; do
    [ -n "${kind:-}" ] || continue
    [ -n "${name:-}" ] || continue
    reason="$(brew_one_line_reason "$retry_dir/$name.out")"
    if [ -z "$reason" ]; then
      reason="$(brew_one_line_reason "$bundle_log")"
    fi
    if [ -z "$reason" ]; then
      reason="Homebrew did not install it, and did not say why."
    fi
    fix="$(brew_fix_command "$kind" "$name")"
    echo "  ${name} (${kind})"
    echo "    Reason: ${reason}"
    echo "    Fix: ${fix}"
  done
}

# Stream CMD to the terminal and append it to DEST. Sets BREW_RUN_RC.
# pipefail is restored before return. The caller keeps set -e.
brew_run_capture() {
  local dest="$1"
  shift
  set +e
  set +o pipefail
  "$@" 2>&1 | tee -a "$dest"
  BREW_RUN_RC=${PIPESTATUS[0]}
  set -o pipefail
  set -e
  # A failed install must not abort the Brewfile run. Callers read
  # BREW_RUN_RC when they care; the retry and the summary still happen.
  if [ "$BREW_RUN_RC" -ne 0 ]; then
    return 0
  fi
}

brew_retry_one() {
  local kind="$1" name="$2" one_log
  one_log="$BREW_TMP/retries/$name.out"
  : > "$one_log"
  if [ "$kind" = "cask" ] && [ "${BREW_ADOPT:-0}" = 1 ]; then
    brew_run_capture "$one_log" brew install --cask --adopt "$name"
  elif [ "$kind" = "cask" ]; then
    brew_run_capture "$one_log" brew install --cask "$name"
  else
    brew_run_capture "$one_log" brew install "$name"
  fi
}

brew_report_unparsed() {
  local file="$1"
  echo "Homebrew says the Brewfile is not satisfied, but no missing formula or cask could be named."
  if [ -n "${BREW_LAST_CHECK:-}" ]; then
    printf '%s\n' "$BREW_LAST_CHECK" | sed 's/^/  /'
  fi
  echo "Fix: brew bundle check --no-upgrade --verbose --file \"$file\""
}

brew_bundle_usage() {
  cat <<'EOF'
Usage: scripts/brew-bundle-install.sh [--install-homebrew] [--file BREWFILE]
  Install every entry in the Brewfile. If one entry fails, retry that entry
  once and keep going. Then name anything still missing, with the Homebrew
  error when there is one, and the command to install it.
  Casks are installed with --adopt when this Homebrew supports it, so an app
  already in /Applications is taken over.
  --install-homebrew   Install Homebrew first when brew is not on PATH.
  --file PATH          Brewfile. Default: ~/.dotfiles-mac/Brewfile.
  -h, --help           Show this help.
EOF
}

brew_on_exit() {
  brew_sudo_keepalive_stop
  if [ -n "${BREW_TMP:-}" ] && [ -d "$BREW_TMP" ]; then
    case "$BREW_TMP" in
      /tmp/*|/var/folders/*|/private/var/folders/*|"${TMPDIR:-/tmp}"/*)
        rm -rf "$BREW_TMP"
        ;;
    esac
  fi
}

# Install FILE. Return 0 when every entry is installed, 1 when some remain
# (they have been named), 2 when a preflight check failed or the arguments
# are wrong. One failed entry does not skip the others.
brew_bundle_main() {
  local file="$HOME/.dotfiles-mac/Brewfile" install_hb=0
  local missing collect_rc delay n bundle_log kind name
  while [ $# -gt 0 ]; do
    case "$1" in
      --file)
        if [ $# -lt 2 ]; then
          echo "brew-bundle-install.sh: --file needs a path" >&2
          return 2
        fi
        file="$2"
        shift 2
        ;;
      --install-homebrew) install_hb=1; shift ;;
      -h|--help) brew_bundle_usage; return 0 ;;
      *)
        echo "Unknown argument: $1 (try --help)" >&2
        return 2
        ;;
    esac
  done
  if [ ! -r "$file" ]; then
    echo "Brewfile not found: $file" >&2
    return 2
  fi

  case "${DOTFILES_BREW_RETRY_DELAY:-2}" in
    ''|*[!0-9]*) DOTFILES_BREW_RETRY_DELAY=2 ;;
  esac
  delay="$DOTFILES_BREW_RETRY_DELAY"

  # Homebrew 7 asks before install. This script answers for itself only.
  export HOMEBREW_NO_ASK=1

  if ! brew_preflight_network; then
    return 2
  fi
  if ! brew_preflight_clt; then
    return 2
  fi
  if ! brew_preflight_disk; then
    return 2
  fi
  if ! brew_ensure_homebrew "$install_hb"; then
    return 2
  fi
  brew_preflight_doctor

  BREW_TMP="$(mktemp -d)"
  mkdir -p "$BREW_TMP/retries"
  bundle_log="$BREW_TMP/bundle.out"
  : > "$bundle_log"

  brew_adopt_enable
  brew_prepare_sudo "$file"

  brew_run_capture "$bundle_log" brew bundle --file "$file"

  collect_rc=0
  brew_collect_missing "$file" "$BREW_TMP/missing" || collect_rc=$?
  missing="$(cat "$BREW_TMP/missing")"
  if [ "$collect_rc" -eq 0 ]; then
    echo "All Brewfile entries are installed."
    return 0
  fi
  if [ "$collect_rc" -eq 3 ]; then
    brew_report_unparsed "$file"
    return 1
  fi

  n="$(printf '%s\n' "$missing" | grep -c . || true)"
  if [ "$n" -eq 1 ]; then
    echo "Retrying 1 missing entry..."
  else
    echo "Retrying ${n} missing entries..."
  fi
  if [ "$delay" -gt 0 ]; then
    echo "Waiting ${delay}s before the retry..."
    sleep "$delay"
  fi

  # Default IFS splits "cask name". An empty IFS would leave name unset.
  while read -r kind name || [ -n "${kind:-}" ]; do
    [ -n "${kind:-}" ] || continue
    [ -n "${name:-}" ] || continue
    brew_retry_one "$kind" "$name"
  done < "$BREW_TMP/missing"

  collect_rc=0
  brew_collect_missing "$file" "$BREW_TMP/missing" || collect_rc=$?
  missing="$(cat "$BREW_TMP/missing")"
  if [ "$collect_rc" -eq 0 ]; then
    echo "All Brewfile entries are installed."
    return 0
  fi
  if [ "$collect_rc" -eq 3 ]; then
    brew_report_unparsed "$file"
    return 1
  fi
  brew_report_missing "$missing" "$bundle_log" "$BREW_TMP/retries"
  return 1
}
