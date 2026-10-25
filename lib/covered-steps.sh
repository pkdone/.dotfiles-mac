# shellcheck shell=bash
# shellcheck disable=SC2034,SC2317
#
# covered-steps.sh — one result for a manual step whose check is @macconfig:<area>.
# The step functions live in checks/<area>.sh (the same ones the section calls).
# Sourced by scripts/manual-steps.sh. The main check already reported the section
# and sets MACCONFIG_OWNS_SECTIONS so the manual-steps list does not count it again.
# shellcheck source=defaults-lib.sh disable=SC1091
. "$DOTDIR/lib/defaults-lib.sh"

covered_step_file() { # area
  case "$1" in
    mdm|karabiner|display|power|notifications|login-items|finder|modes)
      printf '%s\n' "$DOTDIR/checks/$1.sh"
      return 0
      ;;
  esac
  return 1
}

# Prints status|detail. status is ok, warn, or hand. detail may contain '|'.
# Read-only. Does not prompt (FLEET_OFFER=0). The step function's own stdout
# is discarded; pass/warn/bad record the lines macconfig would print.
covered_step_run() { # id area
  local id="$1" area="$2" file fn detail line
  file="$(covered_step_file "$area")" || {
    printf '%s\n' "hand|"
    return 0
  }
  fn="check_step_$(printf '%s' "$id" | tr '-' '_')"
  CHECKED=0
  FLEET_OFFER=0
  COVERED_WARNS=""
  COVERED_OKS=""
  COVERED_FORCE_HAND=0
  COVERED_DOES_NOT_APPLY=0
  pass() { COVERED_OKS="${COVERED_OKS}$1"$'\n'; }
  warn() { COVERED_WARNS="${COVERED_WARNS}$1"$'\n'; }
  bad() { warn "$1"; }
  # info is "could not verify, still by hand" (an unreadable store, no dscl).
  # skip is "this check does not apply" (a clamshell, an unlisted panel).
  info() { COVERED_FORCE_HAND=1; }
  note() { COVERED_FORCE_HAND=1; }
  skip() { COVERED_DOES_NOT_APPLY=1; }
  fixid() { :; }
  hdr() { :; }
  if [ -z "${DOT_PYTHON:-}" ]; then
    DOT_PYTHON="$(dot_python 2>/dev/null || true)"
  fi
  MACCONFIG_CHECKS_DEFINE_ONLY=1
  # shellcheck disable=SC1090
  . "$file"
  unset MACCONFIG_CHECKS_DEFINE_ONLY
  if ! command -v "$fn" >/dev/null 2>&1; then
    printf '%s\n' "hand|"
    return 0
  fi
  "$fn" >/dev/null 2>&1 || true
  if [ -n "$COVERED_WARNS" ]; then
    detail=""
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [ -z "$detail" ]; then detail="$line"; else detail="$detail; $line"; fi
    done <<EOF
$COVERED_WARNS
EOF
    printf 'warn|%s\n' "$detail"
  elif [ "$COVERED_FORCE_HAND" = 1 ]; then
    printf 'hand|\n'
  elif [ -n "$COVERED_OKS" ]; then
    detail=""
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      detail="$line"
      break
    done <<EOF
$COVERED_OKS
EOF
    printf 'ok|%s\n' "$detail"
  elif [ "$COVERED_DOES_NOT_APPLY" = 1 ]; then
    printf 'ok|\n'
  else
    printf 'hand|\n'
  fi
}
