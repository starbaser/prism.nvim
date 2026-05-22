--- prism.lualine: statusline renderer for Prism's seven kitty slots.

local slots = require("prism.slots")

local M = {}

local EMPTY_HL = "PrismSlotEmpty"
local COLOR_HL_PREFIX = "PrismSlotColor_"

local defaults = {
  slot_icon = "󰜌 ",
  empty_icon = "·",
  slot_separator = "",
  show_empty = true,
}

---@return table
function M.default_options()
  return vim.deepcopy(defaults)
end

local function ensure_empty_highlight()
  vim.cmd("highlight default link " .. EMPTY_HL .. " Comment")
end

---@param rgb integer
---@return string
local function color_highlight(rgb)
  local name = string.format("%s%06x", COLOR_HL_PREFIX, rgb)
  vim.api.nvim_set_hl(0, name, { fg = rgb })
  return name
end

---@param text string
---@return string
local function escape_status_text(text)
  return text:gsub("%%", "%%%%")
end

---@param group string
---@param text string
---@return string
local function segment(group, text)
  return "%#" .. group .. "#" .. escape_status_text(text)
end

---@param reg prism.Registration
---@return string
local function slot_highlight(reg)
  if reg.name then
    return reg.name
  end
  return color_highlight(reg.nudged_bg)
end

---@param options? table
---@return table
local function normalize_options(options)
  return vim.tbl_extend("force", defaults, options or {})
end

---@param options? table
---@param state? { slots: table<integer, prism.Registration|nil> }
---@return string
function M.render(options, state)
  local opts = normalize_options(options)
  local status = state or require("prism").status()
  local pieces = {}

  ensure_empty_highlight()

  for i = 1, slots.MAX_SLOTS do
    local reg = status.slots[i]
    if reg then
      pieces[#pieces + 1] = segment(slot_highlight(reg), opts.slot_icon)
    elseif opts.show_empty then
      pieces[#pieces + 1] = segment(EMPTY_HL, opts.empty_icon)
    end
  end

  return table.concat(pieces, opts.slot_separator)
end

return M
