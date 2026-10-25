-- Dressing for the areas that have no grass: moss, roots, drips, rubble, crystals, coral and the like, plus the
-- area's own colouring of its rock. All of it is baked once while the area is generated (the same way as the
-- grass, src.grass), so nothing here runs while the game is played:
--   * decoration pixels: non-solid materials stamped into the terrain (materials.decorKit), painted with the rest
--     of it and gone again if the rock they stand on, hang from or cling to is dug away (World:colorAt);
--   * tints: layers of strata, streaks and blotches blended over the rock and earth where it is painted
--     (World:addTint), worked out from the position alone, so craters keep the pattern.
--
-- An area names a set (`decor = "quarry"` in src.scenes.catacombs); decor.sets[name] = { tint = layers, items... }.
-- An item has a shape and where it grows:
--   floor shapes ("tuft", "mound") stand on the ground; ceiling shapes ("strand", "fringe") hang from the rock
--   above; wall shapes ("streak") cling to a wall face. cover is the share of such spots that get one.
--   water = "avoid" (not in a pool or the flood) / "only" (underwater only); from, to = the part of the area's
--   height it grows in (0 = top, 1 = bottom).
local materials = require("src.materials")

local decor = {}

local floor = math.floor

local function hash(x, y, k)
  local n = math.sin(x * 12.9898 + y * 78.233 + k * 37.719) * 43758.5453
  return n - floor(n)
end

local function rgb(r, g, b)
  return { r, g, b }
end

-- ---------------------------------------------------------------------------------------------------------------
-- The sets. Colours run root to tip (a streak: top to end) in three shades.
-- ---------------------------------------------------------------------------------------------------------------
local sets = {}
decor.sets = sets

-- The Cinder Warrens and the Ember Foundry: scorched basalt, ash drifts, cooled lava spikes, burnt roots, glowing seams
sets.cinder = {
  tint = {
    { kind = "strata", color = rgb(0.08, 0.06, 0.06), amount = 0.38, freq = 0.3, cut = 0.55 }, -- soot bands
    { kind = "blotch", color = rgb(0.60, 0.20, 0.08), amount = 0.20, freq = 0.05, cut = 0.64, seed = 3 }, -- heat-scorched patches
    { kind = "streak", color = rgb(0.16, 0.12, 0.12), amount = 0.30, freq = 0.55, cut = 0.6 },
  },
  { shape = "mound", name = "ashdrift", cover = 0.09, w = { 4, 10 }, h = { 1, 3 }, colors = { rgb(0.20, 0.18, 0.18), rgb(0.33, 0.31, 0.30), rgb(0.46, 0.43, 0.41) }, water = "avoid" },
  { shape = "mound", name = "cinders", cover = 0.04, w = { 2, 5 }, h = { 1, 2 }, colors = { rgb(0.16, 0.08, 0.06), rgb(0.40, 0.16, 0.07), rgb(0.85, 0.40, 0.12) }, water = "avoid" },
  { shape = "tuft", name = "lavaspike", cover = 0.035, h = { 2, 6 }, twin = 0.5, colors = { rgb(0.22, 0.09, 0.07), rgb(0.50, 0.19, 0.08), rgb(1.0, 0.56, 0.18) }, water = "avoid" },
  { shape = "strand", name = "charroot", cover = 0.022, len = { 4, 17 }, sway = 1, colors = { rgb(0.13, 0.09, 0.08), rgb(0.23, 0.15, 0.11), rgb(0.34, 0.22, 0.15) }, water = "avoid" },
  { shape = "streak", name = "emberseam", cover = 0.006, len = { 5, 15 }, colors = { rgb(0.30, 0.10, 0.06), rgb(0.70, 0.25, 0.08), rgb(1.0, 0.52, 0.16) }, water = "avoid" },
}

-- The Drowned Halls and the Silt Vaults: wet slate, hanging weed, drips, algae on the walls, silt and reeds
sets.drowned = {
  tint = {
    { kind = "blotch", color = rgb(0.12, 0.38, 0.32), amount = 0.12, freq = 0.014, cut = 0.4, soft = 1.6, seed = 5 }, -- algae stains
    { kind = "strata", color = rgb(0.04, 0.07, 0.13), amount = 0.10, freq = 0.28, cut = 0.3, soft = 1.5 },
    { kind = "streak", color = rgb(0.30, 0.50, 0.62), amount = 0.07, freq = 0.6, cut = 0.4, soft = 1.5 }, -- mineral runs
  },
  { shape = "strand", name = "dripweed", cover = 0.03, len = { 3, 15 }, sway = 1, colors = { rgb(0.09, 0.27, 0.29), rgb(0.17, 0.41, 0.39), rgb(0.34, 0.64, 0.57) } },
  { shape = "strand", name = "drip", cover = 0.014, len = { 2, 6 }, colors = { rgb(0.36, 0.50, 0.66), rgb(0.58, 0.76, 0.90), rgb(0.92, 0.98, 1.0) }, water = "avoid" },
  { shape = "streak", name = "algae", cover = 0.014, len = { 2, 9 }, colors = { rgb(0.07, 0.21, 0.22), rgb(0.13, 0.35, 0.33), rgb(0.25, 0.55, 0.48) } },
  { shape = "mound", name = "silt", cover = 0.12, w = { 4, 11 }, h = { 1, 2 }, colors = { rgb(0.11, 0.15, 0.21), rgb(0.19, 0.25, 0.35), rgb(0.29, 0.37, 0.49) } },
  { shape = "tuft", name = "reeds", cover = 0.09, h = { 2, 7 }, colors = { rgb(0.13, 0.28, 0.33), rgb(0.24, 0.48, 0.48), rgb(0.52, 0.78, 0.72) } },
}

-- The Quarry and the Foreman's Hall: rubble, dry scrub, rust runs down the walls, roots, amber shards
sets.quarry = {
  tint = {
    { kind = "blotch", color = rgb(0.80, 0.64, 0.44), amount = 0.10, freq = 0.012, cut = 0.4, soft = 1.6, seed = 7 }, -- faint pale patches, broad and soft
    { kind = "blotch", color = rgb(0.50, 0.22, 0.10), amount = 0.08, freq = 0.015, cut = 0.4, soft = 1.6, seed = 13 }, -- a little rust
    { kind = "blotch", color = rgb(0.18, 0.12, 0.09), amount = 0.08, freq = 0.02, cut = 0.4, soft = 1.6, seed = 9 }, -- soot
  },
  { shape = "mound", name = "rubble", cover = 0.09, w = { 3, 9 }, h = { 1, 3 }, colors = { rgb(0.30, 0.25, 0.22), rgb(0.46, 0.40, 0.34), rgb(0.63, 0.56, 0.47) }, water = "avoid" },
  { shape = "tuft", name = "scrub", cover = 0.12, h = { 2, 5 }, lean = true, colors = { rgb(0.26, 0.20, 0.11), rgb(0.44, 0.35, 0.17), rgb(0.63, 0.53, 0.28) }, water = "avoid" },
  { shape = "tuft", name = "amberspike", cover = 0.014, h = { 3, 7 }, twin = 0.7, colors = { rgb(0.45, 0.27, 0.09), rgb(0.85, 0.55, 0.18), rgb(1.0, 0.86, 0.48) }, water = "avoid" },
  { shape = "streak", name = "rust", cover = 0.007, len = { 6, 20 }, colors = { rgb(0.30, 0.13, 0.07), rgb(0.47, 0.20, 0.09), rgb(0.62, 0.31, 0.14) }, water = "avoid" },
  { shape = "strand", name = "dustroot", cover = 0.016, len = { 4, 13 }, sway = 1, colors = { rgb(0.27, 0.20, 0.13), rgb(0.40, 0.30, 0.19), rgb(0.54, 0.42, 0.27) }, water = "avoid" },
  { shape = "fringe", name = "cobweb", cover = 0.01, w = { 4, 10 }, colors = { rgb(0.60, 0.58, 0.54), rgb(0.76, 0.74, 0.70), rgb(0.88, 0.87, 0.84) }, water = "avoid" },
}

-- The Needle: wind-cut sandstone, sand drifts and scree below, frost, icicles and ice ledges toward the summit
sets.needle = {
  tint = {
    { kind = "blotch", color = rgb(0.82, 0.64, 0.46), amount = 0.08, freq = 0.012, cut = 0.4, soft = 1.6, seed = 5 }, -- faint pale patches
    { kind = "blotch", color = rgb(0.80, 0.90, 1.0), amount = 0.14, freq = 0.014, cut = 0.4, soft = 1.6, seed = 2, from = 0.0, to = 0.55 }, -- rime on the high rock
    { kind = "blotch", color = rgb(0.28, 0.34, 0.16), amount = 0.10, freq = 0.014, cut = 0.4, soft = 1.6, seed = 8, from = 0.7, to = 1.0 }, -- lichen on the low
  },
  { shape = "mound", name = "drift", cover = 0.10, w = { 5, 13 }, h = { 1, 2 }, colors = { rgb(0.55, 0.42, 0.30), rgb(0.70, 0.56, 0.40), rgb(0.82, 0.70, 0.52) } },
  { shape = "mound", name = "scree", cover = 0.05, w = { 2, 6 }, h = { 1, 2 }, colors = { rgb(0.26, 0.21, 0.19), rgb(0.42, 0.34, 0.29), rgb(0.58, 0.49, 0.41) } },
  { shape = "mound", name = "snowcap", cover = 0.12, w = { 4, 12 }, h = { 1, 2 }, colors = { rgb(0.62, 0.72, 0.82), rgb(0.82, 0.90, 0.97), rgb(0.97, 0.99, 1.0) }, from = 0.0, to = 0.55 },
  { shape = "tuft", name = "alpine", cover = 0.05, h = { 2, 4 }, colors = { rgb(0.24, 0.27, 0.12), rgb(0.44, 0.48, 0.21), rgb(0.68, 0.70, 0.34) }, from = 0.6, to = 1.0 },
  { shape = "strand", name = "icicle", cover = 0.03, len = { 3, 12 }, taper = true, colors = { rgb(0.50, 0.66, 0.78), rgb(0.76, 0.89, 0.96), rgb(0.97, 1.0, 1.0) }, from = 0.0, to = 0.6 },
  { shape = "streak", name = "frost", cover = 0.012, len = { 3, 10 }, colors = { rgb(0.52, 0.68, 0.82), rgb(0.76, 0.88, 0.96), rgb(0.96, 0.99, 1.0) }, from = 0.0, to = 0.6 },
  { shape = "strand", name = "dustroot", cover = 0.012, len = { 4, 12 }, sway = 1, colors = { rgb(0.27, 0.20, 0.13), rgb(0.40, 0.30, 0.19), rgb(0.54, 0.42, 0.27) }, from = 0.5, to = 1.0 },
  { shape = "tuft", name = "iceshard", cover = 0.012, h = { 3, 7 }, twin = 0.6, colors = { rgb(0.45, 0.62, 0.78), rgb(0.72, 0.86, 0.96), rgb(1.0, 1.0, 1.0) }, from = 0.0, to = 0.6 },
}

-- The Cloud Reaches: wisps hanging under the islands, puffs and star-glass on top, sky vines, a sunset in the cloud
sets.sky = {
  tint = {
    { kind = "strata", color = rgb(1.0, 0.76, 0.70), amount = 0.30, freq = 0.22, cut = 0.45 }, -- peach bands
    { kind = "blotch", color = rgb(0.72, 0.62, 0.95), amount = 0.26, freq = 0.02, cut = 0.5, seed = 4 }, -- lilac
    { kind = "blotch", color = rgb(1.0, 0.92, 0.65), amount = 0.20, freq = 0.03, cut = 0.62, seed = 12 }, -- gold
  },
  { shape = "strand", name = "wisp", cover = 0.07, len = { 3, 14 }, sway = 1, taper = true, colors = { rgb(0.78, 0.84, 0.97), rgb(0.88, 0.92, 1.0), rgb(0.97, 0.98, 1.0) } },
  { shape = "mound", name = "puff", cover = 0.13, w = { 4, 11 }, h = { 1, 3 }, colors = { rgb(0.80, 0.84, 0.96), rgb(0.92, 0.94, 1.0), rgb(1.0, 1.0, 1.0) } },
  { shape = "tuft", name = "starglass", cover = 0.014, h = { 2, 6 }, twin = 0.5, colors = { rgb(0.50, 0.68, 0.98), rgb(0.76, 0.88, 1.0), rgb(1.0, 1.0, 1.0) } },
  { shape = "strand", name = "skyvine", cover = 0.012, len = { 6, 22 }, sway = 2, colors = { rgb(0.50, 0.62, 0.34), rgb(0.68, 0.80, 0.44), rgb(0.92, 0.96, 0.66) } },
  { shape = "tuft", name = "cloudgrass", cover = 0.06, h = { 2, 4 }, lean = true, colors = { rgb(0.64, 0.74, 0.60), rgb(0.78, 0.88, 0.70), rgb(0.94, 0.98, 0.84) } },
}

-- The Flooded Caverns and the Deep: kelp forests, coral, shell sand and barnacles underwater; moss and drips above it
sets.flooded = {
  tint = {
    { kind = "blotch", color = rgb(0.14, 0.40, 0.30), amount = 0.12, freq = 0.014, cut = 0.4, soft = 1.6, seed = 6 }, -- algae
    { kind = "blotch", color = rgb(0.03, 0.05, 0.12), amount = 0.22, freq = 0.01, cut = 0.4, soft = 1.6, seed = 1, from = 0.6, to = 1.0 }, -- the dark of the deep
  },
  { shape = "tuft", name = "kelp", cover = 0.06, h = { 6, 16 }, sway = 2, water = "only", colors = { rgb(0.09, 0.28, 0.14), rgb(0.17, 0.44, 0.22), rgb(0.36, 0.70, 0.36) } },
  { shape = "tuft", name = "coral", cover = 0.022, h = { 3, 8 }, twin = 0.8, water = "only", colors = { rgb(0.55, 0.16, 0.28), rgb(0.85, 0.38, 0.44), rgb(1.0, 0.72, 0.66) } },
  { shape = "tuft", name = "fan", cover = 0.012, h = { 3, 7 }, twin = 0.9, lean = true, water = "only", colors = { rgb(0.55, 0.36, 0.14), rgb(0.85, 0.60, 0.22), rgb(1.0, 0.88, 0.50) } },
  { shape = "mound", name = "shellsand", cover = 0.14, w = { 4, 12 }, h = { 1, 2 }, water = "only", colors = { rgb(0.28, 0.31, 0.36), rgb(0.44, 0.49, 0.54), rgb(0.64, 0.70, 0.72) } },
  { shape = "streak", name = "barnacle", cover = 0.02, len = { 1, 4 }, water = "only", colors = { rgb(0.38, 0.43, 0.48), rgb(0.64, 0.70, 0.73), rgb(0.90, 0.92, 0.90) } },
  { shape = "strand", name = "hangweed", cover = 0.035, len = { 4, 16 }, sway = 2, water = "only", colors = { rgb(0.08, 0.26, 0.26), rgb(0.15, 0.40, 0.37), rgb(0.30, 0.62, 0.54) } },
  { shape = "streak", name = "moss", cover = 0.03, len = { 2, 8 }, water = "avoid", colors = { rgb(0.10, 0.25, 0.20), rgb(0.18, 0.38, 0.28), rgb(0.30, 0.56, 0.38) } },
  { shape = "strand", name = "drip", cover = 0.014, len = { 2, 6 }, water = "avoid", colors = { rgb(0.36, 0.50, 0.66), rgb(0.58, 0.76, 0.90), rgb(0.92, 0.98, 1.0) } },
}

-- The Undercroft, under the fossil beds (the Greywacke): hard grey rock with a green-brown cast, clay red strata,
-- scree, lichen, clay drifts and pale green stone
sets.greywacke = {
  tint = {
    { kind = "strata", color = rgb(0.58, 0.22, 0.14), amount = 0.24, freq = 0.17, cut = 0.5 }, -- clay red bands
    { kind = "blotch", color = rgb(0.36, 0.48, 0.28), amount = 0.18, freq = 0.014, cut = 0.4, soft = 1.6, seed = 21 }, -- muted green staining
    { kind = "streak", color = rgb(0.20, 0.18, 0.15), amount = 0.18, freq = 0.5, cut = 0.55 },
  },
  { shape = "mound", name = "gwscree", cover = 0.09, w = { 3, 9 }, h = { 1, 3 }, colors = { rgb(0.24, 0.26, 0.22), rgb(0.38, 0.41, 0.34), rgb(0.54, 0.56, 0.46) }, water = "avoid" },
  { shape = "tuft", name = "gwlichen", cover = 0.09, h = { 1, 3 }, lean = true, colors = { rgb(0.22, 0.30, 0.15), rgb(0.38, 0.48, 0.24), rgb(0.58, 0.68, 0.38) }, water = "avoid" },
  { shape = "mound", name = "gwclay", cover = 0.05, w = { 4, 11 }, h = { 1, 2 }, colors = { rgb(0.34, 0.16, 0.12), rgb(0.52, 0.26, 0.18), rgb(0.68, 0.38, 0.26) }, water = "avoid" },
  { shape = "strand", name = "gwroot", cover = 0.02, len = { 4, 13 }, sway = 1, colors = { rgb(0.22, 0.17, 0.12), rgb(0.34, 0.26, 0.17), rgb(0.48, 0.37, 0.24) }, water = "avoid" },
  { shape = "streak", name = "gwiron", cover = 0.007, len = { 5, 16 }, colors = { rgb(0.30, 0.13, 0.08), rgb(0.50, 0.22, 0.12), rgb(0.66, 0.32, 0.18) }, water = "avoid" },
  { shape = "tuft", name = "gwgreenstone", cover = 0.012, h = { 3, 6 }, twin = 0.6, colors = { rgb(0.26, 0.40, 0.28), rgb(0.50, 0.68, 0.46), rgb(0.82, 0.94, 0.70) }, water = "avoid" },
}

-- The buried city: grey slate and clay, dust lying over it in drifts, cracks, dead roots and cobweb
sets.buriedcity = {
  tint = {
    { kind = "blotch", color = rgb(0.80, 0.75, 0.66), amount = 0.24, freq = 0.012, cut = 0.35, soft = 1.8, seed = 31 }, -- dust lying over it
    { kind = "strata", color = rgb(0.52, 0.27, 0.20), amount = 0.16, freq = 0.22, cut = 0.5 }, -- clay bands
    { kind = "blotch", color = rgb(0.10, 0.09, 0.10), amount = 0.14, freq = 0.02, cut = 0.42, soft = 1.5, seed = 37 }, -- soot
  },
  { shape = "mound", name = "bcdust", cover = 0.22, w = { 6, 16 }, h = { 1, 3 }, colors = { rgb(0.40, 0.37, 0.33), rgb(0.60, 0.56, 0.49), rgb(0.78, 0.74, 0.66) }, water = "avoid" },
  { shape = "mound", name = "bcrubble", cover = 0.08, w = { 3, 8 }, h = { 1, 3 }, colors = { rgb(0.22, 0.21, 0.21), rgb(0.36, 0.35, 0.34), rgb(0.50, 0.48, 0.45) }, water = "avoid" },
  { shape = "strand", name = "bcdeadroot", cover = 0.018, len = { 4, 14 }, sway = 1, colors = { rgb(0.20, 0.16, 0.13), rgb(0.32, 0.26, 0.20), rgb(0.46, 0.38, 0.29) }, water = "avoid" },
  { shape = "fringe", name = "bccobweb", cover = 0.012, w = { 4, 10 }, colors = { rgb(0.56, 0.55, 0.53), rgb(0.72, 0.71, 0.68), rgb(0.86, 0.85, 0.82) }, water = "avoid" },
  { shape = "streak", name = "bccrack", cover = 0.01, len = { 5, 17 }, colors = { rgb(0.08, 0.07, 0.07), rgb(0.14, 0.13, 0.13), rgb(0.22, 0.21, 0.20) }, water = "avoid" },
  { shape = "streak", name = "bcclay", cover = 0.008, len = { 5, 14 }, colors = { rgb(0.32, 0.15, 0.11), rgb(0.50, 0.24, 0.17), rgb(0.64, 0.34, 0.24) }, water = "avoid" },
}

-- The core: dark brown and grey rock, soot, ash, cooled slag and seams of magma
sets.core = {
  tint = {
    { kind = "strata", color = rgb(0.06, 0.05, 0.05), amount = 0.40, freq = 0.28, cut = 0.5 }, -- soot bands
    { kind = "blotch", color = rgb(0.36, 0.21, 0.12), amount = 0.22, freq = 0.02, cut = 0.45, soft = 1.5, seed = 41 }, -- dark brown
    { kind = "blotch", color = rgb(0.95, 0.38, 0.10), amount = 0.16, freq = 0.05, cut = 0.68, seed = 43 }, -- magma showing through
    { kind = "streak", color = rgb(0.28, 0.27, 0.27), amount = 0.22, freq = 0.5, cut = 0.58 },
  },
  { shape = "mound", name = "coreash", cover = 0.10, w = { 4, 12 }, h = { 1, 3 }, colors = { rgb(0.17, 0.16, 0.16), rgb(0.30, 0.28, 0.27), rgb(0.44, 0.41, 0.39) }, water = "avoid" },
  { shape = "mound", name = "coreslag", cover = 0.05, w = { 2, 6 }, h = { 1, 2 }, colors = { rgb(0.14, 0.09, 0.07), rgb(0.32, 0.14, 0.08), rgb(0.78, 0.34, 0.10) }, water = "avoid" },
  { shape = "tuft", name = "corespike", cover = 0.035, h = { 2, 7 }, twin = 0.5, colors = { rgb(0.20, 0.10, 0.08), rgb(0.46, 0.18, 0.08), rgb(1.0, 0.54, 0.16) }, water = "avoid" },
  { shape = "strand", name = "coreroot", cover = 0.02, len = { 4, 15 }, sway = 1, colors = { rgb(0.12, 0.09, 0.08), rgb(0.22, 0.15, 0.11), rgb(0.32, 0.22, 0.15) }, water = "avoid" },
  { shape = "streak", name = "coreseam", cover = 0.01, len = { 6, 18 }, colors = { rgb(0.30, 0.10, 0.06), rgb(0.74, 0.26, 0.08), rgb(1.0, 0.56, 0.18) }, water = "avoid" },
}

-- ---------------------------------------------------------------------------------------------------------------
-- Shapes. Each puts decoration pixels (stampPixel only ever writes into open air) for a spot found by the scan.
-- ---------------------------------------------------------------------------------------------------------------
local function range(r, u)
  return r[1] + floor(u * (r[2] - r[1] + 1))
end

-- A blade, spike or stalk of kelp standing on (x, y), the first open pixel over the ground
local function tuft(world, item, ids, x, y, salt)
  local h = range(item.h, hash(x, y, salt + 1))
  for k = 1, h + 1 do
    if world:isSolid(x, y - k) then
      h = k - 1
      break
    end
  end
  if h < 2 then
    return false
  end
  local lean = (item.lean or h >= 5) and (hash(x, y, salt + 2) < 0.5 and -1 or 1) or 0
  local sway = item.sway
  local phase = hash(x, y, salt + 3) * 6.28
  local off = 0
  for k = 0, h - 1 do
    if sway then
      off = floor(math.sin(k * 0.55 + phase) * sway + 0.5)
    elseif lean ~= 0 and k >= floor(h / 2) then
      off = lean
    end
    world:stampPixel(x + off, y - k, k == 0 and ids[1] or (k == h - 1 and ids[3] or ids[2]))
  end
  -- (a shorter second blade beside it)
  if item.twin and hash(x, y, salt + 4) < item.twin and not world:isSolid(x + 1, y - 1) and world:isSolid(x + 1, y) then
    for k = 0, math.max(1, h - 3) do
      world:stampPixel(x + 1, y - k, k == 0 and ids[1] or (k == h - 3 and ids[3] or ids[2]))
    end
  end
  return true
end

-- A heap over the ground, w wide and h tall at its middle
local function mound(world, item, ids, x, y, salt)
  local w = range(item.w, hash(x, y, salt + 1))
  local h = range(item.h, hash(x, y, salt + 2))
  local half = floor(w / 2)
  for dx = -half, half do
    -- (the ground at this column, within a few pixels of the spot)
    local gy
    for yy = y - 3, y + 4 do
      if world:isSolid(dx + x, yy + 1) and not world:isSolid(dx + x, yy) then
        gy = yy
        break
      end
    end
    if gy then
      local k = 1 - (dx / (half + 1)) ^ 2
      local ch = floor(h * k + 0.5 + (hash(x + dx, y, salt + 3) - 0.5) * 0.8)
      for j = 0, ch - 1 do
        local c = j == ch - 1 and ids[3] or (j == 0 and ids[1] or ids[2])
        if hash(x + dx, y - j, salt + 4) < 0.15 then
          c = ids[1 + floor(hash(x + dx, j, salt + 5) * 3)]
        end
        world:stampPixel(x + dx, gy - j, c)
      end
    end
  end
  return true
end

-- A strand hanging from the ceiling; (x, y) is the first open row under the rock
local function strand(world, item, ids, x, y, salt)
  local len = range(item.len, hash(x, y, salt + 1))
  local sway = item.sway
  local phase = hash(x, y, salt + 3) * 6.28
  for k = 0, len - 1 do
    local off = sway and floor(math.sin(k * 0.45 + phase) * sway + 0.5) or 0
    local t = k / math.max(1, len - 1)
    if item.taper and t > 0.7 and k > 0 and hash(x, y, salt + 6 + k) < 0.4 then
      break
    end
    if world:isSolid(x + off, y + k) then
      break
    end
    world:stampPixel(x + off, y + k, k == len - 1 and ids[3] or (t > 0.5 and ids[2] or ids[1]))
  end
  return true
end

-- A fringe of growth along the underside of the ceiling, w wide and one or two pixels deep
local function fringe(world, item, ids, x, y, salt)
  local w = range(item.w, hash(x, y, salt + 1))
  for dx = 0, w - 1 do
    local px = x + dx
    if not world:isSolid(px, y) and world:isSolid(px, y - 1) then
      world:stampPixel(px, y, ids[1 + floor(hash(px, y, salt + 2) * 2)])
      if hash(px, y, salt + 3) < 0.45 then
        world:stampPixel(px, y + 1, ids[3])
      end
    end
  end
  return true
end

-- A run down a wall face: the open pixels beside it, top to bottom, fading from the first shade to the last
local function streak(world, item, ids, x, y, side, salt)
  local len = range(item.len, hash(x, y, salt + 1))
  for k = 0, len - 1 do
    if world:isSolid(x, y + k) or not world:isSolid(x + side, y + k) then
      break
    end
    local t = k / math.max(1, len - 1)
    local c = t < 0.34 and ids[1] or (t < 0.8 and ids[2] or ids[3])
    if hash(x, y + k, salt + 2) < 0.18 then
      c = ids[2]
    end
    world:stampPixel(x, y + k, c)
  end
  return true
end

-- ---------------------------------------------------------------------------------------------------------------

-- Bakes the set into the area. x0..x1, y0..y1: the area; hostIds = { [id] = true } for the rock and earth of the
-- area (decoration only grows on them); pools, cellSize, flood: the water (as for the grass); inside(x, y)
-- tells whether a spot is inside the area's own cave (a mountain's silhouette); tick() gives the frame back
function decor.bake(world, name, seed, x0, y0, x1, y1, hostIds, pools, cellSize, flood, inside, tick)
  local set = sets[name]
  if not set then
    return 0
  end
  local H = y1 - y0 + 1
  -- (what is beside, over and under water)
  local wet = {}
  for _, list in ipairs(pools) do
    for _, pool in ipairs(list) do
      local cells = pool.cells
      for i = 1, #cells, 2 do
        wet[floor(cells[i + 1] / cellSize) * 100000 + floor(cells[i] / cellSize)] = true
      end
    end
  end
  local function inWater(x, y)
    if flood and y >= flood.top - 2 then
      return true
    end
    return wet[floor(y / cellSize) * 100000 + floor(x / cellSize)] or false
  end

  -- Split the items by the kind of spot they grow at, with their materials made
  local salt0 = seed % 997
  local lists = { floor = {}, ceil = {}, wall = {} }
  for i, item in ipairs(set) do
    local ids = materials.decorKit(name .. ":" .. item.name, item.shape == "streak" and "near" or (item.shape == "tuft" or item.shape == "mound") and "below" or "above", item.colors)
    local entry = {
      item = item,
      ids = ids,
      salt = salt0 + i * 11,
      y0 = y0 + floor((item.from or 0) * H),
      y1 = y0 + floor((item.to or 1) * H),
    }
    local list = (item.shape == "tuft" or item.shape == "mound") and lists.floor or (item.shape == "streak") and lists.wall or lists.ceil
    list[#list + 1] = entry
  end

  local function allowed(entry, x, y)
    if y < entry.y0 or y > entry.y1 then
      return false
    end
    local w = entry.item.water
    if w then
      local wetHere = inWater(x, y)
      if (w == "only") ~= wetHere then
        return false
      end
    end
    return true
  end

  -- Three columns are kept at a time (solid or not), so each pixel of the area is asked about once
  local function column(x)
    local c = {}
    for y = y0, y1 do
      c[y] = world:isSolid(x, y) or false
    end
    return c
  end
  local prev, cur, nxt = column(x0 - 1), column(x0), column(x0 + 1)
  local count = 0
  local get = world.get
  for x = x0, x1 do
    for y = y0 + 1, y1 - 1 do
      if not cur[y] then
        local cx, cy = x, y
        -- the ground under an open pixel
        if cur[y + 1] and hostIds[get(world, x, y + 1)] then
          for _, e in ipairs(lists.floor) do
            local it = e.item
            if hash(x, y, e.salt) < it.cover and allowed(e, x, y) and inside(x, y) then
              if it.shape == "tuft" then
                if tuft(world, it, e.ids, x, y, e.salt) then
                  count = count + 1
                end
              elseif mound(world, it, e.ids, x, y, e.salt) then
                count = count + 1
              end
              break
            end
          end
        elseif cur[y - 1] and hostIds[get(world, x, y - 1)] then
          for _, e in ipairs(lists.ceil) do
            local it = e.item
            if hash(x, y, e.salt) < it.cover and allowed(e, x, y) and inside(x, y) then
              if it.shape == "strand" then
                strand(world, it, e.ids, x, y, e.salt)
              else
                fringe(world, it, e.ids, x, y, e.salt)
              end
              count = count + 1
              break
            end
          end
        end
        -- a wall face beside it
        local side = (prev[y] and -1) or (nxt[y] and 1)
        if side and not cur[y - 1] and hostIds[get(world, x + side, y)] then
          for _, e in ipairs(lists.wall) do
            local it = e.item
            if hash(x, y, e.salt) < it.cover and allowed(e, x, y) and inside(x, y) then
              streak(world, it, e.ids, x, y, side, e.salt)
              count = count + 1
              break
            end
          end
        end
      end
    end
    prev, cur, nxt = cur, nxt, column(x + 2)
    if x % 6 == 0 then
      tick()
    end
  end
  return count
end

-- Registers the set's colouring of the area's rock and earth (see World:addTint)
function decor.tint(world, name, x0, y0, x1, y1, hostIdList)
  local set = sets[name]
  if not set or not set.tint then
    return
  end
  local H = y1 - y0
  local layers = {}
  for i, L in ipairs(set.tint) do
    local copy = {}
    for k, v in pairs(L) do
      copy[k] = v
    end
    if L.from or L.to then
      copy.y0 = y0 + floor((L.from or 0) * H)
      copy.y1 = y0 + floor((L.to or 1) * H)
    end
    layers[i] = copy
  end
  world:addTint(x0, y0, x1, y1, layers, hostIdList)
end

return decor
