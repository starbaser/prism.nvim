-- Adaptive refresh scheduling.

local helpers = dofile("tests/helpers.lua")
local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

local events
local stats
local registry
local slots

T["events"] = new_set({
  hooks = {
    pre_case = function()
      local _, set_wrap = helpers.spy()
      local _, clear_wrap = helpers.spy()
      package.loaded["prism.terminal"] = {
        set_slot = set_wrap,
        clear_slot = clear_wrap,
        pop = function() end,
      }
      package.loaded["prism.events"] = nil
      package.loaded["prism.stats"] = nil
      package.loaded["prism.registry"] = nil
      package.loaded["prism.slots"] = nil
      package.loaded["prism.scanner"] = nil

      stats = require("prism.stats")
      registry = require("prism.registry")
      slots = require("prism.slots")
      events = require("prism.events")

      stats.reset()
      registry._reset()
      slots._reset()
      vim.cmd("enew")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello" })
      vim.api.nvim_set_hl(0, "Normal", { bg = 0x101010 })
      registry.register("Normal", 0.5)
      registry.rebuild_color_index()

      events.debounce_ms = 20
      events.max_refresh_hz = 20
      events.burst_window_ms = 100
      events.burst_event_threshold = 8
      events.burst_quiet_ms = 40
    end,
    post_case = function()
      events.detach()
      package.loaded["prism.terminal"] = nil
      package.loaded["prism.events"] = nil
      package.loaded["prism.stats"] = nil
      package.loaded["prism.registry"] = nil
      package.loaded["prism.slots"] = nil
      package.loaded["prism.scanner"] = nil
    end,
  },
})

local function wait_for_refreshes(n)
  return vim.wait(500, function()
    return stats.snapshot().scan.count >= n
  end, 5)
end

T["events"]["force_refresh runs immediately"] = function()
  events.force_refresh()
  local s = stats.snapshot()
  eq(s.scan.count, 1)
  eq(s.events, 1)
end

T["events"]["normal debounce merges rapid events"] = function()
  events.schedule_refresh()
  events.schedule_refresh()
  events.schedule_refresh()
  eq(stats.snapshot().scan.count, 0)
  eq(wait_for_refreshes(1), true)
  local s = stats.snapshot()
  eq(s.scan.count, 1)
  eq(s.events, 3)
  eq(s.merged_events >= 2, true)
end

T["events"]["burst mode caps refreshes and exits after quiet"] = function()
  events.debounce_ms = 1000
  events.burst_event_threshold = 3
  events.burst_quiet_ms = 30

  for _ = 1, 6 do
    events.schedule_refresh()
  end

  eq(wait_for_refreshes(1), true)
  local active = stats.snapshot()
  eq(active.burst_entries, 1)
  eq(active.capped_refreshes > 0, true)

  local quiet = vim.wait(500, function()
    return stats.snapshot().burst_active == false
  end, 5)
  eq(quiet, true)
end

return T
