--- prism.scanner: enumerate highlight groups currently visible on screen.
---
--- Uses vim.inspect_pos for per-position resolution — it already merges
--- treesitter captures, syntax stack, semantic tokens, and extmarks and
--- resolves :hi-link chains via hl_group_link.

local M = {}

--- Scan step in columns: 1 = every cell, higher = sparser sampling.
--- Tuneable via setup() for very large screens.
M.scan_step = 1

---@param buf integer
---@param row integer 0-based
---@param col integer 0-based
---@param out table<string, true>
local function collect_at(buf, row, col, out)
  local items = vim.inspect_pos(buf, row, col, {
    syntax = true,
    treesitter = true,
    extmarks = true,
    semantic_tokens = true,
  })
  for _, t in ipairs(items.treesitter) do
    out[t.hl_group_link or t.hl_group] = true
  end
  for _, s in ipairs(items.syntax) do
    out[s.hl_group_link or s.hl_group] = true
  end
  for _, e in ipairs(items.extmarks) do
    if e.opts and e.opts.hl_group then
      out[e.opts.hl_group_link or e.opts.hl_group] = true
    end
  end
  for _, e in ipairs(items.semantic_tokens) do
    if e.opts and e.opts.hl_group then
      out[e.opts.hl_group_link or e.opts.hl_group] = true
    end
  end
end

---@param win integer
---@return integer top 1-based
---@return integer bot 1-based
local function visible_lines(win)
  local pair = vim.api.nvim_win_call(win, function()
    return { vim.fn.line("w0"), vim.fn.line("w$") }
  end)
  return pair[1], pair[2]
end

--- Return the set of highlight group names rendered anywhere across all
--- windows of the current tabpage.
---@nodiscard
---@return table<string, true>
function M.collect_visible()
  local seen = {}
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local top, bot = visible_lines(win)
      local width = vim.api.nvim_win_get_width(win)
      for row = top - 1, bot - 1 do
        for col = 0, width - 1, M.scan_step do
          collect_at(buf, row, col, seen)
        end
      end
    end
  end
  return seen
end

return M
