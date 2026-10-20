-- The Angler Sharkwhale, drawn as a standalone picture (not yet used by the fish boss).
-- A whale shark's spotted body with an angler's lure, seen three-quarters on: a huge
-- domed head, the maw gaping toward the viewer with four great tusks, ray spines with
-- glowing tips. Facing left. Baked once, pixel by pixel:
--   1. a region map from shapes (laid out in the reference picture's coordinates),
--   2. a distance-to-edge map, so the body shades as a rounded mass,
--   3. colour from short palette ramps with ordered dithering, then spots and outlines.
-- anglerart.bake() returns the layers (the body, each tusk and its broken stump, white copies
-- for a hit flash), the tusks' and the body's boxes, and the points to light (glows).

local anglerart = {}

local W, H = 620, 340
anglerart.W, anglerart.H = W, H

-- reference-picture coordinates to canvas pixels
local function R(x, y)
  return (x - 250) * 0.7, (y - 30) * 0.7
end

local ID = {
  NONE = 0, BODY = 1, BELLY = 2, FIN = 3, PEC = 4, SPINE = 5, TIP = 6, CAV = 7, LIP = 8, EYE = 9,
  STALK = 10, BULB = 11, GUM = 16, FANG = 12, TAIL = 17, DORS = 18, -- 12..15: the four tusks
}

-- palette ramps, dark to light
local RAMP = {
  body = { { 0.02, 0.04, 0.10 }, { 0.04, 0.08, 0.18 }, { 0.06, 0.12, 0.26 }, { 0.09, 0.18, 0.35 }, { 0.13, 0.25, 0.45 }, { 0.19, 0.34, 0.56 }, { 0.27, 0.45, 0.67 } },
  belly = { { 0.06, 0.10, 0.20 }, { 0.11, 0.17, 0.30 }, { 0.18, 0.27, 0.42 }, { 0.27, 0.38, 0.55 }, { 0.38, 0.50, 0.66 }, { 0.50, 0.62, 0.76 } },
  fin = { { 0.02, 0.04, 0.10 }, { 0.04, 0.08, 0.18 }, { 0.06, 0.12, 0.25 }, { 0.09, 0.17, 0.33 }, { 0.13, 0.24, 0.42 } },
  cav = { { 0.01, 0.01, 0.03 }, { 0.05, 0.03, 0.09 }, { 0.09, 0.05, 0.15 }, { 0.14, 0.08, 0.22 }, { 0.20, 0.13, 0.30 }, { 0.28, 0.19, 0.38 } },
  lip = { { 0.10, 0.14, 0.26 }, { 0.18, 0.25, 0.38 }, { 0.28, 0.37, 0.52 }, { 0.40, 0.50, 0.65 } },
  fang = { { 0.36, 0.30, 0.28 }, { 0.58, 0.52, 0.44 }, { 0.76, 0.71, 0.60 }, { 0.90, 0.86, 0.74 }, { 1.0, 0.97, 0.89 } },
  glow = { { 0.20, 0.60, 0.90 }, { 0.40, 0.82, 1.0 }, { 0.75, 0.96, 1.0 }, { 1, 1, 1 } },
}
local OUTLINE = { 0.01, 0.02, 0.06 }
local SPOT = { 0.56, 0.86, 0.98 }

-- 4x4 ordered dither thresholds
local BAYER = { { 0, 8, 2, 10 }, { 12, 4, 14, 6 }, { 3, 11, 1, 9 }, { 15, 7, 13, 5 } }

local function ramp(r, s, x, y)
  local n = #r
  local b = (BAYER[y % 4 + 1][x % 4 + 1] + 0.5) / 16
  local i = math.floor(math.max(0, math.min(1, s)) * (n - 1) + b) + 1
  return r[math.max(1, math.min(n, i))]
end

local function mix(a, b, f)
  return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
end

-- shape helpers -----------------------------------------------------------------------------

local function smooth(pts, n)
  for _ = 1, n do
    local out, m = {}, #pts / 2
    for i = 1, m do
      local j = i % m + 1
      local x1, y1, x2, y2 = pts[2 * i - 1], pts[2 * i], pts[2 * j - 1], pts[2 * j]
      out[#out + 1], out[#out + 2] = x1 * 0.75 + x2 * 0.25, y1 * 0.75 + y2 * 0.25
      out[#out + 1], out[#out + 2] = x1 * 0.25 + x2 * 0.75, y1 * 0.25 + y2 * 0.75
    end
    pts = out
  end
  return pts
end

local function fill(map, id, pts)
  local n = #pts / 2
  local ymin, ymax = math.huge, -math.huge
  for i = 1, n do
    ymin, ymax = math.min(ymin, pts[2 * i]), math.max(ymax, pts[2 * i])
  end
  for py = math.max(0, math.floor(ymin)), math.min(H - 1, math.ceil(ymax)) do
    local y = py + 0.5
    local xs = {}
    for i = 1, n do
      local j = i % n + 1
      local x1, y1, x2, y2 = pts[2 * i - 1], pts[2 * i], pts[2 * j - 1], pts[2 * j]
      if (y1 <= y) ~= (y2 <= y) then
        xs[#xs + 1] = x1 + (y - y1) / (y2 - y1) * (x2 - x1)
      end
    end
    table.sort(xs)
    for k = 1, #xs - 1, 2 do
      for px = math.max(0, math.ceil(xs[k] - 0.5)), math.min(W - 1, math.ceil(xs[k + 1] - 0.5) - 1) do
        map[py][px] = id
      end
    end
  end
end

-- a shape given in reference coordinates
local function shape(map, id, rounds, ...)
  local p, out = { ... }, {}
  for i = 1, #p, 2 do
    out[i], out[i + 1] = R(p[i], p[i + 1])
  end
  fill(map, id, smooth(out, rounds))
end

local function disc(map, id, cx, cy, r)
  for py = math.max(0, math.floor(cy - r)), math.min(H - 1, math.ceil(cy + r)) do
    for px = math.max(0, math.floor(cx - r)), math.min(W - 1, math.ceil(cx + r)) do
      local dx, dy = px + 0.5 - cx, py + 0.5 - cy
      if dx * dx + dy * dy <= r * r then
        map[py][px] = id
      end
    end
  end
end

local function bezier(p0, p1, p2, p3, t)
  local u = 1 - t
  return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
end

-- a tapering stroke along a cubic curve (reference coordinates), r0 -> r1 pixels thick
local function stroke(map, id, ax, ay, bx, by, cx, cy, dx, dy, r0, r1)
  local x0, y0 = R(ax, ay)
  local x1, y1 = R(bx, by)
  local x2, y2 = R(cx, cy)
  local x3, y3 = R(dx, dy)
  local steps = 200
  for i = 0, steps do
    local t = i / steps
    disc(map, id, bezier(x0, x1, x2, x3, t), bezier(y0, y1, y2, y3, t), r0 + (r1 - r0) * t)
  end
  return x3, y3
end

-- a curved tusk: base from (lx, ly) to (rx, ry), tip at (tx, ty), bowed by (bx, by)
local function tusk(map, under, id, lx, ly, rx, ry, tx, ty, bx, by)
  local pts = {}
  local function q(ax, ay, cx, cy, ex, ey, t)
    local u = 1 - t
    return u * u * ax + 2 * u * t * cx + t * t * ex, u * u * ay + 2 * u * t * cy + t * t * ey
  end
  local clx, cly = (lx + tx) / 2 + bx, (ly + ty) / 2 + by
  local crx, cry = (rx + tx) / 2 + bx * 0.7, (ry + ty) / 2 + by * 0.7
  for i = 0, 12 do
    local x, y = q(lx, ly, clx, cly, tx, ty, i / 12)
    pts[#pts + 1], pts[#pts + 2] = x, y
  end
  for i = 11, 0, -1 do
    local x, y = q(rx, ry, crx, cry, tx, ty, i / 12)
    pts[#pts + 1], pts[#pts + 2] = x, y
  end
  local tmp = {}
  for y = 0, H - 1 do
    tmp[y] = {}
  end
  shape(tmp, id, 0, (table.unpack or unpack)(pts))
  for y, row in pairs(tmp) do
    for x, v in pairs(row) do
      if v == id and (map[y][x] == ID.CAV or map[y][x] == ID.GUM) then
        under[y][x] = map[y][x]
        map[y][x] = id
      end
    end
  end
end

-- the picture -----------------------------------------------------------------------------

local TUSKS = {
  -- base left, base right, tip, bow (reference coordinates)
  { 330, 176, 392, 180, 380, 302, -14, 0 }, -- upper, front
  { 414, 172, 482, 176, 462, 280, -12, 4 }, -- upper, back
  { 332, 420, 394, 424, 382, 312, -14, 0 }, -- lower, front
  { 430, 428, 496, 424, 472, 314, -12, -4 }, -- lower, back
}

function anglerart.bake()
  local map = {}
  for y = 0, H - 1 do
    map[y] = {}
    for x = 0, W - 1 do
      map[y][x] = 0
    end
  end
  local glows = {}
  local function glow(x, y, r, kind, layer)
    glows[#glows + 1] = { x = x, y = y, r = r, kind = kind, layer = layer }
  end

  -- spines along the nape and the back, behind the body, each tipped with a light
  local spines = {
    { 575, 100, 585, 80, 592, 68, 600, 58, 2.2, 1.0 },
    { 612, 110, 625, 90, 634, 78, 642, 70, 2.2, 1.0 },
    { 650, 124, 662, 106, 672, 96, 682, 88, 2.2, 1.0 },
    { 812, 196, 828, 165, 842, 142, 858, 124, 2.4, 1.0 },
    { 852, 214, 870, 190, 888, 172, 904, 160, 2.4, 1.0 },
    { 892, 232, 908, 214, 924, 202, 942, 194, 2.2, 1.0 },
  }
  for _, s in ipairs(spines) do
    local tx, ty = stroke(map, ID.SPINE, s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], s[9], s[10])
    disc(map, ID.TIP, tx, ty, 2.6)
    glow(tx, ty, 10, "tip", "dors")
  end

  -- the far pelvic fin, the dorsal fin and the tail
  shape(map, ID.FIN, 1, 648, 396, 702, 382, 736, 436, 724, 484, 696, 462, 660, 424)
  do
    local x, y = R(722, 482)
    glow(x, y, 9, "tip", "pelv")
  end
  shape(map, ID.DORS, 1, 684, 142, 738, 94, 792, 66, 784, 120, 806, 182)
  do
    local x, y = R(790, 68)
    glow(x, y, 8, "tip", "dors")
  end
  shape(map, ID.TAIL, 1, 958, 258, 1018, 182, 1078, 102, 1126, 50, 1114, 120, 1082, 210, 1052, 268, 1036, 300, 1004, 344, 984, 312, 968, 296)

  -- the body: a great domed head tapering to the tail
  shape(map, ID.BODY, 2,
    322, 175, 338, 140, 378, 112, 430, 95, 490, 88, 560, 92, 620, 108, 690, 135, 760, 165, 830, 200, 900, 235, 950, 258, 984, 272,
    988, 292, 940, 305, 880, 320, 800, 345, 720, 375, 650, 405, 580, 430, 500, 446, 420, 444, 360, 430, 330, 408, 318, 370, 314, 300, 316, 230)
  -- the pleated underside, from the lower jaw back along the belly
  shape(map, ID.BELLY, 1,
    322, 388, 360, 412, 430, 422, 510, 412, 580, 388, 640, 354, 700, 332, 780, 316, 860, 302, 940, 292, 986, 292,
    940, 305, 880, 320, 800, 345, 720, 375, 650, 405, 580, 430, 500, 446, 420, 444, 360, 430, 330, 408)
  -- the body's own silhouette (before the near fin covers part of it): shading and spots
  -- follow this, so they run on unbroken under the fin
  local sil = {}
  for y = 0, H - 1 do
    sil[y] = {}
    for x = 0, W - 1 do
      sil[y][x] = map[y][x] == ID.BODY or map[y][x] == ID.BELLY
    end
  end
  -- the near pectoral fin, sweeping back under the body
  shape(map, ID.PEC, 1, 632, 346, 700, 338, 780, 362, 860, 394, 908, 412, 842, 418, 760, 408, 686, 388)
  do
    local x, y = R(906, 411)
    glow(x, y, 9, "tip", "pec")
  end

  -- the maw: a thick rim, then the ridged throat
  local cav = { 332, 192, 400, 180, 470, 190, 540, 215, 588, 268, 598, 330, 572, 378, 508, 402, 420, 410, 356, 400, 332, 372, 328, 270 }
  local rim = {}
  for i = 1, #cav, 2 do
    rim[i], rim[i + 1] = 462 + (cav[i] - 462) * 1.07, 296 + (cav[i + 1] - 296) * 1.08
  end
  shape(map, ID.LIP, 2, (table.unpack or unpack)(rim))
  shape(map, ID.CAV, 2, (table.unpack or unpack)(cav))

  -- the tusks
  local tuskEnds = {}
  local under = {}
  for y = 0, H - 1 do
    under[y] = {}
  end
  for i, t in ipairs(TUSKS) do
    -- a gum where the tusk comes out from behind the lip
    local mx, my = (t[1] + t[3]) / 2, (t[2] + t[4]) / 2
    local gx, gy = R(mx + (t[5] - mx) * 0.14, my + (t[6] - my) * 0.14)
    for dx = -16, 16 do
      for dy = -5, 5 do
        if (dx / 16) ^ 2 + (dy / 5) ^ 2 <= 1 then
          local px, py = math.floor(gx + dx), math.floor(gy + dy)
          if map[py] and map[py][px] == ID.CAV then
            map[py][px] = ID.GUM
          end
        end
      end
    end
    tusk(map, under, ID.FANG + i - 1, t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
    local _, by0 = R(0, (t[2] + t[4]) / 2)
    local _, ty0 = R(0, t[6])
    tuskEnds[ID.FANG + i - 1] = { by0, ty0 }
  end

  -- the eye
  local ex, ey = R(530, 158)
  disc(map, ID.EYE, ex, ey, 9)
  glow(ex, ey, 22, "eye", "body")

  -- the lure: a thick stalk arching forward from the crown, and its bulb
  stroke(map, ID.STALK, 470, 94, 445, 18, 335, 14, 304, 112, 4.2, 2.0)
  local bx, by = R(300, 128)
  disc(map, ID.BULB, bx, by, 11)
  glow(bx, by, 60, "lure", "lure")

  -- distance to the edge of the body's silhouette (chamfer), for rounded shading
  local inBody = {}
  local function bodyish(id)
    return id == ID.BODY or id == ID.BELLY or id == ID.CAV or id == ID.LIP or id == ID.EYE or id == ID.GUM or (id >= ID.FANG and id < ID.GUM)
  end
  local dist = {}
  local BIG = 1e9
  for y = 0, H - 1 do
    dist[y] = {}
    for x = 0, W - 1 do
      dist[y][x] = (sil[y][x] or bodyish(map[y][x])) and BIG or 0
    end
  end
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if dist[y][x] > 0 then
        local d = dist[y][x]
        if x > 0 then d = math.min(d, dist[y][x - 1] + 1) else d = 1 end
        if y > 0 then
          d = math.min(d, dist[y - 1][x] + 1)
          if x > 0 then d = math.min(d, dist[y - 1][x - 1] + 1.4) end
          if x < W - 1 then d = math.min(d, dist[y - 1][x + 1] + 1.4) end
        else
          d = 1
        end
        dist[y][x] = d
      end
    end
  end
  for y = H - 1, 0, -1 do
    for x = W - 1, 0, -1 do
      if dist[y][x] > 0 then
        local d = dist[y][x]
        if x < W - 1 then d = math.min(d, dist[y][x + 1] + 1) else d = 1 end
        if y < H - 1 then
          d = math.min(d, dist[y + 1][x] + 1)
          if x < W - 1 then d = math.min(d, dist[y + 1][x + 1] + 1.4) end
          if x > 0 then d = math.min(d, dist[y + 1][x - 1] + 1.4) end
        else
          d = 1
        end
        dist[y][x] = d
      end
    end
  end

  -- each column's top and bottom of the body silhouette (for spots and pleats)
  local top, bot = {}, {}
  for x = 0, W - 1 do
    for y = 0, H - 1 do
      if sil[y][x] or bodyish(map[y][x]) then
        top[x] = top[x] or y
        bot[x] = y
      end
    end
  end

  -- the throat's centre, and each tusk's span per row (for its shading)
  local tcx, tcy = R(520, 306)
  local fspan = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local id = map[y][x]
      if id >= ID.FANG and id < ID.GUM then
        local k = id .. ":" .. y
        local s = fspan[k]
        if not s then
          fspan[k] = { x, x }
        else
          s[1], s[2] = math.min(s[1], x), math.max(s[2], x)
        end
      end
    end
  end

  -- the throat: ridges that crowd together as they fall down it; ph (0..1) moves them inward
  local function throatColour(x, y, ph)
    local dx, dy = x - tcx, (y - tcy) / 1.15
    local r = math.sqrt(dx * dx + dy * dy)
    local a = math.atan2(dy, dx)
    local depth = 70 / (r + 5) -- 0.8 at the rim, 14 at the bottom of the throat
    local light = math.min(1, (r / 90) ^ 0.9)
    local s = 0.08 + 0.75 * light
    local ring = (depth * 3.4 + 0.15 * math.sin(a * 4 + depth) - ph * 3) % 1
    if ring < 0.3 then
      s = s + 0.32 * light * (dy < 0 and 0.6 or 1) -- a ridge, lit from the mouth
    elseif ring < 0.55 then
      s = s - 0.18 * light
    end
    -- shadow under the upper jaw
    local cavTop = select(2, R(0, 190))
    s = s - 0.25 * math.max(0, 1 - (y - cavTop) / 40)
    if r < 12 then
      s = math.min(s, (r - 4) / 40)
    end
    return ramp(RAMP.cav, s, x, y)
  end

  local NB = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
  local function colour(x, y, id)
        local outer, inner, litEdge = false, false, false
        for _, d in ipairs(NB) do
          local q = map[y + d[2]] and map[y + d[2]][x + d[1]]
          if q == nil or q == 0 then
            outer = true
          elseif q ~= id then
            inner = q
          end
        end
        -- the upper edge catches the lure's light
        local above = map[y - 2] and map[y - 2][x]
        if (above == nil or above == 0) and not outer then
          litEdge = true
        end

        local c
        local t = (top[x] and bot[x] and bot[x] > top[x]) and (y - top[x]) / (bot[x] - top[x]) or 0.5
        local lightX = 1 - x / W -- the lure hangs at the front: more light there
        if outer and id ~= ID.TIP and id ~= ID.BULB then
          c = OUTLINE
        elseif id == ID.BODY then
          local round = math.min(1, (dist[y][x] or 0) / 20) ^ 0.6
          local s = 0.02 + 0.5 * round * (1 - 0.75 * t) + 0.22 * (1 - t) + 0.25 * lightX - 0.12 * t * t
          if litEdge then
            s = s + 0.35
          end
          c = ramp(RAMP.body, s, x, y)
          -- whale-shark spots, laid in rows that follow the body and shrink toward the tail
          if t > 0.04 and t < 0.86 then
            local p = x + 0.6 * x * x / W -- stretched along the length
            local row = math.floor(t / 0.105 + 0.5)
            local rowT = row * 0.105
            local sx = 15
            local off = (row % 2) * sx / 2
            local cx = math.floor((p + off) / sx) * sx - off + sx / 2
            local slope = 1 + 1.2 * x / W
            local col = math.floor((p + off) / sx)
            local hsh = math.sin(col * 12.9898 + row * 78.233) * 43758.5453
            hsh = hsh - math.floor(hsh)
            local jx, jy = (hsh - 0.5) * 6, ((hsh * 7) % 1 - 0.5) * 4
            local dx = (p - cx - jx) / slope
            local dy = (t - rowT) * (bot[x] - top[x]) - jy
            local rad = math.max(1.1, (2.8 - 1.6 * x / W) * math.min(1, (bot[x] - top[x]) / 150 + 0.4)) * (0.75 + 0.5 * ((hsh * 13) % 1))
            if hsh > 0.08 and dx * dx + dy * dy <= rad * rad then
              c = mix(c, SPOT, 0.35 + 0.55 * math.min(1, s + 0.2))
            end
          end
        elseif id == ID.BELLY then
          local s = 0.2 + 0.45 * (1 - t) + 0.15 * lightX + 0.15 * math.min(1, (dist[y][x] or 0) / 12)
          -- pleats running along the underside
          if bot[x] and (bot[x] - y) % 4 == 0 then
            s = s - 0.3
          end
          c = ramp(RAMP.belly, s, x, y)
        elseif id == ID.FIN or id == ID.PEC or id == ID.DORS or id == ID.TAIL then
          local s = 0.35 + 0.25 * lightX
          if inner and id == ID.PEC then
            c = RAMP.fin[1]
          else
            if litEdge then
              s = s + 0.35
            end
            c = ramp(RAMP.fin, s, x, y)
            if (x + (math.floor(y / 9) % 2) * 5) % 10 == 0 and y % 9 == 4 then
              c = mix(c, SPOT, 0.55)
            end
          end
        elseif id == ID.SPINE then
          c = ramp(RAMP.fin, 0.55, x, y)
        elseif id == ID.TIP then
          c = RAMP.glow[3]
        elseif id == ID.CAV then
          c = throatColour(x, y, 0)
        elseif id == ID.LIP then
          local s = 0.25 + 0.6 * math.max(0, math.min(1, (y - tcy) / 90 + 0.4))
          c = ramp(RAMP.lip, s, x, y)
        elseif id == ID.GUM then
          c = ramp(RAMP.cav, 0.55, x, y)
          c = { c[1] * 1.6 + 0.08, c[2] * 0.9, c[3] * 1.1 }
        elseif id >= ID.FANG and id < ID.GUM then
          local span = fspan[id .. ":" .. y]
          local f = span and span[2] > span[1] and (x - span[1]) / (span[2] - span[1]) or 0.5
          local e = tuskEnds[id]
          local along = math.max(0, math.min(1, (y - e[1]) / (e[2] - e[1])))
          local s = 1.0 - 0.8 * f
          if f > 0.2 and f < 0.38 then
            s = s + 0.15 -- the shine down its length
          end
          s = s - 0.35 * math.max(0, 0.18 - along) / 0.18 - 0.2 * math.max(0, along - 0.8) / 0.2
          if inner and inner ~= id then
            c = { 0.20, 0.14, 0.16 }
          else
            c = ramp(RAMP.fang, s, x, y)
          end
        elseif id == ID.EYE then
          local dx, dy = x + 0.5 - ex, y + 0.5 - ey
          local d = math.sqrt(dx * dx + dy * dy)
          if d > 6.5 then
            c = { 0.03, 0.06, 0.14 }
          else
            c = ramp(RAMP.glow, 1 - d / 6.5, x, y)
          end
        elseif id == ID.STALK then
          c = ramp(RAMP.body, litEdge and 0.75 or 0.3, x, y)
        elseif id == ID.BULB then
          local dx, dy = x + 0.5 - bx, y + 0.5 - by
          local d = math.sqrt(dx * dx + dy * dy)
          c = ramp(RAMP.glow, 1.05 - d / 11, x, y)
        end
        return c
  end

  -- The layers -----------------------------------------------------------------------------
  -- The picture faces left; the boss faces right, so every layer is written mirrored.
  -- body: the head, the body and everything fixed to it (the maw is a hole in it: the throat,
  --       which is animated, shows through)
  -- jaw: the lower jaw, hinged behind the mouth; the lower tusks ride with it
  -- dors, pelv, tail, pec: fins; lure: the stalk and its bulb; throat: frames of the maw
  local function mx(x)
    return W - 1 - x
  end
  local LAYERS = { "body", "jaw", "dors", "pelv", "tail", "pec", "lure" }
  local LD = {}
  for _, n in ipairs(LAYERS) do
    LD[n] = love.image.newImageData(W, H)
  end
  local layerOf = {
    [ID.SPINE] = "dors", [ID.TIP] = "dors", [ID.DORS] = "dors", [ID.FIN] = "pelv", [ID.TAIL] = "tail",
    [ID.PEC] = "pec", [ID.STALK] = "lure", [ID.BULB] = "lure",
  }
  local hingeX = R(598, 330)
  local _, jawTop = R(0, 300)
  local function jawish(id)
    return id == ID.BODY or id == ID.BELLY or id == ID.LIP or id == ID.GUM
  end
  local function inJaw(x, y, id)
    return jawish(id) and y >= jawTop and x <= hingeX + (y - jawTop) * 0.12
  end

  -- the throat: the maw's pixels, plus a band of the jaw's top (so the jaw can open on it)
  local tlist, tseen = {}, {}
  local function throat(x, y)
    local k = y * W + x
    if not tseen[k] then
      tseen[k] = true
      tlist[#tlist + 1] = { x, y }
    end
  end
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local id = map[y][x]
      if id == ID.CAV or (id >= ID.FANG and id < ID.GUM and under[y][x] == ID.CAV) then
        throat(x, y)
      end
    end
  end
  for x = 0, W - 1 do
    local top
    for y = 0, H - 1 do
      if inJaw(x, y, map[y][x]) then
        top = y
        break
      end
    end
    if top then
      for y = top, math.min(H - 1, top + 14) do
        -- (not out at the rim, where the jaw's edge is the silhouette)
        if inJaw(x, y, map[y][x]) and (map[y][x - 3] or 0) ~= 0 and (map[y][x + 3] or 0) ~= 0 then
          throat(x, y)
        end
      end
    end
  end

  -- A tusk's three states: whole, slightly damaged (cracked, the tip a little short) and badly
  -- damaged (more cracks, chips out of its edge, the tip broken well back, yellowed)
  -- (each tusk wears differently: round bites out of its edges, and its tip broken off in a round
  -- chunk. Slightly damaged has a couple of small bites; badly damaged has more, bigger ones.)
  local function rnd(i, k)
    local v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
    return v - math.floor(v)
  end
  local WEAR = {}
  for i = 1, #TUSKS do
    local w = { bites = { [1] = {}, [2] = {} } }
    local function bite(state, ba, side, r)
      w.bites[state][#w.bites[state] + 1] = { ba = ba, side = side, r = r }
    end
    for c = 1, 1 + math.floor(rnd(i, 1) * 2) do
      local ba, side, r = 0.28 + rnd(i, 10 + c) * 0.45, rnd(i, 20 + c) < 0.5 and -1 or 1, 3 + rnd(i, 30 + c) * 2.5
      bite(1, ba, side, r)
      bite(2, ba, side, r + 1.8) -- (the same bites, grown)
    end
    for c = 1, 2 + math.floor(rnd(i, 2) * 2) do
      bite(2, 0.12 + rnd(i, 50 + c) * 0.6, rnd(i, 60 + c) < 0.5 and -1 or 1, 4 + rnd(i, 70 + c) * 3)
    end
    w.tip1 = 4 + rnd(i, 14) * 3 -- the radius of the chunk gone from the tip
    w.tip2 = 8 + rnd(i, 15) * 5
    w.tipSide = (rnd(i, 16) - 0.5) * 0.5
    w.tint = rnd(i, 17)
    WEAR[i] = w
  end

  -- where a bite is centred (just inside the tusk's edge, at a place along its length)
  local function biteCentre(id, i, bite)
    if bite.cx == nil then
      local e = tuskEnds[id]
      local yb = math.floor(e[1] + bite.ba * (e[2] - e[1]) + 0.5)
      local span = fspan[id .. ":" .. yb]
      if span then
        bite.cx, bite.cy = (bite.side < 0 and span[1] + 1 or span[2] - 1), yb
      else
        bite.cx = false
      end
    end
    return bite.cx, bite.cy
  end

  local function damaged(state, i, id, x, y, c)
    local w = WEAR[i]
    local rim = false
    local e = tuskEnds[id]
    -- the tip: a round chunk gone
    local tr = state == 1 and w.tip1 or w.tip2
    if not w.tipX then
      local dir = e[1] < e[2] and -1 or 1
      for k = 0, 14 do
        local span = fspan[id .. ":" .. math.floor(e[2] + dir * k)]
        if span then
          w.tipX = (span[1] + span[2]) / 2
          break
        end
      end
      w.tipX = w.tipX or 0
    end
    local tx, ty = w.tipX + w.tipSide * tr, e[2]
    local d2 = (x - tx) ^ 2 + (y - ty) ^ 2
    if d2 <= tr * tr then
      return nil
    elseif d2 <= (tr + 1.3) ^ 2 then
      rim = true
    end
    for _, bt in ipairs(w.bites[state]) do
      local cx, cy = biteCentre(id, i, bt)
      if cx then
        local d = (x - cx) ^ 2 + (y - cy) ^ 2
        if d <= bt.r * bt.r then
          return nil
        elseif d <= (bt.r + 1.3) ^ 2 then
          rim = true
        end
      end
    end
    if rim then
      return { 0.34, 0.26, 0.2 } -- a dark edge where it broke
    end
    local yellow = 0.6 + 0.4 * w.tint
    if state == 1 then
      return { c[1] * 0.97, c[2] * 0.95, c[3] * (1 - 0.1 * yellow) }
    end
    return { c[1] * 0.92, c[2] * 0.84, c[3] * (1 - 0.4 * yellow) }
  end

  local tusksD, stumpsD, boxes = {}, {}, {}
  for i = 1, #TUSKS do
    tusksD[i] = { [0] = love.image.newImageData(W, H), [1] = love.image.newImageData(W, H), [2] = love.image.newImageData(W, H) }
    stumpsD[i] = love.image.newImageData(W, H)
    boxes[i] = { math.huge, math.huge, -math.huge, -math.huge }
  end
  local function put(d, x, y, c)
    d:setPixel(mx(x), y, c[1], c[2], c[3], 1)
  end
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local id = map[y][x]
      if id >= ID.FANG and id < ID.GUM then
        local i = id - ID.FANG + 1
        local c = colour(x, y, id)
        put(tusksD[i][0], x, y, c)
        local e = tuskEnds[id]
        local along = (y - e[1]) / (e[2] - e[1])
        local span = fspan[id .. ":" .. y]
        local fx = span and span[2] > span[1] and (x - span[1]) / (span[2] - span[1]) or 0.5
        local width = span and (span[2] - span[1] + 1) or 4
        for state = 1, 2 do
          local c2 = damaged(state, i, id, x, y, c)
          if c2 then
            put(tusksD[i][state], x, y, c2)
          end
        end
        local cut = 0.3 + 0.06 * math.sin(x * 1.9)
        if along < cut then
          put(stumpsD[i], x, y, along > cut - 0.06 and { 0.42, 0.36, 0.32 } or c)
        end
        local bx = boxes[i]
        bx[1], bx[2], bx[3], bx[4] = math.min(bx[1], mx(x)), math.min(bx[2], y), math.max(bx[3], mx(x) + 1), math.max(bx[4], y + 1)
        if under[y][x] == ID.GUM then
          put(i <= 2 and LD.body or LD.jaw, x, y, colour(x, y, ID.GUM))
        end
      elseif id ~= 0 and id ~= ID.CAV then
        local layer = inJaw(x, y, id) and "jaw" or (layerOf[id] or "body")
        put(LD[layer], x, y, colour(x, y, id))
      end
    end
  end

  -- the throat, in frames that loop: the ridges fall steadily inward
  local FRAMES = 12
  local tx0, ty0, tx1, ty1 = math.huge, math.huge, -math.huge, -math.huge
  for _, p in ipairs(tlist) do
    tx0, ty0, tx1, ty1 = math.min(tx0, mx(p[1])), math.min(ty0, p[2]), math.max(tx1, mx(p[1])), math.max(ty1, p[2])
  end
  local throatImgs = {}
  for f = 0, FRAMES - 1 do
    local d = love.image.newImageData(tx1 - tx0 + 1, ty1 - ty0 + 1)
    for _, p in ipairs(tlist) do
      local c = throatColour(p[1], p[2], f / FRAMES)
      d:setPixel(mx(p[1]) - tx0, p[2] - ty0, c[1], c[2], c[3], 1)
    end
    throatImgs[f + 1] = d
  end

  -- the body's box (what a shot or the hunter collides with), in the picture's pixels
  local body = { math.huge, math.huge, -math.huge, -math.huge }
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if sil[y][x] then
        body[1], body[2] = math.min(body[1], mx(x)), math.min(body[2], y)
        body[3], body[4] = math.max(body[3], mx(x) + 1), math.max(body[4], y + 1)
      end
    end
  end

  local function image(d)
    local img = love.graphics.newImage(d)
    img:setFilter("nearest", "nearest")
    return img
  end
  local function white(d)
    local w = d:clone()
    w:mapPixel(function(_, _, r, g, b, a)
      if a > 0 then
        return 1, 1, 1, a
      end
      return r, g, b, a
    end)
    return image(w)
  end
  local art = { W = W, H = H, layers = {}, tusks = {}, stumps = {}, boxes = boxes, body = body, throat = { x = tx0, y = ty0, frames = {} } }
  for _, n in ipairs(LAYERS) do
    art.layers[n] = { img = image(LD[n]), flash = white(LD[n]) }
  end
  for i = 1, #TUSKS do
    local t = { imgs = {}, flashes = {}, masks = {} }
    for st = 0, 2 do
      t.imgs[st], t.flashes[st], t.masks[st] = image(tusksD[i][st]), white(tusksD[i][st]), tusksD[i][st]
    end
    art.tusks[i] = t
    art.stumps[i] = image(stumpsD[i])
  end
  for f = 1, FRAMES do
    art.throat.frames[f] = image(throatImgs[f])
  end
  art.throat.flash = white(throatImgs[1])
  -- where things hang from, in the (mirrored) picture's pixels
  art.hingeX = mx(hingeX)
  art.mouth = { mx(tcx), tcy } -- the centre of the throat
  local mfx, mfy = R(332, 286)
  art.mouthFront = { mx(mfx), mfy } -- the middle of the mouth's opening
  art.dorsRoot = select(2, R(0, 150))
  art.pelvRoot = select(2, R(0, 400))
  art.lureRoot = select(2, R(0, 94))
  art.waveEnd = art.hingeX
  art.glows = {}
  for _, g in ipairs(glows) do
    art.glows[#art.glows + 1] = { x = mx(g.x), y = g.y, r = g.r, kind = g.kind, layer = g.layer }
  end
  return art
end

-- Animation ---------------------------------------------------------------------------------
-- Everything moves in whole pixels, in strips: the body's tail sweeps in a slow wave, the fins
-- flap, the lure bobs on its stalk, the jaw opens a little and the throat falls inward.

local function clamp(v, a, b)
  return math.max(a, math.min(b, v))
end

local function round(v)
  return math.floor(v + 0.5)
end

-- the body's wave: nothing at the head, most at the tail
local function bodyDy(art, t, x)
  local f = clamp((art.waveEnd - x) / art.waveEnd, 0, 1)
  return round(13 * f ^ 1.5 * math.sin(t * 2.3 + x * 0.008))
end

local function finDx(art, t, y, root, dir, amp, speed)
  local f = clamp((root - y) * dir / 120, 0, 1)
  return round(amp * f * math.sin(t * speed - y * 0.02))
end

local function jawOpen(t)
  return 0.022 + 0.022 * math.sin(t * 1.1)
end

-- how far the lower jaw has dropped at picture column x
function anglerart.jawDy(art, t, x)
  return math.max(0, round(jawOpen(t) * (x - art.hingeX)))
end

local function lureBob(t)
  return round(2.5 * math.sin(t * 1.6))
end

local Q
local function quad()
  if not Q then
    Q = love.graphics.newQuad(0, 0, 1, 1, 1, 1)
  end
  return Q
end

-- draws a layer in runs of columns, each moved down by dyOf(x)
local function drawCols(img, art, dyOf, ox, oy)
  local q = quad()
  local W, H = art.W, art.H
  local x0, d0 = 0, dyOf(0)
  for x = 1, W do
    local d = x < W and dyOf(x) or nil
    if d ~= d0 then
      q:setViewport(x0, 0, x - x0, H, W, H)
      love.graphics.draw(img, q, ox + x0, oy + d0)
      x0, d0 = x, d
    end
  end
end

-- draws a layer in runs of rows, each moved right by dxOf(y)
local function drawRows(img, art, dxOf, ox, oy)
  local q = quad()
  local W, H = art.W, art.H
  local y0, d0 = 0, dxOf(0)
  for y = 1, H do
    local d = y < H and dxOf(y) or nil
    if d ~= d0 then
      q:setViewport(0, y0, W, y - y0, W, H)
      love.graphics.draw(img, q, ox + d0, oy + y0)
      y0, d0 = y, d
    end
  end
end

-- Draws the whole fish facing right, its body's box centred on the origin.
-- teeth[i] is false for a tusk that has been broken off.
function anglerart.draw(art, t, flash, teeth, alpha, states)
  local bd = art.body
  local ox, oy = -round((bd[1] + bd[3]) / 2), -round((bd[2] + bd[4]) / 2)
  local L = art.layers
  local function img(name)
    return flash and L[name].flash or L[name].img
  end
  love.graphics.setColor(1, 1, 1, alpha or 1)

  local dorsC = round(art.W * 0.40)
  local pelvC = round(art.W * 0.30)
  -- far fins, then the tail
  drawRows(img("pelv"), art, function(y) return finDx(art, t, y, art.pelvRoot, -1, 6, 1.5) end, ox, oy + bodyDy(art, t, pelvC))
  drawRows(img("dors"), art, function(y) return finDx(art, t, y, art.dorsRoot, 1, -7, 1.9) end, ox, oy + bodyDy(art, t, dorsC))
  drawCols(img("tail"), art, function(x) return bodyDy(art, t, x) + round(3 * math.sin(t * 3 - x * 0.05)) end, ox, oy)
  -- the throat, then the body over it
  if not flash then
    local frames = art.throat.frames
    local f = frames[math.floor(t * 0.9 * #frames) % #frames + 1]
    love.graphics.draw(f, ox + art.throat.x, oy + art.throat.y)
  else
    love.graphics.draw(art.throat.flash, ox + art.throat.x, oy + art.throat.y)
  end
  drawCols(img("body"), art, function(x) return bodyDy(art, t, x) end, ox, oy)
  -- the lower jaw, and its tusks, drop together
  local function jdy(x)
    return anglerart.jawDy(art, t, x)
  end
  drawCols(img("jaw"), art, jdy, ox, oy)
  for i = 1, #art.tusks do
    local lower = i >= 3
    local piece
    if not teeth or teeth[i] then
      local st = states and states[i] or 0
      piece = flash and art.tusks[i].flashes[st] or art.tusks[i].imgs[st]
    else
      piece = art.stumps[i]
    end
    if lower then
      drawCols(piece, art, jdy, ox, oy)
    else
      love.graphics.draw(piece, ox, oy)
    end
  end
  -- the near fin, and the lure over everything
  drawCols(img("pec"), art, function(x)
    local f = clamp((art.W * 0.52 - x) / (art.W * 0.2), 0, 1)
    return bodyDy(art, t, x) + round(6 * f * math.sin(t * 2.6 - x * 0.02))
  end, ox, oy)
  drawRows(img("lure"), art, function(y) return finDx(art, t, y, art.lureRoot, 1, -9, 1.3) end, ox, oy + lureBob(t))
end

-- Is the picture's pixel (ax, ay) inside tusk i (in its damage state)? Shrunk by a pixel, so a
-- shot has to be on the tusk itself and not just near it.
function anglerart.tuskHit(art, i, state, ax, ay)
  local d = art.tusks[i].masks[state or 0]
  local x, y = math.floor(ax), math.floor(ay)
  local W, H = art.W, art.H
  local function solid(px, py)
    if px < 0 or py < 0 or px >= W or py >= H then
      return false
    end
    local _, _, _, a = d:getPixel(px, py)
    return a > 0
  end
  return solid(x, y) and solid(x - 1, y) and solid(x + 1, y) and solid(x, y - 1) and solid(x, y + 1)
end

-- The lights to place in the world, in pixels from the body box's centre (head toward +x):
-- the lure, the eye and the glowing tips, each where its part is right now
function anglerart.lights(art, t)
  local bd = art.body
  local cx, cy = (bd[1] + bd[3]) / 2, (bd[2] + bd[4]) / 2
  local out = {}
  for _, g in ipairs(art.glows) do
    local x, y = g.x, g.y
    if g.layer == "dors" then
      x, y = x + finDx(art, t, y, art.dorsRoot, 1, -7, 1.9), y + bodyDy(art, t, art.W * 0.40)
    elseif g.layer == "pelv" then
      x, y = x + finDx(art, t, y, art.pelvRoot, -1, 6, 1.5), y + bodyDy(art, t, art.W * 0.30)
    elseif g.layer == "pec" then
      local f = clamp((art.W * 0.52 - x) / (art.W * 0.2), 0, 1)
      y = y + bodyDy(art, t, x) + round(6 * f * math.sin(t * 2.6 - x * 0.02))
    elseif g.layer == "lure" then
      x, y = x + finDx(art, t, y, art.lureRoot, 1, -9, 1.3), y + lureBob(t)
    end
    out[#out + 1] = { x = x - cx, y = y - cy, kind = g.kind }
  end
  return out
end

return anglerart
