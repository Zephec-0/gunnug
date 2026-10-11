-- The gunslinger: Noita-style walking/jumping, recoil jumping, aiming and kicking.
local Body = require("src.body")
local bullets = require("src.bullets")
local config = require("src.config")
local effects = require("src.effects")
local physics = require("src.physics")
local playeranim = require("src.playeranim")
local props = require("src.props")
local targets = require("src.targets")

local cfg = config.player

local Player = {}
Player.__index = Player

local function approach(value, target, delta)
  if value < target then
    return math.min(value + delta, target)
  end
  return math.max(value - delta, target)
end

local function sign(v)
  return v > 0 and 1 or (v < 0 and -1 or 0)
end

-- inv: the run's inventory (src.inventory); the held gun is its selected weapon
function Player.new(x, y, world, inv)
  local self = setmetatable({}, Player)
  self.body = Body.new(x, y, cfg.width, cfg.height)
  self.world = world

  -- Props the player was already overlapping at the start of the frame are
  -- ignored, so a prop jammed into the player can never trap them.
  self.ignoreProps = {}
  self.collide = function(cx, cy, cw, ch)
    if Body.terrainOverlaps(self.world, cx, cy, cw, ch) then
      return true
    end
    local prop = props.overlapsRect(cx, cy, cw, ch, self.ignoreProps)
    if prop then
      return true, prop
    end
    return false
  end

  -- Kinematic stand-in so physics objects collide with the player
  local cx, cy = x + cfg.width / 2, y + cfg.height / 2
  self.physBody = love.physics.newBody(physics.world, cx, cy, "kinematic")
  love.physics.newFixture(self.physBody, love.physics.newRectangleShape(cfg.width, cfg.height))
  self.physBody:setFixedRotation(true)
  self.groundProp = nil
  self.hp = cfg.maxHp
  self.maxHp = cfg.maxHp
  self.inventory = inv
  self.gun = inv:selectedGun()
  self.facing = 1
  self.aimAngle = 0
  self.grounded = false
  self.coyoteTimer = 0
  self.jumpBufferTimer = 0
  self.jumping = false -- true while rising from a jump (so releasing jump can cut it)
  self.kickCooldown = 0
  self.kickTimer = 0
  self.anim = playeranim.new()
  self:updateMuzzle()
  return self
end

function Player:center()
  local b = self.body
  return b.x + b.w / 2, b.y + b.h / 2
end

function Player:shoulder()
  return playeranim.shoulder(self)
end

function Player:updateMuzzle()
  self.muzzleX, self.muzzleY = playeranim.muzzle(self)
end

function Player:pressJump()
  self.jumpBufferTimer = cfg.jumpBufferTime
end

function Player:kick()
  if self.kickCooldown > 0 then
    return
  end
  self.kickCooldown = cfg.kickCooldown
  self.kickTimer = cfg.kickDuration
  local b = self.body
  local x = self.facing > 0 and b.x + b.w or b.x - cfg.kickRange
  targets.kick(x, b.y + 4, cfg.kickRange, b.h - 4, cfg.kickDamage)
  props.kick(x, b.y + 4, cfg.kickRange, b.h - 4, self.facing, cfg.kickForce, cfg.kickLift, cfg.kickDamage)
end

-- Velocity along an axis after an airborne recoil kick: at least the kick's
-- speed in its direction. Kicks don't stack, so every shot is one even hop.
local function airKick(v, kick)
  if kick < 0 then
    return math.min(v, kick)
  elseif kick > 0 then
    return math.max(v, kick)
  end
  return v
end

-- Pushes the player opposite the shot. On the ground the push is heavily reduced.
function Player:applyRecoil(angle)
  local b = self.body
  local strength = self.gun.def.recoil
  local ix, iy = -math.cos(angle) * strength, -math.sin(angle) * strength
  if self.grounded then
    b.vx = b.vx + ix * cfg.groundRecoilScale
    b.vy = b.vy + iy * cfg.groundRecoilScale
  else
    b.vx = airKick(b.vx, ix)
    b.vy = airKick(b.vy, iy)
  end
  if iy < 0 then
    self.jumping = false -- recoil lift shouldn't be cut by releasing jump
  end
end

function Player:shoot()
  if not self.gun then
    return
  end
  local shots = self.gun:fire(self.aimAngle)
  if not shots then
    return
  end
  for _, s in ipairs(shots) do
    bullets.spawn(self.muzzleX, self.muzzleY, s)
  end
  effects.muzzleFlash(self.muzzleX, self.muzzleY, self.aimAngle)
  self:applyRecoil(self.aimAngle)
  playeranim.onShoot(self)
end

-- Grounded state, plus the prop underfoot (nil when standing on terrain)
function Player:checkGround()
  local b = self.body
  local hit, prop = Body.isGrounded(b, self.collide)
  self.grounded = hit and b.vy >= 0
  self.groundProp = self.grounded and prop or nil
end

function Player:update(dt, aimX, aimY)
  local b = self.body
  self.ignoreProps = props.overlapping(b.x, b.y, b.w, b.h)

  -- Aim
  local sx, sy = self:shoulder()
  self.aimAngle = math.atan2(aimY - sy, aimX - sx)
  self.facing = aimX >= sx and 1 or -1
  self:updateMuzzle()

  -- Timers
  self.kickCooldown = math.max(0, self.kickCooldown - dt)
  self.kickTimer = math.max(0, self.kickTimer - dt)
  self.jumpBufferTimer = math.max(0, self.jumpBufferTimer - dt)
  self:checkGround()
  self.coyoteTimer = self.grounded and cfg.coyoteTime or math.max(0, self.coyoteTimer - dt)

  -- Horizontal movement. Momentum above walk speed (from recoil) is kept and
  -- only bled off by friction, so walking never cancels a recoil jump.
  local input = 0
  if love.keyboard.isDown("a") then
    input = input - 1
  end
  if love.keyboard.isDown("d") then
    input = input + 1
  end
  local friction = self.grounded and cfg.groundFriction or cfg.airFriction
  if input ~= 0 and not (sign(b.vx) == input and math.abs(b.vx) > cfg.walkSpeed) then
    local accel = self.grounded and cfg.groundAccel or cfg.airAccel
    b.vx = approach(b.vx, input * cfg.walkSpeed, accel * dt)
  elseif input ~= 0 then
    b.vx = approach(b.vx, input * cfg.walkSpeed, friction * dt)
  else
    b.vx = approach(b.vx, 0, friction * dt)
  end

  -- Jumping
  local jumped = false
  if self.jumpBufferTimer > 0 and self.coyoteTimer > 0 then
    b.vy = -cfg.jumpSpeed
    self.jumping = true
    self.jumpBufferTimer = 0
    self.coyoteTimer = 0
    self.grounded = false
    self.groundProp = nil
    jumped = true
  end
  local jumpHeld = love.keyboard.isDown("w") or love.keyboard.isDown("space")
  if self.jumping and not jumpHeld and b.vy < 0 then
    b.vy = b.vy * cfg.jumpCutMultiplier
    self.jumping = false
  end

  -- Gravity
  b.vy = math.min(b.vy + config.gravity * cfg.gravityScale * dt, cfg.maxFallSpeed)

  -- Gun
  self.inventory:update(dt)
  self.gun = self.inventory:selectedGun()
  if love.mouse.isDown(1) then
    self:shoot()
  end

  -- Cap total speed so stacked recoil stays controllable
  local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
  if speed > cfg.maxSpeed then
    b.vx, b.vy = b.vx / speed * cfg.maxSpeed, b.vy / speed * cfg.maxSpeed
  end

  -- Move and collide. Walking into a prop shoves it; jumping into one from
  -- below bonks it upward.
  local wasGrounded = self.grounded
  local blocked, blocker = Body.moveX(b, self.collide, b.vx * dt, cfg.stepHeight)
  if blocked then
    if blocker and input ~= 0 then
      props.push(blocker, input * cfg.pushForce, 0)
    end
    b.vx = 0
  end
  blocked, blocker = Body.moveY(b, self.collide, b.vy * dt)
  if blocked then
    if b.vy < 0 then
      self.jumping = false
      if blocker then
        props.impulse(blocker, 0, b.vy * cfg.headBonk)
      end
    end
    b.vy = 0
  end
  if wasGrounded and not jumped and b.vy >= 0 then
    Body.snapDown(b, self.collide, cfg.stepHeight)
  end
  self:checkGround()

  -- The player's weight presses on whatever prop they stand on
  if self.groundProp then
    props.push(self.groundProp, 0, cfg.standForce)
  end

  playeranim.update(self, dt)
  self:updateMuzzle()
end

-- Before the physics step: move the kinematic stand-in to the player's new
-- position via velocity, so props get proper contact responses.
function Player:syncPhysics(dt)
  local b = self.body
  local tx, ty = b.x + b.w / 2, b.y + b.h / 2
  local px, py = self.physBody:getPosition()
  if math.abs(tx - px) + math.abs(ty - py) > 12 then -- teleported, not walked
    self.physBody:setPosition(tx, ty)
    self.physBody:setLinearVelocity(0, 0)
  else
    self.physBody:setLinearVelocity((tx - px) / dt, (ty - py) / dt)
  end
end

-- After the physics step: ride along with a moving prop underfoot
function Player:ride(dt)
  local prop = self.groundProp
  if not prop then
    return
  end
  local b = self.body
  local vx = prop.body:getLinearVelocityFromWorldPoint(b.x + b.w / 2, b.y + b.h)
  Body.moveX(b, self.collide, vx * dt, cfg.stepHeight)
end

function Player:draw()
  playeranim.draw(self)
end

return Player
