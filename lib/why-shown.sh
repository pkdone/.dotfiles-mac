# shellcheck shell=bash
#
# why-shown.sh — the one reason line under a manual step.
# Sourced by scripts/manual-steps.sh (pending and open) and checks/manual.sh
# (the macconfig info lines). The check's own words stay in the detail.
# This only adds the label.
#
#   NOTSET:  the step has a check, and the check says it is not set yet
#   MANUAL:  it can't be checked automatically
#
# A MANUAL line keeps the useful detail, starts that detail with a capital
# letter, and says to press s if it is already set. An already-done step
# shown with --all keeps its own sentence.

why_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# First letter only. A digit or a symbol is left as it is.
why_capitalize() {
  local s first rest
  s="$(why_trim "$1")"
  [ -n "$s" ] || return 0
  first="$(printf '%s' "$s" | cut -c1)"
  rest="$(printf '%s' "$s" | cut -c2-)"
  first="$(printf '%s' "$first" | tr '[:lower:]' '[:upper:]')"
  printf '%s%s' "$first" "$rest"
}

# Drop a leading "check by hand:" so MANUAL: does not say it twice.
why_strip_hand_label() {
  local s
  s="$(why_trim "$1")"
  case "$s" in
    "check by hand:"*) s="$(why_trim "${s#check by hand:}")" ;;
    "Check by hand:"*) s="$(why_trim "${s#Check by hand:}")" ;;
  esac
  printf '%s' "$s"
}

why_press_s() {
  local s="$1"
  case "$s" in
    *"press s"*) printf '%s' "$s" ;;
    *.) printf '%s If it'"'"'s already set, press s.' "$s" ;;
    *) printf '%s. If it'"'"'s already set, press s.' "$s" ;;
  esac
}

# status is warn, hand, ok, or covered. detail may be empty.
why_shown_line() {
  local status="$1" detail="$2"
  case "$status" in
    warn)
      detail="$(why_capitalize "$detail")"
      if [ -n "$detail" ]; then
        printf 'NOTSET: %s' "$detail"
      else
        printf '%s' "NOTSET: Not set yet"
      fi
      ;;
    ok|covered)
      printf '%s' "Already done, shown because of --all"
      ;;
    *)
      detail="$(why_strip_hand_label "$detail")"
      if [ -z "$detail" ]; then
        printf '%s' "MANUAL: Can't check this automatically. If it's already set, press s."
      else
        printf 'MANUAL: %s' "$(why_press_s "$(why_capitalize "$detail")")"
      fi
      ;;
  esac
}
