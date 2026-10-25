# shellcheck shell=bash
#
# fleet-apps.sh — company apps from Fleet Self service.
# Sourced by bootstrap.sh and checks/mdm.sh. Not executed.
#
# Fleet's device page needs company single sign-on, so this only opens it.
# It does not call the Fleet API and it does not install anything.
# The device id is read from the orbit identifier file on this Mac.
# It is never written into the repo.

# Tests override these. Defaults are the paths on a Fleet-managed Mac.
# FLEET_ID_FILE         orbit device id (default /opt/orbit/identifier)
# FLEET_DESKTOP_APP     Fleet Desktop.app
# FLEET_PROFILES_CMD    `profiles` (or a stub)
# FLEET_OPEN_CMD        `open` (or a stub)
# FLEET_HOST_FALLBACK   used when profiles has no MDM server line
# FLEET_OFFER           0 = never ask, even on a terminal (bootstrap --yes / --dry-run)
# FLEET_CHECK           1 = report through pass/warn (a warning, not drift)

fleet_is_interactive() {
  # Same rule as dotfiles_is_interactive. bootstrap.sh tees stdout into a log,
  # so the inner script's stdout is not a tty; the wrapper records the outer
  # terminal in DOTFILES_INTERACTIVE before that redirect.
  case "${DOTFILES_INTERACTIVE:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  [ -t 0 ] && [ -t 1 ]
}

fleet_should_offer() {
  [ "${FLEET_OFFER:-1}" != 0 ] || return 1
  # Machine-readable runs and a --fix dry run must not wait on a person.
  [ "${HEALTH_JSON:-0}" = 1 ] && return 1
  [ "${ISSUES:-0}" = 1 ] && return 1
  [ "${DRY_RUN:-0}" = 1 ] && return 1
  fleet_is_interactive
}

fleet_with_timeout() {
  local secs="$1"
  shift
  if command -v perl >/dev/null 2>&1; then
    perl -e '$t = shift @ARGV; alarm $t; exec { $ARGV[0] } @ARGV or exit 127' "$secs" "$@"
  else
    "$@"
  fi
}

# Host of the MDM server, from `profiles status -type enrollment`.
# Falls back when the command is missing or the line is not there.
fleet_mdm_host() {
  local cmd prof host fallback
  fallback="${FLEET_HOST_FALLBACK:-cursor.cloud.fleetdm.com}"
  cmd="${FLEET_PROFILES_CMD:-profiles}"
  if [ ! -x "$cmd" ] && ! command -v "$cmd" >/dev/null 2>&1; then
    printf '%s\n' "$fallback"
    return 0
  fi
  prof="$(fleet_with_timeout 10 "$cmd" status -type enrollment 2>/dev/null || true)"
  # Avoid `head` here: under pipefail a closed pipe would fail the script.
  host="$(printf '%s\n' "$prof" | sed -nE 's/^[[:space:]]*MDM server:[[:space:]]+https?:\/\/([^/[:space:]]+).*/\1/p')"
  host="${host%%$'\n'*}"
  case "$host" in
    ''|*[!A-Za-z0-9.-]*) printf '%s\n' "$fallback" ;;
    *) printf '%s\n' "$host" ;;
  esac
}

# Prints the device id, or returns 1 when the file is missing or not 36 chars.
# The id is not logged by this function.
fleet_device_id() {
  local file id
  file="${FLEET_ID_FILE:-/opt/orbit/identifier}"
  [ -f "$file" ] && [ -r "$file" ] || return 1
  id="$(tr -d '[:space:]' < "$file")"
  case "$id" in
    *[!A-Za-z0-9-]*) return 1 ;;
  esac
  [ "${#id}" -eq 36 ] || return 1
  printf '%s\n' "$id"
}

fleet_self_service_url() {
  local id host
  id="$(fleet_device_id)" || return 1
  host="$(fleet_mdm_host)"
  printf 'https://%s/device/%s/self-service\n' "$host" "$id"
}

fleet_manual_path() {
  printf '%s\n' "Fleet Desktop menu bar → My device → Self service"
}

fleet_print_how() {
  local url
  printf 'Install them from Fleet Self service: %s\n' "$(fleet_manual_path)"
  if url="$(fleet_self_service_url)"; then
    printf '%s\n' "$url"
  fi
}

# Open the self-service page. When the device id is missing, open Fleet
# Desktop, or print the menu path when that app cannot be opened.
# Always returns 0. Prints what happened.
fleet_open_self_service() {
  local url desktop cmd
  cmd="${FLEET_OPEN_CMD:-open}"
  if url="$(fleet_self_service_url)"; then
    if "$cmd" "$url"; then
      printf 'Opened %s\n' "$url"
      return 0
    fi
    printf 'Could not open %s\n' "$url"
    printf '%s\n' "$(fleet_manual_path)"
    return 0
  fi
  desktop="${FLEET_DESKTOP_APP:-/opt/orbit/bin/desktop/macos/stable/Fleet Desktop.app}"
  if [ -d "$desktop" ] && "$cmd" "$desktop"; then
    printf 'Opened Fleet Desktop. Use the menu bar: My device → Self service.\n'
    return 0
  fi
  if "$cmd" -a "Fleet Desktop"; then
    printf 'Opened Fleet Desktop. Use the menu bar: My device → Self service.\n'
    return 0
  fi
  printf 'Could not open Fleet Desktop.\n'
  printf '%s\n' "$(fleet_manual_path)"
  return 0
}

fleet_note_present() {
  [ "${FLEET_CHECK:-}" = 1 ] || return 0
  CHECKED=$(( ${CHECKED:-0} + 1 ))
  pass "$1 present (MDM-managed; not in Brewfile)"
}

fleet_note_now() {
  if [ "${FLEET_CHECK:-}" = 1 ]; then
    CHECKED=$(( ${CHECKED:-0} + 1 ))
    pass "$1 is now present (MDM-managed; not in Brewfile)"
  else
    printf '%s is now present\n' "$1"
  fi
}

fleet_note_still() {
  local name="$1" path="$2" msg
  msg="$name missing at $path — install from Fleet Self service (Fleet Desktop menu bar → My device → Self service)"
  if [ "${FLEET_CHECK:-}" = 1 ]; then
    CHECKED=$(( ${CHECKED:-0} + 1 ))
    warn "$msg"
  else
    printf 'warning: %s\n' "$msg"
  fi
}

# $1 is name|path lines. $2 is "recheck" to stat the paths again.
fleet_report_rows() {
  local missing="$1" mode="${2:-}" name path
  while IFS='|' read -r name path || [ -n "${name:-}" ]; do
    [ -n "${name:-}" ] || continue
    if [ "$mode" = recheck ] && [ -n "$path" ] && [ -d "$path" ]; then
      fleet_note_now "$name"
    else
      fleet_note_still "$name" "$path"
    fi
  done <<EOF
$missing
EOF
}

# Name any app in the list that is not installed. On a terminal, offer to
# open Fleet Self service, then check again. A miss is a warning, not a
# failure: this function returns 0 either way.
fleet_company_apps_prompt() {
  local list="$1" name path missing="" reply
  [ -n "${list:-}" ] && [ -r "$list" ] || return 0
  while IFS='|' read -r name path _ || [ -n "${name:-}" ]; do
    name="$(printf '%s' "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    path="$(printf '%s' "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$name" in
      ''|\#*) continue ;;
    esac
    [ -n "$path" ] || continue
    if [ -d "$path" ]; then
      fleet_note_present "$name"
    else
      missing="${missing}${name}|${path}"$'\n'
    fi
  done < "$list"
  [ -n "$missing" ] || return 0

  printf 'Missing company apps:\n'
  while IFS='|' read -r name path || [ -n "${name:-}" ]; do
    [ -n "${name:-}" ] || continue
    printf '  - %s (%s)\n' "$name" "$path"
  done <<EOF
$missing
EOF

  if fleet_should_offer; then
    printf 'Open Fleet Self service to install them now? [Y/n] '
    read -r reply || reply=''
    case "$reply" in
      n|N|no|NO)
        fleet_print_how
        fleet_report_rows "$missing"
        return 0
        ;;
    esac
    fleet_open_self_service
    printf 'Press Enter after installing them. '
    read -r _ || true
    fleet_report_rows "$missing" recheck
    return 0
  fi

  fleet_print_how
  fleet_report_rows "$missing"
  return 0
}
