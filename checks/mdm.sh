# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 2b. MDM / company apps (present, not Brewfile-managed) ----
if [ -r "$DOTDIR/lib/mdm-apps.list" ]; then
  hdr "MDM / company apps"
  fixid mdm
  while IFS='|' read -r name path _mas_id; do
    name="$(printf '%s' "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    path="$(printf '%s' "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$name" in ''|\#*) continue ;; esac
    CHECKED=$((CHECKED + 1))
    if [ -d "$path" ]; then
      pass "$name present (MDM-managed; not in Brewfile)"
    else
      warn "$name missing at $path — install from Iru Self Service"
    fi
  done < "$DOTDIR/lib/mdm-apps.list"
fi
