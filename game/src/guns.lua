-- Gun definitions and the gun state machine (design doc §5).
-- A gun fires its chambers in order and reloads automatically once empty,
-- like a Noita wand's cast delay / recharge time.
local guns = {}

guns.defs = {
  revolver = {
    name = "Revolver",
    chambers = 6,
    fireDelay = 0.25,
    reloadTime = 1.2,
    spread = 2, -- degrees, total cone
    damage = 10,
    pellets = 1,
    bulletSpeed = 650,
    recoil = 115, -- velocity impulse (px/s) applied opposite the shot
    impactForce = 160, -- impulse a bullet gives physics objects (deliberately exaggerated)
    digRadius = 2.5, -- crater size in terrain (pixels)
    digPower = 1, -- vs. material hardness: dirt 1, sandstone 2, rock 3
    slots = 4, -- ammo type / attachment slots (separate from chambers)
    -- Inventory icon: L light steel, # dark steel, c cylinder, w wood grip
    icon = {
      "                ",
      "   LLLLLLLLLLLLL",
      "  #############L",
      "  ####ccc###    ",
      "  ##  ccc  #    ",
      " www###  ##     ",
      "wwww            ",
      "www             ",
    },
  },
}

local Gun = {}
Gun.__index = Gun

function guns.new(name)
  local def = assert(guns.defs[name], "unknown gun: " .. tostring(name))
  return setmetatable({
    def = def,
    chambers = def.chambers,
    fireTimer = 0,
    reloadTimer = 0,
    slots = {}, -- slots[i] = item or nil, for i = 1..def.slots
  }, Gun)
end

function Gun:update(dt)
  self.fireTimer = math.max(0, self.fireTimer - dt)
  if self.reloadTimer > 0 then
    self.reloadTimer = self.reloadTimer - dt
    if self.reloadTimer <= 0 then
      self.reloadTimer = 0
      self.chambers = self.def.chambers
    end
  end
end

function Gun:isReloading()
  return self.reloadTimer > 0
end

-- 0 at the start of a reload, 1 when finished
function Gun:reloadProgress()
  return 1 - self.reloadTimer / self.def.reloadTime
end

function Gun:canFire()
  return self.chambers > 0 and self.fireTimer <= 0 and self.reloadTimer <= 0
end

-- Fires the next chamber. Returns a list of shots (see bullets.spawn) or nil.
function Gun:fire(angle)
  if not self:canFire() then
    return nil
  end
  local def = self.def
  self.chambers = self.chambers - 1
  self.fireTimer = def.fireDelay
  if self.chambers == 0 then
    self.reloadTimer = def.reloadTime
  end

  local shots = {}
  for i = 1, def.pellets do
    local offset = math.rad(def.spread) * (love.math.random() - 0.5)
    shots[i] = {
      angle = angle + offset,
      speed = def.bulletSpeed,
      damage = def.damage,
      impact = def.impactForce,
      digRadius = def.digRadius,
      digPower = def.digPower,
    }
  end
  return shots
end

return guns
