
"""
This is a command-line alternative to the Aseprite interface for the most
important commands. If you have Aseprite, do not use it.
"""

import argparse
import os

try:
    import ramanimator as ra
except ImportError:
    print("Could not import the ramanimator python package. Follow the instructions online to install it.")
    exit(1)

import numpy as np
from PIL import Image

def save_indexed_gif(pixels: np.ndarray, palette: list, out_path: str):
    """
    pixels: 2D uint8 numpy array of shape (H, W) with indices into palette (0..255)
    palette: list of (R,G,B) tuples, length <= 256
    out_path: output filename ending with .gif
    """
    if pixels.dtype != np.uint8:
        raise TypeError("pixels must be uint8")
    if pixels.ndim != 2:
        raise ValueError("pixels must be 2D")

    pal = []
    for r, g, b in palette:
        pal.extend([int(r), int(g), int(b)])

    h, w = pixels.shape
    img = Image.fromarray(pixels, mode="P")
    img.putpalette(pal)

    # Ensure no optimization (don't change indices), and set loop=0 for single image
    img.save(out_path, format="GIF", save_all=False, optimize=False, duration=1000)

def print_answer(answer, on_success):
    status = answer.get("status", None) 
    if status is None:
        print("Answer does not provide a status.")
    else:
        if status != "success":
            print("No success:", status)
        else:
            print(on_success)

def unload_animations(args):
    with ra.Emuserver() as emu:
        answer = emu.send_command("unloadAnimations")
        print_answer(answer, "All animations unloaded.")

def get_library(args):
    with ra.Emuserver() as emu:
        answer = emu.send_command("getLibrary")
        if answer.get("status", None) != "success":
            print_answer(answer, "")
            return

    name = answer["name"]
    print(name)
    print("=" * len(name))
    print()

    # Print the info
    print("Slots")
    print("-----")

    slots = answer["slots"]
    for name in sorted(slots.keys()):
        if args.verbose:
            print(name, slots[name])
        else:
            info = name
            data = slots[name]
            kind = data.get("kind", "")

            if kind == "tile":
                info += " TileSlot"
            elif kind == "sprite":
                info += "SpriteSlot"

            extras = data.get("extras", {})
            print(info)

    hooks = answer["hooks"]
    animations = answer["animations"]

    animations = {anim["name"]: anim for anim in animations}

    print()
    print("Hooks and animations")
    print("--------------------")
    for hook in sorted(hooks, key=lambda hook: hook["name"]):
        if hook.get("isSibling", False):
            continue

        name = hook["name"]
        has_anim = animations.get(name, None) is not None

        if args.verbose:
            if has_anim:
                print("+", name, hook)
            else:
                print("-", name, hook)
        else:
            if has_anim:
                print("+", name)
            else:
                print("-", name)

    print()
    print("Extras")
    print("------")
    extras = answer.get("extras", {})
    for key, val in extras.items():
        print(f"{key}: {val}")
    if len(extras) == 0:
        print("None")

def update_hook(args):
    with ra.Emuserver() as emu:
        answer = emu.send_command("updateHook", {"name": args.name})
        print_answer(answer, "Hook updated.")

def update_hook_palette(args):
    with ra.Emuserver() as emu:
        answer = emu.send_command("updateHook", {"name": args.name, "paletteOnly": True, "paletteIndex": args.palette})
        print_answer(answer, "Hook palette updated.")

def save_hook(path, answer, force=False):
    if os.path.exists(path) and os.path.isdir(path):
        if not force:
            raise FileExistsError(f"Directory exists: {path}")

    os.makedirs(path, exist_ok=True)

    # Convert the palettes to files
    if "palettes" in answer:
        for i_pal, palette in enumerate(answer["palettes"]):
            palpath = os.path.join(path, f"{i_pal + 1}.pal")
            with open(palpath, "w") as out:
                out.write(f"JASC-PAL\n0100\n{len(palette)}\n")
                lst = "\n".join([f"{col[0]} {col[1]} {col[2]}" for col in palette])
                out.write(lst)

    if "pixels" in answer:
        pixels = ra.b64loads(answer["pixels"])
        pixels = np.frombuffer(pixels, dtype=np.uint8).reshape((answer["height"], answer["width"]))

        if "palettes" in answer and len(answer["palettes"]) > 0:
            palette = answer["palettes"][0]
        else:
            palette = np.linspace(0, 255, max(pixels) + 1, dtype=np.uint8)

        gifpath = os.path.join(path, "idle.gif")
        save_indexed_gif(pixels, palette, gifpath)
    else:
        raise Exception("No pixels received.")

def get_hook(args):
    # Export a hook to the given path including palettes
    with ra.Emuserver() as emu:
        answer = emu.send_command("getHook", {"name": args.name})
        if answer.get("status", None) != "success":
            print_answer(answer, "")
            return

    path = os.path.join(args.path, args.name)
    save_hook(path, answer, force=args.force)
    print("Hook saved to", path + "/idle.gif")

def load_slot(args):
    with ra.Emuserver() as emu:
        answer = emu.send_command("loadSlot", {"slotName": args.name, "hookName":args.hookName})
        if answer.get("status", None) != "success":
            print_answer(answer, "")
            return

    path = os.path.join(args.path, args.hookName)
    save_hook(path, answer, force=args.force)
    print("Slot saved to", path + "/idle.gif")

def register_slot(args):
    address = args.address

    if address.startswith("0x"):
        address = address[2:]

    address = int(address, 16)

    palette = args.palette
    if palette == -1:
        palette = None

    with ra.Emuserver() as emu:
        answer = emu.send_command("registerSlot", {"name": args.name, "kind": "tile", "address": address, "width": args.width, "height": args.height, "layout": args.layout, "order": args.order, "palette": palette})

    print_answer(answer, "Slot registered")

def get_version(args):
    print(ra.__version__)

    with ra.Emuserver() as emu:
        answer = emu.send_command("getRAManimatorVersion")
        print("Version on emulator:", answer.get("version", "Error"))

def send_command(args):
    import json
    command = args.command
    args = args.args
    if args is not None:
        try:
            args = json.loads(args)
        except Exception:
            print("Could not parse the JSON arguments.")
            return

    with ra.Emuserver() as emu:
        answer = emu.send_command(command, args)
        print(answer)

def parse_args():
    parser = argparse.ArgumentParser(prog="RAManimator commander", description="Send commands to a running RAManimator instance on mGBA")

    parser.add_argument("--host", default="localhost", help="host name")
    parser.add_argument("--ip", default=8446, type=int, help="ip address")

    subparsers = parser.add_subparsers(dest="command", required=True)

    p_get_library = subparsers.add_parser("getLibrary", help="Print info on current slots, hooks and animations")
    p_get_library.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    p_get_library.set_defaults(func=get_library)

    p_unload_animations = subparsers.add_parser("unloadAnimations", help="Unloads all animations from the library")
    p_unload_animations.set_defaults(func=unload_animations)

    p_update_hook = subparsers.add_parser("updateHook", help="Update a hook to what is currently on screen in its slot.")
    p_update_hook.add_argument("name", type=str, help="Name of the hook")
    p_update_hook.set_defaults(func=update_hook)

    p_update_hook_palette = subparsers.add_parser("updateHookPalette", help="Update a hook's palette to what is currently in its slot.")
    p_update_hook_palette.add_argument("name", type=str, help="Name of the hook")
    p_update_hook_palette.add_argument("--palette", type=int, default=1, help="ID of the hook's palette to edit")
    p_update_hook_palette.set_defaults(func=update_hook_palette)

    p_get_hook = subparsers.add_parser("getHook", help="Export a hook as a GIF with palettes to the specified path")
    p_get_hook.add_argument("name", type=str, help="Name of the hook")
    p_get_hook.add_argument("--path", type=str, default=".", help="Where to create the directory for the hook")
    p_get_hook.add_argument("--force", action="store_true", help="Set to overwrite existing files")
    p_get_hook.set_defaults(func=get_hook)

    p_load_slot = subparsers.add_parser("loadSlot", help="Export a slot's current contents as a GIF")
    p_load_slot.add_argument("name", type=str, help="Name of the slot")
    p_load_slot.add_argument("hookName", type=str, help="Name of the created hook")
    p_load_slot.add_argument("--path", type=str, default=".", help="Where to create the directory for the hook")
    p_load_slot.add_argument("--force", action="store_true", help="Set to overwrite existing files")
    p_load_slot.set_defaults(func=load_slot)

    p_register_slot = subparsers.add_parser("registerSlot", help="Register a new slot for the game")
    p_register_slot.add_argument("name", type=str, help="Name of the slot")
    p_register_slot.add_argument("--address", "-a", required=True, type=str, help="The slot's address (hexadecimal, e.g. 0x9000 or 9000)")
    p_register_slot.add_argument("--width", "-w", required=True, type=int, help="Width in tiles (8 pixels each)")
    p_register_slot.add_argument("--height", "-e", required=True, type=int, help="Height in tiles (8 pixels each)")
    p_register_slot.add_argument("--layout", "-l", required=True, type=int, help="Layout code, e.g. 0, 1 or 3")
    p_register_slot.add_argument("--order", "-o", default=0, type=int, help="Position when listing slots, -1 to hide it")
    p_register_slot.add_argument("--palette", "-p", type=int, default=-1, help="Palette index, -1 for no palette")
    p_register_slot.set_defaults(func=register_slot)

    p_sendCommand = subparsers.add_parser("sendCommand")
    p_sendCommand.add_argument("command", type=str, help="Command")
    p_sendCommand.add_argument("args", type=str, default=None, help="Arguments as JSON dictionary")
    p_sendCommand.set_defaults(func=send_command)

    p_sendCommand = subparsers.add_parser("version")
    p_sendCommand.set_defaults(func=get_version)

    return parser.parse_args()

def main():
    args = parse_args()
    try:
        args.func(args)
    except ConnectionRefusedError:
        print("Could not connect to the emulator, are you sure RAManimator is running there?")
        exit(1)

if __name__ == "__main__":
    main()
