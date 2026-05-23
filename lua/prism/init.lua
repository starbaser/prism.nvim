--- prism: dynamic kitty transparent-background slot manager driven by
--- visible Neovim highlight groups.

local events = require("prism.events")
local log = require("prism.logging")
local registry = require("prism.registry")
local signals = require("prism.signals")
local slots = require("prism.slots")
local stats = require("prism.stats")
local terminal = require("prism.terminal")

---@class prism
local M = {}

---@class prism.GroupSpec
---@field name    string
---@field opacity number

---@class prism.ColorSpec
---@field color   integer|string  0xRRGGBB or "#RRGGBB"
---@field opacity number

---@class prism.Opts
---@field groups       prism.GroupSpec[]
---@field colors       prism.ColorSpec[]
---@field debounce_ms  integer
---@field max_refresh_hz integer
---@field burst_window_ms integer
---@field burst_event_threshold integer
---@field burst_quiet_ms integer

---@type prism.Opts
local defaults = {
  groups = {},
  colors = {},
  debounce_ms = 50,
  max_refresh_hz = 20,
  burst_window_ms = 100,
  burst_event_threshold = 8,
  burst_quiet_ms = 150,
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
  local registration_count = #registry.all()
  -- Colors first so groups nudge around any raw value collisions.
  for _, c in ipairs(defaults.colors) do
    registry.register_color(c.color, c.opacity)
  end
  for _, g in ipairs(defaults.groups) do
    registry.register(g.name, g.opacity)
  end
  registry.rebuild_color_index()
  events.attach(defaults)
  events.force_refresh()
  active = true
  if #registry.all() ~= registration_count then
    signals.emit(signals.REGISTRY_CHANGED)
  end
end

---@param name string
---@param opacity number
function M.register(name, opacity)
  local before = registry.get(name)
  local reg = registry.register(name, opacity)
  if reg and reg ~= before then
    registry.rebuild_color_index()
    events.force_refresh()
    signals.emit(signals.REGISTRY_CHANGED)
  end
  return reg
end

---@param color integer|string
---@param opacity number
function M.register_color(color, opacity)
  local registration_count = #registry.all()
  local reg = registry.register_color(color, opacity)
  if reg and #registry.all() ~= registration_count then
    registry.rebuild_color_index()
    events.force_refresh()
    signals.emit(signals.REGISTRY_CHANGED)
  end
  return reg
end

---@param key string|integer
function M.unregister(key)
  local registration_count = #registry.all()
  registry.unregister(key)
  if #registry.all() ~= registration_count then
    registry.rebuild_color_index()
    events.force_refresh()
    signals.emit(signals.REGISTRY_CHANGED)
  end
end

function M.refresh()
  registry.rebuild_color_index()
  events.force_refresh()
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

---@nodiscard
---@return prism.stats.Snapshot
function M.stats()
  return stats.snapshot()
end

function M.reset_stats()
  stats.reset()
end

return M
