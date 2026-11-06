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
-- Which pixels a search has visited, and which a dig has found anchored, are marked in two tables kept
-- from call to call, each mark the number of its search or dig (so nothing needs clearing between them:
-- new tables for every search were most of a crater's garbage). They start over now and then, between digs.
local visitedMark, settledMark = {}, {}
local floodId, digId, marks = 0, 0, 0
local visitedKeys = {}
local function floodIsland(world, sx, sy)
  local width = world.width
  local count = 0
  local stack = floodStack
  stack[1], stack[2] = sx, sy
  local top = 2
  floodId = floodId + 1
  local fid, did = floodId, digId
  visitedMark[sy * width + sx] = fid
  visitedKeys[1] = sy * width + sx
  local nv = 1
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
        if solid[id] and visitedMark[key] ~= fid then
          if anchored[id] or settledMark[key] == did then
            isAnchored = true
          end
          visitedMark[key] = fid
          nv = nv + 1
          visitedKeys[nv] = key
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
    for i = 1, nv do
      settledMark[visitedKeys[i]] = did
    end
  end
  marks = marks + nv
  return count, isAnchored
end

-- After n pixels (xs, ys) were removed, drops any piece that is now loose. A
-- piece can only have come loose next to a removed pixel, so the searches
-- start from those pixels' neighbours (not from every pixel round the hole).
local NX, NY = { 1, -1, 0, 0 }, { 0, 0, 1, -1 }
local function dropLooseTerrain(world, xs, ys, n)
  if marks > 200000 then
    visitedMark, settledMark, marks = {}, {}, 0 -- (so the marks don't pile up over a whole run)
  end
  digId = digId + 1
  local did = digId
  local width = world.width
  for i = 1, n do
    for d = 1, 4 do
      local x, y = xs[i] + NX[d], ys[i] + NY[d]
      if world:inBounds(x, y) then
        local id = world:get(x, y)
        if solid[id] and not anchored[id] and settledMark[y * width + x] ~= did then
          local count, isAnchored = floodIsland(world, x, y)
          if not isAnchored then
            -- (copied out: making the debris can't reuse the flood's arrays
            -- while it reads them; and its pixels count as settled now)
            local px, py = {}, {}
            for k = 1, count do
              px[k], py[k] = islandX[k], islandY[k]
              settledMark[islandY[k] * width + islandX[k]] = did
            end
            makeDebris(world, px, py, count)
          end
        end
      end
    end
  end
end

-- A cave-in: every solid, destructible pixel in the rectangle comes down at once, cut into blocks of bw x bh that fall as
-- physics debris (a block under MIN_DEBRIS_PIXELS crumbles to dust instead). Returns how many pixels came down.
local collapseX, collapseY = {}, {}
function destruction.collapse(world, x0, y0, x1, y1, bw, bh)
  local total = 0
  for by = y0, y1, bh do
    for bx = x0, x1, bw do
      local n = 0
      for y = by, math.min(y1, by + bh - 1) do
        for x = bx, math.min(x1, bx + bw - 1) do
          if world:inBounds(x, y) then
            local id = world:get(x, y)
            if solid[id] and not anchored[id] then
              n = n + 1
              collapseX[n], collapseY[n] = x, y
            end
          end
        end
      end
      if n > 0 then
        local px, py = {}, {}
        for i = 1, n do
          px[i], py[i] = collapseX[i], collapseY[i]
        end
        makeDebris(world, px, py, n)
        total = total + n
      end
    end
  end
  return total
end

-- A cave-in in rock: the slab breaks into jagged, irregular chunks (each pixel goes to the nearest of a jittered grid of
-- seed points, so the pieces are angular shards, not boxes), roughly bw x bh across. Only the columns where
-- `columnOK(x)` is true come down: the part of the slab resting on the cave's walls stays in the rock (a chunk cut
-- out of the wall would only fall into its own pocket and sit there stuck), and a column beside a held one is
-- spared too, so nothing is jammed against the wall it came out of. Returns how many pixels came down.
local function seedHash(a, b, salt)
  return (math.sin(a * 127.1 + b * 311.7 + salt * 74.7) * 43758.5453) % 1
end

function destruction.collapseRock(world, x0, y0, x1, y1, bw, bh, columnOK)
  local ok = {}
  for x = x0 - 1, x1 + 1 do
    ok[x] = columnOK(x)
  end
  local groups = {}
  for y = y0, y1 do
    local gy = math.floor((y - y0) / bh)
    for x = x0, x1 do
      if ok[x] and ok[x - 1] and ok[x + 1] and world:inBounds(x, y) then
        local id = world:get(x, y)
        if solid[id] and not anchored[id] then
          local gx = math.floor((x - x0) / bw)
          local best, bestD, bestKey
          for oy = -1, 1 do
            for ox = -1, 1 do
              local sx = gx + ox
              local sy = gy + oy
              local px = x0 + (sx + 0.5 + (seedHash(sx, sy, 1) - 0.5) * 0.95) * bw
              local py = y0 + (sy + 0.5 + (seedHash(sx, sy, 2) - 0.5) * 0.95) * bh
              local dx, dy = (x + 0.5 - px) / bw, (y + 0.5 - py) / bh
              local d = dx * dx + dy * dy
              if not bestD or d < bestD then
                bestD, bestKey = d, sy * 4096 + sx
              end
            end
          end
          local g = groups[bestKey]
          if not g then
            g = { xs = {}, ys = {}, n = 0 }
            groups[bestKey] = g
          end
          g.n = g.n + 1
          g.xs[g.n], g.ys[g.n] = x, y
        end
      end
    end
  end
  local total = 0
  for _, g in pairs(groups) do
    makeDebris(world, g.xs, g.ys, g.n)
    total = total + g.n
  end
  return total
end

-- Digs a crater of the given radius at (cx, cy). Each pixel in range is
-- removed with probability power / hardness. dx, dy is the impact direction
-- (debris sprays back against it). Vault rock only gives to a dig with vaultDig set.
-- Returns the number of pixels removed.
local digX, digY = {}, {}
function destruction.dig(world, cx, cy, radius, power, dx, dy, vaultDig)
  local removedX, removedY, n = digX, digY, 0
  local r2 = radius * radius
  for y = math.floor(cy - radius), math.ceil(cy + radius) do
    for x = math.floor(cx - radius), math.ceil(cx + radius) do
      local ox, oy = x + 0.5 - cx, y + 0.5 - cy
      if ox * ox + oy * oy <= r2 and world:inBounds(x, y) then
        local id = world:get(x, y)
        local def = defs[id]
        if def.solid and (vaultDig or not def.vault) and love.math.random() < power / def.hardness then
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
  require("src.cavein").onDig(cx, cy, radius, n) -- (digging out the underside of a roof with no props stresses it)
  return n
end

return destruction
