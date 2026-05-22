--- prism.signals: User autocmd names shared by UI integrations.

local M = {}

M.SLOTS_CHANGED = "PrismSlotsChanged"
M.REGISTRY_CHANGED = "PrismRegistryChanged"

---@param pattern string
function M.emit(pattern)
  vim.api.nvim_exec_autocmds("User", {
    pattern = pattern,
    modeline = false,
  })
end

return M
