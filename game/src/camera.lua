-- Keeps the player centred, leaning slightly toward the aim point. The camera
-- is not clamped to the level, so the player stays in the middle even at the
-- edges; world.draw extends the edge terrain to fill anything beyond.
local config = require("src.config")

local camera = { x = 0, y = 0 }

local LOOK_AHEAD = 0.12
local SMOOTHING = 10

local function target(fx, fy, aimX, aimY)
  local tx = fx + (aimX - fx) * LOOK_AHEAD - config.VIRTUAL_W / 2
  local ty = fy + (aimY - fy) * LOOK_AHEAD - config.VIRTUAL_H / 2
  return tx, ty
end

function camera.snap(fx, fy)
  camera.x, camera.y = target(fx, fy, fx, fy)
end

function camera.update(dt, fx, fy, aimX, aimY)
  local tx, ty = target(fx, fy, aimX, aimY)
  local t = 1 - math.exp(-SMOOTHING * dt)
  camera.x = camera.x + (tx - camera.x) * t
  camera.y = camera.y + (ty - camera.y) * t
end

-- Whole-pixel offset so the low-res canvas stays crisp
function camera.offset()
  return math.floor(camera.x + 0.5), math.floor(camera.y + 0.5)
end

return camera
