-- Weapon models for the item bar and weapon panel, in a chunky pixel style.
-- Each faces left (muzzle on the left) and is drawn on a grid of "cells", q
-- screen pixels to the cell. They show no ammo; each plays its own reload:
--   revolver   the cylinder swings out of the frame while the hammer is eased
--              back, the spent cases drop out, fresh rounds go in, it snaps shut
--   shotgun    a break-action double: the barrels hinge open, the hulls are
--              tossed out and two fresh shells drop in
--   automatic  an AK: the magazine drops away and a fresh one is slapped in
--   pistol     the Broomhandle: the bolt slides back, a stripper clip is set on
--              top and thumbed down into the box magazine, the empty clip flies off
local gunhud = {}

local STEEL, STEEL_L, STEEL_D = { 0.66, 0.68, 0.76 }, { 0.88, 0.90, 0.96 }, { 0.36, 0.37, 0.46 }
local INK = { 0.08, 0.07, 0.10 }
local WOOD, WOOD_L, WOOD_D = { 0.52, 0.32, 0.16 }, { 0.72, 0.47, 0.24 }, { 0.34, 0.20, 0.10 }
local BRASS, BRASS_L = { 0.95, 0.74, 0.26 }, { 1.0, 0.92, 0.55 }
local COPPER = { 0.84, 0.52, 0.28 }
local HULL, HULL_L, HULL_D = { 0.80, 0.16, 0.13 }, { 0.98, 0.42, 0.34 }, { 0.50, 0.08, 0.08 }
local BASE, BASE_D = { 0.95, 0.74, 0.26 }, { 0.68, 0.47, 0.15 }

local function ease(t)
  t = math.max(0, math.min(1, t))
  return t * t * (3 - 2 * t)
end

local function floor(x)
  return math.floor(x + 0.0001)
end

-- A filled-rectangle painter in cell units from the art's top-left pixel
local function painter(ox, oy, q, alpha)
  return function(x, y, w, h, c, a)
    love.graphics.setColor(c[1], c[2], c[3], (a or 1) * (alpha or 1))
    love.graphics.rectangle("fill", ox + floor(x) * q, oy + floor(y) * q, w * q, h * q)
  end
end

-- Revolver ------------------------------------------------------------------

local function drawRevolver(R, rp)
  local out = rp and (ease(rp / 0.12) - ease((rp - 0.84) / 0.1)) or 0
  local cock = rp and (ease(rp / 0.2) - ease((rp - 0.8) / 0.12)) or 0
  local cc = floor(2 * cock + 0.5)
  local dx, dy = -floor(7 * out + 0.5), floor(2 * out + 0.5)

  -- Barrel, front sight, the ejector rod underneath
  R(0, 3, 12, 1, STEEL_L)
  R(0, 4, 12, 1, STEEL)
  R(0, 2, 1, 1, STEEL_D)
  R(1, 5, 11, 1, STEEL_D)
  R(3, 6, 8, 1, STEEL_D)
  R(2, 6, 1, 1, STEEL)
  -- Frame: top strap, the body behind the cylinder, the floor under it
  R(12, 1, 12, 1, STEEL_L)
  R(19, 2, 5, 5, STEEL)
  R(19, 2, 5, 1, STEEL_L)
  R(23, 2, 1, 5, STEEL_D)
  R(12, 7, 8, 1, STEEL_D)
  R(12, 2, 1, 5, STEEL_D)
  -- The empty window the cylinder leaves
  if out > 0.25 then
    R(13, 2, 6, 5, INK)
  end

  -- Hammer, eased back while it reloads
  R(24 + cc, 2, 2, 2, STEEL)
  R(25 + cc, 1, 1, 1, STEEL_L)
  R(24 + cc, 4, 1, 1, STEEL_D)

  -- Grip: a backstrap, then wood curving back and down
  R(22, 5, 5, 2, STEEL)
  local grip = { { 23, 27 }, { 24, 28 }, { 24, 28 }, { 25, 29 }, { 25, 29 }, { 26, 29 }, { 26, 29 } }
  for r, g in ipairs(grip) do
    local c = r == 1 and WOOD_L or (r == #grip and WOOD_D or WOOD)
    R(g[1], 6 + r, g[2] - g[1] + 1, 1, c)
    R(g[1], 6 + r, 1, 1, WOOD_L)
  end
  -- Trigger guard and trigger
  R(15, 8, 8, 1, STEEL_D)
  R(15, 7, 1, 1, STEEL_D)
  R(19, 7, 1, 1, INK)

  -- The crane the cylinder hangs from when it swings out
  if dx < 0 then
    for k = 0, -dx do
      R(14 - k, 6 + floor(dy * k / -dx), 1, 1, STEEL_D)
    end
  end
  -- Cylinder
  local cx, cy = 12 + dx, 2 + dy
  R(cx, cy, 7, 5, STEEL)
  R(cx, cy, 7, 1, STEEL_L)
  R(cx, cy + 4, 7, 1, STEEL_D)
  R(cx, cy, 1, 5, STEEL_D)
  R(cx + 6, cy, 1, 5, STEEL_D)
  if out < 0.5 then
    R(cx + 2, cy + 1, 1, 3, STEEL_D)
    R(cx + 4, cy + 1, 1, 3, STEEL_D)
  else
    -- Swung out and turned side-on: its chambers lie along it, loaded one at a time
    for j = 0, 2 do
      local y = cy + 1 + j
      local t0 = 0.3 + j * 0.15
      R(cx + 1, y, 5, 1, INK)
      if rp >= t0 then
        R(cx + 1, y, 5, 1, BRASS)
        R(cx + 1, y, 1, 1, BRASS_L)
        R(cx + 5, y, 1, 1, COPPER)
      elseif rp >= t0 - 0.08 then
        local slide = (rp - (t0 - 0.08)) / 0.08
        R(cx - 6 + slide * 7, y, 3, 1, BRASS, slide) -- a round sliding in
      end
    end
    -- The spent cases falling out as it opens
    if rp > 0.12 and rp < 0.34 then
      local t = (rp - 0.12) / 0.22
      for j = 0, 2 do
        R(cx + 1 + 2 * j + (j - 1) * t * 2, cy + 5 + t * t * 8, 1, 1, BRASS, 1 - t)
      end
    end
  end
end

-- Double-barrel shotgun -----------------------------------------------------

local PIVOT_X, PIVOT_Y = 16, 10
local OPEN = 0.30

-- A shell, as it drops into a tube whose top row is y (local frame, breech at x = 16)
local function shellIn(R, y, dy)
  R(8, y + dy, 6, 3, HULL)
  R(8, y + dy, 6, 1, HULL_L)
  R(8, y + dy + 2, 6, 1, HULL_D)
  R(14, y + dy, 2, 3, BASE)
  R(14, y + dy, 2, 1, BRASS_L)
  R(15, y + dy + 1, 1, 2, BASE_D)
end

local function drawShotgun(R, rp, ox, oy, q)
  local TOP, LOW = 4, 7

  -- Stock, sloping down and back
  local stock = { { 22, 29 }, { 22, 31 }, { 24, 33 }, { 26, 34 }, { 28, 35 }, { 30, 35 }, { 31, 35 } }
  for r, s in ipairs(stock) do
    local c = r == 1 and WOOD_L or (r == #stock and WOOD_D or WOOD)
    R(s[1], 4 + r, s[2] - s[1] + 1, 1, c)
  end
  R(35, 7, 1, 5, INK) -- butt plate
  -- Action
  R(16, 3, 6, 8, STEEL)
  R(16, 3, 6, 1, STEEL_L)
  R(16, 10, 6, 1, STEEL_D)
  R(21, 3, 1, 8, STEEL_D)
  R(18, 6, 2, 2, STEEL_D)
  R(18, 6, 1, 1, STEEL_L)
  R(17, 2, 3, 1, STEEL_D)
  -- Trigger guard
  R(19, 11, 5, 1, STEEL_D)
  R(23, 9, 1, 3, STEEL_D)
  R(20, 10, 1, 1, INK)

  local open = rp and (ease(rp / 0.14) - ease((rp - 0.72) / 0.1)) or 0
  local function tube(slot, y)
    R(0, y, 16, 3, STEEL)
    R(0, y, 16, 1, STEEL_L)
    R(0, y + 2, 16, 1, STEEL_D)
    R(0, y, 2, 3, STEEL_D)
    R(0, y, 1, 1, STEEL)
    if open > 0.3 then
      R(14, y, 2, 3, INK) -- the empty breech
    end
    if rp then
      local ti = 0.5 + (slot - 1) * 0.06
      if rp >= ti and rp < ti + 0.2 then
        shellIn(R, y, -floor((1 - ease((rp - ti) / 0.2)) * 7)) -- dropped in from above
      end
    end
  end

  -- The barrels hinge about the pivot, muzzles dropping
  love.graphics.push()
  love.graphics.translate(ox + PIVOT_X * q, oy + PIVOT_Y * q)
  love.graphics.rotate(-OPEN * open)
  love.graphics.translate(-(ox + PIVOT_X * q), -(oy + PIVOT_Y * q))
  tube(2, TOP)
  tube(1, LOW)
  love.graphics.pop()

  -- Hulls tossed out of a broken-open gun
  if rp then
    for k = 0, 1 do
      local t = (rp - 0.14 - k * 0.04) / 0.3
      if t > 0 and t < 1 then
        local y = (k == 0 and LOW or TOP) + 1
        local ex, ey = 15 + 9 * t, y - 14 * t + 22 * t * t - 2
        R(ex - 4, ey, 3, 1, HULL, 1 - t * 0.6)
        R(ex - 1, ey, 1, 1, BRASS, 1 - t * 0.6)
      end
    end
  end
end

-- AK ------------------------------------------------------------------------

local MAG_X = { 17, 17, 16, 16, 15, 14, 13, 12, 11 }
local MAG_ROWS = 9

local function drawMag(R, dy, alpha)
  for r = 0, MAG_ROWS - 1 do
    local x, y = MAG_X[r + 1], 6 + r + dy
    R(x, y, 6, 1, STEEL_D, alpha)
    R(x + 1, y, 4, 1, r % 2 == 0 and STEEL_L or STEEL, alpha) -- the ribbed side
    R(x, y, 1, 1, STEEL, alpha)
  end
  R(MAG_X[MAG_ROWS], 6 + MAG_ROWS - 1 + dy, 6, 1, INK, alpha) -- floor plate
end

local function drawAutomatic(R, rp)
  local lift = 0
  if rp and rp > 0.75 and rp < 0.88 then
    lift = 1
  end
  local function Ra(x, y, w, h, c, a)
    R(x, y - lift, w, h, c, a)
  end
  -- Barrel, muzzle brake, sights and gas tube
  Ra(0, 3, 2, 2, STEEL_D)
  Ra(2, 3, 12, 1, STEEL)
  Ra(2, 4, 12, 1, STEEL_D)
  Ra(3, 1, 1, 2, STEEL_D)
  Ra(3, 2, 2, 3, STEEL_D)
  Ra(6, 1, 10, 1, STEEL_L)
  Ra(6, 2, 10, 1, STEEL)
  -- Wooden handguard
  Ra(11, 3, 9, 1, WOOD_L)
  Ra(11, 4, 9, 1, WOOD)
  Ra(11, 5, 9, 1, WOOD_D)
  Ra(15, 2, 5, 1, WOOD)
  -- Receiver, ejection port, rear sight
  Ra(19, 2, 11, 1, STEEL_L)
  Ra(19, 3, 11, 2, STEEL)
  Ra(19, 5, 11, 1, STEEL_D)
  Ra(23, 3, 4, 1, INK)
  Ra(28, 1, 2, 1, STEEL_D)
  -- Stock
  Ra(30, 3, 8, 1, WOOD_L)
  Ra(30, 4, 8, 1, WOOD)
  Ra(31, 5, 7, 1, WOOD)
  Ra(33, 6, 5, 1, WOOD_D)
  Ra(35, 7, 3, 1, WOOD_D)
  Ra(38, 3, 1, 5, INK)
  -- Pistol grip and trigger guard
  Ra(26, 6, 3, 2, WOOD)
  Ra(26, 6, 1, 2, WOOD_L)
  Ra(27, 8, 3, 2, WOOD_D)
  Ra(20, 6, 1, 2, STEEL_D)
  Ra(20, 7, 6, 1, STEEL_D)
  Ra(23, 6, 1, 1, INK)

  -- The magazine: out and down, a gap, then a fresh one slapped up into place
  if rp then
    local out = ease(rp / 0.2)
    local back = ease((rp - 0.45) / 0.3)
    if rp < 0.35 then
      drawMag(Ra, floor(out * 9), 1 - out)
    else
      drawMag(Ra, floor((1 - back) * 9), back)
    end
  else
    drawMag(Ra, 0, 1)
  end
end

-- Broomhandle ---------------------------------------------------------------

local function drawPistol(R0, rp)
  local function R(x, y, w, h, c, a)
    R0(x, y + 4, w, h, c, a) -- room above for the stripper clip
  end
  local slide = rp and (ease((rp - 0.03) / 0.1) - ease((rp - 0.82) / 0.1)) or 0
  local ds = floor(2 * slide + 0.5)

  -- The long barrel, front sight
  R(0, 3, 14, 1, STEEL_L)
  R(0, 4, 14, 1, STEEL)
  R(1, 2, 2, 1, STEEL_D)
  R(0, 2, 1, 2, STEEL_D)
  -- Receiver
  R(14, 2, 12, 1, STEEL_L)
  R(14, 3, 12, 2, STEEL)
  R(14, 5, 12, 1, STEEL_D)
  R(23, 1, 2, 1, STEEL_D) -- rear sight
  if slide > 0.3 then
    R(15, 2, 8, 2, INK) -- the open top of the receiver
  end
  R(23 + ds, 2, 4, 2, STEEL_L) -- the bolt, sliding back
  R(23 + ds, 3, 4, 1, STEEL)
  R(26, 2, 2, 4, STEEL_D)
  -- Hammer
  R(27, 1, 2, 2, STEEL)
  R(28, 0, 1, 1, STEEL_L)
  -- The box magazine in front of the trigger guard
  R(14, 6, 8, 3, STEEL)
  R(14, 6, 8, 1, STEEL_L)
  R(14, 8, 8, 1, STEEL_D)
  R(14, 6, 1, 3, STEEL_D)
  R(15, 9, 6, 1, INK) -- the floor plate
  -- Trigger guard and trigger
  R(22, 8, 5, 1, STEEL_D)
  R(26, 6, 1, 3, STEEL_D)
  R(23, 6, 1, 2, INK)
  -- The round wooden handle, slanting back
  local grip = { { 26, 30 }, { 27, 31 }, { 27, 31 }, { 28, 32 }, { 28, 32 }, { 29, 33 }, { 29, 33 }, { 29, 33 } }
  for r, g in ipairs(grip) do
    local c = r == #grip and WOOD_D or WOOD
    R(g[1], 5 + r, g[2] - g[1] + 1, 1, c)
    R(g[1], 5 + r, 1, 1, WOOD_L)
    if r % 2 == 0 then
      R(g[1] + 2, 5 + r, 1, 1, WOOD_D) -- the grooves of the handle
    end
  end

  -- A stripper clip of rounds set on top, thumbed down, the empty clip flung away
  if rp and rp > 0.2 and rp < 0.86 then
    local clipX, clipY = 16, -1
    local alpha = 1
    if rp < 0.45 then
      clipY = -1 + 3 * ease((rp - 0.2) / 0.25)
    elseif rp >= 0.6 then
      local t = (rp - 0.6) / 0.26
      clipX, clipY = 16 + 12 * t, 2 - 9 * t + 14 * t * t
      alpha = 1 - t
    else
      clipY = 2
    end
    R(clipX, clipY, 7, 1, STEEL_D, alpha)
    if rp < 0.6 then
      for i = 0, 5 do
        if rp < 0.45 or rp < 0.46 + i * 0.02 then
          R(clipX + i, clipY - 1, 1, 1, BRASS, alpha)
          R(clipX + i, clipY - 2, 1, 1, COPPER, alpha)
        end
      end
    end
  end
end

-- Entry points ----------------------------------------------------------------

local MODELS = {
  revolver = { w = 32, h = 14, shiftX = 2, shiftY = 0 },
  shotgun = { w = 36, h = 15, shiftX = 0, shiftY = -2 },
  automatic = { w = 39, h = 15, shiftX = 0, shiftY = 0 },
  pistol = { w = 34, h = 18, shiftX = 0, shiftY = 0 },
}

-- Whether this gun has a drawn model
function gunhud.supports(gun)
  return MODELS[gun.def.model] ~= nil
end

-- The model's size in cells
function gunhud.size(gun)
  local m = MODELS[gun.def.model]
  return m.w, m.h
end

-- Draws the gun's model with its top-left at (ox, oy), q pixels to the cell,
-- playing the reload when the gun is reloading
function gunhud.drawModel(gun, ox, oy, q, alpha)
  local model = gun.def.model
  local m = MODELS[model]
  local rp = gun.isReloading and gun:isReloading() and gun:reloadProgress() or nil
  ox, oy = ox + m.shiftX * q, oy + m.shiftY * q
  local R = painter(ox, oy, q, alpha or 1)
  if model == "revolver" then
    drawRevolver(R, rp)
  elseif model == "shotgun" then
    drawShotgun(R, rp, ox, oy, q)
  elseif model == "automatic" then
    drawAutomatic(R, rp)
  else
    drawPistol(R, rp)
  end
  love.graphics.setColor(1, 1, 1)
end

return gunhud
