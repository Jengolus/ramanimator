
--[[
Unload all animations from the library on the emulator so we can have a
clean export of new animations.
--]]

-- Loaded modules are persistent in Aseprite.
package.loaded["emulator"] = nil

local emulator = require("emulator")

emulator.sendCommand(emulator.printAnswer, "unloadAnimations")
