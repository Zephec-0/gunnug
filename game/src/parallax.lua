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

local STYLES = { mineStyle, hollowsStyle, ventsStyle, warrensStyle, drownedStyle }

-- Draws area `index`'s far scenery over the view (world pixels vx0..vx1, vy0..vy1).
-- colors: the area's three pillar colours (for the mine's far rock).
function parallax.draw(index, camX, camY, vx0, vy0, vx1, vy1, colors)
  local style = STYLES[index] or STYLES[#STYLES]
  style(camX, camY, vx0, vy0, vx1, vy1, colors, love.timer.getTime())
end

return parallax
