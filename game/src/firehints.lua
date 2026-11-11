-- The campfire's smoke pictures: press E at the fire and a cloud of smoke
-- rises from the flames with a little animated picture in it showing one
-- control (walking, shooting, reloading, sliding, rolling, the weapon panel); E again moves to the next
-- picture. The cloud and picture are drawn pixel by pixel in greyscale into a
-- small canvas (so every pixel sits on the game's grid) and the canvas is drawn
-- slightly see-through in world pixels (draw, with the flames); the prompt by the
-- fire is drawn at full resolution (drawScreen). The scene supplies the fire's position.
local input = require("src.input")

local firehints = {}

local PAGES = {
  { id = "move" },
  { id = "fire" },
  { id = "reload" },
  { id = "slide" },
  { id = "roll" },
  { id = "inventory" },
}

local OPEN_FOR = 14 -- seconds before an untouched cloud drifts away
local NEAR = 24 -- how close the hunter must stand (tight, so the camp's other prompts never overlap it)
local GROW = 1.4 -- seconds for the smoke to rise and billow into its cloud
local SEE_THROUGH = 0.7

-- The canvas: CW x CH world pixels, its bottom edge on the ground at the fire.
-- (CX, CY) is the cloud's centre in it; (CX, BASE) is where the smoke leaves the flames.
local CW, CH = 128, 120
local CX, CY = 64, 40
local BASE = 108

local open, page, t, idle = false, 1, 0, 0
local grow, alpha, drift = 0, 0, 0 -- grow: 0..1 (the smoke rising into its cloud); alpha: how solid; drift: how far it has lifted while fading
local canvas

-- Greyscale: the cloud, and the (slightly darker) picture drawn on it
local CLOUD, RIM = 0.85, 0.56
local S1, S2, S3, LIGHT = 0.68, 0.5, 0.3, 0.97

-- The cloud's puffs: x, y, radius about its centre (canvas pixels)
local PUFFS = {
  { -42, 10, 19 }, { -20, -4, 24 }, { 6, -11, 24 }, { 32, -4, 22 }, { 50, 12, 16 },
  { -4, 12, 22 }, { 24, 16, 19 }, { -54, 20, 11 }, { -36, 22, 13 }, { 38, 22, 14 },
}
for _, p in ipairs(PUFFS) do -- (snug around the picture)
  for i = 1, 3 do
    p[i] = math.floor(p[i] * 0.85 + 0.5)
  end
end
-- The tail of smoke from the flames up to the cloud: x, y, radius
local TAIL = { { 0, 68, 3 }, { -2, 58, 4 }, { 2, 47, 5 }, { -1, 36, 7 } }

-- 3x5 letters for the keycaps
local GLYPHS = {
  A = "010101111101101", C = "011100100100011", D = "110101101101110", L = "100100100100111",
  R = "110101110101101", S = "011100010001110", T = "111010010010010", W = "101101101111101",
  B = "110101110101110", F = "111100110100100", H = "101101111101101", I = "111010010010111",
}

local function grey(v, a)
  love.graphics.setColor(v, v, v, a or 1)
end

-- Every picture pixel is whole
local function R(x, y, w, h)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

-- Mirrored rectangle: dx is measured out from x in the facing direction f
local function mrect(x, f, dx, y, w, h)
  R(f > 0 and x + dx or x - dx - w, y, w, h)
end

-- A pixel line, two pixels thick
local function pline(x0, y0, x1, y1)
  local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
  for i = 0, steps do
    R(x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps, 1, 2)
  end
end

-- A filled circle in whole pixels
local function disc(cx, cy, r)
  cx, cy, r = math.floor(cx), math.floor(cy), math.floor(r + 0.5)
  if r < 1 then
    return
  end
  for dy = -r, r do
    local w = math.floor(math.sqrt(r * r - dy * dy) + 0.5)
    love.graphics.rectangle("fill", cx - w, cy + dy, w * 2 + 1, 1)
  end
end

local function glyph(ch, x, y)
  local g = GLYPHS[ch]
  for i = 0, 14 do
    if g:sub(i + 1, i + 1) == "1" then
      R(x + i % 3, y + math.floor(i / 3), 1, 1)
    end
  end
end

-- A keycap: lit = pressed (dark with a pale letter), else pale with a dark letter
local function keycap(label, x, y, lit)
  local w = #label * 4 + 3
  grey(S3)
  R(x, y + 8, w, 1) -- (the key's lower edge)
  R(x - 1, y - 1, w + 2, 9)
  grey(lit and S3 or LIGHT)
  R(x, y, w, 8)
  grey(lit and LIGHT or S3)
  for i = 1, #label do
    glyph(label:sub(i, i), x + 2 + (i - 1) * 4, y + 1)
  end
end

-- The mouse: a body with two buttons and a wheel; the lit button is dark
local function mouse(x, y, leftLit, rightLit)
  grey(S3)
  R(x - 1, y - 1, 12, 17)
  grey(LIGHT)
  R(x, y, 10, 15)
  grey(leftLit and S3 or LIGHT)
  R(x, y, 4, 6)
  grey(rightLit and S3 or LIGHT)
  R(x + 6, y, 4, 6)
  grey(S3)
  R(x + 4, y, 2, 7) -- (the wheel, between the buttons)
  R(x, y + 6, 10, 1)
end

-- The hunter in silhouette: standing (with the stride a walking leg pair takes) or sliding on his back
local function hunter(x, feet, f, stride, slide)
  if slide then
    grey(S3)
    mrect(x, f, -3, feet - 4, 6, 3) -- body
    mrect(x, f, -6, feet - 6, 3, 3) -- head, at the back
    mrect(x, f, 3, feet - 3, 5, 2) -- legs, out in front
    grey(S2)
    mrect(x, f, -7, feet - 7, 5, 1) -- hat
    return
  end
  grey(S3)
  local a, b = stride and 1 or 0, stride and 0 or 1
  R(x - 2, feet - 4 - a, 1, 4 + a) -- legs
  R(x + 1, feet - 4 - b, 1, 4 + b)
  R(x - 2, feet - 9, 4, 5) -- body
  R(x - 1, feet - 12, 3, 3) -- head
  grey(S2)
  R(x - 3, feet - 13, 5, 1) -- hat
  R(x - 2, feet - 15, 3, 2)
end

local function ground(feet)
  grey(S1)
  R(CX - 32, feet, 40, 1)
end

local function pageMove()
  local u = t % 4
  local x, f, lit, hop = 0, 1, nil, 0
  if u < 1.5 then
    x, f, lit = -26 + u / 1.5 * 16, 1, "D"
  elseif u < 2 then
    x, f, lit, hop = -10, 1, "W", math.floor(math.sin((u - 1.5) / 0.5 * math.pi) * 5)
  elseif u < 3.5 then
    x, f, lit = -10 - (u - 2) / 1.5 * 16, -1, "A"
  else
    x, f = -26, 1
  end
  local feet = CY + 12
  ground(feet)
  hunter(CX + x, feet - hop, f, math.floor(t * 8) % 2 == 0, false)
  keycap("W", CX + 12, CY - 12, lit == "W")
  keycap("A", CX + 4, CY - 3, lit == "A")
  keycap("S", CX + 12, CY - 3, false)
  keycap("D", CX + 20, CY - 3, lit == "D")
end

local function pageFire()
  local u = t % 0.9
  local x, feet = CX - 22, CY + 12
  local kick = u < 0.1 and 1 or 0
  ground(feet)
  hunter(x, feet, 1, false, false)
  grey(S3)
  R(x + 1 - kick, feet - 8, 7, 2) -- arm and gun
  R(x + 1 - kick, feet - 7, 3, 3)
  grey(S1)
  R(x + 4 - kick, feet - 8, 6, 1)
  if u < 0.07 then
    grey(LIGHT) -- muzzle flash
    R(x + 10, feet - 10, 4, 4)
    grey(S1)
    R(x + 10, feet - 9, 2, 2)
  end
  if u > 0.04 and u < 0.3 then
    grey(LIGHT) -- the bullet's streak
    R(x + 12 + (u - 0.04) / 0.26 * 12, feet - 8, 4, 1)
  end
  mouse(CX + 14, CY - 10, u < 0.2, false)
end

local function pageReload()
  local u = t % 2.2
  local x, feet = CX - 22, CY + 12
  ground(feet)
  hunter(x, feet, 1, false, false)
  grey(S3)
  pline(x - 1, feet - 5, x + 2, feet - 8) -- stock
  grey(S1)
  if u < 1.5 then -- broken open: the barrel tips down
    pline(x + 2, feet - 8, x + 10, feet - 4)
    if u < 0.7 then -- the spent shell tumbles out
      local k = u / 0.7
      grey(S2)
      R(x + 7 + k * 3, feet - 6 + k * 6, 2, 3)
    else -- a fresh one is pushed in
      local k = math.min(1, (u - 0.7) / 0.7)
      grey(S3)
      R(x + 12 - k * 4, feet - 17 + k * 11, 2, 3)
    end
  else -- snapped shut, level
    pline(x + 2, feet - 8, x + 12, feet - 8)
    if u < 1.75 then
      grey(LIGHT)
      R(x + 13, feet - 12, 1, 2)
      R(x + 15, feet - 10, 2, 1)
    end
  end
  mouse(CX + 14, CY - 10, false, u < 0.3 or (u > 1.45 and u < 1.7))
end

local function pageSlide()
  local u = t % 3
  local feet = CY + 12
  local x, slide = -22, false
  if u < 0.8 then -- running up
    x = -26 + u / 0.8 * 8
  elseif u < 2.2 then -- sliding, slower and slower
    local k = (u - 0.8) / 1.4
    x, slide = -18 + (1 - (1 - k) ^ 2) * 18, true
  else
    x = 0 - (u - 2.2) * 2
  end
  ground(feet)
  hunter(CX + x, feet, 1, math.floor(t * 8) % 2 == 0, slide)
  if slide then
    grey(S1) -- dust kicked up behind
    for i = 1, 4 do
      R(CX + x - 10 - i * 3 - (t * 20) % 3, feet - 1 - (i % 2) * 2, 2, 1)
    end
  end
  keycap("CTRL", CX + 8, CY - 8, slide)
end

-- A dodge roll: the hunter balls up and tumbles along
local function pageRoll()
  local u = t % 2.6
  local feet = CY + 12
  local x, rolling = -26, false
  if u >= 0.5 and u < 1.1 then
    x, rolling = -26 + (u - 0.5) / 0.6 * 28, true
  elseif u >= 1.1 then
    x = 2
  end
  ground(feet)
  if rolling then
    local bx = CX + x
    grey(S3)
    R(bx - 3, feet - 6, 6, 6)
    grey(S2) -- (the hat, going round)
    local mark = ({ { 0, 0 }, { 4, 0 }, { 4, 4 }, { 0, 4 } })[math.floor(t * 16) % 4 + 1]
    R(bx - 3 + mark[1], feet - 6 + mark[2], 2, 2)
    grey(S1) -- dust behind
    for i = 1, 3 do
      R(bx - 6 - i * 3, feet - 1 - (i % 2) * 2, 2, 1)
    end
  else
    hunter(CX + x, feet, 1, false, false)
  end
  keycap("SHIFT", CX + 6, CY - 8, rolling)
end

-- The weapon panel: Tab pops open a row of guns, and the selection moves along it
local function pageInventory()
  local u = t % 2.8
  local open01 = math.min(1, u / 0.35) -- (opening, then open until it shuts)
  if u > 2.4 then
    open01 = math.max(0, 1 - (u - 2.4) / 0.3)
  end
  keycap("TAB", CX - 32, CY - 4, u < 0.35 or u > 2.4)
  local px, py = CX - 8, CY - 12
  local h = math.floor(24 * open01 + 0.5)
  if h < 3 then
    return
  end
  grey(S3)
  R(px - 1, py + 12 - h / 2 - 1, 42, h + 2)
  grey(S1)
  R(px, py + 12 - h / 2, 40, h)
  if open01 >= 1 then
    local sel = math.floor((u - 0.5) / 0.6) % 3
    for i = 0, 2 do
      local sx, sy = px + 2 + i * 13, py + 7
      grey(i == sel and S3 or S2)
      R(sx - 1, sy - 1, 12, 12)
      grey(LIGHT)
      R(sx, sy, 10, 10)
      grey(S3)
      if i == 0 then -- revolver
        R(sx + 1, sy + 3, 7, 2)
        R(sx + 1, sy + 5, 2, 3)
      elseif i == 1 then -- shotgun
        R(sx, sy + 3, 9, 1)
        R(sx, sy + 4, 4, 2)
        R(sx + 4, sy + 4, 4, 1)
      else -- rifle
        R(sx, sy + 4, 10, 1)
        R(sx, sy + 5, 3, 2)
        R(sx + 4, sy + 2, 3, 2)
      end
    end
  end
end

local PAGE_DRAW = { pageMove, pageFire, pageReload, pageSlide, pageRoll, pageInventory }

-- Is the hunter by the fire (fx, and the ground y under it)
local function near(player, fx, fy)
  local px, py = player:center()
  return math.abs(px - fx) < NEAR and math.abs(py - fy) < 24
end

-- E at the fire: opens the cloud, or moves to the next picture. True if it was used.
function firehints.interact(player, fx, fy)
  if player.dead or not near(player, fx, fy) then
    return false
  end
  if open and grow > 0.9 then
    page = page % #PAGES + 1
  else
    open, page = true, 1
    if alpha <= 0 then
      grow = 0
    end
  end
  t, idle = 0, 0
  return true
end

function firehints.update(dt, player, fx, fy)
  if open then
    t = t + dt
    idle = idle + dt
    grow = math.min(1, grow + dt / GROW)
    alpha = math.min(1, alpha + dt * 5)
    drift = 0
    if idle > OPEN_FOR or not player or math.abs(player:center() - fx) > 120 then
      open = false
    end
  else
    alpha = math.max(0, alpha - dt * 1.6) -- (thins out as it lifts away)
    drift = drift + dt * 9
    if alpha <= 0 then
      grow = 0
    end
  end
end

local function ease(g)
  return 1 - (1 - g) * (1 - g)
end

-- The cloud and its picture, into the canvas
local function paint()
  local c = love.timer.getTime()
  local ymin, ymax = 1e9, -1e9
  for _, p in ipairs(PUFFS) do
    ymin, ymax = math.min(ymin, p[2]), math.max(ymax, p[2])
  end
  -- Where each puff is now: they leave the flames in turn (the low ones first) and swell into place
  local shapes = {}
  for j, p in ipairs(TAIL) do
    local g = ease(math.max(0, math.min(1, (grow * 4 - (j - 1) * 0.35) / 0.9)))
    shapes[#shapes + 1] = { CX + p[1] + math.floor(math.sin(c * 2 + j) * 1.5 + 0.5), CY + p[2], p[3] * g }
  end
  for _, p in ipairs(PUFFS) do
    local d = 0.5 * (ymax - p[2]) / (ymax - ymin)
    local g = ease(math.max(0, math.min(1, (grow - 0.15 - d * 0.6) / 0.4)))
    local fx, fy = CX + p[1], CY + p[2]
    shapes[#shapes + 1] = { CX + (fx - CX) * g, (BASE - 30) + (fy - (BASE - 30)) * g, p[3] * g }
  end
  grey(RIM)
  for _, s in ipairs(shapes) do
    disc(s[1], s[2], s[3] + 1)
  end
  grey(CLOUD)
  for _, s in ipairs(shapes) do
    disc(s[1], s[2], s[3])
  end
  if grow >= 0.95 then
    PAGE_DRAW[page]()
  end
end

-- In world pixels (with the flames)
function firehints.draw(fx, fy)
  if alpha <= 0 then
    return
  end
  if not canvas then
    canvas = love.graphics.newCanvas(CW, CH)
    canvas:setFilter("nearest", "nearest")
  end
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("alpha")
  love.graphics.setLineStyle("rough")
  paint()
  love.graphics.pop()
  local a = alpha * SEE_THROUGH
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.setColor(a, a, a, a)
  love.graphics.draw(canvas, math.floor(fx) - CX, math.floor(fy) - 12 - BASE - math.floor(drift))
  love.graphics.setBlendMode("alpha")
end

local function shadowed(text, x, y, c, a)
  love.graphics.setColor(0, 0, 0, 0.85 * a)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.print(text, x, y)
end

-- At full resolution: just the prompt by the fire (the pictures say the rest)
function firehints.drawScreen(toScreen, font, player, fx, fy)
  if not open and alpha <= 0 and near(player, fx, fy) and not player.dead then
    love.graphics.setFont(font)
    local text = "[" .. input.label("interact") .. "] Learn the controls"
    local sx, sy = toScreen(fx, fy - 26)
    shadowed(text, math.floor(sx - font:getWidth(text) / 2), math.floor(sy - font:getHeight()), { 1, 0.92, 0.7 }, 1)
  end
end

return firehints
