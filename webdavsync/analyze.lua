local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")

local Config = require("webdavsync/config")

local Analyze = {}

----------------------------------------------------------------------
-- Scan local directory recursively
--
-- Returns a table indexed by relative file path.
--
-- Example:
--
-- ["book.epub"] = {
--     name = "book.epub",
--     path = "book.epub",
--     full_path = "/mnt/us/Libros/Synced/book.epub",
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
-- Count files
----------------------------------------------------------------------

function Analyze.countFiles(files)

    local count = 0

    for _ in pairs(files) do
        count = count + 1
    end

    return count
end

----------------------------------------------------------------------
-- Main Analyze operation
--
-- At this stage we ONLY analyze the local directory.
-- WebDAV will be added after this has been verified.
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

    ------------------------------------------------------------------
    -- Count files
    ------------------------------------------------------------------

    local local_count = Analyze.countFiles(local_files)

    ------------------------------------------------------------------
    -- Build result
    ------------------------------------------------------------------

    local server_name = server.name or server.address or _("Unnamed WebDAV")

    local text = _("Analyze") .. "\n\n" .. _("WebDAV server: ") .. server_name .. "\n\n" .. _("Local destination: ") ..
                     local_path .. "\n\n" .. _("Local files found: ") .. tostring(local_count)

    ------------------------------------------------------------------
    -- If files exist, show their paths.
    ------------------------------------------------------------------

    if local_count > 0 then

        local paths = {}

        for path in pairs(local_files) do
            table.insert(paths, path)
        end

        table.sort(paths)

        text = text .. "\n\n" .. _("Files:") .. "\n"

        for _, path in ipairs(paths) do

            local file = local_files[path]

            text = text .. "\n" .. path .. " (" .. tostring(file.size or 0) .. " bytes)"

        end
    end

    Config.showInfo(text)
end

return Analyze
