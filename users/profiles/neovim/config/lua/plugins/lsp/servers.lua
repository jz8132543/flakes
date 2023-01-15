-- Add any servers here together with their settings
---@type lspconfig.options
local servers = {
  bashls = {},
  clangd = {},
  cmake = {},
  cssls = {},
  tsserver = {},
  html = {},
  jsonls = {},
  pyright = {},
  yamlls = {},
  nil_ls = {
    formatting = {
      command = { "nixpkgs-fmt" },
    },
  },
  sumneko_lua = {
    settings = {
      Lua = {
        workspace = {
          checkThirdParty = false,
        },
        completion = {
          callSnippet = "Replace",
        },
        diagnostics = {
          globals = { "vim", "use" },
        },
      },
    },
  },
}

return servers
