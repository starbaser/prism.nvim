-- Floating slot/stat diagnostics.

local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

local registry
local debug
local slots
local stats

T["debug"] = new_set({
  hooks = {
    pre_case = function()
      package.loaded["prism"] = nil
      package.loaded["prism.registry"] = nil
      package.loaded["prism.slots"] = nil
      package.loaded["prism.stats"] = nil
      package.loaded["prism.terminal"] = {
        is_kitty = function() return true end,
        push = function() end,
        pop = function() end,
        set_slot = function() end,
        clear_slot = function() end,
      }
      package.loaded["prism.debug"] = nil
      registry = require("prism.registry")
      slots = require("prism.slots")
      stats = require("prism.stats")
      registry._reset()
      slots._reset()
      stats.reset()
      vim.api.nvim_set_hl(0, "Normal", { bg = 0x101010 })
      vim.api.nvim_set_hl(0, "PrismFloatA", { bg = 0x010101 })
      vim.api.nvim_set_hl(0, "PrismFloatLonger", { bg = 0x020202 })
      vim.api.nvim_set_hl(
        0,
        "PrismFloatLongestHighlightGroupNameWithEnoughCharactersToExceedStatsTable",
        { bg = 0x030303 }
      )
      debug = require("prism.debug")
    end,
    post_case = function()
      if debug then debug.close() end
    end,
  },
})

local function open_with_two_groups()
  local a = registry.register("PrismFloatA", 0.5)
  local b = registry.register("PrismFloatLonger", 0.5)
  slots.reconcile({ a, b })
  return debug.open()
end

local function prism_debug_windows()
  local wins = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "prism-debug" then
      wins[#wins + 1] = win
    end
  end
  return wins
end

T["debug"]["renders slot allocation in registration priority order"] = function()
  local win = open_with_two_groups()
  local buf = vim.api.nvim_win_get_buf(win)
  eq(vim.api.nvim_buf_get_lines(buf, 0, 2, false), {
    "1  [1 p=0] PrismFloatA",
    "2  [2 p=0] PrismFloatLonger",
  })
end

T["debug"]["sizes width to the longest rendered line"] = function()
  local win = open_with_two_groups()
  local buf = vim.api.nvim_win_get_buf(win)
  local width = 1
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  eq(vim.api.nvim_win_get_width(win), width)
end

T["debug"]["opens with wrapping disabled"] = function()
  local win = open_with_two_groups()
  eq(vim.wo[win].wrap, false)
end

T["debug"]["highlights each allocation line with the matching group"] = function()
  local win = open_with_two_groups()
  local buf = vim.api.nvim_win_get_buf(win)
  local ns = vim.api.nvim_get_namespaces().prism_debug_float
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  eq(marks[1][3], 11)
  eq(marks[1][4].hl_group, "PrismFloatA")
  eq(marks[2][3], 11)
  eq(marks[2][4].hl_group, "PrismFloatLonger")
end

T["debug"]["refresh resizes after a longer group is registered"] = function()
  local win = open_with_two_groups()
  registry.register(
    "PrismFloatLongestHighlightGroupNameWithEnoughCharactersToExceedStatsTable",
    0.5
  )
  debug.refresh()
  eq(
    vim.api.nvim_win_get_width(win),
    math.min(
      vim.fn.strdisplaywidth("-  [3 p=0] PrismFloatLongestHighlightGroupNameWithEnoughCharactersToExceedStatsTable"),
      vim.o.columns - 2
    )
  )
end

T["debug"]["renders stats as markdown tables below the allocation"] = function()
  local win = open_with_two_groups()
  local buf = vim.api.nvim_win_get_buf(win)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[3], "")
  eq(lines[4], "| metric | count | last_us | mean_us | min_us | max_us |")
  eq(lines[5], "| --- | ---: | ---: | ---: | ---: | ---: |")
  eq(lines[6], "| scan | 0 | 0.0 | 0.0 | 0.0 | 0.0 |")
  eq(lines[9], "| counter | value |")
end

T["debug"]["refresh interval updates stats without command arguments"] = function()
  local win = open_with_two_groups()
  local buf = vim.api.nvim_win_get_buf(win)

  debug.open({ refresh_interval_ms = 10 })
  stats.record_event(false)

  local ok = vim.wait(200, function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for _, line in ipairs(lines) do
      if line == "| events | 1 |" then
        return true
      end
    end
    return false
  end)
  eq(ok, true)
end

T["debug"]["open sweeps stale floats from a reloaded module"] = function()
  open_with_two_groups()
  eq(#prism_debug_windows(), 1)

  package.loaded["prism.debug"] = nil
  debug = require("prism.debug")
  debug.open()
  eq(#prism_debug_windows(), 1)

  debug.close()
  eq(#prism_debug_windows(), 0)
end

return T
