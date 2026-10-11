-- Title screen and pause menu (design doc §9b). While a menu is open the game
-- is paused; the world is drawn dimmed behind it. Navigate with W/S or the
-- arrow keys and Enter, or the mouse (buttons fire on release, so the click
-- that picks one never reaches the game as a shot).
--
-- The menu only reports which action was chosen; src.game carries it out:
--   "play", "resume", "restart", "title", "quit"
local audio = require("src.audio")
local hud = require("src.hud")

local menu = {}

local LAYOUTS = {
  title = {
    title = "GUNNUG",
    subtitle = "A hunter's descent into the catacombs",
    items = { { "Play", "play" }, { "Quit", "quit" } },
  },
  pause = {
    title = "Paused",
    items = { { "Resume", "resume" }, { "Restart run", "restart" }, { "Title screen", "title" }, { "Quit", "quit" } },
  },
}

local state -- nil (closed), "title" or "pause"
local selected = 1
local hitboxes = {}
local pressed -- index of the button the mouse went down on

function menu.open(which)
  state = which
  selected = 1
  pressed = nil
end

function menu.close()
  state = nil
  pressed = nil
end

function menu.isOpen()
  return state ~= nil
end

function menu.state()
  return state
end

local function items()
  return LAYOUTS[state].items
end

local function hitIndex(x, y)
  for i, h in ipairs(hitboxes) do
    if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then
      return i
    end
  end
  return nil
end

-- Returns an action name if the key chose one
function menu.keypressed(key)
  if not state then
    return nil
  end
  local n = #items()
  if key == "w" or key == "up" then
    selected = (selected - 2) % n + 1
    audio.play("tick")
  elseif key == "s" or key == "down" then
    selected = selected % n + 1
    audio.play("tick")
  elseif key == "return" or key == "kpenter" or key == "space" then
    return items()[selected][2]
  elseif key == "escape" and state == "pause" then
    return "resume"
  end
  return nil
end

function menu.mousepressed(x, y, button)
  if state and button == 1 then
    pressed = hitIndex(x, y)
    if pressed then
      selected = pressed
    end
  end
end

-- Returns an action name if a button was clicked (pressed and released on it)
function menu.mousereleased(x, y, button)
  if not state or button ~= 1 then
    return nil
  end
  local i = hitIndex(x, y)
  local down = pressed
  pressed = nil
  if i and i == down then
    return items()[i][2]
  end
  return nil
end

-- Hovering selects
function menu.update()
  if state then
    local i = hitIndex(love.mouse.getPosition())
    if i then
      selected = i
    end
  end
end

local function shadowText(text, x, y, f, color)
  love.graphics.setFont(f)
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.print(text, math.floor(x) + 2, math.floor(y) + 2)
  love.graphics.setColor(color)
  love.graphics.print(text, math.floor(x), math.floor(y))
end

function menu.draw(scale)
  if not state then
    return
  end
  local layout = LAYOUTS[state]
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.03, 0.02, 0.05, state == "title" and 0.78 or 0.6)
  love.graphics.rectangle("fill", 0, 0, ww, wh)

  local big = hud.font(scale * 3.2)
  local mid = hud.font(scale * 1.2)
  local small = hud.font(scale)
  local y = math.floor(wh * 0.2)
  shadowText(layout.title, (ww - big:getWidth(layout.title)) / 2, y, big, state == "title" and { 0.9, 0.18, 0.22 } or { 1, 0.86, 0.45 })
  y = y + big:getHeight()
  if layout.subtitle then
    shadowText(layout.subtitle, (ww - small:getWidth(layout.subtitle)) / 2, y + 2 * scale, small, { 0.8, 0.76, 0.72 })
  end

  hitboxes = {}
  local bw, bh, gap = 70 * scale, 11 * scale, 4 * scale
  local by = math.floor(wh * 0.46)
  for i, item in ipairs(layout.items) do
    local bx = math.floor((ww - bw) / 2)
    local isSel = i == selected
    love.graphics.setColor(0.08, 0.06, 0.10, isSel and 0.95 or 0.75)
    love.graphics.rectangle("fill", bx, by, bw, bh, scale, scale)
    love.graphics.setLineWidth(math.max(1, scale * 0.5))
    if isSel then
      love.graphics.setColor(1, 0.82, 0.35)
    else
      love.graphics.setColor(0.55, 0.48, 0.42, 0.9)
    end
    love.graphics.rectangle("line", bx, by, bw, bh, scale, scale)
    local label = item[1]
    shadowText(label, bx + (bw - mid:getWidth(label)) / 2, by + (bh - mid:getHeight()) / 2, mid, isSel and { 1, 0.9, 0.6 } or { 0.85, 0.82, 0.78 })
    hitboxes[i] = { x = bx, y = by, w = bw, h = bh }
    by = by + bh + gap
  end

  local hint = state == "title" and "W/S or arrows and Enter, or click" or "Esc: resume"
  shadowText(hint, (ww - small:getWidth(hint)) / 2, wh - 24 * scale, small, { 0.6, 0.57, 0.55 })
end

return menu
