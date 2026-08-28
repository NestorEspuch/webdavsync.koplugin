local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")

local Config = require("webdavsync/config")
local WebDavClient = require("webdavsync/webdav_client")

local Analyze = {}

local REMOTE_MAX_DEPTH = 20

----------------------------------------------------------------------
-- Scan local directory recursively
--
-- Returns a table indexed by relative file path.
--
-- Example:
--
-- ["Autor/Saga/book.epub"] = {
--     name = "book.epub",
--     path = "Autor/Saga/book.epub",
--     full_path = "/mnt/us/Libros/Synced/Autor/Saga/book.epub",
--     size = 123456,
--     modified = 1234567890,
-- }
--
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

    -- The root directory must exist.
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
-- Returns a table indexed by relative file path (relative to server.url).
--
-- Example:
--
-- ["Autor/Saga/book.epub"] = {
--     name = "book.epub",
--     url = "Libros/Autor/Saga/book.epub",
--     size = 123456,
-- }
--
----------------------------------------------------------------------

function Analyze.scanRemoteDirectory(server)

    local files = {}
    local url_prefix = (server.url or ""):match("^/*(.-)/*$") .. "/"
    local start_url = server.url or ""
    local stack = {start_url}
    local depth = 0

    while #stack > 0 and depth < REMOTE_MAX_DEPTH do

        local current_url = table.remove(stack)
        local items = WebDavClient.listFolder(server, current_url, true)

        if not items then
            return nil
        end

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
                    table.insert(stack, item.url)
                end

            end
        end

        depth = depth + 1
    end

    return files
end

----------------------------------------------------------------------
-- Compare local and remote files
--
-- Returns a table with four lists: local_only, remote_only,
-- same_size, different_size.
----------------------------------------------------------------------

function Analyze.compare(local_files, remote_files)

    local result = {
        local_only = {},
        remote_only = {},
        same_size = {},
        different_size = {},
    }

    for path, file in pairs(local_files) do
        if remote_files[path] then
            local remote = remote_files[path]
            if remote.size and file.size and remote.size == file.size then
                table.insert(result.same_size, {
                    path = path,
                    size = file.size,
                })
            else
                table.insert(result.different_size, {
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
        .. "     " .. _("Different size: ") .. tostring(#result.different_size)

    UIManager:show(InfoMessage:new{text = summary})

    local categories = {}

    if #result.remote_only > 0 then
        table.insert(categories, {
            text = _("Only on WebDAV") .. " (" .. #result.remote_only .. ")",
            callback = function()
                Analyze.showFileList(
                    _("Only on WebDAV"),
                    result.remote_only
                )
            end,
        })
    end

    if #result.local_only > 0 then
        table.insert(categories, {
            text = _("Only local") .. " (" .. #result.local_only .. ")",
            callback = function()
                Analyze.showFileList(
                    _("Only local"),
                    result.local_only
                )
            end,
        })
    end

    if #result.different_size > 0 then
        table.insert(categories, {
            text = _("Different size") .. " (" .. #result.different_size .. ")",
            callback = function()
                Analyze.showFileList(
                    _("Different size"),
                    result.different_size
                )
            end,
        })
    end

    if #result.same_size > 0 then
        table.insert(categories, {
            text = _("Same size") .. " (" .. #result.same_size .. ")",
            callback = function()
                Analyze.showFileList(
                    _("Same size"),
                    result.same_size
                )
            end,
        })
    end

    if #categories > 0 then
        UIManager:show(Menu:new{
            title = _("Results"),
            item_table = categories,
        })
    end
end

----------------------------------------------------------------------
-- Show a list of files for a given category
----------------------------------------------------------------------

function Analyze.showFileList(title, items)

    local file_items = {}

    for _, item in ipairs(items) do
        local size_str = ""
        if item.size then
            size_str = " — " .. formatSize(item.size)
        elseif item.local_size or item.remote_size then
            local parts = {}
            if item.local_size then
                table.insert(parts, _("local") .. ": " .. formatSize(item.local_size))
            end
            if item.remote_size then
                table.insert(parts, _("remote") .. ": " .. formatSize(item.remote_size))
            end
            size_str = " — " .. table.concat(parts, ", ")
        end

        table.insert(file_items, {
            text = item.path .. size_str,
        })
    end

    UIManager:show(Menu:new{
        title = title .. " (" .. #items .. ")",
        item_table = file_items,
    })
end

----------------------------------------------------------------------
-- Main Analyze operation
----------------------------------------------------------------------

function Analyze.run()

    local server, local_path = Config.checkConfiguration()

    if not server or not local_path then
        return
    end

    ------------------------------------------------------------------
    -- Verify local destination
    ------------------------------------------------------------------

    if lfs.attributes(local_path, "mode") ~= "directory" then
        Config.showInfo(_("The local destination does not exist.") .. "\n\n" .. local_path)
        return
    end

    ------------------------------------------------------------------
    -- Scan local files
    ------------------------------------------------------------------

    local local_files = Analyze.scanLocalDirectory(local_path)

    if not local_files then
        Config.showInfo(_("Could not read the local destination.") .. "\n\n" .. local_path)
        return
    end

    local local_count = Analyze.countFiles(local_files)

    ------------------------------------------------------------------
    -- Scan remote files via WebDAV
    ------------------------------------------------------------------

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

        ------------------------------------------------------------------
        -- Compare and show results
        ------------------------------------------------------------------

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
