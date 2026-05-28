
# Animate other games

RAManimator is not restricted to Pokémon and can in theory be used for all kinds of other games. Here are a few considerations in that direction.

## Suitability
RAManimator is good at replacing static sprites on screen. It will have trouble with objects that are already animated. If both frames of the native animation are in memory simultaneously, take a look at twin slots in the source code. If a slot has twins and writes a frame, it automatically writes the same frame to all of its twin slots. That means to override a game's native animation, all you need to do is set up twin slots (and appropriate hooks) for all other frames. The twins will then always write the current frame to all three addresses and whichever one the game switches to always has the correct frame.

## Slot setup

Both interfaces have commands to set up slots. In mGBA, go `Tools->Game state views->View tiles` and find the address at which a graphics starts and its size, then register a slot to that specification. Note the slot registration commands take the size in tiles, not pixels (divide by eight). If an object can appear at several addresses, look at sibling slots in the source code.

Whenever you register a slot, load it often to see what is actually inside.

Slots can also be exported by `rasave`, look at its source.

## Hook setup

Either do it manually through `Import slot` or look at the separate repository with the scripts I used.

## Sprite slots

For the sprites on mGBA, I use a SpriteSlot. It monitors the sprites and if one of a certain size and palette is listed, it spawns a TileSlot that does the actual animation for that specific address.

## Parallels

Whenever you find a problem, consider whether I also had to face it for the Pokémon games and check how I solved it.
