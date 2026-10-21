-- Weapon chests (design doc §9a): iron-banded chests scattered through the
-- catacombs. Standing next to one and pressing E opens it: it holds either gold
-- (80%) or a generated weapon (20%), never both, so the real prize is saved
-- for playing well down to the shop. Deeper chests hold more gold and
-- better-equipped weapons (more pre-fitted slots).
local input = require("src.input")
local audio = require("src.audio")
local effects = require("src.effects")
local guns = require("src.guns")
local meta = require("src.meta")
local pickups = require("src.pickups")

local chests = {}

local list = {}

local REACH = 20 -- how close the hunter must be to open one
local GOLD_CHANCE = 0.8 -- a chest holds gold with this chance, otherwise a weapon
local LOCKED_CHANCE = 0.3 -- and that weapon is a locked kind (src.meta) with this chance
local W, H = 14, 10

function chests.clear()
  list = {}
end

-- x: centre, groundY: the first solid pixel under it. depth: 0 at the top of
-- the cave, 1 at the bottom.
function chests.spawn(x, groundY, depth)
  local c = { x = x, y = groundY, depth = depth or 0, opened = false, open = 0 }
  list[#list + 1] = c
  return c
end

local function distance(c, player)
  local px, py = player:center()
  return math.sqrt((c.x - px) ^ 2 + (c.y - H / 2 - py) ^ 2)
end

-- The nearest unopened chest within reach (a vault's chest stays shut until
-- its door has been unlocked)
function chests.nearest(player)
  local best, bestDist = nil, REACH
  for _, c in ipairs(list) do
    if not c.opened and not c.locked then
      local d = distance(c, player)
      if d < bestDist then
        best, bestDist = c, d
      end
    end
  end
  return best
end

-- E: opens the nearest chest. Returns true if one was opened.
function chests.interact(player)
  local c = chests.nearest(player)
  if not c then
    return false
  end
  c.opened = true
  audio.play("chest")
  if c.vault then
    -- A vault's chest: a fine weapon, something locked, and gold
    local ix = c.x
    pickups.dropWeapon(ix, c.y - H - 2, guns.generate(meta.lockedArchetype(), nil, 0.8), -30, -150)
    pickups.dropItem(ix + 4, c.y - H - 2, meta.lockedItem() or require("src.items").random(), 30, -140)
    pickups.dropGold(ix, c.y - H, math.floor(love.math.random(60, 110) * (1 + c.depth)))
  elseif love.math.random() < GOLD_CHANCE then
    pickups.dropGold(c.x, c.y - H, math.floor(love.math.random(15, 40) * (1 + c.depth)))
  else
    local fit = 0.15 + 0.45 * c.depth
    -- Now and then a gun the Gunsmith doesn't know yet: something to see
    local locked = love.math.random() < LOCKED_CHANCE and meta.lockedArchetype() or nil
    pickups.dropWeapon(c.x, c.y - H - 2, guns.generate(locked, nil, fit), (love.math.random() - 0.5) * 50, -150)
  end
  for _ = 1, 12 do
    effects.particle(c.x + (love.math.random() - 0.5) * 8, c.y - H, (love.math.random() - 0.5) * 70, -40 - love.math.random() * 70, 0.5, { 1, 0.85, 0.4 }, 300, true)
  end
  return true
end

function chests.update(dt)
  for _, c in ipairs(list) do
    if c.opened then
      c.open = math.min(1, c.open + dt * 4)
    end
  end
end

local function onScreen(c, view)
  return c.x > view.x - 16 and c.x < view.x + view.w + 16 and c.y > view.y - 16 and c.y < view.y + view.h + 16
end

local WOOD, WOOD_L, WOOD_D = { 0.36, 0.25, 0.17 }, { 0.47, 0.34, 0.22 }, { 0.22, 0.15, 0.10 }
local IRON, IRON_L, IRON_D = { 0.30, 0.31, 0.37 }, { 0.44, 0.45, 0.52 }, { 0.17, 0.18, 0.22 }
local PLATE, PLATE_L = { 0.62, 0.48, 0.20 }, { 0.80, 0.66, 0.30 }
local INSIDE = { 0.09, 0.06, 0.05 }
local LID_H = { 4, 4, 3, 2, 2 } -- the lid's front face as it tips back (frames 0..4), and how far it has risen
local LID_UP = { 0, 1, 3, 4, 5 }
local OPEN_FRAMES = 4

local function px(c, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3])
  love.graphics.rectangle("fill", x, y, w, h)
end

-- All of it is drawn before the lighting, so it takes the light (and the dark) of where it stands
function chests.draw(view)
  for _, c in ipairs(list) do
    if onScreen(c, view) then
      local x, y = math.floor(c.x - W / 2), math.floor(c.y)
      local frame = math.floor(c.open * OPEN_FRAMES + 0.001)
      -- Body: planks with iron bands and rivets, a pale top edge, dark feet
      local top = y - 6
      px(WOOD, x, top, W, 6)
      px(WOOD_L, x, top, W, 1)
      px(WOOD_D, x + 4, top + 1, 1, 5)
      px(WOOD_D, x + 9, top + 1, 1, 5)
      px(WOOD_D, x, y - 1, W, 1)
      px(IRON_D, x, y - 1, 2, 1)
      px(IRON_D, x + W - 2, y - 1, 2, 1)
      for _, bx in ipairs({ 1, W - 4 }) do
        px(IRON, x + bx, top, 3, 6)
        px(IRON_L, x + bx, top, 1, 6)
        px(IRON_D, x + bx + 2, top, 1, 6)
        px(IRON_D, x + bx + 1, top + 1, 1, 1) -- rivets
        px(IRON_D, x + bx + 1, top + 4, 1, 1)
      end
      if frame > 0 then
        -- The open mouth: the dark inside
        px(INSIDE, x + 1, top - 1, W - 2, 2)
      end
      -- Lid: a rounded cap that tips back and up as it opens (its underside shows once it is up)
      local lh, lift = LID_H[frame + 1], LID_UP[frame + 1]
      local ly = top - lh - lift + 1
      if frame >= 2 then
        px(WOOD_D, x + 2, ly + lh, W - 4, top - 1 - ly - lh) -- (the back of the chest, up to the tipped lid)
      end
      local face, edge = frame >= 3 and WOOD_D or WOOD, frame >= 3 and WOOD or WOOD_L
      px(face, x, ly + 1, W, lh - 1)
      px(face, x + 1, ly, W - 2, 1)
      px(edge, x + 1, ly, W - 2, 1)
      if lh > 2 then
        px(WOOD_D, x, ly + lh - 1, W, 1)
      end
      for _, bx in ipairs({ 1, W - 4 }) do
        px(IRON, x + bx, ly, 3, lh)
        px(IRON_L, x + bx, ly, 1, lh)
        px(IRON_D, x + bx + 2, ly, 1, lh)
      end
      -- The lock plate, on the lid and the body, until the lid comes up
      if frame == 0 then
        px(PLATE, x + 5, top - 2, 4, 4)
        px(PLATE_L, x + 5, top - 2, 4, 1)
        px(PLATE_L, x + 5, top - 1, 1, 3)
        px(INSIDE, x + 6, top - 1, 2, 2)
      end
    end
  end
end

-- After the lighting: the lock of a closed chest gives off a faint warm glow, with a twinkle now and then
function chests.drawEmissive(view)
  local t = love.timer.getTime()
  for _, c in ipairs(list) do
    if not c.opened and onScreen(c, view) then
      local x, y = math.floor(c.x), math.floor(c.y)
      love.graphics.setColor(1, 0.8, 0.35, 0.16 + 0.05 * math.sin(t * 2 + c.x))
      love.graphics.rectangle("fill", x - 2, y - 9, 4, 4)
      if math.sin(t * 3 + c.x) > 0.93 then
        love.graphics.setColor(1, 1, 0.9, 0.7)
        love.graphics.rectangle("fill", x - 1, y - 7, 3, 1)
        love.graphics.rectangle("fill", x, y - 8, 1, 3)
      end
    end
  end
end

-- (a closed chest has a slight glow of its own; an open one gives none)
function chests.addLights(lighting, view)
  for _, c in ipairs(list) do
    if not c.opened and onScreen(c, view) then
      lighting.add(c.x, c.y - 6, 22, 1, 0.75, 0.35, 0.22)
    end
  end
end

-- The "[E] Open chest" prompt (full resolution)
function chests.drawScreen(toScreen, font, player)
  if player.dead then
    return
  end
  local c = chests.nearest(player)
  if not c then
    return
  end
  local sx, sy = toScreen(c.x, c.y - H - 8)
  local text = "[" .. input.label("interact") .. "] Open chest"
  love.graphics.setFont(font)
  local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy - font:getHeight())
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(0.97, 0.98, 1)
  love.graphics.print(text, x, y)
end

return chests
