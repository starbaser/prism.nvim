--- prism.registry: priority-ordered registration with bg-color nudging.
---
--- Two registration paths share the same priority list:
---   * groups[]: name-keyed; bg read from the live hl group. Groups with
---     the same bg and opacity share one nudged key; otherwise bg is nudged
---     to a unique 24-bit key, then written back. Visibility is gated on the
---     group's name appearing in the scanner's visible_names set.
---   * colors[]: raw RGB; stored as-is (no nudge). Visibility is gated on
---     ANY currently-defined hl group having that exact bg AND appearing in
---     visible_names, looked up via a color_index built from nvim_get_hl(0,{}).

local log = require("prism.logging")

local M = {}

---@class prism.Registration
---@field name        string?   nil for color-only registrations
---@field opacity     number    0.0..1.0 (or -1 = use kitty background_opacity)
---@field index       integer   1-based registration position (= priority)
---@field nudged_bg   integer   unique 24-bit bg value (= kitty slot color key)
---@field original_bg integer?  pre-registration bg; nil for color-only
---@field color_only  boolean   true when registered via colors[], not groups[]

---@type prism.Registration[]
local registrations = {}

---@type table<string, prism.Registration>
local by_name = {}

--- bg value -> list of currently-defined hl group names with that bg.
--- Rebuilt on setup, on ColorScheme, and on :PrismRefresh.
---@type table<integer, string[]>
local color_index = {}

local RGB_MASK = 0xFFFFFF

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

---@param n integer
local function is_used_nudge(n)
  for _, r in ipairs(registrations) do
    if r.nudged_bg == n then
      return true
    end
  end
  return false
end

---@param orig integer
---@param opacity number
---@return integer?
local function shared_nudge(orig, opacity)
  for _, r in ipairs(registrations) do
    if not r.color_only and r.original_bg == orig and r.opacity == opacity then
      return r.nudged_bg
    end
  end
  return nil
end

--- Compute a nudged bg unique within the current registration set.
--- Prefer the smallest positive blue-channel delta so unrelated earlier
--- registrations do not make later groups drift farther from their source bg.
---@param orig integer
---@return integer
function M._nudge(orig)
  local r, g, b = unpack_rgb(orig)
  local function available(n)
    return n and n ~= orig and not is_used_nudge(n)
  end
  for step = 1, 0xff do
    local n = pack_rgb(r, g, b + step)
    if available(n) then return n end
  end
  for step = 1, 0xff do
    local n = pack_rgb(r, g, b - step)
    if available(n) then return n end
  end
  for step = 1, 0xff do
    local n = pack_rgb(r, g + step, b)
    if available(n) then return n end
  end
  for step = 1, 0xff do
    local n = pack_rgb(r, g - step, b)
    if available(n) then return n end
  end
  for step = 1, 0xff do
    local n = pack_rgb(r + step, g, b)
    if available(n) then return n end
  end
  for step = 1, 0xff do
    local n = pack_rgb(r - step, g, b)
    if available(n) then return n end
  end
  error(string.format("prism: exhausted RGB nudge space for #%06x", orig))
end

---@param c integer|string
---@return integer?
local function parse_color(c)
  if type(c) == "number" then
    return c >= 0 and c <= RGB_MASK and c or nil
  end
  if type(c) == "string" then
    local hex = c:gsub("^#", "")
    local n = tonumber(hex, 16)
    if n and n >= 0 and n <= RGB_MASK then return n end
  end
  return nil
end

---@param reg prism.Registration
local function apply_hl(reg)
  local hl = vim.api.nvim_get_hl(0, { name = reg.name, link = false })
  hl.bg = reg.nudged_bg
  ---@diagnostic disable-next-line: param-type-mismatch
  vim.api.nvim_set_hl(0, reg.name, hl)
end

--- Register a highlight group. Returns the registration on success or nil
--- if the group has no bg AND Normal has no bg (kitty needs a key).
---
--- Fallback: when the group itself has no bg (e.g. Terminal links to Normal
--- but no explicit bg propagated), we synthesize one from Normal.bg. The
--- nudge then makes the group's cells distinct from raw Normal cells so
--- kitty slots them independently. User-visible: Terminal cells render with
--- a near-Normal bg shifted by a few LSBs — imperceptible.
---@param name string
---@param opacity number
---@return prism.Registration?
function M.register(name, opacity)
  if type(opacity) ~= "number" then
    log.warn(string.format(
      "prism: %s: opacity must be a number, got %s; skipping",
      tostring(name), type(opacity)
    ))
    return nil
  end
  if by_name[name] then
    log.warn(string.format("prism: %s already registered; skipping", name))
    return by_name[name]
  end
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  local original_bg = hl and hl.bg
  if not original_bg then
    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    if normal and normal.bg then
      original_bg = normal.bg
      log.debug(string.format("prism: %s has no bg; falling back to Normal.bg", name))
    else
      log.warn(string.format("prism: %s has no bg and Normal has no bg; skipping", name))
      return nil
    end
  end
  ---@cast original_bg integer
  local idx = #registrations + 1
  local reg = {
    name = name,
    opacity = opacity,
    index = idx,
    original_bg = original_bg,
    nudged_bg = 0,
    color_only = false,
  }
  reg.nudged_bg = shared_nudge(original_bg, opacity) or M._nudge(original_bg)
  registrations[idx] = reg
  by_name[name] = reg
  apply_hl(reg)
  return reg
end

--- Register a raw 24-bit color. Stored verbatim — no nudging, no hl group
--- modification. Visibility is determined by checking whether any defined
--- hl group with this exact bg is in the scanner's visible_names set.
---@param color integer|string
---@param opacity number
---@return prism.Registration?
function M.register_color(color, opacity)
  if type(opacity) ~= "number" then
    log.warn(string.format(
      "prism: color %s: opacity must be a number, got %s; skipping",
      tostring(color), type(opacity)
    ))
    return nil
  end
  local rgb = parse_color(color)
  if not rgb then
    log.warn(string.format("prism: invalid color %s; skipping", tostring(color)))
    return nil
  end
  if is_used_nudge(rgb) then
    log.warn(string.format("prism: color #%06x collides with existing registration; skipping", rgb))
    return nil
  end
  local idx = #registrations + 1
  local reg = {
    name = nil,
    opacity = opacity,
    index = idx,
    original_bg = nil,
    nudged_bg = rgb,
    color_only = true,
  }
  registrations[idx] = reg
  return reg
end

--- Unregister a highlight group and restore its original bg. For color-only
--- registrations, pass the raw color value (int or "#hex").
---@param key string|integer
function M.unregister(key)
  local reg
  if type(key) == "string" and not key:match("^#") then
    reg = by_name[key]
  else
    local rgb = parse_color(key)
    for _, r in ipairs(registrations) do
      if r.color_only and r.nudged_bg == rgb then
        reg = r
        break
      end
    end
  end
  if not reg then return end

  if not reg.color_only then
    local hl = vim.api.nvim_get_hl(0, { name = reg.name, link = false })
    hl.bg = reg.original_bg
    ---@diagnostic disable-next-line: param-type-mismatch
    vim.api.nvim_set_hl(0, reg.name, hl)
    by_name[reg.name] = nil
  end

  for i, r in ipairs(registrations) do
    if r == reg then
      table.remove(registrations, i)
      break
    end
  end
  for i, r in ipairs(registrations) do
    r.index = i
  end
end

--- Re-resolve and re-apply all registrations after a colorscheme change.
--- For groups: the colorscheme overwrote our nudges, so re-read & re-nudge.
--- For colors: the raw value is preserved; only the index is rebuilt.
function M.on_colorscheme()
  local saved = registrations
  registrations = {}
  by_name = {}
  for _, r in ipairs(saved) do
    if r.color_only then
      M.register_color(r.nudged_bg, r.opacity)
    else
      M.register(r.name, r.opacity)
    end
  end
  M.rebuild_color_index()
end

--- Walk every currently-defined hl group and build a bg -> {names} index.
--- Used to determine visibility for color-only registrations.
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

--- The set of registered group names (color-only registrations excluded).
--- Used by scanner's tier-3 state augmentation to decide which window-state
--- gates to evaluate — we only burn a syscall if the user actually cares.
---@nodiscard
---@return table<string, true>
function M.registered_names()
  local out = {}
  for _, r in ipairs(registrations) do
    if r.name then out[r.name] = true end
  end
  return out
end

--- Names worth searching for during visibility scans. Direct group
--- registrations are included as-is; color-only registrations contribute the
--- currently-defined groups whose bg equals that raw color.
---@nodiscard
---@return table<string, true>
function M.visibility_targets()
  local out = M.registered_names()
  for _, r in ipairs(registrations) do
    if r.color_only then
      local groups = color_index[r.nudged_bg]
      if groups then
        for _, name in ipairs(groups) do
          out[name] = true
        end
      end
    end
  end
  return out
end

---@param name string
---@return prism.Registration?
function M.get(name)
  return by_name[name]
end

--- Reset all state. Test-only.
function M._reset()
  registrations = {}
  by_name = {}
  color_index = {}
end

--- Filter the registration list to those currently visible:
---   * group entries: visible iff the group's name is in `visible_names`
---   * color entries: visible iff any group in color_index[nudged_bg] is in `visible_names`
--- Order is preserved from registration order; the slot reconciler caps the
--- result at the slot count.
---@param visible_names table<string, true>
---@param limit? integer
---@return prism.Registration[]
function M.filter_visible(visible_names, limit)
  local out = {}
  local included_slots = {}
  for _, r in ipairs(registrations) do
    local is_visible
    if r.color_only then
      is_visible = false
      local groups = color_index[r.nudged_bg]
      if groups then
        for _, g in ipairs(groups) do
          if visible_names[g] then
            is_visible = true
            break
          end
        end
      end
    else
      is_visible = visible_names[r.name] == true
    end
    local slot_key = is_visible and string.format("%06x:%s", r.nudged_bg, r.opacity)
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
