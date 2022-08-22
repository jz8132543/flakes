{ config, pkgs, lib, ... }: {

  programs.neovim = {
    plugins = with pkgs; [
      vimPlugins.cmp-nvim-lsp
      vimPlugins.cmp-path
      vimPlugins.cmp_luasnip
      vimPlugins.cmp-tabnine
      vimPlugins.cmp-nvim-lua
      vimPlugins.cmp-buffer
      vimPlugins.cmp-calc
      vimplugins.cmp-emoji
      vimplugins.cmp-treesitter
      vimPlugins.vim-crates
      vimPlugins.cmp-tmux
      {
        plugin = vimPlugins.nvim-cmp;
        config = ''
          require("core.cmp").setup()
        '';
      }
    ];
  };
}
