
--[[
The module for managing the socket.

I don't really know how to do this, so do not use it as an example.
--]]

local connection = {}
connection.dbg = false

local pluginKey = "jengolus/ramanimator"

local socketCallback = nil
local connected = false
local socket = nil

local function socketReceive(messageType, data)
  if messageType == WebSocketMessageType.OPEN then
    if connection.dbg then
      print("Connected to server.")
    end
  elseif messageType == WebSocketMessageType.TEXT then
    connected = true
    if connection.dbg then
      print("Received message: ", data)
    end

    if socketCallback == nil then
      return app.alert("Received a message from the server, but wasn't expecting one: " .. tostring(data))
    end

    -- This one is immutable for some reason, so make a shallow copy.
    -- Its elements are still immutable, so be aware of that.
    local rawMessage = json.decode(data)
    local message = {}
    for k, v in pairs(rawMessage) do
      message[k] = v
    end

    -- Append the raw message for debugging
    if message.raw == nil then
      message.raw = data
    end

    socketCallback(message)
  elseif messageType == WebSocketMessageType.CLOSE then
    connected = false
    if connection.dbg then
      print("Connection closed")
    end
  end
end

local function initSocket()
  local prefs = ramanimatorPreferences

  if prefs == nil then
    -- I don't think this is reachable, but...
    prefs = {ip="localhost", port="8446"}
  end

  if socket ~= nil then
    socket:close()
  end

  socket = WebSocket {
    onreceive = socketReceive,
    url = "ws://" .. prefs.ip .. ":" .. prefs.port,
    deflate = false
  }

  socket:connect()
end

function connection.sendCommand(callback, cmd, args)
  --[[
  -- I have tried to implement this using coroutines, but Aseprite always
  -- crashes without any debug info, so let's just work with a callback.
  --]]
  if not connected then
    initSocket()
    os.execute("sleep 0.1")
  end

  socketCallback = callback

  if args == nil then
    args = {}
  end
  args["command"] = cmd
  message = json.encode(args)

  socket:sendText(message)
end

return connection
