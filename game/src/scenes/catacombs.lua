-- The Catacombs: a randomly generated descending cave area that ends at the
-- shop room (design doc §3, §7). Dark, lit by the hunter, glowing fungus and
-- the shop's candles. The shop is empty for now.
local cavegen = require("src.cavegen")
local config = require("src.config")
local hud = require("src.hud")
local props = require("src.props")
local targets = require("src.targets")

local catacombs = {
  title = "The Catacombs",
  subtitle = "Area 1",
  ambient = { 0.36, 0.32, 0.44 },
}

local info -- layout from cavegen: seed, spawn, shop rect, prop and fungus spots
local shopReached = false

function catacombs.build(opts)
  local seed = (opts and opts.seed) or math.floor(love.math.random() * 1000000)
  local world
  world, info = cavegen.generate(seed)
  catacombs.subtitle = "Area 1  ·  seed " .. seed
  return world, info.spawnX, info.spawnY
end

function catacombs.populate(world)
  targets.clear()
  props.clear()
  shopReached = false
  for _, s in ipairs(info.crates) do
    props.spawn("crate", s[1], s[2] - 7)
  end
  for _, s in ipairs(info.ironCrates) do
    props.spawn("ironCrate", s[1], s[2] - 8.5)
  end
end

function catacombs.info()
  return info
end

-- Entering the shop ends the area
function catacombs.update(dt, player)
  local s = info.shop
  local b = player.body
  if not shopReached and b.x >= s.x and b.x + b.w <= s.x + s.w and b.y >= s.y and b.y + b.h <= s.y + s.h then
    shopReached = true
    hud.showBanner("The Shop", "Area 1 complete. The next area is coming soon")
  end
end

function catacombs.shopReached()
  return shopReached
end

-- Darker the deeper you go
function catacombs.drawBackground(camX, camY)
  local t = math.min(1, camY / 1440)
  love.graphics.setColor(0.10 - t * 0.04, 0.08 - t * 0.03, 0.14 - t * 0.05)
  love.graphics.rectangle("fill", 0, 0, config.VIRTUAL_W, config.VIRTUAL_H)
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

function catacombs.addLights(lighting)
  for i, c in ipairs(candles()) do
    lighting.add(c[1], c[2] - c[3] - 2, i <= 2 and 120 or 64, 1, 0.68, 0.36, 1.0 + flicker(i) * 0.07)
  end
  for i, g in ipairs(info.glows) do
    lighting.add(g[1], g[2] - 3, 34, 0.35, 0.95, 0.85, 0.6 + math.sin(love.timer.getTime() * 1.5 + i) * 0.08)
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

function catacombs.drawDecor()
  for i, g in ipairs(info.glows) do
    drawFungus(g[1], g[2], i)
  end
  local s = info.shop
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

function catacombs.drawEmissive()
  for i, g in ipairs(info.glows) do
    for j = 0, 2 do
      local dx = (j - 1) * 2 + (i + j) % 2
      local h = 2 + (i + j * 3) % 3
      love.graphics.setColor(0.45, 1, 0.88)
      love.graphics.rectangle("fill", g[1] + dx - (j == 1 and 1 or 0), g[2] - h - 1, j == 1 and 3 or 2, 1)
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
