-- The Sulfur Queen's spirits (src.enemies calls them in with her "spawn" attack; they live nowhere else):
--   Gas Spirit   a wisp of sulfur gas. It drifts about the hunter; once he is near enough it locks on, brightens
--                and homes in, loosely (it turns slowly, so he can slip it by moving well). On touch it bursts
--                into a cloud of gas, and it bursts on a fuse if it misses. Shot down first, it only leaks a puff.
local enemies = require("src.enemies")
local Body = require("src.body")
local effects = require("src.effects")
local fluids = require("src.fluids")
local glow = require("src.softglow")

local H = enemies.helpers
local center, collider, removePhysics, sfx = H.center, H.collider, H.removePhysics, H.sfx

local LOCK_RANGE = 230 -- how near the hunter must be for it to lock on
local LOCK_TIME = 0.6 -- the brightening before it goes
local CHASE_SPEED = 55 -- (it starts slow and picks up speed all through the chase)
local CHASE_TOP = 165
local TURN_RATE = 1.5 -- radians a second: loose enough to be outrun round
local FUSE = 3.2 -- seconds of chase before it goes off on its own
local BURST_RADIUS = 46

local D = enemies.defs
D.gasspirit = {
  name = "Gas Spirit",
  w = 12, h = 12, hp = 30, speed = 60, accel = 150,
  sight = 900, forget = 3000,
  knockback = 0.6, gold = { 3, 7 }, weight = 0.5,
  spriteW = 12, spriteH = 12, scale = 1,
  blood = { 0.72, 0.85, 0.3 },
  desc = "A wisp of the Queen's own gas. It drifts, then brightens and homes in on you, slowly. Touch it, or let its fuse run out, and it bursts into a cloud. Shoot it first.",
}
enemies.order[#enemies.order + 1] = "gasspirit"
D.gasspirit.knockMul = 0.5
enemies.VOICES.gasspirit = { "wisp_crackle", 3, 8, 0.35 }
-- Shot down it leaks a small puff, nothing more
D.gasspirit.onDeath = function(e)
  local cx, cy = center(e)
  fluids.addGas(cx, cy, 0.5, 12)
end
D.gasspirit.light = function(e)
  local cx, cy = center(e)
  return { cx, cy, e.state == "chase" and 56 or 40, 0.75, 0.95, 0.3, e.state == "lock" and 0.5 or (e.state == "chase" and 0.5 or 0.3) }
end

local function hypot(x, y)
  return math.sqrt(x * x + y * y)
end

local function burst(e)
  local cx, cy = center(e)
  e.dead = true
  removePhysics(e)
  fluids.addGas(cx, cy, 1, BURST_RADIUS)
  effects.ring(cx, cy, 30, { 0.85, 0.95, 0.35 })
  for _ = 1, 14 do
    local a = love.math.random() * math.pi * 2
    local s = 30 + love.math.random() * 70
    effects.particle(cx, cy, math.cos(a) * s, math.sin(a) * s, 0.6, { 0.72, 0.85, 0.3 }, 60, true)
  end
  sfx("explosion", 0.5, 1.2)
end

local function update(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  local cx, cy = center(e)
  local collide = collider(e, world)
  e.phase = e.phase + dt * 5
  e.contactMul = 0
  e.state = e.state == "sleep" and "drift" or e.state
  e.trail = e.trail or {}
  if e.state == "drift" then
    -- about the hunter, over and around him, at a distance
    e.orbA = (e.orbA or love.math.random() * 6.28) + dt * 0.7
    local tx = px + math.cos(e.orbA) * 170
    local ty = py - 90 + math.sin(e.orbA * 1.3) * 50
    local wx, wy = (tx - cx) * 0.8, (ty - cy) * 0.8
    local d = hypot(wx, wy)
    if d > def.speed then
      wx, wy = wx / d * def.speed, wy / d * def.speed
    end
    if e.stun <= 0 then
      local step = def.accel * dt
      b.vx = b.vx < wx and math.min(b.vx + step, wx) or math.max(b.vx - step, wx)
      b.vy = b.vy < wy and math.min(b.vy + step, wy) or math.max(b.vy - step, wy)
    end
    e.lockCd = (e.lockCd or (1.2 + love.math.random() * 1.5)) - dt
    if e.lockCd <= 0 and hypot(px - cx, py - cy) < LOCK_RANGE and e.stun <= 0 then
      e.state, e.timer = "lock", LOCK_TIME
      sfx("bat_screech", 0.35, 1.8)
    end
  elseif e.state == "lock" then
    -- it stops and brightens
    e.timer = e.timer - dt
    b.vx, b.vy = b.vx * math.exp(-7 * dt), b.vy * math.exp(-7 * dt)
    if e.timer <= 0 then
      e.state, e.fuse = "chase", FUSE
      e.heading = math.atan2(py - cy, px - cx)
    end
  elseif e.state == "chase" then
    e.fuse = e.fuse - dt
    -- turns toward the hunter, but only so fast
    local want = math.atan2(py - cy, px - cx)
    local diff = (want - e.heading + math.pi) % (math.pi * 2) - math.pi
    local turn = TURN_RATE * dt
    e.heading = e.heading + math.max(-turn, math.min(turn, diff))
    local sp = (CHASE_SPEED + (CHASE_TOP - CHASE_SPEED) * (1 - e.fuse / FUSE)) * (e.stun > 0 and 0.2 or 1)
    b.vx, b.vy = math.cos(e.heading) * sp, math.sin(e.heading) * sp
    if love.math.random() < dt * 40 then
      effects.particle(cx, cy, (love.math.random() - 0.5) * 16, (love.math.random() - 0.5) * 16, 0.4, { 0.78, 0.95, 0.3 }, 0, true)
    end
    local pb = player.body
    local touch = not player.dead and cx > pb.x - 4 and cx < pb.x + pb.w + 4 and cy > pb.y - 4 and cy < pb.y + pb.h + 4
    if touch or e.fuse <= 0 then
      burst(e)
      return
    end
  end
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.3
    if e.state == "chase" then
      e.heading = math.atan2(py - cy, px - cx) -- (rock turns it round)
    end
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.3
    if e.state == "chase" then
      e.heading = math.atan2(py - cy, px - cx)
    end
  end
  table.insert(e.trail, 1, { cx, cy })
  while #e.trail > 8 do
    table.remove(e.trail)
  end
  e.facing = px >= cx and 1 or -1
end

local function draw(e)
  local b = e.body
  local white = e.flash > 0
  local mid, my = b.x + b.w / 2, b.y + b.h / 2
  local hot = e.state == "chase" and 1 or (e.state == "lock" and 1 - math.max(0, e.timer) / LOCK_TIME or 0)
  for i, p in ipairs(e.trail or {}) do
    local k = 1 - i / 9
    love.graphics.setColor(0.7 + 0.2 * hot, 0.85, 0.3 + 0.3 * hot, 0.35 * k * (0.5 + hot))
    love.graphics.circle("fill", p[1], p[2], 4 * k + 0.5)
  end
  local wob = math.sin(e.phase) * 0.7
  love.graphics.setColor(white and 1 or 0.45 + 0.25 * hot, white and 1 or 0.65 + 0.15 * hot, white and 1 or 0.15 + 0.1 * hot, 0.9)
  love.graphics.circle("fill", mid, my, 5.5 + wob)
  love.graphics.setColor(0.75 + 0.1 * hot, 0.92, 0.4 + 0.2 * hot, 0.95)
  love.graphics.circle("fill", mid - 1, my - 1, 3 - wob * 0.5)
  love.graphics.setColor(0.1, 0.2, 0.05)
  love.graphics.rectangle("fill", math.floor(mid - 2.5), math.floor(my - 1), 1, 1)
  love.graphics.rectangle("fill", math.floor(mid + 1.5), math.floor(my - 1), 1, 1)
  if e.state == "lock" then
    -- a ring closes in as it brightens
    love.graphics.setColor(0.9, 1, 0.5, 0.5 * hot)
    love.graphics.circle("line", mid, my, 14 - 8 * hot)
  end
end

local function glowIt(e)
  local b = e.body
  local hot = e.state == "chase" and 1 or (e.state == "lock" and 0.7 or 0.25)
  glow.disc(b.x + b.w / 2, b.y + b.h / 2, 12 + 8 * hot, { 0.75, 0.95, 0.3 }, 0.3 + 0.2 * hot)
end

enemies.UPDATE.gasspirit = update
enemies.DRAW.gasspirit = draw
enemies.GLOW.gasspirit = glowIt

return true
