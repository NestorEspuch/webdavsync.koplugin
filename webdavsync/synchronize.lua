local _ = require("gettext")

local Config = require("webdavsync/config")

local Synchronize = {}

function Synchronize.run()
    Config.showInfo(_("Synchronize is not implemented yet."))
end

return Synchronize
