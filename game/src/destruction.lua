-- Destructible terrain: digging craters, and turning chunks of terrain that
-- have been cut loose into falling physics debris (design doc §6).
local effects = require("src.effects")
local fluids = require("src.fluids")
local materials = require("src.materials")
local physics = require("src.physics")
local pickups = require("src.pickups")
local props = require("src.props")

local destruction = {}

local AIR = materials.AIR
local defs = materials.defs
local solid = materials.solid
local anchored = materials.anchored

-- A floating mass of terrain bigger than this stays where it is: still solid
-- terrain that can be dug at. Once digging shrinks it to this many pixels or
-- fewer it becomes physics debris and falls. (This also keeps the
-- connectivity search cheap.)
local MAX_FALLING_PIXELS = 100
-- Loose pieces smaller than this just crumble into particles
local MIN_DEBRIS_PIXELS = 15

local function crumble(world, x, y, id)
  local c = defs[id].color
  effects.particle(
    x + 0.5,
    y + 0.5,
    (love.math.random() - 0.5) * 64,
    -love.math.random() * 48,
    0.5 + love.math.random() * 0.4,
    { c[1], c[2], c[3] },
    480
  )
end

-- Pixel lists are kept as two flat arrays of coordinates and a count (a
-- crater is hundreds of pixels, dug many times a second by a machine gun or a
-- worm: a little table per pixel was a lot of garbage)

-- Removes n pixels (xs[i], ys[i]) and re-traces their collision
local function clearPixels(world, xs, ys, n)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for i = 1, n do
    local x, y = xs[i], ys[i]
    world:setRaw(x, y, AIR)
    x0, y0 = math.min(x0, x), math.min(y0, y)
    x1, y1 = math.max(x1, x), math.max(y1, y)
  end
  world:repaintLater(x0, y0, x1, y1) -- recolour and re-shade around the hole (once a frame, see World:flushRepaints)
  physics.rebuildRegion(x0, y0, x1, y1)
  fluids.wake(x0, y0, x1, y1) -- water next to the hole starts to run at once
end

-- Splits the chunk's pixel mask into rectangles for Box2D fixtures:
-- horizontal runs, merged downward while identical runs continue.
local function rectangles(mask, w, h)
  local rects, open = {}, {}
  for y = 0, h - 1 do
    local runs = {}
    local x = 0
    while x < w do
      if mask[y * w + x] then
        local start = x
        while x < w and mask[y * w + x] do
          x = x + 1
        end
        runs[#runs + 1] = { start, x - start }
      else
        x = x + 1
      end
    end
    local nextOpen = {}
    for _, run in ipairs(runs) do
      local key = run[1] * 4096 + run[2]
      local rect = open[key]
      if rect then
        rect[4] = rect[4] + 1
      else
        rect = { run[1], y, run[2], 1 }
        rects[#rects + 1] = rect
      end
      nextOpen[key] = rect
    end
    open = nextOpen
  end
  return rects
end

-- A terrain pixel's colour as shown (worked out from the cells where its
-- tile isn't painted yet, rather than painting the whole tile to read it)
local function shownColor(world, x, y)
  if world:shownAt(x, y) then
    return world:pixelColor(x, y)
  end
  return world:colorAt(x, y)
end

-- Lifts a loose island of n pixels out of the terrain and into a physics body
local function makeDebris(world, xs, ys, n)
  if n < MIN_DEBRIS_PIXELS then
    for i = 1, n do
      crumble(world, xs[i], ys[i], world:get(xs[i], ys[i]))
    end
    clearPixels(world, xs, ys, n)
    return
  end

  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for i = 1, n do
    x0, y0 = math.min(x0, xs[i]), math.min(y0, ys[i])
    x1, y1 = math.max(x1, xs[i]), math.max(y1, ys[i])
  end
  local w, h = x1 - x0 + 1, y1 - y0 + 1

  local imageData = love.image.newImageData(w, h)
  local mask = {}
  local totalDensity = 0
  local color = { shownColor(world, xs[1], ys[1]) }
  for i = 1, n do
    local lx, ly = xs[i] - x0, ys[i] - y0
    imageData:setPixel(lx, ly, shownColor(world, xs[i], ys[i]))
    mask[ly * w + lx] = true
    totalDensity = totalDensity + (defs[world:get(xs[i], ys[i])].density or 1)
  end
  local image = love.graphics.newImage(imageData)

  clearPixels(world, xs, ys, n)
  props.spawnDebris(image, x0 + w / 2, y0 + h / 2, rectangles(mask, w, h), totalDensity / n, n, color)
end

-- Flood-fills solid terrain from (sx, sy) into islandX/islandY. Returns the
-- island's pixel count and whether it is anchored (touches indestructible
-- terrain, reaches terrain already known to be anchored, or is too big to
-- fall). Anchored searches stop early, so everything they reached is
-- recorded in `settled`.
local islandX, islandY, floodStack = {}, {}, {}
local function floodIsland(world, sx, sy, settled)
  local width = world.width
  local count = 0
  local stack = floodStack
  stack[1], stack[2] = sx, sy
  local top = 2
  local visited = { [sy * width + sx] = true }
  local isAnchored = false
  while top > 0 do
    local y = stack[top]
    local x = stack[top - 1]
    top = top - 2
    count = count + 1
    islandX[count], islandY[count] = x, y
    if count > MAX_FALLING_PIXELS then
      isAnchored = true
      break
    end
    for i = 1, 4 do
      local nx = x + (i == 1 and 1 or i == 2 and -1 or 0)
      local ny = y + (i == 3 and 1 or i == 4 and -1 or 0)
      if not world:inBounds(nx, ny) then
        isAnchored = true
      else
        local id = world:get(nx, ny)
        local key = ny * width + nx
        if solid[id] and not visited[key] then
          if anchored[id] or settled[key] then
            isAnchored = true
          end
          visited[key] = true
          stack[top + 1] = nx
          stack[top + 2] = ny
          top = top + 2
        end
      end
    end
    if isAnchored then
      break
    end
  end
  if isAnchored then
    for key in pairs(visited) do
      settled[key] = true
    end
  end
  return count, isAnchored
end

-- After n pixels (xs, ys) were removed, drops any piece that is now loose. A
-- piece can only have come loose next to a removed pixel, so the searches
-- start from those pixels' neighbours (not from every pixel round the hole).
local NX, NY = { 1, -1, 0, 0 }, { 0, 0, 1, -1 }
local function dropLooseTerrain(world, xs, ys, n)
  local settled = {}
  local width = world.width
  for i = 1, n do
    for d = 1, 4 do
      local x, y = xs[i] + NX[d], ys[i] + NY[d]
      if world:inBounds(x, y) then
        local id = world:get(x, y)
        if solid[id] and not anchored[id] and not settled[y * width + x] then
          local count, isAnchored = floodIsland(world, x, y, settled)
          if not isAnchored then
            -- (copied out: making the debris can't reuse the flood's arrays
            -- while it reads them; and its pixels count as settled now)
            local px, py = {}, {}
            for k = 1, count do
              px[k], py[k] = islandX[k], islandY[k]
              settled[islandY[k] * width + islandX[k]] = true
            end
            makeDebris(world, px, py, count)
          end
        end
      end
    end
  end
end

-- Digs a crater of the given radius at (cx, cy). Each pixel in range is
-- removed with probability power / hardness. dx, dy is the impact direction
-- (debris sprays back against it). Returns the number of pixels removed.
local digX, digY = {}, {}
function destruction.dig(world, cx, cy, radius, power, dx, dy)
  local removedX, removedY, n = digX, digY, 0
  local r2 = radius * radius
  for y = math.floor(cy - radius), math.ceil(cy + radius) do
    for x = math.floor(cx - radius), math.ceil(cx + radius) do
      local ox, oy = x + 0.5 - cx, y + 0.5 - cy
      if ox * ox + oy * oy <= r2 and world:inBounds(x, y) then
        local id = world:get(x, y)
        local def = defs[id]
        if def.solid and love.math.random() < power / def.hardness then
          n = n + 1
          removedX[n], removedY[n] = x, y
          if def.gold and love.math.random() < 0.1 then
            -- A tenth of the ore pixels give a speck or two, spilling out of the hole
            pickups.dropGold(x + 0.5, y + 0.5, love.math.random(def.gold[1], def.gold[2]))
          end
          if love.math.random() < 0.6 then
            local c = def.color
            local a = math.atan2(-(dy or 0), -(dx or 0)) + (love.math.random() - 0.5) * 2.2
            local s = 48 + love.math.random() * 112
            effects.particle(x + 0.5, y + 0.5, math.cos(a) * s, math.sin(a) * s, 0.7, c, 560)
          end
        end
      end
    end
  end
  if n == 0 then
    return 0
  end
  clearPixels(world, removedX, removedY, n)
  dropLooseTerrain(world, removedX, removedY, n)
  return n
end

return destruction
