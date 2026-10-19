-- Pixel terrain: a grid of material ids rendered through an ImageData.
-- Each terrain pixel is one game pixel.
--
-- The world may be any size and its coordinates may be negative: it covers
-- x from `left` to `right - 1` and y from `top` to `bottom - 1` (World.new).
-- Cells are kept per tile (256x256 px) and a tile only gets cell storage when
-- something is written in it; a tile that was filled as a whole (unexplored
-- rock) is just one material id. So a very big world costs only what has
-- actually been generated, dug or built.
local materials = require("src.materials")

local AIR = materials.AIR
local BEDROCK = materials.BEDROCK
local solid = materials.solid
local defs = materials.defs
local floor = math.floor

local World = {}
World.__index = World

-- Deterministic per-pixel noise so recolouring a pixel gives the same shade
local function noise(x, y)
  local n = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
  return n - math.floor(n)
end

-- A tile's cells live in a compact byte array when LuaJIT's FFI is available,
-- else in a plain table.
local hasFFI, ffi = pcall(require, "ffi")

-- The terrain image is split into tiles so changing a few pixels only
-- re-uploads their tile, and drawing only touches tiles on screen.
local TILE = 256

-- left, top: the world's top-left corner (default 0, 0); coordinates may be negative
function World.new(width, height, left, top)
  local self = setmetatable({}, World)
  self.width = width
  self.height = height
  self.left = left or 0
  self.top = top or 0
  self.right = self.left + width -- (exclusive)
  self.bottom = self.top + height
  self.tilesX = math.ceil(width / TILE)
  self.tilesY = math.ceil(height / TILE)
  self.tiles = {}
  self.lazy = {} -- regions painted from the cells when a tile is first needed (see markLazy)
  for ty = 0, self.tilesY - 1 do
    for tx = 0, self.tilesX - 1 do
      local x0, y0 = self.left + tx * TILE, self.top + ty * TILE
      local w, h = math.min(TILE, self.right - x0), math.min(TILE, self.bottom - y0)
      self.tiles[ty * self.tilesX + tx + 1] = {
        world = self,
        x = x0,
        y = y0,
        x1 = x0 + w, -- (exclusive)
        y1 = y0 + h,
        w = w,
        h = h,
        cells = nil, -- byte array, allocated when first written (see allocCells)
        uniform = AIR, -- what every cell is while there is no array
        data = nil, -- ImageData, allocated when first written or drawn (see tileData)
        image = nil, -- created when first drawn
        dirty = true,
      }
    end
  end
  self.ct = self.tiles[1] -- the tile last looked up (a cache: neighbouring lookups are near each other)
  return self
end

-- The tile covering (x, y), which must be inside the world
function World:locate(x, y)
  local t = self.tiles[floor((y - self.top) / TILE) * self.tilesX + floor((x - self.left) / TILE) + 1]
  self.ct = t
  return t
end

local function allocCells(tile)
  local n = tile.w * tile.h
  local c
  if hasFFI then
    c = ffi.new("uint8_t[?]", n + 1) -- (indices 1..n used)
    if tile.uniform ~= AIR then
      ffi.fill(c, n + 1, tile.uniform)
    end
  else
    c = {}
    for i = 1, n do
      c[i] = tile.uniform
    end
  end
  tile.cells = c
  return c
end

-- A tile's pixels are only allocated once something paints or draws there,
-- which saves memory in the big, mostly not-yet-generated world
-- Paints a tile's lazy parts (from the cells) from where it got to down to row `upTo`
local readyTile -- (below)
local function paintLazy(tile, upTo)
  local w = tile.world
  local from = tile.lazyY or tile.y
  local to = math.min(tile.y1, upTo)
  if to <= from then
    return
  end
  tile.painting = true -- (painting writes pixels into this tile: tileData must not start over)
  for _, r in ipairs(w.lazy) do
    local x0, y0 = math.max(r[1], tile.x), math.max(r[2], from)
    local x1, y1 = math.min(r[3], tile.x1 - 1), math.min(r[4], to - 1)
    if x0 <= x1 and y0 <= y1 then
      w:repaintRect(x0, y0, x1, y1)
    end
  end
  tile.lazyY = to
  tile.painting = false
end

local function tileData(tile)
  if not tile.data then
    tile.data = love.image.newImageData(tile.w, tile.h)
    tile.lazyY = tile.y
  end
  -- Parts of the world marked lazy are painted only now, from the cells
  -- (whatever World:prewarm hasn't already done)
  if tile.lazyY < tile.y1 and not tile.painting then
    paintLazy(tile, tile.y1)
  end
  return tile.data
end

-- Paints all of a tile's lazy parts, a strip at a time with tick() (a
-- generator's yield) between strips
local READY_ROWS = 16
readyTile = function(tile, tick)
  if not tile.data then
    tile.data = love.image.newImageData(tile.w, tile.h)
    tile.lazyY = tile.y
  end
  while tile.lazyY < tile.y1 and not tile.painting do
    paintLazy(tile, tile.lazyY + READY_ROWS)
    tick()
  end
end

-- Gets the tiles just outside the view ready before they are seen: their
-- lazy parts painted a strip at a time, then their texture made. A tile of
-- unexplored ground painted all at once the moment it came into view was a
-- ~30 ms hitch. Call once a frame; it does one small piece of work.
local PREWARM_ROWS = 24
function World:prewarm(viewX, viewY, viewW, viewH)
  local m = TILE
  local tx0 = math.max(0, floor((viewX - m - self.left) / TILE))
  local tx1 = math.min(self.tilesX - 1, floor((viewX + viewW + m - self.left) / TILE))
  local ty0 = math.max(0, floor((viewY - m - self.top) / TILE))
  local ty1 = math.min(self.tilesY - 1, floor((viewY + viewH + m - self.top) / TILE))
  for ty = ty0, ty1 do
    for tx = tx0, tx1 do
      local tile = self.tiles[ty * self.tilesX + tx + 1]
      if not tile.image then
        if not tile.data then
          tile.data = love.image.newImageData(tile.w, tile.h)
          tile.lazyY = tile.y
          return
        elseif tile.lazyY < tile.y1 then
          paintLazy(tile, tile.lazyY + PREWARM_ROWS)
          return
        else
          tile.image = love.graphics.newImage(tile.data)
          tile.image:setWrap("clamp", "clamp")
          tile.dirty = false
          return
        end
      end
    end
  end
end

-- Writes a colour into the tile image covering (x, y)
function World:writePixel(x, y, r, g, b, a)
  local tile = self.ct
  if x < tile.x or x >= tile.x1 or y < tile.y or y >= tile.y1 then
    tile = self:locate(x, y)
  end
  tileData(tile):setPixel(x - tile.x, y - tile.y, r, g, b, a)
  tile.dirty = true
end

-- The colour currently shown for a terrain pixel
function World:pixelColor(x, y)
  local tile = self:locate(x, y)
  return tileData(tile):getPixel(x - tile.x, y - tile.y)
end

function World:inBounds(x, y)
  return x >= self.left and y >= self.top and x < self.right and y < self.bottom
end

-- Outside the world counts as bedrock so nothing escapes
function World:get(x, y)
  x, y = x - x % 1, y - y % 1 -- (the pixel the point is in, whatever fraction it has)
  if x < self.left or y < self.top or x >= self.right or y >= self.bottom then
    return BEDROCK
  end
  local t = self.ct
  if x < t.x or x >= t.x1 or y < t.y or y >= t.y1 then
    t = self:locate(x, y)
  end
  local c = t.cells
  if c then
    return c[(y - t.y) * t.w + (x - t.x) + 1]
  end
  return t.uniform
end

function World:isSolid(x, y)
  return solid[self:get(x, y)]
end

-- Raw write without recolouring; use for bulk generation, then call repaintAll()
function World:setRaw(x, y, id)
  x, y = x - x % 1, y - y % 1
  if self:inBounds(x, y) then
    local t = self.ct
    if x < t.x or x >= t.x1 or y < t.y or y >= t.y1 then
      t = self:locate(x, y)
    end
    local c = t.cells
    if not c then
      if t.uniform == id then
        return
      end
      c = allocCells(t)
    end
    c[(y - t.y) * t.w + (x - t.x) + 1] = id
  end
end

-- fillRect for big, plain regions: whole rows at once, and a tile the region
-- covers entirely becomes a single id with no storage (needs the FFI for the
-- partly covered tiles, falling back to fillRect without it)
function World:fillFast(x0, y0, x1, y1, id)
  x0, y0 = math.max(self.left, x0), math.max(self.top, y0)
  x1, y1 = math.min(self.right - 1, x1), math.min(self.bottom - 1, y1)
  if x0 > x1 or y0 > y1 then
    return
  end
  for ty = floor((y0 - self.top) / TILE), floor((y1 - self.top) / TILE) do
    for tx = floor((x0 - self.left) / TILE), floor((x1 - self.left) / TILE) do
      local t = self.tiles[ty * self.tilesX + tx + 1]
      local rx0, ry0 = math.max(x0, t.x), math.max(y0, t.y)
      local rx1, ry1 = math.min(x1, t.x1 - 1), math.min(y1, t.y1 - 1)
      if rx0 == t.x and ry0 == t.y and rx1 == t.x1 - 1 and ry1 == t.y1 - 1 then
        t.cells = nil
        t.uniform = id
      elseif hasFFI then
        local c = t.cells or allocCells(t)
        local n = rx1 - rx0 + 1
        for y = ry0, ry1 do
          ffi.fill(c + ((y - t.y) * t.w + (rx0 - t.x) + 1), n, id)
        end
      else
        for y = ry0, ry1 do
          for x = rx0, rx1 do
            self:setRaw(x, y, id)
          end
        end
      end
    end
  end
end

-- Marks a region as painted on demand: its tiles are painted from the cells
-- the first time they are drawn or touched, instead of all at once. (A world
-- several times bigger than a screen would spend seconds painting ground
-- nobody sees.) Mark after the cells are in place.
function World:markLazy(x0, y0, x1, y1)
  self.lazy[#self.lazy + 1] = { x0, y0, x1, y1 }
end

-- Is the pixel's colour already in its tile? (Not when it is in a part painted
-- on demand that hasn't been painted yet: reading or writing it would paint
-- the whole tile there and then. A stain there can just be skipped.)
function World:shownAt(x, y)
  local tile = self:locate(x, y)
  if tile.painting or (tile.data and (tile.lazyY or tile.y1) >= tile.y1) then
    return true
  end
  return not (y >= (tile.data and tile.lazyY or tile.y) and self:lazyAt(x, y))
end

-- Is the pixel in a region painted on demand?
-- Puts a pixel of decoration into the cells and onto the picture, leaving it to the lazy painting where that
-- has not happened yet (the same rule as a repaint in the middle of play)
function World:stampPixel(x, y, id)
  if not self:inBounds(x, y) or self:get(x, y) ~= AIR then
    return -- (decoration only goes into open air)
  end
  self:setRaw(x, y, id)
  local tile = self:locate(x, y)
  if tile.painting or (tile.data and (tile.lazyY or tile.y1) >= tile.y1) then
    self:writePixel(x, y, self:colorAt(x, y, 0))
  else
    local from = tile.data and tile.lazyY or tile.y
    if not (y >= from and self:lazyAt(x, y)) then
      self:writePixel(x, y, self:colorAt(x, y, 0))
    end
  end
end

function World:lazyAt(x, y)
  for _, r in ipairs(self.lazy) do
    if x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then
      return true
    end
  end
  return false
end

-- Takes a region out of the lazy ones: whoever builds it paints it themselves
-- (an area being generated claims its rectangle first)
function World:claim(x0, y0, x1, y1)
  local out = {}
  for _, r in ipairs(self.lazy) do
    if x1 < r[1] or x0 > r[3] or y1 < r[2] or y0 > r[4] then
      out[#out + 1] = r
    else
      -- what is left of r round the claimed box
      if y0 > r[2] then
        out[#out + 1] = { r[1], r[2], r[3], y0 - 1 }
      end
      if y1 < r[4] then
        out[#out + 1] = { r[1], y1 + 1, r[3], r[4] }
      end
      local top, bottom = math.max(r[2], y0), math.min(r[4], y1)
      if x0 > r[1] then
        out[#out + 1] = { r[1], top, x0 - 1, bottom }
      end
      if x1 < r[3] then
        out[#out + 1] = { x1 + 1, top, r[3], bottom }
      end
    end
  end
  self.lazy = out
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
  self:setRaw(x, y, id)
  self:repaintRegion(x, y, x, y)
end

-- Recolours the box plus the margin whose shading the box can influence.
-- Use after changing terrain with setRaw.
-- (With the sweeps of repaintRect: re-shading pixel by pixel searched up to
-- 56 neighbours for each, and a dynamite crater took 20-50 ms.)
function World:repaintRegion(x0, y0, x1, y1)
  local m = SHADE_DEPTH + 1
  self:repaintRect(x0 - m, y0 - m, x1 + m, y1 + m)
end

-- Queues a repaintRegion for the end of the frame's update (World:flushRepaints).
-- A volley of rounds or a burrowing worm digs many overlapping holes in a
-- frame: each repainted on its own re-shaded the same ground several times.
-- Boxes that overlap (or come within the shading's reach) are merged.
function World:repaintLater(x0, y0, x1, y1)
  local q = self.repaintQueue
  if not q then
    q = {}
    self.repaintQueue = q
  end
  local m = SHADE_DEPTH + 1
  for _, r in ipairs(q) do
    if x0 <= r[3] + m and x1 >= r[1] - m and y0 <= r[4] + m and y1 >= r[2] - m then
      r[1], r[2] = math.min(r[1], x0), math.min(r[2], y0)
      r[3], r[4] = math.max(r[3], x1), math.max(r[4], y1)
      return
    end
  end
  q[#q + 1] = { x0, y0, x1, y1 }
end

function World:flushRepaints()
  local q = self.repaintQueue
  if not q then
    return
  end
  for i = 1, #q do
    local r = q[i]
    q[i] = nil
    self:repaintRegion(r[1], r[2], r[3], r[4])
  end
end

-- Cloud: lit from above, white through its body with soft lumps of billow,
-- going blue in its belly (where open air lies a little way below) rather
-- than one flat mass darkening inward
local cloudNoise = love.math.noise
local function cloudColor(world, def, x, y, depth)
  if not world:isSolid(x, y - 1) then
    local c = def.topColor
    return c[1], c[2], c[3], 1
  end
  local puff = cloudNoise(x * 0.035, y * 0.05) * 0.6 + cloudNoise(x * 0.11, y * 0.13, 3.1) * 0.4
  local lit = 0.72 + (puff - 0.5) * 0.5 - math.min(depth, 20) * 0.006
  if not world:isSolid(x, y + 3) then
    lit = lit - 0.45
  elseif not world:isSolid(x, y + 8) then
    lit = lit - 0.28
  elseif not world:isSolid(x, y + 14) then
    lit = lit - 0.12
  end
  lit = math.max(0, math.min(1, lit))
  local c, s = def.color, def.shadow
  local v = (noise(x, y) - 0.5) * def.variation
  return s[1] + (c[1] - s[1]) * lit + v, s[2] + (c[2] - s[2]) * lit + v, s[3] + (c[3] - s[3]) * lit + v, 1
end

-- Is a pixel of decoration held up: rock (or a held pixel of decoration) next to it in the direction dy, straight
-- or diagonal? (a strand that sways, or a stalk that leans, is held along its length)
local function decorHeld(self, x, y, dy, depth)
  if depth > 18 then
    return false
  end
  local ny = y + dy
  for i = 1, 3 do
    local ox = i == 1 and 0 or (i == 2 and -1 or 1)
    local id = self:get(x + ox, ny)
    if solid[id] or (materials.decor[id] and decorHeld(self, x + ox, ny, dy, depth + 1)) then
      return true
    end
  end
  return false
end

-- Tints (an area's own colouring of its rock and earth, from src.decor): layers of strata, streaks and blotches
-- blended over the pixel's colour. Worked out from the position alone, so a crater's rim keeps the pattern.
local tnoise = love.math.noise
local function applyTint(tint, x, y, id, r, g, b)
  if not tint.ids[id] then
    return r, g, b
  end
  for _, L in ipairs(tint.layers) do
    local m
    local k = L.kind
    local fade = 1
    if L.ramp then
      -- (a layer for part of the area's height fades in and out at its edges, no hard line)
      fade = math.min(1, math.max(0, math.min(y - L.y0, L.y1 - y) / L.ramp))
    end
    if fade <= 0 then
      m = -1
    elseif k == "strata" then
      m = math.sin(y * L.freq + tnoise(x * 0.015, y * 0.01 + L.seed) * 5) - L.cut
    elseif k == "streak" then
      m = tnoise(x * L.freq, y * 0.012 + L.seed) - L.cut
    else
      m = tnoise(x * L.freq, y * L.freq * 1.3 + L.seed) - L.cut
    end
    if m > 0 then
      local a = math.min(1, m * L.soft) * L.amount * fade
      local c = L.color
      r, g, b = r + (c[1] - r) * a, g + (c[2] - g) * a, b + (c[3] - b) * a
    end
  end
  return r, g, b
end

-- Tints the rock and earth ids in a rectangle: layers = { { kind = "strata"|"streak"|"blotch", color, amount, ... } }
function World:addTint(x0, y0, x1, y1, layers, ids)
  local set = {}
  for _, id in ipairs(ids) do
    set[id] = true
  end
  local out = {}
  for i, L in ipairs(layers) do
    out[i] = {
      kind = L.kind,
      color = L.color,
      amount = L.amount or 0.3,
      freq = L.freq or (L.kind == "strata" and 0.35 or L.kind == "streak" and 0.5 or 0.04),
      cut = L.cut or (L.kind == "strata" and 0.6 or 0.58),
      soft = L.soft or 6,
      y0 = L.y0 or y0,
      y1 = L.y1 or y1,
      ramp = L.y0 and math.max(1, math.min(300, (L.y1 - L.y0) * 0.3)) or nil,
      seed = (L.seed or 0) + i * 17.3,
    }
  end
  self.tints = self.tints or {}
  self.tints[#self.tints + 1] = { x0 = x0, y0 = y0, x1 = x1, y1 = y1, layers = out, ids = set }
end

local baseColorAt
function World:colorAt(x, y, depth)
  local r, g, b, a = baseColorAt(self, x, y, depth)
  local tints = self.tints
  if a == 1 and tints then
    for i = 1, #tints do
      local t = tints[i]
      if x >= t.x0 and x <= t.x1 and y >= t.y0 and y <= t.y1 then
        r, g, b = applyTint(t, x, y, self:get(x, y), r, g, b)
        break
      end
    end
  end
  return r, g, b, a
end

baseColorAt = function(self, x, y, depth)
  local def = defs[self:get(x, y)]
  if not def.solid then
    if def.decor then
      -- A blade of grass: painted only while the ground it stands on (or the blade below it) is still there.
      -- Other decoration (src.decor) may hang from above or cling to the side instead (def.support)
      local sup = def.support
      local held
      if sup == "above" then
        held = decorHeld(self, x, y, -1, 0)
      elseif sup == "below" then
        held = decorHeld(self, x, y, 1, 0)
      elseif sup == "near" then
        held = solid[self:get(x, y + 1)] or solid[self:get(x, y - 1)] or solid[self:get(x - 1, y)] or solid[self:get(x + 1, y)]
      else
        local yy = y + 1
        while materials.decor[self:get(x, yy)] and yy < y + 8 do
          yy = yy + 1
        end
        held = solid[self:get(x, yy)]
      end
      if not held then
        self:setRaw(x, y, AIR)
        return 0, 0, 0, 0
      end
      local v = (noise(x, y) - 0.5) * 2 * def.variation
      return def.color[1] + v, def.color[2] + v, def.color[3] + v, 1
    end
    return 0, 0, 0, 0
  end
  if def.cloud then
    return cloudColor(self, def, x, y, depth or self:depthAt(x, y))
  end
  local base = def.color
  if def.topColor and not self:isSolid(x, y - 1) then
    base = def.topColor
  end
  local v = (noise(x, y) - 0.5) * 2 * def.variation
  if def.bands then
    v = v + math.sin(y * 0.7 + math.sin(x * 0.05) * 2) * def.bands
  end
  if def.flecks and noise(x * 3.1, y * 1.7) > (def.fleckMin or 0.58) then
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
-- The depth table is kept and reused (a band of a whole area is ~370,000
-- entries: making it afresh for every call, and growing it, was a 10-20 ms
-- hitch each time). Generation, which yields part-way (tick), has its own,
-- so a crater repainted meanwhile can't overwrite it.
-- They are byte arrays when the FFI is there: as Lua tables of ~460,000
-- numbers each, the collector went through every entry on every cycle.
local depthBuf, depthBufGen = {}, {}
local function depthBuffer(gen, n)
  if not hasFFI then
    return gen and depthBufGen or depthBuf
  end
  local cur = gen and depthBufGen or depthBuf
  if type(cur) == "table" or cur.n < n then
    local size = math.max(n, 65536)
    cur = { buf = ffi.new("uint8_t[?]", size), n = size }
    if gen then
      depthBufGen = cur
    else
      depthBuf = cur
    end
  end
  return cur.buf
end

function World:repaintRect(x0, y0, x1, y1, tick)
  local cap = SHADE_DEPTH + 1
  x0, y0 = math.max(self.left, x0), math.max(self.top, y0)
  x1, y1 = math.min(self.right - 1, x1), math.min(self.bottom - 1, y1)
  -- Extended area the sweeps run over
  local ex0, ex1 = x0 - cap, x1 + cap
  local ew = ex1 - ex0 + 1
  local get = self.get
  local function isSolidAt(x, y)
    return solid[get(self, x, y)] -- (outside the level counts as solid: bedrock)
  end
  local depth = depthBuffer(tick ~= nil, (math.min(BAND, y1 - y0 + 1) + 2 * cap) * ew + 1)
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
      if tick then
        -- tiles this row reaches into that still have unpainted lazy rock
        -- (round the edge of an area) are painted a strip at a time first:
        -- writing the first pixel would otherwise paint all of it at once,
        -- 5-15 ms without a yield
        for tx = x0, x1 + TILE - 1, TILE do
          local tile = self:locate(math.min(tx, x1), y)
          readyTile(tile, tick)
        end
      end
      if tick then
        for x = x0, x1 do
          self:writePixel(x, y, self:colorAt(x, y, depth[row + x]))
          if x % 256 == 0 then
            tick() -- (a whole area's row took longer than a frame's budget)
          end
        end
      else
        -- A crater (or anything else repainted during play) in a tile whose
        -- lazy rock isn't painted yet leaves those pixels alone: they will be
        -- painted from the cells anyway, and writing one would paint the
        -- whole tile there and then (5-25 ms, for a stray round far off)
        local x = x0
        while x <= x1 do
          local tile = self:locate(x, y)
          local runEnd = math.min(x1, tile.x1 - 1)
          if tile.painting or (tile.data and (tile.lazyY or tile.y1) >= tile.y1) then
            for rx = x, runEnd do
              self:writePixel(rx, y, self:colorAt(rx, y, depth[row + rx]))
            end
          else
            local from = tile.data and tile.lazyY or tile.y
            for rx = x, runEnd do
              if not (y >= from and self:lazyAt(rx, y)) then
                self:writePixel(rx, y, self:colorAt(rx, y, depth[row + rx]))
              end
            end
          end
          x = runEnd + 1
        end
      end
      if tick then
        tick()
      end
    end
  end
end

function World:repaintAll(tick)
  self:repaintRect(self.left, self.top, self.right - 1, self.bottom - 1, tick)
end

-- First solid pixel at or below fromY in column x (the world's bottom edge if none)
function World:findGround(x, fromY)
  for y = fromY, self.bottom - 1 do
    if self:isSolid(x, y) then
      return y
    end
  end
  return self.bottom
end

-- Highest ground under a span of columns (x .. x + w - 1): where something
-- of that width can stand without overlapping the terrain
function World:findGroundUnder(x, w, fromY)
  local best = self.bottom
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
function World:draw(viewX, viewY, viewW, viewH, shader)
  love.graphics.setColor(1, 1, 1)
  if shader then
    love.graphics.setShader(shader)
  end
  -- (the tiles at the world's edge also cover the margin beyond it)
  local tx0 = math.max(0, floor((viewX - EDGE_MARGIN - self.left) / TILE))
  local tx1 = math.min(self.tilesX - 1, floor((viewX + viewW + EDGE_MARGIN - self.left) / TILE))
  local ty0 = math.max(0, floor((viewY - EDGE_MARGIN - self.top) / TILE))
  local ty1 = math.min(self.tilesY - 1, floor((viewY + viewH + EDGE_MARGIN - self.top) / TILE))
  for ty = ty0, ty1 do
    for tx = tx0, tx1 do
      local tile = self.tiles[ty * self.tilesX + tx + 1]
      local left = tile.x == self.left and EDGE_MARGIN or 0
      local top = tile.y == self.top and EDGE_MARGIN or 0
      local right = tile.x1 == self.right and EDGE_MARGIN or 0
      local bottom = tile.y1 == self.bottom and EDGE_MARGIN or 0
      local dx0, dy0 = tile.x - left, tile.y - top
      local dx1, dy1 = tile.x1 + right, tile.y1 + bottom
      if dx1 > viewX and dx0 < viewX + viewW and dy1 > viewY and dy0 < viewY + viewH then
        if not tile.image then
          tile.image = love.graphics.newImage(tileData(tile))
          tile.image:setWrap("clamp", "clamp")
          tile.dirty = false
        elseif tile.dirty then
          tile.image:replacePixels(tile.data)
          tile.dirty = false
        end
        if shader then
          shader:send("texel", { 1 / tile.w, 1 / tile.h })
        end
        if left + top + right + bottom == 0 then
          love.graphics.draw(tile.image, tile.x, tile.y)
        else
          tile.quad = tile.quad or love.graphics.newQuad(-left, -top, tile.w + left + right, tile.h + top + bottom, tile.w, tile.h)
          love.graphics.draw(tile.image, tile.quad, dx0, dy0)
        end
      end
    end
  end
  if shader then
    love.graphics.setShader()
  end
end

return World
