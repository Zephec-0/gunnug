-- Monsters of the catacombs (design doc §8): ghouls that walk and lunge,
-- cave bats that hang from ceilings and swoop, spitters that cling to
-- ceilings and lob acid globs, mire hoppers that leap, bloaters that drift
-- leaking poison gas, and cinder wisps that leave fire. Each area also has one
-- boss (a giant ghoul, hopper or bloater). They are placed when an area is generated and
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
local destruction = require("src.destruction")
local effects = require("src.effects")
local fluids = require("src.fluids")
local hud = require("src.hud")
local perks = require("src.perks")
local physics = require("src.physics")
local materials = require("src.materials")
local pickups = require("src.pickups")
local props = require("src.props")

local enemies = {}

-- Tuning. Speeds in px/s, damage in HP, times in seconds.
enemies.defs = {
  ghoul = {
    ground = true, -- stands on the floor at its spawn point (the others hang or float)
    w = 12,
    h = 19,
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
    weight = 3.2, -- how much objects' momentum moves it (speed gained = momentum / weight)
    clawDig = 4.5, -- its lunge rakes a bite this big out of the terrain in front...
    clawPower = 2, -- ...at this digging power (earth always gives, rock half the time)
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
    anchored = true, -- clings to its rock: objects don't knock it about
  },
  -- The DPS dummy in every shop: a straw training dummy on a stand that never
  -- dies, moves or fights back. It is an "enemy" so every effect lands on it
  -- exactly as on a monster (burning, poison, shock arcs, blasts, acid, crits),
  -- and it measures the damage per second (see recordDps).
  dummy = {
    ground = true,
    w = 12,
    h = 26,
    hp = 1000,
    knockback = 0,
    weight = 99,
    anchored = true,
    dummy = true,
    gold = { 0, 0 },
  },
}

-- Mire hopper: a squat marsh toad that crouches, then leaps at the hunter
enemies.defs.hopper = {
  ground = true,
  w = 12,
  h = 9,
  hp = 14,
  leapSpeed = 105,
  leapLift = 235,
  leapCooldown = 1.0,
  windup = 0.3,
  sight = 250,
  forget = 420,
  damage = 9,
  gold = { 2, 5 },
  knockback = 0.6,
  weight = 1.2,
}

-- Bloater: a gas bag that drifts toward the hunter leaking poison, and bursts
-- into a cloud of it (a lit one if it dies in or near fire)
enemies.defs.bloater = {
  w = 14,
  h = 14,
  hp = 26,
  speed = 24,
  accel = 70,
  sight = 260,
  forget = 420,
  damage = 6,
  gold = { 3, 6 },
  knockback = 0.5,
  weight = 0.8,
}

-- Swarm bat: one of a colony. Tiny health, a weak bite, quick and erratic,
-- and the whole swarm wakes together and flocks (see flock).
enemies.defs.swarmbat = {
  w = 10,
  h = 7,
  hp = 5,
  speed = 96,
  accel = 380,
  sight = 270,
  forget = 540,
  damage = 3,
  gold = { 0, 1 },
  retreat = 0.5,
  chargeCooldown = 1.0,
  knockback = 0.9,
  weight = 0.5,
  deathKind = "bat",
}

-- Cinder wisp: a flitting spark that trails fire and lights any gas it meets
enemies.defs.wisp = {
  w = 8,
  h = 8,
  hp = 10,
  speed = 58,
  accel = 260,
  sight = 270,
  forget = 480,
  damage = 7,
  gold = { 3, 7 },
  knockback = 0.3,
  weight = 0.3,
  fireproof = true,
}

-- Bosses: one per area, drawn as bigger versions of the monsters they grew
-- from (spriteW/H is the base sprite, scaled up). Very tough, hard to shove
-- about, and they drop a lot of gold and loot.
local function giant(base, o)
  local d = {}
  for k, v in pairs(enemies.defs[base]) do
    d[k] = v
  end
  for k, v in pairs(o) do
    d[k] = v
  end
  d.boss, d.anchored, d.scale = true, true, o.scale or 2
  d.spriteW, d.spriteH = enemies.defs[base].w, enemies.defs[base].h
  d.deathKind = base
  return d
end
enemies.defs.warden = giant("ghoul", {
  name = "The Ashen Warden",
  w = 24, h = 38, hp = 500, speed = 50, jump = 300,
  lungeRange = 64, lungeSpeed = 170, lungeLift = 170, lungeCooldown = 1.6,
  windup = 0.55, strike = 0.5, sight = 380, forget = 800,
  damage = 22, knockback = 0.06, gold = { 110, 150 }, pushForce = 600, weight = 14,
})
enemies.defs.matron = giant("hopper", {
  name = "The Mire Matron",
  w = 24, h = 18, hp = 650, leapSpeed = 150, leapLift = 290, leapCooldown = 1.7, windup = 0.55,
  sight = 420, forget = 800, damage = 20, knockback = 0.06, gold = { 110, 150 }, weight = 14,
  kids = true, -- calls hoppers
})
enemies.defs.behemoth = giant("bloater", {
  name = "The Gas Behemoth",
  w = 28, h = 28, hp = 800, speed = 20, accel = 50, sight = 440, forget = 800,
  damage = 16, knockback = 0.05, gold = { 110, 150 }, weight = 14,
  puff = true, -- constantly pouring out gas
})

-- The Dread Bat: a bat three times the size. It needs no line of sight: once
-- the hunter is within range it screeches, then dives straight at him through
-- anything in the way, tearing a tunnel through rock and dirt (only bedrock
-- and the shop's walls stop it).
enemies.defs.dreadbat = giant("bat", {
  name = "The Dread Bat",
  scale = 3,
  w = 30, h = 21, hp = 600, speed = 70, accel = 220,
  sight = 560, forget = 1000, damage = 18, retreat = false,
  chargeRange = 420, lockTime = 0.85, chargeSpeed = 250, chargeTime = 1.5, chargeCooldown = 2.4,
  knockback = 0.05, gold = { 110, 150 }, weight = 14,
  digRadius = 17, -- the tunnel it bores
})

-- The Sulfur Queen: the boss of the Sulfur Vents, in the arena at the end of
-- the area. A bloater the size of a house, crowned, that fills the arena with
-- poison gas, lobs gas volleys, and calls bloaters and wisps. Fire ruins her:
-- she is immune to fire, and flies through rock, ledges and walls alike inside
-- her arena (she is only held to it), so the hunter has to out-fight her gas.
enemies.defs.queen = giant("bloater", {
  name = "The Sulfur Queen",
  scale = 6,
  w = 84, h = 84, hp = 1400, speed = 78, accel = 260,
  sight = 560, forget = 4000, damage = 24,
  knockback = 0.02, gold = { 200, 260 }, weight = 30,
  knockMul = 0.1, -- 90% less shove from bullets, kicks, blasts and singularities
  fireproof = true,
  puff = true,
  globSpeed = 210, globGravity = 60, globDamage = 14,
  holdDist = 60, -- she keeps this far from the hunter (plus her own size); dashes in when further
  splitDepth = 4, -- below 33% health she splits in two, down to this many splits in a line
  splitDamage = 0.75, -- each split deals this much of the damage of the one before
})

-- Queen remnant sizes by generation: whole-number sprite scales (the sac is 14 px)
local QUEEN_SCALES = { 6, 5, 4, 3, 2 }

-- Each area's monsters are tougher: damage rises with the area (toughness,
-- which scales health and gold, is set where they are placed)
local DAMAGE_PER_AREA = 0.35

-- The DPS dummy's meter: a session starts with the first hit and ends once
-- DPS_IDLE seconds pass without one; the reading then freezes until the next hit
local DPS_IDLE = 2

local ITEM_DROP_CHANCE = 0.1 -- chance a dying monster drops an ammo type or attachment
local ACTIVE_RANGE = 520 -- enemies further than this from the hunter are frozen
local GLOB_LIFE = 4

local list = {}
local globs = {}
local clock = 0 -- game time (stops while paused), for the DPS meter

-- Set by src.game: called as onKill(enemy, fx) when an enemy dies, with the
-- effects of the bullet that last hit it (nil for kicks and explosions)
enemies.onKill = nil

function enemies.clear()
  list, globs = {}, {}
end

function enemies.count()
  return #list
end

-- Every enemy (for src.fluids and tests)
function enemies.all()
  return list
end

-- Spawns an enemy. Ghouls stand on the ground at (x, groundY); bats and
-- spitters hang from the ceiling at (x, ceilingY). toughness >= 1 scales HP.
function enemies.spawn(kind, x, y, toughness, level, swarm)
  local def = assert(enemies.defs[kind], "unknown enemy: " .. tostring(kind))
  local top = def.ground and y - def.h or y
  local e = {
    kind = kind,
    def = def,
    body = Body.new(math.floor(x - def.w / 2), math.floor(top), def.w, def.h),
    hp = math.floor(def.hp * (toughness or 1) + 0.5),
    maxHp = math.floor(def.hp * (toughness or 1) + 0.5),
    toughness = toughness or 1,
    state = def.dummy and "still" or def.ground and "idle" or "sleep",
    level = level or 1,
    swarm = swarm, -- the colony this monster belongs to: { members = {...}, awake }
    dmgMul = 1 + ((level or 1) - 1) * DAMAGE_PER_AREA,
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
  if swarm then
    swarm.members = swarm.members or {}
    swarm.members[#swarm.members + 1] = e
  end
  return e
end

local function center(e)
  local b = e.body
  return b.x + b.w / 2, b.y + b.h / 2
end

local recordDps -- (defined below)

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
  local share = e.goldShare or 1 -- a Queen remnant's cut of the Queen's gold
  local gold = love.math.random(e.def.gold[1], e.def.gold[2])
  local greed = e.lastFx and e.lastFx.greed or 0
  pickups.dropGold(cx, cy, math.floor(gold * e.toughness * (1 + greed) * share + 0.5))
  pickups.maybeDropItem(cx, cy, ITEM_DROP_CHANCE * perks.prod("loot") * share)
  if enemies.onKill then
    enemies.onKill(e, e.lastFx)
  end
  -- (Monsters never drop weapons: those come from chests and the shop.)
  local r = love.math.random
  local kind = e.def.deathKind or e.kind
  -- A split boss only falls once every remnant is dead
  local lastOfBoss = true
  if e.group then
    e.group.alive = e.group.alive - 1
    lastOfBoss = e.group.alive <= 0
  end
  if e.def.boss and not lastOfBoss then
    effects.explosion(cx, cy, 6 + (e.body.w / 84) * 8)
  elseif e.def.boss then
    -- A boss pays out: a lot more gold, several items and a weapon
    local amount = math.floor(love.math.random(e.def.gold[1], e.def.gold[2]) * e.toughness * 0.5)
    pickups.dropGold(cx, cy, amount)
    pickups.dropGold(cx, cy, amount)
    for _ = 1, 4 do
      pickups.maybeDropItem(cx + (r() - 0.5) * 10, cy, 1)
    end
    pickups.maybeDropWeapon(cx, cy, 1, 0.5)
    effects.popup(cx, e.body.y - 10, "SLAIN", { 0.95, 0.97, 1 })
    if enemies.onBossKilled then
      enemies.onBossKilled(e)
    end
    effects.explosion(cx, cy, 18)
  end
  if kind == "ghoul" then
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
  elseif kind == "hopper" then
    -- Bursts into green slime and bits of toad
    for _ = 1, 12 do
      local a = r() * math.pi * 2
      effects.particle(cx, cy, math.cos(a) * (20 + r() * 60), math.sin(a) * (20 + r() * 60) - 30, 0.6 + r() * 0.4, { 0.26, 0.5, 0.34 }, 300, true)
    end
    for _ = 1, 3 do
      effects.chunk(cx + (r() - 0.5) * 6, cy, (r() - 0.5) * 60, -30 - r() * 40, 3, 2, { 0.22, 0.38, 0.30 }, 3)
    end
  elseif kind == "bloater" then
    -- Bursts: the poison leaves it as a cloud, and burning gas goes up in flames
    local big = e.def.boss
    fluids.addGas(cx, cy, big and 1 or 0.9, big and 44 * (e.body.w / e.def.w) or 18)
    for _ = 1, 10 do
      effects.particle(cx, cy, (r() - 0.5) * 80, (r() - 0.5) * 60, 0.6, { 0.72, 0.85, 0.3 }, 100, true)
    end
    if e.burn or fluids.fireAt(cx, cy) then
      fluids.ignite(cx, cy, 1, true)
    end
  elseif kind == "wisp" then
    -- A flash of fire
    fluids.explosion(cx, cy, 14)
    for _ = 1, 10 do
      effects.particle(cx, cy, (r() - 0.5) * 90, (r() - 0.5) * 90, 0.4, { 1, 0.6, 0.2 }, 0, true)
    end
  elseif kind == "bat" then
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

-- The DPS dummy takes no damage; it adds each hit to its meter instead.
-- Hits landing in the same frame (shotgun pellets, a blast) count as one
-- volley, and the measured time is padded by one average gap between volleys:
-- six shots 0.25 s apart span 1.25 s but are a 1.5 s rate of fire.
recordDps = function(e, amount)
  local m = e.meter
  if not m or not m.active then
    m = { active = true, total = 0, volleys = 0, start = clock, last = clock }
    e.meter = m
  end
  m.total = m.total + amount
  if m.volleys == 0 or clock > m.last then
    m.volleys = m.volleys + 1
  end
  m.last = clock
end

-- Seconds the meter's damage counts over (see recordDps). While a session is
-- running, time since the first hit counts too, so pauses (reloads) pull the
-- reading down as they should.
local function dpsSpan(m)
  local span = m.last - m.start
  if m.volleys > 1 then
    span = span * m.volleys / (m.volleys - 1)
  end
  if m.active then
    span = math.max(span, clock - m.start)
  end
  return math.max(span, 1) -- one hit alone reads as its damage per second
end

-- Damages an enemy. (dx, dy) is the hit direction, force the impact
function enemies.damage(e, amount, dx, dy, force, crit, fx)
  if e.dead then
    return
  end
  if e.acid and e.acid > 0 then
    amount = math.floor(amount * 1.3 + 0.5) -- corroded
  end
  if e.def.dummy then
    recordDps(e, amount)
  else
    e.hp = e.hp - amount
  end
  e.flash = 0.08
  if fx then
    e.lastFx = fx
  end
  local knock = e.def.knockback * (e.def.knockMul or 1)
  if dx and dx ~= 0 and not e.def.knockMul then
    -- A hit shoves the sprite back for a moment
    e.stagger = math.min(0.2, 0.08 + (force or 0) / 2500)
    e.hitDir = dx > 0 and 1 or -1
  end
  local cx = center(e)
  if crit then
    effects.popup(cx, e.body.y - 4, amount .. "!", { 1, 0.5, 0.2 })
  else
    effects.popup(cx, e.body.y - 2, tostring(amount), { 1, 0.27, 0.24 })
  end
  if e.swarm then
    e.swarm.awake = true
  end
  -- Being shot wakes it and makes it hunt the hunter
  if e.state == "sleep" or e.state == "idle" then -- (the dummy is "still")
    e.state = e.kind == "spitter" and "watch" or "chase"
  end
  e.seesPlayer = true
  if force and force > 0 and knock > 0 then
    e.body.vx = e.body.vx + (dx or 0) * force * knock
    e.body.vy = e.body.vy + (dy or 0) * force * knock - 30 * (e.def.knockMul or 1)
    if not e.def.knockMul then
      e.stun = 0.15
    end
  end
  if e.hp <= 0 and not e.def.dummy then
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
        local k = speed * (1 - 0.5 * dist / radius) * (e.def.knockMul or 1)
        e.body.vx = e.body.vx * 0.3 + dx / dist * k
        e.body.vy = e.body.vy * 0.3 + dy / dist * k - 20
        if not e.def.knockMul then
          e.stun = math.max(e.stun, 0.25)
        end
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
  if love.math.random() < dt * 4 then
    local cx, cy = center(e)
    fluids.ignite(cx, cy, 0.5, true) -- a burning monster sets gas alight
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
        local k = e.def.knockMul or 1
        b.vx = dir * 220 * k
        b.vy = -140 * k
        if k >= 1 then
          e.stun = 0.35
        end
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
-- A ghoul's claws rake the terrain in front of it: a ragged bite out of the
-- rock at chest height as the arms fling out, then a low one as they follow
-- through. Masonry, iron and bedrock don't give.
local function clawDig(e, world, low)
  local def, b = e.def, e.body
  local k = def.scale or 1
  local x = b.x + b.w / 2 + e.facing * (b.w / 2 + 3 * k)
  local y = b.y + b.h * (low and 0.68 or 0.42)
  destruction.dig(world, x, y, def.clawDig * k, def.clawPower, e.facing, low and 0.4 or -0.2)
end

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
  if e.rakes == 1 and e.strikeT < def.strike * 0.6 then
    -- The follow-through, low
    e.rakes = 0
    clawDig(e, world, true)
  end
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
        e.rakes = 2 -- digs left in this strike
        b.vx = e.facing * def.lungeSpeed
        b.vy = -def.lungeLift
        e.grounded = false
        audio.play("hit", 0.5, 0.6)
        clawDig(e, world, false)
        e.rakes = 1
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
  if blocked and (e.rakes or 0) > 0 and not blocker then
    -- Lunged into a wall: the claws tear into it there and then
    e.rakes = 0
    clawDig(e, world, true)
  end
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

-- Mire hopper: crouches, then leaps at the hunter in an arc. The Matron
-- (def.kids) calls hoppers to her every third leap.
local function updateHopper(e, dt, world, player, px, py)
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
  if e.grounded then
    b.vx = b.vx * math.max(0, 1 - 10 * dt)
    if e.stun > 0 then
      e.windT = nil
    elseif e.state == "chase" then
      e.facing = px < cx and -1 or 1
      if e.windT then
        e.windT = e.windT - dt
        if e.windT <= 0 then
          e.windT = nil
          local dx = px - cx
          b.vx = (dx < 0 and -1 or 1) * math.min(def.leapSpeed, math.abs(dx) * 2 + 40)
          b.vy = -def.leapLift
          e.grounded = false
          e.cooldown = def.leapCooldown
          e.leaps = (e.leaps or 0) + 1
          audio.play("hit", 0.4, 0.5)
          if def.kids and e.leaps % 3 == 0 then
            e.kids = e.kids or {}
            local alive = {}
            for _, k in ipairs(e.kids) do
              if not k.dead then
                alive[#alive + 1] = k
              end
            end
            e.kids = alive
            for side = -1, 1, 2 do
              if #e.kids < 4 then
                e.kids[#e.kids + 1] = enemies.spawn("hopper", cx + side * 18, b.y + b.h, e.toughness * 0.5, e.level)
                e.kids[#e.kids].state = "chase"
              end
            end
          end
        end
      elseif e.cooldown <= 0 and dist < def.sight then
        e.windT = def.windup
      end
    else
      -- Idle: a small hop now and then
      e.timer = e.timer - dt
      if e.timer <= 0 then
        e.timer = 1.5 + love.math.random() * 2.5
        b.vx = (love.math.random() < 0.5 and -1 or 1) * 30
        b.vy = -110
        e.grounded = false
      end
    end
  end
  b.vy = math.min(b.vy + config.gravity * dt, 450)
  if Body.moveX(b, collide, b.vx * dt, 3) then
    b.vx = 0
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = 0
  end
  if e.grounded and b.vy >= 0 then
    Body.snapDown(b, collide, 3)
  end
end

-- Bloater: drifts toward the hunter, leaking poison gas as it goes
local function updateBloater(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  e.phase = e.phase + dt * 2
  e.puffT = (e.puffT or 1) - dt
  if e.puffT <= 0 then
    e.puffT = def.puff and 0.9 or 2 + love.math.random()
    fluids.addGas(cx, cy + 3, def.puff and 0.5 or 0.28, def.puff and 14 or 6)
  end
  if e.state == "sleep" then
    if e.seesPlayer and dist < def.sight then
      e.state = "chase"
    else
      b.vy = math.sin(e.phase) * 5
      b.vx = 0
    end
  elseif dist > def.forget then
    e.state = "sleep"
  end
  local collide = collider(e, world)
  if e.state == "chase" and e.stun <= 0 then
    local d = math.max(1, dist)
    local tx, ty = (px - cx) / d * def.speed, (py - 10 - cy) / d * def.speed + math.sin(e.phase) * 8
    local step = def.accel * dt
    b.vx = b.vx < tx and math.min(b.vx + step, tx) or math.max(b.vx - step, tx)
    b.vy = b.vy < ty and math.min(b.vy + step, ty) or math.max(b.vy - step, ty)
    e.facing = tx >= 0 and 1 or -1
  end
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.5
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.5
  end
end

-- Flocking for swarm members: how hard to push away from close neighbours
-- (separation) and toward the swarm's centre (cohesion)
local function flock(e, cx, cy)
  local sepX, sepY, ax, ay, n = 0, 0, 0, 0, 0
  for _, o in ipairs(e.swarm.members) do
    if o ~= e and not o.dead then
      local ox, oy = center(o)
      n = n + 1
      ax, ay = ax + ox, ay + oy
      local dx, dy = cx - ox, cy - oy
      local d2 = dx * dx + dy * dy
      if d2 < 256 and d2 > 0 then
        local d = math.sqrt(d2)
        sepX, sepY = sepX + dx / d * (16 - d) / 16, sepY + dy / d * (16 - d) / 16
      end
    end
  end
  local cohX, cohY = 0, 0
  if n > 0 then
    cohX, cohY = ax / n - cx, ay / n - cy
  end
  return sepX * 90, sepY * 90, cohX * 0.7, cohY * 0.7
end

-- A box that is blocked only by terrain that can never be dug away (bedrock,
-- the shop's masonry and iron): the Dread Bat flies through everything else
local function hardTerrain(world, x, y, w, h)
  local anchored = materials.anchored
  for py = y, y + h - 1 do
    for px = x, x + w - 1 do
      if anchored[world:get(px, py)] then
        return true
      end
    end
  end
  return false
end

-- Dread Bat: screeches as soon as the hunter is close (line of sight or not),
-- then dives at where he stood in a straight line, digging out everything in
-- its path. Between dives it flutters toward him, held back by the rock.
local function updateDreadBat(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  e.attackCd = math.max(0, (e.attackCd or 0) - dt)
  e.phase = e.phase + dt * (e.state == "lock" and 6 or (e.state == "charge" and 3 or 11))
  if e.state == "sleep" then
    if dist < def.sight then
      e.state = "chase"
      audio.play("bat_screech", 1, 0.5)
    else
      return
    end
  end
  if e.state ~= "charge" and dist > def.forget then
    e.state = "sleep"
    return
  end
  local collide = collider(e, world)
  local d = math.max(1, dist)
  if e.state == "chase" then
    local tx, ty = (px - cx) / d * def.speed, (py - 4 - cy) / d * def.speed + math.sin(e.phase * 0.5) * 25
    if e.stun <= 0 then
      local step = def.accel * dt
      b.vx = b.vx < tx and math.min(b.vx + step, tx) or math.max(b.vx - step, tx)
      b.vy = b.vy < ty and math.min(b.vy + step, ty) or math.max(b.vy - step, ty)
    end
    e.facing = tx >= 0 and 1 or -1
    if e.attackCd <= 0 and dist < def.chargeRange and e.stun <= 0 then
      e.state = "lock"
      e.timer = def.lockTime
      audio.play("bat_screech", 1, 0.5)
    end
  elseif e.state == "lock" then
    -- Hangs in the air, wings wide, shaking, eyes on the hunter
    b.vx, b.vy = b.vx * math.max(0, 1 - 6 * dt), b.vy * math.max(0, 1 - 6 * dt)
    e.facing = px >= cx and 1 or -1
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.state = "charge"
      e.timer = def.chargeTime
      e.digged = 0
      b.vx, b.vy = (px - cx) / d * def.chargeSpeed, (py - 2 - cy) / d * def.chargeSpeed
      audio.play("explosion", 0.5, 0.6)
    end
  elseif e.state == "charge" then
    e.timer = e.timer - dt
    e.facing = b.vx >= 0 and 1 or -1
    local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    -- Tear out a tunnel just ahead of the body, every few pixels of travel
    e.digged = (e.digged or 0) - speed * dt
    if e.digged <= 0 then
      e.digged = 5
      destruction.dig(world, cx + b.vx / speed * 9, cy + b.vy / speed * 9, def.digRadius, 40, b.vx / speed, b.vy / speed)
    end
    local function hard(x, y, w, h)
      return hardTerrain(world, x, y, w, h)
    end
    local blocked = Body.moveX(b, hard, b.vx * dt, 0)
    local blockedY = Body.moveY(b, hard, b.vy * dt)
    if love.math.random() < dt * 30 then
      effects.particle(cx, cy, -b.vx * 0.05, -b.vy * 0.05, 0.3, { 0.35, 0.22, 0.45 }, 0)
    end
    if e.timer <= 0 or blocked or blockedY then
      e.state = "recover"
      e.timer = 0.9
      e.attackCd = def.chargeCooldown
      b.vx, b.vy = b.vx * 0.2, b.vy * 0.2
      if blocked or blockedY then
        e.stun = 0.4
      end
    end
    return
  elseif e.state == "recover" then
    e.timer = e.timer - dt
    b.vx, b.vy = b.vx * math.max(0, 1 - 3 * dt), b.vy * math.max(0, 1 - 3 * dt)
    if e.timer <= 0 then
      e.state = "chase"
    end
  end
  -- Out of the dive it is held back by terrain like any bat; if the dive
  -- left it inside rock that was dug out, there is nothing to hold it
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.4
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.4
  end
end

-- Swarm bat: wakes with its colony, then flocks at the hunter in a fluttering
-- cloud, biting and veering off
local function updateSwarmBat(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  e.phase = e.phase + dt * 20
  local swarm = e.swarm
  if e.state == "sleep" then
    if (e.seesPlayer and dist < def.sight) or (swarm and swarm.awake) then
      e.state = "chase"
      if swarm then
        swarm.awake = true
      end
    else
      return
    end
  end
  if dist > def.forget then
    e.state = "sleep"
    if swarm then
      swarm.awake = false
    end
    return
  end
  local collide = collider(e, world)
  local d = math.max(1, dist)
  local tx, ty
  if e.state == "retreat" then
    tx, ty = -(px - cx) / d * def.speed, -def.speed * 0.6
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.state = "chase"
    end
  else
    tx, ty = (px - cx) / d * def.speed, (py - 4 - cy) / d * def.speed
  end
  if swarm then
    local sx, sy, kx, ky = flock(e, cx, cy)
    tx, ty = tx + sx + kx, ty + sy + ky
  end
  local t = e.phase
  tx, ty = tx + math.sin(t * 0.13) * 34, ty + math.cos(t * 0.17) * 34
  if e.stun <= 0 then
    local step = def.accel * dt
    b.vx = b.vx < tx and math.min(b.vx + step, tx) or math.max(b.vx - step, tx)
    b.vy = b.vy < ty and math.min(b.vy + step, ty) or math.max(b.vy - step, ty)
  end
  e.facing = b.vx >= 0 and 1 or -1
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.5
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.5
  end
end

-- Cinder wisp: flits at the hunter in a wobbling line, leaving flames
local function updateWisp(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  e.phase = e.phase + dt * 6
  local swarm = e.swarm
  if e.state == "sleep" then
    if (e.seesPlayer and dist < def.sight) or (swarm and swarm.awake) then
      e.state = "chase"
      if swarm then
        swarm.awake = true
      end
    else
      b.vy = math.sin(e.phase * 0.4) * 6
      b.vx = 0
    end
  elseif dist > def.forget then
    e.state = "sleep"
  end
  local collide = collider(e, world)
  if e.state == "chase" and e.stun <= 0 then
    local d = math.max(1, dist)
    local dx, dy = (px - cx) / d, (py - 4 - cy) / d
    local wob = math.sin(e.phase * 0.8) * 50
    local tx, ty = dx * def.speed - dy * wob, dy * def.speed + dx * wob
    if swarm then
      local sx, sy, kx, ky = flock(e, cx, cy)
      tx, ty = tx + sx + kx * 0.5, ty + sy + ky * 0.5
    end
    local step = def.accel * dt
    b.vx = b.vx < tx and math.min(b.vx + step, tx) or math.max(b.vx - step, tx)
    b.vy = b.vy < ty and math.min(b.vy + step, ty) or math.max(b.vy - step, ty)
    e.facing = tx >= 0 and 1 or -1
    e.fireT = (e.fireT or 0) - dt
    if e.fireT <= 0 then
      e.fireT = 0.2
      fluids.ignite(cx, cy, 1)
    end
  end
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.6
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.6
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
    damage = math.floor(def.globDamage * e.dmgMul + 0.5),
    life = GLOB_LIFE,
  }
  for _ = 1, 5 do
    effects.particle(cx, cy, (love.math.random() - 0.5) * 50, love.math.random() * 40, 0.3, { 0.55, 0.95, 0.35 }, 200, true)
  end
end

-- A straight-flying glob of gas at an angle (the Queen's shots; a little
-- gravity so they read as lobbed, not as bullets)
local function fireGlob(e, ang, speed)
  local def = e.def
  local cx, cy = center(e)
  cy = cy + e.body.h * 0.15
  e.spitT = 0.3
  globs[#globs + 1] = {
    isGlob = true,
    x = cx,
    y = cy,
    vx = math.cos(ang) * speed,
    vy = math.sin(ang) * speed,
    gravity = def.globGravity,
    damage = math.max(1, math.floor(def.globDamage * e.dmgMul + 0.5)),
    life = GLOB_LIFE,
  }
  effects.particle(cx, cy, math.cos(ang) * 30, math.sin(ang) * 30, 0.25, { 0.55, 0.95, 0.35 }, 0, true)
end

-- Below a third of her health the Queen splits in two. What she had left is
-- divided between the halves (no shared pool), each a size smaller and weaker
-- than her, and each splits again in turn, down to def.splitDepth splits.
-- Killing every remnant kills the boss (see die).
local function splitQueen(e)
  local def = e.def
  local gen = (e.gen or 0) + 1
  local half = math.max(1, math.floor(e.hp / 2))
  local cx, cy = center(e)
  local size = def.spriteW * QUEEN_SCALES[gen + 1]
  e.group = e.group or { alive = 1 }
  local share = (e.goldShare or 1) / 2
  local dmgMul = e.dmgMul * def.splitDamage
  local scale = QUEEN_SCALES[gen + 1]
  local brood = {}
  for i = 1, 2 do
    local q = e
    if i == 2 then
      q = enemies.spawn("queen", cx, cy, e.toughness, e.level)
      q.areaIndex, q.arena, q.group, q.state = e.areaIndex, e.arena, e.group, "chase"
      e.group.alive = e.group.alive + 1
    end
    q.gen, q.scale, q.hp, q.maxHp = gen, scale, half, half
    q.goldShare, q.dmgMul, q.stage = share, dmgMul, 1
    q.body.w, q.body.h = size, size
    q.body.x, q.body.y = math.floor(cx - size / 2), math.floor(cy - size / 2)
    q.body.vx, q.body.vy = (i == 1 and -1 or 1) * 170, -40
    q.orbit = -math.pi / 2 + (i == 1 and -1 or 1) * (0.35 + love.math.random() * 0.5)
    q.globT, q.colT, q.puffT, q.minionT, q.dashT, q.dashCd = 1.5 + love.math.random(), nil, nil, 3 + love.math.random() * 2, nil, 1
    q.burstLeft, q.novaWind, q.novaT, q.flash = nil, nil, nil, 0.15
    q.minions = {}
    q.phase = love.math.random() * 10
    removePhysics(q) -- (rebuilt at its new size next frame)
    brood[i] = q
  end
  audio.play("bat_screech", 1, 0.5)
  effects.ring(cx, cy, 60, { 0.85, 0.95, 0.35 })
  fluids.addGas(cx, cy, 1, 30)
  for _ = 1, 16 do
    local ang = love.math.random() * math.pi * 2
    effects.particle(cx, cy, math.cos(ang) * (40 + love.math.random() * 90), math.sin(ang) * (40 + love.math.random() * 90), 0.7, { 0.72, 0.85, 0.3 }, 100, true)
  end
  effects.popup(cx, cy - size / 2 - 6, "SPLIT", { 0.85, 0.95, 0.35 })
end

-- Sulfur Queen. Three stages by health (over 66%, over 33%, below): she
-- breathes gas faster and wider each time, shoots triple shots and then
-- straight-line bursts in turn, calls bloaters and then wisps (which light
-- her own gas), and drops pillars of gas across the arena. Below a third of
-- her health she splits in two (see splitQueen); the remnants keep the same
-- attacks, minus the pillars and with less damage. She holds a set distance
-- from the hunter, dashing in when she falls behind. She wakes when the hunter
-- enters her arena and never leaves it.
local function updateQueen(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  local a = e.arena
  local gen = e.gen or 0
  local sf = b.w / def.w -- 1 for her, smaller for each remnant
  local frac = e.hp / e.maxHp
  local stage = frac > 0.66 and 1 or (frac > 0.33 and 2 or 3)
  e.phase = e.phase + dt * 2
  if e.state == "sleep" then
    local inside = not a or (px > a.x0 and px < a.x1 and py > a.top and py < a.floorY)
    if inside and dist < def.sight then
      e.state = "chase"
      e.stage = 1
      e.group = e.group or { alive = 1 }
      audio.play("bat_screech", 1, 0.4)
    else
      b.vx, b.vy = 0, math.sin(e.phase) * 4
      return
    end
  end
  if frac < 0.33 and gen < def.splitDepth then
    splitQueen(e)
    return
  end
  if stage > (e.stage or 1) then
    -- A new stage: a roar and a burst of gas
    audio.play("bat_screech", 1, 0.4)
    effects.ring(cx, cy, 70 * sf, { 0.8, 0.92, 0.3 })
    fluids.addGas(cx, cy, 1, 50 * sf)
  end
  e.stage = stage

  -- Breathes poison
  e.puffT = (e.puffT or 0) - dt
  if e.puffT <= 0 then
    e.puffT = ({ 0.38, 0.28, 0.2 })[stage] * (1 + gen * 0.5)
    fluids.addGas(cx, cy + 16 * sf, 0.5, (28 + stage * 8) * sf)
  end
  -- Shots, alternating: a triple shot fanned at the hunter, then a burst of
  -- shots one after the other down a single line. Remnants fire less often.
  local shotSpeed = def.globSpeed
  local aimAng = math.atan2(py - cy, px - cx)
  e.globT = (e.globT or 1.8) - dt
  if e.globT <= 0 and not (e.burstLeft and e.burstLeft > 0) then
    e.globT = ({ 2.2, 1.8, 1.4 })[stage] * (1 + gen * 0.4)
    e.volley = (e.volley or 0) + 1
    if e.volley % 2 == 1 then
      for i = -1, 1 do
        fireGlob(e, aimAng + i * 0.2, shotSpeed)
      end
      audio.play("shot_pistol", 0.5, 0.45)
    else
      e.burstLeft = 4 + stage * 2
      e.burstAng = aimAng -- the line is fixed when the burst starts
      e.burstT = 0
    end
  end
  if e.burstLeft and e.burstLeft > 0 then
    e.burstT = e.burstT - dt
    if e.burstT <= 0 then
      e.burstT = 0.1
      e.burstLeft = e.burstLeft - 1
      fireGlob(e, e.burstAng, shotSpeed * 1.15)
      audio.play("shot_pistol", 0.3, 0.6)
    end
  end
  -- Gas columns (only before she splits): vents crack open across the arena,
  -- and after a short warning dense gas pours up through its whole height in
  -- several places, walling off parts of it. A new set, in new places, every
  -- few seconds.
  e.colT = (e.colT or 2.5) - dt
  if e.colT <= 0 and a and gen == 0 then
    e.colT = ({ 8, 7, 6 })[stage]
    local n = 1 + stage
    local lo, hi = a.x0 + 110, a.x1 - 110
    local seg = (hi - lo) / n
    for k = 1, n do
      local x = lo + (k - 0.5 + (love.math.random() - 0.5) * 0.7) * seg
      fluids.addColumn(x, 64, a.top + 12, a.floorY - 2, 1.4, 8)
    end
    audio.play("explosion", 0.5, 0.5)
    effects.ring(cx, cy, 50, { 0.9, 0.95, 0.4 })
  end
  -- Calls minions: bloaters first, wisps from the second stage. Remnants call
  -- fewer, less often.
  e.minionT = (e.minionT or 4) - dt
  if e.minionT <= 0 then
    e.minionT = (stage == 1 and 6 or 4.5) * (1 + gen * 1.5)
    local alive = {}
    for _, m in ipairs(e.minions or {}) do
      if not m.dead then
        alive[#alive + 1] = m
      end
    end
    e.minions = alive
    if #alive < (3 + stage) - gen then
      local kind = (stage == 1 or (stage == 3 and #alive % 2 == 0)) and "bloater" or "wisp"
      local side = love.math.random() < 0.5 and -1 or 1
      local m = enemies.spawn(kind, cx + side * 24 * sf - 7, cy + 10 * sf, e.toughness * 0.4, e.level)
      m.state = "chase"
      e.minions[#e.minions + 1] = m
      effects.ring(cx + side * 24 * sf, cy + 10 * sf, 16, { 0.8, 0.92, 0.3 })
    end
  end
  -- The last stage: swells for a moment, then bursts a huge cloud
  if stage == 3 then
    e.novaT = (e.novaT or 4) - dt
    if e.novaT <= 0 and not e.novaWind then
      e.novaWind = 1.2
      audio.play("bat_screech", 0.8, 0.5)
    end
    if e.novaWind then
      e.novaWind = e.novaWind - dt
      if love.math.random() < dt * 30 then
        effects.particle(cx + (love.math.random() - 0.5) * 50 * sf, cy + (love.math.random() - 0.5) * 50 * sf, 0, 0, 0.3, { 0.85, 0.95, 0.35 }, 0, true)
      end
      if e.novaWind <= 0 then
        e.novaWind = nil
        e.novaT = 4.5
        fluids.addGas(cx, cy, 1, 96 * sf)
        effects.ring(cx, cy, 110 * sf, { 0.85, 0.95, 0.35 })
      end
    end
  end

  -- Movement. She holds a set distance from the hunter (further out the bigger
  -- she is), hovering above him, aiming where he is going rather than where he
  -- is. She hurries in proportion to how far behind she is, and when she is
  -- well outside that distance (on screen or not) she dashes in. Nothing in the
  -- arena stops her: she passes through the platforms, and the rock.
  local function nothing()
    return false
  end
  local hold = def.holdDist + b.w * 0.6
  e.orbit = e.orbit or -math.pi / 2
  local ang = e.orbit + math.sin(e.phase * 0.5) * 0.25
  local pvx, pvy = player.body.vx * 0.5, player.body.vy * 0.3
  local gx, gy = px + pvx + math.cos(ang) * hold, py + pvy + math.sin(ang) * hold
  local d = math.max(1, math.sqrt((gx - cx) ^ 2 + (gy - cy) ^ 2))
  e.dashCd = (e.dashCd or 0) - dt
  if e.dashT then
    -- Dashing: a straight, fast line at the spot, ending once she is there
    e.dashT = e.dashT - dt
    if e.dashT <= 0 or d < 24 then
      e.dashT = nil
      e.dashCd = 1.2
    else
      b.vx, b.vy = (gx - cx) / d * 420, (gy - cy) / d * 420
      if love.math.random() < dt * 40 then
        effects.particle(cx, cy, 0, 0, 0.4, { 0.72, 0.85, 0.3 }, 0, true)
      end
    end
  elseif dist > hold + 170 and e.dashCd <= 0 and e.stun <= 0 then
    e.dashT = math.min(1.4, d / 420 + 0.1)
    audio.play("bat_screech", 0.5, 0.8)
    effects.ring(cx, cy, 36 * sf + 14, { 0.9, 0.95, 0.4 })
  end
  if not e.dashT then
    local speed = math.min(300, def.speed * (1 + 0.35 * (stage - 1)) + math.max(0, d - 20) * 1.8)
    local tx, ty = (gx - cx) / d * speed, (gy - cy) / d * speed + math.sin(e.phase) * 6
    if e.stun <= 0 then
      local step = def.accel * dt
      b.vx = b.vx < tx and math.min(b.vx + step, tx) or math.max(b.vx - step, tx)
      b.vy = b.vy < ty and math.min(b.vy + step, ty) or math.max(b.vy - step, ty)
    end
  end
  -- Remnants keep clear of each other
  if e.group then
    for _, o in ipairs(list) do
      if o ~= e and o.group == e.group and not o.dead then
        local ox, oy = center(o)
        local sx, sy = cx - ox, cy - oy
        local sd = math.sqrt(sx * sx + sy * sy)
        local gap = (b.w + o.body.w) * 0.55
        if sd < gap and sd > 0.01 then
          b.vx = b.vx + sx / sd * 260 * dt
          b.vy = b.vy + sy / sd * 260 * dt
        end
      end
    end
  end
  e.facing = px >= cx and 1 or -1
  Body.moveX(b, nothing, b.vx * dt, 0)
  Body.moveY(b, nothing, b.vy * dt)
  if a then
    -- She never leaves the arena (its ceiling is pierced by the tunnels in)
    b.x = math.max(a.x0 + 20, math.min(a.x1 - 20 - b.w, b.x))
    b.y = math.max(a.top + 4, math.min(a.floorY - b.h - 4, b.y))
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
        if not e.def.anchored then
          local push = math.min(momentum / e.def.weight, MAX_PROP_KNOCKBACK)
          b.vx = pvx / speed * push
          b.vy = pvy / speed * push - 40
          e.stun = 0.35
        end
      end
    end
  end
end

-- The DPS dummy stands still; its session ends after DPS_IDLE quiet seconds
local function updateDummy(e)
  local m = e.meter
  if m and m.active and clock - m.last > DPS_IDLE then
    m.active = false
  end
end

local UPDATE = {
  ghoul = updateGhoul,
  warden = updateGhoul,
  bat = updateBat,
  spitter = updateSpitter,
  dummy = updateDummy,
  swarmbat = updateSwarmBat,
  dreadbat = updateDreadBat,
  queen = updateQueen,
  hopper = updateHopper,
  matron = updateHopper,
  bloater = updateBloater,
  behemoth = updateBloater,
  wisp = updateWisp,
}

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
  clock = clock + dt
  local px, py = player:center()
  local pb = player.body
  for i = #list, 1, -1 do
    local e = list[i]
    if e.dead then
      table.remove(list, i)
    else
      local cx, cy = center(e)
      -- (An awake Queen is never frozen: she dashes back to the hunter from anywhere in her arena)
      if (math.abs(cx - px) < ACTIVE_RANGE and math.abs(cy - py) < ACTIVE_RANGE) or (e.kind == "queen" and e.state ~= "sleep") then
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
        if not e.def.dummy then
          updateMotes(e, dt)
        end
        -- Touching the hunter hurts him
        local b = e.body
        if not player.dead and e.state ~= "sleep" and overlaps(b.x, b.y, b.w, b.h, pb.x, pb.y, pb.w, pb.h) then
          if e.def.damage and player:hurt(math.floor(e.def.damage * e.dmgMul + 0.5), center(e)) and e.def.retreat then
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
      if overlaps(g.x - 1, g.y - 1, 3, 3, pb.x, pb.y, pb.w, pb.h) and not player.dead and player:isDodging() then
        player:dodged() -- (rolled under it: it flies on)
      elseif overlaps(g.x - 1, g.y - 1, 3, 3, pb.x, pb.y, pb.w, pb.h) and not player.dead then
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
  claw = { 0.84, 0.80, 0.64 },
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

-- The same, w pixels thick (a w x w square stamped along it)
local function thick(x0, y0, x1, y1, w)
  local n = math.max(1, math.ceil(math.max(math.abs(x1 - x0), math.abs(y1 - y0))))
  local o = (w - 1) / 2
  for i = 0, n do
    local t = i / n
    px(x0 + (x1 - x0) * t - o, y0 + (y1 - y0) * t - o, w, w)
  end
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

-- Where everything on the ghoul is this frame, shared by the body and its
-- glowing eyes. A heavy, hunched brute: it shambles with its long arms
-- dragging behind it, rears back to attack, and flings both arms forward as
-- it lunges.
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
  local lean = 2.4 - 3.4 * wind + 2.4 * strike
  pose.pelvis = { mid - f * 1, b.y + 11.5 + bob * 0.3 }
  pose.shoulder = { mid + f * lean, b.y + 6 + bob * 0.6 + wind * 1.2 }
  pose.head = { pose.shoulder[1] + f * (3 + strike - wind), pose.shoulder[2] - 2 + math.sin(t * 0.7) * 0.5 + wind * 0.5 }
  -- Feet shuffle along the ground, set wide, lifting only a little
  local ground = b.y + b.h - 1
  pose.feet = {}
  for i = 1, 2 do
    local ph = t + (i - 1) * math.pi
    local swing = moving and math.sin(ph) * 3 or (i == 1 and 2 or -1.5)
    local lift = (moving and math.cos(ph) > 0) and math.cos(ph) * 2 or 0
    pose.feet[i] = { mid + f * swing, ground - lift }
  end
  -- Arms: trailing and dragging behind; raised behind the head when rearing
  -- back; thrown forward in the strike
  local sx, sy = pose.shoulder[1], pose.shoulder[2] + 1
  pose.hands = {}
  for i = 1, 2 do
    local drag = (moving and math.sin(t + i) * 1.2 or 0)
    local rest = { sx - f * (5 + i * 1.8 + drag), ground - (i - 1) }
    local back = { sx - f * (4 + wind * 2 + i), sy - 4 - wind * 3 + i * 0.6 }
    local fwd = { sx + f * (5 + 6 * (1 - (1 - strike) ^ 2) + i), sy + 0.5 + i * 1.2 - strike }
    local h = { lerp(rest[1], back[1], wind), lerp(rest[2], back[2], wind) }
    h = { lerp(h[1], fwd[1], strike), lerp(h[2], fwd[2], strike) }
    pose.hands[i] = h
  end
  return pose
end

-- Where the eye sockets are on the head
local function ghoulEyes(pose)
  local hx, hy = pose.head[1], pose.head[2]
  return hx + (pose.f > 0 and 0 or -2), hy
end

-- A hunched, grey, ghost-pale brute: broad back, heavy arms that drag on the
-- ground, a big low skull and raking claws
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
  local reaching = pose.strike > 0.2

  -- An arm: a thick upper arm and forearm, knuckles, and three claws that
  -- point the way it reaches (or trail behind while it drags them)
  local function arm(hand, offset, upper, lower)
    local ax, ay = sx + offset, sy + 1
    local ex, ey = (ax + hand[1]) / 2 - f * 0.5, (ay + hand[2]) / 2 + 2 * (1 - pose.strike)
    color(upper)
    thick(ax, ay, ex, ey, 2)
    color(lower)
    thick(ex, ey, hand[1], hand[2], 2)
    px(hand[1] - 1, hand[2] - 1, 2, 2)
    local cd = reaching and f or -f
    color(GHOUL.claw)
    px(hand[1] + cd * 1.5, hand[2] - 1)
    px(hand[1] + cd * 2, hand[2])
    px(hand[1] + cd * 1.5, hand[2] + 1)
  end

  -- Back arm, then legs, behind the body
  arm(pose.hands[2], -f, GHOUL.skinDark, GHOUL.skinDark)
  for i = 2, 1, -1 do
    local foot = pose.feet[i]
    local c = i == 1 and GHOUL.skin or GHOUL.skinDark
    color(c)
    local kneeX, kneeY = (pelvis[1] + foot[1]) / 2 + f * 2, (pelvis[2] + foot[2]) / 2 - 0.5
    thick(pelvis[1], pelvis[2], kneeX, kneeY, 2) -- thick thigh
    thick(kneeX, kneeY, foot[1], foot[2] - 0.5, 2)
    px(foot[1] - 1, foot[2], 3, 1) -- a broad flat foot
    color(GHOUL.claw)
    px(foot[1] + f * 2, foot[2])
  end

  -- The torso: a broad hunched mass of rags, ragged at the hem
  color(GHOUL.rags)
  thick(pelvis[1], pelvis[2], sx, sy + 1, 5)
  color(GHOUL.ragsDark)
  thick(pelvis[1] - f * 2, pelvis[2], sx - f * 2, sy + 2, 1) -- the shadowed back edge
  for i = -2, 2 do
    px(pelvis[1] + i, pelvis[2] + 2 + ((i + math.floor(e.phase * 0.5)) % 2))
  end
  -- A great bare hump of a back, knotted with spine, and a heavy shoulder
  color(GHOUL.skin)
  px(sx - f * 3 - 1, sy - 2, 4, 3)
  px(sx - 1, sy - 1, 3, 3)
  color(GHOUL.skinLight)
  px(sx - f * 3 - 1, sy - 2, 4, 1)
  px(sx - 1, sy - 1, 2, 1)
  color(GHOUL.skinDark)
  for k = 1, 3 do
    local t = k / 4
    px(lerp(sx, pelvis[1], t) - f * 2.5, lerp(sy, pelvis[2], t))
  end
  px(sx + f, sy + 2)

  -- The head: a big low skull thrust forward, heavy brow, underslung jaw that
  -- drops open when it attacks
  color(GHOUL.skin)
  px(hx - 2, hy - 1, 5, 4)
  color(GHOUL.skinLight)
  px(hx - 2, hy - 1, 5, 1)
  local ex, ey = ghoulEyes(pose)
  color(GHOUL.ragsDark)
  px(ex, ey + 1, 2, 1) -- hollow eye sockets under the brow
  color(GHOUL.skinDark)
  px(hx - 2, hy + 2, 1, 1)
  local open = math.max(pose.wind, pose.strike)
  local jx = hx - 1 + (f > 0 and 1 or -1)
  color(GHOUL.skin)
  px(jx - 1, hy + 3 + (open > 0.3 and 1 or 0), 4, 1) -- the jaw
  color(GHOUL.ragsDark)
  px(jx, hy + 3, 2, open > 0.3 and 1 or 0)
  color(GHOUL.claw)
  px(jx + (f > 0 and 2 or -1), hy + 2) -- a tusk of a tooth

  -- Front arm over the body
  arm(pose.hands[1], 0, GHOUL.skin, GHOUL.skin)
  color(GHOUL.skinLight)
  local hand = pose.hands[1]
  px(hand[1] - 1, hand[2] - 1, 1, 1) -- a lit knuckle
end

local function drawGhoulEyes(e)
  local pose = ghoulPose(e)
  local ex, ey = ghoulEyes(pose)
  local glare = math.max(pose.wind, pose.strike)
  love.graphics.setColor(GHOUL.eye[1], GHOUL.eye[2], GHOUL.eye[3], 0.7 + 0.3 * glare)
  px(ex + (pose.f > 0 and 1 or 0), ey + 1, glare > 0.3 and 2 or 1, 1)
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

-- The DPS dummy: a burlap sack of straw on a post, with crossbar arms, a
-- stitched head and a plank foot. It flashes pale when struck.
local function drawDummy(e)
  local b = e.body
  local x, y = math.floor(b.x), math.floor(b.y)
  local flash = e.flash > 0
  local function c(r, g, bl)
    if flash then
      love.graphics.setColor(0.95, 0.92, 0.85)
    else
      love.graphics.setColor(r, g, bl)
    end
  end
  -- Stand: a plank foot and the post
  c(0.30, 0.21, 0.14)
  px(x - 1, y + 25, 14, 1)
  c(0.38, 0.27, 0.18)
  px(x + 5, y + 16, 2, 9)
  -- Arms: a crossbar with straw bursting from the ends
  c(0.36, 0.26, 0.17)
  px(x - 2, y + 8, 16, 2)
  c(0.78, 0.66, 0.36)
  px(x - 3, y + 7, 1, 1)
  px(x - 3, y + 10, 1, 1)
  px(x + 14, y + 7, 1, 1)
  px(x + 14, y + 10, 1, 1)
  -- Body: a stuffed sack, darker down one side, tied with rope
  c(0.56, 0.45, 0.29)
  px(x + 1, y + 6, 10, 11)
  c(0.44, 0.35, 0.22)
  px(x + 9, y + 6, 2, 11)
  c(0.72, 0.62, 0.40)
  px(x + 1, y + 9, 10, 1)
  px(x + 1, y + 14, 10, 1)
  -- A painted target on the chest
  c(0.62, 0.14, 0.14)
  px(x + 4, y + 10, 4, 3)
  c(0.82, 0.76, 0.60)
  px(x + 5, y + 11, 2, 1)
  -- Head: a smaller sack with stitched-cross eyes and a straw tuft
  c(0.60, 0.49, 0.31)
  px(x + 3, y, 6, 6)
  px(x + 2, y + 1, 8, 4)
  c(0.30, 0.22, 0.14)
  px(x + 4, y + 2, 1, 1)
  px(x + 7, y + 2, 1, 1)
  px(x + 4, y + 4, 4, 1)
  c(0.78, 0.66, 0.36)
  px(x + 5, y - 1, 1, 1)
  px(x + 7, y - 1, 1, 1)
end

-- A function that draws a pixel-art body mirrored by facing within its w-wide box
local function mirror(e, w)
  local b = e.body
  local x, y = math.floor(b.x), math.floor(b.y)
  local f = e.facing or 1
  return function(dx, dy, ww, hh)
    love.graphics.rectangle("fill", f > 0 and x + dx or x + w - dx - ww, y + dy, ww, hh)
  end, x, y
end

local HOPPER = {
  skin = { 0.26, 0.42, 0.32 },
  dark = { 0.16, 0.28, 0.24 },
  belly = { 0.60, 0.66, 0.44 },
  wart = { 0.42, 0.30, 0.46 },
}

-- A squat marsh toad: crouches before a leap, stretches out in the air
local function drawHopper(e)
  local r = mirror(e, 12)
  local function col(c)
    love.graphics.setColor(e.flash > 0 and { 1, 1, 1 } or c)
  end
  local air = not e.grounded
  local sq = e.windT and 1 or 0
  col(HOPPER.dark)
  if air then
    r(-2, 7, 3, 1)
    r(0, 6, 5, 2)
  else
    r(0, 5 + sq, 4, 4 - sq)
  end
  col(HOPPER.skin)
  r(1, 2 + sq, 9, 6 - sq)
  col(HOPPER.belly)
  r(3, 6, 6, 2)
  col(HOPPER.wart)
  r(2, 3 + sq, 1, 1)
  r(5, 2 + sq, 1, 1)
  col(HOPPER.skin)
  r(7, sq, 5, 5)
  col(HOPPER.dark)
  r(8, 4 + sq, 4, 1)
  if air then
    r(9, 6, 3, 1)
  else
    r(8, 7, 3, 2)
  end
end

local function drawHopperEyes(e)
  local r = mirror(e, 12)
  local sq = e.windT and 1 or 0
  love.graphics.setColor(1, 0.85, 0.3, 0.9)
  r(8, 1 + sq, 1, 1)
  r(10, 1 + sq, 1, 1)
end

-- The bloater: a round, veined sac of yellow-green gas with a slack mouth
-- and hanging tendrils; its core glows (see drawBloaterGlow)
local BLOATER_ROWS = { 6, 10, 12, 14, 14, 14, 14, 14, 14, 14, 12, 10, 8, 4 }

local function drawBloater(e)
  local b = e.body
  local x, y = math.floor(b.x), math.floor(b.y)
  local white = e.flash > 0
  local swell = (e.puffT and e.puffT < 0.25) and 1 or 0
  for row, w in ipairs(BLOATER_ROWS) do
    local c = row <= 2 and { 0.74, 0.78, 0.38 } or (row >= 9 and { 0.44, 0.48, 0.20 } or { 0.58, 0.62, 0.26 })
    love.graphics.setColor(white and { 1, 1, 1 } or c)
    local ww = w + swell
    love.graphics.rectangle("fill", x + math.floor((14 - ww) / 2), y + row - 1, ww, 1)
  end
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.36, 0.40, 0.16 })
  love.graphics.rectangle("fill", x + 3, y + 5, 1, 3)
  love.graphics.rectangle("fill", x + 10, y + 6, 1, 3)
  love.graphics.rectangle("fill", x + 6, y + 3, 2, 1)
  love.graphics.rectangle("fill", x + 5, y + 10, 4, 1) -- the slack mouth
  for i = 0, 2 do
    local sway = math.floor(math.sin(e.phase * 1.5 + i * 2) * 1.5 + 0.5)
    love.graphics.rectangle("fill", x + 3 + i * 3 + sway, y + 14, 1, 2)
  end
end

local function drawBloaterGlow(e)
  local b = e.body
  local x, y = math.floor(b.x), math.floor(b.y)
  local pulse = 0.55 + 0.25 * math.sin(e.phase * 1.7)
  love.graphics.setColor(0.8, 0.95, 0.3, pulse)
  love.graphics.rectangle("fill", x + 5, y + 5, 4, 3)
  love.graphics.setColor(1, 0.92, 0.35)
  love.graphics.rectangle("fill", x + 4, y + 7, 1, 1)
  love.graphics.rectangle("fill", x + 9, y + 7, 1, 1)
end

-- The cinder wisp: a spark with a fiery halo and a tail away from its motion
local function drawWispGlow(e)
  local b = e.body
  local cx, cy = math.floor(b.x + b.w / 2), math.floor(b.y + b.h / 2)
  local t = love.timer.getTime()
  local flick = math.floor(math.sin(t * 20 + e.phase) * 0.5 + 1)
  love.graphics.setColor(1, 0.45, 0.12, 0.55)
  love.graphics.rectangle("fill", cx - 3, cy - 3, 6, 6)
  love.graphics.rectangle("fill", cx - 2 - flick, cy - 4, 4 + flick * 2, 8)
  love.graphics.setColor(1, 0.75, 0.25)
  love.graphics.rectangle("fill", cx - 2, cy - 2, 4, 4)
  love.graphics.setColor(1, 0.97, 0.75)
  love.graphics.rectangle("fill", cx - 1, cy - 1, 2, 2)
  local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
  if sp > 5 then
    for i = 1, 3 do
      love.graphics.setColor(1, 0.5, 0.15, 0.5 - i * 0.12)
      love.graphics.rectangle("fill", math.floor(cx - b.vx / sp * i * 3), math.floor(cy - b.vy / sp * i * 3), 2, 2)
    end
  end
end

-- Bosses are drawn by scaling the sprite of the monster they grew from
local function scaled(fn)
  return function(e)
    local d = e.def
    if not d.scale then
      return fn(e)
    end
    local b = e.body
    local proxy = setmetatable({ body = { x = 0, y = 0, w = d.spriteW, h = d.spriteH, vx = b.vx, vy = b.vy } }, { __index = e })
    love.graphics.push()
    love.graphics.translate(math.floor(b.x + b.w / 2), b.y + b.h)
    love.graphics.scale(e.scale or d.scale) -- (Queen remnants are smaller)
    love.graphics.translate(-d.spriteW / 2, -d.spriteH)
    fn(proxy)
    love.graphics.pop()
  end
end

-- The Queen's crown: five gold spikes along the top of the sac, the middle
-- one tallest, with a pale gem (glowing, see drawQueenGlow)
local function drawQueenCrown(e)
  local b = e.body
  local k = b.w / 56
  local cx, top = math.floor(b.x + b.w / 2), math.floor(b.y) + 2
  local white = e.flash > 0
  for i = -2, 2 do
    local h = (11 - math.abs(i) * 3) * k
    local x = cx + i * 9 * k
    love.graphics.setColor(white and { 1, 1, 1 } or { 0.74, 0.64, 0.22 })
    love.graphics.rectangle("fill", x - 2 * k, top - h * 0.5, 5 * k, h * 0.5 + 2)
    love.graphics.setColor(white and { 1, 1, 1 } or { 0.90, 0.80, 0.34 })
    love.graphics.rectangle("fill", x - k, top - h * 0.8, 3 * k, h * 0.4)
    love.graphics.rectangle("fill", x, top - h, k, h * 0.3)
  end
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.90, 0.80, 0.34 })
  love.graphics.rectangle("fill", cx - 12 * k, top + 1, 25 * k, 3 * k)
end

local function drawQueenGlow(e)
  local b = e.body
  local k = b.w / 56
  local cx, top = math.floor(b.x + b.w / 2), math.floor(b.y) + 2
  love.graphics.setColor(1, 0.95, 0.5, 0.6 + 0.3 * math.sin(e.phase * 1.7))
  love.graphics.rectangle("fill", cx - k, top - 3 * k, 3 * k, 4 * k)
  love.graphics.setColor(1, 1, 0.85)
  love.graphics.rectangle("fill", cx, top - 2 * k, k, 2 * k)
  if e.novaWind then
    -- Swelling up for the big burst
    love.graphics.setColor(0.85, 0.95, 0.35, 0.35 + 0.3 * math.sin(love.timer.getTime() * 25))
    love.graphics.rectangle("fill", b.x - 3, b.y - 3, b.w + 6, b.h + 6)
  end
end

local DRAW = {
  ghoul = drawGhoul,
  warden = scaled(drawGhoul),
  bat = drawBat,
  swarmbat = drawBat,
  dreadbat = scaled(drawBat),
  queen = function(e)
    scaled(drawBloater)(e)
    drawQueenCrown(e)
  end,
  spitter = drawSpitter,
  dummy = drawDummy,
  hopper = drawHopper,
  matron = scaled(drawHopper),
  bloater = drawBloater,
  behemoth = scaled(drawBloater),
  wisp = function() end,
}
local GLOW = {
  ghoul = drawGhoulEyes,
  warden = scaled(drawGhoulEyes),
  bat = drawBatEyes,
  swarmbat = drawBatEyes,
  dreadbat = scaled(drawBatEyes),
  queen = function(e)
    scaled(drawBloaterGlow)(e)
    drawQueenGlow(e)
  end,
  spitter = drawSpitterGlow,
  dummy = function() end,
  hopper = drawHopperEyes,
  matron = scaled(drawHopperEyes),
  bloater = drawBloaterGlow,
  behemoth = scaled(drawBloaterGlow),
  wisp = drawWispGlow,
}

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
      if not e.def.dummy then
        drawAura(e)
      end
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
      if not e.def.dummy then
        lighting.add(cx, cy, 13, AURA[1], AURA[2], AURA[3], e.state == "sleep" and 0.03 or 0.045)
      end
      if e.kind == "spitter" then
        lighting.add(cx, cy + 4, e.windup and 30 or 16, 0.5, 1, 0.35, 0.5)
      elseif e.kind == "wisp" then
        lighting.add(cx, cy, 46, 1, 0.6, 0.25, 0.7)
      elseif e.kind == "dreadbat" then
        lighting.add(cx, cy, 50, 0.85, 0.3, 0.5, 0.3) -- so the dark bulk can be seen
      elseif e.kind == "queen" then
        lighting.add(cx, cy, 110, 0.8, 0.95, 0.3, 0.55)
      elseif e.kind == "bloater" or e.kind == "behemoth" then
        lighting.add(cx, cy, e.def.boss and 60 or 30, 0.7, 0.95, 0.3, 0.4)
      end
    end
  end
end

-- The DPS dummy's readout over its head (full resolution): live while a
-- session runs, frozen (and dimmer) after it ends
-- A boss that has noticed the hunter but is off screen is pointed to by a
-- small, wide red triangle on the screen's edge; it goes when the boss is
-- back in view.
local function drawBossPointer(sx, sy, sw, sh, unit)
  local cx, cy = sw / 2, sh / 2
  local dx, dy = sx - cx, sy - cy
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then
    return
  end
  dx, dy = dx / len, dy / len
  -- Where the ray from the centre meets a rectangle inset from the edge
  local inset = math.max(28, unit * 7)
  local hx, hy = cx - inset, cy - inset
  local t = math.min(dx ~= 0 and hx / math.abs(dx) or math.huge, dy ~= 0 and hy / math.abs(dy) or math.huge)
  local px, py = cx + dx * t, cy + dy * t
  local nx, ny = -dy, dx
  local tip = unit * 3.2
  local back = unit * 1.6
  local half = unit * 4.2 -- wide: wider than it is long
  local pulse = 0.75 + 0.25 * math.sin(love.timer.getTime() * 5)
  local ax, ay = px + dx * tip, py + dy * tip
  local bx1, by1 = px - dx * back + nx * half, py - dy * back + ny * half
  local bx2, by2 = px - dx * back - nx * half, py - dy * back - ny * half
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.polygon("fill", ax + dx * 2, ay + dy * 2, bx1 - nx * 2, by1 - ny * 2, bx2 + nx * 2, by2 + ny * 2)
  love.graphics.setColor(1, 0.25 * pulse, 0.24 * pulse)
  love.graphics.polygon("fill", ax, ay, bx1, by1, bx2, by2)
  love.graphics.setColor(1, 0.7, 0.66, 0.9)
  love.graphics.polygon("fill", ax, ay, px - dx * back * 0.2 + nx * half * 0.28, py - dy * back * 0.2 + ny * half * 0.28, px - dx * back * 0.2 - nx * half * 0.28, py - dy * back * 0.2 - ny * half * 0.28)
end

-- Screen overlays at full resolution: boss health bars over their heads and
-- pointers to off-screen bosses, and the DPS dummy's damage number
function enemies.drawScreen(toScreen, font)
  local sw, sh = love.graphics.getDimensions()
  love.graphics.setFont(font)
  local unit = toScreen(1, 0) - toScreen(0, 0) -- one world pixel on screen
  local pointed = {} -- a split boss gets one pointer, not one per remnant
  for _, e in ipairs(list) do
    local b = e.body
    local aggro = e.hp < e.maxHp or (e.state ~= "sleep" and e.state ~= "idle")
    if e.def.boss and not e.dead and aggro then
      local mx, my = toScreen(b.x + b.w / 2, b.y + b.h / 2)
      local x0, y0 = toScreen(b.x, b.y)
      local x1, y1 = toScreen(b.x + b.w, b.y + b.h)
      if x1 < 0 or x0 > sw or y1 < 0 or y0 > sh then
        if not (e.group and pointed[e.group]) then
          drawBossPointer(mx, my, sw, sh, unit)
          if e.group then
            pointed[e.group] = true
          end
        end
      else
        -- The health bar floats above the head: a red gradient, nothing else
        local sx, sy = toScreen(b.x + b.w / 2, b.y - 8)
        sy = math.max(sy, 44 + unit * 2.4) -- (kept on screen when her head is above it)
        local w, h = math.max(b.w * unit * 1.2, (e.gen or 0) > 0 and 48 or 140), math.max(10, unit * 2.4)
        local x, y = math.floor(sx - w / 2), math.floor(sy - h)
        -- Flat: a plain dark trough and a red gradient fill, no glass shading
        love.graphics.setColor(0.10, 0.02, 0.04, 0.75)
        love.graphics.rectangle("fill", x, y, w, h)
        local frac = math.max(0, e.hp) / e.maxHp
        if frac > 0 then
          hud.gradRect(x, y, w * frac, h, { 0.95, 0.22, 0.26 }, { 0.62, 0.07, 0.13 })
        end
      end
    end
    if e.def.dummy and e.meter then
      -- Just the damage dealt: red while hits keep coming, dim once the
      -- 2-second window has closed (the next hit starts it over)
      local sx, sy = toScreen(b.x + b.w / 2, b.y - 6)
      if sx > -200 and sx < sw + 200 and sy > -80 and sy < sh + 80 then
        local text = tostring(e.meter.total)
        local x = math.floor(sx - font:getWidth(text) / 2)
        love.graphics.setColor(0, 0, 0, 0.85)
        love.graphics.print(text, x + 2, math.floor(sy - font:getHeight()) + 2)
        if e.meter.active then
          love.graphics.setColor(1, 0.3, 0.27)
        else
          love.graphics.setColor(0.7, 0.45, 0.45)
        end
        love.graphics.print(text, x, math.floor(sy - font:getHeight()))
      end
    end
  end
end

return enemies
