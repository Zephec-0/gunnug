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
    bulletSpeed = 1040,
    recoil = 184, -- velocity impulse (px/s) applied opposite the shot
    impactForce = 256, -- impulse a bullet gives physics objects (deliberately exaggerated)
    digRadius = 4, -- crater size in terrain (pixels)
    digPower = 1, -- vs. material hardness: dirt 1, sandstone 2, rock 3
    slots = 4, -- ammo type / attachment slots (separate from chambers)
    model = "revolver", -- how the hunter holds and draws it (playeranim.lua)
    length = 8.8, -- grip to muzzle, in pixels
    kick = 1, -- strength of the cosmetic recoil kick in the hands
    flash = 1, -- muzzle flash size
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

  -- Double-barrel: two shells of buckshot, a wide cone and a huge kick.
  -- The best recoil jumper.
  shotgun = {
    name = "Double-Barrel",
    chambers = 2,
    fireDelay = 0.35,
    reloadTime = 1.5,
    spread = 15,
    damage = 6,
    pellets = 7,
    speedJitter = 0.15, -- pellets leave at +-15% of bulletSpeed, so the cone spreads out
    bulletSpeed = 900,
    recoil = 340,
    impactForce = 88, -- per pellet
    digRadius = 2,
    digPower = 1,
    slots = 3,
    model = "shotgun",
    length = 12.5,
    kick = 1.4,
    flash = 1.8,
    icon = {
      "                ",
      "                ",
      "     LLLLLLLLLLL",
      "www#############",
      "wwwwww##c       ",
      "wwww   #        ",
      "ww              ",
      "                ",
    },
  },

  -- Early drum-fed machine gun: a long hose of weak rounds and a long reload.
  -- Its recoil is light per shot but sustained, so firing down slowly lifts
  -- the hunter for as long as the drum lasts.
  automatic = {
    name = "Machine Gun",
    chambers = 40,
    fireDelay = 0.06,
    reloadTime = 3.0,
    spread = 6,
    damage = 4,
    pellets = 1,
    bulletSpeed = 1100,
    recoil = 64,
    impactForce = 120,
    digRadius = 2,
    digPower = 1,
    slots = 5,
    model = "automatic",
    length = 11.5,
    kick = 0.45,
    flash = 0.7,
    icon = {
      "                ",
      "     ##         ",
      "LL#############L",
      "  #######cccccLL",
      "ww###  ##       ",
      "www#   ###      ",
      "ww     ###      ",
      "        #       ",
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

-- Starts a manual reload (right click). Only when at least one chamber is
-- spent and the gun isn't already reloading; takes the full reload time.
-- Returns true if a reload started.
function Gun:reload()
  if self.reloadTimer > 0 or self.chambers >= self.def.chambers then
    return false
  end
  self.reloadTimer = self.def.reloadTime
  return true
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
    local jitter = (def.speedJitter or 0) * (love.math.random() * 2 - 1)
    shots[i] = {
      angle = angle + offset,
      speed = def.bulletSpeed * (1 + jitter),
      damage = def.damage,
      impact = def.impactForce,
      digRadius = def.digRadius,
      digPower = def.digPower,
    }
  end
  return shots
end

return guns
