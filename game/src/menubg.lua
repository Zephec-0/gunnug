-- The title screen's backdrop (design doc §9b): a black hole. Everything the
-- compendium knows — guns, ammo types, attachments, perks and monsters —
-- drifts in from the edges of the screen and spirals down into it, faster and
-- smaller and redder as it nears the dark, until it is swallowed in a flash on
-- the rim. Behind it a dusk-coloured nebula is wound into spiral arms around
-- the hole.
--
-- It is drawn at the game's own resolution (640x360) so it stays pixel art,
-- in three passes:
--   1. the nebula (a shader), the stars, the accretion dust and the falling
--      things, onto a scene canvas;
--   2. that canvas through the lens shader onto the game canvas: light bent
--      around the hole (an Einstein ring), colours split near the edge, the
--      event horizon, a burning photon ring and the swirling accretion disc;
--   3. src.render's usual bloom, grading and vignette on top.
local audio = require("src.audio")
local compendium = require("src.compendium")
local config = require("src.config")

local menubg = {}

local W, H = config.VIRTUAL_W, config.VIRTUAL_H
local CX, CY = math.floor(W * 0.6), math.floor(H * 0.5) -- the hole (right of centre, clear of the menu)
local HORIZON = 24 -- event horizon radius, px
local MAX_THINGS = 34
local DUST = 700
local STARS = 160

local scene -- canvas for pass 1
local nebulaShader, lensShader
local blank -- a 1x1 image, stretched for full-canvas shader passes
local things, dust, stars, flashes = {}, {}, {}, {}
local pool -- images that can fall in
local spawnTimer = 0
local clock = 0
local ready = false

local NEBULA = [[
uniform float time;
uniform vec2 center;
uniform vec2 size;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + 17.0; a *= 0.5; }
  return v;
}
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 d = uv * size - center;
  float r = length(d) / size.y;
  float a = atan(d.y, d.x);
  // Wound into arms: the closer in, the further round it has turned
  float swirl = a + 1.25 / (r + 0.12) - time * 0.07;
  vec2 q = vec2(cos(swirl), sin(swirl)) * (r * 2.6 + 0.4);
  float n = fbm(q * 1.7 + vec2(time * 0.02, 0.0));
  float arms = fbm(q * 3.4 - vec2(0.0, time * 0.035));
  vec3 col = mix(vec3(0.025, 0.018, 0.05), vec3(0.11, 0.05, 0.16), n);
  col += vec3(0.30, 0.13, 0.36) * smoothstep(0.55, 0.85, n) * 0.45;
  col += vec3(0.90, 0.45, 0.20) * smoothstep(0.58, 0.88, arms) * smoothstep(1.3, 0.15, r) * 0.42;
  // Dusk haze brightening toward the hole
  col += vec3(0.55, 0.26, 0.14) * exp(-r * 3.2) * 0.45;
  // A few dark dust lanes
  col *= 0.75 + 0.25 * smoothstep(0.25, 0.6, fbm(q * 5.0 + 3.0));
  return vec4(col, 1.0);
}
]]

local LENS = [[
uniform float time;
uniform vec2 center;   // in pixels
uniform vec2 size;
uniform float horizon; // in pixels
uniform float warp;    // 0 = flat, 1 = full lensing

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 bend(vec2 d, float r, float k) {
  // Light from behind is bent round the hole: a point at r is seen at r - k/r
  float rr = r - k * horizon * horizon / max(r, 1.0);
  return center + d / max(r, 0.001) * rr;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 p = uv * size;
  vec2 d = p - center;
  float r = length(d);
  float a = atan(d.y, d.x);
  float k = 1.15 * warp;
  // Colours split a little near the edge, as through thick glass
  float split = 0.10 * warp * smoothstep(horizon * 4.0, horizon, r);
  vec3 c;
  c.r = Texel(tex, bend(d, r, k * (1.0 + split)) / size).r;
  c.g = Texel(tex, bend(d, r, k) / size).g;
  c.b = Texel(tex, bend(d, r, k * (1.0 - split)) / size).b;

  // The accretion disc: hot gas wound tight round the hole, streaming inward
  float x = r / horizon;
  float disc = smoothstep(1.05, 1.5, x) * smoothstep(4.2, 1.8, x);
  // (noise sampled round a circle, so there's no seam where the angle wraps)
  float spin = a + time * 0.55 / max(x * 0.6, 0.3) - x * 0.75;
  vec2 ring1 = vec2(cos(spin), sin(spin));
  float streak = noise(ring1 * 2.2 + vec2(x * 3.5 - time * 0.6, 0.0)) * 0.7 + noise(ring1 * 4.5 + vec2(0.0, x * 8.0)) * 0.3;
  vec3 hot = mix(vec3(1.0, 0.42, 0.14), vec3(1.0, 0.86, 0.62), smoothstep(2.6, 1.2, x));
  c += hot * disc * pow(streak, 2.2) * 1.15 * (0.85 + 0.15 * sin(time * 0.9));

  // The photon ring: a thin burning circle just outside the horizon
  float ring = exp(-pow((x - 1.12) / 0.07, 2.0));
  vec2 ring2 = vec2(cos(a + time * 1.2), sin(a + time * 1.2));
  c += vec3(1.0, 0.78, 0.5) * ring * (0.95 + 0.25 * noise(ring2 * 5.0 + vec2(time, 0.0)));

  // The event horizon swallows everything (with a soft lip)
  c *= smoothstep(0.96, 1.12, x);
  return vec4(c, 1.0) * color;
}
]]

-- Images to throw in, from the compendium (scaled so they read at 640x360)
local function buildPool()
  pool = {}
  for _, it in ipairs(compendium.allImages()) do
    local w, h = it.image:getDimensions()
    local s
    if it.category == "enemy" then
      s = math.min(1.5, 34 / math.max(w, h))
    elseif it.category == "weapon" then
      s = math.min(2, 22 / w) -- (the drawn gun models are much bigger than item icons)
    else
      s = 2
    end
    pool[#pool + 1] = { image = it.image, scale = s, w = w, h = h, category = it.category }
  end
end

-- How far from the hole a ray at `angle` leaves the screen
local function edgeDistance(angle, margin)
  local dx, dy = math.cos(angle), math.sin(angle)
  local tx = dx > 0 and (W + margin - CX) / dx or (dx < 0 and (-margin - CX) / dx or math.huge)
  local ty = dy > 0 and (H + margin - CY) / dy or (dy < 0 and (-margin - CY) / dy or math.huge)
  return math.min(tx, ty)
end

-- Orbit: slow and wide at the edge, whipping round near the hole
local function angularSpeed(r)
  return 5.2 * (40 / math.max(r, 20)) ^ 1.9 + 0.02
end

local function inwardSpeed(r)
  return 5 + 3600 / math.max(r, 20)
end

local function spawnThing(fresh)
  if #pool == 0 then
    return
  end
  local p = pool[love.math.random(#pool)]
  local angle = love.math.random() * math.pi * 2
  local r = edgeDistance(angle, 24)
  if fresh then
    -- At start-up, scatter them along the way in
    r = HORIZON * 3 + love.math.random() * (r - HORIZON * 3)
  end
  things[#things + 1] = {
    p = p,
    angle = angle,
    r = r,
    rot = love.math.random() * math.pi * 2,
    spin = (love.math.random() - 0.5) * 1.6,
  }
end

local function newDust(d, outer)
  d.angle = love.math.random() * math.pi * 2
  local far = edgeDistance(d.angle, 10)
  d.r = outer and far or (HORIZON * 1.1 + love.math.random() ^ 1.6 * (far - HORIZON))
  local hot = love.math.random()
  if hot < 0.55 then
    d.c = { 1.0, 0.55 + love.math.random() * 0.3, 0.25, 1 }
  elseif hot < 0.85 then
    d.c = { 0.75, 0.55, 0.95, 1 }
  else
    d.c = { 0.95, 0.95, 1.0, 1 }
  end
  d.speed = 0.6 + love.math.random() * 0.8
  return d
end

function menubg.load()
  if ready then
    return
  end
  scene = love.graphics.newCanvas(W, H)
  scene:setFilter("nearest", "nearest")
  local data = love.image.newImageData(1, 1)
  data:setPixel(0, 0, 1, 1, 1, 1)
  blank = love.graphics.newImage(data)
  local ok1, a = pcall(love.graphics.newShader, NEBULA)
  local ok2, b = pcall(love.graphics.newShader, LENS)
  nebulaShader = ok1 and a or nil
  lensShader = ok2 and b or nil
  if not (ok1 and ok2) then
    print("menubg: shaders unavailable", a, b)
  end
  buildPool()
  for i = 1, DUST do
    dust[i] = newDust({}, false)
  end
  for i = 1, STARS do
    local angle = love.math.random() * math.pi * 2
    stars[i] = {
      angle = angle,
      r = HORIZON * 2 + love.math.random() * edgeDistance(angle, 0),
      tw = love.math.random() * 6,
      b = 0.35 + love.math.random() * 0.65,
    }
  end
  for _ = 1, math.floor(MAX_THINGS * 0.7) do
    spawnThing(true)
  end
  ready = true
end

function menubg.update(dt)
  if not ready then
    return
  end
  clock = clock + dt
  spawnTimer = spawnTimer - dt
  if spawnTimer <= 0 and #things < MAX_THINGS then
    spawnTimer = 0.45 + love.math.random() * 0.6
    spawnThing(false)
  end
  for i = #things, 1, -1 do
    local t = things[i]
    t.r = t.r - inwardSpeed(t.r) * dt
    t.angle = t.angle + angularSpeed(t.r) * dt
    t.rot = t.rot + (t.spin + angularSpeed(t.r) * 0.6) * dt
    if t.r <= HORIZON * 1.08 then
      table.remove(things, i)
      flashes[#flashes + 1] = { angle = t.angle, life = 0.5, max = 0.5, size = math.min(10, 3 + t.p.w * t.p.scale * 0.15) }
      if love.math.random() < 0.35 then
        audio.play("swallow", 0.7)
      end
    end
  end
  for _, d in ipairs(dust) do
    d.r = d.r - inwardSpeed(d.r) * d.speed * dt
    d.angle = d.angle + angularSpeed(d.r) * d.speed * dt
    if d.r <= HORIZON * 1.05 then
      newDust(d, true)
    end
  end
  for _, s in ipairs(stars) do
    s.angle = s.angle + 0.004 * dt
  end
  for i = #flashes, 1, -1 do
    local f = flashes[i]
    f.life = f.life - dt
    if f.life <= 0 then
      table.remove(flashes, i)
    end
  end
end

local function drawScene()
  love.graphics.setCanvas(scene)
  love.graphics.clear(0.02, 0.015, 0.04, 1)
  love.graphics.setColor(1, 1, 1)
  if nebulaShader then
    love.graphics.setShader(nebulaShader)
    nebulaShader:send("time", clock)
    nebulaShader:send("center", { CX, CY })
    nebulaShader:send("size", { W, H })
    love.graphics.draw(blank, 0, 0, 0, W, H)
    love.graphics.setShader()
  end

  -- Stars, twinkling
  for _, s in ipairs(stars) do
    local tw = 0.6 + 0.4 * math.sin(clock * 1.7 + s.tw)
    love.graphics.setColor(0.85, 0.88, 1, s.b * tw)
    love.graphics.points(math.floor(CX + math.cos(s.angle) * s.r) + 0.5, math.floor(CY + math.sin(s.angle) * s.r) + 0.5)
  end

  -- Dust streaming in: dim far out, bright and hot near the hole
  local pts = {}
  for _, d in ipairs(dust) do
    local k = math.max(0, math.min(1, 1 - (d.r - HORIZON) / 220))
    local c = d.c
    pts[#pts + 1] = {
      math.floor(CX + math.cos(d.angle) * d.r) + 0.5,
      math.floor(CY + math.sin(d.angle) * d.r) + 0.5,
      c[1], c[2], c[3], 0.12 + k * 0.75,
    }
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.points(pts)

  -- The things falling in: they shrink, redden and darken near the end, and
  -- are stretched along their orbit (the lens finishes the job)
  for _, t in ipairs(things) do
    local p = t.p
    local near = math.max(0, math.min(1, (t.r - HORIZON) / (HORIZON * 5)))
    local s = p.scale * (0.25 + 0.75 * near ^ 0.7)
    local stretch = 1 + (1 - near) * 0.9
    local x = CX + math.cos(t.angle) * t.r
    local y = CY + math.sin(t.angle) * t.r
    local heat = 1 - near
    -- A faint trail behind it
    love.graphics.setColor(1, 0.6, 0.3, 0.12 + heat * 0.25)
    for k = 1, 4 do
      local back = t.angle - k * 0.035 * (1 + heat * 2)
      local rr = t.r + k * 1.5
      love.graphics.points(math.floor(CX + math.cos(back) * rr) + 0.5, math.floor(CY + math.sin(back) * rr) + 0.5)
    end
    local fade = math.min(1, (edgeDistance(t.angle, 24) - t.r + 40) / 40) -- eases in from the edge
    love.graphics.setColor(1, 1 - heat * 0.45, 1 - heat * 0.75, math.max(0, fade))
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(t.angle + math.pi / 2)
    love.graphics.scale(stretch, 1 / stretch)
    love.graphics.rotate(t.rot - t.angle - math.pi / 2)
    love.graphics.draw(p.image, 0, 0, 0, s, s, p.w / 2, p.h / 2)
    love.graphics.pop()
  end
  love.graphics.setCanvas()
end

-- Pass 1 (call before render.beginWorld: it uses its own canvas)
function menubg.prepare()
  if not ready then
    menubg.load()
  end
  love.graphics.push("all")
  love.graphics.origin()
  drawScene()
  love.graphics.pop()
end

-- Pass 2: onto the game canvas (between render.beginWorld and endWorld)
function menubg.draw()
  love.graphics.setColor(1, 1, 1)
  if lensShader then
    love.graphics.setShader(lensShader)
    lensShader:send("time", clock)
    lensShader:send("center", { CX, CY })
    lensShader:send("size", { W, H })
    lensShader:send("horizon", HORIZON)
    lensShader:send("warp", 1)
  end
  love.graphics.draw(scene, 0, 0)
  love.graphics.setShader()
  -- Swallowed things flare on the rim
  for _, f in ipairs(flashes) do
    local k = f.life / f.max
    local x = CX + math.cos(f.angle) * HORIZON * 1.15
    local y = CY + math.sin(f.angle) * HORIZON * 1.15
    love.graphics.setColor(1, 0.85, 0.6, k)
    local r = f.size * (1.4 - k)
    love.graphics.rectangle("fill", math.floor(x - r / 2), math.floor(y), math.ceil(r), 1)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y - r / 2), 1, math.ceil(r))
    love.graphics.setColor(1, 1, 1, k)
    love.graphics.rectangle("fill", math.floor(x) - 1, math.floor(y) - 1, 2, 2)
  end
  love.graphics.setColor(1, 1, 1)
end

-- Where the hole sits on the game canvas
function menubg.center()
  return CX, CY, HORIZON
end

return menubg
