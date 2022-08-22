{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.project-nvim;
        config = ''
          require("core.project").setup()
        '';
      }
    ];
  };
}
