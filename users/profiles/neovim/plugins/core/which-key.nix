{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.which-key-nvim;
        config = ''
          require("core.which-key").setup()
        '';
      }
    ];
  };
}
