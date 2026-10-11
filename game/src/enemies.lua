-- Monsters of the catacombs (design doc §8): ghouls that walk and lunge,
-- cave bats that hang from ceilings and swoop, and spitters that cling to
-- ceilings and lob acid globs. They are placed when an area is generated and
-- sleep until the hunter comes near; only enemies near the hunter are updated.
--
-- Enemies use the same pixel collision as the hunter (src.body) against the
-- terrain and physics objects (crates, fallen debris): they stand on them and
-- push them. While active each has a kinematic physics stand-in, so falling
-- objects land on them. Bullets and kicks hurt them; touching them or their
-- globs hurts the hunter (Player:hurt).
local Body = require("src.body")
local config = require("src.config")
local effects = require("src.effects")
local physics = require("src.physics")
local pickups = require("src.pickups")
local props = require("src.props")

local enemies = {}

-- Tuning. Speeds in px/s, damage in HP, times in seconds.
enemies.defs = {
  ghoul = {
    w = 8,
    h = 14,
    hp = 30,
    speed = 62, -- the hunter walks at 112, so he can outrun them
    jump = 250, -- hops up ledges when blocked (about 46 px)
    lungeRange = 44,
    lungeSpeed = 190,
    lungeLift = 150,
    lungeCooldown = 1.3,
    sight = 280, -- notices the hunter this close (with a clear line of sight)
    forget = 460, -- gives up the chase this far away
    damage = 12,
    knockback = 0.45, -- fraction of a bullet's impact force applied as speed
    gold = { 3, 6 }, -- gold dropped on death (min, max), scaled by toughness
    pushForce = 300, -- shoves crates in its way (the hunter pushes with 512)
    weight = 2.5, -- how much objects' momentum moves it (speed gained = momentum / weight)
  },
  bat = {
    w = 7,
    h = 5,
    hp = 8,
    speed = 125,
    accel = 420,
    sight = 210,
    forget = 520,
    damage = 6,
    gold = { 1, 3 },
    retreat = 0.8, -- flies off this long after biting
    knockback = 0.7,
    weight = 0.6,
  },
  spitter = {
    w = 10,
    h = 8,
    hp = 20,
    sight = 300,
    reload = 2.4, -- time between globs
    windup = 0.45, -- swells up this long before spitting (a tell)
    globSpeed = 190,
    globGravity = 300,
    globDamage = 10,
    gold = { 4, 8 },
    knockback = 0,
    weight = 3,
  },
}

local ITEM_DROP_CHANCE = 0.1 -- chance a dying monster drops an ammo type or attachment
local ACTIVE_RANGE = 520 -- enemies further than this from the hunter are frozen
local GLOB_LIFE = 4

local list = {}
local globs = {}

function enemies.clear()
  list, globs = {}, {}
end

function enemies.count()
  return #list
end

-- Spawns an enemy. Ghouls stand on the ground at (x, groundY); bats and
-- spitters hang from the ceiling at (x, ceilingY). toughness >= 1 scales HP.
function enemies.spawn(kind, x, y, toughness)
  local def = assert(enemies.defs[kind], "unknown enemy: " .. tostring(kind))
  local top = kind == "ghoul" and y - def.h or y
  local e = {
    kind = kind,
    def = def,
    body = Body.new(math.floor(x - def.w / 2), math.floor(top), def.w, def.h),
    hp = math.floor(def.hp * (toughness or 1) + 0.5),
    toughness = toughness or 1,
    state = kind == "ghoul" and "idle" or "sleep",
    facing = love.math.random() < 0.5 and -1 or 1,
    timer = love.math.random() * 2, -- general-purpose state timer
    cooldown = 0,
    sightTimer = love.math.random() * 0.25,
    seesPlayer = false,
    flash = 0,
    stun = 0,
    phase = love.math.random() * 10, -- animation clock
    grounded = false,
  }
  list[#list + 1] = e
  return e
end

local function center(e)
  local b = e.body
  return b.x + b.w / 2, b.y + b.h / 2
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

-- True if nothing solid lies on the straight line between two points
local function lineOfSight(world, x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local steps = math.ceil(math.max(math.abs(dx), math.abs(dy)) / 2)
  for i = 1, steps - 1 do
    local t = i / steps
    if world:isSolid(math.floor(x0 + dx * t), math.floor(y0 + dy * t)) then
      return false
    end
  end
  return true
end

local function removePhysics(e)
  if e.phys then
    e.phys:destroy()
    e.phys = nil
  end
end

local function die(e)
  e.dead = true
  removePhysics(e)
  local cx, cy = center(e)
  local gold = love.math.random(e.def.gold[1], e.def.gold[2])
  pickups.dropGold(cx, cy, math.floor(gold * e.toughness + 0.5))
  pickups.maybeDropItem(cx, cy, ITEM_DROP_CHANCE)
  local colors = {
    ghoul = { { 0.42, 0.10, 0.10 }, { 0.55, 0.52, 0.48 } },
    bat = { { 0.40, 0.08, 0.10 }, { 0.20, 0.17, 0.20 } },
    spitter = { { 0.35, 0.62, 0.25 }, { 0.40, 0.30, 0.32 } },
  }
  local c = colors[e.kind]
  for i = 1, 16 do
    local a = love.math.random() * math.pi * 2
    local s = 30 + love.math.random() * 110
    effects.particle(cx, cy, math.cos(a) * s, math.sin(a) * s - 40, 0.6 + love.math.random() * 0.5, c[i % 2 + 1], 520)
  end
end

-- Damages an enemy. (dx, dy) is the hit direction, force the impact
function enemies.damage(e, amount, dx, dy, force)
  if e.dead then
    return
  end
  e.hp = e.hp - amount
  e.flash = 0.08
  local cx = center(e)
  effects.popup(cx, e.body.y - 2, tostring(amount), { 1, 0.9, 0.3 })
  -- Being shot wakes it and makes it hunt the hunter
  if e.state == "sleep" or e.state == "idle" then
    e.state = e.kind == "spitter" and "watch" or "chase"
  end
  e.seesPlayer = true
  if force and force > 0 and e.def.knockback > 0 then
    e.body.vx = e.body.vx + (dx or 0) * force * e.def.knockback
    e.body.vy = e.body.vy + (dy or 0) * force * e.def.knockback - 30
    e.stun = 0.15
  end
  if e.hp <= 0 then
    die(e)
  end
end

-- Explosions: hurts every enemy within the radius (more at the centre) and
-- throws them away from it. `force` is the shove speed at the centre.
function enemies.damageArea(x, y, radius, damage, force)
  for _, e in ipairs(list) do
    if not e.dead then
      local cx, cy = center(e)
      local dx, dy = cx - x, cy - y
      local dist = math.sqrt(dx * dx + dy * dy)
      local reach = radius + math.max(e.body.w, e.body.h) / 2
      if dist < reach then
        local fall = 1 - 0.6 * dist / reach
        local d = math.max(1, dist)
        enemies.damage(e, math.max(1, math.floor(damage * fall + 0.5)), dx / d, dy / d, force * fall / math.max(0.1, e.def.knockback > 0 and e.def.knockback or 1))
      end
    end
  end
end

-- Sets an enemy alight: dps burning damage for `time` seconds (a stronger
-- fire replaces a weaker one; it refreshes the time)
function enemies.ignite(e, dps, time)
  if e.dead then
    return
  end
  if e.burn then
    e.burn.dps = math.max(e.burn.dps, dps)
    e.burn.left = math.max(e.burn.left, time)
  else
    e.burn = { dps = dps, left = time, tick = 0.5 }
  end
end

-- Burning: a damage tick every half second and flickering flames
local function updateBurn(e, dt)
  local burn = e.burn
  if not burn then
    return
  end
  burn.left = burn.left - dt
  burn.tick = burn.tick - dt
  if love.math.random() < 0.5 then
    local cx = center(e)
    effects.particle(cx + (love.math.random() - 0.5) * e.body.w, e.body.y + love.math.random() * e.body.h, (love.math.random() - 0.5) * 12, -25 - love.math.random() * 25, 0.35, { 1, 0.5 + love.math.random() * 0.3, 0.15 }, -40, true)
  end
  if burn.tick <= 0 then
    burn.tick = 0.5
    enemies.damage(e, math.max(1, math.floor(burn.dps * 0.5 + 0.5)))
  end
  if burn.left <= 0 then
    e.burn = nil
  end
end

-- Bullet hit test: an enemy or an acid glob at the pixel (globs can be shot down)
function enemies.hitTest(px, py)
  for _, e in ipairs(list) do
    local b = e.body
    if not e.dead and px >= b.x and px < b.x + b.w and py >= b.y and py < b.y + b.h then
      return e
    end
  end
  for _, g in ipairs(globs) do
    if not g.dead and math.abs(px - g.x) <= 2 and math.abs(py - g.y) <= 2 then
      return g
    end
  end
  return nil
end

-- Applies a bullet to whatever hitTest returned
function enemies.hit(thing, amount, dx, dy, force)
  if thing.isGlob then
    thing.dead = true
    for _ = 1, 6 do
      effects.particle(thing.x, thing.y, (love.math.random() - 0.5) * 90, -love.math.random() * 60, 0.4, { 0.55, 0.95, 0.35 }, 300, true)
    end
  else
    enemies.damage(thing, amount, dx, dy, force)
  end
end

-- The hunter's kick: hurts and shoves enemies in the box
function enemies.kick(x, y, w, h, dir, damage)
  for _, e in ipairs(list) do
    local b = e.body
    if not e.dead and overlaps(x, y, w, h, b.x, b.y, b.w, b.h) then
      enemies.damage(e, damage, dir, -0.3, 0)
      if e.def.knockback > 0 then
        b.vx = dir * 220
        b.vy = -140
        e.stun = 0.35
      end
    end
  end
end

-- Collision against terrain and physics objects. Objects the enemy already
-- overlapped at the start of its update are ignored, so a crate dropped onto
-- it can never trap it.
local function collider(e, world)
  if not e.collide then
    e.collide = function(x, y, w, h)
      if Body.terrainOverlaps(world, x, y, w, h) then
        return true
      end
      local prop = props.overlapsRect(x, y, w, h, e.ignoreProps)
      if prop then
        return true, prop
      end
      return false
    end
  end
  return e.collide
end

-- Ghoul: wanders when idle; chases on sight, hopping up ledges, and lunges
-- when close
local function updateGhoul(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local collide = collider(e, world)
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  e.grounded = Body.isGrounded(b, collide) and b.vy >= 0

  if e.state == "idle" and e.seesPlayer and dist < def.sight then
    e.state = "chase"
  elseif e.state == "chase" and dist > def.forget then
    e.state = "idle"
  end

  local want = 0
  if e.stun > 0 then
    want = nil -- knocked back: no control
  elseif e.state == "chase" then
    want = px < cx - 2 and -1 or (px > cx + 2 and 1 or 0)
    e.facing = want ~= 0 and want or e.facing
    if e.grounded and e.cooldown <= 0 and dist < def.lungeRange and math.abs(py - cy) < 24 then
      b.vx = e.facing * def.lungeSpeed
      b.vy = -def.lungeLift
      e.cooldown = def.lungeCooldown
      e.grounded = false
    end
  else
    -- Idle: shuffle a few steps now and then
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.wander = love.math.random() < 0.5 and 0 or (love.math.random() < 0.5 and -1 or 1)
      e.timer = 1 + love.math.random() * 2
    end
    want = e.wander or 0
    if want ~= 0 then
      e.facing = want
    end
  end

  if want and e.grounded then
    local speed = e.state == "chase" and def.speed or def.speed * 0.35
    local target = want * speed
    local step = 900 * dt
    b.vx = b.vx < target and math.min(b.vx + step, target) or math.max(b.vx - step, target)
  elseif e.grounded then
    b.vx = b.vx * math.max(0, 1 - 8 * dt)
  end
  b.vy = math.min(b.vy + config.gravity * dt, 450)

  local blocked, blocker = Body.moveX(b, collide, b.vx * dt, 4)
  if blocked then
    if blocker and want and want ~= 0 then
      props.push(blocker, want * def.pushForce, 0)
    end
    if e.grounded and want and want ~= 0 then
      if e.state == "chase" then
        b.vy = -def.jump -- hop up the obstacle
      else
        e.wander = -want -- turn around
      end
    end
    b.vx = 0
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = 0
  end
  if e.grounded and b.vy >= 0 then
    Body.snapDown(b, collide, 4)
  end
  e.phase = e.phase + dt * (math.abs(b.vx) / 9 + 1)
end

-- Bat: hangs asleep until it sees the hunter, then flutters at him, bites,
-- and veers off before coming back
local function updateBat(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  e.phase = e.phase + dt * 18

  if e.state == "sleep" then
    if e.seesPlayer and dist < def.sight then
      e.state = "chase"
    else
      return
    end
  end
  if e.state == "chase" and dist > def.forget then
    e.state = "hover"
  elseif e.state == "hover" and e.seesPlayer and dist < def.sight then
    e.state = "chase"
  end

  local tx, ty = 0, 0
  if e.state == "chase" then
    local d = math.max(1, dist)
    tx, ty = (px - cx) / d * def.speed, (py - 4 - cy) / d * def.speed
  elseif e.state == "retreat" then
    local d = math.max(1, dist)
    tx, ty = -(px - cx) / d * def.speed, -def.speed * 0.8
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.state = "chase"
    end
  end
  -- Fluttery: a wobble on top of the steering
  ty = ty + math.sin(e.phase * 0.35) * 40
  if e.stun <= 0 then
    local step = def.accel * dt
    b.vx = b.vx < tx and math.min(b.vx + step, tx) or math.max(b.vx - step, tx)
    b.vy = b.vy < ty and math.min(b.vy + step, ty) or math.max(b.vy - step, ty)
  end
  if tx ~= 0 then
    e.facing = tx > 0 and 1 or -1
  end
  local collide = collider(e, world)
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.5
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.5
  end
end

-- Spits an acid glob in an arc that lands on (tx, ty)
local function spit(e, tx, ty)
  local def = e.def
  local cx, cy = center(e)
  cy = cy + 3
  local dx, dy = tx - cx, ty - cy
  local t = math.max(0.35, math.sqrt(dx * dx + dy * dy) / def.globSpeed)
  globs[#globs + 1] = {
    isGlob = true,
    x = cx,
    y = cy,
    vx = dx / t,
    vy = dy / t - 0.5 * def.globGravity * t,
    gravity = def.globGravity,
    damage = def.globDamage,
    life = GLOB_LIFE,
  }
  for _ = 1, 5 do
    effects.particle(cx, cy, (love.math.random() - 0.5) * 50, love.math.random() * 40, 0.3, { 0.55, 0.95, 0.35 }, 200, true)
  end
end

-- Spitter: clings to the ceiling and lobs globs when it sees the hunter.
-- Falls if the rock it clings to is shot away.
local function updateSpitter(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  e.phase = e.phase + dt

  local clinging = Body.terrainOverlaps(world, b.x + 2, b.y - 1, b.w - 4, 1)
  if not clinging then
    local collide = collider(e, world)
    b.vy = math.min(b.vy + config.gravity * dt, 450)
    if Body.moveY(b, collide, b.vy * dt) then
      b.vy = 0
    end
  end

  if e.seesPlayer and dist < def.sight then
    e.state = "watch"
  elseif e.state == "watch" and dist > def.sight * 1.4 then
    e.state = "sleep"
  end
  if e.state ~= "watch" then
    e.windup = nil
    return
  end
  e.facing = px < cx and -1 or 1
  if e.windup then
    e.windup = e.windup - dt
    if e.windup <= 0 then
      e.windup = nil
      if e.seesPlayer then
        spit(e, px, py)
      end
      e.cooldown = def.reload
    end
  elseif e.cooldown <= 0 and e.seesPlayer then
    e.windup = def.windup
  end
end

-- Moving physics objects (kicked crates, falling rock) hurt what they hit.
-- Each object can hurt a given enemy at most once per second, so one slide
-- across it isn't counted every frame.
local PROP_HIT_COOLDOWN = 1
local MAX_PROP_KNOCKBACK = 340 -- px/s

local function propImpacts(e, dt)
  local b = e.body
  e.propHit = e.propHit or {}
  for p, t in pairs(e.propHit) do
    e.propHit[p] = t - dt
    if e.propHit[p] <= 0 then
      e.propHit[p] = nil
    end
  end
  -- A pixel wider all round: the enemy's physics stand-in stops objects at
  -- contact, so they touch rather than overlap
  for p in pairs(props.overlapping(b.x - 1, b.y - 1, b.w + 2, b.h + 2)) do
    if not e.propHit[p] then
      -- The object's own velocity as it arrived, before the collision
      local pvx, pvy = p.prevVx or 0, p.prevVy or 0
      local damage, momentum = props.impactDamage(p, pvx, pvy)
      if damage > 0 then
        e.propHit[p] = PROP_HIT_COOLDOWN
        local speed = math.sqrt(pvx * pvx + pvy * pvy)
        enemies.damage(e, damage)
        -- Knocked along the object's path by its momentum; heavy objects and
        -- light creatures fly furthest. Spitters cling to the rock instead.
        if e.kind ~= "spitter" then
          local push = math.min(momentum / e.def.weight, MAX_PROP_KNOCKBACK)
          b.vx = pvx / speed * push
          b.vy = pvy / speed * push - 40
          e.stun = 0.35
        end
      end
    end
  end
end

local UPDATE = { ghoul = updateGhoul, bat = updateBat, spitter = updateSpitter }

-- Before the physics step: moves each stand-in to its enemy via velocity (like
-- the hunter's), so physics objects get proper contact responses
function enemies.syncPhysics(dt)
  for _, e in ipairs(list) do
    if e.phys and not e.dead then
      local b = e.body
      local tx, ty = b.x + b.w / 2, b.y + b.h / 2
      local x, y = e.phys:getPosition()
      if math.abs(tx - x) + math.abs(ty - y) > 24 then
        e.phys:setPosition(tx, ty)
        e.phys:setLinearVelocity(0, 0)
      else
        e.phys:setLinearVelocity((tx - x) / dt, (ty - y) / dt)
      end
    end
  end
end

function enemies.update(dt, world, player)
  local px, py = player:center()
  local pb = player.body
  for i = #list, 1, -1 do
    local e = list[i]
    if e.dead then
      table.remove(list, i)
    else
      local cx, cy = center(e)
      if math.abs(cx - px) < ACTIVE_RANGE and math.abs(cy - py) < ACTIVE_RANGE then
        e.flash = math.max(0, e.flash - dt)
        e.stun = math.max(0, e.stun - dt)
        e.cooldown = math.max(0, e.cooldown - dt)
        e.ignoreProps = props.overlapping(e.body.x, e.body.y, e.body.w, e.body.h)
        if not e.phys then
          local b = e.body
          e.phys = love.physics.newBody(physics.world, b.x + b.w / 2, b.y + b.h / 2, "kinematic")
          love.physics.newFixture(e.phys, love.physics.newRectangleShape(b.w, b.h))
        end
        e.sightTimer = e.sightTimer - dt
        if e.sightTimer <= 0 then
          e.sightTimer = 0.25
          e.seesPlayer = lineOfSight(world, cx, cy, px, py)
        end
        UPDATE[e.kind](e, dt, world, player, px, py)
        propImpacts(e, dt)
        updateBurn(e, dt)
        -- Touching the hunter hurts him
        local b = e.body
        if not player.dead and e.state ~= "sleep" and overlaps(b.x, b.y, b.w, b.h, pb.x, pb.y, pb.w, pb.h) then
          if e.def.damage and player:hurt(e.def.damage, center(e)) and e.kind == "bat" then
            e.state = "retreat"
            e.timer = e.def.retreat
          end
        end
      end
    end
  end

  for i = #globs, 1, -1 do
    local g = globs[i]
    g.life = g.life - dt
    g.vy = g.vy + g.gravity * dt
    -- March so fast globs don't skip through thin walls or the hunter
    local steps = math.max(1, math.ceil(math.max(math.abs(g.vx), math.abs(g.vy)) * dt))
    for _ = 1, steps do
      if g.dead then
        break
      end
      g.x = g.x + g.vx * dt / steps
      g.y = g.y + g.vy * dt / steps
      if overlaps(g.x - 1, g.y - 1, 3, 3, pb.x, pb.y, pb.w, pb.h) and not player.dead then
        player:hurt(g.damage, g.x - g.vx * 0.01, g.y)
        g.dead = true
      elseif world:isSolid(math.floor(g.x), math.floor(g.y)) then
        g.dead = true
      else
        local prop = props.hitTest(g.x, g.y)
        if prop then
          props.impulse(prop, g.vx * 0.15, g.vy * 0.15, g.x, g.y)
          g.dead = true
        end
      end
    end
    if g.dead or g.life <= 0 then
      for _ = 1, 7 do
        effects.particle(g.x, g.y, (love.math.random() - 0.5) * 80, -love.math.random() * 70, 0.5, { 0.5, 0.92, 0.3 }, 300, true)
      end
      table.remove(globs, i)
    end
  end
end

-- Drawing ---------------------------------------------------------------

local function px(x, y, w, h)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w or 1, h or 1)
end

local GHOUL = {
  skin = { 0.52, 0.50, 0.47 },
  skinDark = { 0.36, 0.34, 0.33 },
  rags = { 0.20, 0.17, 0.17 },
}

-- A hunched, long-armed scavenger, pale as ash
local function drawGhoul(e)
  local b, f = e.body, e.facing
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local x, y = b.x, b.y
  local mid = x + 4
  local step = e.grounded and math.sin(e.phase) or 0.6
  -- Legs: bent, scuttling
  color(GHOUL.skinDark)
  px(mid - 2 + step * 1.5, y + 10, 1, 4)
  px(mid + 1 - step * 1.5, y + 10, 1, 4)
  -- Hunched back and torso in rags
  color(GHOUL.rags)
  px(mid - 3, y + 5, 6, 6)
  color(GHOUL.skin)
  px(mid - 3 - f, y + 4, 5, 2) -- the hump of the back
  px(mid + f * 2, y + 6, 2, 3)
  -- Head thrust forward and low
  color(GHOUL.skin)
  px(mid + f * 3 - 1, y + 3, 3, 3)
  -- Long arms reaching ahead, swinging
  color(GHOUL.skinDark)
  local reach = e.state == "chase" and 1 or 0
  px(mid + f * (2 + reach), y + 7 + step, 1, 4)
  px(mid + f * (4 + reach), y + 9 - step, 1, 3)
end

local function drawGhoulEyes(e)
  local b, f = e.body, e.facing
  local mid = b.x + 4
  love.graphics.setColor(1, 0.25, 0.15)
  px(mid + f * 3 + (f > 0 and 1 or -1), b.y + 4)
end

-- A ragged bat: body and two flapping wings
local function drawBat(e)
  local b = e.body
  local white = e.flash > 0
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.18, 0.14, 0.17 })
  local x, y = b.x, b.y
  if e.state == "sleep" then
    -- Hanging upside down, wings folded
    px(x + 2, y, 3, 5)
    px(x + 3, y - 1, 1, 1)
    return
  end
  px(x + 2, y + 1, 3, 3)
  local flap = math.sin(e.phase) > 0
  if flap then
    px(x, y, 2, 1)
    px(x + 5, y, 2, 1)
    px(x - 1, y - 1, 1, 1)
    px(x + 7, y - 1, 1, 1)
  else
    px(x, y + 3, 2, 1)
    px(x + 5, y + 3, 2, 1)
    px(x - 1, y + 4, 1, 1)
    px(x + 7, y + 4, 1, 1)
  end
end

local function drawBatEyes(e)
  local b = e.body
  if e.state == "sleep" then
    return
  end
  love.graphics.setColor(1, 0.35, 0.25)
  px(b.x + 2, b.y + 2)
  px(b.x + 4, b.y + 2)
end

-- A fleshy sac hanging from the rock by tendrils; it swells before spitting
local function drawSpitter(e)
  local b = e.body
  local white = e.flash > 0
  local swell = e.windup and 1 or 0
  local x, y = b.x, b.y
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.30, 0.22, 0.24 })
  px(x + 1, y, 1, 3)
  px(x + 4, y, 1, 2)
  px(x + 8, y, 1, 3)
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.44, 0.33, 0.33 })
  px(x + 1 - swell, y + 2, 8 + swell * 2, 5 + swell)
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.56, 0.44, 0.42 })
  px(x + 2, y + 3, 3, 2)
end

local function drawSpitterGlow(e)
  local b = e.body
  local swell = e.windup and 1 or 0
  love.graphics.setColor(0.55, 1, 0.35)
  px(b.x + 4 - swell, b.y + 6 + swell, 2 + swell * 2, 1)
end

local DRAW = { ghoul = drawGhoul, bat = drawBat, spitter = drawSpitter }
local GLOW = { ghoul = drawGhoulEyes, bat = drawBatEyes, spitter = drawSpitterGlow }

local function onScreen(e, view)
  local b = e.body
  return b.x + b.w > view.x - 8 and b.x < view.x + view.w + 8 and b.y + b.h > view.y - 8 and b.y < view.y + view.h + 8
end

-- view: { x, y, w, h } in world pixels
function enemies.draw(view)
  for _, e in ipairs(list) do
    if onScreen(e, view) then
      DRAW[e.kind](e)
    end
  end
end

-- After the lighting: eyes, glowing mouths and acid globs
function enemies.drawEmissive(view)
  for _, e in ipairs(list) do
    if onScreen(e, view) then
      GLOW[e.kind](e)
    end
  end
  for _, g in ipairs(globs) do
    love.graphics.setColor(0.45, 0.9, 0.3)
    px(g.x - 1, g.y - 1, 3, 3)
    love.graphics.setColor(0.8, 1, 0.6)
    px(g.x, g.y)
  end
end

-- Globs and spitters' mouths give off a faint sickly light
function enemies.addLights(lighting, view)
  for _, g in ipairs(globs) do
    lighting.add(g.x, g.y, 26, 0.5, 1, 0.35, 0.7)
  end
  for _, e in ipairs(list) do
    if e.kind == "spitter" and onScreen(e, view) then
      local cx, cy = center(e)
      lighting.add(cx, cy + 4, e.windup and 30 or 16, 0.5, 1, 0.35, 0.5)
    end
  end
end

return enemies
