{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.nvim-treesitter;
        config = ''
          require("core.treesitter").setup()
        '';
      }
    ];
  };
}
