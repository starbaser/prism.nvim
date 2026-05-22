--- prism.ui.groups: floating registered-highlight-group list.

local signals = require("prism.signals")

local M = {}

local NS = vim.api.nvim_create_namespace("prism_groups_float")

---@class prism.ui.groups.State
---@field buf integer?
---@field win integer?
---@field augroup integer?

---@type prism.ui.groups.State
local state = {}

local function win_valid()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function buf_valid()
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

---@return string[]
local function registered_names()
  local names = {}
  for _, reg in ipairs(require("prism").status().registrations) do
    if reg.name then
      names[#names + 1] = reg.name
    end
  end
  return names
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
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "prism-groups"
  vim.keymap.set("n", "q", M.close, { buffer = state.buf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", M.close, { buffer = state.buf, silent = true, nowait = true })
end

---@param lines string[]
---@param names string[]
local function render_buffer(lines, names)
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)

  if #names == 0 then
    vim.api.nvim_buf_set_extmark(state.buf, NS, 0, 0, {
      end_col = #lines[1],
      hl_group = "Comment",
      priority = 100,
    })
  else
    for i, name in ipairs(names) do
      vim.api.nvim_buf_set_extmark(state.buf, NS, i - 1, 0, {
        end_col = #name,
        hl_group = name,
        priority = 100,
      })
    end
  end

  vim.bo[state.buf].modifiable = false
end

local function attach_autocmds()
  if state.augroup then return end
  state.augroup = vim.api.nvim_create_augroup("prism_groups_float", { clear = true })
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

  local names = registered_names()
  local lines = #names > 0 and names or { "(no registered groups)" }
  render_buffer(lines, names)

  vim.api.nvim_win_set_config(state.win, {
    relative = "editor",
    row = 1,
    col = 1,
    width = list_width(lines),
    height = list_height(lines),
    style = "minimal",
    border = "none",
  })
end

---@param opts? table
---@return integer win
function M.open(opts)
  opts = opts or {}
  ensure_buffer()

  local names = registered_names()
  local lines = #names > 0 and names or { "(no registered groups)" }
  render_buffer(lines, names)

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
    }, opts))
  else
    M.refresh()
    vim.api.nvim_set_current_win(state.win)
  end

  attach_autocmds()
  return state.win
end

function M.close()
  if win_valid() then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  if buf_valid() then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
  end
  state = {}
end

function M.toggle()
  if win_valid() then
    M.close()
  else
    M.open()
  end
end

return M
