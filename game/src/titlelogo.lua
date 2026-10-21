-- The title mark: GUNNUG is a palindrome, so it is built as GUN, a revolver
-- cylinder, and GUN again mirrored. Drawn as a tiny pixel bitmap, scaled up.
local M = { PX = 2 }

local GLYPHS = {
  G = { "..#####..", ".##...##.", "##.....##", "##.......", "##.......", "##..#####", "##..#####", "##.....##", "##.....##", ".##...##.", "..#####.." },
  U = { "##.....##", "##.....##", "##.....##", "##.....##", "##.....##", "##.....##", "##.....##", "##.....##", ".##...##.", ".#######.", "..#####.." },
  N = { "###....##", "####...##", "####...##", "##.##..##", "##.##..##", "##..##.##", "##..##.##", "##...####", "##...####", "##....###", "##.....##" },
}

local W, H = 93, 25 -- logical size (the image gets one extra row/column for the shadow)
local CREAM = { 0.91, 0.86, 0.75 }
local SHADE = { 0.13, 0.09, 0.15 }
local BRASS = { 0.79, 0.63, 0.35 }
local BRASS_DK = { 0.50, 0.37, 0.20 }
local BRASS_HI = { 0.95, 0.82, 0.52 }
local STEEL = { 0.22, 0.19, 0.26 }
local HOLE = { 0.07, 0.05, 0.09 }

local image

local function build()
  local data = love.image.newImageData(W + 1, H + 1)
  local function put(x, y, c)
    if x >= 0 and x <= W and y >= 0 and y <= H then
      data:setPixel(x, y, c[1], c[2], c[3], 1)
    end
  end

  -- Letters: shadow pass first, then the letters, left group and its mirror
  local function letters(c, dx, dy)
    local x0 = 0
    for ch in ("GUN"):gmatch(".") do
      for ry, row in ipairs(GLYPHS[ch]) do
        for rx = 1, 9 do
          if row:sub(rx, rx) == "#" then
            local x, y = x0 + rx - 1, 7 + ry - 1
            put(x + dx, y + dy, c)
            put(W - 1 - x + dx, y + dy, c)
          end
        end
      end
      x0 = x0 + 11
    end
  end
  letters(SHADE, 1, 1)

  -- Cylinder: steel disc with a brass rim, six chambers, one just fired
  local cx, cy = 46, 12
  local function disc(r, c, ox, oy)
    for y = 0, H - 1 do
      for x = cx - 13, cx + 13 do
        if (x - cx) ^ 2 + (y - cy) ^ 2 <= r * r then
          put(x + (ox or 0), y + (oy or 0), c)
        end
      end
    end
  end
  disc(12.5, SHADE, 1, 1)
  disc(12.5, BRASS)
  disc(10.6, BRASS_DK)
  disc(9.8, STEEL)
  for y = 0, H - 1 do
    for x = cx - 13, cx + 13 do
      local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
      if d > 10.6 and d <= 12.5 and (x - cx) + (y - cy) < -4 then
        put(x, y, BRASS_HI)
      end
    end
  end
  local function circle(x, y, r, c)
    for oy = -math.ceil(r), math.ceil(r) do
      for ox = -math.ceil(r), math.ceil(r) do
        if ox * ox + oy * oy <= r * r then
          put(x + ox, y + oy, c)
        end
      end
    end
  end
  circle(cx, cy, 2.4, BRASS)
  circle(cx, cy, 0.5, BRASS_DK)

  letters(CREAM, 0, 0)

  image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
end

-- The chambers (and the flutes between them) are drawn live so the cylinder
-- can turn. Every PERIOD seconds it winds back a hair, then snaps round one
-- chamber and rattles to rest on a damped spring. All six are empty. Shapes
-- are sampled at 4x4 sub-pixels, so the turn glides between logo pixels; at
-- rest they are snapped back to crisp, whole pixels.
local PERIOD, WIND, SETTLE = 2.4, 0.07, 0.34
local CX, CY = 46, 12
local SUB = 4
local SIXTH = math.pi / 3

local function clamp01(v)
  return v < 0 and 0 or (v > 1 and 1 or v)
end

-- How far through the click: 0 at the start position, 1 at the next chamber.
-- Returns that, and how crisp (1 = whole pixels) the shapes should be.
local function click()
  local t = love.timer.getTime() % PERIOD
  if t >= WIND + SETTLE then
    return 1, 1
  end
  if t < WIND then
    return -0.08 * math.sin(math.pi * t / WIND), 1 - clamp01(t / (WIND * 0.6))
  end
  local k = t - WIND
  return 1 - math.exp(-22 * k) * math.cos(30 * k), clamp01((k - 0.14) / 0.16)
end

-- A disc of radius r at (x, y) (pixel-edge coordinates), as per-pixel coverage
local function disc(x, y, r, scale, ox, oy, crisp)
  local x0, x1 = math.floor(x - r), math.ceil(x + r) - 1
  local y0, y1 = math.floor(y - r), math.ceil(y + r) - 1
  local r2 = r * r
  for py = y0, y1 do
    for px = x0, x1 do
      local hit = 0
      for sy = 0, SUB - 1 do
        local dy = py + (sy + 0.5) / SUB - y
        for sx = 0, SUB - 1 do
          local dx = px + (sx + 0.5) / SUB - x
          if dx * dx + dy * dy <= r2 then
            hit = hit + 1
          end
        end
      end
      local cov = hit / (SUB * SUB)
      cov = cov + ((cov >= 0.5 and 1 or 0) - cov) * crisp
      if cov > 0 then
        local c = M._color
        love.graphics.setColor(c[1], c[2], c[3], cov)
        love.graphics.rectangle("fill", ox + px * scale, oy + py * scale, scale, scale)
      end
    end
  end
end

local function ringPos(angle, radius)
  return CX + 0.5 + math.cos(angle) * radius, CY + 0.5 + math.sin(angle) * radius
end

-- One ring of six shapes: it starts on the grid at `base` and ends, a sixth of
-- a turn on, on the grid again, gliding between the two
local function ring(f, crisp, radius, base, r, color, scale, x, y)
  M._color = color
  local s = clamp01(f)
  for i = 0, 5 do
    local a0 = base + i * SIXTH
    local fx, fy = ringPos(a0 + f * SIXTH, radius)
    local x0, y0 = ringPos(a0, radius)
    local x1, y1 = ringPos(a0 + SIXTH, radius)
    -- the grid-snapped end points are the ones whole-pixel shapes sit on
    local cx = fx + (math.floor(x0) + 0.5 - x0) * (1 - s) + (math.floor(x1) + 0.5 - x1) * s
    local cy = fy + (math.floor(y0) + 0.5 - y0) * (1 - s) + (math.floor(y1) + 0.5 - y1) * s
    disc(cx, cy, r, scale, x, y, crisp)
  end
end

-- Size in logo pixels (the shadow is not counted)
M.W, M.H = W, H

-- Just the shape, in the current colour (for casting shadows)
function M.silhouette(x, y, scale)
  if not image then
    build()
  end
  love.graphics.draw(image, x, y, 0, scale, scale)
end

-- Draw with its top-left at (x, y); `scale` is screen pixels per logo pixel
function M.draw(x, y, scale)
  if not image then
    build()
  end
  love.graphics.setColor(1, 1, 1)
  x, y = math.floor(x), math.floor(y)
  love.graphics.draw(image, x, y, 0, scale, scale)
  local f, crisp = click()
  ring(f, crisp, 9.2, -math.pi / 3 + math.pi / 6, 1.0, BRASS_DK, scale, x, y)
  ring(f, crisp, 6.4, -math.pi / 3, 2.7, HOLE, scale, x, y)
  love.graphics.setColor(1, 1, 1)
end

-- The cylinder alone, as an app icon: size x size pixels, transparent around it, the click at rest
function M.iconData(size)
  local scale = math.max(1, math.floor(size * 0.92 / 27))
  local canvas = love.graphics.newCanvas(size, size)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  local cw, ch = 28 * scale, 26 * scale -- (the cylinder's 27 x 25 pixels and its shadow)
  local ox, oy = math.floor((size - cw) / 2), math.floor((size - ch) / 2)
  love.graphics.setScissor(ox, oy, cw, ch)
  local real = love.timer.getTime
  love.timer.getTime = function() return 1 end
  M.draw(ox - 33 * scale, oy, scale)
  love.timer.getTime = real
  love.graphics.setScissor()
  love.graphics.pop()
  return canvas:newImageData()
end

return M
