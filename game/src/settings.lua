-- Player settings (design doc §9b): volumes, display options and key
-- bindings, kept in settings.sav in the LÖVE save directory (the same table
-- format as the save slots, see src.save). Shared by every profile.
local audio = require("src.audio")
local input = require("src.input")
local save = require("src.save")

local settings = {}

-- Remaking the window (updateMode) empties every canvas, and the game keeps drawn-once pictures in many
-- (the item bar's slots, the bottle, sprites...). So every canvas made is remembered, and its picture is
-- kept across the change (kept canvases that are redrawn every frame just come back too).
local canvases = setmetatable({}, { __mode = "k" })
local newCanvas = love.graphics.newCanvas
love.graphics.newCanvas = function(...)
  local cv = newCanvas(...)
  canvases[cv] = true
  return cv
end

local function keepingCanvases(change)
  local kept = {}
  for cv in pairs(canvases) do
    -- (a canvas the game has released raises an error on any use: left out)
    local ok, data = pcall(function()
      if cv:getWidth() * cv:getHeight() <= 4096 * 4096 and cv:getMipmapMode() == "none" then
        return cv:newImageData()
      end
    end)
    if ok and data then
      kept[#kept + 1] = { cv, data }
    end
  end
  change()
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setShader()
  love.graphics.setScissor()
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(1, 1, 1, 1)
  for _, k in ipairs(kept) do
    local img = love.graphics.newImage(k[2])
    img:setFilter("nearest", "nearest")
    love.graphics.setCanvas(k[1])
    love.graphics.draw(img)
  end
  love.graphics.pop()
end

local FILE = "settings.sav"

local DEFAULTS = {
  masterVolume = 0.8,
  musicVolume = 0.7,
  sfxVolume = 0.8,
  fullscreen = false,
  borderless = false, -- windowed fullscreen: a borderless window the size of the desktop
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
local lastMode -- the display mode the window was last put in
local windowed -- { w, h, x, y } to go back to when windowed fullscreen ends

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
  -- Windowed fullscreen: the window loses its border and covers the display (real fullscreen wins over it).
  -- (Changing the window drops the canvases' pictures: see keepingCanvases.)
  local mode = settings.displayMode()
  if mode ~= lastMode then
    lastMode = mode
    if mode ~= "fullscreen" then
      local w, h, flags = love.window.getMode()
      flags.vsync = values.vsync and 1 or 0
      flags.fullscreen = false
      local dw, dh = love.window.getDesktopDimensions(flags.display)
      if mode == "borderless" then
        if not flags.borderless and w < dw and h < dh then
          local x, y = love.window.getPosition()
          windowed = { w = w, h = h, x = x, y = y }
        end
        flags.borderless, flags.x, flags.y = true, nil, nil
        keepingCanvases(function() love.window.updateMode(dw, dh, flags) end)
      else
        local wasBorderless = flags.borderless
        flags.borderless = false
        if windowed then
          flags.x, flags.y = windowed.x, windowed.y
          keepingCanvases(function() love.window.updateMode(windowed.w, windowed.h, flags) end)
        elseif wasBorderless or w >= dw or h >= dh then
          -- (a window as big as the screen is no window: a smaller one, centred)
          flags.x, flags.y = nil, nil
          keepingCanvases(function() love.window.updateMode(math.floor(dw * 0.67), math.floor(dh * 0.67), flags) end)
        else
          keepingCanvases(function() love.window.updateMode(w, h, flags) end)
        end
      end
    end
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

-- The display mode as one of three: "windowed", "borderless" (windowed fullscreen) or "fullscreen".
-- (Fullscreen keeps the other choice, so F11 goes back to it.)
function settings.displayMode()
  if values.fullscreen then
    return "fullscreen"
  end
  return values.borderless and "borderless" or "windowed"
end

function settings.setDisplayMode(mode)
  if mode == "fullscreen" then
    values.fullscreen = true
  else
    values.fullscreen = false
    values.borderless = mode == "borderless"
  end
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
