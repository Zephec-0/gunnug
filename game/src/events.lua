-- Events in the dungeon (design doc §11a-vi), placed by src.cavegen and
-- spawned with each area (catacombs.spawnProps):
--   altar       a plinth with a violet flame: an offering takes a cursed perk
--               and gives a rare one (once)
--   vault       a stone-brick room sealed in the rock, its corridor ending at an
--               iron door. A key opens the door; dynamite or digging gets in
--               through the brick. A reliquary chest inside holds a good
--               weapon, a locked item and gold. The key is carried by the
--               area's first elite (or lies on a ledge if there is none).
--   ghost       a wandering ghost merchant who turns up once a run (60%), sells
--               three things at odd prices in gold, blood or marks
--   wounded     a hunter dying in the Sunken Hollows: gives the questline of
--               the old preacher's three silver bells, one hidden in each of
--               the first three areas. Carry one home alive and put it in the
--               bounty board's box (E at the board): marks for each, a prize for all
local audio = require("src.audio")
local effects = require("src.effects")
local input = require("src.input")
local items = require("src.items")
local meta = require("src.meta")
local npcs = require("src.npcs")
local perks = require("src.perks")
local pickups = require("src.pickups")
local save = require("src.save")

local events = {}

local world
local altars, vaults, keys, relics = {}, {}, {}, {}
local wounded, ghost
local ghostTimer, ghostDone, runTime = 60, false, 0

-- Set by src.game: lets the menu open the ghost's page
events.onGhost = nil

function events.clear()
  world = nil
  altars, vaults, keys, relics = {}, {}, {}, {}
  wounded, ghost = nil, nil
  ghostTimer, ghostDone, runTime = 40 + love.math.random() * 70, false, 0
end

-- The questline's save data: { started, delivered = { [1..3] = true }, done }
function events.quest()
  local p = save.profile()
  if not p then
    return nil
  end
  if type(p.quest) ~= "table" then
    p.quest = {}
  end
  p.quest.delivered = type(p.quest.delivered) == "table" and p.quest.delivered or {}
  return p.quest
end

-- Spawning ---------------------------------------------------------------------------

-- Called once for each area as its props are placed. elites: the area's elite monsters.
function events.spawnArea(w, info, index, tier, elites, chests)
  world = w
  for _, s in ipairs(info.altars or {}) do
    altars[#altars + 1] = { x = s[1], y = s[2], used = false, t = love.math.random() * 6 }
  end
  if info.vault then
    local v = info.vault
    local vault = { x = v.x, y = v.y, door = v.door, room = v.room, open = false, area = index }
    vaults[#vaults + 1] = vault
    local chest = chests.spawn(v.x, v.y, 1)
    chest.vault = true -- (a weapon and a locked item, never just gold)
    chest.locked = true -- (can't be opened until the vault's door is: see events.openVault)
    vault.chest = chest
    local carrier = elites and elites[1]
    if carrier then
      carrier.carriesKey = #vaults
    else
      keys[#keys + 1] = { x = (info.relicSpots and info.relicSpots[3] or { v.x + 20 })[1], y = (info.relicSpots and info.relicSpots[3] or { 0, v.y })[2] - 4, vy = 0, vault = #vaults }
    end
  end
  if info.wounded and not (events.quest() or {}).done then
    wounded = { x = info.wounded[1], y = info.wounded[2], say = nil, age = 0 }
  end
  local q = events.quest()
  if q and q.started and not q.delivered[index] and info.relicSpots and info.relicSpots[1] and index <= 3 then
    relics[#relics + 1] = { x = info.relicSpots[1][1], y = info.relicSpots[1][2] - 5, idx = index, taken = false }
  end
end

-- An elite that carried a vault's key has died: it drops where it fell
function events.dropKey(vaultIndex, x, y)
  keys[#keys + 1] = { x = x, y = y, vy = -60, vault = vaultIndex }
  effects.popup(x, y - 10, "A key!", { 1, 0.85, 0.4 })
end

-- Update ---------------------------------------------------------------------------------

local function dist(a, px, py, oy)
  return math.sqrt((a.x - px) ^ 2 + (a.y + (oy or -8) - py) ^ 2)
end

local function say(o, text)
  o.say = { text = text, age = 0 }
end

-- A spot near the hunter for the ghost: open, with ground under it
local function ghostSpot(px, py)
  for _ = 1, 30 do
    local x = px + (love.math.random() < 0.5 and -1 or 1) * (110 + love.math.random() * 110)
    local gy = world:findGround(math.floor(x), math.floor(py - 24))
    if gy and math.abs(gy - py) < 40 and not world:isSolid(math.floor(x), math.floor(gy - 8)) and not world:isSolid(math.floor(x), math.floor(gy - 20)) then
      return x, gy
    end
  end
  return nil
end

local function rollOffers()
  local out = {}
  local ids = {}
  for _, id in ipairs(items.order) do
    ids[#ids + 1] = id
  end
  for i = 1, 3 do
    local item = items.new(table.remove(ids, love.math.random(#ids)))
    local r = love.math.random()
    local currency, price
    if r < 0.5 then
      currency = "gold"
      -- odd prices: sometimes a steal, sometimes a robbery, never round
      local base = ({ 9, 19, 31, 47, 66, 93, 131, 211 })[love.math.random(1, 8)]
      price = base + love.math.random(0, 6)
    elseif r < 0.8 then
      currency, price = "blood", love.math.random(7, 24)
    else
      currency, price = "marks", love.math.random(2, 6)
    end
    out[i] = { item = item, currency = currency, price = price, sold = false }
  end
  return out
end

function events.runTime()
  return runTime
end

function events.update(dt, player, areaIndex)
  runTime = runTime + dt
  if not world then
    return
  end
  local px, py = player:center()
  local inv = player.inventory
  -- keys fall and are picked up by walking over them
  for i = #keys, 1, -1 do
    local k = keys[i]
    k.vy = k.vy + 420 * dt
    local ny = k.y + k.vy * dt
    if world:isSolid(math.floor(k.x), math.floor(ny + 3)) then
      k.vy = 0
    else
      k.y = ny
    end
    if not player.dead and dist(k, px, py, 0) < 12 then
      inv.keys = (inv.keys or 0) + 1
      table.remove(keys, i)
      audio.play("pickup")
      effects.popup(px, py - 14, "Vault key", { 1, 0.85, 0.4 })
    end
  end
  -- relics
  for i = #relics, 1, -1 do
    local r = relics[i]
    if not r.taken and not player.dead and dist(r, px, py, 0) < 12 then
      r.taken = true
      inv.relics = inv.relics or {}
      inv.relics[r.idx] = true
      audio.play("buy")
      effects.popup(px, py - 14, "A silver bell", { 0.85, 0.9, 1 })
      table.remove(relics, i)
    end
  end
  -- the ghost: turns up once, near the hunter, then fades after a while
  if not ghost and not ghostDone and areaIndex and meta.profileActive() then
    ghostTimer = ghostTimer - dt
    if ghostTimer <= 0 then
      ghostDone = true
      if love.math.random() < 0.6 then
        local x, y = ghostSpot(px, py)
        if x then
          ghost = { x = x, y = y, life = 110, age = 0, offers = rollOffers() }
          effects.popup(x, y - 24, "...", { 0.7, 0.85, 1 })
        end
      end
    end
  end
  if ghost then
    ghost.age = ghost.age + dt
    ghost.life = ghost.life - dt
    if ghost.life <= 0 then
      ghost = nil
    elseif ghost.say then
      ghost.say.age = ghost.say.age + dt
    end
  end
  if wounded then
    wounded.age = wounded.age + dt
    if wounded.say then
      wounded.say.age = wounded.say.age + dt
    end
  end
end

-- For tests: the lists, and a ghost summoned beside the hunter at once
function events.debug()
  return { altars = altars, vaults = vaults, keys = keys, relics = relics, wounded = wounded, ghost = ghost }
end

function events.forceGhost(player)
  local px, py = player:center()
  ghost = { x = px + 20, y = py + 8, life = 110, age = 3, offers = rollOffers() }
  ghostDone = true
end

-- Interaction ---------------------------------------------------------------------------

local function nearestAltar(px, py)
  for _, a in ipairs(altars) do
    if not a.used and dist(a, px, py) < 22 then
      return a
    end
  end
end

local function nearestDoor(px, py)
  for _, v in ipairs(vaults) do
    if not v.open then
      local d = v.door
      local dx, dy = (d.x0 + d.x1) / 2 - px, (d.y0 + d.y1) / 2 - py
      if math.sqrt(dx * dx + dy * dy) < 26 then
        return v
      end
    end
  end
end

local function pickPerk(rarity)
  local pool = {}
  for _, id in ipairs(perks.order) do
    if not perks.has(id) and perks.defs[id].rarity == rarity then
      pool[#pool + 1] = id
    end
  end
  return pool[#pool > 0 and love.math.random(#pool) or 1]
end

function events.openVault(v)
  if v.open then
    return
  end
  v.open = true
  if v.chest then
    v.chest.locked = false
  end
  local d = v.door
  for y = d.y0, d.y1 do
    for x = d.x0, d.x1 do
      world:setRaw(x, y, 0)
    end
  end
  world:repaintRegion(d.x0 - 3, d.y0 - 3, d.x1 + 3, d.y1 + 3)
  require("src.physics").rebuildRegion(d.x0 - 3, d.y0 - 3, d.x1 + 3, d.y1 + 3)
  audio.play("clank")
  for _ = 1, 14 do
    effects.particle((d.x0 + d.x1) / 2, (d.y0 + d.y1) / 2, (love.math.random() - 0.5) * 80, -30 - love.math.random() * 40, 0.6, { 0.7, 0.72, 0.8 }, 400)
  end
end

-- E: returns true if it handled the key
function events.interact(player)
  if not world or player.dead then
    return false
  end
  local px, py = player:center()
  local inv = player.inventory
  if ghost and ghost.age > 1 and dist(ghost, px, py) < 28 then
    if events.onGhost then
      events.onGhost()
    end
    return true
  end
  if wounded and dist(wounded, px, py, -3) < 26 then
    local q = events.quest()
    if q and not q.started then
      q.started = true
      save.touch()
      say(wounded, "The old preacher's three silver bells... find them, bring them home.")
      effects.popup(wounded.x, wounded.y - 18, "Quest: the silver bells", { 0.85, 0.9, 1 })
      audio.play("select")
    elseif q then
      local have = 0
      for i = 1, 3 do
        have = have + (q.delivered[i] and 1 or 0)
      end
      say(wounded, have >= 3 and "You found them all. Rest easy." or ("One in each of the first three depths. " .. have .. " of 3 brought home."))
      audio.play("select")
    end
    return true
  end
  local a = nearestAltar(px, py)
  if a then
    a.used = true
    local boon, curse = pickPerk("rare"), pickPerk("cursed")
    local texts = {}
    if boon then
      perks.add(boon)
      texts[#texts + 1] = perks.defs[boon].name
    end
    if curse then
      perks.add(curse)
      texts[#texts + 1] = perks.defs[curse].name
    end
    player:refreshMaxHp()
    audio.play("buy")
    for _ = 1, 24 do
      effects.particle(a.x + (love.math.random() - 0.5) * 8, a.y - 12, (love.math.random() - 0.5) * 70, -30 - love.math.random() * 70, 0.8, { 0.75, 0.45, 1 }, -30, true)
    end
    effects.popup(a.x, a.y - 26, #texts > 0 and table.concat(texts, " + ") or "The flame gutters", { 0.85, 0.6, 1 })
    return true
  end
  local v = nearestDoor(px, py)
  if v then
    if (inv.keys or 0) > 0 then
      inv.keys = inv.keys - 1
      events.openVault(v)
    else
      effects.popup(px, py - 14, "Locked: it needs a key", { 0.8, 0.8, 0.85 })
      audio.play("deny")
    end
    return true
  end
  return false
end

-- Delivering the bells (E at the bounty board). Returns true if it did.
function events.deliver(player)
  local inv = player.inventory
  local q = events.quest()
  if not q or not inv.relics or next(inv.relics) == nil then
    return false
  end
  local px, py = player:center()
  for idx in pairs(inv.relics) do
    q.delivered[idx] = true
    meta.earn(4, "Bell delivered")
    effects.popup(px, py - 14, "A bell, home safe", { 0.85, 0.9, 1 })
  end
  inv.relics = nil
  local all = true
  for i = 1, 3 do
    all = all and q.delivered[i]
  end
  if all and not q.done then
    q.done = true
    meta.earn(15, "The preacher's bells")
    local item = meta.lockedItem() or items.random()
    pickups.dropItem(px, py - 20, item, 0, -90)
  end
  save.touch()
  save.flush()
  audio.play("buy")
  return true
end

-- The ghost's stock, and buying from it (the menu page calls these)
function events.ghostOffers()
  return ghost and ghost.offers or nil
end

function events.buy(i, player)
  local o = ghost and ghost.offers[i]
  local inv = player.inventory
  if not o or o.sold then
    return false
  end
  if o.currency == "gold" and inv.gold < o.price then
    return false
  elseif o.currency == "blood" and player.hp <= o.price then
    return false
  elseif o.currency == "marks" and meta.marks() < o.price then
    return false
  end
  if not inv:addItem(o.item) then
    return false, "No room"
  end
  if o.currency == "gold" then
    inv.gold = inv.gold - o.price
  elseif o.currency == "blood" then
    player:loseHealth(o.price)
  else
    meta.pay(o.price)
  end
  o.sold = true
  audio.play("buy")
  return true
end

-- Drawing ------------------------------------------------------------------------------

local function R(c, x, y, w, h, a)
  love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1))
  love.graphics.rectangle("fill", x, y, w, h)
end

local STONE, STONE_L, STONE_D = { 0.40, 0.40, 0.44 }, { 0.58, 0.58, 0.62 }, { 0.24, 0.24, 0.28 }
local SKIN, EYE = { 0.80, 0.60, 0.46 }, { 0.08, 0.07, 0.08 }

local function inView(view, x, y, m)
  return x > view.x - m and x < view.x + view.w + m and y > view.y - m and y < view.y + view.h + m
end

local function drawAltar(a)
  local x, g = a.x, a.y
  R(STONE_D, x - 7, g - 3, 14, 3)
  R(STONE, x - 6, g - 7, 12, 4)
  R(STONE_L, x - 6, g - 7, 12, 1)
  R(STONE_D, x - 4, g - 10, 8, 3)
  R(STONE, x - 5, g - 12, 10, 2)
  R(STONE_L, x - 5, g - 12, 10, 1)
  -- carved lines on the face
  R(STONE_D, x - 2, g - 6, 1, 2)
  R(STONE_D, x + 1, g - 6, 1, 2)
  R(a.used and { 0.12, 0.10, 0.12 } or { 0.30, 0.15, 0.40 }, x - 3, g - 13, 6, 1)
end

local function drawKey(k)
  R({ 0.86, 0.68, 0.30 }, k.x - 1, k.y - 6, 4, 3)
  R({ 0.20, 0.17, 0.12 }, k.x, k.y - 5, 2, 1)
  R({ 0.86, 0.68, 0.30 }, k.x + 1, k.y - 3, 1, 5)
  R({ 0.86, 0.68, 0.30 }, k.x + 2, k.y, 2, 1)
  R({ 0.86, 0.68, 0.30 }, k.x + 2, k.y + 1, 1, 1)
end

local function drawBell(r)
  local x, y = r.x, r.y
  R({ 0.55, 0.58, 0.66 }, x - 3, y - 4, 6, 1)
  R({ 0.78, 0.82, 0.92 }, x - 2, y - 3, 4, 3)
  R({ 0.78, 0.82, 0.92 }, x - 3, y, 6, 2)
  R({ 0.55, 0.58, 0.66 }, x - 3, y + 2, 6, 1)
  R({ 0.35, 0.37, 0.45 }, x, y + 3, 1, 1)
  R({ 0.35, 0.30, 0.22 }, x, y - 6, 1, 2)
end

local function drawWounded(w)
  local x, g = w.x, w.y
  -- a hunter propped against the wall, bandaged, his gun across his knees
  R({ 0.50, 0.08, 0.08 }, x - 10, g - 1, 8, 1) -- blood
  R({ 0.22, 0.25, 0.4 }, x - 6, g - 4, 9, 4) -- coat
  R({ 0.16, 0.18, 0.30 }, x - 6, g - 2, 9, 2)
  R({ 0.30, 0.2, 0.12 }, x + 3, g - 3, 3, 3) -- boots
  R({ 0.88, 0.86, 0.80 }, x - 4, g - 4, 4, 2) -- bandage
  R({ 0.60, 0.10, 0.10 }, x - 3, g - 4, 1, 2)
  R(SKIN, x - 8, g - 8, 4, 4)
  R(EYE, x - 6, g - 7, 1, 1)
  R({ 0.30, 0.2, 0.12 }, x - 10, g - 4, 8, 1) -- a hat tilted over the face
  R({ 0.30, 0.2, 0.12 }, x - 9, g - 10, 5, 2)
  R({ 0.5, 0.5, 0.56 }, x - 4, g - 5, 9, 1) -- the gun
  R({ 0.35, 0.22, 0.12 }, x + 4, g - 5, 2, 1)
end

local function drawGhost(gh)
  local t = love.timer.getTime()
  local fade = math.min(1, gh.age / 1.5) * math.min(1, gh.life / 3)
  local bob = math.floor(math.sin(t * 2 + 1) * 1.2 + 0.5)
  local x, g = gh.x, gh.y - 3 + bob
  local a = 0.55 * fade
  -- a pale hooded shape that ends in wisps, with a lantern on a pole
  R({ 0.72, 0.85, 1 }, x - 4, g - 18, 8, 3, a)
  R({ 0.72, 0.85, 1 }, x - 5, g - 15, 10, 8, a)
  R({ 0.60, 0.75, 0.95 }, x - 4, g - 7, 8, 3, a)
  for i = -3, 3, 2 do
    R({ 0.60, 0.75, 0.95 }, x + i, g - 4 + math.floor(math.sin(t * 5 + i) + 0.5), 1, 3, a * 0.8)
  end
  R({ 0.10, 0.14, 0.24 }, x - 3, g - 16, 2, 2, fade)
  R({ 0.10, 0.14, 0.24 }, x + 1, g - 16, 2, 2, fade)
  R({ 0.45, 0.55, 0.7 }, x + 7, g - 20, 1, 14, a)
  R({ 0.55, 0.9, 1.0 }, x + 6, g - 22, 3, 3, fade * 0.9)
end

function events.draw(view)
  if not world then
    return
  end
  for _, a in ipairs(altars) do
    if inView(view, a.x, a.y, 40) then
      drawAltar(a)
    end
  end
  for _, k in ipairs(keys) do
    if inView(view, k.x, k.y, 40) then
      drawKey(k)
    end
  end
  for _, r in ipairs(relics) do
    if inView(view, r.x, r.y, 40) then
      drawBell(r)
    end
  end
  if wounded and inView(view, wounded.x, wounded.y, 40) then
    drawWounded(wounded)
  end
  if ghost and inView(view, ghost.x, ghost.y, 60) then
    drawGhost(ghost)
  end
end

function events.drawEmissive(view)
  if not world then
    return
  end
  local t = love.timer.getTime()
  for _, a in ipairs(altars) do
    if inView(view, a.x, a.y, 40) and not a.used then
      local fl = 0.7 + 0.3 * math.sin(t * 9 + a.t)
      for i = -1, 1 do
        local h = 3 + math.floor((math.sin(t * 11 + i * 2 + a.t) * 0.5 + 0.5) * 3) - math.abs(i)
        R({ 0.75, 0.45, 1, fl }, a.x + i, a.y - 13 - h, 1, h)
        R({ 0.95, 0.8, 1, fl }, a.x + i, a.y - 13 - math.max(1, h - 2), 1, math.max(1, h - 2))
      end
    end
  end
  for _, k in ipairs(keys) do
    if inView(view, k.x, k.y, 40) then
      R({ 1, 0.9, 0.5, 0.5 + 0.4 * math.sin(t * 6) }, k.x + 1, k.y - 7, 1, 1)
    end
  end
  for _, r in ipairs(relics) do
    if inView(view, r.x, r.y, 40) then
      R({ 0.85, 0.92, 1, 0.5 + 0.4 * math.sin(t * 4 + r.idx) }, r.x - 4, r.y - 5, 1, 1)
      R({ 0.85, 0.92, 1, 0.5 + 0.4 * math.sin(t * 4 + r.idx + 2) }, r.x + 4, r.y + 1, 1, 1)
    end
  end
  for _, v in ipairs(vaults) do
    if not v.open and inView(view, v.x, v.y, 80) then
      -- the keyhole glows a little, so the door can be found
      local d = v.door
      R({ 1, 0.8, 0.4, 0.4 + 0.3 * math.sin(t * 3) }, math.floor((d.x0 + d.x1) / 2), math.floor((d.y0 + d.y1) / 2), 1, 2)
    end
  end
  if ghost and inView(view, ghost.x, ghost.y, 60) then
    local fade = math.min(1, ghost.age / 1.5) * math.min(1, ghost.life / 3)
    R({ 0.7, 0.95, 1, 0.7 * fade }, ghost.x + 7, ghost.y - 21 + math.floor(math.sin(t * 2 + 1) * 1.2 + 0.5), 1, 1)
  end
end

function events.addLights(lighting, view)
  if not world then
    return
  end
  local t = love.timer.getTime()
  for _, a in ipairs(altars) do
    if inView(view, a.x, a.y, 120) and not a.used then
      lighting.add(a.x, a.y - 15, 50, 0.65, 0.35, 1, 0.55 + 0.1 * math.sin(t * 9 + a.t))
    end
  end
  for _, v in ipairs(vaults) do
    if not v.open and inView(view, v.x, v.y, 120) then
      local d = v.door
      lighting.add((d.x0 + d.x1) / 2, (d.y0 + d.y1) / 2, 22, 1, 0.8, 0.4, 0.3)
    end
  end
  for _, r in ipairs(relics) do
    if inView(view, r.x, r.y, 120) then
      lighting.add(r.x, r.y, 26, 0.7, 0.85, 1, 0.4)
    end
  end
  if ghost and inView(view, ghost.x, ghost.y, 120) then
    lighting.add(ghost.x + 7, ghost.y - 21, 56, 0.55, 0.85, 1, 0.55)
  end
end

local function prompt(font, toScreen, wx, wy, text)
  local sx, sy = toScreen(wx, wy)
  love.graphics.setFont(font)
  local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy - font:getHeight())
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(1, 0.88, 0.6)
  love.graphics.print(text, x, y)
end

function events.drawScreen(toScreen, font, player)
  if not world or require("src.menu").isOpen() then
    return
  end
  for _, o in ipairs({ wounded, ghost }) do
    if o and o.say then
      npcs.bubble(font, o.say.text, toScreen(o.x, o.y - 22), select(2, toScreen(o.x, o.y - 22)), o.say.age)
    end
  end
  if player.dead then
    return
  end
  local px, py = player:center()
  local key = "[" .. input.label("interact") .. "] "
  if ghost and ghost.age > 1 and dist(ghost, px, py) < 28 then
    prompt(font, toScreen, ghost.x, ghost.y - 24, key .. "Trade with the ghost")
  elseif wounded and dist(wounded, px, py, -3) < 26 then
    prompt(font, toScreen, wounded.x, wounded.y - 12, key .. "Talk to the hunter")
  elseif nearestAltar(px, py) then
    local a = nearestAltar(px, py)
    prompt(font, toScreen, a.x, a.y - 18, key .. "Make an offering (a curse for a boon)")
  elseif nearestDoor(px, py) then
    local v = nearestDoor(px, py)
    local d = v.door
    local have = (player.inventory.keys or 0) > 0
    prompt(font, toScreen, (d.x0 + d.x1) / 2, d.y0 - 4, key .. (have and "Unlock the vault" or "Locked vault (needs a key)"))
  end
end

return events
