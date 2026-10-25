# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 2b. MDM / company apps (present, not Brewfile-managed) ----
# A missing app is a warning (fixid mdm, class PAUL in lib/autofix.list).
# In a terminal this offers to open Fleet Self service. It does not install
# the app, and macconfig --fix does not either. --issues and --health-json
# do not ask.
# shellcheck source=../lib/fleet-apps.sh disable=SC1091
. "$DOTDIR/lib/fleet-apps.sh"
if [ -r "$DOTDIR/lib/mdm-apps.list" ]; then
  hdr "MDM / company apps"
  fixid mdm
  FLEET_CHECK=1
  fleet_company_apps_prompt "$DOTDIR/lib/mdm-apps.list"
fi
