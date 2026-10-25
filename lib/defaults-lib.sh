# shellcheck shell=bash
#
# defaults-lib.sh — value-comparison helpers shared by macos.sh and macconfig-check.sh.
# Sourced, not executed (no shebang, not marked executable). Keeping these in one
# place means the apply path (macos.sh) and the verify path (macconfig-check.sh) compare
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

# Like values_equal, but for int/float a non-empty, non-zero tol lets the actual value
# sit within +/-tol of desired (e.g. a Dock tilesize of 46-48 all match a desired 47 with
# tol 1). Non-numeric types and a blank/zero tol fall straight through to exact equality.
values_match() {  # type actual desired [tol]
  local tol="${4:-}"
  case "$1" in
    int|float)
      if [ -n "$tol" ] && [ "$tol" != 0 ]; then
        awk -v a="$2" -v d="$3" -v t="$tol" 'BEGIN{ x=a-d; if(x<0)x=-x; exit !(x<=t) }'
        return
      fi
      ;;
  esac
  values_equal "$1" "$2" "$3"
}

# 0 or 1 when the text is a boolean or an integer 0/1. Anything else fails.
# `defaults read` prints 0 or 1 for a boolean, and true/false for some writes.
boolish_01() {
  local n
  n="$(norm_bool "$1")"
  case "$n" in
    0|1) printf '%s\n' "$n" ;;
    *) return 1 ;;
  esac
}

# True when the stored type and the list type are boolean and integer (either
# way around) and both the stored value and the desired value are 0 or 1.
# An integer 2 or 3 is not a boolean, so it stays a real type mismatch and is
# not rewritten.
flex_01_applicable() { # read-type word, our type, actual, desired
  case "$1:$2" in
    boolean:int|integer:bool) ;;
    *) return 1 ;;
  esac
  boolish_01 "$3" >/dev/null || return 1
  boolish_01 "$4" >/dev/null
}

# The type already stored, as a write_default type name.
flex_01_write_type() { # read-type word
  case "$1" in
    boolean) printf '%s\n' bool ;;
    integer) printf '%s\n' int ;;
    *) return 1 ;;
  esac
}

# Value to pass to defaults write for that stored type. Booleans are written
# true/false. Integers are written 0/1.
flex_01_write_value() { # write type (bool|int), desired
  local bit
  bit="$(boolish_01 "$2")" || return 1
  if [ "$1" = bool ]; then
    if [ "$bit" = 1 ]; then
      printf '%s\n' true
    else
      printf '%s\n' false
    fi
  else
    printf '%s\n' "$bit"
  fi
}

# True when actual and desired are the same 0 or 1.
flex_01_values_match() { # actual, desired
  local a d
  a="$(boolish_01 "$1")" || return 1
  d="$(boolish_01 "$2")" || return 1
  [ "$a" = "$d" ]
}

# com.apple.screencapture video is On as integer 1 or boolean true. That is
# the same 0/1 rule as every other bool/int setting (flex_01_*).
screencapture_video_matches() { # read-type word, actual, desired
  case "$1" in
    integer|boolean) ;;
    *) return 1 ;;
  esac
  flex_01_values_match "$2" "$3"
}

type_token() {  # our type -> `defaults read-type` word
  case "$1" in
    string) echo string ;;
    float)  echo float ;;
    int)    echo integer ;;
    bool)   echo boolean ;;
  esac
}

# The Show Finder menu shortcut is one entry in a dictionary, so it is not a
# row in lib/macos-defaults.list. Pull that entry out of `defaults read` text.
# Prints the key equivalent (for example @^$f) or nothing.
finder_show_value() {
  printf '%s\n' "$1" | awk '
    index($0, "Show Finder") == 0 { next }
    {
      line = $0
      sub(/^.*"Show Finder"[[:space:]]*=[[:space:]]*/, "", line)
      sub(/^"/, "", line)
      sub(/";?[[:space:]]*$/, "", line)
      sub(/;[[:space:]]*$/, "", line)
      print line
      exit
    }
  '
}

# Interpreter for helpers that read TCC-gated files (BTM db, Finder sidebar SFL).
# Prefer Homebrew/mise python so TCC follows the terminal (Ghostty). Apple's
# /usr/bin/python3 is an xcode-select shim onto com.apple.python3, which has its
# own TCC identity and gets EPERM unless that binary has Full Disk Access.
dot_python() {
  local cand="" p
  if command -v python3 >/dev/null 2>&1; then
    cand="$(command -v python3)"
  fi
  for p in "$cand" /opt/homebrew/bin/python3; do
    [ -n "$p" ] || continue
    [ -x "$p" ] || continue
    case "$p" in
      /usr/bin/python3) continue ;;
    esac
    printf '%s\n' "$p"
    return 0
  done
  if [ -x /usr/bin/python3 ]; then
    printf '%s\n' /usr/bin/python3
    return 0
  fi
  return 1
}
