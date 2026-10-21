-- Scenery of the Catacombs' old mine (design doc §7b), drawn behind the hunter
-- from the lists cavegen makes (info.mine): rail tracks, timber shoring that
-- stands, is half fallen or has collapsed, hanging oil lanterns and lamp posts,
-- skeletal remains and pickaxes. The flames are drawn again after the
-- lighting, and every lantern gives light.
local minedecor = {}
local bake = require("src.bake")

local WOOD, WOOD_L, WOOD_D = { 0.45, 0.30, 0.16 }, { 0.62, 0.43, 0.22 }, { 0.28, 0.19, 0.10 }
local IRON, IRON_L, IRON_D = { 0.38, 0.39, 0.45 }, { 0.62, 0.63, 0.70 }, { 0.20, 0.20, 0.25 }
local BONE, BONE_D = { 0.80, 0.77, 0.66 }, { 0.52, 0.49, 0.42 }
local DARK = { 0.08, 0.07, 0.09 }

local function R(c, x, y, w, h, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", x, y, w, h)
end

local function flicker(seed)
  local t = love.timer.getTime()
  return math.sin(t * 9 + seed) * 0.5 + math.sin(t * 23 + seed * 2) * 0.5
end

-- Tracks ----------------------------------------------------------------------

local function trackRange(t, xa, xb)
  for x = xa, xb do
    local y = t.ys[x]
    if y and not (t.cut and t.cut[x]) then
      if (x - t.x0) % 7 == 3 then
        R(WOOD_D, x - 1, y - 1, 3, 2) -- a sleeper
        R(WOOD, x - 1, y - 1, 3, 1)
      end
      R(IRON, x, y - 3, 1, 2) -- the rail
      R(IRON_L, x, y - 3, 1, 1)
      if (x - t.x0) % 7 == 3 then
        R(IRON_D, x, y - 2, 1, 1) -- a spike
      end
    end
  end
end

local TRACK_PIECE = 256 -- (a long track is baked in pieces of this many pixels)

-- (only the stretch in view: a long track is thousands of pixels)
local function drawTrack(t, view)
  local xa, xb = math.max(t.x0, math.floor(view.x) - 4), math.min(t.x1, math.ceil(view.x + view.w) + 4)
  if bake.enabled.minedecor then
    t.boxes = t.boxes or {}
    for k = math.floor((xa - t.x0) / TRACK_PIECE), math.floor((xb - t.x0) / TRACK_PIECE) do
      local ca, cb = t.x0 + k * TRACK_PIECE, math.min(t.x1, t.x0 + k * TRACK_PIECE + TRACK_PIECE - 1)
      local box = t.boxes[k]
      if box == nil then
        local lo, hi
        for x = ca, cb do
          local y = t.ys[x]
          if y then
            lo, hi = lo and math.min(lo, y) or y, hi and math.max(hi, y) or y
          end
        end
        box = lo and { lo - 4, hi - lo + 6 } or false
        t.boxes[k] = box
      end
      if box then
        -- (two pixels of room each side: a sleeper is three wide)
        bake.piece(t, k, t.ver or 1, ca - 2, box[1], cb - ca + 5, box[2], function()
          trackRange(t, ca, cb)
        end)
      end
    end
  else
    trackRange(t, xa, xb)
  end
  -- A buffer stop at the far end
  local y = t.ys[t.x1]
  if not (t.cut and t.cut[t.x1]) then
    R(WOOD_D, t.x1, y - 7, 2, 7)
    R(WOOD, t.x1 - 2, y - 7, 5, 2)
    R(WOOD_L, t.x1 - 2, y - 7, 5, 1)
  end
end

-- Timber ----------------------------------------------------------------------

local function post(x, top, bottom, seed)
  local h = bottom - top
  if h <= 0 then
    return
  end
  R(WOOD, x - 1, top, 3, h)
  R(WOOD_L, x - 1, top, 1, h)
  R(WOOD_D, x + 1, top, 1, h)
  -- Knots and cracks
  for k = 0, 2 do
    local ky = top + 4 + (seed * 7 + k * 13) % math.max(1, h - 6)
    R(WOOD_D, x - 1 + (seed + k) % 2, ky, 1, 2)
  end
  R(WOOD_D, x - 2, bottom - 1, 5, 1) -- the foot
end

local function splinters(x, y, seed)
  R(WOOD, x - 1, y, 3, 2)
  R(WOOD_L, x - 1, y - 1 - seed % 2, 1, 2)
  R(WOOD, x + 1, y - 2 - (seed + 1) % 3, 1, 3)
  R(WOOD_D, x, y - 1, 1, 1)
end

local function drawSupport(s)
  local x1, x2 = s.x, s.x + s.gap
  local c = s.c
  if s.state == "standing" then
    post(x1, c, s.g1, s.seed)
    post(x2, c, s.g2, s.seed + 3)
    -- Cap beam with braces down to each post
    R(WOOD, x1 - 4, c, s.gap + 9, 3)
    R(WOOD_L, x1 - 4, c, s.gap + 9, 1)
    R(WOOD_D, x1 - 4, c + 2, s.gap + 9, 1)
    for i = 0, 4 do
      R(WOOD_D, x1 + 2 + i, c + 3 + i, 1, 1)
      R(WOOD_D, x2 - 2 - i, c + 3 + i, 1, 1)
    end
  elseif s.state == "broken" then
    -- One post has snapped; the beam hangs from the other, its far end dropped
    local whole, snapped = s.side == 1 and x1 or x2, s.side == 1 and x2 or x1
    local gWhole, gSnapped = s.side == 1 and s.g1 or s.g2, s.side == 1 and s.g2 or s.g1
    post(whole, c, gWhole, s.seed)
    local topSnap = gSnapped - s.breakH
    post(snapped, topSnap, gSnapped, s.seed + 3)
    splinters(snapped, topSnap, s.seed)
    -- The beam, slanting from the standing post down to the broken one
    local dirx = s.side == 1 and 1 or -1
    local drop = math.max(4, topSnap - c - 4)
    for i = -4, s.gap + 4 do
      local k = (s.side == 1 and (i + 4) or (s.gap + 4 - i)) / (s.gap + 8)
      local y = c + math.floor(k * drop)
      R(WOOD, x1 + i, y, 1, 3)
      R(WOOD_L, x1 + i, y, 1, 1)
    end
    -- Splinters and planks on the ground
    R(WOOD_D, snapped - dirx * 4, gSnapped - 2, 3, 2)
    R(WOOD, snapped + dirx * 3, gSnapped - 1, 5, 1)
  else
    -- Collapsed: the posts lie where they fell, the beam across them
    local g = math.max(s.g1, s.g2)
    R(WOOD_D, x1 - 5, g - 2, s.gap + 12, 2)
    R(WOOD, x1 - 5, g - 3, s.gap + 12, 1)
    R(WOOD, x1 - 3, g - 5, 9, 2)
    R(WOOD_L, x1 - 3, g - 5, 9, 1)
    splinters(x1 + s.gap + 5, g - 2, s.seed)
    R(WOOD_D, x1 + 3, g - 6, 4, 1)
  end
end

-- Oil lanterns ------------------------------------------------------------------

local function drawLamp(l)
  if l.broken then
    -- what is left: the chain, or the post and its arm
    if l.hung then
      R(IRON_D, math.floor(l.x), l.y - 8 - (l.rope or 0), 1, 5 + (l.rope or 0))
    else
      local x = math.floor(l.x)
      local dir = l.flip and -1 or 1
      R(WOOD, x, l.y - 4, 2, l.post - l.y + 4)
      R(WOOD, dir > 0 and x or x - 5, l.y - 4, 7, 1)
      R(WOOD_D, x - 2, l.post - 1, 6, 1)
    end
    return
  end
  if l.hung then
    R(IRON_D, math.floor(l.x), l.y - 8 - (l.rope or 0), 1, 6 + (l.rope or 0)) -- the chain (a lamp hung from the rock has a longer one, up into it)
    local x, y = math.floor(l.x) - 2, l.y - 3
    R(IRON, x, y, 5, 1)
    R(IRON, x, y + 7, 5, 1)
    R(IRON_D, x, y + 1, 1, 6)
    R(IRON_D, x + 4, y + 1, 1, 6)
    R(IRON_L, x + 1, y - 1, 3, 1)
  else
    -- A post with an arm, the lantern hanging at its end
    local x = math.floor(l.x)
    local dir = l.flip and -1 or 1
    R(WOOD, x, l.y - 4, 2, l.post - l.y + 4)
    R(WOOD_L, x, l.y - 4, 1, l.post - l.y + 4)
    R(WOOD, dir > 0 and x or x - 5, l.y - 4, 7, 1)
    local lx = x + dir * 5 + (dir > 0 and 0 or 1)
    R(IRON_D, lx, l.y - 3, 1, 2)
    R(IRON, lx - 2, l.y - 1, 5, 1)
    R(IRON, lx - 2, l.y + 6, 5, 1)
    R(IRON_D, lx - 2, l.y, 1, 6)
    R(IRON_D, lx + 2, l.y, 1, 6)
    R(WOOD_D, x - 2, l.post - 1, 6, 1)
  end
end

-- Lamps can be shot (src.bullets asks minedecor.lampAt): every hit spills a
-- little oil (src.fluids), and the fourth, or a blast, breaks the lamp in a
-- puff of fire that lights what it spilt. A broken lamp gives no light.
local LAMP_HP, LAMP_OIL = 10, 26
local lampGrid = {} -- 64-px cells -> the lamps in them
local LCELL = 64
local function cellKey(cx, cy)
  return cy * 65536 + cx -- (a number: every round in flight asks every frame, and string keys were garbage)
end

local function lampBox(l)
  if l.hung then
    local x = math.floor(l.x) - 2
    return x, l.y - 3, x + 4, l.y + 4
  end
  local dir = l.flip and -1 or 1
  local lx = math.floor(l.x) + dir * 5 + (dir > 0 and 0 or 1)
  return lx - 2, l.y - 1, lx + 2, l.y + 6
end

function minedecor.clear()
  lampGrid = {}
end

-- Makes an area's lamps shootable (once its props are placed)
function minedecor.register(mine)
  for _, l in ipairs(mine.lamps) do
    l.hp, l.oil, l.broken = LAMP_HP, LAMP_OIL, false
    local x0, y0, x1, y1 = lampBox(l)
    local key = cellKey(math.floor((x0 + x1) / 2 / LCELL), math.floor((y0 + y1) / 2 / LCELL))
    lampGrid[key] = lampGrid[key] or {}
    table.insert(lampGrid[key], l)
  end
end

-- The unbroken lamp under a point, if any
function minedecor.lampAt(x, y)
  local cx, cy = math.floor(x / LCELL), math.floor(y / LCELL)
  for dy = -1, 1 do
    for dx = -1, 1 do
      local list = lampGrid[cellKey(cx + dx, cy + dy)]
      if list then
        for _, l in ipairs(list) do
          if not l.broken then
            local x0, y0, x1, y1 = lampBox(l)
            if x >= x0 and x <= x1 + 1 and y >= y0 and y <= y1 + 1 then
              return l
            end
          end
        end
      end
    end
  end
  return nil
end

local function breakLamp(l)
  l.broken = true
  local x0, y0, x1, y1 = lampBox(l)
  local x, y = (x0 + x1) / 2, (y0 + y1) / 2
  local fluids = require("src.fluids")
  local effects = require("src.effects")
  fluids.addOil(x, y + 2, l.oil)
  l.oil = 0
  fluids.fireBurst(x, y, 7)
  effects.explosion(x, y, 5)
  for _ = 1, 10 do
    effects.particle(x, y, (love.math.random() - 0.5) * 90, -20 - love.math.random() * 60, 0.6, { 0.75, 0.78, 0.85 }, 400, true)
  end
  require("src.audio").play("explosion", 0.35, 1.6)
end

-- A bullet (or anything else) hits a lamp for `damage`
function minedecor.hitLamp(l, damage)
  if l.broken then
    return
  end
  local x0, y0, x1, y1 = lampBox(l)
  local spill = math.min(l.oil, 3 + math.floor(damage / 3))
  if spill > 0 then
    l.oil = l.oil - require("src.fluids").addOil((x0 + x1) / 2, y1 + 1, spill)
  end
  l.hp = l.hp - damage
  if l.hp <= 0 then
    breakLamp(l)
  end
end

-- A blast breaks every lamp it reaches
function minedecor.explosion(x, y, radius)
  local cx, cy = math.floor(x / LCELL), math.floor(y / LCELL)
  local reach = math.ceil(radius / LCELL) + 1
  for dy = -reach, reach do
    for dx = -reach, reach do
      for _, l in ipairs(lampGrid[cellKey(cx + dx, cy + dy)] or {}) do
        if not l.broken and (l.x - x) ^ 2 + (l.y - y) ^ 2 < (radius + 4) ^ 2 then
          breakLamp(l)
        end
      end
    end
  end
end

local function lampFlame(l)
  if l.broken then
    return
  end
  local x, y
  if l.hung then
    x, y = math.floor(l.x) - 1, l.y - 2
  else
    local dir = l.flip and -1 or 1
    x = math.floor(l.x) + dir * 5 + (dir > 0 and 0 or 1) - 1
    y = l.y + 1
  end
  local f = flicker(l.x) > 0.3 and 1 or 0
  R({ 1, 0.7, 0.28 }, x, y + 1 - f, 3, 4 + f)
  R({ 1, 0.95, 0.72 }, x + 1, y + 2, 1, 2)
end

-- Skeletal remains -----------------------------------------------------------------

local function drawPick(x, y, flip, tilt)
  local dir = flip and -1 or 1
  for i = 0, 11 do
    R(WOOD, x + math.floor(i * tilt * dir), y - i - 1, 1, 1)
  end
  local hx = x + math.floor(11 * tilt * dir)
  R(IRON, hx - 3, y - 13, 7, 1)
  R(IRON_L, hx - 3, y - 13, 3, 1)
  R(IRON, hx - 4, y - 12, 1, 1)
  R(IRON, hx + 4, y - 12, 1, 1)
  R(IRON_D, hx - 1, y - 12, 3, 1)
end

local function drawSkeleton(s)
  local x, y, f = s.x, s.y, s.flip and -1 or 1
  local function r(c, dx, dy, w, h)
    -- dx grows along the way the skeleton faces
    local px = f > 0 and x + dx or x - dx - w + 1
    R(c, px, y + dy, w, h)
  end
  if s.kind == 1 then
    -- Lying on its back: skull, ribs, spine, pelvis, bent legs, an arm flung out
    r(BONE, 0, -3, 4, 3)
    r(DARK, 1, -2, 1, 1)
    r(DARK, 3, -2, 1, 1)
    r(BONE_D, 4, -2, 9, 1)
    for k = 0, 2 do
      r(BONE, 5 + k * 2, -4, 1, 3)
    end
    r(BONE, 12, -3, 3, 2)
    r(BONE, 15, -3, 4, 1)
    r(BONE, 18, -2, 1, 2)
    r(BONE, 15, -1, 5, 1)
    r(BONE_D, 4, -1, 6, 1)
  elseif s.kind == 2 then
    -- Sitting slumped against the wall, hard hat tilted, legs out in front
    r(BONE, 1, -13, 4, 4)
    r(DARK, 3, -12, 1, 1)
    r({ 0.62, 0.48, 0.16 }, 0, -14, 6, 2)
    r(BONE_D, 2, -9, 1, 5)
    for k = 0, 2 do
      r(BONE, 0, -9 + k * 2, 5, 1)
    end
    r(BONE, 0, -4, 5, 2)
    r(BONE, 5, -4, 6, 1)
    r(BONE, 10, -4, 1, 4)
    r(BONE_D, 5, -2, 5, 1)
    r(BONE_D, 4, -8, 3, 1)
    r(BONE_D, 6, -7, 1, 3)
  elseif s.kind == 3 then
    -- A little heap of skulls and crossed thigh bones
    r(BONE, 0, -3, 4, 3)
    r(DARK, 1, -2, 1, 1)
    r(BONE, 4, -2, 3, 2)
    r(DARK, 5, -1, 1, 1)
    r(BONE, 2, -6, 3, 3)
    r(DARK, 3, -5, 1, 1)
    r(BONE_D, -2, -1, 8, 1)
    r(BONE_D, 5, -2, 6, 1)
  else
    -- Scattered: a skull rolled aside, some ribs and a long bone
    r(BONE, 0, -3, 4, 3)
    r(DARK, 1, -2, 1, 1)
    r(BONE_D, 6, -1, 7, 1)
    r(BONE, 8, -2, 1, 2)
    r(BONE, 10, -2, 1, 2)
    r(BONE_D, 15, -1, 4, 1)
    r(BONE, 13, -1, 2, 1)
  end
  if s.pick then
    drawPick(s.x + f * 14, s.y, s.flip, 0.45)
  end
end

-- Entry points ------------------------------------------------------------------

local function inView(view, x0, x1, y0, y1, margin)
  return x1 > view.x - margin and x0 < view.x + view.w + margin and y1 > view.y - margin and y0 < view.y + view.h + margin
end

-- The scenery in view, behind the hunter (noSupports: without the timber frames and the lamps, for the shadow pass)
function minedecor.draw(mine, view, noSupports)
  for _, t in ipairs(mine.tracks) do
    local y = t.ys[t.x0]
    if inView(view, t.x0, t.x1, y - 12, y + 12, 8) then
      drawTrack(t, view)
    end
  end
  for _, s in ipairs(mine.supports) do
    if not noSupports and not s.gone and inView(view, s.x - 6, s.x + s.gap + 6, s.c, math.max(s.g1, s.g2), 8) then
      if bake.enabled.minedecor then
        -- (it changes only when it breaks or falls: its state is the version)
        local y0 = s.c - 8
        bake.piece(s, 0, s.state, s.x - 6, y0, s.gap + 14, math.max(s.g1, s.g2) + 6 - y0, function()
          drawSupport(s)
        end)
      else
        drawSupport(s)
      end
    end
  end
  for _, s in ipairs(mine.skeletons) do
    if not s.gone and inView(view, s.x - 20, s.x + 22, s.y - 16, s.y, 4) then
      if bake.enabled.minedecor then
        bake.piece(s, 0, 1, s.x - 26, s.y - 20, 54, 26, function()
          drawSkeleton(s)
        end)
      else
        drawSkeleton(s)
      end
    end
  end
  for _, p in ipairs(mine.picks) do
    if not p.gone and inView(view, p.x - 6, p.x + 6, p.y - 14, p.y, 4) then
      if bake.enabled.minedecor then
        bake.piece(p, 0, 1, p.x - 14, p.y - 16, 29, 18, function()
          drawPick(p.x, p.y, p.flip, p.tilt)
        end)
      else
        drawPick(p.x, p.y, p.flip, p.tilt)
      end
    end
  end
  for _, l in ipairs(mine.lamps) do
    if not noSupports and not l.gone and inView(view, l.x - 8, l.x + 8, l.y - 8, l.post or l.y + 8, 4) then
      drawLamp(l)
    end
  end
end

-- Held up by the ground ------------------------------------------------------------

-- Everything the mine stands on the floor (or hangs from the rock) is scenery, not terrain: when the
-- digging takes what it rests on away it is gone too, in a puff of splinters. (Run a few times a second
-- for what is near the hunter.)
local function held(world, x, y, dy)
  x, y = math.floor(x), math.floor(y)
  for o = 0, 2 do
    if world:isSolid(x, y + o * dy) then
      return true
    end
  end
  return false
end

local function splinterPuff(x, y, color, n)
  local effects = require("src.effects")
  for _ = 1, n or 6 do
    effects.particle(x + (love.math.random() - 0.5) * 8, y - love.math.random() * 4, (love.math.random() - 0.5) * 50, -10 - love.math.random() * 30, 0.5 + love.math.random() * 0.4, color, 320)
  end
end

local NEAR = 420 -- (only what is this close to the hunter is looked at)
local function near(px, py, x, y)
  return math.abs(x - px) < NEAR and math.abs(y - py) < NEAR
end

function minedecor.checkSupport(world, mine, px, py)
  for _, t in ipairs(mine.tracks) do
    if px > t.x0 - NEAR and px < t.x1 + NEAR and near(px, py, px, t.ys[t.x0]) then
      t.cut = t.cut or {}
      local changed
      for x = t.x0, t.x1 do
        local y = t.ys[x]
        if y and not t.cut[x] and not held(world, x, y, 1) then
          t.cut[x] = true
          changed = true
          if x % 3 == 0 then
            splinterPuff(x, y, WOOD, 2)
          end
        end
      end
      if changed then
        t.ver = (t.ver or 1) + 1
      end
    end
  end
  for _, s in ipairs(mine.supports) do
    if not s.gone and near(px, py, s.x, s.c) then
      local ok
      if s.state == "fallen" then
        ok = held(world, s.x + s.gap / 2, math.max(s.g1, s.g2), 1)
      else
        ok = held(world, s.x, s.g1, 1) and held(world, s.x + s.gap, s.g2, 1)
      end
      if not ok then
        s.gone = true
        splinterPuff(s.x + s.gap / 2, s.c + 6, WOOD, 10)
        splinterPuff(s.x, s.g1, WOOD_L, 4)
        splinterPuff(s.x + s.gap, s.g2, WOOD_L, 4)
      end
    end
  end
  for _, s in ipairs(mine.skeletons) do
    if not s.gone and near(px, py, s.x, s.y) and not held(world, s.x, s.y, 1) then
      s.gone = true
      splinterPuff(s.x, s.y, BONE, 8)
    end
  end
  for _, p in ipairs(mine.picks) do
    if not p.gone and near(px, py, p.x, p.y) and not held(world, p.x, p.y, 1) then
      p.gone = true
      splinterPuff(p.x, p.y - 4, WOOD, 3)
    end
  end
  for _, l in ipairs(mine.lamps) do
    if not l.gone and near(px, py, l.x, l.y) then
      local ok
      if l.support then
        ok = not l.support.gone
      elseif l.hung then
        ok = held(world, l.x, l.y - 11, -1) -- (the chain's top, in the rock)
      else
        ok = held(world, l.x, l.post, 1)
      end
      if not ok then
        if not l.broken then
          breakLamp(l)
        end
        l.gone = true
      end
    end
  end
end

-- The flames, after the lighting
function minedecor.drawEmissive(mine, view)
  for _, l in ipairs(mine.lamps) do
    if not l.gone and inView(view, l.x - 8, l.x + 8, l.y - 4, l.y + 8, 4) then
      lampFlame(l)
    end
  end
end

-- Every lantern lights its surroundings
function minedecor.addLights(lighting, mine, view)
  for i, l in ipairs(mine.lamps) do
    if not l.broken and inView(view, l.x, l.x, l.y, l.y, 110) then
      lighting.add(l.x, l.y + 2, 80, 1, 0.66, 0.32, 0.62 + flicker(i) * 0.05)
    end
  end
end

return minedecor
