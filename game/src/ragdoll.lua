-- The hunter's ragdoll: when he dies (or passes out from drink) he drops into jointed physics parts (head, torso,
-- arms, legs) that tumble over the terrain and settle where they land. Lives in the physics world, so a new
-- world drops it; src.player keeps it as player.ragdoll.
local physics = require("src.physics")

local ragdoll = {}

local COLORS -- (the hunter's palette, from src.playeranim)

local function colors()
  COLORS = COLORS or require("src.playeranim").COLORS
  return COLORS
end

local GROUP = -77 -- the parts never collide with one another

local function part(world, x, y, w, h, density, name)
  local body = love.physics.newBody(world, x, y, "dynamic")
  body:setLinearDamping(0.15)
  body:setAngularDamping(0.5)
  local fixture = love.physics.newFixture(body, love.physics.newRectangleShape(w, h), density)
  fixture:setFriction(0.8)
  fixture:setRestitution(0.18)
  fixture:setGroupIndex(GROUP)
  physics.track(body) -- (switched off far from the hunter, and the ground round it traced while it moves)
  return { body = body, w = w, h = h, name = name }
end

local function hinge(world, a, b, x, y, lo, hi)
  local j = love.physics.newRevoluteJoint(a.body, b.body, x, y, false)
  j:setLimits(lo, hi)
  j:setLimitsEnabled(true)
  return j
end

-- Drops the hunter into parts at his feet. dir: the way he is thrown (-1 / +1); push: how hard (1 = a death)
function ragdoll.start(player, dir, push)
  local b = player.body
  local cx, fy = b.x + b.w / 2, b.y + b.h
  local world = physics.world
  local r = { parts = {}, joints = {}, facing = player.facing, age = 0 }
  local torso = part(world, cx, fy - 11, 6, 9, 1.6, "torso")
  local head = part(world, cx, fy - 18.5, 5, 5, 1.2, "head")
  local armB = part(world, cx - 1.5, fy - 11.5, 2, 7, 0.8, "armB")
  local armF = part(world, cx + 1.5, fy - 11.5, 2, 7, 0.8, "armF")
  local legB = part(world, cx - 1.3, fy - 3.5, 2.4, 7, 1.0, "legB")
  local legF = part(world, cx + 1.3, fy - 3.5, 2.4, 7, 1.0, "legF")
  r.parts = { legB, armB, torso, head, legF, armF }
  r.joints = {
    hinge(world, torso, head, cx, fy - 15.5, -0.9, 0.9),
    hinge(world, torso, armB, cx - 1.5, fy - 14.5, -2.6, 2.6),
    hinge(world, torso, armF, cx + 1.5, fy - 14.5, -2.6, 2.6),
    hinge(world, torso, legB, cx - 1.3, fy - 7, -1.1, 1.1),
    hinge(world, torso, legF, cx + 1.3, fy - 7, -1.1, 1.1),
  }
  push = push or 1
  local vx, vy = (b.vx or 0) * 0.6 + dir * 55 * push, math.min(b.vy or 0, 0) - 70 * push
  for _, p in ipairs(r.parts) do
    p.body:setLinearVelocity(vx + (love.math.random() - 0.5) * 20, vy + (love.math.random() - 0.5) * 20)
    p.body:setAngularVelocity(dir * (4 + love.math.random() * 3) * push)
  end
  -- (his stand-in no longer shoves props about, nor snags the parts)
  if player.physBody and not player.physBody:isDestroyed() then
    player.physBody:setActive(false)
  end
  player.ragdoll = r
  return r
end

local function R(c, w, h, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", -w / 2, -h / 2, w, h)
end

local function drawPart(p, f)
  local c = colors()
  local x, y = p.body:getPosition()
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(p.body:getAngle())
  love.graphics.scale(f, 1)
  if p.name == "torso" then
    R(c.coat, p.w, p.h)
    love.graphics.setColor(c.lining[1], c.lining[2], c.lining[3])
    love.graphics.rectangle("fill", -0.5, -p.h / 2, 1, p.h)
    R(c.mantle, p.w, 2.5)
    love.graphics.translate(0, p.h / 2 - 1)
    R(c.buckle, 1.5, 1)
  elseif p.name == "head" then
    love.graphics.setColor(0.72, 0.58, 0.50)
    love.graphics.rectangle("fill", -p.w / 2, -p.h / 2 + 1, p.w, p.h - 1)
    -- the hat sits on it
    love.graphics.setColor(c.hat[1], c.hat[2], c.hat[3])
    love.graphics.rectangle("fill", -p.w / 2 - 1.5, -p.h / 2 + 0.5, p.w + 3, 1.2)
    love.graphics.rectangle("fill", -p.w / 2 + 0.5, -p.h / 2 - 2, p.w - 1, 2.7)
    love.graphics.setColor(c.hatBand[1], c.hatBand[2], c.hatBand[3])
    love.graphics.rectangle("fill", -p.w / 2 + 0.5, -p.h / 2 - 0.2, p.w - 1, 0.7)
    love.graphics.setColor(c.eye[1], c.eye[2], c.eye[3], 0.5)
    love.graphics.rectangle("fill", 0.8, -0.3, 1, 1)
  elseif p.name == "armB" or p.name == "armF" then
    R(p.name == "armB" and c.coatDark or c.coat, p.w, p.h)
    love.graphics.setColor(c.glove[1], c.glove[2], c.glove[3])
    love.graphics.rectangle("fill", -p.w / 2, p.h / 2 - 1.5, p.w, 1.5)
  else
    R(p.name == "legB" and c.trousersDark or c.trousers, p.w, p.h)
    love.graphics.setColor(c.boots[1], c.boots[2], c.boots[3])
    love.graphics.rectangle("fill", -p.w / 2, p.h / 2 - 2, p.w + 0.8, 2)
  end
  love.graphics.pop()
end

-- Draws the parts back to front
function ragdoll.draw(r)
  for _, p in ipairs(r.parts) do
    drawPart(p, r.facing)
  end
end

-- Where the torso is (the camera and the lights follow it)
function ragdoll.center(r)
  local t = r.parts[3]
  return t.body:getPosition()
end

return ragdoll
