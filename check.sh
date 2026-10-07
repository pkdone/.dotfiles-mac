#!/usr/bin/env bash
#
# check.sh — verifier. By default read-only: reports drift between this machine and the
# repo's desired state WITHOUT changing anything. Exits non-zero if any drift is found, so
# it's usable in a pre-push hook or CI later. With --fix it also applies the SAFE fixes
# from lib/autofix.list (reversible preference writes via the existing setters), re-checks,
# and prints a "Fixed" and a "Needs Paul" list.
#
# Sections: symlinks, Homebrew (Brewfile + cleanup extras), macOS defaults, Dock, Dock desktop assignments, login shell, hostname, display auto-brightness, URL handlers, Finder file handlers, unwanted apps, dictation shortcut + Quick Note shortcut + login LaunchAgents, Finder icon view defaults, Karabiner Fn-kill + Finder Trash, Hammerspoon (running), login items guard, Finder Recents, CotEditor, Ghostty config (valid, not overridden, effective = repo), Logi Options+ (MX Master 3S wheel / thumb wheel / gesture button / pointer speed vs lib/logi-expected.list, from a temp copy of settings.db), Modes (hammerspoon/modes.lua valid, Focus Shortcuts + Focus modes exist, current mode not left on > HEALTH_MODE_MAX_HOURS), MDM apps, leftover *.app.back, security hygiene (FileVault / softwareupdate), Mac health (battery, disk, uptime, memory, storage hogs, security basics, MDM, crashes, background jobs, dotfiles sync, unexpected login items), manual steps (scripts/manual-steps.sh check: permissions, sign-ins, by-hand settings).
# Reuses lib/macos-defaults.list, lib/dock-apps.list, lib/desktop-bindings.list, lib/file-handlers.list, lib/hostname and lib/defaults-lib.sh
# so the verify path uses the exact same data and comparison semantics as the apply path
# (macos.sh / dock.sh / lib/desktop-bindings.py / lib/file-handlers.py) and the two can never drift.
#
# Flags:
#   --no-color     Disable ANSI colour (also honours the NO_COLOR env var).
#   --health-json  Print only a JSON summary (Mac health values, drift/warning counts and
#                  messages) on stdout, for the weekly health note. Same checks, same exit.
#                  With --fix it also has fixed[] / needs_paul[] (and would_fix[] on a dry run).
#   --fix          After the checks, apply the SAFE fixes (lib/autofix.list) for any drift or
#                  warning found, re-run the checks, and report Fixed / Needs Paul. Every fix
#                  is idempotent and logged to ~/Library/Logs/com.pdone.check-fix.log.
#                  Exit status then reflects the drift left AFTER the fixes.
#   --dry-run      With --fix: show what would be fixed; change nothing.
#   --issues       Internal (used by --fix to re-check): print one line per drift/warning
#                  (kind, id, arg, message; separated by \x1f) on stdout and nothing else.
#   -h, --help     Show usage.
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fail early with a clear message if a required data/helper file is missing.
require_file() { [ -r "$1" ] || { echo "Error: required file not found: $1" >&2; exit 1; }; }
for f in defaults-lib.sh links.list macos-defaults.list dock-apps.list hostname; do
  require_file "$DOTDIR/lib/$f"
done

# Hostname is defined once in lib/hostname (shared with hostname.sh).
EXPECTED_HOST="$(awk '$1 !~ /^#/ && NF {print $1; exit}' "$DOTDIR/lib/hostname")"
NO_COLOR_OPT=0
HEALTH_JSON=0
FIX=0
DRY_RUN=0
ISSUES=0

for arg in "$@"; do
  case "$arg" in
    --no-color) NO_COLOR_OPT=1 ;;
    --health-json) HEALTH_JSON=1 ;;
    --fix) FIX=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --issues) ISSUES=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: check.sh [--no-color] [--health-json] [--fix [--dry-run]]
  Default: read-only. Reports drift between this machine and the repo; writes nothing.
  Exit status: 0 = everything matches, 1 = drift found.
  --no-color     Disable ANSI colour (also honours the NO_COLOR env var).
  --health-json  Print only a JSON summary on stdout (Mac health values, drift and
                 warning counts and messages) for the weekly health note. With --fix it
                 also carries fixed[] and needs_paul[] (would_fix[] on a dry run).
  --fix          Apply the SAFE fixes from lib/autofix.list for the drift found (reversible
                 preference writes only), re-check, and print Fixed / Needs Paul lists.
                 Exit status reflects the drift left after the fixes.
  --dry-run      With --fix: show what would be fixed; change nothing.
  -h, --help     Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done
if [ "$DRY_RUN" = 1 ] && [ "$FIX" != 1 ]; then
  echo "--dry-run only applies to --fix (check.sh is read-only without --fix)" >&2; exit 2
fi
if [ "$ISSUES" = 1 ]; then
  if [ "$FIX" = 1 ] || [ "$HEALTH_JSON" = 1 ]; then
    echo "--issues is internal and can't be combined with --fix or --health-json" >&2; exit 2
  fi
fi

# --health-json / --issues: keep the machine output alone on stdout (fd 3); the human
# report goes nowhere.
if [ "$HEALTH_JSON" = 1 ] || [ "$ISSUES" = 1 ]; then
  exec 3>&1 1>/dev/null
  NO_COLOR_OPT=1
fi

# ---- logging (colour only on a tty) -------------------------------------
if [ -t 1 ] && [ "$NO_COLOR_OPT" != 1 ] && [ -z "${NO_COLOR+x}" ]; then
  C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WARN=$'\033[33m'; C_HDR=$'\033[1m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_BAD=''; C_WARN=''; C_HDR=''; C_DIM=''; C_OFF=''
fi

CHECKED=0; OKS=0; DRIFT=0; WARN=0; HAND=0
DRIFT_MSGS=(); WARN_MSGS=()   # kept for --health-json
# Every drift / warning is tagged with an issue id from lib/autofix.list (set by `fixid`
# before the check; `hdr` resets it) so --fix knows which ones are SAFE to repair.
US=$'\037'                    # field separator for FIX_ITEMS / --issues
FIX_ID=unclassified; FIX_ARG=''
FIX_ITEMS=()                  # "kind US id US arg US message" per drift / warning
fixid() { FIX_ID="$1"; FIX_ARG="${2:-}"; }   # fixid ID [ARG] — tag the following lines
record() { FIX_ITEMS+=("$1$US$FIX_ID$US$FIX_ARG$US${2//$US/ }"); }
pass() { OKS=$((OKS + 1));    printf '  %sok%s    %s\n'  "$C_OK"   "$C_OFF" "$1"; }
bad()  { DRIFT=$((DRIFT + 1)); DRIFT_MSGS+=("$1"); record drift "$1"; printf '  %sDRIFT%s %s\n' "$C_BAD"  "$C_OFF" "$1"; }
warn() { WARN=$((WARN + 1));   WARN_MSGS+=("$1");  record warn "$1";  printf '  %swarn%s  %s\n'  "$C_WARN" "$C_OFF" "$1"; }
info() { HAND=$((HAND + 1));   printf '  info  %s\n' "$1"; }   # check-by-hand item: not drift, not a warning
note() { printf '  info  %s\n' "$1"; }                         # FYI line: not counted anywhere

# with_timeout SECS CMD... — macOS has no timeout(1) by default; perl's alarm survives
# exec, so CMD is killed (status 142) if it runs longer than SECS.
with_timeout() {
  local secs="$1"; shift
  perl -e '$t = shift @ARGV; alarm $t; exec { $ARGV[0] } @ARGV or exit 127' "$secs" "$@"
}
hdr()  { fixid unclassified; printf '\n%s%s%s\n' "$C_HDR" "$1" "$C_OFF"; }

# Value-comparison helpers shared with macos.sh (same semantics, single source).
# shellcheck source=lib/defaults-lib.sh disable=SC1091
. "$DOTDIR/lib/defaults-lib.sh"
DOT_PYTHON="$(dot_python || true)"

# ---- 1. symlinks --------------------------------------------------------
hdr "Symlinks"
check_link() {  # target  expected-source
  local target="$1" expected="$2"
  CHECKED=$((CHECKED + 1))
  fixid symlink "$target|$expected"
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

# Static one-to-one links from lib/links.list (shared with install.sh).
while IFS='|' read -r src tgt; do
  case "$src" in ''|'#'*) continue ;; esac
  check_link "${tgt//@HOME@/$HOME}" "$DOTDIR/$src"
done < "$DOTDIR/lib/links.list"
# Fish functions: one-dir-to-many glob, handled as a special case.
for f in "$DOTDIR"/fish/functions/*.fish; do
  check_link "$HOME/.config/fish/functions/$(basename "$f")" "$f"
done

# ---- 2. Homebrew --------------------------------------------------------
hdr "Homebrew (Brewfile)"
fixid brew
CHECKED=$((CHECKED + 1))
if ! command -v brew >/dev/null 2>&1; then
  warn "brew not installed — skipping Brewfile check"
else
  bf_names="$(sed -nE 's/^(brew|cask) "([^"]+)".*/\2/p' "$DOTDIR/Brewfile" | sed -E 's#.*/##' | sort -u)"
  if ! brew bundle check --no-upgrade --file "$DOTDIR/Brewfile" >/dev/null 2>&1; then
    # --no-upgrade => fail only on genuinely MISSING entries, not merely outdated ones.
    bad "Brewfile not satisfied — missing entries:"
    brew bundle check --no-upgrade --file "$DOTDIR/Brewfile" --verbose 2>&1 | sed 's/^/          /' || true
  else
    # The Brewfile pins names, not versions, so a *managed* package being merely
    # outdated is a soft warning (run brewsync), not drift. Match brewsync's env
    # (HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1) so self-updating casks it would never
    # upgrade (Cursor, VS Code, Slack, Gemini, ...) aren't flagged as actionable here.
    outdated="$(HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1 brew outdated --quiet 2>/dev/null | grep -Fxf <(printf '%s\n' "$bf_names") || true)"
    if [ -n "$outdated" ]; then
      warn "all installed; outdated (run brewsync to update): $(printf '%s' "$outdated" | tr '\n' ' ')"
    else
      pass "Brewfile satisfied (all installed and current)"
    fi
  fi
  # Closed-set extras: anything brew bundle cleanup would remove (formulae, casks, MAS)
  # that isn't in the Brewfile. Soft warning only — never auto-zap from check.sh.
  # Manual non-brew apps (Cursor Nightly, YouTube Music) never appear here.
  # MDM apps in lib/mdm-apps.list are expected leftovers — filter them out.
  CHECKED=$((CHECKED + 1))
  cleanup="$(brew bundle cleanup --file "$DOTDIR/Brewfile" 2>/dev/null || true)"
  mdm_names=""
  if [ -r "$DOTDIR/lib/mdm-apps.list" ]; then
    mdm_names="$(awk -F'|' '$1 !~ /^#/ && NF {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1}' "$DOTDIR/lib/mdm-apps.list")"
  fi
  if printf '%s\n' "$cleanup" | rg -q 'Would (uninstall|remove)'; then
    extras="$(printf '%s\n' "$cleanup" | MDM_NAMES="$mdm_names" awk '
      BEGIN { mdm=ENVIRON["MDM_NAMES"]; n=split(mdm, a, "\n"); for (i=1;i<=n;i++) if (a[i]!="") skip[a[i]]=1 }
      /^Would / {grab=1; next}
      /^Run / {grab=0}
      grab && NF {
        line=$0; gsub(/^[[:space:]]+/, "", line)
        name=line; sub(/ \(.*/, "", name)
        if (!(name in skip)) print line
      }
    ' | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    if [ -n "$extras" ]; then
      warn "Brewfile extras (add to Brewfile or uninstall): $extras"
    else
      pass "no undeclared brew/cask/mas extras (MDM apps ignored)"
    fi
  else
    pass "no undeclared brew/cask/mas extras"
  fi
fi

# ---- 2b. MDM / company apps (present, not Brewfile-managed) ----
if [ -r "$DOTDIR/lib/mdm-apps.list" ]; then
  hdr "MDM / company apps"
  fixid mdm
  while IFS='|' read -r name path _mas_id; do
    name="$(printf '%s' "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    path="$(printf '%s' "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$name" in ''|\#*) continue ;; esac
    CHECKED=$((CHECKED + 1))
    if [ -d "$path" ]; then
      pass "$name present (MDM-managed; not in Brewfile)"
    else
      warn "$name missing at $path — install via company MDM / App Store"
    fi
  done < "$DOTDIR/lib/mdm-apps.list"
fi

# Domains may be prefixed with @host/ to use `defaults -currentHost` (ByHost plists).
defaults_read() {  # domain key
  case "$1" in
    @host/*) defaults -currentHost read "${1#@host/}" "$2" ;;
    *)       defaults read "$1" "$2" ;;
  esac
}
defaults_read_type() {  # domain key
  case "$1" in
    @host/*) defaults -currentHost read-type "${1#@host/}" "$2" ;;
    *)       defaults read-type "$1" "$2" ;;
  esac
}

# ---- 3. macOS defaults --------------------------------------------------
hdr "macOS defaults"
while IFS='|' read -r domain key etype desired _restart _area _label _disp tol; do
  case "$domain" in ''|'#'*) continue ;; esac
  CHECKED=$((CHECKED + 1))
  fixid defaults "$domain|$key"
  desired="${desired//@HOME@/$HOME}"
  want_token="$(type_token "$etype")"
  if cur="$(defaults_read "$domain" "$key" 2>/dev/null)"; then
    curtype="$(defaults_read_type "$domain" "$key" 2>/dev/null || true)"
    curtype="${curtype##* }"
    if [ "$curtype" != "$want_token" ]; then
      bad "$domain $key — type mismatch (expected $want_token, found ${curtype:-none})"
    elif values_match "$etype" "$cur" "$desired" "$tol"; then
      if [ -n "$tol" ] && [ "$tol" != 0 ] && ! values_equal "$etype" "$cur" "$desired"; then
        pass "$domain $key = $cur (within ±$tol of $desired)"
      else
        pass "$domain $key = $cur"
      fi
    else
      bad "$domain $key = $cur (expected $desired)"
    fi
  else
    bad "$domain $key — not set (expected $desired)"
  fi
done < "$DOTDIR/lib/macos-defaults.list"

# ---- 4. Dock ------------------------------------------------------------
hdr "Dock"
fixid dock-apps
if ! command -v dockutil >/dev/null 2>&1; then
  fixid tooling
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

# ---- 4b. Dock "Assign To" desktop pins ----------------------------------
# Read-only here. --fix writes the drifted bundles back (same Desktop N → Space
# UUID map) via the desktop fixer below.
hdr "Desktop assignments (Dock → Options → Assign To)"
fixid desktop-assign
if PY="$(dot_python)"; then
  while IFS='|' read -r status bundle msg; do
    [ -z "$status" ] && continue
    CHECKED=$((CHECKED + 1))
    case "$status" in
      ok)  pass "$msg" ;;
      bad) fixid desktop-assign "$bundle"; bad "$msg" ;;
      *)   fixid tooling; warn "${msg:-$bundle}" ;;
    esac
  done < <("$PY" "$DOTDIR/lib/desktop-bindings.py" "$DOTDIR/lib/desktop-bindings.list")
else
  CHECKED=$((CHECKED + 1))
  fixid tooling; warn "no python3 — skipping desktop assignment check"
fi

# ---- 5. login shell -----------------------------------------------------
hdr "Login shell"
fixid login-shell
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
fixid hostname
for which in HostName LocalHostName ComputerName; do
  CHECKED=$((CHECKED + 1))
  cur="$(scutil --get "$which" 2>/dev/null || true)"
  if [ "$cur" = "$EXPECTED_HOST" ]; then
    pass "$which = $cur"
  else
    bad "$which = ${cur:-unset} (expected $EXPECTED_HOST)"
  fi
done

# ---- 6b. Display auto-brightness ----------------------------------------
# Read-only. corebrightnessdiag status-info needs no sudo. The saved value is
# the root-owned CoreBrightness plist, and published writers also change True
# Tone, so this is not applied here or by --fix.
hdr "Display auto-brightness"
fixid auto-brightness
CHECKED=$((CHECKED + 1))
if [ ! -x /usr/libexec/corebrightnessdiag ]; then
  fixid tooling
  warn "corebrightnessdiag missing — can't check Automatically adjust brightness"
elif [ ! -r "$DOTDIR/lib/auto-brightness.py" ]; then
  fixid repo-file
  warn "lib/auto-brightness.py missing — can't check Automatically adjust brightness"
elif ! PY="$(dot_python)"; then
  fixid tooling
  warn "no python3 — can't check Automatically adjust brightness"
else
  diag_out="$(with_timeout 15 /usr/libexec/corebrightnessdiag status-info 2>/dev/null || true)"
  if [ -z "$diag_out" ]; then
    fixid tooling
    warn "corebrightnessdiag status-info returned nothing — can't check Automatically adjust brightness"
  else
    ab_line="$(printf '%s\n' "$diag_out" | "$PY" "$DOTDIR/lib/auto-brightness.py" || true)"
    ab_status="${ab_line%%|*}"
    ab_msg="${ab_line#*|}"
    ab_msg="${ab_msg#*|}"
    case "$ab_status" in
      ok)  pass "$ab_msg" ;;
      bad) bad "$ab_msg" ;;
      *)   fixid tooling; warn "${ab_msg:-auto-brightness check failed}" ;;
    esac
  fi
fi

# ---- 7. URL handlers ----------------------------------------------------
hdr "URL handlers"
fixid url-handler
HANDLERS_LIST="$DOTDIR/lib/url-handlers.list"
if [ ! -r "$HANDLERS_LIST" ]; then
  fixid repo-file; warn "lib/url-handlers.list missing — skipping URL handlers check"
elif ! command -v duti >/dev/null 2>&1; then
  fixid tooling; warn "duti not installed — skipping URL handlers check"
else
  while IFS='|' read -r scheme bundle; do
    case "$scheme" in ''|'#'*) continue ;; esac
    scheme="$(printf '%s' "$scheme" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    bundle="$(printf '%s' "$bundle" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$scheme" ] || continue
    [ -n "$bundle" ] || continue
    CHECKED=$((CHECKED + 1))
    cur="$(duti -d "$scheme" 2>/dev/null || true)"
    if [ "$cur" = "$bundle" ]; then
      pass "$scheme -> $bundle"
    else
      bad "$scheme -> ${cur:-unset} (expected $bundle)"
    fi
  done < "$HANDLERS_LIST"
fi

# ---- 7b. Finder file handlers -------------------------------------------
# Read-only here. lib/file-handlers.py runs `duti -x <ext>` (bundle id is the
# last line). --fix sets drifted extensions with `duti -s <bundle> .<ext> all`
# via the fileext fixer below.
hdr "File handlers"
fixid file-handler
FILE_HANDLERS_LIST="$DOTDIR/lib/file-handlers.list"
if [ ! -r "$FILE_HANDLERS_LIST" ]; then
  fixid repo-file; warn "lib/file-handlers.list missing — skipping file handlers check"
elif ! command -v duti >/dev/null 2>&1; then
  fixid tooling; warn "duti not installed — skipping file handlers check"
elif ! PY="$(dot_python)"; then
  fixid tooling; warn "no python3 — skipping file handlers check"
else
  while IFS='|' read -r status ext msg; do
    [ -z "$status" ] && continue
    CHECKED=$((CHECKED + 1))
    case "$status" in
      ok)  fixid file-handler "$ext"; pass "$msg" ;;
      bad) fixid file-handler "$ext"; bad "$msg" ;;
      *)   fixid tooling; warn "${msg:-$ext}" ;;
    esac
  done < <("$PY" "$DOTDIR/lib/file-handlers.py" "$FILE_HANDLERS_LIST")
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
CHECKED=$((CHECKED + 1))
LA_LABEL=com.pdone.pin-dictation-hotkey-164
fixid launchagent "$LA_LABEL|$HOME/Library/LaunchAgents/$LA_LABEL.plist"
if launchctl print "gui/$(id -u)/$LA_LABEL" >/dev/null 2>&1; then
  pass "LaunchAgent $LA_LABEL loaded (re-pins 164 at login)"
else
  bad "LaunchAgent $LA_LABEL not loaded — re-run install.sh"
fi

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
CHECKED=$((CHECKED + 1))
LA_LABEL=com.pdone.pin-quicknote-hotkey-190
fixid launchagent "$LA_LABEL|$HOME/Library/LaunchAgents/$LA_LABEL.plist"
if launchctl print "gui/$(id -u)/$LA_LABEL" >/dev/null 2>&1; then
  pass "LaunchAgent $LA_LABEL loaded (re-disables 190 at login)"
else
  bad "LaunchAgent $LA_LABEL not loaded — re-run install.sh"
fi

# ---- 9b. Finder icon-view defaults (72 / 13) ------------------------------
hdr "Finder icon view defaults"
fixid finder-icon-view
CHECKED=$((CHECKED + 1))
pin="$DOTDIR/scripts/pin-finder-icon-view.sh"
if [ ! -x "$pin" ]; then
  fixid repo-file; bad "scripts/pin-finder-icon-view.sh missing"
elif "$pin" --check >/dev/null 2>&1; then
  pass "Finder icon view defaults iconSize=72 textSize=13"
else
  bad "Finder icon view defaults drifted ($("$pin" --check 2>&1 || true)) — run macos.sh"
fi

# ---- 10. Karabiner Fn-kill ----------------------------------------------
# Config is symlinked via links.list (section 1). Here we also verify the
# managed rule is still present in that JSON (UI edits can strip it). The DriverKit
# extension and Accessibility grants are manual steps, checked in the "Manual steps"
# section (scripts/manual-steps.sh ids karabiner-driver / karabiner-ax).
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
fi

# ---- 10b. Hammerspoon (Sidecar -> Slack automation) ----------------------
# The ~/.hammerspoon dir symlink is checked in section 1 (links.list) and the cask in
# section 2 (Brewfile). Here: soft-warn if the app isn't running. Its Accessibility
# grant is a manual step, checked in the "Manual steps" section (id hammerspoon-ax).
# Never launches or changes anything.
hdr "Hammerspoon"
fixid hammerspoon
CHECKED=$((CHECKED + 1))
H_HS_RUNNING=no   # reused by the Mac health JSON (background jobs)
if [ ! -d /Applications/Hammerspoon.app ]; then
  H_HS_RUNNING=not_installed
  fixid app-install
  warn "Hammerspoon.app not installed — brew bundle (cask \"hammerspoon\")"
elif ! pgrep -xq Hammerspoon; then
  warn "Hammerspoon not running — open -a Hammerspoon (then it starts at login)"
else
  H_HS_RUNNING=yes
  pass "Hammerspoon running"
fi

# ---- 11. Login Items guard (ChatGPT / Gemini / launcher must stay Off) ----
# SMAppService login items aren't safely disable-able from CLI; check only.
hdr "Login Items (banned open-at-login)"
fixid tooling   # helper / python problems below; the item checks are login-items
BANNED_BUNDLES="com.openai.codex com.google.GeminiMacOS com.google.GeminiMacOS.launcher"
BANNED_NAMES="ChatGPT Gemini GeminiAppLauncher"
# Prefer parsing the world-readable BTM db — `sfltool dumpbtm` pops an admin
# password dialog on Tahoe and must never run from check.sh.
BTM_HELPER="$DOTDIR/lib/btm-login-items.py"
if [ ! -r "$BTM_HELPER" ]; then
  warn "lib/btm-login-items.py missing — skip SMAppService login-item check"
elif [ -z "$DOT_PYTHON" ]; then
  warn "python3 not found — skip SMAppService login-item check"
else
  # shellcheck disable=SC2206  # intentional split of space-separated bundle ids
  btm_bundles=($BANNED_BUNDLES)
  btm_raw="$("$DOT_PYTHON" "$BTM_HELPER" "${btm_bundles[@]}" 2>&1)" && btm_rc=0 || btm_rc=$?
  # bundle ids contain a dot; ignore helper keys like btm= / tcc=
  btm_status="$(printf '%s\n' "$btm_raw" | awk -F= 'NF==2 && $1 ~ /\./ && $2 ~ /^(missing|disabled|enabled|unknown)$/ {print}')"
  btm_err="$(printf '%s\n' "$btm_raw" | awk -F= '!(NF==2 && $1 ~ /\./ && $2 ~ /^(missing|disabled|enabled|unknown)$/) {print}' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ "$btm_rc" = 3 ] || printf '%s\n' "$btm_raw" | rg -q 'tcc=denied|Operation not permitted'; then
    fixid tcc; warn "BTM unreadable (Full Disk Access) via $DOT_PYTHON — System Settings → Privacy & Security → Full Disk Access → enable Ghostty"
  elif [ "$btm_rc" -ne 0 ] || [ -z "$btm_status" ]; then
    warn "BTM helper failed (rc=$btm_rc${btm_err:+; $btm_err}) via $DOT_PYTHON — check Login Items manually"
  else
    fixid login-items
    for bundle in "${btm_bundles[@]}"; do
      CHECKED=$((CHECKED + 1))
      st="$(printf '%s\n' "$btm_status" | awk -F= -v b="$bundle" '$1==b {print $2; exit}')"
      case "$st" in
        missing)  pass "$bundle not in Background Task Management (ok)" ;;
        disabled) pass "$bundle login item disabled" ;;
        enabled)  bad "$bundle is enabled at login — System Settings → General → Login Items → Off" ;;
        *)        warn "$bundle BTM status unknown (${st:-empty}) — check Login Items manually" ;;
      esac
    done
  fi
fi
# Classic login items (System Events) — rare for these apps but cheap to check.
fixid login-items
classic="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || true)"
for name in $BANNED_NAMES; do
  CHECKED=$((CHECKED + 1))
  if printf '%s\n' "$classic" | rg -q "(^|, )${name}(,|$)"; then
    bad "classic login item '$name' present — remove in System Settings → Login Items"
  else
    pass "classic login item '$name' absent"
  fi
done

# ---- 12. Finder sidebar Recents ----
hdr "Finder sidebar Recents"
fixid finder-recents
CHECKED=$((CHECKED + 1))
helper="$DOTDIR/lib/finder-sidebar-recents.py"
if [ ! -r "$helper" ]; then
  fixid tooling; warn "lib/finder-sidebar-recents.py missing — skip"
elif [ -z "$DOT_PYTHON" ]; then
  fixid tooling; warn "python3 not found — skip Finder Recents"
else
  # Guard exit status: with set -e, a failing $(...) aborts before rc= is set.
  out="$("$DOT_PYTHON" "$helper" 2>&1)" && rc=0 || rc=$?
  if [ "$rc" = 3 ] || printf '%s\n' "$out" | rg -q 'tcc=denied|Operation not permitted|PermissionError'; then
    fixid tcc; warn "Finder Recents unreadable (Full Disk Access) — System Settings → Privacy & Security → Full Disk Access → enable Ghostty"
  elif [ "$rc" = 0 ]; then
    pass "Finder sidebar Recents hidden"
  else
    bad "Finder sidebar Recents not hidden ($out) — run macos.sh"
  fi
fi

# ---- 13. CotEditor theme + font ----
hdr "CotEditor"
fixid coteditor
CHECKED=$((CHECKED + 1))
cot_theme="$(defaults read com.coteditor.CotEditor defaultTheme 2>/dev/null || true)"
cot_font="$(defaults export com.coteditor.CotEditor - 2>/dev/null | plutil -extract modes.general.fontType raw - 2>/dev/null || true)"
if [ "$cot_theme" = "Anura (Dark)" ] && [ "$cot_font" = "monospaced" ]; then
  pass "CotEditor theme=Anura (Dark) fontType=monospaced"
else
  bad "CotEditor theme=${cot_theme:-unset} fontType=${cot_font:-unset} (expected Anura (Dark) / monospaced)"
fi

# ---- 13b. Ghostty config (app settings as code) --------------------------
# ghostty/config is symlinked into ~/.config/ghostty/config (section 1). Here: the repo
# file is valid, no other config file Ghostty loads overrides it, and what Ghostty
# actually loads equals the repo file alone (+show-config with only the repo copy vs the
# real one). Read-only: the comparison copy lives in a temp dir that's removed after.
hdr "Ghostty config"
fixid app-config
GHOSTTY_BIN=/Applications/Ghostty.app/Contents/MacOS/ghostty
G_REPO="$DOTDIR/ghostty/config"
if [ ! -x "$GHOSTTY_BIN" ]; then
  CHECKED=$((CHECKED + 1))
  fixid app-install; warn "Ghostty.app not installed — brew bundle (cask \"ghostty\")"
else
  CHECKED=$((CHECKED + 1))
  if g_val="$(with_timeout 10 "$GHOSTTY_BIN" +validate-config --config-file="$G_REPO" </dev/null 2>&1)"; then
    pass "ghostty/config is valid (ghostty +validate-config)"
  else
    bad "ghostty/config has errors: $(printf '%s' "$g_val" | tr '\n' ' ' | sed 's/[[:space:]]*$//') — fix the repo file"
  fi
  # Ghostty also reads these (Application Support is loaded after ~/.config and wins).
  CHECKED=$((CHECKED + 1))
  g_over=""
  for g_f in "$HOME/Library/Application Support/com.mitchellh.ghostty/config" \
             "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty" \
             "$HOME/.config/ghostty/config.ghostty"; do
    if [ -f "$g_f" ] && grep -Eq '^[[:space:]]*[^#[:space:]]' "$g_f"; then g_over="$g_over ${g_f/#$HOME/~};"; fi
  done
  if [ -n "$g_over" ]; then
    bad "Ghostty also loads${g_over%;} — it overrides the repo config; merge it into ghostty/config, then remove it"
  else
    pass "no other Ghostty config file overrides the repo one"
  fi
  CHECKED=$((CHECKED + 1))
  g_tmp="$(mktemp -d)"
  mkdir -p "$g_tmp/ghostty" && cp "$G_REPO" "$g_tmp/ghostty/config"
  g_eff="$(with_timeout 10 "$GHOSTTY_BIN" +show-config </dev/null 2>/dev/null || true)"
  g_want="$(XDG_CONFIG_HOME="$g_tmp" with_timeout 10 "$GHOSTTY_BIN" +show-config </dev/null 2>/dev/null || true)"
  rm -rf "$g_tmp"
  if [ -z "$g_want" ]; then
    fixid tooling; warn "ghostty +show-config printed nothing — can't compare the effective config"
  elif [ "$g_eff" = "$g_want" ]; then
    pass "Ghostty's effective config = ghostty/config ($(printf '%s\n' "$g_eff" | grep -c .) resolved settings)"
  else
    g_diff="$(diff <(printf '%s\n' "$g_want") <(printf '%s\n' "$g_eff") | grep -E '^[<>]' | head -3 | tr '\n' ' ')"
    bad "Ghostty's effective config differs from ghostty/config (< repo, > loaded): ${g_diff% } — check the symlink and override files"
  fi
fi

# ---- 13c. Logi Options+ (MX Master 3S settings, check-only) ---------------
# lib/logi-settings.py reads a temporary copy of Logi Options+'s settings.db (deleted
# afterwards) and compares it with lib/logi-expected.list; the device is found by model,
# not serial. Never writes the database: any drift is restored by hand in the app.
# Cloud backup can't be read locally, so it's the by-hand manual step logi-cloud-backup.
hdr "Logi Options+"
LOGI_APP=/Applications/logioptionsplus.app
LOGI_HELPER="$DOTDIR/lib/logi-settings.py"
CHECKED=$((CHECKED + 1))
if [ ! -d "$LOGI_APP" ]; then
  fixid app-install; warn "Logi Options+ not installed — brew bundle (cask \"logi-options+\")"
elif [ -z "$DOT_PYTHON" ] || [ ! -r "$LOGI_HELPER" ]; then
  fixid tooling; warn "can't check Logi Options+ settings (python3 or lib/logi-settings.py missing)"
else
  logi_ids="$(grep -Ev '^[[:space:]]*(#|$|model\|)' "$DOTDIR/lib/logi-expected.list" 2>/dev/null \
    | cut -d'|' -f1 | tr '\n' ',' | sed 's/,$//')"
  if logi_out="$(with_timeout 20 "$DOT_PYTHON" "$LOGI_HELPER" --only "$logi_ids" </dev/null 2>&1)"; then logi_rc=0; else logi_rc=$?; fi
  logi_n=0
  while IFS='|' read -r l_st _ l_msg; do
    [ -n "$l_st" ] || continue
    case "$l_st" in
      ok)    logi_n=$((logi_n + 1)); [ "$logi_n" -eq 1 ] || CHECKED=$((CHECKED + 1)); pass "$l_msg" ;;
      drift) logi_n=$((logi_n + 1)); [ "$logi_n" -eq 1 ] || CHECKED=$((CHECKED + 1))
             fixid logi-settings; bad "$l_msg — set it back in Logi Options+ (MX Master 3S)" ;;
      warn)  logi_n=$((logi_n + 1)); [ "$logi_n" -eq 1 ] || CHECKED=$((CHECKED + 1))
             fixid logi-settings; warn "$l_msg" ;;
      note)  note "$l_msg" ;;
      *)     fixid logi-unreadable; warn "Logi Options+: ${l_msg:-$l_st}" ;;
    esac
  done <<LOGI_EOF
$logi_out
LOGI_EOF
  case "$logi_rc" in
    0|1|2|3) ;;
    *) fixid logi-unreadable; warn "Logi Options+ check failed or timed out (rc=$logi_rc) — settings not verified" ;;
  esac
  if [ "$logi_n" -eq 0 ] && [ "$logi_rc" -le 1 ]; then
    fixid logi-unreadable; warn "Logi Options+ check printed no results — settings not verified"
  fi
fi

# ---- 13d. Modes (Hammerspoon menu-bar switcher) ----------------------------
# hammerspoon/modes.lua must be valid (the same validator the switcher uses: a Lua
# interpreter if there is one, else the running Hammerspoon via `hs`; `luac -p` only
# checks syntax). The Focus Shortcuts and Focus modes it names should exist (report
# only: a mode still runs without them). A non-Normal mode left on for more than
# HEALTH_MODE_MAX_HOURS is a warning. Apps a mode quit or hid on purpose are listed as
# info, never drift. Read-only: never switches a mode or touches state.json.
hdr "Modes (Hammerspoon)"
HEALTH_MODE_MAX_HOURS="${HEALTH_MODE_MAX_HOURS:-4}"
MODES_CFG="$DOTDIR/hammerspoon/modes.lua"
MODES_ENGINE="$DOTDIR/hammerspoon/mode_switcher.lua"
MODES_STATE="$HOME/Library/Application Support/pdone-modes/state.json"
CHECKED=$((CHECKED + 1))
fixid modes-config
modes_lua=""
for c in lua5.4 lua54 lua; do
  if command -v "$c" >/dev/null 2>&1; then modes_lua="$c"; break; fi
done
modes_val=""
if [ ! -r "$MODES_CFG" ] || [ ! -r "$MODES_ENGINE" ]; then
  fixid repo-file; bad "hammerspoon/modes.lua or mode_switcher.lua missing — restore it from git"
else
  if [ -n "$modes_lua" ]; then
    modes_val="$(with_timeout 10 "$modes_lua" -e "local ms = dofile(arg[1]); io.write(ms.validateFile(arg[2]))" "$MODES_ENGINE" "$MODES_CFG" </dev/null 2>&1 || true)"
    modes_how="$modes_lua"
  elif command -v hs >/dev/null 2>&1 && pgrep -xq Hammerspoon; then
    # hs reads stdin unless it's /dev/null; dofile (not require) = the repo file as it is now
    modes_val="$(with_timeout 15 hs -q -t 10 -c "return dofile('$MODES_ENGINE').validateFile('$MODES_CFG')" </dev/null 2>&1 | grep -v '^-- Loading' || true)"
    modes_how="Hammerspoon (hs)"
  elif command -v luac >/dev/null 2>&1; then
    if modes_err="$(luac -p "$MODES_CFG" 2>&1)"; then modes_val="ok"; else modes_val="error: $modes_err"; fi
    modes_how="luac -p (syntax only)"
  fi
  case "$modes_val" in
    ok)       pass "hammerspoon/modes.lua is valid ($modes_how)" ;;
    error:*)  bad "hammerspoon/modes.lua: ${modes_val#error: } — fix it, then reload Hammerspoon" ;;
    "")       fixid tooling; warn "can't validate hammerspoon/modes.lua (no lua / luac, and Hammerspoon isn't running)" ;;
    *)        fixid tooling; warn "hammerspoon/modes.lua: unexpected validator output: $(printf '%s' "$modes_val" | head -c 200)" ;;
  esac

  # Shortcuts named in modes.lua (Focus on/off only)
  fixid modes-setup
  CHECKED=$((CHECKED + 1))
  modes_need="$(grep -oE "(on|off)[[:space:]]*=[[:space:]]*'[^']+'" "$MODES_CFG" | sed -E "s/^[a-z]+[[:space:]]*=[[:space:]]*'//; s/'\$//" | sort -u)"
  if ! command -v shortcuts >/dev/null 2>&1; then
    fixid tooling; warn "shortcuts CLI not found — can't check the Focus Shortcuts"
  elif ! modes_have="$(with_timeout 15 shortcuts list </dev/null 2>/dev/null)"; then
    fixid tooling; warn "shortcuts list failed — can't check the Focus Shortcuts"
  else
    modes_missing=""
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      if ! printf '%s\n' "$modes_have" | grep -Fxq "$s"; then modes_missing="$modes_missing '$s',"; fi
    done <<< "$modes_need"
    if [ -n "$modes_missing" ]; then
      warn "Shortcuts missing:${modes_missing%,} — create them (manual step mode-focus-shortcuts); modes still run, without the Focus"
    else
      pass "Focus Shortcuts exist ($(printf '%s\n' "$modes_need" | grep -c .))"
    fi
  fi

  # Focus modes named in modes.lua (focus = '<name>'), from the Focus database
  CHECKED=$((CHECKED + 1))
  modes_focus="$(grep -oE "^[[:space:]]+focus[[:space:]]*=[[:space:]]*'[^']+'" "$MODES_CFG" | sed -E "s/.*'([^']+)'/\1/" | sort -u)"
  modes_fdb="$HOME/Library/DoNotDisturb/DB/ModeConfigurations.json"
  if [ -z "$DOT_PYTHON" ]; then
    fixid tooling; warn "python3 missing — can't check the Focus modes"
  elif ! modes_fnames="$("$DOT_PYTHON" - "$modes_fdb" <<'PY' 2>/dev/null
import json, sys
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "name" and isinstance(v, str):
                print(v)
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
walk(json.load(open(sys.argv[1])))
PY
)"; then
    note "Focus modes not readable (needs Full Disk Access) — check System Settings → Focus for:$(printf '%s\n' "$modes_focus" | tr '\n' ' ' | sed 's/ $//; s/^/ /')"
  else
    modes_fmiss=""
    for f in $modes_focus; do
      if ! printf '%s\n' "$modes_fnames" | grep -Fxq "$f"; then modes_fmiss="$modes_fmiss $f"; fi
    done
    if [ -n "$modes_fmiss" ]; then
      warn "Focus modes missing:$modes_fmiss — System Settings → Focus → Add Focus… (manual step mode-focus-modes)"
    else
      pass "Focus modes exist:$(printf '%s\n' "$modes_focus" | tr '\n' ' ' | sed 's/ $//; s/^/ /')"
    fi
  fi
fi

# Current mode (state.json is written by the switcher; absent = Normal)
CHECKED=$((CHECKED + 1))
fixid mode-long
if [ ! -f "$MODES_STATE" ]; then
  pass "mode: Normal (no state.json yet)"
elif [ -z "$DOT_PYTHON" ]; then
  fixid tooling; warn "python3 missing — can't read the mode state"
else
  modes_st="$("$DOT_PYTHON" - "$MODES_STATE" <<'PY' 2>/dev/null
import json, sys, time
s = json.load(open(sys.argv[1]))
ch = s.get("changes") or {}
if not isinstance(ch, dict):
    ch = {}
def names(key):
    return ", ".join((x.get("name") or x.get("bundle") or "?").replace("\u200e", "") for x in ch.get(key) or [] if isinstance(x, dict))
hours = (time.time() - float(s.get("since") or time.time())) / 3600
print("\t".join([str(s.get("mode") or "?"), "%.1f" % hours, str(s.get("phase") or ""), names("quit"), names("hidden")]))
PY
)" || modes_st=""
  if [ -z "$modes_st" ]; then
    fixid modes-config; warn "state.json unreadable ($MODES_STATE) — switch to Normal from the menu bar to rewrite it"
  else
    IFS=$'\t' read -r st_mode st_hours st_phase st_quit st_hidden <<< "$modes_st"
    if [ "$st_mode" = "Normal" ]; then
      pass "mode: Normal"
    else
      if [ -n "$st_quit" ]; then note "quit by $st_mode on purpose (not drift; Normal reopens them): $st_quit"; fi
      if [ -n "$st_hidden" ]; then note "hidden by $st_mode on purpose (not drift; Normal unhides them): $st_hidden"; fi
      if awk -v h="$st_hours" -v max="$HEALTH_MODE_MAX_HOURS" 'BEGIN { exit !(h > max) }'; then
        warn "mode $st_mode has been on for ${st_hours}h (> ${HEALTH_MODE_MAX_HOURS}h) — switch back to Normal from the menu bar if you're done"
      else
        pass "mode: $st_mode for ${st_hours}h${st_phase:+ ($st_phase)}"
      fi
    fi
  fi
fi

# ---- 14. Leftover *.app.back in /Applications ----
hdr "Leftover app backups"
fixid delete-files
CHECKED=$((CHECKED + 1))
shopt -s nullglob
backs=(/Applications/*.app.back)
shopt -u nullglob
if [ ${#backs[@]} -eq 0 ]; then
  pass "no /Applications/*.app.back leftovers"
else
  for f in "${backs[@]}"; do
    warn "leftover $f (safe to trash; leftover from an in-place app update)"
  done
fi


# ---- 15. Security hygiene (soft — warn only) ----------------------------
hdr "Security hygiene"
fixid security
CHECKED=$((CHECKED + 1))
fv="$(fdesetup status 2>/dev/null || true)"
if printf '%s\n' "$fv" | rg -qi 'FileVault is On'; then
  pass "FileVault On"
elif [ -z "$fv" ]; then
  warn "FileVault status unknown (fdesetup failed)"
else
  warn "FileVault not On — $fv"
fi

CHECKED=$((CHECKED + 1))
fixid software-update
# softwareupdate -l talks to Apple; keep it soft and tolerant of transient failures.
su_out="$(softwareupdate -l 2>&1)" || true
if printf '%s\n' "$su_out" | rg -qi 'No new software available'; then
  pass "no pending software updates"
elif printf '%s\n' "$su_out" | rg -q 'Label:'; then
  titles="$(printf '%s\n' "$su_out" | awk -F'Title: ' '/Title:/{print $2}' | sed 's/, Version:.*//; s/[[:space:]]*$//' | paste -sd '; ' -)"
  warn "pending software updates: ${titles:-see softwareupdate -l}"
else
  warn "could not list software updates (softwareupdate -l failed or unexpected output)"
fi

# ---- 15b. Mac health (soft — warn only, never drift) ---------------------
# Read-only and timeout-guarded. Values are also kept in H_* for --health-json.
# Anything that can't be read without sudo / Full Disk Access is an info (by-hand) line.
hdr "Mac health"
fixid health

# Thresholds: the one place to tune the health warnings.
HEALTH_BATTERY_MIN_PCT=80        # battery maximum capacity
HEALTH_DISK_MIN_GB=50            # free space on the Data volume …
HEALTH_DISK_MIN_PCT=15           # … warn when below either
HEALTH_UPTIME_MAX_DAYS=14
HEALTH_SWAP_MAX_GB=8             # swap in use
HEALTH_CRASH_DAYS=7              # look-back window for panics / crashes
HEALTH_CRASH_SAME_APP=3          # warn at this many crashes of one app in the window
HEALTH_CACHES_MAX_GB=20          # ~/Library/Caches
HEALTH_DOCKER_MAX_GB=60          # Docker Desktop disk image (allocated size)
HEALTH_BREW_CACHE_MAX_GB=5       # brew --cache
HEALTH_DERIVED_DATA_MAX_GB=20    # Xcode DerivedData

H_BAT_STATUS=none; H_BAT_COND=""; H_BAT_MAX=""; H_BAT_CYCLES=""
H_DISK_STATUS=unknown; H_DISK_FREE_GB=""; H_DISK_FREE_PCT=""; H_DISK_TOTAL_GB=""
H_UP_STATUS=unknown; H_UP_DAYS=""
H_MEM_STATUS=unknown; H_MEM_SWAP_GB=""; H_MEM_PRESSURE=unknown; H_MEM_FREE_PCT=""
H_STO_STATUS=ok; H_STO_CACHES=""; H_STO_DOCKER=""; H_STO_BREW=""; H_STO_DERIVED=""
H_SEC_STATUS=ok; H_SEC_FIREWALL=unknown; H_SEC_GATEKEEPER=unknown; H_SEC_SIP=unknown
H_SEC_SSH=unknown; H_SEC_SCREENSHARING=unknown; H_SEC_FILESHARING=unknown; H_SEC_SCREENLOCK=unknown
H_MDM_STATUS=unknown; H_MDM_ENROLLED=unknown; H_MDM_AGENT=unknown
H_CR_STATUS=unknown; H_CR_PANICS=""; H_CR_CRASHES=""; H_CR_FAULTS=""; H_CR_APPS=(); H_CR_PANIC_FILES=()
H_JOBS_STATUS=ok; H_JOBS=()
H_GIT_STATUS=unknown; H_GIT_DIRTY=""; H_GIT_AHEAD=""; H_GIT_BEHIND=""; H_GIT_FETCHED=""
H_LI_STATUS=unknown; H_LI_ENABLED=0; H_LI_ALLOW=0; H_LI_MDM=0; H_LI_UNKNOWN=(); H_LI_STALE=()

kb_to_gb() { awk -v k="$1" 'BEGIN { printf "%.1f", k / 1048576 }'; }   # KiB -> GiB, 1 dp
gb_over() { awk -v v="$1" -v m="$2" 'BEGIN { exit !(v > m) }'; }       # gb_over VALUE MAX
# du_kb PATH... — allocated KiB (sparse Docker.raw counts real use), empty if unreadable.
du_kb() { with_timeout 60 du -sk "$@" 2>/dev/null | awk '{ s += $1 } END { if (NR) print s }'; }

# Battery: condition, maximum capacity and cycle count.
CHECKED=$((CHECKED + 1))
sp_power="$(with_timeout 20 system_profiler SPPowerDataType 2>/dev/null || true)"
H_BAT_COND="$(printf '%s\n' "$sp_power" | awk -F': ' '/^ *Condition:/ {print $2; exit}')"
H_BAT_MAX="$(printf '%s\n' "$sp_power" | awk -F': ' '/^ *Maximum Capacity:/ {gsub(/%/, "", $2); print $2; exit}')"
H_BAT_CYCLES="$(printf '%s\n' "$sp_power" | awk -F': ' '/^ *Cycle Count:/ {print $2; exit}')"
if [ -z "$H_BAT_MAX" ] || [ -z "$H_BAT_CYCLES" ]; then
  # Fallback: raw battery registry (NominalChargeCapacity / DesignCapacity).
  bat_io="$(with_timeout 10 ioreg -rn AppleSmartBattery 2>/dev/null || true)"
  if [ -z "$H_BAT_CYCLES" ]; then
    H_BAT_CYCLES="$(printf '%s\n' "$bat_io" | sed -nE 's/^ *"CycleCount" = ([0-9]+).*/\1/p' | head -1)"
  fi
  if [ -z "$H_BAT_MAX" ]; then
    bat_nom="$(printf '%s\n' "$bat_io" | sed -nE 's/.*"NominalChargeCapacity"=([0-9]+).*/\1/p' | head -1)"
    bat_des="$(printf '%s\n' "$bat_io" | sed -nE 's/.*"DesignCapacity"=([0-9]+).*/\1/p' | head -1)"
    if [ -n "$bat_nom" ] && [ -n "$bat_des" ] && [ "$bat_des" -gt 0 ]; then
      H_BAT_MAX=$(( (bat_nom * 100 + bat_des / 2) / bat_des ))
    fi
  fi
fi
case "$H_BAT_MAX" in *[!0-9]*) H_BAT_MAX="" ;; esac
case "$H_BAT_CYCLES" in *[!0-9]*) H_BAT_CYCLES="" ;; esac
if [ -z "$H_BAT_COND$H_BAT_MAX$H_BAT_CYCLES" ]; then
  note "battery: none found (desktop Mac?) — skipped"
  CHECKED=$((CHECKED - 1))
elif [ -n "$H_BAT_COND" ] && [ "$H_BAT_COND" != Normal ]; then
  H_BAT_STATUS=warn
  warn "battery condition ${H_BAT_COND} (max capacity ${H_BAT_MAX:-?}%, ${H_BAT_CYCLES:-?} cycles) — System Settings → Battery → Battery Health"
elif [ -n "$H_BAT_MAX" ] && [ "$H_BAT_MAX" -lt "$HEALTH_BATTERY_MIN_PCT" ]; then
  H_BAT_STATUS=warn
  warn "battery max capacity ${H_BAT_MAX}% (< ${HEALTH_BATTERY_MIN_PCT}%; ${H_BAT_CYCLES:-?} cycles) — consider a service"
else
  H_BAT_STATUS=ok
  pass "battery ${H_BAT_COND:-condition unknown}, max capacity ${H_BAT_MAX:-?}%, ${H_BAT_CYCLES:-?} cycles"
fi

# Disk: free space on the Data volume; warn below either threshold.
CHECKED=$((CHECKED + 1))
disk_vol=/System/Volumes/Data
[ -d "$disk_vol" ] || disk_vol=/
read -r disk_total_k disk_avail_k < <(with_timeout 10 df -k "$disk_vol" 2>/dev/null | awk 'NR==2 {print $2, $4}') || true
if [ -n "${disk_total_k:-}" ] && [ -n "${disk_avail_k:-}" ] && [ "$disk_total_k" -gt 0 ]; then
  H_DISK_FREE_GB=$(( disk_avail_k * 1024 / 1000000000 ))
  H_DISK_TOTAL_GB=$(( disk_total_k * 1024 / 1000000000 ))
  H_DISK_FREE_PCT=$(( disk_avail_k * 100 / disk_total_k ))
  if [ "$H_DISK_FREE_PCT" -lt "$HEALTH_DISK_MIN_PCT" ] || [ "$H_DISK_FREE_GB" -lt "$HEALTH_DISK_MIN_GB" ]; then
    H_DISK_STATUS=warn
    warn "disk: only ${H_DISK_FREE_GB} GB free (${H_DISK_FREE_PCT}%) on $disk_vol — want ≥ ${HEALTH_DISK_MIN_GB} GB and ≥ ${HEALTH_DISK_MIN_PCT}%"
  else
    H_DISK_STATUS=ok
    pass "disk: ${H_DISK_FREE_GB} GB free of ${H_DISK_TOTAL_GB} GB (${H_DISK_FREE_PCT}%)"
  fi
else
  warn "disk: couldn't read free space for $disk_vol (df failed)"
fi

# Uptime: a reboot every couple of weeks lets updates and long-running leaks settle.
CHECKED=$((CHECKED + 1))
boot_sec="$(sysctl -n kern.boottime 2>/dev/null | sed -nE 's/.*[{] sec = ([0-9]+),.*/\1/p')"
if [ -n "$boot_sec" ]; then
  H_UP_DAYS=$(( ($(date +%s) - boot_sec) / 86400 ))
  if [ "$H_UP_DAYS" -gt "$HEALTH_UPTIME_MAX_DAYS" ]; then
    H_UP_STATUS=warn
    warn "uptime ${H_UP_DAYS} days (> ${HEALTH_UPTIME_MAX_DAYS}) — restart when convenient"
  else
    H_UP_STATUS=ok
    pass "uptime ${H_UP_DAYS} day(s)"
  fi
else
  warn "uptime unknown (sysctl kern.boottime failed)"
fi

# Memory: swap in use and the kernel's memory-pressure level (1 normal, 2 warn, 4 critical).
CHECKED=$((CHECKED + 1))
swap_mb="$(sysctl -n vm.swapusage 2>/dev/null | sed -nE 's/.*used = ([0-9.]+)M.*/\1/p')"
[ -n "$swap_mb" ] && H_MEM_SWAP_GB="$(awk -v m="$swap_mb" 'BEGIN { printf "%.1f", m / 1024 }')"
case "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)" in
  1) H_MEM_PRESSURE=normal ;; 2) H_MEM_PRESSURE=warn ;; 4) H_MEM_PRESSURE=critical ;; *) H_MEM_PRESSURE=unknown ;;
esac
H_MEM_FREE_PCT="$(with_timeout 10 memory_pressure -Q 2>/dev/null | sed -nE 's/.*free percentage: ([0-9]+)%.*/\1/p')"
if [ -z "$H_MEM_SWAP_GB" ] && [ "$H_MEM_PRESSURE" = unknown ]; then
  warn "memory: couldn't read swap or memory pressure"
elif [ "$H_MEM_PRESSURE" = critical ] || { [ -n "$H_MEM_SWAP_GB" ] && gb_over "$H_MEM_SWAP_GB" "$HEALTH_SWAP_MAX_GB"; }; then
  H_MEM_STATUS=warn
  warn "memory: pressure $H_MEM_PRESSURE, swap ${H_MEM_SWAP_GB:-?} GB used (> ${HEALTH_SWAP_MAX_GB} GB or critical) — quit heavy apps (Activity Monitor → Memory) or restart"
else
  H_MEM_STATUS=ok
  pass "memory: pressure $H_MEM_PRESSURE, ${H_MEM_FREE_PCT:-?}% free, swap ${H_MEM_SWAP_GB:-?} GB used"
fi

# Storage hogs: allocated sizes, each against its own threshold, with the usual fix.
sto_check() {  # label KiB max_gb fix -> sets sto_gb
  sto_gb=""
  [ -n "$2" ] || return 0
  CHECKED=$((CHECKED + 1))
  sto_gb="$(kb_to_gb "$2")"
  if gb_over "$sto_gb" "$3"; then
    H_STO_STATUS=warn
    warn "$1: ${sto_gb} GB (> $3 GB) — $4"
  else
    pass "$1: ${sto_gb} GB"
  fi
}
sto_check "User caches (~/Library/Caches)" "$(du_kb "$HOME/Library/Caches")" "$HEALTH_CACHES_MAX_GB" \
  "see du -sh ~/Library/Caches/* | sort -h and clear the biggest app caches (quit the app first)"
H_STO_CACHES="$sto_gb"
shopt -s nullglob
docker_raw=("$HOME"/Library/Containers/com.docker.docker/Data/vms/*/data/Docker.raw)
shopt -u nullglob
if [ "${#docker_raw[@]}" -gt 0 ]; then
  sto_check "Docker disk image" "$(du_kb "${docker_raw[@]}")" "$HEALTH_DOCKER_MAX_GB" \
    "docker system prune -a (or Docker Desktop → Troubleshoot → Clean / Purge data)"
  H_STO_DOCKER="$sto_gb"
fi
brew_cache="$(with_timeout 10 brew --cache 2>/dev/null || true)"
if [ -n "$brew_cache" ] && [ -d "$brew_cache" ]; then
  sto_check "Homebrew cache" "$(du_kb "$brew_cache")" "$HEALTH_BREW_CACHE_MAX_GB" "brew cleanup --prune=all"
  H_STO_BREW="$sto_gb"
fi
if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
  sto_check "Xcode DerivedData" "$(du_kb "$HOME/Library/Developer/Xcode/DerivedData")" "$HEALTH_DERIVED_DATA_MAX_GB" \
    "delete ~/Library/Developer/Xcode/DerivedData (Xcode rebuilds it)"
  H_STO_DERIVED="$sto_gb"
fi

fixid security
# Security basics. MDM may manage some of these; unreadable ones are by-hand info lines.
sec_on() {  # label value(on|off|unknown) want(on|off) fix-hint -> echoes nothing
  case "$2" in
    unknown) info "$1: couldn't read — check by hand ($4)" ;;
    "$3")    CHECKED=$((CHECKED + 1)); pass "$1 $2" ;;
    *)       CHECKED=$((CHECKED + 1)); H_SEC_STATUS=warn; warn "$1 $2 (want $3) — $4" ;;
  esac
}
fw="$(with_timeout 5 /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate </dev/null 2>/dev/null || true)"
case "$fw" in
  *"State = 1"*|*"State = 2"*) H_SEC_FIREWALL=on ;;
  *"State = 0"*) H_SEC_FIREWALL=off ;;
esac
sec_on "Application Firewall" "$H_SEC_FIREWALL" on "System Settings → Network → Firewall (may be MDM-managed)"
case "$(with_timeout 5 spctl --status </dev/null 2>&1 || true)" in
  *"assessments enabled"*)  H_SEC_GATEKEEPER=on ;;
  *"assessments disabled"*) H_SEC_GATEKEEPER=off ;;
esac
sec_on "Gatekeeper" "$H_SEC_GATEKEEPER" on "sudo spctl --global-enable"
case "$(with_timeout 5 csrutil status </dev/null 2>&1 || true)" in
  *"status: enabled"*)  H_SEC_SIP=on ;;
  *"status: disabled"*) H_SEC_SIP=off ;;
esac
sec_on "System Integrity Protection" "$H_SEC_SIP" on "re-enable from Recovery: csrutil enable"
# Sharing services, without sudo: a launchd job that's loaded, or a listening port.
listen_ports="$(with_timeout 5 netstat -anp tcp 2>/dev/null | awk '$6 == "LISTEN" {print $4}' || true)"
svc_state() {  # launchd-label port -> on|off
  if with_timeout 5 launchctl print "system/$1" </dev/null >/dev/null 2>&1; then echo on; return; fi
  if printf '%s\n' "$listen_ports" | grep -Eq "[.:]$2\$"; then echo on; return; fi
  echo off
}
H_SEC_SSH="$(svc_state com.openssh.sshd 22)"
sec_on "Remote Login (SSH)" "$H_SEC_SSH" off "System Settings → General → Sharing → Remote Login"
H_SEC_SCREENSHARING="$(svc_state com.apple.screensharing 5900)"
sec_on "Screen Sharing" "$H_SEC_SCREENSHARING" off "System Settings → General → Sharing → Screen Sharing"
H_SEC_FILESHARING="$(svc_state com.apple.smbd 445)"
sec_on "File Sharing" "$H_SEC_FILESHARING" off "System Settings → General → Sharing → File Sharing"
# Password after sleep/screen saver (often MDM-managed). sysadminctl reports on stderr.
sl="$(with_timeout 5 sysadminctl -screenLock status </dev/null 2>&1 || true)"
case "$sl" in
  *"delay is immediate"*) H_SEC_SCREENLOCK=immediate ;;
  *"screenLock is off"*)  H_SEC_SCREENLOCK=off ;;
  *"delay is "*)          H_SEC_SCREENLOCK="$(printf '%s\n' "$sl" | sed -nE 's/.*delay is (.*)$/\1/p' | head -1)" ;;
esac
case "$H_SEC_SCREENLOCK" in
  immediate) CHECKED=$((CHECKED + 1)); pass "password required immediately after sleep / screen saver" ;;
  unknown)   info "screen lock: couldn't read — check by hand (System Settings → Lock Screen; may be MDM-managed)" ;;
  *)         CHECKED=$((CHECKED + 1)); H_SEC_STATUS=warn
             warn "screen lock: password required after '$H_SEC_SCREENLOCK' (want immediately) — System Settings → Lock Screen (may be MDM-managed)" ;;
esac

fixid mdm
# MDM: enrolment (non-sudo `profiles status`) and the Kandji / Iru agent daemons.
prof="$(with_timeout 10 profiles status -type enrollment </dev/null 2>&1 || true)"
case "$prof" in
  *"MDM enrollment: Yes"*) H_MDM_ENROLLED=yes ;;
  *"MDM enrollment: No"*)  H_MDM_ENROLLED=no ;;
esac
mdm_down=""
for mdm_label in io.kandji.kandji-daemon io.kandji.kandji-agent; do
  if ! with_timeout 5 launchctl print "system/$mdm_label" </dev/null 2>/dev/null | grep -q 'state = running'; then
    mdm_down="$mdm_down $mdm_label"
  fi
done
if [ -z "$mdm_down" ]; then H_MDM_AGENT=yes; else H_MDM_AGENT=no; fi
if [ "$H_MDM_ENROLLED" = unknown ]; then
  info "MDM enrolment: couldn't read (profiles status) — check by hand"
  H_MDM_STATUS=unknown
fi
CHECKED=$((CHECKED + 1))
if [ "$H_MDM_ENROLLED" = no ] || [ "$H_MDM_AGENT" = no ]; then
  H_MDM_STATUS=warn
  warn "MDM: enrolled=$H_MDM_ENROLLED, Iru (Kandji) agent not running:${mdm_down:- none} — open Iru Self Service or contact IT"
else
  [ "$H_MDM_ENROLLED" = yes ] && H_MDM_STATUS=ok
  pass "MDM: enrolled=${H_MDM_ENROLLED}, Iru (Kandji) daemon + agent running"
fi

fixid health
# Crashes: kernel panics and app crash reports in the window (lib/crash-reports.py).
CRASH_HELPER="$DOTDIR/lib/crash-reports.py"
if [ -z "$DOT_PYTHON" ] || [ ! -r "$CRASH_HELPER" ]; then
  info "crash reports: needs python3 and lib/crash-reports.py — check by hand (Console → Crash Reports)"
else
  CHECKED=$((CHECKED + 1))
  cr_raw="$(with_timeout 20 "$DOT_PYTHON" "$CRASH_HELPER" "$HEALTH_CRASH_DAYS" 2>/dev/null || true)"
  cr_many=""
  while IFS='|' read -r cr_kind cr_a cr_b cr_c _cr_d; do
    case "$cr_kind" in
      panic)  H_CR_PANIC_FILES+=("$cr_a") ;;
      crash)  H_CR_APPS+=("$cr_a|$cr_b")
              if [ "$cr_b" -ge "$HEALTH_CRASH_SAME_APP" ]; then cr_many="$cr_many, $cr_a ×$cr_b"; fi ;;
      totals) H_CR_PANICS="$cr_a"; H_CR_CRASHES="$cr_b"; H_CR_FAULTS="$cr_c" ;;
    esac
  done <<< "$cr_raw"
  cr_list=""
  for x in ${H_CR_APPS[@]+"${H_CR_APPS[@]}"}; do cr_list="$cr_list, ${x%%|*} ×${x##*|}"; done
  if [ -z "$H_CR_PANICS" ]; then
    H_CR_STATUS=unknown
    warn "crash reports: helper failed — check Console → Crash Reports by hand"
  elif [ "$H_CR_PANICS" -gt 0 ] || [ -n "$cr_many" ]; then
    H_CR_STATUS=warn
    if [ "$H_CR_PANICS" -gt 0 ]; then
      warn "$H_CR_PANICS kernel panic(s) in the last $HEALTH_CRASH_DAYS days: ${H_CR_PANIC_FILES[*]} — see /Library/Logs/DiagnosticReports"
    fi
    if [ -n "$cr_many" ]; then
      warn "apps crashing repeatedly (≥ $HEALTH_CRASH_SAME_APP in $HEALTH_CRASH_DAYS days): ${cr_many#, } — update or reinstall them"
    fi
  else
    H_CR_STATUS=ok
    pass "no kernel panics; $H_CR_CRASHES app crash(es) in $HEALTH_CRASH_DAYS days${cr_list:+ (${cr_list#, })}"
  fi
fi

# Background jobs: every LaunchAgent this repo installs (lib/links.list) is loaded and its
# last run exited 0. The dictation agent's "loaded" state is drift-checked in its own
# section above, so here it only gets the exit-status check. Hammerspoon "running" is the
# Hammerspoon section's result (H_HS_RUNNING), reused for --health-json.
while IFS='|' read -r _la_src la_tgt; do
  case "$la_tgt" in */Library/LaunchAgents/*.plist) ;; *) continue ;; esac
  la_label="$(basename "$la_tgt" .plist)"
  CHECKED=$((CHECKED + 1))
  fixid launchagent "$la_label|${la_tgt//@HOME@/$HOME}"
  if ! la_out="$(with_timeout 5 launchctl print "gui/$(id -u)/$la_label" </dev/null 2>/dev/null)"; then
    H_JOBS+=("$la_label|no|")
    if [ "$la_label" = "$LA_LABEL" ]; then
      CHECKED=$((CHECKED - 1))   # already reported as drift in the Dictation section
    else
      H_JOBS_STATUS=warn; warn "LaunchAgent $la_label not loaded — re-run install.sh"
    fi
    continue
  fi
  la_exit="$(printf '%s\n' "$la_out" | sed -nE 's/^[[:space:]]*last exit code = (.*)$/\1/p' | head -1)"
  case "$la_exit" in
    0)                 H_JOBS+=("$la_label|yes|0"); pass "LaunchAgent $la_label loaded, last exit 0" ;;
    ''|*never*)        H_JOBS+=("$la_label|yes|"); pass "LaunchAgent $la_label loaded (hasn't run yet)" ;;
    *)                 H_JOBS+=("$la_label|yes|$la_exit"); H_JOBS_STATUS=warn; fixid launchagent-exit
                       warn "LaunchAgent $la_label last exit code $la_exit — check: launchctl print gui/$(id -u)/$la_label" ;;
  esac
done < "$DOTDIR/lib/links.list"

fixid dotfiles-git
# Dotfiles in sync: no uncommitted/untracked changes (gitignored .agent-logs etc. don't
# count) and HEAD level with origin/main AS OF THE LAST FETCH/PUSH — no network here, so
# check.sh stays offline and read-only (--no-optional-locks: don't even refresh the index).
CHECKED=$((CHECKED + 1))
if ! git -C "$DOTDIR" rev-parse --git-dir >/dev/null 2>&1; then
  warn "dotfiles: $DOTDIR isn't a git repo"
else
  H_GIT_DIRTY="$(with_timeout 10 git --no-optional-locks -C "$DOTDIR" status --porcelain -- . ':(exclude).agent-logs' 2>/dev/null | grep -c . || true)"
  read -r H_GIT_AHEAD H_GIT_BEHIND < <(with_timeout 10 git -C "$DOTDIR" rev-list --left-right --count HEAD...origin/main 2>/dev/null) || true
  fetch_head="$(git -C "$DOTDIR" rev-parse --git-path FETCH_HEAD 2>/dev/null)"
  case "$fetch_head" in /*) ;; *) fetch_head="$DOTDIR/$fetch_head" ;; esac
  [ -f "$fetch_head" ] && H_GIT_FETCHED="$(date -r "$fetch_head" '+%Y-%m-%d %H:%M %Z')"
  git_issues=""
  [ "${H_GIT_DIRTY:-0}" -gt 0 ] && git_issues="$git_issues; $H_GIT_DIRTY uncommitted/untracked change(s) (dotpush)"
  [ "${H_GIT_AHEAD:-0}" -gt 0 ] && git_issues="$git_issues; $H_GIT_AHEAD commit(s) not pushed (git push)"
  [ "${H_GIT_BEHIND:-0}" -gt 0 ] && git_issues="$git_issues; $H_GIT_BEHIND commit(s) behind origin/main (git pull)"
  if [ -z "${H_GIT_AHEAD:-}" ]; then
    H_GIT_STATUS=warn; warn "dotfiles: no origin/main to compare with${git_issues:+$git_issues}"
  elif [ -n "$git_issues" ]; then
    H_GIT_STATUS=warn; warn "dotfiles out of sync: ${git_issues#; }"
  else
    H_GIT_STATUS=ok
    pass "dotfiles clean and level with origin/main (as of last fetch/push${H_GIT_FETCHED:+; last fetch $H_GIT_FETCHED})"
  fi
fi

fixid login-items
# Login / background items: every ENABLED item must be on lib/login-items-allow.list or
# approved by an MDM Service Management rule; stale items (app gone) are flagged too.
# Reuses lib/btm-login-items.py (same BTM store as the banned-item guard above).
CHECKED=$((CHECKED + 1))
ALLOW_LIST="$DOTDIR/lib/login-items-allow.list"
if [ ! -r "$BTM_HELPER" ] || [ ! -r "$ALLOW_LIST" ] || [ -z "$DOT_PYTHON" ]; then
  fixid tooling; warn "login-item audit skipped (needs python3, lib/btm-login-items.py and lib/login-items-allow.list)"
else
  if li_raw="$(with_timeout 20 "$DOT_PYTHON" "$BTM_HELPER" --audit "$ALLOW_LIST" 2>&1)"; then li_rc=0; else li_rc=$?; fi
  if [ "$li_rc" = 3 ] || printf '%s\n' "$li_raw" | grep -q 'tcc=denied'; then
    fixid tcc; warn "login-item audit: BTM unreadable (Full Disk Access) — System Settings → Privacy & Security → Full Disk Access → enable Ghostty"
  elif [ "$li_rc" -ne 0 ]; then
    warn "login-item audit failed (rc=$li_rc) — check Login Items by hand"
  else
    while IFS='|' read -r li_class li_kind li_name li_dev li_team li_id li_detail; do
      case "$li_class" in
        allow)   H_LI_ENABLED=$((H_LI_ENABLED + 1)); H_LI_ALLOW=$((H_LI_ALLOW + 1)) ;;
        mdm)     H_LI_ENABLED=$((H_LI_ENABLED + 1)); H_LI_MDM=$((H_LI_MDM + 1)) ;;
        unknown)
          H_LI_ENABLED=$((H_LI_ENABLED + 1)); H_LI_UNKNOWN+=("$li_name ($li_kind, $li_id)")
          warn "unexpected login item: $li_name ($li_kind; ${li_dev:-unknown developer}${li_team:+, team $li_team}; $li_id) — turn it Off in System Settings → General → Login Items & Extensions, or add it to lib/login-items-allow.list" ;;
        stale)
          H_LI_ENABLED=$((H_LI_ENABLED + 1)); H_LI_STALE+=("$li_name ($li_id): $li_detail")
          warn "stale login item: $li_name ($li_id) $li_detail — remove it in System Settings → General → Login Items & Extensions (re-add the app if you still want it at login)" ;;
        allowlist:*) warn "lib/login-items-allow.list: ${li_class#allowlist: }" ;;
      esac
    done <<< "$li_raw"
    if [ "${#H_LI_UNKNOWN[@]}" -eq 0 ] && [ "${#H_LI_STALE[@]}" -eq 0 ]; then
      H_LI_STATUS=ok
      pass "login items: all $H_LI_ENABLED enabled items expected ($H_LI_ALLOW allow-listed, $H_LI_MDM MDM-approved)"
    else
      H_LI_STATUS=warn
    fi
  fi
fi

# ---- 16. Manual steps (permissions, sign-ins, by-hand settings) -----------
# lib/manual-steps.list is the single source of truth; scripts/manual-steps.sh runs the
# read-only checks. A failed check is a soft warning (a manual step, not repo drift);
# steps with no reliable check are info lines; steps marked @check.sh are verified by
# their own section above, so they're not repeated here.
hdr "Manual steps (lib/manual-steps.list)"
fixid manual-step
MANUAL_STEPS="$DOTDIR/scripts/manual-steps.sh"
if [ ! -x "$MANUAL_STEPS" ]; then
  CHECKED=$((CHECKED + 1))
  fixid repo-file; warn "scripts/manual-steps.sh missing or not executable — skipping manual steps"
else
  ms_out="$(NO_COLOR=1 "$MANUAL_STEPS" check --porcelain 2>&1)" || true
  while IFS='|' read -r ms_status ms_num _ms_id ms_title ms_detail; do
    case "$ms_status" in
      ok)      CHECKED=$((CHECKED + 1)); pass "$ms_num. $ms_title${ms_detail:+ — $ms_detail}" ;;
      warn)    CHECKED=$((CHECKED + 1)); warn "$ms_num. $ms_title — $ms_detail (scripts/manual-steps.sh open)" ;;
      hand)    info "$ms_num. $ms_title — check by hand${ms_detail:+ ($ms_detail)}" ;;
      covered|'') : ;;
      *)       CHECKED=$((CHECKED + 1)); warn "manual-steps.sh: $ms_status${ms_num:+|$ms_num}" ;;
    esac
  done <<< "$ms_out"
fi

# ---- --fix: apply the SAFE fixes, re-check, report ------------------------
# lib/autofix.list is the one place that says what's SAFE (reversible preference writes,
# done by the existing setters) and what Needs Paul (report only). Nothing here uses sudo,
# deletes files, or touches apps, login items, permissions, MDM or git.
FIXED=(); NEEDS_PAUL=(); WOULD_FIX=(); LOGOUT_NEEDED=()
AFTER_DRIFT="$DRIFT"; AFTER_WARN="$WARN"
if [ "$FIX" = 1 ]; then
  require_file "$DOTDIR/lib/autofix.list"
  require_file "$DOTDIR/lib/autofix-lib.sh"
  # shellcheck source=lib/autofix-lib.sh disable=SC1091
  . "$DOTDIR/lib/autofix-lib.sh"
  AUTOFIX_LIST="$DOTDIR/lib/autofix.list"
  FIX_LOG="$HOME/Library/Logs/com.pdone.check-fix.log"
  fix_log() {
    mkdir -p "$(dirname "$FIX_LOG")"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$FIX_LOG"
  }
  if [ "$DRY_RUN" = 1 ]; then
    hdr "Fix — dry run (nothing is changed)"
  else
    hdr "Fix (SAFE fixes from lib/autofix.list)"
    fix_log "check.sh --fix started ($DRIFT drift, $WARN warning(s))"
  fi

  # Fixers. Each prints one line saying what it did (or would do) and returns 0 = done /
  # would do, 1 = tried and failed, 2 = refused as unsafe right now. All idempotent.
  fix_symlink() {  # "target|repo-source"
    local target="${1%%|*}" src="${1#*|}"
    if [ ! -e "$src" ]; then
      echo "repo source ${src/#$HOME/~} is missing — restore it from git"; return 2
    fi
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      echo "a real file is in the way at ${target/#$HOME/~} — never overwritten; move it aside, then run install.sh (it backs real files up)"; return 2
    fi
    if [ "$DRY_RUN" = 1 ]; then echo "would link ${target/#$HOME/~} -> repo"; return 0; fi
    if mkdir -p "$(dirname "$target")" && ln -sfn "$src" "$target"; then
      echo "linked ${target/#$HOME/~} -> repo"; return 0
    fi
    echo "ln -sfn failed for ${target/#$HOME/~}"; return 1
  }
  fix_launchagent() {  # "label|plist"
    local label="${1%%|*}" plist="${1#*|}" out
    if [ "$DRY_RUN" = 1 ]; then
      echo "would load LaunchAgent $label (scripts/load-launchagent.sh)"; return 0
    fi
    if out="$("$DOTDIR/scripts/load-launchagent.sh" "$plist" 2>&1)"; then
      echo "LaunchAgent $out"; return 0
    fi
    echo "LaunchAgent $label: ${out:-load failed}"; return 1
  }
  fix_hammerspoon() {
    local i=0
    if [ ! -d /Applications/Hammerspoon.app ]; then
      echo "Hammerspoon.app not installed — brew bundle"; return 2
    fi
    if pgrep -xq Hammerspoon; then echo "Hammerspoon already running"; return 0; fi
    if [ "$DRY_RUN" = 1 ]; then echo "would start Hammerspoon (open -g -a Hammerspoon)"; return 0; fi
    open -g -a Hammerspoon 2>/dev/null || true
    while [ "$i" -lt 15 ] && ! pgrep -xq Hammerspoon; do sleep 1; i=$((i + 1)); done
    if pgrep -xq Hammerspoon; then echo "started Hammerspoon"; return 0; fi
    echo "open -a Hammerspoon didn't start it"; return 1
  }

  # Classify every drift / warning. SAFE items are de-duplicated on id|arg.
  SAFE_ITEMS=()                 # "id US arg US message US fixer"
  MACOS_ARGS=()                 # macos.sh --only … arguments (one batched call)
  DESKTOP_ONLY=""               # bundle ids for one batched desktop-bindings.py --apply
  FILE_ONLY=""                  # extensions for one batched file-handlers.py --apply
  safe_seen="$US"
  for it in ${FIX_ITEMS[@]+"${FIX_ITEMS[@]}"}; do
    IFS="$US" read -r _it_kind it_id it_arg it_msg <<< "$it"
    lookup="$(autofix_lookup "$AUTOFIX_LIST" "$it_id")"
    it_cls="${lookup%%|*}"; it_rest="${lookup#*|}"; it_fixer="${it_rest%%|*}"; it_why="${it_rest#*|}"
    if [ "$it_cls" != SAFE ]; then
      NEEDS_PAUL+=("$it_msg — $it_why")
      continue
    fi
    case "$safe_seen" in *"$US$it_id|$it_arg$US"*) continue ;; esac
    safe_seen="$safe_seen$it_id|$it_arg$US"
    SAFE_ITEMS+=("$it_id$US$it_arg$US$it_msg$US$it_fixer")
    if [ "$it_fixer" = macos ]; then
      if [ "$it_id" = defaults ]; then MACOS_ARGS+=(--only "$it_arg"); else MACOS_ARGS+=(--only "@$it_id"); fi
    elif [ "$it_fixer" = desktop ] && [ -n "$it_arg" ]; then
      DESKTOP_ONLY="${DESKTOP_ONLY:+$DESKTOP_ONLY,}$it_arg"
    elif [ "$it_fixer" = fileext ] && [ -n "$it_arg" ]; then
      FILE_ONLY="${FILE_ONLY:+$FILE_ONLY,}$it_arg"
    fi
  done

  # Run the fixers in dependency order: symlinks (a LaunchAgent plist may be one), then one
  # batched macos.sh call (one backup, at most one restart per process), then one batched
  # desktop-bindings.py --apply (one backup, one Dock restart), then one batched
  # file-handlers.py --apply (duti -s for each drifted extension), then LaunchAgents and
  # Hammerspoon. FIX_RESULTS[n] = "rc US what happened" for SAFE_ITEMS[n].
  FIX_RESULTS=()
  MACOS_OUT=""
  macos_line() {  # id arg — this item's chg / warn / ok line from the macos.sh output
    local pat=""
    case "$1" in
      defaults)         pat="${2%%|*} ${2#*|} —" ;;
      dictation-164)    pat="dictation hotkey 164" ;;
      quicknote-190)    pat="Quick Note hotkey 190" ;;
      coteditor)        pat="CotEditor" ;;
      finder-recents)   pat="Finder sidebar Recents" ;;
      finder-icon-view) pat="Finder icon view defaults" ;;
    esac
    printf '%s\n' "$MACOS_OUT" | grep -F -- "$pat" | grep -E '^  (chg|warn|ok) ' | head -1 | sed -E 's/^ +(chg|warn|ok) +//'
  }
  run_fix() {  # fixer arg id — dispatch to the fixer; prints its line, returns its status
    local ml rest
    case "$1" in
      symlink)     fix_symlink "$2" ;;
      launchagent) fix_launchagent "$2" ;;
      hammerspoon) fix_hammerspoon ;;
      desktop)
        ml="$(printf '%s\n' "$DESKTOP_OUT" | awk -F'|' -v b="$2" '$2 == b { print; exit }')"
        if [ -z "$ml" ]; then echo "desktop-bindings.py printed nothing for this item"; return 1; fi
        rest="${ml#*|}"; rest="${rest#*|}"
        echo "desktop: $rest"
        case "${ml%%|*}" in
          chg|ok|dry) return 0 ;;
          refuse) return 2 ;;
          *) return 1 ;;
        esac
        ;;
      fileext)
        ml="$(printf '%s\n' "$FILE_OUT" | awk -F'|' -v e="$2" '$2 == e { print; exit }')"
        if [ -z "$ml" ]; then echo "file-handlers.py printed nothing for this item"; return 1; fi
        rest="${ml#*|}"; rest="${rest#*|}"
        echo "fileext: $rest"
        case "${ml%%|*}" in
          chg|ok|dry) return 0 ;;
          refuse) return 2 ;;
          *) return 1 ;;
        esac
        ;;
      macos)
        ml="$(macos_line "$3" "$2")"
        if [ -z "$ml" ]; then echo "macos.sh printed nothing for this item"; return 1; fi
        echo "macos.sh: $ml"
        if printf '%s\n' "$MACOS_OUT" | grep -F -- "$ml" | grep -q '^  warn '; then return 1; fi ;;
      *) echo "unknown fixer '$1' in lib/autofix.list"; return 2 ;;
    esac
  }
  fix_pass() {  # fixer... — run the SAFE items whose fixer is one of these
    local n=0 item f id arg _msg fixer out rc
    for item in ${SAFE_ITEMS[@]+"${SAFE_ITEMS[@]}"}; do
      IFS="$US" read -r id arg _msg fixer <<< "$item"
      for f in "$@"; do
        if [ "$fixer" = "$f" ]; then
          if out="$(run_fix "$fixer" "$arg" "$id")"; then rc=0; else rc=$?; fi
          FIX_RESULTS[n]="$rc$US$out"
        fi
      done
      n=$((n + 1))
    done
  }
  fix_pass symlink
  if [ "${#MACOS_ARGS[@]}" -gt 0 ]; then
    if [ "$DRY_RUN" = 1 ]; then
      MACOS_OUT="$("$DOTDIR/macos.sh" --dry-run --no-color "${MACOS_ARGS[@]}" 2>&1)" || true
    else
      MACOS_OUT="$("$DOTDIR/macos.sh" --no-color --yes "${MACOS_ARGS[@]}" 2>&1)" || true
      while IFS= read -r ml; do
        if [ -n "$ml" ]; then fix_log "macos.sh: $ml"; fi
      done <<< "$MACOS_OUT"
    fi
    printf '%s\n' "$MACOS_OUT" | sed '/^$/d; s/^/        /'
    # "logout"-class settings: macos.sh lists them after its Note line.
    while IFS= read -r ml; do
      LOGOUT_NEEDED+=("${ml#  - }")
    done < <(printf '%s\n' "$MACOS_OUT" | awk '/^Note: the following changed/ {grab=1; next} grab && /^  - / {print}')
  fi
  # One apply for every drifted bundle: resolve Desktop N → current Space UUID,
  # write app-bindings, restart Dock once. DESKTOP_OUT is status|bundle|message.
  DESKTOP_OUT=""
  if [ -n "$DESKTOP_ONLY" ]; then
    if ! desk_py="$(dot_python)"; then
      while IFS= read -r b; do
        [ -n "$b" ] || continue
        DESKTOP_OUT="${DESKTOP_OUT}fail|${b}|python3 not found — desktop assignment not changed"$'\n'
      done < <(printf '%s\n' "$DESKTOP_ONLY" | tr ',' '\n')
    else
      desk_cmd=("$desk_py" "$DOTDIR/lib/desktop-bindings.py" --apply)
      if [ "$DRY_RUN" = 1 ]; then desk_cmd+=(--dry-run); fi
      desk_cmd+=(--only "$DESKTOP_ONLY" "$DOTDIR/lib/desktop-bindings.list")
      DESKTOP_OUT="$("${desk_cmd[@]}" 2>&1)" || true
      if [ "$DRY_RUN" != 1 ]; then
        while IFS= read -r dl; do
          if [ -n "$dl" ]; then fix_log "desktop: $dl"; fi
        done <<< "$DESKTOP_OUT"
      fi
    fi
    printf '%s\n' "$DESKTOP_OUT" | awk -F'|' 'NF >= 3 && $3 != "" { print "        " $3 }'
  fi
  # One apply for every drifted extension: `duti -s <bundle> .<ext> all`.
  # FILE_OUT is status|ext|message.
  FILE_OUT=""
  if [ -n "$FILE_ONLY" ]; then
    if ! file_py="$(dot_python)"; then
      while IFS= read -r e; do
        [ -n "$e" ] || continue
        FILE_OUT="${FILE_OUT}fail|${e}|python3 not found — file handler not changed"$'\n'
      done < <(printf '%s\n' "$FILE_ONLY" | tr ',' '\n')
    elif ! command -v duti >/dev/null 2>&1; then
      while IFS= read -r e; do
        [ -n "$e" ] || continue
        FILE_OUT="${FILE_OUT}fail|${e}|duti not installed — file handler not changed"$'\n'
      done < <(printf '%s\n' "$FILE_ONLY" | tr ',' '\n')
    else
      file_cmd=("$file_py" "$DOTDIR/lib/file-handlers.py" --apply)
      if [ "$DRY_RUN" = 1 ]; then file_cmd+=(--dry-run); fi
      file_cmd+=(--only "$FILE_ONLY" "$DOTDIR/lib/file-handlers.list")
      FILE_OUT="$("${file_cmd[@]}" 2>&1)" || true
      if [ "$DRY_RUN" != 1 ]; then
        while IFS= read -r fl; do
          if [ -n "$fl" ]; then fix_log "fileext: $fl"; fi
        done <<< "$FILE_OUT"
      fi
    fi
    printf '%s\n' "$FILE_OUT" | awk -F'|' 'NF >= 3 && $3 != "" { print "        " $3 }'
  fi
  fix_pass macos desktop fileext launchagent hammerspoon
  # Items with a fixer name the dispatcher doesn't know (a typo in lib/autofix.list).
  n=0
  for item in ${SAFE_ITEMS[@]+"${SAFE_ITEMS[@]}"}; do
    if [ -z "${FIX_RESULTS[n]:-}" ]; then
      IFS="$US" read -r _id _arg _msg fx <<< "$item"
      FIX_RESULTS[n]="2${US}unknown fixer '$fx' in lib/autofix.list"
    fi
    n=$((n + 1))
  done

  # Report each SAFE item's outcome; on a real run, re-check to see what stuck.
  RECHECK=""
  if [ "$DRY_RUN" != 1 ] && [ "${#SAFE_ITEMS[@]}" -gt 0 ]; then
    RECHECK="$("$DOTDIR/check.sh" --issues 2>/dev/null)" || true
    AFTER_DRIFT=0; AFTER_WARN=0
    while IFS="$US" read -r rk _ri _ra _rm; do
      case "$rk" in drift) AFTER_DRIFT=$((AFTER_DRIFT + 1)) ;; warn) AFTER_WARN=$((AFTER_WARN + 1)) ;; esac
    done <<< "$RECHECK"
  fi
  i=0
  for item in ${SAFE_ITEMS[@]+"${SAFE_ITEMS[@]}"}; do
    IFS="$US" read -r it_id it_arg it_msg it_fixer <<< "$item"
    fr="${FIX_RESULTS[i]}"; fr_rc="${fr%%"$US"*}"; fr_out="${fr#*"$US"}"
    i=$((i + 1))
    if [ "$fr_rc" = 2 ]; then
      NEEDS_PAUL+=("$it_msg — not auto-fixed: $fr_out")
      [ "$DRY_RUN" = 1 ] || fix_log "refused: $it_msg — $fr_out"
      continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
      WOULD_FIX+=("$it_msg → $fr_out")
      continue
    fi
    still="$(printf '%s\n' "$RECHECK" | awk -F"$US" -v id="$it_id" -v arg="$it_arg" '$2 == id && $3 == arg {print $4; exit}')"
    if [ -n "$still" ]; then
      NEEDS_PAUL+=("$it_msg — fix didn't stick (still: $still; $fr_out)")
      fix_log "did not stick: $it_msg — still: $still ($fr_out)"
    elif [ "$fr_rc" = 0 ]; then
      FIXED+=("$it_msg → $fr_out")
      fix_log "fixed: $it_msg → $fr_out"
    else
      NEEDS_PAUL+=("$it_msg — fix failed: $fr_out")
      fix_log "failed: $it_msg — $fr_out"
    fi
  done

  if [ "$DRY_RUN" = 1 ]; then
    printf '\n  Would fix (%d):\n' "${#WOULD_FIX[@]}"
    for x in ${WOULD_FIX[@]+"${WOULD_FIX[@]}"}; do printf '    - %s\n' "$x"; done
    if [ "${#WOULD_FIX[@]}" -eq 0 ]; then printf '    (nothing — no SAFE drift)\n'; fi
  else
    printf '\n  Fixed (%d):\n' "${#FIXED[@]}"
    for x in ${FIXED[@]+"${FIXED[@]}"}; do printf '    - %s\n' "$x"; done
    if [ "${#FIXED[@]}" -eq 0 ]; then printf '    (nothing to fix)\n'; fi
  fi
  printf '\n  Needs Paul (%d):\n' "${#NEEDS_PAUL[@]}"
  for x in ${NEEDS_PAUL[@]+"${NEEDS_PAUL[@]}"}; do printf '    - %s\n' "$x"; done
  if [ "${#NEEDS_PAUL[@]}" -eq 0 ]; then printf '    (nothing)\n'; fi
  if [ "${#LOGOUT_NEEDED[@]}" -gt 0 ]; then
    printf '\n  Log out and back in to finish applying: %s\n' "$(printf '%s; ' "${LOGOUT_NEEDED[@]}" | sed 's/; $//')"
  fi
  if [ "$DRY_RUN" != 1 ]; then
    fix_log "check.sh --fix done: ${#FIXED[@]} fixed, ${#NEEDS_PAUL[@]} need Paul; after: $AFTER_DRIFT drift, $AFTER_WARN warning(s)"
  fi
fi

# ---- summary ------------------------------------------------------------
# A few aligned lines, then a one-line verdict. Colour only on a tty (C_* are empty
# under --no-color / NO_COLOR / when piped). Nothing parses this text: machines use
# --health-json (unchanged).
SUM_NW=${#CHECKED}                      # number column width = widest count
for n in "$DRIFT" "$WARN" "$HAND" "${#FIXED[@]}" "${#NEEDS_PAUL[@]}" "${#WOULD_FIX[@]}"; do
  if [ "${#n}" -gt "$SUM_NW" ]; then SUM_NW=${#n}; fi
done
# sum_row GLYPH GLYPH-CELLS LABEL COUNT COLOUR [SUFFIX] — zero counts are dimmed.
sum_row() {
  local col="$5" lw=12
  if [ "$4" = 0 ]; then col="$C_DIM"; fi
  lw=$((lw - $2 + 1))                   # a 2-cell (emoji) glyph eats one pad space
  printf '  %s%s %-*s %*s%s%s\n' "$col" "$1" "$lw" "$3" "$SUM_NW" "$4" "${6:-}" "$C_OFF"
}
S_DRIFT="$AFTER_DRIFT"; S_WARN="$AFTER_WARN"; S_DRIFT_NOTE=""; S_WARN_NOTE=""
if [ "$FIX" = 1 ] && [ "$DRY_RUN" != 1 ]; then   # after --fix: what's left, and what it was
  if [ "$S_DRIFT" != "$DRIFT" ]; then S_DRIFT_NOTE="   (was $DRIFT before --fix)"; fi
  if [ "$S_WARN" != "$WARN" ]; then S_WARN_NOTE="   (was $WARN before --fix)"; fi
fi
S_OK_COL="$C_OK"; if [ "$OKS" != "$CHECKED" ]; then S_OK_COL=""; fi

printf '\n%sSummary%s\n' "$C_HDR" "$C_OFF"
sum_row "✔" 1 "ok"       "$OKS"     "$S_OK_COL" " / $CHECKED"
sum_row "✖" 1 "drift"    "$S_DRIFT" "$C_BAD"    "$S_DRIFT_NOTE"
sum_row "⚠" 1 "warnings" "$S_WARN"  "$C_WARN"   "$S_WARN_NOTE"
sum_row "✋" 2 "by hand"  "$HAND"    ""         "   (scripts/manual-steps.sh list)"
if [ "$FIX" = 1 ]; then
  if [ "$DRY_RUN" = 1 ]; then
    sum_row "↻" 1 "would fix" "${#WOULD_FIX[@]}" "$C_OK" "   (dry run: nothing changed)"
  else
    sum_row "↻" 1 "fixed"     "${#FIXED[@]}" "$C_OK"
  fi
  sum_row "☞" 1 "needs Paul" "${#NEEDS_PAUL[@]}" "$C_WARN"
else
  # How many of today's issues `--fix` would repair (SAFE rows of lib/autofix.list).
  S_SAFE=0
  if [ "${#FIX_ITEMS[@]}" -gt 0 ] && [ -r "$DOTDIR/lib/autofix-lib.sh" ] && [ -r "$DOTDIR/lib/autofix.list" ]; then
    # shellcheck source=lib/autofix-lib.sh disable=SC1091
    . "$DOTDIR/lib/autofix-lib.sh"
    for it in "${FIX_ITEMS[@]}"; do
      IFS="$US" read -r _ it_id _ _ <<< "$it"
      if [ "$(autofix_class "$DOTDIR/lib/autofix.list" "$it_id")" = SAFE ]; then S_SAFE=$((S_SAFE + 1)); fi
    done
  fi
  if [ "$S_SAFE" -gt 0 ]; then
    printf '  %s→ run ./check.sh --fix to repair %d safe item(s)%s\n' "$C_OK" "$S_SAFE" "$C_OFF"
  fi
fi
S_ATTN=$((S_DRIFT + S_WARN))
if [ "$S_ATTN" -eq 0 ]; then
  printf '  %sAll good%s\n' "$C_OK$C_HDR" "$C_OFF"
else
  S_VCOL="$C_WARN"; if [ "$S_DRIFT" -gt 0 ]; then S_VCOL="$C_BAD"; fi
  S_NEED="need"; if [ "$S_ATTN" -eq 1 ]; then S_NEED="needs"; fi
  S_WHAT=""
  if [ "$S_DRIFT" -gt 0 ]; then S_WHAT="$S_DRIFT drift"; fi
  if [ "$S_WARN" -gt 0 ]; then
    S_W="warnings"; if [ "$S_WARN" -eq 1 ]; then S_W="warning"; fi
    S_WHAT="${S_WHAT:+$S_WHAT, }$S_WARN $S_W"
  fi
  printf '  %s%d %s attention%s (%s)\n' "$S_VCOL$C_HDR" "$S_ATTN" "$S_NEED" "$C_OFF" "$S_WHAT"
fi

# ---- --issues (internal; used by --fix to re-check) ----------------------
if [ "$ISSUES" = 1 ]; then
  for it in ${FIX_ITEMS[@]+"${FIX_ITEMS[@]}"}; do printf '%s\n' "$it"; done >&3
fi

# ---- --health-json -------------------------------------------------------
if [ "$HEALTH_JSON" = 1 ]; then
  json_str() {  # JSON string literal (escapes \ " and control characters)
    local v="$1"
    v="${v//\\/\\\\}"; v="${v//\"/\\\"}"
    v="${v//$'\n'/\\n}"; v="${v//$'\t'/\\t}"; v="${v//$'\r'/\\r}"
    printf '"%s"' "$v"
  }
  json_num() { case "$1" in ''|*[!0-9]*) printf 'null' ;; *) printf '%s' "$1" ;; esac; }
  json_opt() { if [ -n "$1" ]; then json_str "$1"; else printf 'null'; fi; }
  json_dec() { if printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then printf '%s' "$1"; else printf 'null'; fi; }
  json_crash_apps() {  # "app|count"... -> {"app": count, ...}
    local first=1 x
    printf '{'
    for x in "$@"; do
      [ "$first" = 1 ] || printf ', '
      first=0; printf '%s: %s' "$(json_str "${x%|*}")" "$(json_num "${x##*|}")"
    done
    printf '}'
  }
  json_jobs() {  # "label|loaded(yes/no)|last_exit"... -> [{...}, ...]
    local first=1 x label rest loaded ex jb
    printf '['
    for x in "$@"; do
      label="${x%%|*}"; rest="${x#*|}"; loaded="${rest%%|*}"; ex="${rest#*|}"
      [ "$first" = 1 ] || printf ', '
      first=0
      jb=false
      if [ "$loaded" = yes ]; then jb=true; fi
      printf '{"label": %s, "loaded": %s, "last_exit": %s}' "$(json_str "$label")" \
        "$jb" "$(json_num "$ex")"
    done
    printf ']'
  }
  json_arr() {  # json_arr item... -> ["a","b"]
    local first=1 x
    printf '['
    for x in "$@"; do
      [ "$first" = 1 ] || printf ','
      first=0; json_str "$x"
    done
    printf ']'
  }
  {
    printf '{\n'
    printf '  "generated": %s,\n' "$(json_str "$(date '+%Y-%m-%dT%H:%M:%S%z')")"
    printf '  "host": %s,\n' "$(json_str "$(scutil --get ComputerName 2>/dev/null || hostname)")"
    printf '  "summary": {"checked": %d, "ok": %d, "drift": %d, "warnings": %d, "by_hand": %d},\n' \
      "$CHECKED" "$OKS" "$DRIFT" "$WARN" "$HAND"
    printf '  "battery": {"status": %s, "condition": %s, "max_capacity_pct": %s, "cycle_count": %s},\n' \
      "$(json_str "$H_BAT_STATUS")" "$(json_opt "$H_BAT_COND")" "$(json_num "$H_BAT_MAX")" "$(json_num "$H_BAT_CYCLES")"
    printf '  "disk": {"status": %s, "free_gb": %s, "free_pct": %s, "total_gb": %s},\n' \
      "$(json_str "$H_DISK_STATUS")" "$(json_num "$H_DISK_FREE_GB")" "$(json_num "$H_DISK_FREE_PCT")" "$(json_num "$H_DISK_TOTAL_GB")"
    printf '  "uptime": {"status": %s, "days": %s},\n' "$(json_str "$H_UP_STATUS")" "$(json_num "$H_UP_DAYS")"
    printf '  "memory": {"status": %s, "pressure": %s, "free_pct": %s, "swap_used_gb": %s},\n' \
      "$(json_str "$H_MEM_STATUS")" "$(json_str "$H_MEM_PRESSURE")" "$(json_num "$H_MEM_FREE_PCT")" "$(json_dec "$H_MEM_SWAP_GB")"
    printf '  "storage": {"status": %s, "caches_gb": %s, "docker_gb": %s, "brew_cache_gb": %s, "derived_data_gb": %s},\n' \
      "$(json_str "$H_STO_STATUS")" "$(json_dec "$H_STO_CACHES")" "$(json_dec "$H_STO_DOCKER")" "$(json_dec "$H_STO_BREW")" "$(json_dec "$H_STO_DERIVED")"
    printf '  "security": {"status": %s, "firewall": %s, "gatekeeper": %s, "sip": %s, "remote_login": %s, "screen_sharing": %s, "file_sharing": %s, "screen_lock": %s},\n' \
      "$(json_str "$H_SEC_STATUS")" "$(json_str "$H_SEC_FIREWALL")" "$(json_str "$H_SEC_GATEKEEPER")" "$(json_str "$H_SEC_SIP")" \
      "$(json_str "$H_SEC_SSH")" "$(json_str "$H_SEC_SCREENSHARING")" "$(json_str "$H_SEC_FILESHARING")" "$(json_str "$H_SEC_SCREENLOCK")"
    printf '  "mdm": {"status": %s, "enrolled": %s, "agent_running": %s},\n' \
      "$(json_str "$H_MDM_STATUS")" "$(json_str "$H_MDM_ENROLLED")" "$(json_str "$H_MDM_AGENT")"
    printf '  "crashes": {"status": %s, "days": %s, "kernel_panics": %s, "app_crashes": %s, "user_faults": %s, "by_app": %s, "panic_files": %s},\n' \
      "$(json_str "$H_CR_STATUS")" "$(json_num "$HEALTH_CRASH_DAYS")" "$(json_num "$H_CR_PANICS")" "$(json_num "$H_CR_CRASHES")" "$(json_num "$H_CR_FAULTS")" \
      "$(json_crash_apps ${H_CR_APPS[@]+"${H_CR_APPS[@]}"})" "$(json_arr ${H_CR_PANIC_FILES[@]+"${H_CR_PANIC_FILES[@]}"})"
    printf '  "background_jobs": {"status": %s, "hammerspoon_running": %s, "launch_agents": %s},\n' \
      "$(json_str "$H_JOBS_STATUS")" "$(json_str "$H_HS_RUNNING")" "$(json_jobs ${H_JOBS[@]+"${H_JOBS[@]}"})"
    printf '  "dotfiles": {"status": %s, "uncommitted": %s, "ahead": %s, "behind": %s, "last_fetch": %s},\n' \
      "$(json_str "$H_GIT_STATUS")" "$(json_num "$H_GIT_DIRTY")" "$(json_num "$H_GIT_AHEAD")" "$(json_num "$H_GIT_BEHIND")" "$(json_opt "$H_GIT_FETCHED")"
    printf '  "login_items": {"status": %s, "enabled": %d, "allow_listed": %d, "mdm_approved": %d, "unknown": %s, "stale": %s},\n' \
      "$(json_str "$H_LI_STATUS")" "$H_LI_ENABLED" "$H_LI_ALLOW" "$H_LI_MDM" \
      "$(json_arr ${H_LI_UNKNOWN[@]+"${H_LI_UNKNOWN[@]}"})" "$(json_arr ${H_LI_STALE[@]+"${H_LI_STALE[@]}"})"
    if [ "$FIX" = 1 ]; then
      if [ "$DRY_RUN" = 1 ]; then fix_mode=dry-run; else fix_mode=apply; fi
      printf '  "fix": {"mode": %s, "after": {"drift": %d, "warnings": %d}},\n' "$(json_str "$fix_mode")" "$AFTER_DRIFT" "$AFTER_WARN"
      printf '  "fixed": %s,\n' "$(json_arr ${FIXED[@]+"${FIXED[@]}"})"
      printf '  "would_fix": %s,\n' "$(json_arr ${WOULD_FIX[@]+"${WOULD_FIX[@]}"})"
      printf '  "needs_paul": %s,\n' "$(json_arr ${NEEDS_PAUL[@]+"${NEEDS_PAUL[@]}"})"
      printf '  "logout_needed": %s,\n' "$(json_arr ${LOGOUT_NEEDED[@]+"${LOGOUT_NEEDED[@]}"})"
    fi
    printf '  "drift_messages": %s,\n' "$(json_arr ${DRIFT_MSGS[@]+"${DRIFT_MSGS[@]}"})"
    printf '  "warning_messages": %s\n' "$(json_arr ${WARN_MSGS[@]+"${WARN_MSGS[@]}"})"
    printf '}\n'
  } >&3
fi

# With --fix (not a dry run) the exit status reflects the drift left after the fixes.
if [ "$AFTER_DRIFT" -gt 0 ]; then exit 1; fi
exit 0
