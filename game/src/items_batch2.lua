-- The second batch of items: 20 common, 20 rare and 5 epic ammo types and attachments,
-- and the fused items made from them (and from the rares). Loaded by src.items at the
-- end of its own definitions; it only adds data (see src.items for what the mods mean).
--
-- New effects it brings (computed in src.guns, run in src.bullets):
--   bleed        enemies hit bleed for 8 s (steady damage, like venom)
--   leech        hits drink a little health (1 hp per 2 hits at 1)
--   ramp         every shot in a row, until the next reload, hits +N harder (up to 10 shots)
--   lastRound    the final round in the magazine hits +N harder
--   blastSize    explosions are +N wider
--   bounceBoost  a bullet hits +N harder after every bounce
--   critBoost    crits deal +N more than the usual double
--   far / close  up to +N damage at long range (450 px) / at point-blank (under 80 px)
local B = {}

B.defs = {}
B.order = {}
local function A(id, name, short, color, kind, rarity, mods, desc)
  B.defs[id] = { kind = kind, name = name, short = short, color = color, rarity = rarity, desc = desc, mods = mods }
  B.order[#B.order + 1] = id
end

-- Common ammo ---------------------------------------------------------------
A("hollowpoint", "Hollow Points", "HP", { 0.88, 0.80, 0.62 }, "ammo", "common", { damage = 1.25, critChance = 0.05, impactForce = 0.8 },
  "+25% damage and +5% crit chance, but a softer hit: 20% less impact.")
A("tracer", "Tracer Rounds", "TR", { 1.0, 0.82, 0.45 }, "ammo", "common", { glow = 1, bulletSpeed = 1.2, spread = 0.85 },
  "Glowing rounds that fly 20% faster and 15% truer, lighting the dark as they go.")
A("flechette", "Flechettes", "FE", { 0.78, 0.84, 0.86 }, "ammo", "common", { pellets = 1, damage = 0.85, spread = 0.8, bulletSpeed = 1.15 },
  "One extra fast, tight dart per shot, each 15% weaker.")
A("barbed", "Barbed Rounds", "BR", { 0.75, 0.3, 0.3 }, "ammo", "common", { bleed = 1, damage = 0.95 },
  "Barbs that tear: a hit leaves the enemy bleeding for 8 seconds.")
A("rubber", "Rubber Rounds", "RU", { 0.5, 0.52, 0.62 }, "ammo", "common", { bounces = 3, damage = 0.8, impactForce = 1.5 },
  "Bounce off terrain three times and shove hard. -20% damage.")
A("dumdum", "Dum-Dum Rounds", "DD", { 0.7, 0.6, 0.5 }, "ammo", "common", { damage = 1.3, bulletSpeed = 0.8, recoil = 1.15 },
  "+30% damage, but slow, and a little more kick.")
A("lucky", "Lucky Rounds", "LK", { 0.55, 0.9, 0.5 }, "ammo", "common", { critChance = 0.15, damage = 0.95 },
  "+15% chance of a critical hit (double damage). -5% damage.")
A("brass", "Brass Jackets", "BJ", { 0.85, 0.7, 0.3 }, "ammo", "common", { digRadius = 1, digPower = 1, damage = 1.1 },
  "Hard-jacketed: +10% damage, and bullets dig a little deeper into rock.")
A("lightload", "Light Loads", "LD", { 0.9, 0.9, 0.78 }, "ammo", "common", { recoil = 0.6, fireDelay = 0.85, damage = 0.85 },
  "Gentle loads: 40% less recoil and 15% faster fire, each shot 15% weaker.")
A("leechround", "Leech Rounds", "LC", { 0.62, 0.2, 0.35 }, "ammo", "common", { leech = 1, damage = 0.9 },
  "Every hit drinks a little: about one health for every two hits. -10% damage.")

-- Common attachments --------------------------------------------------------
A("foregrip", "Foregrip", "FG", { 0.6, 0.5, 0.4 }, "attachment", "common", { recoil = 0.8, spread = 0.85 },
  "20% less recoil and 15% tighter spread.")
A("sights", "Iron Sights", "IR", { 0.72, 0.74, 0.78 }, "attachment", "common", { spread = 0.8, critChance = 0.05 },
  "20% tighter spread and +5% crit chance.")
A("brake", "Muzzle Brake", "MZ", { 0.55, 0.58, 0.62 }, "attachment", "common", { recoil = 0.65, bulletSpeed = 0.95 },
  "35% less recoil for 5% slower bullets.")
A("heavybarrel", "Heavy Barrel", "HV", { 0.5, 0.52, 0.58 }, "attachment", "common", { damage = 1.15, fireDelay = 1.1, spread = 0.9 },
  "+15% damage and 10% tighter, but 10% slower to fire.")
A("lightframe", "Lightweight Frame", "LW", { 0.78, 0.8, 0.85 }, "attachment", "common", { fireDelay = 0.88, recoil = 1.1 },
  "12% faster fire, with 10% more recoil.")
A("clips", "Stripper Clips", "SK", { 0.8, 0.72, 0.45 }, "attachment", "common", { reloadTime = 0.75, chambers = 1.1 },
  "25% faster reloads and 10% more chambers.")
A("pouch", "Ammo Pouch", "AM", { 0.55, 0.4, 0.28 }, "attachment", "common", { chambers = 1.25, reloadTime = 1.1 },
  "+25% chambers, 10% slower reloads.")
A("rangefinder", "Rangefinder", "RF", { 0.45, 0.78, 0.95 }, "attachment", "common", { far = 0.5, bulletSpeed = 1.1 },
  "Shots hit up to 50% harder the further they have flown. +10% bullet speed.")
A("sawnstock", "Sawn Stock", "SW", { 0.7, 0.45, 0.3 }, "attachment", "common", { close = 0.6, spread = 1.2, recoil = 1.2 },
  "Up to 60% more damage at point-blank range. Wider spread, more kick.")
A("pick", "Prospector's Pick", "PK", { 0.9, 0.78, 0.4 }, "attachment", "common", { digRadius = 1, digPower = 1, greed = 0.25 },
  "Bullets dig deeper and kills spill 25% more gold.")

-- Rare ammo -----------------------------------------------------------------
A("stormround", "Chain Lightning Rounds", "CH", { 0.6, 0.72, 1.0 }, "ammo", "rare", { shock = 2, damage = 0.85 },
  "Lightning leaps through three more enemies instead of two. -15% damage.")
A("marked", "Marked Rounds", "MK", { 0.9, 0.85, 0.3 }, "ammo", "rare", { acid = 1, critChance = 0.1 },
  "Corrodes armour and +10% crit chance: a marked enemy takes more from everything.")
A("siphon", "Siphon Rounds", "SI", { 0.8, 0.15, 0.45 }, "ammo", "rare", { vamp = 1, leech = 0.5, damage = 0.9 },
  "Kills heal you, and hits drink a little too. -10% damage.")
A("quicksilver", "Quicksilver Rounds", "QS", { 0.82, 0.88, 0.95 }, "ammo", "rare", { homing = 1, bulletSpeed = 1.25, bounces = 1 },
  "Fast, seeking rounds that ricochet once.")
A("napalm", "Napalm Rounds", "NP", { 1.0, 0.5, 0.1 }, "ammo", "rare", { incendiary = 2, damage = 0.85, fireDelay = 1.1 },
  "Twice the fire: heavier burning for longer. -15% damage, a little slower to fire.")
A("hemorrhage", "Hemorrhage Rounds", "HM", { 0.8, 0.1, 0.15 }, "ammo", "rare", { bleed = 3, damage = 0.85 },
  "Wounds that will not close: heavy bleeding for 8 seconds. -15% damage.")
A("grapeshot", "Grapeshot", "GP", { 0.6, 0.62, 0.5 }, "ammo", "rare", { pellets = 4, damage = 0.55, spread = 1.8, pierce = 1 },
  "+4 pellets that punch through a target. Each does 45% less damage, with a very wide cone.")
A("rebound", "Rebound Rounds", "RE", { 0.4, 0.9, 0.85 }, "ammo", "rare", { bounces = 3, bounceBoost = 0.5 },
  "Bounce three times, hitting 50% harder after every bounce.")
A("longrifle", "Long Rifle Rounds", "LG", { 0.75, 0.8, 0.9 }, "ammo", "rare", { far = 1, bulletSpeed = 1.5, spread = 0.6, fireDelay = 1.25 },
  "Up to double damage at long range, 50% faster and 40% tighter. 25% slower to fire.")
A("gambler", "Gambler's Rounds", "GB", { 0.95, 0.8, 0.2 }, "ammo", "rare", { critChance = 0.3, critBoost = 1.5, damage = 0.8 },
  "+30% crit chance and crits deal 3.5x instead of 2x. -20% damage otherwise.")

-- Rare attachments ----------------------------------------------------------
A("reaper", "Reaper Chamber", "RP", { 0.55, 0.2, 0.5 }, "attachment", "rare", { lastRound = 1.5, chambers = 0.8 },
  "The last round in the magazine deals 150% more damage. 20% fewer chambers.")
A("rampant", "Rampant Trigger", "RA", { 0.95, 0.4, 0.2 }, "attachment", "rare", { ramp = 0.08, fireDelay = 1.05 },
  "Every shot in a row hits 8% harder, up to +80%, until you reload.")
A("quadburst", "Quad Burst", "QB", { 0.9, 0.55, 0.3 }, "attachment", "rare", { burst = 2, spread = 1.2, damage = 0.9 },
  "Fires in longer rapid bursts. 20% wider, -10% damage.")
A("demosleeve", "Demolition Sleeve", "DM", { 1.0, 0.5, 0.2 }, "attachment", "rare", { explosive = 1, blastSize = 0.8, impactForce = 1.3, damage = 0.85 },
  "Rounds burst on impact, in blasts 80% wider. -15% damage.")
A("phasebarrel", "Phase Barrel", "PH", { 0.65, 0.85, 1.0 }, "attachment", "rare", { ghost = 1, bulletSpeed = 1.1, damage = 0.85 },
  "Bullets pass through rock and wall. -15% damage, 10% faster.")
A("fang", "Vampire Fang", "VF", { 0.85, 0.15, 0.25 }, "attachment", "rare", { vamp = 1, leech = 0.3 },
  "Kills heal you, and hits drink a little.")
A("reloadengine", "Reload Engine", "RL", { 0.5, 0.8, 0.6 }, "attachment", "rare", { reloadTime = 0.45, chambers = 0.9 },
  "Reloads in under half the time. 10% fewer chambers.")
A("treasurebarrel", "Treasure Hunter's Barrel", "TB", { 1.0, 0.85, 0.3 }, "attachment", "rare", { greed = 1, magnet = 100, digPower = 1 },
  "Kills spill double gold, gold flies to you from 100 px, and bullets dig a little.")
A("huntersscope", "Hunter's Scope", "HU", { 0.55, 0.75, 0.55 }, "attachment", "rare", { far = 0.8, critChance = 0.15, laser = 1 },
  "A laser sight, +15% crit chance and up to 80% more damage at range.")
A("killswitch", "Kill Switch", "KS", { 0.9, 0.3, 0.3 }, "attachment", "rare", { refill = 2, execute = 1 },
  "Enemies under 30% health take double damage, and every kill puts two rounds back.")

-- Epic ----------------------------------------------------------------------
A("tempest", "Tempest Rounds", "TP", { 0.55, 0.8, 1.0 }, "ammo", "epic", { shock = 2, freeze = 1, concussive = 1, damage = 1.1 },
  "A storm in a shell: chain lightning, chilling cold and a stunning blow. +10% damage.")
A("phoenix", "Phoenix Rounds", "PX", { 1.0, 0.45, 0.2 }, "ammo", "epic", { incendiary = 2, explosive = 1, vamp = 1, blastSize = 0.5 },
  "Burning, exploding rounds in wide blasts; every kill heals you.")
A("voidround", "Void Rounds", "VD", { 0.5, 0.2, 0.8 }, "ammo", "epic", { gravity = 2, ghost = 1, pierce = 2, damage = 1.15 },
  "Rounds that drag everything inward, slip through rock and pierce two enemies. +15% damage.")
A("omen", "Omen Engine", "OM", { 0.85, 0.3, 0.85 }, "attachment", "epic", { ramp = 0.1, lastRound = 2, critChance = 0.15, critBoost = 1, fireDelay = 0.85 },
  "Each shot hits harder than the last, the last round hits three times as hard, and crits land for triple. +15% crit, 15% faster.")
A("warlord", "Warlord's Rig", "WL", { 1.0, 0.75, 0.25 }, "attachment", "epic", { burst = 1, damage = 1.3, reloadTime = 0.6, chambers = 1.4, greed = 0.5 },
  "Bursts of rounds, +30% damage, +40% chambers, 40% faster reloads, and kills spill more gold.")

-- Fused ---------------------------------------------------------------------
B.fused = {}
B.fusedOrder = {}
local function F(id, name, short, color, kind, mods, desc)
  B.fused[id] = { kind = kind, name = name, short = short, color = color, rarity = "fused", desc = desc, mods = mods }
  B.fusedOrder[#B.fusedOrder + 1] = id
end

-- (from the new commons, and some old ones)
F("mushroom", "Mushroom Rounds", "MU", { 0.85, 0.72, 0.55 }, "ammo", { damage = 1.9, impactForce = 2, bulletSpeed = 0.85, recoil = 1.4, critChance = 0.05 },
  "Huge, soft-nosed slugs: +90% damage, double impact, slow and heavy-kicking.")
F("beacon", "Beacon Rounds", "BE", { 1.0, 0.9, 0.55 }, "ammo", { glow = 2, bulletSpeed = 1.3, spread = 0.8, lamp = 60 },
  "Bright, fast and true: +30% bullet speed, 20% tighter, and a lamp that lights the cave around you while held.")
F("rotround", "Rot Rounds", "RO", { 0.55, 0.6, 0.2 }, "ammo", { bleed = 2, poison = 1, damage = 0.9 },
  "Bleeding and poison together: steady damage that stacks. -10% damage.")
F("pinball", "Pinball Rounds", "PI", { 0.5, 0.95, 0.9 }, "ammo", { bounces = 6, bounceBoost = 0.3, impactForce = 1.6, damage = 0.85 },
  "Bounce six times, hitting 30% harder after each, with a heavy shove. -15% damage.")
F("fortune", "Fortune Rounds", "FO", { 0.95, 0.85, 0.3 }, "ammo", { critChance = 0.2, critBoost = 0.5, greed = 1 },
  "+20% crit chance, crits hit for 2.5x, and kills spill more gold.")
F("harness", "Recoil Harness", "RH", { 0.62, 0.55, 0.45 }, "attachment", { recoil = 0.35, spread = 0.6, fireDelay = 0.95 },
  "65% less recoil, 40% tighter, and a little faster to fire.")
F("sniperkit", "Sniper's Package", "SN", { 0.5, 0.7, 0.9 }, "attachment", { far = 1, critChance = 0.15, spread = 0.5, bulletSpeed = 1.2 },
  "Up to double damage at range, +15% crit, half the spread and 20% faster bullets.")
F("breacher", "Breacher Kit", "BK", { 0.8, 0.5, 0.3 }, "attachment", { close = 1, damage = 1.3, spread = 1.2, impactForce = 1.4 },
  "Point-blank devastation: +30% damage, up to double at close range, and more shove. Wider spread.")
F("quickrig", "Quickload Rig", "QR", { 0.85, 0.78, 0.5 }, "attachment", { chambers = 1.6, reloadTime = 0.55 },
  "+60% chambers and 45% faster reloads.")
-- (from two rares each)
F("stormseeker", "Stormseeker Rounds", "SS", { 0.7, 0.8, 1.0 }, "ammo", { shock = 2, homing = 2, bulletSpeed = 1.2 },
  "Fast seeking rounds whose lightning leaps through three more enemies.")
F("crimsontithe", "Crimson Tithe Rounds", "CT", { 0.85, 0.1, 0.3 }, "ammo", { bleed = 3, vamp = 1, leech = 1, damage = 1.1 },
  "Deep bleeding, and everything you hurt or kill pays you back in health. +10% damage.")
F("billiard", "Billiard Rounds", "BD", { 0.5, 0.95, 0.8 }, "ammo", { bounces = 4, bounceBoost = 1, far = 1, bulletSpeed = 1.4 },
  "Fast long-range rounds that bounce four times and double their damage on every bounce.")
F("deathcycle", "Death Cycle", "DY", { 0.7, 0.2, 0.45 }, "attachment", { ramp = 0.12, lastRound = 2.5, fireDelay = 0.95 },
  "Every shot in a row hits 12% harder, and the last round of the magazine hits for 350%.")
F("executorseye", "Executioner's Eye", "EE", { 0.95, 0.35, 0.3 }, "attachment", { far = 1, critChance = 0.25, execute = 2, refill = 2, laser = 1 },
  "A laser sight, +25% crit, double damage on the wounded, long-range bonus, and kills refill two rounds.")

-- What fuses into what: two plain items, in either order
B.fusions = {
  { "hollowpoint", "dumdum", "mushroom" },
  { "tracer", "glowing", "beacon" },
  { "barbed", "poison", "rotround" },
  { "rubber", "ricochet", "pinball" },
  { "lucky", "gilded", "fortune" },
  { "foregrip", "brake", "harness" },
  { "rangefinder", "sights", "sniperkit" },
  { "sawnstock", "heavybarrel", "breacher" },
  { "clips", "pouch", "quickrig" },
  -- two rares each
  { "stormround", "quicksilver", "stormseeker" },
  { "hemorrhage", "siphon", "crimsontithe" },
  { "rebound", "longrifle", "billiard" },
  { "reaper", "rampant", "deathcycle" },
  { "huntersscope", "killswitch", "executorseye" },
}

return B
