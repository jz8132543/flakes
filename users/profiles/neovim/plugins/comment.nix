{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [{
      plugin = vimPlugins.comment-nvim;
      config = ''
        lua require("config.plugins.comment")
      '';
    }];
  };
}
