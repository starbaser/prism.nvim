# `prism.nvim` 💠

Multi-faceted highlight group-based chroma keying for Neovim via
[kitty’s graphics protocol color stack][kitty-protocol].

![prism.nvim demo](https://raw.githubusercontent.com/starbaser/prism.nvim/main/demo.gif)

[kitty-protocol]: https://sw.kovidgoyal.net/kitty/color-stack/

## Requirements

- Neovim running inside kitty
- The following options in your `kitty.conf`:

```conf
dynamic_background_opacity yes
background_opacity 0.9 # must be < 1.0
# Optionally:
background_blur 64 # Any value > 0
```

> [!NOTE] `prism.nvim` is disabled when `$TERM` is not `xterm-kitty`

## Quickstart

```lua
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("prism_setup", { clear = true }),
  callback = function()
    vim.schedule(function()
      require("prism").setup({
        registrations = {
          { target = "NormalFloat", opacity = 0.80, priority = 30 },
          { target = "CursorLine", opacity = 0.80, priority = 20 },
          { target = "RenderMarkdownCode", opacity = 0.83, priority = 10 },
        },
      })
    end)
  end,
})

vim.cmd.colorscheme("srcery")
```

`registrations` are targets `prism.nvim` should watch.
Targets are highlight group names or raw 24-bit colors.
When a registered target is visible, `prism.nvim` assigns its background to one of kitty’s seven
`transparent_background_color` slots.
`opacity` is the value sent to kitty for that slot.
Higher `priority` values are selected first; ties keep first-registration order.

```lua
require("prism").setup({
  registrations = {
    { target = "NormalFloat", opacity = 0.80, priority = 20 },
    { target = "#30302f", opacity = 0.83, priority = 10 },
  },
})
```

String targets matching `#RRGGBB` or `RRGGBB`, and numeric targets like `0x30302f`, are raw colors.
All other strings are highlight groups.
Raw colors are used verbatim.
Highlight-group backgrounds are nudged only when Prism needs distinct kitty color keys for different
opacity entries.

## Dynamic Highlights

Use `setup({ registrations = ... })` for static configuration.
Use `register()` when your config computes or rewrites highlight groups inside a `ColorScheme`
callback:

```lua
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("eigen_srcery_overrides", { clear = true }),
  pattern = "srcery",
  callback = function()
    eigen.hl.update("RenderMarkdownCode", { bg = eigen.srcery.colors.gray2 })
    eigen.hl.update("CursorLine", { bg = eigen.srcery.colors.gray2 })

    vim.schedule(function()
      local prism = require("prism")
      prism.register("NormalFloat", 0.80, 30)
      prism.register("CursorLine", 0.80, 20)
      prism.register("RenderMarkdownCode", 0.83, 10)
      prism.register("#30302f", 0.83)
    end)
  end,
})

vim.g.srcery_normal_float = 1
vim.cmd.colorscheme("srcery")
```

`register(target, opacity, priority?)` is atomic: calling it again for the same highlight group or
raw color updates the existing registration in place.

## Installation

### `lazy.nvim`

```lua
{
  "starbaser/prism.nvim",
}
```

Load your colorscheme first, then call `setup()` after the highlight groups have their final
backgrounds.

### Nix Flake

```nix
{
  inputs.prism.url = "github:starbaser/prism.nvim";
}
```

The flake exposes:

- `packages.${system}.default`
- `overlays.default`

#### `nvf`

The flake includes an `nvf` module at `nvfModules.default`.

```nix
{
  inputs.prism.url = "github:starbaser/prism.nvim";

  outputs = {nixpkgs, nvf, prism, ...}: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
  in {
    packages.${system}.default = nvf.lib.neovimConfiguration {
      inherit pkgs;
      modules = [
        prism.nvfModules.default
        {
          vim.prism = {
            enable = true;
            registrations = [
              {target = "NormalFloat"; opacity = 0.80; priority = 30;}
              {target = "CursorLine"; opacity = 0.80; priority = 20;}
              {target = "RenderMarkdownCode"; opacity = 0.83; priority = 10;}
              {target = "#30302f"; opacity = 0.83;}
            ];
          };
        }
      ];
    };
  };
}
```

The module configures `vim.extraPlugins.prism` and schedules `require("prism").setup(...)` after nvf
applies the colorscheme.
It exposes `registrations`, refresh throttling options, and `extraSetup` for runtime-configuration
in Lua.

The scheduled callback matters because Prism reads the live highlight background and writes a nearby
color key back into the group before kitty can match it.

## Lualine

The lualine component renders kitty’s seven Prism slots and opens `:PrismDebug` on click:

```lua
require("lualine").setup({
  sections = {
    lualine_x = {
      {
        "prism",
        slot_icon = "󰜌 ",
        empty_icon = "·",
        show_empty = true,
      },
    },
  },
})
```

## Commands

```vim
:PrismEnable
:PrismDisable
:PrismToggle
:PrismRefresh
:PrismDebug
```

## Development

```sh
direnv allow
just lua-test
just check
```
