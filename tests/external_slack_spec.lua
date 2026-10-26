-- Unit tests for hammerspoon/external_slack.lua.
-- Run by tests/external-slack.test.sh with plain Lua 5.4 (CI).
-- Do not run this inside the Hammerspoon hs CLI: the stub replaces hs.
local DIR = (arg and arg[1]) or '.'

local pass, fail = 0, 0
local function ok(desc, cond, extra)
  if cond then pass = pass + 1
  else
    fail = fail + 1
    io.stderr:write('FAIL: ' .. desc .. (extra and (' — ' .. tostring(extra)) or '') .. '\n')
  end
end
local function eq(desc, want, got)
  ok(desc, want == got, 'expected [' .. tostring(want) .. '] got [' .. tostring(got) .. ']')
end

local store = {}
local screens = {}
local watcherFn
local bindings = {}
local slackRunning = true
local queue = {}
local builtin, arzopa, win

local function flush()
  local guard = 0
  while queue[1] and guard < 30 do
    guard = guard + 1
    local fn = table.remove(queue, 1)
    fn()
  end
end

local function screen(name, id, frame)
  return {
    _name = name,
    _id = id,
    _frame = frame,
    name = function(self) return self._name end,
    id = function(self) return self._id end,
    frame = function(self) return self._frame end,
  }
end

builtin = screen('Built-in Retina Display', 1, { x = 0, y = 0, w = 1800, h = 1169 })
arzopa = screen('ARZOPA', 2, { x = -1920, y = 0, w = 1920, h = 1080 })

win = {
  _frame = { x = 10, y = 20, w = 800, h = 600 },
  _full = false,
  _screen = builtin,
  moves = 0,
  framed = nil,
  maximized = false,
}
function win:frame()
  return { x = self._frame.x, y = self._frame.y, w = self._frame.w, h = self._frame.h }
end
function win:setFrame(rect) self.framed = rect end
function win:moveToScreen(target)
  self.moves = self.moves + 1
  self.moved = target
  self._screen = target
end
function win:setFullScreen(value) self._full = value end
function win:isFullScreen() return self._full end
function win:screen() return self._screen end
function win:isStandard() return true end
function win:focus() end
function win:maximize() self.maximized = true end

local app = {
  activate = function() end,
  mainWindow = function() return win end,
  focusedWindow = function() return win end,
  allWindows = function() return { win } end,
}

hs = {
  logger = { new = function() return { i = function() end, e = function() end } end },
  alert = { show = function() end },
  settings = {
    get = function(key) return store[key] end,
    set = function(key, value) store[key] = value end,
    clear = function(key) store[key] = nil end,
  },
  application = {
    get = function(bundle)
      if not slackRunning or bundle ~= 'com.tinyspeck.slackmacgap' then return nil end
      return app
    end,
  },
  geometry = { rect = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end },
  timer = {
    -- Callbacks run after doAfter returns, as they do in Hammerspoon.
    doAfter = function(_, fn)
      local t = { stopped = false }
      function t:stop() self.stopped = true end
      queue[#queue + 1] = function()
        if not t.stopped then fn() end
      end
      return t
    end,
    delayed = {
      new = function(_, fn)
        return {
          start = function()
            queue[#queue + 1] = fn
            flush()
          end,
          stop = function() end,
        }
      end,
    },
  },
  screen = {
    allScreens = function() return screens end,
    primaryScreen = function() return builtin end,
    watcher = {
      new = function(fn)
        watcherFn = fn
        return { start = function() end, stop = function() end }
      end,
    },
  },
  hotkey = {
    bind = function(mods, key, fn)
      local hk = { mods = mods, key = key, fn = fn, deleted = false }
      function hk:delete() self.deleted = true end
      bindings[#bindings + 1] = hk
      return hk
    end,
  },
}

local m = dofile(DIR .. '/hammerspoon/external_slack.lua')

eq('default screen name', 'ARZOPA', m.screenName)
eq('slack bundle', 'com.tinyspeck.slackmacgap', m.slackBundle)
eq('hotkey', 's', m.key)
eq('four modifiers', 4, #m.mods)
eq('modifier shift', 'shift', m.mods[1])
eq('modifier ctrl', 'ctrl', m.mods[2])
eq('modifier alt', 'alt', m.mods[3])
eq('modifier cmd', 'cmd', m.mods[4])
ok('exact name matches', m.nameMatches('ARZOPA'))
ok('name match ignores case', m.nameMatches('arzopa'))
ok('a longer name does not match', not m.nameMatches('ARZOPA display'))
ok('another display does not match', not m.nameMatches('iPad'))
ok('empty name does not match', not m.nameMatches(''))

hs.settings.set('external_slack.screenNames', { 'Portable' })
ok('override replaces the default', m.nameMatches('Portable'))
ok('override drops the default name', not m.nameMatches('ARZOPA'))
hs.settings.clear('external_slack.screenNames')

local function reset()
  store = {}
  screens = { builtin, arzopa }
  slackRunning = true
  win._frame = { x = 10, y = 20, w = 800, h = 600 }
  win._full = false
  win._screen = builtin
  win.moves = 0
  win.moved = nil
  win.framed = nil
  win.maximized = false
  m.stop()
end

reset()
m.start()
flush()
eq('plug at start moves Slack onto the ARZOPA', arzopa, win.moved)
ok('plug at start makes Slack full screen', win._full)
ok('plug at start remembers that we moved Slack', store['external_slack.applied'] == true)
eq('saved frame x', 10, store['external_slack.savedFrame'].x)
eq('saved frame w', 800, store['external_slack.savedFrame'].w)
local movesAfterStart = win.moves
watcherFn()
eq('a repeat screen event does not move Slack again', movesAfterStart, win.moves)

screens = { builtin }
watcherFn()
ok('unplug leaves full screen', not win._full)
eq('unplug moves Slack back to the built-in display', builtin, win.moved)
eq('unplug restores the saved x', 10, win.framed.x)
eq('unplug restores the saved y', 20, win.framed.y)
eq('unplug restores the saved width', 800, win.framed.w)
eq('unplug restores the saved height', 600, win.framed.h)
ok('unplug clears the applied flag', not store['external_slack.applied'])
ok('unplug clears the saved frame', store['external_slack.savedFrame'] == nil)
ok('unplug does not maximize a frame that fits', not win.maximized)

reset()
slackRunning = false
m.start()
flush()
eq('Slack not running does not move a window', 0, win.moves)
ok('Slack not running does not mark itself applied', not store['external_slack.applied'])

reset()
store['external_slack.applied'] = true
store['external_slack.savedFrame'] = { x = 10, y = 20, w = 800, h = 600 }
m.start()
flush()
eq('already moved at start does not move again', 0, win.moves)

reset()
screens = { builtin }
store['external_slack.applied'] = true
store['external_slack.savedFrame'] = { x = 30, y = 40, w = 700, h = 500 }
win._full = true
win._screen = arzopa
m.start()
flush()
eq('missing at start restores the saved width', 700, win.framed.w)
eq('missing at start returns to the built-in display', builtin, win._screen)
ok('missing at start leaves full screen', not win._full)

reset()
m.start()
flush()
local before = win.moves
m.toggle()
flush()
ok('hotkey brings Slack back while the monitor is still connected', win.moves > before)
ok('hotkey clears the applied flag', not store['external_slack.applied'])
before = win.moves
watcherFn()
eq('the monitor staying connected does not undo the hotkey', before, win.moves)

local hk = bindings[#bindings]
eq('bound key', 's', hk.key)
eq('bound shift', 'shift', hk.mods[1])
eq('bound ctrl', 'ctrl', hk.mods[2])
eq('bound alt', 'alt', hk.mods[3])
eq('bound cmd', 'cmd', hk.mods[4])
ok('callback is the toggle', m.toggle == hk.fn)

local msg = string.format('external slack tests: %d passed, %d failed', pass, fail)
print(msg)
if fail > 0 then os.exit(1) end
return msg
