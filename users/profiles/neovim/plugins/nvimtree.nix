{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.telescope-nvim
      vimPlugins.nvim-web-devicons
      {
        plugin = vimPlugins.nvim-tree-lua;
        config = ''
          lua require("config.plugins.nvimtree")
        '';
      }
    ];
  };
}
