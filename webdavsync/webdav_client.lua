local Config = require("webdavsync/config")
local logger = require("logger")

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
        logger.dbg("WebDAVSync: WebDAV module not available")
        callback()
        return
    end
    WebDav.base = server
    WebDav.run(callback)
end

function WebDavClient.listFolder(server, path, include_folders)
    local WebDav = getWebDav()
    if not WebDav then
        logger.dbg("WebDAVSync: listFolder - WebDAV module not available")
        return nil
    end
    WebDav.base = server
    local ok, items = pcall(WebDav.listFolder, path, include_folders)
    if not ok then
        logger.dbg("WebDAVSync: listFolder - error: " .. tostring(items))
        return nil
    end
    return items
end

function WebDavClient.downloadFile(url, local_path, progress_callback)
    local WebDav = getWebDav()
    if not WebDav then
        return nil
    end
    local ok, result = pcall(WebDav.downloadFile, url, local_path, progress_callback)
    if not ok then
        logger.dbg("WebDAVSync: downloadFile - error: " .. tostring(result))
        return nil
    end
    return result
end

function WebDavClient.deleteFile(url)
    local WebDav = getWebDav()
    if not WebDav then
        return nil
    end
    local ok, result = pcall(WebDav.deleteFile, url)
    if not ok then
        logger.dbg("WebDAVSync: deleteFile - error: " .. tostring(result))
        return nil
    end
    return result
end

return WebDavClient
