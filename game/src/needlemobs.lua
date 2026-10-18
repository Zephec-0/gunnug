-- The creatures of the Needle (the mountain dungeon), four of them, each with a voice
-- of its own (src.audio):
--   Needle Crow     a small black crow, asleep under the ceiling like a bat. Awake it
--                   circles the hunter at a distance and spits bile at him
--   Crag Ram        a big, shaggy mountain ram. It paws the ground, snorts, then charges
--                   in a straight line; a wall stuns it, and a stunned ram takes more
--   Dust Devil      a whirling column of wind and grit that drifts after the hunter and
--                   now and then blows a gale that shoves him (and the fog) about
--   Gargoyle        a stone figure hanging among the stalactites. It drops on whoever
--                   passes under it, then flies; every so often it turns to stone,
--                   shrugging everything off, and lunges
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

local function sign(v)
  return v < 0 and -1 or 1
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w or 1, h or 1)
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

-- Definitions ---------------------------------------------------------------------------------------

local D = enemies.defs
D.crow = {
  name = "Needle Crow",
  w = 10, h = 8, hp = 22, speed = 100, accel = 300,
  sight = 440, forget = 900, damage = 6, orbit = 105, spitRange = 300,
  knockback = 0.5, gold = { 3, 7 }, weight = 1.5,
  spriteW = 10, spriteH = 8, scale = 1,
  blood = { 0.16, 0.12, 0.22 },
  desc = "A small black crow of the mountain, asleep upside down among the stalactites. Awake, it will not dive at you: it circles, keeping its distance, and spits bile.",
}
D.cragram = {
  name = "Crag Ram",
  ground = true, w = 22, h = 15, hp = 85, speed = 42, jump = 190,
  sight = 420, forget = 900, damage = 12, chargeSpeed = 235,
  knockback = 0.12, gold = { 8, 15 }, weight = 8, pushForce = 400,
  spriteW = 22, spriteH = 15, scale = 1,
  blood = { 0.55, 0.12, 0.1 },
  desc = "A shaggy mountain ram. It stamps and snorts, then charges at you in a straight line. A wall stops it dead and leaves it dizzy and soft, which is when to shoot it.",
}
D.dustdevil = {
  name = "Dust Devil",
  w = 14, h = 22, hp = 36, speed = 62, accel = 160,
  sight = 460, forget = 900, damage = 8, gale = 170,
  knockback = 0.3, gold = { 5, 10 }, weight = 1,
  spriteW = 14, spriteH = 22, scale = 1,
  blood = { 0.75, 0.66, 0.5 },
  desc = "A whirling column of grit. It drifts after you, then spins up and blows a gale that throws you about, and the fog with you, towards whatever is behind.",
}
D.gargoyle = {
  name = "Gargoyle",
  w = 14, h = 16, hp = 95, speed = 86, accel = 210,
  sight = 230, forget = 700, damage = 14, lungeSpeed = 290,
  knockback = 0.06, gold = { 9, 16 }, weight = 6,
  spriteW = 14, spriteH = 16, scale = 1,
  blood = { 0.5, 0.5, 0.55 },
  desc = "A stone figure that hangs among the stalactites. It drops on whoever passes under it, then flies. Now and then it turns to stone and nothing hurts it, and then it lunges.",
}
for _, k in ipairs({ "crow", "cragram", "dustdevil", "gargoyle" }) do
  enemies.order[#enemies.order + 1] = k
end

-- What a hit does: a ram that has run into a wall is soft; a gargoyle in stone is not hurt at all
D.cragram.filter = function(e, amount)
  return e.state == "dizzy" and math.floor(amount * 1.5 + 0.5) or amount
end
D.gargoyle.filter = function(e, amount)
  if e.state == "stone" or e.state == "drop" then
    audio.playAt("clank", e.body.x, e.body.y, 0.5, 1.5)
    return 0
  end
  return amount
end

enemies.VOICES.crow = { "crow_caw", 3, 7, 1 }
enemies.VOICES.cragram = { "ram_snort", 4, 9, 1 }
enemies.VOICES.dustdevil = { "wind_howl", 5, 10, 1 }
enemies.VOICES.gargoyle = { "gargoyle_grind", 4, 9, 1 }

D.crow.light = function(e)
  local cx, cy = center(e)
  return { cx, cy, 14, 0.7, 0.4, 0.95, 0.18 }
end
D.dustdevil.light = function(e)
  local cx, cy = center(e)
  return { cx, cy, 34, 0.95, 0.8, 0.55, e.state == "blow" and 0.4 or 0.2 }
end

-- The bile the crows spit ---------------------------------------------------------------------------------

local bile = {}

local function spit(e, world, player, px, py)
  local cx, cy = center(e)
  local d = math.max(1, hypot(px - cx, py - cy))
  local speed = 190
  local t = d / speed
  -- (aimed a little ahead of where the hunter is running, and over the drop)
  local lx = px + player.body.vx * t * 0.5
  local ly = py + player.body.vy * t * 0.3 - 0.5 * 90 * t * t
  local ang = math.atan2(ly - cy, lx - cx)
  bile[#bile + 1] = {
    x = cx + math.cos(ang) * 5, y = cy + math.sin(ang) * 5,
    vx = math.cos(ang) * speed, vy = math.sin(ang) * speed,
    life = 3, dmg = math.max(1, math.floor(7 * e.dmgMul + 0.5)),
  }
  audio.playAt("crow_spit", cx, cy, 0.9, 0.9 + love.math.random() * 0.2)
end

-- The crow -----------------------------------------------------------------------------------------------

local function updateCrow(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.phase = e.phase + dt * (e.state == "spit" and 7 or 16)
  e.attackCd = math.max(0, (e.attackCd or (1 + love.math.random() * 1.5)) - dt)
  if e.state == "sleep" then
    if e.seesPlayer and dist < def.sight then
      e.state = "chase"
      audio.playAt("crow_caw", cx, cy, 0.8, 1.1)
    else
      return
    end
  end
  local collide = collider(e, world)
  -- Circle the hunter, a little above him, the way round chosen at random
  e.orbDir = e.orbDir or (love.math.random() < 0.5 and -1 or 1)
  e.orbA = (e.orbA or love.math.random() * math.pi * 2) + dt * e.orbDir * (e.state == "spit" and 0.3 or 1.15)
  local R = def.orbit * (e.seesPlayer and 1 or 0.4)
  local tx, ty = px + math.cos(e.orbA) * R, py - 24 + math.sin(e.orbA) * R * 0.55
  local wantx = math.max(-def.speed, math.min(def.speed, (tx - cx) * 3))
  local wanty = math.max(-def.speed, math.min(def.speed, (ty - cy) * 3)) + math.sin(e.phase * 0.2) * 14
  if not e.seesPlayer then
    local fx, fy = flowDirection(world, cx, cy, px, py - 4) -- (round the rock, not into it)
    if fx then
      wantx, wanty = fx * def.speed, fy * def.speed
    end
  end
  if e.state == "spit" then
    wantx, wanty = wantx * 0.2, wanty * 0.2
    e.timer = e.timer - dt
    if e.timer <= 0 then
      spit(e, world, player, px, py)
      e.state = "chase"
      e.attackCd = 1.9 + love.math.random() * 1.6
    end
  elseif e.seesPlayer and dist < def.spitRange and e.attackCd <= 0 and e.stun <= 0 then
    e.state = "spit"
    e.timer = 0.4 -- (the beak opens, the head goes back)
    audio.playAt("crow_caw", cx, cy, 0.9, 1.3)
  end
  if e.stun <= 0 then
    local step = def.accel * dt
    b.vx = b.vx < wantx and math.min(b.vx + step, wantx) or math.max(b.vx - step, wantx)
    b.vy = b.vy < wanty and math.min(b.vy + step, wanty) or math.max(b.vy - step, wanty)
  end
  e.facing = px >= cx and 1 or -1
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.5
    e.orbDir = -e.orbDir
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.5
  end
end

local CROW = { body = { 0.07, 0.05, 0.10 }, dark = { 0.035, 0.025, 0.055 }, sheen = { 0.36, 0.25, 0.55 }, beak = { 0.50, 0.44, 0.30 } }

local function drawCrow(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c, a)
    if white then
      love.graphics.setColor(1, 1, 1)
    else
      love.graphics.setColor(c[1], c[2], c[3], a or 1)
    end
  end
  local mid, y = b.x + b.w / 2, b.y
  local f = e.facing
  if e.state == "sleep" then
    -- hanging upside down with its wings wrapped round it
    color(CROW.body)
    rect(mid - 3, y + 1, 6, 5)
    rect(mid - 2, y + 6)
    rect(mid + 1, y + 6)
    color(CROW.sheen, 0.6)
    rect(mid - 2, y + 2, 1, 3)
    color(CROW.dark)
    rect(mid - 1, y, 2, 2)
    return
  end
  local flap = math.sin(e.phase)
  local cy = y + 4
  -- wings: swept up and down on the flap
  for side = -1, 1, 2 do
    local far = side == f
    color(far and CROW.dark or CROW.body)
    love.graphics.polygon("fill", mid, cy - 1, mid - f * 2, cy + 1, mid - f * 6 + side * 0, cy - 1 - flap * 5 - (e.state == "spit" and 3 or 0), mid - f * 9, cy - flap * 4)
  end
  -- body, tail, head and beak
  color(CROW.body)
  rect(mid - 3, cy - 1, 6, 4)
  color(CROW.dark)
  rect(mid - f * 5 - (f > 0 and 1 or 0), cy, 3, 2)
  color(CROW.body)
  rect(mid + f * 3 - (f < 0 and 2 or 0), cy - 2, 3, 3)
  color(CROW.beak)
  local open = e.state == "spit" and 2 or 0
  rect(mid + f * 5 - (f < 0 and 2 or 0), cy - 1, 2, 1)
  if open > 0 then
    rect(mid + f * 5 - (f < 0 and 2 or 0), cy + 1, 2, 1)
  end
  color(CROW.sheen, 0.7)
  rect(mid - 1, cy - 1, 3, 1)
end

local function drawCrowGlow(e)
  if e.state == "sleep" then
    return
  end
  local b = e.body
  local f = e.facing
  love.graphics.setColor(1, 0.9, 0.35)
  rect(b.x + b.w / 2 + f * 4 - (f < 0 and 1 or 0), b.y + 2)
end

-- The ram ---------------------------------------------------------------------------------------------------

local function updateRam(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local collide = collider(e, world)
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
  e.phase = e.phase + math.abs(b.vx) * dt * 0.08
  e.contactMul = e.state == "charge" and 1.7 or 0.6
  if e.state == "idle" and e.seesPlayer and dist < def.sight then
    e.state = "chase"
    audio.playAt("ram_snort", cx, cy, 0.8, 0.85)
  elseif e.state == "chase" and dist > def.forget then
    e.state = "idle"
  end
  local want = 0
  if e.state == "idle" then
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.timer = 2 + love.math.random() * 3
      e.facing = love.math.random() < 0.5 and -1 or 1
      e.wander = love.math.random() < 0.5
    end
    want = e.wander and e.facing * def.speed * 0.4 or 0
  elseif e.state == "chase" then
    e.facing = px < cx and -1 or 1
    want = e.facing * def.speed
    if e.stun <= 0 and e.cooldown <= 0 and e.grounded and e.seesPlayer and dist > 55 and dist < 260 and math.abs(py - cy) < 40 then
      e.state, e.timer, e.stamps = "paw", 0.8, 0
      audio.playAt("ram_snort", cx, cy, 1, 1)
    end
  elseif e.state == "paw" then
    -- head down, a foreleg pawing: it has made up its mind
    e.facing = px < cx and -1 or 1
    e.timer = e.timer - dt
    if e.timer < 0.55 and e.stamps == 0 or e.timer < 0.3 and e.stamps == 1 then
      e.stamps = e.stamps + 1
      audio.playAt("ram_stamp", cx, cy, 0.9, 1 - e.stamps * 0.05)
      for _ = 1, 4 do
        effects.particle(cx + e.facing * 9, b.y + b.h, -e.facing * (10 + love.math.random() * 30), -10 - love.math.random() * 30, 0.4, { 0.5, 0.4, 0.3 }, 120)
      end
    end
    if e.timer <= 0 then
      e.state, e.timer = "charge", 1.2
      b.vx = e.facing * def.chargeSpeed
    end
  elseif e.state == "charge" then
    e.timer = e.timer - dt
    b.vx = e.facing * def.chargeSpeed
    if love.math.random() < dt * 30 then
      effects.particle(cx - e.facing * 10, b.y + b.h - 1, -e.facing * 20, -15, 0.35, { 0.55, 0.45, 0.35 }, 80)
    end
    if e.timer <= 0 then
      e.state, e.timer = "recover", 0.6
      e.cooldown = 2.2 + love.math.random()
    end
  elseif e.state == "recover" then
    e.timer = e.timer - dt
    b.vx = b.vx * math.exp(-8 * dt)
    if e.timer <= 0 then
      e.state = "chase"
    end
  elseif e.state == "dizzy" then
    e.timer = e.timer - dt
    b.vx = b.vx * math.exp(-8 * dt)
    if e.timer <= 0 then
      e.state = "chase"
      e.cooldown = 1.5
    end
  end
  if e.state == "idle" or e.state == "chase" then
    local accel = e.grounded and 600 or 200
    b.vx = b.vx < want and math.min(want, b.vx + accel * dt) or math.max(want, b.vx - accel * dt)
  elseif e.state == "paw" then
    b.vx = b.vx * math.exp(-10 * dt)
  end
  b.vy = math.min(b.vy + config.gravity * dt, 450)
  local blocked = Body.moveX(b, collide, b.vx * dt, 5)
  if blocked then
    if e.state == "charge" then
      -- Skull on rock: a crack, a shower of grit and a long daze
      e.state, e.timer = "dizzy", 1.6
      b.vx = -e.facing * 40
      b.vy = -70
      audio.playAt("ram_crash", cx + e.facing * 11, cy, 1, 1)
      require("src.camera").shake(0.18)
      for _ = 1, 12 do
        effects.particle(cx + e.facing * 11, cy + (love.math.random() - 0.5) * 10, -e.facing * love.math.random() * 90, -love.math.random() * 90, 0.5, { 0.5, 0.4, 0.32 }, 300)
      end
      effects.ring(cx + e.facing * 11, cy, 16, { 0.8, 0.7, 0.5 })
    elseif e.grounded and e.state == "chase" then
      b.vy = -def.jump
    end
    b.vx = 0
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = 0
  end
  if e.grounded and b.vy >= 0 then
    Body.snapDown(b, collide, 5)
  end
end

local RAM = { wool = { 0.60, 0.55, 0.46 }, woolDark = { 0.38, 0.34, 0.29 }, horn = { 0.82, 0.76, 0.60 }, hornDark = { 0.55, 0.49, 0.37 }, face = { 0.30, 0.26, 0.23 }, hoof = { 0.12, 0.10, 0.10 } }

local function drawRam(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local f = e.facing
  local x, y = b.x + b.w / 2, b.y
  local walk = (e.grounded and math.abs(b.vx) > 4) and math.sin(e.phase) or 0
  local dip = (e.state == "paw") and 1 or 0
  local tilt = e.state == "dizzy" and math.sin(love.timer.getTime() * 9) * 1 or 0
  local function X(dx)
    return x + f * dx - (f < 0 and 0 or 0)
  end
  -- legs
  color(RAM.hoof)
  rect(X(-7) - 1, y + 11 + (walk > 0 and -1 or 0), 2, 4)
  rect(X(-3) - 1, y + 11 + (walk < 0 and -1 or 0), 2, 4)
  rect(X(3) - 1, y + 11 + (walk < 0 and -1 or 0), 2, 4)
  if e.state == "paw" and math.floor(love.timer.getTime() * 10) % 2 == 0 then
    rect(X(7) - 1, y + 9, 2, 2) -- (a foreleg pawing)
  else
    rect(X(7) - 1, y + 11 + (walk > 0 and -1 or 0), 2, 4)
  end
  -- shaggy body
  color(RAM.woolDark)
  rect(x - 9, y + 3 + dip, 18, 9)
  color(RAM.wool)
  rect(x - 9, y + 2 + dip, 17, 8)
  rect(x - 7, y + 1 + dip, 13, 2)
  for k = 0, 3 do
    rect(x - 8 + k * 4, y + 10 + dip, 2, 1 + (k % 2))
  end
  -- head: low in a charge, with the curl of the horn
  local hy = y + 3 + dip + (e.state == "charge" and 3 or (e.state == "paw" and 2 or 0)) + tilt
  color(RAM.face)
  rect(X(9) - (f < 0 and 4 or 0), hy, 5, 5)
  rect(X(13) - (f < 0 and 2 or 0), hy + 3, 2, 2)
  color(RAM.hornDark)
  rect(X(8) - (f < 0 and 5 or 0), hy - 1, 6, 2)
  rect(X(8) - (f < 0 and 2 or 0), hy + 1, 3, 3)
  color(RAM.horn)
  rect(X(9) - (f < 0 and 5 or 0), hy - 2, 5, 1)
  rect(X(13) - (f < 0 and 2 or 0), hy - 1, 1, 3)
  rect(X(13) - (f < 0 and 2 or 0), hy + 2)
  if e.state == "dizzy" then
    -- stars wheeling over its head
    local t = love.timer.getTime() * 6
    for k = 0, 2 do
      love.graphics.setColor(1, 0.95, 0.5)
      rect(x + math.cos(t + k * 2.1) * 6, y - 3 + math.sin(t + k * 2.1) * 2)
    end
  end
end

local function drawRamGlow(e)
  local b = e.body
  local f = e.facing
  local hy = b.y + 3 + (e.state == "paw" and 2 or 0) + (e.state == "charge" and 3 or 0) + 1
  love.graphics.setColor(e.state == "charge" and 1 or 0.95, e.state == "charge" and 0.3 or 0.7, 0.2)
  rect(b.x + b.w / 2 + f * 11 - (f < 0 and 1 or 0), hy)
end

-- The dust devil ---------------------------------------------------------------------------------------------

local function updateDevil(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.phase = e.phase + dt * (e.state == "blow" and 22 or (e.state == "spin" and 16 or 8))
  e.attackCd = math.max(0, (e.attackCd or (2 + love.math.random() * 2)) - dt)
  if e.state == "sleep" or e.state == "idle" then
    if e.seesPlayer and dist < def.sight then
      e.state = "chase"
    else
      return
    end
  end
  local collide = collider(e, world)
  local tx, ty = px - sign(px - cx) * 70, py - 18
  local wantx = math.max(-def.speed, math.min(def.speed, (tx - cx) * 1.5))
  local wanty = math.max(-def.speed, math.min(def.speed, (ty - cy) * 1.5)) + math.sin(e.phase * 0.3) * 12
  if not e.seesPlayer then
    local fx, fy = flowDirection(world, cx, cy, px, py - 4)
    if fx then
      wantx, wanty = fx * def.speed, fy * def.speed
    end
  end
  if e.state == "spin" then
    wantx, wanty = wantx * 0.2, wanty * 0.2
    e.timer = e.timer - dt
    if love.math.random() < dt * 30 then
      effects.particle(cx + (love.math.random() - 0.5) * 20, cy + 8, 0, -20, 0.4, { 0.75, 0.65, 0.5 }, 0)
    end
    if e.timer <= 0 then
      e.state, e.timer = "blow", 1.4
      audio.playAt("gust_blast", cx, cy, 1, 1)
      e.gdir = sign(px - cx)
    end
  elseif e.state == "blow" then
    -- A gale: the hunter within reach is thrown along it, and everything loose with him
    e.timer = e.timer - dt
    wantx, wanty = 0, 0
    local pb = player.body
    if not player.dead and math.abs(px - cx) < def.gale and math.abs(py - cy) < def.gale * 0.7 then
      local k = 1 - math.abs(px - cx) / def.gale
      pb.vx = pb.vx + e.gdir * 900 * k * dt
      pb.vy = pb.vy - 90 * k * dt
    end
    require("src.fog").push(cx, cy, def.gale, e.gdir * 260, -20)
    if love.math.random() < dt * 60 then
      effects.particle(cx + e.gdir * (6 + love.math.random() * 30), cy + (love.math.random() - 0.5) * 30, e.gdir * (120 + love.math.random() * 120), (love.math.random() - 0.5) * 30, 0.45, { 0.8, 0.7, 0.55 }, 0)
    end
    if e.timer <= 0 then
      e.state = "chase"
      e.attackCd = 4 + love.math.random() * 2
    end
  elseif e.seesPlayer and dist < def.gale and e.attackCd <= 0 and e.stun <= 0 then
    e.state, e.timer = "spin", 0.8
    audio.playAt("wind_howl", cx, cy, 1, 1.15)
  end
  if e.stun <= 0 then
    local step = def.accel * dt
    b.vx = b.vx < wantx and math.min(b.vx + step, wantx) or math.max(b.vx - step, wantx)
    b.vy = b.vy < wanty and math.min(b.vy + step, wanty) or math.max(b.vy - step, wanty)
  end
  e.facing = px >= cx and 1 or -1
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.4
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.4
  end
  if love.math.random() < dt * 14 then
    effects.particle(cx + (love.math.random() - 0.5) * 8, b.y + b.h - 2, (love.math.random() - 0.5) * 12, -8, 0.5, { 0.7, 0.6, 0.45 }, 0)
  end
end

local function drawDevil(e)
  local b = e.body
  local white = e.flash > 0
  local mid = b.x + b.w / 2
  local spin = e.state == "spin" or e.state == "blow"
  local t = e.phase
  -- stacked, wobbling arcs of grit, narrow at the foot and wide at the top
  for row = 0, 10 do
    local u = row / 10
    local y = b.y + row * 2
    local w = (2 + u * 11) * (spin and 1.2 or 1)
    local off = math.sin(t * 0.7 + row * 0.9) * (1 + u * 2)
    local shade = 0.55 + 0.25 * math.sin(t + row * 1.7)
    love.graphics.setColor(white and { 1, 1, 1 } or { 0.78 * shade + 0.1, 0.66 * shade + 0.1, 0.50 * shade + 0.1, 0.8 })
    rect(mid + off - w / 2, y, w, 2)
    -- the leading edge of each ring, lighter
    love.graphics.setColor(white and { 1, 1, 1 } or { 0.95, 0.88, 0.7, 0.7 })
    local ex = mid + off + math.cos(t * 1.3 + row) * w / 2
    rect(ex, y, 1, 1)
  end
  -- flung grit
  for k = 0, 5 do
    local ang = t * 1.6 + k * 1.05
    local r = 5 + (k % 3) * 3
    love.graphics.setColor(0.85, 0.75, 0.55, 0.8)
    rect(mid + math.cos(ang) * r, b.y + 3 + (k * 3 + t * 4) % 18, 1, 1)
  end
end

local function drawDevilGlow(e)
  local b = e.body
  local mid = b.x + b.w / 2
  love.graphics.setColor(1, 0.9, 0.55)
  rect(mid - 2, b.y + 9, 1, 1)
  rect(mid + 1, b.y + 9, 1, 1)
end

-- The gargoyle ------------------------------------------------------------------------------------------------

local function crashGargoyle(e, player, cx, cy)
  audio.playAt("gargoyle_crash", cx, cy, 1, 1)
  require("src.camera").shake(0.3)
  effects.ring(cx, cy + 6, 30, { 0.7, 0.7, 0.78 })
  for _ = 1, 14 do
    effects.chunk(cx, cy + 6, (love.math.random() - 0.5) * 140, -30 - love.math.random() * 90, 2, 2, { 0.5, 0.5, 0.55 }, 1.5)
  end
  if not player.dead then
    local px, py = player:center()
    if hypot(px - cx, py - (cy + 6)) < 34 then
      if player:hurt(math.max(1, math.floor(14 * e.dmgMul + 0.5)), cx, cy, "gargoyle") then
        player.lastEnemy = e
      end
    end
  end
end

local function updateGargoyle(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.phase = e.phase + dt * (e.state == "fly" and 10 or 4)
  e.attackCd = math.max(0, (e.attackCd or 3) - dt)
  local collide = collider(e, world)
  if e.state == "sleep" then
    -- hanging among the stalactites: it comes down on whoever walks beneath
    local below = math.abs(px - cx) < 70 and py > cy and py - cy < 280
    if (e.seesPlayer and dist < def.sight) or (below and e.seesPlayer) then
      e.state, e.timer = "wake", 0.55
      audio.playAt("gargoyle_grind", cx, cy, 1, 0.9)
    else
      return
    end
  end
  if e.state == "wake" then
    e.timer = e.timer - dt -- (cracks run through it, grit falls)
    if love.math.random() < dt * 30 then
      effects.particle(cx + (love.math.random() - 0.5) * 10, cy + 4, 0, 30, 0.5, { 0.5, 0.5, 0.55 }, 200)
    end
    if e.timer <= 0 then
      e.state = "drop"
      b.vy = 20
    end
    return
  end
  if e.state == "drop" then
    b.vy = math.min(b.vy + config.gravity * 1.2 * dt, 520)
    b.vx = b.vx + (px - cx) * 0.6 * dt -- (a little steering)
    Body.moveX(b, collide, b.vx * dt, 0)
    if Body.moveY(b, collide, b.vy * dt) then
      crashGargoyle(e, player, cx, cy)
      e.state, e.timer = "grind", 0.9
      b.vy, b.vx = 0, 0
    end
    return
  end
  if e.state == "grind" then
    -- dazed among the rubble, wings unfolding
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.state = "fly"
      e.attackCd = 3
      b.vy = -60
    end
    return
  end
  local tx, ty = 0, 0
  local d = math.max(1, dist)
  local steer = true
  if e.state == "fly" then
    tx, ty = (px - cx) / d * def.speed, (py - 4 - cy) / d * def.speed + math.sin(e.phase * 0.4) * 24
    if not e.seesPlayer then
      local fx, fy = flowDirection(world, cx, cy, px, py - 4)
      if fx then
        tx, ty = fx * def.speed, fy * def.speed
      end
    end
    if e.seesPlayer and dist < 190 and e.attackCd <= 0 and e.stun <= 0 then
      e.state, e.timer = "stone", 0.7
      audio.playAt("gargoyle_grind", cx, cy, 1, 1.2)
    end
  elseif e.state == "stone" then
    -- turned to stone, hanging in the air, eyes on the hunter
    e.timer = e.timer - dt
    e.facing = px >= cx and 1 or -1
    b.vx, b.vy = b.vx * math.exp(-10 * dt), b.vy * math.exp(-10 * dt)
    steer = false
    if e.timer <= 0 then
      e.state, e.timer = "lunge", 0.5
      b.vx, b.vy = (px - cx) / d * def.lungeSpeed, (py - cy) / d * def.lungeSpeed
      audio.playAt("gust_blast", cx, cy, 0.5, 1.4)
    end
  elseif e.state == "lunge" then
    steer = false
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.state = "fly"
      e.attackCd = 4 + love.math.random() * 2
    end
  end
  if steer then
    if e.stun <= 0 then
      local step = def.accel * dt
      b.vx = b.vx < tx and math.min(b.vx + step, tx) or math.max(b.vx - step, tx)
      b.vy = b.vy < ty and math.min(b.vy + step, ty) or math.max(b.vy - step, ty)
    end
    if tx ~= 0 then
      e.facing = tx > 0 and 1 or -1
    end
  end
  local hit = false
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.4
    hit = true
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.4
    hit = true
  end
  if hit and e.state == "lunge" then
    e.state, e.timer = "fly", 0
    e.attackCd = 3
    e.stun = 0.4
  end
end

local ST = { stone = { 0.50, 0.50, 0.56 }, dark = { 0.28, 0.28, 0.34 }, light = { 0.70, 0.70, 0.76 }, moss = { 0.30, 0.42, 0.30 } }

local function drawGargoyle(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local mid, y = b.x + b.w / 2, b.y
  local f = e.facing
  local st = e.state
  local stoned = st == "sleep" or st == "stone" or st == "drop" or st == "wake"
  local shake = st == "wake" and math.sin(love.timer.getTime() * 60) * 0.7 or 0
  mid = mid + shake
  local flap = math.sin(e.phase)
  local open = (st == "fly" or st == "lunge") and not stoned
  -- wings: folded round it when still, spread when it flies
  for side = -1, 1, 2 do
    color(open and ST.dark or ST.stone)
    if open then
      local lift = flap * 4
      love.graphics.polygon("fill", mid + side * 2, y + 5, mid + side * 9, y + 1 - lift, mid + side * 14, y + 5 - lift * 0.6, mid + side * 10, y + 8, mid + side * 3, y + 10)
      color(ST.light)
      love.graphics.line(mid + side * 2, y + 5, mid + side * 9, y + 1 - lift)
    else
      love.graphics.polygon("fill", mid + side * 2, y + 4, mid + side * 5, y + 5, mid + side * 4, y + 14, mid + side * 1, y + 12)
    end
  end
  -- torso, legs and a tail
  color(ST.stone)
  rect(mid - 3, y + 5, 6, 7)
  color(ST.dark)
  rect(mid - 3, y + 10, 6, 2)
  rect(mid - 3, y + 12, 2, 3)
  rect(mid + 1, y + 12, 2, 3)
  rect(mid - f * 4 - (f > 0 and 1 or 0), y + 11, 2, 3)
  -- head: horns, a heavy brow, a fanged mouth
  color(ST.stone)
  rect(mid - 3, y + 1, 6, 5)
  color(ST.light)
  rect(mid - 3, y + 1, 6, 1)
  color(ST.dark)
  rect(mid - 4, y, 1, 2)
  rect(mid + 3, y, 1, 2)
  rect(mid - 3, y + 3, 6, 1)
  rect(mid - 2, y + 5, 1, 1)
  rect(mid + 1, y + 5, 1, 1)
  -- moss and cracks
  color(ST.moss)
  rect(mid - 3, y + 7, 2, 1)
  rect(mid + 2, y + 1, 1, 1)
  if st == "wake" then
    color(ST.dark)
    rect(mid - 1, y + 2, 1, 3)
    rect(mid + 1, y + 6, 1, 3)
  end
end

local function drawGargoyleGlow(e)
  local st = e.state
  if st == "sleep" or st == "drop" then
    return
  end
  local b = e.body
  local mid = b.x + b.w / 2
  local c = st == "stone" and { 0.9, 0.9, 1 } or { 1, 0.5, 0.2 }
  love.graphics.setColor(c)
  rect(mid - 2, b.y + 3)
  rect(mid + 1, b.y + 3)
end

-- Hooks ---------------------------------------------------------------------------------------------------------

enemies.UPDATE.crow = updateCrow
enemies.DRAW.crow = drawCrow
enemies.GLOW.crow = drawCrowGlow
enemies.UPDATE.cragram = updateRam
enemies.DRAW.cragram = drawRam
enemies.GLOW.cragram = drawRamGlow
enemies.UPDATE.dustdevil = updateDevil
enemies.DRAW.dustdevil = drawDevil
enemies.GLOW.dustdevil = drawDevilGlow
enemies.UPDATE.gargoyle = updateGargoyle
enemies.DRAW.gargoyle = drawGargoyle
enemies.GLOW.gargoyle = drawGargoyleGlow

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  local pb = player.body
  for i = #bile, 1, -1 do
    local s = bile[i]
    s.life = s.life - dt
    s.vy = s.vy + 90 * dt
    local steps = math.max(1, math.ceil(math.max(math.abs(s.vx), math.abs(s.vy)) * dt / 2))
    local gone = s.life <= 0
    for _ = 1, steps do
      if gone then
        break
      end
      s.x, s.y = s.x + s.vx * dt / steps, s.y + s.vy * dt / steps
      if world:isSolid(s.x, s.y) then
        for _ = 1, 4 do
          effects.particle(s.x, s.y, (love.math.random() - 0.5) * 50, -love.math.random() * 40, 0.4, { 0.25, 0.1, 0.35 }, 200)
        end
        gone = true
      elseif not player.dead and overlaps(s.x - 1, s.y - 1, 3, 3, pb.x, pb.y, pb.w, pb.h) then
        player:hurt(s.dmg, s.x - s.vx * 0.05, s.y - s.vy * 0.05, "crow")
        for _ = 1, 5 do
          effects.particle(s.x, s.y, (love.math.random() - 0.5) * 60, -love.math.random() * 50, 0.4, { 0.3, 0.12, 0.4 }, 200)
        end
        gone = true
      end
    end
    if gone then
      table.remove(bile, i)
    end
  end
end

local prevEmissive = enemies.afterEmissive
enemies.afterEmissive = function(view)
  if prevEmissive then
    prevEmissive(view)
  end
  for _, s in ipairs(bile) do
    love.graphics.setColor(0.45, 0.2, 0.6, 0.5)
    rect(s.x - 2, s.y - 2, 4, 4)
    love.graphics.setColor(0.75, 0.45, 0.95)
    rect(s.x - 1, s.y - 1, 2, 2)
  end
end

local prevClear = enemies.clear
enemies.clear = function()
  prevClear()
  bile = {}
end

return true
