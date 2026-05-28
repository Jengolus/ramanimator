
--[[
Module to check whether a Pokémon game is played and load the correct
animation library in that case.

The identification code is used from yPokeStats, distributed under an Unlicense license, see below.
--]]

local pokemonidentify = {}

local games = {}

local function identifySprites(generation, version, language)
    -- Map the sprites on the cartridge to those for which we have
    -- animations.
    -- For now, I don't have anything, actually.

    local romSprites = nil
    local targetSprites = nil

    if generation == 1 then
        targetSprites = "gen1"

        -- Exclude japanese RG
        if (version == "POKEMON GREE" or version == "POKEMON RED")
            and language == "J" then
            romSprites = "gen1rg"
        elseif version == "POKEMON BLUE" or version == "POKEMON RED" then
            romSprites = "gen1rb"
        elseif version == "POKEMON YELL" then
            romSprites = "gen1y"
        else
            console:error("Found a generation 1 game, but couldn't identify which sprites it contains: " .. version)
        end
    elseif generation == 2 then
        targetSprites = "gen2"

        romSprites = "gen2"

        if language == "J" then
            romSprites = romSprites .. "jp"
        end

        if version == "POKEMON_GLDA" then
            romSprites = romSprites .. "gold"
        elseif version == "POKEMON_SLVA" then
            romSprites = romSprites .. "silver"
        elseif version == "PM_CRYSTALB" then
            romSprites = romSprites .. "crystal"
        else
            console:error("Found a generation 2 game, but couldn't identify which sprites it contains: " .. version)
        end
    elseif generation == 3 then
        targetSprites = "gen3"

        romSprites = "gen3"

        if version == "POKEMON RUBY" or version == "POKEMON SAPP" then
            romSprites = romSprites .. "rs"
        elseif version == "POKEMON FIRE" or version == "POKEMON LEAF" then
            romSprites = romSprites .. "frlg"
        elseif version == "POKEMON EMER" then
            romSprites = romSprites .. "emerald"
        else
            console:error("Found a generation 3 game, but couldn't identify which sprites it contains: " .. version)
        end
    end

    return romSprites, targetSprites
end

local function redirectToSetup()
    console:log("The game was recognized as a Pokémon game, but not fully.")
    if emu:platform() == C.PLATFORM.GB then
        console:log("Run setup-pokemon-gen1or2.lua in the scripts directory to generate its configuration.")
    elseif emu:platform() == C.PLATFORM.GB then
        console:log("Run setup-pokemon-gen3-classic.lua or setup-pokemon-gen3-modern.lua in the scripts directory to generate its configuration.")
    else
        console:log("But its generation wasn't.")
    end
end

function pokemonidentify.getLibrary(gamedata)
    -- Return an animation library.
    local gamedata = pokemonidentify.identify()
    if gamedata == nil then
        return nil
    end

    -- Do I know this cartridge?
    local version    = gamedata[1]
    local language   = gamedata[2]
    local generation = gamedata[3]

    if version == 0 and language == 0 and generation == 0 then
        -- Does not seem to be a Pokémon game at all.
        return
    end

    if string.sub(version, 1, 10) == "PM_CRYSTAL" then
        -- As observed for French crystal
        version = "PM_CRYSTALB"
    elseif string.sub(version, 1, 11) == "POKEMON RED" then
        version = "POKEMON RED"
    end

    --console:log("ramanimator found a Pokémon game: Generation " .. tostring(generation) .. ", '" .. tostring(version) .. "', language " .. tostring(language))

    if games[version] == nil then
        -- This branch should be unreachable.
        --console:log("This game isn't supported. Is it a hackrom? It might work but you'll have to add it yourself. Check identify-pokemon.lua and the yPokeStats documentation.")
        -- The outside script will redirect the user to the setup scripts.
        return nil
    end

    local romSprites, targetSprites = identifySprites(generation, version, language)

    if romSprites == nil or targetSprites == nil then
        redirectToSetup()
        return
    end

    local offsets = nil
    -- I originally planned to use the offsets to detect HP changes and
    -- status conditions, but now read that from the screen since I assume
    -- it is easier to maintain for a user.
    local name = nil

    -- Finally, get the offsets for extra functionality.
    if games[version][language] == nil then
        console:log("This game is known, but not this version / language. Animations should mostly work, but some extra features probably won't.")
        console:log("You can always use the corresponding setup scripts in the script directory to generate its full configuration.")
        name = "Unknown variant of " .. tostring(version)
    else
        local romData = games[version][language]
        offsets = {party=romData[2], oppParty=romData[3], strctLen=romData[4]}
        name = romData[1]
    end

    local extras = {}

    if version == "PM_CRYSTALB" then
        --extras["patchCrystal"] = {battlePatchAddress=0xd01c6, statusPatchAddress=0x4e2ad}
        extras["patchCrystal"] = {}
    end

    if generation == 3 then
        -- Just provide anything, these aren't flexibilized.
        extras["gbaFindPalettes"] = {}
        extras["gbaDeactivateBounce"] = {}
    end

    if version == "POKEMON EMER" then
        extras["emeraldDeactivateTwoFrame"] = {}
        extras["emeraldDeactivateSpriteAnims"] = {}
        extras["emeraldDeactivateStatusScreenAnim"] = {}
    end

    -- Defer to the general pokemon module to do the mix and match.
    local pkmn = require("ramanimator/pokemon")
    return pkmn.getLibrary(name, generation, romSprites, targetSprites, extras)
end

--[[
The below code was published by Roman Servais (yling)
for yPokeStats (distributed under an Unlicense license), adapted to mGBA.
https://github.com/yling/yPokeStats
See that repo for an explanation.
The repo also contains data for gens 4 and 5 not included here because
mGBA doesn't support that.
]]--

games["POKEMON RED"],games["POKEMON BLUE"],games["POKEMON YELL"],games["POKEMON GREE"]={},{},{},{}
games["POKEMON_GLDA"],games["POKEMON_SLVA"],games["PM_CRYSTALB"]={},{},{}
games["POKEMON RUBY"],games["POKEMON SAPP"],games["POKEMON EMER"],games["POKEMON FIRE"],games["POKEMON LEAF"]={},{},{},{},{},{} -- Gen 3

-- These are used to identify gen 1 & 2 games
games["lan"]={}
games["lan"][1]={}
games["lan"][2]={}
games["lan"][1]["J"]={0xc1a2,0x36dc,0xd5dd,0x299c,0x47F5} -- JAP gen 1
games["lan"][1]["E"]={0xe691,0xa9d,0x7c04} -- US gen 1
games["lan"][1]["F"]={0xd289,0x9c5e,0xdc5c,0x4a38,0xd714,0xfc7a,0xa456,0x8f4e,0xfb66,0x3756,0xc1b7, 0xbc2e} -- PAL gen 1

games["lan"][2]["J"]={0x409A,0x341D,0x708A} -- JAP gen 2
games["lan"][2]["E"]={0xAE0D,0xD218,0x2D68} -- US gen 2
games["lan"][2]["F"]={0xC66F,0xE2F2,0x5073,0x97DC,0x8249,0x6ECD,0xF442,0x5393,0x4B06,0x8CFB,0xBADB,0x0CCE} -- PAL gen 2

-- The game data is: Display name, player team offset, enemy team offset,
-- Monster structure length.

-- Gen 1
games["POKEMON GREE"]["J"]={"Pokemon Green (JAP)",0xD12B,0xCFCC,44} -- OK
games["POKEMON RED"]["J"]={"Pokemon Red (JAP)",0xD12B,0xCFCC,44} -- OK

games["POKEMON RED"]["F"]={"Pokemon Red (PAL)",0xD170,0xCFEA,44} -- OK
games["POKEMON RED"]["E"]={"Pokemon Red (US)",0xD16B,0xCFE5,44} -- OK

games["POKEMON BLUE"]["F"]={"Pokemon Blue (PAL)",0xD170,0xCFEA,44} -- OK
games["POKEMON BLUE"]["E"]={"Pokemon Blue (US)",0xD16B,0xCFE5,44} -- OK
games["POKEMON BLUE"]["J"]={"Pokemon Blue (JAP)",0xD12B,0xCFCC,44} -- OK

games["POKEMON YELL"]["F"]={"Pokemon Yellow (PAL)",0xD16F,0xCFE9,44} -- OK
games["POKEMON YELL"]["E"]={"Pokemon Yellow (US)",0xD16A,0xCFE4,44} -- OK
games["POKEMON YELL"]["J"]={"Pokemon Yellow (JAP)",0xD12B,0xCFCC,44} -- OK

-- Gen 2
games["POKEMON_GLDA"]["F"]={"Pokemon Gold (PAL)", 0xDA2A,0xD0EF,48} -- OK
games["POKEMON_GLDA"]["E"]={"Pokemon Gold (US)", 0xDA2A,0xD0EF,48} -- OK
games["POKEMON_GLDA"]["J"]={"Pokemon Gold (JAP)",0xD9F0,0xD0E1,48} -- OK

games["POKEMON_SLVA"]["F"]={"Pokemon Silver (PAL)",0xDA2A,0xD0EF,48} -- OK
games["POKEMON_SLVA"]["E"]={"Pokemon Silver (US)",0xDA2A,0xD0EF,48} -- OK
games["POKEMON_SLVA"]["J"]={"Pokemon Silver (JAP)",0xD9F0,0xD0E1,48} -- OK

games["PM_CRYSTALB"]["E"]={"Pokemon Crystal 1.1 (US)",0xDCDF,0xD206,48} -- OK
games["PM_CRYSTALB"]["F"]={"Pokemon Crystal 1.1 (PAL)",0xDCDF,0xD206,48} -- OK
games["PM_CRYSTALB"]["J"]={"Pokemon Crystal 1.1 (JAP)",0xDCA5,0xD237,48} -- OK

-- Gen 3
games["POKEMON RUBY"]["E"]={"Pokemon Ruby (US)",0x03004360,0x30045C0,100} -- RUBY US - OK
games["POKEMON RUBY"]["F"]={"Pokemon Ruby (PAL)",0x03004370,0x30045D0,100} -- RUBY FR - OK
games["POKEMON RUBY"]["J"]={"Pokemon Ruby (JAP)",0x3004290,0x30044F0,100} -- RUBY J -- OK

games["POKEMON SAPP"]["E"]={"Pokemon Sapphire (US)",0x03004360,0x30045C0,100} -- SAPPHIRE US - OK
games["POKEMON SAPP"]["F"]={"Pokemon Sapphire (PAL)",0x03004370,0x30045D0,100} -- SAPPHIRE FR - OK
games["POKEMON SAPP"]["J"]={"Pokemon Sapphire (JAP)",0x3004290,0x30044F0,100} -- SAPPHIRE J -- OK

games["POKEMON EMER"]["E"]={"Pokemon Emerald (US)",0x20244EC,0x2024744,100} -- EMERALD US - OK
games["POKEMON EMER"]["F"]={"Pokemon Emerald (PAL)",0x20244EC,0x2024744,100} -- EMERALD FR - OK
games["POKEMON EMER"]["J"]={"Pokemon Emerald (JAP)",0x2024190,0x20242E8,100} -- EMERALD -- OK

games["POKEMON FIRE"]["E"]={"Pokemon Fire Red (US)",0x02024284,0x0202402C,100} -- FIRE RED US - OK
games["POKEMON FIRE"]["F"]={"Pokemon Fire Red (PAL)",0x02024284,0x0202402C,100} -- FIRE RED FR - OK
games["POKEMON FIRE"]["J"]={"Pokemon Fire Red (JAP)",0x20241E4,0x2023F8C,100} -- FIRE RED JAP - OK

games["POKEMON LEAF"]["E"]={"Pokemon Leaf Green (US)",0x02024284,0x0202402C,100} -- LEAF GREEN US - OK
games["POKEMON LEAF"]["F"]={"Pokemon Leaf Green (PAL)",0x02024284,0x0202402C,100} -- LEAF GREEN US - OK
games["POKEMON LEAF"]["J"]={"Pokemon Leaf Green (JAP)",0x20241E4,0x2023F8C,100} -- LEAF GREEN JAP - OK

local function hasValue(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

function pokemonidentify.identify() -- Reads game memory to determine which game is running
    local version, lan, gen
    if string.find(emu:readRange(0x0134, 12), "POKEMON") or string.find(emu:readRange(0x0134, 12), "PM") then
        version = emu:readRange(0x0134, 12)
        lan = emu:read16(0x014E)
        regions = {"J","E","F"}

        for i=1,2 do -- Finds the proper region and gen
            for j=1,#regions do
                if hasValue(games["lan"][i][regions[j]], lan) then
                    gen = i
                    lan = regions[j]
                end
            end
        end
    elseif string.find(emu:readRange(0x080000A0, 12), "POKEMON") or string.find(emu:readRange(0x080000A0, 4), "PKMN") then
        version = emu:readRange(0x080000A0, 12)
        lan = string.char(emu:read8(0x080000AF))
        gen = 3
    else	
        version = 0
        lan = 0
        gen = 0
    end
    -- I think all PAL regions use the same adresses. Here's the dirty hack to make them all work
    if lan == "H" or lan == "I" or lan =="S" or lan == "X" or lan == "Y" or lan == "Z" then
        lan = "F"
    end

    return {version, lan, gen}
end

return pokemonidentify
