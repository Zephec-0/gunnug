-- Central tuning values. Units are game pixels and seconds.
--
-- The world is authored at 640x360 game pixels per screen, which maps exactly
-- 3:1 onto 1920x1080 (no blurring). When rescaling the whole game, multiply
-- lengths, speeds, accelerations and forces by the same factor; masses and
-- times stay the same; pixel-count limits scale by the factor squared.
local config = {
  -- Low-res render target, scaled up to the window (see design doc §2)
  VIRTUAL_W = 640,
  VIRTUAL_H = 360,

  -- Screen-space UI (HUD, item bar, text) is sized in units of
  -- render.scale * UI_SCALE window pixels, independent of pixel density.
  UI_SCALE = 1.6,

  -- World gravity, shared by the player and physics objects. Objects scale it
  -- with their own gravityScale (see props.lua).
  gravity = 672,

  physics = {
    meter = 12.8, -- pixels per Box2D metre; keeps small props in Box2D's comfort zone
    chunkSize = 48, -- terrain collision is rebuilt per chunk of this many pixels
    simplify = 1.0, -- outline simplification tolerance in pixels
  },

  player = {
    width = 8,
    height = 19,
    maxHp = 100,

    -- The player feels less gravity than the world default, for more air control
    gravityScale = 0.8,
    maxFallSpeed = 448,
    maxSpeed = 576, -- hard cap on total velocity (recoil stacking)

    walkSpeed = 112,
    groundAccel = 1440,
    airAccel = 1040,
    groundFriction = 1600,
    airFriction = 208, -- how quickly excess (recoil) momentum bleeds off in the air
    stepHeight = 5, -- pixels the player can walk up without jumping

    -- Crouching and sliding (Ctrl). Crouching shrinks the hitbox so the
    -- player fits under low gaps; pressing it while moving starts a slide.
    crouchHeight = 12,
    crouchSpeed = 50,
    slideMinSpeed = 70, -- moving at least this fast when Ctrl goes down starts a slide
    slideBoost = 1.2, -- speed multiplier on entering a slide...
    slideMaxSpeed = 260, -- ...but never above this
    slideBoostCooldown = 0.4, -- re-sliding sooner than this gets no boost
    slideFriction = 170, -- deceleration while sliding (low: momentum carries)
    slideEndSpeed = 45, -- slower than this, the slide becomes a crouch-walk
    -- Slopes: gravity along the slope speeds a slide up downhill and slows it uphill
    slideSlopeAccel = 1.0, -- fraction of (the player's) gravity applied along the slope
    slideTopSpeed = 380, -- slopes can't push a slide faster than this
    slideStartSlope = 0.4, -- crouching on a downhill at least this steep (rise/run) starts a slide
    -- Slide-jump: springing out of a slide goes higher and further
    slideJumpHeight = 1.15, -- vertical speed multiplier vs. a normal jump
    slideJumpBoost = 1.3, -- horizontal speed multiplier...
    slideJumpBonus = 40, -- ...plus a flat kick (px/s)...
    slideJumpMaxSpeed = 380, -- ...capped here
    slideJumpBonusDecay = 2.5, -- the extra speed fades in the air (half gone in ~0.28 s); leftovers are removed on landing, so slide-jumps can't be chained for speed

    jumpSpeed = 211,
    jumpCutMultiplier = 0.5, -- releasing jump early shortens it
    coyoteTime = 0.08,
    jumpBufferTime = 0.1,

    -- Recoil is mainly an airborne mechanic; on the ground it is heavily reduced
    groundRecoilScale = 0.15,

    -- Interaction with physics objects
    pushForce = 512, -- force applied while walking into an object (heavier = slower)
    standForce = 192, -- the player's weight pressing on an object they stand on
    headBonk = 0.6, -- fraction of upward speed passed to an object hit from below

    -- Getting hurt (design doc §4.3)
    hurtInvulnerability = 0.9, -- seconds before the hunter can be hurt again
    hurtKnockback = 170, -- sideways speed away from what hit him
    hurtLift = 120,

    kickRange = 14,
    kickForce = 272,
    kickLift = 112,
    kickDamage = 3,
    kickCooldown = 0.35,
    kickDuration = 0.15,
  },
}

return config
