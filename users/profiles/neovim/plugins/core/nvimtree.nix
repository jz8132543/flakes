{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.telescope-nvim
      {
        plugin = vimPlugins.nvim-tree-lua;
        config = ''
          lua require("core.nvimtree").setup()
        '';
      }
    ];
  };
}
