--- prism.slots: minimum-diff reconciler for kitty's 7 transparent slots.
---
--- Maintains a local mirror of which registration occupies each kitty slot
--- and emits only the OSC 21 codes needed to converge to a desired state.

local terminal = require("prism.terminal")
local signals = require("prism.signals")

local M = {}

M.MAX_SLOTS = 7

---@type table<integer, prism.Registration|nil>
local current = {}

---@type table<integer, string|nil>
local current_keys = {}

---@param reg prism.Registration?
---@return string?
local function slot_key(reg)
  if not reg then return nil end
  return string.format("%06x:%.17g", reg.nudged_bg, reg.opacity)
end

--- Set the new desired registration list. Existing visible occupants keep
--- their slots; empty slots are filled from the priority-ordered desired
--- list. Slots whose occupant changed are re-emitted; unchanged slots are
--- left alone so kitty receives only the minimum bytes needed.
---
--- Returns the number of escape codes emitted (set_slot + clear_slot
--- calls). Used by prism.stats for diagnostics.
---@param desired prism.Registration[]
---@return integer emitted
function M.reconcile(desired)
  local visible = {}
  for _, r in ipairs(desired) do
    visible[r] = true
  end

  local target = {}
  local occupied = {}
  for i = 1, M.MAX_SLOTS do
    local cur = current[i]
    if cur and visible[cur] then
      target[i] = cur
      occupied[cur] = true
    end
  end

  local candidate = 1
  for i = 1, M.MAX_SLOTS do
    if not target[i] then
      while candidate <= #desired and occupied[desired[candidate]] do
        candidate = candidate + 1
      end
      if candidate <= #desired then
        local nxt = desired[candidate]
        target[i] = nxt
        occupied[nxt] = true
        candidate = candidate + 1
      end
    end
  end

  local emitted = 0
  for i = 1, M.MAX_SLOTS do
    local cur = current[i]
    local nxt = target[i]
    local nxt_key = slot_key(nxt)
    if cur ~= nxt or current_keys[i] ~= nxt_key then
      if nxt then
        terminal.set_slot(i, nxt.nudged_bg, nxt.opacity)
      else
        terminal.clear_slot(i)
      end
      current[i] = nxt
      current_keys[i] = nxt_key
      emitted = emitted + 1
    end
  end
  if emitted > 0 then
    signals.emit(signals.SLOTS_CHANGED)
  end
  return emitted
end

--- Clear every occupied slot. Used on shutdown after the color stack pop
--- (defence in depth — pop should already restore everything).
function M.clear_all()
  local changed = false
  for i = 1, M.MAX_SLOTS do
    if current[i] then
      terminal.clear_slot(i)
      current[i] = nil
      current_keys[i] = nil
      changed = true
    end
  end
  if changed then
    signals.emit(signals.SLOTS_CHANGED)
  end
end

---@nodiscard
---@return table<integer, prism.Registration|nil>
function M.snapshot()
  local out = {}
  for i = 1, M.MAX_SLOTS do
    out[i] = current[i]
  end
  return out
end

--- Reset internal state. Test-only.
function M._reset()
  current = {}
  current_keys = {}
end

return M
