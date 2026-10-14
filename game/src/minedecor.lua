-- Scenery of the Catacombs' old mine (design doc §7b), drawn behind the hunter
-- from the lists cavegen makes (info.mine): rail tracks, timber shoring that
-- stands, is half fallen or has collapsed, hanging oil lanterns and lamp posts,
-- skeletal remains and pickaxes. The flames are drawn again after the
-- lighting, and every lantern gives light.
local minedecor = {}

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

local function drawTrack(t)
  for x = t.x0, t.x1 do
    local y = t.ys[x]
    if y then
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
  -- A buffer stop at the far end
  local y = t.ys[t.x1]
  R(WOOD_D, t.x1, y - 7, 2, 7)
  R(WOOD, t.x1 - 2, y - 7, 5, 2)
  R(WOOD_L, t.x1 - 2, y - 7, 5, 1)
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
  if l.hung then
    R(IRON_D, math.floor(l.x), l.y - 8, 1, 6) -- the chain
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

local function lampFlame(l)
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

-- The scenery in view, behind the hunter
function minedecor.draw(mine, view)
  for _, t in ipairs(mine.tracks) do
    local y = t.ys[t.x0]
    if inView(view, t.x0, t.x1, y - 12, y + 12, 8) then
      drawTrack(t)
    end
  end
  for _, s in ipairs(mine.supports) do
    if inView(view, s.x - 6, s.x + s.gap + 6, s.c, math.max(s.g1, s.g2), 8) then
      drawSupport(s)
    end
  end
  for _, s in ipairs(mine.skeletons) do
    if inView(view, s.x - 20, s.x + 22, s.y - 16, s.y, 4) then
      drawSkeleton(s)
    end
  end
  for _, p in ipairs(mine.picks) do
    if inView(view, p.x - 6, p.x + 6, p.y - 14, p.y, 4) then
      drawPick(p.x, p.y, p.flip, p.tilt)
    end
  end
  for _, l in ipairs(mine.lamps) do
    if inView(view, l.x - 8, l.x + 8, l.y - 8, l.post or l.y + 8, 4) then
      drawLamp(l)
    end
  end
end

-- The flames, after the lighting
function minedecor.drawEmissive(mine, view)
  for _, l in ipairs(mine.lamps) do
    if inView(view, l.x - 8, l.x + 8, l.y - 4, l.y + 8, 4) then
      lampFlame(l)
    end
  end
end

-- Every lantern lights its surroundings
function minedecor.addLights(lighting, mine, view)
  for i, l in ipairs(mine.lamps) do
    if inView(view, l.x, l.x, l.y, l.y, 110) then
      lighting.add(l.x, l.y + 2, 96, 1, 0.66, 0.32, 0.95 + flicker(i) * 0.07)
    end
  end
end

return minedecor
