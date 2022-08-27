{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [{
      plugin = vimPlugins.indent-blankline-nvim;
      config = ''
        lua require("config.plugins.indent-blankline")
      '';
    }];
  };
}
