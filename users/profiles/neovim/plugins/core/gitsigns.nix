{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.plenary-nvim
      {
        plugin = vimPlugins.gitsigns-nvim;
        config = ''
          require("core.gitsigns").setup()
        '';
      }
    ];
  };
}
