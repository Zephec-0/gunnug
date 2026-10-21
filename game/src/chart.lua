-- The Cartographer's chart: an old, weathered map of the Barrens and what lies under them. It is not to scale.
-- Places are drawn on it as they are discovered, and what is discovered is kept on the save profile (src.meta's
-- "seen" lists: areas the hunter has reached, and the surface places he has walked past), so the chart carries
-- from run to run.
local meta = require("src.meta")

local chart = {}

-- Surface places: where on the world's x axis they lie (the hunter finds one by walking within REACH of it)
local REACH = 260
chart.PLACES = {
  { id = "farwest", name = "Far Mesas", x = -2000, cx = 0.05, kind = "mesa" },
  { id = "lake", name = "The Drowned Lake", x = -900, cx = 0.17, kind = "lake" },
  { id = "westmesa", name = "West Mesa", x = 356, cx = 0.30, kind = "mesa" },
  { id = "camp", name = "Camp", x = 1000, cx = 0.39, kind = "camp" },
  { id = "oasis", name = "Oasis", x = 1348, cx = 0.46, kind = "pond" },
  { id = "mine", name = "Old Mine", x = 1659, cx = 0.53, kind = "derrick" },
  { id = "ruins", name = "Ruins", x = 2390, cx = 0.61, kind = "arch" },
  { id = "quarry", name = "Quarry Crevice", x = 4300, cx = 0.74, kind = "crevice" },
  { id = "mountain", name = "The Mountain", x = 6320, cx = 0.90, kind = "mountain" },
}

-- Areas under the ground: where each sits on the chart (cx, cy as fractions of the page), by layout index
chart.AREAS = {
  [1] = { cx = 0.46, cy = 0.42 },
  [2] = { cx = 0.46, cy = 0.55 },
  [3] = { cx = 0.46, cy = 0.68 },
  [4] = { cx = 0.34, cy = 0.81 },
  [5] = { cx = 0.58, cy = 0.81 },
  [12] = { cx = 0.34, cy = 0.93 },
  [13] = { cx = 0.58, cy = 0.93 },
  [6] = { cx = 0.76, cy = 0.45 },
  [7] = { cx = 0.76, cy = 0.62 },
  [8] = { cx = 0.15, cy = 0.45 },
  [9] = { cx = 0.15, cy = 0.64 },
  [10] = { cx = 0.90, cy = 0.20 },
  [11] = { cx = 0.80, cy = 0.06 },
}
-- Each area is reached from another: the chart draws a trail between them once both are known
local PARENTS = { [2] = 1, [3] = 2, [4] = 3, [5] = 3, [12] = 4, [13] = 5, [7] = 6, [9] = 8, [11] = 10 }
local SURFACE_Y = 0.27

-- Notes the places the hunter is near (called a few times a second with his position; only the surface counts)
local timer = 0
function chart.update(dt, px, py)
  timer = timer - dt
  if timer > 0 then
    return
  end
  timer = 0.5
  if py > 700 then
    return
  end
  for _, p in ipairs(chart.PLACES) do
    if math.abs(px - p.x) < REACH and not meta.isSeen("place", p.id) then
      meta.see("place", p.id)
    end
  end
end

local function areaKnown(i)
  return meta.isSeen("area", i)
end

local function placeKnown(id)
  return meta.isSeen("place", id)
end

-- How many places and areas are charted, and in all
function chart.progress()
  local n, total = 0, #chart.PLACES
  for _, p in ipairs(chart.PLACES) do
    if placeKnown(p.id) then
      n = n + 1
    end
  end
  for i in pairs(chart.AREAS) do
    total = total + 1
    if areaKnown(i) then
      n = n + 1
    end
  end
  return n, total
end

local INK = { 0.24, 0.13, 0.06 }
local INK_L = { 0.42, 0.27, 0.14 }

-- A wobbling closed outline around (cx, cy), radius rx x ry
local function blob(cx, cy, rx, ry, seed)
  local pts = {}
  local rng = love.math.newRandomGenerator(seed)
  for i = 0, 15 do
    local a = i / 16 * math.pi * 2
    local k = 0.82 + rng:random() * 0.3
    pts[#pts + 1] = cx + math.cos(a) * rx * k
    pts[#pts + 1] = cy + math.sin(a) * ry * k
  end
  return pts
end

local function ink(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

-- Draws a small picture of a surface place standing on the ground line at (x, y); s = pixel size
local function drawPlaceIcon(kind, x, y, s)
  ink(INK)
  love.graphics.setLineWidth(math.max(1, s * 0.5))
  if kind == "camp" then
    love.graphics.polygon("line", x - 5 * s, y, x, y - 7 * s, x + 5 * s, y)
    love.graphics.line(x, y - 7 * s, x, y)
    ink({ 0.65, 0.2, 0.1 })
    love.graphics.polygon("fill", x + 7 * s, y, x + 8 * s, y - 3 * s, x + 9 * s, y)
  elseif kind == "pond" then
    ink({ 0.28, 0.40, 0.48 })
    love.graphics.ellipse("fill", x, y + s, 7 * s, 2 * s)
    ink(INK)
    love.graphics.ellipse("line", x, y + s, 7 * s, 2 * s)
    love.graphics.line(x + 8 * s, y, x + 8 * s, y - 6 * s)
    love.graphics.line(x + 8 * s, y - 4 * s, x + 11 * s, y - 6 * s)
  elseif kind == "derrick" then
    love.graphics.polygon("line", x - 4 * s, y, x, y - 10 * s, x + 4 * s, y)
    love.graphics.line(x - 2 * s, y - 5 * s, x + 2 * s, y - 5 * s)
    love.graphics.circle("line", x, y - 10 * s, s)
  elseif kind == "arch" then
    love.graphics.line(x - 5 * s, y, x - 5 * s, y - 6 * s)
    love.graphics.line(x + 5 * s, y, x + 5 * s, y - 6 * s)
    love.graphics.arc("line", "open", x, y - 6 * s, 5 * s, math.pi, math.pi * 2)
  elseif kind == "mesa" then
    love.graphics.polygon("line", x - 8 * s, y, x - 6 * s, y - 6 * s, x + 6 * s, y - 6 * s, x + 8 * s, y)
    love.graphics.line(x - 6 * s, y - 3 * s, x + 6 * s, y - 3 * s)
  elseif kind == "lake" then
    ink({ 0.28, 0.40, 0.48 })
    for i = 0, 2 do
      love.graphics.arc("line", "open", x - 6 * s + i * 6 * s, y, 3 * s, math.pi * 1.1, math.pi * 1.9)
    end
  elseif kind == "crevice" then
    love.graphics.line(x - 5 * s, y, x - 1 * s, y + 2 * s, x + 1 * s, y - 1 * s, x + 5 * s, y + 3 * s)
  elseif kind == "mountain" then
    love.graphics.polygon("line", x - 12 * s, y, x - 3 * s, y - 14 * s, x, y - 9 * s, x + 4 * s, y - 16 * s, x + 14 * s, y)
    love.graphics.line(x + 4 * s, y - 16 * s, x + 2 * s, y - 11 * s, x + 6 * s, y - 11 * s)
  end
end

-- The page: x, y, w, h in screen px; u = px per game pixel; F the menu's fonts. Returns nothing.
function chart.draw(x, y, w, h, u, F)
  local rng = love.math.newRandomGenerator(7)
  love.graphics.push("all")
  love.graphics.setScissor(x, y, w, h)
  -- the paper, then its stains, folds and burnt edges
  love.graphics.setColor(0.80, 0.68, 0.45)
  love.graphics.rectangle("fill", x, y, w, h)
  for i = 1, 70 do
    local bx, by = x + rng:random() * w, y + rng:random() * h
    local r = (6 + rng:random() * 30) * u
    local k = rng:random()
    love.graphics.setColor(0.55 + k * 0.1, 0.40 + k * 0.08, 0.20, 0.05 + rng:random() * 0.07)
    love.graphics.polygon("fill", blob(bx, by, r, r * (0.6 + rng:random() * 0.5), 100 + i))
  end
  -- a water stain with a darker rim
  love.graphics.setColor(0.45, 0.32, 0.15, 0.10)
  love.graphics.setLineWidth(math.max(1, u))
  love.graphics.polygon("line", blob(x + w * 0.72, y + h * 0.78, w * 0.12, h * 0.1, 900))
  -- folds
  love.graphics.setColor(0.35, 0.24, 0.12, 0.25)
  love.graphics.setLineWidth(math.max(1, u * 0.6))
  love.graphics.line(x + w / 2, y, x + w / 2 + u, y + h)
  love.graphics.line(x, y + h / 2, x + w, y + h / 2 - u)
  love.graphics.setColor(1, 0.95, 0.8, 0.12)
  love.graphics.line(x + w / 2 + 2 * u, y, x + w / 2 + 3 * u, y + h)
  -- burnt, darkened edges
  for i = 0, 10 do
    local a = 0.20 * (1 - i / 11) ^ 2
    love.graphics.setColor(0.18, 0.09, 0.03, a)
    local t = i * 2.2 * u
    love.graphics.rectangle("fill", x, y, w, t)
    love.graphics.rectangle("fill", x, y + h - t, w, t)
    love.graphics.rectangle("fill", x, y, t, h)
    love.graphics.rectangle("fill", x + w - t, y, t, h)
  end

  local function px(fx)
    return x + fx * w
  end
  local function py(fy)
    return y + fy * h
  end

  -- the ground line, wandering across the page with a hatching of earth under it
  love.graphics.setLineWidth(math.max(1, u * 0.7))
  ink(INK)
  local groundPts = {}
  for i = 0, 40 do
    local fx = i / 40
    groundPts[#groundPts + 1] = px(fx)
    groundPts[#groundPts + 1] = py(SURFACE_Y) + math.sin(fx * 23 + 1) * 1.2 * u + math.sin(fx * 7) * 1.6 * u
  end
  love.graphics.line(groundPts)
  ink(INK_L, 0.5)
  for i = 0, 60 do
    local fx = i / 60
    local gy = py(SURFACE_Y) + math.sin(fx * 23 + 1) * 1.2 * u + math.sin(fx * 7) * 1.6 * u
    love.graphics.line(px(fx), gy + 2 * u, px(fx) - 2 * u, gy + 4.5 * u)
  end

  -- surface places, drawn once found
  love.graphics.setFont(F.small)
  local s = math.max(1, u * 0.6)
  for _, p in ipairs(chart.PLACES) do
    if placeKnown(p.id) then
      local fx = p.cx
      local gy = py(SURFACE_Y) + math.sin(fx * 23 + 1) * 1.2 * u + math.sin(fx * 7) * 1.6 * u
      drawPlaceIcon(p.kind, px(fx), gy, s)
      ink(INK)
      local tw = F.small:getWidth(p.name)
      love.graphics.print(p.name, math.floor(math.min(x + w - tw - 4 * u, math.max(x + 4 * u, px(fx) - tw / 2))), math.floor(gy - (p.kind == "mountain" and 21 or 17) * s - F.small:getHeight() * 0.4))
    end
  end

  -- trails between the areas that are known, then the areas
  love.graphics.setLineWidth(math.max(1, u * 0.6))
  ink(INK, 0.7)
  for i, parent in pairs(PARENTS) do
    local a, b = chart.AREAS[i], chart.AREAS[parent]
    if a and b and areaKnown(i) and areaKnown(parent) then
      local x0, y0, x1, y1 = px(b.cx), py(b.cy), px(a.cx), py(a.cy)
      local n = math.floor(math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) / (4 * u))
      for k = 0, n, 2 do
        local t0, t1 = k / n, math.min(1, (k + 1) / n)
        love.graphics.line(x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0, x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1)
      end
    end
  end
  -- the shaft down from the Old Mine's place on the surface
  if areaKnown(1) then
    local a = chart.AREAS[1]
    ink(INK, 0.7)
    love.graphics.line(px(0.53), py(SURFACE_Y) + 2 * u, px(a.cx), py(a.cy) - 5 * u)
  end
  for i, a in pairs(chart.AREAS) do
    if areaKnown(i) then
      local theme = require("src.scenes.catacombs").theme(i)
      local name = theme and theme.name or "Unknown"
      local rx, ry = 22 * u, 8 * u
      local pts = blob(px(a.cx), py(a.cy), rx, ry, 40 + i)
      local c = theme and theme.glow or { 0.6, 0.5, 0.3 }
      love.graphics.setColor(c[1] * 0.5 + 0.35, c[2] * 0.5 + 0.28, c[3] * 0.5 + 0.18, 0.55)
      love.graphics.polygon("fill", pts)
      ink(INK)
      love.graphics.setLineWidth(math.max(1, u * 0.7))
      love.graphics.polygon("line", pts)
      -- a little hatching inside, like a cave drawn by hand
      ink(INK_L, 0.55)
      for k = -3, 3 do
        love.graphics.line(px(a.cx) + k * 5 * u, py(a.cy) - 3 * u, px(a.cx) + k * 5 * u - 2 * u, py(a.cy) + 3 * u)
      end
      ink(INK)
      local tw = F.small:getWidth(name)
      love.graphics.print(name, math.floor(px(a.cx) - tw / 2), math.floor(py(a.cy) + ry + u))
    end
  end

  -- a compass rose in the corner and the title
  local cx, cy, cr = x + w - 20 * u, y + h - 20 * u, 11 * u
  ink(INK, 0.8)
  love.graphics.setLineWidth(math.max(1, u * 0.6))
  love.graphics.circle("line", cx, cy, cr * 0.6)
  love.graphics.polygon("fill", cx, cy - cr, cx - cr * 0.18, cy, cx + cr * 0.18, cy)
  love.graphics.polygon("line", cx, cy + cr, cx - cr * 0.18, cy, cx + cr * 0.18, cy)
  love.graphics.line(cx - cr, cy, cx + cr, cy)
  love.graphics.print("N", math.floor(cx - F.small:getWidth("N") / 2), math.floor(cy - cr - F.small:getHeight() - u))
  local n, total = chart.progress()
  local title = "The Barrens and Below"
  ink(INK)
  love.graphics.setFont(F.body)
  love.graphics.print(title, math.floor(x + 8 * u), math.floor(y + 6 * u))
  love.graphics.setFont(F.small)
  ink(INK_L)
  love.graphics.print(n .. " of " .. total .. " places charted. Not to scale.", math.floor(x + 8 * u), math.floor(y + 6 * u + F.body:getHeight() + u))
  love.graphics.setScissor()
  -- a ragged border
  love.graphics.setColor(0.2, 0.1, 0.04, 0.9)
  love.graphics.setLineWidth(math.max(2, u))
  love.graphics.rectangle("line", x, y, w, h)
  love.graphics.pop()
end

return chart
