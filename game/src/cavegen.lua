-- Procedural generation for a descending cave area (design doc §7):
-- an entrance chamber at the top, organic caves, a guaranteed tunnel winding
-- down through them, and the shop room at the bottom.
local materials = require("src.materials")
local World = require("src.world")

local AIR, DIRT, ROCK, BEDROCK = materials.AIR, materials.DIRT, materials.ROCK, materials.BEDROCK
local WOOD, BRICK = materials.WOOD, materials.BRICK

local cavegen = {}

local WIDTH, HEIGHT = 512, 1152
local BORDER = 8
local CELL = 6 -- cellular-automata cave grid resolution, in pixels

local PLAYER_W, PLAYER_H = 5, 11

local function carveCircle(world, cx, cy, r)
  local r2 = r * r
  for y = math.floor(cy - r), math.ceil(cy + r) do
    for x = math.floor(cx - r), math.ceil(cx + r) do
      local dx, dy = x + 0.5 - cx, y + 0.5 - cy
      if dx * dx + dy * dy <= r2 and x >= BORDER and y >= BORDER and x < WIDTH - BORDER and y < HEIGHT - BORDER then
        world:setRaw(x, y, AIR)
      end
    end
  end
end

-- Base rock: dirt pockets in rock, dirt more common near the top
local function fillBase(world, seed)
  for y = 0, HEIGHT - 1 do
    local depth = y / HEIGHT
    for x = 0, WIDTH - 1 do
      local n = love.math.noise(x * 0.018, y * 0.018, seed)
      world:setRaw(x, y, n > 0.38 + depth * 0.35 and DIRT or ROCK)
    end
  end
end

-- Organic caves via cellular automata on a coarse grid, then blended to
-- pixel resolution with noise for natural edges.
local function carveCaves(world, rng, seed)
  local gw, gh = math.ceil(WIDTH / CELL), math.ceil(HEIGHT / CELL)
  local grid = {}
  for i = 0, gw * gh - 1 do
    grid[i] = rng:random() < 0.47 and 1 or 0 -- 1 = air
  end
  for _ = 1, 5 do
    local nextGrid = {}
    for gy = 0, gh - 1 do
      for gx = 0, gw - 1 do
        local air = 0
        for oy = -1, 1 do
          for ox = -1, 1 do
            local nx, ny = gx + ox, gy + oy
            if nx >= 0 and ny >= 0 and nx < gw and ny < gh then
              air = air + grid[ny * gw + nx]
            end
          end
        end
        -- Rock-majority neighbourhoods become rock, air-majority become air
        nextGrid[gy * gw + gx] = air >= 5 and 1 or 0
      end
    end
    grid = nextGrid
  end

  local function cell(gx, gy)
    gx = math.max(0, math.min(gw - 1, gx))
    gy = math.max(0, math.min(gh - 1, gy))
    return grid[gy * gw + gx]
  end
  for y = BORDER, HEIGHT - BORDER - 1 do
    local fy = y / CELL - 0.5
    local gy = math.floor(fy)
    local ty = fy - gy
    for x = BORDER, WIDTH - BORDER - 1 do
      local fx = x / CELL - 0.5
      local gx = math.floor(fx)
      local tx = fx - gx
      local top = cell(gx, gy) * (1 - tx) + cell(gx + 1, gy) * tx
      local bottom = cell(gx, gy + 1) * (1 - tx) + cell(gx + 1, gy + 1) * tx
      local v = top * (1 - ty) + bottom * ty + (love.math.noise(x * 0.15, y * 0.15, seed + 7) - 0.5) * 0.35
      if v > 0.5 then
        world:setRaw(x, y, AIR)
      end
    end
  end
end

-- The guaranteed route: a tunnel that only ever goes down (or level), so it
-- can always be traversed by walking and dropping.
local function carveMainTunnel(world, rng, seed, fromX, fromY, toX, toY)
  local points = { { fromX, fromY } }
  local y = fromY
  while y < toY - 140 do
    y = y + 100 + rng:random() * 60
    points[#points + 1] = { 70 + rng:random() * (WIDTH - 140), y }
  end
  points[#points + 1] = { toX, toY }

  for i = 1, #points - 1 do
    local ax, ay = points[i][1], points[i][2]
    local bx, by = points[i + 1][1], points[i + 1][2]
    local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    for s = 0, len, 2 do
      local t = s / len
      local cx, cy = ax + (bx - ax) * t, ay + (by - ay) * t
      -- Sideways wander only, so the tunnel still never climbs
      cx = cx + (love.math.noise(cy * 0.025, seed + 9) - 0.5) * 40
      local r = 11 + love.math.noise(cx * 0.03, cy * 0.03, seed + 3) * 6
      carveCircle(world, cx, cy, r)
    end
  end
end

local ENTRANCE_GAP = 16 -- half-width of the opening down into the main tunnel

local function carveEntrance(world, x, y)
  -- Chamber the player arrives in. Timber ledges either side, with a gap in
  -- the middle where the main tunnel drops away.
  -- Domed roof over a flat-floored lower half
  for yy = y - 26, y + 14 do
    for xx = x - 38, x + 38 do
      local dx, dy = (xx - x) / 38, (yy - y) / 26
      if yy >= y or dx * dx + dy * dy <= 1 then
        world:setRaw(xx, yy, AIR)
      end
    end
  end
  world:fillRect(x - 40, y + 15, x - ENTRANCE_GAP, y + 17, WOOD)
  world:fillRect(x + ENTRANCE_GAP, y + 15, x + 40, y + 17, WOOD)
  world:fillRect(x - ENTRANCE_GAP + 1, y + 15, x + ENTRANCE_GAP - 1, y + 24, AIR)
  -- Shaft above leading up toward the surface (sealed by bedrock at the top)
  world:fillRect(x - 10, BORDER, x + 10, y - 20, AIR)
  for yy = BORDER, y - 20 do
    world:setRaw(x - 11, yy, WOOD)
    world:setRaw(x + 11, yy, WOOD)
  end
end

-- Builds the brick shop room. Returns its interior rectangle.
local function buildShop(world, cx, floorY)
  local w, h = 150, 54
  local x0, y0 = math.floor(cx - w / 2), floorY - h
  local x1, y1 = x0 + w - 1, floorY - 1
  world:fillRect(x0 - 5, y0 - 5, x1 + 5, y1 + 5, BRICK)
  world:fillRect(x0, y0, x1, y1, AIR)
  -- Opening in the ceiling, with a short drop shaft up to where the tunnel ends
  world:fillRect(math.floor(cx) - 13, y0 - 34, math.floor(cx) + 13, y0 - 1, AIR)
  -- Wooden counter
  world:fillRect(x0 + 18, y1 - 9, x0 + 52, y1, WOOD)
  return { x = x0, y = y0, w = w, h = h }
end

-- Summed-area table of solid pixels, for O(1) "does the player fit here" checks
local function solidTable(world)
  local sat = {}
  local stride = WIDTH + 1
  for x = 0, WIDTH do
    sat[x] = 0
  end
  for y = 1, HEIGHT do
    local rowSum = 0
    sat[y * stride] = 0
    for x = 1, WIDTH do
      rowSum = rowSum + (world:isSolid(x - 1, y - 1) and 1 or 0)
      sat[y * stride + x] = sat[(y - 1) * stride + x] + rowSum
    end
  end
  return function(x, y, w, h)
    if x < 0 or y < 0 or x + w > WIDTH or y + h > HEIGHT then
      return false
    end
    local a = sat[y * stride + x]
    local b = sat[y * stride + x + w]
    local c = sat[(y + h) * stride + x]
    local d = sat[(y + h) * stride + x + w]
    return d - b - c + a == 0
  end
end

-- Breadth-first search over positions where the player fits, from the spawn
-- to inside the shop. A safety net on top of the always-descending tunnel.
local function isReachable(world, sx, sy, goal)
  local fits = solidTable(world)
  local STEP = 3
  local visited = {}
  local queue = { { sx, sy } }
  visited[sy * WIDTH + sx] = true
  local head = 1
  while head <= #queue do
    local p = queue[head]
    head = head + 1
    local x, y = p[1], p[2]
    if x >= goal.x and x <= goal.x + goal.w - PLAYER_W and y >= goal.y and y <= goal.y + goal.h - PLAYER_H then
      return true
    end
    for i = 1, 4 do
      local nx = x + (i == 1 and STEP or i == 2 and -STEP or 0)
      local ny = y + (i == 3 and STEP or i == 4 and -STEP or 0)
      local key = ny * WIDTH + nx
      if not visited[key] and fits(nx, ny, PLAYER_W, PLAYER_H) then
        visited[key] = true
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  return false
end

-- Finds spots on cave floors with open space above, for scattering props
local function findFloorSpots(world, rng, count, clearance, avoid)
  local spots = {}
  for _ = 1, count * 30 do
    if #spots >= count then
      break
    end
    local x = math.floor(BORDER + 4 + rng:random() * (WIDTH - 2 * BORDER - 8))
    local y = math.floor(BORDER + 60 + rng:random() * (HEIGHT - 200))
    if not world:isSolid(x, y) then
      local ground = world:findGround(x, y)
      -- Room above (allowing for a slightly sloped floor) and support below
      local open = true
      for oy = 3, clearance + 2 do
        for ox = -3, 3 do
          if world:isSolid(x + ox, ground - oy) then
            open = false
          end
        end
      end
      local supported = world:isSolid(x - 3, ground + 2) and world:isSolid(x + 3, ground + 2)
      if open and supported and ground < HEIGHT - BORDER and not avoid(x, ground) then
        spots[#spots + 1] = { x, ground }
      end
    end
  end
  return spots
end


-- Generates an area. Returns the world and a description of it:
--   { seed, attempts, spawnX, spawnY, shop = {x, y, w, h}, crates = {{x, groundY}}, ironCrates = ... }
-- Never fails: if no attempt validates, the last one gets a straight
-- emergency tunnel from the entrance to the shop.
local MAX_ATTEMPTS = 6

function cavegen.generate(seed)
  for attempt = 1, MAX_ATTEMPTS do
    local s = seed + (attempt - 1) * 7919
    local rng = love.math.newRandomGenerator(s)
    local noiseSeed = (s % 1000) + 0.5
    local world = World.new(WIDTH, HEIGHT)

    fillBase(world, noiseSeed)
    carveCaves(world, rng, noiseSeed)

    local entranceX, entranceY = WIDTH / 2, 60
    local shopX = 120 + rng:random() * (WIDTH - 240)
    local shopFloor = HEIGHT - BORDER - 30
    local tunnelEndY = shopFloor - 54 - 24
    carveMainTunnel(world, rng, noiseSeed, entranceX, entranceY, shopX, tunnelEndY)
    carveEntrance(world, entranceX, entranceY)
    local shop = buildShop(world, shopX, shopFloor)

    -- Bedrock shell
    world:fillRect(0, 0, WIDTH - 1, BORDER - 1, BEDROCK)
    world:fillRect(0, HEIGHT - BORDER, WIDTH - 1, HEIGHT - 1, BEDROCK)
    world:fillRect(0, 0, BORDER - 1, HEIGHT - 1, BEDROCK)
    world:fillRect(WIDTH - BORDER, 0, WIDTH - 1, HEIGHT - 1, BEDROCK)

    -- Spawn on the left timber ledge of the entrance chamber
    local spawnX = math.floor(entranceX - ENTRANCE_GAP - 14)
    local spawnY = world:findGround(spawnX + 2, entranceY) - PLAYER_H

    local reachable = isReachable(world, spawnX, spawnY, shop)
    if not reachable and attempt == MAX_ATTEMPTS then
      local len = math.sqrt((shopX - entranceX) ^ 2 + (tunnelEndY - entranceY) ^ 2)
      for d = 0, len, 2 do
        local t = d / len
        carveCircle(world, entranceX + (shopX - entranceX) * t, entranceY + (tunnelEndY - entranceY) * t, 12)
      end
      reachable = true
    end

    if reachable then
      local function avoid(x, y)
        local nearSpawn = math.abs(x - entranceX) < 50 and y < entranceY + 40
        local inShop = x > shop.x - 10 and x < shop.x + shop.w + 10 and y > shop.y - 10
        return nearSpawn or inShop
      end
      world:repaintAll()
      return world,
        {
          seed = seed,
          attempts = attempt,
          spawnX = spawnX,
          spawnY = spawnY,
          shop = shop,
          crates = findFloorSpots(world, rng, 14, 10, avoid),
          ironCrates = findFloorSpots(world, rng, 4, 12, avoid),
        }
    end
  end
end

return cavegen
