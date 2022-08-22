{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
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
