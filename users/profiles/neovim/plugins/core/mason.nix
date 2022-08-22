{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = nur.repos.m15a.vimExtraPlugins.mason-nvim;
        config = ''
          require("core.mason").setup()
        '';
      }
    ];
  };
}
