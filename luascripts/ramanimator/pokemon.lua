
--[[
The behavior for most Pokémon games is essentially the same, so this
collects everything.

This file will also contain the animators that handle monsters falling
asleep, feeling weak etc.
--]]

local pkmn = {}

local patcher = require("ramanimator/pokemon-hexedit")
local librarymod = require("ramanimator/library")
local Library = librarymod.Library

local players = require("ramanimator/pokemon-players")

function pkmn.getAnimations(targetSprites)
  --[[
  Given a key for a default set of animations, load all required
  modules. If you want to add a set of animations to all games of a
  generation, add them here. Otherwise, load them manually.
  --]]
  local animModuleNames = {}

  if targetSprites == "gen1" then
    animModuleNames = {
      "ramanimator/data/pkmn-gen1crystal-anims-back", 
      "ramanimator/data/pkmn-gen2crystal-anims-front",
      "ramanimator/data/jengolus-gen1rb-front",
      "ramanimator/data/jengolus-gen1crystal-back",
      "ramanimator/data/jengolus-gen1-trainers",
      "ramanimator/data/jengolus-gen1y-extras",
    }
  elseif targetSprites == "gen1fullcolor" then
    animModuleNames = {
      "ramanimator/data/pkmn-gen2crystal-anims-front",
      "ramanimator/data/jengolus-gen1crystal-back", -- The difference
    }
  elseif targetSprites == "gen2" then
    animModuleNames = {
      "ramanimator/data/pkmn-gen2crystal-anims-front",
      --"ramanimator/data/pkmn-gen2crystal-anims-back", -- These two just copy crystal sprites to GS
      --"ramanimator/data/pkmn-gen2crystal-anims-extra",
      "ramanimator/data/jengolus-gen2crystal-back", 
      "ramanimator/data/accad501-gen2-anims",
    }
  elseif targetSprites == "gen3" then
    -- Only up to gen3, no gender differences, megas etc
    animModuleNames = {
      "ramanimator/data/pkmn-gen3bw-anims-gen1",
      "ramanimator/data/pkmn-gen3bw-anims-gen2",
      "ramanimator/data/pkmn-gen3bw-anims-gen3",
      "ramanimator/data/pkmn-gen3-shadows", -- Opponent shadows
    }
  elseif targetSprites == "gen3ee" then
    -- Emerald expansion
    animModuleNames = {
      "ramanimator/data/pkmn-gen3bw-anims-gen1",
      "ramanimator/data/pkmn-gen3bw-anims-gen2",
      "ramanimator/data/pkmn-gen3bw-anims-gen3",
      "ramanimator/data/pkmn-gen3bw-anims-gen4",
      "ramanimator/data/pkmn-gen3bw-anims-gen5",
      "ramanimator/data/pkmn-gen3bw-anims-gens123-formes",
      "ramanimator/data/pkmn-gen3-shadows", -- Opponent shadows
    }
  elseif targetSprites == "gen3video" then
    -- For the video where every animation is displayed.
    animModuleNames = {
      "ramanimator/data/pkmn-gen3bw-anims-video",
      "ramanimator/data/pkmn-gen3-shadows",
    }
  elseif not targetSprites then
    console:log("No set of animations was requested.")
  else
    console:error("An unimplemented targetSprites key slipped into ramanimator/pokemon/getLibrary: " .. tostring(targetSprites))
    -- Might be intentional to start fresh
  end

  local anims = {}

  for _, path in ipairs(animModuleNames) do
    local mod = require(path)

    table.insert(anims, mod)
  end

  return anims
end

function gen1ResizeFrame(self, frame)
  --[[
  If a 6x6 tile (gen 2-sized) frame is provided, place it bottom-right.
  --]]
  if #frame ~= 6*6*8*8 then
    console:error("Trying to expand a gen1 back frame, but it contains " .. #frame .. " pixels, not the expected " .. 6*6*8*8 .. "!")
    return nil
  end

  local ret = ""

  for y = 1, 7*8 do
    for x = 1, 7*8 do
      if y < 9 or x < 9 then
        ret = ret .. string.char(0)
      else
        local index = 6 * 8 * (y - 8 - 1) + (x - 8)
        ret = ret .. string.sub(frame, index, index)
      end
    end
  end

  return ret
end

function pkmn.getLibrary(name, generation, romSprites, targetSprites, extras)
  --[[
  This resolves the shortcuts that can be used with the individual games.

  romSprites: Which sprites are expected on the ROM and to be used as
  hooks?
  targetSprites: Which sprites should be loaded?
  extras: Flags for special behavior, e.g. patching the code to
  deactivate animations in Crystal and Emerald.
  --]]
  console:log("Generating a RAManimator library for a Pokémon game: " .. tostring(name))

  local slots = {}
  local hooks = {}
  local pack = nil

  if romSprites == "gen1rb" then
    pack = require("ramanimator/data/pkmn-gen1rb-hooks")
  elseif romSprites == "gen1rg" then
    pack = require("ramanimator/data/pkmn-gen1rg-hooks")
  elseif romSprites == "gen1y" then
    pack = require("ramanimator/data/pkmn-gen1y-hooks")

  elseif romSprites == "gen2gold" then
    pack = require("ramanimator/data/pkmn-gen2gold-hooks")
  elseif romSprites == "gen2silver" then
    pack = require("ramanimator/data/pkmn-gen2silver-hooks")
  elseif romSprites == "gen2crystal" then
    pack = require("ramanimator/data/pkmn-gen2crystal-hooks")
  elseif romSprites == "gen2jpgold" then
    pack = require("ramanimator/data/pkmn-gen2jpgold-hooks")
  elseif romSprites == "gen2jpsilver" then
    pack = require("ramanimator/data/pkmn-gen2jpsilver-hooks")
  elseif romSprites == "gen2jpcrystal" then
    pack = require("ramanimator/data/pkmn-gen2jpcrystal-hooks")
  elseif romSprites == "gen1gold" then
    pack = require("ramanimator/data/pkmn-gen1gold-hooks")
  elseif romSprites == "gen1silver" then
    pack = require("ramanimator/data/pkmn-gen1silver-hooks")
  elseif romSprites == "gen1crystal" then
    pack = require("ramanimator/data/pkmn-gen1crystal-hooks")

  elseif romSprites == "gen3rs" then
    pack = require("ramanimator/data/pkmn-gen3rs-hooks")
  elseif romSprites == "gen3frlg" then
    pack = require("ramanimator/data/pkmn-gen3frlg-hooks")
  elseif romSprites == "gen3emerald" then
    pack = require("ramanimator/data/pkmn-gen3emerald-hooks")

  elseif romSprites ~= nil and romSprites:sub(1, #"emeraldexpansion") == "emeraldexpansion" then
    pack = require("ramanimator/data/rhh-" .. romSprites .. "-hooks")

  else
    console:error("An unimplemented romSprites key slipped into ramanimator/pokemon.getLibrary: " .. tostring(romSprites))
  end
  
  if pack ~= nil then
    slots, hooks = table.unpack(pack)
  end

  local anims = pkmn.getAnimations(targetSprites)

  return pkmn.finalizeLibrary(name, generation, slots, hooks, anims, extras)
end

function pkmn.finalizeLibrary(name, generation, slots, hooks, anims, extras)
  --[[
  Does some final adjustments that are specific to Pokemon because some
  things cannot be properly serialized.
  --]]
  if extras == nil then
    extras = {}
  end

  if extras.patchCrystal then
    patcher.patchCrystal(extras.patchCrystal)
  end

  if extras.gbaFindPalettes then
    extras.gbaPaletteAddresses = patcher.gbaFindPalettes(extras.gbaFindPalettes)
  end

  if extras.gbaDeactivateBounce then
    patcher.gbaDeactivateBounce(extras.gbaDeactivateBounce)
  end

  if extras.emeraldDeactivateTwoFrame then
    patcher.emeraldDeactivateTwoFrame(extras.emeraldDeactivateTwoFrame)
  end

  if extras.emeraldDeactivateSpriteAnims then
    patcher.emeraldDeactivateSpriteAnims(extras.emeraldDeactivateSpriteAnims)
  end

  if extras.emeraldDeactivateStatusScreenAnim then
    patcher.emeraldDeactivateStatusScreenAnim(extras.emeraldDeactivateStatusScreenAnim)
  end

  if extras.rhhDeactivateBounce then
    patcher.rhhDeactivateBounce(extras.rhhDeactivateBounce)
  end

  if slots ~= nil then
    -- Add the special AnimPlayers
    for name, slot in pairs(slots) do
      if not slot.subSlots then
        slot.subSlots = {}
      end

      for name, slot in pairs(slot.subSlots) do
        -- Forwarded to the subSlots' hooks
        slot.playerClass = players[slot.player]
      end

      -- In gen2, back sprites are 6x6 tiles, but 7x7 in gen1. This adds
      -- a converter to the gen1 slot so the gen2 files can be loaded
      -- into gen1 games via the server.
      if generation == 1 and slot.name == "Back" then
        slot.resizeFrame = gen1ResizeFrame
      end
    end
  end

  if hooks ~= nil then
    -- Add the special AnimPlayers
    for hookName, hook in pairs(hooks) do
      hook.playerClass = players[hook.playerClass]

      -- This one game has a green tint to the background color
      if name == "POKEMON GREEN (JAP)" and hook.palettes then
        for _, pal in pairs(hook.palettes) do
          pal[1] = 30718
        end
      end
    end
  end

  extras.isPkmnLib = true

  return Library:new(name, slots, hooks, extras, table.unpack(anims))
end

return pkmn
