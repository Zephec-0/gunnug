-- A tiny immediate-mode UI: widgets are drawn and hit-tested in the same call each frame.
-- Mouse presses reach widgets through ui.press(); the first widget under the cursor takes it.
local U = require("src.util")

local ui = {}
local lg = love.graphics

ui.theme = {
  bg = { 0.09, 0.09, 0.11 }, panel = { 0.14, 0.14, 0.17 }, panel2 = { 0.18, 0.18, 0.22 },
  line = { 0.27, 0.27, 0.33 }, btn = { 0.22, 0.22, 0.27 }, btnHover = { 0.30, 0.30, 0.37 },
  btnActive = { 0.16, 0.50, 0.44 }, text = { 0.88, 0.88, 0.90 }, dim = { 0.55, 0.55, 0.60 },
  accent = { 0.20, 0.80, 0.66 }, warn = { 0.95, 0.55, 0.25 }, sel = { 0.98, 0.85, 0.35 },
}
local T = ui.theme

ui.mx, ui.my = 0, 0
ui.wheel = 0
ui.typed = ""
ui.keys = {}
ui.blocked = false

function ui.init()
  ui.font = lg.newFont(12)
  ui.small = lg.newFont(10)
  ui.big = lg.newFont(16)
  lg.setFont(ui.font)
end

function ui.press(b) ui.pressed = b end
function ui.textinput(t)
  if t:match("^[%w%p ]+$") then ui.typed = ui.typed .. t end
end
function ui.key(k) ui.keys[#ui.keys + 1] = k end

function ui.begin()
  ui.mx, ui.my = love.mouse.getPosition()
  ui.tip = nil
  ui.taken = false
  ui.done = nil
end

function ui.finish()
  ui.pressed = nil
  ui.wheel = 0
  ui.typed = ""
  ui.keys = {}
end

function ui.hit(x, y, w, h)
  return not ui.blocked and ui.mx >= x and ui.my >= y and ui.mx < x + w and ui.my < y + h
end

-- True once when button b was pressed over the rectangle
function ui.clicked(x, y, w, h, b)
  if ui.pressed == (b or 1) and not ui.taken and ui.hit(x, y, w, h) then
    ui.taken = true
    return true
  end
  return false
end

-- Takes a wheel movement over the rectangle
function ui.scroll(x, y, w, h)
  if ui.wheel ~= 0 and ui.hit(x, y, w, h) then
    local v = ui.wheel
    ui.wheel = 0
    return v
  end
  return 0
end

function ui.rect(c, x, y, w, h, mode)
  lg.setColor(c)
  lg.rectangle(mode or "fill", x, y, w, h)
end

function ui.text(s, x, y, c, font)
  lg.setFont(font or ui.font)
  lg.setColor(c or T.text)
  lg.print(s, math.floor(x), math.floor(y))
end

function ui.textc(s, x, y, w, h, c, font)
  font = font or ui.font
  lg.setFont(font)
  lg.setColor(c or T.text)
  lg.print(s, math.floor(x + (w - font:getWidth(s)) / 2), math.floor(y + (h - font:getHeight()) / 2))
end

-- Text cut to fit a width
function ui.fit(s, w, font)
  font = font or ui.font
  if font:getWidth(s) <= w then return s end
  while #s > 1 and font:getWidth(s .. "..") > w do s = s:sub(1, -2) end
  return s .. ".."
end

-- o: active, disabled, tip, right (also report right clicks), font, color (swatch fill)
-- Returns the mouse button that clicked it (1 or 2) or false
function ui.button(label, x, y, w, h, o)
  o = o or {}
  local hover = ui.hit(x, y, w, h)
  local c = o.active and T.btnActive or (hover and T.btnHover or T.btn)
  if o.disabled then c = T.panel2 end
  ui.rect(c, x, y, w, h)
  if o.active then ui.rect(T.accent, x, y + h - 2, w, 2) end
  ui.textc(ui.fit(label, w - 4, o.font), x, y, w, h, o.disabled and T.dim or T.text, o.font)
  if hover and o.tip then ui.tip = o.tip end
  if o.disabled then return false end
  if ui.clicked(x, y, w, h, 1) then return 1 end
  if o.right and ui.clicked(x, y, w, h, 2) then return 2 end
  return false
end

function ui.toggle(label, x, y, w, h, v, tip)
  if ui.button(label, x, y, w, h, { active = v, tip = tip }) then return not v, true end
  return v, false
end

-- Horizontal slider. o: step, fmt (label format), track (fn(t) -> r, g, b for a gradient), tip
-- Returns value, changed, released
function ui.slider(id, x, y, w, h, v, lo, hi, label, o)
  o = o or {}
  local hover = ui.hit(x, y, w, h)
  if ui.pressed == 1 and hover and not ui.taken then
    ui.active = id
    ui.taken = true
  end
  local changed, released = false, false
  if ui.active == id then
    if love.mouse.isDown(1) then
      local t = U.clamp((ui.mx - x) / w, 0, 1)
      local nv = lo + t * (hi - lo)
      if o.step then nv = math.floor(nv / o.step + 0.5) * o.step end
      if nv ~= v then v, changed = nv, true end
    else
      ui.active = nil
      released = true
    end
  end
  if hover and o.tip then ui.tip = o.tip end
  local t = hi > lo and U.clamp((v - lo) / (hi - lo), 0, 1) or 0
  if o.track then
    local n = 24
    for i = 0, n - 1 do
      lg.setColor(o.track((i + 0.5) / n))
      lg.rectangle("fill", x + w * i / n, y, w / n + 1, h)
    end
    lg.setColor(0, 0, 0, 0.8)
    lg.rectangle("fill", x + t * w - 2, y, 4, h)
    lg.setColor(1, 1, 1)
    lg.rectangle("line", x + t * w - 1.5, y + 0.5, 3, h - 1)
  else
    ui.rect(hover and T.btnHover or T.btn, x, y, w, h)
    ui.rect(T.btnActive, x, y, w * t, h)
  end
  if label then
    local s = label .. (o.fmt and string.format(o.fmt, v) or "")
    if o.track then
      ui.text(s, x + 5, y + (h - ui.small:getHeight()) / 2 + 1, { 0, 0, 0, 0.9 }, ui.small)
      ui.text(s, x + 4, y + (h - ui.small:getHeight()) / 2, { 1, 1, 1 }, ui.small)
    else
      ui.textc(s, x, y, w, h, T.text, ui.small)
    end
  end
  return v, changed, released
end

-- Single-line text field. Returns the text (live while editing), whether Enter was pressed and
-- whether it lost focus to a click elsewhere
function ui.textbox(id, x, y, w, h, value, o)
  o = o or {}
  local hover = ui.hit(x, y, w, h)
  local submitted, blurred = false, false
  if ui.pressed == 1 and not ui.taken then
    if hover then
      if ui.focus ~= id then
        ui.focus = id
        ui.buf = tostring(value or "")
      end
      ui.taken = true
    elseif ui.focus == id then
      ui.focus = nil
      blurred = true
      value = ui.buf
    end
  end
  if ui.focus == id then
    ui.buf = ui.buf .. ui.typed
    if o.maxLen then ui.buf = ui.buf:sub(1, o.maxLen) end
    for _, k in ipairs(ui.keys) do
      if k == "backspace" then
        ui.buf = ui.buf:sub(1, -2)
      elseif k == "return" or k == "kpenter" or k == "tab" then
        submitted = true
        ui.focus = nil
      elseif k == "escape" then
        ui.focus = nil
      end
    end
    value = ui.buf
  end
  ui.rect(ui.focus == id and T.panel or T.btn, x, y, w, h)
  ui.rect(ui.focus == id and T.accent or T.line, x, y, w, h, "line")
  local s = tostring(value or "")
  lg.setFont(ui.font)
  local tx = x + 4
  if o.label then
    ui.text(o.label, tx, y + (h - ui.font:getHeight()) / 2, T.dim)
    tx = tx + ui.font:getWidth(o.label) + 4
  end
  ui.text(s, tx, y + (h - ui.font:getHeight()) / 2)
  if ui.focus == id and love.timer.getTime() % 1 < 0.6 then
    ui.rect(T.text, tx + ui.font:getWidth(s) + 1, y + 3, 1, h - 6)
  end
  if hover and o.tip then ui.tip = o.tip end
  return value, submitted, blurred
end

function ui.setFocus(id, value)
  ui.focus = id
  ui.buf = tostring(value or "")
end

function ui.drawTip()
  if not ui.tip then return end
  local font = ui.font
  local w = font:getWidth(ui.tip) + 10
  local h = font:getHeight() + 6
  local x = math.min(ui.mx + 14, lg.getWidth() - w - 4)
  local y = ui.my + 18
  if y + h > lg.getHeight() then y = ui.my - h - 6 end
  ui.rect({ 0.05, 0.05, 0.06, 0.95 }, x, y, w, h)
  ui.rect(T.line, x, y, w, h, "line")
  ui.text(ui.tip, x + 5, y + 3)
end

return ui
