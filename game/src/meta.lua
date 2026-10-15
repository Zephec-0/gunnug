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
    found = "Buried under a cave-in in the Catacombs",
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
  found = "Caged in the Old Quarry",
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
meta.PEOPLE.taxidermist = {
  name = "The Taxidermist",
  found = "Arrives once you carry an elite's trophy home",
  blurb = "Mounts the trophies of the elites you have slain. Each kind he mounts gives you a small bonus in every run, for good.",
  greeting = {
    "Don't touch the glass eyes. They watch.",
    "Bring me something with character.",
    "A good mount lasts longer than a good reputation.",
    "Hold still. No, not you. The ghoul.",
  },
}

-- What mounting each kind's trophy gives (a perk-style fx table), and its name
meta.MOUNTS = {
  ghoul = { name = "Ghoul", effect = "+10 max health", fx = { maxHp = 10 }, cost = 3 },
  bat = { name = "Cave Bat", effect = "+4% movement speed", fx = { speed = 1.04 }, cost = 3 },
  spitter = { name = "Spitter", effect = "reloads 5% faster", fx = { reload = 0.95 }, cost = 3 },
  hopper = { name = "Mire Hopper", effect = "+5% jump height", fx = { jump = 1.05 }, cost = 3 },
  bloater = { name = "Bloater", effect = "take 4% less damage", fx = { dmgTaken = 0.96 }, cost = 3 },
  miner = { name = "Skeleton Miner", effect = "+6% gold from everything", fx = { gold = 1.06 }, cost = 3 },
  roller = { name = "Cave Roller", effect = "kicks hit 20% harder", fx = { kickDamage = 1.2 }, cost = 3 },
}
-- The Bartender's house rules: each makes the next run harder and pays more marks
meta.RULES = {
  { id = "rotgut", name = "Rotgut", desc = "Monsters have 40% more health.", marks = 1.35, enemyHp = 1.4 },
  { id = "powderkeg", name = "Powder Keg", desc = "Monsters hit 30% harder.", marks = 1.3, enemyDmg = 1.3 },
  { id = "lean", name = "Lean Times", desc = "Shops charge 30% more, healing too.", marks = 1.2, shop = 1.3 },
}
meta.MOUNT_ORDER = { "ghoul", "bat", "spitter", "hopper", "bloater", "miner", "roller" }

-- The Prospector's strongbox: how much it holds, by Bigger Strongbox tier
meta.BANK_CAP = { 100, 250, 600 }

-- Upgrades sold at camp: each has tiers, bought in order with marks
meta.UPGRADES = {
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

-- A random locked gun archetype (nil if none are left)
function meta.lockedArchetype(random)
  random = random or love.math.random
  local pool = meta.locked("weapon")
  if #pool == 0 or not profile() then
    return nil
  end
  return pool[random(1, #pool)]
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

function meta.atCamp(id)
  local p = profile()
  if p and id == "taxidermist" then
    return meta.trophyTotal() > 0 -- (nobody to free: he turns up with the first trophy)
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

function meta.isMounted(kind)
  local p = profile()
  return p ~= nil and p.mounted[kind] == true
end

-- Mounts a kind's trophy (needs one slain, and the marks). Returns true if paid.
function meta.mount(kind)
  local p = profile()
  local m = meta.MOUNTS[kind]
  if not p or not m or meta.isMounted(kind) or meta.trophyCount(kind) <= 0 or p.marks < m.cost then
    return false
  end
  p.marks = p.marks - m.cost
  p.mounted[kind] = true
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
    for kind in pairs(p.mounted) do
      local m = meta.MOUNTS[kind]
      for k, v in pairs(m and m.fx or {}) do
        if k == "speed" or k == "reload" or k == "jump" or k == "dmgTaken" or k == "gold" or k == "kickDamage" then
          out[k] = (out[k] or 1) * v
        else
          out[k] = (out[k] or 0) + v
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
