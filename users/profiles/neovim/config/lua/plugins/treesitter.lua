return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = "BufReadPost",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
      "nvim-treesitter/nvim-treesitter-refactor",
      "JoosepAlviste/nvim-ts-context-commentstring",
      "nvim-treesitter/nvim-treesitter-context",
      "windwp/nvim-ts-autotag",
      "mrjones2014/nvim-ts-rainbow",
    },
    config = function()
      require("nvim-treesitter.configs").setup({
        sync_install = false,
        auto_install = true,
        ensure_installed = {
          "json",
          "lua",
          "markdown",
          "markdown_inline",
          "python",
          "regex",
          "tsx",
          "typescript",
          "vim",
          "yaml",
        },
        highlight = { enable = true },
        indent = { enable = true },
        context_commentstring = { enable = true, enable_autocmd = true },
        refactor = {
          highlight_definitions = {
            enable = true,
            clear_on_cursor_move = true,
          },
        },
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
            },
          },
        },
        autotag = {
          enable = true,
        },
        rainbow = {
          enable = true,
          extended_mode = true, -- Highlight also non-parentheses delimiters, boolean or table: lang -> boolean
          max_file_lines = 1000, -- Do not enable for files with more than 1000 lines, int
        },
        matchup = {
          enable = true, -- mandatory, false will disable the whole extension
        },
      })
      require("treesitter-context").setup({})
    end,
  },
}
