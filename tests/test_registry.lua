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
  eq(reg.kind, "group")
  eq(reg.target, "PrismTestA")
  eq(reg.group, "PrismTestA")
  eq(reg.opacity, 0.5)
  eq(reg.priority, 0)
  eq(reg.index, 1)
  eq(reg.original_bg, 0x000000)
  -- First registration: nudge to original + 1 = 0x000001
  eq(reg.nudged_bg, 0x000001)
  local hl = vim.api.nvim_get_hl(0, { name = "PrismTestA", link = false })
  eq(hl.bg, 0x000001)
end

T["registry"]["two registrations on identical bg and opacity share a nudge"] = function()
  local r1 = registry.register("PrismTestA", 0.4)
  local r2 = registry.register("PrismTestB", 0.4)
  eq(r1.nudged_bg, 0x000001)
  eq(r2.nudged_bg, 0x000001)
end

T["registry"]["two registrations on identical bg and different opacity get distinct nudges"] = function()
  local r1 = registry.register("PrismTestA", 0.4)
  local r2 = registry.register("PrismTestB", 0.5)
  eq(r1.nudged_bg, 0x000001)
  eq(r2.nudged_bg, 0x000002)
end

T["registry"]["unrelated earlier registrations do not increase nudge distance"] = function()
  vim.api.nvim_set_hl(0, "PrismFarA", { bg = 0x101010 })
  vim.api.nvim_set_hl(0, "PrismFarB", { bg = 0x202020 })
  vim.api.nvim_set_hl(0, "PrismFarC", { bg = 0x202020 })

  local a = registry.register("PrismFarA", 0.4)
  local b = registry.register("PrismFarB", 0.4)
  local c = registry.register("PrismFarC", 0.4)

  eq(a.nudged_bg, 0x101011)
  eq(b.nudged_bg, 0x202021)
  eq(c.nudged_bg, 0x202021)
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
  eq(reg.nudged_bg, 0x808081)   -- Normal.bg + 1
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

T["registry"]["repeated group registration updates in place"] = function()
  local first = registry.register("PrismTestA", 0.4)
  local second = registry.register("PrismTestA", 0.9)
  eq(first, second)
  eq(#registry.all(), 1)
  eq(registry.get("PrismTestA").opacity, 0.9)
  eq(registry.get("PrismTestA").original_bg, 0x000000)
  eq(registry.get("PrismTestA").nudged_bg, 0x000001)
end

T["registry"]["priority update reorders without appending"] = function()
  registry.register("PrismTestA", 0.4)
  registry.register("PrismTestC", 0.5, 10)
  eq(registry.all()[1].group, "PrismTestC")
  eq(registry.all()[2].group, "PrismTestA")

  registry.register("PrismTestA", 0.4, 20)
  eq(#registry.all(), 2)
  eq(registry.all()[1].group, "PrismTestA")
  eq(registry.all()[1].priority, 20)
  eq(registry.all()[2].group, "PrismTestC")
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

T["registry"]["register rejects non-number priority"] = function()
  ---@diagnostic disable-next-line: param-type-mismatch
  local reg = registry.register("PrismTestA", 0.5, "high")
  eq(reg, nil)
  eq(#registry.all(), 0)
end

T["registry"]["register rejects invalid numeric color target"] = function()
  eq(registry.register(-1, 0.5), nil)
  eq(registry.register(0x1000000, 0.5), nil)
  eq(#registry.all(), 0)
end

T["registry"]["register parses raw colors from numbers and hex strings"] = function()
  local reg = registry.register("#abc123", 0.5)
  eq(reg.kind, "color")
  eq(reg.color, 0xabc123)
  eq(reg.target, "#abc123")

  local reg2 = registry.register("DEAD11", 0.5)
  eq(reg2.kind, "color")
  eq(reg2.color, 0xDEAD11)

  local reg3 = registry.register(0x000001, 0.5)
  eq(reg3.kind, "color")
  eq(reg3.target, "#000001")
end

T["registry"]["non-hex strings are highlight group targets"] = function()
  local reg = registry.register("PrismNotAColor", 0.5)
  eq(reg.kind, "group")
  eq(reg.group, "PrismNotAColor")
  eq(reg.original_bg, 0x808080)
end

T["registry"]["repeated raw color registration updates in place"] = function()
  local first = registry.register(0xabc123, 0.5)
  local second = registry.register("#abc123", 0.3, 40)
  eq(first, second)
  eq(#registry.all(), 1)
  eq(second.opacity, 0.3)
  eq(second.priority, 40)
  eq(second.nudged_bg, 0xabc123)
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
  registry.register("PrismTestA", 0.5, 20)
  registry.register("PrismTestC", 0.4, 10)
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

T["registry"]["filter_visible sorts by priority then first registration order"] = function()
  registry.register("PrismTestA", 0.4)
  registry.register("PrismTestB", 0.5, 10)
  registry.register("PrismTestC", 0.4, 10)
  local visible = { PrismTestC = true, PrismTestA = true, PrismTestB = true }
  local got = registry.filter_visible(visible)
  eq(#got, 3)
  eq(got[1].group, "PrismTestB")
  eq(got[2].group, "PrismTestC")
  eq(got[3].group, "PrismTestA")
end

T["registry"]["filter_visible collapses shared color slots"] = function()
  registry.register("PrismTestA", 0.4)
  registry.register("PrismTestB", 0.4)
  local got = registry.filter_visible({ PrismTestA = true, PrismTestB = true })
  eq(#got, 1)
  eq(got[1].group, "PrismTestA")
end

T["registry"]["filter_visible includes a shared slot when only a later group is visible"] = function()
  registry.register("PrismTestA", 0.4)
  registry.register("PrismTestB", 0.4)
  local got = registry.filter_visible({ PrismTestB = true })
  eq(#got, 1)
  eq(got[1].group, "PrismTestB")
  eq(got[1].nudged_bg, 0x000001)
end

T["registry"]["raw color stores exact value with no hl mutation"] = function()
  local before = vim.api.nvim_get_hl(0, { name = "PrismTestA", link = false }).bg
  local reg = registry.register(0xabc123, 0.5)
  eq(reg ~= nil, true)
  eq(reg.kind, "color")
  eq(reg.group, nil)
  eq(reg.original_bg, nil)
  eq(reg.nudged_bg, 0xabc123)
  eq(reg.opacity, 0.5)
  eq(vim.api.nvim_get_hl(0, { name = "PrismTestA", link = false }).bg, before)
end

T["registry"]["group nudge skips around pre-registered colors with different opacity"] = function()
  -- 0x000000 + 1 = 0x000001 would be the natural nudge for PrismTestA;
  -- reserving that slot at another opacity should force PrismTestA to 0x000002.
  registry.register(0x000001, 0.5)
  local reg = registry.register("PrismTestA", 0.4)
  eq(reg.nudged_bg, 0x000002)
end

T["registry"]["group can share a pre-registered raw color with matching opacity"] = function()
  registry.register(0x000001, 0.4)
  local reg = registry.register("PrismTestA", 0.4)
  eq(reg.nudged_bg, 0x000001)
end

T["registry"]["raw color update can force existing group nudge to move"] = function()
  local group = registry.register("PrismTestA", 0.4)
  eq(group.nudged_bg, 0x000001)

  local raw = registry.register(0x000001, 0.5)
  eq(raw.nudged_bg, 0x000001)
  eq(group.nudged_bg, 0x000002)
end

T["registry"]["raw color update can share existing group nudge with matching opacity"] = function()
  local group = registry.register("PrismTestA", 0.4)
  local raw = registry.register(0x000001, 0.4)
  eq(group.nudged_bg, 0x000001)
  eq(raw.nudged_bg, 0x000001)
end

T["registry"]["nudge does not carry across RGB channel boundaries"] = function()
  vim.api.nvim_set_hl(0, "PrismCyanEdge", { bg = 0x00ffff })
  vim.api.nvim_set_hl(0, "PrismBlueEdge", { bg = 0x0000ff })
  vim.api.nvim_set_hl(0, "PrismWhiteEdge", { bg = 0xffffff })

  local cyan = registry.register("PrismCyanEdge", 0.5)
  local blue = registry.register("PrismBlueEdge", 0.5)
  local white = registry.register("PrismWhiteEdge", 0.5)

  eq(cyan.nudged_bg, 0x00fffe)
  eq(blue.nudged_bg, 0x0000fe)
  eq(white.nudged_bg, 0xfffffe)
end

T["registry"]["rebuild_color_index maps bg -> group names"] = function()
  vim.api.nvim_set_hl(0, "PrismIdxA", { bg = 0xdeadbe })
  vim.api.nvim_set_hl(0, "PrismIdxB", { bg = 0xdeadbe })
  registry.register(0xdeadbe, 0.5)
  registry.rebuild_color_index()
  -- Both groups match; visibility of either should slot the color.
  local got = registry.filter_visible({ PrismIdxA = true })
  eq(#got, 1)
  eq(got[1].kind, "color")
end

T["registry"]["visibility_targets includes registered groups and color matches"] = function()
  vim.api.nvim_set_hl(0, "PrismIdxA", { bg = 0xdeadbe })
  vim.api.nvim_set_hl(0, "PrismIdxB", { bg = 0xdeadbe })
  registry.register("PrismTestA", 0.4)
  registry.register(0xdeadbe, 0.5)
  registry.rebuild_color_index()

  local targets = registry.visibility_targets()
  eq(targets.PrismTestA, true)
  eq(targets.PrismIdxA, true)
  eq(targets.PrismIdxB, true)
end

T["registry"]["filter_visible can cap at slot count"] = function()
  for i = 1, 9 do
    local name = "PrismCap" .. i
    vim.api.nvim_set_hl(0, name, { bg = 0x100000 + i })
    registry.register(name, 0.5)
  end
  local visible = {}
  for _, r in ipairs(registry.all()) do
    visible[r.group] = true
  end
  eq(#registry.filter_visible(visible, 7), 7)
end

T["registry"]["filter_visible excludes color with no matching group visible"] = function()
  vim.api.nvim_set_hl(0, "PrismIdxC", { bg = 0xbeefca })
  registry.register(0xbeefca, 0.5)
  registry.rebuild_color_index()
  local got = registry.filter_visible({})
  eq(#got, 0)
end

T["registry"]["filter_visible excludes color with no group having that bg"] = function()
  registry.register(0xffaa00, 0.5)
  registry.rebuild_color_index()
  local got = registry.filter_visible({ AnyOtherName = true })
  eq(#got, 0)
end

T["registry"]["filter_visible interleaves groups and colors by priority"] = function()
  vim.api.nvim_set_hl(0, "PrismMix", { bg = 0xc0ffee })
  registry.register("PrismTestA", 0.4)       -- sequence 1, name-gated
  registry.register(0xc0ffee, 0.3, 20)       -- highest priority, color-gated via PrismMix
  registry.register("PrismTestC", 0.2, 10)   -- middle priority, name-gated
  registry.rebuild_color_index()
  local got = registry.filter_visible({
    PrismTestA = true,
    PrismMix = true,
    PrismTestC = true,
  })
  eq(#got, 3)
  eq(got[1].kind, "color")
  eq(got[1].nudged_bg, 0xc0ffee)
  eq(got[2].group, "PrismTestC")
  eq(got[3].group, "PrismTestA")
end

T["registry"]["unregister removes a raw color registration"] = function()
  registry.register(0xabc123, 0.5)
  registry.register("PrismTestA", 0.4)
  registry.unregister("#abc123")
  eq(#registry.all(), 1)
  eq(registry.all()[1].group, "PrismTestA")
  eq(registry.all()[1].index, 1)
end

T["registry"]["on_colorscheme preserves raw registrations and priority"] = function()
  registry.register(0xabc123, 0.5, 20)
  registry.register("PrismTestA", 0.4, 10)
  registry.on_colorscheme()
  local all = registry.all()
  eq(#all, 2)
  eq(all[1].kind, "color")
  eq(all[1].nudged_bg, 0xabc123)
  eq(all[1].priority, 20)
  eq(all[2].group, "PrismTestA")
  eq(all[2].priority, 10)
end

return T
