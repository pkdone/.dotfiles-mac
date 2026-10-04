-- Hammerspoon config entry point.
-- Symlinked as a directory: ~/.hammerspoon -> ~/.dotfiles-mac/hammerspoon
-- (via lib/links.list; install.sh creates it, check.sh verifies it).
--
-- Keep this file small: each automation lives in its own module next to it and is
-- listed in MODULES below. A module returns a table with a start() function.

-- `hs` CLI support (hs -c '...'). The Homebrew cask links the binary to
-- /opt/homebrew/bin/hs; this just opens the message port it talks to.
require('hs.ipc')

-- App behaviour (Hammerspoon persists these in org.hammerspoon.Hammerspoon).
hs.autoLaunch(true)        -- start at login
hs.consoleOnTop(false)
hs.menuIcon(true)          -- menu-bar icon is the way in (console, reload)
hs.dockIcon(false)         -- no Dock icon (not in lib/dock-apps.list)
hs.uploadCrashData(false)  -- don't send crash reports from a work Mac

local log = hs.logger.new('init', 'info')

-- Automations to load, in order. Add new modules here (e.g. 'trackpad_mute').
local MODULES = {
  'sidecar_slack',  -- Sidecar on: Slack -> iPad, full screen, zoom out; off: reverse
}

-- Global so started modules (and their watchers/hotkeys) are never garbage-collected.
loaded = {}

for _, name in ipairs(MODULES) do
  local ok, mod = pcall(require, name)
  if ok and type(mod) == 'table' and type(mod.start) == 'function' then
    local started, err = pcall(mod.start)
    if started then
      loaded[name] = mod
      log.i('started module ' .. name)
    else
      log.e('module ' .. name .. ' failed to start: ' .. tostring(err))
      hs.alert.show('Hammerspoon: ' .. name .. ' failed to start (see Console)', 3)
    end
  else
    log.e('could not load module ' .. name .. ': ' .. tostring(mod))
    hs.alert.show('Hammerspoon: could not load ' .. name .. ' (see Console)', 3)
  end
end

hs.alert.show('Hammerspoon config loaded', 1)
