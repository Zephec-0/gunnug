-- Stormglass: the environment's shock. Spurs of pale blue glass hang from the roof of the old workings and the fen, where a
-- storm once struck the rock and the lightning set in it. Every few seconds one gathers a charge (a rising crackle and a
-- blue glow in its core, about a second of warning), then arcs down from its tip: a thread of lightning 34 px long and a
-- shock to anyone in it (Shocked, and harder on the Soaked). If there is water under it, the whole pool takes the current
-- (fluids.zap). A bullet into the glass (src.bullets calls livewire.shot) shatters it: it arcs once and is dead. (The file
-- and the area setting keep their first name, "wires".) Joins the secrets (src.secrets); src.cavegen finds the spots (info.wires), src.events
-- calls setup as an area spawns.
local effects = require("src.effects")
local fluids = require("src.fluids")
local status = require("src.status")

local livewire = {}

local wires = {}
local world
local clock = 0
local LEN = 14 -- how far the shard hangs
local ARC_MIN, ARC_MAX = 34, 320 -- the arc reaches down to the floor under the shard: at least this far, at most that

function livewire.clear()
  wires = {}
  world = nil
end

function livewire.setup(w, info)
  world = w
  for i, s in ipairs(info.wires or {}) do
    wires[#wires + 1] = { x = s[1], y = s[2], state = "idle", t = 1.5 + ((i * 37 + s[1]) % 40) / 10, dead = false }
  end
end

local function tip(w)
  return w.x, w.y + LEN
end

-- How far the arc reaches: down to the first solid ground under the tip (worked out as it charges, since the ground
-- may have been dug away or built on)
local function reach(w)
  if not world then
    return ARC_MIN
  end
  local tx, ty = tip(w)
  local d = ARC_MIN
  while d < ARC_MAX and not world:isSolid(tx, ty + d) do
    d = d + 2
  end
  return d
end

local lastPlayer

-- The arc: sound, the pool under it and the hunter in it
local function fire(w, player)
  local tx, ty = tip(w)
  pcall(function()
    require("src.audio").playAt("wisp_crackle", tx, ty, 1, 1.3)
  end)
  local arc = w.arc or ARC_MIN
  for dy = 4, arc + 20, 4 do
    if fluids.waterAt(tx, ty + dy) then
      fluids.zap(tx, ty + dy, 8)
      break
    end
  end
  if player and not player.dead then
    local pcx, pcy = player:center()
    if math.abs(pcx - tx) < 12 and pcy > ty - 4 and pcy < ty + arc then
      player:hurt(math.floor(8 * status.shockMult(player) + 0.5), tx, ty, "shock")
      status.apply(player, "shocked", 0.8)
    end
  end
end

function livewire.update(dt, player)
  clock = clock + dt
  for _, w in ipairs(wires) do
    if w.flash then
      w.flash = w.flash - dt
      if w.flash <= 0 then
        w.flash = nil
      end
    end
  end
  lastPlayer = player
  local pcx, pcy = player:center()
  for _, w in ipairs(wires) do
    if not w.dead and math.abs(pcx - w.x) < 420 and math.abs(pcy - w.y) < 460 then
      w.t = w.t - dt
      local tx, ty = tip(w)
      if w.state == "idle" and w.t <= 0 then
        w.state, w.t = "charge", 1.1
        w.arc = reach(w)
      elseif w.state == "charge" then
        if love.math.random() < dt * 30 then
          effects.particle(tx + (love.math.random() - 0.5) * 6, ty + love.math.random() * 8, (love.math.random() - 0.5) * 30, 10 + love.math.random() * 20, 0.25, { 0.7, 0.9, 1 }, 0, true)
        end
        if w.t <= 0 then
          w.state, w.t = "arc", 0.35
          w.arc = reach(w)
          fire(w, player)
        end
      elseif w.state == "arc" and w.t <= 0 then
        if w.cut then
          w.dead = true
        else
          w.state, w.t = "idle", 3.5 + love.math.random() * 2.5
        end
      end
    end
  end
end

-- A bullet at (x, y) into the glass shatters it: it arcs once, to whoever is under it, and is dead for good
function livewire.shot(x, y)
  for _, w in ipairs(wires) do
    if not w.dead and not w.cut and math.abs(x - w.x) < 6 and y > w.y and y < w.y + LEN + 4 then
      w.cut = true
      -- It goes at once, in a burst of electricity: a flash, sparks flung every way and the glass in pieces. Whoever
      -- is under it still takes the one shock (and the pool under it the current), but there is no arc to wait for.
      w.arc = w.arc or reach(w)
      if w.state ~= "arc" and lastPlayer then
        fire(w, lastPlayer)
      end
      w.dead = true
      w.flash = 0.3
      local tx, ty = tip(w)
      local rnd = love.math.random
      for _ = 1, 26 do
        local a = rnd() * math.pi * 2
        local sp = 60 + rnd() * 150
        effects.particle(tx, ty - 4, math.cos(a) * sp, math.sin(a) * sp - 20, 0.2 + rnd() * 0.3, rnd() < 0.5 and { 0.85, 0.95, 1 } or { 0.5, 0.8, 1 }, 200, true)
      end
      for _ = 1, 10 do
        effects.particle(w.x + (rnd() - 0.5) * 4, w.y + rnd() * LEN, (rnd() - 0.5) * 90, -10 - rnd() * 60, 0.6 + rnd() * 0.4, rnd() < 0.5 and { 0.78, 0.92, 1.0 } or { 0.55, 0.7, 0.85 }, 520)
      end
      pcall(function()
        require("src.audio").playAt("wisp_crackle", tx, ty, 1, 1.6)
      end)
      return true
    end
  end
  return false
end

-- (for the tests) the first wire's state
function livewire.dbgState()
  return wires[1] and wires[1].state or "none"
end

function livewire.interact()
  return false
end

local function R(c, a, x, y, ww, h)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), ww, h)
end

local function inView(view, w)
  return w.x > view.x - 40 and w.x < view.x + view.w + 40 and w.y > view.y - 60 and w.y < view.y + view.h + 60
end

-- A shard hanging from the roof: pale blue glass, tapering to a point, with a lit core
local GLASS_D, GLASS, GLASS_L = { 0.20, 0.28, 0.40 }, { 0.42, 0.60, 0.78 }, { 0.78, 0.92, 1.0 }
local function shard(x, y, len, w0, lit, rooted)
  for i = 0, len - 1 do
    local half = math.max(0, math.floor(w0 * (1 - i / len) + 0.5))
    -- the first rows are sunk in the rock: fainter, as if seen through it
    local a = (rooted and i < 3) and (0.35 + 0.22 * i) or 1
    R(GLASS_D, a, x - half - 1, y + i, half * 2 + 3, 1)
    R(GLASS, a, x - half, y + i, half * 2 + 1, 1)
    if half > 0 then
      R(GLASS_L, a, x - half, y + i, 1, 1) -- (the lit edge)
    end
    if lit and i > 1 and i < len - 2 then
      R(GLASS_L, lit * a, x, y + i, 1, 1) -- (the core)
    end
  end
end

-- the rock the glass grows from: a ragged collar of dark crumbs and chips round its root, no flat bracket
local function root(x, y)
  for i = -6, 6 do
    local h = (math.sin((x + i) * 12.9898 + y * 4.1) * 43758.5453) % 1
    local depth = math.floor((1 - math.abs(i) / 7) * 3 + h * 2 + 0.5)
    if depth > 0 then
      R(i % 2 == 0 and { 0.17, 0.15, 0.19 } or { 0.22, 0.20, 0.25 }, 1, x + i, y - 1, 1, depth + 1)
    end
  end
  R({ 0.30, 0.34, 0.44 }, 0.6, x - 2, y + 1, 5, 1) -- (a glint of glass where the rock closes round it)
end

function livewire.draw(view)
  for _, w in ipairs(wires) do
    if inView(view, w) then
      if w.dead then
        shard(w.x, w.y, 6, 2, nil, true) -- (shattered: a broken stump)
        R(GLASS_L, 0.5, w.x + 2, w.y + 7, 1, 1)
      else
        local lit = w.state == "charge" and (0.5 + 0.5 * (1 - w.t / 1.1)) or (w.state == "arc" and 1 or 0.3 + 0.15 * math.sin(clock * 2 + w.x))
        shard(w.x - 4, w.y - 1, 8, 1, lit * 0.6, true)
        shard(w.x + 4, w.y - 1, 10, 1, lit * 0.6, true)
        shard(w.x, w.y - 2, LEN + 2, 2, lit, true)
      end
      root(w.x, w.y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- (a 32 x 32 soft blob, alpha falling off smoothly from the middle to the edges, made once)
local glow
local function glowImage()
  if not glow then
    local data = love.image.newImageData(32, 32)
    for y = 0, 31 do
      for x = 0, 31 do
        local dx, dy = (x + 0.5 - 16) / 16, (y + 0.5 - 16) / 16
        local d = math.min(1, math.sqrt(dx * dx + dy * dy))
        local a = (1 - d) ^ 2
        data:setPixel(x, y, 1, 1, 1, a)
      end
    end
    glow = love.graphics.newImage(data)
    glow:setFilter("linear", "linear")
  end
  return glow
end

local function bolt(x0, y0, x1, y1, seed)
  local n = 9
  local px, py = x0, y0
  for i = 1, n do
    local t = i / n
    local jx = (i < n) and ((math.sin(seed + i * 4.1) * 43758.5453) % 1 - 0.5) * 9 or 0
    local nx, ny = x0 + (x1 - x0) * t + jx, y0 + (y1 - y0) * t
    local steps = math.max(math.abs(nx - px), math.abs(ny - py))
    for k = 0, steps do
      local f = steps > 0 and k / steps or 0
      R({ 0.85, 0.95, 1 }, 1, px + (nx - px) * f, py + (ny - py) * f, 1, 1)
    end
    px, py = nx, ny
  end
end

function livewire.drawEmissive(view)
  for _, w in ipairs(wires) do
    if inView(view, w) and w.flash then
      -- the burst: a bright ring of light that swells and fades
      local k = 1 - w.flash / 0.3
      local tx, ty = tip(w)
      love.graphics.setColor(0.8, 0.95, 1, 0.8 * (1 - k))
      local d = 18 + 40 * k
      love.graphics.draw(glowImage(), tx - d / 2, ty - 4 - d / 2, 0, d / 32, d / 32)
    end
    if inView(view, w) and not w.dead then
      local tx, ty = tip(w)
      if w.state == "charge" then
        local k = 1 - w.t / 1.1
        local flick = math.floor(clock * 24) % 2
        R({ 0.6, 0.85, 1 }, 0.2 + 0.6 * k, tx - 1, ty + 1, 3, 3)
        love.graphics.setColor(0.6, 0.85, 1, 0.1 + 0.3 * k)
        love.graphics.draw(glowImage(), tx - 12, ty - 10, 0, 24 / 32, 24 / 32)
        if flick == 0 then
          R({ 0.85, 0.95, 1 }, 0.6 * k, tx + (flick == 0 and 3 or -3), ty + 1, 2, 1)
        end
      elseif w.state == "arc" then
        local seed = math.floor(clock * 40) * 1.7 + w.x
        bolt(tx, ty + 2, tx + ((math.sin(seed) * 43758.5453) % 1 - 0.5) * 6, ty + (w.arc or ARC_MIN), seed)
        -- a soft falloff round the bolt: a gradient image, brightest down its middle, fading out to the sides and at both ends
        local arc = w.arc or ARC_MIN
        local img = glowImage()
        local gw, gh = 44, arc + 14
        love.graphics.setColor(0.7, 0.9, 1, 0.42 + 0.12 * math.sin(clock * 50))
        love.graphics.draw(img, tx - gw / 2, ty - 4, 0, gw / 32, gh / 32)
      else
        local pulse = 0.5 + 0.5 * math.sin(clock * 2 + w.x)
        love.graphics.setColor(0.6, 0.85, 1, 0.07 + 0.06 * pulse) -- (a faint light in the glass)
        love.graphics.draw(glowImage(), w.x - 9, w.y - 2, 0, 18 / 32, (LEN + 6) / 32)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function livewire.addLights(lighting, view)
  for _, w in ipairs(wires) do
    if inView(view, w) and w.flash then
      local tx, ty = tip(w)
      lighting.add(tx, ty - 4, 80, 0.7, 0.9, 1, 1.2 * (w.flash / 0.3))
    end
    if inView(view, w) and not w.dead then
      local tx, ty = tip(w)
      if w.state == "arc" then
        local arc = w.arc or ARC_MIN
        for k = 0, math.floor(arc / 40) do -- (a light every few dozen px down the bolt, so it lights the whole way to the floor)
          lighting.add(tx, ty + 14 + k * 40, 90, 0.7, 0.9, 1, 1.0)
        end
      elseif w.state == "charge" then
        lighting.add(tx, ty + 2, 44, 0.6, 0.85, 1, 0.3 + 0.4 * (1 - w.t / 1.1))
      end
    end
  end
end

function livewire.drawScreen() end

return livewire
