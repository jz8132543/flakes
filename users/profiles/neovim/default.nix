{ pkgs, lib, ... }:

{
  programs = {
    neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      plugins = with pkgs; [
        vimPlugins.aerial-nvim
        vimPlugins.nvim-autopairs
        vimPlugins.bufferline-nvim

        vimPlugins.cmp-nvim-lsp
        vimPlugins.cmp-buffer
        vimPlugins.cmp-path
        vimPlugins.cmp-cmdline
        vimPlugins.cmp-nvim-lua
        vimPlugins.cmp-nvim-lsp-signature-help
        vimPlugins.lspkind-nvim

        vimPlugins.comment-nvim
        vimPlugins.nvim-dap
        vimPlugins.nvim-dap-ui
        vimPlugins.dashboard-nvim
        vimPlugins.dressing-nvim
        vimPlugins.gitsigns-nvim
        vimPlugins.indent-blankline-nvim
        nur.repos.m15a.vimExtraPlugins.nvim-lspconfig
        vimPlugins.lualine-nvim
        vimPlugins.nvim-web-devicons
        vimPlugins.lualine-lsp-progress
        vimPlugins.nvim-tree-lua
        vimPlugins.project-nvim
        nur.repos.m15a.vimExtraPlugins.rose-pine
        vimPlugins.luasnip
        vimPlugins.cmp_luasnip
        vimPlugins.telescope-nvim
        vimPlugins.telescope-fzf-native-nvim
        vimPlugins.plenary-nvim
        vimPlugins.which-key-nvim
        vimPlugins.nvim-ts-rainbow
        (vimPlugins.nvim-treesitter.withPlugins (
        plugins: with plugins; [
          tree-sitter-nix
          tree-sitter-lua
          tree-sitter-rust
          tree-sitter-go
        ]
      ))

      ];
      extraConfig = ''
        lua require("core")
        vim.cmd('colorscheme rose-pine')
      '';
    };
  };

  home.file.neovim = {
    source = ./nvim/lua;
    target = ".config/nvim/lua";
    recursive = true;
  };

  home.packages = with pkgs; [
    rnix-lsp
  ];
}
