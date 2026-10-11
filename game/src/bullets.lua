-- Fast projectiles, marched one pixel at a time so they never tunnel through
-- thin terrain, targets or props.
local destruction = require("src.destruction")
local effects = require("src.effects")
local materials = require("src.materials")
local props = require("src.props")
local targets = require("src.targets")

local bullets = {}

local list = {}
local MAX_LIFE = 1.5

function bullets.clear()
  list = {}
end

-- shot: { angle, speed, damage, impact, digRadius, digPower } (from Gun:fire)
function bullets.spawn(x, y, shot)
  list[#list + 1] = {
    x = x,
    y = y,
    prevX = x,
    prevY = y,
    dx = math.cos(shot.angle),
    dy = math.sin(shot.angle),
    speed = shot.speed,
    damage = shot.damage,
    impact = shot.impact or 0,
    digRadius = shot.digRadius or 0,
    digPower = shot.digPower or 0,
    life = MAX_LIFE,
  }
end

-- Advances a bullet along its path; returns true once it has hit something
local function step(b, dt, world)
  local distance = b.speed * dt
  local steps = math.max(1, math.ceil(distance))
  local sx, sy = b.dx * distance / steps, b.dy * distance / steps
  for _ = 1, steps do
    local nx, ny = b.x + sx, b.y + sy
    local px, py = math.floor(nx), math.floor(ny)

    local prop = props.hitTest(nx, ny)
    if prop then
      b.x, b.y = nx, ny
      props.damage(prop, b.damage)
      -- Push at the exact hit point so glancing shots spin the object
      props.impulse(prop, b.dx * b.impact, b.dy * b.impact, nx, ny)
      effects.impact(b.x, b.y, b.dx, b.dy, nil)
      return true
    end

    local target = targets.hitTest(px, py)
    if target then
      b.x, b.y = nx, ny
      targets.damage(target, b.damage)
      effects.impact(b.x, b.y, b.dx, b.dy, nil)
      return true
    end

    if world:isSolid(px, py) then
      local def = materials.defs[world:get(px, py)]
      -- Spawn effects in the last open pixel so debris isn't stuck in the wall
      effects.impact(b.x, b.y, b.dx, b.dy, def.color)
      if b.digRadius > 0 then
        destruction.dig(world, px + 0.5, py + 0.5, b.digRadius, b.digPower, b.dx, b.dy)
      end
      return true
    end

    b.x, b.y = nx, ny
  end
  return false
end

function bullets.update(dt, world)
  for i = #list, 1, -1 do
    local b = list[i]
    b.prevX, b.prevY = b.x, b.y
    b.life = b.life - dt
    if step(b, dt, world) or b.life <= 0 then
      table.remove(list, i)
    end
  end
end

function bullets.draw()
  for _, b in ipairs(list) do
    love.graphics.setColor(1, 0.75, 0.25, 0.8)
    love.graphics.line(b.prevX, b.prevY, b.x, b.y)
    love.graphics.setColor(1, 1, 0.85)
    love.graphics.rectangle("fill", math.floor(b.x), math.floor(b.y), 1, 1)
  end
end

return bullets
