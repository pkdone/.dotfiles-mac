# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.

# launchservices_browser_line PLIST — one line: ok|msg or warn|msg
launchservices_browser_line() {
  with_timeout 15 "$DOT_PYTHON" - "$1" <<'PY'
import plistlib
import sys

path = sys.argv[1]
chrome = "com.google.chrome"


def emit(status, message):
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{status}|{text}")


try:
    with open(path, "rb") as fh:
        data = plistlib.load(fh)
except Exception as exc:  # noqa: BLE001 — report, don't crash the check
    emit("warn", f"couldn't read LaunchServices handlers ({exc})")
    raise SystemExit(0)

handlers = data.get("LSHandlers") if isinstance(data, dict) else None
if not isinstance(handlers, list):
    emit("warn", "LaunchServices plist has no LSHandlers array — can't confirm the default browser")
    raise SystemExit(0)


def bundle_for(scheme):
    for item in handlers:
        if not isinstance(item, dict):
            continue
        if str(item.get("LSHandlerURLScheme", "")).lower() != scheme:
            continue
        role = item.get("LSHandlerRoleAll") or item.get("LSHandlerRoleViewer") or ""
        return str(role)
    return None


shown = []
missing = []
for scheme in ("http", "https"):
    role = bundle_for(scheme)
    shown.append(f"{scheme}={role or 'unset'}")
    if role is None or role.lower() != chrome:
        missing.append(scheme)
detail = ", ".join(shown)
if missing:
    emit(
        "warn",
        "Chrome is not the LaunchServices handler for "
        + " and ".join(missing)
        + f" ({detail}; want com.google.chrome). This check does not change the default browser",
    )
else:
    emit("ok", f"Chrome is the LaunchServices handler for http and https ({detail})")
PY
}

check_default_browser() {
  local plist line st msg rc=0
  plist="$HOME/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
  CHECKED=$((CHECKED + 1))
  if [ ! -e "$plist" ]; then
    fixid url-handler
    warn "LaunchServices handler list is missing (~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist) — can't confirm Chrome is the default browser"
    return 0
  fi
  if [ -z "${DOT_PYTHON:-}" ]; then
    fixid tooling
    warn "no python3 — can't read LaunchServices handlers"
    return 0
  fi
  line="$(launchservices_browser_line "$plist")" || rc=$?
  st="${line%%|*}"
  msg="${line#*|}"
  if [ "$st" = ok ]; then
    fixid url-handler
    pass "$msg"
  elif [ -n "$msg" ]; then
    fixid url-handler
    warn "$msg"
  else
    fixid tooling
    warn "LaunchServices handler check produced nothing (rc=$rc)"
  fi
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

# ---- 7. URL handlers ----------------------------------------------------
hdr "URL handlers"
fixid url-handler
HANDLERS_LIST="$DOTDIR/lib/url-handlers.list"
if [ ! -r "$HANDLERS_LIST" ]; then
  fixid repo-file; warn "lib/url-handlers.list missing — skipping URL handlers check"
elif ! command -v duti >/dev/null 2>&1; then
  fixid tooling; warn "duti not installed — run brewsync (skipping URL handlers check)"
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
check_default_browser
