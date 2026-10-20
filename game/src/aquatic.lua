-- The water's creatures and the fish boss of the Deep. They register
-- themselves with src.enemies (defs, update, draw, glow), so enemies.lua
-- stays as it is.
--
--   jellyfish   pink, glowing; moves in pulses, and now and then shocks everything in a ring
--               round it (and the water carries it to a hunter swimming there)
--   angler      a dark lurker with a glowing lure; hangs still, then lunges and snaps
--   urchin      a drifting ball of spines that rattles, then looses them in all directions
--   bigfish     the boss: four fish, each eating the one before it (Big Fish, Bigger Fish,
--               Even Bigger Fish, The Biggest Fish)
local enemies = require("src.enemies")
local Body = require("src.body")
local audio = require("src.audio")
local config = require("src.config")
local effects = require("src.effects")
local fluids = require("src.fluids")

local H = enemies.helpers
local center, collider, sfx = H.center, H.collider, H.sfx

local aquatic = {}

local function rect(c, x, y, w, h, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

local function hypot(x, y)
  return math.sqrt(x * x + y * y)
end

-- Little creatures stay in the water: turn back at its edge; out of it they sink
local function swim(e, dt, world, stayWet)
  local b = e.body
  local cx, cy = center(e)
  local wet = fluids.waterAt(cx, cy)
  if not wet then
    b.vy = math.min(b.vy + config.gravity * dt, 300)
  elseif stayWet ~= false then
    local sx = b.vx > 0 and 1 or -1
    if not fluids.waterAt(cx + sx * (b.w / 2 + 3), cy) then
      b.vx = -b.vx * 0.6
      e.dirX = e.dirX and -e.dirX
    end
    local sy = b.vy > 0 and 1 or -1
    if not fluids.waterAt(cx, cy + sy * (b.h / 2 + 3)) then
      b.vy = -b.vy * 0.6
      e.dirY = e.dirY and -e.dirY
    end
  end
  local collide = collider(e, world)
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.4
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = wet and -b.vy * 0.4 or 0
  end
  return wet
end

local function preyInWater(player)
  local pb = player.body
  return fluids.waterTouching(pb.x, pb.y, pb.w, pb.h)
end

-- Spines and bubbles in flight (urchins, the Bigger Fish) -------------------------------

local shots = {} -- { x, y, vx, vy, life, damage, kind = "spine" | "bubble", r }

local function addShot(x, y, vx, vy, life, damage, kind, r)
  shots[#shots + 1] = { x = x, y = y, vx = vx, vy = vy, life = life, damage = damage, kind = kind, r = r or 1 }
end

-- Jellyfish ----------------------------------------------------------------------------------

local jelly = {
  w = 14,
  h = 14,
  hp = 14,
  speed = 38,
  sight = 210,
  forget = 320,
  damage = 4,
  gold = { 2, 5 },
  knockback = 0.5,
  weight = 0.3,
  light = function(e)
    local cx, cy = center(e)
    return { cx, cy, e.shockT and 52 or 32, 1, 0.45, 0.85, e.shockT and 0.9 or 0.5 }
  end,
}

local SHOCK_RADIUS = 46

local function updateJelly(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.phase = e.phase + dt * 2
  e.bell = math.max(0, (e.bell or 0) - dt * 2.2)
  e.pulseT = (e.pulseT or 0.6) - dt
  e.shockCd = (e.shockCd or (2 + love.math.random() * 3)) - dt
  local preyWet = not player.dead and preyInWater(player)
  local hunting = preyWet and dist < (e.state == "chase" and def.forget or def.sight)
  e.state = hunting and "chase" or "idle"
  local wet = fluids.waterAt(cx, cy)
  if e.stun > 0 or not wet then
    -- (knocked about, or out of the water)
  elseif e.shockT then
    e.shockT = e.shockT - dt
    local k = math.exp(-dt * 5)
    b.vx, b.vy = b.vx * k, b.vy * k
    if love.math.random() < dt * 40 then
      local a = love.math.random() * math.pi * 2
      effects.particle(cx + math.cos(a) * 8, cy + math.sin(a) * 8, math.cos(a) * 30, math.sin(a) * 30, 0.25, { 1, 0.6, 0.95 }, 0, true)
    end
    if e.shockT <= 0 then
      e.shockT = nil
      effects.ring(cx, cy, SHOCK_RADIUS, { 1, 0.55, 0.95 })
      for _ = 1, 14 do
        local a = love.math.random() * math.pi * 2
        effects.particle(cx, cy, math.cos(a) * 110, math.sin(a) * 110, 0.35, { 1, 0.7, 1 }, 0, true)
      end
      sfx("jelly_zap", 1)
      if not player.dead and preyWet and dist < SHOCK_RADIUS + 4 then
        player:hurt(math.floor(9 * e.dmgMul + 0.5), cx, cy, "jellyfish")
      end
    end
  else
    if e.pulseT <= 0 then
      e.pulseT = 1.3 + love.math.random() * 0.9
      local ang
      if hunting then
        ang = math.atan2(py - cy, px - cx) + (love.math.random() - 0.5) * 0.6
      else
        ang = -math.pi / 2 + (love.math.random() - 0.5) * 2.4
      end
      local sp = def.speed * (hunting and 2.1 or 1.3)
      b.vx, b.vy = math.cos(ang) * sp, math.sin(ang) * sp
      e.bell = 1
      sfx("jelly_pulse", 0.8, 0.9 + love.math.random() * 0.2)
    end
    local k = math.exp(-dt * 2.4)
    b.vx, b.vy = b.vx * k, b.vy * k + 6 * dt -- (it sinks, very slowly, between pulses)
    if hunting and dist < 100 and e.shockCd <= 0 then
      e.shockT = 0.6
      e.shockCd = 4.5 + love.math.random() * 3
      sfx("jelly_zap", 0.35, 1.6)
    end
  end
  if math.abs(b.vx) > 4 then
    e.facing = b.vx < 0 and -1 or 1
  end
  swim(e, dt, world)
end

local function drawJelly(e)
  local b = e.body
  local x, y = math.floor(b.x), math.floor(b.y)
  local t = love.timer.getTime() + e.phase
  local sq = e.bell or 0
  local w = 14 - math.floor(sq * 3 + 0.5)
  local ox = x + math.floor((14 - w) / 2)
  local flash = e.flash > 0
  local main = flash and { 1, 1, 1 } or { 0.90, 0.44, 0.78 }
  local light = flash and { 1, 1, 1 } or { 1, 0.74, 0.94 }
  local dark = flash and { 1, 1, 1 } or { 0.58, 0.24, 0.60 }
  rect(dark, ox + 3, y, w - 6, 1)
  rect(main, ox + 1, y + 1, w - 2, 2)
  rect(main, ox, y + 3, w, 3)
  rect(light, ox + 3, y + 1, 4, 1)
  rect(light, ox + 2, y + 2, 2, 1)
  rect(dark, ox, y + 6, w, 1)
  for i = 0, 3 do
    local tx = ox + 1 + math.floor(i * (w - 3) / 3)
    local len = 5 + (i % 2) * 2
    for k = 0, len - 1 do
      local sway = math.floor(math.sin(t * 5 + k * 0.8 + i * 1.7) * 1.1 + 0.5)
      rect({ 0.85, 0.4, 0.78 }, tx + sway, y + 7 + k, 1, 1, 0.85 - k * 0.07)
    end
  end
end

local function drawJellyGlow(e)
  local b = e.body
  local x, y = math.floor(b.x), math.floor(b.y)
  local pulse = 0.55 + 0.35 * math.sin(love.timer.getTime() * 3 + e.phase)
  local w = 14 - math.floor((e.bell or 0) * 3 + 0.5)
  local ox = x + math.floor((14 - w) / 2)
  rect({ 1, 0.6, 0.95 }, ox + 1, y + 3, w - 2, 1, pulse)
  rect({ 1, 0.8, 1 }, ox + 3, y + 1, 3, 1, pulse)
  if e.shockT then
    -- a ring of crackling arcs gathering
    local cx, cy = center(e)
    local k = 1 - e.shockT / 0.6
    for i = 0, 9 do
      local a = i / 10 * math.pi * 2 + love.timer.getTime() * 6
      local r = SHOCK_RADIUS * k
      rect({ 1, 0.7, 1 }, cx + math.cos(a) * r, cy + math.sin(a) * r, 1, 1, 0.5 + 0.5 * k)
    end
  end
end

-- Anglerfish ----------------------------------------------------------------------------------

local angler = {
  w = 18,
  h = 11,
  hp = 32,
  speed = 30,
  sight = 170,
  forget = 280,
  damage = 12,
  gold = { 3, 7 },
  knockback = 0.4,
  weight = 0.8,
  light = function(e)
    local cx, cy = center(e)
    local f = e.facing or 1
    return { cx + f * 12, cy - 9, e.windT and 56 or 38, 0.55, 1, 0.9, e.windT and 0.9 or 0.6 }
  end,
}

local function updateAngler(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.phase = e.phase + dt
  local preyWet = not player.dead and preyInWater(player)
  local hunting = preyWet and dist < (e.state == "chase" and def.forget or def.sight)
  e.state = hunting and "chase" or "idle"
  local wet = fluids.waterAt(cx, cy)
  e.lureT = (e.lureT or 1.5) - dt
  if e.lureT <= 0 and hunting then
    e.lureT = 4 + love.math.random() * 3
    sfx("angler_lure", 0.8, 0.9 + love.math.random() * 0.2)
  end
  if wet and e.stun <= 0 then
    if e.dashT and e.dashT > 0 then
      e.dashT = e.dashT - dt
      local k = math.exp(-dt * 1.2)
      b.vx, b.vy = b.vx * k, b.vy * k
    elseif e.windT then
      -- The lure flares, and it hangs there, jaws parting
      e.windT = e.windT - dt
      local k = math.exp(-dt * 6)
      b.vx, b.vy = b.vx * k, b.vy * k
      e.facing = px < cx and -1 or 1
      if e.windT <= 0 then
        e.windT = nil
        e.dashT = 0.35
        local d = math.max(1, dist)
        b.vx, b.vy = (px - cx) / d * 250, (py - cy) / d * 250
        sfx("angler_snap", 1, 0.9 + love.math.random() * 0.2)
        e.cooldown = 1.6
      end
    elseif hunting and dist < 85 and e.cooldown <= 0 then
      e.windT = 0.45
      e.facing = px < cx and -1 or 1
    else
      local tx, ty
      if hunting then
        local d = math.max(1, dist)
        tx, ty = (px - cx) / d * def.speed, (py - cy) / d * def.speed
        e.facing = px < cx and -1 or 1
      else
        e.timer = e.timer - dt
        if e.timer <= 0 or not e.heading then
          e.timer = 2 + love.math.random() * 3
          e.heading = love.math.random() * math.pi * 2
        end
        tx, ty = math.cos(e.heading) * def.speed * 0.2, math.sin(e.heading) * def.speed * 0.12
      end
      local k = math.min(1, dt * 3)
      b.vx, b.vy = b.vx + (tx - b.vx) * k, b.vy + (ty - b.vy) * k
    end
  end
  if math.abs(b.vx) > 12 then
    e.facing = b.vx < 0 and -1 or 1
  end
  swim(e, dt, world)
end

-- (a sprite mirrored about its width, like src.enemies' own)
local function mirror(e, w)
  local b = e.body
  local x, y = math.floor(b.x), math.floor(b.y)
  local f = e.facing or 1
  return function(c, dx, dy, ww, hh, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
    love.graphics.rectangle("fill", f > 0 and x + dx or x + w - dx - ww, y + dy, ww, hh)
  end
end

local function drawAngler(e)
  local r = mirror(e, 18)
  local flash = e.flash > 0
  local back = flash and { 1, 1, 1 } or { 0.10, 0.12, 0.22 }
  local body = flash and { 1, 1, 1 } or { 0.18, 0.22, 0.36 }
  local belly = flash and { 1, 1, 1 } or { 0.34, 0.30, 0.42 }
  local t = love.timer.getTime() + e.phase
  local beat = math.sin(t * 8) > 0 and 1 or 0
  -- tail
  r(back, 0, 4 + beat, 2, 4)
  r(body, 2, 3, 2, 5)
  -- body: a round, heavy shape
  r(back, 4, 2, 9, 1)
  r(body, 3, 3, 12, 6)
  r(back, 4, 9, 10, 1)
  r(belly, 5, 8, 8, 1)
  r(back, 8, 1, 3, 1) -- dorsal fin
  r(body, 10, 10, 2, 1)
  -- the head and its wide mouth
  r(body, 14, 4, 3, 5)
  r({ 0.04, 0.03, 0.06 }, 14, 7, 4, 1)
  local open = e.windT and 2 or (e.dashT and e.dashT > 0 and 3 or 0)
  if open > 0 then
    r({ 0.28, 0.06, 0.1 }, 14, 7, 4, open)
  end
  for i = 0, 3 do
    r({ 0.92, 0.9, 0.82 }, 14 + i, 6, 1, 1)
    r({ 0.92, 0.9, 0.82 }, 14 + i, 7 + open, 1, 1)
  end
  r({ 1, 0.9, 0.3 }, 13, 4, 1, 1) -- the eye
  -- the stalk and the lure
  r(body, 12, 1, 1, 1)
  r(body, 13, 0, 3, 1)
  r(body, 16, 0, 1, 2)
end

local function drawAnglerGlow(e)
  local r = mirror(e, 18)
  local pulse = 0.65 + 0.35 * math.sin(love.timer.getTime() * (e.windT and 16 or 4) + e.phase)
  r({ 0.55, 1, 0.9 }, 16, 1, 2, 2, pulse)
  r({ 1, 1, 1 }, 16, 1, 1, 1, pulse)
  r({ 1, 0.9, 0.3 }, 13, 4, 1, 1)
end

-- Urchin -------------------------------------------------------------------------------------------

local urchin = {
  w = 12,
  h = 12,
  hp = 24,
  speed = 14,
  sight = 130,
  forget = 220,
  damage = 5,
  gold = { 2, 5 },
  knockback = 0.3,
  weight = 0.8,
}

local function updateUrchin(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.phase = e.phase + dt * 1.5
  local preyWet = not player.dead and preyInWater(player)
  local near = preyWet and dist < def.sight
  e.state = near and "chase" or "idle"
  e.shotCd = math.max(0, (e.shotCd or 1.5) - dt)
  local wet = fluids.waterAt(cx, cy)
  if wet and e.stun <= 0 then
    if e.rattle then
      e.rattle = e.rattle - dt
      local k = math.exp(-dt * 4)
      b.vx, b.vy = b.vx * k, b.vy * k
      if e.rattle <= 0 then
        e.rattle = nil
        e.shotCd = 3.2
        local n = 10
        local off = love.math.random() * math.pi * 2
        for i = 0, n - 1 do
          local a = off + i / n * math.pi * 2
          addShot(cx + math.cos(a) * 7, cy + math.sin(a) * 7, math.cos(a) * 120, math.sin(a) * 120, 0.55, math.floor(6 * e.dmgMul + 0.5), "spine")
        end
        sfx("urchin_spines", 1)
      end
    else
      e.timer = e.timer - dt
      if e.timer <= 0 or not e.dirX then
        e.timer = 2 + love.math.random() * 3
        local a = love.math.random() * math.pi * 2
        e.dirX, e.dirY = math.cos(a), math.sin(a)
      end
      local tx, ty = e.dirX * def.speed, e.dirY * def.speed * 0.6
      if near then
        local d = math.max(1, dist)
        tx, ty = (px - cx) / d * def.speed * 1.4, (py - cy) / d * def.speed * 1.4
      end
      local k = math.min(1, dt * 2)
      b.vx, b.vy = b.vx + (tx - b.vx) * k, b.vy + (ty - b.vy) * k
      if near and dist < 95 and e.shotCd <= 0 then
        e.rattle = 0.55
        sfx("urchin_rattle", 1)
      end
    end
  end
  swim(e, dt, world)
end

local function drawUrchin(e)
  local b = e.body
  local x, y = math.floor(b.x), math.floor(b.y)
  local flash = e.flash > 0
  local core = flash and { 1, 1, 1 } or { 0.22, 0.10, 0.30 }
  local spine = flash and { 1, 1, 1 } or { 0.46, 0.26, 0.58 }
  local shake = e.rattle and math.floor(math.sin(love.timer.getTime() * 60) * 1 + 0.5) or 0
  x = x + shake
  rect(core, x + 3, y + 3, 6, 6)
  rect(core, x + 2, y + 4, 8, 4)
  rect(core, x + 4, y + 2, 4, 8)
  for i = 0, 7 do
    local a = i / 8 * math.pi * 2
    local sx, sy = x + 6 + math.cos(a) * 5, y + 6 + math.sin(a) * 5
    rect(spine, sx - 0.5, sy - 0.5, 1, 1)
    rect(spine, x + 6 + math.cos(a) * 3.5, y + 6 + math.sin(a) * 3.5, 1, 1)
  end
  rect({ 0.7, 0.9, 0.9 }, x + 5, y + 5, 2, 2)
end

local function drawUrchinGlow(e)
  local b = e.body
  local x, y = math.floor(b.x), math.floor(b.y)
  local a = e.rattle and 1 or 0.35 + 0.2 * math.sin(love.timer.getTime() * 2 + e.phase)
  for i = 0, 7 do
    local ang = i / 8 * math.pi * 2
    rect({ 0.6, 1, 0.9 }, x + 6 + math.cos(ang) * 5.5, y + 6 + math.sin(ang) * 5.5, 1, 1, a)
  end
end

-- The fish boss -------------------------------------------------------------------------------

local fishsprite = require("src.fishsprite")
local bossbg = require("src.bossbg")
local anglerart = require("src.anglerart")

local STAGES = {
  { name = "Big Fish", w = 24, h = 15, damage = 10 },
  { name = "Bigger Fish", w = 48, h = 30, damage = 16 },
  { name = "Even Bigger Fish", w = 150, h = 46, damage = 22 }, -- (an eel: long, not tall)
  { name = "The Biggest Fish", w = 470, h = 250, damage = 0 }, -- (the Angler Sharkwhale's body)
}
local STAGE_HP = 750
local GATE_HP = 75 -- the fish holds at this much until the bigger one arrives
local TOOTH_HP = 100 -- what each of the Biggest Fish's tusks takes before it breaks
local EAT_AT = 150 -- ...which comes at 20% of its health

local STYLE = {
  { back = { 0.36, 0.42, 0.48 }, body = { 0.62, 0.68, 0.70 }, light = { 0.82, 0.86, 0.86 }, belly = { 0.78, 0.30, 0.24 }, fin = { 0.70, 0.25, 0.20 } },
  { back = { 0.14, 0.22, 0.40 }, body = { 0.28, 0.42, 0.62 }, light = { 0.56, 0.72, 0.88 }, belly = { 0.52, 0.20, 0.30 }, fin = { 0.44, 0.14, 0.30 } },
  { back = { 0.13, 0.13, 0.24 }, body = { 0.28, 0.30, 0.46 }, light = { 0.50, 0.54, 0.70 }, belly = { 0.36, 0.14, 0.20 }, fin = { 0.30, 0.10, 0.20 } },
  { back = { 0.10, 0.10, 0.18 }, body = { 0.24, 0.26, 0.40 }, light = { 0.44, 0.48, 0.64 }, belly = { 0.28, 0.09, 0.13 }, fin = { 0.22, 0.07, 0.14 } },
}

local stage4Lights, smallFishLights, tuskStates

local boss = {
  name = "Big Fish",
  alwaysActive = true, -- (its sweeps take it far off screen: it must keep updating there)
  boss = true,
  anchored = true,
  scale = 1,
  w = 24,
  h = 15,
  hp = STAGE_HP,
  speed = 70,
  sight = 2000,
  forget = 4000,
  damage = 10,
  gold = { 110, 150 },
  knockback = 0,
  weight = 14,
  deathKind = "piranha",
  light = function(e)
    if e.stage == 4 then
      return stage4Lights(e)
    end
    return smallFishLights(e)
  end,
  -- (the Biggest Fish cannot be hit anywhere but its tusks until they are all gone)
  noBodyHit = function(e)
    local n = 0
    for i = 1, 4 do
      if e.teeth and e.teeth[i] then
        n = n + 1
      end
    end
    return e.stage == 4 and n > 0
  end,
}

-- The stage's fish, drawn in a 24 x 15 grid scaled to its size (facing right)
local function fishGrid(st, flash)
  local S = STYLE[st]
  local function c(k)
    return flash and { 1, 1, 1 } or S[k]
  end
  return c
end

-- The eel (stage 3): its picture is cut into eight segments that follow one another, so it
-- bends like a body when it turns, instead of sliding about as one flat piece. A joint can only
-- bend a little past the one before it (a tight bias), so the segments do not fold into each
-- other; the tail end also sways as it swims, and a layer of purple streaks pulses along it.
local EEL_SEGS = 8
local EEL_MAX_BEND = 0.3 -- radians between one segment and the next

-- the nine joints of a straight eel centred on (cx, cy), nose first
local function eelStraight(cx, cy, ang, w)
  local J, Ls = {}, w / EEL_SEGS
  local fx, fy = math.cos(ang), math.sin(ang)
  for i = 0, EEL_SEGS do
    J[i] = { cx + fx * (w / 2 - i * Ls), cy + fy * (w / 2 - i * Ls) }
  end
  return J
end

local function wrapAngle(a)
  return (a + math.pi) % (math.pi * 2) - math.pi
end

-- Each frame the nose is put where the head is, and every joint behind follows its leader, a
-- segment's length away, bent no more than the limit
local function updateEelChain(e)
  local w = e.body.w
  local cx, cy = center(e)
  local ang = e.ang or 0
  local J = e.eelJ
  if not J then
    e.eelJ = eelStraight(cx, cy, ang, w)
    return
  end
  local Ls = w / EEL_SEGS
  J[0][1], J[0][2] = cx + math.cos(ang) * w / 2, cy + math.sin(ang) * w / 2
  local prev = ang + math.pi -- (the direction a segment points, nose to tail)
  for i = 1, EEL_SEGS do
    local a = math.atan2(J[i][2] - J[i - 1][2], J[i][1] - J[i - 1][1])
    local d = wrapAngle(a - prev)
    d = math.max(-EEL_MAX_BEND, math.min(EEL_MAX_BEND, d))
    a = prev + d
    J[i][1], J[i][2] = J[i - 1][1] + math.cos(a) * Ls, J[i - 1][2] + math.sin(a) * Ls
    prev = a
  end
end

-- The joints as drawn (the tail end swaying), the way the belly faces (1 or -1)
local function eelDrawJoints(e, cx, cy, w, h, ang)
  local J = (e and e.stage == 3 and e.eelJ) or eelStraight(cx, cy, ang, w)
  local t = love.timer.getTime()
  local px, py = -math.sin(ang), math.cos(ang)
  local D = {}
  for k = 0, EEL_SEGS do
    local off = 0
    if k > 0 then
      off = h * 0.15 * (k / EEL_SEGS) ^ 1.1 * math.sin(t * 6 - k * 0.85)
    end
    D[k] = { J[k][1] + px * off, J[k][2] + py * off }
  end
  return D, math.cos(ang) < 0 and -1 or 1
end

local eelSegQuad
local function drawEelChain(e, cx, cy, w, h, ang, flash, openMouth, alpha)
  local base, streak = fishsprite.eel(w, h, openMouth, flash)
  local D, flip = eelDrawJoints(e, cx, cy, w, h, ang)
  local t = love.timer.getTime()
  local Ls = w / EEL_SEGS
  eelSegQuad = eelSegQuad or love.graphics.newQuad(0, 0, 1, 1, 1, 1)
  for i = 0, EEL_SEGS - 1 do
    local x1 = math.floor(w - (i + 1) * Ls + 0.5)
    local x2 = math.floor(w - i * Ls + 0.5)
    local qx = math.max(0, x1 - 1)
    local qw = math.min(w, x2 + 1) - qx
    eelSegQuad:setViewport(qx, 0, qw, h, w, h)
    local ax, ay, bx, by = D[i][1], D[i][2], D[i + 1][1], D[i + 1][2]
    local rot = math.atan2(ay - by, ax - bx)
    local mx, my = (ax + bx) / 2, (ay + by) / 2
    local ox, oy = (x1 + x2) / 2 - qx, h / 2
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(base, eelSegQuad, mx, my, rot, 1, flip, ox, oy)
    if not flash and not alpha then
      local f = (EEL_SEGS - i) / EEL_SEGS
      local pulse = 0.3 + 0.7 * math.max(0, math.sin(f * 11 - t * 7))
      love.graphics.setColor(1, 1, 1, pulse)
      love.graphics.draw(streak, eelSegQuad, mx, my, rot, 1, flip, ox, oy)
    end
  end
end

-- where a point of the eel is in the world: (segment number, along the segment -0.5..0.5 of its
-- length, across it as a fraction of the body's height, + toward its belly)
local function eelPoint(e, seg, along, across)
  local b = e.body
  local cx, cy = center(e)
  local D, flip = eelDrawJoints(e, cx, cy, b.w, b.h, e.ang or 0)
  local ax, ay, bx, by = D[seg][1], D[seg][2], D[seg + 1][1], D[seg + 1][2]
  local rot = math.atan2(ay - by, ax - bx)
  local mx, my = (ax + bx) / 2, (ay + by) / 2
  local lx, ly = along * (b.w / EEL_SEGS), across * b.h * flip
  return mx + math.cos(rot) * lx - math.sin(rot) * ly, my + math.sin(rot) * lx + math.cos(rot) * ly
end

-- The Biggest Fish is the Angler Sharkwhale (src.anglerart), a picture facing left: it is drawn
-- mirrored, so its head is at +x like the other fish, its body's box centred on the boss's
local ART
local function art()
  if not ART then
    ART = anglerart.bake()
  end
  return ART
end

-- a point of the picture (in its pixels) as a fraction of the boss's box, head at +x
local function artFrac(ax, ay, w, h)
  local bd = art().body
  local bcx, bcy = (bd[1] + bd[3]) / 2, (bd[2] + bd[4]) / 2
  return (ax - bcx) / w, (ay - bcy) / h
end

local function drawAnglerBoss(cx, cy, ang, flash, teeth, phase, states)
  love.graphics.push()
  love.graphics.translate(math.floor(cx + 0.5), math.floor(cy + 0.5))
  love.graphics.rotate(ang or 0)
  love.graphics.scale(1, math.cos(ang or 0) < 0 and -1 or 1)
  anglerart.draw(art(), love.timer.getTime() + (phase or 0), flash, teeth, nil, states)
  love.graphics.pop()
end

-- The Bigger Fish: baked at its real size, then swum in strips, the tail end sweeping side to side
local midQuads = {}
local function midWave(w, h, t, x)
  local f = x / w
  return math.floor(math.sin(f * 6 - t * 6.5) * (h * 0.07 * (1 - f) ^ 1.3 + 0.3) + 0.5)
end

local function drawMid(cx, cy, w, h, ang, flash, beat, openMouth, alpha, fold, side)
  local img = fishsprite.get(STYLE[2], 2, w, h, beat, openMouth, flash)
  local qs = midQuads[w .. "x" .. h]
  if not qs then
    qs = {}
    for x = 0, w - 1 do
      qs[x] = love.graphics.newQuad(x, 0, 1, h, w, h)
    end
    midQuads[w .. "x" .. h] = qs
  end
  local t = love.timer.getTime()
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.rotate(ang or 0)
  love.graphics.scale(1, math.cos(ang or 0) < 0 and -1 or 1)
  love.graphics.translate(-w / 2, -h / 2)
  love.graphics.setColor(1, 1, 1, alpha or 1)
  fold = fold or 0
  local squeeze = 1 - 0.34 * fold
  for x = 0, w - 1 do
    local f = x / w
    -- folding: the tail pulls in toward the head and curls to one side, and the body shortens
    local dy = midWave(w, h, t, x) + math.floor((side or 1) * fold * h * 1.25 * (1 - f) ^ 1.7 + 0.5)
    local dx = math.floor(w - (w - x) * squeeze + 0.5) - x
    love.graphics.draw(img, qs[x], x + dx, dy)
  end
  love.graphics.pop()
end

-- What the fish blocks of the hunter's light: the Sharkwhale as it is shaped (soft: a partial
-- blocker), the smaller fish their box
boss.occluders = function(e)
  local b = e.body
  local cx, cy = center(e)
  if e.stage == 3 then
    return drawEelChain(e, cx, cy, b.w, b.h, e.ang or 0, false, false, 0.75)
  elseif e.stage == 2 then
    return drawMid(cx, cy, b.w, b.h, e.ang or 0, false, 0, false, 0.75)
  elseif e.stage ~= 4 then
    love.graphics.setColor(1, 1, 1, 0.75)
    love.graphics.rectangle("fill", b.x + 1, b.y + 1, math.max(1, b.w - 2), math.max(1, b.h - 2))
    return
  end
  love.graphics.push()
  love.graphics.translate(math.floor(cx + 0.5), math.floor(cy + 0.5))
  love.graphics.rotate(e.ang or 0)
  love.graphics.scale(1, math.cos(e.ang or 0) < 0 and -1 or 1)
  anglerart.draw(art(), love.timer.getTime() + e.phase, false, e.teeth, 0.75)
  love.graphics.pop()
end

local function drawFishBody(e, stage, cx, cy, w, h, ang, flash, beat, openMouth)
  if stage == 4 then
    return drawAnglerBoss(cx, cy, ang, flash, nil, e and e.phase)
  end
  if stage == 3 then
    return drawEelChain(e, cx, cy, w, h, ang, flash, openMouth)
  end
  if stage == 2 then
    return drawMid(cx, cy, w, h, ang, flash, beat, openMouth, nil, e and e.fold, e and e.foldSide)
  end
  if stage >= 2 and stage < 4 then
    local img = fishsprite.get(STYLE[stage], stage, w, h, beat, openMouth, flash)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(ang or 0)
    love.graphics.scale(1, math.cos(ang or 0) < 0 and -1 or 1)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, -w / 2, -h / 2)
    love.graphics.pop()
    return
  end
  local c = fishGrid(stage, flash)
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.rotate(ang or 0)
  love.graphics.scale(w / 24, (math.cos(ang or 0) < 0 and -1 or 1) * h / 15)
  love.graphics.translate(-12, -7.5)
  local function R(col, x, y, ww, hh, a)
    love.graphics.setColor(col[1], col[2], col[3], a or 1)
    love.graphics.rectangle("fill", x, y, ww, hh)
  end
  -- tail
  R(c("fin"), 0, 5 + beat, 1, 5)
  R(c("fin"), 1, 4 + beat, 2, 7)
  R(c("body"), 3, 5, 2, 5)
  -- body
  R(c("back"), 6, 1, 10, 1)
  R(c("back"), 4, 2, 15, 1)
  R(c("body"), 3, 3, 18, 8)
  R(c("light"), 6, 4, 9, 2)
  R(c("belly"), 5, 11, 15, 1)
  R(c("belly"), 7, 12, 11, 1)
  -- dorsal fin (spined on the bigger fish)
  R(c("fin"), 9, 0, 6, 1)
  R(c("fin"), 11, -1, 3, 1)
  if stage >= 2 then
    R(c("fin"), 8, -1, 1, 2)
    R(c("fin"), 15, -1, 1, 2)
    R(c("fin"), 7, 12, 1, 2)
  end
  if stage >= 3 then
    -- scars and a ragged fin
    R(c("light"), 8, 7, 5, 1, 0.5)
    R(c("light"), 10, 8, 4, 1, 0.5)
    R(c("fin"), 12, 11, 2, 3)
  end
  -- gills and eye
  R(c("back"), 14, 5, 1, 5, 0.7)
  R(c("back"), 15, 5, 1, 5, 0.5)
  R(flash and { 1, 1, 1 } or { 0.1, 0.05, 0.05 }, 17, 4, 2, 2)
  R(flash and { 1, 1, 1 } or (stage >= 2 and { 1, 0.25, 0.2 } or { 1, 0.8, 0.5 }), 18, 4, 1, 1)
  -- the head and jaws: the bigger the fish the bigger the teeth
  if stage < 4 then
    local tooth = flash and { 1, 1, 1 } or { 0.94, 0.92, 0.84 }
    local len = stage == 1 and 1 or (stage == 2 and 2 or 3)
    local gap = openMouth and 2 or 0
    R(c("body"), 20, 5, 3, 3)
    R(c("belly"), 19, 9 + gap, 5, 2)
    R(flash and { 1, 1, 1 } or { 0.30, 0.04, 0.06 }, 20, 8, 4, 1 + gap)
    for i = 0, 3 do
      R(tooth, 20 + i, 8 - (i % 2 == 0 and len or len - 1) + 0, 1, i % 2 == 0 and len or len - 1)
      R(tooth, 20 + i, 9 + gap, 1, (i % 2 == 0) and len or len - 1)
    end
  end
  love.graphics.pop()
end

-- The fish turns in the water: its head points where it goes (or at the hunter),
-- turning at a set rate rather than snapping left or right
local function updateAngle(e, dt, px, py)
  local b = e.body
  local cx, cy = center(e)
  local sp = hypot(b.vx or 0, b.vy or 0)
  local target
  if sp > 140 and e.stage ~= 4 then
    target = math.atan2(b.vy, b.vx)
  else
    target = math.atan2(py - cy, px - cx)
  end
  e.ang = e.ang or target
  local d = (target - e.ang + math.pi) % (math.pi * 2) - math.pi
  local rate = (e.stage == 4 and 2.0 or 6.5) * dt
  e.ang = e.ang + math.max(-rate, math.min(rate, d))
end

-- A point in the fish's own frame (fractions of its size, head at +x) as a point in the world
local function framePoint(e)
  local b = e.body
  local cx, cy = center(e)
  local ang = e.ang or 0
  local ca, sa = math.cos(ang), math.sin(ang)
  local fl = ca < 0 and -1 or 1 -- (upside down when it faces the other way: belly stays down)
  local w, h = b.w, b.h
  return function(ux, uy)
    return cx + ux * w * ca - uy * h * fl * sa, cy + ux * w * sa + uy * h * fl * ca
  end
end

-- The last fish's teeth: its four tusks (upper front, upper back, lower front, lower back),
-- boxed from the picture as fractions of its body (centre u, v, width, height). They stand out
-- in the open maw, so a shot reaches them before it reaches the body behind
local TEETH
local function teethTable()
  if not TEETH then
    TEETH = {}
    local st = STAGES[4]
    for i, bx in ipairs(art().boxes) do
      local u, v = artFrac((bx[1] + bx[3]) / 2, (bx[2] + bx[4]) / 2, st.w, st.h)
      TEETH[i] = { u, v, (bx[3] - bx[1]) / st.w, (bx[4] - bx[2]) / st.h, cx = (bx[1] + bx[3]) / 2 }
    end
  end
  return TEETH
end

local function toothRect(e, i)
  local b = e.body
  local P = framePoint(e)
  local t = teethTable()[i]
  local v = t[2]
  if i >= 3 then
    -- the lower jaw is open a little: its tusks have dropped with it
    v = v + anglerart.jawDy(art(), love.timer.getTime() + e.phase, t.cx) / b.h
  end
  local x, y = P(t[1], v)
  local tw, th = t[3] * b.w, t[4] * b.h
  local ca, sa = math.abs(math.cos(e.ang or 0)), math.abs(math.sin(e.ang or 0))
  local bw, bh = tw * ca + th * sa, tw * sa + th * ca
  return x - bw / 2, y - bh / 2, bw, bh
end

-- The lights of the first three fish: a cool wash over each, a glow at the eye, and on the eel
-- the purple streaks that run down it, pulsing
smallFishLights = function(e)
  local b = e.body
  local cx, cy = center(e)
  local P = framePoint(e)
  local t = love.timer.getTime()
  local out = { { cx, cy, math.min(420, 40 + b.w * 0.8), 0.55, 0.72, 1, 0.38 } }
  if e.stage == 3 then
    out[1] = { cx, cy, 190, 0.5, 0.45, 0.95, 0.28 }
    local ex, ey = eelPoint(e, 0, -0.45, -0.1)
    out[#out + 1] = { ex, ey, 64, 1, 0.45, 0.9, 0.6 }
    for _, seg in ipairs({ 2, 4, 6 }) do
      local f = (EEL_SEGS - seg) / EEL_SEGS
      local pulse = 0.3 + 0.7 * math.max(0, math.sin(f * 11 - t * 7))
      local x, y = eelPoint(e, seg, 0, 0)
      out[#out + 1] = { x, y, 54, 0.7, 0.35, 1, 0.5 * pulse }
    end
  elseif e.stage == 2 then
    local ex, ey = P(0.795 - 0.5, 0.37 - 0.5)
    out[#out + 1] = { ex, ey, 40, 1, 0.3, 0.2, 0.5 }
  else
    local ex, ey = P(18.5 / 24 - 0.5, 5 / 15 - 0.5)
    out[#out + 1] = { ex, ey, 26, 1, 0.5, 0.3, 0.5 }
  end
  return out
end

-- The Biggest Fish's lights, where its lure, eye and fin tips are this moment
stage4Lights = function(e)
  local t = love.timer.getTime() + e.phase
  local b = e.body
  local P = framePoint(e)
  local cx, cy = center(e)
  local pulse = 0.85 + 0.15 * math.sin(t * 2.5)
  local out = { { cx, cy, 240, 0.25, 0.45, 0.8, 0.22 } } -- (a faint wash so its bulk can be seen)
  for _, l in ipairs(anglerart.lights(art(), t)) do
    local x, y = P(l.x / b.w, l.y / b.h)
    if l.kind == "lure" then
      out[#out + 1] = { x, y, 300, 0.35, 0.8, 1, 0.75 * pulse }
    elseif l.kind == "eye" then
      out[#out + 1] = { x, y, 70, 0.3, 0.85, 1, 0.5 }
    else
      out[#out + 1] = { x, y, 46, 0.3, 0.75, 1, 0.4 * pulse }
    end
  end
  return out
end

local function teethLeft(e)
  local n = 0
  for i = 1, 4 do
    if e.teeth and e.teeth[i] then
      n = n + 1
    end
  end
  return n
end

-- How worn each tusk looks: 0 whole, 1 under 60% of its strength left, 2 under 30%
function tuskStates(e)
  local out = {}
  for i = 1, 4 do
    local r = (e.teethHp and e.teethHp[i] or TOOTH_HP) / TOOTH_HP
    out[i] = r > 0.6 and 0 or (r > 0.3 and 1 or 2)
  end
  return out
end

-- Which tusk (if any) is at a point of the world: its own pixels, a touch smaller, as drawn
local function toothAt(e, px, py)
  if e.stage ~= 4 or not e.teeth then
    return nil
  end
  local a = art()
  local cx, cy = center(e)
  local ang = e.ang or 0
  local ca, sa = math.cos(ang), math.sin(ang)
  local dx, dy = px - cx, py - cy
  local lx, ly = dx * ca + dy * sa, -dx * sa + dy * ca
  if ca < 0 then
    ly = -ly
  end
  local bd = a.body
  local ax = lx + math.floor((bd[1] + bd[3]) / 2 + 0.5)
  local ay = ly + math.floor((bd[2] + bd[4]) / 2 + 0.5)
  local t = love.timer.getTime() + e.phase
  local st = tuskStates(e)
  for i = 1, 4 do
    if e.teeth[i] then
      local yy = ay
      if i >= 3 then
        yy = ay - anglerart.jawDy(a, t, ax) -- (the lower tusks ride the jaw)
      end
      if anglerart.tuskHit(a, i, st[i], ax, yy) then
        return i
      end
    end
  end
  return nil
end

-- A shot can hit a tooth even where it is outside the body's box
local function extraHit(e, px, py)
  return toothAt(e, px, py) ~= nil
end

-- The Biggest Fish: the Angler Sharkwhale, with whichever tusks it still has
local function drawBiggest(e)
  local cx, cy = center(e)
  drawAnglerBoss(cx, cy, e.ang or 0, e.flash > 0, e.teeth or {}, e.phase, tuskStates(e))
end

local function drawBigFish(e)
  local b = e.body
  local cx, cy = center(e)
  local stage = e.stage or 1
  local t = love.timer.getTime() + e.phase
  local beat = math.sin(t * ((e.bs and e.bs.mode == "dash") and 30 or 10)) > 0 and 1 or 0
  local open = e.bs and (e.bs.mode == "windup" or e.bs.mode == "dash" or e.bs.mode == "bubbles")
  if stage == 4 then
    return drawBiggest(e)
  end
  drawFishBody(e, stage, cx, cy, b.w, b.h, e.ang or 0, e.flash > 0, beat, open)
end

local function drawBigFishGlow(e)
  -- (nothing is painted over the fish: its lights are real lights, see smallFishLights and stage4Lights)
end

-- A fish of a stage's size, an eating one, comes in from far away
local function stageInit(e, n, cx, cy)
  local st = STAGES[n]
  local b = e.body
  if not cx then
    cx, cy = center(e)
  end
  b.w, b.h = st.w, st.h
  b.x, b.y = cx - st.w / 2, (cy or 0) - st.h / 2
  H.removePhysics(e)
  e.stage = n
  e.bossName = st.name
  e.hp, e.maxHp = STAGE_HP, STAGE_HP
  local d = {}
  for k, v in pairs(e.def) do
    d[k] = v
  end
  d.damage = st.damage > 0 and st.damage or nil
  d.w, d.h = st.w, st.h
  d.name = st.name
  e.def = d
  e.bs = { mode = "approach", t = 0, n = 0 }
  e.gate, e.eater, e.tele = nil, nil, nil
  e.teeth = n == 4 and { true, true, true, true } or nil
  if n >= 3 then
    art() -- (bake the Sharkwhale now, before it comes to eat the eel, not mid-fight)
  end
  e.retreatT = nil
  e.chain, e.fold, e.eelJ = nil, nil, nil
  e.teethHp = n == 4 and { TOOTH_HP, TOOTH_HP, TOOTH_HP, TOOTH_HP } or nil
end

-- a centre (cx, cy) for the fish moved to the nearest place it can be inside its arena
local function arenaClampPoint(e, cx, cy, bw, bh)
  local a = e.arena
  if not a then
    return cx, cy
  end
  local b = { w = bw or e.body.w, h = bh or e.body.h }
  if a.shape == "round" then
    -- (an oval room: stay inside it, the bigger the fish the less room it has)
    local mx, my = (a.x0 + a.x1) / 2, (a.top + a.floorY) / 2
    local rx = math.max(60, (a.x1 - a.x0) / 2 - b.w * 0.3)
    local ry = math.max(60, (a.floorY - a.top) / 2 - b.h * 0.3)
    local nx, ny = (cx - mx) / rx, (cy - my) / ry
    local d = nx * nx + ny * ny
    if d > 1 then
      local k = 1 / math.sqrt(d)
      cx, cy = mx + nx * k * rx, my + ny * k * ry
    end
  else
    cx = math.max(a.x0 + b.w / 2, math.min(a.x1 - b.w / 2, cx))
    cy = math.max(a.top + b.h / 2, math.min(a.floorY - b.h / 2, cy))
  end
  return cx, cy
end

local function clampToArena(e)
  if not e.arena then
    return
  end
  local b = e.body
  local cx, cy = arenaClampPoint(e, center(e))
  b.x, b.y = cx - b.w / 2, cy - b.h / 2
end

local function moveBy(e, vx, vy, dt)
  local b = e.body
  b.vx, b.vy = vx, vy
  b.x, b.y = b.x + vx * dt, b.y + vy * dt
  if math.abs(vx) > 8 then
    e.facing = vx < 0 and -1 or 1
  end
  clampToArena(e)
end

local function faceToward(e, px)
  local cx = center(e)
  e.facing = px < cx and -1 or 1
end

local function dotted(x0, y0, x1, y1, a)
  local d = hypot(x1 - x0, y1 - y0)
  local n = math.max(1, math.floor(d / 9))
  for i = 0, n do
    local t = i / n
    love.graphics.rectangle("fill", math.floor(x0 + (x1 - x0) * t), math.floor(y0 + (y1 - y0) * t), 2, 2)
  end
end

local function jelliesAlive()
  local n = 0
  for _, o in ipairs(enemies.all()) do
    if o.kind == "jellyfish" and o.fromBoss and not o.dead then
      n = n + 1
    end
  end
  return n
end

-- The smaller fish is gone, the bigger one is the boss
local function finishEat(e, er, cx, cy)
  local st = STAGES[er.stage]
  sfx("fish_chomp", 1, 0.8)
  for _ = 1, 18 do
    effects.chunk(cx + (love.math.random() - 0.5) * e.body.w, cy + (love.math.random() - 0.5) * e.body.h, (love.math.random() - 0.5) * 160, (love.math.random() - 0.5) * 120, 2, 2, love.math.random() < 0.5 and { 0.8, 0.2, 0.2 } or { 0.7, 0.7, 0.75 }, 3)
    effects.particle(cx, cy, (love.math.random() - 0.5) * 120, (love.math.random() - 0.5) * 120, 0.8, { 1, 0.4, 0.4 }, -20, true)
  end
  effects.ring(er.x, er.y, st.w * 0.6 + 14, { 1, 0.5, 0.4 })
  local facing = er.facing or 1
  local nx, ny = cx, cy -- (it takes the smaller fish's place: no jump)
  if er.stop or er.big then
    nx, ny = er.x, er.y -- (the last one stays where it stopped, well clear of the hunter)
  end
  stageInit(e, er.stage, nx, ny)
  require("src.save").record("enemy", "bigfish_" .. (er.stage - 1)) -- (the smaller fish is in the bestiary now)
  e.facing = facing
  if er.big then
    e.ang = er.ang
  end
  clampToArena(e)
  effects.popup(nx, ny - st.h / 2 - 10, STAGES[er.stage].name, { 1, 0.5, 0.45 })
  require("src.camera").shake(0.6)
  e.invulnT = 0.8
end

local function startEater(e, px, py)
  e.gate = true
  local cx, cy = center(e)
  if e.stage + 1 == 4 then
    -- the Biggest Fish always comes in from the right of the arena, from out of sight
    local ar = e.arena
    local y = cy
    if ar then
      y = math.max(ar.top + 60, math.min(ar.floorY - 60, cy))
    end
    e.eater = { x = (ar and ar.x1 or cx + 700) + 300, y = y, stage = 4, t = 0, big = true, ang = math.pi, facing = -1, phase = "come" }
    sfx("fish_groan", 1, 0.6)
    return
  end
  local a = love.math.random() * math.pi * 2
  local x, y = cx + math.cos(a) * 700, cy + math.sin(a) * 500
  if e.arena then
    x = math.max(e.arena.x0 + 40, math.min(e.arena.x1 - 40, x))
    y = math.max(e.arena.top + 40, math.min(e.arena.floorY - 40, y))
  end
  e.eater = { x = x, y = y, stage = e.stage + 1, t = 0 }
  sfx("fish_groan", 1, 0.7)
end

-- where the Biggest Fish's mouth is, while it is still only an eater
local function eaterMouth(er)
  local st = STAGES[er.stage]
  local a = art()
  local mu, mv = artFrac(a.mouthFront[1], a.mouthFront[2], st.w, st.h)
  local ang = er.ang or 0
  local ca, sa = math.cos(ang), math.sin(ang)
  local fl = ca < 0 and -1 or 1
  return er.x + mu * st.w * ca - mv * st.h * fl * sa, er.y + mu * st.w * sa + mv * st.h * fl * ca
end

-- It swims in from the right, level with the eel, and stops a little way off; then it draws the
-- eel in, faster and faster, and swallows it
local function updateBigEater(e, dt)
  local er = e.eater
  er.t = er.t + dt
  local st = STAGES[4]
  local cx, cy = center(e)
  if er.phase == "come" then
    local tx, ty = arenaClampPoint(e, cx + st.w * 0.72 + 170, cy, st.w, st.h)
    local d = hypot(tx - er.x, ty - er.y)
    if d > 1 then
      local sp = math.min(560, 100 + d * 1.4)
      er.x, er.y = er.x + (tx - er.x) / d * sp * dt, er.y + (ty - er.y) / d * sp * dt
    end
    if d < 30 or er.t > 8 then
      er.phase, er.suckT, er.sucking = "suck", 0, true
      e.tele = nil
      sfx("fish_groan", 1, 0.5)
    end
    return
  end
  er.suckT = er.suckT + dt
  local mx, my = eaterMouth(er)
  local b = e.body
  local d = hypot(mx - cx, my - cy)
  if d > 1 then
    local sp = math.min(140 + 900 * er.suckT ^ 1.6, 80 + d * 6) -- (faster and faster, easing into the mouth)
    b.vx, b.vy = (mx - cx) / d * sp, (my - cy) / d * sp
    b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
    e.facing = b.vx < 0 and -1 or 1
  end
  -- water streaming into the mouth with it
  for _ = 1, 2 do
    local a = love.math.random() * math.pi * 2
    local r = 50 + love.math.random() * 170
    local sx, sy = mx + math.cos(a) * r, my + math.sin(a) * r
    local life = 0.4 + love.math.random() * 0.3
    effects.particle(sx, sy, (mx - sx) / life, (my - sy) / life, life, { 0.7, 0.9, 1 }, 0, false)
  end
  if (d < 35 and er.suckT > 0.8) or er.suckT > 2.4 then
    finishEat(e, er, cx, cy)
  end
end

local function updateEater(e, dt)
  local er = e.eater
  if er.big then
    return updateBigEater(e, dt)
  end
  er.t = er.t + dt
  local cx, cy = center(e)
  local st = STAGES[er.stage]
  local d = hypot(cx - er.x, cy - er.y)
  local speed = 560
  if d > 1 then
    er.x, er.y = er.x + (cx - er.x) / d * speed * dt, er.y + (cy - er.y) / d * speed * dt
    er.facing = cx < er.x and -1 or 1
    er.ang = math.atan2(cy - er.y, cx - er.x)
  end
  if d < (er.stop or st.w * 0.35 + 8) or er.t > 7 then
    finishEat(e, er, cx, cy)
  end
end

local function aimAngle(e, px, py)
  local cx, cy = center(e)
  return math.atan2(py - cy, px - cx)
end

-- At half health the smaller fish get faster and more dangerous
local function isHalf(e)
  return e.hp <= e.maxHp * 0.5
end

-- Small bubbles streaming off the fish's body while it dashes (rate per second)
local function trailBubbles(e, dt, rate)
  e.bubT = (e.bubT or 0) - dt
  while e.bubT <= 0 do
    e.bubT = e.bubT + 1 / rate
    local P = framePoint(e)
    local x, y = P(-0.5 + love.math.random() * 0.55, (love.math.random() - 0.5) * 0.7)
    effects.particle(x, y, (love.math.random() - 0.5) * 36, -8 - love.math.random() * 28, 0.7 + love.math.random() * 0.6, { 0.72, 0.92, 1 }, -45, love.math.random() < 0.4)
  end
end

local function bossUpdate(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  e.state = "chase"
  e.seesPlayer = true
  e.phase = e.phase + dt
  if not e.stage then
    stageInit(e, 1, center(e))
    e.hp, e.maxHp = STAGE_HP, STAGE_HP
  end
  e.invulnT = math.max(0, (e.invulnT or 0) - dt)
  e.fold = math.max(0, (e.fold or 0) - dt * 3.5) -- (the bigger fish folds up when it turns: see drawMid)
  if e.dormant then
    e.state = "idle"
    b.vx, b.vy = 0, 0
    return -- (it lies in wait until the fight starts: see src.scenes.catacombs)
  end
  updateAngle(e, dt, px, py)
  if e.stage == 3 then
    updateEelChain(e)
  end
  local bs = e.bs
  bs.t = bs.t + dt
  local cx, cy = center(e)
  local dist = math.max(1, hypot(px - cx, py - cy))
  local stage = e.stage

  if stage < 4 and not e.gate and e.hp <= EAT_AT then
    startEater(e, px, py)
  end
  if e.eater then
    updateEater(e, dt)
    if e.stage ~= stage then
      return -- (it has just been eaten: the bigger fish starts fresh next frame)
    end
    if e.eater and e.eater.sucking then
      return -- (being drawn in: it does nothing else)
    end
    -- at its threshold it gives up its attacks: it holds still and waits to be eaten (and if a
    -- pass had taken it out of sight, it is brought back into the arena first)
    e.tele = nil
    local tx, ty = arenaClampPoint(e, cx, cy)
    local d = hypot(tx - cx, ty - cy)
    if d > 6 then
      b.vx, b.vy = (tx - cx) / d * 520, (ty - cy) / d * 520
      b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
      e.facing = b.vx < 0 and -1 or 1
    else
      b.vx, b.vy = 0, 0
    end
    return
  end

  if e.tele then
    e.tele.t = e.tele.t - dt
    if e.tele.t <= 0 then
      e.tele = nil
    end
  end

  local function setMode(m, extra)
    bs.mode, bs.t = m, 0
    for k, v in pairs(extra or {}) do
      bs[k] = v
    end
  end

  -- a sweep: the band is shown, the fish swims off out of sight to where the pass begins, waits
  -- there a moment, then comes across. At half health it makes three passes at once, in three
  -- lanes, back and forth
  local function clampSweepY(y)
    if e.arena then
      y = math.max(e.arena.top + b.h, math.min(e.arena.floorY - b.h, y))
    end
    return y
  end
  local function laneTele(lanes, px0, t)
    e.tele = { band = true, ys = lanes, y = lanes[1], x0 = px0 - 560, x1 = px0 + 560, t = t, total = t }
  end
  local function startLane(dir, lanes, lane, px0)
    local y = lanes[lane]
    setMode("sweepexit", { dir = dir, y = y, px = px0, sx = px0 - dir * 560, sy = y, lanes = lanes, lane = lane })
  end
  local function beginSweep(dir, px0, py0)
    local y = clampSweepY(py0)
    local lanes = isHalf(e) and { y, clampSweepY(y - 130), clampSweepY(y + 130) } or { y }
    laneTele({ lanes[1] }, px0, 3)
    startLane(dir, lanes, 1, px0)
  end

  -- Stage 1: dart in, bite, dash away twice as far in a random direction (faster at half health) --
  if stage == 1 then
    local fast = isHalf(e)
    local spd = fast and 470 or 300
    if bs.mode == "approach" then
      local a = aimAngle(e, px, py)
      moveBy(e, math.cos(a) * (fast and 115 or 75), math.sin(a) * (fast and 115 or 75), dt)
      if dist < 120 or bs.t > 3 then
        setMode("windup")
        faceToward(e, px)
      end
    elseif bs.mode == "windup" then
      faceToward(e, px)
      b.vx, b.vy = 0, 0
      if bs.t > (fast and 0.18 or 0.35) then
        bs.dir = aimAngle(e, px, py)
        setMode("dash", { dir = bs.dir })
        sfx("fish_dash", 1, fast and 1.5 or 1.3)
      end
    elseif bs.mode == "dash" then
      moveBy(e, math.cos(bs.dir) * spd, math.sin(bs.dir) * spd, dt)
      trailBubbles(e, dt, 40)
      if bs.t > (fast and 0.3 or 0.35) then
        -- away: a random heading in the half-circle facing away from the hunter, twice as far
        local away = bs.dir + math.pi + (love.math.random() - 0.5) * math.pi * 1.1
        setMode("away", { dir = away })
      end
    elseif bs.mode == "away" then
      moveBy(e, math.cos(bs.dir) * spd, math.sin(bs.dir) * spd, dt)
      trailBubbles(e, dt, 40)
      if bs.t > (fast and 0.5 or 0.7) then
        setMode("approach")
      end
    end

  -- Stage 2: it bobs in a ring around the hunter; from there it spits bubbles (mostly) or makes a
  -- zig-zag dash that always crosses the place the hunter was standing, then comes back to the
  -- ring. At half health every attack comes twice in a row ------------------------------------------
  elseif stage == 2 then
    local half = isHalf(e)
    bs.dirn = bs.dirn or (love.math.random() < 0.5 and 1 or -1)
    -- a ring around the hunter, breathing in and out, with a bob on top
    local function ringPoint()
      local t = e.phase
      local rx = 225 + 30 * math.sin(t * 2.1)
      local ry = 150 + 22 * math.sin(t * 2.1 + 1)
      return arenaClampPoint(e, px + math.cos(bs.a) * rx, py + math.sin(bs.a) * ry + 16 * math.sin(t * 3.3))
    end
    local function toOrbit(atk)
      setMode("orbit", { a = math.atan2(cy - py, cx - px), atk = atk })
    end
    if bs.mode == "approach" then
      toOrbit(1.4)
    elseif bs.mode == "orbit" then
      bs.a = bs.a + dt * bs.dirn * (half and 1.5 or 1.05)
      local tx, ty = ringPoint()
      local d = math.max(1, hypot(tx - cx, ty - cy))
      local sp = math.min(360, d * 4)
      moveBy(e, (tx - cx) / d * sp, (ty - cy) / d * sp, dt)
      faceToward(e, px)
      bs.atk = bs.atk - dt
      if bs.atk <= 0 and (d < 120 or bs.atk < -2) then
        local kind = e.chain
        e.chain = nil
        if not kind then
          bs.n = bs.n + 1
          -- two spits, then a zig-zag
          kind = (bs.n % 3 == 0) and "zig" or "bubbles"
          if half then
            e.chain = kind -- (and again)
          end
        end
        if kind == "zig" then
          -- through the place the hunter is now: legs swing out either side of the line to it,
          -- cross it at the hunter's spot, then carry on past it
          local sx, sy = cx, cy
          local dx, dy = px - sx, py - sy
          local D = math.max(120, hypot(dx, dy))
          local ux, uy = dx / D, dy / D
          local nx, ny = -uy, ux
          local sgn = love.math.random() < 0.5 and 1 or -1
          local lat = 105
          local function at(along, across)
            return { sx + ux * along + nx * across * sgn, sy + uy * along + ny * across * sgn }
          end
          local pts = { { sx, sy }, at(D * 0.3, lat), at(D * 0.64, -lat), { px, py }, at(D + 150, lat), at(D + 290, -lat) }
          for i = 2, #pts do
            if i ~= 4 then
              pts[i][1], pts[i][2] = arenaClampPoint(e, pts[i][1], pts[i][2])
            end
          end
          e.tele = { pts = pts, t = 0.8, total = 0.8 }
          setMode("zigtele", { pts = pts })
        else
          setMode("bubbles", { fired = false })
          sfx("fish_groan", 0.7, 1.4)
        end
      end
    elseif bs.mode == "zigtele" then
      b.vx, b.vy = 0, 0
      if bs.t >= 0.8 then
        setMode("zig", { leg = 1, legT = 0 })
        e.fold, e.foldSide = 0.5, 1
        sfx("fish_dash", 1, 1.1)
      end
    elseif bs.mode == "zig" then
      local p = bs.pts[bs.leg + 1]
      local d = hypot(p[1] - cx, p[2] - cy)
      bs.legT = (bs.legT or 0) + dt
      trailBubbles(e, dt, 55)
      if d < 22 or bs.legT > 1.0 then
        bs.leg = bs.leg + 1
        bs.legT = 0
        e.fold = 1 -- it folds in on itself as it turns
        e.foldSide = (bs.leg % 2 == 0) and 1 or -1
        if bs.leg >= #bs.pts then
          toOrbit(e.chain and 0.3 or (half and 0.9 or 1.3))
          return
        end
        sfx("fish_dash", 0.6, 1.4)
      else
        local sp = 540 * (half and 1.15 or 1)
        if d < 60 then
          sp = sp * 0.65 -- (it slows into a turn, so the fold shows)
        end
        moveBy(e, (p[1] - cx) / d * sp, (p[2] - cy) / d * sp, dt)
      end
    elseif bs.mode == "bubbles" then
      faceToward(e, px)
      b.vx, b.vy = 0, 0
      if bs.t > 0.55 and not bs.fired then
        bs.fired = true
        local mx, my = cx + math.cos(e.ang or 0) * b.w * 0.45, cy + math.sin(e.ang or 0) * b.w * 0.45
        local base = aimAngle(e, px, py)
        for i = 0, 8 do
          local a = base + (i - 4) * 0.22
          addShot(mx, my, math.cos(a) * 110, math.sin(a) * 110, 3.5, math.floor(9 * e.dmgMul + 0.5), "bubble", 4)
        end
        sfx("fish_chomp", 0.6, 1.6)
      end
      if bs.t > 1.05 then
        toOrbit(e.chain and 0.3 or (half and 0.9 or 1.4))
      end
    end

  -- Stage 3: sweeps across the screen from off to one side (lines first), orbiting between
  -- them and spitting jellyfish ---------------------------------------------------------------
  elseif stage == 3 then
    if bs.mode == "approach" then
      setMode("orbit", { a = math.atan2(cy - py, cx - px), shot = 0.8 })
    elseif bs.mode == "orbit" then
      bs.a = bs.a + dt * 1.5
      local tx, ty = px + math.cos(bs.a) * 210, py + math.sin(bs.a) * 150
      local d = math.max(1, hypot(tx - cx, ty - cy))
      if bs.entering then
        -- (coming back in from out of sight: it swims in, it does not pop into the arena)
        tx, ty = arenaClampPoint(e, tx, ty)
        d = math.max(1, hypot(tx - cx, ty - cy))
        b.x, b.y = b.x + (tx - cx) / d * 520 * dt, b.y + (ty - cy) / d * 520 * dt
        b.vx, b.vy = (tx - cx) / d * 520, (ty - cy) / d * 520
        e.facing = b.vx < 0 and -1 or 1
        if d < 90 or bs.t > 2.6 then
          bs.entering = false
          bs.t = 0
        end
      else
        moveBy(e, (tx - cx) / d * math.min(260, d * 3), (ty - cy) / d * math.min(260, d * 3), dt)
        faceToward(e, px)
      end
      bs.shot = bs.shot - dt
      if bs.shot <= 0 then
        bs.shot = 1.25
        if jelliesAlive() < 12 then
          local mx, my = cx + math.cos(e.ang or 0) * b.w * 0.42, cy + math.sin(e.ang or 0) * b.w * 0.42
          for _ = 1, 3 do
            local j = enemies.spawn("jellyfish", mx, my, 1 + (e.level or 1) * 0.1, e.level)
            j.fromBoss = true
            local a = love.math.random() * math.pi * 2 -- (at random, not just at him)
            j.body.vx, j.body.vy = math.cos(a) * 150, math.sin(a) * 150
            j.state = "chase"
          end
          sfx("fish_chomp", 0.5, 1.8)
        end
      end
      if bs.t > 3.6 and not bs.entering then
        beginSweep(1, px, py)
      end
    elseif bs.mode == "sweepexit" then
      local tx, ty = bs.sx, bs.sy
      local d = hypot(tx - cx, ty - cy)
      trailBubbles(e, dt, 50)
      if d < 30 or bs.t > 2.6 then
        b.x, b.y = tx - b.w / 2, ty - b.h / 2
        b.vx, b.vy = 0, 0
        laneTele({ bs.lanes[bs.lane] }, bs.px, isHalf(e) and 0.3 or 0.6)
        setMode("sweepwait")
      else
        local sp = 760
        b.x, b.y = b.x + (tx - cx) / d * sp * dt, b.y + (ty - cy) / d * sp * dt
        b.vx, b.vy = (tx - cx) / d * sp, (ty - cy) / d * sp
        e.facing = b.vx < 0 and -1 or 1
      end
    elseif bs.mode == "sweepwait" then
      b.vx, b.vy = 0, 0
      e.ang = bs.dir > 0 and 0 or math.pi
      e.facing = bs.dir
      if bs.t > (isHalf(e) and 0.3 or 0.6) then
        setMode("sweep", { lanes = bs.lanes, lane = bs.lane, dir = bs.dir, px = bs.px, y = bs.y })
        sfx("fish_dash", 1, 0.8)
        sfx("fish_groan", 0.8, 0.8)
      end
    elseif bs.mode == "sweep" then
      local sp = isHalf(e) and 1050 or 880
      b.x = b.x + bs.dir * sp * dt
      b.vx, b.vy = bs.dir * sp, 0
      e.ang = bs.dir > 0 and 0 or math.pi
      e.facing = bs.dir
      trailBubbles(e, dt, 70)
      if bs.t > 1320 / sp then
        if bs.lane < #bs.lanes then
          -- the next lane, the other way
          laneTele({ bs.lanes[bs.lane + 1] }, bs.px, 0.9) -- (the next lane's line shows only now)
          startLane(-bs.dir, bs.lanes, bs.lane + 1, bs.px)
        elseif bs.dir == 1 and #bs.lanes == 1 then
          -- and back the other way, at wherever the hunter has got to
          beginSweep(-1, px, py)
        else
          setMode("orbit", { a = math.atan2(cy - py, cx - px), shot = 0.6, entering = true })
        end
      end
    end

  -- Stage 4: the Biggest Fish: it just comes, and its teeth must be shot out ---------------
  else
    faceToward(e, px)
    local retreating = e.retreatT and e.retreatT > 0
    if retreating then
      e.retreatT = e.retreatT - dt
      local a = aimAngle(e, px, py) + math.pi
      local spd = e.retreatSpd or 230
      moveBy(e, math.cos(a) * spd, math.sin(a) * spd, dt)
      e.facing = px < cx and -1 or 1
    else
      local a = aimAngle(e, px, py)
      -- it comes on slowly, but keeps level with the hunter (so he cannot just go over it)
      local vy = math.max(-130, math.min(130, (py - cy) * 2.4))
      moveBy(e, math.cos(a) * 56, vy, dt)
      e.facing = px < cx and -1 or 1
    end
    -- a few small bubbles drawn into its mouth
    e.suckT = (e.suckT or 0) - dt
    if e.suckT <= 0 then
      e.suckT = 0.13 + love.math.random() * 0.1
      local a = art()
      local Pf = framePoint(e)
      local mu, mv = artFrac(a.mouthFront[1], a.mouthFront[2], b.w, b.h)
      local tx, ty = Pf(mu - 0.02, mv)
      local sx, sy = Pf(mu + 0.12 + love.math.random() * 0.22, mv + (love.math.random() - 0.5) * 0.45)
      local life = 0.8 + love.math.random() * 0.5
      effects.particle(sx, sy, (tx - sx) / life, (ty - sy) / life, life, { 0.7, 0.9, 1 }, 0, false)
    end
    -- the maw: a bite hurts a lot
    if not player.dead and not retreating then
      local P = framePoint(e)
      local mx, my = P(0.5, 0.12)
      local pcx, pcy = player:center()
      if hypot(pcx - mx, pcy - my) < b.h * 0.24 then
        if player:hurt(math.floor(32 * e.dmgMul + 0.5), mx, my, "bigfish") then
          sfx("fish_chomp", 1, 0.7)
          e.retreatT = 0.9
          e.retreatSpd = 230
        end
      end
    end
    e.vulnerable = teethLeft(e) == 0
    if bs.t > 6 then
      bs.t = 0
      sfx("fish_groan", 1, 0.7)
    end
  end

  if stage < 4 and math.abs(b.vx or 0) > 5 then
    e.facing = b.vx < 0 and -1 or 1
  end
end

-- What a hit does: the smaller fish hold at 10 hp until eaten; the last one takes
-- nothing until its teeth are gone, and a hit on a tooth breaks it
local function bossFilter(e, amount)
  if not e.stage or (e.invulnT or 0) > 0 then
    return 0
  end
  if e.stage < 4 then
    if e.gate then
      amount = math.min(amount, math.max(0, e.hp - GATE_HP))
    elseif e.hp - amount <= GATE_HP then
      amount = math.max(0, e.hp - GATE_HP)
    end
    return amount
  end
  if teethLeft(e) > 0 then
    local x, y = e.hitX, e.hitY
    if x then
      for i = 1, 4 do
        if e.teeth[i] then
          local tx, ty, tw, th = toothRect(e, i)
          if toothAt(e, x, y) == i then
            e.teethHp = e.teethHp or { TOOTH_HP, TOOTH_HP, TOOTH_HP, TOOTH_HP }
            e.teethHp[i] = e.teethHp[i] - math.max(1, amount)
            if e.teethHp[i] > 0 then
              -- it chips, it does not break yet
              sfx("tooth_break", 0.35, 1.7 + i * 0.05)
              for _ = 1, 3 do
                effects.chunk(x, y, (love.math.random() - 0.5) * 120, -love.math.random() * 90, 2, 2, { 0.94, 0.92, 0.84 }, 0.8)
              end
              return 0
            end
            e.teeth[i] = false
            e.retreatT = 0.6
            e.retreatSpd = 156 -- (a short step back: about 95 px)
            sfx("tooth_break", 1, 0.8 + i * 0.05)
            sfx("fish_groan", 1, 0.8)
            for _ = 1, 12 do
              effects.chunk(tx + tw / 2, ty + th / 2, (love.math.random() - 0.5) * 200, (love.math.random() - 0.5) * 200, 3, 3, { 0.94, 0.92, 0.84 }, 2)
            end
            effects.popup(tx + tw / 2, ty - 6, teethLeft(e) == 0 and "Teeth gone!" or (teethLeft(e) .. " teeth left"), { 1, 0.95, 0.7 })
            require("src.camera").shake(0.4)
            return 0
          end
        end
      end
    end
    -- the body takes nothing until the teeth are gone
    return 0
  end
  return amount
end

boss.filter = bossFilter
boss.extraHit = extraHit

local function bossDeath(e)
  local cx, cy = center(e)
  for _ = 1, 60 do
    effects.chunk(cx + (love.math.random() - 0.5) * e.body.w, cy + (love.math.random() - 0.5) * e.body.h, (love.math.random() - 0.5) * 240, (love.math.random() - 0.5) * 200, 3, 3, love.math.random() < 0.5 and { 0.5, 0.55, 0.6 } or { 0.7, 0.2, 0.2 }, 3)
  end
  for _ = 1, 30 do
    effects.particle(cx + (love.math.random() - 0.5) * e.body.w, cy + (love.math.random() - 0.5) * e.body.h, (love.math.random() - 0.5) * 40, -20 - love.math.random() * 50, 1.2, { 0.75, 0.9, 1 }, -30, true)
  end
  sfx("fish_groan", 1, 0.5)
end
boss.onDeath = bossDeath

-- Registration ------------------------------------------------------------------------------------

local function lore(kind, name, text)
  local d = enemies.defs[kind]
  d.name = d.name or name
  d.desc = text
end

local function register(kind, def, update, draw, glow)
  enemies.defs[kind] = def
  enemies.UPDATE[kind] = update
  enemies.DRAW[kind] = draw
  enemies.GLOW[kind] = glow or function() end
end

register("jellyfish", jelly, updateJelly, drawJelly, drawJellyGlow)
register("angler", angler, updateAngler, drawAngler, drawAnglerGlow)
register("urchin", urchin, updateUrchin, drawUrchin, drawUrchinGlow)
register("bigfish", boss, bossUpdate, drawBigFish, drawBigFishGlow)
lore("jellyfish", "Glow Jelly", "A pink bell that pulses through the water and glows in the dark. It shocks everything in a ring around it, and the water carries the shock to anyone swimming close.")
lore("angler", "Lantern Angler", "A heavy fish that hangs still behind its glowing lure, then lunges and snaps. Do not follow the light.")
lore("urchin", "Spine Urchin", "A drifting ball of spines. It rattles, then looses them all at once in every direction.")
lore("bigfish", "The Big Fish", "It was a small fish. Then something bigger ate it. Then something bigger ate that. Shoot the teeth first.")
enemies.defs.bigfish.name = "The Big Fish"

enemies.VOICES.jellyfish = { "jelly_pulse", 4, 9, 1.3 }
enemies.VOICES.angler = { "angler_lure", 5, 10, 1 }
enemies.VOICES.urchin = { "urchin_rattle", 6, 12, 0.8 }
enemies.VOICES.bigfish = { "fish_groan", 6, 11, 1 }

-- Shots in flight, and the fish's telegraphs -----------------------------------------------------

function enemies.afterUpdate(dt, world, player, px, py)
  -- The giant waiting in the dark of the Deep's background (src.bossbg) shows while the fish are
  -- still small, and goes out once the eel is under half its health
  local want, stage, cx, cy = false, 1, nil, nil
  for _, e in ipairs(enemies.all()) do
    if e.kind == "bigfish" and not e.dead then
      stage = e.stage or 1
      want = stage < 3 or (stage == 3 and e.hp > (e.maxHp or STAGE_HP) * 0.5)
      local a = e.arena
      if a then
        cx, cy = (a.x0 + a.x1) / 2, (a.top + a.floorY) / 2
      end
    end
  end
  bossbg.setLurk(dt, want, stage, cx, cy)
  for i = #shots, 1, -1 do
    local s = shots[i]
    s.life = s.life - dt
    local steps = math.max(1, math.ceil(hypot(s.vx, s.vy) * dt / 2))
    local dead = s.life <= 0
    for _ = 1, steps do
      s.x, s.y = s.x + s.vx * dt / steps, s.y + s.vy * dt / steps
      if world:isSolid(math.floor(s.x), math.floor(s.y)) then
        dead = true
        break
      end
    end
    if not dead and not player.dead then
      local pb = player.body
      if s.x > pb.x - s.r and s.x < pb.x + pb.w + s.r and s.y > pb.y - s.r and s.y < pb.y + pb.h + s.r then
        player:hurt(s.damage, s.x - s.vx, s.y - s.vy, s.kind == "bubble" and "bigfish" or "urchin")
        dead = true
      end
    end
    if dead then
      if s.kind == "bubble" then
        for _ = 1, 6 do
          effects.particle(s.x, s.y, (love.math.random() - 0.5) * 60, (love.math.random() - 0.5) * 60, 0.4, { 0.7, 0.9, 1 }, 0, true)
        end
      end
      table.remove(shots, i)
    end
  end
end

function enemies.afterDraw()
  for _, s in ipairs(shots) do
    if s.kind == "bubble" then
      love.graphics.setColor(0.6, 0.85, 1, 0.55)
      love.graphics.circle("fill", s.x, s.y, s.r)
      love.graphics.setColor(0.9, 1, 1, 0.9)
      love.graphics.circle("line", s.x, s.y, s.r)
    else
      love.graphics.setColor(0.7, 0.5, 0.85)
      love.graphics.rectangle("fill", math.floor(s.x), math.floor(s.y), 2, 2)
    end
  end
  -- the boss's lines and the fish that is about to eat it
  for _, e in ipairs(enemies.all()) do
    if e.kind == "bigfish" and not e.dead then
      local pulse = 0.55 + 0.4 * math.sin(love.timer.getTime() * 18)
      if e.tele then
        love.graphics.setColor(1, 0.92, 0.15, pulse)
        if e.tele.band then
          for _, ty in ipairs(e.tele.ys or { e.tele.y }) do
            dotted(e.tele.x0, ty, e.tele.x1, ty)
          end
        elseif e.tele.pts then
          for i = 1, #e.tele.pts - 1 do
            dotted(e.tele.pts[i][1], e.tele.pts[i][2], e.tele.pts[i + 1][1], e.tele.pts[i + 1][2])
          end
        end
      end
      if e.eater then
        local er = e.eater
        local st = STAGES[er.stage]
        drawFishBody(e, er.stage, er.x, er.y, st.w, st.h, er.ang or 0, false, math.floor(love.timer.getTime() * 10) % 2, true)
      end
    end
  end
end

-- For the compendium: a fish of stage n (1..4) posed facing right, its body's top-left at (0, 0)
function aquatic.specimen(n)
  local e = enemies.specimen("bigfish")
  stageInit(e, n, STAGES[n].w / 2, STAGES[n].h / 2)
  e.ang, e.facing = 0, 1
  return e
end

aquatic.STAGES = STAGES
aquatic.stageInit = stageInit
aquatic.toothRect = toothRect
return aquatic
