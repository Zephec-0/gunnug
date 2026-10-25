-- The Hollow King: the last boss of the Undercroft, in the hall at the Core (docs/undercroft-design.md). The hunter
-- falls into a huge open hall. In the middle of it hangs the core, a faceted sphere of metal (drawn by a shader),
-- inert until it is shot. Shot, it comes apart: the camera pulls out and shakes while the sphere flies off in a
-- storm of particles, leaving a small prism of metal at the heart of it. The storm is the King: a hive of some
-- four hundred bits of light and stone that flows like a swarm and takes the shape of the bosses above him, one to a
-- turn, and fights as each of them did, slower and plainer so that it can be read:
--
--   1  the Queen's shape   a fan of lava globs thrown at you
--   2  the Golem's shape   he drops to the floor and slams it: a wave of rock runs out along the ground each way,
--                          and stones come down from the roof
--   3  the Fish's shape    he marks a line across the hall and lunges along it; the roof starts to give
--   4  the hive            a spiral of all of it, with globs, slams, lunges and a falling roof together
--
-- What is his own is the hall: the Undercroft is made of what he is made of, and the roof comes down (a column of
-- dust warns where, then a stone falls) from the third turn on. Between turns he comes apart and cannot be hurt.
-- When he falls the core goes out (src.meta.beatUndercroft): the world turns to dust and ash.
local enemies = require("src.enemies")
local audio = require("src.audio")
local effects = require("src.effects")

local H = enemies.helpers
local center = H.center

local function hypot(x, y)
  return math.sqrt(x * x + y * y)
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w or 1, h or 1)
end

local function shake(k)
  require("src.camera").shake(k)
end

local T = {
  lines = { 0.75, 0.5, 0.25 }, -- the health at which each turn ends
  change = 1.8, -- seconds he spends coming apart and gathering again
  awaken = 3.8, -- the core coming apart
  globDamage = 11,
  slamDamage = 18,
  fallDamage = 16,
  lungeDamage = 20,
  dying = 6.0,
  zoom = 1.9, -- how far the camera pulls out for the fight
}

local N = 380 -- bits in the hive
local CORE_R = 22 -- the sphere's radius

local def = {
  name = "The Hollow King",
  boss = true, anchored = true, alwaysActive = true,
  w = 40, h = 56, hp = 500, speed = 60,
  sight = 1400, forget = 6000,
  knockback = 0, knockMul = 0, gold = { 520, 640 }, weight = 60,
  spriteW = 80, spriteH = 90, scale = 1,
  blood = { 0.55, 0.52, 0.50 },
  desc = "What sits under the world, built out of it. In the middle of a hall too big to see across hangs a core of faceted metal; shoot it and it comes apart into a hive of bits of light and stone, with a small prism of the same metal at its heart. The hive flows like a swarm and takes the shape of the bosses above him, one at a time, and fights as each of them did: globs of lava, slams that send a wave of rock along the floor, lunges down a marked line. In the end he is all of them at once. The roof of his hall is part of him, and it comes down.",
}
enemies.defs.hollowking = def
enemies.order[#enemies.order + 1] = "hollowking"

local globs = {} -- lava globs: { x, y, vx, vy, life }
local waves = {} -- waves of rock along the floor: { x, dir, life }
local falls = {} -- the roof coming down: { x, warn, y, vy, state }
local marks = {} -- a lunge's marked line: { x0, y0, x1, y1, life }

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
  -- 4: the hive itself, three arms of a spiral
  forms[4] = fill({
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
  }
  e.hk = hk
  e.ph = 1
  e.bossName = def.name
  return hk
end

local function phaseOf(e)
  local k = e.hp / e.maxHp
  if k > T.lines[1] then
    return 1
  elseif k > T.lines[2] then
    return 2
  elseif k > T.lines[3] then
    return 3
  end
  return 4
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
  for i = #globs, 1, -1 do globs[i] = nil end
  for i = #waves, 1, -1 do waves[i] = nil end
  for i = #falls, 1, -1 do falls[i] = nil end
  for i = #marks, 1, -1 do marks[i] = nil end
  local cx, cy = center(e)
  audio.playAt("dh_voice", cx, cy, 1, 0.4)
  shake(0.8)
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
  if hk.ph == 4 and e.hp - amount <= 1 then
    startDying(e, hk)
    return 0
  end
  -- the blow that would cross into the next turn stops at its line
  local line = hk.ph < 4 and math.ceil(e.maxHp * T.lines[hk.ph]) or nil
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
  return { cx, cy - 4, 130, c[1], c[2], c[3], 0.45 * k }
end

local function hurt(player, dmg, x, y, e)
  if player:hurt(math.max(1, math.floor(dmg * e.dmgMul + 0.5)), x, y, "hollowking") then
    player.lastEnemy = e
  end
end

-- The attacks ---------------------------------------------------------------------------------------------------

local function throwGlobs(e, hk, px, py)
  local cx, cy = center(e)
  local n = hk.ph == 4 and 7 or 5
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
  -- (and stones shaken off the roof)
  for _ = 1, 3 do
    falls[#falls + 1] = { x = a.cx + (love.math.random() - 0.5) * (a.x1 - a.x0) * 0.7, warn = 1.1, y = a.top + 6, vy = 0, state = "warn" }
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
  for i = 1, hk.ph == 4 and 5 or 4 do
    local x = px + (love.math.random() - 0.5) * 360 + (i - 3) * 50
    x = math.max(a.cx - (a.x1 - a.x0) * 0.42, math.min(a.cx + (a.x1 - a.x0) * 0.42, x))
    falls[#falls + 1] = { x = x, warn = 1.0 + i * 0.12, y = a.top + 6, vy = 0, state = "warn" }
  end
  audio.playAt("clank", px, a.top, 0.6, 0.5)
end

-- The hive -------------------------------------------------------------------------------------------------------------------

-- Where each bit wants to be: its place in the turn's shape, the shape stretched along a lunge, squeezed for a throw
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
  local k, damp = 16, 5.2
  for i, p in ipairs(hk.ps) do
    if p.on then
      if p.free > 0 then
        p.free = p.free - dt -- (just let loose from the core: it flies free for a moment first)
        p.vx, p.vy = p.vx * math.exp(-1.2 * dt), p.vy * math.exp(-1.2 * dt)
      else
        local o = form[i]
        local ox, oy = o[1] * facing * squeeze * spread, o[2] * squeeze * spread
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

-- The fight -------------------------------------------------------------------------------------------------------

local function updateKing(e, dt, world, player, px, py)
  local hk = ensure(e)
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
    end
    b.x, b.y = math.floor(hk.x - b.w / 2), math.floor(hk.y - b.h / 2)
    return
  end
  if hk.dying then
    hk.dyT = hk.dyT + dt
    shake(0.2 + hk.dyT * 0.1)
    -- the hive loses its shape: the bits fly apart, and go out
    for _, p in ipairs(hk.ps) do
      p.vx, p.vy = p.vx * (1 - dt * 0.5) + (love.math.random() - 0.5) * 60, p.vy * (1 - dt * 0.5) + (love.math.random() - 0.5) * 60 - 8 * dt
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    end
    if love.math.random() < dt * 10 then
      effects.particle(hk.x, hk.y, (love.math.random() - 0.5) * 140, -love.math.random() * 120, 0.8, { 1, 0.6, 0.2 }, 100, true)
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
    for _, p in ipairs(hk.ps) do
      p.vx, p.vy = p.vx + (love.math.random() - 0.5) * 260, p.vy + (love.math.random() - 0.5) * 260
    end
    effects.ring(cx, cy, 90, PAL[ph][3])
    audio.playAt("dh_voice", cx, cy, 1, 0.5)
    shake(0.5)
  end
  local reach = a and (a.x1 - a.x0) * 0.4 or 400
  -- (it drifts over the hunter, swaying either side of him, wherever in the hall he is)
  local tx = math.max(hk.home[1] - reach, math.min(hk.home[1] + reach, px + math.sin(hk.t * 0.45) * 180))
  local ty = hk.home[2] + math.sin(hk.t * 0.9) * 22
  local floorY = a and a.floorY or cy + 100
  hk.faceX = (px >= hk.x) and 1 or -1
  if hk.change > 0 then
    tx, ty = hk.x, hk.home[2]
  elseif hk.mode == "patrol" then
    hk.next = hk.next - dt
    if hk.next <= 0 and not player.dead then
      local pick = ({ { "globs" }, { "slam", "globs" }, { "lunge", "globs" }, { "globs", "slam", "lunge" } })[hk.ph]
      local what = hk.force or pick[love.math.random(#pick)] -- (hk.force: for the tests)
      if what == "globs" then
        hk.mode, hk.m = "globs_wind", 0.8
      elseif what == "slam" then
        hk.mode, hk.m = "slam_rise", 0.6
      else
        startLunge(e, hk, px, py)
      end
    end
  end
  if hk.mode == "globs_wind" then
    hk.m = hk.m - dt
    if hk.m <= 0 then
      throwGlobs(e, hk, px, py)
      hk.mode, hk.next = "patrol", (hk.ph == 4 and 2.4 or 3.2) + love.math.random() * 1.2
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
      hk.mode, hk.next = "patrol", (hk.ph == 4 and 2.2 or 3.0) + love.math.random() * 1.2
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
    hk.x = math.max(a.cx - half, math.min(a.cx + half, hk.x))
    hk.y = math.max(a.top + 60, math.min(floorY - 40, hk.y))
    tx, ty = hk.x, hk.y
    if hk.ph == 4 and love.math.random() < dt * 14 then
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
      hk.mode, hk.next = "patrol", (hk.ph == 4 and 2.0 or 3.0) + love.math.random() * 1.2
      for i = #marks, 1, -1 do marks[i] = nil end
    end
  end
  if hk.mode ~= "lunge_dash" and hk.mode ~= "slam_fall" then
    hk.x = lerp(hk.x, tx, math.min(1, dt * 1.6))
    hk.y = lerp(hk.y, ty, math.min(1, dt * 2.2))
  end
  b.x, b.y = math.floor(hk.x - b.w / 2), math.floor(hk.y - b.h / 2)
  b.vx, b.vy = 0, 0
  updateBits(e, hk, dt)
  -- the roof, from the third turn on
  if hk.ph >= 3 and hk.change <= 0 then
    hk.fallT = hk.fallT - dt
    if hk.fallT <= 0 and a then
      hk.fallT = (hk.ph == 4 and 3.6 or 5.0) + love.math.random() * 1.5
      queueFalls(hk, a, px)
    end
  end
  e.hkFloor = floorY
end

-- The things he has thrown ------------------------------------------------------------------------------------------

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  local pb = player.body
  local king, arena
  for _, e in ipairs(enemies.every()) do
    if e.kind == "hollowking" then
      king, arena = e, e.arena
    end
  end
  for i = #globs, 1, -1 do
    local g = globs[i]
    g.life = g.life - dt
    g.vy = g.vy + 330 * dt
    g.x, g.y = g.x + g.vx * dt, g.y + g.vy * dt
    local gone = g.life <= 0 or world:isSolid(g.x, g.y)
    if gone then
      for _ = 1, 5 do
        effects.particle(g.x, g.y, (love.math.random() - 0.5) * 70, -love.math.random() * 60, 0.5, { 1, 0.5, 0.15 }, 300)
      end
    elseif not player.dead and overlaps(g.x - 2, g.y - 2, 4, 4, pb.x, pb.y, pb.w, pb.h) then
      hurt(player, T.globDamage, g.x, g.y, king or { dmgMul = 1 })
      gone = true
    end
    if gone then
      table.remove(globs, i)
    end
  end
  local floorY = arena and arena.floorY
  for i = #waves, 1, -1 do
    local wv = waves[i]
    wv.life = wv.life - dt
    wv.x = wv.x + wv.dir * 230 * dt
    if floorY and not player.dead and not wv.hit and math.abs(wv.x - (pb.x + pb.w / 2)) < 9 and pb.y + pb.h > floorY - 26 then
      wv.hit = true
      hurt(player, T.slamDamage, wv.x, floorY, king or { dmgMul = 1 })
    end
    if floorY and love.math.random() < dt * 40 then
      effects.particle(wv.x, floorY - 3, (love.math.random() - 0.5) * 30, -30 - love.math.random() * 40, 0.4, { 0.55, 0.46, 0.38 }, 300)
    end
    if wv.life <= 0 or (arena and (wv.x < arena.x0 or wv.x > arena.x1)) then
      table.remove(waves, i)
    end
  end
  for i = #falls, 1, -1 do
    local f = falls[i]
    if f.state == "warn" then
      f.warn = f.warn - dt
      if f.warn <= 0 then
        f.state = "fall"
        audio.playAt("clank", f.x, f.y, 0.5, 0.6)
      end
    else
      f.vy = f.vy + 900 * dt
      f.y = f.y + f.vy * dt
      local hitFloor = floorY and f.y >= floorY - 4
      if not player.dead and overlaps(f.x - 5, f.y - 5, 10, 10, pb.x, pb.y, pb.w, pb.h) then
        hurt(player, T.fallDamage, f.x, f.y, king or { dmgMul = 1 })
        hitFloor = true
      end
      if hitFloor then
        for _ = 1, 8 do
          effects.particle(f.x, f.y, (love.math.random() - 0.5) * 100, -love.math.random() * 80, 0.6, { 0.5, 0.42, 0.36 }, 400)
        end
        audio.playAt("explosion", f.x, f.y, 0.4, 1.2)
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
      -- a column of dust where it will land
      local top, bottom = f.y, f.y + 330
      love.graphics.setColor(0.62, 0.58, 0.52, 0.35 + 0.3 * math.sin(t * 24))
      for y = top, bottom, 10 do
        rect(f.x - 5 + math.floor(math.sin(y * 0.3 + t * 8) * 2), y, 2, 4)
      end
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
  globs, waves, falls, marks = {}, {}, {}, {}
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
  -- the prism at the heart of it
  local pr = hk.mode == "awaken" and math.max(0, math.min(1, (hk.aT - 2.3) / 1.2)) or 1
  if pr > 0 then
    local c = PAL[hk.pal][4]
    metal(1, hk.x, hk.y, 9 * pr, { c[1], c[2], c[3] })
  end
end

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
  -- the prism's own light
  local c = PAL[hk.pal][4]
  love.graphics.setColor(c[1], c[2], c[3], 0.8)
  rect(hk.x - 1, hk.y - 1, 2, 2)
end

def.onDeath = function(e)
  for i = #globs, 1, -1 do globs[i] = nil end
  for i = #waves, 1, -1 do waves[i] = nil end
  for i = #falls, 1, -1 do falls[i] = nil end
  for i = #marks, 1, -1 do marks[i] = nil end
  local cx, cy = center(e)
  audio.playAt("explosion", cx, cy, 1, 0.3)
  shake(1.0)
  for _ = 1, 50 do
    local a = love.math.random() * math.pi * 2
    local sp = 60 + love.math.random() * 240
    effects.particle(cx, cy, math.cos(a) * sp, math.sin(a) * sp, 1.2, { 0.5 + love.math.random() * 0.4, 0.4, 0.3 }, 300)
  end
  audio.setBoss(false)
  require("src.meta").beatUndercroft()
end

-- (for the headless tests: how many of each thing are in the air)
function enemies.hollowCounts()
  return #globs, #waves, #falls, #marks
end

enemies.UPDATE.hollowking = updateKing
enemies.DRAW.hollowking = drawKing
enemies.GLOW.hollowking = drawKingGlow
enemies.VOICES.hollowking = { "dh_voice", 5, 10, 0.6 }

return true
