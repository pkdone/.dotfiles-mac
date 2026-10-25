# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 16. Manual steps (permissions, sign-ins, by-hand settings) -----------
# lib/manual-steps.list is the single source of truth; scripts/manual-steps.sh runs the
# read-only checks. A failed check is a soft warning (a manual step, not repo drift);
# steps with no reliable check are info lines. Steps marked @macconfig:<area> are
# verified by their own section above, so MACCONFIG_OWNS_SECTIONS makes them
# covered and they are not repeated here.
hdr "Manual steps (lib/manual-steps.list)"
fixid manual-step
MANUAL_STEPS="$DOTDIR/scripts/manual-steps.sh"
if [ ! -x "$MANUAL_STEPS" ]; then
  CHECKED=$((CHECKED + 1))
  fixid repo-file; warn "scripts/manual-steps.sh missing or not executable — skipping manual steps"
else
  # Sections above already reported @macconfig: steps. Ask for covered, not a second result.
  ms_out="$(MACCONFIG_OWNS_SECTIONS=1 NO_COLOR=1 "$MANUAL_STEPS" check --porcelain 2>&1)" || true
  while IFS='|' read -r ms_status ms_num ms_id ms_title ms_detail; do
    # Placed widgets are reported by the Desktop widgets section. The named
    # check still runs so `manualsteps open` shows the step only when a widget
    # is placed. Skip the duplicate on a full run (WIDGETS_SECTION_RAN).
    # --only manual leaves the flag unset, so the result is printed here.
    if [ "$ms_id" = remove-widgets ] && [ "${WIDGETS_SECTION_RAN:-}" = 1 ]; then
      continue
    fi
    case "$ms_status" in
      ok)      CHECKED=$((CHECKED + 1)); pass "$ms_num. $ms_title${ms_detail:+ — $ms_detail}" ;;
      # Check-only rows get their own PAUL id (never --fix), the same way as
      # mouse-settings. British input, gh auth, 1Password CLI, and pointer
      # size are the scripts/manual-steps.sh result, printed here once.
      warn)
        CHECKED=$((CHECKED + 1))
        case "$ms_id" in
          mouse-settings) fixid mouse-settings ;;
          pointer-size) fixid pointer-size ;;
          input-british) fixid input-british ;;
          gh-auth) fixid gh-auth ;;
          1password-cli) fixid 1password-cli ;;
          spotlight-results) fixid spotlight-results ;;
          remove-widgets) fixid remove-widgets ;;
          tailscale-signin) fixid tailscale-signin ;;
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
