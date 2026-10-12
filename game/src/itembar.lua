-- Noita-style item bar along the top of the screen: 3 weapon slots followed by
-- 7 slots for loose ammo types and attachments. Tab opens the weapon panel in
-- the middle of the screen, where each carried weapon shows its stats and its
-- own ammo/attachment slots. While the panel is open the game is paused and
-- anything in a slot can be dragged to another slot (swapping if occupied).
--
-- Everything is drawn at full window resolution; u = one game pixel.
local gunInfo = require("src.gunInfo")
local inventory = require("src.inventory")
local itemIcons = require("src.icons")
local items = require("src.items")
local perks = require("src.perks")

local itembar = {}

local isOpen = false
local hitboxes = {} -- slot rectangles from the last draw: { x, y, w, h, ref }
local drag -- { ref } while an item is being dragged
local perkCache = {} -- perk id -> the table the UI draws and tooltips

local WEAPON_SIZE, ITEM_SIZE, GUN_SLOT_SIZE = 18, 14, 13

local fontFace = require("src.fonts")
local function font(px)
  return fontFace.get(math.max(9, math.floor(px)))
end

-- Weapon icons are built once from each gun definition's pixel map
local ICON_PALETTE = {
  ["L"] = { 0.80, 0.82, 0.92 },
  ["#"] = { 0.34, 0.35, 0.44 },
  ["k"] = { 0.12, 0.11, 0.16 },
  ["c"] = { 0.66, 0.58, 0.42 },
  ["w"] = { 0.42, 0.26, 0.13 },
  ["W"] = { 0.68, 0.44, 0.22 },
}
local icons = {}
local iconParts = {}

-- An icon image from the pixel map, keeping only the cells `keep(char, x)` accepts
local function buildIcon(rows, keep)
  local data = love.image.newImageData(#rows[1], #rows)
  for y, row in ipairs(rows) do
    for x = 1, #row do
      local ch = row:sub(x, x)
      local c = ICON_PALETTE[ch]
      if c and (not keep or keep(ch, x)) then
        data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img
end

local function weaponIcon(def)
  if not icons[def] then
    icons[def] = buildIcon(def.icon)
  end
  return icons[def]
end

-- The icon split in two for the reload animation: the part that moves
-- (cylinder, drum or magazine; for the double-barrel, the barrels ahead of the
-- hinge) and the rest
local HINGE_X = 6
local function weaponParts(def)
  if not iconParts[def] then
    local barrels = def.model == "shotgun"
    iconParts[def] = {
      body = buildIcon(def.icon, function(ch, x)
        return barrels and x <= HINGE_X or (not barrels and ch ~= "c")
      end),
      part = buildIcon(def.icon, function(ch, x)
        return barrels and x > HINGE_X or (not barrels and ch == "c")
      end),
    }
  end
  return iconParts[def]
end

local function ease(t)
  t = math.max(0, math.min(1, t))
  return t * t * (3 - 2 * t)
end

-- A weapon icon at whole-number scale s from (ox, oy). While the gun reloads
-- it plays its reload: the revolver's cylinder swings out and is thumbed full,
-- the double-barrel breaks open, tosses its shells and takes two more, and the
-- drum or magazine of the others drops away and a fresh one is slapped in.
local function drawWeaponIcon(gun, ox, oy, s, alpha)
  local def = gun.def
  local icon = weaponIcon(def)
  love.graphics.setColor(1, 1, 1, alpha)
  if not (gun.isReloading and gun:isReloading()) then
    love.graphics.draw(icon, ox, oy, 0, s, s)
    return
  end
  local p = gun:reloadProgress()
  local parts = weaponParts(def)
  local model = def.model
  local function px(x, y, w, h, r, g, b, a)
    love.graphics.setColor(r, g, b, (a or 1) * alpha)
    love.graphics.rectangle("fill", math.floor(ox + x * s), math.floor(oy + y * s), w * s, h * s)
    love.graphics.setColor(1, 1, 1, alpha)
  end
  local function img(i, dx, dy, a)
    love.graphics.setColor(1, 1, 1, (a or 1) * alpha)
    love.graphics.draw(i, math.floor(ox + dx * s), math.floor(oy + dy * s), 0, s, s)
  end
  if model == "revolver" then
    -- Cylinder out to the lower right, rounds dropped in one by one, back and snapped shut
    local out = ease(p / 0.12) - ease((p - 0.78) / 0.1)
    img(parts.body, 0, 0)
    img(parts.part, 2 * out, 3 * out)
    for k = 0, 5 do
      local t0 = 0.2 + k * 0.08
      if p > t0 and p < 0.82 then
        local fall = math.min(1, (p - t0) / 0.07)
        px(7 + k % 3 * 2 + 2 * out, 3 + (k >= 3 and 1 or 0) + 3 * out - (1 - fall) * 4, 1, 1, 0.98, 0.78, 0.30, fall)
      end
    end
  elseif model == "shotgun" then
    -- Breaks open about the hinge, shells fly out, new ones go in, snaps shut
    local open = ease(p / 0.14) - ease((p - 0.72) / 0.1)
    img(parts.body, 0, 0)
    love.graphics.push()
    love.graphics.translate(ox + HINGE_X * s, oy + 4.5 * s)
    love.graphics.rotate(-0.45 * open)
    love.graphics.translate(-(ox + HINGE_X * s), -(oy + 4.5 * s))
    img(parts.part, 0, 0)
    love.graphics.pop()
    for k = 0, 1 do
      -- Out: up and back in an arc
      local t = (p - 0.14 - k * 0.04) / 0.3
      if t > 0 and t < 1 then
        px(7 - 3 * t + k * 2, 3 - 6 * t + 9 * t * t - 2, 2, 1, 0.78, 0.18, 0.14, 1 - t * 0.7)
        px(9 - 3 * t + k * 2, 3 - 6 * t + 9 * t * t - 2, 1, 1, 0.9, 0.7, 0.3, 1 - t * 0.7)
      end
      -- In: dropped from above into the barrels
      local u = (p - 0.5 - k * 0.06) / 0.2
      if u > 0 and u < 1 then
        px(8 + k * 2, -3 + 6 * u, 2, 1, 0.78, 0.18, 0.14)
        px(10 + k * 2, -3 + 6 * u, 1, 1, 0.9, 0.7, 0.3)
      end
    end
  else
    -- Magazine out and down, an empty gap, a fresh one slapped up into place
    local down = ease(p / 0.2)
    local back = ease((p - 0.45) / 0.3)
    local snap = p > 0.75 and p < 0.88 and 1 or 0
    img(parts.body, 0, -snap * 0.5)
    if p < 0.35 then
      img(parts.part, 0, 5 * down, 1 - down)
    else
      img(parts.part, 0, 5 * (1 - back), back)
    end
  end
  love.graphics.setColor(1, 1, 1, alpha)
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
  local rarity = thing.rarity and items.rarities[thing.rarity]
  if rarity and thing.rarity ~= "common" then
    return thing.name .. "  [" .. rarity.name .. "]"
  end
  return thing.name
end

-- Draws a weapon icon or item badge centred in a box
local function drawThing(thing, x, y, size, u, alpha)
  alpha = alpha or 1
  if isWeapon(thing) then
    local icon = weaponIcon(thing.def)
    local s = math.max(1, math.floor(size * 0.85 / icon:getWidth())) -- whole-number scale keeps pixels even
    drawWeaponIcon(thing, x + (size - icon:getWidth() * s) / 2, y + (size - icon:getHeight() * s) / 2, s, alpha)
  elseif itemIcons.get(thing) then
    -- A pixel icon in the item's colours, with the rarity rim around it
    local img = itemIcons.get(thing)
    local s = math.max(1, math.floor(size * 0.78 / 8))
    local box = 8 * s
    local ix, iy = x + (size - box) / 2, y + (size - box) / 2
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(img, ix, iy, 0, s, s)
    local rarity = thing.rarity and thing.rarity ~= "common" and items.rarities[thing.rarity]
    if rarity then
      love.graphics.setLineWidth(math.max(1, u * 0.7))
      love.graphics.setColor(rarity.border[1], rarity.border[2], rarity.border[3], alpha)
      love.graphics.rectangle("line", x + u * 0.6, y + u * 0.6, size - u * 1.2, size - u * 1.2, u, u)
    end
  else
    local c = thing.color or { 0.7, 0.7, 0.7 }
    local pad = size * 0.18
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.rectangle("fill", x + pad, y + pad, size - 2 * pad, size - 2 * pad, u, u)
    -- Rare items get a blue rim, cursed ones a red one
    local rarity = thing.rarity and thing.rarity ~= "common" and items.rarities[thing.rarity]
    if rarity then
      love.graphics.setLineWidth(math.max(1, u * 0.7))
      love.graphics.setColor(rarity.border[1], rarity.border[2], rarity.border[3], alpha)
      love.graphics.rectangle("line", x + pad - u * 0.5, y + pad - u * 0.5, size - 2 * pad + u, size - 2 * pad + u, u, u)
    end
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
    love.graphics.setColor(0.55, 0.75, 1)
  else
    love.graphics.setColor(0.55, 0.48, 0.42, 0.9)
  end
  love.graphics.rectangle("line", x, y, size, size, u, u)
  if thing then
    local dragged = drag and drag.ref.kind == ref.kind and drag.ref.index == ref.index and drag.ref.gun == ref.gun
    drawThing(thing, x, y, size, u, dragged and 0.3 or 1)
    if isWeapon(thing) and thing:isReloading() then
      -- A thin bar along the bottom fills as it reloads (holstered guns too)
      love.graphics.setColor(0.04, 0.03, 0.07, 0.8)
      love.graphics.rectangle("fill", x + u, y + size - 2.2 * u, size - 2 * u, 1.2 * u)
      love.graphics.setColor(0.45, 0.85, 1)
      love.graphics.rectangle("fill", x + u, y + size - 2.2 * u, (size - 2 * u) * thing:reloadProgress(), 1.2 * u)
    end
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
  -- The perks taken this run, as small badges under the bar
  local list = perks.list()
  if #list > 0 then
    local px, py = margin, margin + WEAPON_SIZE * u + 3 * u
    local size = 9 * u
    for i, id in ipairs(list) do
      perkCache[id] = perkCache[id] or perks.new(id)
      drawSlot(inv, { kind = "perk", index = i, perk = perkCache[id] }, px, py, size, u, false)
      px = px + size + u
    end
  end
end

-- Effects shown in the stats under the usual numbers
local EFFECT_LABELS = {
  { "pierce", "Pierce" }, { "bounces", "Ricochet" }, { "explosive", "Explosive" }, { "incendiary", "Incendiary" },
  { "freeze", "Frost" }, { "shock", "Shock" }, { "poison", "Venom" }, { "acid", "Acid" }, { "concussive", "Concussive" },
  { "sticky", "Sticky" }, { "homing", "Seeking" }, { "gravity", "Singularity" }, { "split", "Splitting" },
  { "cluster", "Cluster" }, { "boomerang", "Boomerang" }, { "ghost", "Spectral" }, { "execute", "Executioner" },
  { "vamp", "Vampiric" }, { "greed", "Gilded" }, { "burst", "Burst" }, { "rear", "Backblast" }, { "mortar", "Mortar" },
  { "overheat", "Overclock" }, { "refill", "Scavenger" }, { "jets", "Jets" }, { "bayonet", "Bayonet" },
  { "opener", "Primer" }, { "quickdraw", "Quickdraw" }, { "sneak", "Suppressed" }, { "laser", "Laser" },
  { "steady", "Steady" }, { "bgReload", "Holster reload" }, { "glow", "Glowing" }, { "bloodCost", "Blood" }, { "misfire", "Unstable" },
}

-- The gun's effective stats (fitted ammo and attachments applied)
local function statLine(gun)
  local st = gun:stats()
  local dmg = math.max(1, math.floor(st.damage + 0.5))
  local damage = st.pellets > 1 and string.format("%d x %d", dmg, st.pellets) or tostring(dmg)
  local text = string.format(
    "Chambers %d    Fire delay %.2fs    Reload %.2fs    Slots %d\nSpread %.1f°    Damage %s    Impact %d    Recoil %d",
    st.chambers,
    st.fireDelay,
    st.reloadTime,
    gun.slotCount,
    st.spread,
    damage,
    st.impactForce,
    st.recoil
  )
  local effects = {}
  if st.critChance > 0 then
    effects[#effects + 1] = string.format("Crit %d%%", math.floor(st.critChance * 100 + 0.5))
  end
  for _, e in ipairs(EFFECT_LABELS) do
    local n = st[e[1]]
    if n and n > 0 then
      effects[#effects + 1] = (n >= 2 and (e[2] .. " " .. math.floor(n)) or e[2])
    end
  end
  if #effects > 0 then
    text = text .. "\n" .. table.concat(effects, "   ")
  end
  return text
end

-- The weapon panel: one card per carried weapon with its stats and slots
local function drawPanel(inv, u)
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.02, 0.01, 0.04, 0.6)
  love.graphics.rectangle("fill", 0, 0, ww, wh)

  local cardW, cardH = 196 * u, 55 * u
  local x = math.floor((ww - cardW) / 2)
  local y = 34 * u
  local titleFont, textFont, bigFont = font(5 * u), font(3.4 * u), font(6.4 * u)

  shadowPrint("Weapons", x, y - 8 * u, titleFont, { 0.98, 0.99, 1 })
  for i = 1, inventory.WEAPON_SLOTS do
    local gun = inv.weapons[i]
    if gun then
      local selected = i == inv.selected
      love.graphics.setColor(0.10, 0.07, 0.12, 0.94)
      love.graphics.rectangle("fill", x, y, cardW, cardH, 2 * u, 2 * u)
      love.graphics.setLineWidth(math.max(1, u * 0.5))
      love.graphics.setColor(selected and { 0.55, 0.75, 1 } or { 0.55, 0.48, 0.42 })
      love.graphics.rectangle("line", x, y, cardW, cardH, 2 * u, 2 * u)

      -- Big icon on the left, in a framed box, with the weapon's number
      local iconBox = 34 * u
      love.graphics.setColor(0.05, 0.04, 0.08, 0.9)
      love.graphics.rectangle("fill", x + 3 * u, y + 3 * u, iconBox + 2 * u, iconBox + 2 * u, u, u)
      drawThing(gun, x + 4 * u, y + 4 * u, iconBox, u)
      shadowPrint("[" .. i .. "]", x + 4 * u, y + 4 * u + iconBox - textFont:getHeight() * 0.9, textFont, { 0.75, 0.78, 0.86 })
      local tx = x + iconBox + 10 * u

      -- Name, archetype and the grade badge at the right
      local grade = gunInfo.grade(gun)
      shadowPrint(gun.name, tx, y + 2 * u, titleFont, { 0.98, 0.99, 1 })
      local bx, bw = x + cardW - 12 * u, 9 * u
      love.graphics.setColor(0.04, 0.03, 0.07, 0.95)
      love.graphics.rectangle("fill", bx, y + 2 * u, bw, bw, u, u)
      love.graphics.setLineWidth(math.max(1, u * 0.6))
      love.graphics.setColor(grade.color)
      love.graphics.rectangle("line", bx, y + 2 * u, bw, bw, u, u)
      love.graphics.setFont(bigFont)
      love.graphics.setColor(grade.color)
      love.graphics.print(grade.letter, math.floor(bx + (bw - bigFont:getWidth(grade.letter)) / 2), math.floor(y + 2 * u + (bw - bigFont:getHeight()) / 2))
      shadowPrint(gun.def.name, tx, y + 2 * u + titleFont:getHeight(), textFont, { 0.66, 0.70, 0.80 })

      -- The stats in three columns: label, value, and how it compares with
      -- the archetype's base (green is better, red worse)
      local rows = gunInfo.rows(gun)
      local colW = 49 * u
      local gy = y + 2 * u + titleFont:getHeight() + textFont:getHeight() + 1.5 * u
      local rowH = textFont:getHeight() * 0.95
      for n, row in ipairs(rows) do
        local cx = tx + ((n - 1) % 3) * colW
        local cy = gy + math.floor((n - 1) / 3) * rowH
        shadowPrint(row[1], cx, cy, textFont, { 0.62, 0.66, 0.76 })
        local lw = textFont:getWidth(row[1] .. " ")
        shadowPrint(row[2], cx + lw, cy, textFont, { 0.98, 0.99, 1 })
        if row[3] then
          local vw = textFont:getWidth(row[2] .. " ")
          local d = row[3]
          shadowPrint(string.format("%+d%%", math.floor(d * 100 + (d > 0 and 0.5 or -0.5))), cx + lw + vw, cy, textFont, d > 0 and { 0.5, 1, 0.58 } or { 1, 0.45, 0.4 })
        end
      end
      local ey = gy + 3 * rowH + 0.5 * u
      local line = statLine(gun):match("[^\n]*$")
      if statLine(gun):find("\n.*\n") then
        shadowPrint(line, tx, ey, textFont, { 0.80, 0.86, 1 })
      end

      -- The gun's own ammo/attachment slots
      local sy = y + cardH - GUN_SLOT_SIZE * u - 3 * u
      shadowPrint("Slots", x + 6 * u, sy + (GUN_SLOT_SIZE * u - textFont:getHeight()) / 2, textFont, { 0.95, 0.97, 1 })
      for s = 1, gun.slotCount do
        local sx = tx + (s - 1) * (GUN_SLOT_SIZE + 2) * u
        drawSlot(inv, { kind = "gunSlot", gun = gun, index = s }, sx, sy, GUN_SLOT_SIZE * u, u, false)
      end
      y = y + cardH + 4 * u
    end
  end

  local hint = "Drag ammo between slots; drag a weapon or item off the bar to drop it.   1-3 / wheel: switch   Tab: close"
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
      -- Name, and for ammo and attachments what they do
      local f = font(3.4 * u)
      local name = nameOf(thing)
      local grade = isWeapon(thing) and gunInfo.grade(thing)
      local wrapW = 90 * u
      local _, lines = f:getWrap(thing.desc or "", wrapW)
      local nameW = grade and fontFace.gradedWidth(f, name, grade) or f:getWidth(name)
      local w = math.max(nameW, thing.desc and wrapW or 0) + 4 * u
      local h = f:getHeight() * (1 + (thing.desc and #lines or 0)) + 3 * u
      local tx, ty = mx + 4 * u, my + 4 * u
      love.graphics.setColor(0.05, 0.04, 0.06, 0.94)
      love.graphics.rectangle("fill", tx, ty, w, h, u, u)
      if grade then
        fontFace.printGraded(f, name, grade, tx + 2 * u, ty + u, { 0.98, 0.99, 1 }, 2)
      else
        shadowPrint(name, tx + 2 * u, ty + u, f, thing.color or { 1, 1, 1 })
      end
      if thing.desc then
        love.graphics.setFont(f)
        love.graphics.setColor(0.85, 0.83, 0.8)
        love.graphics.printf(thing.desc, tx + 2 * u, ty + u + f:getHeight(), wrapW)
      end
    end
  end
end

-- Shared with the weapon compare prompt (src.compare)
itembar.font = font
itembar.shadowPrint = shadowPrint
itembar.drawThing = drawThing
itembar.statLine = statLine
itembar.weaponIcon = weaponIcon

-- Returns true if the click was used by the item bar
function itembar.mousepressed(inv, x, y, button)
  if not isOpen or button ~= 1 then
    return false
  end
  local h = hitTest(x, y)
  if h and h.ref.kind ~= "perk" and inv:get(h.ref) then
    drag = { ref = h.ref }
  end
  return true
end

-- Called with an item (or, for onDropWeapon, a weapon) that was dragged out of
-- its slot and released outside every slot (set by src.game: it drops it on
-- the ground).
itembar.onDrop = nil
itembar.onDropWeapon = nil

function itembar.mousereleased(inv, x, y, button)
  if not drag or button ~= 1 then
    return
  end
  local h = hitTest(x, y)
  if h then
    inv:move(drag.ref, h.ref)
  elseif drag.ref.kind ~= "weapon" and itembar.onDrop then
    -- Released away from any slot: ammo and attachments are dropped
    local item = inv:get(drag.ref)
    if item then
      inv:set(drag.ref, nil)
      itembar.onDrop(item)
    end
  elseif drag.ref.kind == "weapon" and itembar.onDropWeapon then
    -- ...and so are weapons, even the last one (the slot is then empty: bare hands)
    local gun = inv:get(drag.ref)
    if gun then
      inv:set(drag.ref, nil)
      itembar.onDropWeapon(gun)
    end
  end
  drag = nil
end

return itembar
