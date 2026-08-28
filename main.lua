local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Config = require("webdavsync/config")
local Menu = require("webdavsync/menu")

local WebDAVSync = WidgetContainer:extend{
    name = "webdavsync",
    is_doc_only = false
}

function WebDAVSync:init()
    Config.init()

    self.ui.menu:registerToMainMenu(self)
end

function WebDAVSync:addToMainMenu(menu_items)
    Menu.addToMainMenu(menu_items)
end

return WebDAVSync
