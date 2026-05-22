# `prism.nvim` 💠

Compute optimal chroma-key for Neovim using kitty’s color stack protoclol

Implements OSC 30001 (push), OSC 30101 (pop), and OSC 21 color query/set per the
[kitty color-stack protocol][kitty-protocol].

[kitty-protocol]: https://sw.kovidgoyal.net/kitty/color-stack/

## Layout

```
.
├── flake.nix
├── justfile
├── lua/prism/
│   └── init.lua
├── plugin/prism.lua
└── tests/
    ├── helpers.lua
    └── minimal_init.lua
```

## Quickstart

```sh
direnv allow
just lua-test
```
