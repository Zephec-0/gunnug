-- Fast projectiles, marched one pixel at a time so they never tunnel through
-- thin terrain, targets or props.
--
-- A bullet carries `fx`, the special-ammo effects of the gun that fired it
-- (freeze, shock, poison, sticky, homing, ...; see src.items). Child bullets
-- (from Splitting and Cluster Rounds) carry none and never spawn children.
local audio = require("src.audio")
local destruction = require("src.destruction")
local effects = require("src.effects")
local fluids = require("src.fluids")
local enemies = require("src.enemies")
local materials = require("src.materials")
local props = require("src.props")
local shop = require("src.shop")
local targets = require("src.targets")

local bullets = {}

-- Set by src.game: the hunter, who explosions can hurt
bullets.player = nil

local list = {}
local stuck = {} -- Sticky Bombs waiting to go off: { x, y, enemy, ox, oy, timer, explosive }
local world -- the world of the last update (for blasts started outside it)
local MAX_LIFE = 1.5

function bullets.clear()
  list = {}
  stuck = {}
end

local function has(fx, key)
  return fx[key] ~= nil and fx[key] > 0
end

-- shot: { angle, speed, damage, impact, digRadius, digPower, pierce, bounces,
--         explosive, burn, tint, crit, fx, child, fuse, life } (from Gun:fire)
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
    crit = shot.crit,
    impact = shot.impact or 0,
    digRadius = shot.digRadius or 0,
    digPower = shot.digPower or 0,
    pierce = shot.pierce or 0,
    bounces = shot.bounces or 0,
    explosive = shot.explosive,
    burn = shot.burn,
    tint = shot.tint,
    fx = shot.fx or {},
    child = shot.child,
    fuse = shot.fuse, -- explodes when its (short) life runs out
    hit = {}, -- enemies already pierced, so they aren't hit twice
    age = 0,
    life = shot.life or MAX_LIFE,
  }
end

-- Explosive rounds: a blast that carves a crater and hurts and shoves
-- enemies and loose objects around it. One more explosive ammo type fitted
-- makes it bigger and stronger.
local function explode(b, w, x, y)
  local count, scale = b.explosive.count, b.explosive.scale
  -- A wide blast that hurts, but only a small bite out of the terrain (so
  -- explosives aren't a tunnelling tool)
  local radius = (26 + 6 * (count - 1)) * (scale < 1 and 0.75 or 1)
  local damage = (10 + 4 * (count - 1)) * scale
  destruction.dig(w, x, y, b.blastDig or math.max(3, radius * 0.25), b.blastPower or 1.5, b.dx, b.dy)
  effects.explosion(x, y, radius)
  fluids.explosion(x, y, radius) -- lights any gas it reaches
  audio.play("explosion")
  shop.explosion(x, y, radius)
  -- The hunter is caught in it too
  local player = bullets.player
  if player and not player.dead then
    local px, py = player:center()
    local dx, dy = px - x, py - y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < radius + 6 then
      player:hurt(math.max(1, math.floor(damage * (1 - 0.6 * dist / (radius + 6)) + 0.5)), x, y, b.cause or "selfblast")
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

-- A blast out of nowhere (Unstable Rounds going off in the barrel)
-- cause: what set it off, for the death recap (src.deaths): "dynamite", "keg"; default his own
function bullets.blast(x, y, count, scale, dig, digPower, cause)
  if world then
    explode({ explosive = { count = count, scale = scale }, dx = 0, dy = -1, blastDig = dig, blastPower = digPower, cause = cause }, world, x, y)
  end
end

-- Splitting and Cluster Rounds: what a bullet becomes when it ends. `forward`
-- is true when it ended in an enemy (the pieces carry on through), false for
-- terrain (they scatter back out of the wall).
local function spawnChildren(b, x, y, forward)
  if b.child then
    return
  end
  local fx = b.fx
  local base = math.atan2(b.dy, b.dx) + (forward and 0 or math.pi)
  if has(fx, "split") then
    for side = -1, 1, 2 do
      bullets.spawn(x, y, {
        angle = base + side * (0.35 + love.math.random() * 0.25),
        speed = b.speed * 0.8,
        damage = math.max(1, math.floor(b.damage * 0.4 + 0.5)),
        impact = b.impact * 0.3,
        digRadius = 1,
        digPower = 0,
        tint = b.tint,
        child = true,
      })
    end
  end
  if has(fx, "cluster") then
    for i = -1, 1 do
      bullets.spawn(x, y, {
        angle = base + i * 0.8 + (love.math.random() - 0.5) * 0.4,
        speed = 150 + love.math.random() * 80,
        damage = 1,
        tint = b.tint,
        child = true,
        fuse = true,
        life = 0.22 + love.math.random() * 0.14,
        explosive = { count = 1, scale = 0.4 },
      })
    end
  end
end

-- Sticky Bombs: the bullet stays where it hit (on an enemy it rides along)
local function stick(b, x, y, enemy)
  local ex = b.explosive
  local bomb = { x = x, y = y, timer = 0.8, explosive = { count = ex and ex.count or 1, scale = ex and ex.scale or 1 }, tint = b.tint }
  if enemy and not enemy.isGlob then
    bomb.enemy = enemy
    bomb.ox, bomb.oy = x - enemy.body.x, y - enemy.body.y
  end
  stuck[#stuck + 1] = bomb
end

-- Little visual cues for each kind of special ammo, as the bullet flies
local function trailFx(b, dt)
  if b.child then
    return
  end
  local fx = b.fx
  local r = love.math.random
  local x, y = b.x, b.y
  if has(fx, "freeze") and r() < dt * 40 then
    effects.particle(x, y, (r() - 0.5) * 14, 6 + r() * 10, 0.45, { 0.72, 0.92, 1 }, 120, true) -- ice crystals
  end
  if has(fx, "poison") and r() < dt * 35 then
    effects.particle(x, y, (r() - 0.5) * 8, 8, 0.45, { 0.45, 0.9, 0.3 }, 320, true) -- dripping
  end
  if has(fx, "acid") and r() < dt * 30 then
    effects.particle(x, y, (r() - 0.5) * 10, -4, 0.5, { 0.82, 1, 0.3 }, -40, true) -- bubbles
  end
  if has(fx, "vamp") and r() < dt * 30 then
    effects.particle(x, y, (r() - 0.5) * 8, 4, 0.4, { 0.8, 0.1, 0.2 }, 320, true)
  end
  if has(fx, "greed") and r() < dt * 40 then
    effects.particle(x + (r() - 0.5) * 4, y + (r() - 0.5) * 4, 0, 0, 0.3, { 1, 0.88, 0.35 }, 0, true) -- sparkle
  end
  if has(fx, "execute") and r() < dt * 30 then
    effects.particle(x, y, (r() - 0.5) * 20, (r() - 0.5) * 20, 0.25, { 0.6, 0.08, 0.1 }, 0, true)
  end
  if has(fx, "ghost") and r() < dt * 40 then
    effects.particle(x, y, (r() - 0.5) * 10, -8, 0.4, { 0.7, 0.88, 1 }, -20, true) -- wisps
  end
  if has(fx, "gravity") and r() < dt * 50 then
    local a = r() * math.pi * 2
    effects.particle(x + math.cos(a) * 7, y + math.sin(a) * 7, -math.cos(a) * 30, -math.sin(a) * 30, 0.22, { 0.6, 0.35, 0.95 }, 0, true) -- drawn inward
  end
  if b.burn then
    fluids.ignite(b.x, b.y, 0.6, true) -- incendiary rounds light gas as they pass through it
  end
  if b.burn and r() < dt * 45 then
    effects.particle(x, y, (r() - 0.5) * 10, -10, 0.35, { 1, 0.55 + r() * 0.3, 0.15 }, -60, true) -- embers
  end
  -- Curving shots (seeker, boomerang) leave a trail line behind them
  if has(fx, "homing") or has(fx, "boomerang") then
    b.trail = b.trail or {}
    table.insert(b.trail, 1, { x, y })
    b.trail[9] = nil
  end
end

-- What a hit looks like for each status ammo
local function hitFx(b, enemy)
  local fx = b.fx
  local eb = enemy.body
  local x, y = eb.x + eb.w / 2, eb.y + eb.h / 2
  local r = love.math.random
  if has(fx, "freeze") then
    for _ = 1, 7 do
      local a = r() * math.pi * 2
      effects.particle(x, y, math.cos(a) * 50, math.sin(a) * 50 - 20, 0.5, { 0.75, 0.93, 1 }, 200, true)
    end
  end
  if has(fx, "concussive") then
    effects.ring(x, y, 20, { 0.9, 0.9, 1 })
  end
  if has(fx, "shock") then
    effects.ring(x, y, 10, { 0.6, 0.7, 1 })
  end
  if has(fx, "poison") or has(fx, "acid") then
    for _ = 1, 5 do
      effects.particle(x, y, (r() - 0.5) * 70, -r() * 50, 0.5, has(fx, "acid") and { 0.8, 1, 0.3 } or { 0.45, 0.9, 0.3 }, 300, true)
    end
  end
  if has(fx, "vamp") then
    for _ = 1, 4 do
      effects.particle(x, y, (r() - 0.5) * 60, -r() * 40, 0.5, { 0.8, 0.1, 0.2 }, 320, true)
    end
  end
end

-- A bullet ends in an enemy, prop or target: explode if it carries explosive rounds
local function finish(b, w, x, y, forward)
  if b.explosive then
    explode(b, w, x, y)
  end
  spawnChildren(b, x, y, forward)
  if has(b.fx, "gravity") then
    enemies.pull(x, y, 50, 150)
    effects.ring(x, y, 36, { 0.6, 0.35, 0.95 }, true)
  end
  return true
end

-- What a bullet does to an enemy it hits, on top of the damage itself
local function hurtEnemy(b, enemy)
  local fx = b.fx
  local damage = b.damage
  if not enemy.isGlob then
    if has(fx, "execute") and enemy.hp <= enemy.maxHp * 0.3 then
      damage = damage * 2
    end
    if has(fx, "sneak") and enemy.state == "sleep" then
      damage = damage * 3
    end
  end
  enemies.hit(enemy, damage, b.dx, b.dy, b.impact, b.crit, fx)
  audio.play("hit")
  if enemy.isGlob then
    return
  end
  hitFx(b, enemy)
  if b.burn then
    enemies.ignite(enemy, b.burn.dps, b.burn.time)
  end
  if has(fx, "freeze") then
    enemies.chill(enemy, 3)
  end
  if has(fx, "poison") then
    enemies.poison(enemy, 4 * fx.poison, 5)
  end
  if has(fx, "acid") then
    enemies.corrode(enemy, 4)
  end
  if has(fx, "concussive") then
    enemies.stun(enemy, 0.7)
  end
  if has(fx, "shock") and not enemy.dead then
    enemies.chain(enemy, damage, fx)
  end
end

-- Advances a bullet along its path; returns true once it has hit something
local function step(b, dt, w)
  local fx = b.fx
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
      if has(fx, "sticky") and not b.child then
        stick(b, b.x, b.y)
        return true
      end
      return finish(b, w, b.x, b.y, true)
    end

    local enemy = enemies.hitTest(nx, ny)
    if enemy and not b.hit[enemy] then
      b.x, b.y = nx, ny
      hurtEnemy(b, enemy)
      effects.impact(b.x, b.y, b.dx, b.dy, nil)
      if has(fx, "sticky") and not b.child and not enemy.isGlob then
        stick(b, b.x, b.y, enemy)
        return true
      end
      if b.pierce > 0 and not enemy.isGlob then
        b.pierce = b.pierce - 1 -- through it and on
        b.hit[enemy] = true
      else
        return finish(b, w, b.x, b.y, true)
      end
    end

    -- The shop hatch's chain: a shot that hits it snaps it
    local chainOf = shop.chainAt(px, py)
    if chainOf then
      b.x, b.y = nx, ny
      shop.breakChain(chainOf)
      effects.impact(b.x, b.y, b.dx, b.dy, nil)
      return finish(b, w, b.x, b.y, true)
    end

    local target = targets.hitTest(px, py)
    if target then
      b.x, b.y = nx, ny
      targets.damage(target, b.damage)
      effects.impact(b.x, b.y, b.dx, b.dy, nil)
      return finish(b, w, b.x, b.y, true)
    end

    if w:isSolid(px, py) and not has(fx, "ghost") then
      local def = materials.defs[w:get(px, py)]
      if b.bounces > 0 then
        -- Ricochet: reflect off whichever face was struck, from the last open pixel
        local blockedX = w:isSolid(px, math.floor(b.y))
        local blockedY = w:isSolid(math.floor(b.x), py)
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
        if has(fx, "sticky") and not b.child then
          stick(b, b.x, b.y)
        elseif b.explosive then
          explode(b, w, b.x, b.y) -- the blast does the digging
        elseif b.digRadius > 0 then
          destruction.dig(w, px + 0.5, py + 0.5, b.digRadius, b.digPower, b.dx, b.dy)
        end
        if not (has(fx, "sticky") and not b.child) then
          spawnChildren(b, b.x, b.y, false)
          if has(fx, "gravity") then
            enemies.pull(b.x, b.y, 50, 150)
            effects.ring(b.x, b.y, 36, { 0.6, 0.35, 0.95 }, true)
          end
        end
        return true
      end
    else
      b.x, b.y = nx, ny
    end
  end
  return false
end

-- Seeker Rounds curve toward the nearest enemy; Boomerang Rounds turn around
local function steer(b, dt)
  local fx = b.fx
  if has(fx, "homing") then
    local target = enemies.nearest(b.x, b.y, 110, b.hit)
    if target then
      local tb = target.body
      local want = math.atan2(tb.y + tb.h / 2 - b.y, tb.x + tb.w / 2 - b.x)
      local cur = math.atan2(b.dy, b.dx)
      local diff = (want - cur + math.pi) % (2 * math.pi) - math.pi
      local turn = math.max(-6 * dt, math.min(6 * dt, diff))
      b.dx, b.dy = math.cos(cur + turn), math.sin(cur + turn)
    end
  end
  if has(fx, "boomerang") and not b.returned and b.age > 0.2 then
    b.returned = true
    b.dx, b.dy = -b.dx, -b.dy
    b.hit = {}
    b.life = math.max(b.life, 0.8)
  end
end

function bullets.update(dt, w)
  world = w
  for i = #list, 1, -1 do
    local b = list[i]
    b.prevX, b.prevY = b.x, b.y
    b.life = b.life - dt
    b.age = b.age + dt
    steer(b, dt)
    trailFx(b, dt)
    local done = step(b, dt, w)
    if not done and b.life <= 0 and b.fuse and b.explosive then
      explode(b, w, b.x, b.y)
    end
    if done or b.life <= 0 then
      table.remove(list, i)
    end
  end

  for i = #stuck, 1, -1 do
    local s = stuck[i]
    s.timer = s.timer - dt
    if s.enemy then
      if s.enemy.dead then
        s.timer = 0 -- its carrier died: go off right there
      else
        s.x, s.y = s.enemy.body.x + s.ox, s.enemy.body.y + s.oy
      end
    end
    if love.math.random() < dt * 30 then
      effects.particle(s.x, s.y - 1, (love.math.random() - 0.5) * 20, -20 - love.math.random() * 20, 0.25, { 1, 0.7, 0.2 }, 60, true) -- fizzing fuse
    end
    if s.timer <= 0 then
      explode({ explosive = s.explosive, dx = 0, dy = -1 }, w, s.x, s.y)
      table.remove(stuck, i)
    end
  end
end

-- Drawn after the lighting (bullets glow)
function bullets.draw()
  local t = love.timer.getTime()
  for _, b in ipairs(list) do
    local c = b.tint or { 1, 0.75, 0.25 }
    local fx = b.fx
    -- Seeker and boomerang trails
    if b.trail and #b.trail > 1 then
      for i = 1, #b.trail - 1 do
        love.graphics.setColor(c[1], c[2], c[3], 0.6 * (1 - i / #b.trail))
        love.graphics.line(b.trail[i][1], b.trail[i][2], b.trail[i + 1][1], b.trail[i + 1][2])
      end
    end
    -- Glowing Rounds: a soft glare around the bullet
    if has(fx, "glow") then
      love.graphics.setColor(c[1], c[2], c[3], 0.22)
      love.graphics.circle("fill", b.x, b.y, 5)
      love.graphics.setColor(c[1], c[2], c[3], 0.4)
      love.graphics.circle("fill", b.x, b.y, 2.5)
    end
    local alpha = b.child and 0.5 or 0.8
    if has(fx, "ghost") then
      alpha = 0.35 + 0.3 * math.sin(t * 30 + b.age * 20) -- flickers in and out
    end
    if has(fx, "shock") then
      -- Crackling: a jagged line around the straight path
      local mx, my = (b.prevX + b.x) / 2, (b.prevY + b.y) / 2
      local nx, ny = -b.dy, b.dx
      local j1, j2 = (love.math.random() - 0.5) * 4, (love.math.random() - 0.5) * 4
      love.graphics.setColor(0.7, 0.8, 1, 0.9)
      love.graphics.line(b.prevX, b.prevY, mx + nx * j1, my + ny * j1, b.x + nx * j2 * 0.5, b.y + ny * j2 * 0.5)
    end
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.line(b.prevX, b.prevY, b.x, b.y)
    if has(fx, "boomerang") then
      -- It spins as it flies
      local sa = b.age * 35
      love.graphics.setColor(c[1], c[2], c[3], 0.95)
      love.graphics.line(b.x - math.cos(sa) * 2.5, b.y - math.sin(sa) * 2.5, b.x + math.cos(sa) * 2.5, b.y + math.sin(sa) * 2.5)
    end
    if b.fuse then
      -- A cluster bomblet: its fuse blinks faster and faster
      local blink = math.floor((0.4 - b.life) * 25) % 2 == 0
      love.graphics.setColor(1, blink and 0.3 or 0.8, 0.2)
      love.graphics.rectangle("fill", math.floor(b.x), math.floor(b.y), 2, 2)
    end
    if b.crit then
      love.graphics.setColor(1, 0.6, 0.2)
      love.graphics.rectangle("fill", math.floor(b.x) - 1, math.floor(b.y) - 1, 3, 3)
    end
    love.graphics.setColor(1, 1, 0.85)
    love.graphics.rectangle("fill", math.floor(b.x), math.floor(b.y), 1, 1)
  end
  for _, s in ipairs(stuck) do
    local on = math.floor(s.timer * 12) % 2 == 0
    love.graphics.setColor(on and 1 or 0.6, on and 0.35 or 0.2, 0.3)
    love.graphics.rectangle("fill", math.floor(s.x) - 1, math.floor(s.y) - 1, 3, 3)
  end
end

-- Each bullet carries a small warm light (a lot brighter for Glowing Rounds)
function bullets.addLights(lighting)
  for _, b in ipairs(list) do
    if has(b.fx, "glow") then
      lighting.add(b.x, b.y, 64, 1, 0.9, 0.55, 1.0)
    else
      lighting.add(b.x, b.y, 22, 1, 0.75, 0.4, 0.8)
    end
  end
  for _, s in ipairs(stuck) do
    lighting.add(s.x, s.y, 20, 1, 0.3, 0.2, 0.7)
  end
end

return bullets
