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
local parallax = require("src.parallax")
local bossbg = require("src.bossbg")
local bake = require("src.bake")
local pickups = require("src.pickups")
local glyphs = require("src.glyphs")
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
    name = "The Old Mine",
    grass = true, -- grass along the earth (src.grass); the first three areas only
    subtitle = "Area 1",
    prisoner = "prospector", -- buried by a cave-in in the old mine (src.npcs)
    ambient = { 0.20, 0.18, 0.25 },
    fx = { aberr = 0.7 },
    palette = nil, -- the default rock and dirt
    glow = { 0.35, 0.95, 0.85 }, -- teal fungus
    glowCount = 150,
    glowRadius = 34,
    beacons = { count = 26 }, -- more of the mine's hung oil lamps
    stalk = { 0.55, 0.62, 0.55 },
    backTop = { 0.10, 0.08, 0.14 },
    backDeep = { 0.06, 0.05, 0.09 },
    pillars = { { 0.03, 0.025, 0.05 }, { 0.16, 0.13, 0.22 }, { 0.10, 0.08, 0.15 } },
    monsters = { ghoul = 38, bat = 28, spitter = 14, hopper = 6, miner = 28, roller = 10, worm = 12, wisp = 8 }, -- per 1920x3680; an old mine: skeletal miners, rollers and worms in the rock
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
    grass = true,
    subtitle = "Area 2",
    wounded = true, -- a dying hunter lies somewhere in the fen (src.events)
    prisoner = "gunsmith", -- caged somewhere in the fen (src.npcs)
    ambient = { 0.09, 0.12, 0.18 }, -- darker and colder
    fx = { shadow = { 0.84, 0.95, 1.16 }, light = { 1.0, 1.02, 1.05 }, sat = 0.9, vig = 0.45 },
    palette = { rock = materials.SLATE, dirt = materials.BLUECLAY },
    glow = { 0.35, 1.0, 0.45 }, -- green mushrooms, lots of them
    glowLight = 0.5, -- (480 of them: half the light each, or the fen is overpowered by green)
    glowCount = 480,
    glowRadius = 40,
    beacons = { count = 18 },
    stalk = { 0.45, 0.62, 0.50 },
    backTop = { 0.045, 0.06, 0.105 },
    backDeep = { 0.03, 0.04, 0.075 },
    pillars = { { 0.02, 0.03, 0.05 }, { 0.10, 0.14, 0.22 }, { 0.06, 0.08, 0.14 } },
    monsters = { ghoul = 20, bat = 14, spitter = 20, hopper = 44, bloater = 10, worm = 12, roller = 14, miner = 5, wisp = 8 }, -- a fen: hoppers everywhere
    boss = "matron",
    waterPools = 60,
    swarms = { swarmbat = 2 },
    breakables = { { "sporePod", 36 }, { "urn", 10 }, { "pouch", 14 }, { "lantern", 8 } }, -- glowing spore pods in the fen
    stalactites = 70,
  },
  {
    name = "The Sulfur Vents",
    grass = true,
    subtitle = "Area 3",
    prisoner = "apothecary", -- caged, coughing, somewhere in the fumes (src.npcs)
    ambient = { 0.22, 0.22, 0.13 }, -- a murky yellow-green
    fx = { shadow = { 0.96, 1.06, 0.80 }, light = { 1.1, 1.06, 0.84 }, sat = 1.1, aberr = 0.9 },
    palette = { rock = materials.SULFUR, dirt = materials.BILECLAY },
    glow = { 1.0, 0.92, 0.35 }, -- sulfur crystals
    glowLight = 0.4, -- (yellow reads far brighter than the other areas' tints, so they give less light)
    glowCount = 220,
    glowRadius = 36,
    beacons = { count = 18 },
    crystals = true,
    stalk = { 0.80, 0.72, 0.30 },
    backTop = { 0.085, 0.09, 0.04 },
    backDeep = { 0.05, 0.055, 0.025 },
    pillars = { { 0.035, 0.035, 0.012 }, { 0.20, 0.20, 0.08 }, { 0.11, 0.11, 0.05 } },
    monsters = { ghoul = 14, bat = 10, spitter = 12, hopper = 8, bloater = 46, wisp = 40, worm = 12, roller = 8, miner = 8 }, -- gas bags and fire wisps
    boss = "queen", -- the Sulfur Queen, in the arena that fills the last quarter
    glyph = "sulfur",
    defy = "Caverns", -- (the pedestal at the middle of the arena says "Defy the ...")
    arenaParallax = "acid", -- the arena's own far scenery (src.bossbg), blended in over the area's
    arenaBack = { 0.05, 0.065, 0.02 }, -- ...and its own backdrop colour
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
    decor = "cinder", -- baked dressing and rock colouring (src.decor)
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
    waterPools = 0, -- (none: the Warrens are lava country)
    lavaPools = 26,
    prisoner = "taxidermist", -- caged in the ash (src.npcs): found once the board is up
    breakables = { { "emberPot", 30 }, { "urn", 16 }, { "pouch", 14 }, { "skullCandle", 14 }, { "lantern", 8 } },
    stalactites = 80,
  },
  {
    -- Right of the Queen's arena (area 4b): a flooded slate maze
    name = "The Drowned Halls",
    decor = "drowned", -- baked dressing and rock colouring (src.decor)
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
    monsters = { ghoul = 10, bat = 10, spitter = 16, hopper = 52, bloater = 18, worm = 12, roller = 10, miner = 4, wisp = 8 },
    swarms = { swarmbat = 3 },
    waterPools = 100,
    breakables = { { "sporePod", 30 }, { "geode", 12 }, { "urn", 16 }, { "pouch", 14 }, { "lantern", 12 } },
    stalactites = 90,
  },
  {
    -- Not on the main road: reached by a crevice in the east desert. An old
    -- quarry: pale cut sandstone and spoil, dust, amber lamps and crystals,
    -- the miners' ghosts and their blasting powder.
    name = "The Quarry",
    decor = "quarry", -- baked dressing and rock colouring (src.decor)
    subtitle = "A side road",
    prisoner = "cartographer", -- a lost surveyor, caged in the workings (src.npcs)
    ambient = { 0.22, 0.17, 0.12 },
    fx = { shadow = { 1.0, 0.95, 0.88 }, light = { 1.1, 1.02, 0.88 }, sat = 1.04, aberr = 0.5 },
    palette = { rock = materials.SANDSTONE, dirt = materials.TAILINGS },
    glow = { 1.0, 0.72, 0.28 }, -- amber crystals
    glowCount = 110,
    glowRadius = 36,
    beacons = { count = 30 },
    crystals = true,
    stalk = { 0.75, 0.6, 0.38 },
    backTop = { 0.16, 0.11, 0.08 },
    backDeep = { 0.09, 0.06, 0.05 },
    pillars = { { 0.05, 0.035, 0.03 }, { 0.26, 0.18, 0.12 }, { 0.15, 0.10, 0.07 } },
    monsters = { ghoul = 16, bat = 10, miner = 44, roller = 24, worm = 18, spitter = 6, wisp = 8, wraith = 14, cairncrab = 22 },
    swarms = { swarmbat = 2 },
    waterPools = 8,
    breakables = { { "urn", 8 }, { "pouch", 14 }, { "lantern", 10 }, { "skullCandle", 6 }, { "tntBarrel", 30 }, { "tntBarrel", 12 }, { "crate", 18 } },
    mine = true,
    stalactites = 60,
    parallax = 6, -- (the first area's far scenery, in this area's colours)
    track = 1, -- (and its music)
  },
  {
    -- Under the Quarry: the foreman's hall, a boss chamber sized like the
    -- Queen's. For now its boss is the Warden; he guards the Diving Helm.
    name = "The Foreman's Hall",
    decor = "quarry", -- baked dressing and rock colouring (src.decor)
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
    arenaH = 460,
    arenaWidth = 0.8, -- (of the Quarry's narrow width: the hall is as wide as ever)
    arenaShape = "rect", -- a walled hall: semi-flat rocky floor, stalactites overhead
    noPlatforms = true,
    arenaBanner = { "The Marble Hall", "A colossus of marble stands dormant at the middle of the hall. It guards the way into the flooded caverns" },
    boss = "golem",
    glyph = "stone",
    defy = "Stone",
    bossReward = "diving_helm",
    arenaWon = { "The Colossus Has Fallen", "The gates are open. Take the Diving Helm: the flooded caverns lie beyond" },
    stalactites = 30,
    parallax = 6,
    arenaParallax = "quarryhall", -- (src.bossbg)
    track = 3,
  },
  {
    -- The west: caverns under a lake in the west desert. The lake simply
    -- descends into the top of them, and all of it is water; with no breathing
    -- gear the hunter drowns, so the water is the lock.
    name = "The Flooded Caverns",
    decor = "flooded", -- baked dressing and rock colouring (src.decor)
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
    prisoner = "sawbone", -- floating on the water (src.npcs)
    pillars = { { 0.02, 0.03, 0.05 }, { 0.10, 0.15, 0.22 }, { 0.06, 0.09, 0.14 } },
    monsters = { miner = 14, wisp = 6 }, -- (only skeleton miners and wisps on dry ground: the rest is the water's)
    flood = { level = 150 }, -- every open cell below this (px under the top) is water
    fish = 60, -- piranhas in the water
    aquatic = { jellyfish = 30, angler = 12, urchin = 16 }, -- and the rest of what swims
    mine = true,
    breakables = { { "kelp", 60 }, { "seaSponge", 36 }, { "urn", 6 }, { "pouch", 8 }, { "crate", 10 } },
    stalactites = 60,
    parallax = 7,
    track = 2,
  },
  {
    -- Under the galleries: a big flooded chamber for an aquatic boss. A
    -- placeholder boss for now (the Matron).
    name = "The Deep",
    decor = "flooded", -- baked dressing and rock colouring (src.decor)
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
    breakables = { { "kelp", 24 }, { "seaSponge", 14 } },
    arena = true,
    arenaFrac = 0.08,
    arenaH = 1000,
    arenaWidth = 0.72,
    arenaBanner = { "The Deep", "Something old and large turns in the dark water" },
    arenaWon = { "The Biggest Fish Has Fallen", "The gates are open. The water is still at last" },
    boss = "bigfish",
    glyph = "deep",
    arenaShape = "round", -- (an oval of water, no ledges)
    noPlatforms = true,
    defy = "Depths",
    flood = { level = 90 },
    fish = 30,
    stalactites = 20,
    parallax = 7,
    arenaParallax = "deep", -- the arena's own far scenery (src.bossbg)
    track = 5,
  },
  {
    -- A mountain at the east end of the desert, entered by a doorway at the
    -- top of a long ramp. A deep cave that climbs, on ladders of platforms, to
    -- the summit, where a boss guards the way up into the sky.
    name = "The Needle",
    decor = "needle", -- baked dressing and rock colouring (src.decor)
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
    monsters = { bat = 12, ghoul = 10, spitter = 6, miner = 8, roller = 5, worm = 6, wisp = 6, crow = 34, cragram = 18, dustdevil = 14, gargoyle = 16 },
    swarms = { swarmbat = 3 },
    waterPools = 4,
    breakables = { { "urn", 8 }, { "pouch", 12 }, { "lantern", 10 }, { "skullCandle", 6 }, { "tntBarrel", 12 }, { "crate", 14 } },
    stalactites = 100,
    climb = true, -- the routes go up (see src.cavegen)
    indoors = true, -- dark inside, though it stands above the ground
    profile = function(y)
      -- The mountain's silhouette: the plain's rock below the ground line, a
      -- flank rising from x 5900 to x 6900 at the summit (7400 px up) above it
      if y < -6900 then
        return nil
      end
      if y >= 500 then
        return 5800, 8599
      end
      return math.floor(5900 + (500 - y) * (1000 / 7400)), 8599
    end,
    groundY = 500,
    arena = true,
    arenaFrac = 0.04,
    arenaCx = 7880,
    arenaWidth = 0.46,
    arenaH = 400,
    arenaShape = "round", -- an oval chamber, entered from its lower corners
    platformStyle = "edges", -- its ledges stagger round the outer edges, the middle left open
    caveInset = 300, -- the caves start this much further in from the mountain's face
    fog = 22, -- banks of dense fog in the caves (src.fog)
    arenaDecor = true, -- the Dark Hunter's hall: the shop's void behind the oval, violet crystals round it
    noBraziers = true, -- (no orange fires in it)
    arenaBanner = { "The Summit", "Something wearing your shape waits at the top. The way up lies beyond it" },
    arenaWon = { "The Crow Rider Has Fallen", "The way up to the summit is open. Bring the proof of every boss: the sky waits there" },
    glyph = "hunter", -- (src.glyphs: what a boss leaves behind; the Dark Hunter can fall before the others)
    boss = "darkhunter", -- the Dark Hunter, then the Crow Rider (src.darkhunter)
    bossReward = "akimbo", -- (and beating him unlocks it for good)
    defy = "Heights",
    parallax = 9, -- the inside of a mountain, with holes peeping out to the sky (src.parallax)
    track = 1,
  },
  {
    -- The sky, above the mountain: islands and spires in open air, with low gravity
    name = "The Cloud Reaches",
    decor = "sky", -- baked dressing and rock colouring (src.decor)
    subtitle = "Where the air thins",
    ambient = { 0.55, 0.48, 0.5 },
    fx = { shadow = { 0.95, 0.96, 1.06 }, light = { 1.08, 1.02, 0.92 }, sat = 1.05, aberr = 0.5 },
    palette = { rock = materials.CLOUDBANK, dirt = materials.CLOUD }, -- the ground is cloud
    glow = { 0.75, 0.9, 1.0 },
    glowCount = 60,
    glowRadius = 38,
    crystals = true,
    stalk = { 0.7, 0.8, 0.9 },
    backTop = { 0.30, 0.22, 0.28 },
    backDeep = { 0.30, 0.22, 0.28 },
    pillars = { { 0.2, 0.15, 0.2 }, { 0.5, 0.4, 0.45 }, { 0.35, 0.27, 0.32 } },
    space = true, -- the sky darkens into space toward the top (src.scenes.overworld)
    monsters = { bat = 30, ghoul = 10, spitter = 14, wisp = 12 },
    swarms = { swarmbat = 6, wisp = 3 },
    breakables = { { "urn", 10 }, { "pouch", 12 }, { "lantern", 8 }, { "crate", 12 } },
    stalactites = 20,
    open = true, -- islands and spires, no caves (see src.cavegen)
    gravity = 0.35, -- a third of the pull: high jumps, long recoil
    -- The Champion of the Heavens waits in a floating citadel of cloudstone (an oval hall entered from its lower corners)
    boss = "starwarden", -- (src.starwarden)
    summit = true, -- the chamber on the mountain's top (src.summit)
    arena = true,
    arenaFrac = 0.22,
    arenaCx = 4100,
    arenaWidth = 0.105,
    arenaH = 560,
    arenaShape = "round",
    platformStyle = "edges",
    noBraziers = true,
    defy = "Heavens",
    arenaBanner = { "The Citadel of Stars", "The Champion of the Heavens guards the way. The gods do not like to be defied" },
    arenaWon = { "The Champion Has Fallen", "The heavens are silent. Something in the sky has changed" },
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
  parallax = 4, -- (the Warrens' far scenery)
  -- The way for those who are ready: a lot more of everything, tougher, and thrice the elites
  spawnMul = 1.7,
  toughMul = 1.8,
  eliteMul = 3,
  subtitle = "Area 5 - under the Cinder Warrens",
  ambient = { 0.26, 0.15, 0.11 },
  glowCount = 300,
  lavaPools = 44,
  prisoner = false, -- (the Warrens' cage is enough)
  monsters = { ghoul = 20, bat = 12, spitter = 14, wisp = 44, worm = 18, roller = 24, miner = 28 },
  breakables = { { "emberPot", 44 }, { "urn", 12 }, { "pouch", 12 }, { "skullCandle", 18 }, { "lantern", 8 } },
  stalactites = 60,
})
THEMES[13] = derive(THEMES[5], {
  name = "The Silt Vaults",
  parallax = 5, -- (the Drowned Halls' far scenery)
  spawnMul = 1.7,
  toughMul = 1.8,
  eliteMul = 3,
  subtitle = "Area 5 - under the Drowned Halls",
  ambient = { 0.06, 0.11, 0.15 },
  waterPools = 150,
  monsters = { ghoul = 8, bat = 8, spitter = 18, hopper = 60, bloater = 26, worm = 14, roller = 8, miner = 6, wisp = 8 },
  stalactites = 100,
})

local AREA_W, AREA_H = 2880, 3100
-- The Quarry is a narrow dungeon: deep, but only QUARRY_W wide (centred where it always was)
local QUARRY_W = 1800
local QUARRY_X = AREA_W + math.floor((AREA_W - QUARRY_W) / 2)
local PATH_GAP = 644 -- the rock between the two paths below the Queen
local LAYOUT = {
  { x = 0, y = 0, w = AREA_W, h = AREA_H, tier = 1 },
  { x = 0, y = AREA_H, w = AREA_W, h = AREA_H, tier = 2 },
  { x = 0, y = 2 * AREA_H, w = AREA_W, h = AREA_H, tier = 3 },
  -- (the two paths below the Queen stand apart, with diggable rock between: each
  -- one's way in is its top corner nearest the middle, under its shop's hatch)
  { x = 0, y = 3 * AREA_H, w = AREA_W / 2, h = AREA_H, tier = 4, side = "left", parent = 3, gapRight = PATH_GAP },
  { x = AREA_W / 2 + PATH_GAP, y = 3 * AREA_H, w = AREA_W / 2, h = AREA_H, tier = 4, side = "right", parent = 3, gapLeft = PATH_GAP },
  -- The Old Quarry: a side branch under the east desert, entered from a
  -- crevice on the surface (entry: its x and half-width). Shorter than the
  -- main areas. rank is what it counts as for "deepest reached".
  { x = QUARRY_X, y = 0, w = QUARRY_W, h = 3450, tier = 2, rank = 2, entry = { x = 4300, half = 19 } },
  -- Under the Quarry: its boss's hall, about the size of the Queen's chamber
  { x = QUARRY_X, y = 3450, w = QUARRY_W, h = 800, tier = 3, rank = 3, parent = 6 },
  -- The west: a flooded mine, entered from a shaft in the west desert (the
  -- hunter drowns without the Diving Helm), and a flooded chamber under it
  { x = -2800, y = 0, w = 2400, h = 2600, tier = 3, rank = 3, entry = { x = -900, half = 380, neck = 50, lake = true } },
  { x = -2800, y = 2600, w = 2400, h = 1800, tier = 4, rank = 4, parent = 8 },
  -- The mountain at the east end: a doorway at the top of a ramp (entry.x, entry.y is
  -- inside, behind the doorway), climbing to a summit boss. Its rock above the ground
  -- line is the mountain you see from the desert.
  -- (chamber: where the long passage in from the doorway opens up, about half
  -- the mountain's width in)
  { x = 5800, y = -7660, w = 2800, h = 8000, tier = 4, rank = 4, entry = { x = 6320, y = 380, walk = true, chamber = 7260 } },
  -- The sky, over the mountain's summit and most of the desert, reached through the
  -- gate above the summit boss's arena
  { x = 0, y = -9060, w = 8600, h = 1400, tier = 5, rank = 5, parent = 10 },
  -- The way on below each post-Queen path (their last shops get hatches)
  { x = 0, y = 4 * AREA_H, w = AREA_W / 2, h = AREA_H, tier = 5, parent = 4, gapRight = PATH_GAP },
  { x = AREA_W / 2 + PATH_GAP, y = 4 * AREA_H, w = AREA_W / 2, h = AREA_H, tier = 5, parent = 5, gapLeft = PATH_GAP },
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

-- The entrances with the name of the area behind each: { x, y (for a doorway),
-- walk, lake, name }
function catacombs.namedEntries()
  local list = {}
  for i, l in ipairs(LAYOUT) do
    if l.entry then
      list[#list + 1] = { x = l.entry.x, y = l.entry.y, walk = l.entry.walk, lake = l.entry.lake, name = THEMES[i] and THEMES[i].name or "" }
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
-- The bosses whose fights have a theme of their own (src.audio); the Dark Hunter's is played by src.darkhunter
local BOSS_MUSIC = { queen = true, golem = true, bigfish = true } -- (the Dark Hunter and the Champion play their own through src.audio.setBoss)

function catacombs.count()
  return #levels
end

-- Each area has a name of its own, made up fresh for every run from words that
-- suit its theme (shown when it is entered, in place of "Area 3")
local TITLE_WORDS = {
  ["The Old Mine"] = { { "Rusted", "Forgotten", "Hollow", "Lantern", "Tallow", "Cracked", "Timbered", "Widow's" }, { "Gallery", "Drift", "Shaft", "Seam", "Winze", "Cutting", "Adit", "Stope" } },
  ["The Sunken Hollows"] = { { "Whispering", "Glimmer", "Mossback", "Sporefall", "Dripping", "Pale", "Lanternroot", "Weeping" }, { "Grotto", "Fen", "Hollow", "Warren", "Bower", "Sink", "Mere", "Undergrowth" } },
  ["The Sulfur Vents"] = { { "Yellow", "Choking", "Rotten", "Hissing", "Bitter", "Brimstone", "Pallid", "Fuming" }, { "Flues", "Chimneys", "Breath", "Stacks", "Pits", "Vents", "Reek", "Chambers" } },
  ["The Cinder Warrens"] = { { "Smoldering", "Ashen", "Scorched", "Blackened", "Ember", "Molten", "Charred", "Sooty" }, { "Burrows", "Kilns", "Tunnels", "Crucibles", "Hearths", "Galleries", "Runs", "Furnaces" } },
  ["The Drowned Halls"] = { { "Sunken", "Dripping", "Tidal", "Waterlogged", "Silent", "Brine", "Mirrored", "Cold" }, { "Colonnade", "Cloisters", "Vestibule", "Nave", "Passage", "Arcade", "Crypts", "Atrium" } },
  ["The Quarry"] = { { "Broken", "Chalk", "Grey", "Hewn", "Blasted", "Dusty", "Scarred", "Terraced" }, { "Terraces", "Cuttings", "Ledges", "Faces", "Benches", "Pits", "Slabs", "Yards" } },
  ["The Foreman's Hall"] = { { "Iron", "Silent", "Bellless", "Overseer's", "Last", "Cold", "Tallied", "Shuttered" }, { "Office", "Hall", "Muster", "Chamber", "Roll-Room", "Gantry", "Court", "Forum" } },
  ["The Flooded Caverns"] = { { "Glowing", "Inky", "Abyssal", "Drifting", "Tideless", "Lantern-fish", "Bruised", "Cobalt" }, { "Depths", "Shallows", "Basin", "Reach", "Gulf", "Trench", "Lagoon", "Deeps" } },
  ["The Deep"] = { { "Black", "Bottomless", "Sleeping", "Old", "Crushing", "Maw of the", "Silent", "Leviathan's" }, { "Trench", "Abyss", "Floor", "Hold", "Dark", "Basin", "Deep", "Throat" } },
  ["The Needle"] = { { "Wind-Cut", "Giddy", "Narrow", "Sky-Bound", "Windward", "Spired", "Cragged", "Last" }, { "Ascent", "Stair", "Spire", "Climb", "Ridgeway", "Chimney", "Flue", "Pinnacle" } },
  ["The Cloud Reaches"] = { { "Drifting", "Thin", "Silver", "Floating", "Breathless", "Pale", "Lofty", "Windblown" }, { "Isles", "Spires", "Shelves", "Banks", "Heights", "Steps", "Terraces", "Shoals" } },
  ["The Ember Foundry"] = { { "Roaring", "White-Hot", "Slag", "Forge", "Glowing", "Iron-Fed", "Choking", "Bellows" }, { "Floor", "Casting-Hall", "Foundry", "Crucible", "Works", "Pour", "Smelter", "Furnace-Row" } },
  ["The Silt Vaults"] = { { "Muddy", "Sinking", "Buried", "Murky", "Slumped", "Silted", "Rotting", "Croaking" }, { "Vaults", "Cellars", "Strongrooms", "Crypts", "Basements", "Bogs", "Sumps", "Undercroft" } },
}

function catacombs.areaTitle(i)
  local lv = levels[i]
  if not lv then
    return ""
  end
  if not lv.title then
    local words = TITLE_WORDS[lv.theme.name]
    if words then
      local rng = love.math.newRandomGenerator((baseSeed or 0) * 31 + i * 7919)
      rng:random()
      lv.title = words[1][rng:random(1, #words[1])] .. " " .. words[2][rng:random(1, #words[2])]
    else
      lv.title = lv.theme.subtitle
    end
  end
  return lv.title
end

-- The mountain-shaped areas standing in the open air: { index, theme, y0, y1 }
function catacombs.climbLevels()
  local list = {}
  for i, lv in ipairs(levels) do
    if lv.theme.climb and lv.theme.profile then
      list[#list + 1] = { index = i, theme = lv.theme, y0 = lv.y0, y1 = lv.y1 }
    end
  end
  return list
end

function catacombs.theme(i)
  return THEMES[i] or THEMES[#THEMES]
end

-- The box of area i's boss arena when it has far scenery of its own (theme.arenaParallax):
-- x0, y0, x1, y1 (nil when it has none, or the area is not generated yet)
function catacombs.arenaBox(i)
  local lv = levels[i]
  local a = lv and lv.info and lv.info.arena
  if a and lv.theme.arenaParallax then
    return a.x0, a.top, a.x1, a.floorY
  end
end

-- The sky area that darkens into space at its top: { x0, x1, y0, y1 }, or nil
function catacombs.spaceBand()
  for _, lv in ipairs(levels) do
    if lv.theme.space then
      return lv
    end
  end
  return nil
end

-- An area's rectangle: x0, y0, x1, y1 (nil if the layout has no such area)
function catacombs.bounds(i)
  local lv = levels[i]
  if lv then
    return lv.x0, lv.y0, lv.x1, lv.y1
  end
end

local zoomNow, zoomWant, zoomT = 1, 1, 0 -- (the fight camera: see updateBossCamera)
local updateBossCamera

-- Starts the areas under the surface. first: the first area's rectangle and
-- entrance (see cavegen.generate); tiers: how deep the layout goes (4 is the
-- whole of it, 3 stops after the Sulfur Vents).
function catacombs.start(w, first, seed, tiers)
  world, firstArea, baseSeed = w, first, seed
  minedecor.clear()
  audio.setBoss(false) -- (a fight left by a death must not play on into the next run)
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
        gapLeft = l.gapLeft,
        gapRight = l.gapRight,
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
        if lv.boss then
          lv.boss.state = "done"
        end
        if BOSS_MUSIC[lv.theme.boss] then
          audio.setBoss(false)
        end
        if lv.theme.glyph then
          -- (the proof of the kill, left where it fell)
          require("src.pickups").dropGlyph(e.body.x + e.body.w / 2 - 14, e.body.y + e.body.h / 2 - 6, lv.theme.glyph, -30, -80)
        end
        catacombs.openGates(lv)
        if lv.theme.boss == "starwarden" then
          -- The champion of the heavens is down: the world changes (the sun is eclipsed, the epic items turn up)
          require("src.meta").skyBeaten()
          local items = require("src.items")
          local epics = {}
          for _, id in ipairs(items.order) do
            if items.defs[id].rarity == "epic" then
              epics[#epics + 1] = id
            end
          end
          for k = 1, 2 do
            if #epics > 0 then
              require("src.pickups").dropItem(e.body.x + e.body.w / 2 + (k - 1.5) * 14, e.body.y + e.body.h / 2, items.new(epics[love.math.random(#epics)]), (k - 1.5) * 50, -110)
            end
          end
        end
      end
    end
  end
  require("src.camera").setFocus(nil)
  require("src.render").setZoom(1)
  zoomNow, zoomWant = 1, 1
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
      entranceX = lv.entry.chamber or lv.entry.x,
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
        summit = lv.theme.summit and { cx = ex.cx } or nil,
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
  base.name = lv.theme.name
  base.gapLeft, base.gapRight = lv.gapLeft, lv.gapRight
  base.palette = lv.theme.palette
  base.arena = lv.theme.arena
  base.glowCount = lv.theme.glowCount
  base.beacons = lv.theme.beacons
  base.breakables = lv.theme.breakables
  base.mine = lv.theme.mine
  base.stalactites = lv.theme.stalactites
  base.gasPools = lv.theme.gasPools
  base.grass = lv.theme.grass
  base.decor = lv.theme.decor
  base.waterPools = lv.theme.waterPools
  base.lavaPools = lv.theme.lavaPools
  base.acidPools = lv.theme.acidPools
  base.monsters = lv.theme.monsters
  base.spawnMul, base.toughMul = lv.theme.spawnMul, lv.theme.toughMul
  base.boss = lv.theme.boss
  base.swarms = lv.theme.swarms
  base.arenaFrac, base.arenaH, base.arenaWidth = lv.theme.arenaFrac, lv.theme.arenaH, lv.theme.arenaWidth
  base.arenaShape, base.noPlatforms = lv.theme.arenaShape, lv.theme.noPlatforms
  base.platformStyle = lv.theme.platformStyle
  base.caveInset, base.noBraziers = lv.theme.caveInset, lv.theme.noBraziers
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

-- The next area to build when nothing is close: the first, then the areas entered from the surface
-- (the mountain at the east end first: it is seen from the desert, so it must be standing before the
-- hunter walks over, and they can all be reached on foot without going through the caves), then the
-- rest in order
local function nextUnfinished()
  if levels[1] and not levels[1].info then
    return 1
  end
  for pass = 1, 2 do
    for i, lv in ipairs(levels) do
      if not lv.info and lv.entry and (pass == 2 or lv.entry.walk) then
        return i
      end
    end
  end
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
    local least = 0.00075 -- (always a little, so a frame that is busy on its own still gets the areas built)
    if levels[1] and not levels[1].info then
      -- The first area is where every run goes first: it is built at a steady pace from the moment the run
      -- begins (a good slice of every frame, more as the hunter nears the shaft), so it is standing before he
      -- gets there, not built on the spot when he steps in
      i = 1
      least = needed(py, px, 700) and 0.012 or 0.008
    elseif not i then
      i = nextUnfinished()
      if i and levels[i].entry and py < firstArea.y0 and not catacombs.levelAt(py, px) then -- (not while inside one of them)
        least = 0.007 -- (an area entered from the surface, with the hunter still up there: a fair share of each frame)
      end
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

-- Builds area i (and what it needs) at once. When that takes a moment the screen shows a progress
-- screen meanwhile, rather than the game freezing on a half-built world.
local function generateShowing(i, started)
  local lv = levels[i]
  if not lv or lv.info then
    return
  end
  if i > 1 and not lv.entry then
    generateShowing(lv.parent or (i - 1), started)
  end
  while not lv.info do
    resume(i, 0.03)
    if lv.info or os.clock() - started < 0.25 or not love.graphics.isActive() then
      goto continue
    end
    do
      love.event.pump()
      for name in love.event.poll() do
        if name == "quit" then
          love.event.quit()
        end
      end
      local fonts = require("src.fonts")
      local w, h = love.graphics.getDimensions()
      love.graphics.origin()
      love.graphics.clear(0.02, 0.015, 0.03)
      love.graphics.setColor(1, 1, 1)
      local font = fonts.get(math.max(16, math.floor(h / 30)))
      love.graphics.setFont(font)
      local dots = string.rep(".", math.floor(os.clock() * 3) % 4)
      love.graphics.printf("Building " .. (lv.theme.name or "the next area") .. dots, 0, h / 2 - font:getHeight() / 2, w, "center")
      love.graphics.present()
    end
    ::continue::
  end
end

function catacombs.ensure(py, px)
  for i, lv in ipairs(levels) do
    -- (the first area is completed by the scene when the hunter goes underground)
    if i > 1 and not lv.info then
      if lv.entry then
        -- A side branch: when the hunter is near its crevice (or already in its rock)
        local ey = lv.entry.y or lv.y0
        if px and math.abs(px - lv.entry.x) < ENSURE_NEAR + 300 and py < lv.y1 and py > ey - ENSURE_NEAR and py < ey + 600 then
          generateShowing(i, os.clock())
        end
      elseif py > lv.y0 - ENSURE_NEAR and py < lv.y1 + ENSURE_NEAR and (not px or (px > lv.x0 - ENSURE_NEAR and px < lv.x1 + ENSURE_NEAR)) then
        generateShowing(i, os.clock())
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

-- 0 outside a mountain, easing to 1 once INDOORS_RAMP px in from its face: how
-- dark the light should be there although the rock stands above the ground
local INDOORS_RAMP = 160

function catacombs.indoors(x, y)
  for _, lv in ipairs(levels) do
    local th = lv.theme
    if th.indoors and th.profile and x >= lv.x0 and x <= lv.x1 and y >= lv.y0 and y <= lv.y1 then
      local xa, xb = th.profile(y)
      if xa and x >= xa and x <= xb and y >= lv.y0 then
        -- darkens gradually over the first stretch inside (not in one step at the door)
        local d = math.min(x - xa, xb - x, y - lv.y0)
        local f = math.max(0, math.min(1, d / INDOORS_RAMP))
        return f * f * (3 - 2 * f)
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

-- The backdrop colour of area i at depth y (see catacombs.backdrop)
function catacombs.backdropIn(i, y)
  local lv, t = levels[i], THEMES[i] or THEMES[#THEMES]
  local d = math.min(1, math.max(0, (y - lv.y0) / ((lv.y1 - lv.y0 + 1) * 0.8)))
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
      if lv.theme.fog then
        -- Banks of dense fog lying in the caves (src.fog), well away from the way in and the arena
        local fogRng = love.math.newRandomGenerator(baseSeed + i * 31)
        local a = info.arena
        local made, tries = 0, 0
        while made < lv.theme.fog and tries < lv.theme.fog * 40 and #info.glows > 0 do
          tries = tries + 1
          local s = info.glows[fogRng:random(1, #info.glows)]
          local bx, by = s[1], s[2] - 26
          local clear = not world:isSolid(bx, by) and not world:isSolid(bx - 50, by) and not world:isSolid(bx + 50, by)
          if clear and a and bx > a.x0 - 80 and bx < a.x1 + 80 and by > a.top - 80 and by < a.floorY + 80 then
            clear = false
          end
          if clear and math.abs(bx - (lv.entry and lv.entry.chamber or -9999)) < 160 and by > 200 then
            clear = false -- (not at the first chamber)
          end
          if clear then
            require("src.fog").addBank(bx, by, 150 + fogRng:random() * 110, 56 + fogRng:random() * 30, function()
              return fogRng:random()
            end)
            made = made + 1
          end
        end
      end
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
      if info.arena and not info.flood and lv.theme.boss ~= "queen" then -- (her gas would catch in them)
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
        for kind, count in pairs(lv.theme.aquatic or {}) do
          for _ = 1, count do
            local r = runs[love.math.random(#runs)]
            local x, y = (r[2] + love.math.random() * (r[3] - r[2])) * 2, r[1] * 2 + 1
            local inShop = false
            for _, room in ipairs(info.shops) do
              inShop = inShop or (x > room.x - 20 and x < room.x + room.w + 20 and y > room.y - 20 and y < room.y + room.h + 20)
            end
            if not inShop and r[3] - r[2] > 6 and y > lv.y0 + (lv.theme.flood and lv.theme.flood.level or 0) + 14 then
              enemies.spawn(kind, x, y, 1 + (lv.row - 1) * 0.6, lv.row)
            end
          end
        end
      end
      -- A prisoner's cage, with two of the things that keep them
      local pr = info.prisoner
      local fl = lv.theme.prisoner and lv.entry and lv.entry.lake and require("src.meta").PEOPLE[lv.theme.prisoner].held == "float"
      if fl then
        -- Floats on the lake over the cave's entrance: on the surface water
        -- right beside the neck that drops down into the caverns
        local x0, x1 = lv.entry.x - lv.entry.half + 6, lv.entry.x + lv.entry.half - 6
        local rim = math.min(world:findGround(x0, -400), world:findGround(x1, -400))
        pr = { id = lv.theme.prisoner, x = x1 - 16, y = rim + 36, held = "float" } -- (out toward the lake's right edge, not mid-water)
      end
      if pr and require("src.meta").canFind(pr.id) and not require("src.meta").atCamp(pr.id) then -- (once freed, their cage is gone for good)
        npcs.spawnCage(pr.id, pr.x, pr.y, pr.held, pr.top)
        for _, dx in ipairs(pr.held == "float" and {} or { -46, 52 }) do
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
        if m.boss and m.arena then
          -- An arena's boss isn't there until the hunter steps up to the
          -- pedestal at the middle of the arena (catacombs.interact)
          lv.boss = { m = m, state = "idle" }
          if m.kind == "golem" then
            -- the Colossus waits, dormant, in front of the pedestal: dim, no health bar, until it is woken
            local a = info.arena
            local gy = world:findGround(math.floor(a.cx), a.floorY - 40)
            lv.boss.spot = { a.cx, gy }
            local ge = enemies.spawn("golem", a.cx + 120, gy, m.toughness, lv.row)
            ge.state, ge.altarLocked, ge.invuln = "sleep", true, true
            ge.facing = -1 -- (slumped facing the pedestal)
            ge.areaIndex, ge.arena, ge.reward = i, a, m.reward
            lv.boss.e = ge
          end
          if m.kind == "bigfish" then
            -- The fish waits at the bottom middle of its round arena, no pedestal:
            -- the fight starts when it notices the hunter
            lv.boss.noAltar = true
            local a = info.arena
            local fx, fy = a.cx, a.floorY - 90
            local e = enemies.spawn("bigfish", fx, fy, 1, lv.row)
            e.dormant = true
            e.areaIndex = i
            e.arena = a
            e.reward = m.reward
            lv.boss.e = e
          end
        else
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
          end
        end
      end
      -- A few of them are elite (src.enemies), more the deeper the area
      local elites = enemies.rollElites(spawned, lv.row, nil, lv.theme.eliteMul)
      require("src.events").spawnArea(world, info, i, lv.row, elites, chests)
    end
  end
end

local propTimer = 0
local gravityScale = 1

-- Banners as the hunter reaches each area, the shop-reached message, and gas
local openGate -- (below)
local glyphHint = 0 -- seconds until the sealed door may speak again

local supportTimer = 0
function catacombs.update(player, dt)
  catacombs.spawnProps()
  updateBossCamera(player, dt)
  fluids.update(dt, player, enemies)
  propTimer = propTimer - dt
  if propTimer <= 0 then
    propTimer = 0.3
    fluids.updateProps(props)
  end
  local px, py = player:center()
  local at = catacombs.levelAt(py, px)
  -- Scenery, chests and the like that stood on ground the digging has taken away are gone with it
  supportTimer = supportTimer - dt
  if supportTimer <= 0 then
    supportTimer = 0.3
    for _, lv in ipairs(levels) do
      local info = lv.info
      if info then
        if info.mine then
          minedecor.checkSupport(world, info.mine, px, py)
        end
        if info.story then
          story.checkSupport(world, info.story, px, py)
        end
      end
    end
    chests.checkSupport(world, px, py)
  end
  -- The sky's door: opens once every glyph is in hand, and says what it wants when approached
  glyphHint = math.max(0, glyphHint - dt)
  for _, lv in ipairs(levels) do
    local held = lv.info and lv.info.arena and lv.info.arena.held
    if held then
      if glyphs.complete() then
        lv.info.arena.held = nil
        openGate(held)
        audio.play("hatch")
        hud.showBanner("The Door Opens", "Every glyph is lit. The way up to the sky lies open")
      elseif glyphHint <= 0 and math.abs(px - (held.x0 + held.x1) / 2) < 70 and math.abs(py - held.y1) < 70 then
        glyphHint = 6
        effects.popup((held.x0 + held.x1) / 2, held.y1 + 14, "Sealed: " .. glyphs.count() .. " / " .. glyphs.total() .. " glyphs", { 0.85, 0.8, 0.95 })
      end
    end
  end
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
  -- The zone's name comes up each time the hunter crosses into another (shops don't count:
  -- they belong to the zone around them)
  if not catacombs.inShop(px, py) then
    local zone = catacombs.zoneAt(px, py)
    if zone ~= announced.zone then
      local first = announced.zone == nil
      announced.zone = zone
      if zone == 0 then
        if not first then
          hud.showBanner(catacombs.surfaceName or "The Barrens", nil)
        end
      else
        hud.showBanner(levels[zone].theme.name, catacombs.areaTitle(zone))
      end
    end
  end
  local b = player.body
  for _, lv in ipairs(levels) do
    -- Violet motes drifting up through the Dark Hunter's hall
    local arena = lv.info and lv.info.arena
    if arena and lv.theme.arenaDecor and px > arena.x0 and px < arena.x1 and py > arena.top - 40 and py < arena.floorY + 40 and love.math.random() < dt * 16 then
      local ang, r = love.math.random() * math.pi * 2, math.sqrt(love.math.random())
      local mx, my = arena.cx + math.cos(ang) * r * arena.w * 0.46, arena.top + arena.h / 2 + math.sin(ang) * r * arena.h * 0.46
      effects.particle(mx, my, (love.math.random() - 0.5) * 12, -6 - love.math.random() * 12, 2.5 + love.math.random() * 2.5, love.math.random() < 0.5 and { 0.6, 0.3, 1 } or { 0.35, 0.5, 1 }, -3, true)
    end
    local fish = lv.boss and lv.boss.noAltar and lv.boss.state == "idle" and lv.boss.e
    if fish and not fish.dead then
      local fx, fy = fish.body.x + fish.body.w / 2, fish.body.y + fish.body.h / 2
      if (px - fx) ^ 2 + (py - fy) ^ 2 < 380 ^ 2 or fish.hp < fish.maxHp then
        catacombs.startBoss(lv, player)
      end
    end
  end
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

function openGate(g)
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

-- The Queen is dead: the iron gates over both shafts open
function catacombs.openGates(lv)
  local a = lv.info.arena
  if a.open then
    return
  end
  a.open = true
  audio.play("hatch")
  for _, g in ipairs(a.plugs or {}) do
    -- (the plugs that sealed the tunnels in)
    for y = g.y0, g.y1 do
      for x = g.x0, g.x1 do
        world:setRaw(x, y, materials.AIR)
      end
    end
    world:repaintRegion(g.x0, g.y0, g.x1, g.y1)
    physics.rebuildRegion(g.x0, g.y0, g.x1, g.y1)
  end
  a.plugs = nil
  if a.ring then
    for _, r in ipairs(a.ring) do
      for x = r[1], r[2] do
        world:setRaw(x, r[3], materials.AIR)
      end
    end
    world:repaintRegion(a.x0 - 40, a.top - 30, a.x1 + 40, a.floorY + 60)
    physics.rebuildRegion(a.x0 - 40, a.top - 30, a.x1 + 40, a.floorY + 60)
    a.ring = nil
  end
  if a.seal then
    -- the rock round the arena is only rock again
    local z = a.seal
    for y = z.y0, z.y1 do
      for x = z.x0, z.x1 do
        if world:get(x, y) == materials.SEALED then
          world:setRaw(x, y, z.rock)
        end
      end
    end
    world:repaintRegion(z.x0, z.y0, z.x1, z.y1)
    physics.rebuildRegion(z.x0, z.y0, z.x1, z.y1)
    a.seal = nil
  end
  for _, g in ipairs(a.gates) do
    if g.glyph and not glyphs.complete() then
      a.held = g -- (the sky's door stays shut until every glyph is in hand: see catacombs.update)
    else
      openGate(g)
    end
  end
  local won = lv.theme.arenaWon or { "The Queen Has Fallen", "The gates are open. Two shops lie below, left and right: choose one" }
  if a.held then
    won = { won[1], "The door to the sky is sealed by " .. glyphs.total() .. " glyphs. Bring the proof of every boss" }
  end
  hud.showBanner(won[1], won[2])
end

-- The boss pedestal ------------------------------------------------------------------

-- What the pedestal says (and what it asks of the hunter), by the area's `defy`
local function defyTitle(lv)
  return "Defy the " .. (lv.theme.defy or "Caverns")
end

-- The pedestal's spot: the middle of the arena, on its floor
local function altarSpot(lv)
  local a = lv.info.arena
  if not lv.boss.spot then
    lv.boss.spot = { a.cx, world:findGround(math.floor(a.cx), a.floorY - 40) }
  end
  return lv.boss.spot[1], lv.boss.spot[2]
end

-- The pedestal the hunter is standing at, if any (a boss waiting to be woken)
local function altarNear(px, py)
  for _, lv in ipairs(levels) do
    if lv.info and lv.boss and lv.boss.state == "idle" and not lv.boss.noAltar then
      local ax, ay = altarSpot(lv)
      if math.abs(px - ax) < 22 and math.abs(py - (ay - 8)) < 30 then
        return lv
      end
    end
  end
  return nil
end

-- The pedestal: a stone column with a bowl and a rune that burns while a boss waits
local function drawAltar(lv)
  local x, y = altarSpot(lv)
  x, y = math.floor(x), math.floor(y)
  love.graphics.setColor(0.20, 0.19, 0.24)
  love.graphics.rectangle("fill", x - 9, y - 3, 18, 3)
  love.graphics.setColor(0.30, 0.29, 0.36)
  love.graphics.rectangle("fill", x - 6, y - 15, 12, 12)
  love.graphics.setColor(0.40, 0.39, 0.47)
  love.graphics.rectangle("fill", x - 6, y - 15, 3, 12)
  love.graphics.setColor(0.16, 0.15, 0.20)
  love.graphics.rectangle("fill", x + 3, y - 15, 3, 12)
  love.graphics.setColor(0.42, 0.41, 0.50)
  love.graphics.rectangle("fill", x - 9, y - 18, 18, 4)
  love.graphics.setColor(0.52, 0.51, 0.60)
  love.graphics.rectangle("fill", x - 9, y - 18, 18, 1)
end

local function drawAltarGlow(lv)
  local x, y = altarSpot(lv)
  x, y = math.floor(x), math.floor(y)
  local t = love.timer.getTime()
  local live = lv.boss.state == "idle"
  local pulse = 0.6 + 0.35 * math.sin(t * 3)
  local c = live and { 1, 0.45, 0.25 } or { 0.5, 0.2, 0.15 }
  love.graphics.setColor(c[1], c[2], c[3], live and pulse or 0.4)
  love.graphics.rectangle("fill", x - 3, y - 11, 6, 1)
  love.graphics.rectangle("fill", x - 1, y - 13, 2, 5)
  if live then
    love.graphics.setColor(1, 0.7, 0.3, 0.5 + 0.3 * pulse)
    love.graphics.rectangle("fill", x - 2, y - 24 - math.floor(pulse * 2), 4, 6)
    love.graphics.setColor(1, 0.95, 0.7)
    love.graphics.rectangle("fill", x - 1, y - 21, 2, 3)
  end
end

-- Seals the tunnels into the arena with iron until the boss is dead
local function sealArena(lv)
  local a = lv.info.arena
  a.plugs = {}
  for _, y in ipairs({ a.top - 12, a.top - 22 }) do
    local x = a.x0 - 4
    while x <= a.x1 + 4 do
      if not world:isSolid(x, y) then
        local xa = x
        while x <= a.x1 + 4 and not world:isSolid(x, y) do
          x = x + 1
        end
        a.plugs[#a.plugs + 1] = { x0 = xa - 3, x1 = x + 2, y0 = y - 3, y1 = y + 3 }
      else
        x = x + 1
      end
    end
  end
  for _, g in ipairs(a.plugs) do
    for y = g.y0, g.y1 do
      for x = g.x0, g.x1 do
        if not world:isSolid(x, y) then
          world:setRaw(x, y, materials.IRON)
        end
      end
    end
    world:repaintRegion(g.x0, g.y0, g.x1, g.y1)
    physics.rebuildRegion(g.x0, g.y0, g.x1, g.y1)
  end
  if a.shape == "round" then
    -- An oval hall has its mouths low down, at the foot of the shafts that climb into it:
    -- iron fills every open hole just outside the oval, so nothing can drop out of it
    local cx, cy, rx, ry = a.cx, a.top + a.h / 2, a.w / 2, a.h / 2
    a.ring = {}
    for y = a.top - 30, a.floorY + 60 do
      local ny = ((y - cy) / ry) ^ 2
      local x = a.x0 - 40
      while x <= a.x1 + 40 do
        local d = ((x - cx) / rx) ^ 2 + ny
        if d >= 1.0 and d <= 1.45 and not world:isSolid(x, y) then
          local xa = x
          while x <= a.x1 + 40 and not world:isSolid(x, y) and ((x - cx) / rx) ^ 2 + ny >= 1.0 and ((x - cx) / rx) ^ 2 + ny <= 1.45 do
            world:setRaw(x, y, materials.IRON)
            x = x + 1
          end
          a.ring[#a.ring + 1] = { xa, x - 1, y }
        else
          x = x + 1
        end
      end
    end
    world:repaintRegion(a.x0 - 40, a.top - 30, a.x1 + 40, a.floorY + 60)
    physics.rebuildRegion(a.x0 - 40, a.top - 30, a.x1 + 40, a.floorY + 60)
  end
end

-- The hunter steps up to the pedestal: the arena is sealed, what else lives in
-- it is cleared out, and the boss comes
function catacombs.startBoss(lv, player)
  local a, m = lv.info.arena, lv.boss.m
  lv.boss.state = "fight"
  if BOSS_MUSIC[lv.theme.boss] then
    audio.setBoss(true, lv.theme.boss)
  end
  sealArena(lv)
  for _, e in ipairs(enemies.every()) do
    local cx, cy = e.body.x + e.body.w / 2, e.body.y + e.body.h / 2
    if not e.dead and not e.def.boss and cx > a.x0 and cx < a.x1 and cy > a.top - 40 and cy < a.floorY + 40 then
      enemies.vanish(e)
    end
  end
  if lv.boss.noAltar and lv.boss.e then
    local fe = lv.boss.e
    fe.dormant = false
    fe.state, fe.seesPlayer = "chase", true
    audio.play("explosion", 1, 0.4)
    require("src.camera").shake(0.7)
    hud.showBanner(defyTitle(lv), (lv.theme.arenaBanner and lv.theme.arenaBanner[1] or "The Arena") .. ": the way out is sealed until the boss falls")
    return
  end
  if lv.boss.e and m.kind == "golem" then
    -- the dormant Colossus wakes: it rises from the heap, and the fight begins
    local ge = lv.boss.e
    ge.altarLocked, ge.invuln = false, false
    ge.state, ge.seesPlayer = "chase", true
    audio.play("explosion", 1, 0.4)
    require("src.camera").shake(0.7)
    hud.showBanner(defyTitle(lv), (lv.theme.arenaBanner and lv.theme.arenaBanner[1] or "The Arena") .. ": the way out is sealed until the boss falls")
    return
  end
  local def = enemies.defs[m.kind]
  local ax = altarSpot(lv)
  local x = ax + (def.ground and 190 or 0)
  local y = def.ground and a.floorY - 70 or a.top + 110
  local e = enemies.spawn(m.kind, x, y, m.toughness, lv.row)
  e.reward = m.reward
  e.areaIndex = lv.index
  e.arena = a
  if m.kind ~= "queen" then
    e.state = "chase"
    e.seesPlayer = true
  end
  lv.boss.e = e
  audio.play("explosion", 1, 0.4)
  require("src.camera").shake(0.7)
  effects.ring(x, y, 80, { 1, 0.85, 0.5 })
  hud.showBanner(defyTitle(lv), (lv.theme.arenaBanner and lv.theme.arenaBanner[1] or "The Arena") .. ": the way out is sealed until the boss falls")
end

-- E at the pedestal
function catacombs.interact(player)
  local px, py = player:center()
  local lv = altarNear(px, py)
  if not lv then
    return false
  end
  catacombs.startBoss(lv, player)
  return true
end

-- During a boss fight the camera pulls out a little and looks between the
-- hunter and the boss, so it can't be lost off screen
local FIGHT_ZOOM = 1.35

local function stepZoom(dt)
  zoomT = zoomT - dt
  if zoomNow ~= zoomWant and zoomT <= 0 then
    zoomT = 0.07
    local nz = zoomNow < zoomWant and math.min(zoomWant, zoomNow + 0.05) or math.max(zoomWant, zoomNow - 0.05)
    local render, camera, config = require("src.render"), require("src.camera"), require("src.config")
    local ow, oh = config.VIRTUAL_W, config.VIRTUAL_H
    render.setZoom(nz)
    camera.resized(ow, oh, config.VIRTUAL_W, config.VIRTUAL_H)
    zoomNow = nz
  end
end

updateBossCamera = function(player, dt)
  local fightLv
  for i, lv in ipairs(levels) do
    if lv.boss and lv.boss.state == "fight" then
      fightLv = fightLv or i
    end
  end
  local camera = require("src.camera")
  -- The boss pieces alive in the fight (a split Queen is several of them: the
  -- original may be gone while her remnants fight on)
  local pieces = {}
  if fightLv then
    for _, e in ipairs(enemies.all()) do
      if not e.dead and e.def.boss and (e.areaIndex == nil or e.areaIndex == fightLv) then
        pieces[#pieces + 1] = e
      end
    end
  end
  if #pieces > 0 then
    -- Look at the middle of those near enough to be on screen (else the nearest)
    local px, py = player:center()
    local config = require("src.config")
    local rx, ry = config.VIRTUAL_W * 0.75, config.VIRTUAL_H * 0.75
    local sx, sy, n = 0, 0, 0
    local best, bd
    for _, e in ipairs(pieces) do
      local ex, ey = e.body.x + e.body.w / 2, e.body.y + e.body.h / 2
      if math.abs(ex - px) < rx and math.abs(ey - py) < ry then
        sx, sy, n = sx + ex, sy + ey, n + 1
      end
      local d = (ex - px) ^ 2 + (ey - py) ^ 2
      if not bd or d < bd then
        best, bd = e, d
      end
    end
    if best.kind == "bigfish" then
      camera.setFocus(nil) -- (the camera stays on the hunter: only a wider view)
      zoomWant = 1.3
    else
      if n > 0 then
        camera.setFocus(sx / n, sy / n)
      else
        camera.setFocus(best.body.x + best.body.w / 2, best.body.y + best.body.h / 2)
      end
      zoomWant = FIGHT_ZOOM
    end
  else
    camera.setFocus(nil)
    zoomWant = 1
  end
  stepZoom(dt)
end

-- Is the point inside a shop room?
-- Which zone a point is in: an area's index, or 0 for the open surface and sky above it.
-- A mountain only counts inside its own silhouette.
function catacombs.zoneAt(px, py)
  for i, lv in ipairs(levels) do
    if px >= lv.x0 and px <= lv.x1 and py >= lv.y0 and py <= lv.y1 then
      local th = lv.theme
      if th.profile then
        local xa, xb = th.profile(py)
        if xa and px >= xa and px <= xb then
          return i
        end
      else
        return i
      end
    end
  end
  return 0
end

-- True inside a boss arena (random events keep out of these)
function catacombs.inArena(x, y)
  for _, lv in ipairs(levels) do
    local a = lv.info and lv.info.arena
    if a and x >= a.x0 - 24 and x <= a.x1 + 24 and y >= a.top - 40 and y <= a.floorY + 24 then
      return true
    end
  end
  return false
end

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

-- The ring of violet crystals set into the Dark Hunter's oval: places and sizes, made once
local crystalRings = {}
local function arenaCrystals(a)
  if crystalRings[a] then
    return crystalRings[a]
  end
  local list = {}
  local cx, cy, rx, ry = a.cx, a.top + a.h / 2, a.w / 2, a.h / 2
  for k = 0, 35 do
    local ang = k / 36 * math.pi * 2
    local jitter = 1 - 0.02 * (k % 3)
    list[#list + 1] = {
      x = cx + math.cos(ang) * rx * 0.985 * jitter,
      y = cy + math.sin(ang) * ry * 0.985 * jitter,
      ang = ang,
      len = 6 + (k * 7) % 9,
      ph = k * 1.7,
    }
  end
  crystalRings[a] = list
  return list
end

function catacombs.addLights(lighting, view)
  fluids.addLights(lighting, view)
  local t = love.timer.getTime()
  for _, lv in ipairs(levels) do
    local arena = lv.info and lv.info.arena
    if lv.theme.arenaDecor and arena and view.x + view.w > arena.x0 and view.x < arena.x1 and view.y + view.h > arena.top - 10 and view.y < arena.floorY + 10 then
      for _, c in ipairs(arenaCrystals(arena)) do
        if visible(view, c.x, c.y, 80) then
          lighting.add(c.x, c.y, 70, 0.55, 0.25, 0.95, 0.45 + 0.15 * math.sin(t * 1.3 + c.ph))
        end
      end
    end
    if lv.theme.parallax == 9 and lv.theme.profile and inArea(lv, view) then
      -- The holes in the far rock that open onto the sky throw its light in (src.parallax)
      -- (no lights for them: a light sitting in the far rock spills onto the ground in front.
    -- They glow through drawEmissive instead, only where the air shows them)
    parallax.skyHoles(view.x, view.y, view.x, view.y, view.x + view.w, view.y + view.h, function(x, y, r, g, b, radius)
        if false then
          lighting.add(x, y, radius, r, g, b, 0.75)
        end
      end)
    end
    local info = inArea(lv, view) and lv.info
    if info and lv.boss and lv.boss.state == "idle" and not lv.boss.noAltar and info.arena and visible(view, info.arena.cx, info.arena.floorY, 160) then
      local ax, ay = altarSpot(lv)
      lighting.add(ax, ay - 20, 80, 1, 0.5, 0.28, 0.8 + 0.15 * math.sin(t * 3))
    end
    if info then
      for i, c in ipairs(candles(info)) do
        if visible(view, c[1], c[2], 120) then
          lighting.add(c[1], c[2] - c[3] - 2, 100, 1, 0.68, 0.36, 0.65 + flicker(i) * 0.05)
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

-- The shop's back wall: a void of its own, hiding the cave's parallax (and the
-- same in every area): dark indigo with wisps of purple and blue turning slowly
-- round the room's centre, like the title screen's nebula without the hole
local VOID_SHADER = [[
uniform float time;
uniform float hall;   // 1: the Dark Hunter's hall (dark, calm, with sparks), 0: the shop's void
uniform vec2 offset;  // of the drawn slice inside the shop room
uniform vec2 sliceSize;
uniform vec2 player;  // the hunter, in the room's own coordinates
uniform vec2 oval;    // the pulsing blue oval's centre (the portal), in the same; far away = none
uniform vec2 ovalSize;
uniform vec2 boxMin;  // the whole window, in the room's coordinates
uniform vec2 boxMax;
uniform vec4 feather; // how far in from the left, right, top and bottom edges it fades out (0: not at all)
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + 11.0; a *= 0.5; }
  return v;
}
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 p = uv * sliceSize + offset;
  if (hall > 0.5) {
    // the hall: black, with a few slow swirls of faint smoke turning through it, dust
    // drifting up, and the odd spark winking
    vec2 hq = p * 0.007;
    vec2 centre = (boxMin + boxMax) * 0.5;
    // (the smoke is warped twice and turns a little about the hall's middle)
    float ang = 0.35 * sin(time * 0.05) + length(p - centre) * 0.0011;
    vec2 rp = p - centre;
    rp = vec2(rp.x * cos(ang) - rp.y * sin(ang), rp.x * sin(ang) + rp.y * cos(ang));
    vec2 sq = rp * 0.0065 + vec2(time * 0.006, 0.0);
    vec2 w1 = vec2(fbm(sq + vec2(0.0, time * 0.018)), fbm(sq + vec2(5.2, 1.3) - vec2(time * 0.014, 0.0)));
    float sm = fbm(sq + 2.6 * w1);
    float arm = smoothstep(0.52, 0.82, sm);
    vec3 hc = vec3(0.004, 0.004, 0.008);
    hc += vec3(0.030, 0.022, 0.060) * smoothstep(0.30, 0.85, fbm(hq + vec2(time * 0.01, 0.0))) * 0.8;
    hc += vec3(0.095, 0.058, 0.17) * arm;
    // dust: small pale specks drifting slowly up and across, each a little different
    for (int k = 0; k < 2; k++) {
      float sz = k == 0 ? 7.0 : 13.0;
      vec2 dp = p + vec2(time * (k == 0 ? 3.0 : 1.6), -time * (k == 0 ? 5.0 : 2.8)) + float(k) * 41.0;
      vec2 dc = floor(dp / sz);
      float dr = hash(dc + 17.3 + float(k));
      if (dr > 0.8) {
        vec2 at = vec2(0.2 + 0.6 * hash(dc + 4.1), 0.2 + 0.6 * hash(dc + 8.8));
        at += 0.12 * vec2(sin(time * 0.7 + dr * 50.0), cos(time * 0.6 + dr * 30.0));
        float dd = length(fract(dp / sz) - at) * sz;
        float fade = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * 0.5 + dr * 90.0));
        hc += vec3(0.40, 0.36, 0.55) * smoothstep(1.3, 0.3, dd) * fade * (k == 0 ? 0.32 : 0.2);
      }
    }
    vec2 cell = floor(p / 9.0);
    vec2 inCell = fract(p / 9.0);
    float r = hash(cell + 3.7);
    if (r > 0.975) {
      vec2 at = vec2(0.25 + 0.5 * hash(cell + 9.1), 0.25 + 0.5 * hash(cell + 2.3));
      float tw = 0.5 + 0.5 * sin(time * (1.2 + 2.0 * hash(cell + 5.5)) + r * 40.0);
      float spark = smoothstep(0.16, 0.0, length(inCell - at)) * tw * tw;
      hc += mix(vec3(0.55, 0.40, 0.95), vec3(0.45, 0.80, 1.0), hash(cell + 7.7)) * spark * 0.6;
    }
    // (solid to the edge of the box: only the last few pixels soften)
    float ha = smoothstep(0.0, 6.0, p.x - boxMin.x) * smoothstep(0.0, 6.0, boxMax.x - p.x)
      * smoothstep(0.0, 6.0, p.y - boxMin.y) * smoothstep(0.0, 6.0, boxMax.y - p.y);
    return vec4(hc * ha, ha);
  }
  vec2 q = p * 0.011;
  // the space bends away from the hunter, like a weight pressing on a sheet
  vec2 dp = p - player;
  float near = exp(-dot(dp, dp) / (70.0 * 70.0));
  q += dp / (length(dp) + 8.0) * near * 0.5;
  // the blue oval: it breathes, and bends the space round it a little
  float pulse = 0.5 + 0.5 * sin(time * 1.6);
  vec2 od = (p - oval) / (ovalSize * (1.0 + 0.13 * pulse));
  float ov = length(od);
  q += normalize(p - oval + vec2(0.001)) * exp(-ov * 1.4) * (0.35 + 0.25 * pulse) * 0.5;
  // a fractal fold of the plane: noise warped by noise warped by noise
  vec2 w1 = vec2(fbm(q + vec2(0.0, time * 0.05)), fbm(q + vec2(5.2, 1.3) - vec2(time * 0.04, 0.0)));
  vec2 w2 = vec2(fbm(q + 3.0 * w1 + vec2(1.7, 9.2) + time * 0.03), fbm(q + 3.0 * w1 + vec2(8.3, 2.8) - time * 0.025));
  float n = fbm(q + 3.2 * w2);
  float w = fbm(q * 1.8 + 2.0 * w2 + vec2(0.0, time * 0.04));
  vec3 col = mix(vec3(0.020, 0.016, 0.045), vec3(0.085, 0.045, 0.145), n);
  col += vec3(0.24, 0.10, 0.36) * smoothstep(0.50, 0.85, n) * 0.5;
  col += vec3(0.08, 0.22, 0.48) * smoothstep(0.52, 0.88, w) * 0.5;
  col += vec3(0.30, 0.2, 0.5) * near * 0.12;
  col += vec3(0.10, 0.35, 0.95) * smoothstep(1.0, 0.0, ov) * (0.65 + 0.3 * pulse);
  col += vec3(0.30, 0.6, 1.0) * exp(-abs(ov - 1.0) * 7.0) * (0.35 + 0.3 * pulse);
  col += vec3(0.05, 0.15, 0.45) * exp(-ov * 0.9) * 0.4;
  col *= 0.8 + 0.2 * smoothstep(0.25, 0.65, fbm(q * 4.0 + 3.0));
  // the edges bleed into whatever is behind them
  float a = 1.0;
  // (outward: the room's own box stays at full strength, the void spills past it and fades)
  if (feather.x > 0.0) a *= 1.0 - smoothstep(0.0, feather.x, boxMin.x - p.x);
  if (feather.y > 0.0) a *= 1.0 - smoothstep(0.0, feather.y, p.x - boxMax.x);
  if (feather.z > 0.0) a *= 1.0 - smoothstep(0.0, feather.z, boxMin.y - p.y);
  if (feather.w > 0.0) a *= 1.0 - smoothstep(0.0, feather.w, p.y - boxMax.y);
  return vec4(col * a, a);
}
]]
local voidShader, voidBlank

-- Draws the void over (cx, cy, cw, ch), as a window onto the shop room s's one
-- field of it, so the teleport room below is the same space continued
local VOID_FEATHER = 36 -- (and its edges fade over this much, into the cave's own background)

local function drawVoidRect(s, cx, cy, cw, ch, view, ovalX, ovalY, ovalW, ovalH, fadeTop, fadeBottom, hall)
  -- The shop's void bleeds outward into the backdrop beside it (the hall's fades inward)
  local ox0, ox1, oy0, oy1 = 0, 0, 0, 0
  if not hall then
    ox0, ox1 = VOID_FEATHER, VOID_FEATHER
    oy0, oy1 = fadeTop and VOID_FEATHER or 0, fadeBottom and VOID_FEATHER or 0
  end
  local x0, x1 = math.max(cx - ox0, math.floor(view.x)), math.min(cx + cw + ox1, math.ceil(view.x + view.w))
  local y0, y1 = math.max(cy - oy0, math.floor(view.y)), math.min(cy + ch + oy1, math.ceil(view.y + view.h))
  if x1 <= x0 or y1 <= y0 then
    return
  end
  local t = love.timer.getTime()
  if voidShader == nil then
    local ok, sh = pcall(love.graphics.newShader, VOID_SHADER)
    voidShader = ok and sh or false
    local data = love.image.newImageData(1, 1)
    data:setPixel(0, 0, 1, 1, 1, 1)
    voidBlank = love.graphics.newImage(data)
  end
  if voidShader then
    local okp, gp = pcall(function()
      return require("src.game").player()
    end)
    local px, py = 0, -9999
    if okp and gp then
      px, py = gp:center()
    end
    love.graphics.setShader(voidShader)
    voidShader:send("time", t)
    voidShader:send("hall", hall and 1 or 0)
    voidShader:send("offset", { x0 - s.x, y0 - s.y })
    voidShader:send("sliceSize", { x1 - x0, y1 - y0 })
    voidShader:send("player", { px - s.x, py - s.y })
    voidShader:send("oval", { ovalX or -9999, ovalY or -9999 })
    voidShader:send("ovalSize", { ovalW or 46, ovalH or 26 })
    voidShader:send("boxMin", { cx - s.x, cy - s.y })
    voidShader:send("boxMax", { cx + cw - s.x, cy + ch - s.y })
    voidShader:send("feather", { VOID_FEATHER, VOID_FEATHER, fadeTop and VOID_FEATHER or 0, fadeBottom and VOID_FEATHER or 0 })
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(voidBlank, x0, y0, 0, x1 - x0, y1 - y0)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
  else
    love.graphics.setColor(0.04, 0.03, 0.09)
    love.graphics.rectangle("fill", x0, y0, x1 - x0, y1 - y0)
  end
end

local function drawShopVoid(s, view)
  local b = s.back
  drawVoidRect(s, s.x, s.y, s.w, s.h, view, nil, nil, nil, nil, true, not b)
  if b then
    -- (the pulsing blue oval belongs to the portal below the shop)
    drawVoidRect(s, b.x0, b.y0, b.x1 - b.x0 + 1, b.floorY - b.y0, view, nil, nil, nil, nil, false, true)
  end
end

function catacombs.drawDecor(view)
  fluids.drawDecor(view)
  for _, lv in ipairs(levels) do
    local info = inArea(lv, view) and lv.info
    if info then
      local drawGlow = lv.theme.crystals and drawCrystals or drawFungus
      local arena = info.arena
      if lv.theme.arenaDecor and arena and view.x + view.w > arena.x0 and view.x < arena.x1 and view.y + view.h > arena.top - 10 and view.y < arena.floorY + 10 then
        -- The Dark Hunter's hall: near-black with slow swirls and drifting dust behind the oval, whatever
        -- the mountain's own scenery was (the rock round the oval covers the rest of the box)
        drawVoidRect({ x = arena.x0, y = arena.top }, arena.x0 - 4, arena.top - 4, arena.w + 8, arena.h + 8, view, nil, nil, nil, nil, nil, nil, true)
      end
      if lv.boss and not lv.boss.noAltar and lv.boss.state ~= "done" and lv.info.arena and visible(view, lv.info.arena.cx, lv.info.arena.floorY, 160) then
        drawAltar(lv)
      end
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
          drawShopVoid(s, view)
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
            -- (a slab never changes: drawn once into a canvas, in pieces of at most 512 px, see src.bake)
            local function columns(xa, xb)
              for x = xa, xb do
                local thick = 5 + math.floor(love.math.noise(x * 0.2, p.y) * 3)
                love.graphics.setColor(def.topColor[1], def.topColor[2], def.topColor[3])
                love.graphics.rectangle("fill", x, p.y, 1, 1)
                love.graphics.setColor(def.color[1] * 0.85, def.color[2] * 0.85, def.color[3] * 0.85)
                love.graphics.rectangle("fill", x, p.y + 1, 1, thick - 1)
              end
            end
            if bake.enabled.slabs then
              for xa = p.x0, p.x1, 512 do
                local xb = math.min(p.x1, xa + 511)
                if xb >= view.x - 4 and xa <= view.x + view.w + 4 then
                  bake.piece(p, (xa - p.x0) / 512, 1, xa, p.y, xb - xa + 1, 9, function()
                    columns(xa, xb)
                  end)
                end
              end
            else
              columns(p.x0, p.x1)
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
  -- (no creatures are passed to the far glows below: like the old mine's lanterns they lie over them, instead of leaving a dark cut-out and rim round each one)
  for _, lv in ipairs(levels) do
    if lv.theme.parallax == 9 and lv.theme.profile and inArea(lv, view) then
      local a = lv.info and lv.info.arena
      parallax.drawSkyGlow(view.x, view.y, view.x + view.w, view.y + view.h, require("src.lighting").mask(), lv.theme.profile,
        a and lv.theme.arenaDecor and { a.x0 - 4, a.top - 4, a.x1 + 4, a.floorY + 4 } or nil)
    end
  end
  -- The old mine's far lanterns (their flames and glow, bright over the lit scene, hidden behind rock)
  for _, lv in ipairs(levels) do
    if lv.index == 1 and not lv.theme.parallax and inArea(lv, view) then
      -- (only inside the area's own box: the far scenery is not drawn outside it, nor the sky over it)
      local x0, y0, x1, y1 = math.max(view.x, lv.x0), math.max(view.y, lv.y0), math.min(view.x + view.w, lv.x1), math.min(view.y + view.h, lv.y1)
      if x1 > x0 and y1 > y0 then
        parallax.drawLanternGlow(view.x, view.y, x0, y0, x1, y1, require("src.lighting").mask()) -- (no creatures passed: the far lanterns' glow lies over them, instead of leaving a dark cut-out and rim round each one)
      end
    end
  end
  -- What glows in a boss arena's far scenery (src.bossbg), drawn bright over the lit scene but
  -- hidden behind the terrain, so it never lights the ground in front of it
  for _, lv in ipairs(levels) do
    if lv.theme.arenaParallax and inArea(lv, view) then
      local bx0, by0, bx1, by1 = catacombs.arenaBox(lv.index)
      if bx0 and view.x + view.w > bx0 and view.x < bx1 and view.y + view.h > by0 and view.y < by1 then
        bossbg.drawGlow(view, lv.theme.arenaParallax, { bx0, by0, bx1, by1 }, require("src.lighting").mask())
      end
    end
  end
  -- The sky's door: one rune for each glyph it wants, dark until the hunter has brought it, then lit
  for _, lv in ipairs(levels) do
    local held = lv.info and lv.info.arena and lv.info.arena.held
    if held and view.x + view.w > held.x0 - 60 and view.x < held.x1 + 60 and view.y + view.h > held.y0 - 80 and view.y < held.y1 + 40 then
      local n = #glyphs.order
      local gx0 = math.floor((held.x0 + held.x1) / 2 - (n * 11 - 4) / 2)
      for k, id in ipairs(glyphs.order) do
        glyphs.draw(id, gx0 + (k - 1) * 11, held.y0 - 13, 1, glyphs.has(id) and 1 or 0.14)
      end
    end
  end
  fluids.drawGlints(require("src.lighting").list())
  for _, lv in ipairs(levels) do
    local info = inArea(lv, view) and lv.info
    if info then
      local g = lv.theme.glow
      if lv.boss and not lv.boss.noAltar and lv.boss.state ~= "done" and info.arena and visible(view, info.arena.cx, info.arena.floorY, 160) then
        drawAltarGlow(lv)
      end
      local arena = info.arena
      if lv.theme.arenaDecor and arena and view.x + view.w > arena.x0 and view.x < arena.x1 and view.y + view.h > arena.top - 10 and view.y < arena.floorY + 10 then
        -- Violet crystals growing out of the oval's wall, pulsing, and a haze round each
        local t = love.timer.getTime()
        for _, c in ipairs(arenaCrystals(arena)) do
          if visible(view, c.x, c.y, 30) then
            local pulse = 0.65 + 0.3 * math.sin(t * 1.3 + c.ph)
            local dx, dy = -math.cos(c.ang), -math.sin(c.ang) -- (growing inward)
            love.graphics.setColor(0.55, 0.25, 0.95, 0.16 * pulse)
            love.graphics.circle("fill", c.x, c.y, c.len * 1.6)
            for s = -1, 1 do
              local len = c.len * (s == 0 and 1 or 0.65)
              local ox, oy = c.x - dy * s * 2.5, c.y + dx * s * 2.5
              love.graphics.setColor(0.42, 0.18, 0.78, 0.95)
              love.graphics.polygon("fill", ox - dy * 1.8, oy + dx * 1.8, ox + dy * 1.8, oy - dx * 1.8, ox + dx * len, oy + dy * len)
              love.graphics.setColor(0.86, 0.6, 1, 0.9 * pulse)
              love.graphics.line(ox, oy, ox + dx * len * 0.9, oy + dy * len * 0.9)
            end
          end
        end
      end
      if info.diamonds then
        local t = love.timer.getTime()
        for di, d in ipairs(info.diamonds) do
          if visible(view, d[1], d[2], 12) then
            for k = 1, 5 do
              local h = math.sin(di * 12.9 + k * 78.2) * 43758.5
              h = h - math.floor(h)
              local h2 = math.sin(di * 39.3 + k * 11.1) * 24634.6
              h2 = h2 - math.floor(h2)
              local sx, sy = math.floor(d[1] + (h - 0.5) * 2 * d[3]), math.floor(d[2] + (h2 - 0.5) * 2 * d[3])
              local tw = math.sin(t * 2.2 + di * 3.7 + k * 1.9)
              if tw > 0.55 and world:get(sx, sy) == materials.DIAMONDORE then
                local a = (tw - 0.55) / 0.45
                love.graphics.setColor(0.85, 0.97, 1, a)
                love.graphics.rectangle("fill", sx, sy, 1, 1)
                love.graphics.setColor(0.7, 0.92, 1, a * 0.55)
                love.graphics.rectangle("fill", sx - 1, sy, 3, 1)
                love.graphics.rectangle("fill", sx, sy - 1, 1, 3)
              end
            end
          end
        end
      end
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
-- What is drawn in the dungeon's decor that stands in the world, once more for the lit sprites test (see game.draw)
-- (shadows: for the shadow pass, without the timber frames: their pillars and the beams he jumps up through
-- do not block light)
function catacombs.drawLitDecor(view, shadows)
  for _, lv in ipairs(levels) do
    local info = inArea(lv, view) and lv.info
    if info then
      if info.mine then
        minedecor.draw(info.mine, view, shadows)
      end
      if info.story then
        story.draw(info.story, view)
      end
    end
  end
end

function catacombs.drawFront(view)
  fluids.drawFront(view)
end

function catacombs.drawScreen(toScreen, font, player)
  if player and not player.dead then
    local px, py = player:center()
    local lv = altarNear(px, py)
    if lv then
      local ax, ay = altarSpot(lv)
      local sx, sy = toScreen(ax, ay - 30)
      love.graphics.setFont(font)
      local key = require("src.input").label("interact")
      local lines = { { "[" .. key .. "] " .. defyTitle(lv), { 1, 0.85, 0.6 } }, { "Seals the arena until the boss falls", { 0.85, 0.85, 0.92 } } }
      for i, l in ipairs(lines) do
        local x, y = math.floor(sx - font:getWidth(l[1]) / 2), math.floor(sy - font:getHeight() * (#lines - i + 1))
        love.graphics.setColor(0, 0, 0, 0.85)
        love.graphics.print(l[1], x + 2, y + 2)
        love.graphics.setColor(l[2])
        love.graphics.print(l[1], x, y)
      end
    end
  end
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

function catacombs.seed()
  return baseSeed
end

-- The areas that have a boss arena (for the dev panel)
function catacombs.arenaAreas()
  local out = {}
  for i = 1, #levels do
    if THEMES[i] and THEMES[i].arena then
      out[#out + 1] = i
    end
  end
  return out
end

function catacombs.areaName(i)
  return THEMES[i] and THEMES[i].name or nil
end

return catacombs
