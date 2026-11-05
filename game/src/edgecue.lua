-- The screen-edge damage cue: when the hunter is hurt a red haze closes in from the edges of the frame and fades
-- over about a second. A bigger hit (a larger share of his health) is thicker and lasts longer, and it leans toward
-- the side the blow came from. Drawn on the small frame after the world (src.game), so it sits under the HUD.
-- (The low-health vignette in the grading shader and the quick full-screen flash are separate and stay as they are.)
local edgecue = {}

local strength = 0 -- 0..1, fading
local side = 0 -- -1 the blow came from the left, 1 from the right, 0 unknown (an even haze)
local ring, edgeL

local FADE = 1.25 -- strength lost per second at full strength (so a hard hit lingers a little over a second)

-- amount: damage taken; maxHp: his health; dir: -1/0/1 the side it came from; dot: a damage-over-time tick (faint)
function edgecue.hit(amount, maxHp, dir, dot)
  local share = math.max(0, amount or 0) / math.max(1, maxHp or 100)
  local s
  if dot then
    s = math.min(0.3, 0.12 + share * 1.5)
  else
    s = math.min(1, 0.4 + share * 2.2)
  end
  if s >= strength then
    side = dir or 0
  end
  strength = math.max(strength, s)
end

function edgecue.update(dt)
  strength = math.max(0, strength - dt * FADE)
end

function edgecue.clear()
  strength = 0
end

-- Two small gradients stretched over the frame: the rim of the screen (an oval haze) and a one-sided edge
local function build()
  local n = 64
  local data = love.image.newImageData(n, n)
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local dx, dy = (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1
      -- distance to the middle, the frame's corners further out than its edges' middles
      local d = math.sqrt(dx * dx * 0.8 + dy * dy * 1.1)
      local a = math.max(0, math.min(1, (d - 0.55) / 0.6))
      a = a * a * (3 - 2 * a)
      data:setPixel(x, y, 1, 1, 1, a)
    end
  end
  ring = love.graphics.newImage(data)
  ring:setFilter("linear", "linear")
  local e = love.image.newImageData(32, 1)
  for x = 0, 31 do
    local t = 1 - (x + 0.5) / 32
    e:setPixel(x, 0, 1, 1, 1, t * t)
  end
  edgeL = love.graphics.newImage(e)
  edgeL:setFilter("linear", "linear")
  edgeL:setWrap("clamp", "clamp")
end

function edgecue.draw(w, h)
  if strength <= 0.01 then
    return
  end
  if not ring then
    build()
  end
  local k = strength * strength * (3 - 2 * strength) -- (eased, so it drops away softly)
  love.graphics.setColor(0.78, 0.04, 0.05, 0.62 * k)
  love.graphics.draw(ring, 0, 0, 0, w / 64, h / 64)
  if side ~= 0 then
    -- Heavier on the side of the blow
    love.graphics.setColor(0.85, 0.05, 0.06, 0.5 * k)
    if side < 0 then
      love.graphics.draw(edgeL, 0, 0, 0, w * 0.34 / 32, h)
    else
      love.graphics.draw(edgeL, w, 0, 0, -w * 0.34 / 32, h)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return edgecue
