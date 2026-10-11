-- The shop room's stock (design doc §9). At the end of the catacombs the shop
-- lays out one generated weapon (on the left) and some ammo types and
-- attachments (to its right) on stone pedestals, each with a price in gold. Standing next to one shows
-- "[E] Buy <name>" (the price floats over every pedestal, red when you can't
-- afford it); E buys it.
--
-- A weapon bought with all three weapon slots full opens the compare prompt
-- first, and is only paid for once you pick which gun to replace.
local compare = require("src.compare")
local effects = require("src.effects")
local guns = require("src.guns")
local inventory = require("src.inventory")
local itembar = require("src.itembar")
local items = require("src.items")

local shop = {}

local stock = {}
local floorY = 0

local REACH = 14
local SPACING = 20
local ITEMS = 4

function shop.clear()
  stock = {}
end

local function roundTo5(n)
  return math.floor(n / 5 + 0.5) * 5
end

-- Generates the stock for the shop room rectangle { x, y, w, h }
function shop.populate(room)
  stock = {}
  floorY = room.y + room.h
  local function add(entry, x)
    entry.x = x
    entry.sold = false
    entry.shop = true -- tells src.game how a compare-prompt choice is paid for
    stock[#stock + 1] = entry
  end

  -- One weapon on the left, then the ammo types and attachments to its right
  local gun = guns.generate(nil, nil, 0.3)
  local fitted = 0
  for s = 1, gun.def.slots do
    if gun.slots[s] then
      fitted = fitted + 1
    end
  end
  add({ kind = "weapon", gun = gun, name = gun.name, price = roundTo5(45 + 25 * fitted + love.math.random(0, 20)) }, room.x + 100)
  local itemsX = room.x + 140
  local used = {}
  for i = 1, ITEMS do
    local item
    repeat
      item = items.random()
    until not used[item.id]
    used[item.id] = true
    add({ kind = "item", item = item, name = item.name, price = roundTo5(20 + love.math.random(0, 15)) }, itemsX + (i - 1) * SPACING)
  end
end

function shop.take(entry, inv)
  inv.gold = inv.gold - entry.price
  entry.sold = true
end

local function nearest(player)
  local px, py = player:center()
  local best, bestDist = nil, REACH
  for _, e in ipairs(stock) do
    if not e.sold then
      local d = math.sqrt((e.x - px) ^ 2 + (floorY - 8 - py) ^ 2)
      if d < bestDist then
        best, bestDist = e, d
      end
    end
  end
  return best
end

-- E: buys the nearest piece of stock. Returns true if it handled the key.
function shop.interact(player)
  local e = nearest(player)
  if not e then
    return false
  end
  local inv = player.inventory
  local px, py = player:center()
  if inv.gold < e.price then
    effects.popup(px, py - 14, "Not enough gold", { 1, 0.45, 0.4 })
    return true
  end
  if e.kind == "item" then
    if not inv:addItem(e.item) then
      effects.popup(px, py - 14, "No room", { 1, 0.5, 0.4 })
      return true
    end
    shop.take(e, inv)
    effects.popup(px, py - 14, e.name, e.item.color)
  else
    for i = 1, inventory.WEAPON_SLOTS do
      if not inv.weapons[i] then
        inv.weapons[i] = e.gun
        shop.take(e, inv)
        effects.popup(px, py - 14, e.name, { 1, 0.9, 0.6 })
        return true
      end
    end
    compare.open(e.gun, e) -- paid for when a weapon to replace is chosen
  end
  return true
end

local function onScreen(e, view)
  return e.x > view.x - 20 and e.x < view.x + view.w + 20 and floorY > view.y - 20 and floorY < view.y + view.h + 20
end

-- Pedestals with the goods on top (before the lighting)
function shop.draw(view)
  for _, e in ipairs(stock) do
    if onScreen(e, view) then
      love.graphics.setColor(0.34, 0.32, 0.38)
      love.graphics.rectangle("fill", e.x - 6, floorY - 5, 12, 5)
      love.graphics.setColor(0.46, 0.44, 0.50)
      love.graphics.rectangle("fill", e.x - 6, floorY - 5, 12, 1)
      if not e.sold then
        if e.kind == "weapon" then
          local icon = itembar.weaponIcon(e.gun.def)
          love.graphics.setColor(1, 1, 1)
          love.graphics.draw(icon, e.x - 8, floorY - 5 - icon:getHeight())
        else
          local c = e.item.color
          love.graphics.setColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
          love.graphics.rectangle("fill", e.x - 3, floorY - 11, 6, 6)
          love.graphics.setColor(c[1], c[2], c[3])
          love.graphics.rectangle("fill", e.x - 2, floorY - 10, 4, 4)
        end
      end
    end
  end
end

function shop.addLights(lighting, view)
  for _, e in ipairs(stock) do
    if not e.sold and onScreen(e, view) then
      lighting.add(e.x, floorY - 9, 28, 1, 0.8, 0.5, 0.5)
    end
  end
end

-- Prices over every pedestal, and the buy prompt for the nearest one (full resolution)
function shop.drawScreen(toScreen, font, player)
  love.graphics.setFont(font)
  local near = (not player.dead) and nearest(player) or nil
  local gold = player.inventory.gold
  local sw, sh = love.graphics.getDimensions()
  for _, e in ipairs(stock) do
    if not e.sold then
      local sx, sy = toScreen(e.x, floorY - 14)
      if sx > -60 and sx < sw + 60 and sy > -20 and sy < sh + 20 then
        local text = e.price .. "g"
        local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy - font:getHeight())
        love.graphics.setColor(0, 0, 0, 0.85)
        love.graphics.print(text, x + 2, y + 2)
        if gold >= e.price then
          love.graphics.setColor(1, 0.86, 0.45)
        else
          love.graphics.setColor(0.85, 0.4, 0.38)
        end
        love.graphics.print(text, x, y)
        if e == near then
          local label = "[E] Buy " .. e.name
          local lx, ly = math.floor(sx - font:getWidth(label) / 2), y - font:getHeight() - 2
          love.graphics.setColor(0, 0, 0, 0.85)
          love.graphics.print(label, lx + 2, ly + 2)
          love.graphics.setColor(1, 0.95, 0.75)
          love.graphics.print(label, lx, ly)
        end
      end
    end
  end
end

return shop
