{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.nvim-dap-ui
      {
        plugin = vimPlugins.nvim-dap;
        config = ''
          lua require("config.plugins.dap")
        '';
      }
    ];
  };
}
