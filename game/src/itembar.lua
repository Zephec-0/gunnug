-- Noita-style item bar along the top of the screen: 3 weapon slots followed by
-- 7 slots for loose ammo types and attachments. Tab opens the weapon panel in
-- the middle of the screen, where each carried weapon shows its stats and its
-- own ammo/attachment slots. While the panel is open the game is paused and
-- anything in a slot can be dragged to another slot (swapping if occupied).
--
-- Everything is drawn at full window resolution; u = one game pixel.
local input = require("src.input")
local fuser = require("src.fuser")
local gunInfo = require("src.gunInfo")
local gunhud = require("src.gunhud")
local inventory = require("src.inventory")
local itemIcons = require("src.icons")
local items = require("src.items")
local perks = require("src.perks")

local itembar = {}

local BAR_SCALE = 0.8 -- the always-visible bar is drawn this much smaller than the rest of the UI (it was crowding the health display)

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

local GUN_FILL = 0.92 -- how much of a slot a gun's model fills
local gunCanvases = {} -- "WxH@q" -> the canvas a model is drawn into

-- Draws a weapon icon or item badge centred in a box
local function drawThing(thing, x, y, size, u, alpha)
  alpha = alpha or 1
  if isWeapon(thing) and gunhud.supports(thing) then
    -- The drawn models (each with its own reload animation) come in different
    -- sizes, so each is scaled to fill the slot: drawn crisp at a whole-number
    -- scale into a canvas, then scaled smoothly to the exact size ("sharp
    -- bilinear", like the game's own screen), instead of snapping to 1x or 2x
    local w, h = gunhud.size(thing)
    local fit = math.min(size * GUN_FILL / w, size * GUN_FILL / h) -- screen pixels per model pixel
    local q0 = math.max(1, math.ceil(fit))
    local key = w .. "x" .. h .. "@" .. q0
    local canvas = gunCanvases[key]
    if not canvas then
      canvas = love.graphics.newCanvas(w * q0, h * q0)
      canvas:setFilter("linear", "linear")
      gunCanvases[key] = canvas
    end
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    gunhud.drawModel(thing, 0, 0, q0, 1)
    love.graphics.pop()
    love.graphics.setColor(alpha, alpha, alpha, alpha) -- (premultiplied)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.draw(canvas, math.floor(x + (size - w * fit) / 2), math.floor(y + (size - h * fit) / 2), 0, fit / q0, fit / q0)
    love.graphics.setBlendMode("alpha")
  elseif isWeapon(thing) then
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
    if (thing.level or 0) > 0 then
      itemIcons.drawLevel(thing.level, x, y, size, alpha)
    end
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

local FUSE_TEAL = { 0.25, 1.0, 0.82 }

-- The fuser beside the item slots (src.fuser): two slots in a teal frame, the
-- lock toggle, and the ether gauge under them
local fuseKnob = 0 -- the switch's knob, eased between 0 (off, down) and 1 (on, up)

local function drawFuser(inv, x, y, u, fusable, pip)
  local f = inv.fuse
  local size = ITEM_SIZE * u
  local t = love.timer.getTime()
  local pulse = f.locked and (0.65 + 0.35 * math.sin(t * 4)) or 0.55
  local toggleW = 9 * u
  local w = size * 2 + 2 * u + 2 * u + toggleW
  -- The frame
  love.graphics.setColor(0.03, 0.08, 0.08, 0.75)
  love.graphics.rectangle("fill", x - 1.5 * u, y - 1.5 * u, w + 3 * u, size + 6 * u, 1.5 * u, 1.5 * u)
  love.graphics.setLineWidth(math.max(1, u * 0.5))
  love.graphics.setColor(FUSE_TEAL[1], FUSE_TEAL[2], FUSE_TEAL[3], 0.35 + 0.4 * pulse * (f.locked and 1 or 0.5))
  love.graphics.rectangle("line", x - 1.5 * u, y - 1.5 * u, w + 3 * u, size + 6 * u, 1.5 * u, 1.5 * u)
  for i = 1, 2 do
    local sx = x + (i - 1) * (size + 2 * u)
    drawSlot(inv, { kind = "fuse", index = i }, sx, y, size, u, false)
    local item = f.slots[i]
    if item and fusable and fusable[item] and pip then
      pip(math.floor(sx + 1.5 * u), math.floor(y + 1.5 * u))
    end
    if f.locked then
      -- Locked in: a teal wash and a pulsing rim
      love.graphics.setColor(FUSE_TEAL[1], FUSE_TEAL[2], FUSE_TEAL[3], 0.12 * pulse)
      love.graphics.rectangle("fill", sx, y, size, size, u, u)
      love.graphics.setColor(FUSE_TEAL[1], FUSE_TEAL[2], FUSE_TEAL[3], pulse)
      love.graphics.rectangle("line", sx, y, size, size, u, u)
    end
  end
  -- A "+" between the slots
  love.graphics.setColor(FUSE_TEAL[1], FUSE_TEAL[2], FUSE_TEAL[3], 0.8)
  local cx, cy = x + size + u, y + size / 2
  love.graphics.rectangle("fill", cx - 0.5 * u, cy - 1.5 * u, u, 3 * u)
  love.graphics.rectangle("fill", cx - 1.5 * u, cy - 0.5 * u, 3 * u, u)
  -- The toggle: a switch standing on end, in the same chunky pixels as the
  -- icons. A 7x11 pill filling the whole slot, with a flat 3x3 knob that
  -- slides up (on: the pill lit teal) or down (off: dark)
  local tx = x + size * 2 + 4 * u
  local dt = love.timer.getDelta()
  fuseKnob = fuseKnob + ((f.locked and 1 or 0) - fuseKnob) * math.min(1, dt * 14)
  local cell = math.max(1, math.floor(math.min(toggleW / 7, size / 11)))
  local gx = math.floor(tx + (toggleW - 7 * cell) / 2)
  local gy = math.floor(y + (size - 11 * cell) / 2)
  local function px(cx, cy, cw, ch, c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
    love.graphics.rectangle("fill", gx + cx * cell, gy + cy * cell, cw * cell, ch * cell)
  end
  local outline, fill, knob
  if f.locked then
    local glow = 0.8 + 0.2 * pulse
    outline = { FUSE_TEAL[1] * 0.5 * glow, FUSE_TEAL[2] * 0.62 * glow, FUSE_TEAL[3] * 0.55 * glow }
    fill = { FUSE_TEAL[1] * 0.85, FUSE_TEAL[2] * 0.85, FUSE_TEAL[3] * 0.85 }
    knob = { 1, 1, 1 }
  else
    outline = { 0.03, 0.06, 0.06 }
    fill = { 0.10, 0.14, 0.15 }
    knob = { 0.72, 0.76, 0.78 }
  end
  -- The pill: outline, then fill (the corners cut away)
  px(2, 0, 3, 11, outline)
  px(1, 1, 5, 9, outline)
  px(0, 2, 7, 7, outline)
  px(2, 1, 3, 9, fill)
  px(1, 2, 5, 7, fill)
  -- The knob, a flat square moving a cell at a time
  local ky = 6 - math.floor(4 * fuseKnob + 0.5)
  px(2, ky, 3, 3, knob)
  hitboxes[#hitboxes + 1] = { x = tx, y = y, w = toggleW, h = size, ref = { kind = "fuseToggle" } }
  -- The ether gauge
  local gx, gy, gw, gh = x, y + size + 1.5 * u, size * 2 + 2 * u, math.max(2, 1.6 * u)
  love.graphics.setColor(0.02, 0.05, 0.05, 0.9)
  love.graphics.rectangle("fill", gx, gy, gw, gh)
  local k = fuser.progress(f)
  if k > 0 then
    love.graphics.setColor(FUSE_TEAL[1], FUSE_TEAL[2], FUSE_TEAL[3], 0.9)
    love.graphics.rectangle("fill", gx, gy, gw * k, gh)
    love.graphics.setColor(0.85, 1, 0.95, 0.6 + 0.4 * math.sin(t * 6))
    love.graphics.rectangle("fill", gx + gw * k - u, gy, u, gh)
  end
end

-- What hovering over the fuser's toggle says
local function fuserTip(inv)
  local f = inv.fuse
  if f.locked then
    local id, level = fuser.result(f)
    return "Fuser locked", string.format("Ether %d / %d. Slay monsters to charge it; it fuses into %s. Toggle again (%s) to release it: the ether gathered is lost.", math.floor(f.ether), fuser.NEED, id and items.new(id, level).name or "?", input.label("fuse"))
  end
  if not (f.slots[1] and f.slots[2]) then
    return "Fuser", "Put two common ammo types or attachments in the slots, then lock them in (" .. input.label("fuse") .. "). Kills charge it with ether."
  end
  local id, level = fuser.result(f)
  if not id then
    return "Fuser", level == "max" and ("Together these would go past +" .. items.MAX_LEVEL .. ".") or "These two won't fuse."
  end
  local known = level > 0 or (itembar.isKnown and itembar.isKnown(items.defs[id].kind, items.key(id, level)))
  return "Fuser", "These fuse into " .. (known and items.new(id, level).name or "something new") .. ". Lock them in (" .. input.label("fuse") .. ") and slay " .. fuser.NEED .. " monsters' worth of ether."
end

-- The always-visible bar along the top-left
local function drawBar(inv, u)
  local margin = 6 * u
  local x, y = margin, margin
  local numberFont = font(3 * u)
  for i = 1, inventory.weaponSlots() do
    local size = WEAPON_SIZE * u
    drawSlot(inv, { kind = "weapon", index = i }, x, y, size, u, i == inv.selected or inventory.akimbo())
    shadowPrint(tostring(i), x + u, y + 0.5 * u, numberFont, { 1, 1, 1, 0.7 })
    x = x + size + 2 * u
  end
  x = x + 5 * u
  local itemY = y + (WEAPON_SIZE - ITEM_SIZE) / 2 * u
  -- Which loose items (and items waiting in an unlocked fuser) have a partner
  -- they could be fused with: those get a small teal pip
  local pool = {}
  for i = 1, inventory.ITEM_SLOTS do
    pool[#pool + 1] = inv.items[i]
  end
  if not inv.fuse.locked then
    pool[#pool + 1] = inv.fuse.slots[1]
    pool[#pool + 1] = inv.fuse.slots[2]
  end
  local fusable = {}
  for a = 1, #pool do
    for b = a + 1, #pool do
      if pool[a] and pool[b] and fuser.combine(pool[a], pool[b]) then
        fusable[pool[a]], fusable[pool[b]] = true, true
      end
    end
  end
  local t = love.timer.getTime()
  local function pip(px, py)
    local p = math.max(2, math.floor(2.2 * u))
    local glow = 0.75 + 0.25 * math.sin(t * 5)
    love.graphics.setColor(0.02, 0.06, 0.06, 0.9)
    love.graphics.rectangle("fill", px - 1, py - 1, p + 2, p + 2)
    love.graphics.setColor(FUSE_TEAL[1], FUSE_TEAL[2], FUSE_TEAL[3], glow)
    love.graphics.rectangle("fill", px, py, p, p)
    love.graphics.setColor(0.85, 1, 0.95, glow)
    love.graphics.rectangle("fill", px, py, math.max(1, math.floor(p / 2)), math.max(1, math.floor(p / 2)))
  end
  for i = 1, inventory.ITEM_SLOTS do
    local size = ITEM_SIZE * u
    drawSlot(inv, { kind = "item", index = i }, x, itemY, size, u, false)
    if inv.items[i] and fusable[inv.items[i]] then
      pip(math.floor(x + 1.5 * u), math.floor(itemY + 1.5 * u))
    end
    x = x + size + 2 * u
  end
  drawFuser(inv, x + 5 * u, itemY, u, fusable, pip)
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
  for i = 1, inventory.weaponSlots() do
    local gun = inv.weapons[i]
    if gun then
      local selected = i == inv.selected or inventory.akimbo()
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

  local hint = "Drag ammo between slots; drag a weapon or item off the bar to drop it.   1-3 / wheel: switch   " .. input.label("inventory") .. ": close"
  shadowPrint(hint, math.floor((ww - textFont:getWidth(hint)) / 2), y + 2 * u, textFont, { 1, 1, 1, 0.75 })
end

-- Holding or hovering an item: a pulsing teal frame on every other item on
-- the bar (or in a gun's slots, or the fuser) it can be fused with
local function drawFuseHints(inv, u, mx, my)
  local ref = drag and drag.ref
  local over = not drag and hitTest(mx, my) or nil
  if over then
    ref = over.ref
  end
  if not ref or (ref.kind ~= "item" and ref.kind ~= "gunSlot" and ref.kind ~= "fuse") then
    return
  end
  local a = inv:get(ref)
  if not (a and a.id and items.defs[a.id]) then
    return
  end
  local fuser = require("src.fuser")
  local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 6)
  love.graphics.setLineWidth(math.max(1, u * 0.7))
  for _, box in ipairs(hitboxes) do
    local k = box.ref.kind
    if (k == "item" or k == "gunSlot" or k == "fuse") and box.ref ~= ref and not (ref.kind == box.ref.kind and ref.index == box.ref.index and ref.gun == box.ref.gun) then
      local b = inv:get(box.ref)
      if b and b ~= a and b.id and items.defs[b.id] and fuser.combine(a, b) then
        love.graphics.setColor(FUSE_TEAL[1], FUSE_TEAL[2], FUSE_TEAL[3], 0.35 + 0.65 * pulse)
        local grow = (1 + pulse) * u * 0.5
        love.graphics.rectangle("line", box.x - grow, box.y - grow, box.w + 2 * grow, box.h + 2 * grow, u, u)
      end
    end
  end
end

function itembar.draw(inv, u)
  hitboxes = {}
  if isOpen then
    drawPanel(inv, u)
  end
  drawBar(inv, u * BAR_SCALE)

  local mx, my = love.mouse.getPosition()
  drawFuseHints(inv, u, mx, my)
  if drag then
    local thing = inv:get(drag.ref)
    if thing then
      local size = ITEM_SIZE * u
      drawThing(thing, mx - size / 2, my - size / 2, size, u)
    end
  elseif isOpen then
    local h = hitTest(mx, my)
    local thing = h and h.ref.kind ~= "fuseToggle" and inv:get(h.ref)
    if h and h.ref.kind == "fuseToggle" then
      thing = { name = "", desc = "" }
      thing.name, thing.desc = fuserTip(inv)
      thing.color = FUSE_TEAL
    end
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
-- A gun's picture in the world (lying on the ground, on a shop pedestal): its
-- drawn model at half size, matching the item bar (the old pixel map if none)
function itembar.groundIcon(gun)
  return gunhud.groundImage(gun) or weaponIcon(gun.def)
end

-- Returns true if the click was used by the item bar
function itembar.mousepressed(inv, x, y, button)
  if not isOpen or button ~= 1 then
    return false
  end
  local h = hitTest(x, y)
  if h and h.ref.kind == "fuseToggle" then
    if itembar.onFuseToggle then
      itembar.onFuseToggle()
    end
    return true
  end
  if h and h.ref.kind == "fuse" and inv.fuse.locked then
    return true
  end
  if h and h.ref.kind ~= "perk" and inv:get(h.ref) then
    drag = { ref = h.ref }
  end
  return true
end

-- Set by src.game: called when the fuser's toggle is clicked
itembar.onFuseToggle = nil

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
  if h and h.ref.kind == "fuseToggle" then
    h = nil -- (not a slot: nothing happens)
    drag = nil
    return
  end
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
