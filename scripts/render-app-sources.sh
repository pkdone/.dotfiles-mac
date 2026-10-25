#!/usr/bin/env bash
#
# render-app-sources.sh — keep the README "Where apps come from" section in
# step with the Brewfile and lib/mdm-apps.list.
#
# The section sits between the BEGIN/END markers in README.md. Edit the
# Brewfile or lib/mdm-apps.list, then re-run this script.
# tests/app-sources.test.sh fails when the README section is stale.
#
#   scripts/render-app-sources.sh            update the README section
#   scripts/render-app-sources.sh --stdout   print the section
#   scripts/render-app-sources.sh --check    exit 1 when the README is stale
#
set -euo pipefail

DOTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$DOTDIR/README.md"
BREWFILE="$DOTDIR/Brewfile"
MDM="$DOTDIR/lib/mdm-apps.list"
BEGIN='<!-- BEGIN app-sources -->'
END='<!-- END app-sources -->'

# shellcheck source=../lib/join-names.sh disable=SC1091
. "$DOTDIR/lib/join-names.sh"

usage() {
  cat <<'USAGE'
Usage: scripts/render-app-sources.sh [--stdout|--check]
  (no flag)   Update the "Where apps come from" section in README.md.
  --stdout    Print that section instead of writing it.
  --check     Exit 1 if the README section differs from a fresh render.
  -h, --help  Show this help.
USAGE
}

# kind is brew, cask, or mas. Entries must start the line so a comment cannot
# hide or add a name.
names_of() {
  sed -nE "s/^${1} \"([^\"]+)\".*/\1/p" "$BREWFILE"
}

mdm_names() {
  awk -F'|' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      name = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      if (name != "") print name
    }
  ' "$MDM"
}

render() {
  local tools apps mas_apps company mas_body
  tools="$(names_of brew | join_and)"
  apps="$(names_of cask | join_and)"
  mas_apps="$(names_of mas | join_and)"
  company="$(mdm_names | join_and)"
  if [ -n "$mas_apps" ]; then
    mas_body="Apps the Brewfile installs with \`mas\`.

**Apps:** ${mas_apps}."
  else
    mas_body="No apps currently come from the Mac App Store. This Mac can't sign in with a personal Apple ID."
  fi
  cat <<EOF
## Where apps come from

This repo installs apps and tools from three places.

### Homebrew

Command-line tools and desktop apps listed in the Brewfile. The first setup installs them with \`brew bundle\`. A failed entry is retried once and does not stop the others. An app already in \`/Applications\` is adopted. After that, \`brewsync\` installs anything missing and upgrades what is already there. If one of these is missing, run \`brewsync\`.

**Command-line tools:** ${tools}.

**Desktop apps:** ${apps}.

### Mac App Store

${mas_body}

### Company apps (Fleet Self service)

Company-managed apps. Every name below is required, including Zoom and 1Password. Install each one yourself from Fleet's My device page: Fleet Desktop menu bar → My device → Self service. The names are in \`lib/mdm-apps.list\`. They are not in the Brewfile. If one of these is missing, install it from Fleet Self service. Setup can open that page for you. It does not install the apps on its own, because the page needs company single sign-on.

**Apps:** ${company}.

1Password for Safari and Okta Extension App are not in any of these lists. This Mac can't sign in to the App Store with a personal Apple ID, and it isn't known whether Fleet installs those Safari extensions. They are left out so a missing copy does not raise a warning.

Cursor Nightly and YouTube Music are installed by hand. They are not Homebrew apps and not company apps. See [Setup](docs/setup.md#apps-not-in-the-brewfile).
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
  echo "README.md app-sources section is stale. Regenerate with scripts/render-app-sources.sh" >&2
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
