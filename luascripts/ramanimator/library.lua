
--[[
A library is a collection of slots, hooks and animations.

What's open:
- Palettes
- How are the animations stored within the library if I don't always know
  their offsets beforehand? Maybe slots get a table of their hooks, too?
- Rewrite it to accept tables of animation tables as arguments for my
  convenience. These overwrite each other in order of appearance.
  Or rather: Make anims a vararg?
--]]

local librarymod = {}

local base64 = require("base64")
local raconfig = require("ramanimator/raconfig")
local general = require("general")
local dbg = require("debugging")
local hookmod = require("ramanimator/hook")
local slotmod = require("ramanimator/slot")
local playermod = require("ramanimator/player")
local conversions = require("ramanimator/conversions")

function librarymod.transferRunningPlayers(oldLib, newLib, ignoreActive)
  --[[
  When a running animation is replaced, the new animation should
  automatically start because the trigger is most likely overwritten.

  ignoreActive: For most applications, one should only transfer running
  players. When we are already at the subanimation level, it it sometimes
  necessary to override that.
  --]]
  if not oldLib or not newLib then
    return
  end

  if ignoreActive == nil then ignoreActive = false end

  --oldLib.out:print(emu:currentFrame(), "Attempting transfer between", oldLib.name, "and", newLib.name)

  for groupKey, group in pairs(newLib.slotGroups) do
    local oldGroup = oldLib.slotGroups[groupKey]

    if oldGroup and oldGroup.player and (ignoreActive or oldGroup.player.active) then
      -- Do we have an equivalent animation?
      local oldAnim = oldGroup.player.anim

      for _, slot in pairs(newLib.slots) do
        local equAnim = slot.animations[oldAnim.hook.trigger]

        if equAnim then
          oldLib.out:print("Transferred animation " .. oldAnim.name)
          oldLib.out:print("to library", newLib.name .. ", info:", oldGroup.player.active, ignoreActive)
          group.player = equAnim.hook:newPlayer(equAnim, slot)
          group.player:advanceFrame()
          local frame = group.player.currentFrame

          librarymod.transferRunningPlayers(oldAnim.subLibrary, equAnim.subLibrary)
        end
      end
    end
  end
end

local Library = {}

Library.__index = Library

function Library:new(name, slots, hooks, extras, ...)
  --[[
  name: For user convenience and display
  slots, hooks: Tables of corresponding objects, everything indexed by their
    names.
  extras: JSON seralizable extras
  ...: Vararg of tables that contain animations.
  --]]
  local anims = {...}

  local obj = setmetatable({}, Library)
  obj.name = name
  if not extras then extras = {} end
  obj.extras = extras

  obj.out = dbg.getBuffer(name, raconfig.logLevel)

  -- Do we have everything we need for palettes? Otherwise, the warnings
  -- are delayed until we actually find a palette animation.
  if emu:platform() == C.PLATFORM.GB then
    if emu.writePalette and emu.readPalette then
      obj.paletteAddresses = {-1}
    end
  elseif emu:platform() == C.PLATFORM.GBA then
    if not obj.extras.gbaPaletteAddresses then
      obj.paletteAddresses = {0x5000000}
    else
      obj.paletteAddresses = obj.extras.gbaPaletteAddresses
    end
  end


  -- An empty table is fine because that is what we have for a new game.
  if slots == nil then
    slots = {}
  end

  obj.slots = {}

  -- Regroup animations by their address; if several slots refer to the
  -- same address, this groups them.
  obj.slotGroups = {}

  for internalName, slot in pairs(slots) do
    obj:addSlot(slot)
    slot.serialized.extras.internalName = internalName
  end

  if hooks == nil then
    hooks = {}
  end

  obj.hooks = {}

  for name, hook in pairs(hooks) do
    obj:addHook(hook)
  end

  -- Keep the files in order
  for _, animList in ipairs(anims) do
    for name, anim in pairs(animList) do
      --print(name, anim)
      anim.name = name
      obj:addAnimation(anim)
    end
  end

  return obj
end

function Library:clearCache()
  --[[
  To be called on an animation's sublibrary when it is stopped (but not
  halted). Deletes all players so the subanimations start fresh.
  --]]
  for _, group in pairs(self.slotGroups) do
    if group.player ~= nil then
      group.player.active = false
      local subAnim = group.player.anim
      if subAnim.subLibrary ~= nil then
        subAnim.subLibrary:clearCache()
      end
    end

    group.player = nil
  end
end

function Library:addSlot(slot)
  if slot.name == nil then
    console:error("Trying to add a slot without a name!")
    return
  end

  if self.slots[slot.name] then
    self.out:print("Overwriting existant slot of name " .. slot.name .. "!")
    self:removeSlot(self.slots[slot.name])
  end

  slot.animations = {}

  self.slots[slot.name] = slot

  if slot.kind == "sprite" then
    return
  end

  local group = self.slotGroups[slot.groupKey]

  if group == nil then
    -- This is the definition of a SlotGroup
    group = {
      slots = {slot},
      maxLength = slot.length,
      cachedRam = nil,
      player = nil,
      refSlot = slot, -- Always the longest slot.
    }

    self.slotGroups[slot.groupKey] = group
  else
    table.insert(group.slots, slot)
    local longest = group.maxLength < slot.length
    if longest then
      group.maxLength = math.max(group.maxLength, slot.length)
      group.refSlot = slot
    end
  end
end

function Library:removeSlot(slot)
  --[[
  SpriteSlots can add temporary slots, so they also need to be able to
  remove them once their Sprite is discarded.
  --]]
  if not slot.name then
    console:error("Trying to remove a slot without a name")
    return
  end

  self.out:print("Removed slot", slot.name)

  if not self.slots[slot.name] then
    console:error("Trying to remove slot " .. slot.name .. ", but cannot find it in library " .. self.name)
    return
  end

  self.slots[slot.name] = nil

  local group = self.slotGroups[slot.groupKey]

  if not group and slot.kind ~= "sprite" then
    console:error("Trying to remove non-sprite slot " .. slot.name .. " from library " .. self.name .. ", but it does not have an associated group!")
    return
  end

  -- Remove the slot from its group; delete the group if that empties it.
  if #group.slots == 1 then
    -- This group is obsolete
    self.slotGroups[slot.groupKey] = nil
  else
    -- Remove and update the group if necessary.
    general.tblRemoveElement(group.slots, slot)

    group.cachedRam = nil -- Be safe
    if group.player and group.player.anim.slot == slot then
      group.player = nil
    end

    if group.refSlot == slot then
      local longest = 0
      for _, slot in ipairs(group.slots) do
        group.maxLength = math.max(group.maxLength, slot.length)
        if slot.length >= group.maxLength then
          group.refSlot = slot
        end
      end
    end
  end
end

function Library:addHook(hook)
  self.hooks[hook.name] = hook

  -- If it has siblings, add those, too
  if hook.siblings then
    local slot = hook.slot
    local rawTrigger = nil

    for _, sibDef in pairs(hook.siblings) do
      if not sibDef.manual and self.slots[sibDef.slot] then
        local sibSlot = self.slots[sibDef.slot]
        local newTrigger = hook.trigger

        if sibDef.mirror or sibSlot.layout ~= slot.layout then
          if not rawTrigger then
            rawTrigger = conversions.vram2frame(hook.trigger, slot.width, slot.height, slot.layout)
            newTrigger = rawTrigger
          end

          if sibDef.mirror then
            newTrigger = conversions.mirrorFrame(newTrigger, slot.width, slot.height)
          end
          newTrigger = conversions.frame2vram(newTrigger, sibSlot.width, sibSlot.height, sibSlot.layout)
        end

        -- Problem: Converting tileOptions is work.
        local sibTileOptions = nil
        if hook.tileOptions then
          if slot.layout == sibSlot.layout and not sibDef.mirror then
            sibTileOptions = hook.tileOptions
          else
            console:error("Hook " .. hook.name .. " has tileOptions, but the layout differences between it and its sibling are not implemented for them. Your easiest solution is to do the conversion manually and write the sibling hooks directly to your Lua module; automatic conversion of animations will still work.")
          end
        end

        -- The first hook that spawns the siblings
        local firstBorn = self.extras.firstBorn or hook.name

        self:addHook(hookmod.Hook:new(sibDef.hook, sibSlot, hook.playerClass, newTrigger, hook.palettes, {isSibling=true, twinTriggers=hook.twinTriggers, hasTwin=hook.hasTwin, tileOptions=sibTileOptions, firstBorn=firstBorn, mirrored=sibDef.mirror}))
      end
    end
  end
end

function Library:addAnimation(anim)
  --[[
  Add an animation to this library. The animation is passed in the
  serialized form, i.e. we still need to construct the subslots, link it
  to the hook etc.
  --]]

  if anim == nil then
    console:error("Trying to add a nil animation to " .. tostring(self.name))
    return
  end

  local hook = self.hooks[anim.name]

  if hook == nil then
    -- This can happen with general animation libraries.
    if raconfig.logLevel > 1 then
      self.out:print("Found animation " .. tostring(anim.name) .. " without a corresponding hook!")
    end
    return
  end

  anim.hook = hook

  -- Some validation
  for iStrip, strip in ipairs(anim.strips) do
    if not strip.tag then
      console:error("Animation " .. anim.name .. " contains strip " .. iStrip .. " without a tag!")
    end

    for iInd, index in ipairs(strip.frameIndices) do
      if index < 1 or index > #anim.frames then
        console:error("Animation " .. anim.name .. ", strip " .. tostring(strip.tag) .. " contains an invalid frame index " .. index .. ". Remember they need to be 1-indexed.")
      end
    end
  end

  -- Check whether the animation is new
  local slot = hook.slot

  if slot.kind == "sprite" then
    -- Reset the cached RAM for all active slots of this sprite slot so
    -- the new animation can start automatically.
    for _, sprite in pairs(slot.spriteTbl) do
      local slotGroup = self.slotGroups[sprite.slot.groupKey]
      if slotGroup then
        slotGroup.cachedRam = nil
      end
    end
  else
    -- Make it refresh.
    local slotGroup = self.slotGroups[slot.groupKey]
    if slotGroup then
      slotGroup.cachedRam = nil
    end
  end

  -- Add an animation for the palette, which depends on the hardware
  if slot.subSlots then
    local subSlots = {}
    local subHooks = {}
    local subAnims = {}

    local pal = slot.subSlots.palette
    if pal and anim.palettes then
      -- The slot wants to manipulate a palette, but can we do that?
      if not self.paletteAddresses then
        raconfig.warnPalette()
      end

      local palettes = {}
      local nPal = #anim.palettes

      for iPal = 1, nPal do
        palettes[iPal] = anim.palettes[iPal]

        if slot.subSlots.palette.variantsSource ~= nil then
          local newPals = slot.subSlots.palette.variantsSource(anim.palettes[iPal])
          for iPalInner, newPal in ipairs(newPals) do
            newPal.synthetic = true
            palettes[nPal + #newPals * (iPal-1) + iPalInner] = newPal
          end
        end
      end

      if self.paletteAddresses and hook.palettes and (#palettes > 0) then
        for iAddr, address in ipairs(self.paletteAddresses) do
          -- Filter out the GB case, which only allows one PaletteSlot
          if address == -1 then address = nil end
          local paletteSlot = slotmod.newPaletteSlot(pal.index, slot, {writable=pal.writable, address=address, variantsSource=pal.variantsSource})

          table.insert(subSlots, paletteSlot)

          for i = 1, math.min(#hook.palettes, #palettes) do
            local subName = hook.name .."_palette" .. i
            if address then
              subName = subName .. "_" .. string.format("%x", address)
            end

            subHooks[subName] = hookmod.Hook:new(subName, paletteSlot, pal.playerClass, paletteSlot:tbl2trigger(hook.palettes[i]))

            subAnims[subName] = {
              frames={palettes[i]},
              strips={{tag="idle", frameIndices={1}, timings={30}}},
            }
          end
        end
      end
    end
    
    -- I think it is never actually referenced as a subSlot.
    --if slot.twins ~= nil and hook.hasTwin then
    --  for iTwin, twin in ipairs(slot.twins) do
    --    table.insert(subSlots, twin)
    --  end
    --end

    -- This only works if subSlots are added via table.insert!
    if #subSlots > 0 then
      anim.subLibrary = Library:new(hook.name .. "_sublib", subSlots, subHooks, nil, subAnims)
    end
  end

  -- Actually add it to the slot's list.
  slot:addAnimation(hook, anim)

  local function checkRunningInSlotGroup(slot, slotGroup)
      if slotGroup == nil then
        return
      end

    -- Is this animation currently running? If so, restart it
    -- automatically because the trigger is nigh certainly overwritten.
    local player = slotGroup and slotGroup.player
    if player and player.active then
      local oldAnim = player.anim

      if oldAnim.hook.trigger == hook.trigger then
        slotGroup.player = anim.hook:newPlayer(anim, slot)
        slotGroup.player:advanceFrame()

        -- If so, also try to transfer the sublibrary's animations.
        librarymod.transferRunningPlayers(oldAnim.subLibrary, anim.subLibrary)
      end
    end
  end

  if slot.kind == "sprite" then
    -- Reset the cached RAM for all active slots of this sprite slot so
    -- the new animation can start automatically.
    for _, sprite in pairs(slot.spriteTbl) do
      local slotGroup = self.slotGroups[sprite.slot.groupKey]
      checkRunningInSlotGroup(sprite.slot, slotGroup)
    end
  else
    checkRunningInSlotGroup(slot, self.slotGroups[slot.groupKey])
  end

  -- Printing this for everything takes way to long when loading large
  -- libraries.
  --self.out:print("Added animation", anim.name, "to slot", slot.name, "with", slot.subSlots and #slot.subSlots or "0", "subslots")

  -- If the sprite can appear in an altered form in a different slot,
  -- automatically generate copies of all frames.
  local siblings = hook.siblings
  if siblings then
    -- Convert all frames to a raw index list.
    local rawFrames = nil

    for _, sibling in ipairs(siblings) do
      local sib = self.hooks[sibling.hook]

      if not sib then
        console:error("Trying to add animation " .. anim.name .. " to its sibling " .. tostring(sibling.hook) .. ", but cannot find the sibling!")
      else
        -- Find the sibling's slot
        local sibSlot = sib.slot

        local newAnim = {}
        -- This also copies the table of frames, so don't change that if
        -- it isn't necessary.
        for k, v in pairs(anim) do
          newAnim[k] = v
        end

        newAnim.name = sibling.hook

        -- E.g. to convert a Front animation in GB Pokémon games to their
        -- mirrored equivalents automatically.
        if sibling.mirror or sibSlot.layout ~= slot.layout then
          -- We need to convert the frames to their pixels, then convert
          -- them to the new layout.
          if not rawFrames then
            rawFrames = {}
            for iFrame, frame in ipairs(anim.frames) do
              rawFrames[iFrame] = conversions.vram2frame(frame, slot.width, slot.height, slot.layout)
            end
          end

          local newFrames = {}
          for iFrame, frame in ipairs(rawFrames) do
            if sibling.mirror then
              frame = conversions.mirrorFrame(frame, slot.width, slot.height)
            end

            newFrames[iFrame] = conversions.frame2vram(frame, sibSlot.width, sibSlot.height, sibSlot.layout)
          end

          newAnim.frames = newFrames
        end


        self:addAnimation(newAnim)
      end
    end
  end
end

librarymod.Library = Library

return librarymod
