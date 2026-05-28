
--[[
A slot is a place in memory that data can be read from and written to.
There are several supported kinds:
- Slot: The game always stores the data in this spot, so the slot
  is just the address and a length.
  - The variant TileSlot: Specifically for tiles in VRAM, it contains some
    metadata so that an image to be sent to it can be converted to its
    memory equivalent.
- Out-of-RAM palettes: On SGB and CGB, the colors aren't stored within the
  regular address space, so they need special slots to access them.
- Sprite slots: On GBA, sprites are allocated dynamically, so a constant
  address wouldn't work. Thus, these slots identify the actual address
  by looking through loaded sprites.
  How do I associate them to their palette slot dynamically?

Maybe I will make GBA games generate the TileSlots dynamically, then it
fits in rather well. I'll just need to manager their removal. I think that
sounds like a good idea.

It might not be desirable to distinguish front and back slots on GBA since
they can reuse offsets among each other.
--]]

local slots = {}

local base64 = require("base64")

local dbg = require("debugging")
local general = require("general")
local conversions = require("ramanimator/conversions")
local raconfig = require("ramanimator/raconfig")

local spriteSlotOamData = {}
local spriteSlotOamFrame = 0

-- Base class: Slot. For writing data to RAM as-is.
local Slot = {}
Slot.__index = Slot

-- Legacy, these should just be replaced
slots.tbl2str = general.tbl2str
slots.getTileSize = general.getTileSize
slots.getTileDepth = general.getTileDepth

local function getPaletteSize()
  if emu:platform() == C.PLATFORM.GB then
    return 4
  else
    return 16
  end
end

local function getPaletteCount()
  if emu:platform() == C.PLATFORM.GB then
    return 16
  else
    return 32
  end
end

function Slot:new(name, kind, address, length, order, subSlots, extras)
  --[[
  name: For user convenience and display
  kind: string to easily distinguish subclasses.
  address: Usually an address in Memory
  length: How many bytes / entry this concerns.
  order: Optional, the order in which slots should be listed in a UI;
    if none is given, it is 1.
  subSlots: When a hook and animation are attached to a slot, their
    subanimations should populate these slots.
  --]]
  local obj = setmetatable({}, Slot)
  -- This is a copy of everything needed to generate this slot so that it
  -- can be transferred to an external program which may serialize the
  -- library.
  if extras == nil then
    extras = {}
  end

  obj.serialized = {name=name, kind=kind, address=address, length=length, order=order, subSlots=subSlots, extras=extras}

  obj.name = name
  obj.kind = kind
  obj.address = address
  obj.length = length
  obj.groupKey = address
  obj.subSlots = subSlots
  obj.extras = extras

  -- Slots derived from a SpriteSlot have this to filter them out when
  -- needed
  --obj.parent = nil

  if extras and extras.groupKey then
    obj.groupKey = extras.groupKey
  end

  -- The twin gets managed by the main slot, so it is an attribute of the
  -- slot, but also needs to be added to every animation's subSlots if it
  -- has a twin.
  -- This is skipped for SpriteSlots because in their case, the TileSlots
  -- need to manage the twins.
  if subSlots ~= nil and subSlots.twins ~= nil then
    if kind == "sprite" then
      obj.twins = {}
    else
      local twinTbl = {}

      for iTwin, twinDef in ipairs(subSlots.twins) do
        --print(anim.name, "Twin:", string.format("%x", twinDef.address))
        local twin = setmetatable({}, {__index = obj})

        twin.subSlots = {}
        twin.name = twin.name .. "_Twin" .. iTwin
        twin.isTwin = true

        if not twinDef.address then
          console:error("Found a twin without an address for animation " .. anim.name)
        else
          twin.address = twinDef.address

          table.insert(twinTbl, twin)
          --print("Slot: added twin", twin.name, "to", obj.name)
        end

        obj.twinDefaultOn = twinDef.defaultOn
      end

      obj.twins = twinTbl
    end
  end

  if order == nil then
    order = 1
  end

  obj.order = order
  return obj
end

function Slot:read()
  return emu:readRange(self.address, self.length)
end

function Slot:write(data)
  --[[
  data is a string of bytes.
  
  On GBA, mGBA doesn't allow writing single bytes to some areas, so these
  need to be treated separately..
  --]]
  if emu:platform() == C.PLATFORM.GBA then
    -- These might not be all locations where this can be necessary.
    if self.address >= 0x06000000 and self.address < 0x08000000 then
      -- Write in chunks of 16 bits
      for i = 0, #data - 1, 2 do
        local num = data:byte(i + 1) + 256 * data:byte(i + 2)
        emu:write16(self.address + i, num)
      end

      -- Was there an odd number of bytes?
      -- Should also work if only one byte is written.
      if #data % 2 == 1 then
        local byte1 = emu:read8(self.address + #data - 2)
        local num = byte1 + 256 * data:byte(#data)
        emu:write16(self.address + #data - 2, num)
      end

      return
    end
  end

  -- Or the trivial case
  for i = 1, #data do
    emu:write8(self.address + i - 1, data:byte(i))
  end
end

function Slot:createTriggerMask(hook)
  --[[
  In many cases, we can generate the trigger mask programmatically to
  automate some work.
  --]]
  return nil
end

function Slot:addAnimation(hook, anim)
  self.animations[hook.trigger] = anim
end

-- TileSlot: Contains extra metadata on how raw data needs to be encoded
-- when received via a server.
local TileSlot = {}
TileSlot.__index = TileSlot
setmetatable(TileSlot, Slot)

function TileSlot:new(name, address, width, height, layout, order, subSlots, extras)
  --[[
  width and height are in tiles, not pixels
  layout describes how individual tiles are arranged in memory.
  --]]
  local obj = Slot.new(self, name, "tile", address, width * height * slots.getTileSize(), order, subSlots, extras)
  obj.width = width
  obj.height = height
  obj.layout = layout
  setmetatable(obj, TileSlot)

  obj.serialized.width = width
  obj.serialized.height = height
  obj.serialized.layout = layout

  return obj
end

function TileSlot:resizeFrame(self, frame)
  --[[
  Take a frame in pixel form, i.e. as an array of indices not compressed
  into the native format and try to expand it to the slot's size. This
  is ill defined because we don't have the dimensions of the given frame,
  but can be useful if we want to transfer some specific frame dimensions
  without external conversion.

  Return nil if the expansion is not possible.
  --]]

  return nil
end

function TileSlot:createTriggerMask(hook)
  --[[
  This creates a mask such that trailing zeros are ignored.

  Games often load sprites tile by tile into VRAM, not within one frame.
  If the trigger ends on white space and the animation frames don't, it is
  possible the animation gets triggered and some final white tiles are
  overwritten on the frame, breaking the animation. To fix this,
  triggerMask can mark some bytes of the trigger as 0, meaning they are
  ignored in checks.

  The default triggerMask ignores all trailing zero bytes; if that is
  undesired, provide a different one via extras in the constructor of the
  hook.
  --]]
  local trigger = hook.trigger
  local nzeros = 0
  for i = 1, #trigger do
    if trigger:byte(#trigger - i + 1) == 0 then
      nzeros = nzeros + 1
    else
      break
    end
  end

  local tileSize = slots.getTileSize()
  local total = self.length
  local mask = {}

  for i = 1, total - nzeros do mask[#mask + 1] = 255 end
  for i = 1, nzeros do mask[#mask + 1] = 0 end

  -- If we have tile options, we must exlude everything affected from
  -- the mask.
  if hook.tileOptions then
    -- pairs because it is non-contiguous
    for index, options in pairs(hook.tileOptions) do
      local iStart = tileSize * (index - 1) + 1
      for iByte = iStart, iStart + tileSize - 1 do
        mask[iByte] = 0
      end
    end
  end

  return string.char(table.unpack(mask))
end

-- PaletteSlot (subclass of Slot)
local PaletteSlot = {}
PaletteSlot.__index = PaletteSlot
setmetatable(PaletteSlot, Slot)

function PaletteSlot:new(name, address, length, extras)
  --[[
  extras:
  order -> as for Slot
  subSlots -> as for Slot
  writable -> Which colors of the palette are actually writable? e.g.
    {1, 2} for the two middle colors of a GBC palette.
  --]]
  if not extras then extras = {} end

  local obj = Slot.new(self, name, "palette", address, length, extras.order, extras.subSlots)
  obj.groupKey = "palette" .. obj.groupKey
  obj.writable = extras.writable
  setmetatable(obj, PaletteSlot)

  obj.serialized.groupKey = groupKey
  obj.serialized.writable = writable

  return obj
end

function PaletteSlot:read()
  -- This needs to return a string
  return slots.tbl2str(self:readColors())
end

function PaletteSlot:readColors()
  -- To read the actual, raw table.
  if emu.readPalette == nil then
    return {}
  end

  local ret = {}

  for i = 1, self.length do
    ret[i] = emu:readPalette(self.address + i - 1)
  end

  return ret
end

function PaletteSlot:write(data)
  if emu.writePalette == nil then
    return
  end

  for i, color in ipairs(data) do
    if not self.writable or general.tblContains(self.writable, i - 1) then
      emu:writePalette(self.address + i - 1, color)
    end
  end
end

function PaletteSlot:tbl2trigger(colors)
  return slots.tbl2str(colors)
end

function PaletteSlot:createTriggerMask(hook)
  --[[
  Palette slots may be constructed to only write some of the colors in the
  palette. In that case, we need to mask the other colors from the
  trigger.
  --]]

  if not self.writable then return nil end

  local mask = ""
  local ignore = string.rep(string.char(0), 5)
  local check = string.rep(string.char(255), 5)
  local space = string.char(0)

  for i = 1, self.length do
    if general.tblContains(self.writable, i - 1) then
      mask = mask .. check
    else
      mask = mask .. ignore
    end

    if i ~= self.length then
      mask = mask .. space
    end
  end

  return mask
end

-- RamPaletteSlot (subclass of Slot, unrelated to PaletteSlot)
local RamPaletteSlot = {}
RamPaletteSlot.__index = RamPaletteSlot
setmetatable(RamPaletteSlot, Slot)

function RamPaletteSlot:new(name, address, length, extras)
  --[[
  extras:
  subSlots -> as for Slot
  writable -> Which colors of the palette are actually writable? e.g.
    {1, 2} for the two middle colors of a GBC palette.
  --]]
  if not extras then extras = {} end

  local fullName = name .. "_" .. address
  local obj = Slot.new(self, fullName, "rampalette", address, length, extras.order, extras.subSlots)
  --local obj = Slot.new(self, name .. string.format("-%s", address), "rampalette", address, length, extras.order, extras.subSlots)
  obj.groupKey = "rampalette" .. obj.groupKey
  obj.writable = extras.writable
  setmetatable(obj, RamPaletteSlot)

  obj.serialized.groupKey = groupKey
  obj.serialized.writable = writable

  --print("new RamPaletteSlot for address", string.format("%x", obj.address), "and length", obj.length)

  return obj
end

function RamPaletteSlot:readColors()
  local raw = self:read()

  local colors = {}

  for i = 1, #raw // 2 do
    colors[#colors + 1] = raw:byte(2*i - 1) + 0x100 * raw:byte(2*i)
  end

  return colors
end

function RamPaletteSlot:write(data)
  local bin = self:tbl2trigger(data)
  Slot.write(self, bin)
end

function RamPaletteSlot:tbl2trigger(colors)
  local trigger = ""

  for _, packed in ipairs(colors) do
    trigger = trigger .. string.char(packed % 0x100) .. string.char(packed // 0x100)
  end

  return trigger
end

function RamPaletteSlot:createTriggerMask(hook)
  --[[
  RamPalette slots may be constructed to only write some of the colors in
  the palette. In that case, we need to mask the other colors from the
  trigger.
  --]]

  if not self.writable then return nil end

  local mask = ""
  local ignore = string.rep(string.char(0), 2)
  local check = string.rep(string.char(255), 2)

  for i = 1, self.length do
    if general.tblContains(self.writable, i - 1) then
      mask = mask .. check
    else
      mask = mask .. ignore
    end
  end

  return mask
end

function slots.newPaletteSlot(palId, parentSlot, extras)
  if palId >= getPaletteCount() then
    return nil
  end

  local palSize = getPaletteSize()

  local ret = nil

  if extras and extras.address then
    ret = RamPaletteSlot:new("Palette " .. palId, extras.address + 2 * palSize * palId, 2 * palSize, extras)
  else
    ret = PaletteSlot:new("Palette " .. palId, palSize * palId, palSize, extras)
  end
  ret.parentSlot = parentSlot
  return ret
end

-- SpriteSlot: GBA has dynamic memory allocation, so this creates
-- TileSlots based on where actual sprites are listed.
local SpriteSlot = {}
SpriteSlot.__index = SpriteSlot
setmetatable(SpriteSlot, Slot)

function SpriteSlot:new(name, width, height, layout, order, subSlots, extras)
  --[[
  width, height and layout will be passed to the TileSlots and don't
  directly apply to the SpriteSlot.

  One could make it filter based on the position of the sprites, but that
  might crash hacks and palettes have a similar effect.
  --]]
  local obj = Slot.new(self, name, "sprite", name, width * height * slots.getTileSize(), order, subSlots, extras)
  obj.width = width
  obj.height = height
  obj.layout = layout

  obj.out = dbg.getBuffer(name, raconfig.logLevel)

  obj.spriteTbl = {}

  setmetatable(obj, SpriteSlot)

  obj.serialized.width = width
  obj.serialized.height = height
  obj.serialized.layout = layout

  return obj
end

function SpriteSlot:read()
  error("Trying to read a SpriteSlot directly; only the TileSlots that it spawns can be read!")
end

function SpriteSlot:write(data)
  error("Trying to write to a SpriteSlot directly; only the TileSlots that it spawns can be written to!")
end

function SpriteSlot:registerNewSprite(library, spriteData)
  --[[
  While scanning the sprite list, a new sprite that can be relevant was
  discovered.
  --]]
  local baseName = self.name .. "-Sprite"

  -- Pay attention not to put just self.name as that would delete the
  -- sprite slot from the library!
  -- This is obviously redundant, I just want to be sure I don't simplify
  -- the above line accidentally.
  if baseName == self.name then
    baseName = baseName .. "-Sprite"
  end

  -- If we already have that name, append a counter
  -- Since the list is dynamic and potentially discontinuous, we actually
  -- need to check every variant.
  local cnt = 1
  local name = baseName

  while true do
    local fine = true
    for _, sprite in pairs(self.spriteTbl) do
      if sprite.slot.name == name then
        cnt = cnt + 1
        name = baseName .. cnt
        fine = false
        break
      end
    end

    if fine then
      break
    end
  end

  local tileAddress = 0x06010000 + 32 * spriteData.tileIndex
  local order = 100*self.order + cnt
  -- Fix the case of a hidden slot
  if self.order == -1 then
    order = -1
  end

  local slot = TileSlot:new(name, tileAddress, self.width, self.height, self.layout, order, {palette={index=spriteData.paletteIndex}, twins=self.subSlots.twins})

  self.spriteTbl[spriteData.tileIndex] = {
    tileAddress = tileAddress,
    lastSeen = emu:currentFrame(),
    slot = slot,
  }

  -- Register this in the library
  library:addSlot(slot)
  slot.animations = self.animations
  slot.hooks = self.hooks
  slot.parent = self

  self.out:print("Registered TileSlot:", name)
  --self.out:print(base64.encode(slot:read()))
end

local oamSizes = {
  {1, 1}, {2, 2}, {4, 4}, {8, 8},
  {2, 1}, {4, 1}, {4, 2}, {8, 4},
  {1, 2}, {1, 4}, {2, 4}, {4, 8},
}

function SpriteSlot:updateSpriteTable(library)
  local function getOamData(address)
    local bytes = emu:readRange(address, 8)

    local inUse = false
    for iByte = 1, 8 do
      if bytes:byte(iByte) ~= 0 then
        inUse = true
        break
      end
    end

    if not inUse then
      return nil
    end

    local ret = {}

    ret.x = bytes:byte(3) + 256 * bytes:byte(4) % 2
    ret.y = bytes:byte(1)

    local shapeCode = bytes:byte(2) // 64
    local sizeCode = bytes:byte(4) // 64
    local size = oamSizes[4*shapeCode + sizeCode + 1]

    if not size then
      -- These are illegal values, so something is wrong.
      return nil
    end

    ret.width = size[1]
    ret.height = size[2]

    ret.tileIndex = bytes:byte(5) + 256 * (bytes:byte(6) % 4)
    -- + 16 for the sprite palettes
    ret.paletteIndex = bytes:byte(6) // 16 + 16

    return ret
  end

  local function isRelevant(data)
    if data.width ~= self.width or data.height ~= self.height then
      return false
    end

    -- If provided, filter by palette
    if self.subSlots and self.subSlots.palette then
      if self.subSlots.palette.index ~= data.paletteIndex then
        return false
      end
    end

    return true
  end

  -- Cache this for every frame -- this speeds up a ton.
  local currFrame = emu:currentFrame()
  if spriteSlotOamFrame ~= currFrame then
    for iSprite = 1, 128 do
      local address = 0x7000000 + (iSprite - 1) * 8
      local data = getOamData(address)
      spriteSlotOamData[iSprite] = data
    end
    spriteSlotOamFrame = currFrame
  end

  for iSprite = 1, 128 do
    local data = spriteSlotOamData[iSprite]
    if data ~= nil then
      if isRelevant(data) then
        local spriteData = self.spriteTbl[data.tileIndex]
        if spriteData then
          spriteData.lastSeen = currFrame
        else
          -- This is a new, relevant sprite
          self:registerNewSprite(library, data)
        end
      end
    end
  end
end

function SpriteSlot:scanSprites(library)
  --[[
  Iterate over all active sprites -- do we need to create a new TileSlot
  or delete a preexisting one?
  --]]
  -- Check whether we see new sprites and which known ones are still
  -- around.
  self:updateSpriteTable(library)

  -- Check whether anything seems to be obsolete
  local currFrame = emu:currentFrame()
  local deleteList = {}
  for handle, sprite in pairs(self.spriteTbl) do
    -- Delete sprites that have disappeared for five seconds
    -- We cannot make this too short due to possible blinking effects.
    if currFrame - sprite.lastSeen > 5*60 then
      deleteList[#deleteList + 1] = handle
    end
  end

  for _, handle in ipairs(deleteList) do
    local sprite = self.spriteTbl[handle]
    self.spriteTbl[handle] = nil
    self.out:print("Deleted TileSlot", sprite.slot.name)
    library:removeSlot(sprite.slot)
  end
end

slots.Slot = Slot
slots.TileSlot = TileSlot
slots.PaletteSlot = PaletteSlot
slots.RamPaletteSlot = RamPaletteSlot
slots.SpriteSlot = SpriteSlot

return slots
