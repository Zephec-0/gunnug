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
  { id = "lake", name = "The Pond", x = -900, cx = 0.15, kind = "pond" },
  { id = "camp", name = "Camp", x = 1000, cx = 0.35, kind = "camp" },
  { id = "mine", name = "Old Mine Shaft", x = 1659, cx = 0.50, kind = "derrick" },
  { id = "quarry", name = "Quarry Shaft", x = 4300, cx = 0.74, kind = "crevice" },
  { id = "mountain", name = "The Mountain", x = 6320, cx = 0.90, kind = "mountain" },
}

-- Areas under the ground: where each sits on the chart (cx, cy as fractions of the page), by layout index
local SURFACE_Y = 0.27
chart.AREAS = {
  [1] = { cx = 0.46, cy = 0.37 },
  [2] = { cx = 0.46, cy = 0.53 },
  [3] = { cx = 0.46, cy = 0.68 },
  [4] = { cx = 0.34, cy = 0.82 },
  [5] = { cx = 0.58, cy = 0.82 },
  [12] = { cx = 0.34, cy = 0.96 },
  [13] = { cx = 0.58, cy = 0.96 },
  [6] = { cx = 0.76, cy = 0.45 },
  [7] = { cx = 0.76, cy = 0.66 },
  [8] = { cx = 0.15, cy = 0.45 },
  [9] = { cx = 0.15, cy = 0.66 },
  [10] = { cx = 0.90, cy = 0.27 },
  [11] = { cx = 0.80, cy = 0.06 },
}
-- Each area is reached from another: the chart draws a trail between them once both are known
local PARENTS = { [2] = 1, [3] = 2, [4] = 3, [5] = 3, [12] = 4, [13] = 5, [7] = 6, [9] = 8, [11] = 10 }
-- Surface places that open onto an area: the shaft down to it is drawn once both are known
local SHAFTS = { { place = "mine", area = 1 }, { place = "quarry", area = 6 }, { place = "lake", area = 8 } }

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

-- The view: zoom and where the middle of the chart is shifted to (px), changed by the wheel, dragging and the buttons
chart.view = { z = 1, ox = 0, oy = 0 }
local box = { x = 0, y = 0, w = 1, h = 1 }

function chart.inBox(mx, my)
  return mx >= box.x and mx <= box.x + box.w and my >= box.y and my <= box.y + box.h
end

local function clampView()
  local v = chart.view
  v.z = math.max(0.8, math.min(3.2, v.z))
  local lx, ly = box.w * 0.5 * v.z, box.h * 0.5 * v.z
  v.ox = math.max(-lx, math.min(lx, v.ox))
  v.oy = math.max(-ly, math.min(ly, v.oy))
end

-- Zoom by a factor about a screen point (the middle of the box if none)
function chart.zoom(f, mx, my)
  local v = chart.view
  mx, my = mx or box.x + box.w / 2, my or box.y + box.h / 2
  local before = v.z
  v.z = math.max(0.8, math.min(3.2, v.z * f))
  local k = v.z / before
  -- keep the point under the mouse where it was
  local cx, cy = box.x + box.w / 2, box.y + box.h / 2
  v.ox = (mx - cx) - ((mx - cx) - v.ox) * k
  v.oy = (my - cy) - ((my - cy) - v.oy) * k
  clampView()
end

function chart.pan(dx, dy)
  chart.view.ox = chart.view.ox + dx
  chart.view.oy = chart.view.oy + dy
  clampView()
end

function chart.resetView()
  chart.view = { z = 1, ox = 0, oy = 0 }
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
  box.x, box.y, box.w, box.h = x, y, w, h
  local v = chart.view
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

  -- (positions follow the zoom and pan; sizes grow only a little, so the drawing stays crisp)
  local function px(fx)
    return x + w / 2 + v.ox + (fx - 0.5) * w * v.z
  end
  local function py(fy)
    return y + h / 2 + v.oy + (0.04 + fy * 0.86 - 0.5) * h * v.z
  end
  local grow = 0.7 + 0.3 * v.z

  local function groundAt(fx)
    return py(SURFACE_Y) + (math.sin(fx * 23 + 1) * 1.2 + math.sin(fx * 7) * 1.6) * u
  end
  -- the ground line, wandering across the page (and past it, for the zoom) with a hatching of earth under it
  love.graphics.setLineWidth(math.max(1, u * 0.7))
  ink(INK)
  local groundPts = {}
  for i = -20, 60 do
    local fx = i / 40
    groundPts[#groundPts + 1] = px(fx)
    groundPts[#groundPts + 1] = groundAt(fx)
  end
  love.graphics.line(groundPts)
  ink(INK_L, 0.5)
  for i = -30, 90 do
    local fx = i / 60
    local gy = groundAt(fx)
    love.graphics.line(px(fx), gy + 2 * u, px(fx) - 2 * u, gy + 4.5 * u)
  end

  love.graphics.setFont(F.small)
  local s = math.max(1, u * 0.6) * grow
  local function label(text, cx, ty)
    local tw, th = F.small:getWidth(text), F.small:getHeight()
    -- (a patch of paper behind the words, so a trail or a picture passing under them never muddles the text)
    love.graphics.setColor(0.80, 0.68, 0.45, 0.88)
    love.graphics.rectangle("fill", math.floor(cx - tw / 2) - u, math.floor(ty), tw + 2 * u, th)
    ink(INK)
    love.graphics.print(text, math.floor(cx - tw / 2), math.floor(ty))
  end

  -- trails between the areas that are known: dotted lines, so it is plain what leads to what
  local function trail(x0, y0, x1, y1)
    local n = math.max(2, math.floor(math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) / (4 * u)))
    for k = 0, n, 2 do
      local t0, t1 = k / n, math.min(1, (k + 1) / n)
      love.graphics.line(x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0, x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1)
    end
  end
  love.graphics.setLineWidth(math.max(1, u * 0.6))
  ink(INK, 0.7)
  for i, parent in pairs(PARENTS) do
    local a, b = chart.AREAS[i], chart.AREAS[parent]
    if a and b and areaKnown(i) and areaKnown(parent) then
      trail(px(b.cx), py(b.cy), px(a.cx), py(a.cy))
    end
  end
  -- the shafts down from the surface (the lake drains into the Flooded Caverns)
  for _, sh in ipairs(SHAFTS) do
    local place
    for _, p in ipairs(chart.PLACES) do
      if p.id == sh.place then
        place = p
      end
    end
    local a = chart.AREAS[sh.area]
    if place and a and placeKnown(place.id) and areaKnown(sh.area) then
      trail(px(place.cx), groundAt(place.cx) + 2 * u, px(a.cx), py(a.cy) - 5 * u)
    end
  end

  -- surface places, drawn once found (the mountain is also the Needle, once its way up has been climbed)
  for _, p in ipairs(chart.PLACES) do
    local needle = p.id == "mountain" and areaKnown(10)
    if placeKnown(p.id) or needle then
      local gy = groundAt(p.cx)
      drawPlaceIcon(p.kind, px(p.cx), gy, s)
      ink(INK)
      label(needle and "The Needle" or p.name, px(p.cx), gy - (p.kind == "mountain" and 21 or 17) * s - F.small:getHeight() * 0.4)
    end
  end
  -- the sky above the mountain, once reached
  if areaKnown(11) then
    local a = chart.AREAS[11]
    if areaKnown(10) then
      trail(px(chart.AREAS[10].cx), groundAt(0.9) - 16 * s, px(a.cx), py(a.cy) + 6 * u)
    end
  end

  -- the areas under the ground (the Needle is the mountain itself, above)
  for i, a in pairs(chart.AREAS) do
    if areaKnown(i) and i ~= 10 then
      local theme = require("src.scenes.catacombs").theme(i)
      local name = theme and theme.name or "Unknown"
      local rx, ry = 22 * u * grow, 6.5 * u * grow
      local pts = blob(px(a.cx), py(a.cy), rx, ry, 40 + i)
      local c = theme and theme.glow or { 0.6, 0.5, 0.3 }
      love.graphics.setColor(c[1] * 0.5 + 0.35, c[2] * 0.5 + 0.28, c[3] * 0.5 + 0.18, 0.55)
      love.graphics.polygon("fill", pts)
      ink(INK)
      love.graphics.setLineWidth(math.max(1, u * 0.7))
      love.graphics.polygon("line", pts)
      ink(INK_L, 0.55)
      for k = -3, 3 do
        love.graphics.line(px(a.cx) + k * 5 * u * grow, py(a.cy) - 3 * u * grow, px(a.cx) + k * 5 * u * grow - 2 * u, py(a.cy) + 3 * u * grow)
      end
      ink(INK)
      label(name, px(a.cx), py(a.cy) + ry + u)
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
  love.graphics.print(n .. " of " .. total .. " places charted.", math.floor(x + 8 * u), math.floor(y + 6 * u + F.body:getHeight() + u))
  love.graphics.setScissor()
  -- a ragged border
  love.graphics.setColor(0.2, 0.1, 0.04, 0.9)
  love.graphics.setLineWidth(math.max(2, u))
  love.graphics.rectangle("line", x, y, w, h)
  love.graphics.pop()
end

return chart
