
--[[
Almost fully AI-generated.
Tables that have an __index get rendered as null to avoid recursion.
--]]

local json = {}

local json_string

function checkArray(value)
    if type(value) ~= "table" then
        return false  -- Not a table
    end

    local length = #value  -- Get the length of the table
    local key_count = 0

    -- Count the number of integer keys
    for k in pairs(value) do
        if type(k) == "number" and k % 1 == 0 then  -- Check if the key is an integer
            key_count = key_count + 1
        else
            return false
        end
    end

    -- Check if the length matches the number of integer keys
    return length == key_count
end

function json.encode(value)
    if type(value) == "table" then
        if value.__index ~= nil then
            return "null"
        end

        local json_parts = {}
        -- This counts sequential integer keys starting from one.
        local is_array = checkArray(value)

        for k, v in pairs(value) do
            if is_array then
                json_parts[#json_parts + 1] = json.encode(v)  -- For arrays, just encode the value
            else
                json_parts[#json_parts + 1] = '"' .. tostring(k) .. '":' .. json.encode(v)  -- For objects, encode key-value pairs
            end
        end

        if is_array then
            return "[" .. table.concat(json_parts, ",") .. "]"  -- Join array parts with commas
        else
            return "{" .. table.concat(json_parts, ",") .. "}"  -- Join object parts with commas
        end
    elseif type(value) == "string" then
        return '"' .. value:gsub('"', '\\"') .. '"'  -- Escape double quotes in strings
    elseif type(value) == "number" or type(value) == "boolean" then
        return tostring(value)  -- Convert numbers and booleans to string
    else
        return "null"  -- Convert nil to JSON null
    end
end

function skip_whitespace(pos)
    while pos <= #json_string and json_string:sub(pos, pos):match("%s") do
        pos = pos + 1
    end
    return pos
end

function parse_string(pos)
    local start_pos = pos + 1
    local end_pos = json_string:find('"', start_pos)
    while end_pos do
        if json_string:sub(end_pos - 1, end_pos - 1) ~= '\\' then
            break
        end
        end_pos = json_string:find('"', end_pos + 1)
    end
    if not end_pos then
        console:error("Unterminated string starting at position " .. start_pos)
    end
    local str = json_string:sub(start_pos, end_pos - 1):gsub('\\"', '"')
    return str, end_pos + 1
end

function parse_number(pos)
    local end_pos = pos
    while end_pos <= #json_string and json_string:sub(end_pos, end_pos):match("[%d%.%-]") do
        end_pos = end_pos + 1
    end
    local num_str = json_string:sub(pos, end_pos - 1)
    return tonumber(num_str), end_pos
end

function parse_object(pos)
    local obj = {}
    pos = pos + 1  -- Skip '{'
    while true do
        pos = skip_whitespace(pos)
        if json_string:sub(pos, pos) == '}' then
            return obj, pos + 1
        end
        local key, new_pos = parse_string(pos)
        pos = skip_whitespace(new_pos)
        if json_string:sub(pos, pos) ~= ':' then
            console:error("Expected ':' after key at position " .. pos)
        end
        pos = skip_whitespace(pos + 1)
        local value, new_pos = parse_value(pos)
        obj[key] = value
        pos = new_pos
        pos = skip_whitespace(pos)
        if json_string:sub(pos, pos) == '}' then
            return obj, pos + 1
        elseif json_string:sub(pos, pos) ~= ',' then
            console:error("Expected ',' or '}' at position " .. pos)
        end
        pos = pos + 1  -- Skip ','
    end
end

function parse_array(pos)
    local arr = {}
    pos = pos + 1  -- Skip '['
    while true do
        pos = skip_whitespace(pos)
        if json_string:sub(pos, pos) == ']' then
            return arr, pos + 1
        end
        local value, new_pos = parse_value(pos)
        arr[#arr + 1] = value
        pos = new_pos
        pos = skip_whitespace(pos)
        if json_string:sub(pos, pos) == ']' then
            return arr, pos + 1
        elseif json_string:sub(pos, pos) ~= ',' then
            console:error("Expected ',' or ']' at position " .. pos)
        end
        pos = pos + 1  -- Skip ','
    end
end

function parse_value(pos)
    local char = json_string:sub(pos, pos)

    if char == '"' then
        return parse_string(pos)
    elseif char:match("%d") or char == '-' then
        return parse_number(pos)
    elseif json_string:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif json_string:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif json_string:sub(pos, pos + 3) == "null" then
        return nil, pos + 4
    elseif char == '{' then
        return parse_object(pos)
    elseif char == '[' then
        return parse_array(pos)
    else
        console:error("Unexpected character at position " .. pos)
    end
end


function json.decode(input)
    json_string = input
    -- Start parsing from the beginning of the JSON string
    local result, pos = parse_value(skip_whitespace(1))

    if pos <= #json_string then
        console:error("Extra data after JSON value at position " .. pos)
        return nil -- Return this was invalid
    end
    return result
end

return json
