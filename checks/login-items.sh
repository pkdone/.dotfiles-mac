# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 11. Login Items guard (ChatGPT must stay Off) ----
# SMAppService login items aren't safely disable-able from CLI; check only.
hdr "Login Items (banned open-at-login)"
fixid tooling   # helper / python problems below; the item checks are login-items
BANNED_BUNDLES="com.openai.codex"
BANNED_NAMES="ChatGPT"
# Prefer parsing the world-readable BTM db. `sfltool dumpbtm` can pop an admin
# password dialog on Tahoe. This section never runs it. The Karabiner background
# check reads the same database, and only tries sfltool with a short timeout
# when that database cannot be read.
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
