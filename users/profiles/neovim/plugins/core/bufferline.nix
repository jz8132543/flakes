{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.bufferline-nvim;
        config = ''
          require("core.bufferline").setup()
        '';
      }
    ];
  };
}
