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

-- A monster's portrait, drawn once into an image of its own size
local function enemyImage(kind)
  local e = enemies.specimen(kind)
  local x, y, w, h = enemies.specimenBounds(e)
  w, h = math.ceil(w), math.ceil(h)
  local canvas = love.graphics.newCanvas(w, h)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  love.graphics.translate(-math.floor(x), -math.floor(y))
  local ok = enemies.drawSpecimen(e)
  love.graphics.pop()
  return ok and canvas or nil, e
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
  for _, id in ipairs(ordered(items.defs, itemOrder)) do
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
      image = icons.get(thing),
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

  for _, id in ipairs(ordered(perks.defs, perks.order)) do
    local d = perks.defs[id]
    add("perk", {
      id = id,
      name = d.name,
      desc = d.desc or "",
      rarity = d.rarity,
      color = d.color,
      image = icons.get(perks.new(id)),
      short = d.short,
    })
  end

  local keep = function(_, def)
    return def.compendium ~= false
  end
  for _, id in ipairs(ordered(enemies.defs, enemies.order, keep)) do
    local d = enemies.defs[id]
    local img = enemyImage(id)
    add("enemy", {
      id = id,
      name = d.name or (id:sub(1, 1):upper() .. id:sub(2)),
      desc = d.desc or "",
      image = img,
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
  local s = math.min(w / iw, h / ih)
  if s >= 1 then
    s = math.floor(s)
  end
  local dx = math.floor(x + (w - iw * s) / 2)
  local dy = math.floor(y + (h - ih * s) / 2)
  if silhouette then
    if not silhouetteShader then
      silhouetteShader = love.graphics.newShader([[
        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
          return vec4(color.rgb, color.a * step(0.05, Texel(tex, uv).a));
        }
      ]])
    end
    love.graphics.setShader(silhouetteShader)
    love.graphics.setColor(0.13, 0.11, 0.17, alpha or 1)
    love.graphics.draw(img, dx, dy, 0, s, s)
    love.graphics.setShader()
  else
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(img, dx, dy, 0, s, s)
  end
  if entry.level and not silhouette then
    icons.drawLevel(entry.level, x, y, math.min(w, h), alpha)
  elseif entry.level then
    icons.drawLevel(entry.level, x, y, math.min(w, h), 0.35)
  end
end

-- A live, animated monster for the detail panel, fitted into a box
local live = {}
function compendium.drawLive(entry, x, y, w, h)
  if entry.category ~= "enemy" then
    return compendium.drawIcon(entry, x, y, w, h)
  end
  local e = live[entry.id]
  if e == nil then
    e = enemies.specimen(entry.id)
    live[entry.id] = e
  end
  local bx, by, bw, bh = enemies.specimenBounds(e)
  local s = math.min(w / bw, h / bh)
  if s >= 1 then
    s = math.floor(s)
  end
  e.phase = love.timer.getTime() * 1.0
  love.graphics.push()
  love.graphics.translate(math.floor(x + (w - bw * s) / 2), math.floor(y + (h - bh * s) / 2))
  love.graphics.scale(s, s)
  love.graphics.translate(-bx, -by)
  local ok = enemies.drawSpecimen(e)
  love.graphics.pop()
  if not ok then
    compendium.drawIcon(entry, x, y, w, h)
  end
end

return compendium
