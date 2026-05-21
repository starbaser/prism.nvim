--- prism.nvim entry point.

if vim.g.loaded_prism then
  return
end
vim.g.loaded_prism = true

vim.api.nvim_create_user_command("PrismRefresh", function()
  require("prism").refresh()
end, { desc = "prism: rescan visible highlight groups and reconcile slots" })

vim.api.nvim_create_user_command("PrismStatus", function()
  local s = require("prism").status()
  local lines = {
    string.format("prism: active=%s", tostring(s.active)),
    "registrations:",
  }
  for _, r in ipairs(s.registrations) do
    if r.color_only then
      lines[#lines + 1] = string.format(
        "  [%d] (color)        opacity=%.3f  bg=#%06x",
        r.index, r.opacity, r.nudged_bg
      )
    else
      lines[#lines + 1] = string.format(
        "  [%d] %-16s opacity=%.3f  bg=#%06x (orig #%06x)",
        r.index, r.name, r.opacity, r.nudged_bg, r.original_bg
      )
    end
  end
  lines[#lines + 1] = "slots:"
  for i = 1, 7 do
    local r = s.slots[i]
    lines[#lines + 1] = string.format(
      "  %d -> %s",
      i, r and r.name or "(empty)"
    )
  end
  vim.api.nvim_echo(
    vim.tbl_map(function(l) return { l, "Normal" } end, lines),
    false,
    {}
  )
end, { desc = "prism: print current registrations and slot occupancy" })

vim.api.nvim_create_user_command("PrismDisable", function()
  require("prism").disable()
end, { desc = "prism: detach autocommands and restore kitty color stack" })
