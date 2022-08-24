{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.nvim-web-devicons
      vimPlugins.lualine-lsp-progress
      {
        plugin = vimPlugins.lualine-nvim;
        config = ''
          lua require("config.plugins.lualine")
        '';
      }
    ];
  };
}
