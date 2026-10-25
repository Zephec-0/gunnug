-- Weather and wind. On the surface the wind rises and falls, gusts blow, and
-- now and then a dust storm rolls in: sand streaming across the view, the sky
-- dulling, the sun shafts smothered, the wind louder. Underground there is only
-- the draught: a faint steady push with an occasional gust from some shaft.
-- The wind (px/s) bends smoke, embers and spores (src.effects), the dust motes
-- and the drift of the cave fog (src.lighting), and the wind bed (src.audio).
local audio = require("src.audio")
local effects = require("src.effects")
local lighting = require("src.lighting")

local weather = { wind = 0, dust = 0, drift = 0, ash = 0 }

local W, H = 640, 360
local state = "clear" -- or "dust"
local stateTimer = 40
local windDir = 1
local dirTimer = 30
local gust, gustTimer, gustMax = 0, 12, 1
local surfaceWind = 0
local caveWind = 0
local streaks = {}
local STREAKS = 150

for i = 1, STREAKS do
  streaks[i] = { x = math.random() * W, y = math.random() * H, d = 0.5 + math.random() * 1.0, len = 3 + math.random() * 8, a = 0.2 + math.random() * 0.5 }
end

-- Ash falling over the surface once the core has gone out (src.meta.undercroftBeaten): flakes drifting down
local flakes = {}
for i = 1, 140 do
  flakes[i] = { x = math.random() * W, y = math.random() * H, d = 0.4 + math.random() * 1.0, a = 0.3 + math.random() * 0.5 }
end

-- (for tests) jump straight into a state
function weather.force(name)
  state, stateTimer = name, 120
  if name == "dust" then
    weather.dust = 1
  end
end

function weather.reset()
  state, stateTimer, windDir, dirTimer = "clear", 25 + math.random() * 40, 1, 30
  gust, gustTimer = 0, 8
  weather.wind, weather.dust, weather.drift = 0, 0, 0
  weather.ash = 0
end

-- surface: 1 above ground .. 0 deep underground
function weather.update(dt, surface)
  stateTimer = stateTimer - dt
  if stateTimer <= 0 then
    if false then -- (no dust storms any more: the surface only has its wind)
      state, stateTimer = "dust", 25 + love.math.random() * 25
    else
      state, stateTimer = "clear", 40 + love.math.random() * 50
    end
  end
  dirTimer = dirTimer - dt
  if dirTimer <= 0 then
    dirTimer = 20 + love.math.random() * 40
    windDir = love.math.random() < 0.7 and windDir or -windDir
  end
  local ashTarget = require("src.meta").undercroftBeaten() and 1 or 0
  weather.ash = weather.ash + (ashTarget - weather.ash) * math.min(1, dt * 0.4)
  local dustTarget = state == "dust" and 1 or 0
  weather.dust = weather.dust + (dustTarget - weather.dust) * math.min(1, dt * 0.3)

  -- Gusts
  gustTimer = gustTimer - dt
  if gustTimer <= 0 then
    gustTimer = 9 + love.math.random() * 16
    gust, gustMax = 1, 0.5 + love.math.random() * 0.6
    local loud = surface > 0.5 and (0.3 + 0.7 * weather.dust) or 0.25
    audio.play("wind_gust", loud * gustMax)
  end
  gust = math.max(0, gust - dt / 3)
  local swell = gust * math.sin((1 - gust) * math.pi) -- rises then dies away
  local t = love.timer.getTime()
  surfaceWind = windDir * (12 + 18 * (0.5 + 0.5 * math.sin(t * 0.13)) + 90 * weather.dust + 70 * gustMax * swell + 14 * weather.ash)
  caveWind = windDir * (3 + 5 * math.sin(t * 0.09) + 40 * gustMax * swell)
  local target = caveWind + (surfaceWind - caveWind) * surface
  weather.wind = weather.wind + (target - weather.wind) * math.min(1, dt * 1.5)
  weather.drift = weather.drift + weather.wind * dt
  effects.wind = weather.wind
  lighting.drift = weather.drift
  audio.setWindGain(1 + 2.2 * weather.dust * surface + 0.8 * swell * surface)
  weather.surface = surface
end

-- Dulls the surface's look in a storm: fx and ambient are the scene's (modified in place)
function weather.apply(fx, ambient, surface)
  local k = weather.ash * surface
  if k > 0.001 then
    -- after the core: a dull, grey, smoky day, the shafts of sun smothered
    fx.shaft = (fx.shaft or 0) * (1 - 0.7 * k)
    fx.sat = (fx.sat or 1) * (1 - 0.35 * k)
    fx.vig = (fx.vig or 0.38) + 0.1 * k
    local dull = { 0.50, 0.42, 0.40 }
    for i = 1, 3 do
      ambient[i] = ambient[i] + (dull[i] - ambient[i]) * 0.5 * k
    end
  end
  local d = weather.dust * surface
  if d <= 0.001 then
    return
  end
  fx.shaft = (fx.shaft or 0) * (1 - 0.85 * d)
  fx.sat = (fx.sat or 1) * (1 - 0.28 * d)
  fx.vig = (fx.vig or 0.38) + 0.14 * d
  for i = 1, 3 do
    ambient[i] = ambient[i] * (1 - 0.22 * d)
  end
  ambient[1] = ambient[1] + 0.05 * d
  ambient[2] = ambient[2] + 0.025 * d
end

-- Sand streaming across the view (screen space, on the low-res canvas)
function weather.drawScreen(dt)
  local k = weather.ash * (weather.surface or 1)
  if k > 0.01 then
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setColor(0.42, 0.40, 0.38, 0.14 * k) -- the haze
    love.graphics.rectangle("fill", 0, 0, W, H)
    for _, f in ipairs(flakes) do
      f.x = f.x + weather.wind * f.d * dt * 0.8 + math.sin(f.y * 0.06 + f.d * 5) * dt * 6
      f.y = f.y + (10 + 16 * f.d) * dt
      if f.y > H then
        f.y, f.x = -2, math.random() * W
      end
      if f.x > W + 4 then
        f.x = -4
      elseif f.x < -4 then
        f.x = W + 4
      end
      love.graphics.setColor(0.78, 0.75, 0.70, f.a * k)
      love.graphics.rectangle("fill", math.floor(f.x), math.floor(f.y), f.d > 1 and 2 or 1, 1)
    end
    love.graphics.pop()
  end
  local d = weather.dust * (weather.surface or 1)
  if d <= 0.01 then
    return
  end
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setColor(0.72, 0.52, 0.34, 0.2 * d)
  love.graphics.rectangle("fill", 0, 0, W, H)
  local dir = weather.wind >= 0 and 1 or -1
  for _, s in ipairs(streaks) do
    s.x = s.x + weather.wind * s.d * dt * 2.2
    s.y = s.y + math.sin(s.x * 0.05 + s.d * 7) * dt * 14 + dt * 10 * s.d
    if s.x > W + 12 then
      s.x = -12
      s.y = math.random() * H
    elseif s.x < -12 then
      s.x = W + 12
      s.y = math.random() * H
    end
    if s.y > H then
      s.y = 0
    end
    local len = s.len * (0.5 + math.min(1.5, math.abs(weather.wind) / 80))
    love.graphics.setColor(0.93, 0.78, 0.52, s.a * d * 0.7)
    love.graphics.rectangle("fill", math.floor(dir > 0 and s.x - len or s.x), math.floor(s.y), math.floor(len), 1)
  end
  love.graphics.pop()
end

return weather
