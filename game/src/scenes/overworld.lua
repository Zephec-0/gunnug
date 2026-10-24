-- The whole world of a run, one seamless level with no loading screens.
-- On top, the Barrens: a hand-built desolate desert at dusk, the same every
-- run (design doc §7a). Left to right: badlands with a mesa and a natural
-- arch; the hunter's camp, where he starts (tent, campfire and a practice
-- dummy); a short walk over gently rolling ground past a signpost and the
-- bones of some great beast; the old mine, where a rail track runs down a
-- ramp into a dug-out pit under a tall headframe, and the shaft drops from the
-- pit floor; then a winch house, spoil heaps, crumbling ancient ruins and
-- another mesa out east. Below lie the generated areas
-- (scenes/catacombs.lua), built in the background while the hunter is on the
-- surface.
local catacombs = require("src.scenes.catacombs")
local chests = require("src.chests")
local config = require("src.config")
local enemies = require("src.enemies")
local fluids = require("src.fluids")
local materials = require("src.materials")
local parallax = require("src.parallax")
local depthblend = require("src.depthblend")
local props = require("src.props")
local render = require("src.render")
local weather = require("src.weather")
local shop = require("src.shop")
local npcs = require("src.npcs")
local town = require("src.town")
local targets = require("src.targets")
local barrens = require("src.barrens")
local World = require("src.world")

local SAND, SANDSTONE, WOOD, STONE, AIR, TAILINGS, ROCK, BEDROCK =
  materials.SAND, materials.SANDSTONE, materials.WOOD, materials.STONEBRICK, materials.AIR, materials.TAILINGS, materials.ROCK, materials.BEDROCK

local overworld = {
  title = "The Barrens",
  subtitle = "Find the old mine",
  ambient = { 0.88, 0.76, 0.74 }, -- updated every frame: blends to the cave's as the hunter descends
  fx = {}, -- the look of the post-process pass, blended the same way
}

local SURFACE_FX = { shadow = { 0.95, 0.96, 1.06 }, light = { 1.1, 1.0, 0.88 }, sat = 1.08, aberr = 0.5, shaft = 1.0, vig = 0.34 }

local SURFACE_AMBIENT = { 0.88, 0.76, 0.74 } -- warm evening light

-- The surface's sandstone runs down to CAVE_TOP, where the first area begins;
-- the generated areas are stacked below it, (see scenes/catacombs.lua for their layout)
local LEFT, RIGHT = -2880, 8640 -- the desert runs on both sides of the camp and the mine, over the side branches
local WIDTH = RIGHT - LEFT
local CAVE_TOP = 760
local TIERS = 5 -- how deep the catacombs go (their layout is in scenes/catacombs.lua)
local POND_X0, POND_X1 = 1318, 1378 -- an oasis pond between the bones and the ramp
local SPINE_W = catacombs.SPINE_W
local _, _, LAYOUT_TOP, LAYOUT_H = catacombs.layoutBounds()
local HEIGHT = CAVE_TOP + LAYOUT_H -- (the world's bottom edge)
-- and its top: an invisible ceiling well above the sky dungeon, higher than the
-- view can ever look (the camera stops at the sky's top: see camera.setTop), so
-- the hunter can fly up out of sight and fall back into view
local SKY_HEADROOM = 420
local TOP = CAVE_TOP + LAYOUT_TOP - SKY_HEADROOM

-- The old mine: a ramp down into a pit, the shaft in the pit floor, and two
-- timber-shored steps back up on the far side
local RAMP_X0 = 1450 -- top of the ramp
local PIT_X0 = 1606 -- bottom of the ramp
local SHAFT_X0, SHAFT_X1 = 1640, 1678
local PIT_X1 = 1720 -- end of the pit floor; first step up
local STEP_W = 22 -- width of the step (then the second rise, back to the plain)
local PIT_Y = 572 -- the pit floor
local SHAFT_BOTTOM = CAVE_TOP - 20 -- the cave generator carries it on from here
local ENTRANCE_Y = CAVE_TOP + 96
local SHAFT_CX = math.floor((SHAFT_X0 + SHAFT_X1) / 2)
local FRAME_TOP = PIT_Y - 150 -- the headframe's crossbeam, high enough to be seen from afar

-- Cave generation time per frame (seconds) while nobody is playing (the
-- title screen, a menu), so the title screen gets a head start on the first
-- area. While the hunter plays, generation gets what the frame has to spare
-- (see catacombs.step): a fixed share of every frame was the lag in the hub,
-- the first area and every fight (it vanished once everything was built).
local GEN_BUDGET = 0.010

local SPAWN_X = 990
local CAMPFIRE_X = 972 -- (just right of the tent, clear of the doctor's lot)
local TENT_X = 930
-- (the camp's people and the bounty board live on the lots of the town, src.town)
local WINCH_X = 1758 -- left edge of the winch house
local SUN_X, SUN_Y = 440, 196 -- on screen, low over the horizon

local background -- pre-rendered sky and parallax layers
local backgrounds = {} -- [eclipsed?] -> the sky and layers drawn that way (made when first wanted)
local trees = {}

-- Gently rolling ground of the open plain
local function plain(x)
  local lift = 0
  if x > 5350 then
    local t = math.min(1, (x - 5350) / 520)
    lift = 120 * t * t * (3 - 2 * t) -- the long ramp up to the mountain's door
  end
  -- Rolling dunes and hollows away from the camp and the mine, easing out near the mountain's ramp
  local far = math.max(0, math.min(1, (math.abs(x - 1100) - 800) / 400)) * math.max(0, math.min(1, (5300 - x) / 300))
  local rolling = far * (math.sin(x * 0.0031 + 4) * 24 + math.sin(x * 0.0093 + 0.5) * 11 + math.sin(x * 0.021 + 2) * 4)
  return 509 - lift + rolling + math.sin(x * 0.0058) * 8 + math.sin(x * 0.017 + 1) * 4 + math.sin(x * 0.043 + 2) * 1.5
end

-- The ground's top surface (before anything is built on it or dug out)
local function surface(x)
  if x >= RAMP_X0 and x < PIT_X0 then
    -- The ramp down into the pit eases in and out
    local g = plain(x)
    local t = (x - RAMP_X0) / (PIT_X0 - RAMP_X0)
    return math.floor(g + (PIT_Y - g) * t * t * (3 - 2 * t))
  elseif x >= PIT_X0 and x <= PIT_X1 then
    return PIT_Y
  elseif x > PIT_X1 and x <= PIT_X1 + STEP_W then
    return PIT_Y - 32
  end
  return math.floor(plain(x))
end

-- Flat-topped sandstone mesa with sloped sides (rising 3 px per px inward)
local function mesa(world, x0, x1, top, slope)
  for x = x0, x1 do
    local edge = math.min(x - x0, x1 - x)
    local y = top + math.max(0, (slope - edge)) * 3
    local jag = math.floor(love.math.noise(x * 0.19, top) * 5)
    world:fillRect(x, y + jag, x, surface(x) + 3, SANDSTONE)
  end
end

-- Canyon walls close the world off at each end: tall cliffs, highest at the
-- outer edge, with a ragged face
local function canyonWall(world, x0, x1, fromLeft)
  for x = x0, x1 do
    local t = fromLeft and (x1 - x) / (x1 - x0) or (x - x0) / (x1 - x0) -- 1 at the outer edge
    local top = math.floor(surface(x) - 40 - t ^ 1.4 * 380 - love.math.noise(x * 0.09, 5) * 18)
    world:fillRect(x, top, x, CAVE_TOP, SANDSTONE)
  end
end

-- A rounded boulder half sunk into the ground
local function boulder(world, cx, r, id)
  local g = surface(cx)
  for y = g - r, g + 2 do
    for x = cx - r - 2, cx + r + 2 do
      local dx, dy = (x - cx) / (r + 2), (y - (g - r * 0.3)) / r
      if dx * dx + dy * dy + (love.math.noise(x * 0.3, y * 0.3) - 0.5) * 0.3 < 1 then
        world:setRaw(x, y, id or SANDSTONE)
      end
    end
  end
end

-- A low mound of spoil from the mine
local function spoilHeap(world, x0, x1, height)
  local c, r = (x0 + x1) / 2, (x1 - x0) / 2
  for x = x0, x1 do
    local d = (x - c) / r
    local h = math.floor(height * (1 - d * d) + love.math.noise(x * 0.15, 9) * 3)
    if h > 0 then
      world:fillRect(x, surface(x) - h, x, surface(x) + 2, TAILINGS)
    end
  end
end

-- A weathered stone pillar with a broken, ragged top
local function pillar(world, cx, w, h)
  local ground = surface(cx)
  local x0 = cx - math.floor(w / 2)
  for x = x0, x0 + w - 1 do
    local top = ground - h + math.floor(love.math.noise(x * 0.5, h) * 6)
    world:fillRect(x, top, x, ground + 3, STONE)
  end
  -- Capital: a slightly wider block, only on the tall intact pillars
  if h > 40 then
    world:fillRect(x0 - 2, ground - h - 3, x0 + w + 1, ground - h, STONE)
  end
end

-- Out east: what is left of an ancient town in breakable stone
local function buildRuins(world)
  pillar(world, 2110, 9, 52)
  pillar(world, 2148, 8, 20)
  pillar(world, 2240, 9, 62)
  -- Lintel fragment still resting on the tall pillar
  world:fillRect(2226, surface(2240) - 70, 2262, surface(2240) - 66, STONE)
  -- Low wall remnant with a crumbled top
  for x = 2120, 2215 do
    local top = surface(x) - 4 - math.floor(love.math.noise(x * 0.2, 4) * 8)
    world:fillRect(x, top, x, surface(x) + 2, STONE)
  end
  -- Fallen column, half sunk in the sand
  for x = 2268, 2320 do
    local g = surface(x)
    world:fillRect(x, g - 6, x, g + 2, STONE)
  end
  -- A gateway: two pillars and the lintel across them
  pillar(world, 2370, 8, 56)
  pillar(world, 2410, 8, 56)
  world:fillRect(2362, surface(2390) - 64, 2418, surface(2390) - 59, STONE)
end

-- The mine: the shaft down from the pit floor, timber-lined, and the timber
-- facing of the steps back up
local function buildMine(world)
  world:fillRect(SHAFT_X0, PIT_Y - 40, SHAFT_X1, SHAFT_BOTTOM, AIR)
  world:fillRect(SHAFT_X0 - 3, PIT_Y, SHAFT_X0 - 1, SHAFT_BOTTOM, WOOD)
  world:fillRect(SHAFT_X1 + 1, PIT_Y, SHAFT_X1 + 3, SHAFT_BOTTOM, WOOD)
  world:fillRect(PIT_X1 + 1, PIT_Y - 32, PIT_X1 + 3, PIT_Y + 3, WOOD)
  local x2 = PIT_X1 + STEP_W + 1
  world:fillRect(x2, surface(x2), x2 + 2, PIT_Y - 29, WOOD)
end

local function lerpColor(a, b, t)
  return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

local SKY = {
  { 0.00, { 0.13, 0.10, 0.24 } }, -- dusky violet overhead
  { 0.50, { 0.38, 0.20, 0.32 } },
  { 0.85, { 0.80, 0.40, 0.28 } }, -- ember glow at the horizon
  { 1.00, { 0.90, 0.52, 0.30 } },
}

local function skyColor(t)
  for i = 1, #SKY - 1 do
    local a, b = SKY[i], SKY[i + 1]
    if t <= b[1] then
      return lerpColor(a[2], b[2], (t - a[1]) / (b[1] - a[1]))
    end
  end
  return SKY[#SKY][2][1], SKY[#SKY][2][2], SKY[#SKY][2][3]
end

local function buildBackground(eclipse)
  local W, H = config.VIRTUAL_W, config.VIRTUAL_H
  local rng = love.math.newRandomGenerator(7)
  local sky = love.image.newImageData(W, H)
  for y = 0, H - 1 do
    local r, g, b = skyColor(y / (H - 1))
    for x = 0, W - 1 do
      local dx, dy = x - SUN_X, y - SUN_Y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < 30 and eclipse then
        sky:setPixel(x, y, 0, 0, 0, 1) -- the sun swallowed: the black hole the sky champion left (src.starwarden)
      elseif d < 30 then
        local core = 1 - d / 30 * 0.12
        sky:setPixel(x, y, 1, 0.74 * core, 0.44 * core, 1) -- the setting sun
      else
        local glow = math.max(0, 1 - d / 220) ^ 2 * (eclipse and 0.05 or 0.45)
        if eclipse then
          -- ...a burning orange rim hugging it, and a thin disc of falling light seen edge-on across it
          local rim = math.max(0, 1 - (d - 30) / 5) ^ 2
          local ring = math.max(0, 1 - math.abs(d - 36) / 2.4)
          local disc = (math.abs(dy) < 2.6 and d > 30 and d < 95) and (1 - math.abs(dy) / 2.6) * math.max(0, 1 - (d - 30) / 65) or 0
          glow = glow + rim * 0.9 + ring * 0.35 + disc * 0.8
        end
        local dk = eclipse and 0.42 or 1 -- (the whole sky is darker now)
        local cr, cg, cb = math.min(1, r * dk + glow), math.min(1, g * dk + glow * (eclipse and 0.55 or 0.6)), math.min(1, b * dk * (eclipse and 1.1 or 1) + glow * (eclipse and 0.25 or 0.3))
        -- Long thin clouds, lit from below by the sun
        if y > 50 and y < 190 then
          local c = love.math.noise(x * 0.004, y * 0.05, 3.3)
          if c > 0.64 then
            local k = math.min(1, (c - 0.64) * 4) * 0.55
            local warm = math.max(0, 1 - d / 300)
            cr = cr + (0.62 + 0.3 * warm - cr) * k
            cg = cg + (0.30 + 0.2 * warm - cg) * k
            cb = cb + (0.36 - cb) * k
          end
        end
        sky:setPixel(x, y, cr, cg, cb, 1)
      end
    end
  end
  -- A few early stars, high up where the sky is darkest
  for _ = 1, 60 do
    local x, y = rng:random(0, W - 1), math.floor(rng:random() ^ 2 * H * 0.3)
    local s = 0.45 + rng:random() * 0.3
    sky:setPixel(x, y, s, s * 0.95, s, 1)
  end

  -- Silhouettes wider than the screen, so they scroll with parallax:
  -- distant mountains, then two rows of mesas (the nearer with the stumps of
  -- ruined towers here and there)
  local function layer(parallax, baseY, color, seed, kind)
    local w = math.ceil(W + (WIDTH - W) * parallax) + 2
    local img = love.image.newImageData(w, H)
    for x = 0, w - 1 do
      local top
      if kind == "mountains" then
        top = baseY - math.floor(love.math.noise(x * 0.006, seed) * 60 + love.math.noise(x * 0.03, seed + 2) * 12)
      else
        local n = love.math.noise(x * 0.005, seed)
        local mesaTop = n > 0.55 and baseY - 80 - math.floor((n - 0.55) * 128) or baseY
        top = mesaTop + math.floor(love.math.noise(x * 0.031, seed + 1) * 10)
        if kind == "towers" then
          local tower = love.math.noise(math.floor(x / 7) * 0.9, seed + 5)
          if tower > 0.82 and n <= 0.55 then
            top = top - math.floor((tower - 0.82) * 220)
          end
        end
      end
      for y = math.max(0, top), H - 1 do
        img:setPixel(x, y, color[1], color[2], color[3], 1)
      end
    end
    return { image = love.graphics.newImage(img), parallax = parallax, color = color }
  end

  return {
    sky = love.graphics.newImage(sky),
    layers = {
      layer(0.06, 268, { 0.50, 0.29, 0.36 }, 41, "mountains"),
      layer(0.15, 304, { 0.40, 0.22, 0.30 }, 11),
      layer(0.35, 344, { 0.26, 0.14, 0.20 }, 23, "towers"),
    },
  }
end

local seed
local lakes = {} -- { x0, x1, top } of the lakes over side branches (filled in populate)

-- opts.seed: cave seed (default random). opts.atCave: start in the
-- catacombs' entrance chamber instead of on the surface (generates at once).
function overworld.build(opts)
  lakes = {}
  local world = World.new(WIDTH, HEIGHT - TOP, LEFT, TOP)
  seed = (opts and opts.seed) or math.floor(love.math.random() * 1000000)

  -- Sand over sandstone (the cave generator replaces what lies below
  -- CAVE_TOP); the pit floor is trodden spoil
  for x = LEFT, RIGHT - 1 do
    local top = surface(x)
    local depth = 16 + math.floor(love.math.noise(x * 0.031, 3) * 10)
    local inPit = x >= PIT_X0 - 20 and x <= PIT_X1
    world:fillRect(x, top, x, top + depth, inPit and TAILINGS or SAND)
    world:fillRect(x, top + depth + 1, x, CAVE_TOP + 40, SANDSTONE)
  end

  -- Under the desert east of the first areas: unexplored rock (and bedrock at
  -- the world's edges), for the side branches to be carved from
  world:fillFast(SPINE_W, CAVE_TOP + 41, RIGHT - 1, HEIGHT - 1, ROCK)
  world:fillFast(LEFT, CAVE_TOP + 41, -1, HEIGHT - 1, ROCK)
  world:fillFast(RIGHT - 40, CAVE_TOP + 41, RIGHT - 1, HEIGHT - 1, BEDROCK)
  world:fillFast(LEFT, CAVE_TOP + 41, LEFT + 39, HEIGHT - 1, BEDROCK)
  world:fillFast(LEFT, HEIGHT - 40, RIGHT - 1, HEIGHT - 1, BEDROCK)

  canyonWall(world, LEFT, LEFT + 120, true)
  canyonWall(world, RIGHT - 121, RIGHT - 1, false)
  -- West: badlands
  boulder(world, 168, 9)
  boulder(world, 330, 7) -- (the big hill beside the camp is gone: the hub is open ground)
  -- (the natural arch that stood here fenced in the Prospector's camp and
  -- was taken out: the ground is open)
  -- The pond: a shallow hollow in the sand (filled with water in populate)
  for x = POND_X0, POND_X1 do
    local t = (x - (POND_X0 + POND_X1) / 2) / ((POND_X1 - POND_X0) / 2)
    local depth = math.floor(10 * (1 - t * t))
    local g = math.floor(plain(POND_X0 - 4))
    if depth > 0 then
      world:fillRect(x, g - 2, x, g + depth, AIR)
    end
  end
  -- East: spoil heaps, ruins, a boulder or two and another mesa
  buildMine(world)
  spoilHeap(world, 1830, 1950, 24)
  boulder(world, 2040, 8)
  buildRuins(world)
  boulder(world, 2470, 7)
  mesa(world, 2520, 2660, 404, 8)
  -- West of the badlands: more open desert, mesas and boulders, and the
  -- sealed-off shaft down to the flooded works (built with the crevices below)
  for _, m in ipairs({ { -2560, -2380, 372, 9 }, { -1960, -1800, 404, 8 }, { -1600, -1460, 360, 9 }, { -210, -90, 404, 8 } }) do
    mesa(world, m[1], m[2], m[3], m[4])
  end
  for _, bx in ipairs({ -2780, -2300, -2100, -1700, -440, -300 }) do
    boulder(world, bx, 6 + bx % 4)
  end
  for _, px in ipairs({ -1720, -1760, -400, -358 }) do
    pillar(world, px, 8, 30 + px % 31)
  end
  -- Farther east: open desert, mesas and boulders, with ruined pillars here and there
  for _, m in ipairs({ { 3280, 3460, 380, 9 }, { 4080, 4230, 404, 8 }, { 5000, 5150, 360, 10 } }) do
    mesa(world, m[1], m[2], m[3], m[4])
  end
  for _, bx in ipairs({ 3010, 3650, 4520, 4900, 5260, 5560 }) do
    boulder(world, bx, 6 + bx % 4)
  end
  for _, px in ipairs({ 4700, 4742, 5400, 5440 }) do
    pillar(world, px, 8, 30 + px % 31)
  end
  -- The crevices that lead down to the side branches: a ragged slot through
  -- the sandstone, a stone lip, and a plank lining below
  for _, e in ipairs(catacombs.entries()) do
    if e.walk then
      goto nextEntry -- (a doorway in a mountain: the cave generator cuts it)
    end
    local x0, x1 = e.x - e.half, e.x + e.half
    if e.lake then
      -- A lake: a wide bowl in the ground, narrowing to a neck that drops into the top of the cave below
      local rim = math.min(surface(x0), surface(x1))
      lakes[#lakes + 1] = { x0 = x0 + 6, x1 = x1 - 6, top = rim + 36 }
      -- A beach: the sand slopes gently down from the east bank into the water
      -- and on to the neck, where the cave opens; the far side is a steep bank
      local slopeEnd
      for x = x0, x1 do
        local depth
        local mx = x0 + x1 - x -- (mirrored, so the gentle slope faces the camp)
        slopeEnd = e.x - 90
        if mx < slopeEnd then
          local u = (mx - x0) / (slopeEnd - x0)
          depth = math.floor(230 * u ^ 1.35)
        else
          local u = (mx - slopeEnd) / (x1 - slopeEnd)
          depth = math.floor(230 * (1 - u ^ 3) ^ 0.8)
        end
        local g = surface(x)
        world:fillRect(x, g - 8, x, g + depth, AIR)
        world:fillRect(x, g + depth + 1, x, g + depth + 5, SAND)
      end
      world:fillRect(e.x - e.neck, surface(e.x), e.x + e.neck, SHAFT_BOTTOM, AIR)
      goto nextEntry
    end
    world:fillRect(x0 - 6, surface(e.x) - 14, x0 - 1, surface(e.x) + 2, STONE)
    world:fillRect(x1 + 1, surface(e.x) - 14, x1 + 6, surface(e.x) + 2, STONE)
    world:fillRect(x0, surface(e.x) - 30, x1, SHAFT_BOTTOM, AIR)
    world:fillRect(x0 - 3, surface(e.x) + 3, x0 - 1, SHAFT_BOTTOM, WOOD)
    world:fillRect(x1 + 1, surface(e.x) + 3, x1 + 3, SHAFT_BOTTOM, WOOD)
    ::nextEntry::
  end
  -- Barrens set dressing: rock structures cut into the desert, buried bones
  barrens.build(world, surface, seed, LEFT + 400, 5100, function(x)
    if x > 230 and x < 2050 then
      return true -- (the town starts at 490; structures reach 200 px right of where they start)
    end
    for _, e in ipairs(catacombs.entries()) do
      if math.abs(x - e.x) < (e.half or 100) + 280 then
        return true
      end
    end
    return false
  end, SANDSTONE, materials.FOSSIL)
  -- The town's lots (src.town): fixed every run, but a porch only goes up
  -- once its person has moved in
  town.build(world, surface, materials.HARDWOOD, SAND, AIR) -- (the porches' timber can't be broken)

  -- Only the first stretch is painted now (the cave paints itself as it
  -- generates, and the far desert as it comes into view)
  world:markLazy(SPINE_W, world.top, world.right - 1, world.bottom - 1)
  world:markLazy(LEFT, world.top, -1, world.bottom - 1)
  world:repaintRect(0, 0, SPINE_W - 1, CAVE_TOP + 40)
  require("src.airship").build(world) -- (a secret in the sky: nothing points to it)

  local eclipse = require("src.meta").isSkyBeaten()
  background = backgrounds[eclipse]
  if not background then
    background = buildBackground(eclipse)
    backgrounds[eclipse] = background
  end
  trees = {}
  for _, t in ipairs({ { 200, 1 }, { 1340, -1 }, { 2000, 1 }, { 2460, -1 }, { 2706, 1 }, { 3100, -1 }, { 3800, 1 }, { -2700, 1 }, { -2200, -1 }, { -1900, 1 }, { -1380, -1 }, { -460, -1 }, { -150, 1 }, { 4400, -1 }, { 5100, 1 }, { 5600, -1 } }) do
    trees[#trees + 1] = { x = t[1], y = world:findGround(t[1], 160), lean = t[2], height = 46 + (t[1] % 17) }
  end

  -- Shooting a shop hatch's chain makes sure the area below it exists first
  shop.onHatchBreak = function(child)
    catacombs.generate(child)
  end
  catacombs.surfaceName = overworld.title
  catacombs.start(world, {
    x0 = 0,
    y0 = CAVE_TOP,
    x1 = RIGHT - 1,
    entranceX = SHAFT_CX,
    entranceY = ENTRANCE_Y,
    shaftX0 = SHAFT_X0,
    shaftX1 = SHAFT_X1,
  }, seed, TIERS)
  local band = catacombs.spaceBand()
  require("src.camera").setTop(band and band.y0 or nil)
  if opts and opts.atCave then
    catacombs.finish(1)
    local info = catacombs.info()
    return world, info.spawnX, info.spawnY
  end

  return world, SPAWN_X, world:findGroundUnder(SPAWN_X, config.player.width, 160) - config.player.height
end

-- Testing: finishes generating the first three areas and stands the hunter on
-- the floor of the boss arena, left of centre (F8)
function overworld.toArena(player)
  catacombs.finish(3)
  local a = catacombs.info(3).arena
  local b = player.body
  b.x, b.y = math.floor(a.cx - 300 - b.w / 2), a.floorY - b.h - 1
  b.vx, b.vy = 0, 0
  player.physBody:setPosition(b.x + b.w / 2, b.y + b.h / 2)
end

-- Dev panel teleports: spec = { kind = "camp" } or { kind = "area" | "arena", i }
function overworld.devTeleport(player, spec)
  if spec.kind == "camp" then
    return overworld.toCamp(player)
  end
  catacombs.generate(spec.i)
  local info = catacombs.info(spec.i)
  local b = player.body
  if spec.kind == "arena" and info and info.arena then
    local a = info.arena
    b.x, b.y = math.floor(a.cx - math.min(260, a.w * 0.3) - b.w / 2), a.floorY - 130
  elseif info then
    b.x, b.y = info.spawnX, info.spawnY
  end
  b.vx, b.vy = 0, 0
  player.physBody:setPosition(b.x + b.w / 2, b.y + b.h / 2)
end

-- E at a boss pedestal in an arena
function overworld.interact(player)
  return catacombs.interact(player)
end

-- Back to the camp, where the run began (the way home from the shop after a boss)
function overworld.toCamp(player)
  local b = player.body
  local w = player.world
  local x = SPAWN_X
  b.x = x - math.floor(b.w / 2)
  b.y = w:findGroundUnder(x, b.w, 160) - b.h
  b.vx, b.vy = 0, 0
  player.physBody:setPosition(b.x + b.w / 2, b.y + b.h / 2)
end

-- Called once physics exists; the cave adds its own crates when generated
function overworld.populate(world)
  targets.clear()
  props.clear()
  catacombs.spawnProps()
  fluids.fillWater(world, POND_X0 + 1, POND_X1 - 1, math.floor(plain(POND_X0 - 4)) + 2)
  for _, l in ipairs(lakes) do
    fluids.floodBox(world, l.x0, l.top, l.x1, CAVE_TOP - 1)
  end
  local function ground(x)
    return world:findGround(x, 160)
  end
  -- The camp's practice range, just west of the tent: a DPS dummy and a few
  -- crates to kick about
  enemies.spawn("dummy", 832, ground(832))
  for i, x in ipairs({ 862, 876 }) do
    props.spawn("crate", x, ground(x) - 7)
    if i == 1 then
      props.spawn("crate", x + 7, ground(x) - 20)
    end
  end
  props.spawn("crate", 846, ground(846) - 7)
  -- Where the camp's people set up once they are freed (src.npcs; only
  -- drawn for a profile that has them)
  for _, lot in ipairs(town.LOTS) do
    if lot.id == "board" then
      npcs.setBoard(lot.x, lot.top)
    elseif lot.id ~= "hall" then
      npcs.setCamp(lot.id, lot.x, lot.top)
    end
  end
  -- The Bartender, once the hunter has fallen three times: drinking at the oasis pond's west bank
  npcs.setPond(POND_X0 - 6, ground(POND_X0 - 6))
  props.spawn("crate", 1700, ground(1700) - 7)
  props.spawn("ironCrate", 2335, ground(2335) - 8.5)
  -- Pots, pouches and lamps along the plain, by the camp and the ruins
  for _, o in ipairs({
    { "urn", 1288 }, { "urn", 2040 }, { "urn", 2480 },
    { "pouch", 826 }, { "pouch", 972 }, { "pouch", 1560 - 120 }, { "pouch", 2210 },
    { "lantern", 888 }, { "lantern", 1250 }, { "lantern", 2370 },
    { "skullCandle", 420 }, { "skullCandle", 2150 },
    { "emberPot", 1024 }, { "emberPot", 1880 }, { "emberPot", 2600 },
  }) do
    -- (nothing breakable stands in the camp itself: only the crates by the tent)
    if o[2] < 380 or o[2] > 1420 then
      local def = props.defs[o[1]]
      props.spawn(o[1], o[2], ground(o[2]) - def.height / 2 - 0.5)
    end
  end
  -- Something for whoever explores: a chest on top of the west mesa and one
  -- under the ruins' gateway
  do
    local ax, ay = require("src.airship").chestSpot()
    local c = chests.spawn(ax, ay, 1)
    c.onOpen = require("src.airship").openChest
  end
  chests.spawn(356, ground(356), 0.25)
  chests.spawn(2390, world:findGround(2390, surface(2390) - 30), 0.25)
  -- Farther out, a chest atop each of the far mesas, and pots in the open
  for _, cx in ipairs({ -2470, -1530, 3370, 5075 }) do
    chests.spawn(cx, ground(cx), 0.35)
  end
  for _, o in ipairs({
    { "urn", 3120 }, { "pouch", 3900 }, { "urn", 4640 }, { "emberPot", 5500 }, { "urn", 5700 },
    { "urn", -2600 }, { "pouch", -2100 }, { "urn", -1700 }, { "emberPot", -1340 }, { "urn", -480 },
  }) do
    local def = props.defs[o[1]]
    props.spawn(o[1], o[2], ground(o[2]) - def.height / 2 - 0.5)
  end
  for _, x in ipairs({ -2250, -1500, -1360, 3480, 4900, 5650 }) do
    props.spawn("crate", x, ground(x) - 7)
  end
end

-- How far underground a point is: 0 on the surface, 1 well inside the rock
local function underground(x, y)
  return math.max(0, math.min(1, (y - surface(x) - 24) / 220), catacombs.indoors(x, y))
end

-- The same, for the game's sound mixer
-- For the sound: which area the hunter is in (nil on the surface), and
-- whether he is in a shop room
function overworld.audioInfo(x, y)
  local area = underground(x, y) > 0.3 and catacombs.levelAt(y, x) or nil
  return area, catacombs.inShop(x, y)
end

function overworld.undergroundFactor(x, y)
  return underground(x, y)
end

-- Tumbleweeds roll across the plain on the wind, near the hunter
local weeds = {}

-- A tumbleweed's picture: a ball of grey-brown twigs, a ragged ring with
-- crossing sprigs through it, made once per size and variant and turned as it rolls
local weedImages = {}

local function weedImage(r, variant)
  local key = r * 10 + variant
  if weedImages[key] then
    return weedImages[key]
  end
  local size = 2 * r + 3
  local c = r + 1
  local data = love.image.newImageData(size, size)
  local rng = love.math.newRandomGenerator(r * 131 + variant * 17)
  local tones = { { 0.34, 0.26, 0.16 }, { 0.50, 0.39, 0.24 }, { 0.66, 0.54, 0.34 }, { 0.78, 0.66, 0.42 } }
  local function dot(x, y, t)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if x >= 0 and y >= 0 and x < size and y < size then
      local col = tones[t]
      data:setPixel(x, y, col[1], col[2], col[3], 1)
    end
  end
  -- (the dark inside first, then lighter twigs over it)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local d = math.sqrt((x - c) ^ 2 + (y - c) ^ 2)
      if d < r - 0.5 and rng:random() < 0.3 then
        dot(x, y, 1)
      end
    end
  end
  for _ = 1, r * 2 + 3 do
    -- a twig: a chord across the ball, wobbling a little
    local a = rng:random() * math.pi * 2
    local off = (rng:random() - 0.5) * r * 1.2
    local len = math.sqrt(math.max(1, r * r - off * off))
    local nx, ny = -math.sin(a), math.cos(a)
    local tone = rng:random() < 0.5 and 2 or 3
    for s = -len, len, 0.5 do
      local wob = math.sin(s * 1.3 + a) * 0.5
      dot(c + math.cos(a) * s + nx * (off + wob), c + math.sin(a) * s + ny * (off + wob), tone)
    end
  end
  -- a ragged outline with gaps, and a few sprigs poking out
  for i = 0, 40 do
    local a = i / 40 * math.pi * 2
    if rng:random() < 0.75 then
      local rr = r - 0.3 + (rng:random() - 0.5) * 1.1
      dot(c + math.cos(a) * rr, c + math.sin(a) * rr, rng:random() < 0.35 and 4 or 2)
    end
  end
  for _ = 1, 3 do
    local a = rng:random() * math.pi * 2
    dot(c + math.cos(a) * (r + 0.8), c + math.sin(a) * (r + 0.8), 2)
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  weedImages[key] = img
  return img
end

local function updateWeeds(dt, world, px, py)
  if py > 620 then
    weeds = {}
    return
  end
  while #weeds < 2 do
    weeds[#weeds + 1] = {
      x = px + 360 + love.math.random() * 300,
      y = 300,
      vy = 0,
      speed = 26 + love.math.random() * 24,
      spin = 0,
      r = 3 + love.math.random(0, 2),
      variant = love.math.random(1, 3),
    }
  end
  for i = #weeds, 1, -1 do
    local w = weeds[i]
    w.x = w.x - w.speed * dt
    w.spin = w.spin - w.speed * dt / w.r
    w.vy = w.vy + 500 * dt
    w.y = w.y + w.vy * dt
    local g = world:findGround(math.floor(w.x), math.max(0, math.floor(w.y) - 12))
    if w.y + w.r >= g then
      w.y = g - w.r
      -- A little hop every so often as it catches the ground
      w.vy = love.math.random() < 0.3 and -60 - love.math.random() * 50 or 0
    end
    if w.x < px - 420 or w.x < LEFT + 130 or w.y > 640 then
      table.remove(weeds, i)
    end
  end
end

local smokeTimer, dustTimer, moteTimer = 0, 0, 0

-- Generates the areas below a slice at a time, every frame (see GEN_BUDGET).
-- `spare` is what the frame has left once its own work is done.
function overworld.background(idle, px, py, spare)
  if idle or not px then
    catacombs.step(GEN_BUDGET) -- (nobody playing: build everything, in order)
  else
    catacombs.step(0, px, py, spare)
  end
end

-- Campfire smoke, blowing dust, tumbleweeds, and the light and banners
-- changing as the hunter goes underground
function overworld.update(dt, player, game, effects)
  local px, py = player:center()
  town.sync() -- (a person has moved in, or the save file changed)
  town.tick(dt) -- (the hall's bell, on the hour)
  smokeTimer = smokeTimer - dt
  if smokeTimer <= 0 then
    smokeTimer = 0.2
    -- The campfire's smoke is real smoke, drifting up through the simulation
    fluids.addSmoke(CAMPFIRE_X + (love.math.random() - 0.5) * 4, surface(CAMPFIRE_X) - 10, 0.8)
  end
  -- Wind lifts a little sand off the ground and carries it west
  dustTimer = dustTimer - dt
  if dustTimer <= 0 and effects and py < 620 then
    dustTimer = 0.12
    local x = px - 300 + love.math.random() * 640
    local s = 0.62 + love.math.random() * 0.1
    effects.particle(x, surface(math.floor(x)) - 1 - love.math.random() * 6, -50 - love.math.random() * 40, -6 - love.math.random() * 8, 1.2, { s, s * 0.8, s * 0.6 }, 10)
  end
  updateWeeds(dt, player.world, px, py)
  -- Dust turning slowly in the shaft's light
  moteTimer = moteTimer - dt
  if moteTimer <= 0 and effects and math.abs(px - SHAFT_CX) < 500 and py < CAVE_TOP + 300 then
    moteTimer = 0.1
    effects.particle(SHAFT_X0 + 2 + love.math.random() * (SHAFT_X1 - SHAFT_X0 - 4), PIT_Y + love.math.random() * 360, (love.math.random() - 0.5) * 6, 3 + love.math.random() * 5, 3, { 1, 0.85, 0.55 }, 0, true)
  end

  -- An area must be complete before the hunter can get anywhere near it
  if not catacombs.ready() and py > surface(px) + 12 then
    catacombs.finish(1)
  end
  catacombs.ensure(py, px)
  catacombs.update(player, dt)

  -- The light blends from the surface to the ambient of the area the hunter is in
  local t = underground(px, py)
  local cave = catacombs.theme(catacombs.levelAt(py, px) or 1).ambient
  for i = 1, 3 do
    overworld.ambient[i] = SURFACE_AMBIENT[i] + (cave[i] - SURFACE_AMBIENT[i]) * t
  end
  render.mixFx(overworld.fx, SURFACE_FX, catacombs.theme(catacombs.levelAt(py, px) or 1).fx, t)
  weather.apply(overworld.fx, overworld.ambient, 1 - t)
  if require("src.meta").isSkyBeaten() then
    -- (the sun is gone: the surface is darker for good)
    for i = 1, 3 do
      overworld.ambient[i] = overworld.ambient[i] * (1 - 0.3 * (1 - t))
    end
    overworld.fx.vig = (overworld.fx.vig or 0.34) + 0.12 * (1 - t)
  end
end

local function flicker(seed)
  local t = love.timer.getTime()
  return math.sin(t * 9 + seed) * 0.5 + math.sin(t * 23 + seed * 2) * 0.5
end

-- Lanterns: { x, y } of each flame (the headframe's, two posts by the ramp,
-- and the one by the tent)
local function lanterns()
  local list = {
    { SHAFT_CX - 12, FRAME_TOP + 20 },
    { RAMP_X0 - 4, surface(RAMP_X0 - 4) - 22 },
    { PIT_X0 - 8, surface(PIT_X0 - 8) - 22 },
    { TENT_X - 26, surface(TENT_X - 26) - 22 },
  }
  for _, e in ipairs(catacombs.entries()) do
    if e.walk then
      list[#list + 1] = { e.x - 455, surface(e.x - 455) - 24 }
    elseif not e.lake then
      list[#list + 1] = { e.x - e.half - 8, surface(e.x) - 24 }
      list[#list + 1] = { e.x + e.half + 8, surface(e.x) - 24 }
    end
  end
  return list
end

local function view(camX, camY)
  return { x = camX, y = camY, w = config.VIRTUAL_W, h = config.VIRTUAL_H }
end

function overworld.addLights(lighting, camX, camY)
  -- Low warm light from the setting sun's place in the sky, fading underground
  local sunlight = 1 - underground(camX + config.VIRTUAL_W / 2, camY + config.VIRTUAL_H / 2)
  if sunlight > 0 then
    if require("src.meta").isSkyBeaten() then
      lighting.add(camX + SUN_X, camY + SUN_Y, 360, 0.55, 0.5, 0.95, 0.2 * sunlight) -- (a cold glimmer round the black sun)
    else
      lighting.add(camX + SUN_X, camY + SUN_Y, 420, 1, 0.62, 0.38, 0.3 * sunlight)
    end
  end
  catacombs.addLights(lighting, view(camX, camY))
  require("src.airship").addLights(lighting, view(camX, camY))
  town.addLights(lighting, view(camX, camY))
  for i, l in ipairs(lanterns()) do
    lighting.add(l[1], l[2] + 4, 68, 1, 0.7, 0.35, 0.48 + flicker(i) * 0.05)
  end
  lighting.add(WINCH_X + 26, surface(WINCH_X + 26) - 14, 50, 1, 0.68, 0.32, 0.55)
  lighting.add(CAMPFIRE_X, surface(CAMPFIRE_X) - 5, 110, 1, 0.6, 0.3, 0.85 + flicker(2) * 0.12)
end

-- Vultures circling high over the mine, drawn with the sky at a parallax
local function drawVultures(camX, camY)
  local t = love.timer.getTime()
  local cx = 320 + (SHAFT_CX - camX - 320) * 0.5
  local cy = 112 - (camY - 300) * 0.25
  love.graphics.setColor(0.12, 0.07, 0.10)
  for i = 1, 3 do
    local a = t * (0.22 + i * 0.05) + i * 2.1
    local r = 22 + i * 13
    local x = math.floor(cx + math.cos(a) * r)
    local y = math.floor(cy + math.sin(a) * r * 0.35 + i * 6)
    local flap = math.sin(t * 5 + i * 3) > 0.6 and -1 or 0
    love.graphics.rectangle("fill", x, y, 1, 1)
    love.graphics.rectangle("fill", x - 2, y + flap, 2, 1)
    love.graphics.rectangle("fill", x + 1, y + flap, 2, 1)
    love.graphics.rectangle("fill", x - 3, y + 1 + flap * 2, 1, 1)
    love.graphics.rectangle("fill", x + 3, y + 1 + flap * 2, 1, 1)
  end
end

-- High in the sky (the Cloud Reaches) the dusk gives way to space: the sky
-- darkens toward the top of the area into a starfield with a faint band of
-- nebula, and far banks of cloud drift past below. Screen space, like the rest
-- of the background; worked out per row from the world height it shows.
local SPACE_DEEP = { 0.012, 0.012, 0.035 }
local SPACE_MID = { 0.07, 0.07, 0.20 }

local function drawSpace(camX, camY)
  local band = catacombs.spaceBand()
  if not band then
    return
  end
  local W, H = config.VIRTUAL_W, config.VIRTUAL_H
  -- 0 a little below the cloud floor, 1 near the area's top: a long, gradual overlap of dusk and space
  local lo, hi = band.y1 + 150, band.y0 + 250
  local function depth(wy)
    local d = math.max(0, math.min(1, (lo - wy) / (lo - hi)))
    return d * d * (3 - 2 * d)
  end
  local fight = require("src.enemies").skyFight() -- (1 while the Champion fights: the sky around the hall is only space)
  if depth(camY + H) <= 0 and fight <= 0.01 then
    return
  end
  local t = love.timer.getTime()
  if fight > 0.01 then
    love.graphics.setColor(SPACE_DEEP[1], SPACE_DEEP[2], SPACE_DEEP[3], math.min(1, fight * 1.15))
    love.graphics.rectangle("fill", 0, 0, W, H)
  end
  -- Far cloud banks drifting, lit from the dusk below
  for layer = 1, 3 do
    if fight > 0.8 then
      break
    end
    local p = 0.1 + layer * 0.08
    local baseY = math.floor((band.y1 - 340 + layer * 60 - camY) * p + H * (1 - p) * 0.6)
    local drift = t * (3 + layer * 2)
    local a = (0.16 + layer * 0.06) * (1 - fight)
    local shade = 0.5 + layer * 0.12
    for sx = 0, W, 4 do
      local wx = sx + camX * p + drift
      local h = love.math.noise(wx * 0.004, layer * 7.3) * 40 + love.math.noise(wx * 0.017, layer * 3.1) * 14
      local top = baseY - math.floor(h)
      if top < H then
        love.graphics.setColor(0.62 * shade + 0.25, 0.62 * shade + 0.28, 0.80 * shade + 0.2, a)
        love.graphics.rectangle("fill", sx, top, 4, H - top)
        love.graphics.setColor(1, 0.86, 0.80, a * 0.8)
        love.graphics.rectangle("fill", sx, top, 4, 1)
      end
    end
  end
  -- The dark of space, deeper the higher the row
  for sy = 0, H - 1, 3 do
    local d = depth(camY + sy)
    if d > 0 then
      love.graphics.setColor(SPACE_MID[1] + (SPACE_DEEP[1] - SPACE_MID[1]) * d, SPACE_MID[2] + (SPACE_DEEP[2] - SPACE_MID[2]) * d, SPACE_MID[3] + (SPACE_DEEP[3] - SPACE_MID[3]) * d, d * 0.95)
      love.graphics.rectangle("fill", 0, sy, W, 3)
    end
  end
  -- A faint nebula band, slow to move
  local np = 0.04
  for sx = 0, W, 3 do
    local wx = sx + camX * np
    for k = 0, 5 do
      local sy = math.floor((band.y0 + 380 - camY) * 0.3 + math.sin(wx * 0.006) * 40 + k * 7 + love.math.noise(wx * 0.01, k) * 18)
      if sy >= 0 and sy < H then
        local a = depth(camY + sy) * 0.08 * love.math.noise(wx * 0.008, k * 0.7, 4.2)
        love.graphics.setColor(k % 2 == 0 and 0.55 or 0.35, 0.30, 0.80, a)
        love.graphics.rectangle("fill", sx, sy, 3, 7)
      end
    end
  end
  -- Stars: a fixed field that barely moves, twinkling, showing as the sky darkens
  local sp = 0.05
  local ox, oy = camX * sp, (camY - band.y0) * 0.25
  for i = 0, 220 do
    local hx, hy = math.sin(i * 12.9898) * 43758.5453, math.sin(i * 78.233) * 12543.123
    hx, hy = hx - math.floor(hx), hy - math.floor(hy)
    local sx = (hx * (W + 400) - ox) % (W + 400) - 200
    local sy = math.floor(hy * 900 - oy)
    if sx >= 0 and sx < W and sy >= 0 and sy < H then
      local d = math.max(depth(camY + sy), fight)
      if d > 0.05 then
        local tw = 0.6 + 0.4 * math.sin(t * (1 + hx * 2) + i)
        local big = i % 17 == 0
        love.graphics.setColor(0.85 + hy * 0.15, 0.88, 1, d * tw)
        love.graphics.rectangle("fill", math.floor(sx), sy, 1, 1)
        if big then
          love.graphics.setColor(0.8, 0.85, 1, d * tw * 0.4)
          love.graphics.rectangle("fill", math.floor(sx) - 1, sy, 3, 1)
          love.graphics.rectangle("fill", math.floor(sx), sy - 1, 1, 3)
        end
      end
    end
  end
  -- After the Champion has fallen: the dark of space turns violet and the stars wheel round the hole he left
  local hole = require("src.enemies").skyHole()
  if hole then
    local k = math.min(1, hole.t / 8)
    for sy = 0, H - 1, 3 do
      local d = math.max(depth(camY + sy), fight)
      if d > 0 then
        love.graphics.setColor(0.02, 0.0, 0.05, d * 0.5 * k) -- (darker, with only a trace of violet)
        love.graphics.rectangle("fill", 0, sy, W, 3)
      end
    end
    local hx, hy = hole.x - camX, hole.y - camY
    for i = 1, 240 do
      local h1 = math.sin(i * 12.9898) * 43758.5453
      local h2 = math.sin(i * 78.233) * 12543.123
      h1, h2 = h1 - math.floor(h1), h2 - math.floor(h2)
      local r0 = 24 + h2 * h2 * 520
      local ang = h1 * 6.283 + t * (70 / (r0 + 40))
      local r = r0 * (1 - 0.2 * k)
      local x, y = hx + math.cos(ang) * r, hy + math.sin(ang) * r * 0.55
      if x >= 0 and x < W and y >= 0 and y < H then
        love.graphics.setColor(1, 0.8 + 0.2 * h1, 0.6 + 0.4 * h2, k * 0.85 * (1 - r0 / 560))
        love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 1)
      end
    end
    love.graphics.setColor(1, 0.5, 0.2, 0.08 * k)
    love.graphics.circle("fill", hx, hy, 70)
  end
end

-- The black sun bends only the sky behind it (its own surroundings), as it is drawn
local bendShader
local function bendBegin(x, y, w, h)
  if bendShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      uniform vec2 lensPos;
      uniform float lensR;
      uniform float strength;
      uniform vec2 imgPos;
      uniform vec2 imgSize;
      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec2 d = sc - lensPos;
        float r = max(length(d), 0.5);
        float k = lensR / (r + lensR * 0.3);
        float disp = strength * lensR * 1.2 * k * k * smoothstep(lensR * 7.0, lensR * 0.5, r);
        disp = min(disp, r * 0.9);
        vec2 s = sc - d / r * disp;
        vec2 q = (s - imgPos) / imgSize;
        if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) {
          return vec4(0.0);
        }
        return Texel(tex, q) * color;
      }
    ]])
    bendShader = ok and sh or false
  end
  if not bendShader then
    return
  end
  bendShader:send("lensPos", { SUN_X, SUN_Y })
  bendShader:send("lensR", 30)
  bendShader:send("strength", 1.5)
  bendShader:send("imgPos", { x, y })
  bendShader:send("imgSize", { w, h })
  love.graphics.setShader(bendShader)
end

-- The black sun, alive: a thin disc turning round it, and pixels that drift in from the sky and spiral down
local function drawBlackSun()
  local t = love.timer.getTime()
  love.graphics.setBlendMode("add")
  -- light falling in from the whole sky: pixels drifting down toward it
  for q = 0, 70 do
    local ph = (t * 0.07 + q * 0.0611) % 1
    local ang = q * 2.399
    local rr = 42 + (1 - ph) * (110 + (q % 9) * 14)
    love.graphics.setColor(0.9, 0.7, 0.9, ph * 0.55)
    love.graphics.rectangle("fill", math.floor(SUN_X + math.cos(ang + ph * 2.5) * rr), math.floor(SUN_Y + math.sin(ang + ph * 2.5) * rr * 0.75), 1, 1)
  end
  love.graphics.setBlendMode("alpha")
end

function overworld.drawBackground(camX, camY)
  if camY > CAVE_TOP - 200 then
    return -- the view is all underground; the backdrop (drawDecor) covers it
  end
  -- (asked every frame: a world built behind the title with another save's profile must not keep its sun)
  local black = require("src.meta").isSkyBeaten()
  local background = backgrounds[black]
  if not background then
    background = buildBackground(black)
    backgrounds[black] = background
  end
  love.graphics.setColor(1, 1, 1)
  -- (stretched across if the view has grown wider than when it was painted)
  local ssx, ssy = math.max(1, config.VIRTUAL_W / background.sky:getWidth()), math.max(1, config.VIRTUAL_H / background.sky:getHeight())
  if black then
    bendBegin(0, 0, background.sky:getWidth() * ssx, background.sky:getHeight() * ssy)
  end
  love.graphics.draw(background.sky, 0, 0, 0, ssx, ssy)
  love.graphics.setShader()
  if black then
    drawBlackSun() -- (alive: pixels drifting round it, in front of the sky and behind the far scenery)
  end
  for i, l in ipairs(background.layers) do
    local oy = -math.floor(camY * l.parallax * 0.5)
    love.graphics.setColor(1, 1, 1)
    local lx = -math.floor((camX - LEFT) * l.parallax)
    love.graphics.draw(l.image, lx, oy)
    -- When the camera is high the layer scrolls up; keep its base filled
    local bottom = oy + l.image:getHeight()
    if bottom < config.VIRTUAL_H then
      love.graphics.setColor(l.color)
      love.graphics.rectangle("fill", 0, bottom, config.VIRTUAL_W, config.VIRTUAL_H - bottom)
    end
    if i == 1 then
      drawVultures(camX, camY) -- between the far mountains and the mesas
    end
  end
  -- Dust haze hanging over the plain
  local t = love.timer.getTime()
  for i = 0, 5 do
    local y = 270 + i * 10 - math.floor(camY * 0.15)
    local a = 0.05 + 0.02 * math.sin(t * 0.25 + i)
    love.graphics.setColor(0.92, 0.62, 0.44, a)
    love.graphics.rectangle("fill", 0, y, config.VIRTUAL_W, 16)
  end
  drawSpace(camX, camY)
end

-- Twisted dead tree: a leaning trunk with forked, tapering branches
local function drawTree(tree)
  local rng = love.math.newRandomGenerator(tree.x)
  local function branch(x, y, angle, length, width)
    local ex, ey = x + math.cos(angle) * length, y + math.sin(angle) * length
    love.graphics.setLineWidth(width)
    love.graphics.line(x, y, ex, ey)
    if length > 6 then
      branch(ex, ey, angle - 0.35 - rng:random() * 0.3, length * 0.68, math.max(1, width - 1))
      if rng:random() < 0.7 then
        branch(ex, ey, angle + 0.3 + rng:random() * 0.35, length * 0.6, math.max(1, width - 1))
      end
    end
  end
  love.graphics.setColor(0.24, 0.17, 0.15)
  branch(tree.x + 0.5, tree.y + 2, -math.pi / 2 + tree.lean * 0.18, tree.height * 0.45, 3)
  love.graphics.setLineWidth(1)
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

-- A straight timber w pixels thick from (x0, y0) to (x1, y1)
local function beam(x0, y0, x1, y1, w)
  local n = math.max(1, math.abs(x1 - x0), math.abs(y1 - y0))
  for i = 0, n do
    local t = i / n
    rect(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, w, w)
  end
end

-- Pseudo-random 0..1 from two integers (stable, for placing scenery)
local function hash(i, k)
  local n = math.sin(i * 127.1 + k * 311.7) * 43758.5453
  return n - math.floor(n)
end

local TIMBER = { 0.30, 0.22, 0.16 }
local TIMBER_LIT = { 0.42, 0.31, 0.22 }

-- The view's horizontal reach this frame (set by overworld.drawDecor): the set pieces below are skipped
-- when they are wholly off it
local cullX0, cullX1 = -math.huge, math.huge
local function visibleX(a, b)
  return b >= cullX0 and a <= cullX1
end

-- The headframe over the shaft: two leaning legs, crossbeams and braces, a
-- back-brace down to the step, the sheave wheel on top, and the hoist rope
-- running down the shaft and over to the winch house
local function drawHeadframe()
  if not visibleX(SHAFT_X0 - 24, math.max(WINCH_X + 10, PIT_X1 + 20)) then
    return
  end
  local legL0, legR0 = SHAFT_X0 - 16, SHAFT_X1 + 14
  local legL1, legR1 = SHAFT_X0 - 5, SHAFT_X1 + 3
  local midY = PIT_Y - 72
  local function legX(x0, x1, y)
    return x0 + (x1 - x0) * (PIT_Y - y) / (PIT_Y - FRAME_TOP)
  end
  love.graphics.setColor(TIMBER)
  beam(legL0, PIT_Y, legL1, FRAME_TOP, 3)
  beam(legR0, PIT_Y, legR1, FRAME_TOP, 3)
  -- X braces between the legs, below and above the middle beam
  beam(legX(legL0, legL1, PIT_Y - 4), PIT_Y - 4, legX(legR0, legR1, midY), midY, 2)
  beam(legX(legR0, legR1, PIT_Y - 4), PIT_Y - 4, legX(legL0, legL1, midY), midY, 2)
  beam(legX(legL0, legL1, midY), midY, legX(legR0, legR1, FRAME_TOP + 8), FRAME_TOP + 8, 2)
  beam(legX(legR0, legR1, midY), midY, legX(legL0, legL1, FRAME_TOP + 8), FRAME_TOP + 8, 2)
  -- Back-brace down to the first step
  beam(legR1 + 1, FRAME_TOP + 4, PIT_X1 + 12, PIT_Y - 34, 3)
  -- Crossbeams with a lit top edge
  rect(legX(legL0, legL1, midY) - 2, midY, legX(legR0, legR1, midY) - legX(legL0, legL1, midY) + 7, 3)
  rect(SHAFT_X0 - 10, FRAME_TOP, SHAFT_X1 - SHAFT_X0 + 20, 4)
  love.graphics.setColor(TIMBER_LIT)
  rect(SHAFT_X0 - 10, FRAME_TOP, SHAFT_X1 - SHAFT_X0 + 20, 1)
  rect(legX(legL0, legL1, midY) - 2, midY, legX(legR0, legR1, midY) - legX(legL0, legL1, midY) + 7, 1)
  -- The sheave wheel, turning slowly, on its bearing posts
  local wx, wy, r = SHAFT_CX + 0.5, FRAME_TOP - 9.5, 9
  love.graphics.setColor(TIMBER)
  rect(SHAFT_CX - 2, FRAME_TOP - 10, 5, 10)
  love.graphics.setColor(0.20, 0.19, 0.21)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", wx, wy, r)
  love.graphics.setLineWidth(1)
  local a = love.timer.getTime() * 0.4
  for k = 0, 2 do
    local s = a + k * math.pi / 3
    love.graphics.line(wx - math.cos(s) * r, wy - math.sin(s) * r, wx + math.cos(s) * r, wy + math.sin(s) * r)
  end
  love.graphics.setColor(0.45, 0.43, 0.46)
  rect(SHAFT_CX - 1, FRAME_TOP - 11, 3, 3)
  -- Hoist rope: down into the shaft, and across to the winch house's drum
  love.graphics.setColor(0.36, 0.30, 0.22)
  rect(SHAFT_CX - 9, FRAME_TOP - 9, 1, PIT_Y + 40 - FRAME_TOP)
  local wgy = surface(WINCH_X + 6)
  beam(SHAFT_CX + 9, FRAME_TOP - 9, WINCH_X + 4, wgy - 16, 1)
  -- The lantern's iron cage, hanging off the crossbeam
  local lx, ly = SHAFT_CX - 12, FRAME_TOP + 20
  love.graphics.setColor(0.14, 0.12, 0.12)
  rect(lx, FRAME_TOP + 4, 1, 15)
  rect(lx - 2, ly - 1, 5, 1)
  rect(lx - 2, ly + 7, 5, 1)
  rect(lx - 2, ly, 1, 7)
  rect(lx + 2, ly, 1, 7)
end

-- A lantern hanging from a crooked post (the flame is drawn emissive)
local function drawLanternPost(x)
  if not visibleX(x - 3, x + 7) then
    return
  end
  local g = surface(x)
  love.graphics.setColor(TIMBER)
  rect(x + 4, g - 28, 2, 28)
  rect(x, g - 28, 6, 2)
  love.graphics.setColor(0.14, 0.12, 0.12)
  rect(x, g - 26, 1, 3)
  rect(x - 2, g - 23, 5, 1)
  rect(x - 2, g - 15, 5, 1)
  rect(x - 2, g - 22, 1, 7)
  rect(x + 2, g - 22, 1, 7)
end

-- Rails down the ramp to the shaft, with an ore cart waiting at the top
local function drawRails(vx0, vx1)
  local x0, x1 = math.max(1352, vx0), math.min(PIT_X0 + 24, vx1)
  for x = x0, x1 do
    local g = surface(x)
    if x % 6 == 0 then
      love.graphics.setColor(0.24, 0.17, 0.12)
      rect(x - 1, g - 1, 4, 1) -- sleepers
    end
    love.graphics.setColor(0.36, 0.34, 0.36)
    rect(x, g - 2, 1, 1)
  end
  -- Buffer stop at the bottom
  love.graphics.setColor(TIMBER)
  rect(PIT_X0 + 24, PIT_Y - 6, 3, 6)
  -- The ore cart, tipped forward on the slope's start, half full of spoil
  local cx = 1404
  local g = surface(cx)
  love.graphics.setColor(0.40, 0.35, 0.31)
  rect(cx - 6, g - 13, 13, 3)
  love.graphics.setColor(0.27, 0.27, 0.30)
  rect(cx - 7, g - 11, 15, 7)
  love.graphics.setColor(0.38, 0.38, 0.42)
  rect(cx - 7, g - 11, 15, 1)
  rect(cx - 5, g - 9, 1, 4)
  rect(cx + 4, g - 9, 1, 4)
  love.graphics.setColor(0.14, 0.13, 0.15)
  rect(cx - 5, g - 4, 3, 3)
  rect(cx + 3, g - 4, 3, 3)
end

-- The winch house: a plank shack with a slanted roof, a door and a lit window
local function drawWinchHouse()
  if not visibleX(WINCH_X - 4, WINCH_X + 42) then
    return
  end
  local x, g = WINCH_X, surface(WINCH_X + 18)
  love.graphics.setColor(0.33, 0.24, 0.17)
  rect(x, g - 24, 38, 24)
  love.graphics.setColor(0.27, 0.19, 0.13)
  for px = x + 3, x + 36, 5 do
    rect(px, g - 24, 1, 24) -- plank seams
  end
  -- Roof, sloping down to the right, with an overhang
  love.graphics.setColor(0.22, 0.16, 0.12)
  for i = 0, 43 do
    rect(x - 3 + i, g - 31 + math.floor(i * 0.16), 1, 4)
  end
  -- Door and window frame
  love.graphics.setColor(0.18, 0.13, 0.10)
  rect(x + 26, g - 16, 7, 16)
  rect(x + 7, g - 18, 9, 7)
end

-- The hunter's camp: a canvas lean-to, a bedroll, and the campfire ring
local function drawCamp()
  if not visibleX(math.min(TENT_X - 30, CAMPFIRE_X - 10), math.max(TENT_X + 20, CAMPFIRE_X + 10)) then
    return
  end
  local g = surface(TENT_X)
  -- Lean-to: a sloping canvas sheet over a ridge pole, open toward the fire
  love.graphics.setColor(TIMBER)
  rect(TENT_X - 18, g - 20, 2, 20)
  rect(TENT_X + 14, g - 3, 2, 3)
  love.graphics.setColor(0.50, 0.44, 0.34)
  love.graphics.polygon("fill", TENT_X - 17, g - 20, TENT_X + 16, g, TENT_X - 17, g)
  love.graphics.setColor(0.40, 0.35, 0.27)
  love.graphics.polygon("fill", TENT_X - 17, g - 13, TENT_X + 4, g, TENT_X - 17, g)
  love.graphics.setColor(0.60, 0.54, 0.42)
  beam(TENT_X - 17, g - 20, TENT_X + 15, g - 1, 1)
  -- A bedroll and a pack under it
  love.graphics.setColor(0.42, 0.14, 0.13)
  rect(TENT_X - 12, g - 3, 12, 3)
  love.graphics.setColor(0.30, 0.10, 0.10)
  rect(TENT_X - 12, g - 3, 2, 3)
  love.graphics.setColor(0.34, 0.27, 0.18)
  rect(TENT_X - 15, g - 6, 4, 6)
  drawLanternPost(TENT_X - 26)
  -- Campfire: a ring of stones and crossed logs
  local cg = surface(CAMPFIRE_X)
  love.graphics.setColor(0.36, 0.33, 0.34)
  for _, dx in ipairs({ -7, -5, 5, 7 }) do
    rect(CAMPFIRE_X + dx, cg - 2, 2, 2)
  end
  love.graphics.setColor(0.28, 0.18, 0.12)
  love.graphics.line(CAMPFIRE_X - 5.5, cg - 0.5, CAMPFIRE_X + 4.5, cg - 3.5)
  love.graphics.line(CAMPFIRE_X - 4.5, cg - 3.5, CAMPFIRE_X + 5.5, cg - 0.5)
end

-- Bleached bones of something huge, half buried beside the path, and a
-- smaller skull out west
local BONE, BONE_DARK = { 0.76, 0.70, 0.58 }, { 0.52, 0.47, 0.39 }
local function drawBones()
  local x0 = 1396 -- (moved east of the pond, out of the town's lots)
  if not visibleX(x0 - 16, x0 + 70) then
    -- (only the small skull out west might be in view)
    if visibleX(464, 476) then
      local tx, tg = 468, surface(468)
      love.graphics.setColor(BONE)
      rect(tx, tg - 4, 6, 4)
      rect(tx - 2, tg - 6, 2, 1)
      rect(tx + 6, tg - 6, 2, 1)
      love.graphics.setColor(BONE_DARK)
      rect(tx + 1, tg - 3, 1, 1)
      rect(tx + 4, tg - 3, 1, 1)
    end
    return
  end
  -- Spine along the ground
  for x = x0, x0 + 58, 3 do
    love.graphics.setColor(BONE_DARK)
    rect(x, surface(x) - 2, 2, 2)
  end
  -- Ribs arching up and over, shorter toward the tail
  for i = 0, 6 do
    local bx = x0 + 6 + i * 7
    local h = 18 - i * 2
    local g = surface(bx)
    love.graphics.setColor(BONE)
    for k = 0, h do
      local curl = math.floor((k / h) ^ 2 * 5)
      rect(bx + curl, g - 2 - k, 1, 1)
    end
    love.graphics.setColor(BONE_DARK)
    rect(bx + 5, g - h - 2, 1, 2)
  end
  -- The skull with one long horn
  local sx, sg = x0 - 12, surface(x0 - 12)
  love.graphics.setColor(BONE)
  rect(sx, sg - 6, 11, 5)
  rect(sx - 3, sg - 4, 4, 3)
  love.graphics.setColor(BONE_DARK)
  rect(sx + 3, sg - 5, 2, 2)
  love.graphics.setColor(BONE)
  for k = 0, 6 do
    rect(sx + 9 + math.floor(k * 0.5), sg - 7 - k, 1, 1)
  end
  -- A small horned skull out west
  local tx, tg = 468, surface(468)
  rect(tx, tg - 4, 6, 4)
  rect(tx - 2, tg - 6, 2, 1)
  rect(tx + 6, tg - 6, 2, 1)
  love.graphics.setColor(BONE_DARK)
  rect(tx + 1, tg - 3, 1, 1)
  rect(tx + 4, tg - 3, 1, 1)
end

-- Dry grass tufts and pebbles strewn along the ground
local function drawGroundClutter(vx0, vx1)
  for i = math.floor(vx0 / 9), math.floor(vx1 / 9) do
    local x = i * 9 + math.floor(hash(i, 3) * 6)
    if x > LEFT + 125 and x < RIGHT - 125 and (x < PIT_X0 - 20 or x > PIT_X1 + STEP_W + 4) then
      local h = hash(i, 1)
      local g = surface(x)
      if h > 0.62 then
        local tall = 2 + math.floor(hash(i, 2) * 3)
        love.graphics.setColor(0.58, 0.48, 0.32)
        rect(x, g - tall, 1, tall)
        rect(x - 1, g - tall + 1, 1, tall - 1)
        love.graphics.setColor(0.48, 0.38, 0.26)
        rect(x + 1, g - tall + 1, 1, tall - 1)
      elseif h < 0.2 then
        love.graphics.setColor(0.42, 0.30, 0.25)
        rect(x, g - 1, 2, 1)
      end
    end
  end
end

local function drawWeeds()
  love.graphics.setColor(1, 1, 1)
  for _, w in ipairs(weeds) do
    local img = weedImage(w.r, w.variant or 1)
    local half = img:getWidth() / 2
    love.graphics.draw(img, math.floor(w.x) + 0.5, math.floor(w.y) + 0.5, w.spin, 1, 1, half, half)
  end
end

local EARTH = { 0.10, 0.07, 0.07 }
local EARTH_NEAR = { 0.30, 0.19, 0.15 }
local CAVE_BACK = { 0.10, 0.08, 0.14 }

-- Colour of the backdrop behind the terrain at a depth: dark earth under the
-- surface, turning to the catacombs' cold gloom, darker the deeper you go
local function backdrop(y, x)
  if y < CAVE_TOP then
    return lerpColor(EARTH, CAVE_BACK, math.max(0, (y - (CAVE_TOP - 120)) / 120))
  end
  return catacombs.backdrop(y, x)
end

-- The far scenery of the caves: two layers per area that slide past more
-- slowly than the near terrain, so the open caverns have depth, in the style of
-- the area in view (see src.parallax)

-- Inside a mountain that stands in the open air (the Needle) there is no earth
-- behind the rock: a backdrop and the area's far scenery are drawn in
-- horizontal bands, each clipped to the mountain's silhouette at its top edge
-- (the rock walls are thicker than a band's step, so nothing shows outside)
local NEEDLE_BAND = 40
local NEEDLE_FEATHER = 60 -- px over which the backdrop fades in at the mountain's face

local function drawMountainDepth(camX, camY, vx0, vy0, vx1, vy1)
  for _, m in ipairs(catacombs.climbLevels()) do
    local top, bottom = math.max(vy0, m.y0, -1e9), math.min(vy1, m.y1, CAVE_TOP - 120)
    if bottom > top then
      -- The far scenery of a run of bands the same width is drawn in one go once the run ends (its
      -- pixels don't depend on where the bands split, and the bands don't overlap): drawn band by band
      -- it was ten passes over the scenery and a few hundred draw calls a frame
      local runX0, runX1, runY0, runY1
      local function flushRun()
        if runX0 then
          love.graphics.setScissor(math.floor(runX0 - camX), math.floor(runY0 - camY), math.ceil(runX1 - runX0), runY1 - runY0)
          parallax.draw(m.theme.parallax or m.index, camX, camY, runX0, runY0, runX1, runY1, m.theme.pillars)
          runX0 = nil
        end
      end
      local y = m.y0 + math.floor((top - m.y0) / NEEDLE_BAND) * NEEDLE_BAND -- (the bands start at the mountain's top, so none reaches above the summit)
      while y < bottom do
        local xa, xb = m.theme.profile(math.max(y, m.y0))
        if xa then
          local bx0, bx1 = math.max(xa, vx0), math.min(xb, vx1)
          if bx1 > bx0 then
            -- The backdrop eases in over the first FEATHER px past the mountain's
            -- face (strips that fade up from nothing), so the doorway does not
            -- show the cave's dark as a hard-edged slab against the sky
            local feather = xa >= vx0 and math.min(NEEDLE_FEATHER, bx1 - bx0) or 0
            if feather > 0 then
              local cr, cg, cb, ca = catacombs.backdrop(y, bx0)
              local strips = feather / 3
              love.graphics.setScissor(math.floor(bx0 - camX), math.floor(y - camY), math.ceil(feather), NEEDLE_BAND)
              for j = 0, strips - 1 do
                local a = ((j + 0.5) / strips) ^ 1.6
                love.graphics.setColor(cr, cg, cb, (ca or 1) * a)
                love.graphics.rectangle("fill", bx0 + j * 3, y, 3, NEEDLE_BAND)
              end
            end
            local sx0 = bx0 + feather
            if bx1 > sx0 then
              love.graphics.setScissor(math.floor(sx0 - camX), math.floor(y - camY), math.ceil(bx1 - sx0), NEEDLE_BAND)
              love.graphics.setColor(catacombs.backdrop(y, sx0))
              love.graphics.rectangle("fill", sx0, y, bx1 - sx0, NEEDLE_BAND)
              if runX0 and (runX0 ~= sx0 or runX1 ~= bx1 or runY1 ~= y) then
                flushRun()
              end
              if runX0 then
                runY1 = y + NEEDLE_BAND
              else
                runX0, runX1, runY0, runY1 = sx0, bx1, y, y + NEEDLE_BAND
              end
            else
              flushRun()
            end
          else
            flushRun()
          end
        else
          flushRun()
        end
        y = y + NEEDLE_BAND
      end
      flushRun()
      love.graphics.setScissor()
    end
  end
end

-- Decorations drawn behind the player (they receive lighting)
function overworld.drawDecor(camX, camY)
  require("src.airship").drawBack(camX, camY)
  local vx0, vy0 = camX - 8, camY - 8
  local vx1, vy1 = camX + config.VIRTUAL_W + 8, camY + config.VIRTUAL_H + 8
  -- Backdrop behind the ground, so holes, the mine shaft and the caves show
  -- earth and rock rather than sky. Its top follows the surface.
  -- (warm earth just under the ground, fading to the cave dark by 150 px down,
  -- so a hole dug near the surface is not black)
  -- (a column whose surface and gradient bands are all above the view is plain earth over the whole
  -- view: those are drawn together as one rectangle instead of six polygons each)
  local deepFrom
  for x = math.floor(vx0 / 8) * 8, vx1, 8 do
    local a, b = surface(x) + 4, surface(x + 8) + 4
    if math.abs(a - b) > 12 then
      a, b = math.max(a, b), math.max(a, b) -- a sheer step: stay under its lower side
    end
    local deep = math.max(a, b) + 4 * 30 + 31 < vy0
    if deep then
      deepFrom = deepFrom or x
    elseif deepFrom then
      love.graphics.setColor(EARTH)
      love.graphics.rectangle("fill", deepFrom, vy0, x - deepFrom, vy1 - vy0)
      deepFrom = nil
    end
    if not deep and math.min(a, b) < vy1 then
      love.graphics.setColor(EARTH)
      love.graphics.polygon("fill", x, a, x + 8, b, x + 8, vy1, x, vy1)
      for k = 0, 4 do
        local f = 1 - k / 5
        love.graphics.setColor(EARTH[1] + (EARTH_NEAR[1] - EARTH[1]) * f, EARTH[2] + (EARTH_NEAR[2] - EARTH[2]) * f, EARTH[3] + (EARTH_NEAR[3] - EARTH[3]) * f)
        love.graphics.polygon("fill", x, a + k * 30, x + 8, b + k * 30, x + 8, math.min(vy1, math.max(a, b) + k * 30 + 31), x, math.min(vy1, math.max(a, b) + k * 30 + 31))
      end
    end
  end
  if deepFrom then
    local x1 = math.floor(vx0 / 8) * 8
    while x1 <= vx1 do
      x1 = x1 + 8
    end
    love.graphics.setColor(EARTH)
    love.graphics.rectangle("fill", deepFrom, vy0, x1 - deepFrom, vy1 - vy0)
  end
  -- (above the caves: the earth fading into the cave dark; below, each area's own backdrop,
  -- with the next area's bleeding over it at the borders: src.depthblend)
  for y = math.max(math.floor(vy0 / 8) * 8, CAVE_TOP - 120), math.min(vy1, CAVE_TOP), 8 do
    love.graphics.setColor(backdrop(y, (vx0 + vx1) / 2))
    love.graphics.rectangle("fill", vx0, y, vx1 - vx0, 8)
  end
  drawMountainDepth(camX, camY, vx0, vy0, vx1, vy1)
  if vy1 > CAVE_TOP then
    local index = catacombs.levelAt((math.max(vy0, CAVE_TOP) + vy1) / 2, (vx0 + vx1) / 2) or 1
    depthblend.draw(index, camX, camY, vx0, vy0, vx1, vy1, CAVE_TOP)
    -- (the caves' far backgrounds at half brightness)
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", vx0, math.max(vy0, CAVE_TOP), vx1 - vx0, vy1 - math.max(vy0, CAVE_TOP))
  end
  catacombs.drawDecor(view(camX, camY))
  if vy0 > CAVE_TOP then
    return -- the rest is all on the surface
  end
  cullX0, cullX1 = vx0, vx1
  for _, tree in ipairs(trees) do
    if tree.x > vx0 - 40 and tree.x < vx1 + 40 then
      drawTree(tree)
    end
  end
  drawGroundClutter(vx0, vx1)
  drawBones()
  barrens.draw(vx0, vx1, surface)
  drawCamp()
  town.draw({ x = vx0, y = vy0, w = vx1 - vx0, h = vy1 - vy0 }, surface)
  drawRails(vx0, vx1)
  drawLanternPost(RAMP_X0 - 4)
  drawLanternPost(PIT_X0 - 8)
  for _, e in ipairs(catacombs.entries()) do
    if e.walk then
      drawLanternPost(e.x - 455)
    elseif not e.lake then
      drawLanternPost(e.x - e.half - 8)
      drawLanternPost(e.x + e.half + 8)
    end
  end
  drawWinchHouse()
  drawHeadframe()
  drawWeeds()
end

function overworld.drawLitDecor(v, shadows)
  catacombs.drawLitDecor(v, shadows)
end

-- The sign's lettering, at full resolution
function overworld.drawFront(camX, camY)
  catacombs.drawFront(view(camX, camY))
end

-- Each way down is named over its hole, the lettering fading in as the hunter
-- nears it and out as he walks off or drops in
local NAME_NEAR, NAME_FAR = 21, 90

local NAME_COLORS = {
  ["The Old Mine"] = { 0.95, 0.78, 0.5 },
  ["The Sunken Hollows"] = { 0.45, 0.9, 0.7 },
  ["The Sulfur Vents"] = { 0.95, 0.9, 0.35 },
  ["The Cinder Warrens"] = { 1, 0.5, 0.25 },
  ["The Drowned Halls"] = { 0.4, 0.7, 1 },
  ["The Quarry"] = { 0.8, 0.8, 0.85 },
  ["The Foreman's Hall"] = { 0.9, 0.62, 0.4 },
  ["The Flooded Caverns"] = { 0.35, 0.85, 0.95 },
  ["The Deep"] = { 0.7, 0.5, 1 },
  ["The Needle"] = { 0.85, 0.85, 1 },
  ["The Cloud Reaches"] = { 0.75, 0.9, 1 },
}

local function drawEntranceNames(toScreen, font, player)
  if not player or player.dead then
    return
  end
  local px, py = player:center()
  local spots = { { x = SHAFT_CX, y = PIT_Y - 30, name = catacombs.areaName(1) } }
  for _, e in ipairs(catacombs.namedEntries()) do
    local sy = e.walk and (e.y - 34) or (surface(e.x) - 30)
    if e.lake then
      for _, l in ipairs(lakes) do
        if e.x > l.x0 and e.x < l.x1 then
          sy = surface(e.x) + 195 -- (the lettering floats in the water right over the hole down)
        end
      end
    end
    spots[#spots + 1] = { x = e.walk and (e.x - 455) or e.x, y = sy, name = e.name, range = e.lake and 3 or 1 }
  end
  love.graphics.setFont(font)
  for _, s in ipairs(spots) do
    local d = math.sqrt((px - s.x) ^ 2 + (py - s.y) ^ 2)
    local rg = s.range or 1
    local a = math.max(0, math.min(1, (NAME_FAR * rg - d) / (NAME_FAR * rg - NAME_NEAR)))
    a = a * math.max(0, math.min(1, 1 - (py - s.y - 30) / 40)) -- (once he is down the hole it is gone)
    if a > 0.01 and s.name and s.name ~= "" then
      local sx, sy = toScreen(s.x, s.y)
      -- (larger lettering, with extra room between the letters)
      local big = require("src.fonts").get(math.floor(font:getHeight() * 1.27))
      local gap = math.floor(big:getHeight() * 0.28)
      local total = -gap
      for ch in s.name:gmatch(".") do
        total = total + big:getWidth(ch) + gap
      end
      local x, y = math.floor(sx - total / 2), math.floor(sy - big:getHeight() * 1.6)
      local c = NAME_COLORS[s.name] or { 1, 0.9, 0.7 }
      love.graphics.setFont(big)
      for pass = 1, 2 do
        local px = x
        for ch in s.name:gmatch(".") do
          if pass == 1 then
            love.graphics.setColor(0, 0, 0, 0.85 * a)
            love.graphics.print(ch, px + 2, y + 2)
          else
            love.graphics.setColor(c[1], c[2], c[3], a)
            love.graphics.print(ch, px, y)
          end
          px = px + big:getWidth(ch) + gap
        end
      end
      love.graphics.setFont(font)
    end
  end
end

function overworld.drawScreen(toScreen, font, player)
  catacombs.drawScreen(toScreen, font, player)
  drawEntranceNames(toScreen, font, player)
end

-- The last of the evening sun falling straight down the mine shaft: a warm
-- column of light that thins out with depth and breathes slowly
local function drawShaftLight(camY)
  local top, bottom = PIT_Y + 2, CAVE_TOP + 60
  if camY > bottom or camY + config.VIRTUAL_H < top then
    return
  end
  local t = love.timer.getTime()
  for y = top, bottom, 6 do
    local k = (y - top) / (bottom - top)
    local a = 0.17 * math.min(1, k * 12) * (1 - k) ^ 1.5 * (0.85 + 0.15 * math.sin(t * 0.8 + k * 5))
    love.graphics.setColor(1, 0.78, 0.45, a)
    love.graphics.rectangle("fill", SHAFT_X0, y, SHAFT_X1 - SHAFT_X0 + 1, 6)
  end
end

-- Flames glow regardless of the light level
function overworld.drawEmissive(camX, camY)
  drawShaftLight(camY)
  town.drawEmissive(view(camX, camY))
  catacombs.drawEmissive(view(camX, camY))
  for _, l in ipairs(lanterns()) do
    local lx, ly = l[1], l[2]
    love.graphics.setColor(1, 0.78, 0.38)
    love.graphics.rectangle("fill", lx - 1, ly + 1, 3, 5)
    love.graphics.setColor(1, 0.95, 0.75)
    love.graphics.rectangle("fill", lx, ly + 2, 1, 3)
  end
  -- The winch house's window, lit from inside
  local g = surface(WINCH_X + 18)
  love.graphics.setColor(1, 0.70, 0.32)
  love.graphics.rectangle("fill", WINCH_X + 8, g - 17, 7, 5)
  love.graphics.setColor(0.18, 0.13, 0.10)
  love.graphics.rectangle("fill", WINCH_X + 11, g - 17, 1, 5)
  -- Campfire flames: a few flickering tongues
  local cg = surface(CAMPFIRE_X)
  local t = love.timer.getTime()
  for i = -2, 2 do
    local h = 3 + math.floor((math.sin(t * 13 + i * 1.7) * 0.5 + 0.5) * 4) - math.abs(i)
    love.graphics.setColor(1, 0.55, 0.2)
    love.graphics.rectangle("fill", CAMPFIRE_X + i, cg - 2 - h, 1, h)
    love.graphics.setColor(1, 0.85, 0.45)
    love.graphics.rectangle("fill", CAMPFIRE_X + i, cg - 2 - math.max(1, h - 2), 1, math.max(1, h - 2))
  end
end

return overworld
