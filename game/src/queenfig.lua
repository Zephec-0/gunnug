-- The Sulfur Queen's figure, drawn on the 1:1 pixel grid.
--
-- She is a bag of gas gone to slime: a blob that wobbles and breathes, glassy at the rim and bright
-- in the middle, full of bubbles at several depths. The top of her head rises into a crown of slime
-- lobes with a bubble set in a slime circlet. Her eyes and mouth are dents pressed into the body
-- (shadowed upper-left wall, lit lower-right wall) and the eyes hold a glowing ember. She drips:
-- strands grow from her belly and sides, swell a bulb and let go (the game turns each let-go into a
-- falling drop, see enemies.lua; e.qd[i] is drip i's progress 0..1, the drop leaves at 0.8). Moving
-- drags her: the top lags behind (a sprung lean), she thins as she speeds up, and one blob of slime
-- sloshes about behind her on a stretching neck. Splitting is mitosis: she swells, pinches at the
-- waist, grows a face on each half and pulls apart (e.mito = { t, dur, childW }).
--
-- Everything is one world pixel. The figure is painted into a cell buffer, outlined, then emitted
-- as runs, so the body, crown, drips and tail share one outline. Remnants (84, 70, 56, 42 and 28 px
-- wide) are laid out again for the size they are given, never scaled.
--
--   fig.draw(e)    the body, crown, face, bubbles, drips (before the lighting)
--   fig.glow(e)    the glowing bits: eye embers, throat, the swell before an attack (after it)
local fig = {}

local gfx = love.graphics
local floor, sin, cos, min, max, abs, sqrt, exp = math.floor, math.sin, math.cos, math.min, math.max, math.abs, math.sqrt, math.exp
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local C = {
  ink = { 0.11, 0.13, 0.05 },
  deep = { 0.28, 0.33, 0.13 }, dark = { 0.43, 0.48, 0.20 }, base = { 0.58, 0.64, 0.27 },
  light = { 0.76, 0.82, 0.40 }, pale = { 0.90, 0.95, 0.62 },
  pit = { 0.07, 0.09, 0.04 }, ember = { 0.62, 0.60, 0.16 },
}
fig.colors = C
local RAMP = { C.deep, C.dark, C.base, C.light, C.pale }
local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }

local function clamp(v, a, b)
  return v < a and a or (v > b and b or v)
end
local function lerp(a, b, t)
  return a + (b - a) * t
end
local function ease(k)
  k = clamp(k, 0, 1)
  return k * k * (3 - 2 * k)
end
local function hash(x, y, s)
  local n = sin(x * 127.1 + y * 311.7 + (s or 0) * 74.7) * 43758.5453
  return n - floor(n)
end
local lat = {}
local function lattice(ix, iy)
  ix, iy = ix % 64, iy % 64
  local k = ix * 64 + iy
  local v = lat[k]
  if not v then
    v = hash(ix, iy, 9)
    lat[k] = v
  end
  return v
end
local function vnoise(x, y)
  local ix, iy = floor(x), floor(y)
  local fx, fy = x - ix, y - iy
  fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
  local a = lattice(ix, iy) + (lattice(ix + 1, iy) - lattice(ix, iy)) * fx
  local b = lattice(ix, iy + 1) + (lattice(ix + 1, iy + 1) - lattice(ix, iy + 1)) * fx
  return a + (b - a) * fy
end

-- The cell buffer ------------------------------------------------------------------------------
local cbuf, stamp, gen = {}, {}, 0
local OX, OY, BWID, BHGT = 0, 0, 0, 0
local dx0, dx1, dy0, dy1 -- dirty bounds (buffer cells)
local function put(x, y, c)
  local bx, by = x - OX, y - OY
  if bx < 1 or by < 1 or bx >= BWID - 1 or by >= BHGT - 1 then
    return
  end
  local i = by * BWID + bx
  cbuf[i], stamp[i] = c, gen
  if bx < dx0 then dx0 = bx end
  if bx > dx1 then dx1 = bx end
  if by < dy0 then dy0 = by end
  if by > dy1 then dy1 = by end
end
local function rect(x, y, w, h, c)
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do
      put(xx, yy, c)
    end
  end
end

-- How open her mouth is, 0 (slack) to 1 (wide): open as she spits a volley or dashes,
-- opening as she winds up
local function mouthOpen(e)
  if e.mito then
    return 0.45
  elseif e.spitT and e.spitT > 0 then
    return 1
  elseif e.qs == "attack" and e.atk == "dash" then
    return 1
  elseif e.qs == "windup" then
    local k = 1 - (e.qt or 0) / max(0.01, e.qtTotal or 1)
    return 0.3 + 0.5 * max(0, min(1, k))
  end
  return 0.08 + 0.06 * sin(e.phase * 1.4)
end

-- Her motion, smoothed, and the springs that make her sway, stretch and slosh (advanced once per frame)
local function motion(e)
  local now = love.timer.getTime()
  local s = e.qm
  if not s then
    s = { t = now, vx = 0, vy = 0, lx = 0, lv = 0, sy = 0, sv = 0, ox = 0, oy = 0, ovx = 0, ovy = 0 }
    e.qm = s
  end
  local dt = now - s.t
  if dt > 0.0005 then
    dt = min(dt, 0.04)
    s.t = now
    local b = e.body
    local k = 1 - exp(-dt * 6)
    s.vx = s.vx + ((b.vx or 0) - s.vx) * k
    s.vy = s.vy + ((b.vy or 0) - s.vy) * k
    local tl = -clamp(s.vx / 220, -1, 1)
    s.lv = s.lv + ((tl - s.lx) * 60 - s.lv * 4.5) * dt -- (underdamped: she swings past and settles)
    s.lx = s.lx + s.lv * dt
    local ts = clamp(sqrt(s.vx * s.vx + s.vy * s.vy) / 320, 0, 1)
    s.sv = s.sv + ((ts - s.sy) * 50 - s.sv * 4) * dt
    s.sy = s.sy + s.sv * dt
    -- The trailing blob: it wants to lie behind her, a little sagging, and swings about on its neck
    local W = b.w
    local tx, ty = -s.vx * 0.17, -s.vy * 0.17 + W * 0.1
    local tl2 = sqrt(tx * tx + ty * ty)
    local cap = W * 0.62
    if tl2 > cap then
      tx, ty = tx / tl2 * cap, ty / tl2 * cap
    end
    s.ovx = s.ovx + ((tx - s.ox) * 36 - s.ovx * 4.2) * dt
    s.ovy = s.ovy + ((ty - s.oy) * 36 - s.ovy * 4.2) * dt
    s.ox, s.oy = s.ox + s.ovx * dt, s.oy + s.ovy * dt
  end
  return s
end
local STILL = { lx = 0, sy = 0, ox = 0, oy = 0, vx = 0, vy = 0 }

-- Where everything sits, from the body's size (whole pixels, so every size lands on the grid).
-- o = { cx, y0, W, H } lays out a body other than e.body (the halves of a mitosis)
local function layout(e, o)
  local b = e.body
  local W, H = (o and o.W) or b.w, (o and o.H) or b.h
  local g = { W = W, H = H, big = W >= 56, mid = W >= 42, k = max(0.5, W / 84) }
  if o then
    g.cx, g.y0, g.x0 = o.cx, o.y0, o.cx - floor(W / 2)
  else
    g.x0, g.y0 = floor(b.x), floor(b.y)
    g.cx = g.x0 + floor(W / 2)
  end
  g.srx = max(2, floor(W * 0.09 + 0.5)) -- eye sockets
  g.sry = max(2, floor(W * 0.08 + 0.5))
  g.ex = floor(W * 0.2 + 0.5)
  g.ey = g.y0 + floor(H * 0.38 + 0.5)
  g.my = g.y0 + floor(H * 0.64 + 0.5)
  g.open = mouthOpen(e)
  g.mhalf = max(3, floor(W * (0.11 + 0.06 * g.open) + 0.5))
  g.mry = max(1, floor(H * (0.025 + 0.1 * g.open) + 0.5))
  g.m = o and STILL or motion(e)
  return g
end

-- The body's outline, row by row: XL[r], XR[r] for r = 0 .. H - 1
local XL, XR = {}, {}
local function sacWidth(t)
  -- a round bag with a slightly narrower foot
  local u = (t - 0.5) / 0.5
  local w = sqrt(max(0, 1 - u * u))
  if u > 0 then
    w = w * (1 - 0.14 * u)
  end
  return max(0.14, w)
end
local function silhouette(e, g)
  local ph = e.phase
  local m = g.m
  local breathe = (1 + 0.045 * sin(ph * 1.3)) * (e.novaWind and 1.07 or 1) * (1 - 0.12 * clamp(m.sy, -0.3, 1.2))
  local W, H = g.W, g.H
  for r = 0, H - 1 do
    local t = (r + 0.5) / H
    local wob = 1 + 0.035 * sin(ph * 2 + r * 0.18) + 0.02 * sin(ph * 3.1 - r * 0.3)
    local ww = max(3, floor(sacWidth(t) * W * wob * breathe + 0.5))
    local shift = floor(sin(ph * 1.6 + r * 0.12) * W * 0.018 + m.lx * W * 0.14 * (1 - t) ^ 1.3 + 0.5)
    XL[r] = g.cx - floor(ww / 2) + shift
    XR[r] = XL[r] + ww - 1
  end
end

-- The shading of one body pixel: a ramp index 1 (deep) .. 5 (pale). Glassy: dark at the rim, bright
-- through the middle, light bleeding through the lower right, a bright crescent on the upper left.
local function shade(g, e, x, r, xl, xr)
  local t = (r + 0.5) / g.H
  local half = (xr - xl + 1) / 2
  local nx = (x - (xl + xr) / 2) / half
  local ny = (t - 0.46) / 0.54
  local d = sqrt(nx * nx + ny * ny * 0.85)
  local bay = BAYER[(x % 4) + 4 * (r % 4) + 1] / 15 - 0.5
  local dd = d + bay * 0.14
  local i = dd > 0.86 and 1 or (dd > 0.66 and 2 or (dd > 0.34 and 3 or 4))
  -- gas thicker and thinner, drifting
  local n = vnoise((x - g.x0) * 0.1 + e.phase * 0.1, r * 0.1 - e.phase * 0.07)
  if n > 0.74 and i < 4 then
    i = i + 1
  elseif n < 0.2 and i > 1 then
    i = i - 1
  end
  -- light coming through the lower right, and a glint along the upper left: arcs that hug the rim
  if d > 0.7 and d < 0.93 then
    local a = atan2(ny, nx)
    if a > 0.15 and a < 1.25 and d < 0.86 then
      i = max(i, 4)
    end
    if a > -2.75 and a < -1.85 and d > 0.78 then
      i = (d < 0.88 and bay > -0.25) and 5 or max(i, 4)
    end
  end
  return i
end

local function body(g, e)
  local H, y0 = g.H, g.y0
  local ph1, ph2 = e.phase * 0.1, e.phase * 0.07
  local gx0 = g.x0
  for r = 0, H - 1 do
    local xl, xr = XL[r], XR[r]
    local ny = ((r + 0.5) / H - 0.46) / 0.54
    local ny2 = ny * ny * 0.85
    local half, mid = (xr - xl + 1) / 2, (xl + xr) / 2
    local by = y0 + r - OY
    local row = by * BWID - OX
    local nzr = r * 0.1 - ph2
    local brow = 4 * (r % 4) + 1
    local nv = 0.5
    for x = xl, xr do
      local nx = (x - mid) / half
      local d = sqrt(nx * nx + ny2)
      local bay = BAYER[(x % 4) + brow] / 15 - 0.5
      local dd = d + bay * 0.14
      local i = dd > 0.86 and 1 or (dd > 0.66 and 2 or (dd > 0.34 and 3 or 4))
      if x % 2 == 0 then
        nv = vnoise((x - gx0) * 0.1 + ph1, nzr) -- (gas density: the same for a pair of pixels)
      end
      if nv > 0.74 and i < 4 then
        i = i + 1
      elseif nv < 0.2 and i > 1 then
        i = i - 1
      end
      -- light through the lower right and a glint on the upper left: arcs that hug the rim
      if d > 0.7 and d < 0.93 then
        local a = atan2(ny, nx)
        if a > 0.15 and a < 1.25 and d < 0.86 then
          i = max(i, 4)
        end
        if a > -2.75 and a < -1.85 and d > 0.78 then
          i = (d < 0.88 and bay > -0.25) and 5 or max(i, 4)
        end
      end
      local k = row + x
      cbuf[k], stamp[k] = RAMP[i], gen
    end
    if xl - OX < dx0 then dx0 = xl - OX end
    if xr - OX > dx1 then dx1 = xr - OX end
    if by < dy0 then dy0 = by end
    if by > dy1 then dy1 = by end
  end
end

-- A pixel inside the body only (details never spill over the outline)
local function inside(g, x, y)
  local r = y - g.y0
  if r < 1 or r > g.H - 2 then
    return false
  end
  return x > XL[r] + 1 and x < XR[r] - 1
end
local function bpx(g, c, x, y)
  if inside(g, x, y) then
    put(x, y, c)
  end
end

-- The crown: slime lobes rising from the top of her head, the middle one tallest, painted before the
-- body so it covers their roots. Gaps between them are the points of the crown.
local function lobes(g, e)
  local W, H, cx, y0 = g.W, g.H, g.cx, g.y0
  local n = W >= 50 and 2 or 1
  local sp = g.mid and max(5, floor(W * 0.11 + 0.5)) or max(4, floor(W * 0.17 + 0.5))
  local rb = max(2, floor(W * 0.05 + 0.5))
  local ph = e.phase
  for i = -n, n do
    local h = max(4, floor((15 - abs(i) * (n == 2 and 3.5 or 6)) * W / 84 + 0.5))
    local ybase = y0 + floor(H * 0.1)
    local ytip = y0 - h + floor(H * 0.03)
    local x = cx + i * sp
    for y = ytip, ybase do
      local u = (y - ytip) / max(1, ybase - ytip)
      local r = max(1, floor(lerp(0.9, rb + 0.4, u ^ 0.8) + 0.5))
      local xc = x + floor(sin(ph * 1.2 + i * 1.3) * (1 - u) * 1.2 + 0.5)
      for xx = xc - r, xc + r do
        local c = C.base
        if xx == xc - r then
          c = (r >= 2) and C.light or C.base
        elseif xx == xc + r then
          c = C.deep
        elseif xx >= xc + r - 1 and r >= 3 then
          c = C.dark
        end
        put(xx, y, c)
      end
      if y == ytip then
        put(xc, y, C.pale)
      end
    end
    -- a bubble caught in the lobe
    if h >= 8 then
      put(x - 1, ytip + floor(h * 0.45), C.pale)
      put(x, ytip + floor(h * 0.45) + 1, C.light)
    end
  end
end

-- The slime circlet across her brow, with a bubble set in it (it glints, see fig.glow)
local function circlet(g, e)
  local W, H, cx, y0 = g.W, g.H, g.cx, g.y0
  local half = floor(W * 0.3)
  for x = cx - half, cx + half do
    local u = (x - cx) / max(1, half)
    local y = y0 + floor(H * 0.11) + floor(u * u * H * 0.07)
    bpx(g, C.pale, x, y)
    bpx(g, C.light, x, y + 1)
    bpx(g, C.deep, x, y + 2)
  end
  local gy = y0 + floor(H * 0.11) - 1
  local gr = g.big and 2 or 1
  for dy = -gr - 1, gr + 1 do
    for dx = -gr - 1, gr + 1 do
      local d2 = dx * dx + dy * dy
      if d2 <= gr * gr + 1 then
        bpx(g, (dx + dy < 0) and C.pale or C.light, cx + dx, gy + dy + 1)
      elseif d2 <= (gr + 1) * (gr + 1) + 1 then
        bpx(g, C.deep, cx + dx, gy + dy + 1)
      end
    end
  end
end

-- Bubbles at three depths: far ones are faint rings, near ones are bright with a glint and a shadowed
-- lower edge, and tiny fast ones fizz between them
local function bubbles(g, e)
  local W, H, cx, y0 = g.W, g.H, g.cx, g.y0
  local t = love.timer.getTime()
  local k = g.k
  local function disc(bx, by, r, ring, fill, hi, lo)
    for dy = -r, r do
      for dx = -r, r do
        local d = sqrt(dx * dx + dy * dy)
        if d <= r + 0.35 then
          local c
          if d > r - 1.0 then
            c = ring
            if lo and dx + dy > 0.6 * r and d > r - 1.0 then
              c = lo
            end
          else
            c = fill
          end
          if c then
            bpx(g, c, bx + dx, by + dy)
          end
        end
      end
    end
    if hi then
      bpx(g, hi, bx - floor(r * 0.45), by - floor(r * 0.5))
      if r >= 4 then
        bpx(g, hi, bx - floor(r * 0.45) + 1, by - floor(r * 0.5))
      end
    end
  end
  local nfar = g.mid and 9 or 4
  for i = 1, nfar do
    local rise = (t * 0.07 + e.phase * 0.05 + i * 0.317) % 1
    local bx = cx + floor(sin(i * 2.7 + t * 0.3) * W * 0.3 + 0.5)
    local by = y0 + floor(H * (0.92 - rise * 0.84) + 0.5)
    local r = max(2, floor((3 + (i % 3)) * k + 0.5))
    disc(bx, by, r, C.dark, nil, C.light)
  end
  local nnear = g.mid and 6 or 3
  for i = 1, nnear do
    local rise = (t * 0.12 + e.phase * 0.07 + i * 0.41 + 0.2) % 1
    local bx = cx + floor(sin(i * 1.9 + 1 + t * 0.45) * W * 0.27 + 0.5)
    local by = y0 + floor(H * (0.95 - rise * 0.88) + 0.5)
    local r = max(2, floor((3 + (i % 3) * 1.4) * k + 0.5)) * (rise < 0.15 and 0.6 or 1)
    r = max(2, floor(r + 0.5))
    disc(bx, by, r, C.pale, C.light, C.pale, C.dark)
  end
  for i = 1, g.mid and 9 or 4 do
    local rise = (t * 0.35 + e.phase * 0.1 + i * 0.239) % 1
    bpx(g, C.pale, cx + floor(sin(i * 4.1 + t) * W * 0.32 + 0.5), y0 + floor(H * (0.9 - rise * 0.8) + 0.5))
  end
end

-- A dent pressed into the body, lit from the upper left: its upper-left wall is in shadow, its
-- lower-right wall catches the light, its floor is a dark pit. skew slants it, curve bends it.
local function dent(g, cx, cy, rx, ry, skew, curve)
  for y = cy - ry - 2, cy + ry + 2 do
    for x = cx - rx - 2, cx + rx + 2 do
      local nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
      ny = ny + skew * nx + curve * nx * nx
      local d = nx * nx + ny * ny
      local fc = nx * 0.7 + ny * 0.7
      if d <= 1 then
        local c
        if d > 0.5 then
          c = fc < -0.1 and C.ink or (d > 0.82 and C.pale or C.light)
        else
          c = fc < 0.15 and C.pit or C.ink
        end
        bpx(g, c, x, y)
      elseif d <= 1.5 then
        if fc > 0.25 then
          bpx(g, C.light, x, y) -- (the swollen lip catching light)
        elseif fc < -0.35 and d < 1.3 then
          bpx(g, C.dark, x, y)
        end
      end
    end
  end
end

-- The eye sockets and the mouth
local function face(g, e)
  local angry = e.qs == "windup" or e.qs == "attack"
  local swell = 1 + 0.25 * g.open
  for side = -1, 1, 2 do
    dent(g, g.cx + side * g.ex, g.ey, floor(g.srx * swell + 0.5), floor(g.sry * swell + 0.5), angry and side * -0.3 or 0, 0)
    -- a dim ember in the socket (it glows, see fig.glow), looking at the hunter
    local look = e.aimAng or 0
    local lr = max(0, g.srx - 3)
    local ex = g.cx + side * g.ex + floor(cos(look) * lr * 0.7 + 0.5)
    local ey = g.ey + floor(sin(look) * lr * 0.5 + 0.5)
    local es = g.big and 2 or 1
    rect(ex - floor(es / 2), ey - floor(es / 2), es, es, C.ember)
  end
  dent(g, g.cx, g.my, g.mhalf, g.mry, 0, g.open < 0.4 and 0.9 or 0.15)
  -- Drool strings from the lower lip when she is open
  if g.open > 0.5 and not e.mito then
    local t = love.timer.getTime()
    for s = -1, 1, 2 do
      local x = g.cx + s * floor(g.mhalf * 0.5)
      local len = floor((3 + 3 * sin(t * 2.3 + s)) * g.k + 2)
      for j = 0, len do
        bpx(g, j == len and C.pale or C.light, x, g.my + g.mry + 1 + j)
      end
    end
  end
end

-- Painter's helper for the tail, the neck and the drips: a small shaded disc
local function blob(cx, cy, r)
  for dy = -r, r do
    for dx = -r, r do
      local d = sqrt(dx * dx + dy * dy)
      if d <= r + 0.3 then
        local fc = (dx + dy) / max(1, r)
        local c = d > r - 0.9 and (fc < -0.3 and C.light or (fc > 0.4 and C.deep or C.dark)) or (fc < -0.2 and C.light or C.base)
        put(cx + dx, cy + dy, c)
      end
    end
  end
end

-- Slime stretched between two points, thick at both ends and pinched in the middle: painted in the
-- shadow tone, then again smaller and lit. pinch 0..1 how thin the middle gets.
local function neck(x1, y1, r1, x2, y2, r2, pinch)
  local len = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
  local n = max(2, floor(len / max(2, min(r1, r2) * 0.45)))
  for pass = 1, 2 do
    for i = 0, n do
      local u = i / n
      local r = lerp(r1, r2, u) * (1 - pinch * sin(u * 3.1416) * 0.7)
      local x, y = lerp(x1, x2, u), lerp(y1, y2, u)
      if pass == 1 then
        local ri = floor(r + 0.5)
        for yy = -ri, ri do
          for xx = -ri, ri do
            if xx * xx + yy * yy <= r * r + r * 0.5 then
              put(floor(x) + xx, floor(y) + yy, C.dark)
            end
          end
        end
      else
        local rr = r - 1.4
        if rr > 1 then
          local ri = floor(rr + 1)
          for yy = -ri, ri do
            for xx = -ri, ri do
              if (xx + 1) ^ 2 + (yy + 1) ^ 2 <= rr * rr then
                put(floor(x) + xx - 1, floor(y) + yy - 1, (xx + yy < -rr * 0.55) and C.light or C.base)
              end
            end
          end
        end
      end
    end
  end
end

-- The trailing blob: one lump of slime that lags behind her and sloshes about on a stretching neck
local function tail(g, e)
  local m = g.m
  local dist = sqrt(m.ox * m.ox + m.oy * m.oy)
  if dist < g.W * 0.12 then
    return
  end
  local W = g.W
  local cx, cy = g.cx, g.y0 + floor(g.H * 0.5)
  local tx, ty = cx + m.ox, cy + m.oy
  local rt = W * 0.24 * (1 + 0.07 * sin(love.timer.getTime() * 6 + e.phase))
  neck(cx, cy, W * 0.3, tx, ty, rt, clamp(dist / (W * 0.6), 0, 1) * 0.8)
  -- the lump itself is shaded like her body: dark at the rim, bright inside, a glint on its shoulder
  local ri = floor(rt + 1)
  local ix, iy = floor(tx), floor(ty)
  for yy = -ri, ri do
    for xx = -ri, ri do
      local d = sqrt(xx * xx + yy * yy) / rt
      if d <= 1 then
        local bay = BAYER[((ix + xx) % 4) + 4 * ((iy + yy) % 4) + 1] / 15 - 0.5
        local dd = d + bay * 0.14
        local i = dd > 0.84 and 1 or (dd > 0.62 and 2 or (dd > 0.32 and 3 or 4))
        local a = atan2(yy, xx)
        if a > -2.75 and a < -1.85 and d > 0.6 and d < 0.9 then
          i = 5
        end
        put(ix + xx, iy + yy, RAMP[i])
      end
    end
  end
  -- a bubble in the lump
  local bx, by = floor(tx - rt * 0.25), floor(ty - rt * 0.15)
  put(bx, by, C.pale)
  put(bx + 1, by, C.light)
  put(bx, by + 1, C.light)
  put(bx + 1, by + 1, C.light)
end

-- Drips: a strand grows from her belly or side, swells a bulb on its end, then lets go: the strand
-- snaps back (the game launches the falling drop at that moment)
local DRIP_SPECS = {
  { edge = "B", u = -0.12, row = 1.0, o = 0.00, l = 1.0 },
  { edge = "B", u = 0.04, row = 1.0, o = 0.43, l = 0.6 },
  { edge = "B", u = 0.17, row = 1.0, o = 0.71, l = 0.9 },
  { edge = "L", row = 0.66, o = 0.25, l = 0.8 },
  { edge = "R", row = 0.74, o = 0.58, l = 1.1 },
  { edge = "L", row = 0.82, o = 0.88, l = 0.6 },
}
function fig.dripCount(W)
  return W >= 42 and #DRIP_SPECS or 3
end
function fig.dripOffset(i)
  return DRIP_SPECS[i].o
end
-- Where drip i lets go, in the world (approximate: it ignores the wobble)
function fig.dripTip(e, i)
  local b = e.body
  local W, H = b.w, b.h
  local k = max(0.5, W / 84)
  local s = DRIP_SPECS[i]
  local r = clamp(floor(s.row * H) - (s.edge == "B" and 1 or 0), 1, H - 1)
  local ww = floor(sacWidth((r + 0.5) / H) * W + 0.5)
  local cx = floor(b.x) + floor(W / 2)
  local ax
  if s.edge == "B" then
    ax = cx + floor(s.u * W + 0.5)
  elseif s.edge == "L" then
    ax = cx - floor(ww / 2) + 2
  else
    ax = cx - floor(ww / 2) + ww - 3
  end
  return ax, floor(b.y) + r + max(3, floor((9 + 7 * s.l) * k + 0.5))
end

local function drips(g, e)
  local H, W, k = g.H, g.W, g.k
  local t = love.timer.getTime() * 0.13 + (e.phase * 0.131) % 1
  local nd = fig.dripCount(W)
  for i = 1, nd do
    local s = DRIP_SPECS[i]
    local p = (e.qd and e.qd[i]) or ((t + s.o) % 1)
    local r = clamp(floor(s.row * H) - (s.edge == "B" and 1 or 0), 1, H - 1)
    local ax
    if s.edge == "B" then
      ax = clamp(g.cx + floor(s.u * W + 0.5), XL[r] + 2, XR[r] - 2)
    elseif s.edge == "L" then
      ax = XL[r] + 2
    else
      ax = XR[r] - 2
    end
    local ay = g.y0 + r
    local lmax = max(3, floor((9 + 7 * s.l) * k + 0.5))
    local wtop = g.big and 3 or 2
    local len
    local rb = g.big and 2 or 1
    if p < 0.8 then
      local u = p / 0.8
      len = floor(lmax * u * u * (3 - 2 * u) + 0.5)
      rb = max(1, floor(rb * (0.5 + 0.7 * u) + 0.5))
    elseif p < 0.9 then
      len = floor(lmax * (1 - (p - 0.8) / 0.1) * 0.5 + 0.5) -- (the strand snaps back)
      rb = nil
    else
      len, rb = 0, nil
    end
    for j = 0, len do
      local w = max(1, floor(wtop * (1 - j / (len + 1)) ^ 0.8 + 0.5))
      local x0 = ax - floor(w / 2)
      for q = 0, w - 1 do
        put(x0 + q, ay + j, (q == 0 and w >= 2) and C.light or ((q == w - 1 and w >= 2) and C.deep or C.base))
      end
    end
    if rb and len > 1 then
      blob(ax, ay + len + rb - 1, rb)
      put(ax - 1, ay + len + rb - 2, C.pale)
    end
  end
end

-- Outlines the painted cells and writes them straight into the pixels of a picture that belongs to
-- this monster (thousands of 1 px rectangles, one per run of the dithered shading, cost several
-- milliseconds a frame). The picture is kept and redrawn as it is for a few frames (see fig.draw).
-- shimmer 0..1 washes everything pale.
local ffi = require("ffi")
local rgb = {}
local function bytes(c, white, shimmer)
  local v = rgb[c]
  if not v then
    v = {}
    rgb[c] = v
  end
  local key = white and 2 or (shimmer > 0 and 1 or 0)
  local t = v[key]
  if not t then
    local r, g, b2 = c[1], c[2], c[3]
    if white then
      r, g, b2 = 1, 1, 1
    elseif key == 1 then
      r, g, b2 = lerp(r, 0.95, 0.45), lerp(g, 1, 0.45), lerp(b2, 0.8, 0.45)
    end
    t = { floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b2 * 255 + 0.5) }
    v[key] = t
  end
  return t
end
local function emit(e, white, shimmer)
  local c = e.qc
  if not c or c.w ~= BWID or c.h ~= BHGT then
    local d = love.image.newImageData(BWID, BHGT)
    c = { data = d, ptr = ffi.cast("uint8_t*", d:getFFIPointer()), img = love.graphics.newImage(d), w = BWID, h = BHGT }
    c.img:setFilter("nearest", "nearest")
    e.qc = c
  end
  local ptr = c.ptr
  ffi.fill(ptr, BWID * BHGT * 4, 0)
  for by = dy0 - 1, dy1 + 1 do
    for bx = dx0 - 1, dx1 + 1 do
      local col
      local i = by * BWID + bx
      if stamp[i] == gen then
        col = cbuf[i]
      end
      if col and bx >= 0 and by >= 0 and bx < BWID and by < BHGT then
        local t = bytes(col, white, shimmer)
        local o = i * 4
        ptr[o], ptr[o + 1], ptr[o + 2], ptr[o + 3] = t[1], t[2], t[3], 255
      end
    end
  end
  c.img:replacePixels(c.data)
  c.ox, c.oy = OX, OY
  return c
end

-- The two halves of a mitosis, p 0..1: they swell and shake, pinch apart on a thinning bridge, each
-- grows a face, and they end at the size and spacing of the remnants the game then spawns
local function halves(e, p)
  local b = e.body
  local m = e.mito
  local W = b.w
  local cx0, cy0 = floor(b.x + W / 2), floor(b.y + b.h / 2)
  local Wh = floor(lerp(W, m.childW, ease(p)) + 0.5)
  local dF = floor(m.childW * 0.55)
  local d = floor(dF * ease((p - 0.12) / 0.88) + 0.5)
  local shake = p < 0.2 and floor(sin(m.t * 70) * 1.2 + 0.5) or 0
  local out = {}
  for side = -1, 1, 2 do
    out[#out + 1] = { cx = cx0 + side * d + shake, y0 = cy0 - floor(Wh / 2), W = Wh, H = Wh, side = side }
  end
  return out, cx0, cy0, d, Wh
end

local REDRAW = 1 / 30 -- (her picture is rebuilt this often; in between it is the same picture, moved with her)
function fig.draw(e)
  local b = e.body
  local now = love.timer.getTime()
  local shimmer = 0
  if e.mito or (e.iframes or 0) > 0 then
    shimmer = (floor(now * 12) % 2 == 0) and 0.45 or 0
  end
  local W, H = b.w, b.h
  local key = ((e.flash or 0) > 0 and 1 or 0) + (shimmer > 0 and 2 or 0) + (e.novaWind and 4 or 0) + (e.spitT and e.spitT > 0 and 8 or 0)
  local c = e.qc
  local bx0, by0 = floor(b.x), floor(b.y)
  if c and not e.mito and c.key == key and c.W == W and now - c.t < REDRAW then
    gfx.setColor(1, 1, 1)
    gfx.draw(c.img, c.ox + bx0 - c.bx, c.oy + by0 - c.by)
    return
  end
  gen = gen + 1
  local padx = floor(W * 0.6) + 3
  local up = floor(H * 0.28) + 6
  BWID, BHGT = W + padx * 2, H + up + floor(H * 0.75) + 8
  local cxb = floor(b.x) + floor(W / 2)
  OX, OY = cxb - floor(W / 2) - padx, floor(b.y) - up
  dx0, dx1, dy0, dy1 = BWID, 0, BHGT, 0
  if e.mito then
    local p = clamp(e.mito.t / e.mito.dur, 0, 1)
    local hv, cx0, cy0, d, Wh = halves(e, p)
    -- the bridge between them, thinning to a thread and snapping
    if d >= 2 then
      local rn = Wh * 0.45 * (1 - ease((p - 0.3) / 0.6))
      if rn >= 1 then
        neck(cx0 - d, cy0, rn + 1, cx0 + d, cy0, rn + 1, 0.55)
      end
    end
    local gs = {}
    for i, o in ipairs(hv) do
      gs[i] = layout(e, o)
      silhouette(e, gs[i])
      lobes(gs[i], e)
      body(gs[i], e)
    end
    for _, g in ipairs(gs) do
      silhouette(e, g)
      bubbles(g, e)
      circlet(g, e)
      face(g, e)
    end
  else
    local g = layout(e)
    silhouette(e, g)
    tail(g, e)
    lobes(g, e)
    body(g, e)
    bubbles(g, e)
    circlet(g, e)
    face(g, e)
    drips(g, e)
  end
  c = emit(e, (e.flash or 0) > 0, shimmer)
  c.key, c.W, c.t, c.bx, c.by = key, W, now, bx0, by0
  gfx.setColor(1, 1, 1)
  gfx.draw(c.img, c.ox, c.oy)
end

local function glowFace(g, e, t)
  local cx = g.cx
  -- The throat lights up as she spits
  if g.open > 0.3 then
    local flick = 0.6 + 0.3 * sin(t * 30)
    gfx.setColor(0.7, 1, 0.3, (g.open - 0.2) * flick * 0.8)
    gfx.rectangle("fill", cx - g.mhalf + 2, g.my - g.mry + 2, 2 * g.mhalf - 3, max(1, 2 * g.mry - 3))
  end
  -- Embers in the sockets, looking at the hunter
  local look = e.aimAng or 0
  local lr = max(0, g.srx - 3)
  local es = g.big and 2 or 1
  for side = -1, 1, 2 do
    local ex = cx + side * g.ex + floor(cos(look) * lr * 0.7 + 0.5)
    local ey = g.ey + floor(sin(look) * lr * 0.5 + 0.5)
    gfx.setColor(1, 0.95, 0.4, 0.3)
    gfx.rectangle("fill", ex - es, ey - es, es * 3, es * 3)
    gfx.setColor(1, 0.97, 0.55, 0.95)
    gfx.rectangle("fill", ex - floor(es / 2), ey - floor(es / 2), es, es)
  end
  -- the bubble in her circlet
  local gy = g.y0 + floor(g.H * 0.11)
  local pulse = 0.5 + 0.3 * sin(e.phase * 1.7)
  gfx.setColor(0.9, 1, 0.5, pulse * 0.35)
  gfx.rectangle("fill", cx - 3, gy - 3, 7, 6)
end

function fig.glow(e)
  local b = e.body
  local t = love.timer.getTime()
  if e.mito then
    local p = clamp(e.mito.t / e.mito.dur, 0, 1)
    for _, o in ipairs((halves(e, p))) do
      glowFace(layout(e, o), e, t)
    end
    gfx.setColor(1, 1, 1)
    return
  end
  local g = layout(e)
  if e.qs == "windup" and e.atk == "dash" and e.dashAng then
    -- Where she will go: a dotted line that flickers faster once it locks
    local lock = (e.qt or 0) < 0.3
    local qx, qy = b.x + b.w / 2, b.y + b.h / 2
    for d = b.w * 0.6, 800, 7 do
      if floor(t * (lock and 30 or 9) + d / 7) % 2 == 0 then
        gfx.setColor(1, lock and 0.35 or 0.8, 0.2, lock and 0.9 or 0.55)
        gfx.rectangle("fill", floor(qx + cos(e.dashAng) * d), floor(qy + sin(e.dashAng) * d), 2, 2)
      end
    end
  end
  glowFace(g, e, t)
  if e.novaWind then
    -- Swelling up for an attack: the whole body glows, row by row, in its own outline
    silhouette(e, g)
    local p = 0.22 + 0.2 * sin(t * 25)
    gfx.setColor(0.85, 0.95, 0.35, p)
    for r = 1, g.H - 2 do
      gfx.rectangle("fill", XL[r] + 1, g.y0 + r, XR[r] - XL[r] - 1, 1)
    end
  end
  gfx.setColor(1, 1, 1)
end

return fig
