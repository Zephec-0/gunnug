-- Three monsters that bring the hunter's conditions (src.status) with them, so the bottle has something to answer to:
--   Arc Beetle   a beetle that builds up a charge, then lets it go in a ring of arcs: Shocked, and worse for a hunter who is
--                Soaked. Standing in water it charges the whole pool (fluids.zap). Hollows, and the Old Mine's dry ground
--   Torchbearer  a skeleton miner's cousin: the same shambling AI (keeps its distance, winds up, throws, shooting it does
--                not interrupt the throw) but with a torch and a bandolier of fire bottles, a longer arm and a faster
--                throw. Burning where one lands; the torch lights spilt oil and gas it passes. Fire can't hurt it
--   Tar Crawler  a slug of black pitch that walks the floor, the walls and the roof alike, tracking the hunter over
--                whatever it is on and dropping on him from above. It leaves a trail of oil, spits globs (Oiled), bursts
--                into a pool when it dies, and burns if a flame finds it
-- (and the stormglass, src.livewire, is their environment cousin: glass shards that spark and shock.)
local enemies = require("src.enemies")
local Body = require("src.body")
local audio = require("src.audio")
local config = require("src.config")
local effects = require("src.effects")
local fluids = require("src.fluids")
local status = require("src.status")

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

-- Definitions ---------------------------------------------------------------------------------------------

local D = enemies.defs
D.arcbeetle = {
  name = "Arc Beetle",
  ground = true, w = 12, h = 7, hp = 40, speed = 46, jump = 150,
  sight = 240, forget = 700, damage = 6,
  knockback = 0.3, gold = { 4, 9 }, weight = 2,
  spriteW = 12, spriteH = 8, scale = 1,
  blood = { 0.55, 0.8, 1.0 },
  desc = "A beetle with a coil of charge under its shell. It crawls close, glows, then lets go in a ring of arcs. The current is worse on anyone soaked, and in water it runs through the whole pool: don't be in it, and don't let it be.",
}
D.torchbearer = {
  name = "Torchbearer",
  noHitStun = true, -- (like the miner: shooting it does not stop the throw; shoot the bottle instead)
  ground = true, w = 10, h = 19, hp = 30, speed = 42, jump = 230, fireproof = true,
  sight = 340, forget = 560, damage = 9,
  knockback = 0.45, gold = { 6, 12 }, weight = 3, pushForce = 260,
  throwRange = 330, holdMin = 110, holdMax = 210, -- (the miner's 230 / 80 / 150: a longer arm, so it stands further off)
  throwCooldown = 2.4, windup = 0.42, throwGravity = 360,
  spriteW = 10, spriteH = 19, scale = 1,
  blood = { 0.8, 0.72, 0.55 },
  desc = "A skeleton miner who carried a torch down and never put it out. It shambles after you the way the miners do, keeping its distance, but throws farther and faster: bottles of burning oil, with a bandolier of them across its ribs. Its torch lights any oil or gas it passes. Fire can't hurt it.",
}
D.tarcrawler = {
  name = "Tar Crawler",
  ground = true, w = 10, h = 8, hp = 44, speed = 34, jump = 120,
  sight = 280, forget = 700, damage = 5,
  knockback = 0.2, gold = { 5, 10 }, weight = 4, pushForce = 120,
  spriteW = 12, spriteH = 8, scale = 1,
  blood = { 0.12, 0.09, 0.16 },
  desc = "A slug of black pitch that creeps over the floor, up the walls and along the roof, always toward you, and drops on you if you pass beneath. It leaves oil wherever it goes and spits globs of it to coat you. Oil on its own is harmless: keep it away from flames, or lead it to them.",
}
for _, k in ipairs({ "arcbeetle", "torchbearer", "tarcrawler" }) do
  enemies.order[#enemies.order + 1] = k
end
enemies.VOICES.arcbeetle = { "wisp_crackle", 4, 9, 0.5 }
enemies.VOICES.torchbearer = { "miner_yap", 3.5, 8, 1 }
enemies.VOICES.tarcrawler = { "crab_chitter", 5, 10, 0.6 }

D.arcbeetle.light = function(e)
  local cx, cy = center(e)
  local a = e.state == "charge" and (0.3 + 0.5 * (1 - math.max(0, e.timer) / 0.9)) or 0.18
  return { cx, cy, e.state == "charge" and 64 or 30, 0.5, 0.78, 1.0, a }
end
D.torchbearer.light = function(e)
  local cx, cy = center(e)
  return { cx + e.facing * 5, cy - 4, 78, 1.0, 0.62, 0.28, 0.7 }
end

-- Shared movement (the beetle) ------------------------------------------------------------------------------

-- Gravity, steering to `want` (px/s) and stepping the body. Jumps small ledges when blocked while walking.
local function move(e, dt, world, want, accelG, accelA, walking)
  local b, def = e.body, e.def
  local collide = collider(e, world)
  e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
  local accel = e.grounded and (accelG or 600) or (accelA or 250)
  b.vx = b.vx < want and math.min(want, b.vx + accel * dt) or math.max(want, b.vx - accel * dt)
  b.vy = math.min(b.vy + config.gravity * dt, 450)
  if Body.moveX(b, collide, b.vx * dt, 4) then
    if e.grounded and walking then
      b.vy = -def.jump
    end
    b.vx = 0
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = 0
  end
  if e.grounded and b.vy >= 0 then
    Body.snapDown(b, collide, 4)
  end
  return collide
end

-- Arc Beetle ----------------------------------------------------------------------------------------------

local function discharge(e, world, player, px, py)
  local cx, cy = center(e)
  audio.playAt("wisp_crackle", cx, cy, 1, 1.4)
  effects.ring(cx, cy, 44, { 0.6, 0.85, 1 })
  for i = 1, 14 do
    local a = (i / 14) * math.pi * 2
    for k = 1, 5 do
      local r = 8 + k * 7 + love.math.random() * 4
      effects.particle(cx + math.cos(a) * r, cy + math.sin(a) * r * 0.7, math.cos(a) * 20, math.sin(a) * 20, 0.25, { 0.75, 0.92, 1 }, 0, true)
    end
  end
  require("src.camera").shake(0.1)
  -- through the water it stands in
  if fluids.waterAt(cx, cy) or fluids.waterAt(cx, e.body.y + e.body.h + 2) then
    fluids.zap(cx, cy, 8)
  end
  if player.dead then
    return
  end
  local dx, dy = px - cx, py - cy
  if hypot(dx, dy * 1.4) < 46 then
    local dmg = math.floor(8 * e.dmgMul * status.shockMult(player) + 0.5)
    player:hurt(dmg, cx, cy, "arcbeetle")
    status.apply(player, "shocked", 0.8)
  end
end

local function updateBeetle(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.phase = e.phase + math.abs(b.vx) * dt * 0.25
  e.contactMul = 0.35
  if e.state == "idle" then
    if (e.seesPlayer and dist < def.sight) or dist < 50 then
      e.state = "crawl"
    else
      move(e, dt, world, 0, 600, 250, false)
      return
    end
  end
  e.cooldown = math.max(0, (e.cooldown or 1) - dt)
  local want = 0
  if e.state == "crawl" then
    e.facing = px < cx and -1 or 1
    if e.seesPlayer or dist < def.sight then
      want = e.facing * def.speed * (dist < 40 and 0.3 or 1)
    end
    if dist > def.forget then
      e.state = "idle"
    end
    if e.stun <= 0 and e.cooldown <= 0 and e.grounded and ((dist < 62 and math.abs(py - cy) < 28) or fluids.waterAt(cx, cy)) and e.seesPlayer then
      e.state, e.timer = "charge", 0.9
      audio.playAt("wisp_crackle", cx, cy, 0.8, 0.8)
    end
  elseif e.state == "charge" then
    e.timer = e.timer - dt
    if love.math.random() < dt * 40 then
      local a = love.math.random() * math.pi * 2
      effects.particle(cx + math.cos(a) * 9, cy + math.sin(a) * 6, -math.cos(a) * 30, -math.sin(a) * 25, 0.25, { 0.75, 0.92, 1 }, 0, true)
    end
    if e.timer <= 0 then
      discharge(e, world, player, px, py)
      e.state, e.cooldown = "crawl", 2.6 + love.math.random() * 1.2
    end
  end
  move(e, dt, world, want, 700, 250, e.state == "crawl")
end

-- The beetle, third pass (smaller, 11 x 7): a rounded armoured body with a seam of copper coil between the wing cases,
-- six jointed legs, two spark rods on the back and a stinger-like earthing tail that touches the ground as it charges
local function drawBeetle(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local f = e.facing
  local mid, y = b.x + b.w / 2, b.y
  local charging = e.state == "charge"
  local k = charging and (1 - math.max(0, e.timer) / 0.9) or 0
  local walk = (e.grounded and math.abs(b.vx) > 4) and math.floor(e.phase * 3) % 2 or 0
  -- legs: three a side, alternating
  color({ 0.18, 0.17, 0.22 })
  for i = 0, 2 do
    local up = (i + walk) % 2
    rect(mid - 4 + i * 3, y + 5, 1, 2 - up)
  end
  -- the body: two wing cases, steel blue, with a bright edge along the top
  color({ 0.20, 0.23, 0.34 })
  rect(mid - 5, y + 2, 10, 3)
  rect(mid - 4, y + 1, 8, 2)
  rect(mid - 3, y, 6, 1)
  color({ 0.34, 0.40, 0.58 })
  rect(mid - 3, y + 1, 4, 1)
  rect(mid - 2, y, 3, 1)
  color({ 0.12, 0.14, 0.22 })
  rect(mid - 5, y + 4, 10, 1)
  -- the copper coil down the seam, lighting up with the charge
  for i = 0, 4 do
    color({ 0.55 + 0.4 * k, 0.34 + 0.4 * k, 0.16 + 0.5 * k })
    rect(mid - 5 + i * 2, y + 2, 1, 2)
  end
  -- the head, with two bright eyes
  color({ 0.16, 0.16, 0.22 })
  rect(f > 0 and mid + 5 or mid - 7, y + 2, 2, 3)
  color(charging and { 0.9, 0.97, 1 } or { 0.5, 0.78, 1 })
  rect(f > 0 and mid + 6 or mid - 7, y + 2)
  rect(f > 0 and mid + 6 or mid - 7, y + 4)
  -- the earthing tail behind
  color({ 0.55, 0.55, 0.62 })
  rect(f > 0 and mid - 7 or mid + 6, y + 4, 2, 1)
  rect(f > 0 and mid - 8 or mid + 7, y + 5 + (charging and 1 or 0), 1, 2)
  -- two spark rods on the back
  color({ 0.60, 0.62, 0.70 })
  rect(mid - 2, y - 2, 1, 2)
  rect(mid + 1, y - 2, 1, 2)
end

local function drawBeetleGlow(e)
  local b = e.body
  local mid, y = b.x + b.w / 2, b.y
  local k = e.state == "charge" and (1 - math.max(0, e.timer) / 0.9) or 0
  local flick = math.floor(love.timer.getTime() * 20) % 2
  love.graphics.setColor(0.7, 0.9, 1, 0.35 + 0.6 * k)
  rect(mid - 2, y - 3 - flick)
  rect(mid + 1, y - 3 - (1 - flick))
  if k > 0 then
    love.graphics.setColor(0.7, 0.9, 1, 0.10 + 0.25 * k)
    for i = 0, 4 do
      rect(mid - 5 + i * 2, y + 2, 1, 2)
    end
    love.graphics.setColor(0.7, 0.9, 1, 0.05 + 0.12 * k)
    rect(mid - 7, y - 1, 14, 7)
  end
end

-- Torchbearer ---------------------------------------------------------------------------------------------
-- The miner's own AI (src.enemies updateMiner): idle until it sees the hunter, then chase, keeping between holdMin and
-- holdMax, winding up and throwing when he is within throwRange, a wander when it has not seen him, hopping small
-- ledges and shoving props aside.

local bottles = {}

local function throwBottle(e, px, py)
  local def = e.def
  local cx, cy = center(e)
  local hx, hy = cx + e.facing * 5, cy - 7
  local dx, dy = px - hx, py - hy
  -- faster than a stick: it crosses in 0.35-0.8 s (the miner's 0.45-1.0), on a flatter arc
  local T = math.max(0.35, math.min(0.8, math.abs(dx) / 330))
  local g = def.throwGravity
  bottles[#bottles + 1] = {
    x = hx, y = hy,
    vx = dx / T, vy = (dy - 0.5 * g * T * T) / T,
    life = 4, dmg = math.max(1, math.floor(8 * e.dmgMul + 0.5)),
    isBottle = true, isGlob = true,
  }
  audio.playAt("worm_lunge", hx, hy, 0.5, 1.7)
end

local function updateTorch(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local collide = collider(e, world)
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
  e.phase = e.phase + math.abs(b.vx) * dt * 0.2
  if e.state == "idle" and e.seesPlayer and dist < def.sight then
    e.state = "chase"
  elseif e.state == "chase" and dist > def.forget then
    e.state = "idle"
  end
  -- the torch lights what it passes
  e.touchT = (e.touchT or 0) - dt
  if e.touchT <= 0 then
    e.touchT = 0.35
    fluids.ignite(cx + e.facing * 5, cy - 6, 0.3, true)
  end

  local want = 0
  if e.stun > 0 then
    want = nil
    e.windT = nil
  elseif e.state == "chase" then
    local dir = px >= cx and 1 or -1
    e.facing = dir
    if e.windT then
      want = 0
      e.windT = e.windT - dt
      if e.windT <= 0 then
        e.windT = nil
        e.throwT = 0.3
        throwBottle(e, px, py)
      end
    else
      if dist > def.holdMax then
        want = dir
      elseif dist < def.holdMin then
        want = -dir -- backs away to keep throwing range
      end
      if e.cooldown <= 0 and e.seesPlayer and dist < def.throwRange and e.grounded then
        e.windT = def.windup
        e.cooldown = def.throwCooldown + def.windup
        audio.playAt("miner_light", cx, cy, 0.7, 1.2)
      end
    end
  else
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.wander = love.math.random() < 0.5 and 0 or (love.math.random() < 0.5 and -1 or 1)
      e.timer = 1 + love.math.random() * 2
    end
    want = e.wander or 0
    if want ~= 0 then
      e.facing = want
    end
  end
  e.throwT = math.max(0, (e.throwT or 0) - dt)
  e.cooldown = math.max(0, (e.cooldown or 0) - dt)

  if want and e.grounded then
    local speed = e.state == "chase" and def.speed or def.speed * 0.35
    local target = want * speed
    local step = 900 * dt
    b.vx = b.vx < target and math.min(b.vx + step, target) or math.max(b.vx - step, target)
  elseif e.grounded then
    b.vx = b.vx * math.max(0, 1 - 8 * dt)
  end
  b.vy = math.min(b.vy + config.gravity * dt, 450)
  local blocked, blocker = Body.moveX(b, collide, b.vx * dt, 4)
  if blocked then
    if blocker and want and want ~= 0 then
      require("src.props").push(blocker, want * def.pushForce, 0)
    end
    if e.grounded and want and want ~= 0 then
      if e.state == "chase" and want == e.facing then
        b.vy = -def.jump
      else
        e.wander = -want
      end
    end
    b.vx = 0
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = 0
  end
  if e.grounded and b.vy >= 0 then
    Body.snapDown(b, collide, 4)
  end
  e.contactMul = 0.4
end

D.torchbearer.onDeath = function(e)
  -- the torch drops: a small flame where it fell, and the bandolier goes up with it
  local cx, cy = center(e)
  fluids.fireBurst(cx, cy + 4, 7)
  audio.playAt("explosion", cx, cy, 0.4, 1.6)
end

-- The torchbearer, second pass: the miner's bony silhouette (hard hat, ribs, lamp) in a scorched coat, a torch held out
-- in front that flares and trails sparks, and a bandolier of green bottles across the chest
local function drawTorch(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local f = e.facing
  local mid, y = b.x + b.w / 2, b.y
  local walk = (e.grounded and math.abs(b.vx) > 4) and math.sin(e.phase * 6) or 0
  local wind = e.windT ~= nil
  local throw = (e.throwT or 0) > 0
  -- legs
  color({ 0.62, 0.57, 0.46 })
  rect(mid - 3, y + 13, 2, 6 - (walk > 0 and 1 or 0))
  rect(mid + 1, y + 13, 2, 6 - (walk < 0 and 1 or 0))
  color({ 0.34, 0.26, 0.18 })
  rect(mid - 3, y + 18, 2, 1)
  rect(mid + 1, y + 18, 2, 1)
  -- the scorched coat over the ribs, tattered at the hem
  color({ 0.24, 0.18, 0.14 })
  rect(mid - 4, y + 6, 8, 8)
  rect(mid - 4 + (walk > 0 and 1 or 0), y + 14, 2, 1)
  rect(mid + 1 - (walk > 0 and 1 or 0), y + 14, 2, 1)
  color({ 0.80, 0.76, 0.64 })
  rect(mid - 1, y + 7, 2, 6)
  rect(mid - 3, y + 8, 6, 1)
  rect(mid - 3, y + 10, 6, 1)
  -- the bandolier: a strap across the chest with three bottles on it
  color({ 0.40, 0.28, 0.16 })
  for i = 0, 6 do
    rect(f > 0 and mid - 4 + i or mid + 3 - i, y + 7 + math.floor(i * 0.9), 1, 1)
  end
  color({ 0.42, 0.62, 0.38 })
  rect(f > 0 and mid - 3 or mid + 2, y + 9, 1, 2)
  rect(f > 0 and mid - 1 or mid, y + 10, 1, 2)
  rect(f > 0 and mid + 1 or mid - 2, y + 11, 1, 2)
  color({ 1.0, 0.7, 0.3 })
  rect(f > 0 and mid - 3 or mid + 2, y + 9)
  -- the skull, with a hard hat and a dead lamp
  color({ 0.88, 0.85, 0.74 })
  rect(mid - 3, y + 1, 6, 5)
  color({ 0.10, 0.08, 0.08 })
  rect(mid - 2 + (f > 0 and 1 or 0), y + 3, 1, 2)
  rect(mid + (f > 0 and 1 or -1), y + 3, 1, 2)
  color({ 0.55, 0.28, 0.14 })
  rect(mid - 4, y, 8, 2)
  rect(mid - 3, y - 1, 6, 1)
  color({ 0.30, 0.28, 0.30 })
  rect(f > 0 and mid + 2 or mid - 3, y - 1, 1, 1)
  -- the torch arm: out in front; raised for the wind-up, flung out for the throw
  local ax = f > 0 and mid + 4 or mid - 6
  local ay = y + 7 - (wind and 5 or 0) + (throw and 2 or 0)
  color({ 0.74, 0.70, 0.60 })
  rect(ax, ay, 2, 2)
  color({ 0.36, 0.24, 0.14 })
  rect(f > 0 and ax + 1 or ax, ay - 4, 1, 5)
  -- the bottle in the hand while winding up
  if wind then
    color({ 0.42, 0.62, 0.38 })
    rect(f > 0 and ax + 2 or ax - 2, ay - 5, 2, 3)
    color({ 1.0, 0.7, 0.3 })
    rect(f > 0 and ax + 2 or ax - 2, ay - 6, 2, 1)
  end
end

local function drawTorchGlow(e)
  local b = e.body
  local f = e.facing
  local wind = e.windT ~= nil
  local ax = b.x + b.w / 2 + (f > 0 and 5 or -5)
  local ay = b.y + 3 - (wind and 5 or 0)
  local t = love.timer.getTime() * 14 + e.phase
  local flick = math.floor(t) % 3
  love.graphics.setColor(1, 0.45, 0.12, 0.9)
  rect(ax - 1, ay - 1 - flick, 4, 3)
  love.graphics.setColor(1, 0.7, 0.25, 0.95)
  rect(ax, ay - flick, 2, 3)
  love.graphics.setColor(1, 0.92, 0.5, 0.95)
  rect(ax, ay + 1 - flick, 1, 2)
  if math.floor(t * 2) % 4 == 0 then
    love.graphics.setColor(1, 0.7, 0.3, 0.7)
    rect(ax + (flick - 1) * 2, ay - 4 - flick)
  end
  -- the bottle's mouth, lit, in the bandolier
  love.graphics.setColor(1, 0.7, 0.3, 0.5)
  rect(b.x + b.w / 2 + (f > 0 and -3 or 2), b.y + 9)
end

-- Tar Crawler -----------------------------------------------------------------------------------------------
-- Walking a surface (the Ether Crawler's way, src.ethercrawler): the crawler is a point p, the open pixel just outside the
-- surface it stands on, and the surface's normal n, one of four axis directions pointing out into the air. A wall
-- ahead becomes the surface (an inside corner); no ground ahead and it goes round the edge (an outside corner).

local globs = {}

local function tangent(e)
  return -e.ny * e.dir, e.nx * e.dir
end

local function stepSurface(e, world)
  local tx, ty = tangent(e)
  local fx, fy = e.px + tx, e.py + ty
  if world:isSolid(fx, fy) then
    e.nx, e.ny = -tx, -ty
    return
  end
  if not world:isSolid(fx - e.nx, fy - e.ny) then
    e.px, e.py = fx - e.nx, fy - e.ny
    e.nx, e.ny = tx, ty
    return
  end
  e.px, e.py = fx, fy
end

local function supported(e, world)
  return world:isSolid(e.px - e.nx, e.py - e.ny)
end

local function placeBody(e)
  local b = e.body
  local cx, cy = e.px + 0.5 + e.nx * 3, e.py + 0.5 + e.ny * 3
  b.x, b.y = math.floor(cx - b.w / 2), math.floor(cy - b.h / 2)
end

local function updateTar(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  if not e.px then
    -- (put down by the generator, or made by hand: it stands on the floor where it is)
    e.px, e.py = math.floor(b.x + b.w / 2), math.floor(b.y + b.h) - 1
    e.nx, e.ny, e.dir = 0, -1, love.math.random() < 0.5 and -1 or 1
    e.dist = 0
  end
  e.phase = e.phase + dt * 5
  e.contactMul = 0.4
  local cx, cy = center(e)
  local d = hypot(px - cx, py - cy)

  -- falling: dropped off the roof, or its footing blown away
  if e.state == "fall" then
    e.vy = math.min((e.vy or 0) + 600 * dt, 380)
    local steps = math.max(1, math.ceil(e.vy * dt))
    for _ = 1, steps do
      if world:isSolid(e.px, e.py + 1) then
        e.nx, e.ny, e.state, e.vy = 0, -1, "crawl", 0
        e.cooldown = 1
        break
      end
      e.py = e.py + 1
    end
    placeBody(e)
    return
  end
  if e.state == "idle" then
    -- (it feels the hunter through the rock: awake without a line of sight once he is within 130 px)
    if (e.seesPlayer and d < def.sight) or d < 130 then
      e.state = "crawl"
    else
      placeBody(e)
      return
    end
  end
  if not supported(e, world) then
    local found
    for _, dir in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      if world:isSolid(e.px + dir[1], e.py + dir[2]) then
        e.nx, e.ny = -dir[1], -dir[2]
        found = true
        break
      end
    end
    if not found then
      e.state, e.vy = "fall", 0
      return
    end
  end
  e.cooldown = math.max(0, (e.cooldown or 1.5) - dt)

  -- the way: toward the hunter, along whatever it is walking on
  local tx, ty = -e.ny, e.nx -- (the way dir = +1 goes)
  e.turnT = (e.turnT or 0) - dt
  if e.turnT <= 0 then
    e.turnT = 0.25
    if e.seesPlayer or d < def.sight then
      local toward = (px - cx) * tx + (py - cy) * ty
      local want = toward >= 0 and 1 or -1
      if want ~= e.dir and (math.abs(toward) > 6 or (e.stuckT or 0) > 0.4) then
        e.dir = want
      end
    elseif love.math.random() < 0.15 then
      e.dir = -e.dir
    end
  end
  -- on the roof, with the hunter under it: let go
  if e.ny == 1 and e.state == "crawl" and e.seesPlayer and math.abs(px - cx) < 18 and py > cy + 14 and py < cy + 130 then
    e.state, e.vy = "fall", 0
    audio.playAt("plop", cx, cy, 0.8, 0.7)
    return
  end

  -- spitting: stands still, faces the hunter, lobs a glob
  local speed = def.speed
  if e.state == "spit" then
    speed = 0
    e.timer = e.timer - dt
    if e.timer < 0.2 and e.thrown == 0 then
      e.thrown = 1
      audio.playAt("plop", cx, cy, 1, 0.7)
      local g = 330
      local t = math.max(0.45, math.min(1.0, d / 150))
      -- (out along the surface's normal first, so a glob from the roof or a wall leaves the rock)
      local sx, sy = cx + e.nx * 5, cy + e.ny * 5
      globs[#globs + 1] = {
        x = sx, y = sy,
        vx = (px - sx) / t, vy = (py - sy) / t - 0.5 * g * t,
        life = 4, dmg = math.max(1, math.floor(5 * e.dmgMul + 0.5)), isTar = true, isGlob = true,
      }
    end
    if e.timer <= 0 then
      e.state, e.cooldown = "crawl", 2.6 + love.math.random() * 1.5
    end
  elseif e.cooldown <= 0 and e.stun <= 0 and e.seesPlayer and d > 50 and d < 230 then
    e.state, e.timer, e.thrown = "spit", 0.6, 0
    audio.playAt("crab_rumble", cx, cy, 0.5, 0.7)
  end
  if e.stun > 0 then
    speed = 0
  end

  local before = e.dist or 0
  e.acc = (e.acc or 0) + speed * dt
  local n = 0
  while e.acc >= 1 and n < 4 do
    e.acc = e.acc - 1
    n = n + 1
    local ox, oy = e.px, e.py
    stepSurface(e, world)
    e.dist = (e.dist or 0) + ((ox ~= e.px or oy ~= e.py) and 1 or 0)
  end
  if speed > 0 and n > 0 and e.dist == before then
    e.stuckT = (e.stuckT or 0) + dt
    if e.stuckT > 0.6 then
      e.dir = -e.dir
      e.stuckT = 0
    end
  else
    e.stuckT = 0
  end
  e.facing = e.dir

  -- the trail: a little oil off the surface behind it (off a roof it drips)
  if n > 0 then
    e.leakT = (e.leakT or 0) - dt
    if e.leakT <= 0 then
      e.leakT = 0.45
      fluids.addOil(e.px - tx * 4 + e.nx, e.py - ty * 4 + e.ny, 2)
    end
  end
  -- fire catches it
  if fluids.fireAt(cx, cy) then
    e.burnT = (e.burnT or 0) - dt
    if e.burnT <= 0 then
      e.burnT = 0.4
      enemies.damage(e, 6, 0, 0, 0, false, nil)
    end
  end
  b.vx, b.vy = 0, 0
  placeBody(e)
end

D.tarcrawler.onDeath = function(e)
  local cx, cy = center(e)
  fluids.addOil(cx, cy + 3, 34)
end

-- The tar crawler, second pass: drawn in its own frame, turned to lie along whatever it is on. A glossy black slug,
-- low and long, with a violet sheen, two eye-stalks, a head that lifts to spit, and drips off its belly
local function frame(e)
  return math.atan2(e.nx or 0, -(e.ny or -1))
end

local function drawTar(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c, a)
    if white then
      love.graphics.setColor(1, 1, 1)
    else
      love.graphics.setColor(c[1], c[2], c[3], a or 1)
    end
  end
  local cx, cy = b.x + b.w / 2, b.y + b.h / 2
  love.graphics.push()
  love.graphics.translate(math.floor(cx + 0.5), math.floor(cy + 0.5))
  love.graphics.rotate(frame(e))
  love.graphics.scale(e.dir or e.facing or 1, 1)
  -- local: x forward, y down, the belly on y = +3
  local wave = math.floor(math.sin(e.phase * 2) + 0.5)
  local spit = e.state == "spit"
  local fall = e.state == "fall"
  -- the body: a long low mound that rolls forward in a wave
  color({ 0.07, 0.05, 0.10 })
  rect(-6, 0, 12, 4)
  rect(-5, -1 + wave, 9, 2)
  rect(-3, -2, 5, 2)
  -- the head, raised to spit
  rect(5, spit and -3 or -1, 3, spit and 5 or 3)
  rect(4, spit and -4 or -2, 2, 2)
  -- a glossy highlight and the violet sheen of oil
  color({ 0.24, 0.18, 0.32 })
  rect(-4, -1 + wave, 3, 1)
  color({ 0.46, 0.30, 0.60 })
  rect(-2, -2, 1, 1)
  rect(2, -1, 1, 1)
  color({ 0.20, 0.34, 0.42 })
  rect(-5, 1, 1, 1)
  -- two eye-stalks with pale eyes
  color({ 0.07, 0.05, 0.10 })
  rect(5, spit and -6 or -4, 1, 2)
  rect(7, spit and -6 or -4, 1, 2)
  color({ 0.92, 0.86, 0.55 })
  rect(5, spit and -7 or -5)
  rect(7, spit and -7 or -5)
  -- the trail behind it, and drips off the belly (a long one while it falls)
  color({ 0.07, 0.05, 0.10 })
  rect(-8, 3, 2, 1)
  rect(-4 + wave, 4, 1, fall and 3 or (math.floor(e.phase) % 3 == 0 and 2 or 1))
  love.graphics.pop()
end

-- Hooks ---------------------------------------------------------------------------------------------------------

enemies.UPDATE.arcbeetle = updateBeetle
enemies.DRAW.arcbeetle = drawBeetle
enemies.GLOW.arcbeetle = drawBeetleGlow
enemies.UPDATE.torchbearer = updateTorch
enemies.DRAW.torchbearer = drawTorch
enemies.GLOW.torchbearer = drawTorchGlow
enemies.UPDATE.tarcrawler = updateTar
enemies.DRAW.tarcrawler = drawTar
enemies.GLOW.tarcrawler = function(e)
  -- a faint violet sheen where the light catches it
  local b = e.body
  love.graphics.setColor(0.45, 0.3, 0.6, 0.3)
  rect(b.x + b.w / 2 - 1, b.y + 2, 1, 1)
end

local function stepShots(list, dt, world, player, pb, onGround, onHit)
  for i = #list, 1, -1 do
    local s = list[i]
    s.life = s.life - dt
    s.vy = s.vy + 360 * dt
    local steps = math.max(1, math.ceil(math.max(math.abs(s.vx), math.abs(s.vy)) * dt / 2))
    local gone = s.life <= 0 or s.shot
    for _ = 1, steps do
      if gone then
        break
      end
      s.x, s.y = s.x + s.vx * dt / steps, s.y + s.vy * dt / steps
      if world:isSolid(s.x, s.y) then
        onGround(s)
        gone = true
      elseif not player.dead and overlaps(s.x - 2, s.y - 2, 4, 4, pb.x, pb.y, pb.w, pb.h) then
        onHit(s)
        gone = true
      end
    end
    if gone then
      table.remove(list, i)
    end
  end
end

local function bottleBurst(s)
  audio.playAt("explosion", s.x, s.y, 0.35, 1.7)
  fluids.fireBurst(s.x, s.y - 2, 6)
  for _ = 1, 8 do
    effects.particle(s.x, s.y, (love.math.random() - 0.5) * 80, -love.math.random() * 70, 0.5, { 1, 0.6, 0.2 }, 300, true)
  end
end

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  local pb = player.body
  stepShots(bottles, dt, world, player, pb, bottleBurst, function(s)
    player:hurt(s.dmg, s.x - s.vx * 0.05, s.y - s.vy * 0.05, "torchbearer")
    status.apply(player, "burning", 4)
    fluids.fireBurst(s.x, s.y, 4)
  end)
  stepShots(globs, dt, world, player, pb, function(s)
    fluids.addOil(s.x, s.y - 1, 12)
    for _ = 1, 6 do
      effects.particle(s.x, s.y, (love.math.random() - 0.5) * 60, -love.math.random() * 50, 0.5, { 0.1, 0.07, 0.14 }, 300)
    end
  end, function(s)
    player:hurt(s.dmg, s.x - s.vx * 0.05, s.y - s.vy * 0.05, "tarcrawler")
    status.apply(player, "oiled", 20)
    fluids.addOil(s.x, s.y, 6)
  end)
end

-- Bullets: a bottle or a glob in the air can be shot (enemies.hitTest asks, enemies.hit applies, as for a miner's stick or an
-- acid glob). A bottle bursts into flame where it is; a glob splatters into oil there.
local prevHitTest = enemies.hitTest
enemies.hitTest = function(px, py)
  local found = prevHitTest(px, py)
  if found then
    return found
  end
  for _, s in ipairs(bottles) do
    if not s.shot and math.abs(px - s.x) <= 3 and math.abs(py - s.y) <= 3 then
      return s
    end
  end
  for _, s in ipairs(globs) do
    if not s.shot and math.abs(px - s.x) <= 3 and math.abs(py - s.y) <= 3 then
      return s
    end
  end
  return nil
end

local prevHit = enemies.hit
enemies.hit = function(thing, amount, dx, dy, force, crit, fx)
  if thing.isBottle then
    thing.shot = true
    bottleBurst(thing)
  elseif thing.isTar then
    thing.shot = true
    fluids.addOil(thing.x, thing.y, 8)
    for _ = 1, 6 do
      effects.particle(thing.x, thing.y, (love.math.random() - 0.5) * 60, -love.math.random() * 50, 0.5, { 0.1, 0.07, 0.14 }, 300)
    end
  else
    prevHit(thing, amount, dx, dy, force, crit, fx)
  end
end

local prevDraw = enemies.afterDraw
enemies.afterDraw = function(view)
  if prevDraw then
    prevDraw(view)
  end
  local t = love.timer.getTime()
  for _, s in ipairs(bottles) do
    local spin = math.floor(t * 14) % 4
    love.graphics.setColor(0.42, 0.62, 0.38)
    if spin % 2 == 0 then
      rect(s.x - 1, s.y - 2, 2, 4)
    else
      rect(s.x - 2, s.y - 1, 4, 2)
    end
    love.graphics.setColor(1, 0.65, 0.2)
    rect(s.x + (spin < 2 and 1 or -2), s.y + (spin % 2 == 0 and -3 or -1), 1, 1)
    -- a short tail of sparks
    love.graphics.setColor(1, 0.6, 0.2, 0.6)
    rect(s.x - s.vx * 0.015, s.y - s.vy * 0.015, 1, 1)
  end
  for _, s in ipairs(globs) do
    love.graphics.setColor(0.07, 0.05, 0.10)
    rect(s.x - 2, s.y - 2, 4, 4)
    love.graphics.setColor(0.42, 0.28, 0.55)
    rect(s.x - 2, s.y - 2, 2, 1)
    love.graphics.setColor(0.07, 0.05, 0.10)
    rect(s.x - s.vx * 0.02, s.y - s.vy * 0.02, 2, 2)
  end
end

local prevClear = enemies.clear
enemies.clear = function()
  prevClear()
  bottles, globs = {}, {}
end

return true
