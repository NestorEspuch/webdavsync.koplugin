local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Config = require("funcs/config")
local Analyze = require("funcs/analyze")
local Synchronize = require("funcs/synchronize")

local WebDAVSync = WidgetContainer:extend{
    name = "webdavsync",
    is_doc_only = false
}

function WebDAVSync:init()
    Config.init(self)

    self.ui.menu:registerToMainMenu(self)
end

function WebDAVSync:getSetting(name)
    return Config.getSetting(self, name)
end

function WebDAVSync:setSetting(name, value)
    Config.setSetting(self, name, value)
end

function WebDAVSync:normalizeLocalPath(path)
    return Config.normalizeLocalPath(self, path)
end

function WebDAVSync:ensureDirectory(path)
    return Config.ensureDirectory(self, path)
end

function WebDAVSync:getServers()
    return Config.getServers(self)
end

function WebDAVSync:getSelectedServer()
    return Config.getSelectedServer(self)
end

function WebDAVSync:getSelectedServerName()
    return Config.getSelectedServerName(self)
end

function WebDAVSync:getLocalPath()
    return Config.getLocalPath(self)
end

function WebDAVSync:getLocalPathName()
    return Config.getLocalPathName(self)
end

function WebDAVSync:showInfo(text)
    Config.showInfo(self, text)
end

function WebDAVSync:chooseServer(touchmenu_instance)
    Config.chooseServer(self, touchmenu_instance)
end

function WebDAVSync:chooseLocalPath(touchmenu_instance)
    Config.chooseLocalPath(self, touchmenu_instance)
end

function WebDAVSync:checkConfiguration()
    local server = self:getSelectedServer()
    local local_path = self:getLocalPath()

    if not server and not local_path then
        self:showInfo(_("Please configure a WebDAV server " .. "and a local destination first."))
        return nil, nil
    end

    if not server then
        self:showInfo(_("Please configure a WebDAV server first."))
        return nil, nil
    end

    if not local_path then
        self:showInfo(_("Please configure a local destination first."))
        return nil, nil
    end

    return server, local_path
end

function WebDAVSync:analyze()
    Analyze.run(self)
end

function WebDAVSync:sync()
    Synchronize.run(self)
end

function WebDAVSync:addToMainMenu(menu_items)
    menu_items.webdavsync = {

        text = _("WebDAVSync"),

        sub_item_table = {{

            text = _("Settings"),

            sub_item_table = {{

                text_func = function()
                    return _("WebDAV server: ") .. self:getSelectedServerName()
                end,

                callback = function(touchmenu_instance)
                    self:chooseServer(touchmenu_instance)
                end,

                keep_menu_open = true

            }, {

                text_func = function()
                    return _("Local destination: ") .. self:getLocalPathName()
                end,

                callback = function(touchmenu_instance)
                    self:chooseLocalPath(touchmenu_instance)
                end,

                keep_menu_open = true

            }}
        }, {

            text = _("Analyze"),

            callback = function()
                self:analyze()
            end

        }, {

            text = _("Synchronize"),

            callback = function()
                self:sync()
            end

        }}
    }
end

return WebDAVSync
