-- Procedural, limb-based animation for the gunslinger (Noita-style): instead
-- of sprite frames, a lanky skeleton (hips, knees, feet, shoulders, elbows) is
-- posed every frame and drawn as 1-pixel limbs on the low-res canvas.
--
-- Positions are relative to the hitbox: cx = horizontal centre, fy = feet.
local config = require("src.config")

local cfg = config.player

local anim = {}

-- Limb lengths in pixels
local THIGH, SHIN = 3.3, 3.3
local UPPER_ARM, FOREARM = 2.4, 2.4
local HIP_HEIGHT = 6.2 -- hip above the feet when standing
local TORSO = 4 -- hip to neck
local REACH = 3.6 -- how far in front of the shoulder the hands hold the gun
local GUN_LENGTH = 5.5

local COLORS = {
  skin = { 0.96, 0.75, 0.58 },
  poncho = { 0.92, 0.32, 0.18 },
  ponchoDark = { 0.66, 0.20, 0.12 },
  trim = { 1.0, 0.76, 0.26 },
  jeans = { 0.26, 0.38, 0.70 },
  jeansDark = { 0.17, 0.25, 0.50 },
  boots = { 0.34, 0.20, 0.10 },
  bootsDark = { 0.24, 0.14, 0.07 },
  hat = { 0.50, 0.31, 0.15 },
  hatBand = { 0.26, 0.15, 0.08 },
  eye = { 0.10, 0.08, 0.10 },
  gun = { 0.26, 0.26, 0.32 },
  gunLight = { 0.72, 0.74, 0.82 },
}

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

function anim.new()
  return {
    phase = 0, -- walk cycle, advanced by distance walked
    time = 0,
    squash = 0, -- landing dip, 1 -> 0
    recoil = 0, -- gun kick, 1 -> 0
    lastX = nil,
    lastVy = 0,
    wasGrounded = true,
  }
end

function anim.onShoot(player)
  player.anim.recoil = 1
end

function anim.update(player, dt)
  local a, b = player.anim, player.body
  a.time = a.time + dt
  if a.lastX and player.grounded then
    a.phase = a.phase + math.abs(b.x - a.lastX) * 0.42
  end
  a.lastX = b.x
  a.walking = player.grounded and math.abs(b.vx) > 8

  -- Ease the legs back together when standing still
  if not a.walking and player.grounded then
    local rest = math.floor(a.phase / math.pi + 0.5) * math.pi
    a.phase = lerp(a.phase, rest, 1 - math.exp(-12 * dt))
  end

  if player.grounded and not a.wasGrounded and a.lastVy > 90 then
    a.squash = clamp(a.lastVy / 220, 0.4, 1)
  end
  a.squash = math.max(0, a.squash - dt * 6)
  a.recoil = math.max(0, a.recoil - dt * 7)
  a.wasGrounded = player.grounded
  a.lastVy = b.vy
end

-- Body landmarks shared by drawing and by the gun/muzzle position
local function torso(player)
  local a, b = player.anim, player.body
  local cx, fy = b.x + b.w / 2, b.y + b.h
  local dip = a.squash * 1.6
  if a.walking then
    dip = dip + (1 - math.abs(math.cos(a.phase))) * 0.7
  elseif player.grounded then
    dip = dip + (math.sin(a.time * 2.2) * 0.5 + 0.5) * 0.35 -- breathing
  end
  local lean = clamp(b.vx / cfg.walkSpeed, -1.2, 1.2) * 0.9
  local hipX, hipY = cx, fy - HIP_HEIGHT + dip
  local neckX, neckY = hipX + lean, hipY - TORSO
  return cx, fy, hipX, hipY, neckX, neckY
end

function anim.shoulder(player)
  local _, _, _, _, neckX, neckY = torso(player)
  return neckX, neckY + 0.8
end

-- Where the bullet leaves the barrel (ignores the cosmetic recoil kick)
function anim.muzzle(player)
  local sx, sy = anim.shoulder(player)
  local dx, dy = math.cos(player.aimAngle), math.sin(player.aimAngle)
  return sx + dx * (REACH + GUN_LENGTH), sy + dy * (REACH + GUN_LENGTH)
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

-- Crisp 1-pixel limb segment, snapped to pixel centres
local function segment(x1, y1, x2, y2, color)
  love.graphics.setColor(color)
  love.graphics.line(math.floor(x1) + 0.5, math.floor(y1) + 0.5, math.floor(x2) + 0.5, math.floor(y2) + 0.5)
end

local function pixel(x, y, color)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 1)
end

-- Foot targets for both legs (front, back) for the current state
local function footTargets(player, cx, fy)
  local a, b, f = player.anim, player.body, player.facing
  local fx1, fy1, fx2, fy2
  if player.grounded then
    if a.walking then
      local dir = b.vx >= 0 and 1 or -1
      local stride, lift = 2.7, 1.8
      fx1 = cx + math.sin(a.phase) * stride * dir
      fy1 = fy - math.max(0, math.cos(a.phase)) * lift
      fx2 = cx + math.sin(a.phase + math.pi) * stride * dir
      fy2 = fy - math.max(0, math.cos(a.phase + math.pi)) * lift
    else
      fx1, fy1 = cx + f * 1.3, fy
      fx2, fy2 = cx - f * 1.1, fy
    end
  else
    -- Rising: knees tucked. Falling: legs dangle.
    local t = clamp((b.vy + 60) / 140, 0, 1)
    fx1, fy1 = cx + f * lerp(1.8, 0.8, t), fy - lerp(2.8, 0.3, t)
    fx2, fy2 = cx - f * lerp(0.4, 1.2, t), fy - lerp(1.6, 0, t)
  end
  if player.kickTimer > 0 then
    local t = math.sin(player.kickTimer / cfg.kickDuration * math.pi)
    fx1 = lerp(fx1, cx + f * 6.5, t)
    fy1 = lerp(fy1, fy - 4.5, t)
  end
  return fx1, fy1, fx2, fy2
end

local function drawLeg(hipX, hipY, footX, footY, facing, jeans, boots)
  footX, footY = reachToward(hipX, hipY, footX, footY, THIGH + SHIN - 0.01)
  local kneeX, kneeY = solveIK(hipX, hipY, footX, footY, THIGH, SHIN, -facing)
  segment(hipX, hipY, kneeX, kneeY, jeans)
  segment(kneeX, kneeY, footX, footY, jeans)
  segment(footX, footY, footX + facing, footY, boots)
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
end

function anim.draw(player)
  local a, f = player.anim, player.facing
  local cx, fy, hipX, hipY, neckX, neckY = torso(player)
  local sx, sy = neckX, neckY + 0.8

  -- Gun pose: hands at the grip, pulled back and tipped up by recoil
  local aim = player.aimAngle
  local dx, dy = math.cos(aim), math.sin(aim)
  local gripX = sx + dx * (REACH - a.recoil * 1.6)
  local gripY = sy + dy * (REACH - a.recoil * 1.6)
  local gunAngle = aim - f * a.recoil * 0.45
  local gdx, gdy = math.cos(gunAngle), math.sin(gunAngle)

  local fx1, fy1, fx2, fy2 = footTargets(player, cx, fy)

  -- Back limbs first, in darker shades
  drawArm(sx - f * 0.5, sy, gripX - dx * 0.8, gripY - dy * 0.8, COLORS.ponchoDark)
  drawLeg(hipX - f * 0.5, hipY, fx2, fy2, f, COLORS.jeansDark, COLORS.bootsDark)

  -- Torso: two pixels wide, poncho with a trim line at the waist
  segment(hipX, hipY, neckX, neckY, COLORS.poncho)
  segment(hipX - f, hipY, neckX - f, neckY + 1, COLORS.poncho)
  pixel(hipX, hipY - 1, COLORS.trim)
  pixel(hipX - f, hipY - 1, COLORS.trim)

  drawLeg(hipX + f * 0.5, hipY, fx1, fy1, f, COLORS.jeans, COLORS.boots)

  -- Head: narrow face with an eye on the facing side, under a wide-brimmed hat
  local hx, hy = math.floor(neckX + f * 0.4), math.floor(neckY - 3)
  love.graphics.setColor(COLORS.skin)
  love.graphics.rectangle("fill", f > 0 and hx - 1 or hx, hy, 2, 3)
  pixel(hx, hy + 1, COLORS.eye) -- hx is always the face's front column
  love.graphics.setColor(COLORS.hat)
  love.graphics.rectangle("fill", hx - 3, hy - 1, 7, 1) -- brim
  love.graphics.rectangle("fill", hx - 1 - (f > 0 and 1 or 0), hy - 3, 3, 2) -- crown
  pixel(hx - 1 - (f > 0 and 1 or 0), hy - 2, COLORS.hatBand)
  pixel(hx + 1 - (f > 0 and 1 or 0), hy - 2, COLORS.hatBand)

  -- Revolver, then the front arm over it
  segment(gripX, gripY, gripX + gdx * GUN_LENGTH, gripY + gdy * GUN_LENGTH, COLORS.gun)
  pixel(gripX + gdx * GUN_LENGTH, gripY + gdy * GUN_LENGTH, COLORS.gunLight)
  pixel(gripX - gdy * f * 1.2, gripY + gdx * f * 1.2, COLORS.gun) -- grip
  drawArm(sx + f * 0.5, sy, gripX, gripY, COLORS.poncho)
  pixel(gripX, gripY, COLORS.skin)
end

return anim
