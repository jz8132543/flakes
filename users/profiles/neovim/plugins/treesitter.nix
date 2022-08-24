{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.nvim-ts-rainbow
      (nvim-treesitter.withPlugins (
        plugins: with plugins; [
          tree-sitter-nix
          tree-sitter-lua
          tree-sitter-rust
          tree-sitter-go
        ]
      ))
      {
        plugin = vimPlugins.nvim-treesitter;
        config = ''
          lua require("config.plugins.treesitter")
        '';
      }
    ];
  };
}
