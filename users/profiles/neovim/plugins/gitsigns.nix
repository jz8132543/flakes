{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.nvim-dap-ui
      {
        plugin = vimPlugins.gitsigns-nvim;
        config = ''
          lua require("config.plugins.gitsigns")
        '';
      }
    ];
  };
}
