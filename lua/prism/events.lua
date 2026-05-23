--- prism.events: debounced autocommand wiring that drives the slot reconciler.

local registry = require("prism.registry")
local scanner = require("prism.scanner")
local slots = require("prism.slots")
local stats = require("prism.stats")
local terminal = require("prism.terminal")

local M = {}

local AUGROUP = "prism"
M.debounce_ms = 50
M.max_refresh_hz = 20
M.burst_window_ms = 100
M.burst_event_threshold = 8
M.burst_quiet_ms = 150

---@type uv.uv_timer_t?
local refresh_timer = nil
---@type uv.uv_timer_t?
local quiet_timer = nil
local refresh_timer_active = false
local pending = false
local burst_mode = false
local last_refresh_ms = 0
local recent_events = {} ---@type number[]

local function count_keys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function do_refresh()
  local registered = registry.visibility_targets()
  local t0 = vim.uv.hrtime()
  local visible = scanner.collect_visible(registered)
  local desired = registry.filter_visible(visible, slots.MAX_SLOTS)
  local t1 = vim.uv.hrtime()
  stats.record_scan(t1 - t0, count_keys(visible))

  local emitted = slots.reconcile(desired)
  local t2 = vim.uv.hrtime()
  stats.record_reconcile(t2 - t1, #desired, emitted)
  last_refresh_ms = vim.uv.hrtime() / 1e6
end

---@return uv.uv_timer_t?
local function get_refresh_timer()
  if refresh_timer and not refresh_timer:is_closing() then return refresh_timer end
  refresh_timer = vim.uv.new_timer()
  return refresh_timer
end

---@return uv.uv_timer_t?
local function get_quiet_timer()
  if quiet_timer and not quiet_timer:is_closing() then return quiet_timer end
  quiet_timer = vim.uv.new_timer()
  return quiet_timer
end

local function stop_refresh_timer()
  if refresh_timer and not refresh_timer:is_closing() then
    refresh_timer:stop()
  end
  refresh_timer_active = false
end

local function stop_quiet_timer()
  if quiet_timer and not quiet_timer:is_closing() then
    quiet_timer:stop()
  end
end

local function run_pending()
  stop_refresh_timer()
  if not pending then return end
  pending = false
  do_refresh()
end

---@param delay integer
---@param reset boolean
local function start_refresh_timer(delay, reset)
  local t = get_refresh_timer()
  if not t then
    run_pending()
    return
  end
  if reset then t:stop() end
  if refresh_timer_active and not reset then return end
  refresh_timer_active = true
  t:start(delay, 0, vim.schedule_wrap(run_pending))
end

local function exit_burst_after_quiet()
  stop_quiet_timer()
  if pending then run_pending() end
  if burst_mode then
    burst_mode = false
    recent_events = {}
    stats.record_burst_exit()
  end
end

local function start_quiet_timer()
  local t = get_quiet_timer()
  if not t then return end
  t:stop()
  t:start(M.burst_quiet_ms, 0, vim.schedule_wrap(exit_burst_after_quiet))
end

---@param now_ms number
---@return boolean entered_burst
local function record_recent_event(now_ms)
  recent_events[#recent_events + 1] = now_ms
  local cutoff = now_ms - M.burst_window_ms
  local first = 1
  while recent_events[first] and recent_events[first] < cutoff do
    first = first + 1
  end
  if first > 1 then
    for i = first, #recent_events do
      recent_events[i - first + 1] = recent_events[i]
    end
    for i = #recent_events, #recent_events - first + 2, -1 do
      recent_events[i] = nil
    end
  end

  if not burst_mode and #recent_events >= M.burst_event_threshold then
    burst_mode = true
    stats.record_burst_enter()
    return true
  end
  return false
end

--- Coalesce many events into a single refresh after `debounce_ms` idle.
---@param opts? { force: boolean }
function M.schedule_refresh(opts)
  local force = opts and opts.force == true
  local was_pending = pending or refresh_timer_active
  pending = true
  stats.record_event(was_pending)

  if force then
    stop_refresh_timer()
    stop_quiet_timer()
    if burst_mode then
      burst_mode = false
      recent_events = {}
      stats.record_burst_exit()
    end
    run_pending()
    return
  end

  local now_ms = vim.uv.hrtime() / 1e6
  local entered_burst = record_recent_event(now_ms)

  if burst_mode then
    if entered_burst then stop_refresh_timer() end
    local min_interval = 1000 / math.max(M.max_refresh_hz, 1)
    local elapsed = now_ms - last_refresh_ms
    local delay = math.max(0, math.ceil(min_interval - elapsed))
    if refresh_timer_active then
      stats.record_capped_refresh()
    else
      start_refresh_timer(delay, false)
    end
    start_quiet_timer()
    return
  end

  start_refresh_timer(M.debounce_ms, true)
end

function M.force_refresh()
  M.schedule_refresh({ force = true })
end

local REFRESH_EVENTS = {
  "WinScrolled",
  "WinResized",
  "BufWinEnter",
  "WinEnter",
  "TextChanged",
  "TextChangedI",
  "TextChangedT",
  "DiagnosticChanged",
  "ModeChanged",
  "TabEnter",
}

---@param opts { debounce_ms: integer, max_refresh_hz?: integer, burst_window_ms?: integer, burst_event_threshold?: integer, burst_quiet_ms?: integer }
function M.attach(opts)
  M.debounce_ms = opts.debounce_ms
  M.max_refresh_hz = opts.max_refresh_hz or M.max_refresh_hz
  M.burst_window_ms = opts.burst_window_ms or M.burst_window_ms
  M.burst_event_threshold = opts.burst_event_threshold or M.burst_event_threshold
  M.burst_quiet_ms = opts.burst_quiet_ms or M.burst_quiet_ms

  vim.api.nvim_create_augroup(AUGROUP, { clear = true })

  for _, ev in ipairs(REFRESH_EVENTS) do
    vim.api.nvim_create_autocmd(ev, {
      group = AUGROUP,
      callback = M.schedule_refresh,
    })
  end

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = AUGROUP,
    callback = function()
      registry.on_colorscheme()
      scanner.on_colorscheme()
      M.force_refresh()
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = AUGROUP,
    callback = function()
      terminal.pop()
    end,
  })
end

--- Tear down autocommands. Used by :PrismDisable.
function M.detach()
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  pending = false
  burst_mode = false
  recent_events = {}
  if refresh_timer then
    refresh_timer:stop()
    refresh_timer:close()
    refresh_timer = nil
  end
  if quiet_timer then
    quiet_timer:stop()
    quiet_timer:close()
    quiet_timer = nil
  end
  refresh_timer_active = false
end

return M
