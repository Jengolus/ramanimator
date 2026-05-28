
--[[
AnimPlayers specific to Pokemon games
--]]

local playermod = require("ramanimator/player")
local raconfig = require("ramanimator/raconfig")

local hpSuffixes = {"", "-yellow", "-red", "-fainted"}
local trainerStatusSuffixes = {entry="", loss="-loss", win="-win"}

local players = {}

local function GBGetStatusCondition(player, mapOffset, aTile)
  -- Identify a monster's status condition by reading it from the screen.
  -- Used both by the PokemonPlayer and the PokemonPalettePlayer.
  -- aOffset is the index of the tile that contains 'A', usually 0x80
  if not mapOffset then return "ok" end

  local status = ""
  for i = 1, 3 do
    local char = string.byte("A") + emu:read8(mapOffset + i - 1) - aTile
    if char < 0 or char > 255 then
      char = "#"
    else
      char = string.char(char)
    end
    status = status .. char
  end

  -- Return the status matched by the string
  -- The weird ones are for Japanese
  local tests = {
    sleep = {"SLP", "DRM", "SOM", "SLF", "DOR", string.char(137, 146, 153)},
    poison = {"PSN", "GIF", "ENV", "VLN", "1y@"},
    freeze = {"FRZ", "GEL", "CON", "GFR", string.char(123, 118, 153)},
    paralysis = {"PAR", string.char(144, 140, 64)},
    burn = {"BRN", "QUE", "BRU", "BRT", string.char(149, 122, 49)},
  }

  for effect, strings in pairs(tests) do
    for i, option in pairs(strings) do
      if status == option then return effect end
    end
  end

  -- Debug output
  player.debugger:print("Status condition", status, string.byte(status, 1), string.byte(status, 2), string.byte(status, 3), "from", string.format("%x", mapOffset))

  return "ok"
end

local PokemonPlayer = {}
PokemonPlayer.__index = PokemonPlayer
setmetatable(PokemonPlayer, playermod.AnimPlayer)

function PokemonPlayer:new(anim, slot, cls)
  --[[
  This subclass outlines functions to retrieve relevant information about
  the currently visible monster if the offsets for the current game are
  available. These need to be implemented for every targeted generation.
  --]]
  if not cls then error("Trying to instantiate an abstract PokemonPlayer! The subclass needs to pass itself to new()!") end
  local obj = playermod.AnimPlayer:new(anim, slot, cls)

  obj.hpState = obj:getHpState()
  obj.statusCond = obj:getStatusCondition()
  obj.phase = "idle"

  return obj
end

function PokemonPlayer:augmentStrips()
  -- Auto-generate low-HP strips
  for hpState = 2, 4 do
    for _, stripTag in ipairs({"idle", "emote"}) do
      local handle = stripTag .. hpSuffixes[hpState]
      --print("augment check handle", handle)

      -- It makes more sense for a fainted monster not to emote by
      -- default.
      local blacklisted = handle == "emote-fainted"

      -- If there is no strip of that tag, just take all strips of the
      -- preceeding class slowed down.
      if not self:hasStrip(handle) and not blacklisted then
        --print("augment cannot find handle", handle)
        -- Find strips of the preceeding class
        local refHandle = stripTag .. hpSuffixes[hpState - 1]
        local refStrips = self:getStripsForTag(refHandle)
        --print("augment found", #refStrips, "strips", refHandle)

        for _, strip in ipairs(refStrips) do
          local newTimings = {}
          for i, dur in ipairs(strip.timings) do
            newTimings[i] = dur * 1.5
          end
          --print("auto generated", strip.tag)
          table.insert(self.strips, {tag=handle, frameIndices=strip.frameIndices, timings=newTimings, weight=strip.weight})
        end
      end
    end
  end

  -- Add a strip that is just the trigger again; useful if we still need
  -- time to load the screen to know the HP bar or similar.
  self.frames[#self.frames + 1] = self.anim.hook.trigger
  table.insert(self.strips, {tag="await-trigger", frameIndices={#self.frames}, timings={1}, weight=1})
end

function PokemonPlayer:selectNextStrip()
  --[[
  How does this work? In principle, I have the cycle between idle and
  emote as usual. Further, I want to distinguish between awake and asleep,
  which takes precedence over HP state.
  --]]
  local hpState = self:getHpState()

  if not hpState then
    if not self.hpState then
      if self.slot.name == "FrontM" then
        self.debugger:print("Could not determine HP")
        return "await-trigger"
      else
        hpState = 1
      end
    end

    hpState = self.hpState
  end

  local statusCond = self:getStatusCondition()  

  if not statusCond then
    if not self.statusCond then
      if self.slot.name == "FrontM" then
        self.debugger:print("Could not determine status conditions")
        return "await-trigger"
      end
    end

    statusCond = self.statusCond
  end

  self.statusCond = statusCond

  local sleepIndex = statusCond == "sleep" and 2 or 1
  --print("Status condition", self.statusCond, asleep)

  if self.sleepIndex and sleepIndex ~= self.sleepIndex then
    self.sleepIndex = sleepIndex

    -- Play an animation of the mon falling asleep / waking up if
    -- available.
    local nextStrip = nil
    if sleepIndex == 1 then
      nextStrip = self:getFittingStrip("wakeup", hpState, hpSuffixes)
    else
      nextStrip = self:getFittingStrip("fallasleep", hpState, hpSuffixes)
    end

    if nextStrip then
      return nextStrip
    end
  end

  if self.hpState and hpState ~= self.hpState then
    -- Play a transition between the cycles if available.
    -- If the monster is asleep, this will only play "asleep-" strips and
    -- skip all those with open eyes.
    local slpPrefix = sleepIndex == 2 and "asleep-" or ""
    local nextStrip = nil
    if hpState > self.hpState then
      nextStrip = self:getFittingStrip(slpPrefix .. "hurtto", hpState, hpSuffixes)
    else
      nextStrip = self:getFittingStrip(slpPrefix .. "healto", hpState, hpSuffixes)
    end

    self.hpState = hpState

    if nextStrip then
      return nextStrip
    end
  end

  if not self.hpState then
    self.hpState = hpState
  end

  -- Handle the cycle between idle and emote through the parent.
  local stripTmp = self.stripName
  self.stripName = self.phase
  local phase = playermod.AnimPlayer.selectNextStrip(self)
  self.phase = phase

  -- If asleep, take any sleep strip. If there are none, take the closest
  -- awake strip.
  local nextStrip = self:getFittingStrip(phase, {sleepIndex, hpState}, {{"", "-asleep"}, hpSuffixes})

  -- If we are in a fainted / asleep idle, do not play an unfainted / 
  -- awake emote.
  if stripTmp and nextStrip
    and (string.find(stripTmp, "-asleep") or string.find(stripTmp, "-fainted"))
    and not (string.find(nextStrip, "-asleep") or string.find(nextStrip, "-fainted")) then
    self.phase = "idle"
    nextStrip = self:getFittingStrip("idle", {sleepIndex, hpState}, {{"", "-asleep"}, hpSuffixes})
  end

  --print("Next strip: ", nextStrip, phase, sleepIndex, hpState)
  return nextStrip
end

function PokemonPlayer:getHpState()
  --[[
  1 - Green HP bar
  2 - Yellow
  3 - Red
  4 - Fainted
  --]]
  return 1
end

function PokemonPlayer:getStatusCondition()
  -- "ok", "sleep", "poison", "burn", "paralysis", "freeze"
  return "ok"
end

function PokemonPlayer:getTick()
  if self.statusCond then
    if self.statusCond == "freeze" then
      -- Update our status, otherwise we are stuck forever
      self.statusCond = self:getStatusCondition()
      return 0
    end

    -- Nothing special for sleep because that has its own animations in
    -- theory.
    if self.statusCond == "sleep" or self.statusCond == "ok" then
      return 1
    end

    return 0.5
  end

  return 1
end

local GBPokemonPlayer = {}
GBPokemonPlayer.__index = GBPokemonPlayer
GBPokemonPlayer.handle = "GBPokemonPlayer"
setmetatable(GBPokemonPlayer, PokemonPlayer)
players["GBPokemonPlayer"] = GBPokemonPlayer

function GBPokemonPlayer:new(anim, slot)
  local obj = PokemonPlayer:new(anim, slot, GBPokemonPlayer)

  return obj
end

function GBPokemonPlayer:getHpState()
  --[[
  1 - Green HP bar
  2 - Yellow
  3 - Red
  4 - Fainted
  
  To avoid asking the user to provide offsets for every possible game /
  hack, we read the HP bar length off the screen. This means the user only
  needs to provide the first index of the HP bar in the tile index and 
  (unlikely to change) the tile index of the first HP bar tile.
  --]]
  if self.slot.name == "FrontM" and self.hpState then
    -- A FrontM sprite cannot change its HP state, but the bar can
    -- disappear on the status screen, so we take note once at the start,
    -- then use the cached value.
    return self.hpState
  end

  local parameters = self.slot.extras

  -- Let's assume that the hack did not change the HP bar, so we can use
  -- it to estimate the HP. For the player, we could also read the exact
  -- numbers, but there is no need.
  local mapOffset = parameters.hpbarTileOffset

  local emptyTile = parameters.emptyHpTile % 256 -- The tile for zero pixels
  local pixels = 0
  for i = 1, 6 do
    local tile = emu:read8(mapOffset + i - 1) - emptyTile
    -- Ensure this is an HP bar, not the Pokedex
    local readTile = emu:read8(mapOffset + i - 1)
    --print("hpStatus test:", mapOffset, readTile, emptyTile)
    if readTile == parameters.screenloadTile or readTile == 0 then 
      -- Add an exception for the evolution screen: We check whether what
      -- would be its sprite's top-left corner is actually a sprite.
      local evolutionTopLeft = emu:read8(0x9847)
      if evolutionTopLeft == 0x5b or evolutionTopLeft == 0x2a then
        return 1
      end
      -- Screen is still building up
      --print(self.anim.name, "-> delaying");
      return nil
    end
    if tile < 0 or tile > 8 then return 1 end
    pixels = pixels + tile
  end

  --self.debugger:print("Current HP pixels: ", pixels)
  --self.debugger:print("Limits", parameters.hpBarYellowLimit, parameters.hpBarRedLimit)

  if pixels == 0 then return 4 end
  if pixels < parameters.hpBarRedLimit then return 3 end
  if pixels < parameters.hpBarYellowLimit then return 2 end

  return 1
end

function GBPokemonPlayer:getStatusCondition()
  --[[
  To avoid having to ask the player for memory offsets for hacks, we read
  the status condition directly from screen, which is a bit of a hassle
  because of the different languages of the games.
  --]]
  if self.slot.name == "FrontM" and self.statusCond then
    -- A FrontM sprite cannot change its status condition, but the info
    -- can disappear from the status screen, so we take note once at the
    -- start, then use the cached value.
    return self.statusCond
  end

  return GBGetStatusCondition(self, self.slot.extras.statusTileOffset, self.slot.extras.aTile)
end

local TrainerPlayer = {}
TrainerPlayer.__index = TrainerPlayer
setmetatable(TrainerPlayer, playermod.AnimPlayer)

function TrainerPlayer:new(anim, slot, cls)
  --[[
  Equivalent to PokemonPlayer, this class provides the base functions
  and a subclass for every generation needs to implement how specifically
  the data is obtained.

  Trainers have the following states:
  - entry
  - loss
  - win, which I think only the first rival fight actually has in the
    game.
  --]]
  if not cls then error("Trying to instantiate an abstract TrainerPlayer! The subclass needs to pass itself to new()!") end
  local obj = playermod.AnimPlayer:new(anim, slot, cls)
  return obj
end

function TrainerPlayer:determineStatus()
  return "entry"
end

function TrainerPlayer:selectNextStrip()
  --[[
  This cycles between idle and emote as usual. Further, it distinguishes
  between entry, loss (and win).
  --]]

  -- Determine once at the start because it cannot change.
  if not self.status then
    self.status = self:determineStatus()
    --print("Trainer status", self.status)
  end

  local status = self.status

  -- Handle the cycle between idle and emote through the parent.
  local stripTmp = self.stripName
  self.stripName = self.phase
  local phase = playermod.AnimPlayer.selectNextStrip(self)
  self.phase = phase

  local nextStrip = nil

  -- Skip the intro if we don't have one for this specific status
  if phase == "intro" then
    local handle = "intro" .. trainerStatusSuffixes[status]
    if self:hasStrip(handle) then
      return handle
    end

    -- We don't have the exact strip, move over to idle
    phase = "idle"
    self.phase = phase
  end

  local nextStrip = self:getFittingStrip(phase, 2, {"", trainerStatusSuffixes[status]})
  --print("Next strip: ", nextStrip, phase, hpState)
  return nextStrip
end

local GBTrainerPlayer = {}
GBTrainerPlayer.__index = GBTrainerPlayer
GBTrainerPlayer.handle = "GBTrainerPlayer"
setmetatable(GBTrainerPlayer, TrainerPlayer)

players["GBTrainerPlayer"] = GBTrainerPlayer

function GBTrainerPlayer:new(anim, slot)
  local obj = TrainerPlayer:new(anim, slot, GBTrainerPlayer)

  return obj
end

function GBTrainerPlayer:determineStatus()
  --[[
  Distinguish whether the trainer is about to start, has lost or has won.
  Intro: 0x9C00 -> 0x9FFF are all 0x7F
  Win: 0x9CE0 -> 0x9D7F is 0x7F
  Otherwise and as usual, the trainer lost.
  The only trainer who can win and then appear on the screen are the first
  two rival fights, to my knowledge.
  --]]
  -- Can be set via the server when rendering out animations in a demo
  -- video.
  if raconfig.extras.forceTrainerStatus then
    return "entry"
  end

  -- Is the screen uniform? Then the battle is still loading
  local fullLength = 0x9fff - 0x9c00
  local fullScreen = emu:readRange(0x9c00, fullLength)
  local empty = string.rep(string.char(0x7f), fullLength)

  if fullScreen == empty then
    return "entry"
  end

  -- Did the trainer win? Only relevant for first rival battle.
  -- Check whether the player's screen area is all blank.
  local checkLength = 0x9d7f - 0x9ce0
  local screenSub = fullScreen:sub(0xe0 - 1, 0xe0 - 2 + checkLength)
  local subRef = string.rep(string.char(0x7f), #screenSub)

  if screenSub == subRef then
    return "win"
  end

  return "loss"
end

local PalettePlayer = {}
PalettePlayer.__index = PalettePlayer
setmetatable(PalettePlayer, playermod.AnimPlayer)

function PalettePlayer:new(anim, slot, cls)
  --[[
  To visualize a monster's status condition, this player can tint its
  palette.
  --]]
  if not cls then error("Trying to instantiate an abstract PalettePlayer! The subclass needs to pass itself to new()!") end
  local obj = playermod.AnimPlayer:new(anim, slot, cls)

  obj.statusCond = obj:getStatusCondition()

  return obj
end

function PalettePlayer:getStatusCondition()
  -- Same as for PokemonPlayer
  return "ok"
end

function PalettePlayer:augmentStrips()
  --[[
  Provide tinted palettes and transitions for all non-volatile status
  conditions except sleep.
  --]]
  local origPal = self.frames[1]

  local function addTint(name, tint)
    -- Mix the palettes to obtain the final color
    local final = {}
    for iColor = 1, #tint do
      local bottom = util.unpackColor(origPal[iColor])
      local top    = util.unpackColor(tint[iColor])

      local mixed = {}

      local function mix(b, s)
        return b + (s - b) / 2
      end

      for iChannel = 1, 3 do
        local orig = bottom[iChannel]
        local added = top[iChannel]
        mixed[iChannel] = math.floor(mix(added, orig))
      end

      final[#final + 1] = mixed
    end

    -- Now add the fade / heal animation
    local indices = {}
    local revIndices = {}
    local timings = {}
    local nFrames = 60

    for iFrame = 1, nFrames do
      local frame = {}

      for iColor = 1, math.min(#origPal, #tint) do
        local origColor = util.unpackColor(origPal[iColor])
        local targetColor = final[iColor]
        local color = {}

        for channel = 1, 3 do
          local start = origColor[channel]
          local target = targetColor[channel]
          local intermediate = start + (target - start) * iFrame // nFrames
          table.insert(color, intermediate)
        end

        table.insert(frame, util.packColor(color[1], color[2], color[3]))
      end

      local frameId = #self.frames + 1
      self.frames[frameId] = frame
      indices[iFrame] = frameId
      revIndices[nFrames + 1 - iFrame] = frameId
      timings[iFrame] = 1
    end

    table.insert(self.strips, {tag="afflict-" .. name, frameIndices=indices, timings=timings})
    table.insert(self.strips, {tag="heal-" .. name, frameIndices=revIndices, timings=timings})

    -- Add the final frame generated by the loop below.
    local strip = {tag=name, frameIndices={#self.frames}, timings={30}}
    table.insert(self.strips, strip)
  end

  --addTint("poison", {32703, 25307, 24053, 2115})
  --addTint("burn", {32703, 10911, 6490, 2115})
  --addTint("paralysis", {32703, 15263, 666, 2115})
  --addTint("freeze", {32703, 28306, 24043, 2115})
  local purple = util.packColor(31, 0, 31)
  addTint("poison", {purple, purple, purple, purple})
  addTint("burn", {31, 31, 31, 31})
  addTint("paralysis", {32703, 31 + 32 * 31, 31 + 32 * 31, 2115})
  addTint("freeze", {32703, 31 * 32*32, 31 * 32*32, 2115})
end

function PalettePlayer:selectNextStrip()
  --[[
  Apply / remove tints for status conditions
  --]]
  local statusCond = self:getStatusCondition() 

  if self.statusCond and self.statusCond ~= statusCond then
    -- Play an animation of the tint building / disappearing.
    local stripName = nil
    if statusCond == "ok" then
      stripName = "heal-" .. self.statusCond
    else
      stripName = "afflict-" .. statusCond
    end

    self.statusCond = statusCond

    -- It should have an autogenerated one
    if self:hasStrip(stripName) then
      return stripName
    end

    -- Otherwise fall through
  end

  self.statusCond = statusCond

  if self:hasStrip(statusCond) then return statusCond end

  return "idle"
end

local GBPalettePlayer = {}
GBPalettePlayer.__index = GBPalettePlayer
GBPalettePlayer.handle = "GBPalettePlayer"
setmetatable(GBPalettePlayer, PalettePlayer)
players["GBPalettePlayer"] = GBPalettePlayer

function GBPalettePlayer:new(anim, slot)
  local obj = PalettePlayer:new(anim, slot, GBPalettePlayer)

  return obj
end

function GBPalettePlayer:getStatusCondition()
  --[[
  To avoid having to ask the player for memory offsets for hacks, we read
  the status condition directly from screen, which is a bit of a hassle
  because of the different languages of the games.
  --]]
  if self.slot.parentSlot.name == "FrontM" and self.statusCond then
    -- A FrontM sprite cannot change its status condition, but the info
    -- can disappear from the status screen, so we take note once at the
    -- start, then use the cached value.
    return self.statusCond
  end

  return GBGetStatusCondition(self, self.slot.parentSlot.extras.statusTileOffset, self.slot.parentSlot.extras.aTile)
end

return players
