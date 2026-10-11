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
local audio = require("src.audio")
local Body = require("src.body")
local config = require("src.config")
local effects = require("src.effects")
local perks = require("src.perks")
local physics = require("src.physics")
local pickups = require("src.pickups")
local props = require("src.props")

local enemies = {}

-- Tuning. Speeds in px/s, damage in HP, times in seconds.
enemies.defs = {
  ghoul = {
    w = 10,
    h = 18,
    hp = 24,
    speed = 43, -- the hunter walks at 112, so he can outrun them
    jump = 250, -- hops up ledges when blocked (about 46 px)
    lungeRange = 48,
    lungeSpeed = 133,
    lungeLift = 150,
    lungeCooldown = 1.3,
    windup = 0.4, -- rears back this long before flinging its arms forward
    strike = 0.45, -- how long the arms stay flung out
    sight = 280, -- notices the hunter this close (with a clear line of sight)
    forget = 460, -- gives up the chase this far away
    damage = 12,
    knockback = 0.45, -- fraction of a bullet's impact force applied as speed
    gold = { 3, 6 }, -- gold dropped on death (min, max), scaled by toughness
    pushForce = 300, -- shoves crates in its way (the hunter pushes with 512)
    weight = 2.5, -- how much objects' momentum moves it (speed gained = momentum / weight)
  },
  bat = {
    w = 10,
    h = 7,
    hp = 8,
    speed = 88,
    accel = 294,
    sight = 210,
    forget = 520,
    damage = 6,
    gold = { 1, 3 },
    retreat = 0.8, -- flies off this long after biting
    chargeRange = 130, -- locks on when it can see the hunter this close
    lockTime = 0.55, -- hangs still and screeches this long before charging
    chargeSpeed = 210,
    chargeTime = 0.7, -- a straight-line dive this long at most
    chargeCooldown = 1.4,
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

-- Set by src.game: called as onKill(enemy, fx) when an enemy dies, with the
-- effects of the bullet that last hit it (nil for kicks and explosions)
enemies.onKill = nil

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
    maxHp = math.floor(def.hp * (toughness or 1) + 0.5),
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
  audio.play("enemy_die")
  removePhysics(e)
  local cx, cy = center(e)
  local gold = love.math.random(e.def.gold[1], e.def.gold[2])
  local greed = e.lastFx and e.lastFx.greed or 0
  pickups.dropGold(cx, cy, math.floor(gold * e.toughness * (1 + greed) + 0.5))
  pickups.maybeDropItem(cx, cy, ITEM_DROP_CHANCE * perks.prod("loot"))
  if enemies.onKill then
    enemies.onKill(e, e.lastFx)
  end
  -- (Monsters never drop weapons: those come from chests and the shop.)
  local r = love.math.random
  if e.kind == "ghoul" then
    -- Crumbles to ash, rags and a dropped arm; a pale wisp leaves the body
    for _ = 1, 16 do
      local g = 0.45 + r() * 0.3
      effects.chunk(cx + (r() - 0.5) * 8, cy + (r() - 0.5) * 12, (r() - 0.5) * 36, -20 - r() * 50, 1 + math.floor(r() * 2), 1, { g, g + 0.02, g + 0.04 }, 1.5 + r() * 1.5)
    end
    for _ = 1, 3 do
      effects.chunk(cx + (r() - 0.5) * 6, cy, (r() - 0.5) * 50, -40 - r() * 40, 3, 2, { 0.27, 0.28, 0.32 }, 3)
    end
    effects.chunk(cx, cy - 2, (r() - 0.5) * 60, -60, 4, 1, { 0.62, 0.64, 0.66 }, 3)
    for _ = 1, 8 do
      effects.particle(cx + (r() - 0.5) * 6, cy + (r() - 0.5) * 12, (r() - 0.5) * 12, -10 - r() * 20, 0.9 + r() * 0.5, { 0.78, 0.92, 1 }, -30, true)
    end
  elseif e.kind == "bat" then
    -- Folds up and plummets in pieces: two wings and the fuzzy body
    effects.chunk(cx - 2, cy, -50 - r() * 30, -50, 4, 1, { 0.26, 0.17, 0.24 }, 3)
    effects.chunk(cx + 2, cy, 50 + r() * 30, -50, 4, 1, { 0.26, 0.17, 0.24 }, 3)
    effects.chunk(cx, cy, (r() - 0.5) * 20, -20, 3, 3, { 0.20, 0.15, 0.20 }, 3)
    for _ = 1, 8 do
      effects.particle(cx, cy, (r() - 0.5) * 70, (r() - 0.5) * 60, 0.5, r() < 0.5 and { 0.32, 0.25, 0.32 } or { 0.40, 0.08, 0.10 }, 400)
    end
  else
    -- The spitter pops: acid splashes everywhere and fleshy bits fall
    for _ = 1, 14 do
      local a = r() * math.pi * 2
      effects.particle(cx, cy, math.cos(a) * (30 + r() * 70), math.sin(a) * (30 + r() * 70) - 20, 0.6 + r() * 0.4, { 0.5, 0.92, 0.3 }, 300, true)
    end
    for _ = 1, 4 do
      effects.chunk(cx + (r() - 0.5) * 6, cy, (r() - 0.5) * 70, -30 - r() * 50, 2, 2, { 0.44, 0.33, 0.33 }, 3)
    end
    for _ = 1, 3 do
      effects.chunk(cx + (r() - 0.5) * 8, cy + 2, (r() - 0.5) * 40, -10, 2, 1, { 0.45, 0.8, 0.28 }, 4) -- acid pools
    end
  end
end

-- Damages an enemy. (dx, dy) is the hit direction, force the impact
function enemies.damage(e, amount, dx, dy, force, crit, fx)
  if e.dead then
    return
  end
  if e.acid and e.acid > 0 then
    amount = math.floor(amount * 1.3 + 0.5) -- corroded
  end
  e.hp = e.hp - amount
  e.flash = 0.08
  if fx then
    e.lastFx = fx
  end
  if dx and dx ~= 0 then
    -- A hit shoves the sprite back for a moment
    e.stagger = math.min(0.2, 0.08 + (force or 0) / 2500)
    e.hitDir = dx > 0 and 1 or -1
  end
  local cx = center(e)
  if crit then
    effects.popup(cx, e.body.y - 4, amount .. "!", { 1, 0.55, 0.15 })
  else
    effects.popup(cx, e.body.y - 2, tostring(amount), { 1, 0.9, 0.3 })
  end
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

-- Status effects from special ammo ---------------------------------------

-- Poison: steady damage for `time` seconds (a stronger dose replaces a weaker one)
function enemies.poison(e, dps, time)
  if e.dead then
    return
  end
  if e.poisoned then
    e.poisoned.dps = math.max(e.poisoned.dps, dps)
    e.poisoned.left = math.max(e.poisoned.left, time)
  else
    e.poisoned = { dps = dps, left = time, tick = 0.5 }
  end
end

-- Chilled: moves and acts slowly for `time` seconds
function enemies.chill(e, time)
  e.slow = math.max(e.slow or 0, time)
end

-- Corroded: takes extra damage for `time` seconds
function enemies.corrode(e, time)
  e.acid = math.max(e.acid or 0, time)
end

function enemies.stun(e, time)
  e.stun = math.max(e.stun, time)
end

-- The closest living enemy to (x, y) within range, skipping `skip` (a set)
function enemies.nearest(x, y, range, skip)
  local best, bestDist = nil, range
  for _, e in ipairs(list) do
    if not e.dead and not (skip and skip[e]) then
      local cx, cy = center(e)
      local d = math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2)
      if d < bestDist then
        best, bestDist = e, d
      end
    end
  end
  return best
end

-- Shock Rounds: lightning arcs from a hit enemy to up to two others nearby
function enemies.chain(from, damage, fx)
  local skip = { [from] = true }
  local ax, ay = center(from)
  for _ = 1, 2 do
    local target = enemies.nearest(ax, ay, 48, skip)
    if not target then
      return
    end
    skip[target] = true
    local bx, by = center(target)
    for i = 0, 8 do
      local t = i / 8
      effects.particle(ax + (bx - ax) * t + (love.math.random() - 0.5) * 3, ay + (by - ay) * t + (love.math.random() - 0.5) * 3, 0, 0, 0.12, { 0.65, 0.75, 1 }, 0, true)
    end
    enemies.damage(target, math.max(1, math.floor(damage * 0.5 + 0.5)), 0, 0, 0, false, fx)
    ax, ay = bx, by
  end
end

-- Singularity Rounds: drags enemies within radius toward (x, y)
function enemies.pull(x, y, radius, speed)
  for _, e in ipairs(list) do
    if not e.dead and e.def.knockback > 0 then
      local cx, cy = center(e)
      local dx, dy = x - cx, y - cy
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist < radius and dist > 1 then
        local k = speed * (1 - 0.5 * dist / radius)
        e.body.vx = e.body.vx * 0.3 + dx / dist * k
        e.body.vy = e.body.vy * 0.3 + dy / dist * k - 20
        e.stun = math.max(e.stun, 0.25)
      end
    end
  end
end

-- A few purple motes drift up from every monster and trail away (drawn behind the sprite)
local AURA = { 0.62, 0.36, 0.95 }

local function updateMotes(e, dt)
  local b = e.body
  e.motes = e.motes or {}
  if #e.motes < 6 and love.math.random() < dt * 9 then
    e.motes[#e.motes + 1] = {
      x = b.x - 1 + love.math.random() * (b.w + 2),
      y = b.y - 1 + love.math.random() * (b.h + 2),
      vx = (love.math.random() - 0.5) * 8,
      vy = -4 - love.math.random() * 8,
      life = 0.8,
    }
  end
  for i = #e.motes, 1, -1 do
    local m = e.motes[i]
    m.life = m.life - dt
    m.x, m.y = m.x + m.vx * dt, m.y + m.vy * dt
    if m.life <= 0 then
      table.remove(e.motes, i)
    end
  end
end

local function drawAura(e)
  -- A very faint halo behind the sprite
  local b = e.body
  local a = (e.state == "sleep" and 0.013 or 0.022) * (0.85 + 0.15 * math.sin(love.timer.getTime() * 3 + e.phase))
  love.graphics.setColor(AURA[1], AURA[2], AURA[3], a)
  love.graphics.rectangle("fill", b.x - 1, b.y, b.w + 2, b.h)
  love.graphics.rectangle("fill", b.x, b.y - 1, b.w, b.h + 2)
  for _, m in ipairs(e.motes or {}) do
    love.graphics.setColor(AURA[1], AURA[2], AURA[3], 0.7 * m.life / 0.8)
    love.graphics.rectangle("fill", math.floor(m.x), math.floor(m.y), 1, 1)
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

-- Poison: a damage tick every half second
local function updatePoison(e, dt)
  local poison = e.poisoned
  if not poison then
    return
  end
  poison.left = poison.left - dt
  poison.tick = poison.tick - dt
  if love.math.random() < 0.3 then
    local cx = center(e)
    effects.particle(cx + (love.math.random() - 0.5) * e.body.w, e.body.y + love.math.random() * e.body.h, 0, -14, 0.4, { 0.45, 0.85, 0.30 }, -10, true)
  end
  if poison.tick <= 0 then
    poison.tick = 0.5
    enemies.damage(e, math.max(1, math.floor(poison.dps * 0.5 + 0.5)))
  end
  if poison.left <= 0 then
    e.poisoned = nil
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
function enemies.hit(thing, amount, dx, dy, force, crit, fx)
  if thing.isGlob then
    thing.dead = true
    for _ = 1, 6 do
      effects.particle(thing.x, thing.y, (love.math.random() - 0.5) * 90, -love.math.random() * 60, 0.4, { 0.55, 0.95, 0.35 }, 300, true)
    end
  else
    enemies.damage(thing, amount, dx, dy, force, crit, fx)
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

  e.strikeT = math.max(0, (e.strikeT or 0) - dt)
  local want = 0
  if e.stun > 0 then
    want = nil -- knocked back: no control
    e.windT = nil
  elseif e.state == "chase" then
    want = px < cx - 2 and -1 or (px > cx + 2 and 1 or 0)
    e.facing = want ~= 0 and want or e.facing
    if e.windT then
      -- Rearing back: stands its ground, then flings itself and its arms forward
      want = 0
      e.windT = e.windT - dt
      if e.windT <= 0 then
        e.windT = nil
        e.strikeT = def.strike
        b.vx = e.facing * def.lungeSpeed
        b.vy = -def.lungeLift
        e.grounded = false
        audio.play("hit", 0.5, 0.6)
      end
    elseif e.grounded and e.cooldown <= 0 and dist < def.lungeRange and math.abs(py - cy) < 24 then
      e.windT = def.windup
      e.cooldown = def.lungeCooldown + def.windup
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
  e.phase = e.phase + dt * (math.abs(b.vx) / 7 + 0.8)
  -- Dragging hands kick up a little dust
  if e.grounded and math.abs(b.vx) > 8 and love.math.random() < dt * 8 then
    effects.particle(cx - e.facing * (5 + love.math.random() * 3), b.y + b.h - 1, -e.facing * 6, -8 - love.math.random() * 10, 0.4, { 0.42, 0.40, 0.40 }, 60)
  end
end

-- Bat: hangs asleep until it sees the hunter and flutters in. Once it has a
-- clear line of sight and is close enough it locks on: it hangs still and
-- screeches, then dives at where the hunter stood in a dead straight line.
-- A bite sends it flying off; a miss leaves it recovering for a moment.
local function updateBat(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  e.attackCd = math.max(0, (e.attackCd or 0) - dt)
  local state = e.state
  e.phase = e.phase + dt * (state == "lock" and 7 or (state == "charge" and 3 or 18))

  if state == "sleep" then
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

  local collide = collider(e, world)
  local tx, ty = 0, 0
  local d = math.max(1, dist)
  local steer = true -- false while the dive fixes its own velocity
  if e.state == "chase" then
    tx, ty = (px - cx) / d * def.speed, (py - 4 - cy) / d * def.speed
    if e.seesPlayer and dist < def.chargeRange and e.attackCd <= 0 and e.stun <= 0 then
      e.state = "lock"
      e.timer = def.lockTime
      audio.play("bat_screech")
    end
  elseif e.state == "lock" then
    -- Hangs in the air, wings wide, eyes on the hunter
    e.timer = e.timer - dt
    e.facing = px >= cx and 1 or -1
    if not e.seesPlayer then
      e.state = "chase" -- lost sight: no dive
      e.attackCd = 0.4
    elseif e.timer <= 0 then
      e.state = "charge"
      e.timer = def.chargeTime
      b.vx, b.vy = (px - cx) / d * def.chargeSpeed, (py - 2 - cy) / d * def.chargeSpeed
    end
  elseif e.state == "charge" then
    steer = false
    e.timer = e.timer - dt
    if love.math.random() < dt * 40 then
      effects.particle(cx, cy, -b.vx * 0.05, -b.vy * 0.05, 0.25, { 0.35, 0.22, 0.45 }, 0)
    end
    if e.timer <= 0 then
      e.state = "recover"
      e.timer = 0.7
      e.attackCd = def.chargeCooldown
    end
  elseif e.state == "recover" then
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.state = "chase"
    end
  elseif e.state == "retreat" then
    tx, ty = -(px - cx) / d * def.speed, -def.speed * 0.8
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.state = "chase"
    end
  end
  if steer then
    -- Fluttery: a wobble on top of the steering (none while hanging to screech)
    if e.state ~= "lock" then
      ty = ty + math.sin(e.phase * 0.35) * 40
    end
    if e.stun <= 0 then
      local step = (e.state == "lock" and 700 or def.accel) * dt
      b.vx = b.vx < tx and math.min(b.vx + step, tx) or math.max(b.vx - step, tx)
      b.vy = b.vy < ty and math.min(b.vy + step, ty) or math.max(b.vy - step, ty)
    end
    if tx ~= 0 then
      e.facing = tx > 0 and 1 or -1
    end
  else
    e.facing = b.vx >= 0 and 1 or -1
  end
  local hitWall = false
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.5
    hitWall = true
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.5
    hitWall = true
  end
  if hitWall and e.state == "charge" then
    -- Smacked into rock: dazed for a moment
    e.state = "recover"
    e.timer = 1.0
    e.attackCd = def.chargeCooldown
    e.stun = 0.3
  end
end

-- Spits an acid glob in an arc that lands on (tx, ty)
local function spit(e, tx, ty)
  local def = e.def
  local cx, cy = center(e)
  cy = cy + 3
  local dx, dy = tx - cx, ty - cy
  local t = math.max(0.35, math.sqrt(dx * dx + dy * dy) / def.globSpeed)
  e.spitT = 0.3
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
        e.stagger = math.max(0, (e.stagger or 0) - dt)
        e.spitT = math.max(0, (e.spitT or 0) - dt)
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
        if e.slow and e.slow > 0 then
          e.slow = e.slow - dt
        end
        if e.acid and e.acid > 0 then
          e.acid = e.acid - dt
        end
        UPDATE[e.kind](e, (e.slow and e.slow > 0) and dt * 0.45 or dt, world, player, px, py)
        propImpacts(e, dt)
        updateBurn(e, dt)
        updatePoison(e, dt)
        updateMotes(e, dt)
        -- Touching the hunter hurts him
        local b = e.body
        if not player.dead and e.state ~= "sleep" and overlaps(b.x, b.y, b.w, b.h, pb.x, pb.y, pb.w, pb.h) then
          if e.def.damage and player:hurt(e.def.damage, center(e)) and e.kind == "bat" then
            e.state = "retreat"
            e.timer = e.def.retreat
            e.attackCd = e.def.chargeCooldown
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
  skin = { 0.62, 0.64, 0.66 },
  skinDark = { 0.40, 0.42, 0.46 },
  skinLight = { 0.76, 0.78, 0.80 },
  rags = { 0.27, 0.28, 0.32 },
  ragsDark = { 0.17, 0.18, 0.21 },
  eye = { 0.78, 0.95, 1.0 },
}

-- A line of single pixels from (x0, y0) to (x1, y1)
local function limb(x0, y0, x1, y1)
  local n = math.max(1, math.ceil(math.max(math.abs(x1 - x0), math.abs(y1 - y0))))
  for i = 0, n do
    local t = i / n
    px(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
  end
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

-- Where everything on the ghoul is this frame, shared by the body and its
-- glowing eyes. It shambles hunched over with its arms trailing behind it,
-- rears back to attack, and flings both arms forward as it lunges.
local function ghoulPose(e)
  local b, f = e.body, e.facing
  local def = e.def
  local t = e.phase
  local moving = e.grounded and math.abs(b.vx) > 8
  local wind = e.windT and (1 - e.windT / def.windup) or 0 -- 0 -> 1 while rearing back
  local strike = (e.strikeT or 0) / def.strike -- 1 -> 0 after the lunge
  local mid = b.x + b.w / 2
  local pose = { f = f, wind = wind, strike = strike, moving = moving }
  local bob = moving and math.abs(math.sin(t)) * 1.0 or math.sin(t * 0.5) * 0.4
  local lean = 2.2 - 3.2 * wind + 2.2 * strike
  pose.pelvis = { mid - f * 1, b.y + 11 + bob * 0.3 }
  pose.shoulder = { mid + f * lean, b.y + 6.5 + bob * 0.6 + wind * 1.2 }
  pose.head = { pose.shoulder[1] + f * (2 + strike - wind), pose.shoulder[2] - 3 + math.sin(t * 0.7) * 0.5 + wind * 0.5 }
  -- Feet shuffle along the ground, lifting only a little
  local ground = b.y + b.h - 1
  pose.feet = {}
  for i = 1, 2 do
    local ph = t + (i - 1) * math.pi
    local swing = moving and math.sin(ph) * 2.6 or (i == 1 and 1.2 or -1.0)
    local lift = (moving and math.cos(ph) > 0) and math.cos(ph) * 1.8 or 0
    pose.feet[i] = { mid + f * swing, ground - lift }
  end
  -- Arms: trailing and dragging behind; raised behind the head when rearing
  -- back; thrown forward in the strike
  local sx, sy = pose.shoulder[1], pose.shoulder[2] + 1
  pose.hands = {}
  for i = 1, 2 do
    local drag = (moving and math.sin(t + i) * 1.2 or 0)
    local rest = { sx - f * (5 + i * 1.6 + drag), ground - (i - 1) }
    local back = { sx - f * (4 + wind * 2 + i), sy - 3 - wind * 3 + i * 0.6 }
    local fwd = { sx + f * (4 + 6 * (1 - (1 - strike) ^ 2) + i), sy + 0.5 + i * 1.2 - strike }
    local h = { lerp(rest[1], back[1], wind), lerp(rest[2], back[2], wind) }
    h = { lerp(h[1], fwd[1], strike), lerp(h[2], fwd[2], strike) }
    pose.hands[i] = h
  end
  return pose
end

-- A hunched, grey, ghost-pale scavenger that drags its long arms behind it
local function drawGhoul(e)
  local pose = ghoulPose(e)
  local f = pose.f
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local sx, sy = pose.shoulder[1], pose.shoulder[2]
  local hx, hy = pose.head[1], pose.head[2]
  local pelvis = pose.pelvis

  -- Back arm, then legs, behind the torso
  color(GHOUL.skinDark)
  local backHand = pose.hands[2]
  limb(sx - f, sy + 1, (sx + backHand[1]) / 2 - f, (sy + backHand[2]) / 2 + 2)
  limb((sx + backHand[1]) / 2 - f, (sy + backHand[2]) / 2 + 2, backHand[1], backHand[2])
  for i = 2, 1, -1 do
    local foot = pose.feet[i]
    color(i == 1 and GHOUL.skin or GHOUL.skinDark)
    local kneeX, kneeY = (pelvis[1] + foot[1]) / 2 + f * 1.5, (pelvis[2] + foot[2]) / 2
    limb(pelvis[1], pelvis[2], kneeX, kneeY)
    limb(kneeX, kneeY, foot[1], foot[2])
    px(foot[1], foot[2], 1, 1)
    px(foot[1] + f, foot[2])
  end

  -- Torso in tattered rags: a thick line from hips to shoulders, ragged hem
  color(GHOUL.rags)
  limb(pelvis[1] - 1, pelvis[2], sx - 1, sy + 1)
  limb(pelvis[1], pelvis[2], sx, sy + 1)
  limb(pelvis[1] + 1, pelvis[2], sx + 1, sy + 1)
  color(GHOUL.ragsDark)
  for i = -1, 1 do
    px(pelvis[1] + i, pelvis[2] + 1 + ((i + math.floor(e.phase * 0.5)) % 2))
  end
  limb(pelvis[1] + f, pelvis[2], sx + f, sy + 2)
  -- Bare shoulders and the hump of the spine, ribs showing
  color(GHOUL.skin)
  px(sx - f * 2, sy - 1, 2, 2)
  px(sx - 1, sy, 3, 1)
  color(GHOUL.skinLight)
  px(sx - f * 2, sy - 1)
  color(GHOUL.skinDark)
  px(sx + f, sy + 2)
  px(sx, sy + 3)

  -- Head, thrust forward and low; the jaw hangs open when it attacks
  color(GHOUL.skin)
  px(hx - 2, hy, 4, 3)
  color(GHOUL.skinLight)
  px(hx - 2, hy, 4, 1)
  color(GHOUL.ragsDark)
  px(hx + (f > 0 and 0 or -2), hy + 1, 2, 1) -- hollow eye sockets
  local open = math.max(pose.wind, pose.strike)
  px(hx - 1 + (f > 0 and 1 or 0), hy + 3, 2, open > 0.3 and 2 or 1)
  color(GHOUL.skinDark)
  px(hx - 2, hy + 2)

  -- Front arm over the torso
  color(GHOUL.skin)
  local hand = pose.hands[1]
  local ex, ey = (sx + hand[1]) / 2 - f * 0.5, (sy + hand[2]) / 2 + 2 * (1 - pose.strike)
  limb(sx, sy + 1, ex, ey)
  limb(ex, ey, hand[1], hand[2])
  -- Long fingers
  color(GHOUL.skinLight)
  px(hand[1] + (pose.strike > 0.2 and f or -f), hand[2])
  px(hand[1] + (pose.strike > 0.2 and f or -f), hand[2] + 1)
end

local function drawGhoulEyes(e)
  local pose = ghoulPose(e)
  local hx, hy = pose.head[1], pose.head[2]
  local glare = math.max(pose.wind, pose.strike)
  love.graphics.setColor(GHOUL.eye[1], GHOUL.eye[2], GHOUL.eye[3], 0.7 + 0.3 * glare)
  px(hx + (pose.f > 0 and 0 or -2), hy + 1, glare > 0.3 and 2 or 1, 1)
end

-- A ragged bat: furry body, ears, and two wings with finger bones and a
-- membrane. Hangs folded when asleep, spreads and shakes while locking on,
-- and folds back into a dart for the dive.
local BAT = {
  fur = { 0.20, 0.15, 0.20 },
  furLight = { 0.32, 0.25, 0.32 },
  wing = { 0.14, 0.10, 0.15 },
  membrane = { 0.26, 0.17, 0.24 },
}

local function drawBat(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local x, y = b.x, b.y
  local mid = x + b.w / 2
  if e.state == "sleep" then
    -- Hanging upside down, wings wrapped around like a cloak
    color(BAT.wing)
    px(mid - 3, y + 1, 6, 5)
    px(mid - 2, y + 6)
    px(mid + 1, y + 6)
    color(BAT.membrane)
    px(mid - 2, y + 2, 1, 3)
    px(mid + 1, y + 2, 1, 3)
    color(BAT.fur)
    px(mid - 1, y, 2, 3)
    px(mid - 2, y - 1)
    px(mid + 1, y - 1)
    return
  end
  local lock = e.state == "lock"
  local dive = e.state == "charge"
  local shake = lock and (math.sin(love.timer.getTime() * 70) * 0.8) or 0
  local flap = math.sin(e.phase)
  local f = e.facing
  local cy = y + 3.5
  mid = mid + shake
  for side = -1, 1, 2 do
    -- Wing: shoulder, elbow, tip; the tip sweeps with the flap (wings wide
    -- and nearly still while locking on, swept back in the dive)
    local sh = { mid + side * 1.5, cy - 0.5 }
    local el, tip
    if dive then
      el = { mid + side * 3, cy + 1 }
      tip = { mid + side * 3.5 - f * 0, cy + 4 }
    elseif lock then
      el = { mid + side * 4.5, cy - 1.5 + flap * 0.5 }
      tip = { mid + side * 8, cy - 0.5 + flap * 0.8 }
    else
      el = { mid + side * 4, cy - 1 - flap * 1.5 }
      tip = { mid + side * 7.5, cy + 0.5 + flap * 3.5 }
    end
    -- membrane first, then the arm and finger bones over it
    color(BAT.membrane)
    limb(tip[1], tip[2], mid + side * 1.5, cy + 2.5)
    limb(el[1], el[2] + 1, mid + side * 1, cy + 2.5)
    limb(tip[1] - side, tip[2], el[1], el[2] + 1)
    color(BAT.wing)
    limb(sh[1], sh[2], el[1], el[2])
    limb(el[1], el[2], tip[1], tip[2])
    px(tip[1], tip[2] + 1)
  end
  -- Body and head
  color(BAT.fur)
  px(mid - 1.5, cy - 1.5, 3, 4)
  color(BAT.furLight)
  px(mid - 1, cy - 1, 1, 2)
  color(BAT.fur)
  px(mid - 1.5, cy - 3.5, 3, 2)
  px(mid - 2, cy - 4.5) -- ears
  px(mid + 1, cy - 4.5)
  -- Open mouth with fangs while screeching and diving
  if lock or dive then
    love.graphics.setColor(0.55, 0.08, 0.1)
    px(mid - 1, cy - 2, 2, 1)
    love.graphics.setColor(0.92, 0.9, 0.85)
    px(mid - 1, cy - 1)
    px(mid, cy - 1)
  end
end

local function drawBatEyes(e)
  local b = e.body
  if e.state == "sleep" then
    return
  end
  local mid = b.x + b.w / 2
  local cy = b.y + 3.5
  local angry = e.state == "lock" or e.state == "charge"
  if angry then
    mid = mid + (e.state == "lock" and math.sin(love.timer.getTime() * 70) * 0.8 or 0)
    love.graphics.setColor(1, 0.15, 0.1)
    px(mid - 2, cy - 3, 2, 1)
    px(mid, cy - 3, 2, 1)
  else
    love.graphics.setColor(1, 0.35, 0.25)
    px(mid - 1, cy - 3)
    px(mid + 1, cy - 3)
  end
end

-- A fleshy sac hanging from the rock by twitching tendrils. It watches the
-- hunter with a single eye, swells and throbs as it winds up, its throat
-- glowing brighter, and shrivels for a moment after it spits.
local SPITTER = {
  flesh = { 0.44, 0.33, 0.33 },
  fleshLight = { 0.58, 0.45, 0.43 },
  fleshDark = { 0.30, 0.22, 0.24 },
  vein = { 0.36, 0.20, 0.24 },
}

-- 0 -> 1 as it winds up to spit; and how squeezed it is just after
local function spitterState(e)
  local prog = e.windup and (1 - e.windup / e.def.windup) or 0
  local squeeze = (e.spitT or 0) / 0.3
  return prog, squeeze
end

local function drawSpitter(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local prog, squeeze = spitterState(e)
  local t = love.timer.getTime() + e.phase
  local x, y = b.x, b.y
  local mid = x + 5
  -- Tendrils anchoring it to the rock, each twitching on its own beat
  color(SPITTER.fleshDark)
  for i, tx in ipairs({ 1.5, 4.5, 7.5 }) do
    local sway = math.sin(t * 3 + i * 2) * (0.6 + prog)
    px(x + tx + sway * 0.5, y, 1, 2)
    px(x + tx + sway, y + 2, 1, 1)
  end
  -- The sac: swells outward as it winds up (and throbs), contracts after a spit
  local throb = prog > 0 and math.sin(t * 22) * 0.4 or math.sin(t * 2) * 0.25
  local grow = prog * 1.4 + throb - squeeze * 1.3
  local half = 4 + grow
  local h = 5 + grow * 0.7
  color(SPITTER.flesh)
  px(mid - half, y + 3, half * 2, h)
  px(mid - half + 1, y + 2, half * 2 - 2, 1)
  px(mid - half + 1, y + 3 + h, half * 2 - 2, 1)
  color(SPITTER.fleshDark)
  px(mid - half + 2, y + 3 + h, half * 2 - 4, 1)
  px(mid - half, y + 5, 1, 2)
  -- Veins and a highlight
  color(SPITTER.vein)
  px(mid + 1, y + 3, 1, 3)
  px(mid + 2, y + 5, 2, 1)
  px(mid - 3, y + 5, 2, 1)
  color(SPITTER.fleshLight)
  px(mid - half + 1, y + 3, 3, 1)
  px(mid - half + 1, y + 4, 1, 2)
  -- A pale eye on the side facing the hunter
  color({ 0.78, 0.82, 0.70 })
  px(mid + e.facing * 2 - 1, y + 4, 2, 2)
  color({ 0.1, 0.08, 0.08 })
  px(mid + e.facing * 2 - (e.facing > 0 and 0 or 1), y + 5, 1, 1)
  -- The throat at the bottom: a dark mouth that gapes as it winds up
  color({ 0.12, 0.08, 0.1 })
  px(mid - 1 - prog, y + 3 + h - 1, 2 + prog * 2, 1)
  px(mid - 1, y + 3 + h, 2, 1)
end

local function drawSpitterGlow(e)
  local b = e.body
  local prog, squeeze = spitterState(e)
  local h = 5 + prog * 1.4 * 0.7
  local mid = b.x + 5
  -- Acid brewing in the throat: a dim glow that blazes before the spit
  local glow = 0.25 + prog * 0.75
  love.graphics.setColor(0.55 * glow + 0.1, 1 * glow, 0.35 * glow)
  px(mid - 1 - prog, b.y + 3 + h - 1, 2 + prog * 2, 1)
  if prog > 0.5 then
    px(mid - 1, b.y + 3 + h, 2, 1)
  end
  if squeeze > 0 then
    love.graphics.setColor(0.6, 1, 0.4, squeeze)
    px(mid - 2, b.y + 3 + h + 1, 4, 1)
  end
end

local DRAW = { ghoul = drawGhoul, bat = drawBat, spitter = drawSpitter }
local GLOW = { ghoul = drawGhoulEyes, bat = drawBatEyes, spitter = drawSpitterGlow }

-- How far a freshly struck monster's sprite is thrown back, in pixels
local function staggerOffset(e)
  if not e.stagger or e.stagger <= 0 then
    return 0
  end
  return math.floor((e.hitDir or 1) * e.stagger / 0.2 * 1.6 + 0.5)
end

local function onScreen(e, view)
  local b = e.body
  return b.x + b.w > view.x - 8 and b.x < view.x + view.w + 8 and b.y + b.h > view.y - 8 and b.y < view.y + view.h + 8
end

-- view: { x, y, w, h } in world pixels
function enemies.draw(view)
  for _, e in ipairs(list) do
    if onScreen(e, view) then
      local off = staggerOffset(e)
      love.graphics.push()
      love.graphics.translate(off, 0)
      drawAura(e)
      DRAW[e.kind](e)
      -- Status tints: frost, venom and acid wash over the sprite
      local b = e.body
      if e.slow and e.slow > 0 then
        love.graphics.setColor(0.55, 0.85, 1, 0.35)
        love.graphics.rectangle("fill", math.floor(b.x), math.floor(b.y), b.w, b.h)
      end
      if e.poisoned then
        love.graphics.setColor(0.4, 0.9, 0.3, 0.25)
        love.graphics.rectangle("fill", math.floor(b.x), math.floor(b.y), b.w, b.h)
      end
      if e.acid and e.acid > 0 then
        love.graphics.setColor(0.8, 1, 0.2, 0.25)
        love.graphics.rectangle("fill", math.floor(b.x), math.floor(b.y), b.w, b.h)
      end
      love.graphics.pop()
    end
  end
end

-- After the lighting: eyes, glowing mouths and acid globs
function enemies.drawEmissive(view)
  for _, e in ipairs(list) do
    if onScreen(e, view) then
      love.graphics.push()
      love.graphics.translate(staggerOffset(e), 0)
      GLOW[e.kind](e)
      love.graphics.pop()
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
    if onScreen(e, view) then
      local cx, cy = center(e)
      -- The purple back-light, at a tenth of its old strength
      lighting.add(cx, cy, 13, AURA[1], AURA[2], AURA[3], e.state == "sleep" and 0.03 or 0.045)
      if e.kind == "spitter" then
        lighting.add(cx, cy + 4, e.windup and 30 or 16, 0.5, 1, 0.35, 0.5)
      end
    end
  end
end

return enemies
