-- Visual effects: pixel particles, muzzle flashes and floating damage numbers.
local audio = require("src.audio")

local effects = {}

local particles = {}
local flashes = {}
local popups = {}
local casings = {} -- spent shells lying about; each lasts 10 seconds
local MAX_CASINGS = 250
local CASING_LIFE = 10

function effects.clear()
  particles, flashes, popups, casings = {}, {}, {}, {}
end

-- emissive particles (sparks, flashes) glow: they are drawn after the lighting
function effects.particle(x, y, vx, vy, life, color, gravity, emissive)
  particles[#particles + 1] = {
    x = x,
    y = y,
    vx = vx,
    vy = vy,
    life = life,
    maxLife = life,
    color = color,
    gravity = gravity or 480,
    emissive = emissive or false,
  }
end

-- size scales the flash, its sparks, smoke and light (1 = revolver)
function effects.muzzleFlash(x, y, angle, size)
  size = size or 1
  flashes[#flashes + 1] = { x = x, y = y, angle = angle, life = 0.05, size = size }
  local dx, dy = math.cos(angle), math.sin(angle)
  for _ = 1, math.floor(7 * size + 0.5) do
    local a = angle + (love.math.random() - 0.5) * 0.9
    local s = (96 + love.math.random() * 128) * math.sqrt(size)
    effects.particle(x, y, math.cos(a) * s, math.sin(a) * s, 0.12, { 1, 0.85, 0.3 }, 0, true)
  end
  -- A puff of smoke that drifts upward
  for _ = 1, math.max(1, math.floor(3 * size + 0.5)) do
    effects.particle(
      x + dx * 3,
      y + dy * 3,
      dx * 24 + (love.math.random() - 0.5) * 16,
      dy * 24 - 16,
      0.5,
      { 0.75, 0.72, 0.7 },
      -32
    )
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
  for _ = 1, math.floor(radius * 0.5) do
    local a = love.math.random() * math.pi * 2
    local s = 20 + love.math.random() * radius * 3
    effects.particle(x, y, math.cos(a) * s, math.sin(a) * s - 20, 0.7, { 0.3, 0.27, 0.27 }, -30)
  end
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

function effects.update(dt, world)
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.life = p.life - dt
    p.vy = p.vy + p.gravity * dt
    local nx, ny = p.x + p.vx * dt, p.y + p.vy * dt
    if world:isSolid(math.floor(nx), math.floor(ny)) then
      p.vx, p.vy = 0, 0 -- settle on the surface
    else
      p.x, p.y = nx, ny
    end
    if p.life <= 0 then
      table.remove(particles, i)
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
  for _, f in ipairs(flashes) do
    local dx, dy = math.cos(f.angle), math.sin(f.angle)
    local s = f.size
    love.graphics.setColor(1, 0.95, 0.6)
    love.graphics.circle("fill", f.x + dx * 3 * s, f.y + dy * 3 * s, 4 * s)
    love.graphics.setColor(1, 1, 0.85)
    love.graphics.circle("fill", f.x + dx * 2 * s, f.y + dy * 2 * s, 2 * s)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", math.floor(f.x + dx), math.floor(f.y + dy), 1, 1)
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
function effects.drawScreen(toScreen, font)
  love.graphics.setFont(font)
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
