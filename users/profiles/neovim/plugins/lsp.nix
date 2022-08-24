{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      sumneko-lua-language-server
      # nur.repos.m15a.vimExtraPlugins.nlsp-settings-nvim
      # vimPlugins.null-ls-nvim
      {
        plugin = nur.repos.m15a.vimExtraPlugins.nvim-lspconfig;
        config = ''
          lua require("config.lsp")
        '';
      }
    ];
  };
}
