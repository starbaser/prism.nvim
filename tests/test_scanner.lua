-- Visibility detection: synthetic buffers + extmarks → expected hl_group set.

local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

local scanner

T["scanner"] = new_set({
  hooks = {
    pre_case = function()
      package.loaded["prism.scanner"] = nil
      scanner = require("prism.scanner")
      vim.api.nvim_set_hl(0, "PrismScanAlpha", { bg = 0x010101 })
      vim.api.nvim_set_hl(0, "PrismScanBeta", { bg = 0x020202 })
      vim.api.nvim_set_hl(0, "PrismScanGamma", { bg = 0x030303 })
    end,
  },
})

local function setup_window(lines)
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  -- Force redraw so w0/w$ are accurate.
  vim.cmd("redraw")
  return buf
end

T["scanner"]["detects an extmark hl_group on the visible range"] = function()
  local buf = setup_window({ "hello world", "second line" })
  local ns = vim.api.nvim_create_namespace("prism_test")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    end_row = 0,
    end_col = 5,
    hl_group = "PrismScanAlpha",
  })
  local seen = scanner.collect_visible()
  eq(seen["PrismScanAlpha"], true)
end

T["scanner"]["misses a hl_group with no extmark / syntax / treesitter"] = function()
  setup_window({ "hello world" })
  local seen = scanner.collect_visible()
  eq(seen["PrismScanBeta"], nil)
end

T["scanner"]["picks up multiple distinct extmark groups"] = function()
  local buf = setup_window({ "alpha beta gamma" })
  local ns = vim.api.nvim_create_namespace("prism_test_multi")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    end_row = 0, end_col = 5, hl_group = "PrismScanAlpha",
  })
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 6, {
    end_row = 0, end_col = 10, hl_group = "PrismScanBeta",
  })
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 11, {
    end_row = 0, end_col = 16, hl_group = "PrismScanGamma",
  })
  local seen = scanner.collect_visible()
  eq(seen["PrismScanAlpha"], true)
  eq(seen["PrismScanBeta"], true)
  eq(seen["PrismScanGamma"], true)
end

T["scanner"]["scan_step skips columns"] = function()
  local buf = setup_window({ string.rep("x", 40) })
  local ns = vim.api.nvim_create_namespace("prism_test_step")
  -- One-column extmark at col 5.
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 5, {
    end_row = 0, end_col = 6, hl_group = "PrismScanAlpha",
  })
  scanner.scan_step = 10
  local seen = scanner.collect_visible()
  -- Sampling at cols 0, 10, 20, 30 misses col 5.
  eq(seen["PrismScanAlpha"], nil)
  scanner.scan_step = 1
  seen = scanner.collect_visible()
  eq(seen["PrismScanAlpha"], true)
end

return T
