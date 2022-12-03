vim.opt.list = true
-- vim.opt.listchars:append "eol:↴"

require('indent_blankline').setup {
  show_end_of_line = true,

  filetype_exclude = {
    'startify',
    'dashboard',
    'dotooagenda',
    'log',
    'fugitive',
    'gitcommit',
    'packer',
    'vimwiki',
    'markdown',
    'json',
    'txt',
    'vista',
    'help',
    'todoist',
    'NvimTree',
    'peekaboo',
    'git',
    'TelescopePrompt',
    'undotree',
    'flutterToolsOutline',
    '', -- for all buffers without a file type
  },
  buftype_exclude = { 'terminal', 'nofile' },
  show_current_context_start = true,
  show_current_context = true,
}
