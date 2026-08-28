local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")

local Config = require("webdavsync/config")
local WebDavClient = require("webdavsync/webdav_client")

local Analyze = {}

local REMOTE_MAX_DEPTH = 10

----------------------------------------------------------------------
-- Scan local directory recursively
--
-- Returns a table indexed by relative file path.
----------------------------------------------------------------------

function Analyze.scanLocalDirectory(local_path)

    local files = {}

    local function scanDirectory(current_path, relative_path)

        local iterator, directory = lfs.dir(current_path)

        if not iterator or not directory then
            return false
        end

        for entry in iterator, directory do

            if entry ~= "." and entry ~= ".." then

                local full_path = current_path .. "/" .. entry
                local attributes = lfs.attributes(full_path)

                if attributes then

                    if attributes.mode == "directory" then

                        local child_relative_path

                        if relative_path == "" then
                            child_relative_path = entry
                        else
                            child_relative_path = relative_path .. "/" .. entry
                        end

                        local ok = scanDirectory(full_path, child_relative_path)

                        if not ok then
                            return false
                        end

                    elseif attributes.mode == "file" then

                        local relative_file_path

                        if relative_path == "" then
                            relative_file_path = entry
                        else
                            relative_file_path = relative_path .. "/" .. entry
                        end

                        files[relative_file_path] = {
                            name = entry,
                            path = relative_file_path,
                            full_path = full_path,
                            size = attributes.size,
                            modified = attributes.modification
                        }

                    end
                end
            end
        end

        return true
    end

    if lfs.attributes(local_path, "mode") ~= "directory" then
        return nil
    end

    local ok = scanDirectory(local_path, "")

    if not ok then
        return nil
    end

    return files
end

----------------------------------------------------------------------
-- Scan remote WebDAV directory iteratively (DFS, depth-capped)
--
-- Each stack entry carries its depth level so we cap on actual
-- depth, not on the number of folders processed.
--
-- Temporarily enables show_unsupported so ALL file types are
-- returned, not just formats KOReader can open.
----------------------------------------------------------------------

function Analyze.scanRemoteDirectory(server)

    local files = {}
    local url_prefix = (server.url or ""):match("^/*(.-)/*$") .. "/"
    local start_url = server.url or ""

    -- Temporarily enable show_unsupported to get all file types.
    local settings_file = DataStorage:getSettingsDir() .. "/.settings/reader.lua"
    local reader_settings = LuaSettings:open(settings_file)
    local was_unsupported = reader_settings:isTrue("show_unsupported")
    reader_settings:saveSetting("show_unsupported", true)
    reader_settings:flush()

    local stack = {{url = start_url, level = 0}}

    while #stack > 0 do

        local current = table.remove(stack)

        if current.level < REMOTE_MAX_DEPTH then

            local items = WebDavClient.listFolder(server, current.url, true)

            if items then

                for _, item in ipairs(items) do

                    if item.is_file then

                        local name = item.text

                        if not name:match("^%.") then
                            local relative = item.url:match("^" .. url_prefix:gsub("/", "%%/") .. "(.+)$")
                            if relative then
                                files[relative] = {
                                    name = name,
                                    url = item.url,
                                    size = item.filesize,
                                }
                            end
                        end

                    elseif item.is_folder then

                        local name = item.text:gsub("/$", "")

                        if not name:match("^%.") then
                            table.insert(stack, {
                                url = item.url,
                                level = current.level + 1,
                            })
                        end

                    end
                end
            end
        end
    end

    reader_settings:saveSetting("show_unsupported", was_unsupported)
    reader_settings:flush()

    return files
end

----------------------------------------------------------------------
-- Compare local and remote files
----------------------------------------------------------------------

function Analyze.compare(local_files, remote_files)

    local result = {
        local_only = {},
        remote_only = {},
        same_size = {},
        incomplete = {},
        different_size = {},
    }

    for path, file in pairs(local_files) do
        if remote_files[path] then
            local remote = remote_files[path]
            if remote.size and file.size then
                if remote.size == file.size then
                    table.insert(result.same_size, {
                        path = path,
                        size = file.size,
                    })
                elseif remote.size > file.size then
                    table.insert(result.incomplete, {
                        path = path,
                        local_size = file.size,
                        remote_size = remote.size,
                    })
                else
                    table.insert(result.different_size, {
                        path = path,
                        local_size = file.size,
                        remote_size = remote.size,
                    })
                end
            else
                table.insert(result.incomplete, {
                    path = path,
                    local_size = file.size,
                    remote_size = remote.size,
                })
            end
        else
            table.insert(result.local_only, {
                path = path,
                size = file.size,
            })
        end
    end

    for path, file in pairs(remote_files) do
        if not local_files[path] then
            table.insert(result.remote_only, {
                path = path,
                size = file.size,
            })
        end
    end

    table.sort(result.local_only, function(a, b) return a.path < b.path end)
    table.sort(result.remote_only, function(a, b) return a.path < b.path end)
    table.sort(result.same_size, function(a, b) return a.path < b.path end)
    table.sort(result.incomplete, function(a, b) return a.path < b.path end)
    table.sort(result.different_size, function(a, b) return a.path < b.path end)

    return result
end

----------------------------------------------------------------------
-- Format file size for display
----------------------------------------------------------------------

local function formatSize(bytes)
    if not bytes then return "?" end
    if bytes < 1024 then return tostring(bytes) .. " B" end
    if bytes < 1048576 then return string.format("%.1f KB", bytes / 1024) end
    return string.format("%.1f MB", bytes / 1048576)
end

----------------------------------------------------------------------
-- Build a folder tree from a flat list of file items.
--
-- Input:  [{path = "A/S/book.epub", ...}, ...]
-- Output: { folders = { ["A"] = { folders = { ["S"] = { files = {...} } } } },
--           files = {root-level files} }
----------------------------------------------------------------------

local function buildFolderTree(items)

    local tree = {folders = {}, files = {}}

    for _, item in ipairs(items) do
        local parts = {}
        for part in item.path:gmatch("[^/]+") do
            table.insert(parts, part)
        end

        local current = tree

        if #parts > 1 then
            for i = 1, #parts - 1 do
                local folder = parts[i]
                if not current.folders[folder] then
                    current.folders[folder] = {folders = {}, files = {}}
                end
                current = current.folders[folder]
            end
        end

        table.insert(current.files, {
            text = parts[#parts],
            size = item.size,
            local_size = item.local_size,
            remote_size = item.remote_size,
        })
    end

    return tree
end

----------------------------------------------------------------------
-- Count all files in a tree
----------------------------------------------------------------------

local function countTreeFiles(tree)
    local count = #tree.files
    for _, sub in pairs(tree.folders) do
        count = count + countTreeFiles(sub)
    end
    return count
end

----------------------------------------------------------------------
-- Sort files in a tree by name
----------------------------------------------------------------------

local function sortTree(tree)
    table.sort(tree.files, function(a, b) return a.text < b.text end)
    for _, sub in pairs(tree.folders) do
        sortTree(sub)
    end
end

----------------------------------------------------------------------
-- Folder browser: single Menu using KOReader's native sub_item_table
-- for forward navigation and item_table_stack for back navigation.
----------------------------------------------------------------------

function Analyze.showFolderBrowser(title, items, categories_menu)

    local tree = buildFolderTree(items)
    sortTree(tree)

    local menu

    local function buildItemTable(node, include_back)
        local item_table = {}

        -- Back button at the top when not at root.
        if include_back then
            table.insert(item_table, {
                text = _(".."),
                callback = function()
                    menu:onClose()
                end,
            })
        end

        local sorted_folders = {}
        for name, sub in pairs(node.folders) do
            table.insert(sorted_folders, {name = name, sub = sub})
        end
        table.sort(sorted_folders, function(a, b) return a.name < b.name end)

        for _, entry in ipairs(sorted_folders) do
            local sub = entry.sub
            local sub_items = buildItemTable(sub, true)
            table.insert(item_table, {
                text = entry.name .. "/ (" .. countTreeFiles(sub) .. ")",
                sub_item_table = sub_items,
            })
        end

        local sorted_files = {}
        for _, file in ipairs(node.files) do
            table.insert(sorted_files, file)
        end
        table.sort(sorted_files, function(a, b) return a.text < b.text end)

        for _, file in ipairs(sorted_files) do
            local size_str = ""
            if file.size then
                size_str = " — " .. formatSize(file.size)
            elseif file.local_size or file.remote_size then
                local parts = {}
                if file.local_size then
                    table.insert(parts, _("local") .. ": " .. formatSize(file.local_size))
                end
                if file.remote_size then
                    table.insert(parts, _("remote") .. ": " .. formatSize(file.remote_size))
                end
                size_str = " — " .. table.concat(parts, ", ")
            end
            table.insert(item_table, {
                text = file.text .. size_str,
            })
        end

        return item_table
    end

    local item_table = buildItemTable(tree, false)

    menu = Menu:new{
        title = title,
        item_table = item_table,
        close_callback = function()
            if categories_menu then
                UIManager:close(categories_menu)
            end
        end,
    }

    UIManager:show(menu)
end

----------------------------------------------------------------------
-- Show results: InfoMessage summary + navigable Menu
----------------------------------------------------------------------

function Analyze.showResults(server, local_path, local_count, remote_count, result)

    local server_name = server.name or server.address or _("Unnamed WebDAV")

    local summary = _("Analyze") .. "\n\n"
        .. _("WebDAV server: ") .. server_name .. "\n"
        .. _("Local destination: ") .. local_path .. "\n\n"
        .. _("Local files: ") .. tostring(local_count)
        .. "     " .. _("WebDAV files: ") .. tostring(remote_count) .. "\n"
        .. _("Only local: ") .. tostring(#result.local_only)
        .. "     " .. _("Only WebDAV: ") .. tostring(#result.remote_only) .. "\n"
        .. _("Same size: ") .. tostring(#result.same_size)
        .. "     " .. _("Incomplete: ") .. tostring(#result.incomplete) .. "\n"
        .. _("Different size: ") .. tostring(#result.different_size)

    UIManager:show(InfoMessage:new{text = summary})

    local categories = {}
    local categories_menu

    local function addCategory(label, count, items)
        table.insert(categories, {
            text = label .. " (" .. count .. ")",
            callback = function()
                Analyze.showFolderBrowser(label, items, categories_menu)
            end,
        })
    end

    if #result.remote_only > 0 then
        addCategory(_("Only on WebDAV"), #result.remote_only, result.remote_only)
    end

    if #result.local_only > 0 then
        addCategory(_("Only local"), #result.local_only, result.local_only)
    end

    if #result.incomplete > 0 then
        addCategory(_("Incomplete downloads"), #result.incomplete, result.incomplete)
    end

    if #result.different_size > 0 then
        addCategory(_("Different size"), #result.different_size, result.different_size)
    end

    if #result.same_size > 0 then
        addCategory(_("Same size"), #result.same_size, result.same_size)
    end

    if #categories > 0 then
        categories_menu = Menu:new{
            title = _("Results"),
            item_table = categories,
        }
        UIManager:show(categories_menu)
    end
end

----------------------------------------------------------------------
-- Main Analyze operation
----------------------------------------------------------------------

function Analyze.run()

    local server, local_path = Config.checkConfiguration()

    if not server or not local_path then
        return
    end

    if lfs.attributes(local_path, "mode") ~= "directory" then
        Config.showInfo(_("The local destination does not exist.") .. "\n\n" .. local_path)
        return
    end

    local local_files = Analyze.scanLocalDirectory(local_path)

    if not local_files then
        Config.showInfo(_("Could not read the local destination.") .. "\n\n" .. local_path)
        return
    end

    local local_count = Analyze.countFiles(local_files)

    local analyzing = InfoMessage:new{text = _("Analyzing remote files...")}
    UIManager:show(analyzing)
    UIManager:forceRePaint()

    WebDavClient.run(server, function()
        UIManager:close(analyzing)

        local remote_files = Analyze.scanRemoteDirectory(server)

        if not remote_files then
            Config.showInfo(_("Could not connect to the WebDAV server."))
            return
        end

        local remote_count = Analyze.countFiles(remote_files)

        local result = Analyze.compare(local_files, remote_files)

        Analyze.showResults(server, local_path, local_count, remote_count, result)
    end)
end

----------------------------------------------------------------------
-- Count files
----------------------------------------------------------------------

function Analyze.countFiles(files)
    local count = 0
    for _ in pairs(files) do
        count = count + 1
    end
    return count
end

return Analyze
