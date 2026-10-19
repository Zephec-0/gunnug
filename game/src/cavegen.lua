-- Procedural generation for a descending cave area (design doc §7), carved
-- into a region of the shared world below the surface: an entrance chamber at
-- the top (under the mine shaft), organic caves, large open caverns, several
-- routes of drops and level corridors that cross each other on the way down,
-- and the shop room at the bottom. The lowest part of the area narrows into a
-- funnel toward the shop, ending in a bowl-shaped antechamber over it, so
-- whichever way the hunter comes down he is drawn toward the shop.
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
local PATHS = 4 -- routes from the entrance down to the shop
local REF_AREA = 1920 * 3680 -- the area size the counts below were tuned for
local FUNNEL = 0.3 -- the bottom part of the area (of its height) that narrows toward the shop
local FUNNEL_NECK = 270 -- half-width of the funnel at its bottom
local POOL_CELL = 4 -- gas and water pools are flood-filled on a grid of this many pixels (src.fluids' grid)

-- Sizes of the monsters (w, h) and whether they stand on the floor (else they
-- hang or float at the spot), for finding room to put them
local SIZES = {
  ghoul = { 12, 19, true },
  hopper = { 12, 9, true },
  bat = { 10, 7 },
  swarmbat = { 10, 7 },
  spitter = { 10, 8 },
  bloater = { 14, 14 },
  wisp = { 8, 8 },
  miner = { 10, 19, true },
  roller = { 12, 10, true },
  worm = { 6, 6 },
  queen = { 84, 84 },
  warden = { 24, 38, true }, -- the bosses
  golem = { 56, 84, true },
  matron = { 24, 18, true },
  behemoth = { 28, 28 },
  dreadbat = { 30, 21, false, true }, -- (the fourth entry: hangs from a ceiling)
  darkhunter = { 8, 19, true },
  crow = { 10, 8, false, true }, -- the Needle's creatures
  cragram = { 22, 15, true },
  dustdevil = { 14, 22 },
  gargoyle = { 14, 16, false, true },
}
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
--   glowCount      how many glowing mushroom clusters to scatter (default 150)
--   gasPools       how many pools of poison gas to settle in low spots (default 0)
--   waterPools     how many pools of water to settle in low spots (default 0)
--   lavaPools      how many pools of lava (default 0); acidPools the same for acid
--   flood          { level }: flood every open cell below level px under the top
--   arenaFrac, arenaH, arenaWidth   where the arena starts (fraction of the height, default 0.75),
--                  how tall (400) and how wide (fraction of the width, 0.52) it is
--   bossReward     a perk id the boss drops
--   climb          true: a climbing area (a mountain): the entrance is at the bottom and the
--                  routes go UP, with ladders of one-way platforms in the climbs, to the arena
--                  at the top (arenaFrac small, arenaCx its centre). No shop: the arena's exit
--                  shaft (info.exit) leads up and out through a gate that opens with the boss.
--   profile        function(y) -> xLeft, xRight: the area's silhouette (rows outside it are left
--                  alone, as sky); groundY: where the silhouette meets the ground
--   open           true: a very open area (the sky): no caves, floating islands and spires over a
--                  thick floor, an entrance hole through the floor, one shop at the far end
--   monsters       { kind = count } per 1920x3680 of area (default ghoul 60, bat 40, spitter 26)
--   boss           kind of the area's one boss (see src.enemies), if any; a
--                  list picks one of them at random for each run
--   swarms         { kind = count } per 1920x3680: colonies of swarmbat (8-12) or wisp (4-6)
--   arena          true: a boss arena (a huge flat-floored chamber over 2000 px wide) fills
--                  the last quarter, all the routes lead into it, and its floor has two
--                  gated shafts, left and right, each dropping into its own shop (the
--                  returned info.shops); the boss (area.boss) waits in the middle
-- tick: optional, called regularly so a coroutine can yield. Returns a description:
--   { seed, area, spawnX, spawnY, shop = {x, y, w, h}, crates, ironCrates, chests, glows, breakables, enemies, gas }
-- (spots are { x, groundY }). Never fails: if the reachability check can't
-- find a way down, a straight emergency tunnel is carved.
function cavegen.generate(world, area, seed, tick)
  tick = tick or function() end
  local X0, Y0, X1, Y1 = area.x0, area.y0, area.x1, area.y1
  local W, H = X1 - X0 + 1, Y1 - Y0 + 1
  local rng = love.math.newRandomGenerator(seed)
  local noiseSeed = (seed % 1000) + 0.5
  local level = area.level or 1
  -- This rectangle is painted here, not on demand
  world:claim(X0, math.min(Y0 - 24 - 16, (area.shaftTop or math.huge) - 16), X1, Y1)
  local ROCKID = area.palette and area.palette.rock or ROCK
  local DIRTID = area.palette and area.palette.dirt or DIRT
  -- Counts below scale with the area's size
  local scale = W * H / REF_AREA
  local function scaled(n)
    return math.floor(n * scale + 0.5)
  end

  -- The shop sits somewhere along the bottom; the funnel narrows toward it
  local shopX = X0 + 420 + rng:random() * (W - 840) -- (the room is 700 wide)
  local shopFloor = Y1 - BORDER - 48
  local tunnelEndY = shopFloor - 86 - 38
  local antechamberY = tunnelEndY - 70 -- centre of the bowl over the shop
  local funnel = {
    x = shopX,
    top = antechamberY - math.floor(H * FUNNEL),
    bottom = antechamberY,
    wide = math.max(shopX - X0, X1 - shopX),
  }

  -- The boss arena: a boxy chamber starting at the last quarter of the area
  local arena
  local shopXs = { shopX }
  if area.arena then
    arena = { cx = area.arenaCx or (X0 + W / 2), w = math.floor(W * (area.arenaWidth or 0.52)), top = Y0 + math.floor(H * (area.arenaFrac or 0.75)), h = area.arenaH or 400 }
    arena.floorY = arena.top + arena.h
    arena.shape = area.arenaShape
    arena.x0 = math.floor(arena.cx - arena.w / 2)
    arena.x1 = arena.x0 + arena.w - 1
    shopXs = { X0 + W * 0.3, X0 + W * 0.7 } -- a shop at each lower corner
    funnel.top = math.huge -- (no funnel: the arena is the gathering place)
  end
  local climb, open, profile = area.climb, area.open, area.profile
  if climb then
    shopXs = {} -- (a climbing area has no shop: its arena's exit leads on)
  elseif open then
    shopXs = { X0 + 700 } -- one shop, at the far end from the way in
  end
  if climb or open then
    funnel.top = math.huge
  end
  -- Inside the area's silhouette, m px in from its edge (always true without one)
  local function inProfile(x, y, m)
    if not profile then
      return true
    end
    if y < Y0 + m then
      return false
    end
    local xa, xb = profile(y)
    return xa ~= nil and x >= xa + m + (area.caveInset or 0) and x <= xb - m
  end
  local function inArena(x, y, margin)
    return arena and x > arena.x0 - margin and x < arena.x1 + margin and y > arena.top - margin and y < arena.floorY + margin
  end

  -- Half-width of the open funnel at depth y (the whole area above it)
  local function funnelHalf(y)
    if y < funnel.top then
      return math.huge
    end
    local t = math.min(1, (y - funnel.top) / (funnel.bottom - funnel.top))
    return funnel.wide + (FUNNEL_NECK - funnel.wide) * t
  end

  -- Inside the funnel, with a ragged edge
  local function inFunnel(x, y)
    if profile and not inProfile(x, y, climb and 64 or 36) then
      return false
    end
    if y < funnel.top then
      return true
    end
    local wobble = love.math.noise(y * 0.012, x * 0.004, noiseSeed + 90) * 44 - 10
    return math.abs(x - funnel.x) <= funnelHalf(y) + wobble
  end

  -- Carving never touches the bedrock shell, anything above the cave, or the
  -- rock walls of the funnel
  local function carvable(x, y)
    return x >= X0 + BORDER and x <= X1 - BORDER and y >= Y0 and y <= Y1 - BORDER and inFunnel(x, y)
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
    if open then
      -- Only the thick floor; the rest is sky
      local floorTop = Y1 - 200
      for y = floorTop - 30, Y1 do
        for x = X0, X1 do
          local bumps = math.floor(love.math.noise(x * 0.015, noiseSeed + 21) * 12)
          if materials.defs[DIRTID] and materials.defs[DIRTID].cloud then
            bumps = math.floor(love.math.noise(x * 0.012, noiseSeed + 21) * 26 - math.abs(math.sin(x * 0.021 + love.math.noise(x * 0.004, noiseSeed) * 6)) * 14)
          end
          if y >= floorTop + bumps then
            local n = love.math.noise(x * 0.011, y * 0.011, noiseSeed)
            world:setRaw(x, y, n > 0.5 and DIRTID or ROCKID)
          end
        end
        tick()
      end
      return
    end
    for y = (climb and Y0 or Y0 - BLEND), Y1 do
      local depth = math.max(0, (y - Y0) / H)
      local xa, xb = X0, X1
      if profile then
        xa, xb = profile(y)
      end
      if xa then
        for x = xa, xb do
          local top = climb and Y0 or Y0 - BLEND + math.floor(love.math.noise(x * 0.02, noiseSeed + 21) * BLEND)
          if y >= top then
            local n = love.math.noise(x * 0.011, y * 0.011, noiseSeed)
            world:setRaw(x, y, n > 0.38 + depth * 0.35 and DIRTID or ROCKID)
          end
        end
      end
      tick()
    end
  end

  -- Organic caves via cellular automata on a coarse grid, then blended to
  -- pixel resolution with noise for natural edges. Kept clear of the top so
  -- the caves don't open into the surface.
  local function carveCaves()
    if open then
      return
    end
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
        if v > threshold and inFunnel(x, y) then
          world:setRaw(x, y, AIR)
        end
      end
      tick()
    end
  end

  -- Large open caverns with ragged edges and flatter floors, each with a few
  -- rock ledges to climb on. They break up the cramped tunnels.
  local function carveCaverns()
    if open then
      return
    end
    local count = scaled(6 + rng:random(0, 2))
    for c = 1, count do
      local rx = 170 + rng:random() * 150
      local ry = 100 + rng:random() * 90
      local cx = X0 + BORDER + rx + 20 + rng:random() * (W - 2 * (BORDER + rx + 20))
      -- Spread them down the whole cave, one per band, with some jitter
      local band = (H - 600) / count
      local cy = Y0 + 320 + (c - 1 + 0.25 + rng:random() * 0.5) * band
      -- Down in the funnel, keep them inside it
      if cy > funnel.top then
        local half = funnelHalf(cy) * 0.6
        cx = math.max(funnel.x - half, math.min(funnel.x + half, cx))
      end
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

  -- Keeps a route away from the side walls and inside the funnel at depth y
  -- (with room for the passage's width and wander, so the funnel's rock walls
  -- never cut it)
  local function clampX(x, y)
    local half = math.min(W, funnelHalf(y)) - 64
    return math.max(X0 + 100, math.min(X1 - 100, math.max(funnel.x - half, math.min(funnel.x + half, x))))
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
        nx = x + (rng:random() * 2 - 1) * 220 -- a slanting drop
      end
      -- (a drop into the funnel may have to slant inward)
      nx = clampX(nx, y + drop)
      carveSegment(x, y, nx, y + drop, r, wanderSeed)
      x, y = nx, y + drop
      if y < toY - 320 then
        local dir = rng:random() < 0.5 and -1 or 1
        if x + dir * 300 > X1 - 100 or x + dir * 300 < X0 + 100 then
          dir = -dir
        end
        -- In the funnel, corridors head toward the shop
        if y > funnel.top then
          dir = toX > x and 1 or -1
        end
        nx = clampX(x + dir * (300 + rng:random() * 700), y)
        carveSegment(x, y, nx, y, r, wanderSeed + 1)
        x = nx
      end
    end
    -- Last corridor over to above the shop, then down into it
    local lastY = math.max(y, toY - 200)
    local lx = clampX(x, lastY)
    carveSegment(x, y, lx, lastY, r, wanderSeed)
    carveSegment(lx, lastY, toX, lastY, r, wanderSeed + 1)
    carveSegment(toX, lastY, toX, toY, r, wanderSeed)
  end

  -- Extra corridors and drops scattered across the cave. They cut across
  -- the routes, so the routes join up and you can switch between them.
  local ladders = {} -- one-way platforms for climbing: { x0, x1, y }

  -- A ladder up a vertical shaft carved from (x, yBottom) to (x, yTop) with
  -- seed wanderSeed (see carveSegment): a platform every 28 px, one side then
  -- the other, each inside the shaft, so it can be climbed by jumping
  local function addLadder(x, yBottom, yTop, wanderSeed)
    local side = 1
    for y = math.floor(yBottom - 26), math.floor(yTop), -28 do
      local cx = x + (love.math.noise(y * 0.015, wanderSeed) - 0.5) * 36 + side * 6
      ladders[#ladders + 1] = { x0 = math.floor(cx - 13), x1 = math.floor(cx + 13), y = y }
      side = -side
    end
  end

  local function carveCrossings()
    if open then
      return
    end
    for i = 1, scaled(10) do
      local y = Y0 + 200 + rng:random() * (H - 500)
      local len = 400 + rng:random() * 700
      local x = X0 + 100 + rng:random() * (W - 200 - len)
      carveSegment(x, y, x + len, y, 14 + rng:random() * 4, noiseSeed + 50 + i)
    end
    for i = 1, scaled(6) do
      local x = X0 + 120 + rng:random() * (W - 240)
      local len = 350 + rng:random() * 550
      local y = Y0 + 150 + rng:random() * (H - 400 - len)
      carveSegment(x, y, x, y + len, 14 + rng:random() * 4, noiseSeed + 70 + i)
      if climb then
        addLadder(x, y + len, y, noiseSeed + 70 + i)
      end
    end
  end

  -- The bowl at the bottom of the funnel, right over the shop: its floor
  -- curves down from both sides to the drop into the shop's ceiling
  local function carveAntechamber()
    local cx, cy = funnel.x, antechamberY
    local rx, ryUp, ryDown = FUNNEL_NECK - 20, 70, 62
    for y = cy - ryUp - 20, cy + ryDown + 10 do
      for x = math.floor(cx - rx - 20), math.ceil(cx + rx + 20) do
        local dx = (x - cx) / rx
        local dy = (y - cy) / (y > cy and ryDown or ryUp)
        local edge = (love.math.noise(x * 0.03, y * 0.03, noiseSeed + 33) - 0.5) * 0.35
        if dx * dx + dy * dy + edge < 1 and carvable(x, y) then
          world:setRaw(x, y, AIR)
        end
      end
      tick()
    end
    -- Down from the bowl's lowest point to the shop
    carveSegment(cx, cy + ryDown - 10, cx, tunnelEndY + 10, 18, noiseSeed + 44)
  end

  -- The arena: a wide boxy chamber (a superellipse), a flat slab for a floor,
  -- and a V of platforms above it
  local function carveArena()
    local a = arena
    local cx, cy = a.cx, a.top + a.h / 2
    local rx, ry = a.w / 2, a.h / 2
    for y = a.top - 4, a.floorY + 2 do
      for x = a.x0 - 4, a.x1 + 4 do
        local nx, ny = (x - cx) / rx, (y - cy) / ry
        local edge = (love.math.noise(x * 0.02, y * 0.02, noiseSeed + 61) - 0.5) * 0.12
        local shaped
        if area.arenaShape == "round" then
          shaped = nx ^ 2 + ny ^ 2 + edge < 1 -- (an oval, for a boss in water)
        elseif area.arenaShape == "rect" then
          shaped = math.abs(nx) < 1 and math.abs(ny) < 1 -- (a walled hall)
        else
          shaped = nx ^ 8 + ny ^ 2 + edge < 1
        end
        if shaped and carvable(x, y) then
          world:setRaw(x, y, AIR)
        end
      end
      tick()
    end
    if area.arenaShape ~= "round" then
      world:fillRect(a.x0 - 4, a.floorY, a.x1 + 4, a.floorY + 16, ROCKID)
    end
    if area.arenaShape == "rect" then
      -- A flat floor: layers of rock and packed dirt, built up in bands, nothing to snag on
      for y = a.floorY - 24, a.floorY - 6 do
        world:fillRect(a.x0, y, a.x1, y, (math.floor((y - a.floorY) / 4) % 2 == 0) and ROCKID or DIRTID)
      end
      world:fillRect(a.x0, a.floorY - 5, a.x1, a.floorY - 1, DIRTID)
      world:fillRect(a.x0, a.floorY - 2, a.x1, a.floorY - 1, ROCKID)
      world:fillRect(a.x0, a.floorY - 1, a.x1, a.floorY, DIRTID)
      -- ...and short stalactites hanging from the ceiling
      local x = a.x0 + 20
      while x < a.x1 - 20 do
        local len = 10 + rng:random() * 22
        local half = 3 + rng:random() * 5
        for dy = 0, math.floor(len) do
          local w = math.floor(half * (1 - dy / len) + 0.5)
          world:fillRect(x - w, a.top + dy, x + w, a.top + dy, ROCKID)
        end
        x = x + 60 + rng:random() * 110
      end
    end
    -- Platforms in a V from the middle: a low pair just either side of the
    -- centre, then each one further out a step higher (32 px: within a
    -- jump) and a short hop across, six to a side, so the hunter can climb
    -- either arm
    -- They are one-way slabs, not terrain (see src.world platforms): stood on
    -- from above, jumped up through, and shot, flown and gassed through
    a.platforms = {}
    if area.platformStyle == "edges" and not area.noPlatforms then
      -- Ledges round the outer edges of the oval, alternately low and high so each
      -- is a hop from the last, and nothing across the middle
      local ryy = a.h / 2
      for side = -1, 1, 2 do
        local prevY
        for i, f in ipairs({ 0.44, 0.58, 0.71, 0.82 }) do
          local fy = cy + ryy * math.sqrt(1 - f * f)
          local lx = a.cx + side * f * rx
          local ly = fy - (i % 2 == 1 and 28 or 50)
          -- (never more than a jump (about 41 px) above the last one, or the floor)
          ly = math.max(ly, (prevY or fy) - 34)
          prevY = ly
          a.platforms[#a.platforms + 1] = { x0 = math.floor(lx - 34), x1 = math.floor(lx + 34), y = math.floor(ly) }
        end
      end
    end
    for side = -1, 1, 2 do
      for i = 0, ((area.noPlatforms or area.platformStyle == "edges") and -1 or 5) do
        local lx = a.cx + side * (70 + i * 120)
        local ly = a.floorY - 36 - i * 32
        a.platforms[#a.platforms + 1] = { x0 = math.floor(lx - 42), x1 = math.floor(lx + 42), y = math.floor(ly) }
      end
    end
    -- Braziers: fire bowls along the floor that keep burning (src.fluids)
    a.braziers = {}
    for _, f in ipairs(area.noBraziers and {} or { -0.30, -0.15, 0, 0.15, 0.30 }) do
      local bx = math.floor(a.cx + f * a.w)
      a.braziers[#a.braziers + 1] = { x = bx, y = world:findGround(bx, a.floorY - 40) }
    end
    a.gates = {}
  end

  -- A route UP to (toX, toY) for a climbing area: climbs (vertical shafts with
  -- ladders) of 200-420 px alternating with level corridors
  local function clampUp(x, y)
    local xa, xb = X0, X1
    if profile then
      xa, xb = profile(y)
      xa = xa or X0
      xb = xb or X1
      xa = xa + (area.caveInset or 0)
    end
    return math.max(xa + 100, math.min(xb - 100, x))
  end

  local function carveRouteUp(fromX, fromY, toX, toY, r, wanderSeed)
    local x, y = fromX, fromY
    while y > toY + 420 do
      local climbLen = 200 + rng:random() * 220
      local seed = wanderSeed + math.floor(y)
      carveSegment(x, y, x, y - climbLen, r, seed)
      addLadder(x, y, y - climbLen, seed)
      y = y - climbLen
      if y > toY + 420 then
        local dir = rng:random() < 0.5 and -1 or 1
        local nx = clampUp(x + dir * (300 + rng:random() * 500), y)
        if math.abs(nx - x) < 150 then
          nx = clampUp(x - dir * (300 + rng:random() * 500), y)
        end
        carveSegment(x, y, nx, y, r, wanderSeed + 1)
        x = nx
      end
    end
    -- Over to under the goal, then the last climb
    local gx = clampUp(toX, y)
    carveSegment(x, y, gx, y, r, wanderSeed + 1)
    local seed = wanderSeed + 99
    carveSegment(gx, y, gx, toY, r, seed)
    addLadder(gx, y, toY, seed)
  end

  -- A climbing area's way in: a doorway into the mountain's face at ground
  -- level and a chamber behind it, no drop. Carved straight (not limited to the
  -- silhouette's margin, which would leave the face closed).
  local function carveWalkIn(ex, ey)
    local edgeX = profile(ey) or X0
    local ground = world:findGround(edgeX - 8, ey - 90)
    local cy = ground - 18
    -- A long gentle passage: wide at the mouth, narrowing and winding a little
    -- before it opens into the chamber, so the way in eases from the desert
    -- into the dark rather than being a hole in a cliff
    -- The passage runs about half the mountain's width in, lined with rock so
    -- the caves don't break into it: it only opens up at the chamber
    -- The mouth is flared and arched: taller at the face and easing down to the
    -- passage over ~70 px, with a ragged edge, and its floor follows the desert
    -- ground in so there is no lip to step over
    local function passage(x)
      local t = math.max(0, math.min(1, (x - edgeX) / math.max(1, ex - edgeX)))
      local r = 22 - 6 * math.min(1, t * 3)
      local mid = cy + math.sin((x - edgeX) * 0.011) * 7 * math.min(1, t * 4) * math.min(1, (1 - t) * 6)
      local mouth = math.max(0, 1 - (x - edgeX) / 70) -- 1 at the face, 0 inside
      if mouth > 0 then
        local ragged = love.math.noise(x * 0.09, noiseSeed + 77) * 5
        local extra = (16 * mouth * mouth + ragged * mouth)
        local floorY = mid + r - 4 * mouth -- (the floor settles to the desert ground; the roof lifts)
        r = r + extra / 2
        mid = floorY - r
        r = math.max(r, 1)
      end
      return mid, r
    end
    for x = edgeX + 4, ex - 60 do
      local mid, r = passage(x)
      local lining = r + 14 + math.floor(love.math.noise(x * 0.05, noiseSeed + 61) * 8)
      for y = math.floor(mid - lining), math.ceil(mid + lining) do
        if not world:isSolid(x, y) then
          world:setRaw(x, y, ROCKID)
        end
      end
    end
    for x = edgeX - 14, ex do
      local mid, r = passage(x)
      for y = math.floor(mid - r), math.ceil(mid + r) do
        local dy = y - mid
        if dy * dy <= r * r then
          world:setRaw(x, y, AIR)
        end
      end
      if x % 40 == 0 then
        tick()
      end
    end
    for y = cy - 40, cy + 17 do
      for x = ex - 70, ex + 70 do
        local dx, dy = (x - ex) / 70, (y - cy) / 40
        if y >= cy - 4 or dx * dx + dy * dy <= 1 then
          world:setRaw(x, y, AIR)
        end
      end
    end
    return cy
  end

  -- The sky: rock islands (flat on top, tapering below) and spires, scattered
  -- through the open air over the floor
  local function carveIslands()
    local floorTop = Y1 - 200
    local placed = {}
    -- Keep the sky clear over the shop and over the hole where the way in arrives
    local keepClear = { { (shopXs[1] or X0) - 90, (shopXs[1] or X0) + 90 } }
    if area.shaftX0 then
      keepClear[#keepClear + 1] = { area.shaftX0 - 110, area.shaftX1 + 110 }
    end
    local function clear(x0, x1)
      for _, k in ipairs(keepClear) do
        if x1 > k[1] and x0 < k[2] then
          return false
        end
      end
      return true
    end
    local wanted = scaled(70)
    for _ = 1, wanted * 4 do
      if #placed >= wanted then
        break
      end
      local rx, ry = 45 + rng:random() * 170, 14 + rng:random() * 30
      -- (cloud islands heap up into billows on top instead of a flat crust)
      local puffy = materials.defs[DIRTID] and materials.defs[DIRTID].cloud
      local up, wob = puffy and ry * 1.1 or ry * 0.4, puffy and 0.75 or 0.4
      local cx = X0 + BORDER + rx + 50 + rng:random() * (W - 2 * (BORDER + rx + 50))
      local cy = Y0 + 110 + rng:random() * (floorTop - Y0 - 260)
      local ok = clear(cx - rx * 1.2, cx + rx * 1.2)
      for _, o in ipairs(placed) do
        local nx, ny = (cx - o.cx) / (rx + o.rx + 40), (cy - o.cy) / (ry + o.ry + 70)
        if nx * nx + ny * ny < 1 then
          ok = false
          break
        end
      end
      if ok then
        placed[#placed + 1] = { cx = cx, cy = cy, rx = rx, ry = ry }
        for y = math.floor(cy - up * 1.3), math.ceil(cy + ry * 2) do
          local dy = (y - cy) / (y < cy and up or ry * 1.8)
          for x = math.floor(cx - rx * 1.2), math.ceil(cx + rx * 1.2) do
            local dx = (x - cx) / rx
            local edge = (love.math.noise(x * 0.04, y * 0.04, noiseSeed + 5) - 0.5) * wob
            if puffy and y < cy then
              edge = edge - (love.math.noise(x * 0.025, noiseSeed + 7) - 0.45) * 0.9
            end
            if dx * dx + dy * dy + edge < 1 then
              local n = love.math.noise(x * 0.02, y * 0.02, noiseSeed)
              world:setRaw(x, y, (y < cy + 5 or n > 0.62) and DIRTID or ROCKID)
            end
          end
          tick()
        end
      end
    end
    -- Spires from the floor
    for _ = 1, scaled(14) do
      local x = X0 + BORDER + 80 + rng:random() * (W - 2 * (BORDER + 80))
      local h = 160 + rng:random() * 360
      local w = 22 + rng:random() * 34
      if clear(x - w, x + w) then
        for y = math.floor(floorTop - h), floorTop + 4 do
          local t = (y - (floorTop - h)) / h
          local hw = w * (0.35 + 0.65 * t) / 2
          for xx = math.floor(x - hw), math.ceil(x + hw) do
            world:setRaw(xx, y, ROCKID)
          end
        end
      end
      tick()
    end
  end

  -- The hole through the sky's floor where the shaft from the mountain arrives
  local function carveSkyEntrance(x0, x1)
    world:fillRect(x0, Y1 - 205, x1, Y1, AIR)
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
    local w, h = 700, 86 -- (the DPS dummy's range at the left end, then the goods)
    local x0, y0 = math.floor(cx - w / 2), floorY - h
    local x1, y1 = x0 + w - 1, floorY - 1
    world:fillRect(x0 - 8, y0 - 8, x1 + 8, y1 + 8, BRICK)
    world:fillRect(x0, y0, x1, y1, AIR)
    -- Opening in the ceiling, with a short drop shaft up to where the tunnels
    -- end: it flares wider toward the top, like a funnel, so the way in is not
    -- a slot with square edges, and the flat brick roof is heaped over with
    -- rubble that fades out away from the opening
    local fcx = math.floor(cx)
    for dy = 0, 53 do
      local half = 21 + math.floor((dy / 53) ^ 1.6 * 16 + love.math.noise(dy * 0.2, noiseSeed + 55) * 3)
      world:fillRect(fcx - half, y0 - 1 - dy, fcx + half, y0 - 1 - dy, AIR)
    end
    for x = x0 - 8, x1 + 8 do
      local d = math.abs(x - fcx)
      if d > 24 then
        local near = math.max(0, 1 - (d - 24) / 90)
        local ends = math.max(0, 1 - math.min(x - (x0 - 8), (x1 + 8) - x) / 60)
        local hgt = math.floor((near * 7 + ends * 6) * (0.6 + love.math.noise(x * 0.07, noiseSeed + 56) * 0.8))
        for k = 1, hgt do
          if not world:isSolid(x, y0 - 8 - k) then
            world:setRaw(x, y0 - 8 - k, ROCKID)
          end
        end
      end
    end
    local room = { x = x0, y = y0, w = w, h = h, cx = math.floor(cx) }
    if area.hasNext then
      local hx = x0 + w - 28
      world:fillRect(hx - 19, floorY, hx + 19, floorY + 3, IRON)
      room.hatch = { x0 = hx - 19, x1 = hx + 19, y0 = floorY, y1 = floorY + 3, cx = hx, floorY = floorY, ceilY = y0 }
    end
    if arena or (area.level or 0) >= 4 then
      -- After a boss (and at the foot of every area from the fourth tier down): a small brick room under the shop's floor, between the
      -- merchant and the hatch, reached down a narrow shaft (shallow enough
      -- to jump back out of, with nothing in the way). A teleport pad stands in it that takes
      -- the hunter home to camp, at a price (src.shop).
      local rx = x0 + 600
      world:fillRect(rx - 46, floorY, rx + 46, floorY + 46, BRICK)
      world:fillRect(rx - 42, floorY + 6, rx + 42, floorY + 40, AIR)
      world:fillRect(rx - 8, floorY, rx + 8, floorY + 5, AIR)
      room.back = { cx = rx, floorY = floorY + 41, x0 = rx - 42, x1 = rx + 42, y0 = floorY + 6 }
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
      if head % 256 == 0 then
        tick() -- (2000 steps of this search ran 4-5 ms past the frame's budget)
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
        if isOpen and supported and ground < Y1 - BORDER and inProfile(x, ground - 10, 30) and not avoid(x, ground) then
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
        if ok and inProfile(x, ceiling + 10, 30) and not avoid(x, ceiling) then
          spots[#spots + 1] = { x, ceiling }
        end
      end
    end
    return spots
  end

  -- Veins of gold ore: wandering blobs in solid rock and dirt, some right
  -- at a cave wall (glinting where they can be seen) and some buried deep
  local diamonds = {} -- where the diamond deposits are (they sparkle: see src.scenes.catacombs)
  local function placeOre()
    -- Each deposit has a shape of its own: a round blob, a tilted ellipse, a
    -- diamond, a long streak or a lumpy knob
    local function vein(ore, r)
      local x = X0 + BORDER + 20 + rng:random() * (W - 2 * BORDER - 40)
      local y = Y0 + 140 + rng:random() * (H - 300)
      local shape = rng:random(1, 5)
      local ang = rng:random() * math.pi
      local ca, sa = math.cos(ang), math.sin(ang)
      local squash = 0.4 + rng:random() * 0.3
      local lumps = { rng:random() * 6.28, rng:random() * 6.28, rng:random() * 6.28 }
      local reach = shape == 4 and r * 1.5 or r
      for oy = -math.ceil(reach), math.ceil(reach) do
        for ox = -math.ceil(reach), math.ceil(reach) do
          local px, py = math.floor(x + ox), math.floor(y + oy)
          local id = world:get(px, py)
          if id == ROCKID or id == DIRTID then
            local u, v = ox * ca + oy * sa, -ox * sa + oy * ca
            local inside
            if shape == 1 then
              inside = ox * ox + oy * oy <= r * r
            elseif shape == 2 then
              inside = (u / (r * 1.25)) ^ 2 + (v / (r * squash * 1.4)) ^ 2 <= 1
            elseif shape == 3 then
              inside = math.abs(u) + math.abs(v) <= r * 1.1
            elseif shape == 4 then
              inside = (u / (r * 1.5)) ^ 2 + (v / (r * 0.3)) ^ 2 <= 1
            else
              local a = math.atan2(oy, ox)
              local rr = r * (0.75 + 0.22 * math.sin(a * 3 + lumps[1]) + 0.15 * math.sin(a * 5 + lumps[2]))
              inside = ox * ox + oy * oy <= rr * rr
            end
            if inside then
              world:setRaw(px, py, ore)
            end
          end
        end
      end
      return x, y, r
    end
    for _ = 1, scaled(150) do
      tick()
      vein(GOLDORE, 4 + rng:random() * 5)
    end
    -- Now and then a big seam of gold...
    for _ = 1, scaled(14) do
      tick()
      vein(GOLDORE, 7 + rng:random() * 5)
    end
    -- ...and, rarer and smaller, diamond: ten times the money a speck
    for _ = 1, scaled(18) do
      tick()
      local dx, dy, dr = vein(materials.DIAMONDORE, 2.5 + rng:random() * 2.5)
      diamonds[#diamonds + 1] = { dx, dy, dr }
    end
  end

  fillBase()
  carveCaves()
  placeOre()
  carveCaverns()
  if open then
    carveIslands()
  end

  local entranceX, entranceY = area.entranceX, area.entranceY
  -- One wide main route and narrower side routes; they wander independently,
  -- so they cross each other on the way down (or, in a climbing area, up)
  local routeEnds = {}
  if climb then
    for p = 1, PATHS do
      local gx, gy = arena.cx + (p - 2.5) * 220, arena.floorY
      if arena.shape == "round" then
        -- Up into the oval at its lower left and right corners, never through its floor
        local rx, ry = arena.w / 2, arena.h / 2
        local nx = 0.66 + 0.06 * math.floor((p - 1) / 2)
        gx = arena.cx + (p % 2 == 1 and -1 or 1) * nx * rx
        gy = arena.top + ry + math.sqrt(1 - nx * nx) * ry
      end
      routeEnds[#routeEnds + 1] = { gx, gy }
      carveRouteUp(entranceX, entranceY, gx, gy + 40, p == 1 and 21 or 17, noiseSeed + p * 13)
    end
  elseif not open then
    for p = 1, PATHS do
      if arena then
        carveRoute(entranceX, entranceY, arena.cx + (p - 2.5) * 300, arena.top + 24, p == 1 and 21 or 17, noiseSeed + p * 13)
      else
        carveRoute(entranceX, entranceY, shopX, tunnelEndY, p == 1 and 21 or 17, noiseSeed + p * 13)
      end
    end
  end
  carveCrossings()
  if arena then
    carveArena()
  elseif not open then
    carveAntechamber()
  end
  local exit
  if climb then
    -- The routes come up into the arena through its floor
    for i, e in ipairs(routeEnds) do
      local seed = noiseSeed + 200 + i
      carveSegment(e[1], e[2] + 40, e[1], e[2] - 14, 17, seed)
      addLadder(e[1], e[2] + 40, e[2] - 12, seed)
    end
    -- A cap of bedrock across the summit, and the exit shaft up through it and
    -- the rock over the arena, shut by a gate until the boss is dead
    for y = Y0, Y0 + 29 do
      local xa, xb = profile(y)
      if xa then
        world:fillRect(xa, y, xb, y, BEDROCK)
      end
    end
    exit = { cx = math.floor(arena.cx), x0 = math.floor(arena.cx) - 21, x1 = math.floor(arena.cx) + 21 }
    world:fillRect(exit.x0, Y0, exit.x1, arena.top - 10, AIR)
    local gate = { x0 = exit.x0 - 1, x1 = exit.x1 + 1, y0 = arena.top - 9, y1 = arena.top - 6 }
    world:fillRect(gate.x0, gate.y0, gate.x1, gate.y1, IRON)
    arena.gates[#arena.gates + 1] = gate
    addLadder(exit.cx, arena.top - 12, Y0, noiseSeed + 300)
    entranceY = carveWalkIn(entranceX, entranceY)
  elseif open then
    if area.shaftX0 then
      carveSkyEntrance(area.shaftX0, area.shaftX1)
      addLadder((area.shaftX0 + area.shaftX1) / 2, Y1 + 2, Y1 - 205, noiseSeed + 301)
    end
  else
    carveEntrance(entranceX, entranceY)
  end
  local shops = {}
  for _, sx in ipairs(shopXs) do
    shops[#shops + 1] = buildShop(sx, shopFloor)
  end
  local shop = shops[1]
  if arena then
    -- A shaft from the arena floor down into each shop's ceiling, shut by an
    -- iron gate until the boss is dead (and rubble-filled later if the other
    -- shop is chosen, see src.scenes.catacombs)
    for _, room in ipairs(shops) do
      local x0, x1 = room.cx - 21, room.cx + 21
      world:fillRect(x0, arena.floorY - 40, x1, room.y - 55, AIR) -- (up through the curve of the arena floor)
      local gate = { x0 = x0 - 1, x1 = x1 + 1, y0 = arena.floorY + 4, y1 = arena.floorY + 7 }
      world:fillRect(gate.x0, gate.y0, gate.x1, gate.y1, IRON)
      arena.gates[#arena.gates + 1] = gate
      room.shaft = { x0 = x0, x1 = x1, y0 = arena.floorY + 10, y1 = room.y - 56 }
    end
  end

  -- Bedrock shell at the sides, and at the bottom of the last area (the
  -- surface's rock, or the previous area, is above)
  if not area.hasNext and not open then -- (the sky has no indestructible floor: its cloud can be dug through)
    world:fillRect(X0, Y1 - BORDER + 1, X1, Y1, BEDROCK)
  end
  -- (an inner side, facing the other path, is plain rock instead, with more
  -- rock out to the neighbour so the hunter can dig across)
  local sideTop = climb and (area.groundY or Y0) or Y0 - BLEND
  if open then
    sideTop = world.top -- (the sky's walls go up to the world's invisible ceiling)
  end
  world:fillRect(X0, sideTop, X0 + BORDER - 1, Y1, (area.gapLeft or open) and ROCKID or BEDROCK) -- (the sky's walls are cloud: nothing there is indestructible)
  world:fillRect(X1 - BORDER + 1, sideTop, X1, Y1, (area.gapRight or open) and ROCKID or BEDROCK)
  if area.gapLeft then
    world:fillRect(X0 - area.gapLeft, sideTop, X0 - 1, Y1, ROCKID)
  end
  if area.gapRight then
    world:fillRect(X1 + 1, sideTop, X1 + area.gapRight, Y1, ROCKID)
  end
  if open then
    -- (no roof: the world's top edge above is an invisible ceiling, out of view)
    if area.shaftX0 then
      carveSkyEntrance(area.shaftX0, area.shaftX1) -- (the bottom shell must not close the hole)
    end
  end

  -- Spawn spot (used when starting in the cave): the entrance's left ledge
  local spawnX = math.floor(entranceX - ENTRANCE_GAP - 22)
  if open then
    spawnX = math.floor(entranceX - 70)
  end
  local spawnY = world:findGroundUnder(spawnX, PLAYER_W, entranceY) - PLAYER_H

  -- What the hunter must be able to reach: the shop, or the arena's floor
  local goal = shop
  local goalX, goalY = shopX, tunnelEndY
  if arena then
    goal = { x = arena.cx - 150, y = arena.floorY - 80, w = 300, h = 78 }
    goalX, goalY = arena.cx, arena.top + 24
  end
  if not isReachable(spawnX, spawnY, goal) then
    local len = math.sqrt((goalX - entranceX) ^ 2 + (goalY - entranceY) ^ 2)
    for d = 0, len, 3 do
      local t = d / len
      carveCircle(entranceX + (goalX - entranceX) * t, entranceY + (goalY - entranceY) * t, 19)
    end
    print("cavegen: no route found, carved an emergency tunnel (seed " .. seed .. ")")
  end

  local function avoid(x, y)
    local nearSpawn = math.abs(x - entranceX) < 80 and y < entranceY + 64
    local inShop = false
    for _, room in ipairs(shops) do
      inShop = inShop or (x > room.x - 16 and x < room.x + room.w + 16 and y > room.y - 16)
    end
    return nearSpawn or inShop or inArena(x, y, 20)
  end
  -- A boss's arena is walled in with sealed rock (it breaks again once the boss
  -- is dead), so nobody can tunnel round the fight
  if arena then
    local T = 28
    local sx0, sy0, sx1, sy1 = arena.x0 - T, arena.top - T, arena.x1 + T, arena.floorY + T
    local solidNow = materials.solid
    for y = math.max(sy0, Y0), math.min(sy1, Y1 - BORDER) do
      for x = math.max(sx0, X0), math.min(sx1, X1) do
        if not (x >= arena.x0 and x <= arena.x1 and y >= arena.top and y <= arena.floorY) then
          local id = world:get(x, y)
          if solidNow[id] and (id == ROCKID or id == DIRTID or id == GOLDORE or id == materials.DIAMONDORE) then
            world:setRaw(x, y, materials.SEALED)
          end
        end
      end
      if y % 4 == 0 then
        tick()
      end
    end
    arena.seal = { x0 = sx0, y0 = sy0, x1 = sx1, y1 = sy1, rock = ROCKID }
  end
  world:repaintRect(X0 - (area.gapLeft or 0), math.min(Y0 - BLEND - 16, (area.shaftTop or math.huge) - 16), X1 + (area.gapRight or 0), Y1, tick)

  -- Monsters: none near the entrance or in the shop. More of them, and
  -- tougher, the deeper you go.
  local function avoidForEnemies(x, y)
    local nearEntrance = math.abs(x - entranceX) < 260 and y < entranceY + 220
    local inShop = false
    for _, room in ipairs(shops) do
      inShop = inShop or (x > room.x - 60 and x < room.x + room.w + 60 and y > room.y - 120)
    end
    return nearEntrance or inShop or inArena(x, y, 60)
  end
  local enemies = {}
  -- Room for a w x h monster standing on (floor) or hanging from (else) the spot
  local function fits(kind, x, y)
    local sz = SIZES[kind]
    local w, h = sz[1], sz[2]
    local top = sz[3] and y - h or y
    -- (a few rows at the foot, or the ceiling, may touch sloped rock)
    local from, to = sz[3] and top or top + 2, sz[3] and top + h - 5 or top + h - 1
    for yy = from, to do
      for xx = math.floor(x - w / 2), math.floor(x - w / 2) + w - 1 do
        if world:isSolid(xx, yy) then
          return false
        end
      end
    end
    return true
  end
  -- Tougher the deeper in an area, and a lot tougher with each area
  local function toughnessAt(y)
    local depth = climb and (Y1 - y) / H or (y - Y0) / H -- (a climb gets tougher going up)
    return (1 + depth * 0.6 + (level - 1) * 0.9) * (area.toughMul or 1)
  end
  local function place(kind, spots)
    for _, s in ipairs(spots) do
      local depth = (s[2] - Y0) / H
      local crowded = false
      for _, m in ipairs(enemies) do
        if math.abs(m.x - s[1]) < 48 and math.abs(m.y - s[2]) < 48 then
          crowded = true -- keep them spread out instead of in clumps
        end
      end
      if not crowded and rng:random() < 0.35 + 0.65 * depth and fits(kind, s[1], s[2]) then
        enemies[#enemies + 1] = { kind = kind, x = s[1], y = s[2], toughness = toughnessAt(s[2]) }
      end
    end
  end
  local counts = area.monsters or { ghoul = 60, bat = 40, spitter = 26 }
  if area.spawnMul then
    -- (a deadly area: many more of them)
    local more = {}
    for k, v in pairs(counts) do
      more[k] = math.floor(v * area.spawnMul + 0.5)
    end
    counts = more
  end
  if counts.ghoul then
    place("ghoul", findFloorSpots(scaled(counts.ghoul), 20, avoidForEnemies))
  end
  if counts.hopper then
    place("hopper", findFloorSpots(scaled(counts.hopper), 14, avoidForEnemies))
  end
  if counts.bat then
    place("bat", findCeilingSpots(scaled(counts.bat), 24, avoidForEnemies))
  end
  if counts.spitter then
    place("spitter", findCeilingSpots(scaled(counts.spitter), 30, avoidForEnemies))
  end
  if counts.bloater then
    place("bloater", findCeilingSpots(scaled(counts.bloater), 34, avoidForEnemies))
  end
  if counts.wisp then
    place("wisp", findCeilingSpots(scaled(counts.wisp), 26, avoidForEnemies))
  end
  if counts.miner then
    place("miner", findFloorSpots(scaled(counts.miner), 22, avoidForEnemies))
  end
  if counts.roller then
    place("roller", findFloorSpots(scaled(counts.roller), 14, avoidForEnemies))
  end
  -- (the Needle's own: crows and gargoyles hang from the ceiling, devils float in the open, rams stand)
  if counts.crow then
    place("crow", findCeilingSpots(scaled(counts.crow), 24, avoidForEnemies))
  end
  if counts.gargoyle then
    place("gargoyle", findCeilingSpots(scaled(counts.gargoyle), 30, avoidForEnemies))
  end
  if counts.dustdevil then
    place("dustdevil", findCeilingSpots(scaled(counts.dustdevil), 30, avoidForEnemies))
  end
  if counts.cragram then
    place("cragram", findFloorSpots(scaled(counts.cragram), 24, avoidForEnemies))
  end
  if counts.worm then
    -- Worms lie coiled in solid rock: spots with nothing but rock all round
    local anchored = materials.anchored
    local wanted, found = scaled(counts.worm), 0
    for _ = 1, wanted * 60 do
      if found >= wanted then
        break
      end
      tick()
      local x = math.floor(X0 + BORDER + 30 + rng:random() * (W - 2 * BORDER - 60))
      local y = math.floor(Y0 + 140 + rng:random() * (H - 360))
      local buried = not avoidForEnemies(x, y)
      for oy = -9, 9, 3 do
        for ox = -9, 9, 3 do
          local id = world:get(x + ox, y + oy)
          if not world:isSolid(x + ox, y + oy) or anchored[id] then
            buried = false
          end
        end
      end
      for _, m in ipairs(enemies) do
        if math.abs(m.x - x) < 48 and math.abs(m.y - y) < 48 then
          buried = false
        end
      end
      if buried and rng:random() < 0.35 + 0.65 * ((y - Y0) / H) then
        found = found + 1
        enemies[#enemies + 1] = { kind = "worm", x = x, y = y, toughness = toughnessAt(y) }
      end
    end
  end

  -- Swarms: colonies that hang together under a ceiling and wake as one
  local SWARM_SIZE = { swarmbat = { 8, 12 }, wisp = { 4, 6 } }
  local swarmId = 0
  for kind, count in pairs(area.swarms or {}) do
    for _, s in ipairs(findCeilingSpots(scaled(count), 40, avoidForEnemies)) do
      swarmId = swarmId + 1
      local range = SWARM_SIZE[kind]
      local n = rng:random(range[1], range[2])
      for _ = 1, n * 3 do
        if n <= 0 then
          break
        end
        local mx, my = s[1] + (rng:random() - 0.5) * 56, s[2] + rng:random() * 28
        if fits(kind, mx, my) then
          n = n - 1
          enemies[#enemies + 1] = { kind = kind, x = mx, y = my, toughness = toughnessAt(s[2]), swarm = swarmId }
        end
      end
      tick()
    end
  end

  -- The area's one boss, somewhere in the lower two thirds of the cave on a
  -- cavern floor with room for it (floaters hover a little above the floor)
  local bossKind = type(area.boss) == "table" and area.boss[rng:random(1, #area.boss)] or area.boss
  if bossKind and arena then
    local sz = SIZES[bossKind]
    enemies[#enemies + 1] = { kind = bossKind, x = arena.cx, y = arena.top + 120, toughness = 1 + (level - 1) * 0.5, boss = true, arena = true, reward = area.bossReward }
  elseif bossKind then
    local sz = SIZES[bossKind]
    local best
    local spots
    if sz[4] then
      spots = findCeilingSpots(80, sz[2] + 20, avoidForEnemies) -- hangs under a ceiling
    else
      spots = findFloorSpots(60, sz[2] + 12, avoidForEnemies)
    end
    for _, s in ipairs(spots) do
      local y = (sz[3] or sz[4]) and s[2] or s[2] - sz[2] - 14
      if not best and s[2] > Y0 + H * 0.35 and s[2] < Y1 - H * 0.2 and fits(bossKind, s[1], y) then
        best = { kind = bossKind, x = s[1], y = y, toughness = 1 + (level - 1) * 0.5, boss = true }
      end
    end
    if best then
      enemies[#enemies + 1] = best
    end
  end

  -- Pools of poison gas and of water, settled in low spots: each is
  -- flood-filled over a grid from a floor spot up to a level a little above
  -- it. A fill that runs away (pouring down a shaft) or spreads too wide is
  -- dropped, so pools only form in real basins. Kept away from the entrance
  -- and the shop.
  local taken = {}
  local function makePools(wanted, minDepth, maxDepth, vents)
    local pools = {}
    if (wanted or 0) <= 0 then
      return pools
    end
    local C = POOL_CELL
    local function open(gx, gy)
      local x, y = gx * C + C / 2, gy * C + C / 2
      return x > X0 + BORDER and x < X1 - BORDER and y > Y0 + 60 and y < Y1 - BORDER and not world:isSolid(x, y)
    end
    local function avoidForPools(x, y)
      local nearEntrance = math.abs(x - entranceX) < 300 and y < entranceY + 260
      local nearShop = not arena and math.abs(x - funnel.x) < FUNNEL_NECK + 200 and y > antechamberY - 260
      return nearEntrance or nearShop or inArena(x, y, 60)
    end
    -- (most floor spots aren't basins, so plenty are tried)
    for _, s in ipairs(findFloorSpots(wanted * 14, 24, avoidForPools)) do
      if #pools >= wanted then
        break
      end
      local gx0, gy0 = math.floor(s[1] / C), math.floor((s[2] - 2) / C)
      local key0 = gy0 * 100000 + gx0
      if not taken[key0] and open(gx0, gy0) then
        local level = s[2] - minDepth - rng:random() * (maxDepth - minDepth)
        local seen, cells = { [key0] = true }, { gx0, gy0 }
        local head, ok = 1, true
        while head < #cells do
          local gx, gy = cells[head], cells[head + 1]
          head = head + 2
          if gy * C > s[2] + 90 or #cells > 4000 then
            ok = false -- runs away down a hole, or far too wide
            break
          end
          for i = 1, 4 do
            local nx = gx + (i == 1 and 1 or i == 2 and -1 or 0)
            local ny = gy + (i == 3 and 1 or i == 4 and -1 or 0)
            local k = ny * 100000 + nx
            if not seen[k] and not taken[k] and ny * C + C / 2 >= level and open(nx, ny) then
              seen[k] = true
              cells[#cells + 1] = nx
              cells[#cells + 1] = ny
            end
          end
        end
        if ok and #cells >= 40 then
          local pool = { cells = {}, vent = vents and { s[1], s[2] } or nil, level = level }
          for i = 1, #cells, 2 do
            local gx, gy = cells[i], cells[i + 1]
            taken[gy * 100000 + gx] = true
            pool.cells[#pool.cells + 1] = gx * C
            pool.cells[#pool.cells + 1] = gy * C
          end
          pools[#pools + 1] = pool
        end
      end
      tick()
    end
    return pools
  end
  local gas = makePools(area.gasPools, 22, 52, true)
  local water = makePools(area.waterPools, 20, 64, false) -- (deeper than before, and more of them)
  local lava = makePools(area.lavaPools, 14, 36, false) -- (shallow basins of molten rock)
  local acid = makePools(area.acidPools, 10, 28, false)
  -- A flooded area: every open cell below the flood level is water (src.fluids
  -- fills it in). Runs of 2-px cells, { gy, gx0, gx1 }, from the level down
  local flood
  if area.flood then
    local top = Y0 + (area.flood.level or 120)
    local lake = area.flood.lake -- { x0, x1 }: a lake over the area's top, flooding that width from above Y0
    local runs = {}
    local gx0, gx1 = math.ceil((X0 + BORDER) / 2), math.floor((X1 - BORDER) / 2)
    for gy = math.floor((lake and (Y0 - 28) or top) / 2), math.floor((Y1 - BORDER) / 2) do
      local y = gy * 2 + 1
      local start
      local gxA, gxB = gx0, gx1
      if lake and y < top then
        gxA, gxB = math.max(gx0, math.ceil(lake.x0 / 2)), math.min(gx1, math.floor(lake.x1 / 2))
      end
      for gx = gxA, gxB do
        local open = not world:isSolid(gx * 2 + 1, y)
        if open and not start then
          start = gx
        elseif not open and start then
          runs[#runs + 1] = { gy, start, gx - 1 }
          start = nil
        end
      end
      if start then
        runs[#runs + 1] = { gy, start, gxB }
      end
      tick()
    end
    flood = { top = top, runs = runs }
  end
  -- Grass along the earth and the mossy clays (the first areas only), stamped into the terrain now so it costs nothing in play
  if area.grass then
    require("src.grass").bake(world, X0 + BORDER, Y0 + 40, X1 - BORDER, Y1 - BORDER, { water, lava, acid }, POOL_CELL, flood, tick)
  end
  local result = {
    diamonds = diamonds,
    seed = seed,
    area = area,
    spawnX = spawnX,
    spawnY = spawnY,
    shop = shop,
    shops = shops, -- one, or two (left, right) in a boss area
    arena = arena, -- { x0, x1, top, floorY, cx, braziers = { {x, y} }, gates = { {x0, y0, x1, y1} } }
    crates = findFloorSpots(scaled(40), 16, avoid),
    ironCrates = findFloorSpots(scaled(12), 19, avoid),
    chests = findFloorSpots(scaled(12), 22, avoidForEnemies), -- weapon chests, away from the entrance and shop
    glows = findFloorSpots(scaled(area.glowCount or 150), 6, avoid), -- glowing fungus clusters
    level = level,
    enemies = enemies, -- { kind, x, y, toughness, boss }: ground monsters stand at y, the others hang from it
    gas = gas, -- pools: { cells = { x, y, ... } (POOL_CELL squares), vent = { x, groundY }, level }
    water = water, -- the same, without vents
    flood = flood, -- { top, runs }: the area's flooded part (runs of 2-px cells { gy, gx0, gx1 })
    platforms = ladders, -- one-way platforms to climb by: { x0, x1, y }
    exit = exit, -- a climbing area's way on: { cx, x0, x1 } (the shaft up from its arena)
    story = require("src.story").generate(world, findFloorSpots(scaled(16), 22, avoidForEnemies), level, rng, area.name), -- (src.story: signs, camps, the fallen)
    lava = lava, -- pools of molten rock (src.fluids): they don't flow
    acid = acid, -- pools of acid: they don't flow either
    gasCell = POOL_CELL,
  }

  -- Small breakables (urns, pouches, lamps) from the area's list { name, count per
  -- reference area }, placed last so the rest of the layout is unchanged
  result.breakables = {} -- { { name, spots = { {x, groundY} } } }
  for _, b in ipairs(area.breakables or {}) do
    result.breakables[#result.breakables + 1] = { name = b[1], spots = findFloorSpots(scaled(b[2]), 16, avoid) }
  end

  -- Stalactites: tapering cones of the area's rock hanging from the cave
  -- ceilings (real terrain, so they can be shot down). Each is given room below
  -- it, so none of them blocks a passage.
  for _, s in ipairs(findCeilingSpots(scaled(area.stalactites or 0), 44, avoidForEnemies)) do
    tick()
    local x, cy = s[1], s[2]
    local len = rng:random(6, 24)
    local base = rng:random(2, 4)
    local clear = true
    for _, m in ipairs(enemies) do
      if math.abs(m.x - x) < base + 14 and m.y > cy - 14 and m.y < cy + len + 10 then
        clear = false
      end
    end
    for _, o in ipairs(result.stalactites or {}) do
      if math.abs(o[1] - x) < 9 and math.abs(o[2] - cy) < 6 then
        clear = false
      end
    end
    if clear then
      result.stalactites = result.stalactites or {}
      result.stalactites[#result.stalactites + 1] = { x, cy }
      for dy = 0, len do
        local half = math.floor(base * (1 - dy / len) + 0.5)
        for dx = -half, half do
          if not world:isSolid(x + dx, cy + dy) then
            world:setRaw(x + dx, cy + dy, ROCKID)
          end
        end
      end
      world:repaintRegion(x - base - 2, cy - 2, x + base + 2, cy + len + 2)
    end
  end

  -- The old mine's furnishings (area.mine): rail tracks with ore carts, timber
  -- shoring (standing, half fallen and collapsed), oil lamps, skeletal remains
  -- and pickaxes. All but the carts are scenery (see src.minedecor).
  if area.mine then
    local mine = { tracks = {}, carts = {}, supports = {}, skeletons = {}, picks = {}, lamps = {} }
    result.mine = mine
    local function solidAt(x, y)
      return world:isSolid(x, y)
    end
    -- The ground surface at x within a few pixels of y (air above, rock at it)
    local function groundNear(x, y)
      for yy = y - 4, y + 4 do
        if not solidAt(x, yy - 1) and solidAt(x, yy) then
          return yy
        end
      end
    end
    local function clearAbove(x, y, h)
      for yy = y - h, y - 1 do
        if solidAt(x, yy) then
          return false
        end
      end
      return true
    end

    -- Rail tracks: laid along level stretches of floor, with a cart on some
    for _, s in ipairs(findFloorSpots(scaled(40), 14, avoid)) do
      tick()
      local ys = { [s[1]] = s[2] }
      local x0, x1 = s[1], s[1]
      for dir = -1, 1, 2 do
        local x, y = s[1], s[2]
        for _ = 1, rng:random(28, 95) do
          local ny = groundNear(x + dir, y)
          if not ny or not clearAbove(x + dir, ny, 12) then
            break
          end
          x, y = x + dir, ny
          ys[x] = ny
        end
        if dir < 0 then
          x0 = x
        else
          x1 = x
        end
      end
      local overlaps = false
      for _, t in ipairs(mine.tracks) do
        if x0 < t.x1 + 10 and x1 > t.x0 - 10 and math.abs(ys[s[1]] - (t.ys[t.x0] or ys[s[1]])) < 80 then
          overlaps = true
        end
      end
      if x1 - x0 >= 40 and not overlaps then
        mine.tracks[#mine.tracks + 1] = { x0 = x0, x1 = x1, ys = ys }
        if rng:random() < 0.6 then
          local cx = rng:random(x0 + 12, x1 - 12)
          mine.carts[#mine.carts + 1] = { x = cx, y = ys[cx] }
        end
      end
    end

    -- Timber shoring: two posts and a cap beam between floor and ceiling
    local function ceilAt(cx, from)
      for yy = from, from - 130, -1 do
        if solidAt(cx, yy) then
          return yy
        end
      end
    end
    for _, s in ipairs(findFloorSpots(scaled(240), 8, avoid)) do
      tick()
      local x, gy = s[1], s[2]
      local gap = rng:random(11, 19)
      local c1, c2 = ceilAt(x, gy - 6), ceilAt(x + gap, gy - 6)
      local g2 = groundNear(x + gap, gy)
      if c1 and c2 and g2 and math.abs(c1 - c2) <= 3 and gy - c1 >= 26 and gy - c1 <= 120 and math.abs(g2 - gy) <= 5 then
        local open = true
        for yy = c1 + 1, gy - 1 do
          if solidAt(x + math.floor(gap / 2), yy) then
            open = false
          end
        end
        local roll = rng:random()
        if open then
          mine.supports[#mine.supports + 1] = {
            x = x,
            gap = gap,
            g1 = gy,
            g2 = g2,
            c = math.floor((c1 + c2) / 2),
            state = roll < 0.5 and "standing" or (roll < 0.8 and "broken" or "fallen"),
            side = rng:random(1, 2),
            breakH = rng:random(8, math.max(9, gy - c1 - 10)),
            lantern = rng:random() < 0.5,
            seed = rng:random(1, 1000),
          }
        end
      end
    end
    for _, sp in ipairs(mine.supports) do
      if sp.lantern and sp.state ~= "fallen" then
        mine.lamps[#mine.lamps + 1] = { x = sp.x + sp.gap / 2, y = sp.c + 11, hung = true }
      end
    end

    -- Oil lamps on posts, skeletons, pickaxes
    for _, s in ipairs(findFloorSpots(scaled(22), 24, avoid)) do
      mine.lamps[#mine.lamps + 1] = { x = s[1], y = s[2] - 14, post = s[2], flip = rng:random() < 0.5 }
    end
    for _, s in ipairs(findFloorSpots(scaled(34), 8, avoid)) do
      mine.skeletons[#mine.skeletons + 1] = { x = s[1], y = s[2], kind = rng:random(1, 4), flip = rng:random() < 0.5, pick = rng:random() < 0.4 }
    end
    for _, s in ipairs(findFloorSpots(scaled(28), 12, avoid)) do
      mine.picks[#mine.picks + 1] = { x = s[1], y = s[2], flip = rng:random() < 0.5, tilt = rng:random(-4, 4) / 10 }
    end
  end

  -- A prisoner's cage (src.npcs): on the flattest, roomiest stretch of floor
  -- found, near the middle of the area's depth, which is then levelled and
  -- cleared so the cage always fits. Placed last, so the rest of the layout
  -- doesn't change.
  if area.prisoner and area.prisonerHeld == "float" and flood then
    -- Someone floating on the water's surface: open air over the waterline
    local wy = flood.top
    local spots = {}
    for x = X0 + BORDER + 100, X1 - BORDER - 100, 8 do
      local clear = true
      for dx = -16, 16, 4 do
        for dy = -34, 2, 4 do
          if world:isSolid(x + dx, wy + dy) then
            clear = false
          end
        end
      end
      if clear then
        spots[#spots + 1] = x
      end
    end
    if #spots > 0 then
      local x = spots[rng:random(1, #spots)]
      result.prisoner = { id = area.prisoner, x = x, y = wy, held = "float" }
    end
  elseif area.prisoner then
    local best, bestScore
    for _, s in ipairs(findFloorSpots(40, 30, avoidForEnemies)) do
      local x, g = s[1], s[2]
      local bumps, blocked = 0, 0
      for dx = -20, 18, 2 do
        local gy = world:findGround(x + dx, g - 30)
        bumps = bumps + math.min(4, math.floor(math.abs(gy - g) / 2))
      end
      for dy = 4, 34, 3 do
        for dx = -14, 13, 3 do
          if world:isSolid(x + dx, g - dy) then
            blocked = blocked + 1
          end
        end
      end
      local score = bumps + blocked * 2 + math.abs((g - Y0) / (Y1 - Y0) - 0.45) * 20
      if not bestScore or score < bestScore then
        best, bestScore = s, score
      end
    end
    if best then
      local x, g = best[1], best[2]
      for px = x - 20, x + 18 do
        for py = g - 34, g - 1 do
          if world:isSolid(px, py) then
            world:setRaw(px, py, materials.AIR)
          end
        end
        for py = g, g + 3 do
          world:setRaw(px, py, materials.BRICK) -- (indestructible: the cage's floor)
        end
      end
      local top
      if area.prisonerHeld == "rubble" then
        -- A cave-in: a mound of loose earth with lumps of rock in it, heaped
        -- over him (src.npcs digs out whether he is free yet)
        local dirt = area.palette and area.palette.dirt or materials.DIRT
        for dx = -18, 18 do
          local k = 1 - (dx / 19) ^ 2
          local h = math.floor(21 * k ^ 0.7 + rng:random(0, 1))
          for dy = 1, h do
            local rocky = rng:random() < 0.12
            world:setRaw(x + dx, g - dy, rocky and ROCKID or dirt)
          end
        end
        top = g - 21
      end
      world:repaintRegion(x - 22, g - 36, x + 20, g + 5)
      result.prisoner = { id = area.prisoner, x = x, y = g, held = area.prisonerHeld, top = top }
    end
  end

  -- Events for the dungeon (src.events): altars, spots for a quest relic, a
  -- wounded hunter, and a sealed vault. Placed last, so the layout above is
  -- unchanged.
  if area.monsters and next(area.monsters) and not area.open and not area.arena then
    result.altars = findFloorSpots(level >= 3 and 2 or 1, 26, avoidForEnemies)
    result.relicSpots = findFloorSpots(3, 20, avoidForEnemies)
    if area.wounded then
      result.wounded = findFloorSpots(1, 26, avoidForEnemies)[1]
    end
    -- A vault: a stone-brick room sealed in solid rock, a short corridor
    -- running out to the nearest cave with an iron door at its inner end. The
    -- door takes a key; the brick around it can be dug or blasted through.
    local STONEBRICK, IRON = materials.STONEBRICK, materials.IRON
    for _ = 1, 160 do
      tick()
      local cx = math.floor(X0 + BORDER + 50 + rng:random() * (W - 2 * BORDER - 100))
      local cy = math.floor(Y0 + 150 + rng:random() * (H - 450))
      local solid = true
      for yy = cy - 24, cy + 13, 3 do
        for xx = cx - 20, cx + 20, 3 do
          if not world:isSolid(xx, yy) or not inProfile(xx, yy, 6) or avoidForEnemies(xx, yy) then
            solid = false
          end
        end
      end
      if solid then
        -- Which way is the nearest cave: left, right (level with the floor) or up
        local best, bestD, dir
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, -1 } }) do
          for dist = 17, 80, 2 do
            local ax, ay = cx + d[1] * dist, cy + (d[2] == 0 and 2 or d[2] * (dist - 4))
            if not world:isSolid(ax, ay) then
              if not bestD or dist < bestD then
                best, bestD, dir = d, dist, d
              end
              break
            end
          end
        end
        if best and bestD <= 80 then
          -- (a shell of iron round the room: nothing can dig or blast into it)
          -- (the room is roomy enough to walk about in: 29 wide, 25 tall)
          for yy = cy - 21, cy + 9 do
            for xx = cx - 17, cx + 17 do
              world:setRaw(xx, yy, IRON)
            end
          end
          for yy = cy - 18, cy + 6 do
            for xx = cx - 14, cx + 14 do
              world:setRaw(xx, yy, materials.AIR)
            end
          end
          local door
          if dir[2] == 0 then
            -- a side corridor, level with the floor, out to the cave
            local sx = dir[1]
            for dist = 15, 90 do
              local xx = cx + sx * dist
              if dist > 17 and not world:isSolid(xx, cy + 2) then
                break
              end
              for yy = cy - 14, cy + 6 do
                world:setRaw(xx, yy, materials.AIR)
              end
              for yy = cy - 14, cy + 6 do
                world:setRaw(cx + sx * 15, yy, IRON)
                world:setRaw(cx + sx * 16, yy, IRON)
              end
            end
            local dx0 = math.min(cx + sx * 15, cx + sx * 16)
            door = { x0 = dx0, y0 = cy - 14, x1 = dx0 + 1, y1 = cy + 6 }
          else
            for dist = 19, 90 do
              local yy = cy - dist
              if dist > 22 and not world:isSolid(cx, yy) then
                break
              end
              for xx = cx - 7, cx + 7 do
                world:setRaw(xx, yy, materials.AIR)
              end
            end
            for xx = cx - 7, cx + 7 do
              world:setRaw(xx, cy - 19, IRON)
              world:setRaw(xx, cy - 20, IRON)
            end
            door = { x0 = cx - 7, y0 = cy - 20, x1 = cx + 7, y1 = cy - 19 }
          end
          world:repaintRegion(cx - 20, cy - 100, cx + 20 + 80, cy + 14)
          world:repaintRegion(cx - 100, cy - 100, cx + 20, cy + 14)
          result.vault = { x = cx, y = cy + 6, door = door, dir = dir, room = { x0 = cx - 14, y0 = cy - 18, x1 = cx + 14, y1 = cy + 6 } }
          break
        end
      end
    end
  end

  return result
end

return cavegen
