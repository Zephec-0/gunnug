-- The Foreman's Hall's boss, rebuilt: the Marble Colossus, twice the size, in
-- rusty orange and gold marble with a detached floating head and fists on
-- chains. It wakes slowly, then swipes, hurls rocks, stomps waves (in
-- repetition), sweeps a fire-trailing beam from its eye and leaps to slam the
-- ground (shaking stalactites loose). Twice it kneels in a crystal shell while
-- golemlings drop from the ceiling; the second time there are more, and it
-- keeps sweeping its beam while they live.
local enemies = require("src.enemies")
local Body = require("src.body")
local audio = require("src.audio")
local config = require("src.config")
local destruction = require("src.destruction")
local effects = require("src.effects")
local fluids = require("src.fluids")

local H = enemies.helpers
local center, collider, sfx = H.center, H.collider, H.sfx

local function hypot(x, y)
  return math.sqrt(x * x + y * y)
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

-- Palette: marble gone to rust and gold
local M = {
  light = { 0.94, 0.85, 0.72 },
  mid = { 0.78, 0.64, 0.48 },
  dark = { 0.54, 0.40, 0.29 },
  deep = { 0.30, 0.20, 0.15 },
  rust = { 0.76, 0.38, 0.14 },
  gold = { 1.0, 0.78, 0.28 },
  glow = { 1.0, 0.55, 0.15 },
}

-- Definitions -------------------------------------------------------------------------------------

local def = enemies.defs.golem
local S = 2 / 3 -- (a third smaller than the first rebuild)
def.w, def.h = math.floor(112 * S), math.floor(168 * S)
def.speed = 30
def.spriteW, def.spriteH = def.w, def.h
def.blood = { 0.9, 0.7, 0.45 }
def.light = function(e)
  local cx, cy = center(e)
  -- (a warm glow over the whole of it, so the bulk can be seen, and its eye)
  local l = { { cx, cy - 10, 150, 1, 0.72, 0.42, 0.2 } }
  if e.eyeX then
    l[2] = { e.eyeX, e.eyeY, e.bm and e.bm.phase == "act" and 120 or 50, 1, 0.55, 0.2, 0.85 }
  end
  return l
end
local mini = enemies.defs.minigolem
mini.light = function(e)
  local cx, cy = center(e)
  return { cx, cy - 4, 20, 1, 0.55, 0.2, 0.35 }
end
mini.blood = { 0.9, 0.7, 0.45 }

local ATTACKS = {
  -- name = { windup, act, recover } in seconds (half of what they were)
  swipe = { 0.33, 0.13, 0.28 },
  throw = { 0.4, 0.1, 0.3 },
  stomp = { 0.48, 0.15, 0.4 },
  beam = { 0.6, 1.1, 0.5 },
  leap = { 0.55, 1.6, 0.6 },
}

-- Projectiles and hazards (rocks it hurls, waves along the floor, stalactites
-- shaken loose, patches of beam fire) -------------------------------------------------------------

local stones, waves, rocks = {}, {}, {}

local function hurt(e, player, dmg, fx, fy)
  if player.dead then
    return false
  end
  if player:isDodging() then
    player:dodged()
    return false
  end
  return player:hurt(math.max(1, math.floor(dmg * e.dmgMul + 0.5)), fx, fy, "golem")
end

local function camShake(k)
  require("src.camera").shake(k)
end

-- The head: a spring, kicked by hits ----------------------------------------------------------

def.filter = function(e, amount)
  if e.hitX then
    local cx = center(e)
    local dir = (e.hitX >= cx) and -1 or 1
    e.headVX = (e.headVX or 0) + dir * math.min(36, 8 + amount * 1.2)
    e.headVY = (e.headVY or 0) - 5
  end
  return amount
end

-- The beam ---------------------------------------------------------------------------------------------

local function beamStart(e, px, py, wind, act)
  local ex, ey = e.eyeX, e.eyeY
  local base = math.atan2(py - ey, px - ex)
  local s = love.math.random() < 0.5 and -1 or 1
  e.bm = { phase = "wind", t = wind, wind = wind, act = act, a0 = base - s * 0.95, a1 = base + s * 0.95, hitT = 0, fireT = 0 }
  e.beamA0, e.beamA1 = e.bm.a0, e.bm.a1
  sfx("bat_screech", 0.5, 0.35)
end

local function beamUpdate(e, dt, world, player)
  local bm = e.bm
  if not bm then
    return
  end
  bm.t = bm.t - dt
  local ex, ey = e.eyeX, e.eyeY
  if bm.phase == "wind" then
    e.charge = 1 - math.max(0, bm.t) / bm.wind
    if bm.t <= 0 then
      bm.phase, bm.t = "act", bm.act
      sfx("explosion", 0.4, 1.6)
      camShake(0.3)
    end
  elseif bm.phase == "act" then
    local k = 1 - math.max(0, bm.t) / bm.act
    bm.ang = bm.a0 + (bm.a1 - bm.a0) * k
    local dx, dy = math.cos(bm.ang), math.sin(bm.ang)
    local len = 0
    while len < 1000 do
      len = len + 3
      if world:isSolid(math.floor(ex + dx * len), math.floor(ey + dy * len)) then
        break
      end
    end
    e.beamEnd = { ex + dx * len, ey + dy * len }
    -- the screen warps while it burns
    require("src.render").warpFrame(1)
    camShake(0.12)
    bm.hitT = bm.hitT - dt
    local pcx, pcy = player:center()
    local u = math.max(0, math.min(len, (pcx - ex) * dx + (pcy - ey) * dy))
    local ddx, ddy = pcx - (ex + dx * u), pcy - (ey + dy * u)
    if ddx * ddx + ddy * ddy < 100 and bm.hitT <= 0 then
      bm.hitT = 0.4
      hurt(e, player, e.def.damage * 0.8, ex, ey)
    end
    -- where it lands it sets the ground alight: a trail of fire behind the sweep
    bm.fireT = bm.fireT - dt
    if bm.fireT <= 0 and len < 995 then
      bm.fireT = 0.07
      fluids.ignite(e.beamEnd[1] - dx * 3, e.beamEnd[2] - dy * 3, 2)
    end
    if love.math.random() < dt * 60 then
      effects.particle(e.beamEnd[1], e.beamEnd[2], (love.math.random() - 0.5) * 100, -30 - love.math.random() * 70, 0.4, { 1, 0.6, 0.2 }, 200, true)
    end
    if bm.t <= 0 then
      e.bm, e.beamEnd, e.charge = nil, nil, nil
    end
  end
end

-- Attacks ---------------------------------------------------------------------------------------------

local function beginAttack(e, name, px, py)
  local t = ATTACKS[name]
  e.gs, e.sub, e.gt, e.gd = name, "wind", t[1], t[1]
  e.last = name
  if name == "beam" then
    beamStart(e, px, py, t[1], t[2])
  elseif name == "stomp" or name == "leap" then
    sfx("explosion", 0.3, 0.4)
  end
end

-- Stalactites shaken loose from the ceiling: a rain at random
local function shakeStalactites(e, n, world)
  local a = e.arena
  if not a then
    return
  end
  for _ = 1, n do
    local x = a.x0 + 30 + love.math.random() * (a.x1 - a.x0 - 60)
    local fl = world and world:findGround(math.floor(x), math.floor(a.top + 20)) or a.floorY
    local delay = 0.9 + love.math.random() * 1.1
    rocks[#rocks + 1] = { x = x, y = a.top + 4, vy = 0, delay = delay, wait = delay, floor = fl, dmg = e.def.damage * 0.6, size = 7 + love.math.random() * 5 }
  end
end

local function groundSlam(e, world, player, power)
  local b = e.body
  local cx = center(e)
  local fy = b.y + b.h
  destruction.dig(world, cx, fy, 20 * power, 3.5, 0, -1)
  destruction.dig(world, cx - 22, fy, 9, 3, 0, -1)
  destruction.dig(world, cx + 22, fy, 9, 3, 0, -1)
  sfx("explosion", 1, 0.5)
  camShake(1.0)
  require("src.render").warpFrame(0.6)
  effects.ring(cx, fy - 6, 90, { 1, 0.7, 0.35 })
  for _ = 1, 30 do
    effects.particle(cx + (love.math.random() - 0.5) * 90, fy - 2, (love.math.random() - 0.5) * 240, -60 - love.math.random() * 200, 0.7, { 0.8, 0.62, 0.42 }, 500)
  end
  local pb = player.body
  if not player.dead and math.abs(pb.x + pb.w / 2 - cx) < 90 and pb.y + pb.h > fy - 30 then
    if hurt(e, player, e.def.damage * 0.9, cx, fy) then
      pb.vy = -240
      pb.vx = ((pb.x + pb.w / 2 < cx) and -1 or 1) * 160
    end
  end
end

local function act(e, world, player, px, py, stage)
  local b = e.body
  local f = e.facing
  local cx, cy = center(e)
  local d = e.def
  if e.gs == "swipe" then
    sfx("hit", 0.9, 0.4)
    b.vx = f * 90
    local x0, x1 = cx + f * 16 * S, cx + f * (b.w / 2 + 120 * S)
    local pb = player.body
    if overlaps(math.min(x0, x1), b.y + 30 * S, math.abs(x1 - x0), b.h - 30 * S, pb.x, pb.y, pb.w, pb.h) then
      if hurt(e, player, d.damage, cx, cy) then
        pb.vx, pb.vy = f * 280, -170
      end
    end
    camShake(0.3)
    for i = 1, 10 do
      effects.particle(cx + f * (30 + i * 10), b.y + b.h - 6, f * 50, -20 - love.math.random() * 50, 0.5, { 0.8, 0.62, 0.42 }, 300)
    end
  elseif e.gs == "throw" then
    sfx("hit", 0.7, 0.5)
    local n = stage + 1
    local sx, sy = cx + f * 34 * S, b.y + 20 * S
    local T = math.max(0.6, math.min(1.1, math.abs(px - sx) / 280))
    for i = 1, n do
      local aim = px + (i - (n + 1) / 2) * 50
      stones[#stones + 1] = { x = sx, y = sy, vx = (aim - sx) / T, vy = (py - sy) / T - 0.5 * 520 * T, life = 4, spin = love.math.random() * 6, dmg = d.damage * 0.75, kind = love.math.random(1, 3) }
    end
  elseif e.gs == "stomp" then
    sfx("explosion", 0.8, 0.4)
    camShake(0.6)
    local dirs = { (px < cx) and -1 or 1 }
    if stage >= 2 then
      dirs[2] = -dirs[1]
    end
    for _, dd in ipairs(dirs) do
      waves[#waves + 1] = { x = cx + dd * 60 * S, dir = dd, speed = 190 + 30 * stage, life = 3, hit = false, dmg = d.damage }
    end
    for _ = 1, 20 do
      effects.particle(cx + (love.math.random() - 0.5) * 100, b.y + b.h - 2, (love.math.random() - 0.5) * 140, -40 - love.math.random() * 90, 0.6, { 0.8, 0.62, 0.42 }, 400)
    end
  elseif e.gs == "leap" then
    sfx("hit", 0.8, 0.3)
    b.vy = -300
    b.vx = (px < cx and -1 or 1) * math.min(110, math.abs(px - cx) * 0.6)
    e.leapAir = true
    e.grounded = false
  end
end

-- Helpers fall from the ceiling ---------------------------------------------------------------------

local function spawnMinis(e, n)
  e.minisLeft = n
  e.miniT = 0.2
  e.minis = e.minis or {}
end

local function startShell(e, n)
  e.gs, e.sub, e.gt = "shell", nil, 0
  e.invuln, e.vulnerable = true, false
  e.body.vx = 0
  e.bm, e.beamEnd = nil, nil
  e.shellBeamCd = 3.5
  sfx("explosion", 0.8, 0.45)
  local cx, cy = center(e)
  effects.ring(cx, cy, 120, { 1, 0.7, 0.3 })
  effects.popup(cx, e.body.y - 10, "SHELL", { 1, 0.75, 0.3 })
  camShake(0.6)
  spawnMinis(e, n)
end

local function dropMini(e, world)
  local a = e.arena
  local m
  for _ = 1, 12 do
    local x = (a and a.x0 + 50 or e.body.x - 300) + love.math.random() * ((a and a.x1 - a.x0 - 100) or 600)
    local y = (a and a.top + 14 or e.body.y - 200) + enemies.defs.minigolem.h
    if not Body.terrainOverlaps(world, x - 8, y - 22, 16, 22) then
      m = enemies.spawn("minigolem", x, y, 1, e.level)
      effects.ring(x, y - 10, 14, { 1, 0.7, 0.3 })
      break
    end
  end
  if m then
    m.state = "chase"
    m.seesPlayer = true
    m.falling = true
    e.minis[#e.minis + 1] = m
    sfx("clank", 0.5, 0.6)
  end
end

-- The Colossus -----------------------------------------------------------------------------------------

local function updateGolem(e, dt, world, player, px, py)
  local def2, b = e.def, e.body
  local collide = collider(e, world)
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  local a = e.arena
  e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
  local frac = e.hp / e.maxHp
  local stage = frac > 0.66 and 1 or (frac > 0.33 and 2 or 3)

  -- The floating head, on a spring: it trails and answers knocks
  e.headX, e.headY = e.headX or 0, e.headY or 0
  e.headVX, e.headVY = e.headVX or 0, e.headVY or 0
  local bob = math.sin(love.timer.getTime() * 1.8 + e.phase) * 3
  local drop = (e.invuln and 34 or 0) + (e.gs == "rise" and 40 or 0) + (e.gs == "rest" and 18 or 0)
  local wantX, wantY = 0, bob + drop - (e.sub == "wind" and e.gs ~= "walk" and 8 or 0)
  e.headVX = e.headVX + (wantX - e.headX) * 90 * dt - e.headVX * 9 * dt
  e.headVY = e.headVY + (wantY - e.headY) * 90 * dt - e.headVY * 9 * dt
  e.headX, e.headY = e.headX + e.headVX * dt, e.headY + e.headVY * dt
  local hx, hy = cx + (e.facing * 6 + e.headX) * S, b.y + (34 + e.headY) * S
  e.eyeX, e.eyeY = hx + e.facing * 15 * S, hy + 2 * S
  e.headPos = { hx, hy }

  if e.state == "idle" or e.state == "sleep" then
    local inside = not a or (px > a.x0 and px < a.x1 and py > a.top and py < a.floorY)
    if inside and dist < def2.sight then
      e.state, e.gs, e.gt = "chase", "rise", 2.6
      sfx("explosion", 0.7, 0.35)
    else
      b.vy = math.min(b.vy + config.gravity * dt, 450)
      if Body.moveY(b, collide, b.vy * dt) then
        b.vy = 0
      end
      return
    end
  end
  if not e.gs then
    e.gs, e.gt = "rise", 2.6
    sfx("explosion", 0.7, 0.35)
  end
  e.gt = (e.gt or 1) - dt
  e.minis = e.minis or {}
  beamUpdate(e, dt, world, player)

  if e.gs ~= "shell" and e.gs ~= "rise" and not e.shell1 and frac < 0.66 then
    e.shell1 = true
    startShell(e, 4)
  elseif e.gs ~= "shell" and e.gs ~= "rise" and not e.shell2 and frac < 0.33 then
    e.shell2 = true
    startShell(e, 7)
  end

  local want = 0
  local speed = def2.speed * (1 + 0.25 * (stage - 1))
  if e.gs == "rise" then
    -- Dormant stone coming awake: dust, shaking, then the eyes
    e.invuln = false
    e.facing = px < cx and -1 or 1
    if love.math.random() < dt * 30 then
      effects.particle(cx + (love.math.random() - 0.5) * b.w, b.y + 20, (love.math.random() - 0.5) * 30, 20 + love.math.random() * 40, 0.8, { 0.8, 0.62, 0.42 }, 200)
    end
    if e.gt > 0 and love.math.random() < dt * 4 then
      camShake(0.15)
    end
    if e.gt <= 0 then
      e.gs, e.gt = "walk", 0.5
      sfx("bat_screech", 0.8, 0.3)
      camShake(0.7)
      effects.ring(cx, cy, 120, { 1, 0.7, 0.3 })
    end
  elseif e.gs == "shell" then
    e.facing = px < cx and -1 or 1
    if (e.minisLeft or 0) > 0 then
      e.miniT = e.miniT - dt
      if e.miniT <= 0 then
        e.miniT = 0.7
        e.minisLeft = e.minisLeft - 1
        dropMini(e, world)
      end
    end
    local alive = 0
    for _, m in ipairs(e.minis) do
      if not m.dead then
        alive = alive + 1
      end
    end
    -- the second shell: it keeps sweeping its beam while the little ones live
    if e.shell2 and alive > 0 or (e.shell2 and (e.minisLeft or 0) > 0) then
      e.shellBeamCd = (e.shellBeamCd or 3) - dt
      if e.shellBeamCd <= 0 and not e.bm then
        e.shellBeamCd = 4.5
        beamStart(e, px, py, 0.7, 1.4)
      end
    end
    if (e.minisLeft or 0) <= 0 and alive == 0 then
      e.invuln = false
      e.gs, e.gt = "rest", 2.2
      e.vulnerable = true
      e.bm, e.beamEnd = nil, nil
      sfx("explosion", 0.9, 0.55)
      camShake(0.6)
      effects.ring(cx, cy, 130, { 1, 0.8, 0.4 })
      effects.popup(cx, b.y - 10, "SHELL BROKEN", { 1, 0.9, 0.6 })
      for _ = 1, 30 do
        effects.particle(cx + (love.math.random() - 0.5) * 100, cy + (love.math.random() - 0.5) * 140, (love.math.random() - 0.5) * 180, -love.math.random() * 140, 0.8, { 1, 0.7, 0.3 }, 300, true)
      end
    end
  elseif e.gs == "rest" then
    e.vulnerable = true
    if e.gt <= 0 then
      e.vulnerable = false
      e.gs, e.gt = "walk", 0.5
    end
  elseif e.gs == "walk" then
    e.facing = px < cx and -1 or 1
    local dx = px - cx
    if math.abs(dx) > 60 then
      want = e.facing
    end
    if e.gt <= 0 and e.grounded then
      local near = math.abs(dx) < 120 and math.abs(py - cy) < 90
      local pool = near and { "swipe", "swipe", "stomp", "stomp", "leap", "throw", "beam" } or { "throw", "stomp", "stomp", "stomp", "beam", "leap", "leap" }
      -- the slam comes again and again: a chain of stomps
      if e.last == "stomp" and (e.chain or 0) < 2 and love.math.random() < 0.55 then
        e.chain = (e.chain or 0) + 1
        beginAttack(e, "stomp", px, py)
      else
        e.chain = 0
        for _ = 1, 4 do
          local pick = pool[love.math.random(#pool)]
          if pick ~= e.last then
            beginAttack(e, pick, px, py)
            break
          end
        end
      end
      if e.gs == "walk" then
        e.gt = 0.3
      end
    end
  else
    local t = ATTACKS[e.gs]
    if e.sub == "wind" then
      e.facing = px < cx and -1 or 1
      if e.gt <= 0 then
        e.sub, e.gt, e.gd = "act", t[2], t[2]
        e.actAt = true
      end
    elseif e.sub == "act" then
      if e.actAt then
        e.actAt = false
        act(e, world, player, px, py, stage)
      end
      if e.gs == "beam" then
        if not e.bm then
          e.sub, e.gt, e.gd = "rec", t[3], t[3]
        end
      elseif e.gs == "leap" then
        if e.leapAir and e.grounded and b.vy >= 0 and e.gt < t[2] - 0.15 then
          e.leapAir = false
          groundSlam(e, world, player, 1)
          shakeStalactites(e, (6 + stage * 2) * 3, world)
          e.sub, e.gt, e.gd = "rec", t[3], t[3]
        elseif e.gt <= 0 then
          e.leapAir = false
          e.sub, e.gt, e.gd = "rec", t[3], t[3]
        end
      elseif e.gt <= 0 then
        e.sub, e.gt, e.gd = "rec", t[3], t[3]
      end
    elseif e.sub == "rec" then
      if e.gt <= 0 then
        e.gs, e.sub = "walk", nil
        e.gt = ((e.last == "stomp" and (e.chain or 0) < 2) and 0.25 or (stage == 1 and 0.9 or (stage == 2 and 0.65 or 0.45))) + love.math.random() * 0.3
      end
    end
  end

  if e.grounded then
    local target = want * speed
    local step = 260 * dt
    if e.gs == "leap" and e.sub == "wind" then
      target = 0
    end
    b.vx = b.vx < target and math.min(b.vx + step, target) or math.max(b.vx - step, target)
    if want == 0 then
      b.vx = b.vx * math.max(0, 1 - 6 * dt)
    end
  end
  b.vy = math.min(b.vy + config.gravity * dt, 450)
  if Body.moveX(b, collide, b.vx * dt, 8) then
    b.vx = 0
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = 0
  end
  if e.grounded and b.vy >= 0 and not e.leapAir then
    Body.snapDown(b, collide, 4)
  end
  if a then
    b.x = math.max(a.x0 + 6, math.min(a.x1 - b.w - 6, b.x))
  end
  local step = math.floor(e.phase / math.pi)
  e.phase = e.phase + dt * (math.abs(b.vx) / 14 + 0.5)
  if e.grounded and math.abs(b.vx) > 8 and math.floor(e.phase / math.pi) ~= step then
    sfx("hit", 0.3, 0.25)
    camShake(0.12)
    effects.particle(cx + (love.math.random() - 0.5) * 50, b.y + b.h - 1, 0, -10 - love.math.random() * 20, 0.4, { 0.7, 0.55, 0.4 }, 100)
  end
end

-- Thrown rocks, floor waves, falling stalactites ---------------------------------------------------

function enemies.golemShots(dt, world, player)
  local pb = player.body
  for i = #stones, 1, -1 do
    local s = stones[i]
    s.life = s.life - dt
    s.vy = s.vy + 520 * dt
    s.spin = s.spin + dt * 9
    local steps = math.max(1, math.ceil(math.max(math.abs(s.vx), math.abs(s.vy)) * dt / 2))
    local gone = false
    for _ = 1, steps do
      s.x, s.y = s.x + s.vx * dt / steps, s.y + s.vy * dt / steps
      if not player.dead and overlaps(s.x - 6, s.y - 6, 12, 12, pb.x, pb.y, pb.w, pb.h) then
        if player:isDodging() then
          player:dodged()
        else
          player:hurt(math.max(1, math.floor(s.dmg + 0.5)), s.x - s.vx * 0.01, s.y, "golem")
          gone = true
        end
      elseif world:isSolid(math.floor(s.x), math.floor(s.y)) then
        gone = true
      end
      if gone then
        break
      end
    end
    if love.math.random() < dt * 30 then
      effects.particle(s.x, s.y, (love.math.random() - 0.5) * 20, -10, 0.3, { 1, 0.6, 0.2 }, 0, true)
    end
    if gone or s.life <= 0 then
      audio.playAt("hit", s.x, s.y, 0.6, 0.5)
      for _ = 1, 12 do
        effects.particle(s.x, s.y, (love.math.random() - 0.5) * 160, -love.math.random() * 110, 0.6, { 0.85, 0.65, 0.42 }, 400)
      end
      table.remove(stones, i)
    end
  end
  for i = #waves, 1, -1 do
    local w = waves[i]
    w.life = w.life - dt
    w.x = w.x + w.dir * w.speed * dt
    w.y = world:findGround(math.floor(w.x), math.floor((w.y or pb.y) - 40))
    local blocked = world:isSolid(math.floor(w.x + w.dir * 5), math.floor(w.y - 8))
    if not w.hit and not player.dead and overlaps(w.x - 9, w.y - 24, 18, 24, pb.x, pb.y, pb.w, pb.h) then
      if player:isDodging() then
        player:dodged()
      else
        w.hit = true
        if player:hurt(math.max(1, math.floor(w.dmg + 0.5)), w.x - w.dir * 8, w.y - 6, "golem") then
          pb.vy = -240
          pb.vx = w.dir * 130
        end
      end
    end
    if love.math.random() < dt * 50 then
      effects.particle(w.x, w.y - 2, (love.math.random() - 0.5) * 40, -40 - love.math.random() * 60, 0.4, { 0.85, 0.65, 0.42 }, 300)
    end
    if w.life <= 0 or blocked then
      table.remove(waves, i)
    end
  end
  for i = #rocks, 1, -1 do
    local r = rocks[i]
    if r.delay > 0 then
      r.delay = r.delay - dt
      if love.math.random() < dt * 25 then
        effects.particle(r.x + (love.math.random() - 0.5) * 8, r.y + 2, 0, 20 + love.math.random() * 20, 0.5, { 0.8, 0.62, 0.42 }, 100)
      end
    else
      r.vy = r.vy + 620 * dt
      r.y = r.y + r.vy * dt
      local gone = world:isSolid(math.floor(r.x), math.floor(r.y + r.size)) and r.y > (r.y0 or 0) + 6
      if not r.y0 then
        r.y0 = r.y
      end
      if not player.dead and overlaps(r.x - r.size / 2, r.y - r.size, r.size, r.size * 2, pb.x, pb.y, pb.w, pb.h) then
        if player:isDodging() then
          player:dodged()
        else
          player:hurt(math.max(1, math.floor(r.dmg + 0.5)), r.x, r.y - 20, "golem")
          gone = true
        end
      end
      if gone or r.y > r.y0 + 900 then
        audio.playAt("hit", r.x, r.y, 0.5, 0.45)
        for _ = 1, 8 do
          effects.particle(r.x, r.y, (love.math.random() - 0.5) * 120, -love.math.random() * 90, 0.5, { 0.8, 0.62, 0.42 }, 400)
        end
        table.remove(rocks, i)
      end
    end
  end
end

-- Drawing ------------------------------------------------------------------------------------------------

local function poly(c, a, ...)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.polygon("fill", ...)
end

local function chain(x0, y0, x1, y1)
  local d = hypot(x1 - x0, y1 - y0)
  local n = math.max(1, math.floor(d / 7))
  for i = 1, n - 1 do
    local t = i / n
    local x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t + math.sin(t * math.pi) * 3
    love.graphics.setColor(M.deep[1], M.deep[2], M.deep[3])
    love.graphics.rectangle("fill", math.floor(x) - 1, math.floor(y) - 1, 4, 3)
    love.graphics.setColor(M.gold[1] * 0.7, M.gold[2] * 0.7, M.gold[3] * 0.5)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y) - 1, 2, 1)
  end
end

local function crystal(x, y, w, h, tilt, col)
  poly(col, 1, x - w / 2, y, x + w / 2, y, x + tilt, y - h)
  poly({ math.min(1, col[1] + 0.25), math.min(1, col[2] + 0.25), math.min(1, col[3] + 0.2) }, 1, x - w / 2, y, x, y, x + tilt, y - h)
end

-- A fist: a block of marble with three claw-fingers and a gold band
local function fist(x, y, f, flash, open, scale)
  scale = scale or 1
  local function C(c)
    return flash and { 1, 1, 1 } or c
  end
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(f * scale, scale)
  poly(C(M.dark), 1, -14, -12, 12, -14, 16, 8, -10, 14)
  poly(C(M.mid), 1, -14, -12, 12, -14, 10, -4, -12, -2)
  poly(C(M.deep), 1, 12, -14, 16, 8, 10, 6)
  poly(C(M.gold), 1, -12, 0, 14, -1, 14, 3, -12, 4)
  for i = 0, 2 do
    local fy = -9 + i * 9
    local spread = open and 6 or 0
    poly(C(M.rust), 1, 14, fy, 28, fy + 6 + (i - 1) * spread, 24, fy + 10 + (i - 1) * spread, 13, fy + 7)
    poly(C(M.light), 1, 24, fy + 8 + (i - 1) * spread, 30, fy + 14 + (i - 1) * spread, 25, fy + 10 + (i - 1) * spread)
  end
  love.graphics.pop()
end

local function pose(e)
  -- Where the fists are, in the torso's frame (x forward), and how far the body drops
  local gs, sub = e.gs, e.sub
  local k = 0
  if e.gt and e.gd and e.gd > 0 then
    k = 1 - math.max(0, e.gt) / e.gd
  end
  local p = { fx = 62, fy = 46, bx = -58, by = 40, drop = 0, open = false }
  local sway = math.sin(e.phase * 2) * 3
  p.fy, p.by = p.fy + sway, p.by - sway
  if gs == "swipe" then
    if sub == "wind" then
      p.fx, p.fy = -50 + k * 20, -20 - k * 10
    elseif sub == "act" then
      p.fx, p.fy = -30 + k * 150, 0 + k * 10
      p.open = true
    else
      p.fx, p.fy = 100 - k * 40, 10 + k * 30
    end
  elseif gs == "stomp" then
    if sub == "wind" then
      p.fx, p.fy, p.bx, p.by = 50, -90 * k - 20, -50, -90 * k - 20
    elseif sub == "act" then
      p.fx, p.fy, p.bx, p.by = 60, 80, -60, 80
      p.drop = 8
    else
      p.fx, p.fy, p.bx, p.by = 60, 78 - k * 30, -60, 78 - k * 30
      p.drop = 8 * (1 - k)
    end
  elseif gs == "throw" then
    if sub == "wind" then
      p.fx, p.fy = 40 - k * 20, -70 - k * 20
    else
      p.fx, p.fy = 70, -60 + k * 60
    end
  elseif gs == "beam" then
    p.fx, p.fy, p.bx, p.by = 96, 20, -96, 20
    p.open = true
  elseif gs == "leap" then
    if sub == "wind" then
      p.fx, p.fy, p.bx, p.by = 70, 70, -70, 70
      p.drop = 24 * k
    elseif e.leapAir then
      p.fx, p.fy, p.bx, p.by = 60, -80, -60, -80
    else
      p.fx, p.fy, p.bx, p.by = 66, 82, -66, 82
      p.drop = 10
    end
  elseif gs == "shell" then
    p.fx, p.fy, p.bx, p.by = 40, 70, -40, 70
    p.drop = 40
  elseif gs == "rest" then
    p.fx, p.fy, p.bx, p.by = 50, 86, -50, 86
    p.drop = 28
  elseif gs == "rise" then
    p.fx, p.fy, p.bx, p.by = 40, 86, -40, 86
    p.drop = 40 * (e.gt and math.max(0, e.gt) / 2.6 or 0)
  end
  return p
end

local function drawGolem(e)
  if not e.headPos then
    -- (a portrait, not in the fight: the head where it floats when it stands at rest)
    local cx = e.body.x + e.body.w / 2
    local f = e.facing or 1
    local hx, hy = cx + f * 6 * S, e.body.y + 34 * S
    e.headPos = { hx, hy }
    e.eyeX, e.eyeY = hx + f * 15 * S, hy + 2 * S
  end
  local rb = e.body
  local rcx, rground = rb.x + rb.w / 2, rb.y + rb.h
  -- (drawn at full size in a frame scaled about its feet)
  local b = { x = rcx - 56, y = rground - 168, w = 112, h = 168 }
  love.graphics.push()
  love.graphics.translate(rcx, rground)
  love.graphics.scale(S)
  love.graphics.translate(-rcx, -rground)
  local cx = b.x + b.w / 2
  local f = e.facing or 1
  local flash = e.flash > 0
  local t = love.timer.getTime()
  local p = pose(e)
  local walk = (e.grounded and math.abs(rb.vx) > 4) and math.sin(e.phase * 1.5) or 0
  local function C(c)
    return flash and { 1, 1, 1 } or c
  end
  local ty = b.y + 98 + p.drop -- the torso's centre
  local legTop = ty + 46
  local ground = b.y + b.h
  love.graphics.push()
  love.graphics.translate(cx, 0)
  love.graphics.scale(f, 1)
  -- the back fist and its chain
  local bsx, bsy = -30, ty - 34
  local bfx, bfy = p.bx, ty + p.by - 34
  chain(bsx, bsy, bfx, bfy)
  love.graphics.push()
  love.graphics.scale(-1, 1)
  love.graphics.pop()
  fist(bfx, bfy, -1, flash, p.open, 0.95)
  -- legs: two blocks floating under the torso, joined by chains, walking in turn
  for side = -1, 1, 2 do
    local lw = side * 15
    local lift = (side == 1 and math.max(0, walk) or math.max(0, -walk)) * 8
    local ly = ground - 38 - lift
    if ly > legTop + 6 then
      chain(lw, legTop - 4, lw, ly + 2)
    end
    poly(C(M.dark), 1, lw - 15, ly, lw + 15, ly, lw + 17, ly + 38, lw - 17, ly + 38)
    poly(C(M.mid), 1, lw - 15, ly, lw + 15, ly, lw + 12, ly + 8, lw - 13, ly + 10)
    poly(C(M.deep), 1, lw + 8, ly + 6, lw + 17, ly + 38, lw + 3, ly + 38)
    poly(C(M.gold), 1, lw - 17, ly + 26, lw + 17, ly + 26, lw + 17, ly + 30, lw - 17, ly + 30)
  end
  -- the torso: a great cracked slab, veined with gold, with crystals on the shoulders
  poly(C(M.deep), 1, -42, ty - 46, -20, ty - 60, 20, ty - 60, 42, ty - 46, 48, ty + 4, 20, ty + 54, -20, ty + 54, -48, ty + 4)
  poly(C(M.mid), 1, -38, ty - 44, -18, ty - 56, 18, ty - 56, 38, ty - 44, 42, ty + 2, 17, ty + 48, -17, ty + 48, -42, ty + 2)
  poly(C(M.light), 1, -38, ty - 44, -18, ty - 56, 18, ty - 56, 38, ty - 44, 30, ty - 28, -30, ty - 28)
  poly(C(M.dark), 1, 14, ty - 10, 42, ty + 2, 17, ty + 48, 5, ty + 42)
  -- cracks, gold in them
  love.graphics.setLineWidth(1)
  local cracks = {
    { -20, ty - 28, -8, ty - 6, -16, ty + 14, -4, ty + 38 },
    { 12, ty - 40, 6, ty - 14, 20, ty + 6, 12, ty + 30 },
    { -36, ty - 4, -24, ty + 4, -30, ty + 26 },
  }
  local vp = 0.6 + 0.3 * math.sin(t * 2 + e.phase)
  for _, c in ipairs(cracks) do
    love.graphics.setColor(M.deep[1], M.deep[2], M.deep[3])
    love.graphics.line(c)
    local gc = flash and { 1, 1, 1 } or { M.gold[1], M.gold[2], M.gold[3] }
    love.graphics.setColor(gc[1], gc[2], gc[3], 0.8 * vp)
    local shifted = {}
    for i = 1, #c, 2 do
      shifted[#shifted + 1], shifted[#shifted + 2] = c[i] + 1, c[i + 1]
    end
    love.graphics.line(shifted)
  end
  -- a gold belt, and rust stains
  poly(C(M.gold), 1, -20, ty + 32, 20, ty + 32, 18, ty + 38, -18, ty + 38)
  poly(C(M.rust), 0.7, -14, ty - 20, 6, ty - 22, 2, ty - 8, -10, ty - 6)
  -- shoulder crystals, rusty orange with lit faces
  for side = -1, 1, 2 do
    local sxx = side * 32
    crystal(sxx - side * 10, ty - 48, 12, 34, side * 3, C(M.rust))
    crystal(sxx, ty - 46, 14, 46, side * 6, C(M.glow))
    crystal(sxx + side * 10, ty - 42, 10, 26, side * 9, C(M.rust))
  end
  -- the front fist, last: it is what swings
  local fsx, fsy = 34, ty - 34
  local ffx, ffy = p.fx, ty + p.fy - 34
  chain(fsx, fsy, ffx, ffy)
  fist(ffx, ffy, 1, flash, p.open, 1.1)
  love.graphics.pop()
  -- the head floats free of the body, trailing and answering knocks
  local hx, hy = rcx + (e.headPos[1] - rcx) / S, rground + (e.headPos[2] - rground) / S
  love.graphics.push()
  love.graphics.translate(hx, hy)
  love.graphics.scale(f, 1)
  local hv = e.invuln and 0 or 1
  poly(C(M.deep), 1, -22, -4, -14, -22, 14, -22, 24, -4, 22, 16, 8, 24, -10, 24, -22, 14)
  poly(C(M.mid), 1, -20, -4, -12, -20, 12, -20, 22, -4, 20, 12, 6, 20, -8, 20, -20, 10)
  poly(C(M.light), 1, -20, -4, -12, -20, 12, -20, 10, -10, -10, -10)
  poly(C(M.dark), 1, 6, 6, 20, 12, 6, 20, -2, 14)
  -- a crown of gold and crystal horns
  poly(C(M.gold), 1, -16, -20, 16, -20, 14, -15, -14, -15)
  crystal(-10, -20, 8, 20, -3, C(M.rust))
  crystal(0, -20, 9, 28, 0, C(M.glow))
  crystal(10, -20, 8, 20, 3, C(M.rust))
  -- the brow and a heavy jaw
  poly(C(M.deep), 1, 0, -2, 22, -4, 22, 2, 0, 3)
  love.graphics.pop()
  -- the crystal shell, when it kneels
  if e.invuln then
    local pulse = 0.7 + 0.2 * math.sin(t * 5)
    love.graphics.setColor(1, 0.65, 0.25, 0.3 * pulse)
    love.graphics.polygon("fill", cx - 66, ground, cx - 52, b.y + 60, cx - 20, b.y + 32, cx + 20, b.y + 32, cx + 52, b.y + 60, cx + 66, ground)
    love.graphics.setColor(1, 0.85, 0.5, 0.7 * pulse)
    love.graphics.polygon("line", cx - 66, ground, cx - 52, b.y + 60, cx - 20, b.y + 32, cx + 20, b.y + 32, cx + 52, b.y + 60, cx + 66, ground)
  end
  love.graphics.pop()
end

local function drawGolemGlow(e)
  local t = love.timer.getTime()
  if not e.eyeX then
    return
  end
  local ex, ey = e.eyeX, e.eyeY
  local rise = e.gs == "rise" and e.gt and e.gt > 1.4
  local charging = e.bm and e.bm.phase == "wind"
  local pulse = 0.7 + 0.3 * math.sin(t * (charging and 30 or 5))
  if not rise then
    local s = charging and 7 + 6 * (e.charge or 0) or 5
    love.graphics.setColor(1, 0.5, 0.15, 0.35 * pulse)
    love.graphics.rectangle("fill", math.floor(ex - s), math.floor(ey - s), s * 2 + 1, s * 2 + 1)
    love.graphics.setColor(1, 0.75, 0.3, pulse)
    love.graphics.rectangle("fill", math.floor(ex - 2), math.floor(ey - 2), 5, 5)
    love.graphics.setColor(1, 1, 0.85)
    love.graphics.rectangle("fill", math.floor(ex), math.floor(ey), 1, 1)
    -- the other eye, behind
    love.graphics.setColor(1, 0.55, 0.2, 0.7 * pulse)
    love.graphics.rectangle("fill", math.floor(ex - (e.facing or 1) * 14 - 1), math.floor(ey - 1), 3, 3)
  end
  -- gold in the cracks glows brighter as it winds up
  if e.gs ~= "rise" then
    local b = e.body
    local cx = b.x + b.w / 2
    local vp = (0.25 + 0.2 * math.sin(t * 2.2)) + (e.sub == "wind" and 0.3 or 0)
    love.graphics.setColor(1, 0.7, 0.25, vp * (e.invuln and 0.5 or 1))
    for k = 0, 9 do
      local vx = cx + (k - 4.5) * 8 * S
      local vy = b.y + (80 + (k * 37 % 50)) * S
      love.graphics.rectangle("fill", math.floor(vx), math.floor(vy), 3, 2)
    end
  end
  if charging and e.bm.a0 then
    for _, ang in ipairs({ e.bm.a0, e.bm.a1 }) do
      for d = 14, 560, 9 do
        if math.floor(t * 14 + d / 9) % 2 == 0 then
          love.graphics.setColor(1, 0.7, 0.2, 0.45)
          love.graphics.rectangle("fill", math.floor(ex + math.cos(ang) * d), math.floor(ey + math.sin(ang) * d), 2, 2)
        end
      end
    end
  end
  if e.beamEnd then
    local x1, y1 = e.beamEnd[1], e.beamEnd[2]
    local len = hypot(x1 - ex, y1 - ey)
    for d = 0, len, 2 do
      local f = d / len
      local x, y = ex + (x1 - ex) * f, ey + (y1 - ey) * f
      love.graphics.setColor(1, 0.45, 0.1, 0.35)
      love.graphics.rectangle("fill", math.floor(x) - 4, math.floor(y) - 4, 9, 9)
      love.graphics.setColor(1, 0.8, 0.4, 0.85)
      love.graphics.rectangle("fill", math.floor(x) - 1, math.floor(y) - 1, 3, 3)
      love.graphics.setColor(1, 1, 0.9)
      love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 1)
    end
    love.graphics.setColor(1, 0.85, 0.5, 0.7)
    love.graphics.rectangle("fill", math.floor(x1) - 5, math.floor(y1) - 5, 11, 11)
  end
end

-- The golemlings: small, rust and gold, with crystal spines; arms thrown up as they fall
local function drawMini(e)
  local b = e.body
  local x, y = math.floor(b.x), math.floor(b.y)
  local f = e.facing or 1
  local flash = e.flash > 0
  local function C(c)
    return flash and { 1, 1, 1 } or c
  end
  local air = not e.grounded
  local w = e.grounded and math.abs(b.vx) > 4 and math.sin(e.phase * 1.5) or 0
  local strike = (e.strikeT or 0) > 0
  love.graphics.push()
  love.graphics.translate(x + 7, y)
  love.graphics.scale(f, 1)
  -- legs
  poly(C(M.dark), 1, -5, 13, -1, 13, -1, 20 - math.max(0, w) * 2, -5, 20 - math.max(0, w) * 2)
  poly(C(M.dark), 1, 1, 13, 5, 13, 5, 20 - math.max(0, -w) * 2, 1, 20 - math.max(0, -w) * 2)
  -- body
  poly(C(M.mid), 1, -6, 6, -3, 4, 4, 4, 7, 7, 6, 14, -5, 14)
  poly(C(M.light), 1, -6, 6, -3, 4, 4, 4, 5, 6, -5, 8)
  poly(C(M.gold), 1, -5, 11, 6, 11, 6, 13, -5, 13)
  -- crystal spines
  crystal(-3, 5, 4, 7, -1, C(M.rust))
  crystal(1, 4, 4, 9, 0, C(M.glow))
  -- the head, a block with two orange eyes
  poly(C(M.mid), 1, -4, 0, 4, 0, 5, 6, -3, 6)
  poly(C(M.light), 1, -4, 0, 4, 0, 3, 2, -3, 2)
  -- arms: up as it drops in, forward when it strikes
  if air and e.falling then
    poly(C(M.dark), 1, 5, 6, 7, 6, 8, -3, 6, -3)
    poly(C(M.dark), 1, -6, 6, -8, 6, -9, -3, -7, -3)
  elseif strike then
    poly(C(M.rust), 1, 5, 6, 14, 5, 15, 9, 5, 9)
    poly(C(M.light), 1, 13, 5, 16, 6, 15, 9, 13, 8)
  else
    poly(C(M.dark), 1, 5, 7, 8, 7, 8, 14 + w, 6, 14 + w)
  end
  love.graphics.pop()
end

local function drawMiniGlow(e)
  local b = e.body
  local f = e.facing or 1
  local x, y = math.floor(b.x) + 7, math.floor(b.y)
  love.graphics.setColor(1, 0.6, 0.15, 0.95)
  love.graphics.rectangle("fill", x + f * 2 - 1, y + 2, 2, 1)
  love.graphics.rectangle("fill", x - f * 2 - 1, y + 2, 2, 1)
  love.graphics.setColor(1, 0.55, 0.2, 0.4)
  love.graphics.rectangle("fill", x + f * 2 - 2, y + 1, 4, 3)
end

-- Hooks into the enemy loop -----------------------------------------------------------------------------

enemies.UPDATE.golem = updateGolem
enemies.DRAW.golem = drawGolem
enemies.GLOW.golem = drawGolemGlow
enemies.DRAW.minigolem = drawMini
enemies.GLOW.minigolem = drawMiniGlow
enemies.VOICES.minigolem = { "mouse_grunt", 1.5, 4, 1 }

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  local alive = false
  for _, e in ipairs(enemies.all()) do
    if e.kind == "golem" and not e.dead then
      alive = true
    end
  end
  if not alive then
    stones, waves, rocks = {}, {}, {}
    return
  end
  enemies.golemShots(dt, world, player)
end

local prevDraw = enemies.afterDraw
enemies.afterDraw = function(view)
  if prevDraw then
    prevDraw(view)
  end
  local t = love.timer.getTime()
  for _, s in ipairs(stones) do
    local x, y = math.floor(s.x), math.floor(s.y)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(s.spin)
    love.graphics.setColor(M.dark[1], M.dark[2], M.dark[3])
    love.graphics.polygon("fill", -6, -3, -2, -7, 5, -5, 7, 1, 3, 6, -4, 5)
    love.graphics.setColor(M.mid[1], M.mid[2], M.mid[3])
    love.graphics.polygon("fill", -6, -3, -2, -7, 5, -5, 1, -1)
    love.graphics.setColor(M.gold[1], M.gold[2], M.gold[3])
    love.graphics.line(-3, 1, 2, 3)
    love.graphics.setColor(M.glow[1], M.glow[2], M.glow[3], 0.9)
    love.graphics.rectangle("fill", 1, -2, 2, 2)
    love.graphics.pop()
  end
  for _, w in ipairs(waves) do
    local fade = math.min(1, w.life * 2)
    for k = 0, 5 do
      local h = 9 + 12 * math.abs(math.sin(k * 1.7 + w.x * 0.05))
      local x = w.x - w.dir * k * 7
      love.graphics.setColor(M.mid[1], M.mid[2], M.mid[3], fade)
      love.graphics.polygon("fill", x - 5, w.y, x + 5, w.y, x, w.y - h * (1 - k * 0.12))
      love.graphics.setColor(M.light[1], M.light[2], M.light[3], fade)
      love.graphics.polygon("fill", x - 5, w.y, x - 1, w.y, x - 1, w.y - h * (1 - k * 0.12) + 3)
    end
  end
  for _, r in ipairs(rocks) do
    local shake = r.delay > 0 and math.floor(math.sin(t * 50) * (1 + (1 - r.delay / (r.wait or 1)) * 2) + 0.5) or 0
    if r.delay > 0 and r.floor then
      -- the telegraph: a flashing line down to a warning mark where it will land
      local k = 1 - r.delay / (r.wait or 1)
      local blink = math.floor(t * (6 + 14 * k)) % 2 == 0 and 1 or 0.35
      love.graphics.setColor(1, 0.35, 0.15, 0.6 * blink)
      for yy = r.y + r.size * 2.4, r.floor, 8 do
        love.graphics.rectangle("fill", math.floor(r.x), math.floor(yy), 1, 4)
      end
      love.graphics.setColor(1, 0.45, 0.15, 0.9 * blink)
      love.graphics.polygon("fill", r.x - 7, r.floor, r.x + 7, r.floor, r.x, r.floor - 9)
      love.graphics.setColor(0.1, 0.03, 0.02, 0.9 * blink)
      love.graphics.rectangle("fill", math.floor(r.x) - 1, math.floor(r.floor) - 6, 2, 3)
      love.graphics.rectangle("fill", math.floor(r.x) - 1, math.floor(r.floor) - 2, 2, 1)
    end
    love.graphics.setColor(M.dark[1], M.dark[2], M.dark[3])
    love.graphics.polygon("fill", r.x - r.size / 2 + shake, r.y, r.x + r.size / 2 + shake, r.y, r.x + shake, r.y + r.size * 2.2)
    love.graphics.setColor(M.mid[1], M.mid[2], M.mid[3])
    love.graphics.polygon("fill", r.x - r.size / 2 + shake, r.y, r.x + shake, r.y, r.x + shake, r.y + r.size * 2.2)
  end
end

return true
