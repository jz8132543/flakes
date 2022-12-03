local packer = require 'packer'
packer.startup(function(use)
  use 'wbthomason/packer.nvim'

  -- Base dependence
  use 'nvim-lua/plenary.nvim'
  use "nvim-lua/popup.nvim"
  use 'kyazdani42/nvim-web-devicons'

  -- Color Scheme
  use "savq/melange"

  -- Smooth scroll
  use 'psliwka/vim-smoothie'

  -- Highlight the variable with the same name
  use 'RRethy/vim-illuminate'

  use { 'lukas-reineke/indent-blankline.nvim', config = [[ require 'plugins.indent-blankline' ]] }

  -- Smart comment
  use { 'numToStr/Comment.nvim', config = [[ require 'plugins.comment' ]] }

  -- Aerial
  use { 'stevearc/aerial.nvim', config = [[ require 'plugins.aerial' ]] }

  -- File manager
  use {
    'kyazdani42/nvim-tree.lua',
    config = [[ require 'plugins.nvim-tree']],
  }

  -- Auto save session
  use { 'rmagatti/auto-session' }
   -- Lsp progress alert
  use { 'j-hui/fidget.nvim', after = 'auto-session', config = [[ require 'plugins.fidget' ]] }

  -- Statusline
  use { 'nvim-lualine/lualine.nvim', config = [[ require 'plugins.lualine' ]] }
  -- Bufferline
  use { 'akinsho/bufferline.nvim', config = [[ require 'plugins.bufferline' ]] }

  -- Git
  use {
    {
      'tpope/vim-fugitive',
      cmd = { 'G', 'G!', 'Git', 'Gstatus', 'Gblame', 'Gpush', 'Gpull' },
    },
    {
      'lewis6991/gitsigns.nvim',
      config = [[ require 'plugins.gitsigns' ]],
    },
    -- { 'sindrets/diffview.nvim' },
  }

  -- Search
  use {
    'nvim-telescope/telescope.nvim',
    requires = {
      { 'nvim-telescope/telescope-fzf-native.nvim', run = 'make' },
    },
    config = [[ require 'plugins.telescope' ]],
  }

  use { 'folke/which-key.nvim', config = [[ require 'plugins.which-key' ]] }

  -- Completion and snip
  use {
    'hrsh7th/nvim-cmp',
    requires = {
      'hrsh7th/cmp-nvim-lsp',
      'onsails/lspkind-nvim',
      'hrsh7th/cmp-nvim-lua',
      { 'hrsh7th/cmp-buffer', after = 'nvim-cmp' },
      { 'hrsh7th/cmp-path', after = 'nvim-cmp' },
      { 'hrsh7th/cmp-cmdline', after = 'nvim-cmp' },
      { 'saadparwaiz1/cmp_luasnip', after = 'nvim-cmp' },
    },
    config = [[ require 'plugins.cmp' ]],
  }
  use {
    'L3MON4D3/LuaSnip',
    requires = { 'rafamadriz/friendly-snippets' },
    config = [[ require('luasnip.loaders.from_vscode').lazy_load() ]],
  }
  use { 'windwp/nvim-autopairs', config = [[ require 'plugins.auto-pairs' ]], after = 'nvim-cmp' }


  use {
    'nvim-treesitter/nvim-treesitter',
    requires = {
      'nvim-treesitter/nvim-treesitter-refactor',
      'nvim-treesitter/nvim-treesitter-textobjects',
    },
    config = [[ require 'plugins.treesitter' ]],
  }
  -- Rainbow brackets
  use 'p00f/nvim-ts-rainbow'

  -- Lsp
  use { "williamboman/mason.nvim", config = [[ require 'plugins.lsp' ]] }
  use "williamboman/mason-lspconfig.nvim"
  use 'neovim/nvim-lspconfig'
  use {
    'folke/lsp-colors.nvim',
    config = function()
      require('lsp-colors').setup {
        Error = '#db4b4b',
        Warning = '#e0af68',
        Information = '#0db9d7',
        Hint = '#10B981',
      }
    end,
  }

end)
