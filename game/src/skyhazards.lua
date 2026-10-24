-- What the Cloud Reaches does to the hunter that is not a monster (placeholder art and sounds):
--   gust vents   permanent updraft columns on the islands and over the drops (like the summit's gust): shortcuts up
--                the climb, loot islands at their tops, and traps that throw a jumper into the air
--   lightning    telegraphed strikes in the upper bands: a glow and sparks on the spot, then a bolt a moment later
--   bells        hung from the ruins' lintels; they ring when he brushes past
--   the wreck    the secret: its mast pokes out of the sea floor with a lamp on it; its chest is inside
-- (the wind spirits' gales are in src.skymobs)
local audio = require("src.audio")
local effects = require("src.effects")

local skyhazards = {}

local world, S
local strikes, strikeTimer = {}, 8
local bellT = {}
local inVent = false

local RISE = -250 -- the speed a vent carries him up at
local VENT_RANGE = 700 -- vents further than this from the hunter are not worked

function skyhazards.clear()
  world, S = nil, nil
  strikes, strikeTimer, bellT, inVent = {}, 8, {}, false
end

-- A strike called by something else (a storm cloud): on the ground under x, with the usual warning
function skyhazards.queueStrike(x, fromY)
  if not S or not world then
    return
  end
  local y = world:findGround(math.floor(x), math.floor(fromY))
  if y < fromY + 700 then
    strikes[#strikes + 1] = { x = math.floor(x), y = y, t = 0, warn = 1.3 }
  end
end

function skyhazards.setup(w, info)
  world, S = w, info
  strikes, strikeTimer, bellT, inVent = {}, 8, {}, false
end

local function R(c, a, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

-- Lightning ---------------------------------------------------------------------------------------------------

-- How often it strikes where the hunter is: never in the Cloud Sea, seldom in the Ruins, often in the Star Fields
local function interval(x)
  if x >= S.bands.x2 then
    return x >= S.bands.x1 and nil or (11 + love.math.random() * 6)
  end
  return 4 + love.math.random() * 3
end

local function newStrike(px, py)
  for _ = 1, 8 do
    -- half the time on the island he is crossing, a little ahead of him; otherwise somewhere near
    local x = math.floor(px + (love.math.random() < 0.5 and (love.math.random() - 0.5) * 60 or (love.math.random() - 0.5) * 340))
    local y = world:findGround(x, math.floor(py - 120))
    if y < py + 260 and y > py - 200 then
      return { x = x, y = y, t = 0, warn = 1.5, bolt = nil }
    end
  end
  return nil
end

local function jag(x, y0, y1, seed)
  local pts = { x, y0 }
  local n = 14
  for i = 1, n - 1 do
    local f = i / n
    local s = math.sin(seed * 12.9898 + i * 78.233) * 43758.5453
    s = s - math.floor(s)
    pts[#pts + 1] = x + (s - 0.5) * 26 * (1 - f * 0.5)
    pts[#pts + 1] = y0 + (y1 - y0) * f
  end
  pts[#pts + 1] = x
  pts[#pts + 1] = y1
  return pts
end

-- How strong the sparks are before a strike (0-1): they build for two thirds of the warning, then die away to nothing
function skyhazards.tellLevel(s)
  local f = s.t / s.warn
  if f < 0.68 then
    return (f / 0.68) ^ 1.5
  elseif f < 0.9 then
    return 1 - (f - 0.68) / 0.22
  end
  return 0
end

local function updateLightning(dt, player)
  local px, py = player:center()
  if player.dead then
    return
  end
  local onRoute = py < S.floorTop - 90 and require("src.enemies").skyFight() < 0.3 -- (not down on the sea floor, nor in the wreck, nor during the Champion's fight)
  local wait = onRoute and interval(px)
  strikeTimer = strikeTimer - dt
  if strikeTimer <= 0 then
    strikeTimer = wait or 6
    if wait then
      local s = newStrike(px, py)
      if s then
        strikes[#strikes + 1] = s
      end
    end
  end
  for i = #strikes, 1, -1 do
    local s = strikes[i]
    s.t = s.t + dt
    if not s.bolt then
      -- the warning: sparks start at the spot, grow, die away, and then it strikes
      local k = skyhazards.tellLevel(s)
      if love.math.random() < dt * (k * 70) then
        effects.particle(s.x + (love.math.random() - 0.5) * 10, s.y - 2, (love.math.random() - 0.5) * 70, -30 - love.math.random() * 70, 0.3 + love.math.random() * 0.2, { 0.8, 0.9, 1 }, 220, true)
      end
      if s.t > 0.3 and not s.ticked then
        s.ticked = true
        audio.playAt("wisp_crackle", s.x, s.y, 0.7, 1.6)
      end
      if s.t >= s.warn then
        s.bolt = 0.28
        s.pts = jag(s.x, s.y - 760, s.y, s.x * 0.13 + s.t)
        audio.playAt("explosion", s.x, s.y, 0.7, 1.6)
        audio.playAt("jelly_zap", s.x, s.y, 1, 0.6)
        require("src.camera").shake(0.35)
        if not player.dead and math.abs(px - s.x) < 22 and math.abs(py - s.y) < 70 then
          player:hurt(26, s.x, s.y, "lightning")
        end
        require("src.enemies").damageArea(s.x, s.y - 10, 30, 40, 120)
        for _ = 1, 14 do
          effects.particle(s.x, s.y - 2, (love.math.random() - 0.5) * 160, -30 - love.math.random() * 120, 0.5, { 0.85, 0.92, 1 }, 300, true)
        end
      end
    else
      s.bolt = s.bolt - dt
      if s.bolt <= 0 then
        table.remove(strikes, i)
      end
    end
  end
end

-- Update ---------------------------------------------------------------------------------------------------------

function skyhazards.update(dt, player)
  if not S or player.dead then
    return
  end
  local px, py = player:center()
  local b = player.body
  local inside = false
  for _, v in ipairs(S.vents) do
    if math.abs(px - v.x) < VENT_RANGE then
      local top = v.y - v.h
      if love.math.random() < dt * 6 then
        effects.particle(v.x + (love.math.random() * 2 - 1) * (v.half - 4), v.y - 2, 0, -150 - love.math.random() * 90, 0.9, { 0.8, 0.92, 1 }, 0, true)
      end
      if math.abs(px - v.x) < v.half and py < v.y + 4 and py > top then
        inside = true
        b.vy = b.vy + (RISE - b.vy) * math.min(1, dt * 4)
        player.jumping = false
        player.airJumps = require("src.perks").sum("airJumps")
      end
    end
  end
  if inside and not inVent then
    audio.play("gust_blast", 0.3, 1.3)
  end
  inVent = inside
  updateLightning(dt, player)
  -- bells
  for i, bell in ipairs(S.bells) do
    bellT[i] = math.max(0, (bellT[i] or 0) - dt)
    if bellT[i] <= 0 and math.abs(px - bell.x) < 10 and math.abs(py - (bell.y + 10)) < 22 then
      bellT[i] = 1.2
      bell.swing = 1
      audio.playAt("bell", bell.x, bell.y, 0.8, 0.8 + (i % 5) * 0.12)
    end
    if bell.swing then
      bell.swing = math.max(0, bell.swing - dt * 0.6)
    end
  end
end

-- Drawing ----------------------------------------------------------------------------------------------------------

local function inView(view, x, y, m)
  return x > view.x - m and x < view.x + view.w + m and y > view.y - m and y < view.y + view.h + m
end

function skyhazards.draw(view)
  if not S then
    return
  end
  local t = love.timer.getTime()
  for _, v in ipairs(S.vents) do
    if v.x > view.x - 40 and v.x < view.x + view.w + 40 and v.y > view.y - 20 and v.y - v.h < view.y + view.h then
      -- a worn stone ring round the vent's mouth
      R({ 0.55, 0.58, 0.66 }, 1, v.x - v.half - 2, v.y - 2, 4, 3)
      R({ 0.55, 0.58, 0.66 }, 1, v.x + v.half - 2, v.y - 2, 4, 3)
      R({ 0.85, 0.9, 1 }, 1, v.x - v.half - 2, v.y - 2, 4, 1)
      R({ 0.85, 0.9, 1 }, 1, v.x + v.half - 2, v.y - 2, 4, 1)
    end
  end
  -- the ruins: columns and lintels to walk through (scenery only)
  for _, col in ipairs(S.columns or {}) do
    if inView(view, col.x, col.top, 80) then
      R({ 0.30, 0.29, 0.36 }, 1, col.x - 2, col.top, 5, col.base - col.top)
      R({ 0.42, 0.41, 0.50 }, 1, col.x - 2, col.top, 2, col.base - col.top)
      R({ 0.17, 0.16, 0.21 }, 1, col.x + 2, col.top, 1, col.base - col.top)
      R({ 0.42, 0.41, 0.50 }, 1, col.x - 3, col.top - 1, 7, 2)
    end
  end
  for _, l in ipairs(S.ruins or {}) do
    if inView(view, l.x0, l.y, 80) then
      R({ 0.30, 0.29, 0.36 }, 1, l.x0, l.y, l.x1 - l.x0 + 1, 3)
      R({ 0.42, 0.41, 0.50 }, 1, l.x0, l.y, l.x1 - l.x0 + 1, 1)
    end
  end
  for i, bell in ipairs(S.bells) do
    if inView(view, bell.x, bell.y, 20) then
      local sw = math.sin(t * 7 + i) * (bell.swing or 0) * 2.5
      love.graphics.setColor(0.35, 0.28, 0.12)
      love.graphics.line(bell.x, bell.y - 3, bell.x + sw * 0.5, bell.y)
      R({ 0.82, 0.62, 0.2 }, 1, bell.x - 3 + sw, bell.y, 7, 2)
      R({ 0.82, 0.62, 0.2 }, 1, bell.x - 4 + sw, bell.y + 2, 9, 3)
      R({ 1, 0.88, 0.5 }, 1, bell.x - 3 + sw, bell.y, 2, 4)
      R({ 0.3, 0.22, 0.08 }, 1, bell.x + sw, bell.y + 5, 1, 1)
    end
  end
  local w = S.wreck
  if w and inView(view, w.x, w.mastTop, 60) then
    -- a tattered pennant on the mast's tip
    for i = 0, 9 do
      R({ 0.75, 0.62, 0.35 }, 0.85, w.x + 2 + i, w.mastTop + 2 + math.floor(math.sin(t * 4 - i * 0.6) * 1.5 + 0.5) + math.floor(i / 3), 1, math.max(1, 5 - math.floor(i / 2)))
    end
  end
end

function skyhazards.drawEmissive(view)
  if not S then
    return
  end
  local t = love.timer.getTime()
  love.graphics.setBlendMode("add")
  for _, v in ipairs(S.vents) do
    if v.x > view.x - 40 and v.x < view.x + view.w + 40 and v.y > view.y - 20 and v.y - v.h < view.y + view.h then
      local h = v.h
      for k = 0, 8 do
        local y = v.y - ((t * 150 + k * h / 9) % h)
        local x = v.x + math.sin(k * 2.3 + t * 1.6) * (v.half - 8)
        love.graphics.setColor(0.75, 0.9, 1, 0.2 * (1 - (v.y - y) / h * 0.6))
        love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 18)
        love.graphics.setColor(1, 1, 1, 0.1)
        love.graphics.rectangle("fill", math.floor(x) - 1, math.floor(y), 3, 12)
      end
      love.graphics.setColor(0.6, 0.8, 1, 0.045)
      love.graphics.rectangle("fill", v.x - v.half, v.y - h, v.half * 2, h)
    end
  end
  for _, s in ipairs(strikes) do
    if inView(view, s.x, s.y, 60) or (s.pts and s.x > view.x - 60 and s.x < view.x + view.w + 60) then
      if not s.bolt then
        -- the warning: sparks spitting from the spot, more of them as it builds, gone just before the strike
        local k = skyhazards.tellLevel(s)
        local n = math.floor(k * 22)
        for i = 1, n do
          local ph = (t * 3.1 + i * 0.37) % 1
          local sd = math.sin(i * 12.9898) * 43758.5453
          sd = sd - math.floor(sd)
          local x = s.x + (sd - 0.5) * 16 * (0.3 + ph)
          local y = s.y - 1 - ph * (10 + sd * 16) + ph * ph * 14
          love.graphics.setColor(0.85, 0.93, 1, (1 - ph) * math.min(1, k * 1.5))
          love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 1)
          if sd > 0.6 then
            love.graphics.setColor(1, 1, 1, (1 - ph) * k)
            love.graphics.rectangle("fill", math.floor(x), math.floor(y) - 1, 1, 2)
          end
        end
        love.graphics.setColor(0.7, 0.85, 1, 0.25 * k)
        love.graphics.rectangle("fill", math.floor(s.x) - 2, math.floor(s.y) - 2, 5, 2)
      else
        local a = math.min(1, s.bolt / 0.15)
        love.graphics.setLineWidth(5)
        love.graphics.setColor(0.5, 0.65, 1, 0.3 * a)
        love.graphics.line(s.pts)
        love.graphics.setLineWidth(2)
        love.graphics.setColor(0.85, 0.92, 1, 0.9 * a)
        love.graphics.line(s.pts)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, a)
        love.graphics.line(s.pts)
        love.graphics.setColor(0.8, 0.9, 1, 0.5 * a)
        love.graphics.circle("fill", s.x, s.y, 22)
      end
    end
  end
  local w = S.wreck
  if w and inView(view, w.x, w.mastTop, 80) then
    love.graphics.setColor(1, 0.8, 0.45, 0.6 + 0.2 * math.sin(t * 3))
    love.graphics.rectangle("fill", math.floor(w.lamp[1]) - 1, math.floor(w.lamp[2]) - 1, 3, 3)
    love.graphics.setColor(1, 0.8, 0.45, 0.12)
    love.graphics.circle("fill", w.lamp[1], w.lamp[2], 9)
  end
  love.graphics.setBlendMode("alpha")
  love.graphics.setLineWidth(1)
end

function skyhazards.addLights(lighting, view)
  if not S then
    return
  end
  for _, v in ipairs(S.vents) do
    if v.x > view.x - 120 and v.x < view.x + view.w + 120 and v.y > view.y - 20 and v.y - v.h < view.y + view.h + 60 then
      lighting.add(v.x, v.y - v.h * 0.4, 52, 0.6, 0.8, 1, 0.22)
    end
  end
  for _, s in ipairs(strikes) do
    if inView(view, s.x, s.y, 200) then
      if s.bolt then
        lighting.add(s.x, s.y - 40, 190, 0.75, 0.85, 1, 1.0 * math.min(1, s.bolt / 0.15))
      else
        lighting.add(s.x, s.y - 6, 34, 0.7, 0.85, 1, 0.5 * skyhazards.tellLevel(s))
      end
    end
  end
  local w = S.wreck
  if w and inView(view, w.x, w.mastTop, 160) then
    lighting.add(w.lamp[1], w.lamp[2], 60, 1, 0.75, 0.4, 0.5 + 0.05 * math.sin(love.timer.getTime() * 3))
    lighting.add(w.chest[1], w.chest[2] - 12, 44, 1, 0.75, 0.4, 0.3)
  end
end

-- The wreck's chest: a fine weapon, something locked, and a good deal of gold ------------------------------------

function skyhazards.openWreckChest(c)
  local meta = require("src.meta")
  local pickups = require("src.pickups")
  local guns = require("src.guns")
  pickups.dropWeapon(c.x, c.y - 12, guns.generate(meta.lockedArchetype(), nil, 0.9), -30, -150)
  pickups.dropItem(c.x + 4, c.y - 12, meta.lockedItem() or require("src.items").random(), 30, -140)
  pickups.dropGold(c.x, c.y - 10, 220)
  effects.popup(c.x, c.y - 30, "The wreck's hold", { 1, 0.85, 0.45 })
end

return skyhazards
