-- 2D lighting (Dead Cells-style mood): each frame a light map is built on its
-- own low-res canvas — cleared to the scene's ambient colour, with soft
-- radial lights added on top — and then multiplied over the finished scene.
-- Things that should glow regardless (eyes, flames, sparks, bullets) are
-- drawn after the light map as "emissive".
local config = require("src.config")

local lighting = {}

local W, H = config.VIRTUAL_W, config.VIRTUAL_H
local canvas
local glow -- radial falloff sprite
local lights = {}
local ambient = { 1, 1, 1 }

function lighting.load()
  canvas = love.graphics.newCanvas(W, H)
  local size = 128
  local data = love.image.newImageData(size, size)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local dx, dy = (x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1
      local d = math.min(1, math.sqrt(dx * dx + dy * dy))
      local a = (1 - d) * (1 - d) -- soft quadratic falloff
      data:setPixel(x, y, a, a, a, 1)
    end
  end
  glow = love.graphics.newImage(data)
  glow:setFilter("linear", "linear")
end

-- Starts a new frame of lights with the given ambient colour
function lighting.begin(ambientColor)
  lights = {}
  ambient = ambientColor or { 1, 1, 1 }
end

-- Adds a light in world coordinates. intensity scales the colour.
function lighting.add(x, y, radius, r, g, b, intensity)
  intensity = intensity or 1
  lights[#lights + 1] = { x = x, y = y, radius = radius, r = r * intensity, g = g * intensity, b = b * intensity }
end

-- Renders the light map for the current camera. Call before drawing the
-- scene (it switches canvases).
function lighting.render(camX, camY)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.clear(ambient[1], ambient[2], ambient[3], 1)
  love.graphics.setBlendMode("add")
  local gw = glow:getWidth()
  for _, l in ipairs(lights) do
    local s = l.radius * 2 / gw
    love.graphics.setColor(l.r, l.g, l.b)
    love.graphics.draw(glow, l.x - camX - l.radius, l.y - camY - l.radius, 0, s, s)
  end
  love.graphics.pop()
end

-- Multiplies the light map over everything drawn so far on the current canvas
function lighting.apply()
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setBlendMode("multiply", "premultiplied")
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, 0, 0)
  love.graphics.pop()
end

return lighting
