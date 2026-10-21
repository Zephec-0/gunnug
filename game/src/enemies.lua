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

-- Sounds made while an enemy updates come from where it is (quieter and
-- panned by distance); anything else plays flat
local sndX, sndY
local function sfx(name, volume, pitch)
  if sndX then
    audio.playAt(name, sndX, sndY, volume, pitch)
  else
    audio.play(name, volume, pitch)
  end
end
local Body = require("src.body")
local config = require("src.config")
local destruction = require("src.destruction")
local effects = require("src.effects")
local gore = require("src.gore")
local fluids = require("src.fluids")
local hud = require("src.hud")
local perks = require("src.perks")
local physics = require("src.physics")
local materials = require("src.materials")
local pickups = require("src.pickups")
local props = require("src.props")
local queenfig = require("src.queenfig")

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
    clawDig = 6, -- its lunge rakes a bite this big out of the terrain in front...
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
  speed = 36,
  accel = 90,
  sight = 260,
  forget = 420,
  damage = 6,
  gold = { 3, 6 },
  knockback = 0.1,
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

-- Tunnel worm: bores through the rock after the hunter; in open air it is
-- only carried by its momentum and gravity (see updateWorm)
enemies.defs.worm = {
  w = 4,
  h = 4,
  hp = 14, -- (halved twice on 2026-10-14: still too hard to fight)
  speed = 108, -- it swims through the rock, never slowed by it
  lungeSpeed = 172,
  turn = 5.5, -- radians per second it can swing its head
  segments = 17,
  segGap = 2.8,
  digRadius = 2.4,
  lungeRange = 150,
  lungeTime = 0.8,
  lungeCooldown = 1.6,
  sight = 300,
  forget = 600,
  damage = 5, -- (halved on 2026-10-14)
  bodyDamage = 0.6, -- the body's touch hurts this fraction as much as the head's
  gold = { 5, 9 },
  knockback = 0.25,
  weight = 0.5,
}

-- Skeleton miner: lobs sticks of dynamite from a distance
enemies.defs.miner = {
  ground = true,
  w = 10,
  h = 19,
  hp = 22,
  speed = 40,
  jump = 230,
  sight = 280,
  forget = 480,
  damage = 9,
  gold = { 4, 8 },
  knockback = 0.45,
  weight = 3,
  pushForce = 260,
  throwRange = 230,
  holdMin = 80, -- backs away when the hunter is closer than this...
  holdMax = 150, -- ...and closes in when he is further
  throwCooldown = 3.2,
  windup = 0.55,
  fuse = 1.6,
  throwGravity = 420,
  blast = 1.2, -- the stick's blast, as a multiple of a basic explosive round's
}

-- Cave roller: an armoured pillbug that curls up and rolls at the hunter
enemies.defs.roller = {
  ground = true,
  w = 12,
  h = 10,
  hp = 30,
  speed = 30,
  jump = 200,
  sight = 240,
  forget = 420,
  damage = 12,
  gold = { 3, 7 },
  knockback = 0.2,
  weight = 4,
  armor = 0.3, -- curled or rolling, it takes this fraction of the damage
  curlTime = 0.55,
  rollSpeed = 165,
  rollTime = 2.8,
  rollCooldown = 1.0,
  rollRange = 190,
  dizzyTime = 1.5,
}

-- Piranha: a small, toothy fish of the cave pools. In the water it swims
-- freely, and once the hunter is in the water with it, closes in and darts
-- at him in quick dashes. A small bite, but they come in schools. Out of the
-- water (a dash can fling it out at the surface) it can only flop about in
-- short hops, toward the hunter if he is near; it bites just the same.
enemies.defs.piranha = {
  w = 8,
  h = 5,
  hp = 8,
  speed = 62, -- swimming
  sight = 190,
  forget = 320,
  damage = 4,
  chase = 480, -- once it has bitten, it follows the hunter this far, even out of the water
  dashRange = 64, -- darts at the hunter from this close...
  dashSpeed = 240,
  dashTime = 0.22,
  dashCooldown = 0.9, -- ...this often
  flopTime = 0.55, -- out of the water: a hop about this often
  flopSpeed = 45,
  flopLift = 120,
  gold = { 1, 3 },
  knockback = 0.6,
  weight = 0.4,
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
  w = 84, h = 84, hp = 1000, speed = 78, accel = 260,
  sight = 560, forget = 4000, damage = 24,
  knockback = 0.02, gold = { 200, 260 }, weight = 30,
  knockMul = 0.1, -- 90% less shove from bullets, kicks, blasts and singularities
  fireproof = true,
  puff = true,
  globSpeed = 210, globGravity = 60, globDamage = 14,
  dripDamage = 9, dripPeriod = 6, -- slime drips fall from her and hurt; each of her drips lets go every dripPeriod seconds
  holdDist = 60, -- she keeps this far from the hunter (plus her own size); dashes in when further
  splitDepth = 3, -- below 33% health she splits in two, and every piece splits again below half of its own, down to this many splits in a line (like a slime)
  splitDamage = 0.75, -- each split deals this much of the damage of the one before
})

-- The Marble Colossus: the Quarry's boss, a lumbering golem of veined marble.
-- It swipes, hurls stones, stomps up a wave of rock and sweeps a beam from its
-- eye; twice (at two thirds and a third of its health) it kneels in a crystal
-- shell, invulnerable, while little golems come in from both sides: slay them
-- all and the shell breaks, leaving it open to attack.
enemies.defs.golem = {
  name = "The Marble Colossus",
  boss = true, anchored = true, ground = true,
  w = 56, h = 84, hp = 1500, speed = 26, jump = 0,
  sight = 760, forget = 3000, damage = 22,
  knockback = 0.02, knockMul = 0.06, gold = { 220, 280 }, weight = 40,
  clawDig = 0, clawPower = 0,
  spriteW = 56, spriteH = 84, scale = 1,
  blood = { 0.8, 0.78, 0.84 },
}
enemies.defs.minigolem = {
  ground = true, w = 14, h = 20, hp = 60, speed = 78, jump = 220,
  lungeRange = 22, lungeSpeed = 180, lungeLift = 90, lungeCooldown = 1.2,
  windup = 0.35, strike = 0.35, sight = 900, forget = 3000,
  damage = 12, knockback = 0.3, gold = { 4, 8 }, pushForce = 120, weight = 5,
  clawDig = 0, clawPower = 0,
  blood = { 0.8, 0.78, 0.84 },
}

-- Names and field notes for the compendium's bestiary (src.compendium).
-- Bosses carry their own name; `compendium = false` keeps a kind out of it.
-- A new monster only needs an entry here (and in enemies.order, for where it
-- is listed) to show up.
local LORE = {
  ghoul = { "Ghoul", "A hunched, ash-pale scavenger of the catacombs. Slow on its feet, but it rears back and lunges when it gets close." },
  bat = { "Cave Bat", "Hangs asleep from the ceiling. Once it spots you it locks on, screeches, and dives in a straight line." },
  spitter = { "Spitter", "A fleshy sac clinging to the rock overhead. It swells up, then lobs a glob of acid in an arc. Shoot the glob down, or the rock it hangs from." },
  hopper = { "Mire Hopper", "A squat marsh toad. Crouches for a moment, then leaps at you in a long arc." },
  bloater = { "Bloater", "A veined bag of gas with a glowing core. Drifts after you leaking poison, and bursts into a cloud of it. Kill one near fire and the cloud goes up." },
  swarmbat = { "Swarm Bat", "One of a colony that hangs together. When one wakes they all wake, and the swarm flocks at you as a fluttering cloud." },
  wisp = { "Cinder Wisp", "A flitting spark that leaves a trail of fire and lights any gas it meets. Fire can't hurt it." },
  worm = { "Tunnel Worm", "Swims through solid rock after you, then bursts out of the ground in a leap. In the open air it has no control at all." },
  miner = { "Skeleton Miner", "Keeps its distance and lobs lit dynamite. Shoot the stick out of the air to set it off early." },
  roller = { "Cave Roller", "An armoured pillbug. Curls up and rolls at you, shrugging off most damage. Spent, it uncurls dizzy and soft." },
  piranha = { "Piranha", "A small, toothy fish of the cave pools. In the water it darts at you in quick bites; flung out of it, it flops after you all the same." },
  warden = { nil, "A ghoul grown huge in the dark of the catacombs. Rears back, then lunges from far away." },
  matron = { nil, "A giant hopper that bounds in great leaps, and calls her brood to her side." },
  behemoth = { nil, "A giant bloater, pouring out gas. Burst in fire, it goes up in a huge blast." },
  dreadbat = { nil, "A bat three times the size. It needs no line of sight: it screeches, then dives at you through the rock itself." },
  golem = { nil, "A lumbering giant of veined marble. It swipes, hurls stones, stomps up waves of rock and sweeps a beam from its eye. Now and then it kneels in a crystal shell that nothing can break until the little golems it calls are all dead." },
  minigolem = { "Marble Golemling", "A chip off the old colossus. Slow to start, hard to stop." },
  queen = { nil, "A crowned bloater the size of a house, queen of the Sulfur Vents. Immune to fire, she flies through the walls of her arena, and splits in two when badly hurt." },
}
for kind, l in pairs(LORE) do
  local def = enemies.defs[kind]
  def.name = def.name or l[1]
  def.desc = l[2]
end
enemies.defs.dummy.compendium = false

-- The order monsters are listed in the bestiary (anything missing is listed after)
enemies.order = {
  "ghoul", "bat", "swarmbat", "spitter", "hopper", "bloater", "wisp", "worm", "miner", "roller", "piranha",
  "warden", "dreadbat", "matron", "behemoth", "queen", "golem", "minigolem",
}

-- Queen remnant sizes by generation: whole-number sprite scales (the sac is 14 px)
local QUEEN_SCALES = { 6, 5, 4, 3, 2 }

-- Each area's monsters are tougher: damage rises with the area (toughness,
-- which scales health and gold, is set where they are placed)
local DAMAGE_PER_AREA = 0.35

-- The DPS dummy's meter: a session starts with the first hit and ends once
-- DPS_IDLE seconds pass without one; the reading then freezes until the next hit
local DPS_IDLE = 2

local ITEM_DROP_CHANCE = 0.05 -- chance a dying monster drops an ammo type or attachment
local ACTIVE_RANGE = 520 -- enemies further than this from the hunter are frozen
-- Bullets only test the monsters within this of the hunter (rebuilt every
-- frame): testing every monster in the world at every pixel a bullet moved
-- made heavy fire slow
local HIT_RANGE = 1000
-- Monsters this far from the hunter go dormant: they leave the live list (so no
-- per-frame update, draw, light or physics cost) but keep all their state, and
-- come back once he is within WAKE_RANGE. Bosses and their summons never do.
local dorm = { range = 760, wake = 640, every = 0.25, list = {}, t = 0 } -- (one table: the file is near Lua's local-variable limit)
local near = {}
local GLOB_LIFE = 4

local DRAW_REF, GLOW_REF = {}, {} -- filled in once the drawing functions exist (below)

local list = {}
local globs = {}
local golemStones, golemWaves = {}, {} -- the Marble Colossus's thrown stones and stone waves
local sticks = {} -- thrown dynamite
local clock = 0 -- game time (stops while paused), for the DPS meter

-- Set by src.game: called as onKill(enemy, fx) when an enemy dies, with the
-- effects of the bullet that last hit it (nil for kicks and explosions)
enemies.onKill = nil

function enemies.clear()
  list, globs, sticks, near, dorm.list = {}, {}, {}, {}, {}
  golemStones, golemWaves = {}, {}
end

function enemies.count()
  return #list
end

-- Every enemy (for src.fluids and tests)
-- 0..1: how hard monsters are pressing (px, py): awake ones close by count,
-- bosses more (drives the music's tension layer)
function enemies.threat(px, py)
  local t = 0
  for _, e in ipairs(near) do
    if not e.dead and e.state ~= "idle" and e.state ~= "sleep" then
      local b = e.body
      local d = math.sqrt((b.x + b.w / 2 - px) ^ 2 + (b.y + b.h / 2 - py) ^ 2)
      if d < 300 then
        t = t + (e.def.boss and 0.8 or 0.3) * (1 - d / 300)
      end
    end
  end
  return math.min(1, t)
end

-- Draws a rectangle for each creature in view (into the light-blocking mask)
function enemies.drawOccluders(view)
  for _, e in ipairs(near) do
    local b = e.body
    if not e.dead and not e.noShadow and b.x + b.w > view.x and b.x < view.x + view.w and b.y + b.h > view.y and b.y < view.y + view.h then
      if e.def.occluders then
        e.def.occluders(e) -- (a creature with a shape of its own casts that, not a box)
      else
        love.graphics.rectangle("fill", b.x + 1, b.y + 1, math.max(1, b.w - 2), math.max(1, b.h - 2))
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function enemies.all()
  return list
end

-- Every monster in the world, dormant ones included (a fresh table each call:
-- for the rare whole-world lookups, not per-frame work)
function enemies.every()
  local t = {}
  for _, e in ipairs(list) do
    t[#t + 1] = e
  end
  for _, e in ipairs(dorm.list) do
    t[#t + 1] = e
  end
  return t
end

function enemies.dormantCount()
  return #dorm.list
end

function dorm.canSleep(e)
  return not e.dead and not e.def.boss and not e.def.alwaysActive and not e.fromBoss and e.kind ~= "queen" and not e.def.dummy
end

-- Moves far monsters out of the live list and wakes the ones the hunter nears
function dorm.sweep(px, py)
  local dormant = dorm.list
  for i = #list, 1, -1 do
    local e = list[i]
    local b = e.body
    if dorm.canSleep(e) and (math.abs(b.x - px) > dorm.range or math.abs(b.y - py) > dorm.range) then
      if e.phys then
        e.phys:destroy()
        e.phys = nil
      end
      table.remove(list, i)
      dormant[#dormant + 1] = e
    end
  end
  for i = #dormant, 1, -1 do
    local e = dormant[i]
    local b = e.body
    if e.dead then
      table.remove(dormant, i)
    elseif math.abs(b.x - px) < dorm.wake and math.abs(b.y - py) < dorm.wake then
      table.remove(dormant, i)
      list[#list + 1] = e
    end
  end
end


-- The living monsters within ~1000 px of the hunter (rebuilt every frame by
-- enemies.update): what drawing, lights, blasts and fluids need to look at,
-- instead of every monster in the world
function enemies.nearby()
  return near
end

-- Spawns an enemy. Ghouls stand on the ground at (x, groundY); bats and
-- spitters hang from the ceiling at (x, ceilingY). toughness >= 1 scales HP.
local function newEnemy(kind, x, y, toughness, level, swarm)
  local def = assert(enemies.defs[kind], "unknown enemy: " .. tostring(kind))
  local top = def.ground and y - def.h or y
  local e = {
    kind = kind,
    def = def,
    body = Body.new(math.floor(x - def.w / 2), math.floor(top), def.w, def.h),
    hp = math.floor(def.hp * (toughness or 1) * (def.boss and 1 or require("src.meta").enemyHpMul()) + 0.5),
    maxHp = math.floor(def.hp * (toughness or 1) * (def.boss and 1 or require("src.meta").enemyHpMul()) + 0.5),
    toughness = toughness or 1,
    state = def.dummy and "still" or def.ground and "idle" or "sleep",
    level = level or 1,
    swarm = swarm, -- the colony this monster belongs to: { members = {...}, awake }
    dmgMul = (1 + ((level or 1) - 1) * DAMAGE_PER_AREA) * require("src.meta").enemyDmgMul(),
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
  if kind == "worm" then
    e.wx, e.wy = e.body.x + e.body.w / 2, e.body.y + e.body.h / 2
    e.ang = love.math.random() * math.pi * 2
    e.segs = {}
    for i = 1, def.segments do
      e.segs[i] = { e.wx, e.wy }
    end
    e.air, e.lungeT, e.lungeCd, e.digged = false, 0, 0, 0
  end
  return e
end

function enemies.spawn(kind, x, y, toughness, level, swarm)
  local e = newEnemy(kind, x, y, toughness, level, swarm)
  list[#list + 1] = e
  near[#near + 1] = e -- (testable by bullets at once, until the next frame's list)
  if swarm then
    swarm.members = swarm.members or {}
    swarm.members[#swarm.members + 1] = e
  end
  return e
end

-- A monster that isn't in the world, posed awake for a portrait (the
-- compendium and the title screen draw these with enemies.drawSpecimen).
-- Its body's top-left is at (0, 0).
function enemies.specimen(kind)
  local def = enemies.defs[kind]
  local e = newEnemy(kind, def.w / 2, def.ground and def.h or 0)
  e.state = (kind == "spitter" or kind == "worm") and "watch" or "chase"
  e.facing = 1
  e.grounded = true
  if e.segs then
    -- A worm, curled in an S
    e.state = "chase"
    e.air = true
    e.ang = -0.5
    e.wx, e.wy = 16, 2
    for i, seg in ipairs(e.segs) do
      local t = (i - 1) / #e.segs
      seg[1] = 16 - t * 30
      seg[2] = 2 + math.sin(t * math.pi * 2) * 5 + t * 6
    end
  end
  return e
end

-- The bounding box a specimen's drawing roughly fills: x, y, w, h
function enemies.specimenBounds(e)
  if e.segs then
    return -16, -6, 36, 18
  end
  local b = e.body
  local d = e.def
  local w = (d.spriteW or b.w) * (d.scale or 1)
  local h = (d.spriteH or b.h) * (d.scale or 1)
  return b.x + b.w / 2 - w / 2 - 2, b.y + b.h - h - 2, w + 4, h + 4
end

-- A photograph of a monster as it looks in the game right now (the death
-- recap's wanted poster): drawn into an image of its own size. `e` is the
-- monster that did it; if it isn't known (a glob's shooter) or is a worm
-- (drawn along the world), a posed specimen of its `kind` is photographed.
-- Returns { image, w, h } or nil.
function enemies.photo(e, kind)
  kind = kind or (e and e.kind)
  if not kind or not enemies.defs[kind] then
    return nil
  end
  local subject = e
  if not subject or subject.segs then
    subject = enemies.specimen(kind)
  end
  local flash = subject.flash
  subject.flash = 0 -- (not caught mid white-flash)
  local x, y, w, h = enemies.specimenBounds(subject)
  w, h = math.ceil(w), math.ceil(h)
  local canvas = love.graphics.newCanvas(w, h)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  love.graphics.translate(-math.floor(x), -math.floor(y))
  local ok = enemies.drawSpecimen(subject)
  love.graphics.pop()
  subject.flash = flash
  if not ok then
    return nil
  end
  return { image = canvas, w = w, h = h }
end

-- Draws a specimen (body, then its glowing parts). Returns false if this
-- kind's drawing failed outside the world.
function enemies.drawSpecimen(e)
  local ok = pcall(DRAW_REF[e.kind] or function() end, e)
  if ok then
    ok = pcall(GLOW_REF[e.kind] or function() end, e)
  end
  love.graphics.setColor(1, 1, 1)
  return ok
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

-- Removes a monster outright (no loot, no kill counted): the arena's others when a boss comes
function enemies.vanish(e)
  if e.dead then
    return
  end
  e.dead = true
  removePhysics(e)
  local cx, cy = center(e)
  effects.ring(cx, cy, 14, { 0.8, 0.7, 1 })
  for _ = 1, 8 do
    effects.particle(cx, cy, (love.math.random() - 0.5) * 120, (love.math.random() - 0.5) * 120, 0.5, { 0.8, 0.7, 1 }, 0, true)
  end
end

-- Elites (design doc §11a-iii) -------------------------------------------------------
-- A few monsters in every area are elite: three times the health, a quarter
-- more damage, more gold, a pulsing tint in their affix's colour with a crest
-- of diamonds over the head (one per affix), and a health bar with their name
-- once they are fighting. They pay marks and drop a locked item when killed
-- (enemies.onEliteKilled, set by src.game). Affixes are mostly data plus a
-- few hooks (enemies.damage, die, the update loop):
enemies.AFFIXES = {
  armoured = { name = "Armoured", color = { 0.62, 0.74, 1.0 }, desc = "Takes a third of the damage from the front. Shoot it from behind, or blow it up." },
  burning = { name = "Burning", color = { 1.0, 0.5, 0.18 }, desc = "Leaves fire where it goes, sets gas alight and can't be burned." },
  splitting = { name = "Splitting", color = { 0.55, 1.0, 0.5 }, desc = "Breaks into two of its kind when it dies." },
}
enemies.AFFIX_ORDER = { "armoured", "burning", "splitting" }
local ELITE_HP, ELITE_DAMAGE, ELITE_GOLD = 3, 1.25, 2.5
local ELITE_FRONT = 0.35 -- what an armoured elite takes from the front
local ELITE_BLAST = 1.5 -- ...and from blasts
-- Kinds that can be elite (and of those, the ones that can split)
local ELITE_KINDS = { ghoul = true, bat = true, spitter = true, hopper = true, bloater = true, miner = true, roller = true }
local SPLIT_KINDS = { ghoul = true, bat = true, hopper = true, bloater = true, miner = true, roller = true }
-- Elites per area, by depth tier
local ELITES_PER_TIER = { 3, 4, 5, 6, 7 }
local BOUNTY_POINT = 700 -- a bounty's quarry is pointed to on the screen's edge within this (px)

-- Set by src.game: called with the elite when one dies (marks, its trophy)
enemies.onEliteKilled = nil
local blasting = false -- (set while a blast is dealing damage: armoured elites take more)

-- Makes e elite with the given affixes (ids from enemies.AFFIXES)
function enemies.makeElite(e, affixes)
  e.elite = { affixes = affixes, has = {}, trail = 0, ember = 0 }
  for _, a in ipairs(affixes) do
    e.elite.has[a] = true
  end
  e.hp = math.floor(e.hp * ELITE_HP + 0.5)
  e.maxHp = e.hp
  e.dmgMul = e.dmgMul * ELITE_DAMAGE
  e.fireproof = e.elite.has.burning or nil
end

-- A bounty's named elite (src.bounties): its affixes, half as much health
-- again as an elite, its name, and a pointer on the screen's edge when near
function enemies.makeBounty(e, b)
  if e.elite then
    e.elite.affixes, e.elite.has = b.affixes, {}
    for _, a in ipairs(b.affixes) do
      e.elite.has[a] = true
    end
    e.fireproof = e.elite.has.burning or nil
  else
    enemies.makeElite(e, b.affixes)
  end
  e.hp = math.floor(e.hp * 1.5 + 0.5)
  e.maxHp = e.hp
  e.bounty, e.bountyName = b.id, b.name
end

-- "Armoured Burning Ghoul" (or a bounty's name: "Old Gnasher")
function enemies.eliteName(e)
  if e.bountyName then
    return e.bountyName
  end
  local parts = {}
  for _, a in ipairs(e.elite and e.elite.affixes or {}) do
    parts[#parts + 1] = enemies.AFFIXES[a].name
  end
  local d = e.def
  parts[#parts + 1] = d.name or (e.kind:sub(1, 1):upper() .. e.kind:sub(2))
  return table.concat(parts, " ")
end

-- Picks `count` of an area's monsters (a list) to be elite; tier is the
-- area's depth. From the second tier on, some get two affixes.
function enemies.rollElites(monsters, tier, random, mul)
  random = random or love.math.random
  if not require("src.meta").elitesOn() then
    return {} -- (the first run has none)
  end
  -- Never one the hunter can see right now (the screen is 640x360 world px)
  local px, py
  local game = package.loaded["src.game"]
  local hunter = game and game.player and game.player()
  if hunter then
    px, py = hunter:center()
  end
  local pool = {}
  for _, e in ipairs(monsters) do
    local cx, cy = center(e)
    local onScreen = px and math.abs(cx - px) < 400 and math.abs(cy - py) < 240
    if ELITE_KINDS[e.kind] and not e.def.boss and not e.swarm and not e.elite and not onScreen then
      pool[#pool + 1] = e
    end
  end
  local count = ELITES_PER_TIER[math.max(1, math.min(#ELITES_PER_TIER, tier or 1))] * (mul or 1)
  local made = {}
  for _ = 1, math.min(count, #pool) do
    local e = table.remove(pool, random(1, #pool))
    local options = {}
    for _, a in ipairs(enemies.AFFIX_ORDER) do
      if a ~= "splitting" or SPLIT_KINDS[e.kind] then
        options[#options + 1] = a
      end
    end
    local affixes = { table.remove(options, random(1, #options)) }
    if (tier or 1) >= 2 and #options > 0 and random() < 0.35 then
      affixes[2] = table.remove(options, random(1, #options))
    end
    enemies.makeElite(e, affixes)
    made[#made + 1] = e
  end
  return made
end

-- Every frame an elite is active: the burning one's trail and embers
local function updateElite(e, dt)
  local el = e.elite
  if el.has.burning then
    local b = e.body
    el.ember = el.ember - dt
    if el.ember <= 0 then
      el.ember = 0.07
      effects.particle(b.x + love.math.random() * b.w, b.y + love.math.random() * b.h * 0.6, (love.math.random() - 0.5) * 10, -20 - love.math.random() * 20, 0.4, { 1, 0.45 + love.math.random() * 0.35, 0.12 }, -30, true)
    end
    el.trail = el.trail - dt
    local moving = math.abs(b.vx or 0) > 12 or math.abs(b.vy or 0) > 12
    if el.trail <= 0 and moving and e.state ~= "sleep" then
      el.trail = 0.3
      if e.def.ground then
        fluids.ignite(b.x + b.w / 2, b.y + b.h - 1, 1)
      else
        fluids.ignite(b.x + b.w / 2, b.y + b.h / 2, 0.6, true) -- (a flyer only lights gas)
      end
    end
  end
end

-- An elite falls: it splits, drops its loot, and pays out (src.game)
local function eliteDies(e, cx, cy)
  local el = e.elite
  if el.has.splitting then
    local b = e.body
    for _, side in ipairs({ -1, 1 }) do
      local y = e.def.ground and (b.y + b.h) or b.y
      local kid = enemies.spawn(e.kind, cx + side * 5, y, e.toughness * 0.5, e.level)
      kid.state = (e.kind == "spitter") and "watch" or "chase"
      kid.seesPlayer = true
      kid.body.vx, kid.body.vy = side * 90, -110
      kid.stun = 0.3
    end
    effects.ring(cx, cy, 16, enemies.AFFIXES.splitting.color)
  end
  pickups.dropGold(cx, cy, math.floor(love.math.random(e.def.gold[1], e.def.gold[2]) * e.toughness * (ELITE_GOLD - 1) + 0.5))
  if e.carriesKey then
    require("src.events").dropKey(e.carriesKey, cx, cy)
  end
  local meta = require("src.meta")
  local item = meta.lockedItem() or require("src.items").random()
  pickups.dropItem(cx, cy - 4, item, (love.math.random() - 0.5) * 40, -110)
  effects.popup(cx, e.body.y - 10, "ELITE SLAIN", { 1, 0.85, 0.45 })
  if enemies.onEliteKilled then
    enemies.onEliteKilled(e)
  end
end

local function die(e)
  e.dead = true
  if e.kind == "golem" then
    -- Its little ones crumble with it
    for _, m in ipairs(e.minis or {}) do
      if not m.dead then
        m.dead = true
        removePhysics(m)
      end
    end
    golemStones, golemWaves = {}, {}
  end
  audio.playAt("enemy_die", e.body.x + e.body.w / 2, e.body.y + e.body.h / 2)
  if e.def.onDeath then
    e.def.onDeath(e)
  end
  removePhysics(e)
  local cx, cy = center(e)
  gore.burst(cx, cy, gore.color(e), math.min(2.5, (e.body.w * e.body.h) / 160))
  local share = e.goldShare or 1 -- a Queen remnant's cut of the Queen's gold
  local gold = love.math.random(e.def.gold[1], e.def.gold[2])
  local greed = e.lastFx and e.lastFx.greed or 0
  pickups.dropGold(cx, cy, math.floor(gold * e.toughness * (1 + greed) * share + 0.5))
  pickups.maybeDropItem(cx, cy, ITEM_DROP_CHANCE * perks.prod("loot") * share)
  if e.elite then
    eliteDies(e, cx, cy)
  end
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
    -- (one of the items, and now and then the weapon, is something still
    -- locked, src.meta: a thing to see and later teach the Gunsmith)
    local meta = require("src.meta")
    local lockedItem = meta.lockedItem()
    for k = 1, 4 do
      if k == 1 and lockedItem then
        pickups.dropItem(cx + (r() - 0.5) * 10, cy, lockedItem)
      else
        pickups.maybeDropItem(cx + (r() - 0.5) * 10, cy, 1)
      end
    end
    -- The weapon is never worse than an A. The Queen gives the Gatling gun
    -- until the Gunsmith has crafted it (it turns up nowhere else before that).
    local lockedGun = r() < 0.4 and meta.lockedArchetype() or nil
    if meta.SPECIAL_GUNS.gatling == e.kind and not meta.isUnlocked("weapon", "gatling") then
      lockedGun = "gatling"
    end
    local guns, gunInfo = require("src.guns"), require("src.gunInfo")
    local prize
    for _ = 1, 60 do
      prize = guns.generate(lockedGun, nil, 0.5)
      if gunInfo.gradeIndex(prize) >= 5 then
        break
      end
    end
    pickups.dropWeapon(cx, cy, prize)
    if e.reward then
      pickups.dropPerk(cx + 12, cy - 6, e.reward, 30, -80) -- (what this boss guards, see src.cavegen's bossReward)
    end
    -- ...and a perk, one the hunter doesn't have yet, left where it fell
    local perk = perks.roll(1)[1]
    if perk then
      pickups.dropPerk(cx, cy - 6, perk, 0, -70)
    end
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
    fluids.addGas(cx, cy, big and 1 or 0.9, big and 44 * (e.body.w / e.def.w) or 36)
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
  elseif kind == "worm" then
    -- Comes apart in pink rings and goo along its whole length
    for _, sg in ipairs(e.segs or {}) do
      effects.chunk(sg[1], sg[2], (r() - 0.5) * 60, -20 - r() * 40, 2, 2, r() < 0.5 and { 0.74, 0.52, 0.48 } or { 0.56, 0.36, 0.36 }, 3)
      effects.particle(sg[1], sg[2], (r() - 0.5) * 50, -r() * 40, 0.5, { 0.7, 0.3, 0.3 }, 300)
    end
  elseif kind == "miner" then
    -- Clatters apart: bones, a rusted hat, a dropped pickaxe
    for _ = 1, 9 do
      effects.chunk(cx + (r() - 0.5) * 6, cy + (r() - 0.5) * 10, (r() - 0.5) * 70, -30 - r() * 60, 1 + math.floor(r() * 2), 3, { 0.84, 0.82, 0.72 }, 3)
    end
    effects.chunk(cx, cy - 8, (r() - 0.5) * 50, -70, 5, 2, { 0.66, 0.50, 0.16 }, 3)
    effects.chunk(cx + 3, cy, 30, -40, 4, 1, { 0.46, 0.48, 0.54 }, 3)
    effects.particle(cx, cy - 7, 0, -20, 0.8, { 1, 0.86, 0.42 }, 80, true)
  elseif kind == "piranha" then
    -- A flick of scales and a red puff; bubbles rise if it died under water
    for _ = 1, 6 do
      effects.chunk(cx + (r() - 0.5) * 4, cy, (r() - 0.5) * 60, -20 - r() * 40, 1, 1, r() < 0.5 and { 0.62, 0.66, 0.66 } or { 0.80, 0.24, 0.18 }, 2)
    end
    if e.inWater then
      for _ = 1, 6 do
        effects.particle(cx + (r() - 0.5) * 6, cy, (r() - 0.5) * 10, -20 - r() * 20, 0.7, { 0.75, 0.9, 1 }, -40, true)
      end
    end
  elseif kind == "roller" then
    -- The shell cracks into plates
    for _ = 1, 8 do
      effects.chunk(cx + (r() - 0.5) * 8, cy + (r() - 0.5) * 6, (r() - 0.5) * 80, -30 - r() * 50, 2, 2, r() < 0.5 and { 0.50, 0.47, 0.44 } or { 0.32, 0.30, 0.30 }, 3)
    end
    for _ = 1, 6 do
      effects.particle(cx, cy, (r() - 0.5) * 70, (r() - 0.5) * 50, 0.4, { 0.74, 0.62, 0.54 }, 300)
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

-- A burrowing worm's heading is its own; shoving its head would just fight the steering
local function kindMovable(e)
  return not (e.kind == "worm" and not e.air)
end

-- Damages an enemy. (dx, dy) is the hit direction, force the impact
function enemies.damage(e, amount, dx, dy, force, crit, fx)
  if e.dead then
    return
  end
  amount = require("src.dev").damage(amount)
  if e.def.filter then
    -- (a monster that decides what a hit does: armour, weak points, gates)
    amount = e.def.filter(e, amount)
    if amount <= 0 then
      return
    end
  end
  if e.mito or (e.iframes and e.iframes > 0) then
    -- The Queen splitting (and a moment after): nothing touches her, her skin just shimmers
    local ax, ay = center(e)
    for _ = 1, 2 do
      effects.particle(ax + (love.math.random() - 0.5) * e.body.w, ay + (love.math.random() - 0.5) * e.body.h, (love.math.random() - 0.5) * 60, -love.math.random() * 50, 0.25, { 0.9, 1, 0.6 }, 0, true)
    end
    return
  end
  if e.invuln then
    -- The Colossus in its shell: everything glances off
    audio.playAt("clank", e.body.x, e.body.y, 0.4, 1.7)
    local ax, ay = center(e)
    for _ = 1, 2 do
      effects.particle(ax + (love.math.random() - 0.5) * e.body.w, ay + (love.math.random() - 0.5) * e.body.h, (love.math.random() - 0.5) * 120, -love.math.random() * 80, 0.2, { 0.7, 0.9, 1 }, 200, true)
    end
    return
  end
  if e.acid and e.acid > 0 then
    amount = math.floor(amount * 1.3 + 0.5) -- corroded
  end
  if e.vulnerable then
    -- A spent Queen is open to attack
    amount = math.floor(amount * 1.5 + 0.5)
    local ax, ay = center(e)
    effects.particle(ax + (love.math.random() - 0.5) * e.body.w * 0.6, ay + (love.math.random() - 0.5) * e.body.h * 0.6, 0, -20, 0.3, { 1, 0.95, 0.5 }, 0, true)
  end
  if e.armored and e.def.armor then
    -- A curled roller turns most of it aside in a shower of sparks
    amount = math.max(1, math.floor(amount * e.def.armor + 0.5))
    e.armorHit = 0.12
    sfx("clank", 0.3, 1.8)
    local ax, ay = center(e)
    for _ = 1, 3 do
      effects.particle(ax, ay, (love.math.random() - 0.5) * 120, -love.math.random() * 70, 0.18, { 1, 0.9, 0.55 }, 200, true)
    end
  elseif e.state == "dizzy" then
    amount = math.floor(amount * 1.5 + 0.5) -- soft and uncurled
  end
  if e.elite and e.elite.has.armoured then
    if blasting then
      amount = math.floor(amount * ELITE_BLAST + 0.5) -- plates don't stop a blast
    elseif dx and dx * e.facing < 0 then
      -- Struck from the front: the plates turn most of it aside
      amount = math.max(1, math.floor(amount * ELITE_FRONT + 0.5))
      sfx("clank", 0.25, 1.5)
      local ax, ay = center(e)
      for _ = 1, 2 do
        effects.particle(ax + e.facing * e.body.w / 2, ay, e.facing * (30 + love.math.random() * 60), -love.math.random() * 60, 0.15, { 0.8, 0.88, 1 }, 200, true)
      end
    end
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
  if not (e.def.ground and e.grounded) then
    knock = knock * 0.4 -- in the air they are shoved much less
  end
  if dx and dx ~= 0 and not e.def.knockMul then
    -- A hit shoves the sprite back for a moment
    e.stagger = math.min(0.2, 0.08 + (force or 0) / 2500)
    e.hitDir = dx > 0 and 1 or -1
  end
  if not e.def.dummy and not e.armored then
    local gx, gy = center(e)
    gore.spray(gx, gy, dx or 0, dy or -0.3, gore.color(e), math.min(9, 2 + math.floor(amount / 3)))
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
  if force and force > 0 and knock > 0 and not e.armored and kindMovable(e) then
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
  blasting = true
  for _, e in ipairs(near) do
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
  blasting = false
end

-- Sets an enemy alight: dps burning damage for `time` seconds (a stronger
-- fire replaces a weaker one; it refreshes the time)
function enemies.ignite(e, dps, time)
  if e.dead or e.fireproof then
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
  e.dazed = math.max(e.dazed or 0, time) -- concussive rounds: stars circle its head
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
  for _ = 1, 1 + math.max(1, math.floor(fx and fx.shock or 1)) do
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
    from.zap = 0.4
    enemies.damage(target, math.max(1, math.floor(damage * 0.5 + 0.5)), 0, 0, 0, false, fx)
    target.zap = 0.4
    ax, ay = bx, by
  end
end

-- Singularity Rounds: drags enemies within radius toward (x, y)
function enemies.pull(x, y, radius, speed)
  for _, e in ipairs(near) do
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

-- Status particles ---------------------------------------------------------
-- Each debuff has its own look: frost throws drifting flakes and glints, venom
-- bubbles up, acid drips and sizzles, a shock crackles with sparks, concussion
-- circles its head with stars (drawn in drawDazed). The sprite itself is washed
-- in the status colour by the tint shader in enemies.draw.
-- Monsters make noise while they hunt: sound, first and last gap in seconds
-- (the first right after it notices the hunter), and a pitch (lower for giants)
local VOICES = {
  ghoul = { "ghoul_growl", 3.5, 8, 1 },
  warden = { "ghoul_growl", 3, 6, 0.6 },
  miner = { "miner_yap", 3.5, 8, 1 },
  spitter = { "spitter_gurgle", 4, 10, 1 },
  bloater = { "bloater_wheeze", 4, 9, 1 },
  behemoth = { "bloater_wheeze", 3, 6, 0.6 },
  hopper = { "croak", 4, 9, 1 },
  wisp = { "wisp_crackle", 3, 7, 1 },
}

local function updateVoice(e, dt)
  local voice = VOICES[e.kind]
  if not voice then
    return
  end
  local hunting = e.state == "chase" and e.stun <= 0
  if hunting and e.prevState ~= "chase" then
    e.voiceT = 0.1 + love.math.random() * 0.4 -- (it has just noticed the hunter)
  end
  e.prevState = e.state
  if hunting then
    e.voiceT = (e.voiceT or voice[2]) - dt
    if e.voiceT <= 0 then
      e.voiceT = voice[2] + love.math.random() * (voice[3] - voice[2])
      local vx, vy = center(e)
      audio.playAt(voice[1], vx, vy, e.elite and 1.1 or 0.9, voice[4] * (0.9 + love.math.random() * 0.25) * (e.elite and 0.88 or 1))
    end
  end
end

local function updateStatusFx(e, dt)
  local b = e.body
  local rnd = love.math.random
  -- Bigger monsters throw more
  local size = math.sqrt(b.w * b.h) / 10
  local function chance(rate)
    return rnd() < rate * size * dt
  end
  local function onBody()
    return b.x + rnd() * b.w, b.y + rnd() * b.h
  end
  if e.zap and e.zap > 0 then
    e.zap = e.zap - dt
    if chance(60) then
      local x, y = onBody()
      effects.particle(x, y, (rnd() - 0.5) * 70, (rnd() - 0.5) * 70, 0.08, rnd() < 0.5 and { 0.75, 0.85, 1 } or { 1, 0.95, 0.5 }, 0, true)
    end
  end
  if e.dazed and e.dazed > 0 then
    e.dazed = e.dazed - dt
  end
  if e.slow and e.slow > 0 then
    if chance(7) then
      local x, y = onBody()
      effects.particle(x, y, (rnd() - 0.5) * 6, 4 + rnd() * 6, 0.9, { 0.85, 0.95, 1 }, 6) -- flakes of frost
    end
    if chance(5) then
      local x, y = onBody()
      effects.particle(x, y, 0, 0, 0.22, { 1, 1, 1 }, 0, true) -- a glint
    end
  end
  if e.poisoned then
    if chance(6) then
      local x = b.x + rnd() * b.w
      effects.particle(x, b.y + b.h * (0.4 + rnd() * 0.5), 0, -10 - rnd() * 8, 0.7, { 0.55, 0.95, 0.35 }, -8, true) -- bubbles
    end
    if chance(1.5) then
      local x, y = onBody()
      effects.particle(x, y, (rnd() - 0.5) * 10, -6, 0.6, { 0.25, 0.5, 0.18 }, -4) -- a wisp of green fume
    end
  end
  if e.acid and e.acid > 0 then
    if chance(5) then
      effects.particle(b.x + rnd() * b.w, b.y + b.h * (0.5 + rnd() * 0.5), 0, 0, 0.7, { 0.78, 0.98, 0.18 }, 260) -- a drip falling away
    end
    if chance(3) then
      local x, y = onBody()
      effects.particle(x, y, (rnd() - 0.5) * 16, -14 - rnd() * 10, 0.25, { 0.95, 1, 0.5 }, 40, true) -- sizzle
    end
  end
  if e.burn and chance(2) then
    local x, y = onBody()
    effects.particle(x, y, (rnd() - 0.5) * 8, -12, 0.8, { 0.28, 0.25, 0.25 }, -20) -- smoke
  end
end

-- The tint a monster's sprite is washed in: the blend of every status on it,
-- and how strongly (0 when it has none)
local TINT_FROST, TINT_VENOM, TINT_ACID, TINT_FIRE, TINT_SHOCK = { 0.50, 0.82, 1.0 }, { 0.30, 0.90, 0.22 }, { 0.80, 1.0, 0.12 }, { 1.0, 0.42, 0.08 }, { 0.72, 0.86, 1.0 }

local function statusTint(e, t)
  local r, g, b, w = 0, 0, 0, 0
  local function add(c, weight)
    r, g, b, w = r + c[1] * weight, g + c[2] * weight, b + c[3] * weight, w + weight
  end
  if e.slow and e.slow > 0 then
    add(TINT_FROST, 0.62 * math.min(1, e.slow / 0.6))
  end
  if e.poisoned then
    add(TINT_VENOM, 0.5 * math.min(1, e.poisoned.left / 0.6))
  end
  if e.acid and e.acid > 0 then
    add(TINT_ACID, 0.5 * math.min(1, e.acid / 0.6))
  end
  if e.burn then
    add(TINT_FIRE, 0.30 + 0.14 * math.sin(t * 17 + e.phase))
  end
  if e.zap and e.zap > 0 and math.floor(t * 28) % 2 == 0 then
    add(TINT_SHOCK, 0.9)
  end
  if w == 0 then
    return
  end
  return r / w, g / w, b / w, math.min(0.8, w)
end

local tintShader
local tintTried = false

local function getTintShader()
  if not tintTried then
    tintTried = true
    local ok, shader = pcall(
      love.graphics.newShader,
      [[
      uniform vec3 tint;
      uniform float amount;
      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 c = Texel(tex, uv) * color;
        // Keep the sprite's own shading: dark parts take the tint dark, light parts bright
        float l = dot(c.rgb, vec3(0.30, 0.59, 0.11));
        vec3 toned = tint * (0.40 + 1.0 * l);
        c.rgb = mix(c.rgb, toned, amount);
        return c;
      }
      ]]
    )
    tintShader = ok and shader or nil
  end
  return tintShader
end

-- Stars circling the head of a concussed monster
local function drawDazed(e, t)
  if not (e.dazed and e.dazed > 0) then
    return
  end
  local b = e.body
  local cx, top = b.x + b.w / 2, b.y - 3
  local rx = math.max(4, b.w * 0.35)
  for i = 0, 2 do
    local a = t * 7 + i * 2.094
    local x, y = cx + math.cos(a) * rx, top + math.sin(a) * 2
    local front = math.sin(a) > 0
    love.graphics.setColor(1, 0.92, 0.35, front and 1 or 0.5)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), 2, 2)
    love.graphics.setColor(1, 1, 0.85, front and 1 or 0.5)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 1)
  end
end

-- Bullet hit test: an enemy or an acid glob at the pixel (globs can be shot down)
function enemies.hitTest(px, py)
  for _, e in ipairs(near) do
    local b = e.body
    if not e.dead and e.def.extraHit and e.def.extraHit(e, px, py) then
      e.hitX, e.hitY = px, py -- (a weak point standing outside its body)
      return e
    end
    if not e.dead and px >= b.x and px < b.x + b.w and py >= b.y and py < b.y + b.h and not (e.def.noBodyHit and e.def.noBodyHit(e)) then
      e.hitX, e.hitY = px, py -- (where it was struck: see def.filter)
      return e
    end
    -- A worm can be hit anywhere along its length
    if e.segs and not e.dead and e.state ~= "sleep" then
      for _, sg in ipairs(e.segs) do
        if math.abs(px - sg[1]) <= 2 and math.abs(py - sg[2]) <= 2 then
          return e
        end
      end
    end
  end
  for _, s in ipairs(sticks) do
    if not s.dead and math.abs(px - s.x) <= 3 and math.abs(py - s.y) <= 3 then
      return s
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
  if thing.isStick then
    thing.dead = true -- shot out of the air: it goes off where it is
  elseif thing.isGlob then
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
        local k = (e.def.knockMul or 1) * ((e.def.ground and e.grounded) and 1 or 0.5)
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
  -- Out of pouncing range it is always clawing its way toward the hunter: the
  -- digging never stops, so walls, floors and ceilings only slow it down
  e.digging = false
  if e.state == "chase" and e.stun <= 0 and not e.windT and (e.strikeT or 0) <= 0 and not (dist < def.lungeRange and math.abs(py - cy) < 24) then
    e.digging = true
    e.digTick = (e.digTick or 0) - dt
    if e.digTick <= 0 then
      e.digTick = 0.2
      e.digSide = -(e.digSide or 1)
      local d = math.max(1, dist)
      local nx, ny = (px - cx) / d, (py - cy) / d
      local k = def.scale or 1
      -- (a bite big enough for its whole body to follow through)
      local r = math.max(def.clawDig * 1.8 * k, b.h * 0.8)
      local dug = destruction.dig(world, cx + nx * (b.w / 2 + r * 0.7), cy + ny * (b.h / 2 + r * 0.5 - 4), r, def.clawPower + 1, nx, ny)
      if dug > 0 then
        sfx("hit", 0.3, 0.5 + love.math.random() * 0.2)
        effects.particle(cx + nx * 8, cy + ny * 8, nx * 40 + (love.math.random() - 0.5) * 40, ny * 40 - 20, 0.3, { 0.5, 0.45, 0.4 }, 200, true)
      end
      if ny < -0.5 and e.grounded then
        b.vy = -def.jump * 0.8 -- (clawing upward, it hauls itself up)
      end
    end
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
        sfx("hit", 0.5, 0.6)
        clawDig(e, world, false)
        e.rakes = 1
        if e.digVert and e.digVert ~= 0 then
          -- Stuck below or above the hunter: the claws tear up or down through the rock too
          local k = def.scale or 1
          local dy = e.digVert
          destruction.dig(world, cx, dy < 0 and b.y - 3 or b.y + b.h + 2, def.clawDig * 1.3 * k, def.clawPower, 0, dy)
          if dy < 0 then
            b.vy = -def.lungeLift * 0.6
          end
        end
        e.digVert = nil
      end
    elseif e.grounded and e.cooldown <= 0 and dist < def.lungeRange and math.abs(py - cy) < 24 then
      e.windT = def.windup
      e.cooldown = def.lungeCooldown + def.windup
    elseif e.grounded and e.cooldown <= 0 and (e.stuckT or 0) > 0.8 then
      -- Can't get at the hunter: dig toward him with the claws
      e.stuckT = 0
      e.windT = def.windup
      e.cooldown = def.lungeCooldown + def.windup
      e.digVert = py < cy - 20 and -1 or (py > cy + 20 and 1 or 0)
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
  -- Stuck: pressing on into a wall (or standing under/over the hunter) for a while
  if e.state == "chase" and e.stun <= 0 and want and not e.windT and ((blocked and want ~= 0 and not blocker) or (want == 0 and math.abs(py - cy) > 20)) then
    e.stuckT = (e.stuckT or 0) + dt
  else
    e.stuckT = math.max(0, (e.stuckT or 0) - dt * 2)
  end
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
  e.phase = e.phase + dt * (math.abs(b.vx) / 7 + (e.digging and 5 or 0.8))
  -- Dragging hands kick up a little dust
  if e.grounded and math.abs(b.vx) > 8 and love.math.random() < dt * 8 then
    effects.particle(cx - e.facing * (5 + love.math.random() * 3), b.y + b.h - 1, -e.facing * 6, -8 - love.math.random() * 10, 0.4, { 0.42, 0.40, 0.40 }, 60)
  end
end

-- Swarm bats cannot see through rock, so when the hunter is walled off they
-- follow a flow field: a breadth-first search over coarse cells out from the
-- hunter (shared by every bat, rebuilt a couple of times a second) that gives
-- each open cell the number of steps to him. A bat steps to its lowest neighbour.
local flowDirection
do
local FLOW_CELL, FLOW_RADIUS = 8, 44
local flow = { t = -1, cx = nil, cy = nil, dist = {}, world = nil, solid = {} }
local FLOW_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function flowKey(gx, gy)
  return gx * 65536 + gy
end

local function flowBlocked(world, gx, gy)
  local k = flowKey(gx, gy)
  local v = flow.solid[k]
  if v == nil then
    local x, y = gx * FLOW_CELL + FLOW_CELL / 2, gy * FLOW_CELL + FLOW_CELL / 2
    v = world:isSolid(math.floor(x), math.floor(y)) or world:isSolid(math.floor(x - 3), math.floor(y - 3)) or world:isSolid(math.floor(x + 3), math.floor(y - 3)) or world:isSolid(math.floor(x - 3), math.floor(y + 3)) or world:isSolid(math.floor(x + 3), math.floor(y + 3))
    flow.solid[k] = v
  end
  return v
end

local function flowRebuild(world, px, py)
  local pgx, pgy = math.floor(px / FLOW_CELL), math.floor(py / FLOW_CELL)
  flow.world, flow.cx, flow.cy, flow.t = world, pgx, pgy, love.timer.getTime()
  flow.solid = {}
  local dist = {}
  flow.dist = dist
  local queue, head = { pgx, pgy }, 1
  dist[flowKey(pgx, pgy)] = 0
  while head <= #queue do
    local gx, gy = queue[head], queue[head + 1]
    head = head + 2
    local d = dist[flowKey(gx, gy)]
    if d < FLOW_RADIUS then
      for _, dir in ipairs(FLOW_DIRS) do
        local nx, ny = gx + dir[1], gy + dir[2]
        local k = flowKey(nx, ny)
        if not dist[k] and not flowBlocked(world, nx, ny) and (dir[1] == 0 or dir[2] == 0 or (not flowBlocked(world, gx + dir[1], gy) and not flowBlocked(world, gx, gy + dir[2]))) then
          dist[k] = d + 1
          queue[#queue + 1] = nx
          queue[#queue + 1] = ny
        end
      end
    end
  end
end

-- The unit direction a bat at (x, y) should fly to get round the rock to the
-- hunter at (px, py), or nil if there is no known way (too far, or sealed in)
flowDirection = function(world, x, y, px, py)
  local pgx, pgy = math.floor(px / FLOW_CELL), math.floor(py / FLOW_CELL)
  if flow.world ~= world or not flow.cx or love.timer.getTime() - flow.t > 0.45 or math.abs(pgx - flow.cx) + math.abs(pgy - flow.cy) > 3 then
    flowRebuild(world, px, py)
  end
  local gx, gy = math.floor(x / FLOW_CELL), math.floor(y / FLOW_CELL)
  local here = flow.dist[flowKey(gx, gy)]
  local best, bx, by = here or math.huge, nil, nil
  if not here then
    -- (in rock or off the field: look for any reached neighbour to head for)
    best = math.huge
  end
  for _, dir in ipairs(FLOW_DIRS) do
    local d = flow.dist[flowKey(gx + dir[1], gy + dir[2])]
    if d and d < best then
      best, bx, by = d, dir[1], dir[2]
    end
  end
  if not bx then
    return nil
  end
  -- aim at the next cell's centre (so it hugs corners rather than clipping them)
  local tx, ty = (gx + bx) * FLOW_CELL + FLOW_CELL / 2 - x, (gy + by) * FLOW_CELL + FLOW_CELL / 2 - y
  local d = math.max(1, math.sqrt(tx * tx + ty * ty))
  return tx / d, ty / d
end
end

enemies.flowDirection = flowDirection -- (the Needle's fliers use it too: src.needlemobs)

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
    -- Walled off from the hunter: follow the flow field round the rock (see
    -- flowDirection); in the open, weave in a staggering orbit like the swarm
    local fx, fy
    if not e.seesPlayer then
      fx, fy = flowDirection(world, cx, cy, px, py - 4)
    end
    if fx then
      tx, ty = fx * def.speed, fy * def.speed
    else
      e.orbitT = (e.orbitT or love.math.random() * 2) - dt
      if e.orbitT <= 0 then
        e.orbitT = 0.6 + love.math.random() * 1.2
        e.orbitDir = love.math.random() < 0.5 and -1 or 1
      end
      local k = (e.orbitDir or 1) * def.speed * 0.45
      tx, ty = tx - (py - 4 - cy) / d * k, ty + (px - cx) / d * k
    end
    -- Stuck against terrain: bolt off in a random direction for a moment
    e.stuckT = (e.stuckT or 0) + dt
    if e.stuckT >= 0.4 then
      local mx, my = cx - (e.lastX or cx), cy - (e.lastY or cy)
      e.lastX, e.lastY, e.stuckT = cx, cy, 0
      if mx * mx + my * my < 16 and dist > 24 and e.stun <= 0 then
        e.unstickT = 0.5
        local a = love.math.random() * math.pi * 2
        e.unstickX, e.unstickY = math.cos(a) * def.speed, math.sin(a) * def.speed
      end
    end
    if (e.unstickT or 0) > 0 then
      e.unstickT = e.unstickT - dt
      tx, ty = e.unstickX, e.unstickY
    end
    if e.seesPlayer and dist < def.chargeRange and e.attackCd <= 0 and e.stun <= 0 then
      e.state = "lock"
      e.timer = def.lockTime
      sfx("bat_screech")
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
          sfx("hit", 0.4, 0.5)
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
-- The ordinary bloater is nearly passive: it drifts about, a lot, leaving a
-- train of gas behind it. Hurt it and it lets out a burst, runs from the
-- hunter and leaks much more for a while, so the paths it floats through are
-- walled off by gas the hunter has to cross.
local function updateWanderingBloater(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  e.phase = e.phase + dt * 2
  if e.lastHp and e.hp < e.lastHp then
    -- Struck: a burst of gas, then away
    e.fleeT = 5
    e.gasUp = 9
    fluids.addGas(cx, cy, 0.8, 32)
    local d = math.max(1, dist)
    e.dirX, e.dirY = (cx - px) / d, (cy - py) / d
    e.wanderT = 1.5
  end
  e.lastHp = e.hp
  e.fleeT = math.max(0, (e.fleeT or 0) - dt)
  e.gasUp = math.max(0, (e.gasUp or 0) - dt)
  local fleeing = e.fleeT > 0
  e.puffT = (e.puffT or 0.4) - dt
  if e.puffT <= 0 then
    if e.gasUp > 0 then
      e.puffT = 0.3
      fluids.addGas(cx, cy + 3, 0.5, 22)
    else
      e.puffT = 0.55 + love.math.random() * 0.2
      fluids.addGas(cx, cy + 3, 0.3, 14)
    end
  end
  e.state = fleeing and "chase" or "wander" -- (chase: the wheeze of a frightened bloater)
  e.wanderT = (e.wanderT or 0) - dt
  if e.wanderT <= 0 or not e.dirX then
    local a = love.math.random() * math.pi * 2
    e.dirX, e.dirY = math.cos(a), math.sin(a) * 0.6
    e.wanderT = 1.2 + love.math.random() * 2.2
  end
  local speed = def.speed * (fleeing and 2.2 or 1.1)
  local tx, ty = e.dirX * speed, e.dirY * speed + math.sin(e.phase) * 8
  if e.stun <= 0 then
    local step = def.accel * dt * 1.5
    b.vx = b.vx < tx and math.min(b.vx + step, tx) or math.max(b.vx - step, tx)
    b.vy = b.vy < ty and math.min(b.vy + step, ty) or math.max(b.vy - step, ty)
    e.facing = b.vx >= 0 and 1 or -1
  end
  local collide = collider(e, world)
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.5
    e.dirX = -e.dirX
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.5
    e.dirY = -e.dirY
  end
end

local function updateBloater(e, dt, world, player, px, py)
  if e.kind == "bloater" and not e.def.boss then
    return updateWanderingBloater(e, dt, world, player, px, py)
  end
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
      sfx("bat_screech", 1, 0.5)
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
    if not e.seesPlayer then
      local fx, fy = flowDirection(world, cx, cy, px, py - 4) -- (round the rock, not into it)
      if fx then
        tx, ty = fx * def.speed, fy * def.speed
      end
    end
    if e.stun <= 0 then
      local step = def.accel * dt
      b.vx = b.vx < tx and math.min(b.vx + step, tx) or math.max(b.vx - step, tx)
      b.vy = b.vy < ty and math.min(b.vy + step, ty) or math.max(b.vy - step, ty)
    end
    e.facing = tx >= 0 and 1 or -1
    if e.attackCd <= 0 and dist < def.chargeRange and e.stun <= 0 then
      e.state = "lock"
      e.timer = def.lockTime
      sfx("bat_screech", 1, 0.5)
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
      sfx("explosion", 0.5, 0.6)
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
    local fx, fy
    if not e.seesPlayer then
      fx, fy = flowDirection(world, cx, cy, px, py - 4)
    end
    if fx then
      tx, ty = fx * def.speed, fy * def.speed
    end
    -- A staggering orbit, near the hunter or not: a sideways weave that swaps
    -- direction now and then keeps the bats moving and shakes them off terrain
    e.orbitT = (e.orbitT or love.math.random() * 2) - dt
    if e.orbitT <= 0 then
      e.orbitT = 0.5 + love.math.random() * 1.1
      e.orbitDir = love.math.random() < 0.5 and -1 or 1
      e.orbitAmt = 0.5 + love.math.random() * 0.9
    end
    local ox, oy = -(py - 4 - cy) / d, (px - cx) / d
    local k = (e.orbitDir or 1) * (e.orbitAmt or 1) * def.speed * (fx and 0.15 or 0.8)
    tx, ty = tx + ox * k, ty + oy * k
  end
  -- Stuck on terrain: barely moved for a moment, so it bolts in a random direction
  e.stuckT = (e.stuckT or 0) + dt
  if e.stuckT >= 0.35 then
    local mx, my = cx - (e.lastX or cx), cy - (e.lastY or cy)
    e.lastX, e.lastY = cx, cy
    e.stuckT = 0
    if mx * mx + my * my < 16 and dist > 24 and e.stun <= 0 then
      e.unstickT = 0.5
      local a = love.math.random() * math.pi * 2
      e.unstickX, e.unstickY = math.cos(a) * def.speed, math.sin(a) * def.speed
    end
  end
  if (e.unstickT or 0) > 0 then
    e.unstickT = e.unstickT - dt
    tx, ty = e.unstickX, e.unstickY
  elseif swarm then
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
    if not e.seesPlayer then
      local fx, fy = flowDirection(world, cx, cy, px, py - 4) -- (round the rock, not into it)
      if fx then
        dx, dy, wob = fx, fy, wob * 0.3
      end
    end
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
    source = e.kind,
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
    source = e.kind,
  }
  effects.particle(cx, cy, math.cos(ang) * 30, math.sin(ang) * 30, 0.25, { 0.55, 0.95, 0.35 }, 0, true)
end

-- A drop of her slime lets go and falls (gravity, no gas: it is a projectile like a glob)
local function dropSlime(e, x, y)
  local def = e.def
  globs[#globs + 1] = {
    isGlob = true,
    drip = true,
    x = x,
    y = y,
    vx = (e.body.vx or 0) * 0.25,
    vy = 20,
    gravity = 520,
    damage = math.max(1, math.floor(def.dripDamage * e.dmgMul + 0.5)),
    life = 5,
    source = e.kind,
  }
end

-- Splitting is mitosis: she swells, pinches and pulls apart (queenfig draws it from e.mito) and
-- cannot be hurt until the halves are free and a moment beyond (e.iframes, see enemies.damage)
local MITOSIS = 1.5
local MITOSIS_AFTER = 0.7
local function startSplit(e)
  local gen = (e.gen or 0) + 1
  e.mito = { t = 0, dur = MITOSIS, childW = e.def.spriteW * QUEEN_SCALES[gen + 1] }
  e.novaWind, e.dashT, e.fanLeft, e.vulnerable = nil, nil, nil, false
  sfx("bat_screech", 0.9, 0.35)
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
    local side = i == 1 and -1 or 1
    q.body.x, q.body.y = math.floor(cx + side * size * 0.55 - size / 2), math.floor(cy - size / 2) -- (where the halves of the mitosis ended)
    q.body.vx, q.body.vy = side * 110, -20
    q.mito, q.qm, q.qd = nil, nil, nil
    q.iframes = MITOSIS_AFTER -- (untouchable a moment after, too)
    q.orbit = -math.pi / 2 + (i == 1 and -1 or 1) * (0.35 + love.math.random() * 0.5)
    q.qs, q.qt, q.atk, q.atkI, q.dashT, q.fanLeft, q.recoverSet, q.vulnerable = "hover", 1.5 + love.math.random(), nil, love.math.random(0, 2), nil, nil, nil, nil
    q.puffT, q.novaWind, q.flash = nil, nil, 0
    q.minions = {}
    q.phase = love.math.random() * 10
    removePhysics(q) -- (rebuilt at its new size next frame)
    brood[i] = q
  end
  sfx("bat_screech", 1, 0.5)
  effects.ring(cx, cy, 40, { 0.85, 0.95, 0.35 })
  fluids.addGas(cx, cy, 0.7, 24)
  for _ = 1, 10 do
    local ang = love.math.random() * math.pi * 2
    effects.particle(cx, cy, math.cos(ang) * (30 + love.math.random() * 60), math.sin(ang) * (30 + love.math.random() * 60), 0.6, { 0.72, 0.85, 0.3 }, 100, true)
  end
  effects.popup(cx, cy - size / 2 - 6, "SPLIT", { 0.85, 0.95, 0.35 })
end

-- Sulfur Queen. She fights in a cycle: she hovers high over the arena, picks an
-- attack and TELLS you (she stops dead and swells, glowing), carries it out,
-- and then she is spent: for a couple of seconds she sinks down to where the
-- hunter can reach her, dazed and taking 50% more damage. Hit her hard in
-- those windows; the rest of the time it is about reading the attack and
-- getting out of its way (a dodge roll slips through globs and her dash):
--   fan     three fans of gas globs with a two-glob gap to slip through
--   dash    she locks on and barrels across the arena in a line, leaving gas
--   bloom   she swells and bursts: a ring of globs and a cloud of gas
--   vents   gas columns crack open across the arena (they show a warning first)
--   spawn   calls bloaters (and later wisps)
-- Each stage (by health) adds attacks and shortens the pauses. Below a third
-- she splits in two (see splitQueen); the remnants only fan and dash. She is
-- immune to fire, flies through rock and platforms, and never leaves her arena.
local QUEEN_CYCLES = {
  { "fan", "dash", "fan", "spawn" },
  { "fan", "bloom", "dash", "vents", "fan", "dash" },
  { "fan", "dash", "bloom", "dash", "vents", "fan", "dash", "bloom" },
}
local REMNANT_CYCLE = { "fan", "dash", "fan" }
local QUEEN_WIND = { fan = 0.9, dash = 1.1, bloom = 1.3, vents = 0.7, spawn = 0.7 }

-- Starts the attack once its telegraph is over
local function queenAttack(e, px, py, aimAng, stage, gen, sf)
  local def, b = e.def, e.body
  local a = e.arena
  local cx, cy = center(e)
  local atk = e.atk
  e.qs = "attack"
  if atk == "fan" then
    e.fanLeft = gen > 0 and 2 or (stage == 3 and 4 or 3)
    e.fanT = 0
  elseif atk == "dash" then
    e.dashT = 0.9
    sfx("bat_screech", 0.9, 0.7)
    effects.ring(cx, cy, 40 * sf + 14, { 0.9, 0.95, 0.4 })
  elseif atk == "bloom" then
    sfx("explosion", 0.7, 0.5)
    effects.ring(cx, cy, 110 * sf, { 0.85, 0.95, 0.35 })
    fluids.addGas(cx, cy, 1, 70 * sf)
    local n = 14
    local gap = love.math.random(1, n)
    for i = 1, n do
      if i ~= gap and i ~= gap % n + 1 then
        fireGlob(e, (i / n) * math.pi * 2 + e.phase, def.globSpeed * 0.65)
      end
    end
    e.qs = "recover"
    e.qt = 0.1
  elseif atk == "vents" then
    if a and gen == 0 then
      local n = 1 + stage
      local lo, hi = a.x0 + 110, a.x1 - 110
      local seg = (hi - lo) / n
      for k = 1, n do
        local x = lo + (k - 0.5 + (love.math.random() - 0.5) * 0.7) * seg
        fluids.addColumn(x, 64, a.top + 12, a.floorY - 2, 1.4, 7)
      end
      sfx("explosion", 0.5, 0.5)
    end
    e.qs = "recover"
    e.qt = 0.1
  elseif atk == "spawn" then
    local alive = {}
    for _, m in ipairs(e.minions or {}) do
      if not m.dead then
        alive[#alive + 1] = m
      end
    end
    e.minions = alive
    for side = -1, 1, 2 do
      if #e.minions < 3 + stage then
        local kind = "bloater" -- (never wisps: their flames set her own gas alight)
        local m = enemies.spawn(kind, cx + side * 30 * sf - 7, cy + 10 * sf, e.toughness * 0.4, e.level)
        m.state = "chase"
        e.minions[#e.minions + 1] = m
        effects.ring(cx + side * 30 * sf, cy + 10 * sf, 16, { 0.8, 0.92, 0.3 })
      end
    end
    e.qs = "recover"
    e.qt = 0.1
  end
end

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
  if (e.iframes or 0) > 0 then
    e.iframes = e.iframes - dt
  end
  if e.state == "sleep" then
    local inside = not a or (px > a.x0 and px < a.x1 and py > a.top and py < a.floorY)
    if inside and dist < def.sight then
      e.state = "chase"
      e.stage = 1
      e.group = e.group or { alive = 1 }
      e.qs, e.qt = "hover", 2.5
      sfx("bat_screech", 1, 0.4)
    else
      b.vx, b.vy = 0, math.sin(e.phase) * 4
      return
    end
  end
  if not e.mito and frac < (gen == 0 and 0.33 or 0.5) and gen < def.splitDepth then
    startSplit(e)
  end
  if stage > (e.stage or 1) then
    -- A new stage: a roar and a burst of gas
    sfx("bat_screech", 1, 0.4)
    effects.ring(cx, cy, 70 * sf, { 0.8, 0.92, 0.3 })
    fluids.addGas(cx, cy, 1, 40 * sf)
  end
  e.stage = stage
  e.qs = e.qs or "hover"
  e.qt = e.qt or 2
  local timeScale = 1 + gen * 0.35
  local aimAng = math.atan2(py - cy, px - cx)
  e.aimAng = aimAng -- (her eyes follow the hunter)
  e.vulnerable = e.qs == "recover" and e.qt > 0.2 and not e.mito

  -- A faint leak from her sac, no more
  e.puffT = (e.puffT or 1.5) - dt
  if e.puffT <= 0 then
    e.puffT = 1.4
    fluids.addGas(cx, cy + 14 * sf, 0.3, 9 * sf)
  end
  -- Gas trails behind her wherever she goes, thicker the faster she moves
  local mv = math.sqrt(b.vx * b.vx + b.vy * b.vy)
  e.trailGas = (e.trailGas or 0) - dt
  if mv > 25 and e.trailGas <= 0 then
    e.trailGas = 0.16
    fluids.addGas(cx - b.vx / mv * b.w * 0.3, cy - b.vy / mv * b.h * 0.3 + 4, 0.3 * math.min(1, mv / 150), 8 * sf)
  end
  -- Drips grow on her and let go: each is a falling drop that hurts (queenfig draws the strands from e.qd)
  e.qd = e.qd or {}
  for i = 1, queenfig.dripCount(b.w) do
    local prev = e.qd[i] or queenfig.dripOffset(i)
    local p = prev + dt / def.dripPeriod
    if p >= 1 then
      p = p - 1
    end
    if prev < 0.8 and p >= 0.8 and not e.mito then
      local x, y = queenfig.dripTip(e, i)
      dropSlime(e, x, y)
    end
    e.qd[i] = p
  end

  local wantX, wantY, speed = cx, cy, 0
  local dashing = false
  if e.mito then
    -- Mitosis: she holds still, swelling and pinching in two, then lets go
    local m = e.mito
    m.t = m.t + dt
    e.novaWind = nil
    b.vx, b.vy = b.vx * math.max(0, 1 - 6 * dt), b.vy * math.max(0, 1 - 6 * dt)
    if love.math.random() < dt * 25 then
      local ang = love.math.random() * math.pi * 2
      effects.particle(cx + math.cos(ang) * b.w * 0.5, cy + math.sin(ang) * b.h * 0.5, math.cos(ang) * 20, math.sin(ang) * 20, 0.4, { 0.8, 0.92, 0.35 }, 0, true)
    end
    if m.t >= m.dur then
      splitQueen(e)
      return
    end
  elseif e.qs == "hover" then
    -- High over the arena, drifting along it after the hunter
    local ax = px + math.sin(e.phase * 0.35 + (e.orbit or 0)) * 150
    local ay = a and (a.top + 90 + math.sin(e.phase * 0.5) * 18) or (py - 130)
    if a then
      ax = math.max(a.x0 + 100, math.min(a.x1 - 100, ax))
    end
    wantX, wantY, speed = ax, ay, 90 + 30 * (stage - 1)
    e.qt = e.qt - dt
    if e.qt <= 0 then
      local cycle = gen > 0 and REMNANT_CYCLE or QUEEN_CYCLES[stage]
      e.atkI = (e.atkI or 0) % #cycle + 1
      e.atk = cycle[e.atkI]
      e.qs = "windup"
      e.qt = QUEEN_WIND[e.atk] * timeScale
      e.qtTotal = e.qt
      e.dashAng = aimAng
      sfx("bat_screech", 0.6, 0.55)
    end
  elseif e.qs == "windup" then
    -- The telegraph: she stops and swells, glowing; a dash shows its line, which
    -- follows the hunter until the last third of a second and then locks
    e.qt = e.qt - dt
    e.novaWind = e.qt
    if e.atk == "dash" and e.qt > 0.3 then
      e.dashAng = aimAng
    end
    b.vx, b.vy = b.vx * math.max(0, 1 - 8 * dt), b.vy * math.max(0, 1 - 8 * dt)
    if love.math.random() < dt * 30 then
      local ang = love.math.random() * math.pi * 2
      effects.particle(cx + math.cos(ang) * 30 * sf, cy + math.sin(ang) * 30 * sf, -math.cos(ang) * 40, -math.sin(ang) * 40, 0.4, { 0.85, 0.95, 0.35 }, 0, true)
    end
    if e.qt <= 0 then
      e.novaWind = nil
      queenAttack(e, px, py, aimAng, stage, gen, sf)
    end
    wantX, wantY, speed = cx, cy, 0
  elseif e.qs == "attack" then
    if e.atk == "fan" then
      e.fanT = e.fanT - dt
      if e.fanT <= 0 and e.fanLeft > 0 then
        e.fanT = 0.5 * timeScale
        e.fanLeft = e.fanLeft - 1
        local n = gen > 0 and 5 or (stage == 3 and 11 or 9)
        local arc = gen > 0 and 1.0 or 1.5
        local gap = love.math.random(2, n - 2) -- two neighbouring shots left out
        for i = 1, n do
          if i ~= gap and i ~= gap + 1 then
            fireGlob(e, aimAng + (i - (n + 1) / 2) / (n - 1) * arc, def.globSpeed)
          end
        end
        sfx("shot_pistol", 0.5, 0.45)
      end
      if e.fanLeft <= 0 and e.fanT <= 0 then
        e.qs = "recover"
        e.qt = 0.1
      end
    elseif e.atk == "dash" then
      dashing = true
      e.dashT = e.dashT - dt
      b.vx, b.vy = math.cos(e.dashAng) * 560, math.sin(e.dashAng) * 560
      if love.math.random() < dt * 40 then
        effects.particle(cx, cy, 0, 0, 0.4, { 0.72, 0.85, 0.3 }, 0, true)
      end
      e.dashGas = (e.dashGas or 0) - dt
      if e.dashGas <= 0 then
        e.dashGas = 0.07
        fluids.addGas(cx, cy, 0.5, 12 * sf)
      end
      if e.dashT <= 0 then
        e.qs = "recover"
        e.qt = 0.1
        b.vx, b.vy = b.vx * 0.3, b.vy * 0.3
        e.afterDash = true
      end
    end
  end
  if e.qs == "recover" and not e.mito then
    -- Spent: she sinks to the hunter's height, dazed and open to attack. The
    -- first instant after an attack sets how long this lasts.
    if e.qt <= 0.1 and not e.recoverSet then
      e.recoverSet = true
      e.qt = (({ 2.8, 2.3, 1.9 })[stage] + (e.afterDash and 0.8 or 0)) * timeScale
      e.afterDash = nil
    end
    e.qt = e.qt - dt
    e.dazed = math.max(e.dazed or 0, e.qt)
    local side = px >= cx and -1 or 1
    wantX, wantY, speed = px + side * 90 * (0.4 + sf), py - 40, 110
    if e.qt <= 0 then
      e.qs = "hover"
      e.qt = ({ 1.9, 1.5, 1.1 })[stage] * timeScale
      e.recoverSet = nil
      e.dazed = 0
    end
  end

  if not dashing then
    local d = math.max(1, math.sqrt((wantX - cx) ^ 2 + (wantY - cy) ^ 2))
    local sp = math.min(speed, d * 2.2)
    local tx, ty = (wantX - cx) / d * sp, (wantY - cy) / d * sp + math.sin(e.phase) * 5
    if speed == 0 then
      tx, ty = 0, 0
    end
    if e.stun <= 0 and e.qs ~= "windup" then
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
  local function nothing()
    return false
  end
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
        sfx("spitter_spit", 1, 0.95 + love.math.random() * 0.1)
      end
      e.cooldown = def.reload
    end
  elseif e.cooldown <= 0 and e.seesPlayer then
    e.windup = def.windup
    sfx("spitter_charge", 1, 0.95 + love.math.random() * 0.1)
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
  e.touching = props.overlapping(b.x - 1, b.y - 1, b.w + 2, b.h + 2, e.touching)
  for p in pairs(e.touching) do
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

-- Tunnel worm: a long, thin burrower that bores through anything but bedrock
-- and masonry. While it has rock around its head it steers freely (toward the
-- hunter, lunging when close); the moment its head breaks into open air it is
-- just a thrown thing, carried by its momentum and gravity, until it hits the
-- ground or a wall and digs back in.
local function wormTouching(world, x, y)
  -- Any rock within about five pixels of the head?
  if world:isSolid(x, y) then
    return true
  end
  for i = 0, 7 do
    local a = i * math.pi / 4
    if world:isSolid(x + math.floor(math.cos(a) * 4 + 0.5), y + math.floor(math.sin(a) * 4 + 0.5)) then
      return true
    end
  end
  return false
end

local function angleDiff(a, b)
  return (a - b + math.pi) % (2 * math.pi) - math.pi
end

local function wormInit(e)
  if e.segs then
    return
  end
  local b = e.body
  e.wx, e.wy = b.x + b.w / 2, b.y + b.h / 2
  e.ang = love.math.random() * math.pi * 2
  e.segs = {}
  for i = 1, e.def.segments do
    e.segs[i] = { e.wx, e.wy }
  end
  e.air = false
  e.lungeT, e.lungeCd, e.digged = 0, 0, 0
end

local function updateWorm(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  wormInit(e)
  local dist = math.sqrt((px - e.wx) ^ 2 + (py - e.wy) ^ 2)
  -- Its sounds are only heard as it gets close
  local function wormSound(name, volume)
    local near = math.max(0, 1 - dist / 260)
    if near > 0.03 then
      sfx(name, volume * near ^ 1.5)
    end
  end
  e.phase = e.phase + dt * 9
  e.lungeCd = math.max(0, e.lungeCd - dt)
  local r = love.math.random

  if e.state == "sleep" then
    -- Coiled in the rock until the hunter comes near (no line of sight needed:
    -- it feels the footsteps through the stone)
    if dist < def.sight then
      e.state = "chase"
      wormSound("worm_wake", 0.9)
      for _ = 1, 8 do
        effects.particle(e.wx, e.wy, (r() - 0.5) * 50, -r() * 40, 0.5, { 0.42, 0.36, 0.30 }, 200)
      end
    else
      return
    end
  elseif e.state == "chase" and dist > def.forget then
    e.state = "wander"
    e.wanderAng = r() * math.pi * 2
  elseif e.state == "wander" and dist < def.sight then
    e.state = "chase"
  end

  if e.air then
    -- Out in the open: momentum and gravity only
    b.vy = math.min(b.vy + config.gravity * 0.225 * dt, 520) -- (70% lighter than before, so it can fly)
    local drag = math.max(0, 1 - 0.3 * dt)
    b.vx, b.vy = b.vx * drag, b.vy * drag -- (the only place it loses speed)
    e.wx, e.wy = e.wx + b.vx * dt, e.wy + b.vy * dt
    e.ang = math.atan2(b.vy, b.vx)
    local hx, hy = math.floor(e.wx), math.floor(e.wy)
    if hardTerrain(world, hx - 2, hy - 2, 4, 4) then
      -- Bedrock and masonry can't be dug: it glances off
      e.wx, e.wy = e.wx - b.vx * dt, e.wy - b.vy * dt
      b.vx, b.vy = -b.vx * 0.4, -b.vy * 0.4
    elseif wormTouching(world, hx, hy) then
      -- Hit the ground or a wall: it plunges in and can steer again
      e.air = false
      e.digged = 0
      wormSound("worm_dig", 0.9)
      for _ = 1, 6 do
        effects.particle(e.wx, e.wy, (r() - 0.5) * 70, -r() * 60, 0.5, { 0.42, 0.36, 0.30 }, 300)
      end
    end
  else
    -- Burrowing: steer toward the hunter (or drift when it has lost him)
    local target = math.atan2(py + player.body.vy * 0.25 - 3 - e.wy, px + player.body.vx * 0.25 - e.wx)
    if e.state == "chase" and e.lungeT <= 0 and dist < 190 then
      -- About to break the surface close to the hunter: a burst of speed, to leap at him
      local ax, ay = math.floor(e.wx + math.cos(e.ang) * 8), math.floor(e.wy + math.sin(e.ang) * 8)
      if not world:isSolid(ax, ay) and e.lungeCd <= 0 then
        e.lungeT = 0.35
      end
    end
    if e.state == "wander" then
      e.wanderAng = e.wanderAng + (r() - 0.5) * 2 * dt
      target = e.wanderAng
    end
    local speed = e.state == "wander" and def.speed * 0.5 or def.speed
    if e.lungeT > 0 then
      speed = def.lungeSpeed
      e.lungeT = e.lungeT - dt
      if e.lungeT <= 0 then
        e.lungeCd = def.lungeCooldown
      end
    elseif e.state == "chase" and dist < def.lungeRange and e.lungeCd <= 0 and e.stun <= 0 then
      e.lungeT = def.lungeTime
      wormSound("worm_lunge", 0.9)
    end
    if e.stun > 0 then
      speed = speed * 0.3
    end
    local turn = def.turn * (e.lungeT > 0 and 0.7 or 1)
    local want = -angleDiff(e.ang, target)
    e.ang = e.ang + math.max(-turn * dt, math.min(turn * dt, want)) + math.sin(e.phase * 0.35) * 1.1 * dt
    local dx, dy = math.cos(e.ang), math.sin(e.ang)
    local travel = speed * dt
    local steps = math.max(1, math.ceil(travel / 1.5))
    for _ = 1, steps do
      local nx, ny = e.wx + dx * travel / steps, e.wy + dy * travel / steps
      if hardTerrain(world, math.floor(nx) - 2, math.floor(ny) - 2, 4, 4) then
        e.ang = e.ang + (r() < 0.5 and 1 or -1) * (1.2 + r() * 0.8)
        break
      end
      e.wx, e.wy = nx, ny
      e.digged = e.digged - travel / steps
      if e.digged <= 0 then
        e.digged = 3.2
        destruction.dig(world, e.wx + dx * 3, e.wy + dy * 3, def.digRadius * (e.lungeT > 0 and 1.25 or 1), 40, dx, dy)
        if r() < 0.5 then
          effects.particle(e.wx - dx * 2, e.wy - dy * 2, -dx * 20 + (r() - 0.5) * 30, -dy * 20 - r() * 20, 0.4, { 0.40, 0.34, 0.28 }, 260)
        end
      end
    end
    b.vx, b.vy = dx * speed, dy * speed
    if r() < dt * 1.2 then
      wormSound("worm_dig", 0.5)
    end
    -- Broke through into open air: it flies out on the speed it had
    if not wormTouching(world, math.floor(e.wx), math.floor(e.wy)) then
      e.air = true
      e.lungeT = 0
      wormSound("worm_burst", 0.9)
      for _ = 1, 8 do
        effects.particle(e.wx, e.wy, (r() - 0.5) * 80, -r() * 60, 0.5, { 0.42, 0.36, 0.30 }, 300)
      end
    end
  end

  e.facing = b.vx >= 0 and 1 or -1
  b.x, b.y = math.floor(e.wx - b.w / 2), math.floor(e.wy - b.h / 2)

  -- The body follows the head, each segment held a fixed distance behind the
  -- last (and drooping while it is in the air)
  local lx, ly = e.wx, e.wy
  for _, s in ipairs(e.segs) do
    if e.air then
      s[2] = s[2] + 140 * dt
    end
    local dx, dy = s[1] - lx, s[2] - ly
    local d = math.sqrt(dx * dx + dy * dy)
    if d > def.segGap then
      s[1], s[2] = lx + dx / d * def.segGap, ly + dy / d * def.segGap
    end
    lx, ly = s[1], s[2]
  end
end

-- Skeleton miner: shambles after the hunter, keeping its distance, and lobs
-- sticks of lit dynamite (which bounce and go off a moment later, or at once
-- if shot in the air)
local function throwDynamite(e, px, py)
  local def = e.def
  local cx, cy = center(e)
  local hx, hy = cx + e.facing * 4, cy - 6
  local dx, dy = px - hx, py - hy
  local T = math.max(0.45, math.min(1.0, math.abs(dx) / 170))
  local g = def.throwGravity
  sticks[#sticks + 1] = {
    isStick = true,
    isGlob = true, -- (to bullets a stick is a shootable projectile, like an acid glob)
    x = hx,
    y = hy,
    vx = dx / T,
    vy = (dy - 0.5 * g * T * T) / T,
    grav = g,
    fuse = def.fuse,
    spin = 0,
    mul = e.dmgMul * def.blast,
    dig = 16, -- (about half the bite the hunter's own dynamite takes; same blast)
    digPower = 2.5,
  }
  sfx("worm_lunge", 0.5, 1.6)
end

-- The hunter's own dynamite (the Prospector's): thrown from (x, y) toward
-- (tx, ty), it bounces and goes off 1.4 s later in a bigger blast that digs
-- a crater in any rock (and hurts him too, if he is close). Shooting it in
-- the air sets it off early, like a miner's.
function enemies.throwStick(x, y, tx, ty)
  local dx, dy = tx - x, ty - y
  local d = math.max(1, math.sqrt(dx * dx + dy * dy))
  local speed = math.min(320, 120 + d * 1.2)
  sticks[#sticks + 1] = {
    isStick = true,
    isGlob = true,
    x = x,
    y = y,
    vx = dx / d * speed,
    vy = dy / d * speed - 70,
    grav = 520,
    fuse = 1.4,
    spin = 0,
    mul = 1.6,
    dig = 33, -- (3x the bite out of the ground; the blast hurting things is unchanged)
    digPower = 3.5,
    cause = "selfblast",
  }
  sfx("worm_lunge", 0.5, 1.6)
end

local function updateMiner(e, dt, world, player, px, py)
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
  e.throwT = math.max(0, (e.throwT or 0) - dt)

  local want = 0
  if e.stun > 0 then
    want = nil
    e.windT = nil
  elseif e.state == "chase" then
    local dir = px >= cx and 1 or -1
    e.facing = dir
    if e.windT then
      want = 0
      e.windT = e.windT - dt
      if e.windT <= 0 then
        e.windT = nil
        e.throwT = 0.35
        throwDynamite(e, px, py)
      end
    else
      if dist > def.holdMax then
        want = dir
      elseif dist < def.holdMin then
        want = -dir -- backs away to keep throwing range
      end
      if e.cooldown <= 0 and e.seesPlayer and dist < def.throwRange and e.grounded then
        e.windT = def.windup
        e.cooldown = def.throwCooldown + def.windup
        sfx("miner_light", 0.7)
      end
    end
  else
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
      if e.state == "chase" and want == e.facing then
        b.vy = -def.jump
      else
        e.wander = -want
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
  e.phase = e.phase + dt * (math.abs(b.vx) / 6 + 0.6)
end

-- Cave roller: a plated, grey pillbug. It crawls, then curls into a ball and
-- rolls at the hunter, bouncing off the walls; curled or rolling, its armour
-- takes most of the damage. Spent, it uncurls dizzy and soft.
local function updateRoller(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local collide = collider(e, world)
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
  e.armored = e.state == "curl" or e.state == "roll"
  e.contactMul = e.state == "roll" and 1.3 or 0.4
  e.armorHit = math.max(0, (e.armorHit or 0) - dt)

  if e.state == "idle" and e.seesPlayer and dist < def.sight then
    e.state = "chase"
  elseif e.state == "chase" and dist > def.forget then
    e.state = "idle"
  end

  local want = 0
  if e.state == "chase" and e.stun <= 0 then
    local dir = px >= cx and 1 or -1
    e.facing = dir
    want = dir
    if e.grounded and e.cooldown <= 0 and e.seesPlayer and dist < def.rollRange then
      e.state = "curl"
      e.timer = def.curlTime
      sfx("roller_curl", 0.8)
    end
  elseif e.state == "curl" then
    e.facing = px >= cx and 1 or -1
    e.timer = e.timer - dt
    e.spin = (e.spin or 0) + (math.sin(e.timer * 40) > 0 and 1 or -1) * dt * 3
    if e.timer <= 0 then
      e.state = "roll"
      e.timer = def.rollTime
      b.vx = e.facing * def.rollSpeed
      b.vy = -80
      e.grounded = false
      sfx("roller_roll", 0.8)
    end
  elseif e.state == "roll" then
    e.timer = e.timer - dt
    e.spin = (e.spin or 0) + e.facing * dt * 16
    if e.grounded then
      local target = e.facing * def.rollSpeed
      b.vx = b.vx < target and math.min(b.vx + 700 * dt, target) or math.max(b.vx - 700 * dt, target)
      if love.math.random() < dt * 14 then
        effects.particle(cx - e.facing * 4, b.y + b.h - 1, -e.facing * 14, -10 - love.math.random() * 14, 0.4, { 0.42, 0.40, 0.40 }, 60)
      end
    end
    if e.timer <= 0 then
      e.state = "dizzy"
      e.timer = def.dizzyTime
      e.cooldown = def.rollCooldown
    end
  elseif e.state == "dizzy" then
    e.timer = e.timer - dt
    e.dazed = math.max(e.dazed or 0, e.timer)
    want = nil
    b.vx = b.vx * math.max(0, 1 - 6 * dt)
    if e.timer <= 0 then
      e.state = "chase"
      e.dazed = 0
      e.cooldown = def.rollCooldown + 1.2 -- a breather before it rolls again
    end
  elseif e.state == "idle" then
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.wander = love.math.random() < 0.5 and 0 or (love.math.random() < 0.5 and -1 or 1)
      e.timer = 1 + love.math.random() * 2
    end
    want = e.wander or 0
    if want ~= 0 then
      e.facing = want
    end
  elseif e.stun > 0 then
    want = nil
  end

  if e.state ~= "roll" then
    if want and e.grounded then
      local target = want * (e.state == "chase" and def.speed or def.speed * 0.4)
      local step = 700 * dt
      b.vx = b.vx < target and math.min(b.vx + step, target) or math.max(b.vx - step, target)
    elseif e.grounded then
      b.vx = b.vx * math.max(0, 1 - 8 * dt)
    end
  end
  b.vy = math.min(b.vy + config.gravity * dt, 450)

  local blocked, blocker = Body.moveX(b, collide, b.vx * dt, e.state == "roll" and 2 or 3)
  if blocked then
    if blocker and e.state == "roll" then
      props.damage(blocker, 8)
      props.push(blocker, e.facing * 900, -200)
    end
    if e.state == "roll" then
      -- Bounces off the wall, usually back toward the hunter
      e.facing = (px >= cx and 1 or -1)
      if love.math.random() < 0.35 then
        e.facing = -e.facing
      end
      b.vx = e.facing * def.rollSpeed * 0.9
      b.vy = -70
      sfx("clank", 0.35, 1.5)
      for _ = 1, 4 do
        effects.particle(cx, cy, (love.math.random() - 0.5) * 90, -love.math.random() * 50, 0.2, { 1, 0.9, 0.55 }, 200, true)
      end
    elseif e.grounded and want and want ~= 0 then
      if e.state == "chase" then
        b.vy = -def.jump
      else
        e.wander = -want
      end
      b.vx = 0
    else
      b.vx = 0
    end
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = 0
  end
  if e.grounded and b.vy >= 0 and e.state ~= "roll" then
    Body.snapDown(b, collide, 4)
  end
  e.phase = e.phase + dt * (math.abs(b.vx) / 5 + 0.8)
end

-- Piranha: swims in water (no gravity, steering toward a target), and
-- flops about out of it (gravity, short hops)
local function updatePiranha(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local collide = collider(e, world)
  local cx, cy = center(e)
  if e.state == "sleep" then
    e.state = "idle"
  end
  local wet = fluids.waterAt(cx, cy)
  e.inWater = wet
  -- The hunter counts as in the water if any of him is: head, middle or feet.
  -- It aims at his feet when those are the wet part
  local pb = player.body
  local feetWet = fluids.waterAt(px, pb.y + pb.h - 1)
  local preyWet = fluids.waterTouching(pb.x, pb.y, pb.w, pb.h)
  local ty0 = feetWet and (pb.y + pb.h - 2) or py
  local dx, dy = px - cx, ty0 - cy
  local dist = math.max(1, math.sqrt(dx * dx + dy * dy))
  local r = love.math.random
  local dashing = e.dashT and e.dashT > 0
  if dashing then
    e.dashT = e.dashT - dt
  end
  if wet then
    e.flopT = nil
    if e.stun > 0 then
      b.vx, b.vy = b.vx * (1 - math.min(1, 3 * dt)), b.vy * (1 - math.min(1, 3 * dt))
    elseif not dashing then
      -- Before its first bite it only goes after a hunter in the water;
      -- once it has bitten (e.aggro) it follows him anywhere
      local reach = e.aggro and def.chase or (e.state == "chase" and def.forget or def.sight)
      local hunting = not player.dead and (preyWet or e.aggro) and dist < reach and (e.seesPlayer or e.state == "chase" or e.aggro)
      e.state = hunting and "chase" or "idle"
      if not hunting then
        e.aggro = nil
      end
      local tx, ty
      if hunting and dist < def.dashRange and e.cooldown <= 0 then
        -- A dart at the hunter
        e.dashT = def.dashTime
        e.aggro = true
        b.vx, b.vy = dx / dist * def.dashSpeed, dy / dist * def.dashSpeed
        e.cooldown = def.dashCooldown * (0.8 + r() * 0.4)
        sfx("hit", 0.25, 1.7)
      elseif hunting then
        tx, ty = dx / dist * def.speed, dy / dist * def.speed
      else
        -- Idle: drift about, turning now and then
        e.timer = e.timer - dt
        if e.timer <= 0 or not e.heading then
          e.timer = 1 + r() * 2
          e.heading = r() * math.pi * 2
        end
        tx, ty = math.cos(e.heading) * def.speed * 0.35, math.sin(e.heading) * def.speed * 0.2
      end
      if tx then
        local k = math.min(1, dt * 4)
        b.vx = b.vx + (tx - b.vx) * k
        b.vy = b.vy + (ty - b.vy) * k
      end
      if e.aggro and not preyWet and hunting then
        -- The hunter is out of the water: leap out of the surface after him
        local above = fluids.waterAt(cx, cy - b.h - 2)
        if not above and e.cooldown <= 0 then
          e.cooldown = 0.5
          local dir = dx < 0 and -1 or 1
          b.vx = dir * math.min(def.dashSpeed * 0.6, math.abs(dx) * 3 + 40)
          b.vy = -def.flopLift * 1.7
          sfx("hit", 0.25, 1.4)
        end
      end
      -- Otherwise it never swims out of the water on its own: turn back at the edge
      if not (e.aggro and not preyWet) then
        local sx = b.vx > 0 and 1 or -1
        if not fluids.waterAt(cx + sx * (b.w / 2 + 2), cy) then
          b.vx = -sx * math.abs(b.vx) * 0.5
          e.heading = e.heading and (math.pi - e.heading)
        end
        local sy = b.vy > 0 and 1 or -1
        if not fluids.waterAt(cx, cy + sy * (b.h / 2 + 2)) then
          b.vy = -sy * math.abs(b.vy) * 0.5
          e.heading = e.heading and -e.heading
        end
      end
    else
      local drag = math.exp(-dt * 2)
      b.vx, b.vy = b.vx * drag, b.vy * drag
    end
  else
    -- Out of the water: it falls, and flops along in short hops
    b.vy = math.min(b.vy + config.gravity * dt, 450)
    e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
    if e.grounded then
      b.vx = b.vx * math.max(0, 1 - 12 * dt)
      e.flopT = (e.flopT or r() * 0.3) - dt
      if e.flopT <= 0 and e.stun <= 0 then
        e.flopT = def.flopTime * (0.7 + r() * 0.6)
        local dir
        if not player.dead and dist < (e.aggro and def.chase or def.sight) then
          dir = dx < 0 and -1 or 1
          e.state = "chase"
        else
          dir = r() < 0.5 and -1 or 1
        end
        b.vx = dir * def.flopSpeed * (0.7 + r() * 0.6)
        b.vy = -def.flopLift * (0.7 + r() * 0.5)
        e.grounded = false
        e.facing = dir
      end
    end
  end
  if math.abs(b.vx) > 3 then
    e.facing = b.vx < 0 and -1 or 1
  end
  if Body.moveX(b, collide, b.vx * dt, wet and 0 or 1) then
    b.vx = -b.vx * 0.3
  end
  if Body.moveY(b, collide, b.vy * dt) then
    if wet then
      b.vy = -b.vy * 0.3
    else
      b.vy = 0
    end
  end
end

-- The Marble Colossus ------------------------------------------------------------
local GOLEM_ATTACKS = {
  -- name = { windup, act, recover } in seconds
  swipe = { 0.65, 0.25, 0.55 },
  throw = { 0.8, 0.2, 0.6 },
  stomp = { 0.95, 0.3, 0.9 },
  beam = { 1.15, 2.2, 1.0 },
}

-- Where its eye is, and the hand that throws
local function golemEye(e)
  local b = e.body
  return b.x + b.w / 2 + e.facing * 9, b.y + 17
end

local function golemHurtPlayer(e, player, dmg, fx, fy)
  if player.dead then
    return false
  end
  if player:isDodging() then
    player:dodged()
    return false
  end
  return player:hurt(math.max(1, math.floor(dmg * e.dmgMul + 0.5)), fx, fy, "golem")
end

local function golemSpawnMinis(e, world, n)
  local a = e.arena
  local cx = center(e)
  e.minisLeft = n
  e.miniT = 0.2
  e.minis = e.minis or {}
  e.miniSide = e.miniSide or -1
  e.shellX0 = a and a.x0 + 40 or cx - 360
  e.shellX1 = a and a.x1 - 40 or cx + 360
end

local function golemStartShell(e, world, n)
  e.gs, e.sub, e.gt = "shell", nil, 0
  e.invuln, e.vulnerable = true, false
  e.body.vx = 0
  sfx("explosion", 0.8, 0.45)
  effects.ring(center(e), e.body.y + e.body.h / 2, 90, { 0.6, 0.85, 1 })
  effects.popup(center(e), e.body.y - 10, "SHELL", { 0.6, 0.85, 1 })
  require("src.camera").shake(0.5)
  golemSpawnMinis(e, world, n)
end

local function golemFloorAt(world, x, fromY)
  return world:findGround(math.floor(x), math.floor(fromY))
end

local function golemBeginAttack(e, name, px, py)
  local t = GOLEM_ATTACKS[name]
  e.gs, e.sub, e.gt, e.gd = name, "wind", t[1], t[1]
  e.last = name
  if name == "beam" then
    local ex, ey = golemEye(e)
    local base = math.atan2(py - ey, px - ex)
    local s = love.math.random() < 0.5 and -1 or 1
    e.beamA0, e.beamA1 = base - s * 0.95, base + s * 0.95
    e.beamAng = e.beamA0
    sfx("bat_screech", 0.5, 0.35)
  elseif name == "stomp" then
    sfx("explosion", 0.3, 0.4)
  end
end

-- The effect of an attack as its wind-up ends
local function golemAct(e, world, player, px, py, stage)
  local b = e.body
  local f = e.facing
  local cx, cy = center(e)
  local def = e.def
  if e.gs == "swipe" then
    sfx("hit", 0.9, 0.4)
    b.vx = f * 50
    local x0, x1 = cx + f * 8, cx + f * (b.w / 2 + 62)
    local rx, rw = math.min(x0, x1), math.abs(x1 - x0)
    local pb = player.body
    if overlaps(rx, b.y + 14, rw, b.h - 14, pb.x, pb.y, pb.w, pb.h) then
      if golemHurtPlayer(e, player, def.damage, cx, cy) then
        pb.vx, pb.vy = f * 240, -150
      end
    end
    require("src.camera").shake(0.25)
    for i = 1, 8 do
      effects.particle(cx + f * (20 + i * 6), b.y + b.h - 6, f * 40, -20 - love.math.random() * 40, 0.5, { 0.7, 0.68, 0.74 }, 300)
    end
  elseif e.gs == "throw" then
    sfx("hit", 0.7, 0.5)
    local n = stage
    local sx, sy = cx + f * 16, b.y + 4
    local T = math.max(0.6, math.min(1.2, math.abs(px - sx) / 260))
    for i = 1, n do
      local aim = px + (i - (n + 1) / 2) * 46
      local vx = (aim - sx) / T
      local vy = (py - sy) / T - 0.5 * 520 * T
      golemStones[#golemStones + 1] = { x = sx, y = sy, vx = vx, vy = vy, life = 4, spin = love.math.random() * 6, dmg = def.damage * 0.75 }
    end
  elseif e.gs == "stomp" then
    sfx("explosion", 0.8, 0.4)
    require("src.camera").shake(0.55)
    local dirs = { (px < cx) and -1 or 1 }
    if stage >= 2 then
      dirs[2] = -dirs[1]
    end
    for _, d in ipairs(dirs) do
      golemWaves[#golemWaves + 1] = { x = cx + d * 34, dir = d, speed = 170 + 30 * stage, life = 2.8, hit = false, dmg = def.damage }
    end
    for i = 1, 14 do
      effects.particle(cx + (love.math.random() - 0.5) * 50, b.y + b.h - 2, (love.math.random() - 0.5) * 120, -40 - love.math.random() * 80, 0.6, { 0.7, 0.68, 0.74 }, 400)
    end
  elseif e.gs == "beam" then
    sfx("explosion", 0.4, 1.6)
  end
end

local function updateGolem(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local collide = collider(e, world)
  local cx, cy = center(e)
  local dist = math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
  local a = e.arena
  e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
  local frac = e.hp / e.maxHp
  local stage = frac > 0.66 and 1 or (frac > 0.33 and 2 or 3)
  if e.state == "idle" or e.state == "sleep" then
    local inside = not a or (px > a.x0 and px < a.x1 and py > a.top and py < a.floorY)
    if inside and dist < def.sight then
      e.state, e.gs, e.gt = "chase", "walk", 1.5
    else
      b.vy = math.min(b.vy + config.gravity * dt, 450)
      if Body.moveY(b, collide, b.vy * dt) then
        b.vy = 0
      end
      return
    end
  end
  e.gs = e.gs or "walk"
  e.gt = (e.gt or 1) - dt
  e.minis = e.minis or {}
  -- The two shell phases
  if e.gs ~= "shell" and not e.shell1 and frac < 0.66 then
    e.shell1 = true
    golemStartShell(e, world, 4)
  elseif e.gs ~= "shell" and not e.shell2 and frac < 0.33 then
    e.shell2 = true
    golemStartShell(e, world, 6)
  end
  local want = 0
  local speed = def.speed * (1 + 0.25 * (stage - 1))
  if e.gs == "shell" then
    e.facing = px < cx and -1 or 1
    -- little golems file in from the arena's sides, one after another
    if (e.minisLeft or 0) > 0 then
      e.miniT = e.miniT - dt
      if e.miniT <= 0 then
        e.miniT = 0.9
        e.minisLeft = e.minisLeft - 1
        e.miniSide = -e.miniSide
        local x = e.miniSide < 0 and e.shellX0 or e.shellX1
        local y = (a and a.floorY or cy + 40) - 40
        local m = enemies.spawn("minigolem", x, golemFloorAt(world, x, y), 1, e.level)
        m.state = "chase"
        m.seesPlayer = true
        e.minis[#e.minis + 1] = m
        effects.ring(x, m.body.y + 10, 16, { 0.6, 0.85, 1 })
        sfx("clank", 0.6, 0.7)
      end
    end
    local alive = 0
    for _, m in ipairs(e.minis) do
      if not m.dead then
        alive = alive + 1
      end
    end
    if (e.minisLeft or 0) <= 0 and alive == 0 then
      e.invuln = false
      e.gs, e.gt = "rest", 2.2
      e.vulnerable = true
      sfx("explosion", 0.9, 0.55)
      require("src.camera").shake(0.5)
      effects.ring(cx, cy, 80, { 0.6, 0.85, 1 })
      effects.popup(cx, b.y - 10, "SHELL BROKEN", { 1, 0.9, 0.6 })
      for _ = 1, 24 do
        effects.particle(cx + (love.math.random() - 0.5) * 50, cy + (love.math.random() - 0.5) * 70, (love.math.random() - 0.5) * 160, -love.math.random() * 120, 0.8, { 0.65, 0.88, 1 }, 300, true)
      end
    end
  elseif e.gs == "rest" then
    e.vulnerable = true
    if e.gt <= 0 then
      e.vulnerable = false
      e.gs, e.gt = "walk", 0.8
    end
  elseif e.gs == "walk" then
    e.facing = px < cx and -1 or 1
    local dx = px - cx
    if math.abs(dx) > 46 then
      want = e.facing
    end
    if e.gt <= 0 and e.grounded then
      local near = math.abs(dx) < 96 and math.abs(py - cy) < 70
      local pool = near and { "swipe", "swipe", "swipe", "stomp", "throw", "beam" } or { "throw", "throw", "stomp", "stomp", "beam", "beam" }
      for _ = 1, 4 do
        local pick = pool[love.math.random(#pool)]
        if pick ~= e.last then
          golemBeginAttack(e, pick, px, py)
          break
        end
      end
      if e.gs == "walk" then
        e.gt = 0.3
      end
    end
  else
    -- an attack: wind up, act, recover
    local t = GOLEM_ATTACKS[e.gs]
    if e.sub == "wind" then
      if e.gs ~= "beam" or true then
        e.facing = px < cx and -1 or 1
      end
      if e.gt <= 0 then
        e.sub, e.gt, e.gd = "act", t[2], t[2]
        e.actAt = true
      end
    elseif e.sub == "act" then
      if e.actAt then
        e.actAt = false
        golemAct(e, world, player, px, py, stage)
      end
      if e.gs == "beam" then
        local k = 1 - math.max(0, e.gt) / e.gd
        e.beamAng = e.beamA0 + (e.beamA1 - e.beamA0) * k
        local ex, ey = golemEye(e)
        local dx, dy = math.cos(e.beamAng), math.sin(e.beamAng)
        local len = 0
        while len < 900 do
          len = len + 3
          if world:isSolid(math.floor(ex + dx * len), math.floor(ey + dy * len)) then
            break
          end
        end
        e.beamEnd = { ex + dx * len, ey + dy * len }
        e.beamHitT = (e.beamHitT or 0) - dt
        -- the hunter's distance from the beam
        local pcx, pcy = player:center()
        local u = math.max(0, math.min(len, (pcx - ex) * dx + (pcy - ey) * dy))
        local ddx, ddy = pcx - (ex + dx * u), pcy - (ey + dy * u)
        if ddx * ddx + ddy * ddy < 81 and e.beamHitT <= 0 then
          e.beamHitT = 0.4
          golemHurtPlayer(e, player, def.damage * 0.8, ex, ey)
        end
        if love.math.random() < dt * 40 then
          effects.particle(ex + dx * len, ey + dy * len, (love.math.random() - 0.5) * 80, -30 - love.math.random() * 60, 0.35, { 1, 0.6, 0.85 }, 200, true)
        end
      end
      if e.gt <= 0 then
        e.sub, e.gt, e.gd = "rec", t[3], t[3]
        e.beamEnd = nil
      end
    elseif e.sub == "rec" then
      if e.gt <= 0 then
        e.gs, e.sub = "walk", nil
        e.gt = (stage == 1 and 1.3 or (stage == 2 and 1.0 or 0.75)) + love.math.random() * 0.5
      end
    end
  end
  -- Lumbering: slow to speed up, heavy underfoot
  if e.grounded then
    local target = want * speed
    local step = 220 * dt
    b.vx = b.vx < target and math.min(b.vx + step, target) or math.max(b.vx - step, target)
    if want == 0 then
      b.vx = b.vx * math.max(0, 1 - 6 * dt)
    end
  end
  b.vy = math.min(b.vy + config.gravity * dt, 450)
  local blocked = Body.moveX(b, collide, b.vx * dt, 6)
  if blocked then
    b.vx = 0
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = 0
  end
  if e.grounded and b.vy >= 0 then
    Body.snapDown(b, collide, 4)
  end
  if a then
    b.x = math.max(a.x0 + 6, math.min(a.x1 - b.w - 6, b.x))
  end
  -- Footfalls
  local step = math.floor(e.phase / math.pi)
  e.phase = e.phase + dt * (math.abs(b.vx) / 14 + 0.5)
  if e.grounded and math.abs(b.vx) > 8 and math.floor(e.phase / math.pi) ~= step then
    sfx("hit", 0.25, 0.3)
    require("src.camera").shake(0.06)
    effects.particle(cx + (love.math.random() - 0.5) * 30, b.y + b.h - 1, 0, -10 - love.math.random() * 14, 0.4, { 0.6, 0.58, 0.64 }, 100)
  end
end

-- Thrown stones fly in arcs and shatter; the stone wave runs along the floor
local function updateGolemShots(dt, world, player)
  local pb = player.body
  for i = #golemStones, 1, -1 do
    local s = golemStones[i]
    s.life = s.life - dt
    s.vy = s.vy + 520 * dt
    s.spin = s.spin + dt * 8
    local steps = math.max(1, math.ceil(math.max(math.abs(s.vx), math.abs(s.vy)) * dt / 2))
    local gone = false
    for _ = 1, steps do
      s.x, s.y = s.x + s.vx * dt / steps, s.y + s.vy * dt / steps
      if not player.dead and overlaps(s.x - 4, s.y - 4, 8, 8, pb.x, pb.y, pb.w, pb.h) then
        if player:isDodging() then
          player:dodged()
        else
          player:hurt(math.max(1, math.floor(s.dmg + 0.5)), s.x - s.vx * 0.01, s.y, "golem")
          gone = true
        end
      elseif world:isSolid(math.floor(s.x), math.floor(s.y)) then
        gone = true
      end
      if gone then
        break
      end
    end
    if gone or s.life <= 0 then
      audio.playAt("hit", s.x, s.y, 0.6, 0.5)
      for _ = 1, 10 do
        effects.particle(s.x, s.y, (love.math.random() - 0.5) * 140, -love.math.random() * 100, 0.6, { 0.78, 0.76, 0.82 }, 400)
      end
      table.remove(golemStones, i)
    end
  end
  for i = #golemWaves, 1, -1 do
    local w = golemWaves[i]
    w.life = w.life - dt
    w.x = w.x + w.dir * w.speed * dt
    w.y = world:findGround(math.floor(w.x), math.floor((w.y or pb.y) - 30))
    local blockedAhead = world:isSolid(math.floor(w.x + w.dir * 4), math.floor(w.y - 6))
    if not w.hit and not player.dead and overlaps(w.x - 7, w.y - 18, 14, 18, pb.x, pb.y, pb.w, pb.h) then
      if player:isDodging() then
        player:dodged()
      else
        w.hit = true
        if player:hurt(math.max(1, math.floor(w.dmg + 0.5)), w.x - w.dir * 8, w.y - 6, "golem") then
          pb.vy = -230
          pb.vx = w.dir * 120
        end
      end
    end
    if love.math.random() < dt * 40 then
      effects.particle(w.x, w.y - 2, (love.math.random() - 0.5) * 30, -40 - love.math.random() * 50, 0.4, { 0.74, 0.72, 0.78 }, 300)
    end
    if w.life <= 0 or blockedAhead then
      table.remove(golemWaves, i)
    end
  end
end

local UPDATE = {
  piranha = updatePiranha,
  worm = updateWorm,
  miner = updateMiner,
  roller = updateRoller,
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
  golem = updateGolem,
  minigolem = updateGhoul,
  wisp = updateWisp,
}

-- Before the physics step: moves each stand-in to its enemy via velocity (like
-- the hunter's), so physics objects get proper contact responses
function enemies.syncPhysics(dt)
  for _, e in ipairs(near) do
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
  dorm.t = dorm.t - dt
  if dorm.t <= 0 then
    dorm.t = dorm.every
    dorm.sweep(px, py)
  end
  for i = #near, 1, -1 do
    near[i] = nil
  end
  for _, e in ipairs(list) do
    local b = e.body
    if not e.dead and math.abs(b.x - px) < HIT_RANGE and math.abs(b.y - py) < HIT_RANGE then
      near[#near + 1] = e
    end
  end
  for i = #list, 1, -1 do
    local e = list[i]
    if e.dead then
      table.remove(list, i)
    else
      local cx, cy = center(e)
      -- (An awake Queen is never frozen: she dashes back to the hunter from anywhere in her arena)
      if (math.abs(cx - px) < ACTIVE_RANGE and math.abs(cy - py) < ACTIVE_RANGE) or (e.kind == "queen" and e.state ~= "sleep") or (e.def.alwaysActive and e.state ~= "sleep") then
        e.flash = math.max(0, e.flash - dt)
        e.stagger = math.max(0, (e.stagger or 0) - dt)
        e.spitT = math.max(0, (e.spitT or 0) - dt)
        e.stun = math.max(0, e.stun - dt)
        e.cooldown = math.max(0, e.cooldown - dt)
        e.ignoreProps = props.overlapping(e.body.x, e.body.y, e.body.w, e.body.h, e.ignoreProps)
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
        sndX, sndY = cx, cy
        UPDATE[e.kind](e, (e.slow and e.slow > 0) and dt * 0.45 or dt, world, player, px, py)
        propImpacts(e, dt)
        updateBurn(e, dt)
        updatePoison(e, dt)
        updateStatusFx(e, dt)
        updateVoice(e, dt)
        sndX, sndY = nil, nil
        if e.elite then
          updateElite(e, dt)
        end
        if not e.def.dummy then
          updateMotes(e, dt)
        end
        -- Touching the hunter hurts him
        local b = e.body
        if not player.dead and e.state ~= "sleep" and overlaps(b.x, b.y, b.w, b.h, pb.x, pb.y, pb.w, pb.h) then
          if e.kind == "piranha" then
            e.aggro = true
          end
          local hx, hy = center(e)
          local hurt = e.def.damage and player:hurt(math.floor(e.def.damage * e.dmgMul * (e.contactMul or 1) + 0.5), hx, hy, e.kind)
          if hurt then
            player.lastEnemy = e
          end
          if hurt and e.def.retreat then
            e.state = "retreat"
            e.timer = e.def.retreat
            e.attackCd = e.def.chargeCooldown
          end
        end
        -- A worm's whole length hurts, not just its head
        if e.segs and e.state ~= "sleep" and not player.dead then
          for _, sg in ipairs(e.segs) do
            if overlaps(sg[1] - 1, sg[2] - 1, 2, 2, pb.x, pb.y, pb.w, pb.h) then
              player:hurt(math.floor(e.def.damage * e.def.bodyDamage * e.dmgMul + 0.5), sg[1], sg[2], e.kind)
              break
            end
          end
        end
      elseif e.phys then
        -- Frozen far from the hunter: its physics stand-in goes (one is made
        -- again when he comes near), so it doesn't drift or cost anything
        removePhysics(e)
      end
    end
  end

  if enemies.afterUpdate then
    enemies.afterUpdate(dt, world, player, px, py)
  end

  -- Dynamite: arcs, bounces, and goes off when the fuse runs out (or when shot)
  for i = #sticks, 1, -1 do
    local s = sticks[i]
    s.fuse = s.fuse - dt
    s.vy = s.vy + s.grav * dt
    if fluids.waterAt(s.x, s.y) then
      local k = math.exp(-4.5 * dt) -- (water drags a thrown stick to a slow sink)
      s.vx, s.vy = s.vx * k, s.vy * k
    end
    s.spin = s.spin + dt * (s.vx > 0 and 9 or -9)
    local steps = math.max(1, math.ceil(math.max(math.abs(s.vx), math.abs(s.vy)) * dt / 2))
    for _ = 1, steps do
      local nx = s.x + s.vx * dt / steps
      if world:isSolid(math.floor(nx), math.floor(s.y)) then
        s.vx = -s.vx * 0.4
      else
        s.x = nx
      end
      local ny = s.y + s.vy * dt / steps
      if world:isSolid(math.floor(s.x), math.floor(ny)) then
        s.vy = math.abs(s.vy) < 40 and 0 or -s.vy * 0.35
        s.vx = s.vx * 0.7
      else
        s.y = ny
      end
    end
    if love.math.random() < dt * 40 then
      effects.particle(s.x, s.y - 4, (love.math.random() - 0.5) * 20, -10 - love.math.random() * 20, 0.25, { 1, 0.6, 0.2 }, 0, true)
    end
    if s.fuse <= 0 or s.dead then
      table.remove(sticks, i)
      require("src.bullets").blast(s.x, s.y, 1, s.mul, s.dig, s.digPower, s.cause or "dynamite")
    end
  end

  for i = #globs, 1, -1 do
    local g = globs[i]
    g.life = g.life - dt
    g.vy = g.vy + g.gravity * dt
    if fluids.waterAt(g.x, g.y) then
      local k = math.exp(-5 * dt) -- (and a glob loses its speed in water)
      g.vx, g.vy = g.vx * k, g.vy * k
    end
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
        player:hurt(g.damage, g.x - g.vx * 0.01, g.y, g.source)
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
  updateGolemShots(dt, world, player)
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
-- (The pose is the creature's own table, refilled each time it is asked for:
-- a few dozen ghouls making fifteen fresh tables twice a frame was one of
-- the bigger sources of garbage.)
local function ghoulPose(e)
  local b, f = e.body, e.facing
  local def = e.def
  local t = e.phase
  local moving = e.grounded and math.abs(b.vx) > 8
  local wind = e.windT and (1 - e.windT / def.windup) or 0 -- 0 -> 1 while rearing back
  local strike = (e.strikeT or 0) / def.strike -- 1 -> 0 after the lunge
  local mid = b.x + b.w / 2
  local pose = e.pose
  if not pose then
    pose = { pelvis = { 0, 0 }, shoulder = { 0, 0 }, head = { 0, 0 }, feet = { { 0, 0 }, { 0, 0 } }, hands = { { 0, 0 }, { 0, 0 } } }
    e.pose = pose
  end
  pose.f, pose.wind, pose.strike, pose.moving = f, wind, strike, moving
  local bob = moving and math.abs(math.sin(t)) * 1.0 or math.sin(t * 0.5) * 0.4
  local lean = 2.4 - 3.4 * wind + 2.4 * strike
  local pelvis, shoulder, head = pose.pelvis, pose.shoulder, pose.head
  pelvis[1], pelvis[2] = mid - f * 1, b.y + 11.5 + bob * 0.3
  shoulder[1], shoulder[2] = mid + f * lean, b.y + 6 + bob * 0.6 + wind * 1.2
  head[1], head[2] = shoulder[1] + f * (3 + strike - wind), shoulder[2] - 2 + math.sin(t * 0.7) * 0.5 + wind * 0.5
  -- Feet shuffle along the ground, set wide, lifting only a little
  local ground = b.y + b.h - 1
  for i = 1, 2 do
    local ph = t + (i - 1) * math.pi
    local swing = moving and math.sin(ph) * 3 or (i == 1 and 2 or -1.5)
    local lift = (moving and math.cos(ph) > 0) and math.cos(ph) * 2 or 0
    local foot = pose.feet[i]
    foot[1], foot[2] = mid + f * swing, ground - lift
  end
  -- Arms: trailing and dragging behind; raised behind the head when rearing
  -- back; thrown forward in the strike
  local sx, sy = shoulder[1], shoulder[2] + 1
  for i = 1, 2 do
    local drag = (moving and math.sin(t + i) * 1.2 or 0)
    local restX, restY = sx - f * (5 + i * 1.8 + drag), ground - (i - 1)
    local backX, backY = sx - f * (4 + wind * 2 + i), sy - 4 - wind * 3 + i * 0.6
    local fwdX, fwdY = sx + f * (5 + 6 * (1 - (1 - strike) ^ 2) + i), sy + 0.5 + i * 1.2 - strike
    local hand = pose.hands[i]
    hand[1] = lerp(lerp(restX, backX, wind), fwdX, strike)
    hand[2] = lerp(lerp(restY, backY, wind), fwdY, strike)
    if e.digging then
      -- Raking at the rock ahead, one arm then the other
      local sw = math.sin(t * 2.2 + i * math.pi)
      hand[1] = sx + f * (6 + sw * 2.5)
      hand[2] = sy + 1 + (sw * 0.5 + 0.5) * 4 - 1
    end
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

-- The tunnel worm: a ring-banded pink body that thins to a point, ending in a
-- round blind head with a ring of teeth around its maw
local WORM = {
  skin = { 0.74, 0.52, 0.48 },
  ring = { 0.56, 0.36, 0.36 },
  top = { 0.88, 0.68, 0.62 },
  head = { 0.62, 0.38, 0.36 },
  maw = { 0.22, 0.07, 0.09 },
  tooth = { 0.94, 0.90, 0.80 },
}

local function drawWorm(e)
  if e.state == "sleep" or not e.segs then
    return -- coiled out of sight in the rock
  end
  local white = e.flash > 0
  local function col(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local n = #e.segs
  -- Tail to head, so each segment overlaps the one behind it: thin, tapering
  -- to a single pixel at the tail
  for i = n, 1, -1 do
    local s = e.segs[i]
    local k = 1 - (i - 1) / n -- 1 at the neck, 0 at the tail
    local size = k > 0.5 and 3 or (k > 0.2 and 2 or 1)
    local o = size / 2
    col(i % 2 == 0 and WORM.ring or WORM.skin)
    px(s[1] - o, s[2] - o, size, size)
    if size == 3 and i % 2 == 1 then
      col(WORM.top)
      px(s[1] - o, s[2] - o, 2, 1)
    end
  end
  -- The head: a small round knob with a pinprick maw ringed with teeth
  local hx, hy = e.wx, e.wy
  local fx, fy = math.cos(e.ang), math.sin(e.ang)
  col(WORM.head)
  px(hx - 2, hy - 2, 4, 4)
  px(hx - 1, hy - 3, 2, 1)
  px(hx - 1, hy + 2, 2, 1)
  col(WORM.maw)
  px(hx + fx * 1.6 - 0.5, hy + fy * 1.6 - 0.5)
  col(WORM.tooth)
  for k = 0, 3 do
    local a = e.ang + (k - 1.5) * 0.9
    px(hx + math.cos(a) * 2.6 - 0.5, hy + math.sin(a) * 2.6 - 0.5)
  end
end

-- The skeleton miner: a bony figure in a rusted hard hat with a lamp, tattered
-- rags and a pickaxe over one shoulder; the other hand lights and throws
-- dynamite
local MINER = {
  bone = { 0.84, 0.82, 0.72 },
  boneDark = { 0.58, 0.55, 0.48 },
  hat = { 0.66, 0.50, 0.16 },
  hatDark = { 0.44, 0.33, 0.10 },
  rag = { 0.34, 0.27, 0.20 },
  wood = { 0.45, 0.30, 0.16 },
  iron = { 0.46, 0.48, 0.54 },
  tnt = { 0.78, 0.16, 0.14 },
}

local function minerPose(e)
  local wind = e.windT and (1 - e.windT / e.def.windup) or 0
  local throw = (e.throwT or 0) / 0.35
  return wind, throw
end

local function drawMiner(e)
  local r, x, y = mirror(e, 10)
  local white = e.flash > 0
  local function col(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local b = e.body
  local moving = e.grounded and math.abs(b.vx) > 6
  local t = e.phase
  local wind, throw = minerPose(e)
  local bob = moving and (math.abs(math.sin(t)) > 0.5 and 1 or 0) or 0
  -- Legs
  col(MINER.boneDark)
  local sw = moving and math.floor(math.sin(t) * 2 + 0.5) or 0
  r(3 + sw, 15, 1, 4)
  r(6 - sw, 15, 1, 4)
  r(2 + sw, 18, 2, 1)
  r(6 - sw, 18, 2, 1)
  -- Pelvis, spine, ribs under rags
  col(MINER.bone)
  r(3, 14 - bob, 4, 1)
  r(4, 8 - bob, 2, 6)
  col(MINER.boneDark)
  r(3, 9 - bob, 4, 1)
  r(3, 11 - bob, 4, 1)
  col(MINER.rag)
  r(2, 8 - bob, 2, 5)
  r(2, 12 - bob, 1, 2)
  -- Skull and jaw
  col(MINER.bone)
  r(3, 3 - bob, 5, 4)
  r(4, 7 - bob, 3, 1)
  col({ 0.10, 0.08, 0.08 })
  r(6, 4 - bob, 1, 2)
  r(4, 4 - bob, 1, 1)
  -- Hard hat with its lamp
  col(MINER.hatDark)
  r(2, 2 - bob, 7, 1)
  col(MINER.hat)
  r(3, 0 - bob, 5, 2)
  r(2, 1 - bob, 6, 1)
  r(8, 1 - bob, 2, 2)
  col(MINER.iron)
  r(8, 1 - bob, 1, 1)
  -- The pickaxe over the back shoulder
  col(MINER.wood)
  r(1, 5 - bob, 1, 7)
  col(MINER.iron)
  r(0, 4 - bob, 4, 1)
  r(0, 5 - bob, 1, 1)
  -- The throwing arm: down when idle, raised with a lit stick when winding up,
  -- flung forward after
  local ax, ay
  if throw > 0 then
    ax, ay = 8 + math.floor((1 - throw) * 1), 5
  elseif wind > 0 then
    ax, ay = 6, 1 - math.floor(wind * 2)
  else
    ax, ay = 7, 12 - bob
  end
  col(MINER.bone)
  r(5, 9 - bob, 1, 1)
  r(6, 9 - bob + math.floor((ay - 9 + bob) * 0.4), 1, 1)
  r(ax, ay, 1, 2)
  if wind > 0 and throw <= 0 then
    col(MINER.tnt)
    r(ax - 1, ay - 5, 3, 5)
    col({ 0.14, 0.10, 0.08 })
    r(ax, ay - 6, 1, 1)
  end
end

-- The lamp on its hat, a dim amber glow in the eye socket, and the fuse of the
-- stick it is about to throw
local function drawMinerGlow(e)
  local r = mirror(e, 10)
  love.graphics.setColor(1, 0.86, 0.42)
  r(8, 1, 1, 2)
  love.graphics.setColor(1, 0.95, 0.7)
  r(9, 1, 1, 1)
  love.graphics.setColor(0.95, 0.62, 0.2, 0.9)
  r(6, 4, 1, 1)
  if e.windT then
    local wind = 1 - e.windT / e.def.windup
    local f = math.floor(love.timer.getTime() * 30) % 2
    love.graphics.setColor(1, 0.7 + f * 0.2, 0.25)
    r(6, -5 - math.floor(wind * 2) + 1, 1, 1 + f)
  end
end

-- The cave roller: a plated pillbug that crawls on a fringe of legs, or a
-- striped grey ball once curled
local ROLLER = {
  plate = { 0.50, 0.47, 0.44 },
  dark = { 0.32, 0.30, 0.30 },
  light = { 0.68, 0.65, 0.60 },
  belly = { 0.74, 0.62, 0.54 },
}

local function drawRoller(e)
  local b = e.body
  local white = e.flash > 0
  local function col(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local x, y = math.floor(b.x), math.floor(b.y)
  if e.armored then
    -- A ball, its plates banding across it as it spins
    local cx, cy = x + b.w / 2, y + b.h / 2
    local rad = 5
    local spin = e.spin or 0
    local rows = { 4, 8, 10, 10, 10, 10, 10, 10, 8, 4 }
    for i, w in ipairs(rows) do
      col(i <= 3 and ROLLER.light or (i >= 8 and ROLLER.dark or ROLLER.plate))
      px(cx - w / 2, y + i - 1, w, 1)
    end
    col(ROLLER.dark)
    for k = 0, 3 do
      local o = math.sin(spin + k * 1.1) * 4.2
      local half = math.floor(math.sqrt(math.max(0, rad * rad - o * o)))
      if math.cos(spin + k * 1.1) > 0 then
        px(cx + o, cy - half, 1, half * 2)
      end
    end
    if e.armorHit and e.armorHit > 0 then
      love.graphics.setColor(1, 0.95, 0.7, e.armorHit / 0.12)
      px(x + 2, y + 1, 3, 1)
    end
    return
  end
  local r = mirror(e, 12)
  local t = e.phase
  local wob = e.state == "dizzy" and math.floor(math.sin(t * 3) * 1.5 + 0.5) or 0
  -- Legs, a rippling fringe underneath
  col(ROLLER.belly)
  for i = 0, 4 do
    local lift = (math.sin(t * 2 + i * 1.3) > 0.4) and 1 or 0
    r(2 + i * 2, 9 - lift, 1, 1 + lift)
  end
  -- Plates, front to back
  for i = 0, 5 do
    col(i % 2 == 0 and ROLLER.plate or ROLLER.dark)
    local h = i == 0 and 4 or (i == 5 and 4 or 6)
    r(1 + i * 2 + wob, 8 - h - (i == 0 and 0 or 1), 2, h + 1)
  end
  col(ROLLER.light)
  r(3 + wob, 2, 6, 1)
  -- Head and antennae
  col(ROLLER.dark)
  r(10, 4, 2, 4)
  r(11, 2, 1, 2)
  col({ 0.06, 0.05, 0.05 })
  r(11, 5, 1, 1)
end

-- Sticks of dynamite in flight
local function drawSticks()
  for _, s in ipairs(sticks) do
    love.graphics.push()
    love.graphics.translate(math.floor(s.x), math.floor(s.y))
    love.graphics.rotate(s.spin)
    love.graphics.setColor(0.78, 0.16, 0.14)
    love.graphics.rectangle("fill", -1, -3, 3, 6)
    love.graphics.setColor(0.95, 0.38, 0.32)
    love.graphics.rectangle("fill", -1, -3, 1, 6)
    love.graphics.setColor(0.85, 0.78, 0.60)
    love.graphics.rectangle("fill", -1, -1, 3, 1)
    love.graphics.setColor(0.14, 0.10, 0.08)
    love.graphics.rectangle("fill", 0, -4, 1, 1)
    love.graphics.pop()
  end
end

local function drawSticksGlow()
  local t = love.timer.getTime()
  for _, s in ipairs(sticks) do
    local f = math.floor(t * 30 + s.x) % 2
    local c, sn = math.cos(s.spin), math.sin(s.spin)
    -- The fuse's spark rides at the tip of the stick
    local fx, fy = s.x + sn * 4, s.y - c * 4
    love.graphics.setColor(1, 0.7 + f * 0.2, 0.25)
    love.graphics.rectangle("fill", math.floor(fx), math.floor(fy) - f, 1, 1 + f)
    local urgency = 1 - math.min(1, s.fuse / 0.5)
    if urgency > 0 then
      love.graphics.setColor(1, 0.4, 0.2, urgency * 0.5)
      love.graphics.rectangle("fill", math.floor(s.x) - 3, math.floor(s.y) - 3, 6, 6)
    end
  end
end

-- The bosses ---------------------------------------------------------------------
-- Each is drawn at its own size, in detail: the bigger body has room for more
-- than the small monster it grew from, so none of these is just that sprite
-- blown up. They share the small monster's animation state (pose, wing beat,
-- swell) but have their own art.

local function noise2(a, b)
  local n = math.sin(a * 127.1 + b * 311.7) * 43758.5453
  return n - math.floor(n)
end

-- The Ashen Warden: a giant ghoul in a dented iron half-helm, a spiked
-- pauldron, manacles and chains, a rope belt hung with a skull, ribs showing
-- through its rags and a row of bone spikes down its back
local WARDEN = {
  skin = { 0.60, 0.62, 0.64 },
  skinDark = { 0.38, 0.40, 0.44 },
  skinLight = { 0.78, 0.80, 0.82 },
  deep = { 0.24, 0.25, 0.29 },
  rags = { 0.26, 0.27, 0.31 },
  ragsDark = { 0.14, 0.15, 0.18 },
  ragsLight = { 0.38, 0.39, 0.44 },
  iron = { 0.38, 0.39, 0.45 },
  ironLight = { 0.64, 0.65, 0.72 },
  ironDark = { 0.19, 0.19, 0.24 },
  rust = { 0.52, 0.30, 0.18 },
  bone = { 0.86, 0.82, 0.68 },
  boneDark = { 0.60, 0.56, 0.46 },
  claw = { 0.90, 0.86, 0.68 },
  eye = { 0.78, 0.95, 1.0 },
}

-- The ghoul's pose, worked out on a 12x19 body and doubled to the Warden's 24x38
local function wardenPose(e)
  local b = e.body
  local proxy = setmetatable({ body = { x = 0, y = 0, w = 12, h = 19, vx = b.vx, vy = b.vy } }, { __index = e })
  return ghoulPose(proxy)
end

local function drawWarden(e)
  local b = e.body
  local pose = wardenPose(e)
  local f = pose.f
  local white = e.flash > 0
  local W = WARDEN
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local ox, oy = b.x, b.y
  local function P(p)
    return ox + p[1] * 2, oy + p[2] * 2
  end
  local sx, sy = P(pose.shoulder)
  local hx, hy = P(pose.head)
  local pvx, pvy = P(pose.pelvis)
  local reaching = pose.strike > 0.2
  local open = math.max(pose.wind, pose.strike)
  local t = e.phase

  local function arm(hand, off, upperC, lowerC, front)
    local hx2, hy2 = P(hand)
    local ax, ay = sx + off, sy + 3
    local ex, ey = (ax + hx2) / 2 - f, (ay + hy2) / 2 + 4 * (1 - pose.strike)
    color(upperC)
    thick(ax, ay, ex, ey, 5)
    color(lowerC)
    thick(ex, ey, hx2, hy2, 4)
    if front then
      color(W.skinLight)
      limb(ax, ay - 2, ex, ey - 2)
      limb(ex, ey - 1, hx2, hy2 - 1)
    end
    color(W.deep) -- scars across the forearm
    px(ex + f, ey, 1, 2)
    px((ex + hx2) / 2, (ey + hy2) / 2 - 1, 2, 1)
    -- An iron manacle at the wrist, with a chain swinging from it
    color(W.ironDark)
    px(hx2 - 3, hy2 - 3, 6, 4)
    color(W.iron)
    px(hx2 - 3, hy2 - 3, 6, 2)
    color(W.ironLight)
    px(hx2 - 3, hy2 - 3, 6, 1)
    for k = 1, 3 do
      color(k % 2 == 0 and W.ironLight or W.iron)
      px(hx2 - 1, hy2 + 1 + k * 2 + math.floor(math.sin(t + k) * 0.7), 2, 1)
    end
    -- The hand, and three long claws
    color(front and W.skin or W.skinDark)
    px(hx2 - 2, hy2 - 2, 5, 5)
    local cd = reaching and f or -f
    color(W.claw)
    for k = -1, 1 do
      limb(hx2 + cd * 2, hy2 + k * 2, hx2 + cd * 6, hy2 + k * 2 + k)
    end
  end

  -- The back arm, then the legs
  arm(pose.hands[2], -f * 2, W.skinDark, W.skinDark, false)
  for i = 2, 1, -1 do
    local fx, fy = P(pose.feet[i])
    local c = i == 1 and W.skin or W.skinDark
    local kx, ky = (pvx + fx) / 2 + f * 4, (pvy + fy) / 2 - 1
    color(c)
    thick(pvx, pvy + 2, kx, ky, 5)
    thick(kx, ky, fx, fy - 2, 4)
    if i == 1 then
      color(W.skinLight)
      limb(pvx + 1, pvy + 1, kx + 1, ky - 1)
    end
    color(W.ragsDark) -- a knee wrapped in rag
    px(kx - 2, ky - 1, 5, 3)
    color(W.ragsLight)
    px(kx - 2, ky - 1, 5, 1)
    color(c) -- a broad foot with claws
    px(fx - 3, fy - 1, 7, 2)
    color(W.skinDark)
    px(fx - 3, fy, 7, 1)
    color(W.claw)
    px(fx + f * 4, fy - 1, 1, 1)
    px(fx + f * 4, fy, 1, 1)
  end

  -- The torso: ragged cloth over the hunched mass, shaded front and back
  color(W.rags)
  thick(pvx, pvy, sx, sy + 2, 11)
  color(W.ragsDark)
  thick(pvx - f * 4, pvy, sx - f * 4, sy + 3, 3)
  color(W.ragsLight)
  thick(pvx + f * 3, pvy - 1, sx + f * 3, sy + 3, 1)
  for k = 1, 7 do -- patches and stitching
    local tt = noise2(k, 3)
    local x = sx + (pvx - sx) * tt + (noise2(k, 9) - 0.5) * 8
    local y = sy + (pvy - sy) * tt
    color(noise2(k, 5) < 0.5 and W.ragsDark or W.ragsLight)
    px(x, y, 2 + math.floor(noise2(k, 1) * 3), 2)
  end
  -- Ribs showing through a tear
  local rx, ry = sx + (pvx - sx) * 0.45 + f * 2, sy + (pvy - sy) * 0.45
  color(W.deep)
  px(rx - 4, ry - 3, 8, 9)
  color(W.bone)
  for k = 0, 3 do
    px(rx - 3, ry - 2 + k * 2, 6 - k, 1)
  end
  -- A rope belt and a skull hung from it
  color(W.rust)
  thick(pvx - 5, pvy + 1, pvx + 5, pvy + 1, 2)
  color(W.bone)
  px(pvx + f * 2, pvy + 3, 3, 3)
  color(W.ragsDark)
  px(pvx + f * 2, pvy + 4, 1, 1)
  px(pvx + f * 2 + 2, pvy + 4, 1, 1)
  -- A tattered hem
  for k = -5, 5 do
    color(k % 2 == 0 and W.rags or W.ragsDark)
    px(pvx + k, pvy + 3, 1, 3 + ((k + math.floor(t * 0.5)) % 3))
  end
  -- A great bare hump of a back, with bone spikes down it
  color(W.skin)
  px(sx - f * 7 - 3, sy - 4, 9, 7)
  color(W.skinLight)
  px(sx - f * 7 - 3, sy - 4, 9, 2)
  color(W.skinDark)
  px(sx - f * 7 - 3, sy + 1, 9, 2)
  for k = 0, 4 do
    local tt = k / 4
    local x = sx - f * 5 + (pvx - f * 5 - (sx - f * 5)) * tt
    local y = sy - 3 + (pvy - 1 - (sy - 3)) * tt
    color(W.boneDark)
    px(x, y - 3, 2, 4)
    color(W.bone)
    px(x, y - 4, 1, 3)
  end

  -- The head: a heavy skull under a dented iron half-helm with a fin along the top
  color(W.skin)
  px(hx - 5, hy - 2, 11, 8)
  color(W.skinLight)
  px(hx - 5, hy - 2, 11, 1)
  color(W.skinDark)
  px(hx - 5, hy + 5, 11, 1)
  color(W.ironDark)
  px(hx - 6, hy - 4, 13, 3)
  color(W.iron)
  px(hx - 6, hy - 4, 13, 2)
  color(W.ironLight)
  px(hx - 5, hy - 4, 11, 1)
  color(W.rust)
  px(hx - 3, hy - 3, 2, 1)
  px(hx + 2, hy - 3, 2, 1)
  color(W.iron)
  px(hx - 1, hy - 7, 3, 3)
  color(W.ironLight)
  px(hx, hy - 7, 1, 2)
  color(W.ragsDark) -- the brow and the hollow sockets
  px(hx - 5, hy, 11, 1)
  local ex, ey = ghoulEyes(pose)
  px(ox + ex * 2, oy + ey * 2 + 1, 4, 3)
  color(W.skinDark)
  px(hx - 5, hy + 3, 2, 2)
  -- The jaw drops open when it attacks; tusks and teeth
  local jx = ox + (pose.head[1] - 1 + (f > 0 and 1 or -1)) * 2
  local drop = open > 0.3 and 2 or 0
  color(W.ragsDark)
  px(jx - 2, hy + 6, 6, drop)
  color(W.skin)
  px(jx - 3, hy + 6 + drop, 8, 2)
  color(W.bone)
  for k = 0, 3 do
    px(jx - 2 + k * 2, hy + 5 + drop, 1, 2)
  end
  px(jx + (f > 0 and 5 or -4), hy + 4, 1, 4)

  -- The front arm over the body, and the spiked iron pauldron on its shoulder
  arm(pose.hands[1], 0, W.skin, W.skin, true)
  color(W.ironDark)
  px(sx - 3, sy - 2, 7, 5)
  color(W.iron)
  px(sx - 3, sy - 2, 7, 3)
  color(W.ironLight)
  px(sx - 3, sy - 2, 7, 1)
  px(sx - 3, sy - 2, 1, 3)
  color(W.rust)
  px(sx + 1, sy + 1, 2, 1)
  color(W.ironLight)
  px(sx - 1, sy, 1, 1)
  px(sx + 2, sy, 1, 1)
  color(W.iron)
  px(sx - 1, sy - 5, 3, 3)
  color(W.ironLight)
  px(sx, sy - 6, 1, 3)
end

local function drawWardenGlow(e)
  local pose = wardenPose(e)
  local b = e.body
  local ex, ey = ghoulEyes(pose)
  local glare = math.max(pose.wind, pose.strike)
  love.graphics.setColor(WARDEN.eye[1], WARDEN.eye[2], WARDEN.eye[3], 0.75 + 0.25 * glare)
  px(b.x + ex * 2 + (pose.f > 0 and 1 or 0), b.y + ey * 2 + 2, glare > 0.3 and 3 or 2, 2)
end

-- The Mire Matron: a giant toad with a crest of bone spines down her back,
-- purple warts, a pulsing throat, a ridged brow over great golden eyes,
-- webbed feet, and a mouth of small teeth
local MATRON = {
  skin = { 0.26, 0.42, 0.32 },
  dark = { 0.15, 0.27, 0.23 },
  light = { 0.40, 0.58, 0.40 },
  belly = { 0.64, 0.70, 0.46 },
  bellyDark = { 0.50, 0.56, 0.36 },
  wart = { 0.46, 0.32, 0.50 },
  wartLight = { 0.64, 0.48, 0.68 },
  bone = { 0.86, 0.82, 0.66 },
  mouth = { 0.10, 0.06, 0.08 },
  eye = { 1, 0.85, 0.3 },
}

local WART_SPOTS = { { 6, 6 }, { 9, 5 }, { 12, 7 }, { 8, 9 }, { 5, 9 }, { 13, 10 } }

local function drawMatron(e)
  local r = mirror(e, 24)
  local white = e.flash > 0
  local M = MATRON
  local function col(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local air = not e.grounded
  local sq = e.windT and 2 or 0
  local t = e.phase
  local breath = math.floor(math.sin(t * 2) * 0.6 + 0.6)
  -- Hind legs: stretched out behind in a leap, folded under her otherwise
  if air then
    col(M.dark)
    r(3, 9, 6, 4)
    r(-3, 12, 7, 2)
    col(M.skin)
    r(-7, 12, 5, 2)
    col(M.dark)
    r(-9, 11, 1, 1)
    r(-9, 13, 1, 1)
    r(-8, 12, 1, 1)
    col(M.light)
    r(3, 9, 5, 1)
    -- Front legs reaching out ahead
    col(M.dark)
    r(17, 12, 6, 2)
    col(M.skin)
    r(22, 11, 3, 3)
  else
    col(M.dark)
    r(2, 8 + sq, 9, 8 - sq)
    r(3, 14, 11, 3)
    col(M.skin)
    r(2, 8 + sq, 8, 3)
    col(M.light)
    r(3, 8 + sq, 6, 1)
    col(M.skin)
    r(11, 15, 8, 2)
    col(M.dark)
    r(18, 15, 3, 2)
    r(18, 17, 1, 1)
    r(20, 17, 1, 1) -- the webbed toes
    col(M.dark)
    r(14, 11 + sq, 3, 6 - sq)
    col(M.skin)
    r(14, 11 + sq, 2, 5 - sq)
    r(14, 16, 6, 1)
  end
  -- The body, belly and crest of spines
  col(M.skin)
  r(4, 5 + sq, 13, 9 - sq)
  r(6, 4 + sq, 9, 2)
  col(M.light)
  r(6, 4 + sq, 8, 1)
  r(4, 6 + sq, 1, 4)
  col(M.dark)
  r(4, 11, 13, 3 - sq)
  col(M.belly)
  r(6, 12, 10, 3 - sq)
  col(M.bellyDark)
  r(7, 13, 8, 1)
  for k = 0, 4 do
    col(M.bone)
    r(6 + k * 2, 2 + sq + (k % 2), 1, 3)
    col(M.dark)
    r(7 + k * 2, 3 + sq + (k % 2), 1, 2)
  end
  for _, w in ipairs(WART_SPOTS) do
    col(M.wart)
    r(w[1], w[2] + sq, 2, 2)
    col(M.wartLight)
    r(w[1], w[2] + sq, 1, 1)
  end
  col(M.dark) -- mottling
  r(10, 8 + sq, 2, 1)
  r(7, 11, 1, 1)
  r(14, 8 + sq, 1, 1)
  -- The head: ridged brow, bulging eyes, a wide mouth of small teeth, a throat sac
  col(M.skin)
  r(14, 3 + sq, 10, 9 - sq)
  r(22, 6 + sq, 3, 5 - sq)
  col(M.light)
  r(15, 3 + sq, 8, 1)
  col(M.dark)
  r(15, 2 + sq, 8, 2) -- brow
  col(M.skin)
  r(16, 0 + sq, 5, 4)
  col(M.dark)
  r(16, 0 + sq, 5, 1)
  r(16, 3 + sq, 5, 1)
  col(M.bone)
  r(21, 1 + sq, 1, 2)
  r(23, 2 + sq, 1, 1)
  col(M.mouth)
  r(15, 9 + sq, 10, 1)
  col(M.bone)
  for k = 0, 3 do
    r(17 + k * 2, 10 + sq, 1, 1)
  end
  col(M.belly)
  r(15, 11 + sq, 7, 2 + breath)
  col(M.bellyDark)
  r(16, 12 + sq, 5, 1)
  col(M.dark)
  r(24, 6 + sq, 1, 1) -- a nostril
end

local function drawMatronGlow(e)
  local r = mirror(e, 24)
  local sq = e.windT and 2 or 0
  love.graphics.setColor(MATRON.eye[1], MATRON.eye[2], MATRON.eye[3], 0.9)
  r(17, 1 + sq, 3, 2)
  love.graphics.setColor(1, 1, 0.8)
  r(18, 1 + sq, 1, 1)
end

-- The Dread Bat: shaggy fur, a pig-like snout full of fangs, ears with pink
-- insides, and wings of dark membrane stretched over four finger bones, with
-- veins and ragged edges. It hangs from the ceiling wrapped in its wings when
-- asleep, spreads wide and shakes while it locks on, and sweeps back to dive.
local DREAD = {
  fur = { 0.20, 0.15, 0.20 },
  furLight = { 0.34, 0.26, 0.34 },
  furDark = { 0.11, 0.08, 0.12 },
  membrane = { 0.22, 0.14, 0.21 },
  membraneLight = { 0.34, 0.22, 0.32 },
  bone = { 0.12, 0.09, 0.13 },
  vein = { 0.42, 0.14, 0.20 },
  ear = { 0.55, 0.30, 0.38 },
  fang = { 0.94, 0.92, 0.84 },
}

local function drawDreadBat(e)
  local b = e.body
  local D = DREAD
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local x, y = b.x, b.y
  local mid = x + b.w / 2
  if e.state == "sleep" then
    -- Hanging upside down from its feet, the wings wrapped round like a cloak
    local top = y + 1
    local rows = { 6, 10, 13, 15, 16, 16, 16, 15, 14, 12, 10, 8, 5, 3 }
    for i, w in ipairs(rows) do
      color(i <= 3 and D.membraneLight or (i >= 10 and D.furDark or D.membrane))
      px(mid - w / 2, top + 2 + i, w, 1)
    end
    color(D.bone)
    for k = -3, 3 do
      limb(mid + k * 2, top + 4, mid + k * 1.6, top + 14)
    end
    color(D.fur)
    px(mid - 3, top, 2, 4)
    px(mid + 1, top, 2, 4)
    color(D.furLight)
    px(mid - 4, top, 1, 1)
    px(mid + 3, top, 1, 1)
    color(D.fur) -- the head, tucked at the bottom, eyes closed
    px(mid - 3, top + 16, 6, 3)
    px(mid - 4, top + 17, 1, 3)
    px(mid + 3, top + 17, 1, 3)
    color(D.furDark)
    px(mid - 2, top + 17, 2, 1)
    px(mid + 1, top + 17, 2, 1)
    return
  end
  local lock = e.state == "lock"
  local dive = e.state == "charge"
  local shake = lock and (math.sin(love.timer.getTime() * 70) * 1.2) or 0
  local flap = math.sin(e.phase)
  local cx, cy = mid + shake, y + 10.5
  for side = -1, 1, 2 do
    local sh = { cx + side * 3, cy - 2 }
    local el, wr, p1, p2, p3
    if dive then
      el, wr = { cx + side * 6, cy + 1 }, { cx + side * 7, cy + 9 }
      p1, p2, p3 = { cx + side * 5, cy + 13 }, { cx + side * 3, cy + 12 }, { cx + side * 2, cy + 9 }
    elseif lock then
      el, wr = { cx + side * 10, cy - 3 + flap * 0.8 }, { cx + side * 22, cy - 1 + flap * 1.5 }
      p1, p2, p3 = { cx + side * 19, cy + 8 + flap }, { cx + side * 12, cy + 9 }, { cx + side * 6, cy + 8 }
    else
      el, wr = { cx + side * 9, cy - 4 - flap * 5 }, { cx + side * 20, cy + 1 + flap * 9 }
      p1, p2, p3 = { cx + side * 16, cy + 9 + flap * 4 }, { cx + side * 10, cy + 10 + flap * 2 }, { cx + side * 5, cy + 8 }
    end
    -- The membrane, in panels between the fingers, lighter near the body
    color(D.membrane)
    love.graphics.polygon("fill", sh[1], sh[2], el[1], el[2], wr[1], wr[2])
    love.graphics.polygon("fill", sh[1], sh[2], wr[1], wr[2], p1[1], p1[2])
    love.graphics.polygon("fill", sh[1], sh[2], p1[1], p1[2], p2[1], p2[2])
    love.graphics.polygon("fill", sh[1], sh[2], p2[1], p2[2], p3[1], p3[2])
    color(D.membraneLight)
    love.graphics.polygon("fill", sh[1], sh[2], p2[1], p2[2], p3[1], p3[2])
    -- Veins in the membrane
    color(D.vein)
    limb((el[1] + wr[1]) / 2, (el[2] + wr[2]) / 2 + 1, (p1[1] + p2[1]) / 2, (p1[2] + p2[2]) / 2 - 2)
    limb((p2[1] + sh[1]) / 2, (p2[2] + sh[2]) / 2, p2[1], p2[2] - 2)
    -- The arm and the finger bones
    color(D.bone)
    thick(sh[1], sh[2], el[1], el[2], 2)
    thick(el[1], el[2], wr[1], wr[2], 2)
    limb(wr[1], wr[2], p1[1], p1[2])
    limb(wr[1], wr[2], p2[1], p2[2])
    limb(el[1], el[2], p3[1], p3[2])
    color(D.fang) -- the claw at the wrist
    px(wr[1] + side, wr[2] - 2, 1, 2)
    color(D.furDark) -- ragged notches in the trailing edge
    px(p1[1] - side * 2, p1[2] - 1, 1, 2)
    px(p2[1] + side, p2[2] - 1, 1, 2)
  end
  -- The body: shaggy fur, a lighter chest, small clawed feet
  local body = { 3, 6, 8, 9, 10, 10, 9, 8, 6, 4 }
  for i, w in ipairs(body) do
    color(i <= 2 and D.furLight or (i >= 8 and D.furDark or D.fur))
    px(cx - w / 2, cy - 4 + i, w, 1)
  end
  color(D.furLight)
  px(cx - 2, cy - 1, 4, 5)
  color(D.fur)
  px(cx - 1, cy, 1, 1)
  px(cx + 1, cy + 2, 1, 1)
  color(D.fang)
  px(cx - 2, cy + 6, 1, 2)
  px(cx + 1, cy + 6, 1, 2)
  -- The head: broad skull, big ears with pink insides, a snout and fangs
  local head = { 4, 7, 8, 8, 6 }
  for i, w in ipairs(head) do
    color(i == 1 and D.furLight or D.fur)
    px(cx - w / 2, cy - 11 + i, w, 1)
  end
  color(D.fur)
  px(cx - 5, cy - 14, 3, 4)
  px(cx + 2, cy - 14, 3, 4)
  color(D.ear)
  px(cx - 4, cy - 13, 1, 3)
  px(cx + 3, cy - 13, 1, 3)
  color(D.furDark)
  px(cx - 2, cy - 7, 4, 2) -- the snout
  if lock or dive then
    color({ 0.55, 0.08, 0.1 })
    px(cx - 2, cy - 5, 4, 2)
  end
  color(D.fang)
  px(cx - 2, cy - 5, 1, 2)
  px(cx + 1, cy - 5, 1, 2)
end

local function drawDreadBatGlow(e)
  local b = e.body
  if e.state == "sleep" then
    return
  end
  local mid = b.x + b.w / 2
  local cy = b.y + 10.5
  local angry = e.state == "lock" or e.state == "charge"
  if angry then
    mid = mid + (e.state == "lock" and math.sin(love.timer.getTime() * 70) * 1.2 or 0)
    love.graphics.setColor(1, 0.15, 0.1)
    px(mid - 3, cy - 9, 3, 2)
    px(mid + 1, cy - 9, 3, 2)
  else
    love.graphics.setColor(1, 0.35, 0.25)
    px(mid - 3, cy - 9, 2, 1)
    px(mid + 1, cy - 9, 2, 1)
  end
end

-- The gas bag, for the Behemoth and the Sulfur Queen (and her remnants): a
-- big veined sac, mottled and pustuled, with pores along its belly, a slack
-- toothed mouth and a fringe of swaying tendrils. Everything is laid out by
-- the body's size, so the smaller remnants keep the same look. The glowing
-- core is drawn after the lighting.
local SAC = {
  base = { 0.58, 0.62, 0.26 },
  light = { 0.76, 0.80, 0.40 },
  dark = { 0.44, 0.48, 0.20 },
  deep = { 0.30, 0.34, 0.14 },
  vein = { 0.34, 0.38, 0.14 },
  pale = { 0.84, 0.88, 0.54 },
  mouth = { 0.18, 0.10, 0.10 },
}

local function sacWidth(t)
  -- A round bag, a little narrower at the top and tapering at the foot
  local u = (t - 0.46) / 0.54
  return math.max(0.3, math.sqrt(math.max(0, 1 - u * u)))
end

local function drawSac(e)
  local b = e.body
  local W, H = b.w, b.h
  local x0, y0 = math.floor(b.x), math.floor(b.y)
  local white = e.flash > 0
  local function col(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local sd = e.detail
  if not sd then
    sd = love.math.random(1, 1000)
    e.detail = sd
  end
  local swell = (e.puffT and e.puffT < 0.25) and math.max(1, W / 14) or 0
  local cx = x0 + W / 2
  local rim = math.max(1, math.floor(W / 24))
  for row = 0, H - 1 do
    local t = (row + 0.5) / H
    local ww = math.floor(sacWidth(t) * W + swell)
    local xs = math.floor(cx - ww / 2)
    col(t < 0.2 and SAC.light or (t > 0.85 and SAC.deep or (t > 0.62 and SAC.dark or SAC.base)))
    px(xs, y0 + row, ww, 1)
    if t > 0.08 then
      col(SAC.light)
      px(xs, y0 + row, rim, 1)
    end
    col(SAC.deep)
    px(xs + ww - rim, y0 + row, rim, 1)
  end
  -- Mottling
  for k = 1, math.floor(W * H / 55) do
    local py = math.floor(noise2(k + 17, sd) * H)
    local half = sacWidth((py + 0.5) / H) * W / 2 - 2
    col(noise2(k, sd + 3) < 0.55 and SAC.dark or SAC.pale)
    px(cx + (noise2(k, sd) - 0.5) * 2 * half, y0 + py, 1 + math.floor(noise2(k, 5) * 2), 1)
  end
  -- Veins running out from the core, branching as they go
  local coreY = y0 + H * 0.45
  for v = 1, 8 do
    local a = (v / 8) * 6.283 + noise2(v, sd) * 0.8
    local x, y = cx, coreY
    col(SAC.vein)
    for s = 1, math.floor(W * (0.26 + 0.12 * noise2(v, 2))) do
      a = a + (noise2(v * 31 + s, sd) - 0.5) * 0.7
      x, y = x + math.cos(a), y + math.sin(a)
      px(x, y)
      if s % 6 == 0 then
        for q = 1, 3 do
          px(x + math.cos(a + 1) * q, y + math.sin(a + 1) * q)
        end
      end
    end
  end
  -- Pustules
  for k = 1, math.max(2, math.floor(W / 11)) do
    local py = math.floor((0.15 + noise2(k, sd + 7) * 0.6) * H)
    local half = sacWidth((py + 0.5) / H) * W / 2 - 3
    local x = cx + (noise2(k + 5, sd) - 0.5) * 2 * half
    col(SAC.pale)
    px(x, y0 + py, 2, 2)
    col(SAC.dark)
    px(x, y0 + py + 2, 2, 1)
  end
  -- The slack, toothed mouth and the pores beneath it
  local my = y0 + math.floor(H * 0.72)
  local mw = math.max(4, math.floor(W * 0.3))
  col(SAC.dark)
  px(cx - mw / 2 - 1, my - 1, mw + 2, 1)
  col(SAC.mouth)
  px(cx - mw / 2, my, mw, math.max(2, math.floor(H / 10)))
  col(SAC.pale)
  for k = 0, math.floor(mw / 3) do
    px(cx - mw / 2 + 1 + k * 3, my, 1, 1)
  end
  col(SAC.deep)
  for k = 1, 5 do
    px(cx + (k - 3) * W / 8, y0 + math.floor(H * 0.86), 1, 1)
  end
  -- Tendrils hanging from the underside
  local n = math.max(3, math.floor(W / 5))
  local len = math.floor(H * 0.2)
  local thickness = W > 40 and 2 or 1
  for i = 0, n - 1 do
    local tx = cx - W * 0.32 + i * (W * 0.64 / (n - 1))
    for s = 0, len do
      local sway = math.sin(e.phase * 1.5 + i * 2 + s * 0.25) * (1 + s * 0.12)
      col(s > len - 2 and SAC.pale or SAC.deep)
      px(tx + sway, y0 + H - 2 + s, thickness, 1)
    end
  end
end

local function drawSacGlow(e)
  local b = e.body
  local W, H = b.w, b.h
  local cx, cy = b.x + W / 2, b.y + H * 0.45
  local pulse = 0.55 + 0.25 * math.sin(e.phase * 1.7)
  love.graphics.setColor(0.8, 0.95, 0.3, 0.3 * pulse)
  px(cx - W * 0.17, cy - W * 0.14, W * 0.34, W * 0.28)
  love.graphics.setColor(0.8, 0.95, 0.3, pulse)
  px(cx - W * 0.1, cy - W * 0.08, W * 0.2, W * 0.16)
  love.graphics.setColor(1, 0.92, 0.35)
  px(cx - W * 0.04, cy - W * 0.03, math.max(2, W * 0.08), math.max(2, W * 0.06))
end

-- Piranha: a stubby silver fish, dark back, a red belly and an underbite of
-- white teeth; its tail beats while it swims, and it thrashes out of water
local PIRANHA = {
  back = { 0.24, 0.30, 0.30 },
  body = { 0.56, 0.62, 0.62 },
  light = { 0.76, 0.80, 0.78 },
  belly = { 0.80, 0.24, 0.18 },
  fin = { 0.36, 0.20, 0.18 },
  tooth = { 0.96, 0.94, 0.86 },
}
local function drawPiranha(e)
  local r = mirror(e, 8)
  local function col(c)
    love.graphics.setColor(e.flash > 0 and { 1, 1, 1 } or c)
  end
  local t = love.timer.getTime() + e.phase
  local beat = e.inWater and (math.sin(t * (e.dashT and e.dashT > 0 and 40 or 14)) > 0 and 1 or 0) or (math.sin(t * 30) > 0 and 1 or 0)
  -- Tail
  col(PIRANHA.fin)
  r(0, beat, 1, 3)
  r(1, 1, 1, 1 + beat)
  -- Body: dark back, silver flank, red belly
  col(PIRANHA.back)
  r(2, 0, 4, 1)
  r(4, -1, 1, 1) -- dorsal fin
  col(PIRANHA.body)
  r(2, 1, 5, 2)
  col(PIRANHA.light)
  r(3, 1, 2, 1)
  col(PIRANHA.belly)
  r(2, 3, 4, 1)
  r(3, 4, 3, 1)
  -- Head and the jutting jaw, teeth showing
  col(PIRANHA.body)
  r(7, 1, 1, 1)
  col(PIRANHA.belly)
  r(6, 3, 2, 1)
  col(PIRANHA.tooth)
  r(7, 2, 1, 1)
  r(6, 4, 1, 1)
end
local function drawPiranhaEye(e)
  local r = mirror(e, 8)
  love.graphics.setColor(1, 0.3, 0.2, 0.9)
  r(6, 1, 1, 1)
end

-- The Marble Colossus's sprite --------------------------------------------------
local MARBLE = {
  light = { 0.98, 0.97, 1.0 },
  mid = { 0.84, 0.83, 0.92 },
  dark = { 0.62, 0.61, 0.74 },
  deep = { 0.42, 0.41, 0.56 },
  pink = { 1.0, 0.45, 0.78 },
  blue = { 0.40, 0.66, 1.0 },
}

local function lerp2(a, b, t)
  return a + (b - a) * t
end

-- Where its hands are (in its 56 x 84 box, for a golem facing right), how far
-- it has crouched, and how high a foot is lifted
local function golemPose(e)
  local pose = { fx = 50, fy = 58, bx = 6, by = 58, crouch = 0, lift = 0, stone = false, tilt = 0 }
  local p = 0
  if e.gd and e.gd > 0 then
    p = 1 - math.max(0, e.gt or 0) / e.gd
  end
  local gs, sub = e.gs, e.sub
  if gs == "shell" then
    pose.crouch = 12
    pose.fx, pose.fy, pose.bx, pose.by = 44, 70, 12, 70
  elseif gs == "rest" then
    pose.crouch = 8
    pose.fx, pose.fy, pose.bx, pose.by = 46, 72, 10, 72
  elseif gs == "swipe" then
    if sub == "wind" then
      pose.fx, pose.fy = lerp2(50, 40, p), lerp2(58, -2, p)
    elseif sub == "act" then
      pose.fx, pose.fy = lerp2(40, 86, p), lerp2(-2, 52, p)
    else
      pose.fx, pose.fy = lerp2(86, 50, p), lerp2(52, 58, p)
    end
  elseif gs == "throw" then
    if sub == "wind" then
      pose.fx, pose.fy = lerp2(50, 42, p), lerp2(58, -6, p)
      pose.stone = true
    elseif sub == "act" then
      pose.fx, pose.fy = lerp2(42, 66, p), lerp2(-6, 18, p)
    else
      pose.fx, pose.fy = lerp2(66, 50, p), lerp2(18, 58, p)
    end
  elseif gs == "stomp" then
    if sub == "wind" then
      pose.lift = 12 * p
      pose.fx, pose.fy = 44, lerp2(58, 4, p)
      pose.bx, pose.by = 12, lerp2(58, 4, p)
    elseif sub == "act" then
      pose.fx, pose.fy = 52, lerp2(4, 66, math.min(1, p * 3))
      pose.bx, pose.by = 4, lerp2(4, 66, math.min(1, p * 3))
    else
      pose.fx, pose.fy = 50, 62
    end
  elseif gs == "beam" then
    pose.fx, pose.fy = 46, 50
    pose.tilt = 1
  else
    local sway = math.sin(e.phase) * 3
    pose.fx, pose.fy = 50 + sway * 0.5, 58 + sway
    pose.bx, pose.by = 6 - sway * 0.5, 58 - sway
  end
  return pose
end

-- A thick block-armed limb from (x0, y0) to (x1, y1)
local function golemLimb(r, x0, y0, x1, y1, w, c1, c2)
  local n = math.max(2, math.ceil(math.max(math.abs(x1 - x0), math.abs(y1 - y0)) / 3))
  for i = 0, n do
    local t = i / n
    love.graphics.setColor(i % 2 == 0 and c1 or c2)
    r(lerp2(x0, x1, t) - w / 2, lerp2(y0, y1, t) - w / 2, w, w)
  end
end

local function drawGolem(e)
  local r, bx, by = mirror(e, 56)
  local white = e.flash > 0
  local function col(c, a)
    if white then
      love.graphics.setColor(1, 1, 1)
    else
      love.graphics.setColor(c[1], c[2], c[3], a or 1)
    end
  end
  local pose = golemPose(e)
  local crouch = pose.crouch
  local walk = (e.grounded and math.abs(e.body.vx) > 4) and math.sin(e.phase) or 0
  local bob = math.abs(walk) * 1.5
  local top = crouch + bob
  -- the far arm, then the legs
  golemLimb(r, 12, 24 + top, pose.bx, pose.by + top, 9, MARBLE.dark, MARBLE.deep)
  col(MARBLE.dark)
  r(pose.bx - 6, pose.by + top - 4, 12, 12)
  col(MARBLE.deep)
  r(pose.bx - 6, pose.by + top + 5, 12, 3)
  local lift1 = math.max(0, walk) * 4
  local lift2 = math.max(0, -walk) * 4 + pose.lift
  for i, lx in ipairs({ 10, 32 }) do
    local lift = i == 1 and lift1 or lift2
    local y0 = 54 + crouch
    col(MARBLE.mid)
    r(lx, y0 - lift, 15, 30 - crouch)
    col(MARBLE.light)
    r(lx, y0 - lift, 4, 30 - crouch)
    col(MARBLE.deep)
    r(lx + 12, y0 - lift, 3, 30 - crouch)
    col(MARBLE.dark)
    r(lx - 2, 80 - lift, 19, 4) -- the foot
  end
  -- hips, torso and shoulders
  col(MARBLE.dark)
  r(8, 46 + top, 40, 12)
  col(MARBLE.mid)
  r(6, 18 + top, 44, 32)
  col(MARBLE.light)
  r(6, 18 + top, 44, 4)
  r(6, 18 + top, 5, 32)
  col(MARBLE.deep)
  r(44, 22 + top, 6, 28)
  r(6, 46 + top, 44, 4)
  -- crystal spikes on the shoulders
  for i, sx in ipairs({ 4, 14, 38, 48 }) do
    local h = ({ 10, 7, 8, 11 })[i]
    col(MARBLE.light)
    r(sx, 14 + top - h + 4, 4, h)
    col(MARBLE.mid)
    r(sx + 3, 14 + top - h + 6, 2, h - 2)
    col(MARBLE.light)
    r(sx + 1, 14 + top - h, 2, 3)
  end
  -- the veins that run through it (they glow, see drawGolemGlow)
  for k = 0, 13 do
    local vx = 8 + math.floor(noise2(k, 3) * 36)
    local vy = 22 + top + math.floor(noise2(k, 7) * 24)
    col(k % 2 == 0 and MARBLE.pink or MARBLE.blue)
    r(vx, vy, 4 + k % 4, 2)
    r(vx + 3 + k % 4, vy + 2, 2, 5)
    r(vx + 5 + k % 4, vy + 7, 4, 2)
  end
  -- facets: pale chips along the edges
  for k = 0, 7 do
    col(k % 2 == 0 and MARBLE.light or MARBLE.dark)
    r(7 + k * 5, 18 + top + (k * 7) % 12, 3, 5)
  end
  -- the head: small and blocky, set low between the shoulders
  col(MARBLE.mid)
  r(20, 4 + top + pose.tilt, 18, 16)
  col(MARBLE.light)
  r(20, 4 + top + pose.tilt, 18, 3)
  col(MARBLE.deep)
  r(32, 7 + top + pose.tilt, 6, 13)
  col({ 0.12, 0.1, 0.16 })
  r(27, 9 + top + pose.tilt, 9, 5) -- the eye socket
  -- the front arm, over the body
  golemLimb(r, 44, 24 + top, pose.fx, pose.fy + top, 10, MARBLE.mid, MARBLE.light)
  col(MARBLE.mid)
  r(pose.fx - 7, pose.fy + top - 5, 14, 14)
  col(MARBLE.light)
  r(pose.fx - 7, pose.fy + top - 5, 14, 3)
  col(MARBLE.deep)
  r(pose.fx + 3, pose.fy + top - 2, 4, 11)
  col(MARBLE.pink)
  r(pose.fx - 3, pose.fy + top + 2, 6, 1)
  if pose.stone then
    col(MARBLE.dark)
    r(pose.fx - 6, pose.fy + top - 16, 14, 12)
    col(MARBLE.light)
    r(pose.fx - 6, pose.fy + top - 16, 14, 3)
    col(MARBLE.blue)
    r(pose.fx - 2, pose.fy + top - 11, 6, 1)
  end
  -- the crystal shell
  if e.invuln then
    local t = love.timer.getTime()
    love.graphics.setColor(0.55, 0.85, 1, 0.28 + 0.1 * math.sin(t * 6))
    r(-2, 4, 60, 84)
    love.graphics.setColor(0.8, 0.95, 1, 0.55)
    r(-2, 4, 60, 2)
    r(-2, 86, 60, 2)
    r(-2, 4, 2, 84)
    r(56, 4, 2, 84)
    for k = 0, 4 do
      local sx = -2 + k * 14
      love.graphics.setColor(0.7, 0.92, 1, 0.5)
      r(sx, -8 + (k % 2) * 5, 6, 14)
      love.graphics.setColor(1, 1, 1, 0.5)
      r(sx + 1, -8 + (k % 2) * 5, 2, 6)
    end
  end
end

local function drawGolemGlow(e)
  local b = e.body
  local t = love.timer.getTime()
  local ex, ey = golemEye(e)
  ey = ey + (e.invuln and 12 or (e.gs == "rest" and 8 or 0))
  -- the veins glow in the dark, brighter as it winds up or as it takes damage
  do
    local r = mirror(e, 56)
    local crouch = golemPose(e).crouch + ((e.grounded and math.abs(e.body.vx) > 4) and math.abs(math.sin(e.phase)) * 1.5 or 0)
    local vp = 0.35 + 0.25 * math.sin(t * 2.2) + (e.sub == "wind" and 0.3 or 0)
    for k = 0, 13 do
      local vx = 8 + math.floor(noise2(k, 3) * 36)
      local vy = 22 + crouch + math.floor(noise2(k, 7) * 24)
      local c = k % 2 == 0 and { 1, 0.45, 0.78 } or { 0.4, 0.66, 1 }
      love.graphics.setColor(c[1], c[2], c[3], vp * (e.invuln and 0.5 or 1))
      r(vx, vy, 4 + k % 4, 2)
      r(vx + 3 + k % 4, vy + 2, 2, 5)
    end
  end
  local charging = e.gs == "beam" and e.sub == "wind"
  local pulse = 0.7 + 0.3 * math.sin(t * (charging and 30 or 5))
  local c = e.invuln and { 0.5, 0.85, 1 } or { 1, 0.35, 0.6 }
  local s = charging and 5 + 4 * (1 - math.max(0, e.gt) / e.gd) or 3
  love.graphics.setColor(c[1], c[2], c[3], 0.35 * pulse)
  px(ex - s, ey - s, s * 2 + 1, s * 2 + 1)
  love.graphics.setColor(c[1], c[2], c[3], pulse)
  px(ex - 1, ey - 1, 3, 3)
  love.graphics.setColor(1, 0.95, 0.95)
  px(ex, ey, 1, 1)
  if charging and e.beamA0 then
    -- the line it will sweep, shown dotted before it fires
    for _, ang in ipairs({ e.beamA0, e.beamA1 }) do
      for d = 14, 520, 9 do
        if math.floor(t * 14 + d / 9) % 2 == 0 then
          love.graphics.setColor(1, 0.4, 0.65, 0.4)
          px(ex + math.cos(ang) * d, ey + math.sin(ang) * d, 2, 2)
        end
      end
    end
  end
  if e.beamEnd then
    -- the beam itself
    local x1, y1 = e.beamEnd[1], e.beamEnd[2]
    local len = math.sqrt((x1 - ex) ^ 2 + (y1 - ey) ^ 2)
    for d = 0, len, 2 do
      local f = d / len
      local x, y = ex + (x1 - ex) * f, ey + (y1 - ey) * f
      love.graphics.setColor(1, 0.3, 0.6, 0.35)
      px(x - 3, y - 3, 7, 7)
      love.graphics.setColor(1, 0.7, 0.85, 0.8)
      px(x - 1, y - 1, 3, 3)
      love.graphics.setColor(1, 1, 1)
      px(x, y, 1, 1)
    end
    love.graphics.setColor(1, 0.8, 0.9, 0.7)
    px(x1 - 4, y1 - 4, 9, 9)
  end
end

-- The little golems and the thrown stones and stone waves
local function drawMiniGolem(e)
  local r = mirror(e, 14)
  local white = e.flash > 0
  local function col(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local w = e.grounded and math.abs(e.body.vx) > 4 and math.sin(e.phase * 1.5) or 0
  local strike = (e.strikeT or 0) > 0
  col(MARBLE.dark)
  r(2, 13, 4, 7 - math.max(0, w))
  r(8, 13, 4, 7 - math.max(0, -w))
  col(MARBLE.mid)
  r(1, 5, 12, 9)
  col(MARBLE.light)
  r(1, 5, 12, 2)
  col(MARBLE.deep)
  r(10, 7, 3, 7)
  col(MARBLE.mid)
  r(3, 0, 8, 6)
  col(MARBLE.light)
  r(3, 0, 8, 1)
  col(MARBLE.pink)
  r(4, 9, 3, 1)
  col(MARBLE.dark)
  if strike then
    r(11, 4, 5, 4)
  else
    r(12, 8 + w, 3, 5)
  end
end

local function drawMiniGolemGlow(e)
  local r = mirror(e, 14)
  love.graphics.setColor(1, 0.4, 0.65, 0.9)
  r(8, 2, 2, 1)
end

local function drawGolemShots()
  for _, s in ipairs(golemStones) do
    local x, y = math.floor(s.x), math.floor(s.y)
    love.graphics.setColor(0.52, 0.52, 0.6)
    love.graphics.rectangle("fill", x - 4, y - 4, 8, 8)
    love.graphics.setColor(0.88, 0.88, 0.94)
    love.graphics.rectangle("fill", x - 4 + math.floor(s.spin) % 2, y - 4, 6, 2)
    love.graphics.setColor(0.96, 0.5, 0.78)
    love.graphics.rectangle("fill", x - 2, y, 4, 1)
  end
  for _, w in ipairs(golemWaves) do
    local fade = math.min(1, w.life * 2)
    for k = 0, 4 do
      local h = 6 + 8 * math.abs(math.sin(k * 1.7 + w.x * 0.05))
      local x = w.x - w.dir * k * 5
      love.graphics.setColor(0.72, 0.72, 0.8, fade)
      love.graphics.polygon("fill", x - 4, w.y, x + 4, w.y, x, w.y - h * (1 - k * 0.15))
      love.graphics.setColor(0.92, 0.92, 0.97, fade)
      love.graphics.polygon("fill", x - 4, w.y, x - 1, w.y, x - 1, w.y - h * (1 - k * 0.15) + 2)
    end
  end
end

local function drawGolemShotsGlow()
  for _, s in ipairs(golemStones) do
    love.graphics.setColor(1, 0.5, 0.8, 0.35)
    love.graphics.rectangle("fill", math.floor(s.x) - 5, math.floor(s.y) - 5, 10, 10)
  end
  for _, w in ipairs(golemWaves) do
    love.graphics.setColor(1, 0.55, 0.85, 0.35 * math.min(1, w.life * 2))
    love.graphics.rectangle("fill", math.floor(w.x) - 5, math.floor(w.y) - 4, 10, 4)
  end
end

local DRAW = {
  golem = drawGolem,
  minigolem = drawMiniGolem,
  piranha = drawPiranha,
  worm = drawWorm,
  miner = drawMiner,
  roller = drawRoller,
  ghoul = drawGhoul,
  warden = drawWarden,
  bat = drawBat,
  swarmbat = drawBat,
  dreadbat = drawDreadBat,
  queen = queenfig.draw,
  spitter = drawSpitter,
  dummy = drawDummy,
  hopper = drawHopper,
  matron = drawMatron,
  bloater = drawBloater,
  behemoth = drawSac,
  wisp = function() end,
}
local GLOW = {
  golem = drawGolemGlow,
  minigolem = drawMiniGolemGlow,
  piranha = drawPiranhaEye,
  worm = function() end,
  miner = drawMinerGlow,
  roller = function() end,
  ghoul = drawGhoulEyes,
  warden = drawWardenGlow,
  bat = drawBatEyes,
  swarmbat = drawBatEyes,
  dreadbat = drawDreadBatGlow,
  queen = queenfig.glow,
  spitter = drawSpitterGlow,
  dummy = function() end,
  hopper = drawHopperEyes,
  matron = drawMatronGlow,
  bloater = drawBloaterGlow,
  behemoth = drawSacGlow,
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
  local m = e.segs and 80 or (e.def.drawMargin or 8) -- (a worm's tail trails far behind its head)
  return b.x + b.w > view.x - m and b.x < view.x + view.w + m and b.y + b.h > view.y - m and b.y < view.y + view.h + m
end

-- view: { x, y, w, h } in world pixels
-- (lit: drawing for the lit sprites pass, which leaves out the creatures that def.noRelief marks)
function enemies.draw(view, lit)
  for _, e in ipairs(near) do
    if onScreen(e, view) and not (lit and e.def.noRelief) then
      local off = staggerOffset(e)
      love.graphics.push()
      love.graphics.translate(off, 0)
      if not e.def.dummy then
        drawAura(e)
      end
      -- Status tints: frost, venom, acid, fire and shock wash over the sprite's
      -- own pixels (never a box round it); a hit flash stays plain white
      local t = love.timer.getTime()
      local tr, tg, tb, amount
      if e.flash <= 0 then
        tr, tg, tb, amount = statusTint(e, t)
        if not amount and e.elite then
          -- An elite pulses with its affix's colour (taking turns with two)
          local afx = e.elite.affixes
          local c = enemies.AFFIXES[afx[math.floor(t * 0.8 + e.phase) % #afx + 1]].color
          tr, tg, tb, amount = c[1], c[2], c[3], 0.2 + 0.12 * math.sin(t * 3 + e.phase)
        end
      end
      local shader = amount and getTintShader()
      if shader then
        love.graphics.setShader(shader)
        shader:send("tint", { tr, tg, tb })
        shader:send("amount", amount)
      end
      DRAW[e.kind](e)
      if shader then
        love.graphics.setShader()
      end
      drawDazed(e, t)
      love.graphics.pop()
    end
  end
  drawSticks()
  drawGolemShots()
  if enemies.afterDraw then
    enemies.afterDraw(view)
  end
end

-- (for the art tests: the drawing functions by kind)
enemies.DRAW, enemies.GLOW = DRAW, GLOW
enemies.UPDATE, enemies.VOICES = UPDATE, VOICES
enemies.helpers = { center = center, collider = collider, removePhysics = removePhysics, sfx = sfx, lineOfSight = lineOfSight }
for k, f in pairs(DRAW) do
  DRAW_REF[k] = f
end
for k, f in pairs(GLOW) do
  GLOW_REF[k] = f
end

-- After the lighting: eyes, glowing mouths and acid globs
function enemies.drawEmissive(view)
  drawSticksGlow()
  drawGolemShotsGlow()
  local t = love.timer.getTime()
  for _, e in ipairs(near) do
    if onScreen(e, view) then
      love.graphics.push()
      love.graphics.translate(staggerOffset(e), 0)
      GLOW[e.kind](e)
      if e.elite then
        -- The elite's crest: a small diamond per affix, bobbing over its head
        local b = e.body
        local n = #e.elite.affixes
        local bob = math.floor(math.sin(t * 2.5 + e.phase) + 0.5)
        local x0 = math.floor(b.x + b.w / 2 - (n * 4 - 1) / 2)
        local y = math.floor(b.y - 6 + bob)
        for i, a in ipairs(e.elite.affixes) do
          local c = enemies.AFFIXES[a].color
          local x = x0 + (i - 1) * 4
          love.graphics.setColor(c[1], c[2], c[3], 0.95)
          love.graphics.rectangle("fill", x + 1, y, 1, 3)
          love.graphics.rectangle("fill", x, y + 1, 3, 1)
          love.graphics.setColor(1, 1, 1, 0.9)
          love.graphics.rectangle("fill", x + 1, y + 1, 1, 1)
        end
      end
      love.graphics.pop()
    end
  end
  for _, g in ipairs(globs) do
    if g.drip then
      -- A drop of the Queen's slime: a falling teardrop with a glint, a little streak above it
      love.graphics.setColor(0.58, 0.64, 0.27, 0.5)
      px(g.x, g.y - 4, 1, 2)
      love.graphics.setColor(0.58, 0.68, 0.27)
      px(g.x - 1, g.y - 1, 3, 3)
      px(g.x, g.y - 2, 1, 1)
      love.graphics.setColor(0.9, 0.97, 0.6)
      px(g.x - 1, g.y - 1)
    else
      love.graphics.setColor(0.45, 0.9, 0.3)
      px(g.x - 1, g.y - 1, 3, 3)
      love.graphics.setColor(0.8, 1, 0.6)
      px(g.x, g.y)
    end
  end
  if enemies.afterEmissive then
    enemies.afterEmissive(view) -- (bosses in modules of their own: their shots and beams)
  end
end

-- Globs and spitters' mouths give off a faint sickly light
function enemies.addLights(lighting, view)
  for _, s in ipairs(sticks) do
    lighting.add(s.x, s.y, 36, 1, 0.55, 0.25, 0.6)
  end
  for _, g in ipairs(globs) do
    lighting.add(g.x, g.y, 26, 0.5, 1, 0.35, 0.7)
  end
  for _, e in ipairs(near) do
    if onScreen(e, view) then
      local cx, cy = center(e)
      -- The purple back-light, at a tenth of its old strength
      if not e.def.dummy then
        lighting.add(cx, cy, 13, AURA[1], AURA[2], AURA[3], e.state == "sleep" and 0.03 or 0.045)
      end
      if e.elite then
        local c = enemies.AFFIXES[e.elite.affixes[1]].color
        lighting.add(cx, cy, e.elite.has.burning and 44 or 26, c[1], c[2], c[3], e.elite.has.burning and 0.45 or 0.2)
      end
      if e.def.light then
        local l = e.def.light(e)
        if l then
          if type(l[1]) == "table" then
            for _, one in ipairs(l) do
              lighting.add(one[1], one[2], one[3], one[4], one[5], one[6], one[7])
            end
          else
            lighting.add(l[1], l[2], l[3], l[4], l[5], l[6], l[7])
          end
        end
      end
      if e.kind == "spitter" then
        lighting.add(cx, cy + 4, e.windup and 30 or 16, 0.5, 1, 0.35, 0.5)
      elseif e.kind == "miner" then
        lighting.add(cx + e.facing * 4, cy - 6, 64, 1, 0.84, 0.45, e.windT and 0.6 or 0.4) -- the hat lamp
      elseif e.kind == "wisp" then
        lighting.add(cx, cy, 46, 1, 0.6, 0.25, 0.7)
      elseif e.kind == "dreadbat" then
        lighting.add(cx, cy, 50, 0.85, 0.3, 0.5, 0.3) -- so the dark bulk can be seen
      elseif e.kind == "queen" then
        lighting.add(cx, cy, 110, 0.8, 0.95, 0.3, 0.55)
      elseif e.kind == "golem_old" then
        lighting.add(cx, e.body.y + 10, 70, 0.85, 0.8, 0.95, 0.18) -- so the pale bulk can be seen
        local ex, ey = golemEye(e)
        lighting.add(ex, ey, e.sub == "act" and e.gs == "beam" and 90 or 40, e.invuln and 0.5 or 1, e.invuln and 0.85 or 0.35, e.invuln and 1 or 0.6, 0.8)
        if e.beamEnd then
          lighting.add(e.beamEnd[1], e.beamEnd[2], 70, 1, 0.4, 0.7, 0.9)
        end
      elseif e.kind == "minigolem_old" then
        lighting.add(cx, cy - 6, 22, 1, 0.4, 0.65, 0.4)
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
local function drawBossPointer(sx, sy, sw, sh, unit, gold)
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
  if gold then
    love.graphics.setColor(1, 0.72 * pulse, 0.2 * pulse)
  else
    love.graphics.setColor(1, 0.25 * pulse, 0.24 * pulse)
  end
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
        local sx, sy = toScreen(b.x + b.w / 2, b.y - 8 - (e.def.barLift or 0))
        sy = math.max(sy, 44 + unit * 2.4) -- (kept on screen when her head is above it)
        local w, h = math.max(b.w * unit * 1.2, (e.gen or 0) > 0 and 48 or 140), math.max(10, unit * 2.4)
        w = math.min(w, sw * 0.55) -- (a boss as big as the screen keeps a bar that fits)
        sx = math.max(w / 2 + 8, math.min(sw - w / 2 - 8, sx))
        local x, y = math.floor(sx - w / 2), math.floor(sy - h)
        -- Flat: a plain dark trough and a red gradient fill, no glass shading
        love.graphics.setColor(0.10, 0.02, 0.04, 0.75)
        love.graphics.rectangle("fill", x, y, w, h)
        local frac = math.max(0, e.hp) / e.maxHp
        if frac > 0 then
          hud.gradRect(x, y, w * frac, h, { 0.95, 0.22, 0.26 }, { 0.62, 0.07, 0.13 })
        end
        if e.bossName then
          local nx, ny = math.floor(sx - font:getWidth(e.bossName) / 2), math.floor(y - font:getHeight() - 2)
          love.graphics.setColor(0, 0, 0, 0.85)
          love.graphics.print(e.bossName, nx + 2, ny + 2)
          love.graphics.setColor(1, 0.85, 0.8)
          love.graphics.print(e.bossName, nx, ny)
        end
      end
    end
    if e.bounty and not e.dead then
      -- A bounty off screen but near is pointed to in gold
      local x0, y0 = toScreen(b.x, b.y)
      local x1, y1 = toScreen(b.x + b.w, b.y + b.h)
      if x1 < 0 or x0 > sw or y1 < 0 or y0 > sh then
        local mx, my = toScreen(b.x + b.w / 2, b.y + b.h / 2)
        local far = math.max(math.abs(mx - sw / 2), math.abs(my - sh / 2)) / unit
        if far < BOUNTY_POINT then
          drawBossPointer(mx, my, sw, sh, unit, true)
        end
      end
    end
    if e.elite and not e.dead and (aggro or e.bounty) then
      -- An elite's bar: thinner than a boss's, edged in gold, its name over it
      local sx, sy = toScreen(b.x + b.w / 2, b.y - 9)
      if sx > -100 and sx < sw + 100 and sy > -40 and sy < sh + 40 then
        local w, h = math.max(b.w * unit * 1.6, 70), math.max(5, unit * 1.3)
        local x, y = math.floor(sx - w / 2), math.floor(sy - h)
        love.graphics.setColor(0.85, 0.66, 0.3, 0.85)
        love.graphics.rectangle("fill", x - 1, y - 1, w + 2, h + 2)
        love.graphics.setColor(0.10, 0.02, 0.04, 0.9)
        love.graphics.rectangle("fill", x, y, w, h)
        local frac = math.max(0, e.hp) / e.maxHp
        if frac > 0 then
          hud.gradRect(x, y, w * frac, h, { 0.95, 0.22, 0.26 }, { 0.62, 0.07, 0.13 })
        end
        local name = enemies.eliteName(e)
        local c = e.bounty and { 1, 0.75, 0.3 } or enemies.AFFIXES[e.elite.affixes[1]].color
        local nx, ny = math.floor(sx - font:getWidth(name) / 2), math.floor(y - font:getHeight() - 1)
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.print(name, nx + 2, ny + 2)
        love.graphics.setColor(math.min(1, c[1] * 0.4 + 0.6), math.min(1, c[2] * 0.4 + 0.6), math.min(1, c[3] * 0.4 + 0.6))
        love.graphics.print(name, nx, ny)
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

-- The water's creatures and the fish boss (src.aquatic) register themselves here
package.loaded["src.enemies"] = enemies
require("src.aquatic")
require("src.colossus")
require("src.darkhunter")
require("src.needlemobs")
require("src.quarrymobs")
require("src.ethercrawler")

-- The bosses and creatures in the modules above add their drawing functions after the
-- table was copied for the bestiary's portraits: copy again, or they come out blank
for k, f in pairs(DRAW) do
  DRAW_REF[k] = f
end
for k, f in pairs(GLOW) do
  GLOW_REF[k] = f
end

return enemies
