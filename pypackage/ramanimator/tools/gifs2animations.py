
"""
Use this only if for some reason you do not have Aseprite.

Convert nested directories filled with GIFs into an animation file.^
"""

import argparse
import math
from pathlib import Path
import sys

try:
    import ramanimator as ra
except ImportError:
    print("Could not import the ramanimator python package. Follow the instructions online to install it.")
    exit(1)

import numpy as np
from PIL import Image, ImageSequence

max_colors = 16
finalize_frame = ra.sprite2tiles_gba

def parse_args():
    parser = argparse.ArgumentParser(
        prog="GIFs2Animations",
        description="Converts a folder structure containing GIFs to an animation file. See only documentation. Only use this if you have a good reason not to use Aseprite."
    )

    parser.add_argument(
        "platform",
        choices=["gb", "gba"],
        help="Target platform: 'gb' or 'gba' (required)."
    )

    parser.add_argument(
        "path",
        type=Path,
        help="Path to root directory (required)."
    )

    # optional output
    parser.add_argument(
        "-o", "--output",
        default="anims.lua",
        help="Output filename (default: %(default)s)."
    )

    return parser.parse_args()

def load_gif(path):
    frames = []
    timings = []

    try:
        with Image.open(path) as im:
            for i_frame, frame in enumerate(ImageSequence.Iterator(im)):
                if frame.mode != "RGBA":
                    frame = frame.convert("RGBA")

                idx = np.asarray(frame)
                frames.append(idx.astype(np.uint8))
                # GIF frame duration (ms) stored in frame.info
                delay_ms = frame.info.get("duration", 100)
                timings.append(delay_ms / 1000.0) # seconds
    except FileNotFoundError:
        print("Could not find file", path)
        return None, None

    return frames, timings

def load_palette(path):
    """
    They are in JASC-PAL format, so the first three lines are metadata
    followed by 16 lines of R, G and B.
    """
    ret = {}
    palette = []

    with open(path) as inf:
        lines = inf.readlines()
        length = int(lines[2])

        for iColor, line in enumerate(lines[3:]):
            line = line.split()
            color = tuple([np.uint8(tok) for tok in line] + [255])
            ret[color] = iColor
            palette.append(ra.pack_color(*[math.ceil(int(c) * 31 / 255) for c in color[:3]]))

        if length < max_colors:
            print(f"Palette in {path} contains {length} colors, not {max_colors}! Filling up.")
            palette.extend([0] * (max_colors - length))
        elif length > max_colors:
            raise Exception(f"Palette in {path} contains {length} colors, not {max_colors}!")

    ret["palette"] = palette
    return ret

def get_closest_color(color_map, color):
    """
    Return the index of the color with the smallest euclidean distance.
    """
    best_idx = None
    best_col = None
    best_dist_sq = None

    # Normal int to make negative differences work
    cr, cg, cb, ca = [int(x) for x in color]
    for col, idx in color_map.items():
        kr, kg, kb, ka = [int(x) for x in col]
        dr = kr - cr
        dg = kg - cg
        db = kb - cb
        dist_sq = dr*dr + dg*dg + db*db
        if best_dist_sq is None or dist_sq < best_dist_sq:
            best_dist_sq = dist_sq
            best_col = col
            best_idx = idx

    if best_col is None:
        raise ValueError("Explicit palette is empty")

    return best_col, best_idx

def read_animation(name, path):
    """
    1) Try to read explicit palette files if there are any
    2) Read strip gifs and index colors as we go.
    """
    def collect_palettes():
        palettes = []
        n = 1
        while True:
            pal = path / f"{n}.pal"
            if pal.exists():
                palettes.append(pal)
                n += 1
            else:
                break
        return palettes

    palfiles = collect_palettes()

    palettes = []

    for pal in palfiles:
        palettes.append(load_palette(pal))

    gifs = sorted(path.glob("*.gif"), key=lambda p: p.name.lower())
    # move idle.gif (case-insensitive) to the front if present
    idle_index = next((i for i, p in enumerate(gifs) if p.name.lower() == "idle.gif"), None)
    if idle_index is not None:
        idle = gifs.pop(idle_index)
        gifs.insert(0, idle)

    strips = []

    if len(palettes) > 1:
        palette = palettes[0]["palette"]
        color_map = {key: val for key, val in palettes[0].items() if isinstance(val, int)}
        explicit_palette = True
    else:
        palette = []
        color_map = {}
        explicit_palette = False

    if len(gifs) == 0:
        print(f"{name} does not contain any GIF files!")
        return

    frames = []
    hashed_frames = {}

    for i_gif, gif in enumerate(gifs):
        # In RGBA-format
        strip_frames, strip_timings = load_gif(gif)
        # Remove counter for equivalent strips
        name_info = gif.stem.split("_")
        tag = name_info[0]

        if i_gif == 0 and tag != "idle":
            print(f"{name} does not have an idle.gif, so using {gif.stem} as its idle animation!")
            tag = "idle"

        raw_colors, _ = ra.index_colors(strip_frames)
        raw_colors = [tuple(col) for col in raw_colors]

        # This requires the first pixel to be in the background color
        if len(palette) == 0:
            bkg_color = strip_frames[0][0][0]
            color_map[tuple(bkg_color)] = 0
            palette.append(bkg_color)

        for color in raw_colors:
            if color not in color_map:
                if len(color) > 3 and color[3] == 0:
                    color_map[color] = 0
                    continue

                if explicit_palette:
                    # Just try to match it, whatever
                    match_col, match = get_closest_color(color_map, color)
                
                    print(f"Warning: Animation {name}, strip {gif.name}: Replacing ({color}) with ({match_col}) to stay within explicitly defined palette.")
                    color_map[color] = match
                    continue

                # Add a new color
                color_map[color] = len(palette)
                palette.append(color)

        strip_frames = [ra.index_sprite(rframe, color_map) for rframe in strip_frames]
        #ra.render_sprite_ascii(strip_frames[0])
        # Includes deduplication
        _, strip = ra.frames2strip(tag, strip_frames, strip_timings, frames=frames, hashed_frames=hashed_frames)

        # Timings -> Frames
        for i_time, time in enumerate(strip["timings"]):
            strip["timings"][i_time] = int(60 * time / 1000)

        strips.append(strip)

    if not explicit_palette:
        palettes = [palette]

    frames = [ra.b64dumps(finalize_frame(frame)) for frame in frames]
    # Filter out the "palette" key
    palettes = [[ra.pack_color(*color, truncate=True) for color in palette if not isinstance(color, str)] for palette in palettes]

    return {"name": name, "frames": frames, "strips": strips, "palettes": palettes}

def main():
    global max_colors, finalize_frame
    args = parse_args()

    if args.platform == "gb":
        max_colors = 4
        finalize_frame = ra.sprite2tiles

    path = args.path

    animations = {}

    if not path.exists():
        raise SystemExit(f"Error: path does not exist: {path}")
    if not path.is_dir():
        print(f"Path is a file: {path}")
    if path.is_dir():
        anim_names = [d for d in sorted(path.iterdir()) if d.is_dir()]

        if anim_names:
            for subdir in anim_names:
                anim = read_animation(subdir.name, path / subdir.name)
                if anim is not None:
                    animations[subdir.name] = anim
        else:
            raise SystemExit("The provided directory should contain directories, the names of which match hooks' names, but there are no subdirectories.")

    print("Hook name: Strips")
    print("-----------------")

    for name, anim in animations.items():
        print(f"{name}: " + ", ".join([strip["tag"] for strip in anim["strips"]]))

    ra.save_animations(args.output, animations)
    print(f"""
Copy the animation file to the "luascripts/myfiles" folder in the directory where you installed RAManimator, then add a line like the following, with the correct path, to the end of the animations in your setup:
        anims[#anims + 1] = (require("myfiles/{args.output}"))
""")

if __name__ == "__main__":
    main()
