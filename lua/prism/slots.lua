--- prism.slots: minimum-diff reconciler for kitty's 7 transparent slots.
---
--- Maintains a local mirror of which registration occupies each kitty slot
--- and emits only the OSC 21 codes needed to converge to a desired state.

local terminal = require("prism.terminal")

local M = {}

M.MAX_SLOTS = 7

---@type table<integer, prism.Registration|nil>
local current = {}

--- Set the new desired registration list. The first `MAX_SLOTS` entries
--- (in registration / priority order) get assigned to slots 1..MAX_SLOTS.
--- Slots whose occupant changed are re-emitted; unchanged slots are left
--- alone so kitty receives only the minimum bytes needed.
---
--- Returns the number of escape codes emitted (set_slot + clear_slot
--- calls). Used by prism.stats for diagnostics.
---@param desired prism.Registration[]
---@return integer emitted
function M.reconcile(desired)
  local emitted = 0
  for i = 1, M.MAX_SLOTS do
    local cur = current[i]
    local nxt = desired[i]
    if cur ~= nxt then
      if nxt then
        terminal.set_slot(i, nxt.nudged_bg, nxt.opacity)
      else
        terminal.clear_slot(i)
      end
      current[i] = nxt
      emitted = emitted + 1
    end
  end
  return emitted
end

--- Clear every occupied slot. Used on shutdown after the color stack pop
--- (defence in depth — pop should already restore everything).
function M.clear_all()
  for i = 1, M.MAX_SLOTS do
    if current[i] then
      terminal.clear_slot(i)
      current[i] = nil
    end
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
end

return M
