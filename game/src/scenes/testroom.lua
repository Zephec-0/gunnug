-- Hand-built room for tuning movement, recoil jumping and the revolver.
-- Layout (left to right): floating platform, ramp, steps, a pillar that needs
-- recoil to clear, and a high ledge only reachable by recoil jumping.
local config = require("src.config")
local chests = require("src.chests")
local enemies = require("src.enemies")
local guns = require("src.guns")
local items = require("src.items")
local pickups = require("src.pickups")
local materials = require("src.materials")
local props = require("src.props")
local targets = require("src.targets")
local World = require("src.world")

local DIRT, ROCK, BEDROCK = materials.DIRT, materials.ROCK, materials.BEDROCK

local testroom = {
  title = "Test Room",
  subtitle = "Tuning ground",
  ambient = { 0.5, 0.5, 0.62 },
}

local WIDTH, HEIGHT = 1024, 576
local BORDER = 10
local FLOOR_Y = 499

local function floorTop(x)
  return FLOOR_Y + math.floor(math.sin(x * 0.031) * 3.2 + math.sin(x * 0.081) * 2.4)
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
    world:fillRect(x, floorTop(x), x, 531, DIRT)
    world:fillRect(x, 532, x, HEIGHT - BORDER - 1, ROCK)
  end

  -- Floating platform (left)
  world:fillRect(96, 429, 240, 440, DIRT)
  world:fillRect(112, 441, 224, 445, ROCK)

  -- Ramp up to a plateau, then a cliff back down
  for x = 304, 528 do
    local top = x < 432 and math.floor(FLOOR_Y - (x - 304) * 0.5) or FLOOR_Y - 64
    world:fillRect(x, top, x, FLOOR_Y + 16, DIRT)
  end

  -- Small stairs (each step within the walkable step height)
  for i = 0, 4 do
    local x0 = 552 + i * 10
    world:fillRect(x0, FLOOR_Y - 3 * (i + 1), 598, FLOOR_Y + 16, ROCK)
  end

  -- Pillar too tall to jump: clear it with recoil
  world:fillRect(632, 419, 651, FLOOR_Y + 16, ROCK)

  -- High ledge on the right
  world:fillRect(800, 371, WIDTH - BORDER - 1, 390, ROCK)
  world:fillRect(800, 365, WIDTH - BORDER - 1, 370, DIRT)

  -- Stalactites
  for _, s in ipairs({ { 192, 64 }, { 416, 96 }, { 528, 48 }, { 720, 128 }, { 896, 72 } }) do
    local cx, len = s[1], s[2]
    for y = BORDER, BORDER + len do
      local half = math.floor((1 - (y - BORDER) / len) * 11)
      world:fillRect(cx - half, y, cx + half, y, ROCK)
    end
  end

  world:repaintAll()

  local spawnX = 48
  return world, spawnX, world:findGroundUnder(spawnX, config.player.width, BORDER) - config.player.height
end

-- Places targets and props. Call after physics.init(world).
function testroom.populate(world)
  targets.clear()
  for _, x in ipairs({ 168, 264, 480, 752, 928 }) do
    targets.addDummy(x, world:findGround(x, BORDER + 160))
  end

  props.clear()
  local function onGround(name, x, stackLevel, fromY)
    local h = props.defs[name].height
    local ground = world:findGround(math.floor(x), fromY or BORDER + 160)
    return props.spawn(name, x, ground - h / 2 - (stackLevel or 0) * h - 0.5)
  end
  -- Near spawn, for pushing and standing on
  onGround("crate", 112, 0, 464)
  -- A small pyramid between the pillar and the ledge
  for i, x in ipairs({ 704, 718, 732 }) do
    onGround("crate", x)
    if i < 3 then
      onGround("crate", x + 7, 1)
    end
  end
  onGround("crate", 718, 2)
  -- Heavy iron crates: one on the plateau, one on the ledge
  onGround("ironCrate", 456)
  onGround("ironCrate", 864)

  -- Every ammo type and attachment, lined up on the floor near the start
  -- (only 7 fit in the loose slots at a time: fit some, then grab the rest)
  for i, id in ipairs(items.order) do
    local x = 40 + (i - 1) * 8
    pickups.dropItem(x, world:findGround(x, BORDER + 160) - 6, items.new(id))
  end

  -- A chest and a ready-made weapon on the floor to try finding weapons with
  chests.spawn(150, world:findGround(150, BORDER + 160), 0.5)
  pickups.dropWeapon(190, world:findGround(190, BORDER + 160) - 8, guns.generate(), 0, 0)

  -- One of each monster to practise on: a ghoul on the floor past the
  -- pillar, and a bat and a spitter hanging under the high ledge
  enemies.spawn("ghoul", 760, world:findGround(760, BORDER + 160))
  enemies.spawn("bat", 880, 391)
  enemies.spawn("spitter", 960, 391)
end

return testroom
