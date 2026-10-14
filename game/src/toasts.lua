-- Little notes that slide in at the right edge of the screen when the profile
-- records something for the first time ("New in the compendium"), with the
-- thing's icon. Drawn at full resolution over the HUD.
local audio = require("src.audio")
local compendium = require("src.compendium")
local fonts = require("src.fonts")

local toasts = {}

local LIFE = 3.6
local list = {}

local CATEGORY_NAMES = {}
for _, c in ipairs(compendium.CATEGORIES) do
  CATEGORY_NAMES[c.id] = c.name
end

-- A first discovery: category and id as recorded in the save (src.save)
function toasts.discover(category, id)
  local entry = compendium.entry(category, id)
  if not entry then
    return
  end
  list[#list + 1] = { entry = entry, label = CATEGORY_NAMES[category] or category, age = 0 }
  while #list > 4 do
    table.remove(list, 1)
  end
  audio.play("discover")
end

function toasts.update(dt)
  for i = #list, 1, -1 do
    list[i].age = list[i].age + dt
    if list[i].age > LIFE then
      table.remove(list, i)
    end
  end
end

function toasts.clear()
  list = {}
end

-- u: one UI unit in window pixels
function toasts.draw(u)
  if #list == 0 then
    return
  end
  local ww = love.graphics.getWidth()
  local big = fonts.get(math.max(9, math.floor(u * 4)))
  local small = fonts.get(math.max(9, math.floor(u * 3.4)))
  local w, h = 112 * u, 18 * u
  local y = 54 * u -- (below the gold count)
  for _, t in ipairs(list) do
    local inT = math.min(1, t.age / 0.25)
    local outT = math.max(0, (t.age - (LIFE - 0.4)) / 0.4)
    local slide = (1 - inT) ^ 2 + outT ^ 2
    local alpha = 1 - outT
    local x = math.floor(ww - w - 6 * u + slide * (w + 8 * u))
    love.graphics.setColor(0.05, 0.04, 0.07, 0.88 * alpha)
    love.graphics.rectangle("fill", x, y, w, h, u, u)
    love.graphics.setLineWidth(math.max(1, u * 0.4))
    love.graphics.setColor(0.95, 0.72, 0.42, 0.9 * alpha)
    love.graphics.rectangle("line", x, y, w, h, u, u)
    compendium.drawIcon(t.entry, x + 2 * u, y + 2 * u, 13 * u, 13 * u, false, alpha)
    love.graphics.setFont(small)
    love.graphics.setColor(0.98, 0.72, 0.42, 0.85 * alpha)
    love.graphics.print("New in the compendium: " .. t.label, math.floor(x + 17 * u), math.floor(y + 2 * u))
    love.graphics.setFont(big)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.print(t.entry.name, math.floor(x + 17 * u), math.floor(y + 9 * u))
    y = y + h + 3 * u
  end
  love.graphics.setColor(1, 1, 1)
end

return toasts
