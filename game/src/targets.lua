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
  local w, h = 14, 24
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
  effects.popup(t.x + t.w / 2, t.y - 2, tostring(amount), { 1, 0.27, 0.24 })
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
  local cy = t.y + 7 -- bullseye centre
  -- Post with a darker edge and a foot
  love.graphics.setColor(0.36, 0.26, 0.18)
  love.graphics.rectangle("fill", cx - 1, cy + 5, 3, t.h - 12)
  love.graphics.setColor(0.25, 0.18, 0.12)
  love.graphics.rectangle("fill", cx + 1, cy + 5, 1, t.h - 12)
  love.graphics.rectangle("fill", cx - 4, t.y + t.h - 1, 9, 1)
  -- Bullseye: red, white, red rings with a dark rim
  local white = t.flash > 0
  local function ring(r, color)
    love.graphics.setColor(white and { 1, 1, 1 } or color)
    love.graphics.circle("fill", cx + 0.5, cy + 0.5, r)
  end
  ring(7, { 0.24, 0.05, 0.07 })
  ring(6.2, { 0.60, 0.10, 0.13 })
  ring(4.6, { 0.78, 0.74, 0.62 })
  ring(3.0, { 0.60, 0.10, 0.13 })
  ring(1.4, { 0.78, 0.74, 0.62 })
end

function targets.draw()
  for _, t in ipairs(list) do
    drawDummy(t)
  end
end

return targets
