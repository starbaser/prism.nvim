-- Byte-exact assertions on OSC escape codes emitted by prism.terminal.

local helpers = dofile("tests/helpers.lua")
local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

local saved_ui_send
local ui_spy

T["terminal"] = new_set({
  hooks = {
    pre_case = function()
      saved_ui_send = vim.api.nvim_ui_send
      local spy, wrapper = helpers.spy()
      ui_spy = spy
      vim.api.nvim_ui_send = wrapper
      package.loaded["prism.terminal"] = nil
    end,
    post_case = function()
      vim.api.nvim_ui_send = saved_ui_send
    end,
  },
})

T["terminal"]["push emits OSC 30001"] = function()
  local terminal = require("prism.terminal")
  terminal.push()
  eq(ui_spy.call_count, 1)
  eq(ui_spy.calls[1][1], "\x1b]30001\x1b\\")
end

T["terminal"]["pop emits OSC 30101"] = function()
  local terminal = require("prism.terminal")
  terminal.pop()
  eq(ui_spy.call_count, 1)
  eq(ui_spy.calls[1][1], "\x1b]30101\x1b\\")
end

T["terminal"]["set_slot encodes color and opacity"] = function()
  local terminal = require("prism.terminal")
  terminal.set_slot(3, 0xabc123, 0.5)
  eq(ui_spy.call_count, 1)
  eq(ui_spy.calls[1][1], "\x1b]21;transparent_background_color3=#abc123@0.500\x1b\\")
end

T["terminal"]["set_slot pads with leading zeros"] = function()
  local terminal = require("prism.terminal")
  terminal.set_slot(1, 0x000001, 0.1)
  eq(ui_spy.calls[1][1], "\x1b]21;transparent_background_color1=#000001@0.100\x1b\\")
end

T["terminal"]["clear_slot emits empty value"] = function()
  local terminal = require("prism.terminal")
  terminal.clear_slot(2)
  eq(ui_spy.call_count, 1)
  eq(ui_spy.calls[1][1], "\x1b]21;transparent_background_color2=\x1b\\")
end

T["terminal"]["is_kitty detects TERM=xterm-kitty"] = function()
  local saved = vim.env.TERM
  vim.env.TERM = "xterm-kitty"
  local terminal = require("prism.terminal")
  eq(terminal.is_kitty(), true)
  vim.env.TERM = saved
end

T["terminal"]["is_kitty detects KITTY_WINDOW_ID"] = function()
  local saved_term = vim.env.TERM
  local saved_kwid = vim.env.KITTY_WINDOW_ID
  vim.env.TERM = "tmux-256color"
  vim.env.KITTY_WINDOW_ID = "1"
  local terminal = require("prism.terminal")
  eq(terminal.is_kitty(), true)
  vim.env.TERM = saved_term
  vim.env.KITTY_WINDOW_ID = saved_kwid
end

T["terminal"]["is_kitty false outside kitty"] = function()
  local saved_term = vim.env.TERM
  local saved_kwid = vim.env.KITTY_WINDOW_ID
  vim.env.TERM = "xterm-256color"
  vim.env.KITTY_WINDOW_ID = nil
  local terminal = require("prism.terminal")
  eq(terminal.is_kitty(), false)
  vim.env.TERM = saved_term
  vim.env.KITTY_WINDOW_ID = saved_kwid
end

return T
