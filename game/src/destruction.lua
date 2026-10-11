-- Destructible terrain: digging craters, and turning chunks of terrain that
-- have been cut loose into falling physics debris (design doc §6).
local effects = require("src.effects")
local materials = require("src.materials")
local physics = require("src.physics")
local props = require("src.props")

local destruction = {}

local AIR = materials.AIR
local defs = materials.defs
local solid = materials.solid
local anchored = materials.anchored

-- Loose pieces bigger than this stay put. Keeps the connectivity search cheap
-- and stops large floating landmasses from dropping out of the level.
local MAX_FALLING_PIXELS = 1024
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

-- Removes a list of pixels ({x, y} pairs) and re-traces their collision
local function clearPixels(world, pixels)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, p in ipairs(pixels) do
    world:setRaw(p[1], p[2], AIR)
    x0, y0 = math.min(x0, p[1]), math.min(y0, p[2])
    x1, y1 = math.max(x1, p[1]), math.max(y1, p[2])
  end
  world:repaintRegion(x0, y0, x1, y1) -- recolour and re-shade around the hole once
  physics.rebuildRegion(x0, y0, x1, y1)
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

-- Lifts a loose island of pixels out of the terrain and into a physics body
local function makeDebris(world, pixels)
  if #pixels < MIN_DEBRIS_PIXELS then
    for _, p in ipairs(pixels) do
      crumble(world, p[1], p[2], world:get(p[1], p[2]))
    end
    clearPixels(world, pixels)
    return
  end

  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, p in ipairs(pixels) do
    x0, y0 = math.min(x0, p[1]), math.min(y0, p[2])
    x1, y1 = math.max(x1, p[1]), math.max(y1, p[2])
  end
  local w, h = x1 - x0 + 1, y1 - y0 + 1

  local imageData = love.image.newImageData(w, h)
  local mask = {}
  local totalDensity = 0
  for _, p in ipairs(pixels) do
    local lx, ly = p[1] - x0, p[2] - y0
    imageData:setPixel(lx, ly, world:pixelColor(p[1], p[2]))
    mask[ly * w + lx] = true
    totalDensity = totalDensity + (defs[world:get(p[1], p[2])].density or 1)
  end
  local image = love.graphics.newImage(imageData)

  clearPixels(world, pixels)
  props.spawnDebris(image, x0 + w / 2, y0 + h / 2, rectangles(mask, w, h), totalDensity / #pixels)
end

-- Flood-fills solid terrain from (sx, sy). Returns the island's pixels and
-- whether it is anchored (touches indestructible terrain, reaches terrain
-- already known to be anchored, or is too big to fall). Anchored searches stop
-- early, so everything they reached is recorded in `settled`.
local function floodIsland(world, sx, sy, settled)
  local width = world.width
  local pixels = {}
  local stack = { sx, sy }
  local visited = { [sy * width + sx] = true }
  local isAnchored = false
  while #stack > 0 do
    local y = table.remove(stack)
    local x = table.remove(stack)
    pixels[#pixels + 1] = { x, y }
    if #pixels > MAX_FALLING_PIXELS then
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
          stack[#stack + 1] = nx
          stack[#stack + 1] = ny
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
  return pixels, isAnchored
end

-- After terrain in the box was removed, drops any piece that is now loose
local function dropLooseTerrain(world, x0, y0, x1, y1)
  local settled = {}
  for y = y0 - 1, y1 + 1 do
    for x = x0 - 1, x1 + 1 do
      if world:inBounds(x, y) then
        local id = world:get(x, y)
        if solid[id] and not anchored[id] and not settled[y * world.width + x] then
          local pixels, isAnchored = floodIsland(world, x, y, settled)
          if not isAnchored then
            makeDebris(world, pixels)
          end
        end
      end
    end
  end
end

-- Digs a crater of the given radius at (cx, cy). Each pixel in range is
-- removed with probability power / hardness. dx, dy is the impact direction
-- (debris sprays back against it). Returns the number of pixels removed.
function destruction.dig(world, cx, cy, radius, power, dx, dy)
  local removed = {}
  local r2 = radius * radius
  for y = math.floor(cy - radius), math.ceil(cy + radius) do
    for x = math.floor(cx - radius), math.ceil(cx + radius) do
      local ox, oy = x + 0.5 - cx, y + 0.5 - cy
      if ox * ox + oy * oy <= r2 and world:inBounds(x, y) then
        local id = world:get(x, y)
        local def = defs[id]
        if def.solid and love.math.random() < power / def.hardness then
          removed[#removed + 1] = { x, y }
          if love.math.random() < 0.6 then
            local c = def.color
            local a = math.atan2(-(dy or 0), -(dx or 0)) + (love.math.random() - 0.5) * 2.2
            local s = 48 + love.math.random() * 112
            effects.particle(x + 0.5, y + 0.5, math.cos(a) * s, math.sin(a) * s, 0.7, { c[1], c[2], c[3] }, 560)
          end
        end
      end
    end
  end
  if #removed == 0 then
    return 0
  end
  clearPixels(world, removed)
  local x0, y0 = math.floor(cx - radius), math.floor(cy - radius)
  local x1, y1 = math.ceil(cx + radius), math.ceil(cy + radius)
  dropLooseTerrain(world, x0, y0, x1, y1)
  return #removed
end

return destruction
