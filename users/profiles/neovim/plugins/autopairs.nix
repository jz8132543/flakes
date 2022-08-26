{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.nvim-autopairs;
        config = ''
          lua require("config.plugins.autopairs")
        '';
      }
    ];
  };
}