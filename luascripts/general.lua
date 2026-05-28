
--[[
Some generic, reuseable functions.
--]]

local general = {}

function general.tblContains(t, v)
  for _, val in pairs(t) do
    if val == v then return true end
  end
  return false
end

function general.countTbl(t)
  local cnt = 0
  for _, _ in pairs(t) do
    cnt = cnt + 1
  end

  return cnt
end

function general.printTable(tbl, prefix)
  if prefix == nil then
    prefix = ""
  end

  if #prefix > 5 then
    print("Recursion too deep")
    return
  end

  for k, val in pairs(tbl) do
    if type(val) == "table" then
      print(prefix .. "Table " .. tostring(k))
      general.printTable(val, prefix .. " ")
    else
      print(prefix .. tostring(k) .. " -> " .. tostring(val))

    end
  end
end

function general.tblRemoveElement(t, v)
  --[[
  Remove element v from list t, keeping it contiguous.
  --]]
  for index, val in ipairs(t) do
    if val == v then
      table.remove(t, index)
      return true
    end
  end

  return false
end

function general.getTileSize()
  -- How many bits per tile?
  if emu:platform() == C.PLATFORM.GB then
    return 16
  else
    return 32
  end
end

function general.getTileDepth()
  -- How many bits per pixel?
  if emu:platform() == C.PLATFORM.GB then
    return 2
  else
    return 4
  end
end

function general.tbl2str(tbl)
  -- Since tables cannot be table groupKeys, convert them to a string.
  local ret = ""
  local space = " "
  
  for i, val in ipairs(tbl) do
    if i == #tbl then
      space = ""
    end

    ret = ret .. string.format("%5d", val) .. space
  end

  return ret
end

return general
