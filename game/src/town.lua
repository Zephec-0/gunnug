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
  { id = "gunsmith", x = 1100, accent = { 0.58, 0.30, 0.22 }, sign = "GUNS" },
  { id = "bartender", x = 1166, accent = { 0.55, 0.20, 0.26 }, sign = "SALOON" },
  { id = "hall", x = 1232, accent = { 0.52, 0.49, 0.43 }, sign = "TOWN HALL" },
}
local PEOPLE = { "gunsmith", "prospector", "apothecary", "cartographer", "bartender", "taxidermist" }

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
    return true
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
  R({ 0.92, 0.9, 0.82 }, cx - 4, P - 62, 8, 8)
  R({ 0.2, 0.17, 0.14 }, cx - 4, P - 62, 8, 1)
  R({ 0.2, 0.17, 0.14 }, cx - 4, P - 55, 8, 1)
  R({ 0.2, 0.17, 0.14 }, cx - 4, P - 62, 1, 8)
  R({ 0.2, 0.17, 0.14 }, cx + 3, P - 62, 1, 8)
  R({ 0.2, 0.17, 0.14 }, cx, P - 61, 1, 4)
  R({ 0.2, 0.17, 0.14 }, cx, P - 58, 3, 1)
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
      if stage == 3 then
        for _, wx in ipairs({ cx - 21, cx + 9 }) do
          R({ 1, 0.74, 0.36, 0.38 + 0.1 * fl }, wx + 1, P - 47, 4, 10)
          R({ 1, 0.74, 0.36, 0.38 + 0.1 * fl }, wx + 6, P - 47, 3, 10)
        end
        R({ 1, 0.78, 0.38, fl }, cx - 30, P - 22, 1, 3)
        R({ 1, 0.78, 0.38, fl }, cx + 29, P - 22, 1, 3)
      else
        for _, wx in ipairs({ cx - 16, cx + 8 }) do
          R({ 1, 0.74, 0.36, 0.5 + 0.15 * fl }, wx + 1, P - 36, 5, 3)
        end
        R({ 1, 0.78, 0.38, fl }, cx - 28, P - 26, 1, 3)
        R({ 1, 0.78, 0.38, fl }, cx + 27, P - 26, 1, 3)
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
      lighting.add(l.x - 30, l.top - 24, 40, 1, 0.7, 0.36, 0.4)
      lighting.add(l.x + 30, l.top - 24, 40, 1, 0.7, 0.36, 0.4)
      if stage == 3 then
        lighting.add(l.x, l.top - 42, 60, 1, 0.74, 0.4, 0.4)
      end
    end
  end
end

return town
