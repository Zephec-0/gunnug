-- Physics objects (Box2D rigid bodies): crates, falling terrain debris, and
-- later barrels and physics-based projectiles. Each type sets its own mass and
-- how strongly world gravity affects it (gravityScale) — together, its "weight".
local config = require("src.config")
local effects = require("src.effects")
local physics = require("src.physics")
local pickups = require("src.pickups")

local props = {}

local list = {}

local MAX_DEBRIS = 60 -- oldest terrain debris is removed beyond this

-- Prop art is drawn with whole-pixel rectangles from the top-left of the box
-- (x = -floor(w/2)), so every edge lands exactly on the pixel grid.
local function frame(x, y, w, h, t)
  love.graphics.rectangle("fill", x, y, w, t)
  love.graphics.rectangle("fill", x, y + h - t, w, t)
  love.graphics.rectangle("fill", x, y, t, h)
  love.graphics.rectangle("fill", x + w - t, y, t, h)
end

local function drawCrate(p)
  local w, h = p.width, p.height
  local x, y = -math.floor(w / 2), -math.floor(h / 2)
  love.graphics.setColor(0.52, 0.37, 0.24)
  love.graphics.rectangle("fill", x, y, w, h)
  -- Plank seams
  love.graphics.setColor(0.40, 0.28, 0.18)
  love.graphics.rectangle("fill", x, y + math.floor(h / 3), w, 1)
  love.graphics.rectangle("fill", x, y + math.floor(2 * h / 3), w, 1)
  -- Diagonal brace, one pixel per step
  love.graphics.setColor(0.32, 0.22, 0.14)
  for i = 2, w - 3 do
    love.graphics.rectangle("fill", x + i, y + math.floor(i * (h - 1) / (w - 1)), 1, 1)
  end
  love.graphics.setColor(0.22, 0.15, 0.10)
  frame(x, y, w, h, 1)
end

local function drawIronCrate(p)
  local w, h = p.width, p.height
  local x, y = -math.floor(w / 2), -math.floor(h / 2)
  love.graphics.setColor(0.30, 0.31, 0.36)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0.41, 0.42, 0.48)
  love.graphics.rectangle("fill", x + 2, y + 2, w - 4, 1) -- top highlight
  -- Brass band across the middle
  love.graphics.setColor(0.56, 0.44, 0.24)
  love.graphics.rectangle("fill", x + 1, y + math.floor(h / 2) - 1, w - 2, 2)
  love.graphics.setColor(0.14, 0.14, 0.17)
  frame(x, y, w, h, 1)
  -- Corner rivets
  love.graphics.setColor(0.58, 0.60, 0.66)
  for _, c in ipairs({ { 2, 2 }, { w - 3, 2 }, { 2, h - 3 }, { w - 3, h - 3 } }) do
    love.graphics.rectangle("fill", x + c[1], y + c[2], 1, 1)
  end
end

-- Terrain debris carries an image of the pixels it was cut from
local function drawDebris(p)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(p.image, -math.floor(p.width / 2), -math.floor(p.height / 2))
end

props.defs = {
  crate = {
    width = 13,
    height = 13,
    mass = 1,
    hp = 25, -- breaks when its damage total reaches this
    gold = { 0, 4 }, -- gold spilled when it breaks (min, max)
    itemChance = 0.12, -- chance it holds an ammo type or attachment
    gravityScale = 0.4,
    friction = 0.4,
    restitution = 0.25,
    linearDamping = 0.3,
    angularDamping = 0.4,
    showDamage = true,
    draw = drawCrate,
  },
  ironCrate = {
    width = 16,
    height = 16,
    mass = 4,
    hp = 90,
    gold = { 5, 12 },
    itemChance = 0.4,
    gravityScale = 0.6,
    friction = 0.7,
    restitution = 0.1,
    linearDamping = 0.3,
    angularDamping = 0.5,
    showDamage = true,
    draw = drawIronCrate,
  },
  -- Mass comes from the materials it is made of (materials.lua density)
  debris = {
    gravityScale = 0.7,
    friction = 0.7,
    restitution = 0.1,
    linearDamping = 0.2,
    angularDamping = 0.3,
    showDamage = false,
    draw = drawDebris,
  },
}

function props.clear()
  list = {} -- bodies are destroyed along with the physics world
end

local function newBody(def, x, y, angle)
  local body = love.physics.newBody(physics.world, x, y, "dynamic")
  body:setAngle(angle or 0)
  body:setGravityScale(def.gravityScale)
  body:setLinearDamping(def.linearDamping)
  body:setAngularDamping(def.angularDamping)
  return body
end

local function addFixture(def, body, shape, density)
  local fixture = love.physics.newFixture(body, shape, density)
  fixture:setFriction(def.friction)
  fixture:setRestitution(def.restitution)
  return fixture
end

local function register(prop)
  prop.flash = 0
  prop.total = 0
  list[#list + 1] = prop
  return prop
end

-- Spawns a box-shaped prop centred at (x, y)
function props.spawn(name, x, y, angle)
  local def = assert(props.defs[name], "unknown prop: " .. tostring(name))
  local body = newBody(def, x, y, angle)
  -- Density is per square metre; pick it so the body ends up with def.mass
  local m = config.physics.meter
  local density = def.mass / ((def.width / m) * (def.height / m))
  local fixture = addFixture(def, body, love.physics.newRectangleShape(def.width, def.height), density)
  return register({ def = def, body = body, fixtures = { fixture }, width = def.width, height = def.height })
end

local function remove(p)
  for i, q in ipairs(list) do
    if q == p then
      table.remove(list, i)
      break
    end
  end
  p.body:destroy()
end

-- Spawns a falling chunk of terrain.
--   image: the chunk's pixels; x, y: centre of its bounding box
--   rects: { {x, y, w, h}, ... } in image coordinates, covering the solid pixels
--   density: Box2D density (per square metre)
--   pixels, color: how many pixels it holds and a sample colour; it breaks
--   (crumbles) once damaged for about 40% of its pixel count, at least 6
function props.spawnDebris(image, x, y, rects, density, pixels, color)
  local def = props.defs.debris
  local w, h = image:getDimensions()
  local body = newBody(def, x, y, 0)
  local fixtures = {}
  for _, r in ipairs(rects) do
    local shape = love.physics.newRectangleShape(r[1] + r[3] / 2 - w / 2, r[2] + r[4] / 2 - h / 2, r[3], r[4])
    fixtures[#fixtures + 1] = addFixture(def, body, shape, density)
  end
  local prop = register({
    def = def,
    body = body,
    fixtures = fixtures,
    width = w,
    height = h,
    image = image,
    hp = math.max(6, math.floor((pixels or 20) * 0.4)),
    color = color,
  })

  local debrisCount = 0
  for _, q in ipairs(list) do
    if q.def == def then
      debrisCount = debrisCount + 1
    end
  end
  if debrisCount > MAX_DEBRIS then
    for _, q in ipairs(list) do
      if q.def == def then
        remove(q)
        break
      end
    end
  end
  return prop
end

-- Point test against the prop's actual (rotated) shapes
function props.hitTest(x, y)
  for _, p in ipairs(list) do
    for _, f in ipairs(p.fixtures) do
      if f:testPoint(x, y) then
        return p
      end
    end
  end
  return nil
end

-- Breaks a crate: wood splinters and any gold inside spills out. The prop
-- itself is removed on the next props.update, so callers that are looping
-- over the list aren't disturbed.
local function breakProp(p)
  p.broken = true
  local x, y = p.body:getPosition()
  local c = p.color or (p.def == props.defs.ironCrate and { 0.34, 0.35, 0.40 } or { 0.5, 0.36, 0.23 })
  for _ = 1, 12 do
    local a = love.math.random() * math.pi * 2
    local s = 30 + love.math.random() * 100
    effects.particle(x, y, math.cos(a) * s, math.sin(a) * s - 40, 0.6, c, 520)
  end
  local gold = p.def.gold
  if gold then
    pickups.dropGold(x, y, love.math.random(gold[1], gold[2]))
  end
  if p.def.itemChance then
    pickups.maybeDropItem(x, y, p.def.itemChance)
  end
end

function props.damage(p, amount)
  p.flash = 0.08
  p.total = p.total + amount
  local hp = p.hp or p.def.hp
  if hp and p.total >= hp and not p.broken then
    breakProp(p)
  end
  if p.def.showDamage then
    effects.popup(p.body:getX(), p.body:getY() - p.height / 2 - 2, tostring(amount), { 1, 0.9, 0.3 })
  end
end

-- Impulse at a world point (off-centre hits make the prop spin)
function props.impulse(p, ix, iy, x, y)
  if x then
    p.body:applyLinearImpulse(ix, iy, x, y)
  else
    p.body:applyLinearImpulse(ix, iy)
  end
end

function props.push(p, fx, fy)
  p.body:applyForce(fx, fy)
end

local EPS = 0.05

-- Separating-axis test: is the pixel rectangle overlapping a convex polygon?
local function polygonOverlapsRect(pts, x, y, w, h)
  local n = #pts
  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  for i = 1, n, 2 do
    minX, maxX = math.min(minX, pts[i]), math.max(maxX, pts[i])
    minY, maxY = math.min(minY, pts[i + 1]), math.max(maxY, pts[i + 1])
  end
  if minX >= x + w - EPS or maxX <= x + EPS or minY >= y + h - EPS or maxY <= y + EPS then
    return false
  end
  local corners = { x, y, x + w, y, x, y + h, x + w, y + h }
  for i = 1, n, 2 do
    local j = i + 2 > n and 1 or i + 2
    local nx, ny = pts[j + 1] - pts[i + 1], pts[i] - pts[j]
    local len = math.sqrt(nx * nx + ny * ny)
    nx, ny = nx / len, ny / len
    local pMin, pMax = math.huge, -math.huge
    for k = 1, n, 2 do
      local d = pts[k] * nx + pts[k + 1] * ny
      pMin, pMax = math.min(pMin, d), math.max(pMax, d)
    end
    local rMin, rMax = math.huge, -math.huge
    for k = 1, 8, 2 do
      local d = corners[k] * nx + corners[k + 1] * ny
      rMin, rMax = math.min(rMin, d), math.max(rMax, d)
    end
    if pMin >= rMax - EPS or pMax <= rMin + EPS then
      return false
    end
  end
  return true
end

local function overlapsRect(p, x, y, w, h)
  -- Cheap reject using the prop's bounding radius
  local bx, by = p.body:getPosition()
  local radius = (p.width + p.height) * 0.75
  if bx + radius < x or bx - radius > x + w or by + radius < y or by - radius > y + h then
    return false
  end
  for _, f in ipairs(p.fixtures) do
    if polygonOverlapsRect({ p.body:getWorldPoints(f:getShape():getPoints()) }, x, y, w, h) then
      return true
    end
  end
  return false
end

-- First prop overlapping the rectangle, skipping any in the `ignore` set
function props.overlapsRect(x, y, w, h, ignore)
  for _, p in ipairs(list) do
    if not (ignore and ignore[p]) and overlapsRect(p, x, y, w, h) then
      return p
    end
  end
  return nil
end

-- All props overlapping the rectangle, as a set
function props.overlapping(x, y, w, h)
  local set = {}
  for _, p in ipairs(list) do
    if overlapsRect(p, x, y, w, h) then
      set[p] = true
    end
  end
  return set
end

function props.kick(x, y, w, h, dir, force, lift, damage)
  for _, p in ipairs(list) do
    if overlapsRect(p, x, y, w, h) then
      props.damage(p, damage)
      -- Strike low on the object so it tumbles away
      props.impulse(p, dir * force, -lift, p.body:getX(), y + h * 0.75)
    end
  end
end

function props.all()
  return list
end

-- Remembers every object's velocity from just before the physics step. A
-- collision happens inside the step and changes the velocity, so impacts
-- have to be judged by the speed the object arrived with.
function props.snapshotVelocities()
  for _, p in ipairs(list) do
    p.prevVx, p.prevVy = p.body:getLinearVelocity()
  end
end

-- Impact damage (design doc §6a): what a moving object does to whatever it
-- hits, from its momentum (mass x speed, in the same units as a kick's
-- impulse). A kicked crate is worth about 7, a heavy iron crate or a big
-- chunk of falling rock far more; slow or resting objects do nothing.
-- vx, vy: the object's own velocity (px/s), so a creature walking into a
-- resting object never counts as an impact.
-- Returns damage (0 when too gentle), and the momentum itself.
local MIN_MOMENTUM = 90 -- below this an object just bumps
local MOMENTUM_PER_DAMAGE = 25

function props.impactDamage(p, vx, vy)
  local momentum = p.body:getMass() * math.sqrt(vx * vx + vy * vy)
  if momentum <= MIN_MOMENTUM then
    return 0, momentum
  end
  return math.floor((momentum - MIN_MOMENTUM) / MOMENTUM_PER_DAMAGE), momentum
end

function props.update(dt)
  for i = #list, 1, -1 do
    local p = list[i]
    p.flash = math.max(0, p.flash - dt)
    if p.broken then
      remove(p)
    end
  end
end

function props.draw()
  for _, p in ipairs(list) do
    love.graphics.push()
    -- Whole-pixel position: a sliding crate moves in clean pixel steps
    -- instead of resampling its pixels every frame
    love.graphics.translate(math.floor(p.body:getX() + 0.5), math.floor(p.body:getY() + 0.5))
    love.graphics.rotate(p.body:getAngle())
    if p.flash > 0 and p.def.showDamage then
      love.graphics.setColor(1, 1, 1)
      love.graphics.rectangle("fill", -math.floor(p.width / 2), -math.floor(p.height / 2), p.width, p.height)
    else
      p.def.draw(p)
    end
    love.graphics.pop()
  end
end

return props
