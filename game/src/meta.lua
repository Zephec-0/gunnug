-- What a profile keeps between runs beyond the compendium (design doc
-- §11a-iv, §11a-v): marks, the people living at camp, the upgrades bought
-- from them, and which weapons, ammo types and attachments are unlocked.
--
-- * Marks are the permanent currency, banked the moment they are earned
--   (first-time discoveries, bosses, freeing a prisoner, reaching an area for
--   the first time) and spent at camp. Gold stays run-only.
-- * Unlocked things can drop, turn up in chests and sit in shops. The pool
--   starts small: three guns and every common item. The rest is locked until
--   the Gunsmith is taught it, and he can only learn what the hunter has
--   seen (bosses and chests now and then give out a locked thing to find).
-- * Seen things show in the compendium as silhouettes with their names:
--   visible goals. Anything collected counts as seen.
--
-- Everything lives on the save profile (src.save); with no profile in use
-- (the world built behind the title screen, the test room) the whole pool is
-- open. install() hooks the generators in src.items, src.guns and
-- src.inventory, so they need not know about any of this.
local guns = require("src.guns")
local items = require("src.items")
local save = require("src.save")

local meta = {}

-- Called as onEarn(amount, reason) whenever marks are earned (for the HUD)
meta.onEarn = nil
-- Called as onBought(id) when a camp upgrade is bought (src.game hands over what it gives at once)
meta.onBought = nil

local GATED = { weapon = true, ammo = true, attachment = true }

-- The starting pool: these guns, and every common (and fused) item
meta.STARTER_WEAPONS = { revolver = true, shotgun = true, semiauto = true }

-- What teaching the Gunsmith costs, by what it is
local TEACH_COST = { weapon = 6, rare = 4, cursed = 3, common = 2 }

-- Marks for things done
meta.EARN = {
  discover = 0, -- anything new in the compendium (none for now)
  boss = 5, -- every boss slain (its first kill also counts as a discovery)
  rescue = 5, -- freeing a prisoner, who moves to camp
  area = 3, -- reaching an area for the first time
  elite = 2, -- every elite slain (src.enemies)
}

-- The camp's people (only the Gunsmith can be found so far; the rest of the
-- roster in the design doc is added here as each is built)
meta.PEOPLE = {
  gunsmith = {
    name = "The Gunsmith",
    found = "Caged in the Sunken Hollows",
    blurb = "Upgrades last for every run. Teach him a gun or item you have seen and it joins the pool: shops, chests and drops.",
    greeting = {
      "Mind the bench. Everything on it bites.",
      "Bring me anything I haven't worked on and I'll learn to make it.",
      "Marks spend the same down here as they do in town. Better, maybe.",
      "That revolver of yours wants oil. Everything wants oil.",
    },
  },
  prospector = {
    name = "The Prospector",
    found = "Buried under a cave-in in the Old Mine",
    blurb = "Upgrades last for every run. His strongbox keeps your gold safe between runs, even through death.",
    held = "rubble", -- (how he is found: src.npcs)
    greeting = {
      "Gold don't spoil. Folks do. Leave it with me.",
      "Mind the dynamite. Short fuses on the cheap ones.",
      "Forty years down there and the rock still owes me.",
      "Dig where the timber's broke. That's where they ran.",
    },
  },
}
meta.PEOPLE.gunsmith.held = "cage"
meta.PEOPLE.apothecary = {
  name = "The Apothecary",
  found = "Caged in the Sulfur Vents",
  held = "cage",
  blurb = "Upgrades last for every run. Tonics and flasks for the road down, brewed from whatever grows in the dark.",
  greeting = {
    "Everything down there is poison. Dosage is the only difference.",
    "Don't drink the green one. Or do. It's educational.",
    "Sulfur gets in the lungs. A tonic for it, if you ask.",
    "I keep what I brew. You keep what you can carry.",
  },
}
meta.PEOPLE.cartographer = {
  name = "The Cartographer",
  found = "Caged in the Quarry",
  held = "cage",
  blurb = "Upgrades last for every run. The survey map shows what you have walked, and later, what is worth walking to.",
  greeting = {
    "Every cave lies on the first draft. I only correct it.",
    "Press M and you'll see what your boots have drawn.",
    "The Quarry's a maze. I mapped it three times and lost it twice.",
    "North is wherever the lamp is pointing. Roughly.",
  },
}
meta.PEOPLE.bartender = {
  name = "The Bartender",
  found = "Sets up camp after the first boss falls",
  blurb = "Pick your poison for the next run: each house rule makes the dark worse, and pays more marks.",
  greeting = {
    "First one's free. Second one's a monster.",
    "Back from the Queen? Then you can handle a stiffer drink.",
    "Rules of the house: you die, you pay. I just add flavour.",
    "A harder room, a fatter purse. Fair deal.",
  },
}
meta.PEOPLE.sawbone = {
  name = "The Sawbone",
  found = "Floating on the surface in the Flooded Caverns",
  held = "float",
  blurb = "Patches you up between descents, cheaper than the shops, and will take a part of you in exchange for a gift and a price.",
  greeting = {
    "Hold still. This will only hurt a bit. Later it will hurt more.",
    "Everyone's got a spare of something. Mind if I borrow it?",
    "Gold, marks or a limb. I take all three.",
    "You look terrible. Sit. Let's talk about your arm.",
  },
}
meta.PEOPLE.taxidermist = {
  name = "The Taxidermist",
  found = "Caged in the Cinder Warrens, once you have carried an elite's trophy home",
  held = "cage",
  blurb = "Mounts the trophies of the elites you have slain. Each kind he mounts gives you a small bonus in every run, for good.",
  greeting = {
    "Don't touch the glass eyes. They watch.",
    "Bring me something with character.",
    "A good mount lasts longer than a good reputation.",
    "Hold still. No, not you. The ghoul.",
  },
}

-- What mounting each kind's trophy gives (a perk-style fx table), and its name
-- fx is the first level's bonus; each level after it adds half as much as the
-- one before (see meta.mountScale), so a kind's bonus tapers off: a Ghoul's
-- is +10, +15, +17, +19... max health. fmt shows the number for a level.
meta.MOUNTS = {
  ghoul = { name = "Ghoul", fmt = "+%d max health", base = 10, fx = { maxHp = 10 } },
  bat = { name = "Cave Bat", fmt = "+%d%% movement speed", base = 4, fx = { speed = 1.04 } },
  spitter = { name = "Spitter", fmt = "reloads %d%% faster", base = 5, fx = { reload = 0.95 } },
  hopper = { name = "Mire Hopper", fmt = "+%d%% jump height", base = 5, fx = { jump = 1.05 } },
  bloater = { name = "Bloater", fmt = "take %d%% less damage", base = 4, fx = { dmgTaken = 0.96 } },
  miner = { name = "Skeleton Miner", fmt = "+%d%% gold from everything", base = 6, fx = { gold = 1.06 } },
  roller = { name = "Cave Roller", fmt = "kicks hit %d%% harder", base = 20, fx = { kickDamage = 1.2 } },
}
meta.MOUNT_MAX = 8 -- the most levels a kind can be mounted to
meta.MOUNT_COST = 5 -- marks for a kind's first mount; each level costs 1.2x the last (rounded down)
meta.MOUNT_KILLS = 5 -- more elites of a kind to slay before each upgrade
-- The Bartender's house rules: each makes the next run harder and pays more marks
meta.RULES = {
  { id = "rotgut", name = "Rotgut", desc = "Monsters have 40% more health.", marks = 1.35, enemyHp = 1.4 },
  { id = "powderkeg", name = "Powder Keg", desc = "Monsters hit 30% harder.", marks = 1.3, enemyDmg = 1.3 },
  { id = "lean", name = "Lean Times", desc = "Shops charge 30% more, healing too.", marks = 1.2, shop = 1.3 },
}
-- The Sawbone's trades: each part taken gives a bonus and a penalty (fx tables
-- like a perk's: multipliers for speed/reload/jump/spread/fireDelay/damage/
-- dmgTaken/gold/maxHpMult, sums for crit/regen)
meta.LIMBS = {
  { id = "arm", name = "An Arm", gain = "Fire rate +30%", loss = "Reloading takes 35% longer", fx = { fireDelay = 0.77, reload = 1.35 } },
  { id = "leg", name = "A Leg", gain = "Spread -30%, jump +20%", loss = "Move 20% slower, no rolling or kicking", fx = { spread = 0.7, jump = 1.2, speed = 0.8 } },
  { id = "eye", name = "An Eye", gain = "Critical hits +20%", loss = "Spread +30%, blurred vision", fx = { spread = 1.3, crit = 0.2 } },
  { id = "ear", name = "An Ear", gain = "Damage +20%", loss = "Sounds are muffled and quiet", fx = { damage = 1.2 } },
  { id = "spleen", name = "The Spleen", gain = "Slowly mends: 1 health every 3 s", loss = "Take 15% more damage", fx = { regen = 0.33, dmgTaken = 1.15 } },
  { id = "kidney", name = "A Kidney", gain = "+25% gold from everything", loss = "Max health -15%", fx = { gold = 1.25, maxHpMult = 0.85 } },
}
meta.LIMB_MULT = { fireDelay = true, reload = true, spread = true, jump = true, speed = true, damage = true, dmgTaken = true, gold = true, maxHpMult = true }
meta.MOUNT_ORDER = { "ghoul", "bat", "spitter", "hopper", "bloater", "miner", "roller" }

-- The Prospector's strongbox: how much it holds, by Bigger Strongbox tier
meta.BANK_CAP = { 100, 250, 600 }

-- Upgrades sold at camp: each has tiers, bought in order with marks
meta.UPGRADES = {
  {
    id = "cheapcuts",
    npc = "sawbone",
    name = "Cheap Cuts",
    desc = "His patch-ups cost 25% less per tier.",
    costs = { 4, 8 },
  },
  {
    id = "sharpsaw",
    npc = "sawbone",
    name = "A Sharper Saw",
    desc = "What he takes from you pays 20% more per tier (the bonuses grow, the penalties stay).",
    costs = { 6, 12 },
  },
  {
    id = "grades",
    npc = "gunsmith",
    name = "Filed and Oiled",
    desc = "Weapons in shops and chests roll better bonuses (+15% per tier), so better grades turn up more often.",
    costs = { 6, 12 },
  },
  {
    id = "slots",
    npc = "gunsmith",
    name = "Bored-Out Frames",
    desc = "Weapons in shops and chests have a 15% chance per tier of one more slot.",
    costs = { 8, 16 },
  },
  {
    id = "strongbox",
    npc = "prospector",
    name = "Bigger Strongbox",
    desc = "His strongbox holds more of your gold between runs: 250, then 600 (from 100).",
    costs = { 5, 10 },
  },
  {
    id = "tithe",
    npc = "prospector",
    name = "Miner's Tithe",
    desc = "When you die, 15% per tier of the gold you carried goes into the strongbox (up to what it holds).",
    costs = { 6, 12 },
  },
  {
    id = "blasting",
    npc = "prospector",
    name = "Blasting Kit",
    desc = "Start every run with 2 sticks of dynamite per tier. Throw them with Q (by default); they blow holes in any rock.",
    costs = { 5, 10 },
  },
  {
    id = "vigor",
    npc = "apothecary",
    name = "Vigor Tonic",
    desc = "Every run starts with 12 more maximum health per tier.",
    costs = { 5, 10 },
  },
  {
    id = "flask",
    npc = "apothecary",
    name = "Pocket Flask",
    desc = "Start every run with a flask per tier. Drink one (H by default) to heal 35% of your health.",
    costs = { 6, 12 },
  },
  {
    id = "survey",
    npc = "cartographer",
    name = "Survey Map",
    desc = "Press M for a map of everywhere you have been this run. A second tier marks the shops, bounty quarries and finds.",
    costs = { 6, 10 },
  },
  {
    id = "holster",
    npc = "gunsmith",
    name = "Loaded Holster",
    desc = "Your starting revolver always comes with an ammo type or attachment fitted.",
    costs = { 5 },
  },
}
local upgradeById = {}
for _, u in ipairs(meta.UPGRADES) do
  upgradeById[u.id] = u
end

local function profile()
  return save.profile()
end

-- "slug+2" -> "slug": levelled items share their base item's unlock
local function baseId(id)
  return (tostring(id):gsub("%+%d+$", ""))
end

-- Unlocks ----------------------------------------------------------------------------

-- Whether something can drop, sit in a shop or come out of a chest
function meta.isUnlocked(category, id, p)
  p = p or profile()
  if not GATED[category] or not p then
    return true
  end
  id = baseId(id)
  if p.unlocked[category] and p.unlocked[category][id] then
    return true
  end
  if category == "weapon" then
    return meta.STARTER_WEAPONS[id] == true
  end
  local def = items.defs[id]
  return not def or def.rarity == "common" or def.rarity == "fused"
end

-- Whether the hunter has met it (collected, or seen lying about)
function meta.isSeen(category, id, p)
  p = p or profile()
  if not p then
    return false
  end
  if (p.found[category] and p.found[category][id] or 0) > 0 then
    return true
  end
  if category == "weapon" and meta.SPECIAL_GUNS[id] == "gunsmith" and p.camp.gunsmith then
    return true -- (he handed one over when he was freed, so he can make it)
  end
  return p.seen[category] ~= nil and p.seen[category][id] == true
end

-- Records that the hunter has seen something (a locked item on the ground)
function meta.see(category, id)
  local p = profile()
  if not p or meta.isSeen(category, id, p) then
    return
  end
  p.seen[category] = p.seen[category] or {}
  p.seen[category][id] = true
  save.touch()
end

function meta.teachCost(category, id)
  if category == "weapon" then
    return TEACH_COST.weapon
  end
  local def = items.defs[baseId(id)]
  return TEACH_COST[def and def.rarity or "common"] or TEACH_COST.common
end

-- Teaches the Gunsmith something seen: it joins the pool. Returns true if paid.
function meta.teach(category, id)
  local p = profile()
  if not p or meta.isUnlocked(category, id, p) or not meta.isSeen(category, id, p) then
    return false
  end
  local cost = meta.teachCost(category, id)
  if p.marks < cost then
    return false
  end
  p.marks = p.marks - cost
  p.unlocked[category] = p.unlocked[category] or {}
  p.unlocked[category][id] = true
  save.touch()
  save.flush()
  return true
end

-- Everything that is still locked in a category, in listing order: { id, name }
function meta.locked(category)
  local out = {}
  if category == "weapon" then
    for _, id in ipairs(guns.archetypes()) do
      if not meta.isUnlocked("weapon", id) then
        out[#out + 1] = id
      end
    end
  else
    for _, id in ipairs(items.order) do
      if items.defs[id].kind == category and not meta.isUnlocked(category, id) then
        out[#out + 1] = id
      end
    end
  end
  return out
end

-- A random locked item (nil if none are left): what bosses and chests give
-- out now and then, so there is something to see and later teach
function meta.lockedItem(random)
  random = random or love.math.random
  local pool = {}
  for _, id in ipairs(items.order) do
    if not meta.isUnlocked(items.defs[id].kind, id) then
      pool[#pool + 1] = id
    end
  end
  if #pool == 0 or not profile() then
    return nil
  end
  return items.new(pool[random(1, #pool)])
end

-- Guns that never turn up at random until the Gunsmith crafts them (and so
-- joins them to the pool): each has one source, the first time
--   automatic  the Gunsmith's gift, the first time he is freed
--   gatling    the Queen's prize
meta.SPECIAL_GUNS = { automatic = "gunsmith", gatling = "queen" }

-- No boss has been slain yet on this profile (checked as the first one drops its prize)
function meta.firstBoss()
  local p = profile()
  return p ~= nil and (p.stats.bosses or 0) == 0
end

-- A random locked gun archetype (nil if none are left). The special guns
-- are never among them: they only come from their own source.
function meta.lockedArchetype(random)
  random = random or love.math.random
  local pool = {}
  for _, id in ipairs(meta.locked("weapon")) do
    if not meta.SPECIAL_GUNS[id] then
      pool[#pool + 1] = id
    end
  end
  if #pool == 0 or not profile() then
    return nil
  end
  return pool[random(1, #pool)]
end

-- Gated perks (Akimbo): rolled only once the profile has unlocked them
function meta.perkUnlocked(id, p)
  p = p or profile()
  return p ~= nil and p.unlocked.perk ~= nil and p.unlocked.perk[id] == true
end

-- Unlocks a gated perk for good. Returns true the first time.
function meta.unlockPerk(id)
  local p = profile()
  if not p or meta.perkUnlocked(id, p) then
    return false
  end
  p.unlocked.perk = p.unlocked.perk or {}
  p.unlocked.perk[id] = true
  save.touch()
  save.flush()
  return true
end

-- Marks ------------------------------------------------------------------------------

function meta.marks()
  local p = profile()
  return p and p.marks or 0
end

-- Banks marks at once (they survive a death a second later)
function meta.earn(amount, reason)
  local p = profile()
  if not p or amount <= 0 then
    return
  end
  amount = math.max(1, math.floor(amount * meta.markMul() + 0.5))
  p.marks = p.marks + amount
  p.stats.marksEarned = (p.stats.marksEarned or 0) + amount
  save.touch()
  if meta.onEarn then
    meta.onEarn(amount, reason)
  end
end

-- Whether a save file is in use (events and the ghost only run for one)
function meta.profileActive()
  return profile() ~= nil
end

local function spend(amount)
  local p = profile()
  if not p or p.marks < amount then
    return false
  end
  p.marks = p.marks - amount
  save.touch()
  save.flush()
  return true
end

-- Trophies: elites slain, by kind (for the Taxidermist, later)
function meta.trophy(kind)
  local p = profile()
  if not p then
    return
  end
  p.trophies[kind] = (p.trophies[kind] or 0) + 1
  save.touch()
end

-- The strongbox ------------------------------------------------------------------------

function meta.bank()
  local p = profile()
  return p and (tonumber(p.bank) or 0) or 0
end

function meta.bankCap()
  return meta.BANK_CAP[meta.tier("strongbox") + 1] or meta.BANK_CAP[#meta.BANK_CAP]
end

-- Puts up to `amount` gold in the strongbox (as much as fits). Returns what went in.
function meta.deposit(amount)
  local p = profile()
  if not p or amount <= 0 then
    return 0
  end
  local put = math.max(0, math.min(amount, meta.bankCap() - meta.bank()))
  p.bank = meta.bank() + put
  save.touch()
  return put
end

-- Takes everything out of the strongbox. Returns it.
function meta.withdraw()
  local p = profile()
  local all = meta.bank()
  if p and all > 0 then
    p.bank = 0
    save.touch()
    save.flush()
  end
  return all
end

-- The hunter died carrying `gold`: the Miner's Tithe banks some of it
function meta.tithe(gold)
  local share = math.floor(gold * 0.15 * meta.tier("tithe"))
  return share > 0 and meta.deposit(share) or 0
end

-- Sticks of dynamite a run starts with (the Blasting Kit)
function meta.startDynamite()
  return 2 * meta.tier("blasting")
end

-- Pays marks for something (the ghost's prices). Returns true if paid.
function meta.pay(amount)
  return spend(amount)
end

-- The camp ----------------------------------------------------------------------------

-- How the camp and the dungeon open up, run by run (a new profile starts with
-- nothing but the site):
--   first run          nobody to find, no elites
--   after one death    elites spawn; the Gunsmith and the Prospector can be found
--   after two deaths   the Apothecary and the Cartographer can be found
--   an elite slain, then a death: the bounty board goes up, and the
--                      Taxidermist can be found
--   first boss slain   the Bartender sets up the saloon
local function deaths()
  local p = profile()
  return p and (p.stats.deaths or 0) or 0
end

function meta.elitesOn()
  return profile() == nil or deaths() >= 1
end

-- Called when a run ends in death: if an elite fell in the profile's life so far, the board goes up
function meta.onDeath()
  local p = profile()
  if p and not p.board and meta.trophyTotal() > 0 then
    p.board = true
    save.touch()
  end
end

function meta.boardOpen()
  local p = profile()
  if not p then
    return true
  end
  return p.board == true or (meta.trophyTotal() > 0 and deaths() >= 1) -- (older saves: the same rule from what they have)
end

-- May this person's cage be there to find in the dungeon yet?
function meta.canFind(id)
  local p = profile()
  if not p then
    return true
  end
  if id == "gunsmith" or id == "prospector" then
    return deaths() >= 1
  elseif id == "apothecary" or id == "cartographer" then
    return deaths() >= 2
  elseif id == "taxidermist" then
    return meta.boardOpen()
  end
  return true
end

function meta.atCamp(id)
  local p = profile()
  if p and id == "taxidermist" and p.camp.taxidermist ~= true then
    return next(p.mounted) ~= nil -- (older saves: he came with the first mount)
  end
  if p and id == "bartender" then
    return (p.stats.bosses or 0) > 0 -- (and the first boss)
  end
  return p ~= nil and p.camp[id] == true
end

function meta.trophyTotal()
  local p = profile()
  local n = 0
  for _, v in pairs(p and p.trophies or {}) do
    n = n + v
  end
  return n
end

function meta.trophyCount(kind)
  local p = profile()
  return p and p.trophies[kind] or 0
end

-- How many times a kind has been mounted / upgraded (0 = not at all; saves
-- from before levels hold `true`, which counts as 1)
function meta.mountLevel(kind)
  local p = profile()
  local v = p and p.mounted[kind]
  if v == true then
    return 1
  end
  return tonumber(v) or 0
end

function meta.isMounted(kind)
  return meta.mountLevel(kind) > 0
end

-- What the next level costs in marks: 5 for the first, then 1.2x the one before
function meta.mountCost(kind)
  local cost = meta.MOUNT_COST
  for _ = 1, meta.mountLevel(kind) do
    cost = math.floor(cost * 1.2)
  end
  return cost
end

-- Elites of the kind that must have been slain before the next level: one for
-- the first mount, then five more each time
function meta.mountNeed(kind)
  local level = meta.mountLevel(kind)
  return level == 0 and 1 or 1 + meta.MOUNT_KILLS * level
end

-- How much of the first level's bonus a level adds up to: 1, 1.5, 1.75, ...
function meta.mountScale(level)
  return 2 * (1 - 0.5 ^ level)
end

-- The bonus's text at a level
function meta.mountEffect(kind, level)
  local m = meta.MOUNTS[kind]
  return string.format(m.fmt, math.floor(m.base * meta.mountScale(level) + 0.5))
end

-- Mounts a kind's trophy, or upgrades the mount (needs the elites slain and
-- the marks). Returns true if paid.
function meta.mount(kind)
  local p = profile()
  local m = meta.MOUNTS[kind]
  if not p or not m then
    return false
  end
  local level, cost = meta.mountLevel(kind), meta.mountCost(kind)
  if level >= meta.MOUNT_MAX or meta.trophyCount(kind) < meta.mountNeed(kind) or p.marks < cost then
    return false
  end
  p.marks = p.marks - cost
  p.mounted[kind] = level + 1
  meta.mountsDirty = true
  save.touch()
  save.flush()
  return true
end

-- House rules -------------------------------------------------------------------------

local activeRules = {} -- id -> true for this run (copied from the profile when a run starts)

function meta.ruleOn(id)
  local p = profile()
  return p ~= nil and p.rules[id] == true
end

function meta.toggleRule(id)
  local p = profile()
  if not p then
    return
  end
  p.rules[id] = not p.rules[id] or nil
  save.touch()
end

-- A run starts: the chosen rules apply to it (and nothing mid-run changes them)
function meta.limbOn(id)
  local p = profile()
  return p ~= nil and p.limbs ~= nil and p.limbs[id] == true
end

function meta.toggleLimb(id)
  local p = profile()
  if not p then
    return
  end
  p.limbs = p.limbs or {}
  p.limbs[id] = not p.limbs[id] or nil
  meta.mountsDirty = true
  save.touch()
end

-- The Sawbone's patching up: how much a heal of `frac` of max health restores
-- (at most what is missing) and what it costs in gold
function meta.sawHealQuote(player, frac)
  local missing = math.max(0, player.maxHp - player.hp)
  local heal = math.min(missing, math.ceil(player.maxHp * frac))
  local p = profile()
  local disc = 1 - 0.25 * ((p and p.upgrades.cheapcuts) or 0)
  local gold = heal > 0 and math.max(5, math.floor(heal * 0.9 * disc / 5 + 0.5) * 5) or 0
  return heal, gold
end

meta.SAW_MARKS = 2 -- a full heal paid in marks

-- mode: "half", "full" (gold) or "marks" (a full heal for marks). Returns true if done
function meta.sawHeal(player, inv, mode)
  if player.dead then
    return false
  end
  if mode == "marks" then
    if player.hp >= player.maxHp or not spend(meta.SAW_MARKS) then
      return false
    end
    player.hp = player.maxHp
    return true
  end
  local heal, gold = meta.sawHealQuote(player, mode == "half" and 0.5 or 1)
  if heal <= 0 or inv.gold < gold then
    return false
  end
  inv.gold = inv.gold - gold
  player.hp = math.min(player.maxHp, player.hp + heal)
  return true
end

function meta.beginRun()
  meta.mountsDirty = true
  activeRules = {}
  local p = profile()
  for _, r in ipairs(meta.RULES) do
    if p and p.rules[r.id] then
      activeRules[r.id] = true
    end
  end
end

local function ruleProd(key)
  local v = 1
  for _, r in ipairs(meta.RULES) do
    if activeRules[r.id] and r[key] then
      v = v * r[key]
    end
  end
  return v
end

function meta.enemyHpMul() return ruleProd("enemyHp") end
function meta.enemyDmgMul() return ruleProd("enemyDmg") end
function meta.markMul() return ruleProd("marks") end
function meta.shopMul() return ruleProd("shop") end

-- Flasks (the Pocket Flask): the number a run starts with
function meta.startFlasks()
  return meta.tier("flask")
end

-- The mounted trophies' bonuses, summed into one fx table (see perks.extraFx)
local mountFx, mountVersion = {}, nil
function meta.mountFx()
  local p = profile()
  local out = {}
  if p then
    -- the Apothecary's tonic and the house rules' prices belong here too
    if (p.upgrades.vigor or 0) > 0 then
      out.maxHp = 12 * p.upgrades.vigor
    end
    local shop = meta.shopMul()
    if shop ~= 1 then
      out.shopPrice, out.healPrice = shop, shop
    end
    -- what the Sawbone has taken: a bonus, and a price (the sharper saw grows the bonus)
    local sharp = 1 + 0.2 * (p.upgrades.sharpsaw or 0)
    for _, limb in ipairs(meta.LIMBS) do
      if p.limbs and p.limbs[limb.id] then
        for k, v in pairs(limb.fx) do
          local good
          if meta.LIMB_MULT[k] then
            good = (k == "fireDelay" and v < 1) or (k == "spread" and v < 1) or (k == "damage" and v > 1) or (k == "gold" and v > 1) or (k == "jump" and v > 1)
            if good then
              v = 1 + (v - 1) * sharp
              if k == "fireDelay" or k == "spread" then
                v = math.max(0.2, v)
              end
            end
            out[k] = (out[k] or 1) * v
          else
            out[k] = (out[k] or 0) + v * ((k == "crit" or k == "regen") and sharp or 1)
          end
        end
      end
    end
    for kind in pairs(p.mounted) do
      local m = meta.MOUNTS[kind]
      local scale = meta.mountScale(math.max(1, meta.mountLevel(kind)))
      for k, v in pairs(m and m.fx or {}) do
        if k == "speed" or k == "reload" or k == "jump" or k == "dmgTaken" or k == "gold" or k == "kickDamage" then
          out[k] = (out[k] or 1) * (1 + (v - 1) * scale)
        else
          out[k] = (out[k] or 0) + v * scale
        end
      end
    end
  end
  return out
end

-- A prisoner is freed: they move to camp. Returns true the first time.
function meta.rescue(id)
  local p = profile()
  if not p or p.camp[id] then
    return false
  end
  p.camp[id] = true
  save.touch()
  meta.earn(meta.EARN.rescue, (meta.PEOPLE[id] and meta.PEOPLE[id].name or id) .. " freed")
  save.flush()
  return true
end

function meta.upgrade(id)
  return upgradeById[id]
end

function meta.tier(id)
  local p = profile()
  return p and p.upgrades[id] or 0
end

-- What the next tier of an upgrade costs (nil when it is maxed)
function meta.nextCost(id)
  local u = upgradeById[id]
  return u and u.costs[meta.tier(id) + 1] or nil
end

-- Buys the next tier. Returns true if paid.
function meta.buy(id)
  local cost = meta.nextCost(id)
  if not cost or not spend(cost) then
    return false
  end
  local p = profile()
  p.upgrades[id] = meta.tier(id) + 1
  meta.mountsDirty = true
  save.flush()
  if meta.onBought then
    meta.onBought(id)
  end
  return true
end

-- Hooks ---------------------------------------------------------------------------------

function meta.install()
  items.isAvailable = function(id)
    local def = items.defs[id]
    return meta.isUnlocked(def.kind, id)
  end
  guns.isAvailable = function(id)
    return meta.isUnlocked("weapon", id)
  end
  require("src.perks").isAvailable = meta.perkUnlocked
  guns.rollBoost = function()
    return 1 + 0.15 * meta.tier("grades")
  end
  guns.extraSlotChance = function()
    return 0.15 * meta.tier("slots")
  end
  require("src.inventory").startItemChance = function(base)
    return meta.tier("holster") > 0 and 1 or base
  end
  require("src.inventory").startDynamite = meta.startDynamite
  require("src.inventory").startFlasks = meta.startFlasks
  -- (cached: perks.sum/prod ask for it many times a frame)
  local cache, stamp = {}, nil
  require("src.perks").extraFx = function()
    local p = profile()
    local key = p and p.mounted
    if key ~= stamp or meta.mountsDirty then
      cache, stamp, meta.mountsDirty = meta.mountFx(), key, false
    end
    return cache
  end
end

-- The mark's sigil: a small silver-violet brand, s window pixels per pixel
local SIGIL = {
  "...#...",
  "..#.#..",
  ".#.#.#.",
  "#.###.#",
  ".#.#.#.",
  "..#.#..",
  "...#...",
}
meta.SIGIL_COLOR = { 0.80, 0.74, 1.0 }
function meta.drawSigil(x, y, s, alpha)
  alpha = alpha or 1
  local c = meta.SIGIL_COLOR
  love.graphics.setColor(0.10, 0.07, 0.16, 0.8 * alpha)
  for row = 1, 7 do
    for col = 1, 7 do
      if SIGIL[row]:sub(col, col) == "#" then
        love.graphics.rectangle("fill", x + col * s, y + row * s, s, s)
      end
    end
  end
  for row = 1, 7 do
    for col = 1, 7 do
      if SIGIL[row]:sub(col, col) == "#" then
        local k = (row == 4 and col == 4) and 1 or 0.85
        love.graphics.setColor(c[1] * k + (1 - k) * 0.4, c[2] * k + (1 - k) * 0.3, c[3] * k + (1 - k) * 0.6, alpha)
        love.graphics.rectangle("fill", x + (col - 1) * s, y + (row - 1) * s, s, s)
      end
    end
  end
end

return meta
