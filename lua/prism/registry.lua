--- prism.registry: priority-ordered target registration with bg-color nudging.
---
--- A target is either a highlight group or a raw RGB color. Highlight-group
--- targets read and rewrite the live group's background. Raw-color targets
--- stay exact and are considered visible when any visible highlight group has
--- that exact background.

local log = require("prism.logging")

local M = {}

---@alias prism.RegistrationKind "group"|"color"

---@class prism.Registration
---@field kind        prism.RegistrationKind
---@field target      string   group name or "#rrggbb"
---@field group       string?  highlight group name for group targets
---@field color       integer? raw RGB value for color targets
---@field opacity     number   0.0..1.0 (or -1 = use kitty background_opacity)
---@field priority    number   higher values sort first
---@field sequence    integer first-registration order for priority ties
---@field index       integer 1-based sorted rank
---@field nudged_bg   integer kitty slot color key
---@field original_bg integer? pre-registration bg for group targets

---@type prism.Registration[]
local registrations = {}

---@type table<string, prism.Registration>
local by_key = {}

--- bg value -> list of currently-defined hl group names with that bg.
--- Rebuilt on setup, on ColorScheme, and on :PrismRefresh.
---@type table<integer, string[]>
local color_index = {}

local RGB_MASK = 0xFFFFFF
local next_sequence = 1

---@param rgb integer
---@return integer r
---@return integer g
---@return integer b
local function unpack_rgb(rgb)
  local r = math.floor(rgb / 0x10000) % 0x100
  local g = math.floor(rgb / 0x100) % 0x100
  local b = rgb % 0x100
  return r, g, b
end

---@param r integer
---@param g integer
---@param b integer
---@return integer?
local function pack_rgb(r, g, b)
  if r < 0 or r > 0xff or g < 0 or g > 0xff or b < 0 or b > 0xff then
    return nil
  end
  return r * 0x10000 + g * 0x100 + b
end

---@param color integer|string
---@return integer?
local function parse_color_target(color)
  if type(color) == "number" then
    return color >= 0 and color <= RGB_MASK and color or nil
  end
  if type(color) ~= "string" then return nil end

  local hex = color:match("^#?(%x%x%x%x%x%x)$")
  if not hex then return nil end
  return tonumber(hex, 16)
end

---@param target any
---@return { kind: prism.RegistrationKind, key: string, target: string, group?: string, color?: integer }?
local function parse_target(target)
  local rgb = parse_color_target(target)
  if rgb then
    return {
      kind = "color",
      key = string.format("color:%06x", rgb),
      target = string.format("#%06x", rgb),
      color = rgb,
    }
  end

  if type(target) == "string" then
    return {
      kind = "group",
      key = "group:" .. target,
      target = target,
      group = target,
    }
  end

  return nil
end

---@param value number
---@return string
local function number_key(value)
  return string.format("%.17g", value)
end

---@return string
local function state_signature()
  local parts = {}
  for i, r in ipairs(registrations) do
    parts[i] = table.concat({
      r.kind,
      r.target,
      number_key(r.opacity),
      number_key(r.priority),
      tostring(r.sequence),
      tostring(r.index),
      string.format("%06x", r.nudged_bg or 0),
      r.original_bg and string.format("%06x", r.original_bg) or "-",
    }, "|")
  end
  return table.concat(parts, "\n")
end

local function sort_registrations()
  table.sort(registrations, function(a, b)
    if a.priority ~= b.priority then
      return a.priority > b.priority
    end
    return a.sequence < b.sequence
  end)

  for i, r in ipairs(registrations) do
    r.index = i
  end
end

---@param reg prism.Registration
local function add_indexes(reg)
  local key = reg.kind == "group"
    and "group:" .. reg.group
    or string.format("color:%06x", reg.color)
  by_key[key] = reg
end

local function rebuild_indexes()
  by_key = {}
  for _, reg in ipairs(registrations) do
    add_indexes(reg)
  end
end

---@param name string
---@return table?
local function get_hl(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if not ok then
    log.warn(string.format("prism: invalid highlight group %s; skipping", tostring(name)))
    return nil
  end
  return hl
end

---@param reg prism.Registration
local function apply_hl(reg)
  if reg.kind ~= "group" then return end
  local hl = get_hl(reg.group)
  if not hl then return end
  hl.bg = reg.nudged_bg
  ---@diagnostic disable-next-line: param-type-mismatch
  local ok = pcall(vim.api.nvim_set_hl, 0, reg.group, hl)
  if not ok then
    log.warn(string.format("prism: invalid highlight group %s; skipping", tostring(reg.group)))
  end
end

---@param name string
---@param existing prism.Registration?
---@param force_live boolean?
---@return integer?
local function resolve_group_bg(name, existing, force_live)
  local hl = get_hl(name)
  if not hl then return nil end
  local bg = hl and hl.bg
  if existing and bg == existing.nudged_bg then
    return existing.original_bg
  end
  if bg then return bg end

  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  if normal and normal.bg then
    log.debug(string.format("prism: %s has no bg; falling back to Normal.bg", name))
    return normal.bg
  end

  log.warn(string.format("prism: %s has no bg and Normal has no bg; skipping", name))
  return nil
end

---@param assigned table<integer, { kind: prism.RegistrationKind, opacity: number, original_bg?: integer }[]>
---@param rgb integer
---@param reg prism.Registration
local function assign_color(assigned, rgb, reg)
  local bucket = assigned[rgb]
  if not bucket then
    bucket = {}
    assigned[rgb] = bucket
  end
  bucket[#bucket + 1] = {
    kind = reg.kind,
    opacity = reg.opacity,
    original_bg = reg.original_bg,
  }
end

---@param assigned table<integer, { kind: prism.RegistrationKind, opacity: number, original_bg?: integer }[]>
---@param candidate integer?
---@param original_bg integer
---@param opacity number
---@return boolean
local function can_use_nudge(assigned, candidate, original_bg, opacity)
  if not candidate or candidate == original_bg then return false end

  local bucket = assigned[candidate]
  if not bucket then return true end

  for _, entry in ipairs(bucket) do
    if entry.opacity ~= opacity then
      return false
    end
    if entry.kind == "group" and entry.original_bg ~= original_bg then
      return false
    end
  end
  return true
end

--- Compute a group bg key compatible with already-assigned raw colors and
--- higher-priority group registrations.
---@param original_bg integer
---@param opacity number
---@param assigned table<integer, { kind: prism.RegistrationKind, opacity: number, original_bg?: integer }[]>
---@return integer
function M._nudge(original_bg, opacity, assigned)
  assigned = assigned or {}
  local r, g, b = unpack_rgb(original_bg)
  for step = 1, 0xff do
    local n = pack_rgb(r, g, b + step)
    if can_use_nudge(assigned, n, original_bg, opacity) then return n end
  end
  for step = 1, 0xff do
    local n = pack_rgb(r, g, b - step)
    if can_use_nudge(assigned, n, original_bg, opacity) then return n end
  end
  for step = 1, 0xff do
    local n = pack_rgb(r, g + step, b)
    if can_use_nudge(assigned, n, original_bg, opacity) then return n end
  end
  for step = 1, 0xff do
    local n = pack_rgb(r, g - step, b)
    if can_use_nudge(assigned, n, original_bg, opacity) then return n end
  end
  for step = 1, 0xff do
    local n = pack_rgb(r + step, g, b)
    if can_use_nudge(assigned, n, original_bg, opacity) then return n end
  end
  for step = 1, 0xff do
    local n = pack_rgb(r - step, g, b)
    if can_use_nudge(assigned, n, original_bg, opacity) then return n end
  end
  error(string.format("prism: exhausted RGB nudge space for #%06x", original_bg))
end

local function recompute()
  sort_registrations()

  local assigned = {}
  for _, reg in ipairs(registrations) do
    if reg.kind == "color" then
      reg.nudged_bg = reg.color
      assign_color(assigned, reg.nudged_bg, reg)
    end
  end

  for _, reg in ipairs(registrations) do
    if reg.kind == "group" then
      reg.nudged_bg = M._nudge(reg.original_bg, reg.opacity, assigned)
      assign_color(assigned, reg.nudged_bg, reg)
      apply_hl(reg)
    end
  end

  rebuild_indexes()
end

---@param target string|integer
---@param opacity number
---@param priority? number
---@return prism.Registration?
---@return boolean changed
function M.register(target, opacity, priority)
  local parsed = parse_target(target)
  if not parsed then
    log.warn(string.format("prism: invalid target %s; skipping", tostring(target)))
    return nil, false
  end
  if type(opacity) ~= "number" then
    log.warn(string.format(
      "prism: %s: opacity must be a number, got %s; skipping",
      tostring(target), type(opacity)
    ))
    return nil, false
  end
  if priority ~= nil and type(priority) ~= "number" then
    log.warn(string.format(
      "prism: %s: priority must be a number, got %s; skipping",
      tostring(target), type(priority)
    ))
    return nil, false
  end

  local before = state_signature()
  local reg = by_key[parsed.key]
  local existing = reg ~= nil
  local old_opacity = reg and reg.opacity or nil
  local old_priority = reg and reg.priority or nil
  if not reg then
    reg = {
      kind = parsed.kind,
      target = parsed.target,
      group = parsed.group,
      color = parsed.color,
      opacity = opacity,
      priority = priority or 0,
      sequence = next_sequence,
      index = #registrations + 1,
      original_bg = nil,
      nudged_bg = parsed.color or 0,
    }
    next_sequence = next_sequence + 1
    registrations[#registrations + 1] = reg
  else
    reg.opacity = opacity
    if priority ~= nil then reg.priority = priority end
  end

  if reg.kind == "group" then
    local original_bg = resolve_group_bg(reg.group, existing and reg or nil)
    if not original_bg then
      if not existing then
        registrations[#registrations] = nil
      else
        reg.opacity = old_opacity
        reg.priority = old_priority
      end
      rebuild_indexes()
      return nil, false
    end
    reg.original_bg = original_bg
  end

  recompute()
  return reg, before ~= state_signature()
end

---@param key string|integer
---@return boolean changed
function M.unregister(key)
  local parsed = parse_target(key)
  if not parsed then return false end

  local reg = by_key[parsed.key]
  if not reg then return false end

  local before = state_signature()
  if reg.kind == "group" then
    local hl = get_hl(reg.group)
    if hl then
      hl.bg = reg.original_bg
      ---@diagnostic disable-next-line: param-type-mismatch
      pcall(vim.api.nvim_set_hl, 0, reg.group, hl)
    end
  end

  for i, candidate in ipairs(registrations) do
    if candidate == reg then
      table.remove(registrations, i)
      break
    end
  end

  recompute()
  return before ~= state_signature()
end

--- Re-resolve and re-apply all group registrations after a colorscheme change.
---@return boolean changed
function M.on_colorscheme()
  local before = state_signature()
  local kept = {}

  for _, reg in ipairs(registrations) do
    if reg.kind == "group" then
      local original_bg = resolve_group_bg(reg.group, reg, true)
      if original_bg then
        reg.original_bg = original_bg
        kept[#kept + 1] = reg
      end
    else
      kept[#kept + 1] = reg
    end
  end

  registrations = kept
  recompute()
  M.rebuild_color_index()
  return before ~= state_signature()
end

--- Walk every currently-defined hl group and build a bg -> {names} index.
--- Used to determine visibility for raw-color registrations.
function M.rebuild_color_index()
  color_index = {}
  local all_hl = vim.api.nvim_get_hl(0, {})
  for name, def in pairs(all_hl) do
    if not def.link and def.bg then
      local bucket = color_index[def.bg]
      if not bucket then
        bucket = {}
        color_index[def.bg] = bucket
      end
      bucket[#bucket + 1] = name
    end
  end
end

---@nodiscard
---@return prism.Registration[]
function M.all()
  return registrations
end

--- Highlight groups worth checking during scanner state augmentation.
---@nodiscard
---@return table<string, true>
function M.registered_names()
  local out = {}
  for _, r in ipairs(registrations) do
    if r.kind == "group" then out[r.group] = true end
  end
  return out
end

--- Names worth searching for during visibility scans. Direct group
--- registrations are included as-is; color registrations contribute the
--- currently-defined groups whose bg equals that raw color.
---@nodiscard
---@return table<string, true>
function M.visibility_targets()
  local out = M.registered_names()
  for _, r in ipairs(registrations) do
    if r.kind == "color" then
      local groups = color_index[r.color]
      if groups then
        for _, name in ipairs(groups) do
          out[name] = true
        end
      end
    end
  end
  return out
end

---@param target string|integer
---@return prism.Registration?
function M.get(target)
  local parsed = parse_target(target)
  return parsed and by_key[parsed.key] or nil
end

--- Reset all state. Test-only.
function M._reset()
  registrations = {}
  by_key = {}
  color_index = {}
  next_sequence = 1
end

--- Filter the registration list to those currently visible:
---   * group entries: visible iff the group's name is in `visible_names`
---   * color entries: visible iff any group in color_index[color] is visible
--- The list is already priority sorted; the slot reconciler caps it.
---@param visible_names table<string, true>
---@param limit? integer
---@return prism.Registration[]
function M.filter_visible(visible_names, limit)
  local out = {}
  local included_slots = {}
  for _, r in ipairs(registrations) do
    local is_visible
    if r.kind == "color" then
      is_visible = false
      local groups = color_index[r.color]
      if groups then
        for _, g in ipairs(groups) do
          if visible_names[g] then
            is_visible = true
            break
          end
        end
      end
    else
      is_visible = visible_names[r.group] == true
    end

    local slot_key = is_visible and string.format("%06x:%s", r.nudged_bg, number_key(r.opacity))
    if is_visible and not included_slots[slot_key] then
      out[#out + 1] = r
      included_slots[slot_key] = true
      if limit and #out >= limit then
        break
      end
    end
  end
  return out
end

return M
