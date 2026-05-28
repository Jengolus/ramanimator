
--[[
Set the trigger of an existing hook to what is currently in that slot.
--]]

-- Loaded modules are persistent in Aseprite.
package.loaded["emulator"] = nil

local emulator = require("emulator")

local function importHook(message)
  local hookName = emulator.chooseHookDialog{message=message, skipDependent=false, hideEmpty=true}

  if hookName == nil then
    return
  end

  emulator.sendCommand(emulator.printAnswer, "updateHook", {name=hookName})
end

local function selectSlot(message)
  local availSlots = {}

  for name, data in pairs(message.slots) do
    if data.order ~= -1 or data.updatable then
      table.insert(availSlots, name)
    end
  end

  emulator.sendCommand(importHook, "getHookOverview", {slots=availSlots})
end

emulator.sendCommand(selectSlot, "getSlots", {listHidden=true})
