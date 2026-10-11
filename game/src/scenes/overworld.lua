-- The Badlands: hand-built desert canyon surface. Same every run. The player
-- starts on the left and drops down the old mine shaft on the right to enter
-- the dungeon.
local config = require("src.config")
local materials = require("src.materials")
local props = require("src.props")
local targets = require("src.targets")
local World = require("src.world")

local SAND, SANDSTONE, BEDROCK, WOOD, AIR =
  materials.SAND, materials.SANDSTONE, materials.BEDROCK, materials.WOOD, materials.AIR

local overworld = {
  title = "The Badlands",
  subtitle = "Find the old mine",
}

local WIDTH, HEIGHT = 1200, 640 -- deep enough that the camera never sees past the bottom
local FLOOR = 6 -- bedrock rows at the bottom

-- Mine shaft
local SHAFT_X0, SHAFT_X1 = 1010, 1034
local SHAFT_BOTTOM = 413

local background -- pre-rendered sky and parallax layers
local cacti = {}

local function surface(x)
  return math.floor(318 + math.sin(x * 0.012) * 8 + math.sin(x * 0.037 + 1) * 3)
end

-- Sandstone shape from a list of {x, topY} control points (flat-topped mesa
-- with slightly sloped sides)
local function mesa(world, x0, x1, top, slope)
  for x = x0, x1 do
    local edge = math.min(x - x0, x1 - x)
    local y = top + math.max(0, (slope - edge)) * 3
    local jag = math.floor(love.math.noise(x * 0.3, top) * 3)
    world:fillRect(x, y + jag, x, surface(x) + 2, SANDSTONE)
  end
end

local function canyonWall(world, x0, x1, fromLeft)
  for x = x0, x1 do
    local t = fromLeft and (x - x0) / (x1 - x0) or (x1 - x) / (x1 - x0)
    local top = math.floor(40 + t * t * 240 + love.math.noise(x * 0.2, 5) * 10)
    world:fillRect(x, top, x, HEIGHT - 1, SANDSTONE)
  end
end

local function buildBackground()
  local W, H = config.VIRTUAL_W, config.VIRTUAL_H
  local sky = love.image.newImageData(W, H)
  for y = 0, H - 1 do
    local t = y / (H - 1)
    -- Deep blue at the top to a hot orange near the horizon
    local r = 0.22 + t * 0.75
    local g = 0.30 + t * 0.32
    local b = 0.62 - t * 0.38
    for x = 0, W - 1 do
      local dx, dy = x - 380, y - 70
      local d = math.sqrt(dx * dx + dy * dy)
      if d < 16 then
        sky:setPixel(x, y, 1, 0.95, 0.75, 1) -- sun
      else
        local glow = math.max(0, 1 - d / 120) * 0.25
        sky:setPixel(x, y, math.min(1, r + glow), math.min(1, g + glow * 0.8), b, 1)
      end
    end
  end

  -- Mesa silhouettes: wider than the screen so they can scroll with parallax
  local function layer(parallax, baseY, color, seed)
    local w = math.ceil(W + (WIDTH - W) * parallax) + 2
    local img = love.image.newImageData(w, H)
    for x = 0, w - 1 do
      local n = love.math.noise(x * 0.008, seed)
      local mesaTop = n > 0.55 and baseY - 50 - math.floor((n - 0.55) * 80) or baseY
      local top = mesaTop + math.floor(love.math.noise(x * 0.05, seed + 1) * 6)
      for y = math.max(0, top), H - 1 do
        img:setPixel(x, y, color[1], color[2], color[3], 1)
      end
    end
    return { image = love.graphics.newImage(img), parallax = parallax }
  end

  return {
    sky = love.graphics.newImage(sky),
    layers = {
      layer(0.15, 190, { 0.55, 0.34, 0.42 }, 11),
      layer(0.35, 215, { 0.62, 0.30, 0.26 }, 23),
    },
  }
end

function overworld.build()
  local world = World.new(WIDTH, HEIGHT)

  -- Sand over sandstone
  for x = 0, WIDTH - 1 do
    local top = surface(x)
    world:fillRect(x, top, x, top + 10 + math.floor(love.math.noise(x * 0.05, 3) * 6), SAND)
    world:fillRect(x, top + 11 + math.floor(love.math.noise(x * 0.05, 3) * 6), x, HEIGHT - 1, SANDSTONE)
  end

  canyonWall(world, 0, 40, false)
  canyonWall(world, WIDTH - 41, WIDTH - 1, true)
  mesa(world, 330, 450, 232, 8)
  mesa(world, 600, 680, 196, 5)
  -- Natural arch
  mesa(world, 770, 790, 238, 2)
  mesa(world, 860, 880, 238, 2)
  for x = 770, 880 do
    local arch = math.floor(math.sin((x - 770) / 110 * math.pi) * 10)
    world:fillRect(x, 238, x, 254 - arch, SANDSTONE)
  end

  -- Mine shaft, timber-lined, down to the bedrock
  local groundY = surface((SHAFT_X0 + SHAFT_X1) / 2)
  world:fillRect(SHAFT_X0, groundY - 12, SHAFT_X1, SHAFT_BOTTOM, AIR)
  world:fillRect(SHAFT_X0 - 2, groundY, SHAFT_X0 - 1, SHAFT_BOTTOM, WOOD)
  world:fillRect(SHAFT_X1 + 1, groundY, SHAFT_X1 + 2, SHAFT_BOTTOM, WOOD)
  -- Headframe: two posts, a crossbeam, and braces
  local frameTop = groundY - 46
  world:fillRect(SHAFT_X0 - 4, frameTop, SHAFT_X0 - 2, groundY, WOOD)
  world:fillRect(SHAFT_X1 + 2, frameTop, SHAFT_X1 + 4, groundY, WOOD)
  world:fillRect(SHAFT_X0 - 8, frameTop, SHAFT_X1 + 8, frameTop + 3, WOOD)
  for i = 0, 18 do
    world:fillRect(SHAFT_X0 - 4 - i, groundY - 18 + i, SHAFT_X0 - 3 - i, groundY - 17 + i, WOOD)
    world:fillRect(SHAFT_X1 + 3 + i, groundY - 18 + i, SHAFT_X1 + 4 + i, groundY - 17 + i, WOOD)
  end

  world:fillRect(0, HEIGHT - FLOOR, WIDTH - 1, HEIGHT - 1, BEDROCK)
  world:repaintAll()

  background = background or buildBackground()
  cacti = {}
  for _, x in ipairs({ 120, 260, 300, 520, 730, 940, 1110 }) do
    cacti[#cacti + 1] = { x = x, y = world:findGround(x, 100), tall = 10 + (x % 5) }
  end

  local spawnX = 210
  return world, spawnX, world:findGround(spawnX + 2, 100) - config.player.height
end

function overworld.populate(world)
  targets.clear()
  props.clear()
  -- A little shooting range near the start
  for _, x in ipairs({ 250, 272 }) do
    targets.addDummy(x, world:findGround(x, 100))
  end
  for i, x in ipairs({ 292, 301, 310 }) do
    props.spawn("crate", x, world:findGround(x, 100) - 4.5)
    if i < 3 then
      props.spawn("crate", x + 4.5, world:findGround(x, 100) - 12.5)
    end
  end
  props.spawn("ironCrate", 390, world:findGround(390, 100) - 5.5)
  props.spawn("crate", 640, world:findGround(640, 100) - 4.5)
end

-- Dropping to the bottom of the shaft enters the mine
function overworld.update(dt, player, game)
  local b = player.body
  if b.x >= SHAFT_X0 - 2 and b.x + b.w <= SHAFT_X1 + 2 and b.y + b.h >= SHAFT_BOTTOM - 4 then
    game.enter("mine")
  end
end

function overworld.drawBackground(camX, camY)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(background.sky, 0, 0)
  for _, l in ipairs(background.layers) do
    love.graphics.draw(l.image, -math.floor(camX * l.parallax), -math.floor(camY * l.parallax * 0.5))
  end
end

local function drawCactus(c)
  local x, y = c.x, c.y
  love.graphics.setColor(0.30, 0.62, 0.30)
  love.graphics.rectangle("fill", x - 1, y - c.tall, 3, c.tall)
  love.graphics.rectangle("fill", x - 4, y - c.tall + 4, 2, 4)
  love.graphics.rectangle("fill", x - 4, y - c.tall + 7, 4, 2)
  love.graphics.rectangle("fill", x + 3, y - c.tall + 2, 2, 4)
  love.graphics.rectangle("fill", x + 1, y - c.tall + 5, 4, 2)
  love.graphics.setColor(0.45, 0.78, 0.40)
  love.graphics.rectangle("fill", x - 1, y - c.tall, 1, c.tall)
end

-- Decorations drawn behind the player
function overworld.drawDecor()
  for _, c in ipairs(cacti) do
    drawCactus(c)
  end
  -- Pulley wheel on the headframe
  love.graphics.setColor(0.25, 0.22, 0.22)
  local cx = (SHAFT_X0 + SHAFT_X1) / 2
  local groundY = surface(cx)
  love.graphics.circle("line", cx, groundY - 51, 4)
  love.graphics.line(cx, groundY - 47, cx, groundY + 20)
end

function overworld.drawScreen(toScreen, font)
  local cx = (SHAFT_X0 + SHAFT_X1) / 2
  local sx, sy = toScreen(cx, surface(cx) - 64)
  local text = "OLD MINE"
  love.graphics.setFont(font)
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2) + 2, math.floor(sy) + 2)
  love.graphics.setColor(1, 0.85, 0.4)
  love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2), math.floor(sy))
end

return overworld
