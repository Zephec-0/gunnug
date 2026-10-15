-- The generated areas under the Barrens (design doc §3, §7): the Catacombs,
-- the Sunken Hollows below them, then the Sulfur Vents, each ending at a shop
-- room whose hatch drops into the next. The Vents end differently: a huge
-- boss arena (the Sulfur Queen's) fills their last quarter, and below it, once
-- the Queen is dead, are two shops, left and right, each leading to its own
-- area (the Cinder Warrens on the left, the Drowned Halls on the right).
-- Entering one shop collapses the shaft to the other. Not scenes of their own:
-- the overworld scene owns the whole world and hands this module the region
-- below the surface.
--
-- Generation takes a few seconds per area, so each area runs as a coroutine a
-- few milliseconds per frame, in order, in the background while the hunter is
-- still above it (no loading screen). catacombs.ensure(y) completes any area
-- the hunter is getting close to, if it isn't done yet.
local cavegen = require("src.cavegen")
local chests = require("src.chests")
local audio = require("src.audio")
local effects = require("src.effects")
local enemies = require("src.enemies")
local fluids = require("src.fluids")
local pickups = require("src.pickups")
local hud = require("src.hud")
local materials = require("src.materials")
local minedecor = require("src.minedecor")
local story = require("src.story")
local physics = require("src.physics")
local config = require("src.config")
local props = require("src.props")
local shop = require("src.shop")
local npcs = require("src.npcs")

local catacombs = {}

-- How each area looks: palette, light, the glowing mushrooms (or crystals)
-- that light the way, the backdrop behind the rock and the far rock pillars
-- (dark face, rim light, cracks). glowCount is per 1920x3680 of area.
local THEMES = {
  {
    name = "The Catacombs",
    subtitle = "Area 1",
    prisoner = "prospector", -- buried by a cave-in in the old mine (src.npcs)
    ambient = { 0.20, 0.18, 0.25 },
    fx = { aberr = 0.7 },
    palette = nil, -- the default rock and dirt
    glow = { 0.35, 0.95, 0.85 }, -- teal fungus
    glowCount = 150,
    glowRadius = 34,
    stalk = { 0.55, 0.62, 0.55 },
    backTop = { 0.10, 0.08, 0.14 },
    backDeep = { 0.06, 0.05, 0.09 },
    pillars = { { 0.03, 0.025, 0.05 }, { 0.16, 0.13, 0.22 }, { 0.10, 0.08, 0.15 } },
    monsters = { ghoul = 38, bat = 28, spitter = 14, hopper = 6, miner = 28, roller = 10, worm = 12 }, -- per 1920x3680; an old mine: skeletal miners, rollers and worms in the rock
    boss = { "warden", "dreadbat" }, -- one of the two, chosen per run
    waterPools = 30,
    swarms = { swarmbat = 4 }, -- colonies of bats under the ceilings
    -- Breakables beside the crates { prop, count per 1920x3680 }: pots and pouches of coin, candle-lit skulls and lanterns
    breakables = { { "urn", 14 }, { "pouch", 12 }, { "lantern", 8 }, { "skullCandle", 8 }, { "sporePod", 6 }, { "tntBarrel", 22 }, { "tntBarrel", 8 }, { "crate", 12 } },
    mine = true, -- an old mine: rails and carts, shoring, oil lamps, skeletons, pickaxes, TNT
    stalactites = 150,
  },
  {
    name = "The Sunken Hollows",
    subtitle = "Area 2",
    wounded = true, -- a dying hunter lies somewhere in the fen (src.events)
    prisoner = "gunsmith", -- caged somewhere in the fen (src.npcs)
    ambient = { 0.09, 0.12, 0.18 }, -- darker and colder
    fx = { shadow = { 0.84, 0.95, 1.16 }, light = { 1.0, 1.02, 1.05 }, sat = 0.9, vig = 0.45 },
    palette = { rock = materials.SLATE, dirt = materials.BLUECLAY },
    glow = { 0.35, 1.0, 0.45 }, -- green mushrooms, lots of them
    glowCount = 480,
    glowRadius = 40,
    stalk = { 0.45, 0.62, 0.50 },
    backTop = { 0.045, 0.06, 0.105 },
    backDeep = { 0.03, 0.04, 0.075 },
    pillars = { { 0.02, 0.03, 0.05 }, { 0.10, 0.14, 0.22 }, { 0.06, 0.08, 0.14 } },
    monsters = { ghoul = 20, bat = 14, spitter = 20, hopper = 44, bloater = 10, worm = 12, roller = 14, miner = 5 }, -- a fen: hoppers everywhere
    boss = "matron",
    waterPools = 60,
    swarms = { swarmbat = 2 },
    breakables = { { "sporePod", 36 }, { "urn", 10 }, { "pouch", 14 }, { "lantern", 8 } }, -- glowing spore pods in the fen
    stalactites = 70,
  },
  {
    name = "The Sulfur Vents",
    subtitle = "Area 3",
    prisoner = "apothecary", -- caged, coughing, somewhere in the fumes (src.npcs)
    ambient = { 0.22, 0.22, 0.13 }, -- a murky yellow-green
    fx = { shadow = { 0.96, 1.06, 0.80 }, light = { 1.1, 1.06, 0.84 }, sat = 1.1, aberr = 0.9 },
    palette = { rock = materials.SULFUR, dirt = materials.BILECLAY },
    glow = { 1.0, 0.92, 0.35 }, -- sulfur crystals
    glowLight = 0.4, -- (yellow reads far brighter than the other areas' tints, so they give less light)
    glowCount = 220,
    glowRadius = 36,
    crystals = true,
    stalk = { 0.80, 0.72, 0.30 },
    backTop = { 0.085, 0.09, 0.04 },
    backDeep = { 0.05, 0.055, 0.025 },
    pillars = { { 0.035, 0.035, 0.012 }, { 0.20, 0.20, 0.08 }, { 0.11, 0.11, 0.05 } },
    monsters = { ghoul = 14, bat = 10, spitter = 12, hopper = 8, bloater = 46, wisp = 40, worm = 12, roller = 8, miner = 8 }, -- gas bags and fire wisps
    boss = "queen", -- the Sulfur Queen, in the arena that fills the last quarter
    arena = true,
    gasPools = 34, -- pools of poison gas in low spots (src.fluids)
    waterPools = 22,
    acidPools = 14,
    swarms = { swarmbat = 2, wisp = 3 }, -- and flocks of wisps
    breakables = { { "geode", 30 }, { "urn", 10 }, { "pouch", 12 }, { "lantern", 10 } }, -- sulfur geodes that glow (no open flames: the gas)
    stalactites = 40,
  },
  {
    -- Left of the Queen's arena (area 4a): scorched basalt and ash, ember light
    name = "The Cinder Warrens",
    subtitle = "Area 4 - left path",
    ambient = { 0.22, 0.15, 0.13 },
    fx = { shadow = { 0.95, 0.96, 1.04 }, light = { 1.09, 1.0, 0.90 }, sat = 1.03, contrast = 0.31, aberr = 0.64 },
    palette = { rock = materials.BASALT, dirt = materials.ASH },
    glow = { 1.0, 0.55, 0.25 }, -- embers in the cracks
    glowCount = 260,
    glowRadius = 38,
    stalk = { 0.62, 0.34, 0.22 },
    backTop = { 0.10, 0.05, 0.045 },
    backDeep = { 0.06, 0.03, 0.03 },
    pillars = { { 0.04, 0.02, 0.02 }, { 0.26, 0.12, 0.08 }, { 0.14, 0.06, 0.05 } },
    monsters = { ghoul = 30, bat = 16, spitter = 18, hopper = 4, wisp = 36, worm = 14, roller = 14, miner = 14 },
    swarms = { swarmbat = 3, wisp = 3 },
    waterPools = 14,
    lavaPools = 26,
    breakables = { { "emberPot", 30 }, { "urn", 16 }, { "pouch", 14 }, { "skullCandle", 14 }, { "lantern", 8 } },
    stalactites = 80,
  },
  {
    -- Right of the Queen's arena (area 4b): a flooded slate maze
    name = "The Drowned Halls",
    subtitle = "Area 4 - right path",
    ambient = { 0.08, 0.13, 0.17 },
    fx = { shadow = { 0.90, 0.98, 1.09 }, light = { 1.05, 1.02, 0.95 }, sat = 0.99, aberr = 0.68, vig = 0.40 },
    palette = { rock = materials.SLATE, dirt = materials.BLUECLAY },
    glow = { 0.35, 0.85, 1.0 }, -- cyan glowcaps
    glowCount = 420,
    glowRadius = 40,
    stalk = { 0.40, 0.58, 0.62 },
    backTop = { 0.035, 0.07, 0.09 },
    backDeep = { 0.02, 0.045, 0.06 },
    pillars = { { 0.015, 0.035, 0.05 }, { 0.08, 0.17, 0.24 }, { 0.05, 0.10, 0.15 } },
    monsters = { ghoul = 10, bat = 10, spitter = 16, hopper = 52, bloater = 18, worm = 12, roller = 10, miner = 4 },
    swarms = { swarmbat = 3 },
    waterPools = 100,
    breakables = { { "sporePod", 30 }, { "geode", 12 }, { "urn", 16 }, { "pouch", 14 }, { "lantern", 12 } },
    stalactites = 90,
  },
  {
    -- Not on the main road: reached by a crevice in the east desert. An old
    -- quarry: pale cut sandstone and spoil, dust, amber lamps and crystals,
    -- the miners' ghosts and their blasting powder.
    name = "The Old Quarry",
    subtitle = "A side road",
    prisoner = "cartographer", -- a lost surveyor, caged in the workings (src.npcs)
    ambient = { 0.22, 0.17, 0.12 },
    fx = { shadow = { 1.0, 0.95, 0.88 }, light = { 1.1, 1.02, 0.88 }, sat = 1.04, aberr = 0.5 },
    palette = { rock = materials.SANDSTONE, dirt = materials.TAILINGS },
    glow = { 1.0, 0.72, 0.28 }, -- amber crystals
    glowCount = 110,
    glowRadius = 36,
    crystals = true,
    stalk = { 0.75, 0.6, 0.38 },
    backTop = { 0.16, 0.11, 0.08 },
    backDeep = { 0.09, 0.06, 0.05 },
    pillars = { { 0.05, 0.035, 0.03 }, { 0.26, 0.18, 0.12 }, { 0.15, 0.10, 0.07 } },
    monsters = { ghoul = 16, bat = 10, miner = 44, roller = 24, worm = 18, spitter = 6 },
    swarms = { swarmbat = 2 },
    waterPools = 8,
    breakables = { { "urn", 8 }, { "pouch", 14 }, { "lantern", 10 }, { "skullCandle", 6 }, { "tntBarrel", 30 }, { "tntBarrel", 12 }, { "crate", 18 } },
    mine = true,
    stalactites = 60,
    parallax = 1, -- (the first area's far scenery, in this area's colours)
    track = 1, -- (and its music)
  },
  {
    -- Under the Quarry: the foreman's hall, a boss chamber sized like the
    -- Queen's. For now its boss is the Warden; he guards the Diving Helm.
    name = "The Foreman's Hall",
    subtitle = "The Quarry's heart",
    ambient = { 0.20, 0.15, 0.11 },
    fx = { shadow = { 1.0, 0.95, 0.88 }, light = { 1.1, 1.02, 0.88 }, sat = 1.04, aberr = 0.5 },
    palette = { rock = materials.SANDSTONE, dirt = materials.TAILINGS },
    glow = { 1.0, 0.72, 0.28 },
    glowCount = 60,
    glowRadius = 36,
    crystals = true,
    stalk = { 0.75, 0.6, 0.38 },
    backTop = { 0.14, 0.10, 0.07 },
    backDeep = { 0.08, 0.055, 0.045 },
    pillars = { { 0.05, 0.035, 0.03 }, { 0.26, 0.18, 0.12 }, { 0.15, 0.10, 0.07 } },
    monsters = {},
    arena = true,
    arenaFrac = 0.11,
    arenaH = 400,
    arenaBanner = { "The Foreman's Hall", "Kill the Warden. He guards the way into the flooded caverns" },
    boss = "warden",
    bossReward = "diving_helm",
    stalactites = 30,
    parallax = 1,
    track = 3,
  },
  {
    -- The west: caverns under a lake in the west desert. The lake simply
    -- descends into the top of them, and all of it is water; with no breathing
    -- gear the hunter drowns, so the water is the lock.
    name = "The Flooded Caverns",
    subtitle = "Under the lake",
    ambient = { 0.07, 0.12, 0.16 },
    fx = { shadow = { 0.82, 0.98, 1.1 }, light = { 0.98, 1.05, 1.08 }, sat = 0.95, vig = 0.45, aberr = 0.6 },
    palette = { rock = materials.SLATE, dirt = materials.BLUECLAY },
    glow = { 0.3, 0.9, 1.0 },
    glowCount = 200,
    glowRadius = 40,
    crystals = true,
    stalk = { 0.45, 0.62, 0.62 },
    backTop = { 0.045, 0.07, 0.11 },
    backDeep = { 0.03, 0.045, 0.075 },
    pillars = { { 0.02, 0.03, 0.05 }, { 0.10, 0.15, 0.22 }, { 0.06, 0.09, 0.14 } },
    monsters = { hopper = 10, bloater = 8, spitter = 6, worm = 10, miner = 14 },
    flood = { level = 150 }, -- every open cell below this (px under the top) is water
    fish = 60, -- piranhas in the water
    mine = true,
    breakables = { { "urn", 8 }, { "pouch", 10 }, { "lantern", 10 }, { "crate", 14 } },
    stalactites = 60,
    parallax = 2,
    track = 2,
  },
  {
    -- Under the galleries: a big flooded chamber for an aquatic boss. A
    -- placeholder boss for now (the Matron).
    name = "The Deep",
    subtitle = "Something large lives here",
    ambient = { 0.05, 0.10, 0.14 },
    fx = { shadow = { 0.78, 1.0, 1.12 }, light = { 0.95, 1.08, 1.08 }, sat = 0.95, aberr = 0.7, vig = 0.5 },
    palette = { rock = materials.SLATE, dirt = materials.BLUECLAY },
    glow = { 0.35, 0.95, 0.9 },
    glowCount = 100,
    glowRadius = 40,
    crystals = true,
    stalk = { 0.45, 0.62, 0.62 },
    backTop = { 0.035, 0.06, 0.10 },
    backDeep = { 0.02, 0.04, 0.07 },
    pillars = { { 0.02, 0.03, 0.05 }, { 0.10, 0.15, 0.22 }, { 0.06, 0.09, 0.14 } },
    monsters = {},
    arena = true,
    arenaFrac = 0.08,
    arenaH = 1000,
    arenaWidth = 0.72,
    arenaBanner = { "The Deep", "Something old and large turns in the dark water" },
    boss = "matron",
    flood = { level = 90 },
    fish = 30,
    stalactites = 20,
    parallax = 5,
    track = 5,
  },
  {
    -- A mountain at the east end of the desert, entered by a doorway at the
    -- top of a long ramp. A deep cave that climbs, on ladders of platforms, to
    -- the summit, where a boss guards the way up into the sky.
    name = "The Needle",
    subtitle = "The way up",
    ambient = { 0.18, 0.14, 0.12 },
    fx = { shadow = { 1.0, 0.95, 0.9 }, light = { 1.08, 1.02, 0.9 }, sat = 1.02, aberr = 0.5, vig = 0.42 },
    palette = { rock = materials.SANDSTONE, dirt = materials.SAND },
    glow = { 1.0, 0.6, 0.3 },
    glowCount = 90,
    glowRadius = 34,
    crystals = true,
    stalk = { 0.75, 0.55, 0.38 },
    backTop = { 0.13, 0.09, 0.08 },
    backDeep = { 0.07, 0.05, 0.05 },
    pillars = { { 0.05, 0.035, 0.03 }, { 0.26, 0.17, 0.12 }, { 0.15, 0.10, 0.07 } },
    monsters = { bat = 26, ghoul = 18, spitter = 10, miner = 12, roller = 8, worm = 10 },
    swarms = { swarmbat = 3 },
    waterPools = 4,
    breakables = { { "urn", 8 }, { "pouch", 12 }, { "lantern", 10 }, { "skullCandle", 6 }, { "tntBarrel", 12 }, { "crate", 14 } },
    stalactites = 100,
    climb = true, -- the routes go up (see src.cavegen)
    indoors = true, -- dark inside, though it stands above the ground
    profile = function(y)
      -- The mountain's silhouette: the plain's rock below the ground line, a
      -- flank rising from x 5900 to x 6900 at the summit above it
      if y < -2900 then
        return nil
      end
      if y >= 500 then
        return 5800, 8599
      end
      return math.floor(5900 + (500 - y) * (1000 / 3400)), 8599
    end,
    groundY = 500,
    arena = true,
    arenaFrac = 0.04,
    arenaH = 400,
    arenaCx = 7750,
    arenaBanner = { "The Summit", "Kill the Dreadbat. The way up lies beyond it" },
    arenaWon = { "The Dreadbat Has Fallen", "The gate above the arena is open: the sky lies beyond" },
    boss = "dreadbat",
    parallax = 1,
    track = 1,
  },
  {
    -- The sky, above the mountain: islands and spires in open air, with low gravity
    name = "The Cloud Reaches",
    subtitle = "Where the air thins",
    ambient = { 0.55, 0.48, 0.5 },
    fx = { shadow = { 0.95, 0.96, 1.06 }, light = { 1.08, 1.02, 0.92 }, sat = 1.05, aberr = 0.5 },
    palette = { rock = materials.SANDSTONE, dirt = materials.SAND },
    glow = { 0.75, 0.9, 1.0 },
    glowCount = 60,
    glowRadius = 38,
    crystals = true,
    stalk = { 0.7, 0.8, 0.9 },
    backTop = { 0.30, 0.22, 0.28 },
    backDeep = { 0.30, 0.22, 0.28 },
    pillars = { { 0.2, 0.15, 0.2 }, { 0.5, 0.4, 0.45 }, { 0.35, 0.27, 0.32 } },
    monsters = { bat = 30, ghoul = 10, spitter = 14, wisp = 12 },
    swarms = { swarmbat = 6, wisp = 3 },
    breakables = { { "urn", 10 }, { "pouch", 12 }, { "lantern", 8 }, { "crate", 12 } },
    stalactites = 20,
    open = true, -- islands and spires, no caves (see src.cavegen)
    gravity = 0.35, -- a third of the pull: high jumps, long recoil
    parallax = 2,
    track = 2,
  },
}

-- How the areas are laid out. Every area is its own rectangle: x, y (from the
-- top-left corner of the first area) and w, h in pixels, so areas need not
-- match one another in size or sit in neat rows. tier is how deep it counts for
-- difficulty (monsters, loot, prices); parent is the area whose shop hatch
-- leads into it (default: the one before it in the list) and side which of the
-- parent's shops that is.
-- Below the two post-Queen paths (themes 12 and 13, after the sky): the same
-- caves a tier deeper, hotter and wetter. Each is the next area down from its
-- path's last shop (its hatch opens now).
local function derive(base, over)
  local t = {}
  for k, v in pairs(base) do
    t[k] = v
  end
  for k, v in pairs(over) do
    t[k] = v
  end
  return t
end
THEMES[12] = derive(THEMES[4], {
  name = "The Ember Foundry",
  subtitle = "Area 5 - under the Cinder Warrens",
  ambient = { 0.26, 0.15, 0.11 },
  glowCount = 300,
  lavaPools = 44,
  monsters = { ghoul = 20, bat = 12, spitter = 14, wisp = 44, worm = 18, roller = 24, miner = 28 },
  breakables = { { "emberPot", 44 }, { "urn", 12 }, { "pouch", 12 }, { "skullCandle", 18 }, { "lantern", 8 } },
  stalactites = 60,
})
THEMES[13] = derive(THEMES[5], {
  name = "The Silt Vaults",
  subtitle = "Area 5 - under the Drowned Halls",
  ambient = { 0.06, 0.11, 0.15 },
  waterPools = 150,
  monsters = { ghoul = 8, bat = 8, spitter = 18, hopper = 60, bloater = 26, worm = 14, roller = 8, miner = 6 },
  stalactites = 100,
})

local AREA_W, AREA_H = 2880, 3100
local LAYOUT = {
  { x = 0, y = 0, w = AREA_W, h = AREA_H, tier = 1 },
  { x = 0, y = AREA_H, w = AREA_W, h = AREA_H, tier = 2 },
  { x = 0, y = 2 * AREA_H, w = AREA_W, h = AREA_H, tier = 3 },
  { x = 0, y = 3 * AREA_H, w = AREA_W / 2, h = AREA_H, tier = 4, side = "left", parent = 3 },
  { x = AREA_W / 2, y = 3 * AREA_H, w = AREA_W / 2, h = AREA_H, tier = 4, side = "right", parent = 3 },
  -- The Old Quarry: a side branch under the east desert, entered from a
  -- crevice on the surface (entry: its x and half-width). Shorter than the
  -- main areas. rank is what it counts as for "deepest reached".
  { x = AREA_W, y = 0, w = AREA_W, h = 2300, tier = 2, rank = 2, entry = { x = 4300, half = 19 } },
  -- Under the Quarry: its boss's hall, about the size of the Queen's chamber
  { x = AREA_W, y = 2300, w = AREA_W, h = 800, tier = 3, rank = 3, parent = 6 },
  -- The west: a flooded mine, entered from a shaft in the west desert (the
  -- hunter drowns without the Diving Helm), and a flooded chamber under it
  { x = -2800, y = 0, w = 2400, h = 2600, tier = 3, rank = 3, entry = { x = -900, half = 380, neck = 50, lake = true } },
  { x = -2800, y = 2600, w = 2400, h = 1800, tier = 4, rank = 4, parent = 8 },
  -- The mountain at the east end: a doorway at the top of a ramp (entry.x, entry.y is
  -- inside, behind the doorway), climbing to a summit boss. Its rock above the ground
  -- line is the mountain you see from the desert.
  { x = 5800, y = -3660, w = 2800, h = 4000, tier = 4, rank = 4, entry = { x = 6080, y = 380, walk = true } },
  -- The sky, over the mountain's summit and most of the desert, reached through the
  -- gate above the summit boss's arena
  { x = 0, y = -5060, w = 8600, h = 1400, tier = 5, rank = 5, parent = 10 },
  -- The way on below each post-Queen path (their last shops get hatches)
  { x = 0, y = 4 * AREA_H, w = AREA_W / 2, h = AREA_H, tier = 5, parent = 4 },
  { x = AREA_W / 2, y = 4 * AREA_H, w = AREA_W / 2, h = AREA_H, tier = 5, parent = 5 },
}

-- Width of the main road's column: everything east of it is side branches
catacombs.SPINE_W = AREA_W

-- The surface entrances of side branches: { x, half } of each crevice
function catacombs.entries()
  local list = {}
  for _, l in ipairs(LAYOUT) do
    if l.entry then
      list[#list + 1] = l.entry
    end
  end
  return list
end

-- How deep an area counts as, for the "deepest reached" record
function catacombs.rank(i)
  local l = LAYOUT[i]
  return l and l.rank or i
end

-- How much room the areas take: the left, right and bottom edges (x as in the
-- world, y below the first area's top)
function catacombs.layoutBounds()
  local left, right, top, bottom = 0, 0, 0, 0
  for _, l in ipairs(LAYOUT) do
    left = math.min(left, l.x)
    right = math.max(right, l.x + l.w)
    top = math.min(top, l.y)
    bottom = math.max(bottom, l.y + l.h)
  end
  return left, right, top, bottom
end

local levels = {} -- levels[i] = { theme, area, job, info, propsSpawned, shopReached }
local world
local firstArea, baseSeed
local deadline = 0 -- os.clock() time the current slice of work must stop at
local announced = {} -- the areas whose banner has been shown

function catacombs.count()
  return #levels
end

function catacombs.theme(i)
  return THEMES[i] or THEMES[#THEMES]
end

-- Starts the areas under the surface. first: the first area's rectangle and
-- entrance (see cavegen.generate); tiers: how deep the layout goes (4 is the
-- whole of it, 3 stops after the Sulfur Vents).
function catacombs.start(w, first, seed, tiers)
  world, firstArea, baseSeed = w, first, seed
  minedecor.clear()
  levels = {}
  announced = {}
  fluids.clear()
  for i, l in ipairs(LAYOUT) do
    if l.tier <= (tiers or 1) then
      levels[i] = {
        theme = THEMES[i],
        index = i,
        row = l.tier, -- (the depth tier; still called row in the code below)
        parent = l.parent,
        side = l.side,
        entry = l.entry,
        x0 = first.x0 + l.x,
        x1 = first.x0 + l.x + l.w - 1,
        y0 = first.y0 + l.y,
        y1 = first.y0 + l.y + l.h - 1,
      }
    end
  end
  -- The boss's death opens the arena's gates
  enemies.onBossKilled = function(e)
    for _, lv in ipairs(levels) do
      if lv.info and lv.info.arena and e.areaIndex == lv.index then
        catacombs.openGates(lv)
      end
    end
  end
end

-- The area (index) that the shop j (1 = left, 2 = right) of area i leads to
local function childOf(i, j)
  for k, l in ipairs(levels) do
    if k > 1 and not l.entry and (l.parent or k - 1) == i and (not l.side or (l.side == "left") == (j == 1)) then
      return k
    end
  end
  return nil
end

-- The area spec for level i, built from the area above once that is generated
local function areaFor(i)
  local lv = levels[i]
  local base = {}
  if i == 1 then
    for k, v in pairs(firstArea) do
      base[k] = v
    end
    base.x0, base.x1, base.y0, base.y1 = lv.x0, lv.x1, lv.y0, lv.y1
  elseif lv.entry and lv.entry.walk then
    -- A mountain entered through a doorway at ground level
    base = {
      x0 = lv.x0,
      x1 = lv.x1,
      y0 = lv.y0,
      y1 = lv.y1,
      entranceX = lv.entry.x,
      entranceY = lv.entry.y,
    }
  elseif lv.entry then
    -- A side branch entered from a crevice on the surface (like the first area's shaft)
    local neck = lv.entry.neck or lv.entry.half
    base = {
      x0 = lv.x0,
      x1 = lv.x1,
      y0 = lv.y0,
      y1 = lv.y1,
      entranceX = lv.entry.x,
      entranceY = lv.y0 + 96,
      shaftX0 = lv.entry.x - neck,
      shaftX1 = lv.entry.x + neck,
    }
  else
    local parent = levels[lv.parent or (i - 1)]
    if parent.info.exit then
      -- Entered up the shaft from a climbing area's arena
      local ex = parent.info.exit
      base = {
        x0 = lv.x0,
        x1 = lv.x1,
        y0 = lv.y0,
        y1 = lv.y1,
        entranceX = ex.cx,
        entranceY = lv.y1 - 230,
        shaftX0 = ex.x0,
        shaftX1 = ex.x1,
      }
    else
    local hatch = parent.info.shops[lv.side == "right" and 2 or 1].hatch
    base = {
      x0 = lv.x0,
      x1 = lv.x1,
      y0 = lv.y0,
      y1 = lv.y1,
      entranceX = hatch.cx,
      entranceY = lv.y0 + 96,
      shaftX0 = hatch.x0,
      shaftX1 = hatch.x1,
      shaftTop = hatch.y1 + 1,
    }
    end
  end
  base.level = lv.row
  base.palette = lv.theme.palette
  base.arena = lv.theme.arena
  base.glowCount = lv.theme.glowCount
  base.breakables = lv.theme.breakables
  base.mine = lv.theme.mine
  base.stalactites = lv.theme.stalactites
  base.gasPools = lv.theme.gasPools
  base.waterPools = lv.theme.waterPools
  base.lavaPools = lv.theme.lavaPools
  base.acidPools = lv.theme.acidPools
  base.monsters = lv.theme.monsters
  base.boss = lv.theme.boss
  base.swarms = lv.theme.swarms
  base.arenaFrac, base.arenaH, base.arenaWidth = lv.theme.arenaFrac, lv.theme.arenaH, lv.theme.arenaWidth
  base.bossReward = lv.theme.bossReward
  base.wounded = lv.theme.wounded
  base.prisoner = lv.theme.prisoner
  base.prisonerHeld = lv.theme.prisoner and require("src.meta").PEOPLE[lv.theme.prisoner].held or nil
  base.climb, base.open, base.profile, base.groundY, base.arenaCx = lv.theme.climb, lv.theme.open, lv.theme.profile, lv.theme.groundY, lv.theme.arenaCx
  if lv.theme.flood then
    -- (a lake entrance floods its whole width from the top, down into the area's own flood)
    local lake = lv.entry and lv.entry.lake and { x0 = lv.entry.x - lv.entry.half, x1 = lv.entry.x + lv.entry.half } or nil
    base.flood = { level = lv.theme.flood.level, lake = lake }
  end
  base.hasNext = childOf(i, 1) ~= nil
  return base
end

local function tick()
  if os.clock() > deadline then
    coroutine.yield()
  end
end

-- Runs the coroutine of level i for up to `budget` seconds (creating it first)
local function resume(i, budget)
  local lv = levels[i]
  if not lv.job then
    local area = areaFor(i)
    lv.area = area
    lv.job = coroutine.create(function()
      return cavegen.generate(world, area, baseSeed + (i - 1) * 7919, tick)
    end)
  end
  deadline = os.clock() + budget
  local ok, result = coroutine.resume(lv.job)
  if not ok then
    error(debug.traceback(lv.job, result))
  end
  if coroutine.status(lv.job) == "dead" then
    lv.job, lv.info = nil, result
    world.platforms = world.platforms or {}
    for _, p in ipairs(result.arena and result.arena.platforms or {}) do
      world.platforms[#world.platforms + 1] = p
    end
    for _, p in ipairs(result.platforms or {}) do
      world.platforms[#world.platforms + 1] = p
    end
  end
end

local function nextUnfinished()
  for i, lv in ipairs(levels) do
    if not lv.info then
      return i
    end
  end
  return nil
end

-- The area the hunter will need soonest, if one is coming up and isn't
-- built yet: within `reach` px above its top (or of a side branch's
-- entrance). Returns the area to work on now (its parent first, when the
-- parent is missing too).
local function needed(py, px, reach)
  for i, lv in ipairs(levels) do
    if not lv.info then
      local close
      if lv.entry then
        local ey = lv.entry.y or lv.y0
        close = px and math.abs(px - lv.entry.x) < reach and py > ey - 400 and py < lv.y1
      else
        close = py > lv.y0 - reach and py < lv.y1 and (not px or (px > lv.x0 - reach and px < lv.x1 + reach))
      end
      if close then
        local j = i
        while j > 1 and not levels[j].entry and levels[levels[j].parent or (j - 1)] and not levels[levels[j].parent or (j - 1)].info do
          j = levels[j].parent or (j - 1)
        end
        return j
      end
    end
  end
  return nil
end

-- Spends up to budget seconds on generation; call once per frame.
-- Without a position (nobody playing: the title screen, a menu) it works
-- through every area in order. With the hunter's position, an area he is
-- getting near (within ~3500 px: the next area down as soon as he is in the
-- one above it, a side branch as he nears its entrance) comes first, so it is
-- ready before catacombs.ensure would have to build it on the spot (a freeze
-- of seconds); the rest are built in order after it. `spare` (what is left
-- of this frame once its own work is done) is all it may use, so a busy
-- frame isn't made longer: building every area at a fixed few milliseconds a
-- frame was most of the lag in a fight. Only an area he is about to reach
-- gets time whether or not there is any to spare.
function catacombs.step(budget, px, py, spare)
  local i
  if py then
    i = needed(py, px, 3500)
    local least = 0
    if not i then
      i = nextUnfinished()
    elseif needed(py, px, 700) then
      least = 0.006
    elseif needed(py, px, 1400) then
      least = 0.003
    end
    budget = math.min(0.012, math.max(spare or budget, least))
    if budget < 0.0005 then
      return
    end
  else
    i = nextUnfinished()
  end
  if i then
    resume(i, budget)
  end
end

-- Completes generation of every area up to and including level `upTo` (default: all)
function catacombs.finish(upTo)
  for i = 1, math.min(upTo or #levels, #levels) do
    while not levels[i].info do
      resume(i, math.huge)
    end
  end
end

-- Completes area i and only what it needs: the areas whose shop hatches lead
-- to it (an area entered from the surface needs nothing)
function catacombs.generate(i)
  local lv = levels[i]
  if not lv or lv.info then
    return
  end
  if i > 1 and not lv.entry then
    catacombs.generate(lv.parent or (i - 1))
  end
  while not lv.info do
    resume(i, math.huge)
  end
end

-- Makes sure the area the hunter is heading into exists: any area whose top
-- is within 900 px below him is completed now if it isn't already
-- (Only as close as an area could come into view, 640 x 360 px round the
-- hunter, plus a margin: everything further off is left to catacombs.step,
-- a slice a frame. Building it here is a freeze of a second or more.)
local ENSURE_NEAR = 450
function catacombs.ensure(py, px)
  for i, lv in ipairs(levels) do
    -- (the first area is completed by the scene when the hunter goes underground)
    if i > 1 and not lv.info then
      if lv.entry then
        -- A side branch: when the hunter is near its crevice (or already in its rock)
        local ey = lv.entry.y or lv.y0
        if px and math.abs(px - lv.entry.x) < ENSURE_NEAR + 300 and py < lv.y1 and py > ey - ENSURE_NEAR and py < ey + 600 then
          catacombs.generate(i)
        end
      elseif py > lv.y0 - ENSURE_NEAR and py < lv.y1 + ENSURE_NEAR and (not px or (px > lv.x0 - ENSURE_NEAR and px < lv.x1 + ENSURE_NEAR)) then
        catacombs.generate(i)
      end
    end
  end
end

function catacombs.ready()
  return levels[1] ~= nil and levels[1].info ~= nil
end

-- An area's layout (default the first: where the F10 shortcut spawns), or
-- nil until it is generated
function catacombs.info(i)
  return levels[i or 1] and levels[i or 1].info
end

-- The area (1-based index) a world position lies in, or nil above them all.
-- x is optional (without it the first area at that depth is taken); a point
-- outside every area (a gap, or past the bottom) belongs to the nearest one.
function catacombs.levelAt(y, x)
  if not firstArea then
    return nil
  end
  local best, bestDist
  for i, lv in ipairs(levels) do
    local dy = y < lv.y0 and lv.y0 - y or (y > lv.y1 and y - lv.y1 or 0)
    local dx = 0
    if x then
      dx = x < lv.x0 and lv.x0 - x or (x > lv.x1 and x - lv.x1 or 0)
    end
    local d = dx * dx + dy * dy
    if d == 0 then
      return i
    end
    if not bestDist or d < bestDist then
      best, bestDist = i, d
    end
  end
  if y < firstArea.y0 then
    return nil -- (above the caves, outside any area: the surface or the open air)
  end
  return best or #levels
end

-- 1 inside a mountain (well in from its silhouette), 0.5 near its skin, 0 outside: how
-- dark the light should be there although the rock stands above the ground
function catacombs.indoors(x, y)
  for _, lv in ipairs(levels) do
    local th = lv.theme
    if th.indoors and th.profile and x >= lv.x0 and x <= lv.x1 and y >= lv.y0 and y <= lv.y1 then
      local xa, xb = th.profile(y)
      if xa and x >= xa and x <= xb and y >= lv.y0 then
        return (x >= xa + 24 and x <= xb - 24 and y >= lv.y0 + 24) and 1 or 0.5
      end
    end
  end
  return 0
end

-- Backdrop colour behind the rock at depth y (inside the areas); x picks the
-- side in row 4
function catacombs.backdrop(y, x)
  local i = catacombs.levelAt(y, x) or 1
  local t = THEMES[i] or THEMES[#THEMES]
  local d = math.min(1, math.max(0, (y - levels[i].y0) / ((levels[i].y1 - levels[i].y0 + 1) * 0.8)))
  return t.backTop[1] + (t.backDeep[1] - t.backTop[1]) * d,
    t.backTop[2] + (t.backDeep[2] - t.backTop[2]) * d,
    t.backTop[3] + (t.backDeep[3] - t.backTop[3]) * d
end

-- Scatters crates, chests, monsters and the shop stock through every area
-- that exists. Needs the physics world, so the scene calls it after setting
-- that up (and the area update calls it every frame after).
function catacombs.spawnProps()
  for i, lv in ipairs(levels) do
    local info = lv.info
    if info and not lv.propsSpawned then
      lv.propsSpawned = true
      -- Resting objects start asleep: their terrain outlines are only traced
      -- once something wakes them, instead of all in the same frame
      for _, s in ipairs(info.crates) do
        props.spawn("crate", s[1], s[2] - 7).body:setAwake(false)
      end
      for _, s in ipairs(info.ironCrates) do
        props.spawn("ironCrate", s[1], s[2] - 8.5).body:setAwake(false)
      end
      for _, group in ipairs(info.breakables or {}) do
        local def = props.defs[group.name]
        for _, s in ipairs(group.spots) do
          props.spawn(group.name, s[1], s[2] - def.height / 2 - 0.5, 0, lv.theme.glow).body:setAwake(false)
        end
      end
      if info.mine then
        minedecor.register(info.mine) -- (its lamps can be shot)
      end
      for _, cart in ipairs(info.mine and info.mine.carts or {}) do
        props.spawn("minecart", cart.x, cart.y - 7).body:setAwake(false)
      end
      for j, room in ipairs(info.shops) do
        shop.populate(room, world, lv.row, childOf(i, j))
        enemies.spawn("dummy", shop.dummySpot(room))
      end
      fluids.add(world, info)
      for _, it in ipairs(info.story or {}) do
        if it.loot then
          pickups.dropGold(it.x + (it.flip and -22 or 22), it.y - 6, it.loot) -- the dead man's purse
        end
      end
      -- Piranhas: a small school in every pool big enough (one per ~80 cells
      -- of 4 px, up to six), placed in cells with water above them too
      for _, pool in ipairs(info.water or {}) do
        local n = #pool.cells / 2
        local count = math.min(6, math.floor(n / 80))
        if count > 0 then
          local deep = {}
          local inPool = {}
          for c = 1, #pool.cells, 2 do
            inPool[pool.cells[c] .. "," .. pool.cells[c + 1]] = true
          end
          for c = 1, #pool.cells, 2 do
            local x, y = pool.cells[c], pool.cells[c + 1]
            if inPool[x .. "," .. (y - 4)] and inPool[(x - 4) .. "," .. y] and inPool[(x + 4) .. "," .. y] then
              deep[#deep + 1] = { x, y }
            end
          end
          for _ = 1, math.min(count, #deep) do
            local spot = table.remove(deep, love.math.random(#deep))
            enemies.spawn("piranha", spot[1] + 2, spot[2], 1 + (lv.row - 1) * 0.6, lv.row)
          end
        end
      end
      if info.arena and not info.flood then
        for _, br in ipairs(info.arena.braziers) do
          fluids.addBrazier(br.x, br.y)
        end
      end
      -- A flooded area: piranhas through the water, wherever the runs of water are
      if info.flood and #info.flood.runs > 0 then
        local runs = info.flood.runs
        for _ = 1, lv.theme.fish or 40 do
          local r = runs[love.math.random(#runs)]
          local x, y = (r[2] + love.math.random() * (r[3] - r[2])) * 2, r[1] * 2 + 1
          local inShop = false
          for _, room in ipairs(info.shops) do
            inShop = inShop or (x > room.x - 20 and x < room.x + room.w + 20 and y > room.y - 20 and y < room.y + room.h + 20)
          end
          if not inShop and r[3] - r[2] > 4 then
            enemies.spawn("piranha", x, y, 1 + (lv.row - 1) * 0.6, lv.row)
          end
        end
      end
      -- A prisoner's cage, with two of the things that keep them
      local pr = info.prisoner
      if pr then
        npcs.spawnCage(pr.id, pr.x, pr.y, pr.held, pr.top)
        for _, dx in ipairs({ -46, 52 }) do
          local gx = pr.x + dx
          if not world:isSolid(gx, pr.y - 12) then
            enemies.spawn("ghoul", gx, world:findGround(gx, pr.y - 20), 1 + (lv.row - 1) * 0.6, lv.row)
          end
        end
      end
      local a = info.area
      for _, c in ipairs(info.chests) do
        local depth = math.min(1, (c[2] - a.y0) / (a.y1 - a.y0) + (lv.row - 1) * 0.35)
        chests.spawn(c[1], c[2], depth)
      end
      local swarms = {}
      local spawned = {}
      for _, m in ipairs(info.enemies) do
        local swarm
        if m.swarm then
          swarms[m.swarm] = swarms[m.swarm] or {}
          swarm = swarms[m.swarm]
        end
        local e = enemies.spawn(m.kind, m.x, m.y, m.toughness, lv.row, swarm)
        spawned[#spawned + 1] = e
        e.reward = m.reward
        if m.boss then
          e.areaIndex = i
          if m.arena then
            e.arena = info.arena -- the boss stays inside it, and wakes when the hunter enters
          end
        end
      end
      -- A few of them are elite (src.enemies), more the deeper the area
      local elites = enemies.rollElites(spawned, lv.row)
      require("src.events").spawnArea(world, info, i, lv.row, elites, chests)
    end
  end
end

local propTimer = 0
local gravityScale = 1

-- Banners as the hunter reaches each area, the shop-reached message, and gas
function catacombs.update(player, dt)
  catacombs.spawnProps()
  fluids.update(dt, player, enemies)
  propTimer = propTimer - dt
  if propTimer <= 0 then
    propTimer = 0.3
    fluids.updateProps(props)
  end
  local px, py = player:center()
  local at = catacombs.levelAt(py, px)
  -- Gravity: lighter in the sky
  do
    local want = 1
    local lv = at and levels[at]
    if lv and lv.theme.gravity and px >= lv.x0 and px <= lv.x1 and py >= lv.y0 and py <= lv.y1 then
      want = lv.theme.gravity
    end
    gravityScale = gravityScale + (want - gravityScale) * math.min(1, dt * 3)
    config.gravity = config.baseGravity * gravityScale
    if physics.world then
      physics.world:setGravity(0, config.gravity)
    end
  end
  if at and not announced[at] and py > levels[at].y0 and (not levels[at].theme.indoors or catacombs.indoors(px, py) > 0.5) then
    announced[at] = true
    hud.showBanner(levels[at].theme.name, levels[at].theme.subtitle .. "  -  seed " .. baseSeed)
  end
  local b = player.body
  for i, lv in ipairs(levels) do
    local info = lv.info
    if info then
      local a = info.arena
      if a and not lv.arenaEntered and px > a.x0 and px < a.x1 and py > a.top and py < a.floorY then
        lv.arenaEntered = true
        local banner = lv.theme.arenaBanner or { "The Queen's Lair", "Kill the Sulfur Queen. She is immune to fire, and nothing stops her flying; her gas is not so safe" }
        hud.showBanner(banner[1], banner[2])
      end
      for j, s in ipairs(info.shops) do
        if b.x >= s.x and b.x + b.w <= s.x + s.w and b.y >= s.y and b.y + b.h <= s.y + s.h then
          if not lv.shopReached then
            lv.shopReached = true
            if lv.area.hasNext then
              hud.showBanner("The Shop", "Heal, buy, test guns on the dummy, then shoot the chain to open the hatch. Leaving closes the shop")
            else
              hud.showBanner("The Shop", "This path ends here for now. More depths are coming soon. Try your guns on the dummy")
            end
          end
          -- Choosing one of two shops seals the way to the other
          if #info.shops > 1 and not lv.chosen then
            lv.chosen = j
            for k, other in ipairs(info.shops) do
              if k ~= j then
                catacombs.seal(lv, other)
              end
            end
            hud.showBanner("The Way Behind You Collapses", "The other shop is out of reach unless you dig")
          end
        end
      end
    end
  end
end

-- Fills a shop's access shaft with rubble (breakable rock, so it can be dug out)
function catacombs.seal(lv, room)
  if room.sealed then
    return
  end
  room.sealed = true
  local sh = room.shaft
  local id = lv.theme.palette and lv.theme.palette.rock or materials.ROCK
  for y = sh.y0, sh.y1 do
    for x = sh.x0, sh.x1 do
      world:setRaw(x, y, id)
    end
  end
  world:repaintRegion(sh.x0, sh.y0, sh.x1, sh.y1)
  physics.rebuildRegion(sh.x0, sh.y0, sh.x1, sh.y1)
  audio.play("explosion", 0.8, 0.5)
  for _ = 1, 40 do
    effects.particle(sh.x0 + love.math.random() * (sh.x1 - sh.x0), sh.y0 + love.math.random() * 30, (love.math.random() - 0.5) * 60, 20 + love.math.random() * 60, 1.0, { 0.45, 0.42, 0.30 }, 300)
  end
end

-- The Queen is dead: the iron gates over both shafts open
function catacombs.openGates(lv)
  local a = lv.info.arena
  if a.open then
    return
  end
  a.open = true
  audio.play("hatch")
  for _, g in ipairs(a.gates) do
    for y = g.y0, g.y1 do
      for x = g.x0, g.x1 do
        world:setRaw(x, y, materials.AIR)
      end
    end
    world:repaintRegion(g.x0, g.y0, g.x1, g.y1)
    physics.rebuildRegion(g.x0, g.y0, g.x1, g.y1)
    for _ = 1, 30 do
      effects.particle(g.x0 + love.math.random() * (g.x1 - g.x0), g.y0 + 2, (love.math.random() - 0.5) * 40, 10 + love.math.random() * 50, 1.0, { 0.40, 0.41, 0.48 }, 520)
    end
  end
  local won = lv.theme.arenaWon or { "The Queen Has Fallen", "The gates are open. Two shops lie below, left and right: choose one" }
  hud.showBanner(won[1], won[2])
end

-- Is the point inside a shop room?
function catacombs.inShop(x, y)
  for _, lv in ipairs(levels) do
    for _, s in ipairs(lv.info and lv.info.shops or {}) do
      if x >= s.x and x <= s.x + s.w and y >= s.y and y <= s.y + s.h then
        return true
      end
    end
  end
  return false
end

function catacombs.shopReached()
  return levels[1] ~= nil and levels[1].shopReached == true
end

local function flicker(seed)
  local t = love.timer.getTime()
  return math.sin(t * 9 + seed) * 0.5 + math.sin(t * 23 + seed * 2) * 0.5
end

-- Two iron sconces with candles on each shop's back wall
local function candles(info)
  local list = {}
  for _, s in ipairs(info.shops) do
    list[#list + 1] = { s.x + 48, s.y + 30, 4 }
    list[#list + 1] = { s.x + math.floor(s.w * 0.33), s.y + 30, 4 }
    list[#list + 1] = { s.x + math.floor(s.w * 0.62), s.y + 30, 4 }
    list[#list + 1] = { s.x + s.w - 48, s.y + 30, 4 }
  end
  return list
end

-- view: { x, y, w, h } in world pixels; things outside it (plus margin) are skipped
local function visible(view, x, y, margin)
  return x > view.x - margin and x < view.x + view.w + margin and y > view.y - margin and y < view.y + view.h + margin
end

-- Is the area anywhere near the view? (Its decor, lights and flames are only
-- looked through then: going through every area's lists, a dozen areas of
-- them, each frame added up. The margin takes in its entrance shaft.)
local function inArea(lv, view)
  return view.x + view.w > lv.x0 - 600 and view.x < lv.x1 + 600 and view.y + view.h > lv.y0 - 1500 and view.y < lv.y1 + 600
end

function catacombs.addLights(lighting, view)
  fluids.addLights(lighting, view)
  local t = love.timer.getTime()
  for _, lv in ipairs(levels) do
    local info = inArea(lv, view) and lv.info
    if info then
      for i, c in ipairs(candles(info)) do
        if visible(view, c[1], c[2], 120) then
          lighting.add(c[1], c[2] - c[3] - 2, 120, 1, 0.68, 0.36, 1.0 + flicker(i) * 0.07)
        end
      end
      if info.mine then
        minedecor.addLights(lighting, info.mine, view)
      end
      if info.story then
        story.addLights(lighting, info.story, view)
      end
      local g, r = lv.theme.glow, lv.theme.glowRadius
      local strong = (lv.index > 1 and 0.75 or 0.6) * (lv.theme.glowLight or 1)
      for i, spot in ipairs(info.glows) do
        if visible(view, spot[1], spot[2], r) then
          lighting.add(spot[1], spot[2] - 3, r, g[1], g[2], g[3], strong + math.sin(t * 1.5 + i) * 0.08)
        end
      end
    end
  end
end

-- A cluster of sulfur crystals: little pale spikes (their tips glow, see drawEmissive)
local function drawCrystals(x, y, seed, stalk)
  for i = 0, 2 do
    local dx = (i - 1) * 2 + (seed + i) % 2
    local h = 3 + (seed + i * 5) % 5
    love.graphics.setColor(stalk[1] * (0.8 + 0.1 * i), stalk[2] * (0.8 + 0.1 * i), stalk[3])
    love.graphics.rectangle("fill", x + dx, y - h, 1, h)
  end
  love.graphics.setColor(stalk[1] * 0.6, stalk[2] * 0.6, stalk[3] * 0.6)
  love.graphics.rectangle("fill", x - 3, y - 1, 7, 1)
end

local function drawFungus(x, y, seed, stalk)
  -- A cluster of tiny caps on stalks
  for i = 0, 2 do
    local dx = (i - 1) * 2 + (seed + i) % 2
    local h = 2 + (seed + i * 3) % 3
    love.graphics.setColor(stalk)
    love.graphics.rectangle("fill", x + dx, y - h, 1, h)
  end
end

function catacombs.drawDecor(view)
  fluids.drawDecor(view)
  for _, lv in ipairs(levels) do
    local info = inArea(lv, view) and lv.info
    if info then
      local drawGlow = lv.theme.crystals and drawCrystals or drawFungus
      for i, g in ipairs(info.glows) do
        if visible(view, g[1], g[2], 8) then
          drawGlow(g[1], g[2], i, lv.theme.stalk)
        end
      end
      if info.mine then
        minedecor.draw(info.mine, view)
      end
      if info.story then
        story.draw(info.story, view)
      end
      for _, s in ipairs(info.shops) do
        if visible(view, s.x + s.w / 2, s.y + s.h / 2, 400) then
          -- Empty shelves on the back wall, each with a darker underside
          for i = 0, 2 do
            local y = s.y + 32 + i * 16
            love.graphics.setColor(0.36, 0.25, 0.17)
            love.graphics.rectangle("fill", s.x + s.w - 112, y, 70, 2)
            love.graphics.setColor(0.20, 0.14, 0.10)
            love.graphics.rectangle("fill", s.x + s.w - 112, y + 2, 70, 1)
          end
        end
      end
      if visible(view, view.x + view.w / 2, view.y + view.h / 2, 3000) then
        -- Sconce brackets and candle sticks
        for _, c in ipairs(candles(info)) do
          if visible(view, c[1], c[2], 8) then
            love.graphics.setColor(0.14, 0.12, 0.14)
            love.graphics.rectangle("fill", c[1] - 2, c[2] + 1, 5, 1)
            love.graphics.rectangle("fill", c[1], c[2] + 2, 1, 4)
            love.graphics.setColor(0.82, 0.78, 0.66)
            love.graphics.rectangle("fill", c[1], c[2] - c[3], 1, c[3] + 1)
          end
        end
      end
      -- The arena's one-way platforms: slabs of the area's rock
      if (info.arena and info.arena.platforms) or (info.platforms and #info.platforms > 0) then
        local def = materials.defs[lv.theme.palette and lv.theme.palette.rock or materials.ROCK]
        local slabs = {}
        for _, p in ipairs(info.arena and info.arena.platforms or {}) do
          slabs[#slabs + 1] = p
        end
        for _, p in ipairs(info.platforms or {}) do
          slabs[#slabs + 1] = p
        end
        for _, p in ipairs(slabs) do
          if visible(view, (p.x0 + p.x1) / 2, p.y, 60) then
            for x = p.x0, p.x1 do
              local thick = 5 + math.floor(love.math.noise(x * 0.2, p.y) * 3)
              love.graphics.setColor(def.topColor[1], def.topColor[2], def.topColor[3])
              love.graphics.rectangle("fill", x, p.y, 1, 1)
              love.graphics.setColor(def.color[1] * 0.85, def.color[2] * 0.85, def.color[3] * 0.85)
              love.graphics.rectangle("fill", x, p.y + 1, 1, thick - 1)
            end
          end
        end
      end
      -- The arena's braziers: a stone bowl on a short pedestal (the fire is
      -- real fire, see src.fluids)
      if info.arena then
        for _, br in ipairs(info.arena.braziers) do
          if visible(view, br.x, br.y, 12) then
            love.graphics.setColor(0.28, 0.27, 0.32)
            love.graphics.rectangle("fill", br.x - 2, br.y - 9, 5, 9)
            love.graphics.rectangle("fill", br.x - 6, br.y - 1, 13, 1)
            love.graphics.setColor(0.40, 0.39, 0.46)
            love.graphics.rectangle("fill", br.x - 6, br.y - 12, 13, 4)
            love.graphics.rectangle("fill", br.x - 4, br.y - 9, 9, 1)
            love.graphics.setColor(0.18, 0.17, 0.21)
            love.graphics.rectangle("fill", br.x - 5, br.y - 12, 11, 1)
          end
        end
      end
    end
  end
end

function catacombs.drawEmissive(view)
  fluids.drawEmissive(view)
  fluids.drawGlints(require("src.lighting").list())
  for _, lv in ipairs(levels) do
    local info = inArea(lv, view) and lv.info
    if info then
      local g = lv.theme.glow
      if info.mine then
        minedecor.drawEmissive(info.mine, view)
      end
      if info.story then
        story.drawEmissive(info.story, view)
      end
      for i, spot in ipairs(info.glows) do
        if visible(view, spot[1], spot[2], 8) then
          for j = 0, 2 do
            local dx = (j - 1) * 2 + (i + j) % 2
            love.graphics.setColor(math.min(1, g[1] + 0.1), math.min(1, g[2] + 0.05), math.min(1, g[3] + 0.05))
            if lv.theme.crystals then
              -- A bright tip on each crystal
              local h = 3 + (i + j * 5) % 5
              love.graphics.rectangle("fill", spot[1] + dx, spot[2] - h, 1, 1)
            else
              -- Glowing caps on the fungus stalks
              local h = 2 + (i + j * 3) % 3
              love.graphics.rectangle("fill", spot[1] + dx - (j == 1 and 1 or 0), spot[2] - h - 1, j == 1 and 3 or 2, 1)
            end
          end
        end
      end
      for i, c in ipairs(candles(info)) do
        local top = c[2] - c[3]
        love.graphics.setColor(1, 0.72, 0.28)
        love.graphics.rectangle("fill", c[1], top - 2 - (flicker(i) > 0.3 and 1 or 0), 1, 2)
        love.graphics.setColor(1, 0.95, 0.7)
        love.graphics.rectangle("fill", c[1], top - 1, 1, 1)
      end
    end
  end
end

-- Water and smoke, in front of the hunter
function catacombs.drawFront(view)
  fluids.drawFront(view)
end

function catacombs.drawScreen(toScreen, font)
  for _, lv in ipairs(levels) do
    if lv.info then
      for _, s in ipairs(lv.info.shops) do
        local sx, sy = toScreen(s.x + s.w / 2, s.y + 19)
        local sw, sh = love.graphics.getDimensions()
        if sx > -100 and sx < sw + 100 and sy > -50 and sy < sh + 50 then
          local text = "SHOP"
          love.graphics.setFont(font)
          love.graphics.setColor(0, 0, 0, 0.8)
          love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2) + 2, math.floor(sy) + 2)
          love.graphics.setColor(0.97, 0.98, 1)
          love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2), math.floor(sy))
        end
      end
    end
  end
end

-- An area's name (for the save files' "deepest reached")
-- Whether area i's monsters and props have been placed
function catacombs.spawned(i)
  return levels[i] ~= nil and levels[i].propsSpawned == true
end

function catacombs.areaName(i)
  return THEMES[i] and THEMES[i].name or nil
end

return catacombs
