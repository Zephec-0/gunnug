-- The sky's boss: the Champion of the Heavens, the god's own warden of the stars. He floats in the middle of the
-- Citadel of Stars (the oval hall in the Cloud Reaches, see src.cavegen) and fights in three turns:
--
--   1  The Clock Turns       a hand of light sweeps round him like the hand of a clock; star bolts fan out
--   2  The Heavens Bend      two hands, and gravity wells that bend every shot (and the hunter) toward them
--   3  The Stars Align       he can't be hurt; three stars wake round the hall and light in an order that
--                            must be shot back in the same order, longer each of three rounds. A wrong star
--                            sends the order round again, and every round done is a blow to him.
--
-- Beating him changes the world a little (the sun in the overworld sky is eclipsed, see src.scenes.overworld,
-- and the epic items join the pool, see src.meta.skyBeaten).
local enemies = require("src.enemies")
local audio = require("src.audio")
local effects = require("src.effects")

local H = enemies.helpers
local center = H.center

local function hypot(x, y)
  return math.sqrt(x * x + y * y)
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

-- Tuning
local T = {
  intro = 2.2, -- he wakes
  trans = 2.2, -- between turns, untouchable
  hand = { 0.50, 0.62, 0.42 }, -- the hand's turn, radians a second, by turn
  handLen = 560,
  handDamage = 18,
  boltDamage = 8,
  boltSpeed = 150,
  boltEvery = { 2.6, 3.4, 4.0 },
  wellEvery = 5.5,
  wellLife = 8.5,
  wellR = 130,
  wellDamage = 10,
  nodeHit = 13, -- how near a shot must be to a star to count
  show = 0.85, -- seconds each star stays lit when the order is shown
  rounds = { 3, 4, 5 }, -- stars in the order, by round
  inputTime = 9,
}

local def = {
  name = "The Champion of the Heavens",
  boss = true, anchored = true, alwaysActive = true,
  w = 24, h = 40, hp = 420, speed = 60,
  sight = 1400, forget = 6000,
  knockback = 0, knockMul = 0, gold = { 420, 520 }, weight = 60,
  spriteW = 24, spriteH = 40, scale = 1,
  blood = { 1.0, 0.95, 0.7 },
  desc = "The gods' own champion, sent to answer anyone who climbs this high. A hand of light turns round him like a clock's; the heavens bend around him; and when he is hurt enough the stars themselves take his part, and must be shot in the order they light.",
}
-- (no def.damage: touching him doesn't hurt; his hand and his bolts do)
enemies.defs.starwarden = def
enemies.order[#enemies.order + 1] = "starwarden"

enemies.wells = {} -- gravity wells in the hall: { x, y, r, life, max } (src.bullets bends shots toward them)
local bolts = {} -- star bolts: { x, y, vx, vy, life, dmg }
local rings = {} -- a spent hand's afterglow, for the look only

-- The boss's own state ----------------------------------------------------------------------------------

local function ensure(e)
  if e.sw then
    return e.sw
  end
  local a = e.arena
  local cx, cy = center(e)
  local sw = {
    t = 0,
    intro = T.intro,
    ph = 1,
    pending = nil,
    trans = 0,
    home = { a and a.cx or cx, a and (a.top + math.floor(a.h * 0.36)) or cy },
    handA = -math.pi / 2,
    handDir = 1,
    handT = 0, -- charge: the hand is only live once it has risen
    flipT = 7,
    boltT = 2,
    wellT = 3,
    hitCd = 0,
    nodes = nil,
    round = 0,
  }
  e.sw = sw
  e.ph = 1
  e.bossName = def.name
  return sw
end

-- The three stars of the last turn, on an ellipse round the boss
local function nodePositions(sw, a)
  local w = a and a.w or 500
  local out = {}
  for i, off in ipairs({ { -0.34, 50 }, { 0.34, 50 }, { 0, 135 } }) do
    out[i] = { x = sw.home[1] + off[1] * w, y = sw.home[2] + off[2], lit = 0, solved = 0 }
  end
  return out
end

local function newSequence(sw, n)
  local seq = {}
  local last
  for i = 1, n do
    local k
    repeat
      k = love.math.random(3)
    until k ~= last
    seq[i] = k
    last = k
  end
  sw.seq, sw.stage, sw.stageT, sw.inputI = seq, "show", 0, 1
  for _, nd in ipairs(sw.nodes) do
    nd.lit, nd.solved = 0, 0
  end
end

local function startTurn(e, sw, ph)
  sw.ph, e.ph = ph, ph
  sw.handT = 0
  sw.boltT = 2.2
  sw.wellT = 3
  if ph == 3 then
    sw.nodes = nodePositions(sw, e.arena)
    sw.round = 1
    sw.p3hp = e.hp
    newSequence(sw, T.rounds[1])
    sw.stageT = -1 -- a breath before the first star lights
  end
  local names = {
    { "The Heavens Bend", "Gravity wells open. Shots curve toward them, and so do you" },
    { "The Stars Align", "He cannot be hurt. Shoot the stars in the order they light" },
  }
  local n = names[ph - 1]
  if n then
    require("src.hud").showBanner(n[1], n[2])
  end
end

-- What a hit does ------------------------------------------------------------------------------------------

local function nodeAt(sw, x, y)
  if not sw.nodes then
    return nil
  end
  for i, nd in ipairs(sw.nodes) do
    if (x - nd.x) ^ 2 + (y - nd.y) ^ 2 <= T.nodeHit ^ 2 then
      return i
    end
  end
  return nil
end

local function shake(k)
  require("src.camera").shake(k)
end

-- A star shot in the last turn: right, or wrong
local function shootNode(e, sw, i)
  local nd = sw.nodes[i]
  if sw.stage ~= "input" then
    return
  end
  if sw.seq[sw.inputI] == i then
    sw.inputI = sw.inputI + 1
    nd.solved = 1
    audio.playAt("count_beep", nd.x, nd.y, 0.9, 1 + 0.12 * sw.inputI)
    effects.ring(nd.x, nd.y, 22, { 1, 0.95, 0.6 })
    if sw.inputI > #sw.seq then
      -- The order is whole: he takes a blow, and the next round is longer
      sw.stage, sw.stageT = "struck", 0
      local chunk = sw.round >= #T.rounds and e.hp or math.ceil(sw.p3hp / #T.rounds)
      sw.finishing = true
      enemies.damage(e, chunk, 0, 0, 0, false, nil)
      sw.finishing = false
      audio.playAt("explosion", e.body.x, e.body.y, 0.7, 1.3)
      shake(0.5)
      local cx, cy = center(e)
      effects.ring(cx, cy, 60, { 1, 0.95, 0.6 })
    end
  else
    -- Out of order: they all go dark and the order shows again, and the heavens answer
    audio.playAt("clank", nd.x, nd.y, 0.9, 0.5)
    effects.ring(nd.x, nd.y, 26, { 1, 0.2, 0.2 })
    sw.stage, sw.stageT, sw.inputI = "show", 0, 1
    for _, o in ipairs(sw.nodes) do
      o.solved = 0
    end
    local cx, cy = center(e)
    for k = 0, 7 do
      local ang = k / 8 * math.pi * 2 + sw.t
      bolts[#bolts + 1] = { x = cx, y = cy, vx = math.cos(ang) * T.boltSpeed, vy = math.sin(ang) * T.boltSpeed, life = 4.5, dmg = math.max(1, math.floor(T.boltDamage * e.dmgMul + 0.5)) }
    end
  end
end

def.extraHit = function(e, x, y)
  local sw = e.sw
  return sw ~= nil and sw.ph == 3 and sw.stage == "input" and nodeAt(sw, x, y) ~= nil
end

def.filter = function(e, amount)
  local sw = ensure(e)
  if sw.finishing then
    return amount
  end
  if sw.intro > 0 or sw.trans > 0 or sw.pending then
    return 0
  end
  local ax, ay = center(e)
  if sw.ph == 3 then
    local i = e.hitX and nodeAt(sw, e.hitX, e.hitY)
    if i then
      shootNode(e, sw, i)
    else
      -- (the stars take his part: nothing touches him)
      audio.playAt("clank", ax, ay, 0.4, 1.6)
      effects.particle(ax, ay, (love.math.random() - 0.5) * 120, -love.math.random() * 80, 0.25, { 1, 0.95, 0.7 }, 200, true)
    end
    return 0
  end
  -- The blow that would cross into the next turn stops at it
  local line = sw.ph == 1 and 0.66 or 0.33
  local floorHp = math.ceil(e.maxHp * line)
  if e.hp - amount <= floorHp then
    e.hp = floorHp
    sw.pending = sw.ph + 1
    audio.playAt("dh_voice", ax, ay, 1, 0.55)
    return 0
  end
  return amount
end

def.light = function(e)
  local cx, cy = center(e)
  local l = { { cx, cy - 4, 120, 0.95, 0.9, 0.7, 0.6 } }
  local sw = e.sw
  if sw and sw.nodes then
    for _, nd in ipairs(sw.nodes) do
      local k = math.max(nd.lit, nd.solved)
      if k > 0.05 then
        l[#l + 1] = { nd.x, nd.y, 70, 1, 0.95, 0.65, 0.7 * k }
      end
    end
  end
  return l
end

-- The hand ----------------------------------------------------------------------------------------------

-- Where a beam from (x, y) along angle ang ends: the first rock, or its full length
local function beamEnd(world, x, y, ang)
  local dx, dy = math.cos(ang), math.sin(ang)
  for s = 0, T.handLen, 3 do
    local bx, by = x + dx * s, y + dy * s
    if world:isSolid(bx, by) then
      return bx, by
    end
  end
  return x + dx * T.handLen, y + dy * T.handLen
end

local function segmentDist(px, py, x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local l2 = dx * dx + dy * dy
  local t = l2 > 0 and math.max(0, math.min(1, ((px - x0) * dx + (py - y0) * dy) / l2)) or 0
  return hypot(px - (x0 + dx * t), py - (y0 + dy * t))
end

local function hands(sw)
  local out = { sw.handA }
  if sw.ph == 2 then
    out[2] = sw.handA + math.pi
  end
  return out
end

-- Update ------------------------------------------------------------------------------------------------

local function fireBolts(e, sw, px, py)
  local cx, cy = center(e)
  local dmg = math.max(1, math.floor(T.boltDamage * e.dmgMul + 0.5))
  if sw.ph == 1 then
    local aim = math.atan2(py - cy, px - cx)
    for k = -2, 2 do
      local ang = aim + k * 0.2
      bolts[#bolts + 1] = { x = cx, y = cy, vx = math.cos(ang) * T.boltSpeed, vy = math.sin(ang) * T.boltSpeed, life = 5, dmg = dmg }
    end
  elseif sw.ph == 2 then
    for k = 0, 9 do
      local ang = k / 10 * math.pi * 2 + sw.t * 0.3
      bolts[#bolts + 1] = { x = cx, y = cy, vx = math.cos(ang) * T.boltSpeed * 0.9, vy = math.sin(ang) * T.boltSpeed * 0.9, life = 5, dmg = dmg }
    end
  else
    local aim = math.atan2(py - cy, px - cx)
    for k = -1, 1 do
      local ang = aim + k * 0.25
      bolts[#bolts + 1] = { x = cx, y = cy, vx = math.cos(ang) * T.boltSpeed, vy = math.sin(ang) * T.boltSpeed, life = 5, dmg = dmg }
    end
  end
  audio.playAt("bat_screech", cx, cy, 0.5, 1.9)
end

local function updateNodes(e, sw, dt)
  for _, nd in ipairs(sw.nodes) do
    nd.lit = math.max(0, nd.lit - dt * 3)
  end
  sw.stageT = sw.stageT + dt
  if sw.stage == "show" then
    local i = math.floor(sw.stageT / T.show) + 1
    if sw.stageT >= 0 and i <= #sw.seq then
      local nd = sw.nodes[sw.seq[i]]
      local phase = sw.stageT - (i - 1) * T.show
      if phase < 0.5 then
        if nd.lit < 1 and (sw.shown or 0) ~= i then
          sw.shown = i
          audio.playAt("count_beep", nd.x, nd.y, 0.8, 0.9 + 0.12 * sw.seq[i])
        end
        nd.lit = 1
      end
    elseif sw.stageT > #sw.seq * T.show + 0.4 then
      sw.stage, sw.stageT, sw.inputI, sw.shown = "input", 0, 1, nil
    end
  elseif sw.stage == "input" then
    if sw.stageT > T.inputTime + #sw.seq * 1.5 then
      sw.stage, sw.stageT, sw.inputI = "show", 0, 1
      for _, nd in ipairs(sw.nodes) do
        nd.solved = 0
      end
    end
  elseif sw.stage == "struck" then
    if sw.stageT > 2 and not e.dead then
      sw.round = sw.round + 1
      newSequence(sw, T.rounds[math.min(sw.round, #T.rounds)])
    end
  end
end

local function updateStar(e, dt, world, player, px, py)
  local sw = ensure(e)
  local b = e.body
  local cx, cy = center(e)
  sw.t = sw.t + dt
  e.state, e.seesPlayer = "chase", true
  audio.setBoss(true)
  -- Hovering over the middle of the hall, drifting a little
  local tx = sw.home[1] + math.sin(sw.t * 0.45) * (sw.ph == 3 and 0 or 90)
  local ty = sw.home[2] + math.sin(sw.t * 0.8) * (sw.ph == 3 and 4 or 26)
  b.vx = b.vx + ((tx - cx) * 3 - b.vx * 2.4) * dt
  b.vy = b.vy + ((ty - cy) * 3 - b.vy * 2.4) * dt
  b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
  if sw.intro > 0 then
    sw.intro = sw.intro - dt
    return
  end
  -- Between turns: he rears back, everything hangs
  if sw.pending and sw.trans <= 0 then
    sw.trans = T.trans
    audio.playAt("explosion", cx, cy, 1, 0.5)
    shake(0.6)
    effects.ring(cx, cy, 90, { 1, 0.95, 0.7 })
    for i = #bolts, 1, -1 do
      bolts[i] = nil
    end
    for i = #enemies.wells, 1, -1 do
      enemies.wells[i] = nil
    end
  end
  if sw.trans > 0 then
    sw.trans = sw.trans - dt
    if sw.trans <= 0 and sw.pending then
      startTurn(e, sw, sw.pending)
      sw.pending = nil
    end
    return
  end
  -- The hand: it rises over a second, turns, and now and then reverses (after a pause)
  sw.handT = math.min(1, sw.handT + dt / 1.1)
  sw.flipT = sw.flipT - dt
  if sw.flipT <= 0 then
    sw.flipT = 6 + love.math.random() * 4
    sw.handDir = -sw.handDir
    sw.handT = 0.0
  end
  sw.handA = sw.handA + sw.handDir * T.hand[sw.ph] * dt * (0.4 + 0.6 * sw.handT)
  if sw.handT >= 1 and not player.dead then
    local pcx, pcy = player:center()
    for _, ang in ipairs(hands(sw)) do
      local ex, ey = beamEnd(world, cx, cy, ang)
      if segmentDist(pcx, pcy, cx, cy, ex, ey) < 5 then
        if player:hurt(math.max(1, math.floor(T.handDamage * e.dmgMul + 0.5)), cx, cy, "starwarden") then
          player.lastEnemy = e
        end
      end
    end
  end
  -- Bolts
  sw.boltT = sw.boltT - dt
  if sw.boltT <= 0 then
    sw.boltT = T.boltEvery[sw.ph]
    fireBolts(e, sw, px, py)
  end
  -- Gravity wells
  if sw.ph == 2 then
    sw.wellT = sw.wellT - dt
    if sw.wellT <= 0 and #enemies.wells < 2 then
      sw.wellT = T.wellEvery
      local a = e.arena
      for _ = 1, 20 do
        local wx = sw.home[1] + (love.math.random() * 2 - 1) * (a and a.w * 0.34 or 150)
        local wy = sw.home[2] + (love.math.random() * 2 - 1) * (a and a.h * 0.22 or 80) + 60
        if hypot(wx - px, wy - py) > 90 and not world:isSolid(wx, wy) then
          enemies.wells[#enemies.wells + 1] = { x = wx, y = wy, r = T.wellR, life = T.wellLife, max = T.wellLife }
          audio.playAt("explosion", wx, wy, 0.5, 0.4)
          break
        end
      end
    end
  end
  if sw.ph == 3 then
    updateNodes(e, sw, dt)
  end
end

-- Draw --------------------------------------------------------------------------------------------------

local function R(c, a, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

local ARMOR, ARMOR_L, ARMOR_D = { 0.90, 0.86, 0.72 }, { 1.0, 0.98, 0.88 }, { 0.58, 0.52, 0.44 }
local GOLD, GOLD_D = { 0.98, 0.80, 0.34 }, { 0.62, 0.46, 0.16 }
local CAPE, CAPE_L = { 0.16, 0.20, 0.46 }, { 0.38, 0.46, 0.80 }

local function drawStar(e)
  local sw = e.sw
  local cx, cy = center(e)
  local t = love.timer.getTime()
  cx, cy = math.floor(cx), math.floor(cy) + math.floor(math.sin(t * 1.3) * 1.5 + 0.5)
  -- A cape of night, with stars in it, trailing under him
  for i = 0, 22 do
    local w = 6 + i * 0.5 + math.sin(t * 2 + i * 0.4) * (i * 0.08)
    local c = i % 6 == 0 and CAPE_L or CAPE
    R(c, 0.92 - i * 0.015, cx - w, cy - 4 + i, w * 2, 1)
  end
  -- Arms held a little out, and the torso in layered plate
  R(ARMOR_D, 1, cx - 12, cy - 8, 4, 14)
  R(ARMOR, 1, cx - 12, cy - 8, 3, 14)
  R(ARMOR_D, 1, cx + 8, cy - 8, 4, 14)
  R(ARMOR, 1, cx + 8, cy - 8, 3, 14)
  R(GOLD, 1, cx - 12, cy + 5, 4, 2)
  R(GOLD, 1, cx + 8, cy + 5, 4, 2)
  R(ARMOR_D, 1, cx - 7, cy - 9, 14, 17)
  R(ARMOR, 1, cx - 7, cy - 9, 12, 16)
  R(ARMOR_L, 1, cx - 7, cy - 9, 12, 2)
  R(GOLD, 1, cx - 7, cy + 3, 14, 2)
  R(GOLD_D, 1, cx - 7, cy + 5, 14, 1)
  R({ 0.55, 0.8, 1 }, 1, cx - 1, cy - 4, 3, 3)
  -- The head: a high helm with a crest, a dark visor, and the halo behind it
  R(ARMOR_D, 1, cx - 5, cy - 19, 10, 11)
  R(ARMOR, 1, cx - 5, cy - 19, 9, 10)
  R(ARMOR_L, 1, cx - 5, cy - 19, 9, 1)
  R(GOLD, 1, cx - 1, cy - 25, 3, 7)
  R(GOLD, 1, cx - 3, cy - 22, 7, 2)
  R({ 0.06, 0.05, 0.1 }, 1, cx - 4, cy - 14, 8, 2)
  if e.flash > 0 then
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.rectangle("fill", e.body.x, e.body.y, e.body.w, e.body.h)
  end
end

local function drawStarGlow(e)
  local sw = e.sw
  local cx, cy = center(e)
  local t = love.timer.getTime()
  love.graphics.setBlendMode("add")
  -- The halo: a ring with twelve ticks like a clock's, turning
  local hy = cy - 14
  local pulse = 0.8 + 0.2 * math.sin(t * 2)
  love.graphics.setColor(1, 0.85, 0.4, 0.5 * pulse)
  love.graphics.setLineWidth(1)
  love.graphics.circle("line", cx, hy, 18)
  love.graphics.circle("line", cx, hy, 20)
  for k = 0, 11 do
    local ang = k / 12 * math.pi * 2 + t * 0.3
    local r0, r1 = 20, k % 3 == 0 and 26 or 23
    love.graphics.setColor(1, 0.92, 0.55, 0.75 * pulse)
    love.graphics.line(cx + math.cos(ang) * r0, hy + math.sin(ang) * r0, cx + math.cos(ang) * r1, hy + math.sin(ang) * r1)
  end
  love.graphics.setColor(1, 0.9, 0.5, 0.12 * pulse)
  love.graphics.circle("fill", cx, hy, 30)
  love.graphics.setColor(1, 0.85, 0.5, 0.06)
  love.graphics.circle("fill", cx, cy, 70)
  -- The eyes in the visor
  love.graphics.setColor(0.7, 0.9, 1, 1)
  love.graphics.rectangle("fill", cx - 3, cy - 14, 2, 1)
  love.graphics.rectangle("fill", cx + 1, cy - 14, 2, 1)
  love.graphics.setColor(0.5, 0.8, 1, 0.35)
  love.graphics.circle("fill", cx, cy - 13, 5)
  if not sw then
    love.graphics.setBlendMode("alpha")
    return
  end
  -- The hand(s) of light: thin and pale while it rises, then bright and live
  local w = e.state and e.arena and e.arena or nil
  local world = e.world
  if sw.intro <= 0 and sw.trans <= 0 and not sw.pending then
    local lw = sw.handT
    for _, ang in ipairs(hands(sw)) do
      local ex, ey
      if e.beamWorld then
        ex, ey = beamEnd(e.beamWorld, cx, cy, ang)
      else
        ex, ey = cx + math.cos(ang) * T.handLen, cy + math.sin(ang) * T.handLen
      end
      love.graphics.setLineWidth(1 + 5 * lw * lw)
      love.graphics.setColor(1, 0.7, 0.25, 0.28 + 0.25 * lw)
      love.graphics.line(cx, cy, ex, ey)
      love.graphics.setLineWidth(1 + 1.5 * lw)
      love.graphics.setColor(1, 0.97, 0.8, 0.5 + 0.5 * lw)
      love.graphics.line(cx, cy, ex, ey)
      love.graphics.setColor(1, 0.9, 0.5, 0.35 * lw)
      love.graphics.circle("fill", ex, ey, 4 + 3 * lw)
    end
    love.graphics.setLineWidth(1)
  end
  -- The stars of the last turn, and the lines between those already struck
  if sw.nodes then
    local solved = {}
    for i, nd in ipairs(sw.nodes) do
      if nd.solved > 0 then
        solved[#solved + 1] = nd
      end
    end
    love.graphics.setColor(1, 0.95, 0.65, 0.5)
    for i = 1, #solved - 1 do
      love.graphics.line(solved[i].x, solved[i].y, solved[i + 1].x, solved[i + 1].y)
    end
    for i, nd in ipairs(sw.nodes) do
      local k = math.max(nd.lit, nd.solved, 0.22 + 0.06 * math.sin(t * 3 + i))
      love.graphics.setColor(1, 0.95, 0.65, 0.18 * k)
      love.graphics.circle("fill", nd.x, nd.y, 22)
      love.graphics.setColor(1, 0.97, 0.8, 0.35 + 0.65 * k)
      love.graphics.rectangle("fill", math.floor(nd.x) - 1, math.floor(nd.y) - 6, 3, 13)
      love.graphics.rectangle("fill", math.floor(nd.x) - 6, math.floor(nd.y) - 1, 13, 3)
      love.graphics.setColor(1, 1, 1, 0.5 + 0.5 * k)
      love.graphics.circle("fill", nd.x, nd.y, 2 + 2 * k)
    end
    -- (what the hunter has still to do: the next star waits with a faint ring)
    if sw.stage == "input" and sw.seq[sw.inputI] then
      local nd = sw.nodes[sw.seq[sw.inputI]]
      love.graphics.setColor(1, 0.9, 0.5, 0.0)
    end
  end
  love.graphics.setBlendMode("alpha")
end

-- Bolts, wells and the like, every frame ---------------------------------------------------------------------

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  for _, e in ipairs(enemies.all()) do
    if e.kind == "starwarden" then
      e.beamWorld = world
    end
  end
  if #bolts == 0 and #enemies.wells == 0 then
    return
  end
  local pb = player.body
  for i = #bolts, 1, -1 do
    local s = bolts[i]
    s.life = s.life - dt
    local gone = s.life <= 0
    if not gone then
      s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
      if world:isSolid(s.x, s.y) then
        effects.particle(s.x, s.y, -s.vx * 0.1, -s.vy * 0.1, 0.25, { 1, 0.9, 0.5 }, 200, true)
        gone = true
      elseif not player.dead and overlaps(s.x - 2, s.y - 2, 4, 4, pb.x, pb.y, pb.w, pb.h) then
        player:hurt(s.dmg, s.x - s.vx * 0.05, s.y - s.vy * 0.05, "starwarden")
        gone = true
      end
    end
    if gone then
      table.remove(bolts, i)
    end
  end
  local px2, py2 = player:center()
  for i = #enemies.wells, 1, -1 do
    local wl = enemies.wells[i]
    wl.life = wl.life - dt
    if wl.life <= 0 then
      table.remove(enemies.wells, i)
    elseif not player.dead then
      -- The hunter is drawn in, too (softer than the shots), and hurt at the core
      local dx, dy = wl.x - px2, wl.y - py2
      local d = hypot(dx, dy)
      if d < wl.r and d > 1 then
        local pull = (1 - d / wl.r) ^ 1.3 * 230
        pb.vx = pb.vx + dx / d * pull * dt
        pb.vy = pb.vy + dy / d * pull * dt * 0.5
      end
      if d < 11 then
        wl.hurtT = (wl.hurtT or 0) - dt
        if wl.hurtT <= 0 then
          wl.hurtT = 0.5
          player:hurt(T.wellDamage, wl.x, wl.y, "starwarden")
        end
      end
    end
  end
end

local prevEmissive = enemies.afterEmissive
enemies.afterEmissive = function(view)
  if prevEmissive then
    prevEmissive(view)
  end
  local t = love.timer.getTime()
  for _, wl in ipairs(enemies.wells) do
    local k = math.min(1, wl.life / 1.2, (wl.max - wl.life) / 0.8 + 0.1)
    -- a black heart, a violet rim, and rings falling in
    love.graphics.setColor(0.02, 0.01, 0.05, 0.95 * k)
    love.graphics.circle("fill", wl.x, wl.y, 9 * k)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(0.6, 0.35, 1, 0.55 * k)
    love.graphics.circle("line", wl.x, wl.y, 10 * k)
    for r = 0, 2 do
      local f = ((t * 0.6 + r / 3) % 1)
      love.graphics.setColor(0.55, 0.4, 1, 0.3 * (1 - f) * k)
      love.graphics.circle("line", wl.x, wl.y, wl.r * (1 - f))
    end
    love.graphics.setColor(0.5, 0.3, 0.9, 0.12 * k)
    love.graphics.circle("fill", wl.x, wl.y, 26)
    love.graphics.setBlendMode("alpha")
  end
  love.graphics.setBlendMode("add")
  for _, s in ipairs(bolts) do
    local d = math.max(1, hypot(s.vx, s.vy))
    love.graphics.setColor(1, 0.85, 0.4, 0.5)
    love.graphics.line(s.x - s.vx / d * 7, s.y - s.vy / d * 7, s.x, s.y)
    love.graphics.setColor(1, 0.97, 0.8, 1)
    love.graphics.circle("fill", s.x, s.y, 2)
    love.graphics.setColor(1, 0.8, 0.3, 0.25)
    love.graphics.circle("fill", s.x, s.y, 5)
  end
  love.graphics.setBlendMode("alpha")
end

-- A new fight, or none: nothing of his left flying
local prevClear = enemies.clear
enemies.clear = function()
  prevClear()
  bolts, rings = {}, {}
  for i = #enemies.wells, 1, -1 do
    enemies.wells[i] = nil
  end
end

def.onDeath = function(e)
  for i = #bolts, 1, -1 do
    bolts[i] = nil
  end
  for i = #enemies.wells, 1, -1 do
    enemies.wells[i] = nil
  end
  local cx, cy = center(e)
  for k = 1, 5 do
    effects.ring(cx, cy, 30 + k * 26, { 1, 0.95, 0.65 })
  end
  audio.playAt("explosion", cx, cy, 1, 0.4)
  shake(1.0)
  audio.setBoss(false)
end

enemies.UPDATE.starwarden = updateStar
enemies.DRAW.starwarden = drawStar
enemies.GLOW.starwarden = drawStarGlow

return true
