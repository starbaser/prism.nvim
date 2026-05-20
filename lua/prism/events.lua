--- prism.events: debounced autocommand wiring that drives the slot reconciler.

local registry = require("prism.registry")
local scanner = require("prism.scanner")
local slots = require("prism.slots")
local terminal = require("prism.terminal")

local M = {}

local AUGROUP = "prism"
M.debounce_ms = 50

---@type uv.uv_timer_t?
local timer = nil

local function do_refresh()
  local visible = scanner.collect_visible()
  local desired = registry.filter_visible(visible)
  slots.reconcile(desired)
end

--- Coalesce many events into a single refresh after `debounce_ms` idle.
function M.schedule_refresh()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  local t = vim.uv.new_timer()
  if not t then
    do_refresh()
    return
  end
  timer = t
  t:start(M.debounce_ms, 0, vim.schedule_wrap(function()
    if timer then
      timer:close()
      timer = nil
    end
    do_refresh()
  end))
end

local REFRESH_EVENTS = {
  "WinScrolled",
  "WinResized",
  "BufWinEnter",
  "WinEnter",
  "TextChanged",
  "TextChangedI",
  "ModeChanged",
  "TabEnter",
}

---@param opts { debounce_ms: integer, scan_step: integer }
function M.attach(opts)
  M.debounce_ms = opts.debounce_ms
  scanner.scan_step = opts.scan_step

  vim.api.nvim_create_augroup(AUGROUP, { clear = true })

  for _, ev in ipairs(REFRESH_EVENTS) do
    vim.api.nvim_create_autocmd(ev, {
      group = AUGROUP,
      callback = M.schedule_refresh,
    })
  end

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = AUGROUP,
    callback = function()
      registry.on_colorscheme()
      M.schedule_refresh()
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = AUGROUP,
    callback = function()
      terminal.pop()
    end,
  })
end

--- Tear down autocommands. Used by :PrismDisable.
function M.detach()
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

return M
