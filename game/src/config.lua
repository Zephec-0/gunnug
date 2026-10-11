-- Central tuning values. Units are game pixels and seconds.
local config = {
  -- Low-res render target, scaled up to the window (see design doc §2).
  -- 400x225 is a 20% zoom-in from the original 480x270.
  VIRTUAL_W = 400,
  VIRTUAL_H = 225,

  -- World gravity, shared by the player and physics objects. Objects scale it
  -- with their own gravityScale (see props.lua).
  gravity = 420,

  physics = {
    meter = 8, -- pixels per Box2D metre; keeps small props in Box2D's comfort zone
    chunkSize = 32, -- terrain collision is rebuilt per chunk of this many pixels
    simplify = 0.6, -- outline simplification tolerance in pixels
  },

  player = {
    width = 5,
    height = 12,
    maxHp = 100,

    -- The player feels less gravity than the world default, for more air control
    gravityScale = 0.8,
    maxFallSpeed = 280,
    maxSpeed = 360, -- hard cap on total velocity (recoil stacking)

    walkSpeed = 70,
    groundAccel = 900,
    airAccel = 650,
    groundFriction = 1000,
    airFriction = 130, -- how quickly excess (recoil) momentum bleeds off in the air
    stepHeight = 3, -- pixels the player can walk up without jumping

    jumpSpeed = 132,
    jumpCutMultiplier = 0.5, -- releasing jump early shortens it
    coyoteTime = 0.08,
    jumpBufferTime = 0.1,

    -- Recoil is mainly an airborne mechanic; on the ground it is heavily reduced
    groundRecoilScale = 0.15,

    -- Interaction with physics objects
    pushForce = 320, -- force applied while walking into an object (heavier = slower)
    standForce = 120, -- the player's weight pressing on an object they stand on
    headBonk = 0.6, -- fraction of upward speed passed to an object hit from below

    kickRange = 9,
    kickForce = 170,
    kickLift = 70,
    kickDamage = 3,
    kickCooldown = 0.35,
    kickDuration = 0.15,
  },
}

return config
