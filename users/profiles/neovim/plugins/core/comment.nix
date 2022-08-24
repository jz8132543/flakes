{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.nvim-ts-context-commentstring
      vimPlugins.nvim-treesitter
      {
        plugin = nur.repos.m15a.vimExtraPlugins.nvim-comment;
        config = ''
          lua require("core.comment").setup()
        '';
      }
    ];
  };
}
