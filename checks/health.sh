# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.

# disk_space_level PCT GB MIN_PCT MIN_GB — prints warn when free space is
# below either floor (15% is MIN_PCT; the gigabyte floor is separate).
disk_space_level() {
  if [ "$1" -lt "$3" ] || [ "$2" -lt "$4" ]; then
    printf 'warn\n'
  else
    printf 'ok\n'
  fi
}

# True when the hotkeys section already reported this LaunchAgent. --only health
# leaves the list empty, so an unloaded pin agent is still a warning.
health_pin_already_reported() {
  case " ${LAUNCHAGENT_CHECKED:-} " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

# ---- 15b. Mac health (soft — warn only, never drift) ---------------------
# Read-only and timeout-guarded. Values are also kept in H_* for --health-json.
# Anything that can't be read without sudo / Full Disk Access is an info (by-hand) line.
hdr "Mac health"
fixid health

# Thresholds: the one place to tune the health warnings.
HEALTH_BATTERY_MIN_PCT=80        # battery maximum capacity
HEALTH_DISK_MIN_GB=50            # free space on the Data volume …
HEALTH_DISK_MIN_PCT=15           # … warn when below either
HEALTH_UPTIME_MAX_DAYS=14
HEALTH_SWAP_MAX_GB=8             # swap in use
HEALTH_CRASH_DAYS=7              # look-back window for panics / crashes
HEALTH_CRASH_SAME_APP=3          # warn at this many crashes of one app in the window
HEALTH_CACHES_MAX_GB=20          # ~/Library/Caches
HEALTH_DOCKER_MAX_GB=60          # Docker Desktop disk image (allocated size)
HEALTH_BREW_CACHE_MAX_GB=5       # brew --cache
HEALTH_DERIVED_DATA_MAX_GB=20    # Xcode DerivedData

H_BAT_STATUS=none; H_BAT_COND=""; H_BAT_MAX=""; H_BAT_CYCLES=""
H_DISK_STATUS=unknown; H_DISK_FREE_GB=""; H_DISK_FREE_PCT=""; H_DISK_TOTAL_GB=""
H_UP_STATUS=unknown; H_UP_DAYS=""
H_MEM_STATUS=unknown; H_MEM_SWAP_GB=""; H_MEM_PRESSURE=unknown; H_MEM_FREE_PCT=""
H_STO_STATUS=ok; H_STO_CACHES=""; H_STO_DOCKER=""; H_STO_BREW=""; H_STO_DERIVED=""
H_SEC_STATUS=ok; H_SEC_FIREWALL=unknown; H_SEC_GATEKEEPER=unknown; H_SEC_SIP=unknown
H_SEC_SSH=unknown; H_SEC_SCREENSHARING=unknown; H_SEC_FILESHARING=unknown; H_SEC_SCREENLOCK=unknown
H_MDM_STATUS=unknown; H_MDM_ENROLLED=unknown; H_MDM_AGENT=unknown
H_CR_STATUS=unknown; H_CR_PANICS=""; H_CR_CRASHES=""; H_CR_FAULTS=""; H_CR_APPS=(); H_CR_PANIC_FILES=()
H_JOBS_STATUS=ok; H_JOBS=()
H_GIT_STATUS=unknown; H_GIT_DIRTY=""; H_GIT_AHEAD=""; H_GIT_BEHIND=""; H_GIT_FETCHED=""
H_LI_STATUS=unknown; H_LI_ENABLED=0; H_LI_ALLOW=0; H_LI_MDM=0; H_LI_UNKNOWN=(); H_LI_STALE=()

kb_to_gb() { awk -v k="$1" 'BEGIN { printf "%.1f", k / 1048576 }'; }   # KiB -> GiB, 1 dp
gb_over() { awk -v v="$1" -v m="$2" 'BEGIN { exit !(v > m) }'; }       # gb_over VALUE MAX
# du_kb PATH... — allocated KiB (sparse Docker.raw counts real use), empty if unreadable.
du_kb() { with_timeout 60 du -sk "$@" 2>/dev/null | awk '{ s += $1 } END { if (NR) print s }'; }

# Battery: condition, maximum capacity and cycle count.
CHECKED=$((CHECKED + 1))
sp_power="$(with_timeout 20 system_profiler SPPowerDataType 2>/dev/null || true)"
H_BAT_COND="$(printf '%s\n' "$sp_power" | awk -F': ' '/^ *Condition:/ {print $2; exit}')"
H_BAT_MAX="$(printf '%s\n' "$sp_power" | awk -F': ' '/^ *Maximum Capacity:/ {gsub(/%/, "", $2); print $2; exit}')"
H_BAT_CYCLES="$(printf '%s\n' "$sp_power" | awk -F': ' '/^ *Cycle Count:/ {print $2; exit}')"
if [ -z "$H_BAT_MAX" ] || [ -z "$H_BAT_CYCLES" ]; then
  # Fallback: raw battery registry (NominalChargeCapacity / DesignCapacity).
  bat_io="$(with_timeout 10 ioreg -rn AppleSmartBattery 2>/dev/null || true)"
  if [ -z "$H_BAT_CYCLES" ]; then
    H_BAT_CYCLES="$(printf '%s\n' "$bat_io" | sed -nE 's/^ *"CycleCount" = ([0-9]+).*/\1/p' | head -1)"
  fi
  if [ -z "$H_BAT_MAX" ]; then
    bat_nom="$(printf '%s\n' "$bat_io" | sed -nE 's/.*"NominalChargeCapacity"=([0-9]+).*/\1/p' | head -1)"
    bat_des="$(printf '%s\n' "$bat_io" | sed -nE 's/.*"DesignCapacity"=([0-9]+).*/\1/p' | head -1)"
    if [ -n "$bat_nom" ] && [ -n "$bat_des" ] && [ "$bat_des" -gt 0 ]; then
      H_BAT_MAX=$(( (bat_nom * 100 + bat_des / 2) / bat_des ))
    fi
  fi
fi
case "$H_BAT_MAX" in *[!0-9]*) H_BAT_MAX="" ;; esac
case "$H_BAT_CYCLES" in *[!0-9]*) H_BAT_CYCLES="" ;; esac
if [ -z "$H_BAT_COND$H_BAT_MAX$H_BAT_CYCLES" ]; then
  note "battery: none found (desktop Mac?) — skipped"
  CHECKED=$((CHECKED - 1))
elif [ -n "$H_BAT_COND" ] && [ "$H_BAT_COND" != Normal ]; then
  H_BAT_STATUS=warn
  warn "battery condition ${H_BAT_COND} (max capacity ${H_BAT_MAX:-?}%, ${H_BAT_CYCLES:-?} cycles) — System Settings → Battery → Battery Health"
elif [ -n "$H_BAT_MAX" ] && [ "$H_BAT_MAX" -lt "$HEALTH_BATTERY_MIN_PCT" ]; then
  H_BAT_STATUS=warn
  warn "battery max capacity ${H_BAT_MAX}% (< ${HEALTH_BATTERY_MIN_PCT}%; ${H_BAT_CYCLES:-?} cycles) — consider a service"
else
  H_BAT_STATUS=ok
  pass "battery ${H_BAT_COND:-condition unknown}, max capacity ${H_BAT_MAX:-?}%, ${H_BAT_CYCLES:-?} cycles"
fi

# Disk: free space on the Data volume; warn below either threshold.
CHECKED=$((CHECKED + 1))
disk_vol=/System/Volumes/Data
[ -d "$disk_vol" ] || disk_vol=/
read -r disk_total_k disk_avail_k < <(with_timeout 10 df -k "$disk_vol" 2>/dev/null | awk 'NR==2 {print $2, $4}') || true
if [ -n "${disk_total_k:-}" ] && [ -n "${disk_avail_k:-}" ] && [ "$disk_total_k" -gt 0 ]; then
  H_DISK_FREE_GB=$(( disk_avail_k * 1024 / 1000000000 ))
  H_DISK_TOTAL_GB=$(( disk_total_k * 1024 / 1000000000 ))
  H_DISK_FREE_PCT=$(( disk_avail_k * 100 / disk_total_k ))
  if [ "$(disk_space_level "$H_DISK_FREE_PCT" "$H_DISK_FREE_GB" "$HEALTH_DISK_MIN_PCT" "$HEALTH_DISK_MIN_GB")" = warn ]; then
    H_DISK_STATUS=warn
    warn "disk: only ${H_DISK_FREE_GB} GB free (${H_DISK_FREE_PCT}%) on $disk_vol — want ≥ ${HEALTH_DISK_MIN_GB} GB and ≥ ${HEALTH_DISK_MIN_PCT}%"
  else
    H_DISK_STATUS=ok
    pass "disk: ${H_DISK_FREE_GB} GB free of ${H_DISK_TOTAL_GB} GB (${H_DISK_FREE_PCT}%)"
  fi
else
  warn "disk: couldn't read free space for $disk_vol (df failed)"
fi

# Uptime: a reboot every couple of weeks lets updates and long-running leaks settle.
CHECKED=$((CHECKED + 1))
boot_sec="$(sysctl -n kern.boottime 2>/dev/null | sed -nE 's/.*[{] sec = ([0-9]+),.*/\1/p')"
if [ -n "$boot_sec" ]; then
  H_UP_DAYS=$(( ($(date +%s) - boot_sec) / 86400 ))
  if [ "$H_UP_DAYS" -gt "$HEALTH_UPTIME_MAX_DAYS" ]; then
    H_UP_STATUS=warn
    warn "uptime ${H_UP_DAYS} days (> ${HEALTH_UPTIME_MAX_DAYS}) — restart when convenient"
  else
    H_UP_STATUS=ok
    pass "uptime ${H_UP_DAYS} day(s)"
  fi
else
  warn "uptime unknown (sysctl kern.boottime failed)"
fi

# Memory: swap in use and the kernel's memory-pressure level (1 normal, 2 warn, 4 critical).
CHECKED=$((CHECKED + 1))
swap_mb="$(sysctl -n vm.swapusage 2>/dev/null | sed -nE 's/.*used = ([0-9.]+)M.*/\1/p')"
[ -n "$swap_mb" ] && H_MEM_SWAP_GB="$(awk -v m="$swap_mb" 'BEGIN { printf "%.1f", m / 1024 }')"
case "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)" in
  1) H_MEM_PRESSURE=normal ;; 2) H_MEM_PRESSURE=warn ;; 4) H_MEM_PRESSURE=critical ;; *) H_MEM_PRESSURE=unknown ;;
esac
H_MEM_FREE_PCT="$(with_timeout 10 memory_pressure -Q 2>/dev/null | sed -nE 's/.*free percentage: ([0-9]+)%.*/\1/p')"
if [ -z "$H_MEM_SWAP_GB" ] && [ "$H_MEM_PRESSURE" = unknown ]; then
  warn "memory: couldn't read swap or memory pressure"
elif [ "$H_MEM_PRESSURE" = critical ] || { [ -n "$H_MEM_SWAP_GB" ] && gb_over "$H_MEM_SWAP_GB" "$HEALTH_SWAP_MAX_GB"; }; then
  H_MEM_STATUS=warn
  warn "memory: pressure $H_MEM_PRESSURE, swap ${H_MEM_SWAP_GB:-?} GB used (> ${HEALTH_SWAP_MAX_GB} GB or critical) — quit heavy apps (Activity Monitor → Memory) or restart"
else
  H_MEM_STATUS=ok
  pass "memory: pressure $H_MEM_PRESSURE, ${H_MEM_FREE_PCT:-?}% free, swap ${H_MEM_SWAP_GB:-?} GB used"
fi

# Storage hogs: allocated sizes, each against its own threshold, with the usual fix.
sto_check() {  # label KiB max_gb fix -> sets sto_gb
  sto_gb=""
  [ -n "$2" ] || return 0
  CHECKED=$((CHECKED + 1))
  sto_gb="$(kb_to_gb "$2")"
  if gb_over "$sto_gb" "$3"; then
    H_STO_STATUS=warn
    warn "$1: ${sto_gb} GB (> $3 GB) — $4"
  else
    pass "$1: ${sto_gb} GB"
  fi
}
sto_check "User caches (~/Library/Caches)" "$(du_kb "$HOME/Library/Caches")" "$HEALTH_CACHES_MAX_GB" \
  "see du -sh ~/Library/Caches/* | sort -h and clear the biggest app caches (quit the app first)"
H_STO_CACHES="$sto_gb"
shopt -s nullglob
docker_raw=("$HOME"/Library/Containers/com.docker.docker/Data/vms/*/data/Docker.raw)
shopt -u nullglob
if [ "${#docker_raw[@]}" -gt 0 ]; then
  sto_check "Docker disk image" "$(du_kb "${docker_raw[@]}")" "$HEALTH_DOCKER_MAX_GB" \
    "docker system prune -a (or Docker Desktop → Troubleshoot → Clean / Purge data)"
  H_STO_DOCKER="$sto_gb"
fi
brew_cache="$(with_timeout 10 brew --cache 2>/dev/null || true)"
if [ -n "$brew_cache" ] && [ -d "$brew_cache" ]; then
  sto_check "Homebrew cache" "$(du_kb "$brew_cache")" "$HEALTH_BREW_CACHE_MAX_GB" "brew cleanup --prune=all"
  H_STO_BREW="$sto_gb"
fi
if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
  sto_check "Xcode DerivedData" "$(du_kb "$HOME/Library/Developer/Xcode/DerivedData")" "$HEALTH_DERIVED_DATA_MAX_GB" \
    "delete ~/Library/Developer/Xcode/DerivedData (Xcode rebuilds it)"
  H_STO_DERIVED="$sto_gb"
fi

fixid security
# Security basics. MDM may manage some of these; unreadable ones are by-hand info lines.
sec_on() {  # label value(on|off|unknown) want(on|off) fix-hint -> echoes nothing
  case "$2" in
    unknown) info "$1: couldn't read — check by hand ($4)" ;;
    "$3")    CHECKED=$((CHECKED + 1)); pass "$1 $2" ;;
    *)       CHECKED=$((CHECKED + 1)); H_SEC_STATUS=warn; warn "$1 $2 (want $3) — $4" ;;
  esac
}
fw="$(with_timeout 5 /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate </dev/null 2>/dev/null || true)"
case "$fw" in
  *"State = 1"*|*"State = 2"*) H_SEC_FIREWALL=on ;;
  *"State = 0"*) H_SEC_FIREWALL=off ;;
esac
sec_on "Application Firewall" "$H_SEC_FIREWALL" on "System Settings → Network → Firewall (may be MDM-managed)"
case "$(with_timeout 5 spctl --status </dev/null 2>&1 || true)" in
  *"assessments enabled"*)  H_SEC_GATEKEEPER=on ;;
  *"assessments disabled"*) H_SEC_GATEKEEPER=off ;;
esac
sec_on "Gatekeeper" "$H_SEC_GATEKEEPER" on "sudo spctl --global-enable"
case "$(with_timeout 5 csrutil status </dev/null 2>&1 || true)" in
  *"status: enabled"*)  H_SEC_SIP=on ;;
  *"status: disabled"*) H_SEC_SIP=off ;;
esac
sec_on "System Integrity Protection" "$H_SEC_SIP" on "re-enable from Recovery: csrutil enable"
# Sharing services, without sudo: a launchd job that's loaded, or a listening port.
listen_ports="$(with_timeout 5 netstat -anp tcp 2>/dev/null | awk '$6 == "LISTEN" {print $4}' || true)"
svc_state() {  # launchd-label port -> on|off
  if with_timeout 5 launchctl print "system/$1" </dev/null >/dev/null 2>&1; then echo on; return; fi
  if printf '%s\n' "$listen_ports" | grep -Eq "[.:]$2\$"; then echo on; return; fi
  echo off
}
H_SEC_SSH="$(svc_state com.openssh.sshd 22)"
sec_on "Remote Login (SSH)" "$H_SEC_SSH" off "System Settings → General → Sharing → Remote Login"
H_SEC_SCREENSHARING="$(svc_state com.apple.screensharing 5900)"
sec_on "Screen Sharing" "$H_SEC_SCREENSHARING" off "System Settings → General → Sharing → Screen Sharing"
H_SEC_FILESHARING="$(svc_state com.apple.smbd 445)"
sec_on "File Sharing" "$H_SEC_FILESHARING" off "System Settings → General → Sharing → File Sharing"
# Password after sleep/screen saver (often MDM-managed). sysadminctl reports on stderr.
sl="$(with_timeout 5 sysadminctl -screenLock status </dev/null 2>&1 || true)"
case "$sl" in
  *"delay is immediate"*) H_SEC_SCREENLOCK=immediate ;;
  *"screenLock is off"*)  H_SEC_SCREENLOCK=off ;;
  *"delay is "*)          H_SEC_SCREENLOCK="$(printf '%s\n' "$sl" | sed -nE 's/.*delay is (.*)$/\1/p' | head -1)" ;;
esac
case "$H_SEC_SCREENLOCK" in
  immediate) CHECKED=$((CHECKED + 1)); pass "password required immediately after sleep / screen saver" ;;
  unknown)   info "screen lock: couldn't read — check by hand (System Settings → Lock Screen; may be MDM-managed)" ;;
  *)         CHECKED=$((CHECKED + 1)); H_SEC_STATUS=warn
             warn "screen lock: password required after '$H_SEC_SCREENLOCK' (want immediately) — System Settings → Lock Screen (may be MDM-managed)" ;;
esac

fixid mdm
# MDM: enrolment (non-sudo `profiles status`) and the Fleet agent.
# Orbit is the launch daemon. It runs osquery and starts Fleet Desktop
# from /opt/orbit. Those are not separate launchd jobs.
prof="$(with_timeout 10 profiles status -type enrollment </dev/null 2>&1 || true)"
case "$prof" in
  *"MDM enrollment: Yes"*) H_MDM_ENROLLED=yes ;;
  *"MDM enrollment: No"*)  H_MDM_ENROLLED=no ;;
esac
mdm_down=""
mdm_label="com.fleetdm.orbit"
if ! with_timeout 5 launchctl print "system/$mdm_label" </dev/null 2>/dev/null | grep -q 'state = running'; then
  mdm_down=" $mdm_label"
fi
if [ -z "$mdm_down" ]; then H_MDM_AGENT=yes; else H_MDM_AGENT=no; fi
if [ "$H_MDM_ENROLLED" = unknown ]; then
  info "MDM enrolment: couldn't read (profiles status) — check by hand"
  H_MDM_STATUS=unknown
fi
CHECKED=$((CHECKED + 1))
if [ "$H_MDM_ENROLLED" = no ] || [ "$H_MDM_AGENT" = no ]; then
  H_MDM_STATUS=warn
  warn "MDM: enrolled=$H_MDM_ENROLLED, Fleet agent not running:${mdm_down:- none} — open Fleet Desktop or contact IT"
else
  [ "$H_MDM_ENROLLED" = yes ] && H_MDM_STATUS=ok
  pass "MDM: enrolled=${H_MDM_ENROLLED}, Fleet agent (orbit) running"
fi

fixid health
# Crashes: kernel panics and app crash reports in the window (lib/crash-reports.py).
CRASH_HELPER="$DOTDIR/lib/crash-reports.py"
if [ -z "$DOT_PYTHON" ] || [ ! -r "$CRASH_HELPER" ]; then
  info "crash reports: needs python3 and lib/crash-reports.py — check by hand (Console → Crash Reports)"
else
  CHECKED=$((CHECKED + 1))
  cr_raw="$(with_timeout 20 "$DOT_PYTHON" "$CRASH_HELPER" "$HEALTH_CRASH_DAYS" 2>/dev/null || true)"
  cr_many=""
  while IFS='|' read -r cr_kind cr_a cr_b cr_c _cr_d; do
    case "$cr_kind" in
      panic)  H_CR_PANIC_FILES+=("$cr_a") ;;
      crash)  H_CR_APPS+=("$cr_a|$cr_b")
              if [ "$cr_b" -ge "$HEALTH_CRASH_SAME_APP" ]; then cr_many="$cr_many, $cr_a ×$cr_b"; fi ;;
      totals) H_CR_PANICS="$cr_a"; H_CR_CRASHES="$cr_b"; H_CR_FAULTS="$cr_c" ;;
    esac
  done <<< "$cr_raw"
  cr_list=""
  for x in ${H_CR_APPS[@]+"${H_CR_APPS[@]}"}; do cr_list="$cr_list, ${x%%|*} ×${x##*|}"; done
  if [ -z "$H_CR_PANICS" ]; then
    H_CR_STATUS=unknown
    warn "crash reports: helper failed — check Console → Crash Reports by hand"
  elif [ "$H_CR_PANICS" -gt 0 ] || [ -n "$cr_many" ]; then
    H_CR_STATUS=warn
    if [ "$H_CR_PANICS" -gt 0 ]; then
      warn "$H_CR_PANICS kernel panic(s) in the last $HEALTH_CRASH_DAYS days: ${H_CR_PANIC_FILES[*]} — see /Library/Logs/DiagnosticReports"
    fi
    if [ -n "$cr_many" ]; then
      warn "apps crashing repeatedly (≥ $HEALTH_CRASH_SAME_APP in $HEALTH_CRASH_DAYS days): ${cr_many#, } — update or reinstall them"
    fi
  else
    H_CR_STATUS=ok
    pass "no kernel panics; $H_CR_CRASHES app crash(es) in $HEALTH_CRASH_DAYS days${cr_list:+ (${cr_list#, })}"
  fi
fi

# Background jobs: every LaunchAgent this repo installs (launchagents/*.plist, rendered
# into ~/Library/LaunchAgents) is loaded and its last run exited 0. A pin agent the
# hotkeys section already reported (LAUNCHAGENT_CHECKED) is not reported twice.
# --only health did not run that section, so an unloaded pin agent is still a warning.
# Hammerspoon "running" is the Hammerspoon section's result (H_HS_RUNNING), reused
# for --health-json.
for la_src in "$DOTDIR"/launchagents/*.plist; do
  [ -f "$la_src" ] || continue
  la_label="$(basename "$la_src" .plist)"
  CHECKED=$((CHECKED + 1))
  fixid launchagent "$la_label|$HOME/Library/LaunchAgents/$la_label.plist"
  if ! la_out="$(with_timeout 5 launchctl print "gui/$(id -u)/$la_label" </dev/null 2>/dev/null)"; then
    H_JOBS+=("$la_label|no|")
    if health_pin_already_reported "$la_label"; then
      CHECKED=$((CHECKED - 1))   # already reported as drift in its own section
    else
      H_JOBS_STATUS=warn; warn "LaunchAgent $la_label not loaded — re-run install.sh"
    fi
    continue
  fi
  la_exit="$(printf '%s\n' "$la_out" | sed -nE 's/^[[:space:]]*last exit code = (.*)$/\1/p' | head -1)"
  case "$la_exit" in
    0)                 H_JOBS+=("$la_label|yes|0"); pass "LaunchAgent $la_label loaded, last exit 0" ;;
    ''|*never*)        H_JOBS+=("$la_label|yes|"); pass "LaunchAgent $la_label loaded (hasn't run yet)" ;;
    *)                 H_JOBS+=("$la_label|yes|$la_exit"); H_JOBS_STATUS=warn; fixid launchagent-exit
                       warn "LaunchAgent $la_label last exit code $la_exit — check: launchctl print gui/$(id -u)/$la_label" ;;
  esac
done

fixid dotfiles-git
# Dotfiles in sync: no uncommitted/untracked changes (gitignored .agent-logs etc. don't
# count) and HEAD level with origin/main AS OF THE LAST FETCH/PUSH — no network here, so
# macconfig-check.sh stays offline and read-only (--no-optional-locks: don't even refresh the index).
CHECKED=$((CHECKED + 1))
if ! git -C "$DOTDIR" rev-parse --git-dir >/dev/null 2>&1; then
  warn "dotfiles: $DOTDIR isn't a git repo"
else
  H_GIT_DIRTY="$(with_timeout 10 git --no-optional-locks -C "$DOTDIR" status --porcelain -- . ':(exclude).agent-logs' 2>/dev/null | grep -c . || true)"
  read -r H_GIT_AHEAD H_GIT_BEHIND < <(with_timeout 10 git -C "$DOTDIR" rev-list --left-right --count HEAD...origin/main 2>/dev/null) || true
  fetch_head="$(git -C "$DOTDIR" rev-parse --git-path FETCH_HEAD 2>/dev/null)"
  case "$fetch_head" in /*) ;; *) fetch_head="$DOTDIR/$fetch_head" ;; esac
  [ -f "$fetch_head" ] && H_GIT_FETCHED="$(date -r "$fetch_head" '+%Y-%m-%d %H:%M %Z')"
  git_issues=""
  [ "${H_GIT_DIRTY:-0}" -gt 0 ] && git_issues="$git_issues; $H_GIT_DIRTY uncommitted/untracked change(s) (dotpush)"
  [ "${H_GIT_AHEAD:-0}" -gt 0 ] && git_issues="$git_issues; $H_GIT_AHEAD commit(s) not pushed (git push)"
  [ "${H_GIT_BEHIND:-0}" -gt 0 ] && git_issues="$git_issues; $H_GIT_BEHIND commit(s) behind origin/main (git pull)"
  if [ -z "${H_GIT_AHEAD:-}" ]; then
    H_GIT_STATUS=warn; warn "dotfiles: no origin/main to compare with${git_issues:+$git_issues}"
  elif [ -n "$git_issues" ]; then
    H_GIT_STATUS=warn; warn "dotfiles out of sync: ${git_issues#; }"
  else
    H_GIT_STATUS=ok
    pass "dotfiles clean and level with origin/main (as of last fetch/push${H_GIT_FETCHED:+; last fetch $H_GIT_FETCHED})"
  fi
fi

fixid login-items
# Login / background items: every ENABLED item must be on lib/login-items-allow.list or
# approved by an MDM Service Management rule; stale items (app gone) are flagged too.
# Reuses lib/btm-login-items.py (same BTM store as the banned-item guard above).
CHECKED=$((CHECKED + 1))
ALLOW_LIST="$DOTDIR/lib/login-items-allow.list"
if [ ! -r "$BTM_HELPER" ] || [ ! -r "$ALLOW_LIST" ] || [ -z "$DOT_PYTHON" ]; then
  fixid tooling; warn "login-item audit skipped (needs python3, lib/btm-login-items.py and lib/login-items-allow.list)"
else
  if li_raw="$(with_timeout 20 "$DOT_PYTHON" "$BTM_HELPER" --audit "$ALLOW_LIST" 2>&1)"; then li_rc=0; else li_rc=$?; fi
  if [ "$li_rc" = 3 ] || printf '%s\n' "$li_raw" | grep -q 'tcc=denied'; then
    fixid tcc; warn "login-item audit: BTM unreadable (Full Disk Access) — System Settings → Privacy & Security → Full Disk Access → enable Ghostty"
  elif [ "$li_rc" -ne 0 ]; then
    warn "login-item audit failed (rc=$li_rc) — check Login Items by hand"
  else
    while IFS='|' read -r li_class li_kind li_name li_dev li_team li_id li_detail; do
      case "$li_class" in
        allow)   H_LI_ENABLED=$((H_LI_ENABLED + 1)); H_LI_ALLOW=$((H_LI_ALLOW + 1)) ;;
        mdm)     H_LI_ENABLED=$((H_LI_ENABLED + 1)); H_LI_MDM=$((H_LI_MDM + 1)) ;;
        unknown)
          H_LI_ENABLED=$((H_LI_ENABLED + 1)); H_LI_UNKNOWN+=("$li_name ($li_kind, $li_id)")
          warn "unexpected login item: $li_name ($li_kind; ${li_dev:-unknown developer}${li_team:+, team $li_team}; $li_id) — turn it Off in System Settings → General → Login Items & Extensions, or add it to lib/login-items-allow.list" ;;
        stale)
          H_LI_ENABLED=$((H_LI_ENABLED + 1)); H_LI_STALE+=("$li_name ($li_id): $li_detail")
          warn "stale login item: $li_name ($li_id) $li_detail — remove it in System Settings → General → Login Items & Extensions (re-add the app if you still want it at login)" ;;
        allowlist:*) warn "lib/login-items-allow.list: ${li_class#allowlist: }" ;;
      esac
    done <<< "$li_raw"
    if [ "${#H_LI_UNKNOWN[@]}" -eq 0 ] && [ "${#H_LI_STALE[@]}" -eq 0 ]; then
      H_LI_STATUS=ok
      pass "login items: all $H_LI_ENABLED enabled items expected ($H_LI_ALLOW allow-listed, $H_LI_MDM MDM-approved)"
    else
      H_LI_STATUS=warn
    fi
  fi
fi
