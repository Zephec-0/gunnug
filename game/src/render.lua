-- Draws the game to a low-res canvas and scales it to fill the window.
--
-- When the window isn't a whole multiple of the canvas (e.g. 400x225 into
-- 1920x1080 = 4.8x), plain nearest-neighbour scaling makes some pixels wider
-- than others. Instead the canvas is first blown up by a whole number with
-- nearest-neighbour (crisp), then smoothly scaled down the small remaining
-- amount — "sharp bilinear" scaling, which keeps every pixel the same size.
local config = require("src.config")

local render = { scale = 1, offsetX = 0, offsetY = 0 }

local W, H = config.VIRTUAL_W, config.VIRTUAL_H
local BACKGROUND = { 0.08, 0.06, 0.13 }

local canvas
local upscaled -- intermediate canvas at a whole-number multiple
local upscale = 0

function render.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.graphics.setLineStyle("rough") -- crisp, un-antialiased pixel lines
  canvas = love.graphics.newCanvas(W, H)
  render.layout()
end

function render.layout()
  local ww, wh = love.graphics.getDimensions()
  render.scale = math.min(ww / W, wh / H)
  render.offsetX = math.floor((ww - W * render.scale) / 2)
  render.offsetY = math.floor((wh - H * render.scale) / 2)

  local whole = math.max(1, math.ceil(render.scale - 1e-6))
  if whole ~= upscale then
    upscale = whole
    upscaled = love.graphics.newCanvas(W * whole, H * whole)
    upscaled:setFilter("linear", "linear")
  end
end

function render.beginWorld()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(BACKGROUND)
end

function render.endWorld()
  love.graphics.setColor(1, 1, 1)
  if math.abs(render.scale - upscale) < 1e-6 then
    love.graphics.setCanvas()
    love.graphics.clear(0, 0, 0)
    love.graphics.draw(canvas, render.offsetX, render.offsetY, 0, render.scale, render.scale)
    return
  end
  love.graphics.setCanvas(upscaled)
  love.graphics.clear(0, 0, 0)
  love.graphics.draw(canvas, 0, 0, 0, upscale, upscale)
  love.graphics.setCanvas()
  love.graphics.clear(0, 0, 0)
  local s = render.scale / upscale
  love.graphics.draw(upscaled, render.offsetX, render.offsetY, 0, s, s)
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
