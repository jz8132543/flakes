{ pkgs, ... }:

{
  programs = {
    neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      plugins = with pkgs; [
        vimPlugins.telescope-nvim
        vimPlugins.telescope-fzf-native-nvim
        vimPlugins.gitsigns-nvim
        vimPlugins.lua-dev-nvim
        vimPlugins.nvim-treesitter
        vimPlugins.which-key-nvim
        vimPlugins.bufferline-nvim
        vimPlugins.lspkind-nvim
        vimPlugins.nvim-cmp
        vimPlugins.cmp-path
        vimPlugins.cmp-buffer
        vimPlugins.cmp_luasnip
        vimPlugins.cmp-nvim-lsp
        vimPlugins.nvim-tree-lua
        vimPlugins.comment-nvim
        vimPlugins.nvim-web-devicons
        vimPlugins.SchemaStore-nvim
        vimPlugins.nvim-autopairs
        vimPlugins.alpha-nvim
        vimPlugins.nvim-ts-context-commentstring
        vimPlugins.project-nvim
        vimPlugins.luasnip
        vimPlugins.plenary-nvim
        vimPlugins.FixCursorHold-nvim
        vimPlugins.popup-nvim
        # structlog.nvim
        vimPlugins.null-ls-nvim
        # nvim-lsp-installer
        vimPlugins.nvim-lspconfig
        vimPlugins.friendly-snippets
        # nlsp-settings.nvim
        vimPlugins.lualine-nvim
        vimPlugins.nvim-notify
        # DAPInstall.nvim
        vimPlugins.toggleterm-nvim
        vimPlugins.nvim-dap
        nur.repos.m15a.vimExtraPlugins.rose-pine
        nur.repos.m15a.vimExtraPlugins.nlsp-settings-nvim
        nur.repos.m15a.vimExtraPlugins.mason-nvim
      ];

      extraConfig = ''
        syntax enable
        set number
        set showtabline=2

        " https://github.com/rose-pine/neovim#options
        lua vim.g.rose_pine_variant = 'dawn'
        lua vim.cmd('colorscheme rose-pine')
        " https://github.com/rose-pine/neovim#usage
        lua require('lualine').setup({ options = { theme = 'rose-pine' } })
        lua require('telescope').setup { extensions = { fzf = { fuzzy = true } } }
        lua require('telescope').load_extension('fzf')
        # https://github.com/lewis991/gitsigns.nvim#installation
        lua require('gitsigns').setup { current_line_blame = true }
        " https://github.com/akinsho/bufferline.nvim#usage
        lua require("bufferline").setup{}
        " https://github.com/hrsh7th/nvim-cmp#basic-configuration
        " https://github.com/hrsh7th/cmp-buffer#setup
        " https://github.com/tzachar/cmp-tabnine#install
        lua require('nvim_comment').setup()
        " https://github.com/windwp/nvim-autopairs/
        lua require('nvim-autopairs').setup{}
        # https://github.com/goolord/alpha-nvim
        lua require'alpha'.setup(require'alpha.themes.dashboard'.config)
        # https://github.com/ahmedkhalf/project.nvim
        lua require("project_nvim").setup {}
        " https://github.com/rose-pine/neovim#usage
        lua require('lualine').setup({ options = { theme = 'rose-pine' } })
        # https://github.com/williamboman/mason.nvim#configuration
        require("mason").setup()
        " https://github.com/onsails/lspkind-nvim#configuration
        lua require('lspkind').init()

        lua << EOF
        local lspkind = require('lspkind')
        require'cmp'.setup {
          formatting = {
            format = function(entry, vim_item)
              vim_item.kind = require("lspkind").presets.default[vim_item.kind] .. " " .. vim_item.kind
              vim_item.menu = ({
                buffer = "[Buffer]",
                nvim_lsp = "[LSP]",
                cmp_tabnine = "[TN]",
                path = "[Path]",
              })[entry.source.name]
              return vim_item
            end,
          },
          sources = {
            { name = 'buffer' },
            { name = 'nvim_lsp' },
            { name = 'cmp_tabnine' },
            { name = 'path' },
          },
        }
        EOF

        lua << EOF
        -- https://github.com/hrsh7th/cmp-nvim-lsp#setup
        local capabilities = vim.lsp.protocol.make_client_capabilities()
        capabilities = require('cmp_nvim_lsp').update_capabilities(capabilities)
        -- https://github.com/neovim/nvim-lspconfig/blob/master/CONFIG.md#rnix
        require'lspconfig'.rnix.setup{ capabilities = capabilities, }
        -- https://github.com/neovim/nvim-lspconfig/blob/master/CONFIG.md#tsserver
        require'lspconfig'.tsserver.setup{ capabilities = capabilities, }
        -- https://github.com/neovim/nvim-lspconfig/blob/master/CONFIG.md#pyright
        require'lspconfig'.pyright.setup{ capabilities = capabilities, }
        -- https://github.com/neovim/nvim-lspconfig/blob/master/CONFIG.md#yamlls
        require'lspconfig'.yamlls.setup{ capabilities = capabilities, }
        -- https://github.com/neovim/nvim-lspconfig/blob/master/CONFIG.md#clangd
        require'lspconfig'.clangd.setup{ capabilities = capabilities, }
        -- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md#cmake
        -- require'lspconfig'.cmake.setup{ capabilities = capabilities, }
        -- https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md#rls
        require'lspconfig'.rls.setup{ capabilities = capabilities, }
        EOF
      '';
    };
  };
}
