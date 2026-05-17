--- eigenplug.logging: structured ring buffer with vim.notify facade.

---@class eigenplug.LogEntry
---@field ts    number    monotonic ms (vim.uv.hrtime() / 1e6)
---@field level integer   vim.log.levels.*
---@field msg   string    raw message
---@field seq   integer   monotonic counter

local M = {}

local CAPACITY = 500
local ring = {} ---@type eigenplug.LogEntry[]
local head = 1
local count = 0
local seq = 0
local subscribers = {} ---@type fun(entry: eigenplug.LogEntry)[]

---@param entry eigenplug.LogEntry
local function push(entry)
  ring[head] = entry
  head = (head % CAPACITY) + 1
  if count < CAPACITY then
    count = count + 1
  end
end

---@nodiscard
---@return eigenplug.LogEntry[]
function M.get_all()
  if count == 0 then
    return {}
  end
  local result = {}
  local start = (count < CAPACITY) and 1 or head
  for i = 0, count - 1 do
    local idx = ((start - 1 + i) % CAPACITY) + 1
    result[#result + 1] = ring[idx]
  end
  return result
end

function M.clear()
  ring = {}
  head = 1
  count = 0
end

---@param fn fun(entry: eigenplug.LogEntry)
function M.on_change(fn)
  subscribers[#subscribers + 1] = fn
end

---@param fn fun(entry: eigenplug.LogEntry)
function M.off_change(fn)
  for i, sub in ipairs(subscribers) do
    if sub == fn then
      table.remove(subscribers, i)
      return
    end
  end
end

---@param level integer vim.log.levels.*
---@param msg string
local function emit(level, msg)
  seq = seq + 1
  local entry = {
    ts = vim.uv.hrtime() / 1e6,
    level = level,
    msg = msg,
    seq = seq,
  }
  push(entry)

  for _, fn in ipairs(subscribers) do
    fn(entry)
  end

  if level ~= vim.log.levels.DEBUG then
    vim.notify(msg, level, { title = "eigenplug" })
  end
end

---@param msg string
function M.info(msg) emit(vim.log.levels.INFO, msg) end

---@param msg string
function M.warn(msg) emit(vim.log.levels.WARN, msg) end

---@param msg string
function M.error(msg) emit(vim.log.levels.ERROR, msg) end

---@param msg string
function M.debug(msg) emit(vim.log.levels.DEBUG, msg) end

return M
