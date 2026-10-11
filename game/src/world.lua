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

-- Cells live in a compact byte array when LuaJIT's FFI is available (the
-- unified world is millions of pixels), else in a plain table.
local hasFFI, ffi = pcall(require, "ffi")

local function newCells(n)
  if hasFFI then
    return ffi.new("uint8_t[?]", n + 1) -- zero-filled = AIR; indices 1..n used
  end
  local cells = {}
  for i = 1, n do
    cells[i] = AIR
  end
  return cells
end

-- The terrain image is split into tiles so changing a few pixels only
-- re-uploads their tile, and drawing only touches tiles on screen.
local TILE = 256

function World.new(width, height)
  local self = setmetatable({}, World)
  self.width = width
  self.height = height
  self.cells = newCells(width * height)
  self.tilesX = math.ceil(width / TILE)
  self.tilesY = math.ceil(height / TILE)
  self.tiles = {}
  for ty = 0, self.tilesY - 1 do
    for tx = 0, self.tilesX - 1 do
      local x0, y0 = tx * TILE, ty * TILE
      local w, h = math.min(TILE, width - x0), math.min(TILE, height - y0)
      self.tiles[ty * self.tilesX + tx + 1] = {
        x = x0,
        y = y0,
        w = w,
        h = h,
        data = love.image.newImageData(w, h),
        image = nil, -- created when first drawn
        dirty = true,
      }
    end
  end
  return self
end

-- Writes a colour into the tile image covering (x, y)
function World:writePixel(x, y, r, g, b, a)
  local tx, ty = math.floor(x / TILE), math.floor(y / TILE)
  local tile = self.tiles[ty * self.tilesX + tx + 1]
  tile.data:setPixel(x - tile.x, y - tile.y, r, g, b, a)
  tile.dirty = true
end

-- The colour currently shown for a terrain pixel
function World:pixelColor(x, y)
  local tx, ty = math.floor(x / TILE), math.floor(y / TILE)
  local tile = self.tiles[ty * self.tilesX + tx + 1]
  return tile.data:getPixel(x - tile.x, y - tile.y)
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
  if def.flecks and noise(x * 3.1, y * 1.7) > 0.58 then
    local s = shadeFactor(depth or self:depthAt(x, y))
    return def.flecks[1] * s, def.flecks[2] * s, def.flecks[3] * s, 1
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
    self:writePixel(x, y, self:colorAt(x, y))
  end
end

-- Repaints a rectangle (clamped to the world). Depths come from four sweeps
-- (down, up, right, left) instead of per-pixel searches, which keeps this
-- fast on big areas. Works in horizontal bands so the depth table stays
-- small; each band reads SHADE_DEPTH extra rows/columns around it so depths
-- at its edges are still exact. tick (optional) is called once per row, so a
-- caller running this in a coroutine can yield.
local BAND = 128

function World:repaintRect(x0, y0, x1, y1, tick)
  local w, h, cells = self.width, self.height, self.cells
  local cap = SHADE_DEPTH + 1
  x0, y0 = math.max(0, x0), math.max(0, y0)
  x1, y1 = math.min(w - 1, x1), math.min(h - 1, y1)
  -- Extended area the sweeps run over
  local ex0, ex1 = x0 - cap, x1 + cap
  local ew = ex1 - ex0 + 1
  local function isSolidAt(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then
      return true -- outside the level counts as solid
    end
    return solid[cells[y * w + x + 1]]
  end
  local depth = {}
  for by0 = y0, y1, BAND do
    local by1 = math.min(y1, by0 + BAND - 1)
    local ey0, ey1 = by0 - cap, by1 + cap
    -- Vertical sweeps
    for x = ex0, ex1 do
      local run = cap
      for y = ey0, ey1 do
        local i = (y - ey0) * ew + (x - ex0)
        run = isSolidAt(x, y) and math.min(run + 1, cap) or 0
        depth[i] = run
      end
      run = cap
      for y = ey1, ey0, -1 do
        local i = (y - ey0) * ew + (x - ex0)
        run = isSolidAt(x, y) and math.min(run + 1, cap) or 0
        if run < depth[i] then
          depth[i] = run
        end
      end
      if tick and x % 32 == 0 then
        tick()
      end
    end
    -- Horizontal sweeps (only the band's own rows are needed)
    for y = by0, by1 do
      local row = (y - ey0) * ew - ex0
      local run = cap
      for x = ex0, ex1 do
        run = isSolidAt(x, y) and math.min(run + 1, cap) or 0
        if run < depth[row + x] then
          depth[row + x] = run
        end
      end
      run = cap
      for x = ex1, ex0, -1 do
        run = isSolidAt(x, y) and math.min(run + 1, cap) or 0
        if run < depth[row + x] then
          depth[row + x] = run
        end
      end
      for x = x0, x1 do
        self:writePixel(x, y, self:colorAt(x, y, depth[row + x]))
      end
      if tick then
        tick()
      end
    end
  end
end

function World:repaintAll(tick)
  self:repaintRect(0, 0, self.width - 1, self.height - 1, tick)
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

-- Uploads changed tiles that have been drawn before (others upload when
-- they first come on screen)
function World:refresh()
  for _, tile in ipairs(self.tiles) do
    if tile.dirty and tile.image then
      tile.image:replacePixels(tile.data)
      tile.dirty = false
    end
  end
end

-- Tiles along the level's edge are drawn with a margin: their edge pixels are
-- stretched outward (clamp wrapping), so bedrock borders continue as solid
-- rock and open sky continues as sky when the camera looks past the level.
local EDGE_MARGIN = 480

-- Draws the tiles overlapping the view rectangle (world coordinates)
function World:draw(viewX, viewY, viewW, viewH)
  love.graphics.setColor(1, 1, 1)
  for _, tile in ipairs(self.tiles) do
    local left = tile.x == 0 and EDGE_MARGIN or 0
    local top = tile.y == 0 and EDGE_MARGIN or 0
    local right = tile.x + tile.w == self.width and EDGE_MARGIN or 0
    local bottom = tile.y + tile.h == self.height and EDGE_MARGIN or 0
    local dx0, dy0 = tile.x - left, tile.y - top
    local dx1, dy1 = tile.x + tile.w + right, tile.y + tile.h + bottom
    if dx1 > viewX and dx0 < viewX + viewW and dy1 > viewY and dy0 < viewY + viewH then
      if not tile.image then
        tile.image = love.graphics.newImage(tile.data)
        tile.image:setWrap("clamp", "clamp")
        tile.dirty = false
      elseif tile.dirty then
        tile.image:replacePixels(tile.data)
        tile.dirty = false
      end
      if left + top + right + bottom == 0 then
        love.graphics.draw(tile.image, tile.x, tile.y)
      else
        tile.quad = tile.quad
          or love.graphics.newQuad(-left, -top, tile.w + left + right, tile.h + top + bottom, tile.w, tile.h)
        love.graphics.draw(tile.image, tile.quad, dx0, dy0)
      end
    end
  end
end

return World
