-- The Champion of the Heavens' own servants (src.starwarden calls them in; none of them lives anywhere else):
--   Gilded Lens      a brass contraption of the old builders' kind, gilded: it circles the hall and fires fans of
--                    three bolts, a ring closing on you first
--   Cometling        a small comet. It hangs, tail flaring, then streaks across the hall in a line through you
--   Storm Cloud      a medium thundercloud over the hunter. It calls lightning on his spot (the sparks, then the
--                    strike) and rains star bolts
--   Star Guardian    a medium star that circles him with a shell of light. While it lives he cannot be hurt
local enemies = require("src.enemies")
local Body = require("src.body")
local audio = require("src.audio")
local effects = require("src.effects")
local glow = require("src.softglow")

local H = enemies.helpers
local center, collider = H.center, H.collider

local function hypot(x, y)
  return math.sqrt(x * x + y * y)
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w or 1, h or 1)
end

local D = enemies.defs
D.gildedlens = {
  name = "Gilded Lens",
  w = 14, h = 14, hp = 70, speed = 80, accel = 160,
  sight = 900, forget = 3000, damage = 9, boltDamage = 9, boltSpeed = 120,
  knockback = 0.15, gold = { 8, 16 }, weight = 5,
  spriteW = 14, spriteH = 14, scale = 1,
  blood = { 0.95, 0.8, 0.4 },
  desc = "A brass contraption of the old builders, gilded for the Champion. It circles the hall, and when a ring closes on you it fires three bolts in a fan, and they bend after you.",
}
D.cometling = {
  name = "Cometling",
  w = 9, h = 9, hp = 24, speed = 60, accel = 300,
  sight = 900, forget = 3000, damage = 12, dashSpeed = 330,
  knockback = 0.8, gold = { 4, 9 }, weight = 0.5,
  spriteW = 9, spriteH = 9, scale = 1,
  blood = { 0.8, 0.9, 1.0 },
  desc = "A small comet in the Champion's service. It hangs and flares, then streaks across the hall in a straight line through where you stood.",
}
D.stormcloud = {
  name = "Storm Cloud",
  w = 34, h = 18, hp = 150, speed = 55, accel = 90,
  sight = 900, forget = 3000, damage = 8, boltDamage = 8,
  knockback = 0.1, gold = { 10, 20 }, weight = 6,
  spriteW = 34, spriteH = 18, scale = 1,
  blood = { 0.7, 0.75, 0.95 },
  desc = "A thundercloud tamed to the Champion's hand. It follows you overhead, calls lightning down on your spot (sparks first), and rains star bolts.",
}
D.starguardian = {
  name = "Star Guardian",
  w = 22, h = 22, hp = 260, speed = 130, accel = 200,
  sight = 3000, forget = 6000, damage = 10, boltDamage = 9, boltSpeed = 105,
  knockback = 0.05, gold = { 25, 40 }, weight = 10,
  spriteW = 22, spriteH = 22, scale = 1,
  blood = { 1.0, 0.95, 0.6 },
  desc = "A star the Champion sets to circle him in a shell of light. While it burns he cannot be hurt. Break it.",
}
for _, k in ipairs({ "gildedlens", "cometling", "stormcloud", "starguardian" }) do
  enemies.order[#enemies.order + 1] = k
  D[k].knockMul = 0.1 -- (they hardly stagger or lift when shot: only a tenth of the shove)
end
enemies.VOICES.gildedlens = { "clank", 5, 10, 0.5 }
enemies.VOICES.cometling = { "wisp_crackle", 3, 8, 0.5 }
enemies.VOICES.stormcloud = { "wind_howl", 5, 10, 0.5 }
enemies.VOICES.starguardian = { "sw_chime", 4, 8, 0.4 }

D.gildedlens.light = function(e)
  local cx, cy = center(e)
  return { cx, cy, 40, 1, 0.8, 0.4, e.state == "charge" and 0.7 or 0.3 }
end
D.cometling.light = function(e)
  local cx, cy = center(e)
  return { cx, cy, 44, 0.75, 0.88, 1, e.state == "dash" and 0.8 or 0.4 }
end
D.stormcloud.light = function(e)
  local cx, cy = center(e)
  return { cx, cy, 70, 0.6, 0.7, 1, (e.flashT or 0) > 0 and 0.9 or 0.18 }
end
D.starguardian.light = function(e)
  local cx, cy = center(e)
  return { cx, cy, 110, 1, 0.9, 0.55, 0.7 }
end

local function steer(e, dt, collide, wantx, wanty)
  local b, def = e.body, e.def
  if e.stun <= 0 then
    local step = def.accel * dt
    b.vx = b.vx < wantx and math.min(b.vx + step, wantx) or math.max(b.vx - step, wantx)
    b.vy = b.vy < wanty and math.min(b.vy + step, wanty) or math.max(b.vy - step, wanty)
  end
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.4
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.4
  end
end

local function boltDmg(e)
  return math.max(1, math.floor(e.def.boltDamage * e.dmgMul + 0.5))
end

-- The gilded lens ----------------------------------------------------------------------------------------------

local function updateLens(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local collide = collider(e, world)
  e.home = e.home or { cx, cy }
  e.phase = e.phase + dt * 4
  e.attackCd = math.max(0, (e.attackCd or (1 + love.math.random() * 2)) - dt)
  e.contactMul = 0.5
  e.state = e.state == "sleep" and "orbit" or e.state
  e.orbA = (e.orbA or love.math.random() * 6.28) + dt * 0.5 * (e.orbDir or 1)
  e.orbDir = e.orbDir or (love.math.random() < 0.5 and -1 or 1)
  -- it circles above and about the hunter, well off
  local tx, ty = px + math.cos(e.orbA) * 190, py - 70 + math.sin(e.orbA) * 60
  if e.state == "charge" then
    e.timer = e.timer - dt
    e.aimX, e.aimY = px, py
    tx, ty = cx, cy
    if e.timer <= 0 then
      local d = math.max(1, hypot(px - cx, py - cy))
      local base = math.atan2(py - cy, px - cx)
      for k = -1, 1 do
        local a = base + k * 0.22
        enemies.skyBolt(cx, cy, math.cos(a) * def.boltSpeed, math.sin(a) * def.boltSpeed, boltDmg(e), 1.8, 4.5)
      end
      audio.playAt("clank", cx, cy, 0.6, 1.5)
      e.state, e.attackCd = "orbit", 2.4 + love.math.random() * 1.4
    end
  elseif e.attackCd <= 0 and e.stun <= 0 then
    e.state, e.timer = "charge", 0.6
    audio.playAt("tick", cx, cy, 0.7, 0.7)
  end
  steer(e, dt, collide, math.max(-def.speed, math.min(def.speed, (tx - cx) * 1.2)), math.max(-def.speed, math.min(def.speed, (ty - cy) * 1.2)))
  e.facing = px >= cx and 1 or -1
end

local function drawLens(e)
  local b = e.body
  local white = e.flash > 0
  local mid, my = b.x + b.w / 2, b.y + b.h / 2
  local function color(c)
    love.graphics.setColor(white and { 1, 1, 1 } or c)
  end
  local spin = e.phase
  color({ 0.55, 0.38, 0.12 })
  love.graphics.circle("line", mid, my, 8)
  for k = 0, 3 do
    local a = spin + k * math.pi / 2
    rect(mid + math.cos(a) * 8 - 1, my + math.sin(a) * 8 - 1, 3, 3)
  end
  color({ 0.95, 0.76, 0.3 })
  love.graphics.circle("fill", mid, my, 5.5)
  color({ 1, 0.95, 0.65 })
  love.graphics.circle("fill", mid - 1.5, my - 1.5, 2.5)
  color(e.state == "charge" and { 1, 0.4, 0.25 } or { 0.3, 0.9, 1 })
  rect(mid - 1, my - 1, 3, 3)
  if e.state == "charge" and e.aimX then
    -- the ring closing on the hunter
    local k = math.max(0, e.timer / 0.6)
    local r = 6 + k * 14
    local hot = e.timer < 0.2
    love.graphics.setColor(1, hot and 0.2 or 0.7, hot and 0.15 or 0.3, 0.9)
    love.graphics.circle("line", e.aimX, e.aimY, r)
    for a = 0, 3 do
      local dx, dy = math.cos(a * math.pi / 2), math.sin(a * math.pi / 2)
      love.graphics.line(e.aimX + dx * (r - 3), e.aimY + dy * (r - 3), e.aimX + dx * (r + 4), e.aimY + dy * (r + 4))
    end
  end
end

local function glowLens(e)
  local b = e.body
  love.graphics.setColor(e.state == "charge" and { 1, 0.5, 0.3 } or { 0.5, 1, 1 })
  rect(b.x + b.w / 2, b.y + b.h / 2)
end

-- The cometling --------------------------------------------------------------------------------------------------

local function updateComet(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local collide = collider(e, world)
  e.home = e.home or { cx, cy }
  e.phase = e.phase + dt * 10
  e.attackCd = math.max(0, (e.attackCd or (0.5 + love.math.random() * 2.5)) - dt)
  e.contactMul = e.state == "dash" and 1.2 or 0.3
  e.state = e.state == "sleep" and "hang" or e.state
  e.trail = e.trail or {}
  if e.state == "hang" then
    local tx = px + math.sin(e.phase * 0.05 + e.timer) * 220
    local ty = py - 120 + math.cos(e.phase * 0.04) * 50
    steer(e, dt, collide, (tx - cx) * 0.8, (ty - cy) * 0.8)
    if e.attackCd <= 0 and e.stun <= 0 then
      e.state, e.timer = "aim", 0.7
      audio.playAt("sw_charge", cx, cy, 0.4, 1.8)
    end
  elseif e.state == "aim" then
    e.timer = e.timer - dt
    b.vx, b.vy = b.vx * math.exp(-8 * dt), b.vy * math.exp(-8 * dt)
    if e.timer > 0.2 then
      e.ax, e.ay = px, py
    end
    if e.timer <= 0 then
      local d = math.max(1, hypot(e.ax - cx, e.ay - cy))
      b.vx, b.vy = (e.ax - cx) / d * def.dashSpeed, (e.ay - cy) / d * def.dashSpeed
      e.state, e.timer = "dash", 1.0
      audio.playAt("gust_blast", cx, cy, 0.5, 1.8)
    end
    Body.moveX(b, collide, b.vx * dt, 0)
    Body.moveY(b, collide, b.vy * dt)
  elseif e.state == "dash" then
    e.timer = e.timer - dt
    local hit = Body.moveX(b, collide, b.vx * dt, 0) or Body.moveY(b, collide, b.vy * dt)
    if e.timer <= 0 or hit then
      e.state, e.attackCd = "hang", 1.6 + love.math.random() * 1.6
      b.vx, b.vy = b.vx * 0.1, b.vy * 0.1
    end
    if love.math.random() < dt * 80 then
      effects.particle(cx, cy, (love.math.random() - 0.5) * 20, (love.math.random() - 0.5) * 20, 0.4, { 0.8, 0.92, 1 }, 0, true)
    end
  end
  table.insert(e.trail, 1, { cx, cy })
  while #e.trail > 9 do
    table.remove(e.trail)
  end
  e.facing = px >= cx and 1 or -1
end

local function drawComet(e)
  local b = e.body
  local white = e.flash > 0
  local mid, my = b.x + b.w / 2, b.y + b.h / 2
  for i, p in ipairs(e.trail or {}) do
    local k = 1 - i / 10
    love.graphics.setColor(0.7, 0.85, 1, 0.5 * k * (e.state == "dash" and 1.4 or 0.6))
    love.graphics.circle("fill", p[1], p[2], 4 * k + 0.5)
  end
  if e.state == "aim" and e.ax then
    -- the tail flares, and a faint line points where it will go
    love.graphics.setColor(0.8, 0.9, 1, 0.25)
    local d = math.max(1, hypot(e.ax - mid, e.ay - my))
    love.graphics.line(mid, my, mid + (e.ax - mid) / d * 160, my + (e.ay - my) / d * 160)
  end
  love.graphics.setColor(white and { 1, 1, 1 } or { 0.88, 0.95, 1 })
  love.graphics.circle("fill", mid, my, 4.5)
  love.graphics.setColor(white and { 1, 1, 1 } or { 1, 1, 1 })
  love.graphics.circle("fill", mid - 1, my - 1, 2)
end

local function glowComet(e)
  local b = e.body
  glow.disc(b.x + b.w / 2, b.y + b.h / 2, 13, { 0.8, 0.92, 1 }, 0.7)
end

-- The storm cloud --------------------------------------------------------------------------------------------------

local function updateCloud(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local collide = collider(e, world)
  e.phase = e.phase + dt * 2
  e.attackCd = math.max(0, (e.attackCd or (1.5 + love.math.random() * 2)) - dt)
  e.rainCd = math.max(0, (e.rainCd or 3) - dt)
  e.flashT = math.max(0, (e.flashT or 0) - dt)
  e.contactMul = 0.5
  e.state = e.state == "sleep" and "drift" or e.state
  local tx, ty = px + math.sin(e.phase * 0.3) * 90, py - 115 + math.sin(e.phase * 0.7) * 10
  if e.attackCd <= 0 and e.stun <= 0 then
    e.attackCd = 3.4 + love.math.random() * 1.5
    require("src.skyhazards").queueStrike(px + player.body.vx * 0.3, py - 160)
    e.flashT = 0.25
    audio.playAt("sw_chime", cx, cy, 0.4, 0.5)
  end
  if e.rainCd <= 0 and e.stun <= 0 then
    e.rainCd = 5.5 + love.math.random() * 2
    for k = -2, 2 do
      local a = math.pi / 2 + k * 0.28
      enemies.skyBolt(cx + k * 6, cy + 8, math.cos(a) * 95, math.sin(a) * 95, boltDmg(e), 0, 4)
    end
    audio.playAt("sw_orb", cx, cy, 0.4, 1.2)
  end
  steer(e, dt, collide, math.max(-def.speed, math.min(def.speed, (tx - cx) * 1.1)), math.max(-def.speed, math.min(def.speed, (ty - cy) * 1.1)))
  e.facing = px >= cx and 1 or -1
end

local function drawCloud(e)
  -- a thundercloud of the Champion's own make: cream puffs like his arms, gold-rimmed, with a star for a heart
  local b = e.body
  local white = e.flash > 0
  local mid, my = b.x + b.w / 2, b.y + b.h / 2
  local lit = (e.flashT or 0) > 0
  local function color(c, a)
    love.graphics.setColor(white and 1 or c[1], white and 1 or c[2], white and 1 or c[3], a or 1)
  end
  local puffs = { { -12, 3, 6.5 }, { -6, -3, 7.5 }, { 3, -4, 7.5 }, { 11, 1, 7 }, { 0, 4, 8.5 }, { 7, 5, 6 }, { -9, 6, 5.5 } }
  for i, p in ipairs(puffs) do
    local bob = math.sin(e.phase + i * 1.3) * 0.7
    color({ 0.62, 0.68, 0.9 })
    love.graphics.circle("fill", mid + p[1] + 1, my + p[2] + 1.5 + bob, p[3])
    color(lit and { 1, 1, 0.95 } or { 0.97, 0.94, 0.86 })
    love.graphics.circle("fill", mid + p[1], my + p[2] + bob, p[3] - 0.5)
    color({ 1, 1, 0.97 }, 0.9)
    love.graphics.circle("fill", mid + p[1] - p[3] * 0.3, my + p[2] + bob - p[3] * 0.35, p[3] * 0.4)
  end
  -- the gold rim along its lower edge, and a four-point star in the middle
  color({ 0.93, 0.7, 0.22 })
  love.graphics.setLineWidth(1)
  love.graphics.arc("line", "open", mid, my + 3, 15, 0.25, math.pi - 0.25)
  local r = 5 + (lit and 2 or 0)
  color({ 0.55, 0.38, 0.12 })
  love.graphics.polygon("fill", mid, my - r - 3, mid + 2, my - 2, mid + r + 3, my, mid + 2, my + 2, mid, my + r + 3, mid - 2, my + 2, mid - r - 3, my, mid - 2, my - 2)
  color(lit and { 1, 1, 1 } or { 1, 0.9, 0.5 })
  love.graphics.polygon("fill", mid, my - r - 1, mid + 1.5, my - 1.5, mid + r + 1, my, mid + 1.5, my + 1.5, mid, my + r + 1, mid - 1.5, my + 1.5, mid - r - 1, my, mid - 1.5, my - 1.5)
  if lit then
    -- a bolt jumps from it
    color({ 1, 1, 1 })
    love.graphics.line(mid, my + 8, mid - 3, my + 14, mid + 2, my + 18, mid - 1, my + 24)
  end
end

local function glowCloud(e)
  local b = e.body
  local mid, my = b.x + b.w / 2, b.y + b.h / 2
  glow.disc(mid, my, (e.flashT or 0) > 0 and 30 or 14, { 1, 0.9, 0.5 }, (e.flashT or 0) > 0 and 0.9 or 0.45)
end

-- The star guardian ------------------------------------------------------------------------------------------------

local function updateGuardian(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  e.phase = e.phase + dt * 3
  e.attackCd = math.max(0, (e.attackCd or 2.5) - dt)
  e.contactMul = 0.6
  e.state = "chase"
  local boss = e.guardOf
  local bx, by = cx, cy
  if boss and not boss.dead then
    bx, by = center(boss)
  end
  e.orbA = (e.orbA or 0) + dt * (e.hp < e.maxHp * 0.5 and 1.35 or 0.85)
  local R = 150
  local tx, ty = bx + math.cos(e.orbA) * R, by + math.sin(e.orbA) * R * 0.55
  b.vx = b.vx + ((tx - cx) * 5 - b.vx * 3) * dt
  b.vy = b.vy + ((ty - cy) * 5 - b.vy * 3) * dt
  b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
  if e.attackCd <= 0 then
    e.attackCd = 3.2
    local n = e.hp < e.maxHp * 0.5 and 10 or 7
    local off = e.phase
    for k = 0, n - 1 do
      local a = off + k / n * math.pi * 2
      enemies.skyBolt(cx, cy, math.cos(a) * def.boltSpeed, math.sin(a) * def.boltSpeed, boltDmg(e), 0, 5)
    end
    audio.playAt("sw_chime", cx, cy, 0.7, 1.1)
    effects.ring(cx, cy, 24, { 1, 0.95, 0.65 })
  end
  e.facing = 1
end

local function drawGuardian(e)
  local b = e.body
  local white = e.flash > 0
  local mid, my = b.x + b.w / 2, b.y + b.h / 2
  local t = e.phase
  -- a shell of light, and a star of eight spikes that turns inside it
  love.graphics.setColor(white and 1 or 1, white and 1 or 0.9, white and 1 or 0.5, 0.35)
  love.graphics.circle("line", mid, my, 12)
  love.graphics.circle("line", mid, my, 14)
  love.graphics.setColor(white and 1 or 0.55, white and 1 or 0.38, white and 1 or 0.12)
  for k = 0, 7 do
    local a = t * 0.8 + k * math.pi / 4
    local r = k % 2 == 0 and 12 or 8
    love.graphics.polygon("fill", mid + math.cos(a - 0.2) * 4, my + math.sin(a - 0.2) * 4, mid + math.cos(a) * r, my + math.sin(a) * r, mid + math.cos(a + 0.2) * 4, my + math.sin(a + 0.2) * 4)
  end
  love.graphics.setColor(white and 1 or 0.95, white and 1 or 0.76, white and 1 or 0.3)
  love.graphics.circle("fill", mid, my, 6)
  love.graphics.setColor(1, 0.97, 0.75)
  love.graphics.circle("fill", mid - 1.5, my - 1.5, 3)
end

local function glowGuardian(e)
  local b = e.body
  local mid, my = b.x + b.w / 2, b.y + b.h / 2
  glow.disc(mid, my, 40, { 1, 0.9, 0.5 }, 0.5)
  love.graphics.setColor(1, 1, 0.85, 0.8)
  love.graphics.circle("fill", mid, my, 3)
end

enemies.UPDATE.gildedlens = updateLens
enemies.DRAW.gildedlens = drawLens
enemies.GLOW.gildedlens = glowLens
enemies.UPDATE.cometling = updateComet
enemies.DRAW.cometling = drawComet
enemies.GLOW.cometling = glowComet
enemies.UPDATE.stormcloud = updateCloud
enemies.DRAW.stormcloud = drawCloud
enemies.GLOW.stormcloud = glowCloud
enemies.UPDATE.starguardian = updateGuardian
enemies.DRAW.starguardian = drawGuardian
enemies.GLOW.starguardian = glowGuardian

return true
