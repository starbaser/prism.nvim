--- prism.debug: floating slot/stat diagnostics.

local signals = require("prism.signals")

local M = {}

local FILETYPE = "prism-debug"
local NS = vim.api.nvim_create_namespace("prism_debug_float")
local COLOR_HL_PREFIX = "PrismDebugColor_"
local DEFAULT_REFRESH_INTERVAL_MS = 1000

---@class prism.debug.State
---@field buf integer?
---@field win integer?
---@field augroup integer?
---@field timer uv.uv_timer_t?

---@type prism.debug.State
local state = {}

local function win_valid()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function buf_valid()
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

local function stop_timer()
  local timer = state.timer
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  state.timer = nil
end

---@param rgb integer
---@return string
local function color_highlight(rgb)
  local name = string.format("%s%06x", COLOR_HL_PREFIX, rgb)
  vim.api.nvim_set_hl(0, name, { fg = rgb })
  return name
end

---@param buf integer
---@return boolean
local function is_debug_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  return vim.b[buf].prism_debug_float == true
    or vim.bo[buf].filetype == FILETYPE
end

---@param except_win? integer
local function close_debug_windows(except_win)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= except_win and vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if is_debug_buffer(buf) then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
end

---@param except_buf? integer
local function delete_debug_buffers(except_buf)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= except_buf and is_debug_buffer(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

---@param status { registrations: prism.Registration[], slots: table<integer, prism.Registration|nil> }
---@return table<prism.Registration, integer>
local function slot_lookup(status)
  local lookup = {}
  for slot, reg in pairs(status.slots or {}) do
    if reg then
      lookup[reg] = slot
    end
  end
  return lookup
end

---@param reg prism.Registration
---@return string label
---@return string? hl_group
local function registration_label(reg)
  if reg.name then
    return reg.name, reg.name
  end
  return string.format("#%06x", reg.nudged_bg), color_highlight(reg.nudged_bg)
end

---@param bucket { count: integer, last_us: number, mean_us: number, min_us: number, max_us: number }
---@return string
local function bucket_row(name, bucket)
  return string.format(
    "| %s | %d | %.1f | %.1f | %.1f | %.1f |",
    name,
    bucket.count,
    bucket.last_us,
    bucket.mean_us,
    bucket.min_us,
    bucket.max_us
  )
end

---@param name string
---@param value any
---@return string
local function counter_row(name, value)
  return string.format("| %s | %s |", name, tostring(value))
end

---@param s prism.stats.Snapshot
---@return string[]
local function stats_lines(s)
  return {
    "| metric | count | last_us | mean_us | min_us | max_us |",
    "| --- | ---: | ---: | ---: | ---: | ---: |",
    bucket_row("scan", s.scan),
    bucket_row("reconcile", s.reconcile),
    "",
    "| counter | value |",
    "| --- | ---: |",
    counter_row("emissions", s.emissions),
    counter_row("last_visible", s.last_visible_count),
    counter_row("last_desired", s.last_desired_count),
    counter_row("events", s.events),
    counter_row("merged_events", s.merged_events),
    counter_row("capped_refreshes", s.capped_refreshes),
    counter_row("burst_entries", s.burst_entries),
    counter_row("burst_active", s.burst_active),
  }
end

---@return string[] lines
---@return table[] highlights
local function content()
  local prism = require("prism")
  local status = prism.status()
  local slots = slot_lookup(status)
  local lines = {}
  local highlights = {}

  if #status.registrations == 0 then
    lines[#lines + 1] = "(no registered groups)"
    highlights[#highlights + 1] = {
      row = #lines - 1,
      col = 0,
      end_col = #lines[#lines],
      hl_group = "Comment",
    }
  else
    for _, reg in ipairs(status.registrations) do
      local label, hl_group = registration_label(reg)
      local slot = slots[reg]
      local prefix = string.format("%s  ", slot and tostring(slot) or "-")
      lines[#lines + 1] = prefix .. label
      if hl_group then
        highlights[#highlights + 1] = {
          row = #lines - 1,
          col = #prefix,
          end_col = #prefix + #label,
          hl_group = hl_group,
        }
      end
    end
  end

  lines[#lines + 1] = ""
  vim.list_extend(lines, stats_lines(prism.stats()))
  return lines, highlights
end

---@param lines string[]
---@return integer
local function list_width(lines)
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  return math.min(width, math.max(1, vim.o.columns - 2))
end

---@param lines string[]
---@return integer
local function list_height(lines)
  return math.min(#lines, math.max(1, vim.o.lines - 4))
end

local function ensure_buffer()
  if buf_valid() then return end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.b[state.buf].prism_debug_float = true
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = FILETYPE
  vim.keymap.set("n", "q", M.close, { buffer = state.buf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = state.buf, silent = true, nowait = true })
end

---@param lines string[]
---@param highlights table[]
local function render_buffer(lines, highlights)
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)

  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(state.buf, NS, hl.row, hl.col, {
      end_col = hl.end_col,
      hl_group = hl.hl_group,
      priority = 100,
    })
  end

  vim.bo[state.buf].modifiable = false
end

local function attach_autocmds()
  if state.augroup then return end
  state.augroup = vim.api.nvim_create_augroup("prism_debug_float", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = state.augroup,
    pattern = { signals.REGISTRY_CHANGED, signals.SLOTS_CHANGED },
    callback = function()
      if win_valid() then M.refresh() end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = state.augroup,
    callback = function()
      if win_valid() then M.refresh() end
    end,
  })
end

function M.refresh()
  if not win_valid() or not buf_valid() then return end

  local lines, highlights = content()
  render_buffer(lines, highlights)

  vim.api.nvim_win_set_config(state.win, {
    relative = "editor",
    row = 1,
    col = 1,
    width = list_width(lines),
    height = list_height(lines),
    style = "minimal",
    border = "none",
  })
  vim.wo[state.win].wrap = false
end

---@param refresh_interval_ms integer?
local function start_timer(refresh_interval_ms)
  stop_timer()

  local interval = tonumber(refresh_interval_ms) or DEFAULT_REFRESH_INTERVAL_MS
  if interval <= 0 then return end

  local timer = vim.uv.new_timer()
  if not timer then return end
  state.timer = timer
  timer:start(interval, interval, vim.schedule_wrap(function()
    if win_valid() and buf_valid() then
      M.refresh()
    else
      stop_timer()
    end
  end))
  if timer.unref then timer:unref() end
end

---@param opts? table
---@return integer win
function M.open(opts)
  opts = opts or {}
  local win_opts = vim.deepcopy(opts)
  local refresh_interval_ms = win_opts.refresh_interval_ms
  win_opts.refresh_interval_ms = nil

  if win_valid() then
    close_debug_windows(state.win)
    delete_debug_buffers(state.buf)
  else
    close_debug_windows()
    delete_debug_buffers()
  end
  ensure_buffer()

  local lines, highlights = content()
  render_buffer(lines, highlights)

  if not win_valid() then
    state.win = vim.api.nvim_open_win(state.buf, true, vim.tbl_extend("force", {
      relative = "editor",
      row = 1,
      col = 1,
      width = list_width(lines),
      height = list_height(lines),
      style = "minimal",
      border = "none",
      zindex = 60,
    }, win_opts))
    vim.wo[state.win].wrap = false
  else
    M.refresh()
    vim.api.nvim_set_current_win(state.win)
  end

  attach_autocmds()
  start_timer(refresh_interval_ms)
  return state.win
end

function M.close()
  stop_timer()
  close_debug_windows()
  delete_debug_buffers()
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
  else
    pcall(vim.api.nvim_del_augroup_by_name, "prism_debug_float")
  end
  state = {}
end

---@param opts? table
function M.toggle(opts)
  if win_valid() then
    M.close()
  else
    M.open(opts)
  end
end

return M
