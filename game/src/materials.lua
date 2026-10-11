-- Terrain material definitions. Ids are stored per-pixel in the world grid.
--   hardness: resistance to digging. A dig of power P removes each pixel with
--             probability P / hardness, so hard materials chip away over
--             several hits. math.huge = indestructible (and anchors terrain).
--   density:  Box2D density used when a cut-loose chunk becomes debris.
local materials = {
  AIR = 0,
  DIRT = 1,
  ROCK = 2,
  BEDROCK = 3,
  SAND = 4,
  SANDSTONE = 5,
  WOOD = 6,
  BRICK = 7,
}

materials.defs = {
  [0] = { name = "air", solid = false },
  [1] = {
    name = "dirt",
    solid = true,
    hardness = 1,
    density = 1.5,
    color = { 0.72, 0.40, 0.20 },
    topColor = { 0.42, 0.78, 0.28 }, -- mossy surface
    variation = 0.10,
  },
  [2] = {
    name = "rock",
    solid = true,
    hardness = 3,
    density = 2.5,
    color = { 0.38, 0.40, 0.62 },
    topColor = { 0.58, 0.62, 0.86 },
    variation = 0.08,
  },
  [3] = {
    name = "bedrock",
    solid = true,
    hardness = math.huge,
    color = { 0.18, 0.12, 0.26 },
    topColor = { 0.28, 0.20, 0.38 },
    variation = 0.05,
  },
  [4] = {
    name = "sand",
    solid = true,
    hardness = 1,
    density = 1.4,
    color = { 0.96, 0.74, 0.40 },
    topColor = { 1.0, 0.86, 0.55 },
    variation = 0.06,
  },
  [5] = {
    name = "sandstone",
    solid = true,
    hardness = 2,
    density = 2.0,
    color = { 0.82, 0.38, 0.24 },
    topColor = { 0.95, 0.55, 0.32 },
    variation = 0.07,
    bands = 0.06, -- horizontal strata
  },
  [6] = {
    name = "wood",
    solid = true,
    hardness = 2,
    density = 0.8,
    color = { 0.55, 0.33, 0.16 },
    variation = 0.05,
    grain = true, -- vertical plank lines
  },
  [7] = {
    name = "brick",
    solid = true,
    hardness = math.huge,
    color = { 0.62, 0.26, 0.24 },
    topColor = { 0.72, 0.34, 0.30 },
    variation = 0.05,
    brick = true, -- mortar pattern
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
