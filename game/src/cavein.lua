-- Cave-ins (prototype, see docs/todo.md): a ceiling slab of rock held up by timber props. Take the timber out (shoot it,
-- dig it, blow it up) and the roof lets go: first a rumble (dust and grit sifting off the slab's underside, cracks
-- opening along it, the screen trembling) for a second or so, then the whole slab comes down in chunks that fall as
-- physics debris, hurting whoever is under it and burying what is. A held slab can be dug round; an UNSUPPORTED slab
-- (no props) lets go when enough of its underside is dug out.
--
-- A zone is { x0, y0, x1, y1 } (the slab), supports = { { x, y0, y1 } } (timber columns of materials.WOOD, x the column's
-- middle), and
-- may be placed by src.cavegen later. For now cavein.addZone is called by hand (the dev panel and the test staging).
-- Joins the secrets (src.secrets): update, draw.
local effects = require("src.effects")
local materials = require("src.materials")

local cavein = {}

local zones = {}
local world
local WOOD = materials.WOOD
local RUMBLE = 2.2 -- seconds between the first sign and the fall (long enough to run clear of a 72 px span)
local STRESS_LIMIT = 220 -- pixels dug out of an unsupported slab's underside before it lets go

function cavein.clear()
  zones, world = {}, nil
end

function cavein.addZone(w, z)
  world = w
  z.state = "held"
  z.t = 0
  z.stress = 0
  z.cracks = {}
  z.supports = z.supports or {}
  zones[#zones + 1] = z
  return z
end

-- Whether a prop has been cut through: a gap of 8 px or more anywhere along its column (a bullet or a pick takes a bite
-- like that; it does not need to be felled) lets the roof drop
local function broken(z)
  for _, s in ipairs(z.supports) do
    local gap = 0
    for y = s.y0, s.y1, 2 do
      if world:get(s.x, y) == WOOD then
        gap = 0
      else
        gap = gap + 1
        if gap >= 4 then
          return true
        end
      end
    end
  end
  return false
end

-- Called by src.destruction.dig: n pixels were dug out round (cx, cy). Digging out the underside of a slab that has
-- no timber stresses it.
function cavein.onDig(cx, cy, radius, n)
  for _, z in ipairs(zones) do
    if z.state == "held" and #z.supports == 0 and cx > z.x0 - 8 and cx < z.x1 + 8 and cy > z.y0 - 10 and cy < z.y1 + 14 then
      z.stress = z.stress + n
    end
  end
end

function cavein.trigger(z)
  if z.state == "held" then
    z.state, z.t = "rumble", 0
    pcall(function()
      require("src.audio").play("rumble", 0.7, 0.8)
    end)
  end
end

local function collapse(z, player)
  z.state, z.t = "fallen", 0
  local destruction = require("src.destruction")
  -- the weight of the roof snaps whatever timber is left under it, in splinters
  for _, sp in ipairs(z.supports) do
    for y = sp.y0, sp.y1 do
      for x = sp.x - 2, sp.x + 1 do
        if world:get(x, y) == WOOD then
          world:setRaw(x, y, materials.AIR)
          if love.math.random() < 0.12 then
            effects.particle(x, y, (love.math.random() - 0.5) * 70, -love.math.random() * 50, 0.8, { 0.5, 0.34, 0.2 }, 480)
          end
        end
      end
    end
    world:repaintLater(sp.x - 3, sp.y0, sp.x + 2, sp.y1)
    require("src.physics").rebuildRegion(sp.x - 3, sp.y0, sp.x + 2, sp.y1)
  end
  local n = destruction.collapse(world, z.x0, z.y0, z.x1, z.y1, 11, 9)
  pcall(function()
    require("src.audio").play("explosion", 0.6, 0.5)
    require("src.juice").blast((z.x0 + z.x1) / 2, z.y1, 60)
  end)
  -- a cloud of dust off the whole slab
  for _ = 1, 70 do
    local x = z.x0 + love.math.random() * (z.x1 - z.x0)
    local c = 0.5 + love.math.random() * 0.2
    effects.particle(x, z.y1 + love.math.random() * 10, (love.math.random() - 0.5) * 50, -10 - love.math.random() * 40, 1.0 + love.math.random() * 0.8, { c, c * 0.88, c * 0.75 }, 90)
  end
  -- under it: hurt
  if player and not player.dead then
    local px, py = player:center()
    if px > z.x0 - 4 and px < z.x1 + 4 and py > z.y0 - 20 and py < z.y1 + 90 then
      player:hurt(22, px, z.y1 - 10, "cavein")
    end
  end
  pcall(function()
    local enemies = require("src.enemies")
    for _, e in ipairs(enemies.nearby()) do
      local b = e.body
      if not e.dead and b.x + b.w > z.x0 and b.x < z.x1 and b.y > z.y0 - 20 and b.y < z.y1 + 90 then
        enemies.damage(e, 70, 0, 1, 0, false, nil)
      end
    end
  end)
  return n
end

function cavein.update(dt, player)
  if not world then
    return
  end
  for _, z in ipairs(zones) do
    if z.state == "held" then
      z.check = (z.check or 0) - dt
      if z.check <= 0 then
        z.check = 0.1
        if #z.supports > 0 then
          if broken(z) then
            cavein.trigger(z)
          end
        elseif z.stress >= STRESS_LIMIT then
          cavein.trigger(z)
        end
      end
    elseif z.state == "rumble" then
      z.t = z.t + dt
      local k = z.t / RUMBLE
      -- grit sifting off the underside, more and more of it, and the screen trembling
      for _ = 1, 1 + math.floor(k * 4) do
        if love.math.random() < 0.6 then
          local x = z.x0 + love.math.random() * (z.x1 - z.x0)
          local c = 0.45 + love.math.random() * 0.2
          effects.particle(x, z.y1 + 1, (love.math.random() - 0.5) * 8, 10 + love.math.random() * 30, 0.6 + love.math.random() * 0.5, { c, c * 0.88, c * 0.74 }, 300)
        end
      end
      if love.math.random() < 0.15 + 0.4 * k then
        pcall(function()
          require("src.camera").shake(0.04 + 0.12 * k)
        end)
      end
      if z.t >= RUMBLE then
        collapse(z, player)
      end
    elseif z.state == "fallen" then
      z.t = z.t + dt
    end
  end
end

-- (for the tests) the state of the zone that starts at x0
function cavein.dbgState(x0)
  for _, z in ipairs(zones) do
    if z.x0 == x0 then
      return z.state .. " t=" .. string.format("%.2f", z.t)
    end
  end
  return "none (" .. #zones .. " zones)"
end

function cavein.interact()
  return false
end

local function R(c, a, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

-- Cracks opening across the slab's underside as the rumble goes on
function cavein.draw(view)
  for _, z in ipairs(zones) do
    if z.state == "held" and z.x1 > view.x - 20 and z.x0 < view.x + view.w + 20 and z.y1 > view.y - 20 and z.y0 < view.y + view.h + 20 then
      -- a held roof shows its age: a few hairline cracks and now and then a thread of grit from the beam
      for i = 1, 5 do
        local seed = i * 13.1 + z.x0
        local cx = z.x0 + 6 + ((math.sin(seed) * 43758.5453) % 1) * (z.x1 - z.x0 - 12)
        local len = 3 + ((math.sin(seed * 1.9) * 43758.5453) % 1) * 7
        for step = 0, math.floor(len) do
          local jx = math.floor(((math.sin(seed + step * 2.1) * 43758.5453) % 1 - 0.5) * 3)
          R({ 0.10, 0.08, 0.07 }, 0.45, cx + jx, z.y1 + 2 - step, 1, 1)
        end
      end
      if love.math.random() < 0.012 then
        effects.particle(z.x0 + love.math.random() * (z.x1 - z.x0), z.y1 + 3, 0, 14, 1.0, { 0.55, 0.48, 0.38 }, 200)
      end
    end
    if z.state == "rumble" and z.x1 > view.x - 20 and z.x0 < view.x + view.w + 20 and z.y1 > view.y - 20 and z.y0 < view.y + view.h + 20 then
      local k = math.min(1, z.t / RUMBLE)
      local n = 4 + math.floor(k * 8)
      for i = 1, n do
        local seed = i * 17.3 + z.x0
        local cx = z.x0 + ((math.sin(seed) * 43758.5453) % 1) * (z.x1 - z.x0)
        local len = (4 + ((math.sin(seed * 1.7) * 43758.5453) % 1) * 14) * (0.4 + k)
        local x, y = cx, z.y1
        for step = 0, math.floor(len) do
          local jx = math.floor(((math.sin(seed + step * 2.3) * 43758.5453) % 1 - 0.5) * 3)
          R({ 0.06, 0.05, 0.05 }, 0.8, x + jx, y - step, 1, 1)
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function cavein.drawEmissive() end
function cavein.addLights() end
function cavein.drawScreen() end

return cavein
