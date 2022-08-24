local bufferline = require("utils").requirePlugin("bufferline")

if not bufferline then
    return
end

bufferline.setup({
    options = {
        diagnostics = "nvim_lsp",
        offsets = {
            {
                filetype = "neo-tree",
                text = "File Explorer",
                highlight = "Directory",
                text_align = "left",
            },
        },
    },
})
