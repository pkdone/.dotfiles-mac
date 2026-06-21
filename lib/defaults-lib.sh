# shellcheck shell=bash
#
# defaults-lib.sh — value-comparison helpers shared by macos.sh and check.sh.
# Sourced, not executed (no shebang, not marked executable). Keeping these in one
# place means the apply path (macos.sh) and the verify path (check.sh) compare
# values with identical semantics and can never drift.

norm_bool() {
  case "$1" in
    1|true|TRUE|True|yes|YES)  echo 1 ;;
    0|false|FALSE|False|no|NO) echo 0 ;;
    *) echo "$1" ;;
  esac
}

values_equal() {  # type a b
  case "$1" in
    bool)      [ "$(norm_bool "$2")" = "$(norm_bool "$3")" ] ;;
    int|float) awk -v x="$2" -v y="$3" 'BEGIN{ exit !(x==y) }' ;;
    *)         [ "$2" = "$3" ] ;;
  esac
}

type_token() {  # our type -> `defaults read-type` word
  case "$1" in
    string) echo string ;;
    float)  echo float ;;
    int)    echo integer ;;
    bool)   echo boolean ;;
  esac
}
