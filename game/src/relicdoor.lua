-- The Buried Vault's locks (src.buriedvault, docs/undercroft-design.md): three plinths on the shelf across the
-- goblet's upper bulb, a socket in each for one of three fused items. Pressing E beside them sets a carried item in
-- its socket (the item is spent); with all three set the plug in the neck below gives, and the pool in the bulb
-- pours down into the sealed sphere that holds the Cork.
-- Nothing says what the sockets take until the mouse rests on one: then the item it wants shows, greyed out.
local audio = require("src.audio")
local effects = require("src.effects")
local input = require("src.input")
local inventory = require("src.inventory")
local items = require("src.items")
local buriedvault = require("src.buriedvault")

local relicdoor = {}

-- The three fused items the door takes (all fused from common items, so there is no unlocking in the way)
relicdoor.RECIPE = { "thermal", "sungold", "shrapnel" }

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

-- The Cork on its pedestal, and the pool in the bulb (the pickups and the liquids are made after the world is built)
function relicdoor.populate()
  if not world then
    return
  end
  local i = buriedvault.info
  local ped = i.pedestal
  require("src.pickups").dropItem((ped.x0 + ped.x1) / 2, ped.y0 - 6, items.new("sunkenkey"), 0, 0)
  require("src.fluids").fillWater(world, i.bulb.x0 + 1, i.bulb.x1 - 1, i.waterLevel)
end

local SW, SH = 6, 6 -- a socket's size
local function lockX(i)
  return buriedvault.info.locks[i]
end

-- (a socket sits in the face of its plinth, which stands on the shelf)
local function socketY(i)
  return buriedvault.info.shelf.y0 - 11
end

local function center()
  local l = buriedvault.info.locks
  return l[2], buriedvault.info.shelf.y0 - 8
end

local function near(player)
  if not world or open or player.dead then
    return false
  end
  local px, py = player:center()
  local cx, cy = center()
  return math.abs(px - cx) < REACH and math.abs(py - cy) < 30
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
  local pl = buriedvault.info.plug
  for y = pl.y0, pl.y1 do
    for x = pl.x0, pl.x1 do
      world:setRaw(x, y, 0)
    end
  end
  world:repaintRegion(pl.x0 - 3, pl.y0 - 3, pl.x1 + 3, pl.y1 + 3)
  require("src.physics").rebuildRegion(pl.x0 - 3, pl.y0 - 3, pl.x1 + 3, pl.y1 + 3)
  require("src.fluids").wake(pl.x0 - 12, pl.y0 - 40, pl.x1 + 12, pl.y1 + 4) -- (the pool starts to pour at once)
  audio.play("clank")
  local cx, cy = (pl.x0 + pl.x1) / 2, (pl.y0 + pl.y1) / 2
  for _ = 1, 24 do
    effects.particle(cx + (love.math.random() - 0.5) * 8, cy, (love.math.random() - 0.5) * 60, 10 + love.math.random() * 50, 0.7, { 0.75, 0.78, 0.88 }, 400)
  end
end

function relicdoor.interact(player)
  if not near(player) then
    return false
  end
  local inv = player.inventory
  for i, id in ipairs(relicdoor.RECIPE) do
    if not set[i] then
      local list, slot = carried(inv, id)
      if list then
        list[slot] = nil
        set[i] = true
        local c = items.defs[id].color
        audio.play("buy")
        effects.ring(lockX(i), socketY(i) + 3, 18, c)
        for _ = 1, 10 do
          effects.particle(lockX(i), socketY(i) + 3, (love.math.random() - 0.5) * 50, -20 - love.math.random() * 40, 0.7, c, -20, true)
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

local AMBER = { 1.0, 0.62, 0.18 }
local GOLD_SOCKET = { 1.0, 0.84, 0.32 }

local function R(c, a, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

local function inView(view, m)
  local b = buriedvault.info.bounds
  return view.x + view.w >= b.x0 - m and view.x <= b.x1 + m and view.y + view.h >= b.y0 - m and view.y <= b.y1 + m
end

-- (drawn whether or not the lock is open: the plinths stay, the plug goes)
function relicdoor.draw(view)
  if not world or not inView(view, 40) then
    return
  end
  local sh = buriedvault.info.shelf
  for i = 1, #relicdoor.RECIPE do
    local x, y = lockX(i) - 4, sh.y0 - 12
    R({ 0.12, 0.12, 0.16 }, 1, x - 1, y, 10, 12)
    R({ 0.30, 0.31, 0.38 }, 1, x, y + 1, 8, 11)
    R({ 0.42, 0.43, 0.52 }, 1, x, y + 1, 8, 1)
    local sx, sy = lockX(i) - SW / 2, socketY(i)
    R({ 0.07, 0.07, 0.10 }, 1, sx, sy, SW, SH + 1)
    R({ 0.30, 0.31, 0.38 }, 1, sx + 1, sy + 1, SW - 2, SH - 1)
    if set[i] then
      R(GOLD_SOCKET, 1, sx + 1, sy + 1, SW - 2, SH - 1)
    end
  end
  if not open then
    -- the plug in the neck: a stone stopper with a rune that fills with gold as the locks are set
    local pl = buriedvault.info.plug
    R({ 0.20, 0.21, 0.26 }, 1, pl.x0, pl.y0, pl.x1 - pl.x0 + 1, pl.y1 - pl.y0 + 1)
    R({ 0.36, 0.37, 0.45 }, 1, pl.x0, pl.y0, pl.x1 - pl.x0 + 1, 1)
    local n = 0
    for i = 1, #relicdoor.RECIPE do
      if set[i] then
        n = n + 1
      end
    end
    for k = 1, 3 do
      R(k <= n and GOLD_SOCKET or { 0.10, 0.10, 0.14 }, 1, pl.x0 + 1 + (k - 1) * 4, pl.y0 + 2, 2, 2)
    end
  end
end

-- The rock round each socket glows amber, and gold once its item is set
function relicdoor.drawEmissive(view)
  if not world or not inView(view, 40) then
    return
  end
  local t = love.timer.getTime()
  for i = 1, #relicdoor.RECIPE do
    local sx, y = lockX(i) - SW / 2, socketY(i)
    local pulse = 0.5 + 0.5 * math.sin(t * 2.2 + i * 1.7)
    if set[i] then
      R(GOLD_SOCKET, 0.16 + 0.08 * pulse, sx - 3, y - 3, SW + 6, SH + 7)
      R(GOLD_SOCKET, 0.55 + 0.25 * pulse, sx + 1, y + 1, SW - 2, SH - 1)
      R({ 1, 1, 1 }, 0.35 + 0.25 * pulse, sx + 2, y + 3, 2, 2)
    else
      R(AMBER, 0.08 + 0.05 * pulse, sx - 3, y - 3, SW + 6, SH + 7)
      R(AMBER, 0.22 + 0.12 * pulse, sx + 1, y + 1, SW - 2, SH - 1)
    end
  end
end

function relicdoor.addLights(lighting, view)
  if not world or not inView(view, 120) then
    return
  end
  for i = 1, #relicdoor.RECIPE do
    if set[i] then
      lighting.add(lockX(i), socketY(i) + 3, 40, GOLD_SOCKET[1], GOLD_SOCKET[2], GOLD_SOCKET[3], 0.6)
    else
      lighting.add(lockX(i), socketY(i) + 3, 24, AMBER[1], AMBER[2], AMBER[3], 0.28)
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

-- The key when the hunter carries an item that fits a socket; and, with the mouse resting on a socket, the item
-- it takes, as its icon greyed out
local hoverT = {} -- socket -> how far its icon is faded in (0..1)

function relicdoor.drawScreen(toScreen, font, player)
  if not world then
    return
  end
  local mx, my = love.mouse.getPosition()
  local dt = math.min(0.1, love.timer.getDelta())
  for i, id in ipairs(relicdoor.RECIPE) do
    local x0, y0 = toScreen(lockX(i) - SW / 2, socketY(i))
    local x1, y1 = toScreen(lockX(i) + SW / 2, socketY(i) + SH)
    local pad = math.max(3, (y1 - y0) * 0.4)
    local over = mx >= x0 - pad and mx <= x1 + pad and my >= y0 - pad and my <= y1 + pad
    local f = hoverT[i] or 0
    f = math.max(0, math.min(1, f + (over and 1 or -1) * dt / 0.18))
    hoverT[i] = f
    if f > 0.01 then
      local def = items.defs[id]
      local img = require("src.icons").get({ id = id, color = def.color })
      if img then
        local scale = math.max(1, math.floor((y1 - y0) * 1.5 / 8 + 0.5))
        local w = 8 * scale
        local ix, iy = math.floor(x0 - w - pad * 2), math.floor((y0 + y1) / 2 - w / 2)
        love.graphics.setColor(0.04, 0.04, 0.07, 0.8 * f)
        love.graphics.rectangle("fill", ix - 3, iy - 3, w + 6, w + 6)
        love.graphics.setColor(0.45, 0.46, 0.52, 0.8 * f)
        love.graphics.rectangle("line", ix - 3, iy - 3, w + 6, w + 6)
        local g = set[i] and 0.9 or 0.38
        love.graphics.setColor(g, g, g * 1.05, (set[i] and 1 or 0.7) * f)
        love.graphics.draw(img, ix, iy, 0, scale, scale)
      end
    end
  end
  if not near(player) then
    return
  end
  local inv = player.inventory
  for _, id in ipairs(relicdoor.RECIPE) do
    local fit = false
    for i, rid in ipairs(relicdoor.RECIPE) do
      if rid == id and not set[i] and carried(inv, id) then
        fit = true
      end
    end
    if fit then
      local cx, cy = center()
      prompt(font, toScreen, cx, cy - 22, { { "[" .. input.label("interact") .. "]", { 1, 0.88, 0.6 } } })
      return
    end
  end
end

return relicdoor
