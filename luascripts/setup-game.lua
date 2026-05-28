
--[[
This prints the block for the setup of a generic game. The library that
generates is functionally equivalent to what you get without any setup,
but it makes it clearer where hooks and animations need to be placed
once they are generated.
--]]

local base64 = require("base64")

local function printCode(code)
  console:log("Add the following block to ramanimator/identify-checksum.lua. If you already added one for this game, replace it. Stretch this scripting window to be so wide that all lines fit without wrapping around before copying. Do not copy the ---------")

  local checksum = base64.encode(emu:checksum())
  local name = emu:getGameTitle()
  console:log(string.format(code, checksum, name))
  console:log("After saving the modified file, reset and reload all scripts.")
end

code = [[
-----------
    if checksum == "%s" and name == "%s" then
        -- Add the game's name inside the ""
        local gameName = "Manually setup game"

        -- Replace the file names once you have hook and animation files.
        local hookmod = require("myfiles/emptyhooks")
        local anims = {}

        local slots, hooks = table.unpack(hookmod)

        local extras = {}

        return Library:new(gameName, slots, hooks, extras, anims)
    end
-----------
]]

console:log("\n")
printCode(code)
