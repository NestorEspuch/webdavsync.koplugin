local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local Config = {}

local CONFIG_FILE = DataStorage:getSettingsDir() .. "/webdavsync.lua"

local DEFAULT_SETTINGS = {
    server_index = nil,
    local_path = nil,
    auto_analyze = false,
    auto_sync = false,
}

local settings

function Config.init()
    settings = LuaSettings:open(CONFIG_FILE)
end

function Config.getSetting(name)
    return settings:readSetting(name, DEFAULT_SETTINGS[name])
end

function Config.setSetting(name, value)
    settings:saveSetting(name, value)
    settings:flush()
end

function Config.normalizeLocalPath(path)
    if type(path) ~= "string" then
        return nil
    end

    path = path:match("^%s*(.-)%s*$")

    if path == "" then
        return nil
    end

    if path:find("%z") then
        return nil
    end

    path = path:gsub("/+", "/")

    -- The user may enter the complete /mnt/us/... path.
    if path == "/mnt/us" then
        return nil
    elseif path:sub(1, 8) == "/mnt/us/" then
        path = path:sub(9)
    elseif path:sub(1, 1) == "/" then
        path = path:gsub("^/+", "")
    end

    path = path:gsub("^/+", "")

    path = path:gsub("/+", "/")

    if path:find("%.%.") then
        return nil
    end

    if path == "" then
        return nil
    end

    return "/mnt/us/" .. path
end

function Config.ensureDirectory(path)
    if type(path) ~= "string" or path == "" then
        return false
    end

    if lfs.attributes(path, "mode") == "directory" then
        return true
    end

    local parts = {}

    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end

    local current = ""

    if path:sub(1, 1) == "/" then
        current = "/"
    end

    for _, part in ipairs(parts) do
        if current == "/" then
            current = current .. part
        elseif current == "" then
            current = part
        else
            current = current .. "/" .. part
        end

        if lfs.attributes(current, "mode") ~= "directory" then
            local ok = lfs.mkdir(current)

            if not ok and lfs.attributes(current, "mode") ~= "directory" then
                return false
            end
        end
    end

    return lfs.attributes(path, "mode") == "directory"
end

function Config.getServers()
    local settings_file = DataStorage:getSettingsDir() .. "/cloudstorage.lua"
    local cloudstorage_settings = LuaSettings:open(settings_file)

    local configured = cloudstorage_settings:readSetting("cs_servers", {})
    local servers = {}

    for index, server in ipairs(configured) do
        if type(server) == "table" and server.type == "webdav" then
            table.insert(servers, {
                original_index = index,
                server = server
            })
        end
    end

    return servers
end

function Config.getSelectedServer()
    local selected_index = Config.getSetting("server_index")

    if type(selected_index) ~= "number" then
        return nil
    end

    local servers = Config.getServers()

    for _, entry in ipairs(servers) do
        if entry.original_index == selected_index then
            return entry.server
        end
    end

    return nil
end

function Config.getSelectedServerName()
    local server = Config.getSelectedServer()

    if not server then
        return _("Not selected")
    end

    return server.name or server.address or _("Unnamed WebDAV")
end

function Config.getLocalPath()
    local path = Config.getSetting("local_path")

    if type(path) ~= "string" or path == "" then
        return nil
    end

    return path
end

function Config.getLocalPathName()
    return Config.getLocalPath() or _("Not selected")
end

function Config.checkConfiguration()
    local server = Config.getSelectedServer()
    local local_path = Config.getLocalPath()

    if not server and not local_path then
        Config.showInfo(_("Please configure a WebDAV server and a local destination first."))
        return nil, nil
    end

    if not server then
        Config.showInfo(_("Please configure a WebDAV server first."))
        return nil, nil
    end

    if not local_path then
        Config.showInfo(_("Please configure a local destination first."))
        return nil, nil
    end

    return server, local_path
end

function Config.isConfigured()
    return Config.getSelectedServer() ~= nil
       and Config.getLocalPath() ~= nil
end

function Config.canAutoSync()
    if not Config.isConfigured() then return false end
    return Config.getSetting("auto_analyze")
        or Config.getSetting("auto_sync")
end

function Config.showInfo(text)
    UIManager:show(InfoMessage:new{
        text = text
    })
end

function Config.chooseServer(touchmenu_instance, plugin_instance)
    local servers = Config.getServers()

    local menu
    local items = {}

    table.insert(items, {
        text_func = function()
            local selected_index = Config.getSetting("server_index")

            if selected_index == nil then
                return "✓ " .. _("None")
            end

            return _("None")
        end,

        callback = function()
            Config.setSetting("server_index", nil)

            if plugin_instance then
                plugin_instance:registerEvents()
            end

            if menu then
                menu:updateItems()
            end

            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end
    })

    for _, entry in ipairs(servers) do
        local server = entry.server
        local server_name = server.name or server.address or _("Unnamed WebDAV")

        table.insert(items, {
            text_func = function()
                local selected_index = Config.getSetting("server_index")

                if selected_index == entry.original_index then
                    return "✓ " .. server_name
                end

                return server_name
            end,

            callback = function()
                Config.setSetting("server_index", entry.original_index)

                if plugin_instance then
                    plugin_instance:registerEvents()
                end

                if menu then
                    menu:updateItems()
                end

                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
            end
        })
    end

    menu = Menu:new{
        title = _("WebDAV server"),
        item_table = items
    }

    UIManager:show(menu)
end

function Config.chooseLocalPath(touchmenu_instance, plugin_instance)
    local current = Config.getLocalPath()

    local input_value = ""

    if current and current:sub(1, 8) == "/mnt/us/" then
        input_value = current:sub(9)
    elseif current then
        input_value = current
    end

    local input_dialog

    input_dialog = InputDialog:new{
        title = _("Local destination"),

        input = input_value,

        description = _("Enter the folder relative to /mnt/us/.\n\n" .. "Example: Books/Synced\n\n" ..
                            "The folder will be created automatically " .. "if it does not exist."),

        buttons = {{{
            text = _("Cancel"),
            id = "close",

            callback = function()
                UIManager:close(input_dialog)
            end
        }, {
            text = _("Clear"),

            callback = function()
                Config.setSetting("local_path", nil)

                if plugin_instance then
                    plugin_instance:registerEvents()
                end

                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end

                UIManager:close(input_dialog)
            end
        }, {
            text = _("Save"),
            is_enter_default = true,

            callback = function()
                local value = input_dialog:getInputText()

                if value == "" then
                    Config.setSetting("local_path", nil)

                    if plugin_instance then
                        plugin_instance:registerEvents()
                    end

                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end

                    UIManager:close(input_dialog)
                    return
                end

                local normalized = Config.normalizeLocalPath(value)

                if not normalized then
                    Config.showInfo(_("Invalid destination.") .. "\n\n" .. _("The destination must be inside /mnt/us."))
                    return
                end

                if lfs.attributes(normalized, "mode") ~= "directory" then
                    local ok = Config.ensureDirectory(normalized)

                    if not ok then
                        Config.showInfo(_("Could not create the destination folder."))
                        return
                    end
                end

                Config.setSetting("local_path", normalized)

                if plugin_instance then
                    plugin_instance:registerEvents()
                end

                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end

                UIManager:close(input_dialog)
            end
        }}}
    }

    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function Config.formatSize(bytes)
    if not bytes then return "?" end
    if bytes < 1024 then return tostring(bytes) .. " B" end
    if bytes < 1048576 then return string.format("%.1f KB", bytes / 1024) end
    return string.format("%.1f MB", bytes / 1048576)
end

function Config.getAvailableSpace(path)
    local handle = io.popen('df -B1 "' .. path .. '" 2>/dev/null')
    if handle then
        local result = handle:read("*a")
        handle:close()
        local available = result:match("%S+%s+%S+%s+%S+%s+(%d+)")
        return available and tonumber(available) or nil
    end
    return nil
end

return Config
