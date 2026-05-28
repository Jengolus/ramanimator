
--[[
This module contains the functions that convert between raw index lists
and the platform's VRAM format.
--]]

local conversions = {}

local general = require("general")

-- COL_MAJOR: If the tiles are sorted column-major in memory.
-- REVERSE_TILES_X: If the colums are fine, but their order reversed.
--   This operates after the tiles are sorted to be row-major.
-- I believe reversing about y might just be both of these together
-- RAW: Copy as is, i.e. non-image data
local layoutFlags = {COL_MAJOR = 1, REVERSE_TILES_X = 2, RAW = 128}
conversions.layoutFlags = layoutFlags

local function tile2pixels(tile)
  -- Convert one 8x8 tile from the memory layout to a grid of pixels
  -- indexed as 8*y + x
  local pixels = {}

  if emu:platform() == C.PLATFORM.GB then
    -- Actually, depth is always 2, but whatever
    for row = 1, 8 do
      local depth = general.getTileDepth()

      for bit = 1, 8 do
        pixels[8*row - bit + 1] = 0
      end

      for i = 1, depth do
        local byte = tile:byte(depth*(row - 1) + i)

        -- The tiles index the bits right-to-left
        for bit = 1, 8 do
          local mask = 2^(bit - 1)
          pixels[8*row - bit + 1] = pixels[8*row - bit + 1] + 2^(i - 1) * ((mask & byte) >> (bit - 1))
        end
      end
    end
  else
    -- GBA
    for i = 1, #tile do
      local byte = tile:byte(i)
      local low = byte & 0xF
      table.insert(pixels, low)
      local high = (byte >> 4) & 0xF
      table.insert(pixels, high)
    end
  end

  return pixels
end

local function pixels2tile(tile)
  -- Convert one 8x8 tile from a grid of pixels to the memory layout
  local data = ""

  if emu:platform() == C.PLATFORM.GB then
    for row = 1, 8 do
      local byte1 = 0
      local byte2 = 0

      -- The tiles index the bits right-to-left
      for col = 1, 8 do
        local pixel = tile[8*(row - 1) + col]

        if pixel % 2 == 0 then
          byte1 = 2*byte1 + 0
        else
          byte1 = 2*byte1 + 1
        end

        if pixel // 2 == 0 then
          byte2 = 2*byte2 + 0
        else
          byte2 = 2*byte2 + 1
        end
      end

      data = data .. string.char(byte1) .. string.char(byte2)
    end
  else
    -- GBA
    for i = 1, #tile // 2 do
      local high = tile[2*i]
      local low = tile[2*i - 1]
      local byte = low + 0x10 * high
      data = data .. string.char(byte)
    end
  end

  return data
end

function conversions.vram2frame(ramdata, width, height, layout)
  -- width, height in tiles
  local data = ""

  local tiles = {}

  local tileSize = general.getTileSize()

  if (layout & layoutFlags.COL_MAJOR) ~= 0 then 
    for col = 1, width do
      for row = 1, height do
        local start = tileSize*(height*(col - 1) + row - 1) + 1
        tiles[width*row + col - 1] = tile2pixels(string.sub(ramdata, start, start + tileSize))
      end
    end
  else
    for row = 1, height do
      for col = 1, width do
        local start = tileSize*(width*(row - 1) + col - 1) + 1
        tiles[width*row + col - 1] = tile2pixels(string.sub(ramdata, start, start + tileSize))
      end
    end
  end

  -- At this point, tiles contains all tiles in column-major order
  
  for row = 1, height do
    for subrow = 1, 8 do
      local tile = nil
      for col = 1, width do
        if (layout & layoutFlags.REVERSE_TILES_X) ~= 0 then
          tile = tiles[width*row + width - col]
        else
          tile = tiles[width*row + col - 1]
        end

        for subcol = 1, 8 do
          data = data .. string.char(tile[8*subrow - 8 + subcol])
        end
      end
    end
  end

  return data
end

function conversions.frame2vram(frame, width, height, layout)
  -- Given a row-major frame, convert it to what it looks like in memory.

  -- First, convert it to a 2D array of tiles of pixels
  local tiles = {}
  local pixel = nil
  local rowStride = 8*width

  local col = nil
  for row = 1, height do
    for rcol = 1, width do
      if (layout & layoutFlags.REVERSE_TILES_X) ~= 0 then
        col = width - rcol + 1
      else
        col = rcol
      end

      local tile = {}
      for subrow = 1, 8 do
        local locrow = 8*(row - 1) + subrow - 1
        for subcol = 1, 8 do
          local loccol = 8*(col - 1) + subcol - 1

          pixel = frame:byte(locrow*rowStride + loccol + 1)

          tile[8*(subrow - 1) + subcol] = pixel
        end
      end

      tiles[width*(row - 1) + rcol] = tile
    end
  end

  -- At this point, tiles contains 8x8 tiles

  ret = ""

  if (layout & layoutFlags.COL_MAJOR) ~= 0 then
    for col = 1, width do
      for row = 1, height do
        ret = ret .. pixels2tile(tiles[width*(row - 1) + col])
      end
    end
  else
    for row = 1, height do
      for col = 1, width do
        ret = ret .. pixels2tile(tiles[width*(row - 1) + col])
      end
    end
  end

  return ret
end

function conversions.unpackPalette(palette)
  -- Locally, we store palettes in the console's format just like the
  -- triggers. When sending them away, we need to convert to RGB triples.
  -- This is the CGB conversion formula, not SGB.
  if not palette then
    return nil
  end

  local ret = {}
  for i = 1, #palette do
    local color = palette[i]
    local r = (color & 31) * 255 // 31
    local g = ((color >> 5) & 31) * 255 // 31
    local b = ((color >> 10) & 31) * 255 // 31
    table.insert(ret, {r, g, b})
  end

  return ret
end

function conversions.packPalette(palette)
  -- Convert a list of RGB triples to the native format
  if not palette then
    return nil
  end

  local ret = {}
  for i, color in ipairs(palette) do
    -- Round up to make repeated applications of unpack + pack not
    -- change the values.
    local r = math.ceil(color[1] * 31 / 255)
    local g = math.ceil(color[2] * 31 / 255)
    local b = math.ceil(color[3] * 31 / 255)
    local col = (b << 10) + (g << 5) + r
    table.insert(ret, col)
  end

  return ret
end

function conversions.unpackColor(color)
  -- mGBA does not offer this function directly in 0.10.5
  return {color & 31, (color >> 5) & 31, (color >> 10) & 31}
end

function conversions.packColor(r, g, b)
  -- mGBA does not yet offer this function in 0.10.5
  return r + 32 * g + 32 * 32 * b
end

function conversions.mirrorFrame(inf, width, height)
  -- Mirror a frame vertically.
  local newFrame = ""
  local stride = 8*width

  for y = 1, 8 * height do
    for x = 1, 8 * width do
      local pixel = (stride - x) + (y - 1) * stride + 1
      newFrame = newFrame .. string.sub(inf, pixel, pixel)
    end
  end

  return newFrame
end

return conversions
