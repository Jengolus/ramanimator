
# Set up a Pokémon ROM hack

There is a vast gamut of ROM hacks and it is impossible to predict everything. RAManimator makes an effort to accomodate as many of them as possible with minimal friction, but most hacks require a bit of setup.

This file describes how to set up hacks in the first place; if the hack changes graphics, you will need to change those according to the next how-to.

If you load an "old" hack (not a decompilation), there is a good chance it will be recognized automatically and just work. In some cases, a modern hack might get recognized as "normal" Emerald, in which case a number of red error messages will be printed; if so, you can just proceed with the below steps.

Please understand: Compatibility depends entirely on whether the graphics of a hack match those that RAManimator expects. A single changed pixel will make it not recognize a sprite, and I found that many hacks like to add a lot of minute changes, strongly limiting their compatibility. This does not only go for modern gen 3 hacks, but also colorized gen 1 variants.

## Generate the config
When you load the hack, RAManimator will print some info in the `Scripting` window. If it redirects you to a Pokémon setup script, you will find that script in the `luascripts` folder in your RAManimator directory. In the scripting window, just run it via `File -> Load script`. For gen 3, choose "modern" gen 3 if the hack is a decompilation. These usually feature a "pret x RHH" intro animation when you load the ROM. Otherwise, choose "classic" gen 3.

These scripts should provide you with a few lines of code. You will need to paste them into the RAManimator files. Specifically, go to your RAManimator directory in your file explorer, then open `luascripts/ramanimator/identify-checksum.lua` in your favourite text editor. Please be careful within this file; breaking something will make RAManimator unable to start, in which case you can always replace the file with the one in the Github repo to reset.

All you need to do is paste the config code into the middle of getLibrary() like so:
```diff
function idchecksum.getLibrary()
  -- Just hard-code checksums here
  local checksum = base64.encode(emu:checksum())
  local name = emu:getGameTitle()
  
+ if checksum == "0l+8zA==" and name == "TMT2" then
+   local gameName = "Third generation game"
+   ...
+   return pkmn.finalizeLibrary(gameName, 3, slots, hooks, anims, extras)
+ end

  -- Nothing identified
  return nil
end
```

and read the other printed instructions.

## Everything except modern gen 3
There is only very little else you need to do for most games, other than selecting the base game. For example, if you want to add a gen1 hack (without full color support), your changes would look something like this:

```diff
    if checksum == "NQue6g==" and name == "POKEMON BLU" then
        -- Add the game's name inside the ""
-       local gameName = "First generation game"
+       local gameName = "Cool hack"

        local pkmn = require("ramanimator/pokemon")

        -- Remove the -- in front of the correct base game,
        -- remove all other lines
-       --local baseGame = "gen1rg" -- Japanese Red & Green
-       --local baseGame = "gen1rb" -- Red & Blue
+       local baseGame = "gen1rb" -- Red & Blue
-       --local baseGame = "gen1y" -- Yellow

        local hookFile = "pkmn-" .. baseGame .."-hooks"

        local hookmod = require("ramanimator/data/" .. hookFile)
        local slots, hooks = table.unpack(hookmod)
        local anims = pkmn.getAnimations("gen1")

        return pkmn.finalizeLibrary(gameName, 1, slots, hooks, anims, extras)
    end
```

Gen 1 games with full color support will normally be recognized as gen 2 games. There are special `baseGame` entries for this case.

As long as the hack only uses graphics from one base game, you should be good to go!

## Modern gen 3 hacks
There is an infinite sea of hacks and unfortunately, their setup is a bit more complicated because of that. Still, RAManimator aims to make the process as seamless as possible.

After pasting the code as instructed above, save the file, reset the scripts in mGBA and reload `startup.lua`. If you encounter a small monster of gen 5 or earlier, it should now be animated if the game uses precisely the graphic that is stored as a hook. However, the game still tries to play its own intro animations for the monster, which leads to graphical glitches we need to address.

Before that, go into a battle with an animated monster. Open the bag or status screen. While the screen fades to black, do the colors of the sprite get messed up for a moment? If so, change the following line in the pasted setup:

```diff
        local extras = {
-           gbaFindPalettes={swapBufferOrder=false},
+           gbaFindPalettes={swapBufferOrder=true},
        }
```

Save, reset and reload the scripts. Fades should now get animated properly.

When you open the status screen of an animated monster, its sprite will glitch because the game loads its old animation sprite which doesn't work with the new animation's palette. To fix this, re-run the setup script. Its output should be identical to the first run, except that the line starting with 
```lua
raconfig.extras.rhhHookExtras
```
should now contain an additional entry. Copy it to the setup, replacing the original line. After reloading the scripts, move back to the status screen where the problem should now be fixed.

The same problem occurs on the evolution screen. Once that happens, just execute the setup script again and copy the line with the `rhhHookExtras`.
