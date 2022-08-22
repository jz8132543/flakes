{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.gitsigns-nvim;
        config = ''
          require("core.gitsigns").setup()
        '';
      }
    ];
  };
}
