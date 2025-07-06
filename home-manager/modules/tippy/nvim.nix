{
  pkgs,
  inputs,
  osConfig,
  ...
}:
{
  # https://github.com/mochouaaaaa/nix-config
  home.packages = with pkgs; [
    wl-clipboard
    ghostscript
    multimarkdown
    icu
    python313Packages.pylatexenc
  ];

  imports = [ inputs.nixvim.homeModules.nixvim ];

  programs = rec {
    nixvim = {
      enable = true;
      defaultEditor = true;
      vimAlias = true;
      vimdiffAlias = true;
      globals = {
        IS_NIX = true;
      };
      extraLuaPackages = ps: [
        ps.magick
        pkgs.luajitPackages.luarocks
        pkgs.luajitPackages.luacheck
      ];
      extraPackages = [
        pkgs.imagemagick
        pkgs.sqlite
        pkgs.libgit2
      ];
      extraPlugins = with pkgs.vimPlugins; [
        # nvim-treesitter.withAllGrammars
      ];
      plugins = {
        treesitter = {
          enable = true;
          # grammarPackages = pkgs.vimPlugins.nvim-treesitter;
        };
      };
      extraPython3Packages = ps: [ ps.debugpy ];
      withNodeJs = true;
      extraConfigLuaPre = '''';
      extraConfigLuaPost = ''
        	vim.loader.enable()
        	require "init"
        	vim.keymap.del('n', 's')
                local nvim_lsp = require("lspconfig")
                nvim_lsp.nixd.setup({
                   cmd = { "nixd" },
                   settings = {
                      nixd = {
                         nixpkgs = {
                            expr = 'import (builtins.getFlake "/home/tippy/source/flakes").inputs.nixpkgs {  }',
                         },
                         formatting = {
                            command = { "nixfmt" },
                         },
                         options = {
                            nixos = {
                               expr = '(builtins.getFlake "/home/tippy/source/flakes").nixosConfigurations.${osConfig.networking.hostName}.options',
                            },
                            home_manager = {
                               expr = '(builtins.getFlake "/home/tippy/source/flakes").homeConfigurations.tippy.options',
                            },
                            nix_darwin = {
                               expr = '(builtins.getFlake "/home/tippy/source/flakes").darwinConfigurations.macos.options',
                            },
                         },
                      },
                   },
                })
      '';
    };
  };
}
