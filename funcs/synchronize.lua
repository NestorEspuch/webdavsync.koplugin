local Synchronize = {}

function Synchronize.run(self)
    local server, local_path = self:checkConfiguration()

    if not server or not local_path then
        return
    end

    self:showInfo(_("WebDAV server: ") .. (server.name or server.address or _("Unnamed")) .. "\n\n" ..
                      _("Local destination: ") .. local_path)
end

return Synchronize
