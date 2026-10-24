-- The creatures of the Cloud Reaches: all of them airborne, since the islands are small. Fewer than the
-- caves hold, and tougher. Placeholder art and sounds (reused names from src.audio):
--   Cloud Ray       a manta of the high air. It drifts in a pack, then the whole pack dives in turn
--   Star Moth       an erratic flier that hovers over the drops, glittering, and tempts you out to it
--   Brass Sentinel  a floating brass turret of the ruins: it charges, draws a line to you, and fires a
--                   slow bolt
--   Wind Spirit     a swirl of cold air that takes the side of you the island is on, and blows you off it
local enemies = require("src.enemies")
local Body = require("src.body")
local audio = require("src.audio")
local effects = require("src.effects")

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

-- Definitions ---------------------------------------------------------------------------------------

local D = enemies.defs
D.cloudray = {
  name = "Cloud Ray",
  w = 26, h = 10, hp = 46, speed = 78, accel = 150,
  sight = 380, forget = 900, damage = 10, diveSpeed = 250, orbit = 130,
  knockback = 0.35, gold = { 5, 11 }, weight = 3,
  spriteW = 26, spriteH = 10, scale = 1,
  blood = { 0.75, 0.82, 0.95 },
  desc = "A pale manta of the high air, gold on its belly from the dusk below. It drifts in a pack over the islands, then the pack stoops on you one after another. Keep moving and they miss.",
}
D.starmoth = {
  name = "Star Moth",
  w = 9, h = 8, hp = 16, speed = 96, accel = 420,
  sight = 300, forget = 700, damage = 6, leash = 150,
  knockback = 0.8, gold = { 3, 8 }, weight = 0.5,
  spriteW = 9, spriteH = 8, scale = 1,
  blood = { 0.85, 0.8, 1.0 },
  desc = "A glittering moth that hangs over the drops between the islands. It flutters out to meet you, never far from its place, and every step toward it is a step off the edge.",
}
D.sentinel = {
  name = "Brass Sentinel",
  w = 16, h = 16, hp = 120, speed = 30, accel = 90,
  sight = 400, forget = 700, damage = 10, boltSpeed = 125, boltDamage = 13,
  knockback = 0.08, gold = { 10, 20 }, weight = 8,
  spriteW = 16, spriteH = 16, scale = 1,
  blood = { 0.8, 0.62, 0.25 },
  desc = "A brass sphere that the old builders left to keep their ruins. It hangs in the air and turns its one lens on you; a ring closes round you when it has you. The bolt it fires bends after you, so do not stand still.",
}
D.windspirit = {
  name = "Wind Spirit",
  w = 14, h = 22, hp = 60, speed = 66, accel = 170,
  sight = 360, forget = 800, damage = 7, gale = 150,
  knockback = 0.25, gold = { 7, 14 }, weight = 1,
  spriteW = 14, spriteH = 22, scale = 1,
  blood = { 0.8, 0.9, 1.0 },
  desc = "A cold swirl of the upper air. It drifts to the side of you that has the island under it, spins up, and blows: you leave the edge the way you did not mean to. Shoot it before it gets its breath.",
}
for _, k in ipairs({ "cloudray", "starmoth", "sentinel", "windspirit" }) do
  enemies.order[#enemies.order + 1] = k
end

enemies.VOICES.cloudray = { "bat_flutter", 4, 9, 0.7 }
enemies.VOICES.starmoth = { "wisp_crackle", 3, 8, 0.5 }
enemies.VOICES.sentinel = { "clank", 5, 10, 0.5 }
enemies.VOICES.windspirit = { "wind_howl", 5, 10, 0.8 }

D.starmoth.light = function(e)
  local cx, cy = center(e)
  return { cx, cy, 30, 0.7, 0.75, 1.0, 0.45 }
end
D.sentinel.light = function(e)
  local cx, cy = center(e)
  local hot = e.state == "charge" and 0.55 or 0.22
  return { cx, cy, 36, 1.0, 0.7, 0.3, hot }
end
D.windspirit.light = function(e)
  local cx, cy = center(e)
  return { cx, cy, 28, 0.7, 0.85, 1.0, e.state == "blow" and 0.4 or 0.16 }
end

-- Shared: ease the body's velocity toward (wantx, wanty), then move it, bouncing off what it meets
local function steer(e, dt, collide, wantx, wanty, bounce)
  local b, def = e.body, e.def
  if e.stun <= 0 then
    local step = def.accel * dt
    b.vx = b.vx < wantx and math.min(b.vx + step, wantx) or math.max(b.vx - step, wantx)
    b.vy = b.vy < wanty and math.min(b.vy + step, wanty) or math.max(b.vy - step, wanty)
  end
  local hit = false
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * (bounce or 0.4)
    hit = true
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * (bounce or 0.4)
    hit = true
  end
  return hit
end

-- The cloud ray ---------------------------------------------------------------------------------------

local function updateRay(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  local swarm = e.swarm
  local collide = collider(e, world)
  e.home = e.home or { cx, cy }
  e.phase = e.phase + dt * (e.state == "dive" and 9 or 3)
  e.attackCd = math.max(0, (e.attackCd or (1 + love.math.random() * 2.5)) - dt)
  e.contactMul = e.state == "dive" and 1.4 or 0.5
  local wantx, wanty = 0, 0
  if e.state == "sleep" then
    -- drifting about its place
    wantx = (e.home[1] + math.sin(e.phase * 0.31) * 60 - cx) * 0.8
    wanty = (e.home[2] + math.cos(e.phase * 0.23) * 16 - cy) * 0.8
    if (e.seesPlayer and dist < def.sight) or (swarm and swarm.awake) then
      e.state = "chase"
      e.orbA = love.math.random() * math.pi * 2
      e.orbDir = love.math.random() < 0.5 and -1 or 1
      if swarm then
        swarm.awake = true
      end
      audio.playAt("bat_screech", cx, cy, 0.5, 0.6)
    end
  elseif e.state == "chase" then
    e.orbA = e.orbA + dt * 0.7 * e.orbDir
    local tx, ty = px + math.cos(e.orbA) * def.orbit, py - 80 + math.sin(e.orbA) * 34
    wantx = math.max(-def.speed, math.min(def.speed, (tx - cx) * 2))
    wanty = math.max(-def.speed, math.min(def.speed, (ty - cy) * 2))
    if not e.seesPlayer and e.stun <= 0 then
      local fx, fy = enemies.flowDirection(world, cx, cy, px, py - 4)
      if fx then
        wantx, wanty = fx * def.speed, fy * def.speed
      end
    end
    if dist > def.forget then
      e.state = "sleep"
      if swarm then
        swarm.awake = false
      end
    elseif e.seesPlayer and e.attackCd <= 0 and dist < 320 and dist > 70 and e.stun <= 0 then
      e.state, e.timer = "tilt", 0.55
      audio.playAt("bat_screech", cx, cy, 0.7, 1.1)
    end
  elseif e.state == "tilt" then
    -- hangs, nose at the hunter: the dive goes where he is looking now, a little ahead of his stride
    e.timer = e.timer - dt
    e.facing = px >= cx and 1 or -1
    local ang = math.atan2(py + player.body.vy * 0.25 - cy, px + player.body.vx * 0.3 - cx)
    e.aim = ang
    if e.timer <= 0 then
      e.state, e.timer = "dive", 0.75
      b.vx, b.vy = math.cos(ang) * def.diveSpeed, math.sin(ang) * def.diveSpeed
    end
    wantx, wanty = b.vx * 0.2, b.vy * 0.2
    b.vx, b.vy = b.vx * math.exp(-6 * dt), b.vy * math.exp(-6 * dt)
  elseif e.state == "dive" then
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.state, e.timer = "recover", 0.9
      e.attackCd = 2 + love.math.random() * 2
    end
    local hit = false
    if Body.moveX(b, collide, b.vx * dt, 0) then
      hit = true
    end
    if Body.moveY(b, collide, b.vy * dt) then
      hit = true
    end
    if hit then
      e.state, e.timer = "recover", 1.1
      e.attackCd = 2 + love.math.random() * 2
      b.vx, b.vy = -b.vx * 0.2, -b.vy * 0.2
    end
    if love.math.random() < dt * 30 then
      effects.particle(cx, cy, (love.math.random() - 0.5) * 20, (love.math.random() - 0.5) * 20, 0.35, { 0.9, 0.95, 1 }, 0, true)
    end
    return
  elseif e.state == "recover" then
    e.timer = e.timer - dt
    wantx, wanty = 0, -40 -- (climbs back up)
    if e.timer <= 0 then
      e.state = "chase"
    end
  end
  if e.state ~= "tilt" then
    steer(e, dt, collide, wantx, wanty, 0.4)
  else
    Body.moveX(b, collide, b.vx * dt, 0)
    Body.moveY(b, collide, b.vy * dt)
  end
  if e.state ~= "dive" and math.abs(b.vx) > 8 then
    e.facing = b.vx > 0 and 1 or -1
  end
end

local RAY = { top = { 0.72, 0.8, 0.95 }, dark = { 0.46, 0.54, 0.78 }, belly = { 0.95, 0.78, 0.5 }, eye = { 0.15, 0.15, 0.3 } }

local function drawRay(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c, a)
    if white then
      love.graphics.setColor(1, 1, 1)
    else
      love.graphics.setColor(c[1], c[2], c[3], a or 1)
    end
  end
  local mid, my = b.x + b.w / 2, b.y + b.h / 2
  local f = e.facing
  local diving = e.state == "dive"
  local tilting = e.state == "tilt"
  local flap = diving and 0.15 or math.sin(e.phase * 1.2)
  local lift = tilting and -3 or flap * 4
  local wing = diving and 8 or 12
  -- the tail first, then wings (far, near), the body over them
  color(RAY.dark)
  love.graphics.line(mid - f * 4, my, mid - f * 14, my + 2 + math.sin(e.phase) * 2)
  for side = -1, 1, 2 do
    color(side == f and RAY.top or RAY.dark)
    love.graphics.polygon("fill", mid + f * 3, my - 1, mid + side * wing + f * 0, my + lift, mid + side * (wing - 3) - f * 5, my + 2 + lift * 0.4, mid - f * 4, my + 2)
  end
  color(RAY.top)
  love.graphics.polygon("fill", mid + f * 7, my, mid, my - 3, mid - f * 5, my, mid, my + 3)
  color(RAY.belly)
  rect(mid - 3, my + 1, 6, 1)
  color(RAY.eye)
  rect(mid + f * 4 - (f < 0 and 1 or 0), my - 1, 1, 1)
  if tilting then
    color({ 1, 0.5, 0.35 })
    rect(mid + f * 7 - (f < 0 and 1 or 0), my, 1, 1)
  end
end

local function drawRayGlow(e)
  if e.state == "tilt" or e.state == "dive" then
    local b = e.body
    love.graphics.setColor(1, 0.55, 0.35)
    rect(b.x + b.w / 2 + e.facing * 4 - (e.facing < 0 and 1 or 0), b.y + 4)
  end
end

-- The star moth ---------------------------------------------------------------------------------------------

local function updateMoth(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  local collide = collider(e, world)
  e.home = e.home or { cx, cy }
  e.phase = e.phase + dt * 22
  e.attackCd = math.max(0, (e.attackCd or 1.5) - dt)
  -- an erratic target: it jinks about on a fresh whim every fraction of a second
  e.whim = (e.whim or 0) - dt
  if e.whim <= 0 then
    e.whim = 0.15 + love.math.random() * 0.3
    e.wx, e.wy = (love.math.random() - 0.5) * 2, (love.math.random() - 0.5) * 2
  end
  local hx, hy = e.home[1], e.home[2]
  local tx, ty = hx + e.wx * 50, hy + e.wy * 30
  e.contactMul = 1
  if e.state == "sleep" then
    if e.seesPlayer and dist < def.sight then
      e.state = "chase"
    end
  elseif e.state == "chase" then
    -- out to meet the hunter, but never far from the place it hangs over: so it leads him to the edge
    local d = math.max(1, dist)
    local reach = 56
    local ax, ay = px - (px - cx) / d * reach, py - (py - cy) / d * reach
    local fromHome = hypot(ax - hx, ay - hy)
    if fromHome > def.leash then
      ax, ay = hx + (ax - hx) / fromHome * def.leash, hy + (ay - hy) / fromHome * def.leash
    end
    tx, ty = ax + e.wx * 24, ay + e.wy * 18
    if e.seesPlayer and e.attackCd <= 0 and dist < 130 and e.stun <= 0 then
      e.state, e.timer = "stab", 0.28
      e.sx, e.sy = (px - cx) / d, (py - cy) / d
      audio.playAt("wisp_crackle", cx, cy, 0.6, 1.5)
    end
    if dist > def.forget then
      e.state = "sleep"
    end
  elseif e.state == "stab" then
    e.timer = e.timer - dt
    b.vx, b.vy = e.sx * 210, e.sy * 210
    if e.timer <= 0 then
      e.state, e.attackCd = "chase", 1.6 + love.math.random() * 1.4
    end
    Body.moveX(b, collide, b.vx * dt, 0)
    Body.moveY(b, collide, b.vy * dt)
    return
  end
  local wantx = math.max(-def.speed, math.min(def.speed, (tx - cx) * 4))
  local wanty = math.max(-def.speed, math.min(def.speed, (ty - cy) * 4))
  steer(e, dt, collide, wantx, wanty, 0.5)
  e.facing = (px >= cx) and 1 or -1
  if love.math.random() < dt * 8 then
    effects.particle(cx, cy + 2, (love.math.random() - 0.5) * 10, 8 + love.math.random() * 10, 0.7, { 0.8, 0.85, 1 }, 0, true)
  end
end

local function drawMoth(e)
  local b = e.body
  local white = e.flash > 0
  local mid, my = b.x + b.w / 2, b.y + b.h / 2
  local flap = math.floor(e.phase) % 2 == 0 and 3 or 1
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.62, 0.65, 0.95 })
  love.graphics.polygon("fill", mid, my, mid - 5, my - flap, mid - 4, my + 3, mid, my + 1)
  love.graphics.polygon("fill", mid, my, mid + 5, my - flap, mid + 4, my + 3, mid, my + 1)
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.3, 0.3, 0.6 })
  rect(mid, my - 1, 1, 4)
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.85, 0.88, 1 })
  rect(mid - 3, my - 1, 1, 1)
  rect(mid + 3, my - 1, 1, 1)
end

local function drawMothGlow(e)
  local b = e.body
  local t = e.phase
  love.graphics.setColor(0.9, 0.95, 1, 0.8)
  rect(b.x + b.w / 2 - 3, b.y + 3)
  rect(b.x + b.w / 2 + 3, b.y + 3)
  love.graphics.setColor(1, 1, 1, 0.5 + 0.5 * math.sin(t * 0.4))
  rect(b.x + b.w / 2, b.y + 2)
end

-- The brass sentinel and its bolts -------------------------------------------------------------------------

local bolts = {}

local function fireBolt(e, px, py)
  local cx, cy = center(e)
  local d = math.max(1, hypot(px - cx, py - cy))
  local sp = e.def.boltSpeed
  bolts[#bolts + 1] = {
    x = cx + (px - cx) / d * 9, y = cy + (py - cy) / d * 9,
    vx = (px - cx) / d * sp, vy = (py - cy) / d * sp,
    life = 4.5, dmg = math.max(1, math.floor(e.def.boltDamage * e.dmgMul + 0.5)), home = 2.4,
  }
  audio.playAt("explosion", cx, cy, 0.25, 2.2)
  audio.playAt("clank", cx, cy, 0.6, 1.4)
end

local function updateSentinel(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  local collide = collider(e, world)
  e.home = e.home or { cx, cy }
  e.phase = e.phase + dt * 3
  e.attackCd = math.max(0, (e.attackCd or 2) - dt)
  e.contactMul = 0.6
  if e.state == "sleep" then
    if e.seesPlayer and dist < def.sight then
      e.state = "watch"
      audio.playAt("clank", cx, cy, 0.7, 0.7)
    end
  elseif e.state == "watch" then
    e.aimX, e.aimY = px, py
    if e.seesPlayer and e.attackCd <= 0 and dist < def.sight and e.stun <= 0 then
      e.state, e.timer = "charge", 0.65
      audio.playAt("tick", cx, cy, 0.7, 0.6)
    elseif dist > def.forget then
      e.state = "sleep"
    end
  elseif e.state == "charge" then
    -- the ring stays on him all the while it charges (the bolt tracks him too)
    e.timer = e.timer - dt
    e.aimX, e.aimY = px, py
    if e.timer <= 0 then
      fireBolt(e, e.aimX, e.aimY)
      e.state, e.attackCd = "watch", 1.2 + love.math.random() * 0.9
    end
  end
  e.facing = px >= cx and 1 or -1
  -- hangs about its place, bobbing
  local wantx = (e.home[1] + math.sin(e.phase * 0.4) * 10 - cx) * 1.5
  local wanty = (e.home[2] + math.sin(e.phase) * 3 - cy) * 1.5
  steer(e, dt, collide, math.max(-def.speed, math.min(def.speed, wantx)), math.max(-def.speed, math.min(def.speed, wanty)), 0.2)
end

local BRASS = { body = { 0.78, 0.58, 0.22 }, dark = { 0.46, 0.32, 0.12 }, light = { 0.98, 0.84, 0.46 }, lens = { 0.2, 0.9, 0.95 } }

local function drawSentinel(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local mid, my = b.x + b.w / 2, b.y + b.h / 2
  -- fins, then the sphere with its band, and the lens turned toward what it watches
  color(BRASS.dark)
  rect(mid - 9, my - 1, 4, 2)
  rect(mid + 5, my - 1, 4, 2)
  rect(mid - 1, my - 10, 2, 3)
  love.graphics.setColor(white and { 1, 1, 1 } or BRASS.body)
  love.graphics.circle("fill", mid, my, 7)
  color(BRASS.dark)
  rect(mid - 7, my, 14, 1)
  color(BRASS.light)
  rect(mid - 4, my - 5, 3, 1)
  rect(mid - 5, my - 4, 1, 2)
  local ax, ay = 0, 0
  if e.aimX then
    local d = math.max(1, hypot(e.aimX - mid, e.aimY - my))
    ax, ay = (e.aimX - mid) / d * 3, (e.aimY - my) / d * 3
  end
  color(e.state == "charge" and { 1, 0.35, 0.2 } or BRASS.lens)
  rect(mid + ax - 1, my + ay - 1, 3, 3)
  if e.state == "charge" then
    -- locked on: a ring closing round the hunter, with cross ticks, red when it is about to fire
    local k = math.max(0, e.timer / 0.65)
    local r = 6 + k * 12
    local hot = e.timer < 0.22
    love.graphics.setColor(1, hot and 0.2 or 0.55, hot and 0.15 or 0.3, 0.9)
    love.graphics.setLineWidth(1)
    love.graphics.circle("line", e.aimX, e.aimY, r)
    for a = 0, 3 do
      local dx, dy = math.cos(a * math.pi / 2), math.sin(a * math.pi / 2)
      love.graphics.line(e.aimX + dx * (r - 3), e.aimY + dy * (r - 3), e.aimX + dx * (r + 4), e.aimY + dy * (r + 4))
    end
  end
end

local function drawSentinelGlow(e)
  local b = e.body
  love.graphics.setColor(e.state == "charge" and { 1, 0.5, 0.3 } or { 0.5, 1, 1 })
  rect(b.x + b.w / 2, b.y + b.h / 2)
end

-- The wind spirit -------------------------------------------------------------------------------------------

-- Which side of the hunter has an island under it (-1 left, 1 right, 0 both or neither): the spirit takes that
-- side and blows him off the other
local function groundSide(world, px, py)
  local function ground(x)
    for dy = 6, 40, 6 do
      if world:isSolid(x, py + dy) then
        return true
      end
    end
    return false
  end
  local l, r = ground(px - 40), ground(px + 40)
  if l and not r then
    return -1
  elseif r and not l then
    return 1
  end
  return 0
end

local function updateSpirit(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  local collide = collider(e, world)
  e.phase = e.phase + dt * ((e.state == "spin" or e.state == "blow") and 14 or 5)
  e.attackCd = math.max(0, (e.attackCd or (1.5 + love.math.random() * 2)) - dt)
  e.contactMul = 0.7
  local wantx, wanty = 0, math.sin(e.phase * 0.3) * 10
  if e.state == "sleep" then
    wantx = math.sin(e.phase * 0.2) * 14
    if e.seesPlayer and dist < def.sight then
      e.state = "chase"
      audio.playAt("wind_howl", cx, cy, 0.5, 1.3)
    end
  elseif e.state == "chase" then
    -- to the island side of the hunter, level with him
    if not e.side or e.sideT <= 0 then
      local s = groundSide(world, px, py)
      e.side, e.sideT = s ~= 0 and s or (e.side or (love.math.random() < 0.5 and -1 or 1)), 0.8
    end
    e.sideT = e.sideT - dt
    local tx, ty = px + e.side * 62, py - 6
    wantx = math.max(-def.speed, math.min(def.speed, (tx - cx) * 2.5))
    wanty = math.max(-def.speed, math.min(def.speed, (ty - cy) * 2.5)) + wanty
    if not e.seesPlayer and e.stun <= 0 then
      local fx, fy = enemies.flowDirection(world, cx, cy, px, py - 4)
      if fx then
        wantx, wanty = fx * def.speed, fy * def.speed
      end
    end
    if e.seesPlayer and e.attackCd <= 0 and dist < 130 and e.stun <= 0 then
      e.state, e.timer = "spin", 0.9
      e.gdir = px >= cx and 1 or -1 -- (away from the spirit)
      audio.playAt("wind_howl", cx, cy, 1, 1.0)
    elseif dist > def.forget then
      e.state = "sleep"
    end
  elseif e.state == "spin" then
    -- winding up: loose grit and a streak of wind in the direction it will blow
    wantx, wanty = 0, 0
    e.timer = e.timer - dt
    if love.math.random() < dt * 40 then
      effects.particle(cx + e.gdir * (10 + love.math.random() * 40), py + (love.math.random() - 0.5) * 20, e.gdir * 60, 0, 0.35, { 0.85, 0.95, 1 }, 0, true)
    end
    if e.timer <= 0 then
      e.state, e.timer = "blow", 1.2
      audio.playAt("gust_blast", cx, cy, 1, 0.9)
    end
  elseif e.state == "blow" then
    wantx, wanty = 0, 0
    e.timer = e.timer - dt
    local pb = player.body
    if not player.dead and math.abs(px - cx) < def.gale and math.abs(py - cy) < def.gale * 0.5 then
      local k = 1 - math.abs(px - cx) / def.gale
      pb.vx = pb.vx + e.gdir * 3000 * (0.4 + 0.6 * k) * dt
      pb.vy = pb.vy - 60 * k * dt
    end
    if love.math.random() < dt * 80 then
      effects.particle(cx + e.gdir * (4 + love.math.random() * 90), cy + (love.math.random() - 0.5) * 30, e.gdir * (180 + love.math.random() * 160), (love.math.random() - 0.5) * 20, 0.4, { 0.85, 0.95, 1 }, 0, true)
    end
    if e.timer <= 0 then
      e.state, e.attackCd = "chase", 3.5 + love.math.random() * 2
      e.sideT = 0
    end
  end
  e.facing = px >= cx and 1 or -1
  steer(e, dt, collide, wantx, wanty, 0.4)
end

local function drawSpirit(e)
  local b = e.body
  local white = e.flash > 0
  local mid = b.x + b.w / 2
  local spin = e.state == "spin" or e.state == "blow"
  local t = e.phase
  for row = 0, 10 do
    local u = row / 10
    local y = b.y + row * 2
    local w = (3 + u * 9) * (spin and 1.25 or 1)
    local off = math.sin(t * 0.8 + row * 0.8) * (1 + u * 2)
    local shade = 0.7 + 0.25 * math.sin(t + row * 1.7)
    love.graphics.setColor(white and { 1, 1, 1 } or { 0.7 * shade + 0.15, 0.82 * shade + 0.12, 0.98 * shade, 0.75 })
    rect(mid + off - w / 2, y, w, 2)
    love.graphics.setColor(white and { 1, 1, 1 } or { 1, 1, 1, 0.65 })
    rect(mid + off + math.cos(t * 1.4 + row) * w / 2, y, 1, 1)
  end
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.15, 0.2, 0.4 })
  rect(mid - 2, b.y + 5, 1, 2)
  rect(mid + 1, b.y + 5, 1, 2)
  if e.state == "spin" and e.gdir then
    -- the wind to come, as streaks on the side it will blow toward
    love.graphics.setColor(0.85, 0.95, 1, 0.5)
    for k = 1, 4 do
      rect(mid + e.gdir * (10 + k * 12), b.y + 4 + k * 3, 8, 1)
    end
  end
end

local function drawSpiritGlow(e)
  local b = e.body
  local mid = b.x + b.w / 2
  love.graphics.setColor(0.8, 0.95, 1)
  rect(mid - 2, b.y + 5)
  rect(mid + 1, b.y + 5)
end

-- Hooks ---------------------------------------------------------------------------------------------------------

enemies.UPDATE.cloudray = updateRay
enemies.DRAW.cloudray = drawRay
enemies.GLOW.cloudray = drawRayGlow
enemies.UPDATE.starmoth = updateMoth
enemies.DRAW.starmoth = drawMoth
enemies.GLOW.starmoth = drawMothGlow
enemies.UPDATE.sentinel = updateSentinel
enemies.DRAW.sentinel = drawSentinel
enemies.GLOW.sentinel = drawSentinelGlow
enemies.UPDATE.windspirit = updateSpirit
enemies.DRAW.windspirit = drawSpirit
enemies.GLOW.windspirit = drawSpiritGlow

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  local pb = player.body
  for i = #bolts, 1, -1 do
    local s = bolts[i]
    s.life = s.life - dt
    if s.home and s.home > 0 and not player.dead then
      -- it bends after him, for the first couple of seconds
      s.home = s.home - dt
      local sp = math.sqrt(s.vx * s.vx + s.vy * s.vy)
      local cur = math.atan2(s.vy, s.vx)
      local want = math.atan2(py - s.y, px - s.x)
      local d = (want - cur + math.pi) % (math.pi * 2) - math.pi
      cur = cur + math.max(-1.5 * dt, math.min(1.5 * dt, d))
      s.vx, s.vy = math.cos(cur) * sp, math.sin(cur) * sp
    end
    local gone = s.life <= 0
    local steps = math.max(1, math.ceil(math.max(math.abs(s.vx), math.abs(s.vy)) * dt / 2))
    for _ = 1, steps do
      if gone then
        break
      end
      s.x, s.y = s.x + s.vx * dt / steps, s.y + s.vy * dt / steps
      if world:isSolid(s.x, s.y) then
        gone = true
      elseif not player.dead and overlaps(s.x - 2, s.y - 2, 5, 5, pb.x, pb.y, pb.w, pb.h) then
        player:hurt(s.dmg, s.x - s.vx * 0.05, s.y - s.vy * 0.05, "sentinel")
        gone = true
      end
    end
    if gone then
      for _ = 1, 6 do
        effects.particle(s.x, s.y, (love.math.random() - 0.5) * 60, (love.math.random() - 0.5) * 60, 0.4, { 1, 0.8, 0.4 }, 0, true)
      end
      table.remove(bolts, i)
    end
  end
end

local prevEmissive = enemies.afterEmissive
enemies.afterEmissive = function(view)
  if prevEmissive then
    prevEmissive(view)
  end
  for _, s in ipairs(bolts) do
    love.graphics.setColor(1, 0.7, 0.25, 0.4)
    rect(s.x - 3, s.y - 3, 6, 6)
    love.graphics.setColor(1, 0.95, 0.7)
    rect(s.x - 1, s.y - 1, 3, 3)
  end
end

local prevClear = enemies.clear
enemies.clear = function()
  prevClear()
  bolts = {}
end

return true
