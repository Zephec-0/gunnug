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
local fig = require("src.colossusfig")

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
local S = 2 / 3 -- (the scale the attack ranges below were tuned at; the body itself is drawn at 1:1, src.colossusfig)
def.w, def.h = 40, 148
def.speed = 30
def.spriteW, def.spriteH = 130, 176 -- (the portrait box: the figure with its drifting shards)
def.blood = { 0.9, 0.7, 0.45 }
local IDLE_POSE, DORMANT_POSE -- (set below, with the pose code)
def.occluders = function(e)
  -- soft partial blockers shaped like the body in its pose, mirrored to face the way it faces
  local p = e.fpose or (e.altarLocked and DORMANT_POSE) or IDLE_POSE
  local b = e.body
  local bx, gy = math.floor(b.x + b.w / 2), math.floor(b.y + b.h)
  local f = e.facing or 1
  for _, r in ipairs(fig.occluders(p)) do
    local x = f == 1 and bx + (r[1] - fig.CX) or bx - (r[1] - fig.CX) - r[3]
    love.graphics.setColor(1, 1, 1, r[5])
    love.graphics.rectangle("fill", math.floor(x), math.floor(gy + (r[2] - fig.G)), math.ceil(r[3]), math.ceil(r[4]))
  end
end
def.drawMargin = 150 -- (the figure and its shards reach well past its hitbox: no popping in at the screen's edge)
def.barLift = 42 -- (its health bar floats above the crystal head and the shards, not on its hitbox)
def.light = function(e)
  local cx, cy = center(e)
  -- (a warm glow over the whole of it, so the bulk can be seen, and its eye)
  local l = { { cx, cy - 10, 150, 1, 0.72, 0.42, e.altarLocked and 0.04 or 0.2 } }
  if e.eyeX and not e.altarLocked then
    l[2] = { e.eyeX, e.eyeY, e.bm and e.bm.phase == "act" and 120 or 40, 1, 0.55, 0.2, 0.6 }
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
  swipe = { 0.5, 0.14, 0.3 }, -- (a held wind-up, then it whips: the fist is aimed at the hunter, locked near the end)
  throw = { 0.55, 0.1, 0.35 }, -- (ore gathers out of thin air into a ball)
  stomp = { 0.6, 0.14, 0.45 }, -- (ore piles onto the fists as they rise; then they fall hard)
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
    bm.hum = (bm.hum or 0) - dt
    if bm.hum <= 0 then
      bm.hum = 0.35
      sfx("dh_beam", 0.3, 0.9)
    end
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
  e.clk1, e.clk2, e.tickT = false, false, 0
  -- every attack announces itself: a different sound for each wind-up
  if name == "beam" then
    beamStart(e, px, py, t[1], t[2])
    sfx("dh_charge", 0.5, 0.8)
  elseif name == "stomp" then
    sfx("explosion", 0.3, 0.4)
    sfx("rumble", 0.7, 0.6)
  elseif name == "leap" then
    sfx("explosion", 0.3, 0.4)
    sfx("rumble", 0.7, 0.5)
    sfx("creak", 0.5, 0.6)
  elseif name == "swipe" then
    e.aimX, e.aimY = px, py
    sfx("gargoyle_grind", 0.5, 0.7)
  elseif name == "throw" then
    sfx("rocks", 0.6, 0.7)
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
  sfx("gargoyle_crash", 0.8, 0.6)
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
    sfx("impact", 0.7, 0.5)
    sfx("gust_blast", 0.35, 0.7)
    b.vx = f * 90
    -- the fist goes where the hunter was when the aim locked: its height and its distance
    local gy = b.y + b.h
    local reach = math.max(24, math.min(116, ((e.aimX or px) - cx) * f))
    local aimY = gy + math.max(-150, math.min(8, (e.aimY or py) - gy))
    local x0, x1 = cx + f * 16, cx + f * (reach + 16)
    local pb = player.body
    if overlaps(math.min(x0, x1), aimY - 26, math.abs(x1 - x0), 52, pb.x, pb.y, pb.w, pb.h) then
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
    sfx("gust_blast", 0.5, 0.8)
    local n = stage + 1
    local sx, sy = e.handX or (cx + f * 10), e.handY or (b.y + 20) -- (from the raised fist)
    local T = math.max(0.6, math.min(1.1, math.abs(px - sx) / 280))
    for i = 1, n do
      local aim = px + (i - (n + 1) / 2) * 50
      stones[#stones + 1] = { x = sx, y = sy, vx = (aim - sx) / T, vy = (py - sy) / T - 0.5 * 520 * T, life = 4, spin = love.math.random() * 6, dmg = d.damage * 0.75, kind = love.math.random(1, 3) }
    end
  elseif e.gs == "stomp" then
    sfx("explosion", 0.8, 0.4)
    sfx("ram_stamp", 0.7, 0.5)
    camShake(0.6)
    -- both fists hit the ground: a ring of dust and a spray of rubble where each one lands
    for _, fx in ipairs({ cx + f * 40, cx + f * 78 }) do
      effects.ring(fx, b.y + b.h - 4, 34, { 1, 0.7, 0.35 })
      for _ = 1, 14 do
        effects.particle(fx + (love.math.random() - 0.5) * 20, b.y + b.h - 3, (love.math.random() - 0.5) * 150, -50 - love.math.random() * 150, 0.6, love.math.random() < 0.4 and { 1, 0.75, 0.35 } or { 0.85, 0.72, 0.55 }, 420, love.math.random() < 0.4)
      end
    end
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
    sfx("gust_blast", 0.6, 0.5)
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
  e.shellFloor = e.body.y + e.body.h -- (the floor it lifts off from)
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

local figUpdate
-- The pose: springs chasing targets ----------------------------------------------------------------------
-- Every state names where the figure's parts want to be; each channel is a spring, so the fists swing
-- through and settle, the body leans into a strike and the head trails (src.colossusfig draws the result).

IDLE_POSE = { nf = { -2, 0 }, ff = { 10, 0 }, t = 0.6 }
DORMANT_POSE = { drop = 42, nf = { 26, 0 }, ff = { -18, 0 }, nfist = { 10, 8 }, ffist = { 20, 4 }, hy = 8, lean = 6, dead = true, t = 2 }
local DORMANT = { drop = 42, nfx = 26, ffx = -18, nfistx = 10, nfisty = 8, ffistx = 20, ffisty = 4, hy = 8, lean = 6 }
local SEALED = { drop = 38, nfx = 6, ffx = -4, nfl = 30, ffl = 30, nfistx = 28, nfisty = -35, ffistx = -24, ffisty = -36, hy = 14, lean = 0 } -- curled up small inside the gem
local KNEEL = { drop = 30, nfx = 22, ffx = -14, nfistx = 0, nfisty = 20, ffistx = 12, ffisty = 16, hy = 4 }
local REST = { drop = 14, nfx = 14, ffx = -8, nfistx = 4, nfisty = 12, ffistx = 12, ffisty = 8, hy = 8, jaw = 2, lean = 2 }
local BEAMPOSE = { drop = 4, nfx = -12, ffx = 18, nfistx = -26, nfisty = -26, ffistx = 52, ffisty = -34, jaw = 3 }
local POSES = {
  swipe = {
    wind = { lean = -5, nfx = -6, ffx = 10, nfistx = -30, nfisty = -46, ffistx = -4, ffisty = 4, hx = -3, hy = -2, jaw = 2 },
    act = { lean = 9, drop = 3, nfx = 22, ffx = -18, nfistx = 118, nfisty = -14, ffistx = -14, ffisty = 2, hx = 5, hy = 2, jaw = 3, open = true },
  },
  throw = {
    wind = { lean = -3, nfx = -4, ffx = 12, nfistx = 0, nfisty = -72, ffistx = -10, ffisty = -4, hy = -3 },
    act = { lean = 5, drop = 2, nfx = 10, ffx = 2, nfistx = 52, nfisty = -66, ffistx = -16, ffisty = 2, hx = 3, hy = 1, open = true },
  },
  stomp = {
    wind = { lean = -1, nfx = 3, nfl = 16, ffx = 10, nfistx = 8, nfisty = -72, ffistx = 12, ffisty = -74, hy = -3 },
    act = { drop = 7, nfx = 18, ffx = -12, nfistx = 68, nfisty = 16, ffistx = 44, ffisty = 16, hy = 4, jaw = 2 },
  },
  leap = {
    wind = { drop = 16, lean = -5, nfx = 20, ffx = -16, nfistx = -24, nfisty = 10, ffistx = -8, ffisty = 12, hy = 4 },
    act = { nfx = 10, nfl = 16, ffx = -8, ffl = 14, nfistx = 20, nfisty = -40, ffistx = -4, ffisty = -44, lean = 4, hy = -4, open = true, spread = 0.2 },
    land = { drop = 12, lean = 6, nfx = 26, ffx = -22, nfistx = 24, nfisty = 38, ffistx = 46, ffisty = 34, hy = 6, jaw = 3 },
  },
}

local function lerpn(a, b, t)
  return a + (b - a) * t
end

local function ease(k)
  k = math.max(0, math.min(1, k))
  return k * k * (3 - 2 * k)
end

local function spring(e, name, target, k, dt)
  local sp = e.fs[name]
  if not sp then
    sp = { x = target, v = 0 }
    e.fs[name] = sp
  end
  local c = 2 * math.sqrt(k) * 0.6 -- a little under critical: they overshoot and settle
  local n = 2
  for _ = 1, n do
    sp.v = sp.v + ((target - sp.x) * k - sp.v * c) * dt / n
    sp.x = sp.x + sp.v * dt / n
  end
  return sp.x
end

local function figTarget(e)
  local T = { drop = 0, lean = 0, nfx = -2, nfl = 0, ffx = 10, ffl = 0, nfistx = 0, nfisty = 0, ffistx = 0, ffisty = 0, hx = 0, hy = 0, jaw = 0, spread = 0, bob = 0 }
  local k = 200 -- spring stiffness for this state
  local gs, sub = e.gs, e.sub
  local function use(src)
    for key, v in pairs(src) do
      T[key] = v
    end
  end
  local function walk()
    local b = e.body
    local amp = e.grounded and math.min(1, math.abs(b.vx) / 30) or 0
    local c, sn = math.cos(e.phase), math.sin(e.phase)
    T.nfx, T.ffx = lerpn(-2, 24 * c, amp), lerpn(10, -20 * c, amp)
    T.nfl, T.ffl = 14 * math.max(0, -sn) * amp, 14 * math.max(0, sn) * amp
    T.nfistx, T.ffistx = -12 * c * amp, 14 * c * amp
    T.lean, T.bob = 3 * amp, 2 * math.abs(sn) * amp
  end
  if e.state == "idle" or e.state == "sleep" or not gs then
    use(DORMANT)
    T.dead = true
  elseif gs == "rise" then
    -- dormant stone coming awake: a heap, the ore drifting together, then a flare and the eye
    local p = 1 - math.max(0, e.gt or 0) / 2.6
    T.dead = p < 0.3
    T.drop = lerpn(42, 0, ease((p - 0.2) / 0.7))
    T.spread = p < 0.5 and (p / 0.5) or lerpn(1, 0.3, math.min(1, (p - 0.5) / 0.5))
    T.hy = lerpn(8, -8, ease((p - 0.5) / 0.4))
    T.nfx, T.ffx = lerpn(26, 14, ease(p)), lerpn(-18, -12, ease(p))
    local wake = ease((p - 0.65) / 0.3)
    T.nfistx, T.nfisty = lerpn(10, -20, wake), lerpn(8, -22, wake)
    T.ffistx, T.ffisty = lerpn(20, 40, wake), lerpn(4, -30, wake)
    T.flare = p > 0.8 and (p - 0.8) / 0.2 or 0
    T.charge = p > 0.7 and 0.6 or 0
    T.open = p > 0.8
    T.jaw = p > 0.8 and 4 or 0
    k = 90
  elseif gs == "shell" then
    -- kneels and slims up, then curls into itself while the gem grows round it from the inside out and
    -- lifts it off the floor (e.shellT counts from the kneel)
    local st = e.shellT or 0
    use(KNEEL)
    local curl = ease((st - 0.4) / 0.7)
    for key, v in pairs(SEALED) do
      T[key] = lerpn(T[key] or 0, v, curl)
    end
    T.slim = ease(st / 0.5)
    T.tuck = curl
    T.charge = e.charge or 0
    k = 110
  elseif gs == "rest" then
    use(REST)
    k = 110
  elseif gs == "beam" then
    use(BEAMPOSE)
    T.open = true
    k = sub == "act" and 200 or 150
    if e.bm then
      T.charge = e.bm.phase == "wind" and (e.charge or 0) or 0.4
      if e.bm.ang then
        T.hy = -3 + 3 * math.sin(e.bm.ang)
      else
        T.hy = -5
      end
    end
  elseif POSES[gs] then
    local set = POSES[gs]
    local which = sub == "wind" and "wind" or (sub == "act" and "act" or nil)
    if gs == "leap" then
      if sub == "wind" then
        which = "wind"
      elseif e.leapAir then
        which = "act"
      else
        which = "land"
      end
    end
    if gs == "swipe" and which then
      -- aimed: the fist goes back and away from the hunter and holds, trembling, then whips out to where the
      -- hunter stood when the aim locked (height and distance), the body stretching into it
      local f = e.facing or 1
      local cxx = e.body.x + e.body.w / 2
      local gyy = e.body.y + e.body.h
      local dx = math.max(24, math.min(116, ((e.aimX or cxx) - cxx) * f))
      local dy = math.max(-150, math.min(8, (e.aimY or gyy) - gyy))
      if which == "wind" then
        local pw = 1 - math.max(0, e.gt or 0) / math.max(0.01, e.gd or 1)
        local draw = ease(pw * 1.5)
        use(set.wind)
        T.nfistx = lerpn(0, -34, draw) + math.sin(love.timer.getTime() * 40) * 1.2 * math.max(0, pw - 0.5)
        T.nfisty = lerpn(0, -40 + dy * 0.25, draw)
        T.lean = lerpn(0, -6, draw)
        k = 90
      else
        use(set.act)
        T.nfistx = dx + 28
        T.nfisty = dy + 58
        T.lean = 10
        T.stretch = 10
        k = 2200
      end
    elseif gs == "stomp" and which then
      if which == "wind" then
        -- both fists climb while ore piles onto them, trembling under the weight
        local pw = 1 - math.max(0, e.gt or 0) / math.max(0.01, e.gd or 1)
        local draw = ease(pw * 1.3)
        use(set.wind)
        T.nfisty = lerpn(0, -78, draw)
        T.ffisty = lerpn(0, -80, draw)
        T.nfistx = 8 + math.sin(love.timer.getTime() * 45) * 1.2 * math.max(0, pw - 0.4)
        T.lean = lerpn(0, -6, draw)
        T.stretch = 6 * draw
        T.mass = ease(pw * 1.15)
        k = 100
      else
        -- and falls: heavy, fast, the body dropping with them
        use(set.act)
        T.mass = 1
        T.lean = 6
        T.drop = 11
        k = 2600
      end
    elseif gs == "leap" and which == "act" then
      -- in the air each part chases the one above it: rising, the head leads and the arms and legs
      -- trail below; falling, the feet lead and everything above lags behind
      local vy = e.body.vy
      local sp = math.min(1, math.abs(vy) / 240)
      use(set.act)
      T.stretch = 28 * sp
      T.spread = 0.1 + 0.1 * sp
      if vy < 0 then
        T.nfx, T.ffx, T.nfl, T.ffl = 4, -8, 0, 0
        T.nfistx, T.nfisty, T.ffistx, T.ffisty = -10, 42 * sp, 8, 36 * sp
      else
        T.nfx, T.ffx, T.nfl, T.ffl = 8, -6, 0, 0
        T.nfistx, T.nfisty, T.ffistx, T.ffisty = -4, -84 * sp, 8, -78 * sp
      end
      k = 120
    elseif gs == "leap" and which == "land" then
      -- landed: all of it slams down and comes apart, then the ore pulls itself back together
      local p = 1 - math.max(0, e.gt or 0) / math.max(0.01, e.gd or 1)
      local reform = ease((p - 0.3) / 0.7)
      use(set.land)
      T.drop = lerpn(set.land.drop + 16, 0, reform)
      T.spread = 1 - reform
      T.nfistx, T.nfisty = lerpn(30, 0, reform), lerpn(40, 0, reform)
      T.ffistx, T.ffisty = lerpn(50, 0, reform), lerpn(36, 0, reform)
      k = 140
    elseif which then
      use(set[which])
      k = which == "wind" and 130 or 700
    else
      walk() -- recovering: back to the walk
      k = 120
    end
  else
    walk()
  end
  if gs == "throw" and sub == "wind" then
    T.ball = ease(1.25 * (1 - math.max(0, e.gt or 0) / math.max(0.01, e.gd or 1)))
  end
  -- the beam can be fired from the shell too
  if e.bm and gs ~= "beam" and e.charge then
    T.charge = e.charge
  end
  return T, k
end

figUpdate = function(e, dt)
  e.fs = e.fs or {}
  e.shellT = (e.gs == "shell") and ((e.shellT or 0) + dt) or 0
  -- sealed, it hovers in its gem, clear of the floor (the golemlings have the arena to themselves)
  e.hoverH = (e.gs == "shell") and 56 * ease((e.shellT - 0.6) / 0.9) or 0
  local T, k = figTarget(e)
  dt = math.min(dt, 1 / 20)
  local function sp(name, target, kk)
    return spring(e, name, target or 0, kk or k, dt)
  end
  local hk = 220
  local pose = {
    drop = sp("drop", T.drop),
    lean = sp("lean", T.lean),
    bob = T.bob,
    nf = { sp("nfx", T.nfx), sp("nfl", T.nfl) },
    ff = { sp("ffx", T.ffx), sp("ffl", T.ffl) },
    nfist = { sp("nfistx", T.nfistx), sp("nfisty", T.nfisty) },
    ffist = { sp("ffistx", T.ffistx), sp("ffisty", T.ffisty) },
    hx = sp("hx", T.hx, hk) + (e.headX or 0) * 0.4,
    hy = sp("hy", T.hy, hk) + (e.headY or 0) * 0.4,
    jaw = sp("jaw", T.jaw, hk),
    spread = sp("spread", T.spread, 120),
    stretch = sp("stretch", T.stretch, 200),
    slim = sp("slim", T.slim, 200),
    tuck = sp("tuck", T.tuck, 200),
    mass = sp("mass", T.mass, 60),
    ball = T.ball,
    shellG = e.gs == "shell" and ease((e.shellT or 0) / 1.6) or 0,
    open = T.open,
    charge = T.charge,
    dead = T.dead,
    flare = T.flare,
    t = love.timer.getTime(),
  }
  -- the gem growing: its seeds, then its closing, make sounds
  if e.gs == "shell" then
    local st = e.shellT
    for i, at in ipairs({ 0.45, 0.8, 1.15, 1.45 }) do
      if st >= at and (e.shellCue or 0) < i then
        e.shellCue = i
        sfx(i % 2 == 0 and "wisp_crackle" or "pop", 0.45, 0.8 + i * 0.12)
      end
    end
    if st >= 1.6 and (e.shellCue or 0) < 5 then
      e.shellCue = 5
      sfx("gargoyle_crash", 0.6, 1.3)
      sfx("tooth_break", 0.5, 0.9)
    end
  else
    e.shellCue = 0
  end
  e.fpose = pose
  -- the raised fist, in the world (where thrown stones leave from)
  local b = e.body
  local f = e.facing or 1
  local bx, by = fig.ballOffset(pose)
  e.handX = b.x + b.w / 2 + f * bx
  e.handY = b.y + b.h + by -- (where the thrown stones leave from: the gathered ball)
  -- while the ball gathers, grit and sparks stream in out of the air to it, so the making is easy to see
  if e.gs == "throw" and e.sub == "wind" and (pose.ball or 0) > 0 then
    local n = 1 + math.floor((pose.ball or 0) * 3)
    for _ = 1, n do
      if love.math.random() < dt * 100 then
        local ang = love.math.random() * math.pi * 2
        local dist = 45 + love.math.random() * 55
        local life = 0.28 + love.math.random() * 0.14
        local sx, sy = e.handX + math.cos(ang) * dist, e.handY + math.sin(ang) * dist * 0.8
        local col = love.math.random() < 0.5 and { 1, 0.8, 0.35 } or { 0.95, 0.88, 0.75 }
        effects.particle(sx, sy, (e.handX - sx) / life, (e.handY - sy) / life, life, col, 0, true)
      end
    end
  end
end


local function updateGolem(e, dt, world, player, px, py)
  local def2, b = e.def, e.body
  local collide = collider(e, world)
  local cx, cy = center(e)
  local dist = hypot(px - cx, py - cy)
  local a = e.arena
  e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
  local frac = e.hp / e.maxHp
  local stage = frac > 0.66 and 1 or (frac > 0.33 and 2 or 3)

  -- The floating head, on a spring: it trails and answers knocks (src.colossusfig draws it from the pose)
  e.headX, e.headY = e.headX or 0, e.headY or 0
  e.headVX, e.headVY = e.headVX or 0, e.headVY or 0
  e.headVX = e.headVX + (0 - e.headX) * 90 * dt - e.headVX * 9 * dt
  e.headVY = e.headVY + (0 - e.headY) * 90 * dt - e.headVY * 9 * dt
  e.headX, e.headY = e.headX + e.headVX * dt, e.headY + e.headVY * dt
  -- the eye, wherever the figure's pose (from the last update) puts it: the beam starts there
  local eox, eoy = fig.eyeOffset(e.fpose or IDLE_POSE)
  e.eyeX, e.eyeY = cx + e.facing * eox, b.y + b.h + eoy

  if e.state == "idle" or e.state == "sleep" then
    local inside = not a or (px > a.x0 and px < a.x1 and py > a.top and py < a.floorY)
    if inside and dist < def2.sight and not e.altarLocked then
      e.state, e.gs, e.gt = "chase", "rise", 2.6
      sfx("explosion", 0.7, 0.35)
    else
      b.vy = math.min(b.vy + config.gravity * dt, 450)
      if Body.moveY(b, collide, b.vy * dt) then
        b.vy = 0
      end
      figUpdate(e, dt)
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
      if e.gs == "swipe" and e.gt > t[1] * 0.3 then
        e.aimX, e.aimY = px, py -- (it tracks the hunter, then the aim locks: the last stretch of the wind-up is a dodge window)
      end
      if e.gs == "throw" then
        e.tickT = (e.tickT or 0) - dt
        if e.tickT <= 0 then
          e.tickT = 0.07
          sfx("tick", 0.25, 0.7 + 0.9 * (1 - math.max(0, e.gt) / t[1]))
        end
      end
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
      if e.gs == "leap" then
        -- the ore pulling itself back together, piece by piece
        local rp = 1 - math.max(0, e.gt) / math.max(0.01, e.gd or 1)
        if rp > 0.35 and not e.clk1 then
          e.clk1 = true
          sfx("clank", 0.5, 0.8)
        end
        if rp > 0.6 and not e.clk2 then
          e.clk2 = true
          sfx("clank", 0.6, 1.0)
          sfx("rocks", 0.4, 0.9)
        end
      end
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
  if e.gs == "shell" and e.shellFloor and (e.hoverH or 0) > 0 then
    -- (floating up to its hover height, then bobbing there)
    local want = e.shellFloor - e.hoverH + math.sin(love.timer.getTime() * 2.2) * 2
    b.vy = math.max(-150, math.min(150, (want - (b.y + b.h)) * 8))
  else
    b.vy = math.min(b.vy + config.gravity * dt, 450)
  end
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
  figUpdate(e, dt)
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
    if love.math.random() < dt * 70 then
      effects.particle(w.x, w.y - 2, (love.math.random() - 0.5) * 40, -40 - love.math.random() * 60, 0.4, { 0.85, 0.65, 0.42 }, 300)
    end
    if love.math.random() < dt * 40 then
      effects.particle(w.x, w.y - 4, -w.dir * 20 + (love.math.random() - 0.5) * 30, -30 - love.math.random() * 70, 0.35, { 1, 0.7, 0.3 }, 0, true)
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

local function crystal(x, y, w, h, tilt, col)
  poly(col, 1, x - w / 2, y, x + w / 2, y, x + tilt, y - h)
  poly({ math.min(1, col[1] + 0.25), math.min(1, col[2] + 0.25), math.min(1, col[3] + 0.2) }, 1, x - w / 2, y, x, y, x + tilt, y - h)
end

-- The body is src.colossusfig's figure, drawn each frame into a canvas at 1:1, outlined by a shader
-- (so every part shares one pixel size) and mirrored to face the hunter.
local figCanvas, figShader

local function drawGolem(e)
  if not figCanvas then
    figCanvas = love.graphics.newCanvas(fig.W, fig.H)
    figCanvas:setFilter("nearest", "nearest")
    figShader = love.graphics.newShader(fig.outlineShaderCode)
    figShader:send("texel", { 1 / fig.W, 1 / fig.H })
  end
  local p = e.fpose or (e.altarLocked and DORMANT_POSE) or IDLE_POSE
  local b = e.body
  local f = e.facing or 1
  if not e.eyeX then
    -- (a portrait, not in the fight)
    local eox, eoy = fig.eyeOffset(p)
    e.eyeX, e.eyeY = b.x + b.w / 2 + f * eox, b.y + b.h + eoy
  end
  love.graphics.push("all")
  love.graphics.setCanvas({ figCanvas, stencil = true })
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  love.graphics.setColor(1, 1, 1)
  if e.invuln and (p.shellG or 0) > 0.9 then
    -- sealed: everything is clipped to the gem, so no part hangs out of it
    local pts = fig.gemPoints(p.shellG)
    love.graphics.stencil(function()
      love.graphics.polygon("fill", pts)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
  end
  fig.draw(p)
  love.graphics.setStencilTest()
  love.graphics.pop()
  local bx, gy = math.floor(b.x + b.w / 2), math.floor(b.y + b.h)
  love.graphics.push("all")
  love.graphics.setShader(figShader)
  figShader:send("flash", e.flash > 0 and 0.85 or 0)
  love.graphics.setBlendMode("alpha", "premultiplied")
  if e.altarLocked then
    love.graphics.setColor(0.40, 0.40, 0.46, 0.8) -- dormant: dim, almost fading into the hall
  else
    love.graphics.setColor(1, 1, 1)
  end
  love.graphics.draw(figCanvas, bx, gy, 0, f, 1, fig.CX, fig.G)
  love.graphics.pop()
  -- the crystal shell, when it kneels
  if e.invuln and e.gs == "shell" then
    love.graphics.push()
    love.graphics.translate(bx, gy)
    love.graphics.scale(f, 1)
    love.graphics.translate(-fig.CX, -fig.G)
    fig.shell(love.timer.getTime(), p.shellG)
    love.graphics.pop()
  end
end

local function drawGolemGlow(e)
  local t = love.timer.getTime()
  if not e.eyeX then
    return
  end
  local ex, ey = e.eyeX, e.eyeY
  local p = e.fpose
  local f = e.facing or 1
  local asleep = p and p.dead
  local charging = e.bm and e.bm.phase == "wind"
  local pulse = 0.7 + 0.3 * math.sin(t * (charging and 30 or 5))
  love.graphics.setBlendMode("add")
  if not asleep then
    -- the eye: a soft bloom, a hot core, and a crisp spark
    local rad = (charging and 16 + 16 * (e.charge or 0) or 15) * (0.9 + 0.1 * pulse)
    fig.glow(ex, ey, rad, 1, 0.5, 0.15, 0.5 * pulse)
    fig.glow(ex, ey, rad * 0.42, 1, 0.8, 0.4, 0.8)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 0.95, 0.75, pulse)
    love.graphics.rectangle("fill", math.floor(ex), math.floor(ey - 1), 1, 3)
    love.graphics.setBlendMode("add")
    -- the heart stone, in its dark plane, glows brighter as it winds up
    if p then
      local b = e.body
      local hx, hy = fig.heartOffset(p)
      local x, y = b.x + b.w / 2 + f * hx, b.y + b.h + hy
      local vp = (0.45 + 0.2 * math.sin(t * 2.2)) + (e.sub == "wind" and 0.35 or 0)
      local k = vp * (e.invuln and 0.5 or 1)
      fig.glow(x, y, 17, 1, 0.65, 0.2, 0.5 * k)
      fig.glow(x, y, 7, 1, 0.9, 0.5, 0.7 * k)
    end
  end
  love.graphics.setBlendMode("alpha")
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
    local len = math.max(1, hypot(x1 - ex, y1 - ey))
    local dx, dy = (x1 - ex) / len, (y1 - ey) / len
    local nx, ny = -dy, dx
    local flick = 1 + 0.12 * math.sin(t * 45) + 0.08 * math.sin(t * 23 + 1)
    local function band(w, r, g, b, a)
      love.graphics.setColor(r, g, b, a)
      love.graphics.polygon("fill", ex + nx * w, ey + ny * w, x1 + nx * w, y1 + ny * w, x1 - nx * w, y1 - ny * w, ex - nx * w, ey - ny * w)
    end
    love.graphics.setBlendMode("add")
    band(9 * flick, 1, 0.38, 0.08, 0.12)
    band(6 * flick, 1, 0.5, 0.12, 0.2)
    band(3.6 * flick, 1, 0.7, 0.25, 0.45)
    band(1.8 * flick, 1, 0.92, 0.6, 0.8)
    band(0.8, 1, 1, 0.95, 1)
    -- bloom along its length, and pulses racing out of the eye
    for d = 0, len, 26 do
      fig.glow(ex + dx * d, ey + dy * d, 15, 1, 0.5, 0.15, 0.16)
    end
    local off = (t * 260) % 22
    for d = off, len, 22 do
      fig.glow(ex + dx * d, ey + dy * d, 5, 1, 0.95, 0.7, 0.7)
    end
    -- where it burns: a big bloom, a white-hot core
    fig.glow(x1, y1, 30 * flick, 1, 0.5, 0.12, 0.55)
    fig.glow(x1, y1, 13 * flick, 1, 0.9, 0.55, 0.9)
    fig.glow(ex, ey, 18, 1, 0.6, 0.2, 0.5)
    love.graphics.setBlendMode("alpha")
  end
end

-- The golemlings: a gem for a body and two bits of marble for legs (src.colossusfig), drawn into a small
-- canvas and outlined like their master
local miniCanvas, miniShader

local function drawMini(e)
  if not miniCanvas then
    miniCanvas = love.graphics.newCanvas(fig.MW, fig.MH)
    miniCanvas:setFilter("nearest", "nearest")
    miniShader = love.graphics.newShader(fig.plainShaderCode)
  end
  local b = e.body
  local f = e.facing or 1
  local air = not e.grounded
  love.graphics.push("all")
  love.graphics.setCanvas(miniCanvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  love.graphics.setColor(1, 1, 1)
  fig.drawMini({ ph = e.phase * 1.5, moving = e.grounded and math.abs(b.vx) > 4, air = air, falling = air and e.falling, strike = (e.strikeT or 0) > 0, trip = e.trip and e.trip.t / e.trip.dur, t = love.timer.getTime() })
  love.graphics.pop()
  love.graphics.push("all")
  love.graphics.setShader(miniShader)
  miniShader:send("flash", e.flash > 0 and 0.85 or 0)
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(miniCanvas, math.floor(b.x + b.w / 2), math.floor(b.y + b.h), 0, f, 1, fig.MW / 2 - 8, fig.MG)
  love.graphics.pop()
end

local function drawMiniGlow(e)
  if e.trip and e.trip.t / e.trip.dur > 0.12 and e.trip.t / e.trip.dur < 0.85 then
    return -- (its face is in the dirt)
  end
  local b = e.body
  local f = e.facing or 1
  local x, y = math.floor(b.x + b.w / 2) + f * fig.miniEye[1], math.floor(b.y + b.h) + fig.miniEye[2]
  love.graphics.setColor(1, 0.55, 0.2, 0.4)
  love.graphics.rectangle("fill", x - 3, y - 3, 6, 7)
  love.graphics.setColor(1, 0.7, 0.2, 0.95)
  love.graphics.rectangle("fill", x - 1, y - 2, 2, 4)
end

-- Hooks into the enemy loop -----------------------------------------------------------------------------

enemies.UPDATE.golem = updateGolem
-- A golemling now and then trips over its own feet: it pitches forward, slides, falls, lies dazed, gets up
local baseMiniUpdate = enemies.UPDATE.minigolem
enemies.UPDATE.minigolem = function(e, dt, world, player, px, py)
  local b = e.body
  local tr = e.trip
  if tr then
    local collide = collider(e, world)
    tr.t = tr.t + dt
    b.vx = b.vx * math.max(0, 1 - 3.2 * dt) -- (still sliding on, slowing)
    b.vy = math.min(b.vy + config.gravity * dt, 450)
    if Body.moveX(b, collide, b.vx * dt, 4) then
      b.vx = 0
    end
    if Body.moveY(b, collide, b.vy * dt) then
      b.vy = 0
    end
    e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
    if not tr.landed and tr.t > 0.3 then
      tr.landed = true
      sfx("hit", 0.4, 1.3)
      for _ = 1, 5 do
        effects.particle(b.x + b.w / 2 + (e.facing or 1) * 8, b.y + b.h - 2, (love.math.random() - 0.5) * 50, -20 - love.math.random() * 30, 0.4, { 0.85, 0.7, 0.5 }, 200)
      end
    end
    if tr.t >= tr.dur then
      e.trip = nil
      e.tripCd = 3 + love.math.random() * 3
    end
    return
  end
  e.tripCd = (e.tripCd or (1 + love.math.random() * 3)) - dt
  if e.tripCd <= 0 and e.state == "chase" and e.grounded and not e.falling and (e.strikeT or 0) <= 0 and math.abs(b.vx) > 40 and love.math.random() < dt * 0.4 then
    e.trip = { t = 0, dur = 1.15 }
    b.vx = (e.facing or 1) * 75
    sfx("clank", 0.4, 1.4)
    return
  end
  return baseMiniUpdate(e, dt, world, player, px, py)
end

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
    love.graphics.scale(1.5)
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
    local d = w.dir
    -- a crack running back along the ground behind the front, glowing where the ground is fresh
    for k = 0, 56 do
      local x = math.floor(w.x - d * k)
      local a = (1 - k / 56) * fade
      love.graphics.setColor(M.deep[1], M.deep[2], M.deep[3], 0.8 * a)
      love.graphics.rectangle("fill", x, math.floor(w.y) - 1 + (k % 5 == 0 and 1 or 0), 1, 1)
      if k < 36 then
        love.graphics.setColor(M.gold[1], M.gold[2], M.gold[3], 0.75 * a)
        love.graphics.rectangle("fill", x, math.floor(w.y) - 2, 1, 1)
      end
    end
    -- spikes: tall just behind the front, falling away behind it; each leans, has a lit and a shaded face and
    -- a crystal tip
    for k = 0, 8 do
      local grow = k == 0 and 0.55 or math.max(0, 1 - (k - 1) * 0.125)
      if grow > 0.04 then
        local base = 10 + 14 * math.abs(math.sin(k * 1.7 + w.x * 0.05))
        local h = base * grow
        local x = math.floor(w.x - d * k * 6.5)
        local y = math.floor(w.y)
        local lean = ((k % 2 == 0) and 1 or -1) * 2 - d
        local hw = 5 - math.floor(k / 5)
        local tipx, tipy = x + lean, y - h
        love.graphics.setColor(M.light[1], M.light[2], M.light[3], fade)
        love.graphics.polygon("fill", x - hw, y, x, y, tipx, tipy)
        love.graphics.setColor(M.dark[1], M.dark[2], M.dark[3], fade)
        love.graphics.polygon("fill", x, y, x + hw, y, tipx, tipy)
        -- the crystal tip, orange, the last third of each spike
        local tx = 0.32
        local mxl, mxr = tipx + (x - hw - tipx) * tx, tipx + (x + hw - tipx) * tx
        local my = tipy + (y - tipy) * tx
        love.graphics.setColor(M.glow[1], M.glow[2], M.glow[3], fade)
        love.graphics.polygon("fill", mxl, my, tipx, my, tipx, tipy)
        love.graphics.setColor(M.rust[1], M.rust[2], M.rust[3], fade)
        love.graphics.polygon("fill", tipx, my, mxr, my, tipx, tipy)
        love.graphics.setColor(1, 0.95, 0.7, fade)
        love.graphics.rectangle("fill", math.floor(tipx), math.floor(tipy), 1, 1)
        love.graphics.setColor(M.deep[1], M.deep[2], M.deep[3], fade * 0.8)
        love.graphics.rectangle("fill", x - hw, y - 1, hw * 2 + 1, 1)
      end
    end
    -- the front: a flash of light where the ground splits
    love.graphics.setBlendMode("add")
    fig.glow(w.x, w.y - 4, 22, 1, 0.6, 0.2, 0.45 * fade)
    fig.glow(w.x, w.y - 3, 9, 1, 0.9, 0.6, 0.6 * fade)
    love.graphics.setBlendMode("alpha")
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
