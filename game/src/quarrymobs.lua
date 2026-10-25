-- The creatures of the Old Quarry (the side branch under the east desert), two of them, each with a
-- voice of its own (src.audio):
--   Lamp Wraith   a miner who never left the workings: a pale sheet of a ghost with a hard hat and a
--                 lantern. It hangs asleep among the stalactites, drifts after the hunter, wails, then
--                 lunges with its lantern thrown out. When it cannot reach him it turns to mist,
--                 untouchable, and goes through the rock to come out beside him
--   Cairn Crab    a crab that wears a heap of rubble: a pile of stones until the hunter comes near or a
--                 bullet finds it (a mound shrugs most of a hit off). Awake it scuttles at him, snaps
--                 at close range and lobs stones over the ground between
local enemies = require("src.enemies")
local Body = require("src.body")
local audio = require("src.audio")
local config = require("src.config")
local effects = require("src.effects")

local flowDirection = enemies.flowDirection
local H = enemies.helpers
local center, collider = H.center, H.collider

local function hypot(x, y)
  return math.sqrt(x * x + y * y)
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w or 1, h or 1)
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- Definitions ---------------------------------------------------------------------------------------

local D = enemies.defs
D.wraith = {
  name = "Lamp Wraith",
  w = 12, h = 18, hp = 52, speed = 70, accel = 220,
  sight = 330, forget = 800, damage = 11, lungeRange = 190, lungeSpeed = 255,
  knockback = 0.3, gold = { 6, 12 }, weight = 1.5,
  spriteW = 12, spriteH = 18, scale = 1,
  blood = { 0.55, 0.65, 0.8 },
  desc = "One of the quarry's dead miners, a pale sheet with a hard hat and a lantern. It wails, then flings itself at you with the lamp held out. Lose it behind rock and it turns to mist and comes straight through the wall: nothing hurts it until it is solid again.",
}
D.cairncrab = {
  name = "Cairn Crab",
  ground = true, w = 16, h = 10, hp = 70, speed = 52, jump = 175,
  sight = 220, forget = 700, damage = 13, snapRange = 44,
  knockback = 0.1, gold = { 7, 13 }, weight = 5, pushForce = 200,
  spriteW = 16, spriteH = 10, scale = 1,
  blood = { 0.62, 0.52, 0.38 },
  desc = "A crab that carries a heap of rubble as a shell. Curled up as a pile of stones it shrugs most hits off, and it wakes the moment you are close or a bullet finds it. Awake it scuttles sideways, snaps at close range and lobs stones from further off.",
}
for _, k in ipairs({ "wraith", "cairncrab" }) do
  enemies.order[#enemies.order + 1] = k
end

-- What a hit does: mist is not there to be hit; a crab still a mound takes a quarter
D.wraith.filter = function(e, amount)
  if e.state == "mist" then
    local cx, cy = center(e)
    effects.particle(cx, cy, (love.math.random() - 0.5) * 40, -10, 0.3, { 0.6, 0.7, 0.9 }, 0, true)
    return 0
  end
  return amount
end
D.cairncrab.filter = function(e, amount)
  if e.state == "idle" or e.state == "rise" then
    audio.playAt("clank", e.body.x, e.body.y, 0.35, 0.9)
    if e.state == "idle" then
      e.state, e.timer = "rise", 0.9
    end
    return math.max(1, math.floor(amount * 0.25))
  end
  return amount
end

enemies.VOICES.wraith = { "wraith_moan", 3.5, 8, 1 }
enemies.VOICES.cairncrab = { "crab_chitter", 3, 7, 1 }

D.wraith.light = function(e)
  local cx, cy = center(e)
  local a = e.state == "mist" and 0.05 or (e.state == "sleep" and 0.12 or 0.3)
  if e.state == "wail" then
    a = 0.5
  end
  return { cx + e.facing * 4, cy + 2, 38, 1, 0.72, 0.3, a }
end

-- Drift without collision (mist goes through rock) --------------------------------------------------

local function drift(b, dx, dy)
  b.remX, b.remY = b.remX + dx, b.remY + dy
  local mx = b.remX >= 0 and math.floor(b.remX) or -math.floor(-b.remX)
  local my = b.remY >= 0 and math.floor(b.remY) or -math.floor(-b.remY)
  b.x, b.y = b.x + mx, b.y + my
  b.remX, b.remY = b.remX - mx, b.remY - my
end

-- The wraith ----------------------------------------------------------------------------------------------

local function updateWraith(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.phase = e.phase + dt * (e.state == "wail" and 9 or 3)
  e.attackCd = math.max(0, (e.attackCd or (1 + love.math.random() * 1.5)) - dt)
  if e.state == "sleep" then
    if e.seesPlayer and dist < def.sight then
      e.state = "chase"
      audio.playAt("wraith_moan", cx, cy, 0.9, 1)
    else
      return
    end
  end
  local collide = collider(e, world)
  e.contactMul = e.state == "lunge" and 1.6 or (e.state == "mist" and 0 or 0.35)
  if e.state == "mist" then
    -- Straight through the rock at the hunter, until it is clear of it
    e.mistT = e.mistT + dt
    local d = math.max(1, dist)
    drift(b, (px - cx) / d * 92 * dt, (py - cy) / d * 92 * dt)
    b.vx, b.vy = 0, 0
    e.facing = px >= cx and 1 or -1
    local free = not Body.terrainOverlaps(world, b.x, b.y, b.w, b.h)
    if free and e.mistT > 0.8 and (e.seesPlayer or e.mistT > 3) then
      e.state, e.unseenT = "chase", 0
      audio.playAt("wraith_phase", cx, cy, 0.8, 1.4)
    end
    return
  end
  if e.state == "chase" then
    e.unseenT = e.seesPlayer and 0 or (e.unseenT or 0) + dt
    if e.unseenT > 2.5 and dist > 70 and e.stun <= 0 then
      e.state, e.mistT = "mist", 0
      audio.playAt("wraith_phase", cx, cy, 0.9, 0.8)
      return
    end
  end
  local wantx, wanty = 0, 0
  if e.state == "chase" then
    if e.seesPlayer then
      -- hang about the hunter, a little above him, not on top of him
      local d = math.max(1, dist)
      local k = clamp((dist - 85) / 60, -0.6, 1)
      wantx, wanty = (px - cx) / d * def.speed * k, (py - 20 - cy) / d * def.speed * k
    else
      local fx, fy = flowDirection(world, cx, cy, px, py - 4)
      if fx then
        wantx, wanty = fx * def.speed, fy * def.speed
      end
    end
    wanty = wanty + math.sin(e.phase * 0.8) * 10
    if e.seesPlayer and dist < def.lungeRange and dist > 45 and e.attackCd <= 0 and e.stun <= 0 then
      e.state, e.timer = "wail", 0.8
      audio.playAt("wraith_wail", cx, cy, 1, 0.95 + love.math.random() * 0.1)
    end
  elseif e.state == "wail" then
    -- the lamp flares, the sheet rears back: it has made up its mind
    e.timer = e.timer - dt
    e.facing = px >= cx and 1 or -1
    b.vx, b.vy = b.vx * math.exp(-6 * dt), b.vy * math.exp(-6 * dt)
    if e.timer <= 0 then
      local d = math.max(1, dist)
      e.state, e.timer = "lunge", 0.55
      b.vx, b.vy = (px - cx) / d * def.lungeSpeed, (py - cy) / d * def.lungeSpeed
      audio.playAt("wraith_phase", cx, cy, 0.8, 1.2)
    end
  elseif e.state == "lunge" then
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.state, e.timer = "recover", 0.7
      e.attackCd = 2.2 + love.math.random() * 1.6
    end
  elseif e.state == "recover" then
    e.timer = e.timer - dt
    b.vx, b.vy = b.vx * math.exp(-5 * dt), b.vy * math.exp(-5 * dt)
    if e.timer <= 0 then
      e.state = "chase"
    end
  end
  if e.stun <= 0 and (e.state == "chase") then
    local step = def.accel * dt
    b.vx = b.vx < wantx and math.min(b.vx + step, wantx) or math.max(b.vx - step, wantx)
    b.vy = b.vy < wanty and math.min(b.vy + step, wanty) or math.max(b.vy - step, wanty)
  end
  if e.state ~= "lunge" then
    e.facing = px >= cx and 1 or -1
  end
  local hit = false
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.3
    hit = true
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.3
    hit = true
  end
  if hit and e.state == "lunge" then
    e.state, e.timer = "recover", 0.6
    e.attackCd = 2.5
  end
end

local WR = {
  robe = { 0.62, 0.69, 0.80 }, dark = { 0.36, 0.42, 0.56 }, light = { 0.82, 0.88, 0.96 }, void = { 0.04, 0.05, 0.09 },
  hat = { 0.42, 0.30, 0.20 }, hatLight = { 0.62, 0.46, 0.30 }, lamp = { 1, 0.72, 0.3 },
}

local function drawWraith(e)
  local b = e.body
  local white = e.flash > 0
  local alpha = e.state == "mist" and 0.28 or 1
  local function color(c, a)
    if white then
      love.graphics.setColor(1, 1, 1, alpha)
    else
      love.graphics.setColor(c[1], c[2], c[3], (a or 1) * alpha)
    end
  end
  local f = e.facing
  local mid, y = b.x + b.w / 2, b.y
  local st = e.state
  local asleep = st == "sleep"
  local rear = st == "wail" and 1 or 0
  local stretch = st == "lunge" and 3 or 0
  local ph = e.phase
  -- (the sheet: a tapering robe, its hem waving)
  local top = y + 6
  local bottom = y + 16 + stretch + (asleep and -4 or 0)
  for row = top, bottom do
    local k = (row - top) / math.max(1, bottom - top)
    local halfW = 3 + k * 2 + (st == "lunge" and -k or 0)
    local sway = math.sin(ph * 0.9 + row * 0.55) * (0.6 + k * 1.6) - f * k * (st == "lunge" and 3 or 0)
    color(k > 0.55 and WR.dark or WR.robe)
    rect(mid - halfW + sway, row, halfW * 2, 1)
  end
  -- the ragged hem: ribbons that wave
  for i = -2, 2 do
    local len = 2 + (i + 2) % 3
    color(WR.robe)
    rect(mid + i * 2 + math.sin(ph + i) * 1.2, bottom + 1, 2, len + (st == "lunge" and 2 or 0))
  end
  color(WR.light)
  rect(mid - 3, top + 1, 1, 6)
  -- head under a hard hat: a dark hollow face, two eyes (drawn in the glow)
  color(WR.robe)
  rect(mid - 3, y + 2, 6, 5)
  color(WR.void)
  rect(mid - 2, y + 3, 4, 3)
  color(WR.hat)
  rect(mid - 4, y + 1 - rear, 8, 2)
  rect(mid - 3, y - 1 - rear, 6, 2)
  color(WR.hatLight)
  rect(mid - 3, y - 1 - rear, 6, 1)
  -- the arm and its lantern, swung out on a wail or a lunge
  local ax = mid + f * 3
  local reach = (st == "lunge") and 7 or (st == "wail" and -1 or 3)
  local ay = y + 9 - (st == "wail" and 2 or 0)
  color(WR.robe)
  rect(math.min(ax, ax + f * reach), ay, math.abs(reach) + 1, 1)
  local lx = mid + f * (4 + reach)
  local ly = ay + 1 + math.floor(math.sin(ph * 0.7) * (asleep and 0 or 1.2) + 0.5)
  color(WR.dark)
  rect(lx - 1, ly, 3, 4)
  color(WR.lamp)
  rect(lx, ly + 1, 1, 2)
end

local function drawWraithGlow(e)
  local b = e.body
  local st = e.state
  if st == "mist" then
    return
  end
  local f = e.facing
  local mid, y = b.x + b.w / 2, b.y
  local ph = e.phase
  local k = st == "sleep" and 0.35 or 1
  local reach = (st == "lunge") and 7 or (st == "wail" and -1 or 3)
  local ay = y + 9 - (st == "wail" and 2 or 0)
  local lx = mid + f * (4 + reach)
  local ly = ay + 1 + math.floor(math.sin(ph * 0.7) * (st == "sleep" and 0 or 1.2) + 0.5)
  local flare = st == "wail" and 1 or 0
  love.graphics.setColor(1, 0.75, 0.3, (0.8 + 0.2 * math.sin(ph * 3)) * k)
  rect(lx, ly + 1, 1, 2)
  if flare > 0 then
    love.graphics.setColor(1, 0.8, 0.4, 0.35)
    rect(lx - 2, ly - 1, 5, 6)
  end
  -- the hat lamp
  love.graphics.setColor(1, 0.85, 0.45, k)
  rect(mid + f * 2 - (f < 0 and 0 or 0), y + (st == "wail" and -1 or 1) - 1, 2, 1)
  if st ~= "sleep" then
    love.graphics.setColor(1, 0.7, 0.25)
    rect(mid - 2, y + 4)
    rect(mid + 1, y + 4)
  end
end

-- The crab ------------------------------------------------------------------------------------------------

local rocks = {}

local function updateCrab(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local collide = collider(e, world)
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
  e.phase = e.phase + math.abs(b.vx) * dt * 0.2
  e.contactMul = e.state == "hop" and 1.8 or 0.4
  e.hurlCd = math.max(0, (e.hurlCd or 1.5) - dt)
  local want = 0
  if e.state == "idle" then
    -- a pile of stones; it wakes when the hunter is close, or when shot (def.filter)
    b.vx = 0
    if (e.seesPlayer and dist < 95) or dist < 40 or e.hp < e.maxHp then
      e.state, e.timer = "rise", 0.9
      audio.playAt("crab_rumble", cx, cy, 0.9, 1)
    end
  elseif e.state == "rise" then
    e.timer = e.timer - dt
    b.vx = 0
    if love.math.random() < dt * 20 then
      effects.particle(cx + (love.math.random() - 0.5) * 14, b.y + 3, (love.math.random() - 0.5) * 30, -20 - love.math.random() * 30, 0.4, { 0.55, 0.47, 0.35 }, 200)
    end
    if e.timer <= 0 then
      e.state = "scuttle"
      e.cooldown = 0.5
      audio.playAt("crab_chitter", cx, cy, 1, 0.9)
    end
  elseif e.state == "scuttle" then
    e.facing = px < cx and -1 or 1
    if e.seesPlayer or dist < def.sight then
      want = e.facing * def.speed * (dist < 55 and 0.4 or 1)
    end
    if dist > def.forget then
      e.state = "idle"
    end
    if e.stun <= 0 and e.cooldown <= 0 and e.grounded then
      if dist < def.snapRange and math.abs(py - cy) < 22 then
        e.state, e.timer = "snap", 0.35
        audio.playAt("crab_chitter", cx, cy, 0.8, 1.3)
      elseif e.seesPlayer and dist > 90 and dist < 240 and e.hurlCd <= 0 then
        e.state, e.timer, e.thrown = "hurl", 0.8, 0
        audio.playAt("crab_rumble", cx, cy, 0.7, 1.4)
      end
    end
  elseif e.state == "snap" then
    e.facing = px < cx and -1 or 1
    e.timer = e.timer - dt
    b.vx = b.vx * math.exp(-10 * dt)
    if e.timer <= 0 then
      e.state, e.timer = "hop", 0.35
      b.vx, b.vy = e.facing * 175, -110
      audio.playAt("crab_snap", cx, cy, 1, 1)
    end
  elseif e.state == "hop" then
    e.timer = e.timer - dt
    if e.timer <= 0 and e.grounded then
      e.state, e.cooldown = "scuttle", 1.3
    end
  elseif e.state == "hurl" then
    e.facing = px < cx and -1 or 1
    e.timer = e.timer - dt
    b.vx = b.vx * math.exp(-10 * dt)
    if e.timer < 0.3 and e.thrown == 0 then
      e.thrown = 1
      audio.playAt("crab_hurl", cx, cy, 1, 0.95)
      local g = 380
      local t = clamp(dist / 150, 0.5, 1.2)
      for i = -1, 1 do
        local tx, ty = px + i * 16, py
        rocks[#rocks + 1] = {
          x = cx + e.facing * 6, y = b.y,
          vx = (tx - cx) / t * (0.92 + love.math.random() * 0.16),
          vy = (ty - b.y) / t - 0.5 * g * t,
          life = 4, dmg = math.max(1, math.floor(8 * e.dmgMul + 0.5)),
        }
      end
      effects.particle(cx + e.facing * 6, b.y, 0, -30, 0.3, { 0.6, 0.5, 0.38 }, 100)
    end
    if e.timer <= 0 then
      e.state, e.cooldown = "scuttle", 1
      e.hurlCd = 3.5 + love.math.random() * 2
    end
  end
  if e.state == "scuttle" then
    local accel = e.grounded and 700 or 250
    b.vx = b.vx < want and math.min(want, b.vx + accel * dt) or math.max(want, b.vx - accel * dt)
    -- (clicks as it runs)
    e.stepT = (e.stepT or 0) - dt * math.abs(b.vx) / 40
    if e.stepT <= 0 and e.grounded and math.abs(b.vx) > 10 then
      e.stepT = 1
      audio.playAt("crab_scuttle", cx, b.y + b.h, 0.35, 0.9 + love.math.random() * 0.3)
    end
  end
  b.vy = math.min(b.vy + config.gravity * dt, 450)
  if Body.moveX(b, collide, b.vx * dt, 4) then
    if e.grounded and e.state == "scuttle" then
      b.vy = -def.jump
    end
    if e.state ~= "hop" then
      b.vx = 0
    end
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = 0
  end
  if e.grounded and b.vy >= 0 then
    Body.snapDown(b, collide, 4)
  end
end

local CR = {
  shell = { 0.62, 0.50, 0.36 }, shellDark = { 0.38, 0.30, 0.22 }, shellLight = { 0.80, 0.68, 0.50 },
  claw = { 0.70, 0.38, 0.26 }, clawDark = { 0.46, 0.22, 0.16 }, leg = { 0.30, 0.22, 0.17 },
  stoneA = { 0.52, 0.46, 0.38 }, stoneB = { 0.40, 0.36, 0.30 }, stoneC = { 0.64, 0.57, 0.46 },
}

local function drawCrab(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local f = e.facing
  local mid, y = b.x + b.w / 2, b.y
  local st = e.state
  local mound = st == "idle"
  local lift = 0
  if st == "rise" then
    lift = math.floor((1 - math.max(0, e.timer) / 0.9) * 3 + 0.5)
  end
  local function X(dx)
    return mid + f * dx
  end
  if mound or (st == "rise" and e.timer > 0.45) then
    -- a heap of stones with a crab somewhere under it
    local shake = st == "rise" and math.floor(math.sin(love.timer.getTime() * 50) + 0.5) or 0
    color(CR.stoneB)
    rect(mid - 8 + shake, y + 4, 16, 6)
    color(CR.stoneA)
    rect(mid - 7 + shake, y + 2, 7, 5)
    rect(mid + 1 + shake, y + 3, 6, 6)
    color(CR.stoneC)
    rect(mid - 5 + shake, y + 1, 4, 3)
    rect(mid + 2 + shake, y + 3, 3, 2)
    color(CR.stoneB)
    rect(mid - 2 + shake, y + 5, 3, 2)
    return
  end
  local walk = (e.grounded and math.abs(b.vx) > 4) and math.sin(e.phase * 6) or 0
  local snapUp = (st == "snap" or st == "hurl") and 1 or 0
  -- legs: four a side, alternating as it scuttles
  color(CR.leg)
  for i = -2, 1 do
    local up = ((i + (walk > 0 and 1 or 0)) % 2 == 0) and 1 or 0
    rect(mid + i * 3 - 0, y + 7 - lift, 1, 3 - up)
    rect(mid + i * 3 + 1, y + 9 - up, 1, 1)
  end
  -- the shell: a low dome of cemented rubble
  local top = y + 1 + lift + (st == "hurl" and -1 or 0)
  color(CR.shellDark)
  rect(mid - 7, top + 4, 14, 3)
  color(CR.shell)
  rect(mid - 6, top + 2, 12, 3)
  rect(mid - 4, top, 8, 3)
  color(CR.shellLight)
  rect(mid - 4, top, 5, 1)
  rect(mid - 6, top + 2, 2, 1)
  color(CR.stoneB)
  rect(mid + 1, top + 1, 2, 2)
  rect(mid - 5, top + 4, 2, 1)
  -- eyes on stalks
  color(CR.leg)
  rect(X(3), top - 1 - snapUp, 1, 2)
  rect(X(5), top - 1 - snapUp, 1, 2)
  -- claws forward off the shell's front: raised for a snap or a throw, open as it hops
  local cy2 = y + 4 - snapUp * 3 - lift - (st == "hop" and 2 or 0)
  local cx0 = f > 0 and mid + 5 or mid - 8
  color(CR.clawDark)
  rect(f > 0 and mid + 5 or mid - 6, cy2 + 3 + snapUp, 2, 1) -- the arm
  color(CR.claw)
  rect(cx0, cy2, 3, 3)
  color(CR.clawDark)
  rect(cx0 + (f > 0 and 2 or 0), cy2 + 1, 1, 1) -- the gap between the pincers
  if st == "snap" or st == "hop" or st == "hurl" then
    color(CR.claw)
    rect(cx0 + (f > 0 and 1 or 0), cy2 - 1, 2, 1) -- (open wide)
    -- a pebble held in the raised claw
    if st == "hurl" and e.thrown == 0 then
      color(CR.stoneC)
      rect(cx0, cy2 - 3, 3, 2)
      color(CR.stoneB)
      rect(cx0, cy2 - 2, 3, 1)
    end
  end
end

local function drawCrabGlow(e)
  local st = e.state
  if st == "idle" then
    -- two glints under the stones, blinking
    local b = e.body
    if math.floor(love.timer.getTime() * 0.7 + e.phase) % 5 == 0 then
      love.graphics.setColor(1, 0.8, 0.35, 0.5)
      rect(b.x + b.w / 2 - 3, b.y + 6)
      rect(b.x + b.w / 2 + 2, b.y + 6)
    end
    return
  end
  if st == "rise" then
    return
  end
  local b = e.body
  local top = b.y + 1 + (st == "hurl" and -1 or 0)
  local snapUp = (st == "snap" or st == "hurl") and 1 or 0
  love.graphics.setColor(1, 0.8, 0.3)
  rect(b.x + b.w / 2 + e.facing * 3, top - 1 - snapUp)
  rect(b.x + b.w / 2 + e.facing * 5, top - 1 - snapUp)
end

-- Hooks ---------------------------------------------------------------------------------------------------------

enemies.UPDATE.wraith = updateWraith
enemies.DRAW.wraith = drawWraith
enemies.GLOW.wraith = drawWraithGlow
enemies.UPDATE.cairncrab = updateCrab
enemies.DRAW.cairncrab = drawCrab
enemies.GLOW.cairncrab = drawCrabGlow

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  local pb = player.body
  for i = #rocks, 1, -1 do
    local s = rocks[i]
    s.life = s.life - dt
    s.vy = s.vy + 380 * dt
    local steps = math.max(1, math.ceil(math.max(math.abs(s.vx), math.abs(s.vy)) * dt / 2))
    local gone = s.life <= 0
    for _ = 1, steps do
      if gone then
        break
      end
      s.x, s.y = s.x + s.vx * dt / steps, s.y + s.vy * dt / steps
      if world:isSolid(s.x, s.y) then
        for _ = 1, 5 do
          effects.particle(s.x, s.y, (love.math.random() - 0.5) * 70, -love.math.random() * 60, 0.5, { 0.58, 0.5, 0.38 }, 300)
        end
        audio.playAt("crab_rock", s.x, s.y, 0.5, 0.9 + love.math.random() * 0.3)
        gone = true
      elseif not player.dead and overlaps(s.x - 2, s.y - 2, 4, 4, pb.x, pb.y, pb.w, pb.h) then
        player:hurt(s.dmg, s.x - s.vx * 0.05, s.y - s.vy * 0.05, "cairncrab")
        for _ = 1, 6 do
          effects.particle(s.x, s.y, (love.math.random() - 0.5) * 70, -love.math.random() * 60, 0.5, { 0.58, 0.5, 0.38 }, 300)
        end
        gone = true
      end
    end
    if gone then
      table.remove(rocks, i)
    end
  end
end

local prevDraw = enemies.afterDraw
enemies.afterDraw = function(view)
  if prevDraw then
    prevDraw(view)
  end
  for _, s in ipairs(rocks) do
    love.graphics.setColor(0.36, 0.31, 0.25)
    rect(s.x - 2, s.y - 2, 4, 4)
    love.graphics.setColor(0.66, 0.58, 0.44)
    rect(s.x - 2, s.y - 2, 3, 2)
  end
end

local prevClear = enemies.clear
enemies.clear = function()
  prevClear()
  rocks = {}
end

return true
