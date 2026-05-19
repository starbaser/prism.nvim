---@diagnostic disable: undefined-global, redundant-parameter

-- Minimal init for prism tests.
-- Prepends the project root to rtp and lua/ to package.path so
-- require('prism.*') resolves. Used both by the headless runner
-- and by MiniTest.new_child_neovim():restart().

-- Propagate rtp from PRISM_TEST_RTP env var (set by the nvim-test wrapper).
-- Required so child neovim spawns inherit mini.nvim availability.
local test_rtp = os.getenv('PRISM_TEST_RTP')
if type(test_rtp) == 'string' then
  for entry in test_rtp:gmatch('[^,]+') do
    vim.opt.rtp:prepend(entry)
  end
end

---@type string
local root = os.getenv('PRISM_ROOT')
  or vim.fn.fnamemodify(vim.fn.expand('<sfile>'), ':h:h')
local lua_dir = root .. '/lua'

-- Prepend project root to rtp so plugin/ files auto-source.
vim.opt.rtp:prepend(root)

package.path = lua_dir .. '/?.lua;' .. lua_dir .. '/?/init.lua;' .. package.path
package.cpath = lua_dir .. '/?.so;' .. package.cpath
require('mini.test').setup({})
