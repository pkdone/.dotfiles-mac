-- sidecar_slack.lua: automate the Sidecar + Slack routine.
--
-- Sidecar starts (an iPad display appears):
--   Slack's main window -> Sidecar screen -> full screen -> Cmd - (zoom out one step).
-- Sidecar stops (the display goes away):
--   exit full screen -> back on the built-in/main screen -> Cmd = (zoom back in).
--
-- Acts only on transitions (absent -> present, present -> absent), debounced because
-- hs.screen.watcher can fire several times per change. Cmd = is only sent if this
-- module sent Cmd - earlier (persisted in hs.settings), so Slack's zoom stays balanced
-- across reloads and restarts.
--
-- Manual test / override: Shift+Control+Option+Command+S toggles the routine.
-- Debug from a terminal:  hs -c 'loaded.sidecar_slack.status()'
-- If your Sidecar screen name doesn't match, set extra name fragments, then reload:
--   hs -c "hs.settings.set('sidecar_slack.screenNames', {'Sidecar', 'iPad'}); hs.reload()"
--
-- Needs Accessibility: System Settings -> Privacy & Security -> Accessibility -> Hammerspoon.

local M = {}

local log = hs.logger.new('sidecar', 'info')

local SLACK_BUNDLE = 'com.tinyspeck.slackmacgap'
-- Case-insensitive substrings that identify the Sidecar screen by name.
local DEFAULT_SCREEN_NAMES = { 'sidecar', 'ipad' }

local DEBOUNCE_SECS   = 1.0  -- wait for screen changes to settle
local ACTIVATE_SECS   = 0.6  -- after activating Slack (may switch Space)
local MOVE_SECS       = 1.0  -- after moving the window to another screen
local FULLSCREEN_SECS = 1.5  -- full-screen enter/exit animation
local ALERT_SECS      = 1.5

local KEY_ZOOMED  = 'sidecar_slack.zoomedOut'   -- true once we've sent Cmd -
local KEY_APPLIED = 'sidecar_slack.applied'     -- true while Slack is "on Sidecar"
local KEY_NAMES   = 'sidecar_slack.screenNames' -- optional override list

local HOTKEY_MODS = { 'shift', 'ctrl', 'alt', 'cmd' }
local HOTKEY_KEY  = 's'

local watcher, debounce, hotkey
local sidecarPresent = false
local generation = 0   -- bumped per run; a newer run cancels an older in-flight one
local pending = {}     -- strong refs to scheduled timers so they can't be collected

-- ---- helpers -------------------------------------------------------------

local function after(secs, fn)
  local t
  t = hs.timer.doAfter(secs, function()
    pending[t] = nil
    local ok, err = pcall(fn)
    if not ok then log.e('step failed: ' .. tostring(err)) end
  end)
  pending[t] = true
end

local function alert(msg)
  log.i(msg)
  hs.alert.show(msg, ALERT_SECS)
end

local function screenNames()
  local names = hs.settings.get(KEY_NAMES)
  if type(names) == 'table' and #names > 0 then return names end
  return DEFAULT_SCREEN_NAMES
end

local function isSidecarScreen(screen)
  local name = (screen:name() or ''):lower()
  for _, frag in ipairs(screenNames()) do
    if name:find(tostring(frag):lower(), 1, true) then return true end
  end
  return false
end

local function findSidecarScreen()
  for _, s in ipairs(hs.screen.allScreens()) do
    if isSidecarScreen(s) then return s end
  end
  return nil
end

-- Built-in display if present, otherwise the primary (menu-bar) screen.
local function homeScreen()
  for _, s in ipairs(hs.screen.allScreens()) do
    if not isSidecarScreen(s) and (s:name() or ''):lower():find('built-in', 1, true) then
      return s
    end
  end
  return hs.screen.primaryScreen()
end

local function describeScreens()
  local parts = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    parts[#parts + 1] = string.format('%q (id %s)%s', s:name() or '?', tostring(s:id()),
      isSidecarScreen(s) and ' [sidecar]' or '')
  end
  return table.concat(parts, ', ')
end

local function logScreens(why)
  log.i(why .. ': screens = ' .. describeScreens())
end

local function slackApp()
  return hs.application.get(SLACK_BUNDLE)
end

local function slackWindow(app)
  local win = app:mainWindow() or app:focusedWindow()
  if win and win:isStandard() then return win end
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() then return w end
  end
  return win
end

-- Send Cmd+<key> to Slack only (not whatever app happens to be frontmost).
local function zoom(app, key)
  app:activate()
  hs.eventtap.keyStroke({ 'cmd' }, key, 0, app)
end

-- ---- the two routines ------------------------------------------------------

local function apply(reason)
  local screen = findSidecarScreen()
  if not screen then
    alert('Sidecar: no Sidecar screen found')
    logScreens('apply (' .. reason .. ')')
    return
  end
  local app = slackApp()
  if not app then
    log.i('apply (' .. reason .. '): Slack not running, nothing to do')
    return
  end
  generation = generation + 1
  local gen = generation
  alert('Sidecar on: moving Slack to the iPad')
  app:activate()  -- switches to Slack's Space so its window is reachable
  after(ACTIVATE_SECS, function()
    if gen ~= generation then return end
    local win = slackWindow(app)
    if not win then alert('Sidecar: no Slack window found'); return end
    hs.settings.set(KEY_APPLIED, true)

    local function moveAndFullScreen()
      if gen ~= generation then return end
      win:moveToScreen(screen, false, true, 0)
      after(MOVE_SECS, function()
        if gen ~= generation then return end
        win:setFullScreen(true)
        after(FULLSCREEN_SECS, function()
          if gen ~= generation then return end
          win:focus()
          if not hs.settings.get(KEY_ZOOMED) then
            zoom(app, '-')
            hs.settings.set(KEY_ZOOMED, true)
          else
            log.i('already zoomed out by us; not sending Cmd - again')
          end
          alert('Slack is on Sidecar')
        end)
      end)
    end

    if win:isFullScreen() then
      win:setFullScreen(false)
      after(FULLSCREEN_SECS, moveAndFullScreen)
    else
      moveAndFullScreen()
    end
  end)
end

local function revert(reason)
  local app = slackApp()
  hs.settings.set(KEY_APPLIED, false)
  if not app then
    -- Keep KEY_ZOOMED: Slack remembers its zoom, so restore it next time.
    log.i('revert (' .. reason .. '): Slack not running, nothing to do')
    return
  end
  generation = generation + 1
  local gen = generation
  alert('Sidecar off: restoring Slack')
  app:activate()
  after(ACTIVATE_SECS, function()
    if gen ~= generation then return end
    local win = slackWindow(app)

    local function finish()
      if gen ~= generation then return end
      if win then
        local home = homeScreen()
        local cur = win:screen()
        if home and (not cur or cur:id() ~= home:id()) then
          win:moveToScreen(home, false, true, 0)
        end
        win:focus()
      end
      after(0.3, function()
        if gen ~= generation then return end
        if hs.settings.get(KEY_ZOOMED) then
          zoom(app, '=')
          hs.settings.set(KEY_ZOOMED, false)
        end
        alert('Slack is back on the Mac')
      end)
    end

    if win and win:isFullScreen() then
      win:setFullScreen(false)
      after(FULLSCREEN_SECS, finish)
    else
      finish()
    end
  end)
end

local function onScreensChanged()
  logScreens('screen change')
  local present = findSidecarScreen() ~= nil
  if present == sidecarPresent then return end  -- not a Sidecar transition
  sidecarPresent = present
  if present then
    apply('Sidecar appeared')
  elseif hs.settings.get(KEY_APPLIED) or hs.settings.get(KEY_ZOOMED) then
    revert('Sidecar disappeared')
  else
    log.i('Sidecar disappeared; Slack was not moved by us, leaving it alone')
  end
end

-- ---- public API --------------------------------------------------------------

function M.toggle()
  if hs.settings.get(KEY_APPLIED) then revert('hotkey') else apply('hotkey') end
end

function M.status()
  return string.format('sidecarPresent=%s applied=%s zoomedOut=%s screens: %s',
    tostring(sidecarPresent), tostring(hs.settings.get(KEY_APPLIED) or false),
    tostring(hs.settings.get(KEY_ZOOMED) or false), describeScreens())
end

function M.start()
  sidecarPresent = findSidecarScreen() ~= nil  -- baseline: no action on (re)load
  logScreens('start (Sidecar ' .. (sidecarPresent and 'present' or 'absent') .. ')')
  debounce = hs.timer.delayed.new(DEBOUNCE_SECS, onScreensChanged)
  watcher = hs.screen.watcher.new(function() debounce:start() end)
  watcher:start()
  hotkey = hs.hotkey.bind(HOTKEY_MODS, HOTKEY_KEY, M.toggle)
  return M
end

function M.stop()
  if watcher then watcher:stop(); watcher = nil end
  if debounce then debounce:stop(); debounce = nil end
  if hotkey then hotkey:delete(); hotkey = nil end
  for t in pairs(pending) do t:stop() end
  pending = {}
end

return M
