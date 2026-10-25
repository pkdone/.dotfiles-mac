#!/usr/bin/env bash
#
# Unit tests for lib/defaults-lib.sh — the value-comparison helpers shared by
# macos.sh and macconfig-check.sh. Plain bash + awk, no test framework or extra deps.
# Run: ./tests/defaults-lib.test.sh   (exits non-zero if any assertion fails)
#
set -uo pipefail   # deliberately not -e: run every assertion, then tally failures

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/defaults-lib.sh disable=SC1091
. "$DIR/../lib/defaults-lib.sh"

pass=0
fail=0

# eq DESCRIPTION EXPECTED ACTUAL — assert two strings match
eq() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"
  fi
}

# yes DESCRIPTION CMD... — assert CMD exits 0
yes() {
  local desc="$1"; shift
  if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL (wanted success): %s\n' "$desc"; fi
}

# no DESCRIPTION CMD... — assert CMD exits non-zero
no() {
  local desc="$1"; shift
  if "$@"; then fail=$((fail + 1)); printf 'FAIL (wanted failure): %s\n' "$desc"; else pass=$((pass + 1)); fi
}

# ---- norm_bool: truthy/falsy normalise to 1/0, everything else passes through ----
eq "norm_bool true"        1      "$(norm_bool true)"
eq "norm_bool TRUE"        1      "$(norm_bool TRUE)"
eq "norm_bool yes"         1      "$(norm_bool yes)"
eq "norm_bool 1"           1      "$(norm_bool 1)"
eq "norm_bool false"       0      "$(norm_bool false)"
eq "norm_bool NO"          0      "$(norm_bool NO)"
eq "norm_bool 0"           0      "$(norm_bool 0)"
eq "norm_bool passthrough" "icnv" "$(norm_bool icnv)"

# ---- values_equal: bool (compares normalised forms) ----
yes "bool true == 1"     values_equal bool true 1
yes "bool false == 0"    values_equal bool false 0
yes "bool YES == true"   values_equal bool YES true
no  "bool true != false" values_equal bool true false

# ---- values_equal: int/float (numeric equality via awk) ----
yes "int 46 == 46"     values_equal int 46 46
yes "float 46 == 46.0" values_equal float 46 46.0
yes "int 1 == 1.00"    values_equal int 1 1.00
no  "int 46 != 47"     values_equal int 46 47

# ---- values_equal: string (exact, no coercion) ----
yes "string exact match"        values_equal string PfHm PfHm
no  "string is case-sensitive"  values_equal string PfHm pfhm
no  "string no numeric coercion" values_equal string 1 1.0

# ---- values_match: int/float honour ±tol, else exact; non-numeric ignores tol ----
yes "match exact, no tol"            values_match int 47 47
no  "no-match, no tol"               values_match int 46 47
yes "within +tol"                    values_match int 48 47 1
yes "within -tol"                    values_match int 46 47 1
yes "exact with tol set"             values_match int 47 47 1
no  "just outside +tol"              values_match int 49 47 1
no  "just outside -tol"              values_match int 45 47 1
yes "float within tol"               values_match float 46.5 47 1
yes "blank tol falls back to equal"  values_match int 47 47 ""
no  "blank tol, unequal"             values_match int 46 47 ""
yes "zero tol acts exact (equal)"    values_match int 47 47 0
no  "zero tol acts exact (unequal)"  values_match int 46 47 0
no  "tol ignored for strings"        values_match string PfHm pfhm 5

# ---- bool and int 0/1 are the same value; the write keeps the stored type ----
yes "boolean 1 with int 1 is flexible" flex_01_applicable boolean int 1 1
yes "integer 0 with bool false is flexible" flex_01_applicable integer bool 0 false
yes "boolean 0 with int 0 is flexible" flex_01_applicable boolean int 0 0
no  "the same integer type is not flexible" flex_01_applicable integer int 1 1
no  "integer 2 is not a boolean" flex_01_applicable boolean int 2 0
no  "stored integer 2 against a bool is not flexible" flex_01_applicable integer bool 2 false
no  "a string store is not flexible" flex_01_applicable string int 1 1
eq "a boolean is written as bool" bool "$(flex_01_write_type boolean)"
eq "an integer is written as int" int "$(flex_01_write_type integer)"
eq "bool 1 is written true" true "$(flex_01_write_value bool 1)"
eq "bool 0 is written false" false "$(flex_01_write_value bool 0)"
eq "bool false is written false" false "$(flex_01_write_value bool false)"
eq "int true is written 1" 1 "$(flex_01_write_value int true)"
eq "int false is written 0" 0 "$(flex_01_write_value int false)"
yes "boolean 1 matches int 1" flex_01_values_match 1 1
yes "false matches 0" flex_01_values_match false 0
no  "1 does not match 0" flex_01_values_match 1 0
no  "2 is not a 0/1 value" flex_01_values_match 2 0

# ---- screencapture video: integer 1 and boolean true are the same On ----
yes "video integer 1 matches desired 1" screencapture_video_matches integer 1 1
yes "video boolean true matches desired 1" screencapture_video_matches boolean true 1
yes "video boolean 1 matches desired 1" screencapture_video_matches boolean 1 1
no  "video boolean 0 does not match desired 1" screencapture_video_matches boolean 0 1
no  "video integer 0 does not match desired 1" screencapture_video_matches integer 0 1
no  "video string is not the flexible type" screencapture_video_matches string 1 1
no  "video float is not the flexible type" screencapture_video_matches float 1 1

# ---- type_token: our type -> defaults read-type word ----
eq "type_token string" string  "$(type_token string)"
eq "type_token float"  float   "$(type_token float)"
eq "type_token int"    integer "$(type_token int)"
eq "type_token bool"   boolean "$(type_token bool)"

# shellcheck disable=SC2016  # '@^$f' is the shortcut text, not a variable
eq "Show Finder shortcut" '@^$f' "$(finder_show_value '    "Show Finder" = "@^$f";')"
# shellcheck disable=SC2016
eq "Show Finder among other shortcuts" '@^$f' "$(finder_show_value '{
    "Other" = "@o";
    "Show Finder" = "@^$f";
}')"
eq "missing Show Finder shortcut" "" "$(finder_show_value '{ "Other" = "@o"; }')"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
