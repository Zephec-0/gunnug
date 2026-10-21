-- The Ether Crawler: a small ant-like bug with a swollen sac of ether on its back. Once the hunter has
-- locked the fuser they begin to turn up in the dark, out of sight, and every one of them runs from him as
-- soon as he is near. It walks the floor, the walls and the ceiling alike (it follows the surface it is on:
-- round corners, up walls, along the roof), so it cannot be cornered into a stuck spot. Killing one spills
-- a whole fusion's worth of ether (12).
local enemies = require("src.enemies")
local audio = require("src.audio")
local effects = require("src.effects")

local H = enemies.helpers
local center, lineOfSight = H.center, H.lineOfSight

local function hypot(x, y)
  return math.sqrt(x * x + y * y)
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w or 1, h or 1)
end

local D = enemies.defs
D.ethercrawler = {
  name = "Ether Crawler",
  w = 8, h = 8, hp = 16, speed = 100,
  sight = 190, forget = 700,
  knockback = 0.4, gold = { 2, 5 }, weight = 0.4,
  spriteW = 8, spriteH = 8, scale = 1,
  blood = { 0.3, 0.9, 0.8 },
  noEther = true, -- (its own ether is the 12 it spills, not the usual one)
  desc = "A little ant-like bug with a sac of ether on its back. It runs on the floor, the walls and the ceiling, and runs away from you as soon as you are near. It only turns up once a fusion has begun, and the ether it carries is a whole fusion's worth.",
}
enemies.order[#enemies.order + 1] = "ethercrawler"

D.ethercrawler.onDeath = function(e)
  local cx, cy = center(e)
  require("src.fuser").dropEther(cx, cy, 12)
  audio.playAt("ether_pop", cx, cy, 0.9, 1)
  for _ = 1, 10 do
    effects.particle(cx, cy, (love.math.random() - 0.5) * 110, (love.math.random() - 0.5) * 110, 0.5, { 0.3, 0.95, 0.85 }, 0, true)
  end
  effects.ring(cx, cy, 14, { 0.3, 0.95, 0.85 })
end

D.ethercrawler.light = function(e)
  local cx, cy = center(e)
  return { cx, cy, 24, 0.25, 0.9, 0.8, 0.22 + 0.06 * math.sin(e.phase * 0.5) }
end

enemies.VOICES.ethercrawler = { "ether_chitter", 2.5, 6, 1 }

-- Walking a surface -----------------------------------------------------------------------------------------
-- The crawler is a point p (the open pixel just outside the surface it stands on) and the surface's normal
-- n, one of four axis directions pointing out into the air. Moving along it is one pixel at a time:
--   a wall ahead      -> the wall becomes the surface (an inside corner)
--   no ground ahead   -> it goes round the edge onto the face below (an outside corner)
-- t, the way it walks, is the normal turned a quarter, times dir.

local function tangent(e)
  return -e.ny * e.dir, e.nx * e.dir
end

local function step(e, world)
  local tx, ty = tangent(e)
  local fx, fy = e.px + tx, e.py + ty
  if world:isSolid(fx, fy) then
    e.nx, e.ny = -tx, -ty
    return
  end
  if not world:isSolid(fx - e.nx, fy - e.ny) then
    e.px, e.py = fx - e.nx, fy - e.ny
    e.nx, e.ny = tx, ty
    return
  end
  e.px, e.py = fx, fy
end

-- Is there ground under the point? (it can be blown away: the crawler then falls)
local function supported(e, world)
  return world:isSolid(e.px - e.nx, e.py - e.ny)
end

local function place(e)
  local b = e.body
  -- the body's middle, a few pixels out from the surface
  local cx, cy = e.px + 0.5 + e.nx * 3, e.py + 0.5 + e.ny * 3
  b.x, b.y = math.floor(cx - b.w / 2), math.floor(cy - b.h / 2)
end

local function updateCrawler(e, dt, world, player, px, py)
  local def, b = e.def, e.body
  if not e.px then
    -- (made by hand, e.g. for a portrait or the dev panel: stands where it is)
    e.px, e.py = math.floor(b.x + b.w / 2), math.floor(b.y + b.h)
    e.nx, e.ny, e.dir = 0, -1, 1
    e.dist = 0
  end
  e.phase = e.phase + dt * 14
  local cx, cy = center(e)
  local d = hypot(px - cx, py - cy)
  if e.state == "fall" then
    e.vy = math.min((e.vy or 0) + 600 * dt, 380)
    local steps = math.max(1, math.ceil(e.vy * dt))
    for _ = 1, steps do
      if world:isSolid(e.px, e.py + 1) then
        e.nx, e.ny, e.state, e.vy = 0, -1, "crawl", 0
        break
      end
      e.py = e.py + 1
    end
    place(e)
    return
  end
  if not supported(e, world) then
    -- Look about for any surface touching it before giving up and falling
    local found
    for _, dir in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      if world:isSolid(e.px + dir[1], e.py + dir[2]) then
        e.nx, e.ny = -dir[1], -dir[2]
        found = true
        break
      end
    end
    if not found then
      e.state, e.vy = "fall", 0
      return
    end
  end
  -- Which way: away from the hunter when he is near, otherwise a slow stroll
  e.turnT = (e.turnT or 0) - dt
  local fleeing = d < def.sight
  if e.turnT <= 0 then
    if fleeing then
      e.turnT = 0.3
      local tx, ty = -e.ny, e.nx -- (the way dir = +1 goes)
      local away = (cx - px) * tx + (cy - py) * ty
      local want = away >= 0 and 1 or -1
      if want ~= e.dir and (math.abs(away) > 6 or e.stuckT and e.stuckT > 0.4) then
        e.dir = want
      end
    else
      e.turnT = 1.5 + love.math.random() * 3
      if love.math.random() < 0.4 then
        e.dir = -e.dir
      end
      e.paused = love.math.random() < 0.3
    end
  end
  if fleeing and not e.fled then
    e.fled = true
    audio.playAt("ether_chitter", cx, cy, 0.8, 1.2)
  elseif not fleeing then
    e.fled = false
  end
  local speed = fleeing and def.speed or def.speed * 0.4
  if e.paused and not fleeing then
    speed = 0
  end
  if e.stun > 0 then
    speed = 0
  end
  local before = e.dist or 0
  e.acc = (e.acc or 0) + speed * dt
  local n = 0
  while e.acc >= 1 and n < 4 do
    e.acc = e.acc - 1
    n = n + 1
    local ox, oy = e.px, e.py
    step(e, world)
    e.dist = (e.dist or 0) + ((ox ~= e.px or oy ~= e.py) and 1 or 0)
  end
  -- Cornered somewhere it cannot get along (a pinched gap): turn round
  if speed > 0 and n > 0 and e.dist == before then
    e.stuckT = (e.stuckT or 0) + dt
    if e.stuckT > 0.6 then
      e.dir = -e.dir
      e.stuckT = 0
    end
  else
    e.stuckT = 0
  end
  e.facing = e.dir
  -- (the hunter's own body or a shot that pushed it: the body is simply put back on the surface)
  b.vx, b.vy = 0, 0
  place(e)
end

-- Drawing: it is drawn in its own frame, turned to lie along whatever it is walking on -----------------------

local EC = {
  shell = { 0.46, 0.33, 0.33 }, dark = { 0.26, 0.18, 0.21 }, light = { 0.72, 0.56, 0.52 },
  sac = { 0.18, 0.62, 0.58 }, sacLight = { 0.55, 1, 0.92 }, leg = { 0.30, 0.22, 0.24 },
}

local function frame(e)
  local nx, ny = e.nx or 0, e.ny or -1
  -- (a quarter turn each: local "up" is the normal)
  return math.atan2(nx, -ny)
end

local function drawCrawler(e)
  local b = e.body
  local white = e.flash > 0
  local function color(c, a)
    if white then
      love.graphics.setColor(1, 1, 1)
    else
      love.graphics.setColor(c[1], c[2], c[3], a or 1)
    end
  end
  local cx, cy = b.x + b.w / 2, b.y + b.h / 2
  love.graphics.push()
  love.graphics.translate(math.floor(cx + 0.5), math.floor(cy + 0.5))
  love.graphics.rotate(frame(e))
  love.graphics.scale(e.dir or e.facing or 1, 1)
  -- local: x forward, y down, the feet on y = +3
  local run = math.floor(e.phase) % 2
  local fallen = e.state == "fall"
  -- legs: three a side in two alternating sets
  color(EC.leg)
  for i = 0, 2 do
    local x = -2 + i * 2
    local set = (i + run) % 2
    rect(x, 1, 1, 2 + (fallen and 0 or 1 - set))
    rect(x + (set == 0 and 1 or -1), 3 - set, 1, 1)
  end
  -- the abdomen on the back, swollen with ether, and its sac
  color(EC.shell)
  rect(-5, -1, 4, 3)
  color(EC.dark)
  rect(-5, 1, 4, 1)
  color(EC.sac)
  rect(-6, -4, 5, 4)
  rect(-5, -5, 3, 1)
  color(EC.sacLight)
  rect(-5, -4, 2, 1)
  -- thorax and head
  color(EC.shell)
  rect(-1, -1, 3, 3)
  rect(2, -2, 3, 3)
  color(EC.light)
  rect(2, -2, 3, 1)
  color(EC.dark)
  rect(4, -1, 1, 1)
  -- antennae
  color(EC.leg)
  rect(5, -3, 1, 1)
  rect(6, -4, 1, 1)
  love.graphics.pop()
end

local function drawCrawlerGlow(e)
  local b = e.body
  local cx, cy = b.x + b.w / 2, b.y + b.h / 2
  love.graphics.push()
  love.graphics.translate(math.floor(cx + 0.5), math.floor(cy + 0.5))
  love.graphics.rotate(frame(e))
  love.graphics.scale(e.dir or e.facing or 1, 1)
  local pulse = 0.65 + 0.35 * math.sin(love.timer.getTime() * 3 + e.phase * 0.1)
  love.graphics.setColor(0.3, 1, 0.9, 0.35 * pulse)
  rect(-7, -5, 7, 6)
  love.graphics.setColor(0.5, 1, 0.95, 0.85 * pulse)
  rect(-5, -4, 3, 3)
  love.graphics.setColor(0.8, 1, 1, pulse)
  rect(-4, -3, 1, 1)
  love.graphics.pop()
end

enemies.UPDATE.ethercrawler = updateCrawler
enemies.DRAW.ethercrawler = drawCrawler
enemies.GLOW.ethercrawler = drawCrawlerGlow

-- Turning up: while a fusion is under way, now and then one appears out of sight of the hunter -----------------

local MAX_ALIVE = 3
local spawnT = 6 -- seconds to the next one

local function surfaceNear(world, x, y)
  -- from an open point, the first surface met going along a random axis: { px, py, nx, ny } or nil
  local dirs = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }
  for i = #dirs, 2, -1 do
    local j = love.math.random(i)
    dirs[i], dirs[j] = dirs[j], dirs[i]
  end
  for _, d in ipairs(dirs) do
    for k = 1, 60 do
      if world:isSolid(x + d[1] * k, y + d[2] * k) then
        if k > 1 then
          return x + d[1] * (k - 1), y + d[2] * (k - 1), -d[1], -d[2]
        end
        break
      end
    end
  end
end

local function spawnOne(world, player, px, py)
  local catacombs = require("src.scenes.catacombs")
  for _ = 1, 48 do
    local a = love.math.random() * math.pi * 2
    local r = 190 + love.math.random() * 190
    local x, y = math.floor(px + math.cos(a) * r), math.floor(py + math.sin(a) * r)
    if not world:isSolid(x, y) and catacombs.levelAt(y, x) then
      local sx, sy, nx, ny = surfaceNear(world, x, y)
      if sx and not lineOfSight(world, sx, sy, px, py) then
        local e = enemies.spawn("ethercrawler", sx, sy, 1, 1)
        e.state = "crawl"
        e.px, e.py, e.nx, e.ny = sx, sy, nx, ny
        e.dir = love.math.random() < 0.5 and -1 or 1
        e.dist = 0
        e.body.x, e.body.y = sx - 4, sy - 4
        return true
      end
    end
  end
  return false
end

local prevUpdate = enemies.afterUpdate
enemies.afterUpdate = function(dt, world, player, px, py)
  if prevUpdate then
    prevUpdate(dt, world, player, px, py)
  end
  local inv = require("src.game").inventory()
  if not (inv and inv.fuse and inv.fuse.locked) or player.dead then
    spawnT = math.max(spawnT, 5) -- (the first one comes a little after the fusion starts)
    return
  end
  spawnT = spawnT - dt
  if spawnT > 0 then
    return
  end
  local alive, bossUp = 0, false
  for _, e in ipairs(enemies.every()) do
    if not e.dead then
      if e.kind == "ethercrawler" then
        alive = alive + 1
      elseif e.def.boss and e.state ~= "sleep" then
        bossUp = true
      end
    end
  end
  if alive >= MAX_ALIVE or bossUp then
    spawnT = 5
    return
  end
  if spawnOne(world, player, px, py) then
    spawnT = 14 + love.math.random() * 16
  else
    spawnT = 2
  end
end

return true
