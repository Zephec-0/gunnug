-- The Old Mine: a randomly generated descending cave area that ends at the
-- shop room (design doc §3, §7). The shop is empty for now.
local cavegen = require("src.cavegen")
local hud = require("src.hud")
local props = require("src.props")
local targets = require("src.targets")

local mine = {
  title = "The Old Mine",
  subtitle = "Area 1",
}

local info -- layout from cavegen: seed, spawn, shop rect, prop spots
local shopReached = false

function mine.build(opts)
  local seed = (opts and opts.seed) or math.floor(love.math.random() * 1000000)
  local world
  world, info = cavegen.generate(seed)
  mine.subtitle = "Area 1  ·  seed " .. seed
  return world, info.spawnX, info.spawnY
end

function mine.populate(world)
  targets.clear()
  props.clear()
  shopReached = false
  for _, s in ipairs(info.crates) do
    props.spawn("crate", s[1], s[2] - 4.5)
  end
  for _, s in ipairs(info.ironCrates) do
    props.spawn("ironCrate", s[1], s[2] - 5.5)
  end
end

function mine.info()
  return info
end

-- Entering the shop ends the area
function mine.update(dt, player)
  local s = info.shop
  local b = player.body
  if not shopReached and b.x >= s.x and b.x + b.w <= s.x + s.w and b.y >= s.y and b.y + b.h <= s.y + s.h then
    shopReached = true
    hud.showBanner("The Shop", "Area 1 complete. The next area is coming soon")
  end
end

function mine.shopReached()
  return shopReached
end

-- Darker the deeper you go
function mine.drawBackground(camX, camY)
  local t = math.min(1, camY / 900)
  love.graphics.setColor(0.10 - t * 0.05, 0.07 - t * 0.04, 0.15 - t * 0.07)
  love.graphics.rectangle("fill", 0, 0, 480, 270)
end

local function drawLantern(x, y, flicker)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 0.6, 0.2, 0.16 + flicker * 0.04)
  love.graphics.circle("fill", x, y + 3, 22)
  love.graphics.setColor(1, 0.75, 0.35, 0.22)
  love.graphics.circle("fill", x, y + 3, 10)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(0.25, 0.2, 0.18)
  love.graphics.rectangle("fill", x, y - 3, 1, 3)
  love.graphics.rectangle("fill", x - 2, y, 5, 1)
  love.graphics.setColor(1, 0.85, 0.4)
  love.graphics.rectangle("fill", x - 1, y + 1, 3, 3)
end

function mine.drawDecor()
  local s = info.shop
  local flicker = math.sin(love.timer.getTime() * 9) * 0.5 + math.sin(love.timer.getTime() * 23) * 0.5
  drawLantern(s.x + 30, s.y + 2, flicker)
  drawLantern(s.x + s.w - 30, s.y + 2, -flicker)
  -- Empty shelves on the back wall
  love.graphics.setColor(0.42, 0.26, 0.13)
  for i = 0, 2 do
    love.graphics.rectangle("fill", s.x + s.w - 70, s.y + 20 + i * 10, 44, 2)
  end
end

function mine.drawScreen(toScreen, font)
  local s = info.shop
  local sx, sy = toScreen(s.x + s.w / 2, s.y + 12)
  local text = "SHOP"
  love.graphics.setFont(font)
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2) + 2, math.floor(sy) + 2)
  love.graphics.setColor(1, 0.85, 0.4)
  love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2), math.floor(sy))
end

return mine
