-- The dev panel (F2): toggles for testing and teleports to the camp, the test
-- room, every area and every boss arena. Source checkouts only (see src.dev).
-- Click a row; the mouse wheel scrolls the list; F2 or Esc closes. The game
-- keeps running behind it.
local dev = require("src.dev")
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

local function rows()
  local out = {
    { kind = "head", label = "Toggles" },
    { kind = "toggle", label = "No damage", get = function() return dev.noDamage end, set = function(v) dev.noDamage = v end },
    { kind = "toggle", label = "One-hit kills", get = function() return dev.oneHit end, set = function(v) dev.oneHit = v end },
    { kind = "toggle", label = "Fly / no clip (Shift fast)", get = function() return dev.noclip end, set = function(v) dev.noclip = v end },
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
