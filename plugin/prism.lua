--- prism.nvim

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
    if r.kind == "color" then
      lines[#lines + 1] = string.format(
        "  [%d p=%.3g] (color)        opacity=%.3f  bg=#%06x",
        r.index,
        r.priority,
        r.opacity,
        r.nudged_bg
      )
    else
      lines[#lines + 1] = string.format(
        "  [%d p=%.3g] %-16s opacity=%.3f  bg=#%06x (orig #%06x)",
        r.index,
        r.priority,
        r.group,
        r.opacity,
        r.nudged_bg,
        r.original_bg
      )
    end
  end
  lines[#lines + 1] = "slots:"
  for i = 1, 7 do
    local r = s.slots[i]
    lines[#lines + 1] = string.format("  %d -> %s", i, r and r.target or "(empty)")
  end
  vim.api.nvim_echo(
    vim.tbl_map(function(l)
      return { l, "Normal" }
    end, lines),
    false,
    {}
  )
end, { desc = "prism: print current registrations and slot occupancy" })

vim.api.nvim_create_user_command("PrismDisable", function()
  require("prism").disable()
end, { desc = "prism: detach autocommands and restore kitty color stack" })

vim.api.nvim_create_user_command("PrismEnable", function()
  require("prism").enable()
end, { desc = "prism: attach autocommands and push kitty color stack" })

vim.api.nvim_create_user_command("PrismToggle", function()
  require("prism").toggle()
end, { desc = "prism: toggle kitty slot management" })

vim.api.nvim_create_user_command("PrismStats", function()
  local s = require("prism").stats()
  local lines = {
    "prism stats:",
    string.format(
      "  scan      count=%-6d  last=%7.1fus  mean=%7.1fus  min=%7.1fus  max=%7.1fus",
      s.scan.count,
      s.scan.last_us,
      s.scan.mean_us,
      s.scan.min_us,
      s.scan.max_us
    ),
    string.format(
      "  reconcile count=%-6d  last=%7.1fus  mean=%7.1fus  min=%7.1fus  max=%7.1fus",
      s.reconcile.count,
      s.reconcile.last_us,
      s.reconcile.mean_us,
      s.reconcile.min_us,
      s.reconcile.max_us
    ),
    string.format(
      "  emissions=%d  last_visible=%d  last_desired=%d",
      s.emissions,
      s.last_visible_count,
      s.last_desired_count
    ),
    string.format(
      "  events=%d  merged=%d  capped=%d  bursts=%d  burst_active=%s",
      s.events,
      s.merged_events,
      s.capped_refreshes,
      s.burst_entries,
      tostring(s.burst_active)
    ),
  }
  vim.api.nvim_echo(
    vim.tbl_map(function(l)
      return { l, "Normal" }
    end, lines),
    false,
    {}
  )
end, { desc = "prism: print scan/reconcile timing stats" })

vim.api.nvim_create_user_command("PrismStatsReset", function()
  require("prism").reset_stats()
end, { desc = "prism: clear accumulated timing stats" })

vim.api.nvim_create_user_command("PrismDebug", function()
  require("prism.debug").toggle()
end, { desc = "prism: toggle slot allocation and stats float" })
