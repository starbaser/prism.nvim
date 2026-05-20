--- prism.terminal: kitty detection and OSC escape code emission.
---
--- Uses vim.api.nvim_ui_send per its docstring contract: the canonical
--- path for writing raw bytes to the TUI host terminal (kitty), distinct
--- from nvim_chan_send (which targets Nvim's own stdout) and io.write
--- (which can interfere with the TUI).

local M = {}

local OSC = "\x1b]"
local ST = "\x1b\\"

---@nodiscard
---@return boolean
function M.is_kitty()
  return vim.env.TERM == "xterm-kitty" or vim.env.KITTY_WINDOW_ID ~= nil
end

---@param data string
local function emit(data)
  vim.api.nvim_ui_send(data)
end

--- Push the current kitty color stack frame (OSC 30001).
function M.push()
  emit(OSC .. "30001" .. ST)
end

--- Pop the previously pushed kitty color stack frame (OSC 30101).
function M.pop()
  emit(OSC .. "30101" .. ST)
end

--- Set transparent_background_colorN to rgb24 with the given opacity.
---@param n integer 1..7
---@param rgb24 integer 24-bit color value
---@param opacity number 0.0..1.0 (or -1 to use kitty's background_opacity)
function M.set_slot(n, rgb24, opacity)
  emit(string.format(
    "%s21;transparent_background_color%d=#%06x@%.3f%s",
    OSC, n, rgb24, opacity, ST
  ))
end

--- Clear transparent_background_colorN by sending an empty value.
---@param n integer 1..7
function M.clear_slot(n)
  emit(string.format(
    "%s21;transparent_background_color%d=%s",
    OSC, n, ST
  ))
end

return M
