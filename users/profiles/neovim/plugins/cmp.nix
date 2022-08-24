{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.cmp-nvim-lsp
      vimPlugins.cmp-buffer
      vimPlugins.cmp-path
      vimPlugins.cmp-cmdline
      vimPlugins.cmp-nvim-lua
      vimPlugins.cmp-nvim-lsp-signature-help
      vimPlugins.lspkind-nvim
      {
        plugin = vimPlugins.nvim-cmp;
        config = ''
          lua require("config.plugins.cmp")
        '';
      }
    ];
  };
}
