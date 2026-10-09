# shellcheck shell=bash
#
# autofix-lib.sh — lookup helpers for lib/autofix.list (the safe / needs-Paul split
# used by `macconfig-check.sh --fix`). Sourced, not executed. Shared by macconfig-check.sh and
# tests/autofix.test.sh so the classification is read the same way everywhere.

# autofix_lookup LIST ID — print "class|fixer|why" for ID. An id that isn't listed is
# never automated: it comes back as PAUL with a "not classified" reason.
autofix_lookup() {  # list id
  local row
  row="$(awk -F'|' -v id="$2" '$1 !~ /^#/ && NF && $1 == id { print $2 "|" $3 "|" $4; exit }' "$1" 2>/dev/null)"
  if [ -z "$row" ]; then
    printf 'PAUL||not classified in lib/autofix.list (report only)\n'
    return 0
  fi
  case "$row" in
    SAFE\|\|*) printf 'PAUL||%s (SAFE row has no fixer — report only)\n' "${row##*|}" ;;
    SAFE\|*)   printf '%s\n' "$row" ;;
    *)        printf 'PAUL|%s\n' "${row#*|}" ;;
  esac
}

# autofix_class LIST ID — SAFE or PAUL
autofix_class() { autofix_lookup "$1" "$2" | cut -d'|' -f1; }
