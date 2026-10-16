-- Small harmless creatures that make the dark feel inhabited: beetles that
-- scuttle over the floor and run from the hunter (and are squashed if he lands
-- on one), glowworms hanging from the ceiling that dim when he comes near,
-- moths circling the lamps, and tiny pale fish in the pools. None of them
-- matter to the fight; they react to the hunter and to light.
local audio = require("src.audio")
local effects = require("src.effects")
local fluids = require("src.fluids")
local gore = require("src.gore")
local lighting = require("src.lighting")

local critters = {}

local list = {}
local spawnTimer = 0
local MAX = 30
local r = love.math.random

-- What lives where: area -> { kind, weight }; nil is the surface
local WHO = {
  [0] = { { "beetle", 1 } },
  [1] = { { "beetle", 5 }, { "glowworm", 3 }, { "moth", 2 }, { "fish", 3 } },
  [2] = { { "glowworm", 5 }, { "moth", 3 }, { "beetle", 2 }, { "fish", 4 } },
  [3] = { { "beetle", 8 }, { "moth", 2 } },
  [4] = { { "beetle", 6 }, { "moth", 1 } },
  [5] = { { "glowworm", 3 }, { "fish", 6 }, { "moth", 1 } },
  [6] = { { "beetle", 6 }, { "moth", 3 }, { "glowworm", 1 } },
  [7] = { { "beetle", 4 }, { "moth", 2 } },
  [8] = { { "fish", 8 }, { "glowworm", 3 } },
  [9] = { { "fish", 8 }, { "glowworm", 2 } },
  [10] = { { "beetle", 5 }, { "moth", 3 }, { "glowworm", 2 } },
  [11] = { { "moth", 6 } },
}

function critters.clear()
  list = {}
end

local function pick(area)
  local who = WHO[area or 0] or WHO[0]
  local total = 0
  for _, w in ipairs(who) do
    total = total + w[2]
  end
  local roll = r() * total
  for _, w in ipairs(who) do
    roll = roll - w[2]
    if roll <= 0 then
      return w[1]
    end
  end
  return who[1][1]
end

local function count(kind)
  local n = 0
  for _, c in ipairs(list) do
    if c.kind == kind then
      n = n + 1
    end
  end
  return n
end

local function spawn(kind, view, world, area)
  local x = view.x - 70 + r() * (view.w + 140)
  local y = view.y - 40 + r() * (view.h + 80)
  if world:isSolid(math.floor(x), math.floor(y)) then
    return
  end
  if kind == "beetle" then
    local ground = world:findGround(math.floor(x), math.floor(y))
    if ground - y < 140 and not world:isSolid(math.floor(x), ground - 1) and not world:isSolid(math.floor(x), ground - 5) then
      local shade = 0.1 + r() * 0.12
      local ember = area == 4 and r() < 0.6
      list[#list + 1] = {
        kind = "beetle", x = x, y = ground - 1, dir = r() < 0.5 and -1 or 1, t = r() * 2, go = false, fleeing = false,
        col = ember and { 0.12, 0.08, 0.08 } or (area == nil and { 0.28, 0.2, 0.12 } or { shade + 0.05, shade, shade + 0.03 }), ember = ember,
      }
    end
  elseif kind == "glowworm" then
    local cy = math.floor(y)
    local n = 0
    while not world:isSolid(math.floor(x), cy) and n < 130 do
      cy = cy - 1
      n = n + 1
    end
    if n < 130 and not world:isSolid(math.floor(x), cy + 6) then
      list[#list + 1] = { kind = "glowworm", x = x, y = cy + 1, len = 3 + math.floor(r() * 6), seed = r() * 10, glow = 1, hue = r() < 0.5 and 0 or 1 }
    end
  elseif kind == "moth" then
    local lamps = lighting.lamps(view.x, view.y, 3)
    local l = lamps[1 + math.floor(r() * #lamps)]
    if l then
      list[#list + 1] = { kind = "moth", cx = view.x + l.x * view.w, cy = view.y + l.y * view.h, a = r() * 6.28, rad = 7 + r() * 16, spd = 1.5 + r() * 2, flap = 0, x = x, y = y, seed = r() * 10 }
    end
  elseif kind == "fish" then
    local fx, fy = fluids.probe("water", view.x + view.w / 2, view.y + view.h / 2, 260)
    if fx and fluids.waterAt(fx, fy - 4) and fluids.waterAt(fx, fy + 4) and count("fish") < 12 then
      list[#list + 1] = { kind = "fish", x = fx, y = fy, dx = r() < 0.5 and -1 or 1, dy = 0, t = 1, speed = 8 + r() * 8, tail = 0 }
    end
  end
end

local function squash(c, world)
  c.dead = true
  gore.stain(world, c.x, c.y + 1, c.ember and { 0.9, 0.35, 0.1 } or { 0.28, 0.32, 0.12 }, 0.9)
  for _ = 1, 4 do
    effects.particle(c.x, c.y - 1, (r() - 0.5) * 50, -20 - r() * 30, 0.4, { c.col[1] + 0.15, c.col[2] + 0.15, c.col[3] + 0.05 }, 400)
  end
  audio.playAt("hit", c.x, c.y, 0.25, 2.2)
end

local function updateBeetle(c, dt, world, px, py, player)
  local dist = math.sqrt((c.x - px) ^ 2 + (c.y - py) ^ 2)
  local speed
  if dist < 46 and not player.dead then
    if not c.fleeing then
      c.fleeing = true
      if r() < 0.3 then
        audio.playAt("skitter", c.x, c.y, 0.7, 1.1)
      end
    end
    c.dir = c.x >= px and 1 or -1
    speed = 48
  else
    c.fleeing = false
    c.t = c.t - dt
    if c.t <= 0 then
      c.go = not c.go
      c.t = c.go and 0.4 + r() * 1.2 or 0.6 + r() * 2.5
      if r() < 0.3 then
        c.dir = -c.dir
      end
    end
    speed = c.go and 14 or 0
  end
  if speed > 0 then
    local nx = c.x + c.dir * speed * dt
    local ix, iy = math.floor(nx), math.floor(c.y)
    if world:isSolid(ix, iy) then
      -- a step up, or a wall
      if not world:isSolid(ix, iy - 2) then
        c.y = c.y - 2
        c.x = nx
      else
        c.dir = -c.dir
      end
    elseif world:isSolid(ix, iy + 1) then
      c.x = nx
    elseif world:isSolid(ix, iy + 2) or world:isSolid(ix, iy + 3) then
      c.x, c.y = nx, c.y + 2
    else
      c.dir = -c.dir -- the edge of a drop
    end
    c.leg = (c.leg or 0) + dt * (c.fleeing and 30 or 14)
  end
  -- Landed on by the hunter
  local b = player.body
  if not player.dead and player.body.vy > 40 and c.x > b.x - 1 and c.x < b.x + b.w + 1 and c.y >= b.y + b.h - 4 and c.y <= b.y + b.h + 3 then
    squash(c, world)
  end
end

local function updateFish(c, dt, px, py, player)
  c.t = c.t - dt
  local dist = math.sqrt((c.x - px) ^ 2 + (c.y - py) ^ 2)
  local speed = c.speed
  if dist < 50 and not player.dead then
    c.dx = c.x >= px and 1 or -1
    c.dy = (c.y >= py and 0.4 or -0.4)
    speed = 46
  elseif c.t <= 0 then
    c.t = 1 + r() * 2.5
    c.dx = r() < 0.5 and -1 or 1
    c.dy = (r() - 0.5) * 0.6
  end
  local nx, ny = c.x + c.dx * speed * dt, c.y + c.dy * speed * dt
  if fluids.waterAt(nx, ny) and fluids.waterAt(nx, ny - 2) and fluids.waterAt(nx + c.dx * 3, ny) then
    c.x, c.y = nx, ny
  else
    c.dx, c.dy = -c.dx, 0
    c.t = 0.5 + r()
  end
  c.tail = c.tail + dt * (speed > 20 and 28 or 12)
end

function critters.update(dt, world, player, area, underground, view)
  if underground == nil then
    underground = 1
  end
  local cx, cy = view.x + view.w / 2, view.y + view.h / 2
  local px, py = player:center()
  spawnTimer = spawnTimer - dt
  if spawnTimer <= 0 and #list < MAX then
    spawnTimer = 0.35
    spawn(pick(area), view, world, area)
  end
  for i = #list, 1, -1 do
    local c = list[i]
    local cx0, cy0 = c.x or c.cx, c.y or c.cy
    if math.abs(cx0 - cx) > 560 or math.abs(cy0 - cy) > 400 or c.dead then
      table.remove(list, i)
    elseif c.kind == "beetle" then
      updateBeetle(c, dt, world, px, py, player)
    elseif c.kind == "fish" then
      updateFish(c, dt, px, py, player)
    elseif c.kind == "glowworm" then
      local dist = math.sqrt((c.x - px) ^ 2 + (c.y + c.len - py) ^ 2)
      local want = dist < 42 and 0.1 or 1
      c.glow = c.glow + (want - c.glow) * math.min(1, dt * (want < c.glow and 6 or 0.8))
    elseif c.kind == "moth" then
      c.a = c.a + c.spd * dt
      local tx = c.cx + math.cos(c.a) * c.rad + math.sin(c.a * 2.7 + c.seed) * 3
      local ty = c.cy + math.sin(c.a * 1.3) * c.rad * 0.7 + math.cos(c.a * 3.1) * 2
      c.x = c.x + (tx - c.x) * math.min(1, dt * 6)
      c.y = c.y + (ty - c.y) * math.min(1, dt * 6)
      c.flap = c.flap + dt * 40
    end
  end
end

-- In the lit world, behind the glow
function critters.draw(view)
  for _, c in ipairs(list) do
    if c.kind == "beetle" then
      local x, y = math.floor(c.x), math.floor(c.y)
      love.graphics.setColor(c.col[1], c.col[2], c.col[3])
      love.graphics.rectangle("fill", x - 1, y - 1, 3, 2)
      love.graphics.setColor(c.col[1] + 0.12, c.col[2] + 0.12, c.col[3] + 0.1)
      love.graphics.rectangle("fill", x, y - 2, 1, 1)
      -- legs
      local l = math.floor((c.leg or 0)) % 2
      love.graphics.setColor(c.col[1] * 0.7, c.col[2] * 0.7, c.col[3] * 0.7)
      love.graphics.rectangle("fill", x - 1 + l, y, 1, 1)
      love.graphics.rectangle("fill", x + 1 - l, y, 1, 1)
    elseif c.kind == "fish" then
      local x, y = math.floor(c.x), math.floor(c.y)
      local f = c.dx
      love.graphics.setColor(0.7, 0.82, 0.88, 0.85)
      love.graphics.rectangle("fill", x - (f > 0 and 1 or 0), y, 3, 1)
      love.graphics.setColor(0.45, 0.6, 0.7, 0.8)
      love.graphics.rectangle("fill", x - f * 2 - (f > 0 and 0 or -1), y - (math.floor(c.tail) % 2), 1, 2)
    end
  end
end

-- Glows, after the lighting
function critters.drawEmissive(view)
  for _, c in ipairs(list) do
    if c.kind == "glowworm" and c.glow > 0.03 then
      local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 1.5 + c.seed)
      local g = c.glow * pulse
      local col = c.hue == 0 and { 0.4, 1, 0.8 } or { 0.55, 1, 0.45 }
      love.graphics.setColor(col[1] * 0.5, col[2] * 0.5, col[3] * 0.5, 0.7)
      love.graphics.rectangle("fill", math.floor(c.x), math.floor(c.y), 1, c.len)
      love.graphics.setColor(col[1], col[2], col[3], g)
      love.graphics.rectangle("fill", math.floor(c.x) - 1, math.floor(c.y + c.len), 3, 2)
      love.graphics.setBlendMode("add")
      love.graphics.setColor(col[1], col[2], col[3], 0.22 * g)
      love.graphics.circle("fill", c.x + 0.5, c.y + c.len + 1, 6)
      love.graphics.setBlendMode("alpha")
    elseif c.kind == "moth" then
      local up = math.floor(c.flap) % 2 == 0
      love.graphics.setColor(0.95, 0.9, 0.78, 0.9)
      love.graphics.rectangle("fill", math.floor(c.x) - 1, math.floor(c.y) + (up and -1 or 0), 1, 1)
      love.graphics.rectangle("fill", math.floor(c.x) + 1, math.floor(c.y) + (up and -1 or 0), 1, 1)
      love.graphics.setColor(0.6, 0.5, 0.4, 0.9)
      love.graphics.rectangle("fill", math.floor(c.x), math.floor(c.y), 1, 1)
    elseif c.kind == "beetle" and c.ember then
      love.graphics.setColor(1, 0.45, 0.1, 0.8)
      love.graphics.rectangle("fill", math.floor(c.x), math.floor(c.y) - 2, 1, 1)
    end
  end
end

-- Glowworms light the air a little
function critters.addLights(lighting_, view)
  local n = 0
  for _, c in ipairs(list) do
    if c.kind == "glowworm" and c.glow > 0.2 and n < 6 and c.x > view.x - 20 and c.x < view.x + view.w + 20 then
      n = n + 1
      local col = c.hue == 0 and { 0.4, 1, 0.8 } or { 0.55, 1, 0.45 }
      lighting_.add(c.x, c.y + c.len, 22, col[1], col[2], col[3], 0.35 * c.glow)
    end
  end
end

return critters
