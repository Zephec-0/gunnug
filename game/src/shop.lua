-- The shop rooms (design doc §9). At the end of each area the shop has:
--   * a DPS dummy at the far left end, a practice range for checking guns
--     (an enemy of kind "dummy", spawned by the area; see src.enemies);
--   * three perk pedestals to its right (free: take one and the others
--     vanish; the perks are rolled when the hunter walks in);
--   * a healing pedestal to their right (ivory, with a glowing heart): each E
--     buys 10% of max health, priced by how much health is missing;
--   * one generated weapon, then ammo types and attachments to its right, on
--     stone pedestals with prices floating over them;
--   * a hatch in the floor (when another area lies below) held shut by a chain.
--     Shoot the chain and the iron plate drops away, opening a shaft down into
--     the next area.
-- Leaving the shop locks it: nothing in it can be bought afterwards.
--
-- A weapon bought with all three weapon slots full opens the compare prompt
-- first, and is only paid for once you pick which gun to replace.
local audio = require("src.audio")
local fontFace = require("src.fonts")
local compare = require("src.compare")
local effects = require("src.effects")
local guns = require("src.guns")
local gunInfo = require("src.gunInfo")
local inventory = require("src.inventory")
local icons = require("src.icons")
local itembar = require("src.itembar")
local items = require("src.items")
local materials = require("src.materials")
local perks = require("src.perks")
local physics = require("src.physics")

local shop = {}

local shops = {} -- one per area: { room, world, floorY, stock, heal, hatch, locked, entered }

local REACH = 14
local SPACING = 20
local ITEMS = 8
local HEAL_FRACTION = 0.1 -- of max health per purchase
local HATCH_DELAY = 0.7 -- seconds between the chain breaking and the plate dropping
local RANGE = 80 -- the DPS dummy's range at the left end; the goods start after it

-- Where the DPS dummy stands in a shop room (x centre, floor y)
function shop.dummySpot(room)
  return room.x + 26, room.y + room.h
end

-- Set by the scene: called with the index of the area below when a shop's hatch
-- is about to open, so that area can be made sure to exist
shop.onHatchBreak = nil

function shop.clear()
  shops = {}
end

local function roundTo5(n)
  return math.floor(n / 5 + 0.5) * 5
end

-- What a stock entry costs now (the Haggler and Greedy Hands perks lower prices)
local function priceOf(entry)
  if entry.price <= 0 then
    return 0
  end
  return math.max(5, roundTo5(entry.price * perks.prod("shopPrice")))
end

-- Creates the shop for the room rectangle { x, y, w, h, hatch? } of an area
-- `level` deep (the heal price rises with it); child: the index of the area
-- its hatch drops into
function shop.populate(room, world, level, child)
  local s = {
    room = room,
    world = world,
    level = level,
    child = child,
    floorY = room.y + room.h,
    stock = {},
    locked = false,
    entered = false,
    heal = { x = room.x + RANGE + 105 },
  }
  shops[#shops + 1] = s
  local function add(entry, x)
    entry.x = x
    entry.sold = false
    entry.shop = true -- tells src.game how a compare-prompt choice is paid for
    entry.owner = s
    s.stock[#s.stock + 1] = entry
  end

  -- Three perk pedestals at the far left; what they hold is rolled on entry
  for i = 1, 3 do
    add({ kind = "perk", name = "", price = 0, hidden = true }, room.x + RANGE + 30 + (i - 1) * 25)
  end

  -- Two weapons, then the ammo types and attachments to their right
  for w = 1, 2 do
    local gun = guns.generate(nil, nil, 0.3)
    local fitted = 0
    for slot = 1, gun.slotCount do
      if gun.slots[slot] then
        fitted = fitted + 1
      end
    end
    add({ kind = "weapon", gun = gun, name = gun.name, price = roundTo5(45 + 25 * fitted + 8 * math.max(0, gun.slotCount - gun.def.slots) + 12 * (gunInfo.gradeIndex(gun) - 1) + love.math.random(0, 20)) }, room.x + RANGE + 155 + (w - 1) * 30)
  end
  local used = {}
  for i = 1, ITEMS do
    local item
    repeat
      item = items.random()
    until not used[item.id]
    used[item.id] = true
    local range = items.rarities[item.rarity].price
    add({ kind = "item", item = item, name = item.name, price = roundTo5(love.math.random(range[1], range[2])) }, room.x + RANGE + 235 + (i - 1) * SPACING)
  end

  local h = room.hatch
  if h then
    s.hatch = {
      x0 = h.x0,
      x1 = h.x1,
      y0 = h.y0,
      y1 = h.y1,
      cx = h.cx,
      chainTop = h.ceilY + 4,
      chainBottom = h.floorY - 3,
      broken = false,
      opened = false,
      timer = 0,
    }
  end
end

function shop.take(entry, inv)
  inv.gold = inv.gold - priceOf(entry)
  entry.sold = true
end

-- Rolls the three perks on offer
local function offerPerks(s)
  local picks = perks.roll(3)
  local n = 0
  for _, e in ipairs(s.stock) do
    if e.kind == "perk" then
      n = n + 1
      local id = picks[n]
      if id then
        e.perkId = id
        e.perk = perks.new(id)
        e.name = e.perk.name
        e.hidden = false
        local c = e.perk.color
        for _ = 1, 10 do
          effects.particle(e.x + (love.math.random() - 0.5) * 8, s.floorY - 14, (love.math.random() - 0.5) * 40, -10 - love.math.random() * 40, 0.6, c, 0, true)
        end
      else
        e.sold = true
      end
    end
  end
end

-- Taking a perk: it is yours, and the other two vanish
local function takePerk(s, e, player)
  perks.add(e.perkId)
  player:refreshMaxHp()
  audio.play("buy")
  e.sold = true
  for _, other in ipairs(s.stock) do
    if other.kind == "perk" and not other.sold then
      other.sold = true
      if other.perk then
        for _ = 1, 10 do
          effects.particle(other.x + (love.math.random() - 0.5) * 8, s.floorY - 14, (love.math.random() - 0.5) * 50, -20 - love.math.random() * 40, 0.5, { 0.6, 0.6, 0.65 }, 100, true)
        end
      end
    end
  end
end

-- The weapon on a pedestal under a world point (for the hover card)
function shop.weaponAt(wx, wy)
  for _, s in ipairs(shops) do
    for _, e in ipairs(s.stock) do
      if e.kind == "weapon" and not e.sold and math.abs(wx - e.x) <= 12 and wy >= s.floorY - 20 and wy <= s.floorY then
        return e.gun, e.x, s.floorY - 22
      end
    end
  end
  return nil
end

-- What the hunter is next to: returns shop, kind ("stock" or "heal"), entry
local function nearest(player)
  local px, py = player:center()
  local best, bestDist = nil, REACH
  local bs, bk, be
  for _, s in ipairs(shops) do
    for _, e in ipairs(s.stock) do
      if not e.sold and not e.hidden then
        local d = math.sqrt((e.x - px) ^ 2 + (s.floorY - 8 - py) ^ 2)
        if d < bestDist then
          best, bestDist, bs, bk, be = e, d, s, "stock", e
        end
      end
    end
    local d = math.sqrt((s.heal.x - px) ^ 2 + (s.floorY - 9 - py) ^ 2)
    if d < bestDist then
      best, bestDist, bs, bk, be = s.heal, d, s, "heal", s.heal
    end
  end
  return bs, bk, be
end

-- Healing is priced by how much health is missing: 8g when nearly full up to
-- 40g when nearly dead, for each 10% of max health, and 80% dearer with each
-- area further down (shop s of area s.level)
local HEAL_AREA_RISE = 0.8

local function healCost(player, s)
  local missing = (player.maxHp - player.hp) / player.maxHp
  local area = 1 + (s.level - 1) * HEAL_AREA_RISE
  return roundTo5((8 + 32 * missing) * area * perks.prod("healPrice"))
end

local function healAmount(player)
  return math.min(player.maxHp - player.hp, math.ceil(player.maxHp * HEAL_FRACTION))
end

-- E: buys from the nearest pedestal. Returns true if it handled the key.
function shop.interact(player)
  local s, kind, e = nearest(player)
  if not s then
    return false
  end
  local inv = player.inventory
  local px, py = player:center()
  local function say(text, color)
    effects.popup(px, py - 14, text, color)
  end
  if s.locked then
    say("The shop is closed", { 0.8, 0.8, 0.85 })
    audio.play("deny")
    return true
  end
  if kind == "heal" then
    local amount = healAmount(player)
    if amount <= 0 then
      say("Already at full health", { 0.8, 0.9, 0.8 })
      audio.play("deny", 0.6)
      return true
    end
    local cost = healCost(player, s)
    if inv.gold < cost then
      say("Not enough gold", { 1, 0.45, 0.4 })
      audio.play("deny")
      return true
    end
    inv.gold = inv.gold - cost
    player.hp = math.min(player.maxHp, player.hp + amount)
    audio.play("heal")
    say("+" .. amount .. " HP", { 0.5, 1, 0.55 })
    for _ = 1, 14 do
      effects.particle(s.heal.x + (love.math.random() - 0.5) * 10, s.floorY - 18, (love.math.random() - 0.5) * 30, -20 - love.math.random() * 50, 0.8, { 1, 0.6, 0.65 }, -20, true)
    end
    return true
  end
  if e.kind == "perk" then
    takePerk(s, e, player)
    say(e.name, e.perk.color)
    return true
  end
  if inv.gold < priceOf(e) then
    say("Not enough gold", { 1, 0.45, 0.4 })
    audio.play("deny")
    return true
  end
  if e.kind == "item" then
    if not inv:addItem(e.item) then
      say("No room", { 1, 0.5, 0.4 })
      audio.play("deny")
      return true
    end
    shop.take(e, inv)
    audio.play("buy")
    say(e.name, e.item.color)
  else
    local slot = inv:freeWeaponSlot()
    if slot then
      inv.weapons[slot] = e.gun
      shop.take(e, inv)
      audio.play("buy")
      return true
    end
    compare.open(e.gun, e) -- paid for when a weapon to replace is chosen
  end
  return true
end

-- The hatch chain ------------------------------------------------------------

-- Is there a chain link at this pixel? (bullets test this before terrain)
function shop.chainAt(px, py)
  for _, s in ipairs(shops) do
    local h = s.hatch
    if h and not h.broken and px >= h.cx - 1 and px <= h.cx and py >= h.chainTop and py <= h.chainBottom then
      return s
    end
  end
  return nil
end

-- Snaps the chain (a bullet hit it, or an explosion reached it)
function shop.breakChain(s)
  local h = s.hatch
  if not h or h.broken then
    return
  end
  h.broken = true
  h.timer = HATCH_DELAY
  audio.play("clank")
  for i = 1, 14 do
    local y = h.chainTop + (h.chainBottom - h.chainTop) * love.math.random()
    effects.particle(h.cx, y, (love.math.random() - 0.5) * 60, -20 + love.math.random() * 30, 0.7, { 0.6, 0.62, 0.7 }, 520)
  end
  -- The area below must exist before the floor opens onto it
  if shop.onHatchBreak then
    shop.onHatchBreak(s.child)
  end
end

-- Explosions snap the chain too
function shop.explosion(x, y, radius)
  for _, s in ipairs(shops) do
    local h = s.hatch
    if h and not h.broken and math.abs(x - h.cx) < radius + 2 and y > h.chainTop - radius and y < h.chainBottom + radius then
      shop.breakChain(s)
    end
  end
end

local function openHatch(s)
  local h = s.hatch
  h.opened = true
  audio.play("hatch")
  local world = s.world
  for y = h.y0, h.y1 do
    for x = h.x0, h.x1 do
      world:setRaw(x, y, materials.AIR)
    end
  end
  world:repaintRect(h.x0 - 2, h.y0 - 2, h.x1 + 2, h.y1 + 2)
  physics.rebuildRegion(h.x0, h.y0, h.x1, h.y1)
  for _ = 1, 30 do
    local x = h.x0 + (h.x1 - h.x0) * love.math.random()
    effects.particle(x, h.y0 + 1, (love.math.random() - 0.5) * 40, 10 + love.math.random() * 40, 1.0, { 0.40, 0.41, 0.48 }, 520)
  end
end

local function inside(room, px, py, margin)
  return px > room.x - margin and px < room.x + room.w + margin and py > room.y - margin and py < room.y + room.h + margin
end

-- The hatch plate drops a moment after the chain snaps, and leaving the shop
-- locks it
function shop.update(dt, player)
  local px, py = player:center()
  for _, s in ipairs(shops) do
    s.px = px
    for _, e in ipairs(s.stock) do
      if e.kind == "perk" then
        -- Perks stir as the hunter comes near: rising, glowing, shedding sparks
        local close = (not e.sold and not e.hidden and not s.locked and math.abs(e.x - px) < 40 and math.abs(s.floorY - py) < 30) and 1 or 0
        e.near = (e.near or 0) + (close - (e.near or 0)) * math.min(1, dt * 6)
        if close == 1 and love.math.random() < dt * 8 then
          local c = e.perk.color
          effects.particle(e.x + (love.math.random() - 0.5) * 8, s.floorY - 7, (love.math.random() - 0.5) * 10, -14 - love.math.random() * 14, 0.9, c, -6, true)
        end
      end
    end
    local h = s.hatch
    if h and h.broken and not h.opened then
      h.timer = h.timer - dt
      if h.timer <= 0 then
        openHatch(s)
      end
    end
    if not s.locked then
      if inside(s.room, px, py, 0) then
        if not s.entered then
          offerPerks(s)
        end
        s.entered = true
      elseif s.entered and not inside(s.room, px, py, 10) then
        s.locked = true
        effects.popup(px, py - 14, "The shop closes behind you", { 0.8, 0.8, 0.88 })
      end
    end
  end
end

-- Drawing --------------------------------------------------------------------

local function onScreen(s, x, view)
  return x > view.x - 24 and x < view.x + view.w + 24 and s.floorY > view.y - 30 and s.floorY < view.y + view.h + 30
end

-- Any part of the shop room in view
local function roomOnScreen(s, view)
  return s.room.x < view.x + view.w + 24 and s.room.x + s.room.w > view.x - 24 and s.floorY > view.y - 30 and s.floorY < view.y + view.h + 30
end

-- The ivory healing pedestal with a glowing heart floating over it
local function drawHealPedestal(s)
  local x, f = s.heal.x, s.floorY
  love.graphics.setColor(0.80, 0.76, 0.66)
  love.graphics.rectangle("fill", x - 7, f - 3, 14, 3)
  love.graphics.setColor(0.90, 0.86, 0.76)
  love.graphics.rectangle("fill", x - 4, f - 14, 8, 11)
  love.graphics.setColor(0.72, 0.68, 0.58)
  love.graphics.rectangle("fill", x + 2, f - 14, 2, 11)
  love.graphics.setColor(0.94, 0.90, 0.80)
  love.graphics.rectangle("fill", x - 6, f - 17, 12, 3)
  love.graphics.setColor(0.78, 0.74, 0.64)
  love.graphics.rectangle("fill", x - 6, f - 15, 12, 1)
end

-- Dressing: the room is a little market hall ---------------------------------

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

-- A stepped stone dais for a perk
local function drawDais(s, e)
  local f = s.floorY
  love.graphics.setColor(0.26, 0.25, 0.31)
  rect(e.x - 9, f - 2, 18, 2)
  love.graphics.setColor(0.34, 0.33, 0.40)
  rect(e.x - 7, f - 4, 14, 2)
  love.graphics.setColor(0.42, 0.40, 0.48)
  rect(e.x - 5, f - 6, 10, 2)
  love.graphics.setColor(0.54, 0.52, 0.60)
  rect(e.x - 5, f - 6, 10, 1)
end

-- Banners hanging from the ceiling beams, swaying very slightly
local BANNER_COLORS = { { 0.45, 0.10, 0.14 }, { 0.12, 0.32, 0.34 }, { 0.40, 0.28, 0.10 } }
local function drawBanners(s)
  local r, t = s.room, love.timer.getTime()
  for i, fx in ipairs({ 0.16, 0.50, 0.80 }) do
    local bx, top = r.x + math.floor(r.w * fx), r.y
    local sway = math.sin(t * 0.8 + i * 2) * 1.3
    local col = BANNER_COLORS[i]
    love.graphics.setColor(0.22, 0.15, 0.10)
    rect(bx - 6, top, 12, 1)
    for row = 0, 15 do
      if not (row >= 14 and row <= 15) then
        local off = sway * row / 15
        local shade = 1 - 0.18 * ((row + i) % 2)
        love.graphics.setColor(col[1] * shade, col[2] * shade, col[3] * shade)
        rect(bx - 4 + off, top + 1 + row, 8, 1)
      else
        local off = sway
        love.graphics.setColor(col[1] * 0.8, col[2] * 0.8, col[3] * 0.8)
        rect(bx - 4 + off, top + 1 + row, 3, 1)
        rect(bx + 1 + off, top + 1 + row, 3, 1)
      end
    end
    -- Gold trim and a little sigil
    local off = sway * 0.4
    love.graphics.setColor(0.85, 0.68, 0.28)
    rect(bx - 4 + off * 0.2, top + 2, 8, 1)
    rect(bx - 1 + off, top + 6, 2, 1)
    rect(bx - 2 + off, top + 7, 4, 1)
    rect(bx - 1 + off, top + 8, 2, 1)
  end
end

-- A runner of red cloth along the floor, a barrel, and a stack of crates
local function drawFloorDressing(s)
  local r, f = s.room, s.floorY
  love.graphics.setColor(0.40, 0.09, 0.12)
  rect(r.x + RANGE + 14, f - 1, 415, 1)
  love.graphics.setColor(0.80, 0.62, 0.24)
  for x = r.x + RANGE + 14, r.x + RANGE + 428, 7 do
    rect(x, f - 1, 3, 1)
  end
  -- A chalk line marking the end of the dummy's range
  love.graphics.setColor(0.62, 0.60, 0.56)
  for x = r.x + RANGE - 30, r.x + RANGE - 26 do
    rect(x, f - 1, 1, 1)
  end
  -- Barrel at the edge of the range
  local bx = r.x + RANGE - 6
  love.graphics.setColor(0.36, 0.24, 0.14)
  rect(bx, f - 11, 9, 11)
  love.graphics.setColor(0.46, 0.32, 0.20)
  rect(bx + 1, f - 11, 2, 11)
  love.graphics.setColor(0.18, 0.18, 0.22)
  rect(bx, f - 9, 9, 1)
  rect(bx, f - 3, 9, 1)
  -- Crates stacked between the merchant and the hatch
  local cx = r.x + RANGE + 520
  for i = 0, 1 do
    local y = f - 10 - i * 10
    love.graphics.setColor(0.42, 0.30, 0.18)
    rect(cx + i * 3, y, 10, 10)
    love.graphics.setColor(0.28, 0.19, 0.12)
    rect(cx + i * 3, y, 10, 1)
    rect(cx + i * 3, y + 9, 10, 1)
    rect(cx + i * 3, y, 1, 10)
    rect(cx + i * 3 + 9, y, 1, 10)
    rect(cx + i * 3 + 1, y + 4, 8, 1)
  end
end

-- The merchant: a hooded figure behind a counter, breathing slowly
local function merchantX(s)
  return s.room.x + RANGE + 455
end

local function drawMerchant(s)
  local mx, f, t = merchantX(s), s.floorY, love.timer.getTime()
  local breathe = math.floor(math.sin(t * 1.6) * 0.5 + 0.6)
  -- Robe and hood
  love.graphics.setColor(0.20, 0.14, 0.22)
  rect(mx - 4, f - 14 + breathe, 9, 11)
  love.graphics.setColor(0.27, 0.20, 0.30)
  rect(mx - 3, f - 18 + breathe, 7, 5)
  rect(mx - 2, f - 19 + breathe, 5, 1)
  love.graphics.setColor(0.07, 0.05, 0.09)
  rect(mx - 2, f - 17 + breathe, 5, 3)
  -- Hands resting on the counter, with a ring
  love.graphics.setColor(0.60, 0.55, 0.50)
  rect(mx - 6, f - 9 + breathe, 2, 1)
  rect(mx + 5, f - 9 + breathe, 2, 1)
  love.graphics.setColor(0.85, 0.68, 0.28)
  rect(mx + 6, f - 9 + breathe, 1, 1)
  -- The counter, with a few trinkets on it
  love.graphics.setColor(0.36, 0.25, 0.16)
  rect(mx - 15, f - 8, 30, 8)
  love.graphics.setColor(0.50, 0.37, 0.25)
  rect(mx - 16, f - 9, 32, 2)
  love.graphics.setColor(0.26, 0.18, 0.12)
  rect(mx - 12, f - 6, 1, 6)
  rect(mx + 12, f - 6, 1, 6)
  love.graphics.setColor(0.45, 0.80, 0.85)
  rect(mx - 11, f - 11, 2, 2)
  love.graphics.setColor(0.85, 0.35, 0.40)
  rect(mx - 8, f - 10, 2, 1)
  love.graphics.setColor(0.60, 0.60, 0.68)
  rect(mx + 3, f - 12, 1, 3)
  rect(mx + 9, f - 12, 3, 3)
  love.graphics.setColor(0.2, 0.17, 0.12)
  rect(mx + 9, f - 12, 3, 1)
end

local function drawMerchantEyes(s)
  local mx, f, t = merchantX(s), s.floorY, love.timer.getTime()
  local breathe = math.floor(math.sin(t * 1.6) * 0.5 + 0.6)
  if s.locked then
    love.graphics.setColor(0.35, 0.33, 0.30) -- shut for the day
    rect(mx - 1, f - 15 + breathe, 3, 1)
    return
  end
  local blink = (t % 5.3) < 0.12
  local look = math.max(-1, math.min(1, math.floor(((s.px or mx) - mx) / 50)))
  love.graphics.setColor(1, 0.85, 0.40)
  if blink then
    rect(mx - 2 + look, f - 15 + breathe, 5, 1)
  else
    rect(mx - 2 + look, f - 15 + breathe, 1, 1)
    rect(mx + 1 + look, f - 15 + breathe, 1, 1)
  end
  -- The lantern on the counter
  love.graphics.setColor(1, 0.72, 0.30)
  rect(mx + 13, f - 13, 2, 3 + math.floor(math.sin(t * 9) * 0.5 + 0.5))
  love.graphics.setColor(1, 0.95, 0.7)
  rect(mx + 13, f - 12, 1, 1)
end

-- Pedestals with the goods on top, the healing pedestal, and the hatch chain
-- (before the lighting)
function shop.draw(view)
  for _, s in ipairs(shops) do
    if roomOnScreen(s, view) then
      drawBanners(s)
      drawFloorDressing(s)
      drawMerchant(s)
      drawHealPedestal(s)
      for _, e in ipairs(s.stock) do
        if e.kind == "perk" then
          drawDais(s, e)
        else
          love.graphics.setColor(0.34, 0.32, 0.38)
          love.graphics.rectangle("fill", e.x - 6, s.floorY - 5, 12, 5)
          love.graphics.setColor(0.46, 0.44, 0.50)
          love.graphics.rectangle("fill", e.x - 6, s.floorY - 5, 12, 1)
        end
        if not e.sold and not e.hidden then
          local dim = s.locked and 0.45 or 1
          if e.kind == "perk" then
            -- (the perk itself floats over its pedestal, drawn glowing)
          elseif e.kind == "weapon" then
            local icon = itembar.weaponIcon(e.gun.def)
            love.graphics.setColor(dim, dim, dim)
            love.graphics.draw(icon, e.x - 8, s.floorY - 5 - icon:getHeight())
          else
            local c = e.item.color
            local img = icons.get(e.item)
            if img then
              love.graphics.setColor(dim, dim, dim)
              love.graphics.draw(img, e.x - 4, s.floorY - 14)
            else
              love.graphics.setColor(c[1] * 0.45 * dim, c[2] * 0.45 * dim, c[3] * 0.45 * dim)
              love.graphics.rectangle("fill", e.x - 3, s.floorY - 11, 6, 6)
              love.graphics.setColor(c[1] * dim, c[2] * dim, c[3] * dim)
              love.graphics.rectangle("fill", e.x - 2, s.floorY - 10, 4, 4)
            end
            local rarity = e.item.rarity ~= "common" and items.rarities[e.item.rarity]
            if rarity then
              love.graphics.setColor(rarity.border[1] * dim, rarity.border[2] * dim, rarity.border[3] * dim)
              love.graphics.rectangle("line", e.x - 4.5, s.floorY - 14.5, 9, 9)
            end
          end
        end
      end
      local h = s.hatch
      if h then
        -- Bracket in the ceiling, a chain of links down to a latch on the plate
        love.graphics.setColor(0.30, 0.31, 0.37)
        love.graphics.rectangle("fill", h.cx - 3, h.chainTop - 4, 6, 3)
        if not h.broken then
          for y = h.chainTop, h.chainBottom - 3, 3 do
            love.graphics.setColor(0.50, 0.52, 0.60)
            love.graphics.rectangle("fill", h.cx - 1, y, 2, 2)
            love.graphics.setColor(0.32, 0.33, 0.40)
            love.graphics.rectangle("fill", h.cx - 1, y + 2, 2, 1)
          end
          love.graphics.setColor(0.42, 0.43, 0.50)
          love.graphics.rectangle("fill", h.cx - 3, s.floorY - 3, 6, 3)
          love.graphics.setColor(0.60, 0.50, 0.28)
          love.graphics.rectangle("fill", h.cx - 1, s.floorY - 3, 2, 2)
        else
          -- A few links left dangling from the bracket
          for y = h.chainTop, h.chainTop + 6, 3 do
            love.graphics.setColor(0.50, 0.52, 0.60)
            love.graphics.rectangle("fill", h.cx - 1, y, 2, 2)
          end
        end
      end
    end
  end
end

function shop.drawEmissive(view)
  local t = love.timer.getTime()
  for _, s in ipairs(shops) do
    if roomOnScreen(s, view) then
      drawMerchantEyes(s)
      -- Runes carved into each perk dais, glowing brighter as the hunter nears
      for _, e in ipairs(s.stock) do
        if e.kind == "perk" and not e.sold then
          local c = (e.hidden or not e.perk) and { 0.45, 0.50, 0.60 } or e.perk.color
          local glow = (s.locked and 0.2 or 0.55) + 0.4 * (e.near or 0)
          love.graphics.setColor(c[1] * glow, c[2] * glow, c[3] * glow)
          rect(e.x - 7, s.floorY - 3, 1, 1)
          rect(e.x - 4, s.floorY - 3, 1, 1)
          rect(e.x + 3, s.floorY - 3, 1, 1)
          rect(e.x + 6, s.floorY - 3, 1, 1)
          rect(e.x - 1, s.floorY - 5, 3, 1)
        end
      end
      -- Perks float and glow over their pedestals
      for _, e in ipairs(s.stock) do
        if e.kind == "perk" and not e.sold and not e.hidden then
          local c = e.perk.color
          local k = s.locked and 0.35 or 1
          local near = e.near or 0
          local bob = math.floor(math.sin(t * 2 + e.x) * 1.5 - near * 2)
          local y = s.floorY - 21 + bob
          local pulse = 0.8 + 0.2 * math.sin(t * 3 + e.x) + 0.3 * near
          -- A soft halo, then the perk's icon floating over its dais
          love.graphics.setColor(c[1] * pulse * k, c[2] * pulse * k, c[3] * pulse * k, 0.35)
          love.graphics.rectangle("fill", e.x - 7, y - 3, 14, 14)
          love.graphics.setColor(c[1] * pulse * k, c[2] * pulse * k, c[3] * pulse * k, 0.35)
          love.graphics.rectangle("fill", e.x - 5, y - 5, 10, 18)
          local img = icons.get(e.perk)
          if img then
            love.graphics.setColor(k, k, k)
            love.graphics.draw(img, e.x - 4, y)
          end
          local rarity = e.perk.rarity ~= "common" and items.rarities[e.perk.rarity]
          if rarity then
            love.graphics.setColor(rarity.border[1] * k, rarity.border[2] * k, rarity.border[3] * k)
            love.graphics.rectangle("line", e.x - 4.5, y - 0.5, 9, 9)
          end
        end
      end
      -- The floating heart
      local x, y = s.heal.x, s.floorY - 25 + math.floor(math.sin(t * 2) * 1.5)
      local pulse = 0.8 + 0.2 * math.sin(t * 3)
      local k = s.locked and 0.35 or 1
      love.graphics.setColor(0.95 * pulse * k, 0.30 * k, 0.40 * k)
      love.graphics.rectangle("fill", x - 3, y - 1, 2, 2)
      love.graphics.rectangle("fill", x + 1, y - 1, 2, 2)
      love.graphics.rectangle("fill", x - 3, y, 6, 2)
      love.graphics.rectangle("fill", x - 2, y + 2, 4, 1)
      love.graphics.rectangle("fill", x - 1, y + 3, 2, 1)
      love.graphics.setColor(1 * k, 0.75 * k, 0.78 * k)
      love.graphics.rectangle("fill", x - 2, y - 1, 1, 1)
    end
  end
end

function shop.addLights(lighting, view)
  for _, s in ipairs(shops) do
    if roomOnScreen(s, view) and not s.locked then
      lighting.add(merchantX(s) + 14, s.floorY - 12, 70, 1, 0.78, 0.45, 0.8)
    end
    if onScreen(s, s.heal.x, view) and not s.locked then
      lighting.add(s.heal.x, s.floorY - 22, 38, 1, 0.78, 0.7, 0.5)
    end
    for _, e in ipairs(s.stock) do
      if not e.sold and not e.hidden and not s.locked and onScreen(s, e.x, view) then
        if e.kind == "perk" then
          local c = e.perk.color
          lighting.add(e.x, s.floorY - 12, 34, c[1], c[2], c[3], 0.7)
        else
          lighting.add(e.x, s.floorY - 9, 28, 1, 0.8, 0.5, 0.5)
        end
      end
    end
  end
end

-- Prices over every pedestal, and the buy prompt for the nearest one (full resolution)
function shop.drawScreen(toScreen, font, player)
  love.graphics.setFont(font)
  local ns, nkind, nentry
  if not player.dead then
    ns, nkind, nentry = nearest(player)
  end
  local gold = player.inventory.gold
  local sw, sh = love.graphics.getDimensions()

  local function label(text, sx, sy, color, grade)
    if grade then
      local x, y = math.floor(sx - fontFace.gradedWidth(font, text, grade) / 2), math.floor(sy - font:getHeight())
      fontFace.printGraded(font, text, grade, x, y, color, 2)
      return y
    end
    local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy - font:getHeight())
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.print(text, x + 2, y + 2)
    love.graphics.setColor(color)
    love.graphics.print(text, x, y)
    return y
  end

  for _, s in ipairs(shops) do
    if not s.locked then
      -- Healing
      local hx, hy = toScreen(s.heal.x, s.floorY - 32)
      if hx > -80 and hx < sw + 80 and hy > -20 and hy < sh + 20 then
        local amount = healAmount(player)
        local price
        if amount > 0 then
          price = healCost(player, s)
          label(price .. "g", hx, hy, gold >= price and { 0.95, 0.97, 1 } or { 0.85, 0.4, 0.38 })
        else
          label("Full health", hx, hy, { 0.7, 0.85, 0.7 })
        end
        if ns == s and nkind == "heal" then
          label("[E] Heal +" .. math.max(amount, 0) .. " HP", hx, hy - font:getHeight() - 4, { 0.98, 0.99, 1 })
        end
      end
      for _, e in ipairs(s.stock) do
        if not e.sold and not e.hidden then
          local sx, sy = toScreen(e.x, s.floorY - (e.kind == "perk" and 22 or 14))
          if sx > -60 and sx < sw + 60 and sy > -20 and sy < sh + 20 then
            local price = priceOf(e)
            local y = sy
            if e.kind ~= "perk" then
              y = label(price .. "g", sx, sy, gold >= price and { 0.95, 0.97, 1 } or { 0.85, 0.4, 0.38 })
            end
            if e == nentry then
              local thing = e.perk or e.item
              local title = (e.kind == "perk" and "[E] Take " or "[E] Buy ") .. e.name
              if thing and thing.rarity ~= "common" then
                title = title .. " (" .. items.rarities[thing.rarity].name .. ")"
              end
              y = label(title, sx, y - 2, thing and thing.rarity == "cursed" and { 1, 0.55, 0.5 } or { 0.98, 0.99, 1 }, e.kind == "weapon" and gunInfo.grade(e.gun) or nil)
              if thing and thing.desc then
                -- The effect, wrapped in a box above the prompt
                local width = 460
                local _, lines = font:getWrap(thing.desc, width)
                local top = y - 4 - #lines * font:getHeight()
                love.graphics.setColor(0, 0, 0, 0.8)
                love.graphics.printf(thing.desc, math.floor(sx - width / 2) + 2, top + 2, width, "center")
                love.graphics.setColor(0.9, 0.88, 0.82)
                love.graphics.printf(thing.desc, math.floor(sx - width / 2), top, width, "center")
              end
            end
          end
        end
      end
    elseif ns == s then
      local sx, sy = toScreen(s.floorY and (nentry.x) or 0, s.floorY - 16)
      label("Closed", sx, sy, { 0.65, 0.65, 0.72 })
    end
  end
end

return shop
