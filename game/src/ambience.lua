-- The air and the distance: things that make a place feel lived in rather than
-- empty. Per-area drifting particles (spores in the Hollows, embers and ash in
-- the Warrens, bubbles in the Drowned Halls...) and a soundscape of sounds
-- placed in the world: dripping near water, the crackle of fires, growls and
-- rumbles from far off. Wind lives in src.weather.
local audio = require("src.audio")
local effects = require("src.effects")
local fluids = require("src.fluids")

local ambience = {}

local acc = {}
local timers = {}

local r = love.math.random

-- Emitters per area: { rate per second over the view, function(x, y) }
local EMIT = {
  [1] = {
    { 1.6, function(x, y)
      effects.puff(x, y, (r() - 0.5) * 3, -2, 5, 3, { 0.6, 0.55, 0.5 }, { alpha = 0.12, grow = 0.5, drag = 0.3 })
    end },
  },
  [2] = {
    { 4, function(x, y) -- spores, pale and glowing
      effects.puff(x, y, (r() - 0.5) * 4, -5 - r() * 5, 4.5, 3, { 0.55, 1, 0.8 }, { add = true, alpha = 0.3, grow = 0.3, drag = 0.2, rise = -2 })
    end },
  },
  [3] = {
    { 1.2, function(x, y) -- a sulphurous haze
      effects.puff(x, y, (r() - 0.5) * 4, -3, 5, 16, { 0.78, 0.82, 0.3 }, { alpha = 0.09, grow = 0.8, drag = 0.3 })
    end },
    { 2, function(x, y)
      effects.puff(x, y, (r() - 0.5) * 3, -6 - r() * 4, 3, 3, { 0.95, 0.95, 0.4 }, { add = true, alpha = 0.22, grow = 0.2, rise = -3 })
    end },
  },
  [6] = {
    { 3, function(x, y) -- dust hanging in the lamplight
      effects.puff(x, y, (r() - 0.5) * 5, -2, 5, 4, { 0.8, 0.65, 0.45 }, { alpha = 0.14, grow = 0.5, drag = 0.3 })
    end },
  },
  [4] = {
    { 10, function(x, y) -- embers rising on the heat
      effects.puff(x, y, (r() - 0.5) * 14, -16 - r() * 22, 2 + r() * 2, 3 + r() * 2, { 1, 0.5 + r() * 0.3, 0.15 }, { add = true, alpha = 0.85, grow = -0.4, drag = 0.4, rise = -6 })
      effects.particle(x, y, (r() - 0.5) * 16, -20 - r() * 24, 2.5, { 1, 0.7 + r() * 0.2, 0.3 }, -12, true)
    end },
    { 6, function(x, y) -- ash flakes falling
      local g = 0.35 + r() * 0.2
      effects.particle(x, y, (r() - 0.5) * 12, 4 + r() * 6, 5, { g, g * 0.97, g * 0.95 }, 4)
    end },
  },
  [5] = {
    { 3.5, function(x, y) -- bubbles rising through the damp
      effects.particle(x, y, (r() - 0.5) * 4, -10 - r() * 8, 3, { 0.7, 0.9, 1 }, -6, true)
    end },
    { 1.2, function(x, y)
      effects.puff(x, y, (r() - 0.5) * 3, -2, 5, 14, { 0.3, 0.55, 0.6 }, { alpha = 0.08, grow = 0.6, drag = 0.3 })
    end },
  },
}

-- area: the area the hunter is in (nil on the surface)
function ambience.update(dt, world, player, area, underground, view)
  if underground < 0.5 or not area then
    return
  end
  local list = EMIT[area]
  if list then
    for i, e in ipairs(list) do
      local key = area * 10 + i
      acc[key] = (acc[key] or 0) + e[1] * dt
      local n = 0
      while acc[key] >= 1 and n < 6 do
        acc[key] = acc[key] - 1
        n = n + 1
        local x, y = view.x + r() * view.w, view.y + r() * view.h
        if not world:isSolid(math.floor(x), math.floor(y)) then
          e[2](x, y)
        end
      end
      acc[key] = math.min(acc[key], 2)
    end
  end

  -- The soundscape
  local px, py = player:center()
  local function every(name, lo, hi, fn)
    timers[name] = (timers[name] or (lo + r() * (hi - lo))) - dt
    if timers[name] <= 0 then
      timers[name] = lo + r() * (hi - lo)
      fn()
    end
  end
  -- Something large, far off: left or right, never in view
  every("growl", 16, 38, function()
    local side = r() < 0.5 and -1 or 1
    local x, y = px + side * (170 + r() * 220), py + (r() - 0.5) * 200
    if area == 4 then
      audio.playAt("rumble", x, y, 1.0, 0.8 + r() * 0.3)
    else
      audio.playAt("growl_far", x, y, 0.9, 0.75 + r() * 0.5)
    end
  end)
  if area == 4 or area == 3 then
    every("rumble", 35, 80, function()
      audio.playAt("rumble", px + (r() - 0.5) * 300, py + 120, 0.9, 0.7 + r() * 0.3)
    end)
  end
  -- Water dripping and trickling somewhere near
  every("water", 1.4, 3.6, function()
    local x, y = fluids.probe("water", px, py, 280)
    if x then
      audio.playAt(r() < 0.65 and "drip" or "plop", x, y, 0.7, 0.9 + r() * 0.3)
    end
  end)
  -- Fire: a crackle from the nearest flames
  every("fire", 0.7, 1.6, function()
    local x, y = fluids.probe("fire", px, py, 300)
    if x then
      audio.playAt("crackle", x, y, 0.9)
    end
  end)
end

return ambience
