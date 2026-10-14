-- Player settings (design doc §9b): volumes, display options and key
-- bindings, kept in settings.sav in the LÖVE save directory (the same table
-- format as the save slots, see src.save). Shared by every profile.
local audio = require("src.audio")
local input = require("src.input")
local save = require("src.save")

local settings = {}

local FILE = "settings.sav"

local DEFAULTS = {
  masterVolume = 0.8,
  musicVolume = 0.7,
  sfxVolume = 0.8,
  fullscreen = false,
  vsync = true,
  postfx = true, -- bloom, colour grading and the menu's warp
  showFps = false,
  pauseOnFocusLoss = true,
  lastSlot = false, -- the profile played last (Continue on the title screen)
}

local values = {}

local function apply()
  audio.setVolumes(values.masterVolume, values.musicVolume, values.sfxVolume)
  require("src.render").post = values.postfx
  local overlay = package.loaded["lib.overlayStats"]
  if overlay then
    overlay.isActive = values.showFps
  end
  local fs = love.window.getFullscreen()
  if fs ~= values.fullscreen then
    love.window.setFullscreen(values.fullscreen, "desktop")
  end
  local vs = love.window.getVSync() ~= 0
  if vs ~= values.vsync then
    love.window.setVSync(values.vsync and 1 or 0)
  end
end

function settings.load()
  local saved
  if love.filesystem.getInfo(FILE) then
    local ok, text = pcall(love.filesystem.read, FILE)
    saved = ok and save.decode(text) or nil
  end
  saved = saved or {}
  for k, v in pairs(DEFAULTS) do
    if type(saved[k]) == type(v) or (k == "lastSlot" and type(saved[k]) == "number") then
      values[k] = saved[k]
    else
      values[k] = v
    end
  end
  input.load(saved.bindings)
  apply()
end

function settings.save()
  local t = {}
  for k, v in pairs(values) do
    t[k] = v
  end
  t.bindings = input.bindings()
  love.filesystem.write(FILE, save.encode(t))
end

function settings.get(key)
  return values[key]
end

-- Changes a setting, applies it and writes the file
function settings.set(key, value)
  values[key] = value
  apply()
  settings.save()
end

-- Puts the volumes and display options back to their defaults (not the keys)
function settings.resetDefaults()
  for k, v in pairs(DEFAULTS) do
    if k ~= "lastSlot" then
      values[k] = v
    end
  end
  apply()
  settings.save()
end

function settings.resetBindings()
  input.load(nil)
  settings.save()
end

return settings
