--- lualine component for Prism's live kitty slot iconbar.

local Component = require("lualine.component")
local renderer = require("prism.lualine")
local signals = require("prism.signals")

local M = Component:extend()

local instances = setmetatable({}, { __mode = "v" })
local autocmds_attached = false
local refresh_pending = false

local component_defaults = vim.tbl_extend("force", renderer.default_options(), {
  padding = 0,
})

local function schedule_lualine_refresh()
  if refresh_pending then return end
  refresh_pending = true
  vim.schedule(function()
    refresh_pending = false
    local ok, lualine = pcall(require, "lualine")
    if ok and type(lualine.refresh) == "function" then
      pcall(lualine.refresh, {
        place = { "statusline", "winbar", "tabline" },
        trigger = "autocmd",
      })
    end
  end)
end

local function invalidate_instances()
  for _, instance in pairs(instances) do
    instance._prism_status = nil
  end
  schedule_lualine_refresh()
end

local function attach_autocmds()
  if autocmds_attached then return end
  autocmds_attached = true

  local group = vim.api.nvim_create_augroup("prism_lualine", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { signals.SLOTS_CHANGED, signals.REGISTRY_CHANGED },
    callback = invalidate_instances,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = invalidate_instances,
  })
end

local function toggle_debug()
  pcall(vim.cmd, "PrismDebug")
end

---@param options table
function M:init(options)
  options = vim.tbl_extend("keep", options or {}, component_defaults)
  if options.on_click == nil then
    options.on_click = toggle_debug
  end

  M.super.init(self, options)
  self.options = vim.tbl_extend("keep", self.options or {}, component_defaults)
  instances[self.component_no] = self
  attach_autocmds()
end

function M:update_status()
  if not self._prism_status then
    self._prism_status = renderer.render(self.options)
  end
  return self._prism_status
end

return M
