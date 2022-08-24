local packer = require("core.packer")


require("config.options")

require("config.keymaps")

packer.init_packer()

require("config.colorscheme")

require("config.plugins")

require("config.lsp")

packer.load_plugins()
