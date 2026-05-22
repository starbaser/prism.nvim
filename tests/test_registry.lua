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
      -- Normal needs a known bg for the no-bg-fallback path.
      vim.api.nvim_set_hl(0, "Normal", { bg = 0x808080 })
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

T["registry"]["register falls back to Normal.bg when group has no bg"] = function()
  local reg = registry.register("PrismTestNoBg", 0.5)
  eq(reg ~= nil, true)
  eq(reg.original_bg, 0x808080) -- Normal.bg
  eq(reg.nudged_bg, 0x808081)   -- Normal.bg + index 1
  -- And the group now has the nudged bg so its cells get keyed.
  local hl = vim.api.nvim_get_hl(0, { name = "PrismTestNoBg", link = false })
  eq(hl.bg, 0x808081)
end

T["registry"]["register skips when Normal also has no bg"] = function()
  vim.api.nvim_set_hl(0, "Normal", {})
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

T["registry"]["register rejects missing opacity"] = function()
  ---@diagnostic disable-next-line: missing-parameter
  local reg = registry.register("PrismTestA")
  eq(reg, nil)
  eq(#registry.all(), 0)
end

T["registry"]["register rejects non-number opacity"] = function()
  ---@diagnostic disable-next-line: param-type-mismatch
  local reg = registry.register("PrismTestA", "0.5")
  eq(reg, nil)
  eq(#registry.all(), 0)
end

T["registry"]["register_color rejects missing opacity"] = function()
  ---@diagnostic disable-next-line: missing-parameter
  local reg = registry.register_color(0xabc123)
  eq(reg, nil)
  eq(#registry.all(), 0)
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

T["registry"]["register_color stores raw value, no nudge, no hl mutation"] = function()
  local reg = registry.register_color(0xabc123, 0.5)
  eq(reg ~= nil, true)
  eq(reg.color_only, true)
  eq(reg.name, nil)
  eq(reg.original_bg, nil)
  eq(reg.nudged_bg, 0xabc123)
  eq(reg.opacity, 0.5)
end

T["registry"]["register_color accepts hex string"] = function()
  local reg = registry.register_color("#abc123", 0.5)
  eq(reg.nudged_bg, 0xabc123)
  local reg2 = registry.register_color("DEAD11", 0.5)
  eq(reg2.nudged_bg, 0xDEAD11)
end

T["registry"]["register_color rejects invalid input"] = function()
  eq(registry.register_color("not a color", 0.5), nil)
  eq(registry.register_color(-1, 0.5), nil)
  eq(registry.register_color(0x1000000, 0.5), nil)
  eq(#registry.all(), 0)
end

T["registry"]["register_color rejects collision with existing"] = function()
  registry.register_color(0xabc123, 0.5)
  local reg = registry.register_color(0xabc123, 0.3)
  eq(reg, nil)
  eq(#registry.all(), 1)
end

T["registry"]["group nudge skips around pre-registered colors"] = function()
  -- 0x000000 + 1 = 0x000001 would be the natural nudge for PrismTestA;
  -- reserving that slot first should force PrismTestA to 0x000002.
  registry.register_color(0x000001, 0.5)
  local reg = registry.register("PrismTestA", 0.4)
  eq(reg.nudged_bg, 0x000002)
end

T["registry"]["nudge does not carry across RGB channel boundaries"] = function()
  vim.api.nvim_set_hl(0, "PrismCyanEdge", { bg = 0x00ffff })
  vim.api.nvim_set_hl(0, "PrismBlueEdge", { bg = 0x0000ff })
  vim.api.nvim_set_hl(0, "PrismWhiteEdge", { bg = 0xffffff })

  local cyan = registry.register("PrismCyanEdge", 0.5)
  local blue = registry.register("PrismBlueEdge", 0.5)
  local white = registry.register("PrismWhiteEdge", 0.5)

  eq(cyan.nudged_bg, 0x00fffe)
  eq(blue.nudged_bg, 0x0000fd)
  eq(white.nudged_bg, 0xfffffc)
end

T["registry"]["rebuild_color_index maps bg -> group names"] = function()
  vim.api.nvim_set_hl(0, "PrismIdxA", { bg = 0xdeadbe })
  vim.api.nvim_set_hl(0, "PrismIdxB", { bg = 0xdeadbe })
  registry.register_color(0xdeadbe, 0.5)
  registry.rebuild_color_index()
  -- Both groups match; visibility of either should slot the color.
  local got = registry.filter_visible({ PrismIdxA = true })
  eq(#got, 1)
  eq(got[1].color_only, true)
end

T["registry"]["filter_visible excludes color with no matching group visible"] = function()
  vim.api.nvim_set_hl(0, "PrismIdxC", { bg = 0xbeefca })
  registry.register_color(0xbeefca, 0.5)
  registry.rebuild_color_index()
  local got = registry.filter_visible({})
  eq(#got, 0)
end

T["registry"]["filter_visible excludes color with no group having that bg"] = function()
  registry.register_color(0xffaa00, 0.5)
  registry.rebuild_color_index()
  local got = registry.filter_visible({ AnyOtherName = true })
  eq(#got, 0)
end

T["registry"]["filter_visible interleaves groups and colors by registration order"] = function()
  vim.api.nvim_set_hl(0, "PrismMix", { bg = 0xc0ffee })
  registry.register("PrismTestA", 0.4)       -- index 1, name-gated
  registry.register_color(0xc0ffee, 0.3)     -- index 2, color-gated via PrismMix
  registry.register("PrismTestC", 0.2)       -- index 3, name-gated
  registry.rebuild_color_index()
  local got = registry.filter_visible({
    PrismTestA = true,
    PrismMix = true,
    PrismTestC = true,
  })
  eq(#got, 3)
  eq(got[1].name, "PrismTestA")
  eq(got[2].color_only, true)
  eq(got[2].nudged_bg, 0xc0ffee)
  eq(got[3].name, "PrismTestC")
end

T["registry"]["unregister removes a color-only registration"] = function()
  registry.register_color(0xabc123, 0.5)
  registry.register("PrismTestA", 0.4)
  registry.unregister("#abc123")
  eq(#registry.all(), 1)
  eq(registry.all()[1].name, "PrismTestA")
  eq(registry.all()[1].index, 1)
end

T["registry"]["on_colorscheme preserves color-only registrations verbatim"] = function()
  registry.register_color(0xabc123, 0.5)
  registry.register("PrismTestA", 0.4)
  registry.on_colorscheme()
  local all = registry.all()
  eq(#all, 2)
  eq(all[1].color_only, true)
  eq(all[1].nudged_bg, 0xabc123)
  eq(all[2].name, "PrismTestA")
end

return T
