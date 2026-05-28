
"""
A Python module that collects some functions to generate and manipulate
index-based graphics alongside the other ramanimator scripts.

I still want a function that can split the animations as they come into
idle and emote.
"""

import numpy as np
from PIL import Image

from ramanimator.emuserver import Emuserver
from ramanimator.general import b64dumps, b64loads, pack_color, pack_palette
from ramanimator.memory import MemoryBlock
from ramanimator.tiles import sprite2tiles, sprite2tiles_gba
from ramanimator.version import __version__
from ramanimator.writelua import render as to_lua, LuaToken

def render_sprite_ascii(sprite, dark=True):
    """
    Render a row-major sprite (img[y, x]) to the screen.
    """
    data = ""
    chars = "▓▒░ "
    chars = "█▒░ "

    if not dark:
        chars = chars[::-1]

    if np.max(sprite) > 4:
        chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    for row in range(sprite.shape[0]):
        for col in range(sprite.shape[1]):
            color = sprite[row, col]
            data += chars[color] if color < len(chars) else "?"
        data += "\n"

    print(data)

def render_sprite(sprite, palette=None, invert=False):
    """ Render a sprite using matplotlib """
    try:
        import matplotlib.pyplot as plt
    except ImportError as ex:
        raise ImportError("ramanimator.render_sprite requires matplotlib. Please install it using pip install matplotlib or your equivalent.") from ex

    if palette is None:
        # Default to gray
        tmp = np.array([1.0, 1.0, 1.0])
        palette = np.vstack((tmp, tmp * 2 / 3, tmp * 1 / 3, 0*tmp))

        if invert:
            palette = np.max(palette) - palette

        if np.max(sprite) > 4:
            palette = []
            for grade in np.linspace(1, 0, np.max(sprite) + 1, dtype=float):
                palette.append(tmp * grade)

    palette = np.array(palette)
    sprite = palette[sprite]
    plt.imshow(sprite, cmap="gray", vmin=0, vmax=1)
    plt.axis("off")
    plt.show()

def load_png(path):
    img = Image.open(path).convert("RGBA")
    data = np.array(img) # H, W, 4

    return data

def index_colors(frames, palette_manip=None):
    """
    Given an index in (H, W, 4) format, sort its colors into an index
    table.

    The colors are by default sorted by their luminance as defined by
    RGBDS, except that a transparent color, if present, is placed first.

    If there are several fully transparent colors, they are grouped into
    one.

    palette_manip: Sometimes, we need to manipulate the palette before
    indexing, e.g. to manually set the order of colors or if the image
    does not contain all colors of the palette. palette_manip is a
    function that takes the list of sorted colors and can swap /
    duplicate elements as required by the caller.
    """
    # Create a set to hold unique colors
    unique_colors = set()
    has_transparent = False

    # Loop through the frames and collect unique colors
    if not isinstance(frames, (tuple, list)):
        frames = [frames]

    for frame in frames:
        for row in frame:
            for pixel in row:
                # Only allow one transparent color
                if pixel[-1] == 0:
                    if has_transparent:
                        continue
                    has_transparent = True

                unique_colors.add(tuple(pixel))

    def luminance(color):
        if len(color) > 3 and color[3] == 0:
            return 300
        return 0.299 * color[0] + 0.587 * color[1] + 0.114 * color[2]

    # Sort colors by their RGB sum in descending order
    sorted_colors = sorted(unique_colors, key=luminance, reverse=True)

    if palette_manip:
        sorted_colors = palette_manip(sorted_colors)

    # Initialize a dictionary to hold the final colors with assigned values
    color_mapping = {}

    if sorted_colors:
        # The color with the highest sum and transparency gets value 0
        for index, color in enumerate(sorted_colors):
            color_mapping[color] = index

    return sorted_colors, color_mapping

def index_sprite(data, color_mapping):
    """
    Given a sprite in (H, W, 4)-format and a mapping of its colors to
    indices, convert it.
    """
    mapped_image = np.zeros(data.shape[:2], dtype=np.uint8)

    # Loop through the pixel data and replace colors according to their mapping
    for i in range(data.shape[0]):
        for j in range(data.shape[1]):
            color = tuple(data[i, j])
            alpha = data[i, j][3]
            if alpha == 0:
                mapped_image[i, j] = 0
                continue
            # Raise an exception if a color is missing
            if not color in color_mapping:
                raise Exception("Found a color which does not appear in the index mapping: " + str(color))
            mapped_image[i, j] = color_mapping[color]

    return mapped_image

def png2sprite(png_path, palette_manip=None, color_mapping=None):
    """
    Read a png and convert it to an indexed array. For GB,
    swap_middle_colors swaps the colors of the middle indices in case they
    don't follow the luminance pattern.

    This has three steps:
    - Load the PNG in H, W, 4 format
    - Create an index table from its colors
    - Convert it it H, W with an index table
    """
    # Load the PNG image
    data = load_png(png_path)
    #print(png_path, data.shape)

    if color_mapping is None:
        sorted_colors, color_mapping = index_colors(data, palette_manip)
    else:
        sorted_colors = None

    mapped_image = index_sprite(data, color_mapping)

    return mapped_image, sorted_colors

def resize_frame(frame, pxwidth, pxheight, center=None):
    """
    Resize a frame, width and height in pixels.

    If the frame needs to be enlarged, it is placed in the center, unless
    a center (y, x) is provided.

    If the frame is too large, it is cut around the middle, unless a
    center (y, x) is provided.
    """

    start_width = frame.shape[1]
    start_height = frame.shape[0]

    minwidth = min(start_width, pxwidth)
    maxwidth = max(start_width, pxwidth)

    if center:
        start = max(0, int(center[1]) - minwidth // 2)
    else:
        start = (maxwidth - minwidth) // 2

    if start_width > pxwidth:
        frame = frame[:, start:start+pxwidth]
    elif start_width < pxwidth:
        if start + start_width > pxwidth:
            start = pxwidth - start_width

        tmp = frame
        frame = np.zeros((tmp.shape[0], pxwidth, 4), dtype=tmp.dtype)
        frame[:, start:start+start_width] = tmp

    x_start = start

    minheight = min(start_height, pxheight)
    maxheight = max(start_height, pxheight)

    if center:
        start = max(0, int(center[0]) - minheight // 2)
    else:
        start = (maxheight - minheight) // 2

    if start_height > pxheight:
        frame = frame[start:start+pxheight, :]
    elif start_height < pxheight:
        if start + start_height > pxheight:
            start = pxheight - start_height

        tmp = frame
        frame = np.zeros((pxheight, tmp.shape[1], 4), dtype=tmp.dtype)
        frame[start:start+start_height, :] = tmp

    if center:
        centerstr = f", for center {center[1]}x{center[0]}"
    else:
        centerstr = ""

    #print(f"Resize {start_width}x{start_height} -> {pxwidth}x{pxheight}, starting at {x_start}x{start} {centerstr}")

    return frame

def serialize_frame(frame):
    return frame.flatten().tobytes()

def frames2strip(tag, raw, raw_timings, weight=1, frames=None, hashed_frames=None):
    """
    Given frames in indexed format and their timings, convert them to a
    strip. The main point is that this deduplicates frames from the raw
    data.
    """
    if frames is None:
        frames = []
    if hashed_frames is None:
        hashed_frames = {}
    frame_indices = []
    timings = []

    for i, (frame, duration) in enumerate(zip(raw, raw_timings)):
        # Hash the frame for deduplication
        hashval = serialize_frame(frame)

        index = hashed_frames.get(hashval, None)

        if index is None:
            index = len(frames)
            frames.append(frame)
            hashed_frames[hashval] = index

        if i > 0 and index + 1 == frame_indices[-1]:
            # Sometimes, GIFs produce the same frame twice, but we don't
            # need that.
            timings[-1] += 1000 * duration
        else:
            frame_indices.append(index + 1)
            timings.append(1000 * duration)

    return frames, {"tag": tag, "weight": weight, "frameIndices": frame_indices, "timings": timings}

def frames2animation(tag, raw, timings):
    """
    This returns the components of an animation such that it can be passed
    to the emulator via the server.

    - It takes frames in (H, W, 4)-format and converts them to an indexed
      one.
    - It deletes duplicates while generating the list of indexed frames.
    """
    sorted_colors, color_mapping = index_colors(raw)

    palette = [tuple(c) for c in sorted_colors]

    frames = [index_sprite(rframe, color_mapping) for rframe in raw]

    frames, strip = frames2strip(tag, frames, timings)

    return frames, palette, strip

def send_animation(hookname, frames, palette, strips, server=None):
    if server is None:
        server = Emuserver()

    # Encode the frames in Base64
    frames = [b64dumps(frame) for frame in frames]

    # Ensure this is int, not uint8 etc
    palette = [[int(x) for x in color] for color in palette]

    with server:
        answer = server.send_command("registerAnimation", {"name": hookname, "frames": frames, "strips": strips, "palettes": [palette]})

    return answer

def pack_color(r, g, b, a=None, truncate=False):
    """
    Pack a color's channels into the native BGR 555 format.
    If truncate == True, the colors are provided in range 0..255.
    """
    if truncate:
        r = np.ceil(int(r) * 31 / 255)
        g = np.ceil(int(g) * 31 / 255)
        b = np.ceil(int(b) * 31 / 255)

    return (int(b) << 10) + (int(g) << 5) + int(r)

def save_animations(filename, animations, wrapless=False):
    """
    Save the animations to a file that can be read by the Lua scripts.
    animations is a dict, indexed by the hook names, of dicts containing
    the following keys:
    - frames
    - strips
    - palettes

    wrapless: Only print the animations, not the header and footer.

    If filename is None, this just returns the file contents as a string.
    """

    animfile = """
local base64 = require("base64")

local anims = {
ANIMDATA
}

return anims
"""

    animdata = []

    for name, anim in animations.items():
        raw_frames = anim["frames"]
        anim["frames"] = [LuaToken(f'base64.decode("{frame}")') for frame in raw_frames]
        animdata.append(f'{name}={to_lua(anim)}')
        anim["frames"] = raw_frames

    animdata = ",\n".join(animdata) + ","

    if not wrapless:
        animdata = animfile.replace("ANIMDATA", animdata)

    if filename is not None:
        with open(filename, "w") as out:
            out.write(animdata)

    return animdata
