-- The generated areas under the Barrens (design doc §3, §7): the Catacombs,
-- then the Sunken Hollows below them, each ending at a shop room whose hatch
-- drops into the next. Not scenes of their own: the overworld scene owns the
-- whole world and hands this module the region below the surface.
--
-- Generation takes a few seconds per area, so each area runs as a coroutine a
-- few milliseconds per frame, in order, in the background while the hunter is
-- still above it (no loading screen). catacombs.ensure(y) completes any area
-- the hunter is getting close to, if it isn't done yet.
local cavegen = require("src.cavegen")
local chests = require("src.chests")
local enemies = require("src.enemies")
local hud = require("src.hud")
local materials = require("src.materials")
local props = require("src.props")
local shop = require("src.shop")

local catacombs = {}

-- How each area looks: palette, light, the glowing mushrooms that light the
-- way, and the backdrop behind the rock
local THEMES = {
  {
    name = "The Catacombs",
    subtitle = "Area 1",
    ambient = { 0.36, 0.32, 0.44 },
    palette = nil, -- the default rock and dirt
    glow = { 0.35, 0.95, 0.85 }, -- teal fungus
    glowCount = 150,
    glowRadius = 34,
    stalk = { 0.55, 0.62, 0.55 },
    backTop = { 0.10, 0.08, 0.14 },
    backDeep = { 0.06, 0.05, 0.09 },
  },
  {
    name = "The Sunken Hollows",
    subtitle = "Area 2",
    ambient = { 0.17, 0.21, 0.31 }, -- darker and colder
    palette = { rock = materials.SLATE, dirt = materials.BLUECLAY },
    glow = { 0.35, 1.0, 0.45 }, -- green mushrooms, lots of them
    glowCount = 480,
    glowRadius = 40,
    stalk = { 0.45, 0.62, 0.50 },
    backTop = { 0.045, 0.06, 0.105 },
    backDeep = { 0.03, 0.04, 0.075 },
  },
}

local levels = {} -- levels[i] = { theme, area, job, info, propsSpawned, shopReached }
local world
local firstArea, baseSeed
local levelHeight = 0
local deadline = 0 -- os.clock() time the current slice of work must stop at
local announced = 0 -- the deepest area whose banner has been shown

function catacombs.count()
  return #levels
end

function catacombs.theme(i)
  return THEMES[i] or THEMES[#THEMES]
end

-- Starts the areas under the surface. first: the first area's rectangle and
-- entrance (see cavegen.generate); count: how many areas stack below it.
function catacombs.start(w, first, seed, count)
  world, firstArea, baseSeed = w, first, seed
  levelHeight = first.y1 - first.y0 + 1
  levels = {}
  announced = 0
  for i = 1, count or 1 do
    levels[i] = { theme = THEMES[i] or THEMES[#THEMES], index = i, y0 = first.y0 + (i - 1) * levelHeight }
  end
end

-- The area spec for level i, built from the area above once that is generated
local function areaFor(i)
  local lv = levels[i]
  local base = {}
  if i == 1 then
    for k, v in pairs(firstArea) do
      base[k] = v
    end
  else
    local hatch = levels[i - 1].info.shop.hatch
    base = {
      x0 = firstArea.x0,
      x1 = firstArea.x1,
      y0 = lv.y0,
      y1 = lv.y0 + levelHeight - 1,
      entranceX = hatch.cx,
      entranceY = lv.y0 + 96,
      shaftX0 = hatch.x0,
      shaftX1 = hatch.x1,
      shaftTop = hatch.y1 + 1,
    }
  end
  base.level = i
  base.palette = lv.theme.palette
  base.glowCount = lv.theme.glowCount
  base.hasNext = i < #levels
  return base
end

local function tick()
  if os.clock() > deadline then
    coroutine.yield()
  end
end

-- Runs the coroutine of level i for up to `budget` seconds (creating it first)
local function resume(i, budget)
  local lv = levels[i]
  if not lv.job then
    local area = areaFor(i)
    lv.area = area
    lv.job = coroutine.create(function()
      return cavegen.generate(world, area, baseSeed + (i - 1) * 7919, tick)
    end)
  end
  deadline = os.clock() + budget
  local ok, result = coroutine.resume(lv.job)
  if not ok then
    error(debug.traceback(lv.job, result))
  end
  if coroutine.status(lv.job) == "dead" then
    lv.job, lv.info = nil, result
  end
end

local function nextUnfinished()
  for i, lv in ipairs(levels) do
    if not lv.info then
      return i
    end
  end
  return nil
end

-- Spends up to budget seconds on generation; call once per frame
function catacombs.step(budget)
  local i = nextUnfinished()
  if i then
    resume(i, budget)
  end
end

-- Completes generation of every area up to and including level `upTo` (default: all)
function catacombs.finish(upTo)
  for i = 1, math.min(upTo or #levels, #levels) do
    while not levels[i].info do
      resume(i, math.huge)
    end
  end
end

-- Makes sure the area the hunter is heading into exists: any area whose top
-- is within 900 px below him is completed now if it isn't already
function catacombs.ensure(py)
  for i, lv in ipairs(levels) do
    -- (the first area is completed by the scene when the hunter goes underground)
    if i > 1 and not lv.info and py > lv.y0 - 900 then
      catacombs.finish(i)
    end
  end
end

function catacombs.ready()
  return levels[1] ~= nil and levels[1].info ~= nil
end

-- The first area's layout (where the F10 shortcut spawns)
function catacombs.info()
  return levels[1] and levels[1].info
end

-- The area (1-based) a world y lies in, or nil above them all
function catacombs.levelAt(y)
  if not firstArea or y < firstArea.y0 then
    return nil
  end
  return math.min(#levels, math.floor((y - firstArea.y0) / levelHeight) + 1)
end

-- Backdrop colour behind the rock at depth y (inside the areas)
function catacombs.backdrop(y)
  local i = catacombs.levelAt(y) or 1
  local t = THEMES[i] or THEMES[#THEMES]
  local d = math.min(1, (y - levels[i].y0) / (levelHeight * 0.8))
  return t.backTop[1] + (t.backDeep[1] - t.backTop[1]) * d,
    t.backTop[2] + (t.backDeep[2] - t.backTop[2]) * d,
    t.backTop[3] + (t.backDeep[3] - t.backTop[3]) * d
end

-- Scatters crates, chests, monsters and the shop stock through every area
-- that exists. Needs the physics world, so the scene calls it after setting
-- that up (and the area update calls it every frame after).
function catacombs.spawnProps()
  for i, lv in ipairs(levels) do
    local info = lv.info
    if info and not lv.propsSpawned then
      lv.propsSpawned = true
      -- Resting objects start asleep: their terrain outlines are only traced
      -- once something wakes them, instead of all in the same frame
      for _, s in ipairs(info.crates) do
        props.spawn("crate", s[1], s[2] - 7).body:setAwake(false)
      end
      for _, s in ipairs(info.ironCrates) do
        props.spawn("ironCrate", s[1], s[2] - 8.5).body:setAwake(false)
      end
      shop.populate(info.shop, world, i)
      local a = info.area
      for _, c in ipairs(info.chests) do
        local depth = math.min(1, (c[2] - a.y0) / (a.y1 - a.y0) + (i - 1) * 0.35)
        chests.spawn(c[1], c[2], depth)
      end
      for _, m in ipairs(info.enemies) do
        enemies.spawn(m.kind, m.x, m.y, m.toughness)
      end
    end
  end
end

-- Banners as the hunter reaches each area, and the shop-reached message
function catacombs.update(player)
  catacombs.spawnProps()
  local px, py = player:center()
  local at = catacombs.levelAt(py)
  if at and at > announced and py > levels[at].y0 then
    announced = at
    hud.showBanner(levels[at].theme.name, levels[at].theme.subtitle .. "  -  seed " .. baseSeed)
  end
  local b = player.body
  for i, lv in ipairs(levels) do
    local info = lv.info
    if info and not lv.shopReached then
      local s = info.shop
      if b.x >= s.x and b.x + b.w <= s.x + s.w and b.y >= s.y and b.y + b.h <= s.y + s.h then
        lv.shopReached = true
        if lv.area.hasNext then
          hud.showBanner("The Shop", "Heal, buy, then shoot the chain to open the hatch. Leaving closes the shop")
        else
          hud.showBanner("The Shop", "Area " .. i .. " complete. More depths are coming soon")
        end
      end
    end
  end
end

function catacombs.shopReached()
  return levels[1] ~= nil and levels[1].shopReached == true
end

local function flicker(seed)
  local t = love.timer.getTime()
  return math.sin(t * 9 + seed) * 0.5 + math.sin(t * 23 + seed * 2) * 0.5
end

-- Two iron sconces with candles on each shop's back wall
local function candles(info)
  local s = info.shop
  return {
    { s.x + 48, s.y + 30, 4 },
    { s.x + math.floor(s.w * 0.33), s.y + 30, 4 },
    { s.x + math.floor(s.w * 0.62), s.y + 30, 4 },
    { s.x + s.w - 48, s.y + 30, 4 },
  }
end

-- view: { x, y, w, h } in world pixels; things outside it (plus margin) are skipped
local function visible(view, x, y, margin)
  return x > view.x - margin and x < view.x + view.w + margin and y > view.y - margin and y < view.y + view.h + margin
end

function catacombs.addLights(lighting, view)
  local t = love.timer.getTime()
  for _, lv in ipairs(levels) do
    local info = lv.info
    if info then
      for i, c in ipairs(candles(info)) do
        if visible(view, c[1], c[2], 120) then
          lighting.add(c[1], c[2] - c[3] - 2, 120, 1, 0.68, 0.36, 1.0 + flicker(i) * 0.07)
        end
      end
      local g, r = lv.theme.glow, lv.theme.glowRadius
      local strong = lv.index > 1 and 0.75 or 0.6
      for i, spot in ipairs(info.glows) do
        if visible(view, spot[1], spot[2], r) then
          lighting.add(spot[1], spot[2] - 3, r, g[1], g[2], g[3], strong + math.sin(t * 1.5 + i) * 0.08)
        end
      end
    end
  end
end

local function drawFungus(x, y, seed, stalk)
  -- A cluster of tiny caps on stalks
  for i = 0, 2 do
    local dx = (i - 1) * 2 + (seed + i) % 2
    local h = 2 + (seed + i * 3) % 3
    love.graphics.setColor(stalk)
    love.graphics.rectangle("fill", x + dx, y - h, 1, h)
  end
end

function catacombs.drawDecor(view)
  for _, lv in ipairs(levels) do
    local info = lv.info
    if info then
      for i, g in ipairs(info.glows) do
        if visible(view, g[1], g[2], 8) then
          drawFungus(g[1], g[2], i, lv.theme.stalk)
        end
      end
      local s = info.shop
      if visible(view, s.x + s.w / 2, s.y + s.h / 2, 200) then
        -- Empty shelves on the back wall, each with a darker underside
        for i = 0, 2 do
          local y = s.y + 32 + i * 16
          love.graphics.setColor(0.36, 0.25, 0.17)
          love.graphics.rectangle("fill", s.x + s.w - 112, y, 70, 2)
          love.graphics.setColor(0.20, 0.14, 0.10)
          love.graphics.rectangle("fill", s.x + s.w - 112, y + 2, 70, 1)
        end
        -- Sconce brackets and candle sticks
        for _, c in ipairs(candles(info)) do
          love.graphics.setColor(0.14, 0.12, 0.14)
          love.graphics.rectangle("fill", c[1] - 2, c[2] + 1, 5, 1)
          love.graphics.rectangle("fill", c[1], c[2] + 2, 1, 4)
          love.graphics.setColor(0.82, 0.78, 0.66)
          love.graphics.rectangle("fill", c[1], c[2] - c[3], 1, c[3] + 1)
        end
      end
    end
  end
end

function catacombs.drawEmissive(view)
  for _, lv in ipairs(levels) do
    local info = lv.info
    if info then
      local g = lv.theme.glow
      for i, spot in ipairs(info.glows) do
        if visible(view, spot[1], spot[2], 8) then
          for j = 0, 2 do
            local dx = (j - 1) * 2 + (i + j) % 2
            local h = 2 + (i + j * 3) % 3
            love.graphics.setColor(math.min(1, g[1] + 0.1), math.min(1, g[2] + 0.05), math.min(1, g[3] + 0.05))
            love.graphics.rectangle("fill", spot[1] + dx - (j == 1 and 1 or 0), spot[2] - h - 1, j == 1 and 3 or 2, 1)
          end
        end
      end
      for i, c in ipairs(candles(info)) do
        local top = c[2] - c[3]
        love.graphics.setColor(1, 0.72, 0.28)
        love.graphics.rectangle("fill", c[1], top - 2 - (flicker(i) > 0.3 and 1 or 0), 1, 2)
        love.graphics.setColor(1, 0.95, 0.7)
        love.graphics.rectangle("fill", c[1], top - 1, 1, 1)
      end
    end
  end
end

function catacombs.drawScreen(toScreen, font)
  for _, lv in ipairs(levels) do
    if lv.info then
      local s = lv.info.shop
      local sx, sy = toScreen(s.x + s.w / 2, s.y + 19)
      local sw, sh = love.graphics.getDimensions()
      if sx > -100 and sx < sw + 100 and sy > -50 and sy < sh + 50 then
        local text = "SHOP"
        love.graphics.setFont(font)
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2) + 2, math.floor(sy) + 2)
        love.graphics.setColor(1, 0.85, 0.4)
        love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2), math.floor(sy))
      end
    end
  end
end

return catacombs
