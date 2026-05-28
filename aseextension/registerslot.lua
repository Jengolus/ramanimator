-- Plugin Script for Aseprite
-- This creates a dialog to input variables: name, address, width, height, layout, order

local emulator = require("emulator")

local dlg = Dialog("Register slot")

if ra_lastSlot == nil then
    ra_lastSlot = {}
end

-- Add controls for user inputs
dlg:entry{
    id = "name",
    label = "Name: ",
    text = ra_lastSlot.name or "",
}
dlg:entry{
    id = "address",
    label = "Address: 0x",
    text = ra_lastSlot.address or "0",
}
dlg:number{
    id = "width",
    label = "Width: ",
    text = ra_lastSlot.width and tostring(ra_lastSlot.width) or "1",
}
dlg:number{
    id = "height",
    label = "Height: ",
    text = ra_lastSlot.height and tostring(ra_lastSlot.height) or "1",
}
dlg:number{
    id = "layout",
    label = "Layout: ",
    text = ra_lastSlot.layout and tostring(ra_lastSlot.layout) or "0",
}
dlg:number{
    id = "order",
    label = "Order: ",
    text = ra_lastSlot.order and tostring(ra_lastSlot.order) or "",
}
dlg:number{
    id = "palette",
    label = "Palette: ",
    text = ra_lastSlot.palette and tostring(ra_lastSlot.palette) or "-1",
}

dlg:button{ 
    id = "ok", 
    text = "OK", 
}

dlg:button{ id = "cancel", text = "Cancel", onclick = function() dlg:close() end }

dlg:show()

local data = dlg.data

ra_lastSlot.name = data.name
ra_lastSlot.address = data.address
ra_lastSlot.width = data.width
ra_lastSlot.height = data.height
ra_lastSlot.layout = data.layout
ra_lastSlot.order = data.order
ra_lastSlot.palette = data.palette

local name = data.name:gsub("%W", "")  -- Remove non-word characters

local address = math.floor(tonumber(data.address, 16))
local width = math.floor(data.width)
local height = math.floor(data.height)
local layout = math.floor(data.layout)
local order = data.order -- Allowed to be a float or nil
local palette = math.floor(data.palette)
if palette == -1 then
    palette = nil
end

emulator.sendCommand(emulator.printAnswer, "registerSlot", {name=name, address=address, width=width, height=height, layout=layout, order=order, palette=palette, kind="tile"})

