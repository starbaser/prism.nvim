-- Minimum-diff reconciliation against a spied terminal.

local helpers = dofile("tests/helpers.lua")
local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

local slots
local set_spy, clear_spy

T["slots"] = new_set({
  hooks = {
    pre_case = function()
      -- Inject a fake terminal module before slots loads.
      local s_spy, s_wrap = helpers.spy()
      local c_spy, c_wrap = helpers.spy()
      set_spy, clear_spy = s_spy, c_spy
      package.loaded["prism.terminal"] = {
        set_slot = s_wrap,
        clear_slot = c_wrap,
      }
      package.loaded["prism.slots"] = nil
      slots = require("prism.slots")
      slots._reset()
    end,
    post_case = function()
      package.loaded["prism.terminal"] = nil
      package.loaded["prism.slots"] = nil
    end,
  },
})

local function reg(name, idx, nudged_bg, opacity)
  return { name = name, index = idx, nudged_bg = nudged_bg, opacity = opacity,
           original_bg = nudged_bg - 1 }
end

T["slots"]["empty desired with empty current does nothing"] = function()
  slots.reconcile({})
  eq(set_spy.call_count, 0)
  eq(clear_spy.call_count, 0)
end

T["slots"]["fills two new slots"] = function()
  local r1 = reg("A", 1, 0x111111, 0.5)
  local r2 = reg("B", 2, 0x222222, 0.4)
  local emitted = slots.reconcile({ r1, r2 })
  eq(emitted, 2)
  eq(set_spy.call_count, 2)
  eq(clear_spy.call_count, 0)
  eq(set_spy.calls[1], { 1, 0x111111, 0.5 })
  eq(set_spy.calls[2], { 2, 0x222222, 0.4 })
end

T["slots"]["reconcile returns 0 when nothing changes"] = function()
  local r1 = reg("A", 1, 0x111111, 0.5)
  slots.reconcile({ r1 })
  local emitted = slots.reconcile({ r1 })
  eq(emitted, 0)
end

T["slots"]["unchanged slot is not re-emitted"] = function()
  local r1 = reg("A", 1, 0x111111, 0.5)
  local r2 = reg("B", 2, 0x222222, 0.4)
  local r3 = reg("C", 3, 0x333333, 0.3)
  slots.reconcile({ r1, r2 })
  -- Reset spy counters; only the delta should be emitted next.
  set_spy.calls, set_spy.call_count = {}, 0
  clear_spy.calls, clear_spy.call_count = {}, 0
  slots.reconcile({ r1, r3 })
  eq(set_spy.call_count, 1)
  eq(clear_spy.call_count, 0)
  eq(set_spy.calls[1], { 2, 0x333333, 0.3 })
end

T["slots"]["dropping all clears every occupied slot"] = function()
  local r1 = reg("A", 1, 0x111111, 0.5)
  local r2 = reg("B", 2, 0x222222, 0.4)
  slots.reconcile({ r1, r2 })
  set_spy.calls, set_spy.call_count = {}, 0
  clear_spy.calls, clear_spy.call_count = {}, 0
  slots.reconcile({})
  eq(set_spy.call_count, 0)
  eq(clear_spy.call_count, 2)
  eq(clear_spy.calls[1], { 1 })
  eq(clear_spy.calls[2], { 2 })
end

T["slots"]["caps at MAX_SLOTS"] = function()
  local many = {}
  for i = 1, 9 do
    many[i] = reg("R" .. i, i, 0x100000 + i, 0.5)
  end
  slots.reconcile(many)
  eq(set_spy.call_count, slots.MAX_SLOTS)
  eq(clear_spy.call_count, 0)
end

T["slots"]["snapshot reflects current occupancy"] = function()
  local r1 = reg("A", 1, 0x111111, 0.5)
  slots.reconcile({ r1 })
  local snap = slots.snapshot()
  eq(snap[1], r1)
  for i = 2, slots.MAX_SLOTS do
    eq(snap[i], nil)
  end
end

T["slots"]["clear_all empties everything"] = function()
  local r1 = reg("A", 1, 0x111111, 0.5)
  local r2 = reg("B", 2, 0x222222, 0.4)
  slots.reconcile({ r1, r2 })
  set_spy.calls, set_spy.call_count = {}, 0
  clear_spy.calls, clear_spy.call_count = {}, 0
  slots.clear_all()
  eq(clear_spy.call_count, 2)
end

return T
