# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 15c. British input, sign-ins, pointer (check-only) -----------------
# Warn only: never drift, never --fix, no sudo, and the notification store is
# not opened. lib/session-checks.sh is the same code scripts/manual-steps.sh
# runs. A 1Password CLI that is installed but not signed in (it needs an
# unlock) is info, not a warning. Pointer size runs only when the manual-steps
# list has a pointer-size row. Those rows are not repeated in section 16
# (MANUAL_STEPS_COVERED). MANUAL_STEPS_LIST overrides the list, same as
# scripts/manual-steps.sh.
hdr "Sign-ins, keyboard, and pointer"
SESSION_COVERED=""
emit_manual_check() { # step-id — R_STATUS/R_DETAIL set; caller sets FIX_ID first
  local step="$1" title msg
  title="$(awk -F'|' -v id="$step" '$1 == id { print $3; exit }' "$steps_list")"
  if [ -n "$title" ]; then
    msg="$title — ${R_DETAIL:-$R_STATUS} (manual step $step)"
  else
    msg="${R_DETAIL:-$R_STATUS} (manual step $step)"
  fi
  CHECKED=$((CHECKED + 1))
  case "$R_STATUS" in
    ok)   pass "$msg" ;;
    warn) warn "$msg" ;;
    *)    info "$msg" ;;
  esac
}
cover_step() { # step-id — remember it so section 16 does not print it again
  local step="$1"
  if awk -F'|' -v id="$step" '$1 == id { found = 1 } END { exit !found }' "$steps_list"; then
    SESSION_COVERED="${SESSION_COVERED:+$SESSION_COVERED }$step"
  fi
}
steps_list="${MANUAL_STEPS_LIST:-$DOTDIR/lib/manual-steps.list}"
if [ ! -r "$DOTDIR/lib/session-checks.sh" ]; then
  CHECKED=$((CHECKED + 1))
  fixid repo-file
  warn "lib/session-checks.sh missing — can't check British input, GitHub CLI, 1Password CLI, or pointer size"
else
  # shellcheck source=lib/session-checks.sh disable=SC1091
  . "$DOTDIR/lib/session-checks.sh"
  if awk -F'|' '$1 == "pointer-size" { found = 1 } END { exit !found }' "$steps_list"; then
    R_STATUS=""; R_DETAIL=""
    check_pointer_size
    fixid pointer-size
    emit_manual_check pointer-size
    cover_step pointer-size
  fi
  R_STATUS=""; R_DETAIL=""
  check_input_british
  fixid input-british
  emit_manual_check input-british
  cover_step input-british
  R_STATUS=""; R_DETAIL=""
  check_gh_auth
  fixid gh-auth
  emit_manual_check gh-auth
  cover_step gh-auth
  R_STATUS=""; R_DETAIL=""
  check_op_cli
  fixid 1password-cli
  emit_manual_check 1password-cli
  cover_step 1password-cli
fi
