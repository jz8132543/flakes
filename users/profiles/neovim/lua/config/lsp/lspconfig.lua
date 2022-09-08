local lspconfig = require("lspconfig")
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').update_capabilities(capabilities)

lspconfig.util.default_config = vim.tbl_extend(
  "force",
  lspconfig.util.default_config,
  {
    on_attach = on_attach,
    capabilities = capabilities,
    flags = {
      debounce_text_changes = 150,
    },
    settings = {
      texlab = {
        build = {
          executable = 'tectonic',
          args = { '-X', 'compile', '%f', '--synctex', '--keep-logs', '--keep-intermediates' },
          forwardSearchAfter = true
        },
        forwardSearch = {
          executable = 'sioyek',
          args = {
            '--reuse-instance',
            '--forward-search-file',
            '%f',
            '--forward-search-line',
            '%l',
            '%p'
          }
        }
      }
    }
  }
)
