--- eigenplug

---@class eigenplug
local M = {}

---@class eigenplug.Opts

---@type eigenplug.Opts
local defaults = {}

--- Read merged setup-time defaults.
---@nodiscard
---@return eigenplug.Opts
function M.get_defaults()
  return defaults
end

--- Demo entrypoint — logs a hello message via the structured logger.
function M.hello()
  require("eigenplug.logging").info("hello from eigenplug")
end

---@param opts? eigenplug.Opts
function M.setup(opts)
  defaults = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
