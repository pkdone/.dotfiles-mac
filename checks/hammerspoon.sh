# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# Sourced by macconfig-check.sh. Runs in the current shell (not a subshell)
# so a failing command still stops the check the way it did before the split.

# Lua string literal. hs runs this in the Hammerspoon process, which does not
# see environment variables set on the hs CLI, so the path has to be in the code.
lua_quote() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

# hs_loadfile_code PATH — Lua the hs CLI sends to the running app. The path is in
# the source: os.getenv would read the app's environment, not the CLI's.
hs_loadfile_code() {
  printf 'local f, err = loadfile(%s); if not f then return "error: " .. tostring(err) end return "ok"' "$(lua_quote "$1")"
}

# lua_syntax_code PATH — same compile, for a local lua process (exit 1 on error).
lua_syntax_code() {
  printf 'local f, err = loadfile(%s); if not f then io.stderr:write(err or ""); os.exit(1) end' "$(lua_quote "$1")"
}

# hammerspoon_config_line — one line: ok|msg or warn|msg
# Uses hs when Hammerspoon is running. Otherwise a lua syntax check of the
# repo init.lua. loadfile compiles; it does not run the config.
hammerspoon_config_line() {
  local cfg="$DOTDIR/hammerspoon/init.lua" tool out rc err code
  if [ ! -f "$cfg" ]; then
    printf 'warn|hammerspoon/init.lua missing — cannot check that the config loads\n'
    return 0
  fi
  if [ "${H_HS_RUNNING:-}" = yes ] && command -v hs >/dev/null 2>&1; then
    rc=0
    code="$(hs_loadfile_code "$cfg")"
    out="$(with_timeout 15 hs -c "$code" </dev/null 2>&1)" || rc=$?
    if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -Eq '^(ok|"ok")$'; then
      printf 'ok|Hammerspoon config compiles (hs loadfile of hammerspoon/init.lua)\n'
      return 0
    fi
    if printf '%s\n' "$out" | grep -q '^error:'; then
      err="$(printf '%s' "$out" | tr '\n' ' ' | sed 's/[[:space:]]*$//' | cut -c1-200)"
      printf 'warn|Hammerspoon config did not compile via hs (%s)\n' "${err:-exit $rc}"
      return 0
    fi
    # hs did not answer with a compile result (IPC). Fall through to luac/lua.
  fi
  tool=""
  for c in luac lua5.4 lua54 lua; do
    if command -v "$c" >/dev/null 2>&1; then
      tool="$c"
      break
    fi
  done
  if [ -z "$tool" ]; then
    printf 'warn|cannot syntax-check hammerspoon/init.lua (hs unavailable and no luac/lua)\n'
    return 0
  fi
  rc=0
  if [ "$tool" = luac ]; then
    err="$("$tool" -p "$cfg" 2>&1)" || rc=$?
  else
    code="$(lua_syntax_code "$cfg")"
    err="$("$tool" -e "$code" 2>&1)" || rc=$?
  fi
  if [ "$rc" = 0 ]; then
    printf 'ok|hammerspoon/init.lua passes a lua syntax check (%s; Hammerspoon hs CLI not used)\n' "$tool"
  else
    err="$(printf '%s' "$err" | tr '\n' ' ' | sed 's/[[:space:]]*$//' | cut -c1-200)"
    printf 'warn|hammerspoon/init.lua syntax error (%s): %s\n' "$tool" "${err:-failed}"
  fi
}

check_hammerspoon_config() {
  local line st msg
  CHECKED=$((CHECKED + 1))
  fixid hammerspoon-config
  line="$(hammerspoon_config_line || true)"
  st="${line%%|*}"
  msg="${line#*|}"
  if [ "$st" = ok ]; then
    pass "$msg"
  else
    warn "${msg:-Hammerspoon config check failed}"
  fi
}

if [ "${MACCONFIG_CHECKS_DEFINE_ONLY:-}" = 1 ]; then
  return 0
fi

# ---- 10b. Hammerspoon (Sidecar -> Slack automation) ----------------------
# The ~/.hammerspoon dir symlink is checked in section 1 (links.list) and the cask in
# section 2 (Brewfile). Here: soft-warn if the app isn't running. Its Accessibility
# grant is a manual step, checked in the "Manual steps" section (id hammerspoon-ax).
# Never launches or changes anything.
hdr "Hammerspoon"
fixid hammerspoon
CHECKED=$((CHECKED + 1))
H_HS_RUNNING=no   # reused by the Mac health JSON (background jobs)
if [ ! -d /Applications/Hammerspoon.app ]; then
  H_HS_RUNNING=not_installed
  fixid app-install
  warn "Hammerspoon.app not installed — brew bundle (cask \"hammerspoon\")"
elif ! pgrep -xq Hammerspoon; then
  warn "Hammerspoon not running — open -a Hammerspoon (then it starts at login)"
else
  H_HS_RUNNING=yes
  pass "Hammerspoon running"
fi
check_hammerspoon_config
