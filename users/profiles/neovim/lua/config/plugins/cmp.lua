local lspkind = require("utils").requirePlugin("lspkind")
local cmp = require("utils").requirePlugin("cmp")
local luasnip = require("utils").requirePlugin("luasnip")

if not cmp or not lspkind or not luasnip then
    return
end

-- load the luasnip
require("luasnip.loaders.from_lua").load({ paths = "./snippets" })
-- keymap for luasnip
local map = require("core.keymap").set_keymap
map({ "i", "s" })("<C-l>", function()
    if luasnip.choice_active() then
        luasnip.change_choice(1)
    end
end)

cmp.setup({
    experimental = {
        ghost_text = true,
    },
    window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered(),
    },
    -- 指定 snippet 引擎
    snippet = {
        expand = function(args)
            require("luasnip").lsp_expand(args.body)
        end,
    },
    -- 来源
    sources = cmp.config.sources({
        { name = "nvim_lsp" },
        { name = "luasnip" },
        { name = "nvim_lua" },
        { name = "buffer" },
        { name = "path" },
        { name = "nvim_lsp_signature_help" },
    }),
    -- 快捷键
    mapping = {
        ["<C-k>"] = cmp.mapping.select_prev_item(),
        ["<C-j>"] = cmp.mapping.select_next_item(),

        ["<C-d>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),

        -- 出现/取消补全
        ["<A-.>"] = cmp.mapping(function()
            if cmp.visible() then
                cmp.abort()
            else
                cmp.complete()
            end
        end, { "i", "c" }),

        -- Accept currently selected item. If none selected, `select` first item.
        -- Set `select` to `false` to only confirm explicitly selected items.
        ["<CR>"] = cmp.mapping.confirm({
            select = true,
            -- behavior = cmp.ConfirmBehavior.Replace
        }, { "i", "c" }),
        -- ['<C-y>'] = cmp.config.disable, -- Specify `cmp.config.disable` if you want to remove the default `<C-y>` mapping.

        ["<Tab>"] = cmp.mapping(function(fallback)
            if luasnip.expand_or_locally_jumpable() then
                luasnip.expand_or_jump()
            else
                fallback()
            end
        end, { "i", "s" }),

        ["<S-Tab>"] = cmp.mapping(function(fallback)
            if luasnip.jumpable(-1) then
                luasnip.jump(-1)
            else
                fallback()
            end
        end, { "i", "s" }),
    },

    -- 使用lspkind-nvim显示类型图标
    formatting = {
        format = lspkind.cmp_format({
            with_text = true, -- do not show text alongside icons
            maxwidth = 50, -- prevent the popup from showing more than provided characters (e.g 50 will not show more than 50 characters)
            before = function(entry, vim_item)
                -- Source 显示提示来源
                if entry.source.name == "nvim_lsp" then
                    vim_item.menu = "[LSP]"
                elseif entry.source.name == "nvim_lsp_signature_help" then
                    vim_item.menu = ""
                else
                    vim_item.menu = "[" .. string.upper(entry.source.name) .. "]"
                end
                return vim_item
            end,
        }),
    },
})

-- Use buffer source for `/` `?` and `:`.
cmp.setup.cmdline("/", {
    mapping = cmp.mapping.preset.cmdline(),
    sources = {
        { name = "buffer" },
    },
})
cmp.setup.cmdline("?", {
    mapping = cmp.mapping.preset.cmdline(),
    sources = {
        { name = "buffer" },
    },
})
cmp.setup.cmdline(":", {
    mapping = cmp.mapping.preset.cmdline(),
    sources = {
        { name = "path" },
        { name = "cmdline" },
    },
})
