
--[[
Ask the server for registered hooks, display them to the user,
then import one into a new Sprite. Useful to check whether the hooks are
set up correctly or get something to start drawing.
--]]

-- Loaded modules are persistent in Aseprite.
package.loaded["emulator"] = nil

local emulator = require("emulator")

local function importHook(message)
  local hookName = emulator.chooseHookDialog{message=message, skipDependent=true}

  if hookName == nil then
    return
  end

  emulator.sendCommand(emulator.importSprite, "getHook", {name=hookName})
end

emulator.sendCommand(importHook, "getHookOverview")
