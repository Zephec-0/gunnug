-- Footprints in the Barrens' sand: the hunter leaves a print every few steps, a pair when he lands from a jump,
-- and the wind fills them in after a few seconds. Render-only (nothing is written into the terrain): they are
-- dark dents on the top row of the sand with a pale lip behind them. Only on sand, only above ground, and never
-- while rolling or sliding.
local materials = require("src.materials")

local footprints = {}

local LIFE = 9 -- seconds before one is gone
local FADE = 3 -- (the last seconds it fades)
local STRIDE = 7 -- pixels walked per print
local MAX = 140

local prints = {}
local lastX, travelled, side, wasGrounded = nil, 0, 1, true

local function groundUnder(world, x, y)
  for dy = -1, 2 do
    if world:isSolid(x, y + dy) and not world:isSolid(x, y + dy - 1) then
      return y + dy
    end
  end
  return nil
end

local function add(world, x, y, face, deep)
  x = math.floor(x)
  local gy = groundUnder(world, x, math.floor(y))
  if gy and world:get(x, gy) == materials.SAND then
    prints[#prints + 1] = { x = x, y = gy, face = face, age = 0, deep = deep }
    if #prints > MAX then
      table.remove(prints, 1)
    end
  end
end

-- Call every frame on the surface
function footprints.step(dt, player)
  for i = #prints, 1, -1 do
    local p = prints[i]
    p.age = p.age + dt
    if p.age > LIFE then
      table.remove(prints, i)
    end
  end
  if player.dead then
    lastX = nil
    return
  end
  local world, b = player.world, player.body
  if not (world and b) then
    return
  end
  local cx, foot = b.x + b.w / 2, b.y + b.h
  local face = player.facing or 1
  local grounded = player.grounded and not player.rollT and not player.sliding
  if grounded then
    if not wasGrounded and lastX then
      -- Landing: both feet, a little apart
      add(world, cx - 2, foot, face, true)
      add(world, cx + 2, foot, face, true)
    end
    if lastX and math.abs(b.vx) > 20 then
      travelled = travelled + math.abs(cx - lastX)
      if travelled >= STRIDE then
        travelled = travelled - STRIDE
        side = -side
        local dir = b.vx >= 0 and 1 or -1
        add(world, cx - dir * 2 + side * 1, foot, dir, false)
      end
    end
    lastX = cx
  else
    lastX = cx
    travelled = 0
  end
  wasGrounded = grounded
end

function footprints.clear()
  prints = {}
  lastX, travelled = nil, 0
end

-- x0, x1: the view's reach in world pixels; things outside it are skipped
function footprints.draw(x0, x1)
  for _, p in ipairs(prints) do
    if p.x >= x0 - 4 and p.x <= x1 + 4 then
      local fade = 1 - math.max(0, (p.age - (LIFE - FADE)) / FADE)
      if fade > 0 then
        -- the dent
        love.graphics.setColor(0.36, 0.27, 0.17, (p.deep and 0.62 or 0.5) * fade)
        love.graphics.rectangle("fill", p.x - 1, p.y, 3, 1)
        -- the pale lip pushed up behind the heel
        love.graphics.setColor(0.86, 0.74, 0.52, 0.55 * fade)
        love.graphics.rectangle("fill", p.x - p.face * 2, p.y - 1, 1, 1)
        if p.deep then
          love.graphics.rectangle("fill", p.x + p.face * 2, p.y - 1, 1, 1)
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return footprints
