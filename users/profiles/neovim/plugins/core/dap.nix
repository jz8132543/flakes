{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.nvim-dap;
        config = ''
          require("core.dap").setup()
        '';
      }
    ];
  };
}
