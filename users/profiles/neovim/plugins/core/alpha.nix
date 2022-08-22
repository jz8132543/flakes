{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.alpha-nvim;
        config = ''
          require("core.alpha").setup()
        '';
      }
    ];
  };
}
