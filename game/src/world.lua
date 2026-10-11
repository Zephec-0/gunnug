-- Pixel terrain: a grid of material ids rendered through an ImageData.
-- Each terrain pixel is one game pixel.
local materials = require("src.materials")

local AIR = materials.AIR
local solid = materials.solid
local defs = materials.defs

local World = {}
World.__index = World

-- Deterministic per-pixel noise so recolouring a pixel gives the same shade
local function noise(x, y)
  local n = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
  return n - math.floor(n)
end

function World.new(width, height)
  local self = setmetatable({}, World)
  self.width = width
  self.height = height
  self.cells = {}
  for i = 1, width * height do
    self.cells[i] = AIR
  end
  self.imageData = love.image.newImageData(width, height)
  self.image = love.graphics.newImage(self.imageData)
  self.dirty = false
  return self
end

function World:inBounds(x, y)
  return x >= 0 and y >= 0 and x < self.width and y < self.height
end

-- Outside the world counts as bedrock so nothing escapes
function World:get(x, y)
  if x < 0 or y < 0 or x >= self.width or y >= self.height then
    return materials.BEDROCK
  end
  return self.cells[y * self.width + x + 1]
end

function World:isSolid(x, y)
  return solid[self:get(x, y)]
end

-- Raw write without recolouring; use for bulk generation, then call repaintAll()
function World:setRaw(x, y, id)
  if self:inBounds(x, y) then
    self.cells[y * self.width + x + 1] = id
  end
end

function World:fillRect(x0, y0, x1, y1, id)
  for y = y0, y1 do
    for x = x0, x1 do
      self:setRaw(x, y, id)
    end
  end
end

-- Runtime write: updates the cell and recolours it and its neighbours
function World:set(x, y, id)
  if not self:inBounds(x, y) then
    return
  end
  self.cells[y * self.width + x + 1] = id
  for dy = -1, 1 do
    for dx = -1, 1 do
      self:repaint(x + dx, y + dy)
    end
  end
end

function World:colorAt(x, y)
  local def = defs[self:get(x, y)]
  if not def.solid then
    return 0, 0, 0, 0
  end
  local base = def.color
  if def.topColor and not self:isSolid(x, y - 1) then
    base = def.topColor
  end
  local v = (noise(x, y) - 0.5) * 2 * def.variation
  if def.bands then
    v = v + math.sin(y * 0.7 + math.sin(x * 0.05) * 2) * def.bands
  end
  if def.grain and x % 4 == 0 then
    v = v - 0.12
  end
  if def.brick then
    local row = math.floor(y / 4)
    if y % 4 == 0 or (x + (row % 2) * 4) % 8 == 0 then
      v = v - 0.18 -- mortar
    end
  end
  return base[1] + v, base[2] + v, base[3] + v, 1
end

function World:repaint(x, y)
  if self:inBounds(x, y) then
    self.imageData:setPixel(x, y, self:colorAt(x, y))
    self.dirty = true
  end
end

function World:repaintAll()
  for y = 0, self.height - 1 do
    for x = 0, self.width - 1 do
      self.imageData:setPixel(x, y, self:colorAt(x, y))
    end
  end
  self.dirty = true
end

-- First solid pixel at or below fromY in column x
function World:findGround(x, fromY)
  for y = fromY, self.height - 1 do
    if self:isSolid(x, y) then
      return y
    end
  end
  return self.height
end

function World:refresh()
  if self.dirty then
    self.image:replacePixels(self.imageData)
    self.dirty = false
  end
end

function World:draw()
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.image, 0, 0)
end

return World
