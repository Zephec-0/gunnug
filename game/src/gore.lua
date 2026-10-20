-- Gore that stays: blood sprayed from wounds splatters on the walls and floor
-- (it paints the terrain pixels themselves, so it stays until the rock is dug
-- away), bodies leave lasting bits behind, and explosions scorch the rim of
-- their craters.
local effects = require("src.effects")

local gore = {}

local RED = { 0.5, 0.05, 0.08 }
local BLOOD = {
  ghoul = { 0.2, 0.26, 0.32 },
  hopper = { 0.2, 0.46, 0.3 },
  bloater = { 0.42, 0.5, 0.2 },
  spitter = { 0.3, 0.52, 0.22 },
  matron = { 0.3, 0.5, 0.25 },
  worm = { 0.55, 0.38, 0.28 },
  miner = { 0.72, 0.7, 0.62 }, -- bone dust
  roller = { 0.5, 0.28, 0.2 },
  warden = { 0.35, 0.3, 0.4 },
}

function gore.color(e)
  return e.def.blood or BLOOD[e.def.deathKind or e.kind] or RED
end

-- Paints a splat of colour c on the solid pixels around (x, y)
function gore.stain(world, x, y, c, a)
  x, y = math.floor(x), math.floor(y)
  local r = love.math.random
  for i = 1, 3 do
    local px, py = x + (i == 1 and 0 or math.floor(r() * 3) - 1), y + (i == 1 and 0 or math.floor(r() * 3) - 1)
    if world:inBounds(px, py) and world:isSolid(px, py) and world:shownAt(px, py) then
      local pr, pg, pb = world:pixelColor(px, py)
      local t = a * (0.55 + r() * 0.4)
      local shade = 0.75 + r() * 0.35
      world:writePixel(px, py, pr + (c[1] * shade - pr) * t, pg + (c[2] * shade - pg) * t, pb + (c[3] * shade - pb) * t, 1)
    end
  end
end

-- A spray of blood from a wound at (x, y), thrown along (dx, dy)
function gore.spray(x, y, dx, dy, color, amount)
  local r = love.math.random
  local base = math.atan2(dy or -1, dx or 0)
  for _ = 1, amount do
    local a = base + (r() - 0.5) * 1.5
    local s = 40 + r() * 120
    effects.blood(x, y, math.cos(a) * s, math.sin(a) * s - 20, color)
  end
end

-- A body bursting: a gush all round and some lasting bits
function gore.burst(x, y, color, size)
  local r = love.math.random
  for _ = 1, 10 + math.floor(size * 8) do
    local a = r() * math.pi * 2
    local s = 30 + r() * 110
    effects.blood(x, y, math.cos(a) * s, math.sin(a) * s - 40, color)
  end
  for _ = 1, 3 + math.floor(size * 3) do
    local c = { color[1] * (0.6 + r() * 0.5), color[2] * (0.6 + r() * 0.5), color[3] * (0.6 + r() * 0.5) }
    effects.chunk(x + (r() - 0.5) * 6, y, (r() - 0.5) * 90, -40 - r() * 70, 2 + math.floor(r() * 2), 1 + math.floor(r() * 2), c, 16 + r() * 10)
  end
end

-- Chars the rim of a crater of the given radius at (x, y): solid pixels near
-- open air darken to soot
-- (the box's solidity is read once, a row at a time, into this: each pixel used to be looked up nine times)
local solidAt = {}
function gore.scorch(world, x, y, radius)
  local reach = radius + 5
  local r2 = reach * reach
  local r = love.math.random
  local bx0, by0 = math.floor(x - reach) - 2, math.floor(y - reach) - 2
  local bx1, by1 = math.ceil(x + reach) + 2, math.ceil(y + reach) + 2
  local bw = bx1 - bx0 + 1
  for py = by0, by1 do
    world:solidRow(bx0, bx1, py, solidAt, (py - by0) * bw)
  end
  local function solid(px, py)
    return solidAt[(py - by0) * bw + (px - bx0)] == 1
  end
  for py = math.floor(y - reach), math.ceil(y + reach) do
    for px = math.floor(x - reach), math.ceil(x + reach) do
      local dx, dy = px + 0.5 - x, py + 0.5 - y
      local d2 = dx * dx + dy * dy
      if d2 <= r2 and world:inBounds(px, py) and solid(px, py) and (not solid(px + 1, py) or not solid(px - 1, py) or not solid(px, py + 1) or not solid(px, py - 1) or not solid(px + 2, py) or not solid(px - 2, py) or not solid(px, py - 2) or not solid(px, py + 2)) then
        local fall = 1 - math.sqrt(d2) / reach
        if r() < 0.35 + fall * 0.6 and world:shownAt(px, py) then
          local pr, pg, pb = world:pixelColor(px, py)
          local k = 1 - (0.35 + 0.4 * r()) * fall
          world:writePixel(px, py, pr * k * 0.95, pg * k * 0.9, pb * k * 0.9, 1)
        end
      end
    end
  end
end

return gore
