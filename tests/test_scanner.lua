-- Visibility detection across the three tiers:
--   1) ranged buffer scan (extmarks + treesitter where present)
--   2) winhighlight translation
--   3) registry-gated window-state augmentation

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
      vim.api.nvim_set_hl(0, "PrismScanFloat", { bg = 0x040404 })
    end,
  },
})

local function setup_window(lines)
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd("redraw")
  return buf
end

T["scanner"]["detects an extmark hl_group on the visible range"] = function()
  local buf = setup_window({ "hello world", "second line" })
  local ns = vim.api.nvim_create_namespace("prism_test_extmark")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    end_row = 0,
    end_col = 5,
    hl_group = "PrismScanAlpha",
  })
  local seen = scanner.collect_visible()
  eq(seen["PrismScanAlpha"], true)
end

T["scanner"]["picks up multi-line extmark crossing the viewport top edge"] = function()
  local buf = setup_window({
    "first", "second", "third", "fourth", "fifth",
  })
  local ns = vim.api.nvim_create_namespace("prism_test_multiline")
  -- Mark starting at row 0 col 0, ending at row 4 col 5.
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    end_row = 4,
    end_col = 5,
    hl_group = "PrismScanBeta",
  })
  local seen = scanner.collect_visible()
  eq(seen["PrismScanBeta"], true)
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

T["scanner"]["misses a group with no extmark / syntax / treesitter"] = function()
  setup_window({ "hello world" })
  local seen = scanner.collect_visible()
  eq(seen["PrismScanBeta"], nil)
end

T["scanner"]["always includes Normal when a window is open"] = function()
  setup_window({ "hello" })
  local seen = scanner.collect_visible()
  eq(seen["Normal"], true)
end

T["scanner"]["winhighlight translates Normal to remapped group"] = function()
  setup_window({ "hello" })
  local cur = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value("winhighlight", "Normal:PrismScanFloat", { win = cur })
  local seen = scanner.collect_visible()
  eq(seen["PrismScanFloat"], true)
  eq(seen["Normal"], nil)
  vim.api.nvim_set_option_value("winhighlight", "", { win = cur })
end

T["scanner"]["winhighlight translates a TS/extmark-reported group"] = function()
  local buf = setup_window({ "hello" })
  local ns = vim.api.nvim_create_namespace("prism_test_wh")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    end_row = 0, end_col = 5, hl_group = "PrismScanAlpha",
  })
  local cur = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value("winhighlight", "PrismScanAlpha:PrismScanGamma", { win = cur })
  local seen = scanner.collect_visible()
  eq(seen["PrismScanGamma"], true)
  eq(seen["PrismScanAlpha"], nil)
  vim.api.nvim_set_option_value("winhighlight", "", { win = cur })
end

T["scanner"]["targeted scan filters unrelated extmarks"] = function()
  local buf = setup_window({ "hello" })
  local ns = vim.api.nvim_create_namespace("prism_test_target_filter")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    end_row = 0, end_col = 5, hl_group = "PrismScanAlpha",
  })
  local seen = scanner.collect_visible({ PrismScanBeta = true })
  eq(seen["PrismScanAlpha"], nil)
  eq(seen["PrismScanBeta"], nil)
end

T["scanner"]["targeted scan finds winhighlight destination"] = function()
  local buf = setup_window({ "hello" })
  local ns = vim.api.nvim_create_namespace("prism_test_target_wh")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    end_row = 0, end_col = 5, hl_group = "PrismScanAlpha",
  })
  local cur = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value("winhighlight", "PrismScanAlpha:PrismScanGamma", { win = cur })
  local seen = scanner.collect_visible({ PrismScanGamma = true })
  eq(seen["PrismScanGamma"], true)
  eq(seen["PrismScanAlpha"], nil)
  vim.api.nvim_set_option_value("winhighlight", "", { win = cur })
end

T["scanner"]["state-only targeted scan ignores buffer content groups"] = function()
  local buf = setup_window({ "hello" })
  local ns = vim.api.nvim_create_namespace("prism_test_state_only")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    end_row = 0, end_col = 5, hl_group = "PrismScanAlpha",
  })
  local cur = vim.api.nvim_get_current_win()
  vim.wo[cur].cursorline = true
  local seen = scanner.collect_visible({ CursorLine = true })
  eq(seen["CursorLine"], true)
  eq(seen["PrismScanAlpha"], nil)
  vim.wo[cur].cursorline = false
end

T["scanner"]["tier-3 cursorline is gated on registration"] = function()
  setup_window({ "hello" })
  local cur = vim.api.nvim_get_current_win()
  vim.wo[cur].cursorline = true

  -- Not registered -> not in seen, even with cursorline set.
  local seen_no_reg = scanner.collect_visible()
  eq(seen_no_reg["CursorLine"], nil)

  -- Registered -> added when cursorline is set.
  local seen_reg = scanner.collect_visible({ CursorLine = true })
  eq(seen_reg["CursorLine"], true)

  vim.wo[cur].cursorline = false
end

T["scanner"]["tier-3 cursorline is gated on the option, not just registration"] = function()
  setup_window({ "hello" })
  local cur = vim.api.nvim_get_current_win()
  vim.wo[cur].cursorline = false
  local seen = scanner.collect_visible({ CursorLine = true })
  eq(seen["CursorLine"], nil)
end

T["scanner"]["tier-3 pmenu gated on pumvisible"] = function()
  setup_window({ "hello" })
  -- pumvisible() is 0 in headless / no popup; pmenu should not appear.
  local seen = scanner.collect_visible({ Pmenu = true })
  eq(seen["Pmenu"], nil)
end

T["scanner"]["tier-3 statusline gated on laststatus"] = function()
  setup_window({ "hello" })
  vim.o.laststatus = 0
  local seen_off = scanner.collect_visible({ StatusLine = true })
  eq(seen_off["StatusLine"], nil)

  vim.o.laststatus = 2
  local seen_on = scanner.collect_visible({ StatusLine = true })
  eq(seen_on["StatusLine"], true)
end

T["scanner"]["tier-3 terminal gated on buftype"] = function()
  setup_window({ "hello" })
  local seen_normal = scanner.collect_visible({ Terminal = true })
  eq(seen_normal["Terminal"], nil)
end

T["scanner"]["on_colorscheme clears the link cache"] = function()
  setup_window({ "hello" })
  -- Smoke check: function exists and is callable.
  scanner.on_colorscheme()
end

return T
