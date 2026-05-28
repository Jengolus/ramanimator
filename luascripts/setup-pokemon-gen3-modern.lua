
--[[
With generation 3 games derived from Emerald Expansion, there is too much
stuff going on for me to predict everything, so the user inevitably needs
to do some things themselves. This file should try to automate most of
that.

This file is top-level because it is meant to be loaded by itself.
--]]

console:log("")
console:log("Tool to configure modern generation 3 games and fix issues due to the second frames in monster animations")

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
local ramanimator = require("ramanimator/ramanimator")
local raconfig = require("ramanimator/raconfig")

local lib = ramanimator.library

local function printCode(code, extra, swapBufferOrder)
  console:log("Add the following block to ramanimator/identify-checksum.lua. If you already added one for this game, copy only the changed lines. Stretch this scripting window to be so wide that all lines fit without wrapping around before copying. Do not copy the ---------")

  local checksum = base64.encode(emu:checksum())
  local name = emu:getGameTitle()
  if swapBufferOrder == true then
    swapBufferOrder = "true"
  else
    swapBufferOrder = "false"
  end

  console:log(string.format(code, checksum, name, extra, swapBufferOrder))
end

local code = [[
----------------
    if checksum == "%s" and name == "%s" then
        -- Add the game's name inside the ""
        local gameName = "Modern third generation game"

        local pkmn = require("ramanimator/pokemon")

        %s

        local extras = {
            gbaFindPalettes={swapBufferOrder=%s},
        }

        local hookFile = "ramanimator/data/rhh-emeraldexpansion-1-15-hooks"

        local hookmod = require(hookFile)
        local slots, hooks = table.unpack(hookmod)
        local anims = pkmn.getAnimations("gen3ee")

        return pkmn.finalizeLibrary(gameName, 3, slots, hooks, anims, extras)
    end
----------------
]]

if lib == nil or lib.name == "Unnamed" then
  console:error("Currently, no game is recognized.")
  printCode(code, "raconfig.extras.rhhHookExtras = {}")
  return
end

local function findRamTwin(title, slotName, addrName, sceneName)
  --[[
  The monster sprites are stored in VRAM, but there is also a copy in RAM.
  We need to know its address. If we know the address for the first player
  slot, we can infer the other sprites' addresses from there.
  --]]
  console:log(title)
  -- Find the SpriteSlot of that name
  local slot = lib.slots[slotName]
  if slot == nil then
    console:log("It seems the library does not contain a " .. slotName .. " slot, which is unexpected.")
    return
  end
  -- If RAManimator is loaded from here, this hasn't been called yet.
  slot:scanSprites(lib)

  local tileSlot = lib.slots[slotName .. "-Sprite"]
  if tileSlot == nil then
    console:log("Could not find a " .. slotName .. " sprite on screen. If you are looking for the " .. addrName .. ", try again from the " .. sceneName .. ".")
    return
  end

  -- Load the trigger, then search for it in RAM
  local trigger = tileSlot:read()
  local player = lib.slotGroups[tileSlot.groupKey].player
  if player ~= nil and player.active and player.slot == tileSlot then
    -- If the animation is running, take its trigger directly
    trigger = player.anim.hook.trigger
    print("Found a running animation.")
  end
  print(player, player and player.active, player and player.slot.name)

  local domain = emu.memory.wram

  local hits = memory.searchMemoryDomain(domain, domain:base(), domain:bound() - 1, trigger)

  if #hits == 1 then
    --console:log(string.format("Found one match for the RAM twin at 0x%x. Use it for raconfig.extras.rhhHookExtras.%s.", hits[1], addrName))
    return hits[1]
  elseif #hits == 0 then
    console:log("Did not find the " .. slotName .. " sprite at another offset in memory. This is weird, you may try again from a different scene.")
  else
    console:log("Found too many copies of the " .. slotName .. " sprite in memory. You can try them out individually. The below output will contain the first, which you can replace with the following if it doesn't work:")
    for _, hit in ipairs(hits) do
      console:log(string.format("0x%x", hit))
    end
    return hits[1]
  end
end

-- We expect the user always looks for this one first.
local extras = raconfig.extras.rhhHookExtras
local ramTwinAddr = extras and extras.ramTwinAddress

local outExtras = ""

if ramTwinAddr == nil then
  ramTwinAddr = findRamTwin("In-battle sprites", "Back", "ramTwinAddress", "main menu of a battle")
  if ramTwinAddr == nil then
    -- This should catch the case when this was recognized as normal
    -- Emerald.
    printCode(code, "raconfig.extras.rhhHookExtras = {}")
    console:log("It seems this is the initial setup for this ROM. Please follow the tutorial for setting up modern gen 3 hacks online to remove graphical glitches.")
    return
  end
  console:log([[It seems this is the secondary setup for this ROM. You are going to observe graphical glitches on the monster status screen and during evolution scenes. When you get there, run this script again to generate additional setup information.]])
else
  console:log("The config for the game already contains an address for the battle screen, skipping the search for it.")

  local statusScreenTwinAddr = extras and extras.statusScreenTwinAddress
  if statusScreenTwinAddr == nil then
    statusScreenTwinAddr = findRamTwin("Status screen", "Front2", "statusScreenTwinAddress", "status screen")
  else
    console:log("You already have an address for the status screen, skipping the search for it.")
  end

  if statusScreenTwinAddr ~= nil then
    outExtras = outExtras .. string.format(", statusScreenTwinAddress=0x%x", statusScreenTwinAddr)
  end

  local evolutionScreenAddr = extras and extras.evolutionScreenAddress
  if evolutionScreenAddr == nil then
    evolutionScreenAddr = findRamTwin("Evolution animation", "Dex2", "evolutionTwinAddress", "end of an evolution scene")
  else
    console:log("You already have an address for the status screen, skipping the search for it.")
  end

  if evolutionScreenAddr ~= nil then
    outExtras = outExtras .. string.format(", evolutionScreenAddress=0x%x", evolutionScreenAddr)
  end
end

local outLine = string.format("raconfig.extras.rhhHookExtras = {ramTwinAddress=0x%x", ramTwinAddr)
outLine = outLine .. outExtras ..  "}"

printCode(code, outLine, lib.extras and lib.extras.gbaFindPalettes and lib.extras.gbaFindPalettes.swapBufferOrder)

console:log("If you get weird colors when the screen darkens / brightens, e.g. when opening the bag during a battle or when a wild monster slides onto the screen: In the above code, change\nswapBufferOrder=false\nto\nswapBufferOrder=true")

console:error("Please note:")
console:log([[The graphics in the game need to match the ones of the base game exactly, so hacks with custom sprites, even tiny alterations, cannot be animated. Modern Emerald hacks are extremely varied, so it is impossible this works 100 %.]])
console:log("After saving the modified file, reset and reload all scripts.")
console:log("Done\n")
