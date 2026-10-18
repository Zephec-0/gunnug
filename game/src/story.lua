-- Environmental storytelling: little scenes left in the caves that say what
-- happened to the people who came before. Placed by cavegen on the floors
-- (story.generate), drawn behind the hunter like the mine's scenery:
--   fallen   a dead adventurer: a trail of blood dragged to where he gave up,
--            bones, a hat, a pack, his gun and sometimes a purse of coin
--   camp     a cold camp: bedroll, a dead fire with one last ember, a tin cup
--   ritual   a chalk circle with a skull and burning candles
--   sign     a plank with a last message scratched on it (a tiny 3x5 pixel font)
--   cairn    stones stacked to mark the way (or a grave)
local story = {}

local FONT = {
  A = "010101111101101", B = "110101110101110", C = "011100100100011", D = "110101101101110",
  E = "111100110100111", F = "111100110100100", G = "011100101101011", H = "101101111101101",
  I = "111010010010111", J = "001001001101010", K = "101101110101101", L = "100100100100111",
  M = "101111111101101", N = "110101101101101", O = "010101101101010", P = "110101110100100",
  Q = "010101101110011", R = "110101110101101", S = "011100010001110", T = "111010010010010",
  U = "101101101101111", V = "101101101101010", W = "101101111111101", X = "101101010101101",
  Y = "101101010010010", Z = "111001010100111",
  ["0"] = "111101101101111", ["1"] = "010110010010111", ["2"] = "110001010100111", ["3"] = "110001010001110",
  ["4"] = "101101111001001", ["5"] = "111100110001110", ["6"] = "011100111101111", ["7"] = "111001010010010",
  ["8"] = "111101111101111", ["9"] = "111101111001110", ["!"] = "010010010000010", ["."] = "000000000000010",
  ["'"] = "010010000000000", ["-"] = "000000111000000",
}

story.FONT = FONT -- (the town's signs are lettered with it too)

-- What the dead leave behind, in each named area (a sign picks from its own
-- area's list; areas not listed fall back to the tier's)
local AREA_TEXTS = {
  ["The Old Mine"] = { "SHIFT ENDS AT DUSK", "MIND THE PROPS", "NO CANARY LEFT", "PAY OWED TO MARGO", "LANTERN OIL 3 DEEP", "THE PROPS ARE CREAKING", "DIG NORTH", "CLAIM 14 IS DRY" },
  ["The Sunken Hollows"] = { "DONT DRINK", "THE WATER WATCHES", "TOO MANY EYES", "IT FOLLOWS THE GLOW", "DAY 9 STILL DOWN", "MUSHROOMS SING AT NIGHT", "SPORES IN MY LUNGS", "THE CAPS ARE WATCHING" },
  ["The Sulfur Vents"] = { "DONT BREATHE", "SULFUR SOURS THE MIND", "GAS TO THE LEFT", "WE WERE SIX", "NO FLAME PAST HERE", "WET CLOTH OVER THE MOUTH", "HER VOICE IN THE STEAM", "THE QUEEN WAITS" },
  ["The Cinder Warrens"] = { "IT IS HOT", "ASH TO ASH", "BURN IT ALL", "NO WATER LEFT", "THE FLOOR IS GLASS", "EMBERS SEE YOU", "FOLLOW THE COOL AIR", "DEEPER IS HOTTER" },
  ["The Drowned Halls"] = { "TOO DEEP", "THE TIDE REMEMBERS", "WE FLOODED IT", "COLD COLD COLD", "SHE IS BELOW", "COUNT THE ARCHES", "WADE DONT SWIM", "THE CHAINS MOVE" },
  ["The Quarry"] = { "CUT STRAIGHT", "BLASTING AT NOON", "FOREMAN SAYS DIG", "THE STONE IS HOLLOW", "DONT STAND UNDER", "TALLY 9000 BLOCKS", "NO ONE LEAVES" },
  ["The Foreman's Hall"] = { "FOREMAN WAS HERE", "HE NEVER STOPPED", "LAST SHIFT", "THE BELL DOESNT RING", "TURN AROUND", "ORDERS ARE ORDERS" },
  ["The Flooded Caverns"] = { "BREATHE WHILE YOU CAN", "THE DEEP IS HUNGRY", "TEETH IN THE DARK", "GLOWING THINGS BITE", "NEED A HELM", "DONT GO SWIMMING", "SOMETHING LARGE" },
  ["The Needle"] = { "THE WAY UP", "KEEP CLIMBING", "WIND AT THE TOP", "DONT LOOK DOWN", "SO CLOSE TO THE SKY", "ONLY WINGS NOW", "MIND THE LEDGES" },
  ["The Ember Foundry"] = { "MELT IT DOWN", "THE FURNACE LIVES", "SLAG RUNS DEEP", "FIRE FEEDS HERE", "DAY 3 IN THE HEAT", "DONT TOUCH THE MOLD" },
  ["The Silt Vaults"] = { "SILT TO THE KNEES", "THE VAULTS SINK", "FROGS KNOW THE WAY", "ROT BELOW", "NOTHING DRIES HERE", "THE MUD REMEMBERS" },
}

-- What the dead leave behind, per area
local TEXTS = {
  { "TURN BACK", "THEY HEAR THE LIGHT", "DAY 41", "NO WAY OUT", "DONT TRUST THE LAMPS", "I WAS HERE" },
  { "DONT DRINK", "THE WATER WATCHES", "TOO MANY EYES", "IT FOLLOWS THE GLOW", "DAY 9 STILL DOWN" },
  { "DONT BREATHE", "SULFUR SOURS THE MIND", "GAS TO THE LEFT", "WE WERE SIX", "TURN BACK" },
  { "IT IS HOT", "ASH TO ASH", "BURN IT ALL", "THE QUEEN WAITS", "NO WATER LEFT" },
  { "TOO DEEP", "THE TIDE REMEMBERS", "WE FLOODED IT", "COLD COLD COLD", "SHE IS BELOW" },
}

local R = function(c, x, y, w, h, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", x, y, w, h)
end

local WOOD, WOOD_L, WOOD_D = { 0.45, 0.30, 0.16 }, { 0.62, 0.43, 0.22 }, { 0.28, 0.19, 0.10 }
local BONE, BONE_D = { 0.80, 0.77, 0.66 }, { 0.52, 0.49, 0.42 }
local STONE, STONE_L, STONE_D = { 0.40, 0.40, 0.44 }, { 0.58, 0.58, 0.62 }, { 0.24, 0.24, 0.28 }
local BLOOD = { 0.36, 0.04, 0.06 }

-- Generation -------------------------------------------------------------------

local KINDS = { "fallen", "sign", "camp", "fallen", "cairn", "sign", "ritual", "fallen", "camp", "sign", "fallen", "cairn" }

-- spots: floor spots { x, y } from cavegen; level: the area number; rng: its random generator
function story.generate(world, spots, level, rng, areaName)
  local items = {}
  local texts = AREA_TEXTS[areaName or ""] or TEXTS[math.min(level, #TEXTS)] or TEXTS[1]
  for i, s in ipairs(spots) do
    local kind = KINDS[(i + rng:random(0, 3)) % #KINDS + 1]
    local item = { kind = kind, x = s[1], y = s[2], flip = rng:random() < 0.5, seed = rng:random(1, 9999) }
    if kind == "sign" then
      item.text = texts[rng:random(1, #texts)]
    elseif kind == "fallen" then
      -- The way he dragged himself in: ground heights along the trail
      local dir = item.flip and -1 or 1
      item.trail = {}
      for dx = 0, 30 do
        local gx = item.x - dir * dx
        item.trail[dx] = world:findGround(gx, item.y - 12)
      end
      item.loot = rng:random() < 0.55 and rng:random(12, 20 + level * 14) or nil
      item.skeleton = rng:random(1, 2)
    end
    items[#items + 1] = item
  end
  return items
end

-- Sign images ---------------------------------------------------------------------

local signImages = {}

local function signImage(text)
  local img = signImages[text]
  if img then
    return img
  end
  local w = #text * 4 + 3
  local data = love.image.newImageData(w, 9)
  for y = 0, 8 do
    for x = 0, w - 1 do
      local edge = (x == 0 or x == w - 1 or y == 0 or y == 8)
      local shade = ((x * 7 + y * 13) % 5) * 0.012
      if edge then
        data:setPixel(x, y, WOOD_D[1], WOOD_D[2], WOOD_D[3], 1)
      else
        data:setPixel(x, y, WOOD[1] + shade, WOOD[2] + shade, WOOD[3] + shade, 1)
      end
    end
  end
  for i = 1, #text do
    local g = FONT[text:sub(i, i)]
    if g then
      for k = 0, 14 do
        if g:sub(k + 1, k + 1) == "1" then
          local gx, gy = k % 3, math.floor(k / 3)
          data:setPixel(2 + (i - 1) * 4 + gx, 2 + gy, 0.13, 0.08, 0.05, 1)
        end
      end
    end
  end
  img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  signImages[text] = img
  return img
end

-- Drawing -----------------------------------------------------------------------------

local function inView(view, it, margin)
  return it.x > view.x - margin and it.x < view.x + view.w + margin and it.y > view.y - margin and it.y < view.y + view.h + margin
end

local function drawFallen(it)
  local dir = it.flip and -1 or 1
  -- The drag trail: dark smears hugging the floor, thinning out
  for dx = 0, 30 do
    local gy = it.trail[dx]
    if gy and gy - it.y < 14 and gy - it.y > -14 then
      local a = (1 - dx / 31) * 0.9
      if (dx * 7 + it.seed) % 5 ~= 0 then
        R(BLOOD, it.x - dir * dx, gy - 1, 1, 1, a)
      end
      if (dx * 3 + it.seed) % 9 == 0 then
        R(BLOOD, it.x - dir * dx, gy - 2, 1, 1, a * 0.7)
      end
    end
  end
  love.graphics.push()
  love.graphics.translate(it.x, it.y)
  love.graphics.scale(it.flip and -1 or 1, 1)
  -- bones
  local function r(c, dx, dy, w, h)
    R(c, dx, dy, w, h)
  end
  if it.skeleton == 1 then
    r(BONE, 0, -3, 4, 3)
    r({ 0.08, 0.07, 0.09 }, 1, -2, 1, 1)
    r({ 0.08, 0.07, 0.09 }, 3, -2, 1, 1)
    r(BONE_D, 4, -2, 9, 1)
    for k = 0, 2 do
      r(BONE, 5 + k * 2, -4, 1, 3)
    end
    r(BONE, 12, -3, 3, 2)
    r(BONE, 15, -3, 4, 1)
    r(BONE, 15, -1, 5, 1)
  else
    r(BONE, 1, -9, 4, 4)
    r({ 0.08, 0.07, 0.09 }, 3, -8, 1, 1)
    r(BONE_D, 2, -5, 1, 5)
    r(BONE, 0, -4, 5, 2)
    r(BONE, 5, -4, 6, 1)
    r(BONE_D, 5, -2, 5, 1)
  end
  -- A hat that rolled away, the remains of a coat, a pack and his gun
  r({ 0.30, 0.2, 0.12 }, -7, -2, 6, 1)
  r({ 0.30, 0.2, 0.12 }, -6, -4, 4, 2)
  r({ 0.22, 0.25, 0.4 }, 3, -1, 10, 1) -- torn coat
  r({ 0.18, 0.2, 0.34 }, 6, -2, 4, 1)
  r({ 0.45, 0.32, 0.18 }, 20, -5, 6, 5)
  r({ 0.3, 0.2, 0.1 }, 20, -5, 6, 1)
  r({ 0.6, 0.45, 0.2 }, 22, -3, 2, 1)
  r({ 0.5, 0.5, 0.56 }, -12, -2, 5, 1) -- the gun
  r({ 0.35, 0.22, 0.12 }, -9, -1, 2, 1)
  love.graphics.pop()
end

local function drawCamp(it)
  love.graphics.push()
  love.graphics.translate(it.x, it.y)
  love.graphics.scale(it.flip and -1 or 1, 1)
  -- bedroll, with a pillow and a stripe
  R({ 0.34, 0.2, 0.18 }, -16, -3, 13, 3)
  R({ 0.48, 0.3, 0.26 }, -16, -3, 13, 1)
  R({ 0.72, 0.66, 0.55 }, -17, -4, 3, 2)
  R({ 0.22, 0.12, 0.12 }, -10, -2, 1, 2)
  -- fire pit: a ring of stones round dead logs and ash
  for _, dx in ipairs({ 3, 5, 7, 9, 11, 13 }) do
    R(STONE, dx, -2 + (dx % 4 == 1 and 1 or 0), 2, 2)
    R(STONE_L, dx, -2 + (dx % 4 == 1 and 1 or 0), 1, 1)
  end
  R({ 0.1, 0.09, 0.09 }, 5, -1, 7, 1)
  R({ 0.18, 0.13, 0.1 }, 6, -3, 6, 1)
  R({ 0.14, 0.1, 0.08 }, 8, -4, 1, 2)
  -- tin cup, pack, an unlit lantern
  R({ 0.55, 0.57, 0.62 }, 17, -3, 2, 3)
  R({ 0.4, 0.42, 0.46 }, 19, -2, 1, 1)
  R({ 0.4, 0.3, 0.18 }, -26, -5, 7, 5)
  R({ 0.26, 0.19, 0.1 }, -26, -5, 7, 1)
  R({ 0.5, 0.5, 0.56 }, 22, -6, 3, 1)
  R({ 0.16, 0.16, 0.2 }, 22, -5, 3, 5)
  R({ 0.5, 0.5, 0.56 }, 22, -1, 3, 1)
  love.graphics.pop()
end

local function drawRitual(it)
  love.graphics.push()
  love.graphics.translate(it.x, it.y)
  -- a chalk circle, flattened to the floor
  for i = 0, 27 do
    local a = i / 28 * math.pi * 2
    R({ 0.85, 0.85, 0.8 }, math.floor(math.cos(a) * 14), math.floor(math.sin(a) * 2.5) - 1, 1, 1, 0.5)
  end
  -- the skull in the middle
  R(BONE, -2, -4, 4, 3)
  R({ 0.08, 0.07, 0.09 }, -1, -3, 1, 1)
  R({ 0.08, 0.07, 0.09 }, 1, -3, 1, 1)
  -- candles round it
  for i = 0, 4 do
    local a = (i / 5) * math.pi * 2 + it.seed
    local cx, cy = math.floor(math.cos(a) * 12), math.floor(math.sin(a) * 2)
    R({ 0.85, 0.82, 0.7 }, cx, cy - 4, 1, 3)
    R({ 0.6, 0.55, 0.45 }, cx, cy - 1, 1, 1)
  end
  love.graphics.pop()
end

local function drawSign(it)
  local img = signImage(it.text)
  local w = img:getWidth()
  local x = it.x - math.floor(w / 2)
  R(WOOD_D, it.x - 1, it.y - 12, 2, 12)
  R(WOOD, it.x - 1, it.y - 12, 1, 12)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(img, x, it.y - 20 + (it.seed % 2))
end

local function drawCairn(it)
  love.graphics.push()
  love.graphics.translate(it.x, it.y)
  R(STONE_D, -5, -2, 11, 2)
  R(STONE, -5, -2, 10, 1)
  R(STONE_D, -4, -4, 8, 2)
  R(STONE_L, -4, -4, 5, 1)
  R(STONE, -3, -6, 6, 2)
  R(STONE_L, -3, -6, 3, 1)
  R(STONE_D, -2, -8, 4, 2)
  R(STONE, -2, -8, 3, 1)
  if it.seed % 3 == 0 then
    R({ 0.30, 0.2, 0.12 }, -3, -9, 6, 1) -- a hat on top: a grave
    R({ 0.30, 0.2, 0.12 }, -2, -11, 4, 2)
  end
  love.graphics.pop()
end

function story.draw(items, view)
  for _, it in ipairs(items) do
    if inView(view, it, 40) then
      if it.kind == "fallen" then
        drawFallen(it)
      elseif it.kind == "camp" then
        drawCamp(it)
      elseif it.kind == "ritual" then
        drawRitual(it)
      elseif it.kind == "sign" then
        drawSign(it)
      elseif it.kind == "cairn" then
        drawCairn(it)
      end
    end
  end
end

-- Flames and embers, after the lighting
function story.drawEmissive(items, view)
  local t = love.timer.getTime()
  for _, it in ipairs(items) do
    if inView(view, it, 30) then
      if it.kind == "camp" then
        -- One last ember in the ashes
        local f = it.flip and -1 or 1
        local pulse = 0.5 + 0.5 * math.sin(t * 1.3 + it.seed)
        love.graphics.setColor(1, 0.3, 0.1, 0.35 + 0.5 * pulse)
        love.graphics.rectangle("fill", it.x + f * 8 - (it.flip and 1 or 0), it.y - 2, 1, 1)
      elseif it.kind == "ritual" then
        for i = 0, 4 do
          local a = (i / 5) * math.pi * 2 + it.seed
          local cx, cy = math.floor(math.cos(a) * 12), math.floor(math.sin(a) * 2)
          local fl = 0.7 + 0.3 * math.sin(t * 11 + i * 2.1 + it.seed)
          love.graphics.setColor(1, 0.75, 0.3, fl)
          love.graphics.rectangle("fill", it.x + cx, it.y + cy - 6, 1, 2)
          love.graphics.setColor(1, 0.95, 0.7, fl)
          love.graphics.rectangle("fill", it.x + cx, it.y + cy - 5, 1, 1)
        end
      end
    end
  end
end

function story.addLights(lighting, items, view)
  local t = love.timer.getTime()
  for _, it in ipairs(items) do
    if inView(view, it, 100) then
      if it.kind == "ritual" then
        for i = 0, 4 do
          local a = (i / 5) * math.pi * 2 + it.seed
          lighting.add(it.x + math.floor(math.cos(a) * 12), it.y - 6, 30, 1, 0.68, 0.3, 0.55 + math.sin(t * 9 + i) * 0.06)
        end
      elseif it.kind == "camp" then
        lighting.add(it.x + (it.flip and -8 or 8), it.y - 2, 20, 1, 0.35, 0.12, 0.3)
      end
    end
  end
end

return story
