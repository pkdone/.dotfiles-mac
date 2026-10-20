# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
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
