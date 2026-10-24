-- The sky's boss: the Champion of the Heavens, the god's own warden of the stars. A great golden figure with a halo, a
-- core like a sun, a lance for a body and arms of cloud, ringed by orbs. He fights over the open disc of the Citadel
-- (src.cavegen, src.skygen) in four turns, and between them he slips out of the world, grows, and leaves minions to
-- keep you busy:
--
--   1  Ascension          a hand of light sweeps round him like a clock's; star bolts fan out; now and then he swoops
--   2  The Divine Orbs    two hands, gravity wells that bend every shot (and the hunter), and orbs that break from
--                         his ring and chase
--   3  The Celestial Rays he blinks about the sky and pillars of light fall where you stand (and in combs and sweeps)
--   4  The Stars Align    his true form, the largest: he can't be hurt; three stars wake round the hall and light in
--                         an order that must be shot back in the same order, longer each of three rounds. A wrong
--                         star sends the order round again and the heavens answer; every round done is a blow.
--
-- Between turns he is untouchable (faint, high up) while minions of the sky fight you; when they are dead he comes
-- back larger. Beating him changes the world a little (the sun in the overworld sky is eclipsed, see
-- src.scenes.overworld, and the epic items join the pool, see src.meta.skyBeaten).
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
  intro = 2.4, -- he wakes
  hand = { 0.50, 0.62, 0.40, 0.34 }, -- the hand's turn, radians a second, by turn
  handLen = 560,
  handDamage = 18,
  boltDamage = 8,
  boltSpeed = 150,
  boltEvery = { 2.6, 3.4, 4.2, 4.6 },
  wellEvery = 5.5,
  wellLife = 8.5,
  wellR = 130,
  wellDamage = 10,
  orbDamage = 12,
  orbSpeed = 175,
  orbEvery = { 99, 5.2, 6.0, 8.5 },
  rayEvery = { 99, 99, 4.4, 7.5 },
  rayDamage = 22,
  swoopEvery = { 12, 9, 99, 99 },
  swoopDamage = 16,
  blinkEvery = 8,
  nodeHit = 13, -- how near a shot must be to a star to count
  show = 0.85, -- seconds each star stays lit when the order is shown
  rounds = { 3, 4, 5 }, -- stars in the order, by round
  inputTime = 9,
  size = { 1.0, 1.25, 1.5, 1.8 }, -- how big he is, by turn
  lines = { 0.75, 0.5, 0.25 }, -- the health at which each turn ends
}

local def = {
  name = "The Champion of the Heavens",
  boss = true, anchored = true, alwaysActive = true,
  w = 30, h = 52, hp = 480, speed = 60,
  sight = 1400, forget = 6000,
  knockback = 0, knockMul = 0, gold = { 420, 520 }, weight = 60,
  spriteW = 60, spriteH = 90, scale = 1,
  blood = { 1.0, 0.95, 0.7 },
  desc = "The gods' own champion, sent to answer anyone who climbs this high: a golden figure with a sun for a heart, a halo, a lance for a body and arms of cloud. A hand of light turns round him like a clock's; his orbs break away to hunt you; pillars of light fall where you stand; the heavens bend around him. Each time he is hurt enough he slips out of the world and returns larger, and in the end the stars themselves take his part and must be shot in the order they light.",
}
-- (no def.damage: touching him doesn't hurt; his hand, his swoop, his orbs, rays and bolts do)
enemies.defs.starwarden = def
enemies.order[#enemies.order + 1] = "starwarden"

enemies.wells = {} -- gravity wells in the hall: { x, y, r, life, max } (src.bullets bends shots toward them)
local bolts = {} -- star bolts and orbs: { x, y, vx, vy, life, dmg, orb, home }
local rays = {} -- pillars of light: { x, age, warn, life, w, hit }

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
    mode = "fight", -- fight | interlude (out of the world, minions fight) | emerge (coming back, larger)
    pending = nil,
    size = 1, alpha = 1,
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
    round = 0,
    orbs = {},
    rayBatch = 0,
  }
  for i = 1, 6 do
    sw.orbs[i] = { a = i / 6 * math.pi * 2, state = "idle", t = 0, vis = 0 }
  end
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

local TURN_BANNERS = {
  { "The Divine Orbs", "His orbs break away and hunt. Gravity wells open: shots curve toward them, and so do you" },
  { "The Celestial Rays", "Pillars of light fall where you stand. Do not stay still" },
  { "The Stars Align", "He cannot be hurt. Shoot the stars in the order they light" },
}

local function startTurn(e, sw, ph)
  sw.ph, e.ph = ph, ph
  sw.handT = 0
  sw.boltT = 2.2
  sw.wellT = 3
  sw.orbT = 4
  sw.rayT = 3.5
  sw.swoopT = T.swoopEvery[ph] * 0.8
  sw.blinkT = 5
  sw.move = { kind = "patrol", t = 0 }
  if ph == 4 then
    sw.nodes = nodePositions(sw, e.arena)
    sw.round = 1
    sw.p4hp = e.hp
    newSequence(sw, T.rounds[1])
    sw.stageT = -1 -- a breath before the first star lights
  end
  local n = TURN_BANNERS[ph - 1]
  if n then
    require("src.hud").showBanner(n[1], n[2])
  end
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
  rays[#rays + 1] = { x = x, age = -(delay or 0), warn = 1.05, life = 0.45, w = 20, hit = false, started = false }
end

-- The heavens answering a wrong star: bolts all round, and rays where he stands
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
      local chunk = sw.round >= #T.rounds and e.hp or math.ceil(sw.p4hp / #T.rounds)
      sw.finishing = true
      enemies.damage(e, chunk, 0, 0, 0, false, nil)
      sw.finishing = false
      audio.playAt("explosion", e.body.x, e.body.y, 0.7, 1.3)
      audio.playAt("sw_chime", nd.x, nd.y, 1, 0.8)
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
    answer(e, sw, e.lastPx or sw.home[1])
  end
end

def.extraHit = function(e, x, y)
  local sw = e.sw
  return sw ~= nil and sw.ph == 4 and sw.mode == "fight" and sw.stage == "input" and nodeAt(sw, x, y) ~= nil
end

def.filter = function(e, amount)
  local sw = ensure(e)
  if sw.finishing then
    return amount
  end
  if sw.intro > 0 or sw.mode ~= "fight" or sw.pending or sw.blinking then
    return 0
  end
  local ax, ay = center(e)
  if sw.ph == 4 then
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
  local l = { { cx, cy, 120 * (sw and sw.size or 1) ^ 0.7, 0.95, 0.9, 0.7, 0.6 * k } }
  if sw and sw.nodes then
    for _, nd in ipairs(sw.nodes) do
      local n = math.max(nd.lit, nd.solved)
      if n > 0.05 then
        l[#l + 1] = { nd.x, nd.y, 70, 1, 0.95, 0.65, 0.7 * n }
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

-- The orbs -------------------------------------------------------------------------------------------------

local function orbCount(sw)
  return ({ 2, 4, 4, 6 })[sw.ph]
end

-- Where orb i hangs: on a flattened ring round the core
local function orbPos(e, sw, i)
  local o = sw.orbs[i]
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
  if sw.ph >= 2 and sw.mode == "fight" then
    sw.orbT = sw.orbT - dt
    if sw.orbT <= 0 then
      sw.orbT = T.orbEvery[sw.ph]
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
    -- on him: three round where he stands
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
    local aim = math.atan2(py - cy, px - cx)
    for k = -1, 1 do
      local ang = aim + k * 0.25
      bolts[#bolts + 1] = { x = cx, y = cy, vx = math.cos(ang) * T.boltSpeed, vy = math.sin(ang) * T.boltSpeed, life = 5, dmg = dmg }
    end
  end
  audio.playAt("sw_orb", cx, cy, 0.5, 1.5)
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

-- The minions of each interlude: { kind, count } by the turn just ended
local MINIONS = {
  { { "cloudray", 3 }, { "sentinel", 1 } },
  { { "windspirit", 2 }, { "sentinel", 2 }, { "starmoth", 2 } },
  { { "cloudray", 4 }, { "windspirit", 2 }, { "sentinel", 2 } },
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
  audio.playAt("sw_vanish", cx, cy, 1, 1)
  shake(0.6)
  effects.ring(cx, cy, 90, { 1, 0.95, 0.7 })
  require("src.hud").showBanner("The Heavens Call", "He slips out of the world. His servants come in his stead")
  local swarm = {}
  local at = a and a.cx or cx
  local w = a and a.w or 700
  local ground = a and a.floorY or cy + 200
  for _, grp in ipairs(MINIONS[sw.pending - 1] or {}) do
    for _ = 1, grp[2] do
      local side = love.math.random() < 0.5 and -1 or 1
      local x = at + side * (w * (0.12 + love.math.random() * 0.3))
      local y = ground - 110 - love.math.random() * 170
      local m = enemies.spawn(grp[1], x, y, math.max(1.5, e.toughness * 0.55), e.level, grp[1] == "cloudray" and swarm or nil)
      m.minion = true
      m.seesPlayer = true
      if swarm.members then
        swarm.awake = true
      end
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
end

local function updateStar(e, dt, world, player, px, py)
  local sw = ensure(e)
  local b = e.body
  local a = e.arena
  local cx, cy = center(e)
  sw.t = sw.t + dt
  e.lastPx = px
  e.state, e.seesPlayer = "chase", true
  audio.setBoss(true)
  local fight = sw.mode == "fight" and sw.intro <= 0

  -- Size and presence: he grows into each turn; between turns he is faint
  local aimAlpha = (sw.mode == "interlude" and 0.3) or (sw.blinking and 0.0) or 1
  sw.alpha = sw.alpha + (aimAlpha - sw.alpha) * math.min(1, dt * 5)
  local grow = sw.mode == "emerge" and 2.2 or 1.2
  local sizeT = sw.sizeT or 1
  sw.size = sw.size + (sizeT - sw.size) * math.min(1, dt * grow)

  -- Where he wants to be, and how he gets there
  local tx, ty = sw.home[1], sw.home[2]
  local w = a and a.w or 500
  local m = sw.move
  local dashing = false
  if sw.mode == "interlude" then
    tx, ty = sw.home[1] + math.sin(sw.t * 0.4) * w * 0.2, sw.home[2] - 150 + math.sin(sw.t * 0.9) * 14
  elseif sw.ph == 4 then
    tx, ty = sw.home[1] + math.sin(sw.t * 0.25) * 18, sw.home[2] + math.sin(sw.t * 0.8) * 4
  else
    local fast = ({ 0.5, 0.7, 0.45 })[sw.ph]
    local reach = ({ 0.34, 0.4, 0.44 })[sw.ph]
    tx = sw.home[1] + math.sin(sw.t * fast) * w * reach
    ty = sw.home[2] + math.sin(sw.t * fast * 1.9) * 42 - (sw.ph == 3 and 40 or 0)
  end
  if fight and (sw.ph == 1 or sw.ph == 2) then
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
  -- Turn three: he blinks, to the far side of the sky, and the rays come as he arrives
  if fight and sw.ph == 3 then
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
      sw.mode, sw.emT = "emerge", 2.0
      audio.playAt("sw_grow", cx, cy, 1, 1)
      effects.ring(cx, cy, 60, { 1, 0.95, 0.7 })
    end
    return
  end
  if sw.mode == "emerge" then
    sw.emT = sw.emT - dt
    if sw.emT <= 0 then
      sw.mode = "fight"
      effects.ring(cx, cy, 120, { 1, 0.95, 0.7 })
      effects.ring(cx, cy, 80, { 1, 0.85, 0.5 })
      audio.playAt("explosion", cx, cy, 1, 0.5)
      shake(0.7)
      startTurn(e, sw, sw.pending)
      sw.pending = nil
    end
    return
  end

  -- The hand: it rises over a second, turns, and now and then reverses (after a pause)
  local ox, oy = origin(e, sw)
  sw.handT = math.min(1, sw.handT + dt / 1.1)
  sw.flipT = sw.flipT - dt
  if sw.flipT <= 0 then
    sw.flipT = 6 + love.math.random() * 4
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
    sw.boltT = T.boltEvery[sw.ph]
    fireBolts(e, sw, px, py)
  end
  -- Gravity wells
  if sw.ph == 2 then
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
    if sw.rayT <= 0 and not sw.blinking and (sw.ph == 3 or sw.stage == "input") then
      sw.rayT = T.rayEvery[sw.ph]
      rayVolley(e, sw, a, px)
    end
  end
  if sw.ph == 4 then
    updateNodes(e, sw, dt)
  end
end

-- Draw --------------------------------------------------------------------------------------------------

local CREAM, CREAM_S, CREAM_H = { 0.97, 0.94, 0.86 }, { 0.66, 0.74, 0.92 }, { 1.0, 1.0, 0.97 }
local GOLD_L, GOLD, GOLD_D = { 1.0, 0.92, 0.55 }, { 0.93, 0.70, 0.22 }, { 0.55, 0.38, 0.12 }
local A = 1 -- (how solid he is this frame)

local function col(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (a or 1) * A)
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

-- An arm of cloud: puffs along a curve from the shoulder to a golden gauntlet
local function arm(sx, sy, hx, hy, bulge, t, flip)
  local dx, dy = hx - sx, hy - sy
  local len = math.max(1, hypot(dx, dy))
  local qx, qy = (sx + hx) / 2 - dy / len * bulge, (sy + hy) / 2 + dx / len * bulge
  local n = math.max(6, math.floor(len / 9))
  for i = 0, n do
    local u = i / n
    local x = (1 - u) ^ 2 * sx + 2 * (1 - u) * u * qx + u ^ 2 * hx
    local y = (1 - u) ^ 2 * sy + 2 * (1 - u) * u * qy + u ^ 2 * hy
    local r = 7.5 - u * 3 + math.sin(t * 2 + i * 1.3) * 0.7
    col(CREAM_S, 0.95)
    love.graphics.circle("fill", x + 1, y + 1.5, r)
    col(CREAM)
    love.graphics.circle("fill", x, y, r)
    col(CREAM_H, 0.9)
    love.graphics.circle("fill", x - r * 0.3, y - r * 0.35, r * 0.45)
  end
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

-- An orb: a gold ball with a spike through it, up and down, as in the old paintings of the stars
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
  A = sw and sw.alpha or 1
  if A < 0.02 then
    return
  end
  -- (faint and shimmering between turns)
  if sw and sw.mode == "interlude" then
    A = A * (0.8 + 0.2 * math.sin(t * 9))
  end
  local bob = math.sin(t * 1.3) * 2
  love.graphics.push()
  love.graphics.translate(math.floor(cx), math.floor(cy + bob))
  love.graphics.scale(size, size)
  -- Arms of cloud first, behind: the sweeping ones follow the hand of light; the others hang and sway
  local active = {}
  if sw and sw.mode == "fight" and sw.intro <= 0 then
    for _, ang in ipairs(hands(sw)) do
      active[math.cos(ang) >= 0 and 1 or -1] = ang
    end
  end
  for _, side in ipairs({ -1, 1 }) do
    local sx, sy = side * 10, -8
    local ang = active[side]
    if ang then
      local reach = 46 + 36 * (sw.handT or 1)
      arm(sx, sy, sx + math.cos(ang) * reach, sy + 10 + math.sin(ang) * reach, 8 * side, t, side)
    else
      local lift = (sw and sw.mode ~= "fight") and -18 or 0
      arm(sx, sy, side * (34 + math.sin(t * 1.5 + side) * 3), 20 + lift + math.sin(t * 1.7 + side * 2) * 5, -side * 14, t, side)
    end
  end
  -- The lance below: a long kite of cream and gold, and feathered plates at his sides
  for _, side in ipairs({ -1, 1 }) do
    for k = 1, 3 do
      local sway = math.sin(t * 1.4 + k + side) * 1.5
      col(GOLD_D)
      love.graphics.polygon("fill", side * 5, -2 + k * 7, side * (24 - k * 3) + sway, 2 + k * 9, side * (19 - k * 3) + sway, 12 + k * 9, side * 4, 9 + k * 7)
      col(CREAM)
      love.graphics.polygon("fill", side * 5, -2 + k * 7, side * (22 - k * 3) + sway, 2 + k * 9, side * (18 - k * 3) + sway, 10 + k * 9, side * 4, 8 + k * 7)
      col(GOLD_L, 0.9)
      love.graphics.line(side * 5, -2 + k * 7, side * (22 - k * 3) + sway, 2 + k * 9)
    end
  end
  col(GOLD_D)
  love.graphics.polygon("fill", -7, 2, 0, -6, 7, 2, 3.5, 36, 0, 70, -3.5, 36)
  col(CREAM)
  love.graphics.polygon("fill", -5.5, 2, 0, -4, 5.5, 2, 2.6, 36, 0, 66, -2.6, 36)
  col(GOLD)
  love.graphics.polygon("fill", 0, -4, 1.6, 20, 0, 66, -1.6, 20)
  col(GOLD_L)
  love.graphics.polygon("fill", 0, 22, 1, 28, 0, 52, -1, 28)
  -- The core: a sun in a ring, with spikes up and down and to the sides
  local pulse = 1 + math.sin(t * 2.6) * 0.06
  col(GOLD_D)
  love.graphics.polygon("fill", 0, -34, 3, -14, 0, -10, -3, -14)
  love.graphics.polygon("fill", 0, 14, 3, -6, 0, -10, -3, -6)
  love.graphics.polygon("fill", -22, -10, -6, -13, -4, -10, -6, -7)
  love.graphics.polygon("fill", 22, -10, 6, -13, 4, -10, 6, -7)
  col(GOLD_D)
  love.graphics.circle("fill", 0, -10, 14 * pulse)
  col(GOLD)
  love.graphics.circle("fill", 0, -10, 12 * pulse)
  col(GOLD_L)
  love.graphics.circle("fill", 0, -10, 8 * pulse)
  col({ 1, 1, 0.92 })
  love.graphics.circle("fill", 0, -10, 4 * pulse)
  col(GOLD_L, 0.9)
  love.graphics.setLineWidth(1)
  love.graphics.circle("line", 0, -10, 16)
  -- The halo: a tilted ring over his head, with a spike on top and a glint that travels round it
  local halo = ellipsePoints(26, 8, 32)
  love.graphics.push()
  love.graphics.translate(0, -44)
  love.graphics.rotate(math.sin(t * 0.5) * 0.06)
  love.graphics.setLineWidth(3)
  col(GOLD_D)
  love.graphics.polygon("line", halo)
  love.graphics.setLineWidth(1.5)
  col(GOLD_L)
  love.graphics.polygon("line", halo)
  col(GOLD)
  love.graphics.polygon("fill", 0, -22, 3, -9, 0, -6, -3, -9)
  love.graphics.polygon("fill", -33, 0, -24, -3, -24, 3)
  love.graphics.polygon("fill", 33, 0, 24, -3, 24, 3)
  local ga = t * 1.4
  love.graphics.setColor(1, 1, 0.9, A)
  love.graphics.circle("fill", math.cos(ga) * 26, math.sin(ga) * 8, 2)
  love.graphics.pop()
  love.graphics.setLineWidth(1)
  love.graphics.pop()
  -- The orbs that ring him, and the white flash of a hit
  if sw then
    local n = orbCount(sw)
    for i, o in ipairs(sw.orbs) do
      if o.vis > 0.03 and i <= 6 then
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

local function drawStarGlow(e)
  local sw = e.sw
  local size = sw and sw.size or 1
  local a = sw and sw.alpha or 1
  local cx, cy = center(e)
  local t = love.timer.getTime()
  local hx, hy = cx, cy - 10 * size
  love.graphics.setBlendMode("add")
  local pulse = 0.8 + 0.2 * math.sin(t * 2)
  love.graphics.setColor(1, 0.9, 0.5, 0.2 * pulse * a)
  love.graphics.circle("fill", hx, hy, 26 * size)
  love.graphics.setColor(1, 0.85, 0.5, 0.07 * a)
  love.graphics.circle("fill", hx, hy, 80 * size)
  love.graphics.setColor(1, 0.95, 0.8, 0.35 * a)
  love.graphics.circle("fill", hx, hy, 7 * size)
  -- the halo's glow, and a clock's twelve ticks turning round it
  local ry = cy - 44 * size
  love.graphics.setLineWidth(1)
  for k = 0, 11 do
    local ang = k / 12 * math.pi * 2 + t * 0.3
    love.graphics.setColor(1, 0.92, 0.55, 0.6 * pulse * a)
    love.graphics.line(cx + math.cos(ang) * 30 * size, ry + math.sin(ang) * 10 * size, cx + math.cos(ang) * (k % 3 == 0 and 36 or 33) * size, ry + math.sin(ang) * (k % 3 == 0 and 12 or 11) * size)
  end
  if not sw then
    love.graphics.setBlendMode("alpha")
    return
  end
  -- The orbs' glow, and a ring closing on one that charges
  for i, o in ipairs(sw.orbs) do
    if o.vis > 0.03 then
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
  if sw.intro <= 0 and sw.mode == "fight" and not sw.pending and not sw.blinking then
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
  end
  love.graphics.setBlendMode("alpha")
end

-- Bolts, orbs, rays and wells, every frame --------------------------------------------------------------------

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
  local floorY, ceilY
  for _, e in ipairs(enemies.all()) do
    if e.kind == "starwarden" and e.arena then
      floorY = e.arena.floorY
      ceilY = e.arena.top - 500
    end
  end
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
end

-- A new fight, or none: nothing of his left flying
local prevClear = enemies.clear
enemies.clear = function()
  prevClear()
  bolts, rays = {}, {}
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
  local cx, cy = center(e)
  for k = 1, 5 do
    effects.ring(cx, cy, 30 + k * 26, { 1, 0.95, 0.65 })
  end
  audio.playAt("explosion", cx, cy, 1, 0.4)
  audio.playAt("sw_grow", cx, cy, 1, 0.6)
  shake(1.0)
  audio.setBoss(false)
end

enemies.UPDATE.starwarden = updateStar
enemies.DRAW.starwarden = drawStar
enemies.GLOW.starwarden = drawStarGlow

return true
