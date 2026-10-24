-- The summit: the sky's way in. The mountain's top (src.cavegen, the Needle's cap) is flat and bare but for four
-- pedestals, one for each boss's glyph. Setting a glyph on its pedestal lights its constellation in the sky above:
-- the glyph's own rune, writ large in stars. With all four lit, a gust rises out of the middle of the top and
-- throws whoever stands in it up through the gap to the Cloud Reaches, through the hole in their cloud floor.
--
-- A glyph stays with the hunter when it is set down (the pedestals are only lit again if a run is resumed).
local audio = require("src.audio")
local effects = require("src.effects")
local glyphs = require("src.glyphs")
local input = require("src.input")

local summit = {}

local world, S -- the world, and the top's geometry: cavegen's `summit` result { cx, floorY, pedestals }
local placed, fade, phase, timer, gustT = {}, {}, "idle", 0, 0

local REACH_X, REACH_Y = 18, 34
local GUST_HALF = 46 -- half the gust's width
local RISE = -520 -- the speed it carries the hunter up at
local LET_GO = 140 -- how far below the sky's cloud floor the wind lets go of him: he flies on through the hole and clear of it

function summit.clear()
  world, S = nil, nil
  placed, fade, phase, timer, gustT = {}, {}, "idle", 0, 0
end

function summit.setup(w, info)
  world, S = w, info
  placed, fade, phase, timer, gustT = {}, {}, "idle", 0, 0
end

-- Where the gust ends: the top of the sky's cloud floor, and the hole in it
local function skyFloor()
  local band = require("src.scenes.catacombs").spaceBand()
  return band and band.y1 - 200 or S.floorY - 1100
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
  if placed[i] then
    return true
  end
  local id = glyphs.order[i]
  if not glyphs.has(id) then
    audio.play("deny")
    return true
  end
  local color = glyphs.defs[id].color
  local x = S.pedestals[i]
  placed[i] = true
  audio.play("buy")
  effects.ring(x, S.floorY - 24, 34, color)
  for _ = 1, 14 do
    effects.particle(x, S.floorY - 24, (love.math.random() - 0.5) * 70, -20 - love.math.random() * 60, 0.8, color, -20, true)
  end
  if placedCount() >= #glyphs.order then
    phase, timer = "lit", 3.2
  end
  return true
end

function summit.update(dt, player)
  if not S then
    return
  end
  for i = 1, #glyphs.order do
    fade[i] = math.min(1, (fade[i] or 0) + (placed[i] and dt / 1.4 or 0))
  end
  if phase == "lit" then
    timer = timer - dt
    if timer <= 0 then
      phase, gustT = "gust", 0
      audio.play("explosion", 0.8, 0.5)
      require("src.camera").shake(0.6)
    end
  elseif phase == "gust" then
    gustT = gustT + dt
    local top = skyFloor()
    -- Wind streaming up out of the ground
    if love.math.random() < dt * 50 then
      effects.particle(S.cx + (love.math.random() * 2 - 1) * GUST_HALF, S.floorY - 4, (love.math.random() - 0.5) * 8, -300 - love.math.random() * 200, 1.4, { 0.8, 0.92, 1 }, 0, true)
    end
    if not player.dead then
      local b = player.body
      local px, py = player:center()
      if math.abs(px - S.cx) < GUST_HALF and py < S.floorY + 6 and py > top + LET_GO then
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
  return view.x > S.pedestals[4] + 160 + m or view.x + view.w < S.pedestals[1] - 160 - m or view.y + view.h < S.floorY - 260 - m or view.y > S.floorY + m
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

-- Each glyph's constellation is its rune enlarged: a star at every end, corner and crossing of its strokes,
-- and a line along each stroke between them. Built once from the rune (7 x 7 cells)
local CELL = 13 -- pixels to a cell of the rune
local shapes = {}

local function buildShape(rune)
  local at = {}
  for r = 1, 7 do
    for c = 1, 7 do
      if rune[r]:sub(c, c) == "#" then
        at[r * 10 + c] = true
      end
    end
  end
  local function has(c, r)
    return at[r * 10 + c] == true
  end
  local edges, degree, dirs = {}, {}, {}
  local function link(c0, r0, c1, r1)
    edges[#edges + 1] = { c0, r0, c1, r1 }
    for _, p in ipairs({ { c0, r0, c1 - c0, r1 - r0 }, { c1, r1, c0 - c1, r0 - r1 } }) do
      local k = p[2] * 10 + p[1]
      degree[k] = (degree[k] or 0) + 1
      dirs[k] = dirs[k] or {}
      dirs[k][#dirs[k] + 1] = { p[3], p[4] }
    end
  end
  for r = 1, 7 do
    for c = 1, 7 do
      if has(c, r) then
        if has(c + 1, r) then
          link(c, r, c + 1, r)
        end
        if has(c, r + 1) then
          link(c, r, c, r + 1)
        end
        -- a diagonal step only where it is not already a corner of orthogonal cells
        if has(c + 1, r + 1) and not has(c + 1, r) and not has(c, r + 1) then
          link(c, r, c + 1, r + 1)
        end
        if has(c - 1, r + 1) and not has(c - 1, r) and not has(c, r + 1) then
          link(c, r, c - 1, r + 1)
        end
      end
    end
  end
  local stars = {}
  for r = 1, 7 do
    for c = 1, 7 do
      local k = r * 10 + c
      if has(c, r) then
        local d = degree[k] or 0
        local keep = d ~= 2
        if d == 2 then
          local a, b = dirs[k][1], dirs[k][2]
          keep = not (a[1] == -b[1] and a[2] == -b[2]) -- a bend, not a straight run
        end
        if keep then
          stars[#stars + 1] = { (c - 4) * CELL, (r - 4) * CELL }
        end
      end
    end
  end
  local lines = {}
  for _, e in ipairs(edges) do
    lines[#lines + 1] = { (e[1] - 4) * CELL, (e[2] - 4) * CELL, (e[3] - 4) * CELL, (e[4] - 4) * CELL }
  end
  return { stars = stars, lines = lines }
end

local function shape(i)
  if not shapes[i] then
    shapes[i] = buildShape(glyphs.defs[glyphs.order[i]].rune)
  end
  return shapes[i]
end

-- Where each constellation hangs: over its pedestal
local function skyPos(i)
  return S.pedestals[i], S.floorY - 100
end

function summit.drawEmissive(view)
  if not S or offscreen(view, 60) then
    return
  end
  local t = love.timer.getTime()
  -- The runes over the pedestals, dim until their glyph is set
  for i, x in ipairs(S.pedestals) do
    glyphs.draw(glyphs.order[i], x - 3, S.floorY - 30, 1, 0.3 + 0.7 * (fade[i] or 0))
  end
  love.graphics.setBlendMode("add")
  local all = phase ~= "idle" and 1.25 or 1
  for i = 1, #S.pedestals do
    local k = (fade[i] or 0) * all
    if k > 0 then
      local c = glyphs.defs[glyphs.order[i]].color
      local sh = shape(i)
      local cx, cy = skyPos(i)
      love.graphics.setLineWidth(1)
      for _, l in ipairs(sh.lines) do
        love.graphics.setColor(c[1], c[2], c[3], 0.28 * k)
        love.graphics.line(cx + l[1], cy + l[2], cx + l[3], cy + l[4])
        love.graphics.setColor(1, 1, 1, 0.22 * k)
        love.graphics.line(cx + l[1] + 0.5, cy + l[2] + 0.5, cx + l[3] + 0.5, cy + l[4] + 0.5)
      end
      for n, p in ipairs(sh.stars) do
        local tw = 0.7 + 0.3 * math.sin(t * 2.6 + n * 1.9 + i * 0.7)
        local sx, sy = cx + p[1], cy + p[2]
        love.graphics.setColor(c[1], c[2], c[3], 0.06 * k * tw)
        love.graphics.circle("fill", sx, sy, 15)
        love.graphics.setColor(c[1], c[2], c[3], 0.2 * k * tw)
        love.graphics.circle("fill", sx, sy, 7)
        love.graphics.setColor(1, 1, 1, math.min(1, 0.95 * k) * tw)
        love.graphics.rectangle("fill", math.floor(sx) - 2, math.floor(sy), 5, 1)
        love.graphics.rectangle("fill", math.floor(sx), math.floor(sy) - 2, 1, 5)
        love.graphics.rectangle("fill", math.floor(sx) - 1, math.floor(sy) - 1, 3, 3)
      end
    end
  end
  -- The gust: pale streaks climbing the middle of the top and on up toward the sky
  if phase == "gust" then
    local top = skyFloor()
    local a = math.min(1, gustT / 1.5)
    local h = S.floorY - top
    for k = 0, 17 do
      local y = S.floorY - ((t * 320 + k * h / 18) % h)
      local x = S.cx + math.sin(k * 2.3 + t * 1.6) * (GUST_HALF - 10)
      love.graphics.setColor(0.75, 0.9, 1, 0.22 * a)
      love.graphics.rectangle("fill", math.floor(x), math.floor(y), 1, 26)
      love.graphics.setColor(1, 1, 1, 0.12 * a)
      love.graphics.rectangle("fill", math.floor(x) - 1, math.floor(y), 3, 18)
    end
    love.graphics.setColor(0.6, 0.8, 1, 0.06 * a)
    love.graphics.rectangle("fill", S.cx - GUST_HALF, top, GUST_HALF * 2, h)
  end
  love.graphics.setBlendMode("alpha")
end

-- The stars are lights: each throws its glyph's colour on the ground, the pedestals and whoever stands there
function summit.addLights(lighting, view)
  if not S or offscreen(view, 160) then
    return
  end
  local t = love.timer.getTime()
  for i = 1, #S.pedestals do
    local k = fade[i] or 0
    if k > 0 then
      local c = glyphs.defs[glyphs.order[i]].color
      local cx, cy = skyPos(i)
      for n, p in ipairs(shape(i).stars) do
        local tw = 0.75 + 0.25 * math.sin(t * 2.6 + n * 1.9 + i * 0.7)
        lighting.add(cx + p[1], cy + p[2], 62, c[1], c[2], c[3], 0.5 * k * tw * (phase ~= "idle" and 1.3 or 1), true)
      end
      lighting.add(S.pedestals[i], S.floorY - 24, 56, c[1], c[2], c[3], 0.55 * k)
    end
  end
  if phase == "gust" then
    lighting.add(S.cx, S.floorY - 50, 160, 0.6, 0.8, 1, 0.6)
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

-- Only the key: the pedestals say nothing else
function summit.drawScreen(toScreen, font, player)
  if not S or player.dead then
    return
  end
  local px, py = player:center()
  local i = nearPedestal(px, py)
  if i and not placed[i] then
    prompt(font, toScreen, S.pedestals[i], S.floorY - 40, "[" .. input.label("interact") .. "]")
  end
end

return summit
