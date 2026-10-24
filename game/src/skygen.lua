-- The Cloud Reaches' layout (called by src.cavegen for an `open` area that has `skyRoute`): a guided climb from the
-- landing in the east to the Citadel in the west, in three bands,
--   1  the Cloud Sea     broad cloud islands low over the floor, a safe landing and the shop beside it
--   2  the Ruins         narrower islands with broken colonnades and bridges, more vertical
--   3  the Star Fields   small islands far apart, gust vents to cross the widest gaps
-- Side branches (stairs of small islands, or an island at the top of a vent) hold the chests. The floor is a net under
-- all of it, except two real gaps in the east, over the summit of the mountain, where a fall lands back on top of it.
-- A wreck lies half buried in the sea floor under the Ruins: the area's secret.
--
-- build() carves the islands, columns, bridges and the wreck, and returns what the runtime needs:
--   { islands, vents, bells, wreck, chestSpots, mobs, bands, floorTop, gaps }
local materials = require("src.materials")

local skygen = {}

local BAND_X1, BAND_X2 = 6000, 3300 -- the bands: east of the first, between, west of the second
skygen.BAND_X1, skygen.BAND_X2 = BAND_X1, BAND_X2
local WRECK_X = 5150

-- Island parameters per band: radii, gaps between neighbours, and how much each step may rise
local P = {
  { rx = { 60, 170 }, ry = { 12, 32 }, gap = { 30, 85 } },
  { rx = { 30, 100 }, ry = { 9, 24 }, gap = { 70, 140 } },
  { rx = { 18, 56 }, ry = { 7, 18 }, gap = { 110, 185 } },
}

-- Some islands are stepping stones and some are great banks: sizes are rolled with these on top
local function sizeRoll(rng, p, R)
  local rx, ry = R(p.rx[1], p.rx[2]), R(p.ry[1], p.ry[2])
  local r = rng:random()
  if r < 0.16 then
    return R(14, 24), R(6, 9), "stone"
  elseif r < 0.30 then
    return rx * R(1.5, 1.9), ry * R(1.2, 1.5), "bank"
  end
  return rx, ry, "plain"
end

local function bandOf(x)
  return x >= BAND_X1 and 1 or x >= BAND_X2 and 2 or 3
end

-- c: { world, rng, tick, X0, Y0, X1, Y1, BORDER, ROCKID, DIRTID, noiseSeed, area, arena, shopX }
function skygen.build(c)
  local world, rng, tick = c.world, c.rng, c.tick
  local X0, Y0, X1, Y1 = c.X0, c.Y0, c.X1, c.Y1
  local ROCKID, DIRTID, AIR = c.ROCKID, c.DIRTID, materials.AIR
  local floorTop = Y1 - 200
  local L = { islands = {}, vents = {}, bells = {}, chestSpots = {}, mobs = {}, floorTop = floorTop, gaps = {}, columns = {}, ruins = {} }
  local function R(lo, hi)
    return lo + rng:random() * (hi - lo)
  end

  -- The real gaps in the floor, over the mountain's summit (which spans x 6900 and east): a fall through lands on it
  local hx0, hx1 = c.area.shaftX0 or X1 - 600, c.area.shaftX1 or X1 - 460
  local gaps = { { hx1 + 370, hx1 + 500 }, { hx0 - 860, hx0 - 780 } }
  for _, g in ipairs(gaps) do
    world:fillRect(math.floor(g[1]), floorTop - 40, math.floor(g[2]), Y1, AIR)
    L.gaps[#L.gaps + 1] = { x0 = g[1], x1 = g[2] }
  end

  -- West of the shop the sea floor is only patches of cloud, with drops between them (the wreck's patch is kept whole)
  do
    local x = hx0 - 900
    while x > X0 + 200 do
      local len = R(220, 620)
      local gw = R(110, 260)
      local g0, g1 = x - len - gw, x - len
      if g1 > WRECK_X - 330 and g0 < WRECK_X + 330 then
        x = g0 - 40 -- (never under the wreck)
      else
        for gx = math.floor(g0), math.floor(g1) do
          local t = (gx - g0) / (g1 - g0)
          local depth = 260 * math.min(1, math.sqrt(math.sin(math.pi * t)) * 1.4)
          world:fillRect(gx, floorTop - 40, gx, math.min(Y1, math.floor(floorTop + depth)), AIR)
        end
        L.gaps[#L.gaps + 1] = { x0 = g0, x1 = g1 }
        x = g0
      end
    end
  end

  -- Islands: a lens with a flattish crest (cloud heaped a little on top), tapering underneath
  local placed = L.islands
  local function carve(cx, cy, rx, ry)
    local up = ry * 0.55
    for y = math.floor(cy - up * 1.3), math.ceil(cy + ry * 2) do
      local dy = (y - cy) / (y < cy and up or ry * 1.8)
      for x = math.floor(cx - rx * 1.2), math.ceil(cx + rx * 1.2) do
        local dx = (x - cx) / rx
        local edge = (love.math.noise(x * 0.04, y * 0.04, c.noiseSeed + 5) - 0.5) * 0.4
        if y < cy then
          edge = edge - (love.math.noise(x * 0.025, c.noiseSeed + 7) - 0.45) * 0.45
        end
        if dx * dx + dy * dy + edge < 1 then
          local n = love.math.noise(x * 0.02, y * 0.02, c.noiseSeed)
          world:setRaw(x, y, (y < cy + 5 or n > 0.62) and DIRTID or ROCKID)
        end
      end
      if y % 6 == 0 then
        tick()
      end
    end
  end
  local function overlapsAny(cx, cy, rx, ry, mx, my)
    for _, o in ipairs(placed) do
      local nx, ny = (cx - o.cx) / (rx + o.rx + mx), (cy - o.cy) / (ry + o.ry + my)
      if nx * nx + ny * ny < 1 then
        return true
      end
    end
    return false
  end
  -- (a = the crest's height above the floor)
  local function addIsland(cx, a, rx, ry, extra)
    local cy = floorTop - a + ry * 0.7
    local isl = { cx = cx, cy = cy, rx = rx, ry = ry, a = a, band = bandOf(cx) }
    for k, v in pairs(extra or {}) do
      isl[k] = v
    end
    placed[#placed + 1] = isl
    carve(cx, cy, rx, ry)
    isl.top = world:findGround(math.floor(cx), math.floor(cy - ry - 20))
    return isl
  end

  -- The final slab at the Citadel's east mouth (src.cavegen carves it): where the chain has to end
  local arena = c.arena
  -- (the boss's floor is an open floating disc, no walls: the chain ends at its east rim)
  local rxA = arena.w / 2
  local slabTop, slabRight = arena.floorY, arena.cx + rxA
  local aEnd = floorTop - slabTop
  L.slab = { x0 = arena.cx, x1 = slabRight, y = slabTop }

  local function target(x)
    if x >= 7600 then
      return 100
    elseif x >= BAND_X1 then
      return 100 + (7600 - x) / 1600 * 130
    elseif x >= BAND_X2 then
      return 230 + (BAND_X1 - x) / 2700 * 170
    end
    return 400 + math.min(1, (BAND_X2 - x) / 1200) * (aEnd - 400)
  end

  -- The main chain, east to west
  local chain = {}
  local mouthX = c.shopX
  do
    local p = P[1]
    local rx, ry = R(p.rx[1], p.rx[2]), R(p.ry[1], p.ry[2])
    local kind = "plain"
    local x, a = hx0 - 100 - rx, 100
    while true do
      if math.abs(x - mouthX) < rx + 70 and a < 150 then
        a = 150 -- (clear of the shop's way up)
      end
      chain[#chain + 1] = addIsland(x, a, rx, ry, { main = #chain + 1, size = kind })
      local isl = chain[#chain]
      local np = P[bandOf(x - rx - 120)]
      local nrx, nry, nkind = sizeRoll(rng, np, R)
      local rise = math.max(-25, math.min(65, target(x) - a + R(-25, 25)))
      local gap = math.min(R(np.gap[1], np.gap[2]), 200 - math.max(0, rise) * 1.5)
      local nx = x - rx - gap - nrx
      local na = a + rise
      if nx - nrx <= slabRight + 140 then
        -- the last island, a short hop from the slab
        nrx = math.min(nrx, 40)
        nx = slabRight + 100 + nrx
        nkind = "plain"
        na = a + math.max(-30, math.min(60, aEnd - a))
        if x - rx - (nx + nrx) < 40 then
          break -- (this one is close enough already)
        end
        chain[#chain + 1] = addIsland(nx, na, nrx, math.min(nry, 14), { main = #chain + 1 })
        break
      end
      x, a, rx, ry, kind = nx, na, nrx, nry, nkind
    end
  end
  L.chain = chain

  -- Ruins (band 2): broken colonnades on the islands, bridges between them, bells hung from the lintels
  local STONE = materials.STONEBRICK
  for i, isl in ipairs(chain) do
    if isl.band == 2 and isl.rx >= 50 then
      local cols = {}
      for k = 1, rng:random(2, 3) do
        local x = math.floor(isl.cx + R(-0.7, 0.7) * isl.rx)
        local gy = world:findGround(x, math.floor(isl.cy - isl.ry - 24))
        local h = rng:random() < 0.5 and rng:random(20, 34) or rng:random(44, 70)
        cols[#cols + 1] = { x = x, top = gy - h - 1, h = h, base = gy } -- (scenery only: walked through, not solid)
        tick()
      end
      -- a lintel across the two tallest neighbours, with a bell under it
      table.sort(cols, function(p, q)
        return p.x < q.x
      end)
      for k = 1, #cols - 1 do
        local p, q = cols[k], cols[k + 1]
        if p.h >= 44 and q.h >= 44 and q.x - p.x <= 60 and q.x - p.x >= 22 then
          local y = math.min(p.top, q.top) - 1
          L.ruins[#L.ruins + 1] = { x0 = p.x - 4, x1 = q.x + 4, y = y }
          L.bells[#L.bells + 1] = { x = (p.x + q.x) / 2, y = y + 3 }
          break
        end
      end
      isl.cols = cols
      for _, col in ipairs(cols) do
        L.columns[#L.columns + 1] = col
      end
    end
  end
  for i = 1, #chain - 1 do
    local a, b = chain[i], chain[i + 1]
    local gap = (a.cx - a.rx) - (b.cx + b.rx)
    if a.band == 2 and b.band == 2 and gap > 20 and gap <= 135 and math.abs(a.a - b.a) <= 40 and rng:random() < 0.55 then
      -- a plank bridge from rim to rim, sometimes with a plank missing in the middle
      local ya = a.top + 1
      local yb = b.top + 1
      local x0, x1 = math.floor(b.cx + b.rx * 0.7), math.floor(a.cx - a.rx * 0.7)
      local broken = rng:random() < 0.4 and math.floor((x0 + x1) / 2) or nil
      for x = x0, x1 do
        local y = math.floor(yb + (ya - yb) * (x - x0) / math.max(1, x1 - x0))
        if not broken or math.abs(x - broken) > 7 then
          world:fillRect(x, y, x, y + 2, materials.HARDWOOD)
        end
      end
    end
  end

  -- Side branches: a stair of three small islands going up off the chain (the last holds a chest)
  local function overlapStair(isls, parent)
    for k, s in ipairs(isls) do
      local clash = false
      for _, o in ipairs(placed) do
        if not (k == 1 and o == parent) then
          local nx, ny = (s.cx - o.cx) / (s.rx + o.rx + 30), (s.cy - o.cy) / (s.ry + o.ry + 34)
          clash = clash or nx * nx + ny * ny < 1
        end
      end
      if clash or (s.cx - s.rx < X0 + 60) or (arena and s.cx - s.rx < arena.x1 + 260 and s.cx + s.rx > arena.x0 - 260) then
        return true
      end
    end
    return false
  end
  local branchFor = {}
  for i = 2, #chain - 2 do
    local m = chain[i]
    local want = (m.band == 1 and i % 3 == 2) or (m.band == 2 and i % 3 == 1) or (m.band == 3 and i % 3 == 0)
    if want and m.rx >= 22 then
      for _, dir in ipairs(rng:random() < 0.5 and { -1, 1 } or { 1, -1 }) do
        local function mk(cx, a, rx, ry)
          return { cx = cx, a = a, rx = rx, ry = ry, cy = floorTop - a + ry * 0.7 }
        end
        local r1, r2, r3 = 34, 30, 52
        local s1 = mk(m.cx + dir * (m.rx * 0.5 + r1 * 0.55), m.a + 62, r1, 9)
        local s2 = mk(s1.cx + dir * (r1 + r2 + 80), s1.a + 60, r2, 9)
        local s3 = mk(s2.cx + dir * (r2 + r3 + 85), s2.a + R(0, 30), r3, 13)
        if not overlapStair({ s1, s2, s3 }, m) then
          for k, s in ipairs({ s1, s2, s3 }) do
            local isl = addIsland(s.cx, s.a, s.rx, s.ry, { branch = i, tier = k })
            s.isl = isl
          end
          local top = s3.isl
          L.chestSpots[#L.chestSpots + 1] = { math.floor(top.cx), top.top }
          branchFor[i] = top
          break
        end
      end
    end
  end

  -- Vents (updraft columns): shortcuts up the chain, one loot branch at the top of a vent, and a few traps
  local function ventAt(x, baseY, h, kind)
    L.vents[#L.vents + 1] = { x = x, y = baseY, h = h, half = 20, kind = kind }
    return L.vents[#L.vents]
  end
  for i = 3, #chain - 4 do
    local m = chain[i]
    if m.band >= 2 and i % 6 == 3 and m.rx >= 24 then
      -- a shortcut: from the island's west rim up to the one three along
      local far = chain[math.min(#chain - 1, i + 3)]
      local x = math.floor(m.cx - m.rx + 16)
      local base = world:findGround(x, math.floor(m.cy - m.ry - 30))
      local h = math.max(150, math.min(330, far.a - m.a - 20))
      ventAt(x, base, h, "shortcut")
    end
  end
  -- a loot island at the top of a vent, in the Star Fields and the Ruins
  for i = 4, #chain - 3, 5 do
    local m = chain[i]
    if m.band >= 2 and not branchFor[i] then
      local dir = rng:random() < 0.5 and -1 or 1
      local x = math.floor(m.cx + dir * m.rx * 0.45)
      local isl = { cx = x + dir * 28, a = m.a + 205, rx = 46, ry = 12 }
      isl.cy = floorTop - isl.a + isl.ry * 0.7
      if not overlapStair({ isl }, m) then
        local top = addIsland(isl.cx, isl.a, isl.rx, isl.ry, { branch = i, vent = true })
        local base = world:findGround(x, math.floor(m.cy - m.ry - 30))
        ventAt(x, base, 140, "loot")
        L.chestSpots[#L.chestSpots + 1] = { math.floor(top.cx), top.top }
        branchFor[i] = top
      end
    end
  end
  -- traps: a column up from the floor in a gap, to catch a jumper and throw him high
  for i = 2, #chain - 2, 4 do
    local a, b = chain[i], chain[i + 1]
    if a.band >= 2 and rng:random() < 0.6 then
      local x = math.floor(((a.cx - a.rx) + (b.cx + b.rx)) / 2)
      local base = world:findGround(x, floorTop - 30)
      if base < Y1 - 100 then
        ventAt(x, base, math.max(a.a, b.a) + 90, "trap")
      end
    end
  end

  -- The far-east bank, across the first gap in the floor: a chest on it
  L.chestSpots[#L.chestSpots + 1] = { math.floor(gaps[1][2] + 60), world:findGround(math.floor(gaps[1][2] + 60), floorTop - 60) }

  -- The wreck: a ship half buried in the sea floor under the Ruins, only its mast showing
  do
    local x = WRECK_X
    local sy = world:findGround(x, floorTop - 60)
    local cy = sy + 82
    local rx, ry = 78, 26
    for y = cy - ry - 4, cy + ry + 4 do
      for xx = x - rx - 5, x + rx + 5 do
        local dx, dy = (xx - x) / (rx + 4), (y - cy) / (ry + 4)
        local ex, ey = (xx - x) / rx, (y - cy) / ry
        if dx * dx + dy * dy <= 1 and (y >= cy - 10 or ex * ex + ey * ey > 1) then
          world:setRaw(xx, y, materials.HARDWOOD)
        end
      end
    end
    for y = cy - ry, cy + ry do
      for xx = x - rx, x + rx do
        local ex, ey = (xx - x) / rx, (y - cy) / ry
        if ex * ex + ey * ey <= 1 and y < cy + ry - 14 then
          world:setRaw(xx, y, AIR)
        end
      end
    end
    local deck = cy + ry - 14
    world:fillRect(x - rx + 10, deck, x + rx - 10, deck + 3, materials.HARDWOOD)
    -- the mast, up through the cloud to a yard and a pennant's pole
    world:fillRect(x - 12, deck - 60, x - 10, sy - 70, materials.HARDWOOD)
    world:fillRect(x - 24, sy - 62, x + 2, sy - 61, materials.HARDWOOD)
    L.wreck = { x = x - 11, mastTop = sy - 70, deckY = deck, chest = { x + 34, deck }, lamp = { x - 11, sy - 72 }, sea = sy }
    world:repaintRect(x - rx - 8, sy - 80, x + rx + 8, cy + ry + 8)
  end

  -- Where the monsters go (src.cavegen checks each spot has room): packs of rays, moths over the drops, sentinels in
  -- the ruins, spirits wherever the islands are smallest
  local function mob(kind, x, y, pack)
    L.mobs[#L.mobs + 1] = { kind = kind, x = x, y = y, pack = pack }
  end
  local packId = 0
  local function ray(i, count)
    local m = chain[i]
    if not m then
      return
    end
    packId = packId + 1
    for k = 1, count do
      mob("cloudray", m.cx + R(-60, 60), m.top - 110 - R(0, 70), packId)
    end
  end
  local function over(i, kind, dy)
    local m = chain[i]
    if m then
      mob(kind, m.cx + R(-0.5, 0.5) * m.rx, m.top - dy)
    end
  end
  local function gapOver(i, kind)
    local a, b = chain[i], chain[i + 1]
    if a and b then
      mob(kind, ((a.cx - a.rx) + (b.cx + b.rx)) / 2, (a.top + b.top) / 2 + R(-10, 45))
    end
  end
  mob("starmoth", gaps[1][1] + 65, floorTop - 55) -- (over the first gap: the bait for a jump)
  -- (chance per island of each kind, by band: rays, moths over the next drop, sentinels, spirits)
  local W = { { 0.35, 0.35, 0.12, 0.08 }, { 0.35, 0.45, 0.55, 0.3 }, { 0.4, 0.55, 0.4, 0.65 } }
  for i, m in ipairs(chain) do
    local w = W[m.band]
    local safe = m.cx > 7050 -- (the landing's islands stay quiet)
    if not safe then
      if rng:random() < w[1] then
        ray(i, rng:random(2, 4))
      end
      if rng:random() < w[2] then
        gapOver(i, "starmoth")
        if rng:random() < 0.4 then
          gapOver(i, "starmoth")
        end
      end
      if rng:random() < w[3] then
        over(i, "sentinel", 62)
        if m.size == "bank" and rng:random() < 0.7 then
          over(i, "sentinel", 80)
        end
      end
      if rng:random() < w[4] then
        over(i, "windspirit", 44)
        if m.band == 3 and m.size ~= "stone" and rng:random() < 0.35 then
          over(i, "windspirit", 44)
        end
      end
    end
  end
  for i, top in pairs(branchFor) do
    -- a guard at each loot island
    mob(chain[i].band == 3 and "windspirit" or "sentinel", top.cx, top.top - 55)
  end
  L.bands = { x1 = BAND_X1, x2 = BAND_X2 }
  return L
end

-- The boss's floor: an open floating disc of cloudstone (flat on top, a bowl underneath), nothing round it
function skygen.buildDisc(world, arena, ROCKID, DIRTID, noiseSeed)
  local rx, depth = arena.w / 2, 130
  for y = arena.floorY, arena.floorY + depth do
    local t = (y - arena.floorY) / depth
    local half = rx * math.sqrt(math.max(0, 1 - t * t))
    for x = math.floor(arena.cx - half), math.ceil(arena.cx + half) do
      local n = love.math.noise(x * 0.03, y * 0.03, noiseSeed + 9)
      world:setRaw(x, y, (y < arena.floorY + 6 or n > 0.7) and DIRTID or ROCKID)
    end
  end
  world:repaintRect(arena.cx - rx - 8, arena.floorY - 8, arena.cx + rx + 8, arena.floorY + depth + 8)
end

return skygen
