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
  self.crouched = false
  self.sliding = false
  self.slideBoostTimer = 0
  self.wasGroundedLastFrame = true
  self.springBonus = 0 -- extra speed from a slide-jump, fading while airborne
  self.springDir = 1
  self.slideGrace = 0 -- a jump this soon after a slide still springs
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
  targets.kick(x, b.y + 6, cfg.kickRange, b.h - 6, cfg.kickDamage)
  props.kick(x, b.y + 6, cfg.kickRange, b.h - 6, self.facing, cfg.kickForce, cfg.kickLift, cfg.kickDamage)
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
  effects.muzzleFlash(self.muzzleX, self.muzzleY, self.aimAngle, self.gun.def.flash)
  self:applyRecoil(self.aimAngle)
  playeranim.onShoot(self)
end

-- Resizes the hitbox (and its physics stand-in), keeping the feet in place
function Player:setHeight(h)
  local b = self.body
  b.y = b.y + (b.h - h)
  b.h = h
  for _, f in ipairs(self.physBody:getFixtures()) do
    f:destroy()
  end
  love.physics.newFixture(self.physBody, love.physics.newRectangleShape(b.w, h))
end

-- Only terrain can keep the player crouched: loose objects (a crate resting on
-- a crouched player) are simply shoved aside by standing up
function Player:canStand()
  local b = self.body
  return not Body.terrainOverlaps(self.world, b.x, b.y + b.h - cfg.height, b.w, cfg.height)
end

-- Slope of the terrain under the feet, as rise per pixel toward +x: positive
-- means the ground drops away to the right. Clamped so ledges don't read as cliffs.
function Player:groundSlope()
  local b = self.body
  local feet = b.y + b.h
  local function groundAt(x)
    for y = feet - 6, feet + 10 do
      if self.world:isSolid(x, y) then
        return y
      end
    end
    return feet + 10
  end
  local cx = math.floor(b.x + b.w / 2)
  local slope = (groundAt(cx + 5) - groundAt(cx - 5)) / 10
  return math.max(-1.5, math.min(1.5, slope))
end

-- Crouch on Ctrl; stand back up when it's released and there's headroom.
-- Starting a crouch while moving (or landing in one) turns it into a slide.
function Player:updateCrouch(dt, crouchHeld)
  local b = self.body
  local wasCrouched = self.crouched
  if crouchHeld and not self.crouched then
    self.crouched = true
    self:setHeight(cfg.crouchHeight)
  elseif not crouchHeld and self.crouched and self:canStand() then
    self.crouched = false
    self.sliding = false
    self:setHeight(cfg.height)
  end

  self.slideBoostTimer = math.max(0, self.slideBoostTimer - dt)
  local startedCrouch = self.crouched and (not wasCrouched or not self.wasGroundedLastFrame)
  if self.crouched and self.grounded and startedCrouch and math.abs(b.vx) >= cfg.slideMinSpeed then
    self.sliding = true
    -- Only a fresh Ctrl press on the ground gets the entry boost; landing
    -- into a slide just keeps its momentum
    if self.slideBoostTimer <= 0 and not wasCrouched and self.wasGroundedLastFrame then
      local boosted = math.min(math.abs(b.vx) * cfg.slideBoost, cfg.slideMaxSpeed)
      b.vx = sign(b.vx) * math.max(math.abs(b.vx), boosted)
      self.slideBoostTimer = cfg.slideBoostCooldown
    end
  end
  -- Crouching on a steep downhill slides on its own; a slide only stops
  -- for being slow when the ground isn't steep enough to keep it going
  local steep = self.grounded and math.abs(self:groundSlope()) >= cfg.slideStartSlope
  if self.crouched and steep then
    self.sliding = true
  end
  if self.sliding and (not self.crouched or (math.abs(b.vx) < cfg.slideEndSpeed and not steep)) then
    self.sliding = false
  end
  self.slideGrace = self.sliding and 0.12 or math.max(0, self.slideGrace - dt)
  self.wasGroundedLastFrame = self.grounded
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
  self:updateCrouch(dt, love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl"))

  local maxSpeed = (self.crouched and self.grounded) and cfg.crouchSpeed or cfg.walkSpeed
  local friction = self.grounded and cfg.groundFriction or cfg.airFriction
  if self.sliding and self.grounded then
    -- Sliding ignores steering and coasts on its momentum. Gravity along the
    -- slope speeds it up going downhill and slows it going uphill.
    local slope = self:groundSlope()
    local along = config.gravity * cfg.gravityScale * slope / math.sqrt(1 + slope * slope)
    local before = math.abs(b.vx)
    b.vx = b.vx + along * cfg.slideSlopeAccel * dt
    b.vx = approach(b.vx, 0, cfg.slideFriction * dt)
    if math.abs(b.vx) > cfg.slideTopSpeed and math.abs(b.vx) > before then
      b.vx = sign(b.vx) * math.max(before, cfg.slideTopSpeed)
    end
    if love.math.random() < 0.5 then
      local c = 0.35 + love.math.random() * 0.15
      effects.particle(b.x + b.w / 2 - sign(b.vx) * 3, b.y + b.h - 1, -b.vx * 0.2, -10 - love.math.random() * 25, 0.4, { c, c * 0.9, c * 1.05 }, 120)
    end
  elseif input ~= 0 and not (sign(b.vx) == input and math.abs(b.vx) > maxSpeed) then
    local accel = self.grounded and cfg.groundAccel or cfg.airAccel
    b.vx = approach(b.vx, input * maxSpeed, accel * dt)
  elseif input ~= 0 then
    b.vx = approach(b.vx, input * maxSpeed, friction * dt)
  else
    b.vx = approach(b.vx, 0, friction * dt)
  end

  -- Jumping. Jumping out of a slide springs higher and further.
  local jumped = false
  if self.jumpBufferTimer > 0 and self.coyoteTimer > 0 then
    if self.crouched and self:canStand() then
      self.crouched = false
      self:setHeight(cfg.height)
    end
    if self.sliding or self.slideGrace > 0 then
      self.slideGrace = 0
      local dir = b.vx ~= 0 and sign(b.vx) or self.facing
      local before = math.abs(b.vx)
      local sprung = math.max(before, math.min(before * cfg.slideJumpBoost + cfg.slideJumpBonus, cfg.slideJumpMaxSpeed))
      b.vx = dir * sprung
      -- The extra speed is a temporary bonus that fades in the air
      self.springBonus = sprung - before
      self.springDir = dir
      b.vy = -cfg.jumpSpeed * cfg.slideJumpHeight
      for _ = 1, 10 do
        local c = 0.4 + love.math.random() * 0.15
        effects.particle(b.x + b.w / 2 + (love.math.random() - 0.5) * 8, b.y + b.h - 1, -dir * (20 + love.math.random() * 50), -10 - love.math.random() * 40, 0.5, { c, c * 0.9, c * 0.85 }, 200)
      end
    else
      b.vy = -cfg.jumpSpeed
    end
    self.sliding = false
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

  -- A slide-jump's extra speed bleeds away while airborne
  if self.springBonus > 0 and not self.grounded then
    local lost = self.springBonus * (1 - math.exp(-cfg.slideJumpBonusDecay * dt))
    self.springBonus = self.springBonus - lost
    if sign(b.vx) == self.springDir then
      b.vx = b.vx - self.springDir * math.min(lost, math.abs(b.vx))
    end
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
  if self.grounded and not jumped and self.springBonus > 0 then
    -- Whatever is left of a slide-jump's bonus is lost on landing, so
    -- chaining slide-jumps can't build up speed
    if sign(b.vx) == self.springDir then
      b.vx = b.vx - self.springDir * math.min(self.springBonus, math.abs(b.vx))
    end
    self.springBonus = 0
  end

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
  if math.abs(tx - px) + math.abs(ty - py) > 19 then -- teleported, not walked
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

-- Light carried with the hunter, plus the faint glow of his eyes
function Player:addLights(lighting)
  local cx, cy = self:center()
  lighting.add(cx, cy, 150, 1, 0.86, 0.66, 0.75)
  local ex, ey = playeranim.eyes(self)
  lighting.add(ex, ey, 9, 1, 0.8, 0.4, 0.7)
end

function Player:drawEmissive()
  playeranim.drawEyes(self)
end

function Player:draw()
  playeranim.draw(self)
end

return Player
