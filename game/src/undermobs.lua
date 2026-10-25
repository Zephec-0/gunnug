-- The creatures of the Undercroft (docs/undercroft-design.md), below the Deep. The fossil beds and the Greywacke
-- reuse the creatures of the Quarry and the Needle; these two are the first that are the Undercroft's own, met from
-- the Buried City down:
--   Slagback    a heap of cooling slag that has learnt to crawl, crust dark and cracked, the cracks still white-hot.
--               A mound until the hunter is close or a bullet finds it (the crust shrugs off half a hit), then it
--               crawls at him leaving a trail of molten pools, and stops to spit globs of lava over the ground
--               between them. Dying, it spills what is left of its heat
--   Ash Shade   a drifting column of volcanic ash: grey, ragged at the edges, two dark hollows for eyes with an
--               ember in each. It keeps its distance, then swells and breathes out a fan of ash that stings; when
--               it dies it simply falls apart
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

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w or 1, h or 1)
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

-- Definitions ---------------------------------------------------------------------------------------

local D = enemies.defs
D.slagback = {
  name = "Slagback",
  ground = true, w = 16, h = 11, hp = 110, speed = 36, jump = 150,
  sight = 260, forget = 760, damage = 15,
  knockback = 0.08, gold = { 9, 17 }, weight = 6, pushForce = 220,
  spriteW = 16, spriteH = 11, scale = 1,
  blood = { 0.95, 0.42, 0.12 },
  desc = "A heap of cooling slag that has learnt to crawl. Still a mound it shrugs off half of what hits it; awake, it leaves pools of molten rock where it has been and stops now and then to spit lava at you across the ground. Its cracks show where it is soft.",
}
D.ashshade = {
  name = "Ash Shade",
  w = 16, h = 22, hp = 64, speed = 52, accel = 140,
  sight = 380, forget = 900, damage = 10, breathRange = 190,
  knockback = 0.25, gold = { 8, 15 }, weight = 1,
  spriteW = 16, spriteH = 22, scale = 1,
  blood = { 0.55, 0.52, 0.48 },
  desc = "A column of volcanic ash with two embers for eyes, drifting after you at a distance. It swells, then breathes out a fan of ash that stings. Shot, it comes apart, and gathers again if it is let alone.",
}
for _, k in ipairs({ "slagback", "ashshade" }) do
  enemies.order[#enemies.order + 1] = k
end

-- A slagback still a mound takes half; an ash shade that is breathing out is mostly air
D.slagback.filter = function(e, amount)
  if e.state == "idle" or e.state == "stir" then
    audio.playAt("clank", e.body.x, e.body.y, 0.35, 0.8)
    if e.state == "idle" then
      e.state, e.timer = "stir", 0.8
    end
    return math.max(1, math.floor(amount * 0.5))
  end
  return amount
end
D.ashshade.filter = function(e, amount)
  if e.state == "breathe" then
    return math.max(1, math.floor(amount * 0.6))
  end
  return amount
end

enemies.VOICES.slagback = { "crab_rumble", 4, 9, 1 }
enemies.VOICES.ashshade = { "wraith_moan", 4, 9, 0.7 }

D.slagback.light = function(e)
  local cx, cy = center(e)
  local k = (e.state == "idle") and 0.1 or (e.state == "spit" and 0.6 or 0.4)
  return { cx, cy, 40, 1, 0.5, 0.15, k }
end
D.ashshade.light = function(e)
  local cx, cy = center(e)
  return { cx, cy - 4, 20, 0.75, 0.5, 0.35, e.state == "breathe" and 0.25 or 0.1 }
end

-- What both of them throw ----------------------------------------------------------------------------

local shots = {} -- globs of lava and puffs of ash: { x, y, vx, vy, life, dmg, lava, g }
local pools = {} -- lava pools lying on the ground: { x, y, life, hit }

local function pool(x, y, life)
  if #pools < 90 then
    pools[#pools + 1] = { x = x, y = y, life = life, hit = 0 }
  end
end

local function launch(e, ang, speed, lava)
  local cx, cy = center(e)
  shots[#shots + 1] = {
    x = cx + math.cos(ang) * 6, y = cy - 2 + math.sin(ang) * 4,
    vx = math.cos(ang) * speed, vy = math.sin(ang) * speed,
    life = lava and 4 or 3.2, lava = lava, g = lava and 420 or 14,
    dmg = math.max(1, math.floor((lava and 9 or 6) * e.dmgMul + 0.5)),
  }
end

-- The slagback --------------------------------------------------------------------------------------------

local function updateSlag(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local collide = collider(e, world)
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
  e.phase = e.phase + math.abs(b.vx) * dt * 0.3 + dt * 0.6
  e.contactMul = e.state == "idle" and 0.2 or 1
  e.spitCd = math.max(0, (e.spitCd or 1.5) - dt)
  e.trailT = (e.trailT or 0) - dt
  local want = 0
  if e.state == "idle" then
    -- a heap of slag; it stirs when the hunter is close, or when shot (def.filter)
    b.vx = 0
    if (e.seesPlayer and dist < 140) or dist < 50 or e.hp < e.maxHp then
      e.state, e.timer = "stir", 0.8
      audio.playAt("crab_rumble", cx, cy, 0.9, 0.8)
    end
  elseif e.state == "stir" then
    e.timer = e.timer - dt
    b.vx = 0
    if love.math.random() < dt * 20 then
      effects.particle(cx + (love.math.random() - 0.5) * 12, b.y + 2, (love.math.random() - 0.5) * 30, -20 - love.math.random() * 30, 0.4, { 1, 0.5, 0.15 }, 200)
    end
    if e.timer <= 0 then
      e.state = "crawl"
    end
  elseif e.state == "crawl" then
    e.facing = px < cx and -1 or 1
    if e.seesPlayer or dist < def.sight then
      want = e.facing * def.speed * (dist < 45 and 0.5 or 1)
    end
    if dist > def.forget then
      e.state = "idle"
    end
    if e.trailT <= 0 and e.grounded and math.abs(b.vx) > 5 then
      e.trailT = 0.5
      pool(cx, b.y + b.h - 1, 3.5)
    end
    if e.stun <= 0 and e.spitCd <= 0 and e.seesPlayer and dist > 60 and dist < 230 and e.grounded then
      e.state, e.timer, e.fired = "spit", 0.7, false
      audio.playAt("crab_rumble", cx, cy, 0.8, 1.3)
    end
  elseif e.state == "spit" then
    e.facing = px < cx and -1 or 1
    e.timer = e.timer - dt
    b.vx = b.vx * math.exp(-10 * dt)
    if e.timer < 0.25 and not e.fired then
      e.fired = true
      audio.playAt("crow_spit", cx, cy, 1, 0.55)
      local d = math.max(40, dist)
      local t = clamp(d / 170, 0.45, 1.2)
      for i = -1, 1, 2 do
        local tx = px + i * 12
        shots[#shots + 1] = {
          x = cx + e.facing * 6, y = b.y + 1,
          vx = (tx - cx) / t, vy = (py - b.y) / t - 0.5 * 420 * t,
          life = 4, lava = true, g = 420, dmg = math.max(1, math.floor(9 * e.dmgMul + 0.5)),
        }
      end
    end
    if e.timer <= 0 then
      e.state, e.spitCd = "crawl", 3 + love.math.random() * 2
    end
  end
  if e.state == "crawl" then
    local accel = e.grounded and 600 or 250
    b.vx = b.vx < want and math.min(want, b.vx + accel * dt) or math.max(want, b.vx - accel * dt)
  end
  b.vy = math.min(b.vy + config.gravity * dt, 450)
  if Body.moveX(b, collide, b.vx * dt, 4) then
    if e.grounded and e.state == "crawl" then
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
  if e.state ~= "idle" and love.math.random() < dt * 4 then
    effects.particle(cx + (love.math.random() - 0.5) * 10, b.y + 2, (love.math.random() - 0.5) * 8, -14, 0.5, { 1, 0.55, 0.18 }, -6, true)
  end
end

D.slagback.onDeath = function(e)
  local cx, cy = center(e)
  pool(cx, e.body.y + e.body.h - 1, 4.5)
  for _ = 1, 14 do
    effects.particle(cx, cy, (love.math.random() - 0.5) * 140, -30 - love.math.random() * 90, 0.8, { 1, 0.5, 0.14 }, 360)
  end
end

local SL = {
  dark = { 0.15, 0.115, 0.105 }, mid = { 0.28, 0.21, 0.18 }, light = { 0.44, 0.34, 0.28 }, hot = { 0.62, 0.30, 0.14 },
}

local function drawSlag(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local f = e.facing
  local mid, y = b.x + b.w / 2, b.y
  local mound = e.state == "idle" or e.state == "stir"
  local walk = (e.grounded and math.abs(b.vx) > 4) and math.sin(e.phase * 5) or 0
  local bob = (e.state == "crawl" and walk > 0) and 1 or 0
  local up = e.state == "spit" and 2 or 0
  if mound then
    -- a cooled heap
    color(SL.dark)
    rect(mid - 8, y + 5, 16, 6)
    color(SL.mid)
    rect(mid - 7, y + 3, 14, 6)
    rect(mid - 4, y + 1, 9, 3)
    color(SL.light)
    rect(mid - 6, y + 3, 4, 1)
    rect(mid - 3, y + 1, 4, 1)
    return
  end
  -- feet: two pairs of stubs, alternating as it crawls
  color(SL.dark)
  rect(mid - 7, y + 9 - (walk > 0 and 1 or 0), 3, 2)
  rect(mid - 2, y + 9 - (walk < 0 and 1 or 0), 3, 2)
  rect(mid + 4, y + 9 - (walk > 0 and 1 or 0), 3, 2)
  -- the body: a low hump of plated crust, tallest over the head end
  color(SL.dark)
  rect(mid - 8, y + 4 + bob, 16, 5)
  color(SL.mid)
  rect(mid - 7, y + 2 + bob - up, 14, 6)
  rect(mid - 5 + f * 1, y + bob - up, 9, 3)
  color(SL.light)
  rect(mid - 6, y + 2 + bob - up, 5, 1)
  rect(mid - 3 + f, y + bob - up, 5, 1)
  rect(mid + 2, y + 3 + bob - up, 3, 1)
  color(SL.hot)
  rect(mid - 7, y + 7 + bob, 14, 1)
  -- the head end: a blunt snout with a bright maw when it spits
  color(SL.mid)
  rect(mid + f * 7 - (f < 0 and 3 or 0), y + 3 + bob, 4, 4)
  color(SL.dark)
  rect(mid + f * 7 - (f < 0 and 3 or 0), y + 6 + bob, 4, 1)
end

local function drawSlagGlow(e)
  local b = e.body
  local f = e.facing
  local mid, y = b.x + b.w / 2, b.y
  local t = love.timer.getTime()
  local k = 0.7 + 0.3 * math.sin(t * 5 + e.phase)
  if e.state == "idle" then
    love.graphics.setColor(1, 0.45, 0.12, 0.35 * k)
    rect(mid - 3, y + 6)
    rect(mid + 2, y + 5)
    return
  end
  local walk = (e.grounded and math.abs(b.vx) > 4) and math.sin(e.phase * 5) or 0
  local bob = (e.state == "crawl" and walk > 0) and 1 or 0
  local hot = e.state == "spit"
  love.graphics.setColor(1, hot and 0.9 or 0.5, hot and 0.6 or 0.12, k)
  -- cracks across the back
  rect(mid - 5, y + 3 + bob)
  rect(mid - 4, y + 4 + bob)
  rect(mid - 3, y + 4 + bob)
  rect(mid - 2, y + 5 + bob)
  rect(mid + 1, y + 3 + bob)
  rect(mid + 2, y + 4 + bob)
  rect(mid + 3, y + 5 + bob)
  rect(mid - 6, y + 6 + bob)
  rect(mid + 5, y + 6 + bob)
  -- eyes
  love.graphics.setColor(1, 0.95, 0.6)
  rect(mid + f * 8 - (f < 0 and 1 or 0), y + 4 + bob)
  if hot then
    love.graphics.setColor(1, 0.7, 0.2)
    rect(mid + f * 9 - (f < 0 and 2 or 0), y + 5 + bob, 2, 2)
  end
end

-- The ash shade -------------------------------------------------------------------------------------------

local function updateShade(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  e.phase = e.phase + dt * (e.state == "breathe" and 9 or 3)
  e.attackCd = math.max(0, (e.attackCd or (2 + love.math.random() * 2)) - dt)
  if e.state == "sleep" then
    if e.seesPlayer and dist < def.sight then
      e.state = "chase"
      audio.playAt("wraith_moan", cx, cy, 0.5, 0.9)
    else
      return
    end
  end
  local collide = collider(e, world)
  -- it keeps its distance: about 90 px off, a little above the hunter
  local tx, ty = px - sign(px - cx) * 90, py - 22
  local wantx = clamp((tx - cx) * 1.2, -def.speed, def.speed)
  local wanty = clamp((ty - cy) * 1.2, -def.speed, def.speed) + math.sin(e.phase * 0.4) * 10
  if not e.seesPlayer then
    local fx, fy = flowDirection(world, cx, cy, px, py - 4)
    if fx then
      wantx, wanty = fx * def.speed, fy * def.speed
    end
  end
  if e.state == "breathe" then
    wantx, wanty = wantx * 0.15, wanty * 0.15
    e.timer = e.timer - dt
    if love.math.random() < dt * 40 then
      effects.particle(cx + (love.math.random() - 0.5) * 14, cy + (love.math.random() - 0.5) * 18, 0, -10, 0.5, { 0.6, 0.57, 0.52 }, 0)
    end
    if e.timer < 0.1 and not e.fired then
      e.fired = true
      audio.playAt("wind_howl", cx, cy, 0.8, 0.7)
      local base = math.atan2(py - cy, px - cx)
      for i = -3, 3 do
        launch(e, base + i * 0.2, 80 + love.math.random() * 30, false)
      end
    end
    if e.timer <= 0 then
      e.state, e.attackCd = "chase", 3.5 + love.math.random() * 2
    end
  elseif e.seesPlayer and dist < def.breathRange and e.attackCd <= 0 and e.stun <= 0 then
    e.state, e.timer, e.fired = "breathe", 0.9, false
    audio.playAt("wraith_moan", cx, cy, 0.8, 1.2)
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
  if love.math.random() < dt * 10 then
    effects.particle(cx + (love.math.random() - 0.5) * 8, b.y + b.h - 2, (love.math.random() - 0.5) * 10, 6 + love.math.random() * 8, 0.8, { 0.5, 0.47, 0.43 }, 0)
  end
end

D.ashshade.onDeath = function(e)
  local cx, cy = center(e)
  for _ = 1, 22 do
    effects.particle(cx + (love.math.random() - 0.5) * 10, cy + (love.math.random() - 0.5) * 16, (love.math.random() - 0.5) * 70, -10 - love.math.random() * 40, 1.1, { 0.55, 0.52, 0.48 }, 30)
  end
end

local AS = { { 0.30, 0.285, 0.27 }, { 0.45, 0.43, 0.40 }, { 0.62, 0.59, 0.54 } }

local function drawShade(e)
  local b = e.body
  local white = e.flash > 0
  local mid = b.x + b.w / 2
  local swell = e.state == "breathe" and 2 or 0
  local t = e.phase
  -- rows of ash, swelling toward the head and ragged at the foot; each row a little off the one above, and
  -- the shades turning as it drifts, the edges a one-pixel checker
  for row = 0, 10 do
    local u = row / 10
    local y = b.y + row * 2
    local w = math.floor(4 + math.sin(u * math.pi * 0.85 + 0.2) * 9 + swell + 0.5)
    local off = math.floor(math.sin(t * 0.6 + row * 0.7) * (1 + (1 - u) * 1.5) + 0.5)
    local shade = AS[(row + math.floor(t * 0.7)) % 3 + 1]
    love.graphics.setColor(white and { 1, 1, 1 } or shade)
    local x0 = mid + off - math.floor(w / 2)
    rect(x0 + 1, y, w - 2, 2)
    rect(x0, y + row % 2)
    rect(x0 + w - 1, y + (row + 1) % 2)
  end
  -- two hollows for eyes
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.07, 0.065, 0.065 })
  rect(mid - 4, b.y + 6, 3, 3)
  rect(mid + 1, b.y + 6, 3, 3)
end

local function drawShadeGlow(e)
  local b = e.body
  local mid = b.x + b.w / 2
  local k = e.state == "breathe" and 1 or 0.7 + 0.3 * math.sin(love.timer.getTime() * 4 + e.phase)
  love.graphics.setColor(1, 0.5 + 0.3 * k, 0.15, k)
  rect(mid - 3, b.y + 7)
  rect(mid + 2, b.y + 7)
end

-- Hooks ---------------------------------------------------------------------------------------------------------

enemies.UPDATE.slagback = updateSlag
enemies.DRAW.slagback = drawSlag
enemies.GLOW.slagback = drawSlagGlow
enemies.UPDATE.ashshade = updateShade
enemies.DRAW.ashshade = drawShade
enemies.GLOW.ashshade = drawShadeGlow

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  local pb = player.body
  for i = #shots, 1, -1 do
    local s = shots[i]
    s.life = s.life - dt
    s.vy = s.vy + s.g * dt
    if not s.lava then
      s.vx, s.vy = s.vx * math.exp(-0.6 * dt), s.vy * math.exp(-0.6 * dt)
    end
    local steps = math.max(1, math.ceil(math.max(math.abs(s.vx), math.abs(s.vy)) * dt / 2))
    local gone = s.life <= 0
    for _ = 1, steps do
      if gone then
        break
      end
      s.x, s.y = s.x + s.vx * dt / steps, s.y + s.vy * dt / steps
      if world:isSolid(s.x, s.y) then
        if s.lava then
          pool(s.x - s.vx * 0.01, s.y - 1, 3)
          for _ = 1, 5 do
            effects.particle(s.x, s.y, (love.math.random() - 0.5) * 70, -love.math.random() * 60, 0.5, { 1, 0.5, 0.15 }, 300)
          end
        else
          for _ = 1, 3 do
            effects.particle(s.x, s.y, (love.math.random() - 0.5) * 30, -love.math.random() * 20, 0.5, { 0.55, 0.52, 0.48 }, 20)
          end
        end
        gone = true
      elseif not player.dead and overlaps(s.x - 2, s.y - 2, 4, 4, pb.x, pb.y, pb.w, pb.h) then
        player:hurt(s.dmg, s.x - s.vx * 0.05, s.y - s.vy * 0.05, s.lava and "slagback" or "ashshade")
        if s.lava then
          for _ = 1, 6 do
            effects.particle(s.x, s.y, (love.math.random() - 0.5) * 70, -love.math.random() * 60, 0.5, { 1, 0.5, 0.15 }, 300)
          end
        end
        gone = true
      end
    end
    if gone then
      table.remove(shots, i)
    end
  end
  for i = #pools, 1, -1 do
    local p = pools[i]
    p.life = p.life - dt
    p.hit = math.max(0, p.hit - dt)
    if p.life <= 0 then
      table.remove(pools, i)
    elseif not player.dead and p.hit <= 0 and overlaps(p.x - 4, p.y - 2, 8, 3, pb.x, pb.y, pb.w, pb.h) then
      p.hit = 0.6
      player:hurt(5, p.x, p.y + 4, "slagback")
    end
  end
end

local prevDraw = enemies.afterDraw
enemies.afterDraw = function(view)
  if prevDraw then
    prevDraw(view)
  end
  local t = love.timer.getTime()
  for _, p in ipairs(pools) do
    local k = math.min(1, p.life / 1.2)
    love.graphics.setColor(0.45 + 0.1 * k, 0.17, 0.08)
    rect(p.x - 4, p.y, 8, 1)
    love.graphics.setColor(1, 0.45 + 0.2 * math.sin(t * 8 + p.x), 0.12)
    rect(p.x - 3, p.y - 1, 6, 1)
    rect(p.x - 1 + math.floor(math.sin(t * 6 + p.x) * 2), p.y - 2)
  end
  for _, s in ipairs(shots) do
    if s.lava then
      love.graphics.setColor(0.9, 0.35, 0.1)
      rect(s.x - 2, s.y - 2, 4, 4)
      love.graphics.setColor(1, 0.8, 0.35)
      rect(s.x - 1, s.y - 1, 2, 2)
    else
      love.graphics.setColor(0.36, 0.34, 0.31)
      rect(s.x - 2, s.y - 2, 4, 4)
      love.graphics.setColor(0.62, 0.59, 0.54)
      rect(s.x - 2, s.y - 2, 3, 2)
    end
  end
end

local prevClear = enemies.clear
enemies.clear = function()
  prevClear()
  shots, pools = {}, {}
end

return true
