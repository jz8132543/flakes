{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.dashboard-nvim;
        config = ''
          lua require("config.plugins.dashboard")
        '';
      }
    ];
  };
}
