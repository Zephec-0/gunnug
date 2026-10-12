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
  IRON = 10,
  SLATE = 11,
  BLUECLAY = 12,
  SULFUR = 13,
  BILECLAY = 14,
  TAILINGS = 15,
  BASALT = 16,
  ASH = 17,
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
  -- Iron plate of the shop's hatch: indestructible until its chain is shot
  [10] = {
    name = "iron",
    solid = true,
    hardness = math.huge,
    color = { 0.24, 0.25, 0.30 },
    topColor = { 0.40, 0.41, 0.48 },
    variation = 0.03,
    brick = true, -- riveted plating
  },
  -- Area 2 palette: dark grey-blue slate and blue clay
  [11] = {
    name = "slate",
    solid = true,
    hardness = 3,
    density = 2.6,
    color = { 0.19, 0.21, 0.29 },
    topColor = { 0.30, 0.34, 0.47 },
    variation = 0.05,
    bands = 0.05,
  },
  [12] = {
    name = "blue clay",
    solid = true,
    hardness = 1,
    density = 1.6,
    color = { 0.20, 0.28, 0.43 },
    topColor = { 0.24, 0.46, 0.44 }, -- a cold green moss
    variation = 0.07,
  },
  -- Area 3 palette: crusted yellow sulfur rock and olive bile clay
  [13] = {
    name = "sulfur rock",
    solid = true,
    hardness = 3,
    density = 2.3,
    color = { 0.50, 0.44, 0.15 },
    topColor = { 0.84, 0.74, 0.24 }, -- a crust of bright sulfur
    variation = 0.06,
    bands = 0.05,
  },
  [14] = {
    name = "bile clay",
    solid = true,
    hardness = 1,
    density = 1.6,
    color = { 0.22, 0.30, 0.12 },
    topColor = { 0.42, 0.62, 0.16 }, -- sickly green moss
    variation = 0.07,
  },
  -- Grey-brown spoil dug out of the old mine (the overworld's tailings)
  [15] = {
    name = "tailings",
    solid = true,
    hardness = 1,
    density = 1.7,
    color = { 0.40, 0.35, 0.31 },
    topColor = { 0.50, 0.45, 0.39 },
    variation = 0.09,
  },
  -- Area 4a palette: scorched basalt and ash (the Cinder Warrens)
  [16] = {
    name = "basalt",
    solid = true,
    hardness = 3,
    density = 2.7,
    color = { 0.27, 0.18, 0.18 },
    topColor = { 0.52, 0.30, 0.22 }, -- hot at the edges
    variation = 0.06,
    bands = 0.04,
  },
  [17] = {
    name = "ash",
    solid = true,
    hardness = 1,
    density = 1.2,
    color = { 0.30, 0.28, 0.28 },
    topColor = { 0.46, 0.41, 0.38 },
    variation = 0.08,
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
