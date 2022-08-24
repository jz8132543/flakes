local db = require("utils").requirePlugin("dashboard")
if not db then
    return
end

db.session_directory = os.getenv("HOME") .. "/.local/share/nvim"

db.custom_header = {
    [[                               __                ]],
        [[  ___     ___    ___   __  __ /\_\    ___ ___    ]],
        [[ / _ `\  / __`\ / __`\/\ \/\ \\/\ \  / __` __`\  ]],
        [[/\ \/\ \/\  __//\ \_\ \ \ \_/ |\ \ \/\ \/\ \/\ \ ]],
        [[\ \_\ \_\ \____\ \____/\ \___/  \ \_\ \_\ \_\ \_\]],
        [[ \/_/\/_/\/____/\/___/  \/__/    \/_/\/_/\/_/\/_/]],
    [[                               __                ]],
    [[                               __                ]],
    [[                               __                ]],
    [[                               __                ]],
    [[                               __                ]],
    [[                               __                ]],
    [[                               __                ]],
    [[                               __                ]],
    [[                               __                ]],
    [[                               __                ]],
}
--  SPC mean the leaderkey
db.custom_center = {
    {
        icon = "  ",
        desc = "Recently latest session                 ",
        shortcut = "SPC s l",
        action = "SessionManager load_last_session",
    },
    {
        icon = "  ",
        desc = "Recently opened files                   ",
        action = "Telescope oldfiles",
        shortcut = "SPC f r",
    },
    {
        icon = "  ",
        desc = "Find  File                              ",
        action = "Telescope find_files find_command=rg,--hidden,--files",
        shortcut = "SPC f f",
    },
    {
        icon = "  ",
        desc = "Find  word                              ",
        action = "Telescope live_grep",
        shortcut = "SPC f w",
    },
    {
        icon = "  ",
        desc = "Change Colorscheme                      ",
        action = "lua require('core.colorscheme').changeColorschemeUI()",
        shortcut = "SPC c c",
    },
    {
        icon = "  ",
        desc = "New Buffer                              ",
        action = "DashboardNewFile",
        shortcut = "SPC b n",
    },
}
