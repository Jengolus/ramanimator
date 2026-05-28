
--[[
Ask the server for registered hooks, display them to the user,
then attach one to the active sprite.
--]]

-- Loaded modules are persistent in Aseprite.
package.loaded["emulator"] = nil

local emulator = require("emulator")

local function importHook(message)
  local hookName = emulator.chooseHookDialog{message=message, skipDependent=true}

  if hookName == nil then
    return
  end

  emulator.sendCommand(emulator.addMetadata, "getHook", {name=hookName})
end

emulator.sendCommand(importHook, "getHookOverview")
