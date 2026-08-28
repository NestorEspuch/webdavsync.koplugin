local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Config = require("webdavsync/config")
local Analyze = require("webdavsync/analyze")
local WebDavClient = require("webdavsync/webdav_client")

local Synchronize = {}

local function cleanupTempFiles(path)
    local iterator, directory = lfs.dir(path)
    if not iterator or not directory then return end

    for entry in iterator, directory do
        if entry ~= "." and entry ~= ".." then
            local full_path = path .. "/" .. entry
            local attrs = lfs.attributes(full_path)
            if attrs and attrs.mode == "directory" then
                cleanupTempFiles(full_path)
            elseif attrs and attrs.mode == "file" and entry:match("%.tmp$") then
                os.remove(full_path)
            end
        end
    end
end

local function deleteEmptyDirs(path)
    local iterator, directory = lfs.dir(path)
    if not iterator or not directory then return end

    for entry in iterator, directory do
        if entry ~= "." and entry ~= ".." then
            local full_path = path .. "/" .. entry
            local attrs = lfs.attributes(full_path)
            if attrs and attrs.mode == "directory" then
                deleteEmptyDirs(full_path)
                lfs.rmdir(full_path)
            end
        end
    end
end

function Synchronize.run()

    local server, local_path = Config.checkConfiguration()
    if not server then return end

    if lfs.attributes(local_path, "mode") ~= "directory" then
        Config.showInfo(_("Local destination does not exist."))
        return
    end

    cleanupTempFiles(local_path)

    WebDavClient.run(server, function()
        Trapper:wrap(function()

            Trapper:info(_("Scanning remote files..."))
            local remote_files = Analyze.scanRemoteDirectory(server)
            if not remote_files then
                Trapper:clear()
                UIManager:show(InfoMessage:new{
                    text = _("Error reading remote files."),
                })
                return
            end

            Trapper:info(_("Scanning local files..."))
            local local_files = Analyze.scanLocalDirectory(local_path)
            if not local_files then
                Trapper:clear()
                UIManager:show(InfoMessage:new{
                    text = _("Error reading local files."),
                })
                return
            end

            local result = Analyze.compare(local_files, remote_files)

            local to_download = result.remote_only
            local to_incomplete = result.incomplete
            local to_delete = result.local_only

            local total_count = #to_download + #to_incomplete + #to_delete
            if total_count == 0 then
                Trapper:clear()
                UIManager:show(InfoMessage:new{
                    text = _("Nothing to synchronize."),
                })
                return
            end

            -- Calculate total download size.
            local total_size = 0
            for _, file in ipairs(to_download) do
                if file.size then
                    total_size = total_size + file.size
                end
            end
            for _, file in ipairs(to_incomplete) do
                if file.remote_size then
                    total_size = total_size + file.remote_size
                end
            end

            -- Check available disk space.
            local available = Config.getAvailableSpace(local_path)
            if available and total_size > available then
                Trapper:clear()
                UIManager:show(InfoMessage:new{
                    text = _("Not enough disk space.") .. "\n\n"
                        .. _("Needed: ") .. Config.formatSize(total_size) .. "\n"
                        .. _("Available: ") .. Config.formatSize(available),
                })
                return
            end

            local errors = {}
            local downloaded = 0
            local redownloaded = 0
            local deleted = 0

            -- Download new files (remote_only).
            for i, file in ipairs(to_download) do
                local remote_entry = remote_files[file.path]
                if not remote_entry then
                    table.insert(errors, {file = file.path, error = "URL not found"})
                else
                    local name = file.path:match("([^/]+)$")
                    local size_str = file.size and Config.formatSize(file.size) or ""
                    local text = string.format(
                        _("Downloading %d/%d\n\n%s\n%s"),
                        i, #to_download, name, size_str
                    )
                    if not Trapper:info(text) then break end

                    local dir_path = local_path .. "/" .. file.path:match("(.*/)")
                    if dir_path and dir_path ~= local_path .. "/" then
                        Config.ensureDirectory(dir_path)
                    end

                    local full_path = local_path .. "/" .. file.path
                    local temp_path = full_path .. ".tmp"
                    local code = WebDavClient.downloadFile(remote_entry.url, temp_path)

                    if code == 200 then
                        os.rename(temp_path, full_path)
                        downloaded = downloaded + 1
                    else
                        os.remove(temp_path)
                        table.insert(errors, {
                            file = file.path,
                            error = "HTTP " .. tostring(code or "nil"),
                        })
                    end
                end
            end

            -- Re-download incomplete files (local < remote).
            for i, file in ipairs(to_incomplete) do
                local remote_entry = remote_files[file.path]
                if not remote_entry then
                    table.insert(errors, {file = file.path, error = "URL not found"})
                else
                    local name = file.path:match("([^/]+)$")
                    local size_str = file.remote_size and Config.formatSize(file.remote_size) or ""
                    local text = string.format(
                        _("Re-downloading %d/%d\n\n%s (incomplete)\n%s"),
                        i, #to_incomplete, name, size_str
                    )
                    if not Trapper:info(text) then break end

                    local dir_path = local_path .. "/" .. file.path:match("(.*/)")
                    if dir_path and dir_path ~= local_path .. "/" then
                        Config.ensureDirectory(dir_path)
                    end

                    local full_path = local_path .. "/" .. file.path
                    local temp_path = full_path .. ".tmp"
                    local code = WebDavClient.downloadFile(remote_entry.url, temp_path)

                    if code == 200 then
                        os.rename(temp_path, full_path)
                        redownloaded = redownloaded + 1
                    else
                        os.remove(temp_path)
                        table.insert(errors, {
                            file = file.path,
                            error = "HTTP " .. tostring(code or "nil"),
                        })
                    end
                end
            end

            -- Delete local-only files.
            for i, file in ipairs(to_delete) do
                local name = file.path:match("([^/]+)$") or file.path
                local text = string.format(
                    _("Deleting %d/%d\n\n%s"),
                    i, #to_delete, name
                )
                if not Trapper:info(text) then break end

                local remote_url = (server.url or ""):match("^/*(.-)/*$")
                    .. "/" .. file.path

                local ok = WebDavClient.deleteFile(remote_url)

                if not ok then
                    local full_path = local_path .. "/" .. file.path
                    local local_ok = os.remove(full_path)
                    if local_ok then
                        deleted = deleted + 1
                    else
                        table.insert(errors, {
                            file = file.path,
                            error = "Delete failed",
                        })
                    end
                else
                    deleted = deleted + 1
                end
            end

            -- Clean up empty directories.
            deleteEmptyDirs(local_path)

            -- Final summary.
            Trapper:clear()

            local final = _("Synchronization complete") .. "\n\n"
                .. _("Downloaded: ") .. tostring(downloaded) .. "\n"
                .. _("Re-downloaded: ") .. tostring(redownloaded) .. "\n"
                .. _("Deleted: ") .. tostring(deleted)

            if #errors > 0 then
                final = final .. "\n\n" .. _("Errors: ") .. tostring(#errors) .. "\n"
                for _, err in ipairs(errors) do
                    final = final .. "\n  " .. err.file .. " — " .. err.error
                end
            end

            UIManager:show(InfoMessage:new{text = final})
        end)
    end)
end

return Synchronize
