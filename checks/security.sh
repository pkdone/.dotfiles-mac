# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.

# stealth_from_text TEXT — one line: ok|msg or warn|msg
stealth_from_text() {
  local t="$1" flat
  flat="$(printf '%s' "$t" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ -z "$flat" ]; then
    printf 'warn|Firewall stealth mode unknown (socketfilterfw --getstealthmode failed)\n'
    return 0
  fi
  if printf '%s\n' "$flat" | grep -qi 'disabled\|stealth mode is off'; then
    printf 'warn|Firewall stealth mode is off (%s) — System Settings → Network → Firewall → Stealth mode. This check does not change it\n' "$flat"
    return 0
  fi
  if printf '%s\n' "$flat" | grep -qi 'enabled\|stealth mode is on'; then
    printf 'ok|Firewall stealth mode is on (%s)\n' "$flat"
    return 0
  fi
  printf 'warn|Firewall stealth mode unrecognized (%s)\n' "$flat"
}

# su_plist_lines PLIST — two lines: auto|status|message and pending|status|message
# Read-only. No softwareupdate, no network.
su_plist_lines() {
  with_timeout 15 "$DOT_PYTHON" - "$1" <<'PY'
import plistlib
import sys
from datetime import datetime, timezone

path = sys.argv[1]


def show(value):
    if value is None:
        return "missing"
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value).replace("|", "/").replace("\n", " ")


def truthy(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() in ("1", "true", "yes", "on")
    return False


def emit(kind, status, message):
    text = str(message).replace("\n", " ").replace("|", "/")
    print(f"{kind}|{status}|{text}")


try:
    with open(path, "rb") as fh:
        data = plistlib.load(fh)
except Exception as exc:  # noqa: BLE001 — report, don't crash the check
    emit("auto", "warn", f"couldn't read Software Update plist {path} ({exc})")
    emit("pending", "warn", f"couldn't read Software Update plist {path} ({exc})")
    raise SystemExit(0)

if not isinstance(data, dict):
    emit("auto", "warn", f"Software Update plist {path} is not a dictionary")
    emit("pending", "warn", f"Software Update plist {path} is not a dictionary")
    raise SystemExit(0)

keys = (
    "CriticalUpdateInstall",
    "ConfigDataInstall",
    "AutomaticallyInstallMacOSUpdates",
)
parts = [f"{name}={show(data.get(name))}" for name in keys]
where = f"read from {path}"
off = [name for name in keys if not truthy(data.get(name))]
if off:
    emit(
        "auto",
        "warn",
        "automatic security updates are not all on ("
        + ", ".join(parts)
        + f"; off: {', '.join(off)}; {where}). "
        "System Settings → General → Software Update. This check does not change them",
    )
else:
    emit("auto", "ok", "automatic security updates are on (" + ", ".join(parts) + f"; {where})")

updates = data.get("RecommendedUpdates")
titles = []
if isinstance(updates, list):
    for item in updates:
        if isinstance(item, dict):
            name = item.get("Display Name") or item.get("DisplayName") or item.get("Product Key") or "update"
            titles.append(str(name).replace("|", "/").replace("\n", " "))
        elif item is not None:
            titles.append(str(item).replace("|", "/").replace("\n", " "))
when = data.get("LastSuccessfulDate")
when_s = "missing"
age_days = None
if isinstance(when, datetime):
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    when_s = when.astimezone(timezone.utc).strftime("%Y-%m-%d")
    age_days = (datetime.now(timezone.utc) - when).total_seconds() / 86400.0
title_s = "; ".join(titles) if titles else "none"
if not titles:
    emit(
        "pending",
        "ok",
        f"no pending macOS update in the Software Update cache "
        f"(RecommendedUpdates empty, LastSuccessfulDate={when_s}; {where})",
    )
elif age_days is None:
    emit(
        "pending",
        "warn",
        f"pending macOS update ({title_s}) but LastSuccessfulDate is missing, "
        f"so the age is unknown ({where})",
    )
elif age_days > 7:
    emit(
        "pending",
        "warn",
        f"pending macOS update waiting {age_days:.1f} days "
        f"(LastSuccessfulDate={when_s}): {title_s} ({where}). "
        "System Settings → General → Software Update. This check does not install it",
    )
else:
    emit(
        "pending",
        "info",
        f"pending macOS update, last successful check {age_days:.1f} days ago "
        f"(under 7; LastSuccessfulDate={when_s}): {title_s} ({where})",
    )
PY
}

ssh_mode() { # path — numeric mode, empty if unreadable
  local m
  m="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1" 2>/dev/null || true)"
  printf '%s' "$m"
}

# Literal tilde. ${var/#pat/~} tilde-expands the replacement and would print a real home.
ssh_show() { # path home
  local rest
  case "$1" in
    "$2"/*)
      rest="${1#"$2"/}"
      # Literal tilde. Expanding it would print a real home directory.
      # shellcheck disable=SC2088
      printf '~/%s' "$rest"
      ;;
    *) printf '%s' "$1" ;;
  esac
}

ssh_is_private_key() { # path — 0 if this file should be mode 600
  local name head
  name="$(basename "$1")"
  case "$name" in
    *.pub|config|known_hosts|known_hosts.old|authorized_keys|authorized_keys2|environment|*.old)
      return 1
      ;;
  esac
  [ -f "$1" ] || return 1
  case "$name" in
    id_*|*.pem) return 0 ;;
  esac
  head="$(head -n 2 "$1" 2>/dev/null || true)"
  case "$head" in
    *"PRIVATE KEY"*) return 0 ;;
  esac
  return 1
}

# ssh_audit HOME — lines of ok|msg, warn|msg, info|msg. Read-only.
ssh_audit() {
  local home="$1" sshdir out rc n m key gpgsign fmt priv sig
  sshdir="$home/.ssh"
  if ! command -v ssh-add >/dev/null 2>&1; then
    printf 'warn|ssh-add not found — cannot check whether an SSH key is loaded\n'
  else
    rc=0
    out="$(with_timeout 5 ssh-add -l 2>&1)" || rc=$?
    case "$rc" in
      0)
        n="$(printf '%s\n' "$out" | grep -c . || true)"
        printf 'ok|SSH agent has %s key(s) loaded\n' "${n:-0}"
        ;;
      1) printf 'warn|no SSH key loaded in the agent (ssh-add -l)\n' ;;
      *) printf 'warn|SSH agent is not usable (ssh-add -l exit %s)\n' "$rc" ;;
    esac
  fi
  if [ ! -e "$sshdir" ] && [ ! -L "$sshdir" ]; then
    printf 'info|no ~/.ssh directory — skipped permission checks\n'
  else
    m="$(ssh_mode "$sshdir")"
    if [ "$m" = 700 ]; then
      printf 'ok|~/.ssh is mode 700\n'
    else
      printf 'warn|~/.ssh is mode %s (want 700)\n' "${m:-unknown}"
    fi
    for key in "$sshdir"/*; do
      [ -e "$key" ] || [ -L "$key" ] || continue
      ssh_is_private_key "$key" || continue
      m="$(ssh_mode "$key")"
      if [ "$m" = 600 ]; then
        printf 'ok|%s is mode 600\n' "$(ssh_show "$key" "$home")"
      else
        printf 'warn|%s is mode %s (want 600)\n' "$(ssh_show "$key" "$home")" "${m:-unknown}"
      fi
    done
  fi
  if ! command -v git >/dev/null 2>&1; then
    printf 'warn|git not found — cannot check commit signing\n'
    return 0
  fi
  gpgsign="$(HOME="$home" git config --global --get commit.gpgsign 2>/dev/null || true)"
  fmt="$(HOME="$home" git config --global --get gpg.format 2>/dev/null || true)"
  key="$(HOME="$home" git config --global --get user.signingkey 2>/dev/null || true)"
  case "$(printf '%s' "$gpgsign" | tr '[:upper:]' '[:lower:]')" in
    true|yes|on|1) ;;
    *)
      printf 'info|commit signing is not configured (commit.gpgsign=%s, gpg.format=%s)\n' \
        "${gpgsign:-unset}" "${fmt:-unset}"
      return 0
      ;;
  esac
  case "$(printf '%s' "$fmt" | tr '[:upper:]' '[:lower:]')" in
    ssh) ;;
    *)
      printf 'info|commit signing is configured (commit.gpgsign=%s, gpg.format=%s); the dry test covers ssh only\n' \
        "$gpgsign" "${fmt:-unset}"
      return 0
      ;;
  esac
  priv="$key"
  case "$priv" in
    *.pub) priv="${priv%.pub}" ;;
  esac
  if [ -n "$priv" ] && [ ! -f "$priv" ] && [ -f "$sshdir/$priv" ]; then
    priv="$sshdir/$priv"
  fi
  case "$priv" in
    *.pub) priv="${priv%.pub}" ;;
  esac
  if [ -z "$priv" ] || [ ! -f "$priv" ]; then
    printf 'warn|commit signing is on (gpg.format=ssh) but user.signingkey is not a file (%s)\n' \
      "${key:-unset}"
    return 0
  fi
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    printf 'warn|commit signing is on (gpg.format=ssh) but ssh-keygen is missing, so the dry sign was not run\n'
    return 0
  fi
  rc=0
  sig="$(printf 'macconfig-check\n' | SSH_ASKPASS_REQUIRE=force with_timeout 10 ssh-keygen -Y sign -n git -f "$priv" 2>&1)" || rc=$?
  if [ "$rc" = 0 ] && [ -n "$sig" ]; then
    printf 'ok|git commit signing works (gpg.format=ssh, dry sign with ssh-keygen -Y sign)\n'
  else
    printf 'warn|git commit signing is configured (gpg.format=ssh) but the dry sign failed (ssh-keygen -Y sign, exit %s)\n' "$rc"
  fi
  return 0
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

# ---- 15. Security hygiene (soft — warn only) ----------------------------
hdr "Security hygiene"
fixid security
CHECKED=$((CHECKED + 1))
fv="$(with_timeout 15 fdesetup status 2>/dev/null || true)"
if printf '%s\n' "$fv" | rg -qi 'FileVault is On'; then
  pass "FileVault On"
elif [ -z "$fv" ]; then
  warn "FileVault status unknown (fdesetup failed)"
else
  warn "FileVault not On — $fv"
fi

CHECKED=$((CHECKED + 1))
fixid security
if [ ! -x /usr/libexec/ApplicationFirewall/socketfilterfw ]; then
  warn "socketfilterfw missing — can't check firewall stealth mode"
else
  stealth_line="$(stealth_from_text "$(with_timeout 5 /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode </dev/null 2>/dev/null || true)")"
  stealth_st="${stealth_line%%|*}"
  stealth_msg="${stealth_line#*|}"
  if [ "$stealth_st" = ok ]; then
    pass "$stealth_msg"
  else
    warn "${stealth_msg:-Firewall stealth mode check failed}"
  fi
fi

su_plist=""
for su_candidate in /Library/Preferences/com.apple.SoftwareUpdate.plist \
                    "$HOME/Library/Preferences/com.apple.SoftwareUpdate.plist"; do
  if [ -r "$su_candidate" ]; then
    su_plist="$su_candidate"
    break
  fi
done
if [ -z "$su_plist" ]; then
  CHECKED=$((CHECKED + 1))
  fixid security
  warn "couldn't read com.apple.SoftwareUpdate (tried /Library/Preferences and ~/Library/Preferences) — automatic security updates not verified"
  CHECKED=$((CHECKED + 1))
  fixid software-update
  warn "couldn't read com.apple.SoftwareUpdate — pending macOS update age not verified (no network call)"
elif [ -z "${DOT_PYTHON:-}" ]; then
  CHECKED=$((CHECKED + 1))
  fixid tooling
  warn "no python3 — can't read automatic security update settings"
  CHECKED=$((CHECKED + 1))
  fixid tooling
  warn "no python3 — can't read the Software Update cache"
else
  su_rc=0
  su_out="$(su_plist_lines "$su_plist")" || su_rc=$?
  su_n=0
  while IFS='|' read -r su_kind su_st su_msg; do
    [ -n "${su_kind:-}" ] || continue
    su_n=$((su_n + 1))
    case "$su_kind" in
      auto) fixid security ;;
      pending) fixid software-update ;;
      *) fixid tooling ;;
    esac
    case "$su_st" in
      ok) CHECKED=$((CHECKED + 1)); pass "$su_msg" ;;
      info) note "$su_msg" ;;
      *) CHECKED=$((CHECKED + 1)); warn "${su_msg:-Software Update check failed}" ;;
    esac
  done <<SU_EOF
$su_out
SU_EOF
  if [ "$su_n" -eq 0 ]; then
    CHECKED=$((CHECKED + 1))
    fixid tooling
    warn "Software Update plist check produced nothing (rc=$su_rc)"
  fi
fi

fixid security
while IFS='|' read -r ssh_st ssh_msg; do
  [ -n "${ssh_st:-}" ] || continue
  case "$ssh_st" in
    ok) CHECKED=$((CHECKED + 1)); pass "$ssh_msg" ;;
    info) note "$ssh_msg" ;;
    *) CHECKED=$((CHECKED + 1)); fixid security; warn "$ssh_msg" ;;
  esac
done <<SSH_EOF
$(ssh_audit "$HOME")
SSH_EOF
