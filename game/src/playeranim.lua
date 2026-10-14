-- Procedural, limb-based animation for the hunter (a Van Helsing figure):
-- instead of sprite frames, a lanky skeleton (hips, knees, feet, shoulders,
-- elbows) is posed every frame and drawn as pixel limbs on the low-res canvas.
-- A long coat and its mantle follow the motion with simple secondary physics.
--
-- Positions are relative to the hitbox: cx = horizontal centre, fy = feet.
local audio = require("src.audio")
local config = require("src.config")
local effects = require("src.effects")

local cfg = config.player

local anim = {}

-- Limb lengths in pixels
local THIGH, SHIN = 5.3, 5.3
local UPPER_ARM, FOREARM = 3.8, 3.8
local HIP_HEIGHT = 9.9 -- hip above the feet when standing
local CROUCH_HIP = 5.6
local SLIDE_HIP = 4.2
local ROLL_HIP = 4.6 -- tucked into a ball for the dodge roll
local TORSO = 6.4 -- hip to neck
-- How each kind of gun (its def.model) is held:
--   reach    how far in front of the shoulder the trigger hand holds the grip
--   support  where the other hand goes, along the barrel from the grip
--            (nil: both hands on the grip, pistol style)
--   pull     how far the recoil kick pulls the gun back
--   tip      how far the recoil kick tips the barrel up (radians)
-- Long guns are shouldered (short reach) so the support hand reaches the fore-end.
local HOLDS = {
  revolver = { reach = 5.8, pull = 2.6, tip = 0.45 },
  pistol = { reach = 5.8, pull = 2.0, tip = 0.35 },
  shotgun = { reach = 3.4, support = 4.2, pull = 1.6, tip = 0.3 },
  automatic = { reach = 3.4, support = 4.0, pull = 1.4, tip = 0.22 },
  gatling = { reach = 3.0, support = 5.5, pull = 1.0, tip = 0.1 }, -- heavy: hugged in close, barely kicks
}
local TAIL_LINKS, TAIL_LINK = 4, 2.2

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

-- Reload animations, one per gun model, driven by the gun's reload progress
-- (0 -> 1 over its reload time, so reload speed modifiers speed them up and
-- slow them down). Keyframes ease from one to the next:
--   p      progress at this keyframe
--   tilt   muzzle raised by this many radians (negative: dipped)
--   reach  extra distance of the grip from the shoulder
--   kind   where the support hand goes: "gun" (a = along the barrel from the
--          grip, b = down from it) or "belt" (a = in front of the hips, b = below them)
--   carry  the hand is holding a fresh round / magazine
-- Events fire once per reload as progress passes them.
local RELOAD = {
  -- Tip the muzzle up, tap out the shells, fetch rounds from the belt, thumb
  -- them in and snap the cylinder shut
  revolver = {
    keys = {
      { p = 0.00, tilt = 0.0, reach = 0.0, kind = "gun", a = -1.3, b = 0 },
      { p = 0.12, tilt = 0.9, reach = -0.5, kind = "gun", a = 2.5, b = 1.0 },
      { p = 0.30, tilt = 0.9, reach = -0.5, kind = "gun", a = 2.5, b = 1.5 },
      { p = 0.42, tilt = 0.5, reach = 0.0, kind = "belt", a = 3, b = 0 },
      { p = 0.60, tilt = 0.35, reach = 0.0, kind = "belt", a = 3, b = 0, carry = true },
      { p = 0.80, tilt = 0.35, reach = 0.0, kind = "gun", a = 2.5, b = 1.0, carry = true },
      { p = 0.90, tilt = 0.0, reach = 0.5, kind = "gun", a = 2.5, b = 1.0 },
      { p = 1.00, tilt = 0.0, reach = 0.0, kind = "gun", a = -1.3, b = 0 },
    },
    events = { { 0.28, "eject" }, { 0.72, "click" }, { 0.90, "snap" } },
  },
  -- Break the barrels open, shells pop out, two fresh shells from the belt,
  -- and snap it shut with a flick
  shotgun = {
    keys = {
      { p = 0.00, tilt = 0.0, reach = 0.0, kind = "gun", a = 4.2, b = 0.8 },
      { p = 0.12, tilt = -0.55, reach = -0.5, kind = "gun", a = 4.2, b = 0.8 },
      { p = 0.30, tilt = -0.55, reach = -0.5, kind = "gun", a = 1.5, b = 1.0 },
      { p = 0.42, tilt = -0.4, reach = 0.0, kind = "belt", a = 3, b = 0 },
      { p = 0.62, tilt = -0.4, reach = 0.0, kind = "belt", a = 3, b = 0, carry = true },
      { p = 0.76, tilt = -0.4, reach = 0.0, kind = "gun", a = 1.5, b = 1.0, carry = true },
      { p = 0.88, tilt = 0.1, reach = 0.4, kind = "gun", a = 4.2, b = 0.8 },
      { p = 1.00, tilt = 0.0, reach = 0.0, kind = "gun", a = 4.2, b = 0.8 },
    },
    events = { { 0.30, "eject" }, { 0.72, "click" }, { 0.88, "snap" } },
  },
  -- Muzzle up, a stripper clip fetched from the belt and pressed in from the
  -- top of the receiver, then the slide racked
  pistol = {
    keys = {
      { p = 0.00, tilt = 0.0, reach = 0.0, kind = "gun", a = -1.3, b = 0 },
      { p = 0.15, tilt = 0.4, reach = -0.3, kind = "gun", a = -1.0, b = 0.5 },
      { p = 0.30, tilt = 0.6, reach = -0.3, kind = "belt", a = 3, b = 0 },
      { p = 0.55, tilt = 0.6, reach = 0.0, kind = "belt", a = 3, b = 0, carry = true },
      { p = 0.72, tilt = 0.5, reach = 0.0, kind = "gun", a = 3.0, b = -1.2, carry = true },
      { p = 0.85, tilt = 0.2, reach = 0.0, kind = "gun", a = 3.0, b = -0.5 },
      { p = 0.93, tilt = 0.0, reach = 0.3, kind = "gun", a = 1.0, b = 0 },
      { p = 1.00, tilt = 0.0, reach = 0.0, kind = "gun", a = -1.3, b = 0 },
    },
    events = { { 0.74, "click" }, { 0.93, "snap" } },
  },
  -- Drop the drum, a new one from the belt, slap it on, haul back the
  -- charging handle
  automatic = {
    keys = {
      { p = 0.00, tilt = 0.0, reach = 0.0, kind = "gun", a = 4.0, b = 0.8 },
      { p = 0.12, tilt = 0.3, reach = -0.6, kind = "gun", a = 2.2, b = 2.2 },
      { p = 0.25, tilt = 0.3, reach = -0.6, kind = "gun", a = 2.2, b = 3.0 },
      { p = 0.40, tilt = 0.2, reach = 0.0, kind = "belt", a = 4, b = -1 },
      { p = 0.60, tilt = 0.2, reach = 0.0, kind = "belt", a = 4, b = -1, carry = true },
      { p = 0.75, tilt = 0.3, reach = 0.0, kind = "gun", a = 2.2, b = 2.2, carry = true },
      { p = 0.88, tilt = 0.1, reach = -0.4, kind = "gun", a = -0.5, b = -0.7 },
      { p = 0.95, tilt = 0.0, reach = 0.2, kind = "gun", a = 4.0, b = 0.8 },
      { p = 1.00, tilt = 0.0, reach = 0.0, kind = "gun", a = 4.0, b = 0.8 },
    },
    events = { { 0.24, "drum" }, { 0.76, "click" }, { 0.93, "snap" } },
  },
}

-- The Gatling's hopper comes off and goes on like the machine gun's drum
RELOAD.gatling = RELOAD.automatic

local function smooth(t)
  return t * t * (3 - 2 * t)
end

-- The two keyframes around progress p and how far between them (eased)
local function reloadKeys(model, p)
  local keys = (RELOAD[model] or RELOAD.revolver).keys
  for i = 1, #keys - 1 do
    local k0, k1 = keys[i], keys[i + 1]
    if p <= k1.p then
      return k0, k1, smooth(clamp((p - k0.p) / (k1.p - k0.p), 0, 1))
    end
  end
  local last = keys[#keys]
  return last, last, 0
end
-- Dark, desaturated clothing with a few accents (grey mantle, eyes, silver)
local COLORS = {
  coat = { 0.15, 0.13, 0.17 },
  coatLight = { 0.27, 0.23, 0.30 },
  coatDark = { 0.09, 0.08, 0.11 },
  lining = { 0.20, 0.80, 0.66 }, -- the ether's teal (the fuser's colour)
  mantle = { 0.64, 0.63, 0.62 },
  mantleLight = { 0.78, 0.77, 0.75 },
  mantleDark = { 0.44, 0.43, 0.45 },
  trousers = { 0.20, 0.19, 0.24 },
  trousersDark = { 0.13, 0.12, 0.16 },
  boots = { 0.09, 0.07, 0.08 },
  bootsDark = { 0.06, 0.05, 0.06 },
  buckle = { 0.70, 0.72, 0.78 },
  glove = { 0.10, 0.08, 0.09 },
  hat = { 0.11, 0.09, 0.11 },
  hatLight = { 0.22, 0.19, 0.23 },
  hatBand = { 0.30, 0.24, 0.18 },
  shadow = { 0.03, 0.02, 0.04 }, -- under the brim
  eye = { 1.0, 0.86, 0.48 }, -- glowing
  gun = { 0.17, 0.17, 0.21 },
  gunMid = { 0.36, 0.36, 0.42 },
  silver = { 0.80, 0.82, 0.88 },
  grip = { 0.30, 0.17, 0.11 },
}


function anim.new()
  return {
    phase = 0, -- walk cycle, advanced by distance walked
    time = 0,
    squash = 0, -- landing dip, 1 -> 0
    recoil = 0, -- gun kick, 1 -> 0
    hurt = 0, -- stagger after a hit, 1 -> 0
    hurtDir = 0, -- the way the hit threw him
    deathT = nil, -- seconds since dying (nil while alive)
    gone = false, -- the body has burst and is no longer drawn
    flip = nil, -- double-jump twirl, 0 -> 1
    coatX = 0, -- coat-tail trailing offset (spring-smoothed)
    coatY = 0,
    mantleTail = nil, -- chain of points, created on first update
    lastX = nil,
    lastVy = 0,
    wasGrounded = true,
  }
end

function anim.onShoot(player)
  -- Light guns kick a little on every shot; heavy ones kick hard
  local a = player.anim
  a.recoil = math.max(a.recoil, player.gun.def.kick)
end

local function gunLength(player)
  return player.gun and player.gun.def.length or 8.8
end

local function gunHold(player)
  return HOLDS[player.gun and player.gun.def.model or "revolver"] or HOLDS.revolver
end

-- Body landmarks shared by drawing, the gun/muzzle position and lighting
local function torso(player)
  local a, b = player.anim, player.body
  local cx, fy = b.x + b.w / 2, b.y + b.h
  local hip = HIP_HEIGHT
  if player.sliding then
    hip = SLIDE_HIP
  elseif player.crouched then
    hip = CROUCH_HIP
  end
  local dip = a.squash * 2.6
  if a.walking then
    dip = dip + (1 - math.abs(math.cos(a.phase))) * (player.crouched and 0.6 or 1.1)
  elseif player.grounded and not player.crouched then
    dip = dip + (math.sin(a.time * 2.2) * 0.5 + 0.5) * 0.56 -- breathing
  end
  local lean = clamp(b.vx / cfg.walkSpeed, -1.2, 1.2) * 1.4
  local torsoLen = TORSO
  if player.rollT then
    -- Hunched right over, head tucked in
    hip, dip = ROLL_HIP, 0
    lean = player.rollDir * 3.8
    torsoLen = TORSO - 2.8
  elseif player.sliding then
    -- Lean back against the direction of travel
    lean = -(b.vx >= 0 and 1 or -1) * 3.2
    torsoLen = TORSO - 0.8
  elseif player.crouched then
    lean = lean * 0.5 + player.facing * 1.4
    torsoLen = TORSO - 0.6
  end
  -- A hit whips the upper body back; a kick throws it back for balance
  lean = lean - a.hurtDir * a.hurt * 3
  dip = dip + a.hurt * 1.2
  if player.kickTimer > 0 then
    lean = lean - player.facing * math.sin(player.kickTimer / cfg.kickDuration * math.pi) * 1.6
  end
  local hipX, hipY = cx, fy - hip + dip
  local neckX, neckY = hipX + lean, hipY - torsoLen
  return cx, fy, hipX, hipY, neckX, neckY
end

function anim.shoulder(player)
  local _, _, _, _, neckX, neckY = torso(player)
  return neckX, neckY + 1.3
end

-- Where the bullet leaves the barrel (ignores the cosmetic recoil kick)
function anim.muzzle(player)
  local sx, sy = anim.shoulder(player)
  local dx, dy = math.cos(player.aimAngle), math.sin(player.aimAngle)
  local len = gunHold(player).reach + gunLength(player)
  return sx + dx * len, sy + dy * len
end

-- Mantle tail: a short verlet chain of cloth hanging from the back of the mantle
local function updateMantleTail(player, dt)
  local a, b = player.anim, player.body
  local _, _, _, _, neckX, neckY = torso(player)
  local ax, ay = neckX - player.facing * 2.0, neckY + 3.5
  if not a.mantleTail then
    a.mantleTail = {}
    for i = 1, TAIL_LINKS do
      a.mantleTail[i] = { x = ax - player.facing * i * TAIL_LINK, y = ay, px = ax - player.facing * i * TAIL_LINK, py = ay }
    end
  end
  local s = a.mantleTail
  s[1].x, s[1].y, s[1].px, s[1].py = ax, ay, ax, ay
  -- Air drag pulls the cloth toward "behind" the motion; a little flutter
  local windX = -b.vx * 0.9 + math.sin(a.time * 7) * 14
  local windY = -b.vy * 0.4
  for i = 2, TAIL_LINKS do
    local p = s[i]
    local vx, vy = (p.x - p.px) * 0.92, (p.y - p.py) * 0.92
    p.px, p.py = p.x, p.y
    p.x = p.x + vx + windX * 0.012 * dt * 60
    p.y = p.y + vy + (50 + windY) * dt * dt * 60
  end
  for _ = 1, 3 do
    for i = 2, TAIL_LINKS do
      local p, q = s[i], s[i - 1]
      local dx, dy = p.x - q.x, p.y - q.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d > 0 then
        local k = (d - TAIL_LINK) / d
        if i == 2 then
          p.x, p.y = p.x - dx * k, p.y - dy * k
        else
          p.x, p.y = p.x - dx * k * 0.5, p.y - dy * k * 0.5
          q.x, q.y = q.x + dx * k * 0.5, q.y + dy * k * 0.5
        end
      end
    end
  end
end

-- A hit: the upper body whips back against the way he is thrown
function anim.onHurt(player, dir)
  local a = player.anim
  a.hurt = 1
  a.hurtDir = dir
end

-- Death: the hat flies off, the gun drops, and he collapses (see updateDeath)
function anim.onDeath(player, dir)
  local a = player.anim
  a.deathT = 0
  a.deathDir = dir
  a.gone = false
  local _, _, _, _, neckX, neckY = torso(player)
  local hx, hy = neckX, neckY - 4
  effects.casing(hx, hy, dir * (40 + love.math.random() * 40), -(120 + love.math.random() * 50), 5, COLORS.hat)
  if player.gun then
    effects.casing(neckX + dir * 4, neckY + 3, dir * (20 + love.math.random() * 30), -50, 4, COLORS.gunMid)
  end
end

-- The fallen hunter: a thud when he lands, then (after a beat) he bursts apart
function anim.updateDeath(player, dt)
  local a = player.anim
  if not a.deathT then
    return
  end
  local before = a.deathT
  a.deathT = a.deathT + dt
  local b = player.body
  local cx, fy = b.x + b.w / 2, b.y + b.h
  if before < 0.75 and a.deathT >= 0.75 then
    audio.play("impact", 1.2, 0.5)
    for _ = 1, 8 do
      effects.particle(cx + a.deathDir * 6 + (love.math.random() - 0.5) * 8, fy - 1, (love.math.random() - 0.5) * 50, -love.math.random() * 40, 0.5, { 0.4, 0.37, 0.35 }, 200)
    end
  end
  if before < 1.5 and a.deathT >= 1.5 and not a.gone then
    a.gone = true
    audio.play("explosion", 0.5, 1.4)
    for _ = 1, 34 do
      local ang = love.math.random() * math.pi * 2
      local s = 40 + love.math.random() * 130
      local col = love.math.random() < 0.55 and COLORS.lining or (love.math.random() < 0.5 and COLORS.coat or COLORS.mantle)
      effects.particle(cx, fy - 6, math.cos(ang) * s, math.sin(ang) * s - 60, 0.8 + love.math.random() * 0.6, col, 480)
    end
  end
end

-- Reload progress and its one-off events: shells dropping out, the drum
-- falling away, the clicks of rounds going in and the action snapping shut
function anim.updateReload(player)
  local a, gun = player.anim, player.gun
  if not gun or not gun:isReloading() or player.dead then
    a.reloadP, a.reloadFired, a.reloadGun = nil, nil, nil
    return
  end
  local p = gun:reloadProgress()
  if a.reloadGun ~= gun or (a.reloadP and p < a.reloadP) then
    a.reloadFired = {}
    a.reloadGun = gun
  end
  a.reloadP = p
  local model = gun.def.model
  local set = RELOAD[model]
  if not set then
    return
  end
  local f = player.facing
  local cx = player.body.x + player.body.w / 2
  local _, _, _, _, neckX, neckY = torso(player)
  for i, ev in ipairs(set.events) do
    if p >= ev[1] and not a.reloadFired[i] then
      a.reloadFired[i] = true
      local what = ev[2]
      if what == "eject" then
        local cs = gun.def.casing
        for _ = 1, gun.spent do
          effects.casing(
            neckX + f * (3 + love.math.random() * 2),
            neckY + 4,
            (model == "shotgun" and -f * (15 + love.math.random() * 25) or (love.math.random() - 0.5) * 40) + player.body.vx * 0.3,
            model == "shotgun" and -(60 + love.math.random() * 50) or (10 + love.math.random() * 20),
            cs and cs.size or 3,
            nil,
            cs and cs.hull
          )
        end
        gun.spent = 0
        audio.play("reload_click", 0.8, 0.8)
      elseif what == "drum" then
        effects.casing(neckX + f * 4, neckY + 6, f * 12 + player.body.vx * 0.3, 10, 4, { 0.22, 0.22, 0.27 })
        audio.play("reload_click", 0.9, 0.6)
      elseif what == "click" then
        audio.play("reload_click")
      elseif what == "snap" then
        audio.play("reload_snap")
        a.recoil = math.max(a.recoil, 0.25) -- a little jolt as it closes
      end
    end
  end
end

function anim.update(player, dt)
  local a, b = player.anim, player.body
  a.time = a.time + dt
  if a.lastX and player.grounded and not player.sliding then
    a.phase = a.phase + math.abs(b.x - a.lastX) * (player.crouched and 0.38 or 0.26)
  end
  a.lastX = b.x
  a.walking = player.grounded and not player.sliding and math.abs(b.vx) > 13

  -- Ease the legs back together when standing still
  if not a.walking and player.grounded then
    local rest = math.floor(a.phase / math.pi + 0.5) * math.pi
    a.phase = lerp(a.phase, rest, 1 - math.exp(-12 * dt))
  end

  if player.grounded and not a.wasGrounded and a.lastVy > 144 then
    a.squash = clamp(a.lastVy / 352, 0.4, 1)
  end
  a.squash = math.max(0, a.squash - dt * 6)
  a.recoil = math.max(0, a.recoil - dt * 7)
  a.hurt = math.max(0, a.hurt - dt * 4.5)
  if a.flip then
    a.flip = a.flip + dt / 0.38
    if a.flip >= 1 then
      a.flip = nil
    end
  end
  anim.updateReload(player)
  a.wasGrounded = player.grounded
  a.lastVy = b.vy

  -- Coat tails trail behind the motion and lift when falling
  local t = 1 - math.exp(-10 * dt)
  a.coatX = lerp(a.coatX, clamp(-b.vx * 0.04, -7, 7), t)
  a.coatY = lerp(a.coatY, clamp(-b.vy * 0.025, -6, 2), t)
  updateMantleTail(player, dt)
end

-- Two-bone inverse kinematics: returns the joint (knee/elbow) position.
-- bend = +1 or -1 picks which side the joint folds to.
local function solveIK(ax, ay, tx, ty, l1, l2, bend)
  local dx, dy = tx - ax, ty - ay
  local d = clamp(math.sqrt(dx * dx + dy * dy), math.abs(l1 - l2) + 0.01, l1 + l2 - 0.01)
  local base = math.atan2(dy, dx)
  local cosA = clamp((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1)
  local angle = base + bend * math.acos(cosA)
  return ax + math.cos(angle) * l1, ay + math.sin(angle) * l1
end

-- Reach toward a target, stopping at full limb length
local function reachToward(ax, ay, tx, ty, length)
  local dx, dy = tx - ax, ty - ay
  local d = math.sqrt(dx * dx + dy * dy)
  if d > length then
    return ax + dx / d * length, ay + dy / d * length
  end
  return tx, ty
end

-- Crisp limb segment snapped to pixel centres. A width of 2 adds a second
-- line one pixel behind (toward -facing), for thicker limbs.
local function segment(x1, y1, x2, y2, color, width, facing)
  love.graphics.setColor(color)
  local ax, ay = math.floor(x1) + 0.5, math.floor(y1) + 0.5
  local bx, by = math.floor(x2) + 0.5, math.floor(y2) + 0.5
  love.graphics.line(ax, ay, bx, by)
  if width == 2 then
    local o = -(facing or 1)
    love.graphics.line(ax + o, ay, bx + o, by)
  end
end

local function pixel(x, y, color)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 1)
end

-- Foot targets for both legs (front, back) for the current state, plus the
-- direction knees should bend
local function footTargets(player, cx, fy)
  local a, b, f = player.anim, player.body, player.facing
  local fx1, fy1, fx2, fy2
  local bend = f
  if player.rollT then
    -- Knees pulled up to the chest
    local dir = player.rollDir
    bend = dir
    fx1, fy1 = cx + dir * 2.6, fy - 4.2
    fx2, fy2 = cx + dir * 0.6, fy - 2.6
  elseif player.sliding then
    -- Lead leg stretched out along the ground, trailing leg folded under
    local dir = b.vx >= 0 and 1 or -1
    bend = dir
    fx1, fy1 = cx + dir * 8.5, fy
    fx2, fy2 = cx - dir * 0.5, fy
  elseif player.grounded then
    if a.walking then
      local dir = b.vx >= 0 and 1 or -1
      local stride = player.crouched and 3.0 or 4.3
      local lift = player.crouched and 1.6 or 2.9
      fx1 = cx + math.sin(a.phase) * stride * dir
      fy1 = fy - math.max(0, math.cos(a.phase)) * lift
      fx2 = cx + math.sin(a.phase + math.pi) * stride * dir
      fy2 = fy - math.max(0, math.cos(a.phase + math.pi)) * lift
    elseif player.crouched then
      fx1, fy1 = cx + f * 3.2, fy
      fx2, fy2 = cx - f * 2.4, fy
    else
      fx1, fy1 = cx + f * 2.1, fy
      fx2, fy2 = cx - f * 1.8, fy
    end
  else
    -- Rising: knees tucked. Falling: legs dangle.
    local t = clamp((b.vy + 96) / 224, 0, 1)
    fx1, fy1 = cx + f * lerp(2.9, 1.3, t), fy - lerp(4.5, 0.5, t)
    fx2, fy2 = cx - f * lerp(0.6, 1.9, t), fy - lerp(2.6, 0, t)
  end
  if player.kickTimer > 0 then
    local t = math.sin(player.kickTimer / cfg.kickDuration * math.pi)
    fx1 = lerp(fx1, cx + f * 10.4, t)
    fy1 = lerp(fy1, fy - 7.2, t)
  end
  return fx1, fy1, fx2, fy2, bend
end

local function drawLeg(hipX, hipY, footX, footY, bend, trousers, boots)
  footX, footY = reachToward(hipX, hipY, footX, footY, THIGH + SHIN - 0.01)
  local kneeX, kneeY = solveIK(hipX, hipY, footX, footY, THIGH, SHIN, -bend)
  segment(hipX, hipY, kneeX, kneeY, trousers, 2, bend)
  segment(kneeX, kneeY, footX, footY, trousers, 2, bend)
  -- Boot: heel to toe, with a silver buckle
  segment(footX - bend, footY, footX + bend * 2, footY, boots)
  segment(footX - bend, footY - 1, footX, footY - 1, boots)
  if boots == COLORS.boots then
    pixel(footX, footY - 1, COLORS.buckle)
  end
end

-- Arm from shoulder to hand; elbow folds downward
local function drawArm(sx, sy, hx, hy, color)
  hx, hy = reachToward(sx, sy, hx, hy, UPPER_ARM + FOREARM - 0.01)
  local ex1, ey1 = solveIK(sx, sy, hx, hy, UPPER_ARM, FOREARM, 1)
  local ex2, ey2 = solveIK(sx, sy, hx, hy, UPPER_ARM, FOREARM, -1)
  local ex, ey = ex1, ey1
  if ey2 > ey1 then
    ex, ey = ex2, ey2
  end
  segment(sx, sy, ex, ey, color)
  segment(ex, ey, hx, hy, color)
  pixel(hx, hy, COLORS.glove)
end

local function fillPolygon(points, color)
  love.graphics.setColor(color)
  local ok, triangles = pcall(love.math.triangulate, points)
  if ok then
    for _, tri in ipairs(triangles) do
      love.graphics.polygon("fill", tri)
    end
  end
end

-- Long, slim coat from the shoulders to the knees; the back tail trails behind
local function drawCoat(player, fy, hipX, hipY, neckX, neckY)
  local a, f = player.anim, player.facing
  local hemY = math.min(hipY + 5.5, fy - 1)
  local flutter = math.sin(a.time * 11) * math.min(1, math.abs(player.body.vx) / 80) * 0.8
  local tailX = hipX - f * 2.8 + a.coatX
  local tailY = hemY + a.coatY + flutter
  if player.rollT then
    -- Wrapped round the ball, not trailing
    tailX, tailY = hipX - f * 2.2, hipY + 2.5
  elseif player.crouched or player.sliding then
    tailY = math.min(tailY, fy - 0.5) -- drapes on the ground
  end
  local outline = {
    neckX + f * 1.2, neckY + 0.5,
    hipX + f * 1.6, hipY - 0.5,
    hipX + f * 2.0 + a.coatX * 0.35, hemY - 0.5,
    tailX, tailY,
    hipX - f * 2.4, hipY,
    neckX - f * 1.8, neckY + 2.5,
    neckX - f * 1.0, neckY + 0.5,
  }
  -- Polygons must be listed in a consistent winding; mirror order when facing left
  if f < 0 then
    local reversed = {}
    for i = #outline - 1, 1, -2 do
      reversed[#reversed + 1] = outline[i]
      reversed[#reversed + 1] = outline[i + 1]
    end
    outline = reversed
  end
  fillPolygon(outline, COLORS.coat)
  -- Teal lining (the ether's colour) glimpsed at the open front, and a lit leading edge
  segment(hipX + f * 1.6, hipY, hipX + f * 2.0 + a.coatX * 0.35, hemY - 1, COLORS.lining)
  segment(neckX + f * 1.2, neckY + 1, hipX + f * 1.4, hipY - 1, COLORS.coatLight)
  segment(hipX - f * 2.4, hipY, tailX, tailY, COLORS.coatDark)
  -- Belt with a silver buckle
  for i = -1, 1 do
    pixel(hipX + i * f, hipY - 1, COLORS.coatDark)
  end
  pixel(hipX + f, hipY - 1, COLORS.buckle)
end

-- Light-grey mantle over the shoulders, part of the coat; its loose end is the
-- cloth chain that trails in the wind (drawn behind the body)
local function drawMantleTail(player)
  local s = player.anim.mantleTail
  if not s then
    return
  end
  for i = 1, #s - 1 do
    local color = i <= 2 and COLORS.mantle or COLORS.mantleDark
    segment(s[i].x, s[i].y, s[i + 1].x, s[i + 1].y, color)
  end
end

local function drawMantle(player, neckX, neckY)
  local a, f = player.anim, player.facing
  local back = math.max(-2.5, math.min(2.5, a.coatX * 0.3))
  local shape = {
    neckX - f * 1.4, neckY - 0.5,
    neckX + f * 1.3, neckY,
    neckX + f * 2.0, neckY + 3.0,
    neckX - f * 2.3 + back, neckY + 4.0,
  }
  if f < 0 then
    shape = { shape[7], shape[8], shape[5], shape[6], shape[3], shape[4], shape[1], shape[2] }
  end
  fillPolygon(shape, COLORS.mantle)
  segment(neckX + f * 2.0, neckY + 3.0, neckX - f * 2.3 + back, neckY + 4.0, COLORS.mantleDark) -- hem
  segment(neckX - f * 1.0, neckY, neckX + f * 1.0, neckY, COLORS.mantleLight) -- lit top
end

-- Mostly hat, riding low: a tall crown and a wide drooping brim pulled down
-- to the eyes, the face lost in shadow except for the two glowing eyes
-- The brim sits two pixels over the neck, so the hat comes right down to the
-- shoulders with just the eyes showing between (a future hat swaps the crown
-- and brim drawn below; the face column and collar stay)
local function headOrigin(neckX, neckY, f)
  return math.floor(neckX + f * 0.6), math.floor(neckY - 2)
end

local function drawHead(neckX, neckY, f, nohat)
  local hx, hy = headOrigin(neckX, neckY, f)
  local left = f > 0 and hx - 2 or hx -- 3-wide face column
  love.graphics.setColor(COLORS.shadow)
  love.graphics.rectangle("fill", left, hy, 3, 2)
  -- High coat collar around the jaw
  love.graphics.setColor(COLORS.coat)
  love.graphics.rectangle("fill", left - f, hy + 1, 1, 2)
  love.graphics.rectangle("fill", f > 0 and left or left + 2, hy + 1, 1, 2)
  -- Eyes just under the brim
  pixel(hx, hy + 1, COLORS.eye)
  pixel(hx - f * 2, hy + 1, COLORS.eye)
  if nohat then
    -- Hat gone: dark hair on the bare head
    love.graphics.setColor(COLORS.coatDark)
    love.graphics.rectangle("fill", left, hy - 1, 3, 2)
    pixel(f > 0 and left - 1 or left + 3, hy, COLORS.coatDark)
    return
  end
  -- Brim: wide, drooping more at the front, lit along the top
  love.graphics.setColor(COLORS.hat)
  love.graphics.rectangle("fill", left - 4, hy, 11, 1)
  love.graphics.rectangle("fill", f > 0 and left + 7 or left - 5, hy + 1, 1, 1)
  love.graphics.rectangle("fill", f > 0 and left - 5 or left + 7, hy, 1, 1)
  love.graphics.setColor(COLORS.hatLight)
  love.graphics.rectangle("fill", left - 3, hy - 1, 9, 1)
  -- Crown: tall, slightly tapered, with a band and a silver buckle
  love.graphics.setColor(COLORS.hat)
  love.graphics.rectangle("fill", left - 1, hy - 5, 5, 4)
  love.graphics.rectangle("fill", left, hy - 6, 3, 1)
  love.graphics.setColor(COLORS.hatBand)
  love.graphics.rectangle("fill", left - 1, hy - 2, 5, 1)
  pixel(f > 0 and left + 2 or left, hy - 2, COLORS.buckle)
  love.graphics.setColor(COLORS.hatLight)
  love.graphics.rectangle("fill", f > 0 and left + 3 or left - 1, hy - 5, 1, 3)
end

-- Gun drawers, one per def.model. (x, y) is the grip; d is along the barrel
-- and p perpendicular to it, pointing "down" (toward the grip/magazine side).
local GUN_DRAW = {}

function GUN_DRAW.revolver(x, y, dx, dy, px, py, len)
  -- Grip angles down and back from the hand, perpendicular to the barrel
  segment(x, y, x + px * 2.5 - dx * 1.5, y + py * 2.5 - dy * 1.5, COLORS.grip)
  segment(x, y, x + dx * len, y + dy * len, COLORS.gun)
  -- Cylinder, silver engraving along the barrel, and the muzzle
  pixel(x + dx * 2 + px * 0.9, y + dy * 2 + py * 0.9, COLORS.gunMid)
  pixel(x + dx * 3 + px * 0.9, y + dy * 3 + py * 0.9, COLORS.gunMid)
  pixel(x + dx * 5, y + dy * 5, COLORS.silver)
  pixel(x + dx * len, y + dy * len, COLORS.silver)
end

function GUN_DRAW.pistol(x, y, dx, dy, px, py, len)
  -- Long slanted grip, a boxy slide on top and a magazine in front of the grip
  segment(x, y, x + px * 3 - dx * 1.5, y + py * 3 - dy * 1.5, COLORS.grip)
  segment(x, y, x + dx * len, y + dy * len, COLORS.gun)
  segment(x - dx, y - dy - 0, x + dx * 6, y + dy * 6, COLORS.gunMid)
  pixel(x + dx * 3 + px * 1.6, y + dy * 3 + py * 1.6, COLORS.gun)
  pixel(x + dx * 4 + px * 1.6, y + dy * 4 + py * 1.6, COLORS.gun)
  pixel(x + dx * 7.5, y + dy * 7.5, COLORS.silver)
  pixel(x + dx * len, y + dy * len, COLORS.silver)
end

function GUN_DRAW.shotgun(x, y, dx, dy, px, py, len)
  -- Wooden stock running back into the shoulder
  segment(x, y, x - dx * 4 + px * 1.6, y - dy * 4 + py * 1.6, COLORS.grip)
  segment(x + px, y + py, x - dx * 3 + px * 2.4, y - dy * 3 + py * 2.4, COLORS.grip)
  -- Two barrels side by side, the upper one a shade lighter
  segment(x, y, x + dx * len, y + dy * len, COLORS.gun)
  segment(x + dx * 2 - px, y + dy * 2 - py, x + dx * len - px, y + dy * len - py, COLORS.gunMid)
  -- Wooden fore-end under the barrels, silver action and muzzles
  segment(x + dx * 3 + px, y + dy * 3 + py, x + dx * 6.5 + px, y + dy * 6.5 + py, COLORS.grip)
  pixel(x + dx * 1, y + dy * 1, COLORS.silver)
  pixel(x + dx * len, y + dy * len, COLORS.silver)
  pixel(x + dx * len - px, y + dy * len - py, COLORS.silver)
end

function GUN_DRAW.automatic(x, y, dx, dy, px, py, len)
  -- Short stock, a boxy two-pixel receiver and a drum magazine underneath
  segment(x, y, x - dx * 3 + px * 1.4, y + py * 1.4 - dy * 3, COLORS.grip)
  segment(x - dx, y - dy, x + dx * 5, y + dy * 5, COLORS.gun)
  segment(x - dx - px, y - dy - py, x + dx * 4 - px, y + dy * 4 - py, COLORS.gun)
  local mx, my = x + dx * 2 + px * 2, y + dy * 2 + py * 2
  love.graphics.setColor(COLORS.gun)
  love.graphics.rectangle("fill", math.floor(mx) - 1, math.floor(my) - 1, 3, 3)
  pixel(mx - 1, my - 1, COLORS.gunMid)
  -- Cooling jacket over the barrel, with vent holes, then the muzzle
  segment(x + dx * 5, y + dy * 5, x + dx * len, y + dy * len, COLORS.gunMid)
  pixel(x + dx * 6.5, y + dy * 6.5, COLORS.gun)
  pixel(x + dx * 8.5, y + dy * 8.5, COLORS.gun)
  pixel(x + dx * 3, y + dy * 3 - py, COLORS.silver)
  pixel(x + dx * len, y + dy * len, COLORS.silver)
end

local BRASS = { 0.86, 0.64, 0.24 }

function GUN_DRAW.gatling(x, y, dx, dy, px, py, len, gun)
  -- Stock back into the shoulder, a brass breech casing, the hopper on top
  segment(x, y, x - dx * 3 + px * 1.4, y + py * 1.4 - dy * 3, COLORS.grip)
  segment(x - dx, y - dy, x + dx * 4, y + dy * 4, BRASS)
  segment(x - dx - px, y - dy - py, x + dx * 4 - px, y + dy * 4 - py, BRASS)
  pixel(x + dx * 1.5 - px * 2, y + dy * 1.5 - py * 2, COLORS.gunMid)
  pixel(x + dx * 2.5 - px * 2, y + dy * 2.5 - py * 2, COLORS.gunMid)
  -- The barrel cluster: two rows whose shading swaps as the barrels turn
  local turn = gun and math.floor(gun.spin or 0) % 2 == 1
  segment(x + dx * 4, y + dy * 4, x + dx * len, y + dy * len, turn and COLORS.gunMid or COLORS.gun)
  segment(x + dx * 4 - px, y + dy * 4 - py, x + dx * len - px, y + dy * len - py, turn and COLORS.gun or COLORS.gunMid)
  -- Brass bands round the barrels and a bright muzzle
  pixel(x + dx * 8, y + dy * 8, BRASS)
  pixel(x + dx * 8 - px, y + dy * 8 - py, BRASS)
  pixel(x + dx * len, y + dy * len, COLORS.silver)
  pixel(x + dx * len - px, y + dy * len - py, COLORS.silver)
end

local function drawGun(gun, gripX, gripY, angle, f)
  local dx, dy = math.cos(angle), math.sin(angle)
  local px, py = -dy * f, dx * f
  local def = gun and gun.def
  local draw = GUN_DRAW[def and def.model or "revolver"] or GUN_DRAW.revolver
  draw(gripX, gripY, dx, dy, px, py, def and def.length or 8.8, gun)
end

-- Eye position under the brim (the lighting adds a faint glow there)
function anim.eyes(player)
  local _, _, _, _, neckX, neckY = torso(player)
  local hx, hy = headOrigin(neckX, neckY, player.facing)
  return hx + 0.5, hy + 1.5
end

-- How the whole figure is turned this frame: toppling over when dead, a
-- twirl on a double jump, a forward somersault in a dodge roll.
-- Returns the angle and the point it turns about.
local function bodyTurn(player)
  local a, b = player.anim, player.body
  local cx, fy = b.x + b.w / 2, b.y + b.h
  if player.dead and a.deathT then
    local k = clamp(a.deathT / 0.75, 0, 1)
    local theta = a.deathDir * (math.pi / 2) * k * k
    -- A small bounce as he lands
    if a.deathT > 0.75 then
      theta = theta - a.deathDir * 0.1 * math.exp(-(a.deathT - 0.75) * 9) * math.abs(math.sin((a.deathT - 0.75) * 14))
    end
    return theta, cx, fy
  elseif player.rollT then
    -- One full turn, quick through the middle, about the middle of the ball
    local k = clamp(player.rollT / cfg.rollTime, 0, 1)
    return player.rollDir * math.pi * 2 * smooth(k), cx + player.rollDir * 1.5, fy - 7.5
  elseif a.flip then
    return player.facing * math.pi * 2 * smooth(a.flip), cx, fy - 9
  end
  return 0, cx, fy
end

local function turned(player, draw)
  local theta, px, py = bodyTurn(player)
  if theta == 0 then
    draw()
    return
  end
  love.graphics.push()
  love.graphics.translate(px, py)
  love.graphics.rotate(theta)
  love.graphics.translate(-px, -py)
  draw()
  love.graphics.pop()
end

-- The eyes again, after the lighting, so they glow even in the dark (turned
-- with the body, so they stay in the face through a roll or a twirl)
function anim.drawEyes(player)
  turned(player, function()
    local _, _, _, _, neckX, neckY = torso(player)
    local f = player.facing
    local hx, hy = headOrigin(neckX, neckY, f)
    pixel(hx, hy + 1, COLORS.eye)
    pixel(hx - f * 2, hy + 1, COLORS.eye)
  end)
end

local function drawFigure(player)
  local a, f = player.anim, player.facing
  local dead = player.dead
  local cx, fy, hipX, hipY, neckX, neckY = torso(player)
  local sx, sy = neckX, neckY + 1.3

  -- Gun pose: hands at the grip, pulled back and tipped up by recoil
  local hold = gunHold(player)
  local aim = player.aimAngle
  local dx, dy = math.cos(aim), math.sin(aim)
  -- Reloading changes how the gun is held (see RELOAD above)
  local k0, k1, kt
  local tilt, reachAdd = 0, 0
  if a.reloadP and player.gun then
    k0, k1, kt = reloadKeys(player.gun.def.model, a.reloadP)
    tilt = lerp(k0.tilt, k1.tilt, kt)
    reachAdd = lerp(k0.reach, k1.reach, kt)
  end
  local gripX = sx + dx * (hold.reach - a.recoil * hold.pull + reachAdd)
  local gripY = sy + dy * (hold.reach - a.recoil * hold.pull + reachAdd)
  local gunAngle = aim - f * (a.recoil * hold.tip + tilt + a.hurt * 0.5)
  -- The other hand: on the grip for a pistol, under the fore-end for long guns
  local gdx, gdy = math.cos(gunAngle), math.sin(gunAngle)
  local supX, supY = gripX - dx * 1.3, gripY - dy * 1.3
  if hold.support then
    supX = gripX + gdx * hold.support - gdy * f * 0.8
    supY = gripY + gdy * hold.support + gdx * f * 0.8
  end

  -- Reloading: the support hand follows the keyframes between the gun and the belt
  local carryX, carryY
  if k0 then
    local pdx, pdy = -gdy * f, gdx * f
    local function handAt(k)
      if k.kind == "belt" then
        return hipX + f * k.a, hipY + k.b
      end
      return gripX + gdx * k.a + pdx * k.b, gripY + gdy * k.a + pdy * k.b
    end
    local x0, y0 = handAt(k0)
    local x1, y1 = handAt(k1)
    supX, supY = lerp(x0, x1, kt), lerp(y0, y1, kt)
    if k0.carry then
      carryX, carryY = supX, supY
    end
  end

  if dead then
    -- Arms hang limp (the gun is gone)
    gripX, gripY = sx + f * 1.5, sy + 6.5
    supX, supY = sx - f * 1.0, sy + 6.8
  elseif player.rollT then
    -- Arms wrapped round the knees, the gun tucked away for the moment
    gripX, gripY = cx + f * 3.2, fy - 3.6
    supX, supY = cx + f * 2.4, fy - 3.0
  end

  local fx1, fy1, fx2, fy2, bend = footTargets(player, cx, fy)

  -- Back to front: mantle tail, back arm, legs, coat over the thighs, mantle,
  -- head, gun, front arm
  if not player.rollT then
    drawMantleTail(player) -- (its cloth trails in the world, so it would flail in a somersault)
  end
  drawArm(sx - f * 0.6, sy, supX, supY, COLORS.coatDark)
  drawLeg(hipX - f * 0.6, hipY, fx2, fy2, bend, COLORS.trousersDark, COLORS.bootsDark)
  drawLeg(hipX + f * 0.6, hipY, fx1, fy1, bend, COLORS.trousers, COLORS.boots)
  drawCoat(player, fy, hipX, hipY, neckX, neckY)
  drawMantle(player, neckX, neckY)
  drawHead(neckX, neckY, f, dead)
  if not dead and player.gun and not player.rollT then
    drawGun(player.gun, gripX, gripY, gunAngle, f)
  end
  drawArm(sx + f * 0.6, sy, gripX, gripY, COLORS.coat)
  if carryX and not dead then
    -- A fresh round (or magazine) held in the hand
    local name = player.gun and player.gun.def.model
    pixel(carryX + f, carryY - 1, name == "shotgun" and { 0.72, 0.17, 0.13 } or { 0.85, 0.66, 0.25 })
    pixel(carryX + f, carryY, name == "shotgun" and { 0.85, 0.66, 0.25 } or COLORS.gunMid)
  end
end

-- Draws the hunter. A dying hunter topples over from the feet; a double
-- jump twirls him around his middle; a dodge roll somersaults him forward.
function anim.draw(player)
  turned(player, function()
    drawFigure(player)
  end)
end

return anim
