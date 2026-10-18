-- The visuals panel (F4): sliders for the frame's post-processing, adjusted
-- live while the game runs on behind it. Values live in src.settings (the
-- vis* keys) and are applied by src.render (render.adj). Mouse: click or drag
-- a slider, click Dithering to cycle it; keys: Up/Down pick a row, Left/Right
-- adjust, R resets, F4 or Esc closes.
local settings = require("src.settings")
local render = require("src.render")
local itembar = require("src.itembar")

local visuals = {}

local open = false
local sel = 1
local dragging
local rects = {}

-- kind "cycle" steps through names; otherwise a slider between lo and hi
local ROWS = {
  { key = "dither", label = "Dithering", kind = "cycle" },
  { key = "visDitherAmt", label = "Dither strength", lo = 0, hi = 3, step = 0.1 },
  { key = "visBloom", label = "Bloom", lo = 0, hi = 1.5, step = 0.05 },
  { key = "visBright", label = "Brightness", lo = 0.5, hi = 1.8, step = 0.05 },
  { key = "visGamma", label = "Gamma", lo = 0.5, hi = 1.8, step = 0.05 },
  { key = "visContrast", label = "Contrast", lo = -0.3, hi = 0.7, step = 0.05 },
  { key = "visSat", label = "Saturation", lo = 0, hi = 2, step = 0.05 },
  { key = "visVig", label = "Vignette", lo = 0, hi = 2.5, step = 0.05 },
  { key = "visAberr", label = "Colour fringing", lo = 0, hi = 3, step = 0.1 },
}

function visuals.isOpen()
  return open
end

function visuals.toggle()
  open = not open
  dragging = nil
end

local function snap(r, v)
  return math.max(r.lo, math.min(r.hi, math.floor(v / r.step + 0.5) * r.step))
end

local function nudge(r, dir)
  if r.kind == "cycle" then
    settings.set(r.key, (settings.get(r.key) + dir) % #render.DITHER_NAMES)
  else
    settings.preview(r.key, snap(r, settings.get(r.key) + dir * r.step))
    settings.save()
  end
end

function visuals.keypressed(key)
  if key == "escape" or key == "f4" then
    visuals.toggle()
  elseif key == "up" then
    sel = (sel - 2) % #ROWS + 1
  elseif key == "down" then
    sel = sel % #ROWS + 1
  elseif key == "left" then
    nudge(ROWS[sel], -1)
  elseif key == "right" then
    nudge(ROWS[sel], 1)
  elseif key == "r" then
    settings.resetVisuals()
  end
end

local function dragTo(i, x)
  local r, rc = ROWS[i], rects[i]
  local t = math.max(0, math.min(1, (x - rc.sx) / rc.sw))
  settings.preview(r.key, snap(r, r.lo + t * (r.hi - r.lo)))
end

function visuals.mousepressed(x, y, button)
  if button ~= 1 then
    return
  end
  for i, rc in ipairs(rects) do
    if x >= rc.x and x <= rc.x + rc.w and y >= rc.y and y <= rc.y + rc.h then
      if rc.reset then
        settings.resetVisuals()
      else
        sel = i
        if ROWS[i].kind == "cycle" then
          nudge(ROWS[i], 1)
        else
          dragging = i
          dragTo(i, x)
        end
      end
      return
    end
  end
end

function visuals.mousereleased()
  if dragging then
    dragging = nil
    settings.save()
  end
end

function visuals.update()
  if dragging and open then
    if love.mouse.isDown(1) then
      dragTo(dragging, (love.mouse.getPosition()))
    else
      visuals.mousereleased()
    end
  end
end

function visuals.draw(u)
  if not open then
    return
  end
  local ww = love.graphics.getDimensions()
  local f, small = itembar.font(4.4 * u), itembar.font(3.4 * u)
  local rowH = 9 * u
  local w = 130 * u
  local x, y = math.floor(ww - w - 6 * u), math.floor(24 * u)
  local h = (#ROWS + 2) * rowH + 6 * u
  love.graphics.setColor(0.04, 0.03, 0.07, 0.9)
  love.graphics.rectangle("fill", x, y, w, h, 2 * u, 2 * u)
  love.graphics.setColor(0.5, 0.42, 0.3, 0.9)
  love.graphics.rectangle("line", x, y, w, h, 2 * u, 2 * u)
  itembar.shadowPrint("Visuals", x + 4 * u, y + 2 * u, f, { 1, 0.9, 0.7 })
  local hint = "F4 close   R reset"
  itembar.shadowPrint(hint, x + w - 4 * u - small:getWidth(hint), y + 3 * u, small, { 1, 1, 1, 0.6 })
  rects = {}
  local ry = y + rowH + 2 * u
  for i, r in ipairs(ROWS) do
    local on = i == sel
    love.graphics.setColor(on and { 0.16, 0.12, 0.2, 0.95 } or { 0.08, 0.07, 0.11, 0.8 })
    love.graphics.rectangle("fill", x + 3 * u, ry, w - 6 * u, rowH - u, u, u)
    itembar.shadowPrint(r.label, x + 5 * u, ry + 1.5 * u, small, on and { 1, 0.9, 0.6 } or { 0.85, 0.85, 0.9 })
    local v = settings.get(r.key)
    local rc = { x = x + 3 * u, y = ry, w = w - 6 * u, h = rowH - u }
    if r.kind == "cycle" then
      local name = render.DITHER_NAMES[v + 1]
      itembar.shadowPrint(name, x + w - 5 * u - small:getWidth(name), ry + 1.5 * u, small, { 0.6, 0.9, 1 })
    else
      local sx, sw = x + 62 * u, 40 * u
      local t = (v - r.lo) / (r.hi - r.lo)
      love.graphics.setColor(0.25, 0.22, 0.3)
      love.graphics.rectangle("fill", sx, ry + rowH / 2 - u, sw, u * 1.4)
      love.graphics.setColor(1, 0.8, 0.4)
      love.graphics.rectangle("fill", sx + t * sw - u, ry + 1.5 * u, 2 * u, rowH - 4 * u)
      local txt = string.format("%.2f", v)
      itembar.shadowPrint(txt, x + w - 5 * u - small:getWidth(txt), ry + 1.5 * u, small, { 0.8, 0.8, 0.85 })
      rc.sx, rc.sw = sx, sw
    end
    rects[i] = rc
    ry = ry + rowH
  end
  local rr = { x = x + 3 * u, y = ry, w = w - 6 * u, h = rowH - u, reset = true }
  love.graphics.setColor(0.12, 0.07, 0.07, 0.9)
  love.graphics.rectangle("fill", rr.x, rr.y, rr.w, rr.h, u, u)
  local t = "Reset all"
  itembar.shadowPrint(t, rr.x + (rr.w - small:getWidth(t)) / 2, ry + 1.5 * u, small, { 1, 0.6, 0.55 })
  rects[#ROWS + 1] = rr
  if not render.post then
    itembar.shadowPrint("(needs Bloom and colour grading on)", x + 4 * u, ry + rowH, small, { 1, 0.5, 0.4 })
  end
end

return visuals
