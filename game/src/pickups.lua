-- Things lying in the world that the hunter picks up by walking over them
-- (design doc §9, §9a). For now only gold: little coins that spill out of
-- dead monsters, broken crates and dug-out gold ore, bounce around on the
-- terrain, and are drawn to the hunter when he comes close.
--
-- A coin that lands and isn't picked up disappears 7 seconds later (its gold
-- is lost), blinking for the last second and a half.
--
-- A pickup is { kind, value, x, y, vx, vy, ... }. Coins are simulated per
-- pixel like particles (cheap, so hundreds can lie around) rather than as
-- Box2D bodies.
local input = require("src.input")
local audio = require("src.audio")
local config = require("src.config")
local effects = require("src.effects")
local guns = require("src.guns")
local inventory = require("src.inventory")
local itembar = require("src.itembar")
local perks = require("src.perks")
local glyphs = require("src.glyphs")
local icons = require("src.icons")
local items = require("src.items")

local pickups = {}

local list = {}

local MAX_PICKUPS = 400
local PICKUP_RADIUS = 7 -- touching distance to the hunter's centre
local MAGNET_RANGE = 36
local MAGNET_DELAY = 0.45 -- freshly spilled coins can't be grabbed for this long
local GRAVITY = config.gravity * 0.8
local DESPAWN_TIME = 7 -- a coin that has hit the ground vanishes after this long
local FADE_TIME = 1.5 -- it blinks for the last stretch
local overflow = 0 -- value of coins removed to stay under the cap; added to the next coin
pickups.extraMagnet = 0 -- extra pickup range from the held gun (Magnetic Loader)

function pickups.clear()
  list = {}
  overflow = 0
end

function pickups.count()
  return #list
end

-- Drops an ammo type or attachment (an item from src.items) at (x, y),
-- optionally thrown with a velocity. It never despawns, and is only picked
-- up when the hunter presses E next to it (pickups.interact) and has a free
-- item slot.
function pickups.dropItem(x, y, item, vx, vy)
  list[#list + 1] = {
    kind = "item",
    item = item,
    value = 0,
    x = x,
    y = y,
    vx = vx or (love.math.random() - 0.5) * 60,
    vy = vy or (-80 - love.math.random() * 40),
    age = 0,
    sparkle = love.math.random() * 6,
  }
end

-- Drops a weapon (a gun from src.guns, fitted items and all) at (x, y). Picked
-- up with E: into a free weapon slot, or via the compare prompt (src.compare,
-- through pickups.onWeaponFull) when all slots are full.
function pickups.dropWeapon(x, y, gun, vx, vy)
  list[#list + 1] = {
    kind = "weapon",
    gun = gun,
    value = 0,
    x = x,
    y = y,
    vx = vx or (love.math.random() - 0.5) * 60,
    vy = vy or (-80 - love.math.random() * 40),
    age = 0,
    sparkle = love.math.random() * 6,
  }
end

-- Chance-based drop of a generated weapon
function pickups.maybeDropWeapon(x, y, chance, fitChance)
  if love.math.random() < chance then
    pickups.dropWeapon(x, y, guns.generate(nil, nil, fitChance))
  end
end

-- Set by src.game: called with the weapon pickup when the hunter tries to
-- pick it up but all weapon slots are full
pickups.onWeaponFull = nil

function pickups.remove(p)
  for i, q in ipairs(list) do
    if q == p then
      table.remove(list, i)
      return
    end
  end
end

-- Everything lying about (for tests)
function pickups.all()
  return list
end

-- The weapon lying under a world point (so hovering the mouse over it can
-- show what it is). Returns the gun and the point to float its card above.
function pickups.weaponAt(wx, wy)
  for _, p in ipairs(list) do
    if p.kind == "weapon" then
      local icon = itembar.groundIcon(p.gun)
      local w, h = icon:getWidth(), icon:getHeight()
      if math.abs(wx - p.x) <= w / 2 + 4 and wy >= p.y - h - 5 and wy <= p.y + 5 then
        return p.gun, p.x, p.y - h - 4
      end
    end
  end
  return nil
end

-- Chance-based drop of a random item
function pickups.maybeDropItem(x, y, chance)
  if love.math.random() < chance then
    pickups.dropItem(x, y, items.random())
  end
end

-- Drops a perk (an id from src.perks) at (x, y). Like an item it never
-- despawns; the hunter takes it by pressing E next to it, and it is his for
-- the rest of the run (no slot, no room needed).
function pickups.dropPerk(x, y, id, vx, vy)
  list[#list + 1] = {
    kind = "perk",
    perkId = id,
    perk = perks.new(id),
    value = 0,
    x = x,
    y = y,
    vx = vx or (love.math.random() - 0.5) * 40,
    vy = vy or -90,
    age = 0,
    sparkle = love.math.random() * 6,
  }
end

-- Drops a boss's glyph (an id from src.glyphs): taken with E like a perk, and
-- the hunter's for the rest of the run
function pickups.dropGlyph(x, y, id, vx, vy)
  list[#list + 1] = {
    kind = "glyph",
    glyphId = id,
    perk = glyphs.new(id), -- (shaped like a perk for the prompt and the glow)
    value = 0,
    x = x,
    y = y,
    vx = vx or (love.math.random() - 0.5) * 40,
    vy = vy or -90,
    age = 0,
    sparkle = love.math.random() * 6,
  }
end

-- Spills `amount` gold at (x, y) as a handful of coins, flung outward
function pickups.dropGold(x, y, amount)
  if amount <= 0 then
    return
  end
  local coins = math.min(amount, 8)
  local base, extra = math.floor(amount / coins), amount % coins
  for i = 1, coins do
    local a = -math.pi / 2 + (love.math.random() - 0.5) * 2.4
    local s = 40 + love.math.random() * 90
    if #list >= MAX_PICKUPS then
      overflow = overflow + table.remove(list, 1).value -- the oldest coin gives way, its gold carried on
    end
    list[#list + 1] = {
      kind = "gold",
      value = base + (i <= extra and 1 or 0) + overflow,
      x = x + (love.math.random() - 0.5) * 4,
      y = y,
      vx = math.cos(a) * s,
      vy = math.sin(a) * s,
      age = 0,
      sparkle = love.math.random() * 6,
    }
    overflow = 0
  end
end

-- Returns false if it can't be picked up (no room for an item; a weapon
-- with all slots full goes to the compare prompt instead)
local function collect(p, player)
  local inv = player.inventory
  if p.kind == "weapon" then
    local slot = inv:freeWeaponSlot()
    if slot then
      inv.weapons[slot] = p.gun
      audio.play("pickup")
      return true
    end
    if pickups.onWeaponFull then
      pickups.onWeaponFull(p)
    end
    return false
  elseif p.kind == "item" then
    if not inv:addItem(p.item) then
      return false
    end
    audio.play("pickup")
    effects.popup(p.x, p.y - 6, p.item.name, p.item.color)
    for _ = 1, 4 do
      effects.particle(p.x, p.y, (love.math.random() - 0.5) * 70, -love.math.random() * 60, 0.35, p.item.color, 200, true)
    end
  elseif p.kind == "perk" then
    perks.add(p.perkId)
    player:refreshMaxHp()
    audio.play("buy")
    effects.popup(p.x, p.y - 8, p.perk.name, p.perk.color)
    for _ = 1, 12 do
      effects.particle(p.x, p.y - 4, (love.math.random() - 0.5) * 80, -love.math.random() * 70, 0.5, p.perk.color, 200, true)
    end
  elseif p.kind == "glyph" then
    glyphs.add(p.glyphId)
    audio.play("buy")
    effects.popup(p.x, p.y - 8, p.perk.name, p.perk.color)
    effects.popup(p.x, p.y - 18, glyphs.count() .. " / " .. glyphs.total(), { 0.85, 0.85, 0.9 })
    for _ = 1, 16 do
      effects.particle(p.x, p.y - 4, (love.math.random() - 0.5) * 90, -love.math.random() * 80, 0.6, p.perk.color, 200, true)
    end
  elseif p.kind == "gold" then
    local value = math.max(1, math.floor(p.value * perks.prod("gold") + 0.5))
    inv.gold = inv.gold + value
    audio.play("coin")
    effects.popup(p.x, p.y - 6, "+" .. value, { 1, 0.82, 0.25 })
    for _ = 1, 4 do
      effects.particle(p.x, p.y, (love.math.random() - 0.5) * 70, -love.math.random() * 60, 0.35, { 1, 0.9, 0.4 }, 200, true)
    end
  end
  return true
end

function pickups.update(dt, world, player)
  local px, py = player:center()
  local canCollect = not player.dead
  local magnetRange = MAGNET_RANGE * perks.prod("magnet") + pickups.extraMagnet
  for i = #list, 1, -1 do
    local p = list[i]
    p.age = p.age + dt
    local dx, dy = px - p.x, py - p.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local taken = false
    -- Only gold is collected by walking near; items need E
    if canCollect and p.age > MAGNET_DELAY and p.kind == "gold" then
      if dist < PICKUP_RADIUS then
        taken = collect(p, player)
      elseif dist < magnetRange then
        -- Pulled in, faster the closer it is
        local pull = 900 * (1 - dist / magnetRange) + 120
        p.vx = p.vx + dx / dist * pull * dt
        p.vy = p.vy + dy / dist * pull * dt
        p.pulled = true
      end
    end
    if p.kind == "gold" and p.landedAt and not p.pulled and p.age - p.landedAt > DESPAWN_TIME then
      taken = true -- timed out: just removed, not collected
    elseif p.pulled then
      p.landedAt = nil -- being pulled in: the timer starts again if it lands again
    end
    if taken then
      table.remove(list, i)
    elseif not p.pulled or dist >= magnetRange then
      p.pulled = false
      p.vy = math.min(p.vy + GRAVITY * dt, 450)
      local nx, ny = p.x + p.vx * dt, p.y + p.vy * dt
      if world:isSolid(math.floor(nx), math.floor(p.y)) then
        p.vx = -p.vx * 0.4
        nx = p.x
      end
      if world:isSolid(math.floor(nx), math.floor(ny)) then
        p.landedAt = p.landedAt or p.age
        -- Bounce off the ground, losing most of the energy; settle when slow
        if math.abs(p.vy) < 40 then
          p.vy, ny = 0, p.y
        else
          p.vy = -p.vy * 0.45
          ny = p.y
        end
        p.vx = p.vx * 0.7
      end
      p.x, p.y = nx, ny
    else
      -- Magnetised: fly straight at the hunter (ignores terrain)
      p.vx, p.vy = p.vx * (1 - 4 * dt), p.vy * (1 - 4 * dt)
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    end
  end
end

local ITEM_REACH = 18 -- how close the hunter must be to an item to pick it up with E

-- The nearest item within reach of the hunter, if any
function pickups.nearestItem(player)
  local px, py = player:center()
  local best, bestDist = nil, ITEM_REACH
  for _, p in ipairs(list) do
    if p.kind == "item" or p.kind == "weapon" or p.kind == "perk" or p.kind == "glyph" then
      local d = math.sqrt((p.x - px) ^ 2 + (p.y - py) ^ 2)
      if d < bestDist then
        best, bestDist = p, d
      end
    end
  end
  return best
end

-- E: picks up the nearest item (if there's room for it). Returns true if one was.
function pickups.interact(player)
  local p = pickups.nearestItem(player)
  if not p then
    return false
  end
  if collect(p, player) then
    pickups.remove(p)
    return true
  end
  if p.kind == "item" then
    effects.popup(p.x, p.y - 8, "No room", { 1, 0.5, 0.4 })
  end
  return false
end

-- The "[E] Name" prompt over the nearest item (full resolution)
function pickups.drawScreen(toScreen, font, player)
  if player.dead then
    return
  end
  local p = pickups.nearestItem(player)
  if not p then
    return
  end
  local sx, sy = toScreen(p.x, p.y - 12)
  local text = "[" .. input.label("interact") .. "] " .. (p.item and p.item.name or (p.perk and ("Take " .. p.perk.name) or p.gun.name))
  love.graphics.setFont(font)
  local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy - font:getHeight())
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.print(text, x + 2, y + 2)
  local c = p.item and p.item.color or (p.perk and p.perk.color) or { 1, 0.85, 0.5 }
  love.graphics.setColor(math.min(1, c[1] + 0.3), math.min(1, c[2] + 0.3), math.min(1, c[3] + 0.3))
  love.graphics.print(text, x, y)
end

local function onScreen(p, view)
  return p.x > view.x - 4 and p.x < view.x + view.w + 4 and p.y > view.y - 4 and p.y < view.y + view.h + 4
end

-- Drawn after the lighting so coins glint in the dark and can be spotted
function pickups.drawEmissive(view)
  local t = love.timer.getTime()
  for _, p in ipairs(list) do
    local left = (p.kind == "gold" and p.landedAt) and (DESPAWN_TIME - (p.age - p.landedAt)) or math.huge
    local blinkOff = left < FADE_TIME and math.floor(left * 10) % 2 == 0
    if p.kind == "weapon" and onScreen(p, view) then
      -- The gun's own icon, with a faint pulse so it stands out
      local icon = itembar.groundIcon(p.gun)
      local pulse = 0.85 + 0.15 * math.sin(t * 4 + p.sparkle)
      love.graphics.setColor(pulse, pulse, pulse)
      love.graphics.draw(icon, math.floor(p.x - icon:getWidth() / 2), math.floor(p.y - icon:getHeight()))
    elseif p.kind == "glyph" and onScreen(p, view) then
      -- A glyph: its tablet hovering over the ground in a pulsing halo
      local c = p.perk.color
      local pulse = 0.5 + 0.5 * math.sin(t * 3 + p.sparkle)
      local bob = math.floor(math.sin(t * 2.5 + p.sparkle) * 1.5)
      local x, y = math.floor(p.x) - 4, math.floor(p.y) - 15 + bob
      love.graphics.setColor(c[1], c[2], c[3], 0.12 + 0.1 * pulse)
      love.graphics.rectangle("fill", x - 3, y - 3, 15, 15)
      glyphs.draw(p.glyphId, x + 1, y + 1, 1)
    elseif p.kind == "perk" and onScreen(p, view) then
      -- A perk: its icon hovering over the ground in a pulsing halo of its colour
      local c = p.perk.color
      local img = icons.get(p.perk)
      local pulse = 0.5 + 0.5 * math.sin(t * 3 + p.sparkle)
      local bob = math.floor(math.sin(t * 2.5 + p.sparkle) * 1.5)
      local x, y = math.floor(p.x) - 4, math.floor(p.y) - 13 + bob
      love.graphics.setColor(c[1], c[2], c[3], 0.12 + 0.1 * pulse)
      love.graphics.rectangle("fill", x - 3, y - 3, 14, 14)
      love.graphics.setColor(c[1], c[2], c[3], 0.25 + 0.15 * pulse)
      love.graphics.rectangle("fill", x - 1, y - 1, 10, 10)
      if img then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, x, y)
      end
      local rarity = items.rarities[p.perk.rarity]
      if rarity then
        love.graphics.setColor(rarity.border[1], rarity.border[2], rarity.border[3], 0.9)
        love.graphics.rectangle("line", x - 0.5, y - 0.5, 9, 9)
      end
    elseif p.kind == "item" and onScreen(p, view) then
      -- A little glowing crate in the item's colour
      local c = p.item.color
      local img = icons.get(p.item)
      if img then
        -- Its icon, hovering a little over the ground on a soft glow
        local bob = math.floor(math.sin(t * 3 + p.sparkle) * 1)
        local x, y = math.floor(p.x) - 4, math.floor(p.y) - 10 + bob
        love.graphics.setColor(c[1], c[2], c[3], 0.25)
        love.graphics.rectangle("fill", x - 1, y - 1, 10, 10)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(img, x, y)
        local rarity = p.item.rarity ~= "common" and items.rarities[p.item.rarity]
        if rarity then
          love.graphics.setColor(rarity.border[1], rarity.border[2], rarity.border[3], 0.9)
          love.graphics.rectangle("line", x - 0.5, y - 0.5, 9, 9)
        end
      else
        local x, y = math.floor(p.x) - 2, math.floor(p.y) - 4
        love.graphics.setColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
        love.graphics.rectangle("fill", x - 1, y - 1, 6, 6)
        love.graphics.setColor(c[1], c[2], c[3])
        love.graphics.rectangle("fill", x, y, 4, 4)
      end
    elseif onScreen(p, view) and not blinkOff then
      local x, y = math.floor(p.x), math.floor(p.y)
      love.graphics.setColor(0.95, 0.74, 0.22)
      love.graphics.rectangle("fill", x, y - 1, 2, 2)
      love.graphics.setColor(1, 0.92, 0.55)
      love.graphics.rectangle("fill", x, y - 1, 1, 1)
      -- A glint that twinkles now and then
      if math.sin(t * 5 + p.sparkle) > 0.92 then
        love.graphics.setColor(1, 1, 0.9)
        love.graphics.rectangle("fill", x - 1, y, 4, 1)
        love.graphics.rectangle("fill", x + 0, y - 2, 1, 5)
      end
    end
  end
end

function pickups.addLights(lighting, view)
  for _, p in ipairs(list) do
    if onScreen(p, view) then
      if p.kind == "weapon" then
        lighting.add(p.x, p.y - 4, 30, 1, 0.85, 0.5, 0.6)
      elseif p.kind == "perk" or p.kind == "glyph" then
        local c = p.perk.color
        lighting.add(p.x, p.y - 6, 34, c[1], c[2], c[3], 0.7)
      elseif p.kind == "item" then
        local c = p.item.color
        lighting.add(p.x, p.y - 2, 22, c[1], c[2], c[3], 0.6)
      else
        lighting.add(p.x, p.y, 12, 1, 0.8, 0.3, 0.35)
      end
    end
  end
end

return pickups
