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
-- Player volume settings (src.settings), each 0..1
local volMaster, volMusic, volSfx = 1, 1, 1
local menuMode = false -- the title screens: the void's drone and the menu theme
local recapMode = false -- the death recap: its own sad little theme
local muffled = false -- the weapon panel is open: everything sounds as if through a wall
local MUFFLE = { type = "lowpass", volume = 0.85, highgain = 0.07 }
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
  shot_gatling = { gen = shotAutomatic, volume = 0.26, cooldown = 0.02 },
  -- The Gatling's barrels turning: a dry ratchet click, played faster and
  -- higher as they spin up
  gatling_spin = {
    gen = function()
      return synth(0.05, function(t, p)
        return (noise() * 0.5 + math.sin(t * 1400 * TAU) * 0.3) * math.exp(-p * 7)
      end)
    end,
    volume = 0.22,
  },
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

-- Menu sounds ------------------------------------------------------------------------
-- A softer step back, a page turn, a chime for a new compendium entry, and the
-- sigh of something falling into the void on the title screen.

DEFS.back = {
  gen = function()
    return synth(0.1, function(t, p)
      return math.sin(t * (p < 0.5 and 700 or 470) * TAU) * math.exp(-p * 5) * 0.45
    end)
  end,
  volume = 0.35,
}
DEFS.page = {
  gen = function()
    local band = hp(0.3)
    return synth(0.09, function(t, p)
      return (band(noise()) * 0.6 + math.sin(t * 1300 * TAU) * 0.2) * math.exp(-p * 7)
    end)
  end,
  volume = 0.3,
}
DEFS.discover = {
  gen = function()
    return timeline(1.4, {
      { t = 0, kind = "ting", f = 1047, d = 3.2 },
      { t = 0.11, kind = "ting", f = 1568, d = 2.6 },
      { t = 0.22, kind = "ting", f = 2093, d = 2.2 },
    })
  end,
  volume = 0.35,
}
-- The fuser: a clamp and a rising hum as it locks, a falling breath when it
-- lets go, a tiny glassy blip for each spark of ether, and a bright swell when
-- two items become one
DEFS.fuse_lock = {
  gen = function()
    return synth(0.7, function(t, p)
      local clank = (noise() * 0.5 + math.sin(t * 180 * TAU) * 0.6) * math.exp(-t * 30)
      local hum = math.sin(t * (220 + 220 * p) * TAU) * 0.3 * math.sin(p * math.pi) + math.sin(t * (330 + 330 * p) * TAU) * 0.12 * math.sin(p * math.pi)
      return clank + hum
    end)
  end,
  volume = 0.5,
}
DEFS.fuse_release = {
  gen = function()
    local air = lp(0.15)
    return synth(0.8, function(t, p)
      local f = 500 * (1 - p) + 90
      return (math.sin(t * f * TAU) * 0.3 + air(noise()) * 0.6) * (1 - p) ^ 1.4 * math.min(1, p * 20)
    end)
  end,
  volume = 0.45,
}
DEFS.ether = {
  gen = function()
    return synth(0.12, function(t, p)
      return (math.sin(t * 1760 * TAU) * 0.5 + math.sin(t * 2640 * TAU) * 0.2) * math.exp(-p * 6)
    end)
  end,
  volume = 0.16,
  cooldown = 0.035,
}
DEFS.fuse_done = {
  gen = function()
    return synth(1.6, function(t, p)
      local swell = math.min(1, p * 6) * math.exp(-math.max(0, p - 0.15) * 3)
      local chord = math.sin(t * 523 * TAU) + math.sin(t * 659 * TAU) * 0.8 + math.sin(t * 784 * TAU) * 0.7 + math.sin(t * 1046 * TAU) * 0.5
      local shimmer = math.sin(t * 2093 * TAU) * 0.25 * (0.5 + 0.5 * math.sin(t * 9 * TAU))
      return (chord * 0.22 + shimmer) * swell
    end)
  end,
  volume = 0.5,
}
-- Water: a splash going in (a slap, a burst of spray and a few bubbly
-- blips), and the same sound played backwards coming out, so it sucks
-- up into a pop as the hunter leaves the water
local splashData
local function splash()
  if not splashData then
    local spray = hp(0.35)
    local body = lp(0.25)
    local blips = {}
    for i = 1, 2 do
      blips[i] = { t = 0.03 + love.math.random() * 0.1, f = 500 + love.math.random() * 700 }
    end
    -- (only the opening of it: the slap and a quick burst of spray)
    splashData = synth(0.2, function(t, p)
      local slap = (body(noise()) * 1.6 + math.sin(t * 90 * TAU) * 0.5) * math.exp(-t * 28)
      local hiss = spray(noise()) * 0.55 * math.exp(-t * 16) * math.min(1, t * 80) * (1 - p) ^ 2
      local bub = 0
      for _, b in ipairs(blips) do
        local d = t - b.t
        if d > 0 and d < 0.06 then
          bub = bub + math.sin(d * b.f * (1 + d * 12) * TAU) * math.exp(-d * 60) * 0.35
        end
      end
      return slap + hiss + bub
    end)
  end
  return splashData
end
DEFS.splash_in = {
  gen = splash,
  volume = 0.45,
  cooldown = 0.15,
}
DEFS.splash_out = {
  gen = splash, -- (the same short splash coming out)
  volume = 0.4,
  cooldown = 0.15,
}
-- The wanted poster slammed up on the death recap: a heavy thud, a crack of
-- wood and paper, and dust settling
DEFS.poster_slam = {
  gen = function()
    local low = lp(0.12)
    local crack = hp(0.4)
    return synth(0.6, function(t, p)
      local thud = math.sin(t * (95 - 50 * math.min(1, t * 6)) * TAU) * math.exp(-t * 12) * 1.2
      local body = low(noise()) * 1.4 * math.exp(-t * 14)
      local snap = crack(noise()) * 0.7 * math.exp(-t * 45)
      return thud + body + snap
    end)
  end,
  volume = 0.7,
}
DEFS.swallow = {
  gen = function()
    local phase = 0
    local air = lp(0.25)
    return synth(1.1, function(t, p)
      -- A breath of air drawn down into a low sigh
      local f = 320 * (1 - p) ^ 2 + 38
      phase = phase + f / RATE
      return (math.sin(phase * TAU) * 0.55 + air(noise()) * 0.8 * (1 - p)) * math.sin(math.min(1, p * 3) * math.pi * 0.5) * (1 - p) ^ 1.5
    end)
  end,
  volume = 0.22,
  cooldown = 0.6,
}

-- Footsteps by material ---------------------------------------------------------------
-- A step is a short scuff: filtered noise for the surface, plus a body tone
-- (a thump for earth, a knock for wood, a ring for iron). Played a little
-- varied, so a run of steps doesn't repeat itself.

local function stepSound(duration, noiseCoef, noiseGain, tone, toneGain, toneDecay, ringF)
  return function()
    local body = lp(noiseCoef)
    return synth(duration, function(t, p)
      local n = body(noise()) * noiseGain * math.exp(-p * 9)
      local th = tone > 0 and math.sin(t * tone * TAU) * toneGain * math.exp(-t * toneDecay) or 0
      local ring = ringF and math.sin(t * ringF * TAU) * 0.22 * math.exp(-t * 38) or 0
      return n + th + ring
    end)
  end
end

DEFS.step_dirt = { gen = stepSound(0.09, 0.25, 1.6, 90, 0.5, 40), volume = 0.04, cooldown = 0.08 }
DEFS.step_sand = { gen = stepSound(0.12, 0.12, 1.9, 0, 0, 1), volume = 0.03, cooldown = 0.08 }
DEFS.step_rock = { gen = stepSound(0.07, 0.5, 1.1, 150, 0.4, 55, 1900), volume = 0.045, cooldown = 0.08 }
DEFS.step_wood = { gen = stepSound(0.1, 0.35, 0.7, 180, 0.9, 38, 640), volume = 0.048, cooldown = 0.08 }
DEFS.step_metal = { gen = stepSound(0.16, 0.6, 0.6, 210, 0.35, 30, 1320), volume = 0.042, cooldown = 0.08 }
DEFS.step_ash = { gen = stepSound(0.1, 0.08, 1.7, 0, 0, 1), volume = 0.027, cooldown = 0.08 }
DEFS.step_water = {
  gen = function()
    local body = lp(0.3)
    return synth(0.16, function(t, p)
      local f = 420 + 700 * p
      return (body(noise()) * 0.8 + math.sin(t * f * TAU) * 0.35) * math.sin(math.min(1, p * 6) * math.pi * 0.5) * math.exp(-p * 7)
    end)
  end,
  volume = 0.06,
  cooldown = 0.08,
}

-- Reloads, one voice per gun ------------------------------------------------------------
-- The animation (src.playeranim) fires "eject", "click" and "snap" moments;
-- each model answers with its own sounds.

local function ting(f, t0, decay)
  return { t = t0, kind = "ting", f = f, d = decay or 22 }
end

DEFS.rev_eject = { -- shells tapped out of the cylinder and bouncing about
  gen = function()
    return timeline(0.45, { { t = 0, kind = "click", f = 700, d = 60 }, ting(2900, 0.05), ting(3300, 0.11), ting(2600, 0.16), ting(3100, 0.24), ting(3700, 0.3), ting(2800, 0.36) })
  end,
  volume = 0.4,
}
DEFS.rev_load = { -- every round in: the cylinder spun to a stop, ticks slowing down
  gen = function()
    local events = {}
    local t = 0
    for i = 0, 6 do
      events[#events + 1] = { t = t, kind = "click", f = 1500 - i * 70, d = 90 }
      t = t + 0.02 + i * 0.012
    end
    return timeline(0.4, events)
  end,
  volume = 0.4,
}
DEFS.rev_close = { -- the end of it: one crisp click
  gen = function()
    return timeline(0.12, { { t = 0, kind = "click", f = 1100, d = 70 }, { t = 0.004, kind = "thump", f = 220, d = 50, gain = 0.5 } })
  end,
  volume = 0.5,
}
DEFS.sg_break = { -- the hinge: a metal clack and a creak
  gen = function()
    return timeline(0.3, { { t = 0, kind = "thump", f = 170, d = 30, gain = 0.8 }, { t = 0, kind = "click", f = 700, d = 45 }, { t = 0.02, kind = "swish", len = 0.16, gain = 0.15 } })
  end,
  volume = 0.5,
}
DEFS.sg_eject = { -- two hulls hitting the floor
  gen = function()
    return timeline(0.3, { { t = 0.02, kind = "thump", f = 110, d = 30, gain = 0.8 }, { t = 0.03, kind = "click", f = 420, d = 45 }, { t = 0.14, kind = "thump", f = 130, d = 34, gain = 0.6 }, { t = 0.15, kind = "click", f = 470, d = 50 } })
  end,
  volume = 0.4,
}
DEFS.sg_shell = {
  gen = function()
    return timeline(0.18, { { t = 0, kind = "thump", f = 180, d = 38, gain = 0.8 }, { t = 0, kind = "click", f = 1100, d = 70 } })
  end,
  volume = 0.4,
}
DEFS.sg_close = { -- snapped shut with a flick: a clack and a low thud
  gen = function()
    return timeline(0.26, { { t = 0, kind = "click", f = 520, d = 38 }, { t = 0.01, kind = "thump", f = 90, d = 22, gain = 1.0 }, ting(1600, 0.015, 40) })
  end,
  volume = 0.55,
}
-- Broomhandle: the magazine drops, a new one goes in, a click
DEFS.pi_magdrop = {
  gen = function()
    return timeline(0.4, { { t = 0, kind = "click", f = 800, d = 70 }, { t = 0.08, kind = "thump", f = 95, d = 24, gain = 0.9 }, { t = 0.085, kind = "click", f = 420, d = 40 }, { t = 0.15, kind = "click", f = 1500, d = 90 } })
  end,
  volume = 0.5,
}
DEFS.pi_magin = {
  gen = function()
    return timeline(0.26, { { t = 0, kind = "swish", len = 0.05, gain = 0.3 }, { t = 0.05, kind = "click", f = 1000, d = 60 }, { t = 0.06, kind = "thump", f = 140, d = 36, gain = 0.8 }, { t = 0.11, kind = "click", f = 1700, d = 90 } })
  end,
  volume = 0.5,
}
DEFS.pi_click = {
  gen = function()
    return timeline(0.1, { { t = 0, kind = "click", f = 1300, d = 80 }, { t = 0.003, kind = "thump", f = 200, d = 50, gain = 0.4 } })
  end,
  volume = 0.5,
}

-- Machine gun: the clip drops out and rings, a few sounds as the new one goes in, a click
DEFS.mg_eject = {
  gen = function()
    return timeline(0.5, { { t = 0, kind = "click", f = 600, d = 50 }, { t = 0.03, kind = "thump", f = 85, d = 20, gain = 1.0 }, { t = 0.05, kind = "ting", f = 1900, d = 22 }, { t = 0.2, kind = "thump", f = 100, d = 30, gain = 0.6 }, { t = 0.21, kind = "ting", f = 2300, d = 30 } })
  end,
  volume = 0.5,
}
DEFS.mg_load = {
  gen = function()
    local events = { { t = 0, kind = "swish", len = 0.07, gain = 0.3 }, { t = 0.07, kind = "thump", f = 90, d = 22, gain = 1.0 }, { t = 0.07, kind = "click", f = 520, d = 40 } }
    for i = 1, 4 do
      events[#events + 1] = { t = 0.12 + i * 0.03, kind = "click", f = 1200 + (i % 3) * 350, d = 85 }
    end
    return timeline(0.4, events)
  end,
  volume = 0.55,
}
DEFS.mg_click = {
  gen = function()
    return timeline(0.1, { { t = 0, kind = "click", f = 900, d = 60 }, { t = 0.004, kind = "thump", f = 160, d = 40, gain = 0.5 } })
  end,
  volume = 0.5,
}

-- Gatling: the hopper shaken like a chain, the barrels spun up and slowed, a click
DEFS.gat_rattle = {
  gen = function()
    local events = {}
    local t = 0
    local f = 0
    while t < 1.0 do
      f = f + 1
      events[#events + 1] = { t = t, kind = (f % 3 == 0) and "ting" or "click", f = 2200 + ((f * 7919) % 2600), d = 40 + (f * 31) % 40 }
      t = t + 0.012 + ((f * 13) % 9) * 0.004
    end
    events[#events + 1] = { t = 0, kind = "swish", len = 1.0, gain = 0.15 }
    return timeline(1.15, events)
  end,
  volume = 0.4,
}
DEFS.gat_spin = {
  gen = function()
    local events = {}
    local t = 0
    for i = 0, 17 do
      local speed = math.sin(i / 17 * math.pi) -- speeds up, then slows to a stop
      events[#events + 1] = { t = t, kind = "click", f = 1400 + speed * 600, d = 80 }
      t = t + 0.065 - 0.045 * speed
    end
    return timeline(t + 0.15, events)
  end,
  volume = 0.4,
}
DEFS.gat_click = {
  gen = function()
    return timeline(0.1, { { t = 0, kind = "click", f = 800, d = 55 }, { t = 0.004, kind = "thump", f = 130, d = 36, gain = 0.6 } })
  end,
  volume = 0.5,
}

-- Distant things: heard from far off, panned and quieted by distance (audio.playAt) --------

DEFS.growl_far = {
  gen = function()
    local body = lp(0.04)
    local ph = 0
    return synth(1.8, function(t, p)
      local f = 52 + 18 * math.sin(p * 9) + 14 * math.sin(p * math.pi)
      ph = ph + f / RATE
      local env = math.sin(p * math.pi) ^ 1.5
      return (math.sin(ph * TAU) * 0.6 + math.sin(ph * 2 * TAU + 1) * 0.3 + body(noise()) * 1.2) * env
    end)
  end,
  volume = 0.5,
  cooldown = 0.5,
}
DEFS.rumble = {
  gen = function()
    local body = lp(0.025)
    return synth(2.4, function(t, p)
      return body(noise()) * 3.5 * math.sin(p * math.pi) ^ 1.2
    end)
  end,
  volume = 0.45,
  cooldown = 1,
}
DEFS.crackle = { -- a fire's small pops, fed to it as one sound
  gen = function()
    return synth(0.5, function(t, p)
      local v = 0
      if math.random() < 0.012 then
        v = noise() * 0.9
      end
      return v + noise() * 0.05
    end)
  end,
  volume = 0.25,
  cooldown = 0.3,
}
DEFS.lava_bubble = {
  gen = function()
    local body = lp(0.2)
    return synth(0.28, function(t, p)
      local f = 90 + 220 * p
      return (math.sin(t * f * TAU) * 0.6 + body(noise()) * 0.3) * math.sin(p * math.pi) ^ 0.7 * math.exp(-p * 2)
    end)
  end,
  volume = 0.4,
  cooldown = 0.15,
}
DEFS.steam_hiss = {
  gen = function()
    local hi = hp(0.5)
    return synth(0.7, function(t, p)
      return hi(noise()) * 0.5 * math.sin(math.min(1, p * 8) * math.pi * 0.5) * math.exp(-p * 4)
    end)
  end,
  volume = 0.3,
  cooldown = 0.2,
}
DEFS.acid_fizz = {
  gen = function()
    local hi = hp(0.4)
    return synth(0.35, function(t, p)
      local pop = math.random() < 0.05 and 1 or 0
      return hi(noise()) * 0.2 * math.exp(-p * 3) + pop * noise() * 0.5
    end)
  end,
  volume = 0.3,
  cooldown = 0.2,
}
DEFS.wind_gust = {
  gen = function()
    local body = lp(0.05)
    return synth(2.2, function(t, p)
      return body(noise()) * 2.2 * math.sin(p * math.pi) ^ 2 + math.sin(t * 520 * TAU + math.sin(t * 6) * 4) * 0.03 * math.sin(p * math.pi)
    end)
  end,
  volume = 0.35,
  cooldown = 1,
}
DEFS.skitter = {
  gen = function()
    return synth(0.35, function(t, p)
      local tick = (math.floor(t * 55) % 2 == 0 and 1 or 0) * (math.random() < 0.5 and 1 or 0.3)
      return noise() * tick * 0.35 * math.sin(p * math.pi)
    end)
  end,
  volume = 0.2,
  cooldown = 0.2,
}
DEFS.wing_flutter = {
  gen = function()
    local body = lp(0.3)
    return synth(0.4, function(t, p)
      return body(noise()) * (0.5 + 0.5 * math.sin(t * 38 * TAU)) * 0.9 * math.sin(p * math.pi)
    end)
  end,
  volume = 0.2,
  cooldown = 0.3,
}

-- Beds ------------------------------------------------------------------------------
-- The desert wind over the surface (the areas have music instead, see below)

local BEDS = {
  -- The menu's void: a deep, slowly beating hum under a low roar of falling
  -- air, with a thin glassy whistle drifting in and out
  void = function()
    local low = lp(0.015)
    local mid = lp(0.08)
    return synthLoop(8, function(t, p)
      local swell = 0.65 + 0.35 * math.sin(p * 2 * math.pi)
      local hum = math.sin(t * 36 * TAU) * 0.45 + math.sin(t * 36.5 * TAU) * 0.35 + math.sin(t * 54 * TAU) * 0.12
      local roar = low(noise()) * 2.6 * swell + mid(noise()) * 0.25
      local whistle = math.sin(t * 1244 * TAU + math.sin(t * 0.75 * TAU) * 3) * 0.035 * (0.5 + 0.5 * math.sin(p * 4 * math.pi))
      return (hum * (0.8 + 0.2 * math.sin(p * 6 * math.pi)) + roar + whistle) * 0.55
    end)
  end,
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

-- The title screen's theme: a slow, cold drift in D minor with a glassy bell
-- line, falling away into a long echo
local MENU_TRACK = {
  bpm = 50,
  bars = 8,
  echo = { delay = 0.72, fb = 0.55 },
  prog = { "Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A" },
  chords = {
    Dm = { root = "D2", fifth = "A2", pad = { "D3", "A3", "D4", "F4" }, notes = { "D4", "F4", "A4", "D5", "E5" } },
    Bb = { root = "Bb1", fifth = "F2", pad = { "Bb2", "F3", "Bb3", "D4" }, notes = { "Bb3", "D4", "F4", "A4", "D5" } },
    Gm = { root = "G1", fifth = "D2", pad = { "G2", "D3", "G3", "Bb3" }, notes = { "G3", "Bb3", "D4", "G4", "A4" } },
    A = { root = "A1", fifth = "E2", pad = { "A2", "E3", "A3", "C#4" }, notes = { "A3", "C#4", "E4", "A4", "C#5" } },
  },
  channels = {
    { wave = "tri", gain = 0.13, steps = 1, a = 1.6, r = 1.4, legato = 1.0, tokens = padPattern() },
    { wave = "saw", gain = 0.025, steps = 1, a = 2.0, r = 1.4, legato = 1.0, tokens = padPattern() },
    { wave = "sine", gain = 0.32, steps = 1, a = 0.8, r = 1.0, legato = 1.0, tokens = bassPattern("R") },
    { wave = "sine", gain = 0.09, steps = 8, pluck = 2.2, tokens = arpPattern({ 1, 0, 0, 3, 0, 0, 5, 0 }) },
    {
      wave = "p125", gain = 0.035, steps = 8, pluck = 3.5,
      tokens = explicit({
        "A5 . . . - - - -", "- - - - D6 . . .", "F5 . . . - - - -", "- - E5 . . . D5 .",
        "D5 . . . - - - -", "- - - - Bb5 . . .", "A5 . . . - - - -", "- - - - C#6 . . .",
      }),
    },
  },
}

-- The death recap's theme: very slow and sad, E minor (Em, C, G, D), a lonely
-- sine lead with a slow vibrato over soft pads and a deep sub, a few distant
-- bells, and a long echo
local RECAP_TRACK = {
  bpm = 42,
  bars = 8,
  echo = { delay = 0.8, fb = 0.6 },
  prog = { "Em", "Em", "C", "C", "G", "G", "D", "D" },
  chords = {
    Em = { root = "E2", fifth = "B2", pad = { "E3", "B3", "E4", "G4" }, notes = { "E4", "G4", "B4", "D5", "E5" } },
    C = { root = "C2", fifth = "G2", pad = { "C3", "G3", "C4", "E4" }, notes = { "C4", "E4", "G4", "B4", "C5" } },
    G = { root = "G1", fifth = "D2", pad = { "G2", "D3", "G3", "B3" }, notes = { "G3", "B3", "D4", "G4", "A4" } },
    D = { root = "D2", fifth = "A2", pad = { "D3", "A3", "D4", "F#4" }, notes = { "D4", "F#4", "A4", "C5", "D5" } },
  },
  channels = {
    { wave = "tri", gain = 0.12, steps = 1, a = 2.0, r = 1.8, legato = 1.0, tokens = padPattern() },
    { wave = "saw", gain = 0.02, steps = 1, a = 2.4, r = 1.8, legato = 1.0, tokens = padPattern() },
    { wave = "sine", gain = 0.30, steps = 1, a = 1.0, r = 1.2, legato = 1.0, tokens = bassPattern("R") },
    {
      wave = "sine", gain = 0.11, steps = 4, a = 0.12, r = 1.0, legato = 1.0, vib = { 4.6, 0.009 },
      tokens = explicit({
        "B4 . . .", "G4 . E4 .", "G4 . . .", "E4 . C4 .",
        "D5 . . .", "B4 . G4 .", "A4 . . F#4", "A4 . . .",
      }),
    },
    { wave = "tri", gain = 0.05, steps = 8, pluck = 2.6, tokens = arpPattern({ 0, 0, 0, 0, 5, 0, 0, 0 }) },
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

-- A tension layer for an area's theme: kick and snare, ticking hats and a
-- sawtooth drone on the chord roots, laid over the same chords, tempo and
-- length so it stays in step with the theme itself
local function tensionDef(base)
  return {
    bpm = base.bpm,
    bars = base.bars,
    repeats = base.repeats,
    echo = base.echo,
    prog = base.prog,
    chords = base.chords,
    channels = {
      { drum = true, gain = 0.5, steps = 8, tokens = everyBar("k - - k k - s - ") },
      { drum = true, gain = 0.2, steps = 8, tokens = everyBar("h h h h h h h h") },
      { wave = "saw", gain = 0.06, steps = 1, a = 0.3, r = 0.6, legato = 1.0, tokens = bassPattern("R") },
      { wave = "tri", gain = 0.1, steps = 2, a = 0.05, r = 0.3, legato = 0.7, tokens = bassPattern("R 5") },
    },
  }
end

-- Setup and playback ---------------------------------------------------------------------

local areaMusic = {} -- the area themes, one looping source each
local tensionMusic = {} -- a driving layer per area (drums, a low drone) that fades in when monsters are on the hunter
local tension, tensionTarget = 0, 0
local effectsOk = false -- OpenAL effects (reverb) available
local space, spaceTarget = 0, 0 -- how big the place the hunter stands in is: 0 tight tunnel .. 1 cavern, -1 open air
local listenerX, listenerY = 0, 0
local lastSpace -- the reverb setting last sent
local MAX_HEARD = 460 -- px: beyond this a positional sound is silent
-- Areas whose theme is a recorded file (looped) rather than synthesised.
-- To change one: replace the file (or point this at a different one). Its
-- volume is set automatically from how loud the recording is (AREA_GAIN is
-- filled in at load), so a new file needs no tuning.
local AREA_FILES = { [1] = "audio/caves.wav", [2] = "audio/saxo.wav" }
local SHOP_FILE = "audio/shop.wav" -- the shop's music (the synthesised piano if it is missing)
local shopGain = 1
local AREA_GAIN = {}
local TARGET_RMS = 0.126 -- the loudness (RMS, 0..1) a recorded theme is brought to
local menuMusic -- the title screen's theme
local recapMusic -- the death recap's theme

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
    local shopOk, shopSrc = pcall(function()
      local data = love.sound.newSoundData(SHOP_FILE)
      local sum, n = 0, 0
      for k = 0, data:getSampleCount() * data:getChannelCount() - 1, 40 do
        local v = data:getSample(k)
        sum, n = sum + v * v, n + 1
      end
      local rms = math.sqrt(sum / math.max(1, n))
      shopGain = rms > 0.001 and math.max(0.3, math.min(1.5, TARGET_RMS / rms)) or 1
      return love.audio.newSource(data, "static")
    end)
    music = shopOk and shopSrc or love.audio.newSource(composeShopMusic(), "static")
    music:setLooping(true)
    music:setVolume(0)
    for i, def in ipairs(TRACKS) do
      -- A recorded track takes the place of an area's synthesised theme
      local file = AREA_FILES[i]
      local src
      if file and love.filesystem.getInfo(file) then
        local ok, loaded = pcall(function()
          local data = love.sound.newSoundData(file)
          -- Its loudness: the RMS of every 40th sample
          local sum, n = 0, 0
          for k = 0, data:getSampleCount() * data:getChannelCount() - 1, 40 do
            local v = data:getSample(k)
            sum, n = sum + v * v, n + 1
          end
          local rms = math.sqrt(sum / math.max(1, n))
          AREA_GAIN[i] = rms > 0.001 and math.max(0.3, math.min(1.5, TARGET_RMS / rms)) or 1
          return love.audio.newSource(data, "static")
        end)
        src = ok and loaded or nil
      end
      src = src or love.audio.newSource(renderTrack(def), "static")
      src:setLooping(true) -- (it starts over as soon as it finishes)
      src:setVolume(0)
      areaMusic[i] = src
    end
    for i, def in ipairs(TRACKS) do
      local made, data = pcall(function()
        return renderTrack(tensionDef(def))
      end)
      if made then
        local src = love.audio.newSource(data, "static")
        src:setLooping(true)
        src:setVolume(0)
        tensionMusic[i] = src
      end
    end
    menuMusic = love.audio.newSource(renderTrack(MENU_TRACK), "static")
    menuMusic:setLooping(true)
    menuMusic:setVolume(0)
    recapMusic = love.audio.newSource(renderTrack(RECAP_TRACK), "static")
    recapMusic:setLooping(true)
    recapMusic:setVolume(0)
    pcall(love.audio.setDistanceModel, "none") -- (positional sounds are only panned; their volume is set by hand)
    effectsOk = love.audio.isEffectsSupported and love.audio.isEffectsSupported() or false
    if effectsOk then
      effectsOk = pcall(love.audio.setEffect, "env", { type = "reverb", gain = 0.0, decaytime = 0.6, density = 0.6, diffusion = 0.8, highgain = 0.6 })
    end
    enabled = true
  end)
  if not ok then
    enabled = false
  end
end

-- Plays a named sound. volume scales it; pitch (default 1) is varied a little.
-- With x, y (world pixels) it is heard from there: panned left and right of
-- the listener and quieter the further away it is.
-- A voice for a sound: one of its own that has finished, or a new one. All of
-- a sound's voices share one buffer (clones of the first): a new source made
-- from the samples for every shot, hit and coin copied the whole sound into a
-- fresh buffer each time.
local VOICES_PER_SOUND = 8
local function voice(def)
  local pool = def.pool
  if not pool then
    pool = {}
    def.pool = pool
  end
  for _, s in ipairs(pool) do
    if not s:isPlaying() then
      s:stop() -- (back to the start)
      return s
    end
  end
  if #pool >= VOICES_PER_SOUND then
    return nil
  end
  local ok, src
  if pool[1] then
    ok, src = pcall(pool[1].clone, pool[1])
  else
    ok, src = pcall(love.audio.newSource, def.data, "static")
  end
  if not ok then
    return nil
  end
  if effectsOk and not def.dry then
    pcall(src.setEffect, src, "env")
  end
  pool[#pool + 1] = src
  return src
end

local function start(name, volume, pitch, x, y)
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
  local gain = volume or 1
  local dx, dy
  if x then
    dx, dy = x - listenerX, y - listenerY
    local d = math.sqrt(dx * dx + dy * dy)
    if d >= MAX_HEARD then
      return -- (out of earshot: no voice taken)
    end
    gain = gain * (1 - d / MAX_HEARD) ^ 1.5
  end
  local src = voice(def)
  if not src then
    return
  end
  if x then
    src:setRelative(true)
    src:setPosition(math.max(-1, math.min(1, dx / 160)), 0, -0.4)
  else
    src:setRelative(false)
    src:setPosition(0, 0, 0)
  end
  src:setVolume(def.volume * gain * MASTER * volMaster * volSfx * (0.9 + love.math.random() * 0.2))
  src:setPitch((pitch or 1) * (0.94 + love.math.random() * 0.12))
  if muffled then
    pcall(src.setFilter, src, MUFFLE)
  else
    pcall(src.setFilter, src)
  end
  src:play()
  playing[#playing + 1] = src
end

function audio.play(name, volume, pitch)
  start(name, volume, pitch)
end

function audio.playAt(name, x, y, volume, pitch)
  start(name, volume, pitch, x, y)
end

-- Where the hunter's ears are (call every frame)
function audio.setListener(x, y)
  listenerX, listenerY = x, y
end

-- Scales the surface wind bed (the weather sets it: louder in a dust storm)
local windGain = 1
function audio.setWindGain(g)
  windGain = g
end

-- How big a place the hunter is in, -1 (open air: no echo) to 0 (a tight
-- tunnel) to 1 (a cavern): sets the reverb the sounds go through
function audio.setSpace(v)
  spaceTarget = v
end

-- 0..1: how hard monsters are pressing the hunter (drives the music's tension layer)
function audio.setTension(v)
  tensionTarget = math.max(0, math.min(1, v or 0))
end

local eventTimers = {}
local lastArea
local AREA_TRACK = { [6] = 1, [7] = 3, [8] = 2, [9] = 5, [10] = 1, [11] = 2 } -- areas that borrow another's music and sounds

-- Fades the wind, the area themes and the shop's piano: underground is 0 (open
-- air) to 1; area is the number of the area the hunter is in (nil on the
-- surface); inShop is true inside a shop room, where the piano plays instead of
-- the area's theme
function audio.update(dt, underground, paused, area, inShop, muffle)
  if not enabled then
    return
  end
  area = area and (AREA_TRACK[area] or area) -- (a side branch plays another area's theme)
  -- The weapon panel: the same sounds, but as if through a wall (a low-pass
  -- filter on everything playing; without effects support, just quieter)
  if (muffle and true or false) ~= muffled then
    muffled = muffle and true or false
    local filter = muffled and MUFFLE or nil
    local function apply(src)
      if src then
        pcall(src.setFilter, src, filter)
      end
    end
    apply(ambient.wind)
    apply(music)
    for _, src in ipairs(areaMusic) do
      apply(src)
    end
    for _, src in ipairs(playing) do
      apply(src)
    end
  end
  -- Reverb follows the size of the space: dry in the open, a short slap in
  -- tunnels, a long wash in caverns
  space = space + (spaceTarget - space) * math.min(1, dt * 1.5)
  if effectsOk and math.abs(space - (lastSpace or 99)) > 0.01 then
    lastSpace = space
    local big = math.max(0, space)
    pcall(love.audio.setEffect, "env", {
      type = "reverb",
      gain = space < 0 and 0.01 or 0.11 + 0.25 * big,
      decaytime = 0.4 + 1.9 * big,
      decayhighratio = 0.65,
      density = 0.4 + 0.5 * big,
      diffusion = 0.9,
      highgain = 0.5,
      latedelay = 0.011 + 0.05 * big,
      earlydelay = 0.007 + 0.03 * big,
    })
  end
  tension = tension + (tensionTarget - tension) * math.min(1, dt * (tensionTarget > tension and 1.2 or 0.3))
  -- The title screens play the void and the menu theme over silence
  local function toward(src, target, k)
    src:setVolume(src:getVolume() + (target - src:getVolume()) * k)
  end
  if not menuMusic:isPlaying() then
    menuMusic:play()
  end
  if not ambient.void:isPlaying() then
    ambient.void:play()
  end
  local k = menuMode and math.min(1, dt * 0.8) or math.min(1, dt * 3)
  toward(menuMusic, menuMode and 0.16 * MASTER * 2 * volMaster * volMusic or 0, k)
  toward(recapMusic, recapMode and 0.2 * MASTER * 2 * volMaster * volMusic or 0, recapMode and math.min(1, dt * 0.6) or math.min(1, dt * 3))
  if recapMode and not recapMusic:isPlaying() then
    recapMusic:play()
  end
  toward(ambient.void, menuMode and 0.16 * MASTER * 2 * volMaster * volSfx or 0, k)
  if paused or menuMode then
    for name, src in pairs(ambient) do
      if name ~= "void" then
        src:setVolume(0)
      end
    end
    for _, src in ipairs(areaMusic) do
      src:setVolume(0)
    end
    for _, src in pairs(tensionMusic) do
      src:setVolume(0)
    end
    music:setVolume(0)
    return
  end
  for name, src in pairs(ambient) do
    if name ~= "void" and not src:isPlaying() then
      src:play()
    end
  end
  for _, src in ipairs(areaMusic) do
    if not src:isPlaying() then
      src:play()
    end
  end
  for _, src in pairs(tensionMusic) do
    if not src:isPlaying() then
      src:play()
    end
  end
  if not music:isPlaying() then
    music:play()
  end
  local fade = math.min(1, dt * 1.2)
  local wind = ambient.wind
  wind:setVolume(wind:getVolume() + (0.10 * windGain * (1 - underground) * MASTER * 2 * volMaster * volSfx - wind:getVolume()) * math.min(1, dt * 1.5))
  for i, src in ipairs(areaMusic) do
    local target = ((i == area and not inShop) and 0.10 * underground or 0) * (AREA_GAIN[i] or 1)
    src:setVolume(src:getVolume() + (target * MASTER * 2 * volMaster * volMusic - src:getVolume()) * fade)
  end
  for i, src in pairs(tensionMusic) do
    local target = ((i == area and not inShop) and 0.09 * underground * tension or 0) * (AREA_GAIN[i] or 1)
    src:setVolume(src:getVolume() + (target * MASTER * 2 * volMaster * volMusic - src:getVolume()) * math.min(1, dt * 2))
  end
  music:setVolume(music:getVolume() + ((inShop and 0.13 * shopGain or 0) * MASTER * 2 * volMaster * volMusic - music:getVolume()) * fade)

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

-- Volume settings (src.settings): master, music and sound effects, each 0..1
function audio.setVolumes(master, musicVol, sfx)
  volMaster, volMusic, volSfx = master or 1, musicVol or 1, sfx or 1
end

-- An area's music source (for tests)
function audio.areaTrack(i)
  return areaMusic[i]
end

-- The title screens: the void's drone and the menu theme instead of the world
function audio.setMenu(on)
  menuMode = on and true or false
end

-- The death recap's theme instead of the world
function audio.setRecap(on)
  recapMode = on and true or false
  if recapMode and recapMusic then
    recapMusic:stop()
    recapMusic:setVolume(0)
  end
end

return audio
