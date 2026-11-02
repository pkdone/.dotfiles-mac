# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 16. Manual steps (permissions, sign-ins, by-hand settings) -----------
# lib/manual-steps.list is the single source of truth; scripts/manual-steps.sh runs the
# read-only checks. A failed check is a soft warning (a manual step, not repo drift);
# steps with no reliable check are info lines. Steps marked @macconfig:<area>
# were verified by their own section above. MACCONFIG_OWNS_SECTIONS keeps the
# porcelain status covered so they are not counted again and open does not ask
# to press s. Each one still prints one pointer line in its numbered place.
# remove-widgets is the same pointer when the Desktop widgets section ran.
# shellcheck source=../lib/why-shown.sh disable=SC1091
. "$DOTDIR/lib/why-shown.sh"
# shellcheck source=../lib/covered-steps.sh disable=SC1091
. "$DOTDIR/lib/covered-steps.sh"

# One line for a step already reported under heading. Does not touch CHECKED,
# OKS, DRIFT, WARN, or HAND, and does not record an issue. ok / warn / fail
# come from that heading's rollup. Anything else, including a heading that
# never called pass, warn, or bad, is info: never claim ok without the data.
# The text does not say to press s.
manual_covered_line() { # num title heading
  local num="$1" title="$2" heading="${3-}" status="" marker colour pad msg
  if [ -n "$heading" ] && type section_status_of >/dev/null 2>&1; then
    status="$(section_status_of "$heading" || true)"
  fi
  case "$status" in
    ok|warn|fail) ;;
    *) status="" ;;
  esac
  case "$status" in
    ok)   marker="ok";   colour="${C_OK-}";   pad="    " ;;
    warn) marker="warn"; colour="${C_WARN-}"; pad="  " ;;
    fail) marker="fail"; colour="${C_BAD-}";  pad="  " ;;
    *)    marker="info"; colour="${C_DIM-}";  pad="  " ;;
  esac
  if [ -n "$heading" ]; then
    msg="$num. $title — checked above under $heading"
  else
    msg="$num. $title — checked above"
  fi
  printf '  %s%s%s%s%s\n' "$colour" "$marker" "${C_OFF-}" "$pad" "$msg"
}

hdr "Manual steps (lib/manual-steps.list)"
fixid manual-step
# MANUAL_STEPS_BIN is a test seam. A normal run uses scripts/manual-steps.sh.
MANUAL_STEPS="${MANUAL_STEPS_BIN:-$DOTDIR/scripts/manual-steps.sh}"
if [ ! -x "$MANUAL_STEPS" ]; then
  CHECKED=$((CHECKED + 1))
  fixid repo-file; warn "scripts/manual-steps.sh missing or not executable — skipping manual steps"
else
  # Sections above already reported @macconfig: steps. Ask for covered, not a second result.
  ms_out="$(MACCONFIG_OWNS_SECTIONS=1 NO_COLOR=1 "$MANUAL_STEPS" check --porcelain 2>&1)" || true
  while IFS='|' read -r ms_status ms_num ms_id ms_title ms_detail; do
    # Placed widgets are reported by the Desktop widgets section. The named
    # check still runs so `manualsteps open` shows the step only when a widget
    # is placed. On a full run (WIDGETS_SECTION_RAN) print the pointer in this
    # numbered place and do not count it again. --only manual leaves the flag
    # unset, so the result is printed here.
    if [ "$ms_id" = remove-widgets ] && [ "${WIDGETS_SECTION_RAN:-}" = 1 ]; then
      manual_covered_line "$ms_num" "$ms_title" "$(covered_section_heading "$ms_id" || true)"
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
        warn "$ms_num. $ms_title — $ms_detail (manualsteps open)"
        ;;
      hand)    info "$ms_num. $ms_title — $(why_shown_line hand "$ms_detail")" ;;
      covered)
        manual_covered_line "$ms_num" "$ms_title" "$(covered_section_heading "$ms_id" || true)"
        ;;
      '') : ;;
      *)       CHECKED=$((CHECKED + 1)); warn "manual-steps.sh: $ms_status${ms_num:+|$ms_num}" ;;
    esac
  done <<< "$ms_out"
fi
