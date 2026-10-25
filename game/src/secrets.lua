-- Everything hidden in the world that the hunter can use with E, drawn and lit alongside the events
-- (src.events calls these where it calls the other secrets: the Buried Vault's door, the Deep's sealed floor).
-- Add a module here and it joins the lot.
local secrets = {}

local MODULES = { "relicdoor", "deepseal" }
local mods = {}

for i, name in ipairs(MODULES) do
  mods[i] = require("src." .. name)
end

function secrets.clear()
  for _, m in ipairs(mods) do
    m.clear()
  end
end

function secrets.update(dt, player)
  for _, m in ipairs(mods) do
    m.update(dt, player)
  end
end

function secrets.interact(player)
  for _, m in ipairs(mods) do
    if m.interact(player) then
      return true
    end
  end
  return false
end

function secrets.draw(view)
  for _, m in ipairs(mods) do
    m.draw(view)
  end
end

function secrets.drawEmissive(view)
  for _, m in ipairs(mods) do
    m.drawEmissive(view)
  end
end

function secrets.addLights(lighting, view)
  for _, m in ipairs(mods) do
    m.addLights(lighting, view)
  end
end

function secrets.drawScreen(toScreen, font, player)
  for _, m in ipairs(mods) do
    m.drawScreen(toScreen, font, player)
  end
end

return secrets
