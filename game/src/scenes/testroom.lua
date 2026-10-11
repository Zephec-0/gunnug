-- Hand-built room for tuning movement, recoil jumping and the revolver.
-- Layout (left to right): floating platform, ramp, steps, a pillar that needs
-- recoil to clear, and a high ledge only reachable by recoil jumping.
local config = require("src.config")
local materials = require("src.materials")
local props = require("src.props")
local targets = require("src.targets")
local World = require("src.world")

local DIRT, ROCK, BEDROCK = materials.DIRT, materials.ROCK, materials.BEDROCK

local testroom = {
  title = "Test Room",
  subtitle = "Tuning ground",
}

local WIDTH, HEIGHT = 640, 360
local BORDER = 6
local FLOOR_Y = 312

local function floorTop(x)
  return FLOOR_Y + math.floor(math.sin(x * 0.05) * 2 + math.sin(x * 0.13) * 1.5)
end

function testroom.build()
  local world = World.new(WIDTH, HEIGHT)

  -- Bedrock shell
  world:fillRect(0, 0, WIDTH - 1, BORDER - 1, BEDROCK)
  world:fillRect(0, HEIGHT - BORDER, WIDTH - 1, HEIGHT - 1, BEDROCK)
  world:fillRect(0, 0, BORDER - 1, HEIGHT - 1, BEDROCK)
  world:fillRect(WIDTH - BORDER, 0, WIDTH - 1, HEIGHT - 1, BEDROCK)

  -- Undulating dirt floor over a rock bed
  for x = BORDER, WIDTH - BORDER - 1 do
    world:fillRect(x, floorTop(x), x, 332, DIRT)
    world:fillRect(x, 333, x, HEIGHT - BORDER - 1, ROCK)
  end

  -- Floating platform (left)
  world:fillRect(60, 268, 150, 275, DIRT)
  world:fillRect(70, 276, 140, 278, ROCK)

  -- Ramp up to a plateau, then a cliff back down
  for x = 190, 330 do
    local top = x < 270 and math.floor(FLOOR_Y - (x - 190) * 0.5) or FLOOR_Y - 40
    world:fillRect(x, top, x, FLOOR_Y + 10, DIRT)
  end

  -- Small stairs (each step within the walkable step height)
  for i = 0, 4 do
    local x0 = 345 + i * 6
    world:fillRect(x0, FLOOR_Y - 2 * (i + 1), 374, FLOOR_Y + 10, ROCK)
  end

  -- Pillar too tall to jump: clear it with recoil
  world:fillRect(395, 262, 407, FLOOR_Y + 10, ROCK)

  -- High ledge on the right
  world:fillRect(500, 232, WIDTH - BORDER - 1, 244, ROCK)
  world:fillRect(500, 228, WIDTH - BORDER - 1, 231, DIRT)

  -- Stalactites
  for _, s in ipairs({ { 120, 40 }, { 260, 60 }, { 330, 30 }, { 450, 80 }, { 560, 45 } }) do
    local cx, len = s[1], s[2]
    for y = BORDER, BORDER + len do
      local half = math.floor((1 - (y - BORDER) / len) * 7)
      world:fillRect(cx - half, y, cx + half, y, ROCK)
    end
  end

  world:repaintAll()

  local spawnX = 30
  return world, spawnX, world:findGround(spawnX, BORDER) - config.player.height
end

-- Places targets and props. Call after physics.init(world).
function testroom.populate(world)
  targets.clear()
  for _, x in ipairs({ 105, 165, 300, 470, 580 }) do
    targets.addDummy(x, world:findGround(x, BORDER + 100))
  end

  props.clear()
  local function onGround(name, x, stackLevel, fromY)
    local h = props.defs[name].height
    local ground = world:findGround(math.floor(x), fromY or BORDER + 100)
    return props.spawn(name, x, ground - h / 2 - (stackLevel or 0) * h - 0.5)
  end
  -- Near spawn, for pushing and standing on
  onGround("crate", 70, 0, 290)
  -- A small pyramid between the pillar and the ledge
  for i, x in ipairs({ 440, 449, 458 }) do
    onGround("crate", x)
    if i < 3 then
      onGround("crate", x + 4.5, 1)
    end
  end
  onGround("crate", 449, 2)
  -- Heavy iron crates: one on the plateau, one on the ledge
  onGround("ironCrate", 285)
  onGround("ironCrate", 540)
end

return testroom
