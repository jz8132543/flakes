{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.alpha-nvim;
        config = ''
          lua require("core.alpha").setup()
        '';
      }
    ];
  };
}
