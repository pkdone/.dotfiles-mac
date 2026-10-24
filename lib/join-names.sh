# shellcheck shell=bash
#
# join_and — read one name per line on stdin and print "a, b, and c".
# Sourced by the app-source doc, install.sh, and the Brewfile missing-app hint.
# Two names are "a and b". One name is "a". Empty input prints nothing.

join_and() {
  local items=() line n i
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    items+=("$line")
  done
  n=${#items[@]}
  [ "$n" -eq 0 ] && return 0
  if [ "$n" -eq 1 ]; then
    printf '%s' "${items[0]}"
    return 0
  fi
  if [ "$n" -eq 2 ]; then
    printf '%s and %s' "${items[0]}" "${items[1]}"
    return 0
  fi
  printf '%s' "${items[0]}"
  i=1
  while [ "$i" -lt $((n - 1)) ]; do
    printf ', %s' "${items[$i]}"
    i=$((i + 1))
  done
  printf ', and %s' "${items[$((n - 1))]}"
}
