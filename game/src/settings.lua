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
  dither = 0, -- anti-banding noise: 0 off ... 5 (see render.DITHER_NAMES)
  -- The visuals panel (F4, see src.visuals)
  visDitherAmt = 1,
  visBloom = 0.6,
  visBright = 1,
  visGamma = 1,
  visContrast = 0,
  visSat = 1,
  visVig = 1,
  visAberr = 1,
  showFps = false,
  pauseOnFocusLoss = true,
  lastSlot = false, -- the profile played last (Continue on the title screen)
  -- The crosshair (see src.hud.drawCrosshair)
  crosshairStyle = "plus", -- plus, circle, dot or x
  crosshairColor = 1, -- which of hud.CROSSHAIR_COLORS
  crosshairOpacity = 0.9,
  crosshairThickness = 1, -- px
  crosshairLength = 3, -- px of each arm (the circle's ring grows by it)
  crosshairGap = 2, -- px between the centre and the arms
  crosshairOutline = true, -- a dark edge so it shows on bright ground
}

local values = {}

local function apply()
  audio.setVolumes(values.masterVolume, values.musicVolume, values.sfxVolume)
  require("src.render").post = values.postfx
  local render = require("src.render")
  render.dither = values.dither
  render.bloom = values.visBloom
  local adj = render.adj
  adj.ditherAmt, adj.bright, adj.gamma = values.visDitherAmt, values.visBright, values.visGamma
  adj.contrast, adj.sat, adj.vig, adj.aberr = values.visContrast, values.visSat, values.visVig, values.visAberr
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

-- Changes a setting and applies it without writing the file (a slider mid-drag)
function settings.preview(key, value)
  values[key] = value
  apply()
end

-- Puts the visuals panel's sliders back to their defaults
function settings.resetVisuals()
  for k, v in pairs(DEFAULTS) do
    if k == "dither" or k:sub(1, 3) == "vis" then
      values[k] = v
    end
  end
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
