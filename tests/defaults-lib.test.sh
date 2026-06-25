#!/usr/bin/env bash
#
# Unit tests for lib/defaults-lib.sh — the value-comparison helpers shared by
# macos.sh and check.sh. Plain bash + awk, no test framework or extra deps.
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

# ---- type_token: our type -> defaults read-type word ----
eq "type_token string" string  "$(type_token string)"
eq "type_token float"  float   "$(type_token float)"
eq "type_token int"    integer "$(type_token int)"
eq "type_token bool"   boolean "$(type_token bool)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
