{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.plenary-nvim
      {
        plugin = vimPlugins.gitsigns-nvim;
        config = ''
          lua require("core.gitsigns").setup()
        '';
      }
    ];
  };
}
