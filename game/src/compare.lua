-- The weapon compare prompt (design doc §9a): picking up a fourth weapon with
-- all three weapon slots full opens this. The found weapon is shown next to
-- the three carried ones, with their effective stats and fitted items, and
-- the hunter picks which to replace (click it, or press 1-3). The replaced gun
-- is dropped on the ground. Escape / E / Tab cancels and leaves the found
-- weapon where it lay. The game is paused while it is open.
local input = require("src.input")
local inventory = require("src.inventory")
local itembar = require("src.itembar")

local compare = {}

local found, pickup -- the gun on the ground and its pickup entry
local hitboxes = {}
local hovered

-- Set by src.game: called as onChoose(slotIndex, foundGun, pickup)
compare.onChoose = nil

function compare.open(gun, p)
  found, pickup = gun, p
  hovered = nil
  hitboxes = {}
end

function compare.close()
  found, pickup = nil, nil
end

function compare.isOpen()
  return found ~= nil
end

local function choose(index)
  local gun, p = found, pickup
  compare.close()
  if compare.onChoose then
    compare.onChoose(index, gun, p)
  end
end

function compare.keypressed(key)
  if not found then
    return
  end
  local n = tonumber(key)
  if n and n >= 1 and n <= inventory.weaponSlots() then
    choose(n)
  elseif key == "escape" or input.is("interact", key) or input.is("inventory", key) or key == "backspace" then
    compare.close()
  end
end

local function hitIndex(x, y)
  for i, h in ipairs(hitboxes) do
    if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then
      return i
    end
  end
  return nil
end

-- Releasing the mouse on a carried weapon replaces it (on release, so the
-- click never reaches the game as a shot)
function compare.mousereleased(x, y, button)
  if found and button == 1 then
    local i = hitIndex(x, y)
    if i then
      choose(i)
    end
  end
end

function compare.update()
  if found then
    hovered = hitIndex(love.mouse.getPosition())
  end
end

function compare.draw(inv, u)
  if not found then
    return
  end
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.02, 0.01, 0.04, 0.75)
  love.graphics.rectangle("fill", 0, 0, ww, wh)

  -- The found weapon on the left as a card, an arrow, then the carried weapons' cards: the same cards as the
  -- weapon panel (src.itembar), not live, scaled down to fit the screen
  local C = itembar.CARD
  local carried = {}
  for i = 1, inventory.weaponSlots() do
    if inv.weapons[i] then
      carried[#carried + 1] = i
    end
  end
  local split = 14 -- the gap between the found card and the carried ones, in UI units
  local totalUnits = (#carried + 1) * C.w + math.max(0, #carried - 1) * C.gap + split
  local cu = math.min(u, ww * 0.96 / totalUnits)
  local cardW, cardH, gap = C.w * cu, C.h * cu, C.gap * cu
  local x0 = math.floor((ww - totalUnits * cu) / 2)
  local y = math.max(24 * u, math.floor((wh - cardH) / 2) - 4 * u)
  local title, small = itembar.font(5 * u), itembar.font(3.4 * u)

  -- The found weapon
  itembar.shadowPrint("Found a weapon", x0, y - 9 * u, title, { 0.95, 0.97, 1 })
  itembar.drawGunCard(inv, found, x0, y, cu, { border = { 0.55, 0.75, 1 }, selected = true, static = true })

  -- The arrow between them
  local ax, ay = x0 + cardW + (split * cu) / 2, y + cardH / 2
  love.graphics.setColor(0.55, 0.75, 1, 0.9)
  love.graphics.polygon("fill", ax - 3 * cu, ay - 5 * cu, ax + 3 * cu, ay, ax - 3 * cu, ay + 5 * cu)

  -- The carried weapons: click one (or press its number) to swap it for the found one
  local cx = x0 + cardW + split * cu
  itembar.shadowPrint("Replace which?", cx, y - 9 * u, title, { 0.95, 0.97, 1 })
  hitboxes = {}
  for _, i in ipairs(carried) do
    local isHover = hovered == i
    itembar.drawGunCard(inv, inv.weapons[i], cx, y, cu, { index = i, border = isHover and { 1, 0.5, 0.4 } or { 0.55, 0.48, 0.42 }, selected = isHover, static = true })
    if isHover then
      local f = itembar.font(3.4 * u)
      itembar.shadowPrint("REPLACE", cx + (cardW - f:getWidth("REPLACE")) / 2, y - 4.2 * u, f, { 1, 0.5, 0.4 })
    end
    hitboxes[i] = { x = cx, y = y, w = cardW, h = cardH }
    cx = cx + cardW + gap
  end

  local hint = "Click a carried weapon (or press 1-3) to replace it - the old one drops.   Esc: leave it"
  itembar.shadowPrint(hint, math.floor((ww - small:getWidth(hint)) / 2), y + cardH + 4 * u, small, { 1, 1, 1, 0.8 })
end

return compare
