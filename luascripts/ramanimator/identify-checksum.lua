
--[[
For adding new games and hacks, the easiest way is to just add their
checksums here directly. This module should be first in line, that is
bypass everything else.
--]]

local idchecksum = {}

local base64 = require("base64")

local raconfig = require("ramanimator/raconfig")
local ralibrary = require("ramanimator/library")
local Library = ralibrary.Library

function idchecksum.getLibrary()
    -- Just hard-code checksums here
    local checksum = base64.encode(emu:checksum())
    local name = emu:getGameTitle()

    -- Nothing identified
    return nil
end

return idchecksum
