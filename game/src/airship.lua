-- The airship: a secret, moored in the middle of nothing over the desert, well above anything the hunter can
-- jump to. Only a good gun gets him up to it (recoil jumps, one shot after another). Nothing points to it. On
-- its deck, in the cabin, stands a chest that holds a special unlock (the Skybound perk, once; after that a
-- purse and two fine items).
local materials = require("src.materials")
local config = require("src.config")

local airship = {}

airship.X, airship.DECK = 2300, -90 -- the middle of the deck, and the top of its planks (the desert's ground is about 510)

local WOOD = materials.HARDWOOD
local HALF = 70 -- half the deck's length

function airship.build(world)
  local X, D = airship.X, airship.DECK
  -- The deck: planks, and a hull under them narrowing to a keel
  world:fillRect(X - HALF, D, X + HALF, D + 3, WOOD)
  for i = 0, 22 do
    local half = math.floor(HALF - i * 2.7)
    world:fillRect(X - half, D + 4 + i, X + half, D + 4 + i, WOOD)
  end
  -- A rail post at each end, the mast, and the cabin at the stern: a roof, a back wall, and a front wall with a door
  world:fillRect(X - HALF, D - 10, X - HALF, D - 1, WOOD)
  world:fillRect(X + HALF - 1, D - 10, X + HALF - 1, D - 1, WOOD)
  world:fillRect(X - 12, D - 64, X - 10, D - 1, WOOD)
  world:fillRect(X + 28, D - 29, X + HALF, D - 26, WOOD)
  world:fillRect(X + HALF - 3, D - 25, X + HALF - 1, D - 1, WOOD)
  world:fillRect(X + 28, D - 25, X + 30, D - 21, WOOD) -- (the door: a gap down to the deck, 20 px tall)
  world:repaintRect(X - HALF - 4, D - 70, X + HALF + 4, D + 32)
end

-- Where the chest sits (on the deck, inside the cabin)
function airship.chestSpot()
  return airship.X + 52, airship.DECK
end

-- What the chest holds
function airship.openChest(c)
  local meta = require("src.meta")
  local pickups = require("src.pickups")
  local effects = require("src.effects")
  local audio = require("src.audio")
  audio.play("buy")
  if not meta.perkUnlocked("skybound") then
    meta.unlockPerk("skybound")
    pickups.dropPerk(c.x, c.y - 12, "skybound", 0, -90)
    effects.popup(c.x, c.y - 30, "Something from above", { 0.8, 0.9, 1 })
  else
    local items = require("src.items")
    pickups.dropGold(c.x, c.y - 10, 150)
    for k = 1, 2 do
      local item
      for _ = 1, 30 do
        item = items.random()
        if item.rarity == "rare" or item.rarity == "epic" then
          break
        end
      end
      pickups.dropItem(c.x + (k - 1.5) * 10, c.y - 12, item, (k - 1.5) * 40, -100)
    end
  end
end

local function onScreen(camX, camY, pad)
  local X, D = airship.X, airship.DECK
  return X + 140 > camX - pad and X - 140 < camX + config.VIRTUAL_W + pad and D + 40 > camY - pad and D - 220 < camY + config.VIRTUAL_H + pad
end

-- The balloon and its ropes, behind the hull (the sky's backdrop is already drawn)
function airship.drawBack(camX, camY)
  if not onScreen(camX, camY, 20) then
    return
  end
  local X, D = airship.X, airship.DECK
  local cx, cy, rx, ry = X - 11, D - 130, 66, 56
  for sx = -rx, rx do
    local h = ry * math.sqrt(1 - (sx / rx) ^ 2)
    local stripe = math.floor((sx + rx) / 11) % 2
    local shade = 0.72 + 0.28 * (1 - math.abs(sx) / rx) - (sx > 0 and 0.12 * sx / rx or 0)
    if stripe == 0 then
      love.graphics.setColor(0.70 * shade, 0.18 * shade, 0.16 * shade)
    else
      love.graphics.setColor(0.90 * shade, 0.80 * shade, 0.58 * shade)
    end
    love.graphics.rectangle("fill", cx + sx, math.floor(cy - h), 1, math.floor(h * 2 + 0.5) + 6 * (1 - math.abs(sx) / rx))
  end
  love.graphics.setColor(0.35, 0.10, 0.10)
  for sx = -rx, rx, 4 do
    local h = ry * math.sqrt(1 - (sx / rx) ^ 2)
    love.graphics.rectangle("fill", cx + sx, math.floor(cy - h), 1, 1)
  end
  -- ropes from the envelope's belly down to the rail posts and the mast
  love.graphics.setColor(0.28, 0.2, 0.12)
  love.graphics.line(cx - 40, cy + 42, X - HALF + 1, D - 10)
  love.graphics.line(cx + 40, cy + 42, X + HALF - 1, D - 29)
  love.graphics.line(cx, cy + 56, X - 11, D - 64)
  love.graphics.line(cx - 20, cy + 52, X - 11, D - 64)
  love.graphics.line(cx + 20, cy + 52, X - 11, D - 64)
  -- a pennant on the mast
  local t = love.timer.getTime()
  love.graphics.setColor(0.85, 0.7, 0.3)
  for i = 0, 11 do
    love.graphics.rectangle("fill", X - 9 + i, D - 64 + math.floor(math.sin(t * 5 - i * 0.5) * 1.5 + 0.5) + math.floor(i / 4), 1, 4 - math.floor(i / 3))
  end
end

function airship.addLights(lighting, view)
  if not onScreen(view.x, view.y, 120) then
    return
  end
  local X, D = airship.X, airship.DECK
  lighting.add(X + 52, D - 16, 70, 1, 0.7, 0.35, 0.55 + 0.05 * math.sin(love.timer.getTime() * 3))
  lighting.add(X - HALF + 6, D - 12, 48, 1, 0.7, 0.35, 0.4)
end

return airship
