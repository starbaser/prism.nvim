-- Public Prism lifecycle API and commands.

local MiniTest = require("mini.test")
local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

local prism
local terminal

local function load_prism()
  terminal = {
    pushes = 0,
    pops = 0,
    is_kitty = function() return true end,
    push = function() terminal.pushes = terminal.pushes + 1 end,
    pop = function() terminal.pops = terminal.pops + 1 end,
    set_slot = function() end,
    clear_slot = function() end,
  }

  package.loaded["prism"] = nil
  package.loaded["prism.events"] = nil
  package.loaded["prism.registry"] = nil
  package.loaded["prism.scanner"] = nil
  package.loaded["prism.slots"] = nil
  package.loaded["prism.stats"] = nil
  package.loaded["prism.terminal"] = terminal

  prism = require("prism")
  return prism
end

T["init"] = new_set({
  hooks = {
    pre_case = function()
      load_prism()
    end,
    post_case = function()
      if prism then prism.disable() end
    end,
  },
})

T["init"]["setup enables prism once"] = function()
  eq(prism.setup({}), true)
  eq(prism.status().active, true)
  eq(terminal.pushes, 1)

  eq(prism.enable(), false)
  eq(prism.status().active, true)
  eq(terminal.pushes, 1)
end

T["init"]["disable and enable control the kitty stack"] = function()
  prism.setup({})
  eq(prism.disable(), true)
  eq(prism.status().active, false)
  eq(terminal.pops, 1)

  eq(prism.enable(), true)
  eq(prism.status().active, true)
  eq(terminal.pushes, 2)
end

T["init"]["toggle switches through disable and enable"] = function()
  prism.setup({})
  eq(prism.toggle(), true)
  eq(prism.status().active, false)
  eq(terminal.pops, 1)

  eq(prism.toggle(), true)
  eq(prism.status().active, true)
  eq(terminal.pushes, 2)
end

T["init"]["plugin exposes debug and lifecycle commands"] = function()
  local commands = vim.api.nvim_get_commands({})
  eq(commands.PrismDebug ~= nil, true)
  eq(commands.PrismEnable ~= nil, true)
  eq(commands.PrismDisable ~= nil, true)
  eq(commands.PrismToggle ~= nil, true)
  eq(commands.PrismGroups, nil)
  eq(pcall(vim.cmd, "PrismDebug!"), false)
end

T["init"]["lifecycle commands call the public API"] = function()
  vim.cmd("PrismEnable")
  eq(prism.status().active, true)
  eq(terminal.pushes, 1)

  vim.cmd("PrismToggle")
  eq(prism.status().active, false)
  eq(terminal.pops, 1)

  vim.cmd("PrismToggle")
  eq(prism.status().active, true)
  eq(terminal.pushes, 2)

  vim.cmd("PrismDisable")
  eq(prism.status().active, false)
  eq(terminal.pops, 2)
end

return T
