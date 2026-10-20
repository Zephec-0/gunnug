-- The Marble Colossus's figure: a body of floating ore, drawn on the 1:1 pixel grid.
--
-- Every part is its own lump of marble (rocks, with gaps and gold beads at the joints), seen three-
-- quarters on, facing right. The figure is drawn into a canvas frame (fig.W x fig.H, feet at
-- (fig.CX, fig.G)) with one-pixel detail everywhere, then outlined by src.colossus (outlineShader).
--
-- A pose table p drives it (all optional):
--   drop, lean, bob      body lowered / leaned (px) / raised
--   nf, ff               near / far foot {x offset, lift}
--   nfist, ffist         near / far fist offset from rest {x, y}
--   hx, hy, jaw          head offset, jaw opening
--   open                 claws spread
--   charge               0..1 eye charge; dead = eye dark; flare = extra halo
--   spread               0..1 how far the ore has drifted apart (waking / breaking / after a slam)
--   stretch              px the parts lag each other vertically (a leap: the head leads, the legs trail)
--   slim                 0..1 pulling in (arms, shards, chest) before the shell forms
--   ball                 0..1 a ball of ore gathering above the near fist (the rock throw)
--   tuck                 0..1 everything loose pulled in close (sealed in the gem)
--   mass                 0..1 ore piling onto the fists (the stomp): they swell and gather chunks
--   trail                {{x, y}, ...} where the near fist was a few frames ago (motion ghosts)
--   t                    animation time, for the little bobs
local fig = {}

fig.W, fig.H = 200, 260
fig.CX, fig.G = 90, 246
local CX, G = fig.CX, fig.G

local C = {
  light = { 1.0, 0.97, 0.90 }, mid = { 0.90, 0.82, 0.68 }, dark = { 0.68, 0.56, 0.42 }, deep = { 0.42, 0.32, 0.24 },
  ink = { 0.13, 0.08, 0.08 },
  rust = { 0.82, 0.42, 0.16 }, rustL = { 0.96, 0.58, 0.24 }, rustD = { 0.55, 0.27, 0.11 },
  gold = { 1.0, 0.80, 0.30 }, goldD = { 0.74, 0.52, 0.18 }, glow = { 1.0, 0.58, 0.18 }, hot = { 1.0, 0.96, 0.72 },
  eye = { 0.10, 0.06, 0.10 },
}
fig.colors = C
local FAR = { C.mid, C.dark, C.deep, C.deep } -- the far side sits in shade
local NEAR = { C.light, C.mid, C.dark, C.deep }

local gfx = love.graphics
local floor, sin, cos, min, max = math.floor, math.sin, math.cos, math.min, math.max

local alphaMul = 1 -- (ghosts and fading motes are drawn through this)
local function col(c, a)
  gfx.setColor(c[1], c[2], c[3], (a or 1) * alphaMul)
end
local function R(c, x, y, w, h)
  if w <= 0 or h <= 0 then
    return
  end
  col(c)
  gfx.rectangle("fill", floor(x), floor(y), floor(w), floor(h))
end
local function px(c, x, y)
  R(c, x, y, 1, 1)
end
local function line(c, x0, y0, x1, y1)
  x0, y0, x1, y1 = floor(x0), floor(y0), floor(x1), floor(y1)
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    px(c, x0, y0)
    if x0 == x1 and y0 == y1 then
      break
    end
    local e2 = 2 * err
    if e2 >= dy then
      err = err + dy
      x0 = x0 + sx
    end
    if e2 <= dx then
      err = err + dx
      y0 = y0 + sy
    end
  end
end
local function hash(x, y, s)
  local n = sin(x * 127.1 + y * 311.7 + (s or 0) * 74.7) * 43758.5453
  return n - floor(n)
end
fig.hash = hash
local function ease(k)
  k = max(0, min(1, k))
  return k * k * (3 - 2 * k)
end

-- A broken lump of marble: irregular silhouette, lit from the upper left.
-- o.bite = { rows, inset } takes a chunk out of the top-left; o.shift = { rows, dx } slides the top rows;
-- o.taper narrows both sides by up to that many px towards the bottom.
local function rock(x, y, w, h, seed, tone, o)
  tone, o = tone or NEAR, o or {}
  x, y = floor(x), floor(y)
  for r = 0, h - 1 do
    local base = 0
    if r < 2 then
      base = 2 - r
    elseif r >= h - 2 then
      base = r - (h - 3)
    end
    local rr = floor(r / 3)
    local jl = floor(hash(seed, rr, 1) * 2.4)
    local jr = floor(hash(seed, rr, 2) * 2.4)
    local bl = (o.bite and r < o.bite[1]) and o.bite[2] or 0
    local sh = (o.shift and r < o.shift[1]) and o.shift[2] or 0
    local tp = o.taper and floor(o.taper * r / max(1, h - 1)) or 0
    local x0, x1 = x + base + jl + bl + sh + tp, x + w - base - jr + sh - tp
    if x1 > x0 then
      local c = tone[2]
      if r < 2 then
        c = tone[1]
      elseif r >= h - 2 then
        c = tone[4]
      elseif r >= h - 4 then
        c = tone[3]
      end
      R(c, x0, y + r, x1 - x0, 1)
      if r >= 2 and r < h - 2 then
        R(tone[1], x0, y + r, min(2, x1 - x0), 1)
        R(tone[3], x1 - 3, y + r, 3, 1)
        R(tone[4], x1 - 1, y + r, 1, 1)
      end
    end
  end
  for i = 1, floor(w * h / 70) do
    local sx, sy = x + 3 + floor(hash(i, w, seed) * max(1, w - 7)), y + 3 + floor(hash(h, i, seed) * max(1, h - 7))
    px(hash(sy, sx, i) > 0.5 and tone[1] or tone[3], sx, sy)
  end
end
-- A soft radial glow, for the emissive pass (drawn additively where the game lights its glows)
local glowImg
function fig.glow(x, y, r, cr, cg, cb, a)
  if not glowImg then
    local n = 64
    local d = love.image.newImageData(n, n)
    for j = 0, n - 1 do
      for i = 0, n - 1 do
        local dx, dy = (i + 0.5 - n / 2) / (n / 2), (j + 0.5 - n / 2) / (n / 2)
        local v = max(0, 1 - math.sqrt(dx * dx + dy * dy))
        d:setPixel(i, j, 1, 1, 1, v * v * (3 - 2 * v))
      end
    end
    glowImg = gfx.newImage(d)
    glowImg:setFilter("linear", "linear")
  end
  gfx.setColor(cr, cg, cb, a)
  gfx.draw(glowImg, x, y, 0, r / 32, r / 32, 32, 32)
end

-- A soft disc made of stepped ellipses of rows (pixel-clean, for inside the figure's canvas)
local function softGlow(cx, cy, r, a)
  for i = 5, 1, -1 do
    local rr = r * i / 5
    gfx.setColor(C.glow[1], C.glow[2], C.glow[3], a * (6 - i) / 5 * 0.45)
    for dy = -floor(rr), floor(rr) do
      local w = floor(math.sqrt(max(0, 1 - (dy / max(1, rr)) ^ 2)) * rr)
      gfx.rectangle("fill", floor(cx - w), floor(cy + dy), w * 2 + 1, 1)
    end
  end
end

local function bead(x, y)
  R(C.goldD, x - 1, y - 1, 3, 3)
  px(C.gold, x - 1, y - 1)
  px(C.hot, x, y)
end
local function mote(x, y, big, a)
  local old = alphaMul
  alphaMul = alphaMul * (a or 1)
  if big then
    R(C.gold, x, y, 2, 2)
    px(C.hot, x, y)
  else
    px(C.gold, x, y)
  end
  alphaMul = old
end
local function crack(pts, glow)
  for i = 1, #pts - 2, 2 do
    line(C.deep, pts[i], pts[i + 1], pts[i + 2], pts[i + 3])
    line(glow and C.glow or C.gold, pts[i] + 1, pts[i + 1], pts[i + 2] + 1, pts[i + 3])
  end
end

-- A free-floating crystal shard from (x, y) pointing along ang degrees (0 = right, -90 = up)
local function shard(x, y, len, w, ang, body, lit)
  body, lit = body or C.rust, lit or C.rustL
  local a = math.rad(ang)
  local dx, dy = cos(a), sin(a)
  local nx, ny = -dy, dx
  local function pt(t, s)
    return floor(x + dx * len * t + nx * w * s * 0.5 + 0.5), floor(y + dy * len * t + ny * w * s * 0.5 + 0.5)
  end
  local tipx, tipy = pt(1, 0)
  local mx1, my1 = pt(0.35, 1)
  local mx2, my2 = pt(0.35, -1)
  local tx, ty = pt(-0.1, 0)
  col(body)
  gfx.polygon("fill", tipx, tipy, mx1, my1, tx, ty, mx2, my2)
  local litA, litB = (ny < 0) and { mx1, my1 } or { mx2, my2 }, (ny < 0) and { mx2, my2 } or { mx1, my1 }
  col(lit)
  gfx.polygon("fill", tipx, tipy, litA[1], litA[2], tx, ty)
  px(C.hot, tipx, tipy)
  px(C.rustD, litB[1], litB[2])
end

-- A limb of floating ore: lumps along a drooping line with gold beads at the seams, ending in a fist
local function arm(sx, sy, fx, fy, seed, tone, p, scale)
  scale = scale or 1
  local t, spread = p.t or 0, p.spread or 0
  local dist = math.sqrt((fx - sx) ^ 2 + (fy - sy) ^ 2)
  local n = max(2, floor(dist / 15))
  local sag = min(10, dist * 0.18)
  local prev = { sx, sy }
  for i = 1, n do
    local u = i / (n + 1)
    local cx = sx + (fx - sx) * u + (hash(seed, i, 3) - 0.5) * spread * 16
    local cy = sy + (fy - sy) * u + sin(u * math.pi) * sag + sin(t * 1.3 + i * 1.7 + seed) * 1.2 + (hash(seed, i, 4) - 0.5) * spread * 14
    local w = floor((13 - 3 * (i - 1) / n) * scale)
    local h = floor((11 - 2 * (i - 1) / n) * scale)
    rock(cx - w / 2, cy - h / 2, w, h, seed + i, tone)
    bead((prev[1] + cx) / 2, (prev[2] + cy) / 2)
    prev = { cx, cy }
  end
  bead((prev[1] + fx) / 2, (prev[2] + fy) / 2)
  local mass = p.mass or 0
  local fs = 1 + mass * 0.9
  local w, h = floor(17 * scale * fs), floor(15 * scale * fs)
  rock(fx - w / 2, fy - h / 2, w, h, seed + 50, tone)
  if mass > 0.05 then
    -- ore piling on: chunks stuck round the fist, a heavier lump the longer it is held
    for i = 1, 8 do
      local ang = i / 8 * 6.283 + hash(seed, i, 9) * 0.8
      local rr = w / 2 + 1 + hash(seed, i, 8) * 3
      local sz = floor((4 + hash(seed, i, 7) * 5) * (0.35 + 0.65 * mass))
      if sz >= 3 then
        rock(fx + cos(ang) * rr - sz / 2, fy + sin(ang) * rr * 0.9 - sz / 2, sz, sz, seed + 90 + i, tone)
      end
    end
    R(C.goldD, fx - w / 2 + 2, fy + h / 2 - 3, w - 4, 1)
  end
  R(C.gold, fx - w / 2 + 1, fy - 1, w - 2, 2)
  R(C.goldD, fx - w / 2 + 1, fy + 1, w - 2, 1)
  for k = 0, 2 do
    local ky = fy - h / 2 + 1 + k * 5
    local ext = p.open and 6 or 3
    shard(fx + w / 2 - 2, ky + 2, ext + 5, 4, k * 8 - 8 + (p.open and 0 or 6), C.rust, C.rustL)
  end
  rock(fx - w / 2 - 6, fy - h / 2 - 5 + floor(sin(t * 2 + seed) * 1.5), 6, 5, seed + 70, tone) -- a chip circling the knuckles
  local fade = math.sin((t * 0.35 + seed * 0.37) * math.pi) ^ 2
  mote(fx + 2, fy - h / 2 - 5, true, fade * 0.8)
end

-- A leg in floating pieces: thigh, knee plate, shin and a wedge of a foot; pieces shorten as the leg folds
local function leg(hx, hy, fx, fy, seed, tone, spread)
  spread = spread or 0
  local function jx(k) return floor((hash(seed, k, 1) - 0.5) * spread * 18) end
  local function jy(k) return floor((hash(seed, k, 2) - 0.3) * spread * 10) end
  local lift = (G - 8) - fy
  local L = math.sqrt((fx - hx) ^ 2 + (fy - hy) ^ 2)
  local bend = max(0, 54 - L)
  local kx, ky = (hx + fx) / 2 + 5 + lift * 0.4 + bend * 0.55, (hy + fy) / 2 - bend * 0.15
  local tx, ty = (hx + kx) / 2, (hy + ky) / 2
  local sx, sy = (kx + fx) / 2, (ky + fy) / 2
  local h1 = max(10, min(24, floor(math.sqrt((kx - hx) ^ 2 + (ky - hy) ^ 2)) + 1))
  local h2 = max(10, min(24, floor(math.sqrt((fx - kx) ^ 2 + (fy - ky) ^ 2)) + 1))
  rock(sx - 6 + jx(1), sy - h2 / 2 + jy(1), 12, h2, seed + 1, tone, { taper = 2 }) -- shin
  R(C.goldD, sx - 5 + jx(1), sy + h2 / 2 - 6 + jy(1), 10, 1)
  rock(tx - 8 + jx(2), ty - h1 / 2 + jy(2), 16, h1, seed, tone, { taper = 3 }) -- thigh, heavy at the top
  R(C.gold, tx - 7 + jx(2), ty + h1 / 2 - 5 + jy(2), 14, 1)
  rock(kx - 1 + jx(3), ky - 5 + jy(3), 9, 8, seed + 3, tone) -- knee plate
  if spread < 0.3 then bead(kx + 1, ky + 3) end
  rock(fx - 6 + jx(4), fy - 1, 21, 9, seed + 2, { tone[2], tone[3], tone[4], C.ink }, { taper = 1 }) -- the foot
end

-- The drifting shards: { dx, dy, length, width, angle, glowing } around the body
local SHARDS_BACK = {
  { -40, -56, 20, 6, -125, true }, { -34, -34, 16, 5, -150, false }, { -30, -4, 12, 4, 172, false },
  { -52, -22, 9, 3, -170, true },
}
local SHARDS_FRONT = {
  { 36, -78, 14, 5, -72, false }, { 52, -48, 10, 3, -22, true }, { -26, 6, 9, 3, 205, false },
}
local function drawShards(list, p, cx, ty)
  local spread = p.spread or 0
  for i, s in ipairs(list) do
    local fan = (p.open and 1.25 or 1) + spread * 0.5
    local wob = sin((p.t or 0) * 1.2 + i * 2.1) * 2
    local pull = max(0.12, 1 - 0.6 * (p.slim or 0) - 0.3 * (p.tuck or 0))
    local sx = cx + s[1] * fan * pull - (p.lean or 0) * 0.6
    local sy = ty + 40 + s[2] * pull + wob + (p.charge and p.charge > 0 and -4 or 0) - (p.bob or 0) + (p.drop or 0) * 0.5 - spread * 14
    shard(sx, sy, s[3], s[4], s[5], s[6] and C.glow or C.rust, s[6] and C.hot or C.rustL)
  end
end

-- Where the head and eye are, relative to (CX, G), for a pose (the beam starts at the eye)
function fig.eyeOffset(p)
  local drop, lean, bob = p.drop or 0, p.lean or 0, p.bob or 0
  local hx = 8 + lean + (p.hx or 0)
  local hy = -144 + drop + (p.hy or 0) - bob + floor(sin((p.t or 0) * 1.5)) - floor((p.spread or 0) * 10) - floor(p.stretch or 0)
  return hx + 7, hy - 1, hx, hy
end

-- Where the gathering ball of ore hangs, relative to (CX, G): above the near fist
function fig.ballOffset(p)
  local nfist = p.nfist or { 0, 0 }
  return -28 + nfist[1] - 6, -58 + nfist[2] + (p.drop or 0) - 22
end

-- Draws the figure. Returns the eye's canvas position.
function fig.draw(p)
  local drop, lean, bob = p.drop or 0, p.lean or 0, p.bob or 0
  local cx = CX
  local hipY = G - 64 + drop - bob
  local nf, ff = p.nf or { 0, 0 }, p.ff or { 0, 0 }
  local so = p.stretch or 0 -- parts lag each other: the head leads, the legs trail
  local spread = p.spread or 0
  local slim = p.slim or 0
  local ty = hipY - 52 - floor(so * 0.65) -- top of the chest
  local legHip = hipY - floor(so * 0.25)
  drawShards(SHARDS_BACK, p, cx, ty)
  -- far arm (behind the chest), in shade
  local ffist = p.ffist or { 0, 0 }
  arm(cx + 20 + lean, ty + 10, cx + 34 + ffist[1], G - 54 + ffist[2] + drop, 20, FAR, p, 0.9)
  -- legs: far first, then near
  leg(cx + 6, legHip, cx + ff[1] + 6, G - 8 - ff[2], 30, FAR, spread)
  leg(cx - 4, legHip, cx + nf[1] - 4, G - 8 - nf[2], 40, NEAR, spread)
  -- pelvis, floating a hair under the chest
  local py = hipY - 10 + floor(spread * 5) - floor(so * 0.45)
  rock(cx - 10 + lean * 0.4, py, 28, 11, 60, NEAR)
  R(C.gold, cx - 6 + lean * 0.4, py + 5, 20, 2)
  -- chest, turned three-quarters: a lit side plane on the left and a shaded front plane on the right
  local th = 40
  for r = 0, th - 1 do
    local half = 18 - floor(r * 0.16) - floor(slim * 4)
    local lower = r >= floor(th / 2)
    local yo = lower and floor(spread * 7) or 0 -- broken across the middle when the ore comes apart
    local xo = lower and floor(spread * 4) or 0
    local x0 = cx - half + lean * (1 - r / th) + 5 + xo
    local chip = (r > 12 and r < 22) and 4 or 0
    local w = half * 2 - chip
    local xb = x0 + floor(half * 0.8) -- the edge between the planes
    local top, bot = r < 2, r > th - 3
    R(top and C.light or (bot and C.deep or C.mid), x0, ty + r + yo, xb - x0, 1)
    R(top and C.mid or (bot and C.deep or C.dark), xb, ty + r + yo, w - (xb - x0), 1)
    if r >= 2 and not bot then
      R(C.light, x0, ty + r + yo, 2, 1)
      R(C.light, xb - 1, ty + r + yo, 1, 1) -- the bevelled edge catches the light
      R(C.deep, x0 + w - 3, ty + r + yo, 3, 1)
    end
  end
  for i = 1, 24 do
    px(hash(i, 5, 4) > 0.5 and C.light or C.dark, cx - 12 + floor(hash(i, 3, 1) * 30) + lean + 5, ty + 4 + floor(hash(i, 9, 2) * 33))
  end
  crack({ cx + 7 + lean, ty + 3, cx + 11 + lean, ty + 13, cx + 5 + lean, ty + 23, cx + 10 + lean, ty + 35 })
  crack({ cx - 5 + lean, ty + 20, cx - 9 + lean, ty + 28, cx - 4 + lean, ty + 36 }, true)
  R(C.gold, cx + 11 + lean, ty + 11, 7, 7)
  R(C.hot, cx + 14 + lean, ty + 14, 2, 2) -- the heart stone, in the dark plane so it reads
  -- shoulder pads: the far one small and in shade, the near one big
  rock(cx + 15 + lean - floor(slim * 4), ty - 3 - floor(spread * 4), 12, 11, 70, FAR)
  rock(cx - 17 + lean + floor(slim * 4), ty - 5 - floor(spread * 3), 18, 14, 80, NEAR)
  -- near arm over the chest
  local nfist = p.nfist or { 0, 0 }
  arm(cx - 18 + lean, ty + 8, cx - 28 + nfist[1], G - 58 + nfist[2] + drop, 10, NEAR, p, 1)
  -- a ball of ore gathering out of thin air above the near fist
  if (p.ball or 0) > 0 then
    local k = p.ball
    local ox, oy = fig.ballOffset(p)
    local bx, by = cx + ox, G + oy
    local r = 2 + floor(k * 9)
    for i = 1, 18 do
      local a = (i / 18) * 6.283 + (p.t or 0) * (2.5 + (i % 3)) + i
      local reach = 46 + hash(i, 1, 1) * 40
      local dist = (1 - k) * reach + r + 3
      local cxp, cyp = bx + cos(a) * dist, by + sin(a) * dist * 0.8
      local sz = 4 + (i % 3)
      -- a streak of gold behind each chip, the way it came in
      for j = 1, 3 do
        local tx2 = bx + cos(a - j * 0.2) * (dist + 10 * j)
        local ty2 = by + sin(a - j * 0.2) * (dist + 10 * j) * 0.8
        mote(tx2, ty2, j == 1, (0.9 - j * 0.24) * (1 - k * 0.6))
      end
      rock(cxp - sz / 2, cyp - sz / 2, sz, sz, 200 + i, NEAR)
    end
    rock(bx - r, by - r, r * 2, r * 2, 300, NEAR)
    R(C.goldD, bx - r + 2, by, r * 2 - 4, 1)
    if r > 5 then
      crack({ bx - 2, by - r + 2, bx + 1, by, bx - 1, by + r - 2 }, true)
    end
  end
  -- head: a crystal shard, tilted and lopsided, floating on its own (no mouth)
  local ex, ey, hxo, hyo = fig.eyeOffset(p)
  local hx, hy = cx + hxo, G + hyo
  local lit, face, core, coreR, edge = C.glow, C.rust, C.gold, C.rustL, C.rustD
  if p.dead then
    lit, face, core, coreR, edge = C.dark, C.deep, C.mid, C.dark, C.ink
  end
  local function pt(dx, dy) return hx + dx, hy + dy end
  local Tx, Ty = pt(4, -20)
  local L1x, L1y = pt(-9, -7)
  local L2x, L2y = pt(-8, 10)
  local Bx, By = pt(-1, 17)
  local R1x, R1y = pt(12, -9)
  local R2x, R2y = pt(11, 8)
  col(lit)
  gfx.polygon("fill", Tx, Ty, L1x, L1y, L2x, L2y, Bx, By)
  col(face)
  gfx.polygon("fill", Tx, Ty, R1x, R1y, R2x, R2y, Bx, By)
  col(core) -- the bright heart of each face
  gfx.polygon("fill", hx + 3, hy - 14, hx - 4, hy - 6, hx - 4, hy + 6, hx - 1, hy + 11)
  col(coreR)
  gfx.polygon("fill", hx + 5, hy - 13, hx + 9, hy - 7, hx + 8, hy + 3, hx + 3, hy + 8)
  col(edge) -- the lower facets, in shade
  gfx.polygon("fill", L2x, L2y, Bx, By, hx + 2, hy + 7)
  gfx.polygon("fill", Bx, By, R2x, R2y, hx + 2, hy + 7)
  line(p.dead and C.dark or C.hot, Tx, Ty + 1, hx + 1, hy + 14) -- the ridge catches the light
  line(C.deep, L1x, L1y, hx + 3, hy - 3) -- a facet line across the left face
  local tk = p.tuck or 0
  shard(hx - 15 + 9 * tk, hy - 11 + 6 * tk, 9 - 3 * tk, 3, -155, C.rust, C.rustL) -- a chip drifting off
  p.eyeX, p.eyeY = cx + ex, G + ey
  if not p.dead then
    local s = 5 + floor((p.charge or 0) * 5) + floor((p.flare or 0) * 5)
    softGlow(p.eyeX, p.eyeY, s, 1)
    R(C.eye, p.eyeX - 2, p.eyeY - 3, 5, 7) -- a slit cut into the face...
    R(C.gold, p.eyeX - 1, p.eyeY - 2, 3, 5) -- ...burning
    R(C.hot, p.eyeX, p.eyeY - 1, 1, 3)
  else
    R(C.ink, p.eyeX - 1, p.eyeY - 2, 3, 5)
  end
  -- stray shards near the head: one long and swept back, one stump
  shard(hx - 14 + 10 * tk, hy - 16 + 9 * tk, 22 - 8 * tk, 6, -128, C.glow, C.hot)
  shard(hx + 16 - 10 * tk, hy - 16 + 8 * tk, 10 - 3 * tk, 4, -60, C.rust, C.rustL)
  drawShards(SHARDS_FRONT, p, cx, ty)
  -- motes drifting along the seams (more when the ore has come apart)
  -- Each one lives for several seconds in one place: it fades up, drifts a few pixels upward, fades out,
  -- and the next cycle begins somewhere else.
  for i = 1, 6 + floor(spread * 8) do
    local period = 4 + hash(i, 1, 1) * 4
    local ph = (p.t or 0) / period + hash(i, 2, 2)
    local cyc = floor(ph)
    local f = ph - cyc
    local a = sin(f * math.pi) ^ 2
    local mx = cx - 34 * (1 - 0.6 * (p.tuck or 0)) + floor(hash(i, cyc, 3) * 80 * (1 - 0.6 * (p.tuck or 0)))
    local my = ty + 6 + floor(hash(i, cyc, 5) * 62) - floor(f * 8)
    mote(mx, my, i % 3 == 0, a * 0.85)
  end
  return p.eyeX, p.eyeY
end

-- The crystal shell it kneels in. g (0..1) is how far it has grown: first seed crystals sprout from
-- inside the body and lengthen, then one great orange shard swells outward from the body's middle and
-- closes over it. Drawn over the outlined figure, in world pixels.
local function pixLine(x0, y0, x1, y1)
  local n = floor(max(math.abs(x1 - x0), math.abs(y1 - y0)))
  for k = 0, n do
    local u = k / max(1, n)
    gfx.rectangle("fill", floor(x0 + (x1 - x0) * u), floor(y0 + (y1 - y0) * u), 1, 1)
  end
end

local SHELL_SEEDS = { { -16, -20, -150 }, { -4, -40, -110 }, { 8, -34, -80 }, { 18, -18, -30 }, { -20, 0, -170 }, { 20, 6, 10 }, { 0, -52, -95 }, { -10, -46, -125 }, { 12, -44, -65 } }
-- The gem: a double-pointed hexagonal crystal, outer hexagon and a smaller inner one, so the bevelled faces read
-- (top and bottom points, two side faces) and the window in the middle shows what is sealed inside
local GEM_OUT = { { 0, -76 }, { -42, -37 }, { -42, 37 }, { 0, 76 }, { 42, 37 }, { 42, -37 } } -- T, UL, LL, B, LR, UR
local GEM_IN = { { 0, -50 }, { -23, -21 }, { -23, 21 }, { 0, 50 }, { 23, 21 }, { 23, -21 } }
fig.GEM_CY = -78 -- the gem's middle, above the body's ground point (the sealed pose is curled up around it)

function fig.shell(t, g)
  g = g == nil and 1 or g
  if g <= 0 then
    return
  end
  t = t or 0
  local mx, my = CX + 4, G + fig.GEM_CY
  local pulse = 0.8 + 0.2 * sin(t * 4)
  -- stage one: seed crystals sprouting from inside the body
  local s1 = ease(g / 0.5)
  for i, sd in ipairs(SHELL_SEEDS) do
    local len = (5 + hash(i, 2, 2) * 10) * s1 + 2
    local lg = i % 2 == 0
    shard(mx + sd[1] * (0.5 + 0.5 * s1), my + sd[2] * (0.5 + 0.5 * s1), len, 4 + (i % 3), sd[3], lg and C.glow or C.rust, lg and C.hot or C.rustL)
  end
  -- stage two: the gem swells out from the middle until it closes over everything
  local s2 = ease((g - 0.3) / 0.7)
  if s2 <= 0 then
    return
  end
  local function O(i)
    return mx + GEM_OUT[i][1] * s2, my + GEM_OUT[i][2] * s2
  end
  local function I(i)
    return mx + GEM_IN[i][1] * s2, my + GEM_IN[i][2] * s2
  end
  local function quad(c, a, i, j, k, l)
    gfx.setColor(c[1], c[2], c[3], a * pulse)
    local x1, y1 = O(i)
    local x2, y2 = O(j)
    local x3, y3 = I(k)
    local x4, y4 = I(l)
    gfx.polygon("fill", x1, y1, x2, y2, x3, y3, x4, y4)
  end
  -- bevelled faces: lit on the upper left, darker to the right and below (T=1 UL=2 LL=3 B=4 LR=5 UR=6)
  quad(C.hot, 0.62, 1, 2, 2, 1) -- top left
  quad(C.rustL, 0.58, 1, 6, 6, 1) -- top right
  quad(C.rustL, 0.56, 2, 3, 3, 2) -- left
  quad(C.rust, 0.62, 6, 5, 5, 6) -- right
  quad(C.rust, 0.64, 3, 4, 4, 3) -- bottom left
  quad(C.rustD, 0.68, 5, 4, 4, 5) -- bottom right
  -- the window: a faint orange glass over the body
  gfx.setColor(C.gold[1], C.gold[2], C.gold[3], 0.20 * pulse)
  local w = {}
  for i = 1, 6 do
    w[#w + 1], w[#w + 2] = I(i)
  end
  gfx.polygon("fill", w)
  -- crystal edges: bright on the outline and the window, fainter along the bevel joins
  gfx.setColor(1, 0.85, 0.5, 0.95)
  for i = 1, 6 do
    local x0, y0 = O(i)
    local x1, y1 = O(i % 6 + 1)
    pixLine(x0, y0, x1, y1)
  end
  gfx.setColor(1, 0.95, 0.75, 0.75)
  for i = 1, 6 do
    local x0, y0 = I(i)
    local x1, y1 = I(i % 6 + 1)
    pixLine(x0, y0, x1, y1)
  end
  gfx.setColor(1, 0.9, 0.6, 0.4)
  for i = 1, 6 do
    local x0, y0 = O(i)
    local x1, y1 = I(i)
    pixLine(x0, y0, x1, y1)
  end
  -- a glint sliding down the upper-left bevel
  local gx, gy = O(2)
  local tx, ty = O(1)
  local k = (sin(t * 1.7) + 1) / 2
  gfx.setColor(1, 1, 0.9, 0.9)
  gfx.rectangle("fill", floor(tx + (gx - tx) * k), floor(ty + (gy - ty) * k), 2, 2)
end

-- The gem's outer outline at growth g, as a flat polygon in canvas pixels (slightly inset): what is
-- sealed is clipped to it, so nothing pokes out
function fig.gemPoints(g)
  local s2 = ease((g - 0.3) / 0.7) * 0.96
  local mx, my = CX + 4, G + fig.GEM_CY
  local pts = {}
  for i = 1, 6 do
    pts[#pts + 1] = mx + GEM_OUT[i][1] * s2
    pts[#pts + 1] = my + GEM_OUT[i][2] * s2
  end
  return pts
end

-- Light blockers for the shadow pass: soft partial rectangles for the chest, pelvis, legs, head and fists,
-- following the pose (the light slips between the legs, past the arms and under the hovering gem).
-- { x, y, w, h, alpha } in canvas pixels, for a figure facing right.
function fig.occluders(p)
  local drop, lean, bob = p.drop or 0, p.lean or 0, p.bob or 0
  local so = p.stretch or 0
  local hipY = G - 64 + drop - bob
  local ty = hipY - 52 - floor(so * 0.65)
  local legHip = hipY - floor(so * 0.25)
  local out = {}
  if (p.shellG or 0) > 0.55 then
    -- sealed: a translucent gem, the light passes through it a little
    local s2 = ease(((p.shellG or 0) - 0.3) / 0.7)
    local mx, my = CX + 4, G + fig.GEM_CY
    out[#out + 1] = { mx - 42 * s2, my - 22 * s2, 84 * s2, 44 * s2, 0.34 }
    out[#out + 1] = { mx - 24 * s2, my - 58 * s2, 48 * s2, 36 * s2, 0.30 }
    out[#out + 1] = { mx - 24 * s2, my + 22 * s2, 48 * s2, 36 * s2, 0.30 }
    return out
  end
  out[#out + 1] = { CX - 12 + lean + 3, ty, 28, 40, 0.5 } -- chest
  out[#out + 1] = { CX - 10 + lean * 0.4, hipY - 10 - floor(so * 0.45), 28, 11, 0.4 } -- pelvis
  local nf, ff = p.nf or { 0, 0 }, p.ff or { 0, 0 }
  local legs = { { CX + 6, CX + ff[1] + 6, G - 8 - ff[2] }, { CX - 4, CX + nf[1] - 4, G - 8 - nf[2] } }
  for _, lg in ipairs(legs) do
    for _, t in ipairs({ 0.2, 0.5, 0.8 }) do
      out[#out + 1] = { lg[1] + (lg[2] - lg[1]) * t - 5, legHip + (lg[3] - legHip) * t - 8, 11, 16, 0.32 }
    end
  end
  local _, _, hxo, hyo = fig.eyeOffset(p)
  out[#out + 1] = { CX + hxo - 8, G + hyo - 12, 17, 26, 0.3 } -- the crystal head
  local nfist, ffist = p.nfist or { 0, 0 }, p.ffist or { 0, 0 }
  local fs = 1 + (p.mass or 0) * 0.9
  out[#out + 1] = { CX - 28 + nfist[1] - 8 * fs, G - 58 + nfist[2] + drop - 7 * fs, 17 * fs, 15 * fs, 0.34 }
  out[#out + 1] = { CX + 34 + ffist[1] - 8 * fs, G - 54 + ffist[2] + drop - 7 * fs, 17 * fs, 15 * fs, 0.3 }
  return out
end

-- Where the heart stone is, relative to (CX, G), for a pose (the glow pass lights it)
function fig.heartOffset(p)
  return 14.5 + (p.lean or 0), -116 + (p.drop or 0) - (p.bob or 0) + 14.5 - floor((p.stretch or 0) * 0.65)
end

-- Shader for the figure's canvas (no outline: the figure stands on its own colours): flash whitens the body, and half-transparent glow passes through untouched (premultiplied).
fig.outlineShaderCode = [[
extern vec2 texel;
extern float flash;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 c = Texel(tex, uv);
  if (c.a > 0.99) { return vec4(mix(c.rgb, vec3(1.0), flash), 1.0) * color; }
  if (c.a > 0.01) { return c * color; }
  return vec4(0.0);
}
]]

-- ---------------------------------------------------------------------------------------------
-- The golemlings: a single orange gem for a body (a small cousin of the Colossus's head), two bits of
-- marble for legs that swing past each other, a slit eye, and a soft glow behind. Drawn into a MW x MH
-- canvas, feet at (MW / 2, MG), with no outline (the glow is the rim light).
-- p: ph (the stride's phase), moving, air, falling, strike, t
-- ---------------------------------------------------------------------------------------------
fig.MW, fig.MH, fig.MG = 56, 34, 31
fig.miniEye = { 3, -17 } -- the eye, relative to the feet

-- A stepped, pixel-clean glow: concentric ellipses of rows
local function halo(cx, cy, rw, rh, a)
  gfx.setColor(C.glow[1], C.glow[2], C.glow[3], a)
  for dy = -rh, rh do
    local w = floor(math.sqrt(1 - (dy / rh) ^ 2) * rw)
    gfx.rectangle("fill", floor(cx - w), floor(cy + dy), w * 2 + 1, 1)
  end
end

function fig.drawMini(p)
  local cx, g = fig.MW / 2 - 8, fig.MG
  local trip = p.trip
  if trip then
    -- tripping over its own feet: it pitches forward, falls onto its front, lies there dazed, gets up
    local ang
    if trip < 0.2 then
      ang = ease(trip / 0.2) * 0.5
    elseif trip < 0.4 then
      ang = 0.5 + 0.95 * ease((trip - 0.2) / 0.2)
    elseif trip < 0.75 then
      ang = 1.45 + sin((trip - 0.4) * 40) * 0.05 * max(0, 0.7 - (trip - 0.4) * 2)
    else
      ang = 1.45 * (1 - ease((trip - 0.75) / 0.25))
    end
    gfx.push()
    gfx.translate(cx, g - min(1, ang / 1.45) * 5)
    gfx.rotate(ang)
    gfx.translate(-cx, -g)
  end
  local air, strike = p.air, p.strike
  local lean = strike and 2 or 0
  local ph = p.ph or 0
  local moving = p.moving
  local bob = (moving and not air) and floor(math.abs(sin(ph)) * 1) or 0
  local top = g - 25 - bob
  local function pt(dx, dy) return cx + dx, top + dy end
  -- the glow behind: the rim light that makes it easy to follow
  local pulse = 0.85 + 0.15 * sin((p.t or 0) * 3)
  halo(cx + 1, top + 11, 13, 14, 0.07 * pulse)
  halo(cx + 1, top + 11, 10, 11, 0.10 * pulse)
  halo(cx + 1, top + 11, 7, 8, 0.14 * pulse)
  -- legs: two lumps of marble that swing forward and back past each other, lifting as they pass
  local function leg(x, lift, seed, tone)
    rock(cx + x - 2, g - 6 - lift, 5, 6, seed, tone, { taper = 1 })
  end
  local near, far, nl, fl = 0, 0, 0, 0
  if trip then
    near, far, nl, fl = (trip < 0.4) and 6 or 3, (trip < 0.4) and -2 or -4, 3, 0 -- a foot hooked over the other
  elseif air then
    near, far, nl, fl = (p.falling and -2 or 2), (p.falling and 2 or -2), (p.falling and 0 or 2), (p.falling and 0 or 2)
  elseif moving then
    near, far = 5 * cos(ph), -5 * cos(ph)
    nl, fl = floor(3 * max(0, -sin(ph))), floor(3 * max(0, sin(ph)))
  else
    near, far = -2, 3
  end
  leg(far + 1, fl, 12, FAR) -- the far leg, behind the gem and in shade
  -- the gem
  local Tx, Ty = pt(1 + lean, 0)
  local L1x, L1y = pt(-4 + lean, 5)
  local L2x, L2y = pt(-4, 14)
  local Bx, By = pt(0, 20)
  local R1x, R1y = pt(6 + lean, 6)
  local R2x, R2y = pt(6, 14)
  col(C.glow)
  gfx.polygon("fill", Tx, Ty, L1x, L1y, L2x, L2y, Bx, By)
  col(C.rust)
  gfx.polygon("fill", Tx, Ty, R1x, R1y, R2x, R2y, Bx, By)
  col(C.gold)
  gfx.polygon("fill", cx + 1 + lean, top + 3, cx - 2 + lean, top + 7, cx - 2, top + 13, cx, top + 16)
  col(C.rustL)
  gfx.polygon("fill", cx + 2 + lean, top + 4, cx + 4 + lean, top + 7, cx + 3, top + 12, cx + 2, top + 14)
  col(C.rustD)
  gfx.polygon("fill", L2x, L2y, Bx, By, cx + 1, top + 15)
  gfx.polygon("fill", Bx, By, R2x, R2y, cx + 1, top + 15)
  line(C.hot, Tx, Ty + 1, cx, top + 18)
  -- the eye: a slit in the shaded face
  R(C.eye, cx + 2 + lean, top + 6, 2, 4)
  R(C.gold, cx + 3 + lean, top + 7, 1, 2)
  leg(near - 1, nl, 11, NEAR) -- the near leg, in front
  -- a loose shard or two: flung up as it falls, a spike thrust forward when it strikes
  if air and p.falling then
    shard(cx - 6, top + 3, 5, 2, -110, C.rust, C.rustL)
    shard(cx + 7, top + 2, 5, 2, -70, C.rust, C.rustL)
  elseif strike then
    shard(cx + 6, top + 9, 9, 3, -5, C.glow, C.hot)
  else
    local d = sin((p.t or 0) * 1.6) * 1
    shard(cx - 7, top + 4 + d, 5, 2, -140, C.rust, C.rustL)
  end
  if trip then
    gfx.pop()
    if trip > 0.4 and trip < 0.78 then
      -- dazed: a few sparks circling over it while it lies there
      for i = 1, 3 do
        local a = (p.t or 0) * 5 + i * 2.1
        mote(cx + 13 + cos(a) * 6, g - 12 + sin(a) * 3, i == 1, 0.9)
      end
    end
  end
end

-- No outline for the golemlings: only the flash, and the glow passes through
fig.plainShaderCode = [[
extern float flash;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 c = Texel(tex, uv);
  if (c.a > 0.99) { return vec4(mix(c.rgb, vec3(1.0), flash), 1.0) * color; }
  return c * color;
}
]]

return fig
