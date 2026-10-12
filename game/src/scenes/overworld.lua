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
local props = require("src.props")
local shop = require("src.shop")
local targets = require("src.targets")
local World = require("src.world")

local SAND, SANDSTONE, WOOD, STONE, AIR, TAILINGS =
  materials.SAND, materials.SANDSTONE, materials.WOOD, materials.STONEBRICK, materials.AIR, materials.TAILINGS

local overworld = {
  title = "The Barrens",
  subtitle = "Find the old mine",
  ambient = { 0.88, 0.76, 0.74 }, -- updated every frame: blends to the cave's as the hunter descends
}

local SURFACE_AMBIENT = { 0.88, 0.76, 0.74 } -- warm evening light

-- The surface's sandstone runs down to CAVE_TOP, where the first area begins;
-- the generated areas are stacked below it, each CAVE_HEIGHT tall
local WIDTH = 2880
local CAVE_TOP = 760
local CAVE_HEIGHT = 3100
local AREAS = 4 -- rows of areas: three in a column, then the two side by side
local POND_X0, POND_X1 = 1318, 1378 -- an oasis pond between the bones and the ramp
local HEIGHT = CAVE_TOP + AREAS * CAVE_HEIGHT

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

-- Cave generation time per frame (seconds), spent even while paused, so the
-- title screen gets a head start on the first area
local GEN_BUDGET = 0.010

local SPAWN_X = 990
local CAMPFIRE_X = 1032
local TENT_X = 930
local WINCH_X = 1758 -- left edge of the winch house
local SUN_X, SUN_Y = 440, 196 -- on screen, low over the horizon

local background -- pre-rendered sky and parallax layers
local trees = {}

-- Gently rolling ground of the open plain
local function plain(x)
  return 509 + math.sin(x * 0.0058) * 8 + math.sin(x * 0.017 + 1) * 4 + math.sin(x * 0.043 + 2) * 1.5
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

local function buildBackground()
  local W, H = config.VIRTUAL_W, config.VIRTUAL_H
  local rng = love.math.newRandomGenerator(7)
  local sky = love.image.newImageData(W, H)
  for y = 0, H - 1 do
    local r, g, b = skyColor(y / (H - 1))
    for x = 0, W - 1 do
      local dx, dy = x - SUN_X, y - SUN_Y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < 30 then
        local core = 1 - d / 30 * 0.12
        sky:setPixel(x, y, 1, 0.74 * core, 0.44 * core, 1) -- the setting sun
      else
        local glow = math.max(0, 1 - d / 220) ^ 2 * 0.45
        local cr, cg, cb = math.min(1, r + glow), math.min(1, g + glow * 0.6), math.min(1, b + glow * 0.3)
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

-- opts.seed: cave seed (default random). opts.atCave: start in the
-- catacombs' entrance chamber instead of on the surface (generates at once).
function overworld.build(opts)
  local world = World.new(WIDTH, HEIGHT)
  seed = (opts and opts.seed) or math.floor(love.math.random() * 1000000)

  -- Sand over sandstone (the cave generator replaces what lies below
  -- CAVE_TOP); the pit floor is trodden spoil
  for x = 0, WIDTH - 1 do
    local top = surface(x)
    local depth = 16 + math.floor(love.math.noise(x * 0.031, 3) * 10)
    local inPit = x >= PIT_X0 - 20 and x <= PIT_X1
    world:fillRect(x, top, x, top + depth, inPit and TAILINGS or SAND)
    world:fillRect(x, top + depth + 1, x, CAVE_TOP + 40, SANDSTONE)
  end

  canyonWall(world, 0, 120, true)
  canyonWall(world, WIDTH - 121, WIDTH - 1, false)
  -- West: badlands
  boulder(world, 168, 9)
  mesa(world, 250, 460, 352, 9)
  -- Natural arch
  mesa(world, 560, 592, 404, 3)
  mesa(world, 708, 740, 404, 3)
  for x = 560, 740 do
    local arch = math.floor(math.sin((x - 560) / 180 * math.pi) * 16)
    world:fillRect(x, 404, x, 429 - arch, SANDSTONE)
  end
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
  -- Only the surface is painted now; the cave paints itself as it generates
  world:repaintRect(0, 0, WIDTH - 1, CAVE_TOP + 40)

  background = background or buildBackground()
  trees = {}
  for _, t in ipairs({ { 200, 1 }, { 520, -1 }, { 790, 1 }, { 1340, -1 }, { 2000, 1 }, { 2460, -1 }, { 2706, 1 } }) do
    trees[#trees + 1] = { x = t[1], y = world:findGround(t[1], 160), lean = t[2], height = 46 + (t[1] % 17) }
  end

  -- Shooting a shop hatch's chain makes sure the area below it exists first
  shop.onHatchBreak = function(child)
    catacombs.finish(child)
  end
  catacombs.start(world, {
    x0 = 0,
    y0 = CAVE_TOP,
    x1 = WIDTH - 1,
    y1 = CAVE_TOP + CAVE_HEIGHT - 1,
    entranceX = SHAFT_CX,
    entranceY = ENTRANCE_Y,
    shaftX0 = SHAFT_X0,
    shaftX1 = SHAFT_X1,
  }, seed, AREAS)
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

-- Called once physics exists; the cave adds its own crates when generated
function overworld.populate(world)
  targets.clear()
  props.clear()
  catacombs.spawnProps()
  fluids.fillWater(world, POND_X0 + 1, POND_X1 - 1, math.floor(plain(POND_X0 - 4)) + 2)
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
  props.spawn("crate", 1064, ground(1064) - 7)
  props.spawn("crate", 1700, ground(1700) - 7)
  props.spawn("ironCrate", 2335, ground(2335) - 8.5)
  -- Pots, pouches and lamps along the plain, by the camp and the ruins
  for _, o in ipairs({
    { "urn", 640 }, { "urn", 1180 }, { "urn", 2040 }, { "urn", 2480 },
    { "pouch", 780 }, { "pouch", 972 }, { "pouch", 1560 - 120 }, { "pouch", 2210 },
    { "lantern", 888 }, { "lantern", 1250 }, { "lantern", 2370 },
    { "skullCandle", 420 }, { "skullCandle", 2150 },
    { "emberPot", 1010 }, { "emberPot", 1880 }, { "emberPot", 2600 },
  }) do
    local def = props.defs[o[1]]
    props.spawn(o[1], o[2], ground(o[2]) - def.height / 2 - 0.5)
  end
  -- Something for whoever explores: a chest on top of the west mesa and one
  -- under the ruins' gateway
  chests.spawn(356, ground(356), 0.25)
  chests.spawn(2390, world:findGround(2390, surface(2390) - 30), 0.25)
end

-- How far underground a point is: 0 on the surface, 1 well inside the rock
local function underground(x, y)
  return math.max(0, math.min(1, (y - surface(x) - 24) / 220))
end

-- The same, for the game's sound mixer
function overworld.undergroundFactor(x, y)
  return underground(x, y)
end

-- Tumbleweeds roll across the plain on the wind, near the hunter
local weeds = {}

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
    if w.x < px - 420 or w.x < 130 or w.y > 640 then
      table.remove(weeds, i)
    end
  end
end

local smokeTimer, dustTimer, moteTimer = 0, 0, 0

-- Generates the areas below a slice at a time, every frame (see GEN_BUDGET)
function overworld.background()
  catacombs.step(GEN_BUDGET)
end

-- Campfire smoke, blowing dust, tumbleweeds, and the light and banners
-- changing as the hunter goes underground
function overworld.update(dt, player, game, effects)
  local px, py = player:center()
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
  catacombs.ensure(py)
  catacombs.update(player, dt)

  -- The light blends from the surface to the ambient of the area the hunter is in
  local t = underground(px, py)
  local cave = catacombs.theme(catacombs.levelAt(py, px) or 1).ambient
  for i = 1, 3 do
    overworld.ambient[i] = SURFACE_AMBIENT[i] + (cave[i] - SURFACE_AMBIENT[i]) * t
  end
end

local function flicker(seed)
  local t = love.timer.getTime()
  return math.sin(t * 9 + seed) * 0.5 + math.sin(t * 23 + seed * 2) * 0.5
end

-- Lanterns: { x, y } of each flame (the headframe's, two posts by the ramp,
-- and the one by the tent)
local function lanterns()
  return {
    { SHAFT_CX - 12, FRAME_TOP + 20 },
    { RAMP_X0 - 4, surface(RAMP_X0 - 4) - 22 },
    { PIT_X0 - 8, surface(PIT_X0 - 8) - 22 },
    { TENT_X - 26, surface(TENT_X - 26) - 22 },
  }
end

local function view(camX, camY)
  return { x = camX, y = camY, w = config.VIRTUAL_W, h = config.VIRTUAL_H }
end

function overworld.addLights(lighting, camX, camY)
  -- Low warm light from the setting sun's place in the sky, fading underground
  local sunlight = 1 - underground(camX + config.VIRTUAL_W / 2, camY + config.VIRTUAL_H / 2)
  if sunlight > 0 then
    lighting.add(camX + SUN_X, camY + SUN_Y, 420, 1, 0.62, 0.38, 0.3 * sunlight)
  end
  catacombs.addLights(lighting, view(camX, camY))
  for i, l in ipairs(lanterns()) do
    lighting.add(l[1], l[2] + 4, 80, 1, 0.7, 0.35, 0.7 + flicker(i) * 0.08)
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

function overworld.drawBackground(camX, camY)
  if camY > CAVE_TOP - 200 then
    return -- the view is all underground; the backdrop (drawDecor) covers it
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(background.sky, 0, 0)
  for i, l in ipairs(background.layers) do
    local oy = -math.floor(camY * l.parallax * 0.5)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(l.image, -math.floor(camX * l.parallax), oy)
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

-- The headframe over the shaft: two leaning legs, crossbeams and braces, a
-- back-brace down to the step, the sheave wheel on top, and the hoist rope
-- running down the shaft and over to the winch house
local function drawHeadframe()
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
  local x0 = 1228
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
  local tx, tg = 478, surface(478)
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
    if x > 125 and x < WIDTH - 125 and (x < PIT_X0 - 20 or x > PIT_X1 + STEP_W + 4) then
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
  love.graphics.setColor(0.56, 0.45, 0.30)
  for _, w in ipairs(weeds) do
    local x, y = math.floor(w.x), math.floor(w.y)
    love.graphics.circle("line", x + 0.5, y + 0.5, w.r)
    for k = 0, 1 do
      local a = w.spin + k * math.pi / 2
      love.graphics.line(x + 0.5 - math.cos(a) * w.r, y + 0.5 - math.sin(a) * w.r, x + 0.5 + math.cos(a) * w.r, y + 0.5 + math.sin(a) * w.r)
    end
  end
end

local EARTH = { 0.10, 0.07, 0.07 }
local CAVE_BACK = { 0.10, 0.08, 0.14 }

-- Colour of the backdrop behind the terrain at a depth: dark earth under the
-- surface, turning to the catacombs' cold gloom, darker the deeper you go
local function backdrop(y, x)
  if y < CAVE_TOP then
    return lerpColor(EARTH, CAVE_BACK, math.max(0, (y - (CAVE_TOP - 120)) / 120))
  end
  return catacombs.backdrop(y, x)
end

-- Far rock in the caves: two layers of pillars that slide past more slowly
-- than the near terrain, so the open caverns have depth. Coloured for the
-- area in view.
local function drawCaveDepth(camX, vx0, vx1, vy0, vy1)
  local colors = catacombs.theme(catacombs.levelAt((vy0 + vy1) / 2, (vx0 + vx1) / 2) or 1).pillars
  for layer = 1, 2 do
    local p = layer == 1 and 0.55 or 0.78
    local spacing = layer == 1 and 74 or 48
    local alpha = layer == 1 and 0.5 or 0.38
    local off = camX * (1 - p)
    for i = math.floor((vx0 - off) / spacing) - 1, math.floor((vx1 - off) / spacing) + 1 do
      local h = hash(i, layer)
      local w = (layer == 1 and 10 or 6) + math.floor(h * 14)
      local x = math.floor(i * spacing + off + hash(i, layer + 7) * spacing * 0.6)
      local c = colors[1]
      love.graphics.setColor(c[1], c[2], c[3], alpha)
      love.graphics.rectangle("fill", x, vy0, w, vy1 - vy0)
      -- A rim light down one edge, and cracks across the face
      c = colors[2]
      love.graphics.setColor(c[1], c[2], c[3], alpha * 0.8)
      love.graphics.rectangle("fill", x, vy0, 1, vy1 - vy0)
      c = colors[3]
      for k = 1, 3 do
        local cy = math.floor(vy0 / 40) * 40 + k * 40 + math.floor(hash(i, k) * 30)
        love.graphics.setColor(c[1], c[2], c[3], alpha * 0.7)
        love.graphics.rectangle("fill", x + 1 + math.floor(hash(k, i) * (w - 3)), cy, 2, 5)
      end
    end
  end
end

-- Decorations drawn behind the player (they receive lighting)
function overworld.drawDecor(camX, camY)
  local vx0, vy0 = camX - 8, camY - 8
  local vx1, vy1 = camX + config.VIRTUAL_W + 8, camY + config.VIRTUAL_H + 8
  -- Backdrop behind the ground, so holes, the mine shaft and the caves show
  -- earth and rock rather than sky. Its top follows the surface.
  love.graphics.setColor(EARTH)
  for x = math.floor(vx0 / 8) * 8, vx1, 8 do
    local a, b = surface(x) + 4, surface(x + 8) + 4
    if math.abs(a - b) > 12 then
      a, b = math.max(a, b), math.max(a, b) -- a sheer step: stay under its lower side
    end
    if math.min(a, b) < vy1 then
      love.graphics.polygon("fill", x, a, x + 8, b, x + 8, vy1, x, vy1)
    end
  end
  for y = math.max(math.floor(vy0 / 8) * 8, CAVE_TOP - 120), vy1, 8 do
    love.graphics.setColor(backdrop(y, (vx0 + vx1) / 2))
    love.graphics.rectangle("fill", vx0, y, vx1 - vx0, 8)
  end
  if vy1 > CAVE_TOP then
    drawCaveDepth(camX, vx0, vx1, math.max(vy0, CAVE_TOP), vy1)
  end
  catacombs.drawDecor(view(camX, camY))
  if vy0 > CAVE_TOP then
    return -- the rest is all on the surface
  end
  for _, tree in ipairs(trees) do
    if tree.x > vx0 - 40 and tree.x < vx1 + 40 then
      drawTree(tree)
    end
  end
  drawGroundClutter(vx0, vx1)
  drawBones()
  drawCamp()
  drawRails(vx0, vx1)
  drawLanternPost(RAMP_X0 - 4)
  drawLanternPost(PIT_X0 - 8)
  drawWinchHouse()
  drawHeadframe()
  drawWeeds()
end

-- The sign's lettering, at full resolution
function overworld.drawFront(camX, camY)
  catacombs.drawFront(view(camX, camY))
end

function overworld.drawScreen(toScreen, font)
  catacombs.drawScreen(toScreen, font)
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
