{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.nvim-ts-rainbow
      {
        plugin = vimPlugins.nvim-treesitter;
        config = ''
          lua require("config.plugins.treesitter")
        '';
      }
    ];
  };
}
