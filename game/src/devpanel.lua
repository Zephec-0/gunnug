-- The dev panel (F2): toggles for testing and teleports to the camp, the test
-- room, every area and every boss arena. Source checkouts only (see src.dev).
-- Click a row; the mouse wheel scrolls the list; F2 or Esc closes. The game
-- keeps running behind it.
local dev = require("src.dev")
local bake = require("src.bake")
local lighting = require("src.lighting")
local itembar = require("src.itembar")
local catacombs = require("src.scenes.catacombs")

local panel = {}

local open = false
local scroll = 0
local rects = {} -- { x, y, w, h, row } of the visible rows (screen px)
local box = { x = 0, y = 0, w = 0, h = 0 }

function panel.isOpen()
  return open
end

function panel.toggle()
  open = not open
end

-- Is the mouse over the panel (so a click there is not a shot)?
function panel.overMouse()
  if not open then
    return false
  end
  local mx, my = love.mouse.getPosition()
  return mx >= box.x and mx <= box.x + box.w and my >= box.y and my <= box.y + box.h
end

-- Unlocks everything on the active save file: every weapon, ammo type, attachment
-- and perk, every camp person, and a complete compendium
local function unlockEverything()
  local save = require("src.save")
  local p = save.profile()
  if not p then
    return "No save file in use"
  end
  local guns, items, perks = require("src.guns"), require("src.items"), require("src.perks")
  local meta, compendium = require("src.meta"), require("src.compendium")
  for _, id in ipairs(guns.archetypes()) do
    p.unlocked.weapon[id] = true
    p.seen.weapon[id] = true
  end
  for _, id in ipairs(items.order) do
    local k = items.defs[id].kind
    p.unlocked[k] = p.unlocked[k] or {}
    p.seen[k] = p.seen[k] or {}
    p.unlocked[k][id] = true
    p.seen[k][id] = true
  end
  for id in pairs(perks.defs) do
    p.unlocked.perk[id] = true
    p.seen.perk[id] = true
  end
  for id in pairs(meta.PEOPLE) do
    p.camp[id] = true
  end
  p.marks = (p.marks or 0) + 10
  p.board = true
  p.stats.bosses = math.max(1, p.stats.bosses or 0)
  for _, c in ipairs(compendium.CATEGORIES) do
    p.found[c.id] = p.found[c.id] or {}
    for _, e in ipairs(compendium.entries(c.id)) do
      p.found[c.id][e.id] = math.max(1, p.found[c.id][e.id] or 0)
      for _, key in ipairs(e.tiers or {}) do
        p.found[c.id][key] = math.max(1, p.found[c.id][key] or 0)
      end
    end
  end
  save.touch()
  save.flush()
  return "Everything unlocked"
end

-- 100 gold at the hunter's feet and 12 ether streaming in (it only charges a locked fuser)
local function dropStash()
  local player = require("src.game").player()
  if not player then
    return "No hunter"
  end
  local x, y = player:center()
  require("src.pickups").dropGold(x, y - 12, 100)
  require("src.fuser").dropEther(x, y - 8, 12)
  return "Dropped 100 gold and 12 ether"
end

local function rows()
  local out = {
    { kind = "head", label = "Toggles" },
    { kind = "toggle", label = "No damage", get = function() return dev.noDamage end, set = function(v) dev.noDamage = v end },
    { kind = "toggle", label = "One-hit kills", get = function() return dev.oneHit end, set = function(v) dev.oneHit = v end },
    { kind = "toggle", label = "Fly / no clip (Shift fast)", get = function() return dev.noclip end, set = function(v) dev.noclip = v end },
    { kind = "toggle", label = "Sprites cast shadows (test)", get = function() return lighting.spriteShadows end, set = function(v) lighting.spriteShadows = v end },
    { kind = "toggle", label = "Objects cast shadows", get = function() return lighting.objectShadows end, set = function(v) lighting.objectShadows = v end },
    { kind = "toggle", label = "Lit sprites (test)", get = function() return lighting.litSprites end, set = function(v) lighting.litSprites = v end },
    { kind = "head", label = "Cached drawing (off = the plain way)" },
    { kind = "toggle", label = "Rock slabs", get = function() return bake.enabled.slabs end, set = function(v) bake.enabled.slabs = v end },
    { kind = "toggle", label = "Mine decorations", get = function() return bake.enabled.minedecor end, set = function(v) bake.enabled.minedecor = v end },
    { kind = "toggle", label = "Item bar boxes", get = function() return bake.enabled.itembar end, set = function(v) bake.enabled.itembar = v end },
    { kind = "head", label = "Save file" },
    { kind = "action", label = "Unlock everything (+10 marks)", fn = unlockEverything },
    { kind = "action", label = "Give 10 marks", fn = function()
      local p = require("src.save").profile()
      if not p then
        return "No save file in use"
      end
      p.marks = (p.marks or 0) + 10
      require("src.save").touch()
      return "+10 marks"
    end },
    { kind = "action", label = "Drop 100 gold + 12 ether", fn = dropStash },
    { kind = "head", label = "Go to" },
    { kind = "button", label = "Camp", spec = { kind = "camp" } },
    { kind = "button", label = "Test room", spec = { kind = "test" } },
    { kind = "head", label = "Area entrances" },
  }
  for i = 1, catacombs.count() do
    out[#out + 1] = { kind = "button", label = i .. ". " .. (catacombs.areaName(i) or "?"), spec = { kind = "area", i = i } }
  end
  out[#out + 1] = { kind = "head", label = "Boss arenas" }
  for _, i in ipairs(catacombs.arenaAreas()) do
    out[#out + 1] = { kind = "button", label = i .. ". " .. (catacombs.areaName(i) or "?"), spec = { kind = "arena", i = i } }
  end
  return out
end

function panel.keypressed(key)
  if key == "escape" or key == "f2" then
    open = false
    return true
  end
  return false
end

function panel.wheelmoved(dy)
  if panel.overMouse() then
    scroll = math.max(0, scroll - dy * 3)
    return true
  end
  return false
end

function panel.mousepressed(x, y, button, game)
  if not panel.overMouse() or button ~= 1 then
    return false
  end
  for _, r in ipairs(rects) do
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
      local row = r.row
      if row.kind == "toggle" then
        row.set(not row.get())
      elseif row.kind == "action" then
        local msg = row.fn()
        require("src.toasts").notice("Dev", msg)
      elseif row.kind == "button" then
        game.devTeleport(row.spec)
      end
      break
    end
  end
  return true
end

function panel.draw(u)
  if not open then
    rects = {}
    return
  end
  local ww, wh = love.graphics.getDimensions()
  local f, small = itembar.font(4.4 * u), itembar.font(3.4 * u)
  local rowH = 7.5 * u
  local w = 104 * u
  local x, y = math.floor(ww - w - 6 * u), math.floor(14 * u)
  local h = math.floor(math.min(wh - 24 * u, 190 * u))
  box = { x = x, y = y, w = w, h = h }
  love.graphics.setColor(0.04, 0.03, 0.07, 0.92)
  love.graphics.rectangle("fill", x, y, w, h, 2 * u, 2 * u)
  love.graphics.setColor(0.5, 0.3, 0.55, 0.9)
  love.graphics.rectangle("line", x, y, w, h, 2 * u, 2 * u)
  itembar.shadowPrint("Dev", x + 4 * u, y + 2 * u, f, { 1, 0.6, 1 })
  local hint = "F2 close   wheel scroll"
  itembar.shadowPrint(hint, x + w - 4 * u - small:getWidth(hint), y + 3 * u, small, { 1, 1, 1, 0.55 })
  local list = rows()
  local top, bottom = y + 10 * u, y + h - 2 * u
  local total = #list * rowH
  scroll = math.min(scroll, math.max(0, math.ceil((total - (bottom - top)) / rowH)))
  love.graphics.setScissor(x, top, w, bottom - top)
  rects = {}
  local mx, my = love.mouse.getPosition()
  for i, row in ipairs(list) do
    local ry = top + (i - 1 - scroll) * rowH
    if ry + rowH > top and ry < bottom then
      if row.kind == "head" then
        itembar.shadowPrint(row.label, x + 4 * u, ry + 2 * u, small, { 0.75, 0.6, 0.95 })
      else
        local r = { x = x + 3 * u, y = ry, w = w - 6 * u, h = rowH - u, row = row }
        local hover = mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
        love.graphics.setColor(hover and { 0.2, 0.15, 0.26, 0.95 } or { 0.09, 0.07, 0.12, 0.85 })
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, u, u)
        itembar.shadowPrint(row.label, r.x + 2 * u, ry + 1.2 * u, small, hover and { 1, 0.9, 0.6 } or { 0.88, 0.88, 0.93 })
        if row.kind == "toggle" then
          local on = row.get()
          local t = on and "ON" or "off"
          itembar.shadowPrint(t, r.x + r.w - 2 * u - small:getWidth(t), ry + 1.2 * u, small, on and { 0.5, 1, 0.6 } or { 0.6, 0.6, 0.65 })
        end
        rects[#rects + 1] = r
      end
    end
  end
  love.graphics.setScissor()
end

return panel
