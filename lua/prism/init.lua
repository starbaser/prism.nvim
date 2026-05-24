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

---@param color integer|string
---@return boolean
local function color_registered(color)
  local rgb
  if type(color) == "number" then
    rgb = color
  elseif type(color) == "string" then
    rgb = tonumber(color:gsub("^#", ""), 16)
  end
  if not rgb then return false end

  for _, reg in ipairs(registry.all()) do
    if reg.color_only and reg.nudged_bg == rgb then
      return true
    end
  end
  return false
end

---@nodiscard
---@return prism.Opts
function M.get_defaults()
  return defaults
end

---@return boolean
local function can_enable()
  if not terminal.is_kitty() then
    log.warn(string.format(
      "prism: not running in kitty (TERM=%s); disabled",
      vim.env.TERM or ""
    ))
    return false
  end
  return true
end

local function refresh_active()
  registry.rebuild_color_index()
  events.attach(defaults)
  events.force_refresh()
end

local function activate()
  terminal.push()
  active = true
  refresh_active()
  return true
end

---@param opts? prism.Opts
function M.setup(opts)
  defaults = vim.tbl_deep_extend("force", defaults, opts or {})
  if not can_enable() then return false end

  local registration_count = #registry.all()
  -- Colors reserve raw slots before groups compute nudged keys.
  for _, c in ipairs(defaults.colors) do
    if not color_registered(c.color) then
      registry.register_color(c.color, c.opacity)
    end
  end
  for _, g in ipairs(defaults.groups) do
    if not registry.get(g.name) then
      registry.register(g.name, g.opacity)
    end
  end
  registry.rebuild_color_index()
  if #registry.all() ~= registration_count then
    signals.emit(signals.REGISTRY_CHANGED)
  end

  if active then
    refresh_active()
    return false
  end
  return activate()
end

---@param name string
---@param opacity number
function M.register(name, opacity)
  local before = registry.get(name)
  local reg = registry.register(name, opacity)
  if reg and reg ~= before then
    registry.rebuild_color_index()
    if active then events.force_refresh() end
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
    if active then events.force_refresh() end
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
    if active then events.force_refresh() end
    signals.emit(signals.REGISTRY_CHANGED)
  end
end

function M.refresh()
  registry.rebuild_color_index()
  if active then events.force_refresh() end
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
  if not active then return false end
  events.detach()
  slots.clear_all()
  terminal.pop()
  active = false
  return true
end

function M.enable()
  if active then
    refresh_active()
    return false
  end
  if not can_enable() then return false end

  return activate()
end

function M.toggle()
  if active then
    return M.disable()
  end
  return M.enable()
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
