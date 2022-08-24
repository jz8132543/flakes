{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.project-nvim;
        config = ''
          lua require("core.project").setup()
        '';
      }
    ];
  };
}
