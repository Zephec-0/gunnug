-- The Catacombs: the randomly generated cave under the Barrens, ending at the
-- shop room (design doc §3, §7). Not a scene of its own: the overworld scene
-- owns the whole world and hands this module the region below the surface.
--
-- Generation takes a few seconds, so it runs as a coroutine a few
-- milliseconds per frame while the hunter is still on the surface (no
-- loading screen); catacombs.finish() completes it at once if needed.
local cavegen = require("src.cavegen")
local enemies = require("src.enemies")
local hud = require("src.hud")
local props = require("src.props")

local catacombs = {}

local info -- layout from cavegen once generated: seed, spawn, shop rect, prop and fungus spots
local job -- generation coroutine while it is running
local deadline = 0 -- os.clock() time the current slice of work must stop at
local shopReached = false
local propsSpawned = false

-- Starts generating the cave into world's area (see cavegen.generate)
function catacombs.start(world, area, seed)
  info, shopReached, propsSpawned = nil, false, false
  local function tick()
    if os.clock() > deadline then
      coroutine.yield()
    end
  end
  job = coroutine.create(function()
    return cavegen.generate(world, area, seed, tick)
  end)
end

local function resume(budget)
  deadline = os.clock() + budget
  local ok, result = coroutine.resume(job)
  if not ok then
    error(debug.traceback(job, result))
  end
  if coroutine.status(job) == "dead" then
    job, info = nil, result
  end
end

-- Scatters crates and monsters through the cave once it exists. Needs the
-- physics world, so the scene calls it after setting that up (and every
-- frame after).
function catacombs.spawnProps()
  if info and not propsSpawned then
    propsSpawned = true
    -- They start asleep, resting on the floor: their terrain outlines are
    -- only traced once something wakes them (a shot, kick, push or dig),
    -- instead of all in the same frame
    for _, s in ipairs(info.crates) do
      props.spawn("crate", s[1], s[2] - 7).body:setAwake(false)
    end
    for _, s in ipairs(info.ironCrates) do
      props.spawn("ironCrate", s[1], s[2] - 8.5).body:setAwake(false)
    end
    for _, m in ipairs(info.enemies) do
      enemies.spawn(m.kind, m.x, m.y, m.toughness)
    end
  end
end

-- Spends up to budget seconds on generation; call once per frame
function catacombs.step(budget)
  if job then
    resume(budget)
  end
end

-- Completes generation immediately
function catacombs.finish()
  while job do
    resume(math.huge)
  end
end

function catacombs.ready()
  return info ~= nil
end

function catacombs.info()
  return info
end

function catacombs.shopReached()
  return shopReached
end

-- Entering the shop ends the area
function catacombs.update(player)
  if not info then
    return
  end
  catacombs.spawnProps()
  local s = info.shop
  local b = player.body
  if not shopReached and b.x >= s.x and b.x + b.w <= s.x + s.w and b.y >= s.y and b.y + b.h <= s.y + s.h then
    shopReached = true
    hud.showBanner("The Shop", "Area 1 complete. The next area is coming soon")
  end
end

local function flicker(seed)
  local t = love.timer.getTime()
  return math.sin(t * 9 + seed) * 0.5 + math.sin(t * 23 + seed * 2) * 0.5
end

-- Candles: two iron sconces on the shop's back wall and three on the counter
local function candles()
  local s = info.shop
  return {
    { s.x + 48, s.y + 30, 4 },
    { s.x + s.w - 48, s.y + 30, 4 },
    { s.x + 38, s.y + s.h - 16, 3 },
    { s.x + 52, s.y + s.h - 16, 2 },
    { s.x + 66, s.y + s.h - 16, 3 },
  }
end

-- view: { x, y, w, h } in world pixels; things outside it (plus margin) are skipped
local function visible(view, x, y, margin)
  return x > view.x - margin and x < view.x + view.w + margin and y > view.y - margin and y < view.y + view.h + margin
end

function catacombs.addLights(lighting, view)
  if not info then
    return
  end
  for i, c in ipairs(candles()) do
    if visible(view, c[1], c[2], 120) then
      lighting.add(c[1], c[2] - c[3] - 2, i <= 2 and 120 or 64, 1, 0.68, 0.36, 1.0 + flicker(i) * 0.07)
    end
  end
  local t = love.timer.getTime()
  for i, g in ipairs(info.glows) do
    if visible(view, g[1], g[2], 34) then
      lighting.add(g[1], g[2] - 3, 34, 0.35, 0.95, 0.85, 0.6 + math.sin(t * 1.5 + i) * 0.08)
    end
  end
end

local function drawFungus(x, y, seed)
  -- A cluster of tiny caps on stalks
  for i = 0, 2 do
    local dx = (i - 1) * 2 + (seed + i) % 2
    local h = 2 + (seed + i * 3) % 3
    love.graphics.setColor(0.55, 0.62, 0.55)
    love.graphics.rectangle("fill", x + dx, y - h, 1, h)
  end
end

function catacombs.drawDecor(view)
  if not info then
    return
  end
  for i, g in ipairs(info.glows) do
    if visible(view, g[1], g[2], 8) then
      drawFungus(g[1], g[2], i)
    end
  end
  local s = info.shop
  if not visible(view, s.x + s.w / 2, s.y + s.h / 2, 200) then
    return
  end
  -- Empty shelves on the back wall, each with a darker underside
  for i = 0, 2 do
    local y = s.y + 32 + i * 16
    love.graphics.setColor(0.36, 0.25, 0.17)
    love.graphics.rectangle("fill", s.x + s.w - 112, y, 70, 2)
    love.graphics.setColor(0.20, 0.14, 0.10)
    love.graphics.rectangle("fill", s.x + s.w - 112, y + 2, 70, 1)
  end
  -- Candle sticks and sconce brackets
  for i, c in ipairs(candles()) do
    love.graphics.setColor(0.14, 0.12, 0.14)
    if i <= 2 then
      love.graphics.rectangle("fill", c[1] - 2, c[2] + 1, 5, 1)
      love.graphics.rectangle("fill", c[1], c[2] + 2, 1, 4)
    end
    love.graphics.setColor(0.82, 0.78, 0.66)
    love.graphics.rectangle("fill", c[1], c[2] - c[3], 1, c[3] + 1)
  end
end

function catacombs.drawEmissive(view)
  if not info then
    return
  end
  for i, g in ipairs(info.glows) do
    if visible(view, g[1], g[2], 8) then
      for j = 0, 2 do
        local dx = (j - 1) * 2 + (i + j) % 2
        local h = 2 + (i + j * 3) % 3
        love.graphics.setColor(0.45, 1, 0.88)
        love.graphics.rectangle("fill", g[1] + dx - (j == 1 and 1 or 0), g[2] - h - 1, j == 1 and 3 or 2, 1)
      end
    end
  end
  for i, c in ipairs(candles()) do
    local top = c[2] - c[3]
    love.graphics.setColor(1, 0.72, 0.28)
    love.graphics.rectangle("fill", c[1], top - 2 - (flicker(i) > 0.3 and 1 or 0), 1, 2)
    love.graphics.setColor(1, 0.95, 0.7)
    love.graphics.rectangle("fill", c[1], top - 1, 1, 1)
  end
end

function catacombs.drawScreen(toScreen, font)
  if not info then
    return
  end
  local s = info.shop
  local sx, sy = toScreen(s.x + s.w / 2, s.y + 19)
  local text = "SHOP"
  love.graphics.setFont(font)
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2) + 2, math.floor(sy) + 2)
  love.graphics.setColor(1, 0.85, 0.4)
  love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2), math.floor(sy))
end

return catacombs
