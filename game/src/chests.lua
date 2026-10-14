-- Weapon chests (design doc §9a): iron-banded chests scattered through the
-- catacombs. Standing next to one and pressing E opens it: it holds either gold
-- (80%) or a generated weapon (20%), never both, so the real prize is saved
-- for playing well down to the shop. Deeper chests hold more gold and
-- better-equipped weapons (more pre-fitted slots).
local input = require("src.input")
local audio = require("src.audio")
local effects = require("src.effects")
local guns = require("src.guns")
local pickups = require("src.pickups")

local chests = {}

local list = {}

local REACH = 20 -- how close the hunter must be to open one
local GOLD_CHANCE = 0.8 -- a chest holds gold with this chance, otherwise a weapon
local W, H = 14, 9

function chests.clear()
  list = {}
end

-- x: centre, groundY: the first solid pixel under it. depth: 0 at the top of
-- the cave, 1 at the bottom.
function chests.spawn(x, groundY, depth)
  list[#list + 1] = { x = x, y = groundY, depth = depth or 0, opened = false, open = 0 }
end

local function distance(c, player)
  local px, py = player:center()
  return math.sqrt((c.x - px) ^ 2 + (c.y - H / 2 - py) ^ 2)
end

-- The nearest unopened chest within reach
function chests.nearest(player)
  local best, bestDist = nil, REACH
  for _, c in ipairs(list) do
    if not c.opened then
      local d = distance(c, player)
      if d < bestDist then
        best, bestDist = c, d
      end
    end
  end
  return best
end

-- E: opens the nearest chest. Returns true if one was opened.
function chests.interact(player)
  local c = chests.nearest(player)
  if not c then
    return false
  end
  c.opened = true
  audio.play("chest")
  if love.math.random() < GOLD_CHANCE then
    pickups.dropGold(c.x, c.y - H, math.floor(love.math.random(15, 40) * (1 + c.depth)))
  else
    local fit = 0.15 + 0.45 * c.depth
    pickups.dropWeapon(c.x, c.y - H - 2, guns.generate(nil, nil, fit), (love.math.random() - 0.5) * 50, -150)
  end
  for _ = 1, 12 do
    effects.particle(c.x + (love.math.random() - 0.5) * 8, c.y - H, (love.math.random() - 0.5) * 70, -40 - love.math.random() * 70, 0.5, { 1, 0.85, 0.4 }, 300, true)
  end
  return true
end

function chests.update(dt)
  for _, c in ipairs(list) do
    if c.opened then
      c.open = math.min(1, c.open + dt * 4)
    end
  end
end

local function onScreen(c, view)
  return c.x > view.x - 16 and c.x < view.x + view.w + 16 and c.y > view.y - 16 and c.y < view.y + view.h + 16
end

function chests.draw(view)
  for _, c in ipairs(list) do
    if onScreen(c, view) then
      local x, y = math.floor(c.x - W / 2), math.floor(c.y)
      -- Body: dark wood with iron bands
      love.graphics.setColor(0.36, 0.25, 0.17)
      love.graphics.rectangle("fill", x, y - H + 3, W, H - 3)
      love.graphics.setColor(0.25, 0.17, 0.12)
      love.graphics.rectangle("fill", x, y - 2, W, 2)
      love.graphics.setColor(0.30, 0.31, 0.37)
      love.graphics.rectangle("fill", x + 2, y - H + 3, 2, H - 3)
      love.graphics.rectangle("fill", x + W - 4, y - H + 3, 2, H - 3)
      -- Lid: closed it sits on top; open it is tipped back
      local lift = math.floor(c.open * 4)
      love.graphics.setColor(0.42, 0.30, 0.20)
      love.graphics.rectangle("fill", x, y - H - 1 - lift, W, 4)
      love.graphics.setColor(0.30, 0.31, 0.37)
      love.graphics.rectangle("fill", x + 2, y - H - 1 - lift, 2, 4)
      love.graphics.rectangle("fill", x + W - 4, y - H - 1 - lift, 2, 4)
    end
  end
end

-- After the lighting: the lock glints on closed chests, gold glows from open ones
function chests.drawEmissive(view)
  local t = love.timer.getTime()
  for _, c in ipairs(list) do
    if onScreen(c, view) then
      local x, y = math.floor(c.x), math.floor(c.y)
      if c.opened then
        love.graphics.setColor(1, 0.85, 0.4, 0.8 * (1 - c.open * 0.5))
        love.graphics.rectangle("fill", x - 4, y - H, 8, 2)
      else
        love.graphics.setColor(0.95, 0.74, 0.22)
        love.graphics.rectangle("fill", x - 1, y - H + 1, 3, 3)
        if math.sin(t * 3 + c.x) > 0.85 then
          love.graphics.setColor(1, 1, 0.9)
          love.graphics.rectangle("fill", x - 3, y - H + 2, 7, 1)
          love.graphics.rectangle("fill", x, y - H - 1, 1, 6)
        end
      end
    end
  end
end

function chests.addLights(lighting, view)
  for _, c in ipairs(list) do
    if onScreen(c, view) then
      lighting.add(c.x, c.y - 6, c.opened and 18 or 30, 1, 0.75, 0.35, c.opened and 0.4 or 0.6)
    end
  end
end

-- The "[E] Open chest" prompt (full resolution)
function chests.drawScreen(toScreen, font, player)
  if player.dead then
    return
  end
  local c = chests.nearest(player)
  if not c then
    return
  end
  local sx, sy = toScreen(c.x, c.y - H - 8)
  local text = "[" .. input.label("interact") .. "] Open chest"
  love.graphics.setFont(font)
  local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy - font:getHeight())
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(0.97, 0.98, 1)
  love.graphics.print(text, x, y)
end

return chests
