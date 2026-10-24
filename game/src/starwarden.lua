-- The sky's boss: the Champion of the Heavens, the god's own warden of the stars. A golden figure with a halo, a core
-- like a sun, a lance for a body and arms of cloud, ringed by orbs. He fights over the open disc of the Citadel
-- (src.cavegen, src.skygen) in four turns, and each turn goes the same way:
--
--   the gate      he cannot be hurt. Stars wake round the hall and light in an order that must be shot back in the
--                 same order (more stars each turn: 3, 4, 5, 5; a longer order each time too). He goes on attacking.
--   the window    the gate breaks and he can be hurt like anything else, until the turn's share of his health is gone
--   the interlude he slips out of the world, faint and untouchable, grows and burns brighter, and his own servants
--                 (src.starmobs) fight in his stead; when they are dead he comes back changed
--
--   1  Ascension          a hand of light sweeps round him like a clock's; star bolts fan out; now and then he swoops
--   2  The Divine Orbs    two hands, gravity wells that bend every shot (and the hunter), orbs that break from his
--                         ring and chase, and Star Guardians: while one burns he cannot be hurt
--   3  The Celestial Rays he blinks about the sky and pillars of light fall where you stand (combs, sweeps)
--   4  The Sun            all of it, from a sun's body. When he falls he does not fall: he collapses, a star dying,
--                         and leaves a black hole that bends the light, and the sky behind it changes
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

local function lerp(a, b, t)
  return a + (b - a) * t
end

-- Tuning
local T = {
  intro = 2.4, -- he wakes
  hand = { 0.80, 0.95, 0.70, 0.62 }, -- the hand's turn, radians a second, by turn
  handLen = 560,
  handDamage = 18,
  boltDamage = 8,
  boltSpeed = 150,
  boltEvery = { 2.6, 3.4, 4.2, 3.4 },
  wellEvery = 5.5,
  wellLife = 8.5,
  wellR = 130,
  wellDamage = 10,
  orbDamage = 12,
  orbSpeed = 175,
  orbEvery = { 99, 5.2, 6.0, 5.0 },
  rayEvery = { 99, 99, 4.4, 5.6 },
  rayDamage = 22,
  swoopEvery = { 12, 9, 99, 99 },
  swoopDamage = 16,
  blinkEvery = 8,
  nodeHit = 15, -- how near a shot must be to a star to count
  show = 0.8, -- seconds each star stays lit when the order is shown
  stars = { 3, 4, 5, 5 }, -- stars in the gate, by turn
  order = { 3, 4, 5, 6 }, -- how long the order is, by turn
  inputTime = 11,
  size = { 1.0, 1.25, 1.5, 1.8 }, -- how big he is, by turn
  lines = { 0.75, 0.5, 0.25 }, -- the health at which each turn ends
  dying = 9.5, -- the length of his death
}

local def = {
  name = "The Champion of the Heavens",
  boss = true, anchored = true, alwaysActive = true,
  w = 30, h = 52, hp = 480, speed = 60,
  sight = 1400, forget = 6000,
  knockback = 0, knockMul = 0, gold = { 420, 520 }, weight = 60,
  spriteW = 60, spriteH = 90, scale = 1,
  blood = { 1.0, 0.95, 0.7 },
  desc = "The gods' own champion, sent to answer anyone who climbs this high: a golden figure with a sun for a heart, a halo, a lance for a body and arms of cloud. A hand of light turns round him like a clock's; his orbs break away to hunt you; pillars of light fall where you stand; the heavens bend around him. He cannot be hurt until the stars he wakes are shot in the order they light. Each time he is hurt enough he slips away, burns brighter and sends his servants, and in the end he is a sun. When a sun dies it leaves something behind.",
}
-- (no def.damage: touching him doesn't hurt; his hand, his swoop, his orbs, rays and bolts do)
enemies.defs.starwarden = def
enemies.order[#enemies.order + 1] = "starwarden"

enemies.wells = {} -- gravity wells in the hall: { x, y, r, life, max } (src.bullets bends shots toward them)
local bolts = {} -- star bolts and orbs: { x, y, vx, vy, life, dmg, orb, home }
local rays = {} -- pillars of light: { x, age, warn, life, w, hit }
local hole -- the black hole he leaves: { x, y, t }

-- The colours and shapes of the gate's stars: each its own, so they can be told apart at a glance
local STAR = {
  { c = { 1.0, 0.85, 0.35 }, shape = "circle", note = 0.75 },
  { c = { 0.45, 0.75, 1.0 }, shape = "diamond", note = 0.9 },
  { c = { 1.0, 0.5, 0.7 }, shape = "triangle", note = 1.07 },
  { c = { 0.5, 1.0, 0.65 }, shape = "square", note = 1.25 },
  { c = { 0.8, 0.55, 1.0 }, shape = "hexagon", note = 1.5 },
}

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
    mode = "gate", -- gate | fight | interlude (out of the world, minions fight) | emerge (coming back, changed)
    pending = nil,
    size = 1, sizeT = 1, alpha = 1, form = 0,
    home = { a and a.cx or cx, a and (a.floorY - 215) or cy },
    handA = -math.pi / 2,
    handDir = 1,
    handT = 0, -- charge: the hand is only live once it has risen
    flipT = 7,
    boltT = 2,
    wellT = 3,
    orbT = 4,
    rayT = 3,
    swoopT = 9,
    blinkT = 7,
    move = { kind = "patrol", t = 0 },
    minions = {},
    interT = 0,
    nodes = nil,
    orbs = {},
    rayBatch = 0,
    collapse = 0,
  }
  for i = 1, 6 do
    sw.orbs[i] = { a = i / 6 * math.pi * 2, state = "idle", t = 0, vis = 0 }
  end
  e.sw = sw
  e.ph = 1
  e.bossName = def.name
  return sw
end

-- The gate's stars, on an arc over the hall: low at the sides, high in the middle
local function nodePositions(sw, a, n)
  local w = a and a.w or 600
  local fy = a and a.floorY or sw.home[2] + 215
  local out = {}
  for i = 1, n do
    local u = n == 1 and 0.5 or (i - 1) / (n - 1)
    out[i] = {
      x = sw.home[1] + (u - 0.5) * w * 0.8,
      y = fy - 62 - math.sin(u * math.pi) * 78,
      lit = 0, solved = 0, wrong = 0, kind = i,
    }
  end
  return out
end

local function newSequence(sw, n, len)
  local seq = {}
  local last
  for i = 1, len do
    local k
    repeat
      k = love.math.random(n)
    until k ~= last or n == 1
    seq[i] = k
    last = k
  end
  sw.seq, sw.stage, sw.stageT, sw.inputI = seq, "show", -0.8, 1
  for _, nd in ipairs(sw.nodes) do
    nd.lit, nd.solved = 0, 0
  end
end

local TURN_BANNERS = {
  { "The Divine Orbs", "His orbs break away and hunt. Gravity wells open, and Star Guardians shield him" },
  { "The Celestial Rays", "Pillars of light fall where you stand. Do not stay still" },
  { "The Sun", "All of it, at once. He burns" },
}

-- A turn begins at its gate
local function startTurn(e, sw, ph)
  sw.ph, e.ph = ph, ph
  sw.handT = 0
  sw.boltT = 3.2
  sw.wellT = 3
  sw.orbT = 5
  sw.rayT = 5
  sw.swoopT = T.swoopEvery[ph] * 0.8
  sw.blinkT = 5
  sw.move = { kind = "patrol", t = 0 }
  sw.guard, sw.g2 = nil, false
  sw.mode = "gate"
  sw.nodes = nodePositions(sw, e.arena, T.stars[ph])
  newSequence(sw, T.stars[ph], T.order[ph])
  local n = TURN_BANNERS[ph - 1]
  require("src.hud").showBanner(n and n[1] or "Ascension", n and n[2] or "He cannot be hurt. Shoot the stars in the order they light")
  audio.playAt("sw_hum", sw.home[1], sw.home[2], 0.8, 1)
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

-- Where the boss's core is (the beams, bolts and orbs come from it)
local function origin(e, sw)
  local cx, cy = center(e)
  return cx, cy - 10 * (sw and sw.size or 1)
end

local function addRay(sw, x, delay)
  rays[#rays + 1] = { x = x, age = -(delay or 0), warn = 1.05, life = 0.45, w = 20, hit = false }
end

-- The heavens answering a wrong star: bolts all round, and rays where the hunter stands
local function answer(e, sw, px)
  local cx, cy = origin(e, sw)
  for k = 0, 7 do
    local ang = k / 8 * math.pi * 2 + sw.t
    bolts[#bolts + 1] = { x = cx, y = cy, vx = math.cos(ang) * T.boltSpeed, vy = math.sin(ang) * T.boltSpeed, life = 4.5, dmg = math.max(1, math.floor(T.boltDamage * e.dmgMul + 0.5)) }
  end
  addRay(sw, px, 0)
  addRay(sw, px - 90, 0.25)
  addRay(sw, px + 90, 0.25)
end

-- The gate breaks: he can be hurt
local function breakGate(e, sw)
  sw.mode = "fight"
  local cx, cy = center(e)
  effects.ring(cx, cy, 130, { 1, 0.95, 0.7 })
  effects.ring(cx, cy, 80, { 1, 0.85, 0.5 })
  audio.playAt("explosion", cx, cy, 0.8, 0.9)
  audio.playAt("sw_chime", cx, cy, 1, 0.7)
  shake(0.5)
  for _, nd in ipairs(sw.nodes) do
    effects.ring(nd.x, nd.y, 40, STAR[nd.kind].c)
  end
  require("src.hud").showBanner("The Gate Breaks", "He can be hurt")
  sw.swoopT, sw.rayT = 4, 3
end

-- A star shot in the gate: right, or wrong
local function shootNode(e, sw, i)
  local nd = sw.nodes[i]
  if sw.stage ~= "input" then
    return
  end
  local S = STAR[nd.kind]
  if sw.seq[sw.inputI] == i then
    sw.inputI = sw.inputI + 1
    nd.solved = 1
    audio.playAt("sw_chime", nd.x, nd.y, 0.9, S.note)
    effects.ring(nd.x, nd.y, 26, S.c)
    if sw.inputI > #sw.seq then
      sw.stage, sw.stageT = "done", 0
    end
  else
    -- Out of order: the order starts again, and the heavens answer
    audio.playAt("clank", nd.x, nd.y, 0.9, 0.5)
    effects.ring(nd.x, nd.y, 26, { 1, 0.2, 0.2 })
    nd.wrong = 1
    sw.inputI = 1
    sw.stripBad = 1
    for _, o in ipairs(sw.nodes) do
      o.solved = 0
    end
    answer(e, sw, e.lastPx or sw.home[1])
  end
end

def.extraHit = function(e, x, y)
  local sw = e.sw
  return sw ~= nil and sw.mode == "gate" and sw.stage == "input" and nodeAt(sw, x, y) ~= nil
end

-- A Star Guardian takes his side for a while: he cannot be hurt while it burns
local function summonGuardian(e, sw, hpMul)
  local cx, cy = center(e)
  local g = enemies.spawn("starguardian", cx + 150, cy, math.max(1.5, e.toughness * 0.6) * (hpMul or 1), e.level)
  g.guardOf = e
  g.seesPlayer = true
  sw.guard = g
  effects.ring(cx + 150, cy, 40, { 1, 0.95, 0.65 })
  audio.playAt("sw_grow", cx, cy, 0.7, 1.3)
end

local function guardUp(sw)
  return sw.guard ~= nil and not sw.guard.dead
end

local function startDying(e, sw)
  sw.dying, sw.dyT = true, 0
  e.hp = 1
  for i = #bolts, 1, -1 do
    bolts[i] = nil
  end
  for i = #rays, 1, -1 do
    rays[i] = nil
  end
  for i = #enemies.wells, 1, -1 do
    enemies.wells[i] = nil
  end
  local cx, cy = center(e)
  audio.playAt("sw_grow", cx, cy, 1, 0.5)
  audio.playAt("dh_voice", cx, cy, 1, 0.45)
  shake(0.8)
  require("src.hud").showBanner("It Falls", "A sun, dying")
end

def.filter = function(e, amount)
  local sw = ensure(e)
  if sw.finishing then
    return amount
  end
  local ax, ay = center(e)
  if sw.dying or sw.intro > 0 or sw.mode == "interlude" or sw.mode == "emerge" or sw.pending or sw.blinking then
    return 0
  end
  if sw.mode == "gate" then
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
  if guardUp(sw) then
    -- the shell of light: it rings and shrugs the blow off
    audio.playAt("clank", ax, ay, 0.5, 1.9)
    effects.ring(ax, ay, 40 * sw.size, { 1, 0.95, 0.65 })
    sw.shieldFlash = 0.25
    return 0
  end
  if sw.ph == 2 and not sw.g2 and e.hp - amount <= math.ceil(e.maxHp * (T.lines[1] + T.lines[2]) / 2) then
    -- half way through the turn a second star answers
    e.hp = math.ceil(e.maxHp * (T.lines[1] + T.lines[2]) / 2)
    sw.g2 = true
    summonGuardian(e, sw, 1.3)
    require("src.hud").showBanner("Another Star Answers", "Break it")
    return 0
  end
  if sw.ph == 4 then
    if e.hp - amount <= 1 then
      startDying(e, sw)
      return 0
    end
    return amount
  end
  -- The blow that would cross into the next turn stops at it
  local floorHp = math.ceil(e.maxHp * T.lines[sw.ph])
  if e.hp - amount <= floorHp then
    e.hp = floorHp
    sw.pending = sw.ph + 1
    audio.playAt("dh_voice", ax, ay, 1, 0.55)
    return 0
  end
  return amount
end

def.light = function(e)
  local sw = e.sw
  local cx, cy = origin(e, sw)
  local k = sw and sw.alpha or 1
  local f = sw and sw.form or 0
  local size = sw and sw.size or 1
  local boost = sw and sw.dying and (1 + 2.5 * math.min(1, sw.dyT / 6)) or 1
  local l = { { cx, cy, (110 + 140 * f) * size ^ 0.7 * boost, lerp(0.95, 1, f), lerp(0.88, 0.94, f), lerp(0.65, 0.8, f), (0.65 + 0.5 * f) * k } }
  if sw and sw.nodes then
    for _, nd in ipairs(sw.nodes) do
      local n = math.max(nd.lit, nd.solved)
      if n > 0.05 then
        local c = STAR[nd.kind].c
        l[#l + 1] = { nd.x, nd.y, 90, c[1], c[2], c[3], 1.0 * n }
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
  if sw.ph == 2 or sw.ph == 4 then
    out[2] = sw.handA + math.pi
  end
  return out
end

-- The orbs -------------------------------------------------------------------------------------------------

local function orbCount(sw)
  return ({ 2, 4, 4, 6 })[sw.ph]
end

-- Where orb i hangs: on a flattened ring round the core
local function orbPos(e, sw, i)
  local cx, cy = origin(e, sw)
  local n = orbCount(sw)
  local ang = sw.t * 0.7 + (i - 1) / n * math.pi * 2
  local r = 78 * sw.size
  return cx + math.cos(ang) * r, cy + math.sin(ang) * r * 0.5 - 14 * sw.size
end

local function updateOrbs(e, sw, dt, player, px, py)
  local n = orbCount(sw)
  for i, o in ipairs(sw.orbs) do
    local want = (i <= n and o.state ~= "away") and 1 or 0
    o.vis = o.vis + (want - o.vis) * math.min(1, dt * 3)
    if o.state == "charge" then
      o.t = o.t - dt
      if o.t <= 0 then
        local x, y = orbPos(e, sw, i)
        local d = math.max(1, hypot(px - x, py - y))
        bolts[#bolts + 1] = {
          x = x, y = y, vx = (px - x) / d * T.orbSpeed, vy = (py - y) / d * T.orbSpeed, life = 5.5, orb = true, home = 2.2,
          dmg = math.max(1, math.floor(T.orbDamage * e.dmgMul + 0.5)),
        }
        audio.playAt("sw_orb", x, y, 0.8, 0.9 + love.math.random() * 0.2)
        o.state, o.t = "away", 2.6
      end
    elseif o.state == "away" then
      o.t = o.t - dt
      if o.t <= 0 then
        o.state = "idle"
      end
    end
  end
  if sw.ph >= 2 and (sw.mode == "fight" or sw.mode == "gate") and not sw.dying then
    sw.orbT = sw.orbT - dt
    if sw.orbT <= 0 then
      sw.orbT = T.orbEvery[sw.ph] * (sw.mode == "gate" and 1.4 or 1)
      local pick = 0
      for i, o in ipairs(sw.orbs) do
        if i <= n and o.state == "idle" and pick < (sw.ph == 4 and 3 or 2) then
          pick = pick + 1
          o.state, o.t = "charge", 0.7 + pick * 0.25
          local x, y = orbPos(e, sw, i)
          audio.playAt("sw_chime", x, y, 0.8, 0.9 + pick * 0.15)
        end
      end
    end
  end
end

-- Rays -----------------------------------------------------------------------------------------------------

local function rayVolley(e, sw, a, px)
  local w = a and a.w or 700
  local cx = sw.home[1]
  sw.rayBatch = (sw.rayBatch + 1) % 3
  if sw.rayBatch == 0 then
    addRay(sw, px, 0)
    addRay(sw, px - 75, 0.15)
    addRay(sw, px + 75, 0.15)
  elseif sw.rayBatch == 1 then
    -- a comb across the disc, with a gap that slides
    local gap = love.math.random(0, 5)
    for k = 0, 6 do
      if k ~= gap and k ~= gap + 1 then
        addRay(sw, cx + (k - 3) * (w * 0.14), 0)
      end
    end
  else
    -- a sweep from one side to the other, close on one another
    local dir = px > cx and -1 or 1
    for k = 0, 9 do
      addRay(sw, cx + dir * (w * 0.42) - dir * k * (w * 0.093), k * 0.2)
    end
  end
  audio.playAt("sw_charge", px, sw.home[2], 0.8, 1)
end

-- Update ------------------------------------------------------------------------------------------------

local function fireBolts(e, sw, px, py)
  local cx, cy = origin(e, sw)
  local dmg = math.max(1, math.floor(T.boltDamage * e.dmgMul + 0.5))
  if sw.ph == 1 or sw.ph == 3 then
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
    -- (the sun: a ring and an aimed fan, alternately)
    sw.alt = not sw.alt
    if sw.alt then
      for k = 0, 13 do
        local ang = k / 14 * math.pi * 2 + sw.t * 0.4
        bolts[#bolts + 1] = { x = cx, y = cy, vx = math.cos(ang) * T.boltSpeed * 0.85, vy = math.sin(ang) * T.boltSpeed * 0.85, life = 5, dmg = dmg }
      end
    else
      local aim = math.atan2(py - cy, px - cx)
      for k = -3, 3 do
        local ang = aim + k * 0.17
        bolts[#bolts + 1] = { x = cx, y = cy, vx = math.cos(ang) * T.boltSpeed * 1.1, vy = math.sin(ang) * T.boltSpeed * 1.1, life = 5, dmg = dmg }
      end
    end
  end
  audio.playAt("sw_orb", cx, cy, 0.5, 1.5)
end

local function updateNodes(e, sw, dt)
  for _, nd in ipairs(sw.nodes) do
    nd.lit = math.max(0, nd.lit - dt * 2.4)
    nd.wrong = math.max(0, (nd.wrong or 0) - dt * 3)
  end
  sw.stripBad = math.max(0, (sw.stripBad or 0) - dt * 2.5)
  sw.stageT = sw.stageT + dt
  if sw.stage == "show" then
    local i = math.floor(sw.stageT / T.show) + 1
    if sw.stageT >= 0 and i <= #sw.seq then
      local nd = sw.nodes[sw.seq[i]]
      local phase = sw.stageT - (i - 1) * T.show
      if phase < T.show * 0.7 then
        if (sw.shown or 0) ~= i then
          sw.shown = i
          audio.playAt("sw_chime", nd.x, nd.y, 0.9, STAR[nd.kind].note)
          effects.ring(nd.x, nd.y, 30, STAR[nd.kind].c)
        end
        nd.lit = 1
      end
    elseif sw.stageT > #sw.seq * T.show + 0.5 then
      sw.stage, sw.stageT, sw.inputI, sw.shown = "input", 0, 1, nil
    end
  elseif sw.stage == "input" then
    if sw.stageT > T.inputTime + #sw.seq * 1.5 then
      -- too slow: the order shows again
      sw.stage, sw.stageT, sw.inputI = "show", -0.6, 1
      for _, nd in ipairs(sw.nodes) do
        nd.solved = 0
      end
    end
  elseif sw.stage == "done" then
    if sw.stageT > 1.1 and not e.dead then
      breakGate(e, sw)
    end
  end
end

-- The minions of each interlude: { kind, count } by the turn just ended
local MINIONS = {
  { { "gildedlens", 5 } }, -- (brass contraptions, gilded)
  { { "stormcloud", 2 }, { "cometling", 4 } },
  { { "stormcloud", 2 }, { "cometling", 4 }, { "gildedlens", 2 } },
}

local function beginInterlude(e, sw)
  local a = e.arena
  local cx, cy = center(e)
  sw.mode, sw.interT = "interlude", 0
  for i = #bolts, 1, -1 do
    bolts[i] = nil
  end
  for i = #rays, 1, -1 do
    rays[i] = nil
  end
  for i = #enemies.wells, 1, -1 do
    enemies.wells[i] = nil
  end
  for _, o in ipairs(sw.orbs) do
    o.state, o.t = "idle", 0
  end
  if sw.guard and not sw.guard.dead then
    enemies.vanish(sw.guard)
  end
  audio.playAt("sw_vanish", cx, cy, 1, 1)
  shake(0.6)
  effects.ring(cx, cy, 90, { 1, 0.95, 0.7 })
  require("src.hud").showBanner("The Heavens Call", "He slips out of the world. His servants come in his stead")
  local at = a and a.cx or cx
  local w = a and a.w or 700
  local ground = a and a.floorY or cy + 200
  for _, grp in ipairs(MINIONS[sw.pending - 1] or {}) do
    for _ = 1, grp[2] do
      local side = love.math.random() < 0.5 and -1 or 1
      local x = at + side * (w * (0.12 + love.math.random() * 0.3))
      local y = ground - 110 - love.math.random() * 170
      local m = enemies.spawn(grp[1], x, y, math.max(1.5, e.toughness * 0.55), e.level)
      m.minion = true
      m.seesPlayer = true
      sw.minions[#sw.minions + 1] = m
      effects.ring(x, y, 20, { 1, 0.95, 0.7 })
    end
  end
end

local function minionsLeft(sw)
  local n = 0
  for _, m in ipairs(sw.minions) do
    if not m.dead then
      n = n + 1
    end
  end
  return n
end

local function vanishMinions(sw)
  for _, m in ipairs(sw.minions) do
    if not m.dead then
      enemies.vanish(m)
    end
  end
  sw.minions = {}
  if sw.guard and not sw.guard.dead then
    enemies.vanish(sw.guard)
  end
end

-- His death: he unravels, then collapses in on himself like a dying star, and goes out, leaving a hole ------------

local function updateDying(e, sw, dt, world, player)
  local b = e.body
  sw.dyT = sw.dyT + dt
  local t = sw.dyT
  local ox, oy = origin(e, sw)
  e.state = "chase"
  -- stays where it is, shaking
  b.vx, b.vy = b.vx * 0.9, b.vy * 0.9
  local mag = t < 2.5 and 1.5 or 0.6 + t * 0.5
  b.x = b.x + (love.math.random() - 0.5) * mag
  b.y = b.y + (love.math.random() - 0.5) * mag
  local base = T.size[4]
  if t < 2.5 then
    -- unravelling: he flares and sheds light
    sw.size = base * (1 + 0.04 * math.sin(t * 40))
    sw.collapse = 0
    if love.math.random() < dt * 60 then
      local a = love.math.random() * math.pi * 2
      effects.particle(ox + math.cos(a) * 30, oy + math.sin(a) * 30, math.cos(a) * 120, math.sin(a) * 120, 0.8, { 1, 0.9, 0.55 }, 0, true)
    end
    if math.floor(t * 2) ~= math.floor((t - dt) * 2) then
      effects.ring(ox, oy, 80 + t * 20, { 1, 0.9, 0.6 })
      audio.playAt("sw_chime", ox, oy, 0.6, 0.6 + t * 0.2)
    end
    shake(0.25 + t * 0.1)
  elseif t < 7 then
    -- collapsing: smaller and smaller and brighter, everything falling in
    local k = (t - 2.5) / 4.5
    sw.collapse = k
    sw.size = base * lerp(1, 0.28, k * k)
    local n = math.floor(2 + k * 5)
    for _ = 1, n do
      local a = love.math.random() * math.pi * 2
      local r = 90 + love.math.random() * 190
      local x, y = ox + math.cos(a) * r, oy + math.sin(a) * r
      effects.particle(x, y, -math.cos(a) * r * 1.3, -math.sin(a) * r * 1.3, 0.75, { 1, 0.85 + 0.15 * k, 0.5 + 0.5 * k }, 0, true)
    end
    if math.floor(t * 3) ~= math.floor((t - dt) * 3) then
      effects.ring(ox, oy, 150 - 100 * k, { 1, 0.95, 0.75 }, true)
    end
    if not sw.hummed then
      sw.hummed = true
      audio.playAt("sw_charge", ox, oy, 1, 0.5)
    end
    shake(0.35 + k * 0.5)
  elseif t < T.dying then
    -- the singularity: a flash, and then nothing where he was
    sw.collapse = 1
    sw.size = base * 0.28 * math.max(0, 1 - (t - 7) / 0.5)
    if not sw.flashed then
      sw.flashed = true
      audio.playAt("explosion", ox, oy, 1, 0.3)
      audio.playAt("sw_ray", ox, oy, 1, 0.4)
      audio.setBoss(false)
      for k = 1, 4 do
        effects.ring(ox, oy, 60 + k * 60, { 1, 0.95, 0.8 })
      end
      shake(1.0)
      for _ = 1, 40 do
        local a = love.math.random() * math.pi * 2
        local sp = 80 + love.math.random() * 260
        effects.particle(ox, oy, math.cos(a) * sp, math.sin(a) * sp, 1.0, { 1, 0.92, 0.65 }, 0, true)
      end
    end
  elseif not sw.ended then
    sw.ended = true
    sw.finishing = true
    enemies.damage(e, e.hp + 5, 0, 0, 0, false, nil)
    sw.finishing = false
  end
end

local function updateStar(e, dt, world, player, px, py)
  local sw = ensure(e)
  local b = e.body
  local a = e.arena
  local cx, cy = center(e)
  sw.t = sw.t + dt
  e.lastPx = px
  e.state, e.seesPlayer = "chase", true
  audio.setBoss(not (sw.dying and sw.dyT > 7))
  if sw.dying then
    updateDying(e, sw, dt, world, player)
    sw.alpha = 1
    local nx, ny = center(e)
    b.w, b.h = math.floor(30 * math.max(0.1, sw.size)), math.floor(52 * math.max(0.1, sw.size))
    b.x, b.y = nx - b.w / 2, ny - b.h / 2
    return
  end

  -- Size, presence, and how far he has burned toward a sun
  local aimAlpha = (sw.mode == "interlude" and 0.3) or (sw.blinking and 0.0) or 1
  sw.alpha = sw.alpha + (aimAlpha - sw.alpha) * math.min(1, dt * 5)
  local grow = sw.mode == "emerge" and 2.2 or 1.2
  sw.size = sw.size + ((sw.sizeT or 1) - sw.size) * math.min(1, dt * grow)
  local formT = (sw.mode == "interlude" or sw.mode == "emerge") and (sw.pending or sw.ph) - 1 or sw.ph - 1
  sw.form = sw.form + (formT / 3 - sw.form) * math.min(1, dt * (sw.mode == "emerge" and 1.4 or 0.9))
  sw.shieldFlash = math.max(0, (sw.shieldFlash or 0) - dt)

  -- Where he wants to be, and how he gets there
  local tx, ty = sw.home[1], sw.home[2]
  local w = a and a.w or 500
  local m = sw.move
  local dashing = false
  if sw.mode == "interlude" then
    tx, ty = sw.home[1] + math.sin(sw.t * 0.4) * w * 0.2, sw.home[2] - 150 + math.sin(sw.t * 0.9) * 14
  elseif sw.mode == "gate" then
    tx, ty = sw.home[1] + math.sin(sw.t * 0.3) * 30, sw.home[2] - 30 + math.sin(sw.t * 0.8) * 5
  elseif sw.ph == 4 then
    tx = sw.home[1] + math.sin(sw.t * 0.35) * w * 0.28
    ty = sw.home[2] + math.sin(sw.t * 0.9) * 22
  else
    local fast = ({ 0.5, 0.7, 0.45 })[sw.ph]
    local reach = ({ 0.34, 0.4, 0.44 })[sw.ph]
    tx = sw.home[1] + math.sin(sw.t * fast) * w * reach
    ty = sw.home[2] + math.sin(sw.t * fast * 1.9) * 42 - (sw.ph == 3 and 40 or 0)
  end
  if sw.mode == "fight" and sw.intro <= 0 and (sw.ph == 1 or sw.ph == 2) and not guardUp(sw) then
    if m.kind == "patrol" then
      sw.swoopT = sw.swoopT - dt
      if sw.swoopT <= 0 and not player.dead then
        m.kind, m.t = "windup", 0.75
        m.dir = px >= cx and 1 or -1
        audio.playAt("sw_charge", cx, cy, 0.7, 1.2)
      end
    elseif m.kind == "windup" then
      m.t = m.t - dt
      tx, ty = cx - m.dir * 40, cy - 30 -- (rears back)
      if m.t <= 0 then
        m.kind, m.t = "dash", 0.9
        m.hit = false
        local gx, gy = px, (a and a.floorY or py) - 105
        local d = math.max(1, hypot(gx - cx, gy - cy))
        b.vx, b.vy = (gx - cx) / d * 540, (gy - cy) / d * 540
        audio.playAt("gust_blast", cx, cy, 0.9, 0.7)
        m.tx, m.ty = gx, gy
      end
    elseif m.kind == "dash" then
      dashing = true
      m.t = m.t - dt
      if (cx - m.tx) ^ 2 + (cy - m.ty) ^ 2 < 40 ^ 2 or m.t <= 0 then
        m.kind, m.t = "patrol", 0
        sw.swoopT = T.swoopEvery[sw.ph] * (0.8 + love.math.random() * 0.4)
      end
      if not m.hit and not player.dead then
        local bb = player.body
        if overlaps(b.x - 4, b.y - 4, b.w + 8, b.h + 8, bb.x, bb.y, bb.w, bb.h) then
          m.hit = true
          if player:hurt(math.max(1, math.floor(T.swoopDamage * e.dmgMul + 0.5)), cx, cy, "starwarden") then
            player.lastEnemy = e
          end
        end
      end
      if love.math.random() < dt * 60 then
        effects.particle(cx, cy, (love.math.random() - 0.5) * 30, (love.math.random() - 0.5) * 30, 0.4, { 1, 0.9, 0.5 }, 0, true)
      end
    end
  end
  -- Turn three: he blinks to the far side of the sky, and the rays come as he arrives
  if sw.mode == "fight" and sw.ph == 3 and sw.intro <= 0 then
    sw.blinkT = sw.blinkT - dt
    if sw.blinking == nil and sw.blinkT <= 0 then
      sw.blinking, sw.blinkPhase = true, "out"
      sw.blinkT = T.blinkEvery
      audio.playAt("sw_vanish", cx, cy, 0.7, 1.4)
    end
    if sw.blinking then
      if sw.blinkPhase == "out" and sw.alpha < 0.08 then
        local side = px > sw.home[1] and -1 or 1
        local nx = sw.home[1] + side * w * (0.2 + love.math.random() * 0.2)
        local ny = sw.home[2] - 20 - love.math.random() * 50
        b.x, b.y = nx - b.w / 2, ny - b.h / 2
        b.vx, b.vy = 0, 0
        cx, cy = nx, ny
        sw.blinkPhase = "in"
        effects.ring(nx, ny, 70, { 1, 0.95, 0.7 })
        audio.playAt("sw_chime", nx, ny, 0.9, 0.8)
      elseif sw.blinkPhase == "in" then
        sw.blinking = nil
        if sw.rayT > 1.2 then
          sw.rayT = 0.4
        end
      end
    end
  end
  if not dashing then
    b.vx = b.vx + ((tx - cx) * 2.2 - b.vx * 2.2) * dt
    b.vy = b.vy + ((ty - cy) * 2.2 - b.vy * 2.2) * dt
  end
  b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
  -- (his hitbox grows with him)
  local ncx, ncy = center(e)
  b.w, b.h = math.floor(30 * sw.size), math.floor(52 * sw.size)
  b.x, b.y = ncx - b.w / 2, ncy - b.h / 2
  cx, cy = ncx, ncy

  updateOrbs(e, sw, dt, player, px, py)

  if sw.intro > 0 then
    sw.intro = sw.intro - dt
    if sw.intro <= 0 then
      startTurn(e, sw, 1)
    end
    return
  end

  -- Between turns -----------------------------------------------------------------------------------------
  if sw.pending and sw.mode == "fight" then
    sw.sizeT = T.size[sw.pending]
    beginInterlude(e, sw)
  end
  if sw.mode == "interlude" then
    sw.interT = sw.interT + dt
    if (minionsLeft(sw) == 0 and sw.interT > 4) or sw.interT > 50 then
      vanishMinions(sw)
      sw.mode, sw.emT = "emerge", 2.4
      audio.playAt("sw_grow", cx, cy, 1, 1)
      effects.ring(cx, cy, 60, { 1, 0.95, 0.7 })
    end
    return
  end
  if sw.mode == "emerge" then
    sw.emT = sw.emT - dt
    if sw.emT <= 0 then
      effects.ring(cx, cy, 120, { 1, 0.95, 0.7 })
      effects.ring(cx, cy, 80, { 1, 0.85, 0.5 })
      audio.playAt("explosion", cx, cy, 1, 0.5)
      shake(0.7)
      local ph = sw.pending
      sw.pending = nil
      startTurn(e, sw, ph)
    end
    return
  end

  -- A guardian at the start of turn two's window
  if sw.ph == 2 and sw.mode == "fight" and not sw.guard and not sw.g2 then
    summonGuardian(e, sw, 1)
  end

  -- The hand: it rises over a second, turns, and now and then reverses (after a pause)
  local ox, oy = origin(e, sw)
  sw.handT = math.min(1, sw.handT + dt / 0.8)
  sw.flipT = sw.flipT - dt
  if sw.flipT <= 0 then
    sw.flipT = 5 + love.math.random() * 3.5
    sw.handDir = -sw.handDir
    sw.handT = 0.0
    audio.playAt("sw_hum", ox, oy, 0.8, 1)
  end
  sw.handA = sw.handA + sw.handDir * T.hand[sw.ph] * dt * (0.4 + 0.6 * sw.handT)
  if sw.handT >= 1 and not player.dead and not sw.blinking then
    local pcx, pcy = player:center()
    for _, ang in ipairs(hands(sw)) do
      local ex, ey = beamEnd(world, ox, oy, ang)
      if segmentDist(pcx, pcy, ox, oy, ex, ey) < 5 then
        if player:hurt(math.max(1, math.floor(T.handDamage * e.dmgMul + 0.5)), ox, oy, "starwarden") then
          player.lastEnemy = e
        end
      end
    end
  end
  -- Bolts
  sw.boltT = sw.boltT - dt
  if sw.boltT <= 0 and not sw.blinking then
    sw.boltT = T.boltEvery[sw.ph] * (sw.mode == "gate" and 1.3 or 1)
    fireBolts(e, sw, px, py)
  end
  -- Gravity wells
  if (sw.ph == 2 or sw.ph == 4) and sw.mode == "fight" then
    sw.wellT = sw.wellT - dt
    if sw.wellT <= 0 and #enemies.wells < 2 then
      sw.wellT = T.wellEvery
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
  -- Rays
  if sw.ph >= 3 then
    sw.rayT = sw.rayT - dt
    if sw.rayT <= 0 and not sw.blinking then
      sw.rayT = T.rayEvery[sw.ph] * (sw.mode == "gate" and 1.6 or 1)
      rayVolley(e, sw, a, px)
    end
  end
  if sw.mode == "gate" then
    updateNodes(e, sw, dt)
    sw.stripX = (sw.stripX or px) + (px - (sw.stripX or px)) * math.min(1, dt * 6)
    sw.stripY = py - 52
  end
end

-- Draw --------------------------------------------------------------------------------------------------

local CREAM, CREAM_S, CREAM_H = { 0.97, 0.94, 0.86 }, { 0.66, 0.74, 0.92 }, { 1.0, 1.0, 0.97 }
local GOLD_L, GOLD, GOLD_D = { 1.0, 0.92, 0.55 }, { 0.93, 0.70, 0.22 }, { 0.55, 0.38, 0.12 }
local A = 1 -- (how solid he is this frame)
local F = 0 -- (how far he has burned toward a sun this frame, 0-1)

local function col(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (a or 1) * A)
end

local function mix(c1, c2, k)
  return { lerp(c1[1], c2[1], k), lerp(c1[2], c2[2], k), lerp(c1[3], c2[3], k) }
end

local function ellipsePoints(rx, ry, n)
  local pts = {}
  for i = 0, n - 1 do
    local ang = i / n * math.pi * 2
    pts[#pts + 1] = math.cos(ang) * rx
    pts[#pts + 1] = math.sin(ang) * ry
  end
  return pts
end

-- An arm: puffs along a curve from the shoulder to a golden gauntlet. As he burns the cloud goes to flame
local function arm(sx, sy, hx, hy, bulge, t, flip, collapse)
  hx, hy = lerp(hx, sx, collapse), lerp(hy, sy, collapse)
  local dx, dy = hx - sx, hy - sy
  local len = math.max(1, hypot(dx, dy))
  local qx, qy = (sx + hx) / 2 - dy / len * bulge, (sy + hy) / 2 + dx / len * bulge
  local n = math.max(6, math.floor(len / 9))
  local body = mix(CREAM, { 1.0, 0.93, 0.62 }, F)
  local shade = mix(CREAM_S, { 0.95, 0.62, 0.25 }, F)
  for i = 0, n do
    local u = i / n
    local x = (1 - u) ^ 2 * sx + 2 * (1 - u) * u * qx + u ^ 2 * hx
    local y = (1 - u) ^ 2 * sy + 2 * (1 - u) * u * qy + u ^ 2 * hy
    local r = (7.5 - u * 3 + math.sin(t * 2 + i * 1.3) * 0.7) * (1 + 0.25 * F) * (1 - collapse * 0.6)
    col(shade, 0.95)
    love.graphics.circle("fill", x + 1, y + 1.5, r)
    col(body)
    love.graphics.circle("fill", x, y, r)
    col(CREAM_H, 0.9)
    love.graphics.circle("fill", x - r * 0.3, y - r * 0.35, r * 0.45)
  end
  if collapse < 0.9 then
    col(GOLD_D)
    love.graphics.circle("fill", hx, hy, 6)
    col(GOLD)
    love.graphics.circle("fill", hx, hy, 4.8)
    col(GOLD_L)
    love.graphics.circle("fill", hx - 1.2, hy - 1.2, 2)
    col(GOLD_D)
    love.graphics.polygon("fill", hx + flip * 3, hy - 2, hx + flip * 10, hy - 4, hx + flip * 4, hy + 1)
    love.graphics.polygon("fill", hx + flip * 3, hy + 2, hx + flip * 10, hy + 5, hx + flip * 4, hy + 5)
  end
end

-- An orb: a gold ball with a spike through it
local function orbShape(x, y, r, a, spin)
  love.graphics.setColor(GOLD_D[1], GOLD_D[2], GOLD_D[3], a)
  love.graphics.circle("fill", x, y, r + 1)
  love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], a)
  love.graphics.circle("fill", x, y, r)
  love.graphics.setColor(GOLD_L[1], GOLD_L[2], GOLD_L[3], a)
  love.graphics.circle("fill", x - r * 0.2, y - r * 0.2, r * 0.6)
  love.graphics.setColor(1, 1, 0.9, a)
  love.graphics.circle("fill", x - r * 0.2, y - r * 0.2, r * 0.25)
  love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], a)
  love.graphics.polygon("fill", x, y - r * 2.6, x + r * 0.35, y - r, x, y - r * 0.6, x - r * 0.35, y - r)
  love.graphics.polygon("fill", x, y + r * 2.6, x + r * 0.35, y + r, x, y + r * 0.6, x - r * 0.35, y + r)
  love.graphics.setColor(GOLD_L[1], GOLD_L[2], GOLD_L[3], a * 0.8)
  love.graphics.setLineWidth(1)
  love.graphics.arc("line", "open", x, y, r * 1.7, spin, spin + 2.2)
  love.graphics.arc("line", "open", x, y, r * 1.7, spin + math.pi, spin + math.pi + 2.2)
end

local function drawStar(e)
  local sw = e.sw
  local t = love.timer.getTime()
  local cx, cy = center(e)
  local size = sw and sw.size or 1
  local collapse = sw and sw.collapse or 0
  A = sw and sw.alpha or 1
  F = sw and sw.form or 0
  if A < 0.02 or size < 0.05 then
    return
  end
  if sw and sw.mode == "interlude" then
    A = A * (0.8 + 0.2 * math.sin(t * 9)) -- (faint and shimmering between turns)
  end
  if sw and sw.dying and sw.dyT < 2.5 then
    A = A * (0.7 + 0.3 * math.sin(t * 50))
  end
  local bob = math.sin(t * 1.3) * 2
  love.graphics.push()
  love.graphics.translate(math.floor(cx), math.floor(cy + bob))
  love.graphics.scale(size, size)
  -- Arms first, behind: the sweeping ones follow the hand of light; the others hang and sway
  local active = {}
  if sw and sw.intro <= 0 and not sw.dying and (sw.mode == "fight" or sw.mode == "gate") then
    for _, ang in ipairs(hands(sw)) do
      active[math.cos(ang) >= 0 and 1 or -1] = ang
    end
  end
  for _, side in ipairs({ -1, 1 }) do
    local sx, sy = side * 10, -8
    local ang = active[side]
    if ang then
      local reach = 46 + 36 * (sw.handT or 1)
      arm(sx, sy, sx + math.cos(ang) * reach, sy + 10 + math.sin(ang) * reach, 8 * side, t, side, collapse)
    else
      local lift = (sw and (sw.mode == "interlude" or sw.mode == "emerge")) and -18 or 0
      arm(sx, sy, side * (34 + math.sin(t * 1.5 + side) * 3), 20 + lift + math.sin(t * 1.7 + side * 2) * 5, -side * 14, t, side, collapse)
    end
  end
  -- The lance below and the feathered plates fall away as he becomes a sun
  local body = (1 - 0.75 * F) * (1 - collapse)
  if body > 0.02 then
    for _, side in ipairs({ -1, 1 }) do
      for k = 1, 3 do
        local sway = math.sin(t * 1.4 + k + side) * 1.5
        col(GOLD_D, body)
        love.graphics.polygon("fill", side * 5, -2 + k * 7, side * (24 - k * 3) + sway, 2 + k * 9, side * (19 - k * 3) + sway, 12 + k * 9, side * 4, 9 + k * 7)
        col(CREAM, body)
        love.graphics.polygon("fill", side * 5, -2 + k * 7, side * (22 - k * 3) + sway, 2 + k * 9, side * (18 - k * 3) + sway, 10 + k * 9, side * 4, 8 + k * 7)
        col(GOLD_L, 0.9 * body)
        love.graphics.line(side * 5, -2 + k * 7, side * (22 - k * 3) + sway, 2 + k * 9)
      end
    end
    local L = 70 * (1 - 0.35 * F)
    col(GOLD_D, body)
    love.graphics.polygon("fill", -7, 2, 0, -6, 7, 2, 3.5, L * 0.5, 0, L, -3.5, L * 0.5)
    col(CREAM, body)
    love.graphics.polygon("fill", -5.5, 2, 0, -4, 5.5, 2, 2.6, L * 0.5, 0, L - 4, -2.6, L * 0.5)
    col(GOLD, body)
    love.graphics.polygon("fill", 0, -4, 1.6, 20, 0, L - 4, -1.6, 20)
  end
  -- The core: a sun in a ring, with spikes; it swells as he burns
  local pulse = 1 + math.sin(t * 2.6) * 0.06
  local cr = (12 + 14 * F) * pulse
  col(GOLD_D)
  love.graphics.polygon("fill", 0, -34 - 12 * F, 3, -14, 0, -10, -3, -14)
  love.graphics.polygon("fill", -22 - 8 * F, -10, -6, -13, -4, -10, -6, -7)
  love.graphics.polygon("fill", 22 + 8 * F, -10, 6, -13, 4, -10, 6, -7)
  col(GOLD_D)
  love.graphics.circle("fill", 0, -10, cr + 2)
  col(mix(GOLD, { 1, 0.85, 0.5 }, F))
  love.graphics.circle("fill", 0, -10, cr)
  col(mix(GOLD_L, { 1, 0.97, 0.8 }, F))
  love.graphics.circle("fill", 0, -10, cr * 0.68)
  col({ 1, 1, 0.92 })
  love.graphics.circle("fill", 0, -10, cr * 0.35)
  col(GOLD_L, 0.9)
  love.graphics.setLineWidth(1)
  love.graphics.circle("line", 0, -10, cr + 4)
  -- The halo: a tilted ring over his head (two, crossing, once he is a sun)
  local halo = ellipsePoints(26 + 10 * F, 8 + 2 * F, 32)
  love.graphics.push()
  love.graphics.translate(0, -44 + 14 * F)
  love.graphics.rotate(math.sin(t * 0.5) * 0.06)
  love.graphics.setLineWidth(3)
  col(GOLD_D, 1 - collapse)
  love.graphics.polygon("line", halo)
  love.graphics.setLineWidth(1.5)
  col(GOLD_L, 1 - collapse)
  love.graphics.polygon("line", halo)
  if F > 0.45 then
    love.graphics.rotate(1.1)
    col(GOLD_L, (F - 0.45) * 1.6 * (1 - collapse))
    love.graphics.polygon("line", halo)
  end
  col(GOLD, 1 - collapse)
  love.graphics.polygon("fill", 0, -22, 3, -9, 0, -6, -3, -9)
  love.graphics.pop()
  love.graphics.setLineWidth(1)
  love.graphics.pop()
  -- The orbs that ring him, and the white flash of a hit
  if sw and not sw.dying then
    for i, o in ipairs(sw.orbs) do
      if o.vis > 0.03 then
        local x, y = orbPos(e, sw, i)
        local r = 6 * (0.7 + 0.3 * math.min(1, size)) * (o.state == "charge" and (1 + 0.35 * math.sin(t * 22)) or 1)
        orbShape(x, y, r, o.vis * A, t * 2 + i)
      end
    end
  end
  if e.flash > 0 then
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.circle("fill", cx, cy - 8 * size, 16 * size)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- The shapes of the gate's stars
local function starShape(kind, x, y, r, c, a)
  love.graphics.setColor(c[1], c[2], c[3], a)
  if kind == "circle" then
    love.graphics.circle("fill", x, y, r)
  elseif kind == "diamond" then
    love.graphics.polygon("fill", x, y - r * 1.25, x + r, y, x, y + r * 1.25, x - r, y)
  elseif kind == "triangle" then
    love.graphics.polygon("fill", x, y - r * 1.2, x + r * 1.1, y + r * 0.8, x - r * 1.1, y + r * 0.8)
  elseif kind == "square" then
    love.graphics.rectangle("fill", x - r * 0.9, y - r * 0.9, r * 1.8, r * 1.8)
  else
    local pts = {}
    for k = 0, 5 do
      pts[#pts + 1] = x + math.cos(k / 6 * math.pi * 2) * r * 1.1
      pts[#pts + 1] = y + math.sin(k / 6 * math.pi * 2) * r * 1.1
    end
    love.graphics.polygon("fill", pts)
  end
end

local function drawGate(e, sw, t, a)
  -- the stars: each its own colour and shape, dim until lit; wide halos and a spike when one is called
  local solved = {}
  for i, nd in ipairs(sw.nodes) do
    local S = STAR[nd.kind]
    local k = math.max(nd.lit, nd.solved, 0)
    local idle = 0.35 + 0.08 * math.sin(t * 3 + i)
    love.graphics.setColor(S.c[1], S.c[2], S.c[3], (0.12 + 0.3 * k) * a)
    love.graphics.circle("fill", nd.x, nd.y, 22 + 16 * k)
    starShape(S.shape, nd.x, nd.y, 7 + 3 * k, S.c, (idle + 0.65 * k) * a)
    starShape(S.shape, nd.x, nd.y, 3 + 1.5 * k, { 1, 1, 1 }, (0.4 + 0.6 * k) * a)
    if k > 0.5 then
      love.graphics.setColor(S.c[1], S.c[2], S.c[3], 0.8 * k * a)
      love.graphics.circle("line", nd.x, nd.y, 14 + (1 - k) * 18)
      love.graphics.rectangle("fill", math.floor(nd.x) - 1, math.floor(nd.y) - 20 - 8 * k, 3, 8 * k)
    end
    if (nd.wrong or 0) > 0 then
      love.graphics.setColor(1, 0.2, 0.2, nd.wrong * a)
      love.graphics.circle("line", nd.x, nd.y, 12 + (1 - nd.wrong) * 24)
    end
    if nd.solved > 0 then
      solved[#solved + 1] = nd
    end
  end
  love.graphics.setColor(1, 0.95, 0.7, 0.45 * a)
  for i = 1, #solved - 1 do
    love.graphics.line(solved[i].x, solved[i].y, solved[i + 1].x, solved[i + 1].y)
  end
  -- the order, as a strip over the hunter's head: every step in its colour and shape; the ones done are lit, the
  -- next has a ring, and the whole strip flashes red on a wrong star
  if sw.stage == "input" or sw.stage == "done" then
    local n = #sw.seq
    local x0 = (sw.stripX or sw.home[1]) - (n - 1) * 8
    local y = sw.stripY or (sw.home[2] + 100)
    love.graphics.setColor(0, 0, 0, 0.45 * a)
    love.graphics.rectangle("fill", x0 - 10, y - 8, (n - 1) * 16 + 20, 16)
    for i = 1, n do
      local S = STAR[sw.nodes[sw.seq[i]].kind]
      local done = i < sw.inputI or sw.stage == "done"
      local bad = (sw.stripBad or 0) > 0
      local c = bad and { 1, 0.25, 0.25 } or S.c
      starShape(S.shape, x0 + (i - 1) * 16, y, 4.2, c, (done and 1 or 0.4) * a)
      if i == sw.inputI and sw.stage == "input" then
        love.graphics.setColor(1, 1, 1, (0.6 + 0.4 * math.sin(t * 8)) * a)
        love.graphics.circle("line", x0 + (i - 1) * 16, y, 7)
      end
    end
  end
end

local function drawStarGlow(e)
  local sw = e.sw
  local size = sw and sw.size or 1
  local a = sw and sw.alpha or 1
  local f = sw and sw.form or 0
  local collapse = sw and sw.collapse or 0
  local cx, cy = center(e)
  local t = love.timer.getTime()
  local hx, hy = cx, cy - 10 * size
  if size < 0.05 and not (sw and sw.dying) then
    return
  end
  love.graphics.setBlendMode("add")
  local pulse = 0.8 + 0.2 * math.sin(t * 2)
  -- a sun's glow, growing as he burns, and a corona of rays turning slowly
  love.graphics.setColor(1, 0.9, 0.5, (0.2 + 0.25 * f) * pulse * a)
  love.graphics.circle("fill", hx, hy, (26 + 20 * f) * size)
  love.graphics.setColor(1, 0.85, 0.5, (0.07 + 0.12 * f) * a)
  love.graphics.circle("fill", hx, hy, (80 + 90 * f) * size)
  love.graphics.setColor(1, 0.95, 0.8, 0.35 * a + 0.4 * f)
  love.graphics.circle("fill", hx, hy, (7 + 10 * f) * size)
  if f > 0.25 or collapse > 0 then
    local n = 8 + math.floor(f * 16)
    for k = 0, n - 1 do
      local ang = k / n * math.pi * 2 + t * 0.2 * (k % 2 == 0 and 1 or -1)
      local len = (40 + 70 * f + 16 * math.sin(t * 3 + k * 2)) * size * (1 - collapse * 0.6)
      love.graphics.setColor(1, 0.85, 0.45, (0.3 * f + 0.2) * a)
      love.graphics.polygon("fill", hx + math.cos(ang - 0.05) * 14 * size, hy + math.sin(ang - 0.05) * 14 * size, hx + math.cos(ang) * len, hy + math.sin(ang) * len, hx + math.cos(ang + 0.05) * 14 * size, hy + math.sin(ang + 0.05) * 14 * size)
    end
  end
  -- the halo's glow, and a clock's twelve ticks turning round it
  local ry = cy - (44 - 14 * f) * size
  love.graphics.setLineWidth(1)
  for k = 0, 11 do
    local ang = k / 12 * math.pi * 2 + t * 0.3
    love.graphics.setColor(1, 0.92, 0.55, 0.6 * pulse * a * (1 - collapse))
    love.graphics.line(cx + math.cos(ang) * (30 + 10 * f) * size, ry + math.sin(ang) * (10 + 2 * f) * size, cx + math.cos(ang) * (k % 3 == 0 and 36 + 10 * f or 33 + 10 * f) * size, ry + math.sin(ang) * (k % 3 == 0 and 12 + 2 * f or 11 + 2 * f) * size)
  end
  if not sw then
    love.graphics.setBlendMode("alpha")
    return
  end
  -- a shield of light while a guardian burns (and a flash on it when a shot rings off)
  if guardUp(sw) then
    love.graphics.setColor(1, 0.92, 0.6, 0.12 + 0.5 * (sw.shieldFlash or 0))
    love.graphics.circle("fill", hx, hy, 58 * size)
    love.graphics.setColor(1, 0.95, 0.7, 0.55 + 0.4 * (sw.shieldFlash or 0))
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", hx, hy, 58 * size)
    love.graphics.setLineWidth(1)
    local gx, gy = center(sw.guard)
    love.graphics.setColor(1, 0.9, 0.5, 0.4)
    love.graphics.line(hx, hy, gx, gy)
  end
  -- a gate's veil: the same shield, softer and bluer, while the stars are shot
  if sw.mode == "gate" and not sw.dying then
    love.graphics.setColor(0.7, 0.8, 1, 0.1 + 0.05 * math.sin(t * 4))
    love.graphics.circle("fill", hx, hy, 54 * size)
    love.graphics.setColor(0.8, 0.88, 1, 0.5)
    love.graphics.circle("line", hx, hy, 54 * size)
  end
  -- The orbs' glow, and a ring closing on one that charges
  for i, o in ipairs(sw.orbs) do
    if o.vis > 0.03 and not sw.dying then
      local x, y = orbPos(e, sw, i)
      love.graphics.setColor(1, 0.9, 0.5, 0.25 * o.vis * a)
      love.graphics.circle("fill", x, y, 11)
      if o.state == "charge" then
        local k = math.max(0, o.t / 0.95)
        love.graphics.setColor(1, 0.95, 0.7, 0.8)
        love.graphics.circle("line", x, y, 6 + 18 * k)
      end
    end
  end
  -- The hand(s) of light: thin and pale while it rises, then bright and live
  if sw.intro <= 0 and (sw.mode == "fight" or sw.mode == "gate") and not sw.pending and not sw.blinking and not sw.dying then
    local lw = sw.handT
    for _, ang in ipairs(hands(sw)) do
      local ex, ey
      if e.beamWorld then
        ex, ey = beamEnd(e.beamWorld, hx, hy, ang)
      else
        ex, ey = hx + math.cos(ang) * T.handLen, hy + math.sin(ang) * T.handLen
      end
      love.graphics.setLineWidth(1 + 5 * lw * lw)
      love.graphics.setColor(1, 0.7, 0.25, 0.28 + 0.25 * lw)
      love.graphics.line(hx, hy, ex, ey)
      love.graphics.setLineWidth(1 + 1.5 * lw)
      love.graphics.setColor(1, 0.97, 0.8, 0.5 + 0.5 * lw)
      love.graphics.line(hx, hy, ex, ey)
      love.graphics.setColor(1, 0.9, 0.5, 0.35 * lw)
      love.graphics.circle("fill", ex, ey, 4 + 3 * lw)
    end
    love.graphics.setLineWidth(1)
  end
  if sw.nodes and sw.mode == "gate" then
    drawGate(e, sw, t, a)
  end
  -- the death's flash
  if sw.dying and sw.dyT > 6.4 then
    local k = math.min(1, (sw.dyT - 6.4) / 0.6)
    local fade = sw.dyT > 7.1 and math.max(0, 1 - (sw.dyT - 7.1) / 0.9) or 1
    love.graphics.setColor(1, 0.97, 0.85, 0.9 * k * fade)
    love.graphics.circle("fill", hx, hy, 40 + 220 * k)
  end
  love.graphics.setBlendMode("alpha")
end

-- Bolts, orbs, rays and wells, every frame --------------------------------------------------------------------

local function arenaOf()
  for _, e in ipairs(enemies.all()) do
    if e.kind == "starwarden" and e.arena then
      return e.arena, e
    end
  end
end

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  local floorY
  for _, e in ipairs(enemies.all()) do
    if e.kind == "starwarden" then
      e.beamWorld = world
      floorY = e.arena and e.arena.floorY
    end
  end
  if hole then
    hole.t = hole.t + dt
    -- (a faint pull on loose light: sparks fall toward it)
    if love.math.random() < dt * 14 then
      local a = love.math.random() * math.pi * 2
      local r = 50 + love.math.random() * 120
      effects.particle(hole.x + math.cos(a) * r, hole.y + math.sin(a) * r, -math.cos(a) * r * 0.6 - math.sin(a) * 40, -math.sin(a) * r * 0.6 + math.cos(a) * 40, 1.1, { 1, 0.7, 0.4 }, 0, true)
    end
  end
  if #bolts == 0 and #enemies.wells == 0 and #rays == 0 then
    return
  end
  local pb = player.body
  for i = #bolts, 1, -1 do
    local s = bolts[i]
    s.life = s.life - dt
    local gone = s.life <= 0
    if not gone then
      if s.home and s.home > 0 and not player.dead then
        -- an orb bends after him for a couple of seconds
        s.home = s.home - dt
        local sp = hypot(s.vx, s.vy)
        local cur = math.atan2(s.vy, s.vx)
        local want = math.atan2(py - s.y, px - s.x)
        local d = (want - cur + math.pi) % (math.pi * 2) - math.pi
        cur = cur + math.max(-1.7 * dt, math.min(1.7 * dt, d))
        s.vx, s.vy = math.cos(cur) * sp, math.sin(cur) * sp
      end
      s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
      local r = s.orb and 5 or 2
      if world:isSolid(s.x, s.y) then
        effects.particle(s.x, s.y, -s.vx * 0.1, -s.vy * 0.1, 0.25, { 1, 0.9, 0.5 }, 200, true)
        gone = true
      elseif not player.dead and overlaps(s.x - r, s.y - r, r * 2, r * 2, pb.x, pb.y, pb.w, pb.h) then
        player:hurt(s.dmg, s.x - s.vx * 0.05, s.y - s.vy * 0.05, "starwarden")
        gone = true
      end
    end
    if gone then
      if s.orb then
        for _ = 1, 8 do
          effects.particle(s.x, s.y, (love.math.random() - 0.5) * 120, (love.math.random() - 0.5) * 120, 0.4, { 1, 0.9, 0.5 }, 0, true)
        end
      end
      table.remove(bolts, i)
    end
  end
  -- Pillars of light: they warn, then strike the whole height of the sky
  for i = #rays, 1, -1 do
    local r = rays[i]
    local before = r.age
    r.age = r.age + dt
    if before < 0 and r.age >= 0 then
      audio.playAt("tick", r.x, floorY or py, 0.5, 1.8)
    end
    if before < r.warn and r.age >= r.warn then
      audio.playAt("sw_ray", r.x, floorY or py, 0.9, 0.9 + love.math.random() * 0.2)
      shake(0.25)
      if floorY then
        for _ = 1, 10 do
          effects.particle(r.x + (love.math.random() - 0.5) * r.w, floorY - 2, (love.math.random() - 0.5) * 140, -40 - love.math.random() * 120, 0.5, { 1, 0.9, 0.5 }, 240, true)
        end
      end
    end
    if r.age >= r.warn and r.age < r.warn + r.life and not r.hit and not player.dead then
      if math.abs(px - r.x) < r.w / 2 + 3 and (not floorY or py < floorY + 24) then
        r.hit = true
        player:hurt(math.max(1, math.floor(T.rayDamage * 1.4 + 0.5)), r.x, py, "starwarden")
      end
    end
    if r.age > r.warn + r.life then
      table.remove(rays, i)
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

local function rayExtent()
  local a = arenaOf()
  if a then
    return a.floorY, a.top - 500
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
    if s.orb then
      love.graphics.setColor(1, 0.85, 0.4, 0.4)
      love.graphics.line(s.x - s.vx / d * 14, s.y - s.vy / d * 14, s.x, s.y)
      love.graphics.setColor(1, 0.8, 0.3, 0.3)
      love.graphics.circle("fill", s.x, s.y, 10)
      love.graphics.setColor(1, 0.95, 0.7, 1)
      love.graphics.circle("fill", s.x, s.y, 4.5)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.circle("fill", s.x, s.y, 2)
    else
      love.graphics.setColor(1, 0.85, 0.4, 0.5)
      love.graphics.line(s.x - s.vx / d * 7, s.y - s.vy / d * 7, s.x, s.y)
      love.graphics.setColor(1, 0.97, 0.8, 1)
      love.graphics.circle("fill", s.x, s.y, 2)
      love.graphics.setColor(1, 0.8, 0.3, 0.25)
      love.graphics.circle("fill", s.x, s.y, 5)
    end
  end
  -- the pillars: a faint column and sparks on the floor while they warn, then a white-gold blaze
  local floorY, ceilY = rayExtent()
  if floorY then
    for _, r in ipairs(rays) do
      if r.age >= 0 then
        if r.age < r.warn then
          local k = r.age / r.warn
          love.graphics.setColor(1, 0.9, 0.55, 0.05 + 0.1 * k)
          love.graphics.rectangle("fill", r.x - r.w / 2, ceilY, r.w, floorY - ceilY)
          love.graphics.setColor(1, 0.95, 0.7, 0.3 + 0.5 * k)
          love.graphics.rectangle("fill", math.floor(r.x - r.w / 2 * k), floorY - 1, math.floor(r.w * k), 2)
          for s = 1, math.floor(k * 8) do
            local ph = (t * 2.2 + s * 0.37) % 1
            love.graphics.setColor(1, 0.95, 0.7, 1 - ph)
            love.graphics.rectangle("fill", math.floor(r.x + math.sin(s * 5.1) * r.w * 0.5), math.floor(floorY - 2 - ph * 18), 1, 1)
          end
        else
          local k = 1 - (r.age - r.warn) / r.life
          local w = r.w * (0.6 + 0.4 * k)
          love.graphics.setColor(1, 0.8, 0.35, 0.35 * k)
          love.graphics.rectangle("fill", r.x - w, ceilY, w * 2, floorY - ceilY)
          love.graphics.setColor(1, 0.95, 0.75, 0.85 * k)
          love.graphics.rectangle("fill", r.x - w / 2, ceilY, w, floorY - ceilY)
          love.graphics.setColor(1, 1, 1, k)
          love.graphics.rectangle("fill", r.x - w / 6, ceilY, w / 3, floorY - ceilY)
          love.graphics.setColor(1, 0.9, 0.5, 0.5 * k)
          love.graphics.circle("fill", r.x, floorY, 22 * k + 6)
        end
      end
    end
  end
  love.graphics.setBlendMode("alpha")
  -- the black hole he leaves: a black disc, a burning rim, and the light bent round it (the post pass, src.render)
  if hole then
    local r = 4 + 20 * math.min(1, hole.t / 4)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.circle("fill", hole.x, hole.y, r)
    love.graphics.setBlendMode("add")
    for k = 0, 5 do
      love.graphics.setColor(1, 0.55 + 0.07 * k, 0.2 + 0.1 * k, 0.5 - 0.06 * k)
      love.graphics.setLineWidth(1.5)
      love.graphics.circle("line", hole.x, hole.y, r + 1 + k * 1.5)
    end
    -- a thin disc seen edge-on, turning
    love.graphics.setLineWidth(1)
    for k = 0, 24 do
      local ang = t * 1.5 + k * 0.25
      local rr = r * (1.6 + k * 0.1)
      love.graphics.setColor(1, 0.7, 0.35, 0.5 * (1 - k / 26))
      love.graphics.points(hole.x + math.cos(ang) * rr * 1.6, hole.y + math.sin(ang) * rr * 0.28)
      love.graphics.points(hole.x + math.cos(ang + 3.14) * rr * 1.6, hole.y + math.sin(ang + 3.14) * rr * 0.28)
    end
    love.graphics.setBlendMode("alpha")
    local cx, cy = require("src.camera").offset()
    require("src.render").setLens(hole.x - cx, hole.y - cy, r / 0.7, math.min(1.6, hole.t * 0.8))
  end
end

-- Lights: everything he throws lights the hall, the stars light up in their colours, a ray is a column of light -----

local prevLights = enemies.afterLights
enemies.afterLights = function(lighting, view)
  if prevLights then
    prevLights(lighting, view)
  end
  local t = love.timer.getTime()
  local arena, boss = arenaOf()
  local sw = boss and boss.sw
  if sw then
    -- the hand: lights along the beam, hot at the end
    if sw.intro <= 0 and (sw.mode == "fight" or sw.mode == "gate") and not sw.pending and not sw.blinking and not sw.dying and boss.beamWorld then
      local ox, oy = origin(boss, sw)
      local lw = sw.handT
      for _, ang in ipairs(hands(sw)) do
        local ex, ey = beamEnd(boss.beamWorld, ox, oy, ang)
        local len = hypot(ex - ox, ey - oy)
        for s = 60, len, 90 do
          lighting.add(ox + math.cos(ang) * s, oy + math.sin(ang) * s, 62, 1, 0.78, 0.4, 0.5 * lw)
        end
        lighting.add(ex, ey, 70, 1, 0.8, 0.45, 0.9 * lw)
      end
    end
    for i, o in ipairs(sw.orbs) do
      if o.vis > 0.05 and not sw.dying then
        local x, y = orbPos(boss, sw, i)
        lighting.add(x, y, 44, 1, 0.88, 0.45, 0.6 * o.vis + (o.state == "charge" and 0.5 or 0))
      end
    end
    if sw.nodes and sw.mode == "gate" then
      for _, nd in ipairs(sw.nodes) do
        local c = STAR[nd.kind].c
        lighting.add(nd.x, nd.y, 36, c[1], c[2], c[3], 0.35 + 0.2 * math.sin(t * 3 + nd.kind))
      end
    end
    if guardUp(sw) then
      local ox, oy = origin(boss, sw)
      lighting.add(ox, oy, 90 * sw.size, 1, 0.9, 0.55, 0.5 + 1.5 * (sw.shieldFlash or 0))
    end
    if sw.dying then
      -- dying light: a swelling blaze that is drawn in to a point, and then a white flash
      local ox, oy = origin(boss, sw)
      local k = sw.dyT
      local radius = k < 2.5 and 200 + 60 * math.sin(k * 30) or 200 * (1 - (k - 2.5) / 4.5) + 30
      if k < 7 then
        lighting.add(ox, oy, math.max(30, radius), 1, 0.9, 0.7, 1.2 + k * 0.15)
      elseif k < 8 then
        lighting.add(ox, oy, 420, 1, 0.97, 0.85, 2.2 * (1 - (k - 7)))
      end
    end
  end
  for _, s in ipairs(bolts) do
    lighting.add(s.x, s.y, s.orb and 52 or 28, 1, 0.82, 0.4, s.orb and 0.9 or 0.55)
  end
  for _, wl in ipairs(enemies.wells) do
    local k = math.min(1, wl.life / 1.2, (wl.max - wl.life) / 0.8 + 0.1)
    lighting.add(wl.x, wl.y, 70, 0.55, 0.3, 1, 0.6 * k)
  end
  if arena then
    for _, r in ipairs(rays) do
      if r.age >= 0 then
        local fy = arena.floorY
        if r.age < r.warn then
          local k = r.age / r.warn
          lighting.add(r.x, fy - 6, 46, 1, 0.9, 0.55, 0.5 * k)
        else
          local k = 1 - (r.age - r.warn) / r.life
          for h = 0, 420, 70 do
            lighting.add(r.x, fy - h, 100, 1, 0.9, 0.6, 1.2 * k)
          end
          lighting.add(r.x, fy - 4, 150, 1, 0.95, 0.75, 1.6 * k)
        end
      end
    end
  end
  if hole then
    local r = 4 + 20 * math.min(1, hole.t / 4)
    -- the rim burns: an orange ring of light on whatever is near (the hole itself gives none)
    for k = 0, 5 do
      local a = k / 6 * math.pi * 2 + t * 1.2
      lighting.add(hole.x + math.cos(a) * (r + 4), hole.y + math.sin(a) * (r + 4) * 0.6, 56, 1, 0.55, 0.22, 0.4)
    end
    lighting.add(hole.x, hole.y, 120, 1, 0.5, 0.2, 0.3)
  end
end

-- The sky behind a fallen Champion --------------------------------------------------------------------------------

-- The hole he left, if he has fallen in this run: { x, y, t }
function enemies.skyHole()
  return hole
end

-- A new fight, or none: nothing of his left flying
local prevClear = enemies.clear
enemies.clear = function()
  prevClear()
  bolts, rays, hole = {}, {}, nil
  for i = #enemies.wells, 1, -1 do
    enemies.wells[i] = nil
  end
end

def.onDeath = function(e)
  for i = #bolts, 1, -1 do
    bolts[i] = nil
  end
  for i = #rays, 1, -1 do
    rays[i] = nil
  end
  for i = #enemies.wells, 1, -1 do
    enemies.wells[i] = nil
  end
  if e.sw then
    vanishMinions(e.sw)
  end
  local cx, cy = origin(e, e.sw)
  hole = { x = cx, y = cy, t = 0 }
  audio.playAt("sw_grow", cx, cy, 1, 0.4)
  audio.setBoss(false)
end

enemies.UPDATE.starwarden = updateStar
enemies.DRAW.starwarden = drawStar
enemies.GLOW.starwarden = drawStarGlow

return true
