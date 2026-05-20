--- prism.registry: priority-ordered registration with bg-color nudging.
---
--- Each registered highlight group gets its background color nudged by a
--- small per-registration offset, so every entry has a globally unique
--- 24-bit bg key. Kitty's transparent_background_colorN slots match cells
--- by exact bg color, so this nudge guarantees one-to-one mapping between
--- registered groups and slot color keys.

local log = require("prism.logging")

local M = {}

---@class prism.Registration
---@field name        string   highlight group name
---@field opacity     number   0.0..1.0 (or -1 = use kitty background_opacity)
---@field index       integer  1-based registration position (= priority)
---@field nudged_bg   integer  unique 24-bit bg value written into the hl group
---@field original_bg integer  original bg from the colorscheme

---@type prism.Registration[]
local registrations = {}

---@type table<string, prism.Registration>
local by_name = {}

--- Mask to keep the value in 24 bits.
local RGB_MASK = 0xFFFFFF

---@param n integer
local function is_used_nudge(n)
  for _, r in ipairs(registrations) do
    if r.nudged_bg == n then
      return true
    end
  end
  return false
end

--- Compute a nudged bg unique within the current registration set.
--- The user-visible delta is at most a handful of LSBs of blue/green —
--- imperceptible, but distinct enough for kitty's exact-match keying.
---@param orig integer
---@param index integer
---@return integer
function M._nudge(orig, index)
  local n = (orig + index) % (RGB_MASK + 1)
  while is_used_nudge(n) or n == orig do
    n = (n + 1) % (RGB_MASK + 1)
  end
  return n
end

--- Apply a registration's nudged_bg to the live highlight group, preserving
--- all other attributes (fg, bold, italic, etc.).
---@param reg prism.Registration
local function apply_hl(reg)
  local hl = vim.api.nvim_get_hl(0, { name = reg.name, link = false })
  hl.bg = reg.nudged_bg
  ---@diagnostic disable-next-line: param-type-mismatch
  vim.api.nvim_set_hl(0, reg.name, hl)
end

--- Register a highlight group. Returns the registration on success or nil
--- if the group has no bg (kitty cannot key transparency without one).
---@param name string
---@param opacity number
---@return prism.Registration?
function M.register(name, opacity)
  if by_name[name] then
    log.warn(string.format("prism: %s already registered; skipping", name))
    return by_name[name]
  end
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  if not hl or not hl.bg then
    log.warn(string.format("prism: %s has no bg; skipping", name))
    return nil
  end
  local idx = #registrations + 1
  local reg = {
    name = name,
    opacity = opacity,
    index = idx,
    original_bg = hl.bg,
    nudged_bg = 0,
  }
  reg.nudged_bg = M._nudge(hl.bg, idx)
  registrations[idx] = reg
  by_name[name] = reg
  apply_hl(reg)
  return reg
end

--- Unregister a highlight group and restore its original bg.
---@param name string
function M.unregister(name)
  local reg = by_name[name]
  if not reg then return end
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  hl.bg = reg.original_bg
  ---@diagnostic disable-next-line: param-type-mismatch
  vim.api.nvim_set_hl(0, name, hl)
  by_name[name] = nil
  for i, r in ipairs(registrations) do
    if r.name == name then
      table.remove(registrations, i)
      break
    end
  end
  for i, r in ipairs(registrations) do
    r.index = i
  end
end

--- Re-resolve and re-apply all nudges after a colorscheme change.
--- The colorscheme will have overwritten our nudged values with its own
--- bg values, so we recompute the originals and the nudges and re-write.
function M.on_colorscheme()
  local saved = registrations
  registrations = {}
  by_name = {}
  for _, r in ipairs(saved) do
    M.register(r.name, r.opacity)
  end
end

---@nodiscard
---@return prism.Registration[]
function M.all()
  return registrations
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
end

--- Filter the registration list to those whose names appear in `visible`,
--- preserving registration order. The slot reconciler caps the result at
--- the slot count.
---@param visible table<string, true>
---@return prism.Registration[]
function M.filter_visible(visible)
  local out = {}
  for _, r in ipairs(registrations) do
    if visible[r.name] then
      out[#out + 1] = r
    end
  end
  return out
end

return M
