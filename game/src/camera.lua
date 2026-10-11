-- Follows the player, leaning slightly toward the aim point.
local config = require("src.config")

local camera = { x = 0, y = 0 }

local LOOK_AHEAD = 0.2
local SMOOTHING = 10

local function target(world, fx, fy, aimX, aimY)
  local W, H = config.VIRTUAL_W, config.VIRTUAL_H
  local tx = fx + (aimX - fx) * LOOK_AHEAD - W / 2
  local ty = fy + (aimY - fy) * LOOK_AHEAD - H / 2
  tx = math.max(0, math.min(tx, world.width - W))
  ty = math.max(0, math.min(ty, world.height - H))
  return tx, ty
end

function camera.snap(world, fx, fy)
  camera.x, camera.y = target(world, fx, fy, fx, fy)
end

function camera.update(dt, world, fx, fy, aimX, aimY)
  local tx, ty = target(world, fx, fy, aimX, aimY)
  local t = 1 - math.exp(-SMOOTHING * dt)
  camera.x = camera.x + (tx - camera.x) * t
  camera.y = camera.y + (ty - camera.y) * t
end

-- Whole-pixel offset so the low-res canvas stays crisp
function camera.offset()
  return math.floor(camera.x + 0.5), math.floor(camera.y + 0.5)
end

return camera
