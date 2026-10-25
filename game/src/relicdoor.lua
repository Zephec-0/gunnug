-- The Buried Vault's door (src.buriedvault, docs/undercroft-design.md): a plate in the wall between the
-- antechamber and the Relic's room, with a socket for each of three fused items. Pressing E beside it sets a
-- carried item in its socket (the item is spent); with all three set the door gives and the wall behind it opens.
-- The sockets are shown by the two-letter code of the item each one takes. Nothing else says what they are.
local audio = require("src.audio")
local effects = require("src.effects")
local input = require("src.input")
local inventory = require("src.inventory")
local items = require("src.items")
local buriedvault = require("src.buriedvault")

local relicdoor = {}

-- The three fused items the door takes (all fused from common items, so there is no unlocking in the way)
relicdoor.RECIPE = { "thermal", "sungold", "shrapnel" }
-- The one that lies in the vault's sealed pocket instead of being fused
relicdoor.POCKET_ITEM = "sungold"

local REACH = 38

local world
local set = {} -- recipe index -> true once its item is in
local open = false

function relicdoor.clear()
  world = nil
  set, open = {}, false
end

function relicdoor.setup(w)
  world = w
  set, open = {}, false
end

-- The item in the pocket (the pickups are made after the world is built)
function relicdoor.populate()
  if not world then
    return
  end
  local p = buriedvault.info.pocket
  local item = items.new(relicdoor.POCKET_ITEM)
  require("src.pickups").dropItem((p.x0 + p.x1) / 2, p.y0 + 2, item, 0, 0)
  local ped = buriedvault.info.pedestal
  require("src.pickups").dropItem((ped.x0 + ped.x1) / 2, ped.y0 - 6, items.new("sunkenkey"), 0, 0)
end

local function door()
  return buriedvault.info.door
end

local function socketY(i)
  return buriedvault.info.antechamber.y0 + 8 + (i - 1) * 15
end

local function center()
  local d = door()
  return (d.x0 + d.x1) / 2, (d.y0 + d.y1) / 2
end

local function near(player)
  if not world or open or player.dead then
    return false
  end
  local px, py = player:center()
  local cx, cy = center()
  -- (it is read from the antechamber side only)
  return px < door().x0 and math.abs(px - cx) < REACH and math.abs(py - cy) < 30
end

-- Where in the hunter's loose items (or an unlocked fuser's slots) a carried item with this id is
local function carried(inv, id)
  for i = 1, inventory.ITEM_SLOTS do
    local it = inv.items[i]
    if it and it.id == id and (it.level or 0) == 0 then
      return inv.items, i
    end
  end
  if inv.fuse and not inv.fuse.locked then
    for i = 1, 2 do
      local it = inv.fuse.slots[i]
      if it and it.id == id and (it.level or 0) == 0 then
        return inv.fuse.slots, i
      end
    end
  end
end

local function allSet()
  for i = 1, #relicdoor.RECIPE do
    if not set[i] then
      return false
    end
  end
  return true
end

local function give()
  open = true
  local d = door()
  for y = d.y0, d.y1 do
    for x = d.x0, d.x1 do
      world:setRaw(x, y, 0)
    end
  end
  -- the divider above the doorway too: the whole wall between the rooms
  local a = buriedvault.info.antechamber
  for y = a.y0, a.y1 do
    for x = d.x0, d.x1 do
      world:setRaw(x, y, 0)
    end
  end
  world:repaintRegion(d.x0 - 3, a.y0 - 3, d.x1 + 3, a.y1 + 3)
  require("src.physics").rebuildRegion(d.x0 - 3, a.y0 - 3, d.x1 + 3, a.y1 + 3)
  audio.play("clank")
  local cx, cy = center()
  for _ = 1, 24 do
    effects.particle(cx, cy + (love.math.random() - 0.5) * 40, (love.math.random() - 0.5) * 90, -30 - love.math.random() * 50, 0.7, { 0.75, 0.78, 0.88 }, 400)
  end
end

function relicdoor.interact(player)
  if not near(player) then
    return false
  end
  local inv = player.inventory
  local cx, cy = center()
  for i, id in ipairs(relicdoor.RECIPE) do
    if not set[i] then
      local list, slot = carried(inv, id)
      if list then
        list[slot] = nil
        set[i] = true
        local c = items.defs[id].color
        audio.play("buy")
        effects.ring(cx - 4, cy, 24, c)
        for _ = 1, 10 do
          effects.particle(cx - 3, socketY(i) + 4, (love.math.random() - 0.5) * 50, -20 - love.math.random() * 40, 0.7, c, -20, true)
        end
        if allSet() then
          give()
        end
        return true
      end
    end
  end
  audio.play("deny")
  return true
end

function relicdoor.update() end

local function R(c, a, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

local function inView(view, m)
  local a = buriedvault.info.antechamber
  local d = door()
  return view.x + view.w >= a.x0 - m and view.x <= d.x1 + m and view.y + view.h >= a.y0 - m and view.y <= a.y1 + m
end

-- The plate and its three sockets, drawn over the wall
function relicdoor.draw(view)
  if not world or open or not inView(view, 40) then
    return
  end
  local d = door()
  local a = buriedvault.info.antechamber
  R({ 0.20, 0.21, 0.26 }, 1, d.x0, a.y0, d.x1 - d.x0 + 1, a.y1 - a.y0 + 1)
  R({ 0.36, 0.37, 0.45 }, 1, d.x0, a.y0, 1, a.y1 - a.y0 + 1)
  R({ 0.12, 0.12, 0.16 }, 1, d.x1, a.y0, 1, a.y1 - a.y0 + 1)
  for i = 1, #relicdoor.RECIPE do
    local y = socketY(i)
    R({ 0.07, 0.07, 0.10 }, 1, d.x0, y, 6, 8)
    R({ 0.30, 0.31, 0.38 }, 1, d.x0 + 1, y + 1, 4, 6)
    if set[i] then
      local c = items.defs[relicdoor.RECIPE[i]].color
      R(c, 1, d.x0 + 1, y + 1, 4, 6)
    end
  end
end

function relicdoor.drawEmissive(view)
  if not world or open or not inView(view, 40) then
    return
  end
  local d = door()
  local t = love.timer.getTime()
  for i = 1, #relicdoor.RECIPE do
    if set[i] then
      local c = items.defs[relicdoor.RECIPE[i]].color
      R({ 1, 1, 1 }, 0.35 + 0.25 * math.sin(t * 3 + i), d.x0 + 2, socketY(i) + 3, 2, 2)
      R(c, 0.5, d.x0 + 1, socketY(i) + 1, 4, 6)
    end
  end
end

function relicdoor.addLights(lighting, view)
  if not world or open or not inView(view, 120) then
    return
  end
  local d = door()
  for i = 1, #relicdoor.RECIPE do
    if set[i] then
      local c = items.defs[relicdoor.RECIPE[i]].color
      lighting.add(d.x0 - 2, socketY(i) + 4, 30, c[1], c[2], c[3], 0.5)
    end
  end
end

local function prompt(font, toScreen, wx, wy, parts)
  local sx, sy = toScreen(wx, wy)
  love.graphics.setFont(font)
  local total = 0
  for _, p in ipairs(parts) do
    total = total + font:getWidth(p[1])
  end
  local x, y = math.floor(sx - total / 2), math.floor(sy - font:getHeight())
  for _, p in ipairs(parts) do
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.print(p[1], x + 2, y + 2)
    love.graphics.setColor(p[2][1], p[2][2], p[2][3])
    love.graphics.print(p[1], x, y)
    x = x + font:getWidth(p[1])
  end
end

-- The sockets by their codes, the ones that are filled in their item's colour; and the key when the hunter
-- carries an item that fits one
function relicdoor.drawScreen(toScreen, font, player)
  if not near(player) then
    return
  end
  local inv = player.inventory
  local parts = {}
  local fits = false
  for i, id in ipairs(relicdoor.RECIPE) do
    local def = items.defs[id]
    parts[#parts + 1] = { def.short .. "  ", set[i] and def.color or { 0.45, 0.46, 0.52 } }
    if not set[i] and carried(inv, id) then
      fits = true
    end
  end
  if fits then
    parts[#parts + 1] = { "[" .. input.label("interact") .. "]", { 1, 0.88, 0.6 } }
  end
  local cx, cy = center()
  prompt(font, toScreen, cx - 14, door().y0 - 6, parts)
end

return relicdoor
