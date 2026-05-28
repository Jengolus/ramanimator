
--[[
Send the current sprite to ramanimator and see it animated live.
--]]

-- Loaded modules are persistent in Aseprite.
package.loaded["emulator"] = nil

local emulator = require("emulator")
local base64 = require("base64")
local pluginKey = "jengolus/ramanimator"

local sprite = app.activeSprite

if not sprite then return app.alert("No active sprite!") end

local hookName = sprite.properties(pluginKey).hookName

if not hookName then
  return app.alert("You need to attach a hook to this sprite.")
end

local animation = {}

local props = sprite.properties(pluginKey)
animation["name"] = hookName
animation["width"] = sprite.width
animation["height"] = sprite.height

local frames = {}
local frameTimings = {}

local loopStart = nil
local loopEnd = nil
local loopReps = 1

-- Which index frame i of the animation corresponds to in frames
local frameInds = {}
-- Key: Base64 of a frame, value: its index in frames
local frameKeys = {}

for iFrame, frame in ipairs(sprite.frames) do
  -- Render the frame to a virtual image
  local img = Image(sprite.width, sprite.height, ColorMode.INDEXED)
  img:drawSprite(sprite, iFrame)

  -- Put the frame into a byte string
  local frameData = ""

  for it in img:pixels() do
    local color = it()
    -- Correct for the transparency
    if color ~= 0 then color = color - 1 end
    frameData = frameData .. string.char(color)
  end

  -- Append to lists
  frameData = base64.encode(frameData)

  local key = frameKeys[frameData]

  if not key then
    key = #frames + 1
    frameKeys[frameData] = key
    table.insert(frames, frameData)
  end

  frameInds[iFrame] = key
  frameTimings[iFrame] = math.floor(1000*frame.duration)
end

-- Convert the tags to strips
local strips = {}

if #sprite.tags == 0 then
  -- If there are no tags, tag everything as idle
  strips[1] = {tag="idle", frameIndices=frameInds, timings=frameTimings}
else
  -- Anything that doesn't have a tag isn't transferred
end

for i, tag in ipairs(sprite.tags) do
  local name = tag.name
  local fromFrame = tag.fromFrame.frameNumber
  local toFrame = tag.toFrame.frameNumber

  local frameIndices = {}
  local timings = {}

  if tag.aniDir == AniDir.FORWARD or tag.aniDir == AniDir.PING_PONG then
    for iFrame = fromFrame, toFrame do
      table.insert(frameIndices, frameInds[iFrame])
      table.insert(timings, frameTimings[iFrame])
    end
  end

  if tag.aniDir ~= AniDir.FORWARD then
    for iFrame = toFrame, fromFrame, -1 do
      table.insert(frameIndices, frameInds[iFrame])
      table.insert(timings, frameTimings[iFrame])
    end
  end

  if tag.aniDir == AniDir.PING_PONG_REVERSE then
    for iFrame = fromFrame, toFrame do
      table.insert(frameIndices, frameInds[iFrame])
      table.insert(timings, frameTimings[iFrame])
    end
  end

  local weight = 1  -- Default weight
  
  local userdata = tag.data

  -- Use pattern matching to find a number in the user data -- or not.
  local numberStr = string.match(userdata, "^(%d+)$")

  if numberStr then
    weight = tonumber(numberStr)
  end

  table.insert(strips, {tag=name, frameIndices=frameIndices, timings=timings, weight=weight})

  --print("Strip", name)
  --for i = 1, #frameIndices do
  --  print(frameIndices[i], timings[i])
  --end
end

animation.frames = frames
animation.strips = strips

-- Finally, add the palette
local pal = {}
local palettes = {}
local palette = sprite.palettes[1]
local isDefaultPalette = #palette == #emulator.defaultPalette

--TODO make more robust
local paletteSize = 4
if (#palette - 1) % 16 == 0 then
  paletteSize = 16
end

for i = 1, #palette - 1 do -- Skip transparency
  local col = palette:getColor(i)
  table.insert(pal, {col.red, col.green, col.blue})

  -- Once we have a full palette, push it.
  if #pal == paletteSize then
    palettes[#palettes + 1] = pal
    pal = {}
  end

  if isDefaultPalette then
    local defCol = emulator.defaultPalette[i + 1]
    if col.red ~= defCol.red or col.green ~= defCol.green or col.blue ~= defCol.blue then
      isDefaultPalette = false
    end
  end
end

-- Make sure this isn't the default palette
if not isDefaultPalette then
  animation.palettes = palettes
end

emulator.sendCommand(emulator.printAnswer, "registerAnimation", animation)
