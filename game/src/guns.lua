-- Gun definitions and the gun state machine (design doc §5).
-- A gun fires its chambers in order and reloads automatically once empty,
-- like a Noita wand's cast delay / recharge time.
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
    length = 8.8, -- grip to muzzle, in pixels
    kick = 1, -- strength of the cosmetic recoil kick in the hands
    flash = 1, -- muzzle flash size
    -- Inventory icon: L light steel, # dark steel, c cylinder, w wood grip
    icon = {
      "                ",
      "   LLLLLLLLLLLLL",
      "  #############L",
      "  ####ccc###    ",
      "  ##  ccc  #    ",
      " www###  ##     ",
      "wwww            ",
      "www             ",
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
    model = "shotgun",
    length = 12.5,
    kick = 1.4,
    flash = 1.8,
    icon = {
      "                ",
      "                ",
      "     LLLLLLLLLLL",
      "www#############",
      "wwwwww##c       ",
      "wwww   #        ",
      "ww              ",
      "                ",
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
    length = 10,
    kick = 0.6,
    flash = 0.9,
    icon = {
      "                ",
      "   ############ ",
      "  LLLLLLLLLLLLL#",
      "  ####cc########",
      "  ##   ##  #    ",
      " www#  ##       ",
      "wwww# ###       ",
      "www   ##        ",
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
    slots = 5,
    model = "automatic",
    length = 11.5,
    kick = 0.45,
    flash = 0.7,
    icon = {
      "                ",
      "     ##         ",
      "LL#############L",
      "  #######cccccLL",
      "ww###  ##       ",
      "www#   ###      ",
      "ww     ###      ",
      "        #       ",
    },
  },
}

local Gun = {}
Gun.__index = Gun

function guns.new(name)
  local def = assert(guns.defs[name], "unknown gun: " .. tostring(name))
  local self = setmetatable({
    def = def,
    name = def.name, -- generated guns get a prefix (e.g. "Rapid Revolver")
    rolls = nil, -- generated guns: stat multipliers rolled when they were made
    chambers = def.chambers,
    fireTimer = 0,
    reloadTimer = 0,
    reloadTotal = def.reloadTime,
    slots = {}, -- slots[i] = item or nil, for i = 1..def.slots
  }, Gun)
  return self
end

-- The gun's effective stats: its definition with every fitted ammo type and
-- attachment applied (design doc §5.5). Cached until the slots change.
local MULTIPLIED = { "damage", "spread", "recoil", "fireDelay", "reloadTime", "bulletSpeed", "impactForce", "chambers" }
local ADDED = { "pellets", "digRadius", "digPower" }
local EFFECTS = { "pierce", "bounces", "explosive", "incendiary" }

function Gun:stats()
  local ids = {}
  for i = 1, self.def.slots do
    ids[i] = self.slots[i] and self.slots[i].id or "-"
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
    pellets = def.pellets,
    digRadius = def.digRadius,
    digPower = def.digPower,
    pierce = 0,
    bounces = 0,
    explosive = 0,
    incendiary = 0,
  }
  if self.rolls then
    for _, k in ipairs(MULTIPLIED) do
      st[k] = st[k] * (self.rolls[k] or 1)
    end
  end
  for i = 1, def.slots do
    local item = self.slots[i]
    if item then
      for _, k in ipairs(MULTIPLIED) do
        st[k] = st[k] * (item.mods[k] or 1)
      end
      for _, k in ipairs(ADDED) do
        st[k] = st[k] + (item.mods[k] or 0)
      end
      for _, k in ipairs(EFFECTS) do
        st[k] = st[k] + (item.mods[k] or 0)
      end
    end
  end
  st.chambers = math.max(1, math.floor(st.chambers + 0.5))
  st.damage = math.max(1, st.damage)
  self.statsSignature, self.cached = signature, st
  -- A smaller magazine can't hold more rounds than it has room for
  self.chambers = math.min(self.chambers, st.chambers)
  return st
end

-- Weapon generation (design doc §9a) ----------------------------------------
-- A generated weapon is a base archetype plus stat variation: two stats rolled
-- better (+8-18%), one rolled worse (-5-12%), the rest nudged a little (+-4%),
-- named after its best roll, and each ammo/attachment slot has a chance of
-- already holding something.
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
local FIT_CHANCE = 0.22 -- chance each slot of a generated gun is already filled
local ARCHETYPE_ORDER = { "revolver", "shotgun", "semiauto", "automatic" }

-- rng: a love.math RandomGenerator (default: the global one)
function guns.generate(archetype, rng)
  local items = require("src.items")
  local random = rng and function(...) return rng:random(...) end or love.math.random
  archetype = archetype or ARCHETYPE_ORDER[random(1, #ARCHETYPE_ORDER)]
  local gun = guns.new(archetype)

  local order = {}
  for i = 1, 7 do
    order[i] = i
  end
  for i = #order, 2, -1 do
    local j = random(1, i)
    order[i], order[j] = order[j], order[i]
  end
  local rolls = {}
  local best
  local function apply(stat, dir, amount)
    -- amount > 0 is better; "lower is better" stats shrink instead
    rolls[stat] = dir >= 0 and (1 + amount) or (1 - amount * 0.8)
  end
  for rank, idx in ipairs(order) do
    local stat, dir, prefix = ROLL_STATS[idx][1], ROLL_STATS[idx][2], ROLL_STATS[idx][3]
    if dir ~= 0 and rank <= 2 then
      apply(stat, dir, 0.08 + random() * 0.10)
      if stat == "chambers" then
        -- Whole chambers only: a "capacious" gun always holds at least one more
        rolls.chambers = math.max(rolls.chambers, (gun.def.chambers + 1) / gun.def.chambers)
      end
      best = best or prefix
    elseif dir ~= 0 and rank == 3 then
      apply(stat, dir, -(0.05 + random() * 0.07))
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
  for slot = 1, gun.def.slots do
    if random() < FIT_CHANCE then
      local item = items.new(items.order[random(1, #items.order)])
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

function Gun:update(dt)
  self.fireTimer = math.max(0, self.fireTimer - dt)
  if self.reloadTimer > 0 then
    self.reloadTimer = self.reloadTimer - dt
    if self.reloadTimer <= 0 then
      self.reloadTimer = 0
      self.chambers = self:maxChambers()
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
  return true
end

function Gun:canFire()
  return self.chambers > 0 and self.fireTimer <= 0 and self.reloadTimer <= 0
end

-- Fires the next chamber. Returns a list of shots (see bullets.spawn) or nil.
function Gun:fire(angle)
  if not self:canFire() then
    return nil
  end
  local def, st = self.def, self:stats()
  self.chambers = self.chambers - 1
  self.fireTimer = st.fireDelay
  if self.chambers == 0 then
    self.reloadTimer = st.reloadTime
    self.reloadTotal = st.reloadTime
  end

  -- Tracer colour: the last fitted ammo type that has one
  local tint
  for i = 1, def.slots do
    local item = self.slots[i]
    if item and item.kind == "ammo" and (item.mods.incendiary or item.mods.explosive) then
      tint = item.color
    end
  end

  local pellets = st.pellets
  local shots = {}
  for i = 1, pellets do
    local offset = math.rad(st.spread) * (love.math.random() - 0.5)
    local jitter = (def.speedJitter or 0) * (love.math.random() * 2 - 1)
    shots[i] = {
      angle = angle + offset,
      speed = st.bulletSpeed * (1 + jitter),
      damage = math.max(1, math.floor(st.damage + 0.5)),
      impact = st.impactForce,
      digRadius = st.digRadius,
      digPower = st.digPower,
      pierce = st.pierce,
      bounces = st.bounces,
      -- Explosions are scaled down for multi-pellet shots so a shotgun blast
      -- isn't seven full explosions
      explosive = st.explosive > 0 and {
        count = st.explosive,
        scale = pellets > 1 and 1 / math.sqrt(pellets) or 1,
      } or nil,
      burn = st.incendiary > 0 and { dps = 3 * st.incendiary, time = 2 + st.incendiary } or nil,
      tint = tint,
    }
  end
  return shots
end

return guns
