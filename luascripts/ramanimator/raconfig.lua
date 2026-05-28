
--[[
To be considered immutable at runtime.
--]]

local raconfig = {}

raconfig.version = "1.0.0"
raconfig.logLevel = 0
raconfig.paletteWarningEmitted = false
raconfig.featureGbPalettes = emu and emu.writePalette and emu.readPalette
-- Sometimes, we might need to pass parameters to a hook generating
-- script. Since these take long to load, they are full on modules. We
-- thus pass parameters as global variables through this table.
raconfig.extras = {}

function raconfig.warnPalette()
  if emu:platform() == C.PLATFORM.GB then
    if not raconfig.paletteWarningEmitted then
      console:error("You are playing a Gameboy game on a version of mGBA that does not allow scripts to write to palettes. This means that all animations will appear in the colors that the original sprites have. If you want full color support, read the documentation online.")
    end
  else
    if not raconfig.paletteWarningEmitted then
      console:error("Your are playing a GBA game, but the parameter gbaPaletteAddresses was not provided in the extras. This might work for some games, but it is likely that animations will have the wrong colors. If this is intentional, provide the extra with value 0x5000000 instead to disable this warning.")
    end
  end

  raconfig.paletteWarningEmitted = true
end

return raconfig
