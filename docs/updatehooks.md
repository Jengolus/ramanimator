
# Update hooks

RAManimator looks for specific graphics on the screen. One of the most popular changes in ROM hacks is to improve these graphics, which unfortunately means that RAmanimator often won't recognize graphics even though they are off by only a few pixels. To fix this, it offers ways to update hooks.

> [!Important]
> Saving the updates to hooks requires you to have installed the [Python package](updatehooks.md). Please ensure that it works before proceeding.

## Prerequisites

Since you need to update hooks specifically for each hack, you first need to make a copy of the hook file you are using and refer RAManimator to it.

Look at the configuration code you generated when you set up the hack. It contains info about the `baseGame` the hack uses, which informs which hooks it expects. The hook file is contained in `luascripts/ramanimator/data` and should be named something like `pkmn-(baseGame)-hooks.lua`.

Copy it to something like `luascripts/myfiles/myhooks.lua`.

In the hack's setup, set the variable hookFile to that new path:

```diff
- local hookFile = "ramanimator/data/pkmn-" .. baseGame .."-hooks"
+ local hookFile = "myfiles/myhooks"

  local hookmod = require(hookFile)
```

where you need to drop the `.lua` at the end and put the name in quotes. Reload RAManimator. If there are any errors, you'll need to check where you put the hook file and whether you named everything correctly.

Proceeding with this how-to only makes sense if you currently have a sprite on screen in the game that should be animated, but isn't. Please make sure that it isn't animated because the hook is wrong, not simply because there is no animation for this sprite! You can find infos on which sprites are animated in the readme.

## With Aseprite

This requires the [Aseprite extension](aseextension.md)

Run `File -> RAManimator -> Update hook`. Select the correct slot and hook name. The animation, if it exists, should start now, but you still need to export your changes as described below.

## Without Aseprite

If it is the case that the sprite is animated but the hook is wrong, you also need to know its name. Aseprite will give you a list of available hooks in the GUI, so that is taken care of. If you don't use Aseprite, make sure the Python package works and type `ramanim getLibrary` in your command line. This prints a list of hooks available in the active game, marked with a `+` or `-` to indicate whether an animation is available for them. Just find the name of the hook you are looking for and copy it.

Next, open your command line and run `ramanim updateHook HOOKNAME`, where you need to replace `HOOKNAME` with the name you just found. The animation should automatically start, otherwise something went wrong. If that worked, you still need to save your changes.

## Save changes

From your command line, run `rasave`. This generates a file called `hooks.lua`. You can optionally pass the `--hooks` argument to change where that file goes.

For a Pokémon game, it will not be a full file, but only a list of the new hooks. Open the hook file (`myhooks.lua`) that you copied at the start of this how-to. The file mostly consists of a table that associates hook names with their corresponding graphics, encoded in some fancy way. You need to paste the new hooks to the end of that table without modifying any other lines:

```diff
  Some_Hook=rahooks.Hook:new("Some_Hook", ...),
+ Another_Hook=rahooks.Hook:new("Another_Hook", ...),
+ Updated_Hook=rahooks.Hook:new("Updated_Hook", ...),
  }

  return {slots, hooks}
```

Make sure that the last line before you added your own ends in a `,`.

If you are not working with a Pokémon game, `hooks.lua` should be a standalone file and you should be able to just overwrite the hook file you are using.

Reload RAManimator. If there are any errors, try to fix them. Otherwise, the new hooks should now work.

## Details

This approach sets the colors that are currently observed as the default (if the platform supports colors), i.e. you should only do this with default Pokémon sprites, not their shinies.

If you are playing a Gameboy Pokémon game and the sprite on screen is mirrored, replace the `Front` at the end of the hook name with `FrontM`.

In modern gen 3 games, this does not fix the two-frame animation. There isn't currently any way how to do this.

In modern gen 3 games, it can happen that the animation starts because the hook is the same, but the palette doesn't get updated because the hook's palette was slightly off. In that case, run `updateHookPalette` through the command line or `Update hook palette` in Aseprite. This also allows you to set shiny palettes by setting the palette index to 2.
