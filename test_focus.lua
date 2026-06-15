--- Standalone regression + interaction spec for loveui keyboard (Tab) focus.
--
-- WHAT THIS IS
--   loveui's graphics layer is pure love2d, so its inline test() cases only
--   run inside a love2d window. This script stubs out the love.* API it needs
--   and drives the focus logic headlessly, so the four required Tab-focus
--   scenarios can be reproduced and regression-checked from a plain terminal.
--
-- HOW TO RUN (from the repository root)
--   luajit test_focus.lua      # or:  lua5.1 test_focus.lua
--   (loveui uses the Lua 5.1 / LuaJIT `module()` idiom, so a 5.1-compatible
--    interpreter is required. Lua 5.2+ has no `module` and will not load it.)
--   Exit code 0 = all checks passed; non-zero = a check or an inline test
--   failed. Requiring the library also runs every inline test() in the suite,
--   and any "Test failed" line is treated as a failure here too.
--
-- SCENARIOS COVERED  (each also has a programmatic check below)
--   1. Normal forward switching - Tab moves focus through the focusable
--      controls in order: first -> second -> third.
--   2. End wrap-around          - Tab on the last focusable control returns
--      to the first one (it never stalls on the last control).
--   3. Skip disabled            - controls with `disabled = true` are passed
--      over and never receive Tab focus.
--   4. Skip hidden              - controls whose computed `display == "none"`
--      are passed over and never receive Tab focus.
--   Plus: empty / all-disabled containers are a safe no-op (no error, focus
--   left untouched), the focus/blur callbacks fire in sync with the ui.focus
--   visual state, and nested containers route focus with the same rules.
--
-- HOW TO REPRODUCE THE SAME SCENARIOS MANUALLY IN A LOVE2D APP
--   * Build a ui.context, add a few ui.textfield / ui.button / ui.checkbox.
--   * Forward love.keyreleased(key) to context:keyreleased(key).
--   * Press Tab repeatedly: focus should cycle and wrap (scenarios 1 & 2).
--   * Set someWidget.attributes.disabled = true, or add a style with
--     display = "none" to a widget's tag: Tab should skip it (scenarios 3 & 4).
--   * Give a widget attributes.focusable = false to remove it from the Tab
--     order even though it is shown and enabled.

-- ---------------------------------------------------------------------------
-- Lua 5.1 compatibility shim (test harness only; does not touch the library).
-- loveui targets Lua 5.1 / LuaJIT (module(), setfenv, unpack, ...). Under a
-- real 5.1/LuaJIT interpreter every branch below is a harmless no-op; under
-- Lua 5.2+ it restores just enough of the 5.1 surface to load the library.
-- ---------------------------------------------------------------------------
unpack = unpack or table.unpack
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
math.pow = math.pow or function(x, y) return x ^ y end

if not setfenv then
  local function envindex(fn)
    local i = 1
    while true do
      local name = debug.getupvalue(fn, i)
      if name == "_ENV" then return i end
      if name == nil then return nil end
      i = i + 1
    end
  end
  local function tofunc(target)
    if type(target) == "function" then return target end
    -- target is a stack level relative to the caller of setfenv/getfenv;
    -- +1 accounts for this helper's own frame plus setfenv/getfenv's frame.
    return debug.getinfo(target + 2, "f").func
  end
  function setfenv(target, env)
    local fn = tofunc(target)
    local i = envindex(fn)
    if i then
      debug.upvaluejoin(fn, i, function() return env end, 1)
    end
    return fn
  end
  function getfenv(target)
    local fn = tofunc(target or 1)
    local i = envindex(fn)
    if i then
      local _, value = debug.getupvalue(fn, i)
      return value
    end
    return _G
  end
end

if not package.seeall then
  function package.seeall(M)
    setmetatable(M, { __index = _G })
  end
end

if not module then
  function module(name, ...)
    local M = package.loaded[name]
    if type(M) ~= "table" then
      M = {}
      package.loaded[name] = M
      _G[name] = M
    end
    M._NAME = name
    M._M = M
    M._PACKAGE = string.gsub(name, "[^%.]*$", "")
    setfenv(2, M)
    for _, option in ipairs({...}) do
      option(M)
    end
    return M
  end
end

-- ---------------------------------------------------------------------------
-- Minimal love2d stub: only what loading + the non-drawing focus paths touch.
-- ---------------------------------------------------------------------------
local fakefont = {}
function fakefont:getWidth(s) return s and (#tostring(s) * 7) or 0 end
function fakefont:getHeight() return 14 end

local currentfont = fakefont
local currentcolor = {0, 0, 0, 255}
local noop = function() end

love = {
  graphics = {
    newFont = function() return fakefont end,
    getFont = function() return currentfont end,
    setFont = function(f) currentfont = f end,
    setColor = function(...) currentcolor = {...} end,
    getColor = function() return unpack(currentcolor) end,
    polygon = noop, rectangle = noop, push = noop, pop = noop,
    rotate = noop, translate = noop, scale = noop, line = noop, draw = noop,
    newFramebuffer = noop, setRenderTarget = noop,
    setScissor = noop, getScissor = function() return nil end,
    print = noop, newImage = function() return { setFilter = noop } end,
  },
  timer = { getTime = function() return 0 end },
  keyboard = { isDown = function() return false end },
  mouse = {
    isDown = function() return false end,
    -- Park the cursor far off-screen so update()'s hover logic never fires
    -- and perturbs the focus state during these tests.
    getX = function() return -10000 end,
    getY = function() return -10000 end,
    getPosition = function() return -10000, -10000 end,
  },
  image = { newImageData = function() return { mapPixel = noop } end },
}

-- ---------------------------------------------------------------------------
-- Intercept print before loading so inline test() failures are detected here.
-- ---------------------------------------------------------------------------
local realprint = print
local suitefailures = 0
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  local line = table.concat(parts, "\t")
  if string.find(line, "Test failed", 1, true) then
    suitefailures = suitefailures + 1
  end
  realprint(line)
end

package.path = "./?.lua;" .. package.path
local ui = require "loveui/ui"

-- ---------------------------------------------------------------------------
-- Tiny check helper.
-- ---------------------------------------------------------------------------
local checks, failed = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if cond then
    realprint("  PASS  " .. msg)
  else
    failed = failed + 1
    realprint("  FAIL  " .. msg)
  end
end

local function newform()
  -- A context with three focusable controls of different widget types.
  local c = ui.context()
  local a = c:add(ui.textfield("a", { value = "a" }))
  local b = c:add(ui.button("b", { value = "b" }))
  local d = c:add(ui.checkbox("d", { value = false }))
  return c, a, b, d
end

realprint("== loveui Tab focus regression ==")

-- Scenario 1: normal forward switching.
do
  local c, a, b, d = newform()
  c:keyreleased("tab")
  check(c.focused == a, "S1 normal: Tab -> first control")
  c:keyreleased("tab")
  check(c.focused == b, "S1 normal: Tab -> second control")
  c:keyreleased("tab")
  check(c.focused == d, "S1 normal: Tab -> third control")
end

-- Scenario 2: end wrap-around.
do
  local c, a, b, d = newform()
  c:keyreleased("tab"); c:keyreleased("tab"); c:keyreleased("tab")
  check(c.focused == d, "S2 wrap: focus parked on last control")
  c:keyreleased("tab")
  check(c.focused == a, "S2 wrap: Tab on last wraps back to first")
end

-- Scenario 3: skip disabled controls.
do
  local c, a, b, d = newform()
  b.attributes.disabled = true
  c:keyreleased("tab")
  check(c.focused == a, "S3 skip-disabled: Tab -> a")
  c:keyreleased("tab")
  check(c.focused == d, "S3 skip-disabled: Tab skips disabled b -> d")
  c:keyreleased("tab")
  check(c.focused == a, "S3 skip-disabled: wrap skips disabled b -> a")
end

-- Scenario 4: skip hidden (display:none) controls.
do
  local c = ui.context()
  local a = c:add(ui.textfield("a", { value = "a" }))
  local b = c:add(ui.button("b hidden", { value = "b" }))
  local d = c:add(ui.checkbox("d", { value = false }))
  c:add(ui.style("hidden", { display = "none" }))
  check(b.style.styles.display == "none", "S4 skip-hidden: b computed display==none")
  check(b:focusable() == false, "S4 skip-hidden: hidden b reports not focusable")
  c:keyreleased("tab")
  check(c.focused == a, "S4 skip-hidden: Tab -> a")
  c:keyreleased("tab")
  check(c.focused == d, "S4 skip-hidden: Tab skips hidden b -> d")
  c:keyreleased("tab")
  check(c.focused == a, "S4 skip-hidden: wrap skips hidden b -> a")
end

-- Extra: empty / all-disabled container is a safe no-op (no error, no change).
do
  local c = ui.context()
  local ok = pcall(function() c:keyreleased("tab") end)
  check(ok and c.focused == nil, "no-op: Tab on empty container does nothing")
  local a = c:add(ui.textfield("a", { value = "a" }))
  a.attributes.disabled = true
  c:keyreleased("tab")
  check(c.focused == nil, "no-op: Tab with only disabled controls does nothing")
end

-- Extra: focus/blur callbacks stay in sync with the ui.focus visual state.
do
  local c, a, b, d = newform()
  local log = {}
  a:onfocus(function() log[#log + 1] = "a-focus:" .. tostring(a:match("ui.focus") == true) end)
  a:onblur(function() log[#log + 1] = "a-blur:" .. tostring(a:match("ui.focus") == true) end)
  b:onfocus(function() log[#log + 1] = "b-focus:" .. tostring(b:match("ui.focus") == true) end)
  c:keyreleased("tab")  -- focus a
  c:keyreleased("tab")  -- blur a, focus b
  check(log[1] == "a-focus:true", "order: focus fires with visual tag set")
  check(log[2] == "a-blur:false", "order: blur fires after visual tag cleared")
  check(log[3] == "b-focus:true", "order: next focus fires with its visual tag set")
  check((not a:match("ui.focus")) and b:match("ui.focus"),
    "order: ui.focus moved off old control onto new control")
end

-- Extra: nested containers participate with the same rules (requirement: not
-- worse than before). The flat traversal makes a nested container itself one
-- Tab stop; when the container receives Tab it cycles its own children; and a
-- container can opt out of the Tab order with attributes.focusable = false.
do
  local c = ui.context()
  local field1 = c:add(ui.textfield("f1", { value = "1" }))
  local box = c:add(ui.widget("box"))
  local field2 = c:add(ui.textfield("f2", { value = "2" }))
  local n1 = box:add(ui.textfield("n1", { value = "n1" }))
  local n2 = box:add(ui.textfield("n2", { value = "n2" }))

  -- Top level treats the container as a single focus stop (unchanged model).
  c:keyreleased("tab"); check(c.focused == field1, "nested: top Tab -> field1")
  c:keyreleased("tab"); check(c.focused == box, "nested: top Tab -> container")
  c:keyreleased("tab"); check(c.focused == field2, "nested: top Tab -> field2")
  c:keyreleased("tab"); check(c.focused == field1, "nested: top Tab wraps -> field1")

  -- The same robust cycling logic works at any depth: when the container
  -- itself handles Tab, it walks its own children and wraps.
  box:keyreleased("tab"); check(box.focused == n1, "nested: container Tab -> n1")
  box:keyreleased("tab"); check(box.focused == n2, "nested: container Tab -> n2")
  box:keyreleased("tab"); check(box.focused == n1, "nested: container Tab wraps -> n1")

  -- Disabling a nested child is skipped at its own level too.
  box:focus(nil)
  n1.attributes.disabled = true
  box:keyreleased("tab"); check(box.focused == n2, "nested: container Tab skips disabled n1 -> n2")

  -- A container can be removed from the Tab order without hiding it.
  box.attributes.focusable = false
  c:focus(nil)
  c:keyreleased("tab"); check(c.focused == field1, "opt-out: Tab -> field1")
  c:keyreleased("tab"); check(c.focused == field2, "opt-out: Tab skips focusable=false container -> field2")
end

-- ---------------------------------------------------------------------------
-- Summary.
-- ---------------------------------------------------------------------------
realprint(string.format("== %d checks, %d failed; inline suite failures: %d ==",
  checks, failed, suitefailures))

if failed > 0 or suitefailures > 0 then
  os.exit(1)
end
os.exit(0)
