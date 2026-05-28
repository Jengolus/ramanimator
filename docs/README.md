
# Overview
Within these documents, you will sometimes find instructions on how to change text files. In that case, lines that need to be changed / removed are rendered in red, while new or updated lines are shown in green like this:
```diff
  This line stays as is.
- You need to delete this line.
+ You need to write this line.
```

When using RAManimator, you may run into the following roadblocks:
- You need to set it up for a hack
- A hack modified the graphics and RAManimator doesn't recognize them
- You want to add your own animations

RAManimator comes with features to support you with all three of these goals and some more. Setting up new hacks is handled entirely with mGBA scripts and rather straightforward.

Unfortunately, mGBA 0.10.5 doesn't offer a way for scripts to save additional data. This means that changing hooks and adding animations requires a few extra steps which will be laid out below.

# Users
- [Set up a Pokémon hack](hacksetup.md)
- [Add animation libraries](addanimlibs.md)
- [Updating hooks](updatehooks.md)

# Artists
- [Sprite workflow](workflow.md)
- [Contributing animations](animcontributions.md)

# ROM hackers
- [Improve compatibility](romhackers.md)

# Advanced
- [Animate other games](othergames.md)

# Tools
- [Install the Aseprite extension](aseextension.md)
- [Install the Python package](installpython.md)
