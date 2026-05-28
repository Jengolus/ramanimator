
# Full animation workflow

If you want to create your own animations, you need to go through the following steps:

- Import a hook as a file
- Animate that file
- Send it to the emulator
- Save the emulator-ready animation

All of them can be performed in Aseprite (recommended) or in a less convenient way through the Python package.

> [!WARNING]
> Making RAManimator load the animations on startup always requires the Python package, so please [install it](installpython.md) before proceeding.

## GB and GBA animations

The animations must obey the platforms' technical restrictions, in particular the image sizes and palettes. The main limitations are:

For Gameboy:
- Only white, two colors, and black in a sprite
- Front and back sprites are 56x56 pixels exactly
  - In gen 2, back sprites are only 48x48! RAManimator automatically upscales 48x48 backsprites if you send them to gen 1.

For GBA:
- 16 colors per sprite, the first one is always transparent in the emulator
- 64x64 pixels, though back sprites are partially hidden

## How animations work

RAManimator allows having one animation per hook. To make it more dynamic, an animation can consist of several strips that are dynamically chained after each other. The two main kinds are `idle` and `emote` strips, where one emote strip always comes after three idle strips. For example, a monster will just breath in and out three times, then strike a pose. An animation can contain several `idle` and `emote` strips, among which it will choose randomly.

Further, animations may have an `intro` strip that plays once when the sprite appears. Note this is when the sprite appears in memory, not on screen; if it is loaded for a while before it gets shown, it cannot be synchronized.

> [!NOTE]
> For starters, it is recommended to just have a single idle strip and be done with it.

### Contextual strips

For Pokémon generations 1 and 2, RAManimator allows making strips depend on the monster's status. The animations may differ if a monster is low on HP, fainted or asleep. For example, Charmander's flame slowly dwindles as its HP decrease in the first generation games. This is managed by appending a tag to the strips name; for HP, these names are

- `idle`
- `idle-yellow`
- `idle-red`
- `idle-fainted`

and equivalent for `emote`.

For drastic changes between these states, extra transitions are available:

- `hurtto-yellow`
- `hurtto-red`
- `hurtto-fainted`
- `healto`
- `healto-yellow`

An `asleep-` can be prefixed to all of them for when the monster is asleep.

### Trainer strips

In the generations 1 and 2, RAManimator allows giving trainers special animations for when they lose or win (e.g. first rival battles). The tags are

- `idle`
- `idle-loss`
- `idle-win`

et cetera.

## Managing files

### With Aseprite

Manage files however you like. They will only get bundled together when you send them over to Aseprite.

### Without Aseprite

The structure of a library, its animations and their strips is reflected through the file structure. This means:

- First create one folder for all animations of a game.
- The below commands will generate directories in this folder. Their names will match the hook.
- In each directory, Gif files correspond to individual strips. That means there should at least be an `ìdle.gif`.

> [!NOTE]
> The following steps assume that you are in the folder that holds your animations. If not, you can add a `--path` argument.

## Color palettes

### General

GB and GBA store colors with five bits per channel, modern hardware uses eight bits per channel. This means that colors you send to the emulator might come back differently.

### With Aseprite

The first color is always fully transparent for your convenience, then come batches of four / sixteen colors as the actual palettes. When confused, just import a hook and look at its palette. You can edit the individual colors in a palette freely, though unmodified mGBA cannot change colors on Gameboy games (so you shouldn't change those).

### Without Aseprite

When you import a hook, it prints its palettes to files. If you want to keep things simple, just don't change the colors.

The problem is that the interplay with the emulator needs the colors to be in the correct order, and the order it expects is more or less arbitrary. In any case, it cannot be inferred from the GIFs alone. That is why the palettes are stored in a file: It stores their order. This is particularly necessary for shiny palettes.

Gameboy and Gamebody Color: Since unmodified mGBA cannot change colors here, you'll be best off if you keep the palette files in the directory and don't change anything.

GBA: If you want shiny palettes to work, you will need to keep the palette files. Otherwise, you can delete them and edit the GIFs freely, as long as you stay in the 16 color limit.

> [!NOTE]
> Transparent colors are always mapped to index 0, so you can use a transparency colors in the GIF layers.

> [!WARNING]
> RAManimator still needs to know which is the background color. It will always look at the top-left pixel of the first frame in idle.gif for that purpose.

## Import a hook

### With Aseprite

Click `File -> RAManimator -> Import hook`, then select the slot and hook. It is imported as a new sprite with the palettes set up correctly.

### Without Aseprite

On your command line, navigate to the animation folder you created. Run `ramanim getHook NAME`, where `NAME` needs to be the name of the hook. If you don't know it, run `ramanim getLibrary` which prints a list of all hooks. For example, if you want to animate the front sprite of Bulbasaur, run `ramanim getHook Bulbasaur_Front`.

This creates a subfolder which contains the file `idle.gif`. This is a single frame, namely the hook. Further, it contains two `.pal` files. These contain the palettes in the order that the emulator expects them.

## Using preexisting animations

### With Aseprite

Open the file, then click `File -> RAManimator -> Attach hook` and select the hook. Ideally, also import the hook into a new file and check that the palettes are set up correctly.

### Without Aseprite

Import the hook for which you have an animation as above, then replace `idle.gif` in that folder by your existing animation. If the palettes don't match, delete them and try to save and load the animations as explained below. If that produces glitches, you'll need to try and export the palettes from your GIF manually. The restrictions laid out earlier apply.

## Managing strips

### With Aseprite

Select the frames of a strip, right click, `New Tag`. Set the name to `idle` or whichever strip you want. Animation directions do work. You can add an number to the user data field, which serves as the strips probability weight. The default weight is 1; if you want to add a rare emote, you can give it a weight of e.g. 0.1 here.

### Without Aseprite

Within an animations directory, just copy the imported GIF and give it the name of the strip (and `.gif`).

## Preview animations

### With Aseprite

While the animation's hook is on screen, hit `File -> RAManimator -> Send to emulator`. It should now start; if it doesn't, click `File -> RAManimator -> Update hook`.

There is no way to explicitly preview different strips, but you can always change their names.

### Without Aseprite

Not possible.

## Save to file

In order to have animations load automatically when you start RAManimator, you need to export them to the file format it can read.

### With Aseprite

Send all animations that you want to export to the emulator as explained above. If you still had scratch animations on the server before, use `File -> RAManimator -> Clear animations`.

Next open your command line where you installed the Python package in the folder where you want the animation file. Type `rasave -a FILENAME`, where `FILENAME` is the name of the animation file.

You still need to follow the next step to have it load automatically when you start RAManimator.

### Without Aseprite

In your command line, run `rag2a gba PATH -o OUTPATH`. Replace `gba` with `gb` for Gameboy animations. `PATH` is the relative path to the animation directory, `OUTPATH` is the name of the animation file you aim to generate. `rag2a` stands for RAManimator GIF to Animation.

You still need to follow the next step to have it load automatically when you start RAManimator.

## Load the animation file

The final step is to tell RAManimator where to find your fancy new animation file. To that end, find the directory where you installed RAManimator. Then copy the animation file to `luascripts/myfiles` and follow the instructions [here](addanimlibs.md).
