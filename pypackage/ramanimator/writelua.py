
"""
We frequently need to render Python data structures as Lua because I
decided want to reduct the load time of hook and animation data by not
having to pass them through a JSON parser instead.
"""

class LuaToken:
    """
    This is a wrapper for a string such that the string gets rendered
    verbatim, without quotes.
    """
    def __init__(self, token):
        self.token = token

def render_dict(data):
    out = []

    for key, val in data.items():
        if isinstance(key, str):
            out.append(f"{key}={render(val)}")
        else:
            out.append(f"{{{key}}}={render(val)}")

    return f"{{{", ".join(out)}}}"

def render_list(data):
    return f"{{{", ".join([render(x) for x in data])}}}"

def render(data):
    if data is None:
        return "nil"

    if data is True:
        return "true"

    if data is False:
        return "false"

    if isinstance(data, LuaToken):
        return data.token

    if isinstance(data, dict):
        return render_dict(data)

    if isinstance(data, (list, tuple)):
        return render_list(data)

    if isinstance(data, str):
        return f'"{data}"'

    return str(data)
