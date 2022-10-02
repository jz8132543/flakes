local lspconfig = require("lspconfig")
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').update_capabilities(capabilities)
local servers = { 'gopls', 'rust_analyzer', 'rnix', 'clangd', 'texlab', 'sumneko_lua' }
for _, lsp in pairs(servers) do
  require('lspconfig')[lsp].setup {
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
end

require("mason").setup()
