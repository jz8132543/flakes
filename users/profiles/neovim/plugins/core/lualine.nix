{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.telescope-fzf-native-nvim
      {
        plugin = vimPlugins.lualine-nvim;
        config = ''
          require("core.lualine").setup()
        '';
      }
    ];
  };
}
