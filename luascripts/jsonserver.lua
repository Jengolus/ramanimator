
--[[
This module contains a generic server that sends and accepts JSON data
as a WebSocket implementation. I chose WebSocket because it cleanly
handles the problem of message length and some programs I use don't
have pure sockets. The server should still be able to handle bare JSON
data if no handshake is performed, but that is unsupported.

Other modules can add callbacks to this server so they can receive data
without needing several servers.

This module was tested using a Python client and Aseprite.
--]]

local jsonserver = {}
jsonserver.cmdCallbacks = {}

local debugging = require("debugging")

local dbgout = debugging.getBuffer("jsonserver", 1)

local json = require("json")
local base64 = require("base64")
local sha = require("sha2")

local server = nil
local port = nil

local sockets = {}
local handshakes = {} -- nil -> No message received, true -> Websocket
local receiveCallbacks = {}
local errorCallbacks = {}

local nextSocketId = 1

local function sPrint(id, msg, isError)
	-- Print with prepended socket id
	local prefix = "Socket " .. id
	if isError then
		console:error(prefix .. " Error: " .. tostring(msg))
	else
		dbgout:print(prefix .. ": " .. tostring(msg))
	end
end

local function socketClose(id)
	-- Closes a socket
	console:log("Closing socket " .. tostring(id))
	local sock = sockets[id]
	sockets[id] = nil
	sock:remove(receiveCallbacks[id])
	sock:remove(errorCallbacks[id])
	sock:close()
end

local function isWebsocketHandshake(request)
	-- Check for the presence of required WebSocket headers
	local key = request:match("Sec%-WebSocket%-Key:%s*(%S+)")
	local upgrade = request:match("Upgrade: websocket")
	local connection = request:match("Connection: Upgrade")

	if key and upgrade and connection then
		return key -- Return the key if it's a valid handshake
	end

	return nil -- Not a valid handshake
end

local function respondToHandshake(key)
	-- Calculate the response key
	local hashed_key = sha.hex2bin(sha.sha1(key .. "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	local response_key = base64.encode(hashed_key)

	-- Build the response
	local response = "HTTP/1.1 101 Switching Protocols\r\n" ..
	"Upgrade: websocket\r\n" ..
	"Connection: Upgrade\r\n" ..
	"Sec-WebSocket-Accept: " .. response_key .. "\r\n\r\n"

	return response
end

local function printByter2l(data)
	-- Print byte as 0 and 1, starting with the heighest
	local ret = ""
	for i = 7, 0, -1 do
		ret = ret .. tostring((data >> i) & 1)
	end
	console:log(ret)
end

local function receiveFrame(sock, id)
	-- Receive the header
	local data = sock:receive(2)

	if data == nil then
		-- Connection closed, but without a close frame
		return nil, "closeframe"
	end

	--printByter2l(data:byte(1))
	--printByter2l(data:byte(2))
	
	local fin  = (data:byte(1) & 128) ~= 0
	local rsv1 = (data:byte(1) & 64) ~= 0
	local rsv2 = (data:byte(1) & 32) ~= 0
	local rsv3 = (data:byte(1) & 16) ~= 0
	local opcode = data:byte(1) & 15

	if rsv1 or rsv2 or rsv3 then
		console:error("Message requires unimplemented behaviour: " .. tostring(fin) .. tostring(rsv1) .. tostring(rsv2) .. tostring(rsv3))
	end

	local pingpong = false

	if opcode == 8 then
		return nil, "closeframe"
	elseif opcode == 9 then
		pingpong = "ping"
	elseif opcode == 10 then
		pingpong = "pong"
	elseif opcode == 0 then
		-- Continuation frame. We only accept text anyway.
	elseif opcode ~= 0x1 then
		console:error("Message has unsupported opcode " .. tostring(opcode))
		return nil, nil
	end

	local length = data:byte(2) & 127 -- Get the length of the payload
	local hasMask = (data:byte(2) & 128) ~= 0

	local maskingKey = ""

	if length == 126 then
		data = sock:receive(2)
		length = data:byte(1) * 256 + data:byte(2)
	elseif length == 127 then
		-- Can Lua even handle such large integers?
		data = sock:receive(8)
		length = (((((((data:byte(1) * 256) + data:byte(2)) * 256 + data:byte(3)) * 256 + data:byte(4)) * 256 + data:byte(5)) * 256 + data:byte(6)) * 256 + data:byte(7)) * 256 + data:byte(8) -- Handle as necessary
	end

	if hasMask then
		-- Extract the masking key
		maskingKey = sock:receive(4)
	else
		-- For completeness only, this is the server.
		local null = string.char(0)
		maskingKey = null .. null .. null .. null
	end

	--console:log("Is final frame: " .. tostring(fin))
	--console:log("Expected frame length: " .. tostring(length))

	-- Decode the message
	local message = ""
	while #message < length do
		data = sock:receive(length - #message)
		--console:log("data " .. tostring(data))

		for i = 1, #data do
			local byte = data:byte(i) ~ maskingKey:byte(((i - 1) % 4) + 1)
			message = message .. string.char(byte)
		end
	end
	--console:log("Received frame length: " .. tostring(#message))

	if pingpong then
		return message, pingpong
	end

	return message, nil, fin
end

local function receiveWebsocket(sock, id) 
	-- Receive a WebSocket message. Only activates after the handshake.
	-- Dynamically aims to get the correct lenght and waits for additional
	-- frames.
	local data, frame, extra = "", nil, nil

	local fin = false
	while not fin do
		frame, extra, fin = receiveFrame(sock, id)

		if extra then
			return nil, extra
		end

		--console:log("Received frame of length " .. tostring(#frame))

		data = data .. frame
	end

	return data
end

local function receivePlain(sock, id) 
	-- Receive a non-WebSocket message. For handshakes or when the client
	-- doesn't want a WebSocket. This does not have any length control
	-- mechanism, so use a WebSocket instead.
	local data = "" -- Total received data

	while true do
		raw_data, err = sock:receive(4096)

		--console:log("raw receive " .. tostring(raw_data) .. " " .. tostring(err))

		-- Handle possible errors
		if not raw_data then
			if err == "disconnected" or err == "unknown error" or err == "temporary failure" then
				break
			else
				console:log("Unexpected end when receiving data: " .. err)
				break
			end
		end

		data = data .. raw_data
	end

	if #data == 0 then
		return nil, err
	end

	return data, err
end

local function receiveAll(sock, id)
	--[[
	-- For the first receive, get everything and check whether it is a
	-- WebSocket handshake. If so, answer accordingly. Otherwise, expect
	-- plain JSON without any length control (not recommended).
	--
	-- Going forth, expect to receive JSON data in the form of a table with
	-- the actual command provided with the key "command". If something else
	-- is transmitted, return such a dict where "command" contains what was
	-- received.
	--]]
	local data, extra, err = nil, nil, nil

	if handshakes[id] then
		data, extra, err = receiveWebsocket(sock, id)
		-- data is already decoded at this point

		-- This is a WebSocket message. Decode it.
		--data, extra = decodeWebSocketMessage(data)

		-- Filter out opcodes etc
		if extra ~= nil then
			if extra == "closeframe" then
				sock:send(string.char(0x88, 0x00))
				sPrint(id, "Received close frame")
				socketClose(id)

				return "_opcode", nil
			elseif extra == "ping" then
				sock:send(string.char(0x8A, 0x00))
				if message ~= nil then
					sPrint(id, "Received ping: " .. tostring(message))
				else
					sPrint(id, "Received ping")
				end
				return "_opcode", nil
			elseif extra == "pong" then
				if message ~= nil then
					sPrint(id, "Received pong: " .. tostring(message))
				else
					sPrint(id, "Received pong")
				end
				return "_opcode", nil
			else
				sPrint(id, "Unknown opcode: " .. tostring(opcode), true)
			end
		end
	else
		-- This also receives handshakes.
		data, err = receivePlain(sock, id)
	end

	if data == nil then
		return data, err
	end

	-- Apparently, I don't need to explicitly decode this as UTF-8 because
	-- Lua doesn't acknowledge that anyway.

	-- Is this the first received message?
	if handshakes[id] == nil then
		--console:log("Full message: " .. tostring(data))
		-- Is it a WebSocket handshake?
		local key = isWebsocketHandshake(data)
		if key then
			local response = respondToHandshake(key)
			console:log("Client does want a WebSocket, answer accordingly.")
			--console:log(response)

			handshakes[id] = true
			sock:send(response)
			return "_handshake", nil
		else
			-- The client does not want a WebSocket, so fall through.
			console:log("Client does not want a WebSocket, expect plain JSON.")
			handshakes[id] = false
			-- Fall through
		end
	end

	sPrint(id, "Full message: " .. tostring(data))

	local command = json.decode(data)
	if not command then
		-- This wasn't valid JSON
		console:log("Received message isn't valid JSON")
		command = data
	end

	-- If this wasn't actually JSON or just a plain command, pretend it was
	-- a command without arguments.
	if type(command) ~= "table" then
		command = { command = command }
	end

	command._raw = data

	return command
end

function sendInChunks(sock, content, chunkSize)
	-- A way to send large messages without the WebSocket. Deprecated
	if chunkSize == nil then
		chunkSize = 4096 -- Arbitrary for me
	end

	local start = 1
	local txtLength = #content

	while start <= txtLength do
		local block = content:sub(start, start + chunkSize - 1)
		local success, err = sock:send(block)

		if not success then
			print("Error sending data: " .. err)
			return
		end

		start = start + chunkSize
	end
end

function sendFrame(ws, message, isFinal, isCont)
    local replyMessage = message
		--console:log("Reply: " .. message)
    local byteLength = #replyMessage
		local firstByte = 0

		if isFinal then
			firstByte = firstByte + 128
		end

		if not isCont then
			firstByte = firstByte + 1
		end

    local frame = string.char(firstByte) -- FIN bit + opcode

    -- Prepare the payload length
    if byteLength <= 125 then
        frame = frame .. string.char(byteLength)
    elseif byteLength <= 65535 then
        frame = frame .. string.char(126) .. string.char(byteLength >> 8) .. string.char(byteLength % 256)
    else
        -- For lengths > 65535, use 64-bit representation
				-- Though apparently, I just shouldn't send frames this large.
        frame = frame .. string.char(127)
        for i = 1, 8 do
            frame = frame .. string.char(byteLength & 0xFF)
            byteLength = byteLength >> 8
        end
    end

    -- Append the actual message
    frame = frame .. replyMessage

    -- Send the reply through the websocket
    ws:send(frame)

		local function sleep (a) 
				local sec = tonumber(os.clock() + a); 
				while (os.clock() < sec) do 
				end 
		end

		-- We need some delay, otherwise it looses frames.
		if not isFinal then
			--os.execute("sleep 0.1") -- Works, and opens a window on my machine
			sleep(0.1)
		end
end

function replyToWebsocket(ws, message)
  -- Sends a message in frames of 32768 bytes max
  local maxFrameSize = 2*32768 - 5
  maxFrameSize = 32768
  local remaining = #message
  local offset = 1
	local isCont = false

  while remaining > 0 do
    -- Determine the size of the next submessage
    local submessageSize = math.min(maxFrameSize, remaining)

    -- Extract the submessage
    local submessage = message:sub(offset, offset + submessageSize - 1)

    -- Determine if this is the final frame
    local isFinal = (remaining - submessageSize) == 0
		--console:log("Remaining: " .. tostring(remaining))
		--console:log(tostring(isFinal) .. " " .. tostring(isCont))

    -- Send the frame
    sendFrame(ws, submessage, isFinal, isCont)

    -- Update the remaining bytes and offset
    remaining = remaining - submessageSize
    offset = offset + submessageSize
		isCont = true
  end

	--console:log("Sent everything")
end

function jsonserver.send(sockid, content)
	--[[
	-- Send a message back. Anything that isn't a string already will be
	-- converted to JSON automatically.
	--]]
	local sock = sockets[sockid]

	local txt = content

	if type(content) ~= "string" then
		txt = json.encode(content)
	end

	dbgout:print("Sending: ", txt)

	if handshakes[sockid] then
		replyToWebsocket(sock, txt)
	else
		-- Fallback for clients without WebSocket support.
		sendInChunks(sock, txt)
	end
end

local function socketError(id, err)
	-- Called when an error occurs on the socket
	-- On my machine, errors often just get received anyway.
	-- If this one gets called, the error code is always nil.
	sPrint(id, "In socketError: " .. tostring(err), true)
	console:error("On my machine, the nil error only happens when I open new sockets too quickly. Try using a persistent socket instead.")
	socketClose(id) -- If I don't close it on nil, it continues forever.
end

local function socketReceived(id)
	-- Callback when the socket receives a message
	local sock = sockets[id]
	if not sock then return end

	local msg, err = receiveAll(sock, id)
	if msg == "_handshake" or msg == "_opcode" then
		-- The message was just for the protocol, not a command
		return
	end
	--console:log("Received: " .. tostring(msg) .. " " .. tostring(err))

	if err == "disconnected" then
		-- Python always sends this when it closes the connection, I don't
		-- know why it ends up here.
		sPrint(id, "received a 'disconnected'.")
		socketClose(id)
		return nil, err
	elseif err == "unknown error" then
		sPrint(id, "received the 'unknown error' I receive when I close the Python window while the connection is still open.")
		socketClose(id)
		return nil, err
	end

	if msg then
		local command = msg["command"]
		--sPrint(id, "Received command: " .. tostring(command):match("^(.-)%s*$"))

		local answer = nil

		if command == "getServerVersion" then
			answer = "1.0"
		else
			-- Check all callbacks whether somebody knows this command
			for _, callback in ipairs(jsonserver.cmdCallbacks) do
				answer = callback(command, msg, id) -- Pass socket id for callbacks
				if answer ~= nil then
					break
				end
			end
		end

		if answer == nil then
			console:error("Unknown command: " .. tostring(command))
			answer = {status="Unknown command: " .. tostring(command)}
		end

		jsonserver.send(id, answer)
	else
		if err == "disconnected" then
			socketClose(id)
			return
		end

		console:log("Error in ST_received: " .. tostring(err) .. " for command " .. tostring(command))

		if err ~= socket.ERRORS.AGAIN then
			sPrint(id, err, true)
			socketClose(id)
		end
	end
end

local function socketAccept()
	-- Callback when something connects to the server.
	local sock, err = server:accept()
	if err then
		sPrint("Accept", err, true)
		return
	end

	local id = nextSocketId
	nextSocketId = id + 1
	sockets[id]  = sock
	handshakes[id] = nil
	receiveCallbacks[id] = sock:add("received", function() socketReceived(id) end)
	errorCallbacks[id]   = sock:add("error", function() socketError(id) end)
	sPrint(id, "Connected")
end

function jsonserver.registerCommandCallback(callback)
	-- Whenever a command is received, call the callback function with it.
	-- The addition is irreversible.
	-- If the module does not know the provided command, it returns nil,
	-- otherwise the return table.
	jsonserver.cmdCallbacks[#jsonserver.cmdCallbacks + 1] = callback
end

local port = 8446
while not server do
	-- Open the server port
	server, err = socket.bind(nil, port)
	if err then
		if err == socket.ERRORS.ADDRESS_IN_USE then
			port = port + 1
		else
			sPrint("Bind", err, true)
			break
		end
	else
		local ok
		-- Start to listen
		ok, err = server:listen()
		if err then
			server:close()
			sPrint("Listen", err, true)
		else
			console:log("mGBA JSON server listening on port " .. port)
			server:add("received", socketAccept)
		end
	end
end

return jsonserver
