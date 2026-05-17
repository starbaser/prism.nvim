--- eigenplug.nvim entry point.

if vim.g.loaded_eigenplug then
  return
end
vim.g.loaded_eigenplug = true

vim.keymap.set("n", "<Plug>(EigenplugHello)",
  function() require("eigenplug").hello() end,
  { desc = "Eigenplug hello" })

vim.api.nvim_create_user_command("Eigenplug", function()
  require("eigenplug").hello()
end, { desc = "Run eigenplug demo" })
