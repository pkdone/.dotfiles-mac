#!/usr/bin/env bash
#
# check.sh — read-only verifier. Reports drift between this machine and the repo's
# desired state WITHOUT changing anything. Exits non-zero if any drift is found, so
# it's usable in a pre-push hook or CI later.
#
# Sections: symlinks, Homebrew (Brewfile), macOS defaults, Dock, login shell, hostname.
# Reuses lib/macos-defaults.list, lib/dock-apps.list and lib/defaults-lib.sh so the
# verify path uses the exact same data and comparison semantics as the apply path
# (macos.sh / dock.sh) and the two can never drift.
#
# Flags:
#   --no-color   Disable ANSI colour (also honours the NO_COLOR env var).
#   -h, --help   Show usage.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_HOST="pdone-mac"   # mirrors the hostname block in README (kept manual; needs sudo)
NO_COLOR_OPT=0

for arg in "$@"; do
  case "$arg" in
    --no-color) NO_COLOR_OPT=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: check.sh [--no-color]
  Read-only. Reports drift between this machine and the repo; writes nothing.
  Exit status: 0 = everything matches, 1 = drift found.
  --no-color   Disable ANSI colour (also honours the NO_COLOR env var).
  -h, --help   Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# ---- logging (colour only on a tty) -------------------------------------
if [ -t 1 ] && [ "$NO_COLOR_OPT" != 1 ] && [ -z "${NO_COLOR+x}" ]; then
  C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WARN=$'\033[33m'; C_HDR=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_BAD=''; C_WARN=''; C_HDR=''; C_OFF=''
fi

CHECKED=0; OKS=0; DRIFT=0; WARN=0
pass() { OKS=$((OKS + 1));    printf '  %sok%s    %s\n'  "$C_OK"   "$C_OFF" "$1"; }
bad()  { DRIFT=$((DRIFT + 1)); printf '  %sDRIFT%s %s\n' "$C_BAD"  "$C_OFF" "$1"; }
warn() { WARN=$((WARN + 1));   printf '  %swarn%s  %s\n'  "$C_WARN" "$C_OFF" "$1"; }
hdr()  { printf '\n%s%s%s\n' "$C_HDR" "$1" "$C_OFF"; }

# Value-comparison helpers shared with macos.sh (same semantics, single source).
# shellcheck source=lib/defaults-lib.sh disable=SC1091
. "$DOTDIR/lib/defaults-lib.sh"

# ---- 1. symlinks --------------------------------------------------------
hdr "Symlinks"
check_link() {  # target  expected-source
  local target="$1" expected="$2"
  CHECKED=$((CHECKED + 1))
  if [ ! -L "$target" ]; then
    if [ -e "$target" ]; then
      bad "${target/#$HOME/~} — exists but is not a symlink"
    else
      bad "${target/#$HOME/~} — missing"
    fi
    return 0
  fi
  local actual; actual="$(readlink "$target")"
  if [ "$actual" != "$expected" ]; then
    bad "${target/#$HOME/~} -> $actual (expected $expected)"
  elif [ ! -e "$target" ]; then
    bad "${target/#$HOME/~} -> $expected (broken: source missing)"
  else
    pass "${target/#$HOME/~} -> repo"
  fi
}

check_link "$HOME/.config/ghostty/config"   "$DOTDIR/ghostty/config"
check_link "$HOME/.config/fish/config.fish" "$DOTDIR/fish/config.fish"
for f in "$DOTDIR"/fish/functions/*.fish; do
  check_link "$HOME/.config/fish/functions/$(basename "$f")" "$f"
done
check_link "$HOME/.config/mise/config.toml" "$DOTDIR/mise/config.toml"
check_link "$HOME/.gitconfig"               "$DOTDIR/gitconfig"

# ---- 2. Homebrew --------------------------------------------------------
hdr "Homebrew (Brewfile)"
CHECKED=$((CHECKED + 1))
if ! command -v brew >/dev/null 2>&1; then
  warn "brew not installed — skipping Brewfile check"
elif brew bundle check --file "$DOTDIR/Brewfile" >/dev/null 2>&1; then
  pass "Brewfile satisfied (all formulae, casks, mas apps installed)"
else
  bad "Brewfile not satisfied — missing:"
  brew bundle check --file "$DOTDIR/Brewfile" --verbose 2>&1 | sed 's/^/          /' || true
fi

# ---- 3. macOS defaults --------------------------------------------------
hdr "macOS defaults"
while IFS='|' read -r domain key etype desired restart area label disp; do
  case "$domain" in ''|'#'*) continue ;; esac
  CHECKED=$((CHECKED + 1))
  desired="${desired//@HOME@/$HOME}"
  want_token="$(type_token "$etype")"
  if cur="$(defaults read "$domain" "$key" 2>/dev/null)"; then
    curtype="$(defaults read-type "$domain" "$key" 2>/dev/null || true)"
    curtype="${curtype##* }"
    if [ "$curtype" != "$want_token" ]; then
      bad "$domain $key — type mismatch (expected $want_token, found ${curtype:-none})"
    elif values_equal "$etype" "$cur" "$desired"; then
      pass "$domain $key = $cur"
    else
      bad "$domain $key = $cur (expected $desired)"
    fi
  else
    bad "$domain $key — not set (expected $desired)"
  fi
done < "$DOTDIR/lib/macos-defaults.list"

# ---- 4. Dock ------------------------------------------------------------
hdr "Dock"
if ! command -v dockutil >/dev/null 2>&1; then
  warn "dockutil not installed — skipping Dock check"
else
  # dockutil --list is tab-separated: label \t file://URL \t section \t plist \t bundle-id
  # We compare by PATH (mirrors how dock.sh pins apps). Only %20 needs decoding for our
  # paths; WhatsApp's invisible U+200E mark stays encoded and is absorbed by the * glob.
  url_to_path() { local p="${1#file://}"; p="${p%/}"; printf '%s' "${p//%20/ }"; }

  expected_paths=(); expected_names=()
  while IFS='|' read -r name path; do
    case "$name" in ''|'#'*) continue ;; esac
    expected_names+=("$name"); expected_paths+=("${path/@HOME@/$HOME}")
  done < "$DOTDIR/lib/dock-apps.list"

  actual_paths=()
  while IFS=$'\t' read -r _label url _rest; do
    [ -z "$url" ] && continue
    actual_paths+=("$(url_to_path "$url")")
  done < <(dockutil --list)

  CHECKED=$((CHECKED + 1))
  mism=0
  if [ "${#actual_paths[@]}" -ne "${#expected_paths[@]}" ]; then
    bad "Dock has ${#actual_paths[@]} app(s), expected ${#expected_paths[@]}"
    mism=$((mism + 1))
  fi
  n=${#expected_paths[@]}
  if [ "${#actual_paths[@]}" -lt "$n" ]; then n=${#actual_paths[@]}; fi
  i=0
  while [ "$i" -lt "$n" ]; do
    exp="${expected_paths[$i]}"; act="${actual_paths[$i]}"
    # shellcheck disable=SC2254  # $exp is an intentional glob pattern (WhatsApp uses *)
    case "$act" in
      $exp) : ;;
      *) bad "Dock #$((i + 1)): $act (expected ${expected_names[$i]} ~ $exp)"; mism=$((mism + 1)) ;;
    esac
    i=$((i + 1))
  done
  if [ "$mism" -eq 0 ]; then
    pass "Dock matches lib/dock-apps.list (${#expected_paths[@]} apps, in order)"
  fi
fi

# ---- 5. login shell -----------------------------------------------------
hdr "Login shell"
CHECKED=$((CHECKED + 1))
FISH="$(brew --prefix 2>/dev/null)/bin/fish"
cur_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
if [ "$cur_shell" = "$FISH" ]; then
  pass "login shell = $cur_shell"
else
  bad "login shell = ${cur_shell:-unknown} (expected $FISH)"
fi

# ---- 6. hostname --------------------------------------------------------
hdr "Hostname"
for which in HostName LocalHostName ComputerName; do
  CHECKED=$((CHECKED + 1))
  cur="$(scutil --get "$which" 2>/dev/null || true)"
  if [ "$cur" = "$EXPECTED_HOST" ]; then
    pass "$which = $cur"
  else
    bad "$which = ${cur:-unset} (expected $EXPECTED_HOST)"
  fi
done

# ---- summary ------------------------------------------------------------
printf '\n%sSummary:%s %d checked, %d ok, %d drift, %d warning(s).\n' \
  "$C_HDR" "$C_OFF" "$CHECKED" "$OKS" "$DRIFT" "$WARN"

if [ "$DRIFT" -gt 0 ]; then exit 1; fi
exit 0
