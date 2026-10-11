-- Test targets: fixed bullseye dummies. They are static in the physics world
-- so props bounce off them.
local effects = require("src.effects")
local physics = require("src.physics")

local targets = {}

local list = {}

function targets.clear()
  list = {}
end

-- x is the horizontal centre, groundY the first solid pixel beneath it
function targets.addDummy(x, groundY)
  local w, h = 9, 15
  local t = { x = x - math.floor(w / 2), y = groundY - h, w = w, h = h, flash = 0, total = 0 }
  local body = love.physics.newBody(physics.world, t.x + w / 2, t.y + h / 2, "static")
  love.physics.newFixture(body, love.physics.newRectangleShape(w, h))
  list[#list + 1] = t
end

local function overlapsRect(t, x, y, w, h)
  return t.x < x + w and x < t.x + t.w and t.y < y + h and y < t.y + t.h
end

function targets.hitTest(px, py)
  for _, t in ipairs(list) do
    if px >= t.x and px < t.x + t.w and py >= t.y and py < t.y + t.h then
      return t
    end
  end
  return nil
end

function targets.damage(t, amount)
  t.flash = 0.08
  t.total = t.total + amount
  effects.popup(t.x + t.w / 2, t.y - 2, tostring(amount), { 1, 0.9, 0.3 })
end

function targets.kick(x, y, w, h, damage)
  for _, t in ipairs(list) do
    if overlapsRect(t, x, y, w, h) then
      targets.damage(t, damage)
    end
  end
end

function targets.update(dt)
  for _, t in ipairs(list) do
    t.flash = math.max(0, t.flash - dt)
  end
end

local function drawDummy(t)
  local cx = t.x + math.floor(t.w / 2)
  -- Post
  love.graphics.setColor(0.55, 0.33, 0.16)
  love.graphics.rectangle("fill", cx - 1, t.y + 7, 2, t.h - 7)
  love.graphics.rectangle("fill", cx - 3, t.y + t.h - 1, 6, 1)
  -- Bullseye
  local white = t.flash > 0
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.92, 0.18, 0.22 })
  love.graphics.circle("fill", cx, t.y + 4, 4.5)
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.98, 0.95, 0.85 })
  love.graphics.circle("fill", cx, t.y + 4, 3)
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.92, 0.18, 0.22 })
  love.graphics.rectangle("fill", cx - 1, t.y + 3, 2, 2)
end

function targets.draw()
  for _, t in ipairs(list) do
    drawDummy(t)
  end
end

return targets
