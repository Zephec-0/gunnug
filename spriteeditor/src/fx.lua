-- Pixel effects on image data, each limited to a region {x, y, w, h} (nil: the whole image).
local U = require("src.util")

local fx = {}

local function region(d, r)
  local w, h = d:getDimensions()
  if not r then return 0, 0, w, h end
  local x0, y0 = math.max(0, r.x), math.max(0, r.y)
  local x1, y1 = math.min(w, r.x + r.w), math.min(h, r.y + r.h)
  return x0, y0, math.max(0, x1 - x0), math.max(0, y1 - y0)
end

local function alpha(d, x, y)
  local w, h = d:getDimensions()
  if x < 0 or y < 0 or x >= w or y >= h then return 0 end
  local _, _, _, a = d:getPixel(x, y)
  return a
end

-- Runs fn(r, g, b, a) -> r, g, b, a on every opaque pixel of the region
local function eachOpaque(d, r, fn)
  local x0, y0, w, h = region(d, r)
  for y = y0, y0 + h - 1 do
    for x = x0, x0 + w - 1 do
      local cr, cg, cb, ca = d:getPixel(x, y)
      if ca > 0 then d:setPixel(x, y, fn(cr, cg, cb, ca)) end
    end
  end
end

function fx.flipH(d, r)
  local x0, y0, w, h = region(d, r)
  for y = y0, y0 + h - 1 do
    for i = 0, math.floor(w / 2) - 1 do
      local xa, xb = x0 + i, x0 + w - 1 - i
      local a1, a2, a3, a4 = d:getPixel(xa, y)
      d:setPixel(xa, y, d:getPixel(xb, y))
      d:setPixel(xb, y, a1, a2, a3, a4)
    end
  end
end

function fx.flipV(d, r)
  local x0, y0, w, h = region(d, r)
  for i = 0, math.floor(h / 2) - 1 do
    local ya, yb = y0 + i, y0 + h - 1 - i
    for x = x0, x0 + w - 1 do
      local a1, a2, a3, a4 = d:getPixel(x, ya)
      d:setPixel(x, ya, d:getPixel(x, yb))
      d:setPixel(x, yb, a1, a2, a3, a4)
    end
  end
end

-- Quarter turn about the region's centre (dir 1 clockwise); what leaves the region is cut off
function fx.rotate(d, r, dir)
  local x0, y0, w, h = region(d, r)
  local src = d:clone()
  local cx, cy = x0 + (w - 1) / 2, y0 + (h - 1) / 2
  for y = y0, y0 + h - 1 do
    for x = x0, x0 + w - 1 do
      local u, v = x - cx, y - cy
      local sx, sy
      if dir > 0 then sx, sy = cx + v, cy - u else sx, sy = cx - v, cy + u end
      sx, sy = math.floor(sx + 0.5), math.floor(sy + 0.5)
      if sx >= x0 and sy >= y0 and sx < x0 + w and sy < y0 + h then
        d:setPixel(x, y, src:getPixel(sx, sy))
      else
        d:setPixel(x, y, 0, 0, 0, 0)
      end
    end
  end
  src:release()
end

-- Clear pixels next to the art become `c` (diag: corners count too)
function fx.outline(d, r, c, diag)
  local x0, y0, w, h = region(d, r)
  local src = d:clone()
  for y = y0, y0 + h - 1 do
    for x = x0, x0 + w - 1 do
      if alpha(src, x, y) == 0 then
        local hit = alpha(src, x - 1, y) > 0 or alpha(src, x + 1, y) > 0 or alpha(src, x, y - 1) > 0 or alpha(src, x, y + 1) > 0
        if not hit and diag then
          hit = alpha(src, x - 1, y - 1) > 0 or alpha(src, x + 1, y - 1) > 0 or alpha(src, x - 1, y + 1) > 0 or alpha(src, x + 1, y + 1) > 0
        end
        if hit then d:setPixel(x, y, c[1], c[2], c[3], c[4]) end
      end
    end
  end
  src:release()
end

-- The art's own edge pixels become `c`
function fx.inline(d, r, c)
  local x0, y0, w, h = region(d, r)
  local src = d:clone()
  for y = y0, y0 + h - 1 do
    for x = x0, x0 + w - 1 do
      if alpha(src, x, y) > 0 then
        if alpha(src, x - 1, y) == 0 or alpha(src, x + 1, y) == 0 or alpha(src, x, y - 1) == 0 or alpha(src, x, y + 1) == 0 then
          d:setPixel(x, y, c[1], c[2], c[3], c[4])
        end
      end
    end
  end
  src:release()
end

-- A hard shadow `dx, dy` pixels behind the art
function fx.shadow(d, r, c, dx, dy)
  local x0, y0, w, h = region(d, r)
  local src = d:clone()
  for y = y0, y0 + h - 1 do
    for x = x0, x0 + w - 1 do
      if alpha(src, x, y) == 0 and alpha(src, x - dx, y - dy) > 0 then
        d:setPixel(x, y, c[1], c[2], c[3], c[4])
      end
    end
  end
  src:release()
end

function fx.hsv(d, r, dh, ds, dv)
  eachOpaque(d, r, function(cr, cg, cb, ca)
    local h, s, v = U.rgb2hsv(cr, cg, cb)
    local nr, ng, nb = U.hsv2rgb(h + dh, U.clamp(s + ds, 0, 1), U.clamp(v + dv, 0, 1))
    return nr, ng, nb, ca
  end)
end

function fx.invert(d, r)
  eachOpaque(d, r, function(cr, cg, cb, ca) return 1 - cr, 1 - cg, 1 - cb, ca end)
end

function fx.gray(d, r)
  eachOpaque(d, r, function(cr, cg, cb, ca)
    local l = U.luma(cr, cg, cb)
    return l, l, l, ca
  end)
end

-- Every opaque pixel snaps to the nearest palette colour
function fx.snap(d, r, pal)
  if #pal == 0 then return end
  eachOpaque(d, r, function(cr, cg, cb, ca)
    local best, bd = pal[1], math.huge
    for _, p in ipairs(pal) do
      local dd = (p[1] - cr) ^ 2 + (p[2] - cg) ^ 2 + (p[3] - cb) ^ 2
      if dd < bd then best, bd = p, dd end
    end
    return best[1], best[2], best[3], 1
  end)
end

function fx.replace(d, r, from, to)
  local x0, y0, w, h = region(d, r)
  for y = y0, y0 + h - 1 do
    for x = x0, x0 + w - 1 do
      local cr, cg, cb, ca = d:getPixel(x, y)
      if U.sameColor(from, { cr, cg, cb, ca }) then d:setPixel(x, y, to[1], to[2], to[3], to[4]) end
    end
  end
end

-- Moves the region's pixels, wrapping around its edges (handy for scrolling loops)
function fx.shift(d, r, dx, dy)
  local x0, y0, w, h = region(d, r)
  if w == 0 or h == 0 then return end
  local src = d:clone()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      d:setPixel(x0 + (x + dx) % w, y0 + (y + dy) % h, src:getPixel(x0 + x, y0 + y))
    end
  end
  src:release()
end

function fx.clear(d, r)
  local x0, y0, w, h = region(d, r)
  if w == 0 or h == 0 then return end
  d:mapPixel(function() return 0, 0, 0, 0 end, x0, y0, w, h)
end

-- Removes lone pixels with no opaque neighbour (stray specks after rotating parts)
function fx.despeckle(d, r)
  local x0, y0, w, h = region(d, r)
  local src = d:clone()
  for y = y0, y0 + h - 1 do
    for x = x0, x0 + w - 1 do
      if alpha(src, x, y) > 0 then
        local n = 0
        for oy = -1, 1 do
          for ox = -1, 1 do
            if (ox ~= 0 or oy ~= 0) and alpha(src, x + ox, y + oy) > 0 then n = n + 1 end
          end
        end
        if n == 0 then d:setPixel(x, y, 0, 0, 0, 0) end
      end
    end
  end
  src:release()
end

return fx
