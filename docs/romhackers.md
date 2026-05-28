
# Notes to ROM hackers

While RAManimator tries to make adapting it to hacks as convenient as possible, you can change a few simple things about your hack to make it easier for ramanimator to do so.

## Generate hook files

There is a [separate Git repository](https://www.github.com/Jengolus/ramanimator-tools) that contains the scripts that I used to generate the games' hook files from their pret repositories. While you will most likely need to adept them a bit, this should be quick and save users from updating hooks themselves, which is unfortunately rather cumbersome.

## Write the config

When users set up RAManimator to recognize a new hack, they need to paste a few lines of code into their RAManimator source. It would be great if you could just give them those lines directly with the hack so the hurdle is lessened.

## Deactivate native animations

Crystal and gen 3 games have their own animations, which can cause major problems when they overlap with the new ones. While RAManimator tries to modify the bytecode in memory for binary hacks, this might not always work and is hopeless for modern Emerald, so it would be very helpful if you could just make a few changes to the source yourself. Of course, these have the side effect of deactivating the animations for users without RAManimator, which is unfortunate.

### Crystal

In `pokecrystal/engine/gfx/pic_animation.asm`, find `AnimateMon_CheckIfPokemon`. Make it always fail, i.e. replace its body with `scf; ret`. This deactivates animations in battles.

In `pokecrystal/engine/pokemon/stats_screen.asm`, find `StatsScreen_GetAnimationParam`. Make it always behave as if the monster was `FaintedFrzSlp`, i.e. replace its body with `xor a; ret`. That deactivates the animation on the status screen.

There are probably other solutions; these are just the ones I found that can be binary-hacked.

Since you deactivated the animations, in the game setup, remove `extras.pachCrystal = true` and surrounding clutter. That should be it.

### All of gen 3

All gen 3 games have the bounce effect, where the monster for which you are selecting a move bounces up and down a bit. That looks weird with actual animations on.

In `/src/battle_player_controller.c:HandleInputChooseAction`, find the call to `DoBounceEffect` with parameter `BOUNCE_MON`. Replace the final `1` with a `0`. You can also change the calls to `DoBounceEffect` in other places if you like, I am not aware of bad side effects.

### Emerald, modern or not

The most important thing is to remove the second frame wherever it may appear. In `/src/pokemon.c`, find `HasTwoFramesAnimation` and make it `return false;`. This saves the user a lot of trouble. Tell them they don't need to run the config script more than once.

Next, the monsters have other animations when they come onto the battlefield. You can leave them in or remove them. In `/src/pokemon_animation.c`, find `Task_HandleMonAnimation`. There is a line that sets `sprite->callback`; make it always set it to the `SpriteDummyCallback` so it is immediately discarded.

The same animations play on the status screen; in `pokeemerald/src/pokemon.c`, find `PokemonSummaryDoMonAnimation` and make it return immediately.

That should be all.

