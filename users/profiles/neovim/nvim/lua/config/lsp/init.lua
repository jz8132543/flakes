local use = require("core.packer").add_plugin

use({
    "williamboman/mason.nvim",
    branch = "main",
    config = "require('config.lsp.mason')",
})
use({ "williamboman/mason-lspconfig.nvim" })
use({ "neovim/nvim-lspconfig" })

require("config.lsp.setup")
