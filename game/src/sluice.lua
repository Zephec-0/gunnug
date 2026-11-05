-- Sluice caches: a chamber sealed in the rock, brim full of water, with a chest in the bottom of it. A corridor
-- runs out to the nearest cave and is stopped by a plank gate (src.cavegen builds the room, the corridor, the gate
-- and the water; src.events spawns the chest). Shoot or dig the gate out and the water pours into the cave. The chest
-- is waiting at the bottom of the draining chamber.
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
    caches[#caches + 1] = { x = c.x, y = c.y, room = c.room, gate = c.gate, dir = c.dir, open = false }
  end
end

local function gateStands(c)
  local g = c.gate
  local cx, cy = math.floor((g.x0 + g.x1) / 2), math.floor((g.y0 + g.y1) / 2)
  return world and world:get(cx, cy) == materials.WOOD
end

function sluice.update(dt, player)
  clock = clock + dt
  for _, c in ipairs(caches) do
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

function sluice.draw(view)
  for _, c in ipairs(caches) do
    if not c.open and near(view, c) then
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
