-- Soft light shapes for the emissive pass: a round glow and a column of light, both fading smoothly to nothing at
-- their edges (a filled circle or rectangle at low alpha has a hard rim that reads as a disc). Draw them with the
-- additive blend mode already set.
local softglow = {}

local disc, strip

local function build()
  local n = 64
  local d = love.image.newImageData(n, n)
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local dx, dy = (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1
      local r = math.sqrt(dx * dx + dy * dy)
      local a = math.max(0, 1 - r)
      a = a * a * (3 - 2 * a) -- smoothstep: no rim, no kink at the centre
      d:setPixel(x, y, 1, 1, 1, a)
    end
  end
  disc = love.graphics.newImage(d)
  disc:setFilter("linear", "linear")
  local s = love.image.newImageData(32, 1)
  for x = 0, 31 do
    local k = math.abs((x + 0.5) / 32 * 2 - 1)
    local a = math.max(0, 1 - k)
    s:setPixel(x, 0, 1, 1, 1, a * a * (3 - 2 * a))
  end
  strip = love.graphics.newImage(s)
  strip:setFilter("linear", "linear")
end

-- A round glow of radius r at (x, y), colour c, strength a
function softglow.disc(x, y, r, c, a)
  if not disc then
    build()
  end
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.draw(disc, x - r, y - r, 0, r * 2 / 64, r * 2 / 64)
end

-- A column of light, `half` either side of x, from y0 down to y1, fading to nothing at both sides
function softglow.column(x, y0, y1, half, c, a)
  if not strip then
    build()
  end
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.draw(strip, x - half, y0, 0, half * 2 / 32, y1 - y0)
end

return softglow
