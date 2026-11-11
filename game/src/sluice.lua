-- Sluice caches: a chamber sealed in the rock, brim full of water, with a chest in the bottom of it. A corridor
-- runs out to the nearest cave and is stopped by a plank gate (src.cavegen builds the room, the corridor, the gate
-- and the water; src.events spawns the chest). Shoot or dig the gate out and the water pours into the cave. The chest
-- is waiting at the bottom of the draining chamber.
--
-- Where there is room a second chamber, a reservoir, sits over the first with a plank gate of its own on the other side.
-- Then the chest's gate is sealed (camp timber that cannot be shot away): shoot out the reservoir's gate, let it empty,
-- and a moment later the sealed gate lifts and the chest chamber drains. (A cache with no reservoir keeps the one gate.)
--
-- This module only dresses it: damp seeping from the gate, a faint pulse of the planks, drips from the corridor's
-- roof, a rusted wheel on the gate (so it reads as a sluice and not a plank wall), and the moment it gives.
-- Joins the secrets (src.secrets).
local effects = require("src.effects")
local materials = require("src.materials")

local sluice = {}

local caches = {} -- { x, y, room, gate, dir, open, wasShut }
local world
local clock = 0

function sluice.clear()
  caches, world = {}, nil
end

-- Called with each area as it is spawned (src.events.spawnArea)
function sluice.setup(w, info)
  world = w
  for _, c in ipairs(info.sluices or {}) do
    caches[#caches + 1] = { x = c.x, y = c.y, room = c.room, gate = c.gate, dir = c.dir, open = false, res = c.reservoir, resOpen = false, drained = 0 }
  end
end

local function gateStands(c, g)
  g = g or c.gate
  local cx, cy = math.floor((g.x0 + g.x1) / 2), math.floor((g.y0 + g.y1) / 2)
  if not world then
    return false
  end
  local id = world:get(cx, cy)
  return id == materials.WOOD or id == materials.HARDWOOD
end

-- Whether the reservoir has let its water go (the film left on the floor does not count)
local function reservoirEmpty(c)
  local r = c.res
  local fluids = require("src.fluids")
  for yy = r.y1 - 7, r.y1 - 3, 2 do
    for xx = r.x0 + 2, r.x1 - 2, 4 do
      if fluids.waterAt(xx, yy) then
        return false
      end
    end
  end
  return true
end

-- The sealed gate lifts: gone from the world, with a clank and a spray
local function liftGate(c)
  local g = c.gate
  world:fillRect(g.x0, g.y0, g.x1, g.y1, 0)
  world:repaintRegion(g.x0 - 3, g.y0 - 3, g.x1 + 3, g.y1 + 3)
  pcall(function()
    require("src.physics").rebuildRegion(g.x0 - 3, g.y0 - 3, g.x1 + 3, g.y1 + 3)
  end)
end

function sluice.update(dt, player)
  clock = clock + dt
  for _, c in ipairs(caches) do
    if c.res and not c.resOpen and not gateStands(c, c.res.plug) then
      c.resOpen = true -- the reservoir's gate is gone: its water is out
      local g = c.res.plug
      pcall(function()
        require("src.audio").play("clank", 0.9)
        require("src.fluids").wake(c.res.x0 - 20, c.res.y0 - 20, c.res.x1 + 100, c.res.y1 + 80)
        require("src.fluids").wake(c.res.x0 - 100, c.res.y0 - 20, c.res.x1 + 20, c.res.y1 + 80)
      end)
      for _ = 1, 20 do
        effects.particle((g.x0 + g.x1) / 2, (g.y0 + g.y1) / 2 + (love.math.random() - 0.5) * 8, -c.res.dir * (30 + love.math.random() * 60), -20 - love.math.random() * 40, 0.8, { 0.55, 0.75, 0.95 }, 260, true)
      end
    end
    if c.res and c.resOpen and not c.open then
      -- once the reservoir is empty (and has stayed so a moment), the sealed gate lifts
      if reservoirEmpty(c) then
        c.drained = c.drained + dt
        if c.drained > 1.2 and gateStands(c) then
          liftGate(c)
        end
      else
        c.drained = 0
      end
    end
    if not c.open and not gateStands(c) then
      c.open = true -- the gate is gone: the flood is out
      local g = c.gate
      local gx, gy = (g.x0 + g.x1) / 2, (g.y0 + g.y1) / 2
      pcall(function()
        require("src.audio").play("clank", 0.9)
        require("src.fluids").wake(c.room.x0 - 20, c.room.y0 - 20, c.room.x1 + 100, c.room.y1 + 20)
      end)
      for _ = 1, 20 do
        effects.particle(gx, gy + (love.math.random() - 0.5) * 8, -c.dir * (30 + love.math.random() * 60), -20 - love.math.random() * 40, 0.8, { 0.55, 0.75, 0.95 }, 260, true)
      end
    end
  end
end

function sluice.interact()
  return false
end

local function R(c, a, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

local function near(view, c)
  return c.x > view.x - 120 and c.x < view.x + view.w + 120 and c.y > view.y - 120 and c.y < view.y + view.h + 120
end

-- A gate seen from the cave: the rusted wheel on it and damp running down the planks
local function drawGate(c, g, dir)
  local cx = (g.x0 + g.x1) / 2
  local wx = dir == 1 and g.x1 + 2 or g.x0 - 5
  local wy = (g.y0 + g.y1) / 2 - 3
  R({ 0.30, 0.17, 0.10 }, 1, wx, wy + 2, 3, 2)
  R({ 0.30, 0.17, 0.10 }, 1, wx + 1, wy, 1, 6)
  R({ 0.47, 0.26, 0.14 }, 1, wx, wy + 2, 1, 2)
  for k = 0, 2 do
    local len = 3 + math.floor((math.sin(clock * 0.6 + k * 2 + cx) * 0.5 + 0.5) * 4)
    R({ 0.35, 0.55, 0.78 }, 0.5, g.x0 + k, g.y0 + 3, 1, len)
  end
  R({ 0.10, 0.16, 0.24 }, 0.6, g.x0 - 3, g.y1 - 1, 9, 1)
end

function sluice.draw(view)
  for _, c in ipairs(caches) do
    if c.res and not c.resOpen and near(view, c) then
      drawGate(c, c.res.plug, c.res.dir)
    end
    if c.res and not c.open and near(view, c) then
      -- the chest's gate, sealed: iron bands across the timber, and a lamp-lit rivet at each end
      local g = c.gate
      R({ 0.20, 0.20, 0.24 }, 1, g.x0, g.y0 + 1, 3, 1)
      R({ 0.20, 0.20, 0.24 }, 1, g.x0, g.y1 - 2, 3, 1)
      R({ 0.52, 0.52, 0.58 }, 1, g.x0 + 1, g.y0 + 1, 1, 1)
      R({ 0.52, 0.52, 0.58 }, 1, g.x0 + 1, g.y1 - 2, 1, 1)
    elseif not c.res and not c.open and near(view, c) then
      local g = c.gate
      local cx = (g.x0 + g.x1) / 2
      -- a rusted wheel pressed on the planks, on the cave's side of the gate
      local wx = c.dir == 1 and g.x1 + 2 or g.x0 - 5
      local wy = (g.y0 + g.y1) / 2 - 3
      R({ 0.30, 0.17, 0.10 }, 1, wx, wy + 2, 3, 2)
      R({ 0.30, 0.17, 0.10 }, 1, wx + 1, wy, 1, 6)
      R({ 0.47, 0.26, 0.14 }, 1, wx, wy + 2, 1, 2)
      -- damp running down the planks, a dark stain at the foot of the gate
      for k = 0, 2 do
        local len = 3 + math.floor((math.sin(clock * 0.6 + k * 2 + cx) * 0.5 + 0.5) * 4)
        R({ 0.35, 0.55, 0.78 }, 0.5, g.x0 + k, g.y0 + 3, 1, len)
      end
      R({ 0.10, 0.16, 0.24 }, 0.6, g.x0 - 3, g.y1 - 1, 9, 1)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Water seeping through the planks: a drip now and then, a faint blue lick on the gate
function sluice.drawEmissive(view)
  for _, c in ipairs(caches) do
    if not c.open and near(view, c) then
      local g = c.gate
      local pulse = 0.5 + 0.5 * math.sin(clock * 1.4 + c.x)
      R({ 0.5, 0.75, 1.0 }, 0.05 + 0.04 * pulse, g.x0 - 2, g.y0, 7, g.y1 - g.y0 + 1)
      if love.math.random() < 0.04 then
        effects.particle(g.x0 + love.math.random() * 3, g.y0 + 4, 0, 10, 0.7, { 0.55, 0.78, 1.0 }, 220, true)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function sluice.addLights(lighting, view)
  for _, c in ipairs(caches) do
    if not c.open and near(view, c) then
      local g = c.gate
      lighting.add((g.x0 + g.x1) / 2, (g.y0 + g.y1) / 2, 26, 0.45, 0.7, 1.0, 0.18)
    end
  end
end

function sluice.drawScreen() end

return sluice
