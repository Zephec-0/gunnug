-- Gun definitions and the gun state machine (design doc §5).
-- A gun fires its chambers in order and reloads automatically once empty,
-- like a Noita wand's cast delay / recharge time.
local perks = require("src.perks")

local guns = {}

guns.defs = {
  revolver = {
    name = "Revolver",
    chambers = 6,
    fireDelay = 0.25,
    reloadTime = 1.2,
    spread = 2, -- degrees, total cone
    damage = 10,
    pellets = 1,
    bulletSpeed = 1040,
    recoil = 184, -- velocity impulse (px/s) applied opposite the shot
    impactForce = 256, -- impulse a bullet gives physics objects (deliberately exaggerated)
    digRadius = 4, -- crater size in terrain (pixels)
    digPower = 1, -- vs. material hardness: dirt 1, sandstone 2, rock 3
    slots = 4, -- ammo type / attachment slots (separate from chambers)
    model = "revolver", -- how the hunter holds and draws it (playeranim.lua)
    casing = { size = 3, eject = "reload" }, -- spent shells stay in the cylinder until a reload
    length = 8.8, -- grip to muzzle, in pixels
    kick = 1, -- strength of the cosmetic recoil kick in the hands
    flash = 1, -- muzzle flash size
    -- Inventory icon: L light steel, # dark steel, k black, c the part that
    -- moves when reloading (cylinder, drum or magazine), w dark and W light wood
    icon = {
      "                ",
      "     k  LLLLLLLL",
      "   kkLL#########",
      "  ###kcccccc####",
      "  ##Wkcccccc### ",
      " wWW###kkkk#    ",
      " wWWW   ##      ",
      " wWW            ",
    },
  },

  -- Double-barrel: two shells of buckshot, a wide cone and a huge kick.
  -- The best recoil jumper.
  shotgun = {
    name = "Double-Barrel",
    chambers = 2,
    fireDelay = 0.35,
    reloadTime = 1.5,
    spread = 15,
    damage = 6,
    pellets = 7,
    speedJitter = 0.15, -- pellets leave at +-15% of bulletSpeed, so the cone spreads out
    bulletSpeed = 900,
    recoil = 340,
    impactForce = 88, -- per pellet
    digRadius = 2,
    digPower = 1,
    slots = 3,
    slotBias = -1, -- generated shotguns average a slot fewer (many pellets per shot)
    model = "shotgun",
    casing = { size = 4, eject = "reload", hull = { 0.72, 0.17, 0.13 } }, -- both hulls pop out when it breaks open
    length = 12.5,
    kick = 1.4,
    flash = 1.8,
    icon = {
      "                ",
      "                ",
      "     LLLLLLLLLLL",
      "  wwk###########",
      " wWWWkcc#WWWW## ",
      "wWWW  cc  WW    ",
      "wWW             ",
      "ww              ",
    },
  },

  -- Broomhandle-style semi-automatic pistol: fast follow-ups, low recoil.
  semiauto = {
    name = "Broomhandle",
    chambers = 10,
    fireDelay = 0.15,
    reloadTime = 1.6,
    spread = 3,
    damage = 7,
    pellets = 1,
    bulletSpeed = 1000,
    recoil = 110,
    impactForce = 160,
    digRadius = 3,
    digPower = 1,
    slots = 4,
    model = "pistol",
    casing = { size = 2, eject = "shot" },
    length = 10,
    kick = 0.6,
    flash = 0.9,
    icon = {
      "                ",
      "   ###########  ",
      "  LLLLLLLLLLLL##",
      "  ##k##########L",
      "  ##  ccc  #    ",
      " wWW# ccc       ",
      "wWWW  ccc       ",
      "wWW             ",
    },
  },

  -- Early drum-fed machine gun: a long hose of weak rounds and a long reload.
  -- Its recoil is light per shot but sustained, so firing down slowly lifts
  -- the hunter for as long as the drum lasts.
  automatic = {
    name = "Machine Gun",
    chambers = 40,
    fireDelay = 0.06,
    reloadTime = 3.0,
    spread = 6,
    damage = 4,
    pellets = 1,
    bulletSpeed = 1100,
    recoil = 64,
    impactForce = 120,
    digRadius = 2,
    digPower = 1,
    slots = 4,
    slotBias = -1, -- a hose of bullets: average one slot fewer
    model = "automatic",
    casing = { size = 2, eject = "shot" },
    length = 11.5,
    kick = 0.45,
    flash = 0.7,
    icon = {
      "    ccccc       ",
      "   ccccccc      ",
      "LL##ccccc######L",
      "kkLLLLLLLLLLLL##",
      "wwW##  ##    #  ",
      "wWW#   ###      ",
      "wW     ##       ",
      "        #       ",
    },
  },
}

-- The Gatling: an old crank-style rotary gun with six barrels in a brass
-- frame and a hopper of rounds on top. The biggest ammo pool and the highest
-- rate of fire of any gun, but the barrels must spin up first: holding the
-- trigger winds them up over spoolTime (it can't fire below spoolMin, and
-- fires spoolSlow times slower at the start), and they wind down when let go.
-- Refilling the hopper takes a long time.
guns.defs.gatling = {
  name = "Gatling Gun",
  chambers = 150,
  fireDelay = 0.03,
  reloadTime = 6.0,
  spread = 7,
  damage = 4,
  pellets = 1,
  bulletSpeed = 1100,
  recoil = 38,
  impactForce = 100,
  digRadius = 2,
  digPower = 1,
  slots = 3,
  slotBias = -1,
  model = "gatling",
  casing = { size = 2, eject = "shot" },
  length = 13,
  kick = 0.3,
  flash = 0.7,
  spoolTime = 1.1, -- seconds of holding the trigger to full speed
  spoolMin = 0.2, -- it starts firing this far into the spin-up...
  spoolSlow = 5, -- ...this many times slower than full speed
  icon = {
    "      cccc      ",
    "      cccc      ",
    "WLLLLL##########",
    "W#####WWcccc#W  ",
    "WLLLLL##cccc#WW ",
    "W#####WWcccc# WW",
    "WLLLLL##########",
    "        k  #    ",
  },
}

-- Crossbow: one heavy bolt at a time, a slow wind-up between shots. The bolt
-- is fast and punches through up to two enemies, and it stays stuck in the rock
-- where it lands. Quiet, and no recoil to speak of.
guns.defs.crossbow = {
  name = "Crossbow",
  chambers = 1,
  fireDelay = 0.4,
  reloadTime = 1.35,
  spread = 0.8,
  damage = 46,
  pellets = 1,
  bulletSpeed = 1250,
  recoil = 40,
  impactForce = 420,
  digRadius = 2,
  digPower = 2,
  pierce = 2,
  bolt = true,
  slots = 4,
  slotBias = 0,
  model = "crossbow",
  length = 11,
  kick = 0.6,
  flash = 0.1,
  icon = {
    "     W          ",
    "     W    wwwwww",
    "     WLLLLLLLLww",
    "LLLLLLLLLLLL##Ww",
    "     W   ##wWWW ",
    "     W   #  WW  ",
    "     W          ",
    "                ",
  },
}

-- Flare pistol: a fat-barrelled signal gun. Its flares are slow, burn what they
-- hit and light the dark as they fly, and one that lands in the rock keeps
-- burning there for a while, lighting the way.
guns.defs.flare = {
  name = "Flare Pistol",
  chambers = 3,
  fireDelay = 0.5,
  reloadTime = 1.7,
  spread = 3.5,
  damage = 5,
  pellets = 1,
  bulletSpeed = 520,
  recoil = 70,
  impactForce = 120,
  digRadius = 2,
  digPower = 1,
  incendiary = 2,
  glow = 1,
  flare = true,
  slots = 4,
  model = "flare",
  casing = { size = 3, eject = "shot", hull = { 0.85, 0.3, 0.2 } },
  length = 8,
  kick = 1.1,
  flash = 1.4,
  icon = {
    "                ",
    "   kkkkkk       ",
    " ooOOOOOOkkkkk  ",
    " ooOOOOOO###LL# ",
    "   kkkkkk  #wWW ",
    "           wWW  ",
    "           wW   ",
    "                ",
  },
}

-- Short descriptions for the compendium (src.compendium)
local DESCS = {
  revolver = "Six chambers, a sharp crack and a solid kick. Spent shells stay in the cylinder until it is reloaded.",
  shotgun = "Two shells of buckshot in a wide cone, and a huge kick: the best gun for recoil jumping.",
  semiauto = "A Broomhandle-style pistol. Fast follow-up shots and very little recoil.",
  automatic = "An early drum-fed machine gun: a long hose of weak rounds and a long reload. Fired downward, it slowly lifts the hunter.",
  crossbow = "One heavy bolt at a time, slow to wind. The bolt is fast, pierces up to two enemies and stays stuck in the rock where it lands.",
  flare = "A signal pistol. Its slow flares burn what they hit and light the dark, and one that lands in rock keeps burning there for a while.",
  gatling = "Six spinning barrels and a hopper of 150 rounds: the fastest-firing gun there is, once its barrels have spun up. Refilling the hopper takes a long while.",
}
for id, def in pairs(guns.defs) do
  def.id = id
  def.desc = def.desc or DESCS[id]
end

local Gun = {}
Gun.__index = Gun

-- slotCount: how many ammo/attachment slots this particular gun has (a
-- generated gun rolls it; see guns.generate)
function guns.new(name, slotCount)
  local def = assert(guns.defs[name], "unknown gun: " .. tostring(name))
  local self = setmetatable({
    def = def,
    id = name, -- the archetype (guns.defs key)
    name = def.name, -- generated guns get a prefix (e.g. "Rapid Revolver")
    rolls = nil, -- generated guns: stat multipliers rolled when they were made
    chambers = def.chambers,
    fireTimer = 0,
    reloadTimer = 0,
    reloadTotal = def.reloadTime,
    slotCount = slotCount or def.slots,
    slots = {}, -- slots[i] = item or nil, for i = 1..slotCount
    burstLeft = 0, -- shots still to come in the current burst (Burst Fire)
    heat = 0, -- Overclock: builds with every shot, bleeds off when idle
    fresh = true, -- freshly reloaded: Primer Coil's double-damage shot is ready
    drawn = false, -- just switched to: Quickdraw Holster's shot is ready
    shotCount = 0, -- Mortar Breech fires every fifth shot big
    spent = 0, -- spent shells still in the gun (revolver, double-barrel)
    spool = 0, -- Gatling: how far the barrels have spun up (0..1)
    spin = 0, -- Gatling: the barrels' turn, for drawing
  }, Gun)
  return self
end

-- The gun's effective stats: its definition with every fitted ammo type and
-- attachment applied (design doc §5.5), then the hunter's perks. Cached until
-- the slots or the perks change.
local MULTIPLIED = { "damage", "spread", "recoil", "fireDelay", "reloadTime", "bulletSpeed", "impactForce", "chambers" }
-- Everything that adds up: base stats first, then the effect counts (see
-- src.items for what each does)
local ADDED = {
  "pellets", "digRadius", "digPower", "critChance", "magnet", "lamp",
  "pierce", "bounces", "explosive", "incendiary",
  "freeze", "shock", "poison", "acid", "concussive",
  "vamp", "greed", "refill",
  "sticky", "homing", "gravity", "split", "cluster",
  "boomerang", "ghost", "execute", "glow", "sneak",
  "bloodCost", "misfire",
  "bleed", "leech", "ramp", "lastRound", "blastSize", "bounceBoost", "critBoost", "far", "close",
  "burst", "rear", "opener", "quickdraw", "mortar",
  "laser", "bayonet", "overheat", "jets", "steady", "vulnerable", "bgReload",
  "vaultDig", "moveSpeed",
}
-- Ammo with any of these tints its bullets with the item's colour
local TINTING = {
  "incendiary", "explosive", "freeze", "shock", "poison", "acid", "vamp", "greed", "sticky", "homing", "gravity",
  "split", "cluster", "boomerang", "ghost", "execute", "glow", "concussive", "bloodCost", "misfire",
  "bleed", "leech", "bounceBoost",
}
-- Effects handed to every bullet (see src.bullets)
local BULLET_FX = {
  "freeze", "shock", "poison", "acid", "concussive", "vamp", "greed", "refill", "sticky", "homing", "gravity",
  "split", "cluster", "boomerang", "ghost", "execute", "glow", "sneak",
  "bleed", "leech", "bounceBoost", "far", "close", "vaultDig",
}

-- Effects whose order in the slots matters: what a bullet does on impact, against
-- how many times it bounces first (see src.bullets)
local ORDERED = { "bounces", "split", "cluster", "explosive", "gravity" }

function Gun:stats()
  local ids = { perks.version }
  for i = 1, self.slotCount do
    local item = self.slots[i]
    ids[#ids + 1] = item and (item.id .. "+" .. (item.level or 0)) or "-"
  end
  local signature = table.concat(ids, ",")
  if self.statsSignature == signature then
    return self.cached
  end

  local def = self.def
  local st = {
    damage = def.damage,
    spread = def.spread,
    recoil = def.recoil,
    fireDelay = def.fireDelay,
    reloadTime = def.reloadTime,
    bulletSpeed = def.bulletSpeed,
    impactForce = def.impactForce,
    chambers = def.chambers,
  }
  for _, k in ipairs(ADDED) do
    st[k] = def[k] or 0
  end
  if self.rolls then
    for _, k in ipairs(MULTIPLIED) do
      st[k] = st[k] * (self.rolls[k] or 1)
    end
  end
  -- Damage from fitted items adds up (+50% and +25% make +75%, not +87%);
  -- the other stats still multiply
  local damageBonus = 0
  for i = 1, self.slotCount do
    local item = self.slots[i]
    if item then
      for _, k in ipairs(MULTIPLIED) do
        if k == "damage" then
          local m = item.mods.damage or 1
          damageBonus = damageBonus + (m > 1 and (m - 1) or (m - 1) * 0.8)
        else
          st[k] = st[k] * (item.mods[k] or 1)
        end
      end
      for _, k in ipairs(ADDED) do
        st[k] = st[k] + (item.mods[k] or 0)
      end
    end
  end
  st.damage = st.damage * math.max(0.3, 1 + damageBonus)
  -- Order of operations: where in the slots each order-sensitive effect sits
  -- (first slot that carries it), so src.bullets can tell which happens first
  local order = {}
  for _, k in ipairs(ORDERED) do
    for i = 1, self.slotCount do
      local item = self.slots[i]
      if item and (item.mods[k] or 0) > 0 then
        order[k] = i
        break
      end
    end
  end
  st.order = order
  perks.modifyStats(st)
  st.chambers = math.max(1, math.floor(st.chambers + 0.5))
  st.damage = math.max(1, st.damage)
  st.critChance = math.min(0.95, st.critChance)
  st.fireDelay = math.max(0.03, st.fireDelay)
  self.statsSignature, self.cached = signature, st
  -- A smaller magazine can't hold more rounds than it has room for
  self.chambers = math.min(self.chambers, st.chambers)
  return st
end

-- Weapon generation (design doc §9a) ----------------------------------------
-- A generated weapon is a base archetype plus stat variation: two stats rolled
-- better (+8-18%), one rolled worse (-5-12%), the rest nudged a little (+-4%),
-- named after its best roll, and each ammo/attachment slot has a chance of
-- already holding something. The number of slots is rolled too: from two
-- fewer than the archetype's base up to five more, mostly near the middle
-- (shotguns and machine guns average a slot fewer, see def.slotBias).
local ROLL_STATS = {
  -- stat, which way is better (+1 higher, -1 lower), name prefix when rolled better
  { "damage", 1, "Heavy" },
  { "fireDelay", -1, "Rapid" },
  { "reloadTime", -1, "Swift" },
  { "spread", -1, "Accurate" },
  { "bulletSpeed", 1, "Longshot" },
  { "impactForce", 1, "Punching" },
  { "chambers", 1, "Capacious" },
  { "recoil", 0, nil }, -- neither better nor worse; only nudged
}
-- Slot roll: { cumulative chance, slots added }
local SLOT_ROLLS = {
  { 0.10, -2 }, { 0.22, -1 }, { 0.50, 0 }, { 0.72, 1 }, { 0.86, 2 }, { 0.94, 3 }, { 0.98, 4 }, { 1.00, 5 },
}
local FIT_CHANCE = 0.22 -- chance each slot of a generated gun is already filled
local ARCHETYPE_ORDER = { "revolver", "shotgun", "semiauto", "automatic", "gatling", "crossbow", "flare" }

-- How many slots a freshly generated gun of this archetype gets
local function rollSlots(def, random)
  local r = random()
  local delta = 0
  for _, entry in ipairs(SLOT_ROLLS) do
    if r <= entry[1] then
      delta = entry[2]
      break
    end
  end
  return math.max(1, def.slots + delta + (def.slotBias or 0))
end

-- Hooks set by src.meta (the camp's upgrades and the unlocked pool):
guns.isAvailable = nil -- function(archetype): may it be generated at random?
guns.rollBoost = nil -- function(): how much better bonuses roll (1 = as normal)
guns.extraSlotChance = nil -- function(): chance of one slot more

-- rng: a love.math RandomGenerator (default: the global one);
-- fitChance: chance each slot already holds an item (default FIT_CHANCE)
function guns.generate(archetype, rng, fitChance)
  local items = require("src.items")
  local random = rng and function(...) return rng:random(...) end or love.math.random
  if not archetype then
    local pool = {}
    for _, id in ipairs(ARCHETYPE_ORDER) do
      if not guns.isAvailable or guns.isAvailable(id) then
        pool[#pool + 1] = id
      end
    end
    if #pool == 0 then
      pool = { "revolver" }
    end
    archetype = pool[random(1, #pool)]
  end
  local slots = rollSlots(guns.defs[archetype], random)
  if guns.extraSlotChance and random() < guns.extraSlotChance() then
    slots = slots + 1
  end
  local gun = guns.new(archetype, slots)
  local boost = guns.rollBoost and guns.rollBoost() or 1

  local order = {}
  for i = 1, 7 do
    order[i] = i
  end
  for i = #order, 2, -1 do
    local j = random(1, i)
    order[i], order[j] = order[j], order[i]
  end
  -- A quality tier is rolled first (F D C B A S SS: C is the usual weapon, F and
  -- SS are very rare) and scales how much the good and bad rolls swing. The
  -- camp's roll-boost upgrade pushes the odds toward the better tiers.
  local TIERS = {
    { w = 4, pos = 0.10, neg = 2.5 }, -- F
    { w = 22, pos = 0.50, neg = 1.6 }, -- D
    { w = 40, pos = 1.00, neg = 1.0 }, -- C
    { w = 22, pos = 1.50, neg = 0.7 }, -- B
    { w = 9, pos = 2.20, neg = 0.4 }, -- A
    { w = 2.6, pos = 3.20, neg = 0.15 }, -- S
    { w = 0.4, pos = 5.00, neg = 0 }, -- SS
  }
  local total = 0
  for i, t in ipairs(TIERS) do
    t.eff = t.w * boost ^ (i - 3)
    total = total + t.eff
  end
  local pick, tier = random() * total, TIERS[3]
  for _, t in ipairs(TIERS) do
    pick = pick - t.eff
    if pick <= 0 then
      tier = t
      break
    end
  end
  local rolls = {}
  local best
  local function apply(stat, dir, amount)
    -- amount > 0 is better; "lower is better" stats shrink instead
    rolls[stat] = dir >= 0 and (1 + amount) or (1 - math.min(amount * 0.8, 0.65))
  end
  for rank, idx in ipairs(order) do
    local stat, dir, prefix = ROLL_STATS[idx][1], ROLL_STATS[idx][2], ROLL_STATS[idx][3]
    if dir ~= 0 and rank <= 2 then
      apply(stat, dir, (0.08 + random() * 0.10) * tier.pos)
      if stat == "chambers" then
        -- Whole chambers only: a "capacious" gun always holds at least one more
        rolls.chambers = math.max(rolls.chambers, (gun.def.chambers + 1) / gun.def.chambers)
      end
      best = best or prefix
    elseif dir ~= 0 and rank == 3 then
      apply(stat, dir, -(0.05 + random() * 0.07) * tier.neg)
    else
      apply(stat, dir == 0 and 1 or dir, (random() * 2 - 1) * 0.04)
    end
  end
  gun.rolls = rolls
  if best then
    gun.name = best .. " " .. gun.def.name
  end

  -- Pre-fitted ammo and attachments, never the same one twice
  local used = {}
  for slot = 1, gun.slotCount do
    if random() < (fitChance or FIT_CHANCE) then
      local item = items.random(random)
      if not used[item.id] then
        used[item.id] = true
        gun.slots[slot] = item
      end
    end
  end
  gun.generated = true
  return gun
end

function guns.archetypes()
  return ARCHETYPE_ORDER
end

function Gun:maxChambers()
  return self:stats().chambers
end

-- A gun in the holster: its timers cool off but any reload is paused
function Gun:updateHolstered(dt)
  self.fireTimer = math.max(0, self.fireTimer - dt)
  self.heat = math.max(0, self.heat - 4 * dt)
  self.spool = math.max(0, self.spool - dt * 2)
end

-- Gatling: winds the barrels up while the trigger is held (and the gun isn't
-- reloading), down when it's let go. Called every frame for the held gun.
function Gun:spinUp(dt, held)
  local def = self.def
  if not def.spoolTime then
    return
  end
  if held and self.reloadTimer <= 0 and self.chambers > 0 then
    self.spool = math.min(1, self.spool + dt / def.spoolTime)
  else
    self.spool = math.max(0, self.spool - dt / (def.spoolTime * 0.7))
  end
  self.spin = (self.spin + dt * (1 + 30 * self.spool)) % 6
end

-- Switching away mid-reload throws the reload away: it starts over next time
function Gun:cancelReload()
  self.reloadTimer = 0
  self.burstLeft = 0
end

function Gun:update(dt)
  self.fireTimer = math.max(0, self.fireTimer - dt)
  self.heat = math.max(0, self.heat - 4 * dt)
  if self.chambers <= 0 and self.reloadTimer <= 0 and not guns.manualReload then
    self:reload() -- an empty gun goes straight back to reloading (unless a hat says to do it by hand)
  end
  if self.reloadTimer > 0 then
    self.reloadTimer = self.reloadTimer - dt
    if self.reloadTimer <= 0 then
      self.reloadTimer = 0
      self.chambers = self:maxChambers()
      self.fresh = true
      self.burstLeft = 0
      self.heat = 0
    end
  end
end

function Gun:isReloading()
  return self.reloadTimer > 0
end

-- 0 at the start of a reload, 1 when finished
function Gun:reloadProgress()
  return 1 - self.reloadTimer / self.reloadTotal
end

-- Starts a reload (right click, or automatically when empty). Takes the gun's
-- full reload time. Returns true if a reload started.
function Gun:reload()
  local st = self:stats()
  if self.reloadTimer > 0 or self.chambers >= st.chambers then
    return false
  end
  self.reloadTimer = st.reloadTime
  self.reloadTotal = st.reloadTime
  self.burstLeft = 0
  self.rampCount = 0
  return true
end

-- A kill with Scavenger Bolt: puts rounds back in the gun, or speeds up a reload
function Gun:refill(n)
  if self.reloadTimer > 0 then
    self.reloadTimer = math.max(0.001, self.reloadTimer - 0.5 * n)
  else
    self.chambers = math.min(self:maxChambers(), self.chambers + n)
  end
end

function Gun:canFire()
  return self.chambers > 0 and self.fireTimer <= 0 and self.reloadTimer <= 0
end

-- Fires the next chamber. Returns a list of shots (see bullets.spawn) or nil,
-- plus a table of side effects for the hunter: { cost = HP lost, misfire = true }.
-- ctx (all optional): { damageMult, fireRate, still } from the hunter.
function Gun:fire(angle, ctx)
  if not self:canFire() then
    return nil
  end
  ctx = ctx or {}
  local def, st = self.def, self:stats()
  if def.spoolTime and self.spool < def.spoolMin then
    return nil -- the barrels are still winding up
  end
  self.chambers = self.chambers - 1
  self.shotCount = self.shotCount + 1
  local lastRound = self.chambers == 0 and st.lastRound > 0
  if def.casing and def.casing.eject == "reload" then
    self.spent = math.min(self.spent + 1, def.chambers)
  end

  local delay = st.fireDelay / (ctx.fireRate or 1)
  if def.spoolTime then
    delay = delay * (1 + (def.spoolSlow - 1) * (1 - self.spool) ^ 2)
  end
  local mult = ctx.damageMult or 1
  if self.fresh and st.opener > 0 then
    mult = mult * (1 + st.opener) -- Primer Coil
  end
  if st.ramp > 0 then
    mult = mult * (1 + st.ramp * math.min(10, self.rampCount or 0)) -- Rampant Trigger
    self.rampCount = (self.rampCount or 0) + 1
  end
  if lastRound then
    mult = mult * (1 + st.lastRound) -- Reaper Chamber
  end
  self.fresh = false
  if self.drawn and st.quickdraw > 0 then
    mult = mult * (1 + st.quickdraw) -- Quickdraw Holster
  end
  self.drawn = false

  if st.burst > 0 then
    if self.burstLeft > 0 then
      self.burstLeft = self.burstLeft - 1
    else
      self.burstLeft = 1 + st.burst
    end
    delay = self.burstLeft > 0 and 0.055 or delay * 2.2
  end
  self.fireTimer = delay

  if st.overheat > 0 then
    self.heat = self.heat + 1
    if self.heat >= 9 then
      self.heat = 0
      self.chambers = 0 -- jammed: the magazine is dumped and the gun reloads
    end
  end
  if self.chambers == 0 then
    self.reloadTimer = st.reloadTime
    self.reloadTotal = st.reloadTime
    self.burstLeft = 0
    self.rampCount = 0
  end

  -- Tracer colour: the last fitted ammo type with an effect
  local tint
  for i = 1, self.slotCount do
    local item = self.slots[i]
    if item and item.kind == "ammo" then
      for _, k in ipairs(TINTING) do
        if item.mods[k] then
          tint = item.color
          break
        end
      end
    end
  end

  local fx = { gun = self, order = st.order }
  for _, k in ipairs(BULLET_FX) do
    fx[k] = st[k]
  end

  local pellets = st.pellets
  local explosive = st.explosive
  local bigBlast = st.mortar > 0 and self.shotCount % 5 == 0
  if bigBlast then
    explosive = explosive + 2
  end
  local spread = st.spread * ((st.steady > 0 and ctx.still) and 0.12 or 1)
  local shots = {}
  local function makeShot(shotAngle, damageScale)
    local crit = love.math.random() < st.critChance
    local jitter = (def.speedJitter or 0) * (love.math.random() * 2 - 1)
    local damage = st.damage * mult * damageScale * (crit and (2 + st.critBoost) or 1)
    shots[#shots + 1] = {
      angle = shotAngle,
      speed = st.bulletSpeed * (1 + jitter),
      damage = math.max(1, math.floor(damage + 0.5)),
      crit = crit,
      impact = st.impactForce,
      digRadius = st.digRadius,
      digPower = st.digPower,
      pierce = st.pierce,
      bounces = st.bounces,
      -- Explosions are scaled down for multi-pellet shots so a shotgun blast
      -- isn't seven full explosions
      explosive = explosive > 0 and {
        count = explosive,
        scale = (pellets > 1 and 1 / math.sqrt(pellets) or (bigBlast and 1.3 or 1)) * (1 + st.blastSize),
      } or nil,
      bolt = def.bolt,
      flare = def.flare,
      burn = st.incendiary > 0 and { dps = 3 * st.incendiary, time = 2 + st.incendiary } or nil,
      tint = tint,
      fx = fx,
    }
  end
  for _ = 1, pellets do
    makeShot(angle + math.rad(spread) * (love.math.random() - 0.5), 1)
  end
  if st.rear > 0 then
    makeShot(angle + math.pi + math.rad(spread) * (love.math.random() - 0.5), 0.6)
  end

  local sideEffects
  if st.bloodCost > 0 or st.misfire > 0 then
    sideEffects = {
      cost = st.bloodCost,
      misfire = st.misfire > 0 and love.math.random() < math.min(0.6, 0.2 * st.misfire),
    }
  end
  return shots, sideEffects
end

return guns
