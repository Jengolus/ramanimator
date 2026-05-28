
import numpy as np

# Helpers when writing tiles to / from VRAM
def tile2pixels(tile):
    pixels = np.zeros((8, 8), dtype=int)

    for row in range(8):
        b1 = tile[2*row]
        b2 = tile[2*row + 1]

        for bit in range(8):
            mask = 2**bit
            pixels[row, 7 - bit] = (mask & b1 != 0) + 2 * (mask & b2 != 0)

    return pixels

def pixels2tile(pixels):
    tile = []

    for row in range(8):
        b1 = 0
        b2 = 0

        for bit in range(8):
            mask = 2**bit
            pixel = pixels[row, 7 - bit]
            b1 += mask * (pixel % 2)
            b2 += mask * (pixel // 2)

        tile.append(int(b1))
        tile.append(int(b2))

    return tile

def sprite2tiles(raw_sprite, slot="Front", maintain_size=False):
    """
    Given a sprite, scale it to screen size and apply the layout
    associated with that slot (Front, Back). For Back, if the
    raw_sprite is 32x32, it will be upscaled and trimmed as per gen1
    conventions. If it is a 40x40 Back sprite as in Gen 2, it will not be
    padded, as in Gen 2.

    When in doubt, use Front.
    """
    # Rescale it to 56x56
    width = raw_sprite.shape[0]
    height = raw_sprite.shape[1]

    if slot == "Back" and width == 32:
        # Gen 1 back sprites get trimmed and upscaled
        sprite = np.zeros((56, 56), dtype=int)
        for y in range(28):
            for x in range(28):
                sprite[2*y:2*y+2, 2*x:2*x+2] = raw_sprite[y, x]

        width = 56
        height = 56

    elif width != 56 and not maintain_size:
        sprite = np.zeros((56, 56), dtype=int)
        offset = (56 - width) // 2
        if width == 48:
            offset = 8
        roffset = 56 - height
        for row in range(height):
            for col in range(width):
                sprite[roffset + row, offset + col] = raw_sprite[row, col]

        width = 56
        height = 56

    else:
        sprite = np.asarray(raw_sprite).reshape(height, width)

    tile_data = []

    # Now, put the tiles where they belong
    for col in range(width // 8):
        for row in range(height // 8):
            subset = sprite[8*row:8*(row + 1), 8*col:8*(col + 1)]
            subset.flatten()
            tile_data.extend(pixels2tile(subset))
            #set_tile(7*col + row, pixels2tile(subset))

    return tile_data

def pixels2tile_gba(pixels):
    tile = []

    for row in pixels:
        for low, high in zip(row[::2], row[1::2]):
            byte = low + 0x10 * high
            tile.append(byte)

    return tile

def sprite2tiles_gba(pixels):
    """Convert the pixels to the GBA's VRAM format."""
    width = pixels.shape[0]
    height = pixels.shape[1]

    vram = []

    for row in range(height // 8):
        for col in range(width // 8):
            subset = pixels[8*row:8*(row + 1), 8*col:8*(col + 1)]
            subset.flatten()
            tile_ram = pixels2tile_gba(subset)
            vram.extend(tile_ram)

    return vram
