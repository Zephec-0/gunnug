-- The gunslinger: Noita-style walking/jumping, recoil jumping, aiming and kicking.
local Body = require("src.body")
local audio = require("src.audio")
local bullets = require("src.bullets")
local config = require("src.config")
local controls = require("src.input")
local effects = require("src.effects")
local juice = require("src.juice")
local enemies = require("src.enemies")
local perks = require("src.perks")
local physics = require("src.physics")
local pickups = require("src.pickups")
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
    -- One-way platforms: only landed on, falling or standing, and S drops through
    local plats = self.world.platforms
    if plats and self.body.vy >= 0 and not controls.down("down") then
      local feet = cy + ch
      for _, p in ipairs(plats) do
        if feet == p.y + 1 and cx + cw > p.x0 and cx <= p.x1 then
          return true
        end
      end
    end
    return false
  end

  -- Kinematic stand-in so physics objects collide with the player
  local cx, cy = x + cfg.width / 2, y + cfg.height / 2
  self.physBody = love.physics.newBody(physics.world, cx, cy, "kinematic")
  love.physics.newFixture(self.physBody, love.physics.newRectangleShape(cfg.width, cfg.height))
  self.physBody:setFixedRotation(true)
  self.groundProp = nil
  self.maxHp = perks.maxHp(cfg.maxHp)
  self.hp = self.maxHp
  self.airJumps = 0 -- Double Jump: mid-air jumps left
  self.haste = 0 -- Adrenaline: seconds of extra speed left
  self.streak = 0 -- Momentum: recent kills
  self.streakTimer = 0
  self.regenAcc = 0
  self.drainTimer = 3
  self.dead = false
  self.invuln = 0 -- can't be hurt again until this runs out
  self.hurtFlash = 0 -- red screen flash after a hit
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
  self.rollT = nil -- seconds into the current dodge roll (nil when not rolling)
  self.rollDir = 1
  self.rollCooldown = 0
  self.rollBuffer = 0
  self.rollDodged = false -- something was dodged during this roll (shown once)
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

-- Shift: roll as soon as the hunter is on the ground (see Player:update)
function Player:pressRoll()
  self.rollBuffer = cfg.rollBuffer
end

-- Is he inside the invulnerable part of a dodge roll?
function Player:isDodging()
  return self.rollT ~= nil and self.rollT >= cfg.rollIFrameStart and self.rollT <= cfg.rollIFrameEnd
end

-- Something would have hit him mid-roll: a little "Dodge", once per roll
function Player:dodged()
  if self.rollDodged then
    return
  end
  self.rollDodged = true
  local cx = self:center()
  effects.popup(cx, self.body.y - 6, "Dodge", { 0.7, 0.85, 1 })
  audio.play("tick", 0.5, 1.4)
end

function Player:startRoll(dir)
  local b = self.body
  self.rollT = 0
  self.rollDir = dir
  self.rollCooldown = cfg.rollCooldown
  self.rollBuffer = 0
  self.rollDodged = false
  self.sliding = false
  self.springBonus = 0
  self.kickTimer = 0
  if not self.crouched then
    -- Tucked into a ball: the crouching hitbox, so it fits under low gaps
    self.crouched = true
    self:setHeight(cfg.crouchHeight)
  end
  b.vx = dir * cfg.rollSpeed
  audio.play("land", 0.8, 1.5)
  for _ = 1, 8 do
    local c = 0.4 + love.math.random() * 0.15
    effects.particle(b.x + b.w / 2 - dir * 2 + (love.math.random() - 0.5) * 6, b.y + b.h - 1, -dir * (20 + love.math.random() * 40), -8 - love.math.random() * 30, 0.45, { c, c * 0.9, c * 0.85 }, 200)
  end
end

function Player:kick()
  if self.kickCooldown > 0 or self.rollT then
    return
  end
  self.kickCooldown = cfg.kickCooldown
  self.kickTimer = cfg.kickDuration
  local b = self.body
  local x = self.facing > 0 and b.x + b.w or b.x - cfg.kickRange
  audio.play("kick")
  local damage = cfg.kickDamage * perks.prod("kickDamage")
  if self.gun and self.gun:stats().bayonet > 0 then
    damage = damage * 3
  end
  targets.kick(x, b.y + 6, cfg.kickRange, b.h - 6, damage)
  enemies.kick(x, b.y + 6, cfg.kickRange, b.h - 6, self.facing, damage)
  props.kick(x, b.y + 6, cfg.kickRange, b.h - 6, self.facing, cfg.kickForce, cfg.kickLift, damage)
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
  local st = self.gun:stats()
  local strength = st.recoil
  local ix, iy = -math.cos(angle) * strength, -math.sin(angle) * strength
  if self.grounded then
    local scale = st.jets > 0 and 0.6 or cfg.groundRecoilScale -- Jump Jets
    b.vx = b.vx + ix * scale
    b.vy = b.vy + iy * scale
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
  local st = self.gun:stats()
  local ctx = {
    damageMult = (self.hp < self.maxHp * 0.3) and (1 + perks.sum("lastStand")) or 1,
    fireRate = 1 + 0.06 * self.streak,
    still = math.abs(self.body.vx) < 25 and self.grounded,
  }
  local shots, side = self.gun:fire(self.aimAngle, ctx)
  if not shots then
    return
  end
  -- Bullets start at the shoulder and travel out through the barrel, so a
  -- monster pressed up against the hunter (closer than the muzzle) still
  -- gets hit, and a wall in front of the barrel blocks the shot
  local sx, sy = self:shoulder()
  for _, s in ipairs(shots) do
    bullets.spawn(sx, sy, s)
  end
  -- Spent shell: pistols and machine guns spit it out at once, revolvers and
  -- the double-barrel keep theirs until a reload
  local cs = self.gun.def.casing
  if cs and cs.eject == "shot" then
    local len = self.gun.def.length
    local f = self.facing
    effects.casing(
      self.muzzleX - math.cos(self.aimAngle) * len * 0.55,
      self.muzzleY - math.sin(self.aimAngle) * len * 0.55 - 1,
      -f * (30 + love.math.random() * 50) + self.body.vx * 0.4,
      -(70 + love.math.random() * 70) + self.body.vy * 0.3,
      cs.size,
      nil,
      cs.hull
    )
  end
  local quiet = st.sneak > 0 -- Suppressor
  effects.muzzleFlash(self.muzzleX, self.muzzleY, self.aimAngle, self.gun.def.flash * (quiet and 0.5 or 1), self.gun.def.model)
  audio.play("shot_" .. (self.gun.def.model == "pistol" and "pistol" or self.gun.def.model), quiet and 0.35 or nil)
  if side then
    if side.cost > 0 and self.hp > 1 then
      -- Blood Rounds: every shot costs blood, but never the last drop
      self.hp = math.max(1, self.hp - side.cost)
      effects.popup(self.muzzleX, self.muzzleY - 6, "-" .. side.cost, { 0.8, 0.1, 0.15 })
    end
    if side.misfire then
      bullets.blast(self.muzzleX, self.muzzleY, 1, 0.8) -- Unstable Rounds
    end
  end
  if self.gun.chambers == 0 then
    audio.play("reload", 0.8)
  end
  self:applyRecoil(self.aimAngle)
  juice.shot(self.aimAngle, st.recoil, quiet)
  playeranim.onShoot(self)
end

-- Takes damage from something at (fromX, fromY): knocks the hunter away from
-- it and makes him briefly invulnerable. Returns true if the hit landed.
-- Takes amount off the hunter's health after his damage modifiers (perks,
-- cursed items), with Second Wind and Adrenaline. Returns the damage dealt.
function Player:loseHealth(amount)
  local cx = self:center()
  local vulnerable = self.gun and self.gun:stats().vulnerable or 0
  amount = math.max(1, math.floor(amount * perks.prod("dmgTaken") * (1 + vulnerable) + 0.5))
  if self.hp - amount <= 0 and perks.has("second_wind") and not self.inventory.secondWindUsed then
    -- Second Wind: the first killing blow leaves the hunter standing
    self.inventory.secondWindUsed = true
    amount = 0
    self.hp = math.ceil(self.maxHp * 0.3)
    effects.popup(cx, self.body.y - 14, "Second Wind!", { 0.55, 0.9, 0.8 })
  else
    self.hp = math.max(0, self.hp - amount)
  end
  if perks.has("adrenaline") then
    self.haste = 3
  end
  return amount
end

-- Damage that wears the hunter down rather than striking him (poison gas):
-- no knockback or invulnerability, and the blink after a hit doesn't stop it
-- source: what is doing it (an id for src.deaths: an enemy kind, "gas", "fire"...)
function Player:hurtOverTime(amount, color, source)
  if self.dead then
    return
  end
  self.lastSource, self.lastEnemy = source, nil
  amount = self:loseHealth(amount)
  self.hurtFlash = math.max(self.hurtFlash, 0.35)
  local cx = self:center()
  effects.popup(cx, self.body.y - 4, "-" .. amount, color or { 1, 0.3, 0.3 })
  if self.hp <= 0 then
    audio.play("death")
    self.dead = true
    playeranim.onDeath(self, self.facing)
  end
end

function Player:hurt(amount, fromX, fromY, source)
  if self.dead or self.invuln > 0 then
    return false
  end
  if self:isDodging() then
    self:dodged()
    return false
  end
  self.lastSource, self.lastEnemy = source, nil -- (the last thing to hurt him is what killed him; an enemy sets lastEnemy to itself)
  local b = self.body
  local cx, cy = self:center()
  amount = self:loseHealth(amount)
  audio.play(self.hp <= 0 and "death" or "hurt")
  juice.hurt(amount)
  self.invuln = cfg.hurtInvulnerability
  self.hurtFlash = 1
  effects.popup(cx, b.y - 4, "-" .. amount, { 1, 0.3, 0.3 })
  local dir = cx >= (fromX or cx) and 1 or -1
  playeranim.onHurt(self, dir)
  b.vx = dir * cfg.hurtKnockback
  b.vy = math.min(b.vy, -cfg.hurtLift)
  self.jumping = false
  for _ = 1, 8 do
    effects.particle(cx, cy, (love.math.random() - 0.5) * 120, -love.math.random() * 90, 0.5, { 0.55, 0.06, 0.09 }, 480)
  end
  if self.hp <= 0 then
    -- He topples over, then bursts apart (see playeranim.updateDeath)
    self.dead = true
    playeranim.onDeath(self, dir)
  end
  return true
end

-- Healing from perks, ammo and kills
function Player:heal(amount)
  if self.dead or amount <= 0 or self.hp >= self.maxHp then
    return
  end
  local healed = math.min(self.maxHp - self.hp, amount)
  self.hp = self.hp + healed
  local cx = self:center()
  effects.popup(cx, self.body.y - 4, "+" .. math.floor(healed + 0.5), { 0.5, 1, 0.55 })
end

-- A new max health (a perk was taken): the extra health is granted at once,
-- a lower maximum cuts current health down to it
function Player:refreshMaxHp()
  local newMax = perks.maxHp(cfg.maxHp)
  if newMax > self.maxHp then
    self.hp = self.hp + (newMax - self.maxHp)
  end
  self.maxHp = newMax
  self.hp = math.min(self.hp, newMax)
end

-- An enemy died; fx is the effects of the bullet that last hit it
function Player:onKill(enemy, fx)
  if self.dead then
    return
  end
  self:heal(perks.sum("killHeal") + (fx and fx.vamp or 0))
  if perks.has("momentum") then
    self.streak = math.min(5, self.streak + 1)
    self.streakTimer = 4
  end
  if fx and fx.refill and fx.refill > 0 and fx.gun then
    fx.gun:refill(fx.refill)
  end
end

-- Perks that tick over time
function Player:updatePerks(dt)
  self.haste = math.max(0, self.haste - dt)
  if self.streakTimer > 0 then
    self.streakTimer = self.streakTimer - dt
    if self.streakTimer <= 0 then
      self.streak = 0
    end
  end
  local regen = perks.sum("regen")
  if regen > 0 and self.hp < self.maxHp then
    self.regenAcc = self.regenAcc + regen * dt
    if self.regenAcc >= 1 then
      self.regenAcc = self.regenAcc - 1
      self.hp = math.min(self.maxHp, self.hp + 1)
    end
  end
  if perks.sum("drain") > 0 then
    self.drainTimer = self.drainTimer - dt
    if self.drainTimer <= 0 then
      self.drainTimer = 3
      self.hp = math.max(1, self.hp - 1)
    end
  end
end

-- Hurt timers keep running while dead (the screen flash fades out)
function Player:updateHurt(dt)
  if self.dead then
    playeranim.updateDeath(self, dt)
  end
  self.invuln = math.max(0, self.invuln - dt)
  self.hurtFlash = math.max(0, self.hurtFlash - dt * 3)
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
  self.ignoreProps = props.overlapping(b.x, b.y, b.w, b.h, self.ignoreProps)

  -- Aim
  local sx, sy = self:shoulder()
  self.aimAngle = math.atan2(aimY - sy, aimX - sx)
  self.facing = aimX >= sx and 1 or -1
  if self.rollT then
    self.facing = self.rollDir -- (tucked up, he faces the way he rolls)
  end
  self:updateMuzzle()

  -- Timers
  self.kickCooldown = math.max(0, self.kickCooldown - dt)
  self.kickTimer = math.max(0, self.kickTimer - dt)
  self.jumpBufferTimer = math.max(0, self.jumpBufferTimer - dt)
  self.rollCooldown = math.max(0, self.rollCooldown - dt)
  self.rollBuffer = math.max(0, self.rollBuffer - dt)
  self:checkGround()
  self.coyoteTimer = self.grounded and cfg.coyoteTime or math.max(0, self.coyoteTimer - dt)
  if self.grounded then
    self.airJumps = perks.sum("airJumps")
  end
  self:updatePerks(dt)

  -- Horizontal movement. Momentum above walk speed (from recoil) is kept and
  -- only bled off by friction, so walking never cancels a recoil jump.
  local input = 0
  if controls.down("left") then
    input = input - 1
  end
  if controls.down("right") then
    input = input + 1
  end

  -- Dodge roll: starts on the ground (or just off it), runs its course, then
  -- he stands back up (or stays crouched under a low ceiling)
  if self.rollBuffer > 0 and not self.rollT and self.rollCooldown <= 0 and (self.grounded or self.coyoteTimer > 0) and not self.inWater and not self.dead then
    self:startRoll(input ~= 0 and input or self.facing)
  end
  if self.rollT then
    self.rollT = self.rollT + dt
    if self.rollT >= cfg.rollTime then
      self.rollT = nil
    end
  end
  if not self.rollT then
    self:updateCrouch(dt, controls.down("crouch"))
  end

  local walk = cfg.walkSpeed * perks.prod("speed") * (self.haste > 0 and 1.35 or 1) * (self.inWater and 0.6 or 1)
  local maxSpeed = (self.crouched and self.grounded) and cfg.crouchSpeed or walk
  local friction = self.grounded and cfg.groundFriction or cfg.airFriction
  if self.rollT then
    -- Rolling ignores steering: fast at first, easing off toward the end
    local k = self.rollT / cfg.rollTime
    b.vx = self.rollDir * (cfg.rollSpeed + (cfg.rollEndSpeed - cfg.rollSpeed) * k * k)
    if self.grounded and love.math.random() < 0.35 then
      local c = 0.38 + love.math.random() * 0.12
      effects.particle(b.x + b.w / 2 - self.rollDir * 3, b.y + b.h - 1, -self.rollDir * 15, -6 - love.math.random() * 15, 0.35, { c, c * 0.9, c * 0.85 }, 150)
    end
  elseif self.sliding and self.grounded then
    -- Sliding ignores steering and coasts on its momentum. Gravity along the
    -- slope speeds it up going downhill and slows it going uphill.
    local slope = self:groundSlope()
    local along = config.gravity * cfg.gravityScale * slope / math.sqrt(1 + slope * slope)
    local before = math.abs(b.vx)
    b.vx = b.vx + along * cfg.slideSlopeAccel * dt
    b.vx = approach(b.vx, 0, cfg.slideFriction * perks.prod("slideFriction") * dt)
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
    self.rollT = nil -- jumping out of a roll keeps its speed
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
      b.vy = -cfg.jumpSpeed * perks.prod("jump") * cfg.slideJumpHeight
      for _ = 1, 10 do
        local c = 0.4 + love.math.random() * 0.15
        effects.particle(b.x + b.w / 2 + (love.math.random() - 0.5) * 8, b.y + b.h - 1, -dir * (20 + love.math.random() * 50), -10 - love.math.random() * 40, 0.5, { c, c * 0.9, c * 0.85 }, 200)
      end
    else
      b.vy = -cfg.jumpSpeed * perks.prod("jump")
    end
    self.sliding = false
    self.jumping = true
    self.jumpBufferTimer = 0
    self.coyoteTimer = 0
    self.grounded = false
    self.groundProp = nil
    jumped = true
  elseif self.jumpBufferTimer > 0 and not self.grounded and self.airJumps > 0 then
    -- Double Jump
    self.airJumps = self.airJumps - 1
    self.anim.flip = 0.0001 -- twirl
    b.vy = -cfg.jumpSpeed * perks.prod("jump") * 0.95
    self.jumping = true
    self.jumpBufferTimer = 0
    jumped = true
    for _ = 1, 8 do
      effects.particle(b.x + b.w / 2 + (love.math.random() - 0.5) * 6, b.y + b.h, (love.math.random() - 0.5) * 60, 20 + love.math.random() * 30, 0.35, { 0.8, 0.92, 1 }, 60, true)
    end
  end
  local jumpHeld = controls.down("jump")
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

  -- Gravity. In water he sinks slowly and swims up while jump is held.
  if self.inWater then
    b.vy = math.min(b.vy + config.gravity * cfg.gravityScale * 0.3 * dt, 90)
    b.vx = b.vx * (1 - math.min(1, 1.5 * dt))
    if jumpHeld then
      b.vy = math.max(b.vy - 520 * dt, -95)
    end
  else
    b.vy = math.min(b.vy + config.gravity * cfg.gravityScale * dt, cfg.maxFallSpeed)
  end

  -- Gun
  self.inventory:update(dt)
  self.gun = self.inventory:selectedGun()
  if self.gun ~= self.lastGun then
    self.lastGun = self.gun
    if self.gun then
      self.gun.drawn = true -- Quickdraw Holster: the first shot after switching
    end
  end
  pickups.extraMagnet = self.gun and self.gun:stats().magnet or 0
  local trigger = love.mouse.isDown(1) and not self.rollT
  if self.gun and self.gun.def.spoolTime then
    -- Gatling: the barrels wind up while the trigger is held, ratcheting
    -- faster and higher as they go
    self.gun:spinUp(dt, trigger)
    local spool = self.gun.spool
    self.spinClick = (self.spinClick or 0) - dt
    if spool > 0.02 and self.spinClick <= 0 then
      self.spinClick = 0.16 - 0.12 * spool
      audio.play("gatling_spin", 0.4 + 0.6 * spool, 0.7 + 0.9 * spool)
    end
  end
  if trigger then
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
    if blocker and self.rollT then
      -- A roll bowls small things over
      props.impulse(blocker, self.rollDir * 60, -25, blocker.body:getX(), b.y + b.h - 2)
    elseif blocker and input ~= 0 then
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
  lighting.add(cx, cy, 180, 1, 0.86, 0.66, 1.0)
  local lamp = self.gun and self.gun:stats().lamp or 0
  if lamp > 0 then
    lighting.add(cx, cy, 150 + lamp, 1, 0.82, 0.55, 0.6) -- Muzzle Lantern
  end
  local ex, ey = playeranim.eyes(self)
  lighting.add(ex, ey, 9, 1, 0.8, 0.4, 0.7)
end

-- Blinks while invulnerable after a hit; gone once dead (he bursts apart)
local function visible(self)
  return not self.dead and (self.invuln <= 0 or math.floor(self.invuln * 14) % 2 == 0)
end

function Player:drawEmissive()
  if visible(self) then
    playeranim.drawEyes(self)
    -- Laser Sight: a red line out to the first solid pixel
    if self.gun and self.gun:stats().laser > 0 then
      local dx, dy = math.cos(self.aimAngle), math.sin(self.aimAngle)
      local x, y = self.muzzleX, self.muzzleY
      local length = 0
      while length < 320 and not self.world:isSolid(math.floor(x + dx * length), math.floor(y + dy * length)) do
        length = length + 2
      end
      love.graphics.setColor(1, 0.15, 0.15, 0.55)
      love.graphics.line(x, y, x + dx * length, y + dy * length)
      love.graphics.setColor(1, 0.5, 0.5)
      love.graphics.rectangle("fill", math.floor(x + dx * length), math.floor(y + dy * length), 1, 1)
    end
  end
end

function Player:draw()
  if self.dead then
    if not self.anim.gone then
      playeranim.draw(self) -- the collapse
    end
  elseif visible(self) then
    playeranim.draw(self)
  end
end

return Player
