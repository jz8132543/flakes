M = {}
function M.setup()
  require("nlspsettings").setup()
  require("null-ls").setup({
    sources = {
      require("null-ls").builtins.formatting.stylua,
      require("null-ls").builtins.diagnostics.eslint,
      require("null-ls").builtins.completion.spell,
    },
  })
end

return M
