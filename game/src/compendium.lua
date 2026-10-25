-- The compendium's catalogue (design doc §9c): every weapon, ammo type,
-- attachment, perk and monster in the game, built straight from their
-- definition tables (guns.defs, items.defs, perks.defs, enemies.defs), so
-- anything added to those shows up here with no extra work. Each module's
-- order list decides where an entry is listed; entries missing from it are
-- listed after, by name.
--
-- What a profile has collected or slain lives in the save slot (src.save);
-- this module only knows what exists and how to draw it.
local enemies = require("src.enemies")
local guns = require("src.guns")
local gunhud = require("src.gunhud")
local icons = require("src.icons")
local items = require("src.items")
local perks = require("src.perks")

local compendium = {}

compendium.CATEGORIES = {
  { id = "weapon", name = "Weapons", verb = "Collected" },
  { id = "ammo", name = "Ammo", verb = "Collected" },
  { id = "attachment", name = "Attachments", verb = "Collected" },
  { id = "perk", name = "Perks", verb = "Taken" },
  { id = "enemy", name = "Bestiary", verb = "Slain" },
}

local catalogue -- category id -> list of entries (built on first use)
local byKey = {} -- "category:id" -> entry

-- Ids from `defs` in `order` first, then the rest sorted by name
local function ordered(defs, order, keep)
  local out, seen = {}, {}
  for _, id in ipairs(order or {}) do
    if defs[id] and not seen[id] and (not keep or keep(id, defs[id])) then
      out[#out + 1] = id
      seen[id] = true
    end
  end
  local rest = {}
  for id, def in pairs(defs) do
    if not seen[id] and (not keep or keep(id, def)) then
      rest[#rest + 1] = id
    end
  end
  table.sort(rest, function(a, b)
    return tostring(defs[a].name or a) < tostring(defs[b].name or b)
  end)
  for _, id in ipairs(rest) do
    out[#out + 1] = id
  end
  return out
end

local function fmt(v)
  if v == math.floor(v) then
    return tostring(v)
  end
  return string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
end

-- Weapon icons: the gun's own pixel map, in the item bar's palette
local GUN_PALETTE = {
  ["L"] = { 0.80, 0.82, 0.92 },
  ["#"] = { 0.34, 0.35, 0.44 },
  ["k"] = { 0.12, 0.11, 0.16 },
  ["c"] = { 0.66, 0.58, 0.42 },
  ["w"] = { 0.42, 0.26, 0.13 },
  ["W"] = { 0.68, 0.44, 0.22 },
}

-- A gun's picture: its drawn model, as on the item bar (src.gunhud), or the
-- pixel map for guns without one
local function gunImage(id, def)
  local gun = guns.new(id)
  if gunhud.supports(gun) then
    local w, h = gunhud.size(gun)
    local canvas = love.graphics.newCanvas(w, h)
    canvas:setFilter("nearest", "nearest")
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    gunhud.drawModel(gun, 0, 0, 1, 1)
    love.graphics.pop()
    return canvas
  end
  local rows = def.icon
  if not rows then
    return nil
  end
  local data = love.image.newImageData(#rows[1], #rows)
  for y, row in ipairs(rows) do
    for x = 1, #row do
      local c = GUN_PALETTE[row:sub(x, x)]
      if c then
        data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img
end

-- Monster portraits ------------------------------------------------------------------------------
-- A portrait is a few specimens drawn together (a swarm is several bats), each a monster of its own
-- kind posed awake, with the idle it would have in the world: wings beating, bells pulsing, a rider
-- breathing on his crow. { parts = { { e, x, y, rate, off, bob, tick } }, x, y, w, h } where the box is
-- what it fills. Entries that are not a kind of their own (the Big Fish's sizes, the Crow Rider)
-- are listed in EXTRA.

-- How fast each kind's animation clock runs while it hangs about (the wing and bell beats of the game)
local RATES = {
  bat = 18, swarmbat = 20, dreadbat = 11, wisp = 6, crow = 14, dustdevil = 8, gargoyle = 8, wraith = 5, ethercrawler = 14,
  cloudray = 8, starmoth = 22, sentinel = 3, windspirit = 6, gildedlens = 4, cometling = 10, stormcloud = 2, starguardian = 3,
  bloater = 2, queen = 2, jellyfish = 2, angler = 1, urchin = 1.5, spitter = 1, worm = 2, ashshade = 6,
}
-- How far the flyers bob up and down
local BOB = {
  bat = 2, swarmbat = 2, dreadbat = 3, wisp = 3, crow = 2, dustdevil = 2, gargoyle = 2, wraith = 2,
  cloudray = 3, starmoth = 3, sentinel = 2, windspirit = 3, gildedlens = 2, cometling = 2, stormcloud = 3, starguardian = 2,
  jellyfish = 3, starwarden = 3, urchin = 2, piranha = 1, bigfish_1 = 1, bigfish_2 = 1, ashshade = 3,
}

-- What each kind does while it waits, on top of its animation clock (e is the specimen, t the time).
-- Anything on the ground that is not listed paces on the spot.
local IDLE = {
  hopper = function(e, t)
    -- crouch, leap, land, again
    local k = t % 2.6
    e.windT = k < 0.55 and 1 or nil
    e.grounded = not (k >= 0.55 and k < 1.0)
  end,
  golem = function(e, t)
    e.fpose = { nf = { -2, 0 }, ff = { 10, 0 }, t = t, bob = math.floor(math.sin(t * 1.6) + 0.5) }
  end,
  queen = false,
  starwarden = false,
  spitter = false,
  bloater = false,
  behemoth = false,
  dummy = false,
}
IDLE.matron = IDLE.hopper

local EXTRA = {
  crowrider = {
    name = "The Crow Rider",
    boss = true,
    hp = 1200,
    gold = enemies.defs.darkhunter and enemies.defs.darkhunter.gold,
    desc = "The Dark Hunter, back off his knees and in the saddle of a great black crow. It hangs over you on its wingbeats and dives, shrieking; he shoots from its back and sends his shadows out ahead of him.",
  },
  bigfish_1 = {
    name = "Big Fish", boss = true, hp = 750, damage = 10, stage = 1,
    desc = "It was a small fish. Hurt it enough and it stops fighting and waits, which is a mistake: something bigger is coming to eat it.",
  },
  bigfish_2 = {
    name = "Bigger Fish", boss = true, hp = 750, damage = 16, stage = 2,
    desc = "The thing that ate the first. It folds its tail and sweeps through the water, and it too goes quiet before the end, as if it knows what comes next.",
  },
  bigfish_3 = {
    name = "Even Bigger Fish", boss = true, hp = 750, damage = 22, stage = 3,
    desc = "An eel as long as a hall, bending through the water. It lunges along the dotted lines it draws, and spits bubbles. Something very much larger is circling above.",
  },
}

-- Where each listed entry falls in the bestiary: the ordinary monsters in the order you meet them,
-- then the bosses (anything not named here is listed after, by name)
local ENEMY_ORDER = {
  "ghoul", "bat", "swarmbat", "spitter", "hopper", "bloater", "wisp", "worm", "miner", "roller", "piranha",
  "jellyfish", "angler", "urchin", "crow", "cragram", "dustdevil", "gargoyle", "wraith", "cairncrab", "ethercrawler", "minigolem", "cloudray", "starmoth", "sentinel", "windspirit", "gildedlens", "cometling", "stormcloud", "starguardian",
  "warden", "dreadbat", "matron", "behemoth", "queen", "golem", "darkhunter", "crowrider", "starwarden", "hollowking",
  "bigfish_1", "bigfish_2", "bigfish_3", "bigfish",
}

local function part(e, x, y, kind)
  return { e = e, x = x or 0, y = y or 0, rate = RATES[kind] or 1, off = 0, bob = BOB[kind] or 0, kind = kind }
end

local function buildPortrait(id)
  local extra = EXTRA[id]
  if id == "swarmbat" then
    -- A swarm: bats all about each other, each on its own wingbeat
    local parts = {}
    local spots = { { 2, 14 }, { 26, 2 }, { 50, 16 }, { 16, 34 }, { 40, 38 }, { 66, 30 }, { 34, 20 }, { 78, 8 } }
    for i, s in ipairs(spots) do
      local e = enemies.specimen("swarmbat")
      e.facing = (i % 3 == 0) and -1 or 1
      local p = part(e, s[1], s[2], "swarmbat")
      p.off, p.rate = i * 1.7, 18 + (i % 4) * 2
      p.drift = 2 + (i % 3)
      parts[#parts + 1] = p
    end
    return { parts = parts, x = -4, y = -6, w = 100, h = 58 }
  elseif id == "crowrider" then
    local e = enemies.riderSpecimen()
    local p = part(e, 0, 0, "crowrider")
    p.tick = enemies.riderTick
    local bx = enemies.RIDER_BOUNDS
    return { parts = { p }, x = bx[1], y = bx[2], w = bx[3], h = bx[4] }
  end
  local e
  if extra and extra.stage then
    e = require("src.aquatic").specimen(extra.stage)
  elseif id == "bigfish" then
    e = require("src.aquatic").specimen(4)
  else
    e = enemies.specimen(id)
  end
  local x, y, w, h = enemies.specimenBounds(e)
  return { parts = { part(e, 0, 0, id) }, x = x, y = y, w = w, h = h }
end

local ports = {}
local drawPortrait -- (below)

-- The portrait's box, found by drawing it through a few beats and taking the pixels that were painted
-- (a boss's own idea of its size, or a wing's reach, is never quite what is on the screen)
local function measure(pt)
  -- (a canvas with room round the first guess at the box, for what the guess missed)
  local pad = math.max(30, math.floor(math.max(pt.w, pt.h) * 0.5))
  local cw, ch = math.ceil(pt.w) + 2 * pad, math.ceil(pt.h) + 2 * pad
  local ox, oy = pad - math.floor(pt.x), pad - math.floor(pt.y)
  local canvas = love.graphics.newCanvas(cw, ch)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for i = 0, 5 do
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    love.graphics.translate(ox, oy)
    drawPortrait(pt, 0.35 + i * 0.27, 0.05)
    love.graphics.pop()
    local data = canvas:newImageData()
    local px = require("ffi").cast("uint8_t*", data:getFFIPointer())
    for y = 0, ch - 1 do
      for x = 0, cw - 1 do
        if px[(y * cw + x) * 4 + 3] > 64 then
          if x < x0 then x0 = x end
          if y < y0 then y0 = y end
          if x + 1 > x1 then x1 = x + 1 end
          if y + 1 > y1 then y1 = y + 1 end
        end
      end
    end
    data:release()
  end
  canvas:release()
  if x1 > x0 then
    pt.x, pt.y, pt.w, pt.h = x0 - ox - 1, y0 - oy - 1, x1 - x0 + 2, y1 - y0 + 2
  end
end

local function portrait(id)
  local pt = ports[id]
  if pt == nil then
    local ok, res = pcall(buildPortrait, id)
    pt = ok and res or false
    if pt then
      pcall(measure, pt)
    end
    ports[id] = pt
  end
  return pt or nil
end

-- Draws a portrait at time t (the origin is the world's origin: the caller moves the box there).
-- False if a drawing failed.
function drawPortrait(pt, t, dt)
  local ok = true
  for _, p in ipairs(pt.parts) do
    local e = p.e
    e.phase = t * p.rate + p.off
    local idle = IDLE[p.kind]
    if idle then
      idle(e, t)
    elseif idle == nil and e.def.ground then
      e.body.vx, e.body.vy, e.grounded = e.facing * 26, 0, true -- (a slow walk in place)
    end
    if p.tick then
      p.tick(e, dt or 0, t)
    end
    local bob = p.bob > 0 and math.floor(math.sin(t * 2.2 + p.off) * p.bob + 0.5) or 0
    local dx = p.drift and math.floor(math.sin(t * 1.3 + p.off) * p.drift + 0.5) or 0
    love.graphics.push()
    love.graphics.translate(p.x + dx, p.y + bob)
    ok = enemies.drawSpecimen(e) and ok
    love.graphics.pop()
  end
  return ok
end

-- A monster's portrait, drawn once into an image of its own size
local function enemyImage(id)
  local pt = portrait(id)
  if not pt then
    return nil
  end
  local w, h = math.ceil(pt.w), math.ceil(pt.h)
  local canvas = love.graphics.newCanvas(w, h)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  love.graphics.translate(-math.floor(pt.x), -math.floor(pt.y))
  local ok = drawPortrait(pt, 0.35, 0)
  love.graphics.pop()
  return ok and canvas or nil
end

local function build()
  catalogue = {}
  local function add(cat, entry)
    entry.category = cat
    catalogue[cat] = catalogue[cat] or {}
    local list = catalogue[cat]
    list[#list + 1] = entry
    entry.index = #list
    byKey[cat .. ":" .. entry.id] = entry
  end

  for _, id in ipairs(ordered(guns.defs, guns.archetypes())) do
    local d = guns.defs[id]
    add("weapon", {
      id = id,
      name = d.name,
      desc = d.desc or "",
      image = gunImage(id, d),
      stats = {
        { "Damage", d.pellets and d.pellets > 1 and (fmt(d.damage) .. " x " .. d.pellets) or fmt(d.damage) },
        { "Chambers", fmt(d.chambers) },
        { "Fire delay", fmt(d.fireDelay) .. "s" },
        { "Reload", fmt(d.reloadTime) .. "s" },
        { "Spread", fmt(d.spread) .. " deg" },
        { "Slots", fmt(d.slots) },
      },
    })
  end

  -- Commons first, then the rare and cursed ones, then the fused
  local itemOrder = {}
  for _, id in ipairs(items.order) do
    if items.levelable(id) then
      itemOrder[#itemOrder + 1] = id
    end
  end
  for _, id in ipairs(items.order) do
    if not items.levelable(id) then
      itemOrder[#itemOrder + 1] = id
    end
  end
  for _, id in ipairs(items.fusedOrder or {}) do
    itemOrder[#itemOrder + 1] = id
  end
  for _, id in ipairs(ordered(items.defs, itemOrder, function(id, def)
    return def.compendium ~= false and not (def.secret and not require("src.meta").isUnlocked(def.kind, id))
  end)) do
    local d = items.defs[id]
    local thing = items.new(id)
    local a, b = items.recipe(id)
    local cat = d.kind == "ammo" and "ammo" or "attachment"
    local entry = {
      id = id,
      name = d.name,
      desc = d.desc or "",
      rarity = d.rarity,
      color = d.color,
      image = icons.getHD(thing) or icons.get(thing),
      short = d.short,
      -- Fused items: the two they are made from { category, id, name }
      recipe = a and {
        { items.defs[a].kind, a, items.defs[a].name },
        { items.defs[b].kind, b, items.defs[b].name },
      } or nil,
    }
    add(cat, entry)
    -- Common ones can be fused with themselves, up to +4. They share the one
    -- tile (greyed tier bars that light as each is collected); each level still
    -- has an entry of its own to look up, but isn't listed
    if items.levelable(id) then
      entry.tiers = {}
      for level = 1, items.MAX_LEVEL do
        local lv = items.new(id, level)
        local key = items.key(id, level)
        entry.tiers[level] = key
        byKey[cat .. ":" .. key] = {
          category = cat,
          id = key,
          name = lv.name,
          desc = lv.desc,
          rarity = d.rarity,
          color = d.color,
          image = entry.image,
          short = d.short,
          level = level,
          base = { d.kind, id, d.name },
        }
      end
    end
  end

  for _, id in ipairs(ordered(perks.defs, perks.order, function(_, def)
    return def.compendium ~= false
  end)) do
    local d = perks.defs[id]
    add("perk", {
      id = id,
      name = d.name,
      desc = d.desc or "",
      rarity = d.rarity,
      color = d.color,
      image = (function() local pk = perks.new(id); return icons.getHD(pk) or icons.get(pk) end)(),
      short = d.short,
    })
  end

  -- (the ids of every monster the bestiary lists: those in ENEMY_ORDER, then any others by name)
  local ids, seen = {}, {}
  for _, id in ipairs(ENEMY_ORDER) do
    if EXTRA[id] or (enemies.defs[id] and enemies.defs[id].compendium ~= false) then
      ids[#ids + 1] = id
      seen[id] = true
    end
  end
  for _, id in ipairs(ordered(enemies.defs, enemies.order, function(_, def)
    return def.compendium ~= false
  end)) do
    if not seen[id] then
      ids[#ids + 1] = id
    end
  end
  for _, id in ipairs(ids) do
    local d = EXTRA[id] or enemies.defs[id]
    local name = d.name or (id:sub(1, 1):upper() .. id:sub(2))
    local desc = d.desc or ""
    if id == "bigfish" then
      name = "The Biggest Fish"
      desc = "The last of them: the Angler Sharkwhale, with four great tusks. It was a small fish. Then something bigger ate it, then something bigger ate that. Shoot the teeth first."
    end
    add("enemy", {
      id = id,
      name = name,
      desc = desc,
      image = enemyImage(id),
      boss = d.boss,
      stats = {
        { "Health", fmt(d.hp) },
        { "Damage", d.damage and fmt(d.damage) or (d.globDamage and fmt(d.globDamage)) or "-" },
        { "Gold", d.gold and (d.gold[1] .. "-" .. d.gold[2]) or "-" },
      },
    })
  end
  for _, c in ipairs(compendium.CATEGORIES) do
    catalogue[c.id] = catalogue[c.id] or {}
  end
end

-- The entries of a category, in listing order
function compendium.entries(category)
  if not catalogue then
    build()
  end
  return catalogue[category] or {}
end

function compendium.entry(category, id)
  if not catalogue then
    build()
  end
  return byKey[category .. ":" .. id]
end

-- found and total entries of a category for a profile (all categories if nil)
function compendium.progress(profile, category)
  local found, total = 0, 0
  for _, c in ipairs(compendium.CATEGORIES) do
    if not category or c.id == category then
      local got = profile and profile.found[c.id] or {}
      for _, e in ipairs(compendium.entries(c.id)) do
        total = total + 1
        if (got[e.id] or 0) > 0 then
          found = found + 1
        end
      end
    end
  end
  return found, total
end

-- Every entry image, for the title screen's whirl: { image, category }
function compendium.allImages()
  local out = {}
  for _, c in ipairs(compendium.CATEGORIES) do
    for _, e in ipairs(compendium.entries(c.id)) do
      if e.image and not e.level then
        out[#out + 1] = { image = e.image, category = c.id, entry = e }
      end
    end
  end
  return out
end

-- Draws an entry's image fitted into a box (whole-number scale where it can),
-- centred. silhouette draws it as a flat dark shape (not yet discovered).
local silhouetteShader
function compendium.drawIcon(entry, x, y, w, h, silhouette, alpha)
  local img = entry.image
  if not img then
    return
  end
  local iw, ih = img:getDimensions()
  -- (the item and perk images carry room for a drop shadow: fit the art, not the room)
  local pad = iw == icons.HD_SIZE + 2 * icons.HD_PAD and icons.HD_PAD or 0
  local cw, ch = iw - 2 * pad, ih - 2 * pad
  local s = math.min(w / cw, h / ch)
  if s >= 1 then
    s = math.floor(s)
  end
  local dx = math.floor(x + (w - cw * s) / 2 - pad * s)
  local dy = math.floor(y + (h - ch * s) / 2 - pad * s)
  local centred = pad > 0 and not silhouette
  if silhouette then
    if not silhouetteShader then
      silhouetteShader = love.graphics.newShader([[
        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
          return vec4(color.rgb, color.a * step(0.5, Texel(tex, uv).a));
        }
      ]])
    end
    love.graphics.setShader(silhouetteShader)
    love.graphics.setColor(0.13, 0.11, 0.17, alpha or 1)
    love.graphics.draw(img, dx, dy, 0, s, s)
    love.graphics.setShader()
  else
    if centred then
      icons.drawHDAt(img, x + w / 2, y + h / 2, s, alpha)
    else
      icons.drawHD(img, dx, dy, s, alpha)
    end
  end
  if entry.level and not silhouette then
    icons.drawLevel(entry.level, x, y, math.min(w, h), alpha)
  elseif entry.level then
    icons.drawLevel(entry.level, x, y, math.min(w, h), 0.35)
  end
end

-- A live, animated monster for the detail panel, fitted into a box
local lastLive = 0
function compendium.drawLive(entry, x, y, w, h)
  if entry.category ~= "enemy" then
    return compendium.drawIcon(entry, x, y, w, h)
  end
  local pt = portrait(entry.id)
  if not pt then
    return compendium.drawIcon(entry, x, y, w, h)
  end
  local s = math.min(w / pt.w, h / pt.h)
  if s >= 1 then
    s = math.floor(s)
  end
  local t = love.timer.getTime()
  local dt = math.min(0.1, t - lastLive)
  lastLive = t
  love.graphics.push()
  love.graphics.translate(math.floor(x + (w - pt.w * s) / 2), math.floor(y + (h - pt.h * s) / 2))
  love.graphics.scale(s, s)
  love.graphics.translate(-pt.x, -pt.y)
  local ok = drawPortrait(pt, t, dt)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
  if not ok then
    compendium.drawIcon(entry, x, y, w, h)
  end
end

return compendium
