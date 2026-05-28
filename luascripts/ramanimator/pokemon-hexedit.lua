
--[[
To disable the games' native animations, these functions try to edit the
bytecode directly in a way that should work on as many games as possible.
--]]

local pkmn = {}

local base64 = require("base64")
local memory = require("memory")

local function patchRom(address, defCode, userCode, name, searchSequence, searchSeqMask, sequenceOffset, searchStart, searchLength)
  --[[
  address: If non-nil, do not search and just patch exactly here
  defCode: Default code to patch in
  userCode: If non-nil, overrides defCode
  name: For debug output
  searchSequence: The memory fingerprint to search for
  searchSeqMask: Which bytes to ignore in the search, e.g. because they
    contain addresses that change between ROMs.
  sequenceOffset: Once the fingerprint is found, the patch occurs at a
    position shifted by this value.
  searchStart: Where to place the search window for the fingerprint?
  seachLength: How wide is the search window?

  Note: If there is overlap between the fingerprint and the patched
  region, take care to mask it out and shift the fingerprint if you would
  overwrite its start, which cannot be masked.
  --]]

  -- Default
  local code = defCode
  if user then
    code = userCode
    console:log("Patching user-provided code (Base64)" .. base64.encode(code))
  end

  local userAddress = address ~= nil
  if not userAddress then
    -- Search in a delineated area
    if not searchSequence then
      console:log("Cannot perform patch " .. name .. " because no search fingerprint is provided!")
      return
    end

    local hits = {}

    if searchStart then
      if not searchLength then searchLength = 10 * #searchSequence end

      hits = memory.searchMemoryDomain(emu.memory.cart0, searchStart, searchStart + searchLength, searchSequence, searchSeqMask)
    end

    -- If unsuccessful, search the whole cartridge
    if #hits == 0 then
      if searchStart then
        console:log("Did not find the memory fingerprint for " .. name .. " in the provided search range, looking through whole cartridge.")
      end

      hits = memory.searchCart(searchSequence, searchSeqMask)
    end

    if #hits > 1 then
      console:log("Found memory fingerprint for " .. name .. " " .. tostring(#hits) .. " times; please provide the exact address to manipulate manually or provide a longer fingerprint!")

      return
    end

    if #hits == 0 then
      console:log("Could not find the memory fingerprint for " .. name ..  " anywhere; either it is already patched and the module just got reloaded or it seems the ROM was changed in an unexpected way.")
      
      return
    end

    address = hits[1] + sequenceOffset

    console:log("Found the memory fingerprint for " .. name .. ", patching at " .. string.format("%x", address) .. ".")
  end

  if userAddress then
    console:log("Patching " .. name .. " out at user provided address " .. string.format("%x", address))
  end

  for i = 1, #code do
    emu.memory.cart0:write8(address + i - 1, code:byte(i))
  end
end

function pkmn.patchCrystal(hints)
  --[[
  Crystal has its own animation system which we need to deactivate so it
  does not mess up anything. We do so by manipulating the functions that
  are responsible for deciding whether an animation is played. This first
  means that we need to find them on the cartridge, which might be tough.

  Specifically, we patch two things (with the names as in pokecrystal):
  For battles, make AnimateMon_CheckIfPokemon always fail, i.e. put
  scf; ret == 37 C9
  at cart0.0xd01c6

  StatsScreen_GetAnimationParam always behaves as in .FaintedFrzSleep,
  i.e. we put 
  xor a; ret == AF C9
  at cart0.0x4e2ad

  Now there are two avenues here: I want to look for the functions in
  memory and, once found, patch them. If they have been altered, I wish to
  allow for the user to just provide the exact addresses that need to be
  patched to work around that.
  --]]
  if type(hints) ~= "table" then
    hints = {}
  end

  -- Patch battle animations
  -- As provided, the patch is applied to part of the fingerprint, so we
  -- cut off these bytes the start.
  local battleSeq = base64.decode("+gjR/v0oB81BNzgCp8k3yQ==")
  -- We need to cut off two extra bytes because they differ between
  -- versions.
  battleSeq = string.sub(battleSeq, 5)
  local battleSeqMask = {}
  --for _, k in ipairs({2,3,9}) do battleSeqMask[k] = true end
  for _, k in ipairs({5}) do battleSeqMask[k] = true end
  -- Where this is in english Crystal
  local refBattleAddress = hints.refBattleAddress or 0xd01c6 + 4

  patchRom(hints.battlePatchAddress, string.char(0x37) .. string.char(0xc9), hints.battlePatchCode, "Crystal battle animations", battleSeq, battleSeqMask, -4, refBattleAddress - 0x200, 0x400)

  -- Patch status screen animations
  local statusSeq = base64.decode("+l/PIbVi78m/Ys9i0WLtYgFj+gnRId/cATAAzf4wRE0YI6/JISatATAA+gnRzf4wRE0+Ac3LL83yYvXN4S/xyQEO0RgA+gjR/v0oBc0/ZTgHrzfJPgGnya/J")
  statusSeq = string.sub(statusSeq, 3)
  local statusSeqMask = {}
  --local mask = {2, 5, 6, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 23, 29, 38, 44, 45, 47, 54, 57, 58, 61, 66, 67, 71, 72, 78, 79}
  local mask = {5, 6, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 23, 29, 38, 44, 45, 47, 54, 57, 58, 61, 66, 67, 71, 72, 78, 79}
  for _, k in ipairs(mask) do statusSeqMask[k - 2] = true end
  statusSeq = statusSeq:sub(1, 40)
  local refStatusAddress = hints.refStatusAddress or 0x4e2ad + 2
  patchRom(hints.statusPatchAddress, string.char(0xaf) .. string.char(0xc9), hints.statusPatchCode, "Crystal status screen animations", statusSeq, statusSeqMask, -2, refStatusAddress - 0x200, 0x400)
end

function pkmn.gbaDeactivateBounce(hints)
  --[[
  The own monsters have a bounce when selecting their moves, which clashes
  with the animations. We find the signature of the calls to
  DoBounceEffect (HP info and monster) and set the bounce amount of the
  monster to 0. The functions are called a few times in the code, but in
  my tests, it only found the correct pieces.

  Mainly, this needs to overwrite
  battle_player_controller.c:HandleInputChooseAction
  ]]--
  local bounceSeq = base64.decode("ASEHIgEj4vc++yB4ACEHIg==")
  local bounceSeqMask = {}
  for _, k in ipairs({7, 8, 9, 10}) do bounceSeqMask[k] = true end

  local hits = memory.searchMemoryDomain(emu.memory.cart0, 0x08010000, 0x08100000, bounceSeq, bounceSeqMask)

  for _, hit in ipairs(hits) do
    -- Set the monster's bounce amount to 0.
    emu.memory.cart0:write8(hit + 0x10, 0)
  end

  if #hits > 0 then
    console:log("Deactivated own monster's bounce in battles.")
  else
    console:error("Failed to deactivate own monster's bounce in battles. This just means that the sprites bounce up and down when you are selecting moves for the monsters. Fixing this is a good bit of work, but it's likely not a big problem.")
  end
end

function pkmn.emeraldDeactivateTwoFrame(hints)
  --[[
  Of course, we don't want emerald to place its own second frame in intro
  animations, so we patch it so the corresponding function always returns
  that there is only one frame.

  Specifically, we overwrite pokemon.c:HasTwoFramesAnimation to always
  return false by changing it to
  00 B5 00 20 02 BC 08 47 i.e.
  stmdb sp!, {lr}; mov R0, 0; ldmia sp!, {r1}; BX R1

  In Emerald EN, this happens at 0x0806f0d4
  ]]--
  local seq = base64.decode("ALUABAIMACEISIJCCtAZMIJCB9BmOIJCBNDJIVFASEIIQ8EPCBwCvAhHAACBAQAA")
  local seqMask = {}
  for _, k in ipairs({4, 6, 7, 8}) do seqMask[k] = true end

  local hits = memory.searchMemoryDomain(emu.memory.cart0, 0x08000000, 0x08100000, seq, seqMask)

  if #hits == 1 then
    console:log("Deactivated the second frame in monster animations.")
    local hit = hits[1]
    --print("At", string.format("%x", hit))
    emu.memory.cart0:write8(hit + 3, 0x20)
    emu.memory.cart0:write8(hit + 5, 0xBC)
    emu.memory.cart0:write8(hit + 6, 0x08)
    emu.memory.cart0:write8(hit + 7, 0x47)
  else
    console:error("Failed to deactivate the second frame in monster animations. This can happen e.g. when hacks add new monsters. Fixing this is probably quite a bit of work.")
  end
end

function pkmn.emeraldDeactivateSpriteAnims(hints)
  --[[
  We want to deactivate the animations of entering monsters in emerald.
  To this end, we make all of them use the dummy callback.

  Specifically, we overwrite pokemon_animation.c:Task_HandleMonAnimation
  to always assign the dummy callback, which is then automatically
  disposed off.
  The pointer to the callback is stored in R12 already when assigning the
  intended callback to R0, so we intervene in the association and put an
  mov r0, r12 (0x4660) right before the pointer is stored.

  In Emerald EN, this happens at 0x0817f4fa
  ]]--

  local seq = base64.decode("SRnJAEFEDiKIXoAAgBkAaNhhACA4YAiJATAIgdhp")
  local seqMask = {}
  for _, k in ipairs({15, 16}) do seqMask[k] = true end

  local hits = memory.searchMemoryDomain(emu.memory.cart0, 0x08100000, 0x08200000, seq, seqMask)

  if #hits == 1 then
    console:log("Deactivated the affine and movement parts of monster animations.")
    local hit = hits[1]
    --print("At", string.format("%x", hit))
    emu.memory.cart0:write8(hit + 14, 0x60)
    emu.memory.cart0:write8(hit + 15, 0x46)
  else
    console:error("Failed to deactivate the affine and movement parts of monster animations. Fixing this is probably quite a bit of work. Cause: " .. #hits .. " fingerprints found in memory.")
  end
end

function pkmn.emeraldDeactivateStatusScreenAnim(hints)
  --[[
  We want to deactivate the animations on the status screen, which we
  achieve by not calling the corresponding function in the first place.
  We override the call to it in SpriteCB_Pokemon with no-ops.

  The call consists of four bytes, which we replace by BF 00 BF 00

  In Emerald EN, this happens at 0x081C487A
  ]]--

  local seq = base64.decode("4Y0qeSAcqvYJ/DC8AbwAR+jLAwJ0fAMC")
  local seqMask = {}
  for _, k in ipairs({7, 8, 9, 10, 17, 18, 21, 22}) do seqMask[k] = true end

  local hits = memory.searchMemoryDomain(emu.memory.cart0, 0x08150000, 0x08250000, seq, seqMask)

  if #hits == 1 then
    console:log("Deactivated the animations on the status screen.")
    local hit = hits[1]
    --print("At", string.format("%x", hit))
    emu.memory.cart0:write8(hit + 6, 0xBF)
    emu.memory.cart0:write8(hit + 7, 0x00)
    emu.memory.cart0:write8(hit + 8, 0xBF)
    emu.memory.cart0:write8(hit + 9, 0x00)
  else
    console:error("Failed to deactivate the animations on the status screen. Fixing this is probably quite a bit of work. Cause: " .. #hits .. " fingerprints found in memory.")
  end
end

function pkmn.gbaFindPalettes(hints)
  --[[
  For Gen3 games, the palettes are actually stored somewhere in RAM and
  shaded every frame. So rather than editing the frames in the final
  palette, I need to find them in memory once on startup.

  That has the benefit that the shading works, though it's unfortunate for
  the simplicity.

  swapBufferOrder: With Emerald Expansion, the compiler sometimes swaps
  the order of gPlttBufferFaded and ...Unfaded. In that case, the fadeout
  at the start of a wild battle will glitch. Set the hint to one if that
  is observed.
  --]]
  if type(hints) ~= "table" then
    hints = {}
  end

  local palRam = emu.memory.palette
  local actualPalRam = palRam:readRange(0, palRam:size())

  local searchStart = hints.searchStart or 0x02037714 - 3 * #actualPalRam
  local searchLength = hints.searchLength or 6 * #actualPalRam

  local swapBufferOrder = -1

  if hints.swapBufferOrder then
    swapBufferOrder = 1
  end

  -- Do a quick search where it should be
  local hits = memory.searchMemoryDomain(emu, searchStart, searchStart + searchLength, actualPalRam)

  -- If we did not find them, widen the search
  if #hits == 0 then
    hits = memory.searchMemoryDomain(emu, emu.memory.wram:base(), emu.memory.wram:bound(), actualPalRam)
  end

  if #hits == 1 then
    -- This means we found the faded copy
    console:log("Found palettes at 0x" .. string.format("%x", hits[1] - 0x400) .. ".")
    return {hits[1] + 0x400 * swapBufferOrder, hits[1]}
  end

  if #hits == 2 then
    console:log("Found palettes at 0x" .. string.format("%x", hits[1]) .. ".")
    if hits[2] ~= hits[1] + 0x400 then
      console:error("But something is weird: The palettes were found twice, but their distance is 0x" .. string.format("%x", hits[2] - hits[1]) .. " instead of the expected 0x400.")
    end
    return {hits[1], hits[2]}
  end

  if #hits == 0 then
    console:error("Could not find color palettes! Go to a different scene, reset all scripts and try again. If the problem persists, there seems to be a deeper issue. In any case, most animations are likely to be unusable without writing to palettes.")
    return nil
  end

  console:error("Found too many potential color palettes! Go to a different scene, reset all scripts and try again. If the problem persists, there seems to be a deeper issue. In any case, most animations are likely to be unusable without writing to palettes.")

  return nil
end

function pkmn.rhhDeactivateBounce(hints)
  --[[
  The same as gbaDeactivateBounce, except it tries to find the code in
  emerald-expansion-derived games. The fingerprint is much less stable
  than for the official games, so we dare to be a lot more aggressive and
  warn the user.

  Mainly, this needs to overwrite
  battle_player_controller.c:HandleInputChooseAction

  Turns out this doesn't work in practice, the code is just too volatile.
  ]]--
  local bounceSeq = base64.decode("ASMp8Lb9ACMHIg==")
  local bounceSeqMask = {}
  for _, k in ipairs({3, 5, 6, 7}) do bounceSeqMask[k] = true end

  local hits = memory.searchMemoryDomain(emu.memory.cart0, 0x08010000, 0x08100000, bounceSeq, bounceSeqMask)

  for _, hit in ipairs(hits) do
    -- Set the monster's bounce amount to 0.
    emu.memory.cart0:write8(hit + 0x6, 0x0)
  end

  if #hits > 0 then
    console:log("Deactivated own monster's bounce in battles.")
  else
    console:error("Failed to deactivate own monster's bounce in battles. This just means that the sprites bounce up and down when you are selecting moves for the monsters. Fixing this is a good bit of work, but it's likely not a big problem.")
  end
end

return pkmn
