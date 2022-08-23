{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.null-ls-nvim
      {
        plugin = nur.repos.m15a.vimExtraPlugins.nlsp-settings-nvim;
        config = ''
          require("core.lsp").setup()
        '';
      }
    ];
  };
}
