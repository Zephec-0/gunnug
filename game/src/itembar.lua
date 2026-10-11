-- Noita-style item bar along the top of the screen: 3 weapon slots followed by
-- 7 slots for loose ammo types and attachments. Tab opens the weapon panel in
-- the middle of the screen, where each carried weapon shows its stats and its
-- own ammo/attachment slots. While the panel is open the game is paused and
-- anything in a slot can be dragged to another slot (swapping if occupied).
--
-- Everything is drawn at full window resolution; u = one game pixel.
local inventory = require("src.inventory")

local itembar = {}

local isOpen = false
local hitboxes = {} -- slot rectangles from the last draw: { x, y, w, h, ref }
local drag -- { ref } while an item is being dragged

local WEAPON_SIZE, ITEM_SIZE, GUN_SLOT_SIZE = 18, 14, 13

local fonts = {}
local function font(px)
  px = math.max(9, math.floor(px))
  if not fonts[px] then
    fonts[px] = love.graphics.newFont(px)
  end
  return fonts[px]
end

-- Weapon icons are built once from each gun definition's pixel map
local ICON_PALETTE = {
  ["L"] = { 0.80, 0.82, 0.90 },
  ["#"] = { 0.34, 0.34, 0.42 },
  ["c"] = { 0.54, 0.54, 0.62 },
  ["w"] = { 0.66, 0.40, 0.20 },
}
local icons = {}
local function weaponIcon(def)
  if not icons[def] then
    local rows = def.icon
    local data = love.image.newImageData(#rows[1], #rows)
    for y, row in ipairs(rows) do
      for x = 1, #row do
        local c = ICON_PALETTE[row:sub(x, x)]
        if c then
          data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1)
        end
      end
    end
    icons[def] = love.graphics.newImage(data)
    icons[def]:setFilter("nearest", "nearest")
  end
  return icons[def]
end

function itembar.isOpen()
  return isOpen
end

function itembar.toggle()
  isOpen = not isOpen
  drag = nil
end

local function isWeapon(thing)
  return thing ~= nil and thing.def ~= nil
end

local function nameOf(thing)
  return isWeapon(thing) and thing.def.name or thing.name
end

-- Draws a weapon icon or item badge centred in a box
local function drawThing(thing, x, y, size, u, alpha)
  alpha = alpha or 1
  if isWeapon(thing) then
    local icon = weaponIcon(thing.def)
    local s = math.max(1, math.floor(size * 0.85 / icon:getWidth())) -- whole-number scale keeps pixels even
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(icon, x + (size - icon:getWidth() * s) / 2, y + (size - icon:getHeight() * s) / 2, 0, s, s)
  else
    local c = thing.color or { 0.7, 0.7, 0.7 }
    local pad = size * 0.18
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.rectangle("fill", x + pad, y + pad, size - 2 * pad, size - 2 * pad, u, u)
    local f = font(size * 0.38)
    local label = thing.short or "?"
    love.graphics.setFont(f)
    love.graphics.setColor(0.1, 0.08, 0.1, alpha)
    love.graphics.print(label, math.floor(x + (size - f:getWidth(label)) / 2), math.floor(y + (size - f:getHeight()) / 2))
  end
end

local function drawSlot(inv, ref, x, y, size, u, selected)
  local thing = inv:get(ref)
  love.graphics.setColor(0.08, 0.06, 0.10, 0.82)
  love.graphics.rectangle("fill", x, y, size, size, u, u)
  love.graphics.setLineWidth(math.max(1, u * 0.5))
  if selected then
    love.graphics.setColor(1, 0.82, 0.35)
  else
    love.graphics.setColor(0.55, 0.48, 0.42, 0.9)
  end
  love.graphics.rectangle("line", x, y, size, size, u, u)
  if thing then
    local dragged = drag and drag.ref.kind == ref.kind and drag.ref.index == ref.index and drag.ref.gun == ref.gun
    drawThing(thing, x, y, size, u, dragged and 0.3 or 1)
  end
  hitboxes[#hitboxes + 1] = { x = x, y = y, w = size, h = size, ref = ref }
end

local function hitTest(mx, my)
  for i = #hitboxes, 1, -1 do
    local h = hitboxes[i]
    if mx >= h.x and mx < h.x + h.w and my >= h.y and my < h.y + h.h then
      return h
    end
  end
  return nil
end

local function shadowPrint(text, x, y, f, color)
  love.graphics.setFont(f)
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.print(text, math.floor(x) + 2, math.floor(y) + 2)
  love.graphics.setColor(color or { 1, 1, 1 })
  love.graphics.print(text, math.floor(x), math.floor(y))
end

-- The always-visible bar along the top-left
local function drawBar(inv, u)
  local margin = 6 * u
  local x, y = margin, margin
  local numberFont = font(3 * u)
  for i = 1, inventory.WEAPON_SLOTS do
    local size = WEAPON_SIZE * u
    drawSlot(inv, { kind = "weapon", index = i }, x, y, size, u, i == inv.selected)
    shadowPrint(tostring(i), x + u, y + 0.5 * u, numberFont, { 1, 1, 1, 0.7 })
    x = x + size + 2 * u
  end
  x = x + 5 * u
  local itemY = y + (WEAPON_SIZE - ITEM_SIZE) / 2 * u
  for i = 1, inventory.ITEM_SLOTS do
    local size = ITEM_SIZE * u
    drawSlot(inv, { kind = "item", index = i }, x, itemY, size, u, false)
    x = x + size + 2 * u
  end
end

local function statLine(def)
  local damage = def.pellets > 1 and string.format("%d x %d", def.damage, def.pellets) or tostring(def.damage)
  return string.format(
    "Chambers %d    Fire delay %.2fs    Reload %.2fs\nSpread %g°    Damage %s    Impact %d",
    def.chambers,
    def.fireDelay,
    def.reloadTime,
    def.spread,
    damage,
    def.impactForce
  )
end

-- The weapon panel: one card per carried weapon with its stats and slots
local function drawPanel(inv, u)
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.02, 0.01, 0.04, 0.6)
  love.graphics.rectangle("fill", 0, 0, ww, wh)

  local cardW, cardH = 190 * u, 46 * u
  local x = math.floor((ww - cardW) / 2)
  local y = 36 * u
  local titleFont, textFont = font(5 * u), font(3.4 * u)

  shadowPrint("Weapons", x, y - 8 * u, titleFont, { 1, 0.86, 0.45 })
  for i = 1, inventory.WEAPON_SLOTS do
    local gun = inv.weapons[i]
    if gun then
      local selected = i == inv.selected
      love.graphics.setColor(0.10, 0.07, 0.12, 0.94)
      love.graphics.rectangle("fill", x, y, cardW, cardH, 2 * u, 2 * u)
      love.graphics.setLineWidth(math.max(1, u * 0.5))
      love.graphics.setColor(selected and { 1, 0.82, 0.35 } or { 0.55, 0.48, 0.42 })
      love.graphics.rectangle("line", x, y, cardW, cardH, 2 * u, 2 * u)

      -- Big icon on the left
      local iconBox = 34 * u
      drawThing(gun, x + 4 * u, y + 4 * u, iconBox, u)
      local tx = x + iconBox + 10 * u
      shadowPrint(gun.def.name .. "  [" .. i .. "]", tx, y + 3 * u, titleFont, { 1, 0.9, 0.6 })
      shadowPrint(statLine(gun.def), tx, y + 10 * u, textFont, { 0.88, 0.86, 0.82 })

      -- The gun's own ammo/attachment slots
      local sy = y + cardH - GUN_SLOT_SIZE * u - 4 * u
      shadowPrint("Slots", x + 6 * u, sy + (GUN_SLOT_SIZE * u - textFont:getHeight()) / 2, textFont, { 1, 0.86, 0.45 })
      for s = 1, gun.def.slots do
        local sx = tx + (s - 1) * (GUN_SLOT_SIZE + 2) * u
        drawSlot(inv, { kind = "gunSlot", gun = gun, index = s }, sx, sy, GUN_SLOT_SIZE * u, u, false)
      end
      y = y + cardH + 6 * u
    end
  end

  local hint = "Drag ammo and attachments between the bar and a weapon's slots.   1-3 / mouse wheel: switch weapon.   Tab: close"
  shadowPrint(hint, math.floor((ww - textFont:getWidth(hint)) / 2), y + 2 * u, textFont, { 1, 1, 1, 0.75 })
end

function itembar.draw(inv, u)
  hitboxes = {}
  if isOpen then
    drawPanel(inv, u)
  end
  drawBar(inv, u)

  local mx, my = love.mouse.getPosition()
  if drag then
    local thing = inv:get(drag.ref)
    if thing then
      local size = ITEM_SIZE * u
      drawThing(thing, mx - size / 2, my - size / 2, size, u)
    end
  elseif isOpen then
    local h = hitTest(mx, my)
    local thing = h and inv:get(h.ref)
    if thing then
      local f = font(3.4 * u)
      local name = nameOf(thing)
      love.graphics.setColor(0.05, 0.04, 0.06, 0.92)
      love.graphics.rectangle("fill", mx + 4 * u, my + 4 * u, f:getWidth(name) + 4 * u, f:getHeight() + 2 * u, u, u)
      shadowPrint(name, mx + 6 * u, my + 5 * u, f)
    end
  end
end

-- Returns true if the click was used by the item bar
function itembar.mousepressed(inv, x, y, button)
  if not isOpen or button ~= 1 then
    return false
  end
  local h = hitTest(x, y)
  if h and inv:get(h.ref) then
    drag = { ref = h.ref }
  end
  return true
end

function itembar.mousereleased(inv, x, y, button)
  if not drag or button ~= 1 then
    return
  end
  local h = hitTest(x, y)
  if h then
    inv:move(drag.ref, h.ref)
  end
  drag = nil
end

return itembar
