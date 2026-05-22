-- Lualine statusline rendering for Prism slot state.

local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

local renderer

T["lualine"] = new_set({
  hooks = {
    pre_case = function()
      package.loaded["prism.lualine"] = nil
      renderer = require("prism.lualine")
      vim.api.nvim_set_hl(0, "PrismLineA", { fg = 0x123456 })
    end,
  },
})

local function count_plain(text, needle)
  local count = 0
  local start = 1
  while true do
    local at = text:find(needle, start, true)
    if not at then return count end
    count = count + 1
    start = at + #needle
  end
end

local function reg(name, bg)
  return {
    name = name,
    index = 1,
    nudged_bg = bg,
    opacity = 0.5,
    color_only = name == nil,
  }
end

T["lualine"]["renders seven empty placeholders by default"] = function()
  local got = renderer.render({}, { slots = {} })
  eq(count_plain(got, "·"), 7)
  eq(got:find("%#PrismSlotEmpty#·", 1, true) ~= nil, true)
end

T["lualine"]["renders a named slot with its highlight group"] = function()
  local got = renderer.render({}, {
    slots = {
      [1] = reg("PrismLineA", 0x123456),
    },
  })
  eq(got:find("%#PrismLineA#󰜌 ", 1, true) ~= nil, true)
  eq(count_plain(got, "󰜌"), 1)
  eq(count_plain(got, "·"), 6)
end

T["lualine"]["renders color-only slots with deterministic color highlights"] = function()
  local got = renderer.render({}, {
    slots = {
      [1] = reg(nil, 0xabc123),
    },
  })
  eq(got:find("%#PrismSlotColor_abc123#󰜌 ", 1, true) ~= nil, true)
  local hl = vim.api.nvim_get_hl(0, { name = "PrismSlotColor_abc123", link = false })
  eq(hl.fg, 0xabc123)
end

T["lualine"]["uses configured icons and separators"] = function()
  local got = renderer.render({
    slot_icon = "X",
    empty_icon = "-",
    slot_separator = "|",
  }, {
    slots = {
      [1] = reg("PrismLineA", 0x123456),
    },
  })
  eq(got:find("%#PrismLineA#X|%#PrismSlotEmpty#-", 1, true) ~= nil, true)
end

T["lualine"]["caps overflow slot state at seven rendered positions"] = function()
  local state = { slots = {} }
  for i = 1, 20 do
    local name = "PrismLineOverflow" .. i
    vim.api.nvim_set_hl(0, name, { fg = 0x100000 + i })
    state.slots[i] = reg(name, 0x100000 + i)
  end

  local got = renderer.render({}, state)
  eq(count_plain(got, "󰜌"), 7)
  eq(got:find("PrismLineOverflow8", 1, true), nil)
end

return T
