-- Live wires: the environment's shock. Bare cables hang from the roof of the old workings and the fen, their ends frayed.
-- Every few seconds one gathers a charge (a rising crackle and a blue glow, about a second of warning), then arcs down
-- from its tip: a thread of lightning 34 px long and a shock to anyone in it (Shocked, and harder on the Soaked). If
-- there is water under it, the whole pool takes the current (fluids.zap). A bullet through a cable cuts it (src.bullets calls
-- livewire.shot): it arcs once and is dead. Joins the secrets (src.secrets); src.cavegen finds the spots (info.wires), src.events
-- calls setup as an area spawns.
local effects = require("src.effects")
local fluids = require("src.fluids")
local status = require("src.status")

local livewire = {}

local wires = {}
local clock = 0
local LEN = 14 -- how far the cable hangs
local ARC = 34 -- how far the arc reaches below the tip

function livewire.clear()
  wires = {}
end

function livewire.setup(w, info)
  for i, s in ipairs(info.wires or {}) do
    wires[#wires + 1] = { x = s[1], y = s[2], state = "idle", t = 1.5 + ((i * 37 + s[1]) % 40) / 10, dead = false }
  end
end

local function tip(w)
  return w.x, w.y + LEN
end

local lastPlayer

-- The arc: sound, the pool under it and the hunter in it
local function fire(w, player)
  local tx, ty = tip(w)
  pcall(function()
    require("src.audio").playAt("wisp_crackle", tx, ty, 1, 1.3)
  end)
  for dy = 4, ARC + 20, 4 do
    if fluids.waterAt(tx, ty + dy) then
      fluids.zap(tx, ty + dy, 8)
      break
    end
  end
  if player and not player.dead then
    local pcx, pcy = player:center()
    if math.abs(pcx - tx) < 12 and pcy > ty - 4 and pcy < ty + ARC then
      player:hurt(math.floor(8 * status.shockMult(player) + 0.5), tx, ty, "shock")
      status.apply(player, "shocked", 0.8)
    end
  end
end

function livewire.update(dt, player)
  clock = clock + dt
  lastPlayer = player
  local pcx, pcy = player:center()
  for _, w in ipairs(wires) do
    if not w.dead and math.abs(pcx - w.x) < 420 and math.abs(pcy - w.y) < 360 then
      w.t = w.t - dt
      local tx, ty = tip(w)
      if w.state == "idle" and w.t <= 0 then
        w.state, w.t = "charge", 1.1
      elseif w.state == "charge" then
        if love.math.random() < dt * 30 then
          effects.particle(tx + (love.math.random() - 0.5) * 6, ty + love.math.random() * 8, (love.math.random() - 0.5) * 30, 10 + love.math.random() * 20, 0.25, { 0.7, 0.9, 1 }, 0, true)
        end
        if w.t <= 0 then
          w.state, w.t = "arc", 0.35
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

-- A bullet at (x, y) through the cable cuts it: it arcs once, to whoever is under it, and is dead for good
function livewire.shot(x, y)
  for _, w in ipairs(wires) do
    if not w.dead and not w.cut and math.abs(x - w.x) < 4 and y > w.y and y < w.y + LEN + 4 then
      w.cut = true
      if w.state ~= "arc" then
        w.state, w.t = "arc", 0.35
        if lastPlayer then
          fire(w, lastPlayer)
        end
      end
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

function livewire.draw(view)
  for _, w in ipairs(wires) do
    if inView(view, w) then
      local tx, ty = tip(w)
      -- a bracket in the roof, the cable swaying a little, a frayed copper end
      R({ 0.30, 0.28, 0.32 }, 1, w.x - 2, w.y, 5, 2)
      local sway = w.dead and 0 or math.floor(math.sin(clock * 1.2 + w.x) * 1.2 + 0.5)
      for i = 0, LEN - 1 do
        local k = i / LEN
        R(w.dead and { 0.14, 0.13, 0.15 } or { 0.10, 0.10, 0.12 }, 1, w.x + math.floor(sway * k * k), w.y + 2 + i, 1, 1)
      end
      R({ 0.62, 0.40, 0.22 }, 1, tx - 1 + sway, ty, 1, 2)
      R({ 0.62, 0.40, 0.22 }, 1, tx + 1 + sway, ty + 1, 1, 2)
      R({ 0.80, 0.55, 0.30 }, 1, tx + sway, ty + 2, 1, 1)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
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
    if inView(view, w) and not w.dead then
      local tx, ty = tip(w)
      if w.state == "charge" then
        local k = 1 - w.t / 1.1
        local flick = math.floor(clock * 24) % 2
        R({ 0.6, 0.85, 1 }, 0.2 + 0.6 * k, tx - 1, ty + 1, 3, 3)
        R({ 0.6, 0.85, 1 }, 0.05 + 0.1 * k, tx - 3, ty - 1, 7, 6)
        if flick == 0 then
          R({ 0.85, 0.95, 1 }, 0.6 * k, tx + (flick == 0 and 3 or -3), ty + 1, 2, 1)
        end
      elseif w.state == "arc" then
        local seed = math.floor(clock * 40) * 1.7 + w.x
        bolt(tx, ty + 2, tx + ((math.sin(seed) * 43758.5453) % 1 - 0.5) * 6, ty + ARC, seed)
        for k = 1, 4 do -- (a falloff round the bolt, not a box)
          R({ 0.7, 0.9, 1 }, 0.07, tx - 1 - k * 2, ty + 3, 3 + k * 4, ARC - 3)
        end
      else
        R({ 0.6, 0.85, 1 }, 0.08, tx, ty + 2, 1, 1)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function livewire.addLights(lighting, view)
  for _, w in ipairs(wires) do
    if inView(view, w) and not w.dead then
      local tx, ty = tip(w)
      if w.state == "arc" then
        lighting.add(tx, ty + 14, 90, 0.7, 0.9, 1, 1.0)
      elseif w.state == "charge" then
        lighting.add(tx, ty + 2, 44, 0.6, 0.85, 1, 0.3 + 0.4 * (1 - w.t / 1.1))
      end
    end
  end
end

function livewire.drawScreen() end

return livewire
