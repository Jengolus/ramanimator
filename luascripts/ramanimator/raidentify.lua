
--[[
Try to identify which game is being played without loading everything into
RAM.
--]]

local raidentify = {}

-- Hard code roms by their checksum
local idchecksum = require("ramanimator/identify-checksum")
-- Mix and match triggers and animations
local idpokemon = require("ramanimator/identify-pokemon")

local idModules = {idchecksum, idpokemon}

function raidentify.identify()
  for _, mod in ipairs(idModules) do
    local lib = mod.getLibrary()

    if lib then
      return lib
    end
  end

  -- Game was not identified
  return nil
end

return raidentify
