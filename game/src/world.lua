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

-- Terrain is shaded by how far each pixel is from open air: full brightness at
-- the edges, darker inside (lit rims around dark masses).
local SHADE_DEPTH = 14 -- pixels until full darkness
local SHADE_AMOUNT = 0.4 -- how much darker the deep interior gets

local function shadeFactor(depth)
  return 1 - math.min(depth - 1, SHADE_DEPTH) / SHADE_DEPTH * SHADE_AMOUNT
end

-- Distance (in pixels, 1 = touching air) to the nearest air straight up,
-- down, left or right, capped just past SHADE_DEPTH
function World:depthAt(x, y)
  local best = SHADE_DEPTH + 1
  for d = 1, best - 1 do
    if not self:isSolid(x, y - d) or not self:isSolid(x, y + d) or not self:isSolid(x - d, y) or not self:isSolid(x + d, y) then
      return d
    end
  end
  return best
end

-- Runtime write: updates the cell and re-shades everything it can affect
function World:set(x, y, id)
  if not self:inBounds(x, y) then
    return
  end
  self.cells[y * self.width + x + 1] = id
  self:repaintRegion(x, y, x, y)
end

-- Recolours the box plus the margin whose shading the box can influence.
-- Use after changing terrain with setRaw.
function World:repaintRegion(x0, y0, x1, y1)
  local m = SHADE_DEPTH + 1
  for y = math.max(0, y0 - m), math.min(self.height - 1, y1 + m) do
    for x = math.max(0, x0 - m), math.min(self.width - 1, x1 + m) do
      self:repaint(x, y)
    end
  end
end

function World:colorAt(x, y, depth)
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
    local row = math.floor(y / 5)
    if y % 5 == 0 or (x + (row % 2) * 5) % 10 == 0 then
      v = v - 0.18 -- mortar
    end
  end
  local s = shadeFactor(depth or self:depthAt(x, y))
  return (base[1] + v) * s, (base[2] + v) * s, (base[3] + v) * s, 1
end

function World:repaint(x, y)
  if self:inBounds(x, y) then
    self.imageData:setPixel(x, y, self:colorAt(x, y))
    self.dirty = true
  end
end

-- Full repaint. Depths come from four sweeps (down, up, right, left) instead
-- of per-pixel searches, which keeps this fast on large levels.
function World:repaintAll()
  local w, h, cells = self.width, self.height, self.cells
  local cap = SHADE_DEPTH + 1
  local depth = {}
  for x = 0, w - 1 do
    local run = cap -- outside the level counts as solid
    for y = 0, h - 1 do
      local i = y * w + x + 1
      run = solid[cells[i]] and math.min(run + 1, cap) or 0
      depth[i] = run
    end
    run = cap
    for y = h - 1, 0, -1 do
      local i = y * w + x + 1
      run = solid[cells[i]] and math.min(run + 1, cap) or 0
      if run < depth[i] then
        depth[i] = run
      end
    end
  end
  for y = 0, h - 1 do
    local row = y * w + 1
    local run = cap
    for x = 0, w - 1 do
      local i = row + x
      run = solid[cells[i]] and math.min(run + 1, cap) or 0
      if run < depth[i] then
        depth[i] = run
      end
    end
    run = cap
    for x = w - 1, 0, -1 do
      local i = row + x
      run = solid[cells[i]] and math.min(run + 1, cap) or 0
      if run < depth[i] then
        depth[i] = run
      end
    end
  end
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      self.imageData:setPixel(x, y, self:colorAt(x, y, depth[y * w + x + 1]))
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

-- Highest ground under a span of columns (x .. x + w - 1): where something
-- of that width can stand without overlapping the terrain
function World:findGroundUnder(x, w, fromY)
  local best = self.height
  for cx = x, x + w - 1 do
    best = math.min(best, self:findGround(cx, fromY))
  end
  return best
end

function World:refresh()
  if self.dirty then
    self.image:replacePixels(self.imageData)
    self.dirty = false
  end
end

-- Drawn with a margin around the level: the image's edge pixels are stretched
-- outward (clamp wrapping), so bedrock borders continue as solid rock and open
-- sky continues as sky when the camera looks past the level's edge.
local EDGE_MARGIN = 480

function World:draw()
  if not self.edgeQuad then
    local m = EDGE_MARGIN
    self.image:setWrap("clamp", "clamp")
    self.edgeQuad = love.graphics.newQuad(-m, -m, self.width + 2 * m, self.height + 2 * m, self.width, self.height)
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.image, self.edgeQuad, -EDGE_MARGIN, -EDGE_MARGIN)
end

return World
