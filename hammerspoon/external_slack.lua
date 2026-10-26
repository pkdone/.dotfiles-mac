-- external_slack.lua: keep Slack on the ARZOPA portable monitor.
--
-- The screen name is M.screenName (one place). A screen matches when its name
-- is exactly that, ignoring case. Override the list, then reload:
--   hs -c "hs.settings.set('external_slack.screenNames', {'ARZOPA'}); hs.reload()"
--
-- ARZOPA connects (including when it is already connected at startup):
--   Slack's main window moves onto that screen and goes full screen.
-- ARZOPA disconnects:
--   Slack leaves full screen, comes back to the built-in display, and gets
--   its previous frame back when that frame still fits.
-- Slack's zoom is never changed.
-- The Dock and menu bar stay on the built-in display: this module does not
-- change which display is main.
--
-- Nothing happens when Slack is not running. Screen changes are debounced,
-- and only a real connect or disconnect acts.
-- Manual toggle: Shift+Control+Option+Command+S.
-- Status: hs -c 'loaded.external_slack.status()'
--
-- Needs Accessibility: System Settings -> Privacy & Security -> Accessibility -> Hammerspoon.

local M = {}

local log = hs.logger.new('external', 'info')

M.screenName = 'ARZOPA'
M.slackBundle = 'com.tinyspeck.slackmacgap'
M.mods = { 'shift', 'ctrl', 'alt', 'cmd' }
M.key = 's'

local DEBOUNCE_SECS   = 1.0
local ACTIVATE_SECS   = 0.6
local MOVE_SECS       = 1.0
local FULLSCREEN_SECS = 1.5
local ALERT_SECS      = 1.5

local KEY_APPLIED = 'external_slack.applied'
local KEY_NAMES   = 'external_slack.screenNames'
local KEY_FRAME   = 'external_slack.savedFrame'

local watcher, debounce, hotkey
local externalPresent = false
local generation = 0
local pending = {}

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

function M.configuredNames()
  local names = hs.settings.get(KEY_NAMES)
  if type(names) == 'table' and #names > 0 then return names end
  return { M.screenName }
end

function M.nameMatches(name)
  local got = tostring(name or ''):lower()
  if got == '' then return false end
  for _, want in ipairs(M.configuredNames()) do
    if got == tostring(want):lower() then return true end
  end
  return false
end

local function isExternalScreen(screen)
  return M.nameMatches(screen:name())
end

local function findExternalScreen()
  for _, s in ipairs(hs.screen.allScreens()) do
    if isExternalScreen(s) then return s end
  end
  return nil
end

-- Built-in display if present, otherwise the primary (menu-bar) screen.
local function homeScreen()
  for _, s in ipairs(hs.screen.allScreens()) do
    if not isExternalScreen(s) and (s:name() or ''):lower():find('built-in', 1, true) then
      return s
    end
  end
  return hs.screen.primaryScreen()
end

local function describeScreens()
  local parts = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    parts[#parts + 1] = string.format('%q (id %s)%s', s:name() or '?', tostring(s:id()),
      isExternalScreen(s) and ' [ARZOPA]' or '')
  end
  return table.concat(parts, ', ')
end

local function logScreens(why)
  log.i(why .. ': screens = ' .. describeScreens())
end

local function slackApp()
  return hs.application.get(M.slackBundle)
end

local function slackWindow(app)
  local win = app:mainWindow() or app:focusedWindow()
  if win and win:isStandard() then return win end
  for _, w in ipairs(app:allWindows()) do
    if w:isStandard() then return w end
  end
  return win
end

-- ---- the two routines ------------------------------------------------------

local function apply(reason)
  local screen = findExternalScreen()
  if not screen then
    alert('No ARZOPA display found')
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
  alert('Moving Slack to the ARZOPA display')
  app:activate()
  after(ACTIVATE_SECS, function()
    if gen ~= generation then return end
    local win = slackWindow(app)
    if not win then alert('Slack has no window'); return end

    local function moveAndFullScreen()
      if gen ~= generation then return end
      local f = win:frame()
      hs.settings.set(KEY_FRAME, { x = f.x, y = f.y, w = f.w, h = f.h })
      hs.settings.set(KEY_APPLIED, true)
      log.i(string.format('saved Slack frame %d,%d %dx%d', f.x, f.y, f.w, f.h))
      win:moveToScreen(screen, false, true, 0)
      after(MOVE_SECS, function()
        if gen ~= generation then return end
        win:setFullScreen(true)
        after(FULLSCREEN_SECS, function()
          if gen ~= generation then return end
          win:focus()
          alert('Slack is full screen on the ARZOPA display')
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
    log.i('revert (' .. reason .. '): Slack not running, nothing to do')
    return
  end
  generation = generation + 1
  local gen = generation
  alert('Putting Slack back on the built-in display')
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
        local saved = hs.settings.get(KEY_FRAME)
        local hf = home and home:frame()
        local fits = type(saved) == 'table' and hf and saved.w and saved.h
          and saved.x >= hf.x - 1 and saved.y >= hf.y - 1
          and saved.x + saved.w <= hf.x + hf.w + 1 and saved.y + saved.h <= hf.y + hf.h + 1
        if fits then
          win:setFrame(hs.geometry.rect(saved.x, saved.y, saved.w, saved.h), 0)
          log.i('restored saved Slack frame')
        else
          win:maximize(0)
          log.i('no usable saved frame; maximized Slack on the built-in display')
        end
        hs.settings.clear(KEY_FRAME)
        win:focus()
      end
      alert('Slack is back on the built-in display')
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
  local present = findExternalScreen() ~= nil
  if present == externalPresent then return end
  externalPresent = present
  if present then
    apply('ARZOPA connected')
  elseif hs.settings.get(KEY_APPLIED) then
    revert('ARZOPA disconnected')
  else
    log.i('ARZOPA disconnected; Slack was not moved by us, leaving it alone')
  end
end

-- ---- public API --------------------------------------------------------------

function M.toggle()
  if hs.settings.get(KEY_APPLIED) then revert('hotkey') else apply('hotkey') end
end

function M.status()
  return string.format('externalPresent=%s applied=%s screens: %s',
    tostring(externalPresent), tostring(hs.settings.get(KEY_APPLIED) or false),
    describeScreens())
end

function M.start()
  externalPresent = findExternalScreen() ~= nil
  logScreens('start (ARZOPA ' .. (externalPresent and 'connected' or 'not connected') .. ')')
  debounce = hs.timer.delayed.new(DEBOUNCE_SECS, onScreensChanged)
  watcher = hs.screen.watcher.new(function() debounce:start() end)
  watcher:start()
  hotkey = hs.hotkey.bind(M.mods, M.key, M.toggle)
  -- Already plugged in when Hammerspoon starts: move Slack now. If we moved
  -- it on a previous run, keep the saved frame instead of overwriting it
  -- with the full-screen frame.
  if externalPresent then
    if not hs.settings.get(KEY_APPLIED) then
      apply('connected at start')
    else
      log.i('ARZOPA already connected and Slack was already moved; leaving it')
    end
  elseif hs.settings.get(KEY_APPLIED) then
    revert('missing at start')
  end
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
