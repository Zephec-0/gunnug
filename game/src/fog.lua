-- Dense fog (the Needle): banks of puffs lying in the caves. It is drawn after the
-- lighting, fully opaque, so it hides everything behind it and every light in it.
-- Anything that moves through it shoves it about: the hunter, monsters, bullets in
-- flight, and especially explosions, which blow a hole in it. A puff that has been
-- disturbed starts to thin away, the faster the more it was stirred, so a bank
-- that has been fought through gradually clears; one left alone lies there for good.
local config = require("src.config")

local fog = {}

local puffs = {}
local image
local ACTIVE = 560 -- only puffs this near the hunter are moved

function fog.clear()
  puffs = {}
end

function fog.sample() -- (for tests: some puff)
  return puffs[math.floor(#puffs / 2) + 1]
end

function fog.count()
  return #puffs
end

-- A bank of fog about (cx, cy): w x h px, built of overlapping puffs
function fog.addBank(cx, cy, w, h, random)
  random = random or love.math.random
  local n = math.floor(w * h / 120)
  for _ = 1, n do
    local a, d = random() * math.pi * 2, math.sqrt(random())
    local tone = 0.25 + random() * 0.05
    puffs[#puffs + 1] = {
      x = cx + math.cos(a) * d * w / 2,
      y = cy + math.sin(a) * d * h / 2,
      vx = 0,
      vy = 0,
      r = 13 + random() * 11,
      a = 1, -- opacity: 1 solid
      dis = 0, -- how stirred it has been (it thins faster the more)
      tone = tone,
      seed = random() * 100,
    }
  end
end

-- A blast at (x, y): the fog flies out from it and starts to clear
function fog.explosion(x, y, radius)
  local reach = radius * 2.2 + 30
  for _, p in ipairs(puffs) do
    local dx, dy = p.x - x, p.y - y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < reach then
      local k = 1 - d / reach
      local nd = math.max(d, 1)
      p.vx = p.vx + dx / nd * 420 * k
      p.vy = p.vy + dy / nd * 420 * k
      p.dis = p.dis + 1.6 * k + 0.2
    end
  end
end

-- A steady wind over (x, y) within r: the fog is carried along it (a dust devil's gale)
function fog.push(x, y, r, vx, vy)
  for _, p in ipairs(puffs) do
    local dx, dy = p.x - x, p.y - y
    if math.abs(dx) < r and math.abs(dy) < r * 0.7 then
      local k = 1 - math.sqrt(dx * dx + dy * dy) / (r * 1.1)
      if k > 0 then
        p.vx = p.vx + vx * k * 0.06
        p.vy = p.vy + vy * k * 0.06
        p.dis = p.dis + 0.01
      end
    end
  end
end

-- Things that push: each frame, circles with a velocity and a stir rate
local function stir(p, x, y, r, vx, vy, push, rate, dt)
  local dx, dy = p.x - x, p.y - y
  local reach = r + p.r * 0.6
  local d2 = dx * dx + dy * dy
  if d2 < reach * reach then
    local d = math.max(math.sqrt(d2), 0.5)
    local k = 1 - d / reach
    p.vx = p.vx + (dx / d * push * k + vx * 0.5) * math.min(1, dt * 18)
    p.vy = p.vy + (dy / d * push * k + vy * 0.5) * math.min(1, dt * 18)
    p.dis = p.dis + rate * (0.4 + k) * dt
  end
end

function fog.update(dt, world, player, enemyList, bullets)
  if #puffs == 0 then
    return
  end
  local px, py = player:center()
  local pb = player.body
  local t = love.timer.getTime()
  local live = {}
  for i = #puffs, 1, -1 do
    local p = puffs[i]
    if p.a <= 0 then
      table.remove(puffs, i)
    elseif math.abs(p.x - px) < ACTIVE and math.abs(p.y - py) < ACTIVE then
      live[#live + 1] = p
    end
  end
  local shots = {}
  if bullets then
    bullets.each(function(b)
      shots[#shots + 1] = b
    end)
  end
  for _, p in ipairs(live) do
    -- The hunter wades through it
    stir(p, pb.x + pb.w / 2, pb.y + pb.h / 2, 9, pb.vx, pb.vy, 90, 1.4, dt)
    -- ...and so do the monsters
    for _, e in ipairs(enemyList) do
      local b = e.body
      if not e.dead and math.abs(b.x + b.w / 2 - p.x) < b.w / 2 + 40 and math.abs(b.y + b.h / 2 - p.y) < b.h / 2 + 40 then
        stir(p, b.x + b.w / 2, b.y + b.h / 2, math.max(b.w, b.h) / 2, b.vx or 0, b.vy or 0, 70, 1.0, dt)
      end
    end
    -- ...and bullets carry it along in their wake
    for _, b in ipairs(shots) do
      if math.abs(b.x - p.x) < p.r + 12 and math.abs(b.y - p.y) < p.r + 12 then
        stir(p, b.x, b.y, 8, b.dx * b.speed * 0.5, b.dy * b.speed * 0.5, 40, 3.2, dt)
      end
    end
    -- Drift: damped, with a slow turbulence
    local damp = math.exp(-1.3 * dt)
    p.vx, p.vy = p.vx * damp, p.vy * damp
    p.vx = p.vx + math.sin(t * 0.6 + p.seed) * 1.6 * dt
    p.vy = p.vy + math.cos(t * 0.5 + p.seed * 1.3) * 1.2 * dt
    local nx, ny = p.x + p.vx * dt, p.y + p.vy * dt
    if world:isSolid(nx, p.y) then
      p.vx = -p.vx * 0.3
      nx = p.x
    end
    if world:isSolid(nx, ny) then
      p.vy = -p.vy * 0.3
      ny = p.y
    end
    p.x, p.y = nx, ny
    -- Stirred fog thins away
    if p.dis > 0 then
      p.a = p.a - math.min(2.5, p.dis) * 0.22 * dt
    end
  end
end

local function build()
  local size = 48
  local data = love.image.newImageData(size, size)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local dx, dy = (x + 0.5 - size / 2) / (size / 2), (y + 0.5 - size / 2) / (size / 2)
      local d = math.sqrt(dx * dx + dy * dy)
      local a = math.max(0, math.min(1, (1 - d) * 2.2)) -- solid through the middle, a soft rim
      data:setPixel(x, y, 1, 1, 1, a)
    end
  end
  image = love.graphics.newImage(data)
end


-- Drawing: the puffs are laid, soft and overlapping, into a density map the size of
-- the view; a shader then cuts that map into hard pixels (a threshold broken up by
-- noise, in two or three flat shades), so the bank reads as pixel fog like the water
-- and the acid, not as a pile of round blobs.
local SHADER = [[
uniform vec2 origin;
uniform vec2 size;
uniform float tick;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  float d = Texel(tex, uv).r;
  if (d < 0.05) {
    return vec4(0.0);
  }
  vec2 w = floor(uv * size) + origin;
  // slow rolling swell (6 px grain) and a fine speckle, both in whole pixels
  float n = vnoise(w / 7.0 + vec2(tick * 0.35, tick * 0.12)) * 0.65 + vnoise(w / 2.5 - vec2(tick * 0.2, 0.0)) * 0.35;
  float v = d + (n - 0.5) * 0.7;
  if (v < 0.42) {
    return vec4(0.0);
  }
  vec3 col = vec3(0.20, 0.215, 0.26);        // the body
  if (v > 0.80) col = vec3(0.16, 0.17, 0.215); // the dense heart
  if (v < 0.54) col = vec3(0.31, 0.33, 0.39); // the pale ragged rim
  if (hash(w + floor(tick * 2.0)) > 0.97) col += 0.04;
  return vec4(col, 1.0);
}
]]
local shader, canvas

function fog.draw(view)
  if #puffs == 0 then
    return
  end
  if not image then
    build()
  end
  local W, H = math.ceil(view.w), math.ceil(view.h)
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, SHADER)
    shader = ok and sh or false
  end
  if not shader then
    return
  end
  if not canvas or canvas:getWidth() ~= W or canvas:getHeight() ~= H then
    canvas = love.graphics.newCanvas(W, H)
    canvas:setFilter("nearest", "nearest")
  end
  local vx, vy = math.floor(view.x), math.floor(view.y)
  local any = false
  local prev = love.graphics.getCanvas()
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  love.graphics.translate(-vx, -vy)
  love.graphics.setBlendMode("add")
  local s = image:getWidth()
  for _, p in ipairs(puffs) do
    if p.x + p.r > vx and p.x - p.r < vx + W and p.y + p.r > vy and p.y - p.r < vy + H then
      any = true
      local k = math.min(1, p.a) * 0.55
      love.graphics.setColor(1, 1, 1, k)
      local sc = p.r * 2 / s
      love.graphics.draw(image, math.floor(p.x), math.floor(p.y), 0, sc, sc, s / 2, s / 2)
    end
  end
  love.graphics.pop()
  love.graphics.setCanvas(prev)
  if any then
    love.graphics.push("all")
    love.graphics.setShader(shader)
    shader:send("origin", { vx, vy })
    shader:send("size", { W, H })
    shader:send("tick", math.floor(love.timer.getTime() * 6) / 6) -- (the swell steps, like the water's ripple)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, vx, vy)
    love.graphics.pop()
  end
end

return fog
