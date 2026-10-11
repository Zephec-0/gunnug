-- Ammo types and attachments (design doc §5.5, §5.7). Every one is just data: a
-- table of modifiers applied to the gun it is fitted in. Each filled slot
-- applies on its own and order doesn't matter; ammo types stack, so a gun
-- loaded with several gets all their effects at once.
--
-- Modifiers (src.guns computes a gun's effective stats from them):
--   multiplied (default 1):  damage, spread, recoil, fireDelay, reloadTime,
--                            bulletSpeed, impactForce, chambers
--   added (default 0):       pellets, digRadius, digPower, critChance (0-1),
--                            magnet (px), lamp (px of light), and the effect
--                            counts below, which add up as more are fitted:
--     pierce bounces explosive incendiary      (the original four)
--     freeze shock poison acid concussive      (status effects on a hit)
--     vamp greed refill                        (on a kill: heal, gold, ammo)
--     sticky homing gravity split cluster      (how a bullet flies / ends)
--     boomerang ghost execute glow sneak       (more bullet behaviour)
--     bloodCost misfire                        (curses: cost HP, blow up)
--     burst rear opener quickdraw mortar       (how the gun fires)
--     laser bayonet overheat jets steady       (gun / hunter behaviour)
--     vulnerable                               (curse: damage taken +20% each)
--
-- Rarity: "common", "rare" or "cursed" (powerful, with a real downside).
-- An item is a table { kind = "ammo" | "attachment", id, name, short, color,
-- rarity, desc, mods }.
local items = {}

items.rarities = {
  common = { name = "Common", weight = 70, price = { 20, 35 }, border = { 0.55, 0.52, 0.50 } },
  rare = { name = "Rare", weight = 24, price = { 45, 70 }, border = { 0.35, 0.65, 1.0 } },
  cursed = { name = "Cursed", weight = 6, price = { 35, 55 }, border = { 0.85, 0.15, 0.20 } },
}

items.defs = {
  -- Ammo: the original six --------------------------------------------------
  slug = {
    kind = "ammo",
    name = "Heavy Slug",
    short = "SL",
    color = { 0.62, 0.62, 0.68 },
    rarity = "common",
    desc = "Heavier shot: +50% damage, double impact. Kicks harder, shoots a little slower, tighter.",
    mods = { damage = 1.5, impactForce = 2, recoil = 1.3, spread = 0.7, fireDelay = 1.15 },
  },
  piercing = {
    kind = "ammo",
    name = "Piercing Rounds",
    short = "PR",
    color = { 0.85, 0.62, 0.30 },
    rarity = "rare",
    desc = "Bullets pass through an enemy and keep going. Punches through soft rock a little. -10% damage.",
    mods = { pierce = 1, digPower = 1, damage = 0.9 },
  },
  ricochet = {
    kind = "ammo",
    name = "Ricochet Rounds",
    short = "RC",
    color = { 0.55, 0.85, 0.95 },
    rarity = "common",
    desc = "Bullets bounce off terrain twice before stopping.",
    mods = { bounces = 2 },
  },
  explosive = {
    kind = "ammo",
    name = "Explosive Rounds",
    short = "EX",
    color = { 1.0, 0.45, 0.15 },
    rarity = "rare",
    desc = "Bullets explode on impact, hurting everything nearby (including you). -20% damage, slower fire.",
    mods = { explosive = 1, damage = 0.8, fireDelay = 1.2 },
  },
  incendiary = {
    kind = "ammo",
    name = "Incendiary Rounds",
    short = "IN",
    color = { 1.0, 0.65, 0.2 },
    rarity = "common",
    desc = "Sets enemies alight: burning damage for a few seconds.",
    mods = { incendiary = 1 },
  },
  scatter = {
    kind = "ammo",
    name = "Scatter Shot",
    short = "SC",
    color = { 0.80, 0.80, 0.45 },
    rarity = "common",
    desc = "+2 pellets per shot, but each does 40% less damage and the spread is wider.",
    mods = { pellets = 2, damage = 0.6, spread = 1.6 },
  },

  -- Ammo: new ---------------------------------------------------------------
  frost = {
    kind = "ammo",
    name = "Frost Rounds",
    short = "FR",
    color = { 0.55, 0.85, 1.0 },
    rarity = "common",
    desc = "Chills enemies: they move and act at less than half speed for 3 seconds.",
    mods = { freeze = 1, damage = 0.95 },
  },
  shock = {
    kind = "ammo",
    name = "Shock Rounds",
    short = "SH",
    color = { 0.55, 0.65, 1.0 },
    rarity = "rare",
    desc = "A hit arcs lightning to up to two nearby enemies for half damage.",
    mods = { shock = 1, damage = 0.9 },
  },
  poison = {
    kind = "ammo",
    name = "Venom Rounds",
    short = "VE",
    color = { 0.45, 0.85, 0.30 },
    rarity = "common",
    desc = "Poisons enemies: steady damage for 5 seconds. Stacks with fire.",
    mods = { poison = 1, damage = 0.9 },
  },
  vampiric = {
    kind = "ammo",
    name = "Vampiric Rounds",
    short = "VA",
    color = { 0.75, 0.15, 0.30 },
    rarity = "rare",
    desc = "Killing an enemy with these heals you 3 HP. -10% damage.",
    mods = { vamp = 3, damage = 0.9 },
  },
  gilded = {
    kind = "ammo",
    name = "Gilded Rounds",
    short = "GI",
    color = { 1.0, 0.85, 0.25 },
    rarity = "common",
    desc = "Kills spill 50% more gold. -15% damage.",
    mods = { greed = 0.5, damage = 0.85 },
  },
  sticky = {
    kind = "ammo",
    name = "Sticky Bombs",
    short = "ST",
    color = { 0.85, 0.45, 0.65 },
    rarity = "rare",
    desc = "Bullets stick to what they hit and blow up 0.8 seconds later. -40% damage, slower fire.",
    mods = { sticky = 1, damage = 0.6, fireDelay = 1.1 },
  },
  seeker = {
    kind = "ammo",
    name = "Seeker Rounds",
    short = "SK",
    color = { 0.95, 0.55, 0.85 },
    rarity = "rare",
    desc = "Bullets curve toward the nearest enemy. -15% damage and slower bullets.",
    mods = { homing = 1, damage = 0.85, bulletSpeed = 0.8 },
  },
  singularity = {
    kind = "ammo",
    name = "Singularity Rounds",
    short = "SG",
    color = { 0.45, 0.25, 0.75 },
    rarity = "rare",
    desc = "Impacts drag nearby enemies toward the point of impact. -20% damage.",
    mods = { gravity = 1, damage = 0.8 },
  },
  auger = {
    kind = "ammo",
    name = "Auger Rounds",
    short = "AU",
    color = { 0.65, 0.50, 0.35 },
    rarity = "common",
    desc = "Bores big holes: +3 crater size, digs hard rock. -20% damage.",
    mods = { digRadius = 3, digPower = 2, damage = 0.8 },
  },
  splitting = {
    kind = "ammo",
    name = "Splitting Rounds",
    short = "SP",
    color = { 0.90, 0.75, 0.40 },
    rarity = "common",
    desc = "On impact the bullet splits into two weaker bullets. -20% damage.",
    mods = { split = 1, damage = 0.8 },
  },
  boomerang = {
    kind = "ammo",
    name = "Boomerang Rounds",
    short = "BO",
    color = { 0.45, 0.75, 0.55 },
    rarity = "common",
    desc = "Bullets turn around after a short flight and come back, hitting again.",
    mods = { boomerang = 1, damage = 0.85 },
  },
  acid = {
    kind = "ammo",
    name = "Acid Rounds",
    short = "AC",
    color = { 0.75, 0.95, 0.25 },
    rarity = "common",
    desc = "Corrodes enemies: they take 30% more damage from everything for 4 seconds. Eats rock a little.",
    mods = { acid = 1, digRadius = 1, damage = 0.9 },
  },
  concussive = {
    kind = "ammo",
    name = "Concussive Rounds",
    short = "CO",
    color = { 0.85, 0.85, 0.95 },
    rarity = "common",
    desc = "Huge impact and a stun, but only half the damage.",
    mods = { concussive = 1, impactForce = 3, damage = 0.5 },
  },
  spectral = {
    kind = "ammo",
    name = "Spectral Rounds",
    short = "SE",
    color = { 0.75, 0.90, 1.0 },
    rarity = "rare",
    desc = "Bullets fly through terrain and only stop on enemies. Cannot dig. -20% damage.",
    mods = { ghost = 1, damage = 0.8 },
  },
  executioner = {
    kind = "ammo",
    name = "Executioner Rounds",
    short = "XE",
    color = { 0.55, 0.12, 0.12 },
    rarity = "rare",
    desc = "Double damage against enemies below 30% health. Slower fire.",
    mods = { execute = 1, fireDelay = 1.15 },
  },
  glowing = {
    kind = "ammo",
    name = "Glowing Rounds",
    short = "GL",
    color = { 1.0, 0.95, 0.60 },
    rarity = "common",
    desc = "Bullets blaze with light, lighting up the dark. +10% damage.",
    mods = { glow = 1, damage = 1.1 },
  },
  cluster = {
    kind = "ammo",
    name = "Cluster Rounds",
    short = "CL",
    color = { 1.0, 0.55, 0.30 },
    rarity = "rare",
    desc = "Bullets burst into three little bombs on impact. -30% damage.",
    mods = { cluster = 1, damage = 0.7 },
  },
  feather = {
    kind = "ammo",
    name = "Featherweight Rounds",
    short = "FE",
    color = { 0.90, 0.92, 0.95 },
    rarity = "common",
    desc = "Light powder: +35% bullet speed, 40% less recoil, 15% faster fire, 25% less damage.",
    mods = { bulletSpeed = 1.35, recoil = 0.6, fireDelay = 0.85, damage = 0.75 },
  },
  blood = {
    kind = "ammo",
    name = "Blood Rounds",
    short = "BL",
    color = { 0.70, 0.05, 0.10 },
    rarity = "cursed",
    desc = "CURSED: +90% damage and +15% crit, but every shot costs you 1 HP (it will never kill you).",
    mods = { damage = 1.9, critChance = 0.15, bloodCost = 1 },
  },
  unstable = {
    kind = "ammo",
    name = "Unstable Rounds",
    short = "UN",
    color = { 0.95, 0.30, 0.10 },
    rarity = "cursed",
    desc = "CURSED: explosive, +40% damage and faster fire, but 1 in 5 shots detonates in your face. Wider spread.",
    mods = { explosive = 1, damage = 1.75, fireDelay = 0.85, spread = 2.0, misfire = 1 },
  },

  -- Attachments: the original seven -----------------------------------------
  longbarrel = {
    kind = "attachment",
    name = "Long Barrel",
    short = "LB",
    color = { 0.70, 0.74, 0.85 },
    rarity = "common",
    desc = "+25% bullet speed, 30% tighter spread, +10% damage.",
    mods = { bulletSpeed = 1.25, spread = 0.7, damage = 1.1 },
  },
  extmag = {
    kind = "attachment",
    name = "Extended Magazine",
    short = "EM",
    color = { 0.55, 0.78, 0.55 },
    rarity = "common",
    desc = "+50% chambers, but 15% slower to reload.",
    mods = { chambers = 1.5, reloadTime = 1.15 },
  },
  compensator = {
    kind = "attachment",
    name = "Recoil Compensator",
    short = "RK",
    color = { 0.55, 0.65, 0.90 },
    rarity = "common",
    desc = "40% less recoil. Great for control, worse for recoil jumping.",
    mods = { recoil = 0.6 },
  },
  speedloader = {
    kind = "attachment",
    name = "Speed Loader",
    short = "SD",
    color = { 0.90, 0.80, 0.40 },
    rarity = "common",
    desc = "40% faster reloads.",
    mods = { reloadTime = 0.6 },
  },
  hairtrigger = {
    kind = "attachment",
    name = "Hair Trigger",
    short = "HT",
    color = { 0.95, 0.55, 0.45 },
    rarity = "common",
    desc = "25% faster fire, but 30% wider spread.",
    mods = { fireDelay = 0.75, spread = 1.3 },
  },
  choke = {
    kind = "attachment",
    name = "Choke",
    short = "CH",
    color = { 0.60, 0.60, 0.70 },
    rarity = "common",
    desc = "Halves the spread.",
    mods = { spread = 0.5 },
  },
  charge = {
    kind = "attachment",
    name = "Powder Charge",
    short = "PC",
    color = { 0.85, 0.62, 0.30 },
    rarity = "common",
    desc = "Hotter load: +50% recoil (bigger recoil jumps), +15% damage, +30% impact.",
    mods = { recoil = 1.5, damage = 1.15, impactForce = 1.3 },
  },

  -- Attachments: new --------------------------------------------------------
  burst = {
    kind = "attachment",
    name = "Burst Fire",
    short = "BF",
    color = { 0.90, 0.70, 0.35 },
    rarity = "common",
    desc = "Fires in rapid bursts of three, then pauses. Tighter spread.",
    mods = { burst = 1, spread = 0.85 },
  },
  backblast = {
    kind = "attachment",
    name = "Backblast",
    short = "BB",
    color = { 0.85, 0.50, 0.30 },
    rarity = "common",
    desc = "Also fires a weaker bullet out the back. Hits whatever creeps up behind you.",
    mods = { rear = 1 },
  },
  primer = {
    kind = "attachment",
    name = "Primer Coil",
    short = "PM",
    color = { 0.95, 0.80, 0.25 },
    rarity = "common",
    desc = "The first shot after every reload deals double damage.",
    mods = { opener = 1 },
  },
  suppressor = {
    kind = "attachment",
    name = "Suppressor",
    short = "SU",
    color = { 0.40, 0.42, 0.50 },
    rarity = "common",
    desc = "Shots deal triple damage to sleeping enemies. Quieter, smaller flash. -5% damage.",
    mods = { sneak = 1, damage = 0.95 },
  },
  laser = {
    kind = "attachment",
    name = "Laser Sight",
    short = "LS",
    color = { 1.0, 0.25, 0.25 },
    rarity = "common",
    desc = "Shows where you are aiming. 35% tighter spread.",
    mods = { laser = 1, spread = 0.65 },
  },
  bayonet = {
    kind = "attachment",
    name = "Bayonet",
    short = "BY",
    color = { 0.80, 0.82, 0.88 },
    rarity = "common",
    desc = "Your kick (F) hits three times as hard.",
    mods = { bayonet = 1 },
  },
  overclock = {
    kind = "attachment",
    name = "Overclock",
    short = "OC",
    color = { 1.0, 0.40, 0.20 },
    rarity = "rare",
    desc = "35% faster fire, but the gun overheats and dumps its magazine after about 9 rapid shots.",
    mods = { overheat = 1, fireDelay = 0.65 },
  },
  magnet = {
    kind = "attachment",
    name = "Magnetic Loader",
    short = "MG",
    color = { 0.85, 0.30, 0.35 },
    rarity = "common",
    desc = "Gold within 90 pixels flies to you while this gun is held.",
    mods = { magnet = 90 },
  },
  lantern = {
    kind = "attachment",
    name = "Muzzle Lantern",
    short = "LN",
    color = { 1.0, 0.82, 0.45 },
    rarity = "common",
    desc = "Lights up the dark around you while this gun is held.",
    mods = { lamp = 110 },
  },
  jets = {
    kind = "attachment",
    name = "Jump Jets",
    short = "JJ",
    color = { 0.45, 0.80, 0.95 },
    rarity = "rare",
    desc = "+30% recoil, and recoil lifts you almost as much on the ground as in the air.",
    mods = { jets = 1, recoil = 1.3 },
  },
  mortar = {
    kind = "attachment",
    name = "Mortar Breech",
    short = "MO",
    color = { 0.80, 0.40, 0.25 },
    rarity = "rare",
    desc = "Every fifth shot is a big explosive round.",
    mods = { mortar = 1 },
  },
  scavenger = {
    kind = "attachment",
    name = "Scavenger Bolt",
    short = "SB",
    color = { 0.55, 0.70, 0.40 },
    rarity = "common",
    desc = "Every kill refills one chamber and speeds up a reload.",
    mods = { refill = 1 },
  },
  quickdraw = {
    kind = "attachment",
    name = "Quickdraw Holster",
    short = "QD",
    color = { 0.78, 0.60, 0.40 },
    rarity = "common",
    desc = "Right after you switch to this gun, the first shot deals double damage.",
    mods = { quickdraw = 1 },
  },
  glassbarrel = {
    kind = "attachment",
    name = "Glass Barrel",
    short = "GB",
    color = { 0.75, 0.92, 0.95 },
    rarity = "rare",
    desc = "Double damage, but only half the chambers and a slower reload.",
    mods = { damage = 2.0, chambers = 0.5, reloadTime = 1.3 },
  },
  scope = {
    kind = "attachment",
    name = "Hunter's Scope",
    short = "HS",
    color = { 0.45, 0.75, 0.50 },
    rarity = "rare",
    desc = "+20% crit chance (crits deal double damage). Tighter spread.",
    mods = { critChance = 0.2, spread = 0.8 },
  },
  stock = {
    kind = "attachment",
    name = "Weighted Stock",
    short = "WS",
    color = { 0.62, 0.45, 0.30 },
    rarity = "common",
    desc = "40% tighter spread and 20% less recoil, but 10% slower fire.",
    mods = { spread = 0.6, recoil = 0.8, fireDelay = 1.1 },
  },
  penetrator = {
    kind = "attachment",
    name = "Penetrator Rod",
    short = "PE",
    color = { 0.70, 0.55, 0.85 },
    rarity = "rare",
    desc = "Bullets pass through two enemies. -20% damage, slower fire.",
    mods = { pierce = 2, damage = 0.8, fireDelay = 1.2 },
  },
  stabilizer = {
    kind = "attachment",
    name = "Stabilizer Grip",
    short = "SZ",
    color = { 0.55, 0.75, 0.70 },
    rarity = "common",
    desc = "Standing still (or crouched and slow) makes your shots almost perfectly accurate.",
    mods = { steady = 1 },
  },
  deadmans = {
    kind = "attachment",
    name = "Dead Man's Mag",
    short = "DM",
    color = { 0.45, 0.10, 0.35 },
    rarity = "cursed",
    desc = "CURSED: 2.5x chambers and +20% damage, but reloads take over twice as long and fire is 30% slower.",
    mods = { chambers = 2.5, damage = 1.2, reloadTime = 2.2, fireDelay = 1.3 },
  },
  reckless = {
    kind = "attachment",
    name = "Reckless Trigger",
    short = "RT",
    color = { 0.90, 0.20, 0.30 },
    rarity = "cursed",
    desc = "CURSED: 55% faster fire and +25% damage, but triple spread and you take 25% more damage while holding it.",
    mods = { fireDelay = 0.45, damage = 1.25, spread = 3.0, vulnerable = 0.25 },
  },
}

-- Stable order, for generating and listing
items.order = {
  -- ammo
  "slug", "piercing", "ricochet", "explosive", "incendiary", "scatter",
  "frost", "shock", "poison", "vampiric", "gilded", "sticky", "seeker", "singularity", "auger",
  "splitting", "boomerang", "acid", "concussive", "spectral", "executioner", "glowing", "cluster",
  "feather", "blood", "unstable",
  -- attachments
  "longbarrel", "extmag", "compensator", "speedloader", "hairtrigger", "choke", "charge",
  "burst", "backblast", "primer", "suppressor", "laser", "bayonet", "overclock", "magnet", "lantern",
  "jets", "mortar", "scavenger", "quickdraw", "glassbarrel", "scope", "stock", "penetrator",
  "stabilizer", "deadmans", "reckless",
}

function items.new(id)
  local def = assert(items.defs[id], "unknown item: " .. tostring(id))
  return {
    kind = def.kind,
    id = id,
    name = def.name,
    short = def.short,
    color = def.color,
    rarity = def.rarity,
    desc = def.desc,
    mods = def.mods,
  }
end

-- A random item: common ones turn up most, cursed ones rarely. `rng` is an
-- optional function(m, n) like love.math.random.
function items.random(random)
  random = random or love.math.random
  local total = 0
  for _, id in ipairs(items.order) do
    total = total + items.rarities[items.defs[id].rarity].weight
  end
  local roll = random() * total
  for _, id in ipairs(items.order) do
    roll = roll - items.rarities[items.defs[id].rarity].weight
    if roll <= 0 then
      return items.new(id)
    end
  end
  return items.new(items.order[#items.order])
end

return items
