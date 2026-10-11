-- Procedural generation for a descending cave area (design doc §7), carved
-- into a region of the shared world below the surface: an entrance chamber at
-- the top (under the mine shaft), organic caves, large open caverns, several
-- routes of drops and level corridors that cross each other on the way down,
-- and the shop room at the bottom.
--
-- Generation is long-running, so every heavy loop calls tick() once per row:
-- the caller can yield there to spread the work over frames.
local config = require("src.config")
local materials = require("src.materials")

local AIR, DIRT, ROCK, BEDROCK = materials.AIR, materials.DIRT, materials.ROCK, materials.BEDROCK
local IRON = materials.IRON
local WOOD, BRICK, GOLDORE = materials.WOOD, materials.BRICK, materials.GOLDORE
local solid = materials.solid

local cavegen = {}

local BORDER = 13 -- bedrock thickness at the sides and bottom
local CELL = 10 -- cellular-automata cave grid resolution, in pixels
local BLEND = 24 -- the cave rock meets the surface's rock along a wavy line this tall
local PATHS = 3 -- routes from the entrance down to the shop
local ENTRANCE_GAP = 26 -- half-width of the opening down from the entrance chamber

local PLAYER_W, PLAYER_H = config.player.width, config.player.height

-- Generates a cave in world. area: { x0, y0, x1, y1, entranceX, entranceY }
-- (inclusive pixel bounds; the surface's rock, or the previous area, lies
-- above y0), plus optionally:
--   level          1 for the first area, 2 for the next... (monsters get tougher)
--   palette        { rock, dirt } material ids (default rock and dirt)
--   hasNext        true if another area lies below: the shop gets a hatch
--                  down to it, and the bottom is left open (no bedrock floor)
--   shaftX0/X1     x range of the shaft that drops into the entrance chamber
--   shaftTop       y where that shaft starts (default: just above y0)
--   glowCount      how many glowing mushroom clusters to scatter (default 150) tick: optional,
-- called regularly so a coroutine can yield. Returns a description:
--   { seed, area, spawnX, spawnY, shop = {x, y, w, h}, crates, ironCrates, chests, glows, enemies }
-- (spots are { x, groundY }). Never fails: if the reachability check can't
-- find a way down, a straight emergency tunnel is carved.
function cavegen.generate(world, area, seed, tick)
  tick = tick or function() end
  local X0, Y0, X1, Y1 = area.x0, area.y0, area.x1, area.y1
  local W, H = X1 - X0 + 1, Y1 - Y0 + 1
  local rng = love.math.newRandomGenerator(seed)
  local noiseSeed = (seed % 1000) + 0.5
  local level = area.level or 1
  local ROCKID = area.palette and area.palette.rock or ROCK
  local DIRTID = area.palette and area.palette.dirt or DIRT

  -- Carving never touches the bedrock shell or anything above the cave
  local function carvable(x, y)
    return x >= X0 + BORDER and x <= X1 - BORDER and y >= Y0 and y <= Y1 - BORDER
  end

  local function carveCircle(cx, cy, r)
    local r2 = r * r
    for y = math.floor(cy - r), math.ceil(cy + r) do
      for x = math.floor(cx - r), math.ceil(cx + r) do
        local dx, dy = x + 0.5 - cx, y + 0.5 - cy
        if dx * dx + dy * dy <= r2 and carvable(x, y) then
          world:setRaw(x, y, AIR)
        end
      end
    end
  end

  -- Base rock: dirt pockets in rock, dirt more common near the top. The top
  -- edge wavers so it doesn't meet the surface's sandstone in a straight line.
  local function fillBase()
    for y = Y0 - BLEND, Y1 do
      local depth = math.max(0, (y - Y0) / H)
      for x = X0, X1 do
        local top = Y0 - BLEND + math.floor(love.math.noise(x * 0.02, noiseSeed + 21) * BLEND)
        if y >= top then
          local n = love.math.noise(x * 0.011, y * 0.011, noiseSeed)
          world:setRaw(x, y, n > 0.38 + depth * 0.35 and DIRTID or ROCKID)
        end
      end
      tick()
    end
  end

  -- Organic caves via cellular automata on a coarse grid, then blended to
  -- pixel resolution with noise for natural edges. Kept clear of the top so
  -- the caves don't open into the surface.
  local function carveCaves()
    local gw, gh = math.ceil(W / CELL), math.ceil(H / CELL)
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
        tick()
      end
      grid = nextGrid
    end

    local function cell(gx, gy)
      gx = math.max(0, math.min(gw - 1, gx))
      gy = math.max(0, math.min(gh - 1, gy))
      return grid[gy * gw + gx]
    end
    for y = Y0 + 40, Y1 - BORDER - 1 do
      -- Harder to open up near the top, so caves there get rounded ceilings
      -- instead of all stopping at the same line
      local threshold = 0.5 + math.max(0, (Y0 + 110 - y) / 70)
      local fy = (y - Y0) / CELL - 0.5
      local gy = math.floor(fy)
      local ty = fy - gy
      for x = X0 + BORDER, X1 - BORDER do
        local fx = (x - X0) / CELL - 0.5
        local gx = math.floor(fx)
        local tx = fx - gx
        local top = cell(gx, gy) * (1 - tx) + cell(gx + 1, gy) * tx
        local bottom = cell(gx, gy + 1) * (1 - tx) + cell(gx + 1, gy + 1) * tx
        local v = top * (1 - ty) + bottom * ty + (love.math.noise(x * 0.094, y * 0.094, noiseSeed + 7) - 0.5) * 0.35
        if v > threshold then
          world:setRaw(x, y, AIR)
        end
      end
      tick()
    end
  end

  -- Large open caverns with ragged edges and flatter floors, each with a few
  -- rock ledges to climb on. They break up the cramped tunnels.
  local function carveCaverns()
    local count = 6 + rng:random(0, 2)
    for c = 1, count do
      local rx = 170 + rng:random() * 150
      local ry = 100 + rng:random() * 90
      local cx = X0 + BORDER + rx + 20 + rng:random() * (W - 2 * (BORDER + rx + 20))
      -- Spread them down the whole cave, one per band, with some jitter
      local band = (H - 600) / count
      local cy = Y0 + 320 + (c - 1 + 0.25 + rng:random() * 0.5) * band
      for y = math.floor(cy - ry * 1.3), math.ceil(cy + ry * 1.3) do
        local dy = (y - cy) / (y > cy and ry * 0.75 or ry) -- flatter below the middle
        for x = math.floor(cx - rx * 1.3), math.ceil(cx + rx * 1.3) do
          local dx = (x - cx) / rx
          local edge = (love.math.noise(x * 0.025, y * 0.025, noiseSeed + c) - 0.5) * 0.5
          if dx * dx + dy * dy + edge < 1 and carvable(x, y) then
            world:setRaw(x, y, AIR)
          end
        end
        tick()
      end
      for _ = 1, rng:random(3, 6) do
        local lw = 30 + rng:random() * 40
        local lx = cx + (rng:random() - 0.5) * rx * 1.3
        local ly = cy + (rng:random() * 0.8 - 0.3) * ry * 0.75
        for x = math.floor(lx - lw / 2), math.floor(lx + lw / 2) do
          local thick = 4 + math.floor(love.math.noise(x * 0.2, ly) * 4)
          for y = math.floor(ly), math.floor(ly) + thick do
            if carvable(x, y) then
              world:setRaw(x, y, ROCKID)
            end
          end
        end
      end
    end
  end

  -- Carves a straight passage from a to b, wandering a little to the side
  -- (sideways for drops, up and down only gently for corridors so they stay
  -- walkable)
  local function carveSegment(ax, ay, bx, by, r, wanderSeed)
    local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    if len < 1 then
      return
    end
    local vertical = math.abs(by - ay) > math.abs(bx - ax)
    for s = 0, len, 3 do
      local t = s / len
      local cx, cy = ax + (bx - ax) * t, ay + (by - ay) * t
      if vertical then
        cx = cx + (love.math.noise(cy * 0.015, wanderSeed) - 0.5) * 36
      else
        cy = cy + (love.math.noise(cx * 0.01, wanderSeed) - 0.5) * 14
      end
      carveCircle(cx, cy, r + (love.math.noise(cx * 0.03, cy * 0.03, wanderSeed + 3) - 0.5) * 6)
      if s % 30 == 0 then
        tick()
      end
    end
  end

  local function clampX(x)
    return math.max(X0 + 100, math.min(X1 - 100, x))
  end

  -- A route to the shop built from drops and level corridors (now and then a
  -- slanting drop instead), so it never climbs: it can always be traversed
  -- by walking and falling.
  local function carveRoute(fromX, fromY, toX, toY, r, wanderSeed)
    local x, y = fromX, fromY
    while y < toY - 320 do
      local drop = 220 + rng:random() * 260
      local nx = x
      if rng:random() < 0.3 then
        nx = clampX(x + (rng:random() * 2 - 1) * 220) -- a slanting drop
      end
      carveSegment(x, y, nx, y + drop, r, wanderSeed)
      x, y = nx, y + drop
      if y < toY - 320 then
        local dir = rng:random() < 0.5 and -1 or 1
        if x + dir * 300 > X1 - 100 or x + dir * 300 < X0 + 100 then
          dir = -dir
        end
        nx = clampX(x + dir * (300 + rng:random() * 700))
        carveSegment(x, y, nx, y, r, wanderSeed + 1)
        x = nx
      end
    end
    -- Last corridor over to above the shop, then down into it
    local lastY = math.max(y, toY - 200)
    carveSegment(x, y, x, lastY, r, wanderSeed)
    carveSegment(x, lastY, toX, lastY, r, wanderSeed + 1)
    carveSegment(toX, lastY, toX, toY, r, wanderSeed)
  end

  -- Extra corridors and drops scattered across the cave. They cut across
  -- the routes, so the routes join up and you can switch between them.
  local function carveCrossings()
    for i = 1, 10 do
      local y = Y0 + 200 + rng:random() * (H - 500)
      local len = 400 + rng:random() * 700
      local x = X0 + 100 + rng:random() * (W - 200 - len)
      carveSegment(x, y, x + len, y, 14 + rng:random() * 4, noiseSeed + 50 + i)
    end
    for i = 1, 6 do
      local x = X0 + 120 + rng:random() * (W - 240)
      local len = 350 + rng:random() * 550
      local y = Y0 + 150 + rng:random() * (H - 400 - len)
      carveSegment(x, y, x, y + len, 14 + rng:random() * 4, noiseSeed + 70 + i)
    end
  end

  -- Chamber the player arrives in from the shaft. Timber ledges either side,
  -- with a gap in the middle where the tunnels drop away.
  local function carveEntrance(x, y)
    for yy = y - 42, y + 22 do
      for xx = x - 61, x + 61 do
        local dx, dy = (xx - x) / 61, (yy - y) / 42
        if yy >= y or dx * dx + dy * dy <= 1 then
          world:setRaw(xx, yy, AIR)
        end
      end
    end
    world:fillRect(x - 64, y + 23, x - ENTRANCE_GAP, y + 27, WOOD)
    world:fillRect(x + ENTRANCE_GAP, y + 23, x + 64, y + 27, WOOD)
    world:fillRect(x - ENTRANCE_GAP + 1, y + 23, x + ENTRANCE_GAP - 1, y + 38, AIR)
    -- The surface's mine shaft continues down into the chamber's roof, lined
    -- with timber and open all the way, so the hunter drops straight through.
    if area.shaftX0 then
      local sx0, sx1 = area.shaftX0, area.shaftX1
      local top = area.shaftTop or (Y0 - BLEND - 4)
      world:fillRect(sx0, top, sx1, y - 30, AIR)
      world:fillRect(sx0 - 3, top, sx0 - 1, y - 38, WOOD)
      world:fillRect(sx1 + 1, top, sx1 + 3, y - 38, WOOD)
    end
  end

  -- Builds the brick shop room. Returns its interior rectangle, plus (when
  -- another area lies below) the hatch: an iron plate set into the floor near
  -- the right end, held shut by a chain the hunter has to shoot.
  local function buildShop(cx, floorY)
    local w, h = 620, 86
    local x0, y0 = math.floor(cx - w / 2), floorY - h
    local x1, y1 = x0 + w - 1, floorY - 1
    world:fillRect(x0 - 8, y0 - 8, x1 + 8, y1 + 8, BRICK)
    world:fillRect(x0, y0, x1, y1, AIR)
    -- Opening in the ceiling, with a short drop shaft up to where the tunnels end
    world:fillRect(math.floor(cx) - 21, y0 - 54, math.floor(cx) + 21, y0 - 1, AIR)
    local room = { x = x0, y = y0, w = w, h = h }
    if area.hasNext then
      local hx = x0 + w - 28
      world:fillRect(hx - 19, floorY, hx + 19, floorY + 3, IRON)
      room.hatch = { x0 = hx - 19, x1 = hx + 19, y0 = floorY, y1 = floorY + 3, cx = hx, floorY = floorY, ceilY = y0 }
    end
    return room
  end

  -- Breadth-first search from the spawn to inside the shop over a coarse
  -- grid of 4x4 blocks (a block is open if all its pixels are). The player
  -- fits where a 2x5 run of blocks is open. Conservative: it can miss narrow
  -- gaps, which only means an unneeded emergency tunnel.
  local function isReachable(sx, sy, goal)
    local B = 4
    local gw, gh = math.floor(W / B), math.floor(H / B)
    local open = {}
    for gy = 0, gh - 1 do
      for gx = 0, gw - 1 do
        local px, py = X0 + gx * B, Y0 + gy * B
        local free = true
        for y = py, py + B - 1 do
          for x = px, px + B - 1 do
            if solid[world:get(x, y)] then
              free = false
              break
            end
          end
          if not free then
            break
          end
        end
        open[gy * gw + gx] = free
      end
      tick()
    end
    local bw, bh = math.ceil(PLAYER_W / B), math.ceil(PLAYER_H / B)
    local function fits(gx, gy)
      if gx < 0 or gy < 0 or gx + bw > gw or gy + bh > gh then
        return false
      end
      for y = gy, gy + bh - 1 do
        for x = gx, gx + bw - 1 do
          if not open[y * gw + x] then
            return false
          end
        end
      end
      return true
    end
    local goalX0, goalY0 = math.floor((goal.x - X0) / B), math.floor((goal.y - Y0) / B)
    local goalX1, goalY1 = math.floor((goal.x + goal.w - X0) / B) - bw, math.floor((goal.y + goal.h - Y0) / B) - bh
    -- Start from the nearest grid position at or above the spawn that fits
    local startX, startY = math.floor((sx - X0) / B), math.floor((sy - Y0) / B)
    while startY > 0 and not fits(startX, startY) do
      startY = startY - 1
    end
    local visited = { [startY * gw + startX] = true }
    local queue = { startY * gw + startX }
    local head = 1
    while head <= #queue do
      local key = queue[head]
      head = head + 1
      local x, y = key % gw, math.floor(key / gw)
      if x >= goalX0 and x <= goalX1 and y >= goalY0 and y <= goalY1 then
        return true
      end
      for i = 1, 4 do
        local nx = x + (i == 1 and 1 or i == 2 and -1 or 0)
        local ny = y + (i == 3 and 1 or i == 4 and -1 or 0)
        local nkey = ny * gw + nx
        if not visited[nkey] and fits(nx, ny) then
          visited[nkey] = true
          queue[#queue + 1] = nkey
        end
      end
      if head % 2000 == 0 then
        tick()
      end
    end
    return false
  end

  -- Finds spots on cave floors with open space above, for scattering props
  local function findFloorSpots(count, clearance, avoid)
    local spots = {}
    for _ = 1, count * 30 do
      if #spots >= count then
        break
      end
      tick()
      local x = math.floor(X0 + BORDER + 6 + rng:random() * (W - 2 * BORDER - 12))
      local y = math.floor(Y0 + 96 + rng:random() * (H - 320))
      if not world:isSolid(x, y) then
        local ground = world:findGround(x, y)
        -- Room above (allowing for a slightly sloped floor) and support below
        local isOpen = true
        for oy = 5, clearance + 3 do
          for ox = -5, 5 do
            if world:isSolid(x + ox, ground - oy) then
              isOpen = false
            end
          end
        end
        local supported = world:isSolid(x - 5, ground + 3) and world:isSolid(x + 5, ground + 3)
        if isOpen and supported and ground < Y1 - BORDER and not avoid(x, ground) then
          spots[#spots + 1] = { x, ground }
        end
      end
    end
    return spots
  end

  -- Spots under cave ceilings with open space below, for things that hang
  -- (bats, spitters). Returns { x, y } with y the first open row under the rock.
  local function findCeilingSpots(count, clearance, avoid)
    local spots = {}
    for _ = 1, count * 30 do
      if #spots >= count then
        break
      end
      tick()
      local x = math.floor(X0 + BORDER + 8 + rng:random() * (W - 2 * BORDER - 16))
      local y = math.floor(Y0 + 120 + rng:random() * (H - 320))
      if not world:isSolid(x, y) then
        local ceiling = y
        while ceiling > Y0 and not world:isSolid(x, ceiling - 1) do
          ceiling = ceiling - 1
        end
        local ok = ceiling > Y0 + 40 and y - ceiling < 400
        -- Rock across the top to cling to, and room beneath
        for ox = -4, 4 do
          if not world:isSolid(x + ox, ceiling - 1) then
            ok = false
          end
          for oy = 0, clearance do
            if world:isSolid(x + ox, ceiling + oy) then
              ok = false
            end
          end
        end
        if ok and not avoid(x, ceiling) then
          spots[#spots + 1] = { x, ceiling }
        end
      end
    end
    return spots
  end

  -- Veins of gold ore: wandering blobs in solid rock and dirt, some right
  -- at a cave wall (glinting where they can be seen) and some buried deep
  local function placeOre()
    for _ = 1, 150 do
      tick()
      local x = X0 + BORDER + 20 + rng:random() * (W - 2 * BORDER - 40)
      local y = Y0 + 140 + rng:random() * (H - 300)
      local r = 4 + rng:random() * 5
      for oy = -r, r do
        for ox = -r, r do
          local px, py = math.floor(x + ox), math.floor(y + oy)
          local id = world:get(px, py)
          if ox * ox + oy * oy <= r * r and (id == ROCKID or id == DIRTID) then
            world:setRaw(px, py, GOLDORE)
          end
        end
      end
    end
  end

  fillBase()
  carveCaves()
  placeOre()
  carveCaverns()

  local entranceX, entranceY = area.entranceX, area.entranceY
  local shopX = X0 + 340 + rng:random() * (W - 680)
  local shopFloor = Y1 - BORDER - 48
  local tunnelEndY = shopFloor - 86 - 38
  -- One wide main route and narrower side routes; they wander independently,
  -- so they cross each other on the way down
  for p = 1, PATHS do
    carveRoute(entranceX, entranceY, shopX, tunnelEndY, p == 1 and 21 or 17, noiseSeed + p * 13)
  end
  carveCrossings()
  carveEntrance(entranceX, entranceY)
  local shop = buildShop(shopX, shopFloor)

  -- Bedrock shell at the sides, and at the bottom of the last area (the
  -- surface's rock, or the previous area, is above)
  if not area.hasNext then
    world:fillRect(X0, Y1 - BORDER + 1, X1, Y1, BEDROCK)
  end
  world:fillRect(X0, Y0 - BLEND, X0 + BORDER - 1, Y1, BEDROCK)
  world:fillRect(X1 - BORDER + 1, Y0 - BLEND, X1, Y1, BEDROCK)

  -- Spawn spot (used when starting in the cave): the entrance's left ledge
  local spawnX = math.floor(entranceX - ENTRANCE_GAP - 22)
  local spawnY = world:findGroundUnder(spawnX, PLAYER_W, entranceY) - PLAYER_H

  if not isReachable(spawnX, spawnY, shop) then
    local len = math.sqrt((shopX - entranceX) ^ 2 + (tunnelEndY - entranceY) ^ 2)
    for d = 0, len, 3 do
      local t = d / len
      carveCircle(entranceX + (shopX - entranceX) * t, entranceY + (tunnelEndY - entranceY) * t, 19)
    end
    print("cavegen: no route found, carved an emergency tunnel (seed " .. seed .. ")")
  end

  local function avoid(x, y)
    local nearSpawn = math.abs(x - entranceX) < 80 and y < entranceY + 64
    local inShop = x > shop.x - 16 and x < shop.x + shop.w + 16 and y > shop.y - 16
    return nearSpawn or inShop
  end
  world:repaintRect(X0, math.min(Y0 - BLEND - 16, (area.shaftTop or math.huge) - 16), X1, Y1, tick)

  -- Monsters: none near the entrance or in the shop. More of them, and
  -- tougher, the deeper you go.
  local function avoidForEnemies(x, y)
    local nearEntrance = math.abs(x - entranceX) < 260 and y < entranceY + 220
    local inShop = x > shop.x - 60 and x < shop.x + shop.w + 60 and y > shop.y - 120
    return nearEntrance or inShop
  end
  local enemies = {}
  local function place(kind, spots)
    for _, s in ipairs(spots) do
      local depth = (s[2] - Y0) / H
      local crowded = false
      for _, m in ipairs(enemies) do
        if math.abs(m.x - s[1]) < 48 and math.abs(m.y - s[2]) < 48 then
          crowded = true -- keep them spread out instead of in clumps
        end
      end
      if not crowded and rng:random() < 0.35 + 0.65 * depth then
        enemies[#enemies + 1] = { kind = kind, x = s[1], y = s[2], toughness = 1 + depth * 0.6 + (level - 1) * 0.6 }
      end
    end
  end
  place("ghoul", findFloorSpots(60, 18, avoidForEnemies))
  place("bat", findCeilingSpots(40, 24, avoidForEnemies))
  place("spitter", findCeilingSpots(26, 30, avoidForEnemies))

  return {
    seed = seed,
    area = area,
    spawnX = spawnX,
    spawnY = spawnY,
    shop = shop,
    crates = findFloorSpots(40, 16, avoid),
    ironCrates = findFloorSpots(12, 19, avoid),
    chests = findFloorSpots(12, 22, avoidForEnemies), -- weapon chests, away from the entrance and shop
    glows = findFloorSpots(area.glowCount or 150, 6, avoid), -- glowing fungus clusters
    level = level,
    enemies = enemies, -- { kind, x, y, toughness }: ghouls stand at y, the others hang from it
  }
end

return cavegen
