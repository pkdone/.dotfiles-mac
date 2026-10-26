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
bad('bad app path', function(c) c.modes.WebConf.quit = { { path = 'not-an-app' } } end, 'bad app path')
bad('app path with an extra key', function(c)
  c.modes.WebConf.quit = { { path = '~/Applications/WhatsApp Web.app', bundle = 'com.apple.Safari' } }
end, 'bad app path')
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
  running = { ['com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod'] = true,
              ['com.tinyspeck.slackmacgap'] = true, ['com.granola.app'] = true },
  hidden = {}, names = { ['com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod'] = 'YouTube Music',
                         ['com.tinyspeck.slackmacgap'] = 'Slack',
                         ['com.spotify.client'] = 'Spotify', ['com.granola.app'] = 'Granola' } }
local wc = ms.plan(cfg, 'WebConf', snap)
ok('WebConf: dry-run header', wc[1]:find('dry run, nothing changed', 1, true))
ok('WebConf: state written first', has(wc, 'write state.json'))
ok('WebConf: quits YouTube Music', has(wc, 'quit YouTube Music politely'))
ok('WebConf: Spotify not running', has(wc, 'quit Spotify: not running, skip'))
ok('WebConf: WhatsApp Web not running', has(wc, 'quit WhatsApp Web: not running, skip'))
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
ok('DeepWork: WhatsApp Web not running', has(dw, 'quit WhatsApp Web: not running, skip'))
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

-- WhatsApp Web is a path app. The bundle id is per Mac, so it is not stored here.
local waPath = '~/Applications/WhatsApp Web.app'
local waSpec
for _, spec in ipairs(cfg.modes.WebConf.quit) do
  if type(spec) == 'table' and spec.path == waPath then waSpec = spec end
end
ok('WebConf quits WhatsApp Web by app path', waSpec ~= nil)
eq('WhatsApp Web display name', 'WhatsApp Web', waSpec and waSpec.name)
local deepWa = false
for _, spec in ipairs(cfg.modes.DeepWork.quit) do
  if type(spec) == 'table' and spec.path == waPath then deepWa = true end
end
ok('DeepWork quits the same WhatsApp Web path', deepWa)
local storedId = false
local function walkIds(t)
  if type(t) == 'string' and t:find('WebApp%.', 1, false) then storedId = true end
  if type(t) ~= 'table' then return end
  for _, v in pairs(t) do walkIds(v) end
end
walkIds(cfg)
ok('modes.lua does not store a Safari web app id', not storedId)

local waMissing = deepcopy(snap)
waMissing.missing = { [waPath] = true }
local wcm = ms.plan(cfg, 'WebConf', waMissing)
ok('WebConf: WhatsApp Web not installed', has(wcm, 'quit WhatsApp Web: not installed, skip'))
ok('not installed is a skip, not an error', not has(wcm, 'error'))
local dwm = ms.plan(cfg, 'DeepWork', waMissing)
ok('DeepWork: WhatsApp Web not installed', has(dwm, 'quit WhatsApp Web: not installed, skip'))

local waBlocked = deepcopy(snap)
waBlocked.blocked = { [waPath] = true }
waBlocked.running[waPath] = true
ok('WebConf: refuses to quit Safari', has(ms.plan(cfg, 'WebConf', waBlocked), 'quit WhatsApp Web: would quit Safari, skip'))

local waUnread = deepcopy(snap)
waUnread.unreadable = { [waPath] = true }
ok('WebConf: unreadable bundle id is a skip', has(ms.plan(cfg, 'WebConf', waUnread), "quit WhatsApp Web: can't read its bundle id, skip"))

local waRun = deepcopy(snap)
waRun.running[waPath] = true
waRun.names[waPath] = 'WhatsApp Web'
ok('WebConf: quits a running WhatsApp Web politely', has(ms.plan(cfg, 'WebConf', waRun), 'quit WhatsApp Web politely'))
ok('DeepWork: quits a running WhatsApp Web politely', has(ms.plan(cfg, 'DeepWork', waRun), 'quit WhatsApp Web politely'))

-- A fake id, not the one on any real Mac. state.json stores the id read at quit time.
local waBundle = 'com.apple.Safari.WebApp.11111111-2222-3333-4444-555555555555'
local waExpanded = '/tmp/home/Applications/WhatsApp Web.app'
local waSnap = {
  running = { [waPath] = true },
  names = { [waPath] = 'WhatsApp Web' },
  bundles = { [waPath] = waBundle },
  paths = { [waPath] = waExpanded },
}
local waRec = ms.quitRecord(waSpec, waSnap)
eq('quit records the resolved bundle id', waBundle, waRec and waRec.bundle)
eq('quit records the app path', waExpanded, waRec and waRec.path)
eq('quit records the configured path', waPath, waRec and waRec.app)
eq('quit records the display name', 'WhatsApp Web', waRec and waRec.name)
ok('DeepWork quits that recorded app', ms.modeQuits(cfg.modes.DeepWork, waRec))
ok('WebConf quits that recorded app', ms.modeQuits(cfg.modes.WebConf, waRec))
ok('DeepWork does not quit Spotify', not ms.modeQuits(cfg.modes.DeepWork, { bundle = 'com.spotify.client', name = 'Spotify' }))
eq('a missing WhatsApp Web is not recorded', nil, ms.quitRecord(waSpec, { missing = { [waPath] = true }, running = {} }))
eq('a stopped WhatsApp Web is not recorded', nil, ms.quitRecord(waSpec, { running = {} }))
eq('Safari itself is not recorded', nil, ms.quitRecord(waSpec, {
  running = { [waPath] = true }, blocked = { [waPath] = true },
  bundles = { [waPath] = 'com.apple.Safari' }, paths = { [waPath] = '/Applications/Safari.app' },
}))
eq('a Safari bundle id is refused even when marked running', nil, ms.quitRecord(waSpec, {
  running = { [waPath] = true }, bundles = { [waPath] = 'com.apple.Safari' },
  paths = { [waPath] = '/Applications/Safari.app' },
}))
local spot = ms.quitRecord('com.spotify.client', {
  running = { ['com.spotify.client'] = true }, names = { ['com.spotify.client'] = 'Spotify' },
})
eq('a normal app is still recorded by bundle id', 'com.spotify.client', spot and spot.bundle)
eq('a normal app has no path', nil, spot and spot.path)

local reopen = ms.reopenArgs(waRec)
eq('reopen launches in the background', '-g', reopen and reopen[1])
eq('reopen uses the web app path', waExpanded, reopen and reopen[2])
ok('reopen by path does not name Safari', reopen and not reopen[2]:find('Safari', 1, true))
local reopenId = ms.reopenArgs({ bundle = waBundle, name = 'WhatsApp Web' })
eq('reopen by bundle id is still background', '-g', reopenId and reopenId[1])
eq('reopen by bundle id uses -b', '-b', reopenId and reopenId[2])
eq('reopen by bundle id is the web app', waBundle, reopenId and reopenId[3])
ok('reopen by bundle id is not Safari itself', reopenId and reopenId[3] ~= 'com.apple.Safari')
eq('Safari is not launched', nil, ms.reopenArgs({ bundle = 'com.apple.Safari', name = 'Safari' }))
local reopenSpot = ms.reopenArgs({ bundle = 'com.spotify.client', name = 'Spotify' })
eq('other apps still reopen with open -g -b', '-b', reopenSpot and reopenSpot[2])
eq('other apps reopen their own bundle id', 'com.spotify.client', reopenSpot and reopenSpot[3])

local waBack = deepcopy(snap)
waBack.current = 'WebConf'
waBack.changes = { quit = { waRec } }
ok('Normal: reopens WhatsApp Web in the background', has(ms.plan(cfg, 'Normal', waBack), 'reopen WhatsApp Web in the background (open -g)'))

-- WebConf and DeepWork both quit WhatsApp Web. Switching between them must
-- leave it quit and keep the record, or Normal would lose it and open -g would
-- race the next quit.
local fromWa = deepcopy(snap)
fromWa.current = 'WebConf'
fromWa.changes = { quit = {
  { bundle = waBundle, name = 'WhatsApp Web', path = waExpanded, app = waPath },
  { bundle = 'com.spotify.client', name = 'Spotify' },
}, focus = 'WebConf' }
local toDeep = ms.plan(cfg, 'DeepWork', fromWa)
ok('DeepWork leaves WhatsApp Web quit', has(toDeep, 'leave WhatsApp Web quit (this mode quits it too)'))
ok('DeepWork still reopens Spotify', has(toDeep, 'reopen Spotify in the background'))
ok('DeepWork does not reopen WhatsApp Web', not has(toDeep, 'reopen WhatsApp Web'))
ok('DeepWork keeps the quit for Normal', has(toDeep, 'quit WhatsApp Web: already quit, kept so Normal reopens it'))
local gone = deepcopy(fromWa)
gone.missing = { [waPath] = true }
local gonePlan = ms.plan(cfg, 'DeepWork', gone)
ok('a missing WhatsApp Web is not kept quit', has(gonePlan, 'quit WhatsApp Web: not installed, skip'))
ok('a missing WhatsApp Web is not reopened', has(gonePlan, 'reopen WhatsApp Web: not installed, skip'))
ok('a missing WhatsApp Web is not described as already quit', not has(gonePlan, 'already quit'))

-- ---- Focus skip toast + menu status line ---------------------------------------
eq('missing Shortcut is missing', true, ms.shortcutMissing({}, 'Mode WebConf On'))
eq('present Shortcut is not missing', false, ms.shortcutMissing({ ['Mode WebConf On'] = true }, 'Mode WebConf On'))
eq('unknown Shortcut list is not missing', false, ms.shortcutMissing(nil, 'Mode WebConf On'))
eq('WebConf skip toast', "WebConf Focus skipped — create 'Mode WebConf On' in Shortcuts",
  ms.focusSkipToast('WebConf', 'Mode WebConf On'))
eq('DeepWork skip toast', "DeepWork Focus skipped — create 'Mode DeepWork On' in Shortcuts",
  ms.focusSkipToast('DeepWork', 'Mode DeepWork On'))
eq('one missing Fix title', 'Create missing: Mode WebConf On',
  ms.missingFixTitle({ 'Mode WebConf On' }))
eq('several missing Fix title', 'Create missing: Mode WebConf On, Mode WebConf Off',
  ms.missingFixTitle({ 'Mode WebConf On', 'Mode WebConf Off' }))
eq('missing Fix clipboard is one name per line', "Mode WebConf On\nMode DeepWork Off",
  ms.missingFixClipboard({ 'Mode WebConf On', 'Mode DeepWork Off' }))
eq('one missing Fix alert', "Copied 'Mode WebConf On' — opening Shortcuts",
  ms.missingFixAlert({ 'Mode WebConf On' }))
eq('several missing Fix alert', 'Copied 2 Shortcut names — opening Shortcuts',
  ms.missingFixAlert({ 'Mode WebConf On', 'Mode WebConf Off' }))

local function attempt(prev, which, listed, present)
  return ms.afterFocusAttempt(prev, which, listed, present)
end
local onThere = attempt(nil, 'on', true, true)
eq('present On records Focus on', 'on', onThere.session)
eq('present On does not skip', false, onThere.offSkipped)
local onGone = attempt(nil, 'on', true, false)
eq('missing On records Focus off', 'off', onGone.session)
eq('unlisted Shortcuts record nothing', nil, attempt(nil, 'on', false, false).session)
local offGone = attempt(nil, 'off', true, false)
eq('missing Off is unknown', nil, offGone.session)
eq('missing Off is flagged', true, offGone.offSkipped)
local bothGone = attempt(offGone, 'on', true, false)
eq('missing Off then On stays unknown', nil, bothGone.session)
eq('present On after missing Off is Focus on', 'on', attempt(offGone, 'on', true, true).session)
eq('present Off records Focus off', 'off', attempt(nil, 'off', true, true).session)

local webOn = { ['Mode WebConf On'] = true }
local deepOn = { ['Mode DeepWork On'] = true }
eq('WebConf status', 'WebConf · 12m · Focus on', ms.modeStatus({
  mode = 'WebConf', elapsed = 12 * 60 + 20, focusName = 'WebConf',
  onShortcut = 'Mode WebConf On', shortcuts = webOn,
}))
eq('DeepWork status prefers time left', 'DeepWork · 42m left · Focus on', ms.modeStatus({
  mode = 'DeepWork', elapsed = 8 * 60, remaining = 42 * 60 + 10, focusName = 'DeepWork',
  onShortcut = 'Mode DeepWork On', shortcuts = deepOn,
}))
eq('Normal status', 'Normal · restored', ms.modeStatus({
  mode = 'Normal', elapsed = 3 * 60, shortcuts = { ['Mode WebConf Off'] = true },
}))
eq('Normal Focus off when restored', 'Normal · restored · Focus off', ms.modeStatus({
  mode = 'Normal', session = 'off',
}))
eq('DeepWork done', 'DeepWork · done · Focus on', ms.modeStatus({
  mode = 'DeepWork', timerDone = true, remaining = 0, elapsed = 50 * 60, session = 'on',
}))
eq('WebConf Focus unknown while Shortcuts are unlisted', 'WebConf · <1m', ms.modeStatus({
  mode = 'WebConf', elapsed = 10, focusName = 'WebConf', onShortcut = 'Mode WebConf On',
}))
eq('missing On shows Focus off', 'WebConf · 12m · Focus off', ms.modeStatus({
  mode = 'WebConf', elapsed = 12 * 60, session = 'off', focusName = 'WebConf',
  onShortcut = 'Mode WebConf On', shortcuts = {},
}))
eq('failed Shortcut omits Focus', 'WebConf · 12m', ms.modeStatus({
  mode = 'WebConf', elapsed = 12 * 60, focusName = 'WebConf', onShortcut = 'Mode WebConf On',
  shortcuts = webOn, note = "Focus on: Shortcut 'Mode WebConf On' failed",
}))
eq('break status', 'Normal · break 8m left · Focus off', ms.modeStatus({
  mode = 'Normal', breakLeft = 8 * 60 + 5, session = 'off',
}))
eq('skipped Off does not claim Focus off', 'DeepWork · 42m left', ms.modeStatus({
  mode = 'DeepWork', remaining = 42 * 60, offSkipped = true, focusName = 'DeepWork',
  onShortcut = 'Mode DeepWork On', shortcuts = {},
}))

local summary = string.format('modes tests: %d passed, %d failed', pass, fail)
if #out > 0 then summary = table.concat(out, '\n') .. '\n' .. summary end
print(summary)
return summary
