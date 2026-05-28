
--[[
This module contains AnimPlayers, i.e. the parent class to switch
between different animation strips.

By default, every animation is expected to have an "idle" strip which is
then looped. If it has an "emote" strip, it is placed after every third
"idle".
--]]

local playermod = {}

local dbg = require("debugging")

local raconfig = require("ramanimator/raconfig")
local base64 = require("base64")

local AnimPlayer = {}
AnimPlayer.__index = AnimPlayer

function AnimPlayer:new(anim, slot, cls) 
  --[[
  This basic player will repeat the strip "idle" three times, then play
  "emote" once. If "emote" isn't present, it loops "idle".
  If an "intro" strip is present, it will be played once at the start.

  The slot is stored directly in the player for the case of a SpriteSlot,
  where the animations are collected in SpriteSlot, but need to be
  rendered through TileSlots instead.
  --]]
  local obj = cls and setmetatable({}, cls) or setmetatable({}, AnimPlayer)

  obj.anim = anim
  obj.slot = slot

  obj.debugger = dbg.getBuffer(anim.name, raconfig.logLevel)
  obj.debugger:print("Player created.")

  -- We copy the table of strips because augmentStrips might generate some
  -- extra strips, which we don't want to spill over into the original
  -- animation if it gets exported later on etc.
  obj.strips = {}
  for i, strip in ipairs(anim.strips) do
    obj.strips[i] = strip
    if not strip.tag then
      console:error("Animation " .. anim.hook.name .. " has strip " .. i .. " without a tag!")
    end
  end

  -- Same for frames, since augmentStrips may generate new frames, e.g.
  -- when interpolating palettes.
  obj.frames = {}
  for i, frame in ipairs(anim.frames) do
    obj.frames[i] = frame
  end

  obj.repeats = 0

  -- So augmentStrips can use the cache
  obj:cacheStripTags()

  if not obj:hasStrip("idle") then
    console:error("Trying to instantiate an animation player for " .. tostring(anim.name) .. ", but it doesn't have an 'idle' strip!")
  end

  obj:augmentStrips()

  -- Check which strips I have -- if a subclass adds new phases outside of
  -- augmentStrips, call this again.
  obj:cacheStripTags()

  obj:loadNextStrip()

  obj.iFrame = 0
  obj:advanceFrame()

  return obj
end

function AnimPlayer:hasStrip(tag)
  if not self.stripTagCache then
    self:cacheStripTags()
  end

  return self.stripTagCache[tag]
end

function AnimPlayer:getStripsForTag(tag)
  local ret = {}

  for _, strip in pairs(self.strips) do
    if strip.tag == tag then
      table.insert(ret, strip)
    end
  end

  return ret
end

function AnimPlayer:getFittingStrip(tag, indices, suffixes, depth)
  --[[
  Escalate through the hierarchy until we find a fitting strip.

  Ex: Say we have a sleeping Pokémon in red HP range, but we don't know
  whether it has the exact strip. The function call:
  getFittingStrip("idle", {2, 3}, {{"", "-asleep"}, {"", "-yellow", "-red"}})
  will search through its strips in the following order:
  idle-asleep-red
  idle-asleep-yellow
  idle-asleep
  idle-red
  idle-yellow
  idle
  because a healthier, sleeping monster is closer to what we want than an
  unhealthy, but awake monster.

  If you only have a single layer and pass a scalar as "indices", also
  pass a single table for "suffixes" which will be automatically wrapped.

  If you have more than one layer, pass a table for indices and a table of
  tables for suffixes.

  Pass nothing or 1 for depth.
  --]]
  if not depth then depth = 1 end

  if type(indices) ~= "table" then
    indices = {indices}
    suffixes = {suffixes}
  end

  for i = indices[depth], 1, -1 do
    local handle = tag .. suffixes[depth][i]

    if depth == #indices then
      -- Try to find a corresponding strip.
      if self:hasStrip(handle) then
        return handle
      end
    else
      -- Recurse another layer down
      local ret = self:getFittingStrip(handle, indices, suffixes, depth + 1)
      if ret then return ret end
    end
  end

  if depth == 1 then
    local wishStrip = tag
    --for i = 1, #indices do
    --  wishStrip = wishStrip .. suffixes[indices[i]][1]
    --end

    self.debugger:print("Trying to find a strip for " .. wishStrip .. " but cannot find a fitting one!")
  end

  return nil
end

function AnimPlayer:augmentStrips()
  --[[
  Subclasses might generate default strips from those that are in the
  animation, e.g. changing their speed or tinting palettes.
  --]]
end

function AnimPlayer:cacheStripTags()
  --[[
  Cache available strip tags and their cumulative weight.
  Needs to be rerun if a subclasses new() adds new strips.
  This is useful because it means we can check for a strip's availability
  and total weight via self.stripTagCache[tag].
  --]]
  local cache = {}

  for _, strip in ipairs(self.strips) do
    local tag = strip.tag

    -- This actually writes to the animation, but I think it's fine.
    if not strip.weight then
      strip.weight = 1
    end

    if cache[tag] then
      cache[tag] = cache[tag] + strip.weight
    else
      cache[tag] = strip.weight
    end
  end

  self.stripTagCache = cache
end

function AnimPlayer:writeFrame()
  local anim = self.anim
  local frame = self.frame
  local lastFrame = self.currentFrame

  self.slot:write(frame)

  -- This is here so it is called when a halted animation is resumed.
  if not self.active then
    self.debugger:print("Starting animation " .. anim.name)
  end

  self.active = true

  -- If the data needs to be written to several places, do so now.
  --print("Player", anim.name, "has slot", self.slot.name, "for animation slot", anim.hook.slot.name, anim.hook.hasTwin, self.slot.twins ~= nil)
  if anim.hook.hasTwin and self.slot.twins ~= nil then
    --print("Player", anim.name, "has twins", #self.slot.twins)
    for iTwin, twin in pairs(self.slot.twins) do
      --print("Player", anim.name, ", twin", iTwin)
      local twinMem = twin:read()

      -- lastFrame ~= nil is implied
      if twinMem == anim.hook.trigger or lastFrame == twinMem then
        twin:write(frame)
      elseif anim.hook.twinTriggers ~= nil then

        for iTrig, trig in pairs(anim.hook.twinTriggers) do
          if trig == twinMem then
            twin:write(frame)
          end
        end
      end
    end
  end

  self.currentFrame = frame
end

function AnimPlayer:tick(rewrite)
  self.remainingTime = self.remainingTime - self:getTick()
  if self.remainingTime <= 0 then
    self:advanceFrame()
  elseif rewrite then
    -- RAM was changed in an expected way, rewrite the frame.
    self:writeFrame()
  end
end

function AnimPlayer:getTick()
  -- Can be overridden to slow down / accelerate animations
  return 1
end

function AnimPlayer:loadStrip(stripName)
  -- Given the name of the next strip, load one of its variant
  local anim = self.anim
  self.stripName = stripName
  self.debugger:print("Animation " .. tostring(anim.name) .. " starts strip " .. tostring(stripName))

  if not self:hasStrip(stripName) then
    console:error("Trying to load strip " .. tostring(stripName) .. ", but it doesn't exist in animation " .. tostring(anim.name))
    return
  end

  -- The system allows variants of strips, e.g. there can be a "default"
  -- emote and a rare variant for some variation. In that case, there are
  -- several strips of a given tag. We iterate over them, choosing one by
  -- their weight which must have been cached before.
  local success = false
  local randomNum = math.random() * self.stripTagCache[stripName]
  local cumulativeWeight = 0
  for _, strip in ipairs(self.strips) do
    if strip.tag == stripName then
      cumulativeWeight = cumulativeWeight + strip.weight
      if randomNum <= cumulativeWeight then
        self.frameIndices = strip.frameIndices
        self.timings = strip.timings
        success = true
        break
      end
    end
  end

  if not success then
    -- This can't happen, but just to be safe...
    console:error("Tried to load strip " .. stripName .. " for animation " .. anim.name .. ". With a cached total weight of " .. self.stripTagCache[stripName] .. ", a target weight of " .. randomNum .. " and a total cumulative weight of " .. cumulativeWeight .. ", not suitable strip was found!")
  end
end

function AnimPlayer:selectNextStrip()
  --[[
  This is the function subclasses are meant to override.
  Set the repeat count, return the name of the next strip.
  --]]
  if not self.stripName then
    if self:hasStrip("intro") then
      self.repeats = 0
      return "intro"
    else
      self.repeats = 2
      return "idle"
    end
  end

  if self.stripName == "idle" and self:hasStrip("emote") then
    self.repeats = 0
    return "emote"
  end

  self.repeats = 2
  return "idle"
end

function AnimPlayer:loadNextStrip()
  --[[
  Identifies and loads the next strip. Subclasses are meant to override
  selectNextStrips instead.
  --]]
  local stripName = self:selectNextStrip()

  self:loadStrip(stripName)

  if string.find(self.anim.name, "palette") then
    self.debugger:print("loadNextStrip", self.anim.name, stripName, self.hpState, self.statusCond)
    for i = 1, #self.frameIndices do
      self.debugger:print(i, self.frameIndices[i], self.timings[i])
    end
  end
end

function AnimPlayer:advanceFrame()
  --[[
  Display the next frame. If this is the end of the strip, find the next
  one and queue it.
  --]]
  -- Take this animation and place its next frame.
  local iFrame = self.iFrame + 1
  local anim = self.anim

  if iFrame > #self.frameIndices then
    -- Move over to the next strip
    if self.repeats > 0 then
      self.repeats = self.repeats - 1
    else
      self:loadNextStrip()
    end

    iFrame = 1
  end

  self.iFrame = iFrame

  --self.debugger:print(emu:currentFrame() .. " Placing frame " .. tostring(iFrame) .. " of animation " .. self.anim["name"])
  self.frame = self.frames[self.frameIndices[iFrame]]
  self.remainingTime = self.timings[iFrame]

  self:writeFrame()
end

playermod.AnimPlayer = AnimPlayer

return playermod
