{ pkgs, ... }:

{
  programs = {
    neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      plugins = with pkgs; [
        {
          plugin = vimPlugins.telescope-nvim;
          config = "lua require('telescope').setup { extensions = { fzf = { fuzzy = true } } }\n";
        }
        {
          plugin = vimPlugins.telescope-fzf-native-nvim;
          config = "lua require('telescope').load_extension('fzf')\n";
        }
        {
          plugin = vimPlugins.gitsigns-nvim;
          config = "lua require('gitsigns').setup { current_line_blame = true }\n";
        }
        {
          plugin = vimPlugins.bufferline-nvim;
          config = "lua require('bufferline').setup{}\n";
        }
        {
          plugin = vimPlugins.lspkind-nvim;
          config = "lua require('lspkind').init()\n";
        }
        {
          plugin = vimPlugins.alpha-nvim;
          config = "lua require'alpha'.setup(require'alpha.themes.dashboard'.config)\n";
        }
        {
          plugin = vimPlugins.project-nvim;
          config = "lua require('project_nvim').setup {}\n";
        }
        {
          plugin = vimPlugins.lualine-nvim;
          config = "lua require('lualine').setup({ options = { theme = 'rose-pine' } })\n";
        }
        {
          plugin = nur.repos.m15a.vimExtraPlugins.rose-pine;
          config = ''
            lua vim.g.rose_pine_variant = 'dawn'
            lua vim.cmd('colorscheme rose-pine')
          '';
        }
        {
          plugin = nur.repos.m15a.vimExtraPlugins.nvim-comment;
          config = "lua require('nvim_comment').setup()\n";
        }
        {
          plugin = nur.repos.m15a.vimExtraPlugins.nvim-lsp-installer;
          config = "lua require('nvim-lsp-installer').setup {}\n";
        }
        {
          plugin = vimPlugins.lsp_signature-nvim;
          config = ''
            lua require "lsp_signature".setup()
            lua require'lsp_signature'.on_attach()
          '';
        }
        {
          plugin = vimPlugins.nvim-autopairs;
          config = "lua require('nvim-autopairs').setup{}\n";
        }
        vimPlugins.cmp-nvim-lsp
        vimPlugins.cmp-path
        vimPlugins.cmp-buffer
        vimPlugins.cmp_luasnip
        vimPlugins.nvim-cmp
        vimPlugins.nvim-lspconfig

        vimPlugins.lua-dev-nvim
        vimPlugins.nvim-treesitter
        vimPlugins.which-key-nvim
        vimPlugins.null-ls-nvim
        vimPlugins.nvim-tree-lua
        vimPlugins.nvim-web-devicons
        vimPlugins.SchemaStore-nvim
        vimPlugins.nvim-ts-context-commentstring
        vimPlugins.plenary-nvim
        vimPlugins.FixCursorHold-nvim
        vimPlugins.popup-nvim
        # structlog.nvim
        vimPlugins.friendly-snippets
        vimPlugins.nvim-notify
        # DAPInstall.nvim
        vimPlugins.toggleterm-nvim
        vimPlugins.nvim-dap
        nur.repos.m15a.vimExtraPlugins.nlsp-settings-nvim
      ];

      extraConfig = ''
        syntax enable
        set number
        set showtabline=2
        set tabstop=2
        set shiftwidth=2
        set expandtab
      '' + ''
        lua << EOF
        local lspkind = require('lspkind')
        require'cmp'.setup {
          formatting = {
            format = function(entry, vim_item)
              vim_item.kind = require('lspkind').presets.default[vim_item.kind] .. " " .. vim_item.kind
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
      '' + ''
        lua << EOF
        local capabilities = vim.lsp.protocol.make_client_capabilities()
        capabilities = require('cmp_nvim_lsp').update_capabilities(capabilities)
        require'lspconfig'.rnix.setup{ capabilities = capabilities, }
        require'lspconfig'.tsserver.setup{ capabilities = capabilities, }
        require'lspconfig'.pyright.setup{ capabilities = capabilities, }
        require'lspconfig'.yamlls.setup{ capabilities = capabilities, }
        require'lspconfig'.clangd.setup{ capabilities = capabilities, }
        EOF
      '';
    };
  };

  home.file.".config/nvim/settings.lua".source = ./init.lua;
  home.packages = with pkgs; [
    rnix-lsp
  ];
}
