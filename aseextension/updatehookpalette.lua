
--[[
Set the palette of an existing hook to what is currently in its slot.
--]]

-- Loaded modules are persistent in Aseprite.
package.loaded["emulator"] = nil

local emulator = require("emulator")

local function importHook(message)
  local dlg = emulator.createHookDialog{message=message, skipDependent=false, hideEmpty=true}

  dlg:number{
    id="paletteIndex",
    label="Hook's palette:",
    text="1"
  }

  local data = dlg:show().data
  if not data.import then
    return
  end

  local hookName = data.chooseHook

  if hookName == nil then
    return
  end

  emulator.sendCommand(emulator.printAnswer, "updateHook", {name=hookName, paletteOnly=true, paletteIndex=data.paletteIndex})
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
