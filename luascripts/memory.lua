
--[[
-- Some generic memory manipulation functions, mostly to allow programs to
-- read / write memory.
--]]

local memory = {}

local server = require("jsonserver")
local base64 = require("base64")

function memory.writeRange(domain, address, data)
  --[[
  In some memory regions, mGBA does not allow writing single bytes, so we
  wrap the writes in this.
  --]]
  if emu:platform() == C.PLATFORM.GBA then
    -- These might not be all locations where this can be necessary.
    if address >= 0x06000000 and address < 0x08000000 then
      -- Write in chunks of 16 bits
      for i = 0, #data - 1, 2 do
        local num = data:byte(i + 1) + 256 * data:byte(i + 2)
        emu:write16(address + i, num)
      end

      -- Was there an odd number of bytes?
      -- Should also work if only one byte is written.
      if #data % 2 == 1 then
        local byte1 = emu:read8(address + #data - 2)
        local num = byte1 + 256 * data:byte(#data)
        emu:write16(address + #data - 2, num)
      end

      return
    end
  end

  -- Or the trivial case
  for i = 1, #data do
    emu:write8(address + i - 1, data:byte(i))
  end
end

function memory.searchMemoryDomain(mem, off1, off2, data, mask, verbose)
  --[[
  mem: The memory domain object to be searched
  off1: Search window start
  off2: Search window end (inclusive)
  data: Memory fingerprint to be searched for
  mask: List; data corresponding to indices that are non-nil will be
        ignored. The first byte may not be masked.
  verbose: Print status updates
  --]]
  if mask and mask[1] then
    console:error("Trying to search through memory with a mask on the first byte, which is not allowed.")
    mask[1] = nil
  end
  -- We do it in this complicated way to manage overlaps
  local hits = {}
  local occurences = {}

  for offset = off1, off2 do
    if verbose and offset % 0x00100000 == 0 then
      print("at", string.format("%x", offset))
    end
    local byte = mem:read8(offset)

    local delKeys = {}
    -- Check whether any possible occurence matches / is over
    for key, occ in pairs(occurences) do
      -- Does the next byte work or is it masked out?
      if (mask and mask[occ.byteAt]) or byte == data:byte(occ.byteAt) then
        -- Is this the whole sequence?
        if occ.byteAt == #data then
          table.insert(hits, occ.start)
          table.insert(delKeys, key)
        end
        -- Otherwise: Move on with the next occurence / byte
        occ.byteAt = occ.byteAt + 1
      else
        -- Not a match, remove
        table.insert(delKeys, key)
      end
    end

    for _, key in pairs(delKeys) do
      occurences[key] = nil
    end

    -- Check whether this might start a new occurence
    if byte == data:byte(1) then
      table.insert(occurences, {start=offset, byteAt=2})
    end
  end

  return hits
end

function memory.searchRam(data)
  console:log("Searching the RAM for a byte sequence of lenght " .. tostring(#data))
  if emu:platform() == C.PLATFORM.GB then
    -- This is small, just check the whole thing
    return memory.searchMemoryDomain(emu, 0x8000, 0xffff, data)
  else
    local hits = {}

    for name, domain in pairs(emu.memory) do
      if name:sub(1, 4) ~= "cart" then
        print("Looking through ", domain:name(), string.format("%x", domain:base()), string.format("%x", domain:bound() - 1))
        local locHits = memory.searchMemoryDomain(domain, domain:base(), domain:bound() - 1, data)
        print("Found", #locHits)

        for _, offset in pairs(locHits) do
          table.insert(hits, offset)
        end
      end
    end

    return hits
  end
end

function memory.searchCart(data, mask, domain)
  --[[
  Warning: The bound of cart0 is always reported as 0x8000 by mGBA, and it
  seems there is no way of checking for the actual size of the cartridge
  including all banks. The factor of 128 should be fine, but be aware!
  --]]
  console:log("Searching the cartridge for a byte sequence of lenght " .. tostring(#data))
  if emu:platform() == C.PLATFORM.GB then
    -- This is small, just check the whole thing
    local factor = 128
    return memory.searchMemoryDomain(emu.memory.cart0, emu.memory.cart0:base(), factor*emu.memory.cart0:bound() - 1, data, mask)
  else
    local hits = {}

    local domains = emu.memory
    local ignoreCheck = false

    if domain then
      domains = {}
      domains[domain] = emu.memory[domain]

      ignoreCheck = true

      if not domains[domain] then
        local options = ""
        for name, _ in pairs(emu.memory) do
          options = options .. " ".. name 
        end
        return {status= "Unknown domain " .. domain .. "; known options:" .. options}
      end
    end

    for name, domain in pairs(domains) do
      if ignoreCheck or name:sub(1, 4) == "cart" then
        print("Looking through ", domain:name(), string.format("%x", domain:base()), string.format("%x", domain:bound() - 1))
        local locHits = memory.searchMemoryDomain(domain, domain:base(), domain:bound() - 1, data, mask)
        print("Found", #locHits)

        for _, offset in pairs(locHits) do
          table.insert(hits, offset)
        end
      end
    end

    return hits
  end
end

function memoryCommands(command, args)
  --console:log("Module memory is checking whether it understands the command.")

  if command == "readCart" then
    local start = args["offset"]
    local length = args["length"]
    console:log("Reading 0x" .. string.format("%X", length) .. " bytes from cartridge starting from 0x" .. string.format("%X", start))
    local range = emu.memory.cart0:readRange(start, length)
    return { context = "Data read from cartridge", offset = start, data = base64.encode(range) }

  elseif command == "readRam" then
    local start = args["offset"]
    local length = args["length"]
    console:log("Reading 0x" .. string.format("%X", length) .. " bytes starting from 0x" .. string.format("%X", start))
    local range = emu:readRange(start, length)
    return { context = "Data read from RAM", offset = start, data = base64.encode(range) }

  elseif command == "writeRam" then
    console:log("writeRam " .. tostring(args["offset"]) .. "\t" .. tostring(args["data"]))
    local address = args["offset"]
    local data = base64.decode(args["data"])
    -- I am not aware of a better way.
    memory.writeRange(emu, address, data)

    return "success"

  elseif command == "writeCart" then
    console:log("writeCart " .. tostring(args["offset"]) .. "\t" .. tostring(args["data"]))
    local address = args["offset"]
    local data = base64.decode(args["data"])
    -- I am not aware of a better way.
    for offset = 1, #data do
      emu.memory.cart0:write8(address + offset - 1, data:byte(offset))
    end

    return "success"

  elseif command == "searchRam" then
    if args.data == nil then
      return {status="Argument data missing for command searchRam"}
    end

    local data = base64.decode(args["data"])
    local hits = memory.searchRam(data)

    return {status="success", offsets=hits}

  elseif command == "searchCart" then
    if args.data == nil then
      return {status="Argument data missing for command searchCart"}
    end

    local data = base64.decode(args["data"])
    local mask = nil
    if args.mask then
      -- The keys here must be integers, but JSON only supports string keys!
      mask = {}
      for k, v in pairs(args.mask) do
        mask[tonumber(k)] = v
      end
    end
    local domain = args["domain"]
    local hits = memory.searchCart(data, mask, domain)

    if hits.status then
      -- An error occured
      return hits
    end

    return {status="success", offsets=hits}
  end

  return nil
end

server.registerCommandCallback(memoryCommands)

return memory
