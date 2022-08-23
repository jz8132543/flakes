{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.plenary-nvim
      vimPlugins.telescope-fzf-native-nvim
      {
        plugin = vimPlugins.telescope-nvim;
        config = ''
          require("core.telecope").setup()
        '';
      }
    ];
  };
}
