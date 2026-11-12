-- The camp people's pages, each its own picture (the menu's camp page hands over to these):
--   The Sawbone      a Leonardo-style study of the hunter's body: click a part to have it taken
--   The Gunsmith     his pegboard wall of guns (buy, teach), a drawer of parts, his tools
--   The Apothecary   a herbalist's field notes: a heart and a flask, pressed leaves for the tiers
--   The Taxidermist  his trophy wall: a plaque per kind of elite, a brass nail per level
--   The Prospector   his open strongbox with the gold piled in it, tools on the wall, the shelf
-- Everything is drawn through the menu's own helpers (t, built in src.menu's camp page) so they share its
-- scale, fonts, focus and hit testing. Each function draws below the page's title and returns nothing.
local audio = require("src.audio")
local compendium = require("src.compendium")
local meta = require("src.meta")

local pages = {}

local INK = { 0.20, 0.12, 0.07 }
local INK_FAINT = { 0.20, 0.12, 0.07, 0.45 }
local RED = { 0.78, 0.18, 0.14 }
local GREEN = { 0.30, 0.55, 0.25 }

local floor, max, min = math.floor, math.max, math.min

local function PS(u)
  return require("src.render").cell()
end

-- The page's one art pixel, in screen pixels (set as each page starts): every outline, shadow edge, highlight and bit of
-- pixel art on these pages is a whole number of them, so the line weight and the size of a "pixel" are the same on all
local AP = 1

-- A filled rectangle with both edges snapped to the screen's pixels (so a thin bar is the same thickness wherever it
-- falls, instead of 1 px or 2 depending on the fractions of its position and size)
local function R(x, y, w, h)
  local x0, y0 = floor(x + 0.5), floor(y + 0.5)
  local x1, y1 = floor(x + w + 0.5), floor(y + h + 0.5)
  if x1 <= x0 and w > 0 then
    x1 = x0 + 1
  end
  if y1 <= y0 and h > 0 then
    y1 = y0 + 1
  end
  love.graphics.rectangle("fill", x0, y0, x1 - x0, y1 - y0)
end

local function col(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1))
end

-- One line thickness for every page (the menu's own panels use the same): a whole number of screen pixels
local function lineWidth(t)
  love.graphics.setLineWidth(AP)
end

-- Plain ink text (no drop shadow: it sits on paper)
local function ink(text, x, y, f, color, alpha)
  love.graphics.setFont(f)
  col(color or INK, alpha or 0.92)
  love.graphics.print(text, floor(x), floor(y))
end

-- A sheet of old paper: yellowed, darker toward the edges, stained, with a fold down the middle
local function paper(t, x, y, w, h, seed)
  local u = t.u
  AP = PS(u)
  t.cast(x, y, w, h)
  love.graphics.setColor(0.25, 0.17, 0.10)
  R(x - AP, y - AP, w + 2 * AP, h + 2 * AP)
  love.graphics.setColor(0.74, 0.62, 0.42)
  R(x, y, w, h)
  love.graphics.setColor(0.84, 0.73, 0.53)
  R(x + 2 * u, y + 2 * u, w - 4 * u, h - 4 * u)
  love.graphics.setColor(0.90, 0.80, 0.60)
  R(x + 5 * u, y + 5 * u, w - 10 * u, h - 10 * u)
  local rng = love.math.newRandomGenerator(seed or 1)
  for _ = 1, 9 do
    love.graphics.setColor(0.55, 0.38, 0.18, 0.06 + rng:random() * 0.05)
    love.graphics.circle("fill", x + rng:random() * w, y + rng:random() * h, (3 + rng:random() * 9) * u)
  end
  love.graphics.setColor(0.45, 0.32, 0.16, 0.14)
  R(x + floor(w / 2), y, AP, h)
  love.graphics.setColor(1, 1, 1, 0.08)
  R(x + floor(w / 2) + AP, y, AP, h)
end

-- A dashed line (for what has been cut away)
local function dashed(x1, y1, x2, y2, dash)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  local n = max(1, floor(len / dash))
  for i = 0, n - 1, 2 do
    local a, b = i / n, min(1, (i + 1) / n)
    love.graphics.line(x1 + dx * a, y1 + dy * a, x1 + dx * b, y1 + dy * b)
  end
end

local function dashedPoly(pts, dash)
  for i = 1, #pts do
    local a, b = pts[i], pts[i % #pts + 1]
    dashed(a[1], a[2], b[1], b[2], dash)
  end
end

local function polyPoints(pts)
  local flat = {}
  for _, p in ipairs(pts) do
    flat[#flat + 1] = p[1]
    flat[#flat + 1] = p[2]
  end
  return flat
end

-- One slim upgrade row: name, a pip per tier, price (or Done). Returns whether it has the focus.
local function upgradeRow(t, up, x, y, w, h)
  local u, F = t.u, t.F
  AP = PS(u)
  local marks = meta.marks()
  local tier, cost = meta.tier(up.id), meta.nextCost(up.id)
  local focused = t.widget({ id = "camp:up:" .. up.id, x = x, y = y, w = w, h = h, activate = function()
    if meta.buy(up.id) then
      audio.play("buy")
    else
      audio.play("deny")
    end
  end })
  t.panel(x, y, w, h, focused and 0.95 or 0.82)
  if focused then
    t.focusFrame(x, y, w, h)
  end
  local ty = y + (h - F.body:getHeight()) / 2
  t.shadowPrint(up.name, x + 5 * u, ty, F.body, focused and t.TEXT or t.DIM)
  local px = x + 5 * u + F.body:getWidth(up.name) + 4 * u
  for k = 1, #up.costs do
    love.graphics.setColor(k <= tier and t.WARM or { 0.25, 0.22, 0.3 })
    R(px + (k - 1) * 4 * u, ty + F.body:getHeight() / 2 - 1.2 * u, math.ceil(2.6 * u), math.ceil(2.6 * u))
  end
  if cost then
    t.markPrice(tostring(cost), x + w - 4 * u, ty, F.body, marks >= cost and meta.SIGIL_COLOR or t.DANGER)
  else
    t.shadowPrint("Done", x + w - 4 * u - F.body:getWidth("Done"), ty, F.body, t.FAINT)
  end
  return focused
end

local function upgradesFor(npc)
  local out = {}
  for _, up in ipairs(meta.UPGRADES) do
    if up.npc == npc then
      out[#out + 1] = up
    end
  end
  return out
end

-- A card of words about whatever is hovered: a title (with a price at its right), then wrapped lines
local function infoCard(t, x, y, w, h, title, titleColor, price, priceColor, lines)
  local u, F = t.u, t.F
  AP = PS(u)
  t.panel(x, y, w, h, 0.85)
  if not title then
    return
  end
  t.shadowPrint(title, x + 5 * u, y + 3 * u, F.body, titleColor or t.TEXT)
  if price then
    t.markPrice(price, x + w - 5 * u, y + 3 * u, F.body, priceColor)
  end
  local ty = y + 3 * u + F.body:getHeight() + u
  for _, ln in ipairs(lines or {}) do
    local used = t.wrapped(ln[1], x + 5 * u, ty, w - 10 * u, F.small, ln[2] or t.DIM)
    ty = ty + used + 0.5 * u
  end
end

-- ===================================================================================================
-- The Sawbone: a study of the body
-- ===================================================================================================

-- hit: a box in figure units { x, y, w, h }; label: where its name goes { x, y, align }; lead: leader line
local PARTS = {
  eye = { hit = { -6, 5, 12, 11 }, label = { 15, 3, "l" }, lead = { 7, 10, 14, 8 } },
  ear = { hit = { -15, 6, 8, 13 }, label = { -18, 6, "r" }, lead = { -10, 12, -17, 11 } },
  arm = { hit = { -64, 28, 46, 19 }, label = { -64, 50, "l" }, lead = { -50, 42, -50, 49 } },
  leg = { hit = { -18, 78, 17, 58 }, label = { -22, 104, "r" }, lead = { -14, 104, -21, 108 } },
  spleen = { hit = { 3, 41, 13, 11 }, label = { 22, 47, "l" }, lead = { 15, 48, 21, 50 } },
  kidney = { hit = { -14, 56, 13, 12 }, label = { -19, 60, "r" }, lead = { -13, 62, -18, 64 } },
}

-- The anatomy sheet figure: a Vitruvian man in pixel art (two pairs of arms and legs inside the circle and the square),
-- painted once into an image, a cell per art pixel. Shapes are painted back to front, each with its own outline; a
-- shape shade runs from lit (upper left) to shadowed (lower right).
local OUTLINE = { 0.30, 0.14, 0.06 }
local SKIN = { { 0.99, 0.87, 0.60 }, { 0.95, 0.75, 0.45 }, { 0.84, 0.58, 0.30 }, { 0.68, 0.43, 0.20 } }
local HAIR = { { 0.86, 0.60, 0.28 }, { 0.68, 0.42, 0.18 }, { 0.46, 0.26, 0.10 } }
local CLOTH = { { 0.97, 0.86, 0.64 }, { 0.88, 0.70, 0.44 }, { 0.72, 0.52, 0.30 } }
local LIGHT = { -0.55, -0.83 }

local function hash2(x, y)
  local n = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
  return n - floor(n)
end

local function inPoly(pts, x, y)
  local inside = false
  local j = #pts
  for i = 1, #pts do
    local xi, yi, xj, yj = pts[i][1], pts[i][2], pts[j][1], pts[j][2]
    if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then
      inside = not inside
    end
    j = i
  end
  return inside
end

-- cover functions: (x, y) -> shade 0..1 (0 lit) or nil outside
local function capsule(ax, ay, bx, by, r0, r1)
  local dx, dy = bx - ax, by - ay
  local len2 = dx * dx + dy * dy
  return function(x, y)
    local t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / len2))
    local qx, qy = ax + dx * t, ay + dy * t
    local r = r0 + (r1 - r0) * t
    local ox, oy = x - qx, y - qy
    local d = math.sqrt(ox * ox + oy * oy)
    if d > r then
      return nil
    end
    local light = (ox * LIGHT[1] + oy * LIGHT[2]) / max(r, 0.01)
    return 0.5 - 0.5 * light
  end
end

local function ellipseShape(cx, cy, rx, ry)
  return function(x, y)
    local ox, oy = (x - cx) / rx, (y - cy) / ry
    if ox * ox + oy * oy > 1 then
      return nil
    end
    return 0.5 - 0.5 * (ox * LIGHT[1] + oy * LIGHT[2])
  end
end

local function polyShape(pts, x0, x1)
  return function(x, y)
    if not inPoly(pts, x, y) then
      return nil
    end
    return 0.30 + 0.5 * ((x - x0) / (x1 - x0))
  end
end

local function buildFigure(cp)
  local X0, Y0, X1, Y1 = -76, -8, 76, 142
  local nx, ny = math.ceil((X1 - X0) / cp), math.ceil((Y1 - Y0) / cp)
  local data = love.image.newImageData(nx, ny)
  local function ux(i)
    return X0 + (i + 0.5) * cp
  end
  local function uy(j)
    return Y0 + (j + 0.5) * cp
  end
  local function put(i, j, c, a)
    data:setPixel(i, j, c[1], c[2], c[3], a or 1)
  end
  -- paints one shape: its outline, then its interior through colorOf(v, x, y, i, j)
  local function paint(cover, colorOf)
    local mask = {}
    for j = 0, ny - 1 do
      for i = 0, nx - 1 do
        local v = cover(ux(i), uy(j))
        if v then
          mask[j * nx + i] = v
        end
      end
    end
    for j = 0, ny - 1 do
      for i = 0, nx - 1 do
        local v = mask[j * nx + i]
        if v then
          local edge = i == 0 or j == 0 or not mask[j * nx + i - 1] or not mask[j * nx + i + 1] or not mask[(j - 1) * nx + i] or not mask[(j + 1) * nx + i]
          if edge then
            put(i, j, OUTLINE)
          else
            put(i, j, colorOf(v, ux(i), uy(j), i, j))
          end
        end
      end
    end
  end
  local function skin(v)
    return SKIN[v < 0.30 and 1 or (v < 0.55 and 2 or (v < 0.80 and 3 or 4))]
  end
  local function ramp(set)
    return function(v, x, y, i, j)
      local k = v < 0.35 and 1 or (v < 0.7 and 2 or 3)
      local h = hash2(i, j)
      if h < 0.18 and k > 1 then
        k = k - 1
      elseif h > 0.88 and k < 3 then
        k = k + 1
      end
      return set[k]
    end
  end
  -- single-cell strokes over what is already painted: fn(x, y) -> true
  local function mark(fn, c)
    for j = 0, ny - 1 do
      for i = 0, nx - 1 do
        if fn(ux(i), uy(j)) then
          local _, _, _, a = data:getPixel(i, j)
          if a > 0 then
            put(i, j, c)
          end
        end
      end
    end
  end
  -- the circle and the square, in ink
  for j = 0, ny - 1 do
    for i = 0, nx - 1 do
      local x, y = ux(i), uy(j)
      local ring = math.abs(math.sqrt(x * x + (y - 68) ^ 2) - 72) < cp * 0.55
      local sq = (math.abs(math.abs(x) - 62) < cp * 0.55 and y >= -4 and y <= 134) or ((math.abs(y + 4) < cp * 0.55 or math.abs(y - 134) < cp * 0.55) and math.abs(x) <= 62)
      if ring or sq then
        put(i, j, OUTLINE, 0.85)
      end
    end
  end
  -- limbs behind: the raised arms and the spread legs
  for _, m in ipairs({ -1, 1 }) do
    paint(capsule(m * 16, 33, m * 58, 4, 5.4, 3.0), skin)
    paint(ellipseShape(m * 60, 2.5, 3.2, 2.6), skin)
    paint(capsule(m * 8, 79, m * 40, 130, 7.2, 3.8), skin)
    paint(ellipseShape(m * 42, 132, 5.5, 2.4), skin)
  end
  -- hair behind the head, down to the shoulders
  local hairShapes = { ellipseShape(0, 11, 11.8, 12), ellipseShape(-9.6, 21, 3.4, 7), ellipseShape(9.6, 21, 3.4, 7), ellipseShape(-7.5, 4, 4, 3.5), ellipseShape(7.5, 4, 4, 3.5), ellipseShape(0, 0.8, 5, 3) }
  for _, h in ipairs(hairShapes) do
    paint(h, ramp(HAIR))
  end
  -- the horizontal arms and the legs together
  for _, m in ipairs({ -1, 1 }) do
    paint(capsule(m * 16, 34, m * 60, 38.5, 5.0, 3.1), skin)
    paint(ellipseShape(m * 62.5, 38.5, 3.6, 2.7), skin)
    paint(capsule(m * 6.8, 79, m * 6.8, 130, 7.0, 4.2), skin)
    paint(ellipseShape(m * 8.4, 132, 5.6, 2.5), skin)
  end
  -- neck and torso
  paint(capsule(0, 22, 0, 31, 4.2, 4.6), skin)
  local torso = { { -13, 29.5 }, { 13, 29.5 }, { 19, 33 }, { 18, 38 }, { 17, 46 }, { 14, 56 }, { 12, 64 }, { 14.5, 74 }, { 15, 79 }, { -15, 79 }, { -14.5, 74 }, { -12, 64 }, { -14, 56 }, { -17, 46 }, { -18, 38 }, { -19, 33 } }
  paint(polyShape(torso, -19, 19), skin)
  -- the muscle lines: pectorals, the centre line, the abdomen, the navel
  mark(function(x, y)
    local ax = math.abs(x)
    local pec = ax >= 1.2 and ax <= 15 and math.abs(y - (47 - 0.05 * (ax - 8) ^ 2)) < cp * 0.6
    local mid = ax < cp * 0.6 and y > 38 and y < 70
    local abs = ax >= 2 and ax <= 9 and (math.abs(y - 53) < cp * 0.55 or math.abs(y - 58) < cp * 0.55 or math.abs(y - 63) < cp * 0.55)
    local clav = ax >= 3 and ax <= 15 and math.abs(y - (33.5 + 0.02 * ax * ax)) < cp * 0.55
    local navel = math.abs(x) < cp * 0.7 and math.abs(y - 66) < cp * 0.7
    return pec or mid or abs or clav or navel
  end, SKIN[4])
  -- the loincloth, in folds
  local cloth = { { -15, 67 }, { 15, 67 }, { 16.5, 80 }, { 9, 90 }, { 0, 85 }, { -9, 90 }, { -16.5, 80 } }
  paint(function(x, y)
    if not inPoly(cloth, x, y) then
      return nil
    end
    return 0.25 + 0.5 * ((x + 16) / 32)
  end, function(v, x, y)
    local k = v < 0.4 and 1 or (v < 0.7 and 2 or 3)
    if y < 70 then
      return CLOTH[3] -- the band at the waist
    end
    if ((x * 0.8 + y * 1.1) % 6) < 0.9 then
      k = min(3, k + 1)
    end
    return CLOTH[k]
  end)
  -- the head: skin, then the hair in front, the beard, the face
  paint(ellipseShape(0, 13.5, 8.6, 10.4), skin)
  local function oval(x, y)
    return (x / 8.4) ^ 2 + ((y - 13.5) / 10.1) ^ 2 < 1
  end
  mark(function(x, y)
    return oval(x, y) and (y < 6.5 or (math.abs(x) > 6.2 and y < 17.5))
  end, HAIR[2])
  mark(function(x, y)
    return oval(x, y) and (y < 6.5 or (math.abs(x) > 6.2 and y < 17.5)) and hash2(floor(x / cp), floor(y / cp)) < 0.3
  end, HAIR[1])
  mark(function(x, y)
    local beard = ((x / 5.4) ^ 2 + ((y - 19.5) / 4.8) ^ 2 < 1) and y > 17
    local mous = math.abs(x) < 4.2 and y > 15.3 and y < 17.2 and math.abs(x) > 0.6
    return oval(x, y) and (beard or mous)
  end, HAIR[2])
  mark(function(x, y)
    local beard = ((x / 5.4) ^ 2 + ((y - 19.5) / 4.8) ^ 2 < 1) and y > 17 and hash2(floor(x / cp) + 3, floor(y / cp)) < 0.3
    return oval(x, y) and beard
  end, HAIR[3])
  mark(function(x, y)
    local eyeL = math.abs(x + 3.4) < cp * 0.7 and math.abs(y - 11.2) < cp * 0.6
    local eyeR = math.abs(x - 3.4) < cp * 0.7 and math.abs(y - 11.2) < cp * 0.6
    local browL = x > -5.6 and x < -1.6 and math.abs(y - 9.4) < cp * 0.5
    local browR = x < 5.6 and x > 1.6 and math.abs(y - 9.4) < cp * 0.5
    local nose = math.abs(x - 0.4) < cp * 0.5 and y > 10.5 and y < 15.2
    return eyeL or eyeR or browL or browR or nose
  end, OUTLINE)
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return { img = img, x0 = X0, y0 = Y0, cp = cp }
end

local figureCache = {}
local function figureFor(s)
  local key = floor(AP * 1000 / s)
  if not figureCache[key] then
    figureCache[key] = buildFigure(AP / s)
  end
  return figureCache[key]
end

local ARM_L = { { -18, 31 }, { -62, 33 }, { -62, 40 }, { -17, 44 } }
local ARM_R = { { 18, 31 }, { 62, 33 }, { 62, 40 }, { 17, 44 } }
local LEG_L = { { -15, 78 }, { -1, 78 }, { -3, 134 }, { -15, 134 } }
local LEG_R = { { 15, 78 }, { 1, 78 }, { 3, 134 }, { 15, 134 } }
local TORSO = { { -18, 30 }, { 18, 30 }, { 14, 60 }, { 15, 78 }, { -15, 78 }, { -14, 60 } }

function pages.sawbone(t)
  local u, F = t.u, t.F
  AP = PS(u)
  local game = require("src.game")
  local player, inv = game.player(), game.inventory()
  local marks = meta.marks()

  -- Left: the sheet
  local x0, y0, w0, h0 = t.X(14), t.Y(36), floor(176 * u), floor(184 * u)
  paper(t, x0, y0, w0, h0, 11)
  local s = u * 0.97
  local cx, top = x0 + w0 / 2, y0 + 12 * u
  local function P(fx, fy)
    return cx + fx * s, top + fy * s
  end
  local function T(pts)
    local out = {}
    for i, p in ipairs(pts) do
      local px, py = P(p[1], p[2])
      out[i] = { px, py }
    end
    return out
  end

  -- Which part is under the cursor or keys (the widgets are registered first: the sheet is drawn after, so it knows)
  local hover
  for id, part in pairs(PARTS) do
    local hx, hy, hw, hh = part.hit[1] - 2, part.hit[2] - 2, part.hit[3] + 4, part.hit[4] + 4
    local px, py = P(hx, hy)
    local limb = nil
    for _, l in ipairs(meta.LIMBS) do
      if l.id == id then
        limb = l
      end
    end
    local on = meta.limbOn(id)
    local focused = t.widget({ id = "camp:limb:" .. id, x = px, y = py, w = hw * s, h = hh * s, activate = function()
      meta.toggleLimb(id)
      audio.play(on and "back" or "select")
      t.act("refresh") -- (max health may have changed)
    end })
    if focused then
      hover = limb
    end
  end

  -- The Vitruvian man (the pixel figure, painted once), then the limbs that have been taken, over it
  do
    local fg = figureFor(s)
    local fx, fy = P(fg.x0, fg.y0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(fg.img, floor(fx), floor(fy), 0, AP, AP)
  end
  lineWidth(t)
  local function wash(pts, c, a)
    col(c, a)
    love.graphics.polygon("fill", polyPoints(T(pts)))
  end
  -- a limb: nothing more when kept; a red wash with dashed edges and a cross when taken
  local function limb(id, pts)
    if meta.limbOn(id) then
      wash(pts, RED, 0.28)
      col(RED, 0.95)
      dashedPoly(T(pts), max(3, u * 1.6))
      local a = T(pts)
      love.graphics.line(a[1][1], a[1][2], a[3][1], a[3][2])
      love.graphics.line(a[2][1], a[2][2], a[4][1], a[4][2])
    end
  end
  limb("arm", ARM_L)
  limb("leg", LEG_L)

  -- eyes
  local function almond() end -- (the painted face has its eyes)
  if meta.limbOn("eye") then
    local ex, ey = P(-3.5, 11)
    col(RED, 0.9)
    love.graphics.circle("fill", ex, ey, 2.8 * s)
    col({ 0.3, 0.04, 0.04 }, 1)
    love.graphics.line(ex - 2 * s, ey - 2 * s, ex + 2 * s, ey + 2 * s)
    love.graphics.line(ex - 2 * s, ey + 2 * s, ex + 2 * s, ey - 2 * s)
  else
    almond(-3.5, 11)
  end
  almond(3.5, 11)
  -- ears
  do
    local ex, ey = P(-8.3, 12)
    if meta.limbOn("ear") then
      col(RED, 0.8)
      love.graphics.circle("fill", ex, ey, 2.6 * s)
      col(RED, 1)
      dashed(ex - 4 * s, ey - 4 * s, ex + 1 * s, ey + 4 * s, max(2, u))
    end
  end
  -- spleen and kidneys: small beans
  local function bean(fx, fy, rx, ry, rot, id, kept)
    local bx, by = P(fx, fy)
    if meta.limbOn(id) then
      col(RED, 0.95)
      lineWidth(t, 0.5)
      love.graphics.push()
      love.graphics.translate(bx, by)
      love.graphics.rotate(rot)
      local pts = {}
      for i = 0, 15 do
        local a = i / 16 * math.pi * 2
        pts[#pts + 1] = { math.cos(a) * rx * s, math.sin(a) * ry * s }
      end
      dashedPoly(pts, max(2, u))
      love.graphics.pop()
    else
      love.graphics.push()
      love.graphics.translate(bx, by)
      love.graphics.rotate(rot)
      col({ 0.66, 0.26, 0.2 }, 0.75)
      love.graphics.ellipse("fill", 0, 0, rx * s, ry * s)
      col(INK, 0.8)
      lineWidth(t, 0.4)
      love.graphics.ellipse("line", 0, 0, rx * s, ry * s)
      love.graphics.pop()
    end
  end
  bean(9.5, 46.5, 4.5, 2.6, 0.5, "spleen")
  bean(-7, 62, 3, 4.5, 0.2, "kidney")
  bean(7, 62, 3, 4.5, -0.2, "_kidney2")

  -- the names, and what is hovered
  love.graphics.setFont(F.small)
  for id, part in pairs(PARTS) do
    local limbDef
    for _, l in ipairs(meta.LIMBS) do
      if l.id == id then
        limbDef = l
      end
    end
    local on = meta.limbOn(id)
    local lx, ly = P(part.label[1], part.label[2])
    local name = limbDef.name
    local nw = F.small:getWidth(name)
    local tx = part.label[3] == "r" and (lx - nw) or lx
    local lit = hover == limbDef
    col(INK, 0.5)
    lineWidth(t, 0.3)
    local l1x, l1y = P(part.lead[1], part.lead[2])
    local l2x, l2y = P(part.lead[3], part.lead[4])
    love.graphics.line(l1x, l1y, l2x, l2y)
    ink(name, tx, ly, F.small, on and RED or INK, lit and 1 or 0.78)
    if lit then
      local rx, ry = P(part.hit[1] - 2, part.hit[2] - 2)
      local rw, rh = floor((part.hit[3] + 4) * s), floor((part.hit[4] + 4) * s)
      local pulse = 0.75 + 0.25 * math.sin(love.timer.getTime() * 5)
      col(RED, 0.07 * pulse)
      love.graphics.rectangle("fill", floor(rx), floor(ry), rw, rh, u * 1.5, u * 1.5)
      col(RED, 0.95)
      lineWidth(t, 0.7)
      -- a red pencil ring: four corner ticks, not a solid box
      local ix, iy = floor(rx), floor(ry)
      local c = max(PS(u) * 3, floor(math.min(rw, rh) * 0.3))
      for _, k in ipairs({ { ix, iy, 1, 1 }, { ix + rw, iy, -1, 1 }, { ix, iy + rh, 1, -1 }, { ix + rw, iy + rh, -1, -1 } }) do
        love.graphics.line(k[1], k[2] + k[4] * c, k[1], k[2], k[1] + k[3] * c, k[2])
      end
    end
    if on then
      local w2 = F.small:getWidth("TAKEN")
      ink("TAKEN", part.label[3] == "r" and (lx - w2) or lx, ly + F.small:getHeight() * 0.95, F.small, RED, 0.95)
    end
  end
  -- the caption at the foot of the sheet
  local cap = "Anatomia, for the Sawbone's convenience"
  ink(cap, x0 + (w0 - F.small:getWidth(cap)) / 2, y0 + h0 - 8 * u, F.small, INK, 0.55)

  -- Right: patch-ups, what is hovered, and his upgrades
  local x, y, w = t.X(200), t.Y(36), floor(186 * u)
  t.shadowPrint("Patch up", x, y, F.body, t.WARM)
  y = y + F.body:getHeight() + 2 * u
  local hurt = player and not player.dead and player.hp < player.maxHp
  if player and inv then
    local function pay(id, bx, by, bw, bh, can, mode, draw)
      local focused = t.widget({ id = id, x = bx, y = by, w = bw, h = bh, activate = function()
        if can and meta.sawHeal(player, inv, mode) then
          audio.play("heal")
          t.act("refresh")
        else
          audio.play("deny")
        end
      end })
      t.panel(bx, by, bw, bh, focused and 0.98 or 0.8)
      if focused then
        t.focusFrame(bx, by, bw, bh)
      end
      draw(bx, by, bw, bh, can, focused)
    end
    -- One option, Heal: paid in gold or in marks (a button for each at the right)
    local hFull, gFull = meta.sawHealQuote(player, 1)
    local fh = floor(14 * u)
    t.panel(x, y, w, fh, 0.82)
    t.shadowPrint("Heal (+" .. hFull .. ")", x + 5 * u, y + (fh - F.body:getHeight()) / 2, F.body, hurt and t.DIM or t.FAINT)
    local bw, bh = floor(34 * u), floor(10 * u)
    local gx = x + w - 2 * u - bw * 2 - 2 * u
    pay("camp:saw:fullgold", gx, y + 2 * u, bw, bh, hurt and inv.gold >= gFull, "full", function(bx, by, bw2, bh2, can)
      local tx = gFull .. "g"
      t.shadowPrint(tx, bx + (bw2 - F.body:getWidth(tx)) / 2, by + (bh2 - F.body:getHeight()) / 2, F.body, can and t.WARM or t.FAINT)
    end)
    pay("camp:saw:fullmarks", gx + bw + 2 * u, y + 2 * u, bw, bh, hurt and marks >= meta.SAW_MARKS, "marks", function(bx, by, bw2, bh2, can)
      local tx = tostring(meta.SAW_MARKS)
      local tw = F.body:getWidth(tx) + 9 * u
      local px = bx + (bw2 - tw) / 2
      t.shadowPrint(tx, px, by + (bh2 - F.body:getHeight()) / 2, F.body, can and meta.SIGIL_COLOR or t.FAINT)
      meta.drawSigil(floor(px + F.body:getWidth(tx) + 1 * u), floor(by + bh2 / 2 - 3.5 * PS(u)), PS(u), can and 1 or 0.4)
    end)
    y = y + fh + 4 * u
  end

  -- The note card: what the hovered part (or upgrade) does
  local ups = upgradesFor("sawbone")
  local ch = floor(38 * u)
  local cardY = y
  y = y + ch + 4 * u
  t.shadowPrint("His tools", x, y, F.body, t.WARM)
  y = y + F.body:getHeight() + 2 * u
  local upHover
  for _, up in ipairs(ups) do
    local rh = floor(15 * u)
    if upgradeRow(t, up, x, y, w, rh) then
      upHover = up
    end
    y = y + rh + 2 * u
  end
  if hover then
    local on = meta.limbOn(hover.id)
    infoCard(t, x, cardY, w, ch, hover.name .. (on and "  (taken)" or ""), on and RED or t.TEXT, nil, nil, {
      { "+ " .. hover.gain, { 0.55, 0.9, 0.55 } },
      { "- " .. hover.loss, { 0.95, 0.6, 0.55 } },
      { on and "Click to have it put back." or "Click to have it taken.", t.FAINT },
    })
  elseif upHover then
    infoCard(t, x, cardY, w, ch, upHover.name, t.TEXT, nil, nil, { { upHover.desc, t.DIM } })
  else
    infoCard(t, x, cardY, w, ch, "Take a part", t.WARM, nil, nil, {
      { "Point at the sketch. Each part he takes gives a gift and a price, for good, until you ask for it back.", t.FAINT },
    })
  end
end

-- ===================================================================================================
-- The Gunsmith: his pegboard wall
-- ===================================================================================================

-- One-line stats for a weapon entry (what the compendium keeps)
local function entryLines(t, e, seen, extra)
  local lines = {}
  if seen then
    lines[#lines + 1] = { e.desc or "", t.DIM }
  end
  for _, ex in ipairs(extra or {}) do
    lines[#lines + 1] = ex
  end
  return lines
end

function pages.gunsmith(t)
  local u, F = t.u, t.F
  AP = PS(u)
  local marks = meta.marks()
  local gold = t.runGold and t.runGold() or 0
  local bought = meta.gunBought()
  local room = t.gunRoom == nil or t.gunRoom()

  -- The wall: a pegboard with the guns hung on it
  local wx, wy, ww, wh = t.X(14), t.Y(36), floor(250 * u), floor(94 * u)
  t.cast(wx, wy, ww, wh)
  love.graphics.setColor(0.24, 0.17, 0.11)
  R(wx - AP, wy - AP, ww + 2 * AP, wh + 2 * AP)
  love.graphics.setColor(0.36, 0.26, 0.17)
  R(wx, wy, ww, wh)
  love.graphics.setColor(0.30, 0.21, 0.13)
  for gy = 0, floor(wh / (6 * u)) do
    R(wx, wy + gy * 6 * u, ww, AP) -- (the boards' seams)
  end
  love.graphics.setColor(0.17, 0.11, 0.07)
  for gx = 3 * u, ww - 2 * u, 6 * u do
    for gy = 3 * u, wh - 2 * u, 6 * u do
      R(wx + gx, wy + gy, AP, AP) -- (peg holes)
    end
  end
  love.graphics.setColor(1, 1, 1, 0.05)
  R(wx, wy, ww, AP)
  -- the wall's depth: the lamp-lit middle, the corners in shade
  for vi = 0, 5 do
    love.graphics.setColor(0, 0, 0, 0.07)
    R(wx, wy, ww, AP * (6 - vi) * 2)
    R(wx, wy + wh - AP * (6 - vi) * 2, ww, AP * (6 - vi) * 2)
    R(wx, wy, AP * (6 - vi) * 2, wh)
    R(wx + ww - AP * (6 - vi) * 2, wy, AP * (6 - vi) * 2, wh)
  end

  local hoverEntry, hoverKind
  local cols, rows = 3, 2
  local pad = 4 * u
  local cw, chh = floor((ww - pad * 2) / cols), floor((wh - pad * 2) / rows)
  -- (all six guns at the one scale, the smallest any of them fits)
  local gunScale
  for _, g in ipairs(meta.GUN_PRICES) do
    local s = compendium.fitScale(compendium.entry("weapon", g[1]), cw - 3 * u - 6 * u, chh - 3 * u - 16 * u)
    if s and (not gunScale or s < gunScale) then
      gunScale = s
    end
  end
  for i, g in ipairs(meta.GUN_PRICES) do
    local id, price = g[1], g[2]
    local e = compendium.entry("weapon", id)
    local known = meta.isUnlocked("weapon", id)
    local seen = meta.isSeen("weapon", id)
    local cost = meta.teachCost("weapon", id)
    local col0, row0 = (i - 1) % cols, floor((i - 1) / cols)
    local x, y = wx + pad + col0 * cw, wy + pad + row0 * chh
    local bw, bh = cw - 3 * u, chh - 3 * u
    local can = known and not bought and room and gold >= price
    local canTeach = (not known) and seen and marks >= cost
    local focused = t.widget({ id = "camp:gun:" .. id, x = x, y = y, w = bw, h = bh, activate = function()
      if known then
        if can then
          t.act("buygun", id)
          audio.play("buy")
        else
          audio.play("deny")
        end
      elseif seen and e then
        if marks < cost then
          audio.play("deny")
          return
        end
        t.confirm({
          text = "Have him craft the " .. e.name .. "?",
          detail = "Once he has made one it joins the pool for every run: chests, drops and shops. " .. cost .. " marks.",
          yesLabel = "Craft",
          yes = function()
            if meta.teach("weapon", id) then
              audio.play("buy")
            end
            t.pop()
          end,
        })
      else
        audio.play("deny")
      end
    end })
    -- the shadow the gun casts on the board, then the gun on its pegs
    -- the slot the gun hangs in: a recess with a dark rim, a shadowed top and a lit lower lip
    love.graphics.setColor(0.13, 0.08, 0.05, 0.75)
    R(x, y, bw, AP)
    R(x, y, AP, bh - 12 * u)
    R(x + bw - AP, y, AP, bh - 12 * u)
    love.graphics.setColor(0, 0, 0, 0.22)
    R(x + AP, y + AP, bw - 2 * AP, AP * 3)
    love.graphics.setColor(1, 0.9, 0.7, 0.10)
    R(x + AP, y + bh - 12 * u, bw - 2 * AP, AP)
    love.graphics.setColor(0, 0, 0, focused and 0.28 or 0.18)
    R(x + 2 * u, y + 3 * u, bw - 3 * u, bh - 14 * u)
    if focused then
      love.graphics.setColor(1, 0.85, 0.5, 0.10)
      R(x, y, bw, bh)
    end
    if e then
      compendium.drawIcon(e, x + 3 * u, y + 2 * u, bw - 6 * u, bh - 16 * u, not seen and not known, (known or seen) and 1 or 0.9, gunScale)
    end
    love.graphics.setColor(0.10, 0.07, 0.05)
    R(x + bw / 2 - 12 * u, y + 2 * u, max(1, u * 1.1), max(1, u * 1.1))
    R(x + bw / 2 + 12 * u, y + 2 * u, max(1, u * 1.1), max(1, u * 1.1))
    -- the price tag, hung below on a string
    local tagW, tagH = floor(bw - 14 * u), floor(9 * u)
    local tx, ty = x + (bw - tagW) / 2, y + bh - tagH - u
    love.graphics.setColor(0.10, 0.07, 0.05, 0.9)
    R(x + bw / 2, ty - 3 * u, AP, 3 * u)
    love.graphics.setColor(0.25, 0.17, 0.10)
    R(tx - AP, ty - AP, tagW + 2 * AP, tagH + 2 * AP)
    love.graphics.setColor(0.84, 0.74, 0.54)
    R(tx, ty, tagW, tagH)
    love.graphics.setColor(1, 0.96, 0.8, 0.5)
    R(tx, ty, tagW, AP)
    love.graphics.setColor(0.45, 0.33, 0.18, 0.5)
    R(tx, ty + tagH - AP, tagW, AP)
    local label, color
    if known then
      label = bought and "taken" or (price .. "g")
      color = bought and { 0.4, 0.34, 0.26 } or (can and { 0.45, 0.30, 0.03 } or RED)
      ink(label, tx + (tagW - F.small:getWidth(label)) / 2, ty + (tagH - F.small:getHeight()) / 2, F.small, color)
    elseif seen then
      local txt = tostring(cost)
      local sw = F.small:getWidth(txt) + 7 * u
      local px = tx + (tagW - sw) / 2
      ink(txt, px, ty + (tagH - F.small:getHeight()) / 2, F.small, canTeach and { 0.35, 0.18, 0.5 } or RED)
      meta.drawSigil(floor(px + F.small:getWidth(txt) + 1.5 * u), floor(ty + tagH / 2 - 3.5 * PS(u)), PS(u), 0.95)
    else
      ink("?", tx + (tagW - F.small:getWidth("?")) / 2, ty + (tagH - F.small:getHeight()) / 2, F.small, { 0.4, 0.3, 0.2 })
    end
    if focused then
      t.focusFrame(x, y, bw, bh)
      hoverEntry, hoverKind = e, known and "sell" or "teach"
      hoverEntry = { entry = e, id = id, known = known, seen = seen, price = price, cost = cost }
    end
  end

  -- The drawer of parts (ammo and attachments he could learn), right
  local dx, dy, dw = t.X(272), t.Y(36), floor(114 * u)
  t.shadowPrint("Parts drawer", dx, dy, F.body, t.WARM)
  local list = t.teachList()
  local parts = {}
  for _, e in ipairs(list) do
    if e.category ~= "weapon" then
      parts[#parts + 1] = e
    end
  end
  local top = dy + F.body:getHeight() + 2 * u
  local availH = t.Y(218) - top
  local pd, gap = floor(4 * u), floor(2 * u)
  local cell = floor(19 * u)
  local ncols
  while true do
    ncols = max(1, floor((dw - pd * 2 + gap) / (cell + gap)))
    local nrows = max(1, math.ceil(#parts / ncols))
    if nrows * (cell + gap) - gap + pd * 2 <= availH or cell <= floor(10 * u) then
      break
    end
    cell = cell - floor(u)
  end
  local nrows = max(1, math.ceil(#parts / ncols))
  local dh = min(availH, nrows * (cell + gap) - gap + pd * 2)
  -- (a wooden drawer: a front with a brass pull)
  t.cast(dx, top, dw, dh)
  love.graphics.setColor(0.24, 0.17, 0.11)
  R(dx - AP, top - AP, dw + 2 * AP, dh + 2 * AP)
  love.graphics.setColor(0.17, 0.12, 0.09)
  R(dx, top, dw, dh)
  if #parts == 0 then
    t.printCentered("Nothing left to teach him.", dx + dw / 2, top + dh / 2 - F.small:getHeight() / 2, F.small, t.FAINT)
  end
  local gridW = ncols * (cell + gap) - gap
  local gx0 = dx + floor((dw - gridW) / 2)
  for i, e in ipairs(parts) do
    local cx = gx0 + ((i - 1) % ncols) * (cell + gap)
    local cy = top + pd + floor((i - 1) / ncols) * (cell + gap)
    local seen = meta.isSeen(e.category, e.id)
    local cost = meta.teachCost(e.category, e.id)
    local focused = t.widget({ id = "camp:teach:" .. e.category .. ":" .. e.id, x = cx, y = cy, w = cell, h = cell, activate = function()
      if not seen or marks < cost or not meta.featMet(e.id) then
        audio.play("deny")
        return
      end
      t.confirm({
        text = "Teach him the " .. e.name .. "?",
        detail = "It joins the pool for every run. " .. cost .. " marks.",
        yesLabel = "Teach",
        yes = function()
          if meta.teach(e.category, e.id) then
            audio.play("buy")
          end
          t.pop()
        end,
      })
    end })
    local edge = seen and ((e.rarity and e.rarity ~= "common" and t.RARITY[e.rarity]) or t.SLOT_REST) or { 0.22, 0.2, 0.27 }
    t.slotBox(cx, cy, cell, cell, focused and "focus" or nil, { edge[1], edge[2], edge[3], seen and 0.9 or 0.6 }, not seen and { 0.035, 0.03, 0.05, 0.9 } or nil)
    compendium.drawIcon(e, cx + 2 * u, cy + 2 * u, cell - 4 * u, cell - 4 * u, not seen)
    if focused then
      hoverEntry = { entry = e, id = e.id, part = true, seen = seen, cost = cost }
    end
  end

  -- The card under the wall: what is hovered
  local cx0, cy0, cw0, ch0 = wx, wy + wh + 4 * u, ww, floor(34 * u)
  local ups = upgradesFor("gunsmith")
  local upHover
  local uy = cy0 + ch0 + 4 * u
  for _, up in ipairs(ups) do
    local rh = floor(12 * u)
    if upgradeRow(t, up, wx, uy, ww, rh) then
      upHover = up
    end
    uy = uy + rh + 2 * u
  end
  if upHover then
    infoCard(t, cx0, cy0, cw0, ch0, upHover.name, t.TEXT, nil, nil, { { upHover.desc, t.DIM } })
  elseif hoverEntry then
    local h = hoverEntry
    local e = h.entry
    if h.part then
      local feat = not meta.featMet(h.id) and meta.featText(h.id) or nil
      local title = (h.seen or feat) and e.name or "???"
      if feat then
        infoCard(t, cx0, cy0, cw0, ch0, title, t.TEXT, nil, nil, { { (e.desc or "") .. "  Unlocks once you: " .. feat .. ".", t.DANGER } })
      elseif h.seen then
        infoCard(t, cx0, cy0, cw0, ch0, title, t.TEXT, tostring(h.cost), marks >= h.cost and meta.SIGIL_COLOR or t.DANGER, entryLines(t, e, true, { marks >= h.cost and { "Click to teach him.", t.FAINT } or { "Not enough marks.", t.DANGER } }))
      else
        infoCard(t, cx0, cy0, cw0, ch0, title, t.FAINT, nil, nil, { { "Not seen yet. Bosses, and now and then a chest, give out things he doesn't make; find one and he can learn it.", t.FAINT } })
      end
    elseif h.known then
      local why = bought and "You have bought one this run." or (not room and "No room: free a weapon slot first." or (gold < h.price and "Not enough gold." or "Click to buy: one per run, always B-grade."))
      infoCard(t, cx0, cy0, cw0, ch0, e and e.name or h.id, t.TEXT, nil, nil, entryLines(t, e or {}, true, { { h.price .. " gold.  " .. why, bought and t.FAINT or (gold >= h.price and room) and t.DIM or t.DANGER } }))
    elseif h.seen then
      infoCard(t, cx0, cy0, cw0, ch0, e and e.name or h.id, t.TEXT, tostring(h.cost), marks >= h.cost and meta.SIGIL_COLOR or t.DANGER, entryLines(t, e or {}, true, { marks >= h.cost and { "Click to have him craft one: it joins the pool for every run.", t.FAINT } or { "Not enough marks.", t.DANGER } }))
    else
      local giver = meta.SPECIAL_GUNS[h.id]
      local hint = "Not seen yet. Bosses, and now and then a chest, carry guns he doesn't make; find one and he can learn it."
      if giver == "queen" then
        hint = "Not seen yet. The Queen of the Sulfur Vents guards one; bring it back and he can craft it."
      elseif giver == "sawbone" then
        hint = "Not seen yet. The Sawbone, floating in the Flooded Caverns, has one to give once he is woken."
      elseif giver == "cartographer" then
        hint = "Not seen yet. The Cartographer, caged in the Quarry, has one to give once she is freed."
      end
      infoCard(t, cx0, cy0, cw0, ch0, "???", t.FAINT, nil, nil, { { hint, t.FAINT } })
    end
  else
    local note = bought and "(bought this run)" or (room and "One of his guns a run, for gold, always B-grade." or "No room: free a weapon slot to buy.")
    infoCard(t, cx0, cy0, cw0, ch0, "The wall", t.WARM, nil, nil, { { note .. "  Guns you have seen but he can't yet make hang with a mark price: click to teach him.", t.FAINT } })
  end
end

-- ===================================================================================================
-- The Apothecary: a herbalist's notes
-- ===================================================================================================

local HEART = {
  "00110001100",
  "01111011110",
  "11111111111",
  "11111111111",
  "11111111111",
  "01111111110",
  "00111111100",
  "00011111000",
  "00001110000",
  "00000100000",
}
local CORK = { 0.55, 0.36, 0.18 }
local FLASK = {
  cork = true,
  "00011111000",
  "00001110000",
  "00001110000",
  "00001110000",
  "00011111000",
  "00111111100",
  "01111111110",
  "11111111111",
  "11111111111",
  "11111111111",
  "01111111110",
  "00111111100",
}

-- Blows a small drawing (rows of 0/1) up k times with its corners rounded (each cell sampled smoothly and cut at one half),
-- so the same shape can be drawn with the page's art pixel instead of one k times as big
local function upres(art, k)
  local rows, w = #art, #art[1]
  local function at(r, c)
    return art[r] and art[r]:sub(c, c) == "1" and 1 or 0
  end
  local out = { k = k, cork = art.cork and true or nil, corkRows = art.cork and k or nil }
  for r = 1, rows * k do
    local sy = (r - 0.5) / k + 0.5
    local r0 = floor(sy)
    local fy = sy - r0
    local line = {}
    for c = 1, w * k do
      local sx = (c - 0.5) / k + 0.5
      local c0 = floor(sx)
      local fx = sx - c0
      local v = at(r0, c0) * (1 - fx) * (1 - fy) + at(r0, c0 + 1) * fx * (1 - fy) + at(r0 + 1, c0) * (1 - fx) * fy + at(r0 + 1, c0 + 1) * fx * fy
      line[c] = v >= 0.5 and "1" or "0"
    end
    out[r] = table.concat(line)
  end
  return out
end

local bigArt = {}
local function bigOf(art, k)
  if not bigArt[art] then
    bigArt[art] = upres(art, k)
  end
  return bigArt[art]
end

-- A pixel drawing (rows of 0/1) with its outline in ink and a fill that rises with `level` (0..1) in `liquid`. The glass is
-- shaded: a lit rim along the upper left, a shadowed one along the lower right, a gloss streak; the liquid darkens with depth,
-- has a bright surface line and a few bubbles. Runs of one colour along a row are drawn as one bar.
local function pixelPlate(art, x, y, p, level, liquid, glassTint)
  local rows, w = #art, #art[1]
  local filledFrom = rows - floor(rows * level + 0.5) -- the first row (from the top) with liquid
  local corkRows = art.corkRows or 1
  local k = art.k or 1 -- (how many times the source art was blown up)
  local function on(r, c)
    return art[r] and art[r]:sub(c, c) == "1"
  end
  local function mix(c, f, add)
    return min(1, c[1] * f + add), min(1, c[2] * f + add), min(1, c[3] * f + add)
  end
  local rim = max(1, floor(k * 0.7))
  for r = 1, rows do
    local rr, rg, rb, ra, rs
    local function flush(c)
      if rr then
        love.graphics.setColor(rr, rg, rb, ra)
        R(x + (rs - 1) * p, y + (r - 1) * p, (c - rs) * p, p)
      end
      rr = nil
    end
    for c = 1, w + 1 do
      local cr, cg, cb, ca
      if c <= w and on(r, c) then
        local edge = c == 1 or r == 1 or r == rows or not on(r, c - 1) or not on(r, c + 1) or not on(r - 1, c) or not on(r + 1, c)
        if art.cork and r <= corkRows then
          -- the cork: grain bands and a lit left edge
          local f = (r % 2 == 0) and 0.88 or 1.0
          if edge then
            cr, cg, cb, ca = INK[1], INK[2], INK[3], 0.9
          else
            cr, cg, cb = mix(CORK, f * (c < w * 0.4 and 1.15 or 1), 0)
            ca = 1
          end
        elseif edge then
          cr, cg, cb, ca = INK[1], INK[2], INK[3], 0.9
        else
          local lightRim = not on(r - 1 - rim, c) or not on(r, c - 1 - rim) or not on(r - rim, c - rim)
          local darkRim = not on(r + 1 + rim, c) or not on(r, c + 1 + rim) or not on(r + rim, c + rim)
          local streak = c > w * 0.30 and c <= w * 0.30 + k and r > corkRows + rows * 0.18 and r < rows * 0.55
          if r > filledFrom then
            local depth = (r - filledFrom) / max(1, rows - filledFrom)
            local f = 1.12 - 0.42 * depth
            if r == filledFrom + 1 then
              f = 1.45 -- the bright surface line
            elseif r == filledFrom + 2 then
              f = 1.25
            end
            cr, cg, cb = mix(liquid, f, 0)
            if lightRim then
              cr, cg, cb = mix(liquid, f * 1.2, 0.04)
            elseif darkRim then
              cr, cg, cb = mix(liquid, f * 0.7, 0)
            end
            -- a few bubbles rising in it
            if (c * 7 + r * 13) % 41 == 0 and r > filledFrom + 3 then
              cr, cg, cb = mix(liquid, 1.6, 0.1)
            end
          else
            cr, cg, cb = glassTint[1], glassTint[2], glassTint[3]
            if lightRim then
              cr, cg, cb = mix(glassTint, 1.08, 0.06)
            elseif darkRim then
              cr, cg, cb = mix(glassTint, 0.78, 0)
            end
          end
          if streak then
            cr, cg, cb = mix({ cr, cg, cb }, 1.0, 0.22) -- the gloss
          end
          ca = 1
        end
      end
      if cr ~= rr or cg ~= rg or cb ~= rb or ca ~= ra then
        flush(c)
        if cr then
          rr, rg, rb, ra, rs = cr, cg, cb, ca, c
        end
      end
    end
  end
  -- (a soft shadow under it, on the paper)
  love.graphics.setColor(0.25, 0.15, 0.06, 0.22)
  R(x + 2 * p, y + rows * p, (w - 4) * p, p)
end

-- A pressed leaf (a tier): filled green when bought, only a pencilled outline when not
local function leaf(x, y, s, on)
  love.graphics.setLineWidth(AP)
  local pts = { { 0, 0 }, { 3, -2 }, { 6, -2 }, { 8, 0 }, { 6, 2 }, { 3, 2 } }
  local flat = {}
  for _, p in ipairs(pts) do
    flat[#flat + 1] = x + p[1] * s
    flat[#flat + 1] = y + p[2] * s
  end
  if on then
    col(GREEN, 0.9)
    love.graphics.polygon("fill", flat)
    col({ 0.12, 0.28, 0.1 }, 0.9)
    love.graphics.line(x, y, x + 8 * s, y)
  else
    col(INK, 0.35)
    love.graphics.polygon("line", flat)
  end
  col({ 0.14, 0.09, 0.05 }, on and 0.9 or 0.35)
  love.graphics.line(x - 3 * s, y + 0.5 * s, x, y)
end

-- The Apothecary's two brews are separate things: two glass specimens standing on a wooden shelf, each with a paper label
-- under it (name, a blue pip per tier, the price).
local function apoPlates()
  return {
    { id = "vigor", art = HEART, liquid = { 0.78, 0.14, 0.14 }, tint = { 0.93, 0.86, 0.72 }, title = "Vigor Tonic", sub = "for the heart",
      note = function(tier) return tier > 0 and ("+" .. 12 * tier .. " max health") or "no tonic taken yet" end },
    { id = "flask", art = FLASK, liquid = { 0.30, 0.62, 0.30 }, tint = { 0.88, 0.88, 0.78 }, title = "Pocket Flask", sub = "for the road",
      note = function(tier) return tier > 0 and (tier .. (tier == 1 and " flask" or " flasks") .. " each run") or "no flask carried yet" end },
  }
end

local function apoBuy(id)
  if meta.buy(id) then
    audio.play("buy")
  else
    audio.play("deny")
  end
end

function pages.apothecary(t)
  AP = PS(t.u)
  local u, F = t.u, t.F
  local marks = meta.marks()
  local plates = apoPlates()
  local sx, sw = t.X(40), floor(320 * u)
  local shelfY = t.Y(112)
  t.shadowPrint("Brews", t.X(14), t.Y(36), F.body, t.WARM)
  -- the back wall, a dim panel with a few hanging herbs
  t.panel(sx - 8 * u, t.Y(46), sw + 16 * u, floor(112 * u), 0.55)
  for i = 0, 7 do
    local hx = sx + 14 * u + i * (sw - 28 * u) / 7
    love.graphics.setColor(0.30, 0.22, 0.12)
    R(hx, t.Y(48), AP, 5 * u)
    love.graphics.setColor(0.28 + (i % 3) * 0.06, 0.46, 0.22)
    R(hx - AP, t.Y(48) + 5 * u, AP * 3, 6 * u)
    love.graphics.setColor(0.18, 0.32, 0.14)
    R(hx, t.Y(48) + 8 * u, AP, 3 * u)
  end
  -- the plank, lit on top and dark under
  love.graphics.setColor(0.17, 0.11, 0.07)
  R(sx - 4 * u, shelfY, sw + 8 * u, AP * 3)
  love.graphics.setColor(0.46, 0.32, 0.18)
  R(sx - 4 * u, shelfY, sw + 8 * u, AP * 2)
  love.graphics.setColor(1, 0.9, 0.7, 0.18)
  R(sx - 4 * u, shelfY, sw + 8 * u, AP)
  love.graphics.setColor(0, 0, 0, 0.35)
  R(sx - 4 * u, shelfY + AP * 3, sw + 8 * u, AP * 2)
  local hover
  for i, pl in ipairs(plates) do
    local up = meta.upgrade(pl.id)
    local tier, cost = meta.tier(pl.id), meta.nextCost(pl.id)
    local slotW = floor(120 * u)
    local cx = sx + sw * (i == 1 and 0.27 or 0.73)
    local bx, by, bw, bh = floor(cx - slotW / 2), t.Y(52), slotW, floor(106 * u)
    local focused = t.widget({ id = "camp:up:" .. pl.id, x = bx, y = by, w = bw, h = bh, activate = function() apoBuy(pl.id) end })
    if focused then
      hover = up
      love.graphics.setColor(1, 0.9, 0.6, 0.07)
      R(bx, by, bw, bh)
    end
    local big = bigOf(pl.art, 4)
    local aw, ah = #big[1] * AP, #big * AP
    pixelPlate(big, floor(cx - aw / 2), floor(shelfY - ah), AP, tier / #up.costs, pl.liquid, pl.tint)
    -- a paper label under the shelf: name, a leaf per tier, the price
    local lw, lh = floor(86 * u), floor(34 * u)
    local lx, ly = floor(cx - lw / 2), shelfY + 8 * u
    love.graphics.setColor(0.25, 0.17, 0.10)
    R(lx - AP, ly - AP, lw + 2 * AP, lh + 2 * AP)
    love.graphics.setColor(0.86, 0.75, 0.54)
    R(lx, ly, lw, lh)
    love.graphics.setColor(1, 0.96, 0.8, 0.5)
    R(lx, ly, lw, AP)
    ink(pl.title, cx - F.body:getWidth(pl.title) / 2, ly + 3 * u, F.body, INK, 0.92)
    -- a pip per tier: blue and lit when bought, a dark hollow when not, each outlined an art pixel thick
    do
      local n = #up.costs
      local ps = AP * 4
      local gap = AP * 2
      local px0 = floor(cx - (n * ps + (n - 1) * gap) / 2)
      local py0 = floor(ly + 3 * u + F.body:getHeight() + 4 * u)
      for k = 1, n do
        local pxk = px0 + (k - 1) * (ps + gap)
        love.graphics.setColor(0.10, 0.12, 0.30)
        R(pxk, py0, ps, ps)
        if k <= tier then
          love.graphics.setColor(0.30, 0.55, 1.0)
          R(pxk + AP, py0 + AP, ps - 2 * AP, ps - 2 * AP)
          love.graphics.setColor(0.75, 0.90, 1.0)
          R(pxk + AP, py0 + AP, AP, AP)
        else
          love.graphics.setColor(0.45, 0.38, 0.28, 0.6)
          R(pxk + AP, py0 + AP, ps - 2 * AP, ps - 2 * AP)
        end
      end
    end
    if cost then
      local txt = tostring(cost)
      local tw = F.body:getWidth(txt) + 9 * u
      ink(txt, cx - tw / 2, ly + lh - F.body:getHeight() - 2 * u, F.body, marks >= cost and { 0.35, 0.18, 0.5 } or RED, 1)
      meta.drawSigil(floor(cx - tw / 2 + F.body:getWidth(txt) + 1.5 * u), floor(ly + lh - F.body:getHeight() / 2 - 2 * u - 3.5 * AP), AP, 1)
    else
      ink("Fully brewed", cx - F.body:getWidth("Fully brewed") / 2, ly + lh - F.body:getHeight() - 2 * u, F.body, GREEN, 1)
    end
    if focused then
      t.focusFrame(bx, by, bw, bh)
    end
  end
  local tx, ty, tw = t.X(40), t.Y(168), floor(320 * u)
  t.wrapped(hover and (hover.name .. ".  " .. hover.desc) or "Click a specimen to buy its next tier. Both last through every run.", tx, ty, tw, F.small, hover and t.DIM or t.FAINT)
end

-- ===================================================================================================
-- The Taxidermist: the trophy wall
-- ===================================================================================================

function pages.taxidermist(t)
  local u, F = t.u, t.F
  AP = PS(u)
  local marks = meta.marks()
  local bx, by, bw, bh = t.X(14), t.Y(36), floor(372 * u), floor(112 * u)
  -- the board: planks, with the plaques screwed to it
  t.cast(bx, by, bw, bh)
  love.graphics.setColor(0.17, 0.11, 0.07)
  R(bx - AP, by - AP, bw + 2 * AP, bh + 2 * AP)
  love.graphics.setColor(0.33, 0.22, 0.13)
  R(bx, by, bw, bh)
  for i = 1, 5 do
    love.graphics.setColor(0.26, 0.17, 0.10)
    R(bx, by + i * bh / 6, bw, AP) -- (the boards' seams)
    love.graphics.setColor(1, 1, 1, 0.035)
    R(bx, by + i * bh / 6 + AP, bw, AP)
  end
  local kinds = meta.MOUNT_ORDER
  local n = #kinds
  local pw = floor((bw - 8 * u) / n)
  local hover
  -- (every plaque's picture at the one scale, the smallest any of them fits, so the pixels match across the board)
  local plaqueScale
  for _, kind in ipairs(kinds) do
    local s = compendium.fitScale(compendium.entry("enemy", kind), pw - 3 * u - 6 * u - 4 * u, floor((bh - 10 * u) * 0.50) - 4 * u)
    if s and (not plaqueScale or s < plaqueScale) then
      plaqueScale = s
    end
  end
  for i, kind in ipairs(kinds) do
    local m = meta.MOUNTS[kind]
    local slain, level = meta.trophyCount(kind), meta.mountLevel(kind)
    local need, cost = meta.mountNeed(kind), meta.mountCost(kind)
    local maxed = level >= meta.MOUNT_MAX
    local ready = not maxed and slain >= need
    local x, y = bx + 4 * u + (i - 1) * pw, by + 5 * u
    local w, h = pw - 3 * u, bh - 10 * u
    local focused = t.widget({ id = "camp:mount:" .. kind, x = x, y = y, w = w, h = h, activate = function()
      if meta.mount(kind) then
        audio.play("buy")
        t.act("refresh") -- (max health may have changed)
      else
        audio.play("deny")
      end
    end })
    -- the plaque: a lighter wood shield, a dark velvet window, a brass name plate, brass nails
    love.graphics.setColor(0, 0, 0, 0.3)
    R(x + u, y + u, w, h)
    love.graphics.setColor(0.52, 0.36, 0.20)
    R(x, y, w, h)
    -- wood grain, a lit left edge and a shadowed right one
    for gi = 0, floor(h / AP / 5) do
      local gyy = y + AP * 3 + gi * AP * 5 + ((gi * 7 + i * 3) % 3) * AP
      love.graphics.setColor(0.30, 0.19, 0.09, 0.18)
      R(x + AP * ((gi + i) % 4), gyy, w * (0.35 + 0.1 * ((gi * 5 + i) % 5)), AP)
    end
    love.graphics.setColor(1, 0.9, 0.7, 0.16)
    R(x, y, AP, h)
    love.graphics.setColor(0, 0, 0, 0.22)
    R(x + w - AP, y, AP, h)
    love.graphics.setColor(0.62, 0.45, 0.26)
    R(x, y, w, AP)
    love.graphics.setColor(0.38, 0.26, 0.14)
    R(x, y + h - AP, w, AP)
    local vx, vy, vw, vh = x + 3 * u, y + 3 * u, w - 6 * u, floor(h * 0.50)
    love.graphics.setColor(0.30, 0.20, 0.09)
    R(vx - AP, vy - AP, vw + 2 * AP, vh + 2 * AP) -- (a brass frame round the velvet)
    love.graphics.setColor(0.62, 0.46, 0.20)
    R(vx - AP, vy - AP, vw + 2 * AP, AP)
    R(vx - AP, vy - AP, AP, vh + 2 * AP)
    love.graphics.setColor(0.09, 0.06, 0.09)
    R(vx, vy, vw, vh)
    for vi = 0, 3 do -- (the velvet, lighter toward the middle)
      love.graphics.setColor(0.17, 0.10, 0.15, 0.04 + 0.03 * vi)
      R(vx + AP * (4 - vi) * 2, vy + AP * (4 - vi) * 2, vw - AP * (4 - vi) * 4, vh - AP * (4 - vi) * 4)
    end
    love.graphics.setColor(0, 0, 0, 0.45)
    R(vx, vy, vw, AP * 2)
    R(vx, vy, AP * 2, vh)
    local e = compendium.entry("enemy", kind)
    local mounted = level > 0
    if e then
      compendium.drawIcon(e, vx + 2 * u, vy + 2 * u, vw - 4 * u, vh - 4 * u, slain == 0 and not mounted, mounted and 1 or (slain > 0 and 0.6 or 1), plaqueScale)
    end
    if mounted then
      love.graphics.setColor(1, 0.9, 0.55, 0.08)
      R(vx, vy, vw, vh)
    end
    -- brass name plate
    local ny = vy + vh + 3 * u
    local nh = floor(F.small:getHeight() + 2 * u)
    love.graphics.setColor(mounted and 0.78 or 0.42, mounted and 0.62 or 0.36, mounted and 0.30 or 0.22)
    R(x + 2 * u, ny, w - 4 * u, nh)
    love.graphics.setColor(1, 0.95, 0.7, 0.35)
    R(x + 2 * u, ny, w - 4 * u, AP)
    love.graphics.setColor(0, 0, 0, 0.28)
    R(x + 2 * u, ny + nh - AP, w - 4 * u, AP)
    local name = t.fitText(F.small, m.name, w - 6 * u)
    ink(name, x + (w - F.small:getWidth(name)) / 2, ny + (nh - F.small:getHeight()) / 2, F.small, { 0.18, 0.10, 0.04 }, mounted and 0.95 or 0.6)
    -- nails: a row of eight, brass for each level
    local nyl = ny + nh + 4 * u
    local nr = AP
    for k = 1, meta.MOUNT_MAX do
      local nx = x + w / 2 + ((k - 1) % 4 - 1.5) * 6 * u
      local nyy = nyl + floor((k - 1) / 4) * 5 * u
      love.graphics.setColor(0.12, 0.08, 0.05)
      love.graphics.circle("fill", nx, nyy, nr + 0.6)
      if k <= level then
        love.graphics.setColor(0.95, 0.78, 0.35)
        love.graphics.circle("fill", nx, nyy, nr)
        love.graphics.setColor(1, 0.97, 0.78)
        R(nx - nr * 0.5, nyy - nr * 0.5, AP, AP)
      end
    end
    -- what it gives, or how many are waiting to be mounted, in the space under the nails
    local ty2 = nyl + 12 * u
    local info = mounted and meta.mountEffect(kind, level) or (slain > 0 and "Ready to mount" or "")
    if info ~= "" then
      love.graphics.setFont(F.small)
      love.graphics.setColor(0.16, 0.09, 0.04, mounted and 0.9 or 0.65)
      love.graphics.printf(info, floor(x + 3 * u), floor(ty2), floor(w - 6 * u), "center")
    end
    -- a ready mark: a small glow at the top corner when an upgrade can be bought
    if ready then
      love.graphics.setColor(meta.SIGIL_COLOR[1], meta.SIGIL_COLOR[2], meta.SIGIL_COLOR[3], marks >= cost and 0.9 or 0.4)
      love.graphics.circle("fill", x + w - 3 * u, y + 3 * u, 1.4 * u)
    end
    if focused then
      t.focusFrame(x, y, w, h)
      hover = kind
    end
  end

  -- The card under the board
  local x, y, w, h = bx, by + bh + 4 * u, bw, floor(44 * u)
  t.panel(x, y, w, h, 0.85)
  if hover then
    local m = meta.MOUNTS[hover]
    local slain, level = meta.trophyCount(hover), meta.mountLevel(hover)
    local need, cost = meta.mountNeed(hover), meta.mountCost(hover)
    local maxed = level >= meta.MOUNT_MAX
    local ready = not maxed and slain >= need
    t.shadowPrint(m.name, x + 6 * u, y + 4 * u, F.head, t.TEXT)
    local ty = y + 4 * u + F.head:getHeight() + u
    local now = meta.mountEffect(hover, max(1, level))
    t.shadowPrint(level > 0 and ("Level " .. level .. ":  " .. now) or ("When mounted:  " .. now), x + 6 * u, ty, F.body, level > 0 and t.WARM or t.DIM)
    ty = ty + F.body:getHeight() + 0.5 * u
    if maxed then
      t.shadowPrint("Fully mounted.", x + 6 * u, ty, F.small, t.FAINT)
    else
      t.shadowPrint(level > 0 and ("Next level:  " .. meta.mountEffect(hover, level + 1)) or "", x + 6 * u, ty, F.small, ready and t.DIM or t.FAINT)
    end
    local right = x + w - 6 * u
    local status = slain == 0 and "None slain yet" or ("Elites slain: " .. slain .. (not maxed and slain < need and ("  (next at " .. need .. ")") or ""))
    t.shadowPrint(status, right - F.body:getWidth(status), y + 5 * u, F.body, slain > 0 and t.DIM or t.FAINT)
    if not maxed and ready then
      t.markPrice(tostring(cost), right, y + 5 * u + F.body:getHeight() + u, F.body, marks >= cost and meta.SIGIL_COLOR or t.DANGER)
    end
  else
    t.printCentered("Trophies", x + w / 2, y + 5 * u, F.body, t.WARM)
    t.wrapped("Point at a plaque. A mount is for good: its bonus applies in every run. Slay one elite of a kind to mount it, then five more for each upgrade. Each upgrade costs 1.2x the last and adds half as much as the one before.", x + 10 * u, y + 5 * u + F.body:getHeight() + u, w - 20 * u, F.small, t.FAINT)
  end
end

-- ===================================================================================================
-- The Prospector: the strongbox, the tool wall and the shelf
-- ===================================================================================================

-- Small pixel icons (10 x 10) for the tool wall
local ICONS = {
  strongbox = {
    "0000000000", "0111111110", "1222222221", "1222332221", "1111111111", "1444444441", "1444554441", "1444444441", "1111111111", "0000000000",
  },
  tithe = {
    "0000330000", "0003443000", "0001111000", "0012222100", "0122222210", "0122552210", "0122552210", "0122222210", "0112222110", "0001111000",
  },
  blasting = {
    "0000060000", "0000600000", "0111111000", "0155555100", "0155555100", "0111111000", "0155555100", "0155555100", "0111111000", "0000000000",
  },
  shelf = {
    "0000000000", "0001111000", "0112222110", "1222222221", "1222332221", "1223333221", "1222332221", "0112222110", "0001111000", "0000000000",
  },
}
local ICON_COL = {
  ["1"] = { 0.10, 0.07, 0.05 }, ["2"] = { 0.50, 0.50, 0.56 }, ["3"] = { 0.95, 0.78, 0.30 }, ["4"] = { 0.40, 0.24, 0.12 },
  ["5"] = { 0.86, 0.22, 0.16 }, ["6"] = { 0.9, 0.86, 0.6 },
}
local ICON_OVERRIDE = {
  tithe = { ["2"] = { 0.62, 0.48, 0.28 }, ["5"] = { 0.95, 0.78, 0.30 } },
  shelf = { ["2"] = { 0.45, 0.45, 0.5 }, ["3"] = { 0.9, 0.7, 0.25 } },
}

local function pixelIcon(id, x, y, p)
  local art = ICONS[id]
  local over = ICON_OVERRIDE[id] or {}
  for r = 1, #art do
    for c = 1, #art[r] do
      local ch = art[r]:sub(c, c)
      if ch ~= "0" then
        col(over[ch] or ICON_COL[ch])
        R(x + (c - 1) * p, y + (r - 1) * p, p, p)
      end
    end
  end
end

function pages.prospector(t)
  local u, F = t.u, t.F
  AP = PS(u)
  local marks = meta.marks()
  local inBox, cap = meta.bank(), meta.bankCap()
  local carry = t.runGold and t.runGold() or 0

  -- The strongbox, front on, lid thrown back, the gold heaped in it
  local gx, gy, gw = t.X(14), t.Y(36), floor(176 * u)
  t.shadowPrint("Strongbox", gx, gy, F.body, t.WARM)
  local cx = gx + gw / 2
  local boxW, boxH = floor(120 * u / AP / 2) * 2 * AP, floor(46 * u / AP) * AP
  local bxx, byy = floor((cx - boxW / 2) / AP) * AP, floor((gy + F.body:getHeight() + 56 * u) / AP) * AP
  -- the open lid, behind: a stepped slab, each row a pixel of art tall, outlined a pixel thick
  do
    local lidRows = max(6, floor(26 * u / AP))
    local steps = max(2, floor(6 * u / AP))
    for i = 0, lidRows - 1 do -- (from the box up)
      local inset = floor(i * steps / lidRows) * AP + AP * 2
      local ry = byy - (i + 1) * AP
      love.graphics.setColor(0.10, 0.09, 0.12)
      R(bxx + inset, ry, boxW - 2 * inset, AP)
      if i > 0 and i < lidRows - 1 then
        -- (the lid's inside, darker toward the hinge and lit toward the top, with a ridge now and then)
        local g = 0.20 + 0.10 * (i / lidRows) + (i % 6 == 0 and 0.05 or 0)
        love.graphics.setColor(g, g * 0.98, g * 1.14)
        R(bxx + inset + AP, ry, boxW - 2 * inset - 2 * AP, AP)
        love.graphics.setColor(1, 1, 1, 0.07)
        R(bxx + inset + AP, ry, AP * 2, AP) -- (a lit edge down the left)
        love.graphics.setColor(0, 0, 0, 0.18)
        R(bxx + boxW - inset - AP * 3, ry, AP * 2, AP)
      end
    end
  end
  -- gold: columns of coins rising out of the open top, taller with more in the box
  local fill = cap > 0 and min(1, inBox / cap) or 0
  local cols = 20
  local colW = (boxW - 12 * u) / cols
  local maxPile = 30 * u * fill
  for i = 1, cols do
    local k = (i - 0.5) / cols
    local bell = math.sin(k * math.pi) ^ 0.8
    local wob = 0.85 + 0.15 * math.sin(i * 12.9)
    local hgt = max(inBox > 0 and 2 * u or 0, maxPile * bell * wob + (inBox > 0 and 2 * u or 0))
    local cxx = bxx + 6 * u + (i - 1) * colW
    local coin = PS(u) * 2
    for yy = 0, floor(hgt / coin) do
      local py = byy + 3 * u - yy * coin
      love.graphics.setColor(0.98, 0.80, 0.30)
      R(cxx, py - coin, math.ceil(colW), coin)
      love.graphics.setColor(0.62, 0.45, 0.12)
      R(cxx, py - AP, math.ceil(colW), AP)
      love.graphics.setColor(1, 0.95, 0.65, 0.7)
      R(cxx + AP, py - coin, max(AP, floor(colW * 0.35)), AP)
    end
  end
  -- the box's front, on the same pixel grid: outline, body, a lit lip, two iron bands with rivets, the lock
  t.cast(bxx, byy, boxW, boxH)
  love.graphics.setColor(0.10, 0.09, 0.12)
  R(bxx - AP, byy - AP, boxW + 2 * AP, boxH + 2 * AP)
  love.graphics.setColor(0.30, 0.29, 0.34)
  R(bxx, byy, boxW, boxH)
  love.graphics.setColor(0.38, 0.37, 0.43)
  R(bxx, byy, boxW, AP * 2)
  local bandW = max(4, floor(6 * u / AP / 2) * 2) * AP
  for _, bandX in ipairs({ 0.12, 0.88 }) do
    local bx0 = floor((bxx + boxW * bandX - bandW / 2) / AP + 0.5) * AP
    love.graphics.setColor(0.10, 0.09, 0.12)
    R(bx0 - AP, byy, bandW + 2 * AP, boxH)
    love.graphics.setColor(0.18, 0.17, 0.21)
    R(bx0, byy, bandW, boxH)
    love.graphics.setColor(0.6, 0.58, 0.64)
    for k = 0, 2 do
      R(bx0 + floor(bandW / AP / 2) * AP - AP, byy + AP * 4 + k * floor(15 * u / AP) * AP, AP * 2, AP * 2) -- (rivets)
    end
  end
  -- lock plate, with a blocky keyhole
  local lw, lh = floor(14 * u / AP / 2) * 2 * AP, floor(16 * u / AP) * AP
  local lx, ly = floor((cx - lw / 2) / AP + 0.5) * AP, floor((byy + 10 * u) / AP) * AP
  love.graphics.setColor(0.10, 0.08, 0.04)
  R(lx - AP, ly - AP, lw + 2 * AP, lh + 2 * AP)
  love.graphics.setColor(0.60, 0.50, 0.22)
  R(lx, ly, lw, lh)
  love.graphics.setColor(0.10, 0.08, 0.04)
  local kx, ky = lx + lw / 2, ly + AP * 3
  R(kx - AP, ky, AP * 2, AP)
  R(kx - AP * 2, ky + AP, AP * 4, AP * 2)
  R(kx - AP, ky + AP * 3, AP * 2, AP)
  R(kx - AP, ky + AP * 4, AP * 2, AP * 4)
  -- the depth: plate seams, a lit and a shadowed edge on the bands and the lock, scratches, a dark foot and a shadow on the floor
  love.graphics.setColor(0, 0, 0, 0.16)
  for sxm = AP * 8, boxW - AP * 8, AP * 16 do
    R(bxx + sxm, byy + AP * 2, AP, boxH - AP * 4)
  end
  love.graphics.setColor(1, 1, 1, 0.05)
  for sxm = AP * 9, boxW - AP * 8, AP * 16 do
    R(bxx + sxm, byy + AP * 2, AP, boxH - AP * 4)
  end
  for _, bandX in ipairs({ 0.12, 0.88 }) do
    local bx0 = floor((bxx + boxW * bandX - bandW / 2) / AP + 0.5) * AP
    love.graphics.setColor(0.36, 0.35, 0.42)
    R(bx0, byy + AP * 2, AP, boxH - AP * 2)
    love.graphics.setColor(0.09, 0.08, 0.11)
    R(bx0 + bandW - AP, byy + AP * 2, AP, boxH - AP * 2)
  end
  love.graphics.setColor(0.82, 0.70, 0.36)
  R(lx, ly, lw, AP)
  R(lx, ly, AP, lh)
  love.graphics.setColor(0.40, 0.32, 0.12)
  R(lx, ly + lh - AP, lw, AP)
  R(lx + lw - AP, ly, AP, lh)
  love.graphics.setColor(0.10, 0.09, 0.12, 0.45)
  R(bxx, byy + boxH - AP * 2, boxW, AP * 2)
  for i = 0, 11 do
    local h = (i * 37 + 11) % 97
    love.graphics.setColor(1, 1, 1, 0.10)
    R(bxx + AP * 6 + (h * 13 % max(1, floor(boxW / AP) - 12)) * AP, byy + AP * 4 + (h * 7 % max(1, floor(boxH / AP) - 8)) * AP, AP * (1 + h % 3), AP)
  end
  love.graphics.setColor(0, 0, 0, 0.32)
  R(bxx - AP * 2, byy + boxH + AP, boxW + AP * 4, AP * 2)
  love.graphics.setColor(0, 0, 0, 0.16)
  R(bxx - AP * 4, byy + boxH + AP * 3, boxW + AP * 8, AP)
  -- its readout: what is in the box
  local readout = inBox .. " / " .. cap
  t.printCentered(readout, cx, byy + boxH + 4 * u, F.head, { 1, 0.85, 0.4 })
  t.printCentered("gold kept through death.  You carry " .. carry, cx, byy + boxH + 4 * u + F.head:getHeight(), F.small, t.DIM)
  -- clicking the box does the obvious thing
  local focusedBox = t.widget({ id = "camp:strongbox", x = bxx, y = byy - 28 * u, w = boxW, h = boxH + 28 * u, activate = function()
    if carry > 0 and inBox < cap then
      t.act("deposit")
      audio.play("coin")
    elseif inBox > 0 then
      t.act("withdraw")
      audio.play("coin")
    else
      audio.play("deny")
    end
  end })
  if focusedBox then
    t.focusFrame(bxx - 2 * u, byy - 28 * u, boxW + 4 * u, boxH + 30 * u)
  end
  local btnY = byy + boxH + 4 * u + F.head:getHeight() + F.small:getHeight() + 5 * u
  local bwid, bhh = floor(80 * u), floor(13 * u)
  t.button("camp:deposit", "Put it in", floor(cx - bwid - 3 * u), floor(btnY), bwid, bhh, function()
    t.act("deposit")
    audio.play("coin")
  end, { disabled = carry <= 0 or inBox >= cap })
  t.button("camp:withdraw", "Take it all out", floor(cx + 3 * u), floor(btnY), bwid, bhh, function()
    t.act("withdraw")
    audio.play("coin")
  end, { disabled = inBox <= 0 })

  -- The tool wall (right): a plank per upgrade, its picture hung on it
  local x, y, w = t.X(200), t.Y(36), floor(186 * u)
  t.shadowPrint("On the wall", x, y, F.body, t.WARM)
  y = y + F.body:getHeight() + 2 * u
  local hoverUp
  local p = PS(u)
  for _, up in ipairs(upgradesFor("prospector")) do
    local h = floor(16 * u)
    local tier, cost = meta.tier(up.id), meta.nextCost(up.id)
    local focused = t.widget({ id = "camp:up:" .. up.id, x = x, y = y, w = w, h = h, activate = function()
      if meta.buy(up.id) then
        audio.play("buy")
      else
        audio.play("deny")
      end
    end })
    t.panel(x, y, w, h, focused and 0.95 or 0.82) -- (the same outlined card as every other person's options)
    -- the tool, on a nail
    local iy = y + (h - 10 * p) / 2
    local owned = tier > 0
    love.graphics.setColor(1, 1, 1, owned and 1 or 0.5)
    pixelIcon(up.id, x + 4 * u, iy, p)
    local ty = y + (h - F.body:getHeight()) / 2
    t.shadowPrint(up.name, x + 4 * u + 10 * p + 4 * u, ty, F.body, focused and t.TEXT or t.DIM)
    local px = x + 4 * u + 10 * p + 4 * u + F.body:getWidth(up.name) + 4 * u
    for k = 1, #up.costs do
      love.graphics.setColor(k <= tier and t.WARM or { 0.25, 0.22, 0.3 })
      R(px + (k - 1) * 4 * u, ty + F.body:getHeight() / 2 - 1.2 * u, math.ceil(2.6 * u), math.ceil(2.6 * u))
    end
    if cost then
      t.markPrice(tostring(cost), x + w - 4 * u, ty, F.body, marks >= cost and meta.SIGIL_COLOR or t.DANGER)
    else
      t.shadowPrint("Done", x + w - 4 * u - F.body:getWidth("Done"), ty, F.body, t.FAINT)
    end
    if focused then
      t.focusFrame(x, y, w, h)
      hoverUp = up
    end
    y = y + h + 3 * u
  end
  -- what the hovered tool does
  local dh = floor(20 * u)
  t.wrapped(hoverUp and hoverUp.desc or "Hang a tool on the wall by buying it.", x, y + u, w, F.small, hoverUp and t.DIM or t.FAINT)
  y = y + dh + 2 * u

  -- The shelf: one perk kept through death (once it is bought)
  if meta.tier("shelf") <= 0 and not meta.bankedPerk() then
    return
  end
  local perks = require("src.perks")
  t.shadowPrint("Perk shelf", x, y, F.body, t.WARM)
  y = y + F.body:getHeight() + 2 * u
  local shelved = meta.bankedPerk()
  local function plank(py)
    love.graphics.setColor(0.17, 0.11, 0.07)
    R(x - AP, py, w + 2 * AP, 4 * u)
    love.graphics.setColor(0.46, 0.32, 0.18)
    R(x, py, w, 3 * u)
    love.graphics.setColor(1, 1, 1, 0.08)
    R(x, py, w, AP)
  end
  if shelved then
    local def = perks.defs[shelved]
    local entry = compendium.entry("perk", shelved)
    local isz = floor(24 * u)
    plank(y + isz + 3 * u)
    if entry then
      compendium.drawIcon(entry, x + 6 * u, y + 2 * u, isz, isz)
    end
    t.shadowPrint(def.name, x + isz + 12 * u, y + 2 * u, F.body, def.color)
    t.wrapped(def.desc, x + isz + 12 * u, y + 2 * u + F.body:getHeight() + u, w - isz - 16 * u, F.small, t.DIM)
    local have = false
    for _, id in ipairs(t.runPerks and t.runPerks() or {}) do
      have = have or id == shelved
    end
    local by = y + isz + 9 * u
    t.button("camp:perktake", have and "You already carry one" or "Take it back", floor(x), floor(by), floor(w), floor(12 * u), function()
      t.act("perktake")
      audio.play("pickup")
    end, { disabled = have })
  else
    local mine = {}
    for _, id in ipairs(t.runPerks and t.runPerks() or {}) do
      if meta.canShelve(id) then
        mine[#mine + 1] = id
      end
    end
    if #mine == 0 then
      plank(y + 14 * u)
      t.wrapped("Nothing to keep yet. Bring a perk up from below and he will hold on to it, through death.", x, y, w, F.small, t.FAINT)
    else
      local cell, gap = floor(20 * u), floor(3 * u)
      local colsN = max(1, floor((w + gap) / (cell + gap)))
      local hovered
      for i, id in ipairs(mine) do
        local cx2 = x + ((i - 1) % colsN) * (cell + gap)
        local cy2 = y + floor((i - 1) / colsN) * (cell + gap + 4 * u)
        if (i - 1) % colsN == 0 then
          plank(cy2 + cell + 1 * u)
        end
        local focused = t.widget({ id = "camp:perkstore" .. id, x = cx2, y = cy2, w = cell, h = cell, activate = function()
          t.act("perkstore", id)
          audio.play("buy")
        end })
        t.slotBox(cx2, cy2, cell, cell, focused and "focus" or nil, t.SLOT_REST)
        local entry = compendium.entry("perk", id)
        if entry then
          compendium.drawIcon(entry, cx2 + 2 * u, cy2 + 2 * u, cell - 4 * u, cell - 4 * u)
        end
        if focused then
          hovered = perks.defs[id]
        end
      end
      local ry = y + math.ceil(#mine / colsN) * (cell + gap + 4 * u) + 2 * u
      if hovered then
        t.shadowPrint(hovered.name, x, ry, F.body, hovered.color)
        t.wrapped(hovered.desc, x, ry + F.body:getHeight() + u, w, F.small, t.DIM)
      else
        t.wrapped("Pick a perk to put on the shelf. It leaves your run when you hand it over.", x, ry, w, F.small, t.FAINT)
      end
    end
  end
end

return pages
