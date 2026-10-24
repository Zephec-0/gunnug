-- The summit: the sky's way in. On the mountain's top (src.cavegen carveSummit) stands a walled chamber open to
-- the stars with four pedestals, one for each boss's glyph. Setting a glyph on its pedestal lights its
-- constellation in the sky behind. With all four lit, the chamber's roof falls away and a gust rises out of the
-- middle of the floor and throws whoever stands in it up into the sky, onto the island above (the way into
-- the Cloud Reaches).
--
-- A glyph stays with the hunter when it is set down (the pedestals are only lit again if a run is resumed).
local audio = require("src.audio")
local effects = require("src.effects")
local glyphs = require("src.glyphs")
local input = require("src.input")
local materials = require("src.materials")

local summit = {}

local world, S -- the world, and the chamber's geometry: cavegen's `summit` result
local placed, fade, phase, timer, gustT = {}, {}, "idle", 0, 0

local REACH_X, REACH_Y = 18, 34
local GUST_HALF = 46 -- half the gust's width
local RISE = -490 -- the speed it carries the hunter up at

function summit.clear()
  world, S = nil, nil
  placed, fade, phase, timer, gustT = {}, {}, "idle", 0, 0
end

function summit.setup(w, info)
  world, S = w, info
  placed, fade, phase, timer, gustT = {}, {}, "idle", 0, 0
end

function summit.active()
  return S ~= nil
end

-- The pedestal the hunter is standing at: its index, or nil
local function nearPedestal(px, py)
  if not S or phase ~= "idle" then
    return nil
  end
  for i, x in ipairs(S.pedestals) do
    if math.abs(px - x) < REACH_X and math.abs(py - (S.floorY - 10)) < REACH_Y then
      return i
    end
  end
  return nil
end

local function placedCount()
  local n = 0
  for i = 1, #glyphs.order do
    n = n + (placed[i] and 1 or 0)
  end
  return n
end

function summit.interact(player)
  if not S or player.dead then
    return false
  end
  local px, py = player:center()
  local i = nearPedestal(px, py)
  if not i then
    return false
  end
  local id = glyphs.order[i]
  local def = glyphs.defs[id]
  local x = S.pedestals[i]
  if placed[i] then
    return true
  end
  if not glyphs.has(id) then
    effects.popup(x, S.floorY - 40, "Needs the " .. def.name, { 0.85, 0.8, 0.95 })
    audio.play("deny")
    return true
  end
  placed[i] = true
  audio.play("buy")
  effects.ring(x, S.floorY - 24, 34, def.color)
  effects.popup(x, S.floorY - 40, def.name .. " set", def.color)
  for _ = 1, 14 do
    effects.particle(x, S.floorY - 24, (love.math.random() - 0.5) * 70, -20 - love.math.random() * 60, 0.8, def.color, -20, true)
  end
  if placedCount() >= #glyphs.order then
    phase, timer = "lit", 3.6
    effects.popup(S.cx, S.floorY - 70, "The sky remembers", { 1, 0.95, 0.75 })
  end
  return true
end

-- The roof falls away: nothing stands between the chamber and the heavens
local function openRoof()
  local r = S.roof
  for y = r.y0, r.y1 do
    for x = r.x0, r.x1 do
      world:setRaw(x, y, materials.AIR)
    end
  end
  world:repaintRegion(r.x0, r.y0, r.x1, r.y1)
  require("src.physics").rebuildRegion(r.x0, r.y0, r.x1, r.y1)
  audio.play("explosion", 1, 0.45)
  require("src.camera").shake(0.9)
  for _ = 1, 40 do
    effects.particle(r.x0 + love.math.random() * (r.x1 - r.x0), r.y1, (love.math.random() - 0.5) * 80, 20 + love.math.random() * 90, 1.2, { 0.9, 0.85, 0.7 }, 200, true)
  end
end

function summit.update(dt, player)
  if not S then
    return
  end
  for i = 1, #glyphs.order do
    fade[i] = math.min(1, (fade[i] or 0) + (placed[i] and dt / 1.2 or 0))
  end
  if phase == "lit" then
    timer = timer - dt
    if timer <= 0 then
      openRoof()
      phase, gustT = "gust", 0
      require("src.hud").showBanner("The Gust", "The heavens open")
    end
  elseif phase == "gust" then
    gustT = gustT + dt
    -- Wind streaming up out of the floor
    if love.math.random() < dt * 40 then
      effects.particle(S.cx + (love.math.random() * 2 - 1) * GUST_HALF, S.floorY - 4, (love.math.random() - 0.5) * 8, -260 - love.math.random() * 160, 1.1, { 0.8, 0.92, 1 }, 0, true)
    end
    if not player.dead then
      local b = player.body
      local px, py = player:center()
      local cut = S.landing.y + 470
      if math.abs(px - S.cx) < GUST_HALF and py < S.floorY + 6 and py > cut then
        -- Up and up (and gently toward the middle of it, so the flight stays inside the wind)
        b.vy = b.vy + (RISE - b.vy) * math.min(1, dt * 5)
        b.vx = b.vx + (S.cx - px) * 1.5 * dt
        player.jumping = false
        player.airJumps = require("src.perks").sum("airJumps")
      end
    end
  end
end

-- Drawing ------------------------------------------------------------------------------------------------

local STONE, STONE_L, STONE_D = { 0.30, 0.29, 0.36 }, { 0.42, 0.41, 0.50 }, { 0.17, 0.16, 0.21 }

local function R(c, a, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

local function offscreen(view, m)
  return view.x > S.x1 + m or view.x + view.w < S.x0 - m or view.y + view.h < S.top - m or view.y > S.floorY + m
end

function summit.draw(view)
  if not S or offscreen(view, 40) then
    return
  end
  for _, x in ipairs(S.pedestals) do
    local g = S.floorY
    R(STONE_D, 1, x - 8, g - 3, 16, 3)
    R(STONE, 1, x - 6, g - 14, 12, 11)
    R(STONE_L, 1, x - 6, g - 14, 3, 11)
    R(STONE_D, 1, x + 3, g - 14, 3, 11)
    R(STONE_L, 1, x - 8, g - 17, 16, 4)
    R({ 0.6, 0.6, 0.7 }, 1, x - 8, g - 17, 16, 1)
  end
end

-- A constellation for each glyph: points and the lines between them, in a box about 90 x 70
local SHAPES = {
  { { -42, 10 }, { -24, -20 }, { -2, -6 }, { 18, -30 }, { 38, -8 }, { 26, 24 }, edges = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 5 }, { 5, 6 }, { 3, 6 } } },
  { { -35, -25 }, { -8, -30 }, { 12, -12 }, { -6, 8 }, { -30, 20 }, { 34, 22 }, edges = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 5 }, { 3, 6 } } },
  { { -40, -5 }, { -15, -28 }, { 10, -20 }, { 36, -30 }, { 20, 0 }, { -4, 22 }, { -30, 26 }, edges = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 3, 5 }, { 5, 6 }, { 6, 7 } } },
  { { 0, -34 }, { -26, -10 }, { -34, 20 }, { 0, 6 }, { 34, 20 }, { 26, -10 }, edges = { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 5 }, { 5, 6 }, { 6, 1 }, { 4, 1 } } },
}

function summit.drawEmissive(view)
  if not S or offscreen(view, 40) then
    return
  end
  local t = love.timer.getTime()
  -- The runes over the pedestals: dark until their glyph is set, then lit
  for i, x in ipairs(S.pedestals) do
    glyphs.draw(glyphs.order[i], x - 3, S.floorY - 30, 1, placed[i] and 1 or 0.14)
  end
  -- The constellations, in the sky behind (only inside the chamber, over its backdrop)
  local ys = { S.floorY - 150, S.floorY - 105, S.floorY - 105, S.floorY - 150 }
  local all = phase ~= "idle" and 1.35 or 1
  love.graphics.setBlendMode("add")
  for i, x in ipairs(S.pedestals) do
    local k = (fade[i] or 0) * all
    if k > 0 then
      local c = glyphs.defs[glyphs.order[i]].color
      local shape = SHAPES[i]
      local cx, cy = x, ys[i]
      love.graphics.setColor(c[1], c[2], c[3], 0.07 * k)
      love.graphics.circle("fill", cx, cy, 52)
      love.graphics.setLineWidth(1)
      love.graphics.setColor(c[1], c[2], c[3], 0.5 * k)
      for _, e in ipairs(shape.edges) do
        local a, b = shape[e[1]], shape[e[2]]
        love.graphics.line(cx + a[1], cy + a[2], cx + b[1], cy + b[2])
      end
      for n, p in ipairs(shape) do
        local tw = 0.75 + 0.25 * math.sin(t * 2.4 + n * 1.7 + i)
        love.graphics.setColor(c[1], c[2], c[3], 0.28 * k * tw)
        love.graphics.circle("fill", cx + p[1], cy + p[2], 5)
        love.graphics.setColor(1, 1, 1, math.min(1, 0.9 * k) * tw)
        love.graphics.rectangle("fill", math.floor(cx + p[1]) - 1, math.floor(cy + p[2]), 3, 1)
        love.graphics.rectangle("fill", math.floor(cx + p[1]), math.floor(cy + p[2]) - 1, 1, 3)
      end
    end
  end
  -- The gust: pale streaks climbing the middle of the chamber and on up out of it
  if phase == "gust" then
    local top = S.landing.y + 430
    local a = math.min(1, gustT / 1.5)
    for k = 0, 9 do
      local h = S.floorY - top
      local y = S.floorY - ((t * 300 + k * h / 10) % h)
      local x = S.cx + math.sin(k * 2.3 + t * 1.6) * (GUST_HALF - 10)
      love.graphics.setColor(0.75, 0.9, 1, 0.22 * a)
      love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 26)
      love.graphics.setColor(1, 1, 1, 0.12 * a)
      love.graphics.rectangle("fill", math.floor(x) - 1, math.floor(y), 3, 18)
    end
    love.graphics.setColor(0.6, 0.8, 1, 0.07 * a)
    love.graphics.rectangle("fill", S.cx - GUST_HALF, top, GUST_HALF * 2, S.floorY - top)
  end
  love.graphics.setBlendMode("alpha")
end

function summit.addLights(lighting, view)
  if not S or offscreen(view, 120) then
    return
  end
  for i, x in ipairs(S.pedestals) do
    if placed[i] then
      local c = glyphs.defs[glyphs.order[i]].color
      lighting.add(x, S.floorY - 24, 60, c[1], c[2], c[3], 0.5 * (fade[i] or 0))
    end
  end
  if phase == "gust" then
    lighting.add(S.cx, S.floorY - 40, 150, 0.6, 0.8, 1, 0.55)
  end
end

local function prompt(font, toScreen, wx, wy, text)
  local sx, sy = toScreen(wx, wy)
  love.graphics.setFont(font)
  local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy - font:getHeight())
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(1, 0.88, 0.6)
  love.graphics.print(text, x, y)
end

function summit.drawScreen(toScreen, font, player)
  if not S or player.dead then
    return
  end
  local px, py = player:center()
  local i = nearPedestal(px, py)
  if i and not placed[i] then
    local id = glyphs.order[i]
    local key = "[" .. input.label("interact") .. "] "
    prompt(font, toScreen, S.pedestals[i], S.floorY - 40, key .. (glyphs.has(id) and ("Set the " .. glyphs.defs[id].name) or ("A pedestal for the " .. glyphs.defs[id].name)))
  end
end

return summit
