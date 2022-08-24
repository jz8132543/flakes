{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.nvim-dap;
        config = ''
          lua require("core.dap").setup()
        '';
      }
    ];
  };
}
