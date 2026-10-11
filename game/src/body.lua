-- Pixel-precise movement for axis-aligned boxes.
-- A body has integer x, y (top-left), w, h, and sub-pixel remainders remX, remY.
--
-- Movement functions take a `collide(x, y, w, h)` function that returns true
-- (plus an optional blocker, e.g. a physics prop) when the rectangle is blocked.
local Body = {}

function Body.new(x, y, w, h)
  return { x = x, y = y, w = w, h = h, remX = 0, remY = 0, vx = 0, vy = 0 }
end

-- Rectangle vs. solid terrain pixels
function Body.terrainOverlaps(world, x, y, w, h)
  for py = y, y + h - 1 do
    for px = x, x + w - 1 do
      if world:isSolid(px, py) then
        return true
      end
    end
  end
  return false
end

-- Returns grounded, plus whatever is underfoot if it isn't terrain
function Body.isGrounded(b, collide)
  return collide(b.x, b.y + b.h, b.w, 1)
end

local function takeWholePixels(rem)
  local move = rem >= 0 and math.floor(rem + 0.5) or -math.floor(-rem + 0.5)
  return move, rem - move
end

-- Moves horizontally one pixel at a time, stepping up small ledges.
-- Returns blocked, blocker.
function Body.moveX(b, collide, amount, stepHeight)
  local move
  move, b.remX = takeWholePixels(b.remX + amount)
  local dir = move > 0 and 1 or -1
  while move ~= 0 do
    local hit, blocker = collide(b.x + dir, b.y, b.w, b.h)
    if not hit then
      b.x = b.x + dir
    else
      local stepped = false
      for s = 1, stepHeight or 0 do
        if not collide(b.x + dir, b.y - s, b.w, b.h) then
          b.x = b.x + dir
          b.y = b.y - s
          stepped = true
          break
        end
      end
      if not stepped then
        b.remX = 0
        return true, blocker
      end
    end
    move = move - dir
  end
  return false
end

-- Moves vertically one pixel at a time. Returns blocked, blocker.
function Body.moveY(b, collide, amount)
  local move
  move, b.remY = takeWholePixels(b.remY + amount)
  local dir = move > 0 and 1 or -1
  while move ~= 0 do
    local hit, blocker = collide(b.x, b.y + dir, b.w, b.h)
    if hit then
      b.remY = 0
      return true, blocker
    end
    b.y = b.y + dir
    move = move - dir
  end
  return false
end

-- Keeps a walking body glued to the ground when going down slopes and steps
function Body.snapDown(b, collide, maxDistance)
  local startY = b.y
  for _ = 1, maxDistance do
    if Body.isGrounded(b, collide) then
      return true
    end
    b.y = b.y + 1
  end
  if Body.isGrounded(b, collide) then
    return true
  end
  b.y = startY
  return false
end

return Body
