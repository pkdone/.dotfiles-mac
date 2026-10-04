#!/usr/bin/env bash
#
# check.sh — read-only verifier. Reports drift between this machine and the repo's
# desired state WITHOUT changing anything. Exits non-zero if any drift is found, so
# it's usable in a pre-push hook or CI later.
#
# Sections: symlinks, Homebrew (Brewfile + cleanup extras), macOS defaults, Dock, Dock desktop assignments, login shell, hostname, URL handlers, unwanted apps, dictation shortcut + login LaunchAgent, Finder icon view defaults, Karabiner Fn-kill + Finder Trash, Hammerspoon (running), login items guard, Finder Recents, CotEditor, MDM apps, leftover *.app.back, security hygiene (FileVault / softwareupdate), Mac health (battery, disk, Time Machine, uptime, unexpected login items), manual steps (scripts/manual-steps.sh check: permissions, sign-ins, by-hand settings).
# Reuses lib/macos-defaults.list, lib/dock-apps.list, lib/desktop-bindings.list, lib/hostname and lib/defaults-lib.sh
# so the verify path uses the exact same data and comparison semantics as the apply path
# (macos.sh / dock.sh) and the two can never drift.
#
# Flags:
#   --no-color     Disable ANSI colour (also honours the NO_COLOR env var).
#   --health-json  Print only a JSON summary (Mac health values, drift/warning counts and
#                  messages) on stdout, for the weekly health note. Same checks, same exit.
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

for arg in "$@"; do
  case "$arg" in
    --no-color) NO_COLOR_OPT=1 ;;
    --health-json) HEALTH_JSON=1 ;;
    -h|--help)
      cat <<'USAGE'
Usage: check.sh [--no-color] [--health-json]
  Read-only. Reports drift between this machine and the repo; writes nothing.
  Exit status: 0 = everything matches, 1 = drift found.
  --no-color     Disable ANSI colour (also honours the NO_COLOR env var).
  --health-json  Print only a JSON summary on stdout (Mac health values, drift and
                 warning counts and messages) for the weekly health note.
  -h, --help     Show this help.
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# --health-json: keep the JSON alone on stdout (fd 3); the human report goes nowhere.
if [ "$HEALTH_JSON" = 1 ]; then
  exec 3>&1 1>/dev/null
  NO_COLOR_OPT=1
fi

# ---- logging (colour only on a tty) -------------------------------------
if [ -t 1 ] && [ "$NO_COLOR_OPT" != 1 ] && [ -z "${NO_COLOR+x}" ]; then
  C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_WARN=$'\033[33m'; C_HDR=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_OK=''; C_BAD=''; C_WARN=''; C_HDR=''; C_OFF=''
fi

CHECKED=0; OKS=0; DRIFT=0; WARN=0; HAND=0
DRIFT_MSGS=(); WARN_MSGS=()   # kept for --health-json
pass() { OKS=$((OKS + 1));    printf '  %sok%s    %s\n'  "$C_OK"   "$C_OFF" "$1"; }
bad()  { DRIFT=$((DRIFT + 1)); DRIFT_MSGS+=("$1"); printf '  %sDRIFT%s %s\n' "$C_BAD"  "$C_OFF" "$1"; }
warn() { WARN=$((WARN + 1));   WARN_MSGS+=("$1");  printf '  %swarn%s  %s\n'  "$C_WARN" "$C_OFF" "$1"; }
info() { HAND=$((HAND + 1));   printf '  info  %s\n' "$1"; }   # check-by-hand item: not drift, not a warning
note() { printf '  info  %s\n' "$1"; }                         # FYI line: not counted anywhere

# with_timeout SECS CMD... — macOS has no timeout(1) by default; perl's alarm survives
# exec, so CMD is killed (status 142) if it runs longer than SECS.
with_timeout() {
  local secs="$1"; shift
  perl -e '$t = shift @ARGV; alarm $t; exec { $ARGV[0] } @ARGV or exit 127' "$secs" "$@"
}
hdr()  { printf '\n%s%s%s\n' "$C_HDR" "$1" "$C_OFF"; }

# Value-comparison helpers shared with macos.sh (same semantics, single source).
# shellcheck source=lib/defaults-lib.sh disable=SC1091
. "$DOTDIR/lib/defaults-lib.sh"
DOT_PYTHON="$(dot_python || true)"

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

# ---- 4b. Dock "Assign To" desktop pins ----------------------------------
hdr "Desktop assignments (Dock → Options → Assign To)"
if PY="$(dot_python)"; then
  while IFS='|' read -r status msg; do
    [ -z "$status" ] && continue
    CHECKED=$((CHECKED + 1))
    case "$status" in
      ok)  pass "$msg" ;;
      bad) bad "$msg" ;;
      *)   warn "$msg" ;;
    esac
  done < <("$PY" "$DOTDIR/lib/desktop-bindings.py" "$DOTDIR/lib/desktop-bindings.list")
else
  CHECKED=$((CHECKED + 1))
  warn "no python3 — skipping desktop assignment check"
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

# ---- 7. URL handlers ----------------------------------------------------
hdr "URL handlers"
HANDLERS_LIST="$DOTDIR/lib/url-handlers.list"
if [ ! -r "$HANDLERS_LIST" ]; then
  warn "lib/url-handlers.list missing — skipping URL handlers check"
elif ! command -v duti >/dev/null 2>&1; then
  warn "duti not installed — skipping URL handlers check"
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

# ---- 8. unwanted apps ---------------------------------------------------
hdr "Unwanted apps"
UNWANTED_LIST="$DOTDIR/lib/unwanted-apps.list"
if [ ! -r "$UNWANTED_LIST" ]; then
  warn "lib/unwanted-apps.list missing — skipping unwanted apps check"
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
if [ -x "$DOTDIR/scripts/pin-dictation-hotkey-164.sh" ]; then
  pass "scripts/pin-dictation-hotkey-164.sh present"
else
  bad "scripts/pin-dictation-hotkey-164.sh missing"
fi
CHECKED=$((CHECKED + 1))
LA_LABEL=com.pdone.pin-dictation-hotkey-164
if launchctl print "gui/$(id -u)/$LA_LABEL" >/dev/null 2>&1; then
  pass "LaunchAgent $LA_LABEL loaded (re-pins 164 at login)"
else
  bad "LaunchAgent $LA_LABEL not loaded — re-run install.sh"
fi

# ---- 9b. Finder icon-view defaults (72 / 13) ------------------------------
hdr "Finder icon view defaults"
CHECKED=$((CHECKED + 1))
pin="$DOTDIR/scripts/pin-finder-icon-view.sh"
if [ ! -x "$pin" ]; then
  bad "scripts/pin-finder-icon-view.sh missing"
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
CHECKED=$((CHECKED + 1))
if [ ! -d /Applications/Hammerspoon.app ]; then
  warn "Hammerspoon.app not installed — brew bundle (cask \"hammerspoon\")"
elif ! pgrep -xq Hammerspoon; then
  warn "Hammerspoon not running — open -a Hammerspoon (then it starts at login)"
else
  pass "Hammerspoon running"
fi

# ---- 11. Login Items guard (ChatGPT / Gemini / launcher must stay Off) ----
# SMAppService login items aren't safely disable-able from CLI; check only.
hdr "Login Items (banned open-at-login)"
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
    warn "BTM unreadable (Full Disk Access) via $DOT_PYTHON — System Settings → Privacy & Security → Full Disk Access → enable Ghostty"
  elif [ "$btm_rc" -ne 0 ] || [ -z "$btm_status" ]; then
    warn "BTM helper failed (rc=$btm_rc${btm_err:+; $btm_err}) via $DOT_PYTHON — check Login Items manually"
  else
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
CHECKED=$((CHECKED + 1))
helper="$DOTDIR/lib/finder-sidebar-recents.py"
if [ ! -r "$helper" ]; then
  warn "lib/finder-sidebar-recents.py missing — skip"
elif [ -z "$DOT_PYTHON" ]; then
  warn "python3 not found — skip Finder Recents"
else
  # Guard exit status: with set -e, a failing $(...) aborts before rc= is set.
  out="$("$DOT_PYTHON" "$helper" 2>&1)" && rc=0 || rc=$?
  if [ "$rc" = 3 ] || printf '%s\n' "$out" | rg -q 'tcc=denied|Operation not permitted|PermissionError'; then
    warn "Finder Recents unreadable (Full Disk Access) — System Settings → Privacy & Security → Full Disk Access → enable Ghostty"
  elif [ "$rc" = 0 ]; then
    pass "Finder sidebar Recents hidden"
  else
    bad "Finder sidebar Recents not hidden ($out) — run macos.sh"
  fi
fi

# ---- 13. CotEditor theme + font ----
hdr "CotEditor"
CHECKED=$((CHECKED + 1))
cot_theme="$(defaults read com.coteditor.CotEditor defaultTheme 2>/dev/null || true)"
cot_font="$(defaults export com.coteditor.CotEditor - 2>/dev/null | plutil -extract modes.general.fontType raw - 2>/dev/null || true)"
if [ "$cot_theme" = "Anura (Dark)" ] && [ "$cot_font" = "monospaced" ]; then
  pass "CotEditor theme=Anura (Dark) fontType=monospaced"
else
  bad "CotEditor theme=${cot_theme:-unset} fontType=${cot_font:-unset} (expected Anura (Dark) / monospaced)"
fi

# ---- 14. Leftover *.app.back in /Applications ----
hdr "Leftover app backups"
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
hdr "Mac health"
H_BAT_STATUS=none; H_BAT_COND=""; H_BAT_MAX=""; H_BAT_CYCLES=""
H_DISK_STATUS=unknown; H_DISK_FREE_GB=""; H_DISK_FREE_PCT=""; H_DISK_TOTAL_GB=""
H_TM_STATUS=unknown; H_TM_LAST=""; H_TM_AGE=""
H_UP_STATUS=unknown; H_UP_DAYS=""
H_LI_STATUS=unknown; H_LI_ENABLED=0; H_LI_ALLOW=0; H_LI_MDM=0; H_LI_UNKNOWN=(); H_LI_STALE=()

# Battery: condition, maximum capacity (warn < 80%) and cycle count.
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
elif [ -n "$H_BAT_MAX" ] && [ "$H_BAT_MAX" -lt 80 ]; then
  H_BAT_STATUS=warn
  warn "battery max capacity ${H_BAT_MAX}% (< 80%; ${H_BAT_CYCLES:-?} cycles) — consider a service"
else
  H_BAT_STATUS=ok
  pass "battery ${H_BAT_COND:-condition unknown}, max capacity ${H_BAT_MAX:-?}%, ${H_BAT_CYCLES:-?} cycles"
fi

# Disk: free space on the Data volume; warn below 15% or 50 GB, whichever bites first.
CHECKED=$((CHECKED + 1))
disk_vol=/System/Volumes/Data
[ -d "$disk_vol" ] || disk_vol=/
read -r disk_total_k disk_avail_k < <(with_timeout 10 df -k "$disk_vol" 2>/dev/null | awk 'NR==2 {print $2, $4}') || true
if [ -n "${disk_total_k:-}" ] && [ -n "${disk_avail_k:-}" ] && [ "$disk_total_k" -gt 0 ]; then
  H_DISK_FREE_GB=$(( disk_avail_k * 1024 / 1000000000 ))
  H_DISK_TOTAL_GB=$(( disk_total_k * 1024 / 1000000000 ))
  H_DISK_FREE_PCT=$(( disk_avail_k * 100 / disk_total_k ))
  if [ "$H_DISK_FREE_PCT" -lt 15 ] || [ "$H_DISK_FREE_GB" -lt 50 ]; then
    H_DISK_STATUS=warn
    warn "disk: only ${H_DISK_FREE_GB} GB free (${H_DISK_FREE_PCT}%) on $disk_vol — want ≥ 50 GB and ≥ 15%"
  else
    H_DISK_STATUS=ok
    pass "disk: ${H_DISK_FREE_GB} GB free of ${H_DISK_TOTAL_GB} GB (${H_DISK_FREE_PCT}%)"
  fi
else
  warn "disk: couldn't read free space for $disk_vol (df failed)"
fi

# Time Machine: warn if the last backup is > 7 days old. Not configured is normal on a
# company Mac (backups may be handled elsewhere), so that's an info line.
tm_dest="$(with_timeout 10 tmutil destinationinfo </dev/null 2>&1 || true)"
if printf '%s\n' "$tm_dest" | grep -qi 'No destinations configured'; then
  H_TM_STATUS=not_configured
  note "Time Machine not configured (company backups may be handled elsewhere)"
else
  CHECKED=$((CHECKED + 1))
  # tmutil latestbackup prints a path/name ending in YYYY-MM-DD-HHMMSS[.backup].
  tm_stamp="$(with_timeout 20 tmutil latestbackup </dev/null 2>/dev/null | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}' | tail -1 || true)"
  if [ -n "$tm_stamp" ]; then
    tm_epoch="$(date -j -f '%Y-%m-%d-%H%M%S' "$tm_stamp" +%s 2>/dev/null || true)"
  elif [ -n "$DOT_PYTHON" ]; then
    # Fallback: newest SnapshotDates entry in the TM prefs (may need Full Disk Access).
    tm_epoch="$(with_timeout 10 "$DOT_PYTHON" -c '
import plistlib, sys
try:
    d = plistlib.load(open("/Library/Preferences/com.apple.TimeMachine.plist", "rb"))
except Exception:
    sys.exit(0)
ts = [t for dest in d.get("Destinations", []) for t in dest.get("SnapshotDates", [])]
if ts: print(int(max(ts).timestamp()))
' 2>/dev/null || true)"
  fi
  if [ -n "${tm_epoch:-}" ]; then
    H_TM_LAST="$(date -r "$tm_epoch" '+%Y-%m-%d %H:%M %Z')"
    H_TM_AGE=$(( ($(date +%s) - tm_epoch) / 86400 ))
    if [ "$H_TM_AGE" -gt 7 ]; then
      H_TM_STATUS=warn
      warn "Time Machine: last backup $H_TM_LAST ($H_TM_AGE days ago, > 7)"
    else
      H_TM_STATUS=ok
      pass "Time Machine: last backup $H_TM_LAST ($H_TM_AGE day(s) ago)"
    fi
  else
    H_TM_STATUS=warn
    warn "Time Machine configured but no last-backup date found (tmutil latestbackup / prefs unreadable)"
  fi
fi

# Uptime: a reboot every couple of weeks lets updates and long-running leaks settle.
CHECKED=$((CHECKED + 1))
boot_sec="$(sysctl -n kern.boottime 2>/dev/null | sed -nE 's/.*[{] sec = ([0-9]+),.*/\1/p')"
if [ -n "$boot_sec" ]; then
  H_UP_DAYS=$(( ($(date +%s) - boot_sec) / 86400 ))
  if [ "$H_UP_DAYS" -gt 14 ]; then
    H_UP_STATUS=warn
    warn "uptime ${H_UP_DAYS} days (> 14) — restart when convenient"
  else
    H_UP_STATUS=ok
    pass "uptime ${H_UP_DAYS} day(s)"
  fi
else
  warn "uptime unknown (sysctl kern.boottime failed)"
fi

# Login / background items: every ENABLED item must be on lib/login-items-allow.list or
# approved by an MDM Service Management rule; stale items (app gone) are flagged too.
# Reuses lib/btm-login-items.py (same BTM store as the banned-item guard above).
CHECKED=$((CHECKED + 1))
ALLOW_LIST="$DOTDIR/lib/login-items-allow.list"
if [ ! -r "$BTM_HELPER" ] || [ ! -r "$ALLOW_LIST" ] || [ -z "$DOT_PYTHON" ]; then
  warn "login-item audit skipped (needs python3, lib/btm-login-items.py and lib/login-items-allow.list)"
else
  if li_raw="$(with_timeout 20 "$DOT_PYTHON" "$BTM_HELPER" --audit "$ALLOW_LIST" 2>&1)"; then li_rc=0; else li_rc=$?; fi
  if [ "$li_rc" = 3 ] || printf '%s\n' "$li_raw" | grep -q 'tcc=denied'; then
    warn "login-item audit: BTM unreadable (Full Disk Access) — System Settings → Privacy & Security → Full Disk Access → enable Ghostty"
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
MANUAL_STEPS="$DOTDIR/scripts/manual-steps.sh"
if [ ! -x "$MANUAL_STEPS" ]; then
  CHECKED=$((CHECKED + 1))
  warn "scripts/manual-steps.sh missing or not executable — skipping manual steps"
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

# ---- summary ------------------------------------------------------------
printf '\n%sSummary:%s %d checked, %d ok, %d drift, %d warning(s), %d to check by hand (scripts/manual-steps.sh list).\n' \
  "$C_HDR" "$C_OFF" "$CHECKED" "$OKS" "$DRIFT" "$WARN" "$HAND"

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
    printf '  "time_machine": {"status": %s, "last_backup": %s, "age_days": %s},\n' \
      "$(json_str "$H_TM_STATUS")" "$(json_opt "$H_TM_LAST")" "$(json_num "$H_TM_AGE")"
    printf '  "uptime": {"status": %s, "days": %s},\n' "$(json_str "$H_UP_STATUS")" "$(json_num "$H_UP_DAYS")"
    printf '  "login_items": {"status": %s, "enabled": %d, "allow_listed": %d, "mdm_approved": %d, "unknown": %s, "stale": %s},\n' \
      "$(json_str "$H_LI_STATUS")" "$H_LI_ENABLED" "$H_LI_ALLOW" "$H_LI_MDM" \
      "$(json_arr ${H_LI_UNKNOWN[@]+"${H_LI_UNKNOWN[@]}"})" "$(json_arr ${H_LI_STALE[@]+"${H_LI_STALE[@]}"})"
    printf '  "drift_messages": %s,\n' "$(json_arr ${DRIFT_MSGS[@]+"${DRIFT_MSGS[@]}"})"
    printf '  "warning_messages": %s\n' "$(json_arr ${WARN_MSGS[@]+"${WARN_MSGS[@]}"})"
    printf '}\n'
  } >&3
fi

if [ "$DRIFT" -gt 0 ]; then exit 1; fi
exit 0
