{
  description = "prism — kitty color stack escape codes for Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    gen-luarc = {
      url = "github:mrcjkb/nix-gen-luarc-json";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, gen-luarc, ... }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];

      perSystem = forAllSystems (system:
        let
          pkgs = (nixpkgs.legacyPackages.${system}).extend gen-luarc.overlays.default;

          vimPlugin = pkgs.vimUtils.buildVimPlugin {
            pname = "prism.nvim";
            version = "0.1.0";
            nvimRequireCheck = "prism";
            src = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [
                ./lua
                ./plugin
              ];
            };
          };

          # Lightweight test runner: neovim-unwrapped + mini.nvim only.
          # PRISM_TEST_RTP propagates rtp into MiniTest.new_child_neovim()
          # spawns (child processes inherit env, then minimal_init.lua re-prepends).
          testNvim = pkgs.writeShellScriptBin "nvim-test" ''
            export PRISM_TEST_RTP="${pkgs.vimPlugins.mini-nvim}"
            exec ${pkgs.neovim-unwrapped}/bin/nvim \
              --cmd 'set rtp^=${pkgs.vimPlugins.mini-nvim}' \
              "$@"
          '';

          # lua-language-server workspace library generated from store paths.
          luarc = pkgs.mk-luarc {
            nvim = pkgs.neovim-unwrapped;
            lua-version = "jit51";
            plugins = with pkgs.vimPlugins; [
              mini-nvim
            ];
          };

          luarcJson = pkgs.luarc-to-json (luarc // {
            workspace = luarc.workspace // {
              ignoreDir = luarc.workspace.ignoreDir ++ [
                ".direnv"
                "result"
              ];
            };
            diagnostics = luarc.diagnostics // {
              unusedLocalExclude = [ "_*" ];
            };
          });
        in
        {
          packages = {
            default = vimPlugin;
            nvim-test = testNvim;
          };

          checks = {
            lua-tests = pkgs.runCommand "prism-lua-tests" {} ''
              export HOME=$(mktemp -d)
              export PRISM_ROOT="${self}"
              cd ${self}
              ${testNvim}/bin/nvim-test --headless -u tests/minimal_init.lua \
                -c "lua MiniTest.run({ collect = { find_files = function() return vim.fn.globpath('tests', 'test_*.lua', true, true) end } })"
              touch $out
            '';
          };

          devShells.default = pkgs.mkShell {
            packages = (with pkgs; [
              just
              watchexec
            ]) ++ [ testNvim ];
            shellHook = ''
              export PRISM_ROOT="$(pwd)"
              ln -fs ${luarcJson} .luarc.json
            '';
          };
        });
    in
    {
      packages = lib.mapAttrs (_: v: v.packages) perSystem;
      checks = lib.mapAttrs (_: v: v.checks) perSystem;
      devShells = lib.mapAttrs (_: v: v.devShells) perSystem;

      overlays.default = final: _prev: {
        vimPlugins = _prev.vimPlugins // {
          "prism.nvim" = self.packages.${final.system}.default;
        };
      };
    };
}
