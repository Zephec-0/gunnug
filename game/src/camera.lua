-- Keeps the player centred, leaning slightly toward the aim point. The camera
-- is not clamped to the level, so the player stays in the middle even at the
-- edges; world.draw extends the edge terrain to fill anything beyond.
--
-- On top of that the view can be kicked (a quick shove that eases back: gun
-- recoil) and shaken (trauma that builds with explosions and hits and drains
-- away). Both only move what is drawn; aiming uses the steady camera.
local config = require("src.config")

local camera = { x = 0, y = 0 }

local LOOK_AHEAD = 0.12
local SMOOTHING = 10
local KICK_RECOVERY = 14 -- how fast a kick eases back
local TRAUMA_DRAIN = 1.7 -- trauma lost per second
local MAX_SHAKE = 7 -- px at full trauma

local kickX, kickY = 0, 0
local trauma = 0
local clock = 0

local function target(fx, fy, aimX, aimY)
  local tx = fx + (aimX - fx) * LOOK_AHEAD - config.VIRTUAL_W / 2
  local ty = fy + (aimY - fy) * LOOK_AHEAD - config.VIRTUAL_H / 2
  return tx, ty
end

function camera.snap(fx, fy)
  camera.x, camera.y = target(fx, fy, fx, fy)
  kickX, kickY, trauma = 0, 0, 0
end

function camera.update(dt, fx, fy, aimX, aimY)
  local tx, ty = target(fx, fy, aimX, aimY)
  local t = 1 - math.exp(-SMOOTHING * dt)
  camera.x = camera.x + (tx - camera.x) * t
  camera.y = camera.y + (ty - camera.y) * t
  local k = math.exp(-KICK_RECOVERY * dt)
  kickX, kickY = kickX * k, kickY * k
  trauma = math.max(0, trauma - TRAUMA_DRAIN * dt)
  clock = clock + dt
end

-- A shove of (dx, dy) pixels that eases back (the shot's direction, reversed)
function camera.kick(dx, dy)
  kickX = math.max(-8, math.min(8, kickX + dx))
  kickY = math.max(-8, math.min(8, kickY + dy))
end

-- Adds trauma (0..1); the shake grows with its square
function camera.shake(amount)
  trauma = math.min(1, trauma + amount)
end

-- Whole-pixel offset so the low-res canvas stays crisp (steady: no kick or shake)
function camera.baseOffset()
  return math.floor(camera.x + 0.5), math.floor(camera.y + 0.5)
end

-- The offset the frame is drawn with: the steady one plus kick and shake
function camera.offset()
  local s = trauma * trauma * MAX_SHAKE
  local sx = s * (math.sin(clock * 53.1) * 0.6 + math.sin(clock * 91.7 + 1.3) * 0.4)
  local sy = s * (math.sin(clock * 47.3 + 2.1) * 0.6 + math.sin(clock * 83.9) * 0.4)
  return math.floor(camera.x + kickX + sx + 0.5), math.floor(camera.y + kickY + sy + 0.5)
end

return camera
