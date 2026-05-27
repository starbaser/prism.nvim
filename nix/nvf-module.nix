# nvf module for prism.nvim.
#
# Import into your nvf configuration:
#   imports = [ inputs.prism.nvfModules.default ];
#
# Then configure:
#   vim.prism = {
#     enable = true;
#     registrations = [
#       { target = "NormalFloat"; opacity = 0.9; priority = 20; }
#       { target = "CursorLine";  opacity = 0.8; priority = 10; }
#       { target = "#1c1b19"; opacity = 0.3; }
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

  registrationSubmodule = types.submodule {
    options = {
      target = mkOption {
        type = types.either types.str types.int;
        description = ''
          Highlight group name or raw 24-bit RGB color. Integer targets and
          six-digit hex strings ("#RRGGBB" or "RRGGBB") are raw colors; all
          other strings are highlight groups.
        '';
      };
      opacity = mkOption {
        type = types.either types.float types.int;
        description = "Opacity 0.0..1.0 (or -1 to use kitty's background_opacity).";
      };
      priority = mkOption {
        type = types.either types.float types.int;
        default = 0;
        description = "Registration priority. Higher values are selected first.";
      };
    };
  };

  luaSpec = toLuaObject {
    registrations = cfg.registrations;
    debounce_ms = cfg.debounceMs;
    max_refresh_hz = cfg.maxRefreshHz;
    burst_window_ms = cfg.burstWindowMs;
    burst_event_threshold = cfg.burstEventThreshold;
    burst_quiet_ms = cfg.burstQuietMs;
  };
in {
  options.vim.prism = {
    enable = mkEnableOption "prism dynamic kitty transparent-background slot manager";

    pluginPackage = mkOption {
      type = types.package;
      default = prism-nvim;
      description = "The prism.nvim plugin package.";
    };

    registrations = mkOption {
      type = types.listOf registrationSubmodule;
      default = [];
      description = ''
        Prism targets to register. Highlight groups are nudged to nearby
        color keys when they need distinct opacity entries; raw colors stay
        exact. Higher priority registrations are selected first.
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

    maxRefreshHz = mkOption {
      type = types.int;
      default = 20;
      description = "Maximum Prism visibility refresh rate during sustained event bursts.";
    };

    burstWindowMs = mkOption {
      type = types.int;
      default = 100;
      description = "Time window used to detect high-frequency Prism refresh events.";
    };

    burstEventThreshold = mkOption {
      type = types.int;
      default = 8;
      description = "Number of refresh events within burstWindowMs before Prism enters capped burst mode.";
    };

    burstQuietMs = mkOption {
      type = types.int;
      default = 150;
      description = "Quiet period after a burst before Prism runs its final trailing refresh.";
    };

    extraSetup = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Extra Lua executed immediately after `require('prism').setup(...)`.
        Useful for dynamic registrations via prism.register.
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
