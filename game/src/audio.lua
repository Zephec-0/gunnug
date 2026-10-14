-- Placeholder sound effects and music, synthesised in code (design doc §9b):
-- noise bursts, sine thumps and chirps shaped by simple envelopes. Every sound
-- is built once at start-up as a SoundData; audio.play(name) plays a copy, with
-- a little pitch and volume variation so repeats don't sound identical. Swap
-- these for real recordings later by loading files into the same names.
--
-- Besides the effects there is the desert wind, a chiptune theme for each area
-- with quiet little one-off events over it (drips, creaks...), and the shop's
-- quiet jazz piano.
--
-- Everything is wrapped so that a machine without an audio device just runs
-- silently.
local audio = {}

local RATE = 22050
local TAU = 6.2832
local sources = {} -- name -> { source, volume, cooldown, last }
local MASTER = 0.45
local enabled = false
local ambient = {} -- looping beds: surface wind and one per area
local music -- the shop's piano
local playing = {} -- recently started copies, to cap how many overlap
local MAX_VOICES = 24

local function noise()
  return love.math.random() * 2 - 1
end

-- One-pole filters: lp keeps the lows, hp the highs (coef: 0 = nothing passes
-- .. 1 = everything for lp)
local function lp(coef)
  local y = 0
  return function(x)
    y = y + (x - y) * coef
    return y
  end
end

local function hp(coef)
  local y = 0
  return function(x)
    y = y + (x - y) * coef
    return x - y
  end
end

-- Builds a mono sound of `duration` seconds from fn(t, progress) -> sample (-1..1)
local function synth(duration, fn)
  local n = math.floor(duration * RATE)
  local data = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 0, n - 1 do
    local t = i / RATE
    local v = fn(t, i / n)
    -- A soft limiter, and a fade at the very end so nothing clicks
    local a = v < 0 and -v or v
    if a > 0.8 then
      v = (v < 0 and -1 or 1) * (0.8 + (a - 0.8) * 0.25)
    end
    v = math.max(-1, math.min(1, v)) * math.min(1, (n - i) / 200)
    data:setSample(i, v)
  end
  return data
end

-- A sound that loops seamlessly: built `fade` seconds longer, with the extra
-- tail mixed back over the start
local function synthLoop(duration, fn)
  local fade = 0.5
  local long = synth(duration + fade, fn)
  local n, f = math.floor(duration * RATE), math.floor(fade * RATE)
  local data = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 0, n - 1 do
    local v = long:getSample(i)
    if i < f then
      local k = i / f
      v = v * k + long:getSample(n + i) * (1 - k)
    end
    data:setSample(i, v)
  end
  return data
end

-- A sound made of little events laid on a timeline: { t = start, kind, f = pitch, d = decay, len }
local function voice(ev, t)
  local k = ev.kind
  if k == "click" then
    return (noise() * 0.6 + math.sin(t * ev.f * TAU) * 0.5) * math.exp(-t * ev.d)
  elseif k == "thump" then
    return math.sin(t * ev.f * TAU) * math.exp(-t * ev.d) * (ev.gain or 1)
  elseif k == "ting" then
    return (math.sin(t * ev.f * TAU) + 0.4 * math.sin(t * ev.f * 2.76 * TAU)) * math.exp(-t * ev.d) * 0.5
  elseif k == "swish" and t < ev.len then
    return noise() * math.sin(t / ev.len * math.pi) * (ev.gain or 0.4)
  end
  return 0
end

local function timeline(duration, events)
  return synth(duration, function(t)
    local v = 0
    for _, ev in ipairs(events) do
      if t >= ev.t then
        v = v + voice(ev, t - ev.t)
      end
    end
    return v * 0.7
  end)
end

-- Guns ------------------------------------------------------------------------
-- Each has its own voice: the revolver a sharp crack over a deep thump with a
-- ring, the double-barrel a long low boom, the Broomhandle a bright snap, the
-- machine gun a tight tick. (Reloads share the plain clicks and snap below.)

local function shotRevolver()
  local tail, hi = lp(0.25), hp(0.2)
  return synth(0.36, function(t, p)
    local n = noise()
    local crack = hi(n) * math.exp(-p * 30) * 0.9
    local thump = math.sin(t * (150 - 70 * p) * TAU) * math.exp(-p * 9) * 0.85
    local ring = (math.sin(t * 2300 * TAU) * 0.5 + math.sin(t * 3550 * TAU) * 0.3) * math.exp(-p * 16) * 0.2
    return crack + thump + ring + tail(n) * math.exp(-p * 5) * 0.35
  end)
end

local function shotShotgun()
  local tail, hi = lp(0.1), hp(0.15)
  local phase = 0
  return synth(0.7, function(t, p)
    local n = noise()
    phase = phase + (36 + 85 * math.exp(-t * 14)) / RATE
    local boom = math.sin(phase * TAU) * math.exp(-p * 4.5) * 1.0
    local crack = hi(n) * math.exp(-p * 40) * 1.0
    local blast = tail(n) * math.exp(-p * 3.2) * 1.4
    return boom + crack + blast
  end)
end

local function shotAutomatic()
  local hi = hp(0.35)
  return synth(0.1, function(t, p)
    local n = noise()
    return hi(n) * math.exp(-p * 20) * 0.75 + math.sin(t * 1050 * TAU) * math.exp(-p * 34) * 0.4 + math.sin(t * 120 * TAU) * math.exp(-p * 16) * 0.35
  end)
end

local function shotPistol()
  local tail, hi = lp(0.3), hp(0.3)
  return synth(0.24, function(t, p)
    local n = noise()
    return hi(n) * math.exp(-p * 26) * 0.85
      + math.sin(t * (260 - 90 * p) * TAU) * math.exp(-p * 12) * 0.55
      + math.sin(t * 1750 * TAU) * math.exp(-p * 20) * 0.18
      + tail(n) * math.exp(-p * 6) * 0.2
  end)
end

-- Effects -------------------------------------------------------------------------

local DEFS = {
  shot_revolver = { gen = shotRevolver, volume = 0.55 },
  shot_pistol = { gen = shotPistol, volume = 0.45 },
  shot_shotgun = { gen = shotShotgun, volume = 0.75 },
  shot_automatic = { gen = shotAutomatic, volume = 0.32, cooldown = 0.03 },
  explosion = {
    gen = function()
      local tail = lp(0.12)
      return synth(0.8, function(t, p)
        local env = math.exp(-p * 5)
        return (noise() * 0.5 + tail(noise()) * 0.8 + math.sin(t * 55 * TAU) * 0.8) * env
      end)
    end,
    volume = 0.8,
  },
  hit = {
    gen = function()
      return synth(0.07, function(t, p)
        return (noise() * 0.5 + math.sin(t * 300 * TAU) * 0.5) * math.exp(-p * 7)
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
        return (math.sin(t * f * wobble * TAU) * 0.55 + noise() * 0.12) * math.sin(p * math.pi) ^ 0.5
      end)
    end,
    volume = 0.45,
  },
  casing = {
    gen = function()
      return synth(0.06, function(t, p)
        return (math.sin(t * 3300 * TAU) * 0.5 + math.sin(t * 5100 * TAU) * 0.3) * math.exp(-p * 9)
      end)
    end,
    volume = 0.12,
    cooldown = 0.05,
  },
  reload_click = {
    gen = function()
      return synth(0.07, function(t, p)
        return (noise() * 0.4 + math.sin(t * 900 * TAU) * 0.5) * math.exp(-p * 10)
      end)
    end,
    volume = 0.35,
  },
  reload_snap = {
    gen = function()
      return synth(0.1, function(t, p)
        return (noise() * 0.5 + math.sin(t * 420 * TAU) * 0.6) * math.exp(-p * 12)
      end)
    end,
    volume = 0.45,
  },
  enemy_die = {
    gen = function()
      return synth(0.35, function(t, p)
        local f = 220 * (1 - p * 0.7)
        return (math.sin(t * f * TAU) * 0.5 + noise() * 0.25) * (1 - p) * 0.9
      end)
    end,
    volume = 0.5,
  },
  hurt = {
    gen = function()
      return synth(0.25, function(t, p)
        local f = 150 - p * 60
        return (math.sin(t * f * TAU) * 0.7 + noise() * 0.35) * math.exp(-p * 4)
      end)
    end,
    volume = 0.7,
  },
  death = {
    gen = function()
      return synth(0.9, function(t, p)
        local f = 140 - p * 90
        return (math.sin(t * f * TAU) * 0.7 + noise() * 0.3 * (1 - p)) * (1 - p)
      end)
    end,
    volume = 0.8,
  },
  coin = {
    gen = function()
      return synth(0.16, function(t, p)
        local f = p < 0.35 and 1318 or 1760
        return math.sin(t * f * TAU) * math.exp(-p * 6) * 0.6
      end)
    end,
    volume = 0.3,
    cooldown = 0.05,
  },
  pickup = {
    gen = function()
      return synth(0.22, function(t, p)
        local f = 500 + p * 500
        return math.sin(t * f * TAU) * math.exp(-p * 3.5) * 0.6
      end)
    end,
    volume = 0.5,
  },
  chest = {
    gen = function()
      return synth(0.5, function(t, p)
        local creak = math.sin(t * (110 + math.sin(t * 30) * 25) * TAU) * 0.4
        local chime = p > 0.4 and math.sin(t * 1046 * TAU) * math.exp(-(p - 0.4) * 6) * 0.5 or 0
        return creak * (1 - p) + chime
      end)
    end,
    volume = 0.6,
  },
  buy = {
    gen = function()
      return synth(0.3, function(t, p)
        local f = p < 0.4 and 880 or 1175
        return math.sin(t * f * TAU) * math.exp(-p * 4) * 0.6
      end)
    end,
    volume = 0.5,
  },
  deny = {
    gen = function()
      return synth(0.2, function(t, p)
        return (math.sin(t * 160 * TAU) * 0.6 + noise() * 0.1) * (1 - p) * (math.floor(t * 40) % 2 == 0 and 1 or 0.5)
      end)
    end,
    volume = 0.5,
  },
  heal = {
    gen = function()
      return synth(0.6, function(t, p)
        local f = 392 * (1 + math.floor(p * 3) * 0.25)
        return math.sin(t * f * TAU) * math.sin(p * math.pi) * 0.5
      end)
    end,
    volume = 0.5,
  },
  reload = {
    gen = function()
      return synth(0.18, function(t, p)
        local click = (p < 0.08 or (p > 0.5 and p < 0.58)) and noise() or 0
        return click * 0.6 + math.sin(t * 700 * TAU) * 0.15 * (p < 0.08 and 1 or 0)
      end)
    end,
    volume = 0.4,
  },
  kick = {
    gen = function()
      return synth(0.12, function(t, p)
        return (noise() * 0.4 + math.sin(t * 90 * TAU) * 0.6) * math.exp(-p * 6)
      end)
    end,
    volume = 0.4,
  },
  clank = {
    gen = function()
      return synth(0.6, function(t, p)
        local v = 0
        for _, f in ipairs({ 523, 831, 1244, 2100 }) do
          v = v + math.sin(t * f * TAU) * 0.18
        end
        return (v + noise() * 0.2 * math.exp(-p * 30)) * math.exp(-p * 5)
      end)
    end,
    volume = 0.7,
  },
  hatch = {
    gen = function()
      return synth(0.9, function(t, p)
        local groan = math.sin(t * (70 + math.sin(t * 8) * 15) * TAU) * 0.5 * math.sin(p * math.pi)
        local thud = p > 0.7 and (noise() * 0.5 + math.sin(t * 50 * TAU) * 0.6) * math.exp(-(p - 0.7) * 14) or 0
        return groan + thud
      end)
    end,
    volume = 0.8,
  },
  tick = {
    gen = function()
      return synth(0.05, function(t, p)
        return math.sin(t * 900 * TAU) * math.exp(-p * 9) * 0.5
      end)
    end,
    volume = 0.3,
  },
  select = {
    gen = function()
      return synth(0.12, function(t, p)
        return math.sin(t * (p < 0.5 and 600 or 900) * TAU) * math.exp(-p * 4) * 0.5
      end)
    end,
    volume = 0.4,
  },
  land = {
    gen = function()
      return synth(0.1, function(t, p)
        return (noise() * 0.5 + math.sin(t * 70 * TAU) * 0.5) * math.exp(-p * 8)
      end)
    end,
    volume = 0.3,
    cooldown = 0.15,
  },

  -- The deeper monsters -------------------------------------------------------
  worm_wake = {
    gen = function()
      local low = lp(0.05)
      return synth(0.7, function(t, p)
        return (low(noise()) * 2.2 + math.sin(t * 48 * TAU) * 0.5) * math.sin(p * math.pi) ^ 0.6 + (p < 0.15 and noise() * 0.4 * (1 - p / 0.15) or 0)
      end)
    end,
    volume = 0.5,
  },
  worm_dig = {
    gen = function()
      local band = lp(0.35)
      return synth(0.22, function(t, p)
        local crunch = math.floor(t * 70) % 2 == 0 and 1 or 0.45
        return band(noise()) * 1.6 * crunch * math.sin(p * math.pi) + math.sin(t * 70 * TAU) * 0.3 * (1 - p)
      end)
    end,
    volume = 0.24,
    cooldown = 0.2,
  },
  worm_burst = {
    gen = function()
      local low = lp(0.15)
      return synth(0.4, function(t, p)
        return (noise() * 0.6 + low(noise()) * 1.2) * math.exp(-p * 7) + math.sin(t * 60 * TAU) * math.exp(-p * 10) * 0.7
      end)
    end,
    volume = 0.5,
  },
  worm_lunge = {
    gen = function()
      local band = lp(0.5)
      return synth(0.28, function(t, p)
        local cut = 0.15 + 0.7 * p
        return band(noise()) * 1.1 * math.sin(p * math.pi) * cut
      end)
    end,
    volume = 0.4,
  },
  miner_light = {
    gen = function()
      local hi = hp(0.4)
      return synth(0.55, function(t, p)
        -- A match scratched, then the fuse catching with a hiss
        local scratch = t < 0.12 and hi(noise()) * 0.7 * (1 - t / 0.12) or 0
        local flare = t >= 0.12 and t < 0.2 and math.sin((t - 0.12) / 0.08 * math.pi) * 0.5 or 0
        local hiss = t >= 0.14 and hi(noise()) * 0.45 * math.exp(-(t - 0.14) * 4) or 0
        return scratch + flare * noise() + hiss
      end)
    end,
    volume = 0.45,
  },
  roller_curl = {
    gen = function()
      return timeline(0.4, {
        { t = 0, kind = "swish", len = 0.15, gain = 0.25 },
        { t = 0.12, kind = "click", f = 500, d = 50 },
        { t = 0.2, kind = "click", f = 420, d = 50 },
        { t = 0.2, kind = "thump", f = 90, d = 25, gain = 0.8 },
      })
    end,
    volume = 0.5,
  },
  roller_roll = {
    gen = function()
      local low = lp(0.08)
      return synth(0.6, function(t, p)
        local rumble = low(noise()) * 2.0 * (0.6 + 0.4 * math.sin(t * 22 * TAU))
        return rumble * math.sin(p * math.pi) ^ 0.5 + math.sin(t * 65 * TAU) * 0.3 * (1 - p)
      end)
    end,
    volume = 0.5,
  },

  -- Little events scattered over the area beds ----------------------------------------
  drip = {
    gen = function()
      return synth(0.35, function(t, p)
        local f = 1900 - 900 * math.min(1, t * 22)
        local main = math.sin(t * f * TAU) * math.exp(-t * 28)
        local echo = t > 0.12 and math.sin((t - 0.12) * f * 0.9 * TAU) * math.exp(-(t - 0.12) * 30) * 0.3 or 0
        return (main + echo) * 0.5
      end)
    end,
    volume = 0.35,
  },
  drip_echo = {
    gen = function()
      return synth(0.9, function(t, p)
        local v = 0
        for k = 0, 3 do
          local tt = t - k * 0.22
          if tt >= 0 then
            local f = 1500 - 700 * math.min(1, tt * 20)
            v = v + math.sin(tt * f * TAU) * math.exp(-tt * 24) * 0.5 * (0.55 ^ k)
          end
        end
        return v
      end)
    end,
    volume = 0.4,
  },
  creak = {
    gen = function()
      return synth(0.9, function(t, p)
        -- Old timber taking weight: a groan with stick-slip in it
        local f = 95 + 55 * math.sin(p * math.pi) + math.sin(t * 38) * 9
        local slip = math.floor(t * 26) % 3 == 0 and 1 or 0.4
        return (math.sin(t * f * TAU) * 0.5 + math.sin(t * f * 2.02 * TAU) * 0.2 + noise() * 0.08) * math.sin(p * math.pi) * slip
      end)
    end,
    volume = 0.45,
  },
  rocks = {
    gen = function()
      local low = lp(0.1)
      return synth(1.3, function(t, p)
        local rumble = low(noise()) * 1.2 * math.exp(-p * 3)
        local tick = (math.random() < 0.004 * (1 - p) and 1 or 0) * noise()
        return rumble * 0.6 + tick * 0.8
      end)
    end,
    volume = 0.5,
  },
  croak = {
    gen = function()
      return synth(0.5, function(t, p)
        local v = 0
        for k = 0, 1 do
          local tt = t - k * 0.2
          if tt >= 0 and tt < 0.16 then
            v = v + math.sin(tt * (150 + 40 * math.sin(tt * 60)) * TAU) * (0.55 + 0.45 * math.sin(tt * 160 * TAU / 6)) * math.sin(tt / 0.16 * math.pi)
          end
        end
        return v * 0.7
      end)
    end,
    volume = 0.4,
  },
  plop = {
    gen = function()
      return synth(0.16, function(t, p)
        local f = 280 + 520 * math.min(1, t * 18)
        return math.sin(t * f * TAU) * math.exp(-t * 30) * 0.6
      end)
    end,
    volume = 0.35,
  },
  geyser = {
    gen = function()
      local hi = hp(0.3)
      return synth(1.6, function(t, p)
        return hi(noise()) * 1.0 * math.sin(p * math.pi) ^ 1.5 + math.sin(t * 45 * TAU) * 0.3 * math.sin(p * math.pi)
      end)
    end,
    volume = 0.45,
  },
  pop = {
    gen = function()
      return synth(0.05, function(t, p)
        return (noise() * 0.7 + math.sin(t * 1500 * TAU) * 0.3) * math.exp(-p * 12)
      end)
    end,
    volume = 0.22,
  },
  rumble = {
    gen = function()
      local low = lp(0.04)
      return synth(2.4, function(t, p)
        return (low(noise()) * 3 + math.sin(t * 38 * TAU) * 0.7) * math.sin(p * math.pi) ^ 1.2
      end)
    end,
    volume = 0.6,
  },
  whale = {
    gen = function()
      local phase = 0
      return synth(3.2, function(t, p)
        local f = 95 - 38 * p + math.sin(t * 5) * 3 + (p < 0.3 and 20 * (0.3 - p) / 0.3 or 0)
        phase = phase + f / RATE
        return (math.sin(phase * TAU) * 0.7 + math.sin(phase * 2 * TAU) * 0.25) * math.sin(p * math.pi) ^ 1.3
      end)
    end,
    volume = 0.55,
  },
  slosh = {
    gen = function()
      local band = lp(0.12)
      return synth(1.0, function(t, p)
        return band(noise()) * 1.6 * math.sin(p * math.pi) * (0.7 + 0.3 * math.sin(t * 13 * TAU))
      end)
    end,
    volume = 0.35,
  },
}

-- Beds ------------------------------------------------------------------------------
-- The desert wind over the surface (the areas have music instead, see below)

local BEDS = {
  wind = function()
    local low = lp(0.04)
    return synthLoop(4, function(t, p)
      local swell = 0.6 + 0.4 * math.sin(p * 2 * math.pi * 2)
      return low(noise()) * 1.6 * swell * 0.5
    end)
  end,
}

-- Little one-off sounds over each area's music, quiet and rare:
-- { sound, shortest gap, longest gap, volume }
local EVENTS = {
  { { "creak", 14, 30, 0.35 }, { "drip", 4, 11, 0.4 } },
  { { "drip", 3, 8, 0.4 }, { "plop", 5, 12, 0.3 } },
  { { "plop", 4, 9, 0.3 }, { "drip", 9, 20, 0.25 } },
  { { "pop", 1.5, 5, 0.4 }, { "rocks", 24, 50, 0.3 } },
  { { "drip_echo", 5, 12, 0.45 }, { "slosh", 12, 28, 0.25 } },
}

-- The shop: a quiet, smoky jazz piano ------------------------------------------------
-- A late-night trio without the trio: a walking bass, sparse comping on the
-- off-beats, a soft ride cymbal and a swung melody wandering through seventh
-- chords (a ii-V-I turnaround in C, then a trip to the subdominant and back),
-- 16 bars.

local NOTE_BASE = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local function freq(name)
  local letter, rest = name:sub(1, 1), name:sub(2)
  local acc = 0
  if rest:sub(1, 1) == "#" then
    acc, rest = 1, rest:sub(2)
  elseif rest:sub(1, 1) == "b" then
    acc, rest = -1, rest:sub(2)
  end
  return 440 * 2 ^ ((NOTE_BASE[letter] + acc + (tonumber(rest) - 4) * 12 - 9) / 12)
end

-- Each bar: { walking bass (4 quarter notes), the chord comped (a bar with two
-- chords gives both, split by "|"), the melody in 8 swung eighths ("-" = rest) }
local BARS = {
  { "C2 E2 G2 B2", "E3 G3 B3 D4", "E5 - G5 B5 A5 G5 E5 -" }, -- Cmaj7
  { "A1 C#2 E2 Eb2", "G3 C#4 E4", "C#5 - E5 G5 F#5 E5 C#5 -" }, -- A7
  { "D2 F2 A2 F#2", "F3 A3 C4 E4", "D5 F5 A5 - C6 - A5 F5" }, -- Dm7
  { "G1 B1 D2 Eb2", "F3 B3 D4 E4", "B4 D5 F5 G5 E5 - D5 -" }, -- G7
  { "E2 G2 B2 Bb1", "G3 B3 D4 E4", "G5 - B5 D6 B5 G5 E5 -" }, -- Em7
  { "A1 C#2 E2 Eb2", "G3 C#4 E4", "C#5 E5 G5 - A5 - E5 -" }, -- A7
  { "D2 F2 A2 Ab2", "F3 A3 C4 E4", "F5 A5 C6 - A5 F5 D5 -" }, -- Dm7
  { "G1 B1 D2 Db2", "F3 B3 D4 E4", "D5 F5 G5 B5 D6 - - -" }, -- G7
  { "C2 E2 G2 A2", "E3 G3 B3 D4", "E5 G5 B5 - C6 B5 G5 E5" }, -- Cmaj7
  { "C2 E2 G2 E2", "E3 G3 A3 D4", "A4 C5 E5 - G5 E5 C5 -" }, -- C6
  { "F2 A2 C3 A2", "A3 C4 E4 G4", "A5 - C6 E6 C6 A5 F5 -" }, -- Fmaj7
  { "F2 Ab2 C3 Eb2", "Ab3 C4 Eb4 G4", "Ab5 - C6 Eb6 C6 Ab5 F5 -" }, -- Fm7
  { "E2 G2 B2 Bb1", "G3 B3 D4 E4", "G5 B5 D6 - B5 G5 E5 -" }, -- Em7
  { "A1 C#2 E2 Eb2", "G3 C#4 E4", "C#5 E5 G5 A5 G5 E5 C#5 -" }, -- A7
  { "D2 F2 G1 B1", "F3 A3 C4 E4|F3 B3 D4 E4", "F5 A5 D6 - B5 G5 D5 -" }, -- Dm7 | G7
  { "C2 G2 E2 G2", "E3 G3 B3 D4", "E5 - G5 - C5 - - -" }, -- Cmaj7
}

local function words(str)
  local out = {}
  for w in str:gmatch("[^%s|]+") do
    out[#out + 1] = w
  end
  return out
end

-- One soft piano note laid into the buffer. voice: "lead" (a hint of a second,
-- detuned string), "comp" (round and quiet) or "bass" (low, with a longer ring)
local function pianoNote(buf, start, len, f, gain, voice)
  local n0 = math.floor(start * RATE)
  local count = math.floor(len * RATE)
  local release = math.floor(0.06 * RATE)
  local decay = (voice == "bass" and 1.8 or 3.0) + f / 700
  local partials = voice == "bass" and { 1, 0.6, 0.25 } or (voice == "lead" and { 1, 0.42, 0.18 } or { 1, 0.3, 0.12 })
  for i = 0, count - 1 do
    local idx = n0 + i + 1
    if buf[idx] == nil then
      break
    end
    local t = i / RATE
    local env = math.exp(-t * decay) * math.min(1, t / 0.006) * math.min(1, (count - i) / release)
    local v = 0
    for k, a in ipairs(partials) do
      local fk = f * k
      if voice == "lead" then
        v = v + a * (math.sin(t * fk * TAU) + 0.5 * math.sin(t * (fk + 0.35) * TAU)) * 0.67
      else
        v = v + a * math.sin(t * fk * TAU)
      end
    end
    local felt = i < 80 and noise() * 0.12 * (1 - i / 80) or 0 -- a soft hammer
    buf[idx] = buf[idx] + (v * env + felt) * gain
  end
end

-- A brush-soft tick of ride cymbal
local function ride(buf, start, gain)
  local n0 = math.floor(start * RATE)
  local count = math.floor(0.1 * RATE)
  local prev = 0
  for i = 0, count - 1 do
    local idx = n0 + i + 1
    if buf[idx] == nil then
      break
    end
    local n = noise()
    buf[idx] = buf[idx] + (n - prev) * 0.5 * math.exp(-i / RATE * 34) * gain
    prev = n
  end
end

local function composeShopMusic()
  local BEAT = 0.5
  local SWING = 0.085 -- the off-beat eighths are played late, triplet style
  local n = math.floor((#BARS * 4 * BEAT + 1.4) * RATE)
  local buf = {}
  for i = 1, n do
    buf[i] = 0
  end
  local function slotTime(t0, slot)
    return t0 + (slot - 1) * BEAT / 2 + ((slot % 2 == 0) and SWING or 0)
  end
  for bi, bar in ipairs(BARS) do
    local t0 = (bi - 1) * 4 * BEAT
    local bass, comp, melody = words(bar[1]), bar[2], words(bar[3])
    -- Walking bass: a quarter note on each beat
    for q = 1, 4 do
      pianoNote(buf, t0 + (q - 1) * BEAT, 0.46, freq(bass[q]), 0.42, "bass")
    end
    -- Comping: the chord on beat 2 and the "and" of 4 (a split bar: its second chord on beat 3)
    local halves = {}
    for chunk in (comp .. "|"):gmatch("([^|]*)|") do
      halves[#halves + 1] = words(chunk)
    end
    local hits = #halves == 2 and { { 3, halves[1] }, { 7, halves[2] } } or { { 3, halves[1] }, { 8, halves[1] } }
    for _, hit in ipairs(hits) do
      for _, cn in ipairs(hit[2]) do
        pianoNote(buf, slotTime(t0, hit[1]), 0.38, freq(cn), 0.12, "comp")
      end
    end
    -- The melody
    for slot, note in ipairs(melody) do
      if note ~= "-" then
        pianoNote(buf, slotTime(t0, slot), 0.55, freq(note), 0.34, "lead")
      end
    end
    -- Ride: "ding, ding-da, ding, ding-da"
    for _, slot in ipairs({ 1, 3, 4, 5, 7, 8 }) do
      ride(buf, slotTime(t0, slot), (slot == 4 or slot == 8) and 0.07 or 0.1)
    end
  end
  -- A little room: two quiet echoes
  local d1, d2 = math.floor(0.19 * RATE), math.floor(0.37 * RATE)
  for i = n, 1, -1 do
    local v = buf[i]
    if i > d1 then
      v = v + buf[i - d1] * 0.16
    end
    if i > d2 then
      v = v + buf[i - d2] * 0.07
    end
    buf[i] = v
  end
  -- Normalise, and loop it: the tail after the last bar folds back over the start
  local peak = 0.001
  for i = 1, n do
    peak = math.max(peak, math.abs(buf[i]))
  end
  local loopN = math.floor(#BARS * 4 * BEAT * RATE)
  local tail = n - loopN
  local data = love.sound.newSoundData(loopN, RATE, 16, 1)
  for i = 1, loopN do
    local v = buf[i]
    if i <= tail then
      v = v + buf[loopN + i]
    end
    data:setSample(i - 1, math.max(-1, math.min(1, v / peak * 0.8)))
  end
  return data
end

-- Area music: chiptune -----------------------------------------------------------------
-- Each area has its own slow, ambient theme (in the spirit of Terraria's underground
-- tracks), which replaced the noisy looping beds. All share the Hollows' recipe,
-- the favourite: slow pads, sparse plucked notes, a deep sub and a long echo:
--   1 the old mine      A minor, cave-like, with soft triangle plucks
--   2 the Hollows       a low synth drift
--   3 the Vents         a slow plucked bass-guitar line under the pads
--   4 the Warrens       dark and smouldering, in E phrygian
--   5 the Drowned Halls slow, echoing sine arpeggios
-- A track is channels of tokens (a note name, "+" to stack notes, "-" a rest, "."
-- to hold the last note) played over a grid of steps per bar, then mixed with an
-- echo into a loop.

local function shiftOct(name, n)
  local letter, rest = name:sub(1, 1), name:sub(2)
  local acc = ""
  if rest:sub(1, 1) == "#" or rest:sub(1, 1) == "b" then
    acc, rest = rest:sub(1, 1), rest:sub(2)
  end
  return letter .. acc .. tostring(tonumber(rest) + n)
end

local function wave(kind, ph)
  local p = ph - math.floor(ph)
  if kind == "p125" then
    return p < 0.125 and 1 or -1
  elseif kind == "p25" then
    return p < 0.25 and 1 or -1
  elseif kind == "p50" then
    return p < 0.5 and 1 or -1
  elseif kind == "tri" then
    local v = 4 * math.abs(p - 0.5) - 1
    return math.floor(v * 7.5 + 0.5) / 7.5 -- a 4-bit triangle, like the old consoles
  elseif kind == "saw" then
    return 2 * p - 1
  end
  return math.sin(ph * TAU)
end

-- One note of a channel laid into the buffer
local function chipNote(buf, start, dur, f, ch)
  local n0 = math.floor(start * RATE)
  local release = ch.r or 0.06
  local count = math.floor((dur + release) * RATE)
  local attack = ch.a or 0.004
  local ph = 0
  for i = 0, count - 1 do
    local idx = n0 + i + 1
    if buf[idx] == nil then
      break
    end
    local t = i / RATE
    local env
    if ch.pluck then
      env = math.exp(-t * ch.pluck) * math.min(1, t / 0.003)
    else
      env = math.min(1, t / attack)
      if t > dur then
        env = env * math.max(0, 1 - (t - dur) / release)
      end
    end
    local fr = f
    if ch.vib and t > 0.15 then
      fr = f * (1 + ch.vib[2] * math.sin(t * ch.vib[1] * TAU))
    end
    ph = ph + fr / RATE
    buf[idx] = buf[idx] + wave(ch.wave, ph) * env * ch.gain
  end
end

-- A drum hit: k kick, s snare, h hat
local function drumHit(buf, start, kind, gain)
  local n0 = math.floor(start * RATE)
  local count = math.floor((kind == "k" and 0.2 or (kind == "s" and 0.14 or 0.045)) * RATE)
  local ph = 0
  for i = 0, count - 1 do
    local idx = n0 + i + 1
    if buf[idx] == nil then
      break
    end
    local t = i / RATE
    local v
    if kind == "k" then
      ph = ph + (140 * math.exp(-t * 22) + 40) / RATE
      v = math.sin(ph * TAU) * math.exp(-t * 14)
    elseif kind == "s" then
      v = (noise() * 0.8 + math.sin(t * 190 * TAU) * 0.4) * math.exp(-t * 24)
    else
      v = noise() * math.exp(-t * 90) * 0.7
    end
    buf[idx] = buf[idx] + v * gain
  end
end

-- Token list builders ---------------------------------------------------------------

local function flat(bars)
  local t = {}
  for _, bar in ipairs(bars) do
    for tok in bar:gmatch("%S+") do
      t[#t + 1] = tok
    end
  end
  return t
end

local function explicit(bars)
  return function()
    return flat(bars)
  end
end

local function perChord(fn)
  return function(def)
    local t = {}
    for _, name in ipairs(def.prog) do
      for _, tok in ipairs(fn(def.chords[name])) do
        t[#t + 1] = tok
      end
    end
    return t
  end
end

-- A bass pattern: R the chord's root, 5 its fifth, 8 the root an octave up
local function bassPattern(pattern)
  return perChord(function(c)
    local out = {}
    for tok in pattern:gmatch("%S+") do
      out[#out + 1] = tok == "R" and c.root or (tok == "5" and c.fifth or (tok == "8" and shiftOct(c.root, 1) or tok))
    end
    return out
  end)
end

-- An arpeggio: indexes into the chord's notes (0 is a rest)
local function arpPattern(pattern)
  return perChord(function(c)
    local out = {}
    for _, p in ipairs(pattern) do
      out[#out + 1] = p == 0 and "-" or c.notes[(p - 1) % #c.notes + 1]
    end
    return out
  end)
end

-- The whole chord held for a bar (one step per bar)
local function padPattern()
  return perChord(function(c)
    return { table.concat(c.pad or c.notes, "+") }
  end)
end

-- Stabs: S is the chord's notes together
local function stabPattern(pattern)
  return perChord(function(c)
    local out = {}
    for tok in pattern:gmatch("%S+") do
      out[#out + 1] = tok == "S" and table.concat(c.notes, "+") or tok
    end
    return out
  end)
end

local function everyBar(pattern)
  return function(def)
    local t = {}
    for _ = 1, def.bars do
      for tok in pattern:gmatch("%S+") do
        t[#t + 1] = tok
      end
    end
    return t
  end
end

-- The tracks --------------------------------------------------------------------------

local TRACKS = {
  -- 1: the old mine, a cave-like ambient drift in A minor
  {
    bpm = 60,
    bars = 12,
    echo = { delay = 0.5, fb = 0.5 },
    prog = { "Am", "Am", "F", "F", "Dm", "Dm", "Am", "Am", "E", "E", "F", "E" },
    chords = {
      Am = { root = "A1", fifth = "E2", pad = { "A2", "E3", "A3", "C4", "E4" }, notes = { "A3", "C4", "E4", "A4", "C5" } },
      F = { root = "F1", fifth = "C2", pad = { "F2", "C3", "F3", "A3", "C4" }, notes = { "F3", "A3", "C4", "F4", "A4" } },
      Dm = { root = "D2", fifth = "A2", pad = { "D2", "A2", "D3", "F3", "A3" }, notes = { "D3", "F3", "A3", "D4", "F4" } },
      E = { root = "E2", fifth = "B2", pad = { "E2", "B2", "E3", "G#3", "B3" }, notes = { "E3", "G#3", "B3", "E4", "G#4" } },
    },
    channels = {
      { wave = "tri", gain = 0.12, steps = 1, a = 1.0, r = 1.0, legato = 1.0, tokens = padPattern() },
      { wave = "saw", gain = 0.03, steps = 1, a = 1.3, r = 1.0, legato = 1.0, tokens = padPattern() },
      { wave = "tri", gain = 0.10, steps = 8, pluck = 2.8, tokens = arpPattern({ 1, 0, 3, 0, 5, 0, 3, 0 }) },
      { wave = "sine", gain = 0.30, steps = 1, a = 0.4, r = 0.7, legato = 1.0, tokens = bassPattern("R") },
      {
        wave = "p25", gain = 0.045, steps = 8, pluck = 6,
        tokens = explicit({
          "E5 . . . - - - -", "- - C5 . . . - -", "A4 . . . C5 . . .", "- - - - F5 . . .",
          "D5 . . . - - - -", "- - A4 . . . F5 .", "E5 . . . - - - -", "- - - - C5 . . .",
          "G#4 . . . B4 . . .", "- - - - - - E5 .", "F5 . . . C5 . . .", "- - - - B4 . . .",
        }),
      },
    },
  },
  -- 2: the Sunken Hollows, a low synth drift
  {
    bpm = 64,
    bars = 12,
    echo = { delay = 0.47, fb = 0.5 },
    prog = { "Dm9", "Dm9", "Bb", "Bb", "Gm9", "Gm9", "Dm9", "Dm9", "Bb", "Bb", "Asus", "Asus" },
    chords = {
      Dm9 = { root = "D2", fifth = "A2", pad = { "D3", "A3", "C4", "E4", "F4" }, notes = { "D4", "F4", "A4", "C5", "E5" } },
      Bb = { root = "Bb1", fifth = "F2", pad = { "Bb2", "F3", "A3", "D4" }, notes = { "Bb3", "D4", "F4", "A4", "D5" } },
      Gm9 = { root = "G2", fifth = "D3", pad = { "G2", "D3", "Bb3", "F4", "A4" }, notes = { "G3", "Bb3", "D4", "F4", "A4" } },
      Asus = { root = "A1", fifth = "E2", pad = { "A2", "E3", "G3", "D4" }, notes = { "A3", "D4", "E4", "G4", "A4" } },
    },
    channels = {
      { wave = "tri", gain = 0.12, steps = 1, a = 0.9, r = 0.9, legato = 1.0, tokens = padPattern() },
      { wave = "saw", gain = 0.035, steps = 1, a = 1.2, r = 1.0, legato = 1.0, tokens = padPattern() },
      { wave = "sine", gain = 0.12, steps = 8, pluck = 3.2, tokens = arpPattern({ 1, 2, 3, 4, 5, 4, 3, 2 }) },
      { wave = "sine", gain = 0.30, steps = 1, a = 0.3, r = 0.6, legato = 1.0, tokens = bassPattern("R") },
      {
        wave = "p50", gain = 0.05, steps = 8, pluck = 5,
        tokens = explicit({
          "A5 . . . . . - -", "- - - - E5 . . .", "D5 . . . F5 . . .", "- - - - - - A5 .",
          "G5 . . . - - - -", "- - Bb5 . . . - -", "A5 . . . E5 . . .", "- - - - D5 . . .",
          "F5 . . . - - - -", "- - A5 . . . D5 .", "E5 . . . G5 . . .", "- - - - A5 . . .",
        }),
      },
    },
  },
  -- 3: the Sulfur Vents, an ambient drift over a slow plucked bass
  {
    bpm = 68,
    bars = 12,
    echo = { delay = 0.44, fb = 0.45 },
    prog = { "Em", "Em", "C", "C", "D", "D", "Em", "Em", "C", "C", "B", "B" },
    chords = {
      Em = { root = "E2", fifth = "B2", pad = { "E2", "B2", "E3", "G3", "B3" }, notes = { "E3", "G3", "B3", "D4", "E4" } },
      C = { root = "C2", fifth = "G2", pad = { "C2", "G2", "C3", "E3", "G3" }, notes = { "C4", "E4", "G4", "B4", "C5" } },
      D = { root = "D2", fifth = "A2", pad = { "D2", "A2", "D3", "F#3", "A3" }, notes = { "D4", "F#4", "A4", "C5", "D5" } },
      B = { root = "B1", fifth = "F#2", pad = { "B1", "F#2", "B2", "D#3", "F#3" }, notes = { "B3", "D#4", "F#4", "A4", "B4" } },
    },
    channels = {
      { wave = "tri", gain = 0.11, steps = 1, a = 1.0, r = 1.0, legato = 1.0, tokens = padPattern() },
      { wave = "saw", gain = 0.03, steps = 1, a = 1.2, r = 1.0, legato = 1.0, tokens = padPattern() },
      { wave = "tri", gain = 0.24, steps = 4, pluck = 1.8, tokens = bassPattern("R . 5 .") },
      { wave = "p25", gain = 0.06, steps = 4, pluck = 7, tokens = bassPattern("R . 5 .") },
      { wave = "sine", gain = 0.09, steps = 8, pluck = 3.0, tokens = arpPattern({ 1, 0, 2, 0, 3, 0, 2, 0 }) },
      {
        wave = "p50", gain = 0.045, steps = 8, pluck = 5,
        tokens = explicit({
          "B4 . . . - - - -", "- - - - E5 . . .", "G4 . . . - - E5 .", "- - - - - - - -",
          "A4 . . . F#5 . . .", "- - - - D5 . . .", "B4 . . . - - - -", "- - G5 . . . - -",
          "E5 . . . - - - -", "- - - - C5 . . .", "D#5 . . . - - - -", "- - - - B4 . . .",
        }),
      },
    },
  },
  -- 4: the Cinder Warrens, a dark, slowly smouldering drift in E phrygian
  {
    bpm = 58,
    bars = 12,
    echo = { delay = 0.52, fb = 0.5 },
    prog = { "Em", "Em", "F", "F", "Em", "Em", "G", "G", "F", "F", "Em", "Em" },
    chords = {
      Em = { root = "E2", fifth = "B2", pad = { "E2", "B2", "E3", "G3", "B3" }, notes = { "E3", "G3", "B3", "E4", "G4" } },
      F = { root = "F2", fifth = "C3", pad = { "F2", "C3", "F3", "A3", "C4" }, notes = { "F3", "A3", "C4", "E4", "F4" } },
      G = { root = "G2", fifth = "D3", pad = { "G2", "D3", "G3", "B3", "D4" }, notes = { "G3", "B3", "D4", "F4", "G4" } },
    },
    channels = {
      { wave = "tri", gain = 0.11, steps = 1, a = 1.1, r = 1.0, legato = 1.0, tokens = padPattern() },
      { wave = "saw", gain = 0.05, steps = 1, a = 1.4, r = 1.1, legato = 1.0, tokens = padPattern() },
      { wave = "sine", gain = 0.30, steps = 1, a = 0.5, r = 0.8, legato = 1.0, tokens = bassPattern("R") },
      { wave = "sine", gain = 0.10, steps = 8, pluck = 3.0, tokens = arpPattern({ 1, 0, 0, 3, 0, 0, 5, 0 }) },
      {
        wave = "p25", gain = 0.045, steps = 8, pluck = 6,
        tokens = explicit({
          "B4 . . . - - - -", "- - - - E5 . . .", "A4 . . . - - C5 .", "- - - - F5 . . .",
          "G4 . . . - - B4 .", "- - E5 . . . - -", "D5 . . . - - - -", "- - - - B4 . . .",
          "C5 . . . A4 . . .", "- - - - - - F5 .", "E5 . . . B4 . . .", "- - - - G4 . . .",
        }),
      },
    },
  },
  -- 5: the Drowned Halls, slow echoing arpeggios
  {
    bpm = 60,
    bars = 8,
    echo = { delay = 0.6, fb = 0.55 },
    prog = { "Am", "F", "Dm", "E", "Am", "F", "Dm", "E" },
    chords = {
      Am = { root = "A1", fifth = "E2", pad = { "A2", "E3", "A3", "C4", "E4" }, notes = { "A3", "C4", "E4", "A4", "C5" } },
      F = { root = "F1", fifth = "C2", pad = { "F2", "C3", "F3", "A3", "C4" }, notes = { "F3", "A3", "C4", "F4", "A4" } },
      Dm = { root = "D2", fifth = "A2", pad = { "D2", "A2", "D3", "F3", "A3" }, notes = { "D3", "F3", "A3", "D4", "F4" } },
      E = { root = "E2", fifth = "B2", pad = { "E2", "B2", "E3", "G#3", "B3" }, notes = { "E3", "G#3", "B3", "E4", "G#4" } },
    },
    channels = {
      { wave = "tri", gain = 0.12, steps = 1, a = 1.0, r = 1.0, legato = 1.0, tokens = padPattern() },
      { wave = "sine", gain = 0.13, steps = 8, pluck = 2.5, tokens = arpPattern({ 1, 3, 5, 3, 4, 2, 3, 1 }) },
      { wave = "sine", gain = 0.28, steps = 1, a = 0.4, r = 0.7, legato = 1.0, tokens = bassPattern("R") },
      {
        wave = "p50", gain = 0.05, steps = 8, pluck = 4,
        tokens = explicit({
          "E5 . . . - - - -", "- - C5 . . . - -", "D5 . . . A4 . . .", "- - - - B4 . . .",
          "A5 . . . - - - -", "- - F5 . . . - -", "D5 . . . F5 . . .", "- - - - E5 . . .",
        }),
      },
    },
  },
}

local function renderTrack(def)
  local barLen = 4 * 60 / def.bpm
  local reps = def.repeats or 1 -- (a short track plays its bars through more than once)
  local loopN = math.floor(def.bars * reps * barLen * RATE)
  local n = loopN + math.floor(3 * RATE)
  local buf = {}
  for i = 1, n do
    buf[i] = 0
  end
  for _, ch in ipairs(def.channels) do
    local once = ch.tokens(def)
    local toks = {}
    for _ = 1, reps do
      for _, tok in ipairs(once) do
        toks[#toks + 1] = tok
      end
    end
    local slotLen = barLen / ch.steps
    local i = 1
    while i <= #toks do
      local tok = toks[i]
      if tok == "-" or tok == "." then
        i = i + 1
      elseif ch.drum then
        drumHit(buf, (i - 1) * slotLen, tok, ch.gain)
        i = i + 1
      else
        local len = 1
        while toks[i + len] == "." do
          len = len + 1
        end
        for name in tok:gmatch("[^+]+") do
          chipNote(buf, (i - 1) * slotLen, len * slotLen * (ch.legato or 0.92), freq(name), ch)
        end
        i = i + len
      end
    end
  end
  -- The echo (each repeat feeds the next), then normalise and fold the tail over the start
  local d = math.floor(def.echo.delay * RATE)
  for i = d + 1, n do
    buf[i] = buf[i] + buf[i - d] * def.echo.fb
  end
  local peak = 0.001
  for i = 1, n do
    peak = math.max(peak, math.abs(buf[i]))
  end
  local tail = n - loopN
  local data = love.sound.newSoundData(loopN, RATE, 16, 1)
  for i = 1, loopN do
    local v = buf[i]
    if i <= tail then
      v = v + buf[loopN + i]
    end
    data:setSample(i - 1, math.max(-1, math.min(1, v / peak * 0.8)))
  end
  return data
end

-- Setup and playback ---------------------------------------------------------------------

local areaMusic = {} -- the area themes, one looping source each

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
    music = love.audio.newSource(composeShopMusic(), "static")
    music:setLooping(true)
    music:setVolume(0)
    for i, def in ipairs(TRACKS) do
      local src = love.audio.newSource(renderTrack(def), "static")
      src:setLooping(true)
      src:setVolume(0)
      areaMusic[i] = src
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

local eventTimers = {}
local lastArea

-- Fades the wind, the area themes and the shop's piano: underground is 0 (open
-- air) to 1; area is the number of the area the hunter is in (nil on the
-- surface); inShop is true inside a shop room, where the piano plays instead of
-- the area's theme
function audio.update(dt, underground, paused, area, inShop)
  if not enabled then
    return
  end
  if paused then
    for _, src in pairs(ambient) do
      src:setVolume(0)
    end
    for _, src in ipairs(areaMusic) do
      src:setVolume(0)
    end
    music:setVolume(0)
    return
  end
  for _, src in pairs(ambient) do
    if not src:isPlaying() then
      src:play()
    end
  end
  for _, src in ipairs(areaMusic) do
    if not src:isPlaying() then
      src:play()
    end
  end
  if not music:isPlaying() then
    music:play()
  end
  local fade = math.min(1, dt * 1.2)
  local wind = ambient.wind
  wind:setVolume(wind:getVolume() + (0.10 * (1 - underground) * MASTER * 2 - wind:getVolume()) * math.min(1, dt * 1.5))
  for i, src in ipairs(areaMusic) do
    local target = (i == area and not inShop) and 0.10 * underground or 0
    src:setVolume(src:getVolume() + (target * MASTER * 2 - src:getVolume()) * fade)
  end
  music:setVolume(music:getVolume() + ((inShop and 0.13 or 0) * MASTER * 2 - music:getVolume()) * fade)

  -- Little events over the music
  if area ~= lastArea then
    lastArea = area
    eventTimers = {}
  end
  local events = area and not inShop and underground > 0.5 and EVENTS[area]
  if events then
    for i, ev in ipairs(events) do
      eventTimers[i] = (eventTimers[i] or (ev[2] + love.math.random() * (ev[3] - ev[2]))) - dt
      if eventTimers[i] <= 0 then
        eventTimers[i] = ev[2] + love.math.random() * (ev[3] - ev[2])
        audio.play(ev[1], ev[4], 0.9 + love.math.random() * 0.25)
      end
    end
  end
end

return audio
