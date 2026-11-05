-- Painted ground textures for materials that name one (materials.lua `texture = "..."`; src.world's baseColorAt asks for the
-- colour of a pixel before its grain and the depth shade are applied). Worked out from the position alone, so a crater's
-- rim keeps the pattern, like the area tints (src.decor).
--
--   stratamottle   the Barrens' sandstone: uneven beds that dip, each its own tone, with a dark seam at the base of a bed and a
--                  pale lens here and there, over broad soft patches of rust, tan and pinkish grey that wander across
--                  them (a mix of the strata and mottled-iron studies in docs/ground_designs.png)
local noise = love.math.noise

local groundtex = {}

local function clamp01(v)
  return v < 0 and 0 or (v > 1 and 1 or v)
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local RUST, TAN, PINK = { 0.50, 0.28, 0.21 }, { 0.58, 0.35, 0.27 }, { 0.56, 0.36, 0.32 }

-- The soft patches change slowly, so each 4 x 4 block of pixels shares one value, worked out once and remembered (a screenful
-- is 14,000 blocks instead of 230,000 pixels). The table is thrown away when it grows past 150,000 blocks.
local patchCache, patchCount = {}, 0

local function patch(x, y)
  local cx, cy = x - x % 4, y - y % 4
  local key = cy * 65536 + cx
  local c = patchCache[key]
  if c then
    return c[1], c[2], c[3]
  end
  if patchCount > 150000 then
    patchCache, patchCount = {}, 0
  end
  -- rust to tan along wandering bands, pink-grey where a second noise leaches the colour
  local w = noise(cx * 0.006, cy * 0.03) * 38
  local a = noise(cx * 0.004, (cy + w) * 0.022 + 5)
  local b = noise(cx * 0.012, (cy + w * 0.6) * 0.05 + 40)
  local t = clamp01((a - 0.3) * 2.2)
  local r, g, bl = lerp(RUST[1], TAN[1], t), lerp(RUST[2], TAN[2], t), lerp(RUST[3], TAN[3], t)
  local p = clamp01((b - 0.55) * 3) * 0.6
  r, g, bl = lerp(r, PINK[1], p), lerp(g, PINK[2], p), lerp(bl, PINK[3], p)
  patchCache[key] = { r, g, bl }
  patchCount = patchCount + 1
  return r, g, bl
end

local colCache, colCount = {}, 0
local function column(x)
  local c = colCache[x]
  if not c then
    if colCount > 20000 then
      colCache, colCount = {}, 0
    end
    c = noise(x * 0.01, 3.3) * 14
    colCache[x] = c
    colCount = colCount + 1
  end
  return c
end

function groundtex.stratamottle(x, y)
  local r, g, bl = patch(x, y)
  -- the beds: thickness varies with depth, a gentle dip, each bed a little lighter or darker than the patch under it
  local dip = y + x * 0.045 + column(x)
  local u = dip / 7 + noise(dip * 0.021, 9.1) * 6
  local bed = math.floor(u)
  local f = u - bed
  local h = math.sin(bed * 12.9898) * 43758.5453
  h = h - math.floor(h)
  local tone = (h - 0.5) * 0.10
  r, g, bl = r + tone, g + tone * 0.75, bl + tone * 0.6
  if f < 0.12 then -- the dark seam at the base of the bed
    r, g, bl = r * 0.84, g * 0.82, bl * 0.82
  elseif f > 0.9 then -- a pale edge on its top
    r, g, bl = r * 1.05, g * 1.05, bl * 1.04
  end
  -- a pale lens that pinches out
  local lens = noise(x * 0.025, dip * 0.09 + 20)
  if lens > 0.74 then
    local k = (lens - 0.74) * 3 * 0.45
    r, g, bl = lerp(r, 0.72, k), lerp(g, 0.52, k), lerp(bl, 0.40, k)
  end
  return r, g, bl
end

return groundtex
