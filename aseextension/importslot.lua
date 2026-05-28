
--[[
Ask the server for currently available slots, display them to the user,
then import one into a new Sprite.
--]]

-- Loaded modules are persistent in Aseprite.
package.loaded["emulator"] = nil

local emulator = require("emulator")

local function chooseSlotDialog(message)
  if message.status ~= "success" then
    return app.alert("Error trying to load slot information: " ..tostring(message.status))
  end

  local options, err = emulator.getSortedSlots{message=message, kind="tile"}
  if options == nil then
    return app.alert(err)
  end

  if #options < 1 then
    return app.alert("No slots registered for the current ROM.")
  end

  local dlg = Dialog("Choose slot")
  dlg:entry{
    id="hookName",
    label="Hook name",
  }
  dlg:combobox{
    id="chooseSlot",
    label="Choose a slot: ",
    option=options[1],
    options=options
    --onchange=function
  }
  dlg:button{ id="import", text="Import" }
  dlg:button{ id="cancel", text="Cancel" }
  dlg:show()

  local data = dlg.data
  if data.import then
    local slot = data.chooseSlot
    local hookName = data.hookName

    for name, info in pairs(message.slots) do
      if name == slot then
        emulator.sendCommand(emulator.importSprite, "loadSlot", {slotName=name, hookName=hookName})
      end
    end
  end
end

emulator.sendCommand(chooseSlotDialog, "getSlots")
