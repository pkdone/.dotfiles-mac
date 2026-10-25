-- Unit tests for hammerspoon/finder_hotkey.lua.
-- Run by tests/finder-hotkey.test.sh with a plain Lua 5.4 (CI).
-- Do not run this inside the Hammerspoon `hs` CLI: the stub replaces the
-- global `hs` table, which the live app needs.
-- Returns (and prints) "finder hotkey tests: N passed, M failed".
local DIR = (arg and arg[1]) or FINDER_HOTKEY_TEST_DIR or '.'
local m = dofile(DIR .. '/hammerspoon/finder_hotkey.lua')

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

eq('app is Finder', 'Finder', m.app)
eq('key is f', 'f', m.key)
eq('three modifiers', 3, #m.mods)
eq('modifier shift', 'shift', m.mods[1])
eq('modifier ctrl', 'ctrl', m.mods[2])
eq('modifier cmd', 'cmd', m.mods[3])
local function hasMod(name)
  for _, mod in ipairs(m.mods) do
    if mod == name then return true end
  end
  return false
end
ok('no option modifier', not hasMod('alt') and not hasMod('option'))

local launched
local bindings = {}
hs = {
  application = {
    launchOrFocus = function(name) launched = name end,
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

m.press()
eq('press launches Finder', 'Finder', launched)

launched = nil
m.start()
local first = bindings[1]
ok('start binds a hotkey', first ~= nil)
eq('bound key', 'f', first.key)
eq('bound shift', 'shift', first.mods[1])
eq('bound ctrl', 'ctrl', first.mods[2])
eq('bound cmd', 'cmd', first.mods[3])
eq('callback is press', m.press, first.fn)
first.fn()
eq('callback launches Finder', 'Finder', launched)

m.start()
ok('a second start drops the previous hotkey', first.deleted)
ok('the replacement hotkey stays bound', bindings[2] ~= nil and bindings[2].deleted == false)

m.stop()
ok('stop drops the live hotkey', bindings[2].deleted)

local msg = string.format('finder hotkey tests: %d passed, %d failed', pass, fail)
print(msg)
return msg
