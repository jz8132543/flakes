{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.nvim-autopairs;
        config = ''
          require("core.autopairs").setup()
        '';
      }
    ];
  };
}
