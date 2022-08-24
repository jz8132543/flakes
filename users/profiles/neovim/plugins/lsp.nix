{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      nur.repos.m15a.vimExtraPlugins.nvim-lspconfig
      nur.repos.m15a.vimExtraPlugins.nlsp-settings-nvim
      vimPlugins.null-ls-nvim
      {
        plugin = nur.repos.m15a.vimExtraPlugins.mason-nvim;
        config = ''
          lua require("config.lsp")
        '';
      }
    ];
  };
}
