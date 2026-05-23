--- prism.scanner: enumerate highlight groups currently visible on screen.
---
--- Three-tier detection (each tier is correctness-complementary, not
--- redundant — each catches a class of highlight the other tiers cannot):
---
--- Tier 1 — buffer-content scan (ranged, cheap):
---   Per visible window, query a single range of the buffer:
---     * vim.api.nvim_buf_get_extmarks with type="highlight", overlap=true —
---       one call per buffer, covers extmark-backed highlights AND LSP
---       semantic tokens (they're stored as extmarks under
---       nvim.lsp.semantic_tokens.* namespaces).
---     * Query:iter_captures(root, buf, top, bot) per language tree on the
---       buffer's vim.treesitter.highlighter — ranged iteration used by
---       Neovim's own highlighter; cost is O(captures_in_range), not
---       O(rows*cols).
---     * vim.fn.synstack at a sparse column grid per row, ONLY when
---       treesitter isn't attached (legacy syntax fallback).
---
--- Tier 2 — winhighlight translation:
---   A window with `winhighlight=Normal:MyFloatBg` renders its cells with
---   MyFloatBg.bg, not Normal.bg. Tier 1 reports the buffer-anchored group
---   ("Normal"); we translate through the window's winhighlight map before
---   adding to seen.
---
--- Tier 3 — registry-gated window-state augmentation:
---   Some highlight groups (CursorLine, Visual, StatusLine, Pmenu,
---   NormalFloat, ...) exist purely at Neovim's rendering layer and never
---   surface in buffer state — neither extmarks nor treesitter captures
---   carry them. The previous per-cell vim.inspect_pos scanner ALSO never
---   detected these; the gap is structural. We close it with option-gated
---   state checks, but only for groups the user has actually registered.
---   No registration -> no check. This is the principled middle ground
---   between scattershot "all UI groups are visible" and zero detection.

local M = {}

-- hl-name link resolution cache; invalidated on ColorScheme.
local hl_link_cache = {} ---@type table<string, string>
local syntax_cache = {} ---@type table<integer, { changedtick: integer, rows: table<integer, table<string, true>> }>

local RENDER_GROUPS = {
  ColorColumn = true,
  CursorColumn = true,
  CursorLine = true,
  CursorLineFold = true,
  CursorLineNr = true,
  CursorLineSign = true,
  CurSearch = true,
  FloatBorder = true,
  FloatFooter = true,
  FloatTitle = true,
  FoldColumn = true,
  IncSearch = true,
  LineNr = true,
  LineNrAbove = true,
  LineNrBelow = true,
  Normal = true,
  NormalFloat = true,
  NormalNC = true,
  Pmenu = true,
  PmenuExtra = true,
  PmenuExtraSel = true,
  PmenuKind = true,
  PmenuKindSel = true,
  PmenuMatch = true,
  PmenuMatchSel = true,
  PmenuSbar = true,
  PmenuSel = true,
  PmenuThumb = true,
  Search = true,
  SignColumn = true,
  StatusLine = true,
  StatusLineNC = true,
  TabLine = true,
  TabLineFill = true,
  TabLineSel = true,
  TermCursor = true,
  TermCursorNC = true,
  Terminal = true,
  Visual = true,
  VisualNOS = true,
}

---@param name string
---@return string
local function resolve_hl_link(name)
  local cached = hl_link_cache[name]
  if cached ~= nil then return cached end
  local id = vim.api.nvim_get_hl_id_by_name(name)
  local linked = vim.fn.synIDattr(vim.fn.synIDtrans(id), "name")
  if linked == "" then linked = name end
  hl_link_cache[name] = linked
  return linked
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

--- Parse `winhighlight` value like "Normal:MyN,NormalNC:MyNc" into a map.
---@param win integer
---@return table<string, string>
local function parse_winhighlight(win)
  local raw = vim.wo[win].winhighlight or ""
  local map = {}
  for pair in raw:gmatch("[^,]+") do
    local k, v = pair:match("^([^:]+):(.+)$")
    if k and v then map[k] = v end
  end
  return map
end

---@param targets table<string, true>?
---@param name string
---@return boolean
local function wants(targets, name)
  return targets == nil or targets[name] == true
end

---@param out table<string, true>
---@param targets table<string, true>?
---@param name string
local function add_seen(out, targets, name)
  if wants(targets, name) then out[name] = true end
end

---@param targets table<string, true>?
---@param wh table<string, string>
---@return table<string, true>?
local function source_targets(targets, wh)
  if targets == nil then return nil end
  local out = {}
  for name in pairs(targets) do
    out[name] = true
  end
  for src, dst in pairs(wh) do
    if targets[dst] then out[src] = true end
  end
  return out
end

---@param targets table<string, true>?
---@return boolean
local function needs_content_scan(targets)
  if targets == nil then return true end
  for name in pairs(targets) do
    if not RENDER_GROUPS[name] then return true end
  end
  return false
end

---@param buf integer
---@param row1 integer
---@return table<string, true>
local function syntax_row_groups(buf, row1)
  local changedtick = vim.b[buf].changedtick
  local cache = syntax_cache[buf]
  if not cache or cache.changedtick ~= changedtick then
    cache = { changedtick = changedtick, rows = {} }
    syntax_cache[buf] = cache
  end

  local cached = cache.rows[row1]
  if cached then return cached end

  local groups = {}
  local sample_cols = { 1, 20, 40, 60 }
  for _, col in ipairs(sample_cols) do
    local stack = vim.fn.synstack(row1, col)
    if stack then
      for _, sid in ipairs(stack) do
        local nm = vim.fn.synIDattr(vim.fn.synIDtrans(sid), "name")
        if nm and nm ~= "" then groups[nm] = true end
      end
    end
  end
  cache.rows[row1] = groups
  return groups
end

--- Tier 1: buffer-content scan over [top0, bot0] into `raw`.
---@param buf integer
---@param top0 integer
---@param bot0 integer
---@param raw table<string, true>
---@param targets table<string, true>?
local function scan_buffer(buf, top0, bot0, raw, targets)
  if not needs_content_scan(targets) then return end

  local ok, marks = pcall(
    vim.api.nvim_buf_get_extmarks,
    buf, -1, { top0, 0 }, { bot0, -1 },
    { details = true, overlap = true, type = "highlight" }
  )
  if ok and marks then
    for _, m in ipairs(marks) do
      local details = m[4]
      if details and details.hl_group then
        if wants(targets, details.hl_group) then raw[details.hl_group] = true end
      end
    end
  end

  local highlighter = vim.treesitter.highlighter.active[buf]
  if highlighter then
    highlighter.tree:for_each_tree(function(tstree, ltree)
      if not tstree then return end
      local hl_q = highlighter:get_query(ltree:lang())
      local query = hl_q:query()
      if not query then return end
      local lang = ltree:lang()
      for id in query:iter_captures(tstree:root(), buf, top0, bot0 + 1) do
        local capture_name = query.captures[id]
        if capture_name and not vim.startswith(capture_name, "_") then
          local name = resolve_hl_link("@" .. capture_name .. "." .. lang)
          if wants(targets, name) then raw[name] = true end
        end
      end
    end)
    return
  end

  -- Legacy syntax fallback: sparse column grid per row. Syntax stacks are
  -- often line-uniform but not always (e.g. a keyword followed by a string
  -- on the same line), so a handful of sample columns gives reasonable
  -- coverage without resurrecting the per-cell cost.
  for row1 = top0 + 1, bot0 + 1 do
    for nm in pairs(syntax_row_groups(buf, row1)) do
      if wants(targets, nm) then raw[nm] = true end
    end
  end
end

--- Tier 3: per-window state augmentation. Only sets `seen[name]` when the
--- user has actually registered `name` AND the relevant Vim option is set.
---@param seen table<string, true>
---@param win integer
---@param is_current boolean
---@param registered table<string, true>
local function augment_window_state(seen, win, is_current, registered)
  local function add_if(name)
    if registered and registered[name] then seen[name] = true end
  end

  if vim.wo[win].cursorline then
    add_if("CursorLine")
    add_if("CursorLineNr")
    add_if("CursorLineSign")
    add_if("CursorLineFold")
  end
  if vim.wo[win].cursorcolumn then
    add_if("CursorColumn")
  end
  if vim.wo[win].number or vim.wo[win].relativenumber then
    add_if("LineNr")
    add_if("LineNrAbove")
    add_if("LineNrBelow")
    add_if("CursorLineNr")
  end
  if vim.wo[win].signcolumn ~= "no" then
    add_if("SignColumn")
  end
  if vim.wo[win].foldcolumn ~= "0" then
    add_if("FoldColumn")
  end
  if vim.wo[win].colorcolumn ~= "" then
    add_if("ColorColumn")
  end

  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative and cfg.relative ~= "" then
    add_if("NormalFloat")
    add_if("FloatBorder")
    add_if("FloatTitle")
    add_if("FloatFooter")
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype == "terminal" then
    add_if("Terminal")
    if is_current then
      add_if("TermCursor")
    else
      add_if("TermCursorNC")
    end
  end
end

--- Tier 3: editor-global state augmentation.
---@param seen table<string, true>
---@param has_noncurrent boolean
---@param registered table<string, true>
local function augment_global_state(seen, has_noncurrent, registered)
  local function add_if(name)
    if registered and registered[name] then seen[name] = true end
  end

  if vim.o.laststatus > 0 then
    add_if("StatusLine")
    if has_noncurrent then add_if("StatusLineNC") end
  end
  if vim.o.showtabline > 0 then
    add_if("TabLine")
    add_if("TabLineFill")
    add_if("TabLineSel")
  end
  if vim.fn.pumvisible() == 1 then
    add_if("Pmenu")
    add_if("PmenuSel")
    add_if("PmenuKind")
    add_if("PmenuKindSel")
    add_if("PmenuExtra")
    add_if("PmenuExtraSel")
    add_if("PmenuSbar")
    add_if("PmenuThumb")
    add_if("PmenuMatch")
    add_if("PmenuMatchSel")
  end

  local mc = vim.fn.mode():sub(1, 1)
  if mc == "v" or mc == "V" or mc == "\22" then
    add_if("Visual")
    add_if("VisualNOS")
  end

  if vim.v.hlsearch == 1 then
    add_if("Search")
    add_if("CurSearch")
    add_if("IncSearch")
  end
end

--- Return the set of highlight group names currently visible across all
--- windows of the current tabpage.
---@param registered? table<string, true> optional set of registered group
---  names; only these names are evaluated for tier-3 state augmentation.
---@nodiscard
---@return table<string, true>
function M.collect_visible(registered)
  local seen = {}
  local wins = vim.api.nvim_tabpage_list_wins(0)
  local current_win = vim.api.nvim_get_current_win()
  local any_window = false
  local has_noncurrent = false

  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      any_window = true
      local is_current = win == current_win
      if not is_current then has_noncurrent = true end

      local buf = vim.api.nvim_win_get_buf(win)
      local top1, bot1 = visible_lines(win)
      local top0, bot0 = top1 - 1, bot1 - 1

      local wh = parse_winhighlight(win)
      local raw = {}
      scan_buffer(buf, top0, bot0, raw, source_targets(registered, wh))

      for name in pairs(raw) do
        add_seen(seen, registered, wh[name] or name)
      end

      add_seen(seen, registered, wh["Normal"] or "Normal")
      if not is_current then
        add_seen(seen, registered, wh["NormalNC"] or "NormalNC")
      end

      augment_window_state(seen, win, is_current, registered)
    end
  end

  if any_window then
    augment_global_state(seen, has_noncurrent, registered)
  end

  return seen
end

--- Invalidate the hl-link resolution cache. Called from events.lua on
--- ColorScheme — link chains may have been rewritten.
function M.on_colorscheme()
  hl_link_cache = {}
  syntax_cache = {}
end

return M
