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
local randevents = require("src.randevents")
local targets = require("src.targets")
local World = require("src.world")

local DIRT, ROCK, BEDROCK = materials.DIRT, materials.ROCK, materials.BEDROCK

local testroom = {
  title = "Test Room",
  subtitle = "Tuning ground",
  ambient = { 0.5, 0.5, 0.62 },
}

-- The original room sits OX px in from the left; the item hall fills the space
-- to its left (see itemHall)
local OX = 700
-- Past the room's far wall runs the events row: one stand of every random event
-- (see populate), on a flat floor
local EV_X0 = OX + 1024
local EV_STEP = 200
local EV_KINDS = { "carnival", "gambler", "tinker", "shrine", "cavein", "hunt" }
-- Past the events row: the perk gallery, every perk lying in two rows (floor and a platform above it)
local PERK_X0 = EV_X0 + 60 + #EV_KINDS * EV_STEP + 40
local PERK_STEP = 18
local PERK_COUNT = 31 -- (perks.order)
local WIDTH, HEIGHT = PERK_X0 + math.ceil(PERK_COUNT / 2) * PERK_STEP + 80, 576
local BORDER = 10
local FLOOR_Y = 499

local function floorTop(x)
  if x < OX then
    return FLOOR_Y
  end
  if x >= EV_X0 then
    return FLOOR_Y
  end
  x = x - OX
  return FLOOR_Y + math.floor(math.sin(x * 0.031) * 3.2 + math.sin(x * 0.081) * 2.4)
end

-- The platforms of the item hall: { x0, x1, y } (y is the top of the platform),
-- each stepped in from the other end so the one above can be jumped onto
local HALL_SPACING = 12
local HALL_X0, HALL_X1 = BORDER + 24, OX - 40
function testroom.hallTiers()
  local w = HALL_X1 - HALL_X0
  return {
    { x0 = HALL_X0, x1 = HALL_X1 - 70, y = FLOOR_Y - 34 },
    { x0 = HALL_X0 + 70, x1 = HALL_X1, y = FLOOR_Y - 68 },
    { x0 = HALL_X0, x1 = HALL_X1 - 70, y = FLOOR_Y - 102 },
  }
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
  world:fillRect(OX + 96, 429, OX + 240, 440, DIRT)
  world:fillRect(OX + 112, 441, OX + 224, 445, ROCK)

  -- Ramp up to a plateau, then a cliff back down
  for x = OX + 304, OX + 528 do
    local top = x < OX + 432 and math.floor(FLOOR_Y - (x - OX - 304) * 0.5) or FLOOR_Y - 64
    world:fillRect(x, top, x, FLOOR_Y + 16, DIRT)
  end

  -- Small stairs (each step within the walkable step height)
  for i = 0, 4 do
    local x0 = OX + 552 + i * 10
    world:fillRect(x0, FLOOR_Y - 3 * (i + 1), OX + 598, FLOOR_Y + 16, ROCK)
  end

  -- Pillar too tall to jump: clear it with recoil
  world:fillRect(OX + 632, 419, OX + 651, FLOOR_Y + 16, ROCK)

  -- High ledge on the right
  world:fillRect(OX + 800, 371, EV_X0 - 1, 390, ROCK)
  world:fillRect(OX + 800, 365, EV_X0 - 1, 370, DIRT)

  -- Stalactites
  for _, s in ipairs({ { 192, 64 }, { 416, 96 }, { 528, 48 }, { 720, 128 }, { 896, 72 } }) do
    local cx, len = OX + s[1], s[2]
    for y = BORDER, BORDER + len do
      local half = math.floor((1 - (y - BORDER) / len) * 11)
      world:fillRect(cx - half, y, cx + half, y, ROCK)
    end
  end

  -- The item hall: three stepped platforms to the left of the room (see populate)
  for _, t in ipairs(testroom.hallTiers()) do
    world:fillRect(t.x0, t.y, t.x1, t.y + 5, ROCK)
    world:fillRect(t.x0, t.y - 2, t.x1, t.y - 1, DIRT)
  end

  -- The perk gallery's platform
  world:fillRect(PERK_X0 - 10, FLOOR_Y - 46, WIDTH - BORDER - 40, FLOOR_Y - 41, ROCK)
  world:fillRect(PERK_X0 - 10, FLOOR_Y - 48, WIDTH - BORDER - 40, FLOOR_Y - 47, DIRT)

  world:repaintAll()

  local spawnX = OX + 48
  return world, spawnX, world:findGroundUnder(spawnX, config.player.width, BORDER) - config.player.height
end

-- Places targets and props. Call after physics.init(world).
function testroom.populate(world)
  targets.clear()
  for _, x in ipairs({ 168, 264, 480, 752, 928 }) do
    x = x + OX
    targets.addDummy(x, world:findGround(x, BORDER + 160))
  end

  props.clear()
  local function onGround(name, x, stackLevel, fromY)
    x = x + OX
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
  -- The old mine's TNT barrels (shoot one: they set each other off) and an ore cart
  onGround("tntBarrel", 224, 0, 464)
  onGround("tntBarrel", 241, 0, 464)
  onGround("tntBarrel", 232, 1, 464)
  onGround("minecart", 84, 0, 464)
  -- Heavy iron crates: one on the plateau, one on the ledge
  onGround("ironCrate", 456)
  onGround("ironCrate", 864)

  -- Every ammo type and attachment (fused ones last), spaced out along the
  -- item hall's platforms, filling each tier from its left end
  local ids = {}
  for _, id in ipairs(items.order) do
    ids[#ids + 1] = id
  end
  for _, id in ipairs(items.fusedOrder or {}) do
    ids[#ids + 1] = id
  end
  local tiers = testroom.hallTiers()
  local tier, slot = 1, 0
  for _, id in ipairs(ids) do
    local t = tiers[tier]
    local x = t.x0 + 10 + slot * HALL_SPACING
    if x > t.x1 - 8 and tiers[tier + 1] then
      tier, slot = tier + 1, 0
      t = tiers[tier]
      x = t.x0 + 10
    end
    pickups.dropItem(x, t.y - 8, items.new(id))
    slot = slot + 1
  end

  -- A chest and a ready-made weapon on the floor to try finding weapons with
  chests.spawn(OX + 150, world:findGround(OX + 150, BORDER + 160), 0.5)
  pickups.dropWeapon(OX + 190, world:findGround(OX + 190, BORDER + 160) - 8, guns.generate(), 0, 0)

  -- One of each monster to practise on: a ghoul on the floor past the
  -- pillar, and a bat and a spitter hanging under the high ledge
  enemies.spawn("ghoul", OX + 760, world:findGround(OX + 760, BORDER + 160))
  enemies.spawn("bat", OX + 880, 391)
  enemies.spawn("spitter", OX + 960, 391)
  -- The deeper monsters, near the start so they are easy to try: a skeleton
  -- miner, a cave roller, and a worm coiled in the dirt under the floor
  enemies.spawn("miner", OX + 560, world:findGround(OX + 560, BORDER + 160))
  enemies.spawn("roller", OX + 672, world:findGround(OX + 640, BORDER + 160))
  enemies.spawn("worm", OX + 880, 510)
  -- The events row: the random events, all standing at once (each comes back
  -- a moment after it is spent)
  for i, kind in ipairs(EV_KINDS) do
    local x = EV_X0 + 60 + (i - 0.5) * EV_STEP
    randevents.addStand(kind, x, world:findGround(x, BORDER + 160), world)
  end

  -- The perk gallery: every perk, lying in two rows at the far end
  for i, id in ipairs(require("src.perks").order) do
    local col = math.ceil(i / 2)
    local x = PERK_X0 + (col - 1) * PERK_STEP
    local y = (i % 2 == 1) and (FLOOR_Y - 12) or (FLOOR_Y - 60)
    pickups.dropPerk(x, y, id, 0, 0)
  end

  -- A DPS dummy, like the one in every shop
  enemies.spawn("dummy", OX + 290, world:findGround(OX + 290, BORDER + 160))
end

return testroom
