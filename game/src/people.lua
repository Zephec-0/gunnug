-- The look of the camp's newer people (design doc §11a-iv): one parametric
-- little figure (about 20 px tall, like the hunter), dressed per person, and
-- each person's camp stall. src.npcs asks for them by id: people.draw for a
-- figure (also used inside cages), people.drawStall for the stall at camp.
local people = {}

local function R(c, x, y, w, h, a)
  love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1))
  love.graphics.rectangle("fill", x, y, w, h)
end

local EYE = { 0.08, 0.07, 0.08 }
local BOOT = { 0.14, 0.11, 0.09 }
local WOOD, WOOD_L, WOOD_D = { 0.45, 0.30, 0.16 }, { 0.60, 0.42, 0.22 }, { 0.28, 0.19, 0.10 }
local IRON, IRON_D, IRON_L = { 0.34, 0.34, 0.38 }, { 0.18, 0.18, 0.21 }, { 0.55, 0.56, 0.6 }
local BRASS = { 0.82, 0.64, 0.28 }
local CANVAS, CANVAS_D = { 0.55, 0.48, 0.36 }, { 0.40, 0.34, 0.25 }

-- Per person: skin, shirt (and its dark side), vest or apron over it, trousers,
-- a hat style ("hood", "cap", "bowler"), its colour, a face (beard or
-- moustache) colour and style, and a prop in the front hand
local LOOKS = {
  apothecary = {
    skin = { 0.86, 0.68, 0.55 },
    shirt = { 0.30, 0.46, 0.34 }, shirtD = { 0.20, 0.32, 0.24 },
    vest = { 0.62, 0.55, 0.40 }, trouser = { 0.26, 0.22, 0.20 },
    hat = "hood", hatCol = { 0.24, 0.40, 0.30 },
    face = nil, prop = "flask", coat = true,
  },
  cartographer = {
    skin = { 0.80, 0.62, 0.48 },
    shirt = { 0.52, 0.38, 0.24 }, shirtD = { 0.38, 0.27, 0.16 },
    vest = { 0.68, 0.60, 0.44 }, trouser = { 0.30, 0.30, 0.34 },
    hat = "cap", hatCol = { 0.36, 0.26, 0.16 },
    face = { 0.40, 0.30, 0.22 }, faceStyle = "stubble", prop = "scroll", goggles = true,
  },
  sawbone = {
    skin = { 0.78, 0.74, 0.66 },
    shirt = { 0.62, 0.74, 0.72 }, shirtD = { 0.44, 0.56, 0.55 },
    vest = { 0.90, 0.88, 0.84 }, trouser = { 0.28, 0.30, 0.32 },
    hat = "hood", hatCol = { 0.66, 0.78, 0.76 },
    face = { 0.55, 0.52, 0.50 }, faceStyle = "stubble", prop = "saw", goggles = true, coat = true,
  },
  bartender = {
    skin = { 0.84, 0.64, 0.52 },
    shirt = { 0.88, 0.86, 0.80 }, shirtD = { 0.70, 0.68, 0.62 },
    vest = { 0.40, 0.14, 0.16 }, trouser = { 0.16, 0.16, 0.20 },
    hat = "bowler", hatCol = { 0.20, 0.17, 0.17 },
    face = { 0.22, 0.14, 0.10 }, faceStyle = "moustache", prop = "mug",
  },
  -- the random events' people (src.randevents)
  carny = {
    skin = { 0.84, 0.64, 0.52 },
    shirt = { 0.90, 0.88, 0.80 }, shirtD = { 0.72, 0.70, 0.62 },
    vest = { 0.78, 0.14, 0.16 }, trouser = { 0.22, 0.18, 0.30 },
    hat = "bowler", hatCol = { 0.80, 0.16, 0.18 },
    face = { 0.18, 0.12, 0.10 }, faceStyle = "moustache",
  },
  dealer = {
    skin = { 0.80, 0.66, 0.54 },
    shirt = { 0.86, 0.86, 0.82 }, shirtD = { 0.66, 0.66, 0.62 },
    vest = { 0.12, 0.32, 0.20 }, trouser = { 0.14, 0.14, 0.18 },
    hat = "cap", hatCol = { 0.10, 0.36, 0.22 },
    face = nil,
  },
  tinker = {
    skin = { 0.82, 0.62, 0.48 },
    shirt = { 0.52, 0.38, 0.24 }, shirtD = { 0.36, 0.26, 0.16 },
    vest = { 0.58, 0.46, 0.28 }, trouser = { 0.30, 0.26, 0.22 },
    hat = "hood", hatCol = { 0.42, 0.30, 0.16 },
    face = { 0.50, 0.40, 0.30 }, faceStyle = "stubble", goggles = true, coat = true,
  },
}

function people.has(id)
  return LOOKS[id] ~= nil
end

-- A figure with feet at (x, g), facing +1 or -1. pose: "stand", "work" (the front hand busy),
-- "walk" (legs swing) or "drink" (crouched, scooping water to the mouth); k: 0..1 through a cycle.
-- alpha fades it.
function people.draw(id, x, g, facing, pose, k, alpha)
  local L = LOOKS[id]
  if not L then
    return
  end
  love.graphics.push()
  love.graphics.translate(x, g)
  love.graphics.scale(facing, 1)
  local a = alpha or 1
  local function r(c, dx, dy, w, h)
    R(c, dx, dy, w, h, a)
  end
  local drink = pose == "drink"
  local stride = pose == "walk" and math.floor((k or 0) * 4) % 2 or 0
  if drink then
    -- crouched at the water's edge: knees up, the whole body lower and a little forward
    r(BOOT, -3, -2, 3, 2)
    r(BOOT, 2, -2, 3, 2)
    r(L.trouser, -3, -5, 2, 3)
    r(L.trouser, 3, -5, 2, 3)
    r(L.trouser, -3, -6, 7, 2)
    love.graphics.translate(2, 3)
  else
    r(BOOT, -3 + stride, -2, 3, 2)
    r(BOOT, 1 - stride, -2, 3, 2)
    r(L.trouser, -3 + stride, -7, 2, 5)
    r(L.trouser, 1 - stride, -7, 2, 5)
  end
  -- a long coat reaches down over the trousers
  if L.coat and not drink then
    r(L.shirt, -4, -8, 8, 6)
    r(L.shirtD, -4, -8, 1, 6)
  end
  r(L.shirtD, -4, -14, 1, 5)
  r(L.shirt, -3, -14, 6, 7)
  r(L.vest, -2, -13, 4, 6)
  r(L.shirtD, 0, -13, 1, 6) -- the front opening
  -- front arm and what it holds
  local bob = (pose == "work") and math.floor(math.sin(k * math.pi * 2) + 0.5) or 0
  r(L.shirt, 3, -13, 1, 3)
  if drink then
    -- a cupped hand dips down to the water and comes up to the mouth
    local lift = math.max(0, math.sin((k or 0) * math.pi * 2))
    local hy = -8 - math.floor(lift * 7 + 0.5)
    r(L.shirt, 3, -13, 1, math.max(1, hy + 15))
    r(L.skin, 3, hy, 3, 2)
    if lift > 0.4 then
      r({ 0.55, 0.78, 0.95 }, 4, hy - 1, 1, 1) -- (water running off it)
    end
  else
    r(L.skin, 3, -10 + bob, 2, 1)
  end
  if drink then
    -- (no mug: his hands are full of water)
  elseif L.prop == "flask" then
    r({ 0.60, 0.95, 0.70 }, 5, -12 + bob, 2, 3)
    r({ 0.85, 0.90, 0.85 }, 5, -13 + bob, 2, 1)
  elseif L.prop == "scroll" then
    r({ 0.86, 0.78, 0.58 }, 4, -14 + bob, 2, 7)
    r({ 0.52, 0.40, 0.26 }, 4, -14 + bob, 2, 1)
    r({ 0.52, 0.40, 0.26 }, 4, -8 + bob, 2, 1)
  elseif L.prop == "saw" then
    r(IRON_L, 5, -15 + bob, 1, 7)
    r(IRON_D, 6, -15 + bob, 1, 7)
    r({ 0.45, 0.22, 0.20 }, 5, -9 + bob, 2, 2)
  elseif L.prop == "mug" then
    r({ 0.78, 0.76, 0.70 }, 5, -12 + bob, 2, 3)
    r({ 0.95, 0.80, 0.40 }, 5, -12 + bob, 2, 1)
  end
  -- head
  r(L.skin, -2, -19, 5, 5)
  r(L.skin, 3, -17, 1, 1)
  r(EYE, 1, -17, 1, 1)
  if L.face and L.faceStyle == "moustache" then
    r(L.face, -1, -16, 5, 1)
    r(L.face, -2, -17, 1, 1)
    r(L.face, 4, -17, 1, 1)
  elseif L.face then
    r(L.face, -1, -15, 4, 1)
  end
  if L.goggles then
    r({ 0.55, 0.85, 0.9 }, 1, -18, 2, 2)
    r(BRASS, -1, -19, 4, 1)
  end
  -- hats
  if L.hat == "hood" then
    r(L.hatCol, -3, -21, 7, 3)
    r(L.hatCol, -3, -18, 1, 4)
    r(L.hatCol, 3, -18, 1, 2)
    r({ L.hatCol[1] * 0.7, L.hatCol[2] * 0.7, L.hatCol[3] * 0.7 }, -3, -21, 7, 1)
  elseif L.hat == "cap" then
    r(L.hatCol, -2, -21, 6, 2)
    r(L.hatCol, 3, -20, 3, 1)
    r({ 0.85, 0.80, 0.60 }, -2, -23, 1, 3) -- a feather
  elseif L.hat == "bowler" then
    r(L.hatCol, -2, -22, 5, 3)
    r(L.hatCol, -3, -19, 7, 1)
    r({ 0.50, 0.12, 0.12 }, -2, -20, 5, 1)
  end
  love.graphics.pop()
end

-- Stalls --------------------------------------------------------------------------------

-- Apothecary: a canvas-covered table of bottles in every colour, a small
-- cauldron with a green glow, bundles of herbs drying from a pole
local function apothecaryStall(s)
  local x, g = s.x, s.y
  if not s.bare then
    R(WOOD_D, x - 22, g - 26, 2, 26)
    R(WOOD_D, x + 20, g - 26, 2, 26)
    R(WOOD_D, x - 23, g - 27, 46, 1)
  end
  -- drying herbs
  for i = 0, 5 do
    local hx = x - 18 + i * 7
    R({ 0.30, 0.22, 0.12 }, hx, g - 26, 1, 3)
    R({ 0.32 + (i % 2) * 0.2, 0.52, 0.28 }, hx - 1, g - 23, 3, 5)
  end
  -- the table and its bottles
  R(WOOD_L, x - 20, g - 10, 24, 2)
  R(WOOD_D, x - 19, g - 8, 2, 8)
  R(WOOD_D, x + 1, g - 8, 2, 8)
  local cols = { { 0.80, 0.30, 0.35 }, { 0.35, 0.60, 0.90 }, { 0.90, 0.80, 0.35 }, { 0.55, 0.85, 0.50 }, { 0.75, 0.45, 0.90 } }
  for i = 0, 4 do
    local c = cols[i + 1]
    R({ c[1] * 0.6, c[2] * 0.6, c[3] * 0.6 }, x - 17 + i * 4, g - 15 - (i % 2), 3, 5 + (i % 2))
    R(c, x - 16 + i * 4, g - 14 - (i % 2), 1, 3)
    R(WOOD, x - 17 + i * 4, g - 16 - (i % 2), 3, 1)
  end
  -- the cauldron on three stones
  R(IRON_D, x + 9, g - 9, 10, 8)
  R(IRON, x + 9, g - 9, 10, 1)
  R(IRON_D, x + 8, g - 10, 12, 1)
  R({ 0.35, 0.80, 0.40 }, x + 10, g - 9, 8, 1)
  R(IRON_D, x + 9, g - 1, 2, 1)
  R(IRON_D, x + 17, g - 1, 2, 1)
  people.draw("apothecary", x + 25, g, s.near and (s.facing or 1) or -1, s.near and "stand" or "work", s.hammer)
end

-- Cartographer: a slanted drafting table under a lean-to with a big map
-- pinned up, a brass compass, rolled maps in a barrel
local function cartographerStall(s)
  local x, g = s.x, s.y
  if not s.bare then
    R(WOOD_D, x - 21, g - 24, 2, 24)
    R(WOOD_D, x + 19, g - 24, 2, 24)
  end
  -- the pinned map: a big sheet with a coastline and dotted route
  R({ 0.84, 0.76, 0.56 }, x - 18, g - 25, 22, 15)
  R({ 0.60, 0.48, 0.30 }, x - 18, g - 25, 22, 1)
  R({ 0.60, 0.48, 0.30 }, x - 18, g - 11, 22, 1)
  R({ 0.50, 0.62, 0.62 }, x - 16, g - 23, 8, 6)
  R({ 0.50, 0.62, 0.62 }, x - 10, g - 18, 6, 4)
  for i = 0, 5 do
    R({ 0.62, 0.20, 0.16 }, x - 7 + i * 3, g - 22 + (i % 2) * 2, 1, 1)
  end
  R({ 0.62, 0.20, 0.16 }, x - 1, g - 17, 3, 3)
  -- the table, a compass, a barrel of rolled maps
  R(WOOD_L, x - 20, g - 10, 24, 2)
  R(WOOD_D, x - 19, g - 8, 2, 8)
  R(WOOD_D, x + 1, g - 8, 2, 8)
  R(BRASS, x - 14, g - 12, 3, 2)
  R({ 0.95, 0.95, 0.9 }, x - 13, g - 12, 1, 1)
  R({ 0.86, 0.78, 0.58 }, x - 8, g - 12, 5, 2)
  R(WOOD, x + 10, g - 9, 8, 9)
  R(WOOD_D, x + 10, g - 6, 8, 1)
  for i = 0, 2 do
    R({ 0.86, 0.78, 0.58 }, x + 11 + i * 2, g - 13, 1, 4)
  end
  people.draw("cartographer", x + 24, g, s.near and (s.facing or 1) or -1, s.near and "stand" or "work", s.hammer)
end

-- Bartender: a bar of planks and barrels, a row of bottles on a shelf and
-- mugs along the counter, a lantern, and the bartender polishing a glass
local function bartenderStall(s)
  local x, g = s.x, s.y
  -- the back shelf
  if not s.bare then
    R(WOOD_D, x - 20, g - 26, 2, 26)
    R(WOOD_D, x + 18, g - 26, 2, 26)
  end
  R(WOOD, x - 20, g - 22, 40, 1)
  R(WOOD, x - 20, g - 16, 40, 1)
  local cols = { { 0.55, 0.25, 0.15 }, { 0.25, 0.50, 0.30 }, { 0.65, 0.55, 0.20 }, { 0.45, 0.30, 0.50 } }
  for i = 0, 7 do
    local c = cols[i % 4 + 1]
    R(c, x - 18 + i * 5, g - 26, 2, 4)
    R({ 0.9, 0.85, 0.7 }, x - 18 + i * 5, g - 27, 2, 1)
    if i % 2 == 0 then
      R(c, x - 17 + i * 5, g - 20, 2, 4)
    end
  end
  -- the counter
  R(WOOD_D, x - 22, g - 10, 44, 10)
  R(WOOD, x - 22, g - 11, 44, 2)
  R(WOOD_L, x - 22, g - 11, 44, 1)
  for i = 0, 2 do
    R(WOOD, x - 20 + i * 15, g - 9, 12, 8)
    R(WOOD_D, x - 20 + i * 15, g - 6, 12, 1)
  end
  for i = 0, 2 do
    R({ 0.78, 0.76, 0.70 }, x - 15 + i * 8, g - 14, 2, 3)
    R({ 0.95, 0.80, 0.40 }, x - 15 + i * 8, g - 14, 2, 1)
  end
  -- a cask on the end, a hanging lantern
  R(WOOD, x + 22, g - 9, 8, 9)
  R(IRON_D, x + 22, g - 7, 8, 1)
  R(IRON_D, x + 22, g - 3, 8, 1)
  R(IRON_D, x + 12, g - 24, 1, 3)
  R(IRON_D, x + 11, g - 21, 3, 4)
  people.draw("bartender", x - 4, g - 11 + 11, s.near and (s.facing or 1) or 1, s.near and "stand" or "work", s.hammer)
end

-- The saloon's house rules switched on fly as pennants from poles above the
-- stall, each with a small icon for its debuff (drawn after the lighting so
-- they read in the dark)
local RULE_FLAGS = {
  rotgut = { dx = -13, color = { 0.45, 0.85, 0.25 }, icon = "heart" },
  powderkeg = { dx = 0, color = { 0.95, 0.35, 0.15 }, icon = "burst" },
  lean = { dx = 13, color = { 0.95, 0.78, 0.2 }, icon = "coin" },
}
local FLAG_ICONS = {
  heart = { "01010", "11111", "11111", "01110", "00100" },
  burst = { "10101", "01110", "11111", "01110", "10101" },
  coin = { "01110", "11011", "10001", "11011", "01110" },
}

function people.drawStallGlow(s, t)
  if s.id ~= "bartender" then
    return
  end
  local meta = require("src.meta")
  local x, g = s.x, s.y
  for rule, def in pairs(RULE_FLAGS) do
    if meta.ruleOn(rule) then
      local px, top = x + def.dx, g - 46
      R({ 0.25, 0.2, 0.15 }, px, top, 1, 20) -- the pole
      R({ 0.9, 0.8, 0.4 }, px - 1, top - 1, 3, 1)
      local c = def.color
      for col = 0, 9 do
        local wave = math.floor(math.sin(t * 4 + col * 0.6 + px) * 1.2 + 0.5)
        local h = 9 - math.floor(col * 0.5)
        R({ c[1] * 0.55, c[2] * 0.55, c[3] * 0.55 }, px + 1 + col, top + wave, 1, h)
        R(c, px + 1 + col, top + wave + 1, 1, h - 2)
      end
      local icon = FLAG_ICONS[def.icon]
      for row = 1, 5 do
        for col = 1, 5 do
          if icon[row]:sub(col, col) == "1" then
            R({ 1, 1, 1 }, px + 2 + col, top + 1 + row + math.floor(math.sin(t * 4 + (col + 2) * 0.6 + px) * 1.2 + 0.5), 1, 1, 0.92)
          end
        end
      end
    end
  end
end

-- (the flags give off no light: they only need to be seen)
function people.addStallLights(s, lighting) end

-- Sawbone: a cot with a stained sheet, a bone saw on a hook, jars of things,
-- a lamp, and him with his saw
local function sawboneStall(s)
  local x, g = s.x, s.y
  if not s.bare then
    R(WOOD_D, x - 22, g - 26, 2, 26)
    R(WOOD_D, x + 20, g - 26, 2, 26)
    R(WOOD_D, x - 23, g - 27, 46, 1)
  end
  -- the saw and tools hanging from the beam
  R(IRON_D, x - 16, g - 26, 1, 3)
  R(IRON_L, x - 17, g - 23, 3, 9)
  R(IRON_D, x - 17, g - 14, 3, 1)
  R(IRON_D, x - 10, g - 26, 1, 2)
  R(IRON_L, x - 12, g - 24, 5, 1)
  R(IRON_D, x - 12, g - 23, 1, 3)
  R(IRON_D, x - 8, g - 23, 1, 3)
  -- the cot
  R(WOOD_D, x - 14, g - 6, 2, 6)
  R(WOOD_D, x + 12, g - 6, 2, 6)
  R({ 0.82, 0.80, 0.74 }, x - 15, g - 9, 30, 3)
  R({ 0.62, 0.60, 0.56 }, x - 15, g - 7, 30, 1)
  R({ 0.55, 0.14, 0.12 }, x - 5, g - 9, 6, 3)
  R({ 0.70, 0.68, 0.62 }, x - 15, g - 11, 6, 2)
  -- jars on a shelf
  R(WOOD_D, x + 4, g - 20, 14, 1)
  for i = 0, 2 do
    R({ 0.72, 0.84, 0.80 }, x + 5 + i * 4, g - 24, 3, 4)
    R({ 0.80, 0.50, 0.50 }, x + 5 + i * 4, g - 22, 3, 2)
  end
  people.draw("sawbone", x + 24, g, s.near and (s.facing or 1) or -1, s.near and "stand" or "work", s.hammer)
end

local STALLS = { apothecary = apothecaryStall, cartographer = cartographerStall, bartender = bartenderStall, sawbone = sawboneStall }

function people.drawStall(s)
  local f = STALLS[s.id]
  if f then
    f(s)
    return true
  end
  return false
end

-- Where each stall's lantern/glow is (for lights and the emissive pass): {dx, dy}
local GLOW = { apothecary = { 14, -6, { 0.45, 1, 0.5 } }, cartographer = { -6, -18, { 1, 0.75, 0.4 } }, bartender = { 12, -20, { 0.4, 0.65, 1 } } }

function people.glow(id)
  return GLOW[id]
end

return people
