{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.aerial-nvim;
        config = ''
          lua require("config.plugins.aerial")
        '';
      }
    ];
  };
}
