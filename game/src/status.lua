-- Conditions on the hunter: Soaked, Oiled, Burning, Poisoned and Shocked. They come from the world's liquids and
-- hazards (src.fluids) and from a few enemies' attacks (Player:hurt maps the attacker to a condition), last a while,
-- and play against each other:
--
--   Soaked    from water, 12 s after leaving it, or two rolls (he shakes the water off).  Puts out Burning and washes
--             Oiled off; Burning can't take hold while it lasts. But shocks hurt 75% more and stun 50% longer.
--   Oiled     from oil, 15 s (or until washed).  Burning lasts 80% longer and hurts 50% more; the hunter slides
--             on the ground (a third of the grip). Can't be oiled while swimming.
--   Burning   from fire, lava, flame attacks, 4 s.  2 damage every half second (3 if Oiled), a little faster on
--             the feet. Two rolls smother it; water puts it out. He sheds orange sparks and wisps, and lights
--             any gas or oil he touches.
--   Poisoned  from gas, acid, spitters, 6 s.  1-3 damage every 0.8 s by its stacks (gas builds them the longer he
--             breathes it), and a slower walk.
--   Shocked   from shock rounds in water, lightning, jellyfish, storms, 0.8 s.  Staggers: a fraction of walking
--             speed, no jumping or rolling.
--
-- The conditions show in the health bottle (src.hud reads status.hud): each changes the liquid in it. They are
-- also in the compendium (category "condition"), found the first time one is felt.
local effects = require("src.effects")

local status = {}

status.ORDER = { "soaked", "oiled", "burning", "poisoned", "shocked" }

status.DEFS = {
  soaked = {
    name = "Soaked",
    color = { 0.45, 0.75, 1.0 },
    desc = "Water running off the hunter. It puts out any fire on him and keeps new fire from taking hold, but it carries a current: shocks hurt a good deal more and stun a good deal longer. Two rolls shake it off.",
    stats = { { "From", "Water" }, { "Lasts", "12 s, 2 rolls" }, { "Fire", "Put out" }, { "Shock", "+75%" } },
  },
  oiled = {
    name = "Oiled",
    color = { 0.32, 0.26, 0.40 },
    desc = "A black film of lamp oil. It makes him burn longer and hotter, and his boots slide on it. Water washes it off.",
    stats = { { "From", "Oil" }, { "Lasts", "15 s" }, { "Fire", "+80% long" }, { "Cure", "Water" } },
  },
  burning = {
    name = "Burning",
    color = { 1.0, 0.55, 0.15 },
    desc = "He's on fire. It keeps hurting after he leaves the flames. Two rolls smother it, water puts it out, and a burning hunter lights any gas or oil he touches.",
    stats = { { "From", "Fire, lava" }, { "Lasts", "4 s, 2 rolls" }, { "Damage", "2 / 0.5 s" }, { "Cure", "Rolls, water" } },
  },
  poisoned = {
    name = "Poisoned",
    color = { 0.62, 0.86, 0.26 },
    desc = "Venom or fumes working through him. It ticks harder the more of it he has taken in, and slows him. Breathing gas builds it up.",
    stats = { { "From", "Gas, acid" }, { "Lasts", "12 s" }, { "Damage", "1-3 / 0.8 s" }, { "Slows", "Up to 16%" } },
  },
  shocked = {
    name = "Shocked",
    color = { 0.72, 0.86, 1.0 },
    desc = "A current through the body. For a moment he can barely move: no jumping, no rolling. Worse when he's soaked.",
    stats = { { "From", "Shock, storms" }, { "Lasts", "0.8 s" }, { "Moves", "At 25%" }, { "No", "Jump, roll" } },
  },
}

-- Which condition an attacker (a source id, see src.deaths) leaves behind, and for how long
local SOURCE = {
  spitter = { "poisoned", 10 },
  bloater = { "poisoned", 8 },
  hopper = { "poisoned", 6 },
  acid = { "poisoned", 8 },
  gas = { "poisoned", 6 },
  wisp = { "burning", 3 },
  slagback = { "burning", 4 },
  lava = { "burning", 5 },
  fire = { "burning", 4 },
  starguardian = { "burning", 3 },
  cometling = { "burning", 3 },
  jellyfish = { "shocked", 0.8 },
  lightning = { "shocked", 1.0 },
  stormcloud = { "shocked", 1.0 },
  shock = { "shocked", 0.8 },
  arcbeetle = { "shocked", 0.8 },
  torchbearer = { "burning", 3 },
  tarcrawler = { "oiled", 10 },
}

local DURATION = { soaked = 12, oiled = 15, burning = 4, poisoned = 12, shocked = 0.8 }

local BURN_TICK, POISON_TICK = 0.5, 0.8
local ROLLS_TO_SHAKE = 2 -- rolls (seen through to the end) that shake off Soaked or put out Burning

function status.reset(player)
  player.status = {}
  player.statusSeen = {}
end

local function table_(p)
  p.status = p.status or {}
  return p.status
end

function status.has(p, kind)
  local s = p.status and p.status[kind]
  return s ~= nil and s.t > 0
end

function status.stacks(p, kind)
  local s = p.status and p.status[kind]
  return s and s.t > 0 and (s.stacks or 1) or 0
end

-- Puts a condition on the hunter (or refreshes it). opts.stacks: poison's stack count to rise to at least.
-- Returns whether it took.
function status.apply(p, kind, dur, opts)
  if not p or p.dead or not DURATION[kind] then
    return false
  end
  local S = table_(p)
  dur = dur or DURATION[kind]
  -- How they play against each other
  if kind == "burning" then
    if status.has(p, "soaked") or p.inWater or p.submerged then
      return false
    end
    if status.has(p, "oiled") then
      dur = dur * 1.8
    end
  elseif kind == "soaked" then
    if S.burning and S.burning.t > 0 then
      local cx, cy = p:center()
      for _ = 1, 8 do
        effects.particle(cx + (love.math.random() - 0.5) * 8, cy + (love.math.random() - 0.5) * 12, (love.math.random() - 0.5) * 20, -20 - love.math.random() * 25, 0.7, { 0.8, 0.82, 0.86 }, -10)
      end
      effects.popup(cx, p.body.y - 8, "Doused", { 0.7, 0.85, 1 })
    end
    S.burning = nil
    S.oiled = nil
  elseif kind == "oiled" then
    if p.inWater or p.submerged or status.has(p, "soaked") then
      return false
    end
  elseif kind == "shocked" then
    if status.has(p, "soaked") then
      dur = dur * 1.5
    end
  end
  local s = S[kind]
  local first = s == nil or s.t <= 0
  if first then
    s = { t = 0, max = dur, tick = 0, stacks = 1 }
    S[kind] = s
  end
  s.t = math.max(s.t, dur)
  s.rolls = 0 -- (fresh contact: the rolls start again)
  s.max = math.max(s.max, s.t)
  if kind == "poisoned" then
    local want = (opts and opts.stacks) or 1
    if first or want > s.stacks then
      s.stacks = math.min(3, math.max(first and 1 or s.stacks, want))
    end
    if opts and opts.add then
      s.stacks = math.min(3, s.stacks + opts.add)
    end
  end
  if first then
    status.onFirst(p, kind)
  end
  return true
end

-- The first time one is felt in a run: its name over the hunter, and the compendium learns it (once per profile)
function status.onFirst(p, kind)
  p.statusSeen = p.statusSeen or {}
  local cx = p:center()
  local d = status.DEFS[kind]
  if not p.statusSeen[kind] then
    p.statusSeen[kind] = true
    effects.popup(cx, p.body.y - 14, d.name, d.color)
  end
  pcall(function()
    require("src.save").record("condition", kind)
  end)
end

-- The condition's icon for a death source that was one (fire, lava, poison, gas, acid, a shock), for the wanted poster
local DEATH_ICON = { fire = "burning", lava = "burning", poison = "poisoned", gas = "poisoned", acid = "poisoned", shock = "shocked", lightning = "shocked" }
function status.iconForSource(source)
  local kind = source and DEATH_ICON[source]
  return kind and status.icon(kind) or nil
end

-- The condition an attacker leaves, if any (called when it hurts the hunter)
function status.fromSource(p, source)
  local m = source and SOURCE[source]
  if m then
    status.apply(p, m[1], m[2])
  end
end

-- Shock damage and how long the stun lasts, for the hunter's state (called by fluids.zap)
function status.shockMult(p)
  return status.has(p, "soaked") and 1.75 or 1
end

function status.speedMult(p)
  local m = 1
  if status.has(p, "shocked") then
    m = m * 0.35
  end
  if status.has(p, "poisoned") then
    m = m * (1 - 0.04 * status.stacks(p, "poisoned") - 0.04)
  end
  if status.has(p, "burning") then
    m = m * 1.12
  end
  return m
end

-- Slippery boots: how much grip the ground has (1 normally)
function status.gripMult(p)
  return status.has(p, "oiled") and 0.45 or 1
end

function status.canJump(p)
  return not status.has(p, "shocked")
end

function status.canRoll(p)
  return not status.has(p, "shocked")
end

local function drip(p, color, rate, dt, up)
  if love.math.random() < rate * dt then
    local b = p.body
    effects.particle(b.x + 2 + love.math.random() * (b.w - 4), b.y + 6 + love.math.random() * (b.h - 10), (love.math.random() - 0.5) * 10, up and (-12 - love.math.random() * 20) or (8 + love.math.random() * 20), 0.5, color, up and -10 or 260)
  end
end

-- A dodge roll that went through to the end (src.player calls this as the roll finishes; one cut short by a jump
-- does not count): each one wears Soaked and Burning down, and the second shakes the water off or puts the fire out
function status.rollFinished(p)
  local S = p.status
  if not S or p.dead then
    return
  end
  local cx, cy = p:center()
  for _, kind in ipairs({ "soaked", "burning" }) do
    local s = S[kind]
    if s and s.t > 0 then
      s.rolls = (s.rolls or 0) + 1
      if s.rolls >= ROLLS_TO_SHAKE then
        S[kind] = nil
        for _ = 1, 6 do
          local c = kind == "burning" and { 0.55, 0.52, 0.5 } or { 0.6, 0.82, 1 }
          effects.particle(cx + (love.math.random() - 0.5) * 8, cy + (love.math.random() - 0.5) * 12, (love.math.random() - 0.5) * 40, -10 - love.math.random() * 25, 0.6, c, 20)
        end
        if kind == "burning" then
          effects.popup(cx, p.body.y - 8, "Put out", { 1, 0.75, 0.4 })
        end
      end
    end
  end
end

function status.update(p, dt)
  local S = p.status
  if not S or p.dead then
    if S and p.dead then
      p.status = {}
    end
    return
  end
  for kind, s in pairs(S) do
    s.t = s.t - dt
    if s.t <= 0 then
      S[kind] = nil
    end
  end
  local cx, cy = p:center()
  if S.soaked then
    drip(p, { 0.6, 0.82, 1 }, 5, dt)
  end
  if S.oiled then
    drip(p, { 0.12, 0.09, 0.16 }, 3, dt)
  end
  if S.burning then
    local s = S.burning
    s.tick = s.tick + dt
    if s.tick >= BURN_TICK then
      s.tick = s.tick - BURN_TICK
      p:hurtOverTime(S.oiled and 3 or 2, { 1, 0.55, 0.15 }, "fire")
    end
    -- Wisps and pixels of orange coming off him, rising and fading (no flames drawn on the body)
    local b = p.body
    local fade = math.min(1, s.t / 0.8)
    if love.math.random() < 60 * dt * fade then
      local pick = love.math.random()
      local c = pick < 0.5 and { 1.0, 0.50, 0.12 } or (pick < 0.85 and { 1.0, 0.68, 0.22 } or { 0.85, 0.30, 0.08 })
      effects.particle(b.x + 1 + love.math.random() * (b.w - 2), b.y + 3 + love.math.random() * (b.h - 6), (love.math.random() - 0.5) * 14, -14 - love.math.random() * 26, 0.55 + love.math.random() * 0.5, c, -18, true)
    end
    if love.math.random() < 8 * dt * fade then -- (now and then a dark ember of smoke)
      effects.particle(b.x + b.w / 2 + (love.math.random() - 0.5) * 4, b.y + 1, (love.math.random() - 0.5) * 8, -22 - love.math.random() * 14, 0.9, { 0.25, 0.22, 0.2 }, -8)
    end
    -- a burning hunter lights what he touches: gas and oil
    s.light = (s.light or 0) - dt
    if s.light <= 0 then
      s.light = 0.35
      require("src.fluids").ignite(cx, cy, 0.5, true)
    end
  end
  if S.poisoned then
    local s = S.poisoned
    s.tick = s.tick + dt
    if s.tick >= POISON_TICK then
      s.tick = s.tick - POISON_TICK
      p:hurtOverTime(s.stacks, { 0.62, 0.86, 0.26 }, "poison")
    end
    drip(p, { 0.62, 0.86, 0.26 }, 4 * s.stacks, dt, true)
  end
  if S.shocked then
    drip(p, { 0.75, 0.88, 1 }, 30, dt, true)
  end
end

-- ------------------------------------------------------------------------------------------------------------
-- The health bottle (src.hud): what the liquid in it looks like. nil when the hunter has no condition.
-- ------------------------------------------------------------------------------------------------------------
local function hue(h)
  h = h % 1
  local r = math.abs(h * 6 - 3) - 1
  local g = 2 - math.abs(h * 6 - 2)
  local b = 2 - math.abs(h * 6 - 4)
  return math.max(0, math.min(1, r)), math.max(0, math.min(1, g)), math.max(0, math.min(1, b))
end
status.hue = hue

function status.hud(p)
  local S = p.status
  if not S or not next(S) then
    return nil
  end
  local st = {
    soaked = S.soaked ~= nil, oiled = S.oiled ~= nil, burning = S.burning ~= nil, poisoned = S.poisoned ~= nil, shocked = S.shocked ~= nil,
    stacks = S.poisoned and S.poisoned.stacks or 0,
    shockT = S.shocked and S.shocked.t or 0,
  }
  -- the tint the whole liquid takes, and how strongly
  local tr, tg, tb, ta = 0, 0, 0, 0
  if st.burning then
    tr, tg, tb, ta = tr + 1.0, tg + 0.55, tb + 0.12, ta + 0.5
  end
  if st.poisoned then
    tr, tg, tb, ta = tr + 0.45, tg + 0.8, tb + 0.12, ta + 0.28 + 0.1 * st.stacks
  end
  if ta > 0 then
    local n = (st.burning and 1 or 0) + (st.poisoned and 1 or 0)
    tr, tg, tb = tr / n, tg / n, tb / n
    ta = math.min(0.75, ta)
  end
  st.tint = { tr, tg, tb, ta }
  -- surface line
  if st.burning then
    st.surface = { 1.0, 0.85, 0.35, 0.8 }
  elseif st.poisoned then
    st.surface = { 0.75, 1.0, 0.4, 0.7 }
  end
  -- How the rows near the surface look: oil on top, then water, then the blood (depth in HUD pixels)
  local oilDepth = st.oiled and 2 or 0
  local waterDepth = oilDepth + (st.soaked and 3 or 0)
  function st.liquid(r, g, b, depth, now)
    if depth >= 0 and depth < oilDepth then
      -- the oil: near black, a violet sheen
      return 0.07 + 0.06 * math.sin(now * 2), 0.05, 0.10 + 0.06 * math.sin(now * 2 + 1)
    elseif depth >= 0 and depth < waterDepth then
      return 0.30, 0.58, 0.85
    end
    if ta > 0 then
      local pulse = st.burning and (0.85 + 0.15 * math.sin(now * 9)) or 1
      r, g, b = r + (tr - r) * ta * pulse, g + (tg - g) * ta * pulse, b + (tb - b) * ta * pulse
    end
    return r, g, b
  end
  st.boil = (st.burning and 0.8 or 0) + (st.poisoned and 0.4 or 0)
  return st
end

-- ------------------------------------------------------------------------------------------------------------
-- Icons for the compendium: 12 x 12 pixel maps in each condition's colours
-- ------------------------------------------------------------------------------------------------------------
local ICON_MAPS = {
  soaked = {
    "............",
    ".....#......",
    "....###.....",
    "...#####....",
    "..###o###...",
    "..##oo###...",
    ".###o#####..",
    ".#########..",
    ".#########..",
    "..#######...",
    "...#####....",
    "............",
  },
  oiled = {
    "............",
    ".....#......",
    "....###.....",
    "...#####....",
    "..###v###...",
    "..##vv###...",
    ".###g#####..",
    ".##gg#####..",
    ".#########..",
    "..#######...",
    "...#####....",
    "............",
  },
  burning = {
    "......#.....",
    ".....##.....",
    ".....###....",
    "....####.#..",
    "...#####.#..",
    "..###y###...",
    ".####yy###..",
    ".###yyy###..",
    ".###yyy###..",
    "..##yyy##...",
    "...#####....",
    "............",
  },
  poisoned = {
    "............",
    "...######...",
    "..########..",
    ".##########.",
    ".##oo##oo##.",
    ".##oo##oo##.",
    ".###.##.###.",
    "..########..",
    "...#.##.#...",
    "...#.##.#...",
    "............",
    "............",
  },
  shocked = {
    "......##....",
    ".....##.....",
    "....##......",
    "...####.....",
    "......##....",
    ".....##.....",
    "....##......",
    "...##.......",
    "..##........",
    "..#.........",
    "............",
    "............",
  },
}

local icons = {}
function status.icon(kind)
  if icons[kind] then
    return icons[kind]
  end
  local map, d = ICON_MAPS[kind], status.DEFS[kind]
  if not map then
    return nil
  end
  local c = d.color
  local data = love.image.newImageData(12, 12)
  for y, row in ipairs(map) do
    for x = 1, #row do
      local ch = row:sub(x, x)
      if ch == "#" then
        data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1)
      elseif ch == "o" then
        data:setPixel(x - 1, y - 1, math.min(1, c[1] + 0.35), math.min(1, c[2] + 0.35), math.min(1, c[3] + 0.35), 1)
      elseif ch == "y" then
        data:setPixel(x - 1, y - 1, 1, 0.9, 0.45, 1)
      elseif ch == "v" then
        data:setPixel(x - 1, y - 1, 0.55, 0.4, 0.75, 1)
      elseif ch == "g" then
        data:setPixel(x - 1, y - 1, 0.25, 0.6, 0.55, 1)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  icons[kind] = img
  return img
end

return status
