-- Floating registered-highlight-group list.

local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

local registry
local groups

T["groups"] = new_set({
  hooks = {
    pre_case = function()
      package.loaded["prism"] = nil
      package.loaded["prism.registry"] = nil
      package.loaded["prism.ui.groups"] = nil
      registry = require("prism.registry")
      registry._reset()
      vim.api.nvim_set_hl(0, "Normal", { bg = 0x101010 })
      vim.api.nvim_set_hl(0, "PrismFloatA", { bg = 0x010101 })
      vim.api.nvim_set_hl(0, "PrismFloatLonger", { bg = 0x020202 })
      vim.api.nvim_set_hl(0, "PrismFloatLongestName", { bg = 0x030303 })
      groups = require("prism.ui.groups")
    end,
    post_case = function()
      if groups then groups.close() end
    end,
  },
})

local function open_with_two_groups()
  registry.register("PrismFloatA", 0.5)
  registry.register("PrismFloatLonger", 0.5)
  return groups.open()
end

local function prism_group_windows()
  local wins = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "prism-groups" then
      wins[#wins + 1] = win
    end
  end
  return wins
end

T["groups"]["renders registered group names in priority order"] = function()
  local win = open_with_two_groups()
  local buf = vim.api.nvim_win_get_buf(win)
  eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), {
    "PrismFloatA",
    "PrismFloatLonger",
  })
end

T["groups"]["sizes width to the longest registered group name"] = function()
  local win = open_with_two_groups()
  eq(vim.api.nvim_win_get_width(win), vim.fn.strdisplaywidth("PrismFloatLonger"))
end

T["groups"]["opens with wrapping disabled"] = function()
  local win = open_with_two_groups()
  eq(vim.wo[win].wrap, false)
end

T["groups"]["highlights each line with the matching group"] = function()
  local win = open_with_two_groups()
  local buf = vim.api.nvim_win_get_buf(win)
  local ns = vim.api.nvim_get_namespaces().prism_groups_float
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  eq(marks[1][4].hl_group, "PrismFloatA")
  eq(marks[2][4].hl_group, "PrismFloatLonger")
end

T["groups"]["refresh resizes after a longer group is registered"] = function()
  local win = open_with_two_groups()
  registry.register("PrismFloatLongestName", 0.5)
  groups.refresh()
  eq(vim.api.nvim_win_get_width(win), vim.fn.strdisplaywidth("PrismFloatLongestName"))
end

T["groups"]["open sweeps stale floats from a reloaded module"] = function()
  open_with_two_groups()
  eq(#prism_group_windows(), 1)

  package.loaded["prism.ui.groups"] = nil
  groups = require("prism.ui.groups")
  groups.open()
  eq(#prism_group_windows(), 1)

  groups.close()
  eq(#prism_group_windows(), 0)
end

return T
