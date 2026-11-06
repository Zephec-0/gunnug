-- The Hollow King: the last boss of the Undercroft, in the hall at the Core (docs/undercroft-design.md). The hunter
-- falls into a huge open hall. In the middle of it hangs the core, a faceted sphere of metal (drawn by a shader),
-- inert until it is shot. Shot, it comes apart: the camera pulls out and shakes while the sphere flies off in a
-- storm of particles, leaving a small prism of metal at the heart of it. The storm is the King: a hive of some
-- four hundred bits of light and stone that flows like a swarm and takes the shape of the bosses above him, one to a
-- turn, and fights as each of them did, slower and plainer so that it can be read.
--
-- The rule of the fight is the ground. The hall is made of what he is made of, so everything he does to it stays:
--   * His body is a screen. Shots into the swarm only scatter it (a sliver of damage); the prism at its heart takes
--     the blow, and it is only bare for a few seconds at the end of each chain of attacks (the swarm peels away from it
--     and it blazes), after a slam, a lunge, a sweep of light.
--   * Stones from the roof land as rubble you can stand on, hide behind and dig; his slams and beams knock it down.
--   * The floor cracks open into pits of magma that cool into basalt mounds; the last turn floods it in waves.
--
--   1  the Queen   lava globs and a rain of lava that leaves magma puddles
--   2  the Golem   he drops and slams: a wave of rock along the floor each way, stones from the roof become rubble
--   3  the Fish    a marked lunge that trenches the floor, the floor cracks into magma pits, he sheds wisps
--   4  the Champion  columns of light that vaporise cover, and a beam that sweeps the hall (rock stops it)
--   5  the Hive    all of it, in chains, with the floor rising in magma; he has to be shot to the end
--
-- Between turns he comes apart and cannot be hurt. When he falls the core goes out (src.meta.beatUndercroft): the
-- world turns to dust and ash.
local enemies = require("src.enemies")
local audio = require("src.audio")
local effects = require("src.effects")
local materials = require("src.materials")
local destruction = require("src.destruction")
local physics = require("src.physics")
local fluids = require("src.fluids")

local H = enemies.helpers
local center = H.center

local AIR = materials.AIR

local function hypot(x, y)
  return math.sqrt(x * x + y * y)
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w or 1, h or 1)
end

local function shake(k)
  require("src.camera").shake(k)
end

local function rnd(a, b)
  return a + love.math.random() * (b - a)
end

local T = {
  lines = { 0.8, 0.6, 0.4, 0.2 }, -- the health at which each turn ends
  change = 2.0, -- seconds he spends coming apart and gathering again
  awaken = 3.8, -- the core coming apart
  globDamage = 11,
  slamDamage = 18,
  fallDamage = 16,
  lungeDamage = 20,
  lightDamage = 24, -- a column of light
  beamDamage = 20,
  magmaDamage = 12,
  dying = 6.0,
  zoom = 1.9, -- how far the camera pulls out for the fight
  gap = { 0.9, 0.8, 0.7, 0.6, 0.5 }, -- between the attacks of a chain, by turn
  open = { 3.2, 3.0, 2.8, 2.6, 2.4 }, -- how long the prism stays bare after a chain
  prismHit = 13, -- a shot this close to the heart hits the prism
  prismMul = 1.0, -- bare prism: all of the blow
  swarmBare = 0.3, -- bare, but the shot went into the swarm
  swarmShut = 0.12, -- the prism covered: a sliver
  moundMax = 9, -- pieces of rubble at most
}

local NAMES = {
  { "The Queen", "He wears her face. Her spit is lava now" },
  { "The Golem", "The floor is his. So is what falls from the roof" },
  { "The Fish", "He cuts the hall open, and what is under it burns" },
  { "The Champion", "Light that nothing standing will survive" },
  { "The Hollow", "All of them. The floor itself comes for you" },
}

local N = 380 -- bits in the hive
local CORE_R = 22 -- the sphere's radius

local def = {
  name = "The Hollow King",
  boss = true, anchored = true, alwaysActive = true,
  w = 40, h = 56, hp = 2000, speed = 60,
  sight = 1400, forget = 6000,
  knockback = 0, knockMul = 0, gold = { 520, 640 }, weight = 60,
  spriteW = 80, spriteH = 90, scale = 1,
  blood = { 0.55, 0.52, 0.50 },
  desc = "What sits under the world, built out of it. In the middle of a hall too big to see across hangs a core of faceted metal; shoot it and it comes apart into a hive of bits of light and stone, with a small prism of the same metal at its heart. The hive flows like a swarm and takes the shape of the bosses above him, one at a time, and fights as each of them did: lava, slams that send a wave of rock along the floor, lunges down a marked line, columns of light, a beam that sweeps the hall. Shots into the swarm only scatter it. The prism is bare for a few seconds after each volley of attacks, and that is when he can be hurt. Everything he does to the hall stays: rubble from the roof, pits of magma that cool into stone, a floor that floods.",
}
enemies.defs.hollowking = def
enemies.order[#enemies.order + 1] = "hollowking"

local globs = {} -- lava globs: { x, y, vx, vy, life }
local waves = {} -- waves of rock along the floor: { x, dir, life }
local falls = {} -- things from the roof: { x, warn, y, vy, state, kind = "stone" | "lava" }
local marks = {} -- a lunge's marked line: { x0, y0, x1, y1, life }
local cracks = {} -- the floor about to open: { x0, x1, warn }
local pits = {} -- magma in the floor: { x0, x1, gy, depth, life, cool }
local puddles = {} -- lava on the floor: { x0, x1, y, life }
local mounds = {} -- rubble standing on the floor: { x0, x1, y0, y1 }
local pillars = {} -- columns of light: { x, warn, t, state }
local beam = nil -- { a0, a1, t, dur, state, len }
local rise = { level = 0, x0 = 0, x1 = 0, floorY = 0 } -- the flood of magma over the floor of the last turn
local shed = {} -- the wisps he has let go
local worldRef
local curHk, curTop, curFloor -- (the king's state and hall, for drawing)

local function wipe()
  globs, waves, falls, marks, cracks, puddles, pillars, beam, shed = {}, {}, {}, {}, {}, {}, {}, nil, {}
  rise.level = 0
end

-- The hive's shapes: for each turn, N offsets from its middle -----------------------------------------------------------
local forms = {}
do
  local rng = love.math.newRandomGenerator(41)
  local function disc(r)
    local a, d = rng:random() * math.pi * 2, math.sqrt(rng:random()) * r
    return math.cos(a) * d, math.sin(a) * d
  end
  local function box(x0, y0, x1, y1)
    return x0 + rng:random() * (x1 - x0), y0 + rng:random() * (y1 - y0)
  end
  local function ring(r, w)
    local a = rng:random() * math.pi * 2
    local d = r + (rng:random() - 0.5) * w
    return math.cos(a) * d, math.sin(a) * d
  end
  local function fill(builders)
    local list = {}
    local total = 0
    for _, b in ipairs(builders) do
      total = total + b[1]
    end
    for _, b in ipairs(builders) do
      local n = math.floor(N * b[1] / total + 0.5)
      for _ = 1, n do
        local x, y = b[2]()
        list[#list + 1] = { x, y }
      end
    end
    while #list < N do
      list[#list + 1] = list[#list]
    end
    while #list > N do
      list[#list] = nil
    end
    return list
  end
  -- 1: the Queen, a round body with a crown of spikes and drips under it
  forms[1] = fill({
    { 8, function() return disc(30) end },
    { 1.6, function() local i = rng:random(0, 4); local a = -math.pi / 2 + (i - 2) * 0.42; local d = 30 + rng:random() * 16; return math.cos(a) * d, math.sin(a) * d end },
    { 1.0, function() local i = rng:random(0, 2); return (i - 1) * 14, 30 + rng:random() * 14 end },
  })
  -- 2: the Golem, a blocky figure: head, torso, two arms, two legs
  forms[2] = fill({
    { 1, function() return box(-7, -50, 7, -36) end },
    { 4.5, function() return box(-17, -34, 17, 6) end },
    { 1.4, function() return box(-29, -32, -20, 12) end },
    { 1.4, function() return box(20, -32, 29, 12) end },
    { 2, function() return box(-14, 8, -3, 36) end },
    { 2, function() return box(3, 8, 14, 36) end },
  })
  -- 3: the Fish, long and low, with a tail and a fin
  forms[3] = fill({
    { 6, function() local a, d = rng:random() * math.pi * 2, math.sqrt(rng:random()); return math.cos(a) * d * 40, math.sin(a) * d * 16 end },
    { 1.4, function() local u = rng:random(); return -40 - u * 20, (rng:random() - 0.5) * 2 * (6 + u * 12) end },
    { 0.8, function() local u = rng:random(); return -6 + u * 14, -16 - u * 10 + rng:random() * 3 end },
  })
  -- 4: the Champion, a robed figure with arms out and a halo
  forms[4] = fill({
    { 1.2, function() local x, y = disc(7); return x, y - 34 end },
    { 1.7, function() local x, y = ring(17, 3); return x, y * 0.9 - 34 end },
    { 4, function() return box(-9, -26, 9, 14) end },
    { 2.2, function() return box(-36, -22, -9, -14) end },
    { 2.2, function() return box(9, -22, 36, -14) end },
    { 2.6, function() local y = 10 + rng:random() * 32; local w = 9 + (y - 10) * 0.35; return (rng:random() * 2 - 1) * w, y end },
  })
  -- 5: the hive itself, three arms of a spiral
  forms[5] = fill({
    { 1, function()
      local arm = rng:random(0, 2)
      local u = rng:random()
      local a = arm * math.pi * 2 / 3 + u * 5
      local r = 6 + u * 54
      return math.cos(a) * r + (rng:random() - 0.5) * 7, math.sin(a) * r * 0.8 + (rng:random() - 0.5) * 7
    end },
  })
end

-- Colours of each shape: four shades, the last the brightest (and the one that glows)
local PAL = {
  { { 0.30, 0.34, 0.07 }, { 0.55, 0.62, 0.12 }, { 0.78, 0.86, 0.26 }, { 0.95, 1.0, 0.55 } },
  { { 0.30, 0.24, 0.17 }, { 0.55, 0.45, 0.30 }, { 0.78, 0.64, 0.40 }, { 1.0, 0.72, 0.32 } },
  { { 0.08, 0.15, 0.30 }, { 0.17, 0.34, 0.58 }, { 0.34, 0.60, 0.88 }, { 0.72, 0.92, 1.0 } },
  { { 0.40, 0.34, 0.16 }, { 0.78, 0.68, 0.30 }, { 1.0, 0.94, 0.62 }, { 1.0, 1.0, 0.92 } },
  { { 0.30, 0.30, 0.34 }, { 0.62, 0.64, 0.70 }, { 1.0, 0.50, 0.16 }, { 0.78, 0.40, 1.0 } },
}

-- The metal: a shader for the sphere and the prism ---------------------------------------------------------------------
local shader, white
local SHADER = [[
extern number time;
extern number shape;   // 0: the sphere, 1: the prism
extern vec3 tint;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 p = uv * 2.0 - 1.0;
  vec3 n;
  if (shape < 0.5) {
    float r = length(p);
    if (r > 1.0) { discard; }
    n = vec3(p.x, -p.y, sqrt(1.0 - r * r));
    float a = time * 0.5;
    n.xz = mat2(cos(a), -sin(a), sin(a), cos(a)) * n.xz;
    // facets: the normal snapped to a coarse grid, a little of the true one let through
    n = normalize(floor(n * 2.6 + 0.5) / 2.6 + n * 0.35);
  } else {
    if (abs(p.x) + abs(p.y) > 1.0) { discard; }
    float a = time * 0.9;
    vec2 q = mat2(cos(a), -sin(a), sin(a), cos(a)) * p;
    n = normalize(vec3(sign(q.x) * 0.8, -sign(q.y) * 0.8, 0.6 + 0.4 * (1.0 - abs(p.x) - abs(p.y))));
  }
  vec3 L = normalize(vec3(-0.55, 0.65, 0.75));
  float diff = max(dot(n, L), 0.0);
  vec3 R = reflect(vec3(0.0, 0.0, -1.0), n);
  float env = 0.5 + 0.5 * sin(R.y * 7.0 + R.x * 3.5 + time * 0.6);
  float spec = pow(max(dot(R, L), 0.0), 18.0);
  float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.5);
  vec3 base = mix(vec3(0.16, 0.17, 0.21), vec3(0.66, 0.70, 0.78), env);
  vec3 col = base * (0.35 + 0.65 * diff) + vec3(spec) + rim * tint;
  col = floor(col * 6.0 + 0.5) / 6.0; // a few flat steps, to stay pixel art
  return vec4(col, 1.0);
}
]]

local function metal(shape, cx, cy, r, tint)
  if shader == nil then
    local ok, s = pcall(love.graphics.newShader, SHADER)
    shader = ok and s or false
    white = love.graphics.newImage(love.image.newImageData(1, 1, "rgba8", string.char(255, 255, 255, 255)))
  end
  if shader then
    love.graphics.setShader(shader)
    shader:send("time", love.timer.getTime())
    shader:send("shape", shape)
    shader:send("tint", tint or { 0.4, 0.5, 0.8 })
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(white, math.floor(cx - r), math.floor(cy - r), 0, r * 2, r * 2)
    love.graphics.setShader()
  else
    love.graphics.setColor(0.5, 0.52, 0.58)
    love.graphics.circle("fill", cx, cy, r)
  end
end

-- His state ------------------------------------------------------------------------------------------------------------------

-- Chains of attacks, by turn. Each is played through, with a short gap between, and then the prism is bare.
local CHAINS = {
  { { "globs" }, { "rain" }, { "globs", "rain" } },
  { { "slam" }, { "globs", "slam" }, { "rain", "slam" } },
  { { "lunge" }, { "crack", "globs" }, { "lunge", "slam" }, { "crack", "lunge" } },
  { { "pillars" }, { "beam" }, { "pillars", "globs" }, { "crack", "beam" } },
  { { "slam", "lunge", "lunge" }, { "beam", "pillars" }, { "crack", "globs", "rain" }, { "pillars", "slam", "beam" } },
}

local function ensure(e)
  if e.hk then
    return e.hk
  end
  local a = e.arena
  local cx, cy = center(e)
  local hk = {
    t = 0, ph = 1, change = 0,
    x = cx, y = cy,
    home = { a and a.cx or cx, cy },
    mode = "core", m = 0, next = 3.5, fallT = 6,
    ps = nil, -- the hive's bits
    pal = 1, palFrom = 1, palK = 1,
    zoom = 1.35,
    aT = 0,
    scatter = 0,
    queue = {}, lastChain = 0,
    exposeK = 0,
    riseClock = 0,
    summoned = {},
  }
  e.hk = hk
  e.ph = 1
  e.bossName = def.name
  return hk
end

local function phaseOf(e)
  local k = e.hp / e.maxHp
  for i, line in ipairs(T.lines) do
    if k > line then
      return i
    end
  end
  return 5
end

local function newBits(hk)
  hk.ps = {}
  for i = 1, N do
    hk.ps[i] = { x = hk.x, y = hk.y, vx = 0, vy = 0, i = i, ci = (i % 3) + 1, big = i % 9 == 0, hot = i % 7 == 0, ph = love.math.random() * 6.28, on = false, free = 0 }
  end
end

local function startDying(e, hk)
  hk.dying, hk.dyT = true, 0
  e.hp = 1
  hk.exposeK = 1
  wipe()
  local cx, cy = center(e)
  audio.playAt("dh_voice", cx, cy, 1, 0.4)
  shake(0.8)
end

-- Is the prism bare? (after a chain, and for a moment after a slam)
local function isBare(hk)
  return hk.mode == "open" or hk.mode == "recover" or hk.dying
end

def.filter = function(e, amount)
  local hk = ensure(e)
  if hk.finishing then
    return amount
  end
  local ax, ay = center(e)
  if hk.mode == "core" then
    -- the first shot wakes it; nothing is hurt yet
    e.woken = true
    audio.playAt("clank", ax, ay, 0.8, 0.7)
    return 0
  end
  if hk.dying or hk.mode == "awaken" or hk.change > 0 then
    audio.playAt("clank", ax, ay, 0.4, 1.2)
    return 0
  end
  -- where did it land? (a blast has no point: it counts as a hit on the prism when the prism is bare)
  local hx, hy = e.hitX, e.hitY
  e.hitX, e.hitY = nil, nil
  local bare = isBare(hk) and hk.exposeK > 0.45
  local onPrism = hx == nil or hypot(hx - hk.x, hy - hk.y) <= T.prismHit
  local mul
  if bare and onPrism then
    mul = T.prismMul
    audio.playAt("clank", ax, ay, 0.5, 0.6 + love.math.random() * 0.2)
    effects.ring(hk.x, hk.y, 12, PAL[hk.pal][4])
  elseif bare then
    mul = T.swarmBare
  else
    mul = T.swarmShut
    if love.math.random() < 0.3 then
      audio.playAt("clank", ax, ay, 0.25, 1.4)
    end
  end
  amount = math.max(1, math.floor(amount * mul + 0.5))
  if hk.ph == 5 and e.hp - amount <= 1 then
    startDying(e, hk)
    return 0
  end
  -- the blow that would cross into the next turn stops at its line
  local line = hk.ph < 5 and math.ceil(e.maxHp * T.lines[hk.ph]) or nil
  if line and e.hp - amount <= line then
    e.hp = line
    return 0
  end
  hk.scatter = 0.18 -- (the hive is thrown about by the blow)
  return amount
end

def.light = function(e)
  local cx, cy = center(e)
  local hk = e.hk
  local k = hk and (hk.dying and 1.5 or 1) or 1
  if not hk or hk.mode == "core" then
    return { cx, cy, 150, 0.7, 0.78, 1, 0.35 }
  end
  local c = PAL[hk.pal][3]
  return { cx, cy - 4, 130 + 60 * (hk.exposeK or 0), c[1], c[2], c[3], 0.45 * k + 0.25 * (hk.exposeK or 0) }
end

local function hurt(player, dmg, x, y, e)
  if player:hurt(math.max(1, math.floor(dmg * e.dmgMul + 0.5)), x, y, "hollowking") then
    player.lastEnemy = e
  end
end

-- The ground ---------------------------------------------------------------------------------------------------------------

-- Terrain written by hand must tell the shading, the physics outlines and the water, as a dug hole does
local function changed(w, x0, y0, x1, y1)
  w:repaintLater(x0, y0, x1, y1)
  physics.rebuildRegion(x0, y0, x1, y1)
  fluids.wake(x0, y0, x1, y1)
end

local function fillBox(w, x0, y0, x1, y1, id)
  for y = y0, y1 do
    for x = x0, x1 do
      if w:inBounds(x, y) then
        w:setRaw(x, y, id)
      end
    end
  end
  changed(w, x0, y0, x1, y1)
end

local function groundAt(w, x, a)
  return w:findGround(math.floor(x), a.floorY - 90)
end

local function playerIn(player, x0, y0, x1, y1)
  local pb = player.body
  return overlaps(x0, y0, x1 - x0 + 1, y1 - y0 + 1, pb.x, pb.y, pb.w, pb.h)
end

-- A heap of rubble where a stone lands: a low mound of basalt that can be stood on, hidden behind and dug away.
local function dropRubble(w, a, x, player)
  if not w then
    return
  end
  local cx = math.floor(x)
  local gy = groundAt(w, cx, a)
  local x0, x1 = cx - 8, cx + 8
  if gy < a.floorY - 14 then
    return
  end
  local top = gy - 8
  if playerIn(player, x0, top, x1, gy) then
    return
  end
  for dx = -8, 8 do
    local colG = w:findGround(cx + dx, gy - 20)
    local hh = 8 - math.floor(math.abs(dx) * 0.85)
    if hh > 0 and colG - hh >= top - 2 then
      for y = colG - hh, colG - 1 do
        w:setRaw(cx + dx, y, materials.BASALT)
      end
    end
  end
  changed(w, x0, top - 2, x1, gy)
  mounds[#mounds + 1] = { x0 = x0, x1 = x1, y0 = top - 2, y1 = gy - 1 }
  if #mounds > T.moundMax then
    local old = table.remove(mounds, 1)
    -- (the oldest crumbles: only basalt standing above the floor is taken)
    for y = old.y0, old.y1 do
      for x = old.x0, old.x1 do
        if w:inBounds(x, y) and w:get(x, y) == materials.BASALT and y < a.floorY - 1 then
          w:setRaw(x, y, AIR)
        end
      end
    end
    changed(w, old.x0, old.y0, old.x1, old.y1)
  end
end

-- A crack in the floor opens into a pit of magma, which in time cools into a mound of basalt
local function openPit(w, a, x0, x1)
  if not w then
    return
  end
  local cx = math.floor((x0 + x1) / 2)
  local gy = groundAt(w, cx, a)
  local depth = 9
  fillBox(w, x0, gy, x1, gy + depth - 1, AIR)
  pits[#pits + 1] = { x0 = x0, x1 = x1, gy = gy, depth = depth, life = 9 + love.math.random() * 2 }
  audio.playAt("explosion", cx, gy, 0.7, 0.5)
  shake(0.35)
  for _ = 1, 14 do
    effects.particle(rnd(x0, x1), gy, rnd(-50, 50), -60 - love.math.random() * 120, 0.9, { 1, 0.5, 0.15 }, 300, true)
  end
end

local function coolPit(w, p, player)
  if playerIn(player, p.x0, p.gy - 5, p.x1, p.gy + p.depth) then
    return false -- (not while he stands in it)
  end
  local cx = (p.x0 + p.x1) / 2
  local half = (p.x1 - p.x0) / 2
  for x = p.x0, p.x1 do
    local hh = 5 - math.floor(math.abs(x - cx) / half * 4)
    for y = p.gy - hh, p.gy + p.depth - 1 do
      if w:inBounds(x, y) then
        w:setRaw(x, y, materials.BASALT)
      end
    end
  end
  changed(w, p.x0, p.gy - 6, p.x1, p.gy + p.depth)
  for _ = 1, 10 do
    effects.particle(rnd(p.x0, p.x1), p.gy - 2, rnd(-20, 20), -20 - love.math.random() * 40, 0.8, { 0.5, 0.5, 0.52 }, -10)
  end
  return true
end

-- The attacks ---------------------------------------------------------------------------------------------------

local function throwGlobs(e, hk, px, py)
  local cx, cy = center(e)
  local n = hk.ph >= 5 and 7 or 5
  local base = math.atan2(py - cy, px - cx)
  audio.playAt("crow_spit", cx, cy, 1, 0.5)
  for i = 1, n do
    local ang = base + (i - (n + 1) / 2) * 0.22
    local sp = 150 + love.math.random() * 30
    globs[#globs + 1] = { x = cx, y = cy, vx = math.cos(ang) * sp, vy = math.sin(ang) * sp - 40, life = 4 }
  end
end

local function slam(e, hk, a)
  local cx = center(e)
  audio.playAt("explosion", cx, a.floorY, 0.9, 0.5)
  shake(0.6)
  for dir = -1, 1, 2 do
    waves[#waves + 1] = { x = cx, dir = dir, life = 3.2, hit = false, fy = a.floorY }
  end
  for _ = 1, 16 do
    effects.particle(cx + (love.math.random() - 0.5) * 30, a.floorY - 2, (love.math.random() - 0.5) * 160, -20 - love.math.random() * 90, 0.8, { 0.5, 0.42, 0.36 }, 360)
  end
  -- (and stones shaken off the roof, which land as rubble)
  for _ = 1, 3 do
    falls[#falls + 1] = { x = a.cx + (love.math.random() - 0.5) * (a.x1 - a.x0) * 0.7, warn = 1.1, y = a.top + 6, vy = 0, state = "warn", kind = "stone" }
  end
end

local function startLunge(e, hk, px, py)
  local cx, cy = center(e)
  local dx, dy = px - cx, py - cy
  local d = math.max(1, hypot(dx, dy))
  hk.lx, hk.ly = dx / d, dy / d
  marks[#marks + 1] = { x0 = cx, y0 = cy, x1 = cx + hk.lx * 800, y1 = cy + hk.ly * 800, life = 0.9 }
  hk.mode, hk.m = "lunge_wind", 0.9
  audio.playAt("sw_charge", cx, cy, 0.8, 0.7)
end

local function queueFalls(hk, a, px)
  for i = 1, hk.ph >= 5 and 5 or 4 do
    local x = px + (love.math.random() - 0.5) * 360 + (i - 3) * 50
    x = clamp(x, a.cx - (a.x1 - a.x0) * 0.42, a.cx + (a.x1 - a.x0) * 0.42)
    falls[#falls + 1] = { x = x, warn = 1.0 + i * 0.12, y = a.top + 6, vy = 0, state = "warn", kind = "stone" }
  end
  audio.playAt("clank", px, a.top, 0.6, 0.5)
end

-- Lava drops: marked columns, then the drops
local function startRain(hk, a, px)
  local n = hk.ph >= 5 and 8 or 6
  for i = 1, n do
    local x = clamp(px + (i - (n + 1) / 2) * 34 + rnd(-10, 10), a.cx - (a.x1 - a.x0) * 0.42, a.cx + (a.x1 - a.x0) * 0.42)
    falls[#falls + 1] = { x = x, warn = 1.1 + (i % 3) * 0.2, y = a.top + 6, vy = 0, state = "warn", kind = "lava" }
  end
  audio.playAt("clank", px, a.top, 0.5, 0.4)
end

-- The floor cracks in two or three places near the hunter
local function startCracks(hk, a, px, py)
  local n = hk.ph >= 5 and 3 or 2
  local w = 38
  for i = 1, n do
    local x = clamp(px + (i - (n + 1) / 2) * 90 + rnd(-30, 30), a.cx - (a.x1 - a.x0) * 0.4, a.cx + (a.x1 - a.x0) * 0.4)
    cracks[#cracks + 1] = { x0 = math.floor(x - w / 2), x1 = math.floor(x + w / 2), warn = 1.3 + i * 0.15 }
  end
  audio.playAt("sw_charge", px, a.floorY, 0.6, 0.4)
end

local function startPillars(hk, a, px)
  local half = (a.x1 - a.x0) * 0.42
  for i = -1, 1 do
    local x = clamp(px + i * rnd(55, 85), a.cx - half, a.cx + half)
    pillars[#pillars + 1] = { x = x, warn = 1.35 + (i + 1) * 0.12, t = 0, state = "warn", dug = false }
  end
  audio.playAt("sw_charge", px, a.top, 0.7, 1.2)
end

local function startBeam(hk, px, py)
  local base = math.atan2(py - hk.y, px - hk.x)
  local s = love.math.random() < 0.5 and -1 or 1
  beam = { a0 = base - 0.95 * s, a1 = base + 0.95 * s, t = 0, wind = 1.2, dur = 2.5, state = "wind", len = 900 }
  audio.playAt("sw_charge", hk.x, hk.y, 0.9, 0.9)
end

local function shedWisps(e, hk, a)
  local alive = 0
  for i = #shed, 1, -1 do
    if shed[i].dead then
      table.remove(shed, i)
    else
      alive = alive + 1
    end
  end
  if alive >= 3 then
    return
  end
  local n = hk.ph >= 5 and 4 or 3
  audio.playAt("dh_voice", hk.x, hk.y, 0.9, 1.3)
  for i = 1, n do
    local ang = (i / n) * math.pi * 2 + rnd(-0.3, 0.3)
    local x, y = clamp(hk.x + math.cos(ang) * 70, a.x0 + 30, a.x1 - 30), clamp(hk.y + math.sin(ang) * 50, a.top + 60, a.floorY - 20)
    local m = enemies.spawn("wisp", x, y, 4, e.level)
    shed[#shed + 1] = m
    for _ = 1, 8 do
      effects.particle(x, y, rnd(-70, 70), rnd(-70, 70), 0.6, PAL[hk.pal][4], 0, true)
    end
  end
end

-- Chains --------------------------------------------------------------------------------------------------------------------

local function gap(hk)
  return T.gap[hk.ph]
end

-- An attack is over: the next of the chain, or the prism laid bare
local function finish(hk)
  if #hk.queue > 0 then
    hk.mode, hk.m = "beat", gap(hk)
  else
    hk.mode, hk.m = "open", T.open[hk.ph]
    hk.openT = hk.m
    audio.playAt("clank", hk.x, hk.y, 0.8, 0.4)
    effects.ring(hk.x, hk.y, 40, PAL[hk.pal][4])
  end
end

local function startAttack(e, hk, what, a, px, py)
  if what == "globs" then
    hk.mode, hk.m = "globs_wind", 0.8
  elseif what == "slam" then
    hk.mode, hk.m = "slam_rise", 0.65
  elseif what == "lunge" then
    startLunge(e, hk, px, py)
  elseif what == "rain" then
    startRain(hk, a, px)
    hk.mode, hk.m = "rain", 2.0
  elseif what == "crack" then
    startCracks(hk, a, px, py)
    hk.mode, hk.m = "crack", 1.9
  elseif what == "pillars" then
    startPillars(hk, a, px)
    hk.mode, hk.m = "pillars", 1.9
  elseif what == "beam" then
    startBeam(hk, px, py)
    hk.mode, hk.m = "beam", 4.0
  else
    finish(hk)
  end
end

local function nextInChain(e, hk, a, px, py)
  if #hk.queue == 0 then
    -- a new chain (never the same twice running)
    local list = CHAINS[hk.ph]
    local pick
    repeat
      pick = love.math.random(#list)
    until pick ~= hk.lastChain or #list == 1
    hk.lastChain = pick
    for i, what in ipairs(list[pick]) do
      hk.queue[i] = what
    end
    if hk.force then
      hk.queue = { hk.force }
    end
    -- (the first chain of a turn with wisps sheds them first)
    if (hk.ph == 3 or hk.ph == 5) and not hk.shedDone[hk.ph] then
      hk.shedDone[hk.ph] = true
      table.insert(hk.queue, 1, "shed")
    end
  end
  local what = table.remove(hk.queue, 1)
  if what == "shed" then
    hk.mode, hk.m = "shed", 1.3
    return
  end
  startAttack(e, hk, what, a, px, py)
end

-- The hive -------------------------------------------------------------------------------------------------------------------

-- Where each bit wants to be: its place in the turn's shape, the shape stretched along a lunge, squeezed for a throw,
-- and opened round the prism when it is bare
local function updateBits(e, hk, dt)
  local t = hk.t
  local form = forms[hk.ph]
  local facing = (hk.faceX or 1)
  local spread = 1
  if hk.change > 0 then
    spread = 1 + 1.4 * math.sin(math.min(1, hk.change / T.change) * math.pi) -- coming apart and gathering again
  end
  local squeeze = 1
  if hk.mode == "globs_wind" then
    squeeze = 0.8 + 0.06 * math.sin(t * 30)
  elseif hk.mode == "slam_rise" then
    squeeze = 0.9
  end
  local stretch = (hk.mode == "lunge_dash" or hk.mode == "lunge_wind") and 1 or 0
  local lx, ly = hk.lx or 1, hk.ly or 0
  local open = hk.exposeK or 0
  local k, damp = 16, 5.2
  for i, p in ipairs(hk.ps) do
    if p.on then
      if p.free > 0 then
        p.free = p.free - dt -- (just let loose from the core: it flies free for a moment first)
        p.vx, p.vy = p.vx * math.exp(-1.2 * dt), p.vy * math.exp(-1.2 * dt)
      else
        local o = form[i]
        local ox, oy = o[1] * facing * squeeze * spread, o[2] * squeeze * spread
        if open > 0.01 then
          -- peeled away from the heart: nothing within 26 px of it while it is bare
          local d = hypot(ox, oy)
          if d < 30 then
            local s = (26 + p.ph * 1.4) / math.max(d, 1)
            ox, oy = lerp(ox, ox * s, open), lerp(oy, oy * s, open)
          end
        end
        if stretch > 0 then
          local u = ox * lx + oy * ly
          ox, oy = ox + lx * u * 0.9, oy + ly * u * 0.9
        end
        local breath = 1 + 0.05 * math.sin(t * 2.2 + p.ph)
        local tx, ty = hk.x + ox * breath, hk.y + oy * breath
        local ax = (tx - p.x) * k - p.vx * damp + math.cos(p.ph + t * 2.1) * 55
        local ay = (ty - p.y) * k - p.vy * damp + math.sin(p.ph * 1.3 + t * 2.6) * 55
        p.vx, p.vy = p.vx + ax * dt, p.vy + ay * dt
      end
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    end
  end
  if hk.scatter > 0 then
    hk.scatter = hk.scatter - dt
    for _, p in ipairs(hk.ps) do
      if p.on and love.math.random() < 0.35 then
        p.vx, p.vy = p.vx + (love.math.random() - 0.5) * 220, p.vy + (love.math.random() - 0.5) * 220
      end
    end
  end
  hk.palK = math.min(1, hk.palK + dt * 1.4)
end

-- The flood of the last turn: up over some seconds, held, then drawn back, over and over
local RISE = { rest = 12, warn = 2.2, up = 4.5, hold = 6.0, down = 4.0, top = 38 }
local function updateRise(hk, a, dt)
  rise.x0, rise.x1, rise.floorY = a.x0, a.x1, a.floorY
  local cycle = RISE.rest + RISE.warn + RISE.up + RISE.hold + RISE.down
  local c = hk.riseClock % cycle
  local level = 0
  if c < RISE.rest then
    level = 0
  elseif c < RISE.rest + RISE.warn then
    level = 2 + math.sin(hk.t * 18) -- (the floor glows, the lava seeps)
    if not hk.riseWarned then
      hk.riseWarned = true
      shake(0.4)
      audio.playAt("explosion", a.cx, a.floorY, 0.7, 0.35)
      require("src.hud").showBanner("The Floor Is Burning", "Get off the ground")
    end
  elseif c < RISE.rest + RISE.warn + RISE.up then
    hk.riseWarned = false
    level = lerp(2, RISE.top, (c - RISE.rest - RISE.warn) / RISE.up)
  elseif c < RISE.rest + RISE.warn + RISE.up + RISE.hold then
    level = RISE.top
  else
    level = lerp(RISE.top, 0, (c - RISE.rest - RISE.warn - RISE.up - RISE.hold) / RISE.down)
  end
  hk.riseClock = hk.riseClock + dt
  rise.level = level
end

-- The fight -------------------------------------------------------------------------------------------------------

local function updateKing(e, dt, world, player, px, py)
  local hk = ensure(e)
  hk.shedDone = hk.shedDone or {}
  worldRef = world
  local b = e.body
  local a = e.arena
  hk.t = hk.t + dt
  e.state, e.seesPlayer = "chase", true
  local cx, cy = center(e)
  if hk.mode == "core" then
    -- the hunter has shot it (src.scenes.catacombs wakes the fight): it comes apart
    if e.woken then
      hk.mode, hk.aT = "awaken", 0
      newBits(hk)
      hk.zoom = T.zoom
      audio.playAt("explosion", cx, cy, 1, 0.4)
      audio.playAt("dh_voice", cx, cy, 1, 0.35)
    end
    return
  end
  audio.setBoss(not (hk.dying and hk.dyT > 4.5), "hollowking")
  if hk.mode == "awaken" then
    hk.aT = hk.aT + dt
    local k = hk.aT / T.awaken
    shake(0.55 * (1 - k * 0.5))
    -- the sphere flies off bit by bit in a storm, round the prism that is left
    local want = math.floor(N * math.min(1, hk.aT / (T.awaken * 0.72)))
    for i = 1, want do
      local p = hk.ps[i]
      if not p.on then
        local ang = love.math.random() * math.pi * 2
        local r = CORE_R * (1 - math.min(1, k * 1.2)) * love.math.random()
        p.on, p.free = true, 0.5 + love.math.random() * 0.9
        p.x, p.y = hk.x + math.cos(ang) * r, hk.y + math.sin(ang) * r
        local sp = 70 + love.math.random() * 170
        p.vx, p.vy = math.cos(ang + 1.2) * sp * 0.8 + math.cos(ang) * sp * 0.6, math.sin(ang + 1.2) * sp * 0.8 + math.sin(ang) * sp * 0.6
      end
    end
    updateBits(e, hk, dt)
    if love.math.random() < dt * 40 then
      effects.particle(hk.x, hk.y, (love.math.random() - 0.5) * 220, (love.math.random() - 0.5) * 220, 0.7, { 0.75, 0.78, 0.86 }, 0, true)
    end
    if hk.aT >= T.awaken then
      hk.mode, hk.next = "patrol", 2.5
      hk.change = 0.6
      require("src.hud").showBanner(NAMES[1][1], NAMES[1][2])
    end
    b.x, b.y = math.floor(hk.x - b.w / 2), math.floor(hk.y - b.h / 2)
    return
  end
  if hk.dying then
    hk.dyT = hk.dyT + dt
    shake(0.2 + hk.dyT * 0.1)
    -- the hive loses its shape: the bits fly apart, and go out; the prism blazes and rings
    for _, p in ipairs(hk.ps) do
      p.vx, p.vy = p.vx * (1 - dt * 0.5) + (love.math.random() - 0.5) * 60, p.vy * (1 - dt * 0.5) + (love.math.random() - 0.5) * 60 - 8 * dt
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    end
    if love.math.random() < dt * 10 then
      effects.particle(hk.x, hk.y, (love.math.random() - 0.5) * 140, -love.math.random() * 120, 0.8, { 1, 0.6, 0.2 }, 100, true)
    end
    hk.ringT = (hk.ringT or 0) - dt
    if hk.ringT <= 0 then
      hk.ringT = 0.55
      effects.ring(hk.x, hk.y, 30 + hk.dyT * 18, PAL[5][3 + (math.floor(hk.dyT * 2) % 2)])
      audio.playAt("clank", hk.x, hk.y, 0.5, 0.5 + hk.dyT * 0.12)
    end
    if hk.dyT > T.dying and not hk.ended then
      hk.ended = true
      hk.finishing = true
      enemies.damage(e, e.hp + 5, 0, 0, 0, false, nil)
      hk.finishing = false
    end
    return
  end
  hk.change = math.max(0, hk.change - dt)
  -- A new shape when the health crosses a line
  local ph = phaseOf(e)
  if ph ~= hk.ph then
    hk.palFrom, hk.pal, hk.palK = hk.pal, ph, 0
    hk.ph, e.ph = ph, ph
    hk.change = T.change
    hk.mode, hk.m, hk.next = "patrol", 0, 3
    hk.queue = {}
    hk.lastChain = 0
    wipe()
    rise.level = 0
    hk.riseClock = 0
    for _, p in ipairs(hk.ps) do
      p.vx, p.vy = p.vx + (love.math.random() - 0.5) * 260, p.vy + (love.math.random() - 0.5) * 260
    end
    effects.ring(cx, cy, 90, PAL[ph][3])
    audio.playAt("dh_voice", cx, cy, 1, 0.5)
    shake(0.5)
    require("src.hud").showBanner(NAMES[ph][1], NAMES[ph][2])
  end
  local reach = a and (a.x1 - a.x0) * 0.4 or 400
  -- (it drifts over the hunter, swaying either side of him, wherever in the hall he is)
  local tx = clamp(px + math.sin(hk.t * 0.45) * 180, hk.home[1] - reach, hk.home[1] + reach)
  local ty = hk.home[2] + math.sin(hk.t * 0.9) * 22
  local floorY = a and a.floorY or cy + 100
  hk.faceX = (px >= hk.x) and 1 or -1
  if hk.change > 0 then
    tx, ty = hk.x, hk.home[2]
  elseif hk.mode == "patrol" then
    hk.next = hk.next - dt
    if hk.next <= 0 and not player.dead then
      nextInChain(e, hk, a, px, py)
    end
  end
  if hk.mode == "beat" then
    hk.m = hk.m - dt
    if hk.m <= 0 and not player.dead then
      nextInChain(e, hk, a, px, py)
    end
  elseif hk.mode == "open" then
    -- bare: it sinks to where the hunter can reach it, and hangs there
    hk.m = hk.m - dt
    ty = floorY - 95
    tx = clamp(px + math.sin(hk.t * 0.7) * 90, hk.home[1] - reach, hk.home[1] + reach)
    if hk.m <= 0 then
      hk.mode, hk.next = "patrol", 0.3
    end
  elseif hk.mode == "shed" then
    hk.m = hk.m - dt
    if hk.m <= 0 then
      shedWisps(e, hk, a)
      finish(hk)
    end
  elseif hk.mode == "globs_wind" then
    hk.m = hk.m - dt
    if hk.m <= 0 then
      throwGlobs(e, hk, px, py)
      finish(hk)
    end
  elseif hk.mode == "rain" then
    hk.m = hk.m - dt
    ty = a.top + 120
    if hk.m <= 0 then
      finish(hk)
    end
  elseif hk.mode == "crack" then
    hk.m = hk.m - dt
    if hk.m <= 0 then
      finish(hk)
    end
  elseif hk.mode == "pillars" then
    hk.m = hk.m - dt
    ty = a.top + 130
    if hk.m <= 0 then
      finish(hk)
    end
  elseif hk.mode == "beam" then
    hk.m = hk.m - dt
    ty = hk.home[2] - 30
    if not beam or hk.m <= 0 then
      beam = nil
      finish(hk)
    end
  elseif hk.mode == "slam_rise" then
    hk.m = hk.m - dt
    ty = hk.home[2] - 90
    if hk.m <= 0 then
      hk.mode, hk.m = "slam_fall", 0.9
    end
  elseif hk.mode == "slam_fall" then
    hk.m = hk.m - dt
    ty = floorY - 40
    hk.y = lerp(hk.y, ty, math.min(1, dt * 14))
    if hk.y > floorY - 46 or hk.m <= 0 then
      slam(e, hk, a)
      hk.mode, hk.m = "recover", 1.0
    end
  elseif hk.mode == "recover" then
    hk.m = hk.m - dt
    ty = floorY - 40
    if hk.m <= 0 then
      if #hk.queue > 0 then
        hk.mode, hk.m = "beat", gap(hk)
      else
        hk.mode, hk.m = "open", T.open[hk.ph] - 0.6
        hk.openT = hk.m
      end
    end
  elseif hk.mode == "lunge_wind" then
    hk.m = hk.m - dt
    tx, ty = hk.x - hk.lx * 20, hk.y - hk.ly * 20
    if hk.m <= 0 then
      hk.mode, hk.m, hk.hit = "lunge_dash", 0.7, false
      audio.playAt("gust_blast", cx, cy, 0.9, 0.6)
    end
  elseif hk.mode == "lunge_dash" then
    hk.m = hk.m - dt
    hk.x = hk.x + hk.lx * 620 * dt
    hk.y = hk.y + hk.ly * 620 * dt
    local half = (a.x1 - a.x0) * 0.4
    hk.x = clamp(hk.x, a.cx - half, a.cx + half)
    hk.y = clamp(hk.y, a.top + 60, floorY - 40)
    tx, ty = hk.x, hk.y
    if hk.ph >= 3 and world and hk.y > floorY - 62 then
      -- the dash cuts a trench where it runs low
      destruction.dig(world, hk.x, floorY - 2, 11, 30, 0, -1)
      if love.math.random() < dt * 30 then
        effects.particle(hk.x, floorY - 2, rnd(-60, 60), -40 - love.math.random() * 80, 0.6, { 0.55, 0.45, 0.36 }, 360)
      end
    end
    if hk.ph >= 5 and love.math.random() < dt * 14 then
      globs[#globs + 1] = { x = hk.x, y = hk.y, vx = (love.math.random() - 0.5) * 40, vy = 10, life = 3 }
    end
    if not hk.hit and not player.dead then
      local pb = player.body
      if overlaps(hk.x - 26, hk.y - 30, 52, 60, pb.x, pb.y, pb.w, pb.h) then
        hk.hit = true
        hurt(player, T.lungeDamage, hk.x, hk.y, e)
      end
    end
    if hk.m <= 0 then
      for i = #marks, 1, -1 do marks[i] = nil end
      finish(hk)
    end
  end
  if hk.mode ~= "lunge_dash" and hk.mode ~= "slam_fall" then
    hk.x = lerp(hk.x, tx, math.min(1, dt * 1.6))
    hk.y = lerp(hk.y, ty, math.min(1, dt * 2.2))
  end
  b.x, b.y = math.floor(hk.x - b.w / 2), math.floor(hk.y - b.h / 2)
  b.vx, b.vy = 0, 0
  -- how bare the prism is (it opens quickly and closes quickly)
  local wantOpen = isBare(hk) and 1 or 0
  hk.exposeK = lerp(hk.exposeK, wantOpen, math.min(1, dt * (wantOpen > hk.exposeK and 7 or 5)))
  updateBits(e, hk, dt)
  -- the roof, from the third turn on
  if hk.ph >= 3 and hk.change <= 0 and not isBare(hk) then
    hk.fallT = hk.fallT - dt
    if hk.fallT <= 0 and a then
      hk.fallT = (hk.ph >= 5 and 3.6 or 5.0) + love.math.random() * 1.5
      queueFalls(hk, a, px)
    end
  end
  if hk.ph == 5 and hk.change <= 0 and a then
    updateRise(hk, a, dt)
  end
  e.hkFloor = floorY
end

-- The things he has thrown ------------------------------------------------------------------------------------------

local function beamEnd(world, ox, oy, ang, maxLen)
  local dx, dy = math.cos(ang), math.sin(ang)
  local len = 0
  while len < maxLen do
    len = len + 3
    if world:isSolid(ox + dx * len, oy + dy * len) then
      break
    end
  end
  return len, dx, dy
end

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  local pb = player.body
  local king, arena, hk
  for _, e in ipairs(enemies.every()) do
    if e.kind == "hollowking" then
      king, arena, hk = e, e.arena, e.hk
    end
  end
  local kingStub = king or { dmgMul = 1 }
  curHk, curTop, curFloor = hk, arena and arena.top, arena and arena.floorY
  local floorY = arena and arena.floorY
  for i = #globs, 1, -1 do
    local g = globs[i]
    g.life = g.life - dt
    g.vy = g.vy + 330 * dt
    g.x, g.y = g.x + g.vx * dt, g.y + g.vy * dt
    local solid = world:isSolid(g.x, g.y)
    local gone = g.life <= 0 or solid
    if gone then
      for _ = 1, 5 do
        effects.particle(g.x, g.y, (love.math.random() - 0.5) * 70, -love.math.random() * 60, 0.5, { 1, 0.5, 0.15 }, 300)
      end
      if solid and king and king.hk and king.hk.ph <= 2 and #puddles < 8 and floorY and g.y > floorY - 20 then
        -- (lava that hits the floor stays there a while)
        puddles[#puddles + 1] = { x0 = g.x - 7, x1 = g.x + 7, y = g.y - 2, life = 6 }
      end
    elseif not player.dead and overlaps(g.x - 2, g.y - 2, 4, 4, pb.x, pb.y, pb.w, pb.h) then
      hurt(player, T.globDamage, g.x, g.y, kingStub)
      gone = true
    end
    if gone then
      table.remove(globs, i)
    end
  end
  for i = #waves, 1, -1 do
    local wv = waves[i]
    wv.life = wv.life - dt
    wv.x = wv.x + wv.dir * 230 * dt
    if floorY and not player.dead and not wv.hit and math.abs(wv.x - (pb.x + pb.w / 2)) < 9 and pb.y + pb.h > floorY - 20 then
      wv.hit = true
      hurt(player, T.slamDamage, wv.x, floorY, kingStub)
    end
    if floorY and love.math.random() < dt * 40 then
      effects.particle(wv.x, floorY - 3, (love.math.random() - 0.5) * 30, -30 - love.math.random() * 40, 0.4, { 0.55, 0.46, 0.38 }, 300)
    end
    local blocked = floorY and world:isSolid(wv.x + wv.dir * 5, floorY - 4)
    if blocked then
      -- rubble breaks the wave, and the wave breaks the rubble
      destruction.dig(world, wv.x + wv.dir * 6, floorY - 8, 8, 20, wv.dir, 0)
      for _ = 1, 8 do
        effects.particle(wv.x, floorY - 8, -wv.dir * rnd(20, 90), -rnd(20, 90), 0.6, { 0.5, 0.42, 0.36 }, 360)
      end
      audio.playAt("clank", wv.x, floorY, 0.5, 0.8)
    end
    if blocked or wv.life <= 0 or (arena and (wv.x < arena.x0 or wv.x > arena.x1)) then
      table.remove(waves, i)
    end
  end
  for i = #falls, 1, -1 do
    local f = falls[i]
    if f.state == "warn" then
      f.warn = f.warn - dt
      if f.warn <= 0 then
        f.state = "fall"
        audio.playAt("clank", f.x, f.y, 0.5, f.kind == "lava" and 0.9 or 0.6)
      end
    else
      f.vy = f.vy + 900 * dt
      f.y = f.y + f.vy * dt
      local hitFloor = f.y > (arena and arena.top or 0) + 50 and world:isSolid(f.x, f.y + 4)
      if not player.dead and overlaps(f.x - 5, f.y - 5, 10, 10, pb.x, pb.y, pb.w, pb.h) then
        hurt(player, f.kind == "lava" and T.globDamage + 2 or T.fallDamage, f.x, f.y, kingStub)
        hitFloor = true
      end
      if hitFloor then
        local col = f.kind == "lava" and { 1, 0.5, 0.15 } or { 0.5, 0.42, 0.36 }
        for _ = 1, 8 do
          effects.particle(f.x, f.y, (love.math.random() - 0.5) * 100, -love.math.random() * 80, 0.6, col, 400)
        end
        audio.playAt("explosion", f.x, f.y, 0.4, 1.2)
        if f.kind == "lava" then
          if #puddles < 10 then
            puddles[#puddles + 1] = { x0 = f.x - 8, x1 = f.x + 8, y = f.y - 2, life = 7 }
          end
        elseif arena then
          dropRubble(world, arena, f.x, player)
        end
        table.remove(falls, i)
      end
    end
  end
  for i = #marks, 1, -1 do
    marks[i].life = marks[i].life - dt
    if marks[i].life <= 0 then
      table.remove(marks, i)
    end
  end
  -- the floor opening
  for i = #cracks, 1, -1 do
    local c = cracks[i]
    c.warn = c.warn - dt
    if floorY and love.math.random() < dt * 30 then
      effects.particle(rnd(c.x0, c.x1), floorY - 1, rnd(-12, 12), -rnd(10, 50), 0.5, { 1, 0.5, 0.18 }, 120, true)
    end
    if c.warn <= 0 then
      openPit(world, arena, c.x0, c.x1)
      table.remove(cracks, i)
    end
  end
  for i = #pits, 1, -1 do
    local p = pits[i]
    p.life = p.life - dt
    if not player.dead and overlaps(p.x0, p.gy, p.x1 - p.x0 + 1, p.depth, pb.x, pb.y, pb.w, pb.h) then
      hurt(player, T.magmaDamage, (p.x0 + p.x1) / 2, p.gy, kingStub)
    end
    if p.life <= 0 and coolPit(world, p, player) then
      table.remove(pits, i)
    end
  end
  for i = #puddles, 1, -1 do
    local p = puddles[i]
    p.life = p.life - dt
    if not player.dead and overlaps(p.x0, p.y - 3, p.x1 - p.x0, 6, pb.x, pb.y, pb.w, pb.h) then
      hurt(player, T.magmaDamage - 3, (p.x0 + p.x1) / 2, p.y, kingStub)
    end
    if p.life <= 0 then
      table.remove(puddles, i)
    end
  end
  -- columns of light
  for i = #pillars, 1, -1 do
    local c = pillars[i]
    if c.state == "warn" then
      c.warn = c.warn - dt
      if c.warn <= 0 then
        c.state, c.t = "strike", 0.4
        audio.playAt("gust_blast", c.x, floorY or py, 0.8, 1.4)
        shake(0.3)
      end
    else
      c.t = c.t - dt
      if not c.dug and floorY then
        c.dug = true
        -- the light takes cover with it, and scorches the floor
        destruction.dig(world, c.x, floorY - 2, 9, 30, 0, -1)
        destruction.dig(world, c.x, floorY - 12, 9, 30, 0, -1)
      end
      if not player.dead and math.abs((pb.x + pb.w / 2) - c.x) < 9 then
        hurt(player, T.lightDamage, c.x, py, kingStub)
      end
      if c.t <= 0 then
        table.remove(pillars, i)
      end
    end
  end
  -- the sweep of light
  if beam and hk then
    beam.t = beam.t + dt
    local ang
    if beam.state == "wind" then
      ang = beam.a0
      if beam.t >= beam.wind then
        beam.state, beam.t = "sweep", 0
        audio.playAt("gust_blast", hk.x, hk.y, 0.9, 0.5)
        shake(0.3)
      end
    else
      ang = lerp(beam.a0, beam.a1, clamp(beam.t / beam.dur, 0, 1))
      if beam.t >= beam.dur then
        beam = nil
      end
    end
    if beam then
      beam.ang = ang
      local len, dx, dy = beamEnd(world, hk.x, hk.y, ang, 900)
      beam.len = len
      if beam.state == "sweep" and not player.dead then
        -- distance from the hunter to the beam
        local qx, qy = (pb.x + pb.w / 2) - hk.x, (pb.y + pb.h / 2) - hk.y
        local u = qx * dx + qy * dy
        if u > 0 and u < len then
          local dist = math.abs(qx * dy - qy * dx)
          if dist < 6 then
            hurt(player, T.beamDamage, hk.x + dx * u, hk.y + dy * u, kingStub)
          end
        end
        if love.math.random() < dt * 60 then
          effects.particle(hk.x + dx * len, hk.y + dy * len, rnd(-60, 60), rnd(-60, 60), 0.4, { 1, 0.95, 0.6 }, 100, true)
        end
        -- rock in the way is scorched
        if len < 899 and love.math.random() < dt * 8 then
          destruction.dig(world, hk.x + dx * (len + 2), hk.y + dy * (len + 2), 4, 6, dx, dy)
        end
      end
    end
  end
  -- the flood
  if rise.level > 3 and floorY and not player.dead then
    local top = floorY - rise.level
    if pb.y + pb.h > top and pb.x + pb.w > rise.x0 and pb.x < rise.x1 then
      hurt(player, T.magmaDamage + 2, pb.x + pb.w / 2, floorY, kingStub)
    end
  end
end

local prevDraw = enemies.afterDraw
enemies.afterDraw = function(view)
  if prevDraw then
    prevDraw(view)
  end
  local t = love.timer.getTime()
  for _, m in ipairs(marks) do
    -- the marked line, dotted
    local d = hypot(m.x1 - m.x0, m.y1 - m.y0)
    for s = 0, d, 8 do
      local k = s / d
      love.graphics.setColor(1, 0.5, 0.2, 0.5 + 0.4 * math.sin(t * 20 + s))
      rect(m.x0 + (m.x1 - m.x0) * k, m.y0 + (m.y1 - m.y0) * k, 2, 2)
    end
  end
  for _, f in ipairs(falls) do
    if f.state == "warn" then
      -- a column of dust (or of heat) where it will land
      local top, bottom = f.y, f.y + 330
      if f.kind == "lava" then
        love.graphics.setColor(1, 0.5, 0.2, 0.3 + 0.3 * math.sin(t * 24))
      else
        love.graphics.setColor(0.62, 0.58, 0.52, 0.35 + 0.3 * math.sin(t * 24))
      end
      for y = top, bottom, 10 do
        rect(f.x - 5 + math.floor(math.sin(y * 0.3 + t * 8) * 2), y, 2, 4)
      end
    elseif f.kind == "lava" then
      love.graphics.setColor(0.9, 0.35, 0.1)
      rect(f.x - 4, f.y - 6, 8, 11)
      love.graphics.setColor(1, 0.85, 0.4)
      rect(f.x - 2, f.y - 4, 4, 6)
    else
      love.graphics.setColor(0.30, 0.25, 0.22)
      rect(f.x - 5, f.y - 5, 10, 10)
      love.graphics.setColor(0.50, 0.44, 0.38)
      rect(f.x - 5, f.y - 5, 10, 3)
    end
  end
  for _, wv in ipairs(waves) do
    -- a ridge of rock running along the floor
    for k = 0, 4 do
      local h = 4 + math.floor(math.abs(math.sin(wv.x * 0.3 + k * 1.7)) * 8) - k
      if h > 0 then
        love.graphics.setColor(0.34 + k * 0.03, 0.28 + k * 0.025, 0.24)
        rect(wv.x - wv.dir * k * 3 - 2, wv.fy - h, 4, h)
      end
    end
  end
  for _, g in ipairs(globs) do
    love.graphics.setColor(0.9, 0.35, 0.1)
    rect(g.x - 2, g.y - 2, 4, 4)
    love.graphics.setColor(1, 0.8, 0.35)
    rect(g.x - 1, g.y - 1, 2, 2)
  end
end

local prevClear = enemies.clear
enemies.clear = function()
  prevClear()
  wipe()
  mounds, pits = {}, {}
end

-- Drawing -------------------------------------------------------------------------------------------------------------

local function colour(hk, ci)
  local a, b = PAL[hk.palFrom][ci], PAL[hk.pal][ci]
  local k = hk.palK
  return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
end

local function drawKing(e)
  local hk = e.hk
  local cx, cy = center(e)
  local white = e.flash > 0
  if not hk or hk.mode == "core" then
    -- the core: a faceted sphere of metal, turning slowly and shivering a little
    local t = love.timer.getTime()
    metal(0, cx, cy + math.floor(math.sin(t * 1.3) * 2), CORE_R, { 0.35, 0.5, 0.9 })
    return
  end
  if hk.mode == "awaken" then
    -- coming apart: the sphere shrinks and shakes as the storm pours out of it
    local k = hk.aT / T.awaken
    local r = CORE_R * (1 - math.min(1, k * 1.15))
    if r > 1 then
      local sx, sy = (love.math.random() - 0.5) * 4 * (1 - k), (love.math.random() - 0.5) * 4 * (1 - k)
      metal(0, hk.x + sx, hk.y + sy, r, { 1, 0.6, 0.3 })
    end
  end
  for _, p in ipairs(hk.ps or {}) do
    if p.on then
      local r, g, b = colour(hk, p.ci)
      if white then
        r, g, b = 1, 1, 1
      elseif p.hot then
        r, g, b = 0.62, 0.65, 0.74 -- (a bit of the metal, here and there)
      end
      love.graphics.setColor(r, g, b)
      local s = p.big and 3 or 2
      rect(p.x - s / 2, p.y - s / 2, s, s)
    end
  end
  -- the prism at the heart of it: larger and blazing when it is bare
  local pr = hk.mode == "awaken" and math.max(0, math.min(1, (hk.aT - 2.3) / 1.2)) or 1
  if pr > 0 then
    local c = PAL[hk.pal][4]
    local open = hk.exposeK or 0
    local tint = { lerp(c[1], 1, open), lerp(c[2], 0.95, open), lerp(c[3], 0.7, open) }
    metal(1, hk.x, hk.y, (9 + 4 * open) * pr, tint)
  end
end

-- Emissive: the glow of the hive, the prism, the magma and the light
local function drawKingGlow(e)
  local hk = e.hk
  if not hk or hk.mode == "core" or not hk.ps then
    return
  end
  local t = love.timer.getTime()
  for _, p in ipairs(hk.ps) do
    if p.on and (p.i % 5 == 0) then
      local r, g, b = colour(hk, 4)
      love.graphics.setColor(r, g, b, 0.55 + 0.45 * math.sin(t * 6 + p.ph))
      rect(p.x, p.y, 2, 2)
    end
  end
  -- the prism's own light, and the ring that says it is bare
  local c = PAL[hk.pal][4]
  local open = hk.exposeK or 0
  love.graphics.setColor(c[1], c[2], c[3], 0.8)
  rect(hk.x - 1, hk.y - 1, 2, 2)
  if open > 0.15 then
    for i = 0, 11 do
      local a = i / 12 * math.pi * 2 + t * 1.4
      local r = 17 + math.sin(t * 8 + i) * 1.5
      love.graphics.setColor(1, 0.95, 0.65, 0.35 + 0.5 * open)
      rect(hk.x + math.cos(a) * r, hk.y + math.sin(a) * r, 2, 2)
    end
  end
end

-- The hall's own light: magma, puddles, the flood, cracks, columns and the beam. Drawn whether or not he is on screen.
local function drawHazards()
  local hk = curHk
  local t = love.timer.getTime()
  -- magma in the floor, puddles and the flood
  for _, p in ipairs(pits) do
    local w = p.x1 - p.x0 + 1
    for x = 0, w - 1, 2 do
      local k = 0.55 + 0.45 * math.sin(t * 5 + x * 0.7 + p.x0)
      love.graphics.setColor(1, 0.35 + 0.35 * k, 0.1, 0.85)
      rect(p.x0 + x, p.gy + (x % 4 == 0 and 1 or 0), 2, p.depth - 1)
    end
    love.graphics.setColor(1, 0.9, 0.5, 0.8)
    for x = 0, w - 1, 6 do
      rect(p.x0 + x + math.floor(math.sin(t * 4 + x) * 1), p.gy, 2, 1)
    end
  end
  for _, p in ipairs(puddles) do
    local fade = math.min(1, p.life / 1.5)
    love.graphics.setColor(1, 0.45, 0.12, 0.85 * fade)
    rect(p.x0, p.y, p.x1 - p.x0, 3)
    love.graphics.setColor(1, 0.9, 0.5, 0.9 * fade)
    rect(p.x0 + 2 + math.floor(math.sin(t * 6 + p.x0) * 2), p.y, 4, 1)
  end
  if rise.level > 0.5 then
    local top = rise.floorY - rise.level
    local x0, x1 = rise.x0, rise.x1
    for x = math.floor(x0), x1, 3 do
      local wave = math.sin(t * 3 + x * 0.09) * 1.5 + math.sin(t * 5.3 + x * 0.21)
      love.graphics.setColor(1, 0.4 + 0.2 * math.sin(t * 2 + x * 0.05), 0.1, 0.8)
      rect(x, top + wave, 3, rise.level - wave + 1)
      love.graphics.setColor(1, 0.9, 0.5, 0.9)
      rect(x, top + wave, 3, 1)
    end
  end
  -- cracks about to open
  for _, c in ipairs(cracks) do
    local f = clamp(1 - c.warn / 1.6, 0, 1)
    love.graphics.setColor(1, 0.5, 0.15, 0.4 + 0.5 * f)
    for x = c.x0, c.x1, 2 do
      rect(x, ((curFloor or rise.floorY)) - 1, 2, 1)
    end
  end
  -- columns of light
  for _, c in ipairs(pillars) do
    if c.state == "warn" then
      local f = 1 - clamp(c.warn / 1.5, 0, 1)
      love.graphics.setColor(1, 0.95, 0.6, 0.3 + 0.6 * f)
      local top = (curTop or hk.y - 300)
      local bottom = curFloor or hk.y + 300
      for y = top, bottom, 6 do
        rect(c.x - 1 + (y % 12 < 6 and -1 or 0), y, 2, 3)
      end
    else
      local k = clamp(c.t / 0.4, 0, 1)
      local top = (curTop or hk.y - 300)
      local bottom = (curFloor or hk.y + 300) + 2
      love.graphics.setColor(1, 0.9, 0.5, 0.55 * k)
      rect(c.x - 11 * k - 2, top, 22 * k + 4, bottom - top)
      love.graphics.setColor(1, 1, 0.9, 0.95 * k)
      rect(c.x - 6 * k, top, 12 * k, bottom - top)
    end
  end
  -- the sweep of light
  if beam and beam.ang then
    local dx, dy = math.cos(beam.ang), math.sin(beam.ang)
    local len = beam.len or 900
    if beam.state == "wind" then
      local f = clamp(beam.t / beam.wind, 0, 1)
      love.graphics.setColor(1, 0.95, 0.6, 0.25 + 0.5 * f)
      for s = 8, len, 10 do
        rect(hk.x + dx * s, hk.y + dy * s, 2, 2)
      end
    else
      for s = 0, len, 2 do
        local x, y = hk.x + dx * s, hk.y + dy * s
        love.graphics.setColor(1, 0.9, 0.5, 0.6)
        rect(x - 3, y - 3, 7, 7)
        love.graphics.setColor(1, 1, 0.92, 0.95)
        rect(x - 1, y - 1, 3, 3)
      end
    end
  end
end

local prevEmissive = enemies.drawEmissive
enemies.drawEmissive = function(view)
  prevEmissive(view)
  if curHk and curHk.mode ~= "core" then
    drawHazards()
  end
end

def.onDeath = function(e)
  wipe()
  local cx, cy = center(e)
  audio.playAt("explosion", cx, cy, 1, 0.3)
  shake(1.0)
  for _ = 1, 50 do
    local a = love.math.random() * math.pi * 2
    local sp = 60 + love.math.random() * 240
    effects.particle(cx, cy, math.cos(a) * sp, math.sin(a) * sp, 1.2, { 0.5 + love.math.random() * 0.4, 0.4, 0.3 }, 300)
  end
  -- (and the wisps go out with him)
  for _, m in ipairs(shed) do
    if not m.dead then
      enemies.damage(m, 9999, 0, 0, 0, false, nil)
    end
  end
  shed = {}
  audio.setBoss(false)
  require("src.meta").beatUndercroft()
end

-- (for the headless tests: how many of each thing are in the air)
function enemies.hollowCounts()
  return #globs, #waves, #falls, #marks, #pits, #pillars, #mounds, #puddles
end

enemies.UPDATE.hollowking = updateKing
enemies.DRAW.hollowking = drawKing
enemies.GLOW.hollowking = drawKingGlow
enemies.VOICES.hollowking = { "dh_voice", 5, 10, 0.6 }

return true
