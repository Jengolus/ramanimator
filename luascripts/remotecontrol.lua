
--[[
This module serves as a remote control for the emulator, mostly to set up
button combinations, but also e.g. save states.
--]]

local remote = {}

local server = require("jsonserver")

local buttonQueue = {}
local framesToHold = 0
local framesToWait = 0
local memChecks = {}
local currentKey = 0

local isDone = true -- So the client can check whether all is done

function remote.queue(data)
	-- data is a list of lists
	--console:log("remote control")
	for i = 1, #data do
		table.insert(buttonQueue, data[i])
	end
	isDone = false
end

function remote.consumeQueue()
	-- If we are holding a button, wait to release it
	if framesToHold > 0 then
		framesToHold = framesToHold - 1
		if framesToHold == 0 then
			-- Unpress the key
			--console:log("Release key: " .. tostring(currentKey))
			emu:clearKey(currentKey)
		end

		return
	end

	-- Wait until the event is finished
	if framesToWait > 0 then
		framesToWait = framesToWait - 1
		return
	end

	-- If we are checking against memory, do so now
	if #memChecks > 0 then
		local flag = true
		for i = 1, #memChecks do
			addressToRead = memChecks[i][1]
			valueToAwait = memChecks[i][2]
			local val = emu:read8(addressToRead)

			if #memChecks[i] > 2 then
				-- The third arg is used if we need to read more than a single byte
				if memChecks[i][3] == "16" then
					val = emu:read16(addressToRead)
				else
					console:log("Unknown data type for memory check in remote:" .. tostring(memChecks[i][3]))
				end
			end

			if val == valueToAwait then
				-- At least one of the conditions is fulfilled
				memChecks = {}
				flag = false
				break
			end
		end

		if flag then
			-- Press the button again
			framesToWait = 10
			framesToHold = 5
			emu:addKey(currentKey)
			return
		end
	end

	-- Get the next event
	if #buttonQueue < 1 then
		isDone = true
		return
	end

	local nextEvent = buttonQueue[1]
	table.remove(buttonQueue, 1)

	local key = nextEvent[1]

	if key == "callback" then
		-- This is not a new key press, but we need to call a function.
		console:log("callback")

		callback = nextEvent[2]
		callback(nextEvent[3])
		return
	end

	if key == "a" then
		currentKey = 0
	elseif key == "b" then
		currentKey = 1
	elseif key == "select" then
		currentKey = 2
	elseif key == "start" then
		currentKey = 3
	elseif key == "right" then
		currentKey = 4
	elseif key == "left" then
		currentKey = 5
	elseif key == "up" then
		currentKey = 6
	elseif key == "down" then
		currentKey = 7
	elseif key == "r" then
		currentKey = 8
	elseif key == "l" then
		currentKey = 9
	else
		console:log("Unknown key: " + tostring(key))
		return
	end

	framesToWait = nextEvent[2]
	framesToHold = 5

	if #nextEvent > 2 then
		for i = 3, #nextEvent do
			table.insert(memChecks, nextEvent[i])
		end
	end

	--console:log("Pressing key: " .. tostring(currentKey) .. " " .. key)
	emu:addKey(currentKey)
end

function remote.isDone()
	return isDone
end

function remoteCommands(command, args)
	if command == "remoteControl" then
		local actions = args["actions"]
		remote.queue(actions)
		return {status="success"}

	elseif command == "isRemoteDone" then
		return {status="success", isDone=tostring(remote.isDone())}

	elseif command == "createSavestate" then
		emu:saveStateSlot(args.handle)
		return {status="success"}

	elseif command == "loadSavestate" then
		emu:loadStateSlot(args.handle)
		return {status="success"}
	end

	return nil
end

callbacks:add("frame", remote.consumeQueue)
server.registerCommandCallback(remoteCommands)

return remote
