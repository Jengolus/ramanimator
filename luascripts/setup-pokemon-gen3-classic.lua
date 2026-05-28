
--[[
Check whether we can programmatically deactivate stuff in Gen3. If not,
recommend using gen3emerald-alt instead.
--]]

console:log("")
console:log("Tool to configure generation 3 games that don't use Emerald Expansion")

if emu == nil then
  console:error("You first need to load a game.")
  return
end

if emu:platform() ~= C.PLATFORM.GBA then
  console:error("This script only works for GBA games. Try using setup-pokemon-gen1or2.lua for GB games.")
  return
end

local base64 = require("base64")
local memory = require("memory")
local raconfig = require("ramanimator/raconfig")

local function printCode(code)
  console:log("Add the following block to ramanimator/identify-checksum.lua. If you already added one for this game, replace it. Stretch this scripting window to be so wide that all lines fit without wrapping around before copying. Do not copy the ---------")

  local checksum = base64.encode(emu:checksum())
  local name = emu:getGameTitle()
  console:log(string.format(code, checksum, name))
end

local code = [[
----------------
    if checksum == "%s" and name == "%s" then
        -- Add the game's name inside the ""
        local gameName = "Classic third generation game"

        local pkmn = require("ramanimator/pokemon")

        local extras = {
            gbaFindPalettes={swapBufferOrder=false},
            gbaDeactivateBounce={},
        }

        -- Remove the -- in front of the correct base game,
        -- remove all other lines
        --local baseGame = "gen3rs" -- Ruby / Sapphire
        --local baseGame = "gen3frlg" -- Fire Red / Leaf Green
        --local baseGame = "gen3emerald" -- Emerald
        
        -- Remove Emerald's animations so they don't overlap.
        if baseGame == "gen3emerald" then
            extras.emeraldDeactivateTwoFrame={}
            extras.emeraldDeactivateSpriteAnims={}
            extras.emeraldDeactivateStatusScreenAnim={}
        end

        local hookFile = "ramanimator/data/pkmn-" .. baseGame .."-hooks"

        local hookmod = require(hookFile)
        local slots, hooks = table.unpack(hookmod)
        local anims = pkmn.getAnimations("gen3")

        return pkmn.finalizeLibrary(gameName, 3, slots, hooks, anims, extras)
    end
----------------
]]

printCode(code)

console:error("Please note:")
console:log([[The graphics in the game need to match the ones of the base game exactly, so hacks with custom sprites, even tiny alterations, won't work out of the box.]])

console:log("After saving the modified file, reset and reload all scripts.")

console:log("Done\n")
