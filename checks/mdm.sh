# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# scripts/manual-steps.sh sources this with MACCONFIG_CHECKS_DEFINE_ONLY=1 and
# calls check_step_mdm_apps (manual step mdm-apps, check @macconfig:mdm).
# ---- 2b. MDM / company apps (present, not Brewfile-managed) ----
# A missing app is a warning (fixid mdm, class PAUL in lib/autofix.list).
# In a terminal this offers to open Fleet Self service. It does not install
# the app, and macconfig --fix does not either. --issues and --health-json
# do not ask. manualsteps sets FLEET_OFFER=0 so the walk-through does not ask.
check_step_mdm_apps() {
  [ -r "$DOTDIR/lib/mdm-apps.list" ] || return 0
  # shellcheck source=../lib/fleet-apps.sh disable=SC1091
  . "$DOTDIR/lib/fleet-apps.sh"
  fixid mdm
  FLEET_CHECK=1
  fleet_company_apps_prompt "$DOTDIR/lib/mdm-apps.list"
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

if [ -r "$DOTDIR/lib/mdm-apps.list" ]; then
  hdr "MDM / company apps"
  check_step_mdm_apps
fi
