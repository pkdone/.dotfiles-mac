-- Unit tests for hammerspoon/modes.lua + the pure half of hammerspoon/mode_switcher.lua.
-- Run by tests/modes.test.sh with a plain Lua 5.4 (CI) or inside Hammerspoon (`hs`).
-- Returns (and prints) "modes tests: N passed, M failed".
local DIR = (arg and arg[1]) or MODES_TEST_DIR or '.'
local ms = dofile(DIR .. '/hammerspoon/mode_switcher.lua')
local cfg = dofile(DIR .. '/hammerspoon/modes.lua')

local pass, fail, out = 0, 0, {}
local function ok(desc, cond, extra)
  if cond then pass = pass + 1 else fail = fail + 1; out[#out + 1] = 'FAIL: ' .. desc .. (extra and (' — ' .. tostring(extra)) or '') end
end
local function eq(desc, want, got) ok(desc, want == got, 'expected [' .. tostring(want) .. '] got [' .. tostring(got) .. ']') end
local function deepcopy(t)
  if type(t) ~= 'table' then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = deepcopy(v) end
  return r
end
local function has(lines, needle)
  for _, l in ipairs(lines) do if l:find(needle, 1, true) then return true end end
  return false
end

-- ---- the real modes.lua -----------------------------------------------------
local valid, errs = ms.validate(cfg)
ok('modes.lua is valid', valid, errs and table.concat(errs, '; '))
eq('order starts with Normal', 'Normal', cfg.order[1])
for _, name in ipairs({ 'Normal', 'WebConf', 'DeepWork' }) do ok(name .. ' defined', cfg.modes[name] ~= nil) end
eq('Normal icon is the desktop computer', 'desktopcomputer', cfg.modes.Normal.icon.symbol)
eq('WebConf icon is the red record', 'record.circle.fill', cfg.modes.WebConf.icon.symbol)
eq('DeepWork default timer', 50, cfg.modes.DeepWork.timerMinutes)
eq('validateFile on the repo file', 'ok', ms.validateFile(DIR .. '/hammerspoon/modes.lua'))

-- ---- validation catches mistakes ----------------------------------------------
local function bad(desc, mutate, needle)
  local c = deepcopy(cfg); mutate(c)
  local v, e = ms.validate(c)
  ok(desc .. ' rejected', not v)
  if needle then ok(desc .. ' message', e and table.concat(e, '; '):find(needle, 1, true) ~= nil, e and table.concat(e, '; ')) end
end
bad('missing Normal', function(c) c.modes.Normal = nil end, 'a Normal mode is required')
bad('Normal with actions', function(c) c.modes.Normal.quit = { 'com.x.y' } end, "Normal can't have actions")
bad('typo key', function(c) c.modes.WebConf.qiut = {} end, "unknown key 'qiut'")
bad('bad bundle id', function(c) c.modes.WebConf.quit = { 'not a bundle' } end, 'bad bundle id')
bad('unknown focus', function(c) c.modes.DeepWork.focus = 'Nope' end, "focus 'Nope'")
bad('mode not in order', function(c) c.modes.Extra = { label = 'x', icon = { symbol = 'a', fallback = 'b' } } end, 'missing from order')
bad('timer out of range', function(c) c.modes.DeepWork.timerMinutes = 0 end, 'timerMinutes must be 1-600')
bad('meetingAlerts removed', function(c) c.modes.DeepWork.meetingAlerts = true end, "unknown key 'meetingAlerts'")
ok('no meetings config', cfg.meetings == nil)
eq('validateFile reports syntax errors', 'error', (ms.validateFile(DIR .. '/tests/modes_spec.lua.nope')):sub(1, 5))

-- ---- helpers --------------------------------------------------------------------
eq('duration <1m', '<1m', ms.formatDuration(30))
eq('duration minutes', '42m', ms.formatDuration(42 * 60 + 5))
eq('duration hours', '2h 05m', ms.formatDuration(125 * 60))

-- ---- dry-run plans -----------------------------------------------------------------------
local snap = { current = 'Normal', changes = {}, shortcuts = {},
  running = { ['net.whatsapp.WhatsApp'] = true, ['com.tinyspeck.slackmacgap'] = true, ['com.granola.app'] = true },
  hidden = {}, names = { ['net.whatsapp.WhatsApp'] = 'WhatsApp', ['com.tinyspeck.slackmacgap'] = 'Slack',
                         ['com.spotify.client'] = 'Spotify', ['com.granola.app'] = 'Granola' } }
local wc = ms.plan(cfg, 'WebConf', snap)
ok('WebConf: dry-run header', wc[1]:find('dry run, nothing changed', 1, true))
ok('WebConf: state written first', has(wc, 'write state.json'))
ok('WebConf: quits WhatsApp', has(wc, 'quit WhatsApp politely'))
ok('WebConf: Spotify not running', has(wc, 'quit Spotify: not running, skip'))
ok('WebConf: hides Slack', has(wc, 'hide Slack'))
ok('WebConf: missing Focus Shortcut noted', has(wc, "Shortcut 'Mode WebConf On' (MISSING"))
ok('WebConf: display awake', has(wc, 'keep the display awake'))
ok('WebConf: nothing about desktop icons', not has(wc, 'desktop'))
bad('removed hideDesktopIcons option', function(c) c.modes.WebConf.hideDesktopIcons = true end, "unknown key 'hideDesktopIcons'")
ok('WebConf: nothing about Chrome tabs', not has(wc, 'Chrome:'))
bad('removed chromeTabs option', function(c) c.modes.WebConf.chromeTabs = true end, "unknown key 'chromeTabs'")
ok('WebConf: badges explained', has(wc, 'no macOS API'))
ok('WebConf: Granola to the front', has(wc, 'bring Granola to the front'))
local dw = ms.plan(cfg, 'DeepWork', snap)
ok('DeepWork: quits Slack', has(dw, 'quit Slack politely'))
ok('DeepWork: hides Granola', has(dw, 'hide Granola'))
ok('DeepWork: timer', has(dw, '50-minute countdown'))
ok('DeepWork: never auto-switches', has(dw, 'never switches by itself'))
ok('DeepWork: Spotify untouched', not has(dw, 'Spotify'))
ok('DeepWork: no meeting alerts', not has(dw, 'meeting') and not has(dw, 'Mode Upcoming Meetings') and not has(dw, 'calendar'))
local from = deepcopy(snap); from.current = 'WebConf'
from.changes = { quit = { { bundle = 'com.spotify.client', name = 'Spotify' } }, hidden = { { bundle = 'com.tinyspeck.slackmacgap', name = 'Slack' } },
                 focus = 'WebConf', displayAwake = true }
local sw = ms.plan(cfg, 'DeepWork', from)
ok('switch between modes restores first', has(sw, 'first, restore'))
local nm = ms.plan(cfg, 'Normal', from)
ok('Normal: reopens quit apps in background', has(nm, 'reopen Spotify in the background'))
ok('Normal: unhides', has(nm, 'unhide Slack'))
ok('Normal: Focus off', has(nm, "Shortcut 'Mode WebConf Off'"))
ok('Normal: display sleep back', has(nm, 'allow display sleep'))
ok('Normal: nothing about Chrome tabs', not has(nm, 'Chrome'))
local timed = deepcopy(from)
timed.changes.timer = { minutes = 50 }
local nt = ms.plan(cfg, 'Normal', timed)
ok('Normal: stops the DeepWork timer', has(nt, 'stop the DeepWork timer'))
ok('Normal: no meeting checks', not has(nt, 'meeting'))
ok('Normal from Normal: nothing', has(ms.plan(cfg, 'Normal', snap), 'nothing recorded to restore'))

local summary = string.format('modes tests: %d passed, %d failed', pass, fail)
if #out > 0 then summary = table.concat(out, '\n') .. '\n' .. summary end
print(summary)
return summary
