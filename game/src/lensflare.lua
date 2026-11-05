-- A lens flare for the Barrens' low sun: a bright streak through the sun and a few ghosts strung along the line from
-- the sun through the middle of the frame, drawn additively over the lit scene (src.scenes.overworld, with the
-- emissive layer, so it blooms). Pixel-art banded discs and rings, no smooth gradients.
local lensflare = {}

local disc, ring

local function build()
  local n = 33
  local d = love.image.newImageData(n, n)
  local r = love.image.newImageData(n, n)
  local c = (n - 1) / 2
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local dist = math.sqrt((x - c) ^ 2 + (y - c) ^ 2) / c
      local a = math.max(0, 1 - dist)
      a = math.floor(a * 4 + 0.5) / 4 -- (four bands)
      d:setPixel(x, y, 1, 1, 1, a * 0.9)
      local rr = math.max(0, 1 - math.abs(dist - 0.82) / 0.16)
      rr = math.floor(rr * 3 + 0.5) / 3
      r:setPixel(x, y, 1, 1, 1, rr)
    end
  end
  disc, ring = love.graphics.newImage(d), love.graphics.newImage(r)
  disc:setFilter("nearest", "nearest")
  ring:setFilter("nearest", "nearest")
end

-- The ghosts: where along the sun -> middle line (0 = the sun, 1 = the middle), radius, shape, colour, strength
local GHOSTS = {
  { 0.30, 7, "disc", 1.0, 0.78, 0.45, 0.32 },
  { 0.62, 12, "ring", 0.55, 0.85, 0.80, 0.22 },
  { 0.95, 5, "disc", 1.0, 0.55, 0.40, 0.28 },
  { 1.35, 17, "ring", 1.0, 0.72, 0.38, 0.16 },
  { 1.75, 9, "disc", 0.60, 0.80, 1.0, 0.18 },
}

-- The streak through the sun (a long thin bar and a short upright glint), drawn behind the far scenery so the
-- mountains cover it, on the sky canvas (src.scenes.overworld drawBackground)
function lensflare.drawStreak(sx, sy, strength, tint)
  if strength <= 0.01 then
    return
  end
  local t = love.timer.getTime()
  local s = strength * (0.8 + 0.12 * math.sin(t * 0.9) + 0.08 * math.sin(t * 2.3))
  local tr, tg, tb = 1, 1, 1
  if tint then
    tr, tg, tb = tint[1], tint[2], tint[3]
  end
  local prev, prevAlpha = love.graphics.getBlendMode()
  love.graphics.setBlendMode("add")
  -- The streak: a long thin bar through the sun
  for i = 0, 3 do
    local len = 150 - i * 34
    love.graphics.setColor(1 * tr, 0.78 * tg, 0.5 * tb, (0.05 + i * 0.03) * s)
    love.graphics.rectangle("fill", math.floor(sx - len / 2), math.floor(sy), len, 1)
  end
  love.graphics.setColor(1 * tr, 0.85 * tg, 0.6 * tb, 0.2 * s)
  love.graphics.rectangle("fill", math.floor(sx) - 1, math.floor(sy) - 12, 1, 25)
  love.graphics.setBlendMode(prev, prevAlpha)
  love.graphics.setColor(1, 1, 1, 1)
end

-- (sx, sy): the sun, (cx, cy): the middle of the frame, in the coordinates being drawn in; strength 0..1;
-- tint: optional { r, g, b } to colour the whole flare (a red sun through smoke)
-- vy: the camera's height (world px); the ghosts slide up and down with it as the view tilts, but hold still sideways
function lensflare.draw(sx, sy, cx, cy, strength, tint, vy)
  if strength <= 0.01 then
    return
  end
  if not disc then
    build()
  end
  local t = love.timer.getTime()
  vy = vy or 0
  -- The flare ebbs and flares unevenly (as if dust drifts across the sun) instead of one steady breath
  local flicker = 0.8 + 0.12 * math.sin(t * 0.9) + 0.08 * math.sin(t * 2.3)
  local s = strength * flicker
  -- The axis aims above the middle of the frame; the height of the camera swings it up and down
  cy = cy - 70 + math.sin(vy * 0.015) * 40
  local tr, tg, tb = 1, 1, 1
  if tint then
    tr, tg, tb = tint[1], tint[2], tint[3]
  end
  local prev, prevAlpha = love.graphics.getBlendMode()
  love.graphics.setBlendMode("add")
  -- The ghosts
  for _, g in ipairs(GHOSTS) do
    local gx, gy = sx + (cx - sx) * g[1], sy + (cy - sy) * g[1]
    local scale = g[2] / 16
    -- (each ghost pulses on its own beat and fades toward the ground so none sits over the player)
    local pulse = 0.7 + 0.3 * math.sin(t * (0.8 + g[1]) + g[1] * 9)
    local sky = math.max(0, math.min(1, (sy + 40 - gy) / 80 + 0.5))
    love.graphics.setColor(g[4] * tr, g[5] * tg, g[6] * tb, g[7] * 0.8 * s * pulse * sky)
    love.graphics.draw(g[3] == "disc" and disc or ring, math.floor(gx), math.floor(gy), 0, scale, scale, 16.5, 16.5)
  end
  love.graphics.setBlendMode(prev, prevAlpha)
  love.graphics.setColor(1, 1, 1, 1)
end

return lensflare
