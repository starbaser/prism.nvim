--- prism: dynamic kitty transparent-background slot manager driven by
--- visible Neovim highlight groups.

local events = require("prism.events")
local registry = require("prism.registry")
local signals = require("prism.signals")
local slots = require("prism.slots")
local stats = require("prism.stats")
local terminal = require("prism.terminal")

---@class prism
local M = {}

---@class prism.RegistrationSpec
---@field target  string|integer
---@field opacity number
---@field priority? number

---@class prism.Opts
---@field registrations prism.RegistrationSpec[]
---@field debounce_ms  integer
---@field max_refresh_hz integer
---@field burst_window_ms integer
---@field burst_event_threshold integer
---@field burst_quiet_ms integer

---@type prism.Opts
local defaults = {
  registrations = {},
  debounce_ms = 50,
  max_refresh_hz = 20,
  burst_window_ms = 100,
  burst_event_threshold = 8,
  burst_quiet_ms = 150,
}

local active = false

---@param opts prism.Opts
local function apply_options(opts)
  if opts.registrations ~= nil then defaults.registrations = opts.registrations end
  if opts.debounce_ms ~= nil then defaults.debounce_ms = opts.debounce_ms end
  if opts.max_refresh_hz ~= nil then defaults.max_refresh_hz = opts.max_refresh_hz end
  if opts.burst_window_ms ~= nil then defaults.burst_window_ms = opts.burst_window_ms end
  if opts.burst_event_threshold ~= nil then defaults.burst_event_threshold = opts.burst_event_threshold end
  if opts.burst_quiet_ms ~= nil then defaults.burst_quiet_ms = opts.burst_quiet_ms end
end

---@nodiscard
---@return prism.Opts
function M.get_defaults()
  return defaults
end

---@return boolean
local function can_enable()
  return terminal.is_kitty()
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
  opts = opts or {}
  apply_options(opts)
  if not can_enable() then return false end

  local changed = false
  for _, spec in ipairs(defaults.registrations) do
    local _, did_change = registry.register(spec.target, spec.opacity, spec.priority)
    changed = changed or did_change
  end
  registry.rebuild_color_index()
  if changed then
    signals.emit(signals.REGISTRY_CHANGED)
  end

  if active then
    refresh_active()
    return false
  end
  return activate()
end

---@param target string|integer
---@param opacity number
---@param priority? number
function M.register(target, opacity, priority)
  local reg, changed = registry.register(target, opacity, priority)
  if reg and changed then
    registry.rebuild_color_index()
    if active then events.force_refresh() end
    signals.emit(signals.REGISTRY_CHANGED)
  end
  return reg
end

---@param key string|integer
function M.unregister(key)
  local changed = registry.unregister(key)
  if changed then
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
