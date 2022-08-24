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
      vimPlugins.cmp-emoji
      vimPlugins.cmp-treesitter
      vimPlugins.vim-crates
      vimPlugins.cmp-tmux
      {
        plugin = vimPlugins.nvim-cmp;
        config = ''
          lua require("core.cmp").setup()
        '';
      }
    ];
  };
}
