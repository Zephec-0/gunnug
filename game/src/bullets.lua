-- Fast projectiles, marched one pixel at a time so they never tunnel through
-- thin terrain, targets or props.
local audio = require("src.audio")
local destruction = require("src.destruction")
local effects = require("src.effects")
local enemies = require("src.enemies")
local materials = require("src.materials")
local props = require("src.props")
local shop = require("src.shop")
local targets = require("src.targets")

local bullets = {}

-- Set by src.game: the hunter, who explosions can hurt
bullets.player = nil

local list = {}
local MAX_LIFE = 1.5

function bullets.clear()
  list = {}
end

-- shot: { angle, speed, damage, impact, digRadius, digPower, pierce, bounces,
--         explosive, burn, tint } (from Gun:fire)
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
    pierce = shot.pierce or 0,
    bounces = shot.bounces or 0,
    explosive = shot.explosive,
    burn = shot.burn,
    tint = shot.tint,
    hit = {}, -- enemies already pierced, so they aren't hit twice
    life = MAX_LIFE,
  }
end

-- Explosive rounds: a blast that carves a crater and hurts and shoves
-- enemies and loose objects around it. One more explosive ammo type fitted
-- makes it bigger and stronger.
local function explode(b, world, x, y)
  local count, scale = b.explosive.count, b.explosive.scale
  -- A wide blast that hurts, but only a small bite out of the terrain (so
  -- explosives aren't a tunnelling tool)
  local radius = (26 + 6 * (count - 1)) * (scale < 1 and 0.75 or 1)
  local damage = (10 + 4 * (count - 1)) * scale
  destruction.dig(world, x, y, math.max(3, radius * 0.25), 1.5, b.dx, b.dy)
  effects.explosion(x, y, radius)
  audio.play("explosion")
  shop.explosion(x, y, radius)
  -- The hunter is caught in it too
  local player = bullets.player
  if player and not player.dead then
    local px, py = player:center()
    local dx, dy = px - x, py - y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < radius + 6 then
      player:hurt(math.max(1, math.floor(damage * (1 - 0.6 * dist / (radius + 6)) + 0.5)), x, y)
    end
  end
  enemies.damageArea(x, y, radius, math.max(1, math.floor(damage + 0.5)), 260 * scale)
  for _, p in ipairs(props.all()) do
    local px, py = p.body:getPosition()
    local dx, dy = px - x, py - y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < radius + 6 then
      local fall = 1 - dist / (radius + 6)
      props.damage(p, math.floor(damage * fall + 0.5))
      local d = math.max(1, dist)
      props.impulse(p, dx / d * 240 * fall, dy / d * 240 * fall - 60 * fall, px, py)
    end
  end
end

-- A bullet ends: explode if it carries explosive rounds
local function finish(b, world, x, y)
  if b.explosive then
    explode(b, world, x, y)
  end
  return true
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
      return finish(b, world, b.x, b.y)
    end

    local enemy = enemies.hitTest(nx, ny)
    if enemy and not b.hit[enemy] then
      b.x, b.y = nx, ny
      enemies.hit(enemy, b.damage, b.dx, b.dy, b.impact)
      audio.play("hit")
      if b.burn and not enemy.isGlob then
        enemies.ignite(enemy, b.burn.dps, b.burn.time)
      end
      effects.impact(b.x, b.y, b.dx, b.dy, nil)
      if b.pierce > 0 and not enemy.isGlob then
        b.pierce = b.pierce - 1 -- through it and on
        b.hit[enemy] = true
      else
        return finish(b, world, b.x, b.y)
      end
    end

    -- The shop hatch's chain: a shot that hits it snaps it
    local chainOf = shop.chainAt(px, py)
    if chainOf then
      b.x, b.y = nx, ny
      shop.breakChain(chainOf)
      effects.impact(b.x, b.y, b.dx, b.dy, nil)
      return finish(b, world, b.x, b.y)
    end

    local target = targets.hitTest(px, py)
    if target then
      b.x, b.y = nx, ny
      targets.damage(target, b.damage)
      effects.impact(b.x, b.y, b.dx, b.dy, nil)
      return finish(b, world, b.x, b.y)
    end

    if world:isSolid(px, py) then
      local def = materials.defs[world:get(px, py)]
      if b.bounces > 0 then
        -- Ricochet: reflect off whichever face was struck, from the last open pixel
        local blockedX = world:isSolid(px, math.floor(b.y))
        local blockedY = world:isSolid(math.floor(b.x), py)
        if blockedX or not blockedY then
          b.dx = -b.dx
        end
        if blockedY or not blockedX then
          b.dy = -b.dy
        end
        sx, sy = b.dx * distance / steps, b.dy * distance / steps
        b.bounces = b.bounces - 1
        effects.impact(b.x, b.y, b.dx, b.dy, nil)
      else
        -- Spawn effects in the last open pixel so debris isn't stuck in the wall
        effects.impact(b.x, b.y, b.dx, b.dy, def.color)
        audio.play("impact")
        if b.explosive then
          explode(b, world, b.x, b.y) -- the blast does the digging
        elseif b.digRadius > 0 then
          destruction.dig(world, px + 0.5, py + 0.5, b.digRadius, b.digPower, b.dx, b.dy)
        end
        return true
      end
    else
      b.x, b.y = nx, ny
    end
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

-- Drawn after the lighting (bullets glow)
function bullets.draw()
  for _, b in ipairs(list) do
    local c = b.tint or { 1, 0.75, 0.25 }
    love.graphics.setColor(c[1], c[2], c[3], 0.8)
    love.graphics.line(b.prevX, b.prevY, b.x, b.y)
    love.graphics.setColor(1, 1, 0.85)
    love.graphics.rectangle("fill", math.floor(b.x), math.floor(b.y), 1, 1)
  end
end

-- Each bullet carries a small warm light
function bullets.addLights(lighting)
  for _, b in ipairs(list) do
    lighting.add(b.x, b.y, 22, 1, 0.75, 0.4, 0.8)
  end
end

return bullets
