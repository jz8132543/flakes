{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.nvim-treesitter;
        config = ''
          lua require("core.treesitter").setup()
        '';
      }
    ];
  };
}
