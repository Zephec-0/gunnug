-- Screen-space HUD: health bar and gun status (chambers + reload), Noita-style
-- in the top-right corner.
local fontFace = require("src.fonts")
local goldbag = require("src.goldbag")

local hud = {}

local function font(size)
  return fontFace.get(size)
end

-- Gradients -------------------------------------------------------------------
-- Health bars are drawn at the window's full resolution, with the colour
-- changing smoothly down every pixel row (vertex-coloured quads).

-- A rectangle shaded from top colour to bottom colour
function hud.gradRect(x, y, w, h, top, bottom, alpha)
  alpha = alpha or 1
  local mesh = love.graphics.newMesh({
    { x, y, 0, 0, top[1], top[2], top[3], alpha },
    { x + w, y, 1, 0, top[1], top[2], top[3], alpha },
    { x + w, y + h, 1, 1, bottom[1], bottom[2], bottom[3], alpha },
    { x, y + h, 0, 1, bottom[1], bottom[2], bottom[3], alpha },
  }, "fan", "static")
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(mesh)
end

-- Blood: a dark crimson, glossier at the surface
local LIQUID_TOP = { 0.70, 0.07, 0.11 }
local LIQUID_MID = { 0.45, 0.03, 0.07 }
local LIQUID_BOTTOM = { 0.17, 0.01, 0.035 }

-- The player's health: a glass tube of dark blood. A smooth gradient runs down
-- it; the surface ripples in hard pixel steps; bubbles rise now and then as
-- arcade-style pixel sprites (a little ring with a glint) and pop at the top.
-- When health is low (under 30%) the blood boils: the surface churns, bubbles
-- are big and constant, spray flies, the tube shakes and glows.
local bubbles, drops = {}, {}
local lastBarTime

function hud.drawHealthBar(player, u, x, y, w, h)
  local now = love.timer.getTime()
  local dt = math.min(0.1, lastBarTime and now - lastBarTime or 0)
  lastBarTime = now
  local frac = math.max(0, math.min(1, player.hp / player.maxHp))
  local low = frac < 0.3 and (1 - frac / 0.3) or 0 -- 0 = fine, 1 = nearly dead
  local fw = w * frac

  -- Shaking when it boils
  if low > 0.2 then
    x = x + (love.math.random() - 0.5) * low * 0.9 * u
    y = y + (love.math.random() - 0.5) * low * 0.9 * u
  end
  -- A red glow around a boiling tube
  if low > 0 then
    love.graphics.setColor(1, 0.1, 0.1, (0.10 + 0.14 * math.sin(now * 8) ^ 2) * low)
    love.graphics.rectangle("fill", x - 3 * u, y - 3 * u, w + 6 * u, h + 6 * u, 2 * u, 2 * u)
  end
  love.graphics.setColor(0.03, 0.015, 0.04, 0.5)
  love.graphics.rectangle("fill", x - 0.5 * u, y - 0.5 * u, w + u, h + u, u * 0.5, u * 0.5)
  hud.gradRect(x, y, w, h, { 0.20, 0.05, 0.09 }, { 0.07, 0.02, 0.05 })

  -- The liquid: 3-px columns whose tops ripple, each shaded top to bottom
  local q = math.max(2, math.floor(u * 0.8)) -- one "arcade pixel"
  local cw = q
  local amp = (0.32 + 2.0 * low) * u * 0.5
  local speed = 2 + 9 * low
  local verts = {}
  local function top(px)
    local raw = amp * (0.5 + 0.5 * math.sin(px * 0.045 / u * 4.8 + now * speed) + 0.4 * math.sin(px * 0.11 + now * speed * 1.7))
    return y + math.floor(raw / q + 0.5) * q -- the surface moves in whole pixel steps
  end
  local flare = low * (0.5 + 0.5 * math.sin(now * 10)) * 0.25
  local function col(c, k)
    return math.min(1, c[1] + flare * k), math.min(1, c[2] + flare * k * 0.6), math.min(1, c[3] + flare * k * 0.6)
  end
  local tr, tg, tb = col(LIQUID_TOP, 1)
  local mr, mg, mb = col(LIQUID_MID, 0.6)
  local br, bg, bb = LIQUID_BOTTOM[1], LIQUID_BOTTOM[2], LIQUID_BOTTOM[3]
  local n = math.ceil(fw / cw)
  for i = 0, n - 1 do
    local xa = x + i * cw
    local xb = math.min(x + fw, xa + cw)
    local ta, tb2 = top(xa), top(xb)
    local mida, midb = ta + (y + h - ta) * 0.35, tb2 + (y + h - tb2) * 0.35
    -- Two quads per column: the bright upper part, then down into the deep red
    verts[#verts + 1] = { xa, ta, 0, 0, tr, tg, tb, 1 }
    verts[#verts + 1] = { xb, tb2, 0, 0, tr, tg, tb, 1 }
    verts[#verts + 1] = { xb, midb, 0, 0, mr, mg, mb, 1 }
    verts[#verts + 1] = { xa, ta, 0, 0, tr, tg, tb, 1 }
    verts[#verts + 1] = { xb, midb, 0, 0, mr, mg, mb, 1 }
    verts[#verts + 1] = { xa, mida, 0, 0, mr, mg, mb, 1 }
    verts[#verts + 1] = { xa, mida, 0, 0, mr, mg, mb, 1 }
    verts[#verts + 1] = { xb, midb, 0, 0, mr, mg, mb, 1 }
    verts[#verts + 1] = { xb, y + h, 0, 0, br, bg, bb, 1 }
    verts[#verts + 1] = { xa, mida, 0, 0, mr, mg, mb, 1 }
    verts[#verts + 1] = { xb, y + h, 0, 0, br, bg, bb, 1 }
    verts[#verts + 1] = { xa, y + h, 0, 0, br, bg, bb, 1 }
  end
  if #verts > 0 then
    local mesh = love.graphics.newMesh(verts, "triangles", "static")
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(mesh)
  end
  -- A lit meniscus along the surface
  love.graphics.setColor(0.95, 0.30, 0.32, 0.5)
  for i = 0, n - 1 do
    local xa = x + i * cw
    love.graphics.rectangle("fill", xa, top(xa), math.min(cw, x + fw - xa), math.max(1, q * 0.6))
  end

  -- Bubbles: a trickle when healthy, a roiling boil when low. Each is a tiny
  -- pixel sprite on the arcade-pixel grid: a dot, a 2x2 blob, or a ring with a
  -- glint, rising in whole-pixel steps and popping into spray at the top.
  if fw > 6 * u then
    local rate = 0.6 + low * 14
    if love.math.random() < rate * dt then
      local kind = love.math.random() < (0.35 + low * 0.35) and 3 or (love.math.random() < 0.5 and 2 or 1)
      bubbles[#bubbles + 1] = {
        px = love.math.random() * fw,
        py = h,
        size = kind,
        vy = (3 + love.math.random() * 5) * u * (1 + low * 2.5),
        sway = love.math.random() * 6.3,
        swayRate = 2 + love.math.random() * 3 + low * 4,
      }
    end
  end
  local RING, FILL, GLINT = { 0.80, 0.16, 0.19 }, { 0.30, 0.02, 0.05 }, { 1.0, 0.62, 0.62 }
  local function pix(bx, by, c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
    love.graphics.rectangle("fill", math.floor((x + bx) / q) * q, math.floor((y + by) / q) * q, q, q)
  end
  for i = #bubbles, 1, -1 do
    local b = bubbles[i]
    b.py = b.py - b.vy * dt
    b.px = b.px + math.sin(now * b.swayRate + b.sway) * u * (0.5 + low) * dt * 6
    if b.px > fw or b.px < 0 then
      table.remove(bubbles, i)
    elseif b.py <= q * 0.5 then
      -- Pops at the surface; a boiling one throws off spray
      if low > 0.1 then
        for _ = 1, 2 + math.floor(low * 3) do
          drops[#drops + 1] = { x = x + b.px, y = y, vx = (love.math.random() - 0.5) * 30 * u, vy = -(10 + love.math.random() * 24 * (0.5 + low)) * u, life = 0.35 }
        end
      end
      table.remove(bubbles, i)
    else
      local bx, by = b.px, b.py
      if b.size == 1 then
        pix(bx, by, RING)
      elseif b.size == 2 then
        pix(bx, by, RING) pix(bx + q, by, RING) pix(bx, by + q, RING) pix(bx + q, by + q, FILL)
        pix(bx, by, GLINT, 0.9)
      else
        -- a ring of eight pixels around a dark centre, glint at the top left
        for ox = 0, 2 do
          for oy = 0, 2 do
            if not (ox == 1 and oy == 1) then
              pix(bx + ox * q, by + oy * q, RING)
            end
          end
        end
        pix(bx + q, by + q, FILL)
        pix(bx, by, GLINT)
      end
    end
  end
  for i = #drops, 1, -1 do
    local d = drops[i]
    d.life = d.life - dt
    d.vy = d.vy + 90 * u * dt
    d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
    if d.life <= 0 then
      table.remove(drops, i)
    else
      love.graphics.setColor(0.72, 0.10, 0.14, math.min(1, d.life * 4))
      love.graphics.rectangle("fill", math.floor(d.x / q) * q, math.floor(d.y / q) * q, q, q)
    end
  end

  -- Glass: a faint highlight down the top and a rim
  love.graphics.setColor(1, 1, 1, 0.10)
  love.graphics.rectangle("fill", x, y, w, h * 0.28)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.55, 0.5, 0.6, 0.32)
  love.graphics.rectangle("line", x - 0.25 * u, y - 0.25 * u, w + 0.5 * u, h + 0.5 * u, u * 0.5, u * 0.5)
end

function hud.font(scale)
  return font(math.max(10, math.floor(scale * 4)))
end

local function shadowText(text, x, y, f)
  love.graphics.setFont(f)
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setColor(0, 0, 0, a)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(r, g, b, a)
  love.graphics.print(text, x, y)
end

function hud.draw(player, scale)
  local ww = love.graphics.getWidth()
  local u = scale -- one game pixel at the current scale
  local f = hud.font(scale)
  local margin = 6 * u

  -- Health bar
  local barW, barH = 40 * u, 4.4 * u
  local x, y = ww - margin - barW, margin
  hud.drawHealthBar(player, u, x, y, barW, barH)
  love.graphics.setColor(1, 1, 1)
  local hpText = tostring(math.floor(player.hp))
  shadowText(hpText, x - f:getWidth(hpText) - 4 * u, y + barH / 2 - f:getHeight() / 2, f)

  if player.gun then
    hud.drawGunStatus(player.gun, ww, margin, y + barH, u, f)
  end

  -- Gold: a sack with the run's coins in it, and the total underneath
  local goldText = tostring(player.inventory.gold)
  local p = math.max(1, math.floor(u * 0.5 + 0.5))
  local bagL, bagR, bagBottom = goldbag.draw(player.inventory.gold, player, ww - margin, y + barH + 20 * u, p)
  love.graphics.setColor(0.97, 0.98, 1)
  shadowText(goldText, math.floor((bagL + bagR) / 2 - f:getWidth(goldText) / 2), math.floor(bagBottom + 2 * u), f)
  love.graphics.setColor(1, 1, 1)

  hud.drawBanner(scale)
end

-- Ammo pips -----------------------------------------------------------------
-- Each chamber of the held gun is a little cartridge: the double-barrel's are
-- the fat red-and-brass base of a shotgun shell, everything else's bullets
-- (copper tip, brass case). A fired one goes dull (the revolver keeps its
-- empty brass until it reloads) and gives a tiny poof: a flash, three wisps of
-- smoke and a casing flicked up. Reloading pops the full set back in, left to
-- right.
local PIP = {
  revolver = { w = 3, pitch = 5 },
  pistol = { w = 2, pitch = 4 },
  mg = { w = 2, pitch = 3 },
  shell = { w = 5, pitch = 7 },
}
local TIP, TIP_L = { 0.84, 0.52, 0.28 }, { 1.0, 0.80, 0.55 }
local BRASS, BRASS_L, BRASS_D, RIM = { 0.95, 0.74, 0.26 }, { 1.0, 0.92, 0.55 }, { 0.68, 0.47, 0.15 }, { 0.50, 0.34, 0.10 }
local HULL, HULL_L, HULL_D = { 0.80, 0.16, 0.13 }, { 0.98, 0.42, 0.34 }, { 0.50, 0.08, 0.08 }
local ammoState = setmetatable({}, { __mode = "k" }) -- gun -> { last, puffs, fillAt, fillFrom }
local POOF = 0.38
local POP = 0.2

local function pipKind(gun, count)
  local model = gun.def.model
  local kind = model == "shotgun" and "shell" or (model == "revolver" and "revolver" or (model == "automatic" and "mg" or "pistol"))
  if count > 24 and kind ~= "mg" and kind ~= "shell" then
    kind = "mg"
  end
  return kind
end

-- One pip with its left edge at x and bottom at yb; q = one pip pixel
local function drawPip(kind, x, yb, q, filled, lift)
  local function cell(cx, cy, cw, ch, c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
    love.graphics.rectangle("fill", x + cx * q, yb - lift - (8 - cy) * q, cw * q, ch * q)
  end
  if kind == "shell" then
    -- The base of a shotgun shell: red hull cut off above, a brass band, a rim
    if filled then
      cell(0, 2, 5, 4, HULL)
      cell(0, 2, 1, 4, HULL_L)
      cell(4, 2, 1, 4, HULL_D)
      cell(0, 2, 5, 1, HULL_D)
      cell(0, 6, 5, 1, BRASS)
      cell(0, 6, 1, 1, BRASS_L)
      cell(4, 6, 1, 1, BRASS_D)
      cell(0, 7, 5, 1, BRASS)
      cell(0, 7, 5, 1, BRASS_D, 0.5)
      cell(0, 7, 1, 1, BRASS_L)
      cell(2, 4, 1, 1, { 1, 1, 1 }, 0.25) -- a glint on the hull
    else
      -- Spent: a scorched, dull hull and a dark brass base
      cell(0, 3, 5, 3, { 0.30, 0.10, 0.10 }, 0.55)
      cell(0, 6, 5, 2, { 0.34, 0.27, 0.15 }, 0.55)
      cell(1, 3, 3, 1, { 0.08, 0.06, 0.06 }, 0.6)
    end
    return
  end
  local w = PIP[kind].w
  if filled then
    if w == 3 then
      cell(1, 0, 1, 1, TIP_L)
      cell(0, 1, 3, 1, TIP)
      cell(0, 1, 1, 1, TIP_L)
      cell(0, 2, 1, 5, BRASS_L)
      cell(1, 2, 1, 5, BRASS)
      cell(2, 2, 1, 5, BRASS_D)
      cell(0, 4, 3, 1, BRASS_D, 0.5) -- the groove round the case
    else
      cell(0, 0, 2, 1, TIP_L)
      cell(0, 1, 2, 1, TIP)
      cell(0, 2, 1, 5, BRASS_L)
      cell(1, 2, 1, 5, BRASS)
    end
    cell(0, 7, w, 1, RIM)
  elseif kind == "revolver" then
    -- The empty case stays in the cylinder
    cell(0, 2, w, 5, { 0.42, 0.32, 0.14 }, 0.8)
    cell(0, 2, w, 1, { 0.10, 0.07, 0.05 })
    cell(0, 7, w, 1, { 0.30, 0.2, 0.08 }, 0.8)
  else
    cell(0, 2, w, 6, { 0.45, 0.40, 0.35 }, 0.22)
  end
end

local function drawPoof(kind, cx, cy, q, age, seed)
  local k = age / POOF
  if age < 0.07 then
    local s = (kind == "shell" and 7 or 5) * q
    love.graphics.setColor(1, 0.92, 0.55, 1 - age / 0.07)
    love.graphics.rectangle("fill", math.floor(cx - s / 2), math.floor(cy - s / 2), s, s)
  end
  for i = 1, 3 do
    local ang = seed * 6.28 + i * 2.1
    local d = (4 + 7 * k) * q
    love.graphics.setColor(0.78, 0.78, 0.8, (1 - k) * 0.65)
    local sz = math.max(1, math.floor(q * (1.2 - 0.4 * k) + 0.5))
    love.graphics.rectangle("fill", math.floor(cx + math.cos(ang) * d), math.floor(cy + math.sin(ang) * d * 0.7 - 6 * q * k), sz, sz)
  end
  if kind ~= "revolver" then
    -- The casing flicked up and out
    local fx, fy = cx - (3 + seed * 5) * q * k, cy - (14 * k - 22 * k * k) * q
    love.graphics.setColor(BRASS[1], BRASS[2], BRASS[3], 1 - k)
    love.graphics.rectangle("fill", math.floor(fx), math.floor(fy), q, 2 * q)
  end
end

-- Pips, name and reload bar of the held gun, right-aligned below the health bar
function hud.drawGunStatus(gun, ww, margin, top, u, f)
  local count = gun:maxChambers()
  local kind = pipKind(gun, count)
  local q = math.max(1, math.floor(u * 0.5 + 0.5))
  local spec = PIP[kind]
  local pitch, pw = spec.pitch * q, spec.w * q
  local rowW = (count - 1) * pitch + pw
  local cy = top + 8 * u
  local yb = math.floor(cy + 4 * q)
  local x0 = ww - margin - rowW
  local now = love.timer.getTime()

  -- What changed since last frame: rounds fired (each gets a poof), or refilled
  local st = ammoState[gun]
  if not st then
    st = { last = gun.chambers, puffs = {} }
    ammoState[gun] = st
  end
  if gun.chambers < st.last then
    for i = gun.chambers + 1, math.min(st.last, gun.chambers + 8) do
      st.puffs[#st.puffs + 1] = { i = i, born = now, seed = love.math.random() }
    end
  elseif gun.chambers > st.last then
    st.fillAt, st.fillFrom = now, st.last
  end
  st.last = gun.chambers

  for i = 1, count do
    local lift = 0
    if st.fillAt and i > st.fillFrom then
      local age = now - st.fillAt - (i - st.fillFrom) / math.max(1, count - st.fillFrom) * 0.2
      if age > 0 and age < POP then
        lift = math.sin(age / POP * math.pi) * 3 * q
      elseif age <= 0 and gun.chambers >= i then
        lift = 0
      end
    end
    drawPip(kind, x0 + (i - 1) * pitch, yb, q, i <= gun.chambers, math.floor(lift))
  end

  for n = #st.puffs, 1, -1 do
    local pf = st.puffs[n]
    local age = now - pf.born
    if age >= POOF or n > 24 then
      table.remove(st.puffs, n)
    else
      drawPoof(kind, x0 + (pf.i - 1) * pitch + pw / 2, yb - 4 * q, q, age, pf.seed)
    end
  end

  love.graphics.setColor(1, 1, 1)
  shadowText(gun.name, x0 - f:getWidth(gun.name) - 4 * u, cy - f:getHeight() / 2, f)

  -- Reload bar
  if gun:isReloading() then
    local ry = yb + 3 * u
    love.graphics.setColor(0.1, 0.05, 0.08, 0.8)
    love.graphics.rectangle("fill", x0, ry, rowW, u * 1.5)
    love.graphics.setColor(0.4, 0.85, 1)
    love.graphics.rectangle("fill", x0, ry, rowW * gun:reloadProgress(), u * 1.5)
  end
end

-- Area title card, e.g. when entering a new area
local banner = { time = 0 }
local BANNER_TIME = 3.5

function hud.showBanner(title, subtitle)
  banner = { title = title, subtitle = subtitle, time = BANNER_TIME }
end

function hud.update(dt)
  banner.time = math.max(0, banner.time - dt)
end

function hud.drawBanner(scale)
  if banner.time <= 0 or hud.hideBanner then
    return
  end
  local elapsed = BANNER_TIME - banner.time
  local alpha = math.min(1, elapsed / 0.4, banner.time / 0.8)
  local ww, wh = love.graphics.getDimensions()
  local big = font(math.max(16, math.floor(scale * 9)))
  local f = font(math.max(10, math.floor(scale * 4)))
  local y = math.floor(wh * 0.22)
  love.graphics.setColor(0.96, 0.98, 1, alpha)
  shadowText(banner.title, math.floor((ww - big:getWidth(banner.title)) / 2), y, big)
  fontFace.rule(ww / 2, y + big:getHeight() + 2 * scale, math.max(big:getWidth(banner.title) * 1.3, 80 * scale), math.max(1, math.floor(scale * 0.5)), 0.46, 0.62, 0.9, alpha * 0.9)
  if banner.subtitle then
    love.graphics.setColor(1, 1, 1, alpha * 0.85)
    shadowText(banner.subtitle, math.floor((ww - f:getWidth(banner.subtitle)) / 2), y + big:getHeight() + 6 * scale, f)
  end
end

-- Shown over a dimmed screen once the hunter has died
function hud.drawDeath(scale)
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  local big = font(math.max(16, math.floor(scale * 11)))
  local f = font(math.max(10, math.floor(scale * 4)))
  local y = math.floor(wh * 0.38)
  local title, sub = "You Died", "Press R to begin a new hunt"
  love.graphics.setColor(0.86, 0.16, 0.2)
  shadowText(title, math.floor((ww - big:getWidth(title)) / 2), y, big)
  fontFace.rule(ww / 2, y + big:getHeight() + 2 * scale, math.max(big:getWidth(title) * 1.2, 80 * scale), math.max(1, math.floor(scale * 0.5)), 0.7, 0.14, 0.18)
  love.graphics.setColor(1, 1, 1, 0.85)
  shadowText(sub, math.floor((ww - f:getWidth(sub)) / 2), y + big:getHeight() + 6 * scale, f)
end

function hud.drawCrosshair(vx, vy)
  local x, y = math.floor(vx), math.floor(vy)
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", x - 5, y + 1, 3, 1)
  love.graphics.rectangle("fill", x + 3, y + 1, 3, 1)
  love.graphics.rectangle("fill", x + 1, y - 5, 1, 3)
  love.graphics.rectangle("fill", x + 1, y + 3, 1, 3)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.rectangle("fill", x - 5, y, 3, 1)
  love.graphics.rectangle("fill", x + 3, y, 3, 1)
  love.graphics.rectangle("fill", x, y - 5, 1, 3)
  love.graphics.rectangle("fill", x, y + 3, 1, 3)
end

return hud
