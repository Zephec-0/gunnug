-- The camp's people (design doc §11a-iv, §11a-vi): found below, then they
-- move to camp. So far one: the Gunsmith.
--
-- In the dungeon a prisoner sits in an iron cage on a cave floor, calling out
-- when the hunter comes near. Shooting the padlock off (or blasting it) frees
-- them: they thank him, walk out and are gone, the profile records that they
-- live at camp now (src.meta.rescue, which pays marks), and they leave a gift
-- on the cage floor. A cage whose prisoner is already at camp stands open
-- and empty.
--
-- At camp each freed person has a stall by the fire (the Gunsmith: a workbench
-- and an anvil under an awning, hammering away). Standing next to them shows
-- "[E] Talk to ..." and E opens their page in the menu (npcs.onTalk).
local audio = require("src.audio")
local effects = require("src.effects")
local guns = require("src.guns")
local input = require("src.input")
local meta = require("src.meta")
local people = require("src.people")
local pickups = require("src.pickups")

local npcs = {}

-- Set by src.game: called with the person's id when the hunter talks to them
npcs.onTalk = nil

local cages = {}
local camp = {} -- id -> { x, y = ground }
local TALK_REACH = 22
local CALL_RANGE = 120 -- a prisoner calls out to the hunter within this

local CALLS = {
  apothecary = { "Hunter! Mind the fumes!", "The lock! I can barely breathe!", "I'm no use to anyone in here!", "Shoot the padlock, please!" },
  cartographer = { "Over here! A friendly hand!", "My maps! Shoot the lock!", "I've charted worse. Not much worse.", "Please, the padlock!" },
  gunsmith = { "Hunter! Over here!", "Shoot the lock off, quick!", "They'll be back for me...", "Please, the lock!" },
  prospector = { "Down here! Under the rock!", "Shoot the dirt off me!", "Can't feel my legs...", "Dig, hunter, dig!" },
}
local THANKS = {
  apothecary = { "Fresh air, at last!", "I'll set up by your camp.", "Here, a tonic for the road." },
  cartographer = { "I owe you a good map!", "Find me at your camp.", "Take this. Don't ask what it's for." },
  gunsmith = { "Bless you, hunter!", "I'll make for your camp.", "Find me by the fire. Take this." },
  prospector = { "Air! Sweet air!", "I'll be under the arch, west of your fire.", "Here, for your trouble. Mind the fuses." },
}

-- Set by src.game: called with the person's id when they are freed (their
-- gift for this run, beyond what drops on the ground)
npcs.onFreed = nil

function npcs.clear()
  cages = {}
  camp = {}
  board = nil
end

-- A cage with `id` inside, standing on the floor at (x, groundY); held =
-- "rubble" instead for someone buried by a cave-in (top: the mound's top)
function npcs.spawnCage(id, x, groundY, held, top)
  local c = { id = id, x = math.floor(x), y = math.floor(groundY), state = "locked", t = 0, callT = 1.5, call = 0, door = 0, held = held or "cage", top = top or (groundY - 21), digT = 0 }
  cages[#cages + 1] = c
  return c
end

-- The bounty board at camp (src.bounties): always there
local board -- { x, y = ground }

function npcs.setBoard(x, groundY)
  board = { x = math.floor(x), y = math.floor(groundY) }
end

-- Where a person's stall stands at camp (the overworld places them)
function npcs.setCamp(id, x, groundY)
  camp[id] = { id = id, x = math.floor(x), y = math.floor(groundY), hammer = 0, near = false, said = false }
end

function npcs.cages()
  return cages
end

local function say(c, text)
  c.say = { text = text, age = 0 }
end

-- The lock: a shot inside this box (or a blast reaching it) breaks it
function npcs.lockAt(px, py)
  for _, c in ipairs(cages) do
    if c.held == "cage" and c.state == "locked" and px >= c.x - 1 and px <= c.x + 6 and py >= c.y - 17 and py <= c.y - 7 then
      return c
    end
  end
  return nil
end

function npcs.breakLock(c)
  if c.state ~= "locked" then
    return
  end
  c.state = "open"
  c.t = 0
  if c.held == "cage" then
    audio.play("clank")
    for _ = 1, 14 do
      effects.particle(c.x + 2, c.y - 11, (love.math.random() - 0.5) * 80, -30 - love.math.random() * 40, 0.6, { 0.85, 0.7, 0.3 }, 400)
    end
    effects.chunk(c.x + 2, c.y - 11, 30 + love.math.random() * 30, -60, 3, 3, { 0.75, 0.6, 0.25 }, 3)
  else
    audio.play("pickup")
  end
  c.thanks = 0
  say(c, THANKS[c.id] and THANKS[c.id][1] or "Thank you!")
  if meta.rescue(c.id) then
    if c.id == "prospector" then
      -- His gift: a pouch of nuggets (and dynamite, from src.game)
      pickups.dropGold(c.x, c.y - 10, 60)
    else
      -- A gift on the cage floor: a gun he doesn't make yet if there is one
      local kind = meta.lockedArchetype()
      pickups.dropWeapon(c.x - 4, c.y - 8, guns.generate(kind, nil, 0.5), -30, -90)
    end
    if npcs.onFreed then
      npcs.onFreed(c.id)
    end
  end
end

function npcs.explosion(x, y, radius)
  for _, c in ipairs(cages) do
    local dx, dy = c.x + 2 - x, c.y - 11 - y
    if c.state == "locked" and dx * dx + dy * dy < (radius + 6) ^ 2 then
      npcs.breakLock(c)
    end
  end
end

function npcs.update(dt, player)
  local px, py = player:center()
  for _, c in ipairs(cages) do
    if c.say then
      c.say.age = c.say.age + dt
    end
    if c.state == "locked" and meta.atCamp(c.id) then
      c.state = "empty" -- already freed in an earlier run
      c.door = 1
    end
    if c.state == "locked" and c.held == "rubble" then
      -- Buried: free once most of the earth over his body has been dug away
      c.digT = c.digT - dt
      if c.digT <= 0 then
        c.digT = 0.2
        local w = player.world
        local solid = 0
        for yy = c.y - 16, c.y - 1, 2 do
          for xx = c.x - 3, c.x + 3 do
            if w:isSolid(xx, yy) then
              solid = solid + 1
            end
          end
        end
        if solid <= 14 then
          npcs.breakLock(c)
        end
      end
    end
    if c.state == "locked" then
      local d = math.abs(px - c.x) + math.abs(py - (c.y - 10)) * 1.5
      c.alert = d < CALL_RANGE and not player.dead
      c.facing = px < c.x and -1 or 1
      if c.alert then
        c.callT = c.callT - dt
        if c.callT <= 0 then
          local lines = CALLS[c.id] or { "Help!" }
          c.call = c.call % #lines + 1
          say(c, lines[c.call])
          c.callT = 3.6
        end
      else
        c.callT = math.min(c.callT, 0.6)
      end
    elseif c.state == "open" then
      c.t = c.t + dt
      c.door = math.min(1, c.door + dt * 3)
      local lines = THANKS[c.id] or {}
      local n = math.min(#lines, 1 + math.floor(c.t / 1.6))
      if n > (c.thanks or 0) + 1 and lines[n] then
        c.thanks = n - 1
        say(c, lines[n])
      end
      if c.t > 5.2 then
        c.state = "empty"
        for _ = 1, 16 do
          effects.particle(c.x + 18 + (love.math.random() - 0.5) * 10, c.y - 2 - love.math.random() * 16, (love.math.random() - 0.5) * 20, -10 - love.math.random() * 10, 0.9, { 0.55, 0.5, 0.45 }, -10)
        end
      end
    end
  end
  for id, s in pairs(camp) do
    if meta.atCamp(id) then
      local near = math.abs(px - s.x) < 70 and math.abs(py - (s.y - 10)) < 40
      if near and not s.said then
        -- (one greeting at a time: wait until nobody else is still talking)
        local busy = false
        for _, o in pairs(camp) do
          busy = busy or (o ~= s and o.say ~= nil and o.say.age < 3.4)
        end
        if not busy then
          local lines = meta.PEOPLE[id] and meta.PEOPLE[id].greeting or { "Hello." }
          say(s, lines[love.math.random(1, #lines)])
          s.said = true
        end
      elseif not near and math.abs(px - s.x) > 160 then
        s.said = false
      end
      s.near = near
      if near then
        s.hammer = 0
      else
        local before = s.hammer
        s.hammer = (s.hammer + dt / 1.3) % 1
        if id == "gunsmith" and before < 0.62 and s.hammer >= 0.62 then
          -- The hammer comes down on the anvil: a few sparks
          for _ = 1, 5 do
            effects.particle(s.x + 9, s.y - 10, (love.math.random() - 0.3) * 50, -20 - love.math.random() * 40, 0.35, { 1, 0.75, 0.35 }, 300, true)
          end
        end
      end
      if s.say then
        s.say.age = s.say.age + dt
      end
    end
  end
end

-- The camp person next to the hunter, if any
local function nearestCamp(player)
  local px, py = player:center()
  for id, s in pairs(camp) do
    if meta.atCamp(id) and math.abs(px - s.x) < (people.has(id) and 34 or TALK_REACH) and math.abs(py - (s.y - 10)) < 24 then
      return s
    end
  end
  return nil
end

local function nearBoard(player)
  if not board or not meta.boardOpen() then
    return false
  end
  local px, py = player:center()
  return math.abs(px - board.x) < TALK_REACH and math.abs(py - (board.y - 10)) < 24
end

-- E: talk to whoever is next to the hunter. Returns true if it handled the key.
function npcs.interact(player)
  if nearBoard(player) then
    if require("src.events").deliver(player) then
      return true
    end
    audio.play("page")
    if npcs.onTalk then
      npcs.onTalk("board")
    end
    return true
  end
  local s = nearestCamp(player)
  if not s then
    return false
  end
  audio.play("select")
  if npcs.onTalk then
    npcs.onTalk(s.id)
  end
  return true
end

-- Drawing ------------------------------------------------------------------------------

local function R(c, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
  love.graphics.rectangle("fill", x, y, w, h)
end

local SKIN, SKIN_D = { 0.80, 0.60, 0.46 }, { 0.62, 0.44, 0.34 }
local BEARD = { 0.72, 0.70, 0.66 }
local CAP, BRASS, GLASS = { 0.27, 0.21, 0.16 }, { 0.82, 0.64, 0.28 }, { 0.55, 0.85, 0.9 }
local SHIRT, SHIRT_D = { 0.50, 0.21, 0.17 }, { 0.36, 0.15, 0.13 }
local APRON, APRON_D = { 0.44, 0.30, 0.17 }, { 0.30, 0.20, 0.11 }
local TROUSER, BOOT = { 0.22, 0.21, 0.25 }, { 0.14, 0.11, 0.09 }
local EYE = { 0.08, 0.07, 0.08 }
local IRON, IRON_D, IRON_L = { 0.34, 0.34, 0.38 }, { 0.18, 0.18, 0.21 }, { 0.55, 0.56, 0.6 }
local RUST = { 0.45, 0.25, 0.14 }
local WOOD, WOOD_L, WOOD_D = { 0.45, 0.30, 0.16 }, { 0.60, 0.42, 0.22 }, { 0.28, 0.19, 0.10 }
local CANVAS, CANVAS_D = { 0.55, 0.48, 0.36 }, { 0.40, 0.34, 0.25 }
local STRAW, STRAW_D = { 0.46, 0.40, 0.24 }, { 0.32, 0.27, 0.16 }

-- The Gunsmith, standing at (x, ground g), facing +1 or -1. pose: "stand",
-- "hammer" (k: 0..1 through a swing) or "sit"; alpha fades him out.
local function drawGunsmith(x, g, facing, pose, k, alpha)
  love.graphics.push()
  love.graphics.translate(x, g)
  love.graphics.scale(facing, 1)
  local a = alpha or 1
  local function r(c, dx, dy, w, h)
    R({ c[1], c[2], c[3], a }, dx, dy, w, h)
  end
  if pose == "sit" then
    -- Slumped against the bars, knees up, head down
    r(BOOT, 3, -2, 3, 2)
    r(TROUSER, -3, -4, 6, 2)
    r(TROUSER, 2, -6, 2, 4)
    r(SHIRT_D, -5, -11, 2, 5)
    r(SHIRT, -4, -11, 5, 7)
    r(APRON, -2, -10, 4, 6)
    r(APRON_D, -2, -10, 4, 1)
    r(SKIN, 1, -7, 2, 1)
    r(SKIN, -3, -15, 5, 4)
    r(BEARD, -3, -12, 5, 2)
    r(BEARD, -2, -11, 3, 1)
    r(EYE, 1, -14, 1, 1)
    r(CAP, -4, -17, 6, 2)
    r(CAP, 2, -16, 2, 1)
    r(BRASS, -2, -17, 3, 1)
    love.graphics.pop()
    return
  end
  -- boots and trousers
  r(BOOT, -4, -2, 3, 2)
  r(BOOT, 1, -2, 4, 2)
  r(TROUSER, -4, -6, 3, 4)
  r(TROUSER, 1, -6, 3, 4)
  -- back arm, behind the body
  r(SHIRT_D, -5, -13, 1, 4)
  r(SKIN_D, -5, -9, 1, 2)
  -- shirt and the leather apron over it
  r(SHIRT, -4, -13, 8, 7)
  r(APRON, -2, -12, 6, 8)
  r(APRON_D, -2, -12, 6, 1)
  r(APRON_D, -1, -13, 1, 1)
  r(APRON_D, 0, -8, 3, 1) -- a pocket
  -- front arm: hanging, or swinging the hammer
  if pose == "hammer" then
    local up = k < 0.62
    if up then
      local lift = math.min(1, k / 0.5)
      local hy = -13 - math.floor(lift * 4)
      r(SHIRT, 3, -13, 2, 2)
      r(SKIN, 4, hy, 1, -hy - 11)
      r(WOOD_D, 4, hy - 2, 1, 3) -- the handle
      r(IRON_L, 3, hy - 3, 3, 2) -- the head
    else
      r(SHIRT, 3, -13, 2, 2)
      r(SKIN, 4, -11, 3, 1)
      r(WOOD_D, 6, -12, 2, 1)
      r(IRON_L, 8, -13, 2, 3)
    end
  else
    r(SHIRT, 3, -13, 2, 3)
    r(SKIN, 4, -10, 1, 3)
  end
  -- head: a grey beard, a flat cap with goggles pushed up on it
  r(SKIN, -2, -18, 5, 4)
  r(SKIN, 3, -16, 1, 1)
  r(BEARD, -2, -15, 5, 2)
  r(BEARD, -1, -13, 4, 1)
  r(BEARD, -3, -16, 1, 2)
  r(EYE, 1, -17, 1, 1)
  r(CAP, -3, -20, 6, 2)
  r(CAP, 3, -19, 2, 1)
  r(BRASS, -1, -20, 3, 1)
  r(GLASS, 0, -20, 1, 1)
  love.graphics.pop()
end

-- The Prospector: lanky and old, a battered wide-brimmed hat, white
-- whiskers and a big nose, a red neckerchief, a faded blue shirt under
-- braces. pose: "stand", "pan" (k: 0..1, swirling a gold pan) or "buried"
-- (only his head and a waving arm out of the earth, with g the mound's top)
local P_HAT, P_HAT_D = { 0.56, 0.43, 0.27 }, { 0.36, 0.26, 0.15 }
local P_SHIRT, P_SHIRT_D = { 0.38, 0.46, 0.58 }, { 0.27, 0.33, 0.43 }
local P_TROUSER, P_BRACE = { 0.42, 0.31, 0.20 }, { 0.28, 0.17, 0.09 }
local P_KERCHIEF, P_WHISKER = { 0.72, 0.18, 0.14 }, { 0.88, 0.87, 0.82 }
local PAN = { 0.45, 0.45, 0.50 }

local function drawProspector(x, g, facing, pose, k, alpha)
  love.graphics.push()
  love.graphics.translate(x, g)
  love.graphics.scale(facing, 1)
  local a = alpha or 1
  local function r(c, dx, dy, w, h)
    R({ c[1], c[2], c[3], a }, dx, dy, w, h)
  end
  local function head(oy)
    r(SKIN, -2, -19 + oy, 4, 4)
    r(SKIN_D, 2, -17 + oy, 1, 2) -- the nose
    r(EYE, 1, -18 + oy, 1, 1)
    r(P_WHISKER, -2, -16 + oy, 4, 1)
    r(P_WHISKER, -1, -15 + oy, 3, 1)
    r(P_WHISKER, -3, -17 + oy, 1, 2)
    r(P_HAT, -2, -22 + oy, 4, 2)
    r(P_HAT_D, -2, -21 + oy, 4, 1)
    r(P_HAT, -4, -20 + oy, 8, 1)
    r(P_HAT_D, -5, -20 + oy, 1, 1)
  end
  if pose == "buried" then
    -- g is the top of the mound: his head half out of it, an arm waving
    head(16)
    local wave = math.floor(math.sin(love.timer.getTime() * 8) + 0.5)
    r(P_SHIRT, 3, -2, 1, 3)
    r(SKIN, 3 + wave, -5, 1, 3)
    r(SKIN, 3 + wave, -6, 2, 1)
    love.graphics.pop()
    return
  end
  r(BOOT, -3, -2, 3, 2)
  r(BOOT, 1, -2, 3, 2)
  r(P_TROUSER, -3, -8, 2, 6)
  r(P_TROUSER, 1, -8, 2, 6)
  r(P_SHIRT_D, -4, -14, 1, 4)
  r(SKIN_D, -4, -10, 1, 1)
  r(P_SHIRT, -3, -14, 6, 6)
  r(P_BRACE, -2, -14, 1, 6)
  r(P_BRACE, 1, -14, 1, 6)
  r(P_KERCHIEF, -2, -15, 5, 1)
  r(P_KERCHIEF, -1, -14, 2, 1)
  if pose == "pan" then
    -- Both hands out front, swirling a pan of grit
    local sw = math.floor(math.sin(k * math.pi * 2) + 0.5)
    r(P_SHIRT, 3, -13, 1, 2)
    r(SKIN, 4, -11, 2, 1)
    r(PAN, 4 + sw, -11, 6, 1)
    r(PAN, 5 + sw, -10, 4, 1)
    r({ 0.85, 0.7, 0.3 }, 6 + sw, -11, 1, 1)
  else
    r(P_SHIRT, 3, -14, 1, 3)
    r(SKIN, 3, -11, 1, 2)
  end
  head(0)
  love.graphics.pop()
end

local function drawPerson(id, x, g, facing, pose, k, alpha)
  if id == "prospector" then
    drawProspector(x, g, facing, pose == "sit" and "stand" or pose, k, alpha)
  elseif people.has(id) then
    people.draw(id, x, g, facing, pose == "sit" and "stand" or pose, k, alpha)
  else
    drawGunsmith(x, g, facing, pose, k, alpha)
  end
end

-- A cave-in: someone buried in a mound of earth (the mound is real terrain)
local function drawRubble(c)
  local x = c.x
  if c.state == "locked" then
    drawProspector(x, c.top, c.facing or 1, "buried")
    -- broken shoring sticking out of the heap
    R(WOOD_D, x - 14, c.top + 6, 2, 9)
    R(WOOD, x - 13, c.top + 5, 1, 2)
    for i = 0, 9 do
      R(WOOD_D, x + 6 + i, c.top + 2 + math.floor(i * 0.6), 1, 2)
    end
  elseif c.state == "open" then
    local walk = math.max(0, c.t - 1.4) * 14
    local fade = math.max(0, math.min(1, (5.2 - c.t) / 1))
    local step = (walk > 0 and math.floor(c.t * 6) % 2 == 0) and 1 or 0
    drawProspector(x + math.floor(walk), c.y - step, 1, "stand", 0, fade)
  end
  -- the lantern he had, on its side
  R(IRON_D, x - 22, c.y - 3, 4, 3)
end

local function drawCage(c)
  if c.held == "rubble" then
    return drawRubble(c)
  end
  local x, g = c.x, c.y
  -- straw and a bowl inside, behind him
  R(STRAW_D, x - 12, g - 3, 24, 1)
  for i = 0, 22, 3 do
    R(STRAW, x - 12 + i, g - 3 - (i % 2), 2, 1)
  end
  R(IRON_D, x - 10, g - 4, 4, 2)
  if c.state == "locked" and c.alert then
    -- On his feet at the bars, facing the hunter, calling out
    drawPerson(c.id, x - 3 + (c.facing or 1), g - 2, c.facing or 1, "stand")
  elseif c.state == "locked" then
    drawPerson(c.id, x - 5, g - 2, 1, "sit")
  elseif c.state == "open" then
    -- He gets up, then walks out of the door and on
    local walk = math.max(0, c.t - 1.4) * 14
    local fade = math.max(0, math.min(1, (5.2 - c.t) / 1)) -- gone at 5.2 s
    if c.t < 0.5 then
      drawPerson(c.id, x - 5, g - 2, 1, "sit")
    else
      local step = (walk > 0 and math.floor(c.t * 6) % 2 == 0) and 1 or 0
      drawPerson(c.id, x - 4 + math.floor(walk), g - 2 - step, 1, "stand", 0, fade)
    end
  end
  -- the frame: a floor plate, a roof plate with a ring, bars every 3 pixels
  R(IRON_D, x - 13, g - 2, 26, 2)
  R(IRON, x - 13, g - 2, 26, 1)
  R(IRON_D, x - 13, g - 28, 26, 2)
  R(IRON, x - 13, g - 28, 26, 1)
  R(IRON_D, x - 1, g - 31, 3, 3)
  R(IRON_L, x, g - 30, 1, 1)
  for bx = x - 13, x + 1, 3 do
    R(IRON_D, bx, g - 26, 1, 24)
    R(IRON, bx, g - 26, 1, 1)
  end
  R(IRON_D, x + 12, g - 26, 1, 24)
  R(RUST, x - 10, g - 9, 1, 2)
  R(RUST, x - 4, g - 21, 1, 3)
  -- the door: bars from x+2 to x+11, hinged at the right; swinging open it
  -- foreshortens toward the hinge
  local open = c.door or 0
  local squash = math.cos(open * math.pi * 0.45)
  local hinge = x + 11
  for i = 0, 3 do
    local bx = math.floor(hinge - (9 - i * 3) * squash + 0.5)
    R(IRON_D, bx, g - 26, 1, 24)
  end
  local left = math.floor(hinge - 9 * squash + 0.5)
  R(IRON, left, g - 21, hinge - left + 1, 1)
  R(IRON, left, g - 8, hinge - left + 1, 1)
  if c.state == "locked" then
    -- the padlock on the door's edge
    R(IRON_L, x + 2, g - 15, 3, 1)
    R(IRON_L, x + 2, g - 15, 1, 2)
    R(IRON_L, x + 4, g - 15, 1, 2)
    R(BRASS, x + 1, g - 13, 5, 4)
    R({ 0.95, 0.8, 0.4 }, x + 1, g - 13, 5, 1)
    R(EYE, x + 3, g - 12, 1, 2)
  end
  -- a stub of candle someone left on the floor outside
  R({ 0.85, 0.82, 0.7 }, x - 18, g - 4, 2, 4)
end

-- The Gunsmith's stall at camp: an awning over a workbench, a gun rack, an
-- anvil on a stump and a lantern
-- The Prospector's camp under the arch: a bedroll, his iron-bound strongbox,
-- a pick on a rock, a sack of samples and a lantern on a stake
local function drawProspectorCamp(s)
  local x, g = s.x, s.y
  R({ 0.30, 0.22, 0.16 }, x - 26, g - 2, 12, 2) -- bedroll
  R({ 0.46, 0.34, 0.24 }, x - 26, g - 3, 12, 1)
  R({ 0.62, 0.56, 0.46 }, x - 27, g - 4, 3, 2)
  -- the strongbox
  R(WOOD_D, x + 9, g - 8, 12, 8)
  R(WOOD, x + 9, g - 8, 12, 2)
  R(IRON_D, x + 9, g - 6, 12, 1)
  R(IRON_D, x + 11, g - 8, 1, 8)
  R(IRON_D, x + 18, g - 8, 1, 8)
  R(BRASS, x + 14, g - 6, 2, 2)
  -- pick against a rock, a sack
  R({ 0.36, 0.34, 0.36 }, x - 11, g - 4, 6, 4)
  R({ 0.48, 0.46, 0.48 }, x - 11, g - 4, 6, 1)
  R(WOOD_D, x - 9, g - 13, 1, 9)
  R(IRON_L, x - 12, g - 14, 7, 1)
  R(IRON, x - 13, g - 13, 1, 1)
  R({ 0.52, 0.44, 0.30 }, x + 23, g - 6, 5, 6)
  R({ 0.40, 0.33, 0.22 }, x + 24, g - 7, 3, 1)
  -- the lantern on a stake
  R(WOOD_D, x - 18, g - 16, 1, 16)
  R(IRON_D, x - 19, g - 19, 3, 4)
  local near = s.near
  drawProspector(x, g, (near and s.facing) or 1, near and "stand" or "pan", s.hammer)
end

-- The Taxidermist: bald and round-faced behind small round spectacles, a
-- long grey leather apron over green sleeves, a needle in his hand
local T_APRON, T_APRON_D = { 0.55, 0.55, 0.52 }, { 0.38, 0.38, 0.36 }
local T_SLEEVE, T_SLEEVE_D = { 0.32, 0.42, 0.30 }, { 0.22, 0.30, 0.21 }
local T_SKIN = { 0.88, 0.70, 0.58 }

local function drawTaxidermist(x, g, facing, stitching, k)
  love.graphics.push()
  love.graphics.translate(x, g)
  love.graphics.scale(facing, 1)
  local function r(c, dx, dy, w, h)
    R(c, dx, dy, w, h)
  end
  r(BOOT, -3, -2, 3, 2)
  r(BOOT, 1, -2, 3, 2)
  r(TROUSER, -3, -6, 2, 4)
  r(TROUSER, 1, -6, 2, 4)
  r(T_SLEEVE_D, -4, -14, 1, 5)
  r(T_SLEEVE, -3, -14, 6, 6)
  r(T_APRON, -3, -12, 6, 9)
  r(T_APRON_D, -3, -12, 6, 1)
  r(T_APRON_D, 1, -6, 2, 1)
  -- the working arm, stitching a little up and down
  local dy = stitching and math.floor(math.sin(k * math.pi * 2) + 0.5) or 0
  r(T_SLEEVE, 3, -13, 1, 3)
  r(T_SKIN, 4, -10 + dy, 1, 1)
  r(IRON_L, 5, -10 + dy, 2, 1)
  -- the head
  r(T_SKIN, -2, -19, 5, 5)
  r(T_SKIN, -3, -17, 1, 2)
  r({ 0.20, 0.17, 0.15 }, -3, -18, 1, 2) -- fringe over the ear
  r(EYE, 0, -17, 1, 1)
  r(EYE, 2, -17, 1, 1)
  r(GLASS, -1, -18, 2, 2)
  r(GLASS, 1, -18, 2, 2)
  r(EYE, 0, -17, 1, 1)
  r(EYE, 2, -17, 1, 1)
  r(BRASS, 0, -18, 1, 1)
  r(BRASS, -1, -19, 4, 1)
  r(T_SKIN, 0, -15, 3, 1)
  love.graphics.pop()
end

-- A mounted trophy for the wall: a plaque with the kind's head (a simple
-- shape in the kind's colours)
local MOUNT_LOOK = {
  ghoul = { { 0.62, 0.64, 0.66 }, { 0.8, 0.1, 0.1 } },
  bat = { { 0.30, 0.22, 0.34 }, { 0.9, 0.3, 0.3 } },
  spitter = { { 0.55, 0.62, 0.35 }, { 0.6, 1, 0.4 } },
  hopper = { { 0.28, 0.5, 0.34 }, { 0.9, 0.85, 0.3 } },
  bloater = { { 0.55, 0.62, 0.30 }, { 0.85, 1, 0.4 } },
  miner = { { 0.82, 0.80, 0.72 }, { 0.1, 0.1, 0.1 } },
  roller = { { 0.50, 0.44, 0.42 }, { 0.8, 0.8, 0.8 } },
}

local function drawMount(x, y, kind)
  local look = MOUNT_LOOK[kind] or MOUNT_LOOK.ghoul
  R(WOOD_D, x - 4, y - 4, 9, 9) -- the plaque
  R(WOOD, x - 3, y - 3, 7, 7)
  R(look[1], x - 2, y - 2, 5, 5)
  R({ look[1][1] * 0.7, look[1][2] * 0.7, look[1][3] * 0.7 }, x - 2, y + 1, 5, 2)
  R(look[2], x - 1, y - 1, 1, 1)
  R(look[2], x + 1, y - 1, 1, 1)
end

-- The Taxidermist's stall: a back wall of planks with a shelf, a work
-- table with a half-stuffed something, jars, and the mounted trophies above
local function drawTaxidermistStall(s)
  local x, g = s.x, s.y
  if not s.bare then
    R(WOOD_D, x - 22, g - 30, 2, 30)
    R(WOOD_D, x + 20, g - 30, 2, 30)
    for row = 0, 4 do
      R(row % 2 == 0 and WOOD or WOOD_D, x - 20, g - 29 + row * 5, 40, 5)
    end
    R(WOOD_D, x - 24, g - 33, 48, 3)
    R(WOOD, x - 24, g - 33, 48, 1)
  end
  -- the mounts, in a row on the planks (empty nails for what is not yet mounted)
  local meta = require("src.meta")
  for i, kind in ipairs(meta.MOUNT_ORDER) do
    local mx = x - 18 + (i - 1) * 6
    if meta.isMounted(kind) then
      drawMount(mx + 1, g - 24, kind)
    else
      R({ 0.14, 0.12, 0.12 }, mx + 1, g - 24, 1, 1)
    end
  end
  -- table and a stuffed shape on it, jars on a shelf
  R(WOOD_L, x - 18, g - 10, 18, 2)
  R(WOOD_D, x - 17, g - 8, 2, 8)
  R(WOOD_D, x - 3, g - 8, 2, 8)
  R({ 0.55, 0.48, 0.38 }, x - 14, g - 13, 8, 3)
  R({ 0.42, 0.36, 0.28 }, x - 14, g - 11, 8, 1)
  R({ 0.62, 0.55, 0.45 }, x - 7, g - 15, 3, 5)
  R(IRON_L, x - 12, g - 14, 4, 1)
  R(WOOD_D, x + 3, g - 17, 14, 1)
  for i = 0, 2 do
    R({ 0.55, 0.78, 0.62 }, x + 4 + i * 4, g - 21, 3, 4)
    R({ 0.30, 0.45, 0.35 }, x + 4 + i * 4, g - 21, 3, 1)
  end
  local near = s.near
  drawTaxidermist(x + 8, g, (near and s.facing) or -1, not near, s.hammer)
end

local function drawStall(s)
  if people.drawStall(s) then
    return
  elseif s.id == "prospector" then
    return drawProspectorCamp(s)
  elseif s.id == "taxidermist" then
    return drawTaxidermistStall(s)
  end
  local sx, g = s.x - 4, s.y
  -- awning posts and the sloping canvas, with a fringe (a building has its own: s.bare)
  if not s.bare then
    R(WOOD_D, sx - 22, g - 27, 2, 27)
    R(WOOD_D, sx + 21, g - 23, 2, 23)
    for i = 0, 46 do
      local y = g - 28 + math.floor(i * 5 / 46)
      R(CANVAS, sx - 24 + i, y, 1, 3)
      if i % 4 == 0 then
        R(CANVAS_D, sx - 24 + i, y + 3, 1, 1)
      end
    end
  end
  -- long guns leaning on the left post
  R({ 0.22, 0.22, 0.25 }, sx - 20, g - 22, 1, 14)
  R(WOOD, sx - 20, g - 9, 2, 6)
  R({ 0.22, 0.22, 0.25 }, sx - 18, g - 20, 1, 13)
  R(WOOD_L, sx - 18, g - 8, 2, 5)
  -- the workbench, with a vise, a rifle being mended and a box of cartridges
  R(WOOD_L, sx - 16, g - 10, 15, 2)
  R(WOOD_D, sx - 16, g - 8, 15, 1)
  R(WOOD_D, sx - 15, g - 8, 2, 8)
  R(WOOD_D, sx - 4, g - 8, 2, 8)
  R(WOOD_D, sx - 15, g - 4, 13, 1)
  R(IRON, sx - 15, g - 13, 3, 3)
  R(IRON_D, sx - 16, g - 14, 5, 1)
  R({ 0.24, 0.24, 0.28 }, sx - 11, g - 11, 8, 1)
  R(WOOD, sx - 5, g - 12, 4, 2)
  R(BRASS, sx - 13, g - 6, 3, 2)
  -- the anvil on a stump
  R(WOOD_D, sx + 12, g - 6, 6, 6)
  R(WOOD_L, sx + 12, g - 6, 6, 1)
  R(IRON_D, sx + 13, g - 8, 4, 2)
  R(IRON_D, sx + 10, g - 10, 10, 2)
  R(IRON_L, sx + 10, g - 10, 10, 1)
  R(IRON_D, sx + 20, g - 10, 2, 1)
  -- the lantern hangs from the awning (its flame is emissive)
  R(IRON_D, sx + 17, g - 25, 1, 3)
  R(IRON_D, sx + 16, g - 22, 3, 5)
  local near = s.near
  drawGunsmith(s.x, g, (near and s.facing) or 1, near and "stand" or "hammer", s.hammer)
end

-- The bounty board: two posts, a little shingled roof, a plank back with the
-- posters nailed to it (one per bounty on offer; a taken one is stamped)
local function drawBoard(view)
  local bx, g = board.x, board.y
  R(WOOD_D, bx - 14, g - 26, 2, 26)
  R(WOOD_D, bx + 12, g - 26, 2, 26)
  R(WOOD_D, bx - 17, g - 29, 34, 2)
  R(WOOD, bx - 16, g - 30, 32, 1)
  for i = 0, 7 do
    R(WOOD_L, bx - 16 + i * 4, g - 29, 3, 1)
  end
  for row = 0, 3 do
    R(row % 2 == 0 and WOOD or WOOD_D, bx - 12, g - 25 + row * 4, 24, 4)
  end
  R(WOOD_D, bx - 12, g - 9, 24, 1)
  local list = require("src.bounties").list()
  for i = 1, 3 do
    local b = list[i]
    local px = bx - 11 + (i - 1) * 8
    if b then
      local tilt = (i % 2 == 0) and 1 or 0
      R({ 0.86, 0.76, 0.54 }, px, g - 23 + tilt, 6, 9)
      R({ 0.70, 0.58, 0.38 }, px, g - 15 + tilt, 6, 1)
      R({ 0.30, 0.18, 0.08 }, px + 1, g - 22 + tilt, 4, 1) -- WANTED
      R({ 0.45, 0.32, 0.18 }, px + 2, g - 20 + tilt, 2, 3) -- the picture
      R({ 0.30, 0.18, 0.08 }, px + 1, g - 16 + tilt, 4, 1)
      R({ 0.14, 0.12, 0.12 }, px + 3, g - 23 + tilt, 1, 1) -- the nail
      if b.taken then
        R({ 0.75, 0.12, 0.1 }, px + 1, g - 19 + tilt, 4, 1)
        R({ 0.75, 0.12, 0.1 }, px + 2, g - 18 + tilt, 2, 1)
      end
    else
      R({ 0.14, 0.12, 0.12 }, px + 3, g - 23, 1, 1) -- just the nail
    end
  end
end

local function inView(view, x, y, m)
  return x > view.x - m and x < view.x + view.w + m and y > view.y - m and y < view.y + view.h + m
end

function npcs.draw(view, player)
  local bare = require("src.town").stage() >= 2 -- (the town's buildings hold the stalls up)
  for _, s in pairs(camp) do
    s.bare = bare
  end
  if board and meta.boardOpen() and inView(view, board.x, board.y, 40) then
    drawBoard(view)
  end
  for _, c in ipairs(cages) do
    if inView(view, c.x, c.y, 40) then
      drawCage(c)
    end
  end
  for id, s in pairs(camp) do
    if meta.atCamp(id) and inView(view, s.x, s.y, 60) then
      if player then
        local px = player:center()
        s.facing = px < s.x and -1 or 1
      end
      drawStall(s)
    end
  end
end

function npcs.drawEmissive(view)
  local t = love.timer.getTime()
  for _, c in ipairs(cages) do
    if inView(view, c.x, c.y, 40) then
      local fl = 0.75 + 0.25 * math.sin(t * 10 + c.x)
      R({ 1, 0.75, 0.3, fl }, c.x - 18, c.y - 6, 2, 2)
      R({ 1, 0.95, 0.7, fl }, c.x - 18, c.y - 5, 1, 1)
      if c.state == "locked" then
        -- the padlock catches the light, so it can be found and aimed at
        local glint = 0.35 + 0.35 * math.max(0, math.sin(t * 2.2 + c.x))
        R({ 1, 0.85, 0.45, glint }, c.x + 1, c.y - 13, 1, 1)
      end
    end
  end
  for id, s in pairs(camp) do
    if meta.atCamp(id) and inView(view, s.x, s.y, 60) then
      local fl = 0.8 + 0.2 * math.sin(t * 9 + 3)
      people.drawStallGlow(s, t)
      if people.glow(id) then
        local gl = people.glow(id)
        R({ gl[3][1], gl[3][2], gl[3][3], 0.55 + 0.3 * fl }, s.x + gl[1], s.y + gl[2], 2, 2)
      elseif id == "taxidermist" then
        R({ 0.7, 1, 0.8, 0.5 + 0.2 * fl }, s.x + 5, s.y - 20, 1, 1) -- a glint in a jar
      elseif id == "prospector" then
        R({ 1, 0.78, 0.38, fl }, s.x - 18, s.y - 18, 1, 2)
      else
        local sx, g = s.x - 4, s.y
        R({ 1, 0.78, 0.38, fl }, sx + 17, g - 21, 1, 3)
      end
    end
  end
end

function npcs.addLights(lighting, view)
  for _, c in ipairs(cages) do
    if inView(view, c.x, c.y, 120) then
      lighting.add(c.x - 17, c.y - 6, 46, 1, 0.68, 0.32, 0.55 + math.sin(love.timer.getTime() * 9) * 0.04)
    end
  end
  for id, s in pairs(camp) do
    if meta.atCamp(id) and inView(view, s.x, s.y, 120) then
      people.addStallLights(s, lighting)
      if people.glow(id) then
        local gl = people.glow(id)
        lighting.add(s.x + gl[1], s.y + gl[2], 60, gl[3][1], gl[3][2], gl[3][3], 0.5)
      elseif id == "taxidermist" then
        lighting.add(s.x + 6, s.y - 20, 60, 0.75, 0.95, 0.8, 0.45)
      else
        lighting.add(id == "prospector" and s.x - 18 or s.x + 13, s.y - 18, 70, 1, 0.68, 0.34, 0.6)
      end
    end
  end
end

-- A speech bubble over (sx, sy) on screen
local placed = {} -- the bubbles already drawn this frame (they never overlap)

local function bubble(font, text, sx, sy, age)
  local life = 3.2
  if age > life then
    return
  end
  local a = math.min(1, age / 0.15) * math.min(1, (life - age) / 0.4)
  love.graphics.setFont(font)
  local w, h = font:getWidth(text), font:getHeight()
  local pad = math.max(3, math.floor(h * 0.3))
  local bw, bh = w + pad * 2, h + pad * 2
  local x, y = math.floor(sx - w / 2 - pad), math.floor(sy - h - pad * 2 - 6)
  -- Another bubble in the way: this one goes above it
  local moved = false
  local again = true
  while again do
    again = false
    for _, r in ipairs(placed) do
      if x < r.x + r.w + 2 and x + bw > r.x - 2 and y < r.y + r.h + 2 and y + bh > r.y - 2 then
        y = r.y - bh - 3
        moved = true
        again = true
      end
    end
  end
  placed[#placed + 1] = { x = x, y = y, w = bw, h = bh }
  love.graphics.setColor(0.93, 0.89, 0.8, 0.92 * a)
  love.graphics.rectangle("fill", x, y, w + pad * 2, h + pad * 2, pad, pad)
  if not moved then
    love.graphics.polygon("fill", sx - 4, y + h + pad * 2, sx + 4, y + h + pad * 2, sx, y + h + pad * 2 + 6)
  end
  love.graphics.setColor(0.18, 0.12, 0.08, a)
  love.graphics.print(text, x + pad, y + pad)
end

npcs.bubble = bubble

function npcs.drawScreen(toScreen, font, player)
  placed = {} -- (a new frame: events.drawScreen draws its bubbles after this)
  if require("src.menu").isOpen() then
    return -- (no speech showing through a menu or the death recap)
  end
  for _, c in ipairs(cages) do
    if c.say then
      local dx = c.state == "open" and math.max(0, c.t - 1.4) * 14 or 0
      local sx, sy = toScreen(c.x - 4 + dx, c.y - 32)
      bubble(font, c.say.text, sx, sy, c.say.age)
    end
  end
  for id, s in pairs(camp) do
    if meta.atCamp(id) and s.say then
      local sx, sy = toScreen(s.x, s.y - 30)
      bubble(font, s.say.text, sx, sy, s.say.age)
    end
  end
  if player and not player.dead and nearBoard(player) then
    local text = "[" .. input.label("interact") .. "] Read the bounty board"
    local sx, sy = toScreen(board.x, board.y + 4)
    love.graphics.setFont(font)
    local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy)
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.print(text, x + 2, y + 2)
    love.graphics.setColor(1, 0.88, 0.6)
    love.graphics.print(text, x, y)
  end
  if player and not player.dead then
    local s = nearestCamp(player)
    if s then
      local name = meta.PEOPLE[s.id] and meta.PEOPLE[s.id].name or s.id
      local text = "[" .. input.label("interact") .. "] Talk to " .. name:gsub("^The ", "the ")
      local sx, sy = toScreen(s.x, s.y + 4)
      love.graphics.setFont(font)
      local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy)
      love.graphics.setColor(0, 0, 0, 0.85)
      love.graphics.print(text, x + 2, y + 2)
      love.graphics.setColor(1, 0.88, 0.6)
      love.graphics.print(text, x, y)
    end
  end
end

return npcs
