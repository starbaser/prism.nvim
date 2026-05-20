-- Registration, bg-nudge, and ColorScheme replay behaviour.

local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

local registry

T["registry"] = new_set({
  hooks = {
    pre_case = function()
      package.loaded["prism.registry"] = nil
      registry = require("prism.registry")
      registry._reset()
      -- Define synthetic hl groups with known bg values.
      vim.api.nvim_set_hl(0, "PrismTestA", { bg = 0x000000 })
      vim.api.nvim_set_hl(0, "PrismTestB", { bg = 0x000000 })
      vim.api.nvim_set_hl(0, "PrismTestC", { bg = 0xff0000, fg = 0xffffff, bold = true })
      vim.api.nvim_set_hl(0, "PrismTestNoBg", { fg = 0xffffff })
    end,
  },
})

T["registry"]["register applies a nudged bg"] = function()
  local reg = registry.register("PrismTestA", 0.5)
  eq(reg ~= nil, true)
  eq(reg.name, "PrismTestA")
  eq(reg.opacity, 0.5)
  eq(reg.index, 1)
  eq(reg.original_bg, 0x000000)
  -- First registration: nudge to original + 1 = 0x000001
  eq(reg.nudged_bg, 0x000001)
  local hl = vim.api.nvim_get_hl(0, { name = "PrismTestA", link = false })
  eq(hl.bg, 0x000001)
end

T["registry"]["two registrations on identical bg get distinct nudges"] = function()
  local r1 = registry.register("PrismTestA", 0.4)
  local r2 = registry.register("PrismTestB", 0.4)
  eq(r1.nudged_bg ~= r2.nudged_bg, true)
end

T["registry"]["register preserves fg, bold, and other attrs"] = function()
  registry.register("PrismTestC", 0.3)
  local hl = vim.api.nvim_get_hl(0, { name = "PrismTestC", link = false })
  eq(hl.fg, 0xffffff)
  eq(hl.bold, true)
  eq(hl.bg, 0xff0001)
end

T["registry"]["register skips groups with no bg"] = function()
  local reg = registry.register("PrismTestNoBg", 0.5)
  eq(reg, nil)
  eq(#registry.all(), 0)
end

T["registry"]["double registration is a no-op"] = function()
  registry.register("PrismTestA", 0.4)
  registry.register("PrismTestA", 0.9)
  eq(#registry.all(), 1)
  eq(registry.get("PrismTestA").opacity, 0.4)
end

T["registry"]["unregister restores original bg"] = function()
  registry.register("PrismTestA", 0.5)
  registry.unregister("PrismTestA")
  local hl = vim.api.nvim_get_hl(0, { name = "PrismTestA", link = false })
  eq(hl.bg, 0x000000)
  eq(#registry.all(), 0)
  eq(registry.get("PrismTestA"), nil)
end

T["registry"]["unregister reindexes remaining"] = function()
  registry.register("PrismTestA", 0.5)
  registry.register("PrismTestC", 0.4)
  registry.unregister("PrismTestA")
  eq(#registry.all(), 1)
  eq(registry.get("PrismTestC").index, 1)
end

T["registry"]["on_colorscheme re-nudges after upstream reset"] = function()
  registry.register("PrismTestA", 0.5)
  -- Simulate a colorscheme rewriting the bg back to a clean value.
  vim.api.nvim_set_hl(0, "PrismTestA", { bg = 0x123456 })
  registry.on_colorscheme()
  local hl = vim.api.nvim_get_hl(0, { name = "PrismTestA", link = false })
  -- New original is 0x123456, +1 = 0x123457
  eq(hl.bg, 0x123457)
  eq(registry.get("PrismTestA").original_bg, 0x123456)
  eq(registry.get("PrismTestA").nudged_bg, 0x123457)
end

T["registry"]["filter_visible preserves registration order"] = function()
  registry.register("PrismTestA", 0.4)
  registry.register("PrismTestB", 0.4)
  registry.register("PrismTestC", 0.4)
  local visible = { PrismTestC = true, PrismTestA = true }
  local got = registry.filter_visible(visible)
  eq(#got, 2)
  eq(got[1].name, "PrismTestA")
  eq(got[2].name, "PrismTestC")
end

return T
