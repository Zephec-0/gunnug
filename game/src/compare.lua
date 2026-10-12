-- The weapon compare prompt (design doc §9a): picking up a fourth weapon with
-- all three weapon slots full opens this. The found weapon is shown next to
-- the three carried ones, with their effective stats and fitted items, and
-- the hunter picks which to replace (click it, or press 1-3). The replaced gun
-- is dropped on the ground. Escape / E / Tab cancels and leaves the found
-- weapon where it lay. The game is paused while it is open.
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
  if n and n >= 1 and n <= inventory.WEAPON_SLOTS then
    choose(n)
  elseif key == "escape" or key == "e" or key == "tab" or key == "backspace" then
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

-- One compact weapon card: icon, name, effective stats and fitted items
local function card(gun, x, y, w, h, u, borderColor, tag)
  love.graphics.setColor(0.10, 0.07, 0.12, 0.95)
  love.graphics.rectangle("fill", x, y, w, h, 2 * u, 2 * u)
  love.graphics.setLineWidth(math.max(1, u * 0.5))
  love.graphics.setColor(borderColor)
  love.graphics.rectangle("line", x, y, w, h, 2 * u, 2 * u)

  itembar.drawThing(gun, x + 2 * u, y + 3 * u, 22 * u, u)
  local tx = x + 27 * u
  require("src.fonts").printGraded(itembar.font(3.8 * u), gun.name, require("src.gunInfo").grade(gun), tx, y + 2 * u, { 0.98, 0.99, 1 }, 2)
  itembar.shadowPrint(itembar.statLine(gun), tx, y + 8 * u, itembar.font(3.1 * u), { 0.88, 0.86, 0.82 })

  -- Fitted ammo and attachments, in a row along the bottom
  local size = 7 * u
  local sy = y + h - size - 1.5 * u
  for s = 1, gun.slotCount do
    local sx = tx + (s - 1) * (size + u)
    love.graphics.setColor(0.06, 0.05, 0.08, 0.9)
    love.graphics.rectangle("fill", sx, sy, size, size, u, u)
    love.graphics.setColor(0.45, 0.4, 0.38)
    love.graphics.rectangle("line", sx, sy, size, size, u, u)
    if gun.slots[s] then
      itembar.drawThing(gun.slots[s], sx, sy, size, u)
    end
  end
  if tag then
    local f = itembar.font(3 * u)
    itembar.shadowPrint(tag, x + w - 3 * u - f:getWidth(tag), y + h - 6 * u, f, borderColor)
  end
end

function compare.draw(inv, u)
  if not found then
    return
  end
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.02, 0.01, 0.04, 0.75)
  love.graphics.rectangle("fill", 0, 0, ww, wh)

  local cardW, cardH = 200 * u, 36 * u
  local x = math.floor((ww - cardW) / 2)
  local y = 10 * u
  local title, small = itembar.font(5 * u), itembar.font(3.4 * u)

  itembar.shadowPrint("Found a weapon", x, y, title, { 0.95, 0.97, 1 })
  y = y + 9 * u
  card(found, x, y, cardW, cardH, u, { 0.55, 0.75, 1 }, "FOUND")
  y = y + cardH + 5 * u
  local hint = "Click a carried weapon (or press 1-3) to replace it - the old one drops.   Esc: leave it"
  itembar.shadowPrint(hint, math.floor((ww - small:getWidth(hint)) / 2), y, small, { 1, 1, 1, 0.8 })
  y = y + 7 * u

  hitboxes = {}
  local carriedH = 34 * u
  for i = 1, inventory.WEAPON_SLOTS do
    local gun = inv.weapons[i]
    if gun then
      local isHover = hovered == i
      card(gun, x, y, cardW, carriedH, u, isHover and { 1, 0.5, 0.4 } or { 0.55, 0.48, 0.42 }, isHover and "REPLACE" or ("[" .. i .. "]"))
      hitboxes[i] = { x = x, y = y, w = cardW, h = carriedH }
    end
    y = y + carriedH + 3 * u
  end
end

return compare
