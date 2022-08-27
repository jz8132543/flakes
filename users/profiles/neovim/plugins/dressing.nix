{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [{
      plugin = vimPlugins.dressing-nvim;
      config = ''
        lua require("config.plugins.dressing")
      '';
    }];
  };
}
