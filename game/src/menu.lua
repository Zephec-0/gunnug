-- The menus (design doc §9b): the title screen and its pages (save files,
-- compendium, settings), and the pause menu. While a menu is open the game is
-- paused. The title screen stands over the black hole (src.menubg); the pause
-- menu over the dimmed world.
--
-- Navigation: arrows or WASD move between controls (spatially, so grids and
-- rows work as you'd expect), Enter/Space chooses, left/right change sliders
-- and switches, Q/E (or [ ]) change tabs, Esc/Backspace or the right mouse
-- button go back. The mouse hovers to select and clicks on release (so the
-- click that picks "Play" never reaches the game as a shot).
--
-- The menu carries out its own pages; for anything that changes the game it
-- calls menu.onAction(action, arg), set by src.game:
--   "play" (slot), "continue" (slot: a saved run), "resume", "restart", "title", "quit"
local audio = require("src.audio")
local compendium = require("src.compendium")
local fonts = require("src.fonts")
local input = require("src.input")
local meta = require("src.meta")
local render = require("src.render")
local titlelogo = require("src.titlelogo")
local save = require("src.save")
local settings = require("src.settings")

local menu = {}

menu.onAction = nil

local root -- nil (closed), "title" or "pause"
local stack = {} -- pages over the root: "slots", "compendium", "settings", "confirm"
local focusId -- id of the focused control
local widgets = {} -- the controls drawn last frame
local pressedId -- the control the mouse went down on
local dragging -- a slider being dragged
local mouseX, mouseY = -1, -1
local listening -- { action, slot } while waiting for a key to bind
local confirmBox -- { text, detail, yes, yesLabel, noLabel, danger }
local reveal = false -- scroll the focused control into view (after keyboard moves)
local clock = 0
local enterT = 0 -- time since the page changed (for the fade-in)

-- Compendium page state
local comp = { tab = 1, slot = nil, scroll = 0, target = 0, entry = nil }
-- Settings page state
local settingsTab = 1

-- Colours
local TEXT = { 0.94, 0.95, 1.0 }
local DIM = { 0.66, 0.70, 0.80 }
local FAINT = { 0.42, 0.44, 0.54 }
local ACCENT = { 0.55, 0.75, 1.0 }
local WARM = { 0.98, 0.72, 0.42 }
local BORDER = { 0.55, 0.48, 0.42 }
local DANGER = { 0.95, 0.38, 0.32 }
local RARITY = {
  common = { 0.72, 0.70, 0.68 },
  rare = { 0.45, 0.72, 1.0 },
  cursed = { 0.95, 0.30, 0.32 },
  fused = { 0.25, 1.0, 0.82 },
  epic = { 0.78, 0.50, 1.0 },
}

-- Layout: a 400 x 225 unit space (the game's 640x360 area) centred in the window
local u, ox, oy = 1, 0, 0
local uBase = 1 -- the scale the whole menu is drawn at (a page can shrink itself inside it)
local F = {}

local function X(x)
  return math.floor(ox + x * u)
end
local function Y(y)
  return math.floor(oy + y * u)
end

local function layout(scale, factor)
  uBase = scale
  u = scale * (factor or 1)
  local ww, wh = love.graphics.getDimensions()
  ox = (ww - 400 * u) / 2
  oy = (wh - 225 * u) / 2
  F.small = fonts.get(math.max(9, math.floor(u * 3.4))) -- (the face's 1x size is too small to read on a 1080p screen)
  F.body = fonts.get(math.max(9, math.floor(u * 4)))
  F.head = fonts.get(math.max(12, math.floor(u * 7.5)), "bold")
end

-- Pages ----------------------------------------------------------------------------

local function top()
  return stack[#stack] or root
end

local function setPage()
  focusId = nil
  pressedId = nil
  dragging = nil
  listening = nil
  enterT = 0
end

local function push(page)
  stack[#stack + 1] = page
  setPage()
  love.keyboard.setKeyRepeat(page == "name") -- (backspace repeats while typing a name)
  audio.play("page")
end

local function pop()
  if #stack > 0 then
    local leaving = table.remove(stack)
    setPage()
    love.keyboard.setKeyRepeat(false)
    audio.play("back")
    -- Coming back to a list puts the focus back where it was
    if leaving == "slots" then
      focusId = "title:slots"
    elseif leaving == "compendium" then
      focusId = root .. ":compendium"
    elseif leaving == "settings" then
      focusId = root .. ":settings"
    elseif leaving == "name" then
      focusId = "title:slots"
    end
    return true
  end
  return false
end

local function act(action, arg)
  if menu.onAction then
    menu.onAction(action, arg)
  end
end

local NAME_MAX = 14
local nameState = { slot = nil, text = "" }

local function confirm(box)
  confirmBox = box
  push("confirm")
  focusId = "confirm:no"
end

-- Starts a run on slot i: a file with no name yet asks for one first, and a
-- slot with a saved run asks before that run is thrown away
local function startSlot(i)
  local p = save.peek(i)
  if p and p.name then
    if save.peekRun(i) then
      confirm({ text = "Start a new run?", detail = "The run saved in this slot will be lost.", yesLabel = "New run", danger = true, yes = function()
        act("play", i)
      end })
    else
      act("play", i)
    end
  else
    nameState = { slot = i, text = "" }
    push("name")
  end
end

local recapData -- what the death recap tells: { name, killer, quip, discoveries }

-- data: for "recap", the death to tell (see game.update)
local campNpc -- whose page is open at camp (src.npcs)
local mapDrag -- a right-button drag on the survey map: { x, y, moved }

function menu.open(which, data)
  root = which
  recapData = data
  if which == "camp" then
    campNpc = data
  end
  stack = {}
  setPage()
  love.keyboard.setKeyRepeat(false)
  if which == "title" then
    comp.slot = nil
  end
end

function menu.close()
  root = nil
  stack = {}
  setPage()
  love.keyboard.setKeyRepeat(false)
end

function menu.isOpen()
  return root ~= nil
end

function menu.state()
  return root
end

-- The title screen and its pages (drawn over the black hole, not the world)
function menu.isFrontEnd()
  return root == "title"
end

-- Controls ---------------------------------------------------------------------------

local function inside(w, x, y)
  if w.clip then
    local c = w.clip
    if x < c[1] or y < c[2] or x >= c[1] + c[3] or y >= c[2] + c[4] then
      return false
    end
  end
  return x >= w.x and y >= w.y and x < w.x + w.w and y < w.y + w.h
end

local function hovered()
  for i = #widgets, 1, -1 do
    if inside(widgets[i], mouseX, mouseY) then
      return widgets[i]
    end
  end
  return nil
end

local function find(id)
  for _, w in ipairs(widgets) do
    if w.id == id then
      return w
    end
  end
  return nil
end

-- Registers a control for this frame; returns true if it has the focus
local function widget(w)
  widgets[#widgets + 1] = w
  return focusId == w.id
end

local function shadowPrint(text, x, y, f, color, alpha)
  love.graphics.setFont(f)
  local a = (color[4] or 1) * (alpha or 1)
  love.graphics.setColor(0, 0, 0, 0.55 * a)
  love.graphics.print(text, math.floor(x) + math.max(1, math.floor(u * 0.4)), math.floor(y) + math.max(1, math.floor(u * 0.4)))
  love.graphics.setColor(color[1], color[2], color[3], a)
  love.graphics.print(text, math.floor(x), math.floor(y))
end

local function printCentered(text, cx, y, f, color, alpha)
  shadowPrint(text, cx - f:getWidth(text) / 2, y, f, color, alpha)
end

local function wrapped(text, x, y, width, f, color)
  love.graphics.setFont(f)
  love.graphics.setColor(color)
  love.graphics.printf(text, math.floor(x), math.floor(y), math.floor(width), "left")
  local _, lines = f:getWrap(text, width)
  return #lines * f:getHeight() * f:getLineHeight()
end

-- Rectangles that stand in the light and cast shadows: this frame's are
-- collected as they are drawn, and last frame's are what the shadows use
local casting, casters = {}, {}
local function cast(x, y, w, h)
  casting[#casting + 1] = { x = x, y = y, w = w, h = h }
end

local function panel(x, y, w, h, alpha, edge)
  cast(x, y, w, h)
  love.graphics.setColor(0.045, 0.035, 0.065, alpha or 0.9)
  love.graphics.rectangle("fill", x, y, w, h, u, u)
  love.graphics.setLineWidth(math.max(1, u * 0.4))
  local e = edge or BORDER
  love.graphics.setColor(e[1], e[2], e[3], (e[4] or 0.75))
  love.graphics.rectangle("line", x, y, w, h, u, u)
end

-- A focus frame: a bright edge with small corner ticks, pulsing gently
local function focusFrame(x, y, w, h, color)
  color = color or ACCENT
  local pulse = 0.75 + 0.25 * math.sin(clock * 5)
  love.graphics.setLineWidth(math.max(1, u * 0.5))
  love.graphics.setColor(color[1], color[2], color[3], pulse)
  love.graphics.rectangle("line", x, y, w, h, u, u)
  local t = math.max(2, math.floor(u * 2))
  local k = math.max(1, math.floor(u * 0.6))
  love.graphics.setColor(1, 1, 1, pulse)
  love.graphics.rectangle("fill", x - k, y - k, t, k)
  love.graphics.rectangle("fill", x - k, y - k, k, t)
  love.graphics.rectangle("fill", x + w + k - t, y + h, t, k)
  love.graphics.rectangle("fill", x + w, y + h + k - t, k, t)
end

-- Trim text to fit a width, ending in ".." when it is cut
local function fitText(font, text, maxw)
  if font:getWidth(text) <= maxw then
    return text
  end
  while #text > 1 and font:getWidth(text .. "..") > maxw do
    text = text:sub(1, -2)
  end
  return text .. ".."
end

-- The item bar's slot look for anything you can pick: stepped corners, the dark
-- slot fill and a bevel. state: "selected" (the chosen one: blue rim and wash),
-- "focus" (under the cursor or the keys: a pulsing bright rim), or nothing.
-- border/fill override the resting colours (a rarity's rim, say).
local SLOT_REST = { 0.55, 0.48, 0.42, 0.9 }
local SLOT_FILL = { 0.08, 0.06, 0.10, 0.82 }
local SLOT_SELECTED = { 0.55, 0.75, 1, 1 }
local SLOT_SELECTED_WASH = { 0.45, 0.65, 1, 0.14 }
local SLOT_GOLD = { 0.80, 0.64, 0.30, 0.95 }
local SLOT_GOLD_WASH = { 0.80, 0.64, 0.30, 0.14 }
local focusBorder = { 0.8, 0.9, 1, 1 }
-- Rounded boxes with every corner the same: each corner is one quarter-disc image
-- (smooth edge, made once per radius) drawn mirrored into all four, so they cannot differ
local cornerImages = {}
local function cornerImage(r, bw)
  local key = r .. ":" .. bw
  local c = cornerImages[key]
  if not c then
    local fillData, ringData = love.image.newImageData(r, r), love.image.newImageData(r, r)
    for j = 0, r - 1 do
      for i = 0, r - 1 do
        local d = math.sqrt((r - i - 0.5) ^ 2 + (r - j - 0.5) ^ 2)
        local outer = math.max(0, math.min(1, r - d + 0.5))
        local inner = math.max(0, math.min(1, r - bw - d + 0.5))
        fillData:setPixel(i, j, 1, 1, 1, outer)
        ringData:setPixel(i, j, 1, 1, 1, outer - inner)
      end
    end
    c = { fill = love.graphics.newImage(fillData), ring = love.graphics.newImage(ringData) }
    c.fill:setFilter("nearest", "nearest")
    c.ring:setFilter("nearest", "nearest")
    cornerImages[key] = c
  end
  return c
end

local function fourCorners(img, x, y, w, h, r)
  love.graphics.draw(img, x, y)
  love.graphics.draw(img, x + w, y, 0, -1, 1)
  love.graphics.draw(img, x, y + h, 0, 1, -1)
  love.graphics.draw(img, x + w, y + h, 0, -1, -1)
end

local function roundBox(x, y, w, h, r, color)
  r = math.min(r, math.floor(math.min(w, h) / 2))
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
  love.graphics.rectangle("fill", x + r, y, w - 2 * r, h)
  love.graphics.rectangle("fill", x, y + r, r, h - 2 * r)
  love.graphics.rectangle("fill", x + w - r, y + r, r, h - 2 * r)
  fourCorners(cornerImage(r, 1).fill, x, y, w, h, r)
end

local function roundRim(x, y, w, h, r, bw, color)
  r = math.min(r, math.floor(math.min(w, h) / 2))
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
  love.graphics.rectangle("fill", x + r, y, w - 2 * r, bw)
  love.graphics.rectangle("fill", x + r, y + h - bw, w - 2 * r, bw)
  love.graphics.rectangle("fill", x, y + r, bw, h - 2 * r)
  love.graphics.rectangle("fill", x + w - bw, y + r, bw, h - 2 * r)
  fourCorners(cornerImage(r, bw).ring, x, y, w, h, r)
end

local function slotBox(x, y, w, h, state, border, fill, wash)
  x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
  cast(x, y, w, h)
  if state == "selected" then
    border = SLOT_SELECTED
    wash = wash or SLOT_SELECTED_WASH
  elseif state == "gold" then
    border = SLOT_GOLD
    wash = wash or SLOT_GOLD_WASH
  elseif state == "focus" then
    local pulse = 0.75 + 0.25 * math.sin(clock * 5)
    focusBorder[4] = pulse
    border = focusBorder
  end
  local r = math.max(2, math.floor(u * 1.7))
  local bw = math.max(1, math.floor(u * 0.45))
  local b = border or SLOT_REST
  local f = fill or SLOT_FILL
  roundBox(x, y, w, h, r, f)
  if wash then
    roundBox(x + 1, y + 1, w - 2, h - 2, math.max(1, r - 1), wash)
  end
  -- A bevel just inside: a light line along the top, a dark one along the bottom
  if h >= 8 * u then
    local bw = math.max(1, math.floor(u * 0.35))
    love.graphics.setColor(1, 1, 1, 0.07)
    love.graphics.rectangle("fill", x + r, y + bw + 1, w - 2 * r, bw)
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle("fill", x + r, y + h - 2 * bw - 1, w - 2 * r, bw)
  end
  roundRim(x, y, w, h, r, bw, b)
end

-- A button. opts: align ("left"/"center"), sub (a second, dimmer line),
-- danger (red when focused), disabled
local function button(id, label, x, y, w, h, onActivate, opts)
  opts = opts or {}
  cast(x, y, w, h)
  local focused = widget({ id = id, x = x, y = y, w = w, h = h, activate = not opts.disabled and onActivate or nil })
  if focused and opts.danger then
    slotBox(x, y, w, h, nil, { DANGER[1], DANGER[2], DANGER[3], 1 }, { 0.12, 0.05, 0.07, 0.95 })
  else
    slotBox(x, y, w, h, focused and "focus" or nil, nil, focused and { 0.1, 0.09, 0.14, 0.95 } or nil)
  end
  local color = opts.disabled and FAINT or (focused and (opts.danger and DANGER or TEXT) or DIM)
  local f = opts.font or F.body
  local ty = y + (h - f:getHeight()) / 2
  if opts.sub then
    ty = y + h * 0.5 - f:getHeight() * 0.85
  end
  if opts.align == "left" then
    local lx = x + 5 * u + (focused and u * 2 or 0)
    if focused then
      -- A small diamond marker
      love.graphics.setColor(WARM)
      local cx, cy = x + 3 * u, y + h / 2
      love.graphics.polygon("fill", cx, cy - u, cx + u, cy, cx, cy + u, cx - u, cy)
    end
    shadowPrint(label, lx, ty, f, color)
    if opts.sub then
      shadowPrint(fitText(F.small, opts.sub, x + w - lx - 3 * u), lx, ty + f:getHeight(), F.small, focused and WARM or FAINT)
    end
  else
    printCentered(label, x + w / 2, ty, f, color)
    if opts.sub then
      printCentered(fitText(F.small, opts.sub, w - 6 * u), x + w / 2, ty + f:getHeight(), F.small, focused and WARM or FAINT)
    end
  end
  return focused
end

-- A slider for a value 0..1 in tenths
local function slider(id, x, y, w, h, value, onChange)
  local function set(v)
    v = math.max(0, math.min(1, math.floor(v * 10 + 0.5) / 10))
    if v ~= value then
      onChange(v)
      audio.play("tick")
    end
  end
  local barX, barW = x, w - 16 * u
  local focused = widget({
    id = id, x = x, y = y, w = w, h = h,
    left = function()
      set(value - 0.1)
    end,
    right = function()
      set(value + 0.1)
    end,
    drag = function(mx)
      set((mx - barX) / barW)
    end,
  })
  local segs = 10
  local gap = math.max(1, math.floor(u * 0.6))
  local sw = (barW - gap * (segs - 1)) / segs
  for i = 1, segs do
    local on = value >= i / segs - 0.001
    local sx = barX + (i - 1) * (sw + gap)
    if on then
      local k = i / segs
      love.graphics.setColor(0.45 + 0.5 * k, 0.55 + 0.17 * k, 0.9 - 0.5 * k, focused and 1 or 0.8)
    else
      love.graphics.setColor(0.16, 0.14, 0.2, 0.9)
    end
    love.graphics.rectangle("fill", math.floor(sx), y + h * 0.25, math.ceil(sw), h * 0.5)
  end
  if focused then
    focusFrame(barX - u, y + h * 0.25 - u, barW + 2 * u, h * 0.5 + 2 * u)
  end
  shadowPrint(math.floor(value * 100 + 0.5) .. "%", x + w - 13 * u, y + (h - F.body:getHeight()) / 2, F.body, focused and TEXT or DIM)
end

-- An on/off switch
local function toggle(id, x, y, w, h, value, onChange)
  local function flip()
    onChange(not value)
    audio.play("tick")
  end
  local focused = widget({ id = id, x = x, y = y, w = w, h = h, activate = flip, left = flip, right = flip })
  local half = w / 2
  for i = 0, 1 do
    local on = (i == 1) == value
    slotBox(x + i * half, y + h * 0.1, half - u, h * 0.8, on and "selected" or (focused and "focus" or nil))
    printCentered(i == 0 and "Off" or "On", x + i * half + half / 2 - u / 2, y + (h - F.body:getHeight()) / 2, F.body, on and TEXT or FAINT)
  end
end

local function rule(cx, y, width)
  fonts.rule(cx, y, width, math.max(1, math.floor(u * 0.5)), ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
end

local function pageTitle(text, x, y, center)
  if center then
    printCentered(text, x, y, F.head, TEXT)
    rule(x, y + F.head:getHeight() + u, math.max(F.head:getWidth(text) * 1.4, 90 * u))
  else
    shadowPrint(text, x, y, F.head, TEXT)
  end
end


-- Tabs along the top of a page; returns nothing (switching is handled by the caller's state)
local function tabs(idPrefix, names, current, x, y, w, h, onSelect)
  local tw = w / #names
  for i, name in ipairs(names) do
    local tx = x + (i - 1) * tw
    local sel = i == current
    local focused = widget({ id = idPrefix .. i, x = tx, y = y, w = tw - u, h = h, activate = function()
      onSelect(i)
    end })
    slotBox(tx, y, tw - u, h, sel and "selected" or (focused and "focus" or nil))
    printCentered(name, tx + (tw - u) / 2, y + (h - F.body:getHeight()) / 2, F.body, sel and TEXT or (focused and TEXT or DIM))
  end
end

-- The title screen -------------------------------------------------------------------

-- The title's lettering: its position in game pixels, and its font (drawn
-- scaled up by whole game pixels, so it matches the game's pixel size)
local TITLE_Y = 72

local function lastProfileSlot()
  local s = settings.get("lastSlot")
  if s and save.peek(s) then
    return s
  end
  return nil
end

local function anyProfileSlot()
  local s = lastProfileSlot()
  if s then
    return s
  end
  for i = 1, save.SLOTS do
    if save.peek(i) then
      return i
    end
  end
  return 1
end

local function slotSummary(i)
  local p = save.peek(i)
  if not p then
    return nil
  end
  local found, total = compendium.progress(p)
  return string.format("%sSlot %d - %s - %d%%", p.name and (p.name .. " - ") or "", i, save.formatTime(p.playtime), total > 0 and math.floor(found / total * 100) or 0)
end

-- "Sulfur Caves - 340 gold" for slot i's saved run
local function runSummary(i)
  local r = save.peekRun(i)
  if not r then
    return nil
  end
  local name = (r.area or 0) > 0 and r.areaName or "The Barrens"
  return string.format("%s - %d gold", name or "The caves", tonumber(r.inv.gold) or 0)
end

local PAGES = {}
local WASH_STEPS = 24
local washMesh
local DEFAULT_FOCUS = { compendium = "comp:cell:", slots = "slots:", settings = "set:tab", recap = "recap:new", name = "name:confirm", camp = "camp:up:", board = "board:", ghost = "ghost:", dialog = "dlg:" }

-- The title is lit by the cursor, like a torch in the dark: the mark and the
-- buttons brighten and warm toward it, and cast shadows away from it onto the
-- backdrop. Shadows are drawn pixel-chunky (one canvas pixel per world pixel).
local light = { x = nil, y = nil }
local lightShader, shadowShader, glowImage, shadowCanvas

local function getLightShader()
  if lightShader == nil then
    local ok, shader = pcall(love.graphics.newShader, [[
      extern vec2 lightPos;
      extern float radius;
      extern float power;
      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 t = Texel(tex, uv) * color;
        float d = distance(sc, lightPos) / radius;
        float l = power / (1.0 + d * d);
        vec3 lit = t.rgb * (0.58 + 0.95 * l * vec3(1.0, 0.82, 0.55));
        return vec4(lit, t.a);
      }
    ]])
    lightShader = ok and shader or false
  end
  return lightShader or nil
end

-- Draws the shadow canvas, softened a little more with four offset taps
local function getShadowShader()
  if shadowShader == nil then
    local ok, shader = pcall(love.graphics.newShader, [[
      extern vec2 texel;
      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        float c = 0.25 * (Texel(tex, uv + texel * vec2(-0.75, -0.75)).a
                        + Texel(tex, uv + texel * vec2(0.75, -0.75)).a
                        + Texel(tex, uv + texel * vec2(-0.75, 0.75)).a
                        + Texel(tex, uv + texel * vec2(0.75, 0.75)).a);
        return vec4(color.rgb, c * color.a);
      }
    ]])
    shadowShader = ok and shader or false
  end
  return shadowShader or nil
end

local function lightFlicker()
  return 1 + 0.035 * math.sin(clock * 9.3) + 0.02 * math.sin(clock * 23.7 + 1)
end

-- A soft warm pool of light round the cursor, added over the backdrop
local function drawGlow(lx, ly)
  if not glowImage then
    local n = 96
    local data = love.image.newImageData(n, n)
    for y = 0, n - 1 do
      for x = 0, n - 1 do
        local d = math.sqrt((x + 0.5 - n / 2) ^ 2 + (y + 0.5 - n / 2) ^ 2) / (n / 2)
        local a = d < 1 and (1 - d) ^ 2 or 0
        data:setPixel(x, y, 1, 1, 1, a)
      end
    end
    glowImage = love.graphics.newImage(data)
    glowImage:setFilter("linear", "linear")
  end
  local r = 85 * u * lightFlicker()
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 0.72, 0.42, 0.42)
  love.graphics.draw(glowImage, lx - r, ly - r, 0, 2 * r / glowImage:getWidth(), 2 * r / glowImage:getHeight())
  love.graphics.setBlendMode("alpha")
end

-- Each caster's shadow is its shape smeared away from the light; it grows
-- with distance. They are drawn small and scaled up smoothly, so the edges
-- are soft, and the casters' own footprints are cut out
-- with a stencil (the buttons are translucent).
local function drawShadows(lx, ly, logoX, logoY, logoScale)
  local ww, wh = love.graphics.getDimensions()
  local cell = math.max(1, math.floor(render.scale + 0.5))
  local k = cell * 2.6
  local cw, ch = math.ceil(ww / k), math.ceil(wh / k)
  if not shadowCanvas or shadowCanvas:getWidth() ~= cw or shadowCanvas:getHeight() ~= ch then
    shadowCanvas = love.graphics.newCanvas(cw, ch)
    shadowCanvas:setFilter("linear", "linear")
  end
  local reach = 9 * u
  local function smear(cx, cy)
    local dx, dy = cx - lx, cy - ly
    local d = math.sqrt(dx * dx + dy * dy) + 0.001
    local len = reach * d / (d + 60 * u)
    local ox, oy = dx / d * len, dy / d * len
    return ox, oy, math.max(1, math.ceil(len / k))
  end
  love.graphics.push("all")
  love.graphics.setCanvas(shadowCanvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.scale(1 / k)
  love.graphics.setColor(0, 0, 0, 1)
  if logoX then
    local tw, th = titlelogo.W * logoScale, titlelogo.H * logoScale
    local ox, oy, steps = smear(logoX + tw / 2, logoY + th / 2)
    for i = 1, steps do
      titlelogo.silhouette(logoX + ox * i / steps, logoY + oy * i / steps, logoScale)
    end
  end
  for _, r in ipairs(casters) do
    local ox, oy, steps = smear(r.x + r.w / 2, r.y + r.h / 2)
    for i = 1, steps do
      love.graphics.rectangle("fill", r.x + ox * i / steps, r.y + oy * i / steps, r.w, r.h, u, u)
    end
  end
  love.graphics.pop()

  love.graphics.stencil(function()
    for _, r in ipairs(casters) do
      love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, u, u)
    end
  end, "replace", 1)
  love.graphics.setStencilTest("equal", 0)
  local shader = getShadowShader()
  if shader then
    shader:send("texel", { 1 / cw, 1 / ch })
    love.graphics.setShader(shader)
  end
  love.graphics.setColor(0.01, 0.005, 0.02, 0.65)
  love.graphics.draw(shadowCanvas, 0, 0, 0, k, k)
  love.graphics.setShader()
  love.graphics.setStencilTest()
end

-- The page's light: a glow and shadows over its backdrop, then everything the
-- page draws after this is lit. (logoX/logoY/logoScale: the title mark, if any)
local function litBackdrop(logoX, logoY, logoScale)
  love.graphics.setShader()
  light.x, light.y = love.mouse.getPosition() -- read at draw time: no lag behind the cursor
  local lx, ly = light.x, light.y
  drawGlow(lx, ly)
  drawShadows(lx, ly, logoX, logoY, logoScale)
  local shader = getLightShader()
  if shader then
    shader:send("lightPos", { lx, ly })
    shader:send("radius", 90 * u)
    shader:send("power", lightFlicker())
    love.graphics.setShader(shader)
  end
end

PAGES.title = function()
  local ww, wh = love.graphics.getDimensions()
  -- A dark wash down the left, under the menu: one smooth gradient
  washMesh = washMesh or love.graphics.newMesh(WASH_STEPS * 2 + 2, "strip", "static")
  for i = 0, WASH_STEPS do
    local k = i / WASH_STEPS
    local x = k * ww * 0.5
    local a = 0.8 * (1 - k) ^ 1.5
    washMesh:setVertex(i * 2 + 1, x, 0, 0, 0, 0.02, 0.015, 0.035, a)
    washMesh:setVertex(i * 2 + 2, x, wh, 0, 0, 0.02, 0.015, 0.035, a)
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(washMesh)

  -- The mark, centred over the menu column
  local x, y, w, h, gap = X(34), Y(104), math.floor(118 * u), math.floor(13 * u), math.floor(3.5 * u)
  local logoScale = titlelogo.PX * render.scale
  local tw, th = titlelogo.W * logoScale, titlelogo.H * logoScale
  local _, ty = render.toScreen(0, TITLE_Y)
  local logoX = math.floor(x + w / 2 - tw / 2)

  -- The cursor is the light
  litBackdrop(logoX, ty, logoScale)
  titlelogo.draw(logoX, ty, logoScale)

  local last = lastProfileSlot()
  if last then
    local saved = save.peekRun(last)
    if saved then
      button("title:resume", "Continue run", x, y, w, math.floor(h * 1.35), function()
        act("continue", last)
      end, { align = "left", sub = runSummary(last) })
      y = y + math.floor(h * 1.35) + gap
    end
    button("title:continue", saved and "New run" or "Continue", x, y, w, math.floor(h * 1.35), function()
      startSlot(last)
    end, { align = "left", sub = slotSummary(last) })
    y = y + math.floor(h * 1.35) + gap
  end
  local anySaves = false
  for i = 1, save.SLOTS do
    anySaves = anySaves or save.peek(i) ~= nil
  end
  button("title:slots", anySaves and "Save Files" or "New Game", x, y, w, h, function()
    push("slots")
  end, { align = "left" })
  y = y + h + gap
  button("title:compendium", "Compendium", x, y, w, h, function()
    comp.slot = comp.slot or anyProfileSlot()
    push("compendium")
  end, { align = "left" })
  y = y + h + gap
  button("title:settings", "Settings", x, y, w, h, function()
    push("settings")
  end, { align = "left" })
  y = y + h + gap
  button("title:quit", "Quit", x, y, w, h, function()
    act("quit")
  end, { align = "left" })
end

-- The low-res part of the title screen (between render.beginWorld and
-- endWorld): nothing at the moment (the title is drawn over the menu's wash)
function menu.drawWorldLayer() end

-- Save files ---------------------------------------------------------------------------

local function deepestName(p)
  local d = p.stats.deepest or 0
  if d <= 0 then
    return "The Barrens"
  end
  local ok, catacombs = pcall(require, "src.scenes.catacombs")
  return ok and catacombs.areaName(d) or ("Area " .. d)
end

PAGES.slots = function()
  litBackdrop()
  pageTitle("Save Files", X(22), Y(14))
  shadowPrint("Each file keeps its own compendium and records. Quitting a run saves it.", X(22), Y(30), F.small, FAINT)
  local x, w, h = X(22), math.floor(230 * u), math.floor(40 * u)
  local y = Y(42)
  for i = 1, save.SLOTS do
    local p = save.peek(i)
    local cardW = w - math.floor(36 * u)
    local focused = widget({ id = "slots:" .. i, x = x, y = y, w = cardW, h = h, activate = function()
      startSlot(i)
    end })
    panel(x, y, cardW, h, focused and 0.95 or 0.82)
    if focused then
      focusFrame(x, y, cardW, h)
    end
    local px, py = x + 5 * u, y + 4 * u
    shadowPrint("Slot " .. i, px, py, F.body, focused and WARM or TEXT)
    local after = px + F.body:getWidth("Slot " .. i) + 3 * u
    if p and p.name then
      shadowPrint(p.name, after, py, F.body, focused and TEXT or DIM)
      after = after + F.body:getWidth(p.name) + 3 * u
    end
    if save.activeSlot() == i then
      shadowPrint("(in use)", after, py + u, F.small, FAINT)
    end
    if p then
      local found, total = compendium.progress(p)
      local pct = total > 0 and found / total or 0
      local right = x + cardW - 5 * u
      local label = string.format("%d / %d", found, total)
      shadowPrint(label, right - F.body:getWidth(label), py, F.body, DIM)
      -- Completion bar
      local by = py + F.body:getHeight() + 1.5 * u
      local bw = cardW - 10 * u
      love.graphics.setColor(0.14, 0.12, 0.18)
      love.graphics.rectangle("fill", px, by, bw, math.max(2, u * 1.2))
      love.graphics.setColor(WARM)
      love.graphics.rectangle("fill", px, by, bw * pct, math.max(2, u * 1.2))
      local s = p.stats
      local l1 = string.format("Playtime %s    Runs %d    Resets %d", save.formatTime(p.playtime), s.runs, s.resets or s.deaths or 0)
      local l2 = string.format("Monsters slain %d    Bosses %d    Gold earned %d    Marks %d", s.kills, s.bosses, s.gold, p.marks or 0)
      local l3 = "Deepest: " .. deepestName(p) .. "    Last played " .. os.date("%Y-%m-%d", p.lastPlayed)
      if save.peekRun(i) then
        l3 = "Run saved: " .. runSummary(i) .. "    " .. l3
      end
      shadowPrint(l1, px, by + 3.5 * u, F.small, DIM)
      shadowPrint(l2, px, by + 3.5 * u + F.small:getHeight() * 1.3, F.small, DIM)
      shadowPrint(l3, px, by + 3.5 * u + F.small:getHeight() * 2.6, F.small, FAINT)
    else
      shadowPrint("Empty", px, py + F.body:getHeight() + 3 * u, F.body, FAINT)
      shadowPrint("Start a new hunter here", px, py + F.body:getHeight() * 2 + 4 * u, F.small, focused and WARM or FAINT)
    end
    -- Delete
    local dx = x + cardW + 3 * u
    local saved = p and save.peekRun(i)
    if saved then
      button("slots:resume" .. i, "Resume", dx, y, math.floor(33 * u), math.floor(h * 0.48), function()
        act("continue", i)
      end, { font = F.small })
    end
    if p then
      local dy, dh = y, h
      if saved then
        dy, dh = y + math.floor(h * 0.52), math.floor(h * 0.48)
      end
      button("slots:delete" .. i, "Delete", dx, dy, math.floor(33 * u), dh, function()
        confirm({
          text = "Delete Slot " .. i .. "?",
          detail = "Its compendium and records will be lost for good.",
          yesLabel = "Delete",
          danger = true,
          yes = function()
            save.erase(i)
            if settings.get("lastSlot") == i then
              settings.set("lastSlot", false)
            end
            pop()
            focusId = "slots:" .. i
          end,
        })
      end, { danger = true, font = F.small })
    end
    y = y + h + math.floor(5 * u)
  end
end

-- Confirmation box -------------------------------------------------------------------

PAGES.confirm = function()
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  local b = confirmBox
  local w, h = math.floor(180 * u), math.floor(46 * u)
  local x, y = math.floor((ww - w) / 2), math.floor((wh - h) / 2)
  panel(x, y, w, h, 0.97, b.danger and DANGER or BORDER)
  printCentered(b.text, x + w / 2, y + 7 * u, F.body, TEXT)
  if b.detail then
    printCentered(b.detail, x + w / 2, y + 7 * u + F.body:getHeight() * 1.4, F.small, DIM)
  end
  local bw, bh = math.floor(60 * u), math.floor(12 * u)
  local by = y + h - bh - 7 * u
  button("confirm:yes", b.yesLabel or "Yes", math.floor(x + w / 2 - bw - 3 * u), by, bw, bh, function()
    b.yes()
  end, { danger = b.danger })
  button("confirm:no", b.noLabel or "Cancel", math.floor(x + w / 2 + 3 * u), by, bw, bh, function()
    pop()
  end)
end

-- Compendium -------------------------------------------------------------------------

local function compProfile()
  if root == "pause" then
    return save.profile()
  end
  return comp.slot and save.peek(comp.slot) or nil
end

local function profileSlots()
  local out = {}
  for i = 1, save.SLOTS do
    if save.peek(i) then
      out[#out + 1] = i
    end
  end
  return out
end

local function cycleSlot(dir)
  local list = profileSlots()
  if #list < 2 then
    return
  end
  local idx = 1
  for i, s in ipairs(list) do
    if s == comp.slot then
      idx = i
    end
  end
  comp.slot = list[(idx - 1 + dir) % #list + 1]
  audio.play("page")
end

local function setCompTab(i)
  local n = #compendium.CATEGORIES
  i = (i - 1) % n + 1
  if i ~= comp.tab then
    comp.tab = i
    comp.scroll, comp.target = 0, 0
    comp.entry = nil
    audio.play("page")
  end
end

-- A small brass padlock, s window pixels per pixel, top-left at (x, y): 5 x 6
local function padlock(x, y, s, alpha)
  local a = alpha or 1
  love.graphics.setColor(0.05, 0.04, 0.06, 0.8 * a)
  love.graphics.rectangle("fill", x - s, y - s, 7 * s, 8 * s)
  love.graphics.setColor(0.62, 0.63, 0.68, a)
  love.graphics.rectangle("fill", x + s, y, 3 * s, s)
  love.graphics.rectangle("fill", x + s, y, s, 2 * s)
  love.graphics.rectangle("fill", x + 3 * s, y, s, 2 * s)
  love.graphics.setColor(0.86, 0.66, 0.28, a)
  love.graphics.rectangle("fill", x, y + 2 * s, 5 * s, 4 * s)
  love.graphics.setColor(0.3, 0.2, 0.08, a)
  love.graphics.rectangle("fill", x + 2 * s, y + 3 * s, s, 2 * s)
end

local GATED = { weapon = true, ammo = true, attachment = true }

-- Whether an entry is locked for a profile (src.meta), and whether it's been seen
local function lockState(profile, cat, entry)
  if not profile or not GATED[cat] or entry.level or entry.recipe then
    return false, false
  end
  return not meta.isUnlocked(cat, entry.id, profile), meta.isSeen(cat, entry.id, profile)
end

-- The +1 to +4 tiers of a common item as a column of small bars in a box
-- (top = +4, bottom = +1): grey until that tier has been collected
local ROMAN = { "I", "II", "III", "IV", "V" }
local function drawTierBars(entry, got, x, y, w, h)
  local n = #entry.tiers
  local gap = math.max(1, math.floor(u * 0.6))
  local bh = math.max(1, math.floor((h - gap * (n - 1)) / n))
  local c = RARITY.fused
  -- (drawn in a real font of its own, a point up from the small one, never scaled: scaled
  -- bitmap lettering comes out ragged)
  local f = fonts.get(math.max(9, math.floor(u * 3.4)) + 1)
  local sc = 1
  love.graphics.setFont(f)
  for level = 1, n do
    local by = y + (n - level) * (bh + gap)
    local have = (got[entry.tiers[level]] or 0) > 0
    if have then
      love.graphics.setColor(c[1] * 0.85, c[2] * 0.85, c[3] * 0.85, 1)
    else
      love.graphics.setColor(0.17, 0.16, 0.21, 1)
    end
    love.graphics.rectangle("fill", x, by, w, bh)
    local t = ROMAN[level]
    local tw, th = f:getWidth(t) * sc, f:getHeight() * sc
    love.graphics.setColor(have and 0.02 or 0.4, have and 0.1 or 0.38, have and 0.1 or 0.46, 1)
    love.graphics.print(t, math.floor(x + (w - tw) / 2), math.floor(by + (bh - th) / 2), 0, sc, sc)
  end
end

-- A soft radial gradient (white, fading out smoothly), tinted when drawn
local lightImage
local function getLightImage()
  if not lightImage then
    local n = 128
    local data = love.image.newImageData(n, n)
    for y = 0, n - 1 do
      for x = 0, n - 1 do
        local d = math.sqrt((x + 0.5 - n / 2) ^ 2 + (y + 0.5 - n / 2) ^ 2) / (n / 2)
        local a = d < 1 and math.exp(-d * d * 3.2) * (1 - d * d) or 0
        data:setPixel(x, y, 1, 1, 1, a)
      end
    end
    lightImage = love.graphics.newImage(data)
    lightImage:setFilter("linear", "linear")
  end
  return lightImage
end

-- The item as a light source on its plate: a wide pool of its colour that breathes,
-- a hot white-tinted core, a pool of light spread along the floor of the plate, and
-- a few motes of it drifting up. Added over the plate, kept inside it.
local function itemLight(x, y, w, h, c)
  local img = getLightImage()
  local iwid = img:getWidth()
  local t = clock
  local breathe = 1 + 0.06 * math.sin(t * 2.1) + 0.03 * math.sin(t * 5.3 + 1)
  local cx, cy = x + w / 2, y + h * 0.48
  local prevShader = love.graphics.getShader()
  love.graphics.setShader()
  love.graphics.setScissor(x, y, w, h)
  love.graphics.setBlendMode("add")
  local function pool(px, py, rx, ry, r, g, b, a)
    love.graphics.setColor(r, g, b, a)
    love.graphics.draw(img, px - rx, py - ry, 0, 2 * rx / iwid, 2 * ry / iwid)
  end
  local hot = { c[1] + (1 - c[1]) * 0.55, c[2] + (1 - c[2]) * 0.55, c[3] + (1 - c[3]) * 0.55 }
  pool(cx, cy, w * 0.62 * breathe, h * 0.95 * breathe, c[1], c[2], c[3], 0.5)
  pool(x + w / 2, y + h * 0.97, w * 0.5 * breathe, h * 0.2, c[1], c[2], c[3], 0.32)
  pool(cx, cy, h * 0.42 * breathe, h * 0.42 * breathe, hot[1], hot[2], hot[3], 0.55)
  -- Motes
  local m = math.max(1, math.floor(u * 0.5))
  for i = 1, 7 do
    local k = (t * (0.07 + i * 0.011) + i * 0.37) % 1
    local mx = cx + math.sin(i * 12.9 + t * 0.6) * w * 0.3 + math.sin(i * 3.1) * w * 0.08
    local my = y + h * (0.95 - k * 0.9)
    local a = math.sin(k * math.pi) * 0.7
    love.graphics.setColor(hot[1], hot[2], hot[3], a)
    love.graphics.rectangle("fill", math.floor(mx), math.floor(my), m, m)
  end
  love.graphics.setBlendMode("alpha")
  love.graphics.setScissor()
  love.graphics.setShader(prevShader)
end

local function drawDetail(entry, profile, cat, x, y, w, h)
  panel(x, y, w, h, 0.92)
  if not entry then
    printCentered("Select an entry", x + w / 2, y + h / 2 - F.body:getHeight() / 2, F.body, FAINT)
    return
  end
  local count = profile and (profile.found[cat.id] or {})[entry.id] or 0
  local known = count > 0
  local locked, seen = lockState(profile, cat.id, entry)
  -- The picture: on a dark plate, with a soft glow behind it when known
  local ix, iy, iw, ih = x + 4 * u, y + 4 * u, w - 8 * u, math.floor(52 * u)
  love.graphics.setColor(0.02, 0.015, 0.03, 0.9)
  love.graphics.rectangle("fill", ix, iy, iw, ih, u, u)
  if known then
    itemLight(ix, iy, iw, ih, entry.boss and DANGER or entry.color or (entry.rarity and RARITY[entry.rarity]) or WARM)
    if cat.id == "enemy" then
      compendium.drawLive(entry, ix + 4 * u, iy + 4 * u, iw - 8 * u, ih - 8 * u)
    else
      compendium.drawIcon(entry, ix + 4 * u, iy + 4 * u, iw - 8 * u, ih - 8 * u)
    end
  else
    compendium.drawIcon(entry, ix + 4 * u, iy + 4 * u, iw - 8 * u, ih - 8 * u, true)
  end
  local ty = iy + ih + 4 * u
  local tx = x + 5 * u
  local tw = w - 10 * u
  shadowPrint((known or seen) and entry.name or "???", tx, ty, F.body, known and TEXT or (seen and DIM or FAINT))
  ty = ty + F.body:getHeight() + u
  -- Rarity / kind line
  local tag
  if entry.boss then
    tag = "Boss"
  elseif entry.rarity then
    tag = (entry.rarity:sub(1, 1):upper() .. entry.rarity:sub(2))
  end
  if tag then
    shadowPrint(tag, tx, ty, F.small, entry.boss and DANGER or RARITY[entry.rarity] or DIM)
  end
  local countText = known and (cat.verb .. " x" .. count) or (seen and "Seen" or "Not yet discovered")
  shadowPrint(countText, x + w - 5 * u - F.small:getWidth(countText), ty, F.small, known and WARM or FAINT)
  ty = ty + F.small:getHeight() * 1.6
  if locked then
    -- Locked: it never drops or sits in a shop until the Gunsmith learns it
    local text
    if not (profile.camp and profile.camp.gunsmith) then
      text = "Locked. It won't turn up in shops or chests until someone who knows guns learns to make it."
    elseif seen then
      text = "Locked. Teach the Gunsmith at camp to make it: " .. meta.teachCost(cat.id, entry.id) .. " marks."
    else
      text = "Locked. Find one, then teach the Gunsmith to make it."
    end
    padlock(tx, ty + u, math.max(1, math.floor(u * 0.7)))
    ty = ty + wrapped(text, tx + 6 * u, ty, tw - 6 * u, F.small, DANGER) + 2 * u
  end
  if entry.tiers and known then
    -- A common item: its higher tiers, lit as they are collected
    local got = profile and profile.found[cat.id] or {}
    local bar = math.max(2, math.floor(u * 1.2))
    local label = "Tiers"
    shadowPrint(label, tx, ty, F.small, FAINT)
    local lx = tx + F.small:getWidth(label) + 4 * u
    for level = 1, #entry.tiers do
      local have = (got[entry.tiers[level]] or 0) > 0
      local t = ROMAN[level]
      local c = have and RARITY.fused or FAINT
      shadowPrint(t, lx, ty, F.small, c)
      love.graphics.setColor(have and RARITY.fused[1] or 0.2, have and RARITY.fused[2] or 0.19, have and RARITY.fused[3] or 0.24, 1)
      love.graphics.rectangle("fill", lx, ty + F.small:getHeight() + u * 0.5, F.small:getWidth(t), bar)
      lx = lx + F.small:getWidth(t) + 4 * u
    end
    ty = ty + F.small:getHeight() + bar + 2 * u
  end
  if entry.base then
    -- A levelled common item: how it is made
    local text = "Fuse " .. entry.base[3] .. " with itself: +" .. entry.level .. " is as strong as " .. (entry.level + 1) .. " fitted together"
    ty = ty + wrapped(text, tx, ty, tw, F.small, RARITY.fused) + 2 * u
  end
  if entry.recipe then
    -- Fused items: what goes into the fuser (named once both are found)
    local r = entry.recipe
    local haveA = profile and (profile.found[r[1][1]] or {})[r[1][2]] or 0
    local haveB = profile and (profile.found[r[2][1]] or {})[r[2][2]] or 0
    local text
    if known or (haveA > 0 and haveB > 0) then
      text = (known and "Fused from " or "Try fusing ") .. r[1][3] .. " + " .. r[2][3]
    else
      text = "Made in the fuser from two common items"
    end
    ty = ty + wrapped(text, tx, ty, tw, F.small, RARITY.fused) + 2 * u
  end
  if known then
    ty = ty + wrapped(entry.desc, tx, ty, tw, F.body, DIM) + 2 * u
    if entry.stats then
      local colW = tw / 2
      for i, st in ipairs(entry.stats) do
        local cx = tx + ((i - 1) % 2) * colW
        local cy = ty + math.floor((i - 1) / 2) * F.body:getHeight() * 1.35
        shadowPrint(st[1], cx, cy, F.body, FAINT)
        shadowPrint(st[2], cx + colW - 3 * u - F.body:getWidth(st[2]), cy, F.body, TEXT)
      end
    end
  else
    local hintText = cat.id == "enemy" and "Slay one to learn more." or "Find one to learn more."
    wrapped(hintText, tx, ty, tw, F.body, FAINT)
  end
end

local COMP_WINDOW = 0.84 -- the compendium's window, as a share of the full menu space

PAGES.compendium = function()
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.015, 0.01, 0.025, root == "pause" and 0.93 or 0.6)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  layout(uBase, COMP_WINDOW)
  litBackdrop()
  local profile = compProfile()

  -- Header: title, the slot shown, and the overall count
  pageTitle("Compendium", X(14), Y(9))
  local found, total = compendium.progress(profile)
  local overall = string.format("%d / %d discovered (%d%%)", found, total, total > 0 and math.floor(found / total * 100) or 0)
  shadowPrint(overall, X(386) - F.body:getWidth(overall), Y(11), F.body, WARM)
  if root == "title" then
    local slots = profileSlots()
    local label = profile and ("Slot " .. comp.slot) or "No save files yet"
    local lx = X(14) + F.head:getWidth("Compendium") + 10 * u
    local ly = Y(11)
    if #slots > 1 then
      button("comp:slotPrev", "<", lx, ly - u, math.floor(9 * u), math.floor(10 * u), function()
        cycleSlot(-1)
      end)
      shadowPrint(label, lx + 12 * u, ly, F.body, TEXT)
      button("comp:slotNext", ">", lx + 15 * u + F.body:getWidth(label), ly - u, math.floor(9 * u), math.floor(10 * u), function()
        cycleSlot(1)
      end)
    else
      shadowPrint(label, lx, ly, F.body, DIM)
    end
  else
    shadowPrint("Slot " .. tostring(save.activeSlot()), X(14) + F.head:getWidth("Compendium") + 10 * u, Y(11), F.body, DIM)
  end

  -- Tabs, with each category's count
  local names = {}
  for i, c in ipairs(compendium.CATEGORIES) do
    local f, t = compendium.progress(profile, c.id)
    names[i] = c.name .. " " .. f .. "/" .. t
  end
  tabs("comp:tab", names, comp.tab, X(14), Y(27), math.floor(372 * u), math.floor(12 * u), setCompTab)

  -- The grid
  local cat = compendium.CATEGORIES[comp.tab]
  local entries = compendium.entries(cat.id)
  local got = profile and profile.found[cat.id] or {}
  local gx, gy, gw, gh = X(14), Y(44), math.floor(234 * u), math.floor(166 * u)
  panel(gx, gy, gw, gh, 0.85)
  local wide = cat.id == "weapon" or cat.id == "enemy"
  -- (item tiles carry a column of tier bars on their right edge)
  local cellW = math.floor((wide and 36 or 28) * u)
  local cellH = math.floor((wide and 26 or 19) * u)
  local gap = math.floor(3 * u)
  local pad = math.floor(4 * u)
  local cols = math.max(1, math.floor((gw - pad * 2 + gap) / (cellW + gap)))
  local rows = math.ceil(#entries / cols)
  local contentH = rows * (cellH + gap) - gap
  local viewH = gh - pad * 2
  local maxScroll = math.max(0, contentH - viewH)
  -- Keep the focused cell in view
  local focusedIndex
  for i, e in ipairs(entries) do
    if focusId == "comp:cell:" .. e.id then
      focusedIndex = i
      comp.entry = e
    end
  end
  if reveal and focusedIndex then
    local rowTop = math.floor((focusedIndex - 1) / cols) * (cellH + gap)
    if rowTop < comp.target then
      comp.target = rowTop
    elseif rowTop + cellH > comp.target + viewH then
      comp.target = rowTop + cellH - viewH
    end
  end
  comp.target = math.max(0, math.min(maxScroll, comp.target))
  comp.scroll = comp.scroll + (comp.target - comp.scroll) * math.min(1, love.timer.getDelta() * 14)
  local clip = { gx + 1, gy + 1, gw - 2, gh - 2 }
  love.graphics.setScissor(clip[1], clip[2], clip[3], clip[4])
  -- Centre the grid in its panel
  local gridW = cols * (cellW + gap) - gap
  local x0 = gx + math.floor((gw - gridW) / 2)
  for i, e in ipairs(entries) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local cx = x0 + col * (cellW + gap)
    local cy = math.floor(gy + pad + row * (cellH + gap) - comp.scroll)
    local known = (got[e.id] or 0) > 0
    local locked, seen = lockState(profile, cat.id, e)
    local focused = widget({ id = "comp:cell:" .. e.id, x = cx, y = cy, w = cellW, h = cellH, clip = clip, activate = function() end })
    local edge = known and (e.boss and DANGER or (e.level and RARITY.fused) or (e.rarity and e.rarity ~= "common" and RARITY[e.rarity]) or SLOT_REST) or { 0.22, 0.2, 0.27 }
    local rim = { edge[1], edge[2], edge[3], known and 0.9 or 0.6 }
    local wash = known and e.rarity and e.rarity ~= "common" and { edge[1], edge[2], edge[3], 0.07 } or nil
    local isSel = comp.entry == e
    slotBox(cx, cy, cellW, cellH, focused and "focus" or (isSel and "selected" or nil), rim, known and nil or { 0.035, 0.03, 0.05, 0.9 }, wash)
    compendium.drawIcon(e, cx + 2 * u, cy + 2 * u, cellW - (e.tiers and 12 or 4) * u, cellH - 4 * u, not known, (seen and not known) and 1 or nil)
    if seen and not known then
      -- Seen but not collected: the silhouette has a faint rim
      love.graphics.setColor(0.55, 0.5, 0.65, 0.35)
      love.graphics.rectangle("line", cx + 2 * u, cy + 2 * u, cellW - 4 * u, cellH - 4 * u, u * 0.6, u * 0.6)
    end
    if e.tiers then
      drawTierBars(e, got, cx + cellW - 9 * u, cy + 2 * u, 7 * u, cellH - 4 * u)
    end
    if locked then
      local s = math.max(1, math.floor(u * 0.5))
      padlock(cx + cellW - 6 * s - u - (e.tiers and 8 * u or 0), cy + u + s, s, known and 1 or 0.7)
    end
  end
  love.graphics.setScissor()
  -- A scroll bar when the grid is taller than its panel
  if maxScroll > 0 then
    local bh = viewH * viewH / contentH
    local by = gy + pad + (viewH - bh) * (comp.scroll / maxScroll)
    love.graphics.setColor(0.6, 0.55, 0.5, 0.5)
    love.graphics.rectangle("fill", gx + gw - 2 * u, by, math.max(2, u), bh)
  end
  comp.region = { gx, gy, gw, gh, maxScroll }

  if comp.entry and comp.entry.category ~= cat.id then
    comp.entry = nil
  end
  drawDetail(comp.entry or entries[1], profile, cat, X(252), Y(44), math.floor(134 * u), math.floor(166 * u))
  layout(uBase)
end

-- The camp ------------------------------------------------------------------------------
-- Talking to someone at camp (src.npcs) opens their page: the upgrades they
-- sell for marks and, for the Gunsmith, the guns and items he can be taught.

-- What the Gunsmith could still learn: every locked weapon, ammo type and attachment
local function teachList()
  local out = {}
  for _, cat in ipairs({ "weapon", "ammo", "attachment" }) do
    for _, e in ipairs(compendium.entries(cat)) do
      if not e.level and not e.recipe and not meta.isUnlocked(cat, e.id) then
        out[#out + 1] = e
      end
    end
  end
  return out
end

-- "12" with the mark's sigil before it, right-aligned at rx
local function markPrice(text, rx, y, f, color)
  local s = math.max(1, math.floor(u * 0.75 + 0.5))
  local tx = rx - f:getWidth(text)
  shadowPrint(text, tx, y, f, color)
  meta.drawSigil(math.floor(tx - 7 * s - 2 * u), math.floor(y + f:getHeight() / 2 - 3.5 * s), s)
end

-- The Bartender's bottles: a profile per kind (cork, neck, shoulders, body), drawn a row at a time
local BOTTLES = {
  bottle = { neck = 2, neckLen = 6, shoulder = 5, body = 6, bodyLen = 12 },
  flask = { neck = 2, neckLen = 3, shoulder = 5, body = 8, bodyLen = 10 },
  tall = { neck = 2, neckLen = 7, shoulder = 3, body = 5, bodyLen = 15 },
  jug = { neck = 3, neckLen = 2, shoulder = 5, body = 8, bodyLen = 11 },
}

-- Draws a bottle standing with its base at (cx, baseY); p screen pixels per bit of art. Returns its height.
local function drawDrinkBottle(shape, color, cx, baseY, p)
  local d = BOTTLES[shape] or BOTTLES.bottle
  local rows = {}
  for i = 1, 2 do
    rows[#rows + 1] = { hw = d.neck, cork = true }
  end
  for i = 1, d.neckLen do
    rows[#rows + 1] = { hw = d.neck }
  end
  for i = 1, d.shoulder do
    rows[#rows + 1] = { hw = d.neck + math.floor((d.body - d.neck) * (i / d.shoulder) ^ 0.7 + 0.5) }
  end
  for i = 1, d.bodyLen do
    rows[#rows + 1] = { hw = d.body, body = i }
  end
  local top = baseY - #rows * p
  local lit = { math.min(1, color[1] * 1.35 + 0.12), math.min(1, color[2] * 1.35 + 0.12), math.min(1, color[3] * 1.35 + 0.12) }
  for i, r in ipairs(rows) do
    local y = top + (i - 1) * p
    for x = -r.hw, r.hw do
      local edge = x == -r.hw or x == r.hw or i == #rows or (r.cork and i == 1)
      local col
      if r.cork then
        col = { 0.45, 0.30, 0.17, 1 }
      elseif edge then
        col = { 0.62, 0.68, 0.74, 0.95 }
      elseif r.body and r.body >= math.floor(d.bodyLen * 0.3) and r.body <= math.floor(d.bodyLen * 0.75) then
        col = { 0.90, 0.84, 0.68, 1 } -- the label
      elseif x == -r.hw + 1 or x == -r.hw + 2 then
        col = { lit[1], lit[2], lit[3], 0.95 }
      else
        col = { color[1], color[2], color[3], 0.95 }
      end
      love.graphics.setColor(col)
      love.graphics.rectangle("fill", cx + x * p, y, p, p)
    end
  end
  return #rows * p
end

PAGES.camp = function()
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.015, 0.01, 0.025, 0.93)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  litBackdrop()
  local person = meta.PEOPLE[campNpc] or { name = tostring(campNpc) }
  local marks = meta.marks()
  pageTitle(person.name, X(14), Y(9))
  markPrice(marks .. (marks == 1 and " mark" or " marks"), X(386), Y(11), F.body, meta.SIGIL_COLOR)
  shadowPrint(person.blurb or "Upgrades last for every run.", X(14), Y(26), F.small, FAINT)

  -- Upgrades, one card each
  local x, y, w = X(14), Y(36), math.floor(176 * u)
  local hasUpgrades = false
  for _, up in ipairs(meta.UPGRADES) do
    hasUpgrades = hasUpgrades or up.npc == campNpc
  end
  if campNpc == "cartographer" then
    hasUpgrades = false -- (his one upgrade is a small row of its own, to leave the page to the chart)
  end
  if hasUpgrades then
    shadowPrint("Upgrades", x, y, F.body, WARM)
  end
  y = y + F.body:getHeight() + 2 * u
  if campNpc == "cartographer" then
    -- A slim row: its name, tiers and price, and what it does beside it
    for _, up in ipairs(meta.UPGRADES) do
      if up.npc == campNpc then
        local h, rw = math.floor(15 * u), math.floor(130 * u)
        local tier, cost = meta.tier(up.id), meta.nextCost(up.id)
        local focused = widget({ id = "camp:up:" .. up.id, x = x, y = Y(36), w = rw, h = h, activate = function()
          if meta.buy(up.id) then
            audio.play("buy")
          else
            audio.play("deny")
          end
        end })
        local ry = Y(36)
        panel(x, ry, rw, h, focused and 0.95 or 0.82)
        if focused then
          focusFrame(x, ry, rw, h)
        end
        local ty = ry + (h - F.body:getHeight()) / 2
        shadowPrint(up.name, x + 5 * u, ty, F.body, focused and TEXT or DIM)
        local px2 = x + 5 * u + F.body:getWidth(up.name) + 4 * u
        for k = 1, #up.costs do
          love.graphics.setColor(k <= tier and WARM or { 0.25, 0.22, 0.3 })
          love.graphics.rectangle("fill", math.floor(px2 + (k - 1) * 4 * u), math.floor(ty + F.body:getHeight() / 2 - 1.2 * u), math.ceil(2.6 * u), math.ceil(2.6 * u))
        end
        if cost then
          markPrice(tostring(cost), x + rw - 4 * u, ty, F.body, marks >= cost and meta.SIGIL_COLOR or DANGER)
        else
          shadowPrint("Done", x + rw - 4 * u - F.body:getWidth("Done"), ty, F.body, FAINT)
        end
        wrapped(up.desc, x + rw + 6 * u, ry, X(386) - (x + rw + 6 * u), F.small, FAINT)
      end
    end
  end
  for _, up in ipairs(meta.UPGRADES) do
    if up.npc == campNpc and campNpc ~= "cartographer" then
      local h = math.floor(23 * u)
      local tier, cost = meta.tier(up.id), meta.nextCost(up.id)
      local focused = widget({ id = "camp:up:" .. up.id, x = x, y = y, w = w, h = h, activate = function()
        if meta.buy(up.id) then
          audio.play("buy")
        else
          audio.play("deny")
        end
      end })
      panel(x, y, w, h, focused and 0.95 or 0.82)
      if focused then
        focusFrame(x, y, w, h)
      end
      local tx, ty = x + 5 * u, y + 3 * u
      shadowPrint(up.name, tx, ty, F.body, focused and TEXT or DIM)
      -- a pip per tier, lit when bought
      local px = tx + F.body:getWidth(up.name) + 4 * u
      for k = 1, #up.costs do
        local c = k <= tier and WARM or { 0.25, 0.22, 0.3 }
        love.graphics.setColor(c)
        love.graphics.rectangle("fill", math.floor(px + (k - 1) * 4 * u), math.floor(ty + F.body:getHeight() / 2 - 1.2 * u), math.ceil(2.6 * u), math.ceil(2.6 * u))
      end
      -- (the price sits centred on the card's height, and the description keeps clear of it)
      local priceY = y + (h - F.body:getHeight()) / 2
      local priceW
      if cost then
        priceW = F.body:getWidth(tostring(cost)) + 10 * u
        markPrice(tostring(cost), x + w - 5 * u, priceY, F.body, marks >= cost and meta.SIGIL_COLOR or DANGER)
      else
        priceW = F.body:getWidth("Done")
        shadowPrint("Done", x + w - 5 * u - priceW, priceY, F.body, FAINT)
      end
      wrapped(up.desc, tx, ty + F.body:getHeight() + u, w - 14 * u - priceW, F.small, FAINT)
      y = y + h + 3 * u
    end
  end

  -- The Sawbone: patch-ups and the parts he will take (src.meta LIMBS)
  if campNpc == "sawbone" then
    local game = require("src.game")
    local player, inv = game.player(), game.inventory()
    local x, y, w = X(200), Y(36), math.floor(186 * u)
    shadowPrint("Patch up", x, y, F.body, WARM)
    y = y + F.body:getHeight() + 2 * u
    local hurt = player and not player.dead and player.hp < player.maxHp
    local function healRow(id, label, price, color, can, mode)
      local h = math.floor(12 * u)
      local focused = widget({ id = id, x = x, y = y, w = w, h = h, activate = function()
        if can and meta.sawHeal(player, inv, mode) then
          audio.play("heal")
          act("refresh")
        else
          audio.play("deny")
        end
      end })
      panel(x, y, w, h, focused and 0.95 or 0.82)
      if focused then
        focusFrame(x, y, w, h)
      end
      local ty = y + (h - F.body:getHeight()) / 2
      shadowPrint(label, x + 5 * u, ty, F.body, can and (focused and TEXT or DIM) or FAINT)
      shadowPrint(price, x + w - 5 * u - F.body:getWidth(price), ty, F.body, can and color or FAINT)
      y = y + h + 2.5 * u
    end
    if player and inv then
      local hHalf, gHalf = meta.sawHealQuote(player, 0.5)
      local hFull, gFull = meta.sawHealQuote(player, 1)
      healRow("camp:saw:half", "Half heal (+" .. hHalf .. ")", gHalf .. "g", WARM, hurt and inv.gold >= gHalf, "half")
      -- One tab for the full heal, with two ways to pay at its right: gold, or marks
      local h = math.floor(14 * u)
      panel(x, y, w, h, 0.82)
      shadowPrint("Full heal (+" .. hFull .. ")", x + 5 * u, y + (h - F.body:getHeight()) / 2, F.body, hurt and DIM or FAINT)
      local bw, bh = math.floor(34 * u), math.floor(10 * u)
      local gx = x + w - 2 * u - bw * 2 - 2 * u
      local canGold = hurt and inv.gold >= gFull
      local canMarks = hurt and marks >= meta.SAW_MARKS
      local function payButton(id, bx, can, mode, draw)
        local focused = widget({ id = id, x = bx, y = y + 2 * u, w = bw, h = bh, activate = function()
          if can and meta.sawHeal(player, inv, mode) then
            audio.play("heal")
            act("refresh")
          else
            audio.play("deny")
          end
        end })
        panel(bx, y + 2 * u, bw, bh, focused and 0.98 or 0.7)
        if focused then
          focusFrame(bx, y + 2 * u, bw, bh)
        end
        draw(bx, y + 2 * u, bw, bh, can)
      end
      payButton("camp:saw:fullgold", gx, canGold, "full", function(bx, by, bw2, bh2, can)
        local t = gFull .. "g"
        shadowPrint(t, bx + (bw2 - F.body:getWidth(t)) / 2, by + (bh2 - F.body:getHeight()) / 2, F.body, can and WARM or FAINT)
      end)
      payButton("camp:saw:fullmarks", gx + bw + 2 * u, canMarks, "marks", function(bx, by, bw2, bh2, can)
        local t = tostring(meta.SAW_MARKS)
        local tw = F.body:getWidth(t) + 9 * u
        local tx = bx + (bw2 - tw) / 2
        shadowPrint(t, tx, by + (bh2 - F.body:getHeight()) / 2, F.body, can and meta.SIGIL_COLOR or FAINT)
        meta.drawSigil(math.floor(tx + F.body:getWidth(t) + 1 * u), math.floor(by + bh2 / 2 - 3.5 * 0.8 * u / 1), math.max(1, math.floor(u * 0.8)), can and 1 or 0.4)
      end)
      y = y + h + 2.5 * u
    end
    y = y + 2 * u
    shadowPrint("Take a part", x, y, F.body, WARM)
    y = y + F.body:getHeight() + 2 * u
    for _, limb in ipairs(meta.LIMBS) do
      local on = meta.limbOn(limb.id)
      local h = math.floor(17 * u)
      local focused = widget({ id = "camp:limb:" .. limb.id, x = x, y = y, w = w, h = h, activate = function()
        meta.toggleLimb(limb.id)
        audio.play(on and "back" or "select")
        act("refresh") -- (max health may have changed)
      end })
      panel(x, y, w, h, focused and 0.95 or 0.82, on and DANGER or nil)
      if focused then
        focusFrame(x, y, w, h, on and DANGER or ACCENT)
      end
      shadowPrint(limb.name, x + 5 * u, y + 2 * u, F.body, on and { 1, 0.7, 0.6 } or (focused and TEXT or DIM))
      shadowPrint(on and "TAKEN" or "kept", x + w - 5 * u - F.small:getWidth(on and "TAKEN" or "kept"), y + 2 * u, F.small, on and DANGER or FAINT)
      shadowPrint("+ " .. limb.gain, x + 5 * u, y + 2 * u + F.body:getHeight(), F.small, { 0.6, 0.9, 0.6 })
      shadowPrint("- " .. limb.loss, x + 5 * u, y + 2 * u + F.body:getHeight() + F.small:getHeight(), F.small, { 0.95, 0.6, 0.55 })
      y = y + h + 2 * u
    end
  end

  -- The Bartender: his drinks (right) and, under his upgrades, the house rules that make the next run harder
  if campNpc == "bartender" then
    local ux, uw = x, w
    local ruleY = y + 2 * u -- (under the upgrades the loop above drew)
    -- The drinks: bottles on two shelves, as many as the Back-Room Stock has put out (3 to a shelf)
    local dx, dy, dw = X(200), Y(36), math.floor(186 * u)
    shadowPrint("Drinks", dx, dy, F.body, WARM)
    shadowPrint("(last " .. math.floor(meta.drinkTime() / 60 + 0.5) .. " min underground)", dx + F.body:getWidth("Drinks ") + 2 * u, dy + u * 0.8, F.small, FAINT)
    dy = dy + F.body:getHeight() + 3 * u
    local stocked = {}
    for _, d in ipairs(meta.DRINKS) do
      if meta.drinkStocked(d) then
        stocked[#stocked + 1] = d
      end
    end
    local cw = math.floor(dw / 3)
    local ch = math.floor(74 * u)
    local boardY = 38 * u -- (where the bottles stand, below a shelf's top)
    local pxs = math.max(2, math.floor(u * 1.1))
    for shelf = 1, 2 do
      local sy = dy + (shelf - 1) * (ch + 4 * u)
      -- the board the bottles stand on
      love.graphics.setColor(0.30, 0.20, 0.11)
      love.graphics.rectangle("fill", dx, sy + boardY, dw, math.max(2, 2.2 * u))
      love.graphics.setColor(0.45, 0.31, 0.17)
      love.graphics.rectangle("fill", dx, sy + boardY, dw, math.max(1, 0.8 * u))
      for slot = 1, 3 do
        local d = stocked[(shelf - 1) * 3 + slot]
        if d then
          local cx = dx + (slot - 1) * cw
          local n, left = meta.drinkCount(d.id), meta.drinkLeft(d.id)
          local canBuy = marks >= d.cost
          local focused = widget({ id = "camp:drink:" .. d.id, x = cx, y = sy, w = cw - 2 * u, h = ch, activate = function()
            if canBuy and meta.buyDrink(d.id) then
              audio.play("gulp")
              if meta.passedOut() then
                act("passout")
              else
                act("refresh") -- (max health may have changed)
              end
            else
              audio.play("deny")
            end
          end })
          if focused then
            focusFrame(cx, sy, cw - 2 * u, ch, n > 0 and ACCENT or nil)
          end
          drawDrinkBottle(d.shape, d.color, math.floor(cx + (cw - 2 * u) / 2), math.floor(sy + boardY), pxs)
          -- under it: its name, its price and what it does, spaced out below the board
          local mid = cx + (cw - 2 * u) / 2
          local ty = sy + boardY + 5 * u
          printCentered(d.name, mid, ty, F.small, focused and TEXT or DIM)
          ty = ty + F.small:getHeight() + 2 * u
          local cost = tostring(d.cost)
          markPrice(cost, mid + (F.small:getWidth(cost) + 8 * u) / 2, ty, F.small, canBuy and meta.SIGIL_COLOR or DANGER)
          ty = ty + F.small:getHeight() + 2 * u
          local _, descLines = F.small:getWrap(d.desc, cw - 8 * u)
          for li, line in ipairs(descLines) do
            printCentered(line, mid, ty + (li - 1) * F.small:getHeight() * F.small:getLineHeight(), F.small, FAINT)
          end
          if n > 0 then
            local t = "x" .. n .. "  " .. string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
            shadowPrint(t, cx + cw - 3 * u - F.small:getWidth(t), sy + 1 * u, F.small, ACCENT)
          end
        end
      end
    end

    local rx, ry, rw = ux, ruleY, uw
    local open = meta.rulesUnlocked()
    if not open then
      return -- (the house rules only turn up once they are bought)
    end
    shadowPrint("House rules", rx, ry, F.body, WARM)
    ry = ry + F.body:getHeight() + 2 * u
    for _, r in ipairs(meta.RULES) do
      local on = meta.ruleOn(r.id)
      local h = math.floor(17 * u)
      local focused = false
      if open then
        focused = widget({ id = "camp:rule:" .. r.id, x = rx, y = ry, w = rw, h = h, activate = function()
          meta.toggleRule(r.id)
          audio.play(on and "back" or "select")
        end })
      end
      panel(rx, ry, rw, h, focused and 0.95 or 0.82, on and DANGER or nil)
      if focused then
        focusFrame(rx, ry, rw, h, on and DANGER or ACCENT)
      end
      local tx, ty = rx + 5 * u, ry + 2.5 * u
      shadowPrint(r.name, tx, ty, F.body, not open and FAINT or (on and { 1, 0.7, 0.6 } or (focused and TEXT or DIM)))
      shadowPrint(r.desc, tx, ty + F.body:getHeight() + u * 0.3, F.small, open and DIM or FAINT)
      local pct = "Marks +" .. math.floor((r.marks - 1) * 100 + 0.5) .. "%"
      shadowPrint(pct, rx + rw - 5 * u - F.small:getWidth(pct), ty, F.small, open and meta.SIGIL_COLOR or FAINT)
      if open then
        shadowPrint(on and "ON" or "off", rx + rw - 5 * u - F.small:getWidth(on and "ON" or "off"), ty + F.body:getHeight() + u * 0.3, F.small, on and DANGER or FAINT)
      end
      ry = ry + h + 2.5 * u
    end
    local total = 1
    for _, r in ipairs(meta.RULES) do
      if meta.ruleOn(r.id) then
        total = total * r.marks
      end
    end
    wrapped(open and ("Rules apply from your next run (restart or start a new one). Together they pay marks x" .. string.format("%.2f", total) .. " on everything earned.") or "Buy House Rules above to switch these on.", rx, ry + u * 0.5, rw, F.small, FAINT)
    return
  end
  -- The Cartographer: his chart, right on the page (src.chart); wheel or +/- zooms, a drag moves it
  if campNpc == "cartographer" then
    local chart = require("src.chart")
    local cx0, cy0, cw0 = X(14), Y(58), math.floor(372 * u)
    local ch0 = math.floor(Y(218) - cy0)
    chart.draw(cx0, cy0, cw0, ch0, u, F)
    local bs, gap = math.floor(10 * u), math.floor(2 * u)
    local bx = cx0 + cw0 - gap - bs
    button("chart:zoomin", "+", bx, cy0 + gap, bs, bs, function()
      chart.zoom(1.3)
    end, { font = F.body })
    button("chart:zoomout", "-", bx - bs - gap, cy0 + gap, bs, bs, function()
      chart.zoom(1 / 1.3)
    end, { font = F.body })
    button("chart:reset", "o", bx - 2 * (bs + gap), cy0 + gap, bs, bs, function()
      chart.resetView()
    end, { font = F.body })
    return
  end
  -- The Taxidermist's wall: one row per kind of elite (src.meta.MOUNTS)
  if campNpc == "taxidermist" then
    local enemies = require("src.enemies")
    local x, y, w = X(14), Y(36), math.floor(372 * u)
    shadowPrint("Trophies", x, y, F.body, WARM)
    y = y + F.body:getHeight() + 2 * u
    for _, kind in ipairs(meta.MOUNT_ORDER) do
      local m = meta.MOUNTS[kind]
      local n, level = meta.trophyCount(kind), meta.mountLevel(kind)
      local mounted = level > 0
      local need, cost = meta.mountNeed(kind), meta.mountCost(kind)
      local maxed = level >= meta.MOUNT_MAX
      local ready = not maxed and n >= need
      local h = math.floor(17 * u)
      local focused = widget({ id = "camp:mount:" .. kind, x = x, y = y, w = w, h = h, activate = function()
        if meta.mount(kind) then
          audio.play("buy")
          act("refresh") -- (max health may have changed)
        else
          audio.play("deny")
        end
      end })
      panel(x, y, w, h, focused and 0.95 or 0.82)
      if focused then
        focusFrame(x, y, w, h)
      end
      local tx, ty = x + 5 * u, y + 2.5 * u
      shadowPrint(m.name, tx, ty, F.body, (n > 0) and (focused and TEXT or DIM) or FAINT)
      local slain = n > 0 and ("Elites slain: " .. n) or "None slain yet"
      if not maxed and n > 0 and n < need then
        slain = slain .. "  (next at " .. need .. ")"
      end
      shadowPrint(slain, tx, ty + F.body:getHeight() + u * 0.5, F.small, n > 0 and DIM or FAINT)
      -- what it gives now (level 1's bonus before it is mounted), and what the next level would
      local shown = meta.mountEffect(kind, math.max(1, level))
      shadowPrint((mounted and ("Lv " .. level .. "  ") or "") .. shown, x + 120 * u, ty + u * 0.5, F.body, mounted and WARM or ((n > 0) and DIM or FAINT))
      if mounted and not maxed then
        shadowPrint("next: " .. meta.mountEffect(kind, level + 1), x + 120 * u, ty + F.body:getHeight() + u * 0.5, F.small, ready and DIM or FAINT)
      end
      if maxed then
        shadowPrint("Max", x + w - 5 * u - F.body:getWidth("Max"), y + (h - F.body:getHeight()) / 2, F.body, WARM)
      elseif ready then
        markPrice(tostring(cost), x + w - 5 * u, y + (h - F.body:getHeight()) / 2, F.body, marks >= cost and meta.SIGIL_COLOR or DANGER)
      end
      y = y + h + 3 * u
    end
    wrapped("A mount is for good: its bonus applies in every run. Slay one elite of a kind to mount it, then five more of that kind for each upgrade. Each upgrade costs 1.2x the last and adds half as much as the one before.", x, y + u, w, F.small, FAINT)
    return
  end
  -- The Prospector's strongbox: gold kept between runs
  if campNpc == "prospector" then
    local gx, gy, gw = X(198), Y(36), math.floor(188 * u)
    shadowPrint("Strongbox", gx, gy, F.body, WARM)
    local top = gy + F.body:getHeight() + 2 * u
    local gh = math.floor(62 * u)
    panel(gx, top, gw, gh, 0.85)
    local inBox, cap = meta.bank(), meta.bankCap()
    local carry = menu.runGold and menu.runGold() or 0
    local cx = gx + gw / 2
    local ty = top + 6 * u
    printCentered(inBox .. " / " .. cap .. " gold in the box", cx, ty, F.head, { 1, 0.85, 0.4 })
    ty = ty + F.head:getHeight() + 3 * u
    -- how full it is
    local bw = gw - 24 * u
    love.graphics.setColor(0.14, 0.12, 0.18)
    love.graphics.rectangle("fill", gx + 12 * u, ty, bw, math.max(2, u * 1.4))
    love.graphics.setColor(1, 0.8, 0.35)
    love.graphics.rectangle("fill", gx + 12 * u, ty, bw * math.min(1, inBox / cap), math.max(2, u * 1.4))
    ty = ty + 5 * u
    printCentered("You carry " .. carry .. " gold", cx, ty, F.body, DIM)
    ty = ty + F.body:getHeight() + 5 * u
    local bwid, bh = math.floor(70 * u), math.floor(13 * u)
    button("camp:deposit", "Put it in", math.floor(cx - bwid - 3 * u), ty, bwid, bh, function()
      act("deposit")
      audio.play("coin")
    end, { disabled = carry <= 0 or inBox >= cap })
    button("camp:withdraw", "Take it all out", math.floor(cx + 3 * u), ty, bwid, bh, function()
      act("withdraw")
      audio.play("coin")
    end, { disabled = inBox <= 0 })
    local th = wrapped("What's in the box survives death. Walk back up with your gold to put it away, and take it out at the start of a run to spend it below.", gx, top + gh + 4 * u, gw, F.small, FAINT)
    -- The shelf (an upgrade he sells): one perk kept between runs. The perks you carry are icons; pick one and it
    -- goes on the shelf.
    local perks = require("src.perks")
    local sy = math.floor(top + gh + 4 * u + th + 8 * u)
    if meta.tier("shelf") <= 0 and not meta.bankedPerk() then
      return -- (nothing to show until the shelf is bought)
    end
    shadowPrint("Perk shelf", gx, sy, F.body, WARM)
    sy = sy + F.body:getHeight() + 2 * u
    local shelved = meta.bankedPerk()
    local rowH = math.floor(12 * u)
    if shelved then
      local def = perks.defs[shelved]
      local entry = compendium.entry("perk", shelved)
      local isz = math.floor(24 * u)
      local _, descLines = F.small:getWrap(def.desc, gw - isz - 14 * u)
      local ph = math.max(isz + 8 * u, math.floor(F.body:getHeight() + #descLines * F.small:getHeight() * F.small:getLineHeight() + 9 * u))
      panel(gx, sy, gw, ph, 0.85)
      if entry then
        compendium.drawIcon(entry, gx + 4 * u, sy + (ph - isz) / 2, isz, isz)
      end
      shadowPrint(def.name, gx + isz + 9 * u, sy + 4 * u, F.body, def.color)
      wrapped(def.desc, gx + isz + 9 * u, sy + 4 * u + F.body:getHeight() + u, gw - isz - 14 * u, F.small, DIM)
      local have = false
      for _, id in ipairs(menu.runPerks and menu.runPerks() or {}) do
        have = have or id == shelved
      end
      local by = sy + ph + 3 * u
      button("camp:perktake", have and "You already carry one" or "Take it back", gx, by, gw, rowH, function()
        act("perktake")
        audio.play("pickup")
      end, { disabled = have })
      wrapped("It is yours again at the start of any run, whatever happened to the last one.", gx, by + rowH + 3 * u, gw, F.small, FAINT)
    else
      local mine = {}
      for _, id in ipairs(menu.runPerks and menu.runPerks() or {}) do
        if meta.canShelve(id) then
          mine[#mine + 1] = id
        end
      end
      if #mine == 0 then
        wrapped("Nothing to keep yet. Bring a perk from below and he will hold on to it for you, through death.", gx, sy, gw, F.small, FAINT)
      else
        local cell, gap = math.floor(20 * u), math.floor(3 * u)
        local cols = math.max(1, math.floor((gw + gap) / (cell + gap)))
        local hovered
        for i, id in ipairs(mine) do
          local cx = gx + ((i - 1) % cols) * (cell + gap)
          local cy = sy + math.floor((i - 1) / cols) * (cell + gap)
          local focused = widget({ id = "camp:perkstore" .. id, x = cx, y = cy, w = cell, h = cell, activate = function()
            act("perkstore", id)
            audio.play("buy")
          end })
          slotBox(cx, cy, cell, cell, focused and "focus" or nil, SLOT_REST)
          local entry = compendium.entry("perk", id)
          if entry then
            compendium.drawIcon(entry, cx + 2 * u, cy + 2 * u, cell - 4 * u, cell - 4 * u)
          end
          if focused then
            hovered = perks.defs[id]
          end
        end
        local ry = sy + math.ceil(#mine / cols) * (cell + gap) + 2 * u
        if hovered then
          shadowPrint(hovered.name, gx, ry, F.body, hovered.color)
          wrapped(hovered.desc, gx, ry + F.body:getHeight() + u, gw, F.small, DIM)
        else
          wrapped("Pick a perk to put on the shelf. It leaves your run when you hand it over.", gx, ry, gw, F.small, FAINT)
        end
      end
    end
    return
  end
  -- Teaching: a grid of everything still locked (silhouettes until seen)
  if campNpc ~= "gunsmith" then
    return
  end
  -- Buying: the guns he knows, for gold, one per run, always B-grade (left, under his upgrades)
  do
    local gold = menu.runGold and menu.runGold() or 0
    local bx, by, bw = x, y + 2 * u, w
    shadowPrint("Buy a gun", bx, by, F.body, WARM)
    shadowPrint(meta.gunBought() and "(bought this run)" or "(one per run, B-grade)", bx + F.body:getWidth("Buy a gun ") + 2 * u, by + u * 0.8, F.small, FAINT)
    by = by + F.body:getHeight() + 2 * u
    local cw, chh = math.floor((bw - 3 * u) / 2), math.floor(14 * u)
    local n = 0
    for _, g in ipairs(meta.GUN_PRICES) do
      if meta.isUnlocked("weapon", g[1]) then
        local gx2 = bx + (n % 2) * (cw + 3 * u)
        local gy2 = by + math.floor(n / 2) * (chh + 2 * u)
        local can = not meta.gunBought() and gold >= g[2]
        local focused = widget({ id = "camp:buygun:" .. g[1], x = gx2, y = gy2, w = cw, h = chh, activate = function()
          if can then
            act("buygun", g[1])
            audio.play("buy")
          else
            audio.play("deny")
          end
        end })
        panel(gx2, gy2, cw, chh, focused and 0.95 or 0.82)
        if focused then
          focusFrame(gx2, gy2, cw, chh)
        end
        local ty = gy2 + (chh - F.body:getHeight()) / 2
        local entry = compendium.entry("weapon", g[1])
        local name = entry and entry.name or (g[1]:gsub("^%l", string.upper))
        shadowPrint(name, gx2 + 4 * u, ty, F.body, can and (focused and TEXT or DIM) or FAINT)
        local price = g[2] .. "g"
        shadowPrint(price, gx2 + cw - 4 * u - F.body:getWidth(price), ty, F.body, can and { 1, 0.85, 0.4 } or FAINT)
        n = n + 1
      end
    end
  end
  local gx, gy, gw = X(198), Y(36), math.floor(188 * u)
  shadowPrint("Teach him", gx, gy, F.body, WARM)
  local list = teachList()
  local top = gy + F.body:getHeight() + 2 * u
  local cell, gap, pad = math.floor(19 * u), math.floor(3 * u), math.floor(4 * u)
  local cols = math.max(1, math.floor((gw - pad * 2 + gap) / (cell + gap)))
  local rows = math.max(1, math.ceil(#list / cols))
  local gh = rows * (cell + gap) - gap + pad * 2
  panel(gx, top, gw, gh, 0.85)
  if #list == 0 then
    printCentered("He can make everything you can show him.", gx + gw / 2, top + gh / 2 - F.small:getHeight() / 2, F.small, FAINT)
  end
  local gridW = cols * (cell + gap) - gap
  local x0 = gx + math.floor((gw - gridW) / 2)
  local focusedEntry
  for i, e in ipairs(list) do
    local cx = x0 + ((i - 1) % cols) * (cell + gap)
    local cy = top + pad + math.floor((i - 1) / cols) * (cell + gap)
    local seen = meta.isSeen(e.category, e.id)
    local cost = meta.teachCost(e.category, e.id)
    local focused = widget({ id = "camp:teach:" .. e.category .. ":" .. e.id, x = cx, y = cy, w = cell, h = cell, activate = function()
      if not seen or marks < cost then
        audio.play("deny")
        return
      end
      local gun = e.category == "weapon"
      confirm({
        text = gun and ("Have him craft the " .. e.name .. "?") or ("Teach him the " .. e.name .. "?"),
        detail = (gun and "Once he has made one it joins the pool for every run: chests, drops and shops. " or "It joins the pool for every run. ") .. cost .. " marks.",
        yesLabel = gun and "Craft" or "Teach",
        yes = function()
          if meta.teach(e.category, e.id) then
            audio.play("buy")
          end
          pop()
        end,
      })
    end })
    if focused then
      focusedEntry = e
    end
    local edge = seen and ((e.rarity and e.rarity ~= "common" and RARITY[e.rarity]) or SLOT_REST) or { 0.22, 0.2, 0.27 }
    slotBox(cx, cy, cell, cell, focused and "focus" or nil, { edge[1], edge[2], edge[3], seen and 0.9 or 0.6 }, not seen and { 0.035, 0.03, 0.05, 0.9 } or nil)
    compendium.drawIcon(e, cx + 2 * u, cy + 2 * u, cell - 4 * u, cell - 4 * u, not seen)
  end

  -- The focused one: what it is and what teaching it costs
  local dy = top + gh + 4 * u
  local e = focusedEntry
  if e then
    local seen = meta.isSeen(e.category, e.id)
    local cost = meta.teachCost(e.category, e.id)
    shadowPrint(seen and e.name or "???", gx, dy, F.body, seen and TEXT or FAINT)
    if seen then
      markPrice(tostring(cost), gx + gw, dy, F.body, marks >= cost and meta.SIGIL_COLOR or DANGER)
      local text = (e.desc or "") .. (marks >= cost and "" or "  (Not enough marks.)")
      wrapped(text, gx, dy + F.body:getHeight() + u, gw, F.small, DIM)
    else
      local hint = "Not seen yet. Bosses, and now and then a chest, give out things he doesn't make; find one and he can learn it."
      local giver = e.category == "weapon" and meta.SPECIAL_GUNS[e.id]
      if giver == "queen" then
        hint = "Not seen yet. The Queen of the Sulfur Vents guards one; bring it back and he can craft it."
      elseif giver == "sawbone" then
        hint = "Not seen yet. The Sawbone, floating in the Flooded Caverns, has one to give once he is woken."
      elseif giver == "cartographer" then
        hint = "Not seen yet. The Cartographer, caged in the Quarry, has one to give once she is freed."
      end
      wrapped(hint, gx, dy + F.body:getHeight() + u, gw, F.small, FAINT)
    end
  elseif #list > 0 then
    wrapped("Choose something you have seen to teach him.", gx, dy, gw, F.small, FAINT)
  end
end

-- Settings ---------------------------------------------------------------------------

local SETTINGS_TABS = { "Audio", "Display", "Controls", "Crosshair" }

local function row(label, y)
  shadowPrint(label, X(70), y + (13 * u - F.body:getHeight()) / 2, F.body, DIM)
end

PAGES.settings = function()
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.015, 0.01, 0.025, root == "pause" and 0.93 or 0.55)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  litBackdrop()
  panel(X(58), Y(8), math.floor(284 * u), math.floor(206 * u), 0.9)
  pageTitle("Settings", X(200), Y(12), true)
  tabs("set:tab", SETTINGS_TABS, settingsTab, X(66), Y(34), math.floor(268 * u), math.floor(12 * u), function(i)
    if i ~= settingsTab then
      settingsTab = i
      audio.play("page")
    end
  end)
  local y = Y(52)
  local rh = math.floor(15 * u)
  local cx, cw = X(200), math.floor(130 * u)
  local ch = math.floor(13 * u)
  if settingsTab == 1 then
    for _, s in ipairs({ { "Master volume", "masterVolume" }, { "Music", "musicVolume" }, { "Sound effects", "sfxVolume" } }) do
      row(s[1], y)
      slider("set:" .. s[2], cx, y, cw, ch, settings.get(s[2]), function(v)
        settings.set(s[2], v)
      end)
      y = y + rh
    end
    shadowPrint("Music covers the area themes and the shop's piano; effects include the wind.", X(70), y + 2 * u, F.small, FAINT)
  elseif settingsTab == 4 then
    -- The crosshair: style, colour, opacity, thickness, arm length, gap, outline, and a preview
    local hud = require("src.hud")
    local styleNames = { "Plus", "Circle", "Dot", "X" }
    local cur = 1
    for i, id in ipairs(hud.CROSSHAIR_STYLES) do
      if id == settings.get("crosshairStyle") then
        cur = i
      end
    end
    row("Style", y)
    tabs("set:xh:style", styleNames, cur, cx, y, cw, ch, function(i)
      settings.set("crosshairStyle", hud.CROSSHAIR_STYLES[i])
      audio.play("page")
    end)
    y = y + rh
    row("Colour", y)
    local n = #hud.CROSSHAIR_COLORS
    local sw = cw / n
    for i, col in ipairs(hud.CROSSHAIR_COLORS) do
      local sx = cx + (i - 1) * sw
      local sel = settings.get("crosshairColor") == i
      local focused = widget({ id = "set:xh:color" .. i, x = sx, y = y, w = sw - u, h = ch, activate = function()
        settings.set("crosshairColor", i)
        audio.play("select")
      end })
      slotBox(sx, y, sw - u, ch, sel and "selected" or (focused and "focus" or nil))
      local pad = math.max(3, math.floor(3 * u))
      love.graphics.setColor(col[1], col[2], col[3])
      love.graphics.rectangle("fill", math.floor(sx + pad), math.floor(y + pad), math.floor(sw - u - 2 * pad), math.floor(ch - 2 * pad))
    end
    y = y + rh
    -- {label, setting, lowest, highest, whole numbers?}
    for _, s in ipairs({
      { "Opacity", "crosshairOpacity", 0.1, 1, false },
      { "Line thickness", "crosshairThickness", 1, 4, true },
      { "Line length", "crosshairLength", 1, 12, true },
      { "Gap from the centre", "crosshairGap", 0, 10, true },
    }) do
      row(s[1], y)
      local lo, hi = s[3], s[4]
      slider("set:xh:" .. s[2], cx, y, cw, ch, (settings.get(s[2]) - lo) / (hi - lo), function(v)
        local value = lo + v * (hi - lo)
        settings.set(s[2], s[5] and math.floor(value + 0.5) or value)
      end)
      y = y + rh
    end
    row("Outline", y)
    toggle("set:xh:outline", cx + cw - math.floor(50 * u), y, math.floor(50 * u), ch, settings.get("crosshairOutline"), function(v)
      settings.set("crosshairOutline", v)
    end)
    y = y + rh
    -- A preview on a patch of cave wall, drawn at the game's scale
    local pw, ph = math.floor(92 * u), math.floor(30 * u)
    local px, py = X(200) - pw / 2, y + u
    love.graphics.setColor(0.10, 0.09, 0.12, 0.95)
    love.graphics.rectangle("fill", px, py, pw, ph, u, u)
    love.graphics.setColor(0.28, 0.24, 0.20, 0.9)
    love.graphics.rectangle("fill", px + pw * 0.55, py, pw * 0.45, ph)
    love.graphics.push()
    love.graphics.translate(px + pw / 2, py + ph / 2)
    love.graphics.scale(u, u)
    hud.drawCrosshair(0, 0)
    love.graphics.pop()
  elseif settingsTab == 2 then
    local opts = {
      { "Fullscreen (F11)", "fullscreen" },
      { "Vertical sync", "vsync" },
      { "Bloom and colour grading", "postfx" },
      { "Show FPS counter", "showFps" },
      { "Pause when the window loses focus", "pauseOnFocusLoss" },
    }
    for _, s in ipairs(opts) do
      row(s[1], y)
      toggle("set:" .. s[2], cx + cw - math.floor(50 * u), y, math.floor(50 * u), ch, settings.get(s[2]), function(v)
        settings.set(s[2], v)
      end)
      y = y + rh
    end
  else
    -- Key bindings: two keys per action
    local kh = math.floor(math.min(9.5, 139 / #input.ACTIONS) * u) -- (every action fits above the buttons)
    local kw = math.floor(46 * u)
    for _, a in ipairs(input.ACTIONS) do
      shadowPrint(a.name, X(70), y + (kh - F.small:getHeight()) / 2, F.small, DIM)
      local keys = input.keys(a.id)
      for slot = 1, 2 do
        local kx = X(178) + (slot - 1) * (kw + 3 * u)
        local id = "set:key:" .. a.id .. ":" .. slot
        local isListening = listening and listening.action == a.id and listening.slot == slot
        local focused = widget({ id = id, x = kx, y = y, w = kw, h = kh - u, activate = function()
          listening = { action = a.id, slot = slot }
          audio.play("select")
        end, clear = function()
          input.bind(a.id, slot, false)
          settings.save()
          audio.play("back")
        end })
        slotBox(kx, y, kw, kh - u, isListening and "gold" or (focused and "focus" or nil))
        local label = isListening and (math.floor(clock * 3) % 2 == 0 and "Press a key" or "") or input.keyName(keys[slot])
        printCentered(label, kx + kw / 2, y + (kh - u - F.small:getHeight()) / 2, F.small, isListening and WARM or (keys[slot] and TEXT or FAINT))
      end
      y = y + kh
    end
    -- The mouse, for reference
    local fy = Y(52)
    for _, f in ipairs(input.FIXED) do
      shadowPrint(f[1], X(282), fy, F.small, FAINT)
      shadowPrint(f[2], X(282), fy + F.small:getHeight(), F.small, DIM)
      fy = fy + F.small:getHeight() * 2.6
    end
  end
  local by = Y(196)
  local bw, bh = math.floor(80 * u), math.floor(12 * u)
  if settingsTab == 3 then
    button("set:resetKeys", "Reset controls", X(200) - bw - 2 * u, by, bw, bh, function()
      settings.resetBindings()
      audio.play("back")
    end)
  else
    button("set:reset", "Restore defaults", X(200) - bw - 2 * u, by, bw, bh, function()
      settings.resetDefaults()
      audio.play("back")
    end)
  end
  button("set:back", "Back", X(200) + 2 * u, by, bw, bh, function()
    pop()
  end)
end

-- Naming a save file ---------------------------------------------------------------------

local function nameTrimmed()
  return (nameState.text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function confirmName()
  local name = nameTrimmed()
  if #name == 0 then
    audio.play("deny")
    return
  end
  save.setName(nameState.slot, name)
  audio.play("select")
  act("play", nameState.slot)
end

PAGES.name = function()
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.015, 0.01, 0.025, 0.7)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  litBackdrop()
  pageTitle("Name Your Hunter", ww / 2, Y(46), true)
  printCentered("Save file " .. tostring(nameState.slot) .. ". The name goes on the file, and is called back when death comes.", ww / 2, Y(46) + F.head:getHeight() + 6 * u, F.small, FAINT)
  -- The text box
  local bw, bh = math.floor(150 * u), math.floor(15 * u)
  local bx, by = math.floor((ww - bw) / 2), Y(94)
  panel(bx, by, bw, bh, 0.95, ACCENT)
  local text = nameState.text
  local ty = by + (bh - F.body:getHeight()) / 2
  if text == "" then
    shadowPrint("Type a name", bx + 5 * u, ty, F.body, FAINT)
  else
    shadowPrint(text, bx + 5 * u, ty, F.body, TEXT)
  end
  if math.floor(clock * 2) % 2 == 0 then
    love.graphics.setColor(WARM)
    love.graphics.rectangle("fill", math.floor(bx + 5 * u + F.body:getWidth(text) + u), math.floor(by + 3 * u), math.max(2, math.floor(u * 1.2)), math.floor(bh - 6 * u))
  end
  local count = #text .. " / " .. NAME_MAX
  shadowPrint(count, bx + bw - F.small:getWidth(count), by + bh + 2 * u, F.small, FAINT)
  local w, h = math.floor(70 * u), math.floor(12 * u)
  local y = Y(124)
  button("name:confirm", "Confirm", math.floor(ww / 2 - w - 2 * u), y, w, h, confirmName, { disabled = nameTrimmed() == "" })
  button("name:back", "Back", math.floor(ww / 2 + 2 * u), y, w, h, function()
    pop()
  end)
end

-- Typed text (love.textinput): letters, digits, spaces, hyphens and apostrophes
function menu.textinput(text)
  if top() ~= "name" then
    return
  end
  for ch in text:gmatch("[%w '%-]") do
    local t = nameState.text
    if #t < NAME_MAX and not (ch == " " and (t == "" or t:sub(-1) == " ")) then
      nameState.text = t .. ch
    end
  end
end

-- The death recap -----------------------------------------------------------------------------

local RED = { 0.86, 0.16, 0.2 }

local function drawSegments(segs, cx, y, f)
  local w = 0
  for _, seg in ipairs(segs) do
    w = w + f:getWidth(seg[1])
  end
  local x = cx - w / 2
  for _, seg in ipairs(segs) do
    shadowPrint(seg[1], x, y, f, seg[2])
    x = x + f:getWidth(seg[1])
  end
  return w
end

-- The killer's picture is printed on the poster in ink, like a woodcut: its
-- light and dark become two tones of brown, with nothing of the sprite's own
-- background, so it reads as part of the paper
local inkShader
local function getInk()
  if inkShader == nil then
    local ok, shader = pcall(love.graphics.newShader, [[
      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 t = Texel(tex, uv);
        float l = clamp(dot(t.rgb, vec3(0.3, 0.59, 0.11)) * 1.3, 0.0, 1.0) * 0.7;
        vec3 inkDark = vec3(0.17, 0.09, 0.04);
        vec3 inkLight = vec3(0.56, 0.40, 0.20);
        return vec4(mix(inkDark, inkLight, l), t.a) * color;
      }
    ]])
    inkShader = ok and shader or false
  end
  return inkShader or nil
end

local INK = { 0.24, 0.13, 0.06 }

-- The poster's timing on the recap page (seconds since it opened): it flies in
-- from close to the screen and hits at IMPACT; the rest of the page fades in after
local SLAM_START, IMPACT = 0.3, 0.5
local slammed = false -- the thud has played
local recapLayer -- the page's content (text, compendium, buttons), drawn on its own so it can fade

-- The wanted poster: parchment, WANTED, the killer printed in ink, its name.
-- Centred on (cx, cy), w x h in window pixels; `scale`, `spin` and `alpha`
-- are the slam's.
local function drawPoster(cx, cy, w, h, noun, photo, scale, spin, alpha)
  local x, y = math.floor(cx - w / 2), math.floor(cy - h / 2)
  local function color(r, g, b, a)
    love.graphics.setColor(r, g, b, (a or 1) * alpha)
  end
  local function ink(text, tx, ty, f, c)
    love.graphics.setFont(f)
    c = c or INK
    color(c[1], c[2], c[3])
    love.graphics.print(text, math.floor(tx - f:getWidth(text) / 2), math.floor(ty))
  end
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.rotate(0.025 + spin) -- (nailed up a little crooked)
  love.graphics.scale(scale, scale)
  love.graphics.translate(-cx, -cy)
  -- A soft shadow, the paper, a darker rim and a faint inner border
  color(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", x + 2 * u, y + 2 * u, w, h)
  color(0.78, 0.65, 0.42)
  love.graphics.rectangle("fill", x, y, w, h)
  color(0.86, 0.74, 0.50)
  love.graphics.rectangle("fill", x + u, y + u, w - 2 * u, h - 2 * u)
  love.graphics.setLineWidth(math.max(1, u * 0.5))
  color(0.45, 0.30, 0.16, 0.9)
  love.graphics.rectangle("line", x + 2.5 * u, y + 2.5 * u, w - 5 * u, h - 5 * u)
  -- Stains and a torn corner
  color(0.62, 0.48, 0.28, 0.35)
  love.graphics.rectangle("fill", x + w - 9 * u, y + h - 8 * u, 6 * u, 4 * u)
  love.graphics.rectangle("fill", x + 4 * u, y + 30 * u, 3 * u, 5 * u)
  -- Nails
  for _, nx in ipairs({ x + 3.8 * u, x + w - 3.8 * u }) do
    color(0.14, 0.12, 0.12)
    love.graphics.circle("fill", nx, y + 3.8 * u, 1.1 * u)
    color(0.55, 0.55, 0.58)
    love.graphics.circle("fill", nx - 0.3 * u, y + 3.5 * u, 0.4 * u)
  end
  ink("WANTED", cx, y + 5 * u, F.head)
  color(INK[1], INK[2], INK[3], 0.8)
  love.graphics.rectangle("fill", x + 8 * u, y + 5 * u + F.head:getHeight() + u, w - 16 * u, math.max(1, math.floor(u * 0.5)))
  -- The picture, printed straight onto the paper: a ruled box, and the
  -- monster in ink inside it
  local px, py, pw, ph = x + 8 * u, y + 5 * u + F.head:getHeight() + 4 * u, w - 16 * u, 32 * u
  color(0.70, 0.56, 0.34, 0.35)
  love.graphics.rectangle("fill", px, py, pw, ph)
  color(INK[1], INK[2], INK[3], 0.85)
  love.graphics.rectangle("line", px, py, pw, ph)
  if photo then
    local sc = math.min((pw - 5 * u) / photo.w, (ph - 5 * u) / photo.h)
    if sc >= 1 then
      sc = math.floor(sc)
    end
    local dx = math.floor(px + (pw - photo.w * sc) / 2)
    local dy = math.floor(py + (ph - photo.h * sc) / 2)
    love.graphics.setShader(getInk())
    color(1, 1, 1, 0.95)
    love.graphics.draw(photo.image, dx, dy, 0, sc, sc)
    love.graphics.setShader()
  else
    -- Nothing to photograph (gas, flames, water...): a question mark
    ink("?", px + pw / 2, py + ph / 2 - F.head:getHeight() / 2, F.head, { 0.45, 0.32, 0.16 })
  end
  ink((noun or "Unknown"):upper(), cx, py + ph + 3 * u, F.body)
  love.graphics.pop()
end

-- The ghost merchant (src.events) --------------------------------------------------------

PAGES.ghost = function()
  local events = require("src.events")
  local icons = require("src.icons")
  local game = require("src.game")
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.01, 0.02, 0.04, 0.93)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  litBackdrop()
  pageTitle("The Ghost Merchant", X(14), Y(9))
  shadowPrint("Pale hands, odd prices. Pay in gold, in blood, or in marks. He is gone when the lantern gutters.", X(14), Y(26), F.small, { 0.5, 0.7, 0.85 })
  local offers = events.ghostOffers()
  if not offers then
    printCentered("He has drifted off.", X(200), Y(100), F.body, FAINT)
    return
  end
  local x, y, w = X(14), Y(40), math.floor(372 * u)
  local player = game.player()
  for i, o in ipairs(offers) do
    local h = math.floor(30 * u)
    local can = (o.currency == "gold" and player.inventory.gold >= o.price) or (o.currency == "blood" and player.hp > o.price) or (o.currency == "marks" and meta.marks() >= o.price)
    local focused = widget({ id = "ghost:" .. i, x = x, y = y, w = w, h = h, activate = function()
      if not o.sold then
        act("ghostbuy", i)
      end
    end })
    panel(x, y, w, h, focused and 0.95 or 0.82, { 0.4, 0.65, 0.85 })
    if focused then
      focusFrame(x, y, w, h, { 0.5, 0.8, 1 })
    end
    local img = icons.getHD(o.item) or icons.get(o.item)
    if img then
      local s = math.max(1, math.floor(h * 0.7 / icons.HD_SIZE))
      icons.drawHDAt(img, x + 4 * u + icons.HD_SIZE * s / 2, y + h / 2, s, o.sold and 0.25 or 1)
    end
    local tx = x + 26 * u
    shadowPrint(o.item.name, tx, y + 4 * u, F.body, o.sold and FAINT or TEXT)
    wrapped(o.item.desc or "", tx, y + 4 * u + F.body:getHeight() + u * 0.5, w - 90 * u, F.small, o.sold and FAINT or DIM)
    local price
    if o.sold then
      price = "Sold"
    elseif o.currency == "gold" then
      price = o.price .. " gold"
    elseif o.currency == "blood" then
      price = o.price .. " health"
    else
      price = o.price .. " marks"
    end
    shadowPrint(price, x + w - 6 * u - F.body:getWidth(price), y + 4 * u, F.body, o.sold and FAINT or (can and { 0.6, 0.9, 1 } or DANGER))
    y = y + h + 4 * u
  end
end

-- A generic dialog (random events: src.randevents): a title, some lines of text,
-- an optional custom-drawn area and a stack of buttons. A button's fn(dialog)
-- returns true to keep the dialog open (it is drawn fresh every frame, so it can
-- change its own lines and buttons), anything else closes it.
local dialog

-- (for tests)
function menu.dialogState()
  return dialog
end

function menu.openDialog(dlg)
  dialog = dlg
  menu.open("dialog")
end

PAGES.dialog = function()
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.015, 0.012, 0.03, 0.93)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  litBackdrop()
  if not dialog then
    return
  end
  if dialog.refresh then
    dialog.refresh()
  end
  if dialog.custom then
    -- (the whole page is the event's own: a card table, the tinker's bench...)
    dialog.custom({
      shadowPrint = shadowPrint, printCentered = printCentered, pageTitle = pageTitle, wrapped = wrapped,
      panel = panel, F = F, u = u, X = X, Y = Y,
      close = function()
        act("resume")
      end,
      gp = ww / require("src.config").VIRTUAL_W, -- one game pixel, so art drawn here is the size it is in the world
      button = function(id, label, bx, by, bw, bh, fn, opts)
        return button(id, label, bx, by, bw, bh, function()
          audio.play("select")
          local keep = fn and fn(dialog)
          if not keep then
            act("resume")
          end
        end, opts)
      end,
    }, dialog)
    return
  end
  pageTitle(dialog.title or "", X(14), Y(9))
  if dialog.subtitle then
    shadowPrint(dialog.subtitle, X(14), Y(26), F.small, dialog.subtitleColor or FAINT)
  end
  local x, y, w = X(14), Y(40), math.floor(372 * u)
  if dialog.draw then
    local h = math.floor((dialog.drawH or 50) * u)
    panel(x, y, w, h, 0.85, dialog.edge)
    dialog.draw(x, y, w, h, u, { shadowPrint = shadowPrint, printCentered = printCentered, F = F })
    y = y + h + 4 * u
  end
  for _, line in ipairs(dialog.lines or {}) do
    local text, color = line, DIM
    if type(line) == "table" then
      text, color = line.text, line.color or DIM
    end
    y = y + wrapped(text, x, y, w, F.body, color) + 2 * u
  end
  local bw, bh = math.floor(260 * u), math.floor(15 * u)
  local bx = X(200) - bw / 2
  y = math.max(y + 4 * u, Y(150))
  for i, b in ipairs(dialog.buttons or {}) do
    button("dlg:" .. i, b.label, bx, y, bw, bh, function()
      audio.play("select")
      local keep = b.fn and b.fn(dialog)
      if not keep then
        act("resume")
      end
    end, { sub = b.sub, disabled = b.disabled })
    y = y + bh + 3 * u
  end
end

-- The survey map (src.surveymap) ---------------------------------------------------------

PAGES.map = function()
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.015, 0.01, 0.025, 0.94)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  pageTitle("Survey Map", X(14), Y(9))
  local tier = meta.tier("survey")
  shadowPrint("Charted by your own boots this run. " .. (tier >= 2 and "Gold: chests. Cyan: shops. Red: a bounty's quarry. " or "A second survey tier marks shops, chests and bounty quarries. ") .. "Click to mark a spot, right-click a mark to take it down.", X(14), Y(26), F.small, FAINT)
  local game = require("src.game")
  local sm = require("src.surveymap")
  love.graphics.setFont(F.small)
  local mx, my, mw, mh = X(14), Y(36), math.floor(372 * u), math.floor(182 * u)
  sm.draw(mx, my, mw, mh, u, game.player(), tier, game.mapMarks())
  -- zoom buttons in the corner of the map's border (the wheel zooms too)
  local bs = math.floor(10 * u)
  local gap = math.floor(2 * u)
  button("map:zoomout", "-", mx + mw - bs * 2 - gap * 2, my + gap, bs, bs, function()
    sm.zoom(1 / 1.4)
  end, { font = F.body })
  button("map:zoomin", "+", mx + mw - bs - gap, my + gap, bs, bs, function()
    sm.zoom(1.4)
  end, { font = F.body })
end

-- The bounty board (src.bounties) --------------------------------------------------------
-- Three wanted posters side by side, each with what is wanted, where, the
-- reward and a button to take it (or give it up). Taken ones are stamped.

local posterPhotos = {} -- kind -> photo, made once

PAGES.board = function()
  local bounties = require("src.bounties")
  local enemies = require("src.enemies")
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.015, 0.01, 0.025, 0.93)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  litBackdrop()
  local marks = meta.marks()
  pageTitle("Bounty Board", X(14), Y(9))
  markPrice(marks .. (marks == 1 and " mark" or " marks"), X(386), Y(11), F.body, meta.SIGIL_COLOR)
  local taken = bounties.taken()
  shadowPrint(string.format("Take up to %d. A taken bounty waits in its area every run until you claim it; the reward is paid the moment it dies.", bounties.MAX_TAKEN), X(14), Y(26), F.small, FAINT)
  local list = bounties.list()
  if #list == 0 then
    printCentered("Nothing posted. Come back after your next run.", X(200), Y(100), F.body, FAINT)
    return
  end
  local t = love.timer.getTime()
  for i, b in ipairs(list) do
    local cx = X(200 + (i - 2) * 128)
    local pw, ph = math.floor(56 * u), math.floor(66 * u)
    local cy = Y(76)
    if not posterPhotos[b.kind] then
      posterPhotos[b.kind] = enemies.photo(nil, b.kind) or false
    end
    drawPoster(cx, cy, pw, ph, b.name, posterPhotos[b.kind] or nil, 1, (i - 2) * 0.02, 1)
    if b.taken then
      -- A red "TAKEN" stamp across the paper
      love.graphics.push()
      love.graphics.translate(cx, cy + 4 * u)
      love.graphics.rotate(-0.3)
      love.graphics.setLineWidth(math.max(1, u * 0.7))
      love.graphics.setColor(0.72, 0.1, 0.08, 0.85)
      local sw = F.head:getWidth("TAKEN") + 6 * u
      love.graphics.rectangle("line", -sw / 2, -F.head:getHeight() / 2 - u, sw, F.head:getHeight() + 2 * u)
      love.graphics.setFont(F.head)
      love.graphics.print("TAKEN", math.floor(-F.head:getWidth("TAKEN") / 2), math.floor(-F.head:getHeight() / 2))
      love.graphics.pop()
    end
    -- What and where
    local ty = cy + ph / 2 + 6 * u
    local names = {}
    for _, a in ipairs(b.affixes) do
      names[#names + 1] = enemies.AFFIXES[a].name
    end
    local kindName = enemies.defs[b.kind].name or b.kind
    local what = table.concat(names, " ") .. " " .. kindName
    local c = enemies.AFFIXES[b.affixes[1]].color
    printCentered(what, cx, ty, F.small, { c[1] * 0.5 + 0.5, c[2] * 0.5 + 0.5, c[3] * 0.5 + 0.5 })
    ty = ty + F.small:getHeight() * 1.25
    printCentered("Last seen in " .. bounties.where(b), cx, ty, F.small, DIM)
    ty = ty + F.small:getHeight() * 1.5
    local rt = "Reward " .. b.reward
    local s = math.max(1, math.floor(u * 0.75 + 0.5))
    local rw = F.body:getWidth(rt) + 7 * s + 2 * u
    markPrice(rt, cx + rw / 2, ty, F.body, meta.SIGIL_COLOR)
    ty = ty + F.body:getHeight() + 4 * u
    local bw, bh = math.floor(60 * u), math.floor(12 * u)
    if b.taken then
      button("board:" .. b.id, "Give it up", math.floor(cx - bw / 2), ty, bw, bh, function()
        confirm({
          text = "Give up the bounty on " .. b.name .. "?",
          detail = "The poster comes down. Nothing is paid back.",
          yesLabel = "Give up",
          danger = true,
          yes = function()
            bounties.abandon(b)
            pop()
          end,
        })
      end, { danger = true })
    else
      local full = taken >= bounties.MAX_TAKEN
      button("board:" .. b.id, full and "Hands full" or "Take it", math.floor(cx - bw / 2), ty, bw, bh, function()
        if bounties.take(b) then
          audio.play("buy")
        else
          audio.play("deny")
        end
      end, { disabled = full })
    end
  end
end

PAGES.recap = function()
  local d = recapData or {}
  local ww, wh = love.graphics.getDimensions()
  local t = enterT
  local ti = t - IMPACT -- seconds since the poster hit (negative before)
  if t < 0.05 then
    slammed = false
  end
  if ti >= 0 and not slammed then
    slammed = true
    audio.play("poster_slam")
  end

  -- The page shakes when the poster hits
  local shake = ti >= 0 and ti < 0.45 and 4 * u * math.exp(-ti * 12) or 0
  love.graphics.push()
  love.graphics.translate(math.floor(math.sin(ti * 95) * shake), math.floor(math.cos(ti * 83) * shake))

  -- The world stays visible behind, just darker (the same darkness the death fade reached)
  love.graphics.setColor(0.05, 0.01, 0.02, 0.8)
  love.graphics.rectangle("fill", -20 * u, -20 * u, ww + 40 * u, wh + 40 * u)

  -- Everything but the poster is drawn onto a layer, so it can fade in as a whole
  if not recapLayer or recapLayer:getWidth() ~= ww or recapLayer:getHeight() ~= wh then
    recapLayer = love.graphics.newCanvas(ww, wh)
  end
  love.graphics.push("all")
  love.graphics.setCanvas(recapLayer)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()

  local name, killer = d.name or "The hunter", d.killer or "Unforgiving Dark"
  -- Everything in the middle is one group, centred on the screen: the poster
  -- on the left, the death text beside it
  local posterW, posterH = math.floor(56 * u), math.floor(66 * u)
  local gap = math.floor(14 * u)
  -- (what the text column says, and how tall it comes to; the column is only
  -- as wide as its text, so the group sits centred)
  local full = { { name, WARM }, { " met his end by the ", TEXT }, { killer, RED }, { ".", TEXT } }
  local width = 0
  for _, seg in ipairs(full) do
    width = width + F.body:getWidth(seg[1])
  end
  local oneLine = width < 170 * u
  local quip = '"' .. (d.quip or "") .. '"'
  local quipW, quipLines = F.body:getWrap(quip, math.floor(150 * u))
  local sentenceW = oneLine and width or math.max(F.body:getWidth(name .. " met his end"), F.body:getWidth("by the " .. killer .. "."))
  local colW = math.ceil(math.max(sentenceW, quipW, F.head:getWidth("You Died") * 1.4)) + math.floor(4 * u)
  local lineH = F.body:getHeight()
  local titleH = F.head:getHeight()
  local textH = titleH + 7 * u + lineH * (oneLine and 1.8 or 3.2) + #quipLines * lineH * 1.25

  -- The compendium block's top (so the group never runs into it)
  local list = d.discoveries or {}
  local groups = {}
  for _, c in ipairs(compendium.CATEGORIES) do
    local ids = {}
    for _, found in ipairs(list) do
      if found[1] == c.id then
        ids[#ids + 1] = found[2]
      end
    end
    if #ids > 0 then
      groups[#groups + 1] = { c.name, c.id, ids }
    end
  end
  local rowH = math.floor(10.5 * u)
  local bottom = Y(190)
  local blockTop = bottom - #groups * rowH - math.floor(11 * u)

  local groupH = math.max(posterH, textH)
  local groupTop = math.floor(math.min(wh / 2 - groupH / 2, blockTop - 6 * u - groupH))
  groupTop = math.max(groupTop, math.floor(6 * u))
  local gx = math.floor(ww / 2 - (posterW + gap + colW) / 2)
  local posterCx, posterCy = gx + posterW / 2, groupTop + groupH / 2
  local colCx = gx + posterW + gap + colW / 2

  -- Text column: You Died, the line, the quip
  local ty = math.floor(groupTop + (groupH - textH) / 2)
  printCentered("You Died", colCx, ty, F.head, RED)
  fonts.rule(colCx, ty + titleH + u, math.max(F.head:getWidth("You Died") * 1.4, 90 * u), math.max(1, math.floor(u * 0.5)), 0.7, 0.14, 0.18)
  local y = ty + titleH + 7 * u
  if oneLine then
    drawSegments(full, colCx, y, F.body)
    y = y + lineH * 1.8
  else
    drawSegments({ { name, WARM }, { " met his end", TEXT } }, colCx, y, F.body)
    y = y + lineH * 1.4
    drawSegments({ { "by the ", TEXT }, { killer, RED }, { ".", TEXT } }, colCx, y, F.body)
    y = y + lineH * 1.8
  end
  love.graphics.setFont(F.body)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(quip, math.floor(colCx - colW / 2) + 2, math.floor(y) + 2, colW, "center")
  love.graphics.setColor(DIM)
  love.graphics.printf(quip, math.floor(colCx - colW / 2), math.floor(y), colW, "center")

  -- What the run added to the compendium, just above the buttons: one row per
  -- group (its title, then the sprites; no names)
  love.graphics.setColor(BORDER[1], BORDER[2], BORDER[3], 0.5)
  love.graphics.rectangle("fill", math.floor(ww / 2 - 170 * u), blockTop - math.floor(2 * u), math.floor(340 * u), math.max(1, math.floor(u * 0.4)))
  if #groups == 0 then
    printCentered("Nothing new in the compendium this run.", ww / 2, bottom - 8 * u, F.body, FAINT)
  else
    printCentered("New in the compendium", ww / 2, blockTop + u, F.body, WARM)
    local iconW, step = math.floor(8.5 * u), math.floor(10 * u)
    local labelW = math.floor(38 * u)
    local perRow = math.floor((340 * u - labelW) / step)
    -- (the block is centred as a whole, by its widest row)
    local widest = 0
    for _, g in ipairs(groups) do
      widest = math.max(widest, math.min(#g[3], perRow))
    end
    local x0 = math.floor(ww / 2 - (labelW + widest * step) / 2)
    for gi, g in ipairs(groups) do
      local yy = blockTop + math.floor(11 * u) + (gi - 1) * rowH
      shadowPrint(g[1], x0, yy + (iconW - F.small:getHeight()) / 2, F.small, DIM)
      local ids = g[3]
      local shown = #ids > perRow and perRow - 1 or #ids
      for i = 1, shown do
        local entry = compendium.entry(g[2], ids[i])
        local ix = x0 + labelW + (i - 1) * step
        love.graphics.setColor(0.07, 0.05, 0.09, 0.9)
        love.graphics.rectangle("fill", ix, yy, iconW, iconW, u * 0.5, u * 0.5)
        if entry then
          compendium.drawIcon(entry, ix + u * 0.5, yy + u * 0.5, iconW - u, iconW - u)
        end
      end
      if #ids > shown then
        shadowPrint("+" .. (#ids - shown), x0 + labelW + shown * step, yy + (iconW - F.small:getHeight()) / 2, F.small, DIM)
      end
    end
  end

  local w, h = math.floor(84 * u), math.floor(13 * u)
  local by = Y(196)
  -- (a button press in the first moments is ignored: it is probably the
  -- hunter's trigger finger, not a choice)
  button("recap:new", "New run", math.floor(ww / 2 - w - 3 * u), by, w, h, function()
    if enterT > 0.9 then
      act("restart")
    end
  end)
  button("recap:menu", "Quit to Menu", math.floor(ww / 2 + 3 * u), by, w, h, function()
    if enterT > 0.9 then
      act("title")
    end
  end)

  love.graphics.pop() -- (back from the layer)
  -- Nothing but the poster until it lands; then the rest fades in
  local fade = math.max(0, math.min(1, (t - IMPACT + 0.1) / 0.45))
  if fade > 0 then
    love.graphics.setColor(fade, fade, fade, fade) -- (premultiplied)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.draw(recapLayer, 0, 0)
    love.graphics.setBlendMode("alpha")
  end

  -- The poster, flying in from close to the screen and slamming down
  if t >= SLAM_START then
    local scale, spin, alpha = 1, 0, 1
    if ti < 0 then
      local k = (t - SLAM_START) / (IMPACT - SLAM_START)
      local ease = k * k * k
      scale = 3.2 - 2.2 * ease
      spin = 0.35 * (1 - ease)
      alpha = math.min(1, k * 3)
    else
      scale = 1 - 0.05 * math.exp(-ti * 12) * math.cos(ti * 28) -- (a little rebound)
    end
    drawPoster(posterCx, posterCy, posterW, posterH, d.noun, d.photo, scale, spin, alpha)
    -- Dust thrown out from its edges as it hits
    if ti >= 0 and ti < 0.45 then
      for i = 1, 18 do
        local a = i * 2.399
        local speed = (45 + (i * 37) % 70) * u
        local dx, dy = math.cos(a) * speed * ti, math.sin(a) * speed * ti * 0.8
        local ex = posterCx + math.cos(a) * posterW * 0.5 + dx
        local ey = posterCy + math.sin(a) * posterH * 0.5 + dy
        local size = math.max(1, math.floor((1 + i % 3) * u * 0.6))
        love.graphics.setColor(0.75, 0.66, 0.5, 0.7 * (1 - ti / 0.45))
        love.graphics.rectangle("fill", math.floor(ex), math.floor(ey), size, size)
      end
    end
  end
  love.graphics.pop()
end

-- Pause ------------------------------------------------------------------------------

PAGES.pause = function()
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0.03, 0.02, 0.05, 0.62)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  litBackdrop()
  pageTitle("Paused", ww / 2, Y(34), true)
  local y0 = Y(34) + F.head:getHeight() + 5 * u
  local okc, catacombs = pcall(require, "src.scenes.catacombs")
  local sd = okc and catacombs.seed and catacombs.seed()
  if sd then
    printCentered("seed - " .. sd, ww / 2, y0, F.small, FAINT)
    y0 = y0 + F.small:getHeight() + 2 * u
  end
  local okr, evs = pcall(require, "src.events")
  if okr then
    local secs = math.floor(evs.runTime())
    printCentered(string.format("Run time  %d:%02d:%02d", math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60), ww / 2, y0, F.small, { 0.8, 0.85, 1 })
  end
  local w, h, gap = math.floor(96 * u), math.floor(12 * u), math.floor(3.5 * u)
  local x, y = math.floor((ww - w) / 2), Y(70)
  local function abandon(text, action)
    return function()
      confirm({ text = text, detail = "This run will be lost; the compendium keeps what you found.", yesLabel = "Yes", danger = true, yes = function()
        act(action)
      end })
    end
  end
  local list = {
    { "pause:resume", "Resume", function()
      act("resume")
    end },
    { "pause:compendium", "Compendium", function()
      push("compendium")
    end },
    { "pause:settings", "Settings", function()
      push("settings")
    end },
    { "pause:restart", "Restart run", abandon("Restart the run?", "restart") },
    { "pause:title", "Quit to title", function()
      act("title")
    end },
    { "pause:quit", "Quit to desktop", function()
      act("quit")
    end },
  }
  for _, b in ipairs(list) do
    if b then
      button(b[1], b[2], x, y, w, h, b[3])
      y = y + h + gap
    end
  end
end

-- Input --------------------------------------------------------------------------------

local function moveFocus(dx, dy)
  local cur = find(focusId)
  if not cur then
    if widgets[1] then
      focusId = widgets[1].id
    end
    return
  end
  local cx, cy = cur.x + cur.w / 2, cur.y + cur.h / 2
  local best, bestScore
  for _, w in ipairs(widgets) do
    if w ~= cur then
      local wx, wy = w.x + w.w / 2, w.y + w.h / 2
      local ddx, ddy = wx - cx, wy - cy
      local along = ddx * dx + ddy * dy
      if along > 1 then
        local across = math.abs(ddx * dy) + math.abs(ddy * dx)
        local score = along + across * 2.5
        if not bestScore or score < bestScore then
          best, bestScore = w, score
        end
      end
    end
  end
  if not best and dy ~= 0 then
    -- Wrap round a vertical list to the far end
    for _, w in ipairs(widgets) do
      if w ~= cur and math.abs((w.x + w.w / 2) - cx) < cur.w then
        local along = ((w.y + w.h / 2) - cy) * dy
        if along < -1 and (not bestScore or along < bestScore) then
          best, bestScore = w, along
        end
      end
    end
  end
  if best then
    focusId = best.id
    reveal = true
    audio.play("tick")
  end
end

local function back()
  if listening then
    listening = nil
    audio.play("back")
    return
  end
  if not pop() and (root == "pause" or root == "camp" or root == "board" or root == "map" or root == "ghost" or root == "dialog") then
    act("resume")
  end
end

function menu.keypressed(key)
  if not root then
    return
  end
  if top() == "name" then
    -- (letters arrive through love.textinput, so no key here moves the focus)
    if key == "backspace" then
      local t = nameState.text
      nameState.text = t:sub(1, math.max(0, #t - 1))
    elseif key == "return" or key == "kpenter" then
      confirmName()
    elseif key == "escape" then
      pop()
    end
    return
  end
  if listening then
    if key == "escape" then
      listening = nil
      audio.play("back")
    elseif key == "delete" or key == "backspace" then
      input.bind(listening.action, listening.slot, false)
      settings.save()
      listening = nil
      audio.play("back")
    elseif input.isReserved(key) then
      audio.play("deny")
    else
      input.bind(listening.action, listening.slot, key)
      settings.save()
      listening = nil
      audio.play("select")
    end
    return
  end
  local cur = find(focusId)
  if root == "map" and #stack == 0 then
    if input.is("map", key) or input.is("interact", key) then
      act("resume")
      return
    elseif key == "=" or key == "+" or key == "kp+" then
      require("src.surveymap").zoom(1.4)
      return
    elseif key == "-" or key == "kp-" then
      require("src.surveymap").zoom(1 / 1.4)
      return
    elseif key == "0" then
      require("src.surveymap").fit()
      return
    end
  end
  if (root == "camp" or root == "board" or root == "ghost" or root == "dialog") and #stack == 0 and input.is("interact", key) then
    act("resume") -- (the key that opened a camp page closes it again)
    return
  end
  if key == "up" or key == "w" then
    moveFocus(0, -1)
  elseif key == "down" or key == "s" then
    moveFocus(0, 1)
  elseif key == "left" or key == "a" then
    if cur and cur.left then
      cur.left()
    else
      moveFocus(-1, 0)
    end
  elseif key == "right" or key == "d" then
    if cur and cur.right then
      cur.right()
    else
      moveFocus(1, 0)
    end
  elseif key == "return" or key == "kpenter" or key == "space" then
    if cur and cur.activate then
      audio.play("select")
      cur.activate()
    end
  elseif key == "escape" or key == "backspace" then
    back()
  elseif key == "delete" and cur and cur.clear then
    cur.clear()
  elseif (key == "q" or key == "[" or key == "pageup") then
    if top() == "compendium" then
      setCompTab(comp.tab - 1)
    elseif top() == "settings" then
      settingsTab = (settingsTab - 2) % #SETTINGS_TABS + 1
      audio.play("page")
    end
  elseif (key == "e" or key == "]" or key == "pagedown") then
    if top() == "compendium" then
      setCompTab(comp.tab + 1)
    elseif top() == "settings" then
      settingsTab = settingsTab % #SETTINGS_TABS + 1
      audio.play("page")
    end
  elseif (key == "z" or key == "c") and top() == "compendium" and root == "title" then
    cycleSlot(key == "z" and -1 or 1)
  end
end

function menu.mousepressed(x, y, button)
  if not root then
    return
  end
  mouseX, mouseY = x, y
  if top() == "camp" and campNpc == "cartographer" and button == 1 and require("src.chart").inBox(x, y) and not hovered() then
    mapDrag = { x = x, y = y, moved = false, chart = true } -- (a drag on his chart moves it)
    return
  end
  if top() == "map" then
    -- On the survey map: left-click marks a spot, right-click takes a mark down
    -- (or, dragged, moves the map)
    local sm = require("src.surveymap")
    if sm.inBox(x, y) and not hovered() then
      if button == 1 then
        if sm.addMarker(x, y) then
          audio.play("select")
        end
        return
      elseif button == 2 then
        mapDrag = { x = x, y = y, moved = false }
        return
      end
    end
  end
  if button == 2 then
    back()
    return
  end
  if button ~= 1 then
    return
  end
  if listening then
    listening = nil
    audio.play("back")
    return
  end
  local w = hovered()
  pressedId = w and w.id or nil
  if w then
    focusId = w.id
    if w.drag then
      dragging = w
      w.drag(x)
    end
  end
end

function menu.mousereleased(x, y, button)
  if mapDrag and button == 2 then
    local drag = mapDrag
    mapDrag = nil
    if not drag.moved and require("src.surveymap").removeMarkerAt(x, y) then
      audio.play("back")
    end
    return
  end
  if not root or button ~= 1 then
    return
  end
  mouseX, mouseY = x, y
  local w = hovered()
  local down = pressedId
  pressedId = nil
  if dragging then
    dragging = nil
    return
  end
  if w and w.id == down and w.activate then
    audio.play("select")
    w.activate()
  end
end

function menu.wheelmoved(_, dy)
  if top() == "camp" and campNpc == "cartographer" and require("src.chart").inBox(mouseX, mouseY) then
    require("src.chart").zoom(1.18 ^ dy, mouseX, mouseY)
  end
  if top() == "map" then
    require("src.surveymap").zoom(1.18 ^ dy, mouseX, mouseY)
  end
  if top() == "compendium" and comp.region then
    comp.target = comp.target - dy * 24 * u
  end
end

-- Hovering selects (only when the mouse actually moves, so it doesn't fight the keys)
function menu.update(dt)
  clock = clock + (dt or 0)
  enterT = enterT + (dt or 0)
  if not root then
    light.x = nil -- so the light starts at the cursor when a menu next opens
    return
  end
  local mx, my = love.mouse.getPosition()
  light.x, light.y = mx, my
  if mapDrag and mapDrag.chart then
    if love.mouse.isDown(1) then
      require("src.chart").pan(mx - mapDrag.x, my - mapDrag.y)
      mapDrag.x, mapDrag.y = mx, my
    else
      mapDrag = nil
    end
  end
  if top() == "map" then
    local sm = require("src.surveymap")
    -- a right-button drag moves the map; the arrow keys and WASD do too
    if mapDrag and love.mouse.isDown(2) then
      local dx, dy = mx - mouseX, my - mouseY
      if dx ~= 0 or dy ~= 0 then
        sm.pan(dx, dy)
        if math.abs(mx - mapDrag.x) + math.abs(my - mapDrag.y) > 4 then
          mapDrag.moved = true
        end
      end
    else
      mapDrag = nil
    end
    local kx = (love.keyboard.isDown("left", "a") and 1 or 0) - (love.keyboard.isDown("right", "d") and 1 or 0)
    local ky = (love.keyboard.isDown("up", "w") and 1 or 0) - (love.keyboard.isDown("down", "s") and 1 or 0)
    if kx ~= 0 or ky ~= 0 then
      sm.pan(kx * 420 * dt, ky * 420 * dt)
    end
  end
  if mx ~= mouseX or my ~= mouseY then
    mouseX, mouseY = mx, my
    if dragging then
      dragging.drag(mx)
    else
      local w = hovered()
      if w and w.id ~= focusId then
        focusId = w.id
        reveal = false
        audio.play("tick", 0.5)
      end
    end
  end
end

function menu.draw(scale)
  if not root then
    return
  end
  layout(scale)
  widgets = {}
  local page = top()
  -- Pages over the pause menu or the title replace it; the confirm box sits over the page below it
  casters, casting = casting, {}
  if page == "confirm" and #stack >= 2 then
    PAGES[stack[#stack - 1]]()
    love.graphics.setShader()
    widgets = {}
  elseif page == "confirm" then
    PAGES[root]()
    love.graphics.setShader()
    widgets = {}
  end
  PAGES[page]()
  love.graphics.setShader()
  reveal = false
  -- Nothing focused (a new page): focus its main control, else the first
  if not find(focusId) and widgets[1] then
    focusId = widgets[1].id
    local prefix = DEFAULT_FOCUS[page]
    for _, w in ipairs(widgets) do
      if prefix and w.id:sub(1, #prefix) == prefix then
        focusId = w.id
        break
      end
    end
  end
  -- A short fade as a page comes in
  if enterT < 0.15 then
    local ww, wh = love.graphics.getDimensions()
    love.graphics.setColor(0.02, 0.015, 0.035, 0.6 * (1 - enterT / 0.15))
    love.graphics.rectangle("fill", 0, 0, ww, wh)
  end
  love.graphics.setColor(1, 1, 1)
end

return menu
