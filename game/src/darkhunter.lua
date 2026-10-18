-- The Needle's summit boss, in two phases (replacing the Dread Bat there):
--
-- The Dark Hunter: the hunter's own shape gone dark, in the black and violet
-- of the shop's void, quicker than him. He holds two revolvers (always
-- S grade, an ammo type and an attachment each) and fires both at once, aimed
-- the way the hunter aims; he triple-jumps, rolls through the air in dashes,
-- and keeps an even distance without ever running off. Now and then he
-- triple-jumps high and two shadows of him dash out to either side; all three
-- hang in the air, one of them lights its eye bright red, and that one fires
-- a quick beam at the hunter.
--
-- At no health he kneels for two seconds. A great crow swoops down to him
-- (hurting the hunter if he is in its way), he mounts it and his health comes
-- back doubled: the Crow Rider, who hovers on its wingbeats, shoots and sends
-- shadows the same way, and has the crow dive at the hunter.
--
-- Beating him unlocks the Akimbo perk for the profile (src.perks).
local enemies = require("src.enemies")
local Body = require("src.body")
local audio = require("src.audio")
local config = require("src.config")
local effects = require("src.effects")
local guns = require("src.guns")
local gunInfo = require("src.gunInfo")
local items = require("src.items")
local playeranim = require("src.playeranim")

local H = enemies.helpers
local center, collider, removePhysics = H.center, H.collider, H.removePhysics
local pcfg = config.player

local function hypot(x, y)
  return math.sqrt(x * x + y * y)
end

local function sign(v)
  return v < 0 and -1 or 1
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

-- The hunter's clothes in black and violet (playeranim's COLORS keys)
local PAL = {
  coat = { 0.06, 0.04, 0.09 },
  coatLight = { 0.24, 0.13, 0.34 },
  coatDark = { 0.03, 0.02, 0.05 },
  lining = { 0.74, 0.28, 1.0 },
  mantle = { 0.20, 0.12, 0.30 },
  mantleLight = { 0.42, 0.26, 0.62 },
  mantleDark = { 0.11, 0.06, 0.17 },
  trousers = { 0.08, 0.06, 0.11 },
  trousersDark = { 0.05, 0.04, 0.07 },
  boots = { 0.03, 0.02, 0.04 },
  bootsDark = { 0.02, 0.015, 0.03 },
  buckle = { 0.72, 0.46, 1.0 },
  glove = { 0.05, 0.03, 0.07 },
  hat = { 0.04, 0.03, 0.06 },
  hatLight = { 0.19, 0.11, 0.29 },
  hatBand = { 0.58, 0.22, 0.90 },
  shadow = { 0.02, 0.01, 0.03 },
  eye = { 0.86, 0.45, 1.0 },
  gun = { 0.08, 0.07, 0.10 },
  gunMid = { 0.32, 0.19, 0.45 },
  silver = { 0.80, 0.58, 1.0 },
  grip = { 0.12, 0.06, 0.16 },
}
local function variant(alpha, eye)
  local p = {}
  for k, c in pairs(PAL) do
    p[k] = { c[1], c[2], c[3], alpha }
  end
  if eye then
    p.eye = { eye[1], eye[2], eye[3], 1 }
  end
  return p
end
local PAL_RED = variant(1, { 1, 0.12, 0.10 }) -- the one about to fire: its eye burns red
local PAL_SHADOW = variant(0.6) -- his shadows
local PAL_SHADOW_RED = variant(0.6, { 1, 0.12, 0.10 })

local CROW_SCALE = 1.7 -- (a great crow: big enough to carry him)
local CROW = {
  body = { 0.05, 0.035, 0.07 },
  dark = { 0.025, 0.02, 0.035 },
  sheen = { 0.30, 0.18, 0.46 },
  beak = { 0.22, 0.20, 0.24 },
  eye = { 0.95, 0.35, 1.0 },
}

-- Tuning
local T = {
  speed = 140, -- on foot, a quarter quicker than the hunter
  keep = 150, -- the distance he keeps
  jump = 250,
  airJumps = 3, -- jumps before he must land
  dash = 320, -- air dash speed
  dashTime = 0.3,
  volley = 0.42, -- least time between two volleys
  shotSpeed = 400,
  shotDamage = 6, -- per bullet, before the area's damage scaling
  beamDamage = 22,
  kneel = 2.0,
  crowIn = 1.5,
  swoopDamage = 20,
  hover = 110, -- the Crow Rider hangs this far over the hunter
}

-- Definition ---------------------------------------------------------------------------------------

local def = {
  name = "The Dark Hunter",
  boss = true, anchored = true, ground = true, alwaysActive = true,
  w = 8, h = 19, hp = 600, speed = T.speed,
  sight = 900, forget = 4000,
  knockback = 0.02, knockMul = 0.05, gold = { 220, 280 }, weight = 20,
  spriteW = 8, spriteH = 19, scale = 1,
  blood = { 0.42, 0.18, 0.58 },
  desc = "The hunter's own shape gone dark. Two revolvers, three jumps, and shadows that dash out of him. Knock him down and something comes for him out of the sky.",
}
-- (no def.damage: touching him doesn't hurt; his guns do)
enemies.defs.darkhunter = def
enemies.order[#enemies.order + 1] = "darkhunter"

-- An S-grade revolver with one ammo type and one attachment from the pool
local function bossGun()
  local gun
  local best, bestScore = nil, -math.huge
  for _ = 1, 400 do
    gun = guns.generate("revolver", nil, 0)
    local s = gunInfo.score(gun)
    if s > bestScore and gun.slotCount >= 2 then
      best, bestScore = gun, s
    end
    if gunInfo.gradeIndex(gun) >= 6 and gun.slotCount >= 2 then
      break
    end
  end
  gun = best or guns.generate("revolver", nil, 0)
  if gunInfo.gradeIndex(gun) < 6 then
    -- (rolls nudged up to an S if the dice never got there)
    gun.rolls = gun.rolls or {}
    gun.rolls.damage = math.max(gun.rolls.damage or 1, 1.45)
    gun.rolls.fireDelay = math.min(gun.rolls.fireDelay or 1, 0.75)
    gun.rolls.reloadTime = math.min(gun.rolls.reloadTime or 1, 0.75)
    gun.rolls.bulletSpeed = math.max(gun.rolls.bulletSpeed or 1, 1.25)
  end
  gun.slotCount = math.max(2, gun.slotCount)
  gun.slots = {}
  local want = { ammo = true, attachment = true }
  for _ = 1, 200 do
    local item = items.random()
    if want[item.kind] and item.rarity ~= "cursed" then
      want[item.kind] = nil
      gun.slots[#gun.slots + 1] = item
    end
    if not want.ammo and not want.attachment then
      break
    end
  end
  gun.chambers = gun:maxChambers()
  return gun
end

-- A figure the hunter's animation can draw: the boss himself, or a shadow
local function newFigure(x, y, world)
  return {
    anim = playeranim.new(),
    body = Body.new(math.floor(x - 4), math.floor(y - 19), 8, 19),
    facing = 1,
    aimAngle = 0,
    grounded = true,
    crouched = false,
    sliding = false,
    kickTimer = 0,
    dead = false,
    world = world,
    noWounds = true,
  }
end

local function ensure(e, world)
  if e.fig then
    if world and not e.fig.world then
      e.fig.world = world
    end
    return
  end
  local cx = center(e)
  e.guns = { bossGun(), bossGun() }
  e.fig = newFigure(cx, e.body.y + e.body.h, world)
  e.fig.gun, e.fig.gun2 = e.guns[1], e.guns[2]
  e.ph, e.mode = 1, "fight"
  e.jumps = T.airJumps
  e.specialT = 6 + love.math.random() * 3
  e.strafe, e.strafeT = 0, 0
  e.volleyT, e.dashCd = 0.8, 1
  e.bossName = "The Dark Hunter"
end

-- What a hit does: nothing while he kneels or is being carried off; the blow
-- that would end the first phase leaves him on his knees instead
def.filter = function(e, amount)
  if e.mode == "kneel" or e.mode == "crow" or e.mode == "mount" then
    return 0
  end
  if e.ph == 1 and e.hp - amount <= 0 then
    e.hp = 1
    e.mode, e.modeT = "kneel", T.kneel
    e.sp = nil
    audio.playAt("dh_voice", e.body.x, e.body.y, 1, 0.7)
    audio.playAt("clank", e.body.x, e.body.y, 0.8, 0.5)
    effects.ring(e.body.x + 4, e.body.y + 10, 30, { 0.75, 0.4, 1 })
    return 0
  end
  if e.ph == 2 and e.hp - amount <= 0 then
    require("src.meta").unlockPerk("akimbo")
  end
  return amount
end

def.light = function(e)
  local cx, cy = center(e)
  local l = { { cx, cy - 4, e.ph == 2 and 80 or 46, 0.62, 0.32, 0.95, 0.55 } }
  if e.crow then
    l[#l + 1] = { e.crow.x, e.crow.y, 70, 0.55, 0.3, 0.9, 0.5 }
  end
  local sp = e.sp
  if sp and sp.shooters and sp.stage == "hold" then
    for k in pairs(sp.shooters) do
      local ex, ey = playeranim.eyes(sp.figs[k])
      l[#l + 1] = { ex, ey, 40 + 30 * (sp.t / sp.hold), 1, 0.15, 0.1, 1 }
    end
  end
  return l
end

-- Bullets and the beam ---------------------------------------------------------------------------------

local shots = {} -- his bullets: { x, y, vx, vy, life, dmg, tint }
local beams = {} -- fired beams fading out: { x0, y0, x1, y1, life }
local swoopHit = {} -- (one hit per crow swoop)

local function fireVolley(e, world)
  local fig = e.fig
  local fired = false
  local ready = true
  for _, g in ipairs(e.guns) do
    if not g:isReloading() and not g:canFire() then
      ready = false -- (both fire together: wait for the slower one)
    end
  end
  if not ready then
    return
  end
  for i, g in ipairs(e.guns) do
    if g:canFire() then
      local spread = (love.math.random() - 0.5) * 0.08
      local list = g:fire(fig.aimAngle + spread, {})
      if list then
        fired = true
        local mx, my
        if i == 1 then
          mx, my = playeranim.muzzle(fig)
          playeranim.onShoot(fig)
        else
          mx, my = playeranim.muzzle2(fig)
          playeranim.onShoot2(fig)
        end
        for _, s in ipairs(list) do
          local speed = math.min(T.shotSpeed, (s.speed or T.shotSpeed) * 0.6)
          shots[#shots + 1] = {
            x = mx, y = my,
            vx = math.cos(s.angle) * speed, vy = math.sin(s.angle) * speed,
            life = 1.6,
            dmg = math.max(1, math.floor(T.shotDamage * e.dmgMul + 0.5)),
            tint = s.tint,
          }
        end
        effects.muzzleFlash(mx, my, fig.aimAngle, g.def.flash, g.def.model)
        audio.playAt("shot_revolver", mx, my, 0.75, 0.82)
      end
    end
  end
  if fired then
    e.volleyT = T.volley * (e.ph == 2 and 1.15 or 1)
  end
end

-- Where a beam from (x, y) toward (tx, ty) stops: the first rock, or far off
local function beamEnd(world, x, y, tx, ty)
  local dx, dy = tx - x, ty - y
  local d = math.max(1, hypot(dx, dy))
  dx, dy = dx / d, dy / d
  for s = 0, 900, 2 do
    local bx, by = x + dx * s, y + dy * s
    if world:isSolid(bx, by) then
      return bx, by
    end
  end
  return x + dx * 900, y + dy * 900
end

local function segmentDist(px, py, x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local l2 = dx * dx + dy * dy
  local t = l2 > 0 and math.max(0, math.min(1, ((px - x0) * dx + (py - y0) * dy) / l2)) or 0
  return hypot(px - (x0 + dx * t), py - (y0 + dy * t))
end

-- The crow ---------------------------------------------------------------------------------------------

-- The crow's body box at (x, y) (its middle): what hurts the hunter
local function crowBox(x, y)
  return x - 16 * CROW_SCALE, y - 8 * CROW_SCALE, 32 * CROW_SCALE, 16 * CROW_SCALE
end

-- Where the crow's eye is, drawn at (x, y) facing f
local function crowEye(x, y, f)
  return x + f * 14 * CROW_SCALE, y - 6 * CROW_SCALE
end

local function crowHits(e, x, y, player, dmg, key)
  if player.dead or swoopHit[key] then
    return
  end
  local bx, by, bw, bh = crowBox(x, y)
  local pb = player.body
  if overlaps(bx, by, bw, bh, pb.x, pb.y, pb.w, pb.h) then
    if player:hurt(math.max(1, math.floor(dmg * e.dmgMul + 0.5)), x, y, "darkhunter") then
      player.lastEnemy = e
      swoopHit[key] = true
    end
  end
end

local function bezier(p0, p1, p2, t)
  local u = 1 - t
  return u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1], u * u * p0[2] + 2 * u * t * p1[2] + t * t * p2[2]
end

-- Phase 1 ----------------------------------------------------------------------------------------------

local function startSpecial(e)
  e.sp = { stage = "jump", t = 0, hops = 0 }
end

local function updateSpecial(e, dt, world, player, px, py)
  local sp, b, fig = e.sp, e.body, e.fig
  sp.t = sp.t + dt
  local cx, cy = center(e)
  if sp.stage == "jump" then
    -- Three quick jumps up, each from the top of the last (the Crow Rider
    -- just hangs where he is)
    if e.ph == 1 then
      local collide = collider(e, world)
      b.vx = b.vx * math.exp(-4 * dt)
      b.vy = math.min(b.vy + config.gravity * pcfg.gravityScale * dt, pcfg.maxFallSpeed)
      Body.moveX(b, collide, b.vx * dt, 0)
      if Body.moveY(b, collide, b.vy * dt) then
        if b.vy < 0 then
          sp.blocked = true
        end
        b.vy = 0
      end
    end
    if e.ph == 2 then
      sp.stage, sp.t = "split", 0
    elseif sp.t > 2.5 then
      e.sp = nil -- (something in the way overhead: give it up)
      e.specialT = 3
      return false
    elseif sp.blocked then
      e.sp = nil -- (a roof over him: no room for it)
      e.specialT = 2
      return false
    elseif b.vy >= -40 and sp.hops < 3 then
      sp.hops = sp.hops + 1
      b.vy = -T.jump * 1.12
      fig.anim.flip = 0
      audio.playAt("land", cx, cy, 0.4, 1.6)
    elseif sp.hops >= 3 and b.vy >= -10 then
      sp.stage, sp.t = "split", 0
    end
    return true
  end
  if not sp.figs then
    -- Two shadows dash out of him, one to each side
    sp.figs = { fig }
    sp.pos = { { 0, 0 } }
    for k = 1, 2 do
      local f = newFigure(cx, cy + 9.5, nil)
      f.gun, f.gun2 = fig.gun, fig.gun2
      f.grounded, f.crouched = false, e.ph == 2
      f.facing = fig.facing
      f.rollT, f.rollDir = 0, k == 1 and -1 or 1
      sp.figs[#sp.figs + 1] = f
      -- (far out to either side, one high and one low: the three hang well apart)
      sp.pos[#sp.pos + 1] = { cx, cy, (k == 1 and -1 or 1) * 1150, (k == 1 and -1 or 1) * 160 }
    end
    for _ = 1, 10 do
      effects.particle(cx, cy, (love.math.random() - 0.5) * 140, (love.math.random() - 0.5) * 80, 0.4, { 0.6, 0.3, 0.95 }, 0, true)
    end
    audio.playAt("dh_dash", cx, cy, 0.9, 0.8)
    audio.playAt("dh_voice", cx, cy, 0.6, 1.2)
    sp.stage, sp.t = "split", 0
  end
  b.vx, b.vy = 0, 0 -- (all three hang in the air)
  local a = e.arena
  for k = 2, #sp.figs do
    local p = sp.pos[k]
    p[3] = p[3] * math.exp(-5 * dt)
    p[4] = p[4] * math.exp(-5 * dt)
    p[1] = p[1] + p[3] * dt
    p[2] = p[2] + p[4] * dt
    if a then
      p[1] = math.max(a.x0 + 40, math.min(a.x1 - 40, p[1]))
      p[2] = math.max(a.top + 40, math.min(a.floorY - 30, p[2]))
    end
    if world:isSolid(p[1], p[2]) then
      p[1], p[2] = cx, cy -- (inside rock: back to him)
    end
    local f = sp.figs[k]
    f.body.x, f.body.y = math.floor(p[1] - 4), math.floor(p[2] - (e.ph == 2 and 17 or 9.5))
    f.body.vx = p[3]
    if f.rollT then
      f.rollT = f.rollT + dt
      if f.rollT >= pcfg.rollTime then
        f.rollT = nil
      end
    end
  end
  if sp.stage == "split" and sp.t > 0.25 then
    sp.stage, sp.t = "hold", 0
    sp.hold = 0.55
    -- Phase 1: one of the three fires. The Crow Rider: two of them do
    -- (never the same one twice running: pick from the other two)
    local first = love.math.random(1, 3)
    if first == e.lastFirst then
      first = (first - 1 + love.math.random(1, 2)) % 3 + 1
    end
    e.lastFirst = first
    sp.shooters = { [first] = true }
    if e.ph == 2 then
      sp.shooters[(first + love.math.random(0, 1)) % 3 + 1] = true
    end
    sp.shooter = first
    for k in pairs(sp.shooters) do
      local ex, ey = playeranim.eyes(sp.figs[k])
      audio.playAt("dh_charge", ex, ey, 0.8, 1)
    end
  elseif sp.stage == "hold" then
    if sp.t < 0.35 then
      sp.tx, sp.ty = px, py -- (the aim locks a moment before it fires)
      sp.vx, sp.vy = player.body.vx, player.body.vy
    end
    for _, g in ipairs(sp.figs) do
      local gx = g.body.x + 4
      g.facing = px >= gx and 1 or -1
      g.aimAngle = math.atan2(py - (g.body.y + 7), px - gx)
    end
    if sp.t >= sp.hold then
      local n = 0
      for k in pairs(sp.shooters) do
        n = n + 1
        local ex, ey = playeranim.eyes(sp.figs[k])
        -- (the second beam leads where he is running to)
        local tx, ty = sp.tx + (n > 1 and (sp.vx or 0) * 0.35 or 0), sp.ty
        local x1, y1 = beamEnd(world, ex, ey, tx, ty)
        beams[#beams + 1] = { x0 = ex, y0 = ey, x1 = x1, y1 = y1, life = 0.3 }
        audio.playAt("dh_beam", ex, ey, 1, 1)
        local pcx, pcy = player:center()
        if not player.dead and segmentDist(pcx, pcy, ex, ey, x1, y1) < 7 then
          if player:hurt(math.max(1, math.floor(T.beamDamage * e.dmgMul + 0.5)), ex, ey, "darkhunter") then
            player.lastEnemy = e
          end
        end
        for _ = 1, 8 do
          effects.particle(x1, y1, (love.math.random() - 0.5) * 160, -love.math.random() * 100, 0.35, { 1, 0.3, 0.25 }, 300, true)
        end
      end
      require("src.camera").shake(0.25)
      sp.stage, sp.t = "end", 0
    end
  elseif sp.stage == "end" and sp.t > 0.3 then
    for k = 2, #sp.figs do
      local f = sp.figs[k]
      for _ = 1, 8 do
        effects.particle(f.body.x + 4, f.body.y + 9, (love.math.random() - 0.5) * 60, (love.math.random() - 0.5) * 60, 0.5, { 0.45, 0.2, 0.7 }, -20, true)
      end
    end
    e.sp = nil
    e.specialT = (e.ph == 2 and 8 or 7) + love.math.random() * 4
  end
  return true
end

-- On foot: keep the distance, strafe, jump and dash, and shoot
local function moveHunter(e, dt, world, player, px, py)
  local b, fig = e.body, e.fig
  local collide = collider(e, world)
  local cx, cy = center(e)
  local a = e.arena
  e.grounded = Body.isGrounded(b, collide) and b.vy >= 0
  if e.grounded then
    e.jumps = T.airJumps
  end
  local dx = px - cx
  local dist = math.abs(dx)
  local dir
  e.strafeT = e.strafeT - dt
  if e.strafeT <= 0 then
    e.strafeT = 0.5 + love.math.random() * 0.8
    e.strafe = love.math.random(-1, 1)
  end
  if dist > T.keep + 40 then
    dir = sign(dx) -- closing in
  elseif dist < T.keep - 50 then
    dir = -sign(dx) * 0.7 -- backing off, but never running
  else
    dir = e.strafe * 0.6
  end
  -- Fallen through a hole in the arena floor: straight back up to it
  local low = a and b.y + b.h > a.floorY + 6
  if low then
    dir = sign(a.cx - cx) * 0.4
    if e.grounded or b.vy > -30 then
      if e.grounded then
        e.jumps = T.airJumps
      end
      if e.jumps > 0 then
        b.vy = -T.jump * 1.05
        e.jumps = e.jumps - 1
        fig.anim.flip = not e.grounded and 0 or nil
      end
    end
  end
  -- A gap in the floor ahead: over it if the hunter is across it, else stop at the edge
  if e.grounded and dir ~= 0 and not low then
    local ax = math.floor(cx + sign(dir) * 8)
    local floor = false
    for yy = b.y + b.h, b.y + b.h + 36 do
      if world:isSolid(ax, yy) then
        floor = true
        break
      end
    end
    if not floor then
      if sign(dx) == sign(dir) and dist > 40 then
        b.vy = -T.jump
        e.jumps = e.jumps - 1
        b.vx = sign(dir) * T.speed
      else
        dir = 0
        b.vx = 0
      end
    end
  end
  if a then
    if (dir < 0 and cx < a.x0 + 30) or (dir > 0 and cx > a.x1 - 30) then
      dir = 0
      -- (backed against the wall: over the hunter's head instead)
      if e.grounded and dist < T.keep then
        b.vy = -T.jump * 1.1
        e.jumps = e.jumps - 1
        b.vx = sign(dx) * T.speed * 1.4
      end
    end
  end
  local dashing = e.dashT and e.dashT > 0
  if dashing then
    e.dashT = e.dashT - dt
    b.vx = e.dashDir * T.dash
    b.vy = math.min(b.vy, 10)
    fig.rollT = (1 - e.dashT / T.dashTime) * pcfg.rollTime
    fig.rollDir = e.dashDir
    if e.dashT <= 0 then
      fig.rollT = nil
    end
  else
    local want = dir * T.speed
    local accel = e.grounded and 1400 or 900
    if b.vx < want then
      b.vx = math.min(want, b.vx + accel * dt)
    else
      b.vx = math.max(want, b.vx - accel * dt)
    end
  end
  -- Jumps: up to the hunter when he is higher, now and then to dodge
  local above = py < cy - 36
  if not dashing and e.jumps > 0 then
    if e.grounded and ((above and love.math.random() < dt * 2.5) or love.math.random() < dt * 0.5) then
      b.vy = -T.jump
      e.jumps = e.jumps - 1
    elseif not e.grounded and b.vy > -20 and e.jumps < T.airJumps and ((above and py < cy - 20) or love.math.random() < dt * 0.6) then
      b.vy = -T.jump * 0.92
      e.jumps = e.jumps - 1
      fig.anim.flip = 0 -- (the twirl of a jump in the air)
    end
  end
  -- An air dash, somersaulting, to get back to his distance or out of the way
  -- (never while he is climbing out of a hole)
  e.dashCd = e.dashCd - dt
  if not dashing and not low and not e.grounded and e.dashCd <= 0 and love.math.random() < dt * 1.4 then
    e.dashCd = 1.6 + love.math.random()
    e.dashT = T.dashTime
    e.dashDir = dist > T.keep and sign(dx) or -sign(dx)
    if a and ((e.dashDir < 0 and cx < a.x0 + 80) or (e.dashDir > 0 and cx > a.x1 - 80)) then
      e.dashDir = -e.dashDir
    end
    audio.playAt("dh_dash", cx, cy, 0.8, 1)
  end
  b.vy = math.min(b.vy + config.gravity * pcfg.gravityScale * dt, pcfg.maxFallSpeed)
  if Body.moveX(b, collide, b.vx * dt, pcfg.stepHeight) then
    b.vx = 0
    if e.grounded and e.jumps > 0 then
      b.vy = -T.jump -- (a wall in the way: over it)
      e.jumps = e.jumps - 1
    end
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = 0
  end
  if e.grounded and b.vy >= 0 then
    Body.snapDown(b, collide, pcfg.stepHeight)
  end
  return dashing
end

-- Phase 2: the crow hangs over the hunter on its wingbeats, now and then diving
local function moveRider(e, dt, world, player, px, py)
  local b = e.body
  local collide = collider(e, world)
  local cx, cy = center(e)
  local a = e.arena
  local sw = e.swoop
  if sw then
    sw.t = sw.t + dt
    if sw.stage == "wind" then
      b.vx, b.vy = b.vx * math.exp(-6 * dt), -30
      Body.moveY(b, collide, b.vy * dt)
      -- (the wind-up: the crow rears back with its wings flung wide and shrieks)
      if sw.t < 0.06 then
        audio.playAt("rider_caw", cx, cy, 0.8, 1.15)
      end
      if sw.t >= 0.4 then
        local tx, ty = px, py
        local side = sign(tx - cx)
        -- (the dive bottoms out just over the floor and climbs away past him,
        -- all inside the arena)
        local function inside(x, y)
          if not a then
            return { x, y }
          end
          return { math.max(a.x0 + 24, math.min(a.x1 - 24, x)), math.max(a.top + 24, math.min(a.floorY - 16, y)) }
        end
        sw.stage, sw.t = "dive", 0
        audio.playAt("rider_swoop", cx, cy, 1, 1)
        sw.p0 = { cx, cy }
        sw.p1 = inside(tx, ty + 70)
        sw.p2 = inside(tx + side * 160, ty - 120)
        swoopHit.dive = nil
        audio.playAt("bat_screech", cx, cy, 0.9, 0.45)
      end
    else
      local k = math.min(1, sw.t / 0.62)
      local nx, ny = bezier(sw.p0, sw.p1, sw.p2, k)
      b.vx, b.vy = (nx - cx) / math.max(dt, 1e-3), (ny - cy) / math.max(dt, 1e-3)
      b.x, b.y = math.floor(nx - b.w / 2), math.floor(ny - b.h / 2)
      crowHits(e, nx, ny, player, T.swoopDamage, "dive")
      if k >= 1 then
        e.swoop = nil
        e.swoopCd = 4.5 + love.math.random() * 3
      end
    end
    return true
  end
  -- Hover: off to one side of the hunter and well above him
  e.sideT = (e.sideT or 0) - dt
  if e.sideT <= 0 then
    e.sideT = 2.5 + love.math.random() * 2
    e.side = love.math.random() < 0.5 and -1 or 1
  end
  local tx = px + e.side * 130
  local ty = py - T.hover + math.sin(love.timer.getTime() * 1.7) * 12
  if a then
    tx = math.max(a.x0 + 30, math.min(a.x1 - 30, tx))
    ty = math.max(a.top + 30, math.min(a.floorY - 50, ty))
  end
  b.vx = b.vx + ((tx - cx) * 4 - b.vx * 2.2) * dt
  b.vy = b.vy + ((ty - cy) * 4 - b.vy * 2.2) * dt
  local sp = hypot(b.vx, b.vy)
  if sp > 230 then
    b.vx, b.vy = b.vx / sp * 230, b.vy / sp * 230
  end
  if Body.moveX(b, collide, b.vx * dt, 0) then
    b.vx = -b.vx * 0.3
  end
  if Body.moveY(b, collide, b.vy * dt) then
    b.vy = -b.vy * 0.3
  end
  e.swoopCd = (e.swoopCd or 3) - dt
  if e.swoopCd <= 0 and not e.sp then
    e.swoop = { stage = "wind", t = 0 }
  end
  return false
end

-- The rider sits astride the crow's back
local function seatRider(e)
  local b, fig = e.body, e.fig
  local cx, cy = center(e)
  fig.body.x = math.floor(cx - 4 - e.facing * 2)
  fig.body.y = math.floor(cy - 19 + 2)
  fig.body.vx, fig.body.vy = b.vx, b.vy
  fig.grounded, fig.crouched = true, true
end

local function becomeRider(e)
  e.ph, e.mode = 2, "fight"
  e.maxHp = e.maxHp * 2
  e.hp = e.maxHp
  e.bossName = "The Crow Rider"
  local cx, cy = center(e)
  local b = e.body
  b.w, b.h = 40, 32
  b.x, b.y = math.floor(cx - 20), math.floor(cy - 26)
  b.vx, b.vy = 0, -60
  b.remX, b.remY = 0, 0
  removePhysics(e) -- (its stand-in is made again at the new size)
  e.collide = nil
  e.fig.rollT = nil
  e.flap = 0
  e.swoopCd = 4
  e.specialT = 6
  e.side = 1
  e.sideT = 0
  require("src.hud").showBanner("The Crow Rider", "He rises again, on black wings")
end

local function updateDarkHunter(e, dt, world, player, px, py)
  ensure(e, world)
  local b, fig = e.body, e.fig
  local cx, cy = center(e)
  if e.state == "idle" or e.state == "sleep" then
    -- (waits on his feet until the fight starts)
    local collide = collider(e, world)
    b.vy = math.min(b.vy + config.gravity * dt, 450)
    if Body.moveY(b, collide, b.vy * dt) then
      b.vy = 0
    end
    fig.body.x, fig.body.y = b.x, b.y
    playeranim.update(fig, dt)
    return
  end
  for _, g in ipairs(e.guns) do
    g:update(dt)
  end
  e.facing = px >= cx and 1 or -1
  fig.facing = e.facing
  e.volleyT = math.max(0, e.volleyT - dt)
  local wasFlap = math.sin(e.flap or 0)
  e.flap = (e.flap or 0) + dt * (e.swoop and (e.swoop.stage == "dive" and 4 or 16) or 9)
  if e.ph == 2 and wasFlap < 0 and math.sin(e.flap) >= 0 then
    audio.playAt("rider_flap", cx, cy, 0.5, 1)
  end
  -- (his voice, now and then, while he fights)
  e.voiceT = (e.voiceT or 4) - dt
  if e.voiceT <= 0 and e.mode == "fight" then
    e.voiceT = 6 + love.math.random() * 5
    audio.playAt(e.ph == 2 and "rider_caw" or "dh_voice", cx, cy, 0.8, 0.9 + love.math.random() * 0.2)
  end

  if e.mode == "kneel" then
    -- On his knees, guns down, for a breath; then the crow comes for him
    local collide = collider(e, world)
    b.vx = b.vx * math.exp(-8 * dt)
    b.vy = math.min(b.vy + config.gravity * dt, 450)
    Body.moveX(b, collide, b.vx * dt, 0)
    if Body.moveY(b, collide, b.vy * dt) then
      b.vy = 0
    end
    fig.body.x, fig.body.y, fig.body.vx, fig.body.vy = b.x, b.y, b.vx, b.vy
    fig.grounded, fig.crouched, fig.rollT = true, true, nil
    fig.aimAngle = e.facing > 0 and 1.2 or math.pi - 1.2
    e.modeT = e.modeT - dt
    if e.modeT <= 0 then
      local a = e.arena
      local fromLeft = px > cx
      local sx = a and (fromLeft and a.x0 + 30 or a.x1 - 30) or cx + (fromLeft and -300 or 300)
      local sy = a and a.top + 20 or cy - 220
      e.mode, e.modeT = "crow", T.crowIn
      e.crow = { p0 = { sx, sy }, p1 = { px, math.min((a and a.floorY or cy) - 12, py + 30) }, p2 = { cx, cy - 6 }, x = sx, y = sy }
      swoopHit.arrive = nil
      audio.playAt("rider_caw", sx, sy, 1, 0.9)
    end
    playeranim.update(fig, dt)
    return
  elseif e.mode == "crow" then
    -- The crow swoops down through the arena to him (low across the hunter's ground)
    e.modeT = e.modeT - dt
    local k = 1 - math.max(0, e.modeT) / T.crowIn
    local c = e.crow
    local nx, ny = bezier(c.p0, c.p1, c.p2, k * k * (3 - 2 * k))
    c.vx = (nx - c.x) / math.max(dt, 1e-3)
    c.x, c.y = nx, ny
    crowHits(e, nx, ny, player, T.swoopDamage, "arrive")
    if e.modeT <= 0 then
      e.mode, e.modeT = "mount", 0.45
      audio.playAt("land", cx, cy, 0.8, 0.8)
    end
    playeranim.update(fig, dt)
    return
  elseif e.mode == "mount" then
    -- He leaps onto its back; it beats its wings and lifts him
    e.modeT = e.modeT - dt
    local c = e.crow
    if not e.leapt then
      e.leapt = true
      fig.anim.flip = 0
    end
    if e.modeT <= 0 then
      e.crow = nil
      becomeRider(e)
    else
      c.y = c.y - 20 * dt
    end
    playeranim.update(fig, dt)
    return
  end

  -- The fight
  local busy
  if e.sp then
    busy = updateSpecial(e, dt, world, player, px, py)
  else
    e.specialT = e.specialT - dt
    local inArena = not e.arena or b.y + b.h <= e.arena.floorY + 6
    if e.specialT <= 0 and inArena and (e.ph == 2 and not e.swoop or (e.ph == 1 and e.grounded)) then
      startSpecial(e)
    end
  end
  local dashing = false
  if not busy then
    if e.ph == 1 then
      dashing = moveHunter(e, dt, world, player, px, py)
    else
      dashing = moveRider(e, dt, world, player, px, py)
    end
  elseif e.ph == 2 then
    b.vx, b.vy = 0, 0
  end
  if e.ph == 1 then
    fig.body.x, fig.body.y, fig.body.vx, fig.body.vy = b.x, b.y, b.vx, b.vy
    fig.grounded, fig.crouched = e.grounded and not busy, false
  else
    seatRider(e)
  end
  -- Aim the way the hunter aims: from the shoulder, straight at him
  local sx, sy = playeranim.shoulder(fig)
  local pcx, pcy = player:center()
  fig.aimAngle = math.atan2(pcy - sy, pcx - sx)
  if not busy and not dashing and e.volleyT <= 0 and e.seesPlayer and not player.dead then
    fireVolley(e, world)
  end
  playeranim.update(fig, dt)
end

-- Drawing ---------------------------------------------------------------------------------------------

local function drawCrow(x, y, f, flap, alpha, dive)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(CROW_SCALE)
  love.graphics.translate(-x, -y)
  alpha = alpha or 1
  local function col(c, k)
    k = k or 1
    love.graphics.setColor(c[1] * k, c[2] * k, c[3] * k, alpha)
  end
  local beat = dive and -0.6 or math.sin(flap)
  local function wing(far)
    local k = far and 0.6 or 1
    local sx, sy = x + f * 2, y - 3
    local span = far and 24 or 30
    local ang = -0.25 - beat * 0.95
    local tipX, tipY = sx - f * math.cos(ang) * span * 0.55, sy + math.sin(ang) * span
    local midX, midY = sx - f * span * 0.5, sy + math.sin(ang) * span * 0.45
    col(CROW.body, k)
    love.graphics.polygon("fill", sx, sy, sx - f * 8, sy + 3, midX, midY + 2, tipX, tipY, midX + f * 4, midY - 2)
    -- feather tips
    for q = 0, 3 do
      local t = q / 3
      local fx, fy = midX + (tipX - midX) * t, midY + (tipY - midY) * t
      col(CROW.dark, k)
      love.graphics.polygon("fill", fx, fy, fx - f * 3, fy + 4 - beat * 2, fx + f * 1, fy + 3)
    end
    col(CROW.sheen, k * 0.8)
    love.graphics.line(sx, sy, midX + f * 2, midY)
  end
  wing(true)
  -- tail fan
  col(CROW.dark)
  love.graphics.polygon("fill", x - f * 10, y - 1, x - f * 22, y - 4, x - f * 23, y + 2, x - f * 20, y + 5, x - f * 10, y + 3)
  -- body
  col(CROW.body)
  love.graphics.ellipse("fill", x, y, 13, 6)
  col(CROW.sheen, 0.9)
  love.graphics.ellipse("fill", x + f * 2, y - 3, 8, 1.5)
  -- head and beak
  col(CROW.body)
  love.graphics.circle("fill", x + f * 13, y - 4, 4.5)
  col(CROW.beak)
  love.graphics.polygon("fill", x + f * 16, y - 6, x + f * 23, y - 3, x + f * 16, y - 2)
  love.graphics.setColor(CROW.eye[1], CROW.eye[2], CROW.eye[3], alpha)
  love.graphics.rectangle("fill", math.floor(x + f * 14), math.floor(y - 6), 1, 1)
  -- talons
  col(CROW.beak)
  love.graphics.line(x - f * 2, y + 5, x - f * 3, y + 9)
  love.graphics.line(x + f * 3, y + 5, x + f * 2, y + 9)
  wing(false)
  love.graphics.pop()
end

-- The crow's eye and a violet sheen along its back, glowing in the dark
local function drawCrowGlow(x, y, f, alpha)
  local ex, ey = crowEye(x, y, f)
  love.graphics.setColor(CROW.eye[1], CROW.eye[2], CROW.eye[3], 0.4 * alpha)
  love.graphics.circle("fill", ex, ey, 2.5)
  love.graphics.setColor(1, 0.8, 1, alpha)
  love.graphics.rectangle("fill", math.floor(ex), math.floor(ey), 1, 1)
  love.graphics.setColor(0.55, 0.3, 0.9, 0.25 * alpha)
  love.graphics.ellipse("fill", x, y - 4 * CROW_SCALE, 9 * CROW_SCALE, 1.5)
end

local function eachFigure(e, fn)
  local sp = e.sp
  if sp and sp.figs then
    for k, f in ipairs(sp.figs) do
      fn(f, k, sp)
    end
  else
    fn(e.fig, 1, nil)
  end
end

local function drawDarkHunter(e)
  ensure(e, nil)
  local fig = e.fig
  if e.mode == "crow" or e.mode == "mount" then
    local c = e.crow
    drawCrow(c.x, c.y, sign(c.vx or 1), (e.flap or 0) * 1.4, 1, false)
  end
  eachFigure(e, function(f, k, sp)
    local red = sp and sp.stage == "hold" and sp.shooters and sp.shooters[k] and sp.t > 0.1
    local shadow = k > 1
    if e.ph == 2 then
      local fx, fy = f.body.x + 4 + e.facing * 2, f.body.y + 17
      drawCrow(fx, fy + 4, e.facing, e.flap or 0, shadow and 0.6 or 1, e.swoop and e.swoop.stage == "dive")
    end
    local pal = shadow and (red and PAL_SHADOW_RED or PAL_SHADOW) or (red and PAL_RED or PAL)
    playeranim.drawStyled(f, pal)
  end)
  if e.flash > 0 then
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.rectangle("fill", e.body.x, e.body.y, e.body.w, e.body.h)
  end
end

local function drawDarkHunterGlow(e)
  ensure(e, nil)
  if e.crow then
    drawCrowGlow(e.crow.x, e.crow.y, sign(e.crow.vx or 1), 1)
  end
  eachFigure(e, function(f, k, sp)
    if e.ph == 2 then
      drawCrowGlow(f.body.x + 4 + e.facing * 2, f.body.y + 21, e.facing, k > 1 and 0.6 or 1)
    end
    local red = sp and sp.stage == "hold" and sp.shooters and sp.shooters[k] and sp.t > 0.1
    playeranim.drawStyled(f, red and PAL_RED or PAL, true)
    if red then
      -- the eye flares as the shot comes
      local ex, ey = playeranim.eyes(f)
      local r = 2 + 3 * (sp.t / sp.hold)
      love.graphics.setColor(1, 0.15, 0.1, 0.35)
      love.graphics.circle("fill", ex, ey, r)
      love.graphics.setColor(1, 0.6, 0.5, 0.8)
      love.graphics.rectangle("fill", math.floor(ex), math.floor(ey), 1, 1)
    end
  end)
end

enemies.UPDATE.darkhunter = updateDarkHunter
enemies.DRAW.darkhunter = drawDarkHunter
enemies.GLOW.darkhunter = drawDarkHunterGlow

-- His bullets and beams, every frame while he lives -----------------------------------------------------

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  -- His own music while he fights
  local fighting = false
  for _, e in ipairs(enemies.all()) do
    if e.kind == "darkhunter" and not e.dead and e.state ~= "idle" and e.state ~= "sleep" then
      fighting = true
    end
  end
  audio.setBoss(fighting)
  if #shots == 0 and #beams == 0 then
    return
  end
  local pb = player.body
  for i = #shots, 1, -1 do
    local s = shots[i]
    s.life = s.life - dt
    local steps = math.max(1, math.ceil(math.max(math.abs(s.vx), math.abs(s.vy)) * dt / 3))
    local gone = s.life <= 0
    for _ = 1, steps do
      if gone then
        break
      end
      s.x, s.y = s.x + s.vx * dt / steps, s.y + s.vy * dt / steps
      if world:isSolid(s.x, s.y) then
        effects.particle(s.x, s.y, -s.vx * 0.1, -s.vy * 0.1, 0.2, { 0.8, 0.5, 1 }, 200, true)
        gone = true
      elseif not player.dead and overlaps(s.x - 1, s.y - 1, 2, 2, pb.x, pb.y, pb.w, pb.h) then
        player:hurt(s.dmg, s.x - s.vx * 0.05, s.y - s.vy * 0.05, "darkhunter")
        gone = true
      end
    end
    if gone then
      table.remove(shots, i)
    end
  end
  for i = #beams, 1, -1 do
    beams[i].life = beams[i].life - dt
    if beams[i].life <= 0 then
      table.remove(beams, i)
    end
  end
end

local prevEmissive = enemies.afterEmissive
enemies.afterEmissive = function(view)
  if prevEmissive then
    prevEmissive(view)
  end
  for _, s in ipairs(shots) do
    local d = math.max(1, hypot(s.vx, s.vy))
    local tx, ty = s.x - s.vx / d * 5, s.y - s.vy / d * 5
    local t = s.tint
    love.graphics.setColor(t and t[1] or 0.8, t and t[2] or 0.45, t and t[3] or 1, 0.55)
    love.graphics.line(tx, ty, s.x, s.y)
    love.graphics.setColor(1, 0.9, 1, 1)
    love.graphics.rectangle("fill", math.floor(s.x), math.floor(s.y), 1, 1)
  end
  for _, bm in ipairs(beams) do
    local k = bm.life / 0.3
    love.graphics.setLineWidth(1 + 3 * k)
    love.graphics.setColor(1, 0.15, 0.1, 0.5 * k)
    love.graphics.line(bm.x0, bm.y0, bm.x1, bm.y1)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 0.85, 0.8, k)
    love.graphics.line(bm.x0, bm.y0, bm.x1, bm.y1)
  end
end

-- (a new fight, or none: nothing of his left flying)
local prevClear = enemies.clear
enemies.clear = function()
  prevClear()
  shots, beams, swoopHit = {}, {}, {}
  audio.setBoss(false)
end

return true
