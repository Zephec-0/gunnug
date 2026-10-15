-- What killed the hunter, and how the death recap tells it (design doc §9d).
-- Every source of damage names itself when it hurts the hunter (Player:hurt
-- and hurtOverTime take a source id: an enemy's kind, or one of the others
-- below), and the last one to hurt him is the killer. A line reads:
--
--   <Name> met his end by the <adjective> <killer>.
--
-- followed by a western quip. Enemy names come from enemies.defs (so a new
-- monster only needs a name there; add adjectives here for flavour, or it
-- falls back to a few general ones).
local enemies = require("src.enemies")

local deaths = {}

-- Adjectives per enemy kind
local ADJECTIVES = {
  ghoul = { "Starving", "Shambling", "Ravenous", "Ash-Pale" },
  bat = { "Screeching", "Bloodthirsty", "Leathery" },
  swarmbat = { "Frenzied", "Fluttering", "Pestering" },
  spitter = { "Drooling", "Venomous", "Spiteful" },
  hopper = { "Bog-Bellied", "Slimy", "Spry" },
  bloater = { "Swollen", "Pestilent", "Gassy" },
  wisp = { "Flickering", "Cinder-Hearted", "Mischievous" },
  worm = { "Burrowing", "Slithering", "Dirt-Dwelling" },
  miner = { "Rattling", "Dynamite-Happy", "Hard-Working" },
  roller = { "Rolling", "Armour-Plated", "Ornery" },
  piranha = { "Toothy", "Ornery", "Hungry" },
}
local BOSS_ADJECTIVES = { "Mighty", "Merciless", "Terrible", "Dreaded" }
local GENERAL_ADJECTIVES = { "Wicked", "Ornery", "Cussed" }

-- Everything that isn't an enemy: { noun, adjectives }
local OTHER = {
  dynamite = { "Stick of Dynamite", { "Lit", "Short-Fused", "Sputtering" } },
  keg = { "Powder Keg", { "Unlucky", "Rotten", "Tempting" } },
  selfblast = { "Blast of His Own Making", { "Reckless", "Ill-Judged", "Careless" } },
  gas = { "Gas", { "Poisonous", "Choking", "Sulfurous" } },
  fire = { "Flames", { "Roaring", "Hungry", "Licking" } },
  water = { "Black Water", { "Cold", "Deep", "Unforgiving" } },
  lava = { "Molten Rock", { "Glowing", "Merciless", "Bubbling" } },
  acid = { "Acid", { "Hissing", "Biting", "Green" } },
  dark = { "Dark", { "Unforgiving", "Endless", "Silent" } },
}

local QUIPS = {
  "Reckon the catacombs keep what they're given.",
  "Boots on, hat on, and not a soul to bury him.",
  "Folks say it's a long, dry road to the other side.",
  "Should've shot first.",
  "Dust to dust, with a little lead for company.",
  "Another good man for the sagebrush.",
  "He never did see it coming.",
  "May the next hunter ride a little straighter.",
  "Hard way to end a day, partner.",
  "The buzzards will be along by sundown.",
  "That's one more name for the saloon wall.",
  "The desert wind will sing him out.",
  "Quick on the draw, but not quite quick enough.",
  "There's always another hunter in the next town.",
  "He went down swinging, and that's all a man can ask.",
  "Wasn't the first to try the deep, won't be the last.",
}

local function pick(list)
  return list[love.math.random(#list)]
end

-- The source id for an enemy that hurt the hunter
function deaths.sourceFor(e)
  return e.kind
end

-- "Adjective Noun" for a source id (a random adjective each time), and the
-- noun on its own
function deaths.describe(id)
  local other = OTHER[id or "dark"]
  if other then
    return pick(other[2]) .. " " .. other[1], other[1]
  end
  local def = enemies.defs[id]
  if not def then
    return pick(OTHER.dark[2]) .. " " .. OTHER.dark[1], OTHER.dark[1]
  end
  local noun = def.name or (id:sub(1, 1):upper() .. id:sub(2))
  noun = noun:gsub("^The ", "")
  local adjectives = def.boss and BOSS_ADJECTIVES or ADJECTIVES[id] or GENERAL_ADJECTIVES
  return pick(adjectives) .. " " .. noun, noun
end

function deaths.quip()
  return pick(QUIPS)
end

-- The recap's two parts: the hunter's name, and "the <adjective> <killer>"
function deaths.recap(name, sourceId)
  local killer, noun = deaths.describe(sourceId)
  return {
    name = name or "The hunter",
    killer = killer,
    noun = noun,
    quip = deaths.quip(),
  }
end

return deaths
