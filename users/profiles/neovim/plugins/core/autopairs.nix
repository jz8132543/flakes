{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      {
        plugin = vimPlugins.nvim-autopairs;
        config = ''
          lua require("core.autopairs").setup()
        '';
      }
    ];
  };
}
