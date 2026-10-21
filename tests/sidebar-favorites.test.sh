#!/usr/bin/env bash
#
# Finder Favorites: lib/sidebar-favorites.list, the mysides comparison, and
# macos.sh rebuilding only when the list differs. mysides and Finder are fakes.
# Run: ./tests/sidebar-favorites.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$DIR/lib/sidebar-favorites.py"
LIST="$DIR/lib/sidebar-favorites.list"
MACOS="$DIR/macos.sh"
PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then echo "sidebar-favorites tests: python3 not found, skipped"; exit 0; fi

pass=0
fail=0
eq() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
has() {
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL: %s\n  missing: [%s]\n  in:      [%s]\n' "$1" "$2" "$3" ;; esac
}
miss() {
  case "$3" in *"$2"*) fail=$((fail + 1)); printf 'FAIL: %s\n  unexpected: [%s]\n' "$1" "$2" ;;
    *) pass=$((pass + 1)) ;; esac
}

names="$(awk -F'|' '$1 !~ /^#/ && NF { print $1 }' "$LIST")"
eq "favorites order" "Applications
Desktop
Developer
Documents
Downloads
Movies
Music
Pictures" "$names"

brewfile="$(cat "$DIR/Brewfile")"
has "mysides is a Homebrew cask" 'cask "mysides"' "$brewfile"
miss "mysides is not a formula" 'brew "mysides"' "$brewfile"
has "macos.sh installs mysides as a cask" 'brew install --cask mysides' "$(cat "$DIR/macos.sh")"
has "finder check installs mysides as a cask" 'brew install --cask mysides' "$(cat "$DIR/checks/finder.sh")"

tmp="$(mktemp -d)"
backup_before=""
if [ -d "$DIR/backups" ]; then
  backup_before="$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'defaults-*' | sort)"
fi
cleanup() {
  local d now
  if [ -d "$DIR/backups" ]; then
    now="$(find "$DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'defaults-*' | sort)"
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      case "$backup_before" in
        *"$d"*) ;;
        *) rm -rf "$d" ;;
      esac
    done <<< "$now"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
home="$tmp/home"
mkdir -p "$home"
export HOME="$home"

want="$("$PY" "$HELPER" urls --list "$LIST")"
eq "Applications address" "Applications	file:///Applications/" "$(printf '%s\n' "$want" | head -n 1)"
has "Desktop address uses the home" "file://${home}/Desktop/" "$want"

printf '%s\n' "$want" | awk -F'\t' '{ printf "%s -> %s\n", $1, $2 }' > "$tmp/match.txt"
# A trailing slash difference and an AirDrop line must still match.
sed 's|/$||' "$tmp/match.txt" > "$tmp/noslash.txt"
printf '%s\n' '-> nwnode://domain-AirDrop' >> "$tmp/noslash.txt"
out="$("$PY" "$HELPER" compare --list "$LIST" --mysides "$tmp/noslash.txt")"
eq "trailing slash and AirDrop still match" "ok" "${out%%|*}"

printf '%s\n' 'Applications -> file:///Applications/' > "$tmp/short.txt"
out="$("$PY" "$HELPER" compare --list "$LIST" --mysides "$tmp/short.txt")"
eq "a short list is drift" "bad" "${out%%|*}"

printf '%s\n' \
  'Desktop -> file://'"$home"'/Desktop/' \
  'Applications -> file:///Applications/' \
  > "$tmp/order.txt"
# pad the rest so only the swap is the point: still drift because order differs
"$PY" "$HELPER" urls --list "$LIST" | awk -F'\t' 'NR>2 { printf "%s -> %s\n", $1, $2 }' >> "$tmp/order.txt"
out="$("$PY" "$HELPER" compare --list "$LIST" --mysides "$tmp/order.txt")"
eq "wrong order is drift" "bad" "${out%%|*}"

# macos.sh with a fake mysides. Matching list does not remove, add, or restart Finder.
bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/mysides" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MYSIDES_LOG:?}"
if [ "${1:-}" = list ]; then
  cat "${MYSIDES_NOW:?}"
  exit 0
fi
exit 0
EOF
cat > "$bin/defaults" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat > "$bin/killall" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${KILLALL_LOG:?}"
exit 0
EOF
chmod +x "$bin/mysides" "$bin/defaults" "$bin/killall"
printf '%s\n' "$want" | awk -F'\t' '{ printf "%s -> %s\n", $1, $2 }' > "$tmp/now.txt"

run_macos() {
  : > "$tmp/mysides.log"
  : > "$tmp/killall.log"
  HOME="$home" PATH="$bin:$PATH" MYSIDES_LOG="$tmp/mysides.log" MYSIDES_NOW="$tmp/now.txt" \
    KILLALL_LOG="$tmp/killall.log" \
    "$MACOS" --no-color --yes --only @finder-favorites "$@"
}

out="$(run_macos)"
eq "matching favorites exits 0" 0 "$?"
has "matching favorites are left alone" "Finder Favorites already match" "$out"
eq "matching favorites only lists" "list" "$(cat "$tmp/mysides.log")"
eq "matching favorites does not restart Finder" "" "$(cat "$tmp/killall.log")"
eq "matching favorites does not create Developer" "no" "$([ -d "$home/Developer" ] && echo yes || echo no)"

printf '%s\n' 'Applications -> file:///Applications/' > "$tmp/now.txt"
out="$(run_macos --dry-run)"
has "dry-run would rebuild" "dry-run" "$out"
eq "dry-run does not call mysides add" "" "$(grep -v '^list$' "$tmp/mysides.log" || true)"
eq "dry-run does not restart Finder" "" "$(cat "$tmp/killall.log")"

out="$(run_macos)"
has "rebuild says it changed Favorites" "Finder Favorites -> rebuilt" "$out"
has "rebuild removes the old favorite" "remove Applications" "$(cat "$tmp/mysides.log")"
has "rebuild adds Desktop" "add Desktop" "$(cat "$tmp/mysides.log")"
eq "rebuild restarts Finder" "Finder" "$(cat "$tmp/killall.log")"
eq "rebuild creates the Developer folder" "yes" "$([ -d "$home/Developer" ] && echo yes || echo no)"

printf 'sidebar-favorites tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
