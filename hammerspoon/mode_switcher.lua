-- mode_switcher.lua: menu-bar mode switcher (Normal / WebConf / DeepWork).
--
-- Settings live in modes.lua (pure data). Switching is manual only, from the menu-bar
-- dropdown: no hotkey, no automatic triggers. The menu ticks the current mode and, under
-- the tick, a one-line status (time in the mode, or time left on a DeepWork timer, and
-- Focus on/off when that is known). The icon is an SF Symbol (rendered once to
-- ~/Library/Caches/pdone-modes, text fallback):
-- Normal = desktopcomputer, WebConf = red record.circle.fill (on air), DeepWork = brain + time left.
--
-- A missing Focus Shortcut does not stop the mode. The menu has a clickable Fix (copies
-- the Shortcut name(s) and opens Shortcuts), and the switch shows a short alert
-- ("WebConf Focus skipped — create 'Mode WebConf On' in Shortcuts"). A Shortcut that is
-- present does not raise that alert.
--
-- State: ~/Library/Application Support/pdone-modes/state.json, written BEFORE anything
-- changes, records what the current mode changed so Normal can undo exactly that, also
-- after a Hammerspoon reload or a reboot. Switch log: ~/Library/Logs/pdone-modes.log.
--
-- From a terminal (hs CLI):
--   hs -c "return loaded.mode_switcher.status()"
--   hs -c "return loaded.mode_switcher.dryRun('WebConf')"     -- what it would do; changes nothing
--   hs -c "loaded.mode_switcher.switch('Normal')"
--
-- The first half of this file is pure Lua (no hs.*) so tests/modes.test.sh and macconfig-check.sh
-- can validate modes.lua and the planning logic without Hammerspoon.
--
-- A quit or hide entry is a bundle id, or { path = '~/Applications/Name.app', name = 'Name' }.
-- Path apps (the Safari web app WhatsApp Web) get their bundle id from the app when a
-- mode runs. A missing app is skipped. Safari itself is never quit or launched.

local M = {}

-- =========================================================================
-- Pure helpers (no hs.* here)
-- =========================================================================

local MODE_KEYS = {
  label = 'string', icon = 'table', quit = 'list', hide = 'list', focus = 'string',
  front = 'string', keepDisplayAwake = 'boolean',
  timerMinutes = 'number', breakMinutes = 'number',
}
local ACTION_KEYS = { 'quit', 'hide', 'focus', 'front', 'keepDisplayAwake',
                      'timerMinutes', 'breakMinutes' }

local function isList(t)
  if type(t) ~= 'table' then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n == #t
end

local function bundleOk(s) return type(s) == 'string' and s:match('^[%w][%w%.%-]*$') ~= nil end

--- True for Safari itself. A Safari web app has its own id and is not this.
function M.isSafariBundle(bundle)
  return bundle == 'com.apple.Safari' or bundle == 'com.apple.SafariTechnologyPreview'
end

-- { path = '~/Applications/Name.app' or '/Applications/Name.app', name = 'Name'? }
local function pathAppOk(t)
  if type(t) ~= 'table' then return false end
  for k in pairs(t) do
    if k ~= 'path' and k ~= 'name' then return false end
  end
  local path = t.path
  if type(path) ~= 'string' or path:find('[\r\n%z]') then return false end
  if not (path:match('^~/.*%.app$') or path:match('^/.*%.app$')) then return false end
  if t.name ~= nil and (type(t.name) ~= 'string' or t.name == '') then return false end
  return true
end

--- validate(cfg) -> true | false, {errors}
function M.validate(cfg)
  local errs = {}
  local function err(fmt, ...) errs[#errs + 1] = string.format(fmt, ...) end
  if type(cfg) ~= 'table' then return false, { 'modes.lua must return a table' } end
  if cfg.version ~= 1 then err('version must be 1') end
  if not isList(cfg.order) or #cfg.order == 0 then err('order must be a non-empty list')
  end
  if type(cfg.modes) ~= 'table' then err('modes must be a table'); return false, errs end
  local inOrder = {}
  for _, name in ipairs(type(cfg.order) == 'table' and cfg.order or {}) do
    if type(name) ~= 'string' then err('order entries must be strings')
    elseif inOrder[name] then err("order lists '%s' twice", name)
    else
      inOrder[name] = true
      if not cfg.modes[name] then err("order lists '%s' but modes has no such mode", name) end
    end
  end
  if not cfg.modes.Normal then err('a Normal mode is required') end
  if type(cfg.focus) ~= 'table' then err('focus must be a table') end
  for name, f in pairs(type(cfg.focus) == 'table' and cfg.focus or {}) do
    if type(f) ~= 'table' or type(f.on) ~= 'string' or type(f.off) ~= 'string'
       or f.on == '' or f.off == '' then
      err("focus.%s needs on and off Shortcut names", tostring(name))
    end
  end
  for name, m in pairs(cfg.modes) do
    if type(name) ~= 'string' or not name:match('^%a%w*$') then
      err("mode name '%s' must be a word", tostring(name))
    elseif not inOrder[name] then err("mode '%s' is missing from order", name) end
    if type(m) ~= 'table' then err("mode '%s' must be a table", tostring(name))
    else
      for k, v in pairs(m) do
        local want = MODE_KEYS[k]
        if not want then err("mode '%s': unknown key '%s'", name, tostring(k))
        elseif want == 'list' then
          if not isList(v) then err("mode '%s': %s must be a list", name, k)
          else
            for _, b in ipairs(v) do
              if type(b) == 'string' then
                if not bundleOk(b) then err("mode '%s': %s has a bad bundle id '%s'", name, k, b) end
              elseif type(b) == 'table' then
                if not pathAppOk(b) then
                  err("mode '%s': %s has a bad app path '%s'", name, k, tostring(b.path))
                end
              else
                err("mode '%s': %s has a bad bundle id '%s'", name, k, tostring(b))
              end
            end
          end
        elseif type(v) ~= want then err("mode '%s': %s must be a %s", name, k, want) end
      end
      if type(m.label) ~= 'string' or m.label == '' then err("mode '%s' needs a label", name) end
      if type(m.icon) ~= 'table' or type(m.icon.symbol) ~= 'string' or type(m.icon.fallback) ~= 'string' then
        err("mode '%s' needs icon = { symbol = '...', fallback = '...' }", name)
      end
      if m.front ~= nil and not bundleOk(m.front) then err("mode '%s': bad front bundle id", name) end
      if m.focus ~= nil and (type(cfg.focus) ~= 'table' or not cfg.focus[m.focus]) then
        err("mode '%s': focus '%s' has no entry in focus", name, tostring(m.focus))
      end
      for _, k in ipairs({ 'timerMinutes', 'breakMinutes' }) do
        if m[k] ~= nil and type(m[k]) == 'number' and (m[k] < 1 or m[k] > 600) then
          err("mode '%s': %s must be 1-600", name, k)
        end
      end
      if m.breakMinutes and not m.timerMinutes then err("mode '%s': breakMinutes needs timerMinutes", name) end
      if name == 'Normal' then
        for _, k in ipairs(ACTION_KEYS) do
          if m[k] ~= nil then err("Normal can't have actions ('%s'): it only restores", k) end
        end
      end
    end
  end
  return #errs == 0, errs
end

--- validateFile(path) -> 'ok' | 'error: ...'   (used by macconfig-check.sh via `hs -c`)
function M.validateFile(path)
  local chunk, lerr = loadfile(path)
  if not chunk then return 'error: ' .. tostring(lerr) end
  local ok, cfg = pcall(chunk)
  if not ok then return 'error: ' .. tostring(cfg) end
  local valid, errs = M.validate(cfg)
  if valid then return 'ok' end
  return 'error: ' .. table.concat(errs, '; ')
end

function M.formatDuration(secs)
  secs = math.max(0, math.floor(secs or 0))
  if secs < 60 then return '<1m' end
  local m = secs // 60
  if m < 60 then return string.format('%dm', m) end
  return string.format('%dh %02dm', m // 60, m % 60)
end

--- shortcutMissing(shortcuts, name) -> bool
--- True only when the Shortcuts list is known and this name is not on it.
--- nil shortcuts means "not listed yet", which is not the same as missing.
function M.shortcutMissing(shortcuts, name)
  return type(shortcuts) == 'table' and not shortcuts[name]
end

--- focusSkipToast(focusName, shortcutName) -> string
--- Short alert when a mode's Focus Shortcut is missing. Names the Shortcut to create.
--- The rest of the mode still runs.
function M.focusSkipToast(focusName, shortcutName)
  return string.format("%s Focus skipped — create '%s' in Shortcuts",
    tostring(focusName), tostring(shortcutName))
end

--- missingFixTitle(names) -> string
--- One clickable menu title listing every missing Focus Shortcut.
function M.missingFixTitle(names)
  names = names or {}
  if #names == 0 then return 'Fix missing Focus Shortcuts…' end
  return 'Create missing: ' .. table.concat(names, ', ')
end

--- missingFixClipboard(names) -> string
--- Pasteboard text: one Shortcut name per line, so each can be pasted on its own.
function M.missingFixClipboard(names)
  return table.concat(names or {}, '\n')
end

--- missingFixAlert(names) -> string
--- Short confirmation after the names are copied and Shortcuts is opening.
function M.missingFixAlert(names)
  names = names or {}
  if #names == 1 then
    return "Copied '" .. names[1] .. "' — opening Shortcuts"
  end
  return string.format('Copied %d Shortcut names — opening Shortcuts', #names)
end

--- afterFocusAttempt(prev, which, listed, present) -> { session = 'on'|'off'|nil, offSkipped = bool }
--- which is 'on' or 'off'. When the list is unknown, focus is unknown.
--- A missing Off Shortcut leaves focus unknown (the previous Focus may still be on);
--- a later missing On then stays unknown rather than claiming "Focus off".
function M.afterFocusAttempt(prev, which, listed, present)
  prev = prev or {}
  if not listed then return { session = nil, offSkipped = false } end
  if not present then
    if which == 'off' or prev.offSkipped then
      return { session = nil, offSkipped = true }
    end
    return { session = 'off', offSkipped = false }
  end
  if which == 'on' then return { session = 'on', offSkipped = false } end
  return { session = 'off', offSkipped = false }
end

--- knownFocus(info) -> 'on'|'off'|nil
--- info.session is what this process's last switch established.
--- Otherwise infer from the Shortcuts list: an On Shortcut that exists means Focus on,
--- one that is missing means Focus off. Normal is not guessed (say "restored" only).
--- A note that the Shortcut failed, when the Shortcut does exist, means unknown.
function M.knownFocus(info)
  info = info or {}
  if info.session == 'on' or info.session == 'off' then return info.session end
  -- Off was skipped, so a previous Focus may still be on. Don't claim off.
  if info.offSkipped then return nil end
  if type(info.shortcuts) ~= 'table' then return nil end
  if info.mode == 'Normal' or not info.focusName or type(info.onShortcut) ~= 'string' then
    return nil
  end
  if info.note and info.shortcuts[info.onShortcut] then return nil end
  if info.shortcuts[info.onShortcut] then return 'on' end
  return 'off'
end

--- modeStatusLine(info) -> string  One disabled menu line for the current mode.
--- info.mode, elapsed (seconds), remaining (seconds left on a timer), timerDone,
--- breakLeft (seconds), focus ('on'|'off'|nil).
--- DeepWork prefers time left while the timer is running. Normal says "restored".
function M.modeStatusLine(info)
  info = info or {}
  local parts = { tostring(info.mode or '?') }
  if info.breakLeft ~= nil then
    parts[#parts + 1] = 'break ' .. M.formatDuration(info.breakLeft) .. ' left'
  elseif info.timerDone then
    parts[#parts + 1] = 'done'
  elseif info.remaining ~= nil then
    parts[#parts + 1] = M.formatDuration(info.remaining) .. ' left'
  elseif info.mode == 'Normal' then
    parts[#parts + 1] = 'restored'
  elseif info.elapsed ~= nil then
    parts[#parts + 1] = M.formatDuration(info.elapsed)
  end
  if info.focus == 'on' then parts[#parts + 1] = 'Focus on'
  elseif info.focus == 'off' then parts[#parts + 1] = 'Focus off' end
  return table.concat(parts, ' · ')
end

--- modeStatus(info) -> string  Status line, including Focus when it is known.
function M.modeStatus(info)
  info = info or {}
  return M.modeStatusLine({
    mode = info.mode,
    elapsed = info.elapsed,
    remaining = info.remaining,
    timerDone = info.timerDone,
    breakLeft = info.breakLeft,
    focus = M.knownFocus(info),
  })
end

local function specKey(spec)
  if type(spec) == 'table' then return spec.path end
  return spec
end

--- Display name for a bundle id or a { path, name } app.
local function specName(snap, spec)
  local key = specKey(spec)
  if snap.names and type(key) == 'string' and snap.names[key] then return snap.names[key] end
  if type(spec) == 'table' and type(spec.name) == 'string' and spec.name ~= '' then return spec.name end
  if type(key) == 'string' then return key end
  return '?'
end

--- modeQuits(mode, q) -> bool
--- q is a recorded quit: { bundle, name, path?, app? }. app is the configured
--- path (~/Applications/Name.app) so a later mode can recognise the same app
--- without knowing the per-Mac bundle id.
function M.modeQuits(mode, q)
  if type(mode) ~= 'table' or type(q) ~= 'table' then return false end
  for _, spec in ipairs(mode.quit or {}) do
    if type(spec) == 'string' then
      if spec == q.bundle then return true end
    elseif type(spec) == 'table' then
      if type(q.app) == 'string' and q.app == spec.path then return true end
      if type(q.path) == 'string' and q.path == spec.path then return true end
    end
  end
  return false
end

--- quitLine(spec, snap, carried) -> one dry-run line, without the leading indent.
--- A path app that is not installed, cannot be read, or would be Safari is a skip.
--- carried is quit records the previous mode left behind that this mode also quits.
function M.quitLine(spec, snap, carried)
  snap = snap or {}
  local key = specKey(spec)
  local label = specName(snap, spec)
  if type(spec) == 'table' then
    if snap.blocked and snap.blocked[key] then
      return 'quit ' .. label .. ': would quit Safari, skip'
    end
    if snap.unreadable and snap.unreadable[key] then
      return 'quit ' .. label .. ": can't read its bundle id, skip"
    end
    if snap.missing and snap.missing[key] then
      return 'quit ' .. label .. ': not installed, skip'
    end
  end
  if snap.running and snap.running[key] then
    return 'quit ' .. label .. ' politely (skipped if it has unsaved work or refuses)'
  end
  if type(carried) == 'table' then
    for _, q in ipairs(carried) do
      if M.modeQuits({ quit = { spec } }, q) then
        return 'quit ' .. label .. ': already quit, kept so Normal reopens it'
      end
    end
  end
  return 'quit ' .. label .. ': not running, skip'
end

--- quitRecord(spec, snap) -> { bundle, name, path? } | nil
--- nil means do not quit and do not record it. path is set only for a path app,
--- and only once it is expanded: open does not expand ~.
function M.quitRecord(spec, snap)
  snap = snap or {}
  local key = specKey(spec)
  if type(spec) == 'table' then
    if (snap.blocked and snap.blocked[key]) or (snap.missing and snap.missing[key])
       or (snap.unreadable and snap.unreadable[key]) then
      return nil
    end
  end
  if not (snap.running and snap.running[key]) then return nil end
  local bundle = type(spec) == 'string' and spec or (snap.bundles and snap.bundles[key])
  if type(bundle) ~= 'string' or bundle == '' or M.isSafariBundle(bundle) then return nil end
  local rec = { bundle = bundle, name = specName(snap, spec) }
  if type(spec) == 'table' then
    if type(spec.path) == 'string' then rec.app = spec.path end
    local path = snap.paths and snap.paths[key]
    if type(path) == 'string' and path ~= '' and path:sub(1, 1) ~= '~' then rec.path = path end
  end
  return rec
end

--- reopenArgs(q) -> { '-g', path } | { '-g', '-b', bundle } | nil
--- A recorded path is that app bundle (the web app), launched in the background.
--- A bare Safari bundle id is not launched.
function M.reopenArgs(q)
  if type(q) ~= 'table' then return nil end
  if type(q.path) == 'string' and q.path ~= '' and q.path:sub(1, 1) ~= '~' then
    return { '-g', q.path }
  end
  if type(q.bundle) == 'string' and q.bundle ~= '' and not M.isSafariBundle(q.bundle) then
    return { '-g', '-b', q.bundle }
  end
  return nil
end

-- What Normal's restore would do for a recorded set of changes.
local function restoreLines(cfg, changes, snap, out, indent, nextMode)
  changes = changes or {}
  local any = false
  for _, q in ipairs(changes.quit or {}) do
    any = true
    local label = q.name or q.bundle
    local appKey = type(q.app) == 'string' and q.app or nil
    if appKey and snap.missing and snap.missing[appKey] then
      out[#out + 1] = indent .. 'reopen ' .. label .. ': not installed, skip'
    elseif appKey and snap.unreadable and snap.unreadable[appKey] then
      out[#out + 1] = indent .. 'reopen ' .. label .. ": can't read its bundle id, skip"
    elseif appKey and snap.blocked and snap.blocked[appKey] then
      out[#out + 1] = indent .. 'reopen ' .. label .. ': would launch Safari, skip'
    elseif nextMode and M.modeQuits(nextMode, q) then
      -- Leave it quit. Reopening it, then quitting it again, races open -g.
      out[#out + 1] = indent .. 'leave ' .. label .. ' quit (this mode quits it too)'
    elseif snap.running and snap.running[q.bundle] then
      out[#out + 1] = indent .. 'reopen ' .. label .. ': already running, nothing to do'
    else
      out[#out + 1] = indent .. 'reopen ' .. label .. ' in the background (open -g)'
    end
  end
  for _, h in ipairs(changes.hidden or {}) do
    any = true
    out[#out + 1] = indent .. 'unhide ' .. (h.name or h.bundle)
  end
  if changes.focus then
    any = true
    local f = cfg.focus and cfg.focus[changes.focus]
    out[#out + 1] = indent .. string.format("Focus %s off: Shortcut '%s'", changes.focus, f and f.off or '?')
  end
  if changes.displayAwake then any = true; out[#out + 1] = indent .. 'allow display sleep again (displayIdle off)' end
  if changes.timer then any = true; out[#out + 1] = indent .. 'stop the DeepWork timer' end
  if changes.focus then out[#out + 1] = indent .. 'notification badges come back with the Focus off' end
  if not any then out[#out + 1] = indent .. 'nothing recorded to restore' end
end

--- plan(cfg, name, snap) -> { lines }. snap = { current = 'Mode', changes = {...},
--- running = { [key] = true }, hidden = { [key] = true }, names = { [key] = 'Name' },
--- missing / unreadable / blocked = { [path] = true } for a path app that is not
--- installed, has no readable id, or resolved to Safari,
--- bundles = { [path] = bundle id }, paths = { [path] = expanded path },
--- shortcuts = { [name] = true } | nil (unknown) }
--- A key is a bundle id, or the path of a { path, name } app.
function M.plan(cfg, name, snap)
  snap = snap or {}
  local out = {}
  local m = cfg.modes[name]
  if not m then return { "unknown mode '" .. tostring(name) .. "'" } end
  local current = snap.current or 'Normal'
  out[#out + 1] = string.format('%s: dry run, nothing changed (current mode: %s)', m.label, current)
  if name == 'Normal' then
    restoreLines(cfg, snap.changes, snap, out, '  ')
    return out
  end
  if current == name then
    out[#out + 1] = '  already in ' .. name .. ': switching again restores first, then re-applies'
  end
  local carried
  if current ~= 'Normal' then
    carried = {}
    for _, q in ipairs((snap.changes or {}).quit or {}) do
      if M.modeQuits(m, q) then carried[#carried + 1] = q end
    end
    out[#out + 1] = '  first, restore (as Normal would):'
    restoreLines(cfg, snap.changes, snap, out, '    ', m)
  end
  out[#out + 1] = '  write state.json (mode ' .. name .. ', what will change) before changing anything'
  for _, b in ipairs(m.quit or {}) do
    out[#out + 1] = '  ' .. M.quitLine(b, snap, carried)
  end
  for _, b in ipairs(m.hide or {}) do
    local key = specKey(b)
    local label = specName(snap, b)
    if type(b) == 'table' and snap.missing and snap.missing[key] then
      out[#out + 1] = '  hide ' .. label .. ': not installed, skip'
    elseif not (snap.running and snap.running[key]) then
      out[#out + 1] = '  hide ' .. label .. ': not running, skip'
    elseif snap.hidden and snap.hidden[key] then
      out[#out + 1] = '  hide ' .. label .. ': already hidden, skip (not recorded)'
    else
      out[#out + 1] = '  hide ' .. label
    end
  end
  if m.focus then
    local f = cfg.focus[m.focus]
    local line = string.format("  Focus %s on: Shortcut '%s'", m.focus, f.on)
    if snap.shortcuts and not snap.shortcuts[f.on] then
      line = line .. ' (MISSING: create it; the mode still runs without the Focus)'
    elseif not snap.shortcuts then
      line = line .. " (couldn't list Shortcuts)"
    end
    out[#out + 1] = line
  end
  if m.keepDisplayAwake then out[#out + 1] = '  keep the display awake (displayIdle) until you leave the mode' end
  if m.front then
    out[#out + 1] = '  bring ' .. specName(snap, m.front) .. ' to the front'
      .. ((snap.running and not snap.running[m.front]) and ' (launches it)' or '')
  end
  if name ~= 'Normal' and m.focus then
    out[#out + 1] = '  menu-bar notification badges: no macOS API to hide them; the Focus silences them'
  end
  if m.timerMinutes then
    out[#out + 1] = string.format('  start a %d-minute countdown in the menu bar; at the end a notification offers', m.timerMinutes)
    out[#out + 1] = string.format('    Take a break (%d min) / Back to Normal / Another session (never switches by itself)', m.breakMinutes or 10)
  end
  out[#out + 1] = '  log the switch to ~/Library/Logs/pdone-modes.log'
  return out
end

-- Everything below needs Hammerspoon.
if type(hs) ~= 'table' then return M end

-- =========================================================================
-- Hammerspoon engine
-- =========================================================================

local HOME       = os.getenv('HOME')
local STATE_DIR  = HOME .. '/Library/Application Support/pdone-modes'
local STATE_FILE = STATE_DIR .. '/state.json'
local LOG_FILE   = HOME .. '/Library/Logs/pdone-modes.log'
local CACHE_DIR  = HOME .. '/Library/Caches/pdone-modes'
local QUIT_WAIT_SECS = 6     -- after a polite quit, how long before "it didn't quit"

local log = hs.logger.new('modes', 'info')
local cfg                    -- modes.lua
local state                  -- decoded state.json
local menu                   -- hs.menubar
local icons = {}             -- mode name -> hs.image
local timers = {}            -- name -> hs.timer (strong refs)
local tasks = {}             -- running hs.task objects (strong refs)
local shortcutsKnown         -- set of Shortcut names, nil until listed
local notes = {}             -- key -> text shown (disabled) in the menu
local focusTrack = {}        -- { session = 'on'|'off'|nil, offSkipped = bool } from the last switch
local timerDone = false
local endNotification

-- ---- small helpers --------------------------------------------------------

local function now() return os.time() end

local function alert(msg, secs) hs.alert.show(msg, secs or 3) end

local function notify(title, text)
  hs.notify.new({ title = title, informativeText = text, withdrawAfter = 15 }):send()
end

local function runTask(path, args, cb)
  local t
  t = hs.task.new(path, function(code, out, err)
    tasks[t] = nil
    if cb then
      local ok, e = pcall(cb, code, out or '', err or '')
      if not ok then log.e('task callback: ' .. tostring(e)) end
    end
  end, args)
  tasks[t] = true
  if not t:start() then tasks[t] = nil; if cb then cb(-1, '', 'could not start ' .. path) end end
  return t
end

local function every(name, secs, fn)
  if timers[name] then timers[name]:stop() end
  timers[name] = hs.timer.doEvery(secs, function()
    local ok, e = pcall(fn)
    if not ok then log.e(name .. ': ' .. tostring(e)) end
  end)
end

local function after(name, secs, fn)
  if timers[name] then timers[name]:stop() end
  timers[name] = hs.timer.doAfter(secs, function()
    timers[name] = nil
    local ok, e = pcall(fn)
    if not ok then log.e(name .. ': ' .. tostring(e)) end
  end)
end

local function stopTimer(name)
  if timers[name] then timers[name]:stop(); timers[name] = nil end
end

local function appByBundle(bundle)
  -- Never hand back Safari. A web app has its own bundle id and its own process.
  if type(bundle) ~= 'string' or bundle == '' or M.isSafariBundle(bundle) then return nil end
  for _, a in ipairs(hs.application.applicationsForBundleID(bundle) or {}) do
    if a:isRunning() then
      local ok, bid = pcall(function() return a:bundleID() end)
      if not (ok and M.isSafariBundle(bid)) then return a end
    end
  end
  return nil
end

local function bundleName(bundle)
  local a = appByBundle(bundle)
  if a then return a:name() end
  local info = hs.application.infoForBundleID(bundle)
  return (info and (info.CFBundleDisplayName or info.CFBundleName)) or bundle
end
local function cleanName(n)   -- strip a left-to-right or right-to-left mark from an app name
  return (n:gsub('\226\128[\142\143]', ''))
end

local function loadConfig()
  package.loaded['modes'] = nil
  local ok, c = pcall(require, 'modes')
  if not ok then return nil, tostring(c) end
  local valid, errs = M.validate(c)
  if not valid then return nil, table.concat(errs, '; ') end
  return c
end

-- ---- state + log ------------------------------------------------------------

local function readState()
  local s = hs.json.read(STATE_FILE)
  if type(s) ~= 'table' or type(s.mode) ~= 'string' then
    return { version = 1, mode = 'Normal', since = now(), phase = 'applied', changes = {} }
  end
  s.changes = s.changes or {}
  return s
end

local function writeState(s)
  hs.fs.mkdir(STATE_DIR)
  s.version = 1
  s.updated = os.date('!%Y-%m-%dT%H:%M:%SZ')
  local ok = hs.json.write(s, STATE_FILE, true, true)
  if not ok then log.e('could not write ' .. STATE_FILE) end
  return ok
end

local function logSwitch(newMode, prevMode, prevSince, extra)
  local f = io.open(LOG_FILE, 'a')
  if not f then return end
  f:write(string.format('%s  %-9s (%s lasted %s)%s\n', os.date('%Y-%m-%d %H:%M:%S'), newMode,
    prevMode or '?', M.formatDuration(now() - (prevSince or now())), extra and ('  ' .. extra) or ''))
  f:close()
end

-- ---- icons ------------------------------------------------------------------

local ICON_JS = [[
ObjC.import('AppKit');
function run(argv) {
  var out = argv[0], done = [];
  for (var i = 1; i < argv.length; i++) {
    var name = argv[i];
    var img = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription(name, $());
    if (!img || img.isNil()) continue;
    img = img.imageWithSymbolConfiguration(
      $.NSImageSymbolConfiguration.configurationWithPointSizeWeightScale(14, 0, 2));
    var sz = img.size, w = Math.ceil(sz.width * 2), h = Math.ceil(sz.height * 2);
    var rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
      null, w, h, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0);
    rep.setSize(sz);
    $.NSGraphicsContext.saveGraphicsState;
    $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep));
    img.drawInRectFromRectOperationFraction($.NSMakeRect(0, 0, sz.width, sz.height), $.NSZeroRect, 2, 1.0);
    $.NSGraphicsContext.restoreGraphicsState;
    rep.representationUsingTypeProperties(4, $()).writeToFileAtomically(out + '/' + name + '.png', true);
    done.push(name);
  }
  return done.join(' ');
}
]]

-- WebConf's on-air icon: a red record.circle.fill drawn directly (SF Symbol palette
-- colours don't survive rendering to a bitmap).
local function redRecordIcon()
  local c = hs.canvas.new({ x = 0, y = 0, w = 18, h = 18 })
  local red = { red = 0.95, green = 0.18, blue = 0.17, alpha = 1 }
  c[1] = { type = 'circle', center = { x = 9, y = 9 }, radius = 7.5, action = 'fill', fillColor = red }
  c[2] = { type = 'circle', center = { x = 9, y = 9 }, radius = 5.2, action = 'stroke',
           strokeColor = { white = 1, alpha = 0.95 }, strokeWidth = 1.2 }
  c[3] = { type = 'circle', center = { x = 9, y = 9 }, radius = 3.2, action = 'fill',
           fillColor = { white = 1, alpha = 0.95 } }
  local img = c:imageFromCanvas()
  c:delete()
  return img
end

local updateMenu   -- forward

local function loadIcons()
  icons = {}
  for name, m in pairs(cfg.modes) do
    if m.icon.color == 'red' then
      icons[name] = { image = redRecordIcon(), template = false }
    else
      local img = hs.image.imageFromPath(CACHE_DIR .. '/' .. m.icon.symbol .. '.png')
      if img then icons[name] = { image = img:setSize({ w = 16, h = 16 }, false), template = true } end
    end
  end
end

local function renderIcons()
  hs.fs.mkdir(CACHE_DIR)
  local js = CACHE_DIR .. '/render-symbols.js'
  local f = io.open(js, 'w')
  if not f then loadIcons(); return end
  f:write(ICON_JS); f:close()
  local args = { '-l', 'JavaScript', js, CACHE_DIR }
  for _, m in pairs(cfg.modes) do if m.icon.color ~= 'red' then args[#args + 1] = m.icon.symbol end end
  runTask('/usr/bin/osascript', args, function()
    loadIcons()
    if updateMenu then updateMenu() end
  end)
end

-- ---- Shortcuts (Focus) --------------------------------------------------------

local function refreshShortcuts(cb)
  runTask('/usr/bin/shortcuts', { 'list' }, function(code, out)
    if code == 0 then
      local set = {}
      for line in out:gmatch('[^\r\n]+') do set[line] = true end
      shortcutsKnown = set
    end
    if cb then cb() end
  end)
end

local function missingShortcuts()
  local miss = {}
  if not shortcutsKnown then return miss end
  for _, name in ipairs(cfg.order) do
    local f = cfg.focus[name]
    if f then
      if not shortcutsKnown[f.on] then miss[#miss + 1] = f.on end
      if not shortcutsKnown[f.off] then miss[#miss + 1] = f.off end
    end
  end
  return miss
end

-- Copies every missing Focus Shortcut name and opens Shortcuts so they can be created.
local function fixMissingShortcuts(names)
  hs.pasteboard.setContents(M.missingFixClipboard(names))
  alert(M.missingFixAlert(names), 4)
  runTask('/usr/bin/open', { '-a', 'Shortcuts' })
end

local function runShortcut(name, what, focusName)
  local which = (what == 'Focus on') and 'on' or 'off'
  local listed = type(shortcutsKnown) == 'table'
  local present = listed and shortcutsKnown[name] == true
  -- Record the result first so a synchronous task failure can clear it.
  focusTrack = M.afterFocusAttempt(focusTrack, which, listed, present)
  if M.shortcutMissing(shortcutsKnown, name) then
    notes.focus = "Focus not changed: create Shortcut '" .. name .. "'"
    alert(M.focusSkipToast(focusName, name), 4)
    return
  end
  runTask('/usr/bin/shortcuts', { 'run', name }, function(code, _, err)
    if code ~= 0 then
      notes.focus = string.format("%s: Shortcut '%s' failed", what, name)
      log.w(notes.focus .. ': ' .. err)
      if focusTrack.session == which then focusTrack.session = nil end
      if updateMenu then updateMenu() end
    end
  end)
end

-- ---- transient effects (re-applied after a reload) ---------------------------

local function setDisplayAwake(on)
  hs.caffeinate.set('displayIdle', on, true)
end

-- ---- DeepWork timer -----------------------------------------------------------

local startTimer -- forward
local M_switch   -- forward

local function onTimerEnd()
  timerDone = true
  if state.changes.timer then state.changes.timer.notified = true; writeState(state) end
  local m = cfg.modes[state.mode] or {}
  endNotification = hs.notify.new(function(n)
    local t = n:activationType()
    if t == hs.notify.activationTypes.additionalActionClicked then
      local a = n:additionalActivationAction()
      if a == 'Take a break' then M.takeBreak()
      elseif a == 'Another session' then M.anotherSession() end
    elseif t == hs.notify.activationTypes.actionButtonClicked then
      M_switch('Normal')
    end
  end, {
    title = (m.label or state.mode) .. ' session done',
    informativeText = string.format('%d minutes. Take a break, back to Normal, or another session?',
      (state.changes.timer and state.changes.timer.minutes) or 0),
    hasActionButton = true, actionButtonTitle = 'Back to Normal',
    additionalActions = { 'Take a break', 'Another session' },
    withdrawAfter = 0,
  }):send()
  alert('Session done: choose from the notification or the menu bar', 5)
  if updateMenu then updateMenu() end
end

startTimer = function()
  local t = state.changes.timer
  stopTimer('countdown')
  if not t then return end
  timerDone = (t.endsAt <= now())
  if timerDone then
    if not t.notified then onTimerEnd() end
    return
  end
  every('countdown', 15, function()
    if now() >= t.endsAt then stopTimer('countdown'); onTimerEnd() end
    if updateMenu then updateMenu() end
  end)
end

-- ---- quitting / hiding --------------------------------------------------------

local function unsavedWork(app)
  for _, w in ipairs(app:allWindows()) do
    local ax = hs.axuielement.windowElement(w)
    if ax then
      for _, attr in ipairs({ 'AXDocumentEdited', 'AXModified', 'AXIsEdited' }) do
        if ax:attributeValue(attr) == true then return true end
      end
    end
    local t = w:title() or ''
    if t:match('^•') or t:match('— Edited$') or t:match('%- Edited$') then return true end
  end
  return false
end

local function expandPath(path)
  if type(path) ~= 'string' then return nil end
  if path:sub(1, 2) == '~/' then
    if type(HOME) ~= 'string' or HOME == '' then return nil end
    return HOME .. path:sub(2)
  end
  return path
end

-- Bundle id from a path app's Info.plist. problem is 'missing', 'unreadable',
-- 'safari', or nil when bid is usable. Never raises: a missing app is a skip.
local function bundleIdAtPath(path)
  local info
  if type(hs.application.infoForBundlePath) == 'function' then
    local ok, result = pcall(hs.application.infoForBundlePath, path)
    if ok and type(result) == 'table' then info = result end
  end
  if type(info) ~= 'table' and hs.plist and type(hs.plist.read) == 'function' then
    local ok, result = pcall(hs.plist.read, path .. '/Contents/Info.plist')
    if ok and type(result) == 'table' then info = result end
  end
  local exists = false
  if hs.fs and type(hs.fs.attributes) == 'function' then
    local okAttr, attrs = pcall(hs.fs.attributes, path)
    exists = okAttr and attrs ~= nil
  end
  local bid = type(info) == 'table' and info.CFBundleIdentifier or nil
  if type(bid) == 'string' then bid = bid:match('^%s*(.-)%s*$') end
  if type(bid) ~= 'string' or bid == '' then
    if exists then return nil, 'unreadable' end
    return nil, 'missing'
  end
  if M.isSafariBundle(bid) then return nil, 'safari' end
  return bid, nil
end

local function snapshot()
  local snap = { running = {}, hidden = {}, names = {}, bundles = {}, paths = {},
                 missing = {}, unreadable = {}, blocked = {},
                 shortcuts = shortcutsKnown,
                 current = state.mode, changes = state.changes }
  local function lookBundle(b)
    if type(b) ~= 'string' then return end
    local a = appByBundle(b)
    snap.names[b] = cleanName(bundleName(b))
    if a then snap.running[b] = true; if a:isHidden() then snap.hidden[b] = true end end
  end
  local function noteProblem(key, problem)
    if problem == 'safari' then snap.blocked[key] = true
    elseif problem == 'unreadable' then snap.unreadable[key] = true
    else snap.missing[key] = true end
  end
  local function lookSpec(spec)
    if type(spec) ~= 'table' then lookBundle(spec); return end
    local key = specKey(spec)
    if type(key) ~= 'string' or key == '' then return end
    if type(spec.name) == 'string' and spec.name ~= '' then snap.names[key] = spec.name
    else snap.names[key] = key end
    local path = expandPath(spec.path)
    if type(path) ~= 'string' then noteProblem(key, 'missing'); return end
    snap.paths[key] = path
    local bid, problem = bundleIdAtPath(path)
    if not bid then noteProblem(key, problem); return end
    snap.bundles[key] = bid
    local a = appByBundle(bid)
    if not a then return end
    snap.running[key] = true
    local live = a:name()
    if type(live) == 'string' and live ~= '' then snap.names[key] = cleanName(live) end
    if a:isHidden() then snap.hidden[key] = true end
  end
  for _, m in pairs(cfg.modes) do
    for _, b in ipairs(m.quit or {}) do lookSpec(b) end
    for _, b in ipairs(m.hide or {}) do lookSpec(b) end
    if m.front then lookBundle(m.front) end
  end
  for _, q in ipairs(state.changes.quit or {}) do lookBundle(q.bundle) end
  return snap
end

-- ---- restore (Normal) + apply -------------------------------------------------

-- 'missing', 'unreadable', or 'safari' when a recorded path app must not be launched.
-- nil when it is fine to launch, or when the record is a normal bundle id.
local function pathProblem(q)
  if type(q.app) ~= 'string' then return nil end
  local path = expandPath(q.app)
  if type(path) ~= 'string' then return 'missing' end
  local bid, problem = bundleIdAtPath(path)
  if bid then return nil end
  return problem or 'missing'
end

local function restoreChanges(changes, keep)
  local msgs = {}
  local skip = {}
  for _, q in ipairs(keep or {}) do skip[q] = true end
  for _, q in ipairs(changes.quit or {}) do
    -- keep: the next mode quits this app too, so leave the process quit.
    -- pathProblem: the web app is gone, or the path is Safari itself.
    if not skip[q] and not pathProblem(q) and not appByBundle(q.bundle) then
      local args = M.reopenArgs(q)   -- background, not hidden; path apps are not Safari
      if args then runTask('/usr/bin/open', args) end
    end
  end
  for _, h in ipairs(changes.hidden or {}) do
    local a = appByBundle(h.bundle)
    if a and a:isHidden() then a:unhide() end
  end
  if changes.focus and cfg.focus[changes.focus] then
    runShortcut(cfg.focus[changes.focus].off, 'Focus off', changes.focus)
  end
  if changes.displayAwake then setDisplayAwake(false) end
  stopTimer('countdown'); stopTimer('break')
  timerDone = false
  if endNotification then endNotification:withdraw(); endNotification = nil end
  return msgs
end

local function changesBeingRestored()
  if state.phase == 'restoring' and state.restoreOf then return state.restoreOf end
  return state.changes or {}
end

local function restoreToNormal(keep)
  local prev, prevSince = state.mode, state.since
  local changes = changesBeingRestored()
  -- state first: if anything below fails, the next Normal still knows what to undo
  state = { mode = 'Normal', since = now(), phase = 'restoring', restoreOf = changes, changes = {} }
  writeState(state)
  restoreChanges(changes, keep)
  state.phase = 'applied'; state.restoreOf = nil
  writeState(state)
  return prev, prevSince
end

local function copyQuit(q)
  local rec = { bundle = q.bundle, name = q.name }
  if type(q.path) == 'string' and q.path ~= '' then rec.path = q.path end
  if type(q.app) == 'string' and q.app ~= '' then rec.app = q.app end
  return rec
end

local function carriedDropped(spec, snap, q)
  if type(spec) ~= 'table' or not M.modeQuits({ quit = { spec } }, q) then return false end
  local key = specKey(spec)
  return (snap.missing and snap.missing[key]) or (snap.blocked and snap.blocked[key])
    or (snap.unreadable and snap.unreadable[key])
end

local function applyMode(name, carried)
  local m = cfg.modes[name]
  local snap = snapshot()
  -- Plan what will change and record it BEFORE changing anything.
  local changes = { quit = {}, hidden = {} }
  local seen = {}
  for _, spec in ipairs(m.quit or {}) do
    local rec = M.quitRecord(spec, snap)
    if rec then
      changes.quit[#changes.quit + 1] = rec
      seen[rec.bundle] = true
    end
  end
  -- Apps the previous mode already quit, which this mode quits too, stay
  -- recorded so Normal still reopens them. They were not launched again.
  for _, q in ipairs(carried or {}) do
    if type(q.bundle) == 'string' and not seen[q.bundle] and not M.isSafariBundle(q.bundle) then
      local drop = false
      for _, spec in ipairs(m.quit or {}) do
        if carriedDropped(spec, snap, q) then drop = true end
      end
      if not drop then
        changes.quit[#changes.quit + 1] = copyQuit(q)
        seen[q.bundle] = true
      end
    end
  end
  for _, spec in ipairs(m.hide or {}) do
    local key = specKey(spec)
    if snap.running[key] and not snap.hidden[key] then
      local bundle = type(spec) == 'string' and spec or snap.bundles[key]
      if type(bundle) == 'string' and bundle ~= '' and not M.isSafariBundle(bundle) then
        changes.hidden[#changes.hidden + 1] = { bundle = bundle, name = specName(snap, spec) }
      end
    end
  end
  if m.focus then changes.focus = m.focus end
  if m.keepDisplayAwake then changes.displayAwake = true end
  if m.timerMinutes then
    changes.timer = { minutes = m.timerMinutes, endsAt = now() + m.timerMinutes * 60, notified = false }
  end
  state = { mode = name, since = now(), phase = 'applying', changes = changes }
  writeState(state)

  local skipped = {}
  -- quit politely (kill() = Cmd-Q); never force, and never Safari
  for _, q in ipairs(changes.quit) do
    if M.isSafariBundle(q.bundle) then
      q.result = 'skipped: safari'
      log.w('refusing to quit Safari for ' .. tostring(q.name))
    else
      local a = appByBundle(q.bundle)
      if a then
        if unsavedWork(a) then
          q.result = 'skipped: unsaved work'; skipped[#skipped + 1] = q.name .. ' (unsaved work)'
        elseif a:kill() == false then   -- polite quit, like Cmd-Q
          q.result = 'skipped: refused'; skipped[#skipped + 1] = q.name .. " (didn't accept quit)"
        else q.result = 'asked' end
      end
    end
  end
  for _, h in ipairs(changes.hidden) do
    local a = appByBundle(h.bundle)
    if a then a:hide() end
  end
  if m.focus then runShortcut(cfg.focus[m.focus].on, 'Focus on', m.focus) end
  if m.keepDisplayAwake then setDisplayAwake(true) end
  if m.front then
    after('front', 0.8, function() hs.application.launchOrFocusByBundleID(m.front) end)
  end
  if m.timerMinutes then startTimer() end

  -- After a moment, check the quits stuck; anything still running was not quit.
  after('verifyQuit', QUIT_WAIT_SECS, function()
    for _, q in ipairs(state.changes.quit or {}) do
      if q.result == 'asked' then
        if appByBundle(q.bundle) then
          q.result = 'still running'; skipped[#skipped + 1] = q.name .. ' (still running: asking to save?)'
        else q.result = 'quit' end
      end
    end
    state.phase = 'applied'
    writeState(state)
    if #skipped > 0 then
      local msg = 'Not quit: ' .. table.concat(skipped, ', ')
      alert(msg, 6); notify(m.label, msg)
      notes.skipped = msg
    else notes.skipped = nil end
    if updateMenu then updateMenu() end
  end)
end

function M.switch(name)
  if not cfg then alert('Modes: modes.lua is invalid (see Console)'); return end
  if not cfg.modes[name] then alert("Modes: unknown mode '" .. tostring(name) .. "'"); return end
  local prev, prevSince = state.mode, state.since
  notes.skipped = nil; notes.focus = nil
  focusTrack = {}
  local carried
  if state.mode ~= 'Normal' or state.phase == 'restoring' then
    local nextMode = name ~= 'Normal' and cfg.modes[name] or nil
    carried = {}
    if nextMode then
      for _, q in ipairs(changesBeingRestored().quit or {}) do
        if M.modeQuits(nextMode, q) and not pathProblem(q) then carried[#carried + 1] = q end
      end
    end
    restoreToNormal(carried)
  end
  if name ~= 'Normal' then applyMode(name, carried) end
  logSwitch(name, prev, prevSince)
  alert('Mode: ' .. cfg.modes[name].label, 1.5)
  updateMenu()
  return name
end
M_switch = M.switch

local function startBreakTimer()
  every('break', 15, function()
    if state.breakEndsAt and now() >= state.breakEndsAt then
      stopTimer('break'); state.breakEndsAt = nil; writeState(state)
      hs.notify.new(function(n)
        if n:activationType() == hs.notify.activationTypes.actionButtonClicked then M.switch('DeepWork') end
      end, { title = 'Break over', informativeText = 'Start another DeepWork session?',
             hasActionButton = true, actionButtonTitle = 'Another session', withdrawAfter = 0 }):send()
    end
    updateMenu()
  end)
end

function M.takeBreak()
  local mins = (cfg.modes[state.mode] or {}).breakMinutes or 10
  M.switch('Normal')
  state.breakEndsAt = now() + mins * 60
  writeState(state)
  startBreakTimer()
  updateMenu()
end

function M.anotherSession()
  local name = state.mode ~= 'Normal' and state.mode or 'DeepWork'
  M.switch(name)
end

function M.dryRun(name)
  if not cfg then return 'modes.lua is invalid' end
  local text = table.concat(M.plan(cfg, name, snapshot()), '\n')
  print(text)
  return text
end

function M.status()
  local s = string.format('mode=%s since=%s (%s) phase=%s', state.mode,
    os.date('%Y-%m-%d %H:%M', state.since or now()), M.formatDuration(now() - (state.since or now())),
    tostring(state.phase))
  if state.changes.timer then s = s .. ' timer_left=' .. M.formatDuration(state.changes.timer.endsAt - now()) end
  local miss = missingShortcuts()
  if #miss > 0 then s = s .. ' missing_shortcuts=' .. table.concat(miss, ',') end
  s = s .. ' menubar=' .. tostring(menu ~= nil and menu:isInMenuBar())
  if menu then
    s = s .. ' icon=' .. (menu:icon() and 'image' or 'none') .. ' title=' .. tostring(menu:title())
  end
  return s
end

-- ---- menu bar -----------------------------------------------------------------

updateMenu = function()
  if not menu then return end
  local m = cfg and cfg.modes[state.mode] or { label = state.mode, icon = { fallback = '?' } }
  local ic = icons[state.mode]
  local title = nil
  if ic then menu:setIcon(ic.image, ic.template)
  else menu:setIcon(nil); title = m.icon.fallback end
  if state.changes.timer then
    local left = timerDone and 'done' or M.formatDuration(state.changes.timer.endsAt - now())
    title = (title and (title .. ' ') or '') .. left
  elseif state.breakEndsAt then
    title = (title and (title .. ' ') or '') .. '☕ ' .. M.formatDuration(state.breakEndsAt - now())
  end
  menu:setTitle(title)
  menu:setTooltip('Mode: ' .. (m.label or state.mode))
end

local function currentStatusLine()
  local name = state.mode or 'Normal'
  local m = (cfg and cfg.modes[name]) or {}
  local focusName = m.focus
  local spec = focusName and cfg.focus and cfg.focus[focusName]
  local info = {
    mode = name,
    elapsed = now() - (state.since or now()),
    session = focusTrack.session,
    offSkipped = focusTrack.offSkipped,
    focusName = focusName,
    onShortcut = spec and spec.on,
    shortcuts = shortcutsKnown,
    note = notes.focus,
  }
  if state.breakEndsAt then
    info.breakLeft = state.breakEndsAt - now()
  elseif state.changes and state.changes.timer then
    local left = state.changes.timer.endsAt - now()
    if timerDone or left <= 0 then info.timerDone = true else info.remaining = left end
  end
  return M.modeStatus(info)
end

local function menuItems()
  local items = {}
  if not cfg then
    return { { title = 'modes.lua is invalid: see the Hammerspoon Console', disabled = true } }
  end
  for _, name in ipairs(cfg.order) do
    local nm = name
    items[#items + 1] = { title = cfg.modes[name].label, checked = (state.mode == name),
                          fn = function() M.switch(nm) end }
  end
  items[#items + 1] = { title = currentStatusLine(), disabled = true }
  items[#items + 1] = { title = '-' }
  if state.changes.timer then
    if timerDone then
      items[#items + 1] = { title = 'Session done: Take a break', fn = M.takeBreak }
      items[#items + 1] = { title = 'Session done: Back to Normal', fn = function() M.switch('Normal') end }
      items[#items + 1] = { title = 'Session done: Another session', fn = M.anotherSession }
    else
      items[#items + 1] = { title = 'Time left: ' .. M.formatDuration(state.changes.timer.endsAt - now()), disabled = true }
    end
  end
  if state.breakEndsAt then
    items[#items + 1] = { title = 'Break: ' .. M.formatDuration(state.breakEndsAt - now()) .. ' left', disabled = true }
  end
  local miss = missingShortcuts()
  if #miss > 0 then
    local names = miss
    items[#items + 1] = { title = M.missingFixTitle(names), fn = function() fixMissingShortcuts(names) end }
  end
  for _, k in ipairs({ 'skipped', 'focus' }) do
    if notes[k] then items[#items + 1] = { title = notes[k], disabled = true } end
  end
  items[#items + 1] = { title = '-' }
  local dry = {}
  for _, name in ipairs(cfg.order) do
    local nm = name
    dry[#dry + 1] = { title = cfg.modes[name].label, fn = function() M.dryRun(nm); hs.openConsole() end }
  end
  items[#items + 1] = { title = 'Dry run (prints to the Console)', menu = dry }
  items[#items + 1] = { title = 'Open switch log', fn = function() runTask('/usr/bin/open', { '-a', 'Console', LOG_FILE }) end }
  return items
end

-- ---- start ----------------------------------------------------------------------

function M.start()
  local err
  cfg, err = loadConfig()
  state = readState()
  if not hs.fs.attributes(STATE_FILE) then writeState(state) end   -- so 'since' survives reloads
  menu = hs.menubar.new(true, 'pdone-modes')
  if not cfg then
    log.e('modes.lua invalid: ' .. tostring(err))
    menu:setTitle('⚠︎ mode')
    menu:setTooltip('modes.lua is invalid: ' .. tostring(err))
    menu:setMenu(menuItems)
    error('modes.lua invalid: ' .. tostring(err))
  end
  if not cfg.modes[state.mode] then
    log.w('persisted mode ' .. tostring(state.mode) .. ' no longer exists; showing it as Normal-able')
    state.mode = state.mode or 'Normal'
  end
  menu:setMenu(function()
    refreshShortcuts(updateMenu)
    return menuItems()
  end)
  loadIcons()
  updateMenu()
  renderIcons()
  refreshShortcuts(updateMenu)
  -- After a reload / reboot: put back what lives only in memory, keep the rest as recorded.
  local ch = state.changes
  if state.mode ~= 'Normal' and state.phase ~= 'restoring' then
    if ch.displayAwake then setDisplayAwake(true) end
    if ch.timer then startTimer() end
    log.i('restored persisted mode ' .. state.mode)
  end
  if state.mode == 'Normal' and state.breakEndsAt then startBreakTimer() end
  every('menuRefresh', 60, function() updateMenu() end)
  return M
end

function M.stop()
  for k in pairs(timers) do stopTimer(k) end
  if menu then menu:delete(); menu = nil end
end

return M
