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

# One line, messages separated by "; ". Blank lines are dropped.
# The text is data, so it is not expanded again.
covered_join() { # multiline string
  printf '%s\n' "$1" | awk '
    NF {
      if (out != "") out = out "; "
      out = out $0
    }
    END { printf "%s", out }
  '
}

# What the check actually reads, when the step also has a part left by hand.
covered_checked_part() { # id
  case "$1" in
    finder-sidebar) printf '%s' "the sidebar rows the files name" ;;
    notifications-apps) printf '%s' "Allow Notifications for the listed apps" ;;
    karabiner-login-items) printf '%s' "the Karabiner background items that can be read" ;;
    mode-focus-modes) printf '%s' "the Focus modes that can be read" ;;
    mode-hammerspoon-alerts) printf '%s' "Hammerspoon's notification style" ;;
    user-picture) printf '%s' "the account picture" ;;
    *) printf '%s' "the part this check can read" ;;
  esac
}

# Prints status|detail. status is ok, warn, or hand. detail may contain '|'.
# Read-only. Does not prompt (FLEET_OFFER=0). The step function's own stdout
# is discarded; pass/warn/bad/info/note record the lines macconfig would print.
# A listed app that has never posted a notification ("nothing to turn off")
# counts as done. A third-party app that is only flagged for review is not
# part of the manual step. Any other info or note is a part the check does
# not cover: the step stays up, and the detail names the part that was checked.
covered_step_run() { # id area
  local id="$1" area="$2" file fn detail line partial
  file="$(covered_step_file "$area")" || {
    printf '%s\n' "hand|this check is not wired"
    return 0
  }
  fn="check_step_$(printf '%s' "$id" | tr '-' '_')"
  CHECKED=0
  FLEET_OFFER=0
  COVERED_WARNS=""
  COVERED_OKS=""
  COVERED_PARTIAL=""
  COVERED_DOES_NOT_APPLY=0
  pass() { COVERED_OKS="${COVERED_OKS}$1"$'\n'; }
  warn() { COVERED_WARNS="${COVERED_WARNS}$1"$'\n'; }
  bad() { warn "$1"; }
  # skip is "this check does not apply" (a clamshell, an unlisted panel).
  info() {
    case "$1" in
      *"nothing to turn off"*) COVERED_OKS="${COVERED_OKS}$1"$'\n' ;;
      *"third-party app is not in"*) ;;
      *) COVERED_PARTIAL="${COVERED_PARTIAL}$1"$'\n' ;;
    esac
  }
  note() { info "$1"; }
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
    printf '%s\n' "hand|this check is not wired"
    return 0
  fi
  "$fn" >/dev/null 2>&1 || true
  if [ -n "$COVERED_WARNS" ]; then
    detail="$(covered_join "$COVERED_WARNS")"
    if [ -n "$COVERED_PARTIAL" ]; then
      partial="$(covered_join "$COVERED_PARTIAL")"
      detail="$detail. Still by hand: $partial"
    fi
    printf 'warn|%s\n' "$detail"
  elif [ -n "$COVERED_PARTIAL" ]; then
    partial="$(covered_join "$COVERED_PARTIAL")"
    if [ -n "$COVERED_OKS" ]; then
      printf 'hand|Checked: %s. Still by hand: %s\n' "$(covered_checked_part "$id")" "$partial"
    else
      printf 'hand|%s\n' "$partial"
    fi
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
    printf 'hand|this check did not report a result\n'
  fi
}
