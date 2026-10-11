-- The whole world of a run, one seamless level with no loading screens.
-- On top, the Barrens: a hand-built desolate desert at dusk, the same every
-- run. The hunter starts on the left, passes crumbling ancient ruins with a
-- campfire, a mesa and a natural arch, and drops down the old mine shaft on
-- the right. Below lie the Catacombs, generated fresh each run
-- (scenes/catacombs.lua) in the background while the hunter is on the surface.
local catacombs = require("src.scenes.catacombs")
local config = require("src.config")
local hud = require("src.hud")
local materials = require("src.materials")
local props = require("src.props")
local shop = require("src.shop")
local targets = require("src.targets")
local World = require("src.world")

local SAND, SANDSTONE, WOOD, STONE, AIR =
  materials.SAND, materials.SANDSTONE, materials.WOOD, materials.STONEBRICK, materials.AIR

local overworld = {
  title = "The Barrens",
  subtitle = "Find the old mine",
  ambient = { 0.88, 0.76, 0.74 }, -- updated every frame: blends to the cave's as the hunter descends
}

local SURFACE_AMBIENT = { 0.88, 0.76, 0.74 } -- warm evening light
local CAVE_AMBIENT = { 0.36, 0.32, 0.44 } -- dim but readable (area 1; later areas have their own)

-- The surface's sandstone runs down to CAVE_TOP, where the first area begins;
-- the generated areas are stacked below it, each CAVE_HEIGHT tall
local WIDTH = 1920
local CAVE_TOP = 760
local CAVE_HEIGHT = 3680
local AREAS = 2
local HEIGHT = CAVE_TOP + AREAS * CAVE_HEIGHT

-- Mine shaft: from the headframe down into the catacombs' entrance chamber
local SHAFT_X0, SHAFT_X1 = 1616, 1654
local SHAFT_BOTTOM = CAVE_TOP - 20 -- the cave generator carries it on from here
local ENTRANCE_Y = CAVE_TOP + 96

-- Cave generation time per frame while on the surface (seconds)
local GEN_BUDGET = 0.009

local CAMPFIRE_X = 668
local SUN_X, SUN_Y = 440, 196 -- on screen, low over the horizon

local background -- pre-rendered sky and parallax layers
local trees = {}
local mineGround

local function surface(x)
  return math.floor(509 + math.sin(x * 0.0075) * 13 + math.sin(x * 0.023 + 1) * 5)
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

local function canyonWall(world, x0, x1, fromLeft)
  for x = x0, x1 do
    local t = fromLeft and (x - x0) / (x1 - x0) or (x1 - x) / (x1 - x0)
    local top = math.floor(64 + t * t * 384 + love.math.noise(x * 0.125, 5) * 16)
    world:fillRect(x, top, x, CAVE_TOP, SANDSTONE)
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

local function buildRuins(world)
  pillar(world, 588, 9, 52)
  pillar(world, 626, 8, 20)
  pillar(world, 720, 9, 62)
  -- Lintel fragment still resting on the tall pillar
  world:fillRect(706, surface(720) - 70, 742, surface(720) - 66, STONE)
  -- Low wall remnant with a crumbled top
  for x = 600, 700 do
    if x < CAMPFIRE_X - 14 or x > CAMPFIRE_X + 14 then
      local top = surface(x) - 4 - math.floor(love.math.noise(x * 0.2, 4) * 8)
      world:fillRect(x, top, x, surface(x) + 2, STONE)
    end
  end
  -- Fallen column, half sunk in the sand
  for x = 748, 800 do
    local g = surface(x)
    world:fillRect(x, g - 6, x, g + 2, STONE)
  end
end

-- Weathered timber headframe over the mine shaft
local function buildMine(world)
  local groundY = surface((SHAFT_X0 + SHAFT_X1) / 2)
  mineGround = groundY
  world:fillRect(SHAFT_X0, groundY - 19, SHAFT_X1, SHAFT_BOTTOM, AIR)
  world:fillRect(SHAFT_X0 - 3, groundY, SHAFT_X0 - 1, SHAFT_BOTTOM, WOOD)
  world:fillRect(SHAFT_X1 + 1, groundY, SHAFT_X1 + 3, SHAFT_BOTTOM, WOOD)
  -- Only the right leg, its brace and the crossbeam are solid. The left leg
  -- and brace are drawn as scenery (drawDecor), so the hunter coming from
  -- the left can walk straight into the shaft.
  local frameTop = groundY - 74
  world:fillRect(SHAFT_X1 + 3, frameTop, SHAFT_X1 + 7, groundY, WOOD)
  world:fillRect(SHAFT_X0 - 13, frameTop, SHAFT_X1 + 13, frameTop + 4, WOOD)
  for i = 0, 29 do
    world:fillRect(SHAFT_X1 + 6 + i, groundY - 29 + i, SHAFT_X1 + 7 + i, groundY - 28 + i, WOOD)
  end
end

-- The headframe's left leg and brace, drawn behind the hunter
local function drawOpenSide()
  local groundY, frameTop = mineGround, mineGround - 74
  local c = materials.defs[WOOD].color
  love.graphics.setColor(c[1] * 0.8, c[2] * 0.8, c[3] * 0.8)
  love.graphics.rectangle("fill", SHAFT_X0 - 7, frameTop + 5, 5, groundY - frameTop - 4)
  for i = 0, 29 do
    love.graphics.rectangle("fill", SHAFT_X0 - 7 - i, groundY - 29 + i, 2, 2)
  end
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
        sky:setPixel(x, y, math.min(1, r + glow), math.min(1, g + glow * 0.6), math.min(1, b + glow * 0.3), 1)
      end
    end
  end
  -- A few early stars, high up where the sky is darkest
  for _ = 1, 60 do
    local x, y = rng:random(0, W - 1), math.floor(rng:random() ^ 2 * H * 0.3)
    local s = 0.45 + rng:random() * 0.3
    sky:setPixel(x, y, s, s * 0.95, s, 1)
  end

  -- Mesa silhouettes, wider than the screen so they scroll with parallax
  local function layer(parallax, baseY, color, seed)
    local w = math.ceil(W + (WIDTH - W) * parallax) + 2
    local img = love.image.newImageData(w, H)
    for x = 0, w - 1 do
      local n = love.math.noise(x * 0.005, seed)
      local mesaTop = n > 0.55 and baseY - 80 - math.floor((n - 0.55) * 128) or baseY
      local top = mesaTop + math.floor(love.math.noise(x * 0.031, seed + 1) * 10)
      for y = math.max(0, top), H - 1 do
        img:setPixel(x, y, color[1], color[2], color[3], 1)
      end
    end
    return { image = love.graphics.newImage(img), parallax = parallax, color = color }
  end

  return {
    sky = love.graphics.newImage(sky),
    layers = {
      layer(0.15, 304, { 0.40, 0.22, 0.30 }, 11),
      layer(0.35, 344, { 0.26, 0.14, 0.20 }, 23),
    },
  }
end

local seed

-- opts.seed: cave seed (default random). opts.atCave: start in the
-- catacombs' entrance chamber instead of on the surface (generates at once).
function overworld.build(opts)
  local world = World.new(WIDTH, HEIGHT)
  seed = (opts and opts.seed) or math.floor(love.math.random() * 1000000)

  -- Sand over sandstone (the cave generator replaces what lies below CAVE_TOP)
  for x = 0, WIDTH - 1 do
    local top = surface(x)
    local depth = 16 + math.floor(love.math.noise(x * 0.031, 3) * 10)
    world:fillRect(x, top, x, top + depth, SAND)
    world:fillRect(x, top + depth + 1, x, CAVE_TOP + 40, SANDSTONE)
  end

  canyonWall(world, 0, 64, false)
  canyonWall(world, WIDTH - 65, WIDTH - 1, true)
  buildRuins(world)
  mesa(world, 960, 1088, 314, 8)
  -- Natural arch
  mesa(world, 1232, 1264, 381, 3)
  mesa(world, 1376, 1408, 381, 3)
  for x = 1232, 1408 do
    local arch = math.floor(math.sin((x - 1232) / 176 * math.pi) * 16)
    world:fillRect(x, 381, x, 406 - arch, SANDSTONE)
  end
  buildMine(world)
  -- Only the surface is painted now; the cave paints itself as it generates
  world:repaintRect(0, 0, WIDTH - 1, CAVE_TOP + 40)

  background = background or buildBackground()
  trees = {}
  for _, t in ipairs({ { 205, 1 }, { 470, -1 }, { 880, 1 }, { 1130, -1 }, { 1500, 1 }, { 1790, -1 } }) do
    trees[#trees + 1] = { x = t[1], y = world:findGround(t[1], 160), lean = t[2], height = 46 + (t[1] % 17) }
  end

  -- Shooting a shop hatch's chain makes sure the area below it exists first
  shop.onHatchBreak = function(level)
    catacombs.finish(level + 1)
  end
  catacombs.start(world, {
    x0 = 0,
    y0 = CAVE_TOP,
    x1 = WIDTH - 1,
    y1 = CAVE_TOP + CAVE_HEIGHT - 1,
    entranceX = math.floor((SHAFT_X0 + SHAFT_X1) / 2),
    entranceY = ENTRANCE_Y,
    shaftX0 = SHAFT_X0,
    shaftX1 = SHAFT_X1,
  }, seed, AREAS)
  if opts and opts.atCave then
    catacombs.finish(1)
    local info = catacombs.info()
    return world, info.spawnX, info.spawnY
  end

  local spawnX = 336
  return world, spawnX, world:findGroundUnder(spawnX, config.player.width, 160) - config.player.height
end

-- Called once physics exists; the cave adds its own crates when generated
function overworld.populate(world)
  targets.clear()
  props.clear()
  catacombs.spawnProps()
  -- A little practice range near the start
  for _, x in ipairs({ 400, 435 }) do
    targets.addDummy(x, world:findGround(x, 160))
  end
  for i, x in ipairs({ 467, 481, 495 }) do
    props.spawn("crate", x, world:findGround(x, 160) - 7)
    if i < 3 then
      props.spawn("crate", x + 7, world:findGround(x, 160) - 20)
    end
  end
  props.spawn("ironCrate", 1018, world:findGround(1018, 160) - 8.5)
  props.spawn("crate", 1320, world:findGround(1320, 160) - 7)
end

local smokeTimer = 0

-- How far underground a point is: 0 on the surface, 1 well inside the rock
local function underground(x, y)
  return math.max(0, math.min(1, (y - surface(x) - 24) / 220))
end

-- The same, for the game's sound mixer
function overworld.undergroundFactor(x, y)
  return underground(x, y)
end

-- Campfire smoke, cave generation in the background, and the light and
-- banners changing as the hunter goes underground
function overworld.update(dt, player, game, effects)
  smokeTimer = smokeTimer - dt
  if smokeTimer <= 0 and effects then
    smokeTimer = 0.12
    local g = 0.32 + love.math.random() * 0.1
    effects.particle(CAMPFIRE_X + (love.math.random() - 0.5) * 4, surface(CAMPFIRE_X) - 6, (love.math.random() - 0.3) * 8, -18, 2.2, { g, g * 0.95, g }, -6)
  end

  local px, py = player:center()
  -- An area must be complete before the hunter can get anywhere near it
  if not catacombs.ready() and py > surface(px) + 12 then
    catacombs.finish(1)
  else
    catacombs.step(GEN_BUDGET)
  end
  catacombs.ensure(py)
  catacombs.update(player)

  -- The light blends from the surface to the ambient of the area the hunter is in
  local t = underground(px, py)
  local cave = catacombs.theme(catacombs.levelAt(py) or 1).ambient
  for i = 1, 3 do
    overworld.ambient[i] = SURFACE_AMBIENT[i] + (cave[i] - SURFACE_AMBIENT[i]) * t
  end
end

local function flicker(seed)
  local t = love.timer.getTime()
  return math.sin(t * 9 + seed) * 0.5 + math.sin(t * 23 + seed * 2) * 0.5
end

local function lanternPos()
  return math.floor((SHAFT_X0 + SHAFT_X1) / 2), mineGround - 64
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
  local lx, ly = lanternPos()
  lighting.add(lx, ly + 4, 80, 1, 0.7, 0.35, 0.7 + flicker(1) * 0.08)
  lighting.add(CAMPFIRE_X, surface(CAMPFIRE_X) - 5, 110, 1, 0.6, 0.3, 0.85 + flicker(2) * 0.12)
end

function overworld.drawBackground(camX, camY)
  if camY > CAVE_TOP - 200 then
    return -- the view is all underground; the backdrop (drawDecor) covers it
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(background.sky, 0, 0)
  for _, l in ipairs(background.layers) do
    local oy = -math.floor(camY * l.parallax * 0.5)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(l.image, -math.floor(camX * l.parallax), oy)
    -- When the camera is high the layer scrolls up; keep its base filled
    local bottom = oy + l.image:getHeight()
    if bottom < config.VIRTUAL_H then
      love.graphics.setColor(l.color)
      love.graphics.rectangle("fill", 0, bottom, config.VIRTUAL_W, config.VIRTUAL_H - bottom)
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

local EARTH = { 0.10, 0.07, 0.07 }
local CAVE_BACK = { 0.10, 0.08, 0.14 }
local CAVE_DEEP_BACK = { 0.06, 0.05, 0.09 }

-- Colour of the backdrop behind the terrain at a depth: dark earth under the
-- surface, turning to the catacombs' cold gloom, darker the deeper you go
local function backdrop(y)
  if y < CAVE_TOP then
    return lerpColor(EARTH, CAVE_BACK, math.max(0, (y - (CAVE_TOP - 120)) / 120))
  end
  return catacombs.backdrop(y)
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
    if math.min(a, b) < vy1 then
      love.graphics.polygon("fill", x, a, x + 8, b, x + 8, vy1, x, vy1)
    end
  end
  for y = math.max(math.floor(vy0 / 8) * 8, CAVE_TOP - 120), vy1, 8 do
    love.graphics.setColor(backdrop(y))
    love.graphics.rectangle("fill", vx0, y, vx1 - vx0, 8)
  end
  catacombs.drawDecor(view(camX, camY))
  for _, tree in ipairs(trees) do
    drawTree(tree)
  end
  drawOpenSide()
  -- Pulley wheel and rope on the headframe, with a lantern hanging from the beam
  local cx = math.floor((SHAFT_X0 + SHAFT_X1) / 2)
  love.graphics.setColor(0.22, 0.17, 0.14)
  love.graphics.circle("line", cx + 0.5, mineGround - 82 + 0.5, 6)
  love.graphics.line(cx + 6.5, mineGround - 76, cx + 6.5, mineGround + 32)
  local lx, ly = lanternPos()
  love.graphics.setColor(0.14, 0.12, 0.12)
  love.graphics.rectangle("fill", lx, mineGround - 70, 1, 6)
  love.graphics.rectangle("fill", lx - 2, ly - 1, 5, 1)
  love.graphics.rectangle("fill", lx - 2, ly + 7, 5, 1)
  love.graphics.rectangle("fill", lx - 2, ly, 1, 7)
  love.graphics.rectangle("fill", lx + 2, ly, 1, 7)
  -- Campfire: a ring of stones and crossed logs
  local g = surface(CAMPFIRE_X)
  love.graphics.setColor(0.36, 0.33, 0.34)
  for _, dx in ipairs({ -7, -5, 5, 7 }) do
    love.graphics.rectangle("fill", CAMPFIRE_X + dx, g - 2, 2, 2)
  end
  love.graphics.setColor(0.28, 0.18, 0.12)
  love.graphics.line(CAMPFIRE_X - 5.5, g - 0.5, CAMPFIRE_X + 4.5, g - 3.5)
  love.graphics.line(CAMPFIRE_X - 4.5, g - 3.5, CAMPFIRE_X + 5.5, g - 0.5)
end

function overworld.drawScreen(toScreen, font)
  catacombs.drawScreen(toScreen, font)
end

-- Flames glow regardless of the light level
function overworld.drawEmissive(camX, camY)
  catacombs.drawEmissive(view(camX, camY))
  local lx, ly = lanternPos()
  love.graphics.setColor(1, 0.78, 0.38)
  love.graphics.rectangle("fill", lx - 1, ly + 1, 3, 5)
  love.graphics.setColor(1, 0.95, 0.75)
  love.graphics.rectangle("fill", lx, ly + 2, 1, 3)
  -- Campfire flames: a few flickering tongues
  local g = surface(CAMPFIRE_X)
  local t = love.timer.getTime()
  for i = -2, 2 do
    local h = 3 + math.floor((math.sin(t * 13 + i * 1.7) * 0.5 + 0.5) * 4) - math.abs(i)
    love.graphics.setColor(1, 0.55, 0.2)
    love.graphics.rectangle("fill", CAMPFIRE_X + i, g - 2 - h, 1, h)
    love.graphics.setColor(1, 0.85, 0.45)
    love.graphics.rectangle("fill", CAMPFIRE_X + i, g - 2 - math.max(1, h - 2), 1, math.max(1, h - 2))
  end
end

return overworld
