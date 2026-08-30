local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local logger = require("logger")
local _ = require("gettext")

local Config = require("webdavsync/config")
local Menu = require("webdavsync/menu")
local Analyze = require("webdavsync/analyze")
local Synchronize = require("webdavsync/synchronize")
local WebDavClient = require("webdavsync/webdav_client")
local lfs = require("libs/libkoreader-lfs")

local WebDAVSync = WidgetContainer:extend{
    name = "webdavsync",
    is_doc_only = false
}

function WebDAVSync:init()
    Config.init()

    self.ui.menu:registerToMainMenu(self)
    self:registerEvents()
end

function WebDAVSync:registerEvents()
    if Config.canAutoSync() then
        self.onResume = self._onResume
    else
        self.onResume = nil
    end
end

function WebDAVSync:_onResume()
    logger.dbg("WebDAVSync: onResume")

    if self.is_running then
        logger.dbg("WebDAVSync: already running, skipping")
        return
    end

    UIManager:scheduleIn(10, function()
        self:autoSyncCheck()
    end)
end

function WebDAVSync:autoSyncCheck()
    if not Config.canAutoSync() then return end

    if not NetworkMgr:isOnline() then
        logger.dbg("WebDAVSync: not online, skipping")
        return
    end

    self.is_running = true

    UIManager:scheduleIn(180, function()
        if self.is_running then
            logger.dbg("WebDAVSync: safety timeout, resetting is_running")
            self.is_running = false
        end
    end)

    if Config.getSetting("auto_sync") then
        logger.dbg("WebDAVSync: starting auto-sync")
        self:doAutoSync()
    elseif Config.getSetting("auto_analyze") then
        logger.dbg("WebDAVSync: starting auto-analyze")
        self:doAutoAnalyze()
    else
        self.is_running = false
    end
end

function WebDAVSync:doAutoAnalyze()
    local server, local_path = Config.checkConfiguration()
    if not server or not local_path then
        logger.dbg("WebDAVSync: doAutoAnalyze - no config, aborting")
        self.is_running = false
        return
    end

    if lfs.attributes(local_path, "mode") ~= "directory" then
        logger.dbg("WebDAVSync: doAutoAnalyze - local dir not found")
        self.is_running = false
        return
    end

    local local_files = Analyze.scanLocalDirectory(local_path)
    if not local_files then
        logger.dbg("WebDAVSync: doAutoAnalyze - scanLocal failed")
        self.is_running = false
        return
    end

    WebDavClient.run(server, function()
        Analyze.scanRemoteDirectoryAsync(server, function(remote_files)
            if not remote_files then
                logger.dbg("WebDAVSync: auto-analyze failed, no remote data")
                self.is_running = false
                return
            end

            local result = Analyze.compare(local_files, remote_files)

            if #result.remote_only == 0 then
                logger.dbg("WebDAVSync: auto-analyze - no new books")
                self.is_running = false
                return
            end

            logger.dbg("WebDAVSync: auto-analyze - " .. #result.remote_only .. " new books")

            UIManager:show(ConfirmBox:new{
                text = _("Found ") .. tostring(#result.remote_only) .. " " .. _("new books on server"),
                ok_text = _("Sync now"),
                ok_callback = function()
                    self.is_running = false
                    UIManager:nextTick(function()
                        Synchronize.run()
                    end)
                end,
                cancel_text = _("Close"),
                cancel_callback = function()
                    self.is_running = false
                end,
            })
        end)
    end)
end

function WebDAVSync:doAutoSync()
    local server, local_path = Config.checkConfiguration()
    if not server or not local_path then
        self.is_running = false
        return
    end

    if lfs.attributes(local_path, "mode") ~= "directory" then
        self.is_running = false
        return
    end

    Synchronize.cleanupTempFiles(local_path)

    WebDavClient.run(server, function()
        Analyze.scanRemoteDirectoryAsync(server, function(remote_files)
            if not remote_files then
                logger.dbg("WebDAVSync: auto-sync failed, no remote data")
                self.is_running = false
                return
            end

            local local_files = Analyze.scanLocalDirectory(local_path)
            if not local_files then
                logger.dbg("WebDAVSync: auto-sync failed, no local data")
                self.is_running = false
                return
            end

            local result = Analyze.compare(local_files, remote_files)
            local to_download = result.remote_only
            local to_incomplete = result.incomplete
            local to_delete = result.local_only

            local remote_count = Analyze.countFiles(remote_files)
            local local_count = Analyze.countFiles(local_files)

            if remote_count == 0 and local_count > 0 then
                logger.dbg("WebDAVSync: auto-sync ABORT remote=0, local=" .. local_count)
                self.is_running = false
                return
            end

            local total_count = #to_download + #to_incomplete + #to_delete
            if total_count == 0 then
                logger.dbg("WebDAVSync: auto-sync - nothing to sync")
                self.is_running = false
                return
            end

            local total_size = 0
            for _, file in ipairs(to_download) do
                if file.size then total_size = total_size + file.size end
            end
            for _, file in ipairs(to_incomplete) do
                if file.remote_size then total_size = total_size + file.remote_size end
            end

            local available = Config.getAvailableSpace(local_path)
            if available and total_size > available then
                logger.dbg("WebDAVSync: auto-sync - not enough disk space")
                self.is_running = false
                return
            end

            local errors = {}
            local added_names = {}
            local modified_names = {}
            local deleted_names = {}

            local ops = {}
            for _, file in ipairs(to_download) do
                table.insert(ops, {kind = "download", file = file})
            end
            for _, file in ipairs(to_incomplete) do
                table.insert(ops, {kind = "incomplete", file = file})
            end
            for _, file in ipairs(to_delete) do
                table.insert(ops, {kind = "delete", file = file})
            end

            local function runOp(op)
                local file = op.file
                local name = file.path:match("([^/]+)$") or file.path

                if op.kind == "delete" then
                    local remote_url = (server.url or ""):match("^/*(.-)/*$") .. "/" .. file.path
                    local ok = WebDavClient.deleteFile(remote_url)
                    if not ok then
                        local full_path = local_path .. "/" .. file.path
                        if os.remove(full_path) then
                            table.insert(deleted_names, name)
                        else
                            table.insert(errors, {file = file.path, error = "Delete failed"})
                        end
                    else
                        table.insert(deleted_names, name)
                    end
                    return
                end

                local remote_entry = remote_files[file.path]
                if not remote_entry then
                    return
                end

                local dir_path = local_path .. "/" .. file.path:match("(.*/)")
                if dir_path and dir_path ~= local_path .. "/" then
                    Config.ensureDirectory(dir_path)
                end

                local full_path = local_path .. "/" .. file.path
                local temp_path = full_path .. ".tmp"
                local code = WebDavClient.downloadFile(remote_entry.url, temp_path)

                if code == 200 then
                    os.rename(temp_path, full_path)
                    if op.kind == "download" then
                        table.insert(added_names, name)
                    else
                        table.insert(modified_names, name)
                    end
                else
                    os.remove(temp_path)
                    table.insert(errors, {file = file.path, error = "HTTP " .. tostring(code or "nil")})
                end
            end

            local function finish()
                Synchronize.deleteEmptyDirs(local_path)

                local total = #added_names + #modified_names + #deleted_names
                if total == 0 then
                    logger.dbg("WebDAVSync: auto-sync - nothing synced")
                    self.is_running = false
                    return
                end

                logger.dbg("WebDAVSync: auto-sync - added=" .. #added_names
                    .. " modified=" .. #modified_names
                    .. " deleted=" .. #deleted_names)

                local summary = _("Added: ") .. tostring(#added_names)
                    .. " · " .. _("Deleted: ") .. tostring(#deleted_names)
                    .. " · " .. _("Modified: ") .. tostring(#modified_names)

                if total <= 3 then
                    for _, name in ipairs(added_names) do
                        summary = summary .. "\n  + " .. name
                    end
                    for _, name in ipairs(deleted_names) do
                        summary = summary .. "\n  - " .. name
                    end
                    for _, name in ipairs(modified_names) do
                        summary = summary .. "\n  ~ " .. name
                    end
                end

                if #errors > 0 then
                    summary = summary .. "\n\n" .. _("Errors: ") .. tostring(#errors)
                end

                UIManager:show(InfoMessage:new{text = summary})
                self.is_running = false
            end

            local i = 1
            local function step()
                if i > #ops then
                    finish()
                    return
                end
                runOp(ops[i])
                i = i + 1
                UIManager:scheduleIn(0.05, step)
            end

            UIManager:scheduleIn(0.05, step)
        end)
    end)
end

function WebDAVSync:addToMainMenu(menu_items)
    Menu.addToMainMenu(menu_items, self)
end

return WebDAVSync
