#!/usr/bin/env bash
#
# render-app-sources.sh — keep the short README note on where apps come from
# in step with the Brewfile.
#
# The note sits between the BEGIN/END markers in README.md. It names the
# three sources and what each is for. It does not list the apps. Re-run this
# script after adding or removing a Mac App Store line in the Brewfile.
# tests/app-sources.test.sh fails when the README note is stale.
#
#   scripts/render-app-sources.sh            update the README note
#   scripts/render-app-sources.sh --stdout   print the note
#   scripts/render-app-sources.sh --check    exit 1 when the README note is stale
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$DOTDIR/README.md"
BREWFILE="${APP_SOURCES_BREWFILE:-$DOTDIR/Brewfile}"
BEGIN='<!-- BEGIN app-sources -->'
END='<!-- END app-sources -->'

usage() {
  cat <<'USAGE'
Usage: scripts/render-app-sources.sh [--stdout|--check]
  (no flag)   Update the app-sources note in README.md.
  --stdout    Print that note instead of writing it.
  --check     Exit 1 if the README note differs from a fresh render.
  -h, --help  Show this help.
USAGE
}

# A mas line must start the line, so a comment cannot add one.
has_mas() {
  grep -qE '^mas "' "$BREWFILE"
}

render() {
  local store
  if has_mas; then
    store="The Mac App Store is for the apps the Brewfile installs with \`mas\`."
  else
    store="Nothing is installed from the Mac App Store now, because this Mac can't sign in with a personal Apple ID."
  fi
  cat <<EOF
Apps and tools come from three places. Homebrew, via the Brewfile, is for most apps and command-line tools. Fleet Self service is for company-managed apps that can't be installed unattended; setup prompts you to install them. ${store}
EOF
}

extract() {
  awk -v begin="$BEGIN" -v end="$END" '
    $0 == begin { grab = 1; next }
    $0 == end { grab = 0; next }
    grab { print }
  ' "$README"
}

write_out() {
  local tmp sec
  if ! grep -qxF "$BEGIN" "$README" || ! grep -qxF "$END" "$README"; then
    echo "README.md is missing the app-sources markers ($BEGIN / $END)." >&2
    return 1
  fi
  tmp="$(mktemp)"
  sec="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp' '$sec'" RETURN
  render >"$sec"
  awk -v begin="$BEGIN" -v end="$END" -v sec="$sec" '
    $0 == begin {
      print
      while ((getline line < sec) > 0) print line
      close(sec)
      skip = 1
      next
    }
    $0 == end { skip = 0 }
    skip { next }
    { print }
  ' "$README" >"$tmp"
  mv "$tmp" "$README"
  trap - RETURN
  rm -f "$sec"
}

check_out() {
  local cur new
  if [ ! -f "$README" ]; then
    echo "README.md is missing. Regenerate with scripts/render-app-sources.sh" >&2
    return 1
  fi
  if ! grep -qxF "$BEGIN" "$README" || ! grep -qxF "$END" "$README"; then
    echo "README.md is missing the app-sources markers. Regenerate with scripts/render-app-sources.sh" >&2
    return 1
  fi
  cur="$(mktemp)"
  new="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$cur' '$new'" RETURN
  extract >"$cur"
  render >"$new"
  if cmp -s "$cur" "$new"; then
    trap - RETURN
    rm -f "$cur" "$new"
    return 0
  fi
    echo "README.md app-sources note is stale. Regenerate with scripts/render-app-sources.sh" >&2
  diff -u "$cur" "$new" >&2 || true
  trap - RETURN
  rm -f "$cur" "$new"
  return 1
}

main() {
  case "${1:-}" in
    -h|--help) usage ;;
    --stdout) render ;;
    --check) check_out ;;
    '') write_out ;;
    *) echo "Unknown option: $1 (try --help)" >&2; return 2 ;;
  esac
}

main "$@"
