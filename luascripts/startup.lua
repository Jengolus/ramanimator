
--[[
The entry point that loads all the scripts relevant scripts.
--]]

if _VERSION < "Lua 5.3" then
	console:error("Your emulator is linked to " .. _VERSION .. ", but the scripts require at least Lua 5.3. You will need to try and link mGBA against a higher Lua version.")
	return
end

local server = require("jsonserver")
local dbg = require("debugging")
local memory = require("memory")
local ramanimator = require("ramanimator/ramanimator")
local remote = require("remotecontrol")
