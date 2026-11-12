-- Gas lines (src.cavegen builds them, src.events spawns the chest and the oil): a chamber sealed in the rock and full of
-- gas, with a chest in it. The way out is a corridor stopped by a thick brick plug with one thin slit through its top,
-- and the gas seeps out of that slit into the cave. Two barrels of lamp oil stand beside it.
--
-- The solution: spill the oil along the floor to the slit and set it alight (a fire round, a lantern, a burning
-- hunter...). The flame runs along the oil to the slit and in, the gas in the chamber catches, and when it goes it
-- blows the plug out. This module watches for fire in the chamber and then breaks the plug with a blast a moment later.
-- The chamber is full of gas until then: opening it any other way (digging in) lets the gas out into the cave, where a
-- spark will light it.
-- Joins the secrets (src.secrets).
local effects = require("src.effects")
local materials = require("src.materials")

local gasline = {}

local lines = {}
local world
local clock = 0

function gasline.clear()
  lines, world = {}, nil
end

function gasline.setup(w, info)
  world = w
  for _, g in ipairs(info.gaslines or {}) do
    lines[#lines + 1] = { x = g.x, y = g.y, dir = g.dir, room = g.room, plug = g.plug, slit = g.slit, state = "sealed", t = 0 }
  end
end

local function fireInRoom(g)
  local fluids = require("src.fluids")
  local r = g.room
  for y = r.y0, r.y1, 4 do
    for x = r.x0, r.x1, 4 do
      if fluids.fireAt(x, y) then
        return true
      end
    end
  end
  return false
end

local function blowPlug(g)
  local p = g.plug
  local cx, cy = (p.x0 + p.x1) / 2, (p.y0 + p.y1) / 2
  pcall(function()
    require("src.bullets").blast(cx, cy, 4, 3.2, 14, 8, "keg")
    require("src.audio").play("explosion", 0.8, 0.7)
  end)
  -- The fire takes the whole mouth out: the plug top to bottom (the blast alone may leave a stump of brick), and
  -- the lip of the oil trough in front of it, so what is left is a doorway to walk through
  local x0, x1 = p.x0, p.x1
  if g.dir == 1 then
    x1 = p.x1 + 48
  else
    x0 = p.x0 - 48
  end
  for y = p.y0, p.y1 - 1 do
    for x = x0, x1 do
      local id = world:get(x, y)
      if id ~= materials.AIR and (id == materials.STONEBRICK or x < p.x0 or x > p.x1) then
        world:setRaw(x, y, materials.AIR)
        if love.math.random() < 0.1 then
          effects.particle(x, y, -g.dir * (30 + love.math.random() * 80), -love.math.random() * 60, 0.9, { 0.45, 0.44, 0.5 }, 480)
        end
      end
    end
  end
  world:repaintRegion(x0 - 3, p.y0 - 3, x1 + 3, p.y1 + 3)
  require("src.physics").rebuildRegion(x0 - 3, p.y0 - 3, x1 + 3, p.y1 + 3)
  pcall(function()
    require("src.fluids").wake(p.x0 - 10, p.y0 - 10, p.x1 + 10, p.y1 + 10)
  end)
end

function gasline.update(dt, player)
  clock = clock + dt
  if not world then
    return
  end
  for _, g in ipairs(lines) do
    if g.state == "sealed" then
      g.check = (g.check or 0) - dt
      if g.check <= 0 then
        g.check = 0.15
        if fireInRoom(g) then
          g.state, g.t = "burning", 0 -- the gas has caught
        end
        -- (the plug can also be taken out some other way, by a blast: then it is simply open)
        local mid = math.floor((g.plug.x0 + g.plug.x1) / 2)
        -- (looked for above the slit: the slit itself is open air, and reading that made every plug count as
        -- already open, so the fire in the chamber never blew it)
        if world:get(mid, g.plug.y0 + 3) ~= materials.STONEBRICK then
          g.state = "open"
        end
      end
    elseif g.state == "burning" then
      g.t = g.t + dt
      if g.t > 0.7 then
        blowPlug(g)
        g.state = "open"
      elseif love.math.random() < 0.5 then
        pcall(function()
          require("src.camera").shake(0.05 + g.t * 0.1)
        end)
      end
    end
  end
end

function gasline.interact()
  return false
end

local function R(c, a, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

local function near(view, g)
  return g.x > view.x - 140 and g.x < view.x + view.w + 140 and g.y > view.y - 120 and g.y < view.y + view.h + 120
end

-- The plug wears a stencilled flame so the way is readable, and a stain of oil-black soot round the slit
function gasline.draw(view)
  for _, g in ipairs(lines) do
    if g.state == "sealed" and near(view, g) then
      local p = g.plug
      -- a stencilled flame on the cave face of the plug
      local fx = g.dir == 1 and p.x1 + 1 or p.x0 - 4
      local fy = p.y1 - 6
      R({ 0.10, 0.08, 0.08 }, 0.9, fx, fy + 3, 3, 3)
      R({ 0.85, 0.42, 0.12 }, 0.95, fx + 1, fy, 1, 4)
      R({ 0.95, 0.72, 0.25 }, 0.95, fx + 1, fy + 2, 1, 2)
      -- soot streaked above the slit
      R({ 0.06, 0.05, 0.05 }, 0.5, g.slit.x - 1, g.slit.y - 8, 3, 7)
      R({ 0.06, 0.05, 0.05 }, 0.35, g.slit.x - 2, g.slit.y - 12, 5, 4)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Gas wisps pour out of the slit, green and slow, so the way to it reads from afar
function gasline.drawEmissive(view)
  for _, g in ipairs(lines) do
    if g.state == "sealed" and near(view, g) then
      if love.math.random() < 0.18 then
        effects.particle(g.slit.x, g.slit.y, g.dir * (6 + love.math.random() * 10), -3 - love.math.random() * 5, 1.6, { 0.62, 0.85, 0.28 }, -4, true)
      end
      local pulse = 0.5 + 0.5 * math.sin(clock * 1.6 + g.x)
      R({ 0.55, 0.85, 0.25 }, 0.05 + 0.04 * pulse, g.slit.x - 3, g.slit.y - 3, 7, 6)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function gasline.addLights(lighting, view)
  for _, g in ipairs(lines) do
    if g.state == "sealed" and near(view, g) then
      lighting.add(g.slit.x, g.slit.y, 28, 0.55, 0.85, 0.28, 0.25)
    elseif g.state == "burning" then
      lighting.add((g.room.x0 + g.room.x1) / 2, (g.room.y0 + g.room.y1) / 2, 90, 1.0, 0.6, 0.2, 0.9)
    end
  end
end

function gasline.drawScreen() end

return gasline
