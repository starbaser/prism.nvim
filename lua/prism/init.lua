--- prism: dynamic kitty transparent-background slot manager driven by
--- visible Neovim highlight groups.

local events = require("prism.events")
local log = require("prism.logging")
local registry = require("prism.registry")
local slots = require("prism.slots")
local terminal = require("prism.terminal")

---@class prism
local M = {}

---@class prism.GroupSpec
---@field name string
---@field opacity number

---@class prism.Opts
---@field groups       prism.GroupSpec[]
---@field debounce_ms  integer
---@field scan_step    integer

---@type prism.Opts
local defaults = {
  groups = {},
  debounce_ms = 50,
  scan_step = 1,
}

local active = false

---@nodiscard
---@return prism.Opts
function M.get_defaults()
  return defaults
end

---@param opts? prism.Opts
function M.setup(opts)
  defaults = vim.tbl_deep_extend("force", defaults, opts or {})

  if not terminal.is_kitty() then
    log.warn(string.format(
      "prism: not running in kitty (TERM=%s); disabled",
      vim.env.TERM or ""
    ))
    return
  end

  terminal.push()
  for _, g in ipairs(defaults.groups) do
    registry.register(g.name, g.opacity)
  end
  events.attach(defaults)
  events.schedule_refresh()
  active = true
end

---@param name string
---@param opacity number
function M.register(name, opacity)
  local reg = registry.register(name, opacity)
  if reg then events.schedule_refresh() end
  return reg
end

---@param name string
function M.unregister(name)
  registry.unregister(name)
  events.schedule_refresh()
end

function M.refresh()
  events.schedule_refresh()
end

---@nodiscard
---@return { active: boolean, registrations: prism.Registration[], slots: table<integer, prism.Registration|nil> }
function M.status()
  return {
    active = active,
    registrations = registry.all(),
    slots = slots.snapshot(),
  }
end

function M.disable()
  if not active then return end
  events.detach()
  slots.clear_all()
  terminal.pop()
  active = false
end

return M
