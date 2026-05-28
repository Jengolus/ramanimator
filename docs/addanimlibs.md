
# Add animation libraries

Users might like to share animations they produce. These can be added in two ways.

## Add to a generation

To add an animation file to all games of a generation, just copy the animation file, let's call it `myanimations.lua`, to the `myfiles` directory in your RAManimator folder. Then go to `luascripts/ramanimator/pokemon.lua`. Near the top, there is a function called `getAnimations`. It contains lists of all animation files that are automatically loaded for a given generation. Find the generation you are looking for and add it to the list like so, putting the correct path and dropping the `.lua` at the end of the file name. Also add a comma afterwards. Do not forget the quotation marks.

```diff
 animModuleNames = {
   "ramanimator/data/pkmn-gen2crystal-anims-front",
   "ramanimator/data/pkmn-gen2crystal-anims-back",
   "ramanimator/data/pkmn-gen2crystal-anims-extra",
   "ramanimator/data/jengolus-gen2crystal-back", 
+  "myfiles/myanimations",
 }
```

Once you load an unmoddified game or one that loads the default animations, your new ones should work as well.

## Add to a specific game

To add an animation file to a specific game, just copy the animation file, let's call it `myanimations.lua`, to the `myfiles` directory in your RAManimator folder. Then go to the setup of the hack for which the animations are and add the following line shortly before the end:

```diff
    ...
    local anims = pkmn.getAnimations("gen3ee")

+   anims[#anims + 1] = (require("myfiles/myanimations"))

    return pkmn.finalizeLibrary(gameName, 3, slots, hooks, anims, extras)
  end
end
```

Note that the `.lua` at the end of the file name needs to be dropped here!
