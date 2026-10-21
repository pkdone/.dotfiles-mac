# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 16. Manual steps (permissions, sign-ins, by-hand settings) -----------
# lib/manual-steps.list is the single source of truth; scripts/manual-steps.sh runs the
# read-only checks. A failed check is a soft warning (a manual step, not repo drift);
# steps with no reliable check are info lines; steps marked @macconfig-check.sh are verified by
# their own section above, so they're not repeated here.
hdr "Manual steps (lib/manual-steps.list)"
fixid manual-step
MANUAL_STEPS="$DOTDIR/scripts/manual-steps.sh"
if [ ! -x "$MANUAL_STEPS" ]; then
  CHECKED=$((CHECKED + 1))
  fixid repo-file; warn "scripts/manual-steps.sh missing or not executable — skipping manual steps"
else
  ms_out="$(NO_COLOR=1 MANUAL_STEPS_COVERED="${SESSION_COVERED:-}" "$MANUAL_STEPS" check --porcelain 2>&1)" || true
  while IFS='|' read -r ms_status ms_num ms_id ms_title ms_detail; do
    case "$ms_status" in
      ok)      CHECKED=$((CHECKED + 1)); pass "$ms_num. $ms_title${ms_detail:+ — $ms_detail}" ;;
      # Check-only rows get their own PAUL id (never --fix). The sign-in /
      # pointer ids are usually covered by section 15c; this tags a warning
      # if that section did not run.
      warn)
        CHECKED=$((CHECKED + 1))
        case "$ms_id" in
          mouse-settings) fixid mouse-settings ;;
          pointer-size) fixid pointer-size ;;
          input-british) fixid input-british ;;
          gh-auth) fixid gh-auth ;;
          1password-cli) fixid 1password-cli ;;
          spotlight-results) fixid spotlight-results ;;
          app-store) fixid app-store ;;
          *) fixid manual-step ;;
        esac
        warn "$ms_num. $ms_title — $ms_detail (scripts/manual-steps.sh open)"
        ;;
      hand)    info "$ms_num. $ms_title — check by hand${ms_detail:+ ($ms_detail)}" ;;
      covered|'') : ;;
      *)       CHECKED=$((CHECKED + 1)); warn "manual-steps.sh: $ms_status${ms_num:+|$ms_num}" ;;
    esac
  done <<< "$ms_out"
fi
