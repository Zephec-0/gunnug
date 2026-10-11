-- The shop rooms (design doc §9). At the end of each area the shop has:
--   * a healing pedestal on the left (ivory, with a glowing heart): each E buys
--     10% of max health, priced by how much health is missing;
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
local compare = require("src.compare")
local effects = require("src.effects")
local guns = require("src.guns")
local inventory = require("src.inventory")
local itembar = require("src.itembar")
local items = require("src.items")
local materials = require("src.materials")
local physics = require("src.physics")

local shop = {}

local shops = {} -- one per area: { room, world, floorY, stock, heal, hatch, locked, entered }

local REACH = 14
local SPACING = 20
local ITEMS = 4
local HEAL_FRACTION = 0.1 -- of max health per purchase
local HATCH_DELAY = 0.7 -- seconds between the chain breaking and the plate dropping

-- Set by the scene: called with the shop's area number when its hatch is about
-- to open, so the area below can be made sure to exist
shop.onHatchBreak = nil

function shop.clear()
  shops = {}
end

local function roundTo5(n)
  return math.floor(n / 5 + 0.5) * 5
end

-- Creates the shop for the room rectangle { x, y, w, h, hatch? } of area `level`
function shop.populate(room, world, level)
  local s = {
    room = room,
    world = world,
    level = level,
    floorY = room.y + room.h,
    stock = {},
    locked = false,
    entered = false,
    heal = { x = room.x + 45 },
  }
  shops[#shops + 1] = s
  local function add(entry, x)
    entry.x = x
    entry.sold = false
    entry.shop = true -- tells src.game how a compare-prompt choice is paid for
    entry.owner = s
    s.stock[#s.stock + 1] = entry
  end

  -- One weapon, then the ammo types and attachments to its right
  local gun = guns.generate(nil, nil, 0.3)
  local fitted = 0
  for slot = 1, gun.def.slots do
    if gun.slots[slot] then
      fitted = fitted + 1
    end
  end
  add({ kind = "weapon", gun = gun, name = gun.name, price = roundTo5(45 + 25 * fitted + love.math.random(0, 20)) }, room.x + 95)
  local used = {}
  for i = 1, ITEMS do
    local item
    repeat
      item = items.random()
    until not used[item.id]
    used[item.id] = true
    add({ kind = "item", item = item, name = item.name, price = roundTo5(20 + love.math.random(0, 15)) }, room.x + 125 + (i - 1) * SPACING)
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
  inv.gold = inv.gold - entry.price
  entry.sold = true
end

-- What the hunter is next to: returns shop, kind ("stock" or "heal"), entry
local function nearest(player)
  local px, py = player:center()
  local best, bestDist = nil, REACH
  local bs, bk, be
  for _, s in ipairs(shops) do
    for _, e in ipairs(s.stock) do
      if not e.sold then
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

-- Healing is priced by how much health is missing: 10g when nearly full up to
-- 50g when nearly dead, for each 10% of max health
local function healCost(player)
  local missing = (player.maxHp - player.hp) / player.maxHp
  return roundTo5(10 + 40 * missing)
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
    local cost = healCost(player)
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
  if inv.gold < e.price then
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
    for i = 1, inventory.WEAPON_SLOTS do
      if not inv.weapons[i] then
        inv.weapons[i] = e.gun
        shop.take(e, inv)
        audio.play("buy")
        say(e.name, { 1, 0.9, 0.6 })
        return true
      end
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
    shop.onHatchBreak(s.level)
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
    local h = s.hatch
    if h and h.broken and not h.opened then
      h.timer = h.timer - dt
      if h.timer <= 0 then
        openHatch(s)
      end
    end
    if not s.locked then
      if inside(s.room, px, py, 0) then
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

-- Pedestals with the goods on top, the healing pedestal, and the hatch chain
-- (before the lighting)
function shop.draw(view)
  for _, s in ipairs(shops) do
    if onScreen(s, s.heal.x, view) or (s.hatch and onScreen(s, s.hatch.cx, view)) then
      drawHealPedestal(s)
      for _, e in ipairs(s.stock) do
        love.graphics.setColor(0.34, 0.32, 0.38)
        love.graphics.rectangle("fill", e.x - 6, s.floorY - 5, 12, 5)
        love.graphics.setColor(0.46, 0.44, 0.50)
        love.graphics.rectangle("fill", e.x - 6, s.floorY - 5, 12, 1)
        if not e.sold then
          local dim = s.locked and 0.45 or 1
          if e.kind == "weapon" then
            local icon = itembar.weaponIcon(e.gun.def)
            love.graphics.setColor(dim, dim, dim)
            love.graphics.draw(icon, e.x - 8, s.floorY - 5 - icon:getHeight())
          else
            local c = e.item.color
            love.graphics.setColor(c[1] * 0.45 * dim, c[2] * 0.45 * dim, c[3] * 0.45 * dim)
            love.graphics.rectangle("fill", e.x - 3, s.floorY - 11, 6, 6)
            love.graphics.setColor(c[1] * dim, c[2] * dim, c[3] * dim)
            love.graphics.rectangle("fill", e.x - 2, s.floorY - 10, 4, 4)
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
    if onScreen(s, s.heal.x, view) then
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
    if onScreen(s, s.heal.x, view) and not s.locked then
      lighting.add(s.heal.x, s.floorY - 22, 38, 1, 0.78, 0.7, 0.5)
    end
    for _, e in ipairs(s.stock) do
      if not e.sold and not s.locked and onScreen(s, e.x, view) then
        lighting.add(e.x, s.floorY - 9, 28, 1, 0.8, 0.5, 0.5)
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

  local function label(text, sx, sy, color)
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
          price = healCost(player)
          label(price .. "g", hx, hy, gold >= price and { 1, 0.86, 0.45 } or { 0.85, 0.4, 0.38 })
        else
          label("Full health", hx, hy, { 0.7, 0.85, 0.7 })
        end
        if ns == s and nkind == "heal" then
          label("[E] Heal +" .. math.max(amount, 0) .. " HP", hx, hy - font:getHeight() - 4, { 1, 0.95, 0.75 })
        end
      end
      for _, e in ipairs(s.stock) do
        if not e.sold then
          local sx, sy = toScreen(e.x, s.floorY - 14)
          if sx > -60 and sx < sw + 60 and sy > -20 and sy < sh + 20 then
            local y = label(e.price .. "g", sx, sy, gold >= e.price and { 1, 0.86, 0.45 } or { 0.85, 0.4, 0.38 })
            if e == nentry then
              label("[E] Buy " .. e.name, sx, y - 2, { 1, 0.95, 0.75 })
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
