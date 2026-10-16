-- The bounty board (design doc §11a-vii step 4): wanted posters at camp for
-- named elites. The board holds three posters; the hunter takes up to two.
-- A taken bounty is saved with the profile and waits in its area in every
-- run until it is claimed: when that area's monsters exist, one of the right
-- kind (or a fresh one) becomes the named elite. Killing it pays the reward
-- at once (src.meta.earn), and the poster comes down; a new one goes up when
-- the next run starts.
--
-- A bounty: { id, name, kind, affixes, area, depth (1 upper, 2 middle,
-- 3 lower third of the area), reward, taken }
local catacombs = require("src.scenes.catacombs")
local enemies = require("src.enemies")
local meta = require("src.meta")
local save = require("src.save")

local bounties = {}

bounties.POSTED = 3 -- posters on the board
bounties.MAX_TAKEN = 2 -- bounties the hunter can hold at once

-- Set by src.game: a note for the hunter (title, label)
bounties.onNotice = nil

-- Kinds that walk the floors (so a fresh one can always be placed)
local KINDS = { "ghoul", "hopper", "miner", "roller" }
local TITLES = { "Old", "Mad", "Black", "One-Eyed", "Grinning", "Hungry", "Red", "Crooked", "Grey", "Lame", "Gentleman", "Sour" }
local NOUNS = {
  ghoul = { "Gnasher", "Bone-Picker", "Marrow", "Grub", "Knuckles", "Sallow Tom" },
  hopper = { "Croaker", "Bloat-Belly", "Leaper", "Toad King", "Big Slick", "Puddle" },
  miner = { "Jack", "Dynamite Dan", "Pickaxe Pete", "Lanternjaw", "Tallow", "Fuse" },
  roller = { "Boulder", "Iron Shell", "Tumbler", "Rumble", "Pebble", "Millstone" },
}
bounties.DEPTHS = { "upper", "middle", "lower" }

local placed = {} -- bounty id -> the monster carrying it this run
local noticed = {} -- bounty id -> true once its note was shown this run

local function data(p)
  p = p or save.profile()
  if not p then
    return nil
  end
  if type(p.bounties) ~= "table" then
    p.bounties = {}
  end
  local d = p.bounties
  d.list = type(d.list) == "table" and d.list or {}
  d.next = tonumber(d.next) or 1
  d.claimed = tonumber(d.claimed) or 0
  return d
end

-- A new run: nothing is placed yet, nothing announced
function bounties.reset()
  placed, noticed = {}, {}
end

-- The posters on the board (with taken ones), in order
function bounties.list()
  local d = data()
  return d and d.list or {}
end

function bounties.taken()
  local n = 0
  for _, b in ipairs(bounties.list()) do
    if b.taken then
      n = n + 1
    end
  end
  return n
end

-- Areas a bounty can send the hunter to: ones the profile has reached, plus
-- the first two, that have the kind in them and nothing in the way (no
-- flooding, no boss-only chambers)
local function areasFor(p, kind)
  local out = {}
  for i = 1, catacombs.count() do
    local th = catacombs.theme(i)
    local reached = i <= 2 or (p.seen.area and p.seen.area[i])
    if th and reached and not th.flood and th.monsters and (th.monsters[kind] or 0) > 0 then
      out[#out + 1] = i
    end
  end
  return out
end

local function roll(p, d, random)
  random = random or love.math.random
  -- (a kind already on the board is passed over while there are others)
  local onBoard = {}
  for _, o in ipairs(d.list) do
    onBoard[o.kind] = true
  end
  for try = 1, 20 do
    local kind = KINDS[random(1, #KINDS)]
    if onBoard[kind] and try < 12 then
      kind = nil
    end
    local areas = kind and areasFor(p, kind) or {}
    if #areas > 0 then
      local area = areas[random(1, #areas)]
      local rank = catacombs.rank(area)
      local options = {}
      for _, a in ipairs(enemies.AFFIX_ORDER) do
        options[#options + 1] = a
      end
      local affixes = { table.remove(options, random(1, #options)) }
      if rank >= 2 then
        affixes[2] = table.remove(options, random(1, #options))
      end
      local nouns = NOUNS[kind]
      local b = {
        id = d.next,
        name = TITLES[random(1, #TITLES)] .. " " .. nouns[random(1, #nouns)],
        kind = kind,
        affixes = affixes,
        area = area,
        depth = random(1, 3),
        reward = 6 + 3 * rank + 2 * (#affixes - 1),
      }
      d.next = d.next + 1
      return b
    end
  end
  return nil
end

-- Fills the board back up to three posters (when a run starts)
function bounties.refresh(random)
  local p = save.profile()
  local d = data(p)
  if not d then
    return
  end
  while #d.list < bounties.POSTED do
    local b = roll(p, d, random)
    if not b then
      break
    end
    d.list[#d.list + 1] = b
  end
  save.touch()
end

function bounties.take(b)
  if b.taken or bounties.taken() >= bounties.MAX_TAKEN then
    return false
  end
  b.taken = true
  save.touch()
  save.flush()
  return true
end

-- Tears a poster down (a taken one is given up; nothing is paid back)
function bounties.abandon(b)
  local d = data()
  if not d then
    return
  end
  for i, o in ipairs(d.list) do
    if o == b then
      table.remove(d.list, i)
      break
    end
  end
  local e = placed[b.id]
  if e and not e.dead then
    e.bounty, e.bountyName = nil, nil
  end
  save.touch()
  save.flush()
end

local function find(id)
  for _, b in ipairs(bounties.list()) do
    if b.id == id then
      return b
    end
  end
  return nil
end

-- The named elite is dead: pay the reward and take the poster down
function bounties.claim(e)
  local b = find(e.bounty)
  if not b then
    return
  end
  local d = data()
  for i, o in ipairs(d.list) do
    if o == b then
      table.remove(d.list, i)
      break
    end
  end
  d.claimed = d.claimed + 1
  meta.earn(b.reward, "Bounty claimed: " .. b.name)
  save.flush()
end

-- Turns a monster (or a fresh one) in the bounty's area into its named elite
local function place(b)
  local info = catacombs.info(b.area)
  local a = info.area
  local want = a.y0 + (a.y1 - a.y0) * ((b.depth - 0.5) / 3)
  local best, bestD
  for _, e in ipairs(enemies.all()) do
    if e.kind == b.kind and not e.dead and not e.def.boss and not e.bounty and catacombs.levelAt(e.body.y, e.body.x) == b.area then
      local dd = math.abs(e.body.y - want)
      if not bestD or dd < bestD then
        best, bestD = e, dd
      end
    end
  end
  if not best or bestD > (a.y1 - a.y0) / 3 then
    -- Nobody fits: a fresh one on a floor spot in the right third
    local spots = info.crates or {}
    local spot, sd
    for _, s in ipairs(spots) do
      local dd = math.abs(s[2] - want)
      if not sd or dd < sd then
        spot, sd = s, dd
      end
    end
    if spot then
      local rank = catacombs.rank(b.area)
      best = enemies.spawn(b.kind, spot[1], spot[2], 1 + (rank - 1) * 0.6, rank)
    end
  end
  if best then
    enemies.makeBounty(best, b)
    placed[b.id] = best
  end
  return best
end

-- Every frame: places taken bounties whose areas now exist, and notes it
-- when the hunter walks into an area with one
function bounties.update(player, area)
  local p = save.profile()
  if not p then
    return
  end
  for _, b in ipairs(bounties.list()) do
    if b.taken then
      if not placed[b.id] and catacombs.spawned(b.area) then
        place(b)
      end
      if area == b.area and not noticed[b.id] and placed[b.id] then
        noticed[b.id] = true
        if bounties.onNotice then
          bounties.onNotice("Bounty: " .. b.name, "Somewhere in the " .. bounties.DEPTHS[b.depth] .. " part of this area")
        end
      end
    end
  end
end

-- Where a bounty is, in words: "the lower Sunken Hollows"
function bounties.where(b)
  return "the " .. bounties.DEPTHS[b.depth] .. " " .. (catacombs.areaName(b.area) or ("area " .. b.area)):gsub("^The ", "")
end

function bounties.placed(id)
  return placed[id]
end

return bounties
