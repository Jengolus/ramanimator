
import asyncio
import json
import time

import websockets
from websockets.sync.client import connect as wsconnect

from .general import b64dumps, b64loads
from .memory import *

timeout = 15

class Emuserver:
    """
    Client to the server hosted on an emulator.

    It is implemented synchronously because really, that's enough.
    """

    def __init__(self, ip="localhost", port=8446):
        self.ip = ip
        self.port = port

        # An active server for manual (dis)connects
        self.connection = None
        self.timeout = timeout

    def __enter__(self):
        self.connect()

        return self

    def __exit__(self, exc_type, other, traceback):
        self.disconnect()
        pass

    def connect(self):
        uri = f"ws://{self.ip}:{self.port}"
        self.connection = wsconnect(uri, timeout=self.timeout, ping_interval=None)

    def disconnect(self):
        self.connection.close()
        self.connection = None

    def _send_command(self, socket, command):
        try:
            socket.send(command)
        except websockets.exceptions.ConnectionClosedError as ex:
            """
            I don't know why, but after a few seconds the connection is
            lost only when coming from Python. Attempt to reconnect a
            few times before giving up.
            Is this my antivirus or something?
            """
            raise ex
            #print("Lost connection, trying to reconnect")
            #for i_attempt in range(1, 5):
            #    print("Attempt", i_attempt)
            #    self.disconnect()
            #    time.sleep(i_attempt)
            #    try:
            #        self.connect()
            #        socket.send(command)
            #        break
            #    except websockets.exceptions.ConnectionClosedError:
            #        pass
            #else:
            #    # Reconnection failed
            #    raise ex

        ret = socket.recv()

        # Probably not a great solution, but good enough
        if ret == "awaitcallback":
            ret = socket.recv()

        return ret

    def send_command(self, command, args=None):
        """
        command is the actual command, args are all the arguments to it in
        a dictionary.

        The command is then automatically added to the dict. This is done
        for convenience since the command is the only mandatory element.

        The data is intentionally sent as UTF-8.
        """
        if args is None:
            command = {"command": command}
        else:
            args["command"] = command
            command = args

        if not isinstance(command, str):
            command = json.dumps(command, ensure_ascii=False)

        if self.connection is not None:
            response = self._send_command(self.connection, command)
        else:
            raise Exception("No open connection")
            #with socket.socket() as s:
            #    s.settimeout(timeout)
            #    s.connect((self.ip, self.port))
            #    response = self._send_command(s, command)

        try:
            response = json.loads(response)
        except:
            pass

        return response

    """Module memory"""
    def read_cart(self, start, length):
        """ Read a range from the cartridge """
        ret = self.send_command("readCart", {"offset": start, "length": length})
        ret = b64dumps(ret["data"])
        return MemoryBlock(start, list(ret))

    def read_ram(self, start, length):
        """ Read a range from the bus """
        ret = self.send_command("readRam", {"offset": start, "length": length})
        ret = b64loads(ret["data"])
        return MemoryBlock(start, list(ret))

    def write_range(self, start, data):
        """Write some bytes directly to the bus. Can be an iterable of
        integers or the MemoryBlock type."""
        if isinstance(data, MemoryBlock):
            data = data.data

        if not isinstance(data, bytes):
            data = bytes(data)

        cmd = {"offset": start, "data": b64dumps(data)}
        self.send_command("writeRam", cmd)

    def write_cart(self, start, data):
        """Write some bytes directly to the cartridge. Can be an iterable
        of integers or my own MemoryBlock type."""
        if isinstance(data, MemoryBlock):
            data = data.data

        if not isinstance(data, bytes):
            data = bytes(data)

        cmd = {"offset": start, "data": b64dumps(data)}
        self.send_command("writeCart", cmd)

    def search_ram(self, data):
        if isinstance(data, MemoryBlock):
            data = data.data

        response = self.send_command("searchRam", {"data": b64dumps(data)})
        return response["offsets"]

    def search_cart(self, data, mask=None):
        if isinstance(data, MemoryBlock):
            data = data.data

        response = self.send_command("searchCart", {"data": b64dumps(data), "mask": mask})
        return response["offsets"]

    def send_buttons(self, buttons):
        """
        Press buttons for one frame, then advance for some frames.
        buttons is a list of lists ["button", n_frames].
        """
        self.send_command("remoteControl", {"actions": buttons})
