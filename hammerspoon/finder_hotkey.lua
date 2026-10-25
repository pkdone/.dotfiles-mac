-- finder_hotkey.lua: bring Finder to the front.
--
-- Shift+Control+Command+F launches Finder, or focuses it when it is already
-- running. Hammerspoon owns this shortcut.
--
-- The app name, modifiers, and key are plain fields. tests/finder_hotkey_spec.lua
-- reads them with a normal Lua interpreter, no Hammerspoon.

local M = {}

M.app = 'Finder'
-- Same modifier names as sidecar_slack.lua (shift, ctrl, cmd). No Option.
M.mods = { 'shift', 'ctrl', 'cmd' }
M.key = 'f'

local hotkey

function M.press()
  hs.application.launchOrFocus(M.app)
end

function M.start()
  M.stop()
  hotkey = hs.hotkey.bind(M.mods, M.key, M.press)
  return M
end

function M.stop()
  if hotkey then hotkey:delete(); hotkey = nil end
end

return M
