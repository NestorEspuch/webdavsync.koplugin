local Config = require("webdavsync/config")

local WebDavClient = {}

local function getWebDav()
    local ok, WebDav = pcall(require, "providers/webdav")
    if ok then
        return WebDav
    end
    return nil
end

function WebDavClient.run(server, callback)
    local WebDav = getWebDav()
    if not WebDav then
        Config.showInfo("WebDAV module not available.")
        return
    end
    WebDav.base = server
    WebDav.run(callback)
end

function WebDavClient.listFolder(server, path, include_folders)
    local WebDav = getWebDav()
    if not WebDav then
        return nil
    end
    WebDav.base = server
    return WebDav.listFolder(path, include_folders)
end

function WebDavClient.downloadFile(url, local_path, progress_callback)
    local WebDav = getWebDav()
    if not WebDav then
        return nil
    end
    return WebDav.downloadFile(url, local_path, progress_callback)
end

function WebDavClient.deleteFile(url)
    local WebDav = getWebDav()
    if not WebDav then
        return nil
    end
    return WebDav.deleteFile(url)
end

return WebDavClient
