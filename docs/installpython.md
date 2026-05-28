
# Install the Python package

Unfortunately, mGBA does not offer a way to save data directly, so you always need to manually export changes through a Python interface, then insert the new files. To make this process as smooth as possible, there is a Python library that does most of the work.

## Prerequisites

Please make sure that you have installed [Python](https://www.python.org/) and know how to open a command line, that is usually Powershell on Windows and your terminal everywhere else.

When you run `startup.lua` to load RAManimator in mGBA, it should print a line like `mGBA JSON server listening on port 8446`. If it doesn't, the Python package will not be able to connect to the emulator. If it prints a number different than `8446`, you will need to manually provide the port when trying to connect.

## Installation

Navigate to your RAManimator directory. Open the folder `pypackage` in your command line. On Windows, that means right-clicking the folder and clicking "Open in Terminal". Once you are there, type `pip install .` and press enter, which should install the Python package for you. If there are any problems, try to solve them through [these instructions](https://packaging.python.org/en/latest/tutorials/installing-packages/), in particular [this paragraph](https://packaging.python.org/en/latest/tutorials/installing-packages/#installing-from-a-local-src-tree).

If the installation was successful, you can type `ramanim version` (hit enter) and it should print the version of RAManimator you are using. This also tries to connect to the emulator, so run it while RAManimator is active there.

When you execute a script for the first time, your antivirus is probably going to scan it. It should find the scripts harmless after a few seconds.

## Tour

The Python package provides three commands that you can now use from your command line. You will be instructed on how to use them for specific problems in the other how-tos.

### ramanim

ramanim allows you to send commands to the emulator. Running `ramanim -h` should give you an overview of available commands and which arguments they take. If you use Aseprite, you won't need this one because its functionality is also exposed there as a graphical interface.

### rasave

The most important one, as it saves your changes to files which you then need to copy to the appropriate positions in the `luascripts` directory. Run this when you have updated slots or hooks for a specific game or loaded some animations through Aseprite. It will tell you what to do with the files it generates.


### rag2a

Short for ramanimator gifs to animations. This allows you to convert a bunch of gifs to animation files like RAManimator reads. If you use Aseprite, load the animations through it and use rasave instead.
