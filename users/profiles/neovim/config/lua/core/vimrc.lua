local opt = vim.opt
local cache_dir = os.getenv("HOME") .. "/.cache/nvim/"

vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- color scheme
vim.opt.termguicolors = true
vim.cmd("colorscheme melange")

-- open backup
vim.o.backup = true
vim.o.writebackup = true
vim.o.backupdir = cache_dir .. "backup/"
-- Ask for confirmation when handling unsaved or read-only files
vim.o.confirm = true
vim.o.signcolumn = "yes"

-- command menu
opt.pumheight = 20
opt.pumblend = 15
opt.wildmode = 'longest:full,full'
opt.wildoptions = 'pum'

-- long line wrap
opt.wrap = true
opt.breakindent = true
opt.showbreak = string.rep(' ', 3) -- Make it so that long lines wrap smartly
opt.linebreak = true

opt.encoding = 'utf-8'
opt.fileencoding = 'utf-8'
opt.scrolloff = 5
opt.number = true
opt.relativenumber = true
opt.signcolumn = 'yes'
opt.mouse = 'nv'
opt.writebackup = false
opt.swapfile = false
opt.updatetime = 500
opt.timeoutlen = 500
opt.splitbelow = true
opt.splitright = true
opt.tabstop = 2
opt.softtabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.autoindent = true
opt.smartindent = true
opt.ignorecase = true
opt.smartcase = true
opt.completeopt = 'menu,menuone,noselect,noinsert'
opt.formatoptions = opt.formatoptions
  - 'a' -- Auto formatting is BAD.
  - 't' -- Don't auto format my code. I got linters for that.
  + 'c' -- In general, I like it when comments respect textwidth
  + 'q' -- Allow formatting comments w/ gq
  - 'o' -- O and o, don't continue comments
  + 'r' -- But do continue when pressing enter.
  + 'n' -- Indent past the formatlistpat, not underneath it.
  + 'j' -- Auto-remove comments if possible.

opt.fillchars:append {
  horiz = '━',
  horizup = '┻',
  horizdown = '┳',
  vert = '┃',
  vertleft = '┨',
  vertright = '┣',
  verthoriz = '╋',
}

opt.termguicolors = true

-- colorschme
opt.showmode = false
opt.background = 'dark'
opt.termguicolors = true

-- fold
opt.foldenable = false
