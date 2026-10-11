-- Ammo types and attachments (design doc §5.5). Every one is just data: a
-- table of modifiers applied to the gun it is fitted in. Each filled slot
-- applies on its own and order doesn't matter; ammo types stack, so a gun
-- loaded with several gets all their effects at once.
--
-- Modifiers (src.guns computes a gun's effective stats from them):
--   multiplied (default 1):  damage, spread, recoil, fireDelay, reloadTime,
--                            bulletSpeed, impactForce, chambers
--   added (default 0):       pellets, digRadius, digPower
--   effects (counts that add up as more are fitted):
--                            pierce   (enemies a bullet passes through)
--                            bounces  (terrain ricochets)
--                            explosive, incendiary (strength)
-- An item is a table { kind = "ammo" | "attachment", id, name, short, color, desc, mods }.
local items = {}

items.defs = {
  -- Ammo ---------------------------------------------------------------
  slug = {
    kind = "ammo",
    name = "Heavy Slug",
    short = "SL",
    color = { 0.62, 0.62, 0.68 },
    desc = "Heavier shot: +50% damage, double impact. Kicks harder, shoots a little slower, tighter.",
    mods = { damage = 1.5, impactForce = 2, recoil = 1.3, spread = 0.7, fireDelay = 1.15 },
  },
  piercing = {
    kind = "ammo",
    name = "Piercing Rounds",
    short = "PR",
    color = { 0.55, 0.78, 0.85 },
    desc = "Passes through one enemy and bites deeper into rock. -10% damage.",
    mods = { pierce = 1, digPower = 1, damage = 0.9 },
  },
  ricochet = {
    kind = "ammo",
    name = "Ricochet Rounds",
    short = "RC",
    color = { 0.85, 0.82, 0.45 },
    desc = "Bounces off rock up to 2 times.",
    mods = { bounces = 2 },
  },
  explosive = {
    kind = "ammo",
    name = "Explosive Rounds",
    short = "EX",
    color = { 0.90, 0.45, 0.20 },
    desc = "Bursts on impact, blasting a crater and hurting everything nearby. -20% damage, slower fire.",
    mods = { explosive = 1, damage = 0.8, fireDelay = 1.2 },
  },
  incendiary = {
    kind = "ammo",
    name = "Incendiary Rounds",
    short = "IN",
    color = { 0.95, 0.30, 0.18 },
    desc = "Sets enemies alight: burning damage over a few seconds.",
    mods = { incendiary = 1 },
  },
  scatter = {
    kind = "ammo",
    name = "Scatter Shot",
    short = "SC",
    color = { 0.70, 0.52, 0.34 },
    desc = "Each shot fires 3 weaker pellets in a wider cone (+2 pellets, -40% damage).",
    mods = { pellets = 2, damage = 0.6, spread = 1.6 },
  },
  -- Attachments --------------------------------------------------------
  longbarrel = {
    kind = "attachment",
    name = "Long Barrel",
    short = "LB",
    color = { 0.55, 0.58, 0.72 },
    desc = "Faster, straighter, harder-hitting shots: +25% bullet speed, tighter spread, +10% damage.",
    mods = { bulletSpeed = 1.25, spread = 0.7, damage = 1.1 },
  },
  extmag = {
    kind = "attachment",
    name = "Extended Magazine",
    short = "EM",
    color = { 0.45, 0.62, 0.50 },
    desc = "+50% chambers, but a 15% slower reload.",
    mods = { chambers = 1.5, reloadTime = 1.15 },
  },
  compensator = {
    kind = "attachment",
    name = "Recoil Compensator",
    short = "RK",
    color = { 0.52, 0.70, 0.66 },
    desc = "-40% recoil (steadier, but weaker recoil jumps).",
    mods = { recoil = 0.6 },
  },
  speedloader = {
    kind = "attachment",
    name = "Speed Loader",
    short = "SP",
    color = { 0.78, 0.66, 0.40 },
    desc = "-40% reload time.",
    mods = { reloadTime = 0.6 },
  },
  hairtrigger = {
    kind = "attachment",
    name = "Hair Trigger",
    short = "HT",
    color = { 0.80, 0.50, 0.55 },
    desc = "-25% time between shots, but +30% spread.",
    mods = { fireDelay = 0.75, spread = 1.3 },
  },
  choke = {
    kind = "attachment",
    name = "Choke",
    short = "CH",
    color = { 0.60, 0.55, 0.68 },
    desc = "Halves the spread.",
    mods = { spread = 0.5 },
  },
  charge = {
    kind = "attachment",
    name = "Powder Charge",
    short = "PC",
    color = { 0.85, 0.62, 0.30 },
    desc = "Hotter load: +50% recoil (bigger recoil jumps), +15% damage, +30% impact.",
    mods = { recoil = 1.5, damage = 1.15, impactForce = 1.3 },
  },
}

-- Stable order, for generating and listing
items.order = {
  "slug", "piercing", "ricochet", "explosive", "incendiary", "scatter",
  "longbarrel", "extmag", "compensator", "speedloader", "hairtrigger", "choke", "charge",
}

function items.new(id)
  local def = assert(items.defs[id], "unknown item: " .. tostring(id))
  return {
    kind = def.kind,
    id = id,
    name = def.name,
    short = def.short,
    color = def.color,
    desc = def.desc,
    mods = def.mods,
  }
end

-- A random item (every kind equally likely for now)
function items.random()
  return items.new(items.order[love.math.random(1, #items.order)])
end

return items
