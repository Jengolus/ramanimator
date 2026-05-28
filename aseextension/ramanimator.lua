
ramanimatorPreferences = nil
ramanimatorDefPrefs = {ip="localhost", port="8446"}

local function spriteActive()
  -- Can only change a sprite if there is one
  return app.sprite ~= nil
end

local function spriteExportable()
  -- Checks whether there is an active sprite and it can be sent to the
  -- emulator.
  local sprite = app.sprite

  if sprite == nil then
    return false
  end

  return true
end

local function runScript(f)
  local path = app.fs.joinPath(app.fs.userConfigPath, "extensions", "ramanimator", f) .. ".lua"

  return function()
    app.command.RunScript{ filename=path }
  end
end

function init(plugin)
  for key, val in pairs(ramanimatorDefPrefs) do
    if plugin.preferences[key] == nil then
      plugin.preferences[key] = val
    end
  end

  ramanimatorPreferences = plugin.preferences

  plugin:newMenuGroup{
    id="ramanimator_group",
    title="RAManimator",
    group="file_app"
  }

  plugin:newMenuSeparator{
    group="file_app"
  }

  plugin:newCommand{
    id="ramh_transmit",
    title="Send to emulator",
    group="ramanimator_group",
    onenabled=spriteExportable,
    onclick=runScript("transmit")
  }

  plugin:newCommand{
    id="ramh_importSlot",
    title="Import slot",
    group="ramanimator_group",
    onclick=runScript("importslot")
  }

  plugin:newCommand{
    id="ramh_importHook",
    title="Import hook",
    group="ramanimator_group",
    onclick=runScript("importhook")
  }

  plugin:newCommand{
    id="ramh_attachHook",
    title="Attach hook",
    group="ramanimator_group",
    onenabled=spriteActive,
    onclick=runScript("attachhook")
  }

  plugin:newCommand{
    id="ramh_updateHook",
    title="Update hook",
    group="ramanimator_group",
    onclick=runScript("updatehook")
  }

  plugin:newCommand{
    id="ramh_updateHookPalette",
    title="Update hook palette",
    group="ramanimator_group",
    onclick=runScript("updatehookpalette")
  }

  plugin:newCommand{
    id="ramh_registerSlot",
    title="Register slot",
    group="ramanimator_group",
    onclick=runScript("registerslot")
  }

  plugin:newCommand{
    id="ramh_unloadAnimations",
    title="Clear animations",
    group="ramanimator_group",
    onclick=runScript("unloadanimations")
  }

  plugin:newCommand{
    id="ramh_settings",
    title="Settings",
    group="ramanimator_group",
    onclick=runScript("settings")
  }
end

function exit(plugin)
  --print("Aseprite is closing ramanimator.")
end
