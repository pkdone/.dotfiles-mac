# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 6. hostname --------------------------------------------------------
hdr "Hostname"
fixid hostname
for which in HostName LocalHostName ComputerName; do
  CHECKED=$((CHECKED + 1))
  cur="$(scutil --get "$which" 2>/dev/null || true)"
  if [ "$cur" = "$EXPECTED_HOST" ]; then
    pass "$which = $cur"
  else
    bad "$which = ${cur:-unset} (expected $EXPECTED_HOST)"
  fi
done
