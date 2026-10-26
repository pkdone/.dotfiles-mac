# shellcheck shell=bash
#
# hermetic.sh — a PATH for tests that must not see this machine.
#
# Source this file. hermetic_safe_root prints a directory of symlinks to
# ordinary Unix tools (awk, python3, perl, bash, ...) and leaves out the
# commands that read or change a Mac: lpstat, pmset, system_profiler,
# displayplacer, sfltool, shortcuts, dscl, defaults, ioreg, and the rest of
# hermetic_denied. A test puts its own stubs in front of that directory.
# $PATH is not copied in, so a tool installed on this Mac (Homebrew fish,
# /usr/bin/lpstat, a real defaults) is not found by accident.
#
# hermetic_configured_root writes stubs that answer the way Paul's configured
# Mac does. tests/run-all.sh --configured-mac puts that directory first on
# PATH. A test that still falls through to $PATH then sees "ok" instead of
# "command not found", which is what Linux CI would have said, and the
# assertion fails here.
#
# Bash 3.2-safe. Sourcing this file does not change PATH and does not set
# shell options.

# 0 when $1 is a command tests must stub or leave missing.
hermetic_denied() {
  case "$1" in
    lpstat|lpadmin|lp|lpq|lpr|cancel|cupsfilter|pmset|system_profiler|displayplacer|sfltool|shortcuts|dscl|defaults|ioreg|osascript|open|killall|pgrep|pkill|launchctl|scutil|networksetup|profiles|systemextensionsctl|mdfind|mdls|plutil|PlistBuddy|sqlite3|brew|sudo|spctl|csrutil|fdesetup|sysadminctl|diskutil|tmutil|softwareupdate|caffeinate|screencapture|say|pbcopy|pbpaste|sample|spindump|powermetrics|memory_pressure|sw_vers|nvram|codesign|xattr|xcode-select|hdiutil|pkgutil|installer|ditto|sips|textutil|automator|corebrightnessdiag|socketfilterfw|pluginkit|bioutil|assetutil|brctl|lsbom|kmutil|kextstat|kextload|netstat|df|du|sysctl|log|duti|op|gh|hs)
      return 0
      ;;
  esac
  return 1
}

# Link the safe tools into $1. .ready is written last, inside this private
# directory, before anything publishes it.
hermetic_safe_fill() {
  local dest="$1" d f base
  for d in /bin /usr/bin /usr/sbin /sbin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -e "$f" ] || continue
      [ -x "$f" ] || continue
      [ -d "$f" ] && continue
      base="$(basename "$f")"
      hermetic_denied "$base" && continue
      [ -e "$dest/$base" ] && continue
      ln -s "$f" "$dest/$base" 2>/dev/null || true
    done
  done
  : > "$dest/.ready"
}

# Print the shared safe directory.
# The tree is built in a private directory and published with rename, which
# is atomic on the same filesystem. Callers only use a directory that already
# contains .ready, so a cold parallel run never sees awk without python3,
# perl, or cut. run-all.sh builds it once before starting workers; a suite
# run on its own uses the same publish.
hermetic_safe_root() {
  local dest priv i
  # The suffix is part of the cache key. Bump it when hermetic_denied
  # changes, or a previous directory would still expose a command that
  # should now be hidden (gh was linked before it was denied).
  if [ -n "${HERMETIC_SAFE_OVERRIDE:-}" ]; then
    dest="$HERMETIC_SAFE_OVERRIDE"
  else
    dest="${TMPDIR:-/tmp}/dotfiles-hermetic-safe-${UID:-0}-6"
  fi
  if [ -n "${HERMETIC_SAFE_DIR:-}" ] && [ -f "${HERMETIC_SAFE_DIR}/.ready" ]; then
    printf '%s\n' "$HERMETIC_SAFE_DIR"
    return 0
  fi
  if [ -f "$dest/.ready" ]; then
    HERMETIC_SAFE_DIR="$dest"
    printf '%s\n' "$dest"
    return 0
  fi
  priv="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-hermetic-build.XXXXXX")"
  hermetic_safe_fill "$priv"
  # rename(2) replaces nothing that is already visible. If dest exists, this
  # fails and the other publisher's directory is the one to use.
  if mv "$priv" "$dest" 2>/dev/null; then
    HERMETIC_SAFE_DIR="$dest"
    printf '%s\n' "$dest"
    return 0
  fi
  rm -rf "$priv"
  i=0
  while [ ! -f "$dest/.ready" ]; do
    i=$((i + 1))
    if [ "$i" -ge 20 ]; then
      priv="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-hermetic-build.XXXXXX")"
      hermetic_safe_fill "$priv"
      HERMETIC_SAFE_DIR="$priv"
      printf '%s\n' "$priv"
      return 0
    fi
    sleep 1
  done
  HERMETIC_SAFE_DIR="$dest"
  printf '%s\n' "$dest"
}

# Absolute path of fish, or return 1. A login PATH is not required:
# Homebrew on Apple silicon installs fish at /opt/homebrew/bin/fish, which
# a non-interactive shell often does not have on PATH.
hermetic_fish() {
  local c
  c="$(command -v fish 2>/dev/null || true)"
  if [ -n "$c" ] && [ -x "$c" ]; then
    # command -v can print a shell function. Only a real binary is usable
    # once the test replaces PATH.
    case "$c" in
      /*) printf '%s\n' "$c"; return 0 ;;
    esac
  fi
  for c in /opt/homebrew/bin/fish /usr/local/bin/fish /usr/bin/fish; do
    if [ -x "$c" ]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

# Write configured-Mac stubs into $1 and print that directory.
hermetic_configured_root() {
  local dest="$1" name
  mkdir -p "$dest/btm-empty"
  cat > "$dest/lpstat" <<'EOF'
#!/bin/sh
case "${1:-}" in
  -p) printf '%s\n' "printer HP_ENVY_6000_series is idle. enabled since today" ;;
  -v) printf '%s\n' "device for HP_ENVY_6000_series: dnssd://HP%20ENVY%206000" ;;
esac
exit 0
EOF
  cat > "$dest/pmset" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-g" ] && [ "${2:-}" = "custom" ]; then
  cat <<'CUSTOM'
Battery Power:
 lidwake              1
 displaysleep         2
 Sleep On Power Button 1
 sleep                1
 lessbright           1
 disksleep            10
AC Power:
 lidwake              1
 displaysleep         10
 Sleep On Power Button 1
 sleep                0
 womp                 1
 tcpkeepalive         1
 disksleep            10
CUSTOM
  exit 0
fi
exit 0
EOF
  cat > "$dest/system_profiler" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "SPDisplaysDataType" ]; then
  printf '%s\n' '{"SPDisplaysDataType":[{"spdisplays_ndrvs":[{"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal","_spdisplays_resolution":"1800 x 1169 @ 120.00Hz","spdisplays_pixelresolution":"spdisplays_3024x1964Retina"}]}]}'
  exit 0
fi
exit 1
EOF
  cat > "$dest/displayplacer" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "list" ]; then
  cat <<'LIST'
Persistent screen id: BUILTIN-ID
Type: MacBook built in screen
Resolution: 1800x1169
Hertz: 120
Color Depth: 8
Scaling: on
Origin: (0,0) - main display
Rotation: 0
Resolutions for rotation 0:
  mode 0: res:1800x1169 hz:120 color_depth:8 scaling:on
LIST
  exit 0
fi
exit 0
EOF
  cat > "$dest/shortcuts" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "list" ]; then
  printf '%s\n' "Mode WebConf On" "Mode WebConf Off" "Mode DeepWork On" "Mode DeepWork Off"
fi
exit 0
EOF
  cat > "$dest/sfltool" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "dumpbtm" ]; then
  cat <<'DUMP'
 #4:
                 Name: Karabiner-Core-Service
          Disposition: [enabled, allowed, notified] (11)
 #5:
                 Name: Karabiner-VirtualHIDDevice-Daemon
          Disposition: [enabled, allowed] (3)
DUMP
fi
exit 0
EOF
  cat > "$dest/osascript" <<'EOF'
#!/bin/sh
printf '%s\n' "Tailscale"
exit 0
EOF
  cat > "$dest/open" <<'EOF'
#!/bin/sh
exit 0
EOF
  cat > "$dest/corebrightnessdiag" <<'EOF'
#!/bin/sh
[ "${1:-}" = "status-info" ] || exit 1
cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CBAutoBrightnessEnabled</key>
  <false/>
  <key>DisplayBrightnessAuto</key>
  <integer>0</integer>
</dict>
</plist>
PLIST
exit 0
EOF
  # Every other denied command is present and succeeds, so command -v does
  # not report it missing the way a bare Linux runner would.
  for name in lpadmin lp lpq lpr cancel cupsfilter dscl defaults ioreg killall pgrep pkill launchctl scutil networksetup profiles systemextensionsctl mdfind mdls plutil PlistBuddy sqlite3 brew sudo spctl csrutil fdesetup sysadminctl diskutil tmutil softwareupdate caffeinate screencapture say pbcopy pbpaste sample spindump powermetrics memory_pressure sw_vers nvram codesign xattr xcode-select hdiutil pkgutil installer ditto sips textutil automator socketfilterfw pluginkit bioutil assetutil brctl lsbom kmutil kextstat kextload netstat df du sysctl log duti op gh hs; do
    if [ ! -e "$dest/$name" ]; then
      printf '%s\n' '#!/bin/sh' 'exit 0' > "$dest/$name"
    fi
  done
  chmod +x "$dest"/*
  printf '%s\n' "$dest"
}
