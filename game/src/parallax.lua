-- The far backgrounds of the caves (design doc §2a): each area has its own two
-- layers of scenery that slide past more slowly than the near terrain, so the
-- open caverns have depth and every area has a face of its own:
--   1 the old mine      far rock, and timber frames of old shoring (some fallen),
--                       hanging lanterns glimmering in the distance
--   2 the Hollows       giant fungus with glowing caps, hanging roots, drifting spores
--   3 the Vents         crystal spires, vent chimneys breathing pale steam
--   4 the Warrens       basalt columns, lava falls and rising embers
--   5 the Drowned Halls a drowned colonnade of arches, hanging chains, wavering light
-- Drawn in world coordinates before the terrain; the terrain covers whatever
-- lies behind rock.
local parallax = {}

local function hash(a, b)
  local n = math.sin(a * 127.1 + b * 311.7) * 43758.5453
  return n - math.floor(n)
end

local function rect(c, a, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), math.max(1, math.floor(w)), math.max(1, math.floor(h)))
end

-- Calls fn(i, j, x, y) for every cell of a layer that parallaxes at p, covering
-- the view; (x, y) is the cell's top-left in world pixels
local function cells(p, cw, ch, camX, camY, vx0, vy0, vx1, vy1, fn)
  local ox, oy = camX * (1 - p), camY * (1 - p)
  for j = math.floor((vy0 - oy) / ch) - 1, math.floor((vy1 - oy) / ch) + 1 do
    for i = math.floor((vx0 - ox) / cw) - 1, math.floor((vx1 - ox) / cw) + 1 do
      fn(i, j, math.floor(i * cw + ox), math.floor(j * ch + oy))
    end
  end
end

-- Style 1: the old mine ------------------------------------------------------

local function mineStyle(camX, camY, vx0, vy0, vx1, vy1, colors, t)
  -- Far rock pillars
  local p, spacing = 0.55, 74
  local off = camX * (1 - p)
  for i = math.floor((vx0 - off) / spacing) - 1, math.floor((vx1 - off) / spacing) + 1 do
    local w = 10 + math.floor(hash(i, 1) * 14)
    local x = math.floor(i * spacing + off + hash(i, 8) * spacing * 0.6)
    rect(colors[1], 0.5, x, vy0, w, vy1 - vy0)
    rect(colors[2], 0.4, x, vy0, 1, vy1 - vy0)
  end
  -- Timber frames of old shoring
  cells(0.78, 104, 168, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j) < 0.25 then
      return
    end
    local fx = x + math.floor(hash(i + 3, j) * 60)
    local fy = y + math.floor(hash(i, j + 5) * 60)
    local gap = 22 + math.floor(hash(i, j + 9) * 10)
    local h = 70 + math.floor(hash(i + 7, j) * 40)
    local wood, lit = { 0.24, 0.16, 0.10 }, { 0.38, 0.26, 0.14 }
    local broken = hash(i + 11, j + 2) < 0.35
    rect(wood, 0.8, fx, fy, 3, h)
    rect(lit, 0.6, fx, fy, 1, h)
    if broken then
      rect(wood, 0.8, fx + gap, fy + h * 0.45, 3, h * 0.55) -- a snapped post
      rect(wood, 0.75, fx - 2, fy, gap * 0.7, 3)
      for k = 0, 8 do
        rect(wood, 0.75, fx + gap * 0.7 + k, fy + k * 2, 2, 3) -- the beam, hanging
      end
    else
      rect(wood, 0.8, fx + gap, fy, 3, h)
      rect(lit, 0.6, fx + gap, fy, 1, h)
      rect(wood, 0.8, fx - 4, fy, gap + 11, 3)
      rect(lit, 0.6, fx - 4, fy, gap + 11, 1)
      for k = 0, 6 do
        rect(wood, 0.7, fx + 3 + k, fy + 3 + k, 1, 1)
        rect(wood, 0.7, fx + gap - 1 - k, fy + 3 + k, 1, 1)
      end
      -- A lantern hung from the beam, a warm spark in the dark
      if hash(i, j + 17) < 0.5 then
        local flick = 0.55 + 0.25 * math.sin(t * 7 + i * 3 + j)
        rect({ 0.4, 0.3, 0.2 }, 0.6, fx + gap / 2, fy + 3, 1, 5)
        rect({ 1, 0.7, 0.3 }, flick, fx + gap / 2 - 1, fy + 8, 3, 4)
        rect({ 1, 0.7, 0.3 }, flick * 0.25, fx + gap / 2 - 4, fy + 5, 9, 10)
      end
    end
  end)
end

-- Style 2: the Sunken Hollows --------------------------------------------------

local function hollowsStyle(camX, camY, vx0, vy0, vx1, vy1, colors, t)
  -- Giant fungi: a stalk and a broad glowing cap
  cells(0.52, 120, 200, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j) < 0.2 then
      return
    end
    local sx = x + math.floor(hash(i + 1, j) * 110)
    local base = y + 120 + math.floor(hash(i, j + 4) * 100)
    local h = 70 + math.floor(hash(i + 6, j) * 90)
    local w = 5 + math.floor(hash(i, j + 8) * 6)
    local cap = 22 + math.floor(hash(i + 9, j) * 24)
    rect({ 0.07, 0.14, 0.16 }, 0.8, sx, base - h, w, h)
    -- The cap: stacked rows narrowing upward, glowing at its rim
    local rows = math.floor(cap / 3)
    for r = 0, rows do
      local rw = cap * math.sqrt(math.max(0, 1 - ((rows - r) / rows) ^ 2))
      rect({ 0.08, 0.24, 0.24 }, 0.8, sx + w / 2 - rw / 2, base - h - rows + r, rw, 1)
    end
    local pulse = 0.55 + 0.2 * math.sin(t * 1.2 + i * 2 + j)
    rect({ 0.3, 1, 0.55 }, pulse, sx + w / 2 - cap / 2, base - h, cap, 1)
    rect({ 0.3, 1, 0.55 }, pulse * 0.4, sx + w / 2 - cap / 2 - 2, base - h + 1, cap + 4, 2)
  end)
  -- Roots hanging from the ceiling, swaying, and spores drifting up
  cells(0.78, 46, 260, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 20) < 0.3 then
      return
    end
    local len = 60 + math.floor(hash(i, j + 3) * 160)
    local sway = math.sin(t * 0.8 + i * 1.7) * 2
    for k = 0, len, 2 do
      local bend = sway * (k / len) ^ 2
      rect({ 0.14, 0.30, 0.20 }, 0.6, x + 10 + bend, y + k, 1, 2)
    end
    local sp = (t * 6 + hash(i, j) * 100) % 120
    rect({ 0.5, 1, 0.65 }, 0.35, x + 6 + math.sin(sp * 0.2 + i) * 4, y + 200 - sp, 1, 1)
  end)
end

-- Style 3: the Sulfur Vents ---------------------------------------------------------

local function ventsStyle(camX, camY, vx0, vy0, vx1, vy1, colors, t)
  -- Crystal spires rising from far below
  cells(0.5, 84, 220, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j) < 0.15 then
      return
    end
    local sx = x + math.floor(hash(i + 2, j) * 60)
    local base = y + 200
    local h = 60 + math.floor(hash(i, j + 5) * 110)
    local w = 10 + math.floor(hash(i + 4, j) * 14)
    for r = 0, h, 2 do
      local rw = w * (1 - r / h)
      rect({ 0.24, 0.24, 0.07 }, 0.75, sx + (w - rw) / 2, base - r, rw, 2)
    end
    rect({ 0.60, 0.58, 0.22 }, 0.6, sx + w * 0.5, base - h, 1, h) -- the lit facet
    rect({ 0.9, 0.85, 0.3 }, 0.3 + 0.1 * math.sin(t * 2 + i), sx + w / 2, base - h - 1, 1, 2)
  end)
  -- Vent chimneys, each breathing a slow plume of pale steam
  cells(0.78, 130, 250, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 30) < 0.3 then
      return
    end
    local cx = x + 30 + math.floor(hash(i, j) * 60)
    local base = y + 230
    local h = 30 + math.floor(hash(i, j + 2) * 50)
    rect({ 0.15, 0.15, 0.05 }, 0.55, cx - 5, base - h, 10, h)
    rect({ 0.28, 0.27, 0.09 }, 0.5, cx - 6, base - h, 12, 3)
    for k = 0, 7 do
      local age = ((t * 0.35 + k / 8 + hash(i, j) * 5) % 1)
      local px = cx + math.sin(age * 5 + k) * (3 + age * 10)
      local py = base - h - age * 110
      rect({ 0.80, 0.80, 0.50 }, 0.22 * (1 - age), px - 4 - age * 6, py, 9 + age * 14, 5)
    end
  end)
end

-- Style 4: the Cinder Warrens -----------------------------------------------------------

local function warrensStyle(camX, camY, vx0, vy0, vx1, vy1, colors, t)
  -- Basalt columns, banded where they were cast
  local p, spacing = 0.5, 62
  local off = camX * (1 - p)
  for i = math.floor((vx0 - off) / spacing) - 1, math.floor((vx1 - off) / spacing) + 1 do
    local w = 12 + math.floor(hash(i, 3) * 14)
    local x = math.floor(i * spacing + off + hash(i, 9) * spacing * 0.5)
    rect({ 0.07, 0.04, 0.04 }, 0.6, x, vy0, w, vy1 - vy0)
    rect({ 0.40, 0.18, 0.11 }, 0.55, x, vy0, 1, vy1 - vy0)
    rect({ 0.12, 0.06, 0.05 }, 0.6, x + w - 2, vy0, 2, vy1 - vy0)
    for y = math.floor(vy0 / 14) * 14, vy1, 14 do
      rect({ 0.04, 0.02, 0.02 }, 0.55, x + 1, y + math.floor(hash(i, y) * 8), w - 3, 1)
    end
  end
  -- Lava falls: glowing streaks pouring down the far walls, and embers rising
  cells(0.76, 120, 300, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 40) < 0.4 then
      return
    end
    local fx = x + 20 + math.floor(hash(i, j) * 70)
    local len = 100 + math.floor(hash(i, j + 6) * 160)
    local w = 3 + math.floor(hash(i + 3, j) * 3)
    local glow = 0.38 + 0.12 * math.sin(t * 1.5 + i * 3 + j)
    rect({ 1, 0.3, 0.08 }, glow * 0.5, fx - 3, y, w + 6, len)
    rect({ 1, 0.5, 0.12 }, glow, fx, y, w, len)
    rect({ 1, 0.85, 0.4 }, glow * 0.7, fx + 1, y, 1, len)
    for k = 0, 8 do
      local age = ((t * 0.25 + k / 9 + hash(i, j) * 7) % 1)
      rect({ 1, 0.55, 0.15 }, 0.7 * (1 - age), fx + w / 2 + math.sin(age * 9 + k * 2) * 6, y + len - age * 150, 1, 1)
    end
  end)
end

-- Style 5: the Drowned Halls ------------------------------------------------------------

local function drownedStyle(camX, camY, vx0, vy0, vx1, vy1, colors, t)
  -- A drowned colonnade: tall columns with arches between them, some broken
  local p, spacing = 0.52, 78
  local off = camX * (1 - p)
  for i = math.floor((vx0 - off) / spacing) - 1, math.floor((vx1 - off) / spacing) + 1 do
    local x = math.floor(i * spacing + off)
    local broken = hash(i, 2) < 0.25
    local top = broken and (vy0 + 90 + math.floor(hash(i, 5) * 80)) or vy0
    rect({ 0.05, 0.11, 0.14 }, 0.55, x, top, 14, vy1 - top)
    rect({ 0.16, 0.30, 0.36 }, 0.4, x, top, 2, vy1 - top)
    rect({ 0.03, 0.07, 0.10 }, 0.5, x + 12, top, 2, vy1 - top)
    for y = math.floor(vy0 / 34) * 34, vy1, 34 do
      rect({ 0.12, 0.24, 0.30 }, 0.5, x - 2, y, 18, 3) -- capitals and bands
    end
    if not broken and hash(i + 1, 2) >= 0.25 then
      -- The arch to the next column
      local span = spacing - 14
      for k = 0, span do
        local ah = math.sqrt(math.max(0, 1 - ((k - span / 2) / (span / 2)) ^ 2)) * 26
        rect({ 0.05, 0.11, 0.14 }, 0.45, x + 14 + k, vy0 + 60 - ah, 1, 5)
      end
    end
  end
  -- Chains hanging and swaying, and slow wavering light from the surface
  cells(0.8, 60, 280, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 50) < 0.6 then
      return
    end
    local len = 90 + math.floor(hash(i, j) * 150)
    local sway = math.sin(t * 0.7 + i * 2.1) * 3
    for k = 0, len, 3 do
      local bend = sway * (k / len)
      rect({ 0.22, 0.34, 0.38 }, 0.4, x + 20 + bend, y + k, 1, 2)
    end
  end)
  for k = 0, 4 do
    local x = vx0 + ((k * 137 + camX * 0.1) % (vx1 - vx0 + 60)) - 30
    local a = 0.035 + 0.02 * math.sin(t * 0.6 + k * 2)
    rect({ 0.6, 0.9, 1 }, a, x, vy0, 18 + math.sin(t * 0.4 + k) * 5, vy1 - vy0)
  end
end

-- Style 6: the Quarry ------------------------------------------------------------------
-- Dark, cut stone: stepped terraces of far rock, jagged outcrops and spikes of rock
-- hanging overhead, and veins of ore that shimmer (gold and a cold blue)

local function quarryStyle(camX, camY, vx0, vy0, vx1, vy1, colors, t)
  -- Terraces: wide slabs of far rock stepped up and down, with lit edges, in
  -- three ranks at different depths (the farthest palest and slowest), each
  -- rank a repeating row of ridges that fades out below its stepped top, so
  -- the ranks behind show through instead of one flat wall
  local RANKS = {
    { p = 0.28, cw = 190, rh = 230, fill = { 0.085, 0.07, 0.075 }, edge = { 0.17, 0.14, 0.14 }, a = 0.55, seed = 0 },
    { p = 0.4, cw = 150, rh = 200, fill = { 0.07, 0.06, 0.065 }, edge = { 0.20, 0.17, 0.16 }, a = 0.7, seed = 40 },
    { p = 0.52, cw = 120, rh = 260, fill = { 0.055, 0.045, 0.05 }, edge = { 0.24, 0.20, 0.18 }, a = 0.8, seed = 80 },
  }
  for _, r in ipairs(RANKS) do
    local ox, oy = camX * (1 - r.p), camY * (1 - r.p)
    for j = math.floor((vy0 - oy) / r.rh) - 1, math.floor((vy1 - oy) / r.rh) + 1 do
      local rowY = math.floor(j * r.rh + oy)
      for i = math.floor((vx0 - ox) / r.cw) - 1, math.floor((vx1 - ox) / r.cw) + 1 do
        local x = math.floor(i * r.cw + ox)
        local top = rowY + math.floor(hash(i, j + r.seed) * 90)
        local depth = 70 + math.floor(hash(i + 3, j + r.seed) * 60)
        rect(r.fill, r.a, x, top, r.cw + 1, depth)
        -- (fading out underneath, so the rank behind shows below)
        for k = 1, 4 do
          rect(r.fill, r.a * (1 - k / 5), x, top + depth + (k - 1) * 8, r.cw + 1, 8)
        end
        rect(r.edge, r.a * 0.85, x, top, r.cw + 1, 2)
        -- (the step down to the next slab casts a dark notch)
        rect({ 0.02, 0.02, 0.025 }, r.a * 0.5, x + r.cw - 2, top, 2, depth * 0.6)
        for k = 0, 2 do
          local ly = top + 16 + k * 22 + math.floor(hash(i, j + 10 + k + r.seed) * 10)
          rect({ 0.035, 0.03, 0.035 }, r.a * 0.6, x + math.floor(hash(i, 20 + k + j) * 40), ly, 30 + math.floor(hash(i, 30 + k + j) * 70), 1)
        end
      end
    end
  end
  -- Jagged outcrops of rock, leaning
  cells(0.6, 110, 260, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 60) < 0.35 then
      return
    end
    local bx = x + 10 + math.floor(hash(i, j) * 70)
    local base = y + 250
    local h = 40 + math.floor(hash(i, j + 2) * 90)
    local w = 24 + math.floor(hash(i + 5, j) * 40)
    local lean = (hash(i, j + 7) - 0.5) * 14
    for r = 0, h, 3 do
      local k = r / h
      local rw = w * (1 - k * 0.8) + (hash(i + r, j) - 0.5) * 3
      local shift = lean * k
      rect({ 0.11, 0.095, 0.10 }, 0.85, bx + (w - rw) / 2 + shift, base - r, rw, 3)
      rect({ 0.26, 0.22, 0.19 }, 0.5, bx + (w - rw) / 2 + shift, base - r, 1, 3)
    end
  end)
  -- Rock spikes hanging from above
  cells(0.7, 70, 300, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 80) < 0.5 then
      return
    end
    local sx = x + 20 + math.floor(hash(i, j) * 30)
    local len = 40 + math.floor(hash(i, j + 3) * 100)
    local w = 8 + math.floor(hash(i + 2, j) * 12)
    for r = 0, len, 3 do
      local rw = w * (1 - r / len)
      rect({ 0.09, 0.08, 0.09 }, 0.85, sx + (w - rw) / 2, y + r, rw, 3)
    end
  end)
  -- Ore: clusters of flecks in the far walls that glint in turn
  cells(0.62, 86, 130, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 90) < 0.5 then
      return
    end
    local blue = hash(i, j + 92) < 0.35
    local c = blue and { 0.6, 0.85, 1 } or { 1, 0.8, 0.3 }
    local ox, oy = x + math.floor(hash(i, j) * 70), y + math.floor(hash(i, j + 1) * 100)
    for k = 0, 5 do
      local fx = ox + math.floor((hash(i + k, j) - 0.5) * 18)
      local fy = oy + math.floor((hash(i, j + k) - 0.5) * 12)
      local tw = math.sin(t * 2.2 + hash(i + k, j + k) * 20)
      local a = 0.25 + 0.55 * math.max(0, tw)
      rect({ c[1] * 0.5, c[2] * 0.5, c[3] * 0.5 }, 0.6, fx, fy, 2, 2)
      rect(c, a, fx, fy, 1, 1)
      if tw > 0.85 then
        rect({ 1, 1, 1 }, 0.8, fx - 1, fy, 3, 1)
        rect({ 1, 1, 1 }, 0.8, fx, fy - 1, 1, 3)
      end
    end
  end)
end

-- Style 7: the ocean (the Flooded Caverns and the Deep) ----------------------------------
-- Deep blue water: broad ribbons of light that roll slowly with a fractal swell
-- (octaves of waves, each warped by the one above it), drifting shafts from
-- the surface, tall seaweed swaying up from the dark below, and columns of
-- bubbles rising, wobbling, toward the light

-- A smooth, slowly moving fractal swell at x (four octaves, domain-warped)
local function swell(x, t, seed)
  local w = math.sin(x * 0.0045 + t * 0.11 + seed) * 1.6
  local h, amp, f = 0, 10, 0.006
  for o = 0, 3 do
    h = h + math.sin((x + w * 40) * f + t * (0.16 + o * 0.07) + seed * (o + 1)) * amp
    amp, f = amp * 0.5, f * 2.03
    w = w + h * 0.03
  end
  return h
end

local function oceanStyle(camX, camY, vx0, vy0, vx1, vy1, colors, t)
  -- The swell: wide soft bands of lighter water riding the fractal waves
  local p = 0.3
  local oy = camY * (1 - p)
  for band = 0, 6 do
    local base = vy0 + ((band * 71 - oy * 0.4) % (vy1 - vy0 + 140)) - 70
    local tint = band % 2 == 0 and { 0.20, 0.52, 0.62 } or { 0.28, 0.38, 0.70 }
    for x = math.floor(vx0 / 3) * 3, vx1, 3 do
      local wx = x + camX * (1 - p)
      local w = swell(wx, t, band * 1.7)
      local a = 0.035 + 0.025 * (0.5 + 0.5 * math.sin(wx * 0.004 + t * 0.12 + band * 2))
      rect(tint, a * 0.5, x, base + w - 6, 3, 20)
      rect(tint, a, x, base + w, 3, 8)
      rect({ 0.7, 0.95, 1 }, a * 0.9, x, base + w, 3, 1)
    end
  end
  -- Light falling from far above
  for k = 0, 5 do
    local x = vx0 + ((k * 151 + camX * 0.15 + math.sin(t * 0.15 + k) * 24) % (vx1 - vx0 + 80)) - 40
    local a = 0.035 + 0.02 * math.sin(t * 0.4 + k * 1.9)
    rect({ 0.6, 0.9, 1 }, a, x, vy0, 22 + math.sin(t * 0.3 + k) * 6, vy1 - vy0)
  end
  -- Seaweed: tall strands rising out of the dark, swaying with the swell
  cells(0.45, 90, 300, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    for s = 0, 2 do
      if hash(i + s, j + 9) > 0.3 then
        local kx = x + 10 + math.floor(hash(i + s, j + 4) * 70)
        local root = y + 300
        local len = 80 + math.floor(hash(i, j + s) * 170)
        local col = s == 1 and { 0.10, 0.30, 0.26 } or { 0.12, 0.34, 0.24 }
        for q = 0, len, 2 do
          local u = q / len
          local sway = (math.sin(t * 0.7 + q * 0.035 + kx * 0.05) * 7 + math.sin(t * 0.37 + q * 0.011 + s) * 4) * u
          rect(col, 0.72 - u * 0.2, kx + sway, root - q, 2, 2)
          if q % 14 == 0 and q > 10 then
            local side = (q / 14) % 2 == 0 and 1 or -1
            rect(col, 0.6, kx + sway + side * 2, root - q - 1, 3 * side, 1) -- a frond
          end
        end
      end
    end
  end)
  -- Bubbles: columns of them rising and wobbling, each bubble on its own loop
  cells(0.6, 70, 240, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 31) < 0.45 then
      return
    end
    local bx = x + math.floor(hash(i, j + 32) * 60)
    for b = 0, 4 do
      local speed = 14 + hash(i + b, j) * 16
      local phase = (t * speed + hash(i, j + b) * 240) % 240
      local by = y + 240 - phase
      local wob = math.sin(t * 2.2 + b * 1.7 + i) * 2.5
      local size = 1 + math.floor(hash(i + b, j + 3) * 2.5)
      local a = 0.45 * math.min(1, phase / 40) * math.min(1, (240 - phase) / 40)
      rect({ 0.75, 0.95, 1 }, a, bx + wob, by, size, size)
      if size > 1 then
        rect({ 1, 1, 1 }, a * 0.9, bx + wob, by, 1, 1) -- the glint
      end
    end
  end)
end

-- Style 9: inside the Needle -------------------------------------------------------------------
-- The inside of a mountain: layers of far rock, hanging stalactites, and here and
-- there a hole through the rock that peeps out into the open sky (dusk near the
-- ground, going to indigo and then to starry black the higher the mountain climbs),
-- with a faint shaft of its light falling into the cave. The holes sit on a far
-- layer, so they slide past slowly; parallax.skyHoles gives their places, for the
-- light each one throws (src.scenes.catacombs addLights).

local HOLE_P, HOLE_CW, HOLE_CH = 0.34, 180, 200

-- The hole of cell (i, j) whose corner is at (x, y), or nil: centre, half-size
local function holeAt(i, j, x, y)
  if hash(i, j + 140) < 0.4 then
    return nil
  end
  local rw = 9 + math.floor(hash(i, j + 141) * 14)
  local rh = 13 + math.floor(hash(i, j + 142) * 20)
  -- Staggered: alternate rows keep to the left, then the right half of their cells
  local half = HOLE_CW / 2
  local hx = x + 24 + math.floor(hash(i, j + 143) * (half - 48)) + (j % 2 == 0 and 0 or half)
  return hx, y + 34 + math.floor(hash(i, j + 144) * (HOLE_CH - 68)), rw, rh
end

-- The sky seen through a hole at world height wy: colour of the sky there
-- (always a bright evening: gold at the ground, rose higher up)
local SKY_STOPS = {
  { 0.00, { 1.00, 0.82, 0.46 } },
  { 0.50, { 1.00, 0.76, 0.46 } },
  { 1.00, { 1.00, 0.68, 0.52 } },
}
local function skyAt(wy)
  local t = math.max(0, math.min(1, (500 - wy) / 7000))
  for k = 1, #SKY_STOPS - 1 do
    local a, b = SKY_STOPS[k], SKY_STOPS[k + 1]
    if t <= b[1] then
      local u = (t - a[1]) / (b[1] - a[1])
      return a[2][1] + (b[2][1] - a[2][1]) * u, a[2][2] + (b[2][2] - a[2][2]) * u, a[2][3] + (b[2][3] - a[2][3]) * u
    end
  end
  local c = SKY_STOPS[#SKY_STOPS][2]
  return c[1], c[2], c[3]
end

-- A hole's picture, made once: its dark rim and sky ("rim"), and the sky alone, drawn
-- bright over the lit scene ("glow"). Cached by cell: drawing it row by row every frame
-- was most of the Needle's cost.
local holeSprites = {}
local function holeSprite(i, j, hx, hy, rw, rh)
  local key = i * 4099 + j
  local sp = holeSprites[key]
  if sp then
    return sp
  end
  local W, H = 2 * (rw + 10), 2 * (rh + 4)
  local rim, glow = love.image.newImageData(W, H), love.image.newImageData(W, H)
  local xc = W / 2
  for dy = -rh - 2, rh + 2 do
    local n = dy / (rh + 2)
    local base = math.sqrt(math.max(0, 1 - n * n))
    local jag = (hash(i + dy, j + 150) - 0.5) * 2 + math.sin(dy * 0.3 + i) * 1.2
    local half = (rw + 2) * base + jag * base
    local row = dy + rh + 2
    if half > 0 then
      for x = math.floor(xc - half - 2), math.ceil(xc + half + 2) - 1 do
        rim:setPixel(x, row, 0.04, 0.03, 0.045, 0.9) -- the rock's rim
      end
      if half > 2 then
        -- (rosy up top, warming to gold toward the bottom of the hole)
        local r, g, b = skyAt(hy + dy)
        local k = (n + 1) / 2
        local cr, cg, cb = r * (0.88 + 0.12 * k), g * (0.82 + 0.18 * k), b * (1.0 - 0.2 * k)
        for x = math.floor(xc - half + 1), math.ceil(xc + half - 1) - 1 do
          rim:setPixel(x, row, cr, cg, cb, 1)
          glow:setPixel(x, row, cr, cg, cb, 0.95)
        end
      end
    end
  end
  local a, b = love.graphics.newImage(rim), love.graphics.newImage(glow)
  a:setFilter("nearest", "nearest")
  b:setFilter("nearest", "nearest")
  sp = { rim = a, glow = b, ox = math.floor(-xc), oy = -rh - 2 }
  holeSprites[key] = sp
  return sp
end

-- Calls fn(x, y, r, g, b, radius) for every sky hole in the view (its place in the world
-- as drawn, the colour of the light it throws and how far)
function parallax.skyHoles(camX, camY, vx0, vy0, vx1, vy1, fn)
  cells(HOLE_P, HOLE_CW, HOLE_CH, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    local hx, hy, rw, rh = holeAt(i, j, x, y)
    if hx then
      local r, g, b = skyAt(hy)
      -- (the sky's own colour, lifted so a high, dark sky still throws a cool moonlight)
      fn(hx, hy, 0.20 + r * 0.8, 0.26 + g * 0.75, 0.40 + b * 0.6, 28 + rw * 1.6)
    end
  end)
end

-- The holes' sky drawn bright over the lit scene, but only where the air shows them
-- (the terrain mask hides it behind rock), so it never spills onto the ground
local glowShader
function parallax.drawSkyGlow(vx0, vy0, vx1, vy1, mask, profile)
  if not mask then
    return
  end
  if glowShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
uniform Image mask;
uniform vec2 canvasSize;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  float solid = Texel(mask, sc / canvasSize).r;
  vec4 t = Texel(tex, uv) * color;
  return vec4(t.rgb, t.a * (1.0 - smoothstep(0.2, 0.6, solid)));
}
]])
    glowShader = ok and sh or false
  end
  if not glowShader then
    return
  end
  local camX, camY = vx0, vy0
  love.graphics.setShader(glowShader)
  glowShader:send("mask", mask)
  glowShader:send("canvasSize", { mask:getDimensions() })
  cells(HOLE_P, HOLE_CW, HOLE_CH, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    local hx, hy, rw, rh = holeAt(i, j, x, y)
    if not hx then
      return
    end
    local xa, xb = profile(hy)
    if not (xa and hx > xa + 40 and hx < xb - 40) then
      return
    end
    local sp = holeSprite(i, j, hx, hy, rw, rh)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sp.glow, math.floor(hx) + sp.ox, math.floor(hy) + sp.oy)
  end)
  love.graphics.setShader()
end

local stalSprites = {} -- (each hanging rock drawn once into a picture)
local function needleStyle(camX, camY, vx0, vy0, vx1, vy1, colors, t)
  -- Far rock: wide, dim pillars and slabs
  local p, spacing = 0.22, 120
  local off = camX * (1 - p)
  for i = math.floor((vx0 - off) / spacing) - 1, math.floor((vx1 - off) / spacing) + 1 do
    local w = 30 + math.floor(hash(i, 51) * 46)
    local x = math.floor(i * spacing + off + hash(i, 58) * spacing * 0.5)
    rect(colors[1], 0.55, x, vy0, w, vy1 - vy0)
    rect(colors[3], 0.25, x, vy0, 2, vy1 - vy0)
  end
  -- Holes to the sky, on a far layer
  cells(HOLE_P, HOLE_CW, HOLE_CH, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    local hx, hy, rw, rh = holeAt(i, j, x, y)
    if not hx then
      return
    end
    local sp = holeSprite(i, j, hx, hy, rw, rh)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sp.rim, math.floor(hx) + sp.ox, math.floor(hy) + sp.oy)
  end)
  -- Stalactites hanging from the near rock, drawn over the sky holes
  cells(0.55, 96, 380, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 170) < 0.35 then
      return
    end
    local sx = x + 10 + math.floor(hash(i, j + 171) * 60)
    local key = i * 4099 + j
    local st = stalSprites[key]
    if not st then
      local len = 50 + math.floor(hash(i, j + 172) * 150)
      local w = 10 + math.floor(hash(i, j + 173) * 16)
      local data = love.image.newImageData(w, len + 3)
      for r = 0, len, 3 do
        local rw = w * (1 - r / len) ^ 0.8
        local x0 = math.floor((w - rw) / 2)
        for yy = r, math.min(r + 2, len + 2) do
          for xx = x0, x0 + math.max(1, math.floor(rw)) - 1 do
            if xx < w then
              data:setPixel(xx, yy, colors[1][1], colors[1][2], colors[1][3], 0.9)
            end
          end
          data:setPixel(x0, yy, colors[2][1], colors[2][2], colors[2][3], 0.35)
        end
      end
      local img = love.graphics.newImage(data)
      img:setFilter("nearest", "nearest")
      st = { img = img }
      stalSprites[key] = st
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(st.img, sx, math.floor(y))
  end)
  -- ...and the old timber frames of the mine, further in
  cells(0.78, 130, 210, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 180) < 0.62 then
      return
    end
    local fx = x + math.floor(hash(i, j + 181) * 60)
    local fy = y + math.floor(hash(i, j + 182) * 60)
    local gap = 24 + math.floor(hash(i, j + 183) * 10)
    local h = 70 + math.floor(hash(i, j + 184) * 40)
    rect({ 0.17, 0.11, 0.08 }, 0.7, fx, fy, 3, h)
    rect({ 0.17, 0.11, 0.08 }, 0.7, fx + gap, fy, 3, h)
    rect({ 0.17, 0.11, 0.08 }, 0.7, fx - 4, fy, gap + 11, 3)
  end)
end

local STYLES = { mineStyle, hollowsStyle, ventsStyle, warrensStyle, drownedStyle, quarryStyle, oceanStyle, oceanStyle, needleStyle }

-- Draws area `index`'s far scenery over the view (world pixels vx0..vx1, vy0..vy1).
-- colors: the area's three pillar colours (for the mine's far rock).
function parallax.draw(index, camX, camY, vx0, vy0, vx1, vy1, colors)
  local style = STYLES[index] or STYLES[#STYLES]
  style(camX, camY, vx0, vy0, vx1, vy1, colors, love.timer.getTime())
end

return parallax
