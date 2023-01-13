local servers = require("plugins.lsp.servers")

local function on_attach(client, bufnr)
  require("plugins.lsp.format").on_attach(client, bufnr)
  require("plugins.lsp.keymaps").on_attach(client, bufnr)
end

return {
  -- lspconfig
  {
    "neovim/nvim-lspconfig",
    event = "BufReadPre",
    dependencies = {
      { "folke/neoconf.nvim", cmd = "Neoconf", config = true },
      { "folke/neodev.nvim", config = true },
      { "williamboman/mason.nvim", config = true, cmd = "Mason" },
      { "williamboman/mason-lspconfig.nvim", config = { automatic_installation = false } },
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      -- diagnostics
      for name, icon in pairs(require("config.icons").diagnostics) do
        name = "DiagnosticSign" .. name
        vim.fn.sign_define(name, { text = icon, texthl = name, numhl = "" })
      end
      vim.diagnostic.config({
        underline = true,
        update_in_insert = false,
        virtual_text = { spacing = 4, prefix = "●" },
        severity_sort = true,
      })

      -- lspconfig
      local capabilities = require("cmp_nvim_lsp").default_capabilities(vim.lsp.protocol.make_client_capabilities())
      capabilities.offsetEncoding = "utf-8"
      for server, opts in pairs(servers) do
        opts.capabilities = capabilities
        opts.on_attach = on_attach
        require("lspconfig")[server].setup(opts)
      end
    end,
  },

  -- formatters
  {
    "jose-elias-alvarez/null-ls.nvim",
    event = "BufReadPre",
    config = function()
      local nls = require("null-ls")
      nls.setup({
        debounce = 150,
        save_after_format = false,
        sources = {
          nls.builtins.formatting.stylua,
          nls.builtins.formatting.nixpkgs_fmt,
          nls.builtins.formatting.clang_format,
          nls.builtins.formatting.cmake_format,
          nls.builtins.formatting.shfmt,
          nls.builtins.formatting.isort,
          nls.builtins.formatting.black,
          nls.builtins.formatting.prettierd.with({
            filetypes = { "markdown" }, -- only runs `deno fmt` for markdown
          }),
          -- nls.builtins.formatting.prettierd,
          -- nls.builtins.formatting.fixjson.with({ filetypes = { "jsonc" } }),
          -- nls.builtins.formatting.eslint_d,
          -- nls.builtins.diagnostics.shellcheck,
          nls.builtins.diagnostics.luacheck,
          nls.builtins.diagnostics.cmake_lint,
          nls.builtins.diagnostics.markdownlint,
          nls.builtins.diagnostics.selene.with({
            condition = function(utils)
              return utils.root_has_file({ "selene.toml" })
            end,
          }),
          -- nls.builtins.code_actions.gitsigns,
          nls.builtins.diagnostics.flake8,
        },
        root_dir = require("null-ls.utils").root_pattern(".null-ls-root", ".neoconf.json", ".git"),
      })
    end,
  },

  -- UI
  {
    "glepnir/lspsaga.nvim",
    event = "BufRead",
    config = function()
      require("lspsaga").setup({})
    end,
  },
}
