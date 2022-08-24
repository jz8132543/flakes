{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.bufferline-nvim;
        config = ''
          lua require("core.bufferline").setup()
        '';
      }
    ];
  };
}
