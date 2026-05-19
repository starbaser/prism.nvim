-- Shared test utilities.

local M = {}

---@class prism.test.Spy
---@field calls any[][]
---@field call_count integer
---@field original? function

---@param original? function
---@return prism.test.Spy spy
---@return function wrapper
function M.spy(original)
  ---@type prism.test.Spy
  local s = { calls = {}, call_count = 0, original = original }
  local function wrapper(...)
    s.call_count = s.call_count + 1
    table.insert(s.calls, { ... })
    if original then return original(...) end
  end
  return s, wrapper
end

return M
