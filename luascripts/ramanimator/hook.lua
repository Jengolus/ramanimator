
--[[
A hook is what needs to be found in a slot so that an animation is placed
there instead. Since the game can edit the memory itself (e.g. doing its
own animations), the hook also needs to anticipate what might be placed in
the memory and check whether its own animation should be stopped or
overwrite what it found.
--]]

local hookmod = {}
local playermod = require("ramanimator/player")
local slotmod = require("ramanimator/slot")

local base64 = require("base64")

local Hook = {}
Hook.__index = Hook

function Hook:new(name, slot, playerClass, trigger, palettes, extras)
  --[[
  trigger must be a string, which is why slot:read always returns a string.
  triggerMask is a string containing bytes 0 and 255. The length is the
  same as trigger, and bytes marked as 0 will be ignored when checking
  whether the memory matches the trigger.

  tileOptions acts similarly, but provides a list of options that may be
  observed for each tile, useful e.g. for Crystal's battle animations.
  While tileOptions as a name mostly makes sense for VRAM hooks, the
  concept also works for other memory domains.

  The palettes are mostly a list of their BGR values, but may also contain
  the "synthetic" attribute if they stem from a subSlot's variantsSource.

  Some particular extras:
  isSibling: Set on procedurally generated siblings
  twinTrigger: A trigger that can activate twins and can continue the main
    slot, but not start the animation itself.
  --]]
  local obj = setmetatable({}, Hook)

  obj.name = name
  obj.slot = slot
  obj.slotName = slotName
  obj.playerClass = playerClass
  obj.player = playerClass
  obj.trigger = trigger
  obj.extras = extras
  -- This is set if the hook gets updated programmatically
  obj.updated = false

  -- If the slot has a source for palette variants, call it
  if palettes ~= nil and (slot.subSlots.palette ~= nil and slot.subSlots.palette.variantsSource ~= nil) then
    local myPalettes = {}
    local nPal = #palettes
    for iPal = 1, nPal do
      myPalettes[iPal] = palettes[iPal]

      local newPals = slot.subSlots.palette.variantsSource(palettes[iPal])

      for iPalInner, newPal in ipairs(newPals) do
        newPal.synthetic = true
        myPalettes[nPal + #newPals * (iPal-1) + iPalInner] = newPal
      end
    end

    palettes = myPalettes
  end

  obj.palettes = palettes

  if slot.twins and slot.twinDefaultOn ~= false then
    obj.hasTwin = true
  end

  if extras then
    obj.triggerMask = extras.triggerMask
    obj.tileOptions = extras.tileOptions
    obj.siblings = extras.siblings

    if extras.hasTwin ~= nil then
      obj.hasTwin = extras.hasTwin
    end

    -- Twins may use different triggers, but currently always accept the
    -- normal trigger, too.
    obj.twinTriggers = extras.twinTriggers
  end

  if not obj.triggerMask and slot.extras and slot.extras.requireTriggermask then
    obj.triggerMask = slot:createTriggerMask(obj)
  end

  return obj
end

function Hook:checkRunning(slot, mem, frame)
  --[[
  mem: What is currently in RAM
  frame: What the slot last wrote to RAM.

  Return values
  0 - No match
  1 - Exact match
  2 - Anticipated change and rewrite frame
  --]]
  if type(frame) == "table" then
    -- E.g. for palettes
    frame = slot:tbl2trigger(frame)
  end

  if #frame > #mem then
    error("Trying to check whether an animation is still running, but the provided memory segment is too short! " .. #mem .. " < " .. #frame)
  end

  -- If several slots share one offset, #mem corresponds to the longest
  -- slot.
  if #frame < #mem then
    mem = string.sub(mem, 1, #frame)
  end

  --print("checking", self.name)

  --print(base64.encode(mem))
  --print(base64.encode(frame))

  if mem == frame then
    return 1, "identical"
  end

  -- Note that the twinTriggers are only considered when they override the
  -- actual trigger, not to start the animation.
  if self.twinTriggers ~= nil then
    for id, trigger in pairs(self.twinTriggers) do
      if mem == trigger then
        return 2, "identical to twinTrigger " .. id
      end
    end
  end

  if self.triggerMask then
    -- Only compare bytes that are included in the mask, i.e. ignore some
    -- parts of the data.
    local triggerMask = self.triggerMask
    for i = 1, #triggerMask do
      -- Since Lua 5.3, we could use & to check bitwise, but this is Lua
      -- 5.1 compatible.
      local mask = triggerMask:byte(i)
      -- if mask & mem:byte(i) ~= mask & animPlayer.frame:byte(i) then
      if mask ~= 0 and mem:byte(i) ~= frame:byte(i) then
        --console:log("Mask check for " .. self.name .. " failed at byte " .. tostring(i))
        --if self.active then
        --  print("triggerMask", base64.encode(triggerMask))
        --end
        return 0, "Mask check for " .. self.name .. " failed at byte " .. i
      end
    end
  else
    if self.tileOptions == nil then
      -- No second chance
      return 0, "Expected: " .. tostring(frame) .. "\nGot: " .. tostring(mem)
    end
  end

  if self.tileOptions ~= nil then
    -- If the game animates by swapping out tiles individually, the
    -- animations get messed up because it puts tiles into the animation's
    -- frames. So we need to check whether any discrepancies are due to
    -- tiles we expect to appear or because it is (slowly) loading a new
    -- graphic. Note that this still isn't perfect, but works in practice.
    local tileSize = slotmod.getTileSize()
    for iTile, options in pairs(self.tileOptions) do
      -- When combined with a triggerMask, nil options mean the mask
      -- would have caught it.
      if options ~= nil then
        local observed = string.sub(mem, tileSize * (iTile - 1) + 1, tileSize * iTile)
        -- Check whether we expect this tile
        local match = false
        for iOpt, opt in ipairs(options) do
          --print(#observed, #opt, base64.encode(observed), base64.encode(opt), base64.encode(observed) == base64.encode(opt), opt == observed)
          if opt == observed then
            match = true
            break
          end
        end

        if not match then
          return 0, "Unexpected tile at index " .. iTile
        end
      end
    end
  end

  -- The memory was edited, but we override it.
  return 2, "Not identical, but alright"
end

function Hook:newPlayer(anim, slot)
  -- Start a new player for the provided animation on this hook.
  local class = self.playerClass

  if not class then
    --print("Hook did not find a player class")
    class = playermod.AnimPlayer
  end

  return class:new(anim, slot)
end

hookmod.Hook = Hook

return hookmod
