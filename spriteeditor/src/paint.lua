-- Painting into a cel. A stroke context carries the target cel, colours, brush and mode; points come
-- in canvas pixels and are mapped into the cel through `inv` when the layer rides a posed bone.
--
-- Modes: normal | shadeUp | shadeDown (step to the nearest lighter/darker palette colour) |
--        dither (checkerboard of the two colours)
-- Toggles: lockAlpha (only paint over existing pixels), mirrorX/Y, pixel-perfect freehand.
local U = require("src.util")

local P = {}

function P.begin(ctx)
  ctx.orig, ctx.done, ctx.pts = {}, {}, {}
  ctx.cw, ctx.ch = ctx.cel.data:getDimensions()
  return ctx
end

-- Nearest palette colour that is lighter (dir 1) or darker (dir -1) than c
function P.shade(pal, c, dir)
  local l0 = U.luma(c[1], c[2], c[3])
  local best, bestD
  for _, p in ipairs(pal) do
    local l = U.luma(p[1], p[2], p[3])
    if (l - l0) * dir > 0.02 then
      local d = (p[1] - c[1]) ^ 2 + (p[2] - c[2]) ^ 2 + (p[3] - c[3]) ^ 2
      if not bestD or d < bestD then best, bestD = p, d end
    end
  end
  if best then return best[1], best[2], best[3], c[4] end
  if #pal > 0 then return c[1], c[2], c[3], c[4] end
  local h, s, v = U.rgb2hsv(c[1], c[2], c[3])
  local r, g, b = U.hsv2rgb(h, s, U.clamp(v + 0.08 * dir, 0, 1))
  return r, g, b, c[4]
end

-- Writes one cel pixel according to the mode; returns its key if it was written
local function write(ctx, cx, cy)
  if cx < 0 or cy < 0 or cx >= ctx.cw or cy >= ctx.ch then return end
  local key = cy * ctx.cw + cx
  local d = ctx.cel.data
  local o = ctx.orig[key]
  if not o then
    local r, g, b, a = d:getPixel(cx, cy)
    o = { r, g, b, a }
    ctx.orig[key] = o
  end
  if ctx.lockAlpha and o[4] == 0 then return end
  local r, g, b, a
  local mode = ctx.mode
  if ctx.erase then
    r, g, b, a = 0, 0, 0, 0
  elseif mode == "shadeUp" or mode == "shadeDown" then
    if ctx.done[key] or o[4] == 0 then return end
    r, g, b, a = P.shade(ctx.palette, o, mode == "shadeUp" and 1 or -1)
  elseif mode == "dither" then
    local c = ((cx + cy) % 2 == 0) and ctx.color or ctx.color2
    if c[4] == 0 and c == ctx.color2 then
      r, g, b, a = o[1], o[2], o[3], o[4] -- a clear second colour leaves the gaps alone
    else
      r, g, b, a = c[1], c[2], c[3], c[4]
    end
  else
    local c = ctx.color
    r, g, b, a = c[1], c[2], c[3], c[4]
  end
  ctx.done[key] = true
  d:setPixel(cx, cy, r, g, b, a)
  ctx.touched = true
  return key
end

local function plotCanvas(ctx, x, y, keys)
  local s = ctx.sel
  if s and (x < s.x or y < s.y or x >= s.x + s.w or y >= s.y + s.h) then return end
  local cx, cy = x, y
  if ctx.inv then cx, cy = ctx.inv(x, y) end
  local k = write(ctx, cx, cy)
  if k and keys then keys[#keys + 1] = k end
end

-- One brush dab at canvas pixel (x, y), mirrored as asked
function P.plot(ctx, x, y, keys)
  local s = ctx.size
  local o = -math.floor((s - 1) / 2)
  for by = 0, s - 1 do
    for bx = 0, s - 1 do
      local px, py = x + o + bx, y + o + by
      plotCanvas(ctx, px, py, keys)
      if ctx.mirrorX then plotCanvas(ctx, ctx.W - 1 - px, py, keys) end
      if ctx.mirrorY then plotCanvas(ctx, px, ctx.H - 1 - py, keys) end
      if ctx.mirrorX and ctx.mirrorY then plotCanvas(ctx, ctx.W - 1 - px, ctx.H - 1 - py, keys) end
    end
  end
end

-- Freehand point; with pixel-perfect on, an L-shaped corner pixel is taken back out
local function point(ctx, x, y)
  local keys = {}
  P.plot(ctx, x, y, keys)
  if not (ctx.pp and ctx.size == 1) then return end
  local pts = ctx.pts
  pts[#pts + 1] = { x = x, y = y, keys = keys }
  local n = #pts
  if n < 3 then return end
  local a, b, c = pts[n - 2], pts[n - 1], pts[n]
  if math.abs(a.x - c.x) == 1 and math.abs(a.y - c.y) == 1
    and (b.x == a.x or b.y == a.y) and (b.x == c.x or b.y == c.y) then
    local d = ctx.cel.data
    for _, k in ipairs(b.keys) do
      local o = ctx.orig[k]
      local cx = k % ctx.cw
      d:setPixel(cx, (k - cx) / ctx.cw, o[1], o[2], o[3], o[4])
      ctx.done[k] = nil
    end
    table.remove(pts, n - 1)
  end
end

function P.strokeTo(ctx, x, y)
  if not ctx.lx then
    ctx.lx, ctx.ly = x, y
    point(ctx, x, y)
    return
  end
  if x == ctx.lx and y == ctx.ly then return end
  local first = true
  U.line(ctx.lx, ctx.ly, x, y, function(px, py)
    if first then first = false return end
    point(ctx, px, py)
  end)
  ctx.lx, ctx.ly = x, y
end

-- Bucket fill from canvas pixel (x, y): the contiguous area of that colour, or every pixel of it
function P.fill(ctx, x, y, global)
  local cx, cy = x, y
  if ctx.inv then cx, cy = ctx.inv(x, y) end
  local w, h = ctx.cw, ctx.ch
  if cx < 0 or cy < 0 or cx >= w or cy >= h then return end
  local d = ctx.cel.data
  local tr, tg, tb, ta = d:getPixel(cx, cy)
  local target = { tr, tg, tb, ta }
  local s = not ctx.inv and ctx.sel
  local function inside(px, py)
    return not s or (px >= s.x and py >= s.y and px < s.x + s.w and py < s.y + s.h)
  end
  local px = {}
  local function same(px_, py_)
    local r, g, b, a = d:getPixel(px_, py_)
    return U.sameColor(target, { r, g, b, a })
  end
  if global then
    for yy = 0, h - 1 do
      for xx = 0, w - 1 do
        if inside(xx, yy) and same(xx, yy) then px[#px + 1] = yy * w + xx end
      end
    end
  else
    if not inside(cx, cy) then return end
    local seen, stack = { [cy * w + cx] = true }, { cy * w + cx }
    while #stack > 0 do
      local k = table.remove(stack)
      px[#px + 1] = k
      local xx = k % w
      local yy = (k - xx) / w
      local function try(nx, ny)
        if nx < 0 or ny < 0 or nx >= w or ny >= h then return end
        local nk = ny * w + nx
        if seen[nk] or not inside(nx, ny) or not same(nx, ny) then return end
        seen[nk] = true
        stack[#stack + 1] = nk
      end
      try(xx + 1, yy)
      try(xx - 1, yy)
      try(xx, yy + 1)
      try(xx, yy - 1)
    end
  end
  local lock = ctx.lockAlpha
  ctx.lockAlpha = false
  for _, k in ipairs(px) do
    local xx = k % w
    write(ctx, xx, (k - xx) / w)
  end
  ctx.lockAlpha = lock
end

-- Shapes (pixel lists in canvas coordinates) ------------------------------------------------------

function P.linePoints(x0, y0, x1, y1)
  local pts = {}
  U.line(x0, y0, x1, y1, function(x, y) pts[#pts + 1] = { x, y } end)
  return pts
end

function P.rectPoints(x0, y0, x1, y1, filled)
  if x0 > x1 then x0, x1 = x1, x0 end
  if y0 > y1 then y0, y1 = y1, y0 end
  local pts = {}
  for y = y0, y1 do
    for x = x0, x1 do
      if filled or x == x0 or x == x1 or y == y0 or y == y1 then pts[#pts + 1] = { x, y } end
    end
  end
  return pts
end

-- Alois Zingl's ellipse in a rectangle (handles even sizes cleanly)
function P.ellipsePoints(x0, y0, x1, y1, filled)
  local set, pts = {}, {}
  local function plot(x, y)
    local k = x .. "," .. y
    if not set[k] then
      set[k] = true
      pts[#pts + 1] = { x, y }
    end
  end
  local a, b = math.abs(x1 - x0), math.abs(y1 - y0)
  local b1 = b % 2
  local dx, dy = 4 * (1 - a) * b * b, 4 * (b1 + 1) * a * a
  local err = dx + dy + b1 * a * a
  if x0 > x1 then x0 = x1; x1 = x1 + a end
  if y0 > y1 then y0 = y1 end
  y0 = y0 + math.floor((b + 1) / 2)
  y1 = y0 - b1
  local a8, b8 = 8 * a * a, 8 * b * b
  repeat
    plot(x1, y0); plot(x0, y0); plot(x0, y1); plot(x1, y1)
    local e2 = 2 * err
    if e2 <= dy then y0 = y0 + 1; y1 = y1 - 1; dy = dy + a8; err = err + dy end
    if e2 >= dx or 2 * err > dy then x0 = x0 + 1; x1 = x1 - 1; dx = dx + b8; err = err + dx end
  until x0 > x1
  while y0 - y1 <= b do
    plot(x0 - 1, y0); plot(x1 + 1, y0); y0 = y0 + 1
    plot(x0 - 1, y1); plot(x1 + 1, y1); y1 = y1 - 1
  end
  if filled then
    local rows = {}
    for _, p in ipairs(pts) do
      local r = rows[p[2]]
      if not r then rows[p[2]] = { p[1], p[1] } else r[1] = math.min(r[1], p[1]); r[2] = math.max(r[2], p[1]) end
    end
    for y, r in pairs(rows) do
      for x = r[1] + 1, r[2] - 1 do plot(x, y) end
    end
  end
  return pts
end

function P.commitPoints(ctx, pts)
  for _, p in ipairs(pts) do P.plot(ctx, p[1], p[2]) end
end

return P
