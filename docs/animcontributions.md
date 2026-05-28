
# Contributing animations

RAManimator can only be as useful as the animations that run in it, so contributed animations are highly appreciated! To smoothen the process, here are a few guidelines.

## Organization

Animations should be grouped into files logically. In particular, front sprites should be separated from back sprites and trainer sprites so the files can be loaded as modules.

The name of the animation files should match `YOURNAME-GAME-CONTENT.lua` or similar. For `GAME` and `CONTENT`, you can take a look at the files in `luascripts/ramanimator/data`, though there is no rigorous system.

## Format

Animations should be contributed directly as the file you get by running `rasave` or `rag2a`.

If that somehow doesn't work for you, you may also send the animation folder (zipped) or a zip of Aseprite files via e-mail.

## Submission

If you are familiar with Git, please fork the repository and issue a pull request containing the animations as `Lua` files. This has the advantage that Github will associate your info to the file history for attribution.

Otherwise, try sending the contents as zipped attachments to my e-mail as listed on Github. In this case, you will get attributed via the contributor name at the start of the animation filename. Please also mention under which name you want to be mentioned.

In any case, you will get listed in the list of contributors.

Please understand that in any case, I might take a long while to review the submissions.

I reserve the right to decide what does or doesn't get added to the repository and the automatically loaded files.

## Coordination

Below are my thoughts on how the animation database can be grown. They are just opinions, not rules.

In the interest of efficiency, I use gen 2 back sprites for my own gen 1 animations, meaning that the animation can be used in both gen 1 and 2. This mostly means to keep them within 48x48 pixels. While the graphics don't match the style of gen 1, its own back sprites are a lost cause.

Since most users don't have colors in gen 1 games and in the interest of consistency, I decided to animate Red and Blue sprites rather than just animating Crystal sprites and using them across gens 1 and 2. I think it preferable to stay consistent with Red and Blue rather than adding in some Yellow sprites.

For gen 3, the back sprites as ported from Black and White are, of course, full body sprites. While it is nice to have them, I do think they look disproportionate on GBA. In the long run, I believe it is preferable to animate gen 4 style sprites -- as used by pret -- rather than aiming at gen 5 style.
