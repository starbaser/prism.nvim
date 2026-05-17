# eigenplug.nvim

Neovim Lua plugin template. Nix-flake-based with a lightweight mini.test
runner, gen-luarc-generated `.luarc.json`, and a working example module
(structured ring-buffer logging with subscribers).

## Layout

```
.
├── flake.nix                  # gen-luarc, nvim-test wrapper, vimPlugin, checks
├── justfile                   # lua-test, lua-test-file, lua-test-watch, check, build
├── lua/eigenplug/
│   ├── init.lua               # plugin entrypoint, M.setup()
│   └── logging.lua            # example: ring buffer + subscribers
├── plugin/eigenplug.lua       # <Plug> mappings and :Eigenplug command
├── scripts/rename.sh          # rename eigenplug → <your-name>
└── tests/
    ├── helpers.lua            # spy helper
    ├── minimal_init.lua       # rtp propagation for child neovim
    └── test_logging.lua       # example mini.test suite
```

## Quickstart

```sh
# 1. Copy and rename
cp -r ~/dev/projects/eigenplug.nvim ~/dev/projects/foobar.nvim
cd ~/dev/projects/foobar.nvim
bash scripts/rename.sh foobar
rm -rf .git

# 2. Enter dev shell (materializes .luarc.json, exports EIGENPLUG_ROOT)
direnv allow            # if using direnv
# or
nix develop

# 3. Run tests
just lua-test

# 4. Init git
git init && git add . && git commit -m "initial commit"
```

## Architecture notes

### Test runner

`flake.nix` produces a `nvim-test` wrapper around upstream
`neovim-unwrapped` + `mini.nvim` only. Tests do not depend on a
configured Neovim or any other plugins, so they stay isolated to your
plugin's modules.

`EIGENPLUG_TEST_RTP` is exported by the wrapper and read by
`tests/minimal_init.lua`. Required so `MiniTest.new_child_neovim()`
spawns inherit `mini.nvim` availability — the env var crosses process
boundaries, the `--cmd` flag does not.

`EIGENPLUG_ROOT` is exported by the dev shell `shellHook` and used by
`minimal_init.lua` to locate the plugin source. Falls back to
`<sfile>` path resolution when unset.

### Adding an external plugin dependency

When a new module does `require('snacks')` or similar, add the
corresponding `pkgs.vimPlugins.X` to `luarc.plugins` in `flake.nix` so
lua-language-server can resolve it for go-to-definition.

```nix
luarc = pkgs.mk-luarc {
  nvim = pkgs.neovim-unwrapped;
  lua-version = "jit51";
  plugins = with pkgs.vimPlugins; [
    mini-nvim
    snacks-nvim    # <— new dep
  ];
};
```

Then `direnv reload` (or re-enter the dev shell) to regenerate
`.luarc.json`.

### Test patterns

Three patterns appear in `tests/test_logging.lua`:

1. **Child neovim** — `MiniTest.new_child_neovim():restart()` in
   `pre_case`. Necessary when modules carry persistent state (like the
   ring buffer in `logging.lua`) or touch `vim.notify`, autocmds, etc.

2. **Module-level require** — for pure functions, skip `child` and
   `require()` at the top of the test file. Faster, simpler. See
   talkstream's `test_router.lua` / `test_jsonrpc.lua` for examples.

3. **`package.loaded[...]` mocking** — to stub a dependency before the
   SUT loads:
   ```lua
   child.lua([[
     package.loaded["eigenplug.socket"] = nil
     package.loaded["eigenplug.client"] = nil
     package.loaded["eigenplug.socket"] = { send = function() ... end }
     _G._Client = require("eigenplug.client")
   ]])
   ```

### Commit conventions

This template follows [Conventional Commits](https://www.conventionalcommits.org/).

## License

Whatever you want — strip this section when you fork.
