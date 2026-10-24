-- Far backgrounds made for the boss arenas. Each is drawn only inside its arena's box
-- (src.depthblend sets bossbg.box = { x0, top, x1, floorY } and clips to it), anchored to the
-- arena's own ceiling and floor: nothing hangs in mid-air, nothing stands on nothing.
--   deep        the Big Fish's cavern: black water, rock walls and spires in layers, drifting
--               snow. While the fish are still being eaten, something far larger waits in the
--               middle of it: a lure of blue light and little lights for its eyes, which go
--               out once the eel is under half its health (aquatic.lua)
--   quarryhall  the Colossus's hall: three ranks of stepped terraces rising from a paved
--               ground plane, veins of ore, orange crystals standing on the ledges or hanging
--               from the ceiling
--   acid        the Sulfur Queen's arena: ruined pillars from ceiling to floor, mould mounds
--               and pustules on the ground and on the pillars, a thin glowing pool
-- What glows is drawn again, bright, by bossbg.drawGlow in the scene's emissive pass, behind
-- the terrain mask (a real light would spill onto the ground in front of the far layers).
local config = require("src.config")

local bossbg = {}
local TWO_1A, TWO_1B = { 0.55, 0.85, 1 }, { 1, 0.78, 0.28 }
-- (constant colours, made once: built inline they were new tables every frame)
local BCOL_1 = { 0.01, 0.03, 0.05 }
local BCOL_2 = { 0.3, 0.7, 0.9 }
local BCOL_3 = { 0.45, 0.9, 1 }
local BCOL_4 = { 0.9, 1, 1 }
local BCOL_5 = { 0.4, 0.9, 1 }
local BCOL_6 = { 1, 1, 1 }
local BCOL_7 = { 0.07, 0.13, 0.2 }
local BCOL_8 = { 0.6, 0.8, 0.9 }
local BCOL_9 = { 1, 0.95, 0.7 }
local BCOL_10 = { 1, 0.9, 0.6 }
local BCOL_11 = { 0.045, 0.034, 0.032 }
local BCOL_12 = { 0.2, 0.14, 0.1 }
local BCOL_13 = { 0.12, 0.085, 0.065 }
local BCOL_14 = { 0.26, 0.18, 0.12 }
local BCOL_15 = { 1, 1, 0.8 }
local BCOL_16 = { 0.75, 0.95, 0.2 }
local BCOL_17 = { 0.12, 0.14, 0.06 }
local BCOL_18 = { 0.30, 0.36, 0.14 }
local BCOL_19 = { 0.025, 0.03, 0.012 }
local BCOL_20 = { 0.09, 0.1, 0.045 }
local BCOL_21 = { 0.02, 0.025, 0.01 }
local BCOL_22 = { 0.04, 0.05, 0.02 }
local BCOL_23 = { 0.2, 0.28, 0.08 }
local BCOL_24 = { 0.7, 0.92, 0.2 }
local BCOL_25 = { 0.75, 0.96, 0.25 }
local BCOL_26 = { 0.42, 0.62, 0.08 }
local BCOL_27 = { 0.6, 0.85, 0.16 }
local BCOL_28 = { 0.8, 0.95, 0.3 }

local function hash(a, b)
  local n = math.sin(a * 127.1 + b * 311.7) * 43758.5453
  return n - math.floor(n)
end

-- (rectangles go into the batch, src.quads; anything else drawn flushes it first so the order holds)
local quads = require("src.quads")
local qrect, flush = quads.rect, quads.flush
local floor, max = math.floor, math.max
local function rect(c, a, x, y, w, h)
  qrect(c[1], c[2], c[3], a, floor(x), floor(y), max(1, floor(w)), max(1, floor(h)))
end

local function disc(c, a, x, y, r)
  flush()
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.circle("fill", math.floor(x), math.floor(y), r, 14)
end

local function poly(c, a, ...)
  flush()
  love.graphics.setColor(c[1], c[2], c[3], a)
  local pts = { ... }
  for k = 1, #pts do
    pts[k] = math.floor(pts[k] + 0.5)
  end
  love.graphics.polygon("fill", pts)
end

-- Calls fn(i, j, x, y) for every cell of a layer that parallaxes at p, covering the view
local function cells(p, cw, ch, camX, camY, vx0, vy0, vx1, vy1, fn)
  local ox, oy = camX * (1 - p), camY * (1 - p)
  for j = math.floor((vy0 - oy) / ch) - 1, math.floor((vy1 - oy) / ch) + 1 do
    for i = math.floor((vx0 - ox) / cw) - 1, math.floor((vx1 - ox) / cw) + 1 do
      fn(i, j, math.floor(i * cw + ox), math.floor(j * ch + oy))
    end
  end
end

-- Calls fn(i, x) for every column of width cw of a layer that slides sideways at p (up and
-- down it does not move: it stays glued to the arena's ceiling and floor)
local function columns(p, cw, camX, vx0, vx1, fn)
  local ox = camX * (1 - p)
  for i = math.floor((vx0 - ox) / cw) - 1, math.floor((vx1 - ox) / cw) + 1 do
    fn(i, math.floor(i * cw + ox))
  end
end

-- A rock spire of stacked rows, tapering from its base at (x, y): dir 1 hangs it down from y,
-- -1 stands it up from y. lean drifts its tip sideways. A lit edge on the left, a shadow on the right.
local function spire(x, y, len, w, dir, col, edge, a, lean)
  local shade = { col[1] * 0.55, col[2] * 0.55, col[3] * 0.55 }
  for r = 0, len, 3 do
    local k = r / len
    local rw = math.max(1, w * (1 - k) ^ 0.85)
    local sx = x + (w - rw) / 2 + lean * k
    local sy = dir == 1 and (y + r) or (y - r - 3)
    rect(col, a, sx, sy, rw, 3)
    if edge then
      rect(edge, a * 0.55, sx, sy, 1, 3)
      if rw > 3 then
        rect(shade, a * 0.7, sx + rw - 2, sy, 2, 3)
      end
    end
  end
end

-- The arena the style is drawn for: { x0, top, x1, floorY }, set by src.depthblend
bossbg.box = nil

local function bounds(vy0, vy1)
  local b = bossbg.box
  return b and b[2] or vy0, b and b[4] or vy1
end

-- The glow sprite and the shader that hides it behind terrain ----------------------------------

local glowImg, glowShader
local function glowSprite()
  if not glowImg then
    local n = 64
    local d = love.image.newImageData(n, n)
    for y = 0, n - 1 do
      for x = 0, n - 1 do
        local dist = math.sqrt((x - n / 2 + 0.5) ^ 2 + (y - n / 2 + 0.5) ^ 2) / (n / 2)
        d:setPixel(x, y, 1, 1, 1, math.max(0, 1 - dist) ^ 2)
      end
    end
    glowImg = love.graphics.newImage(d)
    glowImg:setFilter("linear", "linear")
  end
  return glowImg
end

-- A soft glow of radius r (stretched by sx, sy) at x, y
local function glowAt(x, y, r, c, a, sx, sy)
  flush()
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.draw(glowSprite(), x, y, 0, r * 2 / 64 * (sx or 1), r * 2 / 64 * (sy or 1), 32, 32)
end

-- The lurking giant ---------------------------------------------------------------------------
-- want: it is shown (the fish are still small); shown eases to it; stage dims it while it is far

local lurk = { want = false, shown = 0, stage = 1, cx = nil, cy = nil }
local LURK_P = 0.16 -- how slowly it slides past (it is a long way off)
local STAGE_DIM = { 0.7, 0.85, 1, 0 }

-- Called every frame by the fish boss: whether the giant still waits in the dark, which fish
-- the hunter is on, and the middle of the arena it lurks behind
function bossbg.setLurk(dt, want, stage, cx, cy)
  lurk.want, lurk.stage, lurk.cx, lurk.cy = want, stage or 1, cx, cy
  local goal = want and 1 or 0
  lurk.shown = lurk.shown + (goal - lurk.shown) * math.min(1, dt * (want and 1.2 or 0.9))
  if math.abs(goal - lurk.shown) < 0.004 then
    lurk.shown = goal
  end
end

-- How strongly it shows now (0 when it is gone). Going out it gutters like a dying lamp.
local function lurkLevel(t)
  local s = lurk.shown
  if s <= 0.004 then
    return 0
  end
  local dim = STAGE_DIM[lurk.stage] or 1
  if not lurk.want then
    s = s * (0.55 + 0.45 * (math.sin(t * 41) > -0.2 and 1 or 0.15))
  end
  return s * dim
end

-- Where it hangs in the world, for a camera at camX, camY: the middle of the arena pulled
-- toward the middle of the view (the far layer slides slowly)
function bossbg.lurkPos(camX, camY)
  local mx, my = camX + config.VIRTUAL_W / 2, camY + config.VIRTUAL_H / 2
  local acx, acy = lurk.cx or mx, lurk.cy or my
  return mx + (acx - mx) * LURK_P, my + (acy - my) * LURK_P - 24
end

-- Its eyes, offsets from the lure: the one pair (with the lure, the only lights of the scenery)
local EYES = { { -150, 96, 4, 0.1 }, { 150, 96, 4, 0.1 } }

local function blink(t, ph)
  return ((t * 0.31 + ph * 0.77) % 6.5) < 0.16 and 0.1 or 1
end

local function lurkSpot(camX, camY, t)
  local lx, ly = bossbg.lurkPos(camX, camY)
  return lx + math.sin(t * 0.23) * 6, ly + math.sin(t * 0.37) * 3
end

-- Its stalk, a dark curve arching down into the lure, in the scenery itself
local function drawStalk(camX, camY, t)
  local lv = lurkLevel(t)
  if lv <= 0 then
    return
  end
  local lx, ly = lurkSpot(camX, camY, t)
  for k = 0, 36 do
    local u = k / 36
    local x = (1 - u) * (1 - u) * (lx + 70) + 2 * u * (1 - u) * (lx + 96) + u * u * lx
    local y = (1 - u) * (1 - u) * (ly - 170) + 2 * u * (1 - u) * (ly - 70) + u * u * ly
    rect(BCOL_1, 0.9 * lv, x - 1, y, 3, 3)
    if u > 0.55 then
      rect(BCOL_2, (u - 0.55) * 0.9 * lv, x, y, 1, 3) -- (the lure lights its near edge)
    end
  end
end

-- The lure and the eyes, bright (the emissive pass)
local function drawLurkGlow(camX, camY, t)
  local lv = lurkLevel(t)
  if lv <= 0 then
    return
  end
  local lx, ly = lurkSpot(camX, camY, t)
  local pulse = 0.85 + 0.15 * math.sin(t * 2.5)
  local blue = { 0.3, 0.72, 1 }
  glowAt(lx, ly, 170, blue, 0.38 * lv * pulse)
  glowAt(lx, ly, 70, blue, 0.5 * lv * pulse)
  glowAt(lx, ly, 26, { 0.6, 0.9, 1 }, 0.8 * lv)
  rect(BCOL_3, 0.9 * lv, lx - 3, ly - 3, 7, 7)
  rect(BCOL_4, lv, lx - 1, ly - 1, 3, 3)
  for _, e in ipairs(EYES) do
    local a = lv * blink(t, e[4])
    if a > 0.05 then
      local ex, ey = lx + e[1], ly + e[2]
      glowAt(ex, ey, e[3] * 6, { 0.25, 0.8, 1 }, (e[3] > 2 and 0.5 or 0.35) * a)
      rect(BCOL_5, a * (e[3] > 2 and 0.9 or 0.65), ex - e[3] / 2, ey - e[3] / 2, e[3], e[3])
      if e[3] > 2 then
        rect(BCOL_6, a, ex, ey - 1, 1, 1)
      end
    end
  end
end

-- The deep cavern ----------------------------------------------------------------------------

local FAR, MID, NEAR = { 0.024, 0.05, 0.085 }, { 0.04, 0.078, 0.13 }, { 0.02, 0.04, 0.07 }

local function deepStyle(camX, camY, vx0, vy0, vx1, vy1, colors, t)
  -- The far walls: broad, jagged masses of rock, the faintest
  cells(0.1, 240, 380, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 200) < 0.2 then
      return
    end
    local w = 70 + math.floor(hash(i, j + 201) * 90)
    local px = x + math.floor(hash(i, j + 202) * (240 - w))
    for r = 0, 380, 10 do
      local sway = 0.75 + 0.25 * math.sin(r * 0.03 + i * 2.1)
      local lj = math.floor((hash(i + r, j + 203) - 0.5) * 14)
      local rj = math.floor((hash(i + r, j + 204) - 0.5) * 14)
      local ww = w * sway
      rect(FAR, 0.92, px + lj, y + r, ww + rj - lj, 10)
      rect(BCOL_7, 0.35, px + ww + rj - 1, y + r, 1, 10)
    end
  end)
  drawStalk(camX, camY, t)
  -- Stalactites and stalagmites, the middle distance
  cells(0.24, 150, 330, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 210) > 0.25 then
      local len = 70 + math.floor(hash(i, j + 211) * 130)
      local w = 24 + math.floor(hash(i, j + 212) * 30)
      spire(x + 10 + math.floor(hash(i, j + 213) * 90), y, len, w, 1, MID, { 0.1, 0.2, 0.32 }, 0.9, (hash(i, j + 214) - 0.5) * 12)
    end
    if hash(i, j + 215) > 0.3 then
      local len = 60 + math.floor(hash(i, j + 216) * 110)
      local w = 22 + math.floor(hash(i, j + 217) * 30)
      spire(x + 10 + math.floor(hash(i, j + 218) * 90), y + 330, len, w, -1, MID, { 0.1, 0.2, 0.32 }, 0.9, (hash(i, j + 219) - 0.5) * 12)
    end
  end)
  -- Nearer spires, darker
  cells(0.42, 110, 250, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 230) < 0.45 then
      return
    end
    local up = hash(i, j + 231) < 0.5
    local len = 40 + math.floor(hash(i, j + 232) * 90)
    local w = 12 + math.floor(hash(i, j + 233) * 18)
    local bx = x + 8 + math.floor(hash(i, j + 234) * 60)
    spire(bx, up and (y + 250) or y, len, w, up and -1 or 1, NEAR, { 0.07, 0.16, 0.26 }, 0.95, (hash(i, j + 235) - 0.5) * 8)
  end)
  -- Marine snow, drifting down
  cells(0.55, 70, 90, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 250) < 0.4 then
      return
    end
    local fall = (t * (4 + hash(i, j) * 4) + hash(i, j + 1) * 90) % 90
    rect(BCOL_8, 0.2, x + hash(i, j + 2) * 70 + math.sin(t * 0.5 + i) * 3, y + fall, 1, 1)
  end)
end

-- The Colossus's hall -----------------------------------------------------------------------------

-- The cave: two walls of rock, a far one and a nearer, each a smooth rolling skyline rising from the
-- floor, and a drooping ceiling. Few layers, sliding slowly, so the hall stays calm; the middle of
-- the view is left open, the nearer wall most of all.
local WALLS = {
  { p = 0.04, base = 0.6, amp = 0.17, seed = 1.3, clear = 0.4, fill = { 0.20, 0.14, 0.10 }, edge = { 0.36, 0.25, 0.16 } },
  { p = 0.09, base = 0.24, amp = 0.17, seed = 4.1, clear = 1, fill = { 0.10, 0.07, 0.055 }, edge = { 0.27, 0.19, 0.12 } },
}

-- The height of wall w at layer-space coordinate u, drawn at screen-space world x sx
local function wallH(w, u, sx, camX, H)
  local n = math.sin(u * 0.0105 + w.seed) * 0.5 + math.sin(u * 0.0263 + w.seed * 2.1) * 0.3 + math.sin(u * 0.061 + w.seed * 3.7) * 0.2
  local d = math.abs(sx - camX - config.VIRTUAL_W / 2) / 240
  local open = math.min(1, d)
  open = open * open * (3 - 2 * open)
  return math.max(0, H * (w.base + w.amp * n) * (1 - w.clear * (1 - open)))
end


-- The height of the drooping ceiling at screen-space world x sx
local function ceilH(camX, sx)
  local u = sx -- (locked to the world, like the ceiling itself)
  return 12 + 9 * math.sin(u * 0.02) + 5 * math.sin(u * 0.057 + 1)
end

-- Calls fn(x, y, dir, i, hang, layer) for every crystal cluster, each rooted in rock: on the
-- far wall (layer 1) or the nearer one (2), on the ground (3), or in the ceiling (4, hanging).
-- y is where the rock's surface is there. dir -1 grows up, 1 down.
local function eachCluster(camX, vx0, vx1, y0, y1, fn)
  local H = y1 - y0
  for wi, w in ipairs(WALLS) do
    columns(w.p, 240 + wi * 20, camX, vx0, vx1, function(i, x)
      if hash(i, wi * 17) > 0.5 then
        local cx = x + 110
        local top = y1 - wallH(w, cx - camX * (1 - w.p), cx, camX, H)
        if y1 - top > 14 then
          fn(cx, top + 3, -1, i * 3 + wi, false, wi)
        end
      end
    end)
  end
  columns(1, 300, camX, vx0, vx1, function(i, x)
    if hash(i, 331) > 0.55 then
      fn(x + 60 + hash(i, 332) * 160, y1 - 5, -1, i * 3 + 7, false, 3)
    end
  end)
  columns(1, 200, camX, vx0, vx1, function(i, x)
    if hash(i, 335) > 0.55 then
      local cx = x + 40 + hash(i, 336) * 110
      fn(cx, y0 + ceilH(camX, cx) - 3, 1, i * 3 + 11, true, 4)
    end
  end)
end

-- One orange crystal: a six-sided prism with a pointed cap, base (bx, by), leaning ang radians
-- from straight up, its left face dark and its right face bright
local DARK, LIGHT, TIP = { 0.55, 0.2, 0.04 }, { 1, 0.52, 0.12 }, { 1, 0.86, 0.5 }
local function crystal(bx, by, ang, len, w, glow)
  local dx, dy = math.sin(ang), -math.cos(ang)
  local px, py = -dy, dx
  local sx, sy = bx + dx * len * 0.7, by + dy * len * 0.7 -- (where the sides end and the cap begins)
  local tx, ty = bx + dx * len, by + dy * len
  local hw = w / 2
  local g = 0.85 + 0.3 * glow
  local lightC = { math.min(1, LIGHT[1] * g), math.min(1, LIGHT[2] * g), math.min(1, LIGHT[3] * g) }
  poly(DARK, 0.97, bx - px * hw, by - py * hw, bx, by, sx, sy, sx - px * hw, sy - py * hw)
  poly(lightC, 0.97, bx, by, bx + px * hw, by + py * hw, sx + px * hw, sy + py * hw, sx, sy)
  poly({ 0.72, 0.3, 0.07 }, 0.97, sx - px * hw, sy - py * hw, sx, sy, tx, ty)
  poly(TIP, 0.97, sx, sy, sx + px * hw, sy + py * hw, tx, ty)
  rect(BCOL_9, 0.35 + 0.4 * glow, tx, ty, 1, 1)
end


local function quarryHallStyle(camX, camY, vx0, vy0, vx1, vy1, colors, t)
  local y0, y1 = bounds(vy0, vy1)
  local H = y1 - y0
  local DK = { 0.02, 0.015, 0.015 }
  -- A cluster of crystals growing out of a lump of the surrounding rock
  local function cluster(x, y, dir, i, hang, rock)
    local pulse = 0.5 + 0.5 * math.sin(t * 0.9 + i * 2)
    poly(rock, 0.98, x - 28, y - dir * 9, x - 15, y + dir * 3, x + 6, y + dir * 5, x + 24, y + dir * 1, x + 34, y - dir * 9)
    poly({ rock[1] * 1.4, rock[2] * 1.4, rock[3] * 1.4 }, 0.6, x - 15, y + dir * 3, x + 6, y + dir * 5, x + 24, y + dir * 1, x + 22, y + dir * 3, x + 4, y + dir * 7, x - 14, y + dir * 5)
    local n = 3 + math.floor(hash(i, 303) * 3)
    for k = 1, n do
      local u = (k - 1) / math.max(1, n - 1)
      local ang = (u - 0.5) * 1.1 + (hash(i + k, 306) - 0.5) * 0.25 + (hang and math.pi or 0)
      local len = (14 + math.floor(hash(i + k, 304) * 26)) * (1 - math.abs(u - 0.5) * 0.7)
      crystal(x - 6 + u * 28, y + dir * 2, ang, len, 5 + math.floor(hash(i + k, 305) * 4), pulse)
    end
  end
  -- The walls, far to near, drawn in strips four pixels wide, each with its ore and its crystals
  for wi, w in ipairs(WALLS) do
    local off = camX * (1 - w.p)
    for sx = math.floor(vx0 / 4) * 4, vx1, 4 do
      local u = sx - off
      local h = wallH(w, u, sx, camX, H)
      if h > 2 then
        local top = y1 - h
        local cu = math.floor(u / 4)
        rect(w.fill, 0.97, sx, top, 4, h)
        rect(DK, 0.28, sx, top + h * 0.55, 4, h * 0.45) -- (darker toward the ground)
        rect(w.edge, 0.9, sx, top, 4, 2)
        for k = 1, 5 do
          if hash(cu, k + wi * 9) > 0.5 then
            rect(DK, 0.3, sx, top + 8 + k * h / 6 + math.sin(u * 0.05 + k * 2) * 3, 4, 1) -- strata
          end
        end
        if hash(cu, wi) > 0.88 then
          rect(w.edge, 0.4, sx, top + hash(cu, 7) * h, 2, 2)
        end
      end
    end
    -- Veins of ore running down the rock face, ending in a clump of nuggets
    columns(w.p, 150 + wi * 40, camX, vx0, vx1, function(i, x)
      if hash(i, 90 + wi) < 0.4 then
        return
      end
      local vx = x + 20 + math.floor(hash(i, 93) * 120)
      local top = y1 - wallH(w, vx - off, vx, camX, H)
      local steps = 10 + math.floor(hash(i, 94) * 14)
      local vy = top + 12
      if vy + steps * 0.9 > y1 - 12 then
        return
      end
      local c = hash(i, 92) < 0.3 and TWO_1A or TWO_1B
      local dim = { c[1] * 0.5, c[2] * 0.5, c[3] * 0.5 }
      for k = 0, steps do
        local fx, fy = vx + k * 2, vy + math.floor(k * 0.9)
        rect(dim, 0.85, fx, fy, 3, 2)
        if k % 3 == 0 then
          rect(c, 0.5 + 0.4 * math.max(0, math.sin(t * 1.2 + k * 0.7 + i * 5)), fx, fy, 2, 2)
        end
      end
      local ex, ey = vx + steps * 2, vy + math.floor(steps * 0.9)
      for k = 1, 5 do
        local nx, ny = ex + (hash(i + k, 95) - 0.3) * 12, ey + (hash(i + k, 96) - 0.3) * 8
        rect(dim, 0.95, nx - 1, ny - 1, 5, 4)
        rect(c, 0.7 + 0.3 * math.sin(t * 1.5 + k + i), nx, ny - 1, 3, 2)
        rect(BCOL_6, 0.5 + 0.4 * math.max(0, math.sin(t * 1.5 + k * 2 + i)), nx, ny - 1, 1, 1)
      end
    end)
    -- Crystal in the face of the rock: some break out of it in short spikes, others are only
    -- seen as flat faceted inlays set into the stone
    columns(w.p, 110 + wi * 20, camX, vx0, vx1, function(i, x)
      if hash(i, 120 + wi) < 0.45 then
        return
      end
      local fx = x + 20 + math.floor(hash(i, 121) * 70)
      local top = y1 - wallH(w, fx - off, fx, camX, H)
      local fy = top + 16 + hash(i, 122) * math.max(1, y1 - top - 36)
      if y1 - top < 40 then
        return
      end
      local rock = { w.fill[1] * 1.15, w.fill[2] * 1.15, w.fill[3] * 1.15 }
      local pulse = 0.5 + 0.5 * math.sin(t * 0.9 + i)
      if hash(i, 123) < 0.5 then
        poly(rock, 0.98, fx - 9, fy + 5, fx - 4, fy - 3, fx + 5, fy - 4, fx + 11, fy + 5)
        for k = 1, 3 do
          crystal(fx - 6 + k * 5, fy + 3, (k - 2) * 0.55 + (hash(i + k, 124) - 0.5) * 0.3, 7 + math.floor(hash(i + k, 125) * 8), 4, pulse)
        end
      else
        local s = 5 + math.floor(hash(i, 126) * 4)
        poly({ w.fill[1] * 0.4, w.fill[2] * 0.4, w.fill[3] * 0.4 }, 0.95, fx - s - 1, fy, fx, fy - s - 1, fx + s + 1, fy, fx, fy + s + 1)
        poly(DARK, 0.95, fx - s, fy, fx, fy - s, fx, fy + s)
        poly({ 1, 0.52 * (0.9 + 0.2 * pulse), 0.12 }, 0.95, fx, fy - s, fx + s, fy, fx, fy + s)
        rect(BCOL_10, 0.4 + 0.4 * pulse, fx + 1, fy - s + 2, 1, 2)
      end
    end)
    eachCluster(camX, vx0, vx1, y0, y1, function(x, y, dir, i, hang, layer)
      if layer == wi then
        cluster(x, y, dir, i, hang, { w.fill[1] * 1.1, w.fill[2] * 1.1, w.fill[3] * 1.1 })
      end
    end)
  end
  -- The ceiling, drooping, with a few stalactites
  for sx = math.floor(vx0 / 4) * 4, vx1, 4 do
    local ch = ceilH(camX, sx)
    rect(BCOL_11, 0.97, sx, y0, 4, ch)
    rect(BCOL_12, 0.5, sx, y0 + ch, 4, 1)
  end
  columns(1, 150, camX, vx0, vx1, function(i, x)
    if hash(i, 320) > 0.45 then
      local sx = x + 30 + math.floor(hash(i, 321) * 80)
      spire(sx, y0 + ceilH(camX, sx) - 2, math.min(40 + math.floor(hash(i, 322) * 80), H * 0.35), 14 + math.floor(hash(i, 323) * 16), 1, { 0.05, 0.037, 0.036 }, { 0.2, 0.14, 0.1 }, 0.95, (hash(i, 324) - 0.5) * 8)
    end
  end)
  -- The ground: a band of rubble
  rect(BCOL_13, 0.98, vx0, y1 - 8, vx1 - vx0, 8)
  rect(BCOL_14, 0.7, vx0, y1 - 8, vx1 - vx0, 1)
  columns(1, 26, camX, vx0, vx1, function(i, x)
    if hash(i, 340) > 0.5 then
      rect(BCOL_12, 0.8, x, y1 - 8 - math.floor(hash(i, 341) * 3), 2 + math.floor(hash(i, 342) * 3), 3)
    end
  end)
  eachCluster(camX, vx0, vx1, y0, y1, function(x, y, dir, i, hang, layer)
    if layer == 3 then
      cluster(x, y, dir, i, hang, { 0.14, 0.1, 0.075 })
    elseif layer == 4 then
      cluster(x, y, dir, i, hang, { 0.06, 0.045, 0.042 })
    end
  end)
end

local function drawHallGlow(view, t, y0, y1)
  local orange = { 1, 0.5, 0.14 }
  eachCluster(view.x, view.x, view.x + view.w, y0, y1, function(x, y, dir, i)
    local pulse = 0.7 + 0.3 * math.sin(t * 1.4 + i * 2)
    glowAt(x + 4, y + dir * 16, 58, orange, 0.42 * pulse)
  end)
end

-- The Sulfur Queen's acid cavern --------------------------------------------------------------------

local MOLD_A, MOLD_B = { 0.20, 0.30, 0.07 }, { 0.42, 0.55, 0.12 }

-- A pillar of column i: x offset, width, top (the ceiling, or a broken stub standing on the
-- floor); nil if there is none
local function pillarOf(i, y0, y1)
  if hash(i, 400) < 0.35 then
    return nil
  end
  local full = hash(i, 401) < 0.45
  return 30 + math.floor(hash(i, 402) * 90), 18 + math.floor(hash(i, 403) * 14), full and y0 or (y1 - 50 - hash(i, 404) * (y1 - y0) * 0.5), full
end

-- Calls fn(x, y, r, id, onMound) for every pustule: on the faces of the pillars and sitting on
-- the mould mounds along the ground
local function eachPustule(camX, vx0, vx1, y0, y1, fn)
  columns(0.22, 170, camX, vx0, vx1, function(i, x)
    local off, w, top = pillarOf(i, y0, y1)
    if off and hash(i, 430) > 0.35 then
      local py = top + 40 + hash(i, 431) * math.max(10, y1 - top - 90)
      fn(x + off + w * 0.5 + (hash(i, 432) - 0.5) * w, py, 4 + math.floor(hash(i, 433) * 4), i, false)
    end
  end)
  columns(0.6, 120, camX, vx0, vx1, function(i, x)
    if hash(i, 470) > 0.4 then
      local mh = 10 + hash(i, 471) * 12
      for k = 1, 1 + math.floor(hash(i, 472) * 3) do
        local r = 4 + math.floor(hash(i + k, 473) * 5)
        fn(x + 30 + (k - 1) * 12 + hash(i + k, 474) * 8, y1 - mh - r * 0.4, r, i * 5 + k, true)
      end
    end
  end)
end

local function drawPustule(x, y, r, id, t)
  local swell = 1 + 0.12 * math.sin(t * (1.1 + hash(id, 1) * 1.2) + hash(id, 2) * 20)
  disc({ 0.16, 0.24, 0.05 }, 0.95, x, y, r * swell + 1)
  disc({ 0.62, 0.8, 0.14 }, 0.9, x, y, r * swell)
  disc({ 0.9, 0.95, 0.4 }, 0.6, x - r * 0.2, y - r * 0.25, r * 0.55 * swell)
  rect(BCOL_15, 0.9, x - r * 0.45, y - r * 0.55, 2, 1) -- the gloss
  -- Now and then one weeps: a drop that runs down and is gone
  local cyc = (t * 0.35 + hash(id, 3) * 5) % 3
  if cyc < 0.7 and hash(id, 4) > 0.4 then
    rect(BCOL_16, 0.8 * (1 - cyc / 0.7), x, y + r + cyc * 20, 1, 3)
  end
end

local function acidStyle(camX, camY, vx0, vy0, vx1, vy1, colors, t)
  local y0, y1 = bounds(vy0, vy1)
  -- The pillars, ceiling to floor (or broken off short, standing on the floor)
  columns(0.22, 170, camX, vx0, vx1, function(i, x)
    local off, w, top, full = pillarOf(i, y0, y1)
    if not off then
      return
    end
    local px = x + off
    for r = 0, y1 - top, 8 do
      local jag = (not full and r < 16) and math.floor((hash(r, i) - 0.5) * 8) or 0
      rect(BCOL_17, 0.95, px + jag, top + r, w - jag, 8)
    end
    rect(BCOL_18, 0.6, px, top, 2, y1 - top)
    rect(BCOL_19, 0.7, px + w - 3, top, 3, y1 - top)
    if full then
      rect(BCOL_20, 0.95, px - 4, y0, w + 8, 8) -- (its capital, against the ceiling)
    end
    for k = 0, 2 do
      rect(MOLD_A, 0.5, px + 2 + k * 4, top + 20 + hash(i, 410 + k) * math.max(10, y1 - top - 80), 2, 18 + math.floor(hash(i, 415 + k) * 40))
    end
    local cy = top + 30 + hash(i, 420) * math.max(10, y1 - top - 70)
    for k = 0, 9 do
      rect(BCOL_21, 0.8, px + 4 + math.floor(math.sin(k * 1.3 + i) * 3) + k % 2, cy + k * 4, 1, 4)
    end
  end)
  -- The ceiling and the stalactites hanging from it, slimed and dripping
  rect(BCOL_22, 0.97, vx0, y0, vx1 - vx0, 10)
  rect(BCOL_23, 0.5, vx0, y0 + 10, vx1 - vx0, 1)
  columns(0.5, 100, camX, vx0, vx1, function(i, x)
    if hash(i, 450) < 0.5 then
      return
    end
    local sx = x + 10 + math.floor(hash(i, 451) * 60)
    local len = math.min(30 + math.floor(hash(i, 452) * 90), (y1 - y0) * 0.35)
    local w = 12 + math.floor(hash(i, 453) * 16)
    spire(sx, y0 + 8, len, w, 1, { 0.04, 0.05, 0.02 }, { 0.2, 0.28, 0.08 }, 0.95, (hash(i, 454) - 0.5) * 10)
    local tipx = sx + w / 2 + (hash(i, 454) - 0.5) * 10
    rect(BCOL_24, 0.75, tipx, y0 + 8 + len, 1, 3)
    local cyc = (t * 0.5 + hash(i, 455) * 4) % 2
    if cyc < 1.2 then
      rect(BCOL_25, 0.8 * (1 - cyc / 1.2), tipx, y0 + 11 + len + cyc * 60, 1, 3)
    end
  end)
  -- Mould mounds along the ground, crusted with blocks of mould
  columns(0.6, 120, camX, vx0, vx1, function(i, x)
    if hash(i, 470) <= 0.4 then
      return
    end
    local mh = 10 + hash(i, 471) * 12
    poly({ 0.1, 0.14, 0.04 }, 0.97, x + 12, y1, x + 30, y1 - mh, x + 70, y1 - mh * 0.8, x + 92, y1)
    for k = 1, 9 do
      local bx = x + 16 + hash(i + k, 475) * 70
      local by = y1 - mh * (0.3 + hash(i + k, 476) * 0.6)
      local s = 3 + math.floor(hash(i + k, 477) * 5)
      rect(MOLD_A, 0.9, bx, by, s, s - 1)
      rect(MOLD_B, 0.55, bx + 1, by, s - 2, 1)
    end
  end)
  -- Mould patches round the pustules on the pillars
  eachPustule(camX, vx0, vx1, y0, y1, function(x, y, r, id, onMound)
    if not onMound then
      for k = 1, 6 do
        local s = 4 + math.floor(hash(id + k, 478) * 5)
        rect(MOLD_A, 0.85, x + (hash(id + k, 479) - 0.5) * 22, y + (hash(id + k, 480) - 0.5) * 16, s, s - 1)
      end
    end
  end)
  eachPustule(camX, vx0, vx1, y0, y1, function(x, y, r, id)
    drawPustule(x, y, r, id, t)
  end)
  -- The pool along the ground: one soft layer of acid, thickest at the floor, a faint chop on top
  for k = 0, 7 do
    rect(BCOL_26, 0.04 + k * 0.018, vx0, y1 - 30 + k * 3.5, vx1 - vx0, 4)
  end
  for x = math.floor(vx0 / 4) * 4, vx1, 4 do
    local wx = x + camX * 0.4
    local w = math.sin(wx * 0.035 + t * 0.8) * 1.5 + math.sin(wx * 0.09 + t * 1.3) * 0.7
    rect(BCOL_27, 0.14, x, y1 - 20 + w, 4, 2)
  end
  for k = 0, 4 do
    local bx = vx0 + ((k * 97) % (vx1 - vx0 + 40)) - 20
    local cyc = (t * 0.6 + k * 0.37) % 2.4
    if cyc < 0.5 then
      flush()
      love.graphics.setColor(0.85, 1, 0.35, 0.45 * (1 - cyc / 0.5))
      love.graphics.circle("line", math.floor(bx), math.floor(y1 - 19), 1 + cyc * 7, 10)
    end
  end
  -- Spores rising off the acid
  cells(0.68, 90, 170, camX, camY, vx0, vy0, vx1, vy1, function(i, j, x, y)
    if hash(i, j + 460) < 0.45 then
      return
    end
    local rise = (t * (8 + hash(i, j) * 8) + hash(i, j + 1) * 170) % 170
    local py = y + 170 - rise
    if py > y0 + 10 and py < y1 - 12 then
      local a = 0.35 * math.min(1, rise / 30) * math.min(1, (170 - rise) / 40)
      rect(BCOL_28, a, x + hash(i, j + 2) * 90 + math.sin(t * 0.8 + rise * 0.05 + i) * 4, py, 2, 2)
    end
  end)
end

local function drawAcidGlow(view, t, y0, y1)
  eachPustule(view.x, view.x, view.x + view.w, y0, y1, function(x, y, r, id)
    glowAt(x, y, 30, { 0.7, 0.95, 0.15 }, 0.3 * (0.75 + 0.25 * math.sin(t * 1.1 + id)))
  end)
  -- the pool glows softly along its length
  glowAt(view.x + view.w / 2, y1 - 8, 1, { 0.5, 0.85, 0.1 }, 0.2, view.w * 0.8, 24)
end

bossbg.styles = { deep = deepStyle, quarryhall = quarryHallStyle, acid = acidStyle }

-- What glows in the arena's far layers, drawn bright over the lit scene in the emissive pass, with
-- the terrain mask hiding it wherever rock is in front. view = { x, y, w, h }, box = the arena's
-- box, mask = the frame's terrain mask (nil: draw nothing).
local clearImage -- a 1x1 image with nothing in it: "no creatures" for the glow shader
function bossbg.drawGlow(view, kind, box, mask, ents)
  if not mask then
    return
  end
  if not ents then
    -- (like the old mine's far lanterns: the glow lies over the creatures, with no dark cut-out or rim round them)
    clearImage = clearImage or love.graphics.newImage(love.image.newImageData(1, 1))
    ents = clearImage
  end
  if glowShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
uniform Image mask;
uniform Image ents; // the creatures and the hunter in front (alpha): they stay in front of the glow
uniform vec2 canvasSize;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 q = sc / canvasSize;
  vec2 px = 3.0 / canvasSize; // (a few pixels round each creature too: a dark rim to read it by)
  float e = max(max(Texel(ents, q + vec2(px.x, 0.0)).a, Texel(ents, q - vec2(px.x, 0.0)).a),
    max(Texel(ents, q + vec2(0.0, px.y)).a, Texel(ents, q - vec2(0.0, px.y)).a));
  float solid = max(Texel(mask, q).r, max(e, Texel(ents, q).a));
  vec4 t = Texel(tex, uv) * color;
  return vec4(t.rgb, t.a * (1.0 - smoothstep(0.2, 0.6, solid)));
}
]])
    glowShader = ok and sh or false
  end
  if not glowShader then
    return
  end
  local t = love.timer.getTime()
  flush()
  love.graphics.push("all")
  love.graphics.setShader(glowShader)
  glowShader:send("mask", mask)
  glowShader:send("ents", ents)
  glowShader:send("canvasSize", { mask:getDimensions() })
  love.graphics.setBlendMode("add")
  if kind == "deep" then
    drawLurkGlow(view.x, view.y, t)
  elseif kind == "quarryhall" then
    drawHallGlow(view, t, box[2], box[4])
  elseif kind == "acid" then
    drawAcidGlow(view, t, box[2], box[4])
  end
  love.graphics.pop()
end

return bossbg
