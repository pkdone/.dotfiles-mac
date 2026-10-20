# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.
# ---- 8. unwanted apps ---------------------------------------------------
hdr "Unwanted apps"
fixid unwanted-app
UNWANTED_LIST="$DOTDIR/lib/unwanted-apps.list"
if [ ! -r "$UNWANTED_LIST" ]; then
  fixid repo-file; warn "lib/unwanted-apps.list missing — skipping unwanted apps check"
else
  while IFS="|" read -r name path _mas_id; do
    case "$name" in ""|"#"*) continue ;; esac
    name="$(printf "%s" "$name" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")"
    path="$(printf "%s" "$path" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")"
    [ -n "$name" ] || continue
    [ -n "$path" ] || continue
    CHECKED=$((CHECKED + 1))
    if [ -e "$path" ]; then
      bad "$name still installed at $path (run prune-apps.sh)"
    else
      pass "$name absent"
    fi
  done < "$UNWANTED_LIST"
fi
