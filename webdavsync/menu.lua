local _ = require("gettext")

local Config = require("webdavsync/config")
local Analyze = require("webdavsync/analyze")
local Synchronize = require("webdavsync/synchronize")

local Menu = {}

function Menu.addToMainMenu(menu_items)
    menu_items.webdavsync = {

        text = _("WebDAVSync"),

        sub_item_table = {{

            text = _("Settings"),

            sub_item_table = {{

                text_func = function()
                    return _("WebDAV server: ") .. Config.getSelectedServerName()
                end,

                callback = function(touchmenu_instance)
                    Config.chooseServer(touchmenu_instance)
                end,

                keep_menu_open = true

            }, {

                text_func = function()
                    return _("Local destination: ") .. Config.getLocalPathName()
                end,

                callback = function(touchmenu_instance)
                    Config.chooseLocalPath(touchmenu_instance)
                end,

                keep_menu_open = true

            }}
        }, {

            text = _("Analyze"),

            callback = function()
                Analyze.run()
            end,

            keep_menu_open = true

        }, {

            text = _("Synchronize"),

            callback = function()
                Synchronize.run()
            end,

            keep_menu_open = true

        }}
    }
end

return Menu
