-- Dev mode (F2 opens src.devpanel): toggles for no damage, one-hit kills and
-- fast no-clip flight, plus teleports.
-- Only in a source checkout: a fused (released) build never turns it on, and
-- its F-keys do nothing.
local input = require("src.input")

local dev = { noDamage = false, oneHit = false, noclip = false }

dev.allowed = not love.filesystem.isFused()
dev.SPEED = 360

-- F2 opens the dev panel (src.devpanel) with the toggles and teleports
function dev.toggle()
  if not dev.allowed then
    return
  end
  require("src.devpanel").toggle()
end

-- What a hit does to an enemy
function dev.damage(amount)
  return dev.oneHit and 1000 or amount
end

-- Called after the hunter's own update: flies him about where the keys point,
-- through anything, from where he stood before it
function dev.flyStep(player, dt, ox, oy)
  if not dev.noclip then
    return
  end
  local b = player.body
  local dx = (input.down("right") and 1 or 0) - (input.down("left") and 1 or 0)
  local dy = (input.down("down") and 1 or 0) - (input.down("jump") and 1 or 0)
  local speed = dev.SPEED * (love.keyboard.isDown("lshift", "rshift") and 2.5 or 1)
  b.x, b.y = ox + dx * speed * dt, oy + dy * speed * dt
  b.vx, b.vy = 0, 0
  player.invuln = 0.1
end

return dev
