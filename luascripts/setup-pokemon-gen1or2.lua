
--[[
There is hardly anything to configure for non-Crystal GB games.
--]]

local base64 = require("base64")

console:log("")
console:log("Tool to configure generation 1 and 2 games")

if emu == nil then
  console:error("You first need to load a game.")
  return
end

if emu:platform() ~= C.PLATFORM.GB then
  console:error("This script only works for GB games. Try using a script for gen3 games.")
  return
end

local function getGeneration()
  -- Infer the generation from the cartridge header
  -- Check whether the highest bit is set, then it isn't ASCII
  if emu:read8(0x143) > 127 then return 2 end

  return 1
end

local function printCode(code)
  console:log("Add the following block to ramanimator/identify-checksum.lua. If you already added one for this game, replace it. Stretch this scripting window to be so wide that all lines fit without wrapping around before copying. Do not copy the ---------")

  local checksum = base64.encode(emu:checksum())
  local name = emu:getGameTitle()
  console:log(string.format(code, checksum, name))
  console:log("Remove all lines with \"local baseGame\" except for the one that matches the hack's base. Remove that line's -- at the start if it has any.")
end

local gen1code = [[
----------------
    if checksum == "%s" and name == "%s" then
        -- Add the game's name inside the ""
        local gameName = "First generation game"

        local pkmn = require("ramanimator/pokemon")

        -- Remove the -- in front of the correct base game,
        -- remove all other lines
        --local baseGame = "gen1rg" -- Japanese Red & Green
        --local baseGame = "gen1rb" -- Red & Blue
        --local baseGame = "gen1y" -- Yellow
        
        local hookFile = "ramanimator/data/pkmn-" .. baseGame .."-hooks"

        local hookmod = require(hookFile)
        local slots, hooks = table.unpack(hookmod)
        local anims = pkmn.getAnimations("gen1")

        return pkmn.finalizeLibrary(gameName, 1, slots, hooks, anims, extras)
    end
----------------
]]

local gen2code = [[
----------------
    if checksum == "%s" and name == "%s" then
        -- Add the game's name inside the ""
        local gameName = "Second generation game"

        local pkmn = require("ramanimator/pokemon")

        local extras = {}
        -- Remove the -- in front of the correct base game,
        -- remove all other lines
        --local baseGame = "gen2gold" -- Gold
        --local baseGame = "gen2silver" -- Silver
        --local baseGame = "gen2crystal" -- Crystal
        --local baseGame = "gen2jpgold" -- Japanese Gold
        --local baseGame = "gen2jpsilver" -- Japanese Silver
        --local baseGame = "gen2jpcrystal" -- Japanese Crystal
        --local baseGame = "gen1gold" -- Gen1 with Gold sprites
        --local baseGame = "gen1silver" -- Gen1 with Silver sprites
        --local baseGame = "gen1crystal" -- Gen1 with Crystal sprites

        if baseGame == "gen2crystal" or baseGame == "gen2jpcrystal" then
            extras.patchCrystal = true
        end
        
        local hookFile = "pkmn-" .. baseGame .."-hooks"
        local animations = "gen2"
        local generation = 2

        if baseGame == "gen1gold" or baseGame == "gen1silver" or baseGame == "gen1crystal" then
          generation = 1
          animations = "gen1fullcolor"
        end

        local hookmod = require("ramanimator/data/" .. hookFile)
        local slots, hooks = table.unpack(hookmod)
        local anims = pkmn.getAnimations(animations)

        return pkmn.finalizeLibrary(gameName, generation, slots, hooks, anims, extras)
    end
----------------
]]

local generation = getGeneration()

if generation == 1 then
  console:log("Found a first generation game.")
  printCode(gen1code)
else
  console:log("Found a second generation game.")
  printCode(gen2code)
end

console:error("Please note:")
  console:log([[The graphics in the game need to match the ones of the base game exactly, so hacks with custom sprites, even tiny alterations, cannot be animated.]])

if generation == 2 then
  console:log([[This game was recognized as gen 2 because it has GBC support. If this is actually a gen 1 game with color support you can try proceeding since these often use gen 2 sprites, but expect to run into difficulties.]])
end

if emu.writePalette == nil or emu.readPalette == nil then
  console:log("You are playing a Gameboy game on a version of mGBA that does not allow scripts to write to palettes. This means that all animations will appear in the colors that the original sprites have. If you want full color support, read the documentation online.")
end

console:log("After saving the modified file, reset and reload all scripts.")
