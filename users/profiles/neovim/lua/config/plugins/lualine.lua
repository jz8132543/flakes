local lualine = require("utils").requirePlugin("lualine")
local utils = require("utils")

if not lualine then
    return
end

lualine.setup({
    options = {
        icons_enabled = true,
        theme = 'rose-pine',
    },
    sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { "filename" },
        lualine_x = { "aerial" },
        lualine_y = { "lsp_progress" },
        lualine_z = { "progress" },
    },
    inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_c = { "filename" },
        lualine_x = { "location" },
        lualine_y = {},
        lualine_z = {},
    },
    tabline = {},
    extensions = {},
})
