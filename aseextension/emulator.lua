
local emulator = {}

local base64 = require("base64")
local connection = require("connection")

local pluginKey = "jengolus/ramanimator"

local dbg = false -- Print debug info

-- https://lospec.com/palette-list/nintendo-gameboy-bgb
-- Colors are distinguishable from each other and transparency grays.
local defaultPalette = {
  Color{r=255, g=255, b=255, a=0},
  Color{r=224, g=248, b=208},
  Color{r=136, g=192, b=106},
  Color{r=52, g=106, b=86},
  Color{r=8, g=24, b=32}
}

function emulator.addMetadata(data, sprite)
  -- Add the metadata of what is currently on screen to the open sprite.
  data = emulator.decodeSpriteData(data)

  if sprite == nil then
    sprite = app.sprite
  end

  sprite.properties(pluginKey, {
      slotName = data.slotName, -- Obsolete I think
      hookName = data.hookName
    })

  if data.hookName ~= nil and sprite.filename == "Sprite" then
    sprite.filename = tostring(data.hookName)
  end
end

function emulator.importSprite(data)
  -- Load tiles from memory, place them in a new sprite
  if data.status ~= "success" then
    return app.alert("Error trying to import a sprite: " .. tostring(data.status))
  end

  data = emulator.decodeSpriteData(data)

  local sprite = Sprite(data.width, data.height, ColorMode.INDEXED)
  emulator.addMetadata(data, sprite)

  if data.name ~= nil then
    sprite.filename = data.name
  end

  local pixels = data.pixels

  local cel = sprite.cels[1] --app.activeCel

  local img = cel.image

  local recPal = {}

  if data.palettes ~= nil then
    for _, palette in ipairs(data.palettes) do
      for _, col in ipairs(palette) do
        table.insert(recPal, col)
      end
    end
  end

  local palSize = math.max(5, #recPal + 1)

  if #recPal % 16 == 0 then
    -- GBA comes with its own transparency color. For simplicity, we just
    -- keep our own and that one since some games might wish to use
    -- graphics without transparency.
  end

  local palette = Palette(palSize)

  palette:setColor(0, Color{r=255, g=255, b=255, a=0})

  for i, col in ipairs(recPal) do
    palette:setColor(i, Color{r=col[1], g=col[2], b=col[3]})
  end

  -- If there was no palette, fill up with a GB-inspired one (GBA games
  -- always send one).
  for i = 1 + #recPal, 4 do
    palette:setColor(i, defaultPalette[i + 1])
  end

  sprite:setPalette(palette)
  
  --for x = 0, data.width - 1 do
  --  for y = 0, data.height - 1 do
  --    img:drawPixel(x, y, pixels:byte(y + x))
  --    --img:drawPixel(x, y, 2)
  --  end
  --end
  local index = 1
  for it in img:pixels() do
    it(pixels:byte(index) + 1)
    index = index + 1
  end

  return sprite
end

function emulator.decodeSpriteData(message)
  -- Decode the sprite contained in the message, unless it is already
  -- decoded.

  if message["_decoded"] then
    return message
  end

  message.pixels = base64.decode(message.pixels)
  message["_decoded"] = true
  return message
end

function emulator.getSortedSlots(args)
  -- Given a message that contains a "slots" attribute, return a list of
  -- their names sorted by their order attribute.
  local message = args.message
  if message.slots == nil then
    return nil, "The server did not provide any slot info."
  end

  local options = {}

  for name, slot in pairs(message.slots) do
    if not (args.skipDependent and slot.dependent) then
      if not args.kind or args.kind == slot.kind then
        local order = slot.order
        if order == -1 then
          order = 1001
        end

        table.insert(options, {name=name, order=order})
      end
    end
  end

  if #options < 0 then
    return nil, "There are no registered slots on the server!"
  end

  table.sort(options, function(a, b)
    return a.order < b.order
  end)

  for i, val in ipairs(options) do
    options[i] = val.name
  end

  return options
end

function emulator.getSortedHookInfo(message)
  --[[
  Given a message that contains a "hooks" attribute, return a list of
  their names sorted alphabetically.
  Optional arguments:
  skipDependent: If a hook contains a dependent attribute, skip it
  kind: Only return hooks of matching kind attribute.
  ]]--
  if message.hooks == nil then
    return nil, "The server did not provide any hook info."
  end

  local hooks = {}

  for k, v in ipairs(message.hooks) do
    table.insert(hooks, v)
  end

  table.sort(hooks, function(a, b)
    return a.name < b.name
  end)

  return hooks
end

function emulator.createHookDialog(args)
  --[[
  Create a dialog for hook selection, but return it prior to showing so
  the caller can add extra fields.
  --]]
  local message = args.message
  if message.status ~= "success" then
    return app.alert("Error trying to load hook information: " ..tostring(message.status))
  end

  local options, err = emulator.getSortedSlots{message=message, kind=args.kind, skipDependent=args.skipDependent}
  if options == nil then
    return app.alert(err)
  end

  local hooks, err = emulator.getSortedHookInfo(message)
  if hooks == nil then
    return app.alert(tostring(err))
  end

  local hookOptions = {}
  local refslot = options[1]

  for i, hook in ipairs(hooks) do
    if hook.slot == refslot then
      table.insert(hookOptions, hook.name)
    end
  end

  if args.hideEmpty then
    -- Remove empty slots
    local flags = {}
    for i, hook in ipairs(hooks) do
      flags[hook.slot] = true
    end

    local empty = {}
    -- Fill it up backwards so the indices stay consistent
    for index, slot in ipairs(options) do
      if not flags[slot] then
        table.insert(empty, 1, index)
      end
    end

    for _, index in ipairs(empty) do
      table.remove(options, index)
    end
  end

  local dlg = Dialog("Choose a hook to import")

  local function filterHooks()
    local data = dlg.data
    local slot = data.chooseSlot

    local filteredOptions = {}

    for i, hook in ipairs(hooks) do
      if hook.slot == slot then
        table.insert(filteredOptions, hook.name)
      end
    end

    dlg:modify{id="chooseHook", options=filteredOptions, option=filteredOptions[1]}
  end

  dlg:combobox{ id="chooseSlot",
                label="Choose a slot: ",
                option=options[1],
                options=options,
                onchange=filterHooks }

  dlg:combobox{ id="chooseHook",
                label="Choose a hook: ",
                option=hookOptions[1],
                options=hookOptions,
                onchange=nil }

  dlg:button{ id="import", text="Import" }
  dlg:button{ id="cancel", text="Cancel" }

  return dlg
end

function emulator.chooseHookDialog(args)
  --[[
  Provide a dialog with one drop-down menu for the available slots as
  a filter, then a menu for the filtered hooks.
  Arguments:
  kind
  skipDependent -- Do not show dependent (sibling) slots.
  hideEmpty -- Do not show slots with 0 hooks.
  --]]
  local dlg = emulator.createHookDialog(args)

  local data = dlg:show().data

  if data.import then
    return data.chooseHook
  end

  return nil
end

function emulator.printAnswer(data)
  local status = data["status"]
  if status ~= "success" then
    app.alert(tostring(status))
  end
end

emulator.sendCommand = connection.sendCommand
-- Only valid for (C)GB
emulator.defaultPalette = defaultPalette

return emulator
