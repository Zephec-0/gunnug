-- Draws the game to a low-res canvas and scales it to the window by the
-- largest whole-number factor that fits, letterboxing any leftover space.
local config = require("src.config")

local render = { scale = 1, offsetX = 0, offsetY = 0 }

local W, H = config.VIRTUAL_W, config.VIRTUAL_H
local BACKGROUND = { 0.08, 0.06, 0.13 }

local canvas

function render.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  canvas = love.graphics.newCanvas(W, H)
  render.layout()
end

function render.layout()
  local ww, wh = love.graphics.getDimensions()
  render.scale = math.max(1, math.floor(math.min(ww / W, wh / H)))
  render.offsetX = math.floor((ww - W * render.scale) / 2)
  render.offsetY = math.floor((wh - H * render.scale) / 2)
end

function render.beginWorld()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(BACKGROUND)
end

function render.endWorld()
  love.graphics.setCanvas()
  love.graphics.clear(0, 0, 0)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, render.offsetX, render.offsetY, 0, render.scale, render.scale)
end

-- Window pixels -> canvas pixels
function render.toVirtual(sx, sy)
  return (sx - render.offsetX) / render.scale, (sy - render.offsetY) / render.scale
end

-- Canvas pixels -> window pixels
function render.toScreen(vx, vy)
  return vx * render.scale + render.offsetX, vy * render.scale + render.offsetY
end

return render
