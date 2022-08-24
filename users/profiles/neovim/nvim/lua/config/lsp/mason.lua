local mason = require("utils").requirePlugin("mason")
local mason_lspconfig = require("utils").requirePlugin("mason-lspconfig")
if not mason or not mason_lspconfig then
    return
end

mason_lspconfig.setup({
    automatic_installation = true,
    ensure_installed = {
        "sumneko_lua",
    },
})

mason.setup({
    ui = {
        border = "single",
    },
})
