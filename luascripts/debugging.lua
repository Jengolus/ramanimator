
--[[
The module provides a wrapper for mGBA's TextWrapper. It just
automatically passes all calls, except if logging is disabled, in which
case it does nothing.

What I really want: The logging threshold is not global, but per wrapper.
So it is passed to new(). I believe that a buffer should only really be
opened if something is written to it, but that I can do later on.
--]]

local debug = {}

local WrapTextBuffer = {}
WrapTextBuffer.__index = WrapTextBuffer

local function is_enabled(log_level)
  return (log_level or 0) > 0
end

-- Helper to determine if a key is callable on inner buffer
local function is_callable(obj, key)
  local v = obj[key]
  return type(v) == "function"
end

local function theVoid(...) end

-- Constructor
function WrapTextBuffer.new(handle, title, log_level)
  local wrapper = {
    handle = handle,
    title = title,
    __inner = 0, -- nil ends in recursion
    log_level = log_level,
  }

  -- metatable to forward method calls and property access
  local mt = {
    __index = function(tbl, key)
      if key == "is_enabled" then
        return function() return is_enabled(tbl.log_level) end
      end

      if not is_enabled(tbl.log_level) then return theVoid end

      -- If we have to do something, ensure there actually is a buffer for
      -- that handle.
      -- We delay this so we don't have a bunch of empty buffers floating
      -- around.
      if tbl.__inner == 0 then
        local fresh = console:createBuffer(tbl.handle)
        --print("Debug:", tbl.handle, "became a buffer to call", tostring(key))
        fresh:setName(tbl.title)
        tbl.__inner = fresh
      end

      local class_method = WrapTextBuffer[key]
      if class_method ~= nil then return class_method end

      local inner = tbl.__inner
      -- if enabled and inner has a function, return a bound function that calls it
      if is_callable(inner, key) then
        -- return a function that calls inner:key(...) preserving colon semantics
        return function(_, ...)
          -- allow both wrapper:method(...) and wrapper.method(wrapper, ...)
          -- call inner:key(inner, ...)
          return inner[key](inner, ...)
        end
      end

      -- If disabled and inner has a function, return a no-op that returns nil (or choose defaults)
      if is_callable(inner, key) then
        return function() end
      end

      -- If it's a property on inner, forward its value in either mode
      local val = inner[key]
      if val ~= nil then
        return val
      end

      -- fallback to methods/fields on the wrapper itself (if any)
      return WrapTextBuffer[key]
    end,

    --[[
    -- TextWrapper does not have attributes, so this is redundant.
    __newindex = function(tbl, key, value)
      local inner = tbl.__inner
      -- write through properties to inner if they exist there; otherwise store on wrapper
      if inner[key] ~= nil then
        inner[key] = value
      else
        rawset(tbl, key, value)
      end
    end,
    --]]

    __tostring = function(tbl)
      return tostring(tbl.__inner)
    end,
  }

  return setmetatable(wrapper, mt)
end

function WrapTextBuffer:print(...)
  local args = {...}
  for i=1,#args do
    args[i] = tostring(args[i])
  end

  local line = table.concat(args, " ")

  return self.__inner:print(line .. "\n")
end

local bufferTable = {}

function debug.getBuffer(handle, logLevel, title)
  if not logLevel then logLevel = 1 end
  if not title then title = handle end

  local old = bufferTable[handle]

  if old then
    --old:setName(title)
    return old
  end

  local fresh = WrapTextBuffer.new(handle, title, logLevel)

  bufferTable[handle] = fresh
  return fresh
end

return debug
