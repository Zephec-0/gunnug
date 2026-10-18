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

local STAGES = {
  { name = "Big Fish", w = 24, h = 15, damage = 10 },
  { name = "Bigger Fish", w = 48, h = 30, damage = 16 },
  { name = "Even Bigger Fish", w = 96, h = 60, damage = 22 },
  { name = "The Biggest Fish", w = 520, h = 280, damage = 0 },
}
local STAGE_HP = 100
local GATE_HP = 10 -- the fish holds at this much until the bigger one arrives
local EAT_AT = 20 -- ...which comes at 20% of its health

local STYLE = {
  { back = { 0.36, 0.42, 0.48 }, body = { 0.62, 0.68, 0.70 }, light = { 0.82, 0.86, 0.86 }, belly = { 0.78, 0.30, 0.24 }, fin = { 0.70, 0.25, 0.20 } },
  { back = { 0.14, 0.22, 0.40 }, body = { 0.28, 0.42, 0.62 }, light = { 0.56, 0.72, 0.88 }, belly = { 0.52, 0.20, 0.30 }, fin = { 0.44, 0.14, 0.30 } },
  { back = { 0.13, 0.13, 0.24 }, body = { 0.28, 0.30, 0.46 }, light = { 0.50, 0.54, 0.70 }, belly = { 0.36, 0.14, 0.20 }, fin = { 0.30, 0.10, 0.20 } },
  { back = { 0.10, 0.10, 0.18 }, body = { 0.24, 0.26, 0.40 }, light = { 0.44, 0.48, 0.64 }, belly = { 0.28, 0.09, 0.13 }, fin = { 0.22, 0.07, 0.14 } },
}

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
    local cx, cy = center(e)
    return { cx, cy, math.min(420, 40 + e.body.w * 0.8), 0.55, 0.72, 1, 0.38 }
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

local function drawFishBody(e, stage, cx, cy, w, h, ang, flash, beat, openMouth)
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

-- The last fish's teeth: two fangs in each jaw, standing out beyond the front of its body
-- (centre and size as fractions of it), so a shot reaches them before it reaches the body
local TEETH = {
  { 0.585, -0.02, 0.10, 0.24 }, -- upper, front
  { 0.525, 0.0, 0.07, 0.16 }, -- upper, back
  { 0.595, 0.27, 0.10, 0.24 }, -- lower, front
  { 0.535, 0.23, 0.07, 0.16 }, -- lower, back
}

local function toothRect(e, i)
  local b = e.body
  local P = framePoint(e)
  local t = TEETH[i]
  local x, y = P(t[1], t[2])
  local tw, th = t[3] * b.w, t[4] * b.h
  local ca, sa = math.abs(math.cos(e.ang or 0)), math.abs(math.sin(e.ang or 0))
  local bw, bh = tw * ca + th * sa, tw * sa + th * ca
  return x - bw / 2, y - bh / 2, bw, bh
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

-- A shot can hit a tooth even where it is outside the body's box
local function extraHit(e, px, py)
  if e.stage ~= 4 or not e.teeth then
    return false
  end
  for i = 1, 4 do
    if e.teeth[i] then
      local tx, ty, tw, th = toothRect(e, i)
      if px >= tx - 3 and px <= tx + tw + 3 and py >= ty - 3 and py <= ty + th + 3 then
        return true
      end
    end
  end
  return false
end

-- The Biggest Fish: a huge head and a gaping, fanged maw, a ribbed dorsal fin, a
-- pair of big orange bulbs on its flank (not its eyes) and a small red real eye
local function drawBiggest(e)
  local b = e.body
  local w, h = b.w, b.h
  local flash = e.flash > 0
  local t = love.timer.getTime() + e.phase
  local P = framePoint(e)
  local function poly(col, ...)
    local pts = { ... }
    local out = {}
    for i = 1, #pts, 2 do
      local x, y = P(pts[i], pts[i + 1])
      out[#out + 1], out[#out + 2] = x, y
    end
    love.graphics.setColor(col[1], col[2], col[3], col[4] or 1)
    love.graphics.polygon("fill", out)
  end
  local function C(c)
    return flash and { 1, 1, 1 } or c
  end
  local body, dark, belly, fin = C({ 0.30, 0.36, 0.44 }), C({ 0.14, 0.17, 0.24 }), C({ 0.56, 0.62, 0.68 }), C({ 0.20, 0.24, 0.34 })
  local sway = math.sin(t * 2) * 0.02
  -- tail
  poly(fin, -0.36, -0.04, -0.52, -0.2 + sway, -0.47, 0.0, -0.52, 0.2 - sway, -0.36, 0.06)
  -- dorsal fin, with ribs
  poly(fin, -0.28, -0.3, -0.12, -0.52, 0.08, -0.5, 0.2, -0.3)
  love.graphics.setColor(dark[1], dark[2], dark[3], 0.8)
  for i = 0, 4 do
    local x0, y0 = P(-0.22 + i * 0.07, -0.3)
    local x1, y1 = P(-0.16 + i * 0.065, -0.48)
    love.graphics.line(x0, y0, x1, y1)
  end
  -- the round body and the pale belly
  poly(body, -0.42, 0.0, -0.3, -0.3, -0.05, -0.37, 0.24, -0.33, 0.4, -0.2, 0.4, 0.2, 0.2, 0.36, -0.1, 0.4, -0.32, 0.28)
  poly(belly, -0.38, 0.12, -0.1, 0.34, 0.2, 0.32, 0.38, 0.18, 0.1, 0.4, -0.2, 0.42, -0.34, 0.28)
  -- pectoral fin
  poly(fin, -0.02, 0.2, 0.12, 0.34, 0.06, 0.46, -0.1, 0.34)
  -- gill slits
  love.graphics.setColor(dark[1], dark[2], dark[3], 0.9)
  for i = 0, 2 do
    local x0, y0 = P(0.04 + i * 0.03, -0.06)
    local x1, y1 = P(0.01 + i * 0.03, 0.14)
    love.graphics.line(x0, y0, x1, y1)
  end
  -- the head: an upper jaw reaching out past the body, the lower jaw hanging open
  local open = 0.05 * math.sin(t * 1.3)
  poly(body, 0.2, -0.33, 0.5, -0.18, 0.64, -0.06, 0.62, -0.01, 0.22, 0.0)
  poly(C({ 0.30, 0.04, 0.07 }), 0.62, -0.01, 0.62, 0.27 + open, 0.14, 0.12, 0.14, 0.02)
  poly(belly, 0.62, 0.27 + open, 0.64, 0.43 + open, 0.02, 0.36, 0.14, 0.12)
  poly(dark, 0.62, -0.01, 0.62, 0.03, 0.2, 0.03, 0.22, -0.02)
  -- the four teeth: curved fangs, or the stump of a broken one
  local bone = C({ 0.95, 0.93, 0.84 })
  for i = 1, 4 do
    local tu = TEETH[i]
    local up = i <= 2
    local x0, x1 = tu[1] - tu[3] / 2, tu[1] + tu[3] / 2
    local y0, y1 = tu[2] - tu[4] / 2, tu[2] + tu[4] / 2
    if e.teeth and e.teeth[i] then
      if up then
        poly(bone, x0, y0, x1, y0, x1 + tu[3] * 0.2, y1)
      else
        poly(bone, x0, y1, x1, y1, x1 + tu[3] * 0.2, y0)
      end
      local ax, ay = P(tu[1], up and y0 or y1)
      local bx, by = P(tu[1] + tu[3] * 0.1, up and y0 + tu[4] * 0.8 or y1 - tu[4] * 0.8)
      love.graphics.setColor(0.6, 0.55, 0.45)
      love.graphics.line(ax, ay, bx, by)
    else
      local sy0 = up and y0 or y1 - tu[4] * 0.2
      poly({ 0.58, 0.52, 0.44 }, x0 + tu[3] * 0.15, sy0, x1 - tu[3] * 0.15, sy0, x1 - tu[3] * 0.15, sy0 + tu[4] * 0.2, x0 + tu[3] * 0.15, sy0 + tu[4] * 0.2)
    end
  end
  -- the big orange bulb: it is not an eye
  local bx, by = P(-0.04, -0.12)
  local br = h * 0.1
  love.graphics.setColor(dark[1], dark[2], dark[3])
  love.graphics.circle("fill", bx, by, br + 4)
  love.graphics.setColor(flash and 1 or 0.95, flash and 1 or 0.45, flash and 1 or 0.1)
  love.graphics.circle("fill", bx, by, br)
  love.graphics.setColor(1, 0.8, 0.4, 0.8)
  love.graphics.circle("fill", bx - br * 0.3, by - br * 0.3, br * 0.4)
  -- its real eye: a small red dot
  local ex, ey = P(0.37, -0.2)
  love.graphics.setColor(1, 0.1, 0.1)
  love.graphics.circle("fill", ex, ey, math.max(3, h * 0.014))
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
  local b = e.body
  local w, h = b.w, b.h
  local P = framePoint(e)
  if e.stage == 4 then
    local pulse = 0.6 + 0.3 * math.sin(love.timer.getTime() * 3)
    local bx, by = P(-0.04, -0.12)
    love.graphics.setColor(1, 0.5, 0.1, 0.35 * pulse)
    love.graphics.circle("fill", bx, by, h * 0.17)
    love.graphics.setColor(1, 0.7, 0.2, 0.55 * pulse)
    love.graphics.circle("fill", bx, by, h * 0.1)
    local ex, ey = P(0.37, -0.2)
    love.graphics.setColor(1, 0.1, 0.1, 0.9)
    love.graphics.circle("fill", ex, ey, math.max(3, h * 0.016))
    -- the teeth, lit, so they can be shot at
    for i = 1, 4 do
      if e.teeth and e.teeth[i] then
        local tx, ty, tw, th = toothRect(e, i)
        love.graphics.setColor(1, 0.97, 0.85, 0.55)
        love.graphics.rectangle("fill", tx + tw * 0.2, ty + th * 0.1, tw * 0.6, th * 0.8)
      end
    end
    return
  end
  -- the eye
  local ex, ey = P(18.5 / 24 - 0.5, 5 / 15 - 0.5)
  love.graphics.setColor(1, 0.35, 0.2, 0.9)
  love.graphics.circle("fill", ex, ey, math.max(1, math.min(w / 24, 14)))
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
  e.retreatT = nil
end

local function clampToArena(e)
  local a = e.arena
  if not a then
    return
  end
  local b = e.body
  local cx, cy = center(e)
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

local function startEater(e)
  e.gate = true
  local cx, cy = center(e)
  local a = love.math.random() * math.pi * 2
  local x, y = cx + math.cos(a) * 700, cy + math.sin(a) * 500
  if e.arena then
    x = math.max(e.arena.x0 + 40, math.min(e.arena.x1 - 40, x))
    y = math.max(e.arena.top + 40, math.min(e.arena.floorY - 40, y))
  end
  e.eater = { x = x, y = y, stage = e.stage + 1, t = 0 }
  sfx("fish_groan", 1, 0.7)
end

local function updateEater(e, dt)
  local er = e.eater
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
  if d < st.w * 0.35 + 8 or er.t > 7 then
    -- chomp: the smaller fish is gone, the bigger one is the boss
    sfx("fish_chomp", 1, 0.8)
    for _ = 1, 18 do
      effects.chunk(cx + (love.math.random() - 0.5) * e.body.w, cy + (love.math.random() - 0.5) * e.body.h, (love.math.random() - 0.5) * 160, (love.math.random() - 0.5) * 120, 2, 2, love.math.random() < 0.5 and { 0.8, 0.2, 0.2 } or { 0.7, 0.7, 0.75 }, 3)
      effects.particle(cx, cy, (love.math.random() - 0.5) * 120, (love.math.random() - 0.5) * 120, 0.8, { 1, 0.4, 0.4 }, -20, true)
    end
    effects.ring(er.x, er.y, st.w * 0.6 + 14, { 1, 0.5, 0.4 })
    local facing = er.facing or 1
    local nx, ny = cx, cy -- (it takes the smaller fish's place: no jump)
    stageInit(e, er.stage, nx, ny)
    e.facing = facing
    clampToArena(e)
    effects.popup(nx, ny - st.h / 2 - 10, STAGES[er.stage].name, { 1, 0.5, 0.45 })
    require("src.camera").shake(0.6)
    e.invulnT = 0.8
  end
end

local function aimAngle(e, px, py)
  local cx, cy = center(e)
  return math.atan2(py - cy, px - cx)
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
  if e.dormant then
    e.state = "idle"
    b.vx, b.vy = 0, 0
    return -- (it lies in wait until the fight starts: see src.scenes.catacombs)
  end
  updateAngle(e, dt, px, py)
  local bs = e.bs
  bs.t = bs.t + dt
  local cx, cy = center(e)
  local dist = math.max(1, hypot(px - cx, py - cy))
  local stage = e.stage

  if stage < 4 and not e.gate and e.hp <= EAT_AT then
    startEater(e)
  end
  if e.eater then
    updateEater(e, dt)
    if e.stage ~= stage then
      return -- (it has just been eaten: the bigger fish starts fresh next frame)
    end
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

  -- Stage 1: dart in, bite, dash away twice as far in a random direction ----------------
  if stage == 1 then
    if bs.mode == "approach" then
      local a = aimAngle(e, px, py)
      moveBy(e, math.cos(a) * 75, math.sin(a) * 75, dt)
      if dist < 120 or bs.t > 3 then
        setMode("windup")
        faceToward(e, px)
      end
    elseif bs.mode == "windup" then
      faceToward(e, px)
      b.vx, b.vy = 0, 0
      if bs.t > 0.35 then
        bs.dir = aimAngle(e, px, py)
        setMode("dash", { dir = bs.dir })
        sfx("fish_dash", 1, 1.3)
      end
    elseif bs.mode == "dash" then
      moveBy(e, math.cos(bs.dir) * 300, math.sin(bs.dir) * 300, dt)
      if bs.t > 0.35 then
        -- away: a random heading in the half-circle facing away from the hunter, twice as far
        local away = bs.dir + math.pi + (love.math.random() - 0.5) * math.pi * 1.1
        setMode("away", { dir = away })
      end
    elseif bs.mode == "away" then
      moveBy(e, math.cos(bs.dir) * 300, math.sin(bs.dir) * 300, dt)
      if bs.t > 0.7 then
        setMode("approach")
      end
    end

  -- Stage 2: fast zig-zag dashes (shown first by dotted lines), and a burst of bubbles -----
  elseif stage == 2 then
    if bs.mode == "approach" then
      local a = aimAngle(e, px, py)
      moveBy(e, math.cos(a) * 85, math.sin(a) * 85, dt)
      if bs.t > 0.55 then
        bs.n = bs.n + 1
        -- it alternates: a zig-zag, then a spit; far away it always zig-zags to catch up
        if dist > 300 or (bs.n % 2 == 1 and dist > 140) then
          -- far off: a wide zig-zag to catch up, the same size every time
          local sx, sy = cx, cy
          local a2 = aimAngle(e, px, py)
          local pts = { { sx, sy } }
          for i = 1, 4 do
            local along = 190 * i
            local side = (i % 2 == 1 and 1 or -1) * 200
            pts[#pts + 1] = { sx + math.cos(a2) * along - math.sin(a2) * side, sy + math.sin(a2) * along + math.cos(a2) * side }
          end
          e.tele = { pts = pts, t = 1.0, total = 1.0 }
          setMode("zigtele", { pts = pts })
        else
          -- close in: it spits instead
          setMode("bubbles")
          faceToward(e, px)
          sfx("fish_groan", 0.7, 1.4)
        end
      end
    elseif bs.mode == "zigtele" then
      b.vx, b.vy = 0, 0
      if bs.t >= 1.0 then
        setMode("zig", { leg = 1 })
        sfx("fish_dash", 1, 1.1)
      end
    elseif bs.mode == "zig" then
      local p = bs.pts[bs.leg + 1]
      local d = hypot(p[1] - cx, p[2] - cy)
      if d < 22 then
        bs.leg = bs.leg + 1
        if bs.leg >= #bs.pts then
          setMode("rest")
          return
        end
        sfx("fish_dash", 0.6, 1.4)
      else
        moveBy(e, (p[1] - cx) / d * 470, (p[2] - cy) / d * 470, dt)
      end
    elseif bs.mode == "rest" then
      moveBy(e, 0, 0, dt)
      if bs.t > 0.9 then
        setMode("approach")
      end
    elseif bs.mode == "bubbles" then
      faceToward(e, px)
      b.vx, b.vy = 0, 0
      if bs.t > 0.7 and not bs.fired then
        bs.fired = true
        local mx, my = cx + math.cos(e.ang or 0) * b.w * 0.45, cy + math.sin(e.ang or 0) * b.w * 0.45
        local base = aimAngle(e, px, py)
        for i = 0, 8 do
          local a = base + (i - 4) * 0.22
          addShot(mx, my, math.cos(a) * 110, math.sin(a) * 110, 3.5, math.floor(9 * e.dmgMul + 0.5), "bubble", 4)
        end
        sfx("fish_chomp", 0.6, 1.6)
      end
      if bs.t > 1.2 then
        setMode("approach")
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
      moveBy(e, (tx - cx) / d * math.min(260, d * 3), (ty - cy) / d * math.min(260, d * 3), dt)
      faceToward(e, px)
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
      if bs.t > 3.6 then
        local y = py
        if e.arena then
          y = math.max(e.arena.top + b.h, math.min(e.arena.floorY - b.h, y))
        end
        local dir = 1
        e.tele = { band = true, y = y, x0 = px - 560, x1 = px + 560, t = 1.1, total = 1.1 }
        setMode("sweeptele", { dir = dir, y = y, px = px })
      end
    elseif bs.mode == "sweeptele" then
      b.vx, b.vy = 0, 0
      if bs.t > 1.1 then
        -- out of sight to the left (or right), then across
        local startX = bs.px - bs.dir * 560
        b.x, b.y = startX - b.w / 2, bs.y - b.h / 2
        e.facing = bs.dir
        setMode("sweep")
        sfx("fish_dash", 1, 0.8)
        sfx("fish_groan", 0.8, 0.8)
      end
    elseif bs.mode == "sweep" then
      b.x = b.x + bs.dir * 880 * dt
      b.vx, b.vy = bs.dir * 880, 0
      e.ang = bs.dir > 0 and 0 or math.pi
      e.facing = bs.dir
      if bs.t > 1.5 then
        if bs.dir == 1 then
          -- and back the other way, at wherever the hunter has got to
          local y = py
          if e.arena then
            y = math.max(e.arena.top + b.h, math.min(e.arena.floorY - b.h, y))
          end
          e.tele = { band = true, y = y, x0 = px - 560, x1 = px + 560, t = 1.1, total = 1.1 }
          setMode("sweeptele", { dir = -1, y = y, px = px })
        else
          setMode("orbit", { a = math.atan2(cy - py, cx - px), shot = 0.6 })
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
      moveBy(e, math.cos(a) * 230, math.sin(a) * 230, dt)
      e.facing = px < cx and -1 or 1
    else
      local a = aimAngle(e, px, py)
      -- (faster than he can swim)
      moveBy(e, math.cos(a) * 112, math.sin(a) * 112, dt)
      e.facing = px < cx and -1 or 1
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
          if x >= tx - 4 and x <= tx + tw + 4 and y >= ty - 4 and y <= ty + th + 4 then
            e.teeth[i] = false
            e.retreatT = 2.6
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
    -- no shield, but the body barely feels it until the teeth are gone
    e.chip = (e.chip or 0) + amount * 0.01
    local whole = math.floor(e.chip)
    e.chip = e.chip - whole
    return whole
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
          dotted(e.tele.x0, e.tele.y - e.body.h / 2, e.tele.x1, e.tele.y - e.body.h / 2)
          dotted(e.tele.x0, e.tele.y + e.body.h / 2, e.tele.x1, e.tele.y + e.body.h / 2)
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

aquatic.STAGES = STAGES
return aquatic
