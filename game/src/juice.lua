-- Game feel: the shared helpers that turn events into camera kick and shake.
-- Everything is small and short; the point is that shots and hits land with weight.
local camera = require("src.camera")

local juice = {}

-- (There used to be a brief freeze on hits here; it hurt the flow of play, so it is gone.)

-- The hunter fired: shove the view back along the shot. strength is the gun's
-- recoil stat (px/s of impulse), so a shotgun kicks the view hard and a pistol barely
function juice.shot(angle, strength, quiet)
  local k = math.min(3.2, 0.35 + strength / 130) * (quiet and 0.6 or 1)
  camera.kick(-math.cos(angle) * k, -math.sin(angle) * k)
  if strength > 250 then
    camera.shake(0.12)
  end
end

-- Something big went off at (x, y); distance to the view's centre softens it
function juice.blast(x, y, radius)
  local cx, cy = camera.x + 320, camera.y + 180
  local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
  local near = math.max(0, 1 - d / 420)
  camera.shake(math.min(0.7, 0.12 + radius / 60) * near)
end

-- A bullet struck an enemy: a kill shakes the view
function juice.impact(damage, killed)
  if killed then
    camera.shake(0.18)
  end
end

-- The hunter took a hit
function juice.hurt(amount)
  camera.shake(math.min(0.6, 0.25 + amount / 60))
end

return juice
