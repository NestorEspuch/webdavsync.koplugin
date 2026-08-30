local _ = require("gettext")

local Config = require("webdavsync/config")
local Analyze = require("webdavsync/analyze")
local Synchronize = require("webdavsync/synchronize")

local Menu = {}

function Menu.addToMainMenu(menu_items, plugin_instance)
    menu_items.webdavsync = {

        text = _("WebDAVSync"),

        sub_item_table = {{

            text = _("Settings"),

            sub_item_table = {{

                text_func = function()
                    return _("WebDAV server: ") .. Config.getSelectedServerName()
                end,

                callback = function(touchmenu_instance)
                    Config.chooseServer(touchmenu_instance, plugin_instance)
                end,

                keep_menu_open = true

            }, {

                text_func = function()
                    return _("Local destination: ") .. Config.getLocalPathName()
                end,

                callback = function(touchmenu_instance)
                    Config.chooseLocalPath(touchmenu_instance, plugin_instance)
                end,

                keep_menu_open = true,
                separator = true,

            }, {

                text = _("Auto-analyze on resume"),

                checked_func = function()
                    return Config.getSetting("auto_analyze")
                end,

                callback = function()
                    Config.setSetting("auto_analyze", not Config.getSetting("auto_analyze"))
                    if plugin_instance then
                        plugin_instance:registerEvents()
                    end
                end,

                enabled_func = function()
                    return Config.isConfigured() and not Config.getSetting("auto_sync")
                end,

                keep_menu_open = true

            }, {

                text = _("Auto-sync on resume"),

                checked_func = function()
                    return Config.getSetting("auto_sync")
                end,

                callback = function()
                    Config.setSetting("auto_sync", not Config.getSetting("auto_sync"))
                    if plugin_instance then
                        plugin_instance:registerEvents()
                    end
                end,

                enabled_func = function()
                    return Config.isConfigured()
                end,

                keep_menu_open = true

            }}
        }, {

            text = _("Analyze"),

            callback = function()
                Analyze.run()
            end,

            enabled_func = function()
                return Config.isConfigured()
            end,

            keep_menu_open = true

        }, {

            text = _("Synchronize"),

            callback = function()
                Synchronize.run()
            end,

            enabled_func = function()
                return Config.isConfigured()
            end,

            keep_menu_open = true

        }}
    }
end

return Menu
