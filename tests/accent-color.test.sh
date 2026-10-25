#!/usr/bin/env bash
#
# Theme colour Graphite: NSGlobalDomain AppleAccentColor = -1 (integer).
# AppleHighlightColor stays unset. A change is noted for logout; a match is not.
# Fake defaults only. Run: ./tests/accent-color.test.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="$DIR/lib/macos-defaults.list"
MACOS="$DIR/macos.sh"

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

eq "accent colour is integer -1" '-1' \
  "$(awk -F'|' '$1=="NSGlobalDomain" && $2=="AppleAccentColor" { print $4; exit }' "$LIST")"
eq "accent colour type is int" int \
  "$(awk -F'|' '$1=="NSGlobalDomain" && $2=="AppleAccentColor" { print $3; exit }' "$LIST")"
eq "accent colour needs a logout when it changes" logout \
  "$(awk -F'|' '$1=="NSGlobalDomain" && $2=="AppleAccentColor" { print $5; exit }' "$LIST")"
eq "highlight colour is not a managed key" "" \
  "$(awk -F'|' '$2=="AppleHighlightColor" { print; exit }' "$LIST")"
miss "macos.sh does not write the highlight colour" AppleHighlightColor "$(cat "$MACOS")"
has "settings names Graphite" "Appearance → Theme → Colour: Graphite" "$(cat "$DIR/docs/settings.md")"
has "settings says the highlight stays unset" "AppleHighlightColor" "$(cat "$DIR/docs/settings.md")"
# shellcheck disable=SC2016  # the check source contains this literal
has "the defaults check reports a missing accent" \
  'bad "$domain $key — not set (expected $desired)"' "$(cat "$DIR/checks/defaults.sh")"

tmp="$(mktemp -d)"
bin="$tmp/bin"
state="$tmp/state"
dlog="$tmp/defaults.log"
logout="$tmp/logout.txt"
mkdir -p "$bin"
: > "$dlog"
: > "$logout"
: > "$tmp/made-backups"
note_backups() {
  printf '%s\n' "$1" | awk '/backups -> / { print $NF }' >> "$tmp/made-backups"
}
cleanup() {
  local d
  while IFS= read -r d; do
    [ -n "$d" ] && rm -rf "$d"
  done < "$tmp/made-backups"
  rm -rf "$tmp"
}
trap cleanup EXIT

cat > "$bin/defaults" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DEFAULTS_LOG:?}"
args=("$@")
if [ "${args[0]}" = "-currentHost" ]; then
  args=("${args[@]:1}")
fi
cmd="${args[0]}"
domain="${args[1]:-}"
key="${args[2]:-}"
case "$cmd" in
  read|read-type)
    line="$(awk -F'|' -v d="$domain" -v k="$key" '$1 == d && $2 == k { print; exit }' "${DEFAULTS_STATE:?}")"
    [ -n "$line" ] || exit 1
    if [ "$cmd" = read ]; then
      printf '%s\n' "$(printf '%s\n' "$line" | cut -d'|' -f4-)"
      exit 0
    fi
    typ="$(printf '%s\n' "$line" | cut -d'|' -f3)"
    case "$typ" in
      int) echo "Type is integer" ;;
      *) exit 1 ;;
    esac
    ;;
  export) touch "${args[2]}" ;;
  write)
    printf 'W|%s|%s|%s|%s\n' "$domain" "$key" "${args[3]:-}" "${args[4]:-}" >> "${DEFAULTS_LOG:?}"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$bin/defaults"
writes() { grep '^W|' "$dlog" || true; }

run() {
  : > "$dlog"
  : > "$logout"
  PATH="$bin:$PATH" HOME="$tmp/home" DEFAULTS_LOG="$dlog" DEFAULTS_STATE="$state" \
    DOTFILES_LOGOUT_FILE="$logout" \
    "$MACOS" --no-color --yes --only 'NSGlobalDomain|AppleAccentColor'
}

mkdir -p "$tmp/home"
printf 'NSGlobalDomain|AppleAccentColor|int|-1\n' > "$state"
out="$(run)"
rc=$?
note_backups "$out"
eq "a matching accent exits 0" 0 "$rc"
has "a matching accent is left alone" "already set: -1 (left alone)" "$out"
eq "a matching accent does not write" "" "$(writes)"
miss "a matching accent does not ask for a logout" "logout" "$out"
eq "a matching accent is not queued for bootstrap" "" "$(cat "$logout")"

: > "$state"
out="$(run)"
rc=$?
note_backups "$out"
eq "a missing accent exits 0" 0 "$rc"
has "a missing accent is set" "set (was unset) -> -1" "$out"
has "a missing accent is written as an integer" "W|NSGlobalDomain|AppleAccentColor|-int|-1" "$(writes)"
miss "a missing accent does not write the highlight" AppleHighlightColor "$(writes)"
has "a change names the logout note" "may need a logout/login" "$out"
has "a change names the accent on the logout note" "NSGlobalDomain AppleAccentColor" "$out"
eq "a change is queued for bootstrap" "NSGlobalDomain AppleAccentColor" "$(cat "$logout")"

printf 'NSGlobalDomain|AppleAccentColor|int|4\n' > "$state"
out="$(run)"
note_backups "$out"
has "a blue accent is changed to Graphite" "changed: 4 -> -1" "$out"
has "a blue accent is written as -int -1" "W|NSGlobalDomain|AppleAccentColor|-int|-1" "$(writes)"
eq "a blue accent is queued for bootstrap" "NSGlobalDomain AppleAccentColor" "$(cat "$logout")"

printf 'accent-color tests: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
