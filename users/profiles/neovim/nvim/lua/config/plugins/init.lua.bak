local use = require("core.packer").add_plugin

-- Packer can manage itself
use({ "wbthomason/packer.nvim" })

-- autopairs
use{
    "windwp/nvim-autopairs",
    after = "nvim-cmp",
    config = "require('config.plugins.autopairs')",
}

-- bufferline #buffer
use{
    "akinsho/bufferline.nvim",
    requires = "kyazdani42/nvim-web-devicons",
    event = "BufWinEnter",
    config = "require('config.plugins.bufferline')",
}

-- cmp
use({ "hrsh7th/nvim-cmp", config = "require('config.plugins.cmp')", after = "lspkind-nvim" })
use({ "hrsh7th/cmp-nvim-lsp", after = "nvim-cmp" })
use({ "hrsh7th/cmp-buffer", after = "nvim-cmp" })
use({ "hrsh7th/cmp-path", after = "nvim-cmp" })
use({ "hrsh7th/cmp-cmdline", after = "nvim-cmp" })
use({ "hrsh7th/cmp-nvim-lua", after = "nvim-cmp" })
use({ "hrsh7th/cmp-nvim-lsp-signature-help", after = "nvim-cmp" })
use({ "onsails/lspkind-nvim", event = "BufWinEnter" })

-- Comment
use{
    "numToStr/Comment.nvim",
    requires = "JoosepAlviste/nvim-ts-context-commentstring",
    event = "BufWinEnter",
    config = "require('config.plugins.comment')",
}

-- Dashboard
use({
    "glepnir/dashboard-nvim",
    event = "BufWinEnter",
    config = "require('config.plugins.dashboard')",
})

-- Debugging
use({ "mfussenegger/nvim-dap" })
use({ "rcarriga/nvim-dap-ui" })
use({ "Pocco81/DAPInstall.nvim" })

-- lualine
use{
    "nvim-lualine/lualine.nvim",
    requires = { "kyazdani42/nvim-web-devicons", opt = true },
    config = "require('config.plugins.lualine')",
}
use({"nvim-lua/lsp-status.nvim"})

-- snippets
use({ "L3MON4D3/LuaSnip", event = "InsertEnter" })
use({ "saadparwaiz1/cmp_luasnip", after = { "nvim-cmp", "LuaSnip" } })

-- nvimtree
use{
    "kyazdani42/nvim-tree.lua",
    requires = { "kyazdani42/nvim-web-devicons", opt = true },
    config = "require('config.plugins.nvimtree')",
}

-- recent project
use({
    "ahmedkhalf/project.nvim",
    after = "telescope.nvim",
    config = "require('config.plugins.project')",
})

-- rose-pine
use({
    'rose-pine/neovim',
    as = 'rose-pine',
    config = function()
        vim.cmd('colorscheme rose-pine')
    end
})

-- telescope
use({
    "nvim-telescope/telescope.nvim",
    requires = {
        "nvim-lua/plenary.nvim",
        "kyazdani42/nvim-web-devicons",
    },
    event = "BufWinEnter",
    config = "require('config.plugins.telescope')",
})
use({ "nvim-telescope/telescope-fzf-native.nvim", run = "make", after = "telescope.nvim" })

-- treesitter highlight
use({
    "nvim-treesitter/nvim-treesitter",
    run = ":TSUpdate",
    config = "require('config.plugins.nvim-treesitter')",
})
use({ "p00f/nvim-ts-rainbow", after = "nvim-treesitter" })

-- which-key
use({
    "folke/which-key.nvim",
    event = "BufWinEnter",
    config = "require('config.plugins.which-key')",
})
