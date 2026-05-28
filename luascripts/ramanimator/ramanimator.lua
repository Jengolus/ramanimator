
--[[
This module handles animations in RAM, most notably for switching out
graphics in real time to animate what is actually a static graphic in
the game.

An animation consists of the following:
- An address
- A byte sequence that triggers the animation
- Strips, which are a list of frames and their timings
- An index into a list of classes that decide which strip comes next

Once the RAM data matches the trigger, the data is replaced by the
first frame and then updated after the supplied number of frames. This
process continues until the content of the RAM gets altered by the game,
in which case we pause the operation. If the RAM returns to the last
frame, the animation proceeds.

This is used to animate tiles directly in VRAM, which is nice because
it is very easy and still allows the game to perform other effects
and animations natively on top.

In Gen3, I think addresses should be stored if a fitting sprite is
discovered and "freed" if it has disappeared for long enough. Longer than
a flicker animation, but Fly etc can reset animations for all I care.
--]]

local ramanimator = {}

ramanimator.lastFrame = 0

local general = require("general")
local libmod = require("ramanimator/library")
local slotmod = require("ramanimator/slot")
local hookmod = require("ramanimator/hook")
local playermod = require("ramanimator/player")
local conversions = require("ramanimator/conversions")

local raconfig = require("ramanimator/raconfig")
local raidentify = require("ramanimator/raidentify")

local server = require("jsonserver")
local base64 = require("base64")
local json = require("json")

-- Forward declaration
local animateLibrary = nil

-- Contains slots and hooks in raw form.
local library = nil

--[[
Most data is restricted to individual libraries, but the animation players
need to be global so that a running animation can be carried over if it is
overwritten.

But really? Can't I just have a palette slot and override the animation?
I do think that sounds reasonable. I'd need to manually deactivate the
subanimations then, which is probably fine. I.e., whenever an animation is
halted, its subanimations are halted, too. Which is elegantly handled by
libraries.

Is there another way of transferring subanimations? Probably yes.
]]--

local function formatUnicodeSprite(sprite, width, height)
  -- Format, but don't print, a frame as unicode art. Dimensions in pixels.
  if not width then width = 56 end
  if not height then height = 56 end

  local out = ""
  local chars = "0123456789ABCDEF"

  -- Check whether we can use a nicer palette
  local useNicePalette = true
  for i = 1, #sprite do
    if sprite:byte(i) >= 4 then
      useNicePalette = false
      break
    end
  end

  if useNicePalette then
    --chars = "█▓▒░" -- mGBA console doesn't support unicode...
    chars = " *%#" -- and is always in light mode
  end

  for row = 1, height do
    for col = 1, width do
      local index = (row - 1) * width + col
      if index <= #sprite then
        out = out .. chars:sub(sprite:byte(index) + 1, sprite:byte(index) + 1)
      else
        out = out .. "?" -- Unexpected byte
      end
    end

    out = out .. "\n"  -- Newline for the next row
  end

  return out
end

local function compareSprites(...)
  -- This handles 2D palette index arrays, use compareVram when comparing
  -- with memory.
  -- Output is automatically printed to console
  local sprites = {...}
  local formattedSprites = {}

  for _, sprite in ipairs(sprites) do
    formattedSprites[#formattedSprites + 1] = formatUnicodeSprite(sprite)
  end

  -- Split the sprites into their lines
  local maxLines = 0
  for i = 1, #formattedSprites do
    local formatted = formattedSprites[i]
    local lines = {}
    for line in formatted:gmatch("[^\n]+") do
      lines[#lines + 1] = line
    end
    maxLines = math.max(maxLines, #lines)
    formattedSprites[i] = lines  -- Store lines for each sprite
  end

  -- Print sprites side by side
  local output = ""
  for lineNumber = 1, maxLines do
    for _, lines in ipairs(formattedSprites) do
      if lines[lineNumber] then
        output = output .. lines[lineNumber] .. " | "  -- Space between sprites
      else
        output = output .. " |  "  -- Space for missing lines
      end
    end
    output = output .. "\n"  -- Newline at the end of each row
  end

  console:log(output)  -- Display the combined sprites
end

local function compareVram(width, height, layout, ...)
  -- To compare frames, triggers etc with VRAM.
  local data = {...}
  local sprites = {}

  for _, dat in pairs(data) do
    sprites[#sprites + 1] = conversions.vram2frame(dat, width, height, layout)
  end

  compareSprites(table.unpack(sprites))
end

function ramanimator.registerAnimation(anim)
  if not library then
    return {status="No library loaded."}
  end

  if not anim.name then return {status="Attribute name is missing!"} end
  if not anim.frames then return {status="'frames' is missing!"} end

  -- Do we know this hook?
  local hook = library.hooks[anim.name]

  if not hook then
    return {status="No hook found for name " .. tostring(anim.name)}
  end

  local slot = hook.slot

  -- Decode all frames
  for i, rawFrame in ipairs(anim.frames) do
    local frame = base64.decode(rawFrame)
    -- Check whether this sprite has the correct size and try to expand
    -- it otherwise.
    if #frame ~= slot.width * slot.height * 8*8 then
      local newFrame = slot:resizeFrame(frame)
      if not newFrame then
        local msg = "Could not load animation " .. anim.name .. " because frame " .. i .. " (" .. #frame .. " pixels) does not have the correct size for slot " .. slot.name .. " (" .. slot.width * slot.height * 64 .. " pixels), which does not have a function to resize it."
        console:error(msg)
        return {status=msg}
      end

      frame = newFrame

      if #frame ~= slot.width * slot.height * 8*8 then
        local msg = "Something went wrong trying to resize animation " .. anim.name .. ": The resized frame is of size " .. #frame .. ", but the slot requires " .. slot.width*slot.height*8*8 .. " pixels."
        console:error(msg)
        return {status=msg}
      end
    end

    anim.frames[i] = conversions.frame2vram(frame, slot.width, slot.height, slot.layout)
    --compareSprites(frame, conversions.vram2frame(anim.frames[i], anim["width"], anim["height"], anim["layout"]))
  end

  for i, strip in ipairs(anim.strips) do
    for iTime, milliseconds in ipairs(strip.timings) do
      strip.timings[iTime] = milliseconds * 60 / 1000
    end
  end

  -- Pack the palettes into the native format
  if anim.palettes then
    local palettes = {}
    for i, palette in ipairs(anim.palettes) do
      palettes[i] = conversions.packPalette(palette)
    end

    anim.palettes = palettes
  end

  -- Means it makes sense to export this
  anim.updated = true
  library:addAnimation(anim)

  return {status="success"}
end

local function checkTriggers(group)
  -- All slots in a group have the same address.
  local slot = group.refSlot
  local current = slot:read()

  -- I don't actually know whether caching is relevant.
  if current == group.cachedRam then
    -- RAM didn't change, so nothing can get triggered.
    return nil
  end

  group.cachedRam = current

  for _, slot in pairs(group.slots) do
    -- Some slots in the list might have different lengths.
    local trigger = current

    if slot.kind ~= "palette" then
      trigger = trigger:sub(1, slot.length)
    end

    local anim = slot.animations[trigger]

    if anim then
      return anim, slot
    end
  end

  return nil
end

local function playAnimation(group, slot, anim, forceSubAnims)
  if forceSubAnims == nil then forceSubAnims = false end

  local oldPlayer = group.player

  group.player = anim.hook:newPlayer(anim, slot)
  -- Force a full scan once this animation is halted.
  group.cachedRam = nil

  -- If the prior animation had active subslots, transfer them to the new
  -- animation since their triggers are overridden.
  if oldPlayer then
    local oldAnim = oldPlayer.anim
    libmod.transferRunningPlayers(oldAnim.subLibrary, anim.subLibrary, false)
    -- If an animation was running in this group, reset the sublibrary.
    local subAnim = oldPlayer.anim
    if subAnim.subLibrary ~= nil then
      subAnim.subLibrary:clearCache()
    end
  end

  if forceSubAnims and anim.subLibrary then
    -- Useful to e.g. activate palette animations no matter what
    -- Only makes sense if there is only one subanim per slot for now.
    for _, subSlot in pairs(anim.subLibrary.slots) do
      local subGroup = anim.subLibrary.slotGroups[subSlot.groupKey]

      if subGroup then
        for _, subAnim in pairs(subSlot.animations) do
          -- Hack: Only default palettes, not shinies; for the demo video
          local subs = subAnim.name:sub(#subAnim.name - 8, #subAnim.name - 8)
          --if emu:platform() ~= C.PLATFORM.GBA or subs == "1" then
          if true then
            playAnimation(subGroup, subSlot, subAnim, true)
            break
          end
        end
      end
    end
  end
end

function ramanimator.playAnimationCmd(args)
  --[[
  A wrapper for playAnimation that allows it to be called via the server.
  --]]
  if args.name == nil then
    return {status="Argument name is missing!"}
  end

  if library == nil then
    return {status="No library loaded!"}
  end

  -- Find the animation and slot
  local name = args.name

  for _, slot in pairs(library.slots) do
    if slot.kind ~= "sprite" then
      for _, anim in pairs(slot.animations) do
        if anim.name == name then
          local group = library.slotGroups[slot.groupKey]
          library.out:print("Playing animation by command:", name, "in", slot.name, "of group", slot.groupKey)
          playAnimation(group, slot, anim, true)

          return {status="success"}
        end
      end
    end
  end

  return {status="No animation of name " .. args.name .. " found!"}
end

local function animateSlotGroup(group)
  -- SpriteSlots don't get animated directly, only their offspring.
  if group.refSlot.kind == "sprite" then return end

  local currentPlayer = group.player

  if currentPlayer then
    -- console:log("Current animation: " .. anim["name"])
    -- Check whether the game has overwritten the RAM itself
    local anim = currentPlayer.anim
    local mem = currentPlayer.slot:read()

    local status, cause = anim.hook:checkRunning(currentPlayer.slot, mem, currentPlayer.frame)

    if status ~= 0 then
      currentPlayer:tick(status > 1)

      -- If there are subanimations, go on.
      animateLibrary(currentPlayer.anim.subLibrary)

      return
    --else
    --  The game has edited the VRAM, so we pause this animation but keep
    --  it active so it can resume after the game has finished. This is
    --  useful because the game might just manipulate the tiles and put
    --  them back to how they were before that rather than reset to the
    --  trigger.
    --
    --  Fall through
    end

    -- Print the frame that paused an animation.
    if currentPlayer.active then
      currentPlayer.debugger:print("Halting animation " .. currentPlayer.anim.name)
      currentPlayer.debugger:print("Cause", cause)
      currentPlayer.active = false
      --compareVram(7, 7, 0, mem, currentPlayer["frame"])

      -- Forward the halt to subanimations.
      local subLibrary = currentPlayer.anim.subLibrary
      if subLibrary ~= nil then
        for _, subGroup in pairs(subLibrary.slotGroups) do
          if subGroup.player then
            subGroup.player.active = false
          end
        end
      end
    end
  end

  -- If no animation has been started or the animation is paused, check
  -- whether a new animation is triggered.
  local anim, slot = checkTriggers(group)
  if anim then
    playAnimation(group, slot, anim)
  end
end

local function animateLibrary_def(lib)
  if not lib then
    return
  end

  -- SpriteSlots get their own branch because they can only spawn other
  -- slots, but not get animated themselves.
  for name, slot in pairs(lib.slots) do
    if slot.kind == "sprite" then
      slot:scanSprites(lib)
    end
  end

  for groupKey, group in pairs(lib.slotGroups) do
    animateSlotGroup(group)
  end
end

animateLibrary = animateLibrary_def

function ramanimator.animate()
  -- On some mGBA versions, frame callbacks don't get reset as expected.
  local currFrame = emu:currentFrame()
  if ramanimator.lastFrame == currFrame then
    return
  end

  ramanimator.lastFrame = currFrame

  animateLibrary(library)
end

local function detectGame()
  local checksum = base64.encode(emu:checksum())
  local name = emu:getGameTitle()
  console:log("ramanimator is looking for the game. Found name " .. tostring(name) .. " and checksum " .. tostring(checksum) .. " (encoded in BASE64).")
  library = raidentify.identify()
  if library then
    console:log("Loaded library: " .. tostring(library.name))
  else
    console:log("The loaded game was not recognized by RAManimator. If somebody provided instructions on how to set it up, follow these. If this is a Pokemon game, use the corresponding setup script in the RAManimator scripts folder. If you want to set up this game yourself, run 'setup-game.lua'.")

    library = libmod.Library:new("Unnamed")
  end

  ramanimator.library = library
end

local function remindReload()
  -- If we put detectGame as the callback, it doesn't have the correct
  -- path for finding the modules.
  console:error("After swapping the game, you need to click File>Reset and reload the script in the Scripting window.")
end

function ramanimator.registerSlot(args)
  --console:log(tostring(args._raw))
  local kind = args.kind
  local address = args.address
  local width  = args.width -- In tiles
  local height = args.height
  local layout = args.layout
  local name   = args.name
  local order  = args.order
  local palette = args.palette

  local orderAppend = false

  if not kind then return {status="Parameter kind missing."} end

  if not address then return {status="Parameter address missing."} end
  if not width then return {status="Parameter width missing."} end
  if not height then return {status="Parameter height missing."} end
  if not layout then return {status="Parameter layout missing."} end
  if not name then return {status="Parameter name missing."} end
  if not order then orderAppend = true end

  if palette then
    palette = {index=palette}
  end

  local maxOrder = 0
  for oname, slot in pairs(library.slots) do
    if oname == name then
      console:log("Overriding existant slot of that name.")
    else
      maxOrder = math.max(maxOrder, slot.order)

      if not orderAppend and slot.order == order then
        console:log("There already is a slot of order " .. order .. ", appending instead.")
        orderAppend = true
      end
    end
  end

  if orderAppend then
    order = maxOrder + 1
  end

  local slot = slotmod.TileSlot:new(name, address, width, height, layout, order, {palette=palette})
  library:addSlot(slot)

  return {status="success"}
end

function ramanimator.loadSlot(args)
  -- Load the content of the current TileSlot. Useful because it
  -- acknowledges palettes etc.
  -- Creates a hook if there isn't one already.
  local slotName = args["slotName"]
  if not slotName then
    return {status="Argument slotName missing."}
  end

  if not library then
    return {status="No library loaded."}
  end

  local hookName = args["hookName"]

  if not hookName then
    return {status="Argument hookName missing."}
  end

  local function getAvailSlots()
    local slotNames = ""

    for name, slot in pairs(library.slots) do
      if slot.kind == "tile" then
        slotNames = slotNames + name + ", "
      end
    end

    if #slotNames <= 2 then
      return "Currently none"
    end

    return slotNames:sub(1, -3)
  end

  for name, slot in pairs(library.slots) do
    if name == slotName then
      -- Return the contents of this slot.
      if slot.kind ~= "tile" then
        return {status="Requested a slot that isn't a TileSlot. Options: " .. slotNames}
      end

      local ramdata = slot:read()
      local trigger = ramdata
      local pixels = conversions.vram2frame(ramdata, slot.width, slot.height, slot.layout)

      local palette = nil
      if slot.subSlots.palette then
        if emu:platform() == C.PLATFORM.GB and emu.readPalette then
          palette = slotmod.newPaletteSlot(slot.subSlots.palette.index):readColors()
        elseif emu:platform() == C.PLATFORM.GBA then
          palette = slotmod.newPaletteSlot(slot.subSlots.palette.index, nil, {address=0x5000000}):readColors()
        end
      end

      -- Do we already have a hook of that name?
      local hook = library.hooks[hookName]
      if hook then
        -- Is the trigger the same?
        if hook.trigger ~= trigger then
          console:warn("There already is a hook called " .. hookName .. ", but with a different trigger. Overriding.")
          hook = nil
        end
      end

      -- Do we already have a hook of that trigger?
      if not hook then
        for name, testHook in pairs(library.hooks) do
          if testHook.trigger == trigger then
            -- Reuse this hook
            hook = testHook
            break
          end
        end
      end

      -- We need to create a new hook.
      if not hook then
        -- If this is a TileSlot spawned from a SpriteSlot, add it to the
        -- parent.
        local targetSlot = slot.parent or slot
        hook = hookmod.Hook:new(hookName, targetSlot, nil, trigger, {palette})

        library:addHook(hook)
      end

      hook.updated = true

      return {status="success", width=8*slot.width,
        height=8*slot.height, pixels=base64.encode(pixels),
        slotName=slotName, hookName=hook.name,
        palettes={conversions.unpackPalette(palette)},
        trigger=base64.encode(trigger),
        rawPalette=palette,
      }
    end
  end

  return {status="No slot of the given name registered. Options: " .. slotNames, name=slotName}
end

function ramanimator.registerHook(args)
  --[[
  Register a hook programmatically. This is intended for easier debugging,
  but might be of further use.
  --]]
  local name = args.name
  local slotName = args.slotName
  local player = args.playerName
  local trigger = args.trigger
  local palettes = args.palettes
  if not palettes then palettes = {args.palette} end -- Convenience
  local extras = args.extras

  -- Extra stuff not implemented
  local errs = ""
  if not name then errs = errs .. "Parameter name is missing.\n" end
  if not slotName then errs = errs .. "Parameter slotName is missing.\n" end
  if not trigger then errs = errs .. "Parameter trigger is missing.\n" end

  if slotName and not library.slots[slotName] then
    errs = errs .. "No slot of handle " .. tostring(slotName) .. " known to library " .. library.name .. ".\n"
  end

  if #errs > 0 then return {status=errs} end

  --print("palettes", palettes)
  --if palettes then
  --  for i, palette in ipairs(palettes) do
  --    print(palettes)
  --    palettes[i] = conversions.packPalette(palette)
  --  end
  --end

  --for iPal, palette in ipairs(palettes) do
  --  for iCol, color in ipairs(palette) do
  --    print(iCol, color)
  --  end
  --end
  
  local hook = hookmod.Hook:new(name, library.slots[slotName], player, base64.decode(trigger), palettes, extras)

  library:addHook(hook)

  return {status="success"}
end

function ramanimator.getTiles(args)
  -- width and height are in units of tiles, not pixels!
  -- At this point, this is merely a debugging function.
  local address = args["address"]
  local width = args["width"] -- In tiles
  local height = args["height"]
  local layout = args["layout"]

  local ramdata = emu:readRange(address, slotmod.getTileSize()*width*height)
  local pixels = conversions.vram2frame(ramdata, width, height, layout)
  local trigger = base64.encode(ramdata)

  -- In this case, we can't read the color since we don't know which
  -- palette we are looking for.
  return {status="success", width=8*width, height=8*height,
    pixels=base64.encode(pixels), address=address, layout=layout,
    trigger=trigger}
end

function ramanimator.writeTiles(args)
  -- width and height are in units of tiles, not pixels!
  -- This is merely a debugging function.
  local address = args["address"]
  local width = args["width"] -- In tiles
  local height = args["height"]
  local layout = args["layout"]
  local pixels = base64.decode(args["pixels"])

  local ramdata = conversions.frame2vram(pixels, width, height, layout)

  -- A quick temporary slot
  local slot = slotmod.TileSlot:new("tmp", address, width, height, layout, 0)
  slot:write(ramdata)

  return {status="success"}
end

function ramanimator.getSlots(args)
  if not library then
    return {status="No library loaded."}
  end

  local slots = {}

  for _, slot in pairs(library.slots) do
    -- Skip hidden unless hidden is overridden or that slot is explicitly
    -- requested.
    if slot.order ~= -1 or (args ~= nil and args.listHidden) or (args.slots and general.tblContains(args.slots, slot.name)) then
      slots[slot.name] = {order=slot.order, dependent=slot.parent ~= nil, kind=slot.kind, updatable=slot.extras and slot.extras.updatable}
    end
  end

  return {status="success", slots=slots}
end

function ramanimator.getHookOverview(args)
  -- Return the slots and the names of the hooks for a menu where the
  -- user can select one filtered by their slots.
  if not library then
    return {status="No library is loaded."}
  end

  local hookNames = {}

  for _, hook in pairs(library.hooks) do
    if args.slots == nil or general.tblContains(args.slots, hook.slot.name) then
      -- For updating palettes: Count the non-synthetic palettes on the hook
      local paletteInds = {}
      if hook.palettes then
        for index, pal in ipairs(hook.palettes) do
          if not pal.synthetic then
            table.insert(paletteInds, index)
          end
        end
      end

      table.insert(hookNames, {name=hook.name, slot=hook.slot.name, paletteIndices=paletteInds})
    end
  end

  local slots = ramanimator.getSlots({slots=args.slots}).slots

  return {status="success", slots=slots, hooks=hookNames}
end

function ramanimator.getAnimOverview(args)
  -- Return the slots and the names of the animations.
  if not library then
    return {status="No library is loaded."}
  end

  local anims = {}

  for _, slot in pairs(library.slots) do
    if slot.parent == nil then
      local slotAnims = {}
      for _, anim in pairs(slot.animations) do
        table.insert(slotAnims, anim.name)
      end
      anims[slot.name] = slotAnims
    end
  end

  local slots = ramanimator.getSlots({slots=args.slots}).slots

  return {status="success", slots=slots, animations=anims}
end

function ramanimator.getHook(args)
  -- Return the info attached to the hook of that name.
  -- Arguments:
  -- includeSyntheticPalettes -> Returns all palettes, even procedurally
  -- generated ones.
  if not library then
    return {status="No library is loaded."}
  end

  local hookName = args.name
  if not hookName then
    return {status="No hook name provided."}
  end

  local hook = nil

  for _, hookCan in pairs(library.hooks) do
    if hookName == hookCan.name then
      hook = hookCan
      break
    end
  end

  if not hook then
    return {status="Did not find a hook of name: " .. tostring(args.name)}
  end

  local slot = hook.slot

  if slot.kind ~= "tile" and slot.kind ~= "sprite" then
    return {status="The requested hook does not belong to a TileSlot or SpriteSlot."}
  end

  local pixels = conversions.vram2frame(hook.trigger, slot.width, slot.height, slot.layout)
  pixels = base64.encode(pixels)

  local palettes = nil

  if hook.palettes then
    palettes = {}
    for _, pal in ipairs(hook.palettes) do
      -- If the palette is added by the slot
      local palette = {}
      if not pal.synthetic or args.includeSyntheticPalettes then
        for _, color in ipairs(pal) do
          palette[#palette + 1] = color
        end
        table.insert(palettes, conversions.unpackPalette(palette))
      end
    end
  end

  local playerClass = hook.playerClass
  if playerClass ~= nil and type(playerClass) ~= "string" then
    playerClass = playerClass.handle
  end

  -- Some extras need to be changed to make them serializable
  local extras = hook.extras

  if extras ~= nil then
    local extraOverrides = {}

    for name, val in pairs(extras) do
      if name == "twinTriggers" then
        local newList = {}
        for _, trigger in ipairs(val) do
          table.insert(newList, base64.encode(trigger))
        end
        extraOverrides[name] = newList
      end
    end

    for k, v in pairs(extraOverrides) do
      extras[k] = v
    end
  end

  local platform = "gb"

  if emu:platform() == C.PLATFORM.GBA then
    platform = "gba"
  end

  return {status="success", name=hook.name, width=8*slot.width, 
    height=8*slot.height, pixels=pixels, trigger=base64.encode(hook.trigger),
    hookName=hook.name, slotName=slot.name,
    palettes=palettes, playerClass=playerClass,
    extras=extras, platform=platform,
  }
end

function ramanimator.updateHook(args)
  --[[
  Given the name of a hook, set what is currently in that hook's slot as
  the new trigger.
  --]]
  if library == nil then
    return {status="No library loaded"}
  end

  local name = args.name
  if name == nil then
    return {status="Argument 'name' missing"}
  end

  local hook = library.hooks[name]
  if hook == nil then
    return {status="No hook of that name found", name=name}
  end

  local slot = hook.slot
  local slotGroup = library.slotGroups[slot.groupKey]

  if slotGroup == nil then
    if slot.kind == "sprite" then
      local cnt = general.countTbl(slot.spriteTbl)
      if cnt > 1 then
        return {status="Currently, this hook's slot has several active sprites. Wait a few seconds or change to a different scene to try again."}
      elseif cnt == 0 then
        return {status="No sprite of that slot found on screen."}
      else
        -- Get the unique TileSlot
        for k, v in pairs(slot.spriteTbl) do
          slot = v.slot
        end
        slotGroup = library.slotGroups[slot.groupKey]
      end
    else
      return {status="That hook's slot does not work here. You cannot update that hook in this way."}
    end
  end

  -- Keep a copy in case we need to fix the layout.
  local origSlot = hook.slot
  local origHook = hook

  -- Escalate up to the hook that is manually defined, not a sibling
  while hook.extras and hook.extras.isSibling do
    hook = library.hooks[hook.extras.firstBorn]
    slot = hook.slot
  end

  local updateSiblings = hook.siblings ~= nil
  local oldTrigger = hook.trigger
  local anim = slot.animations[oldTrigger]

  if not args.paletteOnly then
    hook.trigger = slot:read()

    if origSlot.layout ~= slot.layout or origHook.extras.mirrored then
      local rawTrigger = conversions.vram2frame(hook.trigger, origSlot.width, origSlot.height, origSlot.layout)
      if origHook.extras.mirrored then
        rawTrigger = conversions.mirrorFrame(rawTrigger, slot.width, slot.height)
      end
      hook.trigger = conversions.frame2vram(rawTrigger, slot.width, slot.height, slot.layout)
    end

    slot.animations[hook.trigger] = anim
    slot.animations[oldTrigger] = nil
  end

  hook.updated = true

  -- Make it check the hooks again
  slotGroup.cachedRam = nil

  -- Update the first or selected palette
  if origSlot.subSlots.palette ~= nil then
    local palette = nil
    local paletteIndex = args.paletteIndex or 1
    if emu:platform() == C.PLATFORM.GB and emu.readPalette then
      palette = slotmod.newPaletteSlot(origSlot.subSlots.palette.index):readColors()
    elseif emu:platform() == C.PLATFORM.GBA then
      palette = slotmod.newPaletteSlot(origSlot.subSlots.palette.index, nil, {address=0x5000000}):readColors()
    end

    hook.palettes[paletteIndex] = palette

    -- Since we are going to regenerate the hook, we need to remove all
    -- of its synthetic palettes.
    local nPals = #hook.palettes
    for i = 1, nPals do
      if hook.palettes[i] and hook.palettes[i].synthetic then
        hook.palettes[i] = nil
      end
    end
  end

  local sibAnims = {}
  if updateSiblings then
    -- Unwire the old animations
    for _, sibDef in pairs(hook.siblings) do
      local sibSlot = library.slots[sibDef.slot]
      local hookName = sibDef.hook
      local sibHook = library.hooks[hookName]

      -- This part is obsolete now, I think.
      --sibAnims[hookName] = sibSlot.animations[sibHook.trigger]
      ---- Update the animation's reference to its hook
      --sibAnims[hookName].hook = library.hooks[hookName]
      sibSlot.animations[sibHook.trigger] = nil
    end
  end

  -- Regenerate hook, its synthetic palettes and potential siblings.
  library:addHook(hook)
  -- These need to get updated so their hook references are correct.
  library:addAnimation(anim)

  return {status="success"}
end

function ramanimator.unloadAnimations(args)
  --[[
  When we want to export new animations, we can first clear the library so
  that the export will be clean.
  --]]

  if library == nil then
    return {status="No library loaded"}
  end

  -- Remove all animations from their slots
  for name, slot in pairs(library.slots) do
    slot.animations = {}
  end

  -- Stop all running player
  for key, group in pairs(library.slotGroups) do
    group.player = nil
  end

  return {status="success"}
end

function ramanimator.getLibrary(args)
  --[[
  Send the information that is necessary to construct the library so
  that it can be serialized to a file. This is the mechanism to export the
  data so that an external Python program can write it to a file so that
  it can in turn be read by ramanimator without having to send over every
  custom animation from Aseprite every time.

  For animations and hooks, this only sends the names for individual
  retrieval by getAnimation and getHook because otherwise libraries can
  become too big.
  --]]
  local animations = {}
  local hooks = {}
  local slots = {}

  local filterUpdated = args and args.filterUpdated == true

  if library == nil then
    return {status="No library loaded"}
  end

  for name, slot in pairs(library.slots) do
    -- Filter out dependent and undesired slots
    if slot.parent ~= nil and args and args.slots and not general.tblContains(args.slots, slot.name) then
      -- Skip it
    else
      slots[name]=slot.serialized

      for trigger, anim in pairs(slot.animations) do
        if not (filterUpdated and not anim.updated) then
          table.insert(animations, {name=anim.name, updated=anim.updated, isSibling=anim.hook.extras and anim.hook.extras.isSibling})
        end
      end
    end
  end

  for name, hook in pairs(library.hooks) do
    local slot = hook.slot
    if args and args.slots and not general.tblContains(args.slots, slot.name) then
      -- Skip it
    elseif not (filterUpdated and not hook.updated) then
      table.insert(hooks, {name=name, isSibling=hook.extras and hook.extras.isSibling, updated=hook.updated})
    end
  end

  return {status="success", name=library.name, slots=slots, hooks=hooks, animations=animations, extras=library.extras}
end

function ramanimator.getAnimation(args)
  --[[
  Send all the information that was necessary to construct the library so
  that it can be serialized to a file. This is the mechanism to export the
  data so that an external Python program can write it to a file so that
  it can in turn be read by ramanimator without having to send over every
  custom animation from Aseprite every time.

  Note this returns the data in native formats, so not directly readable.
  --]]
  local name = args.name

  if name == nil then
      return {status="Argument name missing"}
  end

  local animation = nil

  for _, slot in pairs(library.slots) do
    for trigger, anim in pairs(slot.animations) do
      if anim.name == name then
        local frames = {}
        for i, frame in ipairs(anim.frames) do
          table.insert(frames, base64.encode(frame))
        end

        animation = {
          strips=anim.strips,
          frames=frames,
          palettes=anim.palettes,
        }
        break
      end
    end

    if animation ~= nil then
      break
    end
  end

  if animation == nil then
    return {status="No animation of that name found", name=name}
  end

  return {status="success", name=name, animation=animation}
end

function ramanimator.getRunningAnimation(args)
  if library == nil then
    return {status="No library loaded."}
  end

  local slotName = args.slotName

  if slotName == nil then
    return {status="Argument slotName missing."}
  end

  local slot = library.slots[slotName]

  if slot == nil then
    return {status="No slot found for that name."}
  end

  local slotGroup = library.slotGroups[slot.groupKey]

  if slotGroup == nil then
    return {status="No slot group registered for that slot."}
  end

  local player = slotGroup.player

  if player == nil then
    return {status="No animation playing in that slot."}
  end

  local anim = player.anim

  -- All that I need for now.
  return {status="success", name=anim.name}
end

function ramanimator.setConfig(args)
  -- Set args.name to args.value in raconfig.extras
  if args.name == nil then
    return {status="No config name provided!"}
  end

  -- The value might intentionally be nil
  raconfig.extras[args.name] = args.value

  return {status="success"}
end

local function ramanimatorCommands(command, args)
  if command == "getRAManimatorVersion" then
    return {status="success", version=raconfig.version}

  elseif command == "registerAnimation" then
    return ramanimator.registerAnimation(args)

  elseif command == "registerSlot" then
    return ramanimator.registerSlot(args)

  elseif command == "registerHook" then
    return ramanimator.registerHook(args)

  elseif command == "getTiles" then
    return ramanimator.getTiles(args)

  elseif command == "writeTiles" then
    return ramanimator.writeTiles(args)

  elseif command == "getSlots" then
    return ramanimator.getSlots(args)

  elseif command == "loadSlot" then
    return ramanimator.loadSlot(args)
    
  elseif command == "getHookOverview" then
    return ramanimator.getHookOverview(args)

  elseif command == "getAnimOverview" then
    return ramanimator.getAnimOverview(args)

  elseif command == "getHook" then
    return ramanimator.getHook(args)

  elseif command == "updateHook" then
    return ramanimator.updateHook(args)

  elseif command == "unloadAnimations" then
    return ramanimator.unloadAnimations(args)

  elseif command == "getLibrary" then
    return ramanimator.getLibrary(args)

  elseif command == "getAnimation" then
    return ramanimator.getAnimation(args)

  elseif command == "playAnimation" then
    return ramanimator.playAnimationCmd(args)

  elseif command == "getRunningAnimation" then
    return ramanimator.getRunningAnimation(args)

  elseif command == "getPlayers" then
    return ramanimator.getPlayers(args)

  elseif command == "setConfig" then
    return ramanimator.setConfig(args)
  end
end

callbacks:add("frame", ramanimator.animate)
server.registerCommandCallback(ramanimatorCommands)

-- When a ROM is loaded, load its animations etc.
-- We don't do this as a callback because it uses a different module
-- search path than when called on startup and we delay loading animations
-- to reduce startup time.
callbacks:add("start", remindReload)
if emu then
	detectGame()
else
  console:error("You need to re-run the script once a game is loaded so that its graphics can be found.")
end

ramanimator.getLibrary()

return ramanimator
