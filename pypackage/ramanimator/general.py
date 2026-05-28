
import base64
import math

def b64dumps(data):
    """Wrapper that returns a string."""
    if not isinstance(data, bytes):
        #print(data)
        data = bytes(data)

    return base64.b64encode(data).decode("utf-8")

def b64loads(data):
    """Wrapper that returns bytes."""
    return base64.b64decode(data)

def pack_color(color):
    # color = [r, g, b] from 0 to 255
    r = math.ceil(color[0] * 31 / 255)
    g = math.ceil(color[1] * 31 / 255)
    b = math.ceil(color[2] * 31 / 255)
    return (b << 10) + (g << 5) + r

def pack_palette(pal):
    if pal is None:
        return None

    return [pack_color(color) for color in pal]
