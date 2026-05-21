-- Timing/emission counter bookkeeping.

local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

local stats

T["stats"] = new_set({
  hooks = {
    pre_case = function()
      package.loaded["prism.stats"] = nil
      stats = require("prism.stats")
      stats.reset()
    end,
  },
})

T["stats"]["empty snapshot reports zeroes"] = function()
  local s = stats.snapshot()
  eq(s.scan.count, 0)
  eq(s.scan.last_us, 0)
  eq(s.scan.min_us, 0)
  eq(s.scan.max_us, 0)
  eq(s.scan.mean_us, 0)
  eq(s.reconcile.count, 0)
  eq(s.emissions, 0)
  eq(s.last_visible_count, 0)
  eq(s.last_desired_count, 0)
end

T["stats"]["record_scan accumulates count and ns"] = function()
  stats.record_scan(2000, 5)
  stats.record_scan(4000, 7)
  local s = stats.snapshot()
  eq(s.scan.count, 2)
  eq(s.scan.last_us, 4.0)
  eq(s.scan.min_us, 2.0)
  eq(s.scan.max_us, 4.0)
  eq(s.scan.mean_us, 3.0)
  eq(s.last_visible_count, 7)
end

T["stats"]["record_reconcile tracks emissions across calls"] = function()
  stats.record_reconcile(1500, 3, 2)
  stats.record_reconcile(500, 3, 1)
  local s = stats.snapshot()
  eq(s.reconcile.count, 2)
  eq(s.reconcile.last_us, 0.5)
  eq(s.reconcile.min_us, 0.5)
  eq(s.reconcile.max_us, 1.5)
  eq(s.reconcile.mean_us, 1.0)
  eq(s.emissions, 3)
  eq(s.last_desired_count, 3)
end

T["stats"]["reset clears every bucket"] = function()
  stats.record_scan(1000, 4)
  stats.record_reconcile(500, 2, 1)
  stats.reset()
  local s = stats.snapshot()
  eq(s.scan.count, 0)
  eq(s.scan.max_us, 0)
  eq(s.reconcile.count, 0)
  eq(s.emissions, 0)
  eq(s.last_visible_count, 0)
  eq(s.last_desired_count, 0)
end

T["stats"]["min stays unchanged when subsequent samples are larger"] = function()
  stats.record_scan(1000, 1)
  stats.record_scan(5000, 1)
  stats.record_scan(3000, 1)
  local s = stats.snapshot()
  eq(s.scan.min_us, 1.0)
  eq(s.scan.max_us, 5.0)
end

return T
