return {
  -- vscode like colorscheme
  {
    "Mofiqul/vscode.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.o.background = "dark"
      local c = require("vscode.colors").get_colors()
      require("vscode").setup({
        transparent = false,
        italic_comments = true,
        disable_nvimtree_bg = true,
        color_overrides = {
          vscLineNumber = "#FFFFFF",
        },
        group_overrides = {
          Cursor = { fg = c.vscDarkBlue, bg = c.vscLightGreen, bold = true },
        },
      })
    end,
  },

  -- catppuccin
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = function()
      vim.cmd.colorscheme("catppuccin")
    end,
  },
}
