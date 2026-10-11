-- Terrain material definitions. Ids are stored per-pixel in the world grid.
--   hardness: resistance to digging. A dig of power P removes each pixel with
--             probability P / hardness, so hard materials chip away over
--             several hits. math.huge = indestructible (and anchors terrain).
--   density:  Box2D density used when a cut-loose chunk becomes debris.
--
-- Palette: dark fantasy — muted, cool bases that the lighting darkens further,
-- with lighter tops so silhouettes stay readable.
local materials = {
  AIR = 0,
  DIRT = 1,
  ROCK = 2,
  BEDROCK = 3,
  SAND = 4,
  SANDSTONE = 5,
  WOOD = 6,
  BRICK = 7,
  STONEBRICK = 8,
  GOLDORE = 9,
}

materials.defs = {
  [0] = { name = "air", solid = false },
  [1] = {
    name = "earth",
    solid = true,
    hardness = 1,
    density = 1.5,
    color = { 0.36, 0.26, 0.22 },
    topColor = { 0.30, 0.42, 0.30 }, -- dead moss
    variation = 0.07,
  },
  [2] = {
    name = "rock",
    solid = true,
    hardness = 3,
    density = 2.5,
    color = { 0.28, 0.30, 0.40 },
    topColor = { 0.44, 0.48, 0.62 },
    variation = 0.06,
  },
  [3] = {
    name = "bedrock",
    solid = true,
    hardness = math.huge,
    color = { 0.10, 0.08, 0.13 },
    topColor = { 0.16, 0.13, 0.20 },
    variation = 0.04,
  },
  -- Desert materials (the overworld), weathered and muted for dusk
  [4] = {
    name = "sand",
    solid = true,
    hardness = 1,
    density = 1.4,
    color = { 0.66, 0.52, 0.38 },
    topColor = { 0.78, 0.64, 0.47 },
    variation = 0.06,
  },
  [5] = {
    name = "sandstone",
    solid = true,
    hardness = 2,
    density = 2.0,
    color = { 0.54, 0.32, 0.25 },
    topColor = { 0.68, 0.44, 0.32 },
    variation = 0.07,
    bands = 0.06, -- horizontal strata
  },
  [6] = {
    name = "wood",
    solid = true,
    hardness = 2,
    density = 0.8,
    color = { 0.38, 0.27, 0.19 },
    variation = 0.05,
    grain = true, -- vertical plank lines
  },
  -- Gothic stone; this variant never breaks (shop walls)
  [7] = {
    name = "masonry",
    solid = true,
    hardness = math.huge,
    color = { 0.30, 0.28, 0.34 },
    topColor = { 0.42, 0.40, 0.46 },
    variation = 0.05,
    brick = true, -- mortar pattern
  },
  -- Breakable stone blocks (ancient ruins)
  [8] = {
    name = "stone brick",
    solid = true,
    hardness = 3,
    density = 2.4,
    color = { 0.40, 0.38, 0.43 },
    topColor = { 0.52, 0.50, 0.55 },
    variation = 0.05,
    brick = true,
  },
  -- Rock veined with gold: spills coins when dug out (destruction.dig)
  [9] = {
    name = "gold ore",
    solid = true,
    hardness = 2,
    density = 2.8,
    color = { 0.30, 0.30, 0.38 },
    topColor = { 0.46, 0.46, 0.58 },
    variation = 0.06,
    flecks = { 0.95, 0.74, 0.22 }, -- gold glints scattered through it
    gold = { 1, 2 }, -- gold per speck (a tenth of the pixels dug out give one)
  },
}

-- Flat lookups for hot paths
materials.solid = {}
materials.anchored = {}
for id, def in pairs(materials.defs) do
  materials.solid[id] = def.solid
  materials.anchored[id] = def.hardness == math.huge
end

return materials
