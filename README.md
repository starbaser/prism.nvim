# `prism.nvim` 💠

Compute optimal iridescence.

Multi-faceted uncapped highlight group Chroma-keying for Neovim using
[kitty’s graphic protocol’s color stack][kitty-protocol].

![prism.nvim demo](https://raw.githubusercontent.com/starbaser/prism.nvim/main/demo.gif)

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

Under construction …
