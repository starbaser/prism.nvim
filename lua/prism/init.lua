--- prism: kitty color stack escape codes for Neovim.

---@class prism
local M = {}

---@class prism.Opts

---@type prism.Opts
local defaults = {}

---@nodiscard
---@return prism.Opts
function M.get_defaults()
  return defaults
end

---@param opts? prism.Opts
function M.setup(opts)
  defaults = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
