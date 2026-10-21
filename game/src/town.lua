-- The town (design doc §11a-xv): the hub grows from a hunter's camp into a
-- western town as the people found below move in.
--
-- The ground plan never changes: a row of fixed LOTS along the street, each
-- with a raised wooden porch and three steps up (real terrain, built with the
-- world), so everyone is always in the same place. What stands on a lot
-- depends on how many of the six people are at camp (town.stage):
--
--   stage 1  (up to half: 0-3 people)  a camp: the stalls as they were
--   stage 2  (4-5 people)              a settlement: plank shacks with shingle roofs,
--            porch posts, lanterns and a sign over the ridge
--   stage 3  (all 6)                   a town: false-front buildings with
--            striped awnings, lit windows, painted signs and cornices, a
--            welcome sign, telegraph poles with a wire along the street
--
-- A lot is { id, x (porch centre), top (set when built: the porch's surface),
-- accent, sign }. Adding a building or a person later means adding a lot or
-- changing one's id; the look per stage is drawn from the lot's data.
local meta = require("src.meta")
local story = require("src.story")

local town = {}

town.PORCH_H = 8 -- how far the porch stands above the street
town.PORCH_HALF = 28 -- half its width
local STEP_W, STEPS = 3, 3 -- steps on the left end of each porch, 2 px a rise

town.LOTS = {
  { id = "apothecary", x = 520, accent = { 0.38, 0.55, 0.42 }, sign = "APOTHECARY" },
  { id = "cartographer", x = 586, accent = { 0.35, 0.45, 0.58 }, sign = "SURVEYS" },
  { id = "prospector", x = 652, accent = { 0.58, 0.42, 0.22 }, sign = "ASSAY" },
  { id = "taxidermist", x = 718, accent = { 0.42, 0.50, 0.30 }, sign = "TAXIDERMY" },
  { id = "board", x = 784, accent = { 0.45, 0.32, 0.20 }, sign = "WANTED" },
  { id = "sawbone", x = 1034, accent = { 0.40, 0.58, 0.56 }, sign = "DOCTOR" },
  { id = "gunsmith", x = 1100, accent = { 0.58, 0.30, 0.22 }, sign = "GUNS" },
  { id = "bartender", x = 1166, accent = { 0.55, 0.20, 0.26 }, sign = "SALOON" },
  { id = "hall", x = 1232, accent = { 0.52, 0.49, 0.43 }, sign = "TOWN HALL" },
}
local PEOPLE = { "gunsmith", "prospector", "apothecary", "cartographer", "bartender", "taxidermist", "sawbone" }

local byId = {}
for _, l in ipairs(town.LOTS) do
  byId[l.id] = l
end

function town.lot(id)
  return byId[id]
end

-- How many of the six are at camp, and the stage that makes
function town.count()
  local n = 0
  for _, id in ipairs(PEOPLE) do
    if meta.atCamp(id) then
      n = n + 1
    end
  end
  return n
end

function town.stage()
  local n = town.count()
  if n >= #PEOPLE then
    return 3
  elseif n * 2 > #PEOPLE then
    return 2
  end
  return 1
end

-- The street's x range (the welcome sign and the telegraph poles go at its ends)
local STREET_X0, STREET_X1 = 468, 1270

-- Terrain ------------------------------------------------------------------------------

local ctx = {} -- { world, surface, WOOD, SAND, AIR }: what the porches are built in

-- Works out every lot's ground plan (where its porch stands and how its steps
-- run down to the street). Nothing is built until someone lives there (town.sync).
function town.build(world, surface, WOOD, SAND, AIR)
  ctx = { world = world, surface = surface, WOOD = WOOD, SAND = SAND, AIR = AIR }
  for _, l in ipairs(town.LOTS) do
    local lo = l.x - town.PORCH_HALF - STEP_W * STEPS
    local minS = math.huge
    for x = lo, l.x + town.PORCH_HALF do
      minS = math.min(minS, surface(x))
    end
    l.ground = minS
    l.top = minS - town.PORCH_H
    l.built = false
  end
  town.sync(true)
end

-- The columns a lot's porch and steps fill: { x, top } each
local function columns(l)
  local surface = ctx.surface
  local out = {}
  local x0, x1 = l.x - town.PORCH_HALF, l.x + town.PORCH_HALF
  for x = x0, x1 do
    out[#out + 1] = { x, l.top }
  end
  local lo = x0 - STEP_W * STEPS
  -- the steps, from the porch's edge outward, evenly down to the street as it
  -- is where they end (so a dip in the ground never makes a step too tall
  -- to walk up: 5 px is the most)
  local rise = math.max(town.PORCH_H, surface(lo - 1) - l.top)
  for j = 1, STEPS do
    local top = l.top + math.floor(rise * j / (STEPS + 1))
    for k = 0, STEP_W - 1 do
      local x = x0 - STEP_W * (j - 1) - 1 - k
      if surface(x) > top then
        out[#out + 1] = { x, top }
      end
    end
  end
  return out
end

-- Whether a lot has anyone in it (the board stands from the start; the town
-- hall is built when all six have come)
local function occupied(l, stage)
  if l.id == "board" then
    return meta.boardOpen()
  elseif l.id == "hall" then
    return stage >= 3
  end
  return meta.atCamp(l.id)
end

local function setLot(l, on, quiet)
  local world, surface = ctx.world, ctx.surface
  local x0, x1 = math.huge, -math.huge
  for _, c in ipairs(columns(l)) do
    local x, top = c[1], c[2]
    if on then
      world:fillRect(x, top, x, surface(x) + 1, ctx.WOOD)
    else
      world:fillRect(x, top, x, surface(x) - 1, ctx.AIR)
      world:fillRect(x, surface(x), x, surface(x) + 1, ctx.SAND)
    end
    x0, x1 = math.min(x0, x), math.max(x1, x)
  end
  world:repaintRegion(x0 - 3, l.top - 4, x1 + 3, l.ground + 8)
  if not quiet then
    require("src.physics").rebuildRegion(x0 - 3, l.top - 4, x1 + 3, l.ground + 8)
    if on then
      local effects = require("src.effects")
      for _ = 1, 18 do
        effects.particle(x0 + love.math.random() * (x1 - x0), l.ground - 2, (love.math.random() - 0.5) * 50, -10 - love.math.random() * 40, 0.8, { 0.75, 0.6, 0.42 }, 60)
      end
      require("src.audio").play("clank", 0.5, 0.7)
    end
  end
  l.built = on
end

-- Builds a lot's porch when someone moves in (and takes it away if they are
-- not there: another save file). quiet: no dust (while the world is built).
function town.sync(quiet)
  if not ctx.world then
    return
  end
  local stage = town.stage()
  for _, l in ipairs(town.LOTS) do
    local want = occupied(l, stage)
    if want ~= l.built then
      setLot(l, want, quiet)
    end
  end
end

-- Pixel text ---------------------------------------------------------------------------

local drawClockHands -- (below)
local textImages = {}

-- A little signboard with the text in 3x5 letters; returns an image
local function textImage(text, bg, fg)
  local key = text .. bg[1] .. bg[2] .. bg[3]
  local img = textImages[key]
  if img then
    return img
  end
  local w, h = #text * 4 + 3, 9
  local data = love.image.newImageData(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if x == 0 or y == 0 or x == w - 1 or y == h - 1 then
        data:setPixel(x, y, bg[1] * 0.45, bg[2] * 0.45, bg[3] * 0.45, 1)
      else
        data:setPixel(x, y, bg[1], bg[2], bg[3], 1)
      end
    end
  end
  for i = 1, #text do
    local g = story.FONT[text:sub(i, i)]
    if g then
      for k = 0, 14 do
        if g:sub(k + 1, k + 1) == "1" then
          data:setPixel(2 + (i - 1) * 4 + k % 3, 2 + math.floor(k / 3), fg[1], fg[2], fg[3], 1)
        end
      end
    end
  end
  img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  textImages[key] = img
  return img
end

-- Drawing ------------------------------------------------------------------------------

local function R(c, x, y, w, h, a)
  love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1))
  love.graphics.rectangle("fill", x, y, w, h)
end

local function shade(c, k)
  return { math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k) }
end

local WOOD, WOOD_L, WOOD_D = { 0.45, 0.30, 0.16 }, { 0.60, 0.42, 0.22 }, { 0.28, 0.19, 0.10 }
local CREAM, CREAM_D = { 0.86, 0.80, 0.66 }, { 0.62, 0.56, 0.44 }
local SHINGLE, SHINGLE_D = { 0.40, 0.27, 0.20 }, { 0.28, 0.18, 0.14 }
local IRON_D = { 0.18, 0.18, 0.21 }

local function sign(text, cx, y, accent)
  local img = textImage(text, shade(accent, 1.15), CREAM)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(img, cx - math.floor(img:getWidth() / 2), y)
end

-- A lantern hanging at (x, y): the flame is drawn in drawEmissive
local function lantern(x, y)
  R(IRON_D, x, y, 1, 2)
  R(IRON_D, x - 1, y + 2, 3, 4)
end

-- Plank wall, with the seams of vertical boards
local function planks(x, y, w, h, c)
  R(c, x, y, w, h)
  local d = shade(c, 0.78)
  for px = x + 3, x + w - 1, 4 do
    R(d, px, y, 1, h)
  end
end

-- Little pictures for each building's front, 11 x 7: what each trade is about
local EMBLEM_COLORS = {
  k = { 0.14, 0.13, 0.16 }, g = { 0.62, 0.64, 0.70 }, w = { 0.50, 0.33, 0.17 }, r = { 0.80, 0.18, 0.16 },
  b = { 0.30, 0.50, 0.85 }, y = { 0.95, 0.76, 0.28 }, l = { 0.35, 0.75, 0.42 }, c = { 0.92, 0.88, 0.74 },
}
local EMBLEMS = {
  gunsmith = { "..kkkkkkkk.", "..kggggggkk", "..kkkkkkk..", ".....kk....", "....wkk....", "...wwk.....", "...ww......" },
  apothecary = { "....kkk....", ".....l.....", "....lll....", "...lllll...", "..lllllll..", "..lyyyyyl..", "...lllll..." },
  cartographer = { ".ccccccccc.", "cc.......cc", "c.k.kk.k..c", "c..kk..kk.c", "c.k..kk...c", "cc.......cc", ".ccccccccc." },
  prospector = { "..kkkkkk...", ".kg.....k..", "k...w....k.", ".....w.....", ".....w.....", ".....w.....", ".....w....." },
  bartender = { "..cccccc...", "..cyyyyc.cc", "..cyyyyc..c", "..cyyyyc..c", "..cyyyyc.cc", "..cccccc...", "..wwwwww..." },
  taxidermist = { "k.k.....k.k", "kkk.....kkk", ".kkk...kkk.", "..kkkkkkk..", "....www....", "....www....", "..........." },
  sawbone = { "....rrr....", "....rrr....", ".rrrrrrrrr.", ".rrrrrrrrr.", "....rrr....", "....rrr....", "..........." },
}

local function emblem(id, x, y)
  local rows = EMBLEMS[id]
  if not rows then
    return
  end
  for ry, row in ipairs(rows) do
    for rx = 1, #row do
      local c = EMBLEM_COLORS[row:sub(rx, rx)]
      if c then
        R(c, x + rx - 1, y + ry - 1, 1, 1)
      end
    end
  end
end

local function hash2(a, b)
  local n = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
  return n - math.floor(n)
end

-- Shutters: a slatted board beside a window (x = left edge, y = top, h = height)
local function shutter(x, y, h, c)
  R(shade(c, 0.62), x, y, 3, h)
  for sy = y + 1, y + h - 1, 2 do
    R(shade(c, 0.45), x, sy, 3, 1)
  end
  R(shade(c, 0.85), x, y, 1, h)
end

-- A window box under a window at (x, y): a plank trough with flowers in the trade's colours
local function flowerBox(x, y, w, id)
  R(WOOD_D, x, y, w, 3)
  R(WOOD, x, y, w, 1)
  local cols = { gunsmith = { 0.9, 0.35, 0.25 }, apothecary = { 0.95, 0.9, 0.4 }, cartographer = { 0.4, 0.6, 0.95 }, prospector = { 0.95, 0.65, 0.25 }, bartender = { 0.95, 0.4, 0.6 }, taxidermist = { 0.8, 0.5, 0.95 }, sawbone = { 0.95, 0.95, 0.95 } }
  local fc = cols[id] or { 0.95, 0.5, 0.5 }
  for fx = x + 1, x + w - 2 do
    R({ 0.22, 0.45, 0.2 }, fx, y - 1, 1, 1)
    if hash2(fx, y) < 0.6 then
      R(fc, fx, y - 2, 1, 1)
    end
  end
end

-- Stage 2: a plank shack with a shingle roof, porch posts, a sign over the ridge
local function shack(l)
  local cx, P, a = l.x, l.top, l.accent
  planks(cx - 27, P - 38, 54, 38, shade(a, 0.62))
  -- the roof: three courses of shingles, overhanging
  for row = 0, 3 do
    R(row % 2 == 0 and SHINGLE or SHINGLE_D, cx - 29 + row, P - 42 + row, 58 - row * 2, 1)
  end
  R(SHINGLE_D, cx - 29, P - 38, 58, 1)
  for sx = cx - 28, cx + 26, 3 do
    R(SHINGLE_D, sx, P - 41, 1, 3)
  end
  -- the porch roof, on two posts
  R(WOOD_D, cx - 29, P - 31, 58, 2)
  R(WOOD_L, cx - 29, P - 31, 58, 1)
  R(WOOD_D, cx - 29, P - 29, 2, 29)
  R(WOOD_D, cx + 27, P - 29, 2, 29)
  -- two small windows in the gable wall above it
  for _, wx in ipairs({ cx - 16, cx + 8 }) do
    R(WOOD_D, wx - 1, P - 38, 9, 6)
    R({ 0.30, 0.26, 0.20 }, wx, P - 37, 7, 4)
  end
  -- the sign, standing on the ridge
  R(WOOD_D, cx - 14, P - 47, 2, 6)
  R(WOOD_D, cx + 12, P - 47, 2, 6)
  sign(l.sign, cx, P - 54, a)
  lantern(cx - 28, P - 29)
  lantern(cx + 27, P - 29)
  -- the detail: weathered shingles, a stone chimney, shutters, the trade's emblem
  for row = 0, 3 do
    for sx = cx - 28 + row, cx + 26 - row do
      local hsh = hash2(sx, row + l.x)
      if hsh < 0.3 then
        R(SHINGLE_D, sx, P - 42 + row, 1, 1)
      elseif hsh > 0.85 then
        R({ 0.52, 0.38, 0.28 }, sx, P - 42 + row, 1, 1)
      end
    end
  end
  R({ 0.50, 0.46, 0.42 }, cx + 17, P - 50, 5, 9)
  R({ 0.36, 0.33, 0.30 }, cx + 17, P - 50, 1, 9)
  R({ 0.30, 0.27, 0.25 }, cx + 16, P - 51, 7, 2)
  for _, wx in ipairs({ cx - 16, cx + 8 }) do
    shutter(wx - 4, P - 38, 6, a)
    shutter(wx + 9, P - 38, 6, a)
    R({ 0.42, 0.37, 0.28 }, wx + 3, P - 37, 1, 4) -- the muntin
  end
  emblem(l.id, cx - 5, P - 39)
  R(shade(a, 0.5), cx - 27, P - 33, 54, 1) -- (a shadow line under the eaves)
end

-- Stage 3: a false-front building: striped awning, clapboard facade with
-- lit windows, a cornice and a painted sign on a raised parapet
local function facade(l)
  local cx, P, a = l.x, l.top, l.accent
  -- the side wall, in shadow, and the back wall under the awning
  R(shade(a, 0.4), cx + 28, P - 50, 3, 50)
  R(shade(a, 0.55), cx - 27, P - 30, 54, 30)
  for y = P - 28, P - 2, 4 do
    R(shade(a, 0.45), cx - 27, y, 54, 1)
  end
  -- the facade above: clapboard in the building's colour, cream trim
  R(a, cx - 28, P - 52, 56, 22)
  for y = P - 50, P - 32, 3 do
    R(shade(a, 0.82), cx - 28, y, 56, 1)
  end
  R(CREAM, cx - 28, P - 52, 56, 1)
  R(CREAM, cx - 28, P - 31, 56, 1)
  R(CREAM_D, cx - 28, P - 52, 1, 22)
  R(CREAM_D, cx + 27, P - 52, 1, 22)
  -- the windows (their glass lights up at night in drawEmissive)
  for _, wx in ipairs({ cx - 21, cx + 9 }) do
    R(CREAM, wx - 1, P - 49, 12, 14)
    R({ 0.20, 0.17, 0.14 }, wx, P - 48, 10, 12)
    R(CREAM, wx + 5, P - 48, 1, 12)
    R(CREAM, wx, P - 43, 10, 1)
  end
  -- the cornice and the parapet that carries the sign
  R(CREAM, cx - 30, P - 55, 60, 3)
  R(CREAM_D, cx - 30, P - 53, 60, 1)
  R(a, cx - 24, P - 66, 48, 11)
  R(CREAM, cx - 25, P - 67, 50, 2)
  R(CREAM, cx - 25, P - 66, 1, 11)
  R(CREAM, cx + 24, P - 66, 1, 11)
  sign(l.sign, cx, P - 65, a)
  -- the striped awning over the porch, scalloped, on posts
  R(WOOD_D, cx - 31, P - 31, 62, 2)
  for i = 0, 14 do
    local sx = cx - 31 + i * 4
    R(i % 2 == 0 and shade(a, 1.2) or CREAM, sx, P - 29, 4, 3)
    R(i % 2 == 0 and shade(a, 1.2) or CREAM, sx + 1, P - 26, 2, 1)
  end
  R(WOOD_D, cx - 30, P - 25, 2, 25)
  R(WOOD_D, cx + 28, P - 25, 2, 25)
  lantern(cx - 30, P - 25)
  lantern(cx + 29, P - 25)
  -- the detail: corner quoins, cornice dentils, shutters, window boxes, an emblem between the windows,
  -- tassels on the awning and a dotted frame round the sign
  for qy = P - 51, P - 32, 4 do
    R(CREAM, cx - 28, qy, 3, 2)
    R(CREAM_D, cx - 28, qy + 2, 2, 2)
    R(CREAM, cx + 25, qy, 3, 2)
    R(CREAM_D, cx + 26, qy + 2, 2, 2)
  end
  for dx = cx - 29, cx + 28, 3 do
    R(CREAM_D, dx, P - 54, 1, 1)
  end
  shutter(cx - 26, P - 48, 12, a)
  shutter(cx + 21, P - 48, 12, a)
  for _, wx in ipairs({ cx - 21, cx + 9 }) do
    flowerBox(wx - 1, P - 35, 12, l.id)
    R({ 0.62, 0.30, 0.30, 0.5 }, wx, P - 48, 3, 12) -- (a curtain drawn back)
    R({ 0.62, 0.30, 0.30, 0.5 }, wx + 7, P - 48, 3, 12)
  end
  emblem(l.id, cx - 5, P - 46)
  for fx = cx - 24, cx + 22, 6 do
    R(CREAM, fx, P - 64, 1, 1)
    R(CREAM, fx, P - 57, 1, 1)
  end
  for i = 0, 14 do
    local sx = cx - 31 + i * 4
    R(i % 2 == 0 and shade(a, 0.8) or CREAM_D, sx + 1, P - 25, 1, 1)
  end
  R({ 0, 0, 0, 0.18 }, cx - 27, P - 24, 54, 2) -- (the awning's shadow on the wall)
end

-- The hall's clock tells the computer's time. The hands (a few pixels, on the world's own pixel grid) are
-- worked out again only when the minute changes; the face is drawn with the rest of the hall.
local clockStamp, clockPixels = -1, {}

local function line(x0, y0, x1, y1, out)
  -- (Bresenham, from the middle of the face out to the tip)
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    out[#out + 1] = { x0, y0 }
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

local function clockHandsFor(stamp)
  local t = os.date("*t", stamp * 60)
  local out = {}
  local ma = (t.min / 60) * math.pi * 2
  local ha = (((t.hour % 12) + t.min / 60) / 12) * math.pi * 2
  line(0, 0, math.floor(math.sin(ha) * 3 + (math.sin(ha) >= 0 and 0.5 or -0.5)), math.floor(-math.cos(ha) * 3 + (-math.cos(ha) >= 0 and 0.5 or -0.5)), out)
  local hourN = #out
  line(0, 0, math.floor(math.sin(ma) * 5 + (math.sin(ma) >= 0 and 0.5 or -0.5)), math.floor(-math.cos(ma) * 5 + (-math.cos(ma) >= 0 and 0.5 or -0.5)), out)
  return out, hourN
end

local hourCount = 0
function drawClockHands(cx, cy)
  local stamp = math.floor(os.time() / 60)
  if stamp ~= clockStamp then
    clockStamp = stamp
    clockPixels, hourCount = clockHandsFor(stamp)
  end
  for i, p in ipairs(clockPixels) do
    -- (the short hour hand first, in a darker ink; the minute hand over it)
    if i <= hourCount then
      love.graphics.setColor(0.12, 0.10, 0.08)
    else
      love.graphics.setColor(0.2, 0.17, 0.14)
    end
    love.graphics.rectangle("fill", cx + p[1], cy + p[2], 1, 1)
  end
end

-- Strikes the hour on the hall's bell: once for each hour on the clock, as the hour comes round
local lastHour, chimesLeft, chimeTimer = nil, 0, 0
function town.tick(dt, hearer)
  local lot = byId.hall
  if not lot or not lot.built or not lot.top then
    return
  end
  local t = os.date("*t")
  if lastHour == nil then
    lastHour = t.hour -- (no chime for the hour already running when the world loads)
  elseif t.min == 0 and t.hour ~= lastHour then
    lastHour = t.hour
    chimesLeft = t.hour % 12 == 0 and 12 or t.hour % 12
    chimeTimer = 0
  end
  if chimesLeft > 0 then
    chimeTimer = chimeTimer - dt
    if chimeTimer <= 0 then
      chimeTimer = 1.7
      chimesLeft = chimesLeft - 1
      require("src.audio").playAt("bell", lot.x, lot.top - 50, 0.9)
    end
  end
end

-- The town hall (the spare lot): a stone-coloured hall with a clock and a flag, closed for now
local function hall(l)
  local cx, P, a = l.x, l.top, l.accent
  R(shade(a, 0.4), cx + 30, P - 50, 4, 50)
  R(a, cx - 30, P - 46, 60, 46)
  for y = P - 44, P - 2, 4 do
    R(shade(a, 0.84), cx - 30, y, 60, 1)
  end
  R(CREAM, cx - 31, P - 48, 62, 3)
  R(CREAM_D, cx - 31, P - 46, 62, 1)
  -- a tower with a clock
  R(a, cx - 9, P - 66, 18, 20)
  R(CREAM, cx - 10, P - 68, 20, 3)
  -- the clock face: a round, bevelled dial in the hall's own pixels (a brass ring, cream face, twelve ticks)
  local ccx, ccy = cx, P - 56
  for dy = -7, 7 do
    for dx = -7, 7 do
      local d = math.sqrt(dx * dx + dy * dy)
      if d <= 7.2 then
        local col
        if d > 6.1 then
          col = (dx + dy < 0) and { 0.88, 0.72, 0.38 } or { 0.55, 0.40, 0.18 } -- ring, lit from the upper left
        elseif d > 5.2 then
          col = { 0.30, 0.22, 0.12 } -- the inner shadow line
        else
          col = (dx + dy < -2) and { 0.97, 0.95, 0.86 } or { 0.88, 0.85, 0.74 } -- the face, shaded lower right
        end
        R(col, ccx + dx, ccy + dy, 1, 1)
      end
    end
  end
  for k = 0, 11 do
    local ang = k / 12 * math.pi * 2
    local r1 = k % 3 == 0 and 4.4 or 4.9
    R({ 0.2, 0.17, 0.14 }, ccx + math.floor(math.sin(ang) * r1 + 0.5), ccy + math.floor(-math.cos(ang) * r1 + 0.5), 1, 1)
    if k % 3 == 0 then
      R({ 0.2, 0.17, 0.14 }, ccx + math.floor(math.sin(ang) * (r1 - 1) + 0.5), ccy + math.floor(-math.cos(ang) * (r1 - 1) + 0.5), 1, 1)
    end
  end
  drawClockHands(ccx, ccy) -- (the computer's time, redrawn when the minute changes)
  R({ 0.75, 0.2, 0.18 }, ccx, ccy, 1, 1) -- the pin
  R(WOOD_D, cx, P - 76, 1, 8)
  R({ 0.75, 0.2, 0.18 }, cx + 1, P - 76, 6, 4)
  -- tall double doors, shut, and two shuttered windows
  R(WOOD_D, cx - 7, P - 24, 14, 24)
  R(WOOD, cx - 6, P - 23, 6, 23)
  R(WOOD, cx + 1, P - 23, 6, 23)
  for _, wx in ipairs({ cx - 24, cx + 17 }) do
    R(CREAM, wx - 1, P - 38, 9, 13)
    R(WOOD_D, wx, P - 37, 7, 11)
  end
  sign(l.sign, cx, P - 43, a)
  -- a wide porch roof on posts
  R(WOOD_D, cx - 34, P - 28, 68, 2)
  R(WOOD_D, cx - 32, P - 26, 2, 26)
  R(WOOD_D, cx + 30, P - 26, 2, 26)
end

-- The welcome sign at the west end of the street, and a telegraph pole at each end
local function streetExtras(surface)
  local gl = surface(STREET_X0 + 6)
  R(WOOD_D, STREET_X0 - 2, gl - 22, 2, 22)
  R(WOOD_D, STREET_X0 + 22, gl - 22, 2, 22)
  love.graphics.setColor(1, 1, 1)
  local img = textImage("GUNNUG", { 0.50, 0.36, 0.22 }, CREAM)
  love.graphics.draw(img, STREET_X0 + 10 - math.floor(img:getWidth() / 2), gl - 28)
  -- telegraph poles with a wire between them, sagging over the rooftops
  local g0, g1 = surface(STREET_X0 - 8), surface(STREET_X1 + 8)
  local top0, top1 = g0 - 92, g1 - 92
  for _, p in ipairs({ { STREET_X0 - 8, g0, top0 }, { STREET_X1 + 8, g1, top1 } }) do
    R(WOOD_D, p[1] - 1, p[3], 3, p[2] - p[3])
    R(WOOD, p[1] - 5, p[3] + 2, 11, 2)
    R(CREAM_D, p[1] - 5, p[3] + 1, 1, 1)
    R(CREAM_D, p[1] + 5, p[3] + 1, 1, 1)
  end
  love.graphics.setColor(0.12, 0.1, 0.1, 0.85)
  local px, py = STREET_X0 - 3, top0 + 1
  for x = STREET_X0 - 3, STREET_X1 + 13, 6 do
    local t = (x - (STREET_X0 - 3)) / ((STREET_X1 + 13) - (STREET_X0 - 3))
    local y = top0 + (top1 - top0) * t + math.sin(t * math.pi) * 12 + 1
    love.graphics.line(px, py, x, y)
    px, py = x, y
  end
end

local function inView(view, x0, x1)
  return x1 > view.x - 20 and x0 < view.x + view.w + 20
end

-- Everything the town adds behind the hunter. surface(x): the street's ground.
function town.draw(view, surface)
  local stage = town.stage()
  for _, l in ipairs(town.LOTS) do
    if l.top and l.built and inView(view, l.x - 40, l.x + 40) then
      -- (nothing at all stands on a lot until its person has come)
      if l.id == "hall" then
        hall(l)
      elseif l.id ~= "board" then
        if stage == 2 then
          shack(l)
        elseif stage == 3 then
          facade(l)
        end
      end
    end
  end
  if stage >= 3 and inView(view, STREET_X0 - 20, STREET_X1 + 20) then
    streetExtras(surface)
  end
end

-- Lit windows and lanterns
function town.drawEmissive(view)
  local stage = town.stage()
  if stage < 2 then
    return
  end
  local t = love.timer.getTime()
  for _, l in ipairs(town.LOTS) do
    if l.top and inView(view, l.x - 40, l.x + 40) and l.id ~= "board" and meta.atCamp(l.id) then
      local P, cx = l.top, l.x
      local fl = 0.8 + 0.2 * math.sin(t * 9 + l.x)
      local lamp = l.id == "bartender" and { 0.45, 0.68, 1 } or { 1, 0.78, 0.38 } -- (blue at the saloon)
      local glass = l.id == "bartender" and { 0.35, 0.6, 1 } or { 1, 0.74, 0.36 }
      if stage == 3 then
        for _, wx in ipairs({ cx - 21, cx + 9 }) do
          R({ glass[1], glass[2], glass[3], 0.38 + 0.1 * fl }, wx + 1, P - 47, 4, 10)
          R({ glass[1], glass[2], glass[3], 0.38 + 0.1 * fl }, wx + 6, P - 47, 3, 10)
        end
        R({ lamp[1], lamp[2], lamp[3], fl }, cx - 30, P - 22, 1, 3)
        R({ lamp[1], lamp[2], lamp[3], fl }, cx + 29, P - 22, 1, 3)
      else
        for _, wx in ipairs({ cx - 16, cx + 8 }) do
          R({ glass[1], glass[2], glass[3], 0.5 + 0.15 * fl }, wx + 1, P - 36, 5, 3)
        end
        R({ lamp[1], lamp[2], lamp[3], fl }, cx - 28, P - 26, 1, 3)
        R({ lamp[1], lamp[2], lamp[3], fl }, cx + 27, P - 26, 1, 3)
      end
    end
  end
end

function town.addLights(lighting, view)
  local stage = town.stage()
  if stage < 2 then
    return
  end
  for _, l in ipairs(town.LOTS) do
    if l.top and inView(view, l.x - 100, l.x + 100) and l.id ~= "board" and meta.atCamp(l.id) then
      -- (the saloon's lights are blue: the warm ones were lost in the camp's glow)
      local blue = l.id == "bartender"
      local c = blue and { 0.35, 0.6, 1 } or { 1, 0.7, 0.36 }
      local k = blue and 0.3 or 0.2
      lighting.add(l.x - 30, l.top - 24, blue and 34 or 26, c[1], c[2], c[3], k)
      lighting.add(l.x + 30, l.top - 24, blue and 34 or 26, c[1], c[2], c[3], k)
      if stage == 3 then
        lighting.add(l.x, l.top - 42, blue and 44 or 34, c[1], blue and c[2] or 0.74, blue and c[3] or 0.4, k)
      end
    end
  end
end

return town
