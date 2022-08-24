{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.which-key-nvim;
        config = ''
          lua require("config.plugins.which-key")
        '';
      }
    ];
  };
}
