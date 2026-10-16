-- Visual effects: pixel particles, muzzle flashes and floating damage numbers.
local audio = require("src.audio")
local gunInfo = require("src.gunInfo")

local gore -- (src.gore, loaded on first use: it needs effects itself)

local effects = {}

local particles = {}
local flashes = {}
local popups = {}
local rings = {} -- expanding (or collapsing) shock rings
local chunks = {} -- larger bits: hats, drums, ash, wings
local puffs = {} -- soft round sprites: smoke, spores, embers' glow
local puffImage
local MAX_PUFFS = 320
local casings = {} -- spent shells lying about; each lasts 10 seconds
local MAX_CASINGS = 250
local CASING_LIFE = 10

function effects.clear()
  particles, flashes, popups, casings, rings, chunks, puffs = {}, {}, {}, {}, {}, {}, {}
end

-- emissive particles (sparks, flashes) glow: they are drawn after the lighting
-- Particles are recycled (a gunfight makes hundreds a second: each a new
-- table was garbage for the collector) and capped: past the cap new ones are
-- simply not made
local MAX_PARTICLES = 1500
local particlePool = {}
function effects.particle(x, y, vx, vy, life, color, gravity, emissive)
  local n = #particles
  if n >= MAX_PARTICLES then
    return nil
  end
  local np = #particlePool
  local p = particlePool[np]
  if p then
    particlePool[np] = nil
  else
    p = {}
  end
  p.x, p.y, p.vx, p.vy = x, y, vx, vy
  p.life, p.maxLife, p.color = life, life, color
  p.gravity, p.emissive, p.stain = gravity or 480, emissive or false, nil
  particles[n + 1] = p
  return p
end

-- A soft round puff (a radial gradient sprite) that drifts, swells and fades.
--   size: starting diameter in px; opts.grow: how much bigger it gets by the end
--   (default 1.2 = 120% more); opts.rise: upward acceleration (px/s², negative
--   rises); opts.drag: horizontal slowing per second; opts.add: glows (drawn
--   additively after the lighting); opts.alpha: starting opacity (default 0.5);
--   opts.wind: how much the wind pushes it (default 1)
function effects.puff(x, y, vx, vy, life, size, color, opts)
  opts = opts or {}
  if #puffs >= MAX_PUFFS then
    table.remove(puffs, 1)
  end
  puffs[#puffs + 1] = {
    x = x, y = y, vx = vx, vy = vy, life = life, maxLife = life, size = size,
    color = color, grow = opts.grow or 1.2, rise = opts.rise or 0, drag = opts.drag or 0.6,
    add = opts.add or false, alpha = opts.alpha or 0.5, wind = opts.wind or 1,
  }
end

-- The wind (px/s) that light things (puffs, smoke, embers) are pushed by; set by src.weather
effects.wind = 0

local function buildPuff()
  local n = 32
  local data = love.image.newImageData(n, n)
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local dx, dy = (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1
      local d = math.min(1, math.sqrt(dx * dx + dy * dy))
      -- a little noise at the edge so it reads as vapour, not a disc
      local n1 = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
      local jitter = (n1 - math.floor(n1) - 0.5) * 0.25
      local a = math.max(0, (1 - d) ^ 1.6 + jitter * (1 - d) * d * 2)
      data:setPixel(x, y, 1, 1, 1, a)
    end
  end
  puffImage = love.graphics.newImage(data)
  puffImage:setFilter("linear", "linear")
end

local function drawPuffs(additive)
  if not puffImage then
    buildPuff()
  end
  local gw = puffImage:getWidth()
  if additive then
    love.graphics.setBlendMode("add")
  end
  for _, p in ipairs(puffs) do
    if p.add == additive then
      local k = 1 - p.life / p.maxLife
      local size = p.size * (1 + p.grow * k)
      local a = p.alpha * math.min(1, p.life / (p.maxLife * 0.45)) * math.min(1, k * 8 + 0.15)
      love.graphics.setColor(p.color[1], p.color[2], p.color[3], a)
      local s = size / gw
      love.graphics.draw(puffImage, p.x, p.y, 0, s, s, gw / 2, gw / 2)
    end
  end
  if additive then
    love.graphics.setBlendMode("alpha")
  end
end

-- A drop of blood (or slime, or bone dust): falls like a particle, and where
-- it lands on rock it stains it
function effects.blood(x, y, vx, vy, color)
  local p = effects.particle(x, y, vx, vy, 0.9, color, 520)
  if p then
    p.stain = true
  end
end

-- size scales the flash, its sparks, smoke and light (1 = revolver)
-- style (the gun's model) shapes the flash: a round one with side sparks for
-- the revolver, a small star for the pistol, a wide fan for the shotgun and
-- a thin needle for the machine gun
function effects.muzzleFlash(x, y, angle, size, style)
  size = size or 1
  flashes[#flashes + 1] = { x = x, y = y, angle = angle, life = (style == "automatic" or style == "gatling") and 0.035 or 0.05, size = size, style = style }
  local dx, dy = math.cos(angle), math.sin(angle)
  for _ = 1, math.floor(7 * size + 0.5) do
    local a = angle + (love.math.random() - 0.5) * 0.9
    local s = (96 + love.math.random() * 128) * math.sqrt(size)
    effects.particle(x, y, math.cos(a) * s, math.sin(a) * s, 0.12, { 1, 0.85, 0.3 }, 0, true)
  end
  -- A puff of smoke that drifts upward
  for _ = 1, math.max(1, math.floor(2 * size + 0.5)) do
    effects.puff(x + dx * 3, y + dy * 3, dx * 26 + (love.math.random() - 0.5) * 16, dy * 26 - 10, 0.7 + love.math.random() * 0.4, 4 + 3 * size, { 0.72, 0.7, 0.68 }, { rise = -30, alpha = 0.32 })
  end
end

-- A burst of fire, sparks and smoke for an explosion of the given radius
function effects.explosion(x, y, radius)
  flashes[#flashes + 1] = { x = x, y = y, angle = 0, life = 0.1, size = radius / 6 }
  for _ = 1, math.floor(radius * 1.6) do
    local a = love.math.random() * math.pi * 2
    local s = (0.3 + love.math.random() * 0.9) * radius * 8
    effects.particle(x, y, math.cos(a) * s, math.sin(a) * s, 0.25 + love.math.random() * 0.25, { 1, 0.55 + love.math.random() * 0.35, 0.2 }, 120, true)
  end
  for _ = 1, math.floor(radius * 0.4) do
    local a = love.math.random() * math.pi * 2
    local s = 20 + love.math.random() * radius * 3
    effects.puff(x, y, math.cos(a) * s * 0.5, math.sin(a) * s * 0.5 - 20, 1.2 + love.math.random() * 0.8, 8 + radius * 0.35, { 0.26, 0.24, 0.24 }, { rise = -40, alpha = 0.55, grow = 1.6 })
  end
  effects.puff(x, y, 0, 0, 0.35, radius * 1.4, { 1, 0.7, 0.3 }, { add = true, alpha = 0.55, grow = 0.6, drag = 0 })
end

-- Sparks plus debris in the struck material's colour
function effects.impact(x, y, dx, dy, debrisColor)
  for _ = 1, 4 do
    local a = math.atan2(-dy, -dx) + (love.math.random() - 0.5) * 2
    local s = 64 + love.math.random() * 144
    effects.particle(x, y, math.cos(a) * s, math.sin(a) * s, 0.15, { 1, 0.95, 0.55 }, 0, true)
  end
  if debrisColor then
    for _ = 1, 3 do
      local a = math.atan2(-dy, -dx) + (love.math.random() - 0.5) * 1.6
      local s = 48 + love.math.random() * 80
      effects.particle(x, y, math.cos(a) * s, math.sin(a) * s, 0.6, debrisColor, 560)
    end
  end
end

-- A spent shell (2-4 pixels long) that tumbles, bounces off the terrain with a
-- little tick, settles, and vanishes after ten seconds. hull: a coloured
-- shotgun hull with a brass base instead of plain brass.
function effects.casing(x, y, vx, vy, size, color, hull)
  if #casings >= MAX_CASINGS then
    table.remove(casings, 1)
  end
  casings[#casings + 1] = {
    x = x,
    y = y,
    vx = vx,
    vy = vy,
    size = size or 2,
    color = color or { 0.82, 0.64, 0.24 },
    hull = hull,
    life = CASING_LIFE,
    spin = love.math.random() * 6,
    bounces = 0,
    landed = false,
  }
end

-- A shock ring that expands (or, with inward, collapses) from a point
function effects.ring(x, y, radius, color, inward)
  rings[#rings + 1] = { x = x, y = y, radius = radius, color = color, inward = inward, life = 0.25, maxLife = 0.25 }
end

-- A bigger bit (w x h pixels) that tumbles, bounces, lies there and fades
function effects.chunk(x, y, vx, vy, w, h, color, life)
  if #chunks >= 260 then
    table.remove(chunks, 1)
  end
  chunks[#chunks + 1] = { x = x, y = y, vx = vx, vy = vy, w = w, h = h, color = color, life = life or 3, maxLife = life or 3, landed = false, bounces = 0 }
end

function effects.popup(x, y, text, color)
  popups[#popups + 1] = {
    x = x + (love.math.random() - 0.5) * 10,
    y = y,
    text = text,
    color = color or { 1, 1, 1 },
    life = 0.8,
    maxLife = 0.8,
  }
end

-- A vertical card that floats up from (x, y) and fades: the weapon's name,
-- its grade and a few stats. Shown when a weapon is picked up or bought.
local cards = {}

function effects.weaponCard(x, y, gun)
  cards[#cards + 1] = { x = x, y = y, gun = gun, life = 3.4, maxLife = 3.4 }
end

function effects.update(dt, world)
  for i = #cards, 1, -1 do
    local c = cards[i]
    c.life = c.life - dt
    c.y = c.y - 9 * dt
    if c.life <= 0 then
      table.remove(cards, i)
    end
  end
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.life = p.life - dt
    p.vy = p.vy + p.gravity * dt
    if p.gravity < 100 then
      p.vx = p.vx + effects.wind * dt * 0.5 -- (smoke, wisps and embers lean with the wind)
    end
    local nx, ny = p.x + p.vx * dt, p.y + p.vy * dt
    if world:isSolid(math.floor(nx), math.floor(ny)) then
      p.vx, p.vy = 0, 0 -- settle on the surface
      if p.stain then
        gore = gore or require("src.gore")
        gore.stain(world, nx, ny, p.color, 0.85)
        p.life = 0
      end
    else
      p.x, p.y = nx, ny
    end
    if p.life <= 0 then
      -- (the last one takes its place: order doesn't matter, and shifting
      -- a long list down for every one that ends did)
      local n = #particles
      particles[i] = particles[n]
      particles[n] = nil
      particlePool[#particlePool + 1] = p
    end
  end
  for i = #puffs, 1, -1 do
    local p = puffs[i]
    p.life = p.life - dt
    p.vx = p.vx * math.max(0, 1 - p.drag * dt) + effects.wind * p.wind * dt * 0.6
    p.vy = p.vy + p.rise * dt
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    if p.life <= 0 then
      table.remove(puffs, i)
    end
  end
  for i = #casings, 1, -1 do
    local c = casings[i]
    c.life = c.life - dt
    if not c.landed then
      c.vy = math.min(c.vy + 560 * dt, 420)
      c.spin = c.spin + dt * 22
      local nx, ny = c.x + c.vx * dt, c.y + c.vy * dt
      if world:isSolid(math.floor(nx), math.floor(c.y)) then
        c.vx = -c.vx * 0.4
        nx = c.x
      end
      if world:isSolid(math.floor(nx), math.floor(ny)) then
        if c.vy > 45 and c.bounces < 3 then
          c.vy = -c.vy * 0.38
          c.vx = c.vx * 0.6
          c.bounces = c.bounces + 1
          if c.bounces == 1 then
            audio.play("casing", 0.8 + love.math.random() * 0.5)
          end
        else
          c.landed = true
          c.vx, c.vy = 0, 0
        end
        ny = c.y
      end
      c.x, c.y = nx, ny
    end
    if c.life <= 0 then
      table.remove(casings, i)
    end
  end
  for i = #rings, 1, -1 do
    rings[i].life = rings[i].life - dt
    if rings[i].life <= 0 then
      table.remove(rings, i)
    end
  end
  for i = #chunks, 1, -1 do
    local c = chunks[i]
    c.life = c.life - dt
    if not c.landed then
      c.vy = math.min(c.vy + 520 * dt, 400)
      local nx, ny = c.x + c.vx * dt, c.y + c.vy * dt
      if world:isSolid(math.floor(nx), math.floor(c.y)) then
        c.vx = -c.vx * 0.4
        nx = c.x
      end
      if world:isSolid(math.floor(nx), math.floor(ny)) then
        if c.vy > 50 and c.bounces < 2 then
          c.vy = -c.vy * 0.3
          c.vx = c.vx * 0.5
          c.bounces = c.bounces + 1
        else
          c.landed = true
          c.vx, c.vy = 0, 0
        end
        ny = c.y
      end
      c.x, c.y = nx, ny
    end
    if c.life <= 0 then
      table.remove(chunks, i)
    end
  end
  for i = #flashes, 1, -1 do
    flashes[i].life = flashes[i].life - dt
    if flashes[i].life <= 0 then
      table.remove(flashes, i)
    end
  end
  for i = #popups, 1, -1 do
    local p = popups[i]
    p.life = p.life - dt
    p.y = p.y - 40 * dt
    if p.life <= 0 then
      table.remove(popups, i)
    end
  end
end

local function drawChunks()
  for _, c in ipairs(chunks) do
    local alpha = math.min(1, c.life / math.min(0.6, c.maxLife))
    love.graphics.setColor(c.color[1], c.color[2], c.color[3], alpha)
    love.graphics.rectangle("fill", math.floor(c.x), math.floor(c.y) - c.h + 1, c.w, c.h)
  end
end

local function drawParticles(emissive)
  for _, p in ipairs(particles) do
    if p.emissive == emissive then
      local c = p.color
      love.graphics.setColor(c[1], c[2], c[3], math.min(1, p.life / p.maxLife * 2))
      love.graphics.rectangle("fill", math.floor(p.x), math.floor(p.y), 1, 1)
    end
  end
end

-- Lit normally (dust, debris, smoke). Low-res canvas, world space.
function effects.drawWorld()
  drawParticles(false)
  drawChunks()
  drawPuffs(false)
  for _, c in ipairs(casings) do
    local long = c.size
    local thick = c.size >= 4 and 2 or 1
    local w, h = long, thick
    if not c.landed and math.floor(c.spin) % 2 == 1 then
      w, h = thick, long -- tumbling end over end
    end
    local alpha = math.min(1, c.life / 1.2) -- fades out over the last stretch
    local x, y = math.floor(c.x), math.floor(c.y) - h + 1
    local col = c.hull or c.color
    love.graphics.setColor(col[1], col[2], col[3], alpha)
    love.graphics.rectangle("fill", x, y, w, h)
    if c.hull then
      love.graphics.setColor(c.color[1], c.color[2], c.color[3], alpha) -- brass base
      love.graphics.rectangle("fill", x, y, w > h and 1 or w, w > h and h or 1)
    end
    love.graphics.setColor(1, 1, 0.85, 0.5 * alpha) -- glint
    love.graphics.rectangle("fill", x + (w > 1 and 1 or 0), y, 1, 1)
  end
end

-- Drawn after the lighting so they glow: muzzle flashes and sparks
function effects.drawEmissive()
  drawPuffs(true)
  for _, f in ipairs(flashes) do
    local dx, dy = math.cos(f.angle), math.sin(f.angle)
    local px, py = -dy, dx
    local s = f.size
    local style = f.style
    if style == "shotgun" then
      -- A wide fan of fire with a hot core
      love.graphics.setColor(1, 0.6, 0.2)
      love.graphics.polygon("fill", f.x, f.y, f.x + dx * 15 + px * 8, f.y + dy * 15 + py * 8, f.x + dx * 18, f.y + dy * 18, f.x + dx * 15 - px * 8, f.y + dy * 15 - py * 8)
      love.graphics.setColor(1, 0.95, 0.6)
      love.graphics.polygon("fill", f.x, f.y, f.x + dx * 11 + px * 4, f.y + dy * 11 + py * 4, f.x + dx * 13, f.y + dy * 13, f.x + dx * 11 - px * 4, f.y + dy * 11 - py * 4)
    elseif style == "automatic" or style == "gatling" then
      -- A thin, fast needle of light
      love.graphics.setColor(1, 0.85, 0.4)
      love.graphics.setLineWidth(2)
      love.graphics.line(f.x, f.y, f.x + dx * 11, f.y + dy * 11)
      love.graphics.setColor(1, 1, 0.9)
      love.graphics.setLineWidth(1)
      love.graphics.line(f.x, f.y, f.x + dx * 8, f.y + dy * 8)
    elseif style == "pistol" then
      -- A small sharp star
      love.graphics.setColor(1, 0.9, 0.5)
      love.graphics.polygon("fill", f.x + dx * 8, f.y + dy * 8, f.x + px * 2, f.y + py * 2, f.x - dx, f.y - dy, f.x - px * 2, f.y - py * 2)
      love.graphics.setColor(1, 1, 0.9)
      love.graphics.circle("fill", f.x + dx * 2, f.y + dy * 2, 1.5)
    else
      -- Revolver: a round blast, with a flash of fire out of the cylinder gap
      love.graphics.setColor(1, 0.95, 0.6)
      love.graphics.circle("fill", f.x + dx * 3 * s, f.y + dy * 3 * s, 4 * s)
      love.graphics.setColor(1, 1, 0.85)
      love.graphics.circle("fill", f.x + dx * 2 * s, f.y + dy * 2 * s, 2 * s)
      if style == "revolver" then
        love.graphics.setColor(1, 0.7, 0.3)
        love.graphics.line(f.x - dx * 4 + px * 1, f.y - dy * 4 + py * 1, f.x - dx * 4 + px * 5, f.y - dy * 4 + py * 5)
        love.graphics.line(f.x - dx * 4 - px * 1, f.y - dy * 4 - py * 1, f.x - dx * 4 - px * 5, f.y - dy * 4 - py * 5)
      end
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", math.floor(f.x + dx), math.floor(f.y + dy), 1, 1)
  end
  for _, r in ipairs(rings) do
    local t = 1 - r.life / r.maxLife
    local radius = r.inward and r.radius * (1 - t) or r.radius * t
    love.graphics.setLineWidth(1)
    love.graphics.setColor(r.color[1], r.color[2], r.color[3], 0.8 * (1 - t))
    love.graphics.circle("line", r.x, r.y, radius)
  end
  drawParticles(true)
end

-- Muzzle flashes light up their surroundings
function effects.addLights(lighting)
  for _, f in ipairs(flashes) do
    lighting.add(f.x, f.y, 90 * math.sqrt(f.size), 1, 0.8, 0.45, 1.2)
  end
end

-- Drawn at full resolution, after the canvas is scaled up
-- Draws the weapon card for a gun, its bottom centre at screen (sx, sy): the
-- name, the grade letter in the grade's colour, and a few stats, in a box
-- bordered in that colour
function effects.drawWeaponCard(sx, sy, gun, font, alpha)
  alpha = alpha or 1
  local info = gunInfo.summary(gun)
  local fh = font:getHeight()
  local pad = fh * 0.45
  local w = font:getWidth(info.title)
  for _, l in ipairs(info.lines) do
    w = math.max(w, font:getWidth(l))
  end
  w = w + pad * 3 + font:getWidth(info.grade.letter) + fh * 0.4
  local h = fh * (1 + #info.lines) + pad * 2
  local x, y = math.floor(sx - w / 2), math.floor(sy - h)
  love.graphics.setFont(font)
  love.graphics.setColor(0.04, 0.03, 0.07, 0.94 * alpha)
  love.graphics.rectangle("fill", x, y, w, h, 3, 3)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(info.grade.color[1], info.grade.color[2], info.grade.color[3], alpha)
  love.graphics.rectangle("line", x, y, w, h, 3, 3)
  love.graphics.setColor(0.98, 0.99, 1, alpha)
  love.graphics.print(info.title, x + pad, y + pad)
  love.graphics.setColor(info.grade.color[1], info.grade.color[2], info.grade.color[3], alpha)
  love.graphics.print(info.grade.letter, x + w - pad - font:getWidth(info.grade.letter), y + pad)
  for n, l in ipairs(info.lines) do
    love.graphics.setColor(0.80, 0.85, 0.96, alpha)
    love.graphics.print(l, x + pad, y + pad + fh * n)
  end
end

function effects.drawScreen(toScreen, font)
  love.graphics.setFont(font)
  for _, c in ipairs(cards) do
    local sx, sy = toScreen(c.x, c.y)
    effects.drawWeaponCard(sx, sy, c.gun, font, math.min(1, c.life / 0.6, (c.maxLife - c.life) / 0.12 + 0.2))
  end
  for _, p in ipairs(popups) do
    local sx, sy = toScreen(p.x, p.y)
    local alpha = math.min(1, p.life / p.maxLife * 2)
    local w = font:getWidth(p.text)
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.print(p.text, math.floor(sx - w / 2) + 2, math.floor(sy) + 2)
    love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha)
    love.graphics.print(p.text, math.floor(sx - w / 2), math.floor(sy))
  end
end

return effects
