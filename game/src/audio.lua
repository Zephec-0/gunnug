-- Placeholder sound effects, synthesised in code (design doc §9b): noise
-- bursts, sine thumps and chirps shaped by simple envelopes. Every sound is
-- built once at start-up as a SoundData; audio.play(name) plays a copy, with a
-- little pitch and volume variation so repeats don't sound identical. Swap
-- these for real recordings later by loading files into the same names.
--
-- Everything is wrapped so that a machine without an audio device just runs
-- silently.
local audio = {}

local RATE = 22050
local sources = {} -- name -> { source, volume, cooldown, last }
local MASTER = 0.45
local enabled = false
local ambient = {} -- looping beds: surface wind and cave drone
local playing = {} -- recently started copies, to cap how many overlap
local MAX_VOICES = 24

local function noise()
  return love.math.random() * 2 - 1
end

-- Builds a mono sound of `duration` seconds from fn(t, progress) -> sample (-1..1)
local function synth(duration, fn)
  local n = math.floor(duration * RATE)
  local data = love.sound.newSoundData(n, RATE, 16, 1)
  local prev = 0
  for i = 0, n - 1 do
    local t = i / RATE
    local v = fn(t, i / n)
    -- Gentle clipping, and a fade at the very end so nothing clicks
    v = math.max(-1, math.min(1, v)) * math.min(1, (n - i) / 200)
    prev = v
    data:setSample(i, v)
  end
  return data
end

-- Decaying noise + low thump: a shot. body = how much low "thump", crack = bright noise
local function shot(duration, crack, body, pitch)
  return synth(duration, function(t, p)
    local env = math.exp(-p * 9)
    local lowpass = noise() * 0.5
    return (noise() * crack + math.sin(t * pitch * 6.2832) * body * math.exp(-p * 14)) * env + lowpass * 0 * env
  end)
end

local DEFS = {
  shot_revolver = { gen = function() return shot(0.22, 0.75, 0.7, 150) end, volume = 0.55 },
  shot_pistol = { gen = function() return shot(0.14, 0.6, 0.5, 190) end, volume = 0.4 },
  shot_shotgun = { gen = function() return shot(0.38, 0.95, 1.0, 95) end, volume = 0.7 },
  shot_automatic = { gen = function() return shot(0.09, 0.55, 0.4, 170) end, volume = 0.3, cooldown = 0.03 },
  explosion = {
    gen = function()
      return synth(0.7, function(t, p)
        local env = math.exp(-p * 5)
        return (noise() * 0.7 + math.sin(t * 55 * 6.2832) * 0.8) * env
      end)
    end,
    volume = 0.8,
  },
  hit = {
    gen = function()
      return synth(0.07, function(t, p)
        return (noise() * 0.5 + math.sin(t * 300 * 6.2832) * 0.5) * math.exp(-p * 7)
      end)
    end,
    volume = 0.35,
    cooldown = 0.04,
  },
  impact = {
    gen = function()
      return synth(0.05, function(t, p)
        return noise() * math.exp(-p * 8) * 0.6
      end)
    end,
    volume = 0.15,
    cooldown = 0.07,
  },
  bat_screech = {
    gen = function()
      return synth(0.5, function(t, p)
        -- A shrill chirp that climbs, wobbles and then cracks downward
        local f = p < 0.55 and (1500 + p * 2400) or (2800 - (p - 0.55) * 4200)
        local wobble = 1 + 0.25 * math.sin(t * 60)
        return (math.sin(t * f * wobble * 6.2832) * 0.55 + noise() * 0.12) * math.sin(p * math.pi) ^ 0.5
      end)
    end,
    volume = 0.45,
  },
  casing = {
    gen = function()
      return synth(0.06, function(t, p)
        return (math.sin(t * 3300 * 6.2832) * 0.5 + math.sin(t * 5100 * 6.2832) * 0.3) * math.exp(-p * 9)
      end)
    end,
    volume = 0.12,
    cooldown = 0.05,
  },
  reload_click = {
    gen = function()
      return synth(0.07, function(t, p)
        return (noise() * 0.4 + math.sin(t * 900 * 6.2832) * 0.5) * math.exp(-p * 10)
      end)
    end,
    volume = 0.35,
  },
  reload_snap = {
    gen = function()
      return synth(0.1, function(t, p)
        return (noise() * 0.5 + math.sin(t * 420 * 6.2832) * 0.6) * math.exp(-p * 12)
      end)
    end,
    volume = 0.45,
  },
  enemy_die = {
    gen = function()
      return synth(0.35, function(t, p)
        local f = 220 * (1 - p * 0.7)
        return (math.sin(t * f * 6.2832) * 0.5 + noise() * 0.25) * (1 - p) * 0.9
      end)
    end,
    volume = 0.5,
  },
  hurt = {
    gen = function()
      return synth(0.25, function(t, p)
        local f = 150 - p * 60
        return (math.sin(t * f * 6.2832) * 0.7 + noise() * 0.35) * math.exp(-p * 4)
      end)
    end,
    volume = 0.7,
  },
  death = {
    gen = function()
      return synth(0.9, function(t, p)
        local f = 140 - p * 90
        return (math.sin(t * f * 6.2832) * 0.7 + noise() * 0.3 * (1 - p)) * (1 - p)
      end)
    end,
    volume = 0.8,
  },
  coin = {
    gen = function()
      return synth(0.16, function(t, p)
        local f = p < 0.35 and 1318 or 1760
        return math.sin(t * f * 6.2832) * math.exp(-p * 6) * 0.6
      end)
    end,
    volume = 0.3,
    cooldown = 0.05,
  },
  pickup = {
    gen = function()
      return synth(0.22, function(t, p)
        local f = 500 + p * 500
        return math.sin(t * f * 6.2832) * math.exp(-p * 3.5) * 0.6
      end)
    end,
    volume = 0.5,
  },
  chest = {
    gen = function()
      return synth(0.5, function(t, p)
        local creak = math.sin(t * (110 + math.sin(t * 30) * 25) * 6.2832) * 0.4
        local chime = p > 0.4 and math.sin(t * 1046 * 6.2832) * math.exp(-(p - 0.4) * 6) * 0.5 or 0
        return creak * (1 - p) + chime
      end)
    end,
    volume = 0.6,
  },
  buy = {
    gen = function()
      return synth(0.3, function(t, p)
        local f = p < 0.4 and 880 or 1175
        return math.sin(t * f * 6.2832) * math.exp(-p * 4) * 0.6
      end)
    end,
    volume = 0.5,
  },
  deny = {
    gen = function()
      return synth(0.2, function(t, p)
        return (math.sin(t * 160 * 6.2832) * 0.6 + noise() * 0.1) * (1 - p) * (math.floor(t * 40) % 2 == 0 and 1 or 0.5)
      end)
    end,
    volume = 0.5,
  },
  heal = {
    gen = function()
      return synth(0.6, function(t, p)
        local f = 392 * (1 + math.floor(p * 3) * 0.25)
        return math.sin(t * f * 6.2832) * math.sin(p * math.pi) * 0.5
      end)
    end,
    volume = 0.5,
  },
  reload = {
    gen = function()
      return synth(0.18, function(t, p)
        local click = (p < 0.08 or (p > 0.5 and p < 0.58)) and noise() or 0
        return click * 0.6 + math.sin(t * 700 * 6.2832) * 0.15 * (p < 0.08 and 1 or 0)
      end)
    end,
    volume = 0.4,
  },
  kick = {
    gen = function()
      return synth(0.12, function(t, p)
        return (noise() * 0.4 + math.sin(t * 90 * 6.2832) * 0.6) * math.exp(-p * 6)
      end)
    end,
    volume = 0.4,
  },
  clank = {
    gen = function()
      return synth(0.6, function(t, p)
        local v = 0
        for _, f in ipairs({ 523, 831, 1244, 2100 }) do
          v = v + math.sin(t * f * 6.2832) * 0.18
        end
        return (v + noise() * 0.2 * math.exp(-p * 30)) * math.exp(-p * 5)
      end)
    end,
    volume = 0.7,
  },
  hatch = {
    gen = function()
      return synth(0.9, function(t, p)
        local groan = math.sin(t * (70 + math.sin(t * 8) * 15) * 6.2832) * 0.5 * math.sin(p * math.pi)
        local thud = p > 0.7 and (noise() * 0.5 + math.sin(t * 50 * 6.2832) * 0.6) * math.exp(-(p - 0.7) * 14) or 0
        return groan + thud
      end)
    end,
    volume = 0.8,
  },
  tick = {
    gen = function()
      return synth(0.05, function(t, p)
        return math.sin(t * 900 * 6.2832) * math.exp(-p * 9) * 0.5
      end)
    end,
    volume = 0.3,
  },
  select = {
    gen = function()
      return synth(0.12, function(t, p)
        return math.sin(t * (p < 0.5 and 600 or 900) * 6.2832) * math.exp(-p * 4) * 0.5
      end)
    end,
    volume = 0.4,
  },
  land = {
    gen = function()
      return synth(0.1, function(t, p)
        return (noise() * 0.5 + math.sin(t * 70 * 6.2832) * 0.5) * math.exp(-p * 8)
      end)
    end,
    volume = 0.3,
    cooldown = 0.15,
  },
}

-- Looping beds: wind over the desert and a low drone in the caves
local BEDS = {
  wind = function()
    local lp = 0
    return synth(4, function(t, p)
      lp = lp + (noise() - lp) * 0.04
      local swell = 0.6 + 0.4 * math.sin(p * 2 * math.pi * 2)
      return lp * 1.6 * swell * 0.5
    end)
  end,
  drone = function()
    return synth(4, function(t, p)
      local v = math.sin(t * 55 * 6.2832) * 0.4 + math.sin(t * 82.5 * 6.2832) * 0.25 + math.sin(t * 110.7 * 6.2832) * 0.1
      return v * (0.7 + 0.3 * math.sin(p * 2 * math.pi * 2)) * 0.5
    end)
  end,
}

function audio.load()
  local ok = pcall(function()
    for name, def in pairs(DEFS) do
      sources[name] = { data = def.gen(), volume = def.volume or 0.5, cooldown = def.cooldown or 0, last = -1 }
    end
    for name, gen in pairs(BEDS) do
      local src = love.audio.newSource(gen(), "static")
      src:setLooping(true)
      src:setVolume(0)
      ambient[name] = src
    end
    enabled = true
  end)
  if not ok then
    enabled = false
  end
end

-- Plays a named sound. volume scales it; pitch (default 1) is varied a little.
function audio.play(name, volume, pitch)
  if not enabled then
    return
  end
  local def = sources[name]
  if not def then
    return
  end
  local now = love.timer.getTime()
  if def.cooldown > 0 and now - def.last < def.cooldown then
    return
  end
  def.last = now
  -- Drop voices that have finished, and cap how many play at once
  for i = #playing, 1, -1 do
    if not playing[i]:isPlaying() then
      table.remove(playing, i)
    end
  end
  if #playing >= MAX_VOICES then
    return
  end
  local ok, src = pcall(love.audio.newSource, def.data, "static")
  if not ok then
    return
  end
  src:setVolume(def.volume * (volume or 1) * MASTER * (0.9 + love.math.random() * 0.2))
  src:setPitch((pitch or 1) * (0.94 + love.math.random() * 0.12))
  src:play()
  playing[#playing + 1] = src
end

-- Fades the surface wind and the cave drone: underground is 0 (open air) to 1
function audio.update(dt, underground, paused)
  if not enabled then
    return
  end
  local wind, drone = ambient.wind, ambient.drone
  if paused then
    wind:setVolume(0)
    drone:setVolume(0)
    return
  end
  if not wind:isPlaying() then
    wind:play()
    drone:play()
  end
  local target = { wind = 0.10 * (1 - underground), drone = 0.14 * underground }
  for name, src in pairs(ambient) do
    local v = src:getVolume()
    v = v + (target[name] * MASTER * 2 - v) * math.min(1, dt * 2)
    src:setVolume(v)
  end
end

return audio
