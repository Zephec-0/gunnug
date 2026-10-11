-- Things lying in the world that the hunter picks up by walking over them
-- (design doc §9, §9a). For now only gold: little coins that spill out of
-- dead monsters, broken crates and dug-out gold ore, bounce around on the
-- terrain, and are drawn to the hunter when he comes close.
--
-- A coin that lands and isn't picked up disappears 7 seconds later (its gold
-- is lost), blinking for the last second and a half.
--
-- A pickup is { kind, value, x, y, vx, vy, ... }. Coins are simulated per
-- pixel like particles (cheap, so hundreds can lie around) rather than as
-- Box2D bodies.
local config = require("src.config")
local effects = require("src.effects")
local items = require("src.items")

local pickups = {}

local list = {}

local MAX_PICKUPS = 400
local PICKUP_RADIUS = 7 -- touching distance to the hunter's centre
local MAGNET_RANGE = 36
local MAGNET_DELAY = 0.45 -- freshly spilled coins can't be grabbed for this long
local GRAVITY = config.gravity * 0.8
local DESPAWN_TIME = 7 -- a coin that has hit the ground vanishes after this long
local FADE_TIME = 1.5 -- it blinks for the last stretch
local overflow = 0 -- value of coins removed to stay under the cap; added to the next coin

function pickups.clear()
  list = {}
  overflow = 0
end

function pickups.count()
  return #list
end

-- Drops an ammo type or attachment (an item from src.items) at (x, y). It
-- never despawns; the hunter picks it up when he has a free item slot.
function pickups.dropItem(x, y, item)
  list[#list + 1] = {
    kind = "item",
    item = item,
    value = 0,
    x = x,
    y = y,
    vx = (love.math.random() - 0.5) * 60,
    vy = -80 - love.math.random() * 40,
    age = 0,
    sparkle = love.math.random() * 6,
  }
end

-- Chance-based drop of a random item
function pickups.maybeDropItem(x, y, chance)
  if love.math.random() < chance then
    pickups.dropItem(x, y, items.random())
  end
end

-- Spills `amount` gold at (x, y) as a handful of coins, flung outward
function pickups.dropGold(x, y, amount)
  if amount <= 0 then
    return
  end
  local coins = math.min(amount, 8)
  local base, extra = math.floor(amount / coins), amount % coins
  for i = 1, coins do
    local a = -math.pi / 2 + (love.math.random() - 0.5) * 2.4
    local s = 40 + love.math.random() * 90
    if #list >= MAX_PICKUPS then
      overflow = overflow + table.remove(list, 1).value -- the oldest coin gives way, its gold carried on
    end
    list[#list + 1] = {
      kind = "gold",
      value = base + (i <= extra and 1 or 0) + overflow,
      x = x + (love.math.random() - 0.5) * 4,
      y = y,
      vx = math.cos(a) * s,
      vy = math.sin(a) * s,
      age = 0,
      sparkle = love.math.random() * 6,
    }
    overflow = 0
  end
end

-- Returns false if it can't be picked up (no room for an item)
local function collect(p, player)
  local inv = player.inventory
  if p.kind == "item" then
    if not inv:addItem(p.item) then
      return false
    end
    effects.popup(p.x, p.y - 6, p.item.name, p.item.color)
    for _ = 1, 4 do
      effects.particle(p.x, p.y, (love.math.random() - 0.5) * 70, -love.math.random() * 60, 0.35, p.item.color, 200, true)
    end
  elseif p.kind == "gold" then
    inv.gold = inv.gold + p.value
    effects.popup(p.x, p.y - 6, "+" .. p.value, { 1, 0.82, 0.25 })
    for _ = 1, 4 do
      effects.particle(p.x, p.y, (love.math.random() - 0.5) * 70, -love.math.random() * 60, 0.35, { 1, 0.9, 0.4 }, 200, true)
    end
  end
  return true
end

function pickups.update(dt, world, player)
  local px, py = player:center()
  local canCollect = not player.dead
  for i = #list, 1, -1 do
    local p = list[i]
    p.age = p.age + dt
    local dx, dy = px - p.x, py - p.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local taken = false
    if canCollect and p.age > MAGNET_DELAY then
      local room = p.kind ~= "item" or player.inventory:hasRoom()
      if dist < PICKUP_RADIUS and room then
        taken = collect(p, player)
      elseif dist < MAGNET_RANGE and room then
        -- Pulled in, faster the closer it is
        local pull = 900 * (1 - dist / MAGNET_RANGE) + 120
        p.vx = p.vx + dx / dist * pull * dt
        p.vy = p.vy + dy / dist * pull * dt
        p.pulled = true
      end
    end
    if p.kind == "gold" and p.landedAt and not p.pulled and p.age - p.landedAt > DESPAWN_TIME then
      taken = true -- timed out: just removed, not collected
    elseif p.pulled then
      p.landedAt = nil -- being pulled in: the timer starts again if it lands again
    end
    if taken then
      table.remove(list, i)
    elseif not p.pulled or dist >= MAGNET_RANGE then
      p.pulled = false
      p.vy = math.min(p.vy + GRAVITY * dt, 450)
      local nx, ny = p.x + p.vx * dt, p.y + p.vy * dt
      if world:isSolid(math.floor(nx), math.floor(p.y)) then
        p.vx = -p.vx * 0.4
        nx = p.x
      end
      if world:isSolid(math.floor(nx), math.floor(ny)) then
        p.landedAt = p.landedAt or p.age
        -- Bounce off the ground, losing most of the energy; settle when slow
        if math.abs(p.vy) < 40 then
          p.vy, ny = 0, p.y
        else
          p.vy = -p.vy * 0.45
          ny = p.y
        end
        p.vx = p.vx * 0.7
      end
      p.x, p.y = nx, ny
    else
      -- Magnetised: fly straight at the hunter (ignores terrain)
      p.vx, p.vy = p.vx * (1 - 4 * dt), p.vy * (1 - 4 * dt)
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    end
  end
end

local function onScreen(p, view)
  return p.x > view.x - 4 and p.x < view.x + view.w + 4 and p.y > view.y - 4 and p.y < view.y + view.h + 4
end

-- Drawn after the lighting so coins glint in the dark and can be spotted
function pickups.drawEmissive(view)
  local t = love.timer.getTime()
  for _, p in ipairs(list) do
    local left = (p.kind == "gold" and p.landedAt) and (DESPAWN_TIME - (p.age - p.landedAt)) or math.huge
    local blinkOff = left < FADE_TIME and math.floor(left * 10) % 2 == 0
    if p.kind == "item" and onScreen(p, view) then
      -- A little glowing crate in the item's colour
      local x, y = math.floor(p.x) - 2, math.floor(p.y) - 4
      local c = p.item.color
      love.graphics.setColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
      love.graphics.rectangle("fill", x - 1, y - 1, 6, 6)
      love.graphics.setColor(c[1], c[2], c[3])
      love.graphics.rectangle("fill", x, y, 4, 4)
      love.graphics.setColor(1, 1, 1, 0.7)
      love.graphics.rectangle("fill", x, y, 2, 1)
    elseif onScreen(p, view) and not blinkOff then
      local x, y = math.floor(p.x), math.floor(p.y)
      love.graphics.setColor(0.95, 0.74, 0.22)
      love.graphics.rectangle("fill", x, y - 1, 2, 2)
      love.graphics.setColor(1, 0.92, 0.55)
      love.graphics.rectangle("fill", x, y - 1, 1, 1)
      -- A glint that twinkles now and then
      if math.sin(t * 5 + p.sparkle) > 0.92 then
        love.graphics.setColor(1, 1, 0.9)
        love.graphics.rectangle("fill", x - 1, y, 4, 1)
        love.graphics.rectangle("fill", x + 0, y - 2, 1, 5)
      end
    end
  end
end

function pickups.addLights(lighting, view)
  for _, p in ipairs(list) do
    if onScreen(p, view) then
      if p.kind == "item" then
        local c = p.item.color
        lighting.add(p.x, p.y - 2, 22, c[1], c[2], c[3], 0.6)
      else
        lighting.add(p.x, p.y, 12, 1, 0.8, 0.3, 0.35)
      end
    end
  end
end

return pickups
