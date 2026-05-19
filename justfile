# Lua tests (mini.test, runs via nvim-test wrapper)

lua-test:
    nvim-test --headless -u tests/minimal_init.lua \
      -c "lua MiniTest.run({ collect = { find_files = function() return vim.fn.globpath('tests', 'test_*.lua', true, true) end } })"

lua-test-file FILE:
    nvim-test --headless -u tests/minimal_init.lua \
      -c "lua MiniTest.run_file('{{FILE}}')"

lua-test-watch:
    watchexec -e lua -w lua -w tests -- just lua-test

# Nix

check:
    nix flake check

build:
    nix build .#default
