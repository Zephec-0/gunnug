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
  DIAMONDORE = 18,
  ICE = 19,
  FOSSIL = 25,
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
    grassColors = { { 0.18, 0.28, 0.16 }, { 0.30, 0.44, 0.22 }, { 0.50, 0.64, 0.30 } }, -- blades grow along its top (src.grass)
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
    grassColors = { { 0.12, 0.30, 0.30 }, { 0.22, 0.46, 0.42 }, { 0.42, 0.68, 0.58 } },
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
    grassColors = { { 0.24, 0.40, 0.08 }, { 0.44, 0.64, 0.14 }, { 0.72, 0.86, 0.30 } },
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
  -- Rock veined with diamond: rarer than gold and worth twenty times as much a speck
  [18] = {
    name = "diamond ore",
    solid = true,
    hardness = 3,
    density = 2.8,
    color = { 0.26, 0.30, 0.40 },
    topColor = { 0.42, 0.48, 0.62 },
    variation = 0.06,
    flecks = { 0.80, 0.95, 1.0 }, -- silver-blue glints, thicker and brighter than gold's
    fleckMin = 0.46,
    gold = { 20, 40 },
  },
  -- A skin of ice on frozen water (frost rounds)
  [19] = {
    name = "ice",
    solid = true,
    hardness = 1,
    density = 0.9,
    color = { 0.55, 0.74, 0.86 },
    topColor = { 0.78, 0.92, 1.0 },
    variation = 0.05,
  },
}

-- Hardpan: sand packed solid under the camp's streets (never breaks)
materials.HARDPAN = 20
materials.defs[20] = {}
for k, v in pairs(materials.defs[4]) do
  materials.defs[20][k] = v
end
materials.defs[20].name = "hardpan"
materials.defs[20].hardness = math.huge

-- Camp timber: the planks under each person's stall and building never break
materials.HARDWOOD = 22
materials.defs[22] = {}
for k, v in pairs(materials.defs[6]) do
  materials.defs[22][k] = v
end
materials.defs[22].name = "camp timber"
materials.defs[22].hardness = math.huge

-- Sealed rock: the rock around a boss's arena, unbreakable until the boss dies
materials.SEALED = 21
materials.defs[21] = {}
for k, v in pairs(materials.defs[2]) do
  materials.defs[21][k] = v
end
materials.defs[21].name = "sealed rock"
materials.defs[21].hardness = math.huge

-- The sky's ground: banks of cloud, soft and white on top, blue in the shadowed
-- billows below (World:colorAt shades it in puffs rather than flat by depth)
materials.CLOUD = 23
materials.defs[23] = {
  name = "cloud",
  solid = true,
  hardness = 1,
  density = 0.6,
  color = { 0.80, 0.86, 0.97 },
  topColor = { 0.97, 0.98, 1.0 },
  shadow = { 0.46, 0.56, 0.80 }, -- the blue of a cloud's underside
  variation = 0.02,
  cloud = true,
}
-- Denser, greyer cloud: the islands' cores and the spires
materials.CLOUDBANK = 24
materials.defs[24] = {
  name = "cloudbank",
  solid = true,
  hardness = 2,
  density = 0.9,
  color = { 0.79, 0.85, 0.97 }, -- (all but the same look as cloud, so the two meet without a seam)
  topColor = { 0.96, 0.97, 1.0 },
  shadow = { 0.45, 0.55, 0.80 },
  variation = 0.02,
  cloud = true,
}

-- Bone buried in the desert's sandstone: skeletons you can see in the cut of the ground
materials.defs[25] = {
  name = "fossil",
  solid = true,
  hardness = 1.5,
  density = 1.6,
  color = { 0.74, 0.62, 0.50 },
  topColor = { 0.82, 0.72, 0.58 },
  variation = 0.09, -- (a mottled bone that takes on the ground's colour)
}

-- Blades of grass, stamped into the terrain when an area is generated (src.grass): not solid (bullets, the hunter
-- and the flow of water and gas pass through them), only painted, three shades of green root to tip for each
-- material that grows grass. A blade whose ground is dug away vanishes on the next repaint (see World:colorAt).
do
  local nextId = 30
  for _, id in ipairs({ 1, 12, 14 }) do
    local d = materials.defs[id]
    d.grassIds = {}
    for k = 1, 3 do
      materials.defs[nextId] = { name = "grass", solid = false, decor = true, color = d.grassColors[k], variation = 0.05 }
      d.grassIds[k] = nextId
      nextId = nextId + 1
    end
  end
end

-- Flat lookups for hot paths
materials.solid = {}
materials.anchored = {}
materials.decor = {}
for id, def in pairs(materials.defs) do
  materials.solid[id] = def.solid
  materials.decor[id] = def.decor or false
  materials.anchored[id] = def.hardness == math.huge
end

return materials
