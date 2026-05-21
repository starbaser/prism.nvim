# nvf module for prism.nvim.
#
# Import into your nvf configuration:
#   imports = [ inputs.prism.nvfModules.default ];
#
# Then configure:
#   vim.prism = {
#     enable = true;
#     groups = [
#       { name = "NormalFloat"; opacity = 0.9; }
#       { name = "CursorLine";  opacity = 0.8; }
#     ];
#     colors = [
#       { color = "#1c1b19"; opacity = 0.3; }
#     ];
#   };
{prism-nvim}: {
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkOption mkIf types;
  inherit (lib.nvim.lua) toLuaObject;

  cfg = config.vim.prism;

  groupSubmodule = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "Highlight group name to register.";
      };
      opacity = mkOption {
        type = types.either types.float types.int;
        description = "Opacity 0.0..1.0 (or -1 to use kitty's background_opacity).";
      };
    };
  };

  colorSubmodule = types.submodule {
    options = {
      color = mkOption {
        type = types.either types.str types.int;
        description = ''
          24-bit RGB color: integer (0xRRGGBB) or string ("#RRGGBB").
          Matched against the effective background of any cell — kitty
          composites cells whose bg equals this value at the given opacity.
        '';
      };
      opacity = mkOption {
        type = types.either types.float types.int;
        description = "Opacity 0.0..1.0 (or -1 to use kitty's background_opacity).";
      };
    };
  };

  luaSpec = toLuaObject {
    groups = cfg.groups;
    colors = cfg.colors;
    debounce_ms = cfg.debounceMs;
  };
in {
  options.vim.prism = {
    enable = mkEnableOption "prism dynamic kitty transparent-background slot manager";

    pluginPackage = mkOption {
      type = types.package;
      default = prism-nvim;
      description = "The prism.nvim plugin package.";
    };

    groups = mkOption {
      type = types.listOf groupSubmodule;
      default = [];
      description = ''
        Highlight groups to register, in priority order. Each becomes a
        candidate for one of kitty's seven transparent_background_color
        slots when visible on screen. Group bg is nudged by registration
        index so kitty's color-keyed transparency matcher has a unique key
        per group.
      '';
    };

    colors = mkOption {
      type = types.listOf colorSubmodule;
      default = [];
      description = ''
        Raw 24-bit colors to register, in priority order. Used verbatim
        as kitty slot keys — no nudge — so cells with the exact matching
        bg get the configured opacity. Colors are registered before groups,
        so group nudges step around any reserved raw value.
      '';
    };

    debounceMs = mkOption {
      type = types.int;
      default = 50;
      description = ''
        Coalesce visibility-rescan events within this window (ms).
        Lower = more reactive but more work; higher = smoother under
        rapid event bursts (typing, scrolling).
      '';
    };

    extraSetup = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Extra Lua executed immediately after `require('prism').setup(...)`.
        Useful for dynamic registrations via prism.register / prism.register_color.
      '';
    };
  };

  config = mkIf cfg.enable {
    # vim.schedule defers setup until after the colorscheme module has
    # applied its `:colorscheme` call — registry.register() reads the
    # colorscheme's intended bg values rather than the pre-scheme default.
    vim.extraPlugins.prism = {
      package = cfg.pluginPackage;
      setup = ''
        vim.schedule(function()
          require('prism').setup(${luaSpec})
          ${cfg.extraSetup}
        end)
      '';
    };
  };
}
