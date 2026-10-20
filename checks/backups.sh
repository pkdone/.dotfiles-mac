# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 14. Leftover *.app.back in /Applications ----
hdr "Leftover app backups"
fixid delete-files
CHECKED=$((CHECKED + 1))
shopt -s nullglob
backs=(/Applications/*.app.back)
shopt -u nullglob
if [ ${#backs[@]} -eq 0 ]; then
  pass "no /Applications/*.app.back leftovers"
else
  for f in "${backs[@]}"; do
    warn "leftover $f (safe to trash; leftover from an in-place app update)"
  done
fi
