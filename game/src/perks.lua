-- Perks (design doc §5.8): passive upgrades for the whole run, taken one at
-- a time from the shop's perk pedestals (free, pick one of three). They have
-- no slot and can't be dropped. Like items they have a rarity, and cursed
-- perks are powerful with a real downside.
--
-- A perk's `fx` is a table of named numbers that the rest of the game asks
-- for through perks.sum(key) (added up) and perks.prod(key) (multiplied):
--   sum:  maxHp crit incendiary bounces pierce killHeal airJumps regen
--         lastStand (damage bonus below 30% HP) momentum secondWind
--         deathBurst adrenaline drain
--   prod: dmgTaken damage reload fireDelay spread speed jump gold shopPrice
--         healPrice loot magnet slideFriction kickDamage
local items = require("src.items")

local perks = {}

perks.rarities = items.rarities

perks.defs = {
  -- Survival ------------------------------------------------------------
  thick_skin = {
    name = "Thick Skin",
    short = "TS",
    color = { 0.85, 0.55, 0.45 },
    rarity = "common",
    desc = "+25 max health.",
    fx = { maxHp = 25 },
  },
  iron_will = {
    name = "Iron Will",
    short = "IW",
    color = { 0.62, 0.66, 0.78 },
    rarity = "rare",
    desc = "+50 max health.",
    fx = { maxHp = 50 },
  },
  second_wind = {
    name = "Second Wind",
    short = "SW",
    color = { 0.55, 0.90, 0.80 },
    rarity = "rare",
    desc = "The first lethal hit of the run leaves you on 30% health instead.",
    fx = { secondWind = 1 },
  },
  scar_tissue = {
    name = "Scar Tissue",
    short = "ST",
    color = { 0.75, 0.50, 0.50 },
    rarity = "common",
    desc = "Take 15% less damage.",
    fx = { dmgTaken = 0.85 },
  },
  last_stand = {
    name = "Last Stand",
    short = "LS",
    color = { 0.95, 0.40, 0.30 },
    rarity = "rare",
    desc = "Below 30% health, deal 50% more damage.",
    fx = { lastStand = 0.5 },
  },
  regeneration = {
    name = "Regeneration",
    short = "RG",
    color = { 0.45, 0.90, 0.50 },
    rarity = "rare",
    desc = "Heal 1 HP every 3 seconds.",
    fx = { regen = 1 / 3 },
  },
  bloodthirst = {
    name = "Bloodthirst",
    short = "BT",
    color = { 0.80, 0.15, 0.25 },
    rarity = "common",
    desc = "Heal 2 HP for every kill.",
    fx = { killHeal = 2 },
  },
  adrenaline = {
    name = "Adrenaline",
    short = "AD",
    color = { 1.0, 0.70, 0.30 },
    rarity = "common",
    desc = "Getting hurt makes you 35% faster for 3 seconds.",
    fx = { adrenaline = 1 },
  },

  -- Movement ------------------------------------------------------------
  springheel = {
    name = "Springheel",
    short = "SH",
    color = { 0.55, 0.85, 0.55 },
    rarity = "common",
    desc = "Jump 15% higher.",
    fx = { jump = 1.15 },
  },
  fleet_foot = {
    name = "Fleet Foot",
    short = "FF",
    color = { 0.60, 0.80, 0.95 },
    rarity = "common",
    desc = "Walk 15% faster.",
    fx = { speed = 1.15 },
  },
  slick_soles = {
    name = "Slick Soles",
    short = "SO",
    color = { 0.70, 0.75, 0.90 },
    rarity = "common",
    desc = "Slides carry far more momentum.",
    fx = { slideFriction = 0.45 },
  },
  double_jump = {
    name = "Double Jump",
    short = "DJ",
    color = { 0.75, 0.90, 1.0 },
    rarity = "rare",
    desc = "Jump once more in mid-air.",
    fx = { airJumps = 1 },
  },

  -- Economy -------------------------------------------------------------
  prospector = {
    name = "Prospector",
    short = "PS",
    color = { 1.0, 0.82, 0.25 },
    rarity = "common",
    desc = "Gold you pick up is worth 25% more.",
    fx = { gold = 1.25 },
  },
  haggler = {
    name = "Haggler",
    short = "HG",
    color = { 0.90, 0.75, 0.40 },
    rarity = "common",
    desc = "Everything in the shop costs 20% less.",
    fx = { shopPrice = 0.8, healPrice = 0.8 },
  },
  lucky_find = {
    name = "Lucky Find",
    short = "LF",
    color = { 0.45, 0.90, 0.45 },
    rarity = "rare",
    desc = "Monsters drop ammo and attachments two and a half times as often.",
    fx = { loot = 2.5 },
  },
  magnetic_pockets = {
    name = "Magnetic Pockets",
    short = "MP",
    color = { 0.85, 0.35, 0.40 },
    rarity = "common",
    desc = "Gold is drawn to you from much further away.",
    fx = { magnet = 2.5 },
  },

  -- Combat --------------------------------------------------------------
  sharp_eyes = {
    name = "Sharp Eyes",
    short = "SE",
    color = { 0.45, 0.80, 0.55 },
    rarity = "common",
    desc = "+10% crit chance with every gun (crits deal double damage).",
    fx = { crit = 0.10 },
  },
  heavy_hitter = {
    name = "Heavy Hitter",
    short = "HH",
    color = { 0.90, 0.55, 0.30 },
    rarity = "common",
    desc = "+15% damage with every gun.",
    fx = { damage = 1.15 },
  },
  quick_hands = {
    name = "Quick Hands",
    short = "QH",
    color = { 0.90, 0.85, 0.50 },
    rarity = "common",
    desc = "Reload 20% faster.",
    fx = { reload = 0.8 },
  },
  momentum = {
    name = "Momentum",
    short = "MM",
    color = { 1.0, 0.60, 0.25 },
    rarity = "rare",
    desc = "Each kill makes you fire 6% faster for 4 seconds, stacking up to five times.",
    fx = { momentum = 1 },
  },
  pyromaniac = {
    name = "Pyromaniac",
    short = "PY",
    color = { 1.0, 0.50, 0.15 },
    rarity = "rare",
    desc = "Every shot sets enemies alight.",
    fx = { incendiary = 1 },
  },
  ricochet_master = {
    name = "Ricochet Master",
    short = "RM",
    color = { 0.55, 0.85, 0.95 },
    rarity = "rare",
    desc = "Every bullet ricochets once.",
    fx = { bounces = 1 },
  },
  needle_sight = {
    name = "Needle Sight",
    short = "NS",
    color = { 0.78, 0.65, 0.90 },
    rarity = "rare",
    desc = "Every bullet passes through one extra enemy.",
    fx = { pierce = 1 },
  },
  death_burst = {
    name = "Death Burst",
    short = "DB",
    color = { 1.0, 0.45, 0.20 },
    rarity = "rare",
    desc = "Enemies you kill explode, hurting others nearby (never you).",
    fx = { deathBurst = 1 },
  },
  kicker = {
    name = "Kicker",
    short = "KK",
    color = { 0.80, 0.70, 0.55 },
    rarity = "common",
    desc = "Your kick hits three times as hard.",
    fx = { kickDamage = 3 },
  },

  -- Cursed --------------------------------------------------------------
  glass_cannon = {
    name = "Glass Cannon",
    short = "GC",
    color = { 0.80, 0.95, 1.0 },
    rarity = "cursed",
    desc = "CURSED: +60% damage with every gun, but you have 40% less max health.",
    fx = { damage = 1.6, maxHpMult = 0.6 },
  },
  devils_bargain = {
    name = "Devil's Bargain",
    short = "DV",
    color = { 0.85, 0.15, 0.20 },
    rarity = "cursed",
    desc = "CURSED: gold is worth double, but you take 50% more damage.",
    fx = { gold = 2.0, dmgTaken = 1.5 },
  },
  greedy_hands = {
    name = "Greedy Hands",
    short = "GH",
    color = { 0.95, 0.75, 0.10 },
    rarity = "cursed",
    desc = "CURSED: +60% gold and the shop's loot is yours for 30% less, but healing costs double.",
    fx = { gold = 1.6, shopPrice = 0.7, healPrice = 2.0 },
  },
  berserker = {
    name = "Berserker",
    short = "BK",
    color = { 0.90, 0.25, 0.15 },
    rarity = "cursed",
    desc = "CURSED: fire 40% faster and reload 30% faster, but your spread is 70% wider.",
    fx = { fireDelay = 0.6, reload = 0.7, spread = 1.7 },
  },
  pact_of_pain = {
    name = "Pact of Pain",
    short = "PP",
    color = { 0.60, 0.10, 0.45 },
    rarity = "cursed",
    desc = "CURSED: kills heal 6 HP and kicks deal triple damage, but you bleed 1 HP every 3 seconds (never to death).",
    fx = { killHeal = 6, kickDamage = 3, drain = 1 },
  },
}

perks.order = {
  "thick_skin", "iron_will", "second_wind", "scar_tissue", "last_stand", "regeneration", "bloodthirst", "adrenaline",
  "springheel", "fleet_foot", "slick_soles", "double_jump",
  "prospector", "haggler", "lucky_find", "magnetic_pockets",
  "sharp_eyes", "heavy_hitter", "quick_hands", "momentum", "pyromaniac", "ricochet_master", "needle_sight",
  "death_burst", "kicker",
  "glass_cannon", "devils_bargain", "greedy_hands", "berserker", "pact_of_pain",
}

-- The run's perks live in its inventory (inv.perks = { id, ... }); this
-- module reads whichever inventory was bound last (see inventory.new)
local owned = {}
perks.version = 0

function perks.bind(inv)
  owned = inv.perks
  perks.version = perks.version + 1
end

function perks.has(id)
  for _, p in ipairs(owned) do
    if p == id then
      return true
    end
  end
  return false
end

function perks.list()
  return owned
end

function perks.sum(key)
  local total = 0
  for _, id in ipairs(owned) do
    total = total + (perks.defs[id].fx[key] or 0)
  end
  return total
end

function perks.prod(key)
  local total = 1
  for _, id in ipairs(owned) do
    total = total * (perks.defs[id].fx[key] or 1)
  end
  return total
end

function perks.maxHp(base)
  return math.max(10, math.floor((base + perks.sum("maxHp")) * perks.prod("maxHpMult") + 0.5))
end

-- Adds a perk to the run
function perks.add(id)
  owned[#owned + 1] = id
  perks.version = perks.version + 1
end

-- A fresh perk instance for UI code (same shape as an item: name, short,
-- color, desc, rarity), with isPerk set
function perks.new(id)
  local def = assert(perks.defs[id], "unknown perk: " .. tostring(id))
  return { id = id, isPerk = true, name = def.name, short = def.short, color = def.color, rarity = def.rarity, desc = def.desc }
end

-- Three distinct perks the hunter doesn't have yet, weighted by rarity
function perks.roll(count, random)
  random = random or love.math.random
  local pool = {}
  for _, id in ipairs(perks.order) do
    if not perks.has(id) then
      pool[#pool + 1] = id
    end
  end
  local picked = {}
  for _ = 1, math.min(count, #pool) do
    local total = 0
    for _, id in ipairs(pool) do
      total = total + perks.rarities[perks.defs[id].rarity].weight
    end
    local roll = random() * total
    local chosen = #pool
    for i, id in ipairs(pool) do
      roll = roll - perks.rarities[perks.defs[id].rarity].weight
      if roll <= 0 then
        chosen = i
        break
      end
    end
    picked[#picked + 1] = table.remove(pool, chosen)
  end
  return picked
end

-- Applies the perks that change every gun to a freshly computed stats table
function perks.modifyStats(st)
  st.damage = st.damage * perks.prod("damage")
  st.reloadTime = st.reloadTime * perks.prod("reload")
  st.fireDelay = st.fireDelay * perks.prod("fireDelay")
  st.spread = st.spread * perks.prod("spread")
  st.critChance = st.critChance + perks.sum("crit")
  st.incendiary = st.incendiary + perks.sum("incendiary")
  st.bounces = st.bounces + perks.sum("bounces")
  st.pierce = st.pierce + perks.sum("pierce")
end

return perks
